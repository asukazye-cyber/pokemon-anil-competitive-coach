#===============================================================================
# MOD: 099_Anti_Black_Screen (v7 — intercept ALL freeze/transition no JoiPlay)
#-------------------------------------------------------------------------------
# CAUSA RAIZ REAL (v7):
#   No JoiPlay/Android, a cena de intro faz seu próprio Graphics.freeze +
#   Graphics.transition internamente. O segundo freeze() captura o frame sujo
#   que ainda estava no pipeline do driver gráfico Android.
#
# SOLUÇÃO v7:
#   - Graphics.freeze sobrescrito GLOBALMENTE: enquanto $antighost_blackout
#     estiver true, pinta a tela de preto a cada chamada de freeze.
#   - Graphics.transition sobrescrito: se $antighost_blackout true, roda com
#     duração 0 (transição instantânea do preto) para não revelar frame sujo.
#   - $antighost_blackout só é desligado DEPOIS que a cena de título/intro
#     terminar seu primeiro ciclo de update — momento seguro.
#   - Redução de prioridade de tiles e tilemap.update mantidos.
#===============================================================================

def antighost_log(msg)
  return unless (anil_diagnostico_ligado? rescue false)
  puts "[AntiGhost] #{msg}"
  paths = []
  if defined?(System) && System.respond_to?(:data_directory) && System.data_directory
    paths << File.join(System.data_directory, "antighost_log.txt")
  end
  paths << "antighost_log.txt"
  paths.each do |path|
    begin
      File.open(path, "a") { |f| f.puts("[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] #{msg}") }
      break
    rescue; end
  end
end

begin
  paths = []
  if defined?(System) && System.respond_to?(:data_directory) && System.data_directory
    paths << File.join(System.data_directory, "antighost_log.txt")
  end
  paths << "antighost_log.txt"
  paths.each { |path| File.delete(path) rescue nil }
rescue; end

antighost_log("Carregando 099_Anti_Black_Screen v7...")

#===============================================================================
# DETECTA JOIPLAY
#===============================================================================
def antighost_joiplay?
  return $antighost_is_joiplay unless $antighost_is_joiplay.nil?
  $antighost_is_joiplay = begin
    (defined?($joiplay) && $joiplay) ||
    ENV['ANDROID_ROOT'] || ENV['ANDROID_DATA'] ||
    File.exist?("/system/app") ||
    (defined?(System) && System.platform.to_s =~ /android/i)
  rescue; false
  end ? true : false
end

#===============================================================================
# FLAGS GLOBAIS
#===============================================================================
$antighost_pending_load_refresh = false
$antighost_exiting_to_title     = false
$antighost_is_joiplay           = nil
$antighost_save_blackout_flushed= false

# Flag principal v7: enquanto true, TODO freeze pinta preto primeiro
# e todo transition roda com duração 0
$antighost_blackout             = false

# Viewport/Sprite do blackout — recriados a cada freeze interceptado
$antighost_blackout_viewport    = nil
$antighost_blackout_sprite      = nil
$antighost_quit_viewport        = nil
$antighost_quit_sprite          = nil

#===============================================================================
# HELPER: pinta a tela de preto e faz flush para a GPU commitar
#===============================================================================
def antighost_paint_black_and_flush!(flush_count = nil)
  # Se já existe o sprite e ele é válido, não recria nem faz o flush longo novamente
  if $antighost_blackout_sprite && !$antighost_blackout_sprite.disposed?
    antighost_log("paint_black: sprite já existe e está ativo, pulando recriação/flush.")
    return
  end

  # Limpa viewport anterior se existir
  begin
    $antighost_blackout_sprite&.bitmap&.dispose rescue nil
    $antighost_blackout_sprite&.dispose rescue nil
    $antighost_blackout_viewport&.dispose rescue nil
  rescue; end
  $antighost_blackout_sprite   = nil
  $antighost_blackout_viewport = nil

  begin
    vp = Viewport.new(0, 0, Graphics.width, Graphics.height)
    vp.z = 2_147_483_647  # z máximo possível
    sp = Sprite.new(vp)
    sp.bitmap = Bitmap.new(Graphics.width, Graphics.height)
    sp.bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(0, 0, 0, 255))
    $antighost_blackout_viewport = vp
    $antighost_blackout_sprite   = sp
  rescue => e
    antighost_log("paint_black erro: #{e.message}")
    return
  end

  # Realiza um Heavy Refresh (limpeza profunda de cache GPU e coleta de lixo de memória)
  begin
    RPG::Cache.clear rescue nil
    GC.start rescue nil
  rescue => e
    antighost_log("Heavy refresh erro: #{e.message}")
  end

  # Flush: reduzido para 12 frames para evitar congelamentos e ANR
  default_flush = 12
  flush = flush_count || default_flush

  antighost_log("paint_black: flush #{flush} frames (JoiPlay=#{antighost_joiplay?})")
  flush.times { Graphics.update rescue nil }
