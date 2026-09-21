#===============================================================================
# MOD: 038_Multiplayer_Detailed_Logs.rb
#-------------------------------------------------------------------------------
# Adiciona logs detalhados de batalha em Data/detailed_battle_log.txt
# Permite diagnosticar e encontrar desincronizações (desyncs) comparando logs
# do host e do cliente.
# Pode ser ativado/desativado no menu do F9 (Opções de Combate).
#===============================================================================

class PokemonSystem
  attr_writer :detailed_battle_log

  def detailed_battle_log
    @detailed_battle_log = 0 if @detailed_battle_log.nil? # 0 = Sim (Ativado por padrão), 1 = Não (Desativado)
    return @detailed_battle_log
  end
end

module AnilLanRework
  def self.detailed_battle_log_active?
    false
  end
end

if defined?(MenuHandlers)
  MenuHandlers.add(:debug_menu, :toggle_detailed_battle_log, {
    "name"        => _INTL("Log de Batalha Detalhado"),
    "parent"      => :battle_menu,
    "description" => _INTL("Salva logs ultra detalhados em Data/detailed_battle_log.txt para depurar desyncs."),
    "effect"      => proc {
      $PokemonSystem.detailed_battle_log = ($PokemonSystem.detailed_battle_log == 0) ? 1 : 0
      if $PokemonSystem.detailed_battle_log == 0
        pbMessage(_INTL("Log de Batalha Detalhado: ATIVADO.\nSalvo em Data/detailed_battle_log.txt"))
      else
        pbMessage(_INTL("Log de Batalha Detalhado: DESATIVADO."))
      end
    }
  })
end

