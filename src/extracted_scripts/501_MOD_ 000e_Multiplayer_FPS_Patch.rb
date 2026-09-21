# encoding: UTF-8
#===============================================================================
# AnilLanRework — FPS Patch
# Coloque este arquivo APÓS o script principal (0449_Multiplayer_Anil.rb)
# no Plugin Manager ou editor de scripts.
#
# Corrige as 5 causas principais de queda de FPS no modo multiplayer:
#
#  FIX 1 — Router.tick: guard de frame movido para o INÍCIO do método,
#           eliminando execuções repetidas de I/O de rede no mesmo frame.
#
#  FIX 2 — Graphics.update override: processamento de rede fora da
#           Scene_Map reduzido a read_packets + flush_batch leves,
#           sem chamar Router.tick completo (que já roda via Scene_Map#update).
#
#  FIX 3 — Spriteset_Map#update: loop de peers throttled a cada 2 frames
#           via guard de frame, sem alterar lógica de sprite.
#
#  FIX 4 — WorldSync.build_snapshot: snapshot full de switches reduzido
#           de revision % 20 para revision % 60 no host.
#
#  FIX 5 — WorldSync.capture_switches_delta: remove rescue por iteração
#           dentro do loop de 500 switches (overhead silencioso alto).
#===============================================================================

# ==============================================================================
# PROFILER & DIAGNOSTICS HUD
# ==============================================================================
class AnilProfilerHUD
  def initialize
    width = 220
    height = 135
    x = Graphics.width - width - 10 rescue 10
    y = 45
    
    @viewport = Viewport.new(x, y, width, height)
    @viewport.z = 999999
    
    @sprite = Sprite.new(@viewport)
    @sprite.bitmap = Bitmap.new(width, height)
    
    @font_name = MessageConfig::FONT_NAME rescue Font.default_name
    
    draw_hud
  end

  def draw_hud
    return if @sprite.disposed?
    
    bitmap = @sprite.bitmap
    bitmap.clear
    
    # Semitransparent background
    bitmap.fill_rect(0, 0, bitmap.width, bitmap.height, Color.new(10, 15, 25, 210))
    
    # Sleek dark blue / neon blue borders
    bitmap.fill_rect(0, 0, bitmap.width, 2, Color.new(0, 230, 255, 255))
    bitmap.fill_rect(0, bitmap.height - 2, bitmap.width, 2, Color.new(0, 230, 255, 255))
    bitmap.fill_rect(0, 0, 2, bitmap.height, Color.new(0, 230, 255, 255))
    bitmap.fill_rect(bitmap.width - 2, 0, 2, bitmap.height, Color.new(0, 230, 255, 255))
    
    bitmap.font.name = @font_name
    bitmap.font.size = 14
    bitmap.font.bold = true
    bitmap.font.color = Color.new(0, 230, 255)
    bitmap.font.out_color = Color.new(0, 0, 0)
    
    bitmap.draw_text(6, 4, bitmap.width - 12, 18, "DIAGNÓSTICO ONLINE", 1)
    
    bitmap.font.size = 13
    
    fps = AnilProfiler.fps
    frame_t = AnilProfiler.frame_time
    scenemap_t = AnilProfiler.scenemap_time
    net_t = AnilProfiler.network_time
    peer_t = AnilProfiler.peer_render_time
    spawns_t = AnilProfiler.spawns_time

    draw_stat(bitmap, 6, 24, "FPS:", "#{fps}", color_for_fps(fps))
    draw_stat(bitmap, 6, 42, "Total Frame:", sprintf("%.2f ms", frame_t), color_for_time(frame_t, 16.6))
    draw_stat(bitmap, 6, 60, "Scene_Map:", sprintf("%.2f ms", scenemap_t), color_for_time(scenemap_t, 8.0))
    draw_stat(bitmap, 6, 78, "Rede (Router):", sprintf("%.2f ms", net_t), color_for_time(net_t, 4.0))
    draw_stat(bitmap, 6, 96, "Peers (Render):", sprintf("%.2f ms", peer_t), color_for_time(peer_t, 4.0))
    draw_stat(bitmap, 6, 114, "Spawns (VOE):", sprintf("%.2f ms", spawns_t), color_for_time(spawns_t, 4.0))
  end

  def draw_stat(bitmap, x, y, label, value, val_color)
    bitmap.font.color = Color.new(200, 200, 200)
    bitmap.draw_text(x, y, bitmap.width - 12, 16, label, 0)
    bitmap.font.color = val_color
    bitmap.draw_text(x, y, bitmap.width - 12 - 6, 16, value, 2)
  end

  def color_for_fps(fps)
    if fps >= 55
      Color.new(50, 255, 50)
    elsif fps >= 40
      Color.new(255, 255, 50)
    else
      Color.new(255, 50, 50)
    end
  end

  def color_for_time(ms, threshold)
    if ms <= threshold
      Color.new(150, 255, 150)
    elsif ms <= threshold * 2
      Color.new(255, 255, 150)
    else
      Color.new(255, 150, 150)
    end
  end

  def update
    return if @sprite.disposed?
    if !$scene.is_a?(Scene_Map)
      @sprite.visible = false if @sprite.visible
      return
    else
      @sprite.visible = true if !@sprite.visible
    end
    draw_hud
  end

  def dispose
    @sprite.bitmap.dispose if @sprite.bitmap && !@sprite.bitmap.disposed?
    @sprite.dispose if @sprite && !@sprite.disposed?
    @viewport.dispose if @viewport && !@viewport.disposed?
  end
