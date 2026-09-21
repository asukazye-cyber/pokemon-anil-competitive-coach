# encoding: UTF-8
#===============================================================================
# Coach Engine 2.0 — Search: expectiminimax with alpha-beta over REAL rounds.
#
# Tree structure (a Pokémon round is SIMULTANEOUS: both sides choose, then
# one real engine round executes). Depth counts ROUNDS:
#
#   value(state, d)                     MAX over our joint actions
#     -> foe_node(state, ours, d)       MIN over foe joint actions
#          (or the game AI's own choice when foe_model == :game_ai)
#       -> chance_node(..., d)          enumerated outcomes of the round
#            (ChanceEnumerator: hit/miss x crit x damage bands, exact
#             threshold probabilities MEASURED against the engine)
#            -> forced-replacement decisions inside the round:
#               our replacements -> MAX, foe's -> MIN (enumerated)
#            -> value(child, d-1)       next round (d stays on extension)
#
# Pruning, all with explicitly bounded error:
#   * alpha-beta at MAX/MIN nodes (exact).
#   * Chance nodes (Star1-style): outcomes in descending probability; with
#     partial sum S and remaining mass M the node value lies in [S, S+M]
#     (values are in [0,1]), so the node is cut when that interval cannot
#     affect the parent MIN's decision by more than eps. Pruned values are
#     returned as the pessimistic bound for our side — pruning never
#     flatters a line. Remaining mass <= eps/2 folds into the last outcome.
#   * Late-move reductions (rank >= lmr_from) with re-search on improvement.
#
# Adaptive depth:
#   * Iterative deepening with aspiration windows (re-search on fail).
#   * Root depth boost for small action spaces; endgame boost when few
#     Pokémon remain (endgame_depth caps; chance granularity goes :fine).
#   * Extensions (round doesn't consume depth): KO rounds and forcing lines
#     (foe locked in a multi-turn move), capped by ext_cap per line.
#
# Correctness properties:
#   * Successor states ONLY via TurnDriver/ChanceEnumerator (real engine).
#   * A KO'd battler never receives value for an unexecuted action.
#   * TT entries carry value bounds (:exact/:lower/:upper) and include the
#     extension budget in the key, so extensions can't pollute lookups.
#===============================================================================

