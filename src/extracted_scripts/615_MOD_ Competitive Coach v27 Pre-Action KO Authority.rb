#===============================================================================
# Competitive Turn Coach v27 - Pre-Action KO Authority
# Root tactical legality/survival gate using the game's own live Battle::AI
# rough_damage and rough_priority. Battle-only; no map/input/player hooks.
#===============================================================================
class Battle
  # True when foe action is resolved before our move under live battle ordering.
  def competitive_coach_v27_foe_first?(our_ai, foe_ai, our_move, foe_move)
    return false if !our_ai || !foe_ai || !our_move || !foe_move
    our_ai.send(:set_up_move_check,our_move) rescue nil
    foe_ai.send(:set_up_move_check,foe_move) rescue nil
    op=(our_ai.move.rough_priority(our_ai.user) rescue our_move.priority.to_i)
    fp=(foe_ai.move.rough_priority(foe_ai.user) rescue foe_move.priority.to_i)
    return true if fp>op
    return false if op>fp
    # Let Essentials' own AI battlers decide effective speed ordering. This keeps
    # Tailwind/paralysis/abilities/items/Trick Room behavior aligned with the game.
    foe_fast=(foe_ai.user.faster_than?(our_ai.user) rescue nil)
    return foe_fast unless foe_fast.nil?
    fs=(@battlers[foe_ai.user.index].pbSpeed rescue 0)
    os=(@battlers[our_ai.user.index].pbSpeed rescue 0)
    trick=(@field.effects[PBEffects::TrickRoom].to_i>0 rescue false)
    return trick ? fs<os : fs>os
  rescue
    false
  end

  # Enumerate live known foe moves and ask the shipped high-skill AI damage
  # estimator whether any can KO before the proposed move executes.
  def competitive_coach_v27_pre_action_threat(idxBattler, our_move)
    user=@battlers[idxBattler] rescue nil
    return nil if !user || user.fainted? || !our_move
    foes=allOtherSideBattlers(idxBattler) rescue []
    foe=Array(foes).find{|b| b && !b.fainted?}
    return nil if !foe
    our_ai=competitive_coach_v7_ai(idxBattler)
    foe_ai=competitive_coach_v7_ai(foe.index)
    return nil if !our_ai || !foe_ai
    worst=nil
    foe.moves.each_with_index do |fm,i|
      next if !fm || (fm.pp.to_i<=0 rescue false) || !fm.damagingMove?
      dmg=competitive_coach_v7_damage(foe_ai,fm,user)
      next if dmg<=0
      first=competitive_coach_v27_foe_first?(our_ai,foe_ai,our_move,fm)
      ko=(dmg>=user.hp.to_i)
      row={name:fm.name.to_s,index:i,damage:dmg,ko:ko,foe_first:first,
           priority:(foe_ai.move.rough_priority(foe_ai.user) rescue fm.priority.to_i)}
      if first && ko
        worst=row if !worst || row[:damage]>worst[:damage]
      end
    end
    worst
  rescue => e
    PBDebug.log("[CompetitiveCoachV27 threat] #{e.class}: #{e.message}") rescue nil
    nil
  end

  alias competitive_coach_v27_v26_recommendation competitive_coach_recommendation
  def competitive_coach_recommendation(idxBattler)
    base=competitive_coach_v27_v26_recommendation(idxBattler)
    return base if !base
    user=@battlers[idxBattler] rescue nil
    return base if !user || user.fainted? || !pbOwnedByPlayer?(idxBattler)

    # Build the same root action universe as v26, but give pre-action death
    # absolute authority over ordinary move recommendations.
    ctx=competitive_coach_team_context(idxBattler) rescue nil
    foe=(ctx[:foes][0] rescue nil)
    state=(competitive_coach_v22_state(idxBattler,ctx,user,foe) rescue nil)
    if state && foe
      state[:weather]=(@field.weather rescue nil)
      state[:terrain]=(@field.terrain rescue nil)
      state[:trick_room]=(@field.effects[PBEffects::TrickRoom].to_i rescue 0)
      acts=competitive_coach_v26_actions(state,true)
      safe_moves=[]
      lethal_moves=[]
      acts.each do |a|
        next if a[:kind]!=:move
        live_move=user.moves.find{|m| (m.id rescue nil)==(a[:move][:id] rescue nil)} rescue nil
        live_move ||= user.moves.find{|m| m && m.name.to_s==a[:name].to_s} rescue nil
        threat=competitive_coach_v27_pre_action_threat(idxBattler,live_move)
        if threat
          lethal_moves << [a,threat]
        else
          safe_moves << a
        end
      end

      # If v26 selected a move that literally cannot execute against a known
      # faster/prioritized KO reply, veto it. Prefer a safe move, then a v26-safe
      # switch/sack. This is a survival legality gate, not a soft heuristic.
      chosen=acts.find{|a| a[:name].to_s==base[:best].to_s}
      if chosen && chosen[:kind]==:move
        lm=lethal_moves.find{|x| x[0][:name].to_s==chosen[:name].to_s}
        if lm
          alternatives=safe_moves + acts.select{|a| [:switch,:sack].include?(a[:kind])}
          replacement=alternatives.max_by{|a| a[:utility].to_f}
          if replacement
            base[:best]=replacement[:name]
            base[:kind]=replacement[:kind]
            base[:warning]="#{lm[1][:name]} age antes e pode nocautear antes da acao"
            base[:pre_action_ko_veto]=true
            base[:vetoed_action]=chosen[:name]
            base[:lethal_reply]=lm[1][:name]
            base[:lethal_reply_damage]=lm[1][:damage]
          else
            base[:warning]="AMEACA DE KO ANTES DE AGIR: #{lm[1][:name]}"
            base[:pre_action_ko_veto]=true
            base[:lethal_reply]=lm[1][:name]
          end
        end
      end
    end
    base[:engine]='V27-PRE-ACTION-KO-AUTHORITY'
    base[:initiative_authority]=true
    base[:battle_only]=true
    base
  rescue => e
    PBDebug.log("[CompetitiveCoachV27] #{e.class}: #{e.message}") rescue nil
    base
  end
end
