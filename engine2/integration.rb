# encoding: UTF-8
#===============================================================================
# Coach Engine 2.0 — in-game integration layer.
#
# This is the ONLY piece of Engine 2.0 that touches game-facing classes, and
# it does so by defining (not aliasing) one method that older Coach layers
# also defined: Battle#competitive_coach_recommendation. Because this script
# is loaded last, its definition wins — no alias chains, no edits to any
# existing script section.
#
# Data flow (battle model strictly separate from search/presentation):
#   live battle --Marshal snapshot--> CoachEngine2 twin (TwinBehavior)
#     -> ActionSpace (engine-decided legality) -> Search (real rounds only)
#     -> Evaluator win probability -> HUD hash
#
# Failure policy: ANY exception in this layer falls back to the previous
# (v27) recommendation method captured at load time. The battle can never
# break because of the coach.
#===============================================================================
module CoachEngine2
  #--------------------------------------------------------------------------
  # User-facing configuration. Flip `enabled` to false to remove Engine 2.0
  # from the game entirely (the pre-2.0 Coach v27 chain then serves the HUD
  # again, unchanged).
  #--------------------------------------------------------------------------
  CONFIG = {
    enabled: true,   # default; runtime switch is CoachEngine2.enabled
    # :desktop, :joiplay or nil (auto-detect). JoiPlay/Android gets smaller
    # budgets to keep the menu responsive on weaker hardware.
    profile: nil,
    budgets: {
      desktop: { max_depth: 3, node_budget: 600, time_budget_ms: 3000,
                 foe_branching: 5, our_branching: 14,
                 chance: :on, chance_granularity: :coarse, eps: 0.02 },
      joiplay: { max_depth: 2, node_budget: 150, time_budget_ms: 2000,
                 foe_branching: 4, our_branching: 10,
                 chance: :root, chance_granularity: :coarse, eps: 0.03 }
    }.freeze,
    foe_model: :adversarial
  }.freeze

  class << self
    # Runtime on/off switch (CONFIG is frozen). Defaults to CONFIG[:enabled].
    attr_writer :enabled

    def enabled?
      @enabled = CONFIG[:enabled] if @enabled.nil?
      @enabled
    end

    # Best-effort platform detection; anything unusual falls back to desktop.
    def detect_profile
      return CONFIG[:profile] if CONFIG[:profile]
      env = (ENV["ANDROID_ROOT"] rescue nil) || ""
      path = (Dir.pwd rescue ".") || "."
      return :joiplay if env.include?("android") || path.include?("/storage/emulated")
      return :joiplay if defined?(System) && System.respond_to?(:platform) &&
                         System.platform.to_s.downcase.include?("android")
      :desktop
    rescue StandardError
      :desktop
    end

    def budget
      CONFIG[:budgets][detect_profile] || CONFIG[:budgets][:desktop]
    end

    # Computes the Engine 2.0 recommendation for a battler. Returns a HUD
    # hash (best/alternative/confidence_dots/warning) or nil if unavailable.
    def recommend_for(battle, idxBattler)
      return nil unless battle.respond_to?(:battlers)
      battler = battle.battlers[idxBattler]
      return nil if !battler || battler.fainted?
      # Only the player's own side can be coached.
      return nil unless battle.pbOwnedByPlayer?(idxBattler)

      twin = TwinFactory.from_live(battle, idxBattler,
        rng: DeterministicRNG.new(seed: Kernel.rand(2**31), policy: :median))
      result = Search.new(twin, viewpoint_side: 0, config: {
        foe_model: CONFIG[:foe_model]
      }.merge(budget)).recommend
      to_hud(battle, idxBattler, result)
    rescue StandardError => e
      PBDebug.log("[CoachEngine2] unavailable: #{e.class}: #{e.message}") rescue nil
      nil
    end

    private

    def to_hud(battle, idxBattler, result)
      return nil if result.nil? || result.action.nil?
      choice = result.action[idxBattler] || result.action.values.first
      best =
        case choice[0]
        when :UseMove
          mv = GameData::Move.try_get(choice[2].respond_to?(:id) ? choice[2].id : choice[2])
          mv ? mv.real_name.to_s : "Atacar"
        when :SwitchOut
          pkmn = battle.pbParty(idxBattler)[choice[1]]
          pkmn ? "Cambiar: #{pkmn.name}" : "Cambiar"
        else "Atacar"
        end
      alt = "W=#{(result.value * 100).round}%"
      dots = [[(result.value * 5).round, 5].min, 1].max
      warning = nil
      if result.metrics.elapsed_ms > 0
        alt += " d#{result.metrics.max_depth_reached}"
      end
      { best: best, alternative: alt, confidence_dots: dots, warning: warning,
        engine2: true }
    end
  end
end

# Capture the pre-Engine-2.0 recommendation (Coach v27 chain) so it can be
# restored when Engine 2.0 is disabled or fails. This is a method OBJECT, not
# an alias: nothing about the old chain is modified.
unless defined?(CoachEngine2::PRE_2_0_RECOMMENDATION)
  if Battle.method_defined?(:competitive_coach_recommendation)
    CoachEngine2::PRE_2_0_RECOMMENDATION =
      Battle.instance_method(:competitive_coach_recommendation)
  end
end

class Battle
  # Engine 2.0 recommendation entry point (same contract as the Coach chain:
  # returns a HUD hash or nil). Defined last => wins over v19–v27 without
  # touching them.
  def competitive_coach_recommendation(idxBattler)
    fallback = lambda do
      m = CoachEngine2::PRE_2_0_RECOMMENDATION
      return nil if m.nil?
      return m.bind(self).call(idxBattler)
    end
    return fallback.call if !CoachEngine2.enabled?
    # One computation per (battler, turn, HP signature): the HUD may ask
    # several times while the menu is open.
    key = [idxBattler, turnCount,
           @battlers.map { |b| b && !b.fainted? ? b.hp : -1 }]
    @_coach2_cache ||= {}
    @_coach2_cache_key ||= nil
    if @_coach2_cache_key == key
      return @_coach2_cache
    end
    rec = CoachEngine2.recommend_for(self, idxBattler)
    rec = fallback.call if rec.nil?
    @_coach2_cache_key = key
    @_coach2_cache = rec
    rec
  rescue StandardError
    fallback.call
  end
end
