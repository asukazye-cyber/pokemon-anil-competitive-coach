class Battle
  #=============================================================================
  # Clear commands
  #=============================================================================
  def pbClearChoice(idxBattler)
    @choices[idxBattler] = [] if !@choices[idxBattler]
    @choices[idxBattler][0] = :None
    @choices[idxBattler][1] = 0
    @choices[idxBattler][2] = nil
    @choices[idxBattler][3] = -1
  end

  def pbCancelChoice(idxBattler)
    # If idxBattler's choice was to use an item, return that item to the Bag
    if @choices[idxBattler][0] == :UseItem
      item = @choices[idxBattler][1]
      pbReturnUnusedItemToBag(item, idxBattler) if item
    end
    # If idxBattler chose to Mega Evolve, cancel it
    pbUnregisterMegaEvolution(idxBattler)
    # Clear idxBattler's choice
    pbClearChoice(idxBattler)
  end

  #=============================================================================
  # Use main command menu (Fight/Pokémon/Bag/Run)
  #=============================================================================
  def pbCommandMenu(idxBattler, firstAction)
    return @scene.pbCommandMenu(idxBattler, firstAction)
  end

  #=============================================================================
  # Check whether actions can be taken
  #=============================================================================
  def pbCanShowCommands?(idxBattler)
    return false if @battlers[idxBattler].isCommander?
    battler = @battlers[idxBattler]
    return false if !battler || battler.fainted?
    return false if battler.usingMultiTurnAttack?
    return true
  end

  def pbCanShowFightMenu?(idxBattler)
    battler = @battlers[idxBattler]
    # Encore
    return false if battler.effects[PBEffects::Encore] > 0
    # No moves that can be chosen (will Struggle instead)
    usable = false
    battler.eachMoveWithIndex do |_m, i|
      next if !pbCanChooseMove?(idxBattler, i, false)
      usable = true
      break
    end
    return usable
  end

  #=============================================================================
  # Use sub-menus to choose an action, and register it if is allowed
  #=============================================================================
  # Returns true if a choice was made, false if cancelled.
  def pbFightMenu(idxBattler)
    # Auto-use Encored move or no moves choosable, so auto-use Struggle
    return pbAutoChooseMove(idxBattler) if !pbCanShowFightMenu?(idxBattler)
    # Battle Palace only
    return true if pbAutoFightMenu(idxBattler)
    # Regular move selection
    ret = false
    @scene.pbFightMenu(idxBattler, pbCanMegaEvolve?(idxBattler)) do |cmd|
      case cmd
      when -1   # Cancel
      when -2   # Toggle Mega Evolution
        pbToggleRegisteredMegaEvolution(idxBattler)
        next false
      when -3   # Shift
        pbUnregisterMegaEvolution(idxBattler)
        pbRegisterShift(idxBattler)
        ret = true
      else      # Chose a move to use
        next false if cmd < 0 || !@battlers[idxBattler].moves[cmd] ||
                      !@battlers[idxBattler].moves[cmd].id
        next false if !pbRegisterMove(idxBattler, cmd)
        next false if !singleBattle? &&
                      !pbChooseTarget(@battlers[idxBattler], @battlers[idxBattler].moves[cmd])
        ret = true
      end
      next true
    end
    return ret
  end

  def pbAutoFightMenu(idxBattler); return false; end

  def pbChooseTarget(battler, move)
    target_data = move.pbTarget(battler)
    idxTarget = @scene.pbChooseTarget(battler.index, target_data)
    return false if idxTarget < 0
    pbRegisterTarget(battler.index, idxTarget)
    return true
  end

  def pbItemMenu(idxBattler, firstAction)
    if !@internalBattle
      pbDisplay(_INTL("Aquí no se pueden usar objetos."))
      return false
    end
    ret = false
    @scene.pbItemMenu(idxBattler, firstAction) do |item, useType, idxPkmn, idxMove, itemScene|
      next false if !item
      battler = pkmn = nil
      case useType
      when 1, 2   # Use on Pokémon/Pokémon's move
        next false if !ItemHandlers.hasBattleUseOnPokemon(item)
        battler = pbFindBattler(idxPkmn, idxBattler)
        pkmn    = pbParty(idxBattler)[idxPkmn]
        next false if !pbCanUseItemOnPokemon?(item, pkmn, battler, itemScene)
      when 3   # Use on battler
        next false if !ItemHandlers.hasBattleUseOnBattler(item)
        battler = pbFindBattler(idxPkmn, idxBattler)
        pkmn    = battler.pokemon if battler
        next false if !pbCanUseItemOnPokemon?(item, pkmn, battler, itemScene)
      when 4   # Poké Balls
        next false if idxPkmn < 0
        battler = @battlers[idxPkmn]
        pkmn    = battler.pokemon if battler
      when 5   # No target (Poké Doll, Guard Spec., Launcher items)
        battler = @battlers[idxBattler]
        pkmn    = battler.pokemon if battler
      else
        next false
      end
      next false if !pkmn
      next false if !ItemHandlers.triggerCanUseInBattle(item, pkmn, battler, idxMove,
                                                        firstAction, self, itemScene)
      next false if !pbRegisterItem(idxBattler, item, idxPkmn, idxMove)
      ret = true
      next true
    end
    return ret
  end

  def pbPartyMenu(idxBattler)
    ret = -1
    if @debug
      ret = @battleAI.pbDefaultChooseNewEnemy(idxBattler)
    else
      ret = pbPartyScreen(idxBattler, false, true, true)
    end
    battler = @battlers[idxBattler]
    @battlers[idxBattler].refresh_moves if !battler.effects[PBEffects::Transform]
    return ret >= 0
  end

  def pbRunMenu(idxBattler)
    # Regardless of succeeding or failing to run, stop choosing actions
    return pbRun(idxBattler) != 0
  end

  def pbCallMenu(idxBattler)
    return pbRegisterCall(idxBattler)
  end

  def pbDebugMenu
    pbBattleDebug(self)
    @scene.pbRefreshEverything
    allBattlers.each { |b| b.pbCheckFormOnWeatherChange }
    pbEndPrimordialWeather
    allBattlers.each { |b| b.pbAbilityOnTerrainChange }
    allBattlers.each do |b|
      b.pbCheckFormOnMovesetChange
      b.pbCheckFormOnStatusChange
    end
  end

  #=============================================================================
  # Command phase
  #=============================================================================
  def pbCommandPhase
    @command_phase = true
    @scene.pbBeginCommandPhase
    # Reset choices if commands can be shown
    @battlers.each_with_index do |b, i|
      next if !b
      pbClearChoice(i) if pbCanShowCommands?(i)
    end
    # Reset choices to perform Mega Evolution if it wasn't done somehow
    2.times do |side|
      @megaEvolution[side].each_with_index do |megaEvo, i|
        @megaEvolution[side][i] = -1 if megaEvo >= 0
      end
    end
    # Choose actions for the round (player first, then AI)
    pbCommandPhaseLoop(true)    # Player chooses their actions
    if @decision != 0   # Battle ended, stop choosing actions
      @command_phase = false
      return
    end
    pbCommandPhaseLoop(false)   # AI chooses their actions
    @command_phase = false
  end

  def pbCommandPhaseLoop(isPlayer)
    # NOTE: Doing some things (e.g. running, throwing a Poké Ball) takes up all
    #       your actions in a round.
    actioned = []
    idxBattler = -1
    loop do
      break if @decision != 0   # Battle ended, stop choosing actions
      idxBattler += 1
      break if idxBattler >= @battlers.length
      next if !@battlers[idxBattler] || pbOwnedByPlayer?(idxBattler) != isPlayer
      if @choices[idxBattler][0] != :None || !pbCanShowCommands?(idxBattler)
        # Action is forced, can't choose one
        PBDebug.log_ai("#{@battlers[idxBattler].pbThis} (#{idxBattler}) is forced to use a multi-turn move")
        next
      end
      # AI controls this battler
      if @controlPlayer || !pbOwnedByPlayer?(idxBattler)
        @battleAI.pbDefaultChooseEnemyCommand(idxBattler)
        next
      end
      # Player chooses an action
      actioned.push(idxBattler)
      commandsEnd = false   # Whether to cancel choosing all other actions this round
      loop do
        cmd = pbCommandMenu(idxBattler, actioned.length == 1)
        # If being Sky Dropped, can't do anything except use a move
        if cmd > 0 && @battlers[idxBattler].effects[PBEffects::SkyDrop] >= 0
          pbDisplay(_INTL("¡Caída Libre no deja cambiar a {1}!", @battlers[idxBattler].pbThis(true)))
          next
        end
        case cmd
        when 0    # Fight
          break if pbFightMenu(idxBattler)
        when 1    # Bag
          if pbItemMenu(idxBattler, actioned.length == 1)
            commandsEnd = true if pbItemUsesAllActions?(@choices[idxBattler][1])
            break
          end
        when 2    # Pokémon
          break if pbPartyMenu(idxBattler)
        when 3    # Run
          # NOTE: "Run" is only an available option for the first battler the
          #       player chooses an action for in a round. Attempting to run
          #       from battle prevents you from choosing any other actions in
          #       that round.
          if pbRunMenu(idxBattler)
            commandsEnd = true
            break
          end
        when 4    # Call
          break if pbCallMenu(idxBattler)
        when -2   # Debug
          pbDebugMenu
          next
        when -1   # Go back to previous battler's action choice
          next if actioned.length <= 1
          actioned.pop   # Forget this battler was done
          idxBattler = actioned.last - 1
          pbCancelChoice(idxBattler + 1)   # Clear the previous battler's choice
          actioned.pop   # Forget the previous battler was done
          break
        end
        pbCancelChoice(idxBattler)
      end
      break if commandsEnd
    end
  end
end


