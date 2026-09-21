# encoding: UTF-8
#===============================================================================
# MOD: 099_Save_Coordinate_Fix
#-------------------------------------------------------------------------------
# 1. Separação LAN/Online Estrita
# 2. SaveCoordFix Robusto com BFS corrigido
#===============================================================================

class PokemonGlobalMetadata
  attr_accessor :online_id
  attr_accessor :is_multiplayer_online_save
  attr_accessor :is_verified_online_save
end

class Player
  attr_accessor :online_id
end

module Game
  class << self
    alias anil_save_seg_load load unless method_defined?(:anil_save_seg_load)
    def load(save_data)
      # Força o reset do estado loaded de TODOS os SaveData::Value registrados.
      # Isso garante que mesmo que o jogo tenha iniciado sem save (e carregado valores
      # de bootup padrão no arranque), o novo save carregado irá ler absolutamente
      # tudo de forma correta (incluindo $game_system, $stats, etc.).
      if defined?(SaveData)
        values = SaveData.instance_variable_get(:@values) rescue nil
        if values.is_a?(Array)
          values.each { |val| val.mark_as_unloaded rescue nil }
        end
      end

      if defined?(AnilLanRework) && AnilLanRework.respond_to?(:multiplayer_mode) && AnilLanRework.multiplayer_mode
        # BARREIRA 1: Só promove para online se o save realmente tem whitelist_code válido
        has_valid_code = false
        if save_data && save_data[:global_metadata]
          wc = save_data[:global_metadata].respond_to?(:whitelist_code) ? save_data[:global_metadata].whitelist_code.to_s.strip : ""
          has_valid_code = (wc =~ /\A\d{6}\z/) ? true : false
        end
        # Fallback: verifica também no :player caso o :global_metadata não tenha
        if !has_valid_code && save_data && save_data[:player]
          wc_p = save_data[:player].respond_to?(:whitelist_code) ? save_data[:player].whitelist_code.to_s.strip : ""
          has_valid_code = (wc_p =~ /\A\d{6}\z/) ? true : false
        end

        if has_valid_code
          if save_data && save_data[:global_metadata]
            save_data[:global_metadata].is_multiplayer_online_save = true
            save_data[:global_metadata].is_verified_online_save = true rescue nil
          end
          $anil_loading_multiplayer_online = true
        else
          # Save sem código de whitelist válido — NÃO promover para online
          AnilLanRework.log("[SAVE_GUARD] Game.load: save sem whitelist_code válido — NÃO promovido para online.") rescue nil
          if save_data && save_data[:global_metadata]
            save_data[:global_metadata].is_multiplayer_online_save = false
            save_data[:global_metadata].is_verified_online_save = false rescue nil
          end
          # BARREIRA 4: Limpa cache de machine_id para evitar hash leakage
          AnilLanRework.instance_variable_set(:@persistent_machine_id, nil) rescue nil
        end
      else
        if save_data && save_data[:global_metadata]
          save_data[:global_metadata].is_multiplayer_online_save = false
          save_data[:global_metadata].is_verified_online_save = false rescue nil
        end
        # BARREIRA 4: Limpa cache de machine_id ao carregar save offline
        if defined?(AnilLanRework)
          AnilLanRework.instance_variable_set(:@persistent_machine_id, nil) rescue nil
        end
      end
      
      anil_save_seg_load(save_data)
      
      if $anil_loading_multiplayer_online
        $PokemonGlobal.is_multiplayer_online_save = true if $PokemonGlobal
        $PokemonGlobal.is_verified_online_save = true if $PokemonGlobal rescue nil
        $anil_loading_multiplayer_online = false
      else
        if $PokemonGlobal
          $PokemonGlobal.is_multiplayer_online_save = false
          $PokemonGlobal.is_verified_online_save = false rescue nil
        end
      end
    end

    alias anil_save_seg_start_new start_new unless method_defined?(:anil_save_seg_start_new)
    def start_new
      if defined?(AnilLanRework)
        AnilLanRework.instance_variable_set(:@persistent_machine_id, nil)
        AnilLanRework.instance_variable_set(:@self_internal_id, nil)
      end
      # NÃO reseta $new_game_machine_hash aqui, pois ele é definido na tela de título
      # em 100_Multiplayer_Whitelist e limpo no final do start_new de lá.
      anil_save_seg_start_new
      if defined?(AnilLanRework) && AnilLanRework.respond_to?(:multiplayer_mode) && AnilLanRework.multiplayer_mode
        $PokemonGlobal.is_multiplayer_online_save = true if $PokemonGlobal
        $PokemonGlobal.is_verified_online_save = true if $PokemonGlobal rescue nil
      else
        $PokemonGlobal.is_multiplayer_online_save = false if $PokemonGlobal
        $PokemonGlobal.is_verified_online_save = false if $PokemonGlobal rescue nil
      end
    end
  end
