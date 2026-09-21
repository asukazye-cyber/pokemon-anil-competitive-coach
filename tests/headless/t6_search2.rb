# encoding: UTF-8
#===============================================================================
# T6: milestone suite — exact chance enumeration, adaptive search with
# ε-bounded pruning, replacement enumeration, and opponent beliefs.
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

def mk_battle(ours, foes, seed: 7)
  rng = CoachEngine2::DeterministicRNG.new(seed: seed, policy: :median)
  b = CoachEngine2::TwinFactory.build(ours, foes,
    player: CoachEngine2::DummyTrainer.new("Player"),
    opponent: CoachEngine2::DummyTrainer.new("Rival"), rng: rng)
  b.pbStartBattleCore(false)
  b
end

def cfg(overrides = {})
  { max_depth: 2, node_budget: 150, time_budget_ms: 12000,
    foe_branching: 4, our_branching: 10, chance: :on }.merge(overrides)
end

load_engine2 rescue nil

begin
  #===========================================================================
  # MILESTONE 1 — exact chance enumeration
  #===========================================================================
  # 1a. Thunder (base 70) vs Snorlax: a miss branch with p ~= 0.30 and
  #     hit branches summing to ~0.70; total exactly 1.
  b = mk_battle([mk(:ELECTIVIRE, 60, moves: [:THUNDER])],
                [mk(:SNORLAX, 60, moves: [:BODYSLAM])])
  drv = CoachEngine2::TurnDriver.new(b)
  outs = CoachEngine2::ChanceEnumerator.enumerate(
    b, ours: { 0 => drv.move_choice(0, 0) }, foes: { 1 => drv.move_choice(1, 0) },
    granularity: :coarse, metrics: nil)
  total = outs.sum(&:prob)
  miss = outs.select { |o| o.tags.include?(:miss) }
  miss_p = miss.sum(&:prob)
  hit_p = 1.0 - miss_p
  check("T6 Thunder outcomes sum to 1", (total - 1.0).abs < 1e-6, "total=#{total}")
  check("T6 Thunder miss probability measured ~0.30 (base 70)",
        miss.any? && (miss_p - 0.30).abs < 0.011,
        "miss_p=#{miss_p.round(4)} outcomes=#{outs.map { |o| [o.tags, o.prob.round(3)] }.inspect}")

  # 1b. No Guard: no accuracy branch at all — single hit, p = 1.
  b = mk_battle([mk(:ELECTIVIRE, 60, moves: [:THUNDER], ability: :NOGUARD)],
                [mk(:SNORLAX, 60, moves: [:BODYSLAM])])
  drv = CoachEngine2::TurnDriver.new(b)
  outs = CoachEngine2::ChanceEnumerator.enumerate(
    b, ours: { 0 => drv.move_choice(0, 0) }, foes: { 1 => drv.move_choice(1, 0) },
    granularity: :coarse, metrics: nil)
  check("T6 No Guard Thunder: no miss branch, deterministic p=1",
        outs.none? { |o| o.tags.include?(:miss) } && outs.size >= 1 &&
        (outs.sum(&:prob) - 1.0).abs < 1e-6,
        "outcomes=#{outs.map { |o| [o.tags, o.prob.round(3)] }.inspect}")

  # 1c. 100% accuracy move: damage bands only (no miss branch).
  b = mk_battle([mk(:SNORLAX, 60, moves: [:BODYSLAM])],
                [mk(:SNORLAX, 60, moves: [:BODYSLAM])])
  drv = CoachEngine2::TurnDriver.new(b)
  outs = CoachEngine2::ChanceEnumerator.enumerate(
    b, ours: { 0 => drv.move_choice(0, 0) }, foes: { 1 => drv.move_choice(1, 0) },
    granularity: :coarse, metrics: nil)
  check("T6 100% move has no miss branch",
        outs.none? { |o| o.tags.include?(:miss) },
        "outcomes=#{outs.map { |o| [o.tags, o.prob.round(3)] }.inspect}")
  dmg_probs = outs.map(&:prob).sort
  check("T6 damage bands carry 1/16, 1/16, 14/16",
        outs.size == 3 && (dmg_probs[0] - 1.0 / 16).abs < 1e-6 &&
        (dmg_probs[1] - 1.0 / 16).abs < 1e-6 && (dmg_probs[2] - 14.0 / 16).abs < 1e-6,
        "probs=#{dmg_probs.inspect}")

  # 1d. :fine granularity adds exact crit branching (1/24 Gen9 base rate).
  outs = CoachEngine2::ChanceEnumerator.enumerate(
    b, ours: { 0 => CoachEngine2::TurnDriver.new(b).move_choice(0, 0) },
    foes: { 1 => CoachEngine2::TurnDriver.new(b).move_choice(1, 0) },
    granularity: :fine, max_outcomes: 40, metrics: nil)
  crit_p = outs.select { |o| o.tags.include?(:crit) }.sum(&:prob)
  check("T6 :fine enumerates exact crit probability 1/24",
        (crit_p - 1.0 / 24).abs < 1e-6,
        "crit_p=#{crit_p.round(4)} n_outcomes=#{outs.size}")
  check("T6 :fine outcome probabilities sum to 1", (outs.sum(&:prob) - 1.0).abs < 1e-6, "")

  # 1e. Expectimax decomposition: at depth 1 (no boost, no extensions) the
  #     search value MUST equal Σ p_i * eval(child_i) over the same
  #     enumerated outcomes — verified against a manual recomputation.
  ours = [mk(:ELECTIVIRE, 60, moves: [:THUNDER])]
  # Blissey never acts: it only keeps alive_count at 3 so the endgame rule
  # doesn't switch granularity to :fine (the manual sum uses :coarse too).
  foes = [mk(:SNORLAX, 60, moves: [:BODYSLAM]), mk(:BLISSEY, 100, moves: [:BODYSLAM])]
  bb = CoachEngine2::TwinFactory.build(
    ours.map { |p| Marshal.load(Marshal.dump(p)) },
    foes.map { |p| Marshal.load(Marshal.dump(p)) },
    player: CoachEngine2::DummyTrainer.new("P"), opponent: CoachEngine2::DummyTrainer.new("R"),
    rng: CoachEngine2::DeterministicRNG.new(seed: 7, policy: :median))
  bb.pbStartBattleCore(false)
  flat = cfg(max_depth: 1, boost: false, ext_cap: 0, eps: 0.0)
  res = CoachEngine2::Search.new(bb, viewpoint_side: 0, config: flat).recommend
  drv1 = CoachEngine2::TurnDriver.new(bb)
  outs = CoachEngine2::ChanceEnumerator.enumerate(bb,
    ours: { 0 => drv1.move_choice(0, 0) }, foes: { 1 => drv1.move_choice(1, 0) },
    granularity: :coarse, metrics: nil)
  ev = CoachEngine2::Evaluator.new(0)
  manual = outs.sum { |o| o.prob * ev.win_probability(o.state) }
  check("T6 expectimax value == Σ p_i * eval(child_i)",
        (res.value - manual).abs < 1e-6,
        "search=#{res.value.round(6)} manual=#{manual.round(6)} outcomes=#{outs.size}")

  # 1f. ε pruning: deterministic; bounded error; folds actually happen.
  r1 = CoachEngine2::Search.new(bb, viewpoint_side: 0, config: flat).recommend
  r2 = CoachEngine2::Search.new(bb, viewpoint_side: 0, config: flat).recommend
  r3 = CoachEngine2::Search.new(bb, viewpoint_side: 0,
      config: cfg(max_depth: 1, boost: false, ext_cap: 0, eps: 0.45)).recommend
  check("T6 search deterministic (same config, same result)",
        (r1.value - r2.value).abs < 1e-9 && r1.action == r2.action,
        "v1=#{r1.value.round(4)} v2=#{r2.value.round(4)}")
  check("T6 eps pruning keeps error within bound and fires",
        (r1.value - r3.value).abs <= 0.45 && r3.metrics.eps_prunes > 0,
        "|#{r1.value.round(3)}-#{r3.value.round(3)}|=#{(r1.value - r3.value).abs.round(3)} prunes=#{r3.metrics.eps_prunes}")

  #===========================================================================
  # MILESTONE 2 — adaptive depth, extensions, budgets
  #===========================================================================
  # 2a. Trivial position: solved to a proven win (early stop allowed).
  b = mk_battle([mk(:GLIMMORA, 100, moves: [:POWERGEM])], [mk(:MAREEP, 3, moves: [:TACKLE])])
  res = CoachEngine2::Search.new(b, viewpoint_side: 0,
    config: cfg(max_depth: 2)).recommend
  check("T6 trivial position solved to a win (W=1.0)",
        res.value >= 0.999,
        "value=#{res.value.round(3)} depth=#{res.metrics.max_depth_reached} #{res.metrics.report}")
  # Small root action space (<= 4) searches DEEPER than the configured max.
  b2 = mk_battle([mk(:BLASTOISE, 55, moves: [:SURF, :RAINDANCE])],
                 [mk(:SNORLAX, 55, moves: [:BODYSLAM, :EARTHQUAKE, :REST])])
  res2 = CoachEngine2::Search.new(b2, viewpoint_side: 0,
    config: cfg(max_depth: 2, node_budget: 400, time_budget_ms: 20000)).recommend
  check("T6 small root boosts depth beyond configured max",
        res2.metrics.max_depth_reached > 2,
        "reached=#{res2.metrics.max_depth_reached} (configured 2, +2 boost) rounds=#{res2.metrics.rounds_run}")

  # 2b. KO rounds extend (quiescence) when the battle CONTINUES past the KO.
  b3 = mk_battle([mk(:CHARIZARD, 100, moves: [:AERIALACE])],
                 [mk(:BUTTERFREE, 5, moves: [:GUST]), mk(:BLISSEY, 100, moves: [:BODYSLAM])])
  res3 = CoachEngine2::Search.new(b3, viewpoint_side: 0,
    config: cfg(max_depth: 2, our_repl_cap: 1, foe_repl_cap: 1)).recommend
  check("T6 extensions used on non-terminal KO rounds",
        res3.metrics.extensions > 0,
        "extensions=#{res3.metrics.extensions} value=#{res3.value.round(3)}")

  # 2c. Budgets respected.
  check("T6 node budget respected",
        res.metrics.rounds_run <= 150,
        "rounds=#{res.metrics.rounds_run} budget=150")
  check("T6 time budget respected",
        res.metrics.elapsed_ms <= 12000 + 1500,
        "ms=#{res.metrics.elapsed_ms.to_i}")

  #===========================================================================
  # MILESTONE 3a — forced replacement enumeration (sac is explicit)
  #===========================================================================
  # Our lead is OHKO'd by a faster foe. Party order puts the LOSING backup
  # first (the auto-pick would choose it); the winning backup is last.
  # Enumeration must find the winning replacement.
  ours = [mk(:MAREEP, 3, moves: [:TACKLE]),        # dies to everything
          mk(:BUTTERFREE, 5, moves: [:GUST]),      # auto-pick would choose; loses
          mk(:CHARIZARD, 100, moves: [:AERIALACE])] # outspeeds, 4x OHKOs Heracross
  foes = [mk(:HERACROSS, 55, moves: [:MEGAHORN])]
  b = mk_battle(ours.map { |p| Marshal.load(Marshal.dump(p)) },
                foes.map { |p| Marshal.load(Marshal.dump(p)) })
  res = CoachEngine2::Search.new(b, viewpoint_side: 0,
    config: cfg(max_depth: 2, our_repl_cap: 3, node_budget: 300)).recommend
  check("T6 replacement enumeration runs and finds the win",
        res.value >= 0.95 && res.metrics.repl_expansions > 0,
        "value=#{res.value.round(3)} repl=#{res.metrics.repl_expansions}")
  # Order independence: with enumeration, party order can't hide the winner.
  b_rev = mk_battle([mk(:MAREEP, 3, moves: [:TACKLE]),
                     mk(:CHARIZARD, 100, moves: [:AERIALACE]),
                     mk(:BUTTERFREE, 5, moves: [:GUST])],
                    [mk(:HERACROSS, 55, moves: [:MEGAHORN])])
  res_rev = CoachEngine2::Search.new(b_rev, viewpoint_side: 0,
    config: cfg(max_depth: 2, our_repl_cap: 3, node_budget: 300)).recommend
  check("T6 enumeration makes the value party-order independent",
        (res.value - res_rev.value).abs < 0.10,
        "charizard-first=#{res_rev.value.round(3)} charizard-last=#{res.value.round(3)}")

  # 3b. Foe replacements are adversarial: their best counter is assumed.
  ours = [mk(:CHARIZARD, 100, moves: [:AERIALACE])]
  foes = [mk(:BUTTERFREE, 5, moves: [:GUST]),     # lead: dies to Aerial Ace
          mk(:BLISSEY, 100, moves: [:BODYSLAM]),  # weak answer (auto-pick)
          mk(:TYRANITAR, 100, moves: [:ANCIENTPOWER])] # counters Charizard (4x Rock)
  b = mk_battle(ours.map { |p| Marshal.load(Marshal.dump(p)) },
                foes.map { |p| Marshal.load(Marshal.dump(p)) })
  res = CoachEngine2::Search.new(b, viewpoint_side: 0,
    config: cfg(max_depth: 2, foe_repl_cap: 3)).recommend
  res_f0 = CoachEngine2::Search.new(b, viewpoint_side: 0,
    config: cfg(max_depth: 2, foe_repl_cap: 0)).recommend
  check("T6 foe replacement enumeration is adversarial (assumes their counter)",
        res.value < res_f0.value - 0.10 && res.metrics.repl_expansions > 0,
        "adversarial=#{res.value.round(3)} auto=#{res_f0.value.round(3)} repl=#{res.metrics.repl_expansions}")

  #===========================================================================
  # MILESTONE 3b — opponent beliefs
  #===========================================================================
  # A battle where the foe has only ever used FLAMETHROWER.
  b = mk_battle([mk(:BLASTOISE, 55, moves: [:SURF])],
                [mk(:SNORLAX, 60, moves: [:FLAMETHROWER, :THUNDERBOLT])])
  drv = CoachEngine2::TurnDriver.new(b)
  1.times do
    drv.inject!(0 => drv.move_choice(0, 0), 1 => drv.move_choice(1, 0))
    drv.step!
  end
  beliefs = CoachEngine2::BeliefState.of(b)
  check("T6 beliefs record only the observed move",
        beliefs.observed_moves(1) == [:FLAMETHROWER],
        "observed=#{beliefs.observed_moves(1).inspect}")
  full_acts = CoachEngine2::ActionSpace.side_actions(b, 1)
  rev_acts = CoachEngine2::ActionSpace.side_actions(b, 1, beliefs: beliefs, foe_info: :revealed)
  full_moves = full_acts.map { |j| j.values[0][0] == :UseMove ? j.values[0][2].id : :switch }.uniq
  rev_moves = rev_acts.map { |j| j.values[0][0] == :UseMove ? j.values[0][2].id : :switch }.uniq
  check("T6 :revealed excludes unobserved foe moves",
        rev_moves.include?(:FLAMETHROWER) && !rev_moves.include?(:THUNDERBOLT) &&
        full_moves.include?(:THUNDERBOLT),
        "revealed=#{rev_moves.inspect} full=#{full_moves.inspect}")
  res = CoachEngine2::Search.new(b, viewpoint_side: 0,
    config: cfg(foe_info: :revealed, max_depth: 2)).recommend
  check("T6 search runs under :revealed policy",
        !res.action.nil? && res.value >= 0.0,
        "value=#{res.value.round(3)} #{res.metrics.report}")
rescue => e
  check("T6 raised", false, "#{e.class}: #{e.message}")
  (e.backtrace || [])[0, 10].each { |l| puts "    #{l}" }
end

fails = $TESTS.count { |_n, ok, _| !ok }
puts "T6-SUMMARY: #{$TESTS.size - fails}/#{$TESTS.size} passed"
exit(fails.zero? ? 0 : 1)