#===============================================================================
# Competitive Turn Coach v5 - Full Team Strategy
# Live battle state + complete synchronized PvP rosters. No network request here.
#===============================================================================
class Battle
  def competitive_coach_team_context(idxBattler)
    user=@battlers[idxBattler]
    foes=user ? user.allOpposing.select{|b| b && !b.fainted?} : []
    own_party=Array((pbParty(idxBattler) rescue [])).compact
    foe_party=[]
    if foes.length>0
      foe_party=Array((pbParty(foes[0].index) rescue [])).compact
    end
    # In online PvP, BattleSync hydrates ctx.foe_party and @party2 in real time.
    begin
      if defined?(AnilLanRework::BattleSync)
        ctx=AnilLanRework::BattleSync.active_context rescue nil
        if ctx && ctx.mode==:pvp && ctx.foe_party && !ctx.foe_party.empty?
          foe_party=Array(ctx.foe_party).compact
        end
      end
    rescue
    end
    alive=lambda{|p| !(p.respond_to?(:fainted?) ? p.fainted? : ((p.hp.to_i rescue 1)<=0))}
    {user:user, foes:foes, own_party:own_party, foe_party:foe_party,
     own_alive:own_party.count{|p| alive.call(p)}, foe_alive:foe_party.count{|p| alive.call(p)}}
  rescue
    {user:@battlers[idxBattler],foes:[],own_party:[],foe_party:[],own_alive:0,foe_alive:0}
  end

  def competitive_coach_move_pressure(pkmn, target)
    return 0 if !pkmn || !target || !pkmn.respond_to?(:moves)
    types=(target.types rescue [])
    best=0
    pkmn.moves.each do |m|
      next if !m || ((m.pp.to_i<=0 && m.total_pp.to_i>0) rescue false)
      power=(m.power.to_i rescue 0); next if power<=0
      eff=(Effectiveness.calculate(m.type,*types) rescue 8)
      val=power*eff/8
      # STAB and priority are useful approximations for roster planning.
      val=(val*1.5).to_i if (pkmn.types.include?(m.type) rescue false)
      val+=18 if (m.priority.to_i>0 rescue false)
      best=val if val>best
    end
    best
  rescue; 0; end

  def competitive_coach_roster_value(pkmn, foe_party)
    return 0 if !pkmn
    alive=Array(foe_party).compact.reject{|p| (p.fainted? rescue false)}
    return 0 if alive.empty?
    pressure=0; checks=0
    alive.each do |foe|
      x=competitive_coach_move_pressure(pkmn,foe)
      pressure += [x,220].min
      checks += 1 if x>=120
    end
    hp=(pkmn.totalhp.to_i>0 rescue false) ? pkmn.hp.to_f/pkmn.totalhp : 1.0
    (pressure/[alive.length,1].max/7.0 + checks*7 + hp*12).round
  rescue; 0; end

  # How dangerous a known opponent is to this Pokemon, using the synchronized moveset.
  def competitive_coach_threat(foe, ours)
    return 0 if !foe || !ours
    x=competitive_coach_move_pressure(foe,ours)
    hp=(ours.totalhp.to_i>0 rescue false) ? ours.hp.to_f/ours.totalhp : 1.0
    t=x/3
    t+=18 if x>=180
    t+=12 if hp<0.45 && x>=100
    t
  rescue; 0; end

  # Measures whether a Pokemon is a unique/important answer to remaining threats.
  def competitive_coach_preservation_value(pkmn, foe_party, own_party)
    return 0 if !pkmn
    value=competitive_coach_roster_value(pkmn,foe_party)
    unique=0
    Array(foe_party).each do |foe|
      next if (foe.fainted? rescue false)
      mine=competitive_coach_move_pressure(pkmn,foe)
      next if mine<120
      alternatives=Array(own_party).count do |ally|
        next false if !ally || ally.equal?(pkmn) || (ally.fainted? rescue false)
        competitive_coach_move_pressure(ally,foe)>=120
      end
      unique+=1 if alternatives==0
    end
    value + unique*18
  rescue; 0; end

  def competitive_coach_recommendation(idxBattler)
    return nil if !@battlers[idxBattler] || !pbOwnedByPlayer?(idxBattler)
    ctx=competitive_coach_team_context(idxBattler); user=ctx[:user]; return nil if !user
    ai=Battle::AI.new(self); ai.create_ai_objects
    old_trainer=old_skill=old_flags=nil
    begin
      ai.set_up(idxBattler)
      old_trainer=ai.trainer
      if old_trainer
        old_skill=old_trainer.instance_variable_get(:@skill)
        old_flags=old_trainer.instance_variable_get(:@skill_flags)
        old_trainer.instance_variable_set(:@skill,255)
        old_trainer.instance_variable_set(:@skill_flags,["PredictMoveFailure","ScoreMoves","PreferMultiTargetMoves","HPAware","ConsiderSwitching","ReserveLastPokemon"])
      end
      candidates=[]; best_moves={}
      Array(ai.pbGetMoveScores).each do |choice|
        im,score,it=choice; next if im.nil? || score.nil?
        best_moves[im]=[score.to_i,it] if !best_moves[im] || score.to_i>best_moves[im][0]
      end
      active_pkmn=user.pokemon
      preserve=competitive_coach_preservation_value(active_pkmn,ctx[:foe_party],ctx[:own_party])
      active_foe=ctx[:foes][0]&.pokemon
      incoming=competitive_coach_threat(active_foe,active_pkmn)
      hp=(user.totalhp.to_i>0) ? user.hp.to_f/user.totalhp : 1.0
      preserve_bonus=0
      preserve_bonus += 8 if preserve>=55 && ctx[:foe_alive]>=2
      preserve_bonus += 10 if preserve>=80 && ctx[:foe_alive]>=3
      preserve_bonus += 12 if hp<=0.4 && preserve>=55
      preserve_bonus += 10 if incoming>=65 && preserve>=55

      best_moves.each do |im,data|
        move=user.moves[im] rescue nil; next if !move || move.pp==0
        score=data[0]
        # Robustness bonus: damaging moves useful into several remaining opponents
        # are preferred when the immediate AI scores are close.
        if (move.power.to_i rescue 0)>0 && !ctx[:foe_party].empty?
          good=0; immune=0
          ctx[:foe_party].each do |foe|
            next if (foe.fainted? rescue false)
            eff=(Effectiveness.calculate(move.type,*(foe.types rescue [])) rescue 8)
            good+=1 if eff>8; immune+=1 if eff==0
          end
          score += [good*3,9].min
          score -= [immune*3,9].min
        end
        score-=preserve_bonus if preserve_bonus>0 && score<130
        candidates << [score,move.name.to_s,:move,im,data[1]]
      end

      if @canSwitch && pbCanSwitchOut?(idxBattler)
        party=pbParty(idxBattler)
        switch_wanted=false
        begin
          reserves_ai=ai.get_non_active_party_pokemon(idxBattler)
          switch_wanted=Battle::AI::Handlers.should_switch?(ai.user,reserves_ai,ai,self)
          switch_wanted=false if switch_wanted && Battle::AI::Handlers.should_not_switch?(ai.user,reserves_ai,ai,self)
        rescue; end
        party.each_with_index do |pkmn,i|
          next if !pbCanSwitchIn?(idxBattler,i)
          base=(ai.rate_replacement_pokemon(idxBattler,pkmn,100) rescue nil); next if base.nil?
          roster=competitive_coach_roster_value(pkmn,ctx[:foe_party])
          threat=competitive_coach_threat(active_foe,pkmn)
          keep=competitive_coach_preservation_value(pkmn,ctx[:foe_party],ctx[:own_party])
          adjusted=base.to_i+[roster/4,25].min-(threat/8)
          adjusted += (switch_wanted ? 24 : -10)
          adjusted += preserve_bonus if preserve_bonus>0
          # Avoid throwing a crucial future check into a very dangerous current matchup.
          adjusted -= 10 if keep>=80 && threat>=70
          candidates << [adjusted,"Trocar > #{pkmn.name}",:switch,i,nil]
        end
      end
      candidates.sort!{|x,y| y[0]<=>x[0]}; return nil if candidates.empty?
      best=candidates[0]; alt=candidates.find{|c| c[1]!=best[1]}; gap=alt ? best[0]-alt[0] : 99
      confidence=gap>=25 ? "ALTA" : (gap>=10 ? "MEDIA" : "BAIXA")
      {best:best[1],alternative:(alt ? alt[1] : nil),best_score:best[0],alt_score:(alt ? alt[0] : nil),
       confidence:confidence,kind:best[2],live:true,own_alive:ctx[:own_alive],foe_alive:ctx[:foe_alive],
       full_team:(!ctx[:foe_party].empty?),opponent_known:ctx[:foe_party].length}
    rescue => e
      PBDebug.log("[CompetitiveCoachV5] #{e.class}: #{e.message}") rescue nil
      nil
    ensure
      if old_trainer
        old_trainer.instance_variable_set(:@skill,old_skill) if !old_skill.nil?
        old_trainer.instance_variable_set(:@skill_flags,old_flags) if old_flags
      end
    end
  end
end


#===============================================================================
# Competitive Turn Coach v6 - Adversarial Search / Risk Engine
# Rebuilds the decision from the live Battle state every time Fight is opened.
# Uses only data already present in the battle / synchronized PvP context.
#===============================================================================
class Battle
  def competitive_coach_speed_value(pkmn)
    return 0 if !pkmn
    return pkmn.speed.to_i if pkmn.respond_to?(:speed)
    return pkmn.stats[:SPEED].to_i if pkmn.respond_to?(:stats) && pkmn.stats
    0
  rescue; 0; end

  def competitive_coach_hp_ratio(pkmn)
    return 0.0 if !pkmn
    max=(pkmn.totalhp.to_f rescue 0.0)
    return 0.0 if max<=0
    (pkmn.hp.to_f rescue 0.0)/max
  rescue; 0.0; end

  # Estimates how much immediate tactical pressure a known moveset can create.
  # This is intentionally conservative; the normal Essentials AI score remains
  # the primary move evaluator because it knows field/ability/item interactions.
  def competitive_coach_live_pressure(attacker, defender)
    return 0 if !attacker || !defender || !attacker.respond_to?(:moves)
    best=0
    attacker.moves.each do |m|
      next if !m
      next if ((m.pp.to_i<=0 && m.total_pp.to_i>0) rescue false)
      power=(m.power.to_i rescue 0)
      if power>0
        eff=(Effectiveness.calculate(m.type,*(defender.types rescue [])) rescue 8)
        val=power*eff/8
        val=(val*1.5).to_i if (attacker.types.include?(m.type) rescue false)
        val+=22 if (m.priority.to_i>0 rescue false)
        val+=12 if competitive_coach_speed_value(attacker)>competitive_coach_speed_value(defender)
        best=val if val>best
      else
        fc=(m.function_code.to_s rescue "")
        val=0
        val=95 if fc.match?(/RaiseUser.*(Attack|SpAtk|Speed)|SleepTarget|ParalyzeTarget|BurnTarget|PoisonTarget/)
        val=85 if fc.match?(/HealUser|Recover|ProtectUser/)
        best=val if val>best
      end
    end
    best
  rescue; 0; end

  # Full opponent turn evaluation using the same high-skill AI framework that
  # evaluates our legal moves. Returns the best currently plausible reply.
  def competitive_coach_opponent_reply(idxFoe)
    return {score:100,name:nil} if idxFoe.nil? || !@battlers[idxFoe] || @battlers[idxFoe].fainted?
    ai=Battle::AI.new(self); ai.create_ai_objects; ai.set_up(idxFoe)
    tr=ai.trainer
    if tr
      tr.instance_variable_set(:@skill,255)
      tr.instance_variable_set(:@skill_flags,["PredictMoveFailure","ScoreMoves","PreferMultiTargetMoves","HPAware","ConsiderSwitching","ReserveLastPokemon"])
    end
    best=nil
    Array(ai.pbGetMoveScores).each do |choice|
      im,score,_target=choice; next if im.nil? || score.nil?
      mv=@battlers[idxFoe].moves[im] rescue nil; next if !mv || (mv.pp.to_i<=0 rescue false)
      row=[score.to_i,mv.name.to_s,im]
      best=row if !best || row[0]>best[0]
    end
    best ? {score:best[0],name:best[1],index:best[2]} : {score:100,name:nil}
  rescue
    {score:100,name:nil}
  end

  # Position value after the immediate exchange. Positive = strategically good
  # for us. This adds team preservation, HP economy, speed and remaining roster.
  def competitive_coach_position_value(ours, foe, ctx)
    return 0 if !ours
    value=0
    value += (competitive_coach_hp_ratio(ours)*32).round
    value -= (competitive_coach_hp_ratio(foe)*18).round if foe
    value += [competitive_coach_roster_value(ours,ctx[:foe_party]),45].min
    value += 8 if foe && competitive_coach_speed_value(ours)>competitive_coach_speed_value(foe)
    value -= [competitive_coach_live_pressure(foe,ours)/10,30].min if foe
    value
  rescue; 0; end

  def competitive_coach_recommendation(idxBattler)
    return nil if !@battlers[idxBattler] || !pbOwnedByPlayer?(idxBattler)
    ctx=competitive_coach_team_context(idxBattler); user=ctx[:user]; return nil if !user
    foe_battler=ctx[:foes][0]
    foe_pkmn=foe_battler&.pokemon
    reply=competitive_coach_opponent_reply(foe_battler&.index)

    ai=Battle::AI.new(self); ai.create_ai_objects; ai.set_up(idxBattler)
    tr=ai.trainer
    if tr
      tr.instance_variable_set(:@skill,255)
      tr.instance_variable_set(:@skill_flags,["PredictMoveFailure","ScoreMoves","PreferMultiTargetMoves","HPAware","ConsiderSwitching","ReserveLastPokemon"])
    end
    candidates=[]
    seen={}
    active=user.pokemon
    preserve=competitive_coach_preservation_value(active,ctx[:foe_party],ctx[:own_party])
    hp=competitive_coach_hp_ratio(active)
    incoming=competitive_coach_live_pressure(foe_pkmn,active)

    Array(ai.pbGetMoveScores).each do |choice|
      im,raw,target=choice; next if im.nil? || raw.nil?
      mv=user.moves[im] rescue nil; next if !mv || (mv.pp.to_i<=0 rescue false)
      score=raw.to_i
      power=(mv.power.to_i rescue 0)
      if power>0 && foe_pkmn
        pressure=competitive_coach_live_pressure(active,foe_pkmn)
        foe_hp=competitive_coach_hp_ratio(foe_pkmn)
        # Reward lines that remove the opponent before its strongest reply.
        score += 22 if pressure>=180 && foe_hp<=0.45
        score += 12 if pressure>=120 && foe_hp<=0.28
        # Faster attackers can convert offensive pressure more safely.
        score += 7 if competitive_coach_speed_value(active)>competitive_coach_speed_value(foe_pkmn)
        score += 8 if (mv.priority.to_i>0 rescue false) && hp<=0.35
      end
      # If the known opponent has a very strong immediate reply, discourage
      # low-impact lines and preserve unique checks rather than blindly trading.
      danger=[reply[:score].to_i-100,0].max + incoming/6
      score -= [danger/3,24].min if raw.to_i<115
      score -= 12 if preserve>=80 && hp<=0.45 && danger>=35
      # Small whole-roster robustness bonus.
      if power>0 && !ctx[:foe_party].empty?
        good=immune=0
        ctx[:foe_party].each do |fp|
          next if (fp.fainted? rescue false)
          eff=(Effectiveness.calculate(mv.type,*(fp.types rescue [])) rescue 8)
          good+=1 if eff>8; immune+=1 if eff==0
        end
        score += [good*3,9].min-[immune*3,9].min
      end
      key=[:move,im]
      row=[score,mv.name.to_s,:move,im,target]
      seen[key]=row if !seen[key] || row[0]>seen[key][0]
    end
    candidates.concat(seen.values)

    if @canSwitch && pbCanSwitchOut?(idxBattler)
      party=pbParty(idxBattler)
      reserves_ai=(ai.get_non_active_party_pokemon(idxBattler) rescue [])
      switch_wanted=(Battle::AI::Handlers.should_switch?(ai.user,reserves_ai,ai,self) rescue false)
      switch_wanted=false if switch_wanted && (Battle::AI::Handlers.should_not_switch?(ai.user,reserves_ai,ai,self) rescue false)
      party.each_with_index do |pkmn,i|
        next if !pbCanSwitchIn?(idxBattler,i)
        base=(ai.rate_replacement_pokemon(idxBattler,pkmn,100) rescue nil); next if base.nil?
        pos=competitive_coach_position_value(pkmn,foe_pkmn,ctx)
        threat=competitive_coach_live_pressure(foe_pkmn,pkmn)
        keep=competitive_coach_preservation_value(pkmn,ctx[:foe_party],ctx[:own_party])
        adjusted=base.to_i + pos/3 - threat/10
        adjusted += switch_wanted ? 26 : -8
        adjusted += 18 if incoming>=150 && threat<=90
        adjusted += 12 if preserve>=70 && hp<=0.45 && threat<incoming
        adjusted -= 16 if keep>=85 && threat>=150
        candidates << [adjusted,"Trocar > #{pkmn.name}",:switch,i,nil]
      end
    end

    candidates.sort!{|a,b| b[0]<=>a[0]}; return nil if candidates.empty?
    best=candidates[0]; alt=candidates.find{|c| c[1]!=best[1]}
    gap=alt ? best[0]-alt[0] : 99
    confidence=gap>=25 ? "ALTA" : (gap>=10 ? "MEDIA" : "BAIXA")
    warning=nil
    if reply[:name] && (reply[:score].to_i>=125 || incoming>=150)
      warning="Cuidado: #{reply[:name]}"
    elsif preserve>=85 && hp<=0.45
      warning="Preserve #{active.name}"
    end
    {best:best[1],alternative:(alt ? alt[1] : nil),best_score:best[0],alt_score:(alt ? alt[0] : nil),
     confidence:confidence,kind:best[2],live:true,own_alive:ctx[:own_alive],foe_alive:ctx[:foe_alive],
     full_team:(!ctx[:foe_party].empty?),opponent_known:ctx[:foe_party].length,
     opponent_reply:reply[:name],warning:warning,engine:"V6"}
  rescue => e
    PBDebug.log("[CompetitiveCoachV6] #{e.class}: #{e.message}") rescue nil
    nil
  end
