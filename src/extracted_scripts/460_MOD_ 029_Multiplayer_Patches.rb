# ======================================================================
# MÓDULO: PATCHES v2
# Fonte: 0451_Multiplayer_Anil_patchv2.rb (3088 linhas)
# Cópia fiel 1:1 do script original para facilitar manutenção.
# ======================================================================

# encoding: UTF-8
# ============================================================================
# 0449b_Multiplayer_Anil_Patch
# ============================================================================

# ============================================================================
# Scene_CharacterSelect - Tela de selecao de personagem com sprite animado
# ============================================================================
class Scene_CharacterSelect
  ANIM_SPEED   = 10  # Velocidade da animação do charset
  SPRITE_SCALE = 1   # Escala do charset
  
  # Cores do Tema (Azul Profundo e Ouro)
  COLOR_BG_DARK    = Color.new(10, 15, 35)
  COLOR_BG_LIGHT   = Color.new(25, 40, 80)
  COLOR_ACCENT     = Color.new(255, 215, 0, 200) # Ouro
  COLOR_GLASS      = Color.new(255, 255, 255, 30)
  COLOR_BORDER     = Color.new(255, 255, 255, 80)
  def initialize
    @index = 0
    @chars = AnilLanRework.available_characters
    @current_skin = ($game_player&.character_name).to_s rescue "POKEMONTRAINER_RojoNeutro"
    @current_multiplayer_skin = ($player&.multiplayer_skin).to_s rescue ""
    @current_player_meta_id = ($player&.character_ID rescue nil)
    
    # Encontra o índice inicial
    if @chars && !@chars.empty?
      @chars.each_with_index do |entry, idx|
        entry_meta_id = entry["player_meta_id"]
        if entry_meta_id && @current_multiplayer_skin.empty? && @current_player_meta_id.to_i == entry_meta_id.to_i
          @index = idx
          break
        end
        compare_name = @current_multiplayer_skin.empty? ? @current_skin : @current_multiplayer_skin
        if entry["char_name"].to_s == compare_name.to_s
          @index = idx
          break
        end
      end
    end
    @exit = false
  end

  def main
    return if !@chars || @chars.empty?
    
    $game_temp.in_menu = true if $game_temp
    begin
      @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
      @viewport.z = 99_999
      @sprites = {}
      
      create_background
      create_trainer_sprite
      create_ui_panels
      create_character_preview
      create_navigation_hints
      
      # Estado inicial
      refresh_all
      
      @anim_frame = 0
      @anim_counter = 0
      @input_cooldown = 10
      
      pbFadeInAndShow(@sprites)
      
      loop do
        Graphics.update
        Input.update
        update
        break if @exit
      end
      dispose
    ensure
      $game_temp.in_menu = false if $game_temp
    end
  end

  def create_background
    @sprites["bg"] = BitmapSprite.new(Graphics.width, Graphics.height, @viewport)
    bmp = @sprites["bg"].bitmap
    # Gradiente Azul Marinho Profundo
    Graphics.height.times do |y|
      ratio = y.to_f / Graphics.height
      r = 10 + (15 * ratio).to_i
      g = 15 + (25 * ratio).to_i
      b = 35 + (45 * ratio).to_i
      bmp.fill_rect(0, y, Graphics.width, 1, Color.new(r, g, b))
    end
    # Grid discreto
    grid_color = Color.new(255, 255, 255, 12)
    (Graphics.width / 40).times { |i| bmp.fill_rect(i * 40, 0, 1, Graphics.height, grid_color) }
    (Graphics.height / 40).times { |i| bmp.fill_rect(0, i * 40, Graphics.width, 1, grid_color) }
  end
  def create_trainer_sprite
    @sprites["trainer"] = Sprite.new(@viewport)
    @sprites["trainer"].z = 10
  end

  def refresh_trainer_sprite
    entry = @chars[@index]
    return if !entry
    sprite_name = entry["trainer_sprite"].to_s
    begin
      # Mesmo cuidado do refresh_char_preview: sem PNG, o RPG::Cache levanta
      # PhysFSError, que nao e StandardError e escapa aos dois rescue.
      bmp = nil
      if File.exist?("Graphics/Trainers/#{sprite_name}.png")
        begin
          bmp = RPG::Cache.load_bitmap("Graphics/Trainers/", sprite_name)
        rescue Exception
          bmp = nil
        end
      end
      if bmp && bmp.height > 0
        @sprites["trainer"].bitmap = bmp
        
        target_h = Graphics.height * 0.75
        zoom = target_h / bmp.height
        zoom = 1.2 if zoom > 1.2
        
        @sprites["trainer"].zoom_x = zoom
        @sprites["trainer"].zoom_y = zoom
        
        # Centralizado à esquerda
        @sprites["trainer"].ox = bmp.width / 2
        @sprites["trainer"].oy = bmp.height / 2
        @sprites["trainer"].x = 160
        @sprites["trainer"].y = Graphics.height / 2 + 10
      else
        @sprites["trainer"].bitmap = nil
      end
    rescue
      @sprites["trainer"].bitmap = nil
    end
  end

  def create_ui_panels
    panel_x = Graphics.width - 290
    panel_y = (Graphics.height - 320) / 2
    
    # Painel Principal (Glass)
    @sprites["info_panel"] = BitmapSprite.new(260, 320, @viewport)
    @sprites["info_panel"].x = panel_x
    @sprites["info_panel"].y = panel_y
    @sprites["info_panel"].z = 20
  end

  def draw_glass_panel(bmp)
    bmp.clear
    # Fundo semi-transparente
    bmp.fill_rect(0, 0, bmp.width, bmp.height, Color.new(255, 255, 255, 30))
    # Bordas
    bmp.fill_rect(0, 0, bmp.width, 2, Color.new(255, 255, 255, 80))
    bmp.fill_rect(0, bmp.height - 2, bmp.width, 2, Color.new(255, 255, 255, 80))
    bmp.fill_rect(0, 0, 2, bmp.height, Color.new(255, 255, 255, 80))
    bmp.fill_rect(bmp.width - 2, 0, 2, bmp.height, Color.new(255, 255, 255, 80))
    # Linha divisória
    bmp.fill_rect(15, 75, bmp.width - 30, 2, COLOR_ACCENT)
  end

  def create_character_preview
    @sprites["char_preview"] = Sprite.new(@viewport)
    @sprites["char_preview"].z = 35
    @sprites["char_preview"].zoom_x = 2.0
    @sprites["char_preview"].zoom_y = 2.0
  end

  def refresh_char_preview
    # ⚠️ RASTO PARA O FECHO SILENCIOSO NO ANDROID.
    #
    # O jogo fecha sem erro nenhum ao abrir este menu — nao e excepcao de Ruby,
    # e o sistema a matar o processo. Sem mensagem nao ha por onde comecar, e
    # nao consigo reproduzir aqui. Isto grava a ultima entrada que se tentou
    # desenhar; a seguir ao fecho, a ultima linha do ficheiro diz qual era.
    #
    # Ficheiro proprio, porque o AnilLanRework.log sai calado sem a flag global
    # (e ligar essa flag trava o "recuperar partida").
    begin
      e0 = @chars[@index]
      if (anil_diagnostico_ligado? rescue false)
        File.open("seletor_skin.txt", "a") do |f|
          f.puts("[#{Time.now.strftime("%H:%M:%S")}] indice=#{@index}/#{@chars.length} "                "char=#{(e0 && e0["char_name"]).inspect} unlocked=#{e0 && e0["unlocked"]}")
        end
      end
    rescue
    end

    entry = @chars[@index]
    return if !entry
    # ⚠️ SANEAR ANTES DE TOCAR NO DISCO.
    #
    # O File.exist? logo abaixo esta FORA do begin/rescue deste metodo (ele so
    # comeca vinte linhas adiante). Com um char_name que traga um byte nulo, o
    # Ruby levanta ArgumentError ali e a excepcao sobe ate derrubar o jogo — era
    # o crash ao abrir o seletor no JoiPlay. O nome_seguro devolve "" nesse
    # caso, e "" ja era tratado como "sem skin" pelo resto do metodo.
    skin_name = (AnilLanRework::ServerSkins.nome_seguro(entry["char_name"]) rescue entry["char_name"].to_s.delete(0.chr))
    
    # Define opacidades dependendo do estado de desbloqueio
    unlocked = entry.key?("unlocked") ? entry["unlocked"] : true
    target_opacity = unlocked ? 255 : 120
    @sprites["char_preview"].opacity = target_opacity if @sprites["char_preview"]
    @sprites["trainer"].opacity = target_opacity if @sprites["trainer"]
    
    # Se a skin não existe localmente nas pastas de Skins ou Characters, baixa em background!
    skins_enabled = defined?(AnilLanRework::SKINS_ENABLED) && AnilLanRework::SKINS_ENABLED
    if skins_enabled && !skin_name.empty? &&
       !File.exist?(File.join(AnilLanRework::SKINS_FOLDER, "#{skin_name}.png")) &&
       !File.exist?("Graphics/Characters/#{skin_name}.png")
      
      @waiting_download_skin = skin_name
      Thread.new do
        begin
          if defined?(AnilLanRework::ServerSkins)
            AnilLanRework::ServerSkins.baixar_skin_do_servidor(skin_name)
          end
        rescue
        end
      end
    else
      @waiting_download_skin = nil
    end
    
    begin
      bmp = nil
      # Ver o comentario em refresh_char_preview: conferir a existencia antes,
      # senao o PhysFSError de ficheiro ausente escapa aos rescue e derruba tudo.
      if skins_enabled && (AnilLanRework::ServerSkins.png_valido?(File.join(AnilLanRework::SKINS_FOLDER, "#{skin_name}.png")) rescue false)
        begin
          bmp = RPG::Cache.load_bitmap(AnilLanRework::SKINS_FOLDER, skin_name + ".png")
        rescue Exception
          bmp = nil
        end
      end
      if !bmp && (AnilLanRework::ServerSkins.png_valido?("Graphics/Characters/#{skin_name}.png") rescue false)
        begin
          bmp = RPG::Cache.load_bitmap("Graphics/Characters/", skin_name)
        rescue Exception
          bmp = nil
        end
      end
      @char_bitmap = bmp
      
      if bmp && bmp.width > 0
        @cw = bmp.width / 4
        @ch = bmp.height / 4
        
        # Reutiliza ou cria bitmap do sprite
        if !@sprites["char_preview"].bitmap || @sprites["char_preview"].bitmap.width != @cw
          @sprites["char_preview"].bitmap.dispose if @sprites["char_preview"].bitmap
          @sprites["char_preview"].bitmap = Bitmap.new(@cw, @ch)
        end
        
        # Centralização Perfeita
        panel_center_x = @sprites["info_panel"].x + 130
        panel_center_y = @sprites["info_panel"].y + 165
        
        @sprites["char_preview"].ox = @cw / 2
        @sprites["char_preview"].oy = @ch / 2
        @sprites["char_preview"].x = panel_center_x
        @sprites["char_preview"].y = panel_center_y
        
        update_character_frame
      else
        @sprites["char_preview"].bitmap = nil
      end
    rescue
      @char_bitmap = nil
    end
  end

  def create_navigation_hints
    @sprites["help_bg"] = BitmapSprite.new(Graphics.width, 54, @viewport)
    @sprites["help_bg"].y = Graphics.height - 54
    @sprites["help_bg"].z = 40
    bmp = @sprites["help_bg"].bitmap
    bmp.fill_rect(0, 0, Graphics.width, 54, Color.new(0, 0, 0, 180))
    
    pbSetSystemFont(bmp)
    skins_enabled = defined?(AnilLanRework::SKINS_ENABLED) && AnilLanRework::SKINS_ENABLED
    if skins_enabled
      text = _INTL("< Navegar >    [C] Selecionar    [X] Voltar    [F8] Resgatar Código")
    else
      text = _INTL("< Navegar >    [C] Selecionar    [X] Voltar")
    end
    pbDrawShadowText(bmp, 0, 8, Graphics.width, 40, text, Color.new(240, 240, 240), Color.new(0, 0, 0, 100), 1)
  end

  def update
    if @input_cooldown > 0
      @input_cooldown -= 1
      return
    end
    
    update_animation
    
    if Input.trigger?(Input::BACK)
      pbPlayCancelSE
      @exit = true
    elsif Input.trigger?(Input::LEFT)
      @index = (@index - 1) % @chars.length
      pbPlayCursorSE
      refresh_all
      @input_cooldown = 4
    elsif Input.trigger?(Input::RIGHT)
      @index = (@index + 1) % @chars.length
      pbPlayCursorSE
      refresh_all
      @input_cooldown = 4
    elsif Input.trigger?(Input::USE)
      entry = @chars[@index]
      unlocked = entry.key?("unlocked") ? entry["unlocked"] : true
      if !unlocked
        pbPlayBuzzerSE() rescue nil
        pbMessage(_INTL("Essa é uma skin customizada — apenas o dono dela pode utilizá-la.\n\nSe você tem um código de acesso, aperte [F8] para inseri-lo."))
      else
        pbPlayDecisionSE
        apply_character
        @exit = true
      end
    elsif (Input.triggerex?(:F8) rescue false) && defined?(AnilLanRework::SKINS_ENABLED) && AnilLanRework::SKINS_ENABLED
      pbPlayDecisionSE() rescue nil
      codigo = pbEnterText("Digite o código de resgate:", "", "", 30)
      if codigo && !codigo.strip.empty?
        codigo = codigo.strip
        res = AnilLanRework::ServerSkins.resgatar_codigo_skin(codigo)
        if res.is_a?(Hash) && res["status"] == "success"
          pbMessage(_INTL("Sucesso: {1}", res["message"]))
          AnilLanRework.clear_char_cache rescue nil
          @chars = AnilLanRework.available_characters
          refresh_all
        else
          msg = res.is_a?(Hash) ? res["message"] : res.to_s
          pbMessage(_INTL("Erro: {1}", msg))
        end
      end
      @input_cooldown = 10
    end
  end

  def update_animation
    skins_enabled = defined?(AnilLanRework::SKINS_ENABLED) && AnilLanRework::SKINS_ENABLED
    if @waiting_download_skin && skins_enabled &&
       (File.exist?(File.join(AnilLanRework::SKINS_FOLDER, "#{@waiting_download_skin}.png")) ||
        File.exist?("Graphics/Characters/#{@waiting_download_skin}.png"))
      @waiting_download_skin = nil
      refresh_char_preview rescue nil
    end

    @anim_counter += 1
    if @anim_counter >= ANIM_SPEED
      @anim_counter = 0
      @anim_frame = (@anim_frame + 1) % 4
      update_character_frame
    end
  end

  def update_character_frame
    return unless @char_bitmap && @sprites["char_preview"] && @sprites["char_preview"].bitmap
    bmp = @sprites["char_preview"].bitmap
    bmp.clear
    src_rect = Rect.new(@anim_frame * @cw, 0, @cw, @ch)
    bmp.blt(0, 0, @char_bitmap, src_rect)
  end

  def refresh_all
    refresh_trainer_sprite
    refresh_char_preview
    update_texts
  end

  def update_texts
    entry = @chars[@index]
    return if !entry
    bmp = @sprites["info_panel"].bitmap
    draw_glass_panel(bmp)
    
    pbSetSystemFont(bmp)
    # Nome do Personagem
    name_text = entry["label"].to_s
    pbDrawShadowText(bmp, 10, 20, 240, 40, name_text, Color.new(255, 255, 255), Color.new(0, 0, 0, 120), 1)
    
    # Contador
    count_text = _INTL("Personagem {1}/{2}", @index + 1, @chars.length)
    pbDrawShadowText(bmp, 10, 270, 240, 40, count_text, COLOR_ACCENT, Color.new(0, 0, 0, 120), 1)
  end

  def apply_character
    entry = @chars[@index]
    skin_name = entry["char_name"].to_s
    player_meta_id = entry["player_meta_id"]
    trainer_type = entry["trainer_type"]
    selected_char = skin_name
    
    if defined?($player) && $player
      if player_meta_id
        $player.character_ID = player_meta_id.to_i
        $player.multiplayer_skin = nil
        meta = GameData::PlayerMetadata.get(player_meta_id)
        trainer_type ||= meta&.trainer_type
        selected_char = meta&.walk_charset.to_s if meta
      else
        selected_char = skin_name
        $game_player.character_name = selected_char if $game_player
        $player.multiplayer_skin = selected_char
      end
      $player.online_trainer_type = trainer_type if $player.respond_to?(:online_trainer_type=)
    end
    
    $game_player.refresh_charset if $game_player
    
    # Persistência no arquivo de config
    file = AnilLanRework::PLAYER_CFG
    rows = {}
    if File.exist?(file)
      File.readlines(file, encoding: "UTF-8").each do |line|
        parts = line.strip.split("=", 2)
        rows[parts[0].strip] = parts[1].to_s.strip if parts.size == 2
      end
    end
    rows["char"] = selected_char
    File.open(file, "wb") do |f|
      f.write(rows.map { |k, v| k + "=" + v + "\n" }.join.encode(Encoding::UTF_8))
    end
    AnilLanRework.log("character skin changed to #{selected_char}")
    if !selected_char.empty? && defined?(AnilLanRework::SKINS_ENABLED) && AnilLanRework::SKINS_ENABLED
      Thread.new do
        begin
          if defined?(AnilLanRework) && AnilLanRework.respond_to?(:upload_custom_skin)
            AnilLanRework.upload_custom_skin(selected_char)
          end
        rescue
        end
      end
    end

    # Wipe viewports, clear graphics cache, and refresh map spriteset
    begin
      RPG::Cache.clear
      GC.start
      if defined?(AnilLanRework) && AnilLanRework.respond_to?(:request_map_graphics_refresh!)
        AnilLanRework.request_map_graphics_refresh!("character_change", 4)
      end
    rescue => e
      AnilLanRework.log("apply_character wipe error: #{e.message}")
    end
  end

  def dispose
    pbDisposeSpriteHash(@sprites)
    @viewport.dispose
  end
