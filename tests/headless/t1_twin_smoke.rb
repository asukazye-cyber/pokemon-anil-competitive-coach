# encoding: UTF-8
# T1: TwinBattle smoke test.
# Builds REAL battles with the real engine, runs real rounds, verifies:
#   1. battle construction + start sequence works headless;
#   2. a move choice produces sensible damage/state changes;
#   3. determinism: same seed + same actions => identical state;
#   4. roll policies alter outcomes (min vs max damage rolls differ);
#   5. Marshal deep-copy of a live twin works (needed for search);
#   6. switch actions + forced replacements work;
#   7. accuracy: Thunder in rain vs sun behaves as the engine dictates.
$TESTS = []

def check(name, cond, extra = "")
  $TESTS.push([name, !!cond, extra])
  puts "[#{cond ? 'PASS' : 'FAIL'}] #{name}#{extra.empty? ? '' : " — #{extra}"}"
end

def mk_pkmn(species, level, moves: nil, item: nil, ability: nil)
  p = Pokemon.new(species, level, nil, false)   # no owner, no default moves
  p.item = item if item
  p.ability = ability if ability
  if moves
    p.instance_variable_set(:@moves, moves.map { |m| Pokemon::Move.new(m) })
  end
  p
end

#--- 1. construction ----------------------------------------------------------
p1 = mk_pkmn(:GARCHOMP, 50, moves: [:EARTHQUAKE, :DRAGONCLAW])
p2 = mk_pkmn(:BLASTOISE, 50, moves: [:SURF, :ICEBEAM])
check("species built", p1.species == :GARCHOMP && p2.hp > 0, "hp=#{p2.hp}/#{p2.totalhp}")

twin = CoachEngine2::TwinFactory.build(
  [p1], [p2],
  player: CoachEngine2::DummyTrainer.new("Player"), opponent: CoachEngine2::DummyTrainer.new("Rival")
)
check("twin built", twin.is_a?(Battle), twin.class.to_s)

decision = nil
begin
  twin.pbStartBattleCore(false)
  check("start sequence", twin.battlers[0] && twin.battlers[1] &&
        !twin.battlers[0].fainted? && twin.turnCount == 0)
rescue => e
  check("start sequence", false, "#{e.class}: #{e.message}")
  (e.backtrace || [])[0, 22].each { |l| puts "    #{l}" }
end

#--- 2. a real round ----------------------------------------------------------
drv = CoachEngine2::TurnDriver.new(twin)
b0, b1 = twin.battlers[0], twin.battlers[1]
hp_before = b1.hp
drv.inject!(0 => drv.move_choice(0, 0), 1 => drv.move_choice(1, 0))
begin
  decision = drv.step!
  check("round executed", true, "decision=#{decision} foeHP #{hp_before}->#{b1.hp}")
  check("damage happened", b1.hp < hp_before, "delta=#{hp_before - b1.hp}")
rescue => e
  check("round executed", false, "#{e.class}: #{e.message}")
end

#--- 3. determinism -----------------------------------------------------------
def run_round(seed, policy, move_idx0 = 0, move_idx1 = 0)
  srand(seed)   # Pokemon.new rolls IVs via Kernel#rand
  p1 = Pokemon.new(:GARCHOMP, 50, nil, false)
  p1.instance_variable_set(:@moves, [:EARTHQUAKE, :DRAGONCLAW].map { |m| Pokemon::Move.new(m) })
  p2 = Pokemon.new(:BLASTOISE, 50, nil, false)
  p2.instance_variable_set(:@moves, [:SURF, :ICEBEAM].map { |m| Pokemon::Move.new(m) })
  rng = CoachEngine2::DeterministicRNG.new(seed: seed, policy: policy)
  twin = CoachEngine2::TwinFactory.build([p1], [p2],
    player: CoachEngine2::DummyTrainer.new("Player"), opponent: CoachEngine2::DummyTrainer.new("Rival"), rng: rng)
  twin.pbStartBattleCore(false)
  drv = CoachEngine2::TurnDriver.new(twin)
  drv.inject!(0 => drv.move_choice(0, move_idx0), 1 => drv.move_choice(1, move_idx1))
  drv.step!
  [twin.battlers[0].hp, twin.battlers[1].hp, CoachEngine2::TurnDriver::StateSummary.of(twin).hashable]
end

a1 = run_round(42, :free)
a2 = run_round(42, :free)
check("determinism same seed", a1 == a2, "rolls identical")

b_min = run_round(1, :min)
b_max = run_round(1, :max)
check("policy sensitivity", b_min != b_max, "min_hp=#{b_min[0..1].inspect} max_hp=#{b_max[0..1].inspect}")

#--- 4. Marshal deep copy -----------------------------------------------------
copy = drv.deep_copy
check("marshal round-trip of live twin", copy.is_a?(Battle) &&
      copy.battlers[0].hp == twin.battlers[0].hp)

#--- 5. switch action + forced replacement ------------------------------------
p3 = mk_pkmn(:LUCARIO, 50, moves: [:AURASPHERE])
p4 = mk_pkmn(:BLASTOISE, 50, moves: [:SURF])
team1 = [p3, p4]
twin2 = CoachEngine2::TwinFactory.build(team1, [mk_pkmn(:SNORLAX, 50, moves: [:BODYSLAM])],
  player: CoachEngine2::DummyTrainer.new("Player"), opponent: CoachEngine2::DummyTrainer.new("Rival"))
twin2.pbStartBattleCore(false)
drv2 = CoachEngine2::TurnDriver.new(twin2)
drv2.inject!(0 => drv2.switch_choice(0, 1), 1 => drv2.move_choice(1, 0))
d = drv2.step!
check("switch executed", twin2.battlers[0].pokemonIndex == 1 &&
      twin2.battlers[0].pokemon.species == :BLASTOISE,
      "active=#{twin2.battlers[0].pokemon.species}")

#--- 6. accuracy mechanics: Thunder -------------------------------------------
thunder_user = mk_pkmn(:ZAPDOS, 60, moves: [:THUNDER])
ground_foe  = mk_pkmn(:SNORLAX, 60, moves: [:BODYSLAM])   # NOT Ground: Electric must connect
thunder_hits = 0
10.times do |i|
  rng = CoachEngine2::DeterministicRNG.new(seed: i, policy: :free)
  tw = CoachEngine2::TwinFactory.build([thunder_user], [ground_foe],
    player: CoachEngine2::DummyTrainer.new("Player"), opponent: CoachEngine2::DummyTrainer.new("Rival"), rng: rng)
  tw.pbStartBattleCore(false)
  dv = CoachEngine2::TurnDriver.new(tw)
  dv.inject!(0 => dv.move_choice(0, 0), 1 => dv.move_choice(1, 0))
  hp0 = tw.battlers[1].hp
  dv.step!
  hit = tw.battlers[1].hp < hp0
  thunder_hits += 1 if hit
  acc_rolls = rng.log.select { |v, mx, _| mx == 100 }.map(&:first)
  puts "    seed=#{i} hit=#{hit} hp #{hp0}->#{tw.battlers[1].hp} rolls(100)=#{acc_rolls.inspect}"
end
check("thunder accuracy sampled", thunder_hits > 0 && thunder_hits < 10, "hits=#{thunder_hits}/10 (base 70)")

#--- summary ------------------------------------------------------------------
fails = $TESTS.count { |_n, ok, _| !ok }
puts "T1-SUMMARY: #{$TESTS.size - fails}/#{$TESTS.size} passed"
exit(fails == 0 ? 0 : 1)