end


#===============================================================================
# Competitive Turn Coach v7 - Deep Strategy / Exact Live Damage Layer
# Uses the game's own high-skill AI rough_damage/rough_stat calculations.
# Reads a fresh Battle state every time the Fight menu is opened.
#===============================================================================
class Battle
  def competitive_coach_v7_ai(idx)
    ai=Battle::AI.new(self); ai.create_ai_objects; ai.set_up(idx)
    tr=ai.trainer
    if tr
      tr.instance_variable_set(:@skill,255)
      tr.instance_variable_set(:@skill_flags,["PredictMoveFailure","ScoreMoves","PreferMultiTargetMoves","HPAware","ConsiderSwitching","ReserveLastPokemon"])
    end
    ai
  rescue; nil; end

  def competitive_coach_v7_damage(ai, move, target_battler)
    return 0 if !ai || !move || !target_battler || !move.damagingMove?
    target_ai=(ai.battlers[target_battler.index] rescue nil)
    return 0 if !target_ai
    ai.send(:set_up_move_check,move)
    ai.send(:set_up_move_check_target,target_ai)
    (ai.move.rough_damage.to_i rescue 0)
  rescue; 0; end

  def competitive_coach_v7_speed_order(ai, foe_ai, move=nil)
    return 0 if !ai || !foe_ai
    pri=(ai.move.rough_priority(ai.user) rescue (move.priority.to_i rescue 0))
    # Positive means our action has an ordering advantage before considering foe priority.
    return 2 if pri>0
    return (ai.user.faster_than?(foe_ai) rescue false) ? 1 : -1
  rescue; 0; end

  def competitive_coach_v7_best_reply(idxFoe, our_battler)
    return {score:100,name:nil,damage:0,ko:false,priority:0} if idxFoe.nil? || !@battlers[idxFoe] || @battlers[idxFoe].fainted?
    ai=competitive_coach_v7_ai(idxFoe); return {score:100,name:nil,damage:0,ko:false,priority:0} if !ai
    best=nil
    Array(ai.pbGetMoveScores).each do |ch|
      im,score,_=ch; next if im.nil? || score.nil?
      mv=@battlers[idxFoe].moves[im] rescue nil; next if !mv || (mv.pp.to_i<=0 rescue false)
      dmg=competitive_coach_v7_damage(ai,mv,our_battler)
      pri=(ai.move.rough_priority(ai.user) rescue (mv.priority.to_i rescue 0))
      ko=(our_battler && dmg>=our_battler.hp.to_i)
      value=score.to_i + (ko ? 45 : 0) + [dmg*35/[our_battler.hp.to_i,1].max,35].min + (pri>0 ? 8 : 0)
      row={score:score.to_i,value:value,name:mv.name.to_s,index:im,damage:dmg,ko:ko,priority:pri}
      best=row if !best || row[:value]>best[:value]
    end
    best || {score:100,name:nil,damage:0,ko:false,priority:0}
  rescue; {score:100,name:nil,damage:0,ko:false,priority:0}; end

  def competitive_coach_recommendation(idxBattler)
    return nil if !@battlers[idxBattler] || !pbOwnedByPlayer?(idxBattler)
    ctx=competitive_coach_team_context(idxBattler); user=ctx[:user]; return nil if !user
    foe=ctx[:foes][0]; foe_pkmn=foe&.pokemon; active=user.pokemon
    ai=competitive_coach_v7_ai(idxBattler); return nil if !ai
    foe_ai=(foe ? (ai.battlers[foe.index] rescue nil) : nil)
    reply=competitive_coach_v7_best_reply(foe&.index,user)
    preserve=competitive_coach_preservation_value(active,ctx[:foe_party],ctx[:own_party])
    hp=competitive_coach_hp_ratio(active)
    candidates=[]; seen={}

    Array(ai.pbGetMoveScores).each do |ch|
      im,raw,target=ch; next if im.nil? || raw.nil?
      mv=user.moves[im] rescue nil; next if !mv || (mv.pp.to_i<=0 rescue false)
      score=raw.to_i
      dmg=(foe ? competitive_coach_v7_damage(ai,mv,foe) : 0)
      foe_hp=(foe ? foe.hp.to_i : 0)
      ko=(foe && dmg>=foe_hp && foe_hp>0)
      ratio=(foe_hp>0 ? dmg.to_f/foe_hp : 0.0)
      pri=(ai.move.rough_priority(ai.user) rescue (mv.priority.to_i rescue 0))
      faster=(foe_ai ? (ai.user.faster_than?(foe_ai) rescue false) : false)
      # Exact live tactical layer: guaranteed rough KO, 2HKO pressure and ordering.
      score += 48 if ko
      score += 20 if !ko && ratio>=0.50
      score += 9 if !ko && ratio>=0.33
      score += 12 if ko && (pri>reply[:priority].to_i || (pri==reply[:priority].to_i && faster))
      # A move that lets a known reply KO us is less attractive unless it KOs first.
      if reply[:ko] && !ko
        score -= 34
        score -= 12 if preserve>=70
      end
      # Prefer robust damage when behind; preserve low-HP unique checks when not converting a KO.
      score -= 15 if preserve>=85 && hp<=0.40 && !ko && ratio<0.45
      # Whole-roster coverage remains a tiebreaker rather than the primary score.
      if mv.damagingMove? && !ctx[:foe_party].empty?
        good=0; bad=0
        ctx[:foe_party].each do |fp|
          next if (fp.fainted? rescue false)
          eff=(Effectiveness.calculate(mv.type,*(fp.types rescue [])) rescue 8)
          good+=1 if eff>8; bad+=1 if eff==0
        end
        score += [good*2,6].min-[bad*2,6].min
      end
      row=[score,mv.name.to_s,:move,im,target,{damage:dmg,ko:ko,ratio:ratio}]
      key=[:move,im]; seen[key]=row if !seen[key] || row[0]>seen[key][0]
    end
    candidates.concat(seen.values)

    if @canSwitch && pbCanSwitchOut?(idxBattler)
      party=pbParty(idxBattler)
      reserves=(ai.get_non_active_party_pokemon(idxBattler) rescue [])
      wants=(Battle::AI::Handlers.should_switch?(ai.user,reserves,ai,self) rescue false)
      wants=false if wants && (Battle::AI::Handlers.should_not_switch?(ai.user,reserves,ai,self) rescue false)
      party.each_with_index do |pkmn,i|
        next if !pbCanSwitchIn?(idxBattler,i)
        base=(ai.rate_replacement_pokemon(idxBattler,pkmn,100) rescue nil); next if base.nil?
        roster=competitive_coach_roster_value(pkmn,ctx[:foe_party])
        incoming=competitive_coach_live_pressure(foe_pkmn,pkmn)
        keep=competitive_coach_preservation_value(pkmn,ctx[:foe_party],ctx[:own_party])
        score=base.to_i + [roster,45].min/3 - incoming/10
        score += wants ? 28 : -7
        score += 20 if reply[:ko] && incoming<110
        score += 12 if preserve>=80 && hp<=0.40 && incoming<competitive_coach_live_pressure(foe_pkmn,active)
        score -= 15 if keep>=90 && incoming>=150
        candidates << [score,"Trocar > #{pkmn.name}",:switch,i,nil,{damage:0,ko:false,ratio:0.0}]
      end
    end

    candidates.sort!{|a,b| b[0]<=>a[0]}; return nil if candidates.empty?
    best=candidates[0]; alt=candidates.find{|c| c[1]!=best[1]}
    gap=alt ? best[0]-alt[0] : 99
    confidence=gap>=25 ? "ALTA" : (gap>=10 ? "MEDIA" : "BAIXA")
    warning=nil
    if reply[:ko] && !(best[5] && best[5][:ko])
      warning="Cuidado: #{reply[:name]} pode nocautear"
    elsif reply[:name] && reply[:value].to_i>=155
      warning="Cuidado: #{reply[:name]}"
    elsif preserve>=85 && hp<=0.40
      warning="Preserve #{active.name}"
    end
    {best:best[1],alternative:(alt ? alt[1] : nil),best_score:best[0],alt_score:(alt ? alt[0] : nil),
     confidence:confidence,kind:best[2],live:true,own_alive:ctx[:own_alive],foe_alive:ctx[:foe_alive],
     full_team:(!ctx[:foe_party].empty?),opponent_known:ctx[:foe_party].length,
     opponent_reply:reply[:name],warning:warning,engine:"V7",predicted_damage:(best[5] ? best[5][:damage] : 0),
     predicted_ko:(best[5] ? best[5][:ko] : false)}
  rescue => e
    PBDebug.log("[CompetitiveCoachV7] #{e.class}: #{e.message}") rescue nil
    nil
  end
end

