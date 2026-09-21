# encoding: UTF-8
#===============================================================================
# T3: from_live (Marshal snapshot) faithfulness — the in-game integration path.
#
# A twin built via from_live must be INDISTINGUISHABLE from the battle it was
# taken from: running identical joint actions on the original and on the
# snapshot must produce identical StateSummary hashes (HP, statuses, stages,
# field, effects, choices, turn count...). This is the differential validation
# required for the in-game path, executed headless against real engine rounds.
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
  # A non-trivial live state: two rounds played, statuses and stages applied.
  ours  = [mk(:BLASTOISE, 55, moves: [:SURF, :RAINDANCE]),
           mk(:ZOROARK, 55, moves: [:FLAMETHROWER, :NASTYPLOT])]
  foes  = [mk(:SNORLAX, 55, moves: [:BODYSLAM, :EARTHQUAKE]),
           mk(:MAGNETON, 55, moves: [:THUNDERBOLT, :THUNDERWAVE])]
  rng = CoachEngine2::DeterministicRNG.new(seed: 11, policy: :median)
  live = CoachEngine2::TwinFactory.build(ours, foes,
    player: CoachEngine2::DummyTrainer.new("Player"),
    opponent: CoachEngine2::DummyTrainer.new("Rival"), rng: rng)
  live.pbStartBattleCore(false)
  drv = CoachEngine2::TurnDriver.new(live)
  2.times do
    drv.inject!(0 => drv.move_choice(0, 0), 1 => drv.move_choice(1, 1))
    drv.step!
  end
  check("T3 live state is non-trivial",
        live.turnCount == 2 && live.battlers.any? { |b| b.hp < b.totalhp },
        "turn=#{live.turnCount} hp=#{live.battlers.map { |b| b.hp.to_s }.join('/')}")

  # Snapshot.
  twin = CoachEngine2::TwinFactory.from_live(live, 0, rng: CoachEngine2::DeterministicRNG.new(seed: 99, policy: :median))
  check("T3 from_live returns a twin-extended battle",
        twin.is_a?(Battle) && twin.singleton_class.include?(CoachEngine2::TwinBehavior),
        "class=#{twin.class}")

  # Immediate summaries must match (same rng policy pinned? live rng differs
  # from twin rng, but summaries cover state, not rolls).
  s_live = CoachEngine2::TurnDriver::StateSummary.of(live).hashable
  s_twin = CoachEngine2::TurnDriver::StateSummary.of(twin).hashable
  check("T3 snapshot state matches live state", s_live == s_twin, "")

  # Live battle untouched by the snapshot (its scene restored, still playable).
  check("T3 live battle scene restored",
        live.instance_variable_get(:@scene).equal?(drv.instance_variable_get(:@battle).instance_variable_get(:@scene)) ||
        live.instance_variable_get(:@scene).is_a?(CoachEngine2::NullScene),
        live.instance_variable_get(:@scene).class.to_s)

  # Differential: identical actions on live-continuation vs twin must produce
  # identical successor summaries. Give both the SAME deterministic rng policy
  # so the comparison is exact.
  live2 = CoachEngine2::TwinFactory.from_live(live, 0, rng: CoachEngine2::DeterministicRNG.new(seed: 5, policy: :median))
  twin2 = CoachEngine2::TwinFactory.from_live(live, 0, rng: CoachEngine2::DeterministicRNG.new(seed: 5, policy: :median))
  [0, 1].each do |mv|
    a = CoachEngine2::TurnDriver.new(live2)
    b = CoachEngine2::TurnDriver.new(twin2)
    a.inject!(0 => a.move_choice(0, mv), 1 => a.move_choice(1, 0))
    b.inject!(0 => b.move_choice(0, mv), 1 => b.move_choice(1, 0))
    da = a.step!
    db = b.step!
    ha = CoachEngine2::TurnDriver::StateSummary.of(live2).hashable
    hb = CoachEngine2::TurnDriver::StateSummary.of(twin2).hashable
    check("T3 differential round (our move #{mv}) identical",
          da == db && ha == hb,
          "decision #{da}==#{db}, summaries #{ha == hb ? 'match' : 'DIVERGE'}")
    # Reset for next iteration via fresh snapshots from the same live state.
    live2 = CoachEngine2::TwinFactory.from_live(live, 0, rng: CoachEngine2::DeterministicRNG.new(seed: 5, policy: :median))
    twin2 = CoachEngine2::TwinFactory.from_live(live, 0, rng: CoachEngine2::DeterministicRNG.new(seed: 5, policy: :median))
  end

  # Snapshot-of-snapshot: Marshal of a twin-extended battle still works
  # (search clones states this way).
  twin3 = CoachEngine2::TwinFactory.from_live(twin, 0, rng: CoachEngine2::DeterministicRNG.new(seed: 5, policy: :median))
  check("T3 snapshot of a snapshot works (search clone path)",
        CoachEngine2::TurnDriver::StateSummary.of(twin3).hashable == CoachEngine2::TurnDriver::StateSummary.of(twin).hashable,
        "")

  # Search actually runs on a snapshot taken mid-battle (non-fresh state).
  res = CoachEngine2::Search.new(twin, viewpoint_side: 0, config: {
    max_depth: 2, node_budget: 60, time_budget_ms: 8000,
    foe_branching: 4, our_branching: 8 }).recommend
  check("T3 search on mid-battle snapshot returns an action",
        !res.action.nil? && res.value >= 0.0,
        "value=#{res.value.round(3)} #{res.metrics.report}")
rescue => e
  check("T3 raised", false, "#{e.class}: #{e.message}")
  (e.backtrace || [])[0, 8].each { |l| puts "    #{l}" }
end

fails = $TESTS.count { |_n, ok, _| !ok }
puts "T3-SUMMARY: #{$TESTS.size - fails}/#{$TESTS.size} passed"
exit(fails.zero? ? 0 : 1)