end

# ==============================================================================
# PARTE 1: FLAG DE MODO ONLINE E HIGIENIZAÇÃO DE IDS ÚNICOS
# ==============================================================================
module AnilLanRework
  @online_session_active = false
  MACHINE_ID_FILE = "multiplayer_machine_id.txt" unless const_defined?(:MACHINE_ID_FILE)

  class << self
    attr_accessor :online_session_active
    attr_accessor :self_internal_id

    def mark_as_online_session!
      @online_session_active = true
    end

    def online_session?
      @online_session_active == true
    end

    def self_internal_id
      clean_id = get_player_id rescue nil
      @self_internal_id = clean_id if clean_id && !clean_id.empty?
      @self_internal_id
    end

    alias anil_lan_orig_disconnect disconnect unless method_defined?(:anil_lan_orig_disconnect)
    def disconnect(*args)
      @online_session_active = false
      anil_lan_orig_disconnect(*args)
    end

    def generate_unique_hash
      # Garante o semeamento do rand
      srand(Time.now.to_f.to_i ^ 0x3F3F3F3F ^ (Process.pid rescue 9999))
      
      computer = ENV["COMPUTERNAME"] || ENV["HOSTNAME"] || "pc"
      computer = "pc" if computer.to_s.strip.empty? || computer.to_s.downcase.include?("localhost")
      pid = (Process.pid rescue 0)
      base = "#{computer}_#{Time.now.to_f}_#{rand(1000000)}_#{pid}"
      
      # FNV-1a hash de 32 bits em Ruby puro
      hash = 2166136261
      base.each_byte do |byte|
        hash ^= byte
        hash = (hash * 16777619) & 0xffffffff
      end
      
      # Converte para string de 6 caracteres do alfabeto
      chars = [("A".."Z").to_a, ("0".."9").to_a].flatten
      res = ""
      6.times do
        res << chars[hash % chars.length]
        hash /= chars.length
      end
      res.upcase
    end

    def persistent_machine_id
      return @persistent_machine_id if @persistent_machine_id && !@persistent_machine_id.empty?

      is_new_game = $starting_new_game_multiplayer || ($game_temp && $game_temp.respond_to?(:begun_new_game) && $game_temp.begun_new_game)
      if $new_game_machine_hash
        @persistent_machine_id = $new_game_machine_hash.downcase
        return @persistent_machine_id
      end

      file = MACHINE_ID_FILE
      val  = nil
      
      unless is_new_game
        begin
          val = File.read(file, encoding: "UTF-8").strip if File.exist?(file)
        rescue; end
      end

      # Evita sufixos padrão/distribuídos no zip para prevenir colisão entre jogadores
      default_hashes = ["bso899", "bso89g", "q9yn57", "hifuo0"]
      if val.nil? || val.empty? || val.downcase.include?("localhost") || val !~ /\A[A-Za-z0-9]{4,}\z/ || default_hashes.include?(val.to_s.strip.downcase)
        val = generate_unique_hash
        if is_new_game
          $new_game_machine_hash = val.upcase
        end
        begin File.open(file, "w:UTF-8") { |f| f.write(val) }; rescue; end
      end

      cleaned = val.to_s.downcase.gsub(/[^a-z0-9]/, "")[0, 6]
      cleaned = generate_unique_hash.downcase if cleaned.nil? || cleaned.empty?
      @persistent_machine_id = cleaned
    end

    def machine_token
      persistent_machine_id
    end

    def resolve_online_id
      if defined?($PokemonGlobal) && $PokemonGlobal
        unless $PokemonGlobal.respond_to?(:online_id)
          class << $PokemonGlobal; attr_accessor :online_id; end
        end
        oid = $PokemonGlobal.online_id.to_s
        default_hashes = ["bso899", "bso89g", "q9yn57", "hifuo0"]
        if oid.empty? || oid == "A78YUA" || oid.downcase.include?("localhost") || oid !~ /\A[A-Z0-9]{6}\z/i || default_hashes.include?(oid.downcase)
          $PokemonGlobal.online_id = persistent_machine_id.upcase
        else
          $PokemonGlobal.online_id = oid[0, 6].upcase
        end
        if defined?($player) && $player
          unless $player.respond_to?(:online_id)
            class << $player; attr_accessor :online_id; end
          end
          $player.online_id = $PokemonGlobal.online_id.to_s rescue nil
        end
        return $PokemonGlobal.online_id.to_s
      end
      persistent_machine_id.upcase
    end

    def canonical_player_name(fallback_id = nil)
      name       = (defined?($player) && $player) ? $player.name.to_s : ""
      clean_name = name.gsub(/[^a-zA-Z0-9_-]/, '').downcase
      if clean_name.empty?
        raw        = fallback_id.to_s.downcase.gsub(/[^a-z0-9_-]+/, "-").gsub(/\A-+|-+\z/, "")
        raw        = raw.sub(/\Ajogador-/, "").sub(/-(localhost|[a-z0-9]{6})\z/i, "")
        clean_name = raw.gsub(/[^a-z0-9_-]/, '').downcase
      end
      clean_name = "jogador" if clean_name.empty?
      clean_name
    end

    def canonical_player_id(fallback_id = nil)
      clean_name = canonical_player_name(fallback_id)
      oid        = resolve_online_id.to_s.downcase
      oid        = persistent_machine_id.downcase if oid.empty?
      "#{clean_name}-#{oid}".downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")[0, 100]
    end

    def legacy_or_invalid_player_id?(player_id)
      raw = player_id.to_s.strip.downcase
      return true if raw.empty? || raw.include?("localhost")
      !(raw =~ /\A[a-z0-9][a-z0-9_-]*-[a-z0-9]{6}\z/)
    end

    def normalized_player_id(raw_id = nil)
      return canonical_player_id(raw_id) if legacy_or_invalid_player_id?(raw_id)
      sanitize_id(raw_id)
    end

    def placeholder_player_name?(name = nil)
      raw   = (name.nil? && defined?($player) && $player) ? $player.name.to_s : name.to_s
      clean = raw.to_s.strip.downcase
      return true if clean.empty?
      %w[unnamed unamed jogador trainer treinador player].include?(clean)
    end

    def resolve_internal_id(config_id)
      if online_session?
        "#{sanitize_id(config_id)}-#{machine_token}"
      else
        sanitize_id(config_id)
      end
    end

    def get_player_id
      if online_session?
        canonical_player_id
      else
        clean_name = canonical_player_name
        "jogador-#{clean_name}".downcase.gsub(/[^a-z0-9_-]+/, "-").gsub(/\A-+|-+\z/, "")[0, 100]
      end
    end
  end