#===============================================================================
# Competitive Turn Coach v8 - Two-Ply Lookahead / Endgame Solver
# Counterfactual search over our action -> strongest known reply -> continuation.
# It never executes or mutates the real battle while analysing.
#===============================================================================
class Battle
  def competitive_coach_v8_continuation(ai, user, foe, hp_after_reply)
    return 0 if !ai || !user || !foe || foe.fainted?
    best=0
    Array(ai.pbGetMoveScores).each do |ch|
      im,raw,_=ch; next if im.nil? || raw.nil?
      mv=user.moves[im] rescue nil; next if !mv || (mv.pp.to_i<=0 rescue false)
      dmg=competitive_coach_v7_damage(ai,mv,foe)
      ratio=dmg.to_f/[foe.hp.to_i,1].max
      v=raw.to_i/5 + [ratio*42,42].min.to_i
      v+=28 if dmg>=foe.hp.to_i
      best=v if v>best
    end
    # A continuation that only exists at critically low HP is less reliable.
    best=(best*0.72).to_i if hp_after_reply>0 && hp_after_reply <= [user.totalhp.to_i*0.20,1].max
    best
  rescue; 0; end

  def competitive_coach_v8_endgame_bonus(ctx, action_kind, ko, ratio)
    alive=ctx[:own_alive].to_i+ctx[:foe_alive].to_i
    return 0 if alive>6
    b=0
    b+=18 if ko
    b+=8 if ratio>=0.50
    b+=5 if action_kind==:switch && ctx[:own_alive].to_i>1
    b
  rescue; 0; end

  def competitive_coach_recommendation(idxBattler)
    return nil if !@battlers[idxBattler] || !pbOwnedByPlayer?(idxBattler)
    ctx=competitive_coach_team_context(idxBattler); user=ctx[:user]; return nil if !user
    foe=ctx[:foes][0]; foe_pkmn=foe&.pokemon; active=user.pokemon
    ai=competitive_coach_v7_ai(idxBattler); return nil if !ai
    foe_ai=(foe ? (ai.battlers[foe.index] rescue nil) : nil)
    reply=competitive_coach_v7_best_reply(foe&.index,user)
    preserve=competitive_coach_preservation_value(active,ctx[:foe_party],ctx[:own_party])
    hp=competitive_coach_hp_ratio(active)
    candidates=[]

    Array(ai.pbGetMoveScores).each do |ch|
      im,raw,target=ch; next if im.nil? || raw.nil?
      mv=user.moves[im] rescue nil; next if !mv || (mv.pp.to_i<=0 rescue false)
      score=raw.to_i
      dmg=(foe ? competitive_coach_v7_damage(ai,mv,foe) : 0)
      foe_hp=(foe ? foe.hp.to_i : 0)
      ko=(foe && foe_hp>0 && dmg>=foe_hp)
      ratio=(foe_hp>0 ? dmg.to_f/foe_hp : 0.0)
      pri=(ai.move.rough_priority(ai.user) rescue (mv.priority.to_i rescue 0))
      faster=(foe_ai ? (ai.user.faster_than?(foe_ai) rescue false) : false)
      acts_first = ko && (pri>reply[:priority].to_i || (pri==reply[:priority].to_i && faster))

      score += 50 if ko
      score += 21 if !ko && ratio>=0.50
      score += 9 if !ko && ratio>=0.33
      score += 15 if acts_first

      # Two-ply layer: if the foe survives, price in its strongest current reply,
      # then value our best plausible continuation from the resulting HP state.
      reply_damage = (ko && acts_first) ? 0 : reply[:damage].to_i
      hp_after=[user.hp.to_i-reply_damage,0].max
      if hp_after<=0 && !acts_first
        score -= 48
        score -= 14 if preserve>=70
      else
        continuation=competitive_coach_v8_continuation(ai,user,foe,hp_after)
        score += [continuation/3,24].min
        score -= [reply_damage*28/[user.hp.to_i,1].max,28].min
      end

      # Full-team strategic tie-breaks.
      if mv.damagingMove? && !ctx[:foe_party].empty?
        good=0; immune=0
        ctx[:foe_party].each do |fp|
          next if (fp.fainted? rescue false)
          eff=(Effectiveness.calculate(mv.type,*(fp.types rescue [])) rescue 8)
          good+=1 if eff>8; immune+=1 if eff==0
        end
        score += [good*2,7].min-[immune*2,7].min
      end
      score -= 14 if preserve>=85 && hp<=0.40 && !ko && ratio<0.45
      score += competitive_coach_v8_endgame_bonus(ctx,:move,ko,ratio)
      candidates << [score,mv.name.to_s,:move,im,target,{damage:dmg,ko:ko,ratio:ratio,reply_damage:reply_damage,hp_after:hp_after}]
    end

    if @canSwitch && pbCanSwitchOut?(idxBattler)
      party=pbParty(idxBattler)
      reserves=(ai.get_non_active_party_pokemon(idxBattler) rescue [])
      wants=(Battle::AI::Handlers.should_switch?(ai.user,reserves,ai,self) rescue false)
      wants=false if wants && (Battle::AI::Handlers.should_not_switch?(ai.user,reserves,ai,self) rescue false)
      current_incoming=competitive_coach_live_pressure(foe_pkmn,active)
      party.each_with_index do |pkmn,i|
        next if !pbCanSwitchIn?(idxBattler,i)
        base=(ai.rate_replacement_pokemon(idxBattler,pkmn,100) rescue nil); next if base.nil?
        roster=competitive_coach_roster_value(pkmn,ctx[:foe_party])
        incoming=competitive_coach_live_pressure(foe_pkmn,pkmn)
        keep=competitive_coach_preservation_value(pkmn,ctx[:foe_party],ctx[:own_party])
        counter=competitive_coach_live_pressure(pkmn,foe_pkmn)
        score=base.to_i + [roster,48].min/3 - incoming/9 + [counter/18,12].min
        score += wants ? 28 : -7
        score += 23 if reply[:ko] && incoming<110
        score += 13 if preserve>=80 && hp<=0.40 && incoming<current_incoming
        score -= 17 if keep>=90 && incoming>=150
        score += competitive_coach_v8_endgame_bonus(ctx,:switch,false,0)
        candidates << [score,"Trocar > #{pkmn.name}",:switch,i,nil,{damage:0,ko:false,ratio:0.0,reply_damage:incoming}]
      end
    end

    candidates.sort!{|a,b| b[0]<=>a[0]}; return nil if candidates.empty?
    best=candidates[0]; alt=candidates.find{|c| c[1]!=best[1]}
    gap=alt ? best[0]-alt[0] : 99
    confidence=gap>=25 ? "ALTA" : (gap>=10 ? "MEDIA" : "BAIXA")
    warning=nil
    if best[2]==:move && best[5] && best[5][:hp_after].to_i<=0 && !best[5][:ko]
      warning="Linha arriscada: resposta pode nocautear"
    elsif reply[:ko] && best[2]!=:switch && !(best[5] && best[5][:ko])
      warning="Cuidado: #{reply[:name]} pode nocautear"
    elsif preserve>=85 && hp<=0.40
      warning="Preserve #{active.name}"
    end
    {best:best[1],alternative:(alt ? alt[1] : nil),best_score:best[0],alt_score:(alt ? alt[0] : nil),
     confidence:confidence,kind:best[2],live:true,own_alive:ctx[:own_alive],foe_alive:ctx[:foe_alive],
     full_team:(!ctx[:foe_party].empty?),opponent_known:ctx[:foe_party].length,
     opponent_reply:reply[:name],warning:warning,engine:"V8-2PLY",predicted_damage:(best[5] ? best[5][:damage] : 0),
     predicted_ko:(best[5] ? best[5][:ko] : false)}
  rescue => e
    PBDebug.log("[CompetitiveCoachV8] #{e.class}: #{e.message}") rescue nil
    nil
  end
end

#===============================================================================
# Competitive Turn Coach v9 - Virtual Battle State / Adaptive 3-Ply Search
# Builds immutable lightweight snapshots. Never mutates the real Battle.
# Search: our action -> strongest opponent reply -> our best continuation.
# Endgames deepen tactical weighting automatically.
#===============================================================================
class Battle
  def competitive_coach_v9_snapshot(ctx, user, foe)
    {
      our_hp: user.hp.to_i, our_max: [user.totalhp.to_i,1].max,
      foe_hp: (foe ? foe.hp.to_i : 0), foe_max: (foe ? [foe.totalhp.to_i,1].max : 1),
      own_alive: ctx[:own_alive].to_i, foe_alive: ctx[:foe_alive].to_i,
      own_party: ctx[:own_party], foe_party: ctx[:foe_party]
    }.freeze
  end

  def competitive_coach_v9_reply_candidates(idxFoe, our_battler)
    return [] if idxFoe.nil? || !@battlers[idxFoe] || @battlers[idxFoe].fainted?
    ai=competitive_coach_v7_ai(idxFoe); return [] if !ai
    rows=[]
    Array(ai.pbGetMoveScores).each do |ch|
      im,raw,_=ch; next if im.nil? || raw.nil?
      mv=@battlers[idxFoe].moves[im] rescue nil; next if !mv || (mv.pp.to_i<=0 rescue false)
      dmg=competitive_coach_v7_damage(ai,mv,our_battler)
      pri=(ai.move.rough_priority(ai.user) rescue (mv.priority.to_i rescue 0))
      rows << {name:mv.name.to_s,index:im,raw:raw.to_i,damage:dmg,priority:pri,
               damaging:(mv.damagingMove? rescue false)}
    end
    rows.sort_by{|r| -(r[:raw]+[r[:damage]*40/[our_battler.hp.to_i,1].max,40].min+(r[:priority]>0 ? 7 : 0))}[0,4]
  rescue; []; end

  def competitive_coach_v9_best_continuation(ai,user,foe,virtual_foe_hp,virtual_our_hp,ctx)
    return 0 if !ai || !user || !foe || virtual_our_hp<=0 || virtual_foe_hp<=0
    best=-9999
    Array(ai.pbGetMoveScores).each do |ch|
      im,raw,_=ch; next if im.nil? || raw.nil?
      mv=user.moves[im] rescue nil; next if !mv || (mv.pp.to_i<=0 rescue false)
      dmg=competitive_coach_v7_damage(ai,mv,foe)
      ratio=dmg.to_f/[virtual_foe_hp,1].max
      val=raw.to_i/4+[ratio*48,48].min.to_i
      val+=42 if dmg>=virtual_foe_hp
      val+=10 if ratio>=0.50 && dmg<virtual_foe_hp
      val-=10 if virtual_our_hp <= [user.totalhp.to_i*0.18,1].max
      best=val if val>best
    end
    # In small endgames, preserving a legal switch is itself a continuation resource.
    if ctx[:own_alive].to_i<=3 && @canSwitch && pbCanSwitchOut?(user.index)
      party=pbParty(user.index)
      party.each_with_index do |pkmn,i|
        next if !pbCanSwitchIn?(user.index,i)
        val=competitive_coach_roster_value(pkmn,ctx[:foe_party])/2-
            competitive_coach_live_pressure(foe.pokemon,pkmn)/12
        best=val if val>best
      end
    end
    [best,0].max
  rescue; 0; end

  def competitive_coach_v9_search_move(ai,user,foe,mv,raw,ctx,snap)
    dmg=competitive_coach_v7_damage(ai,mv,foe)
    foe_after=[snap[:foe_hp]-dmg,0].max
    our_ai=(ai.battlers[user.index] rescue nil); foe_ai=(ai.battlers[foe.index] rescue nil)
    our_pri=(ai.move.rough_priority(ai.user) rescue (mv.priority.to_i rescue 0))
    faster=(our_ai && foe_ai ? (our_ai.faster_than?(foe_ai) rescue false) : false)
    replies=competitive_coach_v9_reply_candidates(foe.index,user)
    # If we KO before the foe can act, opponent ply is removed.
    if foe_after<=0
      top_pri=(replies[0] ? replies[0][:priority].to_i : 0)
      first=(our_pri>top_pri || (our_pri==top_pri && faster))
      if first
        val=raw.to_i+62+competitive_coach_v8_endgame_bonus(ctx,:move,true,1.0)
        return [val,{damage:dmg,ko:true,reply:nil,reply_damage:0,hp_after:snap[:our_hp],continuation:0}]
      end
    end
    # Min layer: assume opponent selects the reply that leaves us the worst position.
    worst=nil
    (replies.empty? ? [{name:nil,damage:0,priority:0,raw:100}] : replies).each do |r|
      our_after=[snap[:our_hp]-r[:damage].to_i,0].max
      cont=competitive_coach_v9_best_continuation(ai,user,foe,foe_after,our_after,ctx)
      positional=(foe_after<=0 ? 55 : ((snap[:foe_hp]-foe_after)*35/[snap[:foe_hp],1].max))
      survival=(our_after*24/[snap[:our_hp],1].max)
      branch=raw.to_i+positional+survival+cont/3
      branch-=58 if our_after<=0 && foe_after>0
      branch+=competitive_coach_v8_endgame_bonus(ctx,:move,foe_after<=0,dmg.to_f/[snap[:foe_hp],1].max)
      row=[branch,{damage:dmg,ko:(foe_after<=0),reply:r[:name],reply_damage:r[:damage].to_i,
                   hp_after:our_after,foe_after:foe_after,continuation:cont}]
      worst=row if !worst || row[0]<worst[0]
    end
    worst
  rescue; [raw.to_i,{damage:0,ko:false,reply:nil,reply_damage:0,hp_after:snap[:our_hp],continuation:0}]; end

  def competitive_coach_recommendation(idxBattler)
    return nil if !@battlers[idxBattler] || !pbOwnedByPlayer?(idxBattler)
    ctx=competitive_coach_team_context(idxBattler); user=ctx[:user]; return nil if !user
    foe=ctx[:foes][0]; return nil if !foe
    active=user.pokemon; ai=competitive_coach_v7_ai(idxBattler); return nil if !ai
    snap=competitive_coach_v9_snapshot(ctx,user,foe)
    preserve=competitive_coach_preservation_value(active,ctx[:foe_party],ctx[:own_party])
    candidates=[]
    Array(ai.pbGetMoveScores).each do |ch|
      im,raw,target=ch; next if im.nil? || raw.nil?
      mv=user.moves[im] rescue nil; next if !mv || (mv.pp.to_i<=0 rescue false)
      score,meta=competitive_coach_v9_search_move(ai,user,foe,mv,raw,ctx,snap)
      score-=12 if preserve>=85 && competitive_coach_hp_ratio(active)<=0.35 && !meta[:ko]
      candidates << [score,mv.name.to_s,:move,im,target,meta]
    end
    if @canSwitch && pbCanSwitchOut?(idxBattler)
      party=pbParty(idxBattler)
      party.each_with_index do |pkmn,i|
        next if !pbCanSwitchIn?(idxBattler,i)
        base=(ai.rate_replacement_pokemon(idxBattler,pkmn,100) rescue nil); next if base.nil?
        incoming=competitive_coach_live_pressure(foe.pokemon,pkmn)
        counter=competitive_coach_live_pressure(pkmn,foe.pokemon)
        roster=competitive_coach_roster_value(pkmn,ctx[:foe_party])
        keep=competitive_coach_preservation_value(pkmn,ctx[:foe_party],ctx[:own_party])
        score=base.to_i+[roster,50].min/3+[counter/16,14].min-incoming/8
        score+=18 if incoming<competitive_coach_live_pressure(foe.pokemon,active)
        score-=18 if keep>=90 && incoming>=145
        score+=8 if ctx[:own_alive].to_i<=3 && incoming<100
        candidates << [score,"Trocar > #{pkmn.name}",:switch,i,nil,{damage:0,ko:false,reply:nil,reply_damage:incoming,hp_after:pkmn.hp.to_i,continuation:0}]
      end
    end
    candidates.sort!{|a,b| b[0]<=>a[0]}; return nil if candidates.empty?
    best=candidates[0]; alt=candidates.find{|c| c[1]!=best[1]}; gap=alt ? best[0]-alt[0] : 99
    confidence=gap>=24 ? "ALTA" : (gap>=9 ? "MEDIA" : "BAIXA")
    warning=nil
    if best[5][:reply_damage].to_i>=best[5][:hp_after].to_i && best[2]==:move && !best[5][:ko]
      warning="Linha de alto risco"
    elsif preserve>=85 && competitive_coach_hp_ratio(active)<=0.35
      warning="Preserve #{active.name}"
    end
    {best:best[1],alternative:(alt ? alt[1] : nil),best_score:best[0],alt_score:(alt ? alt[0] : nil),
     confidence:confidence,kind:best[2],live:true,own_alive:ctx[:own_alive],foe_alive:ctx[:foe_alive],
     full_team:(!ctx[:foe_party].empty?),opponent_known:ctx[:foe_party].length,
     opponent_reply:best[5][:reply],warning:warning,engine:"V9-3PLY",
     predicted_damage:best[5][:damage].to_i,predicted_ko:best[5][:ko],continuation:best[5][:continuation].to_i}
  rescue => e
    PBDebug.log("[CompetitiveCoachV9] #{e.class}: #{e.message}") rescue nil
    nil
  end