end

#===============================================================================
# HELPER: descarta o blackout sprite (sem afetar o freeze que já capturou preto)
#===============================================================================
def antighost_dispose_blackout_sprite!
  begin
    $antighost_blackout_sprite&.bitmap&.dispose rescue nil
    $antighost_blackout_sprite&.dispose rescue nil
    $antighost_blackout_viewport&.dispose rescue nil
  rescue; end
  $antighost_blackout_sprite   = nil
  $antighost_blackout_viewport = nil
end

#===============================================================================
# HELPER: cria o overlay preto persistente global
#===============================================================================
def antighost_create_persistent_black_overlay!
  antighost_log("antighost_create_persistent_black_overlay! ativado")
  begin
    $antighost_quit_sprite&.bitmap&.dispose rescue nil
    $antighost_quit_sprite&.dispose rescue nil
    $antighost_quit_viewport&.dispose rescue nil
  rescue; end

  begin
    $antighost_quit_viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    $antighost_quit_viewport.z = 999999
    $antighost_quit_sprite = Sprite.new($antighost_quit_viewport)
    $antighost_quit_sprite.bitmap = Bitmap.new(Graphics.width, Graphics.height)
    $antighost_quit_sprite.bitmap.fill_all(Color.new(0, 0, 0, 255))
  rescue => e
    antighost_log("Erro ao criar overlay persistente: #{e.message}")
  end
end

#===============================================================================
# HOOK GLOBAL: Graphics.freeze
#
# Toda chamada a freeze() enquanto $antighost_blackout == true vai:
#   1. Pintar preto + flush antes de capturar
#   2. Deixar o freeze capturar o preto
#   3. Descartar o sprite (o frame capturado já é preto)
#===============================================================================
class << Graphics
  alias antighost_original_freeze freeze unless method_defined?(:antighost_original_freeze)

  def freeze
    if $antighost_blackout || $antighost_exiting_to_title
      antighost_log("Graphics.freeze interceptado (blackout/exit) — pintando preto...")
      antighost_paint_black_and_flush!
      result = antighost_original_freeze
      antighost_dispose_blackout_sprite!
      antighost_log("Graphics.freeze: capturou frame preto.")
      result
    else
      if defined?(antighost_joiplay?) && antighost_joiplay?
        antighost_log("Graphics.freeze: JoiPlay detectado, executando flush preventivo...")
        6.times { Graphics.update rescue nil }
      end
      antighost_original_freeze
    end
  end
end

#===============================================================================
# HOOK GLOBAL: Graphics.transition
#
# Enquanto $antighost_blackout == true, força duração 0 para não revelar
# nenhum frame sujo — a transição começa e termina do preto instantaneamente.
# Após a primeira transition limpa o blackout (a cena de título está rodando).
#===============================================================================
class << Graphics
  alias antighost_original_transition transition unless method_defined?(:antighost_original_transition)

  def transition(duration = 8, filename = "", vague = 40)
    if $antighost_blackout
      antighost_log("Graphics.transition interceptado — blackout ativo, forçando duração 0")
      $antighost_blackout = false
      $antighost_save_blackout_flushed = false
      antighost_dispose_blackout_sprite!
      antighost_log("blackout desligado — cena de título iniciando")
      antighost_original_transition(0)
    else
      antighost_original_transition(duration, filename, vague)
    end
  end
end

#===============================================================================
# FUNÇÃO PÚBLICA: ativa o blackout (chamada antes de mudar de cena)
#===============================================================================
def antighost_start_blackout!(flush_count = nil)
  antighost_log("antighost_start_blackout! ativado (flush=#{flush_count})")
  $antighost_blackout         = true
  $antighost_exiting_to_title = true
  # Já pinta preto agora para garantir que qualquer update subsequente seja preto
  antighost_paint_black_and_flush!(flush_count)
end

#===============================================================================
# FUNÇÃO PÚBLICA: desativa blackout manualmente (fallback)
#===============================================================================
def antighost_stop_blackout!
  return unless $antighost_blackout
  antighost_log("antighost_stop_blackout! chamado manualmente")
  $antighost_blackout         = false
  $antighost_exiting_to_title = false
  antighost_dispose_blackout_sprite!
