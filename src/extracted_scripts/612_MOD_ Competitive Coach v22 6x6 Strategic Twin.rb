#===============================================================================
# Competitive Turn Coach v22 - 6x6 Strategic Search / Full Roster Twin
# Side-effect-free. Uses only battle/team information already available locally.
#===============================================================================
class Battle
  def competitive_coach_v22_pkmn_snapshot(p, active=false, battler=nil)
    return nil if !p
    types=(p.types rescue [])
    moves=Array(p.moves).map do |pm|
      begin
        gd=GameData::Move.get(pm.id)
        { id:pm.id, name:gd.name.to_s, power:gd.power.to_i, type:gd.type,
          category:gd.category, accuracy:gd.accuracy.to_i, priority:gd.priority.to_i,
          function:gd.function_code.to_s, pp:(pm.pp.to_i rescue 1) }
      rescue
        { id:(pm.id rescue nil), name:(pm.name.to_s rescue '?'), power:(pm.power.to_i rescue 0),
          type:(pm.type rescue nil), category:nil, accuracy:100, priority:0, function:'', pp:(pm.pp.to_i rescue 1) }
      end
    end
    h={name:(p.name.to_s rescue '?'),hp:(p.hp.to_i rescue 1),max:[(p.totalhp.to_i rescue 1),1].max,
       status:(p.status rescue :NONE),types:types,ability:(p.ability_id rescue p.ability rescue nil),
       item:(p.item_id rescue p.item rescue nil),attack:(p.attack.to_i rescue 1),defense:(p.defense.to_i rescue 1),
       spatk:(p.spatk.to_i rescue 1),spdef:(p.spdef.to_i rescue 1),speed:(p.speed.to_i rescue 1),
       moves:moves,stages:{ATTACK:0,DEFENSE:0,SPECIAL_ATTACK:0,SPECIAL_DEFENSE:0,SPEED:0,ACCURACY:0,EVASION:0},
       substitute:0,encore:0,taunt:0,confusion:0,protect:false,choice:nil}
    if active && battler
      live=competitive_coach_v19_battler_snapshot(battler) rescue {}
      h.merge!(live.reject{|k,_| k==:side})
      h[:moves]=moves; h[:attack]=(p.attack.to_i rescue h[:attack]); h[:defense]=(p.defense.to_i rescue h[:defense])
      h[:spatk]=(p.spatk.to_i rescue h[:spatk]); h[:spdef]=(p.spdef.to_i rescue h[:spdef]); h[:speed]=(p.speed.to_i rescue h[:speed])
    end
    h
  rescue; nil; end

  def competitive_coach_v22_roster(party, active_pkmn, battler=nil)
    arr=[]; active_idx=0
    Array(party).each_with_index do |p,i|
      next if !p
      is_active=(p.equal?(active_pkmn) || (p.object_id==active_pkmn.object_id rescue false))
      active_idx=arr.length if is_active
      arr << competitive_coach_v22_pkmn_snapshot(p,is_active,battler)
    end
    [arr.compact,active_idx]
  end

  def competitive_coach_v22_alive?(x); x && x[:hp].to_i>0; end
  def competitive_coach_v22_stage(x,k); ((x[:stages]||{})[k]||0).to_i; end
  def competitive_coach_v22_mult(s); competitive_coach_v19_stage_mult(s); end

  def competitive_coach_v22_effectiveness(type, defender)
    return 1.0 if !type
    v=(Effectiveness.calculate(type,*Array(defender[:types])) rescue nil)
    return v.to_f/8.0 if v
    1.0
  rescue; 1.0; end

  def competitive_coach_v22_move_damage(att,defn,m)
    return 0.0 if m[:power].to_i<=0
    physical=(m[:category]==0 || m[:category]==:PHYSICAL)
    a=(physical ? att[:attack] : att[:spatk]).to_f
    d=(physical ? defn[:defense] : defn[:spdef]).to_f; d=1.0 if d<=0
    ast=competitive_coach_v22_stage(att,physical ? :ATTACK : :SPECIAL_ATTACK)
    dst=competitive_coach_v22_stage(defn,physical ? :DEFENSE : :SPECIAL_DEFENSE)
    ratio=(a*competitive_coach_v22_mult(ast))/(d*competitive_coach_v22_mult(dst))
    stab=Array(att[:types]).include?(m[:type]) ? 1.5 : 1.0
    eff=competitive_coach_v22_effectiveness(m[:type],defn)
    # Relative estimator calibrated to HP scale. Root v19 remains authoritative
    # for the final recommendation; this value ranks future roster branches.
    base=((m[:power].to_f*ratio*stab*eff)/2.2)
    acc=m[:accuracy].to_i; acc=100 if acc<=0
    base*[acc,100].min/100.0
  rescue; 0.0; end

  def competitive_coach_v22_hazard_damage(mon,side)
    return 0 if !mon || !side
    max=[mon[:max].to_i,1].max; dmg=0.0
    if side[:stealth_rock]
      rock=competitive_coach_v22_effectiveness(:ROCK,mon)
      dmg += max*0.125*rock
    end
    layers=side[:spikes].to_i
    grounded=!Array(mon[:types]).include?(:FLYING) && mon[:ability]!=:LEVITATE
    dmg += max*([0,0.125,1.0/6.0,0.25][[layers,3].min]||0) if grounded && layers>0
    dmg.round
  rescue; 0; end

  def competitive_coach_v22_switch!(s, ours, idx)
    side=ours ? s[:our] : s[:foe]; old=side[:team][side[:active]]; neu=side[:team][idx]
    return false if !competitive_coach_v22_alive?(neu) || idx==side[:active]
    # Standard switch clears the outgoing active's volatile/stat state.
    old[:stages]={ATTACK:0,DEFENSE:0,SPECIAL_ATTACK:0,SPECIAL_DEFENSE:0,SPEED:0,ACCURACY:0,EVASION:0}
    old[:substitute]=0; old[:encore]=0; old[:taunt]=0; old[:confusion]=0; old[:protect]=false
    side[:active]=idx
    hz=competitive_coach_v22_hazard_damage(neu,side[:side]||{})
    neu[:hp]=[neu[:hp].to_i-hz,0].max
    if (side[:side]||{})[:sticky_web] && !Array(neu[:types]).include?(:FLYING) && neu[:ability]!=:LEVITATE
      neu[:stages]||={}; neu[:stages][:SPEED]=[neu[:stages][:SPEED].to_i-1,-6].max
    end
    true
  end

  def competitive_coach_v22_actions(s, ours)
    side=ours ? s[:our] : s[:foe]; opp=ours ? s[:foe] : s[:our]
    me=side[:team][side[:active]]; them=opp[:team][opp[:active]]; rows=[]
    return rows if !competitive_coach_v22_alive?(me)
    Array(me[:moves]).each_with_index do |m,i|
      next if m[:pp].to_i<=0
      next if me[:taunt].to_i>0 && m[:power].to_i<=0
      next if me[:encore].to_i>0 && me[:encore_move] && m[:id]!=me[:encore_move]
      next if me[:choice] && me[:choice]!=0 && me[:choice]!=-1 && m[:id]!=me[:choice]
      dmg=competitive_coach_v22_move_damage(me,them,m)
      eff=competitive_coach_v20_decode_function(m[:function]) rescue {}
      util=dmg
      util+=18 if (eff[:self_stages]||{}).values.any?{|v| v.to_i>0}
      util+=12 if eff[:status] || eff[:hazard] || eff[:screen] || eff[:tailwind]
      rows << {kind: :move,index:i,name:m[:name],move:m,damage:dmg,utility:util,native_effect:eff}
    end
    side[:team].each_with_index do |p,i|
      next if i==side[:active] || !competitive_coach_v22_alive?(p)
      hz=competitive_coach_v22_hazard_damage(p,side[:side]||{})
      next if hz>=p[:hp].to_i
      incoming=competitive_coach_v22_best_damage(them,p)
      outgoing=competitive_coach_v22_best_damage(p,them)
      preserve=(p[:hp].to_f/[p[:max].to_i,1].max)*12
      rows << {kind: :switch,index:i,name:"Trocar > #{p[:name]}",utility:(outgoing-incoming*0.85+preserve),damage:0}
    end
    rows.sort_by{|a| -a[:utility].to_f}[0,5]
  rescue; []; end

  def competitive_coach_v22_best_damage(att,defn)
    Array(att[:moves]).map{|m| competitive_coach_v22_move_damage(att,defn,m)}.max.to_f
  rescue; 0.0; end

  def competitive_coach_v22_apply(s,a,ours)
    ns=competitive_coach_v21_clone(s)
    if a[:kind]==:switch
      competitive_coach_v22_switch!(ns,ours,a[:index]); return ns
    end
    side=ours ? ns[:our] : ns[:foe]; opp=ours ? ns[:foe] : ns[:our]
    me=side[:team][side[:active]]; them=opp[:team][opp[:active]]; m=a[:move]; eff=a[:native_effect]||{}
    dmg=competitive_coach_v22_move_damage(me,them,m).round
    if them[:protect]
      dmg=0
    elsif them[:substitute].to_i>0 && dmg>0
      them[:substitute]=[them[:substitute].to_i-dmg,0].max; dmg=0
    else
      them[:hp]=[them[:hp].to_i-dmg,0].max
    end
    competitive_coach_v20_apply_stage_hash!(me,eff[:self_stages]||{}) rescue nil
    competitive_coach_v20_apply_stage_hash!(them,eff[:target_stages]||{}) rescue nil
    them[:status]=eff[:status] if eff[:status] && (them[:status].nil? || them[:status]==:NONE)
    if eff[:heal_frac]; me[:hp]=[me[:hp]+(me[:max]*eff[:heal_frac]).round,me[:max]].min; end
    if eff[:drain_frac]; me[:hp]=[me[:hp]+(dmg*eff[:drain_frac]).round,me[:max]].min; end
    me[:hp]=[me[:hp]-(dmg*eff[:recoil_frac]).round,0].max if eff[:recoil_frac]
    me[:protect]=true if eff[:protect]
    if eff[:hazard]
      opp[:side]||={}; k=eff[:hazard]
      if k==:spikes; opp[:side][k]=[opp[:side][k].to_i+1,3].min
      elsif k==:toxic_spikes; opp[:side][k]=[opp[:side][k].to_i+1,2].min
      else opp[:side][k]=true; end
    end
    if eff[:screen]; side[:side]||={}; side[:side][eff[:screen]]=5; end
    if eff[:tailwind]; side[:side]||={}; side[:side][:tailwind]=4; end
    ns
  rescue; s; end

  def competitive_coach_v22_force_replacement!(s,ours)
    side=ours ? s[:our] : s[:foe]; cur=side[:team][side[:active]]
    return if competitive_coach_v22_alive?(cur)
    best=nil
    side[:team].each_with_index{|p,i| next if !competitive_coach_v22_alive?(p); v=p[:hp].to_f/[p[:max],1].max; best=[v,i] if !best || v>best[0]}
    competitive_coach_v22_switch!(s,ours,best[1]) if best
  end

  def competitive_coach_v22_eval(s)
    val=0.0
    [[:our,1],[:foe,-1]].each do |key,sign|
      side=s[key]; side[:team].each_with_index do |p,i|
        next if !p
        hp=[p[:hp].to_f/[p[:max].to_i,1].max,0].max
        val += sign*(competitive_coach_v22_alive?(p) ? 105+hp*38 : 0)
        if i==side[:active] && competitive_coach_v22_alive?(p)
          st=[:ATTACK,:DEFENSE,:SPECIAL_ATTACK,:SPECIAL_DEFENSE,:SPEED].sum{|k| competitive_coach_v22_stage(p,k)}
          val += sign*st*4
          val += sign*12 if p[:substitute].to_i>0
        end
      end
      sd=side[:side]||{}
      pressure=sd[:spikes].to_i*4+sd[:toxic_spikes].to_i*4+(sd[:stealth_rock] ? 7:0)+(sd[:sticky_web] ? 5:0)
      val -= sign*pressure
    end
    val.round
  end

  def competitive_coach_v22_key(s,depth,maxing)
    pack=lambda{|side| [side[:active],side[:team].map{|p| [p[:hp].to_i/4,p[:status],p[:item],p[:stages]]},side[:side]]}
    [depth,maxing,pack.call(s[:our]),pack.call(s[:foe])]
  end

  def competitive_coach_v22_search(s,depth,maxing,alpha,beta)
    @competitive_coach_v22_nodes+=1
    competitive_coach_v22_force_replacement!(s,true); competitive_coach_v22_force_replacement!(s,false)
    return competitive_coach_v22_eval(s) if depth<=0 || @competitive_coach_v22_nodes>=@competitive_coach_v22_budget
    return competitive_coach_v22_eval(s) if !s[:our][:team].any?{|p| competitive_coach_v22_alive?(p)} || !s[:foe][:team].any?{|p| competitive_coach_v22_alive?(p)}
    key=competitive_coach_v22_key(s,depth,maxing); old=@competitive_coach_v22_tt[key]; return old if old
    acts=competitive_coach_v22_actions(s,maxing); return competitive_coach_v22_eval(s) if acts.empty?
    acts=acts[0,(depth>=5 ? 3 : 5)]
    best=maxing ? -999999 : 999999
    acts.each do |a|
      ns=competitive_coach_v22_apply(s,a,maxing)
      v=competitive_coach_v22_search(ns,depth-1,!maxing,alpha,beta)
      if maxing; best=v if v>best; alpha=[alpha,best].max; break if beta<=alpha
      else best=v if v<best; beta=[beta,best].min; break if beta<=alpha; end
    end
    @competitive_coach_v22_tt[key]=best if @competitive_coach_v22_tt.length<30000
    best
  rescue; competitive_coach_v22_eval(s); end

  def competitive_coach_v22_state(idx,ctx,user,foe)
    ot,oi=competitive_coach_v22_roster(ctx[:own_party],user.pokemon,user)
    ft,fi=competitive_coach_v22_roster(ctx[:foe_party],foe.pokemon,foe)
    return nil if ot.empty? || ft.empty?
    {our:{team:ot,active:oi,side:competitive_coach_v19_side_snapshot(user)},
     foe:{team:ft,active:fi,side:competitive_coach_v19_side_snapshot(foe)},turn:0}
  rescue; nil; end

  alias competitive_coach_v22_prev_rec competitive_coach_recommendation
  def competitive_coach_recommendation(idxBattler)
    base=competitive_coach_v22_prev_rec(idxBattler); return base if !base
    ctx=competitive_coach_team_context(idxBattler) rescue nil; user=@battlers[idxBattler] rescue nil; foe=(ctx[:foes][0] rescue nil)
    return base if !ctx || !user || !foe || ctx[:own_party].empty? || ctx[:foe_party].empty?
    state=competitive_coach_v22_state(idxBattler,ctx,user,foe); return base if !state
    alive=ctx[:own_alive].to_i+ctx[:foe_alive].to_i
    @competitive_coach_v22_budget=alive<=4 ? 180000 : (alive<=7 ? 90000 : 38000)
    maxdepth=alive<=4 ? 10 : (alive<=7 ? 8 : 6)
    @competitive_coach_v22_nodes=0; @competitive_coach_v22_tt={}
    completed=nil; d=2
    while d<=maxdepth && @competitive_coach_v22_nodes<@competitive_coach_v22_budget
      pass=[]; competitive_coach_v22_actions(state,true).each do |a|
        break if @competitive_coach_v22_nodes>=@competitive_coach_v22_budget
        ns=competitive_coach_v22_apply(state,a,true)
        pass << [competitive_coach_v22_search(ns,d-1,false,-999999,999999),a]
      end
      completed=pass unless pass.empty?; d+=2
    end
    ranked=Array(completed).sort_by{|x| -x[0]}; best=ranked[0]; alt=ranked[1]
    if best
      # Native v21 tactical layer remains the safety authority. Roster search
      # overrides only with a meaningful strategic margin or agreement.
      if base[:best].to_s==best[1][:name].to_s || !alt || best[0]-alt[0]>=30
        base[:best]=best[1][:name]
      end
      base[:alternative]=alt[1][:name] if alt
      base[:roster_score]=best[0]; base[:search_nodes]=@competitive_coach_v22_nodes
      base[:search_depth]=[d-2,maxdepth].min
    end
    base[:engine]='V22-6X6-STRATEGIC-TWIN'; base[:full_roster_search]=true
    base
  rescue => e
    PBDebug.log("[CompetitiveCoachV22] #{e.class}: #{e.message}") rescue nil
    competitive_coach_v22_prev_rec(idxBattler)
  end
end
