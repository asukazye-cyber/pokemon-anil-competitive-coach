# ======================================================================
# MÓDULO: CORE COMPLETO
# Fonte: 0449_Multiplayer_Anil.rb (14673 linhas)
# Cópia fiel 1:1 do script original para facilitar manutenção.
# ======================================================================

# encoding: UTF-8
#===============================================================================
# Multiplayer Anil — Script Unificado
# Gerado em: 2026-04-30
#
# Este arquivo contem TODO o sistema multiplayer integrado:
#   SECAO 1 — Script principal (Multiplayer Anil Cable Rework)
#   SECAO 2 — Correcoes de preview/selecao PvP
#   SECAO 3 — Correcoes de bugs (desync, double wild, coop, busy balloon)
#
# Instrucoes:
#   Cole este script inteiro no Plugin Manager ou editor de scripts.
#   NAO e necessario nenhum outro arquivo de patch.
#   Ordem: coloque APOS os scripts nativos do Pokemon Essentials.
#===============================================================================
#===============================================================================
# SECAO 1 — Script Principal: Multiplayer Anil Cable Rework
#===============================================================================

#===============================================================================
# Multiplayer Anil Cable Rework
# Active compiled build.
# This file is the current multiplayer runtime source.
#===============================================================================
require "socket"

class AnilMainMenuRedirectException < Exception
end

module AnilLanPureJSON
  module_function

  def normalize_string(value)
    text = value.to_s.dup
    begin
      utf8 = text.dup.force_encoding(Encoding::UTF_8)
      return utf8 if utf8.valid_encoding?
    rescue
    end
    begin
      return text.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "?")
    rescue
    end
    text.force_encoding(Encoding::UTF_8) rescue nil
    text
  end

  def deep_normalize(value)
    case value
    when Hash
      normalized = {}
      value.each { |k, v| normalized[normalize_string(k)] = deep_normalize(v) }
      normalized
    when Array
      value.map { |item| deep_normalize(item) }
    when String
      normalize_string(value)
    else
      value
    end
  end

  def escape_string(value)
    normalize_string(value).gsub('\\', '\\\\\\\\').gsub('"', '\\"').gsub("\n", '\\n').gsub("\r", '')
  end

  def encode(obj)
    case obj
    when Hash
      "{" + obj.map { |k, v| "\"#{escape_string(k)}\":#{encode(v)}" }.join(",") + "}"
    when Array
      "[" + obj.map { |v| encode(v) }.join(",") + "]"
    when String
      "\"#{escape_string(obj)}\""
    when Integer, Float
      obj.to_s
    when true
      "true"
    when false
      "false"
    when NilClass
      "null"
    else
      "\"#{escape_string(obj.to_s)}\""
    end
  end

  def decode(str)
    return nil if str.nil? || str.strip.empty?
    begin
      deep_normalize(parse_container(str.strip))
    rescue
      nil
    end
  end

  def parse_container(source)
    case source[0]
    when "{"
      result = {}
      source = source[1..-2].to_s.strip
      until source.empty?
        match = source.match(/\A"((?:[^"\\]|\\.)*)"\s*:\s*/)
        break unless match
        key = normalize_string(match[1].gsub('\\"', '"').gsub('\\n', "\n").gsub('\\\\', '\\'))
        source = match.post_match
        value, source = decode_value(source)
        result[key] = value
        source = source.lstrip.sub(/\A,/, "").lstrip
      end
      result
    when "["
      result = []
      source = source[1..-2].to_s.strip
      until source.empty?
        value, source = decode_value(source)
        result << value
        source = source.lstrip.sub(/\A,/, "").lstrip
      end
      result
    else
      decode_value(source)[0]
    end
  end

  def decode_value(source)
    source = source.to_s.lstrip
    if source.start_with?('"')
      match = source.match(/\A"((?:[^"\\]|\\.)*)"/)
      return [nil, source] unless match
      value = normalize_string(match[1].gsub('\\"', '"').gsub('\\n', "\n").gsub('\\\\', '\\'))
      [value, source[match[0].length..-1]]
    elsif source.start_with?("{") || source.start_with?("[")
      open_c  = source[0]
      close_c = (open_c == "{") ? "}" : "]"
      depth   = 0
      i       = 0
      in_str  = false
      escape  = false
      source.each_char do |ch|
        if escape
          escape = false
        elsif ch == "\\" && in_str
          escape = true
        elsif ch == '"'
          in_str = !in_str
        elsif !in_str
          depth += 1 if ch == open_c
          depth -= 1 if ch == close_c
        end
        i += 1
        break if depth == 0
      end
      [parse_container(source[0...i]), source[i..-1]]
    elsif source.start_with?("true")
      [true, source[4..-1]]
    elsif source.start_with?("false")
      [false, source[5..-1]]
    elsif source.start_with?("null")
      [nil, source[4..-1]]
    else
      match = source.match(/\A-?[\d]+(?:\.[\d]+)?/)
      return [nil, source] unless match
      value = match[0].include?(".") ? match[0].to_f : match[0].to_i
      [value, source[match[0].length..-1]]
    end
  end
end

# ==============================================================================
# 5. ANUNCIOS PASSIVOS DE HABILIDADE EM BATALHAS ONLINE
#    Alguns textos/splashes de habilidade nao alteram a logica da batalha, mas
#    podem aparecer em ordem diferente entre os clientes e abrir dessync visual.
#    Aqui silenciamos os anuncios mais problematicos no LAN e mantemos apenas os
#    efeitos mecanicos.
# ==============================================================================
module AnilLanRework
  class << self
    attr_accessor :multiplayer_mode
    attr_accessor :intentional_disconnect
    attr_accessor :pending_restore_coords

    def apply_coordinate_restore!(coords)
      return unless coords.is_a?(Hash)
      map_id = coords["map_id"].to_i
      x = coords["x"].to_i
      y = coords["y"].to_i
      dir = (coords["dir"] || 2).to_i

      return if map_id <= 0
      return unless $game_player && $game_map

      # Evita teleporte redundante se já estiver na posição correta
      if $game_map.map_id == map_id && $game_player.x == x && $game_player.y == y
        $game_player.direction = dir if $game_player.direction != dir rescue nil
        return
      end

      AnilLanRework.log("apply_coordinate_restore!: restoring to map=#{map_id} x=#{x} y=#{y} dir=#{dir}")

      begin
        if $game_map.map_id == map_id
          if defined?(pbFadeOutIn)
            pbFadeOutIn {
              $game_player.moveto(x, y)
              $game_player.direction = dir rescue nil
              $game_player.straighten rescue nil
              if defined?(AnilCoordFix) && AnilCoordFix.respond_to?(:fix_player_position)
                AnilCoordFix.fix_player_position rescue nil
              end
              $game_map.autoplay rescue nil
              $game_map.refresh rescue nil
            }
          else
            $game_player.moveto(x, y)
            $game_player.direction = dir rescue nil
            $game_player.straighten rescue nil
            if defined?(AnilCoordFix) && AnilCoordFix.respond_to?(:fix_player_position)
              AnilCoordFix.fix_player_position rescue nil
            end
          end
        else
          $game_temp.player_transferring = true rescue nil
          $game_temp.player_new_map_id = map_id rescue nil
          $game_temp.player_new_x = x rescue nil
          $game_temp.player_new_y = y rescue nil
          $game_temp.player_new_direction = dir rescue nil
        end
      rescue => e
        AnilLanRework.log("apply_coordinate_restore! error: #{e.class}: #{e.message}")
      end
    end

    # ⚠️ ISTO NUNCA PERGUNTOU "ESTOU NO JOIPLAY". Pergunta "estou no Android".
    #
    # Enquanto o Android so chegava por JoiPlay, os dois eram a mesma coisa e o
    # nome nao incomodava. Deixam de ser no dia em que existir um APK nativo:
    # esse tambem responde true a tudo o que esta aqui em baixo (ANDROID_ROOT,
    # /sdcard, System.platform), e ai heranca de nome vira bug.
    #
    # Os contornos dividem-se em dois grupos:
    #   • do ANDROID          — ecra tactil, memoria, sistema de ficheiros
    #   • do JOIPLAY          — o CR do updater, o refresh de graficos que
    #                           ele nao aguenta, o teclado que engole o apagar
    #
    # O segundo grupo nao se aplica a um build nativo, e alguns fariam mal la.
    # Separam-se agora, enquanto se sabe qual e qual — depois de existir o APK
    # ja ninguem se lembra.
    def android?
      return true if ENV['ANDROID_ROOT'] || ENV['ANDROID_DATA']
      return true if File.exist?("/system/app") || Dir.exist?("/sdcard") rescue false
      return true if System.platform =~ /android/i rescue false
      false
    end

    # ⚠️ Especificamente o JoiPlay, e nao "Android".
    #
    # O $joiplay e posto pelo proprio JoiPlay. O `mkxp_nativo?` e a saida: num
    # APK feito por nos, deixa-se um ficheiro marcador ao extrair os assets, e
    # a partir dai o jogo sabe que esta em casa e nao dentro do JoiPlay.
    def joiplay?
      return false if mkxp_nativo?
      return true if defined?($joiplay) && $joiplay
      android?
    end

    # Marcador deixado pelo instalador do APK nativo ao extrair o jogo.
    def mkxp_nativo?
      return @mkxp_nativo unless @mkxp_nativo.nil?
      @mkxp_nativo = (File.exist?("Data/apk_nativo.txt") rescue false)
    rescue
      @mkxp_nativo = false
    end

    def show_image_overlay(filename, message = nil, force_title: false)
      return unless defined?(Graphics) && defined?(Viewport) && defined?(Sprite)
      begin
        path = pbResolveBitmap("Graphics/Pictures/" + filename) rescue nil
        path ||= "Graphics/Pictures/" + filename if File.exist?("Graphics/Pictures/" + filename)
        return unless path

        viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
        viewport.z = 999999
        
        # Fundo escurecido - solido para esconder o mapa completamente
        bg_sprite = Sprite.new(viewport)
        bg_sprite.bitmap = Bitmap.new(Graphics.width, Graphics.height)
        bg_sprite.bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(0, 0, 0, 255))
        
        # Imagem de aviso principal
        img_sprite = Sprite.new(viewport)
        img_sprite.bitmap = Bitmap.new(path)
        img_sprite.x = (Graphics.width - img_sprite.bitmap.width) / 2
        img_sprite.y = (Graphics.height - img_sprite.bitmap.height) / 2
        
        # Sprite de texto manual para o modo force_title (não usa pbMessage)
        text_sprite = nil
        if force_title && message
          # Limpa formatação de controle do pbMessage (\r[...], \n, \c[N])
          clean_msg = message.to_s.dup
          clean_msg.gsub!(/\\r\[([^\]]+)\]/, '\1')  # \r[titulo] -> titulo
          clean_msg.gsub!(/\\c\[\d+\]/, '')           # \c[N] -> remove
          clean_msg.gsub!(/\\n/, "\n")                # \n literal -> newline
          lines = clean_msg.split("\n").map { |l| l.strip }
          
          text_w = Graphics.width - 40
          text_h = [lines.size * 28 + 20, 200].min
          text_y = img_sprite.y + img_sprite.bitmap.height + 10
          text_y = [text_y, Graphics.height - text_h - 10].min
          
          text_sprite = Sprite.new(viewport)
          text_sprite.bitmap = Bitmap.new(text_w, text_h)
          text_sprite.x = (Graphics.width - text_w) / 2
          text_sprite.y = text_y
          text_sprite.z = 100
          
          # Fundo semi-transparente para o texto
          text_sprite.bitmap.fill_rect(0, 0, text_w, text_h, Color.new(0, 0, 0, 180))
          
          text_sprite.bitmap.font.size = 18
          text_sprite.bitmap.font.bold = false
          lines.each_with_index do |line, i|
            # Titulo em destaque (primeira linha)
            if i == 0
              text_sprite.bitmap.font.bold = true
              text_sprite.bitmap.font.color = Color.new(255, 200, 80)
            else
              text_sprite.bitmap.font.bold = false
              text_sprite.bitmap.font.color = Color.new(255, 255, 255)
            end
            text_sprite.bitmap.draw_text(10, 10 + i * 26, text_w - 20, 26, line, 1)
          end
        end
        
        Graphics.update rescue nil
        
        if force_title
          # Modo force_title: loop isolado com timer, SEM pbMessage
          # Isso impede que menus subjacentes processem input
          start_time = Time.now.to_f
          loop do
            if Graphics.respond_to?(:anil_rework_update)
              Graphics.anil_rework_update
            else
              Graphics.update
            end
            Input.update rescue nil
            break if Input.trigger?(Input::USE) || Input.trigger?(Input::BACK)
            break if Time.now.to_f - start_time >= 5.0
          end
        elsif message
          pbMessage(message)
        else
          start_time = Time.now.to_f
          loop do
            if Graphics.respond_to?(:anil_rework_update)
              Graphics.anil_rework_update
            else
              Graphics.update
            end
            Input.update rescue nil
            break if Input.trigger?(Input::USE) || Input.trigger?(Input::BACK)
            break if Time.now.to_f - start_time >= 5.0
          end
        end
      ensure
        if $antighost_exiting_to_title
          if defined?(antighost_create_persistent_black_overlay!)
            antighost_create_persistent_black_overlay! rescue nil
          end
        end
        Graphics.freeze rescue nil
        text_sprite.bitmap.dispose rescue nil if text_sprite && text_sprite.bitmap
        text_sprite.dispose rescue nil if text_sprite
        img_sprite.bitmap.dispose rescue nil if img_sprite && img_sprite.bitmap
        img_sprite.dispose rescue nil if img_sprite
        bg_sprite.bitmap.dispose rescue nil if bg_sprite && bg_sprite.bitmap
        bg_sprite.dispose rescue nil if bg_sprite
        viewport.dispose rescue nil if viewport
      end
    end

    # Congela todo o jogo, exibe a tela de desconexão e vai diretamente para o título.
    # Não usa pbMessage nem raises — garante que nenhum menu subjacente processe input.
    def force_main_title!(overlay_file, message)
      $antighost_exiting_to_title = true
      
      # Prepara estado visual para desconexão
      AnilAntiBlackScreen.prepare_server_disconnect! rescue nil
      
      # Exibe imagem do servidor offline com loop isolado (sem pbMessage)
      show_image_overlay(overlay_file, message, force_title: true) rescue nil
      
      # Marca flags de pós-desconexão
      $anil_abs_pending_fix     = true
      $anil_abs_post_disconnect = true
      SaveData.mark_values_as_unloaded if defined?(SaveData.mark_values_as_unloaded)
      
      # Vai direto para o título sem raise de exception
      $scene = pbCallTitle
    end

    unless defined?(AnilPlayerUnstuckException)
      class AnilPlayerUnstuckException < Exception; end
    end

    # Executa a transferência imediata do jogador para tirá-lo de um estado travado
    def perform_unstuck_transfer(map_id, x, y, direction = 2)
      begin
        # Grava log inicial
        begin
          curr_map = $game_map ? $game_map.map_id : "nil"
          curr_x = $game_player ? $game_player.x : "nil"
          curr_y = $game_player ? $game_player.y : "nil"
          scene_class = $scene ? $scene.class : "nil"
          has_spriteset = $scene && $scene.is_a?(Scene_Map) && !$scene.instance_variable_get(:@spritesetGlobal).nil?
          
          File.open("unstuck_debug.log", "a") do |f|
            f.puts("--- UNSTUCK ATTEMPT: #{Time.now} ---")
            f.puts("Target location: Map #{map_id}, X #{x}, Y #{y}, Dir #{direction}")
            f.puts("Current location: Map #{curr_map}, X #{curr_x}, Y #{curr_y}")
            f.puts("Scene class: #{scene_class}, Has spriteset: #{has_spriteset}")
          end rescue nil
        rescue Exception => log_err
        end

        # Detecta se o jogador está em estado travado/ocupado (diálogo, batalha, menu ou outra cena)
        is_stuck = false
        if !$scene.is_a?(Scene_Map) || 
           $scene.instance_variable_get(:@spritesetGlobal).nil? ||
           (defined?($game_temp) && $game_temp && ($game_temp.message_window_showing || $game_temp.in_menu || $game_temp.in_battle)) ||
           (pbMapInterpreterRunning? rescue false)
          is_stuck = true
        end

        # Cancela batalha ativa se houver
        active_ctx = AnilLanRework::BattleSync.active_context rescue nil
        if active_ctx && active_ctx.battle
          active_ctx.battle.decision = 5 rescue nil
        end

        # Destrava o jogador (limpa rotas forçadas e travas de movimento)
        if $game_player
          begin
            $game_player.instance_variable_set(:@move_route_forcing, false)
          rescue Exception; end
          begin
            $game_player.instance_variable_set(:@move_route, nil)
          rescue Exception; end
          begin
            $game_player.instance_variable_set(:@locked, false)
          rescue Exception; end
          begin
            $game_player.unlock
          rescue Exception; end
          begin
            if $game_player.respond_to?(:through=)
              $game_player.through = false
            else
              $game_player.instance_variable_set(:@through, false)
            end
          rescue Exception; end
          begin
            if $game_player.respond_to?(:transparent=)
              $game_player.transparent = false
            else
              $game_player.instance_variable_set(:@transparent, false)
            end
          rescue Exception; end
        end
        
        # Destrava todos os eventos do mapa e limpa rotas forçadas neles
        if $game_map && $game_map.respond_to?(:events) && $game_map.events
          $game_map.events.values.each do |event|
            next unless event
            begin
              event.unlock
            rescue Exception; end
            begin
              event.instance_variable_set(:@move_route_forcing, false)
            rescue Exception; end
            begin
              event.instance_variable_set(:@move_route, nil)
            rescue Exception; end
            begin
              event.instance_variable_set(:@starting, false)
            rescue Exception; end
          end rescue nil
        end
        
        # Reativa menus, saves e encontros, e limpa interpretador de eventos travados
        if $game_system
          begin
            $game_system.menu_disabled = false
          rescue Exception; end
          begin
            $game_system.save_disabled = false
          rescue Exception; end
          begin
            $game_system.encounter_disabled = false
          rescue Exception; end
          if $game_system.respond_to?(:map_interpreter) && $game_system.map_interpreter
            begin
              $game_system.map_interpreter.clear
            rescue Exception; end
            begin
              $game_system.map_interpreter.setup(nil, 0)
            rescue Exception; end
          end
        end
        
        # Limpa variáveis temporárias de eventos e janelas de mensagem
        if $game_temp
          begin
            $game_temp.common_event_id = 0
          rescue Exception; end
          begin
            $game_temp.message_window_showing = false
          rescue Exception; end
          begin
            $game_temp.in_battle = false
          rescue Exception; end
          begin
            $game_temp.in_menu = false
          rescue Exception; end
        end

        if defined?(AnilLanRework) && AnilLanRework.respond_to?(:message_active=)
          AnilLanRework.message_active = false rescue nil
        end

        # Reseta tom da tela e flashes
        if $game_screen
          $game_screen.start_tone_change(Tone.new(0,0,0,0), 0) rescue nil
          $game_screen.start_flash(Color.new(0,0,0,0), 0) rescue nil
        end

        # Configura as variáveis de transferência no game_temp
        $game_temp.player_transferring = true rescue nil
        $game_temp.player_new_map_id = map_id rescue nil
        $game_temp.player_new_x = x rescue nil
        $game_temp.player_new_y = y rescue nil
        $game_temp.player_new_direction = direction rescue nil
        $game_temp.transition_processing = true rescue nil

        pbDismountBike rescue nil
        
        # Se o jogador estiver em outra cena (menu, batalha, etc), força retorno ao mapa
        if !$scene.is_a?(Scene_Map)
          $scene = Scene_Map.new rescue nil
        end
        
        # Executa transferência suave imediata se já estiver no mapa
        if $scene.is_a?(Scene_Map)
          begin
            $scene.transfer_player
            File.open("unstuck_debug.log", "a") do |f|
              f.puts("Immediate smooth transfer executed successfully.")
            end rescue nil
          rescue Exception => e
            File.open("unstuck_debug.log", "a") do |f|
              f.puts("Error in immediate smooth transfer: #{e.class}: #{e.message}. Letting engine transfer next frame.")
            end rescue nil
          end
        end
      rescue Exception => outer_err
        if outer_err.is_a?(AnilPlayerUnstuckException)
          raise outer_err
        else
          File.open("unstuck_debug.log", "a") do |f|
            f.puts("FATAL Error in perform_unstuck_transfer outer: #{outer_err.class}: #{outer_err.message}")
            f.puts(outer_err.backtrace.join("\n"))
          end rescue nil
        end
      end
    end
  end
  @multiplayer_mode = false unless defined?(@multiplayer_mode)
  @intentional_disconnect = false unless defined?(@intentional_disconnect)

  # Ver a nota no 0000_Disable_Debug_Logs: ligar isto para diagnostico travou o
  # "recuperar partida" em 2026-08-01. O log por-linha abre e fecha o ficheiro a
  # cada chamada; nos caminhos pesados (recover, carregar mapa) isso sozinho
  # congela o jogo. Diagnosticar com ficheiro proprio, nao com este interruptor.
  $anil_debug_log_enabled = false
  $anil_battle_verbose_log_enabled = false
  BATTLE_VERBOSE_LOG_FILE = "multiplayer_battle_debug.txt" unless const_defined?(:BATTLE_VERBOSE_LOG_FILE)
# --- [REMOVIDO] Bloco de codigo (linhas 199 a 289) movido para 000d_Multiplayer_Battle_Trade_RNG_Sync.rb ---
end

if defined?(Battle::AbilityEffects)
  Battle::AbilityEffects::AfterMoveUseFromTarget.add(:OVERGROW,
    proc { |ability, target, user, move, switched_battlers, battle|
      next if !target.droppedBelowThirdHP
      if AnilLanRework::BattleSync.suppress_passive_ability_text?(battle, ability)
        AnilLanRework.log("lan passive ability text suppressed battle_id=#{AnilLanRework::BattleSync.active_context&.battle_id} ability=#{ability} battler=#{target.index}")
        next
      end
      battle.pbShowAbilitySplash(target)
      type = GameData::Ability.get(ability).flags[0] if !GameData::Ability.get(ability).flags.empty?
      type = GameData::Type.get(type).name if type && GameData::Type.exists?(type)
      if type
        battle.pbDisplay(_INTL("¡{1} activado! Los ataques de tipo {2} de {3} ahora son más potentes.", target.abilityName, type, target.pbThis(true)))
      else
        battle.pbDisplay(_INTL("¡{1} activado! Los ataques del primer tipo de {2} ahora son más potentes.", target.abilityName, target.pbThis(true)))
      end
      battle.pbHideAbilitySplash(target)
    }
  )
  Battle::AbilityEffects::AfterMoveUseFromTarget.copy(:OVERGROW, :TORRENT, :BLAZE, :SWARM, :SOBRECARGA)

  Battle::AbilityEffects::OnSwitchIn.add(:OVERGROW,
    proc { |ability, battler, battle, switch_in|
      next if battler.hp > (battler.totalhp / 3).floor
      if AnilLanRework::BattleSync.suppress_passive_ability_text?(battle, ability)
        AnilLanRework.log("lan switch-in ability text suppressed battle_id=#{AnilLanRework::BattleSync.active_context&.battle_id} ability=#{ability} battler=#{battler.index}")
        next
      end
      battle.pbShowAbilitySplash(battler)
      type = GameData::Ability.get(ability).flags[0] if !GameData::Ability.get(ability).flags.empty?
      type = GameData::Type.get(type).name if type && GameData::Type.exists?(type)
      if type
        battle.pbDisplay(_INTL("¡{1} activado! Los ataques de tipo {2} de {3} ahora son más potentes.", battler.abilityName, type, battler.pbThis(true)))
      else
        battle.pbDisplay(_INTL("¡{1} activado! Los ataques del primer tipo de {2} ahora son más potentes.", battler.abilityName, battler.pbThis(true)))
      end
      battle.pbHideAbilitySplash(battler)
    }
  )
  Battle::AbilityEffects::OnSwitchIn.copy(:OVERGROW, :TORRENT, :BLAZE, :SWARM, :SOBRECARGA)

  Battle::AbilityEffects::OnSwitchIn.add(:INTIMIDATE,
    proc { |ability, battler, battle, switch_in|
      next if battler.effects[PBEffects::OneUseAbility] == ability
      show_splash = !AnilLanRework::BattleSync.suppress_entry_ability_splash?(battle, ability)
      battle.pbShowAbilitySplash(battler) if show_splash
      battle.allOtherSideBattlers(battler.index).each do |b|
        next if !b.near?(battler)
        check_item = true
        if b.hasActiveAbility?([:CONTRARY, :GUARDDOG])
          check_item = false if b.statStageAtMax?(:ATTACK)
        elsif b.statStageAtMin?(:ATTACK)
          check_item = false
        end
        check_ability = b.pbLowerAttackStatStageIntimidate(battler)
        b.pbAbilitiesOnIntimidated if check_ability
        b.pbItemOnIntimidatedCheck if check_item
      end
      battle.pbHideAbilitySplash(battler) if show_splash
      battler.effects[PBEffects::OneUseAbility] = ability
    }
  )

  Battle::AbilityEffects::OnSwitchIn.add(:ESPANTO,
    proc { |ability, battler, battle, switch_in|
      next if battler.effects[PBEffects::OneUseAbility] == ability
      show_splash = !AnilLanRework::BattleSync.suppress_entry_ability_splash?(battle, ability)
      battle.pbShowAbilitySplash(battler) if show_splash
      battle.allOtherSideBattlers(battler.index).each do |b|
        next if !b.near?(battler)
        check_item = true
        if b.hasActiveAbility?([:CONTRARY])
          check_item = false if b.statStageAtMax?(:SPECIAL_ATTACK)
        elsif b.statStageAtMin?(:SPECIAL_ATTACK)
          check_item = false
        end
        check_ability = b.pbLowerSpecialAttackStatStageIntimidate(battler)
        b.pbAbilitiesOnIntimidated if check_ability
        b.pbItemOnIntimidatedCheck if check_item
      end
      battle.pbHideAbilitySplash(battler) if show_splash
      battler.effects[PBEffects::OneUseAbility] = ability
    }
  )

  Battle::AbilityEffects::OnSwitchIn.add(:ILLUMINATE,
    proc { |ability, battler, battle, switch_in|
      next if battler.effects[PBEffects::OneUseAbility] == ability
      show_splash = !AnilLanRework::BattleSync.suppress_entry_ability_splash?(battle, ability)
      battle.pbShowAbilitySplash(battler) if show_splash
      battle.allOtherSideBattlers(battler.index).each do |b|
        next if !b.near?(battler)
        b.pbLowerStatStageByAbility(:ACCURACY, 1, battler, false)
      end
      battle.pbHideAbilitySplash(battler) if show_splash
      battler.effects[PBEffects::OneUseAbility] = ability
    }
  )
end

module AnilLanRework
  PLAYER_CFG = "multiplayer_player.txt"
  IP_CFG     = "multiplayer_ip.txt"
  COOP_PARTIAL_CFG_KEY = "coop_partial"
  COOP_TOTAL_CFG_KEY   = "coop_total"

  def self.read_cfg(file, key, default = "")
    if File.exist?(file)
      File.readlines(file, encoding: "UTF-8").each do |line|
        parts = line.strip.split("=", 2)
        return parts[1].to_s.strip if parts.size == 2 && parts[0].strip == key
      end
    end
    default
  end

  def self.write_cfg(file, key, value)
    rows = {}
    if File.exist?(file)
      File.readlines(file, encoding: "UTF-8").each do |line|
        parts = line.strip.split("=", 2)
        rows[parts[0].strip] = parts[1].to_s.strip if parts.size == 2
      end
    end
    rows[key] = value.to_s
    File.open(file, "w:UTF-8") do |f|
      rows.each { |k, v| f.puts("#{k}=#{v}") }
    end
  end

  def self.cfg_true?(file, key, default = false)
    value = read_cfg(file, key, default ? "1" : "0").to_s.strip.downcase
    return true if ["1", "true", "on", "yes", "sim"].include?(value)
    return false if ["0", "false", "off", "no", "nao"].include?(value)
    default
  end

  def self.coop_partial_enabled?
    cfg_true?(PLAYER_CFG, COOP_PARTIAL_CFG_KEY, true)
  end

  def self.coop_total_enabled?
    cfg_true?(PLAYER_CFG, COOP_TOTAL_CFG_KEY, false)
  end

  def self.set_coop_partial_enabled(enabled)
    enabled = enabled ? true : false
    write_cfg(PLAYER_CFG, COOP_PARTIAL_CFG_KEY, enabled ? "1" : "0")
    write_cfg(PLAYER_CFG, COOP_TOTAL_CFG_KEY, "0") if enabled
  end

  def self.set_online_level_cap_state(active)
    return unless defined?($player) && $player
    $player.connecting_online = (active ? true : false) if $player.respond_to?(:connecting_online=)
  rescue
  end

  def self.set_coop_total_enabled(enabled)
    enabled = enabled ? true : false
    write_cfg(PLAYER_CFG, COOP_TOTAL_CFG_KEY, enabled ? "1" : "0")
    write_cfg(PLAYER_CFG, COOP_PARTIAL_CFG_KEY, "0") if enabled
  end
end

module System
  def self.uptime
    Time.now.to_f
  end
end unless defined?(System) && System.respond_to?(:uptime)

def lerp(a, b, duration, start_time, current_time = nil)
  return b.to_f if duration <= 0
  delta = current_time ? (current_time.to_f - start_time.to_f) : start_time.to_f
  return a.to_f if delta <= 0
  return b.to_f if delta >= duration
  a + (b - a) * (delta / duration.to_f)
end

class Game_Temp
  attr_accessor :anil_pending_multiplayer_auto_connect
end

# Log dedicado da auto-conexao.
#
# ⚠️ Nao usar AnilLanRework.log aqui: ele so escreve com $anil_debug_log_enabled
# ligado, e ligar essa global quebra o "recuperar partida" (ver a nota de
# logs-nao-ligar-global). Ficheiro proprio, com o MESMO interruptor do updater
# (Data/anil_debug.txt), que ja e o que se pede ao jogador para criar.
# Tela preta "Carregando" que cobre o overworld enquanto a conexao nao resolve.
#
# Existe porque o save do servidor NUNCA deve ser jogado offline: sem ela ha um
# intervalo em que o mundo esta visivel e jogavel sem ligacao — da para andar,
# falar com NPC e entrar em batalha, e so depois o jogo fica online, com o
# servidor sem saber de nada do que aconteceu.
#
# Viewport com z altissimo para ficar por cima de tudo, inclusive dos HUDs.
module AnilTelaCarregando
  module_function

  def visivel?
    !@sprite.nil?
  end

  def mostrar!(texto = "Carregando...", atualizar_ecra = true)
    return if @sprite
    @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 99999
    @sprite = Sprite.new(@viewport)
    @sprite.bitmap = Bitmap.new(Graphics.width, Graphics.height)
    @sprite.bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(0, 0, 0))
    begin
      pbSetSystemFont(@sprite.bitmap)
    rescue
    end
    @sprite.bitmap.font.color = Color.new(255, 255, 255)
    # Faixa centrada verticalmente. Com o rect da altura toda o texto saía
    # colado ao topo em vez de ao centro.
    altura_faixa = 40
    @sprite.bitmap.draw_text(0, (Graphics.height - altura_faixa) / 2, Graphics.width, altura_faixa, texto, 1)
    Graphics.update if atualizar_ecra
  rescue => e
    anil_autoconnect_log("falha ao criar a tela de carregamento: #{e.class}: #{e.message}")
  end

  # Reescreve o texto sem derrubar a tela — usado para trocar "Carregando..."
  # por uma mensagem de erro no mesmo ecra preto.
  def trocar_texto!(texto)
    return unless @sprite && @sprite.bitmap && !@sprite.bitmap.disposed?
    @sprite.opacity = 255
    @sprite.bitmap.clear
    @sprite.bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(0, 0, 0))
    begin
      pbSetSystemFont(@sprite.bitmap)
    rescue
    end
    @sprite.bitmap.font.color = Color.new(255, 255, 255)
    altura_faixa = 40
    @sprite.bitmap.draw_text(0, (Graphics.height - altura_faixa) / 2, Graphics.width, altura_faixa, texto, 1)
    Graphics.update
  rescue
  end

  # Some em fade, revelando o mundo ja conectado.
  def esconder_em_fade!(frames = 24)
    return unless @sprite
    passo = 255.0 / [frames, 1].max
    frames.times do
      @sprite.opacity = [@sprite.opacity - passo, 0].max
      Graphics.update
      Input.update
    end
    descartar!
  rescue
    descartar!
  end

  def descartar!
    @sprite.bitmap.dispose if @sprite && @sprite.bitmap && !@sprite.bitmap.disposed?
    @sprite.dispose if @sprite && !@sprite.disposed?
    @viewport.dispose if @viewport && !@viewport.disposed?
  rescue
  ensure
    @sprite = nil
    @viewport = nil
  end
end

# Caminho de FALHA: mostra o erro no proprio ecra preto e volta ao titulo.
#
# ⚠️ Nao usa force_main_title!: aquele caminho passa por show_image_overlay, e
# eu tinha-o envolvido em `rescue nil` — quando ele falhava, a tela preta era
# descartada e o jogo seguia para o overworld OFFLINE, que e precisamente o que
# nao pode acontecer. Aqui os passos sao explicitos e cada falha e registada.
#
# Os passos 1, 3 e 4 sao os mesmos do force_main_title! (desconectar, blackout,
# marcar valores como nao carregados); so o overlay de imagem e que sai.
# O treinador ainda nao tem nome proprio?
#
# `Player.new("Unnamed", ...)` (0032_Game_SaveValues) e o que o Essentials cria
# ao comecar um jogo novo; o nome real so entra quando o jogador o escreve na
# introducao. Enquanto for "Unnamed" (ou vazio) nao ha conta que o servidor
# possa amarrar — ligar nessa altura e o que fazia o Novo Jogo falhar.
#
# "jogador" tambem conta como sem nome: e o placeholder que o servidor usa nas
# entradas de whitelist e que o update_whitelisted_name! recusa gravar.
# A ligacao seria recusada agora, por um dos patches que embrulham o
# trigger_auto_connect_on_map?
#
# Espelha o portao do 099_Save_Coordinate_Fix (PARTE 2): durante o Novo Jogo e
# nos mapas da introducao ele repoe a flag de pendente e sai sem ligar.
#
# Saber isto ANTES evita o ciclo inutil que o log mostrou: levantar a tela preta,
# congelar o jogador, contar 80 frames, tentar, ser adiado, baixar a tela —
# SETE vezes seguidas por cima da introducao, com o "Carregando..." a piscar. Com
# esta verificacao espera-se em silencio, sem tela e sem congelar ninguem.
#
# ⚠️ A lista de mapas esta duplicada de proposito (o 099 nao a expoe). Se ela
# mudar la, tem de mudar aqui — o pior que acontece e voltar o pisca-pisca.
def anil_autoconnect_seria_adiado?
  return true if $game_temp && $game_temp.respond_to?(:begun_new_game) && $game_temp.begun_new_game
  return true if $game_map && [1, 29, 104].include?($game_map.map_id)
  false
rescue
  false
end

def anil_autoconnect_sem_nome?
  # O 099_Save_Coordinate_Fix ja mantem esta lista (unnamed/unamed/jogador/
  # trainer/treinador/player). Delegar evita duas nocoes de "nome placeholder"
  # a divergirem com o tempo; a lista local fica so como recurso se o 099 nao
  # tiver carregado.
  if AnilLanRework.respond_to?(:placeholder_player_name?)
    return AnilLanRework.placeholder_player_name? ? true : false
  end
  nome = ($player && $player.respond_to?(:name) ? $player.name.to_s.strip : "")
  return true if nome.empty?
  return true if nome.casecmp("Unnamed").zero?
  return true if nome.casecmp("jogador").zero?
  false
rescue
  true
end

def anil_autoconnect_falhar!(mensagem)
  anil_autoconnect_log("FALHA: #{mensagem} — voltando ao titulo")

  # A tela pode ter sido descartada por outro caminho; garante que ha algo preto
  # por cima antes de escrever o erro.
  AnilTelaCarregando.mostrar!(mensagem) unless AnilTelaCarregando.visivel?
  AnilTelaCarregando.trocar_texto!(mensagem)

  # 1. Fecha socket e threads antes de qualquer transicao de cena.
  begin
    AnilLanRework.disconnect(false) if AnilLanRework.respond_to?(:disconnect)
  rescue => e
    anil_autoconnect_log("  disconnect falhou: #{e.class}: #{e.message}")
  end

  # 2. Tempo de leitura (~2,5s a 60fps).
  150.times do
    Graphics.update rescue nil
    Input.update rescue nil
  end

  # 3. Estado limpo, senao a proxima tentativa herda os sinalizadores desta.
  AnilLanRework.multiplayer_mode = false rescue nil
  $game_temp.anil_pending_multiplayer_auto_connect = false if $game_temp.respond_to?(:anil_pending_multiplayer_auto_connect=)
  $anil_auto_connect_agendado      = nil
  $anil_autoconnect_espera_ja_comecou = nil
  $anil_autoconnect_ja_relatou     = nil
  $anil_autoconnect_ramo_relatado  = nil
  $anil_autoconnect_espera_relatada = nil
  $anil_autoconnect_flag_anterior  = nil
  anil_autoconnect_destravar_jogador!

  # 4. Blackout do anti-tela-preta, para o freeze da cena nova capturar preto.
  begin
    $antighost_exiting_to_title = true
    antighost_start_blackout! if defined?(antighost_start_blackout!)
    AnilAntiBlackScreen.prepare_server_disconnect! if defined?(AnilAntiBlackScreen)
  rescue => e
    anil_autoconnect_log("  blackout falhou: #{e.class}: #{e.message}")
  end

  AnilTelaCarregando.descartar!
  $anil_abs_pending_fix     = true
  $anil_abs_post_disconnect = true
  begin
    SaveData.mark_values_as_unloaded if defined?(SaveData) && SaveData.respond_to?(:mark_values_as_unloaded)
  rescue
  end

  $scene = pbCallTitle
  anil_autoconnect_log("cena trocada para o titulo")
rescue => e
  # Ultimo recurso: se ate isto falhar, ir para o titulo continua a ser melhor
  # do que deixar entrar offline.
  anil_autoconnect_log("ERRO no caminho de falha: #{e.class}: #{e.message}") rescue nil
  ($scene = pbCallTitle) rescue nil
end

# O save tem credenciais do servidor e ainda nao ha ligacao?
# Usado para decidir se o mundo pode ou nao ser mostrado.
def anil_autoconnect_precisa_conectar?
  return false if AnilLanRework.connected? rescue true
  oid = ($PokemonGlobal && $PokemonGlobal.respond_to?(:online_id))      ? $PokemonGlobal.online_id.to_s.strip      : ""
  wc  = ($PokemonGlobal && $PokemonGlobal.respond_to?(:whitelist_code)) ? $PokemonGlobal.whitelist_code.to_s.strip : ""
  if wc.empty? && defined?($player) && $player && $player.respond_to?(:whitelist_code)
    wc = $player.whitelist_code.to_s.strip
  end
  if oid.empty? && defined?($player) && $player && $player.respond_to?(:online_id)
    oid = $player.online_id.to_s.strip
  end
  !oid.empty? && (wc =~ /\A\d{6}\z/ ? true : false)
rescue
  false
end

class Scene_Map
  # ⚠️ A tela preta tem de subir AQUI, e nao no primeiro update.
  #
  # `main` faz createSpritesets e logo a seguir Graphics.transition — e nessa
  # transicao que o mundo aparece. Como o update so corre depois, cobrir la
  # deixava o overworld piscar na tela antes de ser tapado, que e exactamente o
  # que nao se quer num save que ainda nem esta ligado ao servidor.
  alias anil_autoconnect_orig_main main unless method_defined?(:anil_autoconnect_orig_main)

  def main
    begin
      # ESTADO DA SESSAO ANTERIOR NAO PODE SOBREVIVER A ESTA.
      #
      # `$anil_auto_connect_agendado` guarda o online_id ja agendado e SO era
      # limpo no caminho de falha — depois de uma ligacao bem sucedida ficava
      # com o oid para sempre. Ao voltar ao titulo e carregar de novo (Multi
      # Save) isso dava dois estragos de uma vez:
      #
      #   1. o agendamento nao repetia, porque a condicao e
      #      `$anil_auto_connect_agendado != oid` e o oid e o MESMO jogador;
      #   2. a rede de seguranca la em baixo via `agendado` verdadeiro, a tela
      #      levantada, a flag por false e nenhuma ligacao — e concluia FALHA.
      #
      # Resultado: a primeira tentativa de entrar dava sempre erro, e como o
      # caminho de falha limpa a variavel, a segunda entrava. Era o "sempre na
      # primeira tentativa retorna erro".
      #
      # `Scene_Map#main` corre uma vez por sessao de mapa (mudar de mapa nao
      # recria a cena), por isso e o sitio certo para comecar do zero. So se
      # limpa quando NAO ha ligacao viva, para nao pisar uma sessao a decorrer.
      begin
        unless AnilLanRework.connected?
          if $anil_auto_connect_agendado || $anil_autoconnect_flag_anterior
            anil_autoconnect_log("nova sessao de mapa: limpando estado do auto-connect anterior (agendado=#{$anil_auto_connect_agendado.inspect})")
          end
          $anil_auto_connect_agendado       = nil
          $anil_autoconnect_flag_anterior   = nil
          $anil_autoconnect_ja_relatou      = nil
          $anil_autoconnect_ramo_relatado   = nil
          $anil_autoconnect_espera_relatada = nil
          $anil_autoconnect_porque_nao_agendou = nil
          $anil_autoconnect_espera_ja_comecou  = nil
        end
      rescue
      end

      if anil_autoconnect_precisa_conectar? && !AnilTelaCarregando.visivel? &&
         !anil_autoconnect_seria_adiado? && !anil_autoconnect_sem_nome?
        # sem Graphics.update aqui: os spritesets ainda nao existem e o proprio
        # `main` trata de desenhar a seguir.
        #
        # Na introducao esta tela nao sobe: nao ha mundo por tapar e ela cobria
        # a cutscene inteira. Ver anil_autoconnect_seria_adiado?.
        AnilTelaCarregando.mostrar!(_INTL("Carregando..."), false)
        anil_autoconnect_log("tela de carregamento levantada antes do transition")
      end
    rescue => e
      anil_autoconnect_log("falha ao cobrir antes do transition: #{e.class}: #{e.message}") rescue nil
    end
    anil_autoconnect_orig_main
  end
end

# Solta o jogador congelado pela espera de conexao. Idempotente, e so mexe na
# tranca se foi ESTE codigo que a pos — para nao fechar a caixa de texto de
# outra coisa que tenha aberto entretanto.
def anil_autoconnect_destravar_jogador!
  return unless $anil_autoconnect_input_travado
  $anil_autoconnect_input_travado = false
  $game_temp.message_window_showing = false if $game_temp.respond_to?(:message_window_showing=)
rescue
end

# ⚠️ UM INTERRUPTOR SO PARA TODOS OS DIAGNOSTICOS.
#
# Havia sete ficheiros de log e so quatro olhavam para o Data/anil_debug.txt.
# Os outros tres (skin_sync, anil_save_atrasado, anil_stats_pvp) escreviam
# sempre — nasceram assim porque o log global nao pode ser ligado (trava o
# "recuperar partida") e cada um resolveu o seu problema sozinho. Em producao
# isso dava 2,3 MB so de skin_sprite_log.
#
# Agora todos passam por aqui. Sem o ficheiro, ninguem escreve nada.
#
# A resposta fica em cache: isto e chamado a cada linha de log, e um
# File.exist? por linha e I/O a serio no telemovel. Para voltar a ligar, cria-se
# o ficheiro e reinicia-se o jogo.
def anil_diagnostico_ligado?
  # ⚠️ ESTE File.exist? E O UNICO QUE NAO SE SUBSTITUI.
  #
  # E a propria leitura do interruptor. Um substituir global de
  # File.exist?("Data/anil_debug.txt") por anil_diagnostico_ligado? apanhou esta
  # linha e o metodo passou a chamar-se a si proprio — SystemStackError no
  # arranque, o jogo nem abria.
  if $anil_diag_cache.nil?
    $anil_diag_cache = (File.exist?("Data/anil_debug.txt") rescue false)
  end
  $anil_diag_cache
end

def anil_autoconnect_log(msg)
  return unless anil_diagnostico_ligado?
  File.open("Data/autoconnect_log.txt", "a") do |f|
    f.puts("[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] #{msg}")
  end
rescue
end

module AnilLanRework
  VERSION            = "draft-2026-04-11"

  # Versao dos SCRIPTS do cliente, enviada no join. O servidor compara com o
  # min_client_build do server.json e recusa quem estiver abaixo, mandando
  # baixar a atualizacao.
  #
  # BUMPAR A CADA PACOTE PUBLICADO. Formato numerico separado por pontos
  # ("4.0.7", "4.0.8"...), comparado campo a campo — nao alfabeticamente, entao
  # 4.0.10 e maior que 4.0.9 normalmente.
  #
  # Nao se usa Settings::GAME_VERSION aqui porque ele nao vem sendo mantido
  # (esta em 4.0.3 enquanto o pacote atual e 4.0.7).
  CLIENT_BUILD       = "4.0.7"
  @message_active    = false
  @last_battle_end_frame = 0
  @multiplayer_mode  = false
  class << self
    attr_accessor :message_active
    attr_accessor :last_battle_end_frame
    attr_accessor :multiplayer_mode
  end
  SERVER_PORT        = 7654
  DISCOVERY_PORT     = 7655
  PLAYER_SEND_TICK   = 4
  MULTIPLAYER_DOUBLE_WILD_CHANCE = 5 unless const_defined?(:MULTIPLAYER_DOUBLE_WILD_CHANCE)

  def self.trigger_auto_connect_on_map(silent = false)
    unless defined?(AnilLanRework) && AnilLanRework.respond_to?(:multiplayer_mode) && AnilLanRework.multiplayer_mode
      if $game_temp && $game_temp.respond_to?(:anil_pending_multiplayer_auto_connect)
        $game_temp.anil_pending_multiplayer_auto_connect = false
      end
      return
    end
    AnilLanRework.update_player_config
    player_id   = AnilLanRework.read_cfg("multiplayer_player.txt", "id", "jogador#{rand(9000) + 1000}")
    player_name = $player.name.to_s rescue "Treinador"
    player_char = $game_player.character_name.to_s rescue "trainer_m"
    target_ip   = (AnilLanRework.respond_to?(:dedicated_server_ip) ? AnilLanRework.dedicated_server_ip : "127.0.0.1")
    
    if silent
      AnilLanRework.add_popup(_INTL("Conectando ao servidor..."), 4.0)
    else
      pbMessage(_INTL("Conectando ao servidor principal...\\\\wt[45]\\\\^"))
    end
    # Fotografia do estado ANTES de tentar. Sem isto, uma falha aqui e apenas
    # "Falha ao tentar se conectar" — e os tres portoes que o AnilLanRework.connect
    # atravessa (save 'Partida', save verificado, modo LAN) devolvem false sem
    # deixar rasto nenhum, o que torna impossivel saber qual deles disparou.
    anil_autoconnect_log("--- tentativa de ligacao ---")
    anil_autoconnect_log("  player_id=#{player_id.inspect} nome=#{player_name.inspect} char=#{player_char.inspect}")
    anil_autoconnect_log("  ip=#{target_ip.inspect} multiplayer_mode=#{AnilLanRework.multiplayer_mode.inspect}")
    begin
      anil_autoconnect_log("  online_id=#{($PokemonGlobal.online_id rescue nil).inspect} " \
                           "machine_hash=#{($PokemonGlobal.client_machine_hash rescue nil).inspect} " \
                           "whitelist_code=#{($PokemonGlobal.whitelist_code rescue nil).inspect}")
      anil_autoconnect_log("  is_multiplayer_online_save=#{($PokemonGlobal.is_multiplayer_online_save rescue nil).inspect} " \
                           "is_verified_online_save=#{($PokemonGlobal.is_verified_online_save rescue nil).inspect}")
      anil_autoconnect_log("  save_slot=#{($player.save_slot rescue nil).inspect} " \
                           "FILE_PATH=#{(SaveData::FILE_PATH.to_s rescue nil).inspect}")
      anil_autoconnect_log("  party=#{($player.party.length rescue nil).inspect} mapa=#{($game_map.map_id rescue nil).inspect}")
    rescue => e
      anil_autoconnect_log("  (falha ao recolher diagnostico: #{e.class}: #{e.message})")
    end

    # RETENTATIVAS.
    #
    # A primeira tentativa falhava de forma reprodutivel e a segunda passava — o
    # estado de que o join precisa (multiplayer_player.txt gravado, online_id no
    # $PokemonGlobal, caches de id do AnilLanRework) so fica completo depois de
    # uma passagem pelo update_player_config. Em vez de adivinhar qual peca
    # chega atrasada, tenta-se de novo: e barato e cobre tambem o caso banal de
    # o primeiro TCP apanhar a rede num mau momento.
    #
    # Nao se retenta quando o servidor RESPONDEU a recusar (banido, versao
    # antiga, codigo invalido, manutencao): a resposta seria a mesma e o jogador
    # so esperaria mais tempo pelo mesmo erro.
    ok = false
    tentativas = 3
    1.upto(tentativas) do |n|
      begin
        ok = AnilLanRework.connect(target_ip, player_id, player_name, player_char, false)
      rescue => e
        ok = false
        AnilLanRework.log("Auto-connect map error: #{e.class}: #{e.message}")
        anil_autoconnect_log("  tentativa #{n}/#{tentativas}: EXCECAO #{e.class}: #{e.message}")
      end

      break if ok

      err = AnilLanRework.last_error_message.to_s
      anil_autoconnect_log("  tentativa #{n}/#{tentativas}: falhou — last_error=#{err.inspect}")

      if err.start_with?("BANNED:") || err =~ /desatualizada|manuten|inválido|invalido|utilizado|Debug Mode/i
        anil_autoconnect_log("  recusa explicita do servidor — nao vale a pena repetir")
        break
      end
      break if n == tentativas

      # ~0,5s entre tentativas, dando tempo ao que estiver a faltar.
      30.times { Graphics.update rescue nil }
      AnilLanRework.update_player_config rescue nil
      novo_id = AnilLanRework.read_cfg("multiplayer_player.txt", "id", player_id)
      if novo_id.to_s != player_id.to_s && !novo_id.to_s.empty?
        anil_autoconnect_log("  player_id mudou entre tentativas: #{player_id.inspect} -> #{novo_id.inspect}")
        player_id = novo_id
      end
    end
    anil_autoconnect_log("  resultado final: ok=#{ok.inspect}")

    if ok
      if silent
        AnilLanRework.add_popup(_INTL("Conectado ao servidor!"), 4.0)
      else
        pbMessage(_INTL("Conectado ao servidor principal com sucesso!\\\\wt[45]\\\\^"))
      end
      
      AnilLanRework.request_same_map_transfer!("join_vps_connect_same_map", 4)
      AnilLanRework.apply_pending_same_map_transfer!($scene)
      $game_map.need_refresh = true rescue nil
    else
      err_msg = AnilLanRework.last_error_message.to_s
      anil_autoconnect_log("LIGACAO FALHOU apos #{tentativas} tentativa(s). Motivo: #{err_msg.inspect}")
      if err_msg.start_with?("BANNED:")
        return
      elsif silent
        AnilLanRework.add_popup(_INTL("Falha na conexão: {1}", err_msg), 5.0)
      else
        pbPlayBuzzerSE() rescue nil
        AnilLanRework.show_image_overlay("servidor_offline.png", _INTL("\\r[Conexão Perdida]\\n\\nNão foi possível conectar ao servidor: {1}.\\nO jogo retornará à tela de título.", err_msg)) rescue nil
      end
      AnilLanRework.multiplayer_mode = false if defined?(AnilLanRework) && AnilLanRework.respond_to?(:multiplayer_mode=)
      AnilLanRework.disconnect(false) rescue nil
      SaveData.mark_values_as_unloaded if defined?(SaveData.mark_values_as_unloaded)
      $scene = pbCallTitle
    end
  end

  # Hue de super shiny do Pokemon que esta liderando a equipe. Devolve 0 para
  # qualquer um que NAO seja super shiny — e o zero que importa, ver abaixo.
  def self.local_follower_hue
    pkmn = (AnilLanRework::WorldSync.visible_follower_pokemon rescue nil)
    return 0 unless pkmn
    return 0 unless (pkmn.super_shiny? rescue false)
    return 0 unless pkmn.respond_to?(:super_shiny_hue)
    pkmn.super_shiny_hue.to_i
  rescue
    0
  end

  def self.refresh_local_follower!
    return unless defined?($game_temp) && $game_temp && $game_temp.respond_to?(:followers)
    fol = $game_temp.followers.get_follower_by_index(0) rescue nil
    if fol && defined?(AnilLanRework::WorldSync)
      # ⚠️ SE ELE ESTA GUARDADO, O NOME E VAZIO.
      #
      # O plugin esconde o seguidor BLANQUEANDO o charset (`remove_sprite`, no
      # 04_05), e nao com transparencia nem apagando o evento. Este metodo
      # escrevia por cima o sprite do primeiro Pokemon apto, sempre — portanto
      # qualquer coisa que o chamasse (trocar a equipa, uma troca, uma skin, o
      # regresso da agua) fazia o seguidor guardado voltar a aparecer.
      #
      # Le-se a intencao, tal como no pacote de rede.
      escondido = ($PokemonGlobal && $PokemonGlobal.follower_toggled == false) rescue false
      new_char = escondido ? "" : (AnilLanRework::WorldSync.resolve_follower_char rescue "")
      fol.character_name = new_char if fol.respond_to?(:character_name=)
      if $PokemonGlobal && $PokemonGlobal.followers && $PokemonGlobal.followers[0]
        $PokemonGlobal.followers[0].character_name = new_char
      end

      # O HUE TEM DE VIR JUNTO COM O NOME.
      #
      # Antes so o character_name era atualizado aqui. Quem pinta o super shiny
      # e o character_hue (o sprite base vem da pasta "Followers shiny/", o tom
      # e aplicado por cima), e ele ficava com o valor do Pokemon ANTERIOR.
      # Resultado: ao trocar um super shiny por um normal, o normal aparecia
      # atras do jogador com a cor do que saiu, e so voltava ao certo na
      # troca de mapa — que e quando o evento do follower e reconstruido do zero.
      #
      # O FollowingPkmn.change_sprite (patch do DBK) ja faz isto direito, mas ele
      # so roda no refresh do plugin; a troca de Pokemon nao passa por la.
      novo_hue = local_follower_hue
      fol.character_hue = novo_hue if fol.respond_to?(:character_hue=)
      if $PokemonGlobal && $PokemonGlobal.followers && $PokemonGlobal.followers[0] &&
         $PokemonGlobal.followers[0].respond_to?(:character_hue=)
        $PokemonGlobal.followers[0].character_hue = novo_hue
      end
      # Force spriteset update
      map_id = (fol.map_id rescue nil) || ($game_map.map_id rescue nil)
      if map_id
        $scene.spriteset(map_id)&.addUserAnimation(Settings::DUST_ANIMATION_ID, fol.x, fol.y, true, 1) rescue nil
      end
    end
  end

  def self.resolve_peer_follower_char(peer)
    return "" unless peer && peer.party_blob && !peer.party_blob.empty?
    pkmn_list = AnilLanRework::Serializer.deserialize_party(peer.party_blob) rescue nil
    return "" unless pkmn_list && pkmn_list.first
    pkmn = pkmn_list.first
    species = pkmn.species.to_s
    form = (pkmn.respond_to?(:form_simple) ? pkmn.form_simple : pkmn.form).to_i rescue 0
    suffix = form > 0 ? "_#{form}" : ""
    if pkmn.shiny?
      shiny_path = "Followers shiny/#{species}#{suffix}"
      return shiny_path if pbResolveBitmap("Graphics/Characters/#{shiny_path}") rescue nil
    end
    default_path = "Followers/#{species}#{suffix}"
    return default_path if pbResolveBitmap("Graphics/Characters/#{default_path}") rescue nil
    fallback_path = "Followers/#{species}"
    return fallback_path if pbResolveBitmap("Graphics/Characters/#{fallback_path}") rescue nil
    ""
  rescue
    ""
  end

  # Pasta de skins para sprites de caminhada (walk sprites)
  SKINS_FOLDER = "Graphics/Skins/" unless const_defined?(:SKINS_FOLDER)

  def self.normalize_graphic_name(name, folder = nil)
    value = name.to_s.strip
    return "" if value.empty?
    prefix = folder.to_s
    value = value.sub(/\A#{Regexp.escape(prefix)}/i, "") unless prefix.empty?
    value
  rescue
    name.to_s.strip
  end

  def self.native_trainer_type_for_character(char_name)
    target = normalize_graphic_name(char_name, "Graphics/Characters/")
    return nil if target.empty?
    unless defined?(@native_trainer_type_cache) && @native_trainer_type_cache
      @native_trainer_type_cache = {}
      GameData::TrainerType.each do |trainer_type|
        begin
          charset_name = normalize_graphic_name(
            GameData::TrainerType.charset_filename_brief(trainer_type.id),
            "Graphics/Characters/"
          )
          if !charset_name.empty?
            @native_trainer_type_cache[charset_name.downcase] ||= trainer_type.id
          end
        rescue
        end
        begin
          front_name = normalize_graphic_name(
            GameData::TrainerType.front_sprite_filename(trainer_type.id),
            "Graphics/Trainers/"
          )
          if !front_name.empty?
            @native_trainer_type_cache[front_name.downcase] ||= trainer_type.id
          end
        rescue
        end
      end
    end
    @native_trainer_type_cache[target.downcase]
  rescue
    nil
  end

  def self.player_metadata_for_character(char_name)
    target = normalize_graphic_name(char_name, "Graphics/Characters/")
    return nil if target.empty?
    GameData::PlayerMetadata.each do |meta|
      return meta if meta.walk_charset.to_s.casecmp(target).zero?
    end
    nil
  rescue
    nil
  end

  def self.trainer_type_for_character(char_name, fallback = nil)
    meta = player_metadata_for_character(char_name)
    trainer_type = meta&.trainer_type
    return trainer_type if trainer_type
    native_type = native_trainer_type_for_character(char_name)
    return native_type if native_type
    return fallback
  rescue
    fallback
  end

  def self.charset_name_for_trainer_type(trainer_type)
    # 1. Tentar diretamente o nome do ID (comum em Anil)
    str_id = trainer_type.to_s
    return str_id if File.exist?("Graphics/Characters/#{str_id}.png")
    
    # 2. Tentar o método nativo se existir
    normalize_graphic_name(GameData::TrainerType.charset_filename_brief(trainer_type), "Graphics/Characters/")
  rescue
    str_id = trainer_type.to_s
    File.exist?("Graphics/Characters/#{str_id}.png") ? str_id : ""
  end

  # Diagnostico do sprite de treinador de uma skin, uma linha por nome.
  #
  # Vai para Data/skin_sprite_log.txt, gated pelo Data/anil_debug.txt — ficheiro
  # PROPRIO, fora da lista BLOCKED do 0000_Disable_Debug_Logs, que e o padrao
  # que aquele script recomenda para nao repetir o caso do $ENABLE_DEBUG_LOGS.
  def self.log_resolucao_sprite(char_name, etapa, valor)
    return unless anil_diagnostico_ligado?
    @sprite_log_visto ||= {}
    chave = "#{char_name}|#{etapa}"
    return if @sprite_log_visto[chave]
    @sprite_log_visto[chave] = true
    File.open("Data/skin_sprite_log.txt", "a") do |f|
      f.puts("[#{Time.now.strftime('%H:%M:%S')}] #{char_name.inspect} #{etapa} => #{valor.inspect}")
    end
  rescue
  end

  def self.trainer_sprite_name_for_character(char_name, back = false)
    trainer_type = trainer_type_for_character(char_name, nil)
    log_resolucao_sprite(char_name, "trainer_type", trainer_type)
    log_resolucao_sprite(char_name, "por_metadata", (player_metadata_for_character(char_name)&.id rescue nil))
    log_resolucao_sprite(char_name, "por_native", (native_trainer_type_for_character(char_name) rescue nil))
    log_resolucao_sprite(char_name, "ficheiro_direto_existe", File.exist?("Graphics/Trainers/#{normalize_graphic_name(char_name)}.png"))
    if trainer_type
      sprite = if back
                 GameData::TrainerType.back_sprite_filename(trainer_type).to_s
               else
                 GameData::TrainerType.front_sprite_filename(trainer_type).to_s
               end
      sprite = normalize_graphic_name(sprite, "Graphics/Trainers/")
      log_resolucao_sprite(char_name, "RESULTADO_por_trainer_type", sprite)
      return sprite unless sprite.empty?
    end

    # Se falhou, tentar achar direto o nome na pasta Trainers
    direct = normalize_graphic_name(char_name)
    if back
      direct_back = direct + "_back"
      return direct_back if !direct.empty? && File.exist?("Graphics/Trainers/#{direct_back}.png")
    else
      return direct if !direct.empty? && File.exist?("Graphics/Trainers/#{direct}.png")
    end
    ""
  rescue
    # Fallback final se der erro: tenta usar o trainer_type.to_s
    if trainer_type
      str_id = trainer_type.to_s
      target = back ? "#{str_id}_back" : str_id
      return target if File.exist?("Graphics/Trainers/#{target}.png")
    end
    ""
  end

  # Cache para a lista de personagens
  @cached_chars = nil

  def self.clear_char_cache
    @cached_chars = nil
  end

  # Carrega dinamicamente as skins da pasta
  def self.available_characters
    return @cached_chars if @cached_chars
    chars = []
    seen = {}
    # 1. Metadados de Jogador (Personagens padrão e nativos)
    GameData::PlayerMetadata.each do |meta|
      char_name = meta.walk_charset.to_s.strip
      next if char_name.empty?
      key = char_name.downcase
      next if seen[key]
      trainer_type = meta.trainer_type
      label = ""
      begin
        label = GameData::TrainerType.get(trainer_type).real_name.to_s
      rescue
        label = ""
      end
      label = char_name if label.empty?
      label = label.gsub('POKEMONTRAINER_', '').gsub('_', ' ')
      chars << {
        "label"          => label,
        "char_name"      => char_name,
        "trainer_sprite" => trainer_sprite_name_for_character(char_name),
        "player_meta_id" => meta.id
      }
      seen[key] = true
    end
    # 2. Tipos de Treinador (Fallback para outros charsets)
    GameData::TrainerType.each do |trainer_type|
      char_name = charset_name_for_trainer_type(trainer_type.id)
      next if char_name.empty?
      key = char_name.downcase
      next if seen[key]
      label = trainer_type.real_name.to_s
      label = trainer_type.id.to_s if label.empty?
      chars << {
        "label"          => label,
        "char_name"      => char_name,
        "trainer_sprite" => trainer_sprite_name_for_character(char_name),
        "player_meta_id" => nil,
        "trainer_type"   => trainer_type.id
      }
      seen[key] = true
    end
    # 3. Pasta de Skins customizadas
    if File.directory?(SKINS_FOLDER)
      Dir.entries(SKINS_FOLDER).each do |f|
        next unless f.downcase.end_with?('.png')
        skin_name = File.basename(f, '.*')
        key = skin_name.downcase
        next if seen[key]
        display_name = skin_name.gsub('POKEMONTRAINER_', '').gsub('_', ' ')
        chars << {
          "label"          => display_name,
          "char_name"      => skin_name,
          "trainer_sprite" => trainer_sprite_name_for_character(skin_name),
          "player_meta_id" => nil,
          "trainer_type"   => trainer_type_for_character(skin_name, nil)
        }
        seen[key] = true
      end
    end
    if chars.empty?
      chars = [{
        "label"          => "Treinador Padrao",
        "char_name"      => "POKEMONTRAINER_RojoNeutro",
        "trainer_sprite" => trainer_sprite_name_for_character("POKEMONTRAINER_RojoNeutro"),
        "player_meta_id" => nil,
        "trainer_type"   => trainer_type_for_character("POKEMONTRAINER_RojoNeutro", nil)
      }]
    end
    @cached_chars = chars.sort_by { |c| c["label"].to_s }
  end
  SNAPSHOT_SEND_TICK = 40
  EVENT_STREAM_TICK  = 6
  PARTY_SEND_TICK    = 600
  KEEPALIVE_TICK     = 120
  PACKET_TRACE       = false
  # Sem limite de espera pelo join_ack, de proposito: quem espera e o loop de
  # reconexao, que ja tem os proprios cortes. O que realmente limita cada
  # tentativa e o connect_timeout do TCP (Connection#connect): 20s em VPN, 8s
  # normal, 4s no boot. Mexer aqui NAO muda esses tres — eles sao clampados.
  JOIN_TIMEOUT       = 99999.0
  BATTLE_INVITE_TIMEOUT = 20.0
  TURN_TIMEOUT       = 30.0
  COOP_COMMAND_TIMEOUT = 60.0
  # Espera por um slot remoto TRAVADO (golpe de duas fases, recarga, Outrage...).
  # Nesse caso o parceiro auto-escolhe na hora — nao ha humano no menu —, entao
  # se o pacote nao chegou em poucos segundos ele nao vem mesmo, e insistir so
  # congela a batalha (era o freeze de ~30-60s depois do Meteor Beam).
  COOP_LOCKED_SLOT_TIMEOUT = 4.0
  DISCOVERY_TIMEOUT  = 5.5
  DISCOVERY_MAGIC    = "ANIL_LAN_REWORK_DISCOVERY_V1"
  FOLLOW_HOST_CAMERA = false
  LAN_BRIEF_MESSAGE_PAUSE  = 1
  LAN_MESSAGE_PAUSE        = 1
  LAN_PAUSED_MESSAGE_PAUSE = 1
  LAN_BATTLE_TEXT_LEAD_LIMIT = 1
  LAN_BATTLE_TEXT_SYNC_TIMEOUT = 5.0
  REMOTE_SPAWN_AUTHORITY_DISTANCE = 12
  REMOTE_SUBPIXELS_X = (Game_Map::REAL_RES_X rescue 128)
  REMOTE_SUBPIXELS_Y = (Game_Map::REAL_RES_Y rescue 128)
  REMOTE_INTERP_SPEED_X = (REMOTE_SUBPIXELS_X * 10 / 32).clamp(12, REMOTE_SUBPIXELS_X)
  REMOTE_INTERP_SPEED_Y = (REMOTE_SUBPIXELS_Y * 10 / 32).clamp(12, REMOTE_SUBPIXELS_Y)
  REMOTE_TELEPORT_THRESHOLD_TILES = 6
  REMOTE_BUSY_BALLOON_COOLDOWN = 1.5
  # Configurações do balão de ocupado (indicador visual quando outro jogador está ocupado)
  REMOTE_BUSY_BALLOON_BLINK_ENABLED = true    # true = balão pisca, false = balão sempre visível
  REMOTE_BUSY_BALLOON_BLINK_INTERVAL = 0.5    # Intervalo de piscar em segundos (0.5 = pisca a cada meio segundo)
  REMOTE_CATCH_BALLOON_ENABLED = false       # true = Poké Bola ao batalhar/capturar, false = apenas busy balloon normal
  REMOTE_STATUS_TONES = {
    :SLEEP    => Tone.new(-40, -40, 70, 10),
    :POISON   => Tone.new(70, -20, 70, 0),
    :BURN     => Tone.new(90, -35, -35, 0),
    :PARALYSIS => Tone.new(85, 85, -40, 0),
    :FROZEN   => Tone.new(-30, 40, 100, 0)
  }.freeze unless const_defined?(:REMOTE_STATUS_TONES)

  module BusyBalloon
    # Sistema de balão de ocupado para indicar quando outros jogadores estão ocupados
    # O balão aparece acima do personagem e pode piscar (configurável via REMOTE_BUSY_BALLOON_BLINK_ENABLED)
    # Não reproduz som - apenas indicador visual
    BALLOON_W = 18
    BALLOON_H = 12
    TAIL_H    = 4

    module_function

    def create_bitmap
      # Carregar diretamente usando Bitmap.new para evitar problemas com o Cache do Essentials
      anim_bmp = nil
      begin
        anim_bmp = Bitmap.new("Graphics/Animations/Overworld exclaim.png")
      rescue
        begin
          anim_bmp = Bitmap.new("Graphics/Animations/emo.png")
        rescue
          anim_bmp = nil
        end
      end
      
      if anim_bmp && anim_bmp.width >= 192 && anim_bmp.height >= 192
        # O spritesheet de animação tem blocos de 192x192. Pegamos apenas o primeiro frame.
        bmp = Bitmap.new(192, 192)
        bmp.blt(0, 0, anim_bmp, Rect.new(0, 0, 192, 192))
        return bmp
      end

      # Fallback transparente caso não encontre a imagem
      bmp = Bitmap.new(1, 1)
      bmp
    rescue => e
      AnilLanRework.log("busy balloon bitmap error #{e.class}: #{e.message}") rescue nil
      Bitmap.new(1, 1)
    end
  end

  @connection       = nil
  @players          = {}
  @known_peers      = {}
  @self_internal_id = nil
  @self_display_id  = nil
  @self_name        = nil
  @is_host          = false
  @enabled          = false
  @last_error_message = nil
  @map_refresh_requested = 0
  @delayed_map_refresh_at = nil
  @delayed_map_refresh_reason = nil
  @delayed_map_refresh_passes = 0
  @pre_coop_location = nil
  @peer_interaction_cooldown_until = 0
  @pending_return_location = nil
  @pending_same_map_transfer = nil

  @reconnecting = false
  @reconnect_start_time = nil
  @reconnect_thread = nil
  @reconnect_sprite = nil
  @reconnect_viewport = nil
  @last_reconnect_fail_time = 0.0

  @last_connect_ip = nil
  @last_connect_player_id = nil
  @last_connect_player_name = nil
  @last_connect_char_name = nil
  @last_connect_is_host = nil
  @last_connect_alt_ips = nil

  class << self
    attr_accessor :connection
    attr_accessor :players
    attr_accessor :known_peers
    attr_accessor :self_internal_id
    attr_accessor :self_display_id
    attr_accessor :self_name
    attr_accessor :is_host
    attr_accessor :enabled
    attr_accessor :last_error_message
    attr_accessor :map_refresh_requested
    attr_accessor :delayed_map_refresh_at
    attr_accessor :delayed_map_refresh_reason
    attr_accessor :delayed_map_refresh_passes
    attr_accessor :pre_coop_location
    attr_accessor :peer_interaction_cooldown_until
    attr_accessor :pending_return_location
    attr_accessor :pending_same_map_transfer

    attr_accessor :reconnecting
    attr_accessor :reconnect_start_time
    attr_accessor :reconnect_thread
    attr_accessor :reconnect_sprite
    attr_accessor :reconnect_viewport
    attr_accessor :last_reconnect_fail_time
    attr_accessor :last_connect_ip
    attr_accessor :last_connect_player_id
    attr_accessor :last_connect_player_name
    attr_accessor :last_connect_char_name
    attr_accessor :last_connect_is_host
    attr_accessor :last_connect_alt_ips
  end

  module_function

  def safe_ui_text(value)
    str = value.to_s.dup
    begin
      return str.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "?")
    rescue
    end
    begin
      win1252 = Encoding.find("Windows-1252")
      return str.dup.force_encoding(win1252).encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "?")
    rescue
    end
    str.force_encoding(Encoding::UTF_8) rescue nil
    return str
  end

  # ⚠️ UM APELIDO NAO DIZ O QUE SE ESTA A RECEBER.
  #
  # Nas trocas so aparecia `pkmn.name`, que e o apelido quando o Pokemon tem
  # um: "Enviar Azulao por Rex?" nao diz nem a especie nem o nivel de nenhum dos
  # dois. Quem aceita esta a decidir as cegas, e um apelido bem escolhido
  # ("Mewtwo") chega para enganar alguem distraido.
  #
  # Devolve:
  #   com apelido -> "Azulao (Pikachu Nv.50)"
  #   sem apelido -> "Pikachu Nv.50"
  #
  # O `speciesName` e o nome da ESPECIE na lingua do jogo; o `name` e o apelido
  # ou, quando nao ha, o proprio nome da especie — por isso a comparacao entre os
  # dois e o que decide se ha apelido, e nao um campo `nickname` (que o
  # Essentials nao expoe aqui).
  def nome_e_especie(pkmn)
    return "" unless pkmn
    especie = (pkmn.speciesName.to_s rescue "")
    apelido = (pkmn.name.to_s rescue "")
    nivel   = (pkmn.level.to_i rescue 0)
    corpo   = especie.empty? ? apelido : especie
    corpo   = "#{corpo} Nv.#{nivel}" if nivel > 0
    return corpo if apelido.empty? || especie.empty? || apelido == especie
    "#{apelido} (#{corpo})"
  rescue
    (pkmn.name.to_s rescue "")
  end

  def ui_format(template, *args)
    text = safe_ui_text(template)
    args.each_with_index do |value, idx|
      text = text.gsub("{#{idx + 1}}", safe_ui_text(value))
    end
    return text
  rescue
    return template.to_s
  end

  def mark_skip_battle_evolution_once(mode = nil)
    return unless defined?($game_temp) && $game_temp
    $game_temp.instance_variable_set(:@anil_skip_battle_evolution_once, true)
    $game_temp.instance_variable_set(:@anil_skip_battle_evolution_mode, mode.to_sym) if mode
  rescue
  end

  def skip_battle_evolution_once?
    return false unless defined?($game_temp) && $game_temp
    !!$game_temp.instance_variable_get(:@anil_skip_battle_evolution_once)
  rescue
    false
  end

  def skip_battle_evolution_mode
    return nil unless defined?($game_temp) && $game_temp
    mode = $game_temp.instance_variable_get(:@anil_skip_battle_evolution_mode)
    mode ? mode.to_sym : nil
  rescue
    nil
  end

  def clear_skip_battle_evolution_once
    return unless defined?($game_temp) && $game_temp
    $game_temp.instance_variable_set(:@anil_skip_battle_evolution_once, false)
    $game_temp.instance_variable_set(:@anil_skip_battle_evolution_mode, nil)
  rescue
  end

  def append_log_line(file_name, text)
    stamp = Time.now.strftime("%Y-%m-%d %H:%M:%S.%L") rescue Time.now.to_s
    frame = Graphics.frame_count rescue -1
    File.open(file_name, "a:UTF-8") do |f|
      f.puts("[#{stamp}] [frame=#{frame}] #{text}")
    end
  rescue
  end

  def battle_log_enabled?
    $anil_battle_verbose_log_enabled != false
  end

  def log(text)
    return unless $anil_debug_log_enabled
    append_log_line("multiplayer_debug.txt", text)
    append_log_line(BATTLE_VERBOSE_LOG_FILE, "legacy_log #{text}") if battle_log_enabled?
  rescue
  end

  def verbose_log(text)
    return unless battle_log_enabled?
    append_log_line(BATTLE_VERBOSE_LOG_FILE, text)
  rescue
  end

  def log_value(value)
    case value
    when nil
      "nil"
    when TrueClass, FalseClass, Numeric, Symbol
      value.to_s
    when String
      value.gsub(/\s+/, " ").strip
    when Array
      "[" + value.map { |item| log_value(item) }.join(",") + "]"
    when Hash
      "{" + value.map { |k, v| "#{k}:#{log_value(v)}" }.join(",") + "}"
    else
      value.to_s
    end
  rescue
    value.inspect rescue "?"
  end

  def battle_log(event, fields = nil, battle = nil, ctx = nil)
    return unless battle_log_enabled?
    ctx ||= AnilLanRework::BattleSync.active_context rescue nil
    battle ||= (ctx.battle rescue nil)
    payload = {
      "event"     => event.to_s,
      "mode"      => (ctx.mode.to_s rescue nil),
      "battle_id" => (ctx.battle_id.to_s rescue nil),
      "turn"      => (battle.turnCount.to_i rescue nil),
      "decision"  => (battle.decision.to_i rescue nil)
    }
    payload.merge!(fields) if fields.is_a?(Hash)
    line = payload.map { |k, v| next if v.nil? || v == ""; "#{k}=#{log_value(v)}" }.compact.join(" ")
    verbose_log(line)
  rescue
  end

  def battler_log_fields(battler, prefix = "battler")
    return { "#{prefix}" => "nil" } unless battler
    {
      "#{prefix}_index"   => (battler.index.to_i rescue nil),
      "#{prefix}_name"    => ((battler.pokemon&.name || battler.name) rescue nil),
      "#{prefix}_species" => (battler.pokemon&.species rescue nil),
      "#{prefix}_level"   => (battler.pokemon&.level rescue nil),
      "#{prefix}_hp"      => (battler.hp.to_i rescue nil),
      "#{prefix}_totalhp" => (battler.totalhp.to_i rescue nil),
      "#{prefix}_status"  => (battler.status.to_s rescue nil),
      "#{prefix}_ability" => (battler.ability.to_s rescue nil),
      "#{prefix}_item"    => (battler.item.to_s rescue nil),
      "#{prefix}_owner"   => (battler.pbOwnedByPlayer? rescue nil)
    }
  rescue
    { "#{prefix}" => "error" }
  end

  def pokemon_log_fields(pkmn, prefix = "pokemon", index = nil)
    return { "#{prefix}" => "nil" } unless pkmn
    {
      "#{prefix}_index"   => index,
      "#{prefix}_name"    => (pkmn.name rescue nil),
      "#{prefix}_species" => (pkmn.species rescue nil),
      "#{prefix}_level"   => (pkmn.level rescue nil),
      "#{prefix}_exp"     => (pkmn.exp.to_i rescue nil),
      "#{prefix}_hp"      => (pkmn.hp.to_i rescue nil),
      "#{prefix}_totalhp" => (pkmn.totalhp.to_i rescue nil),
      "#{prefix}_status"  => (pkmn.status.to_s rescue nil),
      "#{prefix}_ability" => (pkmn.ability.to_s rescue nil),
      "#{prefix}_item"    => (pkmn.item_id.to_s rescue pkmn.item.to_s rescue nil)
    }
  rescue
    { "#{prefix}" => "error" }
  end

  def packet_trace?
    PACKET_TRACE == true
  end

  def packet_log_summary(packet)
    return packet.inspect unless packet.is_a?(Hash)
    filtered = packet.reject { |k, _| k == "events" }
    if packet["events"].is_a?(Hash)
      filtered = filtered.merge("events_count" => packet["events"].length)
    end
    filtered.inspect
  end

  def trace_packet(prefix, packet)
    verbose_log("packet prefix=#{prefix} payload=#{packet_log_summary(packet)}") if battle_log_enabled?
    return unless packet_trace?
    log("#{prefix} #{packet_log_summary(packet)}")
  rescue
  end

  def sanitize_id(text, fallback = "jogador")
    cleaned = text.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
    cleaned = fallback if cleaned.empty?
    cleaned[0, 100]
  end

  def machine_token
    raw = begin
      Socket.gethostname
    rescue
      ENV["COMPUTERNAME"] || ENV["HOSTNAME"] || "pc"
    end
    sanitize_id(raw, "pc")
  end

  def resolve_internal_id(config_id)
    sanitize_id(config_id)
  end

  def private_ipv4?(ip)
    octets = ip.to_s.split(".").map { |v| v.to_i }
    return false unless octets.length == 4 && octets.all? { |v| v.between?(0, 255) }
    return false if octets[0] == 0 || octets[0] == 127
    return true if octets[0] == 10
    return true if octets[0] == 192 && octets[1] == 168
    return true if octets[0] == 172 && octets[1].between?(16, 31)
    return true if octets[0] == 169 && octets[1] == 254
    return true if octets[0] == 25 || octets[0] == 26 # Hamachi e Radmin VPN
    false
  end

  def local_ipv4_candidates
    candidates = []
    begin
      Socket.ip_address_list.each do |addr|
        next unless addr.ipv4?
        ip = addr.ip_address.to_s
        next unless private_ipv4?(ip)
        candidates << ip
      end
    rescue
      # Fallback para JoiPlay/Android onde ip_address_list pode falhar
      begin
        udp = UDPSocket.new
        udp.connect("8.8.8.8", 1)
        local_ip = udp.addr.last
        candidates << local_ip if private_ipv4?(local_ip)
        udp.close
      rescue
      end
    end
    candidates.uniq!

    candidates.sort_by do |ip|
      type = detect_network_type(ip)
      case type
      when /ZeroTier/i then 0
      when "Radmin", "Hamachi" then 1
      when "Wi-Fi/LAN" then 2
      else 3
      end
    end
  rescue
    []
  end

  def zerotier_ipv4_candidates
    candidates = local_ipv4_candidates
    candidates.select do |ip|
      type = detect_network_type(ip)
      type.include?("ZeroTier")
    end
  end

  def diagnose_connection_issues
    log("=== DIAGNOSTICO DE CONEXAO ===")
    
    # Verificar interfaces de rede
    ips = local_ipv4_candidates
    log("Interfaces de rede disponiveis: #{ips.inspect}")
    
    # Verificar ZeroTier especificamente
    zerotier_ips = zerotier_ipv4_candidates
    log("Interfaces ZeroTier detectadas: #{zerotier_ips.inspect}")
    
    # Verificar se está conectado
    log("Estado de conexao: #{connected? ? 'CONECTADO' : 'DESCONECTADO'}")
    
    # Verificar se é host
    log("Modo host: #{host? ? 'SIM' : 'NAO'}")
    
    # Verificar portas
    log("Porta servidor: #{SERVER_PORT}")
    log("Porta descoberta: #{DISCOVERY_PORT}")
    
    # Verificar se o listener de descoberta está ativo
    if @discovery_thread&.alive?
      log("Listener de descoberta: ATIVO")
    else
      log("Listener de descoberta: INATIVO")
    end
    
    log("=== FIM DIAGNOSTICO ===")
  end

  def local_ip_summary
    ips = local_ipv4_candidates
    return "127.0.0.1" if ips.empty?
    ips.map { |ip| "#{ip} [#{detect_network_type(ip)}]" }.join(", ")
  end

  def discovery_broadcast_targets
    targets = ["127.0.0.1", "255.255.255.255"]
    local_ipv4_candidates.each do |ip|
      parts = ip.split(".")
      next unless parts.length == 4

      # Broadcast padrão /24 (Wi-Fi de casa)
      targets << "#{parts[0]}.#{parts[1]}.#{parts[2]}.255"

      # Broadcast /16 (Usado pelo ZeroTier, Hamachi, Radmin)
      targets << "#{parts[0]}.#{parts[1]}.255.255"

      # Broadcast /8 (Garante que acha em redes virtuais maiores)
      targets << "#{parts[0]}.255.255.255"
    end
    targets.uniq
  end

  def discover_hosts(timeout = DISCOVERY_TIMEOUT)
    socket = UDPSocket.new
    socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_BROADCAST, true) rescue nil
    socket.bind("0.0.0.0", 0)

    packet = { "type" => "discover_host", "magic" => DISCOVERY_MAGIC, "display_id" => @self_display_id.to_s }
    payload = AnilLanPureJSON.encode(packet)

    discovery_broadcast_targets.each do |target|
      socket.send(payload, 0, target, DISCOVERY_PORT) rescue nil
    end

    hosts = {}
    deadline = Time.now.to_f + timeout.to_f
    while (remaining = deadline - Time.now.to_f) > 0
      ready = IO.select([socket], nil, nil, remaining)
      break unless ready
      begin
        data, addr = socket.recvfrom(4096)
      rescue SystemCallError
        next
      rescue
        next
      end
      msg = AnilLanPureJSON.decode(data.to_s)
      next unless msg.is_a?(Hash) && msg["type"] == "discover_ack" && msg["magic"] == DISCOVERY_MAGIC
      
      # Prefer the actual UDP source IP (addr[3]) — this is the IP that 
      # ACTUALLY delivered the packet to us, so TCP should work on it too.
      # The payload "ip" might be the host's LAN IP which is unreachable 
      # from VPN networks like ZeroTier.
      udp_source_ip = addr[3].to_s
      announced_ip  = msg["ip"].to_s
      
      ip = udp_source_ip.empty? ? announced_ip : udp_source_ip
      
      # Store both so we can try the alternative if TCP fails
      alt_ips = [announced_ip, udp_source_ip].map(&:to_s).reject(&:empty?).uniq - [ip]
      all_ips = Array(msg["all_ips"])
      alt_ips = (alt_ips + all_ips).uniq - [ip] unless all_ips.empty?
      
      log("discover_host found ip=#{ip} udp_src=#{udp_source_ip} announced=#{announced_ip} alt=#{alt_ips.inspect}") rescue nil
      
      hosts[ip] = {
        "ip"            => ip,
        "alt_ips"       => alt_ips,
        "host_id"       => msg["host_id"].to_s,
        "host_name"     => msg["host_name"].to_s
      }
    end
    hosts.values
  ensure
    socket.close rescue nil if socket
  end

  def pick_discovered_host(hosts, preferred_ip = nil)
    return nil if hosts.nil? || hosts.empty?
    preferred = preferred_ip.to_s.strip
    if !preferred.empty?
      match = hosts.find { |entry| entry["ip"].to_s == preferred }
      return match if match
    end
    hosts.first
  end

  def detect_network_type(ip)
    # IP do servidor dedicado = label especial
    dedicated_ip = (dedicated_server_ip rescue "127.0.0.1")
    return "Servidor Pokemon Azul" if ip.to_s.strip == dedicated_ip.to_s.strip
    
    octets = ip.to_s.split(".").map { |v| v.to_i }
    return "LAN" if octets.empty?
    return "ZeroTier" if octets[0] == 172 && (octets[1] >= 20 && octets[1] <= 31)
    return "Radmin" if octets[0] == 26
    return "Hamachi" if octets[0] == 25
    return "ZeroTier" if octets[0] == 10
    return "Wi-Fi/LAN" if octets[0] == 192 && octets[1] == 168
    return "VPN/LAN"
  end

  def discovered_host_label(entry)
    return "" unless entry.is_a?(Hash)
    name = entry["host_name"].to_s.strip
    ip   = entry["ip"].to_s.strip
    net_type = detect_network_type(ip)
    # Nunca exibir o IP real quando for o servidor dedicado (seguranca)
    if net_type == "Servidor Pokemon Azul"
      return name.empty? ? net_type : "#{name} [#{net_type}]"
    end
    return "#{name} [#{net_type}]" if ip.empty?
    return "#{ip} [#{net_type}]" if name.empty?
    ui_format("{1} ({2}) [{3}]", name, ip, net_type)
  end

  def connected?
    !!(@connection && @connection.connected?)
  end

  def enabled?
    @enabled == true
  end

  def host?
    @is_host == true
  end

  def reset_runtime_state
    @players = {}
    @known_peers = {}
  end

  def activate_runtime!(player_id:, player_name:, is_host:)
    clear_all_remote_events_from_map rescue nil
    $vower_pending_actions.clear if defined?($vower_pending_actions) && $vower_pending_actions.is_a?(Array)
    AnilLanRework.intentional_disconnect = false rescue nil
    @self_display_id = player_id.to_s
    @self_internal_id = resolve_internal_id(player_id)
    @self_name = player_name.to_s
    @is_host = is_host ? true : false
    @enabled = true
    AnilLanRework.set_online_level_cap_state(true)
    @last_error_message = nil
    @players = {}
    @known_peers = {}
  end

  def clear_all_remote_events_from_map
    return unless $game_map && $game_map.events
    ids_to_remove = []
    $game_map.events.each do |id, event|
      next unless event
      is_remote = false
      is_remote ||= (event.instance_variable_get(:@anil_remote_poke_event) == true rescue false)
      is_remote ||= (event.instance_variable_get(:@vower_spawn_id) != nil rescue false)
      is_remote ||= (event.name.to_s.start_with?("anil_remote_") rescue false)
      is_remote ||= (event.name.to_s.start_with?("ReleasedPoke_") rescue false)
      
      if is_remote
        ids_to_remove << id
      end
    end
    return if ids_to_remove.empty?
    # Remove eventos remotos diretamente SEM pbFadeOutIn.
    # O pbFadeOutIn causava tela preta no Joiplay quando chamado
    # fora da Scene_Map (ex: tela de load/titulo).
    ids_to_remove.each do |id|
      if $game_map.respond_to?(:removeThisEventfromMap)
        $game_map.removeThisEventfromMap(id) rescue nil
      else
        $game_map.events.delete(id) rescue nil
      end
    end
    # Refresh de spritesets apenas se estiver no mapa
    if $scene.is_a?(Scene_Map)
      $scene.disposeSpritesets rescue nil
      $scene.createSpritesets rescue nil
    end
  end

  def deactivate_runtime!
    was_client = (@enabled == true && @is_host == false)
    @enabled = false
    @is_host = false
    AnilLanRework.set_online_level_cap_state(false)
    clear_delayed_map_refresh!
    @pending_same_map_transfer = nil
    reset_runtime_state
    clear_all_remote_events_from_map rescue nil
    WorldSync.authoritative_map_id = nil if defined?(WorldSync)
    WorldSync.host_reported_map_id = nil if defined?(WorldSync)
    WorldSync.host_reported_map_frame = -1 if defined?(WorldSync)
    WorldSync.pending_snapshot = nil if defined?(WorldSync)
    if defined?(BattleSync)
      if (BattleSync.instance_variable_get(:@partner_injected) rescue false)
        BattleSync.remove_partner rescue nil
        if defined?($PokemonGlobal) && $PokemonGlobal.respond_to?(:partner=)
          $PokemonGlobal.partner = nil
        end
      end
      BattleSync.clear_context
    end
    if was_client && @pre_coop_location
      loc = @pre_coop_location
      @pre_coop_location = nil
      log("RESTORING pre-coop location: #{loc.inspect}")
      @pending_return_location = loc
      apply_pending_return_location!
    else
      @pending_return_location = nil
    end
  end

  def apply_pending_return_location!(scene = nil)
    loc = @pending_return_location
    return false unless loc.is_a?(Hash)
    scene ||= $scene
    return false unless scene.is_a?(Scene_Map)
    return false unless $game_temp && $game_map && $game_player
    return false if $game_temp.in_battle
    return false if $game_temp.message_window_showing
    return false if (pbMapInterpreterRunning? rescue false)
    begin
      $game_temp.player_new_map_id      = loc[:map_id]
      $game_temp.player_new_x           = loc[:x]
      $game_temp.player_new_y           = loc[:y]
      $game_temp.player_new_direction   = loc[:dir]
      $game_temp.player_transferring    = true
      $game_temp.transition_processing  = true
      pbDismountBike rescue nil
      scene.transfer_player
      request_map_graphics_refresh!("disconnect_restore", 1)
      @pending_return_location = nil
      true
    rescue => e
      log("apply_pending_return_location error #{e.class}: #{e.message}")
      false
    end
  end

  def request_same_map_transfer!(reason = nil, passes = 4)
    return false unless $game_map && $game_player
    @pending_same_map_transfer = {
      :map_id  => $game_map.map_id,
      :x       => $game_player.x,
      :y       => $game_player.y,
      :dir     => $game_player.direction,
      :reason  => reason.to_s,
      :passes  => [passes.to_i, 1].max
    }
    log("same_map_transfer requested reason=#{reason}") if reason
    true
  rescue => e
    log("request_same_map_transfer error #{e.class}: #{e.message}")
    false
  end

  def apply_pending_same_map_transfer!(scene = nil)
    loc = @pending_same_map_transfer
    return false unless loc.is_a?(Hash)
    scene ||= $scene
    return false unless scene.is_a?(Scene_Map)
    return false unless $game_temp && $game_map && $game_player
    return false if $game_temp.in_battle
    return false if $game_temp.message_window_showing
    return false if (pbMapInterpreterRunning? rescue false)
    begin
      log("Executing same_map_transfer: Double refresh only to reload spritesets without map reloading or player teleportation")
      $game_temp.transition_processing = false rescue nil
      $game_temp.player_transferring   = false rescue nil
      
      # Executa o duplo refresh sob a tela diretamente
      scene.disposeSpritesets rescue nil
      scene.createSpritesets rescue nil
      
      # Executa updates de rede e rendering sob a tela para garantir sincronização inicial
      5.times do
        AnilLanRework::Router.tick rescue nil if AnilLanRework.enabled? && AnilLanRework.connected?
        if scene.respond_to?(:updateSpritesets)
          scene.updateSpritesets(true) rescue nil
        elsif scene.instance_variable_get(:@spritesetGlobal)
          scene.instance_variable_get(:@spritesetGlobal).update rescue nil
        end
        $game_map.update rescue nil
        $game_player.update rescue nil
        Graphics.update rescue nil
        Input.update rescue nil
      end
      
      # Refresh final limpo das spritesets
      scene.disposeSpritesets rescue nil
      scene.createSpritesets rescue nil
      if scene.respond_to?(:updateSpritesets)
        scene.updateSpritesets(true) rescue nil
      end
      
      # Recentraliza a câmera, corrige posição impossível e destrava transição
      $game_player.center($game_player.x, $game_player.y) rescue nil
      AnilCoordFix.fix_player_position rescue nil if defined?(AnilCoordFix)
      Graphics.transition(0) rescue nil
      
      AnilLanRework.clear_map_graphics_refresh!
      AnilLanRework.clear_delayed_map_refresh!
      @pending_same_map_transfer = nil
      $game_map.need_refresh = true rescue nil
      true
    rescue => e
      log("apply_pending_same_map_transfer error #{e.class}: #{e.message}")
      false
    end
  end

  def connect(ip, player_id, player_name, char_name, is_host = false, alt_ips = nil, startup: false)
    # Se for conexão LAN local (não VPS), desativa o auto-connect pendente
    dedicated_ip = (AnilLanRework.respond_to?(:dedicated_server_ip) ? AnilLanRework.dedicated_server_ip : "127.0.0.1")
    if ip.to_s.strip != dedicated_ip
      if $game_temp && $game_temp.respond_to?(:anil_pending_multiplayer_auto_connect)
        $game_temp.anil_pending_multiplayer_auto_connect = false
      end
    elsif !AnilLanRework.multiplayer_mode
      @last_error_message = "IP do servidor bloqueado no modo LAN"
      log("Erro: Tentativa de conexao ao servidor VPS no modo LAN bloqueada.")
      return false
    end

    if ip.to_s.strip == dedicated_ip
      slot_name = ($player ? $player.save_slot.to_s : "")
      save_path = (SaveData::FILE_PATH.to_s rescue "")
      if slot_name.downcase.include?("partida") || File.basename(save_path).downcase.include?("partida")
        @last_error_message = "Saves do tipo 'Partida' não são autorizados no modo Online!"
        log("Erro: Tentativa de conexao ao servidor usando save local/offline ('#{slot_name}') bloqueada.")
        return false
      end

      if $PokemonGlobal
        is_verified = ($PokemonGlobal.respond_to?(:is_verified_online_save) && $PokemonGlobal.is_verified_online_save == true)
        unless is_verified
          @last_error_message = "Save inválido: Não é um save verificado do modo multiplayer online!"
          log("Erro: Tentativa de conexao ao servidor com save sem tag de verificação online.")
          return false
        end
      end
    end

    activate_runtime!(player_id: player_id, player_name: player_name, is_host: is_host)
    @connection = AnilLanRework::Connection.new
    is_vpn_target = detect_network_type(ip.to_s) =~ /ZeroTier|Radmin|Hamachi|VPN/i
    # ⚠️ android?, nao joiplay?: o timeout maior e por estar num TELEMOVEL —
    # rede movel, CPU mais lenta — e nao por ser o JoiPlay. Um APK nativo num
    # aparelho fraco precisa do mesmo folego. As outras tres chamadas de
    # joiplay? neste ficheiro ficam como estao, porque sao mesmo contornos do
    # JoiPlay (o refresh de graficos, o salto do updateMaps, o icone embutido) e
    # um build nativo deve ter o comportamento normal.
    is_joiplay = AnilLanRework.android?
    timeout_window = if is_joiplay
                      [JOIN_TIMEOUT.to_f + 25.0, 50.0].max
                      # Timeout aumentado para JoiPlay 1.21
                     elsif startup
                      8.0
                     elsif is_vpn_target
                      [JOIN_TIMEOUT.to_f + 20.0, 45.0].max
                     else
                      [JOIN_TIMEOUT.to_f + 10.0, 30.0].max
                     end
    ok = false
    worker_error = nil
    worker = Thread.new do
      begin
        ok = @connection.connect(ip,
          internal_id: @self_internal_id,
          display_id: @self_display_id,
          player_name: @self_name,
          char_name: char_name,
          is_host: @is_host,
          startup: startup
        )
      rescue => e
        worker_error = e
      end
    end
    finished = worker.join(timeout_window)
    unless finished
      @last_error_message = "connection timeout"
      @connection.disconnect rescue nil
      worker.kill rescue nil
      disconnect
      
      # Try alternative IPs if the primary one failed
      fallback_ips = Array(alt_ips).reject { |aip| aip.to_s == ip.to_s }
      if !fallback_ips.empty?
        fallback_ips.each do |fallback_ip|
          log("connection fallback trying alt ip=#{fallback_ip} (primary=#{ip} failed)")
          result = connect(fallback_ip, player_id, player_name, char_name, is_host, nil)
          return result if result
        end
      end
      
      return false
    end
    if worker_error
      # Try alternative IPs before raising
      fallback_ips = Array(alt_ips).reject { |aip| aip.to_s == ip.to_s }
      if !fallback_ips.empty?
        fallback_ips.each do |fallback_ip|
          log("connection error fallback trying alt ip=#{fallback_ip} (primary=#{ip} error=#{worker_error.message})")
          result = connect(fallback_ip, player_id, player_name, char_name, is_host, nil)
          return result if result
        end
      end
      raise worker_error
    end
    unless ok
      # Try alternative IPs before giving up
      fallback_ips = Array(alt_ips).reject { |aip| aip.to_s == ip.to_s }
      if !fallback_ips.empty?
        fallback_ips.each do |fallback_ip|
          log("connection refused fallback trying alt ip=#{fallback_ip} (primary=#{ip})")
          result = connect(fallback_ip, player_id, player_name, char_name, is_host, nil)
          return result if result
        end
      end
      @last_error_message = @connection&.last_error.to_s
      disconnect
      if @last_error_message.to_s.start_with?("BANNED:")
        clean_msg = @last_error_message.sub("BANNED:", "").strip
        AnilLanRework.force_main_title!("aviso_banido.png", clean_msg)
      end
    end
    if ok
      @last_connect_ip = ip
      @last_connect_player_id = player_id
      @last_connect_player_name = player_name
      @last_connect_char_name = char_name
      @last_connect_is_host = is_host
      @last_connect_alt_ips = alt_ips

      AnilLanRework.multiplayer_mode = true rescue nil
      if defined?(WorldSync)
        WorldSync.send_player_state
        @connection.flush_batch rescue nil
      end
      # Se ha skin a espera de aprovacao, lembra o jogador. A decisao pode
      # demorar dias e sem isto ele esquece que esta a espera (MOD 137).
      AnilSkinAprovacao.lembrar_pendentes if defined?(AnilSkinAprovacao)
      TradeSync.send_party_sync if defined?(TradeSync)
      # Agenda refresh pós-conexão para garantir renderização correta de sprites dos jogadores
      schedule_delayed_map_refresh!("join_settle", 1.5, 1) rescue nil
    end
    ok
  rescue => e
    @last_error_message = e.message
    disconnect
    if @last_error_message.to_s.start_with?("BANNED:")
      clean_msg = @last_error_message.sub("BANNED:", "").strip
      AnilLanRework.force_main_title!("aviso_banido.png", clean_msg)
    end
    false
  end

  def disconnect(save = true)
    AnilLanRework.intentional_disconnect = true rescue nil
    @reconnecting = false
    dispose_reconnect_banner rescue nil
    if @reconnect_thread
      @reconnect_thread.kill rescue nil
      @reconnect_thread = nil
    end
    # Salva o progresso do jogador antes de desconectar
    if save
      begin
        if defined?(Game) && Game.respond_to?(:save)
          Game.save
          log("Progresso salvo localmente na desconexão.")
        elsif defined?(SaveData) && SaveData.respond_to?(:save_to_file)
          SaveData.save_to_file(SaveData::FILE_PATH)
          log("Progresso salvo localmente na desconexão (SaveData).")
        end
      rescue => e
        log("Erro ao salvar localmente na desconexão: #{e.class}: #{e.message}")
      end
    end
    @connection&.disconnect
    @connection = nil
    deactivate_runtime!
    AnilLanRework.multiplayer_mode = false rescue nil
    # Restaura o Turbo ao estado original quando desconecta
    if defined?($CanToggle)
      $CanToggle = ($PokemonSystem.only_speedup_battles == 0 rescue true)
    end
  end

  def request_map_graphics_refresh!(reason = nil, passes = 2)
    return if AnilLanRework.joiplay? rescue false
    passes = [passes.to_i, 1].max
    current = @map_refresh_requested.to_i
    @map_refresh_requested = [current, passes].max
    log("map refresh requested reason=#{reason}") if reason
  end

  def schedule_delayed_map_refresh!(reason = nil, delay_seconds = 5.0, passes = 2)
    delay = [delay_seconds.to_f, 0.0].max
    @delayed_map_refresh_at = Time.now.to_f + delay
    @delayed_map_refresh_reason = reason.to_s
    @delayed_map_refresh_passes = [passes.to_i, 1].max
    log("delayed map refresh scheduled reason=#{reason} delay=#{delay} passes=#{@delayed_map_refresh_passes}")
  end

  def clear_delayed_map_refresh!
    @delayed_map_refresh_at = nil
    @delayed_map_refresh_reason = nil
    @delayed_map_refresh_passes = 0
  end

  def process_delayed_map_refresh!(scene = nil)
    scheduled_at = @delayed_map_refresh_at
    return false unless scheduled_at
    return false if Time.now.to_f < scheduled_at.to_f
    scene ||= $scene
    return false unless scene.is_a?(Scene_Map)
    return false unless $game_temp && $game_map && $game_player
    return false if $game_temp.in_battle
    return false if $game_temp.message_window_showing
    return false if (pbMapInterpreterRunning? rescue false)
    passes = [@delayed_map_refresh_passes.to_i, 1].max
    reason = @delayed_map_refresh_reason
    clear_delayed_map_refresh!
    request_map_graphics_refresh!(reason, passes)
    true
  end

  def suppress_peer_interaction!(frames = 12)
    current_frame = Graphics.frame_count rescue 0
    frames = [frames.to_i, 1].max
    @peer_interaction_cooldown_until = [@peer_interaction_cooldown_until.to_i, current_frame + frames].max
  end

  def peer_interaction_suppressed?
    current_frame = Graphics.frame_count rescue 0
    current_frame < @peer_interaction_cooldown_until.to_i
  end

  def clear_input_buffer
    2.times do
      Input.update rescue nil
      Graphics.update rescue nil
    end
  end

  def clear_map_graphics_refresh!
    @map_refresh_requested = 0
  end

  def fade_to_black_and_freeze
    Graphics.freeze rescue nil
  rescue
  end

  def rebuild_scene_map!(reason = nil, passes = 3)
    request_map_graphics_refresh!(reason, passes)
    Graphics.frame_reset rescue nil
    $scene = Scene_Map.new
  rescue => e
    log("rebuild_scene_map error #{e.class}: #{e.message}")
    $scene = Scene_Map.new
  end

  def hard_refresh_screen!(reason = nil, passes = 5)
    log("hard_refresh_screen triggered reason=#{reason}")
    pbFadeOutIn do
      AnilLanRework.wipe_stuck_graphics!(true) rescue nil
      $game_map&.setup($game_map.map_id)
      $game_player&.moveto($game_player.x, $game_player.y)
      $game_player&.straighten
      $scene = Scene_Map.new
    end
    true
  end

  # Refresh bruto para Joiplay - SEM pbFadeOutIn.
  # Reconstroi todos os sprites e viewports diretamente,
  # limpando qualquer estado gráfico congelado/preso.
  def joiplay_force_refresh!(scene = nil)
    scene ||= $scene
    log("joiplay_force_refresh! triggered")
    begin
      # 1. Descongelar Graphics caso esteja frozen
      Graphics.transition(0) rescue nil
      
      # 2. Limpar viewports de fade que possam estar sobrepostos
      if defined?($anil_fade_viewport) && $anil_fade_viewport
        $anil_fade_viewport.dispose rescue nil
        $anil_fade_viewport = nil
      end
      
      # 3. Resetar o mapa no mesmo lugar
      if $game_map
        map_id = $game_map.map_id
        $game_map.setup(map_id)
        $game_map.autoplay
        $game_map.update
      end
      
      # 4. Reposicionar player
      if $game_player
        $game_player.moveto($game_player.x, $game_player.y)
        $game_player.straighten
        $game_player.update
      end
      
      # 5. Recrear TODOS os spritesets se estiver na Scene_Map
      if scene.is_a?(Scene_Map)
        # Dispose do spriteset global
        if scene.instance_variable_get(:@spritesetGlobal)
          scene.instance_variable_get(:@spritesetGlobal).dispose rescue nil
          scene.instance_variable_set(:@spritesetGlobal, nil)
        end
        # Dispose e recria spritesets de mapa
        scene.disposeSpritesets rescue nil
        scene.createSpritesets rescue nil
        scene.updateSpritesets(true) rescue nil
      end
      
      # 6. Forçar múltiplos frames de update gráfico
      5.times do
        Graphics.update rescue nil
      end
      
      Graphics.frame_reset rescue nil
      log("joiplay_force_refresh! completed successfully")
    rescue => e
      log("joiplay_force_refresh! error: #{e.class}: #{e.message}")
    end
  end

  def consume_map_graphics_refresh?
    count = @map_refresh_requested.to_i
    return false if count <= 0
    @map_refresh_requested = count - 1
    true
  end

  def refresh_scene_map_graphics!(scene = nil)
    scene ||= $scene
    return false unless scene.is_a?(Scene_Map)
    begin
      $game_map.need_refresh = true if $game_map
      if scene.respond_to?(:disposeSpritesets) && scene.respond_to?(:createSpritesets)
        if scene.instance_variable_get(:@spritesetGlobal)
          scene.instance_variable_get(:@spritesetGlobal).dispose rescue nil
          scene.instance_variable_set(:@spritesetGlobal, nil)
        end
        scene.disposeSpritesets
        # RPG::Cache.clear removido para evitar bugs no Joiplay
        scene.createSpritesets
        scene.updateSpritesets(true) if scene.respond_to?(:updateSpritesets)
      end
      Graphics.frame_reset rescue nil
      Graphics.update rescue nil
      log("map graphics refreshed map_id=#{$game_map&.map_id}")
      true
    rescue => e
      log("map graphics refresh error #{e.class}: #{e.message}")
      false
    end
  end

  def update_player_config
    return unless defined?(AnilLanRework) && (AnilLanRework.multiplayer_mode || AnilLanRework.online_session?)
    file = "multiplayer_player.txt"
    return unless defined?($player) && $player
    name = $player.name.to_s
    clean_name = name.gsub(/[^a-zA-Z0-9_-]/, '')

    # Generate persistent unique ID if not exists
    if defined?($PokemonGlobal) && $PokemonGlobal
      if !$PokemonGlobal.respond_to?(:online_id)
        class << $PokemonGlobal
          attr_accessor :online_id
        end
      end
      if AnilLanRework.respond_to?(:online_session?) && AnilLanRework.online_session?
        if !$PokemonGlobal.online_id
          begin
            require 'digest'
            tempo_atual = Time.now.to_f.to_s
            salt = rand(1000000..9999999).to_s
            string_unica = "#{name}_#{tempo_atual}_#{salt}"
            $PokemonGlobal.online_id = Digest::SHA256.hexdigest(string_unica)[0, 6].upcase
          rescue => e
            # Fallback robusto se a biblioteca digest falhar
            chars = [("a".."z").to_a, ("0".."9").to_a].flatten
            $PokemonGlobal.online_id = (0...6).map { chars[rand(chars.length)] }.join.upcase
          end
        elsif $PokemonGlobal.online_id.length > 6
          $PokemonGlobal.online_id = $PokemonGlobal.online_id[0, 6].upcase
        end
      end
      hash_suffix = $PokemonGlobal.online_id
    else
      hash_suffix = nil
    end

    hash_suffix = "A78YUA" if hash_suffix.nil? || hash_suffix.empty?

    id = "#{clean_name}-#{hash_suffix}"
    @self_id = nil # Força a recarga do ID no próximo request
    char = $game_player.character_name.to_s rescue "trainer_m"

    rows = {}
    if File.exist?(file)
      File.readlines(file, encoding: "UTF-8").each do |line|
        parts = line.strip.split("=", 2)
        rows[parts[0].strip] = parts[1].to_s.strip if parts.size == 2
      end
    end
    rows["id"] = id
    rows["nome"] = name
    rows["char"] = char
    rows[COOP_PARTIAL_CFG_KEY] = "1" unless rows.key?(COOP_PARTIAL_CFG_KEY)
    rows[COOP_TOTAL_CFG_KEY] = "0" unless rows.key?(COOP_TOTAL_CFG_KEY)

    File.open(file, "wb") do |f|
      f.write(rows.map { |k, v| "#{k}=#{v}\n" }.join.encode(Encoding::UTF_8))
    end
    log("player config updated: #{id}")
  rescue => e
    log("update_player_config error: #{e}")
  end
end

module AnilLanRework
  module RememberedSessions
    FILE_PATH   = "multiplayer_sessions_rework.json"
    MAX_ENTRIES = 24

    module_function

    def load_entries
      return [] unless File.exist?(FILE_PATH)
      data = AnilLanPureJSON.decode(File.binread(FILE_PATH))
      return [] unless data.is_a?(Array)
      entries = data.map { |entry| normalize_entry(entry) }.compact
      entries.sort_by { |entry| -entry["last_seen_at"].to_i }
    rescue => e
      AnilLanRework.log("remembered sessions load error #{e.class}: #{e.message}")
      []
    end

    def save_entries(entries)
      rows = Array(entries).map { |entry| normalize_entry(entry) }.compact
      File.open(FILE_PATH, "wb") do |f|
        f.write(AnilLanPureJSON.encode(rows.first(MAX_ENTRIES)).encode(Encoding::UTF_8))
      end
    rescue => e
      AnilLanRework.log("remembered sessions save error #{e.class}: #{e.message}")
    end

    def normalize_entry(entry)
      return nil unless entry.is_a?(Hash)
      host_id = entry["host_id"].to_s.strip
      ip      = entry["last_ip"].to_s.strip
      return nil if host_id.empty? || ip.empty?
      {
        "host_id"       => host_id,
        "host_name"     => entry["host_name"].to_s,
        "display_id"    => entry["display_id"].to_s,
        "last_ip"       => ip,
        "last_seen_at"  => entry["last_seen_at"].to_i,
        "session_token" => entry["session_token"].to_s
      }
    rescue
      nil
    end

    def remember_session(ip, host_id:, host_name:, display_id: "", session_token: "")
      entry = normalize_entry(
        "host_id"       => host_id,
        "host_name"     => host_name,
        "display_id"    => display_id,
        "last_ip"       => ip,
        "last_seen_at"  => Time.now.to_i,
        "session_token" => session_token
      )
      return nil unless entry
      rows = load_entries.reject { |row| row["host_id"].to_s == entry["host_id"].to_s }
      rows.unshift(entry)
      save_entries(rows)
      entry
    end

    def forget_session(host_id)
      key = host_id.to_s
      rows = load_entries.reject { |entry| entry["host_id"].to_s == key }
      save_entries(rows)
    end

    def host_label(entry)
      row = normalize_entry(entry)
      return "" unless row
      name = row["host_name"].to_s
      name = row["display_id"].to_s if name.empty?
      name = row["host_id"].to_s if name.empty?
      "#{name} (#{row['last_ip']})"
    end

    def request(ip, packet, timeout = 1.2)
      socket = if Socket.respond_to?(:tcp)
        Socket.tcp(ip.to_s, AnilLanRework::SERVER_PORT, connect_timeout: timeout)
      else
        TCPSocket.new(ip.to_s, AnilLanRework::SERVER_PORT)
      end
      socket.write(AnilLanPureJSON.encode(packet) + "\n")
      deadline = Time.now.to_f + timeout
      buffer = +""
      loop do
        wait = deadline - Time.now.to_f
        break if wait <= 0
        ready = IO.select([socket], nil, nil, wait)
        break unless ready && ready[0]&.include?(socket)
        chunk = socket.recv(4096)
        break if chunk.nil? || chunk.empty?
        buffer << chunk
        next unless (idx = buffer.index("\n"))
        line = buffer.slice!(0..idx).to_s.strip
        return AnilLanPureJSON.decode(line) if !line.empty?
      end
      nil
    rescue => e
      AnilLanRework.log("remembered session request error ip=#{ip} #{e.class}: #{e.message}")
      nil
    ensure
      socket.close rescue nil if socket
    end

    def probe_session(entry, player_id = nil)
      row = normalize_entry(entry)
      return nil unless row
      packet = {
        "type"    => "mailbox_probe",
        "host_id" => row["host_id"]
      }
      packet["player_id"] = player_id.to_s if player_id && !player_id.to_s.empty?
      request(row["last_ip"], packet)
    end

    def pull_saved_payout(entry, player_id)
      row = normalize_entry(entry)
      return nil unless row
      return nil if player_id.to_s.empty?
      request(row["last_ip"], {
        "type"      => "mailbox_pull",
        "host_id"   => row["host_id"],
        "player_id" => player_id.to_s
      })
    end
  end
end

module AnilLanRework
  module Codec
    module_function

    def encode(packet)
      AnilLanPureJSON.encode(packet) + "\n"
    end

    def decode(line)
      AnilLanPureJSON.decode(line)
    rescue
      nil
    end
  end
end


module AnilLanRework
  module CableOrder
    module_function

    # Adapted from CableClub.pokemon_order
    def pokemon_order(client_index)
      case client_index.to_i % 2
      when 0 then [0, 2, 1, 3, 4, 5]
      when 1 then [1, 3, 0, 2, 5, 4]
      else        [0, 2, 1, 3, 4, 5]
      end
    end

    # Adapted from CableClub.pokemon_target_order
    def target_order(_client_index)
      [1, 0, 3, 2, 5, 4]
    end

    def flip_index(index)
      idx = index.to_i
      idx >= 0 ? (idx ^ 1) : idx
    end
  end
end

# --- [REMOVIDO] Bloco de codigo (linhas 1939 a 1986) movido para 000d_Multiplayer_Battle_Trade_RNG_Sync.rb ---

module AnilLanRework
  module SkinSync
    @downloading = {}
    @requested = {}

    module_function

    def check_and_request(peer_id, skin_name)
      return if skin_name.to_s.empty?
      # Ignorar nomes básicos do jogo para evitar requests desnecessários
      return if ["boy_walk", "girl_walk", "boy_run", "girl_run", "boy_surf", "girl_surf"].include?(skin_name.downcase)
      
      # Verifica se o arquivo existe (adiciona .png se necessário)
      base_name = skin_name.to_s
      path = "Graphics/Characters/#{base_name}.png"
      return if File.exist?(path)
      
      # Evitar pedidos repetidos muito rápidos (cooldown de 60 segundos por skin)
      now = Time.now.to_i
      return if @requested[base_name] && (now - @requested[base_name] < 60)
      
      @requested[base_name] = now
      AnilLanRework.log("SkinSync: solicitando '#{base_name}' do peer #{peer_id}")
      
      AnilLanRework.connection.send_packet("request_skin", {
        "to_id" => peer_id,
        "skin"  => base_name
      })
    end

    def handle_request(packet)
      skin_name = packet["skin"].to_s
      to_id = packet["sender_id"]
      return if skin_name.empty? || !to_id
      
      path = "Graphics/Characters/#{skin_name}.png"
      unless File.exist?(path)
        AnilLanRework.log("SkinSync: peer #{to_id} pediu skin '#{skin_name}' mas eu nao tenho localmente.")
        return
      end

      begin
        # Lê o arquivo binário e converte para Base64 para envio via JSON
        data = File.open(path, "rb") { |f| f.read }
        encoded = [data].pack("m0")
        
        AnilLanRework.log("SkinSync: enviando '#{skin_name}' (#{data.size} bytes) para #{to_id}")
        
        AnilLanRework.connection.send_packet("skin_data", {
          "to_id" => to_id,
          "skin"  => skin_name,
          "data"  => encoded
        })
      rescue => e
        AnilLanRework.log("SkinSync: erro ao enviar skin: #{e.message}")
      end
    end

    def handle_data(packet)
      skin_name = packet["skin"].to_s
      encoded = packet["data"].to_s
      return if skin_name.empty? || encoded.empty?
      
      # Segurança: sanitização do nome do arquivo
      safe_name = skin_name.gsub(/[^a-zA-Z0-9_\-]/, "")
      return if safe_name.empty?
      
      path = "Graphics/Characters/#{safe_name}.png"
      return if File.exist?(path)

      begin
        data = encoded.unpack1("m0")
        # Garantir que a pasta existe
        Dir.mkdir("Graphics/Characters") unless Dir.exist?("Graphics/Characters")
        
        File.open(path, "wb") { |f| f.write(data) }
        AnilLanRework.log("SkinSync: skin '#{safe_name}' baixada e salva com sucesso (#{data.size} bytes).")
        
        # O cache do RPG Maker precisa ser limpo para reconhecer o novo arquivo no disco
        RPG::Cache.clear rescue nil
      rescue => e
        AnilLanRework.log("SkinSync: erro ao salvar skin recebida: #{e.message}")
      end
    end
  end
end

class AnilLanRework::RemotePeer
  # Acima disto nao e movimento real: entrada no mapa, teleporte, ou perda
  # longa de ligacao. 15 tiles sao ~0,7s a correr, muito acima de lag normal.
  TELEPORTE_TILES = 15 unless const_defined?(:TELEPORTE_TILES)
  # Acima disto nao e movimento: e alguem que acabou de entrar no mapa, que
  # teleportou, ou pacotes perdidos. Interpolar nesses casos faz o boneco
  # atravessar paredes em linha recta ate ao destino.
  DISTANCIA_TELEPORTE = 3 unless const_defined?(:DISTANCIA_TELEPORTE)

  attr_accessor :move_speed
  attr_accessor :internal_id, :display_id, :name, :map_id, :x, :y, :dir, :char_name, :follower_char, :party_blob, :trade_index, :trade_confirmed, :pattern, :character_index, :real_x, :real_y, :sprite_size, :opacity, :blend_type, :animation_id, :transparent, :battle_busy, :menu_open, :status_id, :remote_follower_visual, :coop_wild_invites_enabled, :coop_trainer_invites_enabled, :follower_super_shiny, :follower_hue, :character_hue, :busy, :target_x, :target_y, :last_update_time, :occupied_status, :anil_perfume
  attr_accessor :f_x, :f_y, :f_rx, :f_ry, :f_dir, :f_pat

  def initialize
    @last_update_time = Time.now.to_f
    @internal_id     = ""
    @display_id      = ""
    @name            = ""
    @map_id          = -1
    @x               = 0
    @y               = 0
    @dir             = 2
    @char_name       = "POKEMONTRAINER_RojoArio"
    @anil_montaria   = nil
    @anil_montaria_shiny = false
    @anil_montaria_hue = 0
    @anil_jump_tok = nil
    @anil_jump_ini = nil
    @anil_jump_som = true
    @anil_mont_novo = nil
    @anil_mont_troca_em = nil
    @follower_char   = ""
    @anil_perfume    = false
    @party_blob      = []
    @trade_index     = nil
    @trade_confirmed = false
    @pattern         = 0
    @character_index = 0
    @real_x          = 0
    @real_y          = 0
    @target_x        = 0
    @target_y        = 0
    @sprite_size     = [0, 0]
    @opacity         = 255
    @blend_type      = 0
    @animation_id    = 0
    @transparent     = false
    @battle_busy     = false
    @menu_open       = false
    @coop_wild_invites_enabled = true
    @coop_trainer_invites_enabled = true
    @status_id       = nil
    @remote_follower_visual = false
    @follower_super_shiny = false
    @follower_hue = 0
    @character_hue = 0
    @occupied_status = nil
    @anim_count      = 0
    @moving          = false
    @initialized_pos = false
    @f_x             = nil
    @f_y             = nil
    @f_rx            = nil
    @f_ry            = nil
    @f_dir           = nil
    @f_pat           = nil
  end

  def apply_state_hash(packet)
    @last_update_time = Time.now.to_f
    @display_id    = packet["display_id"].to_s if packet.key?("display_id")
    @name          = packet["name"].to_s if packet.key?("name")
    @map_id        = packet["map_id"].to_i if packet.key?("map_id")
    @x             = packet["x"].to_i if packet.key?("x")
    @y             = packet["y"].to_i if packet.key?("y")
    @dir           = packet["dir"].to_i if packet.key?("dir")
    @char_name     = packet["char"].to_s if packet.key?("char")
    # O salto le-se PRIMEIRO: e ele que decide se a troca da montaria espera
    # pela aterragem ou entra assim que o movimento chegar ao ecra.
    saltou_agora = false
    if packet.key?("jump_tok")
      tok = packet["jump_tok"].to_i
      # ⚠️ So dispara na MUDANCA, e nunca na primeira vez que se ve este jogador.
      #
      # Sem o `!@anil_jump_tok.nil?`, alguem que entrasse no mapa com o contador
      # ja alto saltava sem razao nenhuma assim que aparecesse.
      if !@anil_jump_tok.nil? && tok != @anil_jump_tok
        # comeca quando o movimento correspondente chegar ao ecra, nao agora
        @anil_jump_ini = Time.now.to_f + atraso_render
        @anil_jump_som = false
        saltou_agora = true
      end
      @anil_jump_tok = tok
    end

    if packet.key?("mont")
      m = packet["mont"].to_s
      novo = m.empty? ? nil : m
      alvo = @anil_mont_troca_em ? @anil_mont_novo : @anil_montaria
      if novo != alvo
        @anil_mont_novo = novo
        @anil_mont_troca_em = Time.now.to_f + atraso_render +
                              (saltou_agora ? AnilLanRework::RemotePeer::SALTO_DURACAO : 0.0)
      end
    end
    @anil_montaria_shiny = (packet["mont_shiny"] == true) if packet.key?("mont_shiny")
    @anil_montaria_hue = packet["mont_hue"].to_i if packet.key?("mont_hue")
    @anil_perfume = (packet["perfume"] == true) if packet.key?("perfume")
    @follower_char = packet["follower"].to_s if packet.key?("follower")
    @party_blob    = Array(packet["party"]) if packet.key?("party")
    @battle_busy   = (packet["battle_busy"] == true || packet["busy"] == true)
    @menu_open     = (packet["menu_open"] == true || packet["busy"] == true || packet["message_active"] == true)
    @busy          = (packet["busy"] == true || packet["message_active"] == true)
    @follower_super_shiny = (packet["follower_super_shiny"] == true)
    @follower_hue  = packet["follower_hue"].to_i if packet.key?("follower_hue")
    if packet.key?("occupied_status")
      raw = packet["occupied_status"].to_s
      @occupied_status = raw.empty? ? nil : raw.to_sym
    else
      @occupied_status = nil
    end
    if packet.key?("status")
      raw = packet["status"].to_s
      @status_id = raw.empty? ? nil : raw.to_sym
    end
    if packet.key?("f_rx")
      @f_x = packet["f_x"].to_i
      @f_y = packet["f_y"].to_i
      @f_rx = packet["f_rx"].to_i
      @f_ry = packet["f_ry"].to_i
      @f_dir = packet["f_dir"].to_i
      @f_pat = packet["f_pat"].to_i
    else
      @f_x = nil
      @f_y = nil
      @f_rx = nil
      @f_ry = nil
      @f_dir = nil
      @f_pat = nil
    end
  end

  def busy?
    @battle_busy || @menu_open
  end

  def disposed?
    false
  end

  def trx; Game_Map::REAL_RES_X rescue 128; end
  def try; Game_Map::REAL_RES_Y rescue 128; end
  def direction; @dir; end
  def direction=(v); @dir = v.to_i; end
  # A especie em que este jogador vai montado, ou nil. Quem le e o 156_Montaria,
  # pelo AnilMontaria.montaria_de — que trata o RemotePeer e o $game_player da
  # mesma maneira.
  # ⚠️ O ARCO DO LADO REMOTO NAO COPIA AS MEDIDAS DO MOTOR. E DE PROPOSITO.
  #
  # O salto local dura 0,125 s e sobe 12 px — sao OITO frames. Localmente le-se
  # bem porque o motor move o boneco de um tile ao outro nesses mesmos oito
  # frames, e o olho junta as duas coisas.
  #
  # Do lado de quem ve, a posicao vem de um interpolador com buffer, e nao ha
  # garantia nenhuma de que o deslocamento horizontal caia dentro da mesma
  # janela: bastam dois ou tres frames de desencontro para o arco passar
  # despercebido e ficar so um corte. Foi o que aconteceu.
  #
  # Entao aqui o arco e mais alto e mais longo — 19 frames em vez de 8. Nao e
  # fiel ao frame, e quem esta a ver nao tem como notar; o que ele nota e se ha
  # ou nao ha um pulo.
  SALTO_DURACAO = 0.30
  SALTO_PICO    = 20

  # ⚠️ A MONTARIA DE UM REMOTO NAO SE APLICA QUANDO O PACOTE CHEGA.
  #
  # O 136_Movimento_Remoto desenha os outros jogadores 150 ms NO PASSADO (o
  # ATRASO dele), a partir de um buffer de amostras — e o que faz o andar deles
  # ser suave. So que o meu arco de salto e a troca da montaria aplicavam-se no
  # instante em que o pacote chegava, ou seja 150 ms ANTES de o movimento
  # correspondente aparecer no ecra.
  #
  # Resultado: o bicho aparecia/desaparecia antes do salto, e o arco corria
  # sozinho num sitio onde o boneco ainda nao estava. Era isso o "splitar".
  #
  # Agora a troca fica agendada para o mesmo relogio do movimento: atraso de
  # render, mais a duracao do salto quando houve salto — porque LOCALMENTE a
  # montaria so entra na aterragem.
  def atraso_render
    (AnilMovimentoRemoto::ATRASO rescue 0.15)
  end

  def anil_montaria
    if @anil_mont_troca_em && Time.now.to_f >= @anil_mont_troca_em
      @anil_montaria = @anil_mont_novo
      @anil_mont_troca_em = nil
    end
    @anil_montaria
  end

  attr_writer :anil_montaria
  # A cor da montaria DESTE jogador, vinda no pacote dele.
  attr_accessor :anil_montaria_shiny
  attr_accessor :anil_montaria_hue
  # Ultimo aviso de salto que se viu deste jogador, e quando comecou a toca-lo.
  attr_accessor :anil_jump_tok
  attr_accessor :anil_jump_ini

  def character_name; @char_name; end
  def character_name=(v)
    v = v.to_s
    if !v.empty? && @char_name != v
      @char_name = v
      AnilLanRework::SkinSync.check_and_request(@internal_id, v)
    end
  end

  def occupied_reason
    return @occupied_status if @occupied_status
    return :battle if @battle_busy == true
    return :menu if @menu_open == true
    nil
  end

  def update_from_packet(packet)
    if packet.key?("map_id")
      new_map_id = packet["map_id"].to_i
      @initialized_pos = false if @map_id != new_map_id
      @map_id = new_map_id
    end
    @dir = packet["dir"].to_i if packet.key?("dir")
    @pattern = packet["pattern"].to_i if packet.key?("pattern")
    @move_speed ||= 3.5
    # Relogio de quem enviou (ms). E a linha do tempo usada na interpolacao.
    @t_env = packet["t_env"].to_i if packet.key?("t_env")
    # Velocidade que o dono tinha no instante do envio. Sem a chave (cliente
    # antigo) fica o passo de andar, que e o comportamento de hoje.
    @move_speed = packet["move_speed"].to_f if packet.key?("move_speed")
    self.character_name = packet["char"] if packet.key?("char") && !packet["char"].to_s.empty?
    # O salto le-se PRIMEIRO: e ele que decide se a troca da montaria espera
    # pela aterragem ou entra assim que o movimento chegar ao ecra.
    saltou_agora = false
    if packet.key?("jump_tok")
      tok = packet["jump_tok"].to_i
      # ⚠️ So dispara na MUDANCA, e nunca na primeira vez que se ve este jogador.
      #
      # Sem o `!@anil_jump_tok.nil?`, alguem que entrasse no mapa com o contador
      # ja alto saltava sem razao nenhuma assim que aparecesse.
      if !@anil_jump_tok.nil? && tok != @anil_jump_tok
        # comeca quando o movimento correspondente chegar ao ecra, nao agora
        @anil_jump_ini = Time.now.to_f + atraso_render
        @anil_jump_som = false
        saltou_agora = true
      end
      @anil_jump_tok = tok
    end

    if packet.key?("mont")
      m = packet["mont"].to_s
      novo = m.empty? ? nil : m
      alvo = @anil_mont_troca_em ? @anil_mont_novo : @anil_montaria
      if novo != alvo
        @anil_mont_novo = novo
        @anil_mont_troca_em = Time.now.to_f + atraso_render +
                              (saltou_agora ? AnilLanRework::RemotePeer::SALTO_DURACAO : 0.0)
      end
    end
    @anil_montaria_shiny = (packet["mont_shiny"] == true) if packet.key?("mont_shiny")
    @anil_montaria_hue = packet["mont_hue"].to_i if packet.key?("mont_hue")
    @anil_perfume = (packet["perfume"] == true) if packet.key?("perfume")
    @follower_char = packet["follower"].to_s if packet.key?("follower")
    @battle_busy = packet["battle_busy"] == true if packet.key?("battle_busy")
    @menu_open = packet["menu_open"] == true if packet.key?("menu_open")
    if packet.key?("occupied_status")
      raw = packet["occupied_status"].to_s
      @occupied_status = raw.empty? ? nil : raw.to_sym
    end
    if packet.key?("status")
      raw = packet["status"].to_s
      @status_id = raw.empty? ? nil : raw.to_sym
    end
    if packet.key?("real_x")
      @target_x = packet["real_x"].to_i
    elsif packet.key?("x")
      @target_x = packet["x"].to_i * trx
      @x = packet["x"].to_i if !@initialized_pos
    end
    if packet.key?("real_y")
      @target_y = packet["real_y"].to_i
    elsif packet.key?("y")
      @target_y = packet["y"].to_i * try
      @y = packet["y"].to_i if !@initialized_pos
    end
    @x = packet["x"].to_i if packet.key?("x")
    @y = packet["y"].to_i if packet.key?("y")
    unless @initialized_pos
      @real_x = @target_x
      @real_y = @target_y
      @initialized_pos = true
      # Peer novo (ou mudou de mapa): o historico antigo e de outro sitio.
      AnilMovimentoRemoto.limpar!(self) if defined?(AnilMovimentoRemoto)
    end
    if packet.key?("f_rx")
      @f_x = packet["f_x"].to_i
      @f_y = packet["f_y"].to_i
      @f_rx = packet["f_rx"].to_i
      @f_ry = packet["f_ry"].to_i
      @f_dir = packet["f_dir"].to_i
      @f_pat = packet["f_pat"].to_i
    else
      @f_x = nil
      @f_y = nil
      @f_rx = nil
      @f_ry = nil
      @f_dir = nil
      @f_pat = nil
    end
    # Guarda este instante no historico. Tem de ser o ULTIMO passo do metodo:
    # corpo e follower sao gravados juntos, para depois serem desenhados no
    # mesmo instante e nunca se separarem.
    AnilMovimentoRemoto.registrar!(self) if defined?(AnilMovimentoRemoto)
  end

  # Delega para o MOD 136, dono unico da movimentacao remota.
  #
  # ⚠️ Existe outra definicao deste metodo no 000e_FPS_Patch, que carrega DEPOIS
  # e sobrepoe esta. As duas delegam para o mesmo sitio de proposito: assim
  # tanto faz qual vence, e nao ha como corrigir uma e esquecer a outra — que ja
  # aconteceu e deu build que compila sem mudar nada em jogo.
  def update_anim
    AnilMovimentoRemoto.aplicar!(self)
  end

  def jumping?; false; end
  def jump_count; 0; end
  def jump_distance; 0; end
  def jump_distance_left; 0; end
  def jump_peak; 1; end
  def shows_shadow?(_r = false); true; end
  def moving?; @moving; end
  def move_speed; 3; end
  def map; $game_map; end
  def screen_x; ((@real_x.to_f - $game_map.display_x) / (Game_Map::X_SUBPIXELS rescue 4)).round + (Game_Map::TILE_WIDTH rescue 32) / 2; end
  def screen_y_ground; ((@real_y.to_f - $game_map.display_y) / (Game_Map::Y_SUBPIXELS rescue 4)).round + (Game_Map::TILE_HEIGHT rescue 32); end
  def screen_y; screen_y_ground; end
  def screen_z(_h = 0); screen_y_ground; end
  def bush_depth; 0; end
  def tile_id; 0; end
  def x_offset; 0; end
  def y_offset; 0; end
  def bob_height; 0; end
  def pattern_surf; @pattern; end
  def should_update?; true; end
  def name; @name.to_s; end
  def character_hue; @character_hue || 0; end
  def walk_anime; true; end
  def step_anime; true; end
  def anime_count; @anim_count; end
  def width; 1; end
  def height; 1; end
end
class AnilLanRework::Connection
  attr_reader :session_token, :host_id, :last_error, :ip

  def initialize
    @socket            = nil
    @buffer            = +""
    @incoming          = []
    @connected         = false
    @join_ack_received = false
    @session_token     = nil
    @host_id           = nil
    @last_error        = nil
    @frame_counter     = 0
    @send_batch        = +""
    @ip                = nil
    # --- NOVO ---
    @recv_mutex        = Mutex.new
    @async_buffer      = +""
    @recv_thread       = nil
    @last_flush_frame  = nil
    @last_packet_time  = Time.now.to_f
  end

  def start_recv_thread
    @recv_thread&.kill rescue nil
    @recv_mutex.synchronize { @async_buffer = +"" }
    sock = @socket  # captura local para evitar race condition
    @recv_thread = Thread.new do
      begin
        loop do
          break unless @connected && sock
          # Bloqueia aqui liberando o GIL — a main thread continua rodando
          chunk = sock.recv(8192)
          if chunk.nil? || chunk.empty?
            @connected = false
            @last_error = "server disconnected (recv thread)"
            break
          end
          @recv_mutex.synchronize do
            @async_buffer << chunk
            @last_packet_time = Time.now.to_f
          end
        end
      rescue IOError, Errno::ECONNRESET, Errno::EPIPE
        @connected = false
      rescue => e
        @last_error = e.message
        @connected = false
      end
    end
  end

  def connected?
    timeout_limit = (defined?(AnilLanRework) && AnilLanRework.respond_to?(:online_session?) && AnilLanRework.online_session?) ? 60.0 : 300.0
    if @connected && @join_ack_received && Time.now.to_f - @last_packet_time > timeout_limit
      @last_error = "heartbeat timeout"
      disconnect
      return false
    end
    @connected == true
  end

  def connect(ip, internal_id:, display_id:, player_name:, char_name:, is_host:, startup: false)
    @ip = ip
    initial_state = {}
    if defined?(AnilLanRework::WorldSync)
      initial_state = AnilLanRework::WorldSync.capture_player_state || {}
    end
    is_vpn = AnilLanRework.detect_network_type(ip.to_s) =~ /ZeroTier|Radmin|Hamachi|VPN/i
    connect_timeout = if is_vpn
      [[AnilLanRework::JOIN_TIMEOUT.to_f, 12.0].max, 20.0].min
    elsif startup
      4.0
    else
      [[AnilLanRework::JOIN_TIMEOUT.to_f / 2.0, 3.0].max, 8.0].min
    end
    AnilLanRework.log("tcp connect ip=#{ip} vpn=#{is_vpn ? 'yes' : 'no'} timeout=#{connect_timeout}") rescue nil
    @socket = if Socket.respond_to?(:tcp)
      Socket.tcp(ip.to_s, AnilLanRework::SERVER_PORT, connect_timeout: connect_timeout)
    else
      TCPSocket.new(ip.to_s, AnilLanRework::SERVER_PORT)
    end
    @socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
    @socket.sync = true rescue nil
    @connected = true
    @buffer = +""
    @incoming = []
    @send_batch = +""
    @join_ack_received = false
    @session_token = nil
    @host_id = nil
    @last_error = nil
    @last_packet_time = Time.now.to_f
    if defined?(AnilLanRework) && AnilLanRework.respond_to?(:upload_custom_skin)
      skin_to_upload = ($player && $player.respond_to?(:multiplayer_skin) && $player.multiplayer_skin) ? $player.multiplayer_skin : char_name.to_s
      if skin_to_upload && !skin_to_upload.empty?
        Thread.new do
          begin
            AnilLanRework.upload_custom_skin(skin_to_upload)
          rescue
          end
        end
      end
    end
    send_packet("join",
      "internal_id" => internal_id,
      "display_id"  => display_id,
      "name"        => player_name,
      "char"        => char_name.to_s,
      "host"        => is_host ? true : false,
      "channel_id"  => ($PokemonSystem ? $PokemonSystem.multiplayer_channel : 1),
      "map_id"      => initial_state["map_id"] || (($game_map && $game_map.map_id) || -1),
      "x"           => initial_state["x"] || ($game_player&.x || 0),
      "y"           => initial_state["y"] || ($game_player&.y || 0),
      "real_x"      => initial_state["real_x"] || ($game_player&.real_x || 0),
      "real_y"      => initial_state["real_y"] || ($game_player&.real_y || 0),
      "dir"         => initial_state["dir"] || ($game_player&.direction || 2),
      "pattern"     => initial_state["pattern"] || ($game_player&.pattern || 0),
      "follower"    => initial_state["follower"] || "",
      "status"      => initial_state["status"],
      "battle_busy" => initial_state["battle_busy"] == true,
      "menu_open"   => initial_state["menu_open"] == true,
      "online_id"   => ($PokemonGlobal && $PokemonGlobal.respond_to?(:online_id) ? $PokemonGlobal.online_id : nil),
      "reconnect"   => (startup == false && (defined?(AnilLanRework) && AnilLanRework.respond_to?(:last_connect_ip) && AnilLanRework.last_connect_ip) ? true : false),
      "debug"       => ($DEBUG == true ? true : false),
      "test"        => ($TEST == true ? true : false),
      # Gate de versao: o servidor recusa quem estiver abaixo do minimo.
      "client_build" => (AnilLanRework::CLIENT_BUILD rescue ""),
      "game_version" => (Settings::GAME_VERSION rescue ""),
      # RANQUEADO: anuncia que este cliente sabe reportar o resultado de um PVP.
      # O servidor so pontua uma partida quando os DOIS lados dizem isto — ver a
      # nota em register_client (server_runtime). Cliente antigo nao envia o
      # campo, continua a jogar, e a partida simplesmente nao conta.
      "ranked"       => true
    )
    flush_batch
    start_recv_thread
    wait_for_join_ack(startup ? 6.0 : AnilLanRework::JOIN_TIMEOUT)
  rescue => e
    @last_error = e.message
    disconnect
    false
  end

  def disconnect
    @connected = false
    @recv_thread&.kill rescue nil
    @recv_thread = nil
    @socket.close rescue nil
    @socket = nil
    @send_batch = +""
  end

  def tick
    return unless connected?
    @frame_counter += 1
    read_packets
    send_packet("ping") if (@frame_counter % AnilLanRework::KEEPALIVE_TICK).zero?
    flush_batch
  end

  def send_packet(type, payload = {})
    return unless connected?
    packet = payload.merge(
      "type"      => type,
      "session"   => @session_token,
      "sender_id" => AnilLanRework.self_internal_id,
      "frame"     => Graphics.frame_count
    )
    encoded = AnilLanRework::Codec.encode(packet)
    case type.to_s
    # ⚠️ O QUE E FREQUENTE VAI NO LOTE. O RESTO E QUE PODE ESCREVER JA.
    #
    # O @socket.write daqui e SINCRONO e corre na thread do jogo: se a fila de
    # envio do sistema estiver cheia, o jogo para ali. Com o `vower_wild_spawn`
    # isso acontecia a cada selvagem que nascia — e um selvagem nasce ao passo —
    # o que dava um solavanco de FPS de cada vez.
    #
    # O lote e esvaziado uma vez por frame pelo update do Scene_Map (ver o
    # flush_batch no MOD 000e), portanto o atraso maximo e de um frame e as
    # escritas passam a ser uma so, juntas, em vez de uma por evento.
    #
    # O `vower_wild_despawn` NAO entra aqui de proposito: e raro e e enviado
    # mesmo antes de entrar em batalha, quando o Scene_Map ja nao vai correr
    # para esvaziar o lote.
    # ⚠️ OS DA CAVERNA ENTRAM AQUI PELA MESMA RAZAO QUE OS DO MATO ENTRARAM.
    #
    # Sao frequentes: as posicoes dos inimigos e do ajudante saem 7,5 vezes por
    # segundo cada uma, e cada golpe manda outro. Fora do lote, cada um deles e
    # um `@socket.write` SINCRONO na thread do jogo — 17 por segundo a somar aos
    # 30 do `player_state`. E exactamente o defeito que este lote foi escrito
    # para resolver, so que numa parte do jogo que nao existia quando ele foi
    # escrito.
    #
    # O `caverna_morte` fica de FORA de proposito, como o `vower_wild_despawn`:
    # e raro, e atrasa-lo um frame deixava o outro jogador a bater num corpo.
    when "world_snapshot", "world_event_stream", "ping",
         "vower_wild_spawn", "vower_wild_move",
         "caverna_golpe", "caverna_mob", "caverna_mobs"
      @send_batch ||= +""
      @send_batch << encoded
    else
      @socket.write(encoded)
    end
  rescue => e
    @last_error = e.message
    disconnect
  end

  def flush_batch
    return unless connected?
    return if !@send_batch || @send_batch.empty?
    # Evita múltiplos writes no mesmo frame
    current_frame = Graphics.frame_count
    return if @last_flush_frame == current_frame
    @last_flush_frame = current_frame
    @socket.write(@send_batch)
    @send_batch = +""
  rescue => e
    @last_error = e.message
    disconnect
  end

  def read_packets
    # Transfere bytes do buffer async (escrito pela recv_thread) para o buffer principal
    unless @async_buffer.empty?
      @recv_mutex.synchronize do
        @buffer << @async_buffer
        @async_buffer.clear
      end
    end

    # Processa todas as linhas completas acumuladas em uma única operação de corte
    last_newline_idx = @buffer.rindex("\n")
    if last_newline_idx
      chunk = @buffer.slice!(0..last_newline_idx)
      chunk.split("\n").each do |line|
        stripped = line.strip
        next if stripped.empty?
        packet = AnilLanRework::Codec.decode(stripped)
        next unless packet.is_a?(Hash)
        @last_packet_time = Time.now.to_f
        handle_packet(packet)
      end
    end
  rescue => e
    @last_error = e.message
    disconnect
  end

  def handle_packet(packet)
    case packet["type"]
    when "join_ack"
      @join_ack_received = true
      @session_token = packet["session_token"].to_s
      @host_id = packet["host_id"].to_s
      # ⚠️ ANTES de qualquer upload: e este pacote que diz se este servidor sabe
      # fundir seccoes. Ver AnilSaveSecoes.so_seccoes?.
      if defined?(AnilSaveSecoes) && packet.key?("so_seccoes")
        AnilSaveSecoes.servidor_definiu!(packet["so_seccoes"]) rescue nil
      end
      # RANQUEADO: pede o estado logo ao entrar. Sem isto o cartao so mostraria
      # o rank DEPOIS da primeira partida ranqueada da sessao — antes disso
      # ficava com o valor antigo dos Pontos de Batalha e sem emblema.
      AnilRanqueado.pedir_estado if defined?(AnilRanqueado)
      if packet["server_time"]
        AnilLanRework.server_time_offset = packet["server_time"].to_i - Time.now.to_i
        AnilLanRework.log("join_ack: server_time_offset set to #{AnilLanRework.server_time_offset}s")
      end
      # Desativada restauração de coordenadas via servidor para evitar descompassos e personagem sumindo
      # if packet["restore_coords"]
      #   AnilLanRework.pending_restore_coords = packet["restore_coords"]
      #   AnilLanRework.log("join_ack: enqueued restore_coords: #{packet["restore_coords"].inspect}")
      # end
      AnilLanRework.log("join_ack host=#{@host_id} session=#{@session_token} players=#{Array(packet["players"]).length}")
      Array(packet["players"]).each do |peer_hash|
        next unless peer_hash.is_a?(Hash)
        peer_id = peer_hash["internal_id"].to_s
        next if peer_id.empty? || peer_id == AnilLanRework.self_internal_id
        peer = (AnilLanRework.players[peer_id] ||= AnilLanRework::RemotePeer.new)
        peer.internal_id = peer_id
        peer.apply_state_hash(peer_hash)
        peer.update_from_packet(peer_hash)
        if defined?(AnilLanRework) && AnilLanRework.respond_to?(:known_peers) && AnilLanRework.known_peers
          AnilLanRework.known_peers[peer_id] = true
        end
        AnilLanRework.log("join_ack peer cached peer=#{peer_id} map=#{peer.map_id} x=#{peer.x} y=#{peer.y} char=#{peer.char_name}")
      end
    when "error"
      @last_error = packet["message"].to_s
      disconnect
    when "session_rehost"
      @host_id = packet["host_id"].to_s
      @session_token = packet["session_token"].to_s if packet["session_token"]
      @incoming << packet
    when "request_skin"
      AnilLanRework::SkinSync.handle_request(packet)
    when "skin_data"
      AnilLanRework::SkinSync.handle_data(packet)
    else
      if @session_token && packet.key?("session") && packet["session"].to_s != @session_token.to_s
        AnilLanRework.log("ignored packet foreign session type=#{packet["type"]} sender=#{packet["sender_id"]} session=#{packet["session"]} expected=#{@session_token}")
        return
      end
      @incoming << packet
    end
  end

  def wait_for_join_ack(timeout = AnilLanRework::JOIN_TIMEOUT)
    started = Time.now.to_f
    until @join_ack_received
      tick
      kick_packet = @incoming.find { |p| p["type"] == "admin_kick" }
      if kick_packet
        @last_error = "BANNED: #{kick_packet['reason']}"
        disconnect
        return false
      end
      if !connected?
        kick_packet = @incoming.find { |p| p["type"] == "admin_kick" }
        if kick_packet
          @last_error = "BANNED: #{kick_packet['reason']}"
        end
        return false
      end
      return false unless @last_error.to_s.empty?
      if Time.now.to_f - started >= timeout
        @last_error = "join handshake timeout"
        disconnect
        return false
      end
      sleep(0.02)
    end
    true
  end

  # ⚠️ SEM FILTRO, TIRA-SE DA FRENTE. NAO SE PROCURA.
  #
  # Isto fazia sempre um `index` — um varrimento da fila inteira — mesmo quando
  # nao havia tipo nenhum a procurar. Esvaziar N pacotes custava N(N+1)/2
  # comparacoes:
  #
  #     10 pacotes ->    55 comparacoes
  #     60 pacotes ->  1830
  #    120 pacotes ->  7260
  #
  # Num PC nao se nota. Num telemovel, com o mundo a mandar snapshots e estados
  # de varios jogadores, nota-se — e nota-se so a RECEBER, porque o envio nao
  # passa por aqui. Era essa a assimetria reportada.
  #
  # Com filtro continua a procurar (e raro e e preciso); sem filtro tira o
  # primeiro, que e o que a palavra "fila" quer dizer.
  def next_packet(expected_type = nil)
    return @incoming.shift if expected_type.nil?
    index = @incoming.index { |packet| packet["type"].to_s == expected_type.to_s }
    index ? @incoming.delete_at(index) : nil
  end

  # ⚠️ O QUE E URGENTE NAO ESPERA ATRAS DO QUE E PESADO.
  #
  # A fila era servida por ordem de chegada. Um golpe da arena que chegasse
  # depois de um `world_snapshot` esperava que o snapshot inteiro fosse
  # aplicado — switches, eventos, o mundo todo — antes de aparecer no ecra.
  #
  # Nao sao coisas da mesma natureza. Um snapshot pode chegar um frame mais
  # tarde e ninguem repara; um ataque atrasado e o jogo a responder mal.
  #
  # Duas passagens: primeiro o que tem de ser imediato, depois o resto. A
  # ordem DENTRO de cada grupo mantem-se, portanto nada se baralha.
  # ⚠️ O MOVIMENTO E O MAIS SENSIVEL DE TODOS, E ESTAVA NA FILA GERAL.
  #
  # O `player_state` e a posicao de cada jogador. Ele e barato de aplicar — sao
  # umas coordenadas — e e o unico pacote cujo atraso se ve DIRECTAMENTE: um
  # boneco a andar aos solavancos. Estava a ser servido depois de snapshots do
  # mundo, que sao caros e que ninguem nota se chegarem um frame mais tarde.
  #
  # Trocar a ordem entre os dois nao custa nada e resolve as duas coisas: o
  # movimento fica fluido e o mundo continua a chegar no mesmo frame.
  #
  # E um Hash e nao um Array: com dez tipos e dezenas de pacotes, o
  # `Array#include?` percorre a lista toda para cada um. O Hash responde de
  # imediato, e num telemovel isso conta.
  URGENTES = {
    "player_state"    => true,   # a posicao dos outros: o que mais se ve
    "peer_joined"     => true,
    "player_join"     => true,
    "peer_left"       => true,
    "arena_golpe"     => true,
    "arena_dano"      => true,
    "arena_fim"       => true,
    "arena_mostra"    => true,
    "arena_armadilha" => true,
    "arena_parceiro"  => true,
    "arena_convite"   => true,
    "arena_aceite"    => true,
    "arena_recusa"    => true
  }.freeze

  # ⚠️ UMA PASSAGEM, E NAO TRES.
  #
  # A primeira versao disto varria a fila para achar os urgentes e depois fazia
  # `@incoming -= urgentes`, que e outro varrimento por cada um deles. Corrigir
  # um custo quadratico com outro custo quadratico nao e corrigir.
  #
  # Separa-se em dois baldes numa passagem so; a ordem dentro de cada balde
  # mantem-se, que e a unica garantia que aqui importa.
  def drain
    return unless block_given?
    return if @incoming.empty?
    urgentes = []
    resto    = []
    @incoming.each do |p|
      (URGENTES[p["type"].to_s] ? urgentes : resto) << p
    end
    @incoming = resto
    urgentes.each { |p| yield p }
    while (packet = next_packet)
      yield packet
    end
  end
end


module AnilLanRework
  module Serializer
    module_function

    def dump_marshaled(object)
      [Marshal.dump(object)].pack("m0")
    rescue
      nil
    end

    def load_marshaled(blob)
      return nil if blob.nil? || blob.to_s.empty?
      Marshal.load(blob.unpack1("m0"))
    rescue
      nil
    end

    def has_key?(blob, key)
      blob.is_a?(Hash) && (blob.key?(key) || blob.key?(key.to_sym))
    end

    def fetch_value(blob, key)
      return nil unless blob.is_a?(Hash)
      return blob[key] if blob.key?(key)
      blob[key.to_sym]
    end

    def present_id(value)
      return nil if value.nil?
      text = value.to_s.strip
      return nil if text.empty?
      text.to_sym
    rescue
      nil
    end

    def bool_value(value)
      return true if value == true
      return false if value == false || value.nil?
      return true if value.to_s.strip.downcase == "true"
      false
    end

    def serialize_stat_hash(stats)
      data = {}
      return data unless stats.is_a?(Hash)
      stats.each do |key, value|
        data[key.to_s] = value.to_i
      end
      data
    end

    def apply_stat_hash(target_stats, blob)
      return unless target_stats.is_a?(Hash)
      return unless blob.is_a?(Hash)
      blob.each do |key, value|
        target_stats[key.to_sym] = value.to_i
      end
    end

    def serialize_move(move)
      return nil unless move
      {
        "id"   => move.id.to_s,
        "pp"   => move.pp.to_i,
        "ppup" => move.ppup.to_i
      }
    rescue
      nil
    end

    def deserialize_move(blob)
      move_id = if blob.is_a?(Hash)
                  present_id(fetch_value(blob, "id"))
                else
                  present_id(blob)
                end
      return nil unless move_id
      move = Pokemon::Move.new(move_id)
      if blob.is_a?(Hash)
        move.ppup = fetch_value(blob, "ppup").to_i if has_key?(blob, "ppup")
        move.pp   = fetch_value(blob, "pp").to_i if has_key?(blob, "pp")
      end
      move
    rescue
      nil
    end

    def legacy_deserialize_pokemon(blob)
      return nil unless blob.is_a?(Hash)
      species = present_id(fetch_value(blob, "species"))
      return nil unless species
      level = fetch_value(blob, "level").to_i
      level = 1 if level <= 0
      pkmn = Pokemon.new(species, level)
      if has_key?(blob, "form")
        form_value = fetch_value(blob, "form").to_i
        if pkmn.respond_to?(:form_simple=)
          pkmn.form_simple = form_value
        else
          pkmn.form = form_value
        end
      end
      Array(fetch_value(blob, "moves")).each_with_index do |move_blob, move_index|
        move = deserialize_move(move_blob)
        next unless move
        pkmn.moves[move_index] = move
      end
      ability = present_id(fetch_value(blob, "ability"))
      item = present_id(fetch_value(blob, "item"))
      pkmn.ability = ability if ability
      pkmn.item = item if item
      pkmn.calc_stats rescue nil
      pkmn
    rescue
      nil
    end

    def serialize_pokemon(pkmn)
      return nil unless pkmn
      status_id = pkmn.status rescue nil
      status_id = nil if status_id.to_s.empty? || status_id.to_sym == :NONE
      {
        "species"       => pkmn.species.to_s,
        "level"         => pkmn.level.to_i,
        "exp"           => pkmn.exp.to_i,
        "form"          => (pkmn.respond_to?(:form_simple) ? pkmn.form_simple : pkmn.form).to_i,
        "name"          => pkmn.name.to_s,
        "hp"            => pkmn.hp.to_i,
        "totalhp"       => pkmn.totalhp.to_i,
        "stats"         => (serialize_stat_hash(pkmn.stats) rescue {}),
        "status"        => status_id ? status_id.to_s : nil,
        "status_count"  => pkmn.statusCount.to_i,
        "gender"        => pkmn.gender.nil? ? nil : pkmn.gender.to_i,
        "shiny"         => pkmn.shiny? ? true : false,
        "super_shiny"   => pkmn.respond_to?(:super_shiny?) ? (pkmn.super_shiny? ? true : false) : false,
        # Hue por-Pokemon. Le o ivar em vez do getter super_shiny_hue de proposito:
        # o getter, quando nao ha hue proprio, DERIVA a cor da especie e grava no
        # cache (DBK [004] Game Data.rb:583/601). Chamar ele aqui transformaria
        # "derivado" em "fixo" em todo mundo que fosse serializado. Cache vazio
        # vai como 0 e o outro lado deriva pela especie, como deve ser.
        "super_shiny_hue" => (pkmn.instance_variable_get(:@cached_super_shiny_hue).to_i rescue 0),
        "ability_index" => pkmn.ability_index.nil? ? nil : pkmn.ability_index.to_i,
        "ability"       => (pkmn.ability_id ? pkmn.ability_id.to_s : nil),
        "nature"        => (pkmn.nature_id ? pkmn.nature_id.to_s : nil),
        # ⚠️ A NATUREZA DAS MENTAS VIAJA A PARTE.
        #
        # Uma menta escreve em `nature_for_stats` e deixa o `nature` de nascenca
        # intacto. So o segundo ia no pacote, portanto todo o Pokemon que
        # passasse pela rede — troca, mercado, co-op — chegava do outro lado com
        # os atributos revertidos: a menta que o jogador pagou evaporava-se na
        # entrega, sem erro nenhum e sem ninguem ligar uma coisa a outra.
        #
        # Vai o ID CRU (nature_for_stats_id), nao o getter: o getter, quando nao
        # ha menta, devolve a natureza normal — e isso gravava "tem menta" em
        # toda a gente.
        "nature_for_stats" => ((pkmn.nature_for_stats_id ? pkmn.nature_for_stats_id.to_s : nil) rescue nil),
        "item"          => (pkmn.item_id ? pkmn.item_id.to_s : nil),
        "poke_ball"     => (pkmn.poke_ball ? pkmn.poke_ball.to_s : nil),
        "happiness"     => pkmn.happiness.to_i,
        "personal_id"   => pkmn.personalID.to_i,
        "obtain_method" => pkmn.obtain_method.to_i,
        "obtain_map"    => pkmn.obtain_map.to_i,
        "obtain_text"   => pkmn.obtain_text.to_s,
        "obtain_level"  => pkmn.obtain_level.to_i,
        "hatched_map"   => pkmn.hatched_map.to_i,
        "time_received" => (pkmn.timeReceived.to_i rescue 0),
        "time_hatched"  => (pkmn.timeEggHatched.to_i rescue 0),
        "hp_level"      => (pkmn.respond_to?(:hp_level) ? pkmn.hp_level.to_i : 0),
        "immunities"    => (pkmn.respond_to?(:immunities) ? Array(pkmn.immunities).map { |i| i.to_s } : []),
        "iv"            => serialize_stat_hash(pkmn.iv),
        "ev"            => serialize_stat_hash(pkmn.ev),
        "moves"         => Array(pkmn.moves).map { |move| serialize_move(move) },
        "first_moves"   => Array(pkmn.first_moves).map { |move_id| move_id.to_s },
        "ot_name"       => (pkmn.owner.name.to_s rescue ""),
        "ot_gender"     => (pkmn.owner.gender.to_i rescue 2),
        "ot_id"         => (pkmn.owner.id.to_i rescue 0),
        "ot_language"   => (pkmn.owner.language.to_i rescue 0)
      }
    rescue
      nil
    end

    def apply_pokemon_blob(pkmn, blob)
      return nil unless pkmn
      return nil unless blob.is_a?(Hash)

      # Atributos de boss (Deluxe Battle Kit). PRECISAM ser aplicados antes do
      # calc_stats la embaixo, senao o HP total e recalculado sem o hp_boost e o
      # jogador 2 monta um selvagem comum no lugar do boss.
      if has_key?(blob, "hp_level") && pkmn.respond_to?(:hp_level=)
        pkmn.hp_level = fetch_value(blob, "hp_level").to_i rescue nil
      end
      if has_key?(blob, "immunities") && pkmn.respond_to?(:immunities=)
        imms = Array(fetch_value(blob, "immunities")).map { |i| present_id(i) }.compact
        pkmn.immunities = imms rescue nil
      end

      if has_key?(blob, "form")
        form_value = fetch_value(blob, "form").to_i
        if pkmn.respond_to?(:form_simple=)
          pkmn.form_simple = form_value
        else
          pkmn.form = form_value
        end
      end

      # Nivel e exp sao enviados os DOIS, e em varios Pokemon deste jogo eles
      # nao batem entre si (criados por painel/editor: level gravado sem o exp
      # correspondente). Antes isto era if/elsif e o exp sempre vencia, entao o
      # nivel era RE-DERIVADO da experiencia e mudava na travessia:
      # Charizard 53->57, Mewtwo 50->45, Electivire 51->54, Butterfree 39->37...
      # Em batalha o totalhp forcado logo abaixo mascarava o erro ate o primeiro
      # calc_stats (pbUpdate ao cair uma Illusion, p.ex.) e o HP saltava; em
      # troca o Pokemon mudava de nivel de vez.
      #
      # O nivel do dono e a verdade: e o que ele ve e o que gera os stats dele.
      # Por isso o exp entra primeiro e o nivel manda por ultimo.
      #
      # Nao se usa pkmn.level= aqui: o Level Caps EX sobrescreve esse setter e
      # faz @exp = minimum_exp_for_level(value), o que apagaria a experiencia
      # (destrutivo numa troca). Escrever @level direto preserva o exp.
      if has_key?(blob, "exp")
        pkmn.exp = fetch_value(blob, "exp").to_i
      end
      if has_key?(blob, "level")
        blob_level = fetch_value(blob, "level").to_i
        if blob_level > 0
          begin
            pkmn.instance_variable_set(:@level, blob_level)
          rescue
            pkmn.level = blob_level rescue nil
          end
        end
      end

      pkmn.personalID = fetch_value(blob, "personal_id").to_i if has_key?(blob, "personal_id")
      pkmn.name = AnilLanPureJSON.normalize_string(fetch_value(blob, "name")) if has_key?(blob, "name")
      pkmn.gender = fetch_value(blob, "gender").to_i if has_key?(blob, "gender") && !fetch_value(blob, "gender").nil?

      if has_key?(blob, "ability_index") && !fetch_value(blob, "ability_index").nil?
        pkmn.ability_index = fetch_value(blob, "ability_index").to_i
      elsif has_key?(blob, "ability")
        pkmn.ability = present_id(fetch_value(blob, "ability"))
      end

      pkmn.nature = present_id(fetch_value(blob, "nature")) if has_key?(blob, "nature")
      # DEPOIS do nature, nunca antes: o `nature_for_stats=` chama calc_stats, e
      # calcular com a natureza velha para depois a trocar era trabalho a dobrar.
      # Um cliente antigo nao manda a chave, o has_key? da false e fica tudo como
      # estava — nao ha nada a partir.
      if has_key?(blob, "nature_for_stats")
        (pkmn.nature_for_stats = present_id(fetch_value(blob, "nature_for_stats"))) rescue nil
      end
      pkmn.item = present_id(fetch_value(blob, "item")) if has_key?(blob, "item")
      pkmn.poke_ball = present_id(fetch_value(blob, "poke_ball")) if has_key?(blob, "poke_ball")
      pkmn.happiness = fetch_value(blob, "happiness").to_i if has_key?(blob, "happiness")

      if has_key?(blob, "shiny")
        shiny = bool_value(fetch_value(blob, "shiny"))
        begin
          pkmn.shiny = shiny
        rescue
          pkmn.instance_variable_set(:@shiny, shiny)
        end
      end
      if has_key?(blob, "super_shiny") && pkmn.respond_to?(:super_shiny=)
        eh_super = bool_value(fetch_value(blob, "super_shiny"))
        pkmn.super_shiny = eh_super
        # Hue por-Pokemon. Sem isto o outro lado so recebia o booleano e o DBK
        # derivava a cor pela ESPECIE — por isso "ver pokemon" de outro jogador,
        # trocas, PvP e coop mostravam o tom padrao em vez do super shiny unico.
        # Mesma regra do servidor (server_runtime.rb, deserialize_pokemon):
        # 1..359 e hue proprio; 0 (ou 360, que volta ao inicio) limpa o cache e
        # deixa o cliente derivar pela especie.
        if has_key?(blob, "super_shiny_hue") && pkmn.respond_to?(:cached_super_shiny_hue=)
          hue = fetch_value(blob, "super_shiny_hue").to_i
          if eh_super && hue > 0 && hue <= 359
            pkmn.cached_super_shiny_hue = hue
          else
            pkmn.cached_super_shiny_hue = nil
          end
        end
      end
      pkmn.obtain_method = fetch_value(blob, "obtain_method").to_i if has_key?(blob, "obtain_method")
      pkmn.obtain_map    = fetch_value(blob, "obtain_map").to_i if has_key?(blob, "obtain_map")
      pkmn.obtain_text   = fetch_value(blob, "obtain_text").to_s if has_key?(blob, "obtain_text")
      pkmn.obtain_level  = fetch_value(blob, "obtain_level").to_i if has_key?(blob, "obtain_level")
      pkmn.hatched_map   = fetch_value(blob, "hatched_map").to_i if has_key?(blob, "hatched_map")
      pkmn.timeReceived  = fetch_value(blob, "time_received").to_i if has_key?(blob, "time_received")
      pkmn.timeEggHatched = fetch_value(blob, "time_hatched").to_i if has_key?(blob, "time_hatched")

      if has_key?(blob, "ot_name")
        pkmn.owner.name     = fetch_value(blob, "ot_name").to_s rescue nil
        pkmn.owner.gender   = fetch_value(blob, "ot_gender").to_i rescue nil
        pkmn.owner.id       = fetch_value(blob, "ot_id").to_i rescue nil
        pkmn.owner.language = fetch_value(blob, "ot_language").to_i rescue nil
      end

      apply_stat_hash(pkmn.iv, fetch_value(blob, "iv"))
      apply_stat_hash(pkmn.ev, fetch_value(blob, "ev"))

      if has_key?(blob, "moves")
        moves = []
        Array(fetch_value(blob, "moves")).each_with_index do |move_blob, move_index|
          moves[move_index] = deserialize_move(move_blob)
        end
        pkmn.moves = moves
      end
      if has_key?(blob, "first_moves")
        pkmn.first_moves = Array(fetch_value(blob, "first_moves")).map { |move_id| present_id(move_id) }.compact
      end

      pkmn.calc_stats rescue nil

      # Force stats parity from network blob to prevent calculation desyncs
      if has_key?(blob, "stats")
        apply_stat_hash(pkmn.stats, fetch_value(blob, "stats")) rescue nil
      end
      if has_key?(blob, "totalhp")
        thp = fetch_value(blob, "totalhp").to_i
        begin
          pkmn.totalhp = thp
        rescue
          pkmn.instance_variable_set(:@totalhp, thp) rescue nil
        end
      end

      if has_key?(blob, "status")
        status_id = present_id(fetch_value(blob, "status"))
        if status_id.nil? || status_id == :NONE
          pkmn.heal_status rescue nil
        else
          pkmn.status = status_id rescue nil
        end
      end
      pkmn.statusCount = fetch_value(blob, "status_count").to_i if has_key?(blob, "status_count")
      pkmn.hp = fetch_value(blob, "hp").to_i if has_key?(blob, "hp")
      pkmn
    end

    def deserialize_pokemon(blob, target = nil)
      return legacy_deserialize_pokemon(blob) unless blob.is_a?(Hash)
      species = present_id(fetch_value(blob, "species"))
      return nil unless species
      pkmn = target
      if !pkmn || !pkmn.respond_to?(:species) || pkmn.species.to_s != species.to_s
        level = fetch_value(blob, "level").to_i
        level = 1 if level <= 0
        pkmn = Pokemon.new(species, level)
      end
      apply_pokemon_blob(pkmn, blob)
    rescue
      nil
    end

    def serialize_party(party)
      Array(party).map { |pkmn| serialize_pokemon(pkmn) }.compact
    end

    def deserialize_party(data)
      Array(data).map { |blob| deserialize_pokemon(blob) }.compact
    end

    # ---------------------------------------------------------------------
    # VERSOES POSICIONAIS — para quando o INDICE importa (troca)
    #
    # O serialize_party/deserialize_party acima terminam em .compact, e isso
    # esta certo para quem so itera a lista (HUD, montar equipa de batalha):
    # um Pokemon que nao se consegue reconstruir e melhor sumir do que virar
    # um buraco.
    #
    # Na TROCA e o contrario, e o .compact era um bug silencioso. O indice
    # escolhido viaja no trade_confirm ("idx" => session.local_index) e e uma
    # posicao na party REAL de quem envia; do outro lado ele indexa o blob.
    # Se um Pokemon qualquer falhar a serializar ou a desserializar, o .compact
    # fecha o buraco e TUDO o que vem depois anda uma casa. O resultado nao e
    # so a troca falhar por nil — quando ha Pokemon suficientes a seguir, ela
    # completa-se com o Pokemon ERRADO, sem erro nenhum.
    #
    # Isto explica o padrao observado: falha aleatoria (depende de quem e o
    # parceiro e do que ele tem na party) e sem uma linha nos logs do servidor,
    # porque tudo acontece no cliente e as duas rotinas engolem a excecao.
    #
    # Aqui guarda-se a posicao com nil. Quem le tem de tratar o nil — e no
    # caminho da troca ja trata: `unless my_pkmn && their_pkmn` aborta limpo.
    #
    # Compatibilidade: um cliente antigo que receba um blob com nulos volta a
    # compacta-los na leitura, ou seja, fica exactamente como esta hoje. Nao
    # piora nada em versoes misturadas, e fica correcto quando os dois lados
    # tiverem esta versao.
    # ---------------------------------------------------------------------
    def serialize_party_posicional(party)
      Array(party).map do |pkmn|
        next nil unless pkmn
        blob = (serialize_pokemon(pkmn) rescue nil)
        if blob.nil?
          AnilLanRework.log("[TRADE] AVISO: nao consegui serializar #{(pkmn.name rescue '?')} (#{(pkmn.species rescue '?')}); a posicao vai vazia") rescue nil
        end
        blob
      end
    end

    def deserialize_party_posicional(data)
      Array(data).each_with_index.map do |blob, i|
        next nil if blob.nil?
        pkmn = deserialize_pokemon(blob)
        if pkmn.nil?
          especie = (fetch_value(blob, "species") rescue nil)
          AnilLanRework.log("[TRADE] AVISO: nao consegui reconstruir o Pokemon da posicao #{i} (species=#{especie.inspect})") rescue nil
        end
        pkmn
      end
    end

    def serialize_trainers(trainers)
      Array(trainers).map do |trainer|
        next nil unless trainer
        dump_marshaled(trainer)
      rescue
        nil
      end.compact
    end

    def deserialize_trainers(data)
      Array(data).map do |blob|
        load_marshaled(blob)
      rescue
        nil
      end.compact
    end
  end
end

module AnilLanRework
  module WorldSync
    MAX_TRACKED_SWITCH = 500
    EVENT_INTERP_SPEED_X = AnilLanRework::REMOTE_INTERP_SPEED_X
    EVENT_INTERP_SPEED_Y = AnilLanRework::REMOTE_INTERP_SPEED_Y
    EVENT_TELEPORT_THRESHOLD = AnilLanRework::REMOTE_TELEPORT_THRESHOLD_TILES
    @revision = 0
    @authoritative_map_id = nil
    @pending_snapshot = nil
    @pending_event_stream = nil
    @event_stream_cache = {}
    @event_stream_map_id = nil
    @switch_cache = {}
    @self_switch_cache = {}
    @spawn_authority_cache = {}
    @spawn_authority_cache_frame = -1
    @host_reported_map_id = nil
    @host_reported_map_frame = -1

    class << self
      attr_accessor :authoritative_map_id
      attr_accessor :host_reported_map_id
      attr_accessor :host_reported_map_frame
      attr_accessor :pending_snapshot
      attr_accessor :pending_event_stream
      attr_accessor :event_stream_cache
      attr_accessor :event_stream_map_id
      attr_accessor :switch_cache
      attr_accessor :self_switch_cache
      attr_accessor :spawn_authority_cache
      attr_accessor :spawn_authority_cache_frame
    end

    module_function

    def get_local_follower_event
      if defined?($game_temp) && $game_temp && $game_temp.respond_to?(:followers) && $game_temp.followers
        fol = $game_temp.followers.get_follower_by_index(0) rescue nil
        return fol if fol && fol.character_name && !fol.character_name.empty?
      end
      nil
    rescue
      nil
    end

    def capture_player_state
      return nil unless $game_map && $game_player
      real_res_x = Game_Map::REAL_RES_X rescue 128
      real_res_y = Game_Map::REAL_RES_Y rescue 128
      # Metadados do follower saem do MESMO Pokemon que ele mostra (o 1o apto),
      # nao de party.first. Antes o substituto herdava status/brilho do desmaiado.
      follower_pkmn = visible_follower_pokemon
      follower_status = begin
        raw = follower_pkmn ? (follower_pkmn.status rescue nil) : nil
        raw = nil if raw.to_s.empty? || raw.to_sym == :NONE rescue false
        raw ? raw.to_s : nil
      rescue
        nil
      end
      res = {
        "internal_id" => AnilLanRework.self_internal_id,
        "display_id"  => AnilLanRework.self_display_id,
        "name"        => AnilLanRework.self_name,
        "map_id"      => $game_map.map_id,
        "x"           => $game_player.x,
        "y"           => $game_player.y,
        "real_x"      => ($game_player.real_x rescue ($game_player.x * real_res_x)),
        "real_y"      => ($game_player.real_y rescue ($game_player.y * real_res_y)),
        "dir"         => $game_player.direction,
        "pattern"     => ($game_player.pattern rescue 0),
        # VELOCIDADE REAL, em vez de a adivinhar pelo nome do sprite.
        #
        # O lado remoto deduzia "esta a correr?" de char_name.include?("run").
        # So que 7 dos 652 charsets tem variante _run — as 645 skins restantes
        # nunca acionavam a corrida, e o boneco era desenhado a andar enquanto o
        # dono corria. Dai ficar para tras e depois saltar para alcançar.
        #
        # Numeros do motor (set_movement_type): andar 3.5, correr 5.5, bici 8,
        # surf 4, mergulho 4.8, gelo 6.
        "move_speed"  => ($game_player.move_speed rescue 3.5),
        # RELOGIO DE QUEM ENVIA, em milissegundos.
        #
        # E o que permite ao outro lado reconstruir a linha do tempo real do
        # movimento. Carimbar pela hora de CHEGADA parece equivalente e nao e: o
        # jitter da rede entraria direto na posicao desenhada. Medido em
        # simulacao, com 80ms de jitter isso dava saltos de 149px contra 50px do
        # esperado. Nao e preciso os relogios estarem certos entre si — so
        # precisam andar, porque o que se usa sao as DIFERENCAS.
        "t_env"       => (Time.now.to_f * 1000).to_i,
        "char"        => $game_player.character_name.to_s,
        # A montaria e so o nome da especie; o desenho monta-se do outro lado a
        # partir da receita, que ja viaja no update. Nil quando se anda a pe, e
        # os clientes antigos ignoram a chave.
        "mont"        => (defined?(AnilMontaria) ? (AnilMontaria.montado rescue nil) : nil),
        # ⚠️ A COR TEM DE VIAJAR COM A ESPECIE.
        #
        # Sem isto o outro lado desenhava a montaria com a cor de um Pokemon da
        # equipa DELE — a funcao que a calculava nao levava personagem e lia
        # sempre a equipa local.
        "mont_shiny"  => (defined?(AnilMontaria) ? ((AnilMontaria.montaria_shiny? rescue false) ? true : false) : false),
        "mont_hue"    => (defined?(AnilMontaria) ? (AnilMontaria.montaria_hue.to_i rescue 0) : 0),
        # Sobe a cada salto de montar/desmontar. Ver o marcar_salto! no MOD 160.
        "jump_tok"    => ($anil_montaria_salto_tok.to_i rescue 0),
        # ⚠️ O FOLLOWER ESCONDIDO TEM DE VIAJAR COMO ESCONDIDO.
        #
        # O resolve_follower_char, quando o sistema de followers nao devolve
        # sprite nenhum, cai para o primeiro Pokemon APTO da equipa. Isso e o
        # que se quer quando o follower existe mas ainda nao tem sprite — e e
        # exactamente o que NAO se quer quando o jogador o guardou com a tecla:
        # localmente desaparecia, e para os outros continuava la para sempre.
        #
        # Aqui le-se a intencao (`follower_toggled`) e nao o desenho.
        # ⚠️ ESCONDER O SEGUIDOR SO DO MEU LADO NAO O ESCONDE.
        #
        # O `Followers.hide_followers` da arena tira-o da MINHA tela; para os
        # outros ele continua a existir, porque quem o desenha na tela deles e
        # este campo. Um Pokemon a lutar com outro Pokemon colado atras nao le
        # como luta nenhuma. Vazio quer dizer "nao tenho seguidor", que e a
        # mesma coisa que o jogo ja diz quando o jogador o desliga.
        "follower"    => ((($PokemonGlobal && $PokemonGlobal.follower_toggled == false) ||
                           (AnilArena.activa? rescue false)) ? "" : resolve_follower_char),
        # Perfume do Sweet Scent ligado? So o suficiente para o outro lado
        # desenhar as petalas — a duracao e os passos ficam em casa.
        "perfume"     => (defined?(AnilPerfume) ? ((AnilPerfume.activo? rescue false) ? true : false) : false),
        "status"      => follower_status,
        "battle_busy" => AnilLanRework::BattleSync.local_player_busy?,
        "menu_open"   => (($game_temp && $game_temp.in_menu) ? true : false),
        "channel_id"  => ($PokemonSystem ? $PokemonSystem.multiplayer_channel : 1),
        "occupied_status" => (
          if AnilLanRework::BattleSync.active_context && AnilLanRework::BattleSync.active_context.mode == :pvp
            :pvp
          elsif ($game_temp && $game_temp.in_battle) || $scene.is_a?(Battle::Scene)
            :battle
          elsif $anil_current_menu_state
            $anil_current_menu_state
          elsif defined?(::PokemonBag_Scene) && $scene.is_a?(::PokemonBag_Scene)
            :bag
          elsif AnilLanRework.local_player_afk?
            :afk
          elsif ($game_temp && $game_temp.in_menu) || (!$scene.is_a?(Scene_Map) && !$scene.is_a?(Battle::Scene))
            :menu
          else
            nil
          end
        ),
        "message_active" => (AnilLanRework.message_active || ($game_temp && $game_temp.respond_to?(:message_window_showing) && $game_temp.message_window_showing) ? true : false),
        "follower_super_shiny" => (follower_pkmn && follower_pkmn.respond_to?(:super_shiny?) && follower_pkmn.super_shiny?) ? true : false,
        "follower_hue" => (follower_pkmn && follower_pkmn.respond_to?(:super_shiny_hue)) ? follower_pkmn.super_shiny_hue : 0,
        "coop_wild_invites_enabled" => ($PokemonSystem.coop_wild_invites == 0),
        "coop_trainer_invites_enabled" => ($PokemonSystem.coop_trainer_invites == 0)
      }
      fol = get_local_follower_event
      if fol
        res["f_x"]   = fol.x
        res["f_y"]   = fol.y
        res["f_rx"]  = fol.real_x
        res["f_ry"]  = fol.real_y
        res["f_dir"] = fol.direction
        res["f_pat"] = fol.pattern
      end
      res
    end

    def capture_event_state(event)
      data = {
        "x"      => event.x,
        "y"      => event.y,
        "real_x" => event.real_x,
        "real_y" => event.real_y,
        "dir"    => event.direction,
        "pattern"=> event.pattern,
        "char"   => event.character_name.to_s,
        "page"   => (event.instance_variable_get(:@page_index) || -1).to_i,
        "through"=> (event.through ? 1 : 0)
      }
      if defined?(Game_PokeEvent) && event.is_a?(Game_PokeEvent)
        data["is_poke"] = true
        data["pkmn"] = AnilLanRework::Serializer.serialize_pokemon(event.pokemon) if event.pokemon
      end
      data
    end

    def capture_event_state_light(event)
      data = {
        "x"       => event.x,
        "y"       => event.y,
        "real_x"  => event.real_x,
        "real_y"  => event.real_y,
        "dir"     => event.direction,
        "pattern" => event.pattern,
        "char"    => event.character_name.to_s,
        "page"    => (event.instance_variable_get(:@page_index) || -1).to_i,
        "through" => (event.through ? 1 : 0)
      }
      if defined?(Game_PokeEvent) && event.is_a?(Game_PokeEvent)
        data["is_poke"] = true
      end
      data
    end

    def reset_event_stream_cache_if_needed
      current_map_id = ($game_map && $game_map.map_id) || -1
      if @event_stream_map_id != current_map_id
        @event_stream_map_id = current_map_id
        @event_stream_cache = {}
      end
    end

    # Pokemon que o follower mostra: primeiro APTO (nao desmaiado/nao ovo),
    # com fallback para o 1o slot. So usado para os metadados do follower.
    def visible_follower_pokemon
      return nil unless defined?($player) && $player && $player.party
      # ⚠️ Montado, o follower nao pode ser o Pokemon montado — senao os OUTROS
      # jogadores viam o mesmo bicho duas vezes: por baixo e atras. Mesma regra
      # do lado local; ver o pokemon_do_follower no MOD 156.
      if defined?(AnilMontaria) && (AnilMontaria.montado? rescue false)
        return (AnilMontaria.pokemon_do_follower rescue nil)
      end
      ($player.first_able_pokemon rescue nil) || $player.party.first
    rescue
      nil
    end

    def resolve_follower_char
      visible_char = resolve_visible_follower_char
      return visible_char unless visible_char.empty?
      # Fallback so dispara quando o sistema de follower nao devolve char. Usa o
      # primeiro APTO (o substituto quando o 1o desmaia), nao party.first cru —
      # senao os outros jogadores viam o Pokemon desmaiado. A logica de sprite
      # abaixo fica EXATAMENTE como o original (nao mexer no render local).
      pkmn = visible_follower_pokemon
      return "" unless pkmn
      species = pkmn.species.to_s
      form = (pkmn.respond_to?(:form_simple) ? pkmn.form_simple : pkmn.form).to_i rescue 0
      suffix = form > 0 ? "_#{form}" : ""
      if pkmn.shiny?
        shiny_path = "Followers shiny/#{species}#{suffix}"
        return shiny_path if pbResolveBitmap("Graphics/Characters/#{shiny_path}") rescue nil
      end
      default_path = "Followers/#{species}#{suffix}"
      return default_path if pbResolveBitmap("Graphics/Characters/#{default_path}") rescue nil
      fallback_path = "Followers/#{species}"
      return fallback_path if pbResolveBitmap("Graphics/Characters/#{fallback_path}") rescue nil
      ""
    rescue
      ""
    end

    def resolve_visible_follower_char
      followers = nil
      followers = $game_temp.followers if defined?($game_temp) && $game_temp && $game_temp.respond_to?(:followers)
      visible = followers.visible_followers if followers && followers.respond_to?(:visible_followers)
      # Filtra apenas followers com Pokémon vivos
      Array(visible).each do |follower|
        next unless follower && follower.respond_to?(:character_name)
        char = follower.character_name.to_s
        next if char.empty?
        return char
      end
      ""
    rescue
      ""
    end

    def capture_switches
      out = {}
      (1..MAX_TRACKED_SWITCH).each do |index|
        value = $game_switches[index] rescue nil
        @switch_cache[index] = value
        out[index.to_s] = value if value
      end
      out
    end

    def capture_switches_full
      out = {}
      (1..MAX_TRACKED_SWITCH).each do |index|
        value = $game_switches[index] rescue nil
        @switch_cache[index] = value
        out[index.to_s] = value if value
      end
      out
    end

    def capture_switches_delta
      out = {}
      (1..MAX_TRACKED_SWITCH).each do |index|
        value = $game_switches[index] rescue nil
        next if !value && !@switch_cache.key?(index)
        next if value == @switch_cache[index]
        @switch_cache[index] = value
        out[index.to_s] = value
      end
      out
    end

    # O @self_switch_cache e indexado pela CHAVE ORIGINAL ([map, evento, "A"]),
    # nao pela string do protocolo. Array em Ruby tem hash por valor, entao serve
    # de chave direto — e a string "#{k[0]}_#{k[1]}_#{k[2]}" so precisa existir
    # para o que REALMENTE mudou, que e o que vai no pacote.
    #
    # PERFORMANCE: antes a string era montada para TODO self switch do save a
    # cada captura, e isso roda a cada EVENT_STREAM_TICK = 6 frames (~7x/s) no
    # host. Num save avancado sao milhares de self switches, ou seja dezenas de
    # milhares de strings descartaveis por segundo so para descobrir que nada
    # mudou. Esse lixo de GC engasga o frame do host — e como o
    # send_player_state e disparado por contagem de frames, o envio da posicao
    # sai irregular e o OUTRO jogador ve o host andando aos trancos, mesmo com a
    # tela do host parecendo normal (o proprio boneco e local).
    def self_switch_wire_key(key)
      "#{key[0]}_#{key[1]}_#{key[2]}"
    end

    def capture_self_switches
      out = {}
      raw = ($game_self_switches.instance_variable_get(:@data) rescue nil) || {}
      raw.each do |key, value|
        @self_switch_cache[key] = value ? true : false
        out[self_switch_wire_key(key)] = true if value
      end
      out
    end

    def capture_self_switches_delta
      out = {}
      raw = ($game_self_switches.instance_variable_get(:@data) rescue nil) || {}

      raw.each do |key, value|
        novo = value ? true : false
        next if @self_switch_cache[key] == novo
        @self_switch_cache[key] = novo
        out[self_switch_wire_key(key)] = novo
      end

      # Chaves que sumiram do @data desde a ultima captura. Antes isto pedia
      # @self_switch_cache.keys, que aloca um array com TODAS as chaves a cada
      # chamada; com a chave original da para consultar o raw direto.
      @self_switch_cache.each do |key, cacheado|
        next if cacheado == false
        next if raw.key?(key)
        @self_switch_cache[key] = false
        out[self_switch_wire_key(key)] = false
      end

      out
    end
    def capture_events
      out = {}
      reset_event_stream_cache_if_needed
      $game_map.events.each do |event_id, event|
        next unless event
        next unless defined?(Game_PokeEvent) && event.is_a?(Game_PokeEvent)
        out[event_id.to_s] = capture_event_state(event)
      end
      out
    end

    def capture_events_light
      out = {}
      reset_event_stream_cache_if_needed
      $game_map.events.each do |event_id, event|
        next unless event
        next unless defined?(Game_PokeEvent) && event.is_a?(Game_PokeEvent)
        out[event_id.to_s] = capture_event_state_light(event)
      end
      out
    end

    def capture_event_deltas
      out = {}
      live_ids = {}
      reset_event_stream_cache_if_needed
      $game_map.events.each do |event_id, event|
        next unless event
        next unless defined?(Game_PokeEvent) && event.is_a?(Game_PokeEvent)
        key = event_id.to_s
        live_ids[key] = true
        state = capture_event_state(event)
        state.delete("pkmn")
        previous = @event_stream_cache[key]
        next if previous == state
        @event_stream_cache[key] = state
        out[key] = state
      end
      @event_stream_cache.keys.each do |key|
        @event_stream_cache.delete(key) unless live_ids[key]
      end
      out
    end

    def build_snapshot
      return nil unless $game_map && $game_player
      @revision += 1
      force_full_sw = (@revision <= 1) || (@revision % 20 == 0)
      {
        "type"       => "world_snapshot",
        "revision"   => @revision,
        "host_id"    => AnilLanRework.self_internal_id,
        "map_id"     => $game_map.map_id,
        "host_state" => capture_player_state,
        "switches"   => force_full_sw ? capture_switches_full : capture_switches_delta,
        "self_sw"    => capture_self_switches_delta,
        "events"     => capture_events_light
      }
    end

    def build_event_stream
      return nil unless $game_map
      events = capture_event_deltas
      sw_delta = capture_switches_delta
      self_sw_delta = capture_self_switches_delta
      return nil if events.empty? && sw_delta.empty? && self_sw_delta.empty?
      packet = {
        "type"       => "world_event_stream",
        "host_id"    => AnilLanRework.self_internal_id,
        "map_id"     => $game_map.map_id,
        "events"     => events
      }
      packet["sw"] = sw_delta unless sw_delta.empty?
      packet["self_sw"] = self_sw_delta unless self_sw_delta.empty?
      packet
    end

    # ⚠️ O MESMO ESTADO IA DUAS VEZES A CADA TROCA DE MAPA.
    #
    # Tres MODs fazem alias do Scene_Map#transfer_player — o 000 (aqui), o 099
    # (correcao de coordenadas) e o 101 (modo completo) — e correm todos em
    # cadeia. O 000 manda o estado depois da transferencia; o 099 volta a mandar
    # depois de correr o fix_player_position. Dois pacotes "player_state" por
    # mapa, por jogador.
    #
    # Nao se apaga nenhuma das duas chamadas: a do 099 e a que vale (vem DEPOIS
    # de o fix poder ter mexido nas coordenadas, portanto a do 000 e que pode
    # sair velha), mas apagar a do 000 deixaria o envio dependente de o alias do
    # 099 estar vivo. O corte fica aqui, onde vale para qualquer caminho:
    # repetir o MESMO estado no MESMO frame nao diz nada de novo ao servidor.
    #
    # A dedupe e so dentro do frame de proposito. Entre frames o estado repetido
    # ainda serve de sinal de vida, e nao se mexe nisso as cegas.
    def send_player_state
      return unless AnilLanRework.connected?
      payload = capture_player_state
      return unless payload
      frame = (Graphics.frame_count rescue 0)
      if @last_state_frame == frame && @last_state_payload == payload
        return
      end
      @last_state_frame   = frame
      @last_state_payload = payload
      AnilLanRework.connection.send_packet("player_state", payload)
    end

    def send_snapshot_if_host
      return unless AnilLanRework.host?
      payload = build_snapshot
      return unless payload
      AnilLanRework.connection.send_packet("world_snapshot", payload)
    end

    def send_event_stream_if_host
      return unless AnilLanRework.host?
      packet = build_event_stream
      return unless packet
      AnilLanRework.connection.send_packet("world_event_stream", packet)
    end

    def queue_snapshot(packet)
      @pending_snapshot = packet if packet.is_a?(Hash)
    end

    def queue_event_stream(packet)
      @pending_event_stream = packet if packet.is_a?(Hash)
    end

    def apply_pending_snapshot
      return unless @pending_snapshot
      packet = @pending_snapshot
      @pending_snapshot = nil
      apply_snapshot(packet)
    end

    def apply_pending_event_stream
      return unless @pending_event_stream
      packet = @pending_event_stream
      @pending_event_stream = nil
      apply_event_stream(packet)
    end

    def apply_snapshot(packet)
      return unless packet.is_a?(Hash)
      map_id = packet["map_id"].to_i
      return if map_id <= 0

      # Evitar que o Host adicione a si mesmo como peer ao receber o próprio snapshot (redundância)
      host_id = packet["host_id"].to_s
      if host_id != AnilLanRework.self_internal_id
        apply_host_state(packet["host_state"])
      end

      @host_reported_map_id = map_id
      @host_reported_map_frame = Graphics.frame_count rescue 0

      if !$game_map || $game_map.map_id != map_id
        @authoritative_map_id = nil
        return
      end

      @authoritative_map_id = map_id

      apply_switches(packet["switches"])
      apply_self_switches(packet["self_sw"])
      apply_events(packet["events"])
    end

    def apply_event_stream(packet)
      return unless packet.is_a?(Hash)
      map_id = packet["map_id"].to_i
      return if map_id <= 0
      @host_reported_map_id = map_id
      @host_reported_map_frame = Graphics.frame_count rescue 0
      return unless $game_map && $game_map.map_id == map_id
      @authoritative_map_id = map_id
      apply_switches(packet["sw"]) if packet["sw"]
      apply_self_switches(packet["self_sw"]) if packet["self_sw"]
      apply_event_motion(packet["events"])
    end

    def apply_host_state(hash)
      return unless hash.is_a?(Hash)
      host_id = hash["internal_id"].to_s
      host_id = AnilLanRework.connection&.host_id.to_s if host_id.empty?
      return if host_id.empty? || host_id == AnilLanRework.self_internal_id

      # Segurança extra: se já existir mas com ID diferente, remover antigo
      AnilLanRework.players.delete(host_id) if AnilLanRework.players[host_id] && AnilLanRework.players[host_id].internal_id != host_id

      peer = (AnilLanRework.players[host_id] ||= AnilLanRework::RemotePeer.new)
      peer.internal_id = host_id
      peer.apply_state_hash(hash)
      peer.update_from_packet(hash)
    rescue => e
      AnilLanRework.log("apply_host_state error #{e}")
    end

    # ------------------------------------------------------------------
    # PERFORMANCE: so marca need_refresh quando algo REALMENTE mudou.
    #
    # O host manda world_event_stream a cada EVENT_STREAM_TICK = 6 frames, ou
    # seja ~7 vezes por segundo, e essas duas funcoes marcavam
    # $game_map.need_refresh INCONDICIONALMENTE. O Game_Map#refresh percorre
    # TODOS os eventos do mapa chamando event.refresh, entao o cliente refazia o
    # mapa inteiro 7x por segundo mesmo com nenhuma switch tendo mudado —
    # reavaliando condicao de quest que nem esta ativa.
    #
    # Isso explica o sintoma de o movimento parecer travado SO NA TELA DO OUTRO:
    # quem anda ve o proprio boneco liso (e local), mas quem RECEBE o stream
    # gasta o frame refazendo o mapa e desenha o peer aos solavancos.
    #
    # O snapshot manda o estado inteiro de proposito (para reconciliar), entao a
    # comparacao tem de ser feita aqui, no destino, e nao no envio.
    # ------------------------------------------------------------------
    def apply_switches(hash)
      return unless hash.is_a?(Hash)
      mudou = false
      hash.each do |key, value|
        idx = key.to_i
        novo = value ? true : false
        atual = $game_switches[idx] ? true : false
        next if atual == novo
        $game_switches[idx] = novo
        mudou = true
      end
      $game_map.need_refresh = true if mudou rescue nil
    end

    def apply_self_switches(hash)
      return unless hash.is_a?(Hash)
      mudou = false
      hash.each do |key, value|
        parts = key.to_s.split("_")
        next unless parts.length == 3
        chave = [parts[0].to_i, parts[1].to_i, parts[2]]
        novo  = value ? true : false
        atual = ($game_self_switches[chave] ? true : false) rescue false
        next if atual == novo
        $game_self_switches[chave] = novo rescue nil
        mudou = true
      end
      $game_map.need_refresh = true if mudou rescue nil
    end

    def build_remote_poke_rpg_event(id, state)
      event = RPG::Event.new(state["x"].to_i, state["y"].to_i)
      event.id = id
      event.name = "anil_remote_poke_#{id}"
      page = event.pages[0]
      page.graphic.character_name = state["char"].to_s
      page.graphic.character_hue = 0
      page.trigger = 2
      page.step_anime = true
      page.move_speed = 3
      page.move_frequency = 3
      page.move_type = 0
      if defined?(Compiler)
        Compiler::push_script(page.list, "AnilLanRework::WorldSync.start_remote_poke_battle(#{id})")
        Compiler::push_end(page.list)
      end
      event
    end

    def sync_remote_poke_sprite(event)
      return unless event
      return unless $scene.is_a?(Scene_Map)
      return unless $scene.respond_to?(:spritesets)
      spritesets = $scene.spritesets
      return unless spritesets
      spriteset = spritesets[$game_map.map_id] rescue nil
      spriteset ||= spritesets.values.find { |s| s.respond_to?(:map) && s.map == $game_map } rescue nil
      return unless spriteset
      return unless spriteset.respond_to?(:character_sprites)
      already_present = spriteset.character_sprites.any? { |sprite| sprite.character == event } rescue false
      return if already_present
      viewport = Spriteset_Map.viewport rescue nil
      return unless viewport
      spriteset.character_sprites.push(Sprite_Character.new(viewport, event))
    rescue => e
      AnilLanRework.log("sync_remote_poke_sprite error #{e}")
    end

    def create_remote_poke_event(id, state)
      return nil unless state.is_a?(Hash)
      pokemon = AnilLanRework::Serializer.deserialize_pokemon(state["pkmn"])
      return nil unless pokemon
      rpg_event = build_remote_poke_rpg_event(id, state)
      game_event = Game_PokeEvent.new($game_map.map_id, rpg_event, $game_map)
      game_event.id = id
      game_event.moveto(state["x"].to_i, state["y"].to_i)
      game_event.pokemon = pokemon
      # build_remote_poke_rpg_event deixa o hue em 0 e o sync_remote_poke_sprite
      # so cria o sprite, entao o Pokemon remoto aparecia sem cor. Aqui ja temos
      # o objeto, entao aplica-se o tom como no 070_Multiplayer_OW_Spawns_Sync.
      if pokemon.respond_to?(:super_shiny?) && pokemon.super_shiny?
        hue_remoto = (pokemon.super_shiny_hue.to_i rescue 0)
        rpg_event.pages[0].graphic.character_hue = hue_remoto rescue nil
        game_event.character_hue = hue_remoto rescue nil
      end
      game_event.instance_variable_set(:@anil_remote_poke_event, true)
      $game_map.events[id] = game_event
      game_event.calculate_bush_depth rescue nil
      sync_remote_poke_sprite(game_event)
      game_event
    rescue => e
      AnilLanRework.log("create_remote_poke_event error #{e}")
      nil
    end

    def remove_remote_poke_event(id)
      return unless $game_map && $game_map.events
      if $game_map.respond_to?(:removeThisEventfromMap)
        $game_map.removeThisEventfromMap(id)
      else
        $game_map.events.delete(id)
      end
    rescue => e
      AnilLanRework.log("remove_remote_poke_event error #{e}")
    end

    def remote_poke_event?(event)
      defined?(Game_PokeEvent) && event.is_a?(Game_PokeEvent) &&
        event.instance_variable_get(:@anil_remote_poke_event) == true
    end

    def request_remote_poke_battle(event)
      return unless event
      return unless AnilLanRework.connected?
      host_id = AnilLanRework.connection&.host_id.to_s
      return if host_id.empty?
      AnilLanRework.connection.send_packet("remote_poke_battle_request",
        "to_id"    => host_id,
        "map_id"   => $game_map.map_id,
        "event_id" => event.id
      )
    rescue => e
      AnilLanRework.log("request_remote_poke_battle error #{e}")
    end

    def start_remote_poke_battle(event_id)
      return false unless defined?(Game_PokeEvent)
      return false unless $game_map && $game_map.events
      event = $game_map.events[event_id.to_i]
      return false unless remote_poke_event?(event)
      pokemon = event.pokemon
      return false unless pokemon

      request_remote_poke_battle(event)
      remove_remote_poke_event(event.id)

      begin
        pbStoreTempForBattle() if defined?(pbStoreTempForBattle)
        if $PokemonEncounters && $PokemonEncounters.respond_to?(:encounter_type_on_tile)
          $game_temp.encounter_type = $PokemonEncounters.encounter_type_on_tile(event.x, event.y)
        end
        allowed = true
        allowed = pbCheckBattleAllowed() if defined?(pbCheckBattleAllowed)
        return false unless allowed
        $PokemonGlobal.battlingSpawnedPokemon = true if defined?($PokemonGlobal)
        pbSingleOrDoubleWildBattle($game_map.map_id, event.x, event.y, pokemon)
        true
      ensure
        $PokemonGlobal.battlingSpawnedPokemon = false if defined?($PokemonGlobal)
        pbResetTempAfterBattle() if defined?(pbResetTempAfterBattle)
      end
    rescue => e
      AnilLanRework.log("start_remote_poke_battle error #{e}")
      false
    end

    def handle_remote_poke_battle_request(packet)
      return unless AnilLanRework.host?
      return unless packet.is_a?(Hash)
      map_id = packet["map_id"].to_i
      event_id = packet["event_id"].to_i
      return if map_id <= 0 || event_id <= 0
      return unless $game_map && $game_map.map_id == map_id
      event = $game_map.events[event_id]
      return unless defined?(Game_PokeEvent) && event.is_a?(Game_PokeEvent)
      remove_remote_poke_event(event_id)
      send_snapshot_if_host
    rescue => e
      AnilLanRework.log("handle_remote_poke_battle_request error #{e}")
    end

    def apply_events(hash)
      return unless hash.is_a?(Hash)

      # Remover eventos dinâmicos (VOE) que não estão no snapshot do Host
      if defined?(Game_PokeEvent) && !AnilLanRework.host? && remote_spawn_authority_active?($game_map.map_id)
        $game_map.events.each do |id, event|
          if event.is_a?(Game_PokeEvent) && !hash.key?(id.to_s)
            $game_map.removeThisEventfromMap(id) rescue $game_map.events.delete(id)
          end
        end
      end

      hash.each do |event_id, state|
        id = event_id.to_i
        event = $game_map.events[id]

        if !state["is_poke"]
          next
        end

        # Criar Game_PokeEvent se faltar no Cliente
        if !event && state["is_poke"] && defined?(Game_PokeEvent) && !AnilLanRework.host?
          event = create_remote_poke_event(id, state)
        end

        next unless event && state.is_a?(Hash)
        if state["is_poke"] && remote_poke_event?(event) && state["pkmn"]
          event.pokemon = AnilLanRework::Serializer.deserialize_pokemon(state["pkmn"], event.pokemon) || event.pokemon
          sync_remote_poke_sprite(event)
        end

        already_synced = event.instance_variable_get(:@anil_remote_sync_initialized)
        event.instance_variable_set(:@anil_remote_sync, true)
        event.instance_variable_set(:@anil_remote_target_x, state["x"].to_i)
        event.instance_variable_set(:@anil_remote_target_y, state["y"].to_i)
        event.instance_variable_set(:@anil_remote_target_real_x, state["real_x"].to_i)
        event.instance_variable_set(:@anil_remote_target_real_y, state["real_y"].to_i)
        event.instance_variable_set(:@anil_remote_target_dir, state["dir"].to_i)
        event.instance_variable_set(:@anil_remote_target_pattern, state["pattern"].to_i)
        event.instance_variable_set(:@anil_remote_target_char, state["char"].to_s)
        event.instance_variable_set(:@anil_remote_target_page, state["page"].to_i) if state.key?("page")

        if state.key?("through")
          event.through = state["through"].to_i == 1
        end

        if state.key?("page") && event.instance_variable_get(:@page_index).to_i != state["page"].to_i
          $game_map.need_refresh = true rescue nil
        end

        unless already_synced
          event.instance_variable_set(:@x, state["x"].to_i)
          event.instance_variable_set(:@y, state["y"].to_i)
          event.instance_variable_set(:@real_x, state["real_x"].to_i)
          event.instance_variable_set(:@real_y, state["real_y"].to_i)
          event.direction = state["dir"].to_i
          event.pattern = state["pattern"].to_i
          event.character_name = state["char"].to_s
          event.calculate_bush_depth rescue nil
          event.instance_variable_set(:@anil_remote_sync_initialized, true)
        end

        event.instance_variable_set(:@wait_count, 0)
        event.instance_variable_set(:@stop_count, 0)
      end
    end

    def apply_event_motion(hash)
      return unless hash.is_a?(Hash)
      hash.each do |event_id, state|
        id = event_id.to_i
        event = $game_map.events[id]
        next unless event && state.is_a?(Hash)

        if !state["is_poke"]
          next
        end
        event.instance_variable_set(:@anil_remote_sync, true)
        event.instance_variable_set(:@anil_remote_target_x, state["x"].to_i)
        event.instance_variable_set(:@anil_remote_target_y, state["y"].to_i)
        event.instance_variable_set(:@anil_remote_target_real_x, state["real_x"].to_i)
        event.instance_variable_set(:@anil_remote_target_real_y, state["real_y"].to_i)
        event.instance_variable_set(:@anil_remote_target_dir, state["dir"].to_i)
        event.instance_variable_set(:@anil_remote_target_pattern, state["pattern"].to_i)
        event.instance_variable_set(:@anil_remote_target_char, state["char"].to_s)
        event.instance_variable_set(:@anil_remote_target_page, state["page"].to_i) if state.key?("page")
        event.through = state["through"].to_i == 1 if state.key?("through")
        if state.key?("page") && event.instance_variable_get(:@page_index).to_i != state["page"].to_i
          $game_map.need_refresh = true rescue nil
        end
        unless event.instance_variable_get(:@anil_remote_sync_initialized)
          event.instance_variable_set(:@x, state["x"].to_i)
          event.instance_variable_set(:@y, state["y"].to_i)
          event.instance_variable_set(:@real_x, state["real_x"].to_i)
          event.instance_variable_set(:@real_y, state["real_y"].to_i)
          event.direction = state["dir"].to_i
          event.pattern = state["pattern"].to_i
          event.character_name = state["char"].to_s
          event.calculate_bush_depth rescue nil
          event.instance_variable_set(:@anil_remote_sync_initialized, true)
        end
      end
    end

    def interpolate_event!(event)
      return unless event
      return unless event.instance_variable_get(:@anil_remote_sync)
      target_real_x = event.instance_variable_get(:@anil_remote_target_real_x)
      target_real_y = event.instance_variable_get(:@anil_remote_target_real_y)
      return if target_real_x.nil? || target_real_y.nil?

      real_res_x = (Game_Map::REAL_RES_X rescue 128)
      real_res_y = (Game_Map::REAL_RES_Y rescue 128)
      subpixels_x = (Game_Map::X_SUBPIXELS rescue 4)
      current_real_x = event.real_x.to_i
      current_real_y = event.real_y.to_i
      dx = target_real_x.to_i - current_real_x
      dy = target_real_y.to_i - current_real_y
      dist = [dx.abs, dy.abs].max

      event.direction = event.instance_variable_get(:@anil_remote_target_dir).to_i
      event.character_name = event.instance_variable_get(:@anil_remote_target_char).to_s

      # Anima a silhueta de caminhada de forma fluida na taxa de quadros (FPS) local,
      # em vez de travar no padrão de atualização de rede (que atualiza apenas a 10 FPS).
      if dist > 0
        est_speed = (dist / 6.0).ceil
        anime_speed = if est_speed >= 48
                        2.0  # Ciclismo
                      elsif est_speed >= 24
                        1.5  # Corrida
                      else
                        1.0  # Caminhada
                      end
        
        anime_count = event.instance_variable_get(:@anil_remote_anime_count) || 0.0
        anime_count += anime_speed
        
        threshold = if est_speed >= 48
                      144 # Ciclismo: 144 / 2.0 = 72 frames renderizados
                    elsif est_speed >= 24
                      108 # Corrida: 108 / 1.5 = 72 frames renderizados
                    else
                      120 # Caminhada: 120 / 1.0 = 120 frames renderizados
                    end
        
        if anime_count >= threshold
          event.pattern = (event.pattern + 1) % 4
          anime_count = 0.0
        end
        event.instance_variable_set(:@anil_remote_anime_count, anime_count)
      else
        event.pattern = event.instance_variable_get(:@anil_remote_target_pattern).to_i
        event.instance_variable_set(:@anil_remote_anime_count, 0.0)
      end

      return if dist == 0

      threshold_px = EVENT_TELEPORT_THRESHOLD * [real_res_x, real_res_y].max
      if dist > threshold_px
        event.instance_variable_set(:@real_x, target_real_x.to_i)
        event.instance_variable_set(:@real_y, target_real_y.to_i)
        event.instance_variable_set(:@x, target_real_x.to_i / real_res_x)
        event.instance_variable_set(:@y, target_real_y.to_i / real_res_y)
        event.instance_variable_set(:@anil_remote_smooth_x, target_real_x.to_i)
        event.instance_variable_set(:@anil_remote_smooth_y, target_real_y.to_i)
        event.calculate_bush_depth rescue nil
        return
      end

      # Suavização com velocidade dinâmica baseada na distância até o alvo.
      # EVENT_STREAM_TICK = 6 frames é o intervalo de tempo entre atualizações (100ms).
      # Dividindo dist por 6.0 calculamos a velocidade ideal para que o evento cubra
      # o trajeto exatamente a tempo da próxima atualização de rede chegar.
      speed = (dist / 6.0).ceil
      
      # Garantir velocidade múltipla de subpixels_x (alinhamento de pixel perfeito)
      speed = (speed.to_f / subpixels_x).round * subpixels_x
      
      # Garantir velocidade mínima de 16 subpixels (4 pixels) para evitar que o personagem pare perto demais do alvo,
      # e limitar à velocidade máxima de 64 subpixels (16 pixels) de corrida/ciclismo para evitar movimentos bruscos.
      speed = subpixels_x * 4 if speed < subpixels_x * 4 && dist > 0
      speed = subpixels_x * 16 if speed > subpixels_x * 16

      # Inicializa ou carrega as coordenadas de suavização
      smooth_x = event.instance_variable_get(:@anil_remote_smooth_x) || current_real_x
      smooth_y = event.instance_variable_get(:@anil_remote_smooth_y) || current_real_y

      # Garante alinhamento de pixel inicial
      smooth_x = (smooth_x.to_f / subpixels_x).round * subpixels_x
      smooth_y = (smooth_y.to_f / subpixels_x).round * subpixels_x

      # Corrige eventuais grandes desvios entre smooth_x/y e a posição real atual do evento
      if (smooth_x - current_real_x).abs > 64
        smooth_x = (current_real_x.to_f / subpixels_x).round * subpixels_x
      end
      if (smooth_y - current_real_y).abs > 64
        smooth_y = (current_real_y.to_f / subpixels_x).round * subpixels_x
      end

      # Move a posição suavizada em direção à posição alvo (target)
      dx_smooth = target_real_x.to_i - smooth_x
      dy_smooth = target_real_y.to_i - smooth_y

      if dx_smooth.abs <= speed
        smooth_x = target_real_x.to_i
      else
        smooth_x += speed * (dx_smooth > 0 ? 1 : -1)
      end

      if dy_smooth.abs <= speed
        smooth_y = target_real_y.to_i
      else
        smooth_y += speed * (dy_smooth > 0 ? 1 : -1)
      end

      event.instance_variable_set(:@anil_remote_smooth_x, smooth_x)
      event.instance_variable_set(:@anil_remote_smooth_y, smooth_y)

      # Aplica as coordenadas calculadas no evento
      event.instance_variable_set(:@real_x, smooth_x)
      event.instance_variable_set(:@real_y, smooth_y)
      event.instance_variable_set(:@x, smooth_x / real_res_x)
      event.instance_variable_set(:@y, smooth_y / real_res_y)
      event.calculate_bush_depth rescue nil
    rescue => e
      AnilLanRework.log("interpolate_event error #{e.class}: #{e.message}")
    end

    def authoritative_for?(map_id)
      !AnilLanRework.host? && @authoritative_map_id.to_i == map_id.to_i
    end

    def host_reported_same_map_recent?(map_id, max_age_frames = 180)
      return false if AnilLanRework.host?
      return false if map_id.to_i <= 0
      return false unless @host_reported_map_id.to_i == map_id.to_i
      current_frame = Graphics.frame_count rescue 0
      (current_frame - @host_reported_map_frame.to_i) <= max_age_frames.to_i
    rescue
      false
    end

    def authoritative_host_peer
      host_id = AnilLanRework.connection&.host_id.to_s
      return nil if host_id.empty?
      AnilLanRework.players[host_id]
    rescue
      nil
    end

    def remote_spawn_authority_active?(map_id)
      current_frame = Graphics.frame_count
      if @spawn_authority_cache_frame == current_frame
        return @spawn_authority_cache.fetch(map_id.to_i, false)
      end
      @spawn_authority_cache = {}
      @spawn_authority_cache_frame = current_frame
      return false unless authoritative_for?(map_id)
      peer = authoritative_host_peer
      return false unless peer
      return false unless peer.map_id.to_i == map_id.to_i
      dx = (peer.x.to_i - $game_player.x.to_i).abs
      dy = (peer.y.to_i - $game_player.y.to_i).abs
      result = [dx, dy].max <= AnilLanRework::REMOTE_SPAWN_AUTHORITY_DISTANCE
      @spawn_authority_cache[map_id.to_i] = result
      result
    rescue
      false
    end

    def input_locked?
      return true if defined?(AnilLanRework::BattleSync) &&
                     (AnilLanRework::BattleSync.waiting_for_coop_start? rescue false)
      false
    end

    def hide_peer_sprite?(peer)
      false
    end
  end
end

# --- [REMOVIDO] Bloco de codigo (linhas 3619 a 8256) movido para 000d_Multiplayer_Battle_Trade_RNG_Sync.rb ---

module AnilLanRework
  module MailboxSync
    @worker = nil
    @boot_attempted = false

    class << self
      attr_accessor :worker
      attr_accessor :boot_attempted
    end

    module_function

    def player_config_path
      if defined?(Scene_MultiplayerLobby_Rework::PLAYER_CFG)
        Scene_MultiplayerLobby_Rework::PLAYER_CFG
      else
        "multiplayer_player.txt"
      end
    end

    def read_cfg_value(file, key)
      return "" unless File.exist?(file)
      File.readlines(file, encoding: "UTF-8").each do |line|
        parts = line.strip.split("=", 2)
        return parts[1].to_s.strip if parts.size == 2 && parts[0].to_s.strip == key.to_s
      end
      ""
    rescue
      ""
    end

    def current_player_internal_id
      raw_id = read_cfg_value(player_config_path, "id")
      return "" if raw_id.empty?
      AnilLanRework.resolve_internal_id(raw_id)
    rescue
      ""
    end

    def apply_results(results)
      total = 0
      Array(results).each do |row|
        next unless row.is_a?(Hash)
        amount = row["amount"].to_i
        next if amount <= 0
        $player.money += amount
        total += amount
        host_name = row["host_name"].to_s
        host_name = row["last_ip"].to_s if host_name.empty?
        AnilLanRework::PlayerMarket.pending_messages << AnilLanRework.ui_format(
          "Recebeste ${1} da sessao guardada {2}.",
          amount,
          host_name
        )
      end
      AnilLanRework::PlayerMarket.save_game if total > 0
      total
    rescue => e
      AnilLanRework.log("mailbox apply results error #{e.class}: #{e.message}")
      0
    end

    def start_background_sync(force: false)
      return if AnilLanRework.connected?
      return if @worker&.alive?
      return if @boot_attempted && !force
      player_id = current_player_internal_id
      sessions = AnilLanRework::RememberedSessions.load_entries
      @boot_attempted = true
      return if player_id.empty? || sessions.empty?
      @worker = Thread.new(player_id, sessions) do |resolved_id, entries|
        results = []
        entries.each do |entry|
          packet = AnilLanRework::RememberedSessions.pull_saved_payout(entry, resolved_id)
          next unless packet.is_a?(Hash) && packet["ok"] == true
          amount = packet["amount"].to_i
          next if amount <= 0
          results << {
            "host_id"   => entry["host_id"].to_s,
            "host_name" => packet["host_name"].to_s.empty? ? entry["host_name"].to_s : packet["host_name"].to_s,
            "last_ip"   => entry["last_ip"].to_s,
            "amount"    => amount
          }
        end
        results
      end
    rescue => e
      AnilLanRework.log("mailbox background sync error #{e.class}: #{e.message}")
    end

    def update
      start_background_sync if !@boot_attempted && $scene.is_a?(Scene_Map) && !$game_temp&.in_battle
      return unless @worker
      return if @worker.alive?
      results = @worker.value rescue []
      @worker = nil
      apply_results(results)
    rescue => e
      AnilLanRework.log("mailbox update error #{e.class}: #{e.message}")
      @worker = nil
    end
  end
end

# --- [REMOVIDO] Bloco de codigo (linhas 8362 a 8606) movido para 000d_Multiplayer_Battle_Trade_RNG_Sync.rb ---

module AnilLanRework
  module ItemSync
    @pending_offer_results  = {}
    @pending_incoming_gifts = {}
    @pending_messages       = []

    class << self
      attr_accessor :pending_offer_results
      attr_accessor :pending_incoming_gifts
      attr_accessor :pending_messages
    end

    module_function

    def ensure_scene_ready?
      $scene.is_a?(Scene_Map) && !($game_temp&.message_window_showing) && !(pbMapInterpreterRunning? rescue false)
    end

    def peer_available?(peer)
      return false unless peer.is_a?(AnilLanRework::RemotePeer)
      return false unless AnilLanRework.connected?
      return false if peer.internal_id.to_s.empty?
      peer.map_id.to_i == $game_map.map_id.to_i
    rescue
      false
    end

    def peer_display_name(peer)
      return "" unless peer
      name = peer.name.to_s
      return name unless name.empty?
      peer.internal_id.to_s
    rescue
      ""
    end

    def build_gift_id
      "#{AnilLanRework.self_internal_id}-#{Graphics.frame_count}-#{rand(1_000_000)}"
    end

    def open_bag_for_peer(peer)
      if !peer_available?(peer)
        pbMessage(_INTL("O parceiro nao esta disponivel para receber itens agora.")) rescue nil
        return
      end
      pbFadeOutIn do
        scene = PokemonBag_Scene.new
        screen = PokemonBagScreen.new(scene, $bag, peer)
        screen.pbStartScreen
      end
    rescue => e
      AnilLanRework.log("open_bag_for_peer error #{e.class}: #{e.message}")
      pbMessage(_INTL("Nao foi possivel abrir a Mochila para envio.")) rescue nil
    end

    def send_item(peer, item, quantity)
      return [false, _INTL("O parceiro nao esta disponivel para receber itens agora.")] if !peer_available?(peer)
      item_data = GameData::Item.try_get(item)
      return [false, _INTL("Item invalido.")] if !item_data
      qty = quantity.to_i
      return [false, _INTL("Quantidade invalida.")] if qty <= 0
      return [false, _INTL("Nao ha itens suficientes na Mochila.")] if !$bag.can_remove?(item_data.id, qty)

      gift_id = build_gift_id
      AnilLanRework.connection.send_packet("coop_item_offer",
        "to_id"    => peer.internal_id,
        "gift_id"  => gift_id,
        "item"     => item_data.id.to_s,
        "quantity" => qty
      )

      result = wait_for_offer_result(gift_id)
      return [false, _INTL("O envio falhou por tempo limite.")] if !result

      case result["status"].to_s
      when "accepted"
        if !$bag.remove_all(item_data.id, qty)
          AnilLanRework.connection.send_packet("coop_item_cancel",
            "to_id"   => peer.internal_id,
            "gift_id" => gift_id,
            "reason"  => "missing_item"
          )
          return [false, _INTL("Os itens nao estavam mais disponiveis na Mochila.")]
        end
        AnilLanRework.connection.send_packet("coop_item_commit",
          "to_id"    => peer.internal_id,
          "gift_id"  => gift_id,
          "item"     => item_data.id.to_s,
          "quantity" => qty
        )
        item_name = (qty > 1) ? item_data.portion_name_plural : item_data.portion_name
        return [true, AnilLanRework.ui_format("Enviou {1} {2} para {3}.", qty, item_name, peer_display_name(peer))]
      when "bag_full"
        return [false, AnilLanRework.ui_format("{1} nao tem espaco suficiente na Mochila.", peer_display_name(peer))]
      when "invalid_item"
        return [false, _INTL("O outro jogador nao conseguiu validar esse item.")]
      when "unavailable"
        return [false, _INTL("O parceiro nao esta disponivel para receber itens agora.")]
      else
        return [false, result["message"].to_s.empty? ? _INTL("Nao foi possivel enviar o item.") : result["message"].to_s]
      end
    rescue => e
      AnilLanRework.log("send_item error #{e.class}: #{e.message}")
      [false, _INTL("Erro ao enviar item.")]
    end

    def wait_for_offer_result(gift_id)
      started = Time.now.to_f
      loop do
        packet = @pending_offer_results.delete(gift_id.to_s)
        return packet if packet
        return nil unless AnilLanRework.connected?
        return nil if Time.now.to_f - started >= AnilLanRework::TURN_TIMEOUT
        AnilLanRework::Router.tick
        Graphics.update rescue nil
        Input.update rescue nil
      end
    end

    def on_packet(packet)
      case packet["type"]
      when "coop_item_offer"
        receive_offer(packet)
      when "coop_item_offer_result"
        receive_offer_result(packet)
      when "coop_item_commit"
        receive_commit(packet)
      when "coop_item_cancel"
        receive_cancel(packet)
      end
    end

    def receive_offer(packet)
      sender_id = packet["sender_id"].to_s
      gift_id   = packet["gift_id"].to_s
      item_data = GameData::Item.try_get(packet["item"])
      qty       = packet["quantity"].to_i

      status = if gift_id.empty? || !item_data || qty <= 0
        "invalid_item"
      elsif !$bag.can_add?(item_data.id, qty)
        "bag_full"
      else
        @pending_incoming_gifts[gift_id] = {
          "sender_id" => sender_id,
          "item"      => item_data.id.to_s,
          "quantity"  => qty
        }
        "accepted"
      end

      AnilLanRework.connection.send_packet("coop_item_offer_result",
        "to_id"   => sender_id,
        "gift_id" => gift_id,
        "status"  => status
      )
    rescue => e
      AnilLanRework.log("receive_offer error #{e.class}: #{e.message}")
      if sender_id && !sender_id.empty?
        AnilLanRework.connection.send_packet("coop_item_offer_result",
          "to_id"   => sender_id,
          "gift_id" => gift_id.to_s,
          "status"  => "invalid_item"
        ) rescue nil
      end
    end

    def receive_offer_result(packet)
      gift_id = packet["gift_id"].to_s
      return if gift_id.empty?
      @pending_offer_results[gift_id] = packet
    end

    def receive_commit(packet)
      gift_id = packet["gift_id"].to_s
      cached  = @pending_incoming_gifts.delete(gift_id) || {}
      sender_id = (cached["sender_id"] || packet["sender_id"]).to_s
      item_data = GameData::Item.try_get(cached["item"] || packet["item"])
      qty       = (cached["quantity"] || packet["quantity"]).to_i
      return unless item_data && qty > 0

      if $bag.add(item_data.id, qty)
        peer = AnilLanRework.players[sender_id]
        sender_name = peer_display_name(peer)
        sender_name = sender_id if sender_name.empty?
        item_name = (qty > 1) ? item_data.portion_name_plural : item_data.portion_name
        @pending_messages << AnilLanRework.ui_format("{1} enviou {2} {3} para voce.", sender_name, qty, item_name)
      else
        @pending_messages << _INTL("Nao foi possivel receber o item enviado.")
      end
    rescue => e
      AnilLanRework.log("receive_commit error #{e.class}: #{e.message}")
    end

    def receive_cancel(packet)
      @pending_incoming_gifts.delete(packet["gift_id"].to_s)
    end

    def update_pending
      return unless ensure_scene_ready?
      message = @pending_messages.shift
      pbMessage(message) if message && !message.to_s.empty?
    rescue => e
      AnilLanRework.log("item_sync update_pending error #{e.class}: #{e.message}")
    end
  end
end

class PokemonGlobalMetadata
  attr_accessor :online_market_pokemon
  attr_accessor :online_market_items
  attr_accessor :online_market_payouts
  attr_accessor :online_market_next_listing_id
  # IDs de devolucao do mercado ja processados. Vive no save de proposito: e o
  # que impede um Pokemon devolvido de entrar duas vezes se o ACK se perder e o
  # servidor reenviar. Sem accessor aqui, o dedupe falharia em silencio.
  attr_accessor :anil_devolucoes_recebidas

  alias anil_market_initialize initialize unless method_defined?(:anil_market_initialize) || private_method_defined?(:anil_market_initialize)
  def initialize
    anil_market_initialize
    @online_market_pokemon ||= []
    @online_market_items ||= []
    @online_market_payouts ||= {}
    @online_market_next_listing_id ||= 1
  end
end

module AnilLanRework
  module PlayerMarket
    @pending_results  = {}
    @pending_messages = []

    class << self
      attr_accessor :pending_results
      attr_accessor :pending_messages
    end

    module_function

    def ensure_market_metadata
      return unless defined?($PokemonGlobal) && $PokemonGlobal
      $PokemonGlobal.online_market_pokemon ||= []
      $PokemonGlobal.online_market_items ||= []
      $PokemonGlobal.online_market_payouts ||= {}
      $PokemonGlobal.online_market_next_listing_id ||= 1
    end

    def market_ready?
      AnilLanRework.enabled? && AnilLanRework.connected?
    end

    def host_market_id
      if defined?(AnilLanRework) && AnilLanRework.respond_to?(:multiplayer_mode) && AnilLanRework.multiplayer_mode
        return "server"
      end
      return AnilLanRework.self_internal_id if AnilLanRework.host?
      id = AnilLanRework.connection&.host_id.to_s
      return "server" if id.empty? && AnilLanRework.connected?
      id
    rescue
      ""
    end

    def build_request_id
      "market-#{AnilLanRework.self_internal_id}-#{Graphics.frame_count}-#{rand(1_000_000)}"
    end

    def next_listing_id
      ensure_market_metadata
      listing_id = $PokemonGlobal.online_market_next_listing_id.to_i
      listing_id = 1 if listing_id <= 0
      $PokemonGlobal.online_market_next_listing_id = listing_id + 1
      listing_id
    end

    def host_pokemon_listings
      ensure_market_metadata
      $PokemonGlobal.online_market_pokemon
    end

    def host_item_listings
      ensure_market_metadata
      $PokemonGlobal.online_market_items
    end

    def save_game
      if defined?(Game) && Game.respond_to?(:save)
        Game.save
      elsif defined?(SaveData) && SaveData.respond_to?(:save_to_file)
        SaveData.save_to_file(SaveData::FILE_PATH)
      end
    rescue => e
      AnilLanRework.log("player market save error #{e.class}: #{e.message}")
    end

    def pending_payout_amount_for(seller_id)
      ensure_market_metadata
      key = seller_id.to_s
      return 0 if key.empty?
      $PokemonGlobal.online_market_payouts[key].to_i
    rescue
      0
    end

    def host_pull_payout_for(seller_id)
      ensure_market_metadata
      key = seller_id.to_s
      return 0 if key.empty?
      amount = $PokemonGlobal.online_market_payouts[key].to_i
      return 0 if amount <= 0
      $PokemonGlobal.online_market_payouts.delete(key)
      save_game
      amount
    rescue => e
      AnilLanRework.log("host_pull_payout_for error #{e.class}: #{e.message}")
      0
    end

    def receive_listing_label(listing)
      species_name = pokemon_listing_species_name(listing)
      level = listing.dig("pokemon", "level").to_i
      AnilLanRework.ui_format("{1} Nv.{2}", species_name, level)
    end

    def item_listing_label(listing)
      item_data = GameData::Item.try_get(listing["item"])
      item_name = item_data ? item_data.name.to_s : listing["item"].to_s
      qty = listing["quantity"].to_i
      return item_name if qty <= 1
      AnilLanRework.ui_format("{1} x{2}", item_name, qty)
    end

    def listing_pokemon(listing)
      @listing_pokemon_cache ||= {}
      cache_key = listing["listing_id"] || listing.object_id
      return @listing_pokemon_cache[cache_key] if @listing_pokemon_cache.key?(cache_key)
      @listing_pokemon_cache[cache_key] = AnilLanRework::Serializer.deserialize_pokemon(listing["pokemon"])
    rescue
      nil
    end

    def pokemon_listing_species_name(listing)
      pkmn = listing_pokemon(listing)
      return pkmn.speciesName.to_s if pkmn
      blob = listing["pokemon"]
      species = blob && blob["species"]
      return GameData::Species.get(species).name.to_s if species
      _INTL("Pokemon")
    rescue
      _INTL("Pokemon")
    end

    def pokemon_listing_display_name(listing)
      pkmn = listing_pokemon(listing)
      species_name = pokemon_listing_species_name(listing)
      level = pkmn ? pkmn.level.to_i : listing.dig("pokemon", "level").to_i
      return species_name if level <= 0
      AnilLanRework.ui_format("{1} Nv.{2}", species_name, level)
    end

    def pokemon_listing_purchase_name(listing)
      pkmn = listing_pokemon(listing)
      return pkmn.name.to_s if pkmn && !pkmn.name.to_s.empty?
      pokemon_listing_species_name(listing)
    end

    def pokemon_listing_description(listing)
      pkmn = listing_pokemon(listing)
      return _INTL("Nao foi possivel carregar os dados deste Pokemon.") unless pkmn
      species_name = pkmn.speciesName.to_s
      title = (pkmn.name.to_s.empty? || pkmn.name.to_s == species_name) ? species_name : _INTL("{1} ({2})", pkmn.name, species_name)
      nature_name = pkmn.nature ? pkmn.nature.name.to_s : _INTL("Desconhecida")
      ability_name = pkmn.ability ? pkmn.ability.name.to_s : _INTL("Desconhecida")
      item_name = pkmn.item ? pkmn.item.name.to_s : _INTL("Nenhum")
      AnilLanRework.ui_format("{1}\nNv.{2} / {3}\nHab.: {4}\nObjeto: {5}",
        title, pkmn.level.to_i, nature_name, ability_name, item_name
      )
    rescue
      _INTL("Nao foi possivel carregar os dados deste Pokemon.")
    end

    def item_listing_data(listing)
      GameData::Item.try_get(listing["item"])
    rescue
      nil
    end

    def item_listing_id(listing)
      item_data = item_listing_data(listing)
      item_data ? item_data.id : nil
    end

    # Teto do anuncio no mercado. Era 999_999. O servidor nunca teve teto
    # (persistent_store so recusa price <= 0), entao o limite era so este, e
    # MAX_MONEY e 999_999_999 — 99 milhoes cabe sem encostar no teto de dinheiro.
    def choose_price(message, max_value = 99_900_000)
      params = ChooseNumberParams.new
      params.setRange(1, max_value)
      params.setDefaultValue([1_000, max_value].min)
      pbMessageChooseNumber(message, params)
    rescue
      0
    end

    def wait_for_result(request_id)
      started = Time.now.to_f
      loop do
        packet = @pending_results.delete(request_id.to_s)
        return packet if packet
        return nil unless AnilLanRework.connected?
        return nil if Time.now.to_f - started >= AnilLanRework::TURN_TIMEOUT
        AnilLanRework::Router.tick
        Graphics.update rescue nil
        Input.update rescue nil
      end
    end

    def queue_result(packet)
      request_id = packet["request_id"].to_s
      return if request_id.empty?
      @pending_results[request_id] = packet
    end

    # Sem `box` devolve tudo (como sempre fez). Com `box`, devolve so aquela
    # pagina e o total — e o que permite a loja abrir sem descarregar as 17
    # caixas.
    def fetch_listings(kind, box = nil)
      kind = kind.to_s
      if AnilLanRework.host?
        todas = Marshal.load(Marshal.dump(kind == "pokemon" ? host_pokemon_listings : host_item_listings))
        return todas if box.nil?
        ini = box.to_i * PokemonBox::BOX_SIZE
        return { "listings" => (todas[ini, PokemonBox::BOX_SIZE] || []),
                 "total" => todas.length, "box" => box.to_i }
      end
      request_id = build_request_id
      host_id = host_market_id
      return (box.nil? ? [] : nil) if host_id.empty?
      pedido = {
        "to_id"       => host_id,
        "request_id"  => request_id,
        "market_kind" => kind
      }
      pedido["box"] = box.to_i unless box.nil?
      AnilLanRework.connection.send_packet("market_request_listings", pedido)
      result = wait_for_result(request_id)
      if box.nil?
        return [] unless result.is_a?(Hash)
        return Array(result["listings"])
      end
      # nil (e nao []) quando falha: o chamador precisa de distinguir "caixa
      # vazia" de "nao consegui buscar", senao marcava a pagina como carregada e
      # o jogador ficava com uma caixa vazia para sempre.
      return nil unless result.is_a?(Hash)
      # Servidor antigo: nao sabe paginar e mandou tudo. Fatia-se aqui.
      unless result.key?("total")
        todas = Array(result["listings"])
        ini = box.to_i * PokemonBox::BOX_SIZE
        return { "listings" => (todas[ini, PokemonBox::BOX_SIZE] || []),
                 "total" => todas.length, "box" => box.to_i }
      end
      { "listings" => Array(result["listings"]),
        "total"    => result["total"].to_i,
        "box"      => result["box"].to_i }
    rescue => e
      AnilLanRework.log("fetch_listings error #{e.class}: #{e.message}")
      []
    end

    def can_receive_pokemon?
      return false unless defined?($PokemonStorage) && $PokemonStorage
      return true if $PokemonStorage.respond_to?(:pbFindBoxWithSpace) && $PokemonStorage.pbFindBoxWithSpace >= 0
      return true if $PokemonStorage.respond_to?(:maxBoxes) && $PokemonStorage.respond_to?(:pbFirstFreePos) &&
                     (0...$PokemonStorage.maxBoxes).any? { |box| $PokemonStorage.pbFirstFreePos(box) >= 0 }
      false
    rescue
      false
    end

    def store_pokemon_locally(blob)
      return [false, _INTL("Nao ha espaco livre no PC.")] unless can_receive_pokemon?
      pkmn = AnilLanRework::Serializer.deserialize_pokemon(blob)
      return [false, _INTL("Nao foi possivel restaurar o Pokemon comprado.")] unless pkmn
      # MARCA DE COMPRA — para o resumo poder dizer "Comprado" em vez de
      # "Trocado". Carimba-se aqui, no unico ponto por onde um Pokemon comprado
      # entra no jogo, e nao no obtain_method: gastar um valor novo (o 3 esta
      # livre) obrigaria a mexer na tabela de frases do plugin 041, que e inline
      # dentro de um metodo de 200 linhas. Assim o obtain_method continua 2
      # ("trocado"), que e verdade e nao quebra nada, e a distincao fica neste
      # campo proprio.
      pkmn.instance_variable_set(:@anil_comprado_em, Time.now.to_i) rescue nil
      box = $PokemonStorage.pbStoreCaught(pkmn)
      return [false, _INTL("Nao ha espaco livre no PC.")] if box.nil? || box.to_i < 0
      [true, AnilLanRework.ui_format("{1} foi enviado para a Caixa {2}.", pkmn.name, box.to_i + 1)]
    rescue => e
      AnilLanRework.log("store_pokemon_locally error #{e.class}: #{e.message}")
      [false, _INTL("Falha ao guardar o Pokemon comprado.")]
    end

    def publish_pokemon(blob, price)
      return [false, _INTL("Mercado indisponivel.")] unless market_ready?
      request_id = build_request_id
      listing = {
        "seller_id"   => AnilLanRework.self_internal_id,
        "seller_name" => AnilLanRework.self_name,
        "price"       => price.to_i,
        "pokemon"     => blob
      }
      if AnilLanRework.host?
        result = host_publish_pokemon(listing)
        return [result["ok"] == true, result["message"].to_s]
      end
      host_id = host_market_id
      return [false, _INTL("Host do mercado indisponivel.")] if host_id.empty?
      AnilLanRework.connection.send_packet("market_publish_pokemon",
        "to_id"      => host_id,
        "request_id" => request_id,
        "listing"    => listing
      )
      result = wait_for_result(request_id)
      return [false, _INTL("Tempo limite ao publicar Pokemon.")] unless result
      [result["ok"] == true, result["message"].to_s]
    end

    def publish_item(item, quantity, price)
      return [false, _INTL("Mercado indisponivel.")] unless market_ready?
      item_data = GameData::Item.try_get(item)
      qty = quantity.to_i
      return [false, _INTL("Item invalido.")] unless item_data
      return [false, _INTL("Quantidade invalida.")] if qty <= 0
      request_id = build_request_id
      listing = {
        "seller_id"   => AnilLanRework.self_internal_id,
        "seller_name" => AnilLanRework.self_name,
        "item"        => item_data.id.to_s,
        "quantity"    => qty,
        "price"       => price.to_i
      }
      if AnilLanRework.host?
        result = host_publish_item(listing)
        return [result["ok"] == true, result["message"].to_s]
      end
      host_id = host_market_id
      return [false, _INTL("Host do mercado indisponivel.")] if host_id.empty?
      AnilLanRework.connection.send_packet("market_publish_item",
        "to_id"      => host_id,
        "request_id" => request_id,
        "listing"    => listing
      )
      result = wait_for_result(request_id)
      return [false, _INTL("Tempo limite ao publicar item.")] unless result
      [result["ok"] == true, result["message"].to_s]
    end

    def purchase_pokemon_listing(listing)
      return [false, _INTL("Nao ha espaco livre no PC.")] unless can_receive_pokemon?
      price = listing["price"].to_i
      return [false, _INTL("Dinheiro insuficiente.")] if $player.money.to_i < price
      request_id = build_request_id
      if AnilLanRework.host?
        result = host_purchase_pokemon(listing["listing_id"], AnilLanRework.self_internal_id)
      else
        host_id = host_market_id
        return [false, _INTL("Host do mercado indisponivel.")] if host_id.empty?
        AnilLanRework.connection.send_packet("market_purchase_pokemon",
          "to_id"      => host_id,
          "request_id" => request_id,
          "listing_id" => listing["listing_id"].to_i
        )
        result = wait_for_result(request_id)
      end
      return [false, _INTL("A compra falhou por tempo limite.")] unless result
      return [false, result["message"].to_s] unless result["ok"] == true
      stored, message = store_pokemon_locally(result["pokemon"])
      return [false, message] unless stored
      $player.money -= result["price"].to_i
      save_game
      [true, message]
    rescue => e
      AnilLanRework.log("purchase_pokemon_listing error #{e.class}: #{e.message}")
      [false, _INTL("Falha ao comprar Pokemon.")]
    end

    # ⚠️ O ANUNCIO E MEU?
    #
    # O `seller_id` vem em dois formatos conforme o caminho que trouxe a
    # listagem: solto no topo, ou dentro de um `seller` com `id` e `name`.
    # Aceitam-se os dois; olhar so para um deixava o menu de dono a nao
    # aparecer, sem erro nenhum e sem forma de perceber porque.
    def own_listing?(listing)
      return false unless listing.is_a?(Hash)
      meu = AnilLanRework.self_internal_id.to_s.strip.downcase
      return false if meu.empty?
      vendedor = listing["seller_id"]
      vendedor = listing["seller"]["id"] if vendedor.nil? && listing["seller"].is_a?(Hash)
      vendedor = vendedor.to_s.strip.downcase
      !vendedor.empty? && vendedor == meu
    end

    # O mercado do servidor e o unico que sabe retirar e reprecificar. No modo
    # LAN antigo (um jogador a fazer de host) essas operacoes nao existem, e
    # dizer isso e melhor do que falhar em silencio.
    def mercado_do_servidor?
      (AnilLanRework.respond_to?(:multiplayer_mode) && AnilLanRework.multiplayer_mode) ? true : false
    rescue
      false
    end

    # ⚠️ VOLTA SEM A MARCA DE COMPRADO.
    #
    # O `store_pokemon_locally` carimba `@anil_comprado_em`, para o resumo dizer
    # "Comprado". Aqui e o proprio dono a receber de volta o que ja era dele:
    # carimba-lo seria rebaixar-lhe o Pokemon por ele ter mudado de ideias.
    def guardar_de_volta(blob)
      return [false, _INTL("Não há espaço livre no PC.")] unless can_receive_pokemon?
      pkmn = AnilLanRework::Serializer.deserialize_pokemon(blob)
      return [false, _INTL("Não foi possível restaurar o Pokémon.")] unless pkmn
      box = $PokemonStorage.pbStoreCaught(pkmn)
      return [false, _INTL("Não há espaço livre no PC.")] if box.nil? || box.to_i < 0
      [true, AnilLanRework.ui_format("{1} voltou para a Caixa {2}.", pkmn.name, box.to_i + 1)]
    rescue => e
      AnilLanRework.log("guardar_de_volta error #{e.class}: #{e.message}")
      [false, _INTL("Falha ao guardar o Pokémon.")]
    end

    def cancel_pokemon_listing(listing)
      return [false, _INTL("Isso só funciona no servidor.")] unless mercado_do_servidor?
      return [false, _INTL("Não há espaço livre no PC.")] unless can_receive_pokemon?
      request_id = build_request_id
      AnilLanRework.connection.send_packet("market_cancel_pokemon",
        "to_id"      => "server",
        "request_id" => request_id,
        "listing_id" => listing["listing_id"].to_i
      )
      result = wait_for_result(request_id)
      return [false, _INTL("O servidor não respondeu a tempo.")] unless result
      return [false, result["message"].to_s] unless result["ok"] == true
      guardado, mensagem = guardar_de_volta(result["pokemon"])
      # ⚠️ SE FALHAR AQUI, O POKEMON JA SAIU DO MERCADO.
      #
      # O anuncio foi apagado no servidor antes de este cliente o guardar. Nao
      # se pode fingir que nao aconteceu: grava-se na mesma o que houver e
      # avisa-se, porque perder o bicho em silencio e o pior desfecho possivel.
      unless guardado
        AnilLanRework.log("cancel_pokemon_listing: anuncio removido mas NAO guardado: #{mensagem}")
        return [false, mensagem.to_s + " " + _INTL("O anúncio já foi retirado — libere espaço e fale com um administrador.")]
      end
      save_game
      [true, mensagem]
    rescue => e
      AnilLanRework.log("cancel_pokemon_listing error #{e.class}: #{e.message}")
      [false, _INTL("Falha ao retirar o Pokémon.")]
    end

    def update_pokemon_listing_price(listing, novo_preco)
      return [false, _INTL("Isso só funciona no servidor.")] unless mercado_do_servidor?
      preco = novo_preco.to_i
      return [false, _INTL("Preço inválido.")] if preco <= 0
      request_id = build_request_id
      AnilLanRework.connection.send_packet("market_update_price_pokemon",
        "to_id"      => "server",
        "request_id" => request_id,
        "listing_id" => listing["listing_id"].to_i,
        "price"      => preco
      )
      result = wait_for_result(request_id)
      return [false, _INTL("O servidor não respondeu a tempo.")] unless result
      return [false, result["message"].to_s] unless result["ok"] == true
      [true, AnilLanRework.ui_format("Novo preço: {1} moedas.", result["price"].to_i.to_s_formatted)]
    rescue => e
      AnilLanRework.log("update_pokemon_listing_price error #{e.class}: #{e.message}")
      [false, _INTL("Falha ao mudar o preço.")]
    end

    def purchase_item_listing(listing)
      item_data = GameData::Item.try_get(listing["item"])
      return [false, _INTL("Item invalido.")] unless item_data
      return [false, _INTL("Dinheiro insuficiente.")] if $player.money.to_i < listing["price"].to_i
      return [false, _INTL("Sem espaco na Mochila.")] unless $bag.can_add?(item_data.id, listing["quantity"].to_i)
      request_id = build_request_id
      if AnilLanRework.host?
        result = host_purchase_item(listing["listing_id"], AnilLanRework.self_internal_id)
      else
        host_id = host_market_id
        return [false, _INTL("Host do mercado indisponivel.")] if host_id.empty?
        AnilLanRework.connection.send_packet("market_purchase_item",
          "to_id"      => host_id,
          "request_id" => request_id,
          "listing_id" => listing["listing_id"].to_i
        )
        result = wait_for_result(request_id)
      end
      return [false, _INTL("A compra falhou por tempo limite.")] unless result
      return [false, result["message"].to_s] unless result["ok"] == true
      qty = result["quantity"].to_i
      $bag.add(item_data.id, qty)
      $player.money -= result["price"].to_i
      save_game
      item_name = qty > 1 ? item_data.portion_name_plural : item_data.portion_name
      [true, AnilLanRework.ui_format("Comprou {1} {2}.", qty, item_name)]
    rescue => e
      AnilLanRework.log("purchase_item_listing error #{e.class}: #{e.message}")
      [false, _INTL("Falha ao comprar item.")]
    end

    def host_publish_pokemon(listing)
      ensure_market_metadata
      price = listing["price"].to_i
      return { "ok" => false, "message" => _INTL("Preco invalido.") } if price <= 0
      blob = listing["pokemon"]
      return { "ok" => false, "message" => _INTL("Pokemon invalido.") } unless blob.is_a?(Hash)
      host_pokemon_listings << listing.merge("listing_id" => next_listing_id, "created_at" => Time.now.to_i)
      save_game
      { "ok" => true, "message" => _INTL("Pokemon colocado a venda no mercado online.") }
    end

    def host_publish_item(listing)
      ensure_market_metadata
      item_data = GameData::Item.try_get(listing["item"])
      qty = listing["quantity"].to_i
      price = listing["price"].to_i
      return { "ok" => false, "message" => _INTL("Item invalido.") } unless item_data
      return { "ok" => false, "message" => _INTL("Quantidade invalida.") } if qty <= 0
      return { "ok" => false, "message" => _INTL("Preco invalido.") } if price <= 0
      host_item_listings << listing.merge("listing_id" => next_listing_id, "created_at" => Time.now.to_i)
      save_game
      { "ok" => true, "message" => _INTL("Item colocado a venda no mercado online.") }
    end

    def credit_sale_to_seller(seller_id, amount)
      ensure_market_metadata
      seller_key = seller_id.to_s
      return if seller_key.empty? || amount.to_i <= 0
      if seller_key == AnilLanRework.self_internal_id
        $player.money += amount.to_i
        @pending_messages << AnilLanRework.ui_format("Recebeu ${1} por uma venda online.", amount.to_i)
      else
        current = $PokemonGlobal.online_market_payouts[seller_key].to_i
        $PokemonGlobal.online_market_payouts[seller_key] = current + amount.to_i
      end
      save_game
      flush_pending_payouts_for_online_players
    end

    def host_purchase_pokemon(listing_id, buyer_id)
      ensure_market_metadata
      idx = host_pokemon_listings.index { |entry| entry["listing_id"].to_i == listing_id.to_i }
      return { "ok" => false, "message" => _INTL("Essa oferta nao esta mais disponivel.") } if idx.nil?
      listing = host_pokemon_listings[idx]
      return { "ok" => false, "message" => _INTL("Nao podes comprar o teu proprio Pokemon.") } if listing["seller_id"].to_s == buyer_id.to_s
      host_pokemon_listings.delete_at(idx)
      credit_sale_to_seller(listing["seller_id"], listing["price"].to_i)
      save_game
      {
        "ok"      => true,
        "message" => _INTL("Compra concluida."),
        "price"   => listing["price"].to_i,
        "pokemon" => listing["pokemon"]
      }
    end

    def host_purchase_item(listing_id, buyer_id)
      ensure_market_metadata
      idx = host_item_listings.index { |entry| entry["listing_id"].to_i == listing_id.to_i }
      return { "ok" => false, "message" => _INTL("Essa oferta nao esta mais disponivel.") } if idx.nil?
      listing = host_item_listings[idx]
      return { "ok" => false, "message" => _INTL("Nao podes comprar o teu proprio item.") } if listing["seller_id"].to_s == buyer_id.to_s
      host_item_listings.delete_at(idx)
      credit_sale_to_seller(listing["seller_id"], listing["price"].to_i)
      save_game
      {
        "ok"       => true,
        "message"  => _INTL("Compra concluida."),
        "price"    => listing["price"].to_i,
        "item"     => listing["item"],
        "quantity" => listing["quantity"].to_i
      }
    end

    def flush_pending_payouts_for_online_players
      return unless AnilLanRework.host?
      ensure_market_metadata
      payouts = $PokemonGlobal.online_market_payouts
      payouts.keys.each do |seller_id|
        next if seller_id.to_s.empty?
        amount = payouts[seller_id].to_i
        next if amount <= 0
        if seller_id.to_s == AnilLanRework.self_internal_id
          $player.money += amount
          @pending_messages << AnilLanRework.ui_format("Recebeu ${1} por vendas online pendentes.", amount)
          payouts.delete(seller_id)
          next
        end
        next unless AnilLanRework.players[seller_id.to_s]
        AnilLanRework.connection.send_packet("market_payout",
          "to_id"  => seller_id.to_s,
          "amount" => amount
        )
        payouts.delete(seller_id)
      end
      save_game
    rescue => e
      AnilLanRework.log("flush_pending_payouts_for_online_players error #{e.class}: #{e.message}")
    end

    def receive_payout(packet)
      amount = packet["amount"].to_i
      return if amount <= 0
      $player.money += amount
      @pending_messages << AnilLanRework.ui_format("Recebeste ${1} por vendas online.", amount)
      save_game
    end

    class OnlineItemMarketAdapter
      def getMoneyString
        pbGetGoldString
      end

      def getDisplayName(listing)
        AnilLanRework::PlayerMarket.item_listing_label(listing)
      end

      def getDisplayNamePlural(listing)
        getDisplayName(listing)
      end

      def getDisplayPrice(listing, _selling = false)
        _INTL("{1} Moedas", listing["price"].to_i.to_s_formatted)
      end

      def getDescription(listing)
        item_data = AnilLanRework::PlayerMarket.item_listing_data(listing)
        return item_data.description if item_data
        _INTL("Nao foi possivel carregar a descricao deste item.")
      end

      def getQuantity(listing)
        item_id = AnilLanRework::PlayerMarket.item_listing_id(listing)
        return 0 if !item_id
        $bag.quantity(item_id)
      end

      def icon_item(listing)
        AnilLanRework::PlayerMarket.item_listing_id(listing)
      end
    end

    class OnlinePokemonMarketAdapter
      def getMoneyString
        pbGetGoldString
      end

      def getDisplayName(listing)
        AnilLanRework::PlayerMarket.pokemon_listing_display_name(listing)
      end

      def getDisplayNamePlural(listing)
        getDisplayName(listing)
      end

      def getDisplayPrice(listing, _selling = false)
        _INTL("{1} Moedas", listing["price"].to_i.to_s_formatted)
      end

      def getDescription(listing)
        AnilLanRework::PlayerMarket.pokemon_listing_description(listing)
      end
    end

    class OnlineItemMarketScene < PokemonMart_Scene
      def pbRefresh
        itemwindow = @sprites["itemwindow"]
        listing = itemwindow.item
        @sprites["icon"].item = @adapter.icon_item(listing)
        @sprites["itemtextwindow"].text =
          (listing) ? @adapter.getDescription(listing) : _INTL("Cancelar a compra.")
        @sprites["qtywindow"].visible = !listing.nil?
        @sprites["qtywindow"].text    = _INTL("Na Mochila:<r>{1}", @adapter.getQuantity(listing))
        @sprites["qtywindow"].y       = Graphics.height - 102 - @sprites["qtywindow"].height
        @sprites["qtywindow"].baseColor   = Color.new(250, 250, 250)
        @sprites["qtywindow"].shadowColor = Color.new(75, 75, 75)
        itemwindow.refresh
        @sprites["moneywindow"].text = _INTL("Dinheiro:\n<r>{1}", @adapter.getMoneyString)
        @sprites["moneywindow"].baseColor   = Color.new(250, 250, 250)
        @sprites["moneywindow"].shadowColor = Color.new(75, 75, 75)
      end

      def pbStartBuyScene(stock, adapter)
        pbScrollMap(6, 5, 5)
        @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
        @viewport.z = 99999
        @stock = stock
        @adapter = adapter
        @sprites = {}
        @sprites["background"] = IconSprite.new(0, 0, @viewport)
        @sprites["background"].setBitmap("Graphics/UI/Mart/bg")
        @sprites["icon"] = ItemIconSprite.new(36, Graphics.height - 50, nil, @viewport)
        winAdapter = BuyAdapter.new(adapter)
        @sprites["itemwindow"] = Window_PokemonMart.new(
          stock, winAdapter, Graphics.width - 316 - 16, 10, 330 + 16, Graphics.height - 124
        )
        @sprites["itemwindow"].viewport = @viewport
        @sprites["itemwindow"].index = 0
        @sprites["itemwindow"].refresh
        @sprites["itemtextwindow"] = Window_UnformattedTextPokemon.newWithSize(
          "", 64, Graphics.height - 96 - 16, Graphics.width - 64, 128, @viewport
        )
        pbPrepareWindow(@sprites["itemtextwindow"])
        @sprites["itemtextwindow"].baseColor = Color.new(248, 248, 248)
        @sprites["itemtextwindow"].shadowColor = Color.black
        @sprites["itemtextwindow"].windowskin = nil
        @sprites["helpwindow"] = Window_AdvancedTextPokemon.new("")
        pbPrepareWindow(@sprites["helpwindow"])
        @sprites["helpwindow"].visible = false
        @sprites["helpwindow"].viewport = @viewport
        pbBottomLeftLines(@sprites["helpwindow"], 1)
        @sprites["moneywindow"] = Window_AdvancedTextPokemon.new("")
        pbPrepareWindow(@sprites["moneywindow"])
        @sprites["moneywindow"].setSkin("Graphics/Windowskins/goldskin")
        @sprites["moneywindow"].visible = true
        @sprites["moneywindow"].viewport = @viewport
        @sprites["moneywindow"].x = 0
        @sprites["moneywindow"].y = 0
        @sprites["moneywindow"].width = 190
        @sprites["moneywindow"].height = 96
        @sprites["moneywindow"].baseColor = Color.new(88, 88, 80)
        @sprites["moneywindow"].shadowColor = Color.new(168, 184, 184)
        @sprites["qtywindow"] = Window_AdvancedTextPokemon.new("")
        pbPrepareWindow(@sprites["qtywindow"])
        @sprites["qtywindow"].setSkin("Graphics/Windowskins/goldskin")
        @sprites["qtywindow"].viewport = @viewport
        @sprites["qtywindow"].width = 190
        @sprites["qtywindow"].height = 64
        @sprites["qtywindow"].baseColor = Color.new(88, 88, 80)
        @sprites["qtywindow"].shadowColor = Color.new(168, 184, 184)
        @sprites["qtywindow"].text = _INTL("Na Mochila:<r>{1}", @adapter.getQuantity(@sprites["itemwindow"].item))
        @sprites["qtywindow"].y = Graphics.height - 102 - @sprites["qtywindow"].height
        pbDeactivateWindows(@sprites)
        @buying = true
        pbRefresh
        Graphics.frame_reset
      end
    end

    class OnlinePokemonMarketScene < PokemonMart_Scene
      def pbRefresh
        itemwindow = @sprites["itemwindow"]
        listing = itemwindow.item
        @sprites["pricewindow"].visible = !listing.nil?
        @sprites["pricewindow"].text = listing ? _INTL("Preco:\n<r>{1}", @adapter.getDisplayPrice(listing)) : ""
        @sprites["pricewindow"].baseColor   = Color.new(250, 250, 250)
        @sprites["pricewindow"].shadowColor = Color.new(75, 75, 75)
        @sprites["itemtextwindow"].text =
          (listing) ? @adapter.getDescription(listing) : _INTL("Cancelar a compra.")
        itemwindow.refresh
        @sprites["moneywindow"].text = _INTL("Dinheiro:\n<r>{1}", @adapter.getMoneyString)
        @sprites["moneywindow"].baseColor   = Color.new(250, 250, 250)
        @sprites["moneywindow"].shadowColor = Color.new(75, 75, 75)
      end

      def pbStartBuyScene(stock, adapter)
        pbScrollMap(6, 5, 5)
        @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
        @viewport.z = 99999
        @stock = stock
        @adapter = adapter
        @sprites = {}
        @sprites["background"] = IconSprite.new(0, 0, @viewport)
        @sprites["background"].setBitmap("Graphics/UI/Mart/bg")
        winAdapter = BuyAdapter.new(adapter)
        @sprites["itemwindow"] = Window_PokemonMart.new(
          stock, winAdapter, Graphics.width - 316 - 16, 10, 330 + 16, Graphics.height - 124
        )
        @sprites["itemwindow"].viewport = @viewport
        @sprites["itemwindow"].index = 0
        @sprites["itemwindow"].refresh
        @sprites["itemtextwindow"] = Window_UnformattedTextPokemon.newWithSize(
          "", 64, Graphics.height - 96 - 16, Graphics.width - 64, 128, @viewport
        )
        pbPrepareWindow(@sprites["itemtextwindow"])
        @sprites["itemtextwindow"].baseColor = Color.new(248, 248, 248)
        @sprites["itemtextwindow"].shadowColor = Color.black
        @sprites["itemtextwindow"].windowskin = nil
        @sprites["helpwindow"] = Window_AdvancedTextPokemon.new("")
        pbPrepareWindow(@sprites["helpwindow"])
        @sprites["helpwindow"].visible = false
        @sprites["helpwindow"].viewport = @viewport
        pbBottomLeftLines(@sprites["helpwindow"], 1)
        @sprites["moneywindow"] = Window_AdvancedTextPokemon.new("")
        pbPrepareWindow(@sprites["moneywindow"])
        @sprites["moneywindow"].setSkin("Graphics/Windowskins/goldskin")
        @sprites["moneywindow"].visible = true
        @sprites["moneywindow"].viewport = @viewport
        @sprites["moneywindow"].x = 0
        @sprites["moneywindow"].y = 0
        @sprites["moneywindow"].width = 190
        @sprites["moneywindow"].height = 96
        @sprites["moneywindow"].baseColor = Color.new(88, 88, 80)
        @sprites["moneywindow"].shadowColor = Color.new(168, 184, 184)
        @sprites["pricewindow"] = Window_AdvancedTextPokemon.new("")
        pbPrepareWindow(@sprites["pricewindow"])
        @sprites["pricewindow"].setSkin("Graphics/Windowskins/goldskin")
        @sprites["pricewindow"].viewport = @viewport
        @sprites["pricewindow"].visible = false
        @sprites["pricewindow"].x = 0
        @sprites["pricewindow"].y = Graphics.height - 154
        @sprites["pricewindow"].width = 190
        @sprites["pricewindow"].height = 96
        @sprites["pricewindow"].baseColor = Color.new(88, 88, 80)
        @sprites["pricewindow"].shadowColor = Color.new(168, 184, 184)
        pbDeactivateWindows(@sprites)
        @buying = true
        pbRefresh
        Graphics.frame_reset
      end

      def pbEndScene
        pbEndBuyScene
      end
    end

    class OnlineItemMarketScreen
      def initialize(scene, listings)
        @scene = scene
        @stock = listings
        @adapter = OnlineItemMarketAdapter.new
      end

      def pbBuyScreen
        @scene.pbStartBuyScene(@stock, @adapter)
        loop do
          listing = @scene.pbChooseBuyItem
          break if !listing
          price = listing["price"].to_i
          if $player.money.to_i < price
            @scene.pbDisplayPaused(_INTL("Dinheiro insuficiente."))
            next
          end
          item_name = item_listing_label(listing)
          next if !@scene.pbConfirm(_INTL("Comprar {1} por ${2}?", item_name, price.to_s_formatted))
          ok, message = AnilLanRework::PlayerMarket.purchase_item_listing(listing)
          if ok
            @scene.pbDisplayPaused(message) { pbSEPlay("Mart buy item") }
            break
          end
          @scene.pbDisplayPaused(message)
          break if message.to_s =~ /nao esta mais disponivel/i
        end
        @scene.pbEndBuyScene
      end

      private

      def item_listing_label(listing)
        AnilLanRework::PlayerMarket.item_listing_label(listing)
      end
    end

    class OnlinePokemonMarketScreen
      def initialize(scene, listings)
        @scene = scene
        @stock = listings
        @adapter = OnlinePokemonMarketAdapter.new
      end

      def pbBuyScreen
        @scene.pbStartBuyScene(@stock, @adapter)
        loop do
          listing = @scene.pbChooseBuyItem
          break if !listing
          price = listing["price"].to_i
          if $player.money.to_i < price
            @scene.pbDisplayPaused(_INTL("Dinheiro insuficiente."))
            next
          end
          pokemon_name = AnilLanRework::PlayerMarket.pokemon_listing_purchase_name(listing)
          next if !@scene.pbConfirm(_INTL("Comprar {1} por ${2}?", pokemon_name, price.to_s_formatted))
          ok, message = AnilLanRework::PlayerMarket.purchase_pokemon_listing(listing)
          if ok
            @scene.pbDisplayPaused(message) { pbSEPlay("Mart buy item") }
            break
          end
          @scene.pbDisplayPaused(message)
          break if message.to_s =~ /nao esta mais disponivel/i
        end
        @scene.pbEndScene
      end
    end

    class OnlinePokemonStorage
      attr_reader :boxes
      attr_accessor :currentBox

      # ⚠️ CAIXA A CAIXA, e nao a loja inteira.
      #
      # Cada anuncio traz o blob completo do Pokemon (~1,2 KB). Com 500 na loja
      # eram ~600 KB da VPS para o telemovel a cada abertura, mais 500
      # deserialize_pokemon para construir caixas que o jogador quase nunca vai
      # ver. Agora so se busca a caixa que ele esta a olhar.
      #
      # O `carregador` e uma proc que devolve
      # { "listings" => [...], "total" => N } para uma caixa. Se for nil,
      # comporta-se como antes (a lista veio toda de uma vez).
      def initialize(listings, total = nil, carregador = nil)
        @carregador = carregador
        @paginas    = {}
        @party      = []
        @currentBox = 0
        if total.nil?
          @modo_pagina = false
          replace_listings(listings)
        else
          @modo_pagina = true
          @listings = []
          definir_total!(total)
          guardar_pagina!(0, Array(listings))
        end
      end

      def definir_total!(total)
        n = (total.to_i.to_f / PokemonBox::BOX_SIZE).ceil
        n = 1 if n <= 0
        @total = total.to_i
        @boxes = Array.new(n) do |i|
          b = PokemonBox.new(n > 1 ? _INTL("Loja {1}", i + 1) : _INTL("Loja de Jogadores"),
                             PokemonBox::BOX_SIZE)
          b.background = 0
          b
        end
        @currentBox = n - 1 if @currentBox.to_i >= n
        @currentBox = 0 if @currentBox.to_i < 0
      end

      def guardar_pagina!(idx, lista)
        @paginas[idx] = true
        caixa = @boxes[idx]
        return unless caixa
        lista.each_with_index do |listing, i|
          next if !listing || i >= PokemonBox::BOX_SIZE
          caixa[i] = AnilLanRework::PlayerMarket.listing_pokemon(listing)
        end
        base = idx * PokemonBox::BOX_SIZE
        lista.each_with_index { |l, i| @listings[base + i] = l }
      end

      # ⚠️ Uma pagina que falhe NAO fica marcada como carregada.
      #
      # Senao um soluco de rede deixava aquela caixa vazia para o resto da
      # sessao, sem forma de a recuperar a nao ser fechar e reabrir a loja.
      def modo_pagina?
        @modo_pagina == true
      end

      # Esquece a pagina e vai busca-la outra vez. Usado depois de comprar.
      def recarregar_caixa!(idx)
        return unless @modo_pagina
        i = idx.to_i
        @paginas.delete(i)
        caixa = @boxes[i]
        PokemonBox::BOX_SIZE.times { |j| caixa[j] = nil } if caixa
        base = i * PokemonBox::BOX_SIZE
        PokemonBox::BOX_SIZE.times { |j| @listings[base + j] = nil }
        garantir_pagina!(i)
      end

      def garantir_pagina!(idx)
        return if !@modo_pagina || idx.nil? || idx < 0
        return if @paginas[idx]
        return if @carregador.nil?
        r = (@carregador.call(idx) rescue nil)
        return unless r.is_a?(Hash)
        definir_total!(r["total"]) if r["total"].to_i > 0 && r["total"].to_i != @total
        guardar_pagina!(idx, Array(r["listings"]))
      end

      def replace_listings(listings)
        @modo_pagina = false
        @paginas = {}
        @listings = Array(listings)
        num_boxes = (@listings.length.to_f / PokemonBox::BOX_SIZE).ceil
        num_boxes = 1 if num_boxes == 0
        # Se a caixa aberta deixou de existir, recuar para a ultima valida.
        # Sem isto o ecra continuava a pedir uma caixa fora do intervalo.
        @currentBox = num_boxes - 1 if @currentBox.to_i >= num_boxes
        @currentBox = 0 if @currentBox.to_i < 0
        @boxes = []
        num_boxes.times do |box_idx|
          box_name = num_boxes > 1 ? _INTL("Loja {1}", box_idx + 1) : _INTL("Loja de Jogadores")
          @boxes[box_idx] = PokemonBox.new(box_name, PokemonBox::BOX_SIZE)
          @boxes[box_idx].background = 0
          start_idx = box_idx * PokemonBox::BOX_SIZE
          @listings[start_idx, PokemonBox::BOX_SIZE].to_a.each_with_index do |listing, i|
            next if !listing
            @boxes[box_idx][i] = AnilLanRework::PlayerMarket.listing_pokemon(listing)
          end
        end
      end

      def party
        @party
      end

      def maxBoxes
        @boxes.length
      end

      # ⚠️ A LISTA DO MERCADO ENCOLHE COM O ECRA ABERTO.
      #
      #   NoMethodError: undefined method `[]' for nil:NilClass
      #   0315_UI_PokemonStorage:354 in `block in initialize'  ->  @storage[boxnumber, i]
      #
      # O replace_listings reconstroi o @boxes conforme o numero de anuncios.
      # Quando o mercado e recarregado e passa a ter menos anuncios, o numero de
      # caixas diminui — mas a cena continua a apontar para a caixa antiga, e
      # @boxes[3] passa a ser nil. O indexador rebentava em vez de dizer "vazio".
      #
      # Devolver nil e o comportamento certo: o proprio ecra ja trata slot vazio
      # (`@pokemonsprites[i] = PokemonBoxIcon.new(pokemon, viewport)` aceita nil).
      #
      # E o ponto onde a caixa e pedida: a cena chega aqui ao mudar de caixa.
      def [](x, y = nil)
        if y.nil?
          return @party if x == -1
          garantir_pagina!(x)
          return @boxes[x]
        end
        return (@party ? @party[y] : nil) if x == -1
        garantir_pagina!(x)
        caixa = @boxes[x]
        return nil unless caixa
        caixa[y]
      end

      def market_listing_at(box, index)
        garantir_pagina!(box.to_i)
        overall_index = box.to_i * PokemonBox::BOX_SIZE + index.to_i
        @listings[overall_index]
      end

      # Em modo de pagina o @listings so tem o que ja foi buscado; quem quer
      # saber o tamanho da loja quer o TOTAL.
      def listing_count
        return @total.to_i if @modo_pagina
        @listings.length
      end

      def empty?
        return @total.to_i <= 0 if @modo_pagina
        @listings.empty?
      end

      def isAvailableWallpaper?(_wallpaper)
        true
      end
    end

    class OnlinePokemonStorageScene < PokemonStorageScene
      def pbUpdateOverlay(selection, party = nil)
        overlay = @sprites["overlay"].bitmap
        overlay.clear
        buttonbase = Color.new(248, 248, 248)
        buttonshadow = Color.new(80, 80, 80)
        pbDrawTextPositions(
          overlay,
          [[_INTL("Ofertas: {1}", (@storage.listing_count rescue 0)), 270, 334, :center, buttonbase, buttonshadow, :outline],
           [_INTL("Sair"), 446, 334, :center, buttonbase, buttonshadow, :outline]]
        )
        pokemon = nil
        if @screen.pbHeldPokemon
          pokemon = @screen.pbHeldPokemon
        elsif selection >= 0
          pokemon = (party) ? party[selection] : @storage[@storage.currentBox, selection]
        end
        if !pokemon
          @sprites["pokemon"].visible = false
          return
        end
        @sprites["pokemon"].visible = true
        base   = Color.new(88, 88, 80)
        shadow = Color.new(168, 184, 184)
        nonbase   = Color.new(208, 208, 208)
        nonshadow = Color.new(224, 224, 224)
        pokename = pokemon.name
        textstrings = [[pokename, 10, 14, :left, base, shadow]]
        if !pokemon.egg?
          imagepos = []
          if pokemon.male?
            textstrings.push([_INTL("♂"), 148, 14, :left, Color.new(24, 112, 216), Color.new(136, 168, 208)])
          elsif pokemon.female?
            textstrings.push([_INTL("♀"), 148, 14, :left, Color.new(248, 56, 32), Color.new(224, 152, 144)])
          end
          imagepos.push([_INTL("Graphics/UI/Storage/overlay_lv"), 6, 246])
          textstrings.push([pokemon.level.to_s, 28, 240, :left, base, shadow])
          if pokemon.ability
            textstrings.push([pokemon.ability.name, 86, 312, :center, base, shadow])
          else
            textstrings.push([_INTL("Sin habilidad"), 86, 312, :center, nonbase, nonshadow])
          end
          listing = @storage.market_listing_at(@storage.currentBox, selection)
          if listing
            textstrings.push([_INTL("{1} Moedas", listing["price"].to_i.to_s_formatted), 86, 348, :center, base, shadow])
          else
            textstrings.push([_INTL("Sem preco"), 86, 348, :center, nonbase, nonshadow])
          end
          imagepos.push(["Graphics/UI/shiny", 156, 198]) if pokemon.shiny? && !pokemon.super_shiny?
          imagepos.push(["Graphics/UI/shiny_ur", 156, 198]) if pokemon.super_shiny?
          typebitmap = AnimatedBitmap.new(_INTL("Graphics/UI/types"))
          pokemon.types.each_with_index do |type, i|
            type_number = GameData::Type.get(type).icon_position
            type_rect = Rect.new(0, type_number * 28, 64, 28)
            type_x = (pokemon.types.length == 1) ? 52 : 18 + (70 * i)
            overlay.blt(type_x, 272, typebitmap.bitmap, type_rect)
          end
          drawMarkings(overlay, 70, 240, 128, 20, pokemon.markings)
          pbDrawImagePositions(overlay, imagepos)
          typebitmap.dispose
        end
        pbDrawTextPositions(overlay, textstrings)
        @sprites["pokemon"].setPokemonBitmap(pokemon)
        @sprites["pokemon"].make_grey_if_fainted = pokemon.perma_faint
      end

      def pbSummary(selected, heldpoke)
        oldsprites = pbFadeOutAndHide(@sprites)
        scene = PokemonSummary_Scene.new
        scene.remote_view = true
        screen = PokemonSummaryScreen.new(scene)
        screen.remote_view = true
        if heldpoke
          screen.pbStartScreen([heldpoke], 0)
        elsif selected[0] == -1
          @selection = screen.pbStartScreen(@storage.party, selected[1])
          pbPartySetArrow(@sprites["arrow"], @selection)
          pbUpdateOverlay(@selection, @storage.party)
        else
          @selection = screen.pbStartScreen(@storage.boxes[selected[0]], selected[1])
          pbSetArrow(@sprites["arrow"], @selection)
          pbUpdateOverlay(@selection)
        end
        pbFadeInAndShow(@sprites, oldsprites)
      end
    end

    class OnlinePokemonStorageScreen < PokemonStorageScreen
      def initialize(scene, storage, refresh_proc)
        super(scene, storage)
        @refresh_proc = refresh_proc
      end

      def pbStartBuyScreen
        $game_temp.in_storage = true
        @heldpkmn = nil
        @scene.pbStartBox(self, 1)
        loop do
          selected = @scene.pbSelectBox(@storage.party)
          break if selected.nil?
          case selected[0]
          when -2
            # Clique em Ofertas (atualizar)
            refresh_market
            next
          when -3
            break if pbConfirm(_INTL("Fechar a loja de jogadores?"))
            next
          when -4
            next
          end
          pokemon = @storage[selected[0], selected[1]]
          next if !pokemon
          listing = @storage.market_listing_at(selected[0], selected[1])
          next if !listing
          # ⚠️ O MENU DE QUEM VENDE E OUTRO.
          #
          # Ate aqui so havia "Comprar", e o servidor recusava a compra do
          # proprio anuncio — ou seja, quem punha um Pokemon a venda ficava sem
          # nenhuma forma de o tirar de la ou de corrigir o preco. Era preciso
          # pedir a um administrador.
          meu = (AnilLanRework::PlayerMarket.own_listing?(listing) rescue false)
          if meu
            command = pbShowCommands(
              _INTL("{1} — seu anúncio por {2} moedas.", pokemon.name, listing["price"].to_i.to_s_formatted),
              [_INTL("Resumo"), _INTL("Remover"), _INTL("Mudar preço"), _INTL("Cancelar")])
            case command
            when 0
              pbSummary(selected, nil)
            when 1
              next if !pbConfirm(_INTL("Retirar {1} do mercado?", pokemon.name))
              ok, message = AnilLanRework::PlayerMarket.cancel_pokemon_listing(listing)
              pbDisplay(message)
              refresh_market
              break if ok || @storage.empty?
            when 2
              actual = listing["price"].to_i
              novo = nil
              begin
                params = ChooseNumberParams.new
                params.setRange(1, 999_999_999)
                params.setDefaultValue(actual)
                params.setCancelValue(0)
                novo = pbMessageChooseNumber(_INTL("Preço atual: {1}. Qual o novo?", actual.to_s_formatted), params)
              rescue
                novo = nil
              end
              next if novo.nil? || novo.to_i <= 0 || novo.to_i == actual
              ok, message = AnilLanRework::PlayerMarket.update_pokemon_listing_price(listing, novo)
              pbDisplay(message)
              refresh_market if ok
            end
          else
            command = pbShowCommands(_INTL("Selecionaste {1}.", pokemon.name),
                                     [_INTL("Comprar"), _INTL("Resumo"), _INTL("Cancelar")])
            case command
            when 0
              price = listing["price"].to_i
              if $player.money.to_i < price
                pbDisplay(_INTL("Dinheiro insuficiente."))
                next
              end
              next if !pbConfirm(_INTL("Comprar {1} por ${2}?", pokemon.name, price.to_s_formatted))
              ok, message = AnilLanRework::PlayerMarket.purchase_pokemon_listing(listing)
              pbDisplay(message)
              refresh_market
              break if ok || @storage.empty?
            when 1
              pbSummary(selected, nil)
            end
          end
        end
        @scene.pbCloseBox
        $game_temp.in_storage = false
      end

      def pbBoxCommands
      end



      private

      # ⚠️ Depois de uma compra so se recarrega a CAIXA ABERTA.
      #
      # Isto chamava o @refresh_proc, que buscava a loja INTEIRA e caia no
      # replace_listings — ou seja, desfazia a paginacao e descarregava as 17
      # caixas outra vez, precisamente a seguir a uma compra. Em modo de pagina
      # basta reler a caixa onde se esta; o total vem na resposta e ajusta o
      # numero de caixas se a loja encolheu.
      def refresh_market
        if @storage.respond_to?(:recarregar_caixa!) && @storage.modo_pagina?
          @storage.recarregar_caixa!(@storage.currentBox)
        else
          listings = @refresh_proc.call
          @storage.replace_listings(listings)
        end
        @scene.pbHardRefresh
        pbDisplay(_INTL("Nao ha nada a venda.")) if @storage.empty?
      end
    end

    def on_packet(packet)
      case packet["type"]
      when "market_listings", "market_action_result"
        queue_result(packet)
      when "market_payout"
        receive_payout(packet)
      when "market_request_listings"
        handle_request_listings(packet) if AnilLanRework.host?
      when "market_publish_pokemon"
        handle_publish_pokemon(packet) if AnilLanRework.host?
      when "market_publish_item"
        handle_publish_item(packet) if AnilLanRework.host?
      when "market_purchase_pokemon"
        handle_purchase_pokemon(packet) if AnilLanRework.host?
      when "market_purchase_item"
        handle_purchase_item(packet) if AnilLanRework.host?
      end
    end

    def handle_request_listings(packet)
      kind = packet["market_kind"].to_s
      listings = kind == "pokemon" ? host_pokemon_listings : host_item_listings
      AnilLanRework.connection.send_packet("market_listings",
        "to_id"       => packet["sender_id"].to_s,
        "request_id"  => packet["request_id"].to_s,
        "market_kind" => kind,
        "listings"    => listings
      )
    end

    def handle_publish_pokemon(packet)
      result = host_publish_pokemon(packet["listing"] || {})
      AnilLanRework.connection.send_packet("market_action_result",
        "to_id"      => packet["sender_id"].to_s,
        "request_id" => packet["request_id"].to_s,
        "ok"         => result["ok"] == true,
        "message"    => result["message"].to_s
      )
    end

    def handle_publish_item(packet)
      result = host_publish_item(packet["listing"] || {})
      AnilLanRework.connection.send_packet("market_action_result",
        "to_id"      => packet["sender_id"].to_s,
        "request_id" => packet["request_id"].to_s,
        "ok"         => result["ok"] == true,
        "message"    => result["message"].to_s
      )
    end

    def handle_purchase_pokemon(packet)
      result = host_purchase_pokemon(packet["listing_id"], packet["sender_id"])
      AnilLanRework.connection.send_packet("market_action_result",
        "to_id"      => packet["sender_id"].to_s,
        "request_id" => packet["request_id"].to_s,
        "ok"         => result["ok"] == true,
        "message"    => result["message"].to_s,
        "price"      => result["price"],
        "pokemon"    => result["pokemon"]
      )
    end

    def handle_purchase_item(packet)
      result = host_purchase_item(packet["listing_id"], packet["sender_id"])
      AnilLanRework.connection.send_packet("market_action_result",
        "to_id"      => packet["sender_id"].to_s,
        "request_id" => packet["request_id"].to_s,
        "ok"         => result["ok"] == true,
        "message"    => result["message"].to_s,
        "price"      => result["price"],
        "item"       => result["item"],
        "quantity"   => result["quantity"]
      )
    end

    def update_pending
      message = @pending_messages.shift
      pbMessage(message) if message && !message.to_s.empty?
    rescue => e
      AnilLanRework.log("player market update_pending error #{e.class}: #{e.message}")
    end

    def open_remote_blob_summary(blob)
      pkmn = AnilLanRework::Serializer.deserialize_pokemon(blob)
      return unless pkmn
      pbFadeOutIn do
        scene = PokemonSummary_Scene.new
        scene.remote_view = true
        screen = PokemonSummaryScreen.new(scene)
        screen.remote_view = true
        screen.pbStartScreen([pkmn], 0)
      end
    rescue => e
      AnilLanRework.log("open_remote_blob_summary error #{e.class}: #{e.message}")
    end

    def open_pc_buy_menu
      # Pede so a primeira caixa. O total vem junto, e as outras sao buscadas
      # quando (e se) o jogador la chegar.
      primeira = fetch_listings("pokemon", 0)
      if primeira.nil?
        pbMessage(_INTL("O mercado nao respondeu. Tenta novamente mais tarde."))
        return
      end
      total = primeira["total"].to_i
      if total <= 0
        pbMessage(_INTL("Nao ha nada a venda."))
        return
      end
      carregador = proc { |idx| fetch_listings("pokemon", idx) }
      storage = OnlinePokemonStorage.new(Array(primeira["listings"]), total, carregador)
      scene = OnlinePokemonStorageScene.new
      screen = OnlinePokemonStorageScreen.new(scene, storage, proc { fetch_listings("pokemon") })
      screen.pbStartBuyScreen
    end

    def open_item_buy_menu
      listings = fetch_listings("item")
      if listings.empty?
        pbMessage(_INTL("Nao ha nada a venda."))
        return
      end
      scene = OnlineItemMarketScene.new
      screen = OnlineItemMarketScreen.new(scene, listings)
      screen.pbBuyScreen
    end

    def open_item_sell_menu
      return pbMessage(_INTL("Precisas de uma sessao online para usar o mercado.")) unless market_ready?
      scene = PokemonBag_Scene.new
      screen = PokemonBagScreen.new(scene, $bag)
      item = screen.pbChooseItemScreen(proc { |itm| next false if !itm; next false if GameData::Item.get(itm).is_important?; true })
      return if !item
      max_qty = $bag.quantity(item)
      return if max_qty <= 0
      qty = max_qty
      if max_qty > 1
        params = ChooseNumberParams.new
        params.setRange(1, max_qty)
        params.setDefaultValue(1)
        qty = pbMessageChooseNumber(_INTL("Quantidade para vender online?"), params)
      end
      return if qty.to_i <= 0
      price = choose_price(_INTL("Preco do lote para o mercado?"))
      return if price.to_i <= 0
      ok, message = publish_item(item, qty, price)
      if ok
        $bag.remove(item, qty)
        save_game
      end
      pbMessage(message)
    rescue => e
      AnilLanRework.log("open_item_sell_menu error #{e.class}: #{e.message}")
      pbMessage(_INTL("Nao foi possivel publicar o item."))
    end

    def open_peer_follower_summary(peer)
      return unless peer
      party = AnilLanRework::Serializer.deserialize_party(peer.party_blob)
      party = Array(party).compact.select { |p| p.respond_to?(:species) }
      if party.empty?
        pbMessage(_INTL("Nao foi possivel obter os Pokemon desse jogador."))
        return
      end
      party.each do |pkmn|
        pkmn.owner.name = peer.name.to_s rescue nil
        pkmn.owner.gender = 2 rescue nil
      end
      pbFadeOutIn do
        scene = PokemonSummary_Scene.new
        scene.remote_view = true
        scene.peer_owner_name = peer.name.to_s
        screen = PokemonSummaryScreen.new(scene)
        screen.remote_view = true
        screen.pbStartScreen(party, 0)
      end
    rescue => e
      AnilLanRework.log("open_peer_follower_summary error #{e.class}: #{e.message}")
      pbMessage(_INTL("Falha ao abrir os dados do Pokemon do outro jogador."))
    end

    def sell_storage_selected(storage_screen, selected, pokemon)
      return false unless storage_screen && selected && pokemon
      return pbMessage(_INTL("Nao podes vender Ovos no mercado online.")) if pokemon.egg?
      if pokemon.hasItem?
        pbMessage(_INTL("Nao podes vender Pokemon segurando objetos. Retira o item primeiro."))
        return false
      end
      if selected[0].to_i == -1
        able_count = $player.party.count { |pkmn| pkmn && !pkmn.egg? && pkmn.hp.to_i > 0 }
        if pokemon.hp.to_i > 0 && able_count <= 1
          pbMessage(_INTL("Nao podes vender o teu ultimo Pokemon capaz de batalhar."))
          return false
        end
      end
      price = choose_price(_INTL("Preco do Pokemon no mercado?"))
      return false if price.to_i <= 0
      ok, message = publish_pokemon(AnilLanRework::Serializer.serialize_pokemon(pokemon), price)
      if ok
        storage_screen.storage.pbDelete(selected[0], selected[1])
        storage_screen.scene.pbHardRefresh rescue storage_screen.scene.pbRefresh rescue nil
        save_game
      end
      pbMessage(message)
      ok
    rescue => e
      AnilLanRework.log("sell_storage_selected error #{e.class}: #{e.message}")
      pbMessage(_INTL("Nao foi possivel vender esse Pokemon agora."))
      false
    end
  end
end

module AnilLanRework
  module Router
    PAYOUT_FLUSH_TICK = 300 unless const_defined?(:PAYOUT_FLUSH_TICK)
    @last_tick_frame = -1
    @last_player_send = -1
    @last_party_send = -1
    @last_snapshot = -1
    @last_event_stream = -1
    @last_payout_flush = -1
    @peer_debug_snapshot = {}

    class << self
      attr_accessor :last_payout_flush
    end
    module_function

    def tick
      return unless AnilLanRework.connected?
      if $game_temp && $game_temp.respond_to?(:in_menu) && $game_temp.in_menu
        File.open("menu_debug.txt", "a") { |f| f.puts("[Router.tick] in_menu=true, frame=#{Graphics.frame_count rescue 0}") rescue nil }
      end

      AnilLanRework.update_active_time rescue nil

      # Previne timeout falso dos jogadores devido à pausa do loop principal (ex: menus ou transições longas)
      now_time = Time.now.to_f
      @last_router_tick_time ||= now_time
      gap = now_time - @last_router_tick_time
      @last_router_tick_time = now_time

      if gap > 4.0
        AnilLanRework.players.each_value do |peer|
          peer.last_update_time = now_time if peer.last_update_time
        end
        AnilLanRework.log("[Router.tick] Pausa longa de #{gap.round(2)}s detectada. Ajustado last_update_time de todos os peers para evitar timeout falso.") rescue nil
      end

      # Timeout de cliente removido: a VPS/servidor envia peer_left/player_disconnect
      # quando os jogadores realmente saem, evitando que eles sumam ao entrar em menus ou batalhas.
      # stale_peers = []
      # AnilLanRework.players.each do |peer_id, peer|
      #   next if peer_id.to_s == AnilLanRework.self_internal_id.to_s
      #   peer.last_update_time ||= now_time
      #   if now_time - peer.last_update_time > 25.0
      #     stale_peers << peer_id
      #   end
      # end
      # stale_peers.each do |peer_id|
      #   peer = AnilLanRework.players[peer_id]
      #   AnilLanRework.log("peer timeout peer=#{peer_id} name=#{peer&.name}") rescue nil
      #   AnilLanRework.players.delete(peer_id)
      #   AnilLanRework.request_map_graphics_refresh!("peer_timeout_#{peer_id}", 2) rescue nil
      # end

      # Processa restauração de coordenadas de forma segura no main thread
      # Desativada restauração de coordenadas via servidor para evitar descompassos e personagem sumindo
      # if AnilLanRework.pending_restore_coords
      #   coords = AnilLanRework.pending_restore_coords
      #   AnilLanRework.pending_restore_coords = nil
      #   AnilLanRework.apply_coordinate_restore!(coords) rescue nil
      # end

      # Evitar processamento múltiplo no mesmo frame (correção para spam de pacotes)
      current_frame = Graphics.frame_count
      if current_frame == @last_tick_frame
        return
      end
      @last_tick_frame = current_frame

      AnilLanRework.connection.tick

      if !AnilLanRework::WorldSync.input_locked? &&
         current_frame - @last_player_send >= AnilLanRework::PLAYER_SEND_TICK &&
         current_frame - AnilLanRework.last_battle_end_frame > 60 # Bloqueia sync de party por 60 frames após batalha
        @last_player_send = current_frame
        AnilLanRework::WorldSync.send_player_state
      end
      if current_frame - @last_party_send >= AnilLanRework::PARTY_SEND_TICK
        @last_party_send = current_frame
        AnilLanRework::TradeSync.send_party_sync
      end
      if AnilLanRework.host? && current_frame - @last_event_stream >= AnilLanRework::EVENT_STREAM_TICK
        @last_event_stream = current_frame
        AnilLanRework::WorldSync.send_event_stream_if_host
      end
      if AnilLanRework.host? && current_frame - @last_snapshot >= AnilLanRework::SNAPSHOT_SEND_TICK
        @last_snapshot = current_frame
        AnilLanRework::WorldSync.send_snapshot_if_host
      end
      if AnilLanRework.host? && current_frame - @last_payout_flush >= PAYOUT_FLUSH_TICK
        @last_payout_flush = current_frame
        AnilLanRework::PlayerMarket.flush_pending_payouts_for_online_players
      end
      AnilLanRework.connection.flush_batch

      AnilLanRework.connection.drain { |packet| route_packet(packet) }
      AnilLanRework::BattleSync.expire_outgoing_invites
      AnilLanRework::WorldSync.apply_pending_snapshot
      AnilLanRework::WorldSync.apply_pending_event_stream
    rescue => e
      AnilLanRework.log("router tick error #{e.class}: #{e.message}")
    end

    def route_packet(packet)
      case packet["type"]
      when "channel_change_ack", "map_change_ack"
        begin
          new_host_id = packet["host_id"].to_s
          # 1. Update the host ID of the connection and local host status
          if AnilLanRework.connection && new_host_id && !new_host_id.empty?
            AnilLanRework.connection.instance_variable_set(:@host_id, new_host_id)
          end
          is_host = (new_host_id == AnilLanRework.self_internal_id)
          AnilLanRework.instance_variable_set(:@is_host, is_host)
          
          # 2. Remove sprites do mapa anterior, mas preserve o cadastro de peers
          # quando for apenas troca de MAPA. Assim o lobby pode manter jogadores
          # conhecidos em outros mapas do mesmo canal. Em troca de CANAL, limpa,
          # pois os peers pertencem a outra sessao/canal.
          AnilLanRework.clear_all_remote_events_from_map rescue nil
          if packet["type"] == "channel_change_ack"
            AnilLanRework.players.clear
          end
          
          # 3. Populate/merge peers announced by the server
          Array(packet["players"]).each do |peer_hash|
            next unless peer_hash.is_a?(Hash)
            peer_id = peer_hash["internal_id"].to_s
            next if peer_id.empty? || peer_id == AnilLanRework.self_internal_id
            peer = (AnilLanRework.players[peer_id] ||= AnilLanRework::RemotePeer.new)
            peer.internal_id = peer_id
            peer.apply_state_hash(peer_hash)
            peer.update_from_packet(peer_hash)
            if defined?(AnilLanRework) && AnilLanRework.respond_to?(:known_peers) && AnilLanRework.known_peers
              AnilLanRework.known_peers[peer_id] = true
            end
          end
          
          # 4. Trigger map graphics refresh
          AnilLanRework.request_map_graphics_refresh!(packet["type"], 4)
          
          # 5. Display corner popup notification
          if packet["type"] == "channel_change_ack"
            current_ch = $PokemonSystem ? $PokemonSystem.multiplayer_channel : 1
            AnilLanRework.enqueue_corner_popup(_INTL("Canal {1} Conectado", current_ch)) rescue nil
          end
          
          AnilLanRework.log("#{packet["type"]} processed: new_host=#{new_host_id} peers=#{Array(packet["players"]).length}")
        rescue => e
          AnilLanRework.log("#{packet["type"]} error: #{e.class}: #{e.message}")
        end
        return
      when "gift_box_open_broadcast"
        GiftBoxSystem.on_receive_gift_box_open(packet) rescue nil
        return
      when "player_capture"
        AnilLanRework.show_capture_balloon_for_peer(packet) rescue nil
        return
      when "battle_rejoin_ack"
        begin
          ctx = AnilLanRework::BattleSync.active_context rescue nil
          if ctx && ctx.battle_id.to_s == packet["battle_id"].to_s
            if packet["status"] == "ok" || packet["partner_id"]
              # Desfaz flags de coop_eliminated para restaurar sincronia
              ctx.instance_variable_set(:@anil_remote_coop_eliminated, false)
              ctx.instance_variable_set(:@anil_remote_coop_watch_until_end, false)
              AnilLanRework.log("[BATTLE_REJOIN] Batalha #{ctx.battle_id} re-atada com sucesso! partner=#{packet['partner_id']}")
              # Tira o duelo da espera de queda (MOD 146). Sem isto o contador
              # continuava a correr apesar de a batalha ja estar re-atada.
              AnilPvpQueda.on_packet(packet) if defined?(AnilPvpQueda)
              # ⚠️ O popup de canto e desenho do MAPA.
              #
              # Dentro de uma batalha ele nao aparece, e so era visto quando o
              # jogador voltava ao overworld — noticia velha, sobre uma batalha
              # que ja tinha acabado. Quando isto acontece em duelo, quem avisa
              # e a propria janela de espera do MOD 146, na hora certa.
              em_batalha = ($game_temp && $game_temp.in_battle) ||
                           (ctx && [:pvp, :coop].include?(ctx.mode))
              unless em_batalha
                AnilLanRework.enqueue_corner_popup("Parceiro reconectado à batalha!") rescue nil
              end
            else
              AnilLanRework.log("[BATTLE_REJOIN] Parceiro offline, batalha continua com IA. status=#{packet['status']}")
            end
          end
        rescue => e
          AnilLanRework.log("[BATTLE_REJOIN] Erro no ack: #{e.class}: #{e.message}")
        end
        return
      when "battle_hp_sync"
        AnilLanRework::BattleSync.receive_hp_sync(packet)
      when "pvp_hp_snapshot"
        AnilLanRework::BattleSync.receive_hp_snapshot(packet)
      when "pvp_hp_request"
        AnilLanRework::BattleSync.receive_hp_request(packet)
      when "gift_broadcast"
        begin
          player_name = packet["player_name"].to_s
          player_id = packet["player_id"].to_s
          
          # Não exibe a mensagem de broadcast para o próprio jogador local, pois ele já tem o popup local dele
          is_local = false
          if defined?(AnilLanRework)
            if !player_id.empty?
              is_local = (player_id == AnilLanRework.self_internal_id || player_id == AnilLanRework.self_display_id)
            else
              is_local = (player_name.to_s.downcase.strip == AnilLanRework.self_name.to_s.downcase.strip)
            end
          end
          return if is_local

          item_id = packet["item"].to_s.upcase.to_sym
          qty = packet["qty"].to_i
          item_name = if GameData::Item.exists?(item_id)
                        GameData::Item.get(item_id).name rescue item_id.to_s
                      else
                        item_id.to_s
                      end
          if defined?(AnilLanRework) && AnilLanRework.respond_to?(:enqueue_popup)
            if player_name.to_s.downcase.strip == "todos" || player_id.to_s.upcase.strip == "ALL"
              text = qty > 1 ? _INTL("Todos receberam {1}x {2} de presente!", qty, item_name) : _INTL("Todos receberam {1} de presente!", item_name)
            else
              text = qty > 1 ? _INTL("{1} recebeu {2}x {3} de presente!", player_name, qty, item_name) : _INTL("{1} recebeu {2} de presente!", player_name, item_name)
            end
            AnilLanRework.enqueue_popup(text, 6.0, item_id)
          end
        rescue => e
          AnilLanRework.log("gift_broadcast error: #{e.message}")
        end
       when "peer_joined", "player_join", "player_state"
        merge_peer_from_packet(packet)
      when "peer_left", "player_disconnect"
        peer_id = (packet["peer_id"] || packet["player_id"]).to_s
        peer = AnilLanRework.players[peer_id]
        if peer
          unless packet["map_change"] == true
            AnilLanRework.enqueue_corner_popup("#{peer.name} saiu")
          end

          # TROCA DE MAPA NAO APAGA O PEER.
          #
          # Apagar era o que fazia o parceiro sumir do HUD de grupo assim que
          # mudava de mapa: o HUD faz players[partner_id] e, sem o objecto, ele
          # esconde-se inteiro — como se nao houvesse grupo. O mesmo valia para
          # a lista de jogadores.
          #
          # Agora, quando o servidor diz PARA ONDE a pessoa foi, o peer fica na
          # lista com o mapa novo. Nao aparece sprite fantasma: o Spriteset_Map
          # ja so desenha peers cujo map_id e igual ao mapa actual (ver o
          # `on_this_map` e o `keep` la).
          #
          # Sem new_map_id comporta-se como antes e apaga — e o caso da troca de
          # CANAL (a pessoa saiu mesmo do teu mundo) e tambem o de um servidor
          # antigo, que nao manda este campo.
          novo_mapa = packet["new_map_id"]
          if packet["map_change"] == true && !novo_mapa.nil?
            peer.map_id = novo_mapa.to_i
            # As coordenadas ficam como estao, de proposito. Anula-las parecia
            # mais limpo, mas o sprite usa @real_x/@real_y (que sao outros
            # campos) e varios sitios fazem peer.x sem proteger — o filtro por
            # map_id ja impede tanto o desenho como a interacao, entao mexer
            # aqui so acrescentaria risco.
            AnilLanRework.log("[PEER] #{peer.name} mudou para o mapa #{novo_mapa} — mantido na lista") rescue nil
            # `return` e nao `next`: isto esta dentro do metodo route_packet, nao
            # de um bloco. O valor devolvido nao e usado (o chamador e um
            # `drain { |p| route_packet(p) }`), entao sair aqui e seguro.
            return
          end

          AnilLanRework.players.delete(peer_id)
# Limpa parceiro de grupo apenas em desconexao real; se for so troca de mapa, avisa e mantem o grupo
if defined?(AnilLanRework) && AnilLanRework.respond_to?(:coop_party_partner_id) &&
   AnilLanRework.coop_party_partner_id.to_s == peer_id
  if packet["map_change"] == true
    AnilLanRework.enqueue_corner_popup("#{peer.name} mudou de mapa") rescue nil
  else
    AnilLanRework.coop_party_partner_id = nil
  end
end
          # Notifica BattleSync imediatamente se o peer era o parceiro de batalha coop ativo
          begin
            ctx = AnilLanRework::BattleSync.active_context rescue nil
            if ctx && ctx.mode == :coop && ctx.partner_id.to_s == peer_id
              AnilLanRework.log("[PEER_LEFT] Parceiro coop #{peer_id} desconectou durante batalha ativa — acionando fallback de IA imediato")
              AnilLanRework::BattleSync.receive_coop_eliminated({
                "battle_id" => ctx.battle_id,
                "watch_until_end" => false
              })
            end
          rescue => e
            AnilLanRework.log("[PEER_LEFT] Erro ao notificar BattleSync: #{e.class}: #{e.message}")
          end
          # Força refresh do mapa para remover sprite imediatamente (Refresh removido)
          # AnilLanRework.request_map_graphics_refresh!("peer_disconnect_#{peer_id}", 2)
        end
      when "world_snapshot"
        AnilLanRework::WorldSync.queue_snapshot(packet)
      when "world_event_stream"
        AnilLanRework::WorldSync.queue_event_stream(packet)
      when "battle_request"
        merge_peer_from_packet(packet)
        AnilLanRework::BattleSync.store_coop_request(packet)
      when "battle_response"
        AnilLanRework::BattleSync.store_battle_response(packet)
      when "battle_action"
        AnilLanRework::BattleSync.queue_remote_action(packet)
      when "battle_foe_action"
        AnilLanRework::BattleSync.queue_remote_foe_action(packet)
      when "battle_foe_turn"
        AnilLanRework::BattleSync.queue_remote_foe_turn(packet)
      when "battle_hp_event"
        AnilLanRework::BattleSync.queue_remote_hp_event(packet)
      when "coop_turn_batch"
        AnilLanRework::BattleSync.queue_coop_turn_batch(packet)
      when "coopcc_foe"
        CoopCC.guardar_escolha_foe(packet) rescue nil
      when "coopcc_desistir"
        # O parceiro fugiu/desistiu. Por ora so registra: o tratamento de fuga
        # em coop e o P5 (D7 do plano), que ainda nao foi feito.
        AnilLanRework.log("CoopCC: parceiro desistiu da batalha #{packet['battle_id']}") rescue nil
      when "coopcc_troca"
        CoopCC.guardar_troca(packet) rescue nil
      when "coopauth_resultado"
        # 127_Coop_Auth_Reprodutor: turno resolvido pelo servidor.
        CoopAuthCliente.guardar_resultado(packet) rescue nil
      when "coopauth_pronto", "coopauth_recusado", "coopauth_encerrada"
        CoopAuthCliente.guardar_resultado(packet) rescue nil
      when "coopcc_party"
        CoopCC.guardar_party(packet) rescue nil
      when "coopcc_escolha"
        # 125_Coop_CableClub_Base (P4a). Aditivo: nenhum cliente envia este tipo
        # ainda — a classe nova so e instanciada no P4b.
        CoopCC.guardar_escolha(packet) rescue nil
      when "coop_priority_order"
        # 124_Coop_Determinismo_V3: ordem do turno autoritativa (host -> guest)
        AnilLanRework::BattleSync.queue_coop_priority_order(packet) rescue nil
      when "coop_turn_hash"
        # 124_Coop_Determinismo_V3: hash de turno canonico para deteccao de desync
        AnilLanRework::BattleSync.queue_coop_turn_hash(packet) rescue nil
      when "battle_status_event"
        AnilLanRework::BattleSync.queue_remote_status_event(packet)
      when "battle_capture_result"
        AnilLanRework::BattleSync.queue_remote_capture_result(packet)
      when "battle_text_step"
        AnilLanRework::BattleSync.queue_remote_text_step(packet)
      when "battle_text_state"
        AnilLanRework::BattleSync.queue_remote_text_state(packet)
      when "battle_manual_lock"
        AnilLanRework::BattleSync.queue_remote_manual_lock(packet)
      when "battle_phase_sync"
        AnilLanRework::BattleSync.queue_remote_phase_sync(packet)
      when "battle_called_move"
        AnilLanRework::BattleSync.queue_remote_called_move(packet)
      when "battle_turn_hash"
        AnilLanRework::BattleSync.queue_remote_turn_hash(packet)
      when "battle_start_signal"
        AnilLanRework::BattleSync.receive_start_signal(packet)
      when "battle_seed_response"
        AnilLanRework::BattleSync.queue_battle_seed(packet) rescue nil
      when "turn_seed_response"
        AnilLanRework::BattleSync.queue_turn_seed(packet) rescue nil
      when "battle_field_sync"
        AnilLanRework::BattleSync.queue_field_state_sync(packet) rescue nil
      when "party_sync"
        merge_peer_from_packet(packet)
        AnilLanRework::TradeSync.on_packet(packet)
      when "party_request"
        AnilLanRework::TradeSync.send_party_sync(packet["sender_id"].to_s)
      when "battle_invite"
        merge_peer_from_packet(packet)
        AnilLanRework::BattleSync.store_incoming_invite(packet)
      when "battle_accept"
        merge_peer_from_packet(packet)
        AnilLanRework::BattleSync.receive_accept(packet)
      when "battle_lineup_progress"
        # PvP negociado: o que o oponente marcou ate agora (rodape ao vivo).
        AnilLanRework::BattleSync.receive_lineup_progress(packet)
      when "battle_lineup_final"
        # PvP negociado: equipe fechada do oponente.
        AnilLanRework::BattleSync.receive_lineup_final(packet)
      when "battle_decline"
        AnilLanRework::BattleSync.receive_decline(packet)
      when "battle_switch"
        AnilLanRework::BattleSync.queue_remote_switch(packet)
      when "battle_forced_switch"
        AnilLanRework::BattleSync.queue_remote_forced_switch(packet)
      when "battle_turn"
        AnilLanRework::BattleSync.queue_remote_turn(packet)
      when "battle_end"
        AnilLanRework::BattleSync.receive_battle_end(packet)
      when "battle_coop_eliminated"
        AnilLanRework::BattleSync.receive_coop_eliminated(packet)
      when "battle_evolution"
        AnilLanRework::BattleSyncEvolution.receive_battle_evolution(packet)
      when "battle_evolution_ack"
        AnilLanRework::BattleSyncEvolution.receive_evolution_ack(packet)
      when "remote_poke_battle_request"
        AnilLanRework::WorldSync.handle_remote_poke_battle_request(packet)
      # "trade_ok" e o aval do servidor na troca autoritativa.
      #
      # Fica num ramo proprio, SEM merge_peer_from_packet: quem o envia e o
      # servidor, nao o parceiro, e o pacote so tem type + sender_id. Passa-lo
      # pelo merge faria o apply_state_hash/update_from_packet correrem sem
      # map_id, x, y nem char_name, com risco de esmagar o estado do parceiro
      # justamente a meio da troca.
      #
      # Tem de estar listado aqui: o case interno do TradeSync so e alcancado
      # pelos tipos que este despachante deixa passar, e um tipo em falta e
      # descartado em silencio — sem erro e sem log. Foi o que prendeu a troca em
      # :aguardar_servidor, sem animacao e sem party nova ate reabrir o jogo.
      when "trade_ok"
        AnilLanRework::TradeSync.on_packet(packet)
      # Cadeia de derrotados partilhada com o parceiro de grupo (MOD 135).
      # Sem merge_peer_from_packet: o pacote nao traz estado de posicao.
      when "coop_chain"
        AnilLanRework::CadeiaRouter.on_packet(packet) if defined?(AnilLanRework::CadeiaRouter)
      # Estado da skin custom na fila de aprovacao (MOD 137). Sem merge de peer:
      # quem manda e o servidor, e o pacote nao traz posicao nenhuma.
      when "ranked_state"
        AnilRanqueado.receber_estado(packet) if defined?(AnilRanqueado)
      # Queda e retomada de um duelo (MOD 146). Sem merge_peer_from_packet: sao
      # avisos do servidor sobre uma sessao, nao estado de posicao.
      when "battle_peer_lost", "battle_peer_back", "battle_resume_ok"
        AnilPvpQueda.on_packet(packet) if defined?(AnilPvpQueda)
      when "skin_status"
        AnilLanRework::SkinAprovacaoRouter.on_packet(packet) if defined?(AnilLanRework::SkinAprovacaoRouter)
      when "trade_invite", "trade_accept", "trade_pick", "trade_confirm", "trade_cancel"
        merge_peer_from_packet(packet)
        AnilLanRework::TradeSync.on_packet(packet)
      when "coop_item_offer", "coop_item_offer_result", "coop_item_commit", "coop_item_cancel"
        merge_peer_from_packet(packet)
        AnilLanRework::ItemSync.on_packet(packet)
      when "market_request_listings", "market_listings", "market_publish_pokemon", "market_publish_item",
           "market_purchase_pokemon", "market_purchase_item", "market_action_result", "market_payout"
        merge_peer_from_packet(packet)
        AnilLanRework::PlayerMarket.on_packet(packet)
      when "party_invite", "party_accept", "party_decline", "party_leave"
        merge_peer_from_packet(packet)
        AnilLanRework.on_party_packet(packet)
      when "server_shutdown"
        reason = packet["reason"].to_s
        reason = "O servidor está reiniciando para manutenção." if reason.empty?
        pbPlayDecisionSE() rescue nil
        
        # Em vez de fechar o jogo imediatamente, inicia a reconexão automática silenciosa em segundo plano!
        AnilLanRework.start_reconnection($scene, reason)
        return
      when "admin_kick"
        reason = packet["reason"].to_s
        reason = "Violação de regras do servidor" if reason.empty?
        pbPlayBuzzerSE() rescue nil
        
        # Marca como desconexão intencional para o watchdog não atuar
        AnilLanRework.intentional_disconnect = true rescue nil
        
        # Disconnect without saving on kick/ban
        AnilLanRework.disconnect(false) rescue nil
        
        # Abort active battle if any to exit cleanly
        active_ctx = AnilLanRework::BattleSync.active_context rescue nil
        if active_ctx && active_ctx.battle
          active_ctx.battle.decision = 5 rescue nil
        end
        
        # Force Main Title: congela input e vai direto para o título
        AnilLanRework.force_main_title!("aviso_banido.png", _INTL("\\r[Você foi EXPULSO do servidor!]\\n\\nMotivo: \\c[2]#{reason}\\c[0]"))
        return
      when "market_return_pokemon"
        # Devolucao de listagem do mercado (removida pelo admin ou expirada).
        # Chega pela mesma fila dos presentes por ID, que espera o dono voltar.
        #
        # ENTREGA CONFIRMADA, NAO "ENVIADA E TORCER".
        #   O servidor so tira a devolucao da fila quando recebe o ACK daqui. Se
        #   este cliente nao conseguir guardar (equipe E PC lotados) ou o jogo
        #   fechar antes, nenhum ACK sai e o Pokemon e reenviado na proxima
        #   conexao — em vez de sumir.
        #
        #   O outro lado disso e o risco de entrega DUPLICADA (ACK perdido no
        #   caminho), o que num mercado e pior que a perda. Dai a lista de
        #   return_id ja processados, que vive no save: um reenvio do mesmo id e
        #   apenas re-confirmado, nunca adicionado duas vezes.
        begin
          return_id = packet["return_id"].to_s
          ja_feitos = ($PokemonGlobal.anil_devolucoes_recebidas ||= []) rescue []

          if !return_id.empty? && ja_feitos.include?(return_id)
            # Duplicata: nao adiciona de novo, so reconfirma para o servidor
            # poder tirar da fila.
            AnilLanRework.connection.send_packet("market_return_ack", "return_id" => return_id) rescue nil
            AnilLanRework.log("market_return_pokemon: #{return_id} ja processado, apenas reconfirmado") rescue nil
          else
            blob = packet["pokemon"]
            pkmn = AnilLanRework::Serializer.deserialize_pokemon(blob) rescue nil
            if pkmn
              nome = (pkmn.name rescue "Pokemon")
              motivo = packet["reason"].to_s
              pbPlayDecisionSE() rescue nil
              # pbAddPokemon manda para a equipe e, se estiver cheia, para o PC.
              if pbAddPokemon(pkmn)
                pbMEPlay("Item get") rescue nil
                texto = motivo.empty? ? _INTL("{1} voltou do Mercado Global!", nome) :
                                        _INTL("{1} voltou do Mercado Global ({2}).", nome, motivo)
                if defined?(AnilLanRework) && AnilLanRework.respond_to?(:enqueue_popup)
                  AnilLanRework.enqueue_popup(texto, 6.0)
                else
                  pbMessage(texto)
                end
                # Ordem importa: marca e SALVA antes de confirmar. Se o ACK sair
                # primeiro e o jogo cair antes do save, o servidor teria tirado
                # da fila um Pokemon que o save nao guardou.
                ja_feitos << return_id unless return_id.empty?
                ja_feitos.shift while ja_feitos.length > 50
                (Game.save rescue nil) if defined?(Game) && Game.respond_to?(:save)
                AnilLanRework.connection.send_packet("market_return_ack", "return_id" => return_id) rescue nil
              else
                # Sem ACK de proposito: fica na fila do servidor para a proxima vez.
                pbMessage(_INTL("{1} voltou do Mercado Global, mas não há espaço na equipe nem no PC!\nLibere espaço e reconecte para recebê-lo.", nome))
              end
            else
              AnilLanRework.log("market_return_pokemon: blob invalido") rescue nil
            end
          end
        rescue => e
          AnilLanRework.log("market_return_pokemon erro: #{e.class}: #{e.message}") rescue nil
        end

      when "admin_gift"
        item_id = packet["item"].to_s.upcase.to_sym
        qty = packet["qty"].to_i
        qty = 1 if qty <= 0
        begin
          if GameData::Item.exists?(item_id)
            item_name = GameData::Item.get(item_id).name rescue item_id.to_s
            pbPlayDecisionSE() rescue nil
            if $bag.add(item_id, qty)
              pbMEPlay("Item get") rescue nil
              unless packet["global"] == true
                if defined?(AnilLanRework) && AnilLanRework.respond_to?(:enqueue_popup)
                  text = qty > 1 ? _INTL("Você recebeu {1}x {2} de presente!", qty, item_name) : _INTL("Você recebeu {1} de presente!", item_name)
                  AnilLanRework.enqueue_popup(text, 6.0, item_id)
                else
                  pbMessage(_INTL("Você recebeu \\c[2]#{qty}x #{item_name}\\c[0] de presente!"))
                end
              end
            else
              if defined?(AnilLanRework) && AnilLanRework.respond_to?(:enqueue_popup)
                AnilLanRework.enqueue_popup(_INTL("Mochila cheia! Não foi possível receber {1}.", item_name), 6.0, item_id)
              else
                pbMessage(_INTL("Sua mochila está cheia! O item foi perdido!"))
              end
            end
          else
            AnilLanRework.log("admin_gift error: Item #{item_id} nao existe!")
          end
        rescue => e
          AnilLanRework.log("admin_gift error: #{e.message}")
        end
      when "admin_move"
        begin
          map_id = packet["map_id"].to_i
          x = packet["x"].to_i
          y = packet["y"].to_i
          dir = (packet["direction"] || 2).to_i
          
          pbPlayDecisionSE() rescue nil
          if defined?(AnilLanRework) && AnilLanRework.respond_to?(:enqueue_popup)
            AnilLanRework.enqueue_popup(_INTL("Você foi movido!"), 5.0)
          else
            pbMessage(_INTL("Você foi movido!"))
          end
          
          AnilLanRework.perform_unstuck_transfer(map_id, x, y, dir)
        rescue => e
          AnilLanRework.log("admin_move error: #{e.message}")
        end
      when "admin_msg"
        begin
          msg = packet["msg"].to_s
          sender = packet["sender"].to_s
          sender = "ADMINISTRADOR" if sender.empty?
          pbPlayDecisionSE() rescue nil
          AnilLanRework.enqueue_popup(_INTL("[{1}]: {2}", sender, msg), 15.0) rescue nil
        rescue => e
          AnilLanRework.log("admin_msg error: #{e.message}")
        end
      when "admin_edit_money"
        begin
          amount = packet["amount"].to_i
          sender = packet["sender"].to_s
          sender = "ADMINISTRADOR" if sender.empty?
          if $player
            $player.money = amount
            pbPlayDecisionSE() rescue nil
            pbMessage(_INTL("\\c[4][#{sender}]\\c[0] definiu seu dinheiro para \\c[2]${1}\\c[0]!", amount.to_s_formatted)) rescue nil
          end
        rescue => e
          AnilLanRework.log("admin_edit_money error: #{e.message}")
        end
      when "admin_unstuck"
        begin
          healing = $PokemonGlobal.healingSpot
          if healing
            map_id = healing[0]
            x = healing[1]
            y = healing[2]
          else
            map_id = 2
            x = 28
            y = 35
          end
          
          pbPlayDecisionSE() rescue nil
          if defined?(AnilLanRework) && AnilLanRework.respond_to?(:enqueue_popup)
            AnilLanRework.enqueue_popup(_INTL("Você foi desprendido!"), 5.0)
          else
            pbMessage(_INTL("Você foi desprendido!"))
          end
          
          AnilLanRework.perform_unstuck_transfer(map_id, x, y, 2)
        rescue => e
          AnilLanRework.log("admin_unstuck error: #{e.message}")
        end
      when "admin_heal"
        begin
          pbHealAll() rescue nil
          pbPlayDecisionSE() rescue nil
          if defined?(AnilLanRework) && AnilLanRework.respond_to?(:enqueue_popup)
            AnilLanRework.enqueue_popup(_INTL("Sua equipe foi curada pelo administrador!"), 5.0)
          else
            pbMessage(_INTL("Sua equipe foi curada pelo administrador!"))
          end
        rescue => e
          AnilLanRework.log("admin_heal error: #{e.message}")
        end
      when "admin_inspect"
        AnilLanRework.send_inspect_update
      end
    end

    def merge_peer_from_packet(packet)
      peer_id = (packet["internal_id"] || packet["sender_id"] || packet["peer_id"]).to_s
      return if peer_id.empty? || peer_id == AnilLanRework.self_internal_id
      is_new_peer = !AnilLanRework.players.key?(peer_id)
      peer = (AnilLanRework.players[peer_id] ||= AnilLanRework::RemotePeer.new)
      peer.internal_id = peer_id
      peer.apply_state_hash(packet)
      peer.update_from_packet(packet)
      if is_new_peer
        unless packet["map_change"] == true
          if defined?(AnilLanRework) && AnilLanRework.respond_to?(:known_peers) && AnilLanRework.known_peers
            unless AnilLanRework.known_peers.key?(peer_id)
              AnilLanRework.known_peers[peer_id] = true
              AnilLanRework.enqueue_corner_popup("#{peer.name} entrou")
            end
          else
            AnilLanRework.enqueue_corner_popup("#{peer.name} entrou")
          end
        end
      end
      snapshot = [
        packet["type"].to_s,
        peer.map_id.to_i,
        peer.x.to_i,
        peer.y.to_i,
        peer.char_name.to_s,
        peer.battle_busy ? 1 : 0
      ].join("|")
      if is_new_peer || @peer_debug_snapshot[peer_id] != snapshot
        @peer_debug_snapshot[peer_id] = snapshot
        AnilLanRework.log("peer packet type=#{packet["type"]} peer=#{peer_id} map=#{peer.map_id} x=#{peer.x} y=#{peer.y} char=#{peer.char_name} busy=#{peer.battle_busy}")
      end
    end
  end
end

class << Graphics
  alias anil_rework_update update unless method_defined?(:anil_rework_update)
  def update
    if defined?(AnilLanRework) && AnilLanRework.respond_to?(:enabled?) && AnilLanRework.enabled?
      if $DEBUG || $TEST || (defined?(Input::F9) && Input.trigger?(Input::F9) rescue false)
        $DEBUG = false
        $TEST = false
        begin
          # Marca como desconexão intencional para evitar watchdog loops
          AnilLanRework.intentional_disconnect = true rescue nil
          AnilLanRework.disconnect(false) rescue nil
          
          # Force title screen warning
          AnilLanRework.force_main_title!("aviso_banido.png", "O Debug Mode não é permitido no modo online!") rescue nil
        rescue => err
          $scene = pbCallTitle() rescue nil
        end
        # Skip standard frame updates to abort gracefully
        anil_rework_update
        return
      end
    end

    # ================================================================
    # APP RESUME DETECTION (Anti-Background-Freeze)
    # Detecta quando o app voltou do segundo plano (Android/JoiPlay/PC)
    # verificando o gap de tempo real entre frames.
    # Se > 2s, o app provavelmente foi suspenso.
    # ================================================================
    now_real = Time.now.to_f
    @anil_last_update_time ||= now_real
    gap = now_real - @anil_last_update_time
    @anil_last_update_time = now_real

    if gap > 2.0 && !@anil_processing_resume
      @anil_processing_resume = true
      begin
        AnilLanRework.log("[RESUME] App retornou do segundo plano! gap=#{gap.round(1)}s") rescue nil

        # 1. Frame reset imediato — evita que o engine tente renderizar
        #    centenas de frames atrasados (causa principal do freeze)
        Graphics.frame_reset rescue nil

        # 2. Verificar saúde da conexão
        if AnilLanRework.respond_to?(:enabled?) && AnilLanRework.enabled?
          conn = AnilLanRework.connection rescue nil
          if conn
            if conn.connected?
              # Tentar enviar ping para verificar se o socket ainda está vivo
              begin
                conn.send_packet("ping")
                conn.flush_batch
                # Drenar pacotes acumulados durante o background
                conn.read_packets rescue nil
                AnilLanRework.log("[RESUME] Conexão verificada - socket OK")
              rescue => e
                AnilLanRework.log("[RESUME] Socket morto durante background: #{e.message}")
                conn.disconnect rescue nil
              end
            end

            # 3. Se a conexão morreu, não tenta reconectar silenciosamente (evita travar a thread por timeout)
            if !conn.connected? && AnilLanRework.respond_to?(:multiplayer_mode) && AnilLanRework.multiplayer_mode
              AnilLanRework.log("[RESUME] Conexão perdida durante background - watchdog vai tratar")
            end
          end
        end

        # 4. Reset de timestamps dos loops de espera para evitar
        #    que timeouts baseados em Time.now disparem imediatamente.
        #    Apenas ativa a graça de resume se continuarmos conectados, para que o watchdog atue imediatamente
        #    caso tenhamos perdido a conexão.
        if AnilLanRework.connected?
          AnilLanRework.instance_variable_set(:@resume_grace_until, now_real + 3.0) rescue nil
        end

      rescue => e
        AnilLanRework.log("[RESUME] Erro no handler de resume: #{e.class}: #{e.message}") rescue nil
      ensure
        @anil_processing_resume = false
      end
    end

    # Processa mensagens de desconexão pendentes de forma segura no início de cada Graphics.update
    if $game_temp && $game_temp.respond_to?(:anil_pending_disconnect_msg) && $game_temp.anil_pending_disconnect_msg && !@anil_processing_disconnect
      @anil_processing_disconnect = true
      msg = $game_temp.anil_pending_disconnect_msg
      $game_temp.anil_pending_disconnect_msg = nil
      begin
        # Usa banner piscante ao invés de pbMessage — pbMessage chama Graphics.update
        # internamente, causando recursão infinita que crasha o Joiplay.
        clean_msg = msg.to_s.gsub(/\\[a-z]\[[^\]]*\]/, '').gsub("\\n", " ").gsub("\\r", "")
        AnilServerShutdownNotice.show_blinking_notice(clean_msg) rescue nil
        SaveData.mark_values_as_unloaded if defined?(SaveData.mark_values_as_unloaded)
        $scene = pbCallTitle
      rescue => e
        $scene = pbCallTitle rescue nil
      ensure
        @anil_processing_disconnect = false
      end
    end

    # Watchdog para queda inesperada de conexão no multiplayer
    # Pula o watchdog durante o período de graça pós-resume
    resume_grace = AnilLanRework.instance_variable_get(:@resume_grace_until) rescue nil
    skip_watchdog = resume_grace && now_real < resume_grace.to_f

    if !skip_watchdog &&
       defined?(AnilLanRework) && AnilLanRework.respond_to?(:online_session?) && AnilLanRework.online_session? &&
       AnilLanRework.respond_to?(:multiplayer_mode) && AnilLanRework.multiplayer_mode &&
       AnilLanRework.respond_to?(:enabled?) && AnilLanRework.enabled? &&
       !AnilLanRework.connected? && !AnilLanRework.instance_variable_get(:@intentional_disconnect)

      # ⚠️ DAR TEMPO A RECONEXAO ANTES DE DESISTIR.
      #
      # Este watchdog disparava no PRIMEIRO frame em que connected? fosse falso.
      # Ao reiniciar o servidor a sequencia era: chega o server_shutdown, o
      # start_reconnection poe a faixa "Conexao perdida. Tentando reconectar...",
      # o socket fecha — e no frame seguinte isto mandava tudo para o titulo. Da
      # o aspecto de a faixa aparecer um segundo e o jogo cair para a intro,
      # sem nunca dar hipotese ao update_reconnection, que tenta de 3 em 3s.
      #
      # Agora: se nao ha reconexao a decorrer, ARRANCA uma em vez de desistir;
      # e enquanto ela estiver a correr dentro da janela, o watchdog cala-se.
      # So depois de TEMPO_LIMITE_RECONEXAO sem sucesso e que se vai ao titulo.
      agora_wd = Time.now.to_f
      reconectando = AnilLanRework.instance_variable_get(:@reconnecting)

      unless reconectando
        begin
          AnilLanRework.log("[WATCHDOG] Ligacao caiu; a iniciar reconexao (limite #{AnilLanRework::TEMPO_LIMITE_RECONEXAO.round}s).")
          AnilLanRework.start_reconnection($scene, "queda inesperada")
          return
        rescue => e
          AnilLanRework.log("[WATCHDOG] Falha ao iniciar reconexao: #{e.class}: #{e.message}") rescue nil
        end
      else
        inicio = (AnilLanRework.instance_variable_get(:@reconnect_start_time) || agora_wd).to_f
        if agora_wd - inicio < AnilLanRework::TEMPO_LIMITE_RECONEXAO
          # Ainda dentro da janela: deixa o update_reconnection trabalhar.
          @anil_wd_avisado = nil
          return
        end
        unless @anil_wd_avisado
          @anil_wd_avisado = true
          AnilLanRework.log("[WATCHDOG] #{(agora_wd - inicio).round}s sem reconseguir ligacao — a desistir.") rescue nil
        end
      end

      AnilLanRework.intentional_disconnect = true rescue nil
      AnilLanRework.log("[WATCHDOG] Conexão com o servidor perdida inesperadamente!")
      
      # Cancela batalha ativa se houver
      active_ctx = AnilLanRework::BattleSync.active_context rescue nil
      if active_ctx && active_ctx.battle
        active_ctx.battle.decision = 5 rescue nil
      end
      
      # Desconecta e Salva o jogo localmente antes de forçar saída
      AnilLanRework.disconnect(true) rescue nil
      
      # Force Main Title: congela input e vai direto para o título
      AnilLanRework.force_main_title!("servidor_offline.png", _INTL("\\r[Conexão Perdida]\\n\\nA conexão com o servidor foi perdida.\\nO jogo retornará à tela de título."))
      return
    end

    if AnilLanRework.enabled? && AnilLanRework.connected?
      if @anil_rework_updating
        begin
          conn = AnilLanRework.connection
          if conn && conn.connected?
            conn.read_packets rescue nil
            if (Graphics.frame_count % AnilLanRework::KEEPALIVE_TICK).zero?
              conn.send_packet("ping") rescue nil
              conn.flush_batch rescue nil
            end
          end
        rescue
        end
      elsif AnilLanRework.in_battle_wait?
        begin
          conn = AnilLanRework.connection
          if conn && conn.connected?
            conn.read_packets rescue nil
            conn.flush_batch rescue nil
          end
        rescue
        end
      else
        @anil_rework_updating = true
        begin
          AnilLanRework::Router.tick
          AnilLanRework::BattleSync.update_pending_coop_invite unless $game_temp&.in_battle
        rescue => e
          AnilLanRework.log("graphics network update error #{e.class}: #{e.message}")
        ensure
          @anil_rework_updating = false
        end
      end
    end
    if defined?(AnilLanRework) && AnilLanRework.enabled? && AnilLanRework.connected?
      if $scene.is_a?(Scene_Map) && $game_temp && $game_temp.respond_to?(:in_menu) && $game_temp.in_menu
        # Otimização extrema para evitar lag nos menus (Mochila, Pokémon, etc.):
        # Não atualiza mapas/spritesets no JoiPlay (Android) e reduz para a cada 30 frames no PC.
        # Os jogadores ainda são atualizados internamente via Router.tick, mas o processamento gráfico pesado é pausado.
        unless AnilLanRework.joiplay?
          if (Graphics.frame_count % 30).zero?
            $scene.updateMaps rescue nil
            $scene.updateSpritesets rescue nil
          end
        end
      end
    end
    anil_rework_update
  end
end

if defined?(pbSpawnOnStepTaken) && !defined?(anil_rework_original_pbSpawnOnStepTaken)
  alias anil_rework_original_pbSpawnOnStepTaken pbSpawnOnStepTaken
  def pbSpawnOnStepTaken(repel_active)
    if AnilLanRework.enabled? && AnilLanRework.connected? && !AnilLanRework.host? && $game_map
      map_id = $game_map.map_id
      if AnilLanRework::WorldSync.authoritative_for?(map_id) ||
         AnilLanRework::WorldSync.host_reported_same_map_recent?(map_id)
        return
      end
    end
    anil_rework_original_pbSpawnOnStepTaken(repel_active)
  end
end

# --- [REMOVIDO] Bloco de codigo (linhas 5460 a 6407) movido para 000d_Multiplayer_Battle_Trade_RNG_Sync.rb ---

# --- [REMOVIDO] Bloco de codigo (linhas 11427 a 11445) movido para 000d_Multiplayer_Battle_Trade_RNG_Sync.rb ---


# --- [REMOVIDO] Bloco de codigo (linhas 11448 a 11751) movido para 000d_Multiplayer_Battle_Trade_RNG_Sync.rb ---



AnilLanRework.log("AnilLanRework_BattleFreezePatch loaded OK")

class PokemonEncounters
  alias anil_rework_original_have_double_wild_battle? have_double_wild_battle? unless method_defined?(:anil_rework_original_have_double_wild_battle?)

  def have_double_wild_battle?
    return anil_rework_original_have_double_wild_battle? unless AnilLanRework.connected?
    # --- FIX: No double battles for spawned/overworld encounters ---
    return false if $PokemonGlobal&.battlingSpawnedPokemon
    
    peer = AnilLanRework::BattleSync.partner_on_same_map rescue nil
    return false unless peer
    return false if $game_temp.force_single_battle
    return false if AnilLanRework.force_single_wild?
    # -------------------------------------------------------
    return false if pbInSafari?
    return false if $player.able_pokemon_count <= 1
    return rand(100) < AnilLanRework::MULTIPLAYER_DOUBLE_WILD_CHANCE
  end
end

if defined?(WildBattle)
  class << WildBattle
    alias anil_rework_original_start start unless method_defined?(:anil_rework_original_start)

    def start(*args, can_override: false)
      AnilLanRework::BattleSync.sanitize_injected_partner_state!("WildBattle.start") if AnilLanRework.enabled?
      if AnilLanRework.enabled? && AnilLanRework::BattleSync.suppress_local_wild_battle?
        AnilLanRework.log("wild battle suppressed on remote authoritative map map_id=#{$game_map&.map_id}")
        return nil
      end

      # --- OFFLINE/DISCONNECTED SANITIZATION ---
      if !AnilLanRework.connected?
        if defined?($PokemonGlobal) && $PokemonGlobal.partner
          is_mp = ($PokemonGlobal.partner[4] == true || 
                   (AnilLanRework::BattleSync.instance_variable_get(:@partner_injected) rescue false) ||
                   !AnilLanRework::BattleSync.is_story_partner?($PokemonGlobal.partner))
          if is_mp
            $PokemonGlobal.partner = nil
            AnilLanRework::BattleSync.remove_partner rescue nil
            AnilLanRework.log("WildBattle.start (offline): Cleaned leaked multiplayer partner!")
          end
        end
        return anil_rework_original_start(*args, can_override: can_override)
      end
      
      begin
        ctx = AnilLanRework::BattleSync.active_context rescue nil
        if ctx && !(AnilLanRework::BattleSync.instance_variable_get(:@partner_injected) rescue false)
          AnilLanRework.log("WildBattle.start: Clearing stale context!")
          AnilLanRework::BattleSync.clear_context
          ctx = nil
        end
        if ctx && ctx.mode == :coop
          valid_host_bootstrap = (ctx.client_index.to_i == 0 &&
            (AnilLanRework::BattleSync.coop_wild_start_pending?(ctx.battle_id) rescue false))
          if ctx.client_index.to_i == 1 || !valid_host_bootstrap
            AnilLanRework.log(
              "WildBattle.start: Clearing invalid coop context battle_id=#{ctx.battle_id} client_index=#{ctx.client_index}"
            )
            AnilLanRework::BattleSync.remove_partner rescue nil
            AnilLanRework::BattleSync.clear_context
            ctx = nil
          end
        end
        if ctx
          AnilLanRework::BattleSync.clear_coop_wild_start_pending rescue nil
          return anil_rework_original_start(*args, can_override: can_override)
        end
        
        # --- FIX: Limpeza de Parceiro ---
        if defined?($PokemonGlobal) && $PokemonGlobal.partner
          is_mp = ($PokemonGlobal.partner[4] == true || 
                   (AnilLanRework::BattleSync.instance_variable_get(:@partner_injected) rescue false) ||
                   !AnilLanRework::BattleSync.is_story_partner?($PokemonGlobal.partner))
          if is_mp
            $PokemonGlobal.partner = nil
            AnilLanRework::BattleSync.remove_partner if defined?(AnilLanRework::BattleSync.remove_partner)
          end
        end
        # --------------------------------

        if $PokemonSystem.coop_wild_invites == 1 # Off
          return anil_rework_original_start(*args, can_override: can_override)
        end
        peer = AnilLanRework::BattleSync.partner_on_same_map
        # --- FIX: Distância Mínima para Coop ---
        dist_limit = 12
        dist = 999
        if peer
          dist = [(peer.x.to_i - $game_player.x.to_i).abs, (peer.y.to_i - $game_player.y.to_i).abs].max
        end
        
        # Se CTRL estiver pressionado ou longe, pula coop e vai pro single
        if dist > dist_limit || (Input.press?(Input::CTRL) rescue false)
          return anil_rework_original_start(*args, can_override: can_override)
        end
        # ----------------------------------------
        return anil_rework_original_start(*args, can_override: can_override) unless peer

        foe_party = begin
          generate_foes(*args)
        rescue
          []
        end
        coop = AnilLanRework::BattleSync.request_coop_battle(
          kind: :wild,
          foe_party: foe_party,
          can_override: can_override
        )
        if coop.is_a?(Hash)
          AnilLanRework::BattleSync.ensure_wild_rule(foe_party)
        elsif coop == false
          AnilLanRework.log("wild battle blocked peer unavailable peer=#{peer.internal_id} busy=#{peer.battle_busy == true} menu=#{peer.menu_open == true}")
          return nil
        elsif coop == :declined
          AnilLanRework::BattleSync.sanitize_injected_partner_state!("wild_declined_fallback")
          setBattleRule("nopartner") rescue nil
          AnilLanRework.log("wild battle local decline fallback peer=#{peer.internal_id} busy=#{peer.battle_busy == true}")
        else
          AnilLanRework.log("wild battle local fallback peer=#{peer.internal_id} busy=#{peer.battle_busy == true}")
        end
        foe_party.empty? ? anil_rework_original_start(*args, can_override: can_override) :
                          anil_rework_original_start(*foe_party, can_override: can_override)
      ensure
        if defined?($PokemonGlobal) && $PokemonGlobal.partner
          is_mp = ($PokemonGlobal.partner[4] == true || 
                   (AnilLanRework::BattleSync.instance_variable_get(:@partner_injected) rescue false) ||
                   !AnilLanRework::BattleSync.is_story_partner?($PokemonGlobal.partner))
          if is_mp
            $PokemonGlobal.partner = nil
            AnilLanRework::BattleSync.remove_partner rescue nil
            AnilLanRework.log("WildBattle.start (ensure): Cleaned up coop partner after battle end!")
          end
        end
      end
    end
  end
end

if defined?(pbBattleOnStepTaken) && !defined?(anil_rework_original_pbBattleOnStepTaken)
  alias anil_rework_original_pbBattleOnStepTaken pbBattleOnStepTaken
  def pbBattleOnStepTaken(repel_active)
    AnilLanRework::BattleSync.sanitize_injected_partner_state!("pbBattleOnStepTaken") if AnilLanRework.enabled?
    if AnilLanRework.enabled? && AnilLanRework::BattleSync.suppress_local_wild_battle?
      AnilLanRework.log("step encounter suppressed on remote authoritative map map_id=#{$game_map&.map_id}")
      return
    end
    anil_rework_original_pbBattleOnStepTaken(repel_active)
  end
end

if defined?(pbEncounter) && !defined?(anil_rework_original_pbEncounter)
  alias anil_rework_original_pbEncounter pbEncounter
  def pbEncounter(enc_type, only_single = true)
    AnilLanRework::BattleSync.sanitize_injected_partner_state!("pbEncounter") if AnilLanRework.enabled?
    if AnilLanRework.enabled? && AnilLanRework::BattleSync.suppress_local_wild_battle?
      AnilLanRework.log("direct encounter suppressed on remote authoritative map enc_type=#{enc_type}")
      return false
    end
    anil_rework_original_pbEncounter(enc_type, only_single)
  end
end

if defined?(TrainerBattle)
  class << TrainerBattle
    alias anil_rework_original_start start unless method_defined?(:anil_rework_original_start)
    alias anil_rework_original_start_core start_core unless method_defined?(:anil_rework_original_start_core)

    def start(*args)
      # --- OFFLINE/DISCONNECTED SANITIZATION ---
      if !AnilLanRework.connected?
        if defined?($PokemonGlobal) && $PokemonGlobal.partner
          is_mp = ($PokemonGlobal.partner[4] == true || 
                   (AnilLanRework::BattleSync.instance_variable_get(:@partner_injected) rescue false) ||
                   !AnilLanRework::BattleSync.is_story_partner?($PokemonGlobal.partner))
          if is_mp
            $PokemonGlobal.partner = nil
            AnilLanRework::BattleSync.remove_partner rescue nil
            AnilLanRework.log("TrainerBattle.start (offline): Cleaned leaked multiplayer partner!")
          end
        end
        return anil_rework_original_start(*args)
      end
      
      begin
        if AnilLanRework::BattleSync.active_context && !(AnilLanRework::BattleSync.instance_variable_get(:@partner_injected) rescue false)
          AnilLanRework.log("TrainerBattle.start: Clearing stale context!")
          AnilLanRework::BattleSync.clear_context
        end
        return anil_rework_original_start(*args) if AnilLanRework::BattleSync.active_context

        if defined?($game_temp) && $game_temp.instance_variable_get(:@anil_skip_coop_invite)
          $game_temp.instance_variable_set(:@anil_skip_coop_invite, false)
          return anil_rework_original_start(*args)
        end

        # --- FIX: Limpeza de Parceiro ---
        if defined?($PokemonGlobal) && $PokemonGlobal.partner
          is_mp = ($PokemonGlobal.partner[4] == true || 
                   (AnilLanRework::BattleSync.instance_variable_get(:@partner_injected) rescue false) ||
                   !AnilLanRework::BattleSync.is_story_partner?($PokemonGlobal.partner))
          if is_mp
            $PokemonGlobal.partner = nil
            AnilLanRework::BattleSync.remove_partner if defined?(AnilLanRework::BattleSync.remove_partner)
          end
        end
        # --------------------------------
        
        if $PokemonSystem.coop_trainer_invites == 1 # Off
          return anil_rework_original_start(*args)
        end
        peer = AnilLanRework::BattleSync.partner_on_same_map
        # --- FIX: Distância Mínima para Coop ---
        dist_limit = 12
        dist = 999
        if peer
          dist = [(peer.x.to_i - $game_player.x.to_i).abs, (peer.y.to_i - $game_player.y.to_i).abs].max
        end
        if dist > dist_limit || (Input.press?(Input::CTRL) rescue false)
          return anil_rework_original_start(*args)
        end
        # ----------------------------------------
        return anil_rework_original_start(*args) unless peer

        foe_trainers, = begin
          generate_foes(*args)
        rescue
          [nil]
        end
        coop = AnilLanRework::BattleSync.request_coop_battle(
          kind: :trainer,
          foe_trainers: foe_trainers
        )
        if coop == :declined
          AnilLanRework::BattleSync.sanitize_injected_partner_state!("trainer_declined_fallback")
          setBattleRule("nopartner") rescue nil
          return anil_rework_original_start(*args)
        end
        return anil_rework_original_start(*args) unless coop

        AnilLanRework::BattleSync.ensure_trainer_rule
        anil_rework_original_start(*args)
      ensure
        if defined?($PokemonGlobal) && $PokemonGlobal.partner
          is_mp = ($PokemonGlobal.partner[4] == true || 
                   (AnilLanRework::BattleSync.instance_variable_get(:@partner_injected) rescue false) ||
                   !AnilLanRework::BattleSync.is_story_partner?($PokemonGlobal.partner))
          if is_mp
            $PokemonGlobal.partner = nil
            AnilLanRework::BattleSync.remove_partner rescue nil
            AnilLanRework.log("TrainerBattle.start (ensure): Cleaned up coop partner after battle end!")
          end
        end
      end
    end
  end
end

if defined?(BattleCreationHelperMethods)
  class << BattleCreationHelperMethods
    alias anil_rework_original_partner_can_participate partner_can_participate? unless method_defined?(:anil_rework_original_partner_can_participate)
    alias anil_rework_original_set_up_player_trainers set_up_player_trainers unless method_defined?(:anil_rework_original_set_up_player_trainers)
    alias anil_rework_original_prepare_battle prepare_battle unless method_defined?(:anil_rework_original_prepare_battle)
  end

  def BattleCreationHelperMethods.partner_can_participate?(foe_party)
    ctx = AnilLanRework::BattleSync.active_context rescue nil
    if ctx && ctx.mode == :coop && $PokemonGlobal&.partner && Array($PokemonGlobal.partner[3]).length > 0
      return true
    end
    anil_rework_original_partner_can_participate(foe_party)
  end

  def BattleCreationHelperMethods.set_up_player_trainers(foe_party)
    ctx = AnilLanRework::BattleSync.active_context rescue nil
    if ctx && ctx.mode == :pvp && !Array(ctx.local_party_blob).empty?
      local_party = AnilLanRework::BattleSync.selected_pvp_party(ctx)
      if !local_party.empty?
        result = [[$player], [], local_party, [0]]
        AnilLanRework.log("pvp setup battle_id=#{ctx.battle_id} local_party=#{AnilLanRework::BattleSync.party_species_names(local_party).inspect} foe_party=#{AnilLanRework::BattleSync.party_species_names(foe_party).inspect} custom=#{AnilLanRework::BattleSync.custom_duel_rules?(ctx.rules)} rule=#{($game_temp.battle_rules['size'] rescue nil).inspect} trainers=1")
        return result
      end
    end
    if ctx && ctx.mode == :coop
      peer = AnilLanRework.players[ctx.partner_id.to_s] rescue nil
      partner_party = Array($PokemonGlobal.partner && $PokemonGlobal.partner[3])
      AnilLanRework.log("coop setup entry battle_id=#{ctx.battle_id} partner_global=#{partner_party.length} peer_blob=#{Array(peer&.party_blob).length} foe_party=#{Array(foe_party).length}")
      if partner_party.empty? && peer
        hydrated_party = AnilLanRework::Serializer.deserialize_party(peer.party_blob)
        if !hydrated_party.empty?
          trainer_type = AnilLanRework.trainer_type_for_character(peer.char_name, GameData::TrainerType.keys.first)
          trainer_name = peer.name.to_s.empty? ? "Parceiro" : peer.name.to_s
          $PokemonGlobal.partner = [trainer_type, trainer_name, rand(65_535), hydrated_party, true]
          partner_party = hydrated_party
          AnilLanRework.log("coop partner rehydrated battle_id=#{ctx.battle_id} party_size=#{hydrated_party.length}")
        else
          AnilLanRework.log("coop partner rehydrate skipped battle_id=#{ctx.battle_id} empty_blob=true")
        end
      end
      if !partner_party.empty?
        trainer_type = ($PokemonGlobal.partner && $PokemonGlobal.partner[0]) || GameData::TrainerType.keys.first
        trainer_name = ($PokemonGlobal.partner && $PokemonGlobal.partner[1]).to_s
        trainer_name = peer.name.to_s if trainer_name.empty? && peer
        trainer_name = "Parceiro" if trainer_name.empty?
        trainer_id = ($PokemonGlobal.partner && $PokemonGlobal.partner[2]) || rand(65_535)
        ally = begin
          NPCTrainer.new(trainer_name, trainer_type)
        rescue
          Trainer.new(trainer_name, trainer_type)
        end
        ally.id = trainer_id if ally.respond_to?(:id=)
        ally.party = partner_party
        ally_items = []
        ally_items[1] = ally.items.clone rescue nil
        pokemon_array = []
        $player.party.each { |pkmn| pokemon_array << pkmn }
        party_starts = [0, pokemon_array.length]
        partner_party.each { |pkmn| pokemon_array << pkmn }

        foe_len = Array(foe_party).length
        desired_rule = foe_len >= 2 ? "2v#{[foe_len, 3].min}" : "2v1"
        current_rule = ($game_temp.battle_rules["size"] || "").to_s.downcase
        if current_rule.empty? || current_rule == "single" || current_rule.start_with?("1v")
          setBattleRule(desired_rule)
          AnilLanRework.log("coop setup override size battle_id=#{ctx.battle_id} from=#{current_rule.inspect} to=#{desired_rule}")
        end

        result = [[$player, ally], ally_items, pokemon_array, party_starts]
        AnilLanRework.log("coop setup trainers battle_id=#{ctx.battle_id} foe_party=#{Array(foe_party).length} partner_party=#{partner_party.length} rule=#{($game_temp.battle_rules['size'] rescue nil).inspect} forced=true")
        AnilLanRework.log("coop setup result battle_id=#{ctx.battle_id} trainers=#{result[0].length} party_size=#{result[2].length} starts=#{result[3].inspect}")
        return result
      end
      AnilLanRework.log("coop setup trainers battle_id=#{ctx.battle_id} foe_party=#{Array(foe_party).length} partner_party=#{partner_party.length} rule=#{($game_temp.battle_rules['size'] rescue nil).inspect} forced=false")
    end

    result = anil_rework_original_set_up_player_trainers(foe_party)

    if ctx && ctx.mode == :coop
      trainers, _ally_items, player_party, party_starts = result
      AnilLanRework.log("coop setup result battle_id=#{ctx.battle_id} trainers=#{Array(trainers).length} party_size=#{Array(player_party).length} starts=#{Array(party_starts).inspect}")
    end
    result
  end

  def BattleCreationHelperMethods.prepare_battle(battle)
    anil_rework_original_prepare_battle(battle)
    battle.anil_rework_force_valid_coop_layout!("prepare_battle") if battle.respond_to?(:anil_rework_force_valid_coop_layout!)
  end
end

# --- [REMOVIDO] Bloco de codigo (linhas 12107 a 13075) movido para 000d_Multiplayer_Battle_Trade_RNG_Sync.rb ---

class Spriteset_Map
  def self.viewport
    if $scene.is_a?(Scene_Map)
      if $scene.respond_to?(:spriteset) && $scene.spriteset
        vp = $scene.spriteset.instance_variable_get(:@viewport1) rescue nil
        return vp if vp
      elsif $scene.respond_to?(:spritesets) && $scene.spritesets
        s = $scene.spritesets[$game_map.map_id] rescue nil
        s ||= $scene.spritesets.values.first rescue nil
        vp = s.instance_variable_get(:@viewport1) rescue nil if s
        return vp if vp
      end
    end
    @@viewport1 rescue nil
  end

  alias anil_rework_initialize initialize unless method_defined?(:anil_rework_initialize) || private_method_defined?(:anil_rework_initialize)
  alias anil_rework_update update unless method_defined?(:anil_rework_update)
  alias anil_rework_dispose dispose unless method_defined?(:anil_rework_dispose)

  def initialize(*args)
    @anil_rework_remote_sprites = {}
    @anil_rework_remote_followers = {}
    @anil_rework_peer_busy_effects = {}
    @anil_rework_peer_busy_snapshot = {}
    @anil_rework_peer_map_snapshot = {}
    @anil_rework_peer_visibility_snapshot = {}
    @anil_rework_peer_busy_blink_timers = {}
    @anil_rework_peer_busy_blink_phases = {}
    
    @anil_rework_peer_busy_balloon_type = {}
    @anil_rework_peer_busy_balloon_frame = {}
    @anil_rework_peer_busy_balloon_ticks = {}
    @anil_rework_peer_busy_balloon_state = {}
    anil_rework_initialize(*args)
  end

  def ensure_busy_balloon_sprite(peer_id, reason, viewport)
    sprite = @anil_rework_peer_busy_effects[peer_id]
    current_type = @anil_rework_peer_busy_balloon_type[peer_id]
    
    if sprite && !(sprite.disposed? rescue false) && current_type == reason
      return sprite
    end
    
    sprite&.dispose rescue nil
    @anil_rework_peer_busy_effects.delete(peer_id)
    
    sprite = Sprite.new(viewport)
    @anil_rework_peer_busy_balloon_type[peer_id] = reason
    @anil_rework_peer_busy_balloon_frame[peer_id] = 0
    @anil_rework_peer_busy_balloon_ticks[peer_id] = 0
    @anil_rework_peer_busy_balloon_state[peer_id] ||= :shaking
    
    case reason
    when :pvp
      sprite.bitmap = Bitmap.new("Graphics/Animations/balloon_vs.png") rescue nil
      if sprite.bitmap
        sprite.src_rect = Rect.new(0, 0, 48, 48)
        sprite.ox = 24
        sprite.oy = 48
      end
    when :bag, :menu
      sprite.bitmap = Bitmap.new("Graphics/Animations/balloon_gear.png") rescue nil
      if sprite.bitmap
        sprite.src_rect = Rect.new(0, 0, 48, 48)
        sprite.ox = 24
        sprite.oy = 48
      end
    when :afk
      sprite.bitmap = Bitmap.new("Graphics/Animations/balloon_clock.png") rescue nil
      if sprite.bitmap
        sprite.src_rect = Rect.new(0, 0, 48, 48)
        sprite.ox = 24
        sprite.oy = 48
      end
    when :battle
      if AnilLanRework::REMOTE_CATCH_BALLOON_ENABLED
        sprite.bitmap = Bitmap.new("Graphics/Animations/catch_balloon.png") rescue nil
        if sprite.bitmap
          sprite.src_rect = Rect.new(0, 0, 48, 48)
          sprite.ox = 24
          sprite.oy = 48
          sprite.zoom_x = 1.0
          sprite.zoom_y = 1.0
        end
      else
        sprite.bitmap = Bitmap.new("Graphics/Animations/balloon_pokeball.png") rescue nil
        if sprite.bitmap
          sprite.src_rect = Rect.new(0, 0, 48, 48)
          sprite.ox = 24
          sprite.oy = 48
        end
      end
    else # :menu or others
      sprite.bitmap = AnilLanRework::BusyBalloon.create_bitmap
      if sprite.bitmap && sprite.bitmap.width == 192
        sprite.ox = 96
        sprite.oy = 176
      else
        sprite.ox = sprite.bitmap.width / 2 rescue 0
        sprite.oy = (sprite.bitmap.height + 40) rescue 0
      end
    end
    sprite.z = 999
    @anil_rework_peer_busy_effects[peer_id] = sprite
    sprite
  end

  def trigger_capture_balloon_state(peer_id, peer)
    viewport = @viewport1 rescue nil
    viewport ||= Spriteset_Map.viewport rescue nil
    return unless viewport
    
    # Force creation or retrieval of the battle Poké Ball balloon sprite
    ensure_busy_balloon_sprite(peer_id, :battle, viewport)
    @anil_rework_peer_busy_balloon_state[peer_id] = :captured
    update_busy_balloon_for_peer(peer_id, peer, true, viewport) rescue nil
  end

  def update_busy_balloon_for_peer(peer_id, peer, visible, viewport = nil)
    sprite = @anil_rework_peer_busy_effects[peer_id]
    state = @anil_rework_peer_busy_balloon_state[peer_id] || :shaking
    
    # Se capturou, forçamos a exibição até terminar de rodar a animação de plim
    if AnilLanRework::REMOTE_CATCH_BALLOON_ENABLED
      if state == :captured || state == :captured_hold
        visible = true
      elsif state == :done
        visible = false
      end
    end
    
    unless visible
      sprite&.dispose rescue nil
      @anil_rework_peer_busy_effects.delete(peer_id)
      @anil_rework_peer_busy_blink_timers.delete(peer_id)
      @anil_rework_peer_busy_blink_phases.delete(peer_id)
      @anil_rework_peer_busy_balloon_type.delete(peer_id)
      @anil_rework_peer_busy_balloon_frame.delete(peer_id)
      @anil_rework_peer_busy_balloon_ticks.delete(peer_id)
      if !peer || !peer.occupied_reason
        @anil_rework_peer_busy_balloon_state.delete(peer_id)
      end
      return
    end
    
    viewport ||= (@viewport1 rescue nil)
    viewport ||= (Spriteset_Map.viewport rescue nil)
    return unless viewport
    remote_sprite = @anil_rework_remote_sprites[peer_id]
    return unless remote_sprite && !(remote_sprite.disposed? rescue false)
    
    reason = peer.occupied_reason || @anil_rework_peer_busy_balloon_type[peer_id] || :menu
    sprite = ensure_busy_balloon_sprite(peer_id, reason, viewport)
    
    # Atualiza posição acima do jogador (se o nameplate estiver visível, posiciona acima dele)
    sprite.x = remote_sprite.x
    name_sprite = remote_sprite.instance_variable_get(:@peer_name_sprite)
    if name_sprite && !(name_sprite.disposed? rescue true) && name_sprite.visible
      sprite.y = name_sprite.y - 29
    else
      sprite.y = remote_sprite.y - 49
    end
    
    # Configura propriedades de desenho específicas de cada tipo
    if reason == :battle && AnilLanRework::REMOTE_CATCH_BALLOON_ENABLED
      frame = @anil_rework_peer_busy_balloon_frame[peer_id] || 0
      ticks = @anil_rework_peer_busy_balloon_ticks[peer_id] || 0
      
      if state == :shaking
        ticks += 1
        if ticks >= 6 # Velocidade de animação das oscilações da pokebola
          ticks = 0
          frame = (frame + 1) % 4
        end
        @anil_rework_peer_busy_balloon_frame[peer_id] = frame
        @anil_rework_peer_busy_balloon_ticks[peer_id] = ticks
        if sprite.bitmap
          sprite.src_rect.x = frame * 48
        end
        
      elsif state == :captured
        # Toca plim e muda para frame 4
        pbPlayDecisionSE() rescue nil
        pbSEPlay("Saint6", 80, 100) rescue nil
        frame = 4
        ticks = 0
        @anil_rework_peer_busy_balloon_frame[peer_id] = frame
        @anil_rework_peer_busy_balloon_ticks[peer_id] = ticks
        @anil_rework_peer_busy_balloon_state[peer_id] = :captured_hold
        if sprite.bitmap
          sprite.src_rect.x = frame * 48
        end
        
      elsif state == :captured_hold
        ticks += 1
        if ticks == 8
          frame = 5 # checkmark final brilhante
          if sprite.bitmap
            sprite.src_rect.x = frame * 48
          end
        elsif ticks >= 30 # Tempo total de retenção do checkmark na tela
          @anil_rework_peer_busy_balloon_state[peer_id] = :done
          update_busy_balloon_for_peer(peer_id, peer, false, viewport)
          return
        end
        @anil_rework_peer_busy_balloon_frame[peer_id] = frame
        @anil_rework_peer_busy_balloon_ticks[peer_id] = ticks
      end
    elsif [:battle, :pvp, :bag, :afk, :menu].include?(reason)
      sprite.src_rect.x = 0 if sprite.bitmap
    end

    # Aplica lógica de visibilidade/piscar unificada para todos os balões
    if reason == :battle && AnilLanRework::REMOTE_CATCH_BALLOON_ENABLED && (state == :captured || state == :captured_hold)
      sprite.visible = true
      sprite.opacity = 255
    else
      if AnilLanRework::REMOTE_BUSY_BALLOON_BLINK_ENABLED
        current_time = (System.uptime rescue Time.now.to_f).to_f
        @anil_rework_peer_busy_blink_timers[peer_id] ||= current_time
        @anil_rework_peer_busy_blink_phases[peer_id] ||= 0
        
        time_elapsed = current_time - @anil_rework_peer_busy_blink_timers[peer_id]
        if time_elapsed > AnilLanRework::REMOTE_BUSY_BALLOON_BLINK_INTERVAL
          @anil_rework_peer_busy_blink_timers[peer_id] = current_time
          @anil_rework_peer_busy_blink_phases[peer_id] = (@anil_rework_peer_busy_blink_phases[peer_id] + 1) % 2
        end
        
        sprite.visible = @anil_rework_peer_busy_blink_phases[peer_id] == 0
        sprite.opacity = sprite.visible ? ([:battle, :pvp, :bag, :afk, :menu].include?(reason) ? 255 : 220) : 0
      else
        sprite.visible = true
        sprite.opacity = [:battle, :pvp, :bag, :afk, :menu].include?(reason) ? 255 : 220
      end
    end
  rescue => e
    AnilLanRework.log("busy balloon update error #{e.class}: #{e.message}")
  end

  def show_busy_balloon_for_peer(peer_id, peer)
    viewport = @viewport1 rescue nil
    viewport ||= Spriteset_Map.viewport rescue nil
    return unless viewport && peer
    update_busy_balloon_for_peer(peer_id, peer, true, viewport)
  end

  def update
    anil_rework_update
    
    # Evita que a atualização de peers seja executada duas vezes por frame 
    # se o patch de FPS estiver ativo (que gerencia isso de forma otimizada).
    return if defined?(AnilProfiler)

    unless AnilLanRework.enabled? && AnilLanRework.connected? && $game_map
      return
    end
    unless @map.map_id == $game_map.map_id
      return
    end

    viewport = @viewport1 rescue nil
    viewport ||= Spriteset_Map.viewport rescue nil
    unless viewport
      return
    end

    current_map_id = $game_map.map_id

    AnilLanRework.players.each do |peer_id, peer|
      # Garante que não recrie o próprio jogador
      next if peer_id.to_s == AnilLanRework.self_internal_id.to_s

      peer_map_id = peer.map_id
      on_this_map = peer_map_id == current_map_id && !AnilLanRework::WorldSync.hide_peer_sprite?(peer)
      visibility_snapshot = "#{peer_map_id}|#{current_map_id}|#{on_this_map ? 1 : 0}|#{peer.char_name}"
      if @anil_rework_peer_visibility_snapshot[peer_id] != visibility_snapshot
        @anil_rework_peer_visibility_snapshot[peer_id] = visibility_snapshot
        AnilLanRework.log("peer visibility peer=#{peer_id} peer_map=#{peer_map_id} current_map=#{current_map_id} visible=#{on_this_map} char=#{peer.char_name}")
      end
      unless on_this_map
        if @anil_rework_remote_sprites[peer_id]
          @anil_rework_remote_sprites[peer_id].dispose rescue nil
          @anil_rework_remote_sprites.delete(peer_id)
          @anil_rework_peer_busy_effects[peer_id]&.dispose rescue nil
          @anil_rework_peer_busy_effects.delete(peer_id)
          @anil_rework_peer_busy_blink_timers.delete(peer_id)
          @anil_rework_peer_busy_blink_phases.delete(peer_id)
          @anil_rework_peer_busy_snapshot.delete(peer_id)
          @anil_rework_peer_map_snapshot.delete(peer_id)
        end
        if @anil_rework_remote_followers[peer_id]
          @anil_rework_remote_followers[peer_id][0].dispose rescue nil
          @anil_rework_remote_followers.delete(peer_id)
        end
        next
      end
      busy_state = peer.occupied_reason
      previous_busy_state = @anil_rework_peer_busy_snapshot.fetch(peer_id, :__unknown__)
      if previous_busy_state != busy_state
        @anil_rework_peer_busy_snapshot[peer_id] = busy_state
      end

      peer.update_anim

      unless @anil_rework_remote_sprites[peer_id]
        @anil_rework_remote_sprites[peer_id] = Sprite_Character.new(viewport, peer)
        @anil_rework_peer_map_snapshot[peer_id] = peer_map_id
        AnilLanRework.log("remote sprite created peer=#{peer_id} map=#{peer_map_id} x=#{peer.x} y=#{peer.y} char=#{peer.char_name}")
      end
      @anil_rework_remote_sprites[peer_id].update rescue nil
      update_busy_balloon_for_peer(peer_id, peer, !busy_state.nil?, viewport)

      follower_name = peer.follower_char.to_s
      # Verifica se o nome do follower é válido e não é um tile ID (que causaria o bug da árvore)
      if follower_name.empty? || follower_name.to_i > 0
        if @anil_rework_remote_followers[peer_id]
          @anil_rework_remote_followers[peer_id][0].dispose rescue nil
          @anil_rework_remote_followers.delete(peer_id)
        end
        next
      end

      unless @anil_rework_remote_followers[peer_id]
        fake = AnilLanRework::RemotePeer.new
        follower_sprite = Sprite_Character.new(viewport, fake) rescue nil
        @anil_rework_remote_followers[peer_id] = [follower_sprite, fake] if follower_sprite
      end
      next unless @anil_rework_remote_followers[peer_id]

      fake = @anil_rework_remote_followers[peer_id][1]
      fake.character_name = follower_name
      fake.map_id = peer_map_id
      fake.status_id = peer.status_id
      fake.follower_super_shiny = peer.follower_super_shiny
      fake.character_hue = (peer.follower_super_shiny ? peer.follower_hue : 0)
      fake.remote_follower_visual = true
      fake.calculate_bush_depth rescue nil
      if peer.f_rx && peer.f_rx > 0
        target_real_x = peer.f_rx
        target_real_y = peer.f_ry
        target_x = peer.f_x
        target_y = peer.f_y
        target_dir = peer.f_dir
        target_pat = peer.f_pat
        use_sync = true
      else
        ox = (peer.direction == 6 ? -1 : peer.direction == 4 ? 1 : 0)
        oy = (peer.direction == 2 ? -1 : peer.direction == 8 ? 1 : 0)
        target_real_x = peer.real_x + (ox * peer.trx)
        target_real_y = peer.real_y + (oy * peer.try)
        target_x = peer.x + ox
        target_y = peer.y + oy
        target_dir = peer.direction
        target_pat = peer.pattern
        use_sync = false
      end

      fake.target_x = target_real_x
      fake.target_y = target_real_y

      if !fake.instance_variable_get(:@initialized_follower_pos) || 
         (fake.real_x - target_real_x).abs > (peer.trx * AnilLanRework::RemotePeer::TELEPORTE_TILES) || 
         (fake.real_y - target_real_y).abs > (peer.try * AnilLanRework::RemotePeer::TELEPORTE_TILES)
        fake.real_x = target_real_x
        fake.real_y = target_real_y
        fake.x = target_x
        fake.y = target_y
        fake.direction = target_dir
        fake.pattern = target_pat
        fake.instance_variable_set(:@initialized_follower_pos, true)
      else
        if use_sync
          fake.x = target_x
          fake.y = target_y
          fake.direction = target_dir
          fake.pattern = target_pat
          
          # Interpola real_x/real_y suavemente em direção à posição sincronizada do parceiro
          dx = fake.target_x - fake.real_x
          dy = fake.target_y - fake.real_y
          distance = [dx.abs, dy.abs].max
          if distance > 0
            base_step = [(peer.trx / 10.0).ceil, 1].max
            step = [[(distance / 6.0).ceil, base_step].max, peer.trx].min
            fake.real_x += (dx > 0 ? [step, dx].min : [-step, dx].max)
            fake.real_y += (dy > 0 ? [step, dy].min : [-step, dy].max)
          end
        else
          # Movimentação baseada em passos discretos e ciclos de pernas correspondentes, idêntica ao player e NPCs do Life System
          fake.update_anim
          # Determina a direção do movimento baseada na diferença real
          dx = target_real_x - fake.real_x
          dy = target_real_y - fake.real_y
          if dx.abs > 5 || dy.abs > 5
            if dx.abs > dy.abs
              fake.direction = dx > 0 ? 6 : 4
            else
              fake.direction = dy > 0 ? 2 : 8
            end
          else
            fake.direction = peer.direction
          end
        end
      end
      @anil_rework_remote_followers[peer_id][0].update rescue nil
    end

    stale_ids = (@anil_rework_remote_sprites.keys + @anil_rework_remote_followers.keys).uniq
    stale_ids.each do |peer_id|
      peer = AnilLanRework.players[peer_id]
      keep = peer && peer.map_id == current_map_id && !AnilLanRework::WorldSync.hide_peer_sprite?(peer)
      next if keep
      @anil_rework_remote_sprites[peer_id]&.dispose rescue nil
      @anil_rework_remote_sprites.delete(peer_id)
      @anil_rework_peer_busy_effects[peer_id]&.dispose rescue nil
      @anil_rework_peer_busy_effects.delete(peer_id)
      @anil_rework_peer_busy_blink_timers.delete(peer_id)
      @anil_rework_peer_busy_blink_phases.delete(peer_id)
      @anil_rework_peer_busy_snapshot.delete(peer_id)
      @anil_rework_peer_map_snapshot.delete(peer_id)
      @anil_rework_peer_visibility_snapshot.delete(peer_id)
      
      @anil_rework_peer_busy_balloon_type.delete(peer_id)
      @anil_rework_peer_busy_balloon_frame.delete(peer_id)
      @anil_rework_peer_busy_balloon_ticks.delete(peer_id)
      @anil_rework_peer_busy_balloon_state.delete(peer_id)
      @anil_rework_remote_followers[peer_id]&.first&.dispose rescue nil
      @anil_rework_remote_followers.delete(peer_id)
    end
  end

  def dispose
    @anil_rework_remote_sprites&.each_value { |sprite| sprite.dispose rescue nil }
    @anil_rework_remote_sprites&.clear
    @anil_rework_remote_followers&.each_value { |pair| pair[0].dispose rescue nil }
    @anil_rework_remote_followers&.clear
    @anil_rework_peer_busy_effects&.each_value { |sprite| sprite.dispose rescue nil }
    @anil_rework_peer_busy_effects&.clear
    @anil_rework_peer_busy_blink_timers&.clear
    @anil_rework_peer_busy_blink_phases&.clear
    @anil_rework_peer_busy_snapshot&.clear
    @anil_rework_peer_map_snapshot&.clear
    
    @anil_rework_peer_busy_balloon_type&.clear
    @anil_rework_peer_busy_balloon_frame&.clear
    @anil_rework_peer_busy_balloon_ticks&.clear
    @anil_rework_peer_busy_balloon_state&.clear
    anil_rework_dispose
  end
end

if defined?(Sprite_Character)
  class Sprite_Character
    alias anil_rework_remote_follower_status_update update unless method_defined?(:anil_rework_remote_follower_status_update)

    def update
      anil_rework_remote_follower_status_update
      return unless @character.is_a?(AnilLanRework::RemotePeer)
      return unless @character.remote_follower_visual
      
      desired_status_tone = AnilLanRework::REMOTE_STATUS_TONES[@character.status_id]
      if desired_status_tone
        env_tone = self.tone || Tone.new(0, 0, 0, 0)
        combined_tone = Tone.new(
          (env_tone.red + desired_status_tone.red).clamp(-255, 255),
          (env_tone.green + desired_status_tone.green).clamp(-255, 255),
          (env_tone.blue + desired_status_tone.blue).clamp(-255, 255),
          (env_tone.gray + desired_status_tone.gray).clamp(-255, 255)
        )
        self.tone = combined_tone rescue nil
      end
    rescue
    end
  end
end

class Game_Character
  if method_defined?(:update_move) && !method_defined?(:anil_rework_update_move)
    alias anil_rework_update_move update_move
    def update_move
      return if self.instance_variable_get(:@anil_remote_sync)
      anil_rework_update_move
    end
  end
end

class Game_Event
  alias anil_rework_update update unless method_defined?(:anil_rework_update)
  alias anil_rework_update_command update_command unless method_defined?(:anil_rework_update_command)
  alias anil_rework_check_event_trigger_auto check_event_trigger_auto unless method_defined?(:anil_rework_check_event_trigger_auto)
  if method_defined?(:check_event_trigger_touch) && !method_defined?(:anil_rework_check_event_trigger_touch)
    alias anil_rework_check_event_trigger_touch check_event_trigger_touch
  end

  def update
    is_poke = (defined?(Game_PokeEvent) && self.is_a?(Game_PokeEvent))
    if is_poke && AnilLanRework.enabled? && (AnilLanRework::WorldSync.authoritative_for?(@map_id) || self.instance_variable_get(:@anil_remote_sync))
      # Bypassa a movimentação autônoma local do Game_Event, mas mantém a animação básica via Game_Character
      super rescue nil
      AnilLanRework::WorldSync.interpolate_event!(self)
    else
      anil_rework_update
    end
  end

  def update_command
    # Permitir a execução local de comandos de eventos (diálogos, portas, baús, etc.) no multiplayer
    anil_rework_update_command
  end

  def check_event_trigger_auto
    # Permitir execução local de eventos automáticos
    anil_rework_check_event_trigger_auto
  end

  def check_event_trigger_touch(*args)
    # Permitir execução local de eventos de toque (portais de teletransporte, etc.)
    return anil_rework_check_event_trigger_touch(*args) if respond_to?(:anil_rework_check_event_trigger_touch, true)
    false
  end
end

class Game_Player
  alias anil_rework_update_command_new update_command_new unless method_defined?(:anil_rework_update_command_new)
  alias anil_rework_update_event_triggering update_event_triggering unless method_defined?(:anil_rework_update_event_triggering)

  def update_command_new
    return if AnilLanRework.enabled? && AnilLanRework::WorldSync.input_locked?
    anil_rework_update_command_new
  end

  def update_event_triggering
    return if AnilLanRework.enabled? && AnilLanRework::WorldSync.input_locked?
    anil_rework_update_event_triggering
  end
end

class Scene_Map
  attr_reader :spritesets if !method_defined?(:spritesets)
  alias anil_rework_scene_update update unless method_defined?(:anil_rework_scene_update)
  alias anil_rework_scene_main main unless method_defined?(:anil_rework_scene_main)
  alias anil_rework_transfer_player transfer_player unless method_defined?(:anil_rework_transfer_player)
  alias anil_rework_updateMaps updateMaps unless method_defined?(:anil_rework_updateMaps)
  alias anil_rework_updateSpritesets updateSpritesets unless method_defined?(:anil_rework_updateSpritesets)

  def updateMaps(*args)
    current_map = ($game_map.map_id rescue nil)
    map_changed = @anil_rework_last_map_id != current_map
    @anil_rework_last_map_id = current_map

    if $game_temp && $game_temp.respond_to?(:in_menu) && $game_temp.in_menu
      is_transferring = map_changed || 
                        ($game_temp.respond_to?(:player_transferring) && $game_temp.player_transferring) || 
                        ($game_temp.respond_to?(:transition_processing) && $game_temp.transition_processing)
      if is_transferring
        @last_maps_update_frame = -1
      else
        current_frame = Graphics.frame_count rescue 0
        @last_maps_update_frame ||= -1
        return if @last_maps_update_frame == current_frame
        @last_maps_update_frame = current_frame
      end
    end
    anil_rework_updateMaps(*args)
  end

  def updateSpritesets(*args)
    if args[0] == true
      return anil_rework_updateSpritesets(*args)
    end

    current_map = ($game_map.map_id rescue nil)
    map_changed = @anil_rework_last_map_id != current_map
    @anil_rework_last_map_id = current_map

    if $game_temp && $game_temp.respond_to?(:in_menu) && $game_temp.in_menu
      is_transferring = map_changed || 
                        ($game_temp.respond_to?(:player_transferring) && $game_temp.player_transferring) || 
                        ($game_temp.respond_to?(:transition_processing) && $game_temp.transition_processing)
      if is_transferring
        @last_spritesets_update_frame = -1
      else
        current_frame = Graphics.frame_count rescue 0
        @last_spritesets_update_frame ||= -1
        return if @last_spritesets_update_frame == current_frame
        @last_spritesets_update_frame = current_frame
      end
    end
    anil_rework_updateSpritesets(*args)
  end

  alias anil_rework_miniupdate miniupdate unless method_defined?(:anil_rework_miniupdate)

  def miniupdate(*args)
    anil_rework_miniupdate(*args)
    $anil_channel_hud.update rescue nil if $anil_channel_hud
    $anil_map_name_hud.update rescue nil if $anil_map_name_hud
    $anil_partner_hud.update rescue nil if $anil_partner_hud
  end

  def main
    AnilLanRework.init_popups(nil)
    begin
      anil_rework_scene_main
    ensure
      $anil_channel_hud.dispose rescue nil if $anil_channel_hud
      $anil_channel_hud = nil
      $anil_map_name_hud.dispose rescue nil if $anil_map_name_hud
      $anil_map_name_hud = nil
      AnilLanRework.dispose_popups
      AnilLanRework::GlobalNotification.dispose rescue nil
      AnilLanRework.dispose_overworld_animations rescue nil
    end
  end

  def transfer_player(*args)
    AnilLanRework.dispose_overworld_animations rescue nil
    result = anil_rework_transfer_player(*args)
    AnilLanRework.request_map_graphics_refresh!("map_transfer", 1)
    AnilLanRework::WorldSync.send_player_state rescue nil
    result
  end

  def update
    AnilLanRework.update_overworld_animations rescue nil
    begin
      # AGENDAMENTO DA AUTO-CONEXAO
      #
      # ⚠️ Isto tem de estar aqui, e nao no carregador. `trigger_auto_connect_on_map`
      # so e chamado quando esta flag esta ligada, e quem a ligava era APENAS o
      # fluxo de "Recuperar partida". Quem entrava pelo Multi Save nunca a
      # ligava, entao nada agendava a conexao e o jogo ficava offline — com o
      # menu F7 a mostrar as opcoes de LAN.
      #
      # Agendar a partir do estado do jogo (save carregado + credenciais) em vez
      # de a partir de um caminho de carregamento especifico cobre TODOS os
      # caminhos, presentes e futuros, sem ter de os descobrir um a um.
      #
      # `$anil_auto_connect_agendado` guarda o online_id ja agendado, e nao um
      # simples true/false: sem trava nenhuma, uma tentativa falhada deixaria
      # multiplayer_mode a false e isto voltaria a agendar a cada frame, num
      # ciclo infinito; com um booleano, carregar OUTRO save na mesma sessao
      # (que e o proprio caso de uso do Multi Save) ja nao agendava nada.
      # Diagnostico: se a tela preta esta no ar e nada foi agendado, diz PORQUE.
      # Sem isto o unico sintoma e um ecra preto eterno, sem uma linha de log.
      if AnilTelaCarregando.visivel? && !$anil_auto_connect_agendado && !$anil_autoconnect_porque_nao_agendou
        $anil_autoconnect_porque_nao_agendou = true
        anil_autoconnect_log("tela no ar e NADA agendado — game_temp=#{!!$game_temp} " \
                             "pendente=#{($game_temp.anil_pending_multiplayer_auto_connect rescue '?')} " \
                             "player=#{!!(defined?($player) && $player)} " \
                             "connected=#{AnilLanRework.connected? rescue '?'} " \
                             "multiplayer_mode=#{AnilLanRework.multiplayer_mode rescue '?'} " \
                             "mapa=#{($game_map.map_id rescue '?')}")
      end

      # ⚠️ SEM `&& !AnilLanRework.multiplayer_mode` aqui.
      #
      # Era essa condicao que deixava o Multi Save preso na tela "Carregando..."
      # para sempre. Quem levanta a tela (Scene_Map#main -> precisa_conectar?)
      # so olha para "nao ligado + tem credenciais"; quem AGENDA a ligacao exigia
      # ainda que o modo multiplayer estivesse DESLIGADO. Entrando pelo slot do
      # Multi Save o modo ja vem ligado, entao a tela subia e nunca era agendado
      # nada — e a rede de seguranca la em baixo depende de uma flag que nunca
      # chegava a ser posta. Recuperar partida funcionava por entrar noutro
      # estado. As duas condicoes tem de ser a mesma, senao ha sempre um caminho
      # que cobre o mundo e nunca o descobre.
      #
      # Nao volta a agendar em ciclo: o `$anil_auto_connect_agendado != oid` mais
      # abaixo e a propria flag de pendente ja travam isso — que e exatamente
      # para o que foram escritos.
      if $game_temp && $game_temp.respond_to?(:anil_pending_multiplayer_auto_connect) &&
         !$game_temp.anil_pending_multiplayer_auto_connect &&
         defined?($player) && $player &&
         !AnilLanRework.connected?
        begin
          oid  = ($PokemonGlobal && $PokemonGlobal.respond_to?(:online_id))      ? $PokemonGlobal.online_id.to_s.strip      : ""
          wc   = ($PokemonGlobal && $PokemonGlobal.respond_to?(:whitelist_code)) ? $PokemonGlobal.whitelist_code.to_s.strip : ""
          # O codigo tambem e gravado no :player — o Game.load ja usa esse
          # fallback, entao ler so o $PokemonGlobal deixaria de fora os saves
          # que so o tem la.
          if wc.empty? && defined?($player) && $player && $player.respond_to?(:whitelist_code)
            wc = $player.whitelist_code.to_s.strip
          end
          if oid.empty? && defined?($player) && $player && $player.respond_to?(:online_id)
            oid = $player.online_id.to_s.strip
          end

          unless $anil_autoconnect_ja_relatou
            $anil_autoconnect_ja_relatou = true
            marcado = ($PokemonGlobal && $PokemonGlobal.respond_to?(:is_multiplayer_online_save)) ? $PokemonGlobal.is_multiplayer_online_save.inspect : "(sem atributo)"
            anil_autoconnect_log("avaliando: online_id=#{oid.inspect} whitelist_code=#{wc.inspect} is_multiplayer_online_save=#{marcado} mapa=#{($game_map.map_id rescue '?')}")
          end

          if !oid.empty? && wc =~ /\A\d{6}\z/ && $anil_auto_connect_agendado != oid
            $anil_auto_connect_agendado = oid
            # A espera comeca AQUI. E o que distingue "ainda nao tentei" de
            # "tentei e nao deu" para a rede de seguranca la em baixo.
            $anil_autoconnect_espera_ja_comecou = true

            # ⚠️ Carimbar o save como verificado, senao o `connect` recusa antes
            # sequer de abrir o socket:
            #
            #   unless $PokemonGlobal.is_verified_online_save == true
            #     "Save invalido: Nao e um save verificado do modo multiplayer online!"
            #     return false
            #
            # Quem carimba e o Game.load (099), mas ele so o faz quando
            # multiplayer_mode JA esta ligado — e o Multi Save nem passa por la,
            # tem carregador proprio. Resultado: save legitimo, com codigo
            # valido, entrava como se fosse offline.
            #
            # O criterio aqui e EXACTAMENTE o do Game.load: codigo de whitelist
            # de 6 digitos no save. Nao afrouxa nada — quem valida de verdade e
            # o servidor, que confere codigo e player_id no join.
            if $PokemonGlobal
              $PokemonGlobal.is_multiplayer_online_save = true rescue nil
              $PokemonGlobal.is_verified_online_save    = true rescue nil
            end

            # ⚠️ Ligar multiplayer_mode AQUI, no agendamento, e nao la a frente
            # no disparo. Ha um SEGUNDO update (099, AnilCoordFix) que cancela o
            # agendamento a cada frame enquanto o modo estiver desligado:
            #
            #   if pending && !online_session? && !multiplayer_mode
            #     $game_temp.anil_pending_multiplayer_auto_connect = false
            #
            # Como o disparo so acontece 80 frames depois, e so ele e que ligava
            # o modo, o cancelador vencia sempre a corrida: o contador chegava a
            # 1 e a flag era limpa antes do frame seguinte. Era isto que fazia o
            # jogo continuar offline mesmo com tudo o resto correcto.
            AnilLanRework.multiplayer_mode = true rescue nil

            # Cobre o mundo IMEDIATAMENTE, no mesmo frame do agendamento. Se
            # subisse junto do disparo, o overworld ja teria aparecido.
            #
            # Excepto na introducao: ali nao ha mundo para tapar (e uma cutscene)
            # e a tela so atrapalhava — subia aqui e caia logo a seguir no ramo
            # de espera, dando um flash de "Carregando..." por cima do Oak.
            if anil_autoconnect_seria_adiado? || anil_autoconnect_sem_nome?
              anil_autoconnect_log("AGENDADO sem tela (introducao a decorrer)")
            else
              AnilTelaCarregando.mostrar!(_INTL("Carregando..."))
            end

            $game_temp.anil_pending_multiplayer_auto_connect = true
            anil_autoconnect_log("AGENDADO para #{oid} (save verificado, modo VPS ligado)")
          end
        rescue => e
          anil_autoconnect_log("ERRO ao avaliar credenciais: #{e.class}: #{e.message}")
        end
      end

      # Vigia a flag: se ela cair sozinha entre frames, alguem a cancelou e e
      # esse alguem que interessa descobrir.
      if $anil_auto_connect_agendado && $game_temp && $game_temp.respond_to?(:anil_pending_multiplayer_auto_connect)
        atual_flag = $game_temp.anil_pending_multiplayer_auto_connect ? true : false
        if $anil_autoconnect_flag_anterior && !atual_flag && !AnilLanRework.connected?
          anil_autoconnect_log("!! FLAG CANCELADA por terceiro (multiplayer_mode=#{AnilLanRework.multiplayer_mode} online_session=#{AnilLanRework.online_session? rescue '?'})")
        end
        $anil_autoconnect_flag_anterior = atual_flag

        # Rede de seguranca: se a espera terminou por qualquer via — cancelada
        # por terceiro, conexao concluida, cena trocada — o jogador tem de ser
        # solto. Ficar congelado sem caixa de texto na tela e pior do que entrar
        # offline.
        if $anil_autoconnect_input_travado && (!atual_flag || AnilLanRework.connected?)
          anil_autoconnect_destravar_jogador!
          anil_autoconnect_log("jogador destravado (pendente=#{atual_flag} conectado=#{AnilLanRework.connected?})")
        end

        # A tela preta nunca pode sobreviver ao fim da espera: se a flag foi
        # cancelada por outro caminho, ninguem mais a tiraria e o jogador ficaria
        # olhando para um ecra preto sem saber porque.
        if AnilTelaCarregando.visivel? && !atual_flag
          if AnilLanRework.connected?
            AnilTelaCarregando.esconder_em_fade!
            anil_autoconnect_log("tela retirada pela rede de seguranca (conectado)")
          elsif !$anil_autoconnect_espera_ja_comecou
            # Segunda tranca para o mesmo problema de estado residual: so ha
            # falha se a espera CHEGOU A COMECAR nesta sessao. Sem isto, um
            # `$anil_auto_connect_agendado` deixado para tras basta para
            # declarar falha antes de existir uma unica tentativa — foi o que o
            # log mostrou, com "FALHA" logo a seguir a "tela levantada", sem
            # nenhum "conectando" pelo meio.
            anil_autoconnect_log("rede de seguranca ignorada: a espera nem chegou a comecar (estado residual) — apenas retirando a tela")
            AnilTelaCarregando.esconder_em_fade!
          else
            # ⚠️ NAO descartar aqui. Descartar sem ligacao revelava o overworld
            # offline — era este o buraco que fazia o jogo entrar normalmente
            # com o servidor desligado, mesmo com o caminho de falha escrito.
            anil_autoconnect_falhar!(_INTL("Falha ao tentar se conectar"))
          end
        end
      end

      if $game_temp && $game_temp.respond_to?(:anil_pending_multiplayer_auto_connect) && $game_temp.anil_pending_multiplayer_auto_connect
        unless $anil_autoconnect_ramo_relatado
          $anil_autoconnect_ramo_relatado = true
          anil_autoconnect_log("consumindo flag: player=#{(!!$player)} party=#{($player.party.length rescue 'nil')} mapa=#{($game_map.map_id rescue '?')} multiplayer_mode=#{AnilLanRework.multiplayer_mode}")
        end
        if defined?($player) && $player && $player.party
          if anil_autoconnect_sem_nome? || anil_autoconnect_seria_adiado?
            # Este ramo NAO conta o delay: espera o tempo que for preciso.
            #
            # O QUE ESPERAMOS: o jogador escolher o nome na introducao.
            #
            # A condicao original era `!AnilLanRework.multiplayer_mode && (party
            # vazia || mapa 29/1)`, e o `!multiplayer_mode` anulava o ramo
            # exactamente no caso que ele existe para proteger: no Novo Jogo com
            # multiplayer essa flag ja e true ANTES da introducao (posta pelo
            # 100_Multiplayer_Whitelist assim que o codigo valida). Caia-se no
            # else e o jogo ligava ~1,3s depois, a meio da introducao, sem nome
            # nenhum — falhava, e a chave ja tinha sido queimada (ela e consumida
            # quando se digita o codigo). Ver [[chave-resgate-incompleto]].
            #
            # POR QUE O NOME E NAO A PARTY: esperar pela equipa deixava o jogador
            # offline durante toda a introducao e ele acabava a entrar
            # desconectado. O nome e o que o servidor precisa para amarrar a
            # conta (update_whitelisted_name!), e chega bem antes do inicial —
            # portanto assim que ha nome da para ligar, ainda dentro da intro.
            #
            # O `|| mapa 29/1` da condicao antiga tambem saiu: sozinho, impedia
            # a ligacao de QUALQUER save ja formado parado no mapa 1 ou 29.
            unless $anil_autoconnect_espera_relatada
              $anil_autoconnect_espera_relatada = true
              anil_autoconnect_log("EM ESPERA (sem nome=#{anil_autoconnect_sem_nome?} seria_adiado=#{anil_autoconnect_seria_adiado?} mapa=#{($game_map.map_id rescue nil)}) — sem tela e sem congelar; liga quando a intro acabar")
            end
            @anil_silent_connect = true

            # A tela preta sobe no AGENDAMENTO para tapar o overworld enquanto a
            # ligacao nao existe. Enquanto se esperava 80 frames isso durava ~1,3s
            # e ninguem reparava; agora que se espera a introducao inteira, ela
            # ficaria por cima da cena toda — o jogador via "Carregando..." em vez
            # do Oak e nao conseguia sequer escolher o nome.
            #
            # Retirar aqui e seguro: a razao de existir da tela e nao deixar o
            # MUNDO JOGAVEL aparecer offline, e durante a introducao nao ha mundo
            # jogavel — e uma cutscene em que o jogador so responde a caixas de
            # texto. Assim que a equipa tiver Pokemon cai-se no ramo de baixo,
            # que volta a cobrir o ecra e trata da ligacao.
            if AnilTelaCarregando.visivel?
              AnilTelaCarregando.esconder_em_fade!
              anil_autoconnect_log("tela de carregamento retirada: introducao a decorrer")
            end
          else
            @anil_auto_connect_delay ||= 0
            @anil_auto_connect_delay += 1
            anil_autoconnect_log("contando delay: #{@anil_auto_connect_delay}/80") if @anil_auto_connect_delay % 20 == 1

            # ⚠️ CONGELAR o jogador durante a espera.
            #
            # Sem isto ha ~1,3s de overworld JOGAVEL antes de a conexao existir:
            # da para andar, falar com NPC, apanhar item e entrar em batalha
            # offline — e so depois o jogo entra online, com o servidor sem
            # saber de nada do que aconteceu. E a receita para divergencia entre
            # o save local e o do servidor.
            #
            # `message_window_showing` e a MESMA tranca que a engine usa para
            # travar o passo enquanto ha caixa de texto aberta (Game_Player:478),
            # entao nao e preciso inventar mecanismo novo nem tocar no
            # Game_Player. E reposta antes de qualquer saida deste bloco.
            if $game_temp.respond_to?(:message_window_showing=) && !$anil_autoconnect_input_travado
              $anil_autoconnect_input_travado = true
              $game_temp.message_window_showing = true
              anil_autoconnect_log("jogador congelado ate a conexao resolver")
            end

            # Repoe a tela preta. O ramo de espera acima retira-a para a
            # introducao poder ser vista, entao aqui — ja com nome e a caminho da
            # ligacao — ela tem de voltar, senao reaparece a janela de overworld
            # visivel antes de o jogo estar online.
            if !AnilTelaCarregando.visivel?
              AnilTelaCarregando.mostrar!(_INTL("Carregando..."))
              anil_autoconnect_log("tela de carregamento reposta antes de ligar")
            end

            if @anil_auto_connect_delay >= 80
              $game_temp.anil_pending_multiplayer_auto_connect = false
              silent = (@anil_silent_connect == true)
              @anil_auto_connect_delay = nil
              @anil_silent_connect = nil
              # SEMPRE silent: a caixa "Conectando ao servidor principal..." e
              # modal e apareceria por cima da tela de carregamento. Quem informa
              # o jogador agora e a propria tela preta.
              anil_autoconnect_log("conectando (silencioso, atras da tela de carregamento)")
              begin
                anil_autoconnect_destravar_jogador!
                AnilLanRework.trigger_auto_connect_on_map(true)
              ensure
                anil_autoconnect_destravar_jogador!
              end

              conectado = (AnilLanRework.connected? rescue false)
              anil_autoconnect_log("resultado: connected?=#{conectado} multiplayer_mode=#{AnilLanRework.multiplayer_mode}")

              # ADIADO != FALHOU.
              #
              # O `trigger_auto_connect_on_map` esta embrulhado por varios
              # patches. O do 099_Save_Coordinate_Fix recusa-se a ligar enquanto
              # se estiver em Novo Jogo ou nos mapas de introducao (1, 29, 104) —
              # e, em vez de falhar, REPOE a flag de pendente e faz `return`.
              #
              # Este bloco lia so o `connected?`, via false e mandava tudo para a
              # tela preta de erro. Era esta a "Falha ao tentar se conectar" que
              # aparecia mesmo depois de escolher o nome: o jogador continuava no
              # mapa 1, o 099 adiava, e o adiamento era tratado como falha.
              #
              # A flag reposta e o sinal de que houve adiamento — quando ela
              # volta, recomeca-se a espera em vez de desistir.
              adiado = false
              begin
                adiado = !conectado && $game_temp &&
                         $game_temp.respond_to?(:anil_pending_multiplayer_auto_connect) &&
                         $game_temp.anil_pending_multiplayer_auto_connect ? true : false
              rescue
                adiado = false
              end

              if conectado
                AnilTelaCarregando.esconder_em_fade!
              elsif adiado
                anil_autoconnect_log("ADIADO por um dos patches (provavelmente mapa de intro) — volta a esperar, sem erro")
                @anil_auto_connect_delay = nil
                @anil_silent_connect = nil
                $anil_autoconnect_espera_relatada = nil
                $anil_autoconnect_ramo_relatado = nil
                anil_autoconnect_destravar_jogador!
                # A introducao tem de continuar visivel enquanto se espera.
                AnilTelaCarregando.esconder_em_fade! if AnilTelaCarregando.visivel?
              else
                # ⚠️ Save do servidor NUNCA entra offline. Sem isto o jogador
                # ficava a jogar localmente e o save divergia do que esta no
                # servidor — que e o mais dificil de reconciliar depois.
                anil_autoconnect_falhar!(_INTL("Falha ao tentar se conectar"))
              end
            end
          end
        end
      end

      if defined?($player) && $player && $player.name.to_s != $anil_last_player_name.to_s
        $anil_last_player_name = $player.name.to_s
        AnilLanRework.update_player_config
        File.delete("multiplayer_sessions_rework.json") if File.exist?("multiplayer_sessions_rework.json")
        AnilLanRework.log("Player context changed: Config updated, stale sessions cleared.")
      end

      # --- SANITIZE MULTIPLAYER PARTNER OFFLINE ---
      if defined?($PokemonGlobal) && $PokemonGlobal.partner && !AnilLanRework.connected?
        is_mp = ($PokemonGlobal.partner[4] == true || 
                 (AnilLanRework::BattleSync.instance_variable_get(:@partner_injected) rescue false) ||
                 !AnilLanRework::BattleSync.is_story_partner?($PokemonGlobal.partner))
        if is_mp
          $PokemonGlobal.partner = nil
          AnilLanRework::BattleSync.remove_partner rescue nil
          AnilLanRework.log("Scene_Map#update: Cleaned leaked multiplayer partner offline!")
        end
      end

      AnilLanRework.update_popups
      AnilLanRework::GlobalNotification.update rescue nil
      
      # Gerenciamento dinâmico e preguiçoso do HUD de Canais
      if AnilLanRework.enabled? && AnilLanRework.connected?
        if !$anil_channel_hud
          $anil_channel_hud = AnilChannelHUD.new rescue nil
        end
        $anil_channel_hud.update rescue nil if $anil_channel_hud
      else
        if $anil_channel_hud
          $anil_channel_hud.dispose rescue nil
          $anil_channel_hud = nil
        end
      end

      # Gerenciamento dinâmico e preguiçoso do HUD de Nome do Mapa
      if AnilLanRework.enabled? && AnilLanRework.connected?
        if !$anil_map_name_hud
          $anil_map_name_hud = AnilMapNameHUD.new rescue nil
        end
        $anil_map_name_hud.update rescue nil if $anil_map_name_hud
      else
        if $anil_map_name_hud
          $anil_map_name_hud.dispose rescue nil
          $anil_map_name_hud = nil
        end
      end

# Gerenciamento dinâmico e preguiçoso do HUD de Grupo (parceiro)
if AnilLanRework.enabled? && AnilLanRework.connected?
  if !$anil_partner_hud
    $anil_partner_hud = AnilPartnerHUD.new rescue nil
  end
  $anil_partner_hud.update rescue nil if $anil_partner_hud
else
  if $anil_partner_hud
    $anil_partner_hud.dispose rescue nil
    $anil_partner_hud = nil
  end
end

      if !($game_temp&.message_window_showing) && !(pbMapInterpreterRunning? rescue false) &&
         !($game_temp && $game_temp.respond_to?(:in_menu) && $game_temp.in_menu)
        if (Input.trigger?(Input::F9) rescue false)
          pbPlayDecisionSE
          if defined?(AnilProfiler)
            AnilProfiler.toggle
          else
            $anil_debug_log_enabled = !$anil_debug_log_enabled
            status = $anil_debug_log_enabled ? "LIGADO" : "DESLIGADO"
            pbMessage(_INTL("Multiplayer Debug Log: {1}", status))
          end
          return
        elsif (Input.trigger?(Input::F7) rescue false)
          pbPlayDecisionSE
          $game_player.straighten rescue nil
          Scene_Map_MultiplayerMainMenu.open
          return
        elsif (Input.trigger?(Input::F5) rescue false)
          pbPlayDecisionSE
          $game_player.straighten rescue nil
          AnilLanRework.hard_refresh_screen!("manual_f5_hard_refresh", 5)
          return
        end
      end

      anil_rework_scene_update

      if AnilLanRework.enabled? && AnilLanRework.connected?
        begin
          AnilLanRework::Router.tick
        rescue AnilMainMenuRedirectException => e
          raise e
        rescue => e
          AnilLanRework.log("scene map network tick error #{e.class}: #{e.message}")
        end
      end

      AnilLanRework::MailboxSync.update
      AnilLanRework::PlayerMarket.update_pending unless AnilLanRework.enabled? && AnilLanRework.connected?
      if AnilLanRework.apply_pending_return_location!(self)
        return
      end
      if AnilLanRework.apply_pending_same_map_transfer!(self)
        return
      end

      AnilLanRework.process_delayed_map_refresh!(self)
      if AnilLanRework.consume_map_graphics_refresh?
        AnilLanRework.refresh_scene_map_graphics!(self)
        return
      end

      return unless AnilLanRework.enabled? && AnilLanRework.connected?

      AnilLanRework::BattleSync.update_pending_coop_invite
      AnilLanRework::BattleSync.update_pending_coop_start
      AnilLanRework::BattleSync.update_pending_invite
      AnilLanRework::BattleSync.update_pending_start
      AnilLanRework::TradeSync.update_pending
      AnilLanRework::ItemSync.update_pending
      AnilLanRework::PlayerMarket.update_pending
      return if AnilLanRework::WorldSync.input_locked?

      return if $game_temp&.message_window_showing
      return if (pbMapInterpreterRunning? rescue false)
      return unless $game_player

      AnilLanRework.handle_peer_interaction_trigger if AnilLanRework.respond_to?(:handle_peer_interaction_trigger)
    rescue AnilMainMenuRedirectException
      AnilLanRework.log("Scene_Map#update: Redirecionando para a tela de título devido a perda de conexão/desconexão.")
      $scene = pbCallTitle
    end
  end
end

MenuHandlers.add(:pc_menu, :anil_online_market_buy, {
  "name"  => proc { next _INTL("Loja de Jogadores") },
  "order" => 15,
  "effect" => proc { |_menu|
    if !AnilLanRework.enabled? || !AnilLanRework.connected?
      pbMessage(_INTL("Liga-te a uma sessao online para usar o mercado."))
    else
      AnilLanRework::PlayerMarket.open_pc_buy_menu
    end
    next false
  }
})

if defined?(PokemonStorageScreen)
  class PokemonStorageScreen
    alias anil_market_organise_commands organise_commands unless method_defined?(:anil_market_organise_commands)

    def organise_commands(selected, pokemon)
      commands = []
      cmdMove       = -1
      cmdSummary    = -1
      cmdWithdraw   = -1
      cmdItem       = -1
      cmdMark       = -1
      cmdPokedex    = -1
      cmdRelease    = -1
      cmdSellOnline = -1
      cmdDebug      = -1
      heldpoke = pbHeldPokemon
      if heldpoke
        helptext = _INTL("Selecionaste {1}.", heldpoke.name)
        commands[cmdMove = commands.length] = (pokemon) ? _INTL("Trocar") : _INTL("Colocar")
      elsif pokemon
        helptext = _INTL("Selecionaste {1}.", pokemon.name)
        commands[cmdMove = commands.length] = _INTL("Mover")
      elsif @heldpkmn
        helptext = _INTL("Selecionaste {1}.", @heldpkmn.name)
      else
        helptext = _INTL("Nenhum Pokemon selecionado.")
      end
      commands[cmdSummary = commands.length]  = _INTL("Resumo")
      commands[cmdWithdraw = commands.length] = (selected[0] == -1) ? _INTL("Guardar") : _INTL("Retirar")
      commands[cmdItem = commands.length]     = _INTL("Objeto")
      commands[cmdMark = commands.length]     = _INTL("Marcas")
      commands[cmdPokedex = commands.length]  = _INTL("Pokédex")
      if pokemon && AnilLanRework.enabled? && AnilLanRework.connected?
        commands[cmdSellOnline = commands.length] = _INTL("Vender")
      end
      commands[cmdRelease = commands.length]  = _INTL("Liberar")
      commands[cmdDebug = commands.length]    = _INTL("Debug") if $DEBUG
      commands[commands.length]               = _INTL("Cancelar")
      command = pbShowCommands(helptext, commands)
      if cmdMove >= 0 && command == cmdMove
        if @heldpkmn
          (pokemon) ? pbSwap(selected) : pbPlace(selected)
        else
          pbHold(selected)
        end
      elsif cmdSummary >= 0 && command == cmdSummary
        pbSummary(selected, @heldpkmn)
      elsif cmdWithdraw >= 0 && command == cmdWithdraw
        (selected[0] == -1) ? pbStore(selected, @heldpkmn) : pbWithdraw(selected, @heldpkmn)
      elsif cmdItem >= 0 && command == cmdItem
        pbItem(selected, @heldpkmn)
      elsif cmdMark >= 0 && command == cmdMark
        pbMark(selected, @heldpkmn)
      elsif cmdPokedex >= 0 && command == cmdPokedex
        openPokedexOnPokemon(pokemon.species, pokemon.gender, pokemon.form) if pokemon
        openPokedexOnPokemon(@heldpkmn.species, @heldpkmn.gender, @heldpkmn.form) if !pokemon && @heldpkmn
      elsif cmdSellOnline >= 0 && command == cmdSellOnline
        AnilLanRework::PlayerMarket.sell_storage_selected(self, selected, pokemon)
      elsif cmdRelease >= 0 && command == cmdRelease
        pbRelease(selected, @heldpkmn)
      elsif cmdDebug >= 0 && command == cmdDebug
        pbPokemonDebug((@heldpkmn) ? @heldpkmn : pokemon, selected, heldpoke)
      end
    end
  end
end

if defined?(pbPokemonMart) && !defined?(anil_market_original_pbPokemonMart)
  alias anil_market_original_pbPokemonMart pbPokemonMart
  def pbPokemonMart(stock, speech = nil, cantsell = false)
    return anil_market_original_pbPokemonMart(stock, speech, cantsell) unless AnilLanRework.enabled? && AnilLanRework.connected?
    loop do
      shop_type = pbMessage(
        speech || _INTL("Bem-vindo! O que deseja fazer?"),
        [_INTL("Loja Normal"), _INTL("Loja de Jogadores"), _INTL("Sair")],
        3
      )
      case shop_type
      when 0
        normal_commands = [_INTL("Comprar")]
        normal_commands << _INTL("Vender") unless cantsell
        normal_commands << _INTL("Cancelar")
        normal_choice = pbMessage(_INTL("Loja Normal"), normal_commands, normal_commands.length)
        if normal_choice == 0
          scene = PokemonMart_Scene.new
          screen = PokemonMartScreen.new(scene, stock)
          screen.pbBuyScreen
        elsif !cantsell && normal_choice == 1
          scene = PokemonMart_Scene.new
          screen = PokemonMartScreen.new(scene, stock)
          screen.pbSellScreen
        end
      when 1
        player_choice = pbMessage(
          _INTL("Loja de Jogadores"),
          [_INTL("Comprar"), _INTL("Vender"), _INTL("Cancelar")],
          3
        )
        case player_choice
        when 0 then AnilLanRework::PlayerMarket.open_item_buy_menu
        when 1 then AnilLanRework::PlayerMarket.open_item_sell_menu
        end
      else
        pbMessage(_INTL("Volte sempre!"))
        break
      end
    end
  end
end

# Cursor naming variant for JoiPlay multiplayer rename.
# It avoids the automatic switch from uppercase to lowercase after the first
# character, which can glitch on some virtual gamepad setups.
class MultiplayerJoiPlayPlayerNameEntryScene < PokemonEntryScene2
  def pbDrawRawTextPositions(bitmap, textpos)
    textpos.each do |i|
      text = i[0] || ""
      textsize = bitmap.text_size(text)
      x = i[1]
      y = i[2]
      case i[3]
      when :right, true, 1
        x -= textsize.width
      when :center, 2
        x -= (textsize.width / 2)
      end
      mode = i[6]
      mode = :none if !i[5]
      case mode
      when :outline, true, 1
        pbDrawOutlineText(bitmap, x, y, textsize.width, textsize.height, text, i[4], i[5])
      when :none
        pbDrawPlainText(bitmap, x, y, textsize.width, textsize.height, text, i[4])
      else
        pbDrawShadowText(bitmap, x, y, textsize.width, textsize.height, text, i[4], i[5])
      end
    end
  end

  def pbStartScene(helptext, minlength, maxlength, initialText, subject = 0, pokemon = nil)
    @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 99999
    @helptext = helptext
    @helper = CharacterEntryHelper.new(initialText)
    @bitmaps = []
    @@Characters.length.times do |i|
      @bitmaps[i] = AnimatedBitmap.new(sprintf("Graphics/UI/Naming/overlay_tab_%d", i + 1))
      b = @bitmaps[i].bitmap.clone
      pbSetSystemFont(b)
      textPos = []
      COLUMNS.times do |y|
        ROWS.times do |x|
          pos = (y * ROWS) + x
          textPos.push([@@Characters[i][0][pos], 44 + (x * 32), 24 + (y * 38), :center,
                        Color.new(16, 24, 32), Color.new(160, 160, 160)])
        end
      end
      pbDrawRawTextPositions(b, textPos)
      @bitmaps[@@Characters.length + i] = b
    end
    underline_bitmap = Bitmap.new(24, 6)
    underline_bitmap.fill_rect(2, 2, 22, 4, Color.new(168, 184, 184))
    underline_bitmap.fill_rect(0, 0, 22, 4, Color.new(16, 24, 32))
    @bitmaps.push(underline_bitmap)
    @sprites = {}
    @sprites["bg"] = IconSprite.new(0, 0, @viewport)
    @sprites["bg"].setBitmap("Graphics/UI/Naming/bg")
    case subject
    when 1
      meta = GameData::PlayerMetadata.get($player.character_ID)
      if meta
        @sprites["shadow"] = IconSprite.new(0, 0, @viewport)
        @sprites["shadow"].setBitmap("Graphics/UI/Naming/icon_shadow")
        @sprites["shadow"].x = 66
        @sprites["shadow"].y = 64
        filename = pbGetPlayerCharset(meta.walk_charset, nil, true)
        @sprites["subject"] = TrainerWalkingCharSprite.new(filename, @viewport)
        charwidth = @sprites["subject"].bitmap.width
        charheight = @sprites["subject"].bitmap.height
        @sprites["subject"].x = 88 - (charwidth / 8)
        @sprites["subject"].y = 76 - (charheight / 4)
      end
    when 2
      if pokemon
        @sprites["shadow"] = IconSprite.new(0, 0, @viewport)
        @sprites["shadow"].setBitmap("Graphics/UI/Naming/icon_shadow")
        @sprites["shadow"].x = 66
        @sprites["shadow"].y = 64
        @sprites["subject"] = PokemonIconSprite.new(pokemon, @viewport)
        @sprites["subject"].setOffset(PictureOrigin::CENTER)
        @sprites["subject"].x = 88
        @sprites["subject"].y = 54
        @sprites["gender"] = BitmapSprite.new(32, 32, @viewport)
        @sprites["gender"].x = 430
        @sprites["gender"].y = 54
        @sprites["gender"].bitmap.clear
        pbSetSystemFont(@sprites["gender"].bitmap)
        textpos = []
        if pokemon.male?
          textpos.push([_INTL("♂"), 0, 6, :left, Color.new(0, 128, 248), Color.new(168, 184, 184)])
        elsif pokemon.female?
          textpos.push([_INTL("♀"), 0, 6, :left, Color.new(248, 24, 24), Color.new(168, 184, 184)])
        end
        pbDrawRawTextPositions(@sprites["gender"].bitmap, textpos)
      end
    when 3
      @sprites["shadow"] = IconSprite.new(0, 0, @viewport)
      @sprites["shadow"].setBitmap("Graphics/UI/Naming/icon_shadow")
      @sprites["shadow"].x = 66
      @sprites["shadow"].y = 64
      @sprites["subject"] = TrainerWalkingCharSprite.new(pokemon.to_s, @viewport)
      charwidth = @sprites["subject"].bitmap.width
      charheight = @sprites["subject"].bitmap.height
      @sprites["subject"].x = 88 - (charwidth / 8)
      @sprites["subject"].y = 76 - (charheight / 4)
    when 4
      @sprites["subject"] = TrainerWalkingCharSprite.new(nil, @viewport)
      @sprites["subject"].altcharset = "Graphics/UI/Naming/icon_storage"
      @sprites["subject"].anim_duration = 0.4
      charwidth = @sprites["subject"].bitmap.width
      charheight = @sprites["subject"].bitmap.height
      @sprites["subject"].x = 88 - (charwidth / 8)
      @sprites["subject"].y = 52 - (charheight / 2)
    end
    @sprites["bgoverlay"] = BitmapSprite.new(Graphics.width, Graphics.height, @viewport)
    pbDoUpdateOverlay
    @blanks = []
    @mode = 0
    @minlength = minlength
    @maxlength = maxlength
    @maxlength.times do |i|
      @sprites["blank#{i}"] = Sprite.new(@viewport)
      @sprites["blank#{i}"].x = 160 + (24 * i)
      @sprites["blank#{i}"].bitmap = @bitmaps[@bitmaps.length - 1]
      @blanks[i] = 0
    end
    @sprites["bottomtab"] = Sprite.new(@viewport)
    @sprites["bottomtab"].x = 22
    @sprites["bottomtab"].y = 162
    @sprites["bottomtab"].bitmap = @bitmaps[@@Characters.length]
    @sprites["toptab"] = Sprite.new(@viewport)
    @sprites["toptab"].x = 22 - 504
    @sprites["toptab"].y = 162
    @sprites["toptab"].bitmap = @bitmaps[@@Characters.length + 1]
    @sprites["controls"] = IconSprite.new(0, 0, @viewport)
    @sprites["controls"].x = 16
    @sprites["controls"].y = 96
    @sprites["controls"].setBitmap(_INTL("Graphics/UI/Naming/overlay_controls"))
    @sprites["overlay"] = BitmapSprite.new(Graphics.width, Graphics.height, @viewport)
    pbDoUpdateOverlay2
    @sprites["cursor"] = NameEntryCursor.new(@viewport)
    @cursorpos = 0
    @refreshOverlay = true
    @sprites["cursor"].setCursorPos(@cursorpos)
    pbFadeInAndShow(@sprites) { pbUpdate }
  end

  def pbDoUpdateOverlay
    return if !@refreshOverlay
    @refreshOverlay = false
    bgoverlay = @sprites["bgoverlay"].bitmap
    bgoverlay.clear
    pbSetSystemFont(bgoverlay)
    textPositions = [
      [@helptext, 160, 18, :left, Color.new(16, 24, 32), Color.new(168, 184, 184)]
    ]
    chars = @helper.textChars
    x = 172
    chars.each do |ch|
      textPositions.push([ch, x, 54, :center, Color.new(16, 24, 32), Color.new(168, 184, 184)])
      x += 24
    end
    pbDrawRawTextPositions(bgoverlay, textPositions)
  end

  def pbEntry
    ret = ""
    loop do
      Graphics.update
      Input.update
      pbUpdate
      next if pbMoveCursor
      if Input.trigger?(Input::SPECIAL)
        pbChangeTab
      elsif Input.trigger?(Input::ACTION)
        @cursorpos = OK
        @sprites["cursor"].setCursorPos(@cursorpos)
      elsif Input.trigger?(Input::BACK)
        @helper.delete
        pbPlayCancelSE
        pbUpdateOverlay
      elsif Input.trigger?(Input::USE)
        case @cursorpos
        when BACK
          @helper.delete
          pbPlayCancelSE
          pbUpdateOverlay
        when OK
          pbSEPlay("GUI naming confirm")
          if @helper.length >= @minlength
            ret = @helper.text
            break
          end
        when MODE1
          pbChangeTab(0) if @mode != 0
        when MODE2
          pbChangeTab(1) if @mode != 1
        when MODE3
          pbChangeTab(2) if @mode != 2
        when MODE4
          pbChangeTab(3) if @mode != 3
        else
          cursormod = @cursorpos % ROWS
          cursordiv = @cursorpos / ROWS
          charpos = (cursordiv * ROWS) + cursormod
          chset = @@Characters[@mode][0]
          @helper.delete if @helper.length >= @maxlength
          @helper.insert(chset[charpos])
          pbPlayCursorSE
          if @helper.length >= @maxlength
            @cursorpos = OK
            @sprites["cursor"].setCursorPos(@cursorpos)
          end
          pbUpdateOverlay
        end
      end
    end
    Input.update
    return ret
  end
end

#-------------------------------------------------------------------------------
# Scene_Map_MultiplayerMainMenu
# Menu principal: Abrir host / Entrar / Trocar personagem / Desconectar
# Fluxo: escolha -> carregar save se preciso -> abrir lobby com acao pre-selecionada
#-------------------------------------------------------------------------------
module Scene_Map_MultiplayerMainMenu
  module_function

  @active = false

  def active?
    return @active
  end

  def open
    was_active = @active
    @active = true
    if $anil_channel_hud
      $anil_channel_hud.update_hud(true) rescue nil
    end
    if $anil_map_name_hud
      $anil_map_name_hud.update_hud(true) rescue nil
    end
if $anil_partner_hud
  $anil_partner_hud.update_hud(true) rescue nil
end

    begin
      # Mostra o overlay apenas enquanto o menu estiver aberto
      overlay = AnilLanRework::Overlay.new(nil) rescue nil
      overlay&.update

    AnilLanRework.update_player_config rescue nil
    online_id = (AnilLanRework.online_session? && $PokemonGlobal && $PokemonGlobal.respond_to?(:online_id)) ? $PokemonGlobal.online_id : nil
    id_label = online_id ? "\\c[3]ID: #{online_id}\\c[0]" : "Modo Multiplayer"

    commands = []
    actions = []
    if AnilLanRework.connected?
      # ==========================================
      # ESTADO CONECTADO (Online VPS ou LAN Rework)
      # ==========================================
      if defined?(AnilLanRework) && AnilLanRework.respond_to?(:online_session?) && AnilLanRework.online_session?
        # Online VPS ativo
        commands << _INTL("Mudar Canal")
        actions << :change_channel
        commands << _INTL("Trocar Personagem")
        actions << :character
        if online_id
          commands << _INTL("Ver ID Único")
          actions << :show_id
        end
      else
        # LAN Rework ativo: Desconectar no topo, sem ID Único.
        # "Modo Debug" saiu daqui — ver a nota no ramo desconectado abaixo.
        commands << _INTL("Desconectar")
        actions << :disconnect
        commands << _INTL("Trocar Personagem")
        actions << :character
        commands << _INTL("Mudar Nome")
        actions << :rename
      end
    else
      # ==========================================
      # ESTADO DESCONECTADO (Online VPS ou LAN Rework)
      # ==========================================
      # ⚠️ Antes havia DOIS conjuntos aqui, escolhidos por `multiplayer_mode`.
      # Esse sinalizador so fica true depois de uma conexao bem sucedida e volta
      # a false ao desconectar — ou seja, quem carrega o save pelo Multi Save
      # (que nao conecta) caia SEMPRE no conjunto LAN e via "Multiplayer -
      # Abrir/Entrar", "Digitar IP" e "Modo Debug".
      #
      # Este jogo e servido por um VPS dedicado: hospedar partida, entrar por IP
      # a mao e o menu de debug nao sao opcoes validas para o jogador. Ficavam
      # expostas so por causa do estado em que o menu foi aberto.
      #
      # Passa a existir UM conjunto so. `multiplayer_mode` deixa de decidir o que
      # aparece — continua a valer para o resto do sistema.
      commands << _INTL("Mudar Canal")
      actions << :change_channel
      commands << _INTL("Trocar Personagem")
      actions << :character
      commands << _INTL("Mudar Nome")
      actions << :rename
      if online_id
        commands << _INTL("Ver ID Único")
        actions << :show_id
      end
    end

    if AnilLanRework.connected?
      commands << _INTL("Jogadores Online")
      actions << :online_players
      commands << _INTL("PvP Finder") if defined?(AnilPvPFinder)
      actions << :pvp_finder if defined?(AnilPvPFinder)
    end

    commands << _INTL("Cancelar")
    actions << :cancel

    header = if AnilLanRework.connected?
      role = AnilLanRework.host? ? _INTL("Host") : _INTL("Cliente")
      ch_label = "Canal #{$PokemonSystem ? $PokemonSystem.multiplayer_channel : 1}"
      AnilLanRework.ui_format("Multiplayer [{1}]\\n{2} - \\c[2]{3}\\c[0]", role, id_label, ch_label)
    else
      ch_label = "Canal Selecionado: #{$PokemonSystem ? $PokemonSystem.multiplayer_channel : 1}"
      _INTL("Multiplayer [desconectado]\\n{1} - \\c[2]{2}\\c[0]", id_label, ch_label)
    end

    choice = pbMessage(header, commands, commands.length)

    # Esconde e limpa o overlay quando o jogador escolhe uma opção
    overlay&.dispose rescue nil

    case actions[choice]
    when :pvp_finder
      AnilPvPFinder.open
      open
    when :online_players
      open_online_players_menu
      open
    when :show_id
      pbPlayDecisionSE() rescue nil
      pbMessage(_INTL("Seu ID Único de Jogador é:\\n\\c[3]#{online_id}\\c[0]\\n\\nUse este ID para receber prêmios, resgatar doações ou em contatos de suporte!"))
      open
    when :connect_vps
      target_ip   = (AnilLanRework.respond_to?(:dedicated_server_ip) ? AnilLanRework.dedicated_server_ip : "127.0.0.1")
      AnilLanRework.update_player_config
      player_id   = AnilLanRework.read_cfg("multiplayer_player.txt", "id", "jogador#{rand(9000) + 1000}")
      player_name = $player.name.to_s
      player_char = $game_player.character_name.to_s rescue "trainer_m"
      pbMessage(_INTL("Conectando ao servidor...\\wt[30]\\^"))
      ok = false
      begin
        ok = AnilLanRework.connect(target_ip, player_id, player_name, player_char, false)
      rescue => e
        AnilLanRework.log("F7 connection error: #{e.class}: #{e.message}")
      end
      if ok
        # Desativa o Turbo ao entrar no modo multiplayer
        $GameSpeed = 0 if defined?($GameSpeed)
        $CanToggle = false if defined?($CanToggle)
        pbMessage(_INTL("Conectado ao servidor!\\wt[40]\\^"))
        
        AnilLanRework.request_same_map_transfer!("join_vps_connect_same_map", 4)
        AnilLanRework.apply_pending_same_map_transfer!($scene)
      else
        err_msg = AnilLanRework.last_error_message.to_s
        err_msg = "tempo limite excedido" if err_msg.empty?
        pbMessage(_INTL("Não foi possível conectar ao servidor: {1}.", err_msg))
      end
    when :host
      return unless ensure_save_loaded("abrir")
      open_lobby_with_action(:host)
    when :join
      return unless ensure_save_loaded("entrar")
      open_lobby_with_action(:join)
    when :join_manual
      return unless ensure_save_loaded("entrar")
      do_join_manual_on_map
    when :change_channel
      return unless ensure_save_loaded("mudar canal")
      current_ch = $PokemonSystem ? $PokemonSystem.multiplayer_channel : 1
      commands = []
      (1..10).each do |ch|
        commands << (ch == current_ch ? _INTL("Canal {1} (Atual)", ch) : _INTL("Canal {1}", ch))
      end
      commands << _INTL("Voltar")
      choice = pbMessage(_INTL("Escolha um Canal para se conectar:"), commands, commands.length)
      if choice >= 0 && choice < 10
        new_ch = choice + 1
        if $PokemonSystem
          $PokemonSystem.multiplayer_channel = new_ch
        end
        # Se estivermos conectados, envia um pacote change_channel direto sem desconectar
        if AnilLanRework.connected? && defined?(AnilLanRework) && AnilLanRework.respond_to?(:online_session?) && AnilLanRework.online_session?
          begin
            AnilLanRework.connection.send_packet("change_channel", "channel_id" => new_ch)
          rescue => e
            AnilLanRework.log("F7 channel switch send error: #{e.class}: #{e.message}")
          end
        end
        open
      else
        open
      end
    when :character
      open_lobby_with_action(:character)
    when :rename
      change_player_name
    when :disconnect
      do_disconnect_from_menu
    when :debug_menu
      sub_commands = [
        _INTL("Debug Log (Atual: {1})", $anil_debug_log_enabled ? "ON" : "OFF"),
        _INTL("Abrir Menu de Debug"),
        _INTL("Cancelar")
      ]
      sub_choice = pbMessage(_INTL("Opções de Desenvolvimento / Debug:"), sub_commands, sub_commands.length)
      case sub_choice
      when 0
        $anil_debug_log_enabled = !$anil_debug_log_enabled
        status = $anil_debug_log_enabled ? "LIGADO" : "DESLIGADO"
        pbMessage(_INTL("Multiplayer Debug Log: {1}", status))
        open
      when 1
        pbFadeOutIn do
          pbDebugMenu
        end
        open
      else
        open
      end
    end
  ensure
    @active = was_active
    if $anil_channel_hud
      $anil_channel_hud.update_hud(true) rescue nil
    end
    if $anil_map_name_hud
      $anil_map_name_hud.update_hud(true) rescue nil
    end
if $anil_partner_hud
  $anil_partner_hud.update_hud(true) rescue nil
end
  end
end

  # Lista remota: usa somente peers/dados que o servidor ja entregou ao cliente.
  # Mantido no mesmo escopo dos helpers existentes deste menu para compatibilidade JoiPlay.
  def open_online_players_menu
    unless AnilLanRework.connected?
      pbMessage(_INTL("Nao estas conectado ao multiplayer."))
      return
    end
    loop do
      peers = []
      begin
        AnilLanRework.players.each_value do |peer|
          next if !peer
          next if peer.respond_to?(:internal_id) && peer.internal_id.to_s.empty?
          peers << peer
        end
      rescue => e
        AnilLanRework.log("online players enumerate error #{e.class}: #{e.message}") rescue nil
        peers = []
      end
      peers.sort! { |a,b| a.name.to_s.downcase <=> b.name.to_s.downcase }
      if peers.empty?
        pbMessage(_INTL("Nenhum outro jogador esta disponivel neste canal."))
        return
      end
      commands = []
      peers.each do |peer|
        commands << _INTL("{1} - {2}", peer.name.to_s, online_peer_status_label(peer))
      end
      commands << _INTL("Atualizar")
      commands << _INTL("Voltar")
      choice = pbMessage(_INTL("Jogadores Online ({1})", peers.length), commands, commands.length)
      return if choice < 0 || choice == commands.length - 1
      next if choice == commands.length - 2
      peer = peers[choice]
      open_online_player_actions(peer) if peer
    end
  rescue => e
    AnilLanRework.log("online players menu error #{e.class}: #{e.message}") rescue nil
    pbMessage(_INTL("Nao foi possivel abrir a lista de jogadores."))
  end

  def online_peer_status_label(peer)
    begin
      return _INTL("Em batalha") if peer.respond_to?(:battle_busy) && peer.battle_busy
      return _INTL("Em menu") if peer.respond_to?(:menu_open) && peer.menu_open
    rescue
    end
    return _INTL("Disponivel")
  end

  def online_remote_party_count(peer)
    begin
      party = AnilLanRework::Serializer.deserialize_party(peer.party_blob)
      return Array(party).compact.select { |p| p.respond_to?(:species) }.length
    rescue
      return 0
    end
  end

  def open_online_player_actions(peer)
    return if !peer
    loop do
      begin
        map_id = peer.respond_to?(:map_id) ? peer.map_id : "?"
      rescue
        map_id = "?"
      end
      begin
        pid = peer.respond_to?(:display_id) ? peer.display_id : nil
        pid = peer.internal_id if (pid.nil? || pid.to_s.empty?) && peer.respond_to?(:internal_id)
      rescue
        pid = "?"
      end
      pid = "?" if pid.nil? || pid.to_s.empty?
      count = online_remote_party_count(peer)
      header = _INTL("{1}\nID: {2} | Mapa: {3}\nStatus: {4} | Pokemon: {5}", peer.name.to_s, pid.to_s, map_id.to_s, online_peer_status_label(peer), count)
      commands = [_INTL("Ver Pokemon"), _INTL("Desafiar para PvP"), _INTL("Voltar")]
      choice = pbMessage(header, commands, commands.length)
      case choice
      when 0
        # O servidor nao envia necessariamente a party de todos os peers no join.
        # Usa o fluxo oficial ja existente no PvP: party_request -> party_sync.
        has_party = peer.respond_to?(:party_blob) && peer.party_blob && !peer.party_blob.empty?
        unless has_party
          pbMessage(_INTL("Solicitando equipe de {1}...", peer.name.to_s))
          if defined?(AnilLanRework::BattleSync) && AnilLanRework::BattleSync.respond_to?(:wait_for_party)
            has_party = AnilLanRework::BattleSync.wait_for_party(peer, 2.5)
          end
        end
        if has_party
          AnilLanRework::PlayerMarket.open_peer_follower_summary(peer)
        else
          pbMessage(_INTL("Nao foi possivel obter os Pokemon desse jogador. O servidor pode limitar a consulta entre mapas."))
        end
      when 1
        if defined?(AnilLanRework::BattleSync) && AnilLanRework::BattleSync.respond_to?(:request_custom_duel)
          AnilLanRework::BattleSync.request_custom_duel(peer)
        else
          pbMessage(_INTL("O sistema de PvP nao esta disponivel nesta sessao."))
        end
      else
        return
      end
    end
  rescue => e
    AnilLanRework.log("online player actions error #{e.class}: #{e.message}") rescue nil
    pbMessage(_INTL("Nao foi possivel abrir as opcoes desse jogador."))
  end

  # Submenu de opcoes desativado temporariamente no F7.
  def option_state_label(enabled)
    enabled ? _INTL("On") : _INTL("Off")
  end

  # Submenu de opcoes desativado temporariamente no F7.
  def open_options_menu
    loop do
      commands = [
        _INTL("Coop Parcial {1}", option_state_label(AnilLanRework.coop_partial_enabled?)),
        _INTL("Coop Total {1}", option_state_label(AnilLanRework.coop_total_enabled?)),
        _INTL("Voltar")
      ]
      header = _INTL("Opcoes do Multiplayer")
      choice = pbMessage(header, commands, commands.length)
      case choice
      when 0
        enabled = !AnilLanRework.coop_partial_enabled?
        AnilLanRework.set_coop_partial_enabled(enabled)
        pbMessage(enabled ?
          _INTL("Coop Parcial ativado. O Coop Total foi desligado automaticamente.") :
          _INTL("Coop Parcial desativado.")
        )
      when 1
        enabled = !AnilLanRework.coop_total_enabled?
        AnilLanRework.set_coop_total_enabled(enabled)
        pbMessage(enabled ?
          _INTL("Coop Total ativado. O Coop Parcial foi desligado automaticamente.\nReconecte a sessao para aplicar totalmente a sincronizacao de mundo.") :
          _INTL("Coop Total desativado.")
        )
      else
        break
      end
    end
  end

  def change_player_name
    return unless ensure_save_loaded("mudar nome")
    current_name = $player.name.to_s
    new_name = prompt_player_name_for_multiplayer(current_name)
    new_name = new_name.to_s.strip
    return if new_name.empty?
    return if new_name == current_name
    $player.name = new_name
    AnilLanRework.self_name = new_name
    AnilLanRework.update_player_config
    if AnilLanRework.connected?
      pbMessage(_INTL("Nome alterado. Reconecte a sessao para que os outros jogadores vejam o novo nome."))
    else
      pbMessage(_INTL("Nome alterado com sucesso."))
    end
  rescue => e
    AnilLanRework.log("change_player_name error #{e.class}: #{e.message}")
    pbMessage(_INTL("Nao foi possivel alterar o nome agora."))
  end

  def prompt_player_name_for_multiplayer(current_name)
    help_text = _INTL("Novo nome do jogador?")
    return pbEnterPlayerName(help_text, 1, Settings::MAX_PLAYER_NAME_SIZE, current_name, true) unless $joiplay

    ret = ""
    pbFadeOutIn(99999, true) do
      scene = MultiplayerJoiPlayPlayerNameEntryScene.new
      screen = PokemonEntry.new(scene)
      ret = screen.pbStartScreen(help_text, 1, Settings::MAX_PLAYER_NAME_SIZE, current_name, 1, nil)
    end
    ret
  end

  def do_disconnect_from_menu
    if AnilLanRework.connected?
      return unless pbConfirmMessage(_INTL("Desconectar da sessao multiplayer atual?"))
      AnilLanRework.disconnect
      AnilLanRework.request_map_graphics_refresh!("menu_disconnect", 1)
      pbMessage(_INTL("Desconectado com sucesso."))
    else
      pbMessage(_INTL("Nao ha nenhuma sessao multiplayer ativa."))
    end
  end

  def open_lobby_with_action(action)
    case action
    when :character
      pbFadeOutIn do
        AnilLanRework.clear_input_buffer
        scene = Scene_CharacterSelect.new
        scene.main
        AnilLanRework.wipe_stuck_graphics!(true) rescue nil
        AnilLanRework.clear_input_buffer
      end
      return
    when :host
      do_host_on_map
    when :join
      do_join_on_map
    end
  end

  def do_host_on_map
    player_id = AnilLanRework.read_cfg(AnilLanRework::PLAYER_CFG, "id", AnilLanRework.machine_token).to_s
    player_id = AnilLanRework.machine_token if player_id.empty?
    player_name = ($player&.name || "Jogador").to_s
    player_char = ($player&.multiplayer_skin || $game_player&.character_name).to_s

    # -------------------------------------------------------------
    # SELEÇÃO DE IP PARA HOSPEDAR (Local ou ZeroTier)
    # -------------------------------------------------------------
    dedicated_ip_for_filter = (AnilLanRework.respond_to?(:dedicated_server_ip) ? AnilLanRework.dedicated_server_ip : nil).to_s.strip
    ips = AnilLanRework.local_ipv4_candidates.reject { |ip| !dedicated_ip_for_filter.empty? && ip.to_s.strip == dedicated_ip_for_filter }
    ip_commands = ips.map { |ip| "#{ip} [#{AnilLanRework.detect_network_type(ip)}]" }
    ip_commands << _INTL("Todas as redes (0.0.0.0)")
    ip_commands << _INTL("Cancelar")

    choice = pbMessage(_INTL("Em qual rede deseja abrir o servidor?"), ip_commands, ip_commands.length)
    return if choice < 0 || choice == ip_commands.length - 1

    bind_ip = (choice == ip_commands.length - 2) ? "0.0.0.0" : ips[choice]
    connect_ip = (bind_ip == "0.0.0.0") ? "127.0.0.1" : bind_ip
    
    # Detectar se é ZeroTier e adicionar mensagem informativa
    net_type = AnilLanRework.detect_network_type(bind_ip)
    if net_type.include?("ZeroTier")
      pbMessage(_INTL("Iniciando servidor ZeroTier em {1}...\wt[30]\^", bind_ip))
      pbMessage(_INTL("Para jogadores remotos: procure por este servidor na lista de conexões!"))
    else
      pbMessage(_INTL("Iniciando servidor em {1}...\wt[30]\^", bind_ip))
    end

    unless $anil_lan_server_thread&.alive?
      $anil_lan_server_thread = Thread.new do
        begin
          LanCableReworkServer.new(bind_ip).run
        rescue => e
          AnilLanRework.log("server thread error #{e.class}: #{e.message}")
        end
      end
    end

    server_ready = false
    start_time = Time.now.to_f
    while Time.now.to_f - start_time < 5.0
      begin
        probe = TCPSocket.new(connect_ip, AnilLanRework::SERVER_PORT)
        probe.close
        server_ready = true
        break
      rescue
        sleep(0.1)
      end
    end

    unless server_ready
      pbMessage(_INTL("ERRO: O servidor local nao pode ser iniciado no IP {1}.", bind_ip))
      return
    end

    # Desativa o Turbo ao entrar no modo multiplayer
    $GameSpeed = 0 if defined?($GameSpeed)
    $CanToggle = false if defined?($CanToggle)
    ok = AnilLanRework.connect(connect_ip, player_id, player_name, player_char, true)
    if ok
      pbMessage(_INTL("Servidor iniciado! Voce é o Host em {1}.\wt[40]\^", connect_ip))
      AnilLanRework.request_same_map_transfer!("host_connect_same_map", 4)
      AnilLanRework.apply_pending_same_map_transfer!($scene)
    else
      pbMessage(AnilLanRework.ui_format("ERRO ao se conectar: {1}", AnilLanRework.last_error_message.to_s))
    end
  end

  def do_join_on_map
    player_id = AnilLanRework.read_cfg(AnilLanRework::PLAYER_CFG, "id", AnilLanRework.machine_token).to_s
    player_id = AnilLanRework.machine_token if player_id.empty?
    player_name = ($player&.name || "Jogador").to_s
    player_char = ($player&.multiplayer_skin || $game_player&.character_name).to_s
    saved_ip = AnilLanRework.read_cfg(AnilLanRework::IP_CFG, "ip", "127.0.0.1")

    pbMessage(_INTL("A procurar hosts na rede local...\\wt[30]\\^"))
    hosts = AnilLanRework.discover_hosts

    # Ordenar hosts para priorizar Wi-Fi/LAN local
    hosts = hosts.sort_by do |host|
      ip = host["ip"].to_s
      net_type = AnilLanRework.detect_network_type(ip)
      case net_type
      when /Wi-Fi/ then 0      # Prioridade máxima para Wi-Fi local
      when /LAN/ then 1        # Segunda prioridade para LAN
      when /ZeroTier/ then 2   # Terceira prioridade para ZeroTier
      when /VPN/ then 3        # Quarta prioridade para outras VPNs
      else 4                   # Menor prioridade para outros
      end
    end

    if hosts.empty?
      pbMessage(_INTL("Nenhum host encontrado na rede. A tentar IP salvo...\wt[30]\^"))
      target_ip = saved_ip
      chosen = nil
    else
      commands = hosts.map { |h| AnilLanRework.discovered_host_label(h) }
      commands << _INTL("Usar IP salvo")
      commands << _INTL("Diagnóstico de conexão")
      commands << _INTL("Cancelar")

      choice = pbMessage(_INTL("Escolha um Host online (ZeroTier priorizado):"), commands, commands.length)
      
      if choice == commands.length - 2  # Diagnóstico
        AnilLanRework.diagnose_connection_issues
        pbMessage(_INTL("Diagnóstico completo. Verifique o log para detalhes.\\wt[60]\\^"))
        return
      end
      if choice < 0 || choice == commands.length - 1
        return
      elsif choice == commands.length - 3  # Usar IP salvo agora é -3
        target_ip = saved_ip
        chosen = nil
      else
        chosen = hosts[choice]
        target_ip = chosen["ip"].to_s
        AnilLanRework.write_cfg(AnilLanRework::IP_CFG, "ip", target_ip)
      end
    end

    dedicated_ip = (AnilLanRework.respond_to?(:dedicated_server_ip) ? AnilLanRework.dedicated_server_ip : "127.0.0.1")
    if target_ip.to_s.strip == dedicated_ip
      pbPlayBuzzerSE() rescue nil
      pbMessage(_INTL("ERRO: O IP do servidor principal não é permitido no modo LAN. Se quiser jogar no servidor, use a opção 'Conectar ao Servidor'."))
      return
    end

    alt_ips = chosen ? Array(chosen["alt_ips"]) : []
    
    # Tentar conectar com múltiplos IPs (importante para ZeroTier)
    ok = false
    all_ips = [target_ip] + alt_ips
    
    # Log para debug de conexão ZeroTier
    AnilLanRework.log("Attempting connection to #{target_ip} with alt_ips: #{alt_ips.inspect}")
    
    all_ips.each_with_index do |ip, index|
      next if ip.empty?
      net_type = AnilLanRework.detect_network_type(ip)
      AnilLanRework.log("Trying connection #{index + 1}/#{all_ips.length} to #{ip} [#{net_type}]")
      
      ok = AnilLanRework.connect(ip, player_id, player_name, player_char, false, all_ips - [ip])
      if ok
        AnilLanRework.write_cfg(AnilLanRework::IP_CFG, "ip", ip) # Salvar IP que funcionou
        # Desativa o Turbo ao entrar no modo multiplayer
        $GameSpeed = 0 if defined?($GameSpeed)
        $CanToggle = false if defined?($CanToggle)
        pbMessage(_INTL("Conectado com sucesso via {1}!\\wt[40]\\^", net_type))
        break
      else
        error_msg = AnilLanRework.last_error_message.to_s
        AnilLanRework.log("Connection to #{ip} failed: #{error_msg}")
        pbMessage(AnilLanRework.ui_format("Falha em {1}: {2}. Tentando próximo...\\wt[20]\\^", net_type, error_msg)) if index < all_ips.length - 1
      end
    end
    
    if ok
      AnilLanRework.request_same_map_transfer!("join_connect_same_map", 4)
      AnilLanRework.apply_pending_same_map_transfer!($scene)
    else
      pbMessage(AnilLanRework.ui_format("ERRO: Não foi possível conectar com nenhum dos IPs disponíveis. Verifique se o host está online e acessível."))
    end
  end

  def do_join_manual_on_map
    player_id = AnilLanRework.read_cfg(AnilLanRework::PLAYER_CFG, "id", AnilLanRework.machine_token).to_s
    player_id = AnilLanRework.machine_token if player_id.empty?
    player_name = ($player&.name || "Jogador").to_s
    player_char = ($player&.multiplayer_skin || $game_player&.character_name).to_s
    saved_ip = AnilLanRework.read_cfg(AnilLanRework::IP_CFG, "ip", "127.0.0.1")

    target_ip = pbMessageFreeText(_INTL("Digite o IP do Host:"), saved_ip, false, 20)
    return if target_ip.nil? || target_ip.strip.empty?
    target_ip = target_ip.strip

    dedicated_ip = (AnilLanRework.respond_to?(:dedicated_server_ip) ? AnilLanRework.dedicated_server_ip : "127.0.0.1")
    if target_ip == dedicated_ip
      pbPlayBuzzerSE() rescue nil
      pbMessage(_INTL("ERRO: O IP do servidor principal não é permitido no modo LAN. Se quiser jogar no servidor, use a opção 'Conectar ao Servidor'."))
      return
    end

    AnilLanRework.write_cfg(AnilLanRework::IP_CFG, "ip", target_ip)

    ok = AnilLanRework.connect(target_ip, player_id, player_name, player_char, false)
    if ok
      # Desativa o Turbo ao entrar no modo multiplayer
      $GameSpeed = 0 if defined?($GameSpeed)
      $CanToggle = false if defined?($CanToggle)
      pbMessage(_INTL("Conectado com sucesso!\\wt[40]\\^"))
      AnilLanRework.request_same_map_transfer!("join_manual_connect_same_map", 4)
      AnilLanRework.apply_pending_same_map_transfer!($scene)
    else
      err_msg = AnilLanRework.last_error_message.to_s
      if err_msg.start_with?("BANNED:")
        return
      else
        pbMessage(AnilLanRework.ui_format("ERRO ao conectar: {1}", err_msg))
      end
    end
  end

  def localhost_server_ready?
    probe = TCPSocket.new("127.0.0.1", AnilLanRework::SERVER_PORT)
    probe.close
    true
  rescue
    false
  end

  def ensure_save_loaded(mode_label)
    return true if save_is_loaded?

    pbMessage(_INTL(
      "Nenhum save carregado.\nEscolha um save para usar no Multiplayer ({1}).",
      mode_label
    ))

    result = load_save_for_multiplayer
    unless result
      pbMessage(_INTL("Nenhum save selecionado. Operacao cancelada."))
      return false
    end
    true
  end

  def save_is_loaded?
    return false unless defined?($player) && $player
    return false if $player.name.to_s.empty?
    return false unless defined?($game_map) && $game_map
    true
  rescue
    false
  end

  def load_save_for_multiplayer
    scene = UI::Load.new rescue nil
    unless scene
      begin
        pbFadeOutIn { $scene = Scene_Load.new }
        return save_is_loaded?
      rescue
        return false
      end
    end

    pbFadeOutIn do
      scene.main
    end
    save_is_loaded?
  rescue => e
    AnilLanRework.log("load_save_for_multiplayer error #{e.class}: #{e.message}")
    false
  end
end

module AnilLanRework
  @last_player_x = 0
  @last_player_y = 0
  @last_player_dir = 0
  @last_player_map_id = 0
  @last_active_time = nil

  def self.reset_active_time
    @last_active_time = Time.now.to_f
  end

  def self.update_active_time
    @last_active_time ||= Time.now.to_f
    
    current_x = ($game_player.x rescue 0)
    current_y = ($game_player.y rescue 0)
    current_dir = ($game_player.direction rescue 0)
    current_map = ($game_map.map_id rescue 0)
    
    if current_x != @last_player_x || current_y != @last_player_y || current_dir != @last_player_dir || current_map != @last_player_map_id
      @last_player_x = current_x
      @last_player_y = current_y
      @last_player_dir = current_dir
      @last_player_map_id = current_map
      reset_active_time
    elsif (Input.dir4 > 0 rescue false) || (Input.trigger?(Input::C) rescue false) || (Input.trigger?(Input::B) rescue false)
      reset_active_time
    end
  end

  def self.local_player_afk?
    return false unless @last_active_time
    Time.now.to_f - @last_active_time >= 60.0
  end

  @popup_manager = nil
  @corner_popup_manager = nil
  @chat_popup_manager = nil
  @main_popup_animations = []
  @corner_popup_animations = []
  @chat_popup_animations = []
  @gift_popup_animations = []
  @pending_popup_queue = []
  @pending_corner_queue = []
  @popup_queue_mutex = Mutex.new

  def self.player_busy_in_menu?
    return true if $game_temp && $game_temp.respond_to?(:in_menu) && $game_temp.in_menu
    return true if $game_temp && $game_temp.respond_to?(:message_window_showing) && $game_temp.message_window_showing
    return true if $scene && !$scene.is_a?(Scene_Map)
    return true if defined?(AnilLanRework) && AnilLanRework.respond_to?(:message_active) && AnilLanRework.message_active
    false
  end

  def self.merge_popup_text(existing_text, new_text)
    parse_gift = proc do |t|
      t = t.to_s.strip
      if t =~ /^(.+?)\s+recebeu\s+(\d+)x\s+(.+?)\s+de\s+presente!$/i
        rec, qty, it = $1.strip, $2.to_i, $3.strip
        rec = "Você" if rec =~ /^Voc/i
        [rec, qty, it]
      elsif t =~ /^(.+?)\s+recebeu\s+(.+?)\s+de\s+presente!$/i
        rec, qty, it = $1.strip, 1, $2.strip
        rec = "Você" if rec =~ /^Voc/i
        [rec, qty, it]
      elsif t =~ /^Todos\s+receberam\s+(\d+)x\s+(.+?)\s+de\s+presente!$/i
        ["Todos", $1.to_i, $2.strip]
      elsif t =~ /^Todos\s+receberam\s+(.+?)\s+de\s+presente!$/i
        ["Todos", 1, $1.strip]
      else
        nil
      end
    end

    p1 = parse_gift.call(existing_text)
    p2 = parse_gift.call(new_text)

    if p1 && p2 && p1[0].downcase == p2[0].downcase && p1[2].downcase == p2[2].downcase
      new_qty = p1[1] + p2[1]
      recipient = p1[0]
      item = p1[2]
      if recipient.downcase == "você"
        return _INTL("Você recebeu {1}x {2} de presente!", new_qty, item)
      elsif recipient.downcase == "todos"
        return _INTL("Todos receberam {1}x {2} de presente!", new_qty, item)
      else
        return _INTL("{1} recebeu {2}x {3} de presente!", recipient, new_qty, item)
      end
    end
    nil
  end

  def self.enqueue_popup(text, duration = 3.0, item_id = nil)
    if self.player_busy_in_menu?
      # Só presente enviado pelo servidor (tem item_id) pode ficar na fila até
      # o jogador fechar o menu. Qualquer outro broadcast é ignorado na hora.
      return if item_id.nil?
    end

    # Tenta mesclar com algum popup ativo na tela primeiro
    @gift_popup_animations ||= []
    @gift_popup_animations.delete_if { |anim| anim.disposed? rescue true }
    active_merged = false
    @gift_popup_animations.each do |anim|
      next if anim.disposed?
      merged_text = self.merge_popup_text(anim.text, text) rescue nil
      if merged_text
        anim.update_text(merged_text, duration) rescue nil
        active_merged = true
        break
      end
    end
    return if active_merged

    # Tenta mesclar com algum item na fila
    queue_merged = false
    @popup_queue_mutex.synchronize do
      @pending_popup_queue.each do |entry|
        merged_text = self.merge_popup_text(entry[:text], text) rescue nil
        if merged_text
          entry[:text] = merged_text
          entry[:duration] = [entry[:duration], duration].max
          queue_merged = true
          break
        end
      end
      
      unless queue_merged
        @pending_popup_queue << { text: text, duration: duration, item_id: item_id }
        # Limita tamanho da fila para evitar lag de exibição ao sair de menus
        @pending_popup_queue.shift while @pending_popup_queue.size > 3
      end
    end
  rescue => e
    log("enqueue_popup error: #{e.message}")
  end

  def self.flush_popup_queue
    return if self.player_busy_in_menu?
    
    @last_popup_flush_time ||= 0
    now = System.uptime rescue Time.now.to_f
    return if now - @last_popup_flush_time < 0.8
    
    entry = nil
    @popup_queue_mutex.synchronize do
      entry = @pending_popup_queue.shift
    end
    return unless entry
    
    @last_popup_flush_time = now
    add_popup(entry[:text], entry[:duration], entry[:item_id]) rescue nil
  rescue
  end

  def self.enqueue_corner_popup(text, duration = 4.0)
    if self.player_busy_in_menu?
      # Popup de canto nunca é presente do servidor — ocupado em menu, ignora tudo.
      return
    end

    @popup_queue_mutex.synchronize do
      @pending_corner_queue << { text: text, duration: duration }
      # Limita tamanho da fila para evitar lag de exibição ao sair de menus
      @pending_corner_queue.shift while @pending_corner_queue.size > 3
    end
  rescue
  end

  def self.flush_corner_queue
    return if self.player_busy_in_menu?
    
    @last_corner_flush_time ||= 0
    now = System.uptime rescue Time.now.to_f
    return if now - @last_corner_flush_time < 0.6
    
    entry = nil
    @popup_queue_mutex.synchronize do
      entry = @pending_corner_queue.shift
    end
    return unless entry
    
    @last_corner_flush_time = now
    add_corner_popup(entry[:text], entry[:duration]) rescue nil
  rescue
  end

  # ⚠️ O draw_text do RGSS ENCOLHE o texto para caber no rectangulo.
  #
  # Nao corta nem passa a linha: espreme as letras na horizontal ate caberem.
  # Era isso que fazia as mensagens compridas aparecerem em letra minuscula e
  # ilegivel no rodape. A solucao e nunca lhe dar mais texto do que cabe.
  #
  # Parte por espacos e, quando uma palavra sozinha nao cabe (um "aaaa...a"
  # nao tem espaco nenhum), parte a palavra letra a letra.
  def self.quebrar_texto(texto, bitmap, largura, max_linhas = 3)
    linhas = []
    actual = ""

    texto.to_s.split(" ").each do |palavra|
      if bitmap.text_size(palavra).width > largura
        unless actual.empty?
          linhas << actual
          actual = ""
        end
        pedaco = ""
        palavra.each_char do |c|
          if !pedaco.empty? && bitmap.text_size(pedaco + c).width > largura
            linhas << pedaco
            pedaco = c
          else
            pedaco += c
          end
        end
        actual = pedaco
        next
      end

      teste = actual.empty? ? palavra : "#{actual} #{palavra}"
      if bitmap.text_size(teste).width > largura
        linhas << actual unless actual.empty?
        actual = palavra
      else
        actual = teste
      end
    end

    linhas << actual unless actual.empty?
    linhas = [""] if linhas.empty?

    if linhas.length > max_linhas
      linhas = linhas[0, max_linhas]
      linhas[-1] = linhas[-1].to_s[0, [linhas[-1].to_s.length - 1, 1].max] + "..."
    end
    linhas
  rescue
    [texto.to_s]
  end

  # Onde e que o canto superior esquerdo fica livre. Com o HUD de grupo na tela
  # (260x40 em 10,10) os avisos de "entrou"/"saiu" caiam por cima dele.
  def self.topo_livre_y
    return 10 unless $anil_partner_hud
    return 10 unless ($anil_partner_hud.visivel? rescue false)
    56
  rescue
    10
  end

  def self.add_popup(text, duration = 3.0, item_id = nil)
    return if $game_temp && $game_temp.respond_to?(:in_battle) && $game_temp.in_battle
    if self.player_busy_in_menu?
      self.enqueue_popup(text, duration, item_id)
      return
    end
    return if item_id && add_gift_popup_animation(text, duration, item_id)
    return if add_main_popup_animation(text, duration)
    init_popups(nil) unless @popup_manager
    @popup_manager&.add(text, duration, item_id)
  end

  def self.add_corner_popup(text, duration = 4.0)
    return if $game_temp && $game_temp.respond_to?(:in_battle) && $game_temp.in_battle
    if self.player_busy_in_menu?
      self.enqueue_corner_popup(text, duration)
      return
    end
    if text.include?(" entrou") || text.include?(" saiu")
      return if add_corner_popup_animation(text, duration)
      init_popups(nil) unless @corner_popup_manager
      @corner_popup_manager&.add(text, duration)
    else
      return if add_chat_popup_animation(text, duration)
      init_popups(nil) unless @chat_popup_manager
      @chat_popup_manager&.add(text, duration)
    end
  end

  # ⚠️ APAGA O QUE JA ESTA NO ECRA, nao so o que vier a seguir.
  #
  # Quando o historico abre (segurar o T), o gancho do MOD 182 impede que
  # mensagens NOVAS virem popup. Mas as que ja la estavam continuavam a flutuar
  # por cima do painel ate o temporizador delas acabar — e a aparecer duas
  # vezes, uma na lista e outra no rodape.
  #
  # Aqui deitam-se fora as do rodape (chat) e as do canto (entrou/saiu). Nao se
  # perde nada: estao todas na lista, que e o que o jogador esta a olhar.
  # Os popups grandes de anuncio nao se tocam — esses nao sao chat.
  def self.limpar_popups_de_chat!
    dispose_chat_popup_animations
    dispose_corner_popup_animations
    @chat_popup_manager&.dispose
    @chat_popup_manager = ChatPopupManager.new(@popup_viewport)
    @corner_popup_manager&.dispose
    @corner_popup_manager = CornerPopupManager.new(@popup_viewport)
    # As filas de espera tambem, senao voltavam a nascer assim que o painel
    # fechasse — mensagens velhas a aparecer do nada.
    @popup_queue_mutex&.synchronize { @pending_corner_queue&.clear }
  rescue
  end

  def self.clear_popups
    @popup_manager&.dispose
    @popup_manager = PopupManager.new(@popup_viewport)
    @corner_popup_manager&.dispose
    @corner_popup_manager = CornerPopupManager.new(@popup_viewport)
    @chat_popup_manager&.dispose
    @chat_popup_manager = ChatPopupManager.new(@popup_viewport)
    dispose_main_popup_animations
    dispose_corner_popup_animations
    dispose_chat_popup_animations
    dispose_gift_popup_animations
  end

  def self.init_popups(viewport)
    @popup_manager&.dispose
    # Cria um viewport dedicado para garantir renderização acima de tudo no JoiPlay
    if viewport.nil? && defined?(Graphics)
      begin
        @popup_viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
        @popup_viewport.z = 999999
        viewport = @popup_viewport
      rescue
        @popup_viewport = nil
      end
    end
    @popup_manager = PopupManager.new(viewport)
    
    @corner_popup_manager&.dispose
    @corner_popup_manager = CornerPopupManager.new(viewport)

    @chat_popup_manager&.dispose
    @chat_popup_manager = ChatPopupManager.new(viewport)
  end

  def self.update_popups
    # ⚠️ NAO SE APAGA O AVISO: ADIA-SE.
    #
    # "Fulano entrou", "novas atualizacoes", o presente que chegou — nada disso
    # e urgente ao ponto de valer tapar uma luta. Deixa-se de ESVAZIAR a fila
    # enquanto a arena corre; os avisos ficam la e aparecem todos quando ela
    # acabar. Os que ja estavam no ecra terminam a sua animacao normalmente.
    unless (AnilArena.activa? rescue false)
      flush_popup_queue
      flush_corner_queue
    end
    @popup_manager&.update
    @corner_popup_manager&.update
    @chat_popup_manager&.update
  end


# Verdadeiro se algum popup "de topo" (broadcast/gift/aviso principal) estiver
# ativo na tela agora. Usado para esconder HUDs de topo (grupo/localizacao)
# enquanto o popup grande estiver visivel, evitando sobreposicao visual.
def self.top_broadcast_active?
  ((@main_popup_animations && @main_popup_animations.any? { |a| !(a.disposed? rescue true) }) ||
   (@gift_popup_animations && @gift_popup_animations.any? { |a| !(a.disposed? rescue true) }) ||
   (@popup_manager && @popup_manager.active?)) rescue false
end
  def self.dispose_popups
    @popup_manager&.dispose
    @popup_manager = nil
    @corner_popup_manager&.dispose
    @corner_popup_manager = nil
    @chat_popup_manager&.dispose
    @chat_popup_manager = nil
    dispose_main_popup_animations
    dispose_corner_popup_animations
    dispose_chat_popup_animations
    dispose_gift_popup_animations
    @popup_viewport&.dispose rescue nil
    @popup_viewport = nil
  end

  def self.can_use_map_popup_animations?
    return false unless $scene.is_a?(Scene_Map) rescue false
    viewport = Spriteset_Map.viewport rescue nil
    return !viewport.nil?
  end

  def self.add_main_popup_animation(text, duration = 3.0)
    return false unless can_use_map_popup_animations?
    viewport = Spriteset_Map.viewport rescue nil
    return false unless viewport
    @main_popup_animations ||= []
    @main_popup_animations.delete_if { |anim| anim.disposed? rescue true }
    while @main_popup_animations.size >= 10
      oldest = @main_popup_animations.shift
      oldest.dispose rescue nil
    end
    anim = MainTextPopupAnimation.new(viewport, text, @main_popup_animations.size, duration)
    @main_popup_animations << anim
    add_overworld_animation(anim)
    refresh_main_popup_animation_positions
    true
  rescue => e
    log("add_main_popup_animation error #{e.class}: #{e.message}")
    false
  end

  def self.refresh_main_popup_animation_positions
    @main_popup_animations ||= []
    @main_popup_animations.delete_if { |anim| anim.disposed? rescue true }
    @main_popup_animations.each_with_index do |anim, i|
      anim.reposition(i) rescue nil
    end
  end

  def self.dispose_main_popup_animations
    @main_popup_animations ||= []
    @main_popup_animations.each { |anim| anim.dispose rescue nil }
    @main_popup_animations.clear
  end

  def self.add_corner_popup_animation(text, duration = 4.0)
    return false unless can_use_map_popup_animations?
    viewport = Spriteset_Map.viewport rescue nil
    return false unless viewport
    @corner_popup_animations ||= []
    @corner_popup_animations.delete_if { |anim| anim.disposed? rescue true }
    while @corner_popup_animations.size >= 6
      oldest = @corner_popup_animations.shift
      oldest.dispose rescue nil
    end
    anim = CornerTextPopupAnimation.new(viewport, text, @corner_popup_animations.size, duration)
    @corner_popup_animations << anim
    add_overworld_animation(anim)
    refresh_corner_popup_animation_positions
    true
  rescue => e
    log("add_corner_popup_animation error #{e.class}: #{e.message}")
    false
  end

  def self.refresh_corner_popup_animation_positions
    @corner_popup_animations ||= []
    @corner_popup_animations.delete_if { |anim| anim.disposed? rescue true }
    size = @corner_popup_animations.size
    @corner_popup_animations.each_with_index do |anim, i|
      anim.reposition(size - 1 - i) rescue nil
    end
  end

  def self.dispose_corner_popup_animations
    @corner_popup_animations ||= []
    @corner_popup_animations.each { |anim| anim.dispose rescue nil }
    @corner_popup_animations.clear
  end

  def self.add_chat_popup_animation(text, duration = 4.0)
    return false unless can_use_map_popup_animations?
    viewport = Spriteset_Map.viewport rescue nil
    return false unless viewport
    @chat_popup_animations ||= []
    @chat_popup_animations.delete_if { |anim| anim.disposed? rescue true }
    while @chat_popup_animations.size >= 6
      oldest = @chat_popup_animations.shift
      oldest.dispose rescue nil
    end
    anim = ChatTextPopupAnimation.new(viewport, text, @chat_popup_animations.size, duration)
    @chat_popup_animations << anim
    add_overworld_animation(anim)
    refresh_chat_popup_animation_positions
    true
  rescue => e
    log("add_chat_popup_animation error #{e.class}: #{e.message}")
    false
  end

  # ⚠️ Empilha-se pela ALTURA de cada popup, nao por um passo fixo de 30px.
  # Desde que uma mensagem comprida passa a ocupar duas ou tres linhas, um passo
  # fixo punha-as uma por cima da outra.
  def self.refresh_chat_popup_animation_positions
    @chat_popup_animations ||= []
    @chat_popup_animations.delete_if { |anim| anim.disposed? rescue true }
    base = (Graphics.height rescue 384) - 10
    @chat_popup_animations.reverse_each do |anim|
      alt = (anim.altura rescue 30)
      base -= alt
      anim.posicionar_em(base) rescue nil
      base -= 2
    end
  end

  def self.dispose_chat_popup_animations
    @chat_popup_animations ||= []
    @chat_popup_animations.each { |anim| anim.dispose rescue nil }
    @chat_popup_animations.clear
  end

  def self.add_gift_popup_animation(text, duration = 3.0, item_id = nil)
    return false unless item_id
    return false unless $scene.is_a?(Scene_Map) rescue false
    viewport = Spriteset_Map.viewport rescue nil
    return false unless viewport

    @gift_popup_animations ||= []
    @gift_popup_animations.delete_if { |anim| anim.disposed? rescue true }

    # Tenta mesclar com algum popup ativo na tela primeiro
    @gift_popup_animations.each do |anim|
      next if anim.disposed?
      merged_text = self.merge_popup_text(anim.text, text) rescue nil
      if merged_text
        anim.update_text(merged_text, duration) rescue nil
        return true
      end
    end

    while @gift_popup_animations.size >= 10
      oldest = @gift_popup_animations.shift
      oldest.dispose rescue nil
    end

    anim = GiftPopupAnimation.new(viewport, text, @gift_popup_animations.size, duration, item_id)
    @gift_popup_animations << anim
    add_overworld_animation(anim)
    refresh_gift_popup_animation_positions
    true
  rescue => e
    log("add_gift_popup_animation error #{e.class}: #{e.message}")
    false
  end

  def self.refresh_gift_popup_animation_positions
    @gift_popup_animations ||= []
    @gift_popup_animations.delete_if { |anim| anim.disposed? rescue true }
    @gift_popup_animations.each_with_index do |anim, i|
      anim.reposition(i) rescue nil
    end
  end

  def self.dispose_gift_popup_animations
    @gift_popup_animations ||= []
    @gift_popup_animations.each { |anim| anim.dispose rescue nil }
    @gift_popup_animations.clear
  end

  class PopupManager
    def initialize(viewport)
      @viewport = viewport
      @popups = []
    end

    def active?
      @popups.any? { |p| !(p.disposed? rescue true) }
    end

    def add(text, duration = 3.0, item_id = nil)
      # Limite de segurança: no máximo 10 popups ativos ao mesmo tempo
      while @popups.size >= 10
        oldest = @popups.shift
        oldest.dispose rescue nil
      end
      
      @popups << Popup.new(@viewport, text, @popups.size, duration, item_id)
      
      # Re-posiciona todos para garantir que a ordem e as posições batam
      @popups.each_with_index do |p, i|
        p.reposition(i)
      end
    end

    def update
      @popups.each(&:update)
      if @popups.any?(&:disposed?)
        @popups.delete_if(&:disposed?)
        # Re-posiciona os popups restantes
        @popups.each_with_index do |p, i|
          p.reposition(i)
        end
      end
    end

    def dispose
      @popups.each(&:dispose)
      @popups.clear
    end
  end

  class GiftPopupAnimation
    attr_reader :disposed
    attr_reader :text

    def initialize(viewport, text, index, duration = 3.0, item_id = nil)
      @viewport = viewport
      @text = text
      @sprite = Sprite.new(viewport)
      @sprite.z = 100001

      w = [Graphics.width - 40, 420].max
      h = 36
      @sprite.bitmap = Bitmap.new(w, h)
      @sprite.x = (Graphics.width - w) / 2

      begin
        fade_w = (w * 0.25).to_i
        @sprite.bitmap.gradient_fill_rect(0, 0, fade_w, h, Color.new(0, 0, 0, 0), Color.new(0, 0, 0, 200), false)
        @sprite.bitmap.fill_rect(fade_w, 0, w - 2 * fade_w, h, Color.new(0, 0, 0, 200))
        @sprite.bitmap.gradient_fill_rect(w - fade_w, 0, fade_w, h, Color.new(0, 0, 0, 200), Color.new(0, 0, 0, 0), false)
      rescue
        @sprite.bitmap.fill_rect(0, 0, w, h, Color.new(0, 0, 0, 180)) rescue nil
      end

      begin
        @sprite.bitmap.font.size = 18
        @sprite.bitmap.font.bold = true
      rescue
      end

      icon_bmp = nil
      begin
        fallback_color = Color.new(200, 200, 200)
        if defined?(GiftBoxSystem)
          icon_bmp = GiftBoxSystem.load_item_icon(item_id, fallback_color) rescue nil
        else
          filename = GameData::Item.icon_filename(item_id) rescue nil
          icon_bmp = filename ? Bitmap.new(filename) : nil rescue nil
        end
      rescue
      end

      if icon_bmp && icon_bmp.width > icon_bmp.height
        cropped = Bitmap.new(icon_bmp.height, icon_bmp.height)
        cropped.blt(0, 0, icon_bmp, Rect.new(0, 0, icon_bmp.height, icon_bmp.height))
        icon_bmp.dispose rescue nil
        icon_bmp = cropped
      end

      icon_w = 28
      icon_h = 28
      spacing = 8
      text_w = w - 40
      begin
        text_w = @sprite.bitmap.text_size(text).width + 12
      rescue
      end

      total_w = text_w
      total_w += spacing + icon_w if icon_bmp
      start_x = (w - total_w) / 2

      begin
        @sprite.bitmap.font.color = Color.new(0, 0, 0, 200)
        @sprite.bitmap.draw_text(start_x + 1, 8, text_w, h - 10, text, 0)
      rescue
      end

      begin
        @sprite.bitmap.font.color = Color.new(255, 220, 50)
        @sprite.bitmap.draw_text(start_x, 7, text_w, h - 10, text, 0)
      rescue
      end

      @icon_sprite = nil
      if icon_bmp
        begin
          @icon_sprite = Sprite.new(viewport)
          @icon_sprite.bitmap = icon_bmp
          @icon_sprite.z = @sprite.z + 1
          @icon_sprite.ox = icon_bmp.width / 2 rescue 14
          @icon_sprite.oy = icon_bmp.height / 2 rescue 14
          @icon_base_x = start_x + text_w + spacing + (icon_w / 2)
          @icon_base_y = h / 2
          @icon_sprite.x = @sprite.x + @icon_base_x
        rescue => e
          AnilLanRework.log("Error creating gift popup icon sprite: #{e.message}")
          icon_bmp.dispose rescue nil
        end
      end

      reposition(index)
      @timer = (Graphics.frame_count rescue 0) + ((Graphics.frame_rate rescue 40) * duration).to_i
      @disposed = false
    end

    def reposition(index)
      return if @disposed
      @sprite.y = 13 + (index * 40)
      if @icon_sprite && !@icon_sprite.disposed?
        @icon_sprite.y = @sprite.y + @icon_base_y
      end
    end

    def update
      return if @disposed
      if (Graphics.frame_count rescue 0) > @timer
        dispose
        return
      end

      if @icon_sprite && !@icon_sprite.disposed?
        time = (System.uptime rescue Time.now.to_f).to_f
        scale = 1.05 + 0.10 * Math.sin(time * 5.0)
        @icon_sprite.zoom_x = scale rescue 1.0
        @icon_sprite.zoom_y = scale rescue 1.0
        @icon_sprite.angle = 8.0 * Math.sin(time * 3.5) rescue 0.0
      end
    end

    def update_text(new_text, new_duration = nil)
      return if @disposed
      @text = new_text
      
      return unless @sprite && !@sprite.disposed? && @sprite.bitmap
      w = @sprite.bitmap.width
      h = @sprite.bitmap.height
      @sprite.bitmap.clear
      
      begin
        fade_w = (w * 0.25).to_i
        @sprite.bitmap.gradient_fill_rect(0, 0, fade_w, h, Color.new(0, 0, 0, 0), Color.new(0, 0, 0, 200), false)
        @sprite.bitmap.fill_rect(fade_w, 0, w - 2 * fade_w, h, Color.new(0, 0, 0, 200))
        @sprite.bitmap.gradient_fill_rect(w - fade_w, 0, fade_w, h, Color.new(0, 0, 0, 200), Color.new(0, 0, 0, 0), false)
      rescue
        @sprite.bitmap.fill_rect(0, 0, w, h, Color.new(0, 0, 0, 180)) rescue nil
      end
      
      text_w = w - 40
      begin
        text_w = @sprite.bitmap.text_size(@text).width + 12
      rescue
      end
      
      icon_w = 28
      spacing = 8
      total_w = text_w
      icon_bmp = @icon_sprite&.bitmap
      total_w += spacing + icon_w if icon_bmp
      start_x = (w - total_w) / 2
      
      begin
        @sprite.bitmap.font.color = Color.new(0, 0, 0, 200)
        @sprite.bitmap.draw_text(start_x + 1, 8, text_w, h - 10, @text, 0)
      rescue
      end
      
      begin
        @sprite.bitmap.font.color = Color.new(255, 220, 50)
        @sprite.bitmap.draw_text(start_x, 7, text_w, h - 10, @text, 0)
      rescue
      end
      
      if @icon_sprite && !@icon_sprite.disposed?
        @icon_base_x = start_x + text_w + spacing + (icon_w / 2)
        @icon_sprite.x = @sprite.x + @icon_base_x
      end
      
      if new_duration
        @timer = (Graphics.frame_count rescue 0) + ((Graphics.frame_rate rescue 40) * new_duration).to_i
      end
    end

    def dispose
      return if @disposed
      @sprite.bitmap&.dispose rescue nil
      @sprite.dispose rescue nil
      if @icon_sprite
        @icon_sprite.bitmap&.dispose rescue nil
        @icon_sprite.dispose rescue nil
      end
      @disposed = true
    end

    def disposed?
      @disposed
    end
  end

  class MainTextPopupAnimation
    attr_reader :disposed

    def initialize(viewport, text, index, duration = 3.0)
      @sprite = Sprite.new(viewport)
      @sprite.z = 100001

      w = [Graphics.width - 40, 420].max
      h = 36
      @sprite.bitmap = Bitmap.new(w, h)
      @sprite.x = (Graphics.width - w) / 2

      begin
        @sprite.bitmap.fill_rect(0, 0, w, h, Color.new(0, 0, 0, 180))
      rescue
      end

      begin
        @sprite.bitmap.font.size = 18
        @sprite.bitmap.font.bold = true
      rescue
      end

      begin
        @sprite.bitmap.font.color = Color.new(0, 0, 0, 200)
        @sprite.bitmap.draw_text(1, 8, w, h - 10, text, 1)
      rescue
      end

      begin
        @sprite.bitmap.font.color = Color.new(255, 220, 50)
        @sprite.bitmap.draw_text(0, 7, w, h - 10, text, 1)
      rescue
      end

      reposition(index)
      @timer = (Graphics.frame_count rescue 0) + ((Graphics.frame_rate rescue 40) * duration).to_i
      @disposed = false
    end

    def reposition(index)
      return if @disposed
      @sprite.y = 13 + (index * 40)
    end

    def update
      return if @disposed
      dispose if (Graphics.frame_count rescue 0) > @timer
    end

    def dispose
      return if @disposed
      @sprite.bitmap&.dispose rescue nil
      @sprite.dispose rescue nil
      @disposed = true
    end

    def disposed?
      @disposed
    end
  end

  class CornerTextPopupAnimation
    attr_reader :disposed

    def initialize(viewport, text, index, duration = 4.0)
      @sprite = Sprite.new(viewport)
      @sprite.z = 100001

      w = 230
      h = 26
      @sprite.bitmap = Bitmap.new(w, h)
      @sprite.x = 10

      text_color = Color.new(255, 255, 255)
      if text.include?(" entrou")
        text_color = Color.new(120, 255, 120)
      elsif text.include?(" saiu")
        text_color = Color.new(255, 120, 120)
      end

      begin
        @sprite.bitmap.fill_rect(0, 0, w, h, Color.new(0, 0, 0, 150))
      rescue
      end

      begin
        left_border_color = if text.include?(" entrou")
                              Color.new(46, 204, 113)
                            elsif text.include?(" saiu")
                              Color.new(231, 76, 60)
                            else
                              Color.new(52, 152, 219)
                            end
        @sprite.bitmap.fill_rect(0, 0, 3, h, left_border_color)
      rescue
      end

      begin
        @sprite.bitmap.font.size = 18
        @sprite.bitmap.font.bold = true
        @sprite.bitmap.font.name = MessageConfig::FONT_NAME rescue (Font.default_name rescue "Arial")
      rescue
      end

      begin
        @sprite.bitmap.font.color = Color.new(0, 0, 0, 220)
        @sprite.bitmap.draw_text(9, 1, w - 12, h, text, 0)
      rescue
      end

      begin
        @sprite.bitmap.font.color = text_color
        @sprite.bitmap.draw_text(8, 0, w - 12, h, text, 0)
      rescue
      end

      reposition(index)
      @timer = (Graphics.frame_count rescue 0) + ((Graphics.frame_rate rescue 40) * duration).to_i
      @disposed = false
    end

    def reposition(pos_index)
      return if @disposed
      @pos_idx = pos_index
      @sprite.y = (AnilLanRework.topo_livre_y rescue 10) + (pos_index * 24)
    end

    def update
      return if @disposed
      # Ver a nota no CornerPopup: o HUD de grupo vai e vem.
      reposition(@pos_idx || 0)
      dispose if (Graphics.frame_count rescue 0) > @timer
    end

    def dispose
      return if @disposed
      @sprite.bitmap&.dispose rescue nil
      @sprite.dispose rescue nil
      @disposed = true
    end

    def disposed?
      @disposed
    end
  end

  class ChatTextPopupAnimation
    LINHA_H    = 21
    MARGEM_V   = 5
    MAX_LINHAS = 3

    attr_reader :disposed
    attr_reader :altura

    def initialize(viewport, text, index, duration = 10.0)
      @sprite = Sprite.new(viewport)
      @sprite.z = 100001

      w = 430
      fonte = (MessageConfig::FONT_NAME rescue (Font.default_name rescue "Arial"))

      # Mede-se num bitmap a parte, com a MESMA fonte com que se vai desenhar.
      medidor = Bitmap.new(8, 8)
      begin
        medidor.font.size = 19
        medidor.font.bold = true
        medidor.font.name = fonte
      rescue
      end
      linhas = AnilLanRework.quebrar_texto(text, medidor, w - 16, MAX_LINHAS)
      medidor.dispose rescue nil

      h = (MARGEM_V * 2) + (linhas.length * LINHA_H)
      @altura = h

      @sprite.bitmap = Bitmap.new(w, h)
      @sprite.x = 10

      begin
        @sprite.bitmap.fill_rect(0, 0, w, h, Color.new(0, 0, 0, 150))
      rescue
      end

      begin
        @sprite.bitmap.fill_rect(0, 0, 3, h, Color.new(52, 152, 219))
      rescue
      end

      begin
        @sprite.bitmap.font.size = 19
        @sprite.bitmap.font.bold = true
        @sprite.bitmap.font.name = fonte
      rescue
      end

      linhas.each_with_index do |linha, i|
        y = MARGEM_V + (i * LINHA_H)
        begin
          @sprite.bitmap.font.color = Color.new(0, 0, 0, 220)
          @sprite.bitmap.draw_text(9, y + 1, w - 12, LINHA_H, linha, 0)
        rescue
        end
        begin
          @sprite.bitmap.font.color = Color.new(255, 255, 255)
          @sprite.bitmap.draw_text(8, y, w - 12, LINHA_H, linha, 0)
        rescue
        end
      end

      @timer = (Graphics.frame_count rescue 0) + ((Graphics.frame_rate rescue 40) * duration).to_i
      @disposed = false
    end

    # y = topo do popup, ja calculado pelo gestor a partir das alturas.
    def posicionar_em(y)
      return if @disposed
      @sprite.y = y
    end

    # Compatibilidade: alguem que ainda chame pelo indice antigo.
    def reposition(pos_index)
      return if @disposed
      posicionar_em(((Graphics.height rescue 384) - 10) - ((pos_index + 1) * (@altura || 30)))
    end

    def update
      return if @disposed
      dispose if (Graphics.frame_count rescue 0) > @timer
    end

    def dispose
      return if @disposed
      @sprite.bitmap&.dispose rescue nil
      @sprite.dispose rescue nil
      @disposed = true
    end

    def disposed?
      @disposed
    end
  end


  class Popup
    attr_reader :disposed

    def initialize(viewport, text, index, duration = 3.0, item_id = nil)
      @sprite = Sprite.new(viewport)
      @sprite.z = 100001

      w = [Graphics.width - 40, 420].max
      h = 36
      @sprite.bitmap = Bitmap.new(w, h)
      @sprite.x = (Graphics.width - w) / 2

      is_gift = !item_id.nil?
      @icon_sprite = nil
      use_embedded_icon = (AnilLanRework.joiplay? rescue false)

      begin
        if is_gift
          # Degradê horizontal nas beiradas, meio escuro
          begin
            fade_w = (w * 0.25).to_i
            @sprite.bitmap.gradient_fill_rect(0, 0, fade_w, h, Color.new(0, 0, 0, 0), Color.new(0, 0, 0, 200), false)
            @sprite.bitmap.fill_rect(fade_w, 0, w - 2 * fade_w, h, Color.new(0, 0, 0, 200))
            @sprite.bitmap.gradient_fill_rect(w - fade_w, 0, fade_w, h, Color.new(0, 0, 0, 200), Color.new(0, 0, 0, 0), false)
          rescue
            @sprite.bitmap.fill_rect(0, 0, w, h, Color.new(0, 0, 0, 180)) rescue nil
          end
        else
          # Fundo preto translúcido padrão
          @sprite.bitmap.fill_rect(0, 0, w, h, Color.new(0, 0, 0, 180))
        end
      rescue
      end

      begin
        @sprite.bitmap.font.size = 18
        @sprite.bitmap.font.bold = true
      rescue
      end

      if is_gift
        # Carrega o ícone do presente/item
        icon_bmp = nil
        begin
          fallback_color = Color.new(200, 200, 200)
          if defined?(GiftBoxSystem)
            icon_bmp = GiftBoxSystem.load_item_icon(item_id, fallback_color) rescue nil
          else
            filename = GameData::Item.icon_filename(item_id) rescue nil
            icon_bmp = filename ? Bitmap.new(filename) : nil rescue nil
          end
        rescue
        end

        if icon_bmp && icon_bmp.width > icon_bmp.height
          cropped = Bitmap.new(icon_bmp.height, icon_bmp.height)
          cropped.blt(0, 0, icon_bmp, Rect.new(0, 0, icon_bmp.height, icon_bmp.height))
          icon_bmp.dispose rescue nil
          icon_bmp = cropped
        end

        icon_w = 28
        icon_h = 28
        spacing = 8

        # Calcula o tamanho do texto para centralizar o bloco (texto + espaçamento + ícone).
        # Adicionamos uma margem de +12 pixels para compensar a subestimação de largura do bold no RGSS.
        text_w = w - 40
        begin
          text_w = @sprite.bitmap.text_size(text).width + 12
        rescue
        end

        total_w = text_w
        total_w += spacing + icon_w if icon_bmp

        start_x = (w - total_w) / 2

        if use_embedded_icon
          begin
            @sprite.bitmap.font.color = Color.new(0, 0, 0, 200)
            @sprite.bitmap.draw_text(start_x + 1, 5, text_w, h - 4, text, 0)
          rescue
          end

          begin
            @sprite.bitmap.font.color = Color.new(255, 220, 50)
            @sprite.bitmap.draw_text(start_x, 4, text_w, h - 4, text, 0)
          rescue
          end

          if icon_bmp
            begin
              dest_rect = Rect.new(start_x + text_w + spacing, (h - icon_h) / 2, icon_w, icon_h)
              src_rect = Rect.new(0, 0, icon_bmp.width, icon_bmp.height)
              @sprite.bitmap.stretch_blt(dest_rect, icon_bmp, src_rect)
            rescue
            ensure
              icon_bmp.dispose rescue nil
            end
          end
        else
          # Sombra do texto (perfeitamente centrada verticalmente usando o mesmo 'h' do bitmap)
          begin
            @sprite.bitmap.font.color = Color.new(0, 0, 0, 200)
            @sprite.bitmap.draw_text(start_x + 1, 8, text_w, h - 10, text, 0)
          rescue
          end

          # Texto amarelo principal
          begin
            @sprite.bitmap.font.color = Color.new(255, 220, 50)
            @sprite.bitmap.draw_text(start_x, 7, text_w, h - 10, text, 0)
          rescue
          end

          # Fora do JoiPlay, mantemos o icone em sprite separado para animacao.
          if icon_bmp
            begin
              @icon_sprite = Sprite.new(viewport)
              @icon_sprite.bitmap = icon_bmp
              @icon_sprite.z = @sprite.z + 1
              @icon_sprite.ox = icon_bmp.width / 2 rescue 14
              @icon_sprite.oy = icon_bmp.height / 2 rescue 14
              @icon_base_x = start_x + text_w + spacing + (icon_w / 2)
              @icon_base_y = h / 2
              @icon_sprite.x = @sprite.x + @icon_base_x
            rescue => e
              AnilLanRework.log("Error creating icon sprite: #{e.message}")
              icon_bmp.dispose rescue nil
            end
          end
        end
      else
        # Sombra do texto centralizado
        begin
          @sprite.bitmap.font.color = Color.new(0, 0, 0, 200)
          @sprite.bitmap.draw_text(1, 8, w, h - 10, text, 1)
        rescue
        end

        # Texto amarelo centralizado
        begin
          @sprite.bitmap.font.color = Color.new(255, 220, 50)
          @sprite.bitmap.draw_text(0, 7, w, h - 10, text, 1)
        rescue
        end
      end

      reposition(index)
      @timer = (Graphics.frame_count rescue 0) + ((Graphics.frame_rate rescue 40) * duration).to_i
      @disposed = false
    end

    def reposition(index)
      return if @disposed
      @sprite.y = 13 + (index * 40)
      if @icon_sprite && !@icon_sprite.disposed?
        @icon_sprite.y = @sprite.y + @icon_base_y
      end
    end

    def update
      return if @disposed
      if (Graphics.frame_count rescue 0) > @timer
        dispose
        return
      end
      
      # Leve giro (balanço lateral) e pulso suave no ícone de presente
      if @icon_sprite && !@icon_sprite.disposed?
        time = (System.uptime rescue Time.now.to_f).to_f
        # Escala oscila suavemente entre 0.95 e 1.15
        scale = 1.05 + 0.10 * Math.sin(time * 5.0)
        @icon_sprite.zoom_x = scale rescue 1.0
        @icon_sprite.zoom_y = scale rescue 1.0
        # Ângulo gira levemente de um lado para o outro (balanço de -8 a 8 graus)
        @icon_sprite.angle = 8.0 * Math.sin(time * 3.5) rescue 0.0
      end
    end

    def dispose
      return if @disposed
      @sprite.bitmap&.dispose rescue nil
      @sprite.dispose rescue nil
      if @icon_sprite
        @icon_sprite.bitmap&.dispose rescue nil
        @icon_sprite.dispose rescue nil
      end
      @disposed = true
    end

    def disposed?
      @disposed
    end
  end

  class CornerPopupManager
    def initialize(viewport)
      @viewport = viewport
      @popups = []
    end

    def add(text, duration = 4.0)
      # Limite de segurança: no máximo 6 popups ativos ao mesmo tempo
      while @popups.size >= 6
        oldest = @popups.shift
        oldest.dispose rescue nil
      end
      
      @popups << CornerPopup.new(@viewport, text, duration)
      
      # Re-posiciona todos para garantir que a ordem e as posições batam
      reposition_all
    end

    def reposition_all
      size = @popups.size
      @popups.each_with_index do |p, i|
        # O mais recente (último elemento) fica no index_posicao 0 (mais embaixo)
        pos_idx = size - 1 - i
        p.reposition(pos_idx)
      end
    end

    def update
      @popups.each(&:update)
      if @popups.any?(&:disposed?)
        @popups.delete_if(&:disposed?)
        reposition_all
      end
    end

    def dispose
      @popups.each(&:dispose)
      @popups.clear
    end
  end

  class CornerPopup
    attr_reader :disposed

    def initialize(viewport, text, duration = 4.0)
      @sprite = Sprite.new(viewport)
      @sprite.z = 100001

      # Fonte 13 numa caixa de 20px era pequena demais para ser lida: o resto do
      # jogo usa MessageConfig::FONT_SIZE = 22. Subiu para 18, e a caixa cresceu
      # junto (a altura tem de acompanhar, senao o texto fica cortado no
      # draw_text, que centraliza dentro do retangulo).
      w = 230
      h = 26
      @sprite.bitmap = Bitmap.new(w, h)
      @sprite.x = 10

      # Cor baseada no tipo de mensagem
      text_color = Color.new(255, 255, 255)
      if text.include?(" entrou")
        text_color = Color.new(120, 255, 120) # Verde suave
      elsif text.include?(" saiu")
        text_color = Color.new(255, 120, 120) # Vermelho suave
      end

      # Fundo preto semi-transparente
      begin
        @sprite.bitmap.fill_rect(0, 0, w, h, Color.new(0, 0, 0, 150))
      rescue
      end
      
      # Borda fina do lado esquerdo para estilo
      begin
        left_border_color = if text.include?(" entrou")
                              Color.new(46, 204, 113) # Verde
                            elsif text.include?(" saiu")
                              Color.new(231, 76, 60) # Vermelho
                            else
                              Color.new(52, 152, 219) # Azul
                            end
        @sprite.bitmap.fill_rect(0, 0, 3, h, left_border_color)
      rescue
      end

      begin
        @sprite.bitmap.font.size = 18
        @sprite.bitmap.font.bold = true
        @sprite.bitmap.font.name = MessageConfig::FONT_NAME rescue (Font.default_name rescue "Arial")
      rescue
      end

      # Sombra do texto
      begin
        @sprite.bitmap.font.color = Color.new(0, 0, 0, 220)
        @sprite.bitmap.draw_text(9, 1, w - 12, h, text, 0)
      rescue
      end

      # Texto
      begin
        @sprite.bitmap.font.color = text_color
        @sprite.bitmap.draw_text(8, 0, w - 12, h, text, 0)
      rescue
      end

      @timer = (Graphics.frame_count rescue 0) + ((Graphics.frame_rate rescue 40) * duration).to_i
      @disposed = false
    end

    def reposition(pos_index)
      return if @disposed
      # 0 é o mais alto (y mínimo) no canto superior esquerdo
      @pos_idx = pos_index
      @sprite.y = (AnilLanRework.topo_livre_y rescue 10) + (pos_index * 24)
    end

    def update
      return if @disposed
      # ⚠️ Recalcula-se todos os frames de proposito. O HUD de grupo aparece e
      # desaparece sozinho (entra em batalha, abre um menu); se a posicao so
      # fosse decidida na criacao, um aviso ficava por cima dele a meio da vida.
      reposition(@pos_idx || 0)
      if (Graphics.frame_count rescue 0) > @timer
        dispose
      end
    end

    def dispose
      return if @disposed
      @sprite.bitmap&.dispose
      @sprite.dispose
      @disposed = true
    end

    def disposed?
      @disposed
    end
  end

  class ChatPopupManager
    def initialize(viewport)
      @viewport = viewport
      @popups = []
    end

    def add(text, duration = 10.0)
      while @popups.size >= 6
        oldest = @popups.shift
        oldest.dispose rescue nil
      end
      
      @popups << ChatPopup.new(@viewport, text, duration)
      reposition_all
    end

    def reposition_all
      base = (Graphics.height rescue 384) - 10
      @popups.reverse_each do |p|
        alt = (p.altura rescue 30)
        base -= alt
        p.posicionar_em(base) rescue nil
        base -= 2
      end
    end

    def update
      @popups.each(&:update)
      if @popups.any?(&:disposed?)
        @popups.delete_if(&:disposed?)
        reposition_all
      end
    end

    def dispose
      @popups.each(&:dispose)
      @popups.clear
    end
  end

  class ChatPopup
    LINHA_H    = 21
    MARGEM_V   = 5
    MAX_LINHAS = 3

    attr_reader :disposed
    attr_reader :altura

    def initialize(viewport, text, duration = 10.0)
      @sprite = Sprite.new(viewport)
      @sprite.z = 100001

      w = 430
      fonte = (MessageConfig::FONT_NAME rescue (Font.default_name rescue "Arial"))

      # Mede-se num bitmap a parte, com a MESMA fonte com que se vai desenhar.
      medidor = Bitmap.new(8, 8)
      begin
        medidor.font.size = 19
        medidor.font.bold = true
        medidor.font.name = fonte
      rescue
      end
      linhas = AnilLanRework.quebrar_texto(text, medidor, w - 16, MAX_LINHAS)
      medidor.dispose rescue nil

      h = (MARGEM_V * 2) + (linhas.length * LINHA_H)
      @altura = h

      @sprite.bitmap = Bitmap.new(w, h)
      @sprite.x = 10

      begin
        @sprite.bitmap.fill_rect(0, 0, w, h, Color.new(0, 0, 0, 150))
      rescue
      end

      begin
        @sprite.bitmap.fill_rect(0, 0, 3, h, Color.new(52, 152, 219))
      rescue
      end

      begin
        @sprite.bitmap.font.size = 19
        @sprite.bitmap.font.bold = true
        @sprite.bitmap.font.name = fonte
      rescue
      end

      linhas.each_with_index do |linha, i|
        y = MARGEM_V + (i * LINHA_H)
        begin
          @sprite.bitmap.font.color = Color.new(0, 0, 0, 220)
          @sprite.bitmap.draw_text(9, y + 1, w - 12, LINHA_H, linha, 0)
        rescue
        end
        begin
          @sprite.bitmap.font.color = Color.new(255, 255, 255)
          @sprite.bitmap.draw_text(8, y, w - 12, LINHA_H, linha, 0)
        rescue
        end
      end

      @timer = (Graphics.frame_count rescue 0) + ((Graphics.frame_rate rescue 40) * duration).to_i
      @disposed = false
    end

    # y = topo do popup, ja calculado pelo gestor a partir das alturas.
    def posicionar_em(y)
      return if @disposed
      @sprite.y = y
    end

    # Compatibilidade: alguem que ainda chame pelo indice antigo.
    def reposition(pos_index)
      return if @disposed
      posicionar_em(((Graphics.height rescue 384) - 10) - ((pos_index + 1) * (@altura || 30)))
    end

    def update
      return if @disposed
      dispose if (Graphics.frame_count rescue 0) > @timer
    end

    def dispose
      return if @disposed
      @sprite.bitmap&.dispose rescue nil
      @sprite.dispose rescue nil
      @disposed = true
    end

    def disposed?
      @disposed
    end
  end

end

module AnilLanRework
  class Overlay
    def initialize(viewport)
      @viewport = viewport
      @sprite = Sprite.new(@viewport)
      @sprite.z = 100000
      @sprite.bitmap = Bitmap.new(Graphics.width, 160)
      @sprite.x = 10
      @sprite.y = 10
      @last_update_frame = -1
      @last_players_count = -1
      @last_ip = nil
      @visible = false
      update
    end

    def dispose
      @sprite.bitmap&.dispose
      @sprite.dispose
    end

    def update
      if !AnilLanRework.enabled? || !AnilLanRework.connected?
        @sprite.visible = false if @sprite.visible
        return
      end

      current_frame = Graphics.frame_count rescue 0
      players_count = AnilLanRework.players.size
      current_ip = AnilLanRework.connection&.ip

      if current_frame > @last_update_frame + 40 || players_count != @last_players_count || current_ip != @last_ip
        refresh
        @last_update_frame = current_frame
        @last_players_count = players_count
        @last_ip = current_ip
      end
      @sprite.visible = true unless @sprite.visible
    end

    def refresh
      bitmap = @sprite.bitmap
      bitmap.clear

      ip = AnilLanRework.connection&.ip.to_s
      return if ip.empty?

      net_type = AnilLanRework.detect_network_type(ip)
      # Nunca exibir o IP real neste HUD (seguranca)
      header = (net_type == "Servidor Pokemon Azul") ? "Servidor Pokémon Azul" : "Conectado [#{net_type}]"

      # Fonte base
      bitmap.font.size = 15
      bitmap.font.bold = true

      # Sombra do Header
      bitmap.font.color = Color.new(0, 0, 0, 180)
      bitmap.draw_text(1, 1, Graphics.width, 24, header)
      # Texto Principal do Header
      bitmap.font.color = Color.new(255, 220, 50) # Amarelo ouro
      bitmap.draw_text(0, 0, Graphics.width, 24, header)

      # Lista de jogadores
      bitmap.font.size = 13
      bitmap.font.bold = false
      y = 26

      # Jogador Local
      self_name = AnilLanRework.self_name.to_s
      self_text = "• #{self_name} (Você)"
      bitmap.font.color = Color.new(0, 0, 0, 180)
      bitmap.draw_text(1, y + 1, Graphics.width, 20, self_text)
      bitmap.font.color = Color.new(100, 255, 100) # Verde
      bitmap.draw_text(0, y, Graphics.width, 20, self_text)
      y += 20

      # Outros Jogadores
      AnilLanRework.players.each_value do |peer|
        next if peer.name.to_s == self_name
        peer_text = "• #{peer.name}"
        bitmap.font.color = Color.new(0, 0, 0, 180)
        bitmap.draw_text(1, y + 1, Graphics.width, 20, peer_text)
        bitmap.font.color = Color.new(255, 255, 255)
        bitmap.draw_text(0, y, Graphics.width, 20, peer_text)
        y += 20
        break if y > 140
      end
    end
  end
end

#===============================================================================
# SISTEMA DE RECARREGAMENTO DINÂMICO DE SCRIPTS (F5)
#===============================================================================
# --- [REMOVIDO] Bloco de codigo (linhas 14574 a 14651) movido para 000d_Multiplayer_Battle_Trade_RNG_Sync.rb ---

# --- [REMOVIDO] Bloco de codigo (linhas 14653 a 14668) movido para 000d_Multiplayer_Battle_Trade_RNG_Sync.rb ---

module AnilLanRework
  module GlobalNotification
    @sprite = nil
    @timer = 0
    @duration = 10.0
    @pulse_frame = 0

    def self.show(text)
      if defined?(AnilLanRework) && AnilLanRework.respond_to?(:add_popup)
        AnilLanRework.add_popup(text, 6.0)
      end
    end

    def self.update
      # No-op
    end

    def self.dispose
      # No-op
    end
  end

  def self.update_connection_watchdog(scene)
    return unless @multiplayer_mode
    return unless enabled?
    return if @intentional_disconnect

    unless online_session?
      if !connected?
        log("[LAN] Conexão com o host ou cliente perdida no watchdog.")
        disconnect
        request_map_graphics_refresh!("lan_disconnect_watchdog", 1) rescue nil
        pbMessage(_INTL("A conexão LAN com o host foi perdida.")) rescue nil
      end
      return
    end

    now_real = Time.now.to_f
    resume_grace = @resume_grace_until rescue nil
    return if resume_grace && now_real < resume_grace.to_f

    if !@reconnecting
      if !connected?
        start_reconnection(scene)
      end
    else
      update_reconnection(scene)
    end
  end

  # Quanto tempo se insiste antes de mandar o jogador para o titulo.
  # Reiniciar o servidor demora bem menos que isto, portanto uma manutencao
  # normal passa a ser invisivel: a faixa fica, e o jogo continua.
  TEMPO_LIMITE_RECONEXAO = 240.0 unless const_defined?(:TEMPO_LIMITE_RECONEXAO)

  def self.start_reconnection(scene, reason = nil)
    @reconnecting = true
    @reconnect_start_time = Time.now.to_f
    @last_reconnect_fail_time = 0.0
    # ⚠️ Mesmo buraco do outro sitio: um `= nil` por cima de uma thread viva
    # perde-a de vista com o socket dela dentro. Uma reconexao pode comecar
    # sobre outra que ainda nao acabou (queda seguida de queda).
    abandonar_tentativa!("nova reconexao")
    
    @connection.disconnect rescue nil if @connection
    @connection = nil
    
    # Mostra a barra de reconexão no topo da tela
    create_reconnect_banner
    
    log("[RECONNECT] Conexão perdida. Iniciando tentativa de reconexão em segundo plano (motivo: #{reason || 'desconexão inesperada'}).")
    
    launch_reconnect_thread
  end

  def self.update_reconnection(scene)
    # Check if thread finished
    if @reconnect_thread && !@reconnect_thread.alive?
      ok = @reconnect_thread[:ok]
      conn = @reconnect_thread[:conn]
      err = @reconnect_thread[:error]
      @reconnect_thread = nil
      
      if ok && conn && conn.connected?
        log("[RECONNECT] Reconectado com sucesso em segundo plano!")
        @connection.disconnect rescue nil if @connection
        @connection = conn
        
        AnilLanRework.multiplayer_mode = true rescue nil
        if defined?(AnilLanRework::WorldSync)
          AnilLanRework::WorldSync.send_player_state rescue nil
          @connection.flush_batch rescue nil
        end
        if defined?(AnilLanRework::TradeSync)
          AnilLanRework::TradeSync.send_party_sync rescue nil
        end
        # Tenta re-atar à batalha coop/pvp ativa se ainda existir
        begin
          ctx = AnilLanRework::BattleSync.active_context rescue nil
          if ctx && ctx.battle_id && [:coop, :pvp].include?(ctx.mode)
            log("[RECONNECT] Tentando battle_rejoin para battle_id=#{ctx.battle_id} mode=#{ctx.mode}")
            @connection.send_packet("battle_rejoin",
              "battle_id"  => ctx.battle_id,
              "partner_id" => ctx.partner_id.to_s,
              "mode"       => ctx.mode.to_s
            )
            @connection.flush_batch rescue nil
          end
        rescue => e
          log("[RECONNECT] Erro no battle_rejoin: #{e.class}: #{e.message}")
        end
        AnilLanRework.schedule_delayed_map_refresh!("join_settle", 1.5, 1) rescue nil
        
        @reconnecting = false
        dispose_reconnect_banner
        arrumar_zumbis!
        
        AnilLanRework.add_popup("Reconectado com sucesso!", 3.0) rescue nil
      else
        log("[RECONNECT] Tentativa de reconexão falhou. Erro: #{err ? AnilLanRework.safe_ui_text(err.message) : 'desconhecido'}")
        if conn && conn.respond_to?(:last_error) && conn.last_error.to_s.start_with?("BANNED:")
          reason = conn.last_error.sub("BANNED:", "").strip
          conn.disconnect rescue nil if conn
          @reconnecting = false
          dispose_reconnect_banner rescue nil
          AnilLanRework.intentional_disconnect = true rescue nil
          AnilLanRework.disconnect(false) rescue nil
          active_ctx = AnilLanRework::BattleSync.active_context rescue nil
          if active_ctx && active_ctx.battle
            active_ctx.battle.decision = 5 rescue nil
          end
          AnilLanRework.force_main_title!("aviso_banido.png", _INTL("\\r[Você foi BANIDO / EXPULSO do servidor!]\n\n{1}", reason))
          return
        end
        conn.disconnect rescue nil if conn
        
        @last_reconnect_fail_time = Time.now.to_f
      end
    elsif !@reconnect_thread
      if Time.now.to_f - @last_reconnect_fail_time >= 3.0
        launch_reconnect_thread
      end
    else
      # Thread still running
      if Time.now.to_f - (@last_reconnect_fail_time > 0 ? @last_reconnect_fail_time : @reconnect_start_time) >= 15.0
        log("[RECONNECT] Tentativa de reconexão travada. Forçando reinício do thread.")
        abandonar_tentativa!("travada")
        @last_reconnect_fail_time = Time.now.to_f
      end
    end
  end

  # [REMOVIDO] trigger_strict_disconnect — nunca foi chamado por ninguem.
  # Prometia desistir da reconexao e voltar ao titulo ("A conexao com o servidor
  # foi perdida"), mas o update_reconnection tenta reconectar indefinidamente
  # (nova tentativa a cada 3s, tentativa travada morta aos 15s). O comportamento
  # real e reconectar para sempre; a funcao so enganava quem lia o codigo.

  def self.create_reconnect_banner
    dispose_reconnect_banner
    
    @reconnect_viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @reconnect_viewport.z = 999999
    
    text = "Conexão perdida. Tentando reconectar..."
    
    w = 420
    h = 32
    x = (Graphics.width - w) / 2
    y = 10
    
    @reconnect_sprite = Sprite.new(@reconnect_viewport)
    @reconnect_sprite.z = 100001
    @reconnect_sprite.bitmap = Bitmap.new(w, h)
    @reconnect_sprite.x = x
    @reconnect_sprite.y = y
    
    # Smooth background (dark semi-transparent)
    @reconnect_sprite.bitmap.fill_rect(0, 0, w, h, Color.new(0, 0, 0, 150))
    
    @reconnect_sprite.bitmap.font.size = 15
    @reconnect_sprite.bitmap.font.bold = true
    
    # Text Shadow
    @reconnect_sprite.bitmap.font.color = Color.new(0, 0, 0, 200)
    @reconnect_sprite.bitmap.draw_text(1, 3, w, 28, text, 1)
    
    # Text Front
    @reconnect_sprite.bitmap.font.color = Color.new(255, 255, 255)
    @reconnect_sprite.bitmap.draw_text(0, 2, w, 28, text, 1)
  end

  def self.dispose_reconnect_banner
    @reconnect_sprite.bitmap.dispose rescue nil if @reconnect_sprite && @reconnect_sprite.bitmap
    @reconnect_sprite.dispose rescue nil if @reconnect_sprite
    @reconnect_sprite = nil
    @reconnect_viewport.dispose rescue nil if @reconnect_viewport
    @reconnect_viewport = nil
  end

  #-----------------------------------------------------------------------------
  # ABANDONAR UMA TENTATIVA DE RECONEXAO SEM DEIXAR LIXO
  #
  # ⚠️ ISTO E O "FECHA SEM AVISO" DEPOIS DE VOLTAR DE OUTRA APLICACAO.
  #
  # O que estava aqui era:
  #
  #     @reconnect_thread.kill
  #     conn = @reconnect_thread[:conn]     # <- quase sempre nil
  #     conn.disconnect if conn
  #     @reconnect_thread = nil
  #
  # E o `[:conn]` so e escrito DEPOIS de `conn.connect(...)` voltar. Uma
  # tentativa "travada" e, por definicao, uma que ainda nao voltou — portanto o
  # `[:conn]` esta vazio, o `disconnect` nunca corria, e a referencia era
  # deitada fora com o `= nil`.
  #
  # O que se perdia de cada vez NAO era so um socket. O `Connection#connect`
  # chama `start_recv_thread` la dentro: fica um socket aberto E uma segunda
  # thread a ler dele, para sempre, sem ninguem que lhes chegue.
  #
  # Isto repete-se de 15 em 15 segundos enquanto nao houver rede. Quem deixa o
  # jogo em segundo plano para responder a uma mensagem volta minutos depois com
  # dezenas de sockets e dezenas de threads acumulados. O processo morre por
  # falta de descritores ou de memoria — e uma morte NATIVA, nao uma excepcao de
  # Ruby: por isso nao aparece a caixa de erro do JoiPlay, simplesmente fecha.
  #
  # Duas correccoes, e a ordem importa:
  #
  #   1. O `conn` passa a ser publicado ANTES de se ligar, para que haja sempre
  #      alguem por quem pegar.
  #   2. Fecha-se o socket PRIMEIRO e mata-se a thread a seguir. Fechar o
  #      descritor e o que desprende uma thread encravada numa leitura; matar
  #      primeiro e fechar depois deixa-a a ler um socket que ja nao existe.
  #-----------------------------------------------------------------------------
  ZUMBIS_MAX = 3   # tentativas abandonadas ainda vivas antes de parar de lancar

  def self.abandonar_tentativa!(motivo)
    th = @reconnect_thread
    @reconnect_thread = nil
    return unless th
    cn = (th[:conn] rescue nil)
    (cn.disconnect rescue nil) if cn
    (th.kill rescue nil)
    @reconnect_zumbis ||= []
    @reconnect_zumbis << th
    log("[RECONNECT] Tentativa abandonada (#{motivo}); zumbis=#{@reconnect_zumbis.size}") rescue nil
  rescue
    nil
  end

  # ⚠️ `Thread#kill` nao garante morte imediata: uma thread parada dentro de uma
  # chamada de sistema so morre quando essa chamada volta. Por isso nao se
  # assume nada — guarda-se e confirma-se depois. E enquanto houver zumbis a
  # mais, nao se lancam mais tentativas, que era exactamente o que alimentava a
  # pilha.
  def self.arrumar_zumbis!
    return 0 if @reconnect_zumbis.nil? || @reconnect_zumbis.empty?
    @reconnect_zumbis.reject! do |th|
      morta = (!th.alive? rescue true)
      if !morta
        # Continua viva: fecha-se-lhe o socket outra vez, se entretanto o abriu.
        cn = (th[:conn] rescue nil)
        (cn.disconnect rescue nil) if cn
      end
      morta
    end
    @reconnect_zumbis.size
  rescue
    0
  end

  def self.launch_reconnect_thread
    # ⚠️ Nunca duas tentativas ao mesmo tempo. O caminho antigo punha
    # `@reconnect_thread = nil` e lancava outra por cima da que ainda corria.
    return if @reconnect_thread && (@reconnect_thread.alive? rescue false)
    vivos = arrumar_zumbis!
    if vivos >= ZUMBIS_MAX
      log("[RECONNECT] #{vivos} tentativas antigas ainda presas; espera-se em vez de abrir mais.") rescue nil
      @last_reconnect_fail_time = Time.now.to_f
      return
    end
    @reconnect_thread = Thread.new do
      begin
        ip = @last_connect_ip || "127.0.0.1"
        player_id = @last_connect_player_id
        if player_id.to_s.empty?
          player_id = AnilLanRework.read_cfg("multiplayer_player.txt", "id", "")
        end
        if player_id.to_s.empty?
          player_id = "jogador#{rand(9000) + 1000}"
        end
        player_name = @last_connect_player_name || ($player.name.to_s rescue "Treinador")
        char_name = @last_connect_char_name || ($game_player.character_name.to_s rescue "trainer_m")
        is_host = @last_connect_is_host || false
        
        display_id = player_id.to_s
        internal_id = resolve_internal_id(player_id)
        
        conn = AnilLanRework::Connection.new
        # Publicado ANTES da ligacao: se esta tentativa for abandonada a meio,
        # quem a abandona tem por onde lhe fechar o socket.
        Thread.current[:conn] = conn
        ok = conn.connect(ip,
          internal_id: internal_id,
          display_id: display_id,
          player_name: player_name,
          char_name: char_name,
          is_host: is_host,
          startup: false
        )
        
        Thread.current[:ok] = ok
        Thread.current[:conn] = conn
      rescue => e
        Thread.current[:ok] = false
        Thread.current[:error] = e
      end
    end
  end
end

# [REMOVIDO] Game.load override para Joiplay (causava tela preta)
# O request_same_map_transfer! era chamado antes da Scene_Map#main inicializar,
# fazendo pbFadeOutIn num Graphics já congelado, resultando em tela preta permanente.

#===============================================================================
# * Hook para desconectar ao sair do jogo (Menu Pause)
#===============================================================================
if defined?(MenuHandlers)
  quit_handler = MenuHandlers.get(:pause_menu, :quit_game) rescue nil
  if quit_handler
    orig_effect = quit_handler["effect"]
    quit_handler["effect"] = proc { |menu|
      if orig_effect
        res = orig_effect.call(menu)
        if res # Se retornou true, o jogador confirmou a saída do jogo
          if defined?(AnilLanRework) && AnilLanRework.respond_to?(:disconnect)
            AnilLanRework.log("[QuitHook] Jogador saindo pelo menu. Desconectando...") rescue nil
            AnilLanRework.disconnect(true) rescue nil
          end
        end
        res
      end
    }
  end
end


#===============================================================================
# * Sistema de Animação de Captura de Pokémon Overworld
#===============================================================================
module AnilLanRework
  @active_overworld_animations = []

  class << self
    attr_accessor :active_overworld_animations

    def add_overworld_animation(anim)
      @active_overworld_animations ||= []
      @active_overworld_animations << anim
    end

    def update_overworld_animations
      return if @active_overworld_animations.nil?
      @active_overworld_animations.delete_if { |a| a.disposed? rescue true }
      @active_overworld_animations.each { |a| a.update rescue nil }
      @active_overworld_animations.delete_if { |a| a.disposed? rescue true }
      refresh_main_popup_animation_positions
      refresh_corner_popup_animation_positions
      refresh_chat_popup_animation_positions
      refresh_gift_popup_animation_positions
    end

    def dispose_overworld_animations
      return if @active_overworld_animations.nil?
      @active_overworld_animations.each { |a| a.dispose rescue nil }
      @active_overworld_animations.clear
    end

    def show_capture_balloon_for_peer(packet)
      return unless REMOTE_CATCH_BALLOON_ENABLED
      sender_id = packet["sender_id"].to_s
      return if sender_id.empty?
      return if sender_id == AnilLanRework.self_internal_id

      peer = AnilLanRework.players[sender_id]
      if !peer
        base_sender = sender_id.split("-").first.to_s.downcase
        unless base_sender.empty?
          peer = AnilLanRework.players.values.find do |p|
            p.internal_id.to_s.split("-").first.to_s.downcase == base_sender
          end
        end
      end
      return unless peer
      return unless $game_map && peer.map_id == $game_map.map_id

      spriteset = nil
      if $scene.is_a?(Scene_Map)
        if $scene.respond_to?(:spriteset) && $scene.spriteset
          spriteset = $scene.spriteset
        elsif $scene.instance_variable_get(:@spritesets) && $game_map
          spriteset = $scene.instance_variable_get(:@spritesets)[$game_map.map_id] rescue nil
        end
      end
      
      if spriteset
        actual_id = peer.internal_id.to_s
        spriteset.trigger_capture_balloon_state(actual_id, peer) rescue nil
        AnilLanRework.log("Triggered capture balloon state transition for peer #{actual_id}")
      end
    end
  end
end

class Game_Map
  alias anil_rework_game_map_update update unless method_defined?(:anil_rework_game_map_update)

  def update
    if defined?(AnilLanRework) && AnilLanRework.enabled? && AnilLanRework.connected? && $game_temp && $game_temp.in_menu
      old_in_menu = $game_temp.in_menu
      $game_temp.in_menu = false
      begin
        anil_rework_game_map_update
      ensure
        $game_temp.in_menu = old_in_menu
      end
    else
      anil_rework_game_map_update
    end
  end
end

class Game_FollowerFactory
  alias anil_rework_follower_update_menu_bypass update unless method_defined?(:anil_rework_follower_update_menu_bypass)

  def update
    if defined?(AnilLanRework) && AnilLanRework.enabled? && AnilLanRework.connected?
      followers = $PokemonGlobal.followers
      return if followers.length == 0
      leader = $game_player
      player_moving = $game_player.moving? || $game_player.jumping?
      followers.each_with_index do |follower, i|
        event = @events[i]
        next if !event
        if follower.invisible_after_transfer && player_moving
          follower.invisible_after_transfer = false
          event.turn_towards_leader($game_player)
        end
        event.move_speed  = leader.move_speed
        event.transparent = !follower.visible?
        if $PokemonGlobal.ice_sliding
          event.straighten
          event.walk_anime = false
        else
          event.walk_anime = true
        end
        if event.jumping? || event.moving? || !player_moving
          event.update
        elsif !event.starting
          event.set_starting
          event.update
          event.clear_starting
        end
        follower.direction = event.direction
        leader = event
      end
      
      # Check event triggers (only when NOT in menu)
      if Input.trigger?(Input::USE) && !$game_temp.in_menu && !$game_temp.in_battle &&
         !$game_player.move_route_forcing && !$game_temp.message_window_showing &&
         !pbMapInterpreterRunning? &&
         !(defined?(AnilLanRework::ChatInputHUD) && AnilLanRework::ChatInputHUD.respond_to?(:input_blocked?) && AnilLanRework::ChatInputHUD.input_blocked?)
        facing_tile = $map_factory.getFacingTile
        each_follower do |event, follower|
          next if !facing_tile || event.map.map_id != facing_tile[0] ||
                  !event.at_coordinate?(facing_tile[1], facing_tile[2])
          next if event.jumping?
          follower.interact(event)
        end
      end
    else
      anil_rework_follower_update_menu_bypass
    end
  end
end


#===============================================================================
# REGISTRO E CONTROLE DINÂMICO DE MENUS E SUBMENUS PARA O BALÃO DE OCUPADO
#===============================================================================
$anil_current_menu_state = nil

# Hooking submenus of the game dynamically
[
  [:PokemonBag_Scene, :bag],
  [:PokemonParty_Scene, :menu],
  [:PokemonPokedex_Scene, :menu],
  [:PokemonPokedexInfo_Scene, :menu],
  [:PokemonTrainerCard_Scene, :menu],
  [:PokemonSummary_Scene, :menu],
  [:PokemonSave_Scene, :menu],
  [:PokemonOption_Scene, :menu]
].each do |klass_sym, state_sym|
  next unless Object.const_defined?(klass_sym)
  klass = Object.const_get(klass_sym)
  
  if klass.method_defined?(:pbStartScene)
    start_alias = "anil_state_orig_pbStartScene_#{state_sym}"
    klass.class_eval do
      unless method_defined?(start_alias)
        alias_method start_alias, :pbStartScene
        define_method(:pbStartScene) do |*args|
          $anil_current_menu_state = state_sym
          send(start_alias, *args)
        end
      end
    end
  end

  if klass.method_defined?(:pbEndScene)
    end_alias = "anil_state_orig_pbEndScene_#{state_sym}"
    klass.class_eval do
      unless method_defined?(end_alias)
        alias_method end_alias, :pbEndScene
        define_method(:pbEndScene) do |*args|
          res = send(end_alias, *args)
          $anil_current_menu_state = nil if $anil_current_menu_state == state_sym
          res
        end
      end
    end
  end
end

# Hooking the Diamond/Pearl pause menu loop (DP_PauseMenu) to track its open/close state
if Object.const_defined?(:DP_PauseMenu)
  DP_PauseMenu.class_eval do
    alias_method :anil_menu_state_orig_update, :update unless method_defined?(:anil_menu_state_orig_update)
    def update(*args)
      $anil_current_menu_state = :menu
      anil_menu_state_orig_update(*args)
      if @done
        $anil_current_menu_state = nil if $anil_current_menu_state == :menu
      end
    end
  end
end

#===============================================================================
# Real-Time Inspection System Updates
#===============================================================================
module AnilLanRework
  def self.send_inspect_update
    return unless defined?(AnilLanRework) && AnilLanRework.respond_to?(:connected?) && AnilLanRework.connected?
    begin
      party_data = []
      if $player && $player.party
        $player.party.each do |pkmn|
          next unless pkmn
          moves_list = []
          pkmn.moves.each do |m|
            moves_list << m.name if m
          end
          
          iv_hash = {}
          if pkmn.respond_to?(:iv) && pkmn.iv
            pkmn.iv.each_key { |k| iv_hash[k.to_s] = pkmn.iv[k] }
          end

          ev_hash = {}
          if pkmn.respond_to?(:ev) && pkmn.ev
            pkmn.ev.each_key { |k| ev_hash[k.to_s] = pkmn.ev[k] }
          end

          party_data << {
            "species" => pkmn.species.to_s,
            "name" => pkmn.name,
            "level" => pkmn.level,
            "hp" => pkmn.hp,
            "max_hp" => pkmn.totalhp,
            "shiny" => pkmn.shiny?,
            "ability" => pkmn.ability.to_s,
            "nature" => pkmn.nature.to_s,
            "moves" => moves_list,
            "iv" => iv_hash,
            "ev" => ev_hash,
            "item" => pkmn.item ? pkmn.item.to_s : ""
          }
        end
      end

      bag_data = []
      if $bag
        $bag.pockets.each do |pocket|
          next unless pocket
          pocket.each do |item_slot|
            next unless item_slot
            item_id, qty = item_slot
            next if qty <= 0
            item_data = GameData::Item.try_get(item_id)
            name = item_data ? item_data.name : item_id.to_s
            bag_data << {
              "id" => item_id.to_s,
              "name" => name,
              "qty" => qty
            }
          end
        end
      end

      AnilLanRework.connection.send_packet("player_inspect_data", {
        "party" => party_data,
        "bag" => bag_data,
        "money" => $player ? $player.money : 0
      })
    rescue => e
      AnilLanRework.log("send_inspect_update error: #{e.message}")
    end
  end
end

class PokemonBag
  alias anil_inspect_add add unless method_defined?(:anil_inspect_add)
  def add(item, qty = 1)
    ret = anil_inspect_add(item, qty)
    if ret && defined?(AnilLanRework) && AnilLanRework.respond_to?(:send_inspect_update)
      AnilLanRework.send_inspect_update
    end
    return ret
  end

  alias anil_inspect_remove remove unless method_defined?(:anil_inspect_remove)
  def remove(item, qty = 1)
    ret = anil_inspect_remove(item, qty)
    if ret && defined?(AnilLanRework) && AnilLanRework.respond_to?(:send_inspect_update)
      AnilLanRework.send_inspect_update
    end
    return ret
  end

  alias anil_inspect_clear clear unless method_defined?(:anil_inspect_clear)
  def clear
    anil_inspect_clear
    if defined?(AnilLanRework) && AnilLanRework.respond_to?(:send_inspect_update)
      AnilLanRework.send_inspect_update
    end
  end
end

class Player
  alias anil_inspect_coins coins= unless method_defined?(:anil_inspect_coins)
  def coins=(value)
    old_val = @coins
    anil_inspect_coins(value)
    if @coins != old_val && defined?(AnilLanRework) && AnilLanRework.respond_to?(:send_inspect_update)
      AnilLanRework.send_inspect_update
    end
  end
end

class Trainer
  alias anil_inspect_heal_party heal_party unless method_defined?(:anil_inspect_heal_party)
  def heal_party
    anil_inspect_heal_party
    if defined?(AnilLanRework) && AnilLanRework.respond_to?(:send_inspect_update)
      AnilLanRework.send_inspect_update
    end
  end
end

# Hooking battle end and PC storage closure to send inspect updates
if defined?(EventHandlers) && EventHandlers.respond_to?(:add)
  EventHandlers.add(:on_end_battle, :inspect_end_battle, proc { |_outcome|
    if defined?(AnilLanRework) && AnilLanRework.respond_to?(:send_inspect_update)
      AnilLanRework.send_inspect_update
    end
  })
end

class PokemonStorageScreen
  alias anil_inspect_pbStartScreen pbStartScreen unless method_defined?(:anil_inspect_pbStartScreen)
  def pbStartScreen(*args)
    res = anil_inspect_pbStartScreen(*args)
    if defined?(AnilLanRework) && AnilLanRework.respond_to?(:send_inspect_update)
      AnilLanRework.send_inspect_update
    end
    return res
  end
end

class PokemonSystem
  attr_writer :multiplayer_channel

  def multiplayer_channel
    @multiplayer_channel ||= 1
    return @multiplayer_channel
  end
end

# ==============================================================================
# MULTIPLAYER ACTIVE CHANNEL HUD
# ==============================================================================
class AnilChannelHUD
  def initialize
    # 200 e nao 160: a segunda linha leva "Cadeia 22 Totodile" e o icone. A caixa
    # e alinhada a direita do ecra, portanto alargar so a estica para a esquerda
    # e a primeira linha continua no mesmo sitio.
    @width = 200
    # 36 da primeira linha + 30 da linha do bonus de shiny. A segunda linha fica
    # vazia quando nao ha nada a mostrar, entao a caixa nao muda de tamanho.
    @height = 66
    @x = Graphics.width - @width - 10 rescue 10
    @y = 10
    
    @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 999999
    
    @sprite = Sprite.new(@viewport)
    @sprite.bitmap = Bitmap.new(@width, @height)
    @sprite.x = @x
    @sprite.y = @y
    
    @font_name = MessageConfig::FONT_NAME rescue Font.default_name
    @last_channel = nil
    @last_connected = nil
    @last_map_id = nil
    @last_players_count = nil
    @last_shiny = nil
    
    update_hud(true)
  end

  def update_hud(force = false)
    return if @sprite.disposed?
    
    connected = (defined?(AnilLanRework) && AnilLanRework.connected?)
    channel = ($PokemonSystem ? $PokemonSystem.multiplayer_channel : 1)
    map_id = $game_map ? $game_map.map_id : 0
    is_mp_map = (defined?(AnilLanRework) && AnilLanRework.multiplayer_map?(map_id))
    f7_active = defined?(Scene_Map_MultiplayerMainMenu) && Scene_Map_MultiplayerMainMenu.respond_to?(:active?) && Scene_Map_MultiplayerMainMenu.active?
    
    # ⚠️ NA BATALHA DIRETA O ECRA E DO COMBATE.
    #
    # Estes HUDs foram feitos para quem esta a andar pelo mundo: o canal, o
    # grupo, o nome do mapa. Por cima de uma luta em tempo real eles tapam
    # exactamente o que precisa de ser lido — a vida e os golpes — e o jogador
    # nao pode fecha-los sem sair da luta. Somem enquanto ela durar e voltam
    # sozinhos no fim; nada e desligado, so escondido.
    should_be_visible = connected && is_mp_map && $scene.is_a?(Scene_Map) && f7_active &&
                        !$game_temp&.in_battle && !(AnilArena.activa? rescue false)
    
    if @sprite.visible != should_be_visible
      @sprite.visible = should_be_visible
    end
    
    return unless should_be_visible
    
    players_count = (defined?(AnilLanRework) && AnilLanRework.players) ? (AnilLanRework.players.size + 1) : 1
    
    # Estado do bonus de shiny: [tem_amuleto, cadeia]. So se redesenha quando
    # muda, como tudo o resto nesta HUD.
    shiny_estado = begin
      defined?(AnilCadeiaCoop) ? AnilCadeiaCoop.estado_hud : nil
    rescue
      nil
    end

    if force || channel != @last_channel || connected != @last_connected || map_id != @last_map_id || players_count != @last_players_count || shiny_estado != @last_shiny
      @last_shiny = shiny_estado
      @last_channel = channel
      @last_connected = connected
      @last_map_id = map_id
      @last_players_count = players_count
      
      bitmap = @sprite.bitmap
      bitmap.clear
      
      bitmap.font.name = @font_name
      bitmap.font.size = 20
      bitmap.font.bold = true
      
      text = _INTL("C{1} | {2} ON", channel, players_count)
      
      # Sombra do texto em preto
      bitmap.font.color = Color.new(0, 0, 0, 220)
      bitmap.draw_text(2, 2, bitmap.width, bitmap.height, text, 2)
      
      # Texto principal em ciano neon
      bitmap.font.color = Color.new(0, 230, 255)
      bitmap.draw_text(0, 0, bitmap.width, 36, text, 2)

      desenhar_bonus_shiny(bitmap, shiny_estado)
    end
  end

  # Segunda linha: icone do amuleto (se o tiver) e "Cadeia NN" (se houver
  # cadeia). Sem nenhum dos dois nao se desenha nada — a linha fica vazia.
  #
  # ⚠️ Isto vive na HUD e nao no cabecalho do menu de proposito. O cabecalho do
  # F7 e um pbMessage, e acrescentar-lhe linhas mexia no tamanho da janela de
  # escolha. Aqui e um bitmap proprio, ao lado do "C1 | N ON", que ja aparece
  # exactamente nas mesmas condicoes.
  def desenhar_bonus_shiny(bitmap, estado)
    return unless estado.is_a?(Array)
    amuleto, cadeia, nome = estado
    return if !amuleto && cadeia.to_i <= 0

    y = 34
    dir = bitmap.width

    if cadeia.to_i > 0
      texto = format("Cadeia %02d", cadeia.to_i)
      texto = "#{texto} #{nome}" if nome && !nome.to_s.empty?
      bitmap.font.size = 18
      # Nomes longos (Crabominable, Fletchinder) nao cabem a 18 com o icone ao
      # lado. Encolhe-se a fonte ate caber, em vez de cortar o nome a meio.
      espaco = dir - (amuleto ? 32 : 4)
      while bitmap.font.size > 12 && bitmap.text_size(texto).width > espaco
        bitmap.font.size -= 1
      end
      bitmap.font.color = Color.new(0, 0, 0, 220)
      bitmap.draw_text(2, y + 2, dir - 2, 28, texto, 2)
      bitmap.font.color = Color.new(110, 235, 130)   # o mesmo verde do CheckIcon
      bitmap.draw_text(0, y, dir, 28, texto, 2)
      largura = bitmap.text_size(texto).width
      dir -= (largura + 6)
    end

    if amuleto
      caminho = (GameData::Item.icon_filename(amuleto) rescue nil)
      if caminho
        icone = (AnimatedBitmap.new(caminho).deanimate rescue nil)
        if icone && !icone.disposed?
          lado = 26
          bitmap.stretch_blt(Rect.new(dir - lado, y + 1, lado, lado),
                             icone, Rect.new(0, 0, icone.width, icone.height))
          icone.dispose rescue nil
        end
      end
    end
  rescue
    nil
  end

  def update
    return if @sprite.disposed?
    update_hud
  end

  def dispose
    @sprite.bitmap.dispose if @sprite.bitmap && !@sprite.bitmap.disposed?
    @sprite.dispose if @sprite && !@sprite.disposed?
    @viewport.dispose if @viewport && !@viewport.disposed?
  end
end
# ==============================================================================
# GROUP PARTNER HUD (Superior Esquerdo) - Fase 1: mostra o parceiro de grupo atual
# ==============================================================================
class AnilPartnerHUD
  # Os avisos de "entrou"/"saiu" precisam de saber se este HUD esta la para se
  # desviarem dele. Ver AnilLanRework.topo_livre_y.
  def visivel?
    return false if @sprite.nil?
    return false if (@sprite.disposed? rescue true)
    @sprite.visible == true
  rescue
    false
  end

  def initialize
    @width = 260
    @height = 40
    @x = 10 rescue 10
    @y = 10 rescue 10

    @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 999999

    @sprite = Sprite.new(@viewport)
    @sprite.bitmap = Bitmap.new(@width, @height)
    @sprite.x = @x
    @sprite.y = @y

    @font_name = MessageConfig::FONT_NAME rescue Font.default_name
    @last_text_key = nil

    update_hud(true)
  end

  def update_hud(force = false)
    return if @sprite.disposed?

partner_id = (defined?(AnilLanRework) && AnilLanRework.respond_to?(:coop_party_partner_id)) ? AnilLanRework.coop_party_partner_id : nil
peer = (partner_id && defined?(AnilLanRework) && AnilLanRework.players) ? AnilLanRework.players[partner_id] : nil

in_menu = ($game_temp && $game_temp.respond_to?(:in_menu) && $game_temp.in_menu) ||
          ($game_temp && $game_temp.respond_to?(:message_window_showing) && $game_temp.message_window_showing) ||
          (defined?(Scene_Map_MultiplayerMainMenu) && Scene_Map_MultiplayerMainMenu.respond_to?(:active?) && Scene_Map_MultiplayerMainMenu.active?)

should_be_visible = !partner_id.nil? && !peer.nil? && $scene.is_a?(Scene_Map) && !$game_temp&.in_battle && !in_menu && !(AnilLanRework.top_broadcast_active? rescue false) && !(AnilArena.activa? rescue false)

    if @sprite.visible != should_be_visible
      @sprite.visible = should_be_visible
    end

    return unless should_be_visible

    status = if peer.respond_to?(:battle_busy) && peer.battle_busy
      _INTL("Em batalha")
    elsif peer.respond_to?(:menu_open) && peer.menu_open
      _INTL("No menu")
    else
      _INTL("Disponível")
    end

    # No mesmo mapa mostra ONDE ele esta; noutro mapa mostra QUAL e o mapa.
    #
    # Antes dizia so "Mesmo mapa", que nao ajudava a encontrar ninguem — e ao
    # trocar de mapa o HUD desaparecia por completo, porque o peer era apagado
    # da lista (ver route_packet, "player_disconnect" com map_change).
    same_map = ($game_map && peer.respond_to?(:map_id) && peer.map_id == $game_map.map_id)
    location_text = if same_map
      px = (peer.x.to_i rescue 0)
      py = (peer.y.to_i rescue 0)
      _INTL("Aqui ({1},{2})", px, py)
    elsif peer.respond_to?(:map_id) && peer.map_id
      nome = (pbGetMapNameFromId(peer.map_id) rescue "")
      nome.to_s.empty? ? _INTL("Outro mapa") : _INTL("Em {1}", nome)
    else
      _INTL("Outro mapa")
    end

    peer_name = (peer.respond_to?(:name) && peer.name) ? peer.name.to_s : "?"
    text_key = "#{peer_name}|#{status}|#{location_text}"

    if force || text_key != @last_text_key
      @last_text_key = text_key

      bitmap = @sprite.bitmap
      bitmap.clear

      line1 = _INTL("Grupo: {1}", peer_name)
      line2 = "#{location_text} - #{status}"

      bitmap.font.name = @font_name
      bitmap.font.size = 20
      bitmap.font.bold = true
      bitmap.font.color = Color.new(0, 0, 0, 220)
      bitmap.draw_text(2, 2, bitmap.width, 20, line1, 0)

      bitmap.font.color = Color.new(255, 255, 255)
      bitmap.draw_text(0, 0, bitmap.width, 20, line1, 0)

      bitmap.font.size = 16
      bitmap.font.color = Color.new(0, 0, 0, 220)
      bitmap.draw_text(2, 21, bitmap.width, 18, line2, 0)

      bitmap.font.color = Color.new(180, 230, 255)
      bitmap.draw_text(0, 19, bitmap.width, 18, line2, 0)
    end
  end

  def update
    return if @sprite.disposed?
    update_hud
  end

  def dispose
    @sprite.bitmap.dispose if @sprite.bitmap && !@sprite.bitmap.disposed?
    @sprite.dispose if @sprite && !@sprite.disposed?
    @viewport.dispose if @viewport && !@viewport.disposed?
  end
end


# ==============================================================================
# MULTIPLAYER MAP NAME HUD (Superior Direito)
# ==============================================================================
class AnilMapNameHUD
  def initialize
    @width = 300
    @height = 36
    @x = Graphics.width - @width - 10 rescue 10
    @y = 10 rescue 10
    
    @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 999999
    
    @sprite = Sprite.new(@viewport)
    @sprite.bitmap = Bitmap.new(@width, @height)
    @sprite.x = @x
    @sprite.y = @y
    
    @font_name = MessageConfig::FONT_NAME rescue Font.default_name
    @last_map_id = nil
    @last_map_name = nil
    @last_connected = nil
    @last_in_menu = nil
    
    update_hud(true)
  end

  def update_hud(force = false)
    return if @sprite.disposed?
    
    connected = (defined?(AnilLanRework) && AnilLanRework.connected?)
    map_id = $game_map ? $game_map.map_id : 0
    is_mp_map = (defined?(AnilLanRework) && AnilLanRework.multiplayer_map?(map_id))
    
    in_menu = ($game_temp && $game_temp.respond_to?(:in_menu) && $game_temp.in_menu) ||
              ($game_temp && $game_temp.respond_to?(:message_window_showing) && $game_temp.message_window_showing) ||
              (defined?(Scene_Map_MultiplayerMainMenu) && Scene_Map_MultiplayerMainMenu.respond_to?(:active?) && Scene_Map_MultiplayerMainMenu.active?)
              
    should_be_visible = connected && is_mp_map && $scene.is_a?(Scene_Map) && !in_menu && !$game_temp&.in_battle && !(AnilLanRework.top_broadcast_active? rescue false) && !(AnilArena.activa? rescue false)
    
    if @sprite.visible != should_be_visible
      @sprite.visible = should_be_visible
    end
    
    return unless should_be_visible
    
    map_name = $game_map ? $game_map.name : ""
    
    if force || map_id != @last_map_id || map_name != @last_map_name || connected != @last_connected || in_menu != @last_in_menu
      @last_map_id = map_id
      @last_map_name = map_name
      @last_connected = connected
      @last_in_menu = in_menu
      
      bitmap = @sprite.bitmap
      bitmap.clear
      
      bitmap.font.name = @font_name
      bitmap.font.size = 20
      bitmap.font.bold = true
      
      # Sombra preta
      bitmap.font.color = Color.new(0, 0, 0, 220)
      bitmap.draw_text(2, 2, bitmap.width, bitmap.height, map_name, 2)
      
      # Texto principal branco
      bitmap.font.color = Color.new(255, 255, 255)
      bitmap.draw_text(0, 0, bitmap.width, bitmap.height, map_name, 2)
    end
  end

  def update
    return if @sprite.disposed?
    update_hud
  end

  def dispose
    @sprite.bitmap.dispose if @sprite.bitmap && !@sprite.bitmap.disposed?
    @sprite.dispose if @sprite && !@sprite.disposed?
    @viewport.dispose if @viewport && !@viewport.disposed?
  end
end