end

#===============================================================================
# 🔧 Fix: Tilemap.update forçado no Spriteset_Map (ghost de tiles)
#===============================================================================
class Spriteset_Map
  alias ghost_fix_update update unless method_defined?(:ghost_fix_update)
  def update
    ghost_fix_update
    @tilemap.update if @tilemap
  end
end

#===============================================================================
# 🔧 Fix: Reduz prioridade de tiles >= 5 (ghost de copas/telhados)
#===============================================================================
class Game_Map
  alias antighost_updateTileset updateTileset unless method_defined?(:antighost_updateTileset)
  def updateTileset
    antighost_updateTileset
    if @priorities
      @priorities.xsize.times { |i| @priorities[i] = 1 if @priorities[i] >= 5 }
    end
  end
end

#===============================================================================
# PATCH: AnilLanRework.force_main_title!
# Agora usa antighost_start_blackout! que intercepta TODOS os freezes futuros
#===============================================================================
if defined?(AnilLanRework)
  module AnilLanRework
    class << self
      alias antighost_original_force_main_title force_main_title! rescue nil

      def force_main_title!(overlay_file, message)
        antighost_log("force_main_title! v8: desconectando e iniciando blackout global...")

        # 1. Desconecta do servidor imediatamente para parar threads e fechar sockets
        if defined?(AnilLanRework) && AnilLanRework.respond_to?(:disconnect)
          AnilLanRework.disconnect(false) rescue nil
        end

        # 2. Intervalo curto para processar buffers e liberar threads (10 frames)
        10.times do
          Graphics.update rescue nil
          Input.update rescue nil
        end

        # 3. Ativa blackout — a partir daqui todo freeze captura preto
        antighost_start_blackout!

        # 4. Prepara estado visual do multiplayer
        AnilAntiBlackScreen.prepare_server_disconnect! rescue nil

        # 4.5. Descarta o sprite do blackout temporário para revelar o overlay de aviso
        antighost_dispose_blackout_sprite! rescue nil

        # 5. Exibe overlay de aviso com loop isolado (sem pbMessage)
        show_image_overlay(overlay_file, message, force_title: true) rescue nil

        # 6. Flags pós-desconexão
        $anil_abs_pending_fix     = true
        $anil_abs_post_disconnect = true
        SaveData.mark_values_as_unloaded if defined?(SaveData.mark_values_as_unloaded)

        # 7. Muda para o título — o freeze interno da nova cena vai capturar preto
        $scene = pbCallTitle
      end
    end
  end
  antighost_log("AnilLanRework.force_main_title! patcheado (v7).")
end

#===============================================================================
# HOOK: Game.load
#===============================================================================
module Game
  class << self
    alias antighost_load load unless method_defined?(:antighost_load)
    def load(save_data)
      antighost_log("Game.load: limpando cache antes do load...")
      RPG::Cache.clear rescue nil
      result = antighost_load(save_data)
      antighost_log("Game.load: limpando cache pós-load...")
      RPG::Cache.clear rescue nil
      $antighost_pending_load_refresh = true
      result
    end
  end
end

