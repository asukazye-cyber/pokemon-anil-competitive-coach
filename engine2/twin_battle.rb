# encoding: UTF-8
#===============================================================================
# Coach Engine 2.0 — TwinBattle: drives the REAL Añil battle engine as the sole
# successor-state authority.
#
# A TwinBattle is a real `Battle` subclass with:
#   * a NullScene that swallows all presentation (the engine's logic paths stay
#     untouched; only UI side effects are silenced);
#   * a deterministic, instrumented RNG (pbRandom) that supports "roll
#     policies", letting the search enumerate chance outcomes exactly instead
#     of sampling them.
#
# IMPORTANT: nothing in this file monkey-patches Battle. It subclasses it.
# The multiplayer rework's aliased methods (anil_rework_*) remain intact and
# in the call chain, because we call the final public methods normally.
#===============================================================================

module CoachEngine2
  # Headless only: the engine's Battle#pbShowAbilitySplash reads the constant
  # Battle::Scene::USE_ABILITY_SPLASH (defined in the UI script 0190, which a
  # headless boot doesn't load). In-game the real constant exists and is used;
  # either way the twin's NullScene swallows the presentation call itself.
  if defined?(Battle)
    # In-game, Battle::Scene exists (script 0190) and already has the
    # constant — both steps below are no-ops there. Headless, the battle
    # slice may have created an empty Battle::Scene via BattleArena's
    # reopening; provide the constant so logic checks don't NameError.
    # The constant only gates PRESENTATION calls, which NullScene swallows
    # anyway; battle logic is identical either way.
    Battle.const_set(:Scene, Class.new) unless Battle.const_defined?(:Scene)
    unless Battle::Scene.const_defined?(:USE_ABILITY_SPLASH)
      Battle::Scene.const_set(:USE_ABILITY_SPLASH, false)
    end
  end

  #---------------------------------------------------------------------------
  # Swallows every scene call. Battle logic calls scene methods for messages
  # and animations; the twin must not render or wait for input.
  #---------------------------------------------------------------------------
  class NullScene
    def pbStartBattle(_battle); end
    def pbStartBattleSendOut(_battlers); end
    def pbBeginAttackPhase; end
    def pbEndAttackPhase; end
    def pbBeginTurn(_round); end
    def pbEndTurn(_round); end
    def pbChangeBackground(_backdrop); end
    def pbRefresh; end
    def pbRefreshOne(_idxBattler); end
    def pbUpdate(_linelite = false); end
    def pbShowHelp(_text); end
    def pbHideHelp; end
    def pbShowParty(_idxSide); end
    def pbHideParty; end
    def pbShowAnnotations; end
    def pbHideAnnotations; end
    def pbSet battler, _sprite; end
    def pbResetCommands(_idxBattler); end
    def pbDecisionOnWait; end
    def pbDamageAnimation(_battler, _effective = false); end
    def pbHPChanged(_battler, _oldhp, _effective = false); end
    def pbFaintAnimation(_battler); end
    def pbThrowSuccessAnimation; end
    def pbOpponentHPChanged(_battler, _oldhp); end
    def pbEXPBar(_battler, _startexp, _endexp, _tempexp1, _tempexp2); end
    def pbCommonAnimation(_anim, _battler = nil, _target = nil); end
    def pbAnimation(_anim, _user, _target, _hitnum = 0); end
    # Message-ish calls: return values are checked by some callers.
    def pbDisplayMessage(_msg, _brief = false, &_block); end
    def pbDisplay(_msg, &_block); end
    def pbDisplayBrief(_msg); end
    def pbDisplayPaused(_msg); end
    def pbDisplayConfirm(_msg); return true; end
    def pbConfirm(_msg); return false; end
    def pbMessage(_msg); return ""; end
    def pbShowCommands(_idxBattler, _commands, _firstc); return -1; end
    def pbCommandMenu(_idxBattler); return 0; end
    def pbFightMenu(_idxBattler, _firstMoveIndex); return -1; end
    def pbFightMenuDefault(_idxBattler); return -1; end
    def pbMachineMenu(_idxBattler); return -1; end
    def pbItemMenu(_idxBattler); return -1; end
    def pbPartyScreen(*_a); return -1; end
    def pbSummary(_idxBattler); end
    def pbUseItem(_battler, _item); end
    def pbReturnToBall(_idxBattler); end
    def pbSendOut(_idxBattler, _sendOutBattler); end
    # Anything not anticipated: accept and continue. Returning nil is right
    # for void calls; callers that branch on a scene return value are rare and
    # always have non-scene paths in logic we run.
    def method_missing(_name, *_args, &_block); end
    def respond_to_missing?(_name, _include_private = false); return true; end
  end

  #---------------------------------------------------------------------------
  # Deterministic, instrumented RNG.
  #
  # Policies:
  #   :free      — draw from a seeded Mersenne stream (replay/probe mode)
  #   :median    — every roll returns max/2 (expectation-collapsed world)
  #   :min / :max— every roll returns 0 / max-1
  #   :pinned    — rolls matching recorded indices are pinned to given values,
  #                others take the policy default (for outcome enumeration)
  #
  # Every drawn roll is recorded as [value, max, stack_tag]. The twin exposes
  # the log so the search can identify which roll is the accuracy check, the
  # damage variance roll, the crit roll, etc., and compute exact branch
  # probabilities.
  #---------------------------------------------------------------------------
  class DeterministicRNG
    attr_reader :policy, :log

    def initialize(seed: 0, policy: :median, pinned: {})
      @seed    = seed
      @policy  = policy
      @pinned  = pinned     # {roll_index => value}
      @rng     = Random.new(seed)
      @log     = []
    end

    def rand(max = nil)
      idx = @log.size
      if @pinned.key?(idx)
        v = @pinned[idx]
      else
        case @policy
        when :free   then v = max ? @rng.rand(max) : @rng.rand
        when :median then v = max ? max / 2 : 0.5
        when :min    then v = max ? 0 : 0.0
        when :max    then v = max ? max - 1 : 0.999999
        else raise ArgumentError, "unknown policy #{policy}"
        end
      end
      v = 0 if !v.is_a?(Float) && v.negative?
      v = max - 1 if max && v.is_a?(Integer) && v >= max
      @log.push([v, max, caller[1, 4].join("|")])
      return v
    end
  end

  #---------------------------------------------------------------------------
  # The twin battle. All RNG goes through one DeterministicRNG; both pbRandom
  # and rand are covered (the multiplayer sync rework routes rand through
  # anil_rework_rng if set — we set it, and it calls our RNG for both paths).
  #---------------------------------------------------------------------------
  # All coach behaviour that a battle instance needs on top of the real
  # engine. Defined as a module so BOTH paths share one implementation:
  #   * TwinBattle (headless construction from parties), and
  #   * TwinFactory.from_live (Marshal snapshot of a live battle, extended
  #     with this module — the snapshot keeps its original battle class,
  #     preserving format-specific behaviour like Battle Arena's).
  module TwinBehavior
    attr_accessor :coach_rng
    attr_writer :turnCount
    attr_accessor :coach_next_replacements  # {battler_index => party_index}
    attr_accessor :coach_events             # informational events (msg strings)

    def init_coach_ivars(rng)
      @coach_rng = rng || DeterministicRNG.new(policy: :median)
      @coach_next_replacements = {}
      @coach_events = []
    end
  end

  class TwinBattle < Battle
    include TwinBehavior

    def initialize(scene, p1, p2, player, opponent, rng: nil)
      init_coach_ivars(rng)
      @coach_rng = rng || DeterministicRNG.new(policy: :median)
      @coach_next_replacements = {}
      @coach_events = []
      super(scene, p1, p2, player, opponent)
      # Route the multiplayer-sync patched rand/pbRandom into our RNG.
      self.anil_rework_rng = CoachRNGAdapter.new(@coach_rng) if respond_to?(:anil_rework_rng=)
    end

    # The AnilLanRework BattleRNG duck-type (only what battle code touches).
    class CoachRNGAdapter
      def initialize(rng); @rng = rng; end
      def rand(max = nil); @rng.rand(max); end
      def snapshot; nil; end
      def restore(_x); end
    end

    def pbRandom(x = nil)
      return @coach_rng.rand(x)
    end

    def rand(x = nil)
      return @coach_rng.rand(x)
    end

    def pbAIRandom(x = nil)
      return @coach_rng.rand(x)
    end

    # Exp gain is meaningless in a twin; the bookkeeping touches the player's
    # real party and storage. Silently no-op at the source of the chain.
    def pbGainExp; end

    # Dex registration is out-of-battle bookkeeping (it reads the player's
    # pokedex); a twin must not mutate anything outside itself.
    def pbSetSeen(_battler); end

    def pbSetCaught(_battler); end

    def pbSetDefeated(_battler); end

    # End-of-battle bookkeeping (money, storage) has no place in a twin.
    def pbEndOfBattle; end

    # Forced replacement after a faint: instead of opening a party screen
    # (there is no UI in a twin), use the replacement the controller
    # pre-registered for this battler; if none, auto-pick the first able party
    # member (documented policy; the search may enumerate replacements via
    # TurnDriver#step!'s replacements argument instead).
    def pbGetReplacementPokemonIndex(idxBattler, random = false)
      preset = @coach_next_replacements[idxBattler]
      return preset if !preset.nil? && pbCanSwitchIn?(idxBattler, preset)
      party = pbParty(idxBattler)
      idx_start, _idx_end = pbTeamIndexRangeFromBattlerIndex(idxBattler)
      (idx_start...party.length).each do |i|
        next if !party[i] || !party[i].able?
        next if @battlers.any? { |b| b && !b.fainted? && b.pokemonIndex == i && b.index % 2 == idxBattler % 2 }
        return i
      end
      return -1
    end

    # Catch-all observation: collect displayed messages (they are legitimate
    # client-visible information; useful for belief updates and debugging).
    def pbDisplay(msg, &block)
      @coach_events.push(msg) if msg.is_a?(String)
      super
    end

    def pbDisplayMessage(msg, &block)
      @coach_events.push(msg) if msg.is_a?(String)
      super
    end

    def pbDisplayBrief(msg)
      @coach_events.push(msg) if msg.is_a?(String)
      super
    end
  end

  #---------------------------------------------------------------------------
  # Minimal trainer stand-ins (headless; in-game the real objects are used).
  #---------------------------------------------------------------------------
  # Interface matched to what battle/AI code calls on trainers:
  # skill helpers, has_skill_flag, badge_count, party, win/lose text.
  class DummyTrainer
    attr_reader :name, :trainertype, :skill_level, :flags, :party

    def initialize(name = "Foe", trainertype = 0, skill_level = 100, flags: [], badges: 8)
      @name = name
      @trainertype = trainertype
      @skill_level = skill_level
      @flags = flags
      @badges = badges
      @party = []
    end

    def full_name; @name; end
    def id; 0; end
    def badge_count; @badges.nil? ? 8 : @badges; end
    def win_text; ""; end
    def lose_text; ""; end
    def high_skill?; @skill_level >= 48; end
    def medium_skill?; @skill_level >= 32; end
    def low_skill?; @skill_level < 32; end
    def has_skill_flag?(flag)
      return true if @skill_level >= 100
      @flags.include?(flag.to_s)
    end
  end

  #---------------------------------------------------------------------------
  # Builds a twin from parties (headless or live). For the live battle we copy
  # the parties' Pokemon (deep) and reproduce field/side/battler state.
  #---------------------------------------------------------------------------
  module TwinFactory
    module_function

    # Deep-copies a Pokemon using the real class. Marshal is used when the
    # object is dumpable (fast, exact); otherwise falls back to manual copy.
    def dup_pokemon(pkmn)
      return Marshal.load(Marshal.dump(pkmn))
    rescue StandardError, TypeError
      copy = pkmn.clone
      return copy
    end

    def dup_party(party)
      out = []
      party.each do |p|
        out << (p.nil? ? nil : dup_pokemon(p))
      end
      out
    end

    # Headless construction from explicit parties.
    def build(party1, party2, player: nil, opponent: nil, rng: nil,
              environment: :None, weather: nil, terrain: nil, can_switch: true)
      scene = NullScene.new
      battle = TwinBattle.new(
        scene, dup_party(party1), dup_party(party2), player, opponent, rng: rng
      )
      battle.environment = environment
      battle.canSwitch = can_switch
      battle.expGain = false
      battle.moneyGain = false
      battle
    end

    def from_live(live, idx_viewpoint, rng: nil)
      snapshot_twin(live, rng: rng)
    end

    # Builds a twin from a live battle by Marshal-snapshotting the ENTIRE
    # battle object (with the scene swapped out for a NullScene, since real
    # scenes hold undumpable RGSS sprites). This copies every piece of state
    # the engine itself maintains — choices, damage states, phase flags, party
    # order, AI, field/side/position effects — without enumerating ivars by
    # hand, so nothing can be missed or re-bound incorrectly. The live battle
    # is restored before returning (only its @scene is touched, briefly).
    #
    # Raises if the battle graph holds anything else undumpable (e.g. a
    # network socket in a multiplayer battle); the caller treats that as
    # "coach unavailable for this battle".
    def snapshot_twin(live, rng: nil)
      saved_scene = live.instance_variable_get(:@scene)
      live.instance_variable_set(:@scene, NullScene.new)
      begin
        copy = Marshal.load(Marshal.dump(live))
      ensure
        live.instance_variable_set(:@scene, saved_scene)
      end
      copy.extend(TwinBehavior)
      copy.init_coach_ivars(rng)
      # Route the multiplayer-sync patched rand/pbRandom into our RNG.
      if copy.respond_to?(:anil_rework_rng=)
        copy.anil_rework_rng = TwinBattle::CoachRNGAdapter.new(copy.coach_rng)
      end
      copy
    end

    # Legacy field-by-field path kept for reference/debugging only.
    def from_live_fieldwise(live, idx_viewpoint, rng: nil)
      # Parties are duplicated so the twin can damage them freely.
      party1 = live.party1.map { |p| p.nil? ? nil : dup_pokemon(p) }
      party2 = live.party2.map { |p| p.nil? ? nil : dup_pokemon(p) }
      player = live.player
      opponent = live.opponent
      twin = TwinBattle.new(NullScene.new, party1, party2, player, opponent, rng: rng)
      twin.environment = live.environment
      twin.backdrop = live.backdrop
      twin.time = live.time
      twin.internalBattle = live.internalBattle
      twin.canRun = live.canRun
      twin.canSwitch = live.canSwitch
      twin.canLose = live.canLose
      twin.switchStyle = live.switchStyle
      twin.showAnims = false
      twin.expGain = false
      twin.moneyGain = false
      twin.rules = live.rules
      twin.turnCount = live.turnCount
      # Field / side / position effects.
      copy_effect_container(live.field, twin.field)
      copy_effect_container(live.sides[0], twin.sides[0])
      copy_effect_container(live.sides[1], twin.sides[1])
      live.positions.each_with_index do |pos, i|
        twin.positions[i] ||= Battle::BattlerPosition.new(i % 2, i / 2) if pos && !twin.positions[i]
        copy_effect_container(pos, twin.positions[i]) if pos && twin.positions[i]
      end
      # Rebuild battlers to mirror the live ones.
      twin.party1order = live.party1order.dup
      twin.party2order = live.party2order.dup
      twin.party1starts = live.party1starts.dup
      twin.party2starts = live.party2starts.dup
      live.battlers.each_with_index do |lb, i|
        next unless lb
        pkmn = party1[lb.pokemonIndex] || party2[lb.pokemonIndex]
        # Recreate battler bound to the twin battle and same party pokemon.
        nb = Battle::Battler.new(twin, lb.pokemonIndex)
        lb.instance_variables.each do |iv|
          val = lb.instance_variable_get(iv)
          case iv
          when :@battle then nil                     # keep twin binding
          when :@pokemon then nb.pokemon            # fresh battler's own
          else nb.instance_variable_set(iv, copy_value(val))
          end
        end
        twin.battlers[i] = nb
      end
      twin.megaEvolution = Marshal.load(Marshal.dump(live.megaEvolution)) rescue live.megaEvolution.dup
      twin.lastMoveUsed = live.lastMoveUsed
      twin.lastMoveUser = live.lastMoveUser
      twin.fainted_count = live.fainted_count.dup if live.respond_to?(:fainted_count)
      twin.abils_triggered = live.abils_triggered.map(&:dup) if live.respond_to?(:abils_triggered)
      twin.rage_hit_count = live.rage_hit_count.map(&:dup) if live.respond_to?(:rage_hit_count)
      twin
    end

    def copy_effect_container(src, dst)
      return unless src && dst
      src.instance_variables.each do |iv|
        dst.instance_variable_set(iv, copy_value(src.instance_variable_get(iv)))
      end
    end

    def copy_value(v)
      case v
      when NilClass, TrueClass, FalseClass, Numeric, Symbol, String then v
      when Battle::Battler then v   # battler refs rebound by caller if needed
      else
        begin
          Marshal.load(Marshal.dump(v))
        rescue StandardError, TypeError
          v.clone
        end
      end
    end
  end
end