end

if defined?(AnilLanRework::SKINS_ENABLED) && AnilLanRework::SKINS_ENABLED
  # Extensão de Scene_CharacterSelect para suportar skins VIP e resgate F8
  class Scene_CharacterSelect
    alias standard_initialize initialize
    def initialize
      standard_initialize
      # Se as skins estiverem ativadas, atualiza a lista incluindo skins do servidor/locais
      @chars = AnilLanRework.available_characters
      if @chars && !@chars.empty?
        @chars.each_with_index do |entry, idx|
          compare_name = @current_multiplayer_skin.empty? ? @current_skin : @current_multiplayer_skin
          if entry["char_name"].to_s == compare_name.to_s
            @index = idx
            break
          end
        end
      end
    end

    alias standard_create_navigation_hints create_navigation_hints
    def create_navigation_hints
      @sprites["help_bg"] = BitmapSprite.new(Graphics.width, 54, @viewport)
      @sprites["help_bg"].y = Graphics.height - 54
      @sprites["help_bg"].z = 40
      bmp = @sprites["help_bg"].bitmap
      bmp.fill_rect(0, 0, Graphics.width, 54, Color.new(0, 0, 0, 180))
      
      pbSetSystemFont(bmp)
      text = _INTL("< Navegar >    [C] Selecionar    [X] Voltar    [F8] Resgatar Código")
      pbDrawShadowText(bmp, 0, 8, Graphics.width, 40, text, Color.new(240, 240, 240), Color.new(0, 0, 0, 100), 1)
    end

    alias standard_refresh_char_preview refresh_char_preview
    def refresh_char_preview
      entry = @chars[@index]
      return if !entry
      skin_name = entry["char_name"].to_s
      
      unlocked = entry.key?("unlocked") ? entry["unlocked"] : true
      target_opacity = unlocked ? 255 : 120
      @sprites["char_preview"].opacity = target_opacity if @sprites["char_preview"]
      @sprites["trainer"].opacity = target_opacity if @sprites["trainer"]
      
      if !skin_name.empty? &&
         !File.exist?(File.join(AnilLanRework::SKINS_FOLDER, "#{skin_name}.png")) &&
         !File.exist?("Graphics/Characters/#{skin_name}.png")
        
        @waiting_download_skin = skin_name
        Thread.new do
          begin
            AnilLanRework::ServerSkins.baixar_skin_do_servidor(skin_name)
          rescue
          end
        end
      else
        @waiting_download_skin = nil
      end
      
      begin
        # ⚠️ Pedir ao RPG::Cache um ficheiro que nao existe levanta PhysFSError,
        # que NAO e StandardError — passava direto pelo "rescue nil" desta linha
        # E pelo "rescue" do bloco, derrubando o menu inteiro em vez de so ficar
        # sem previa. Basta um personagem da lista sem PNG (charset de
        # GameData sem ficheiro, skin que ainda nao desceu) para acontecer.
        # Conferir a existencia ANTES e o que evita a excecao; o rescue Exception
        # cobre o resto (ficheiro presente mas corrupto).
        bmp = nil
        caminho_skin = File.join(AnilLanRework::SKINS_FOLDER, "#{skin_name}.png")
        # png_valido? em vez de File.exist?: um ficheiro corrompido rebenta
        # dentro do descodificador, onde o `rescue Exception` abaixo nao chega.
        if (AnilLanRework::ServerSkins.png_valido?(caminho_skin) rescue false)
          begin
            bmp = RPG::Cache.load_bitmap(AnilLanRework::SKINS_FOLDER, skin_name + ".png")
          rescue Exception
            bmp = nil
          end
        end
        if !bmp && (AnilLanRework::ServerSkins.png_valido?("Graphics/Characters/#{skin_name}.png") rescue false)
          begin
            bmp = RPG::Cache.load_bitmap("Graphics/Characters/", skin_name)
          rescue Exception
            bmp = nil
          end
        end
        @char_bitmap = bmp
        
        if bmp && bmp.width > 0
          @cw = bmp.width / 4
          @ch = bmp.height / 4
          
          if !@sprites["char_preview"].bitmap || @sprites["char_preview"].bitmap.width != @cw
            @sprites["char_preview"].bitmap.dispose if @sprites["char_preview"].bitmap
            @sprites["char_preview"].bitmap = Bitmap.new(@cw, @ch)
          end
          
          panel_center_x = @sprites["info_panel"].x + 130
          panel_center_y = @sprites["info_panel"].y + 165
          
          @sprites["char_preview"].ox = @cw / 2
          @sprites["char_preview"].oy = @ch / 2
          @sprites["char_preview"].x = panel_center_x
          @sprites["char_preview"].y = panel_center_y
          
          update_character_frame
        else
          @sprites["char_preview"].bitmap = nil
        end
      rescue
        @char_bitmap = nil
      end
    end

    alias standard_update update
    def update
      if @input_cooldown > 0
        @input_cooldown -= 1
        return
      end
      
      update_animation
      
      if Input.trigger?(Input::BACK)
        pbPlayCancelSE
        @exit = true
      elsif Input.trigger?(Input::LEFT)
        @index = (@index - 1) % @chars.length
        pbPlayCursorSE
        refresh_all
        @input_cooldown = 4
      elsif Input.trigger?(Input::RIGHT)
        @index = (@index + 1) % @chars.length
        pbPlayCursorSE
        refresh_all
        @input_cooldown = 4
      elsif Input.trigger?(Input::USE)
        entry = @chars[@index]
        unlocked = entry.key?("unlocked") ? entry["unlocked"] : true
        if !unlocked
          pbPlayBuzzerSE() rescue nil
          pbMessage(_INTL("Essa é uma skin customizada — apenas o dono dela pode utilizá-la.\n\nSe você tem um código de acesso, aperte [F8] para inseri-lo."))
        else
          pbPlayDecisionSE
          apply_character
          @exit = true
        end
      elsif (Input.triggerex?(:F8) rescue false)
        pbPlayDecisionSE() rescue nil
        codigo = pbEnterText("Digite o código de resgate:", "", "", 30)
        if codigo && !codigo.strip.empty?
          codigo = codigo.strip
          res = AnilLanRework::ServerSkins.resgatar_codigo_skin(codigo)
          if res.is_a?(Hash) && res["status"] == "success"
            pbMessage(_INTL("Sucesso: {1}", res["message"]))
            AnilLanRework.clear_char_cache rescue nil
            @chars = AnilLanRework.available_characters
            refresh_all
          else
            msg = res.is_a?(Hash) ? res["message"] : res.to_s
            pbMessage(_INTL("Erro: {1}", msg))
          end
        end
        @input_cooldown = 10
      end
    end
  end
end

# Patch global para garantir que os sprites do treinador (batalhas/ui)
# utilizem a skin multiplayer atual do jogador
module GameData
  class TrainerType
    class << self
      alias patches_original_player_front_sprite_filename player_front_sprite_filename unless method_defined?(:patches_original_player_front_sprite_filename)
      alias patches_original_player_back_sprite_filename player_back_sprite_filename unless method_defined?(:patches_original_player_back_sprite_filename)

      def player_front_sprite_filename(tr_type)
        if $player && $player.respond_to?(:multiplayer_skin) && $player.multiplayer_skin && !$player.multiplayer_skin.empty?
          sprite_name = AnilLanRework.trainer_sprite_name_for_character($player.multiplayer_skin)
          unless sprite_name.empty?
            ret = "Graphics/Trainers/" + sprite_name
            return ret if pbResolveBitmap(ret)
          end
        end
        patches_original_player_front_sprite_filename(tr_type)
      end

      def player_back_sprite_filename(tr_type)
        if $player && $player.respond_to?(:multiplayer_skin) && $player.multiplayer_skin && !$player.multiplayer_skin.empty?
          sprite_name = AnilLanRework.trainer_sprite_name_for_character($player.multiplayer_skin, true)
          unless sprite_name.empty?
            ret = "Graphics/Trainers/" + sprite_name
            return ret if pbResolveBitmap(ret)
          end
        end
        patches_original_player_back_sprite_filename(tr_type)
      end
    end
  end
end

class Trainer
  attr_accessor :multiplayer_skin
  attr_accessor :online_trainer_type
end

class Battle::Scene
  alias anil_rework_pbCreateTrainerFrontSprite pbCreateTrainerFrontSprite unless method_defined?(:anil_rework_pbCreateTrainerFrontSprite)
  def pbCreateTrainerFrontSprite(idxTrainer, trainerType, numTrainers = 1)
    # Check if the opponent trainer has a multiplayer skin
    trainer_obj = @battle.opponent[idxTrainer]
    if trainer_obj && trainer_obj.respond_to?(:multiplayer_skin) && trainer_obj.multiplayer_skin && !trainer_obj.multiplayer_skin.empty?
      sprite_name = AnilLanRework.trainer_sprite_name_for_character(trainer_obj.multiplayer_skin)
      trainerFile = "Graphics/Trainers/" + sprite_name
      if !sprite_name.empty? && pbResolveBitmap(trainerFile)
        spriteX, spriteY = Battle::Scene.pbTrainerPosition(1, idxTrainer, numTrainers)
        trainer = pbAddSprite("trainer_#{idxTrainer + 1}", spriteX, spriteY, trainerFile, @viewport)
        if trainer.bitmap
          trainer.z  = 7 + idxTrainer
          trainer.ox = trainer.src_rect.width / 2
          trainer.oy = trainer.bitmap.height
          return
        end
      end
    end
    anil_rework_pbCreateTrainerFrontSprite(idxTrainer, trainerType, numTrainers)
  end
end

class Sprite_Character < RPG::Sprite
  def refresh_graphic
    
    return if @tile_id == @character.tile_id &&
              @character_name == @character.character_name &&
              @character_hue == @character.character_hue &&
              @oldbushdepth == @character.bush_depth
    @tile_id        = @character.tile_id
    @character_name = @character.character_name
    @character_hue  = @character.character_hue
    @oldbushdepth   = @character.bush_depth
    @charbitmap&.dispose
    @charbitmap = nil
    @bushbitmap&.dispose
    @bushbitmap = nil
    if @tile_id >= 384
      @charbitmap = pbGetTileBitmap(@character.map.tileset_name, @tile_id,
                                    @character_hue, @character.width, @character.height)
      @charbitmapAnimated = false
      @spriteoffset = false
      @cw = Game_Map::TILE_WIDTH * @character.width
      @ch = Game_Map::TILE_HEIGHT * @character.height
      self.src_rect.set(0, 0, @cw, @ch)
      self.ox = @cw / 2
      self.oy = @ch
    elsif @character_name != ""
      # Monkey patch: Tentar carregar skin da pasta Graphics/Skins/ primeiro (skins multiplayer) se habilitado
      skins_enabled = defined?(AnilLanRework::SKINS_ENABLED) && AnilLanRework::SKINS_ENABLED
      skin_path = "Graphics/Skins/" + @character_name
      cache_path = "Graphics/Skins/Cache/" + @character_name

      # ⚠️ QUATRO IDAS AO DISCO POR CADA REFRESCO DE CADA SPRITE.
      #
      # O ficheiro do motor (0067_Sprite_Character) ja tinha esta cache, com a
      # nota a explicar porque. Este metodo redefine o de la de raiz — sem
      # alias — portanto a cache do motor era codigo morto e voltavam as quatro
      # chamadas cruas, agora duplicadas por causa do Skins/Cache.
      #
      # Uma entrada num mapa com 53 personagens da 268 refrescos: mais de mil
      # `File.exist?`. Num telemovel, e sobretudo com a thread do autosave a
      # escrever ao lado, cada um deles pode parar milissegundos — foi assim que
      # a Rota 13 passou de 720 ms para 6,1 s com exactamente o mesmo trabalho:
      # 268 refrescos nos dois casos, 176 ms de bitmaps nos dois casos, e cinco
      # segundos e meio a mais sem sair do `refresh_graphic`.
      #
      # A resposta so muda quando chega uma skin nova, e quem a grava ja faz
      # `$anil_skin_existe = nil`. E a mesma chave e a mesma convencao do motor.
      $anil_skin_existe ||= {}
      exists_png = if $anil_skin_existe.key?(skin_path)
        $anil_skin_existe[skin_path]
      else
        $anil_skin_existe[skin_path] =
          (File.exist?(skin_path + ".png") || File.exist?(skin_path + ".PNG"))
      end
      exists_cache = if $anil_skin_existe.key?(cache_path)
        $anil_skin_existe[cache_path]
      else
        $anil_skin_existe[cache_path] =
          (File.exist?(cache_path + ".png") || File.exist?(cache_path + ".PNG"))
      end
      
      # Baixa skin customizada de outro jogador em tempo real se não existir localmente e habilitado
      if skins_enabled && !@character_name.empty?
        $downloaded_skins_cache ||= {}
        if !$downloaded_skins_cache.key?(@character_name)
          exists_char = pbResolveBitmap("Graphics/Characters/" + @character_name) rescue false
          if !exists_png && !exists_cache && !exists_char
            $downloaded_skins_cache[@character_name] = true
            Thread.new do
              begin
                if defined?(AnilLanRework::ServerSkins)
                  AnilLanRework.log("SkinSync: Baixando skin ausente '#{@character_name}' em tempo real...")
                  AnilLanRework::ServerSkins.baixar_skin_do_servidor(@character_name, true)
                  if $scene.is_a?(Scene_Map)
                    $game_map.need_refresh = true rescue nil
                  end
                end
              rescue => e
                AnilLanRework.log("SkinSync: Erro ao baixar skin ausente '#{@character_name}': #{e.message}")
              end
            end
          else
            $downloaded_skins_cache[@character_name] = false
          end
        end
      end

      if exists_png
        @charbitmap = AnimatedBitmap.new(skin_path + ".png", @character_hue)
        RPG::Cache.retain("Graphics/Skins/", @character_name + ".png", @character_hue) if @character == $game_player
      elsif exists_cache
        @charbitmap = AnimatedBitmap.new(cache_path + ".png", @character_hue)
        RPG::Cache.retain("Graphics/Skins/Cache/", @character_name + ".png", @character_hue) if @character == $game_player
      elsif resolved = pbResolveBitmap(skin_path)
        @charbitmap = AnimatedBitmap.new(resolved, @character_hue)
        RPG::Cache.retain("Graphics/Skins/", File.basename(resolved), @character_hue) if @character == $game_player
      else
        @charbitmap = AnimatedBitmap.new(
          "Graphics/Characters/" + @character_name, @character_hue
        )
        RPG::Cache.retain("Graphics/Characters/", @character_name, @character_hue) if @character == $game_player
      end
      @charbitmapAnimated = true
      @spriteoffset = @character_name[/offset/i]
      @cw = @charbitmap.width / 4
      @ch = @charbitmap.height / 4
      self.ox = @cw / 2
      self.oy = @ch
    else
      self.bitmap = nil
      @cw = 0
      @ch = 0
    end
    @character.sprite_size = [@cw, @ch]
  end

end

class Sprite_DynamicShadows < RPG::Sprite
  def update
    return if !@character || !@character.map
    if !@character.is_a?(Game_Event) && @character.transparent
      self.visible = false
      return
    end
    super
    if @tile_id != @character.tile_id ||
       @character_name != @character.character_name ||
       @character_hue != @character.character_hue
      @tile_id        = @character.tile_id
      @character_name = @character.character_name
      @character_hue  = @character.character_hue
      @chbitmap&.dispose
      if @tile_id >= 384
        @chbitmap = pbGetTileBitmap(@character.map.tileset_name,
                                    @tile_id, @character.character_hue)
        self.src_rect.set(0, 0, 32, 32)
        @ch = 32
        @cw = 32
        self.ox = 16
        self.oy = 32
      else
        # Monkey patch
        skins_enabled = defined?(AnilLanRework::SKINS_ENABLED) && AnilLanRework::SKINS_ENABLED
        skin_path = "Graphics/Skins/" + @character.character_name
        if skins_enabled && (File.exist?(skin_path + ".png") || File.exist?(skin_path + ".PNG"))
          @chbitmap = AnimatedBitmap.new(skin_path + ".png", @character.character_hue)
        elsif skins_enabled && resolved = pbResolveBitmap(skin_path)
          @chbitmap = AnimatedBitmap.new(resolved, @character.character_hue)
        else
          @chbitmap = AnimatedBitmap.new("Graphics/Characters/" + @character.character_name,
                                         @character.character_hue)
        end
        @cw = @chbitmap.width / 4
        @ch = @chbitmap.height / 4
        self.ox = @cw / 2
        self.oy = @ch
      end
    end
    this_x = @character.screen_x
    this_x = ((this_x - (Graphics.width / 2)) * TilemapRenderer::ZOOM_X) + (Graphics.width / 2) if TilemapRenderer::ZOOM_X != 1
    self.x = this_x
    this_y = @character.screen_y
    this_y = ((this_y - (Graphics.height / 2)) * TilemapRenderer::ZOOM_Y) + (Graphics.height / 2) if TilemapRenderer::ZOOM_Y != 1
    self.y = this_y - 2
    if @character.is_a?(Game_Player) || @character.is_a?(Game_Event) ||
       @character.is_a?(Game_Follower)
      self.z = 2
    else
      self.z = @character.screen_z(@ch) - 1
    end
    self.visible = @character.transparent ? false : true
    self.opacity = 255
    if @tile_id == 0
      sx = @character.pattern * @cw
      sy = ((@character.direction - 2) / 2) * @ch
      self.src_rect.set(sx, sy, @cw, @ch)
    end
    if @character.is_a?(Game_Event) && @character.name[/regulartone/i]
      self.tone.set(0, 0, 0, 0)
    else
      pbDayNightTint(self)
    end
    if !@character.is_a?(Game_Event)
      self.color = Color.new(0, 0, 0, 80)
    elsif @character.name[/dinamicshadow/i]
      self.color = Color.new(0, 0, 0, 80)
    else
      self.visible = false
    end
  end