class Battle
  def log_detailed(msg)
    return unless defined?(AnilLanRework) && AnilLanRework.detailed_battle_log_active?
    begin
      Dir.mkdir("Data") unless Dir.exist?("Data")
      File.open("Data/detailed_battle_log.txt", "a") do |f|
        turn_str = @turnCount ? "Turno:#{@turnCount}" : "Turno:?"
        f.puts("[#{Time.now.strftime('%H:%M:%S.%L')}] [#{turn_str}] #{msg}")
      end
    rescue => e
      PBDebug.log("Erro ao escrever log detalhado: #{e.message}") rescue nil
    end
  end

  # Limpa o arquivo no início da batalha
  alias anil_log_pbStartBattleCore pbStartBattleCore unless method_defined?(:anil_log_pbStartBattleCore)
  def pbStartBattleCore(*args)
    if defined?(AnilLanRework) && AnilLanRework.detailed_battle_log_active?
      begin
        Dir.mkdir("Data") unless Dir.exist?("Data")
        File.delete("Data/detailed_battle_log.txt") if File.exist?("Data/detailed_battle_log.txt")
      rescue
      end
    end

    result = anil_log_pbStartBattleCore(*args)

    if defined?(AnilLanRework) && AnilLanRework.detailed_battle_log_active?
      log_detailed("=== INÍCIO DA BATALHA ===")
      ctx = AnilLanRework::BattleSync.active_context rescue nil
      if ctx
        log_detailed("Contexto: modo=#{ctx.mode} battle_id=#{ctx.battle_id} client_index=#{ctx.client_index}")
        log_detailed("Seed/Estado RNG: #{ctx.rng&.state rescue 'nenhum'}")
      end
      if @player.is_a?(Array)
        @player.each_with_index { |pl, idx| log_detailed("Jogador #{idx}: #{pl&.name}") if pl }
      elsif @player
        log_detailed("Jogador: #{@player.name}")
      end

      if @opponent.is_a?(Array)
        @opponent.each_with_index { |op, idx| log_detailed("Oponente #{idx}: #{op&.name}") if op }
      elsif @opponent
        log_detailed("Oponente: #{@opponent.name}")
      end
      
      @battlers.each_with_index do |b, idx|
        next unless b
        log_detailed("Battler #{idx}: #{b.name} HP=#{b.hp}/#{b.totalhp} Lvl=#{b.level} Ability=#{b.ability_id} Item=#{b.item_id} Status=#{b.status}")
      end
    end

    result
  end

  # Loga o início de cada turno
  alias anil_log_pbCommandPhase pbCommandPhase unless method_defined?(:anil_log_pbCommandPhase)
  def pbCommandPhase(*args)
    if defined?(AnilLanRework) && AnilLanRework.detailed_battle_log_active?
      log_detailed("--- INÍCIO DA FASE DE COMANDOS (Turno #{@turnCount + 1}) ---")
      @battlers.each_with_index do |b, idx|
        next unless b
        log_detailed("Estado Battler #{idx}: #{b.name} HP=#{b.hp}/#{b.totalhp} Status=#{b.status} StatusCount=#{b.statusCount} Stages=#{b.stages.inspect} Effects=#{b.effects.inspect rescue 'error'}")
      end
    end
    anil_log_pbCommandPhase(*args)
  end

  # Loga mudanças de clima e terreno
  alias anil_log_pbStartWeather pbStartWeather unless method_defined?(:anil_log_pbStartWeather)
  def pbStartWeather(user, newWeather, fixedDuration = false, showAnim = true)
    old_weather = @field.weather
    result = anil_log_pbStartWeather(user, newWeather, fixedDuration, showAnim)
    if old_weather != @field.weather
      log_detailed("Clima Alterado: #{old_weather} -> #{@field.weather} (Duração: #{@field.weatherDuration}) por user=#{user ? user.index : 'nenhum'}")
    end
    result
  end

  alias anil_log_pbStartTerrain pbStartTerrain unless method_defined?(:anil_log_pbStartTerrain)
  def pbStartTerrain(user, newTerrain, fixedDuration = true)
    old_terrain = @field.terrain
    result = anil_log_pbStartTerrain(user, newTerrain, fixedDuration)
    if old_terrain != @field.terrain
      log_detailed("Terreno Alterado: #{old_terrain} -> #{@field.terrain} (Duração: #{@field.terrainDuration}) por user=#{user ? user.index : 'nenhum'}")
    end
    result
  end

  # Loga chamadas de RNG/rand dentro da batalha
  alias anil_log_rand rand unless method_defined?(:anil_log_rand)
  def rand(x = nil)
    result = anil_log_rand(x)
    if defined?(AnilLanRework) && AnilLanRework.detailed_battle_log_active?
      state_desc = ""
      if respond_to?(:anil_rework_rng) && anil_rework_rng
        state_desc = " RNGState=#{anil_rework_rng.state rescue 'error'}"
      end
      log_detailed("RAND: Max=#{x.inspect} Retorno=#{result.inspect}#{state_desc}")
    end
    result
  end

end