end

module AnilProfiler
  @enabled = false
  @hud = nil

  @frame_start = 0.0
  @frame_time = 0.0
  @fps = 0.0
  
  @scenemap_start = 0.0
  @scenemap_time = 0.0
  
  @network_start = 0.0
  @network_time = 0.0
  
  @peer_render_start = 0.0
  @peer_render_time = 0.0
  
  @spawns_time_accumulator = 0.0
  @spawns_time = 0.0

  @frame_times_buf = []
  @scenemap_times_buf = []
  @network_times_buf = []
  @peer_render_times_buf = []
  @spawns_times_buf = []
  
  @fps_frames = 0
  @fps_last_time = nil

  class << self
    attr_accessor :enabled
    attr_reader :fps, :frame_time, :scenemap_time, :network_time, :peer_render_time, :spawns_time

    def toggle
      @enabled = !@enabled
      if @enabled
        @hud ||= AnilProfilerHUD.new rescue nil
      else
        @hud&.dispose rescue nil
        @hud = nil
      end
    end

    def start_frame
      now = System.uptime
      @frame_start = now
      @fps_last_time ||= now
      @fps_frames += 1
      if now - @fps_last_time >= 1.0
        @fps = (@fps_frames.to_f / (now - @fps_last_time)).round(1)
        @fps_frames = 0
        @fps_last_time = now
      end
      @spawns_time_accumulator = 0.0
    end

    def end_frame
      return unless @frame_start > 0
      t = (System.uptime - @frame_start) * 1000.0
      add_metric(t, @frame_times_buf)
      @frame_time = average(@frame_times_buf)
      
      add_metric(@spawns_time_accumulator * 1000.0, @spawns_times_buf)
      @spawns_time = average(@spawns_times_buf)

      if @enabled
        if !$scene.is_a?(Scene_Map)
          if @hud
            @hud.dispose rescue nil
            @hud = nil
          end
        else
          @hud ||= AnilProfilerHUD.new rescue nil
          @hud.update if @hud && (Graphics.frame_count % 5 == 0)
        end
      else
        if @hud
          @hud.dispose rescue nil
          @hud = nil
        end
      end
    end

    def start_scenemap
      @scenemap_start = System.uptime
    end

    def end_scenemap
      return unless @scenemap_start > 0
      t = (System.uptime - @scenemap_start) * 1000.0
      add_metric(t, @scenemap_times_buf)
      @scenemap_time = average(@scenemap_times_buf)
    end

    def start_network
      @network_start = System.uptime
    end

    def end_network
      return unless @network_start > 0
      t = (System.uptime - @network_start) * 1000.0
      add_metric(t, @network_times_buf)
      @network_time = average(@network_times_buf)
    end

    def start_peer_render
      @peer_render_start = System.uptime
    end

    def end_peer_render
      return unless @peer_render_start > 0
      t = (System.uptime - @peer_render_start) * 1000.0
      add_metric(t, @peer_render_times_buf)
      @peer_render_time = average(@peer_render_times_buf)
    end

    def accumulate_spawn_time(start_t)
      @spawns_time_accumulator += (System.uptime - start_t) rescue 0.0
    end

    private

    def add_metric(val, buf)
      buf << val
      buf.shift if buf.size > 30
    end

    def average(buf)
      return 0.0 if buf.empty?
      buf.inject(0.0) { |sum, x| sum + x } / buf.size
    end
  end