end

# ==============================================================================
# INTERCEPTADOR DE CONEXÃO
# ==============================================================================
module AnilLanRework
  DEDICATED_SERVER_IP = "127.0.0.1".freeze unless const_defined?(:DEDICATED_SERVER_IP)

  class << self
    alias anil_lan_orig_connect connect unless method_defined?(:anil_lan_orig_connect)

    def connect(ip, player_id, player_name, char_name, is_host = false, *args)
      if ip.to_s == (AnilLanRework.respond_to?(:dedicated_server_ip) ? AnilLanRework.dedicated_server_ip : DEDICATED_SERVER_IP)
        mark_as_online_session!
      else
        @online_session_active = false
        AnilLanRework.log("[LAN/Online Fix] Conectando via LAN (#{ip}) — modo LAN")
      end
      clean_id   = AnilLanRework.get_player_id rescue nil
      player_id  = clean_id if clean_id && !clean_id.empty?
      anil_lan_orig_connect(ip, player_id, player_name, char_name, is_host, *args)
    end
  end

  alias anil_lan_orig_update_player_config update_player_config unless method_defined?(:anil_lan_orig_update_player_config)
  def update_player_config
    return unless defined?(AnilLanRework) && (AnilLanRework.multiplayer_mode || AnilLanRework.online_session?)
    anil_lan_orig_update_player_config rescue nil
    begin
      return unless defined?($player) && $player
      return if AnilLanRework.respond_to?(:placeholder_player_name?) && AnilLanRework.placeholder_player_name?
      file = "multiplayer_player.txt"
      id   = AnilLanRework.get_player_id rescue nil
      id   ||= canonical_player_id
      rows = {}
      if File.exist?(file)
        File.readlines(file, encoding: "UTF-8").each do |line|
          parts = line.strip.split("=", 2)
          rows[parts[0].strip] = parts[1].to_s.strip if parts.size == 2
        end
      end
      rows["id"] = id
      File.open(file, "w:UTF-8") { |f| f.write(rows.map { |k, v| "#{k}=#{v}\n" }.join) }
    rescue; end
  end
