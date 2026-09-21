# encoding: UTF-8
#===============================================================================
# Benchmark: Engine 2.0 search cost in THIS environment (Ruby 3.3 wasm32-wasi
# under wasmtime). In-game performance on desktop/JoiPlay native CPUs will
# differ; these numbers are the honest reference for the environment that was
# actually available, plus per-round unit costs that transfer approximately.
#===============================================================================
load_engine2 rescue nil

def mk(species, level, moves: nil, ability: nil)
  srand(1234)
  p = Pokemon.new(species, level, nil, false)
  p.ability = ability if ability
  p.instance_variable_set(:@moves, moves.map { |m| Pokemon::Move.new(m) }) if moves
  p
end

def bench(label, ours, foes, cfg)
  rng = CoachEngine2::DeterministicRNG.new(seed: 7, policy: :median)
  b = CoachEngine2::TwinFactory.build(ours, foes,
    player: CoachEngine2::DummyTrainer.new("P"),
    opponent: CoachEngine2::DummyTrainer.new("R"), rng: rng)
  b.pbStartBattleCore(false)
  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  res = CoachEngine2::Search.new(b, viewpoint_side: 0, config: cfg).recommend
  ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000
  m = res.metrics
  rps = m.rounds_run.zero? ? 0.0 : m.rounds_run / (ms / 1000.0)
  puts format("%-34s best=%-22s W=%-5s nodes=%-4d rounds=%-4d depth=%d ms=%-6.0f rounds/s=%-5.1f tt_hit=%d tt_store=%d",
    label, (res.pv.first || "?")[0, 22], res.value.round(2).to_s,
    m.nodes, m.rounds_run, m.max_depth_reached, ms, rps, m.tt_hits, m.tt_stores)
  [ms, m]
end

puts "=== Engine 2.0 search benchmarks (wasm32-wasi, wasmtime) ==="
puts ""

# Scenario A: trivial position (free KO) — must be cheap and find the win.
bench("A trivial (Lv100 vs Lv3, desktop)",
  [mk(:GLIMMORA, 100, moves: [:POWERGEM, :EARTHPOWER])],
  [mk(:MAREEP, 3, moves: [:TACKLE])],
  CoachEngine2::CONFIG[:budgets][:desktop].merge(foe_model: :adversarial))

# Scenario B: even 1v1 midgame.
bench("B even 1v1 (desktop)",
  [mk(:BLASTOISE, 55, moves: [:SURF, :RAINDANCE, :ICEBEAM])],
  [mk(:SNORLAX, 55, moves: [:BODYSLAM, :EARTHQUAKE, :REST])],
  CoachEngine2::CONFIG[:budgets][:desktop].merge(foe_model: :adversarial))

# Scenario C: 2-mon side with switching (bigger action space).
bench("C 2-mon side w/ switches (desktop)",
  [mk(:BLASTOISE, 55, moves: [:SURF, :ICEBEAM]),
   mk(:ZOROARK, 55, moves: [:FLAMETHROWER, :NASTYPLOT])],
  [mk(:SNORLAX, 55, moves: [:BODYSLAM, :EARTHQUAKE]),
   mk(:MAGNETON, 55, moves: [:THUNDERBOLT, :THUNDERWAVE])],
  CoachEngine2::CONFIG[:budgets][:desktop].merge(foe_model: :adversarial))

# Scenario D: same as C but game_ai foe model (single foe action per node).
bench("D 2-mon side, foe=game_ai (desktop)",
  [mk(:BLASTOISE, 55, moves: [:SURF, :ICEBEAM]),
   mk(:ZOROARK, 55, moves: [:FLAMETHROWER, :NASTYPLOT])],
  [mk(:SNORLAX, 55, moves: [:BODYSLAM, :EARTHQUAKE]),
   mk(:MAGNETON, 55, moves: [:THUNDERBOLT, :THUNDERWAVE])],
  CoachEngine2::CONFIG[:budgets][:desktop].merge(foe_model: :game_ai))

# Scenario E: JoiPlay budget on the big scenario.
bench("E 2-mon side (joiplay)",
  [mk(:BLASTOISE, 55, moves: [:SURF, :ICEBEAM]),
   mk(:ZOROARK, 55, moves: [:FLAMETHROWER, :NASTYPLOT])],
  [mk(:SNORLAX, 55, moves: [:BODYSLAM, :EARTHQUAKE]),
   mk(:MAGNETON, 55, moves: [:THUNDERBOLT, :THUNDERWAVE])],
  CoachEngine2::CONFIG[:budgets][:joiplay].merge(foe_model: :adversarial))

# Scenario F: endgame solving — 1v1 both low HP, deeper budget.
bench("F low-HP endgame, depth 4 (desktop)",
  [mk(:BLASTOISE, 55, moves: [:SURF, :ICEBEAM])],
  [mk(:SNORLAX, 55, moves: [:BODYSLAM])],
  { max_depth: 4, node_budget: 300, time_budget_ms: 3000,
    foe_branching: 5, our_branching: 14, foe_model: :adversarial })

# Unit cost: raw round execution (Marshal clone + full pbAttackPhase +
# pbEndOfRoundPhase) without search overhead.
rng = CoachEngine2::DeterministicRNG.new(seed: 7, policy: :median)
b = CoachEngine2::TwinFactory.build(
  [mk(:BLASTOISE, 55, moves: [:SURF, :ICEBEAM]),
   mk(:ZOROARK, 55, moves: [:FLAMETHROWER])],
  [mk(:SNORLAX, 55, moves: [:BODYSLAM, :EARTHQUAKE]),
   mk(:MAGNETON, 55, moves: [:THUNDERBOLT])],
  player: CoachEngine2::DummyTrainer.new("P"),
  opponent: CoachEngine2::DummyTrainer.new("R"), rng: rng)
b.pbStartBattleCore(false)
t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
n = 0
30.times do
  c = Marshal.load(Marshal.dump(b))
  d = CoachEngine2::TurnDriver.new(c)
  d.inject!(0 => d.move_choice(0, 0), 1 => d.move_choice(1, 0))
  d.step!
  n += 1
  break if c.decision != 0
end
ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000
puts format("%-34s rounds=%d ms=%.0f ms/round=%.2f (clone+full round)",
  "G raw round unit cost", n, ms, ms / [n, 1].max)
puts ""
puts "All numbers measured in this sandbox (Ruby 3.3.3 wasm32-wasi, wasmtime"
puts "48). Native desktop CPU expected several times faster; JoiPlay variable."
