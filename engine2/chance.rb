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
#     copied, no extra round executions. Branches: hit (P = thr/max) and
#     miss (P = 1 - thr/max). Not branched when thr == 0/max (one-sided).
#     Identification of which move owns the roll is VERIFIED by an exact
#     state-equality check; on any mismatch the event is not branched.
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
# verified (the roll consumed at index k must have the same max as in the
# probe); a failing branch folds its probability into the largest outcome —
# approximations are counted in metrics, never silent.
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

    def enumerate
      probe_state, _d, probe_rng = run_with({})
      probe_log = probe_rng.log
      return [Outcome.new(state: probe_state, prob: 1.0, tags: [:deterministic], pins: {})] if probe_log.empty?

      acc_idx = first_index(probe_log, TAG_ACC)
      dmg_idx = first_index(probe_log, TAG_DMG)
      crit_idx = @granularity == :fine ? first_index(probe_log, TAG_CRIT) : nil

      acc = build_acc_event(acc_idx, probe_log, probe_state)
      dmg = dmg_idx && dmg_idx > (acc ? acc[:idx] : -1) ? { idx: dmg_idx } : nil
      crit = nil
      if crit_idx && crit_idx > (acc ? acc[:idx] : -1)
        ratio = measure_crit_ratio
        crit = { idx: crit_idx, ratio: ratio } if ratio && ratio > 1
      end

      hit_p  = acc ? acc[:thr].to_f / acc[:max] : 1.0
      miss_p = acc ? 1.0 - hit_p : 0.0

      # Band representatives: the probe's own values where they fall in the
      # band (so the probe run is reused), canonical values elsewhere.
      acc_hit_val  = acc ? (probe_log[acc[:idx]][0] < acc[:thr] ? probe_log[acc[:idx]][0] : 0) : nil
      acc_miss_val = acc ? (probe_log[acc[:idx]][0] >= acc[:thr] ? probe_log[acc[:idx]][0] : acc[:thr]) : nil
      dmg_val      = dmg ? probe_log[dmg[:idx]][0] : nil

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
          [[0, 1.0 / crit[:ratio]], [probe_log[crit[:idx]][0], (crit[:ratio] - 1).to_f / crit[:ratio]]]
        end

      # The probe is exactly: hit? (acc median value vs thr) + mid damage +
      # no-crit (crit median value != 0 unless ratio == 1, excluded above).
      probe_dmg_val = dmg ? dmg_val : nil
      probe_is_hit = !acc || probe_log[acc[:idx]][0] < acc[:thr]

      outcomes = []
      branches = []
      crit_bands.each do |cv, cp|
        next if cv.nil? && crit # no-crit band only
        dmg_bands.each do |dv, dp|
          pins = {}
          pins[acc[:idx]] = acc_hit_val if acc && acc_hit_val
          pins[crit[:idx]] = cv if crit && cv
          pins[dmg[:idx]] = dv if dmg && dv
          tags = [:hit]
          tags.push(:crit) if crit && cv == 0
          branches.push([pins, hit_p * cp * dp, tags])
        end
      end
      branches.push([{ acc[:idx] => acc_miss_val }, miss_p, [:miss]]) if acc && acc_miss_val

      processed = 0
      branches.sort_by { |_p, prob, _t| -prob }.each do |pins, prob, tags|
        break if outcomes.size >= @max_outcomes
        processed += 1
        # Probe reuse: the pins reproduce the probe's own roll values.
        if pins.all? { |k, v| probe_log[k][0] == v }
          outcomes.push(Outcome.new(state: probe_state, prob: prob, tags: [:probe] + tags, pins: pins))
          next
        end
        child, _dec, rng = run_with(pins)
        if pins.all? { |k, _v| rng.log[k] && rng.log[k][1] == probe_log[k][1] }
          outcomes.push(Outcome.new(state: child, prob: prob, tags: tags, pins: pins))
        else
          fold(outcomes, prob, probe_state)
        end
      end

      # Cap: fold the mass of branches that never ran.
      if processed < branches.size
        folded = branches[processed..-1].sum { |_p, prob, _t| prob }
        fold(outcomes, folded, probe_state) if folded > 0
      end

      total = outcomes.sum(&:prob)
      outcomes.each { |o| o.prob /= total } if total > 0 && (total - 1.0).abs > 1e-9
      outcomes
    rescue StandardError => e
      warn_chance(e)
      [Outcome.new(state: (probe_state || run_with({})[0]), prob: 1.0, tags: [:fallback], pins: {})]
    end

    private

    def first_index(log, tag)
      log.index { |_v, _max, stack| stack =~ tag }
    end

    def run_with(pins)
      @metrics.rounds_run += 1 if @metrics
      TurnDriver.execute(@state, ours: @ours, foes: @foes, replacements: @replacements,
                         rng: DeterministicRNG.new(policy: :median, pinned: pins))
    end

    def warn_chance(e)
      return unless defined?($DEBUG_COACH) && $DEBUG_COACH
      $stderr.puts "[engine2] chance failed: #{e.class}: #{e.message[0, 90]}"
      (e.backtrace || [])[0, 8].each { |l| $stderr.puts "  #{l}" }
    end

    # Folds probability into the largest outcome (or the probe if none).
    def fold(outcomes, prob, probe_state, pins)
      if outcomes.empty?
        outcomes.push(Outcome.new(state: probe_state, prob: prob, tags: [:folded], pins: {}))
      else
        outcomes.max_by(&:prob).prob += prob
      end
      @metrics.unbranched += 1 if @metrics
    end

    # Accuracy event: measure thr, verify identification by exact state
    # equality (hit-side pin must reproduce the probe when the probe hit).
    def build_acc_event(acc_idx, probe_log, probe_state)
      return nil unless acc_idx
      thr = measure_accuracy_threshold
      return nil unless thr
      max = probe_log[acc_idx][1]
      return nil if thr <= 0 || thr >= max   # one-sided: no branch
      acc = { idx: acc_idx, thr: thr, max: max }
      # Identification verification: if the probe hit, pinning the acc roll
      # to thr-1 (also a hit, rest median) must reproduce the probe exactly.
      if probe_log[acc_idx][0] < thr
        vstate, = run_with(acc[:idx] => thr - 1)
        same = vstate &&
               TurnDriver::StateSummary.of(vstate).hashable == TurnDriver::StateSummary.of(probe_state).hashable
        return nil unless same
      end
      acc
    end

    # thr of the round's FIRST accuracy-checking move: bisection on the
    # engine's own pbAccuracyCheck (standalone call, no round execution).
    def measure_accuracy_threshold
      clone = Marshal.load(Marshal.dump(@state))
      order = execution_order(@state)
      order.each do |idx|
        choice = choice_for(idx)
        next unless choice.is_a?(Array) && choice[0] == :UseMove
        user = clone.battlers[idx]
        next unless user && !user.fainted?
        move = choice[1] == -1 ? clone.struggle : user.moves[choice[1]]
        next unless move.respond_to?(:pbAccuracyCheck)
        target = clone.battlers[target_index(@state, idx, choice)]
        next unless target
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
      order = execution_order(@state)
      order.each do |idx|
        choice = choice_for(idx)
        next unless choice.is_a?(Array) && choice[0] == :UseMove
        user = clone.battlers[idx]
        next unless user && !user.fainted?
        move = choice[1] == -1 ? clone.struggle : user.moves[choice[1]]
        next unless move.respond_to?(:pbIsCritical?)
        target = clone.battlers[target_index(@state, idx, choice)]
        next unless target
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

    def choice_for(idx)
      return @ours[idx] if @ours.is_a?(Hash) && @ours.key?(idx)
      return @foes[idx] if @foes.is_a?(Hash) && @foes.key?(idx)
      @state.choices[idx]
    end

    # The engine's @priority entries are [battler, speed, subpri, ...]
    # (battler OBJECTS — see pbCalculatePriority); turn them into indices.
    def execution_order(state)
      pri = state.instance_variable_get(:@priority)
      if pri.is_a?(Array) && !pri.empty?
        idxs = pri.map do |e|
          next nil unless e.is_a?(Array) && e[0]
          e[0].respond_to?(:index) ? e[0].index : e[0]
        end.compact
        return idxs unless idxs.empty?
      end
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