end

# ==============================================================================
# PARTE 2: AUTO-CONNECT BLOQUEADO PARA MODO LAN
# ==============================================================================
module AnilLanRework
  class << self
    alias anil_lan_orig_trigger_auto_connect trigger_auto_connect_on_map \
      unless method_defined?(:anil_lan_orig_trigger_auto_connect)

    def trigger_auto_connect_on_map(silent = false)
      # O SAVE sabe se e uma conta do servidor: traz online_id e o codigo de
      # acesso de 6 digitos. Sem olhar para isso, so entrava em modo VPS quem
      # tinha acabado de usar "Recuperar partida" (que liga multiplayer_mode a
      # mao) — quem carregava pelo Multi Save caia em OFFLINE, e o menu F7
      # mostrava as opcoes de LAN (abrir/entrar/IP/debug), que nao fazem sentido
      # neste jogo.
      save_e_online = begin
        wc  = ($PokemonGlobal && $PokemonGlobal.respond_to?(:whitelist_code)) ? $PokemonGlobal.whitelist_code.to_s.strip : ""
        oid = ($PokemonGlobal && $PokemonGlobal.respond_to?(:online_id))      ? $PokemonGlobal.online_id.to_s.strip      : ""
        !oid.empty? && wc =~ /\A\d{6}\z/ ? true : false
      rescue
        false
      end

      unless AnilLanRework.online_session? || (defined?(AnilLanRework) && AnilLanRework.multiplayer_mode) || save_e_online
        $game_temp.anil_pending_multiplayer_auto_connect = false \
          if $game_temp&.respond_to?(:anil_pending_multiplayer_auto_connect)
        AnilLanRework.log("[LAN/Online Fix] trigger_auto_connect_on_map BLOQUEADO (save sem credenciais do servidor)")
        return
      end

      # `trigger_auto_connect_on_map` original tambem sai cedo se multiplayer_mode
      # for falso, entao nao basta passar o portao acima: e preciso ligar o modo
      # antes de lhe entregar o controlo.
      if save_e_online && defined?(AnilLanRework) && AnilLanRework.respond_to?(:multiplayer_mode=) && !AnilLanRework.multiplayer_mode
        AnilLanRework.multiplayer_mode = true rescue nil
        AnilLanRework.log("[LAN/Online Fix] Save com credenciais do servidor — entrando em modo VPS.")
      end
      
      # Bloqueia a conexão automática se estiver no Novo Jogo ou nos mapas da introdução (Oak's Speech)
      is_new_game = $game_temp && $game_temp.respond_to?(:begun_new_game) && $game_temp.begun_new_game
      is_intro_map = $game_map && ($game_map.map_id == 1 || $game_map.map_id == 104 || $game_map.map_id == 29)
      if is_new_game || is_intro_map
        $game_temp.anil_pending_multiplayer_auto_connect = true \
          if $game_temp&.respond_to?(:anil_pending_multiplayer_auto_connect)
        AnilLanRework.log("[LAN/Online Fix] trigger_auto_connect_on_map ADIADO (iniciando novo jogo/intro)")
        return
      end
      
      if AnilLanRework.respond_to?(:placeholder_player_name?) && AnilLanRework.placeholder_player_name?
        if defined?(AnilLanRework) && AnilLanRework.multiplayer_mode
          $game_temp.anil_pending_multiplayer_auto_connect = true \
            if $game_temp&.respond_to?(:anil_pending_multiplayer_auto_connect)
          AnilLanRework.log("[LAN/Online Fix] trigger_auto_connect_on_map ADIADO (nome placeholder)")
          return
        end
      end
      AnilLanRework.update_player_config rescue nil
      anil_lan_orig_trigger_auto_connect(silent)
    end
  end
