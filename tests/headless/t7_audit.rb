# encoding: UTF-8
#===============================================================================
# T7: post-merge audit regressions for Coach Engine 2.0.
#
# Every check pins ONE defect found by the post-merge audit (see CHANGELOG
# "Fixed (post-merge audit)" and AUDIT §8). Each one was reproduced against
# the merged code BEFORE the fix — the "was" notes below are measured output, not
# speculation — and is asserted here in its fixed form so it cannot regress
# silently again.
#
#   A   the branch cap raised inside ChanceEnumerator#fold (arity), so the
#       blanket rescue collapsed the whole enumeration into ONE [:fallback]
#       outcome with p=1.0. That cap is hit in EVERY endgame round, because
#       the search force-upgrades 1v1 rounds to :fine (33 branches) while the
#       default cap is 8.
#       was: outcomes=1 tags=[[:fallback]] (ArgumentError: given 3, expected 4)
#   A2  the endgame :fine upgrade ignored the outcome budget and truncated
#       most of the distribution it was meant to enumerate; the truncated mass
#       was also folded into the LARGEST outcome, inflating the miss branch.
#       was: [[:miss], 0.707] for a 70%-accuracy move (truth 0.30)
#   B   the move owning the round's first accuracy roll was identified from the
#       PARENT state's stale @priority/choices — the PREVIOUS round's order.
#       Trick Room ending, priority moves, speed changes and switches all flip
#       it: the foe's Fire Blast (85) was branched with our Thunder's (70)
#       threshold, and the one-sided verification passed anyway.
#       was: miss_p=0.30 measured for an 85%-accuracy move (truth 0.15)
#   B2  with foes: :game_ai the foe's executed choice was never consulted, so
#       no accuracy event was identified at all (silent 100% hit assumption).
#   B3  assign_side captured a choice read out of the engine's own @choices BY
#       REFERENCE (multi-turn lock, game AI), and inject!'s pbClearChoice
#       rewrites that array IN PLACE - so the action was wiped to [:None]
#       before it was injected and the battler did nothing at all. (This is
#       what made B2 untestable: the AI chose correctly and lost the choice.)
#       was: a charging Solar Beam never fired on turn 2; a :game_ai foe never
#       used a single move in any round of any search.
#   C   StateSummary — the transposition key AND the differential oracle —
#       ignored field effects (Trick Room!), WHICH battler effects were set
#       (only their count) and remaining PP. Colliding keys return another
#       state's search value.
#       was: Trick-Room-only and PP-only differences compared EQUAL
#   D   the foe's replies were ordered by their effectiveness against the
#       FOE'S OWN team, so their most dangerous answer ranked last.
#       was: [Bola Sombra, Lanzallamas] vs Steelix (Lanzallamas is 4x)
#   E   a from_live snapshot of a plain Battle — the path the GAME uses — kept
#       the engine's own pbRandom: rounds were non-reproducible and chance
#       enumeration reported "deterministic" with an empty roll log. It also
#       kept pbSetSeen/pbGainExp/pbEndOfBattle and the party-screen
#       replacement prompts, which only TwinBattle overrode.
#       was: rng log 0/0, identical rounds=false, outcomes=[[:deterministic]]
#   E2  a snapshot taken inside an active BattleSync context inherits the
#       network wrappers on pbAttackPhase/pbEndOfRoundPhase/pbJudge/
#       pbSwitchInBetween (turn barriers, HP reconciliation, pending-sync
#       draining, switch broadcast). Simulating a round there would touch the
#       peer connection on behalf of the LIVE battle.
#===============================================================================
load_engine2 rescue nil   # no-op when the suite runner already loaded engine2

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

# A plain `Battle` (NOT a TwinBattle) needs a trainer that answers the dex
# bookkeeping the engine performs on send-out — exactly what a real in-game
# trainer object does and what a snapshot of one inherits.
class T7Dex
  def register(*); end
  def register_caught(*); end
  def register_defeated(*); end
end

class T7Trainer < CoachEngine2::DummyTrainer
  def pokedex
    @t7dex ||= T7Dex.new
  end
end

