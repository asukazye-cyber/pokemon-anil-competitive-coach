#===============================================================================
# Competitive Turn Coach v23 - Probabilistic Battle Solver
# Chance nodes use the accuracy rules exposed by this build of Anil/Essentials.
# Side-effect-free: never calls the live RNG and never mutates the live battle.
#===============================================================================
class Battle
  def competitive_coach_v23_acc_stage_ratio(stage)
    s=[[stage.to_i,-6].max,6].min
    s>=0 ? (3.0+s)/3.0 : 3.0/(3.0-s)
  end

  def competitive_coach_v23_weather(s)
    w=s[:weather] rescue nil
    return w if w
    (@field.weather rescue nil)
  end

  def competitive_coach_v23_base_accuracy(s, move)
    acc=move[:accuracy].to_f
    fn=move[:function].to_s
    w=competitive_coach_v23_weather(s)
    # Native Anil classes: Thunder/Hurricane family is perfect in rain, 50 in sun.
    if fn.include?("AlwaysHitsInRain") || fn.include?("HitsDecreasesInSun")
      return 0.0 if [:Rain,:HeavyRain].include?(w)
      return 50.0 if [:Sun,:HarshSun].include?(w)
    end
    # Blizzard-like native function is perfect in hail/snow builds that expose it.
    if fn.include?("AlwaysHitsInHail") || fn.include?("AlwaysHitsInSnow")
      return 0.0 if [:Hail,:Snow].include?(w)
    end
    acc
  rescue
    move[:accuracy].to_f
  end

  def competitive_coach_v23_hit_probability(s, att, defn, move, ours=true)
    base=competitive_coach_v23_base_accuracy(s,move)
    return 1.0 if base<=0.0                         # native always-hit convention
    ua=att[:ability]; da=defn[:ability]
    # Exact handlers present in this Anil build (s235): either side's No Guard.
    return 1.0 if ua==:NOGUARD || da==:NOGUARD
    # This build also makes Electric moves perfect vs Lightning Rod in accuracy calc.
    return 1.0 if da==:LIGHTNINGROD && move[:type]==:ELECTRIC

    acc_stage=competitive_coach_v22_stage(att,:ACCURACY)
    eva_stage=competitive_coach_v22_stage(defn,:EVASION)
    acc_mult=1.0; eva_mult=1.0
    # Ability handlers from the shipped scripts.
    acc_mult*=1.3 if ua==:COMPOUNDEYES
    acc_mult*=0.8 if ua==:HUSTLE && move[:power].to_i>0
    eva_stage=0 if [:KEENEYE,:MINDSEYE].include?(ua) && eva_stage>0
    eva_stage=0 if ua==:UNAWARE && move[:power].to_i>0
    acc_mult*=1.1 if ua==:VICTORYSTAR
    if da==:SANDVEIL && competitive_coach_v23_weather(s)==:Sandstorm; eva_mult*=1.25; end
    if da==:SNOWCLOAK && [:Hail,:Snow].include?(competitive_coach_v23_weather(s)); eva_mult*=1.25; end
    # Item handlers from shipped scripts (s236).
    acc_mult*=1.1 if att[:item]==:WIDELENS
    # Zoom Lens is conditional on the target already moving; don't award it unless known.
    acc_mult*=0.9 if [:BRIGHTPOWDER,:LAXINCENSE].include?(defn[:item])
    # Gravity is represented when available in the field snapshot/live field.
    gravity=(s[:gravity].to_i rescue 0)
    gravity=(@field.effects[PBEffects::Gravity].to_i rescue gravity)
    acc_mult*=5.0/3.0 if gravity>0

    threshold=base * competitive_coach_v23_acc_stage_ratio(acc_stage) * acc_mult /
                    (competitive_coach_v23_acc_stage_ratio(eva_stage) * eva_mult)
    [[threshold/100.0,0.0].max,1.0].min
  rescue
    a=move[:accuracy].to_f; a=100.0 if a<=0; [[a/100.0,0.0].max,1.0].min
  end

  def competitive_coach_v23_secondary_probability(move)
    gd=GameData::Move.get(move[:id]) rescue nil
    c=(gd.effect_chance.to_f rescue 0.0)
    [[c/100.0,0.0].max,1.0].min
  rescue; 0.0; end

  def competitive_coach_v23_apply_hit(s,a,ours,apply_secondary=true)
    # v22 application is deterministic; force accuracy to 100 for a resolved hit.
    aa=a.dup
    if a[:move]
      mm=a[:move].dup; mm[:accuracy]=100; aa[:move]=mm
    end
    ns=competitive_coach_v22_apply(s,aa,ours)
    # v22 applies decoded status/stages as guaranteed. If this is a failed
    # secondary branch, reconstruct hit damage without optional secondary effect.
    if !apply_secondary && a[:native_effect]
      eff=a[:native_effect]
      optional=(competitive_coach_v23_secondary_probability(a[:move])>0)
      if optional
        stripped=eff.dup
        [:status,:target_stages].each{|k| stripped.delete(k)}
        aa2=aa.dup; aa2[:native_effect]=stripped
        ns=competitive_coach_v22_apply(s,aa2,ours)
      end
    end
    ns
  rescue; competitive_coach_v22_apply(s,a,ours); end

  def competitive_coach_v23_outcomes(s,a,ours)
    return [[1.0,competitive_coach_v22_apply(s,a,ours),:deterministic]] if a[:kind]!=:move
    side=ours ? s[:our] : s[:foe]; opp=ours ? s[:foe] : s[:our]
    me=side[:team][side[:active]]; them=opp[:team][opp[:active]]
    ph=competitive_coach_v23_hit_probability(s,me,them,a[:move],ours)
    miss=competitive_coach_v21_clone(s)
    out=[]
    out << [1.0-ph,miss,:miss] if ph<0.999999
    ps=competitive_coach_v23_secondary_probability(a[:move])
    if ps>0.0 && ps<1.0 && a[:native_effect] && (a[:native_effect][:status] || a[:native_effect][:target_stages])
      out << [ph*(1.0-ps),competitive_coach_v23_apply_hit(s,a,ours,false),:hit]
      out << [ph*ps,competitive_coach_v23_apply_hit(s,a,ours,true),:hit_secondary]
    else
      out << [ph,competitive_coach_v23_apply_hit(s,a,ours,true),:hit]
    end
    out.select{|x| x[0]>0.000001}
  rescue
    [[1.0,competitive_coach_v22_apply(s,a,ours),:fallback]]
  end

  def competitive_coach_v23_search(s,depth,maxing,alpha,beta)
    @competitive_coach_v23_nodes+=1
    competitive_coach_v22_force_replacement!(s,true); competitive_coach_v22_force_replacement!(s,false)
    return competitive_coach_v22_eval(s) if depth<=0 || @competitive_coach_v23_nodes>=@competitive_coach_v23_budget
    return competitive_coach_v22_eval(s) if !s[:our][:team].any?{|p| competitive_coach_v22_alive?(p)} || !s[:foe][:team].any?{|p| competitive_coach_v22_alive?(p)}
    key=[:v23,depth,maxing,competitive_coach_v22_key(s,depth,maxing)]
    old=@competitive_coach_v23_tt[key]; return old if old
    acts=competitive_coach_v22_actions(s,maxing); return competitive_coach_v22_eval(s) if acts.empty?
    acts=acts[0,(depth>=5 ? 3 : 5)]
    best=maxing ? -999999.0 : 999999.0
    acts.each do |a|
      ev=0.0
      competitive_coach_v23_outcomes(s,a,maxing).each do |prob,ns,_label|
        ev += prob*competitive_coach_v23_search(ns,depth-1,!maxing,alpha,beta)
      end
      if maxing; best=ev if ev>best; alpha=[alpha,best].max; break if beta<=alpha
      else best=ev if ev<best; beta=[beta,best].min; break if beta<=alpha; end
    end
    @competitive_coach_v23_tt[key]=best if @competitive_coach_v23_tt.length<45000
    best
  rescue; competitive_coach_v22_eval(s); end

  alias competitive_coach_v23_prev_rec competitive_coach_recommendation
  def competitive_coach_recommendation(idxBattler)
    base=competitive_coach_v23_prev_rec(idxBattler); return base if !base
    ctx=competitive_coach_team_context(idxBattler) rescue nil; user=@battlers[idxBattler] rescue nil; foe=(ctx[:foes][0] rescue nil)
    return base if !ctx || !user || !foe || ctx[:own_party].empty? || ctx[:foe_party].empty?
    state=competitive_coach_v22_state(idxBattler,ctx,user,foe); return base if !state
    state[:weather]=(@field.weather rescue nil)
    alive=ctx[:own_alive].to_i+ctx[:foe_alive].to_i
    @competitive_coach_v23_budget=alive<=4 ? 220000 : (alive<=7 ? 110000 : 48000)
    maxdepth=alive<=4 ? 10 : (alive<=7 ? 8 : 6)
    @competitive_coach_v23_nodes=0; @competitive_coach_v23_tt={}
    completed=nil; d=2
    while d<=maxdepth && @competitive_coach_v23_nodes<@competitive_coach_v23_budget
      pass=[]
      competitive_coach_v22_actions(state,true).each do |a|
        break if @competitive_coach_v23_nodes>=@competitive_coach_v23_budget
        ev=0.0
        competitive_coach_v23_outcomes(state,a,true).each do |prob,ns,_|
          ev += prob*competitive_coach_v23_search(ns,d-1,false,-999999.0,999999.0)
        end
        pass << [ev,a]
      end
      completed=pass unless pass.empty?; d+=2
    end
    ranked=Array(completed).sort_by{|x|-x[0]}; best=ranked[0]; alt=ranked[1]
    if best
      if base[:best].to_s==best[1][:name].to_s || !alt || best[0]-alt[0]>=25
        base[:best]=best[1][:name]
      end
      base[:alternative]=alt[1][:name] if alt
      # Expose resolved hit probability for the recommended root move.
      if best[1][:kind]==:move
        me=state[:our][:team][state[:our][:active]]; them=state[:foe][:team][state[:foe][:active]]
        base[:hit_probability]=(competitive_coach_v23_hit_probability(state,me,them,best[1][:move],true)*100).round(1)
      end
      base[:prob_score]=best[0].round(2); base[:search_nodes]=@competitive_coach_v23_nodes; base[:search_depth]=[d-2,maxdepth].min
    end
    base[:engine]='V23-PROBABILISTIC-BATTLE-SOLVER'; base[:chance_nodes]=true
    base
  rescue => e
    PBDebug.log("[CompetitiveCoachV23] #{e.class}: #{e.message}") rescue nil
    base
  end
end
