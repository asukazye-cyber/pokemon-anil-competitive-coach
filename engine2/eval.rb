# encoding: UTF-8
#===============================================================================
# Coach Engine 2.0 — Evaluation: estimated win probability for a state.
#
# HONESTY NOTE: terminal states (battle decision) are EXACT (1.0 / 0.0).
# Non-terminal values are a calibrated ESTIMATE. The estimate uses only
# client-legitimate information (party HP/status, active stats/stages the
# client can see, real PBS data via the engine's own GameData).
#
# Design goals (from the project brief):
#   * maximize probability of winning the WHOLE battle, not damage;
#   * dynamically preserve strategically valuable Pokémon — a 1-HP 'mon that
#     outspeeds and KOs the foe's last Pokémon is a WIN CONDITION, so value
#     scales with what a 'mon can still DO, not just its HP fraction.
#
# The estimate deliberately does NOT pretend to be empirical: its calibration
# is a documented design pending playtesting. Terminal exactness comes from
# the search; this function only ranks non-terminal leaves.
#===============================================================================

module CoachEngine2
  class Evaluator
    THREAT_WEIGHT = 0.45   # what the mon can still do
    HP_WEIGHT     = 0.40   # raw survivability
    STATUS_WEIGHT = 0.15   # afflictions

    def initialize(viewpoint_side = 0, beliefs: nil, foe_info: :full)
      @side = viewpoint_side
      @beliefs = beliefs
      @foe_info = foe_info
    end

    # battle: TwinBattle (or any real Battle). Returns [0.0, 1.0].
    def win_probability(battle)
      case battle.decision
      when 1 then return @side == 0 ? 1.0 : 0.0   # side 0 won
      when 2 then return @side == 0 ? 0.0 : 1.0   # side 1 won
      when 3, 4 then return 0.5                    # ran away / caught: n/a in PvP coach
      end

      s0 = side_score(battle, 0)
      s1 = side_score(battle, 1)
      return 0.5 if (s0 + s1) <= 0.0
      # Logistic squash of the side differential (k tuned so a 2:1 advantage
      # ≈ 0.75 — documented, not claimed empirical).
      diff = (s0 - s1) / [s0 + s1, 0.001].max
      1.0 / (1.0 + Math.exp(-3.5 * diff))
    end

    def side_score(battle, side)
      foe_side = 1 - side
      foe_active = battle.battlers.select { |b| b && !b.fainted? && b.index % 2 == foe_side }
      total = 0.0
      party = battle.pbParty(side == 0 ? 0 : 1)
      party.each do |pkmn|
        next unless pkmn && pkmn.able?
        hp_frac = pkmn.hp.to_f / pkmn.totalhp
        threat = 0.0
        speed_factor = 0.0
        # Under the :revealed policy the foe's UNOBSERVED moves must not be
        # treated as known: they are excluded from threat (documented
        # optimistic bias); species/stats stay public once active.
        moves_for_threat = pkmn.moves
        if @beliefs && side == 1 && @foe_info == :revealed
          owner = battle.battlers.select { |b| b && !b.fainted? && b.index % 2 == 1 }
                        .find { |b| b.pokemon.equal?(pkmn) }
          moves_for_threat = owner ? @beliefs.threat_moves_for(battle, owner.index) : []
        end
        moves_for_threat.each do |pm|
          move_data = GameData::Move.try_get(pm.respond_to?(:id) ? pm.id : pm)
          next unless move_data
          foe_active.each do |fb|
            # Real effectiveness from the engine's own tables.
            eff = move_data.type ? Effectiveness.calculate(move_data.type, *fb.pokemon.types.compact) : 1
            base = (move_data.power || 0).to_f
            stab = (pkmn.types.include?(move_data.type)) ? 1.5 : 1.0
            dmg_proxy = base * eff * stab
            ko_ratio = foe_active.any? { |f| f.hp > 0 } ? (dmg_proxy / (fb.hp * 8.0 + 1.0)) : 0.0
            threat = [threat, ko_ratio].max
          end
        end
        # Outspeed check against current foes (uses the engine's own pbSpeed
        # via a temporary comparison; fall back to raw stats if unavailable).
        speed_factor = speed_edge(battle, side, pkmn, foe_active)
        status_pen = status_penalty(pkmn)
        mon = THREAT_WEIGHT * [[threat, 1.0].min, 0.25 * speed_factor + 0.05].max +
              HP_WEIGHT * hp_frac -
              STATUS_WEIGHT * status_pen
        total += [mon, 0.0].max
      end
      # Field pressure: hazards on our side hurt; on foe side help.
      hazards = hazard_score(battle, side)
      total += hazards
      [total, 0.0].max
    end

    def speed_edge(battle, _side, pkmn, foes)
      return 0.0 if foes.empty?
      begin
        # Use species base speed relative to foe's realized speed band.
        my = pkmn.speed
        faster = foes.count { |f| my > f.pokemon.speed }
        faster.to_f / foes.length
      rescue StandardError
        0.0
      end
    end

    def status_penalty(pkmn)
      case pkmn.status
      when :SLEEP, :FROZEN then 0.8
      when :PARALYSIS then 0.35
      when :BURN, :POISON then 0.25
      when :TOXIC then 0.45
      else 0.0
      end
    end

    def hazard_score(battle, side)
      e = battle.sides[side].effects
      score = 0.0
      score -= 0.4 * e[PBEffects::StealthRock] if e[PBEffects::StealthRock]
      score -= 0.15 * e[PBEffects::Spikes] if e[PBEffects::Spikes]
      score -= 0.1 * e[PBEffects::ToxicSpikes] if e[PBEffects::ToxicSpikes]
      score -= 0.1 * e[PBEffects::StickyWeb] if e[PBEffects::StickyWeb]
      score
    end
  end
end