begin
  #===========================================================================
  # A — the outcome cap must truncate, not collapse the enumeration
  #===========================================================================
  b = mk_battle([mk(:ELECTIVIRE, 60, moves: [:THUNDER])],
                [mk(:SNORLAX, 60, moves: [:BODYSLAM])])
  drv = CoachEngine2::TurnDriver.new(b)
  m = CoachEngine2::Search::Metrics.new
  outs = CoachEngine2::ChanceEnumerator.enumerate(
    b, ours: { 0 => drv.move_choice(0, 0) }, foes: { 1 => drv.move_choice(1, 0) },
    granularity: :fine, max_outcomes: 8, metrics: m)
  miss_p = outs.select { |o| o.tags.include?(:miss) }.sum(&:prob)
  total  = outs.sum(&:prob)
  check("T7 capped :fine enumeration survives (no [:fallback] collapse)",
        outs.size > 1 && outs.none? { |o| o.tags.include?(:fallback) } &&
        (total - 1.0).abs < 1e-6,
        "outcomes=#{outs.size} total=#{total.round(6)} tags=#{outs.map { |o| o.tags.first }.inspect}")
  check("T7 truncated mass goes to one [:folded] bucket, not into the miss branch",
        (miss_p - 0.30).abs < 0.011 && outs.count { |o| o.tags.include?(:folded) } == 1 &&
        m.unbranched > 0,
        "miss_p=#{miss_p.round(4)} folded=#{outs.select { |o| o.tags.include?(:folded) }.map { |o| o.prob.round(3) }.inspect} unbranched=#{m.unbranched}")

  #===========================================================================
  # A2 — the endgame :fine upgrade must respect the outcome budget
  #===========================================================================
  endgame = mk_battle([mk(:GLIMMORA, 100, moves: [:POWERGEM])],
                      [mk(:MAREEP, 3, moves: [:TACKLE])])
  res = CoachEngine2::Search.new(endgame, viewpoint_side: 0,
    config: { max_depth: 1, boost: false, ext_cap: 0, node_budget: 150,
              time_budget_ms: 20000, chance: :on }).recommend
  check("T7 endgame search enumerates exactly under the default cap (no truncation)",
        res.metrics.unbranched.zero? && res.metrics.chance_nodes > 0 &&
        res.metrics.chance_outcomes >= res.metrics.chance_nodes,
        "ch=#{res.metrics.chance_nodes}/#{res.metrics.chance_outcomes} unb=#{res.metrics.unbranched} value=#{res.value.round(3)}")
  check("T7 :fine is only used when the cap can hold it",
        CoachEngine2::ChanceEnumerator::MAX_FINE_BRANCHES >
          CoachEngine2::Search::DEFAULT_CONFIG[:max_outcomes],
        "MAX_FINE_BRANCHES=#{CoachEngine2::ChanceEnumerator::MAX_FINE_BRANCHES} " \
        "default max_outcomes=#{CoachEngine2::Search::DEFAULT_CONFIG[:max_outcomes]}")

  #===========================================================================
  # B — the accuracy event must be identified from the round that ran
  #===========================================================================
  ours = [mk(:ELECTIVIRE, 60, moves: [:THUNDER, :QUICKATTACK])]
  foes = [mk(:SNORLAX, 60, moves: [:TRICKROOM, :FIREBLAST])]
  tb = mk_battle(ours, foes)
  tdrv = CoachEngine2::TurnDriver.new(tb)
  tdrv.inject!(0 => tdrv.move_choice(0, 0), 1 => tdrv.move_choice(1, 0))
  tdrv.step!   # Snorlax sets Trick Room; Electivire moved first this round
  stale = tb.instance_variable_get(:@priority).map { |e| e[0].index }
  mb = CoachEngine2::Search::Metrics.new
  outs = CoachEngine2::ChanceEnumerator.enumerate(
    tb, ours: { 0 => tdrv.move_choice(0, 0) }, foes: { 1 => tdrv.move_choice(1, 1) },
    granularity: :coarse, metrics: mb)
  probe_order, = CoachEngine2::TurnDriver.execute(
    tb, ours: { 0 => tdrv.move_choice(0, 0) }, foes: { 1 => tdrv.move_choice(1, 1) })
  real_order = probe_order.instance_variable_get(:@priority).map { |e| e[0].index }
  miss_p = outs.select { |o| o.tags.include?(:miss) }.sum(&:prob)
  check("T7 Trick Room flip: the parent's stale order is not used",
        tb.field.effects[PBEffects::TrickRoom] > 0 && stale != real_order,
        "stale=#{stale.inspect} real=#{real_order.inspect}")
  check("T7 miss probability belongs to the move that rolled first (Fire Blast 85)",
        (miss_p - 0.15).abs < 0.011 && mb.unbranched.zero?,
        "miss_p=#{miss_p.round(4)} (0.30 would be THUNDER's) unbranched=#{mb.unbranched}")

  # B2 — the same identification must work when the foe's action comes from the
  # game's own AI (nothing explicit in `foes:` to read a choice from).
  gb = mk_battle([mk(:SNORLAX, 60, moves: [:BODYSLAM])],
                 [mk(:ELECTIVIRE, 60, moves: [:THUNDER])])
  gdrv = CoachEngine2::TurnDriver.new(gb)
  gouts = CoachEngine2::ChanceEnumerator.enumerate(
    gb, ours: { 0 => gdrv.move_choice(0, 0) }, foes: :game_ai,
    granularity: :coarse, metrics: nil)
  gmiss = gouts.select { |o| o.tags.include?(:miss) }.sum(&:prob)
  check("T7 :game_ai rounds still identify the foe's accuracy event",
        gouts.any? { |o| o.tags.include?(:miss) } && (gmiss - 0.30).abs < 0.011,
        "miss_p=#{gmiss.round(4)} outcomes=#{gouts.map { |o| [o.tags, o.prob.round(3)] }.inspect}")

  # B3 — the same aliasing defect destroyed the ENGINE'S OWN locked choice for
  # a battler in a multi-turn attack: assign_side captured battle.choices[i] BY
  # REFERENCE and inject!'s pbClearChoice rewrote that array in place, so the
  # continuation turn was injected as [:None] and the battler simply did
  # nothing. (was: Solar Beam charged and never fired)
  lock = mk_battle([mk(:VENUSAUR, 60, moves: [:SOLARBEAM])],
                   [mk(:SNORLAX, 60, moves: [:BODYSLAM])])
  ldrv = CoachEngine2::TurnDriver.new(lock)
  ldrv.inject!(0 => ldrv.move_choice(0, 0), 1 => ldrv.move_choice(1, 0))
  ldrv.step!
  charging = lock.battlers[0].usingMultiTurnAttack?
  hp_before = lock.battlers[1].hp
  child2, = CoachEngine2::TurnDriver.execute(lock, ours: nil,
                                             foes: { 1 => ldrv.move_choice(1, 0) })
  check("T7 a multi-turn lock survives injection (Solar Beam fires on round 2)",
        charging && child2.coach_choices[0][0] == :UseMove &&
        child2.battlers[1].hp < hp_before && !child2.battlers[0].usingMultiTurnAttack?,
        "charging=#{charging} choice=#{child2.coach_choices[0].inspect} " \
        "foeHP #{hp_before}->#{child2.battlers[1].hp}")

  # B4 — and the game AI's own choice must reach the round it was chosen for.
  gaib = mk_battle([mk(:SNORLAX, 60, moves: [:BODYSLAM])],
                   [mk(:ELECTIVIRE, 60, moves: [:THUNDER])])
  gaidrv = CoachEngine2::TurnDriver.new(gaib)
  gaichild, = CoachEngine2::TurnDriver.execute(gaib, ours: { 0 => gaidrv.move_choice(0, 0) },
                                                     foes: :game_ai)
  check("T7 the game AI's choice is injected, not wiped by pbClearChoice",
        gaichild.coach_choices[1][0] == :UseMove && gaichild.battlers[0].hp < gaichild.battlers[0].totalhp,
        "foe choice=#{gaichild.coach_choices[1].inspect} ourHP=#{gaichild.battlers[0].hp}/#{gaichild.battlers[0].totalhp}")

  #===========================================================================
  # C — StateSummary must not collide on state that changes the future
  #===========================================================================
  c1 = mk_battle([mk(:ELECTIVIRE, 60, moves: [:THUNDER])],
                 [mk(:SNORLAX, 60, moves: [:BODYSLAM])])
  s1 = CoachEngine2::TurnDriver::StateSummary.of(c1).hashable

  c2 = Marshal.load(Marshal.dump(c1))
  c2.field.effects[PBEffects::TrickRoom] = 5
  check("T7 field effects (Trick Room) are part of the state summary",
        s1 != CoachEngine2::TurnDriver::StateSummary.of(c2).hashable, "")

  c3 = Marshal.load(Marshal.dump(c1))
  c3.battlers[1].effects[PBEffects::Yawn]    = 1
  c3.battlers[1].effects[PBEffects::Embargo] = 1
  c4 = Marshal.load(Marshal.dump(c1))
  c4.battlers[1].effects[PBEffects::Nightmare] = true
  c4.battlers[1].effects[PBEffects::Taunt]     = 1
  check("T7 WHICH battler effects are set matters, not just how many",
        CoachEngine2::TurnDriver::StateSummary.of(c3).hashable !=
        CoachEngine2::TurnDriver::StateSummary.of(c4).hashable, "")

  c5 = Marshal.load(Marshal.dump(c1))
  c5.battlers[0].moves[0].pp = 1
  check("T7 remaining PP is part of the state summary",
        s1 != CoachEngine2::TurnDriver::StateSummary.of(c5).hashable, "")

  c6 = Marshal.load(Marshal.dump(c1))
  check("T7 identical states still summarize identically (no false splits)",
        s1 == CoachEngine2::TurnDriver::StateSummary.of(c6).hashable, "")

  #===========================================================================
  # D — the adversary's replies are ranked against OUR team
  #===========================================================================
  d = mk_battle([mk(:STEELIX, 60, moves: [:IRONHEAD])],
                [mk(:GENGAR, 60, moves: [:SHADOWBALL, :FLAMETHROWER])])
  search = CoachEngine2::Search.new(d, viewpoint_side: 0,
                                    config: { node_budget: 1, time_budget_ms: 1 })
  foe_order = search.send(:ordered_actions, d, 1, 5).map do |joint|
    joint.values.map { |c| c[2].respond_to?(:id) ? c[2].id : c[0] }
  end
  check("T7 foe replies ordered by danger to OUR battlers",
        foe_order.first == [:FLAMETHROWER],
        "order=#{foe_order.inspect} (Lanzallamas is 4x on Steelix, Bola Sombra is 1x)")
  our_order = search.send(:ordered_actions, d, 0, 5).map do |joint|
    joint.values.map { |c| c[2].respond_to?(:id) ? c[2].id : c[0] }
  end
  check("T7 our own ordering is unchanged by the fix",
        our_order.first == [:IRONHEAD], "order=#{our_order.inspect}")

  #===========================================================================
  # E — a snapshot of a PLAIN Battle is instrumented and protected
  #===========================================================================
  live = Battle.new(CoachEngine2::NullScene.new,
                    [mk(:ELECTIVIRE, 60, moves: [:THUNDER])],
                    [mk(:SNORLAX, 60, moves: [:BODYSLAM])],
                    T7Trainer.new("Player"), CoachEngine2::DummyTrainer.new("Rival"))
  live.environment = :None
  live.canSwitch = true
  live.expGain = false
  live.moneyGain = false
  live.pbStartBattleCore(false)
  check("T7 the live battle for this check is a plain Battle (not a TwinBattle)",
        live.class == Battle && !live.is_a?(CoachEngine2::TwinBattle),
        "class=#{live.class} anil_rework_rng?=#{live.respond_to?(:anil_rework_rng=)}")

  snap = CoachEngine2::TwinFactory.from_live(
    live, 0, rng: CoachEngine2::DeterministicRNG.new(seed: 3, policy: :median))
  sdrv = CoachEngine2::TurnDriver.new(snap)
  run = lambda do
    CoachEngine2::TurnDriver.execute(snap,
      ours: { 0 => sdrv.move_choice(0, 0) }, foes: { 1 => sdrv.move_choice(1, 0) },
      rng: CoachEngine2::DeterministicRNG.new(seed: 3, policy: :median))
  end
  r1, _d1, rng1 = run.call
  r2, _d2, rng2 = run.call
  same = CoachEngine2::TurnDriver::StateSummary.of(r1).hashable ==
         CoachEngine2::TurnDriver::StateSummary.of(r2).hashable
  check("T7 from_live snapshot routes every roll through the twin RNG",
        rng1.log.size > 0 && rng2.log.size > 0 && rng1.log.size == rng2.log.size && same,
        "log=#{rng1.log.size}/#{rng2.log.size} identical rounds=#{same} " \
        "owner=#{snap.method(:pbRandom).owner}")
  eouts = CoachEngine2::ChanceEnumerator.enumerate(
    snap, ours: { 0 => sdrv.move_choice(0, 0) }, foes: { 1 => sdrv.move_choice(1, 0) },
    granularity: :coarse, metrics: nil)
  check("T7 chance enumeration works on the in-game snapshot path",
        eouts.size > 1 && eouts.none? { |o| o.tags.include?(:deterministic) } &&
        eouts.any? { |o| o.tags.include?(:miss) },
        "outcomes=#{eouts.map { |o| [o.tags, o.prob.round(3)] }.inspect}")
  check("T7 snapshot carries the twin protections (dex/exp/replacement hooks)",
        [:pbSetSeen, :pbSetCaught, :pbSetDefeated, :pbGainExp, :pbEndOfBattle,
         :pbSwitchInBetween, :pbGetReplacementPokemonIndex].all? { |mth|
           snap.method(mth).owner == CoachEngine2::TwinBehavior
         },
        "owners=#{[:pbSetSeen, :pbSwitchInBetween].map { |mth| snap.method(mth).owner }.inspect}")

  # A faint inside a simulated round must never reach a party screen: the twin
  # picks the replacement itself and records it as forced.
  weak = Battle.new(CoachEngine2::NullScene.new,
                    [mk(:MAREEP, 3, moves: [:TACKLE]), mk(:ZOROARK, 55, moves: [:FLAMETHROWER])],
                    [mk(:GLIMMORA, 100, moves: [:POWERGEM])],
                    T7Trainer.new("Player"), CoachEngine2::DummyTrainer.new("Rival"))
  weak.environment = :None
  weak.canSwitch = true
  weak.expGain = false
  weak.moneyGain = false
  weak.pbStartBattleCore(false)
  wsnap = CoachEngine2::TwinFactory.from_live(weak, 0)
  wdrv = CoachEngine2::TurnDriver.new(wsnap)
  wchild, wdec, = CoachEngine2::TurnDriver.execute(
    wsnap, ours: { 0 => wdrv.move_choice(0, 0) }, foes: { 1 => wdrv.move_choice(1, 0) })
  check("T7 forced replacement on the snapshot path never opens a party screen",
        wchild.coach_forced_replacements.include?(0) && !wchild.battlers[0].fainted? &&
        wchild.decision == 0 && wchild.battlers[0].pokemon.species == :ZOROARK,
        "decision=#{wdec} forced=#{wchild.coach_forced_replacements.inspect} " \
        "active=#{wchild.battlers[0].pokemon.species}")

  #===========================================================================
  # E2 — the multiplayer isolation gate
  #===========================================================================
  unless defined?(AnilLanRework) && defined?(AnilLanRework::BattleSync)
    module ::AnilLanRework
      module BattleSync
        class << self
          attr_accessor :active_context
        end
      end
    end
  end

  AnilLanRework::BattleSync.active_context = Object.new   # a live sync context
  raised = nil
  begin
    CoachEngine2::TwinFactory.from_live(live, 0)
  rescue CoachEngine2::TwinIsolationError => e
    raised = e
  end
  check("T7 snapshot inside an active BattleSync context is refused",
        !raised.nil?, "#{raised.class}: #{raised&.message.to_s[0, 60]}")
  check("T7 a refused snapshot degrades to 'no Engine 2.0 recommendation'",
        CoachEngine2.recommend_for(live, 0).nil?,
        "recommend_for -> #{CoachEngine2.recommend_for(live, 0).inspect} (v27 chain serves the HUD)")
  CoachEngine2.allow_sync_twins = true
  bypass = begin
    CoachEngine2::TwinFactory.from_live(live, 0)
  rescue StandardError
    nil
  end
  check("T7 the documented override bypasses the gate",
        !bypass.nil?, "allow_sync_twins=#{CoachEngine2.allow_sync_twins}")
  CoachEngine2.allow_sync_twins = false
  AnilLanRework::BattleSync.active_context = nil          # back to single player
  sp = begin
    CoachEngine2::TwinFactory.from_live(live, 0)
  rescue StandardError
    nil
  end
  check("T7 single-player snapshots are unaffected by the gate",
        !sp.nil? && CoachEngine2.allow_sync_twins == false, "twin=#{sp.class}")
rescue => e
  check("T7 raised", false, "#{e.class}: #{e.message}")
  (e.backtrace || [])[0, 12].each { |l| puts "    #{l}" }
end

fails = $TESTS.count { |_n, ok, _| !ok }
puts "T7-SUMMARY: #{$TESTS.size - fails}/#{$TESTS.size} passed"
exit(fails.zero? ? 0 : 1)