end

# ==============================================================================
# FIX 1 — Router.tick: guard de frame no INÍCIO
# ==============================================================================
module AnilLanRework
  def self.multiplayer_map?(map_id = nil)
    map_id ||= ($game_map ? $game_map.map_id : 0)
    return false if map_id <= 0
    # Mapas de introdução/novo jogo são estritamente singleplayer
    return false if map_id == 1 || map_id == 104 || map_id == 29
    true
  end

  def self.alone_on_map?
    return true if !defined?(AnilLanRework) || !AnilLanRework.connected?
    current_map_id = $game_map ? $game_map.map_id : -1
    # Se houver qualquer outro jogador no mesmo mapa, não está sozinho
    AnilLanRework.players.each do |peer_id, peer|
      next if peer_id.to_s == AnilLanRework.self_internal_id.to_s
      return false if peer.map_id == current_map_id
    end
    true
  end

  module Router
    def self.tick
      start_t = (defined?(AnilProfiler) && AnilProfiler.enabled) ? System.uptime : nil
      AnilProfiler.start_network if start_t
      begin
        return unless AnilLanRework.connected?

        # ----------------------------------------------------------------
        # Guard de frame PRIMEIRO — evita múltiplas execuções de I/O no
        # mesmo frame (Graphics.update é chamado N vezes por frame em
        # menus, animações e batalhas, e cada chamada disparava tick).
        # ----------------------------------------------------------------
        current_frame = Graphics.frame_count
        return if current_frame == @last_tick_frame
        @last_tick_frame = current_frame

        # Bloqueante de map_ID no cliente
        if $game_map && !AnilLanRework.multiplayer_map?($game_map.map_id)
          return
        end

        AnilLanRework.update_active_time rescue nil

        # Previne timeout falso dos jogadores em pausas longas (ex: menus)
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

        # Desativada restauração de coordenadas via servidor para evitar descompassos e personagem sumindo
        # if AnilLanRework.pending_restore_coords
        #   coords = AnilLanRework.pending_restore_coords
        #   AnilLanRework.pending_restore_coords = nil
        #   AnilLanRework.apply_coordinate_restore!(coords) rescue nil
        # end

        AnilLanRework.connection.tick

        # Controle dinâmico/inteligente de envio de posição para evitar lag I/O e pbResolveBitmap
        map_changed = (@last_sent_map_id != $game_map.map_id rescue true)
        # ⚠️ CADENCIA POR FRAMES CASTIGA QUEM TEM MENOS FRAMES.
        #
        # "De 4 em 4 frames" sao 67 ms a 60 fps — e 133 ms no JoiPlay, que corre
        # a metade disso. Quem joga no telemovel mandava metade dos pacotes e
        # via o dobro do atraso, sem que nada disso aparecesse no ping. Medir em
        # segundos trata os dois aparelhos por igual.
        #
        # E num duelo manda-se ao dobro: 33 ms. Sao ~30 pacotes por segundo para
        # DOIS jogadores, o que nao pesa em servidor nenhum, e e o que permite
        # baixar o buffer de interpolacao para 70 ms (ver o MOD 136).
        agora_envio = Time.now.to_f
        intervalo_envio = if (AnilArena.activa? rescue false)
                            0.033
                          elsif AnilLanRework.alone_on_map?
                            1.0
                          else
                            0.067
                          end
        na_hora = (agora_envio - @ultimo_envio_seg.to_f) >= intervalo_envio
        
        if !AnilLanRework::WorldSync.input_locked? &&
           (map_changed || na_hora) &&
           current_frame - AnilLanRework.last_battle_end_frame > 60
          @ultimo_envio_seg = agora_envio
          @last_player_send = current_frame
          @last_sent_map_id = $game_map.map_id
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
      ensure
        AnilProfiler.end_network if start_t
      end
    end
  end
end