end

#===============================================================================
# PvP Battle Fixes
# - Sincroniza texto de batalha entre os dois jogadores (evita desync de status/dano)
# - Remove ganho de XP em batalhas PvP
# - Remove ganho de dinheiro em batalhas PvP
# - Desativa menus de "Loja de Jogadores" e "Vender" no PC Storage durante PvP
#
# Cole este arquivo DEPOIS do arquivo principal do multiplayer (AnilLanRework).
#===============================================================================

# ==============================================================================
# 1. SINCRONIZAÇÃƒO DE TEXTO DE BATALHA
#    Garante que ambos os jogadores vejam cada mensagem ao mesmo tempo,
#    evitando que um jogador avance muito na batalha enquanto o outro ainda
#    está lendo texto anterior (causa de dessync de status/HP).
# ==============================================================================

if defined?(Battle) && defined?(Battle::Scene)
  class Battle::Scene
    unless method_defined?(:anil_pvp_fix_pbUpdate)
      # Overrides para sincronização e logs de batalha online
      alias anil_pvp_fix_pbUpdate pbUpdate unless method_defined?(:anil_pvp_fix_pbUpdate)
    alias anil_pvp_fix_pbDisposeSprites pbDisposeSprites unless method_defined?(:anil_pvp_fix_pbDisposeSprites)
    alias anil_pvp_fix_pbDisplayMessage pbDisplayMessage unless method_defined?(:anil_pvp_fix_pbDisplayMessage)
    alias anil_pvp_fix_pbDisplayPausedMessage pbDisplayPausedMessage unless method_defined?(:anil_pvp_fix_pbDisplayPausedMessage)
    alias anil_pvp_fix_pbWaitMessage pbWaitMessage unless method_defined?(:anil_pvp_fix_pbWaitMessage)
    alias anil_pvp_fix_pbStartBattle pbStartBattle unless method_defined?(:anil_pvp_fix_pbStartBattle)
    alias anil_pvp_fix_pbCommandMenuEx pbCommandMenuEx unless method_defined?(:anil_pvp_fix_pbCommandMenuEx)
    alias anil_pvp_fix_pbFightMenu pbFightMenu unless method_defined?(:anil_pvp_fix_pbFightMenu)
    alias anil_pvp_fix_pbChooseTarget pbChooseTarget unless method_defined?(:anil_pvp_fix_pbChooseTarget)
    alias anil_pvp_fix_pbLevelUp pbLevelUp unless method_defined?(:anil_pvp_fix_pbLevelUp)
    alias anil_pvp_fix_pbForgetMove pbForgetMove unless method_defined?(:anil_pvp_fix_pbForgetMove)
    alias anil_pvp_fix_pbDisplayConfirmMessage pbDisplayConfirmMessage unless method_defined?(:anil_pvp_fix_pbDisplayConfirmMessage)

    def anil_pvp_lan_sync?
      ctx = AnilLanRework::BattleSync.active_context rescue nil
      return false unless ctx && AnilLanRework.connected?
      # Só sincroniza se o contexto já estiver ligado a esta batalha
      return false if !ctx.respond_to?(:battle) || ctx.battle.nil?
      ctx.battle.equal?(@battle)
    rescue
      false
    end

    def anil_wait_overlay
      return @anil_wait_overlay if @anil_wait_overlay
      viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
      viewport.z = 99_999
      window = Window_UnformattedTextPokemon.newWithSize("", 0, 0, Graphics.width, 64, viewport)
      window.y = (Graphics.height - window.height) / 2
      window.visible = false
      @anil_wait_overlay = [viewport, window]
    rescue
      nil
    end

    def anil_show_wait_overlay(text)
      overlay = anil_wait_overlay
      return unless overlay
      viewport, window = overlay
      return unless viewport && window
      new_text = text.to_s
      return if new_text.empty?
      window.text = new_text if window.text.to_s != new_text
      window.y = (Graphics.height - window.height) / 2
      viewport.visible = true if viewport.respond_to?(:visible=)
      window.visible = true
    rescue
      nil
    end

    def anil_hide_wait_overlay
      return unless @anil_wait_overlay
      viewport, window = @anil_wait_overlay
      window.text = "" rescue nil
      window.visible = false rescue nil
      viewport.visible = false if viewport && viewport.respond_to?(:visible=)
    end

    def pbDisposeSprites
      if @anil_wait_overlay
        viewport, window = @anil_wait_overlay
        window.dispose rescue nil
        viewport.dispose rescue nil
        @anil_wait_overlay = nil
      end
      anil_pvp_fix_pbDisposeSprites rescue nil
    end


    def anil_wait_overlay_needed?
      return false unless anil_pvp_lan_sync?
      return false if (AnilLanRework::BattleSync.local_manual_lock? rescue false)
      return false unless (AnilLanRework::BattleSync.remote_manual_lock? rescue false)
      message_window = @sprites["messageWindow"] rescue nil
      return false if message_window && message_window.visible
      true
    rescue
      false
    end

    # ==========================================================================
    # OVERRIDES PARA OCULTAR O OVERLAY DE ESPERA EM MENUS E DIÁLOGOS INTERATIVOS
    # ==========================================================================
    alias anil_wait_fix_pbFadeOutAndHide pbFadeOutAndHide unless method_defined?(:anil_wait_fix_pbFadeOutAndHide)
    def pbFadeOutAndHide(sprites)
      anil_hide_wait_overlay
      anil_wait_fix_pbFadeOutAndHide(sprites)
    end

    alias anil_wait_fix_pbFadeInAndShow pbFadeInAndShow unless method_defined?(:anil_wait_fix_pbFadeInAndShow)
    def pbFadeInAndShow(sprites, visibleSprites)
      result = anil_wait_fix_pbFadeInAndShow(sprites, visibleSprites)
      if anil_wait_overlay_needed?
        wait_text = AnilLanRework::BattleSync.manual_wait_text rescue AnilLanRework::BattleSync.waiting_text("Aguardando parceiro...")
        anil_show_wait_overlay(wait_text)
      end
      result
    end

    def pbFadeOutIn(z = 99999, nofadeout = false, &block)
      anil_hide_wait_overlay
      result = super(z, nofadeout, &block)
      if anil_wait_overlay_needed?
        wait_text = AnilLanRework::BattleSync.manual_wait_text rescue AnilLanRework::BattleSync.waiting_text("Aguardando parceiro...")
        anil_show_wait_overlay(wait_text)
      end
      result
    end

    def pbFadeOutInWithMusic(zViewport = 99999, &block)
      anil_hide_wait_overlay
      result = super(zViewport, &block)
      if anil_wait_overlay_needed?
        wait_text = AnilLanRework::BattleSync.manual_wait_text rescue AnilLanRework::BattleSync.waiting_text("Aguardando parceiro...")
        anil_show_wait_overlay(wait_text)
      end
      result
    end

    def pbTopRightWindow(text, scene = nil)
      anil_hide_wait_overlay
      result = super(text, scene || self)
      if anil_wait_overlay_needed?
        wait_text = AnilLanRework::BattleSync.manual_wait_text rescue AnilLanRework::BattleSync.waiting_text("Aguardando parceiro...")
        anil_show_wait_overlay(wait_text)
      end
      result
    end

    alias anil_wait_fix_pbShowCommands pbShowCommands unless method_defined?(:anil_wait_fix_pbShowCommands)
    def pbShowCommands(msg, commands, defaultValue)
      anil_hide_wait_overlay
      result = anil_wait_fix_pbShowCommands(msg, commands, defaultValue)
      if anil_wait_overlay_needed?
        wait_text = AnilLanRework::BattleSync.manual_wait_text rescue AnilLanRework::BattleSync.waiting_text("Aguardando parceiro...")
        anil_show_wait_overlay(wait_text)
      end
      result
    end

    def anil_wait_for_remote_manual_unlock(waiting_text = nil)
      return false unless anil_pvp_lan_sync?
      return false if (AnilLanRework::BattleSync.local_manual_lock? rescue false)
      locked = (AnilLanRework::BattleSync.remote_manual_lock? rescue false)
      return false unless locked
      waited = false
      loop do
        break unless locked
        waited = true
        wait_text = waiting_text || (AnilLanRework::BattleSync.manual_wait_text rescue AnilLanRework::BattleSync.waiting_text("Aguardando parceiro..."))
        AnilLanRework::BattleSync.wait_for_remote_manual_lock(wait_text, AnilLanRework::TURN_TIMEOUT) rescue nil
        AnilLanRework::BattleSync.pump_network rescue nil
        locked = (AnilLanRework::BattleSync.remote_manual_lock? rescue false)
        break unless AnilLanRework.connected?
      end
      waited
    rescue
      false
    end

    def pbUpdate(cw = nil)
      if AnilLanRework.connected?
        AnilLanRework::BattleSync.pump_network rescue nil
        AnilLanRework::BattleSync.flush_remote_status_events_safe rescue nil
      end
      result = anil_pvp_fix_pbUpdate(cw)
      cw_visible = false
      begin
        cw_visible = cw && cw.visible
      rescue
      end
      if cw_visible
        anil_hide_wait_overlay
      elsif anil_wait_overlay_needed?
        wait_text = AnilLanRework::BattleSync.manual_wait_text rescue AnilLanRework::BattleSync.waiting_text("Aguardando parceiro...")
        anil_show_wait_overlay(wait_text)
      else
        anil_hide_wait_overlay
      end
      result
    end

    def pbCommandMenuEx(idxBattler, texts, mode = 0)
      pbShowWindow(COMMAND_BOX)
      cw = @sprites["commandWindow"]
      cw.setTexts(texts)
      cw.setIndexAndMode(@lastCmd[idxBattler], mode)
      pbSelectBattler(idxBattler)
      ret = -1
      loop do
        anil_wait_for_remote_manual_unlock
        oldIndex = cw.index
        pbUpdate(cw)
        if Input.trigger?(Input::LEFT)
          cw.index -= 1 if (cw.index & 1) == 1
        elsif Input.trigger?(Input::RIGHT)
          cw.index += 1 if (cw.index & 1) == 0
        elsif Input.trigger?(Input::UP)
          cw.index -= 2 if (cw.index & 2) == 2
        elsif Input.trigger?(Input::DOWN)
          cw.index += 2 if (cw.index & 2) == 0
        end
        pbPlayCursorSE if cw.index != oldIndex
        if Input.trigger?(Input::USE)
          pbPlayDecisionSE
          ret = cw.index
          @lastCmd[idxBattler] = ret
          break
        elsif Input.trigger?(Input::BACK) && mode == 1
          pbPlayCancelSE
          break
        elsif Input.trigger?(Input::F9) && $DEBUG
          pbPlayDecisionSE
          ret = -2
          break
        end
      end
      ret
    end

    def pbFightMenu(idxBattler, megaEvoPossible = false)
      battler = @battle.battlers[idxBattler]
      cw = @sprites["fightWindow"]
      cw.battler = battler
      moveIndex = 0
      if battler.moves[@lastMove[idxBattler]]&.id
        moveIndex = @lastMove[idxBattler]
      end
      cw.shiftMode = (@battle.pbCanShift?(idxBattler)) ? 1 : 0
      cw.setIndexAndMode(moveIndex, (megaEvoPossible) ? 1 : 0)
      needFullRefresh = true
      needRefresh = false
      loop do
        if needFullRefresh
          pbShowWindow(FIGHT_BOX)
          pbSelectBattler(idxBattler)
          needFullRefresh = false
        end
        if needRefresh
          if megaEvoPossible
            newMode = (@battle.pbRegisteredMegaEvolution?(idxBattler)) ? 2 : 1
            cw.mode = newMode if newMode != cw.mode
          end
          needRefresh = false
        end
        if anil_wait_for_remote_manual_unlock
          needFullRefresh = true
          next
        end
        oldIndex = cw.index
        pbUpdate(cw)
        if Input.trigger?(Input::LEFT)
          cw.index -= 1 if (cw.index & 1) == 1
        elsif Input.trigger?(Input::RIGHT)
          cw.index += 1 if battler.moves[cw.index + 1]&.id && (cw.index & 1) == 0
        elsif Input.trigger?(Input::UP)
          cw.index -= 2 if (cw.index & 2) == 2
        elsif Input.trigger?(Input::DOWN)
          cw.index += 2 if battler.moves[cw.index + 2]&.id && (cw.index & 2) == 0
        end
        pbPlayCursorSE if cw.index != oldIndex
        if Input.trigger?(Input::USE)
          pbPlayDecisionSE
          break if yield cw.index
          needFullRefresh = true
          needRefresh = true
        elsif Input.trigger?(Input::BACK)
          pbPlayCancelSE
          break if yield -1
          needRefresh = true
        elsif Input.trigger?(Input::ACTION)
          if megaEvoPossible
            pbPlayDecisionSE
            break if yield -2
            needRefresh = true
          end
        elsif Input.trigger?(Input::SPECIAL)
          if cw.shiftMode > 0
            pbPlayDecisionSE
            break if yield -3
            needRefresh = true
          end
        end
      end
      @lastMove[idxBattler] = cw.index
    end

    def pbDisposeSprites
      anil_hide_wait_overlay
      if @anil_wait_overlay
        viewport, window = @anil_wait_overlay
        window.dispose rescue nil
        viewport.dispose rescue nil
        @anil_wait_overlay = nil
      end
      anil_pvp_fix_pbDisposeSprites
    end

    def anil_pvp_message_tick(cw = nil)
      AnilLanRework::BattleSync.pump_network rescue nil
      AnilLanRework::BattleSync.wait_for_remote_manual_lock(AnilLanRework::BattleSync.waiting_text("Aguardando parceiro...")) rescue nil
      AnilLanRework::BattleSync.flush_remote_party_refresh rescue nil
      AnilLanRework::BattleSync.flush_remote_status_events rescue nil
      pbUpdate(cw)
    end

    def pbWaitMessage
      return anil_pvp_fix_pbWaitMessage unless anil_pvp_lan_sync?
      return unless @briefMessage
      pbShowWindow(MESSAGE_BOX)
      cw = @sprites["messageWindow"]
      timer_start = System.uptime
      while System.uptime - timer_start < AnilLanRework::LAN_BRIEF_MESSAGE_PAUSE
        anil_pvp_message_tick(cw)
      end

      # Sincroniza que terminou a mensagem breve
      ctx = AnilLanRework::BattleSync.active_context
      if defined?(@briefMessageStep) && @briefMessageStep.to_i > 0 && ctx && ctx.mode == :coop
        AnilLanRework::BattleSync.sync_text_display_state(@briefMessageStep, "done", "brief_message")
      end

      cw.text    = ""
      cw.visible = false
      @briefMessage = false
      @briefMessageStep = 0
    end

    def pbDisplayMessage(msg, brief = false)
      return anil_pvp_fix_pbDisplayMessage(msg, brief) unless anil_pvp_lan_sync?
      AnilLanRework::BattleSync.wait_for_remote_manual_lock(AnilLanRework::BattleSync.waiting_text("Aguardando parceiro...")) rescue nil

      # Sincroniza passo de texto: bloqueia quem está Ã  frente
      msg = AnilLanRework::BattleSync.sync_message_step(msg) rescue msg
      if msg == :__anil_skip_local_message__
        yield if block_given?
        return
      end
      ctx = AnilLanRework::BattleSync.active_context
      local_step = ctx ? ctx.local_text_step.to_i : 0

      # Detecta se é mensagem manual (level up / novo golpe)
      is_manual = AnilLanRework::BattleSync.anil_is_manual_message?(msg)
      protected_manual = AnilLanRework::BattleSync.local_manual_lock? rescue false

      pbWaitMessage
      pbShowWindow(MESSAGE_BOX)
      cw = @sprites["messageWindow"]
      old_letter = cw.letterbyletter
      cw.letterbyletter = is_manual # Mantém animação se for manual
      cw.setText(msg)
      PBDebug.log_message(msg)
      yield if block_given?

      # Sincroniza que a mensagem foi exibida (mostrada)
      if local_step > 0 && ctx && ctx.mode == :coop
        AnilLanRework::BattleSync.sync_text_display_state(local_step, "shown", "message")
      end

      if brief
        @briefMessage = true
        @briefMessageStep = local_step
        return
      end

      local_done = false
      sent_done = false
      timer_start = System.uptime
      loop do
        anil_pvp_message_tick(cw)
        if !local_done
          if is_manual
            if !cw.busy? && (Input.trigger?(Input::USE) || Input.trigger?(Input::BACK))
              local_done = true
            end
          else
            if System.uptime - timer_start >= AnilLanRework::LAN_MESSAGE_PAUSE
              local_done = true
            end
          end
        end
        if local_done && !sent_done
          if local_step > 0 && ctx && ctx.mode == :coop
            AnilLanRework::BattleSync.sync_text_display_state(local_step, "done", "message", false)
          end
          sent_done = true
        end
        remote_done = (local_step <= 0) || !ctx || ctx.mode != :coop || 
                      AnilLanRework::BattleSync.remote_text_state_synced?(local_step, "done") ||
                      AnilLanRework::BattleSync.coop_remote_sync_disabled?(ctx)
        break if local_done && (remote_done || protected_manual)
      end

      cw.text    = ""
      cw.visible = false
      AnilLanRework::BattleSync.wait_for_remote_manual_lock(AnilLanRework::BattleSync.waiting_text("Aguardando parceiro...")) rescue nil
    ensure
      cw.letterbyletter = old_letter if defined?(cw) && cw
    end

    def pbDisplayPausedMessage(msg)
      return anil_pvp_fix_pbDisplayPausedMessage(msg) unless anil_pvp_lan_sync?
      AnilLanRework::BattleSync.wait_for_remote_manual_lock(AnilLanRework::BattleSync.waiting_text("Aguardando parceiro...")) rescue nil

      # Sincroniza passo de texto: bloqueia quem está Ã  frente
      msg = AnilLanRework::BattleSync.sync_message_step(msg) rescue msg
      if msg == :__anil_skip_local_message__
        yield if block_given?
        return
      end
      ctx = AnilLanRework::BattleSync.active_context
      local_step = ctx ? ctx.local_text_step.to_i : 0

      # Detecta se é mensagem manual
      is_manual = AnilLanRework::BattleSync.anil_is_manual_message?(msg)
      protected_manual = AnilLanRework::BattleSync.local_manual_lock? rescue false

      pbWaitMessage
      pbShowWindow(MESSAGE_BOX)
      cw = @sprites["messageWindow"]
      old_letter = cw.letterbyletter
      cw.letterbyletter = is_manual
      cw.text = msg + "\1"
      PBDebug.log_message(msg)
      yield if block_given?

      # Sincroniza que a mensagem foi exibida (mostrada)
      if local_step > 0 && ctx && ctx.mode == :coop
        AnilLanRework::BattleSync.sync_text_display_state(local_step, "shown", "paused_message")
      end

      local_done = false
      sent_done = false
      timer_start = System.uptime
      loop do
        anil_pvp_message_tick(cw)
        if !local_done
          if is_manual
            if !cw.busy? && (Input.trigger?(Input::USE) || Input.trigger?(Input::BACK))
              local_done = true
            end
          else
            if System.uptime - timer_start >= AnilLanRework::LAN_PAUSED_MESSAGE_PAUSE
              local_done = true
            end
          end
        end
        if local_done && !sent_done
          if local_step > 0 && ctx && ctx.mode == :coop
            AnilLanRework::BattleSync.sync_text_display_state(local_step, "done", "paused_message", false)
          end
          sent_done = true
        end
        remote_done = (local_step <= 0) || !ctx || ctx.mode != :coop || 
                      AnilLanRework::BattleSync.remote_text_state_synced?(local_step, "done") ||
                      AnilLanRework::BattleSync.coop_remote_sync_disabled?(ctx)
        break if local_done && (remote_done || protected_manual)
      end

      cw.text    = ""
      cw.visible = false
      AnilLanRework::BattleSync.wait_for_remote_manual_lock(AnilLanRework::BattleSync.waiting_text("Aguardando parceiro...")) rescue nil
    ensure
      cw.letterbyletter = old_letter if defined?(cw) && cw
    end

    def pbStartBattle(*args)
      ctx = AnilLanRework::BattleSync.active_context rescue nil
      AnilLanRework.log("battle scene start battle_id=#{ctx&.battle_id}") if anil_pvp_lan_sync?
      result = anil_pvp_fix_pbStartBattle(*args)
      AnilLanRework.log("battle scene start done battle_id=#{ctx&.battle_id}") if anil_pvp_lan_sync?
      result
    end

    def pbLevelUp(*args)
      return anil_pvp_fix_pbLevelUp(*args) unless anil_pvp_lan_sync?
      # Já estamos no lock de "exp_phase", então só atualiza a reason contextual
      AnilLanRework::BattleSync.update_manual_lock_reason("level_up_stats")
      result = anil_pvp_fix_pbLevelUp(*args)
      # Retorna ao status anterior caso ainda tenha mais XP para processar
      AnilLanRework::BattleSync.update_manual_lock_reason("exp_gaining")
      result
    end

    def pbForgetMove(*args)
      return anil_pvp_fix_pbForgetMove(*args) unless anil_pvp_lan_sync?
      AnilLanRework::BattleSync.update_manual_lock_reason("choosing_move")
      result = anil_pvp_fix_pbForgetMove(*args)
      AnilLanRework::BattleSync.update_manual_lock_reason("exp_gaining")
      result
    end

    def pbDisplayConfirmMessage(msg)
      return anil_pvp_fix_pbDisplayConfirmMessage(msg) unless anil_pvp_lan_sync?
      AnilLanRework::BattleSync.with_manual_lock("confirm_message") do
        anil_pvp_fix_pbDisplayConfirmMessage(msg)
      end
    end

    def pbChooseTarget(idxBattler, target_data, visibleSprites = nil)
      if anil_pvp_lan_sync?
        ctx = AnilLanRework::BattleSync.active_context
        AnilLanRework.log("battle scene choose_target battle_id=#{ctx&.battle_id} battler=#{idxBattler}")
      end
      anil_pvp_fix_pbChooseTarget(idxBattler, target_data, visibleSprites)
    end
    end # FIM do bypass do soft-reset F5
  end
