#===============================================================================
# Competitive Turn Coach v21 - Battle Digital Twin / Quiescence Search
# Side-effect-free search state. Uses only information already present in the
# local battle state; it never mutates the live Battle object.
#===============================================================================
class Battle
  def competitive_coach_v21_clone(o)
    Marshal.load(Marshal.dump(o)) rescue o.dup
  end

  def competitive_coach_v21_stage(snap, stat)
    ((snap[:vstages]||{})[stat] || (snap[:stages]||{})[stat] || 0).to_i
  end

  def competitive_coach_v21_stage_ratio(stage)
    competitive_coach_v19_stage_mult(stage)
  end

  def competitive_coach_v21_damage(a, attacker, defender)
    dmg=a[:damage].to_f
    cat=a[:category]
    atkstat=(cat==:SPECIAL ? :SPECIAL_ATTACK : :ATTACK)
    defstat=(cat==:SPECIAL ? :SPECIAL_DEFENSE : :DEFENSE)
    # a[:damage] is rooted in the live position. Apply only virtual delta from
    # root stages to avoid double-counting the live stage already seen by AI.
    live_a=((attacker[:stages]||{})[atkstat]||0).to_i
    virt_a=competitive_coach_v21_stage(attacker,atkstat)
    live_d=((defender[:stages]||{})[defstat]||0).to_i
    virt_d=competitive_coach_v21_stage(defender,defstat)
    dmg*=competitive_coach_v21_stage_ratio(virt_a)/competitive_coach_v21_stage_ratio(live_a) if virt_a!=live_a
    dmg*=competitive_coach_v21_stage_ratio(live_d)/competitive_coach_v21_stage_ratio(virt_d) if virt_d!=live_d
    side=defender[:side]||{}
    if cat==:PHYSICAL && side[:reflect].to_i>0
      dmg*=0.5
    elsif cat==:SPECIAL && side[:light_screen].to_i>0
      dmg*=0.5
    end
    dmg*=0.5 if side[:aurora_veil].to_i>0
    # Expected accuracy branch. Deterministic effects are weighted by the same
    # probability below rather than pretending every inaccurate move connects.
    p=[[a[:accuracy].to_f/100.0,1.0].min,0.0].max
    [dmg*p,p]
  rescue
    [a[:damage].to_f*(a[:accuracy].to_f/100.0), a[:accuracy].to_f/100.0]
  end

  def competitive_coach_v21_apply_residual!(snap, state)
    return if snap[:hp].to_i<=0
    max=[snap[:max].to_i,1].max
    case snap[:status]
    when :BURN
      snap[:hp]=[snap[:hp].to_i-(max/16.0).floor,0].max
    when :POISON
      snap[:hp]=[snap[:hp].to_i-(max/8.0).floor,0].max
    end
    w=state[:weather]
    if (w==:Sandstorm || w==:Hail) && snap[:hp].to_i>0
      # Conservative chip: only apply when the snapshot does not advertise an
      # obvious type immunity. Ability/item weather immunity remains handled by
      # the root estimator and is intentionally not guessed here.
      ts=Array(snap[:types])
      immune=(w==:Sandstorm && ts.any?{|t| [:ROCK,:GROUND,:STEEL].include?(t)}) ||
             (w==:Hail && ts.include?(:ICE))
      snap[:hp]=[snap[:hp].to_i-(max/16.0).floor,0].max unless immune
    end
  end

  def competitive_coach_v21_tick!(s)
    [:our,:foe].each do |who|
      x=s[who]; side=x[:side]||{}
      [:reflect,:light_screen,:aurora_veil,:tailwind].each{|k| side[k]=[side[k].to_i-1,0].max if side[k].to_i>0}
      [:encore,:taunt,:confusion].each{|k| x[k]=[x[k].to_i-1,0].max if x[k].to_i>0}
      x[:protect]=false
      competitive_coach_v21_apply_residual!(x,s)
    end
    s[:turn]=s[:turn].to_i+1
  end

  alias competitive_coach_v21_prev_apply competitive_coach_v19_apply_move
  def competitive_coach_v19_apply_move(s,a,ours)
    ns=competitive_coach_v21_clone(s)
    me=ours ? ns[:our] : ns[:foe]; them=ours ? ns[:foe] : ns[:our]
    eff=a[:native_effect] || competitive_coach_v20_decode_function(a[:function])
    dmg,p=competitive_coach_v21_damage(a,me,them)
    # Protect/Substitute are explicit twin state rather than generic score.
    if them[:protect]
      dmg=0
    elsif them[:substitute].to_i>0 && dmg>0
      left=them[:substitute].to_i-dmg.round
      them[:substitute]=[left,0].max
      dmg=0
    else
      them[:hp]=[them[:hp].to_i-dmg.round,0].max
    end
    # Expected deterministic move effects. For accuracy <100%, scale strategic
    # changes conservatively by requiring >=50% hit probability.
    if p>=0.5
      competitive_coach_v20_apply_stage_hash!(me,eff[:self_stages]||{})
      competitive_coach_v20_apply_stage_hash!(them,eff[:target_stages]||{})
      if eff[:heal_frac]
        me[:hp]=[me[:hp].to_i+(me[:max].to_i*eff[:heal_frac]).round,me[:max].to_i].min
      elsif eff[:drain_frac]
        me[:hp]=[me[:hp].to_i+(dmg*eff[:drain_frac]).round,me[:max].to_i].min
      end
      me[:hp]=[me[:hp].to_i-(dmg*eff[:recoil_frac]).round,0].max if eff[:recoil_frac]
      me[:hp]=[me[:hp].to_i-(me[:max].to_i*eff[:recoil_hp_frac]).round,0].max if eff[:recoil_hp_frac]
      them[:status]=eff[:status] if eff[:status] && (them[:status].nil? || them[:status]==:NONE)
      them[:confusion]=3 if eff[:confuse]
      me[:protect]=true if eff[:protect]
      if eff[:substitute] && me[:hp].to_i>(me[:max].to_i/4)
        cost=(me[:max].to_i/4.0).floor; me[:hp]-=cost; me[:substitute]=cost
      end
      if eff[:screen]; me[:side]||={}; me[:side][eff[:screen]]=5; end
      if eff[:tailwind]; me[:side]||={}; me[:side][:tailwind]=4; end
      if eff[:hazard]
        them[:side]||={}
        case eff[:hazard]
        when :spikes then them[:side][:spikes]=[them[:side][:spikes].to_i+1,3].min
        when :toxic_spikes then them[:side][:toxic_spikes]=[them[:side][:toxic_spikes].to_i+1,2].min
        else them[:side][eff[:hazard]]=true
        end
      end
      if eff[:remove_hazards]
        me[:side]||={}; [:spikes,:toxic_spikes,:stealth_rock,:sticky_web].each{|k| me[:side][k]=(k==:spikes||k==:toxic_spikes ? 0 : false)}
      end
      ns[:weather]=eff[:weather] if eff[:weather]
      ns[:terrain]=eff[:terrain] if eff[:terrain]
    end
    step=(a[:stage_weight].to_i/12.0).round
    me[:stage_score]=[[me[:stage_score].to_i+step,6].min,-6].max
    competitive_coach_v21_tick!(ns) if ours==false
    ns
  rescue
    competitive_coach_v21_prev_apply(s,a,ours)
  end

  alias competitive_coach_v21_prev_eval competitive_coach_v19_terminal_eval
  def competitive_coach_v19_terminal_eval(s,ctx)
    base=competitive_coach_v21_prev_eval(s,ctx).to_i
    os=s[:our]; fs=s[:foe]
    # Digital-twin positional terms: real per-stat stages, substitutes, screens
    # and hazard pressure. Kept bounded so material/KO remains dominant.
    stage=0
    [:ATTACK,:DEFENSE,:SPECIAL_ATTACK,:SPECIAL_DEFENSE,:SPEED].each do |st|
      stage+=(competitive_coach_v21_stage(os,st)-competitive_coach_v21_stage(fs,st))*4
    end
    sub=(os[:substitute].to_i>0 ? 14 : 0)-(fs[:substitute].to_i>0 ? 14 : 0)
    screen=[:reflect,:light_screen,:aurora_veil,:tailwind].sum{|k| (os[:side]||{})[k].to_i>0 ? 4 : 0} -
           [:reflect,:light_screen,:aurora_veil,:tailwind].sum{|k| (fs[:side]||{})[k].to_i>0 ? 4 : 0}
    hazard=lambda{|x| sd=x[:side]||{}; sd[:spikes].to_i*5+sd[:toxic_spikes].to_i*5+(sd[:stealth_rock] ? 7:0)+(sd[:sticky_web] ? 5:0)}
    base+stage+sub+screen+hazard.call(fs)-hazard.call(os)
  rescue; competitive_coach_v21_prev_eval(s,ctx); end

  def competitive_coach_v21_noisy?(s,acts)
    hp1=s[:our][:hp].to_f/[s[:our][:max].to_i,1].max
    hp2=s[:foe][:hp].to_f/[s[:foe][:max].to_i,1].max
    return true if hp1<0.34 || hp2<0.34
    Array(acts).any?{|a| a[:damage].to_i>=s[:foe][:hp].to_i || a[:stage_weight].to_i.abs>=18}
  end

  alias competitive_coach_v21_prev_search competitive_coach_v19_search
  def competitive_coach_v19_search(ours,theirs,s,depth,maxing,alpha,beta,ctx)
    # Quiescence: at nominal leaf, extend volatile positions by up to two plies
    # instead of evaluating in the middle of a forced KO/setup sequence.
    if depth<=0 && s[:qdepth].to_i<2 && competitive_coach_v21_noisy?(s,maxing ? ours : theirs)
      qs=competitive_coach_v21_clone(s); qs[:qdepth]=s[:qdepth].to_i+1
      depth=1; s=qs
    end
    competitive_coach_v21_prev_search(ours,theirs,s,depth,maxing,alpha,beta,ctx)
  end

  alias competitive_coach_v21_prev_key competitive_coach_v19_key
  def competitive_coach_v19_key(s,depth,maxing)
    base=competitive_coach_v21_prev_key(s,depth,maxing)
    os=s[:our]; fs=s[:foe]
    base+[s[:turn].to_i,s[:qdepth].to_i,os[:item],fs[:item],os[:ability],fs[:ability],
      os[:encore].to_i,fs[:encore].to_i,os[:taunt].to_i,fs[:taunt].to_i,
      os[:side],fs[:side]]
  end

  alias competitive_coach_v21_prev_rec competitive_coach_recommendation
  def competitive_coach_recommendation(idxBattler)
    r=competitive_coach_v21_prev_rec(idxBattler)
    if r
      r[:engine]='V21-DIGITAL-TWIN'
      r[:digital_twin]=true
      r[:quiescence]=true
    end
    r
  rescue
    competitive_coach_v21_prev_rec(idxBattler)
  end
end