end

# (bloco de auto-connect unificado no AnilCoordFixMixin abaixo)

# ==============================================================================
# PARTE 4: SaveCoordFix — BFS concêntrico CORRIGIDO
#
# BUG NO ORIGINAL: os dois loops aninhados (dx/dy) geravam apenas cantos e
# bordas laterais, perdendo linhas inteiras do quadrado e duplicando tiles.
# Correção: gera TODOS os tiles da borda do quadrado de lado (2*r+1),
# depois itera para dentro — garantindo varredura completa e sem repetição.
# ==============================================================================
module AnilCoordFix
  FALLBACK_MAP_ID = 29
  FALLBACK_X      = 10
  FALLBACK_Y      = 10
  FALLBACK_DIR    = 2

  def self.log(msg)
    if defined?(AnilLanRework)
      AnilLanRework.log("[SaveCoordFix] #{msg}")
    else
      echoln("[SaveCoordFix] #{msg}") rescue nil
    end
  end

  # BFS concêntrico CORRETO:
  # Para cada raio r, percorre a moldura quadrada completa de distância r
  # ao ponto de origem — todos os (dx, dy) onde max(|dx|,|dy|) == r.
  # Isso garante que nenhum tile seja pulado ou duplicado.
  def self.find_passable_spot(start_x, start_y, map, max_radius = 15)
    return [start_x, start_y] unless map
    w = map.width  rescue 0
    h = map.height rescue 0
    return [start_x, start_y] if w <= 0 || h <= 0

    # Raio 0: verifica o tile atual primeiro
    (0..max_radius).each do |r|
      # Gera a moldura do quadrado de raio r (todos os tiles a distância Chebyshev == r)
      candidates = []
      if r == 0
        candidates << [0, 0]
      else
        # Topo e base
        (-r..r).each { |dx| candidates << [dx, -r]; candidates << [dx, r] }
        # Laterais (excluindo cantos já adicionados)
        (-(r-1)..(r-1)).each { |dy| candidates << [-r, dy]; candidates << [r, dy] }
      end

      candidates.each do |dx, dy|
        x = start_x + dx
        y = start_y + dy
        next if x < 0 || x >= w || y < 0 || y >= h
        begin
          passable = (map.passableStrict?(x, y, 0, $game_player) rescue map.passable?(x, y, 2) rescue true)
          return [x, y] if passable
        rescue
          next
        end
      end
    end

    # Fallback: clamp dentro dos limites do mapa
    [start_x.clamp(0, w - 1), start_y.clamp(0, h - 1)]
  end

  def self.get_healing_spot_fallback
    return nil unless defined?($PokemonGlobal) && $PokemonGlobal
    h = $PokemonGlobal.healingSpot rescue nil
    return nil unless h.is_a?(Array) && h[0].to_i > 0
    { map_id: h[0].to_i, x: h[1].to_i, y: h[2].to_i, dir: (h[3] || 2).to_i }
  rescue
    nil
  end

  # Verifica se o tile atual do jogador é válido.
  # Retorna :ok, :out_of_bounds ou :impassable
  def self.check_player_position
    return :ok unless defined?($game_player) && $game_player
    return :ok unless defined?($game_map) && $game_map
    map = $game_map
    w   = map.width  rescue 0
    h   = map.height rescue 0
    return :ok if w <= 0 || h <= 0

    x = $game_player.x.to_i rescue 0
    y = $game_player.y.to_i rescue 0

    return :out_of_bounds if x < 0 || x >= w || y < 0 || y >= h

    passable = (map.passableStrict?(x, y, 0, $game_player) rescue map.passable?(x, y, 2) rescue true)
    passable ? :ok : :impassable
  rescue
    :ok
  end

  def self.fix_player_position
    return unless defined?($game_player) && $game_player
    return unless defined?($game_map) && $game_map

    map    = $game_map
    status = check_player_position
    return if status == :ok

    x = $game_player.x.to_i rescue 0
    y = $game_player.y.to_i rescue 0
    w = map.width  rescue 0
    h = map.height rescue 0

    # Ponto de partida para a busca BFS
    search_x = x.clamp(0, [w - 1, 0].max)
    search_y = y.clamp(0, [h - 1, 0].max)

    # Se o healing spot for neste mapa, começa a busca a partir dele
    healing = get_healing_spot_fallback
    if healing && healing[:map_id] == map.map_id
      search_x = healing[:x].clamp(0, [w - 1, 0].max)
      search_y = healing[:y].clamp(0, [h - 1, 0].max)
    end

    nx, ny = find_passable_spot(search_x, search_y, map)

    log("Status: #{status} | Original (#{x},#{y}) | Corrigido para (#{nx},#{ny}) | Mapa #{map.map_id}")
    $game_player.moveto(nx, ny)
    $game_player.straighten rescue nil
  rescue => e
    log("Erro em fix_player_position: #{e.class}: #{e.message}")
  end