end

# ==============================================================================
# 2. SEM GANHO DE XP EM PvP (Comentado - transferido e corrigido no MOD 033)
# ==============================================================================

# if defined?(Battle)
#   class Battle
#     alias anil_pvp_fix_pbGainExp pbGainExp unless method_defined?(:anil_pvp_fix_pbGainExp)
# 
#     def pbGainExp
#       ctx = AnilLanRework::BattleSync.active_context rescue nil
#       partner_injected = (AnilLanRework::BattleSync.instance_variable_get(:@partner_injected) rescue false)
#       coop_active = (ctx && ctx.mode == :coop && partner_injected)
#       if ctx && ctx.mode == :pvp
#         AnilLanRework.log("pvp: XP gain skipped battle_id=#{ctx.battle_id}")
#         return
#       end
# 
#       # Registro de níveis iniciais
#       old_lvls = $player.party.map { |p| p.level } if coop_active
# 
#       anil_pvp_fix_pbGainExp
# 
#       if coop_active
#         new_lvls = $player.party.map { |p| p.level }
#         if old_lvls != new_lvls
#           AnilLanRework.log("coop: Level up detected, forcing party sync")
#           AnilLanRework::BattleSync.queue_outbound_party_sync rescue nil
#         end
#         # Sincronização final da fase de XP (passo virtual alto)
#         AnilLanRework::BattleSync.sync_text_display_state(99999, "done", "exp_gain", false) rescue nil
#       end
#     end
# 
#     # pbGainExpOne já era sobreescrito pelo multiplayer para sync de party.
#     # Aqui garantimos que ele também pule em PvP.
#     alias anil_pvp_fix_pbGainExpOne pbGainExpOne unless method_defined?(:anil_pvp_fix_pbGainExpOne)
# 
#     def pbGainExpOne(idxParty, defeatedBattler, numPartic, expShare, expAll, showMessages = true)
#       ctx = AnilLanRework::BattleSync.active_context rescue nil
#       partner_injected = (AnilLanRework::BattleSync.instance_variable_get(:@partner_injected) rescue false)
#       if ctx && ctx.mode == :pvp
#         return nil
#       end
#       if ctx && ctx.mode == :coop && partner_injected
#         local_party_size = @player[0] ? @player[0].party.length : ($player.party.length rescue 6)
#         if idxParty >= local_party_size
#           AnilLanRework.log("coop: skipping local EXP gain for partner's pokemon at idxParty=#{idxParty}")
#           return nil
#         end
#       end
#       anil_pvp_fix_pbGainExpOne(idxParty, defeatedBattler, numPartic, expShare, expAll, showMessages)
#     end
# 
#     alias anil_pvp_fix_pbGainEVsOne pbGainEVsOne unless method_defined?(:anil_pvp_fix_pbGainEVsOne)
#     def pbGainEVsOne(idxParty, defeatedBattler)
#       ctx = AnilLanRework::BattleSync.active_context rescue nil
#       partner_injected = (AnilLanRework::BattleSync.instance_variable_get(:@partner_injected) rescue false)
#       if ctx && ctx.mode == :pvp
#         return nil
#       end
#       if ctx && ctx.mode == :coop && partner_injected
#         local_party_size = @player[0] ? @player[0].party.length : ($player.party.length rescue 6)
#         if idxParty >= local_party_size
#           return nil
#         end
#       end
#       anil_pvp_fix_pbGainEVsOne(idxParty, defeatedBattler)
#     end
#   end
# end

if defined?(Battle)
  class Battle
    # Override de pbLearnMove (Battle) para enviar reason contextual
    # quando o jogador precisa escolher qual golpe esquecer.
    alias anil_coop_original_pbLearnMove pbLearnMove unless method_defined?(:anil_coop_original_pbLearnMove)
    def pbLearnMove(idxParty, newMove)
      ctx = AnilLanRework::BattleSync.active_context rescue nil
      if ctx && ctx.mode == :coop && AnilLanRework.connected?
        pkmn = pbParty(0)[idxParty] rescue nil
        # Se o Pokémon já tem 4 golpes, o jogador vai precisar escolher
        if pkmn && !pkmn.hasMove?(newMove) && pkmn.numMoves >= Pokemon::MAX_MOVES
          AnilLanRework::BattleSync.update_manual_lock_reason("choosing_move")
        end
      end
      result = anil_coop_original_pbLearnMove(idxParty, newMove)
      AnilLanRework::BattleSync.update_manual_lock_reason("exp_gaining") if ctx && ctx.mode == :coop
      result
    end


  end
end

# ==============================================================================
# 3. SEM GANHO DE DINHEIRO EM PvP
#    Impede que o jogador ganhe dinheiro ao vencer uma batalha PvP online.
#    pbEndOfBattle retorna o resultado; o dinheiro é concedido internamente
#    por pbGainMoney / pbGainMoneyFromBattle.
# ==============================================================================

if defined?(Battle)
  class Battle
    # Intercepta o método que concede dinheiro após a batalha.
    # O método exato pode variar por versão do Essentials; cobrimos os nomes comuns.

    %i[pbGainMoney pbGainMoneyFromBattle pbReceiveMoney].each do |method_name|
      if method_defined?(method_name) && !method_defined?(:"anil_pvp_fix_#{method_name}")
        alias_method :"anil_pvp_fix_#{method_name}", method_name
        define_method(method_name) do |*args, **kwargs, &block|
          ctx = AnilLanRework::BattleSync.active_context rescue nil
          if ctx && ctx.mode == :pvp
            AnilLanRework.log("pvp: money gain skipped (#{method_name}) battle_id=#{ctx.battle_id}")
            return
          end
          send(:"anil_pvp_fix_#{method_name}", *args, **kwargs, &block)
        end
      end
    end

    # Fallback: sobrescreve pbEndOfBattle para remover prêmio em dinheiro.
    # Fazemos isso restaurando o dinheiro ao valor anterior após a batalha PvP.
    alias anil_pvp_fix_money_pbEndOfBattle pbEndOfBattle unless method_defined?(:anil_pvp_fix_money_pbEndOfBattle)

    def pbEndOfBattle(*args)
      ctx = AnilLanRework::BattleSync.active_context rescue nil
      money_before = (defined?($player) && $player ? $player.money.to_i : 0) if ctx && ctx.mode == :pvp

      result = anil_pvp_fix_money_pbEndOfBattle(*args)

      if ctx && ctx.mode == :pvp && defined?($player) && $player
        if $player.money.to_i > money_before.to_i
          AnilLanRework.log("pvp: money gain reverted battle_id=#{ctx.battle_id} before=#{money_before} after=#{$player.money}")
          $player.money = money_before
        end
      end

      result
    end
  end
end

# ==============================================================================
# 4. DESATIVA MENUS DE "LOJA DE JOGADORES" E "VENDER" NO PC STORAGE
#    Durante uma sessão PvP (ou simplesmente: enquanto o multiplayer estiver
#    ativo) ocultamos as opÃ§ões de mercado de jogadores para evitar
#    inconsistências de estado.
# ==============================================================================

# 4a. Menu do PC (Computador) — remove "Loja de Jogadores"
if defined?(MenuHandlers)
  # Substituímos o handler registrado pelo arquivo principal para verificar
  # se uma batalha PvP está ativa antes de abrir o mercado.
  MenuHandlers.add(:pc_menu, :anil_online_market_buy, {
    "name"  => proc { next _INTL("Loja de Jogadores") },
    "order" => 15,
    "condition" => proc {
      # Mostra apenas se conectado E não em batalha PvP
      next false unless AnilLanRework.enabled? && AnilLanRework.connected?
      ctx = AnilLanRework::BattleSync.active_context rescue nil
      next false if ctx && ctx.mode == :pvp
      next true
    },
    "effect" => proc { |_menu|
      AnilLanRework::PlayerMarket.open_pc_buy_menu
      next false
    }
  })
end

# 4b. PC Storage — remove opção "Vender" do menu de comandos por Pokémon
if defined?(PokemonStorageScreen)
  class PokemonStorageScreen
    alias anil_pvp_fix_organise_commands organise_commands unless method_defined?(:anil_pvp_fix_organise_commands)

    def organise_commands(selected, pokemon)
      # Desabilita mercado online se em batalha PvP ou sem conexão
      ctx = AnilLanRework::BattleSync.active_context rescue nil
      pvp_active = ctx && ctx.mode == :pvp
      market_available = AnilLanRework.enabled? && AnilLanRework.connected? && !pvp_active

      commands     = []
      cmdMove      = -1
      cmdSummary   = -1
      cmdWithdraw  = -1
      cmdItem      = -1
      cmdMark      = -1
      cmdPokedex   = -1
      cmdRelease   = -1
      cmdSellOnline = -1
      cmdDebug     = -1

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

      commands[cmdSummary  = commands.length] = _INTL("Resumo")
      commands[cmdWithdraw = commands.length] = (selected[0] == -1) ? _INTL("Guardar") : _INTL("Retirar")
      commands[cmdItem     = commands.length] = _INTL("Objeto")
      commands[cmdMark     = commands.length] = _INTL("Marcas")
      commands[cmdPokedex  = commands.length] = _INTL("Pokédex")

      if pokemon && market_available
        commands[cmdSellOnline = commands.length] = _INTL("Vender")
      end

      commands[cmdRelease = commands.length] = _INTL("Liberar")
      commands[cmdDebug   = commands.length] = _INTL("Debug") if $DEBUG
      commands[commands.length]              = _INTL("Cancelar")

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

# 4c. NPC de loja (pbPokemonMart) — remove opção "Loja de Jogadores" em PvP
if defined?(pbPokemonMart) && !defined?(anil_pvp_fix_original_pbPokemonMart)
  alias anil_pvp_fix_original_pbPokemonMart pbPokemonMart

  def pbPokemonMart(stock, speech = nil, cantsell = false)
    $game_temp.in_menu = true rescue nil
    begin
      ctx = AnilLanRework::BattleSync.active_context rescue nil
      pvp_active  = ctx && ctx.mode == :pvp
      market_live = AnilLanRework.enabled? && AnilLanRework.connected? && !pvp_active

      # Se não há sessão online ativa ou está em PvP, usa loja normal diretamente
      return anil_pvp_fix_original_pbPokemonMart(stock, speech, cantsell) unless market_live

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
            scene  = PokemonMart_Scene.new
            screen = PokemonMartScreen.new(scene, stock)
            screen.pbBuyScreen
          elsif !cantsell && normal_choice == 1
            scene  = PokemonMart_Scene.new
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
    ensure
      $game_temp.in_menu = false rescue nil
    end
  end
end

#===============================================================================
# SECAO 2 — Correcoes de Preview e Selecao PvP (integrado)
#
# - selected_pvp_party: deserializa blob negociado (host e cliente)
# - request_duel: envia selected_party com size correto
# - receive_accept: preserva local_party_blob do host
# - update_pending_invite: limita selecao ao tamanho do host
#===============================================================================

