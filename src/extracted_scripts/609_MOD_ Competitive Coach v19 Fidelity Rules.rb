#===============================================================================
# Competitive Turn Coach v19 - Fidelity / Rules-Aware Search Layer
# Uses only battle state already legitimately available to this client.
# Never mutates the live Battle object while searching.
#===============================================================================
class Battle
  COACH_V19_STAGE_STATS = [:ATTACK,:DEFENSE,:SPECIAL_ATTACK,:SPECIAL_DEFENSE,:SPEED,:ACCURACY,:EVASION]

  def competitive_coach_v19_effect(b, name, default=0)
    return default if !b || !defined?(PBEffects)
    k=PBEffects.const_get(name) rescue nil
    return default if k.nil?
    v=b.effects[k] rescue default
    v.nil? ? default : v
  rescue; default; end

  def competitive_coach_v19_stages(b)
    h={}
    COACH_V19_STAGE_STATS.each { |s| h[s]=(b.stages[s].to_i rescue 0) }
    h
  rescue; {}; end

  def competitive_coach_v19_side_snapshot(b)
    side=(b.pbOwnSide rescue nil)
    {
      spikes:(side.effects[PBEffects::Spikes].to_i rescue 0),
      toxic_spikes:(side.effects[PBEffects::ToxicSpikes].to_i rescue 0),
      stealth_rock:!!(side.effects[PBEffects::StealthRock] rescue false),
      sticky_web:!!(side.effects[PBEffects::StickyWeb] rescue false),
      reflect:(side.effects[PBEffects::Reflect].to_i rescue 0),
      light_screen:(side.effects[PBEffects::LightScreen].to_i rescue 0),
      aurora_veil:(side.effects[PBEffects::AuroraVeil].to_i rescue 0),
      tailwind:(side.effects[PBEffects::Tailwind].to_i rescue 0)
    }
  rescue; {}; end

  def competitive_coach_v19_battler_snapshot(b)
    {
      hp:b.hp.to_i,max:[b.totalhp.to_i,1].max,status:(b.status rescue :NONE),
      stages:competitive_coach_v19_stages(b),
      substitute:competitive_coach_v19_effect(b,:Substitute,0).to_i,
      encore:competitive_coach_v19_effect(b,:Encore,0).to_i,
      taunt:competitive_coach_v19_effect(b,:Taunt,0).to_i,
      confusion:competitive_coach_v19_effect(b,:Confusion,0).to_i,
      protect:!!competitive_coach_v19_effect(b,:Protect,false),
      leech_seed:competitive_coach_v19_effect(b,:LeechSeed,-1).to_i,
      choice:(b.effects[PBEffects::ChoiceBand] rescue nil),
      ability:(b.ability rescue nil),item:(b.item rescue nil),
      types:(b.pbTypes(true) rescue []),side:competitive_coach_v19_side_snapshot(b)
    }
  rescue; {hp:1,max:1,stages:{},side:{}}; end

  def competitive_coach_v19_stage_mult(stage)
    s=[[stage.to_i,6].min,-6].max
    s>=0 ? (2.0+s)/2.0 : 2.0/(2.0-s)
  end

  def competitive_coach_v19_speed(b,snap)
    raw=(b.pbSpeed.to_i rescue 1)
    st=(snap[:stages][:SPEED].to_i rescue 0)
    # pbSpeed already reflects the live stage; only virtual deltas are handled
    # by the search state after the root.
    raw=[raw,1].max
    raw*=2 if (snap[:side][:tailwind].to_i rescue 0)>0
    raw.to_i
  rescue; 1; end

  def competitive_coach_v19_move_legal?(b,mv)
    return false if !mv || (mv.pp.to_i<=0 rescue false)
    if competitive_coach_v19_effect(b,:Taunt,0).to_i>0 && (mv.statusMove? rescue false)
      return false
    end
    enc=competitive_coach_v19_effect(b,:Encore,0).to_i
    if enc>0
      enc_id=(b.effects[PBEffects::EncoreMove] rescue nil)
      return false if enc_id && (mv.id rescue nil)!=enc_id
    end
    cho=(b.effects[PBEffects::ChoiceBand] rescue nil)
    if cho && cho!=0 && cho!=-1
      return false if (mv.id rescue nil)!=cho
    end
    true
  rescue; true; end

  def competitive_coach_v19_move_actions(battler,target,ctx)
    rows=[]; return rows if !battler || !target
    ai=competitive_coach_v7_ai(battler.index) rescue nil
    Array(battler.moves).each_with_index do |mv,i|
      next unless competitive_coach_v19_move_legal?(battler,mv)
      dmg=competitive_coach_v7_damage(ai,mv,target).to_i rescue 0
      acc=competitive_coach_v12_accuracy(ai,mv,target).to_f rescue 100.0
      util=competitive_coach_v12_role_bonus(mv,battler,target,ctx).to_i rescue 0
      util+=competitive_coach_v13_synergy_bonus(battler,mv,target,ctx).to_i rescue 0
      delta=competitive_coach_v14_stage_delta(battler,mv,target,ctx).to_i rescue 0
      # Keep the signed/weighted v14 delta rather than discarding negative
      # effects. Contrary-aware v14 already reverses self drops where relevant.
      rows << {kind: :move,index:i,name:mv.name.to_s,id:(mv.id rescue nil),
        damage:dmg,accuracy:acc,priority:(mv.priority.to_i rescue 0),
        stage_weight:delta,utility:util,status:(mv.statusMove? rescue false),
        function:(mv.function_code.to_s rescue '')}
    end
    rows.sort!{|x,y| (y[:damage]+y[:utility])<=>(x[:damage]+x[:utility])}
    rows[0,6] || rows
  rescue; []; end

  def competitive_coach_v19_terminal_eval(s,ctx)
    return 20000 if s[:foe][:hp]<=0 && s[:our][:hp]>0
    return -20000 if s[:our][:hp]<=0 && s[:foe][:hp]>0
    hp=(s[:our][:hp].to_f/s[:our][:max]-s[:foe][:hp].to_f/s[:foe][:max])*220.0
    material=(ctx[:own_alive].to_i-ctx[:foe_alive].to_i)*34
    stages=(s[:our][:stage_score].to_i-s[:foe][:stage_score].to_i)*11
    status=0
    status-=18 if s[:our][:status] && s[:our][:status]!=:NONE
    status+=18 if s[:foe][:status] && s[:foe][:status]!=:NONE
    hp.round+material+stages+status
  end

  def competitive_coach_v19_apply_move(s,a,ours)
    ns=Marshal.load(Marshal.dump(s)) rescue s.dup
    me=ours ? ns[:our] : ns[:foe]; them=ours ? ns[:foe] : ns[:our]
    dmg=(a[:damage].to_f*a[:accuracy].to_f/100.0)
    # Virtual setup changes future output; stage_weight is normalized to a
    # bounded strategic stage score, not blindly treated as raw stat stages.
    boost=[[me[:stage_score].to_i,6].min,-6].max
    dmg*=competitive_coach_v19_stage_mult(boost) if boost!=0
    # Screens are represented in state and reduce the approximate branch damage.
    side=them[:side]||{}
    dmg*=0.67 if (side[:aurora_veil].to_i>0 rescue false)
    them[:hp]=[them[:hp].to_i-dmg.round,0].max
    step=(a[:stage_weight].to_i/12.0).round
    me[:stage_score]=[[me[:stage_score].to_i+step,6].min,-6].max
    ns
  rescue; s; end

  def competitive_coach_v19_key(s,depth,maxing)
    [depth,maxing,s[:our][:hp]/3,s[:foe][:hp]/3,s[:our][:stage_score],s[:foe][:stage_score],
     s[:our][:status],s[:foe][:status],s[:our][:substitute].to_i/10,s[:foe][:substitute].to_i/10]
  end

  def competitive_coach_v19_search(ours,theirs,s,depth,maxing,alpha,beta,ctx)
    @competitive_coach_v19_nodes+=1
    return competitive_coach_v19_terminal_eval(s,ctx) if depth<=0 || @competitive_coach_v19_nodes>=@competitive_coach_v19_budget || s[:our][:hp]<=0 || s[:foe][:hp]<=0
    key=competitive_coach_v19_key(s,depth,maxing)
    return @competitive_coach_v19_tt[key] if @competitive_coach_v19_tt.key?(key)
    acts=maxing ? ours : theirs
    acts=acts[0,(depth>=6 ? 3 : 5)] || []
    return competitive_coach_v19_terminal_eval(s,ctx) if acts.empty?
    best=maxing ? -999999 : 999999
    acts.each do |a|
      ns=competitive_coach_v19_apply_move(s,a,maxing)
      immediate=maxing ? a[:utility].to_i : -a[:utility].to_i
      val=immediate+competitive_coach_v19_search(ours,theirs,ns,depth-1,!maxing,alpha,beta,ctx)
      if maxing
        best=val if val>best; alpha=best if best>alpha; break if beta<=alpha
      else
        best=val if val<best; beta=best if best<beta; break if beta<=alpha
      end
    end
    @competitive_coach_v19_tt[key]=best if @competitive_coach_v19_tt.length<20000
    best
  rescue; competitive_coach_v19_terminal_eval(s,ctx); end

  alias competitive_coach_v19_previous_recommendation competitive_coach_recommendation
  def competitive_coach_recommendation(idxBattler)
    base=competitive_coach_v19_previous_recommendation(idxBattler)
    return base if !base
    ctx=competitive_coach_team_context(idxBattler) rescue nil
    user=@battlers[idxBattler] rescue nil
    foe=(ctx[:foes][0] rescue nil)
    return base if !ctx || !user || !foe
    alive=[ctx[:own_alive].to_i+ctx[:foe_alive].to_i,1].max
    @competitive_coach_v19_nodes=0; @competitive_coach_v19_tt={}
    @competitive_coach_v19_budget=alive<=4 ? 120000 : (alive<=7 ? 55000 : 22000)
    maxdepth=alive<=4 ? 10 : (alive<=7 ? 8 : 6)
    ours=competitive_coach_v19_move_actions(user,foe,ctx)
    theirs=competitive_coach_v19_move_actions(foe,user,ctx)
    # Preserve the proven v13/v14 switch/sack layer as root candidates. The
    # fidelity tree itself searches moves; switch lines remain safety-gated.
    switches=competitive_coach_v18_switch_actions(idxBattler,foe,ctx) rescue []
    return base if ours.empty? || theirs.empty?
    us=competitive_coach_v19_battler_snapshot(user); fs=competitive_coach_v19_battler_snapshot(foe)
    state={our:us.merge(stage_score:0),foe:fs.merge(stage_score:0)}
    completed=nil; depth=2
    while depth<=maxdepth && @competitive_coach_v19_nodes<@competitive_coach_v19_budget
      pass=[]
      ours.each do |a|
        break if @competitive_coach_v19_nodes>=@competitive_coach_v19_budget
        ns=competitive_coach_v19_apply_move(state,a,true)
        v=a[:utility].to_i+competitive_coach_v19_search(ours,theirs,ns,depth-1,false,-999999,999999,ctx)
        pass << [v,a]
      end
      completed=pass unless pass.empty?; depth+=2
    end
    ranked=(completed||[]).sort{|x,y| y[0]<=>x[0]}
    if !ranked.empty?
      best=ranked[0]; alt=ranked[1]
      # Hard tactical knowledge remains authoritative unless deeper search has
      # a meaningful margin. This protects Safety Gate and intentional sacks.
      if base[:best].to_s==best[1][:name].to_s || (alt && best[0]-alt[0]>=24)
        base[:best]=best[1][:name]
      end
      base[:alternative]=(alt ? alt[1][:name] : base[:alternative])
      base[:search_score]=best[0].to_i
    end
    base[:search_nodes]=@competitive_coach_v19_nodes
    base[:search_depth]=[depth-2,maxdepth].min
    base[:search_budget]=@competitive_coach_v19_budget
    base[:engine]='V19-FIDELITY-RULES'
    base[:fidelity]=true
    base
  rescue => e
    PBDebug.log("[CompetitiveCoachV19] #{e.class}: #{e.message}") rescue nil
    competitive_coach_v19_previous_recommendation(idxBattler)
  end
end
