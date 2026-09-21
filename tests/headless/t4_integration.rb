# encoding: UTF-8
#===============================================================================
# T4: in-game integration layer (headless validation of everything except
# actual RGSS sprite drawing, which this environment cannot reproduce).
#===============================================================================
$TESTS = []

def check(name, cond, extra = "")
  $TESTS.push([name, !!cond, extra])
  puts "[#{cond ? 'PASS' : 'FAIL'}] #{name}#{extra.empty? ? '' : " — #{extra}"}"
end

def mk(species, level, moves: nil, ability: nil)
  srand(1234)
  p = Pokemon.new(species, level, nil, false)
  p.ability = ability if ability
  p.instance_variable_set(:@moves, moves.map { |m| Pokemon::Move.new(m) }) if moves
  p
end

load_engine2 rescue nil

begin
  ours = [mk(:BLASTOISE, 55, moves: [:SURF, :RAINDANCE]),
          mk(:ZOROARK, 55, moves: [:FLAMETHROWER, :NASTYPLOT])]
  foes = [mk(:SNORLAX, 55, moves: [:BODYSLAM, :EARTHQUAKE])]
  rng = CoachEngine2::DeterministicRNG.new(seed: 3, policy: :median)
  battle = CoachEngine2::TwinFactory.build(ours, foes,
    player: CoachEngine2::DummyTrainer.new("Player"),
    opponent: CoachEngine2::DummyTrainer.new("Rival"), rng: rng)
  battle.pbStartBattleCore(false)

  rec = battle.competitive_coach_recommendation(0)
  check("T4 recommendation returns a HUD hash",
        rec.is_a?(Hash) && rec[:best].is_a?(String) && !rec[:best].empty?,
        "best=#{rec && rec[:best].inspect} alt=#{rec && rec[:alternative].inspect} dots=#{rec && rec[:confidence_dots]}")
  check("T4 HUD contract fields present",
        rec.is_a?(Hash) && rec.key?(:best) && rec.key?(:alternative) && rec.key?(:confidence_dots),
        "")

  # Caching: same turn/HP -> same object, no recompute.
  rec2 = battle.competitive_coach_recommendation(0)
  check("T4 recommendation cached within a turn", rec2.equal?(rec), "")

  # Disable switch: falls back to the captured pre-2.0 method (not loaded in
  # this headless boot -> nil) WITHOUT raising.
  CoachEngine2.enabled = false
  rec3 = nil
  begin
    rec3 = battle.competitive_coach_recommendation(0)
  rescue => e
    check("T4 disable switch", false, "#{e.class}: #{e.message}")
  end
  check("T4 disable switch falls back cleanly",
        rec3.nil? || rec3.is_a?(Hash),
        "returned #{rec3.class}")
  CoachEngine2.enabled = true

  # A played round invalidates the cache and yields a fresh recommendation.
  drv = CoachEngine2::TurnDriver.new(battle)
  drv.inject!(0 => drv.move_choice(0, 0), 1 => drv.move_choice(1, 0))
  drv.step!
  rec4 = battle.competitive_coach_recommendation(0)
  check("T4 cache invalidated after a round",
        rec4.is_a?(Hash) && !rec4.equal?(rec),
        "best=#{rec4 && rec4[:best].inspect}")

  # Foe-side battler: not our side -> no coaching (nil), no crash.
  rec5 = battle.competitive_coach_recommendation(1)
  check("T4 foe side not coached", rec5.nil? || rec5.is_a?(Hash), "class=#{rec5.class}")

  # Budget profile plumbing.
  check("T4 profiles expose budgets",
        CoachEngine2::CONFIG[:budgets][:desktop][:node_budget] > 0 &&
        CoachEngine2::CONFIG[:budgets][:joiplay][:node_budget] > 0 &&
        CoachEngine2::CONFIG[:budgets][:joiplay][:node_budget] < CoachEngine2::CONFIG[:budgets][:desktop][:node_budget],
        "desktop=#{CoachEngine2::CONFIG[:budgets][:desktop][:node_budget]} joiplay=#{CoachEngine2::CONFIG[:budgets][:joiplay][:node_budget]}")

  # Isolation: the integration defines nothing outside Battle + CoachEngine2.
  src = Dir.glob("/work/engine2/*.rb").sort.map { |f| File.read(f) }.join
  forbidden = src.scan(/^\s*(class|module)\s+(Input|Graphics|Game_Map|Game_Player|Game_Event|Game_Temp|SpriteSet|Scene_Map|PokemonBag|Window)\b/)
  aliases = src.scan(/^\s*alias(?:_method)?\s+(\w+)/).flatten
  check("T4 integration adds no foreign classes/aliases",
        forbidden.empty? && aliases.empty?, "#{forbidden.inspect} #{aliases.inspect}")
rescue => e
  check("T4 raised", false, "#{e.class}: #{e.message}")
  (e.backtrace || [])[0, 8].each { |l| puts "    #{l}" }
end

fails = $TESTS.count { |_n, ok, _| !ok }
puts "T4-SUMMARY: #{$TESTS.size - fails}/#{$TESTS.size} passed"
exit(fails.zero? ? 0 : 1)