module AnilLanRework
  module BattleSync
    class << self

      # ----------------------------------------------------------------------
      # selected_pvp_party — deserializa o blob negociado (host e cliente)
      # ----------------------------------------------------------------------
      def selected_pvp_party(ctx)
        return [] unless ctx && ctx.mode == :pvp

        unless Array(ctx.local_party_blob).empty?
          party = AnilLanRework::Serializer.deserialize_party(ctx.local_party_blob)
          return party unless party.empty?
        end

        unless Array(ctx.local_party_order).empty?
          party = party_from_order(ctx.local_party_order)
          return party unless party.empty?
        end

        if custom_duel_rules?(ctx.rules)
          party = party_from_order(normalize_duel_rules(ctx.rules)["local_party_order"])
          return party unless party.empty?
        end

        []
      rescue
        []
      end

      # ----------------------------------------------------------------------
      # request_duel — envia selected_party E size = tamanho da party escolhida
      # ----------------------------------------------------------------------
      alias anil_v2_original_request_duel request_duel unless method_defined?(:anil_v2_original_request_duel)
      def request_duel(peer, size: 1, party: nil, full_party: nil, rules: nil)
        duel_rules = normalize_duel_rules(rules)
        duel_rules["style"] = duel_style_from_rules(duel_rules, size)

        selected_party = Array(party)
        selected_party = $player.party if selected_party.empty?
        preview_party  = Array(full_party)
        preview_party  = $player.party if preview_party.empty?

        # size reflete o numero real de pokemons escolhidos
        effective_size = selected_party.length
        effective_size = size if effective_size <= 0

        battle_id = build_battle_id("duel")
        seed      = rand(0x3FFF_FFFF)

        stored_packet = {
          "to_id"          => peer.internal_id,
          "battle_id"      => battle_id,
          "mode"           => "pvp",
          "size"           => effective_size,
          "seed"           => seed,
          "rules"          => duel_rules,
          "party"          => AnilLanRework::Serializer.serialize_party(preview_party),
          "selected_party" => AnilLanRework::Serializer.serialize_party(selected_party),
          "sent_at"        => Time.now.to_f
        }

        wire_packet = stored_packet.dup
        wire_packet["rules"] = public_duel_rules(duel_rules)

        @outgoing_invites[battle_id] = stored_packet

        AnilLanRework.log(
          "request_duel battle_id=#{battle_id} size=#{effective_size} " \
          "rules=#{duel_rules.inspect} " \
          "local_party=#{party_species_names(selected_party).inspect}"
        )

        AnilLanRework.connection.send_packet("battle_invite", wire_packet)
      end

      # ----------------------------------------------------------------------
      # receive_accept — preserva local_party_blob do host
      # ----------------------------------------------------------------------
      alias anil_v2_original_receive_accept receive_accept unless method_defined?(:anil_v2_original_receive_accept)
      def receive_accept(packet)
        battle_id = packet["battle_id"].to_s
        original  = @outgoing_invites.delete(battle_id)
        return unless original

        peer_id = packet["sender_id"].to_s
        peer    = AnilLanRework.players[peer_id]
        peer.party_blob = Array(packet["party"]) if peer && packet["party"]

        pending_rules    = normalize_duel_rules(original["rules"])
        local_party_blob = Array(original["selected_party"] || original["party"])
        foe_party_blob   = Array(packet["selected_party"] || packet["party"])

        AnilLanRework.log(
          "receive_accept battle_id=#{battle_id} " \
          "local=#{party_species_names(AnilLanRework::Serializer.deserialize_party(local_party_blob)).inspect} " \
          "foe=#{party_species_names(AnilLanRework::Serializer.deserialize_party(foe_party_blob)).inspect}"
        )

        @pending_start = {
          :battle_id    => battle_id,
          :peer_id      => peer_id,
          :size         => original["size"].to_i,
          :seed         => original["seed"].to_i,
          :client_index => 0,
          :rules        => pending_rules,
          :party        => foe_party_blob,
          :local_party  => local_party_blob
        }
        AnilLanRework.suppress_peer_interaction!(20)
      end

      # ----------------------------------------------------------------------
      # update_pending_invite — cliente: limita selecao ao tamanho do host
      # e passa selected_party no accept
      # ----------------------------------------------------------------------
      alias anil_v2_original_update_pending_invite update_pending_invite unless method_defined?(:anil_v2_original_update_pending_invite)
      def update_pending_invite
        return unless @pending_invite
        return unless $scene.is_a?(Scene_Map)
        return if $game_temp&.message_window_showing

        invite    = @pending_invite
        @pending_invite = nil
        sender_id = invite["sender_id"].to_s

        peer = AnilLanRework.players[sender_id]
        sender_name = peer && !peer.name.to_s.empty? ? peer.name.to_s : sender_id

        size         = invite["size"].to_i
        invite_rules = normalize_duel_rules(invite["rules"])

        return unless pbConfirmMessage(duel_invite_message(sender_name, size, invite_rules))

        peer.party_blob = Array(invite["party"]) if peer && invite["party"]

        # Party do oponente para o preview (a selected_party que o host escolheu)
        host_selected_blob = Array(invite["selected_party"] || invite["party"])
        host_selected      = AnilLanRework::Serializer.deserialize_party(host_selected_blob)

        local_party = $player.party

        if custom_duel_rules?(invite_rules)
          # Passa o tamanho da party do host como limite para o cliente
          response = prompt_custom_duel_response_sized(
            invite_rules,
            sender_name,
            host_selected,
            size   # <- limite = numero de pokemons que o host escolheu
          )

          unless response
            AnilLanRework.connection.send_packet("battle_decline",
              "to_id" => sender_id, "battle_id" => invite["battle_id"].to_s
            )
            pbMessage(_INTL("O convite de PvP customizado foi cancelado.")) rescue nil
            return
          end

          invite_rules, local_party = response

          if local_party.empty?
            AnilLanRework.connection.send_packet("battle_decline",
              "to_id" => sender_id, "battle_id" => invite["battle_id"].to_s
            )
            pbMessage(_INTL("Nao foi possivel montar a tua equipe para este PvP.")) rescue nil
            return
          end
        end

        local_party_blob   = AnilLanRework::Serializer.serialize_party(local_party)

        AnilLanRework.log(
          "accept_duel battle_id=#{invite['battle_id']} " \
          "local=#{party_species_names(local_party).inspect} " \
          "foe=#{party_species_names(host_selected).inspect}"
        )

        AnilLanRework.connection.send_packet("battle_accept",
          "to_id"          => sender_id,
          "battle_id"      => invite["battle_id"].to_s,
          "party"          => AnilLanRework::Serializer.serialize_party($player.party),
          "selected_party" => local_party_blob
        )

        @pending_start = {
          :battle_id    => invite["battle_id"].to_s,
          :peer_id      => sender_id,
          :size         => size,
          :seed         => invite["seed"].to_i,
          :client_index => 1,
          :rules        => invite_rules,
          :party        => host_selected_blob,  # foe = selected do host
          :local_party  => local_party_blob     # local = o que o cliente escolheu
        }
        AnilLanRework.suppress_peer_interaction!(20)
      end

      # ----------------------------------------------------------------------
      # prompt_custom_duel_response_sized — igual ao original mas com limite
      # de pokemons igual ao que o host escolheu (parametro max_size)
      # ----------------------------------------------------------------------
      def prompt_custom_duel_response_sized(rules, opponent_name, opponent_party, max_size)
        normalized = normalize_duel_rules(rules)
        selection  = choose_custom_duel_party_sized(
          style:         normalized["style"],
          opponent_name: opponent_name,
          opponent_party: opponent_party,
          max_size:      max_size
        )
        return nil unless selection

        order, local_party = selection
        normalized["local_party_order"] = order
        [normalized, local_party]
      end

      # ----------------------------------------------------------------------
      # choose_custom_duel_party_sized — selecao com limite de tamanho
      # ----------------------------------------------------------------------
      def choose_custom_duel_party_sized(style:, opponent_name:, opponent_party:, max_size: 6)
        battle_rules = build_custom_duel_online_rules_sized(style, max_size)
        local_party  = Array($player&.party)
        return nil if local_party.empty?

        unless battle_rules.ruleset.hasRegistrableTeam?(local_party)
          pbMessage(_INTL("Nao tens uma equipe Pokemon valida para esse PvP.")) rescue nil
          return nil
        end

        foe_party = Array(opponent_party)
        if battle_rules.team_preview? && !foe_party.empty?
          CableClub_Scene.new.pbTeamPreview(
            build_preview_trainer(opponent_name),
            foe_party,
            battle_rules.team_preview
          )
        end

        team_order = CableClub.choose_team(battle_rules.ruleset)
        return nil if !team_order || team_order.empty?

        selected_party = party_from_order(team_order)
        return nil if selected_party.empty?

        [team_order, selected_party]
      end

      # ----------------------------------------------------------------------
      # build_custom_duel_online_rules_sized — regras com min/max = max_size
      # ----------------------------------------------------------------------
      def build_custom_duel_online_rules_sized(style, max_size)
        n     = [[max_size.to_i, 1].max, 6].min
        rules = PokemonOnlineRules.new
        rules.setNumberRange(n, n)   # min e max iguais ao host
        rules.addPokemonRule(NonEggRestriction) if defined?(NonEggRestriction)
        case duel_style_from_rules({ "style" => style })
        when "double"
          rules.addBattleRule(DoubleBattle) if defined?(DoubleBattle)
        when "triple"
          rules.addBattleRule(TripleBattle) if defined?(TripleBattle)
        end
        rules.setTeamPreview(30)
        rules
      end

      # ----------------------------------------------------------------------
      # start_pvp_battle — usa local_party_blob desserializado
      # ----------------------------------------------------------------------
      alias anil_v2_original_start_pvp_battle start_pvp_battle unless method_defined?(:anil_v2_original_start_pvp_battle)
      def start_pvp_battle(data)
        peer      = AnilLanRework.players[data[:peer_id].to_s]
        foe_party = AnilLanRework::Serializer.deserialize_party(
          data[:party] || (peer && peer.party_blob)
        )
        return if foe_party.empty?

        trainer_type = AnilLanRework.respond_to?(:default_trainer_type) ? AnilLanRework.default_trainer_type : GameData::TrainerType.keys.first
        trainer_name = (peer && !peer.name.to_s.empty?) ? peer.name.to_s : "Rival"
        foe_trainer  = begin
          NPCTrainer.new(trainer_name, trainer_type)
        rescue
          Trainer.new(trainer_name, trainer_type)
        end
        foe_trainer.party = foe_party
        foe_trainer.multiplayer_skin = peer.char_name if peer && foe_trainer.respond_to?(:multiplayer_skin)

        local_party_blob = Array(data[:local_party])
        local_party      = AnilLanRework::Serializer.deserialize_party(local_party_blob)
        local_party      = $player.party if local_party.empty?

        AnilLanRework.log(
          "start_pvp_battle battle_id=#{data[:battle_id]} " \
          "client_index=#{data[:client_index]} " \
          "local=#{party_species_names(local_party).inspect} " \
          "foe=#{party_species_names(foe_party).inspect}"
        )

        activate_context(
          battle_id:         data[:battle_id],
          mode:              :pvp,
          client_index:      data[:client_index],
          partner_id:        data[:peer_id],
          seed:              data[:seed],
          rules:             data[:rules],
          foe_party:         foe_trainer.party,
          local_party_blob:  local_party_blob,
          local_party_order: normalize_duel_rules(data[:rules])["local_party_order"]
        )

        battle_style = duel_style_from_rules(data[:rules], data[:size])
        setBattleRule(battle_style) rescue nil

        # Substitui a party global temporariamente (caso BattleCreationHelperMethods não seja chamado)
        saved_local_party = $player.party
        $player.party = local_party

        if TrainerBattle.respond_to?(:start_core)
          TrainerBattle.start_core(foe_trainer)
        elsif TrainerBattle.respond_to?(:mp_orig_start_core)
          TrainerBattle.mp_orig_start_core(foe_trainer)
        end
        
        $player.party = saved_local_party

      rescue => e
        AnilLanRework.log("start_pvp_battle error #{e}")
        $player.party = saved_local_party if saved_local_party
        $game_temp.clear_battle_rules rescue nil
        remove_partner if respond_to?(:remove_partner)
        clear_context
        AnilLanRework.request_map_graphics_refresh!("pvp_start_error", 3)
        pbMessage(_INTL("O duelo online foi cancelado.")) rescue nil
      end

    end
  end
end

# ------------------------------------------------------------------------------
# BattleCreationHelperMethods — usa selected_pvp_party do ctx (blob negociado)
# ------------------------------------------------------------------------------
if defined?(BattleCreationHelperMethods)
  module BattleCreationHelperMethods
    class << self
      alias anil_v2_orig_set_up_player_trainers set_up_player_trainers unless method_defined?(:anil_v2_orig_set_up_player_trainers)

      def set_up_player_trainers(foe_party)
        ctx = AnilLanRework::BattleSync.active_context rescue nil

        if ctx && ctx.mode == :pvp && !Array(ctx.local_party_blob).empty?
          local_party = AnilLanRework::BattleSync.selected_pvp_party(ctx)

          unless local_party.empty?
            trainers, ally_items, _pp, _ps = anil_v2_orig_set_up_player_trainers(foe_party)

            AnilLanRework.log(
              "set_up_player_trainers pvp " \
              "local=#{AnilLanRework::BattleSync.party_species_names(local_party).inspect} " \
              "foe=#{AnilLanRework::BattleSync.party_species_names(foe_party).inspect}"
            )

            return [trainers, ally_items, local_party, [0]]
          end
        end

        anil_v2_orig_set_up_player_trainers(foe_party)
      end
    end
  end
end

# ------------------------------------------------------------------------------
# Fix Joiplay: @exit = true apos conectar com sucesso (host e cliente)
# ------------------------------------------------------------------------------
class Scene_MultiplayerLobby_Rework
  def do_join
    set_status(_INTL("A procurar hosts na rede local..."))
    Graphics.update

    hosts     = AnilLanRework.discover_hosts
    chosen    = AnilLanRework.pick_discovered_host(hosts, @server_ip)
    target_ip = @server_ip.to_s

    if chosen
      target_ip  = chosen["ip"].to_s
      @server_ip = target_ip
      write_cfg(IP_CFG, "ip", @server_ip)
      host_label = AnilLanRework.discovered_host_label(chosen)
      msg = hosts.length > 1 ?
        AnilLanRework.ui_format("Foram encontrados {1} hosts LAN.\nA usar: {2}\n\nA ligar em {3}...", hosts.length, host_label, target_ip) :
        AnilLanRework.ui_format("Host encontrado: {1}\n\nA ligar em {2}...", host_label, target_ip)
      set_status(msg)
    else
      set_status(AnilLanRework.ui_format("Nenhum host respondeu.\nA ligar em {1}...", target_ip))
    end
    Graphics.update

    ok = begin
      AnilLanRework.connect(target_ip, @player_id, @player_name, @player_char, false)
    rescue => e
      AnilLanRework.log("join connect error #{e.class}: #{e.message}"); false
    end

    if ok
      @action_succeeded = true
      remember_connected_session(target_ip, chosen)
      set_status(_INTL("Ligado ao rework LAN."))
      Graphics.update
      AnilLanRework.request_map_graphics_refresh!("join_connect", 3)
      AnilLanRework.schedule_delayed_map_refresh!("join_connect_patch", 2.0, 3)
      $scene = Scene_Map.new if $joiplay
      sleep(1.0) unless $joiplay
      @exit = true
    else
      set_status(AnilLanRework.ui_format("ERRO: {1}\n\nPressiona X/Z para fechar.", AnilLanRework.last_error_message.to_s))
    end
  end

  def do_host
    set_status(_INTL("A iniciar servidor local do rework..."))
    Graphics.update

    unless @server_thread&.alive?
      server_error = nil
      @server_thread = Thread.new do
        begin
          LanCableReworkServer.new.run
        rescue => e
          server_error = "#{e.class}: #{e.message}"
          AnilLanRework.log("server thread error #{e.class}: #{e.message}")
        end
      end

      if $joiplay
        sleep(0.5)
        unless @server_thread.alive?
          set_status(AnilLanRework.ui_format("ERRO: servidor nao iniciou.\n{1}\n\nPressiona X/Z.", server_error || "thread morreu"))
          return
        end
      else
        ready = false; probe_error = nil; t0 = Time.now.to_f
        while Time.now.to_f - t0 < 3.0
          break unless @server_thread&.alive?
          begin
            TCPSocket.new("127.0.0.1", AnilLanRework::SERVER_PORT).close
            ready = true
            break
          rescue => e
            probe_error = e.message
            sleep(0.05)
          end
        end
        unless ready
          detail = server_error ? "thread=#{server_error}" : probe_error ? "probe=#{probe_error}" : "timeout"
          set_status(AnilLanRework.ui_format("ERRO: servidor nao iniciou na porta {1}.\n{2}\n\nPressiona X/Z.", AnilLanRework::SERVER_PORT, detail))
          return
        end
      end
    end

    ok = begin
      AnilLanRework.connect("127.0.0.1", @player_id, @player_name, @player_char, true)
    rescue => e
      AnilLanRework.log("host connect error #{e.class}: #{e.message}"); false
    end

    if ok
      @action_succeeded = true
      set_status(AnilLanRework.ui_format("Servidor iniciado! Voce e o host.\nIPs locais: {1}", AnilLanRework.local_ip_summary))
      Graphics.update
      AnilLanRework.request_map_graphics_refresh!("host_connect", 4)
      AnilLanRework.schedule_delayed_map_refresh!("host_connect_patch", 2.0, 4)
      $scene = Scene_Map.new if $joiplay
      sleep(1.0) unless $joiplay
      @exit = true
    else
      set_status(AnilLanRework.ui_format("ERRO: {1}\n\nPressiona X/Z para fechar.", AnilLanRework.last_error_message.to_s))
    end
  end
end

#===============================================================================
# AnilLanRework — Battle Freeze & Connection Patch
# Corrige os travamentos por turno sem alterar a lógica de batalha.
#===============================================================================

module AnilLanRework
  @battle_wait_depth = 0

  class << self
    attr_accessor :battle_wait_depth

    def in_battle_wait?
      @battle_wait_depth.to_i > 0
    end

    def enter_battle_wait!
      @battle_wait_depth = @battle_wait_depth.to_i + 1
    end

    def leave_battle_wait!
      @battle_wait_depth = [@battle_wait_depth.to_i - 1, 0].max
    end
  end