end


# Competitive Coach v10 - Mega Awareness
class Battle
  def competitive_coach_v10_mega_clone(pkmn)
    return nil if !pkmn || !pkmn.respond_to?(:hasMegaForm?) || !pkmn.hasMegaForm?
    c = pkmn.clone
    c.makeMega
    c.calc_stats if c.respond_to?(:calc_stats)
    c
  rescue
    nil
  end

  def competitive_coach_v10_can_mega_battler?(battler)
    return false if !battler || battler.fainted?
    return false if !battler.pokemon || !battler.pokemon.hasMegaForm?
    return pbCanMegaEvolve?(battler.index) if respond_to?(:pbCanMegaEvolve?)
    false
  rescue
    false
  end

  def competitive_coach_v10_stat_total(pkmn)
    return 0 if !pkmn
    [:attack,:defense,:spatk,:spdef,:speed].sum { |m| (pkmn.send(m).to_i rescue 0) }
  rescue
    0
  end

  def competitive_coach_v10_mega_delta(pkmn)
    mega=competitive_coach_v10_mega_clone(pkmn); return 0 if !mega
    [[competitive_coach_v10_stat_total(mega)-competitive_coach_v10_stat_total(pkmn),0].max/8,35].min
  rescue
    0
  end

  # Roster planning now treats an unused, item-enabled Mega form as a real threat/resource.
  alias competitive_coach_v10_old_move_pressure competitive_coach_move_pressure
  def competitive_coach_move_pressure(pkmn,target)
    normal=competitive_coach_v10_old_move_pressure(pkmn,target)
    mega=competitive_coach_v10_mega_clone(pkmn)
    return normal if !mega
    mega_val=competitive_coach_v10_old_move_pressure(mega,target)
    [normal, mega_val + competitive_coach_v10_mega_delta(pkmn)].max
  rescue
    competitive_coach_v10_old_move_pressure(pkmn,target)
  end

  alias competitive_coach_v10_old_v9_reply_candidates competitive_coach_v9_reply_candidates
  def competitive_coach_v9_reply_candidates(idxFoe,our_battler)
    rows=competitive_coach_v10_old_v9_reply_candidates(idxFoe,our_battler)
    foe=@battlers[idxFoe] rescue nil
    if competitive_coach_v10_can_mega_battler?(foe)
      bonus=competitive_coach_v10_mega_delta(foe.pokemon)
      rows.each do |r|
        r[:raw]=r[:raw].to_i + bonus
        r[:damage]=(r[:damage].to_i*(100+[bonus,25].min)/100.0).round if r[:damaging]
        r[:mega]=true
        r[:name]="Mega + #{r[:name]}" if r[:name]
      end
    end
    rows
  rescue
    rows || []
  end

  # Wrap the v9 recommendation: Mega availability is authoritative from the live Battle,
  # while the item/form mapping comes from this build's own getMegaForm/species data.
  alias competitive_coach_v10_old_recommendation competitive_coach_recommendation
  def competitive_coach_recommendation(idxBattler)
    result=competitive_coach_v10_old_recommendation(idxBattler)
    return result if !result
    user=@battlers[idxBattler] rescue nil
    foe=nil
    begin
      ctx=competitive_coach_team_context(idxBattler)
      foe=ctx[:foes][0]
    rescue
    end
    our_mega=competitive_coach_v10_can_mega_battler?(user)
    foe_mega=competitive_coach_v10_can_mega_battler?(foe)
    if our_mega && result[:kind]==:move && result[:best] && result[:best] !~ /^Mega \+ /
      result[:best]="Mega + #{result[:best]}"
      result[:best_score]=result[:best_score].to_i + competitive_coach_v10_mega_delta(user.pokemon)
    end
    if foe_mega
      result[:mega_threat]=true
      result[:warning] ||= "Mega adversaria disponivel"
    end
    result[:our_mega_available]=our_mega
    result[:foe_mega_available]=foe_mega
    result[:engine]="V10-MEGA-3PLY"
    result
  rescue => e
    PBDebug.log("[CompetitiveCoachV10] #{e.class}: #{e.message}") rescue nil
    competitive_coach_v10_old_recommendation(idxBattler)
  end
end


#===============================================================================
# Competitive Coach FINAL v11 - Polished Strategic Layer
# Live-state safety, Mega timing, tactical resources and adaptive endgame hints.
#===============================================================================
class Battle
  def competitive_coach_v11_fc(move)
    (move.function_code.to_s rescue "")
  end

  def competitive_coach_v11_move_role(move)
    return :damage if (move.damagingMove? rescue false)
    fc=competitive_coach_v11_fc(move)
    return :recovery if fc.match?(/HealUser|Recover|RestoreUser|HealUserDepending/)
    return :protect if fc.match?(/ProtectUser|ProtectUserFrom/)
    return :setup if fc.match?(/RaiseUser|RaiseUserMainStats|RaiseUserAtk|RaiseUserSpAtk|RaiseUserSpeed/)
    return :hazard if fc.match?(/StealthRock|Spikes|ToxicSpikes|StickyWeb|Add.*Hazard/)
    return :removal if fc.match?(/Remove.*Hazard|RapidSpin|Defog|RemoveUserBindingAndEntryHazards/)
    return :status if fc.match?(/SleepTarget|ParalyzeTarget|BurnTarget|PoisonTarget|ConfuseTarget/)
    :utility
  rescue; :utility; end

  def competitive_coach_v11_tactical_note(idxBattler, result)
    user=@battlers[idxBattler] rescue nil
    return nil if !user || !result
    ctx=competitive_coach_team_context(idxBattler) rescue nil
    return nil if !ctx
    foe=ctx[:foes][0] rescue nil
    return nil if !foe
    # Only surface a note when it is decision-critical; HUD stays compact.
    if result[:predicted_ko]
      return "KO previsto"
    end
    if result[:kind]==:switch
      return "Preservar a peca ativa" if competitive_coach_preservation_value(user.pokemon,ctx[:foe_party],ctx[:own_party]).to_i>=85
    end
    if ctx[:foe_alive].to_i<=2 && ctx[:own_alive].to_i>=ctx[:foe_alive].to_i
      return "Linha de endgame"
    end
    nil
  rescue; nil; end

  def competitive_coach_v11_mega_timing(idxBattler, result)
    user=@battlers[idxBattler] rescue nil
    return result if !user || !result || result[:kind]!=:move
    can=competitive_coach_v10_can_mega_battler?(user) rescue false
    return result if !can
    delta=competitive_coach_v10_mega_delta(user.pokemon).to_i rescue 0
    ctx=competitive_coach_team_context(idxBattler) rescue nil
    foe=(ctx && ctx[:foes] ? ctx[:foes][0] : nil) rescue nil
    # Mega now when the form materially improves stats, when the current matchup is
    # dangerous, or in the endgame. Otherwise don't falsely force Mega every turn.
    danger=(foe ? competitive_coach_live_pressure(foe.pokemon,user.pokemon).to_i : 0) rescue 0
    endgame=(ctx && (ctx[:own_alive].to_i+ctx[:foe_alive].to_i)<=5)
    use_now=(delta>=8 || danger>=145 || endgame || result[:predicted_ko])
    if use_now
      result[:best]="Mega + #{result[:best]}" if result[:best] && result[:best] !~ /^Mega \+ /
      result[:mega_recommended]=true
    else
      result[:best]=result[:best].sub(/^Mega \+ /,"") if result[:best]
      result[:mega_recommended]=false
    end
    result
  rescue; result; end

  alias competitive_coach_v11_previous_recommendation competitive_coach_recommendation
  def competitive_coach_recommendation(idxBattler)
    result=competitive_coach_v11_previous_recommendation(idxBattler)
    return result if !result
    result=competitive_coach_v11_mega_timing(idxBattler,result)
    result[:tactical_note]=competitive_coach_v11_tactical_note(idxBattler,result)
    # Preserve warnings from the deeper search. Only add a concise note if there
    # isn't already a more urgent warning.
    result[:warning] ||= result[:tactical_note]
    result[:engine]="FINAL-V11-ADAPTIVE-3PLY"
    result
  rescue => e
    PBDebug.log("[CompetitiveCoachV11] #{e.class}: #{e.message}") rescue nil
    competitive_coach_v11_previous_recommendation(idxBattler)
  end
end

