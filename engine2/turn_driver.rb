# encoding: UTF-8
#===============================================================================
# Coach Engine 2.0 — TurnDriver: the search-facing interface to TwinBattle.
#
# Responsibilities (and nothing else):
#   * start a twin battle (headless or cloned from live);
#   * inject a joint action (one choice per unfainted battler);
#   * execute one round with the real engine (pbAttackPhase +
#     pbEndOfRoundPhase, exactly what pbBattleLoop does between command
#     phases — the command phase is replaced by our injected choices);
#   * expose a compact, hashable state summary for TT keys and comparisons;
#   * provide exact-chance bookkeeping from the instrumented RNG.
#
# This is the ONLY code that creates successor states. Search code never
# mutates battles directly.
#===============================================================================

module CoachEngine2
  class TurnDriver
    attr_reader :battle

    def initialize(battle)
      @battle = battle
    end

    #-------------------------------------------------------------------------
    # Choice construction. Formats mirror the engine's own pbRegisterMove /
    # pbRegisterSwitch (see Battle_ActionSwitching pbRegisterSwitch:
    #   @choices[idxBattler] = [:SwitchOut, idxParty]
    # and Battle_CommandPhase pbRegisterMove:
    #   @choices[idxBattler] = [:UseMove, idxMove, battler.moves[idxMove], -1]).
    #-------------------------------------------------------------------------
    def move_choice(idxBattler, idxMove, target = -1)
      b = @battle.battlers[idxBattler]
      move = idxMove == -1 ? @battle.struggle : b.moves[idxMove]
      [:UseMove, idxMove, move, target]
    end

    def switch_choice(idxBattler, idxParty)
      [:SwitchOut, idxParty]
    end

    #-------------------------------------------------------------------------
    # Inject one joint action. actions: {idxBattler => choice_array}.
    # All unfainted battlers must have a choice; a battler that faints mid-round
    # keeps no value for its unexecuted action (the engine enforces this by
    # checking b.fainted? before each action, and pbProcessTurn bails if the
    # user fainted before acting).
    #-------------------------------------------------------------------------
    def inject!(actions)
      # The engine's pbClearChoice REWRITES THE EXISTING ARRAY IN PLACE
      # (@choices[i][0] = :None, [2] = nil, ...), and an action captured from
      # battle.choices — a multi-turn lock or a game-AI choice — IS that very
      # array. Copy every action before clearing anything, or the battler's
      # action is destroyed by the clear that was meant to make room for it.
      actions = actions.each_with_object({}) do |(idx, choice), copy|
        copy[idx] = choice.is_a?(Array) ? choice.dup : choice
      end
      # Only clear choices the engine itself would clear in pbCommandPhase;
      # multi-turn locks (pbCanShowCommands? false) keep the engine's choice.
      @battle.battlers.each_with_index do |b, i|
        next unless b
        @battle.pbClearChoice(i) if @battle.pbCanShowCommands?(i)
      end
      actions.each do |idx, choice|
        @battle.choices[idx] = localize_choice(idx, choice)
      end
    end

    # Rebinds a choice to THIS battle's own objects. The engine mutates
    # @choices entries in place (pbCalculatePriority appends a priority
    # element; cancels rewrite elements), and Battle::Move objects carry
    # per-battle state — so a choice built for another battle must never be
    # inserted as-is. :UseMove choices are rebuilt from this battle's own
    # battler moves (or its Struggle); the array itself is duplicated.
    def localize_choice(idx, choice)
      return choice.dup unless choice.is_a?(Array) && choice[0] == :UseMove
      if choice[1] == -1 || choice[2].nil?
        move = @battle.struggle
      else
        b = @battle.battlers[idx]
        move = b ? b.moves[choice[1]] : nil
        move = @battle.struggle if move.nil?
      end
      [:UseMove, choice[1], move, choice[3]]
    end

    # Execute one round. replacement: optional {idxBattler => party_index}
    # used if a faint forces a switch-in.
    # Returns the battle's decision (0 = ongoing, 1/2 = side 0/1 won...).
    def step!(replacements = {})
      @battle.coach_next_replacements.replace(replacements)
      @battle.coach_events.clear
      @battle.coach_forced_replacements.clear
      @battle.pbAttackPhase
      if @battle.decision == 0
        @battle.pbEndOfRoundPhase
        @battle.turnCount += 1 if @battle.decision == 0
      end
      @battle.decision
    end

    #-------------------------------------------------------------------------
    # One full successor construction: clone -> localize choices -> execute a
    # real round. Used by both the search and the chance enumerator, so ALL
    # successor states keep coming from a single authority.
    #   ours/foes: {idxBattler => choice} (nil entries fall back to the
    #   engine's own forced choice or, as a last resort, the game AI).
    #   rng: fresh DeterministicRNG for this run (pins = roll overrides).
    #   replacements: {idxBattler => party_index} presets for forced switch-ins.
    # Returns [clone, decision, rng].
    #-------------------------------------------------------------------------
    def self.execute(state, ours: nil, foes: nil, rng: nil, replacements: {},
                     beliefs: nil)
      clone = Marshal.load(Marshal.dump(state))
      rng ||= DeterministicRNG.new(policy: :median)
      clone.coach_rng = rng
      if clone.respond_to?(:anil_rework_rng=)
        clone.anil_rework_rng = TwinBattle::CoachRNGAdapter.new(rng)
      end
      drv = new(clone)
      actions = {}
      assign_side(clone, 0, ours, actions, beliefs: beliefs)
      assign_side(clone, 1, foes, actions, beliefs: beliefs)
      drv.inject!(actions)
      # What this round executes, recorded as plain data for the chance
      # enumerator (see TwinBehavior#coach_choices). Recorded BEFORE the round
      # runs: the engine keeps mutating @choices entries while it executes
      # (priority element, Pursuit targets, cancels), and this record must say
      # what was CHOSEN.
      if clone.respond_to?(:coach_choices=)
        clone.coach_choices = actions.each_with_object({}) do |(i, c), h|
          h[i] = plain_choice(c)
        end
      end
      decision = drv.step!(replacements)
      [clone, decision, rng]
    end

    # A choice reduced to plain data: the move OBJECT becomes its id, so the
    # record can live on a clone that the search Marshals again.
    def self.plain_choice(choice)
      return choice unless choice.is_a?(Array)
      return choice.dup unless choice[0] == :UseMove
      mv = choice[2]
      [:UseMove, choice[1], (mv.respond_to?(:id) ? mv.id : mv), choice[3]]
    end

    # The engine keeps its AI in an ivar with no public reader.
    def self.ai_of(battle)
      ai = battle.instance_variable_get(:@battleAI)
      return ai if ai
      ai = Battle::AI.new(battle)
      ai.create_ai_objects
      battle.instance_variable_set(:@battleAI, ai)
      ai
    end

    def self.assign_side(battle, side, joint, actions, beliefs: nil)
      battle.battlers.each_with_index do |b, i|
        next unless b && !b.fainted? && i % 2 == side
        if joint.is_a?(Hash) && joint.key?(i)
          actions[i] = joint[i]
        elsif ActionSpace.forced_choice?(battle, i)
          # The engine's own locked choice (multi-turn attack). COPIED: it is
          # the live @choices array, which pbClearChoice rewrites in place.
          actions[i] = engine_choice_copy(battle, i)
        elsif side == 1 && joint == :game_ai
          battle.pbClearChoice(i)
          ai_of(battle).pbDefaultChooseEnemyCommand(i)
          actions[i] = engine_choice_copy(battle, i)
        elsif side == 1 && beliefs && !joint.is_a?(Hash)
          # No explicit foe action; :revealed policy restricts the fallback
          # (game AI reads the real moveset, which :revealed forbids).
          actions[i] = ActionSpace.struggle_choice(battle, i)
        else
          battle.pbClearChoice(i)
          ai_of(battle).pbDefaultChooseEnemyCommand(i)
          actions[i] = engine_choice_copy(battle, i)
        end
      end
      actions
    end

    # A choice read out of the engine's own @choices must never be held by
    # reference: the engine mutates those arrays in place (pbClearChoice,
    # pbCalculatePriority's element [4], Pursuit target rewrites), so an
    # aliased action can be wiped or rewritten before it is injected.
    def self.engine_choice_copy(battle, idxBattler)
      c = battle.choices[idxBattler]
      c.is_a?(Array) ? c.dup : c
    end

    #-------------------------------------------------------------------------
    # State summary: everything needed to compare two post-round states and to
    # build transposition keys. Only client-visible information is included.
    #-------------------------------------------------------------------------
    class StateSummary
      attr_reader :decision, :turn, :weather, :terrain, :sides

      # A summary is a TRANSPOSITION KEY and a state-equality oracle, so it
      # must cover everything that can change the future of the battle. Two
      # states that differ only in a field effect (Trick Room flips the
      # execution order), in WHICH battler effects are set (not merely in how
      # many), or in remaining PP are different states and must never share a
      # key — a collision here silently returns another state's value.
      def self.of(battle)
        s = new
        s.instance_variable_set(:@decision, battle.decision)
        s.instance_variable_set(:@turn, battle.turnCount)
        s.instance_variable_set(:@weather, [battle.field.weather, battle.field.weatherDuration])
        s.instance_variable_set(:@terrain, [battle.field.terrain, battle.field.terrainDuration])
        s.instance_variable_set(:@field, effect_pairs(battle.field.effects))
        mons = []
        2.times do |side|
          party = battle.pbParty(side == 0 ? 0 : 1)
          party.each_with_index do |pkmn, i|
            next unless pkmn
            active = battle.battlers.any? { |b| b && !b.fainted? && b.pokemonIndex == i && b.index % 2 == side }
            mons.push([
              side, i, pkmn.species, pkmn.hp, pkmn.totalhp, pkmn.status.to_s,
              pkmn.statusCount, pkmn.item.to_s, pkmn.ability.to_s, active,
              pkmn.moves.compact.map { |m| [m.id, m.pp] }
            ])
          end
        end
        s.instance_variable_set(:@mons, mons)
        actives = []
        battle.battlers.each_with_index do |b, i|
          next unless b
          actives.push([
            i, b.pokemonIndex, b.hp, b.stages.dup, b.fainted?, b.turnCount,
            b.ability.to_s, b.item.to_s, b.status.to_s, b.statusCount,
            effect_pairs(b.effects),
            b.moves.compact.map { |m| [m.id, m.pp] }
          ])
        end
        s.instance_variable_set(:@actives, actives)
        sides = [[], []]
        2.times do |side|
          sides[side] = effect_pairs(battle.sides[side].effects)
        end
        s.instance_variable_set(:@sides, sides)
        # NOTE: effect containers are Arrays indexed by PBEffects constants.
        s.instance_variable_set(:@positions, battle.positions.map { |p| p ? effect_pairs(p.effects) : nil })
        s
      end

      # Nonzero entries of an effects container, as ordered [index, value]
      # pairs. Object values are reduced to clone-stable scalars: two snapshots
      # of the same battle must summarize EQUAL, so a Pokemon held by an effect
      # (Illusion) is fingerprinted instead of compared by identity.
      def self.effect_pairs(effects)
        return [] unless effects
        out = []
        effects.each_with_index do |v, i|
          next if v.nil? || v == false || v == 0
          out.push([i, scalarize(v)])
        end
        out
      end

      def self.scalarize(v)
        case v
        when nil, true, false, Numeric, Symbol, String then v
        when Array  then v.first(8).map { |x| scalarize(x) }
        when Pokemon then [:pkmn, v.species, v.hp, v.totalhp]
        when Battle::Battler then [:battler, v.index]
        else v.class.name
        end
      end

      def hashable
        [@decision, @turn, @weather, @terrain, @field, @mons, @actives, @sides, @positions]
      end

      def hash
        hashable.hash
      end

      def eql?(other)
        hashable == other.hashable
      end

      def side0_alive
        @mons.count { |m| m[0] == 0 && m[3] > 0 }
      end

      def side1_alive
        @mons.count { |m| m[0] == 1 && m[3] > 0 }
      end

      def to_s
        "turn=#{@turn} decision=#{@decision} weather=#{@weather[0]} field=#{@field.size} " +
          @actives.map { |a| "[b#{a[0]} p#{a[1]} hp=#{a[2]} stages=#{a[3].inspect} ko=#{a[4]} eff=#{a[10].size}]" }.join(" ")
      end
    end

    def summary
      StateSummary.of(@battle)
    end

    #-------------------------------------------------------------------------
    # Determinism / cloning helpers.
    #-------------------------------------------------------------------------
    def deep_copy(rng: nil)
      dumped = Marshal.dump(@battle)
      copy = Marshal.load(dumped)
      copy.coach_rng = rng if rng
      copy
    end
  end
end