end


class << Graphics
  alias anil_freeze_patch_original_graphics_update update unless method_defined?(:anil_freeze_patch_original_graphics_update)

  def update
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
          unless $game_temp&.in_battle
            AnilLanRework::BattleSync.update_pending_coop_invite
          end
        rescue => e
          AnilLanRework.log("graphics network update error #{e.class}: #{e.message}")
        ensure
          @anil_rework_updating = false
        end
      end
    end
    anil_freeze_patch_original_graphics_update
  end
end


module AnilLanRework
  module BattleSync
    def self.with_battle_wait
      AnilLanRework.enter_battle_wait!
      yield
    ensure
      AnilLanRework.leave_battle_wait!
    end

    class << self
      alias anil_freeze_patch_original_wait_for_remote_actions wait_for_remote_actions unless method_defined?(:anil_freeze_patch_original_wait_for_remote_actions)
      alias anil_freeze_patch_original_wait_for_remote_foe_action wait_for_remote_foe_action unless method_defined?(:anil_freeze_patch_original_wait_for_remote_foe_action)
      alias anil_freeze_patch_original_wait_for_remote_hp_event wait_for_remote_hp_event unless method_defined?(:anil_freeze_patch_original_wait_for_remote_hp_event)
      alias anil_freeze_patch_original_wait_for_remote_foe_turn wait_for_remote_foe_turn unless method_defined?(:anil_freeze_patch_original_wait_for_remote_foe_turn)
      alias anil_freeze_patch_original_wait_for_remote_called_move wait_for_remote_called_move unless method_defined?(:anil_freeze_patch_original_wait_for_remote_called_move)
      alias anil_freeze_patch_original_wait_for_remote_capture_result wait_for_remote_capture_result unless method_defined?(:anil_freeze_patch_original_wait_for_remote_capture_result)
      alias anil_freeze_patch_original_wait_for_remote_turn wait_for_remote_turn unless method_defined?(:anil_freeze_patch_original_wait_for_remote_turn)
      alias anil_freeze_patch_original_wait_for_remote_turn_hash wait_for_remote_turn_hash unless method_defined?(:anil_freeze_patch_original_wait_for_remote_turn_hash)
      alias anil_freeze_patch_original_wait_for_remote_switch wait_for_remote_switch unless method_defined?(:anil_freeze_patch_original_wait_for_remote_switch)
      alias anil_freeze_patch_original_send_pvp_turn_hash send_pvp_turn_hash unless method_defined?(:anil_freeze_patch_original_send_pvp_turn_hash)
      alias anil_freeze_patch_original_queue_remote_turn_hash queue_remote_turn_hash unless method_defined?(:anil_freeze_patch_original_queue_remote_turn_hash)
      alias anil_freeze_patch_original_flush_remote_status_events flush_remote_status_events unless method_defined?(:anil_freeze_patch_original_flush_remote_status_events)

      def update_battle_graphics(ctx = nil)
        ctx ||= @active_context
        battle = ctx.battle rescue nil
        if battle && battle.respond_to?(:scene) && battle.scene
          scene = battle.scene
          # pbFrameUpdate atualiza os sprites dos battlers (HP, animações, sombras)
          scene.pbFrameUpdate rescue nil
          # pbGraphicsUpdate atualiza fundo, animações de lineup e chama Graphics.update
          if scene.respond_to?(:pbGraphicsUpdate)
            scene.pbGraphicsUpdate
          else
            Graphics.update
          end
        else
          Graphics.update
        end
      rescue
        Graphics.update
      end

      def anil_freeze_patch_wait_deadlines(timeout = nil)
        effective_timeout = timeout.to_f
        effective_timeout = AnilLanRework::TURN_TIMEOUT.to_f if effective_timeout <= 0
        started = Time.now.to_f
        absolute_deadline = started + (effective_timeout * 2.0)
        [started, effective_timeout, absolute_deadline]
      rescue
        started = Time.now.to_f
        [started, AnilLanRework::TURN_TIMEOUT.to_f, started + (AnilLanRework::TURN_TIMEOUT.to_f * 2.0)]
      end

      def anil_freeze_patch_wait_timed_out?(started, timeout, absolute_deadline)
        now = Time.now.to_f
        return true if absolute_deadline && now >= absolute_deadline
        return false if !timeout || timeout.to_f <= 0
        (now - started) >= timeout.to_f
      rescue
        false
      end

      def anil_freeze_patch_context_details(ctx = nil)
        ctx ||= @active_context
        battle = ctx && ctx.battle
        turn = battle ? (battle.turnCount.to_i rescue "nil") : "nil"
        "battle_id=#{ctx&.battle_id || 'nil'} mode=#{ctx&.mode || 'nil'} client_index=#{ctx&.client_index || 'nil'} turn=#{turn}"
      rescue
        "battle_id=nil mode=nil client_index=nil turn=nil"
      end

      def anil_freeze_patch_log_pvp_wait(label, message, ctx = nil)
        ctx ||= @active_context
        return unless ctx && ctx.mode == :pvp
        AnilLanRework.log("#{label} #{anil_freeze_patch_context_details(ctx)} #{message}")
      rescue
      end


      def send_pvp_turn_hash(battle)
        state_hash = anil_freeze_patch_original_send_pvp_turn_hash(battle)
        ctx = @active_context
        if state_hash && ctx && ctx.mode == :pvp
          turn = battle ? (battle.turnCount.to_i rescue 0) : 0
          AnilLanRework.log(
            "pvp turn hash tx #{anil_freeze_patch_context_details(ctx)} expected_turn=#{turn} state_hash=#{state_hash}"
          )
        end
        state_hash
      end

      def queue_remote_turn_hash(packet)
        if packet.is_a?(Hash)
          ctx = @active_context
          battle_id = packet["battle_id"].to_s
          if ctx && ctx.mode == :pvp && ctx.battle_id.to_s == battle_id
            AnilLanRework.log(
              "pvp turn hash rx #{anil_freeze_patch_context_details(ctx)} packet_turn=#{packet['turn'].to_i} state_hash=#{packet['state_hash'].to_i & 0xFFFFFFFF}"
            )
          end
        end
        anil_freeze_patch_original_queue_remote_turn_hash(packet)
      end

      def wait_for_remote_actions(waiting_text = nil, timeout_override = nil, expected_turn = nil, expected_slot = nil)
        return nil if coop_remote_sync_disabled?
        started = Time.now.to_f
        viewport = nil
        window = nil
        base_text = waiting_text || "Aguardando parceiro..."
        begin
          with_battle_wait do
            loop do
              actions = next_remote_action(expected_turn, expected_slot)
              return actions if actions
              return nil unless AnilLanRework.connected?

              lock_active = remote_manual_lock?
              if lock_active
                started = Time.now.to_f
                lock_text = manual_wait_text
                if !window
                  viewport, window = build_wait_window(lock_text)
                elsif window.text != lock_text
                  window.text = lock_text
                end
              else
                if window && window.text != base_text
                  window.text = base_text
                elsif !window && waiting_text
                  viewport, window = build_wait_window(base_text)
                end
              end

              # Ver a nota em 000d wait_for_remote_actions: com o slot remoto
              # travado (golpe de duas fases) nao ha humano escolhendo, entao a
              # espera e curta. Escolha humana mantem o timeout longo.
              limite = timeout_override || (
                (@active_context && @active_context.mode == :coop) ?
                  AnilLanRework::COOP_COMMAND_TIMEOUT :
                  AnilLanRework::TURN_TIMEOUT
              )
              return nil if Time.now.to_f - started >= limite
              AnilLanRework.connection.tick
              AnilLanRework.connection.drain { |packet| AnilLanRework::Router.route_packet(packet) }
              flush_remote_party_refresh
              flush_remote_status_events_safe
              update_battle_graphics(@active_context) rescue nil
              Input.update rescue nil
              window.update rescue nil if window
            end
          end
        ensure
          dispose_wait_window(viewport, window) if window
        end
      end

      def wait_for_remote_foe_action(idx_battler, waiting_text = nil)
        return nil if coop_remote_sync_disabled?
        started = Time.now.to_f
        viewport = nil
        window = nil
        base_text = waiting_text || "Sincronizando inimigo..."
        begin
          with_battle_wait do
            loop do
              packet = next_remote_foe_action(idx_battler)
              return packet if packet
              return nil unless AnilLanRework.connected?

              lock_active = remote_manual_lock?
              if lock_active
                started = Time.now.to_f
                lock_text = manual_wait_text
                if !window
                  viewport, window = build_wait_window(lock_text)
                elsif window.text != lock_text
                  window.text = lock_text
                end
              else
                if window && window.text != base_text
                  window.text = base_text
                elsif !window && waiting_text
                  viewport, window = build_wait_window(base_text)
                end
              end

              return nil if Time.now.to_f - started >= AnilLanRework::TURN_TIMEOUT
              AnilLanRework.connection.tick
              AnilLanRework.connection.drain { |p| AnilLanRework::Router.route_packet(p) }
              flush_remote_party_refresh
              flush_remote_status_events_safe
              update_battle_graphics(@active_context) rescue nil
              Input.update rescue nil
              window.update rescue nil if window
            end
          end
        ensure
          dispose_wait_window(viewport, window) if window
        end
      end

      def wait_for_remote_hp_event(idx_battler, hp_kind, timeout = nil)
        return nil if coop_remote_sync_disabled?
        timeout ||= AnilLanRework::TURN_TIMEOUT
        with_battle_wait do
          started, effective_timeout, absolute_deadline = anil_freeze_patch_wait_deadlines(timeout)
          loop do
            packet = extract_valid_remote_hp_event(idx_battler, hp_kind)
            return packet if packet
            return nil unless AnilLanRework.connected?

            if AnilLanRework::BattleSync.remote_manual_lock?
              started = Time.now.to_f
              absolute_deadline = started + (effective_timeout * 2.0) if absolute_deadline
            end

            if anil_freeze_patch_wait_timed_out?(started, effective_timeout, absolute_deadline)
              lock_active = AnilLanRework::BattleSync.remote_manual_lock?
              AnilLanRework.log(
                "battle hp wait timeout #{anil_freeze_patch_context_details} battler=#{idx_battler} kind=#{hp_kind} " \
                "manual_lock=#{lock_active} absolute=#{Time.now.to_f >= absolute_deadline}"
              )
              return nil
            end
            AnilLanRework.connection.tick
            AnilLanRework.connection.drain { |remote_packet| AnilLanRework::Router.route_packet(remote_packet) }
            flush_remote_status_events_safe
            packet = extract_valid_remote_hp_event(idx_battler, hp_kind)
            return packet if packet
            if @active_context && !@active_context.pending_status_events.empty?
              return :authoritative_none
            end
            update_battle_graphics(@active_context) rescue nil
            Input.update rescue nil
          end
        end
      end

      def wait_for_remote_foe_turn
        return nil if coop_remote_sync_disabled?
        with_battle_wait { anil_freeze_patch_original_wait_for_remote_foe_turn }
      end

      def wait_for_remote_called_move(idx_battler)
        return nil if coop_remote_sync_disabled?
        with_battle_wait do
          started = Time.now.to_f
          loop do
            packet = next_remote_called_move(idx_battler)
            return packet if packet
            return nil unless AnilLanRework.connected?

            started = Time.now.to_f if AnilLanRework::BattleSync.remote_manual_lock?

            return nil if Time.now.to_f - started >= AnilLanRework::TURN_TIMEOUT
            pump_network
            flush_remote_status_events_safe
            consume_remote_text_steps(@active_context)
            update_battle_graphics(@active_context) rescue nil
            Input.update rescue nil
          end
        end
      end

      def wait_for_remote_capture_result(idx_battler)
        return nil if coop_remote_sync_disabled?
        with_battle_wait do
          started, effective_timeout, absolute_deadline = anil_freeze_patch_wait_deadlines(AnilLanRework::TURN_TIMEOUT)
          loop do
            packet = next_remote_capture_result(idx_battler)
            return packet if packet
            return nil unless AnilLanRework.connected?

            if AnilLanRework::BattleSync.remote_manual_lock?
              started = Time.now.to_f
              absolute_deadline = started + (effective_timeout * 2.0) if absolute_deadline
            end

            if anil_freeze_patch_wait_timed_out?(started, effective_timeout, absolute_deadline)
              lock_active = AnilLanRework::BattleSync.remote_manual_lock?
              AnilLanRework.log(
                "battle capture wait timeout #{anil_freeze_patch_context_details} battler=#{idx_battler} " \
                "manual_lock=#{lock_active} absolute=#{Time.now.to_f >= absolute_deadline}"
              )
              return nil
            end
            pump_network
            flush_remote_status_events_safe
            consume_remote_text_steps(@active_context)
            update_battle_graphics(@active_context) rescue nil
            Input.update rescue nil
          end
        end
      end


      def wait_for_remote_turn(expected_turn = nil)
        return nil if coop_remote_sync_disabled?
        started, effective_timeout, absolute_deadline = anil_freeze_patch_wait_deadlines(AnilLanRework::TURN_TIMEOUT)
        base_text = wait_text_for_remote_turn
        viewport, window = build_wait_window(base_text)
        anil_freeze_patch_log_pvp_wait("pvp wait remote turn start", "timeout=#{effective_timeout}")
        lock_text = manual_wait_text
        with_battle_wait do
          loop do
            pump_network
            flush_remote_party_refresh
            packet = next_remote_turn(expected_turn)
            if packet
              choices = Array(packet["choices"]).length
              anil_freeze_patch_log_pvp_wait("pvp wait remote turn recv", "choices=#{choices}")
              return packet
            end
            return nil unless AnilLanRework.connected?

            locked = remote_manual_lock?
            if locked || remote_message_active?
              started = Time.now.to_f
              absolute_deadline = started + (effective_timeout * 2.0) if absolute_deadline
              window.text = remote_message_active? ? "Aguardando diálogo do parceiro..." : lock_text if window
            elsif window && window.text != base_text
              window.text = base_text
            end

            if anil_freeze_patch_wait_timed_out?(started, effective_timeout, absolute_deadline)
              anil_freeze_patch_log_pvp_wait(
                "pvp wait remote turn timeout",
                "pending_turns=#{@active_context&.pending_turns&.length || 0} manual_lock=#{locked} absolute=#{Time.now.to_f >= absolute_deadline}"
              )
              return nil
            end
            update_battle_graphics(@active_context) rescue nil
            Input.update rescue nil
            window.update rescue nil
          end
        end
      ensure
        dispose_wait_window(viewport, window)
      end

      def wait_for_remote_turn_hash(expected_turn)
        return nil if coop_remote_sync_disabled?
        started, effective_timeout, absolute_deadline = anil_freeze_patch_wait_deadlines(AnilLanRework::TURN_TIMEOUT)
        viewport, window = build_wait_window(wait_text_for_turn_hash)
        anil_freeze_patch_log_pvp_wait("pvp wait turn hash start", "expected_turn=#{expected_turn} timeout=#{effective_timeout}")
        with_battle_wait do
          loop do
            pump_network
            packet = next_remote_turn_hash(expected_turn)
            if packet
              anil_freeze_patch_log_pvp_wait(
                "pvp wait turn hash recv",
                "expected_turn=#{expected_turn} packet_turn=#{packet['turn'].to_i} state_hash=#{packet['state_hash'].to_i & 0xFFFFFFFF}"
              )
              return packet
            end
            return nil unless AnilLanRework.connected?
            locked = remote_manual_lock?
            if locked || remote_message_active?
              started = Time.now.to_f
              absolute_deadline = started + (effective_timeout * 2.0) if absolute_deadline
              window.text = remote_message_active? ? "Aguardando sincronização de diálogos..." : manual_wait_text if window
            end

            if anil_freeze_patch_wait_timed_out?(started, effective_timeout, absolute_deadline)
              anil_freeze_patch_log_pvp_wait(
                "pvp wait turn hash timeout",
                "expected_turn=#{expected_turn} pending_hashes=#{@active_context&.pending_turn_hashes&.length || 0} absolute=#{Time.now.to_f >= absolute_deadline}"
              )
              return nil
            end
            update_battle_graphics(@active_context) rescue nil
            Input.update rescue nil
            window.update rescue nil
          end
        end
      ensure
        dispose_wait_window(viewport, window)
      end

      def wait_for_remote_switch(expected_slot = nil)
        return nil if coop_remote_sync_disabled?
        started = Time.now.to_f
        base_text = wait_text_for_remote_switch rescue "Aguardando troca..."
        viewport, window = build_wait_window(base_text)
        begin
          with_battle_wait do
            loop do
              pump_network
              return nil if @active_context && @active_context.instance_variable_get(:@anil_battle_end_received) == true
              flush_remote_party_refresh
              packet = next_remote_switch(expected_slot)
              return packet if packet
              return nil unless AnilLanRework.connected?

              if remote_manual_lock?
                started = Time.now.to_f
                if window
                  w_text = remote_message_active? ? "Aguardando diálogo do parceiro..." : manual_wait_text
                  window.text = w_text if window.text != w_text
                end
              elsif window && window.text != base_text
                window.text = base_text
              end

              return nil if Time.now.to_f - started >= AnilLanRework::TURN_TIMEOUT
              update_battle_graphics(@active_context) rescue nil
              Input.update rescue nil
              window.update rescue nil if window
            end
          end
        ensure
          dispose_wait_window(viewport, window) if window
        end
      end

      def flush_remote_status_events_safe
        ctx = @active_context
        battle = ctx && ctx.battle
        return unless ctx && battle
        return if !ctx.pending_status_events || ctx.pending_status_events.empty?
        until ctx.pending_status_events.empty?
          packet = ctx.pending_status_events.shift
          if packet.is_a?(Hash) && (packet["battlers"] || packet["positions"] || packet["sides"] || packet["field"])
            apply_remote_status_snapshot(battle, packet)
          else
            apply_legacy_remote_status_packet(battle, packet)
          end
        end
        ctx.pending_party_refresh = true
      end

      def flush_remote_status_events
        anil_freeze_patch_original_flush_remote_status_events
      end
    end
  end