class Battle::Battler
  # Loga acerto e dano do movimento
  alias anil_log_pbProcessMoveHit pbProcessMoveHit unless method_defined?(:anil_log_pbProcessMoveHit)
  def pbProcessMoveHit(move, user, targets, hitNum, skipAccuracyCheck)
    result = anil_log_pbProcessMoveHit(move, user, targets, hitNum, skipAccuracyCheck)
    if @battle.respond_to?(:log_detailed)
      targets.each do |target|
        next unless target
        damage = target.damageState.hpLost rescue 0
        crit_str = (target.damageState.critical ? 'SIM' : 'NÃO') rescue 'NÃO'
        eff_str = target.damageState.typeMod rescue '?'
        @battle.log_detailed("Ataque Hit: User=#{user.index}(#{user.name rescue '?'}) Target=#{target.index}(#{target.name rescue '?'}) Move=#{move.name rescue '?'} HitNum=#{hitNum} Dano=#{damage} TargetHP=#{target.hp rescue '?'}/#{target.totalhp rescue '?'} Crit=#{crit_str} Eficácia=#{eff_str}")
      end
    end
    result
  end
  # Loga o uso de movimentos
  alias anil_log_pbUseMove pbUseMove unless method_defined?(:anil_log_pbUseMove)
  def pbUseMove(choice, specialUsage = false)
    move = choice[2]
    if move && @battle.respond_to?(:log_detailed)
      @battle.log_detailed("Uso de Movimento: User=#{@index}(#{name}) Move=#{move.name}(#{move.id}) Alvo=#{choice[3]} Especial=#{specialUsage}")
    end
    anil_log_pbUseMove(choice, specialUsage)
  end



  # Loga reduções e recuperações de HP
  alias anil_log_pbReduceHP pbReduceHP unless method_defined?(:anil_log_pbReduceHP)
  def pbReduceHP(amt, anim = true, registerDamage = true, anyAnim = true)
    oldHP = @hp
    result = anil_log_pbReduceHP(amt, anim, registerDamage, anyAnim)
    if @battle.respond_to?(:log_detailed) && result > 0
      @battle.log_detailed("HP Reduzido: Battler=#{@index}(#{name}) Perdido=#{result} HP=#{oldHP}->#{@hp} (Máx=#{@totalhp})")
    end
    result
  end

  alias anil_log_pbRecoverHP pbRecoverHP unless method_defined?(:anil_log_pbRecoverHP)
  def pbRecoverHP(amt, anim = true, anyAnim = true)
    oldHP = @hp
    result = anil_log_pbRecoverHP(amt, anim, anyAnim)
    if @battle.respond_to?(:log_detailed) && result > 0
      @battle.log_detailed("HP Recuperado: Battler=#{@index}(#{name}) Ganho=#{result} HP=#{oldHP}->#{@hp} (Máx=#{@totalhp})")
    end
    result
  end

  # Loga desmaio (Faint)
  alias anil_log_pbFaint pbFaint unless method_defined?(:anil_log_pbFaint)
  def pbFaint(showMessage = true)
    if @battle.respond_to?(:log_detailed)
      @battle.log_detailed("Battler Desmaiou: Battler=#{@index}(#{name}) HP=#{@hp}")
    end
    anil_log_pbFaint(showMessage)
  end

  # Loga alterações de status
  alias anil_log_status_equals status= unless method_defined?(:anil_log_status_equals)
  def status=(value)
    old_status = @status
    anil_log_status_equals(value)
    if @battle.respond_to?(:log_detailed) && old_status != value
      @battle.log_detailed("Status Alterado: Battler=#{@index}(#{name}) Status=#{old_status} -> #{value}")
    end
  end

  alias anil_log_statusCount_equals statusCount= unless method_defined?(:anil_log_statusCount_equals)
  def statusCount=(value)
    old_count = @statusCount
    anil_log_statusCount_equals(value)
    if @battle.respond_to?(:log_detailed) && old_count != value
      @battle.log_detailed("Contador Status Alterado: Battler=#{@index}(#{name}) Count=#{old_count} -> #{value}")
    end
  end

  # Loga alterações de estágios de atributos
  alias anil_log_pbRaiseStatStageBasic pbRaiseStatStageBasic unless method_defined?(:anil_log_pbRaiseStatStageBasic)
  def pbRaiseStatStageBasic(stat, increment, ignoreContrary = false)
    old_stage = @stages[stat]
    result = anil_log_pbRaiseStatStageBasic(stat, increment, ignoreContrary)
    if @battle.respond_to?(:log_detailed) && result != 0
      @battle.log_detailed("Stat Aumentado: Battler=#{@index}(#{name}) Stat=#{stat} Aumento=#{result} Estágio=#{old_stage}->#{@stages[stat]}")
    end
    result
  end

  alias anil_log_pbLowerStatStageBasic pbLowerStatStageBasic unless method_defined?(:anil_log_pbLowerStatStageBasic)
  def pbLowerStatStageBasic(stat, increment, ignoreContrary = false)
    old_stage = @stages[stat]
    result = anil_log_pbLowerStatStageBasic(stat, increment, ignoreContrary)
    if @battle.respond_to?(:log_detailed) && result != 0
      @battle.log_detailed("Stat Reduzido: Battler=#{@index}(#{name}) Stat=#{stat} Redução=#{result} Estágio=#{old_stage}->#{@stages[stat]}")
    end
    result
  end

  alias anil_log_pbResetStatStages pbResetStatStages unless method_defined?(:anil_log_pbResetStatStages)
  def pbResetStatStages
    if @battle.respond_to?(:log_detailed)
      @battle.log_detailed("Stats Reiniciados: Battler=#{@index}(#{name}) EstágiosAntes=#{@stages.inspect}")
    end
    anil_log_pbResetStatStages
  end