# ==============================================================================
# FIX 2 — Graphics.update: rede leve fora de Scene_Map
# ==============================================================================
module PluginManager
  class << self
    alias anil_rework_runPlugins runPlugins unless method_defined?(:anil_rework_runPlugins)
    def runPlugins
      anil_rework_runPlugins
      
      # Após o carregamento de todos os plugins, podemos envolver com segurança o Graphics.update final:
      class << Graphics
        alias final_plugin_graphics_update update unless method_defined?(:final_plugin_graphics_update)
        
        def update
          if defined?(AnilProfiler)
            AnilProfiler.start_frame
          end
          begin
            $anil_channel_hud.update rescue nil if $anil_channel_hud
            $anil_map_name_hud.update rescue nil if $anil_map_name_hud
            $anil_partner_hud.update rescue nil if $anil_partner_hud
            
            # ----------------------------------------------------------------
            # APP RESUME DETECTION (Anti-Background-Freeze)
            # ----------------------------------------------------------------
            now_real = Time.now.to_f
            @anil_last_update_time ||= now_real
            gap = now_real - @anil_last_update_time
            @anil_last_update_time = now_real

            if gap > 2.0 && !@anil_processing_resume
              @anil_processing_resume = true
              begin
                AnilLanRework.log("[RESUME] App retornou do segundo plano! gap=#{gap.round(1)}s") rescue nil
                Graphics.frame_reset rescue nil
                if AnilLanRework.respond_to?(:enabled?) && AnilLanRework.enabled?
                  conn = AnilLanRework.connection rescue nil
                  if conn
                    if conn.connected?
                      begin
                        conn.send_packet("ping")
                        conn.flush_batch
                        conn.read_packets rescue nil
                        AnilLanRework.log("[RESUME] Conexão verificada - socket OK")
                      rescue => e
                        AnilLanRework.log("[RESUME] Socket morto durante background: #{e.message}")
                        conn.disconnect rescue nil
                      end
                    end
                    if !conn.connected? && AnilLanRework.respond_to?(:multiplayer_mode) && AnilLanRework.multiplayer_mode
                      AnilLanRework.log("[RESUME] Conexão perdida durante background - watchdog vai tratar")
                    end
                  end
                end
                if AnilLanRework.connected?
                  AnilLanRework.instance_variable_set(:@resume_grace_until, now_real + 3.0) rescue nil
                end
              rescue => e
                AnilLanRework.log("[RESUME] Erro no handler de resume: #{e.class}: #{e.message}") rescue nil
              ensure
                @anil_processing_resume = false
              end
            end

            # ----------------------------------------------------------------
            # Mensagens de desconexão pendentes
            # ----------------------------------------------------------------
            if $game_temp && $game_temp.respond_to?(:anil_pending_disconnect_msg) && $game_temp.anil_pending_disconnect_msg && !@anil_processing_disconnect
              @anil_processing_disconnect = true
              msg = $game_temp.anil_pending_disconnect_msg
              $game_temp.anil_pending_disconnect_msg = nil
              begin
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

            # ----------------------------------------------------------------
            # Watchdog de conexão online (reconexão automática em segundo plano)
            # ----------------------------------------------------------------
            if defined?(AnilLanRework) && AnilLanRework.respond_to?(:update_connection_watchdog)
              cf = Graphics.frame_count rescue 0
              @anil_watchdog_frame ||= -1
              if cf != @anil_watchdog_frame
                @anil_watchdog_frame = cf
                AnilLanRework.update_connection_watchdog($scene)
              end
            end

            # ----------------------------------------------------------------
            # Processamento de Rede do Multiplayer (Menus, Batalhas, etc.)
            # ----------------------------------------------------------------
            if defined?(AnilLanRework) && AnilLanRework.enabled? && AnilLanRework.connected?
              is_scene_map = $scene.is_a?(Scene_Map) && !($game_temp && $game_temp.respond_to?(:in_menu) && $game_temp.in_menu)
              
              if is_scene_map
                # Scene_Map ativa cuida de rodar o Router.tick completo a cada frame.
                # No Graphics.update fazemos apenas a leitura de pacotes leve se necessário.
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
              elsif ($game_map && $game_map.map_id > 0 && $game_player rescue false)
                # Em jogo (Menus, Batalhas, etc.), mas fora de Scene_Map:
                # Precisamos rodar o Router.tick para processar eventos e sync de rede.
                if @anil_rework_updating
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
                    AnilLanRework::BattleSync.update_pending_coop_invite rescue nil
                  rescue => e
                    AnilLanRework.log("graphics network update error #{e.class}: #{e.message}")
                  ensure
                    @anil_rework_updating = false
                  end
                end
              end
            end

            # Atualiza animações e posições do mapa/multiplayer durante menus em Scene_Map
            if defined?(AnilLanRework) && AnilLanRework.enabled? && AnilLanRework.connected?
              if $scene.is_a?(Scene_Map) && $game_temp && $game_temp.respond_to?(:in_menu) && $game_temp.in_menu
                $scene.updateSpritesets rescue nil
              end
            end

            final_plugin_graphics_update
          ensure
            if defined?(AnilProfiler)
              AnilProfiler.end_frame
            end
          end
        end
      end
    end
  end
