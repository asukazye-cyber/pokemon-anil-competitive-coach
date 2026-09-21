# encoding: UTF-8
#===============================================================================
# Coach Engine 2.0 — ActionSpace: legal action generation.
#
# Legality is decided by the ENGINE'S OWN checks (pbCanChooseMove?,
# pbCanShowFightMenu?, pbCanShowCommands?, pbCanSwitchOut?,
# pbCanChooseNonActive?, pbCanSwitchIn?). No duplicated rules here — if the
# engine allows it in the real command phase, it is legal here, and vice
# versa. Battlers locked into multi-turn moves keep the engine's own choice.
#===============================================================================

module CoachEngine2
  module ActionSpace
    module_function

    # True when the engine itself keeps this battler's choice from the
    # previous round (multi-turn moves like Outrage/charging). The caller
    # must NOT clear or replace that choice.
    def forced_choice?(battle, idxBattler)
      b = battle.battlers[idxBattler]
      return false if b.nil? || b.fainted?
      !battle.pbCanShowCommands?(idxBattler)
    end

    # Legal choices for idxBattler in engine format:
    #   [:UseMove, idxMove, Battle::Move, -1] or [:SwitchOut, idxParty].
    # A fainted battler has NO actions. A locked battler has exactly one:
    # the engine's own current choice.
    def actions_for(battle, idxBattler)
      b = battle.battlers[idxBattler]
      return [] if b.nil? || b.fainted?

      return [battle.choices[idxBattler]] if forced_choice?(battle, idxBattler)

      out = []

      #--- Moves -------------------------------------------------------------
      if battle.pbCanShowFightMenu?(idxBattler)
        b.eachMoveWithIndex do |_m, i|
          next unless battle.pbCanChooseMove?(idxBattler, i, false)
          out.push([:UseMove, i, b.moves[i], -1])
        end
      else
        # Encore or nothing choosable: mirror pbAutoChooseMove exactly.
        idx_encored = b.pbEncoredMoveIndex
        if idx_encored >= 0 && battle.pbCanChooseMove?(idxBattler, idx_encored, false)
          out.push([:UseMove, idx_encored, b.moves[idx_encored], -1])
        else
          out.push([:UseMove, -1, battle.struggle, -1])
        end
      end

      #--- Switches (deliberate, rated actions; a sacrifice is a switch whose
      #    value the search computes honestly, never a hidden default) --------
      begin
        if battle.pbCanSwitchOut?(idxBattler) && battle.pbCanChooseNonActive?(idxBattler)
          party = battle.pbParty(idxBattler)
          party.each_with_index do |pkmn, idx_party|
            next unless pkmn&.able?
            next unless battle.pbCanSwitchIn?(idxBattler, idx_party)
            out.push([:SwitchOut, idx_party])
          end
        end
      rescue StandardError
        nil
      end

      out
    end

    # Struggle in engine choice format (used when a :revealed-policy foe
    # model has no observed moves to choose from).
    def struggle_choice(battle, idxBattler)
      [:UseMove, -1, battle.struggle, -1]
    end

    # Joint actions for one side: array of {idxBattler => choice}.
    # (Single battle = one battler per side → flat list of single-entry hashes.)
    # beliefs: optional BeliefState; when the foe side is generated under the
    # :revealed policy, unobserved moves are excluded (never treated as
    # known) and switches remain full.
    def side_actions(battle, side, beliefs: nil, foe_info: :full)
      idxs = battle.battlers.each_index.select do |i|
        b = battle.battlers[i]
        b && !b.fainted? && (i % 2 == side)
      end
      return [] if idxs.empty?
      per_battler = idxs.map do |i|
        acts = actions_for(battle, i)
        if beliefs && side != 0 && foe_info == :revealed
          acts = acts.select do |c|
            case c[0]
            when :UseMove then c[1] == -1 || beliefs.move_observed?(battle, i, c[2])
            else true   # switches stay available
            end
          end
          # A foe with no observed usable move keeps only switches; if it
          # has none either, Struggle keeps the round valid.
          acts = [struggle_choice(battle, i)] if acts.empty?
        end
        acts
      end
      product = [{}]
      idxs.each_with_index do |i, k|
        return [] if per_battler[k].empty?   # a side with no action can't act
        product = product.flat_map { |base| per_battler[k].map { |c| base.merge(i => c) } }
      end
      product
    end
  end
end