#===============================================================================
# Competitive Coach ULTIMATE v12
# Probabilistic risk, adversarial switch coverage, effect-aware resources,
# adaptive endgame confidence. Never mutates the real Battle state.
#===============================================================================
class Battle
  def competitive_coach_v12_accuracy(ai, move, target)
    return 100 if !ai || !move || !target
    tai=(ai.battlers[target.index] rescue nil); return 100 if !tai
    ai.send(:set_up_move_check,move) rescue nil
    ai.send(:set_up_move_check_target,tai) rescue nil
    [[(ai.move.rough_accuracy.to_f rescue 100.0),0.0].max,100.0].min
  rescue; 100.0; end

  def competitive_coach_v12_role_bonus(move, user, foe, ctx)
    role=competitive_coach_v11_move_role(move)
    hp=competitive_coach_hp_ratio(user.pokemon)
    foehp=competitive_coach_hp_ratio(foe.pokemon)
    case role
    when :recovery
      return hp<=0.30 ? 30 : (hp<=0.55 ? 18 : (hp>=0.88 ? -28 : 5))
    when :protect
      return hp<=0.30 ? 10 : 3
    when :setup
      pressure=competitive_coach_live_pressure(foe.pokemon,user.pokemon).to_i
      return pressure<75 ? 22 : (pressure<120 ? 8 : -24)
    when :hazard
      return ctx[:foe_alive].to_i>=4 ? 20 : (ctx[:foe_alive].to_i==3 ? 8 : -14)
    when :removal
      return 12
    when :status
      return foehp>=0.45 ? 12 : 2
    end
    0
  rescue; 0; end

  # How badly a candidate move is punished by an obvious opponent switch.
  # Uses only the synchronized/live roster already available to the battle.
  def competitive_coach_v12_switch_penalty(move, foe, ctx)
    return [0,nil] if !move || !(move.damagingMove? rescue false)
    worst=0; name=nil
    Array(ctx[:foe_party]).each do |pkmn|
      next if !pkmn || (pkmn.fainted? rescue false) || pkmn.equal?(foe.pokemon)
      # Existing pressure evaluator understands this build's types/moves/items.
      our=competitive_coach_move_pressure(foe.pokemon,pkmn).to_i rescue 0
      their=competitive_coach_move_pressure(pkmn,foe.pokemon).to_i rescue 0
      # A low-pressure hit into a high-pressure switch is strategically dangerous.
      p=[[their/18-our/28,0].max,28].min
      if p>worst; worst=p; name=pkmn.name.to_s; end
    end
    [worst,name]
  rescue; [0,nil]; end

  def competitive_coach_v12_confidence(best, alt)
    return [3,"ALTA"] if !alt
    gap=best[0].to_i-alt[0].to_i
    return [3,"ALTA"] if gap>=24
    return [2,"MEDIA"] if gap>=9
    [1,"BAIXA"]
  end

  alias competitive_coach_v12_previous_recommendation competitive_coach_recommendation
  def competitive_coach_recommendation(idxBattler)
    base=competitive_coach_v12_previous_recommendation(idxBattler)
    return base if !base
    ctx=competitive_coach_team_context(idxBattler) rescue nil
    user=@battlers[idxBattler] rescue nil
    foe=(ctx[:foes][0] rescue nil)
    return base if !ctx || !user || !foe
    ai=competitive_coach_v7_ai(idxBattler)
    return base if !ai

    candidates=[]
    Array(ai.pbGetMoveScores).each do |ch|
      im,raw,target=ch; next if im.nil? || raw.nil?
      mv=user.moves[im] rescue nil; next if !mv || (mv.pp.to_i<=0 rescue false)
      snap=competitive_coach_v9_snapshot(ctx,user,foe)
      score,meta=competitive_coach_v9_search_move(ai,user,foe,mv,raw,ctx,snap)
      acc=competitive_coach_v12_accuracy(ai,mv,foe)
      # Expected-value penalty is intentionally nonlinear for inaccurate, decisive moves.
      miss=(100.0-acc)/100.0
      score -= (miss*32).round
      score -= (miss*18).round if meta[:ko]
      score += competitive_coach_v12_role_bonus(mv,user,foe,ctx)
      swpen,swname=competitive_coach_v12_switch_penalty(mv,foe,ctx)
      score -= swpen
      meta=meta.merge({accuracy:acc, switch_penalty:swpen, switch_target:swname,
                       role:competitive_coach_v11_move_role(mv)})
      candidates << [score,mv.name.to_s,:move,im,target,meta]
    end

    if @canSwitch && pbCanSwitchOut?(idxBattler)
      party=pbParty(idxBattler)
      party.each_with_index do |pkmn,i|
        next if !pbCanSwitchIn?(idxBattler,i)
        base_score=(ai.rate_replacement_pokemon(idxBattler,pkmn,100) rescue nil); next if base_score.nil?
        incoming=competitive_coach_live_pressure(foe.pokemon,pkmn).to_i
        counter=competitive_coach_live_pressure(pkmn,foe.pokemon).to_i
        roster=competitive_coach_roster_value(pkmn,ctx[:foe_party]).to_i
        keep=competitive_coach_preservation_value(pkmn,ctx[:foe_party],ctx[:own_party]).to_i
        score=base_score.to_i+[roster,55].min/3+[counter/15,15].min-incoming/8
        score+=20 if incoming < competitive_coach_live_pressure(foe.pokemon,user.pokemon).to_i
        score-=22 if keep>=90 && incoming>=145
        score+=12 if ctx[:own_alive].to_i<=3 && incoming<100
        candidates << [score,"Trocar > #{pkmn.name}",:switch,i,nil,
                       {accuracy:100.0,reply_damage:incoming,damage:0,ko:false,continuation:0,
                        role: :switch,switch_penalty:0}]
      end
    end

    candidates.sort!{|a,b| b[0]<=>a[0]}; return base if candidates.empty?
    best=candidates[0]; alt=candidates.find{|c| c[1]!=best[1]}
    dots,conf=competitive_coach_v12_confidence(best,alt)
    result=base.merge({best:best[1],alternative:(alt ? alt[1] : nil),best_score:best[0],
      alt_score:(alt ? alt[0] : nil),kind:best[2],confidence:conf,confidence_dots:dots,
      predicted_damage:best[5][:damage].to_i,predicted_ko:!!best[5][:ko],
      continuation:best[5][:continuation].to_i,accuracy:best[5][:accuracy],
      switch_cover:best[5][:switch_target],engine:"ULTIMATE-V12-PROB-3PLY"})

    # Re-apply authoritative live Mega timing after re-ranking.
    result=competitive_coach_v11_mega_timing(idxBattler,result) rescue result
    # Critical warning only. Confidence stays visual in the COACH label.
    if best[5][:accuracy].to_f<80 && best[5][:ko]
      result[:warning]="Linha depende de acerto"
    elsif best[5][:switch_penalty].to_i>=20 && best[5][:switch_target]
      result[:warning]="Cobre troca: #{best[5][:switch_target]}"
    else
      result[:warning]=competitive_coach_v11_tactical_note(idxBattler,result) rescue result[:warning]
    end
    result
  rescue => e
    PBDebug.log("[CompetitiveCoachV12] #{e.class}: #{e.message}") rescue nil
    competitive_coach_v12_previous_recommendation(idxBattler)
  end
end

#===============================================================================
# Competitive Turn Coach v13 - Rules/Synergy Engine + Switch Safety Gate
# Reads move function codes/abilities/items from this build rather than species
# matchup exceptions.  It is deliberately generic: interactions are inferred
# from mechanics exposed by the live Pokemon/Move objects.
#===============================================================================
class Battle
  # Estimate immediate move pressure for a Pokemon that is not currently a
  # Battler (e.g. a prospective switch-in). Includes offensive/defensive stats.
  def competitive_coach_v13_pressure(attacker, defender)
    return 0 if !attacker || !defender || !attacker.respond_to?(:moves)
    best=0
    attacker.moves.each do |m|
      next if !m
      next if ((m.pp.to_i<=0 && m.total_pp.to_i>0) rescue false)
      power=(m.power.to_i rescue 0)
      next if power<=0
      eff=(Effectiveness.calculate(m.type,*(defender.types rescue [])) rescue 8)
      next if eff<=0
      physical=(m.physicalMove? rescue false)
      atk=(physical ? (attacker.attack.to_f rescue 1.0) : (attacker.spatk.to_f rescue 1.0))
      dfn=(physical ? (defender.defense.to_f rescue 1.0) : (defender.spdef.to_f rescue 1.0))
      dfn=1.0 if dfn<=0
      val=power.to_f*(eff.to_f/8.0)*(atk/dfn)
      val*=1.5 if (attacker.types.include?(m.type) rescue false)
      val*=1.25 if (m.priority.to_i>0 rescue false)
      # Accuracy matters, but a possible lethal hit must never disappear merely
      # because it is imperfect.
      acc=(m.accuracy.to_f rescue 100.0); acc=100.0 if acc<=0
      val*=([acc,100.0].min/100.0*0.35+0.65)
      best=val if val>best
    end
    best.round
  rescue; competitive_coach_live_pressure(attacker,defender).to_i; end

  # Generic post-action synergy value. This intentionally keys off effect codes
  # and live mechanics rather than Pokemon names.
  def competitive_coach_v13_synergy_bonus(user, move, foe, ctx)
    return 0 if !user || !move
    fc=(move.function_code.to_s rescue '')
    bonus=0
    contrary=(user.hasActiveAbility?(:CONTRARY) rescue false)
    simple=(user.hasActiveAbility?(:SIMPLE) rescue false)
    # Self stat drops become setup under Contrary (Superpower/Leaf Storm/etc.).
    if contrary && fc.match?(/LowerUser/)
      stages=fc.scan(/(Attack|Defense|SpAtk|SpDef|Speed)(\d*)/)
      amount=stages.sum { |x| x[1].to_s.empty? ? 1 : x[1].to_i }
      amount=1 if amount<=0
      bonus += 22 + [amount*12,42].min
      # Damaging setup that also pressures the current foe is particularly good.
      bonus += 12 if (move.damagingMove? rescue false)
    end
    # Simple makes self-boosting moves more valuable because each stage doubles.
    if simple && fc.match?(/RaiseUser/)
      bonus += 18
    end
    # Common mechanic-level synergies exposed by live ability/status/item state.
    if (user.hasActiveAbility?(:GUTS) rescue false) && (user.status != :NONE rescue false) && (move.physicalMove? rescue false)
      bonus += 14
    end
    if (user.hasActiveAbility?(:TECHNICIAN) rescue false) && (move.power.to_i>0 rescue false) && (move.power.to_i<=60 rescue false)
      bonus += 8
    end
    if (user.hasActiveAbility?(:SHEERFORCE) rescue false) && (move.addlEffect.to_i>0 rescue false)
      bonus += 8
    end
    # Snowball value scales with how many opposing Pokemon remain.
    bonus += [ctx[:foe_alive].to_i-1,0].max*3 if bonus>0
    bonus
  rescue; 0; end

  # Hard safety check for a proposed switch. A switch which is plausibly lost
  # immediately to a known move is strongly rejected unless the current Pokemon
  # is in even greater danger. Uses the synchronized moveset already available.
  def competitive_coach_v13_switch_safety(foe, candidate, current)
    return [0,nil,0] if !foe || !candidate
    cand_pressure=competitive_coach_v13_pressure(foe.pokemon,candidate).to_i
    cur_pressure=current ? competitive_coach_v13_pressure(foe.pokemon,current.pokemon).to_i : 0
    hp_ratio=competitive_coach_hp_ratio(candidate)
    # Convert pressure to a conservative danger score; stat-aware pressure is
    # intentionally nonlinear so high-power STAB/super-effective hits dominate.
    danger=[cand_pressure,220].min
    penalty=0
    penalty += [danger/2,70].min
    penalty += 32 if danger>=115
    penalty += 30 if danger>=155
    # Don't forbid a necessary escape if staying is even worse.
    penalty -= 24 if cur_pressure>cand_pressure*1.35
    penalty += 18 if hp_ratio<0.50 && danger>=90
    worst=nil; worstv=-1
    Array(foe.pokemon.moves).each do |m|
      next if !m || (m.power.to_i rescue 0)<=0
      eff=(Effectiveness.calculate(m.type,*(candidate.types rescue [])) rescue 8)
      physical=(m.physicalMove? rescue false)
      atk=(physical ? (foe.pokemon.attack.to_f rescue 1) : (foe.pokemon.spatk.to_f rescue 1))
      dfn=(physical ? (candidate.defense.to_f rescue 1) : (candidate.spdef.to_f rescue 1)); dfn=1 if dfn<=0
      v=(m.power.to_f rescue 0)*(eff.to_f/8.0)*(atk/dfn)
      if v>worstv; worstv=v; worst=m.name.to_s; end
    end
    [[penalty,95].min,worst,danger]
  rescue; [0,nil,0]; end

  alias competitive_coach_v13_previous_recommendation competitive_coach_recommendation
  def competitive_coach_recommendation(idxBattler)
    base=competitive_coach_v13_previous_recommendation(idxBattler)
    return base if !base
    ctx=competitive_coach_team_context(idxBattler) rescue nil
    user=@battlers[idxBattler] rescue nil
    foe=(ctx[:foes][0] rescue nil)
    return base if !ctx || !user || !foe
    ai=competitive_coach_v7_ai(idxBattler); return base if !ai
    candidates=[]
    Array(ai.pbGetMoveScores).each do |ch|
      im,raw,target=ch; next if im.nil? || raw.nil?
      mv=user.moves[im] rescue nil; next if !mv || (mv.pp.to_i<=0 rescue false)
      snap=competitive_coach_v9_snapshot(ctx,user,foe)
      score,meta=competitive_coach_v9_search_move(ai,user,foe,mv,raw,ctx,snap)
      acc=competitive_coach_v12_accuracy(ai,mv,foe)
      miss=(100.0-acc)/100.0
      score-=(miss*32).round; score-=(miss*18).round if meta[:ko]
      score+=competitive_coach_v12_role_bonus(mv,user,foe,ctx)
      score+=competitive_coach_v13_synergy_bonus(user,mv,foe,ctx)
      swpen,swname=competitive_coach_v12_switch_penalty(mv,foe,ctx); score-=swpen
      meta=meta.merge({accuracy:acc,switch_penalty:swpen,switch_target:swname,
        synergy:competitive_coach_v13_synergy_bonus(user,mv,foe,ctx),role:competitive_coach_v11_move_role(mv)})
      candidates << [score,mv.name.to_s,:move,im,target,meta]
    end
    if @canSwitch && pbCanSwitchOut?(idxBattler)
      party=pbParty(idxBattler)
      party.each_with_index do |pkmn,i|
        next if !pbCanSwitchIn?(idxBattler,i)
        base_score=(ai.rate_replacement_pokemon(idxBattler,pkmn,100) rescue nil); next if base_score.nil?
        incoming=competitive_coach_v13_pressure(foe.pokemon,pkmn).to_i
        counter=competitive_coach_v13_pressure(pkmn,foe.pokemon).to_i
        roster=competitive_coach_roster_value(pkmn,ctx[:foe_party]).to_i
        keep=competitive_coach_preservation_value(pkmn,ctx[:foe_party],ctx[:own_party]).to_i
        safety,worst,danger=competitive_coach_v13_switch_safety(foe,pkmn,user)
        score=base_score.to_i+[roster,55].min/3+[counter/15,15].min-incoming/8-safety
        score+=14 if danger<competitive_coach_v13_pressure(foe.pokemon,user.pokemon).to_i
        score-=22 if keep>=90 && danger>=115
        candidates << [score,"Trocar > #{pkmn.name}",:switch,i,nil,
          {accuracy:100.0,reply_damage:incoming,damage:0,ko:false,continuation:0,role: :switch,
           switch_penalty:safety,switch_target:nil,switch_danger:danger,worst_move:worst}]
      end
    end
    candidates.sort!{|a,b| b[0]<=>a[0]}; return base if candidates.empty?
    best=candidates[0]; alt=candidates.find{|c| c[1]!=best[1]}
    dots,conf=competitive_coach_v12_confidence(best,alt)
    result=base.merge({best:best[1],alternative:(alt ? alt[1] : nil),best_score:best[0],alt_score:(alt ? alt[0] : nil),
      kind:best[2],confidence:conf,confidence_dots:dots,predicted_damage:best[5][:damage].to_i,
      predicted_ko:!!best[5][:ko],continuation:best[5][:continuation].to_i,accuracy:best[5][:accuracy],
      switch_cover:best[5][:switch_target],engine:'V13-RULES-SYNERGY-SAFETY'})
    result=competitive_coach_v11_mega_timing(idxBattler,result) rescue result
    if best[2]==:switch && best[5][:switch_danger].to_i>=115
      result[:warning]="Risco: #{best[5][:worst_move]}" if best[5][:worst_move]
    elsif best[5][:accuracy].to_f<80 && best[5][:ko]
      result[:warning]='Linha depende de acerto'
    elsif best[5][:switch_penalty].to_i>=20 && best[5][:switch_target]
      result[:warning]="Cobre troca: #{best[5][:switch_target]}"
    else
      result[:warning]=competitive_coach_v11_tactical_note(idxBattler,result) rescue result[:warning]
    end
    result
  rescue => e
    PBDebug.log("[CompetitiveCoachV13] #{e.class}: #{e.message}") rescue nil
    competitive_coach_v13_previous_recommendation(idxBattler)
  end