end

# ==============================================================================
# HOOK NA SCENE_MAP — alias clássico, sem prepend, sem super.
#
# POR QUE NÃO PREPEND:
#   O 040_Multiplayer_Post_Plugin_Patches usa class_eval com alias dentro
#   de apply_post_plugin_patches (chamado pelo PluginManager#runPlugins).
#   Esse alias captura o método "update" que estiver vigente no momento da
#   execução — que seria o nosso prepend. O nosso prepend por sua vez chama
#   super → cai no alias do 040 → que chama anil_speech_original_update →
#   que é o nosso prepend → loop infinito → SystemStackError.
#
# SOLUÇÃO: alias com nome único (anil_coord_fix_update_orig) aplicado
#   via class_eval. O 040 roda no PluginManager#runPlugins (boot), e o
#   099 é carregado depois (ordem alfabética), então nosso alias fica no
#   TOPO da cadeia e chama o alias do 040, que chama o original.
#   Cadeia correta: anil_coord_fix_update → anil_speech_original_update
#   → update_original_do_essentials. Sem ciclo.
# ==============================================================================
class Scene_Map
  unless method_defined?(:anil_coord_fix_update_orig)
    alias anil_coord_fix_update_orig update
  end

  def update
    # Fix de coordenadas: roda a cada frame ATÉ conseguir validar de fato.
    #
    # BUG ORIGINAL: @_anil_coord_fix_applied era marcado como true no primeiro
    # update, mesmo que online_session? ainda fosse false (o normal, já que a
    # conexão com o servidor é assíncrona e quase nunca termina a tempo do
    # primeiro frame). Resultado: a checagem nunca rodava de verdade no login.
    #
    # CORREÇÃO: só marca @_anil_coord_fix_applied quando a checagem REALMENTE
    # executou. Em offline/LAN roda na hora. Em online, tenta a cada frame até
    # a sessão ficar pronta.
    unless @_anil_coord_fix_applied
      needs_online = defined?(AnilLanRework) && AnilLanRework.respond_to?(:multiplayer_mode) && AnilLanRework.multiplayer_mode
      ready = !needs_online || (defined?(AnilLanRework) && AnilLanRework.online_session?)
      if ready
        AnilCoordFix.fix_player_position rescue nil
        @_anil_coord_fix_applied = true
      end
    end

    # Cancela pending auto-connect em modo LAN
    if $game_temp&.respond_to?(:anil_pending_multiplayer_auto_connect) &&
       $game_temp.anil_pending_multiplayer_auto_connect &&
       !AnilLanRework.online_session? &&
       !(defined?(AnilLanRework) && AnilLanRework.multiplayer_mode)
      $game_temp.anil_pending_multiplayer_auto_connect = false
      AnilLanRework.log("[LAN/Online Fix] pending auto-connect cancelado (modo LAN/offline)")
    end

    anil_coord_fix_update_orig
  end

  unless method_defined?(:anil_coord_fix_transfer_orig)
    alias anil_coord_fix_transfer_orig transfer_player
  end

  def transfer_player(*args)
    result = anil_coord_fix_transfer_orig(*args)
    # Reseta flag para que o fix rode no primeiro update do novo mapa
    @_anil_coord_fix_applied = false
    if defined?(AnilLanRework) && AnilLanRework.online_session?
      AnilCoordFix.fix_player_position rescue nil
    end
    AnilLanRework::WorldSync.send_player_state rescue nil if defined?(AnilLanRework) && AnilLanRework.respond_to?(:connected?) && AnilLanRework.connected?
    result
  end