end

# ==============================================================================
# Otimizações na classe RemotePeer (Evitar NoMethodError e Early Return)
# ==============================================================================
class AnilLanRework::RemotePeer
  # Acima disto nao e movimento real: entrada no mapa, teleporte, ou perda
  # longa de ligacao. 15 tiles sao ~0,7s a correr, muito acima de lag normal.
  TELEPORTE_TILES = 15 unless const_defined?(:TELEPORTE_TILES)
  # Previne exceptions de NoMethodError na chamada silenciosa do seguidor remoto
  def calculate_bush_depth
  end

  # Evita processamento e conversões de float caso o peer já esteja na posição alvo
  # Delega para o MOD 136, dono unico da movimentacao remota.
  #
  # ⚠️ Existe outra definicao deste metodo no 000e_FPS_Patch, que carrega DEPOIS
  # e sobrepoe esta. As duas delegam para o mesmo sitio de proposito: assim
  # tanto faz qual vence, e nao ha como corrigir uma e esquecer a outra — que ja
  # aconteceu e deu build que compila sem mudar nada em jogo.
  def update_anim
    AnilMovimentoRemoto.aplicar!(self)
  end
end

# ==============================================================================
# FIX 3 — Spriteset_Map#update: culling de distância e throttling do loop de peers
# ==============================================================================
class Spriteset_Map
  # NÃO reaproveitar "anil_rework_update": esse nome já foi usado pelo MOD 000
  # (script 450) para guardar o update ORIGINAL, antes do MOD 047 (nuvens)
  # sequer existir. Usar remove_method + esse apelido antigo decapitava a
  # cadeia de patches e fazia o update das nuvens nunca mais rodar.
  alias anil_fps_pre_update update unless method_defined?(:anil_fps_pre_update)

  def update
    anil_fps_pre_update

    # Inicializa hashes preventivamente para evitar NoMethodError
    @anil_rework_remote_sprites ||= {}
    @anil_rework_remote_followers ||= {}
    @anil_rework_peer_busy_effects ||= {}
    @anil_rework_peer_busy_snapshot ||= {}
    @anil_rework_peer_map_snapshot ||= {}
    @anil_rework_peer_visibility_snapshot ||= {}
    @anil_rework_peer_busy_blink_timers ||= {}
    @anil_rework_peer_busy_blink_phases ||= {}
    @anil_rework_peer_visible_cache ||= {}
    @anil_rework_peer_visible_tick ||= {}
    @anil_rework_peer_busy_balloon_type ||= {}
    @anil_rework_peer_busy_balloon_frame ||= {}
    @anil_rework_peer_busy_balloon_ticks ||= {}
    @anil_rework_peer_busy_balloon_state ||= {}

    return unless AnilLanRework.enabled? && AnilLanRework.connected? && $game_map
    return unless @map.map_id == $game_map.map_id
    return unless AnilLanRework.multiplayer_map?($game_map.map_id)

    if $game_temp && $game_temp.respond_to?(:in_menu) && $game_temp.in_menu
      File.open("menu_debug.txt", "a") { |f| f.puts("[Spriteset_Map.update] in_menu=true, players_count=#{AnilLanRework.players.length}, frame=#{Graphics.frame_count}") rescue nil }
    end
    cf = Graphics.frame_count rescue 0
    @anil_peer_sprite_frame ||= -1
    return if cf == @anil_peer_sprite_frame
    @anil_peer_sprite_frame = cf

    viewport = @viewport1 rescue nil
    viewport ||= Spriteset_Map.viewport rescue nil
    return unless viewport

    subpixels_x = (Game_Map::X_SUBPIXELS rescue 4)
    current_map_id = $game_map.map_id

    start_peer_t = (defined?(AnilProfiler) && AnilProfiler.enabled) ? System.uptime : nil
    begin
      AnilProfiler.start_peer_render if start_peer_t
      AnilLanRework.players.each do |peer_id, peer|
        next if peer_id.to_s == AnilLanRework.self_internal_id.to_s
        next if peer.map_id != current_map_id

        # ----------------------------------------------------------------
        # CULLING DE DISTÂNCIA (Otimização de Renderização)
        # Só cria e atualiza sprites se o jogador estiver próximo (raio <= 22)
        # ----------------------------------------------------------------
        dist_x = (peer.x - $game_player.x).abs
        dist_y = (peer.y - $game_player.y).abs
        in_range = (dist_x <= 22 && dist_y <= 22)

        peer_map_id = peer.map_id

        # Cache de visibilidade reavaliado a cada 10 frames
        on_this_map = @anil_rework_peer_visible_cache[peer_id]
        if on_this_map.nil? || (cf - (@anil_rework_peer_visible_tick[peer_id] || 0) > 10)
          on_this_map = !AnilLanRework::WorldSync.hide_peer_sprite?(peer)
          @anil_rework_peer_visible_cache[peer_id] = on_this_map
          @anil_rework_peer_visible_tick[peer_id] = cf
        end

        unless on_this_map && in_range
          # Limpa os sprites se o jogador saiu da tela/alcance
          if @anil_rework_remote_sprites[peer_id]
            @anil_rework_remote_sprites[peer_id].dispose rescue nil
            @anil_rework_remote_sprites.delete(peer_id)
            @anil_rework_peer_busy_effects[peer_id]&.dispose rescue nil
            @anil_rework_peer_busy_effects.delete(peer_id)
            @anil_rework_peer_busy_blink_timers.delete(peer_id)
            @anil_rework_peer_busy_blink_phases.delete(peer_id)
            @anil_rework_peer_busy_snapshot.delete(peer_id)
            @anil_rework_peer_map_snapshot.delete(peer_id)
            @anil_rework_peer_visibility_snapshot.delete(peer_id)
          end
          if @anil_rework_remote_followers[peer_id]
            @anil_rework_remote_followers[peer_id][0].dispose rescue nil
            @anil_rework_remote_followers.delete(peer_id)
          end
          # Força snap na volta do culling
          peer.instance_variable_set(:@initialized_pos, false)
          next
        end

        visibility_snapshot = "#{peer_map_id}|#{current_map_id}|#{on_this_map ? 1 : 0}|#{peer.char_name}"
        if @anil_rework_peer_visibility_snapshot[peer_id] != visibility_snapshot
          @anil_rework_peer_visibility_snapshot[peer_id] = visibility_snapshot
          AnilLanRework.log("peer visibility peer=#{peer_id} peer_map=#{peer_map_id} current_map=#{current_map_id} visible=#{on_this_map} char=#{peer.char_name}")
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
        if follower_name.empty? || follower_name.to_i > 0
          if @anil_rework_remote_followers[peer_id]
            @anil_rework_remote_followers[peer_id][0].dispose rescue nil
            @anil_rework_remote_followers.delete(peer_id)
          end
          next
        end

        unless @anil_rework_remote_followers[peer_id]
          fake = AnilLanRework::RemotePeer.new
          fake.instance_variable_set(:@owner_peer, peer)
          follower_sprite = Sprite_Character.new(viewport, fake) rescue nil
          @anil_rework_remote_followers[peer_id] = [follower_sprite, fake] if follower_sprite
        end
        next unless @anil_rework_remote_followers[peer_id]

        fake = @anil_rework_remote_followers[peer_id][1]
        
        # Throttling real: atualiza dados do follower e calculate_bush_depth a cada 4 frames intercalados
        if (cf % 4) == (peer_id.hash % 4)
          fake.character_name = follower_name
          fake.map_id = peer_map_id
          fake.status_id = peer.status_id
          fake.follower_super_shiny = peer.follower_super_shiny
          fake.character_hue = (peer.follower_super_shiny ? peer.follower_hue : 0)
          fake.remote_follower_visual = true
          fake.calculate_bush_depth
        end

        # POSICAO DO FOLLOWER NO MESMO INSTANTE DO CORPO.
        #
        # Antes isto tinha a TERCEIRA copia da matematica de movimento, com
        # passo proprio. O corpo e o follower calculavam por caminhos diferentes
        # e separavam-se: o bicho ficava para tras a correr, ou "viajava" pelo
        # mapa quando o limite de salto era alto.
        #
        # Agora ambos saem do mesmo ponto interpolado do MOD 136, portanto
        # movem-se sempre juntos, exactamente como estavam no dono.
        interp = (AnilMovimentoRemoto.follower(peer) rescue nil)
        if interp
          target_real_x = interp[0]
          target_real_y = interp[1]
          target_dir    = interp[2]
          target_x      = target_real_x / peer.trx
          target_y      = target_real_y / peer.try
          target_pat    = peer.f_pat || peer.pattern
        else
          # Sem follower sincronizado: fica atras do dono, como antes.
          ox = (peer.direction == 6 ? -1 : peer.direction == 4 ? 1 : 0)
          oy = (peer.direction == 2 ? -1 : peer.direction == 8 ? 1 : 0)
          target_real_x = peer.real_x + (ox * peer.trx)
          target_real_y = peer.real_y + (oy * peer.try)
          target_x      = peer.x + ox
          target_y      = peer.y + oy
          target_dir    = peer.direction
          target_pat    = peer.pattern
        end

        # O corpo ja vem interpolado; o follower acompanha sem passo proprio.
        salto = (fake.real_x - target_real_x).abs > (peer.trx * AnilMovimentoRemoto::TELEPORTE_TILES) ||
                (fake.real_y - target_real_y).abs > (peer.try * AnilMovimentoRemoto::TELEPORTE_TILES)
        fake.target_x  = target_real_x
        fake.target_y  = target_real_y
        fake.real_x    = target_real_x
        fake.real_y    = target_real_y
        fake.x         = target_x
        fake.y         = target_y
        fake.direction = target_dir
        fake.pattern   = target_pat
        fake.instance_variable_set(:@initialized_follower_pos, true) if salto

        @anil_rework_remote_followers[peer_id][0].update rescue nil
      end

      if (cf % 10) == 0
        stale_ids = (@anil_rework_remote_sprites.keys + @anil_rework_remote_followers.keys).uniq
        stale_ids.each do |peer_id|
          peer = AnilLanRework.players[peer_id]
          dist_x = peer ? (peer.x - $game_player.x).abs : 999
          dist_y = peer ? (peer.y - $game_player.y).abs : 999
          in_range = (dist_x <= 22 && dist_y <= 22)
          
          keep = peer && peer.map_id == current_map_id && in_range && !AnilLanRework::WorldSync.hide_peer_sprite?(peer)
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
    ensure
      AnilProfiler.end_peer_render if start_peer_t
    end
  end
