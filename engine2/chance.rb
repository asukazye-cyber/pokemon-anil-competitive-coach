# encoding: UTF-8
#===============================================================================
# Coach Engine 2.0 — Exact chance enumeration over REAL engine rounds.
#
# A round's RNG draws are classified by the ENGINE'S OWN call stack (the RNG
# log records the caller chain): accuracy checks (pbAccuracyCheck), critical
# hits (pbIsCritical?) and damage variance (pbCalcDamageMultipliers,
# `85 + pbRandom(16)`). The enumerator produces the decision-relevant
# outcome set:
#
#   * Accuracy: the threshold thr (hits iff roll < thr) is MEASURED by
#     bisection on the engine's own pbAccuracyCheck call — no formulas
#     copied. Branches: hit (P = thr/max) and
#     miss (P = 1 - thr/max). Not branched when thr == 0/max (one-sided).
#     The move that owns the roll is identified from the round's REAL
#     execution order (the probe round's own @priority, filled by
#     pbCalculatePriority) and from the choices that round actually executed
#     — NEVER from the parent state's stale @priority/choices, which describe
#     the PREVIOUS round and flip under Trick Room, priority moves, speed
#     changes and switches. Identification is then PROVEN differentially:
#     pinning the roll just below thr must reproduce the probe while pinning
#     it at thr must change it (exactly one side may match). On any mismatch
#     the event is not branched and is counted in metrics.
#   * Critical: P(crit) = 1/ratio measured from the engine's own roll
#     request (pbIsCritical? standalone call). Branched at :fine only.
#   * Damage variance (uniform over 16 values): :coarse = 3-point
#     quadrature {min: 1/16, mid: 14/16, max: 1/16}; :fine = all 16 values
#     at 1/16 each. Only the FIRST damaging move's roll is branched; later
#     rolls keep the :median policy (tracked in metrics).
#
# Probabilities of branched events multiply (independent draws) and always
# sum to 1. The probe run (all-median) is reused as the outcome whose band
# representatives are the median values themselves. Every pinned run is
# verified for pin-LANDING (the roll consumed at index k must have the same
# max as in the probe AND the value we pinned); a branch that does not land,
# or mass truncated by the outcome cap, goes into one extra [:folded]
# outcome carrying the probe's (median) state — never into another branch's
# probability. All approximations are counted in metrics, never silent.
#===============================================================================

