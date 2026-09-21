#===============================================================================
# Competitive Turn Coach v20 - Native Function-Code Rules Engine
# Decodes the game's own Battle::Move function_code naming scheme into a
# side-effect-free virtual transition model. No live Battle object is mutated.
#===============================================================================
class Battle
  COACH_V20_STATS = {
    "Attack"=>:ATTACK, "Defense"=>:DEFENSE, "SpAtk"=>:SPECIAL_ATTACK,
    "SpDef"=>:SPECIAL_DEFENSE, "Speed"=>:SPEED, "Accuracy"=>:ACCURACY,
    "Evasion"=>:EVASION, "Atk"=>:ATTACK, "Def"=>:DEFENSE, "Spd"=>:SPEED,
    "Acc"=>:ACCURACY
  }

  def competitive_coach_v20_decode_function(code)
    c=code.to_s; e={self_stages:{},target_stages:{}}
    # Native function codes encode most deterministic stat changes in the name.
    c.scan(/RaiseUser(Attack|Defense|SpAtk|SpDef|Speed|Accuracy|Evasion)([123])/).each { |st,n| e[:self_stages][COACH_V20_STATS[st]]=n.to_i }
    c.scan(/LowerUser(Attack|Defense|SpAtk|SpDef|Speed|Accuracy|Evasion)([123])/).each { |st,n| e[:self_stages][COACH_V20_STATS[st]]=-n.to_i }
    c.scan(/LowerTarget(Attack|Defense|SpAtk|SpDef|Speed|Accuracy|Evasion)([123])/).each { |st,n| e[:target_stages][COACH_V20_STATS[st]]=-n.to_i }
    c.scan(/RaiseTarget(Attack|Defense|SpAtk|SpDef|Speed|Accuracy|Evasion)([123])/).each { |st,n| e[:target_stages][COACH_V20_STATS[st]]=n.to_i }
    # Compact multi-stat codes used heavily by Essentials/Añil.
    compact={"Atk"=>:ATTACK,"Def"=>:DEFENSE,"SpAtk"=>:SPECIAL_ATTACK,"SpDef"=>:SPECIAL_DEFENSE,"Spd"=>:SPEED,"Acc"=>:ACCURACY}
    [[/RaiseUser((?:Atk|Def|SpAtk|SpDef|Spd|Acc)+)([123])/,1], [/LowerUser((?:Atk|Def|SpAtk|SpDef|Spd|Acc)+)([123])/, -1]].each do |rx,sgn|
      if c =~ rx
        seq=$1; n=$2.to_i*sgn
        seq.scan(/SpAtk|SpDef|Atk|Def|Spd|Acc/).each { |x| e[:self_stages][compact[x]]=n }
      end
    end
    [[/LowerTarget((?:Atk|Def|SpAtk|SpDef|Spd|Acc)+)([123])/, -1], [/RaiseTarget((?:Atk|Def|SpAtk|SpDef|Spd|Acc)+)([123])/,1]].each do |rx,sgn|
      if c =~ rx
        seq=$1; n=$2.to_i*sgn
        seq.scan(/SpAtk|SpDef|Atk|Def|Spd|Acc/).each { |x| e[:target_stages][compact[x]]=n }
      end
    end
    e[:status]=:SLEEP if c =~ /SleepTarget/
    e[:status]=:POISON if c =~ /PoisonTarget/ && c !~ /BadPoisonTarget/
    e[:status]=:POISON if c =~ /BadPoisonTarget/
    e[:toxic]=true if c =~ /BadPoisonTarget/
    e[:status]=:PARALYSIS if c =~ /ParalyzeTarget/
    e[:status]=:BURN if c =~ /BurnTarget/
    e[:confuse]=true if c =~ /ConfuseTarget/
    e[:flinch]=true if c =~ /FlinchTarget/
    e[:heal_frac]=1.0 if c =~ /HealUserFully/
    e[:heal_frac]=0.5 if c =~ /HealUserHalfOfTotalHP/
    e[:heal_frac]=0.25 if c =~ /HealUserAndAlliesQuarterOfTotalHP/
    e[:drain_frac]=0.5 if c =~ /HealUserByHalfOfDamageDone/
    e[:drain_frac]=0.75 if c =~ /HealUserByThreeQuartersOfDamageDone/
    e[:recoil_frac]=0.25 if c =~ /RecoilQuarterOfDamageDealt/
    e[:recoil_frac]=1.0/3.0 if c =~ /RecoilThirdOfDamageDealt/
    e[:recoil_frac]=0.5 if c =~ /RecoilHalfOfDamageDealt/
    e[:recoil_hp_frac]=0.5 if c =~ /RecoilHalfOfTotalHP/
    e[:protect]=true if c =~ /^ProtectUser/
    e[:substitute]=true if c =~ /UserMakeSubstitute/
    e[:pivot]=true if c =~ /SwitchOutUser/
    e[:force_switch]=true if c =~ /SwitchOutTarget/
    e[:hazard]=:spikes if c =~ /AddSpikesToFoeSide/
    e[:hazard]=:toxic_spikes if c =~ /AddToxicSpikesToFoeSide/
    e[:hazard]=:stealth_rock if c =~ /AddStealthRocksToFoeSide/
    e[:hazard]=:sticky_web if c =~ /AddStickyWebToFoeSide/
    e[:remove_hazards]=true if c =~ /RemoveUserBindingAndEntryHazards|RemoveHazards/
    e[:screen]=:reflect if c=="StartWeakenPhysicalDamageAgainstUserSide"
    e[:screen]=:light_screen if c=="StartWeakenSpecialDamageAgainstUserSide"
    e[:screen]=:aurora_veil if c=="StartWeakenDamageAgainstUserSideIfHail"
    e[:tailwind]=true if c=="StartUserSideDoubleSpeed"
    e[:encore]=true if c=="DisableTargetUsingDifferentMove"
    e[:taunt]=true if c=="DisableTargetStatusMoves"
    e[:weather]=:Sun if c=="StartSunWeather"; e[:weather]=:Rain if c=="StartRainWeather"
    e[:weather]=:Sandstorm if c=="StartSandstormWeather"; e[:weather]=:Hail if c=="StartHailWeather"
    e[:terrain]=:Electric if c=="StartElectricTerrain"; e[:terrain]=:Grassy if c=="StartGrassyTerrain"
    e[:terrain]=:Misty if c=="StartMistyTerrain"; e[:terrain]=:Psychic if c=="StartPsychicTerrain"
    e
  rescue; {self_stages:{},target_stages:{}}; end

  def competitive_coach_v20_contrary?(snap)
    (snap[:ability] rescue nil)==:CONTRARY
  end

  def competitive_coach_v20_apply_stage_hash!(snap, changes)
    snap[:vstages] ||= {}
    changes.each do |st,d|
      d=-d if competitive_coach_v20_contrary?(snap)
      snap[:vstages][st]=[[snap[:vstages].fetch(st,0).to_i+d.to_i,6].min,-6].max
    end
  end

  alias competitive_coach_v20_prev_snapshot competitive_coach_v19_battler_snapshot
  def competitive_coach_v19_battler_snapshot(b)
    h=competitive_coach_v20_prev_snapshot(b)
    h[:vstages]={}
    h
  end

  alias competitive_coach_v20_prev_actions competitive_coach_v19_move_actions
  def competitive_coach_v19_move_actions(battler,target,ctx)
    rows=competitive_coach_v20_prev_actions(battler,target,ctx)
    rows.each do |a|
      a[:native_effect]=competitive_coach_v20_decode_function(a[:function])
      mv=(battler.moves[a[:index]] rescue nil)
      a[:category]=(mv.category rescue nil)
    end
    rows
  end

  def competitive_coach_v20_offense_mult(snap,action)
    cat=(action[:category] rescue nil)
    st=(cat==:SPECIAL ? :SPECIAL_ATTACK : :ATTACK)
    competitive_coach_v19_stage_mult((snap[:vstages]||{}).fetch(st,0))
  rescue; 1.0; end

  alias competitive_coach_v20_prev_apply competitive_coach_v19_apply_move
  def competitive_coach_v19_apply_move(s,a,ours)
    ns=Marshal.load(Marshal.dump(s)) rescue s.dup
    me=ours ? ns[:our] : ns[:foe]; them=ours ? ns[:foe] : ns[:our]
    eff=a[:native_effect] || competitive_coach_v20_decode_function(a[:function])
    # Expected damage branch. v7 already uses the game's AI damage estimator.
    dmg=a[:damage].to_f*a[:accuracy].to_f/100.0
    dmg*=competitive_coach_v20_offense_mult(me,a)
    side=them[:side]||{}
    dmg*=0.67 if side[:aurora_veil].to_i>0
    them[:hp]=[them[:hp].to_i-dmg.round,0].max
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
    if eff[:screen]
      me[:side]||={}; me[:side][eff[:screen]]=5
    end
    if eff[:tailwind]
      me[:side]||={}; me[:side][:tailwind]=4
    end
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
    ns[:weather]=eff[:weather] if eff[:weather]; ns[:terrain]=eff[:terrain] if eff[:terrain]
    # Keep v14's broad strategic stage score as a secondary signal for custom
    # effects not yet expressible by deterministic native decoding.
    step=(a[:stage_weight].to_i/12.0).round
    me[:stage_score]=[[me[:stage_score].to_i+step,6].min,-6].max
    ns
  rescue
    competitive_coach_v20_prev_apply(s,a,ours)
  end

  alias competitive_coach_v20_prev_key competitive_coach_v19_key
  def competitive_coach_v19_key(s,depth,maxing)
    base=competitive_coach_v20_prev_key(s,depth,maxing)
    os=(s[:our][:vstages]||{}); fs=(s[:foe][:vstages]||{})
    base+[os[:ATTACK],os[:DEFENSE],os[:SPECIAL_ATTACK],os[:SPECIAL_DEFENSE],os[:SPEED],
          fs[:ATTACK],fs[:DEFENSE],fs[:SPECIAL_ATTACK],fs[:SPECIAL_DEFENSE],fs[:SPEED],
          s[:weather],s[:terrain]]
  end

  alias competitive_coach_v20_prev_rec competitive_coach_recommendation
  def competitive_coach_recommendation(idxBattler)
    r=competitive_coach_v20_prev_rec(idxBattler)
    if r
      r[:engine]='V20-NATIVE-RULES'
      r[:native_rules]=true
    end
    r
  rescue
    competitive_coach_v20_prev_rec(idxBattler)
  end
end
