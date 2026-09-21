# encoding: UTF-8
# Loads the Engine 2.0 section EXACTLY AS SHIPPED inside game/Scripts.rxdata
# (extracted from the built file, not from engine2/ sources) and runs a smoke
# recommendation. This validates the deliverable artifact end-to-end.
SCRIPTS_RXDATA = "/work/game/Scripts.rxdata"

# Minimal Marshal reader for the Scripts.rxdata structure (no zlib in the
# wasm stdlib? there is: require 'zlib' works). Parse: top-level array of
# [id, name(ivar str), code(deflated)].
require "zlib"
data = File.binread(SCRIPTS_RXDATA)
raise "bad version" unless data[0, 2] == "\x04\x08".b

class RxReader
  def initialize(data)
    @d = data.b
    @i = 2
    @symbols = []
  end
  def byte; b = @d.getbyte(@i); @i += 1; b; end
  def long
    b = byte
    return 0 if b.zero?
    if b >= 1 && b <= 4
      v = 0
      b.times { v |= (byte << (8 * _1)) }
      return v
    end
    return b - 5 if b >= 5 && b < 128
    if b >= 0xfc
      n = 0x100 - b
      v = 0
      n.times { v |= (byte << (8 * _1)) }
      return -v
    end
    raise "bad long byte #{b}"
  end
  def parse
    b = byte
    case b
    when 0x5b then Array.new(long) { parse }
    when 0x49 then parse_ivar
    when 0x22 then len = long; s = @d[@i, len]; @i += len; s
    when 0x3a then len = long; s = @d[@i, len]; @i += len; @symbols << s; s
    when 0x3b then @symbols[long]
    when 0x69 then long
    when 0x54 then true
    when 0x46 then false
    when 0x30 then nil
    else raise "unsupported type byte #{b} at #{@i - 1}"
    end
  end
  def parse_ivar
    obj = parse
    n = long
    n.times { parse; parse }
    obj
  end
end

entries = RxReader.new(data).parse
puts "rxdata entries: #{entries.length}"
raise "expected 617" unless entries.length == 617
newest = entries.last
sid, name, code = newest
puts "last section: id=#{sid} name=#{name.inspect} bytes=#{code.bytesize}"
src = Zlib::Inflate.inflate(code).force_encoding("UTF-8")
puts "inflated: #{src.length} chars"

# The engine2 module must not exist yet.
raise "leak: CoachEngine2 already defined" if defined?(CoachEngine2)

# Evaluate the shipped section as the game would.
eval(src, TOPLEVEL_BINDING, "Scripts.rxdata[616]")

raise "CoachEngine2 not defined by shipped section" unless defined?(CoachEngine2)
puts "shipped section evaluated: CoachEngine2 defined, Battle#competitive_coach_recommendation #{Battle.method_defined?(:competitive_coach_recommendation) ? 'present' : 'MISSING'}"

# Smoke: build a battle and ask the shipped layer for a recommendation.
srand(1234)
glimmora = Pokemon.new(:GLIMMORA, 100, nil, false)
glimmora.instance_variable_set(:@moves, [Pokemon::Move.new(:POWERGEM), Pokemon::Move.new(:EARTHPOWER)])
zoroark = Pokemon.new(:ZOROARK, 55, nil, false)
zoroark.instance_variable_set(:@moves, [Pokemon::Move.new(:FLAMETHROWER)])
srand(1235)
mareep = Pokemon.new(:MAREEP, 3, nil, false)
mareep.instance_variable_set(:@moves, [Pokemon::Move.new(:TACKLE)])
rng = CoachEngine2::DeterministicRNG.new(seed: 7, policy: :median)
battle = CoachEngine2::TwinFactory.build([glimmora, zoroark], [mareep],
  player: CoachEngine2::DummyTrainer.new("Player"),
  opponent: CoachEngine2::DummyTrainer.new("Rival"), rng: rng)
battle.pbStartBattleCore(false)
rec = battle.competitive_coach_recommendation(0)
raise "no recommendation from shipped section" if rec.nil? || rec[:best].nil?
puts "shipped-layer recommendation: best=#{rec[:best].inspect} alt=#{rec[:alternative].inspect} dots=#{rec[:confidence_dots]}"
puts "RXDATA-SMOKE: PASS"
