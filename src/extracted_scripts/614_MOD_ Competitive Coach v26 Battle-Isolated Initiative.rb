#===============================================================================
# Competitive Turn Coach v26 - Battle-Isolated Initiative Engine
# Clean rebuild on v23. No Scene_Map/Input/Game_Player hooks and no replacement
# of v22 action/apply methods. Safety and turn resolution live only in this layer.
#===============================================================================
class Battle
  def competitive_coach_v26_status_move?(a)
    return false if !a || a[:kind] != :move
    m=a[:move] || {}; m[:power].to_i<=0 || m[:category]==2 || m[:category]==:STATUS
  rescue; false; end

  def competitive_coach_v26_priority(state, mon, action)
    return 6 if action[:kind]==:switch || action[:kind]==:sack
    m=action[:move] || {}; p=m[:priority].to_i; ab=mon[:ability]
    p+=1 if ab==:GALEWINGS && Array(mon[:types]).include?(:FLYING) && mon[:hp].to_i>=mon[:max].to_i
    p+=1 if ab==:PRANKSTER && competitive_coach_v26_status_move?(action)
    fn=m[:function].to_s
    healing=(action[:native_effect]||{})[:heal_frac] || (action[:native_effect]||{})[:drain_frac] || fn =~ /Heal|Recover|Roost|Wish|Rest|StrengthSap|LifeDew|JungleHealing/
    p+=3 if ab==:TRIAGE && healing
    terrain=state[:terrain]
    p+=1 if fn.include?("HigherPriorityInGrassyTerrain") && terrain==:Grassy
    p+=1 if fn.include?("HigherPriorityInMistyTerrain") && terrain==:Misty
    p
  rescue; 0; end

  def competitive_coach_v26_speed(state, mon, ours)
    v=[mon[:speed].to_f,1.0].max
    v*=competitive_coach_v22_mult(competitive_coach_v22_stage(mon,:SPEED))
    side=ours ? state[:our] : state[:foe]
    v*=2.0 if (side[:side]||{})[:tailwind].to_i>0
    v*=1.5 if mon[:item]==:CHOICESCARF
    v*=0.5 if mon[:item]==:IRONBALL
    v*=0.5 if mon[:status]==:PARALYSIS && mon[:ability]!=:QUICKFEET
    v*=1.5 if mon[:ability]==:QUICKFEET && mon[:status] && mon[:status]!=:NONE
    v
  rescue; 1.0; end

  def competitive_coach_v26_order(state, our_action, foe_action)
    om=state[:our][:team][state[:our][:active]]; fm=state[:foe][:team][state[:foe][:active]]
    op=competitive_coach_v26_priority(state,om,our_action); fp=competitive_coach_v26_priority(state,fm,foe_action)
    return :our if op>fp; return :foe if fp>op
    ob=([:STALL,:MYCELIUMMIGHT].include?(om[:ability]) || [:LAGGINGTAIL,:FULLINCENSE].include?(om[:item])) ? -1 : 0
    fb=([:STALL,:MYCELIUMMIGHT].include?(fm[:ability]) || [:LAGGINGTAIL,:FULLINCENSE].include?(fm[:item])) ? -1 : 0
    return :our if ob>fb; return :foe if fb>ob
    os=competitive_coach_v26_speed(state,om,true); fs=competitive_coach_v26_speed(state,fm,false)
    return :tie if (os-fs).abs<0.001
    trick=state[:trick_room].to_i>0
    trick ? (os<fs ? :our : :foe) : (os>fs ? :our : :foe)
  rescue; :tie; end

  # Conservative hit damage. Accuracy remains a probability, never a damage discount.
  def competitive_coach_v26_incoming(state, attacker, candidate, attacker_is_ours)
    worst=nil
    Array(attacker[:moves]).each do |m|
      next if !m || m[:power].to_i<=0 || m[:pp].to_i<=0
      ev=competitive_coach_v22_move_damage(attacker,candidate,m).to_f
      hp=competitive_coach_v23_hit_probability(state,attacker,candidate,m,attacker_is_ours) rescue nil
      hp=(m[:accuracy].to_f<=0 ? 1.0 : m[:accuracy].to_f/100.0) if !hp || hp<=0
      hit=ev/[hp,0.05].max; upper=hit*1.20
      row={name:m[:name].to_s,hit_damage:hit,upper_damage:upper,hit_probability:hp,ratio:upper/[candidate[:hp].to_i,1].max}
      worst=row if !worst || row[:ratio]>worst[:ratio]
    end
    worst || {name:nil,hit_damage:0.0,upper_damage:0.0,hit_probability:0.0,ratio:0.0}
  rescue; {name:nil,hit_damage:0.0,upper_damage:0.0,hit_probability:0.0,ratio:0.0}; end

  # Root/deep action filter without monkey-patching v22_actions.
  def competitive_coach_v26_actions(state, ours)
    rows=competitive_coach_v22_actions(state,ours)
    side=ours ? state[:our] : state[:foe]; opp=ours ? state[:foe] : state[:our]
    them=opp[:team][opp[:active]]; me=side[:team][side[:active]]
    current=competitive_coach_v26_incoming(state,them,me,!ours)
    out=[]
    rows.each do |a|
      if a[:kind]!=:switch
        out << a; next
      end
      cand=side[:team][a[:index]]; next if !cand
      hz=competitive_coach_v22_hazard_damage(cand,side[:side]||{}).to_i
      post=cand.dup; post[:hp]=[cand[:hp].to_i-hz,0].max; next if post[:hp]<=0
      risk=competitive_coach_v26_incoming(state,them,post,!ours)
      unsafe=risk[:ratio]>=0.90 || risk[:upper_damage]>=post[:hp].to_i
      aa=a.dup; aa[:switch_risk]=risk; aa[:entry_hazards]=hz
      if unsafe
        # Never disguise a lethal entry as a normal switch. A sack is explicit and
        # only admitted when staying is also in immediate danger and >2 mons remain.
        alive=side[:team].count{|x| competitive_coach_v22_alive?(x)}
        frac=post[:hp].to_f/[post[:max].to_i,1].max
        if current[:ratio]>=0.90 && alive>2 && frac<=0.45
          aa[:kind]=:sack; aa[:name]="SACRIFICIO > #{cand[:name]}"; aa[:utility]=aa[:utility].to_f-65.0; aa[:intentional_sack]=true
          out << aa
        end
      else
        aa[:utility]=aa[:utility].to_f-risk[:ratio]*24.0; out << aa
      end
    end
    out.sort_by{|a|-a[:utility].to_f}[0,5]
  rescue; rows || []; end

  def competitive_coach_v26_sucker_fails?(a,other)
    return false if !a || a[:kind]!=:move
    fn=(a[:move]||{})[:function].to_s
    fn.include?("FailsIfTargetActed") && (!other || other[:kind]!=:move || competitive_coach_v26_status_move?(other))
  rescue; false; end

  def competitive_coach_v26_apply(state,action,ours,other=nil)
    return [[1.0,state,:failed_condition]] if competitive_coach_v26_sucker_fails?(action,other)
    aa=action
    if action && action[:kind]==:sack
      aa=action.dup; aa[:kind]=:switch
    end
    competitive_coach_v23_outcomes(state,aa,ours)
  rescue; [[1.0,competitive_coach_v22_apply(state,aa||action,ours),:fallback]]; end

  def competitive_coach_v26_alive?(state,ours)
    side=ours ? state[:our] : state[:foe]; competitive_coach_v22_alive?(side[:team][side[:active]])
  rescue; false; end

  def competitive_coach_v26_pair(state,oa,fa,forced=nil)
    first=forced || competitive_coach_v26_order(state,oa,fa)
    if first==:tie
      return competitive_coach_v26_pair(state,oa,fa,:our).map{|p,s,l|[p*0.5,s,[:tie_our,l]]}+
             competitive_coach_v26_pair(state,oa,fa,:foe).map{|p,s,l|[p*0.5,s,[:tie_foe,l]]}
    end
    first_ours=(first==:our); a1=first_ours ? oa : fa; a2=first_ours ? fa : oa; out=[]
    competitive_coach_v26_apply(state,a1,first_ours,a2).each do |p1,s1,l1|
      second_ours=!first_ours
      if !competitive_coach_v26_alive?(s1,second_ours)
        out << [p1,s1,[l1,:second_cancelled_ko]]; next
      end
      competitive_coach_v26_apply(s1,a2,second_ours,a1).each{|p2,s2,l2| out << [p1*p2,s2,[l1,l2]]}
    end
    out
  rescue => e; [[1.0,state,[:resolver_error,e.class.to_s]]]; end

  def competitive_coach_v26_search(state,depth,alpha,beta)
    @competitive_coach_v26_nodes+=1
    competitive_coach_v22_force_replacement!(state,true); competitive_coach_v22_force_replacement!(state,false)
    return competitive_coach_v22_eval(state) if depth<=0 || @competitive_coach_v26_nodes>=@competitive_coach_v26_budget
    ours=competitive_coach_v26_actions(state,true); foes=competitive_coach_v26_actions(state,false)
    return competitive_coach_v22_eval(state) if ours.empty? || foes.empty?
    ours=ours[0,(depth>=3 ? 3 : 5)]; foes=foes[0,(depth>=3 ? 3 : 5)]; best=-999999.0
    ours.each do |oa|
      worst=999999.0
      foes.each do |fa|
        ev=0.0
        competitive_coach_v26_pair(state,oa,fa).each{|pr,ns,_| ev+=pr*competitive_coach_v26_search(ns,depth-1,alpha,beta)}
        worst=ev if ev<worst; break if worst<=alpha
      end
      best=worst if worst>best; alpha=[alpha,best].max; break if beta<=alpha
    end
    best
  rescue; competitive_coach_v22_eval(state); end

  alias competitive_coach_v26_v23_recommendation competitive_coach_recommendation
  def competitive_coach_recommendation(idxBattler)
    # This method can only exist on a live Battle instance. No map/input hook.
    base=competitive_coach_v26_v23_recommendation(idxBattler); return base if !base
    ctx=competitive_coach_team_context(idxBattler) rescue nil; user=@battlers[idxBattler] rescue nil; foe=(ctx[:foes][0] rescue nil)
    return base if !ctx || !user || !foe || ctx[:own_party].empty? || ctx[:foe_party].empty?
    state=competitive_coach_v22_state(idxBattler,ctx,user,foe); return base if !state
    state[:weather]=(@field.weather rescue nil); state[:terrain]=(@field.terrain rescue nil); state[:trick_room]=(@field.effects[PBEffects::TrickRoom].to_i rescue 0)
    alive=ctx[:own_alive].to_i+ctx[:foe_alive].to_i
    @competitive_coach_v26_budget=alive<=4 ? 150000 : (alive<=7 ? 75000 : 32000); maxturns=alive<=4 ? 5 : (alive<=7 ? 4 : 3); @competitive_coach_v26_nodes=0
    ours=competitive_coach_v26_actions(state,true); foes=competitive_coach_v26_actions(state,false); ranked=[]
    ours.each do |oa|
      worst=999999.0; reply=nil
      foes.each do |fa|
        ev=0.0; competitive_coach_v26_pair(state,oa,fa).each{|pr,ns,_| ev+=pr*competitive_coach_v26_search(ns,maxturns-1,-999999.0,999999.0)}
        if ev<worst; worst=ev; reply=fa; end
      end
      ranked << [worst,oa,reply]; break if @competitive_coach_v26_nodes>=@competitive_coach_v26_budget
    end
    ranked.sort_by!{|x|-x[0]}; best=ranked[0]; alt=ranked[1]
    if best
      base[:best]=best[1][:name]; base[:kind]=best[1][:kind]; base[:alternative]=alt[1][:name] if alt
      base[:opponent_best_reply]=(best[2][:name] rescue nil)
      if best[2]
        ord=competitive_coach_v26_order(state,best[1],best[2]); base[:opponent_moves_first]=(ord==:foe || ord==:tie); base[:initiative]=(ord==:tie ? 'SPEED TIE' : (ord==:foe ? 'OPPONENT FIRST' : 'COACH FIRST'))
      end
      if best[1][:kind]==:sack; base[:warning]='SACRIFICIO planejado'; base[:intentional_sack]=true; end
      base[:turn_score]=best[0].round(2); base[:search_nodes]=@competitive_coach_v26_nodes; base[:search_depth]=maxturns
    end
    base[:engine]='V26-BATTLE-ISOLATED-INITIATIVE'; base[:hard_switch_gate]=true; base[:simultaneous_turns]=true; base[:priority_aware]=true; base[:map_isolated]=true
    base
  rescue => e
    PBDebug.log("[CompetitiveCoachV26] #{e.class}: #{e.message}") rescue nil
    base
  end
end