#===============================================================================
# HOOK: Scene_Map
#===============================================================================
class Scene_Map
  alias antighost_original_createSpritesets createSpritesets unless method_defined?(:antighost_original_createSpritesets)
  alias antighost_original_update           update           unless method_defined?(:antighost_original_update)
  alias antighost_original_dispose          dispose          unless method_defined?(:antighost_original_dispose)

  def createSpritesets
    if $antighost_pending_load_refresh
      $antighost_pending_load_refresh = false
      antighost_log("createSpritesets: refresh pós-load...")

      RPG::Cache.clear rescue nil

      @antighost_viewport = Viewport.new(0, 0, Graphics.width, Graphics.height) rescue nil
      if @antighost_viewport
        @antighost_viewport.z = 999999
        @antighost_sprite = Sprite.new(@antighost_viewport) rescue nil
        if @antighost_sprite
          bmp = Bitmap.new(Graphics.width, Graphics.height) rescue nil
          if bmp
            bmp.fill_all(Color.new(0, 0, 0, 255)) rescue nil
            @antighost_sprite.bitmap = bmp
          end
        end
      end

      antighost_original_createSpritesets
      @antighost_timer = 200

      if defined?(AnilLanRework)
        AnilLanRework.request_map_graphics_refresh!("load_game", 3)
        AnilLanRework.schedule_delayed_map_refresh!("load_game_patch", 1.0, 3)
      else
        disposeSpritesets rescue nil
        if @spritesetGlobal
          @spritesetGlobal.dispose rescue nil
          @spritesetGlobal = nil
        end
        antighost_original_createSpritesets rescue nil
      end
    else
      antighost_original_createSpritesets
    end
  end

  def update
    antighost_original_update
    if @antighost_timer && @antighost_timer > 0
      @antighost_timer -= 1
      if @antighost_sprite
        @antighost_sprite.opacity = @antighost_timer <= 30 ? (@antighost_timer * 8.5).round : 255
      end
      antighost_cleanup_load_overlay if @antighost_timer == 0
    end

    # ── WATCHDOG anti tela-preta-travada ─────────────────────────────────
    # $antighost_blackout só é desligado dentro do override de Graphics.transition.
    # Se alguma exceção for engolida (rescue nil) antes desse transition rodar,
    # a flag fica travada em true pra sempre. Aqui, se já estamos dentro do
    # Scene_Map#update normalmente, é seguro revelar a tela depois de uma margem.
    if $antighost_blackout
      @antighost_blackout_watchdog = (@antighost_blackout_watchdog || 0) + 1
      if @antighost_blackout_watchdog > 120  # ~2s a 60fps
        antighost_log("WATCHDOG: $antighost_blackout travado — forçando reset.")
        antighost_stop_blackout! rescue nil
        @antighost_blackout_watchdog = 0
      end
    else
      @antighost_blackout_watchdog = 0
    end
  end

  def dispose
    antighost_cleanup_load_overlay

    if $antighost_exiting_to_title
      antighost_log("Scene_Map#dispose: exiting to title detected. Creating persistent black overlay...")
      
      # Clean up any existing persistent overlay first
      begin
        $antighost_quit_sprite&.bitmap&.dispose rescue nil
        $antighost_quit_sprite&.dispose rescue nil
        $antighost_quit_viewport&.dispose rescue nil
      rescue; end

      # Create persistent black overlay using global variables
      begin
        $antighost_quit_viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
        $antighost_quit_viewport.z = 999999
        $antighost_quit_sprite = Sprite.new($antighost_quit_viewport)
        $antighost_quit_sprite.bitmap = Bitmap.new(Graphics.width, Graphics.height)
        $antighost_quit_sprite.bitmap.fill_all(Color.new(0, 0, 0, 255))
      rescue => e
        antighost_log("Scene_Map#dispose error creating overlay: #{e.message}")
      end

      # Graphics.update x3 BEFORE disposing spritesets
      3.times { Graphics.update rescue nil }

      # Now dispose map spritesets
      antighost_original_dispose
    else
      antighost_original_dispose
    end
  end

  def antighost_cleanup_load_overlay
    if @antighost_sprite
      @antighost_sprite.bitmap.dispose rescue nil if @antighost_sprite.bitmap
      @antighost_sprite.dispose rescue nil
      @antighost_sprite = nil
    end
    if @antighost_viewport
      @antighost_viewport.dispose rescue nil
      @antighost_viewport = nil
    end
  end
end
#===============================================================================
# HELPER: aplica hooks com segurança em classes de Plugins (após carregamento)
#===============================================================================
def antighost_apply_plugin_hooks!

  if defined?(DP_PauseMenu)
    antighost_log("Aplicando hook em DP_PauseMenu pós-carregamento de plugins...")
    DP_PauseMenu.class_eval do
      alias_method :antighost_dp_initialize, :initialize unless method_defined?(:antighost_dp_initialize)
      def initialize(*args)
        antighost_dp_initialize(*args)
        exit_option = @options.find { |opt| opt[0] == "Salir" || opt[0] == _INTL("Salir") }
        if exit_option
          exit_option[3] = proc {
            if pbConfirmMessage(_INTL("¿Estás segur\@ de que quieres volver a la pantalla de título?"))
              antighost_log("DP_PauseMenu Salir: confirmado. Iniciando desconexão e blackout...")
              
              # 1. Desconectar do multiplayer de forma limpa e intencional
              if defined?(AnilLanRework)
                AnilLanRework.intentional_disconnect = true rescue nil
                AnilLanRework.disconnect(true) rescue nil
              end
              
              @done = true
              @sprites.visible = false
              $game_temp.in_menu = false
              
              # 2. Salvar jogo
              scene = PokemonSave_Scene.new
              screen = PokemonSaveScreen.new(scene)
              screen.pbSaveScreen(true)
              
              # 3. Ativa blackout (pinta tela de preto e inicia transição instantânea)
              antighost_start_blackout!
              
              # 4. Fade out total para preto e mantém preto
              pbFadeOutAndHide(@sprites) rescue nil
              
              # 5. Dispor recursos e descarregar
              $scene.dispose rescue nil
              SaveData.mark_values_as_unloaded if defined?(SaveData.mark_values_as_unloaded)
              pbBGMFade(1.0) rescue nil
              pbBGSFade(1.0) rescue nil
              
              # 6. Ir direto para a cena de título (o pbCallTitle interceptado fará o blackout)
              $scene = pbCallTitle
            end
          }
        end
      end
    end
    antighost_log("DP_PauseMenu patcheado com sucesso pós-carregamento de plugins.")
  end