end

module AnilLanRework
  module BattleSync
    class << self
      alias anil_freeze_patch_original_pump_network pump_network unless method_defined?(:anil_freeze_patch_original_pump_network)

      def pump_network
        return unless AnilLanRework.connected?
        AnilLanRework.connection.tick
        AnilLanRework.connection.drain { |packet| AnilLanRework::Router.route_packet(packet) }
        consume_remote_text_steps
        consume_remote_text_states
        if AnilLanRework.in_battle_wait?
          flush_remote_status_events_safe
        else
          flush_remote_status_events
        end
      end
    end
  end
end



if defined?(Battle)
  class Battle
    alias anil_phase_probe_original_pbCommandPhase pbCommandPhase unless method_defined?(:anil_phase_probe_original_pbCommandPhase)
    alias anil_phase_probe_original_pbAttackPhase pbAttackPhase unless method_defined?(:anil_phase_probe_original_pbAttackPhase)
    alias anil_phase_probe_original_pbEndOfRoundPhase pbEndOfRoundPhase unless method_defined?(:anil_phase_probe_original_pbEndOfRoundPhase)
    alias anil_phase_probe_original_pbEORSwitch pbEORSwitch unless method_defined?(:anil_phase_probe_original_pbEORSwitch)
    alias anil_phase_probe_original_pbSwitchInBetween pbSwitchInBetween unless method_defined?(:anil_phase_probe_original_pbSwitchInBetween)
    alias anil_phase_probe_original_pbGetReplacementPokemonIndex pbGetReplacementPokemonIndex unless method_defined?(:anil_phase_probe_original_pbGetReplacementPokemonIndex)
    alias anil_phase_probe_original_pbJudge pbJudge unless method_defined?(:anil_phase_probe_original_pbJudge)

    def anil_phase_probe_ctx
      AnilLanRework::BattleSync.active_context rescue nil
    end

    def anil_phase_probe_pvp?
      ctx = anil_phase_probe_ctx
      ctx && ctx.mode == :pvp
    rescue
      false
    end

    def anil_phase_probe_battlers
      @battlers.compact.map do |b|
        name = (b.pokemon&.name || b.name rescue "?").to_s
        status = (b.status || :NONE).to_s rescue "NONE"
        fainted = b.fainted? rescue false
        "#{b.index}:#{name}:#{b.hp}/#{b.totalhp}:#{status}:#{fainted ? 'KO' : 'UP'}"
      end.join(" | ")
    rescue
      "battlers=unavailable"
    end

    def anil_phase_probe_log(label, extra = nil)
      ctx = anil_phase_probe_ctx
      return unless ctx && ctx.mode == :pvp
      turn = self.turnCount.to_i rescue 0
      decision = @decision rescue nil
      suffix = extra.to_s
      suffix = " #{suffix}" unless suffix.empty?
      AnilLanRework.log(
        "#{label} battle_id=#{ctx.battle_id} client_index=#{ctx.client_index} turn=#{turn} decision=#{decision.inspect}#{suffix}"
      )
    rescue => e
      AnilLanRework.log("phase probe log error #{e.class}: #{e.message}")
    end

    def pbCommandPhase(*args)
      anil_phase_probe_log("pvp phase enter pbCommandPhase", "battlers=#{anil_phase_probe_battlers}") if anil_phase_probe_pvp?
      if anil_phase_probe_pvp?
        # Wrap the entire command phase in a manual lock to prevent the remote
        # peer from timing out while the local player is choosing moves.
        AnilLanRework::BattleSync.with_manual_lock("command_phase") do
          anil_phase_probe_original_pbCommandPhase(*args)
        end
      else
        anil_phase_probe_original_pbCommandPhase(*args)
      end
      anil_phase_probe_log("pvp phase exit pbCommandPhase", "battlers=#{anil_phase_probe_battlers}") if anil_phase_probe_pvp?
    end

    def pbAttackPhase(*args)
      ctx = AnilLanRework::BattleSync.active_context rescue nil
      if ctx && ctx.mode == :pvp && AnilLanRework.connected?
        AnilLanRework::BattleSync.sync_pvp_turn_bundle(self, "attack_phase_gate")
      end
      anil_phase_probe_log("pvp phase enter pbAttackPhase", "battlers=#{anil_phase_probe_battlers}") if anil_phase_probe_pvp?
      result = anil_phase_probe_original_pbAttackPhase(*args)
      anil_phase_probe_log("pvp phase exit pbAttackPhase", "battlers=#{anil_phase_probe_battlers}") if anil_phase_probe_pvp?
      result
    end

    def pbEndOfRoundPhase(*args)
      anil_phase_probe_log("pvp phase enter pbEndOfRoundPhase", "battlers=#{anil_phase_probe_battlers}") if anil_phase_probe_pvp?
      result = anil_phase_probe_original_pbEndOfRoundPhase(*args)
      
      # SYNC FIELD STATE AFTER END OF ROUND
      begin
        ctx = AnilLanRework::BattleSync.active_context rescue nil
        if ctx && [:pvp, :coop].include?(ctx.mode) && AnilLanRework.connected?
          AnilLanRework::BattleSync.sync_field_state(self)
        end
      rescue => e
        AnilLanRework.log("pbEndOfRoundPhase field sync error #{e.class}: #{e.message}")
      end

      anil_phase_probe_log("pvp phase exit pbEndOfRoundPhase", "battlers=#{anil_phase_probe_battlers}") if anil_phase_probe_pvp?
      result
    end

    def pbEORSwitch(favorDraws = false)
      anil_phase_probe_log(
        "pvp phase enter pbEORSwitch",
        "favorDraws=#{favorDraws ? true : false} battlers=#{anil_phase_probe_battlers}"
      ) if anil_phase_probe_pvp?
      result = anil_phase_probe_original_pbEORSwitch(favorDraws)
      anil_phase_probe_log("pvp phase exit pbEORSwitch", "battlers=#{anil_phase_probe_battlers}") if anil_phase_probe_pvp?
      result
    end

    def pbSwitchInBetween(idxBattler, checkLaxOnly = false, canCancel = false)
      anil_phase_probe_log(
        "pvp switch enter pbSwitchInBetween",
        "idxBattler=#{idxBattler} checkLaxOnly=#{checkLaxOnly ? true : false} canCancel=#{canCancel ? true : false}"
      ) if anil_phase_probe_pvp?
      if anil_phase_probe_pvp? && pbOwnedByPlayer?(idxBattler)
        # Prevent the remote peer from timing out while we are in the party menu.
        result = AnilLanRework::BattleSync.with_manual_lock("switch_prompt") do
          anil_phase_probe_original_pbSwitchInBetween(idxBattler, checkLaxOnly, canCancel)
        end
      else
        result = anil_phase_probe_original_pbSwitchInBetween(idxBattler, checkLaxOnly, canCancel)
      end
      anil_phase_probe_log(
        "pvp switch exit pbSwitchInBetween",
        "idxBattler=#{idxBattler} result=#{result.inspect}"
      ) if anil_phase_probe_pvp?
      result
    end

    def pbGetReplacementPokemonIndex(idxBattler, random = false)
      anil_phase_probe_log(
        "pvp switch enter pbGetReplacementPokemonIndex",
        "idxBattler=#{idxBattler} random=#{random ? true : false}"
      ) if anil_phase_probe_pvp?
      result = anil_phase_probe_original_pbGetReplacementPokemonIndex(idxBattler, random)
      anil_phase_probe_log(
        "pvp switch exit pbGetReplacementPokemonIndex",
        "idxBattler=#{idxBattler} random=#{random ? true : false} result=#{result.inspect}"
      ) if anil_phase_probe_pvp?
      result
    end

    def pbJudge(*args)
      anil_phase_probe_log("pvp judge enter pbJudge", "battlers=#{anil_phase_probe_battlers}") if anil_phase_probe_pvp?
      result = anil_phase_probe_original_pbJudge(*args)
      anil_phase_probe_log("pvp judge exit pbJudge", "battlers=#{anil_phase_probe_battlers}") if anil_phase_probe_pvp?
      result
    end
  end
end



module AnilLanRework
  module BattleSync
    class << self
      alias anil_freeze_patch_original_sync_message_step sync_message_step unless method_defined?(:anil_freeze_patch_original_sync_message_step)

      def sync_message_step(message = nil)
        ctx = @active_context
        return message unless ctx && [:pvp, :coop].include?(ctx.mode) && AnilLanRework.connected?
        consume_remote_text_steps(ctx)
        ctx.local_text_step = ctx.local_text_step.to_i + 1
        local_step = ctx.local_text_step.to_i
        normalized_message = normalize_text_step_message(message)
        AnilLanRework.connection.send_packet("battle_text_step",
          "to_id"     => ctx.partner_id,
          "battle_id" => ctx.battle_id,
          "step"      => local_step,
          "message"   => message.to_s,
          "msg_key"   => normalized_message
        )
        minimum_remote_step = local_step - text_lead_limit(ctx)
        return message if minimum_remote_step <= 0
        return message if ctx.remote_text_step.to_i >= minimum_remote_step
        started = Time.now.to_f
        effective_timeout = [AnilLanRework::LAN_BATTLE_TEXT_SYNC_TIMEOUT.to_f, 3.0].min
        with_battle_wait do
          while ctx.remote_text_step.to_i < minimum_remote_step
            break unless AnilLanRework.connected?
            break if Time.now.to_f - started >= effective_timeout
            pump_network
            flush_remote_status_events_safe
            consume_remote_text_steps(ctx)
            Graphics.update rescue nil
            Input.update rescue nil
          end
        end
        remote_packet = ctx.remote_text_packets[local_step] rescue nil
        resolved_message = message
        if remote_packet
          remote_key = remote_packet["msg_key"].to_s
          remote_message = remote_packet["message"].to_s
          if !normalized_message.empty? && !remote_key.empty? && remote_key != normalized_message
            if ctx.mode == :coop && !authoritative_text_sender?(ctx) && !remote_message.empty?
              resolved_message = remote_message
            end
          end
        end
        resolved_message
      rescue => e
        AnilLanRework.log("battle text sync error #{e.class}: #{e.message}")
        message
      end
    end
    module_function :wait_for_remote_hp_event
  end
end

AnilLanRework.log("AnilLanRework_BattleFreezePatch loaded OK")


if defined?(AnilLanRework::BattleSync)
  module AnilLanRework
    module BattleSync
      class << self
        unless method_defined?(:_unified_orig_start_pvp)
          alias _unified_orig_start_pvp start_pvp_battle
        end

        def start_pvp_battle(*args)
          # Limpa partner residual antes de PvP
          if defined?($PokemonGlobal) && $PokemonGlobal
            if $PokemonGlobal.respond_to?(:partner) && $PokemonGlobal.partner
              AnilLanRework.log(
                "unified_fix: clearing stale partner before PvP — " +
                "was: " + $PokemonGlobal.partner.inspect.to_s[0, 80]
              )
              $PokemonGlobal.partner = nil
            end
          end
          _unified_orig_start_pvp(*args)
        end
      end
    end
  end
end

if defined?(Battle)
  class Battle
    unless method_defined?(:_unified_orig_init) || private_method_defined?(:_unified_orig_init)
      alias _unified_orig_init initialize
    end

    def initialize(scene, p1, p2, player, opponent)
      ctx = (AnilLanRework::BattleSync.active_context rescue nil)

      if ctx && ctx.mode == :pvp
        # Forca limpeza de partner global
        if defined?($PokemonGlobal) && $PokemonGlobal
          $PokemonGlobal.partner = nil if $PokemonGlobal.respond_to?(:partner=)
        end
        
        # Limita a array de trainers do jogador a 1 para PvP 1v1
        if player.is_a?(Array)
          if player.length > 1
             AnilLanRework.log("unified_fix: trimming player array to 1")
             player = [player[0]]
          end
        end
      end

      _unified_orig_init(scene, p1, p2, player, opponent)

      # Correcao para erro de animacao (ballTracksHand / nil:NilClass)
      # Garante que trainers remotos tenham dados basicos para o motor de animacao
      if @player && @player.is_a?(Array)
        @player.each_with_index do |trainer, i|
          next unless trainer
          trainer.id = 0 if trainer.respond_to?(:id) && trainer.id.nil?
          # ForÃ§a um ID temporário para evitar o erro de NilClass na animação
          if i > 0 && trainer.respond_to?(:id) && (trainer.id == 0 || trainer.id.nil?)
            trainer.id = $player.id rescue 0
          end
        end
      end
    end

    # pbRandom override removed to prevent RNG desync during transitions; using standard modular RNG instead.
  end
end

# --- VACINA CONTRA CRASH DE ANIMACAO (ballTracksHand) ---
module Battle::Scene::Animation::BallAnimationMixin
  alias _unified_orig_ballTracksHand ballTracksHand unless method_defined?(:_unified_orig_ballTracksHand)
  def ballTracksHand(ball, traSprite, safariThrow = false)
    # Se o sprite ou o bitmap forem nulos, cancelamos a animacao complexa para evitar crash
    if !traSprite || !traSprite.bitmap || traSprite.bitmap.disposed?
      return traSprite ? traSprite.x : 0, traSprite ? traSprite.y : 0
    end
    return _unified_orig_ballTracksHand(ball, traSprite, safariThrow)
  end
end


# ------------------------------------------------------------------------------
# FIX 2: BATALHA 1V1 QUANDO PARCEIRO RECUSA COOP
#
# CAUSA: Quando parceiro recusa convite de batalha coop selvagem,
# $PokemonGlobal.partner nao e limpo e a batalha ainda inclui os
# pokemon dele na party, forcando double encounter.
#
# CORRECAO: Ao receber recusa, setar flag force_single_wild e limpar
# $PokemonGlobal.partner. Bloquear start_coop_battle se recusou.
# ------------------------------------------------------------------------------

module AnilLanRework
  @_unified_force_single_wild = false

  class << self
    def force_single_wild!
      @_unified_force_single_wild = true
      log("unified_fix: force_single_wild flag SET (partner declined)")
    end

    def force_single_wild?
      @_unified_force_single_wild == true
    end

    def reset_force_single_wild!
      @_unified_force_single_wild = false
    end
  end
end

if defined?(AnilLanRework::BattleSync)
  module AnilLanRework
    module BattleSync
      class << self
        # Intercepta recusa de batalha
        if method_defined?(:receive_battle_decline) &&
           !method_defined?(:_unified_orig_recv_decline)
          alias _unified_orig_recv_decline receive_battle_decline
          def receive_battle_decline(packet)
            battle_id = (packet["battle_id"].to_s rescue "unknown")
            AnilLanRework.log(
              "unified_fix: battle decline received — battle_id=#{battle_id}"
            )
            AnilLanRework.force_single_wild!
            if defined?($PokemonGlobal) && $PokemonGlobal
              $PokemonGlobal.partner = nil if $PokemonGlobal.respond_to?(:partner=)
            end
            _unified_orig_recv_decline(packet)
          end
        end

        if method_defined?(:handle_battle_decline) &&
           !method_defined?(:_unified_orig_handle_decline)
          alias _unified_orig_handle_decline handle_battle_decline
          def handle_battle_decline(packet)
            AnilLanRework.log("unified_fix: handle_battle_decline — forcing single")
            AnilLanRework.force_single_wild!
            if defined?($PokemonGlobal) && $PokemonGlobal
              $PokemonGlobal.partner = nil if $PokemonGlobal.respond_to?(:partner=)
            end
            _unified_orig_handle_decline(packet)
          end
        end

        # Bloqueia coop se parceiro recusou
        if method_defined?(:start_coop_battle) &&
           !method_defined?(:_unified_orig_start_coop)
          alias _unified_orig_start_coop start_coop_battle
          def start_coop_battle(*args)
            if AnilLanRework.force_single_wild?
              AnilLanRework.log(
                "unified_fix: start_coop_battle BLOCKED — " +
                "partner declined, falling back to solo 1v1"
              )
              AnilLanRework.reset_force_single_wild!
              if defined?($PokemonGlobal) && $PokemonGlobal
                $PokemonGlobal.partner = nil if $PokemonGlobal.respond_to?(:partner=)
              end
              return false
            end
            _unified_orig_start_coop(*args)
          end
        end
      end
    end
  end
end


# ------------------------------------------------------------------------------
# FIX 3: POKEMON SELVAGEM DUPLO — CHANCE CORRIGIDA PARA 5%
#
# CAUSA: O codigo forca double wild incondicionalmente quando multiplayer
# esta conectado, ignorando MULTIPLAYER_DOUBLE_WILD_CHANCE = 5 (5%).
#
# CORRECAO: Interceptar pbDoubleWildBattle para checar rand(100) < 5.
# Se falhar, faz fallback para pbWildBattle single.
# Se parceiro recusou, NUNCA double (1v1 puro).
# ------------------------------------------------------------------------------