end

# Mantém suporte aos logs originais do anil_log
class Battle
  alias anil_log_original_pbGainExpOne pbGainExpOne unless method_defined?(:anil_log_original_pbGainExpOne)
  def pbGainExpOne(idxParty, defeatedBattler, numPartic, expShare, expAll, showMessages = true)
    pkmn = pbParty(0)[idxParty] rescue nil
    before_exp = pkmn ? pkmn.exp : 0
    before_lvl = pkmn ? pkmn.level : 0
    
    result = anil_log_original_pbGainExpOne(idxParty, defeatedBattler, numPartic, expShare, expAll, showMessages)
    
    after_exp = pkmn ? pkmn.exp : 0
    after_lvl = pkmn ? pkmn.level : 0
    gain = after_exp - before_exp
    
    if gain > 0
      if respond_to?(:log_detailed)
        log_detailed("Ganho EXP: PKMN=#{idxParty}(#{pkmn.name rescue '?'}) Gain=#{gain} Lvl=#{before_lvl}->#{after_lvl} Exp=#{before_exp}->#{after_exp}")
      end
      # Mantém compatibilidade com logs de rede padrão
      AnilLanRework.battle_log_detailed("xp_gain", {
        "pkmn" => "#{idxParty}(#{pkmn.name rescue '?'})",
        "gain" => gain,
        "level" => "#{before_lvl}->#{after_lvl}",
        "exp" => "#{before_exp}->#{after_exp}"
      }) rescue nil
    end
    result
  end
end

if defined?(Battle::Battler) && Battle::Battler.method_defined?(:pbContinualAbilityChecks) && !Battle::Battler.method_defined?(:anil_log_original_pbContinualAbilityChecks)
  class Battle::Battler
    alias anil_log_original_pbContinualAbilityChecks pbContinualAbilityChecks
    def pbContinualAbilityChecks(onSwitchIn = false)
      if hasActiveAbility?(:TRACE)
        # Loga no arquivo detalhado
        if @battle.respond_to?(:log_detailed)
          @battle.log_detailed("ContinualAbilityCheck: Battler=#{@index}(#{name}) Habilidade=TRACE switch_in=#{onSwitchIn}")
        end
        # Mantém compatibilidade antiga
        AnilLanRework.battle_log_detailed("ability_check", {
          "battler" => "#{self.index}(#{self.name})",
          "ability" => "TRACE",
          "onSwitchIn" => onSwitchIn
        }) rescue nil
      end
      anil_log_original_pbContinualAbilityChecks(onSwitchIn)
    end
  end
end

if defined?(Battle::AbilityEffects)
  module Battle::AbilityEffects
    class << self
      if method_defined?(:triggerOnSwitchIn) && !method_defined?(:anil_log_original_triggerOnSwitchIn)
        alias anil_log_original_triggerOnSwitchIn triggerOnSwitchIn
        def triggerOnSwitchIn(ability, battler, battle, switch_in = false)
          # Loga no arquivo detalhado
          if battle.respond_to?(:log_detailed)
            battle.log_detailed("Habilidade Ativada SwitchIn: Battler=#{battler.index}(#{battler.name}) Habilidade=#{ability} switch_in=#{switch_in}")
          end
          # Mantém compatibilidade antiga
          AnilLanRework.battle_log_detailed("ability_trigger", {
            "battler" => "#{battler.index}(#{battler.name})",
            "ability" => ability.to_s,
            "switch_in" => switch_in
          }) rescue nil
          anil_log_original_triggerOnSwitchIn(ability, battler, battle, switch_in)
        end
      end
    end
  end
end