end

#===============================================================================
# HOOKS NOS MENUS DE SAÍDA — ativam blackout antes de sair
#===============================================================================

if defined?(MenuHandlers)
  antighost_log("Interceptando MenuHandlers :quit_game...")
  MenuHandlers.add(:pause_menu, :quit_game, {
    "name"  => proc { _INTL("Cerrar Juego") },
    "order" => 90,
    "effect" => proc { |menu|
      menu.pbHideMenu
      if pbConfirmMessage(_INTL("¿Estás segur{1} de que quieres cerrar el juego?", $player.female? ? 'a' : 'o'))
        scene  = PokemonSave_Scene.new
        screen = PokemonSaveScreen.new(scene)
        screen.pbSaveScreen
        antighost_log("quit_game: ativando blackout...")
        antighost_start_blackout!
        $scene = nil
        menu.pbEndScene
        next true
      end
      menu.pbRefresh
      menu.pbShowMenu
      next false
    }
  })
end

#===============================================================================
# HOOK: pbCallTitle — ativa blackout ao chamar o título
#===============================================================================
def antighost_hook_pbCallTitle!(force = false)
  return if $antighost_pbCallTitle_hooked && !force
  antighost_log("Hook pbCallTitle (force=#{force})...")
  Object.class_eval do
    remove_method(:antighost_original_pbCallTitle) rescue nil
    alias antighost_original_pbCallTitle pbCallTitle rescue nil
    def pbCallTitle(*args)
      if $antighost_exiting_to_title || $antighost_blackout
        antighost_log("pbCallTitle: ativando blackout...")
        antighost_start_blackout!
      else
        antighost_log("pbCallTitle: boot inicial, pulando blackout...")
      end
      defined?(antighost_original_pbCallTitle) ? antighost_original_pbCallTitle(*args) :
        ($DEBUG && defined?(Settings::SHOW_TITLE_SCREEN_ON_DEBUG) && !Settings::SHOW_TITLE_SCREEN_ON_DEBUG ?
          Scene_DebugIntro.new : Scene_Intro.new)
    end
  end
  $antighost_pbCallTitle_hooked = true
end

def antighost_safely_hook_main(klass, alias_name)
  antighost_log("Hook main em #{klass}...")
  klass.class_eval do
    remove_method(alias_name) rescue nil
    alias_method alias_name, :main rescue nil
    define_method(:main) do |*args|
      if $antighost_exiting_to_title
        $antighost_exiting_to_title = false
        antighost_log("main em #{self.class}: limpando overlay persistente...")
        begin
          $antighost_quit_sprite&.bitmap&.dispose rescue nil
          $antighost_quit_sprite&.dispose rescue nil
          $antighost_quit_viewport&.dispose rescue nil
        rescue; end
        $antighost_quit_sprite = nil
        $antighost_quit_viewport = nil
      end
      respond_to?(alias_name) ? send(alias_name, *args) : nil
    end
  end
end

def antighost_apply_all_hooks!(force = false)
  antighost_log("antighost_apply_all_hooks! (force=#{force})")
  antighost_hook_pbCallTitle!(force)
  antighost_safely_hook_main(Scene_DebugIntro, :antighost_debug_intro_main) if defined?(Scene_DebugIntro)
  antighost_safely_hook_main(Scene_Intro,      :antighost_intro_main)       if defined?(Scene_Intro)
end

antighost_apply_all_hooks!(false)
antighost_apply_plugin_hooks! rescue nil

if defined?(PluginManager)
  module PluginManager
    class << self
      alias antighost_runPlugins runPlugins unless method_defined?(:antighost_runPlugins)
      def runPlugins(*args)
        antighost_runPlugins(*args)
        antighost_apply_all_hooks!(true)
        antighost_apply_plugin_hooks! rescue nil
      end
    end
  end
end

antighost_log("099_Anti_Black_Screen v7 carregado.")