module CoachEngine2
  class ChanceEnumerator
    Outcome = Struct.new(:state, :prob, :tags, :pins, keyword_init: true)

    TAG_ACC  = /pbAccuracyCheck/.freeze
    TAG_CRIT = /pbIsCritical/.freeze
    TAG_DMG  = /pbCalcDamage/.freeze

    # opts: { ours:, foes:, granularity: :coarse|:fine, max_outcomes:,
    #          replacements: {}, metrics: }
    def self.enumerate(state, opts = {})
      new(state, opts).enumerate
    end

    def initialize(state, opts)
      @state = state
      @ours = opts[:ours]
      @foes = opts[:foes]
      @granularity = opts[:granularity] || :coarse
      @max_outcomes = opts[:max_outcomes] || 8
      @replacements = opts[:replacements] || {}
      @metrics = opts[:metrics]
    end

    # Branch count a full :fine enumeration can need (2 crit bands x 16 damage
    # bands + the miss branch). Callers use it to decide whether an outcome
    # budget can actually represent :fine instead of truncating most of it.
    MAX_FINE_BRANCHES = 33

    def enumerate
      @probe_state, _d, probe_rng = run_with({})
      @probe_log = probe_rng.log
      if @probe_log.empty?
        # No roll was recorded: either the round is genuinely roll-free, or
        # this battle's pbRandom is not routed through the twin instrument.
        # The second case must not pass for "deterministic" silently.
        count_unbranched(:rng_not_instrumented) unless instrumented?(@probe_state, probe_rng)
        return [Outcome.new(state: @probe_state, prob: 1.0, tags: [:deterministic], pins: {})]
      end

      # Identification data comes from the round that ACTUALLY ran: its real
      # execution order (pbCalculatePriority filled @priority) and the joint
      # action it executed (TurnDriver records it as plain data — the engine
      # clears @choices as battlers act). The parent state's @priority and
      # @choices describe the PREVIOUS round and are wrong whenever the order
      # flips.
      @order = execution_order(@probe_state)
      @probe_choices = probe_choices(@probe_state)

      acc_idx  = first_index(@probe_log, TAG_ACC)
      dmg_idx  = first_index(@probe_log, TAG_DMG)
      crit_idx = @granularity == :fine ? first_index(@probe_log, TAG_CRIT) : nil

      acc = build_acc_event(acc_idx)
      dmg = dmg_idx && dmg_idx > (acc ? acc[:idx] : -1) ? { idx: dmg_idx } : nil
      crit = nil
      if crit_idx && crit_idx > (acc ? acc[:idx] : -1)
        ratio = measure_crit_ratio
        if ratio && ratio > 1
          crit = { idx: crit_idx, ratio: ratio }
        else
          count_unbranched(:crit_unmeasured)
        end
      end

      hit_p  = acc ? acc[:thr].to_f / acc[:max] : 1.0
      miss_p = acc ? 1.0 - hit_p : 0.0

      # Band representatives: the probe's own values where they fall in the
      # band (so the probe run is reused), canonical values elsewhere.
      acc_hit_val  = acc ? (@probe_log[acc[:idx]][0] < acc[:thr] ? @probe_log[acc[:idx]][0] : 0) : nil
      acc_miss_val = acc ? (@probe_log[acc[:idx]][0] >= acc[:thr] ? @probe_log[acc[:idx]][0] : acc[:thr]) : nil
      dmg_val      = dmg ? @probe_log[dmg[:idx]][0] : nil

      dmg_bands =
        if !dmg
          [[nil, 1.0]]
        elsif @granularity == :fine
          (0...16).map { |v| [v, 1.0 / 16.0] }
        else
          [[0, 1.0 / 16.0], [dmg_val, 14.0 / 16.0], [15, 1.0 / 16.0]]
        end
      crit_bands =
        if !crit
          [[nil, 1.0]]
        else
          [[0, 1.0 / crit[:ratio]], [@probe_log[crit[:idx]][0], (crit[:ratio] - 1).to_f / crit[:ratio]]]
        end

      outcomes = []
      branches = []
      crit_bands.each do |cv, cp|
        dmg_bands.each do |dv, dp|
          pins = {}
          pins[acc[:idx]]  = acc_hit_val if acc && acc_hit_val
          pins[crit[:idx]] = cv if crit && cv
          pins[dmg[:idx]]  = dv if dmg && dv
          tags = acc ? [:hit] : []
          tags.push(:crit) if crit && cv == 0
          branches.push([pins, hit_p * cp * dp, tags])
        end
      end
      branches.push([{ acc[:idx] => acc_miss_val }, miss_p, [:miss]]) if acc && acc_miss_val

      # Most probable first, so the outcome cap drops the least significant
      # branches. The folded mass is the TAIL OF THIS ORDER — slicing the
      # unsorted list mis-accounted which branches were skipped.
      ordered = branches.sort_by { |_p, prob, _t| -prob }
      processed = 0
      ordered.each do |pins, prob, tags|
        break if outcomes.size >= @max_outcomes
        processed += 1
        # Probe reuse: the pins reproduce the probe's own roll values.
        if pin_landed?(@probe_log, pins)
          outcomes.push(Outcome.new(state: @probe_state, prob: prob, tags: [:probe] + tags, pins: pins))
          next
        end
        child, _dec, rng = run_with(pins)
        if pin_landed?(rng.log, pins, @probe_log)
          outcomes.push(Outcome.new(state: child, prob: prob, tags: tags, pins: pins))
        else
          count_unbranched(:pin_not_landed)
          fold(outcomes, prob, @probe_state, pins)
        end
      end

      # Cap: fold the mass of the branches that never ran.
      if processed < ordered.length
        folded = ordered[processed..-1].sum { |_p, prob, _t| prob }
        if folded > 0
          count_unbranched(:capped)
          fold(outcomes, folded, @probe_state)
        end
      end

      total = outcomes.sum(&:prob)
      outcomes.each { |o| o.prob /= total } if total > 0 && (total - 1.0).abs > 1e-9
      outcomes
    rescue StandardError => e
      warn_chance(e)
      count_unbranched(:enumerator_error)
      state = @probe_state
      if state.nil?
        state = begin
          run_with({})[0]
        rescue StandardError
          nil
        end
      end
      [Outcome.new(state: state, prob: 1.0, tags: [:fallback], pins: {})]
    end

    private

    def first_index(log, tag)
      log.index { |_v, _max, stack| stack =~ tag }
    end

    def run_with(pins)
      @metrics.rounds_run += 1 if @metrics
      rng = DeterministicRNG.new(policy: :median, pinned: pins)
      child, decision, _rng = TurnDriver.execute(@state, ours: @ours, foes: @foes,
                                                 replacements: @replacements, rng: rng)
      [child, decision, rng]
    end

    def warn_chance(e)
      return unless defined?($DEBUG_COACH) && $DEBUG_COACH
      $stderr.puts "[engine2] chance failed: #{e.class}: #{e.message[0, 90]}"
      (e.backtrace || [])[0, 8].each { |l| $stderr.puts "  #{l}" }
    end

    # Every approximation this enumerator makes is counted in the metrics it
    # was given — nothing degrades silently.
    def count_unbranched(_reason)
      @metrics.unbranched += 1 if @metrics
    end

    # Folds probability mass that could not be branched (a cap truncation, a
    # pin that did not land) into ONE extra outcome carrying the probe's state
    # — the median-band representative, i.e. the least biased state we have.
    # Dumping the mass into the largest outcome instead distorts the
    # distribution it is supposed to approximate (a truncated :fine
    # enumeration used to inflate the miss branch to ~0.7). Every fold is
    # counted in the metrics by the caller.
    def fold(outcomes, prob, probe_state, pins = {})
      existing = outcomes.find { |o| o.tags.include?(:folded) }
      if existing
        existing.prob += prob
      else
        outcomes.push(Outcome.new(state: probe_state, prob: prob, tags: [:folded], pins: pins))
      end
    end

    # A branch is usable only if every pinned roll really LANDED on the roll it
    # was meant for: same index, same max as in the probe, and the value we
    # asked for (the RNG clamps out-of-range pins, and a shifted roll sequence
    # would put the pin on somebody else's draw).
    def pin_landed?(log, pins, probe_log = nil)
      pins.all? do |k, v|
        entry = log[k]
        next false unless entry
        next false if probe_log && (!probe_log[k] || entry[1] != probe_log[k][1])
        entry[0] == v
      end
    end

    # True when this battle really routes pbRandom through the twin instrument
    # (an empty roll log then means "no roll was drawn", not "not measured").
    def instrumented?(battle, rng)
      return false unless battle.respond_to?(:coach_rng) && battle.coach_rng.equal?(rng)
      owner = begin
        battle.method(:pbRandom).owner
      rescue StandardError, NameError
        nil
      end
      return true if owner == TwinBehavior || owner == TwinBattle
      adapter = battle.respond_to?(:anil_rework_rng) ? battle.anil_rework_rng : nil
      adapter.is_a?(TwinBattle::CoachRNGAdapter)
    end

    # Accuracy event: measure thr for the move that really owns the roll, then
    # PROVE the identification differentially.
    def build_acc_event(acc_idx)
      return nil unless acc_idx
      thr = measure_accuracy_threshold
      unless thr
        count_unbranched(:acc_unmeasured)
        return nil
      end
      max = @probe_log[acc_idx][1]
      return nil if thr <= 0 || thr >= max   # one-sided: no branch
      acc = { idx: acc_idx, thr: thr, max: max }
      return acc if identification_holds?(acc)
      count_unbranched(:acc_misidentified)
      nil
    end

    # Pinning the roll just below thr (a hit) and exactly at thr (a miss) must
    # change the round, and EXACTLY ONE of the two may reproduce the probe. A
    # threshold measured for the wrong move typically agrees with the probe on
    # both sides (both rolls still hit), which is what this rejects.
    def identification_holds?(acc)
      low_same  = same_as_probe?(run_with(acc[:idx] => acc[:thr] - 1)[0])
      high_same = same_as_probe?(run_with(acc[:idx] => acc[:thr])[0])
      low_same != high_same
    end

    def same_as_probe?(state)
      return false unless state && @probe_state
      TurnDriver::StateSummary.of(state).hashable ==
        TurnDriver::StateSummary.of(@probe_state).hashable
    end

    # thr of the round's FIRST accuracy-checking move: bisection on the
    # engine's own pbAccuracyCheck (standalone call, no round execution).
    def measure_accuracy_threshold
      clone = Marshal.load(Marshal.dump(@state))
      each_round_move(clone) do |user, move, target|
        next unless move.respond_to?(:pbAccuracyCheck)
        rng = DeterministicRNG.new(policy: :median, pinned: { 0 => 0 })
        clone.coach_rng = rng
        begin
          move.pbAccuracyCheck(user, target)
        rescue StandardError
          next
        end
        next unless rng.log.size == 1 && rng.log[0][1] == 100
        return bisect_accuracy(clone, user, move, target)
      end
      nil
    end

    def bisect_accuracy(clone, user, move, target)
      passes = lambda do |v|
        rng = DeterministicRNG.new(policy: :median, pinned: { 0 => v })
        clone.coach_rng = rng
        move.pbAccuracyCheck(user, target)
      end
      return 100 if passes.call(99)
      return 0 unless passes.call(0)
      lo = 0
      hi = 99
      while hi - lo > 1
        mid = (lo + hi) / 2
        passes.call(mid) ? lo = mid : hi = mid
      end
      hi
    end

    # Crit ratio of the round's first crit-checked move: the engine's own
    # roll request max IS the ratio (crit iff roll == 0). One call, exact.
    def measure_crit_ratio
      clone = Marshal.load(Marshal.dump(@state))
      each_round_move(clone) do |user, move, target|
        next unless move.respond_to?(:pbIsCritical?)
        rng = DeterministicRNG.new(policy: :max, pinned: { 0 => 1 })
        clone.coach_rng = rng
        begin
          move.pbIsCritical?(user, target)
        rescue StandardError
          next
        end
        next unless rng.log.size == 1
        return rng.log[0][1]
      end
      nil
    end

    # Yields [user, move, target] for every move the probed round executed, in
    # that round's real order, bound to the given (pre-round) clone.
    def each_round_move(clone)
      (@order || fallback_order(clone)).each do |idx|
        choice = choice_for(idx)
        next unless choice.is_a?(Array) && choice[0] == :UseMove
        user = clone.battlers[idx]
        next unless user && !user.fainted?
        move = choice[1] == -1 ? clone.struggle : user.moves[choice[1]]
        next unless move
        target = clone.battlers[target_index(clone, idx, choice)]
        next unless target
        yield user, move, target
      end
    end

    def choice_for(idx)
      # What the probed round ACTUALLY executed: TurnDriver's plain-data record
      # (coach_choices) is the only source that survives the round and the only
      # one that exists at all when a side is driven by the game AI.
      c = @probe_choices[idx] if @probe_choices.is_a?(Hash)
      return c if c.is_a?(Array) && c[0] == :UseMove
      return @ours[idx] if @ours.is_a?(Hash) && @ours.key?(idx)
      return @foes[idx] if @foes.is_a?(Hash) && @foes.key?(idx)
      @state.choices[idx]
    end

    def probe_choices(state)
      return state.coach_choices if state.respond_to?(:coach_choices) &&
                                    state.coach_choices.is_a?(Hash) &&
                                    !state.coach_choices.empty?
      begin
        state.choices
      rescue StandardError
        nil
      end
    end

    # The engine's @priority entries are [battler, speed, subpri, ...]
    # (battler OBJECTS — see pbCalculatePriority); turn them into indices.
    # Called on the POST-round probe state, so this is the order the round
    # really used — not the previous round's leftover.
    def execution_order(state)
      pri = state.instance_variable_get(:@priority)
      if pri.is_a?(Array) && !pri.empty?
        idxs = pri.map do |e|
          next nil unless e.is_a?(Array) && e[0]
          e[0].respond_to?(:index) ? e[0].index : e[0]
        end.compact
        return idxs unless idxs.empty?
      end
      fallback_order(state)
    end

    def fallback_order(state)
      state.battlers.each_index.select { |i| state.battlers[i] }
    end

    def target_index(state, idx, choice)
      return choice[3] if choice[3].is_a?(Integer) && choice[3] >= 0
      b = state.battlers[idx]
      opp = b.respond_to?(:pbDirectOpposing) ? b.pbDirectOpposing : nil
      return opp.index if opp
      state.battlers.each_index do |i|
        next unless state.battlers[i] && !state.battlers[i].fainted? && i % 2 != idx % 2
        return i
      end
      idx
    end
  end
end