end

# ==============================================================================
# FIX 4 — WorldSync.build_snapshot: snapshot full menos frequente
# ==============================================================================
module AnilLanRework
  module WorldSync
    def self.build_snapshot
      return nil unless $game_map && $game_player
      @revision += 1
      # FIX 4: era revision % 20 — reduziu para % 60 para evitar
      # serialização pesada de todos os switches a cada ~0.5s no host.
      force_full_sw = (@revision <= 1) || (@revision % 60 == 0)
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
  end
end

# ==============================================================================
# FIX 5 — WorldSync.capture_switches_delta: remove rescue por iteração
# ==============================================================================
module AnilLanRework
  module WorldSync
    def self.capture_switches_delta
      out = {}
      # FIX 5: rescue dentro de each iteração tem custo em MRI Ruby mesmo
      # quando não há exceção. Movido para fora do loop.
      (1..MAX_TRACKED_SWITCH).each do |index|
        value = $game_switches[index]
        next if !value && !@switch_cache.key?(index)
        next if value == @switch_cache[index]
        @switch_cache[index] = value
        out[index.to_s] = value
      end
      out
    rescue => e
      AnilLanRework.log("capture_switches_delta error #{e.class}: #{e.message}")
      {}
    end

    def self.capture_switches_full
      out = {}
      (1..MAX_TRACKED_SWITCH).each do |index|
        value = $game_switches[index]
        @switch_cache[index] = value
        out[index.to_s] = value if value
      end
      out
    rescue => e
      AnilLanRework.log("capture_switches_full error #{e.class}: #{e.message}")
      {}
    end
  end