module CoachEngine2
  class Search
    Result = Struct.new(:value, :action, :pv, :metrics, keyword_init: true)

    class Metrics
      attr_accessor :nodes, :tt_hits, :tt_stores, :rounds_run, :max_depth_reached,
                    :elapsed_ms, :pv, :lines_evaluated,
                    :chance_nodes, :chance_outcomes, :unbranched, :eps_prunes,
                    :extensions, :reductions, :repl_expansions, :aspiration_fails,
                    :root_actions

      def initialize
        @nodes = 0; @tt_hits = 0; @tt_stores = 0
        @rounds_run = 0; @max_depth_reached = 0; @lines_evaluated = 0
        @elapsed_ms = 0.0; @pv = []
        @chance_nodes = 0; @chance_outcomes = 0; @unbranched = 0
        @eps_prunes = 0; @extensions = 0; @reductions = 0; @repl_expansions = 0
        @aspiration_fails = 0; @root_actions = 0
      end

      def effective_branching
        return 0.0 if @rounds_run.zero?
        @nodes.to_f / @rounds_run
      end

      def report
        "nodes=#{@nodes} rounds=#{@rounds_run} lines=#{@lines_evaluated} " \
        "depth=#{@max_depth_reached} ch=#{@chance_nodes}/#{@chance_outcomes}" \
        "#{"!" if @unbranched > 0}#{@unbranched} epsPr=#{@eps_prunes} " \
        "ext=#{@extensions} lmr=#{@reductions} repl=#{@repl_expansions} " \
        "tt=#{@tt_hits}/#{@tt_stores} af=#{@aspiration_fails} " \
        "b_eff=#{format('%.1f', effective_branching)} ms=#{@elapsed_ms.to_i} " \
        "pv=#{@pv.inspect}"
      end
    end

    DEFAULT_CONFIG = {
      max_depth: 3,
      node_budget: 600,            # executed engine rounds
      time_budget_ms: 3000,
      foe_model: :adversarial,     # :adversarial | :game_ai
      foe_branching: 5,
      our_branching: 14,
      # --- chance ---
      chance: :on,                 # :on (every round) | :root | :off
      chance_granularity: :coarse, # :coarse | :fine (crit + 16-point damage)
      max_outcomes: 8,
      eps: 0.02,                   # chance-node pruning error bound
      # --- adaptive depth ---
      aspiration: 0.10,
      ext_cap: 2,
      lmr_from: 4,                 # reduce our moves at this rank or later
      endgame_depth: 8,
      boost: true,                 # small-root/endgame depth boosts
      # --- decisions inside a round ---
      our_repl_cap: 3,
      foe_repl_cap: 3,
      # --- opponent information policy ---
      foe_info: :full,             # :full | :revealed (see BeliefState)
      tt: true
    }.freeze

    attr_reader :metrics, :config

    def initialize(battle, viewpoint_side: 0, config: {})
      @battle = battle
      @side = viewpoint_side
      @cfg = DEFAULT_CONFIG.merge(config)
      @metrics = Metrics.new
      @tt = {}
      @deadline = nil
      @abort = false
      @beliefs = BeliefState.of(battle)
      @evaluator = Evaluator.new(viewpoint_side, beliefs: @beliefs,
                                                  foe_info: @cfg[:foe_info])
    end

    # Returns Result (value, best joint action, PV, metrics).
    def recommend
      @metrics = Metrics.new
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @deadline = t0 + @cfg[:time_budget_ms] / 1000.0
      root_actions = ordered_actions(@battle, @side, @cfg[:our_branching])
      @metrics.root_actions = root_actions.length
      return empty_result if root_actions.empty?

      depth_cap = adaptive_depth(root_actions.length)
      best = nil
      best_val = -1.0
      prev_val = nil
      (1..depth_cap).each do |depth|
        @metrics.max_depth_reached = depth
        window = aspiration_window(prev_val)
        val, action = root_pass(root_actions, depth, window)
        if action && val > best_val
          best_val = val
          best = action
        end
        prev_val = val
        break if @abort || budget_exhausted? || best_val >= 1.0
      end
      @metrics.elapsed_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000.0
      @metrics.pv = best ? [describe(@battle, best)] : []
      Result.new(value: best_val, action: best, pv: @metrics.pv, metrics: @metrics)
    end

    private

    def empty_result
      Result.new(value: -1.0, action: nil, pv: [], metrics: @metrics)
    end

    def budget_exhausted?
      @abort ||
        @metrics.rounds_run >= @cfg[:node_budget] ||
        (Process.clock_gettime(Process::CLOCK_MONOTONIC) >= @deadline)
    end

    # Adaptive depth: small action spaces search deeper; endgames (few able
    # mons) get a boost; endgame_depth caps the total.
    def adaptive_depth(root_count)
      cap = @cfg[:max_depth]
      if @cfg[:boost]
        cap += 2 if root_count <= 4
        cap += 1 if root_count > 4 && root_count <= 8
        cap += 2 if alive_count(@battle) <= 2
      end
      [cap, @cfg[:endgame_depth]].min
    end

    def alive_count(state)
      (0..1).sum do |side|
        party = state.pbParty(side == 0 ? 0 : 1)
        party.count { |p| p&.able? }
      end
    end

    def aspiration_window(prev)
      return [0.0, 1.0] if prev.nil? || @cfg[:aspiration] <= 0
      [[prev - @cfg[:aspiration], 0.0].max, [prev + @cfg[:aspiration], 1.0].min]
    end

    def root_pass(root_actions, depth, window)
      val, action = root_search(root_actions, depth, window[0], window[1])
      if val <= window[0] || val >= window[1] || action.nil?
        @metrics.aspiration_fails += 1 if window != [0.0, 1.0]
        val, action = root_search(root_actions, depth, 0.0, 1.0)
      end
      [val, action]
    end

    def root_search(root_actions, depth, alpha, beta)
      best_val = -1.0
      best_action = nil
      root_actions.each_with_index do |ours, rank|
        break if budget_exhausted? || best_val >= beta
        d = rank >= @cfg[:lmr_from] && depth > 1 ? depth - 1 : depth
        val = foe_node(@battle, ours, d, alpha, beta, 0, true)
        if d < depth && val > alpha
          @metrics.reductions += 1
          val = foe_node(@battle, ours, depth, alpha, beta, 0, true)
        end
        @metrics.lines_evaluated += 1
        if val > best_val
          best_val = val
          best_action = ours
          alpha = val
        end
      end
      [best_val, best_action]
    end

    #-------------------------------------------------------------------------
    # MAX over our joint actions (round `depth`).
    #-------------------------------------------------------------------------
    def value(state, depth, alpha, beta, ext, chance_ok)
      @metrics.nodes += 1
      return exact(state) if state.decision != 0
      return @evaluator.win_probability(state) if depth <= 0 || budget_exhausted?

      key = nil
      if @cfg[:tt]
        key = [TurnDriver::StateSummary.of(state).hashable, depth, ext]
        if (hit = @tt[key])
          @metrics.tt_hits += 1
          v, flag = hit
          return v if flag == :exact
          return v if flag == :lower && v >= beta
          return v if flag == :upper && v <= alpha
        end
      end

      ours_list = ordered_actions(state, @side, @cfg[:our_branching])
      if ours_list.empty?
        # No controllable action this round (side locked/forced): play out.
        val = foe_node(state, nil, depth, alpha, beta, ext, chance_ok)
        tt_store(key, val, alpha, beta)
        return val
      end

      best = -1.0
      flag = :exact
      ours_list.each_with_index do |ours, rank|
        break if budget_exhausted? || best >= beta
        d = rank >= @cfg[:lmr_from] && depth > 1 ? depth - 1 : depth
        v = foe_node(state, ours, d, [alpha, best].max, beta, ext, chance_ok)
        if d < depth && v > [alpha, best].max
          @metrics.reductions += 1
          v = foe_node(state, ours, depth, [alpha, best].max, beta, ext, chance_ok)
        end
        if v > best
          best = v
          flag = v >= beta ? :lower : :exact
        end
      end
      best = @evaluator.win_probability(state) if best < 0
      tt_store(key, best, alpha, beta, flag)
      best
    end

    #-------------------------------------------------------------------------
    # MIN over foe joint actions (or the game AI's own choice).
    #-------------------------------------------------------------------------
    def foe_node(state, ours, depth, alpha, beta, ext, chance_ok)
      @metrics.nodes += 1
      return exact(state) if state.decision != 0
      return @evaluator.win_probability(state) if depth <= 0 || budget_exhausted?

      if @cfg[:foe_model] == :game_ai
        return chance_node(state, ours, :game_ai, depth, alpha, beta, ext, chance_ok)
      end
      foes_list = ordered_actions(state, 1, @cfg[:foe_branching])
      if foes_list.empty?
        return chance_node(state, ours, nil, depth, alpha, beta, ext, chance_ok)
      end
      worst = 2.0
      foes_list.each do |foes|
        break if budget_exhausted? || worst <= alpha
        v = chance_node(state, ours, foes, depth, alpha, [beta, worst].min, ext, chance_ok)
        worst = v if v < worst
      end
      worst > 1.0 ? @evaluator.win_probability(state) : worst
    end

    #-------------------------------------------------------------------------
    # CHANCE node: enumerated outcomes with exact probabilities; ε-bounded
    # pruning; forced-replacement decisions enumerated inside each outcome.
    #-------------------------------------------------------------------------
    def chance_node(state, ours, foes, depth, alpha, beta, ext, chance_ok)
      @metrics.chance_nodes += 1
      use_chance = chance_ok && @cfg[:chance] != :off
      granularity = @cfg[:chance_granularity]
      granularity = :fine if @cfg[:chance] == :on && alive_count(state) <= 2

      outcomes =
        if use_chance
          ChanceEnumerator.enumerate(state, ours: ours, foes: foes,
                                     granularity: granularity,
                                     max_outcomes: @cfg[:max_outcomes],
                                     metrics: @metrics)
        else
          child, _dec, = TurnDriver.execute(state, ours: ours, foes: foes)
          @metrics.rounds_run += 1
          [ChanceEnumerator::Outcome.new(state: child, prob: 1.0, tags: [:median], pins: {})]
        end
      @metrics.chance_outcomes += outcomes.length

      parent_alive = alive_count(state)
      s = 0.0
      mass = 1.0
      outcomes.sort_by { |o| -o.prob }.each do |o|
        break if budget_exhausted?
        v = outcome_value(state, ours, foes, o, depth, ext, chance_ok, parent_alive)
        s += o.prob * v
        mass -= o.prob
        if mass > 0 && mass <= @cfg[:eps] * 0.5
          # Remaining outcomes can shift the value by at most mass <= eps/2:
          # fold them into the last evaluated outcome's value.
          @metrics.eps_prunes += 1
          s += mass * v
          mass = 0.0
          break
        end
        if s >= beta + @cfg[:eps]
          # Cannot get below the MIN parent's current best by more than eps;
          # return the pessimistic (upper) bound for the foe's line.
          @metrics.eps_prunes += 1
          return s + mass
        end
      end
      s
    end

    # One outcome's value, expanding forced-replacement decisions (a faint
    # forced a switch-in: our replacements are OUR decisions -> MAX; the
    # foe's are theirs -> MIN; deliberate sacrifice vs forced loss is
    # therefore an explicit, rated choice).
    def outcome_value(state, ours, foes, outcome, depth, ext, chance_ok, parent_alive)
      child = outcome.state
      return 0.5 if child.nil?
      return exact(child) if child.decision != 0

      forced = child.coach_forced_replacements.to_a.uniq
      our_forced = forced.select { |i| i % 2 == @side }
      foe_forced = forced.select { |i| i % 2 != @side }

      ko = alive_count(child) < parent_alive
      if our_forced.empty? && foe_forced.empty?
        return recurse(child, depth, ext, chance_ok, ko)
      end

      # Singles only for now: enumerate when exactly ONE battler per side
      # needs a replacement (documented limitation for doubles).
      our_cands = our_forced.length == 1 ? replacement_candidates(state, our_forced[0]).first(@cfg[:our_repl_cap]) : []
      foe_cands = foe_forced.length == 1 ? replacement_candidates(state, foe_forced[0]).first(@cfg[:foe_repl_cap]) : []
      @metrics.repl_expansions += 1

      best = -1.0
      variants = our_cands.empty? ? [nil] : our_cands
      variants.each do |oc|
        worst = 2.0
        fvariants = foe_cands.empty? ? [nil] : foe_cands
        fvariants.each do |fc|
          break if budget_exhausted?
          reps = {}
          reps[oc[0]] = oc[1] if oc
          reps[fc[0]] = fc[1] if fc
          vchild, _dec, = TurnDriver.execute(state, ours: ours, foes: foes,
                                             replacements: reps,
                                             rng: DeterministicRNG.new(policy: :median,
                                                                       pinned: outcome.pins || {}))
          @metrics.rounds_run += 1
          v = if vchild.nil?
                0.5
              elsif vchild.decision != 0
                exact(vchild)
              else
                recurse(vchild, depth, ext, chance_ok, ko)
              end
          worst = v if v < worst
        end
        best = worst if worst < 2.0 && worst > best
      end
      best < 0 ? recurse(child, depth, ext, chance_ok, ko) : best
    end

    # Next round's depth: extensions for KO rounds and forcing lines.
    def recurse(child, depth, ext, chance_ok, ko)
      ext2 = ext
      d2 = depth - 1
      if ext2 < @cfg[:ext_cap] && (ko || forcing?(child))
        ext2 += 1
        d2 = depth
        @metrics.extensions += 1
      end
      chance_ok2 = @cfg[:chance] == :on ? true : false
      value(child, d2, 0.0, 1.0, ext2, chance_ok2)
    end

    def forcing?(state)
      state.battlers.any? { |b| b && !b.fainted? && b.index % 2 != @side && b.usingMultiTurnAttack? }
    rescue StandardError
      false
    end

    def replacement_candidates(state, idxBattler)
      party = state.pbParty(idxBattler)
      start, = state.pbTeamIndexRangeFromBattlerIndex(idxBattler)
      list = []
      (start...party.length).each do |k|
        next unless party[k]&.able?
        next unless state.pbCanSwitchIn?(idxBattler, k)
        list.push([idxBattler, k])
      end
      list
    end

    def tt_store(key, val, alpha, beta, flag = nil)
      return unless @cfg[:tt] && key
      flag ||= if val <= alpha then :upper
               elsif val >= beta then :lower
               else :exact
               end
      @tt[key] = [val, flag]
      @metrics.tt_stores += 1
    end

    def exact(state)
      case state.decision
      when 1 then @side == 0 ? 1.0 : 0.0
      when 2 then @side == 0 ? 0.0 : 1.0
      else 0.5
      end
    end

    # Order: expected damage first, switches last (move ordering for α-β and
    # LMR; also ranks the adversary's most dangerous replies).
    def ordered_actions(state, side, cap)
      list = ActionSpace.side_actions(state, side,
                                      beliefs: side == 1 ? @beliefs : nil,
                                      foe_info: @cfg[:foe_info])
      if list.length > 1
        list = list.sort_by { |joint| -joint.values.sum { |c| action_score(state, c) } }
      end
      list.first(cap)
    end

    def action_score(state, choice)
      case choice[0]
      when :UseMove
        move_data = GameData::Move.try_get(choice[2].respond_to?(:id) ? choice[2].id : choice[2])
        return 0.0 unless move_data && move_data.power.to_i > 0
        foes = state.battlers.select { |x| x && !x.fainted? && x.index % 2 != @side }
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
      return "" if joint.nil?
      joint = { @side => joint } unless joint.is_a?(Hash)
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