module AnilLanRework
  class << self
    def should_double_wild?
      return false if force_single_wild?
      return false unless connected?
      return false if pbInSafari? rescue false
      return false if $game_temp&.force_single_battle
      return false if $PokemonGlobal&.battlingSpawnedPokemon
      return false if $player.able_pokemon_count <= 1
      peer = AnilLanRework::BattleSync.partner_on_same_map rescue nil
      return false unless peer

      chance = (MULTIPLAYER_DOUBLE_WILD_CHANCE rescue 5).to_i.clamp(0, 100)
      roll = rand(100)
      result = roll < chance

      log("unified_fix: double wild check — roll=#{roll} chance=#{chance}% result=#{result}")
      result
    end
  end
end

if defined?(pbDoubleWildBattle)
  alias _unified_orig_dbl_wild pbDoubleWildBattle unless defined?(_unified_orig_dbl_wild)

  def pbDoubleWildBattle(species1, level1, species2, level2, *args)
    if AnilLanRework.connected?
      if AnilLanRework.force_single_wild?
        AnilLanRework.log(
          "unified_fix: double wild -> single (partner declined)"
        )
        AnilLanRework.reset_force_single_wild!
        return pbWildBattle(species1, level1)
      end

      unless AnilLanRework.should_double_wild?
        AnilLanRework.log(
          "unified_fix: double wild -> single (5% check failed, species=#{species1})"
        )
        return pbWildBattle(species1, level1)
      end

      AnilLanRework.log(
        "unified_fix: double wild APPROVED — #{species1} Lv#{level1} + #{species2} Lv#{level2}"
      )
    end

    _unified_orig_dbl_wild(species1, level1, species2, level2, *args)
  end
end

if defined?(pbWildBattle) && !defined?($unified_wild_patched)
  $unified_wild_patched = true
  alias _unified_orig_wild pbWildBattle

  def pbWildBattle(species, level, *args)
    if AnilLanRework.connected?
      AnilLanRework.reset_force_single_wild! if AnilLanRework.force_single_wild?

      ctx = (AnilLanRework::BattleSync.active_context rescue nil)
      if !ctx || ctx.mode != :coop
        if defined?($PokemonGlobal) && $PokemonGlobal
          if $PokemonGlobal.respond_to?(:partner) && $PokemonGlobal.partner
            is_story = ($PokemonGlobal.partner[4] == false)
            if !is_story && defined?(AnilLanRework::BattleSync)
              is_story = AnilLanRework::BattleSync.is_story_partner?($PokemonGlobal.partner) rescue false
            end
            unless is_story
              AnilLanRework.log("unified_fix: clearing partner in solo wild battle")
              $PokemonGlobal.partner = nil
            end
          end
        end
      end
    end

    decision = _unified_orig_wild(species, level, *args)

    # Intercepta captura bem sucedida para quest de NPCs (agora controlado via menu pbStorePokemon)
    # Anteriormente auto-completava ao capturar qualquer pokemon da rota.

    return decision
  end
end


# ------------------------------------------------------------------------------
# FIX 4: BALAO DE OCUPADO EM JOGADORES REMOTOS
#
# CAUSA: busy=true ja era transmitido nos pacotes player_state mas
# NENHUM indicador visual aparecia no mapa. A constante
# REMOTE_BUSY_BALLOON_COOLDOWN existia sem implementacao.
#
# CORRECAO: Sprite de balao "..." animado sobre jogadores remotos com
# busy=true. Garante build_player_state envia busy corretamente.
# ------------------------------------------------------------------------------


# Garante que busy reflete estado real do jogador
if defined?(AnilLanRework)
  module AnilLanRework
    class << self
      if method_defined?(:build_player_state)
        unless method_defined?(:_unified_orig_build_state)
          alias _unified_orig_build_state build_player_state
        end

        def build_player_state
          state = _unified_orig_build_state
          if state.is_a?(Hash)
            is_busy = false
            if defined?($game_temp) && $game_temp
              is_busy = true if $game_temp.respond_to?(:in_battle) && $game_temp.in_battle
              is_busy = true if $game_temp.respond_to?(:in_menu) && ($game_temp.in_menu rescue false)
              is_busy = true if $game_temp.respond_to?(:message_window_showing) && $game_temp.message_window_showing
            end
            is_busy = true if !is_busy && (pbMapInterpreterRunning? rescue false)
            state["busy"] = is_busy
          end
          state
        end
      end
    end
  end
end

#===============================================================================
# Fix: Canonical Targeting RNG Desynchronization in Co-op
#===============================================================================
if defined?(Battle)
  class Battle::Battler
    def anil_rework_canonical_index
      idx = self.index
      ctx = AnilLanRework::BattleSync.active_context rescue nil
      if ctx && ctx.mode == :coop && ctx.client_index.to_i == 1
        return 2 if idx == 0
        return 0 if idx == 2
      end
      idx
    end

    # Sincronização de Ditto / Imposter em Co-op
    alias anil_pvp_sync_pbTransform pbTransform unless method_defined?(:anil_pvp_sync_pbTransform)
    def pbTransform(target)
      anil_pvp_sync_pbTransform(target)
      ctx = AnilLanRework::BattleSync.active_context rescue nil
      if ctx && ctx.mode == :coop
        AnilLanRework.log("coop: transforming battler index=#{@index} into target=#{target.index}")
        # Envia snapshot imediatamente para garantir que ambos vejam a mesma forma
        AnilLanRework::BattleSync.send_battle_status_snapshot rescue nil
      end
    end


    alias anil_rework_canonical_pbChangeTargets pbChangeTargets unless method_defined?(:anil_rework_canonical_pbChangeTargets)
    def pbChangeTargets(*args)
      result = anil_rework_canonical_pbChangeTargets(*args)
      if result && result.is_a?(Array)
        ctx = AnilLanRework::BattleSync.active_context rescue nil
        if ctx && ctx.mode == :coop
          result.sort_by! { |b| b.anil_rework_canonical_index }
        end
      end
      result
    end
  end

  class Battle
    alias anil_rework_canonical_allBattlers allBattlers unless method_defined?(:anil_rework_canonical_allBattlers)
    def allBattlers
      result = anil_rework_canonical_allBattlers
      ctx = AnilLanRework::BattleSync.active_context rescue nil
      if ctx && ctx.mode == :coop
        result.sort_by! { |b| b.anil_rework_canonical_index }
      end
      result
    end

    alias anil_rework_canonical_allSameSideBattlers allSameSideBattlers unless method_defined?(:anil_rework_canonical_allSameSideBattlers)
    def allSameSideBattlers(*args)
      result = anil_rework_canonical_allSameSideBattlers(*args)
      ctx = AnilLanRework::BattleSync.active_context rescue nil
      if ctx && ctx.mode == :coop
        result.sort_by! { |b| b.anil_rework_canonical_index }
      end
      result
    end

    alias anil_rework_canonical_allOtherSideBattlers allOtherSideBattlers unless method_defined?(:anil_rework_canonical_allOtherSideBattlers)
    def allOtherSideBattlers(*args)
      result = anil_rework_canonical_allOtherSideBattlers(*args)
      ctx = AnilLanRework::BattleSync.active_context rescue nil
      if ctx && ctx.mode == :coop
        result.sort_by! { |b| b.anil_rework_canonical_index }
      end
      result
    end

    alias anil_rework_canonical_pbCalculatePriority pbCalculatePriority unless method_defined?(:anil_rework_canonical_pbCalculatePriority)
    def pbCalculatePriority(*args)
      anil_rework_canonical_pbCalculatePriority(*args)
    end
  end
end

# Log final
if defined?(AnilLanRework)
  AnilLanRework.log(
    "unified_fix: all fixes loaded OK + " +
    "pvp_desync, double_wild_5pct, coop_decline_1v1, busy_balloon, canonical_rng_sync"
  )
end

# Sincronização de Diálogos de Batalha (pbMessage)
alias anil_rework_original_pbMessageDisplay pbMessageDisplay unless defined?(anil_rework_original_pbMessageDisplay)
def pbMessageDisplay(msgwindow, message, letterbyletter = true, commandProc = nil, &block)
  was_active = AnilLanRework.message_active rescue false
  AnilLanRework.message_active = true if defined?(AnilLanRework)
  begin
    anil_rework_original_pbMessageDisplay(msgwindow, message, letterbyletter, commandProc, &block)
  ensure
    AnilLanRework.message_active = was_active if defined?(AnilLanRework)
  end
end

# Estabilização de Mega Evolução e MecÃ¢nicas Especiais
class Battle
  alias anil_rework_original_pbMegaEvolve pbMegaEvolve unless method_defined?(:anil_rework_original_pbMegaEvolve)
  def pbMegaEvolve(idxBattler)
    anil_rework_original_pbMegaEvolve(idxBattler)
    if defined?(AnilLanRework) && AnilLanRework::BattleSync.online_battle_scene_sync?(self)
      AnilLanRework.log("Mega Evolution sync point reached battler=#{idxBattler}")
      # Pequeno delay para garantir que a animação terminou em ambos os lados
      AnilLanRework::BattleSync.pump_network
    end
  end

  # Correção de Engine: Garante que os arrays de times tenham o tamanho correto, mesmo se um time não tiver Pokémon aptos.
  alias anil_rework_original_pbAbleTeamCounts pbAbleTeamCounts unless method_defined?(:anil_rework_original_pbAbleTeamCounts)
  def pbAbleTeamCounts(side)
    counts = anil_rework_original_pbAbleTeamCounts(side)
    expected_teams = pbPartyStarts(side).length
    while counts.length < expected_teams
      counts.push(0)
    end
    counts
  end
end

class PokemonEncounters
  if method_defined?(:have_double_wild_battle_on_tile?)
    alias anil_rework_original_have_double_wild_battle_on_tile? have_double_wild_battle_on_tile? unless method_defined?(:anil_rework_original_have_double_wild_battle_on_tile?)

    def have_double_wild_battle_on_tile?(x, y, map_id)
      return false if $game_temp.force_single_battle
      return false if pbInSafari?
      if $PokemonGlobal.partner
        # Check if it is a story/quest partner
        # Safe access using respond_to? and checking if index is valid
        is_story = true
        if $PokemonGlobal.partner.respond_to?(:[])
          is_story = ($PokemonGlobal.partner[4] == false || $PokemonGlobal.partner[4].nil?)
        end
        if !is_story
          if defined?(AnilLanRework) && AnilLanRework.connected?
            is_story = AnilLanRework::BattleSync.is_story_partner?($PokemonGlobal.partner) rescue false
          else
            is_story = true
          end
        end
        if is_story
          return rand(100) < 5
        end

        # If it's a multiplayer coop partner:
        if defined?(AnilLanRework) && AnilLanRework.connected?
          peer = AnilLanRework::BattleSync.partner_on_same_map rescue nil
          return false unless peer
          return false if AnilLanRework.force_single_wild?
          return false if $player.able_pokemon_count <= 1
          return rand(100) < (AnilLanRework::MULTIPLAYER_DOUBLE_WILD_CHANCE rescue 5)
        end

        # Default fallback for any other partner
        return true
      end

      # Original logic for non-partner double wild battles (e.g. double grass/terrain)
      return false if $player.able_pokemon_count <= 1
      terrainTag = nil
      if $map_factory
        if $map_factory.respond_to?(:get_terrain_tag)
          terrainTag = $map_factory.get_terrain_tag(map_id, x, y)
        elsif $map_factory.respond_to?(:getTerrainTag)
          terrainTag = $map_factory.getTerrainTag(map_id, x, y)
        end
      end
      if !terrainTag && defined?($game_map) && $game_map
        terrainTag = $game_map.terrain_tag(x, y)
      end
      if terrainTag && terrainTag.respond_to?(:double_wild_encounters) && terrainTag.double_wild_encounters
        return rand(100) < 30
      end
      return false
    end
  end
end

class Game_Follower < Game_Event
  def move_fancy(direction)
    move_through(direction)
  end

  def jump_fancy(direction, leader)
    delta_x = (direction == 6) ? 2 : (direction == 4) ? -2 : 0
    delta_y = (direction == 2) ? 2 : (direction == 8) ? -2 : 0
    if leader.jumping?
      self.jump_speed = leader.jump_speed || 3
    else
      self.jump_speed = leader.move_speed || 3
      @jump_time /= 2 rescue nil
    end
    jump(delta_x, delta_y)
  end
end

if defined?(Battle::Scene::BattlerSprite)
  class Battle::Scene::BattlerSprite
    alias anil_lock_sprite_update update unless method_defined?(:anil_lock_sprite_update)
    def update
      anil_lock_sprite_update
      if animated?
        # Setting to nil first and then back to itself forces the C++ binding
        # of Sprite#bitmap= to actually reload/refresh the texture,
        # bypassing the same-object check in MKXP.
        bmp = self.bitmap
        self.bitmap = nil
        self.bitmap = bmp
      end
    end
  end
end

class Player
  def outfit
    @outfit || 0
  end

  def online_id
    if $PokemonGlobal && $PokemonGlobal.respond_to?(:online_id)
      return $PokemonGlobal.online_id.to_s
    end
    return ""
  end

  def online_id=(val)
    if $PokemonGlobal
      if !$PokemonGlobal.respond_to?(:online_id)
        class << $PokemonGlobal
          attr_accessor :online_id
        end
      end
      $PokemonGlobal.online_id = val.to_s
    end
  end
end

class PokemonSummary_Scene
  attr_accessor :remote_view
  attr_accessor :peer_owner_name

  alias patch_remote_pbMoveSelection pbMoveSelection unless method_defined?(:patch_remote_pbMoveSelection)
  def pbMoveSelection
    return if @remote_view
    patch_remote_pbMoveSelection
  end

  alias patch_remote_pbRibbonSelection pbRibbonSelection unless method_defined?(:patch_remote_pbRibbonSelection)
  def pbRibbonSelection
    return if @remote_view
    patch_remote_pbRibbonSelection
  end

  alias patch_remote_pbOptions pbOptions unless method_defined?(:patch_remote_pbOptions)
  def pbOptions
    return false if @remote_view
    patch_remote_pbOptions
  end
end

class PokemonSummaryScreen
  attr_accessor :remote_view
end

#===============================================================================
# MOD: Correção de visualização da Party e transição limpa para o Multi Save
#===============================================================================

class PokemonPartyScreen
  alias anil_coop_initialize initialize unless method_defined?(:anil_coop_initialize)
  def initialize(scene, party)
    ctx = AnilLanRework::BattleSync.active_context rescue nil
    if ctx && ctx.mode == :coop && ctx.battle
      battle = ctx.battle
      if battle.respond_to?(:party1starts) && battle.party1starts && battle.party1starts[1]
        start_idx = battle.party1starts[1].to_i
        party = party[0...start_idx] if party.length > start_idx
      end
    end
    anil_coop_initialize(scene, party)
  end
end

class DP_PauseMenu
  alias anil_coop_exit_initialize initialize unless method_defined?(:anil_coop_exit_initialize)
  def initialize(*args)
    anil_coop_exit_initialize(*args)
    exit_option = @options.find { |opt| opt[0] == "Salir" || opt[0] == _INTL("Salir") }
    if exit_option
      exit_option[3] = proc {
        if pbConfirmMessage(_INTL("¿Estás segur\\@ de que quieres volver a la pantalla de título?"))
          @done = true
          @sprites.visible = false
          $game_temp.in_menu = false
          
          # Salvar jogo
          scene = PokemonSave_Scene.new
          screen = PokemonSaveScreen.new(scene)
          screen.pbSaveScreen(true)
          
          # Fade out total para preto e mantém preto
          pbFadeOutAndHide(@sprites) rescue nil
          
          # Dispor recursos e descarregar
          $scene.dispose rescue nil
          SaveData.mark_values_as_unloaded if defined?(SaveData.mark_values_as_unloaded)
          pbBGMFade(1.0) rescue nil
          pbBGSFade(1.0) rescue nil
          
          # Desconectar multiplayer de forma limpa e intencional
          if defined?(AnilLanRework)
            AnilLanRework.intentional_disconnect = true rescue nil
            AnilLanRework.disconnect(true) rescue nil
          end
          
          # Ir direto para a cena de multisave
          $scene = pbCallTitle
        end
      }
    end
  end
end

module PluginManager
  class << self
    alias anil_coop_exit_runPlugins runPlugins unless method_defined?(:anil_coop_exit_runPlugins)
    def runPlugins(*args)
      anil_coop_exit_runPlugins(*args)
      
      # Garante a redefinição global do pbCallTitle após todos os plugins carregarem
      Object.class_eval do
        def pbCallTitle
          begin
            if defined?(AnilLanRework)
              AnilLanRework.disconnect rescue nil
              AnilLanRework.multiplayer_mode = false rescue nil
              AnilLanRework.online_session_active = false rescue nil
            end
          rescue
          end
          # Desativa a flag de save online no objeto global existente para evitar redirecionamento indevido
          if $PokemonGlobal
            $PokemonGlobal.is_multiplayer_online_save = false rescue nil
            $PokemonGlobal.is_verified_online_save = false rescue nil
          end
          begin
            pbFadeOutAndHide(Hash.new) rescue nil
            Graphics.freeze rescue nil
          rescue
          end
          if $DEBUG && defined?(Settings::SHOW_TITLE_SCREEN_ON_DEBUG) && !Settings::SHOW_TITLE_SCREEN_ON_DEBUG
            return Scene_DebugIntro.new
          else
            return Scene_Intro.new
          end
        end
      end
    end
  end
end