end

# ==============================================================================
# HOOK EM SaveData.read_from_file — corrige posição ANTES de carregar a cena
# Não tenta recriar Game_Map (instável fora do contexto de cena).
# Apenas garante que as coordenadas salvas sejam válidas para o mapa declarado.
# ==============================================================================
if defined?(SaveData)
  module SaveData
    class << self
      alias anil_coord_fix_read_from_file read_from_file \
        unless method_defined?(:anil_coord_fix_read_from_file)

      def read_from_file(file_path)
        save_data = anil_coord_fix_read_from_file(file_path)
        return save_data unless save_data.is_a?(Hash)

        is_online_save = false
        begin
          if save_data[:global_metadata]
            is_online_save = save_data[:global_metadata].is_multiplayer_online_save
          end
        rescue; end

        return save_data unless is_online_save

        begin
          gp = save_data[:game_player]
          next_map_id = gp&.instance_variable_get(:@map_id).to_i rescue 0

          if next_map_id <= 0
            # Mapa ID inválido: tenta usar o healing spot como fallback
            fallback = { map_id: AnilCoordFix::FALLBACK_MAP_ID,
                         x:      AnilCoordFix::FALLBACK_X,
                         y:      AnilCoordFix::FALLBACK_Y,
                         dir:    AnilCoordFix::FALLBACK_DIR }

            begin
              global = save_data[:global_metadata]
              if global
                h = global.healingSpot rescue nil
                if h.is_a?(Array) && h[0].to_i > 0
                  fallback[:map_id] = h[0].to_i
                  fallback[:x]      = h[1].to_i
                  fallback[:y]      = h[2].to_i
                  fallback[:dir]    = (h[3] || 2).to_i
                end
              end
            rescue; end

            AnilCoordFix.log("Map ID inválido no save (#{next_map_id}) — fallback para mapa #{fallback[:map_id]}")

            if gp
              gp.instance_variable_set(:@map_id,    fallback[:map_id]) rescue nil
              gp.instance_variable_set(:@x,         fallback[:x])      rescue nil
              gp.instance_variable_set(:@y,         fallback[:y])      rescue nil
              gp.instance_variable_set(:@direction, fallback[:dir])    rescue nil
            end

            mf = save_data[:map_factory]
            mf.instance_variable_set(:@map_id, fallback[:map_id]) rescue nil
            # NÃO recria Game_Map aqui — o Essentials faz isso ao inicializar a cena.
          end
        rescue => e
          AnilCoordFix.log("Erro no read_from_file patch: #{e.class}: #{e.message}")
        end

        save_data
      end
    end
  end