end

#===============================================================================
# Competitive Turn Coach v14 - Virtual Stat Stages + Intentional Sack Engine
#===============================================================================
class Battle
  # Estimate the strategic value of stat changes caused by a move. Unlike a
  # flat "setup bonus", this values the boosted stats according to the user's
  # actual attacking profile, remaining opposing roster and immediate danger.
  def competitive_coach_v14_stage_delta(user, move, foe, ctx)
    return 0 if !user || !move
    fc=(move.function_code.to_s rescue '')
    role=(competitive_coach_v11_move_role(move) rescue nil)
    bonus=0
    # Generic setup families used by Essentials/custom content. The exact
    # mechanics still remain authoritative in the live Battle object; this is
    # a forward-position valuation for search.
    if role==:setup || fc.match?(/RaiseUser|RaiseUserMainStats/)
      atk_user=(user.attack.to_i rescue 0); spa_user=(user.spatk.to_i rescue 0)
      speed_user=(user.speed.to_i rescue 0); speed_foe=(foe.speed.to_i rescue 0)
      physical=Array(user.moves).count{|m| m && (m.damagingMove? rescue false) && (m.physicalMove? rescue false)}
      special=Array(user.moves).count{|m| m && (m.damagingMove? rescue false) && (m.specialMove? rescue false)}
      # Nasty Plot/SpA setup is worth more on a special attacker; Swords Dance
      # similarly on a physical attacker. Speed setup is worth more if it flips
      # the current speed relation.
      if fc.match?(/SpAtk|SpecialAttack/i)
        bonus += 24 + special*7
      elsif fc.match?(/Attack|Atk/i) && !fc.match?(/SpAtk/i)
        bonus += 24 + physical*7
      else
        bonus += 20 + [physical,special].max*5
      end
      bonus += 18 if fc.match?(/Speed/i) && speed_user<=speed_foe
      bonus += [ctx[:foe_alive].to_i-1,0].max*4
      # Setup is only valuable if there is a plausible next turn.
      danger=competitive_coach_v13_pressure(foe.pokemon,user.pokemon).to_i rescue 0
      hp=competitive_coach_hp_ratio(user.pokemon) rescue 1.0
      bonus -= 38 if danger>=150 && hp<0.80
      bonus -= 20 if danger>=115 && hp<0.55
    end
    # Contrary converts self-drops into virtual positive stages. v13 recognizes
    # the synergy; v14 increases future-turn value because the boost persists.
    if (user.hasActiveAbility?(:CONTRARY) rescue false) && fc.match?(/LowerUser/)
      bonus += 22 + [ctx[:foe_alive].to_i-1,0].max*4
    end
    # Simple doubles the practical value of stat-stage changes.
    bonus = (bonus*1.35).round if bonus>0 && (user.hasActiveAbility?(:SIMPLE) rescue false)
    bonus
  rescue; 0; end

  # Marginal value of keeping a Pokemon alive *from this exact position*.
  # Low HP + no useful matchup => cheap sack. Unique checks/win conditions are
  # deliberately expensive to lose.
  def competitive_coach_v14_marginal_value(pkmn, ctx)
    return 999 if !pkmn
    hp=competitive_coach_hp_ratio(pkmn) rescue 0.0
    preserve=competitive_coach_preservation_value(pkmn,ctx[:foe_party],ctx[:own_party]).to_i rescue 50
    roster=competitive_coach_roster_value(pkmn,ctx[:foe_party]).to_i rescue 0
    pressure=0
    Array(ctx[:foe_party]).each do |f|
      next if !f || (f.fainted? rescue false)
      pressure=[pressure,competitive_coach_v13_pressure(pkmn,f).to_i].max rescue pressure
    end
    value=(preserve*0.65 + [roster,90].min*0.35).round
    value=(value*(0.35+0.65*hp)).round
    value+=18 if pressure>=120
    value+=20 if preserve>=90
    value
  rescue; 50; end

  # Determine whether an otherwise unsafe switch is a *deliberate sack* that
  # buys a materially better free entry. Returns [bonus, followup_name].
  def competitive_coach_v14_sack_value(idxBattler, foe, candidate, ctx, danger)
    return [0,nil] if danger.to_i<115 || !candidate || ctx[:own_alive].to_i<=1
    loss=competitive_coach_v14_marginal_value(candidate,ctx)
    return [0,nil] if loss>=80   # don't casually throw away a key answer/wincon
    party=pbParty(idxBattler) rescue []
    best_follow=nil; best_gain=0
    party.each_with_index do |p,i|
      next if !p || p.equal?(candidate) || (p.fainted? rescue false)
      next if !(pbCanSwitchIn?(idxBattler,i) rescue false)
      keep=competitive_coach_v14_marginal_value(p,ctx)
      counter=competitive_coach_v13_pressure(p,foe.pokemon).to_i rescue 0
      incoming=competitive_coach_v13_pressure(foe.pokemon,p).to_i rescue 999
      # Free entry is valuable when the follow-up threatens the foe and would
      # have been unsafe to hard-switch directly.
      gain=counter/3 + [keep,100].min/5
      gain+=24 if counter>=120
      gain+=18 if incoming>=115
      if gain>best_gain
        best_gain=gain; best_follow=p.name.to_s
      end
    end
    net=best_gain-loss/2
    return [0,nil] if net<18
    [[net,48].min,best_follow]
  rescue; [0,nil]; end

  alias competitive_coach_v14_previous_recommendation competitive_coach_recommendation
  def competitive_coach_recommendation(idxBattler)
    base=competitive_coach_v14_previous_recommendation(idxBattler)
    return base if !base
    ctx=competitive_coach_team_context(idxBattler) rescue nil
    user=@battlers[idxBattler] rescue nil
    foe=(ctx[:foes][0] rescue nil)
    return base if !ctx || !user || !foe
    ai=competitive_coach_v7_ai(idxBattler); return base if !ai
    candidates=[]
    Array(ai.pbGetMoveScores).each do |ch|
      im,raw,target=ch; next if im.nil? || raw.nil?
      mv=user.moves[im] rescue nil; next if !mv || (mv.pp.to_i<=0 rescue false)
      snap=competitive_coach_v9_snapshot(ctx,user,foe)
      score,meta=competitive_coach_v9_search_move(ai,user,foe,mv,raw,ctx,snap)
      acc=competitive_coach_v12_accuracy(ai,mv,foe)
      miss=(100.0-acc)/100.0
      score-=(miss*32).round; score-=(miss*18).round if meta[:ko]
      score+=competitive_coach_v12_role_bonus(mv,user,foe,ctx)
      score+=competitive_coach_v13_synergy_bonus(user,mv,foe,ctx)
      stage_delta=competitive_coach_v14_stage_delta(user,mv,foe,ctx)
      score+=stage_delta
      swpen,swname=competitive_coach_v12_switch_penalty(mv,foe,ctx); score-=swpen
      meta=meta.merge({accuracy:acc,switch_penalty:swpen,switch_target:swname,
        synergy:competitive_coach_v13_synergy_bonus(user,mv,foe,ctx),stage_delta:stage_delta,
        role:competitive_coach_v11_move_role(mv),intentional_sack:false})
      candidates << [score,mv.name.to_s,:move,im,target,meta]
    end
    if @canSwitch && pbCanSwitchOut?(idxBattler)
      party=pbParty(idxBattler)
      party.each_with_index do |pkmn,i|
        next if !pbCanSwitchIn?(idxBattler,i)
        base_score=(ai.rate_replacement_pokemon(idxBattler,pkmn,100) rescue nil); next if base_score.nil?
        incoming=competitive_coach_v13_pressure(foe.pokemon,pkmn).to_i
        counter=competitive_coach_v13_pressure(pkmn,foe.pokemon).to_i
        roster=competitive_coach_roster_value(pkmn,ctx[:foe_party]).to_i
        keep=competitive_coach_preservation_value(pkmn,ctx[:foe_party],ctx[:own_party]).to_i
        safety,worst,danger=competitive_coach_v13_switch_safety(foe,pkmn,user)
        sack_bonus,follow=competitive_coach_v14_sack_value(idxBattler,foe,pkmn,ctx,danger)
        intentional=sack_bonus>0
        # Safety remains dominant for ordinary switches. A recognized sack can
        # recover part (never all) of the safety penalty if it buys a free entry.
        effective_safety=intentional ? [safety-(sack_bonus*0.65).round,12].max : safety
        score=base_score.to_i+[roster,55].min/3+[counter/15,15].min-incoming/8-effective_safety
        score+=14 if danger<competitive_coach_v13_pressure(foe.pokemon,user.pokemon).to_i
        score-=22 if keep>=90 && danger>=115
        score+=sack_bonus if intentional
        label=intentional ? "SACRIFICIO > #{pkmn.name}" : "Trocar > #{pkmn.name}"
        candidates << [score,label,:switch,i,nil,
          {accuracy:100.0,reply_damage:incoming,damage:0,ko:false,continuation:0,role: :switch,
           switch_penalty:effective_safety,switch_target:nil,switch_danger:danger,worst_move:worst,
           intentional_sack:intentional,sack_followup:follow,sack_bonus:sack_bonus}]
      end
    end
    candidates.sort!{|a,b| b[0]<=>a[0]}; return base if candidates.empty?
    best=candidates[0]; alt=candidates.find{|c| c[1]!=best[1]}
    dots,conf=competitive_coach_v12_confidence(best,alt)
    result=base.merge({best:best[1],alternative:(alt ? alt[1] : nil),best_score:best[0],alt_score:(alt ? alt[0] : nil),
      kind:best[2],confidence:conf,confidence_dots:dots,predicted_damage:best[5][:damage].to_i,
      predicted_ko:!!best[5][:ko],continuation:best[5][:continuation].to_i,accuracy:best[5][:accuracy],
      switch_cover:best[5][:switch_target],engine:'V14-VIRTUAL-STAGES-SACK'})
    result=competitive_coach_v11_mega_timing(idxBattler,result) rescue result
    if best[5][:intentional_sack]
      result[:warning]=best[5][:sack_followup] ? "Depois > #{best[5][:sack_followup]}" : 'Sacrificio deliberado'
    elsif best[2]==:switch && best[5][:switch_danger].to_i>=115
      result[:warning]="Risco: #{best[5][:worst_move]}" if best[5][:worst_move]
    elsif best[5][:accuracy].to_f<80 && best[5][:ko]
      result[:warning]='Linha depende de acerto'
    elsif best[5][:switch_penalty].to_i>=20 && best[5][:switch_target]
      result[:warning]="Cobre troca: #{best[5][:switch_target]}"
    else
      result[:warning]=competitive_coach_v11_tactical_note(idxBattler,result) rescue result[:warning]
    end
    result
  rescue => e
    PBDebug.log("[CompetitiveCoachV14] #{e.class}: #{e.message}") rescue nil
    competitive_coach_v14_previous_recommendation(idxBattler)
  end
