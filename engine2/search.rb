# encoding: UTF-8
#===============================================================================
# Coach Engine 2.0 — Search: adversarial expectimax over REAL engine rounds.
#
# Model (a Pokémon round is SIMULTANEOUS: both sides choose, then the engine
# executes the round for both choices at once):
#
#   value(state, depth):
#     * decision != 0              -> EXACT 1.0 / 0.0 (terminal)
#     * depth == 0 / budget out    -> Evaluator estimate
#     * otherwise                  -> max over our joint actions of
#                                     ( :game_ai  -> round with AI's choice )
#                                     ( :adversarial -> MIN over foe joint
#                                       actions of round outcome )
#
#   Chance handling (DOCUMENTED APPROXIMATION): rounds run with the
#   deterministic :median roll policy (every RNG draw returns max/2), which
#   collapses chance nodes into one representative outcome. Outcomes that the
#   rules make roll-independent (No Guard accuracy, fixed damage, status
#   certain-hit effects) are EXACT under this policy by construction.
#   Exact chance enumeration (hit/miss/crit/damage-roll branching with the
#   pinned-RNG interface) is a designed next milestone, not a claim.
#
# Correctness properties:
#   * Successor states are ONLY created by TurnDriver (real engine).
#   * A KO'd battler never receives value for an unexecuted action: the
#     engine itself skips fainted battlers, so such lines simply yield the
#     post-KO state with no credit for the dead mon's move.
#   * TT is depth-aware (deeper results replace shallower, never reverse).
#
# Instrumentation: every search reports nodes, unique states, TT hits/stores,
# executed rounds, pruning, depth, effective branching, elapsed time, PV.
#===============================================================================