end

# ==============================================================================
# MIGRATION AUTOMÁTICA DE SAVES COM "LOCALHOST" NO NOME
# ==============================================================================
begin
  dirs = ["./"]
  begin
    sd = System.data_directory
    dirs << sd if sd && File.directory?(sd)
  rescue; end
  dirs.uniq!

  dirs.each do |dir|
    next unless File.directory?(dir)
    Dir.glob(File.join(dir, "*.rxdata")).each do |fpath|
      next unless File.basename(fpath) =~ /^([a-z0-9_-]+)-localhost\.rxdata$/i
      prefix     = $1
      machine_id = AnilLanRework.persistent_machine_id.downcase rescue next
      next if machine_id.empty?

      new_fpath = File.join(dir, "#{prefix}-#{machine_id}.rxdata")
      next if File.exist?(new_fpath)
      begin
        File.rename(fpath, new_fpath)
        AnilLanRework.log("MIGRATION: #{File.basename(fpath)} → #{File.basename(new_fpath)}") rescue nil
      rescue => e
        AnilLanRework.log("MIGRATION ERRO: #{e.message}") rescue nil
      end

      bak     = fpath + ".bak"
      new_bak = new_fpath + ".bak"
      if File.exist?(bak) && !File.exist?(new_bak)
        File.rename(bak, new_bak) rescue nil
      end
    end
  end

  cfg = "multiplayer_player.txt"
  if File.exist?(cfg)
    rows    = {}
    updated = false
    File.readlines(cfg, encoding: "UTF-8").each do |line|
      parts = line.strip.split("=", 2)
      next unless parts.size == 2
      k, v = parts[0].strip, parts[1].to_s.strip
      if k == "id" && v =~ /^([a-z0-9_-]+)-localhost$/i
        mid = AnilLanRework.persistent_machine_id.downcase rescue nil
        if mid && !mid.empty?
          v       = "#{$1}-#{mid}"
          updated = true
        end
      end
      rows[k] = v
    end
    if updated
      File.open(cfg, "w:UTF-8") { |f| f.write(rows.map { |k, v| "#{k}=#{v}\n" }.join) }
      AnilLanRework.log("MIGRATION: #{cfg} atualizado (localhost removido)") rescue nil
    end
  end
rescue => e
  AnilLanRework.log("MIGRATION ERRO CRÍTICO: #{e.message}") rescue nil
end

AnilCoordFix.log("Patch LAN/Online + SaveCoordFix v2 carregado.")

# Hook em Game.load para limpar o hash temporário do novo jogo
module Game
  class << self
    alias anil_new_game_hash_orig_load load unless method_defined?(:anil_new_game_hash_orig_load)
    def load(save_data)
      $new_game_machine_hash = nil
      anil_new_game_hash_orig_load(save_data)
    end
  end
end