end

# ==============================================================================
# FIX 6 — Shadow Bypass para RemotePeer
# O script Overworld_Shadows_EX (0418) cria um Sprite_OWShadow para todo
# Sprite_Character. Como RemotePeer não herda Game_Character, o update do
# shadow dispara NoMethodError silencioso a cada frame por peer, causando
# um overhead massivo de CPU. Este patch contorna o bug em ambas as direções
# de carregamento (load order), interceptando a atualização e a inicialização.
# ==============================================================================
if defined?(Sprite_Character) && defined?(AnilLanRework::RemotePeer)
  class Sprite_Character < RPG::Sprite
    alias __fps_patch_shadow_init__ initialize unless private_method_defined?(:__fps_patch_shadow_init__)
    def initialize(*args)
      __fps_patch_shadow_init__(*args)
      if args[1].is_a?(AnilLanRework::RemotePeer)
        if @ow_shadow
          @ow_shadow.dispose rescue nil
          @ow_shadow = nil
        end
      end
    end

    alias __fps_patch_shadow_update__ update unless method_defined?(:__fps_patch_shadow_update__)
    def update(*args)
      if @character.is_a?(AnilLanRework::RemotePeer)
        if @ow_shadow
          @ow_shadow.dispose rescue nil
          @ow_shadow = nil
        end
      end
      __fps_patch_shadow_update__(*args)
    end
  end