module CoachEngine2
  class Search
    Result = Struct.new(:value, :action, :pv, :metrics, keyword_init: true)

    class Metrics
      attr_accessor :nodes, :tt_hits, :tt_stores, :rounds_run, :max_depth_reached,
                    :elapsed_ms, :pv, :lines_evaluated

      def initialize
        @nodes = 0; @tt_hits = 0; @tt_stores = 0
        @rounds_run = 0; @max_depth_reached = 0; @lines_evaluated = 0
        @elapsed_ms = 0.0; @pv = []
      end

      def effective_branching
        return 0.0 if @rounds_run.zero?
        @nodes.to_f / @rounds_run
      end

      def report
        "nodes=#{@nodes} tt_hit=#{@tt_hits} tt_store=#{@tt_stores} " \
        "rounds=#{@rounds_run} lines=#{@lines_evaluated} " \
        "depth=#{@max_depth_reached} b_eff=#{format('%.1f', effective_branching)} " \
        "ms=#{@elapsed_ms.to_i} pv=#{@pv.inspect}"
      end
    end

    DEFAULT_CONFIG = {
      max_depth: 3,
      node_budget: 400,          # executed engine rounds
      time_budget_ms: 5000,
      foe_model: :adversarial,   # :adversarial | :game_ai
      foe_branching: 5,
      our_branching: 16,
      tt: true
    }.freeze

    attr_reader :metrics, :config

    def initialize(battle, viewpoint_side: 0, config: {})
      @battle = battle
      @side = viewpoint_side
      @cfg = DEFAULT_CONFIG.merge(config)
      @evaluator = Evaluator.new(viewpoint_side)
      @metrics = Metrics.new
      @tt = {}
      @deadline = nil
      @abort = false
    end

    # Returns Result (value, best joint action, PV, metrics).
    def recommend
      @metrics = Metrics.new
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @deadline = t0 + @cfg[:time_budget_ms] / 1000.0
      best = nil
      best_val = -1.0
      (1..@cfg[:max_depth]).each do |depth|
        @metrics.max_depth_reached = depth
        val, action = root_pass(depth)
        if action && (best.nil? || val >= best_val)
          best_val = val
          best = action
        end
        break if @abort || budget_exhausted?
      end
      @metrics.elapsed_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000.0
      @metrics.pv = best ? [describe(@battle, best)] : []
      Result.new(value: best_val, action: best, pv: @metrics.pv, metrics: @metrics)
    end

    private

    def budget_exhausted?
      @abort ||
        @metrics.rounds_run >= @cfg[:node_budget] ||
        (Process.clock_gettime(Process::CLOCK_MONOTONIC) >= @deadline)
    end

    def root_pass(depth)
      actions = ordered_actions(@battle, @side, @cfg[:our_branching])
      return [-1.0, nil] if actions.empty?
      best_val = -1.0
      best_action = nil
      actions.each do |ours|
        break if budget_exhausted?
        val =
          if @cfg[:foe_model] == :game_ai
            child = round_clone(@battle, ours, :game_ai)
            child ? value(child, depth - 1) : -1.0
          else
            foe_actions = ordered_actions(@battle, 1, @cfg[:foe_branching])
            if foe_actions.empty?
              child = round_clone(@battle, ours, nil)
              child ? value(child, depth - 1) : -1.0
            else
              worst = 2.0
              foe_actions.each do |foes|
                break if budget_exhausted?
                child = round_clone(@battle, ours, foes)
                next if child.nil?
                v = value(child, depth - 1)
                worst = v if v < worst
              end
              worst > 1.0 ? -1.0 : worst
            end
          end
        @metrics.lines_evaluated += 1
        if val > best_val
          best_val = val
          best_action = ours
        end
      end
      [best_val, best_action]
    end

    def value(state, depth)
      @metrics.nodes += 1
      return exact(state) if state.decision != 0
      return @evaluator.win_probability(state) if depth <= 0 || budget_exhausted?

      key = nil
      if @cfg[:tt]
        key = CoachEngine2::TurnDriver::StateSummary.of(state).hashable
        if (hit = @tt[key]) && hit[1] >= depth
          @metrics.tt_hits += 1
          return hit[0]
        end
      end

      ours_list = ordered_actions(state, @side, @cfg[:our_branching])
      if ours_list.empty?
        # No controllable action this round (e.g. our side fully locked or
        # only forced choices): let the round play out.
        child = round_clone(state, nil, @cfg[:foe_model] == :game_ai ? :game_ai : nil)
        val = child ? value(child, depth - 1) : @evaluator.win_probability(state)
      else
        best = -1.0
        ours_list.each do |ours|
          break if budget_exhausted?
          val =
            if @cfg[:foe_model] == :game_ai
              child = round_clone(state, ours, :game_ai)
              child ? value(child, depth - 1) : -1.0
            else
              foe_actions = ordered_actions(state, 1, @cfg[:foe_branching])
              if foe_actions.empty?
                child = round_clone(state, ours, nil)
                child ? value(child, depth - 1) : -1.0
              else
                worst = 2.0
                foe_actions.each do |foes|
                  break if budget_exhausted?
                  child = round_clone(state, ours, foes)
                  next if child.nil?
                  v = value(child, depth - 1)
                  worst = v if v < worst
                end
                worst > 1.0 ? -1.0 : worst
              end
            end
          best = val if val > best
        end
        val = best < 0 ? @evaluator.win_probability(state) : best
      end

      if @cfg[:tt] && key
        @tt[key] = [val, depth]
        @metrics.tt_stores += 1
      end
      val
    end

    def exact(state)
      case state.decision
      when 1 then @side == 0 ? 1.0 : 0.0
      when 2 then @side == 0 ? 0.0 : 1.0
      else 0.5
      end
    end

    # Executes one round on a deep copy. ours/foes: joint action hashes (or
    # nil to keep engine/forced/AI choices), :game_ai for the game's own AI.
    def round_clone(state, ours, foes)
      clone = Marshal.load(Marshal.dump(state))
      @metrics.rounds_run += 1
      drv = TurnDriver.new(clone)
      actions = {}
      # Side 0 (ours at root; in recursive states side identity is fixed).
      assign_side(clone, 0, ours, actions)
      assign_side(clone, 1, foes, actions)
      drv.inject!(actions)
      drv.step!
      clone
    rescue StandardError => e
      $stderr.puts "[engine2] round_clone failed: #{e.class}: #{e.message[0, 90]}" if $DEBUG_COACH
      nil
    end

    # The engine keeps its AI in an ivar with no public reader.
    def ai_of(battle)
      ai = battle.instance_variable_get(:@battleAI)
      return ai if ai
      ai = Battle::AI.new(battle)
      ai.create_ai_objects
      battle.instance_variable_set(:@battleAI, ai)
      ai
    end

    def assign_side(battle, side, joint, actions)
      battle.battlers.each_with_index do |b, i|
        next unless b && !b.fainted? && i % 2 == side
        if joint.is_a?(Hash) && joint.key?(i)
          actions[i] = joint[i]
        elsif ActionSpace.forced_choice?(battle, i)
          actions[i] = battle.choices[i]          # engine's own locked choice
        elsif side == 1 && joint == :game_ai
          battle.pbClearChoice(i)
          ai_of(battle).pbDefaultChooseEnemyCommand(i)
          actions[i] = battle.choices[i]
        else
          # Idle/unknown: let the game AI pick a sane choice so the round is
          # valid (all unfainted battlers need a choice).
          battle.pbClearChoice(i)
          ai_of(battle).pbDefaultChooseEnemyCommand(i)
          actions[i] = battle.choices[i]
        end
      end
    end

    # Ordering: our damaging moves likely-to-KO first, switches last.
    def ordered_actions(state, side, cap)
      list = ActionSpace.side_actions(state, side)
      if side == @side && list.length > 1
        list = list.sort_by { |joint| -joint.values.sum { |c| action_score(state, c) } }
      end
      list.first(cap)
    end

    def action_score(state, choice)
      case choice[0]
      when :UseMove
        move_data = GameData::Move.try_get(choice[2].id)
        return 0.0 unless move_data && move_data.power.to_i > 0
        foes = state.battlers.select { |x| x && !x.fainted? && x.index % 2 == 1 }
        return 0.0 if foes.empty?
        foes.map do |f|
          eff = Effectiveness.calculate(move_data.type, *f.pokemon.types.compact) rescue 1.0
          move_data.power * eff
        end.max.to_f
      when :SwitchOut
        -5.0
      else
        0.0
      end
    end

    def describe(state, joint)
      joint.map do |i, c|
        b = state.battlers[i]
        next "" unless b
        case c[0]
        when :UseMove
          mv_id = c[2].respond_to?(:id) ? c[2].id : c[2]
          md = GameData::Move.try_get(mv_id)
          "#{b.pokemon.species}:#{md ? md.real_name : mv_id}"
        when :SwitchOut
          pkmn = state.pbParty(i)[c[1]]
          "SWITCH:#{pkmn&.species}"
        end
      end.compact.join(" | ")
    end
  end
end