end

#===============================================================================
# Competitive Turn Coach v18 - Adaptive Selective Search
#===============================================================================
class Battle
  def competitive_coach_v18_reset_search(ctx)
    alive=[ctx[:own_alive].to_i+ctx[:foe_alive].to_i,1].max
    @competitive_coach_v18_nodes=0
    @competitive_coach_v18_tt={}
    @competitive_coach_v18_budget = alive<=4 ? 80000 : (alive<=7 ? 35000 : 14000)
    @competitive_coach_v18_depth  = alive<=4 ? 9 : (alive<=7 ? 7 : 5)
  end

  def competitive_coach_v18_stage_gain(battler, move, foe, ctx)
    v=competitive_coach_v14_stage_delta(battler,move,foe,ctx).to_i rescue 0
    [[v/12,0].max,6].min
  rescue; 0; end

  # Compact action model used only by the look-ahead tree. The live Battle
  # object remains authoritative; this never mutates HP, stages or parties.
  def competitive_coach_v18_move_actions(battler, target, ctx)
    rows=[]
    return rows if !battler || !target
    ai=competitive_coach_v7_ai(battler.index) rescue nil
    Array(battler.moves).each_with_index do |mv,i|
      next if !mv || (mv.pp.to_i<=0 rescue false)
      dmg=competitive_coach_v7_damage(ai,mv,target).to_i rescue 0
      acc=competitive_coach_v12_accuracy(ai,mv,target).to_f rescue 100.0
      role=competitive_coach_v11_move_role(mv) rescue nil
      sg=competitive_coach_v18_stage_gain(battler,mv,target,ctx)
      util=competitive_coach_v12_role_bonus(mv,battler,target,ctx).to_i rescue 0
      util+=competitive_coach_v13_synergy_bonus(battler,mv,target,ctx).to_i rescue 0
      rows << {kind: :move,index:i,name:mv.name.to_s,damage:dmg,accuracy:acc,
               priority:(mv.priority.to_i rescue 0),stage:sg,utility:util,role:role}
    end
    rows.sort!{|a,b| (b[:damage]+b[:utility])<=>(a[:damage]+a[:utility])}
    rows[0,5] || rows
  rescue; []; end

  def competitive_coach_v18_switch_actions(idxBattler, foe, ctx)
    rows=[]; return rows if !@canSwitch || !(pbCanSwitchOut?(idxBattler) rescue false)
    Array(pbParty(idxBattler)).each_with_index do |p,i|
      next if !p || !(pbCanSwitchIn?(idxBattler,i) rescue false)
      inc=competitive_coach_v13_pressure(foe.pokemon,p).to_i rescue 999
      out=competitive_coach_v13_pressure(p,foe.pokemon).to_i rescue 0
      keep=competitive_coach_v14_marginal_value(p,ctx).to_i rescue 50
      rows << {kind: :switch,index:i,name:"Trocar > #{p.name}",damage:0,accuracy:100.0,
               priority:6,stage:0,utility:(out/5-inc/7+keep/6),incoming:inc}
    end
    rows.sort!{|a,b| b[:utility]<=>a[:utility]}
    rows[0,3] || rows
  rescue; []; end

  def competitive_coach_v18_eval(our_hp,our_max,foe_hp,foe_max,our_stage,foe_stage,ctx)
    return 10000 if foe_hp<=0 && our_hp>0
    return -10000 if our_hp<=0 && foe_hp>0
    hp=((our_hp.to_f/[our_max,1].max)-(foe_hp.to_f/[foe_max,1].max))*170.0
    material=(ctx[:own_alive].to_i-ctx[:foe_alive].to_i)*24
    hp.round+material+(our_stage-foe_stage)*16
  end

  # Expectiminimax-style selective tree. Accuracy is folded into expected
  # damage; alpha/beta + beam ordering + TT keep the tree bounded.
  def competitive_coach_v18_search(our_actions,foe_actions,state,depth,maximizing,alpha,beta,ctx)
    @competitive_coach_v18_nodes+=1
    return competitive_coach_v18_eval(state[0],state[1],state[2],state[3],state[4],state[5],ctx) if depth<=0 || @competitive_coach_v18_nodes>=@competitive_coach_v18_budget || state[0]<=0 || state[2]<=0
    key=[depth,maximizing,state[0]/4,state[2]/4,state[4],state[5]]
    old=@competitive_coach_v18_tt[key]; return old if old
    actions=maximizing ? our_actions : foe_actions
    return competitive_coach_v18_eval(state[0],state[1],state[2],state[3],state[4],state[5],ctx) if !actions || actions.empty?
    actions=actions[0,(depth>=6 ? 3 : 4)]
    best=maximizing ? -99999 : 99999
    actions.each do |a|
      s=state.dup
      if a[:kind]==:move
        expected=(a[:damage].to_f*a[:accuracy].to_f/100.0).round
        if maximizing
          expected=(expected*(1.0+s[4]*0.12)).round if s[4]>0
          s[2]=[s[2]-expected,0].max; s[4]=[[s[4]+a[:stage].to_i,6].min,-6].max
          immediate=a[:utility].to_i
        else
          expected=(expected*(1.0+s[5]*0.12)).round if s[5]>0
          s[0]=[s[0]-expected,0].max; s[5]=[[s[5]+a[:stage].to_i,6].min,-6].max
          immediate=-a[:utility].to_i
        end
      else
        # Switches are positional actions: their utility already includes
        # matchup pressure, preservation and switch safety from v13/v14.
        immediate=maximizing ? a[:utility].to_i : -a[:utility].to_i
      end
      val=immediate+competitive_coach_v18_search(our_actions,foe_actions,s,depth-1,!maximizing,alpha,beta,ctx)
      if maximizing
        best=val if val>best; alpha=best if best>alpha; break if beta<=alpha
      else
        best=val if val<best; beta=best if best<beta; break if beta<=alpha
      end
    end
    @competitive_coach_v18_tt[key]=best if @competitive_coach_v18_tt.length<12000
    best
  rescue
    competitive_coach_v18_eval(state[0],state[1],state[2],state[3],state[4],state[5],ctx)
  end

  alias competitive_coach_v18_previous_recommendation competitive_coach_recommendation
  def competitive_coach_recommendation(idxBattler)
    base=competitive_coach_v18_previous_recommendation(idxBattler)
    return base if !base
    ctx=competitive_coach_team_context(idxBattler) rescue nil
    user=@battlers[idxBattler] rescue nil
    foe=(ctx[:foes][0] rescue nil)
    return base if !ctx || !user || !foe
    competitive_coach_v18_reset_search(ctx)
    ours=competitive_coach_v18_move_actions(user,foe,ctx)+competitive_coach_v18_switch_actions(idxBattler,foe,ctx)
    theirs=competitive_coach_v18_move_actions(foe,user,ctx)
    return base if ours.empty? || theirs.empty?
    state=[user.hp.to_i,[user.totalhp.to_i,1].max,foe.hp.to_i,[foe.totalhp.to_i,1].max,0,0]
    ranked=[]
    # Iterative deepening: a complete shallow result is always available if
    # the node budget is exhausted during a deeper pass.
    completed=nil
    d=3
    while d<=@competitive_coach_v18_depth && @competitive_coach_v18_nodes<@competitive_coach_v18_budget
      pass=[]
      ours.each do |a|
        break if @competitive_coach_v18_nodes>=@competitive_coach_v18_budget
        s=state.dup; immediate=a[:utility].to_i
        if a[:kind]==:move
          dmg=(a[:damage].to_f*a[:accuracy].to_f/100.0).round
          s[2]=[s[2]-dmg,0].max; s[4]=[[a[:stage].to_i,6].min,-6].max
        end
        val=immediate+competitive_coach_v18_search(ours,theirs,s,d-1,false,-99999,99999,ctx)
        pass << [val,a]
      end
      completed=pass unless pass.empty?
      d+=2
    end
    ranked=(completed || []).sort{|a,b| b[0]<=>a[0]}
    return base if ranked.empty?
    best=ranked[0]; alt=ranked.find{|x| x[1][:name]!=best[1][:name]}
    # Blend search with the mature v14 tactical score so one approximate deep
    # branch cannot erase hard safety/sack/rules-engine knowledge.
    search_name=best[1][:name]
    if base[:best].to_s==search_name
      final_name=base[:best]
    elsif best[0].to_i-(alt ? alt[0].to_i : 0)>=18
      final_name=search_name
    else
      final_name=base[:best]
    end
    base[:alternative]=(final_name==search_name ? (alt ? alt[1][:name] : base[:alternative]) : search_name)
    base[:best]=final_name
    base[:search_score]=best[0].to_i
    base[:search_nodes]=@competitive_coach_v18_nodes.to_i
    base[:search_depth]=[d-2,@competitive_coach_v18_depth].min
    base[:search_budget]=@competitive_coach_v18_budget
    base[:engine]='V18-ADAPTIVE-SEARCH'
    base
  rescue => e
    PBDebug.log("[CompetitiveCoachV18] #{e.class}: #{e.message}") rescue nil
    competitive_coach_v18_previous_recommendation(idxBattler)
  end
end