end

if defined?(Sprite_OWShadow) && defined?(AnilLanRework::RemotePeer)
  class Sprite_OWShadow
    alias __fps_patch_ow_shadow_init__ initialize unless private_method_defined?(:__fps_patch_ow_shadow_init__)
    def initialize(sprite, event, viewport = nil)
      if event.is_a?(AnilLanRework::RemotePeer)
        @rsprite  = sprite
        @event    = event
        @viewport = viewport
        @sprite   = nil
        @disposed = true
        return
      end
      __fps_patch_ow_shadow_init__(sprite, event, viewport)
    end
  end
end

AnilLanRework.log("AnilLanRework_FPSPatch loaded OK — fixes 1-6 active")

# ==============================================================================
# Scene_Map profiling and F9 trigger hook
# ==============================================================================
class Scene_Map
  alias anil_profiler_scene_map_update update unless method_defined?(:anil_profiler_scene_map_update)

  def update
    start_sc_t = (defined?(AnilProfiler) && AnilProfiler.enabled) ? System.uptime : nil
    AnilProfiler.start_scenemap if start_sc_t
    begin
      anil_profiler_scene_map_update
    ensure
      AnilProfiler.end_scenemap if start_sc_t
    end
  end
end

# ==============================================================================
# DIAGNOSTIC PACKET LOGGER
# ==============================================================================
module AnilLanRework
  module Router
    class << self
      alias __diag_route_packet__ route_packet unless defined?(__diag_route_packet__)
      def route_packet(packet)
        __diag_route_packet__(packet)
        # ⚠️ Uma linha por PACOTE recebido. Sem portao, isto escrevia em
        # disco dezenas de vezes por segundo em qualquer mapa com gente.
        return unless (anil_diagnostico_ligado? rescue false)
        begin
          if packet.is_a?(Hash) && $game_map
            type = packet["type"].to_s
            sender = packet["sender_id"] || packet["player_id"] || packet["host_id"] || packet["internal_id"]
            p_map_id = packet["map_id"] || (packet["host_state"]["map_id"] rescue nil)
            File.open("multiplayer_packet_log.txt", "a") do |f|
              f.puts("[RECEIVE] Time: #{Time.now.strftime('%H:%M:%S.%L')} | Type: #{type} | Sender: #{sender} | Packet Map: #{p_map_id} | Client Map: #{$game_map.map_id}")
            end
          end
        rescue => e
          # ignore
        end
      end
    end
  end
end




