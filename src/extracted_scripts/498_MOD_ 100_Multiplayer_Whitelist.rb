# encoding: UTF-8
#===============================================================================
# MOD: 100_Multiplayer_Whitelist (FIXED)
#-------------------------------------------------------------------------------
# CORREÇÕES:
# 1. Hash ID gerado e persistido DENTRO do save game, sem depender de arquivo externo.
#    O client_hash.txt é usado apenas como cache secundário, a fonte da verdade é o save.
# 2. Loop de validação nunca retorna false silenciosamente — sempre oferece novo input.
# 3. Validação automática do código salvo: se falhar, entra no loop pedindo novo código
#    em vez de fechar ou travar o jogo.
# 4. FIX: Encoding::CompatibilityError resolvido — todas as strings _INTL com acentos
#    agora são forçadas para UTF-8 antes de serem passadas ao _INTL/pbMessage.
#===============================================================================

begin
  require 'timeout'
rescue LoadError
end

unless defined?(Timeout)
  module Timeout
    class Error < RuntimeError; end
    def self.timeout(sec)
      yield
    end
  end
end

class Game_Temp
  attr_accessor :anil_pending_multiplayer_instant_connect
end

# Extensão das classes de save para serialização do hash e do código
class PokemonGlobalMetadata
  attr_accessor :whitelist_code
  attr_accessor :client_machine_hash   # Hash persistido NO save, fonte da verdade
end

class Player
  attr_accessor :whitelist_code
  attr_accessor :client_machine_hash
end

module AnilLanRework
  remove_const(:JOIN_TIMEOUT) if const_defined?(:JOIN_TIMEOUT)
  JOIN_TIMEOUT = 99999.0

  def self.dedicated_server_ip
    if File.exist?("multiplayer_vps_ip.txt")
      ip = File.read("multiplayer_vps_ip.txt").strip
      return ip unless ip.empty?
    end
    if File.exist?("multiplayer_ip.txt")
      content = File.read("multiplayer_ip.txt").to_s
      if content =~ /ip\s*=\s*([^\s]+)/
        return $1.strip
      elsif !content.strip.empty?
        return content.strip
      end
    end
    "179.198.110.71"
  end

  class Connection
    alias anil_lan_orig_class_connect connect unless method_defined?(:anil_lan_orig_class_connect)
    alias anil_lan_orig_wait_for_join_ack wait_for_join_ack unless method_defined?(:anil_lan_orig_wait_for_join_ack)
    alias anil_whitelist_orig_handle_packet handle_packet unless method_defined?(:anil_whitelist_orig_handle_packet)

    attr_reader :new_online_id, :new_player_id

    def handle_packet(packet)
      if packet.is_a?(Hash) && packet["type"] == "join_ack"
        @new_online_id = packet["new_online_id"]
        @new_player_id = packet["new_player_id"]
      end
      anil_whitelist_orig_handle_packet(packet)
    end

    def wait_for_join_ack(timeout = AnilLanRework::JOIN_TIMEOUT)
      started = Time.now.to_f
      until @join_ack_received
        tick

        err_packet = @incoming.find { |p| p["type"] == "error" }
        if err_packet
          @last_error = err_packet["message"] || err_packet["error"]
          disconnect
          return false
        end

        kick_packet = @incoming.find { |p| p["type"] == "admin_kick" }
        if kick_packet
          @last_error = "BANNED: #{kick_packet['reason']}"
          disconnect
          return false
        end

        if !connected?
          read_packets rescue nil
          err_packet = @incoming.find { |p| p["type"] == "error" }
          if err_packet
            @last_error = err_packet["message"] || err_packet["error"]
            disconnect
            return false
          end

          kick_packet = @incoming.find { |p| p["type"] == "admin_kick" }
          if kick_packet
            @last_error = "BANNED: #{kick_packet['reason']}"
          else
            if @last_error.to_s.empty? || @last_error.to_s.include?("disconnected") || @last_error.to_s.include?("closed")
              @last_error = "Conexao encerrada pelo servidor."
            end
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

    def connect(ip, internal_id:, display_id:, player_name:, char_name:, is_host:, startup: false)
      vps_ip = AnilLanRework.dedicated_server_ip
      if ip.to_s == "127.0.0.1" || ip.to_s == vps_ip
        @ip = ip
        initial_state = {}
        if defined?(AnilLanRework::WorldSync)
          initial_state = AnilLanRework::WorldSync.capture_player_state || {}
        end

        AnilLanRework.log("[WHITELIST/TIMEOUT] Conectando ao servidor dedicado/VPS (#{ip}) sem limite de timeout") rescue nil

        @socket = TCPSocket.new(ip.to_s, AnilLanRework::SERVER_PORT)
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
        @new_online_id = nil
        @new_player_id = nil

        # ⚠️ O upload da skin tem de estar AQUI tambem.
        #
        # O connect original (000_Multiplayer_Online) manda a skin custom ao
        # ligar-se. Este connect e uma reimplementacao para o IP da VPS, e o
        # bloco ficou de fora — logo, em producao, ligar-se ao servidor nunca
        # enviava skin nenhuma. Sobrava um unico gatilho: TROCAR de skin no
        # seletor. Quem ja tivesse a skin escolhida podia entrar mil vezes que
        # ela nunca chegava ao painel.
        #
        # E o mesmo tipo de lacuna que ja tinha acontecido com os campos do join
        # (ranked, client_build, game_version): o que vale e este ficheiro.
        if defined?(AnilLanRework) && AnilLanRework.respond_to?(:upload_custom_skin)
          skin_a_enviar = if $player && $player.respond_to?(:multiplayer_skin) && $player.multiplayer_skin
                            $player.multiplayer_skin
                          else
                            char_name.to_s
                          end
          if skin_a_enviar && !skin_a_enviar.to_s.empty?
            Thread.new do
              begin
                # Primeiro garantir que EU tenho o ficheiro. Se nao tiver, e
                # inutil (e impossivel) enviar: o upload_custom_skin desiste
                # logo no File.exist?. Num aparelho novo e este passo que traz
                # a skin de volta — sou o dono, o servidor autoriza.
                baixou = begin
                  AnilLanRework::ServerSkins.assegurar_skin_local!
                rescue
                  false
                end
                # Se acabei de a baixar do servidor, ela ja la esta: reenviar
                # so daria trabalho aos dois lados.
                AnilLanRework.upload_custom_skin(skin_a_enviar) unless baixou
              rescue
              end
            end
          end
        end

        send_packet("join",
          "internal_id" => internal_id,
          "display_id"  => display_id,
          "name" => player_name,
          "char" => char_name.to_s,
          "host" => is_host ? true : false,
          "map_id" => initial_state["map_id"] || (($game_map && $game_map.map_id) || -1),
          "x" => initial_state["x"] || ($game_player&.x || 0),
          "y" => initial_state["y"] || ($game_player&.y || 0),
          "real_x" => initial_state["real_x"] || ($game_player&.real_x || 0),
          "real_y" => initial_state["real_y"] || ($game_player&.real_y || 0),
          "dir" => initial_state["dir"] || ($game_player&.direction || 2),
          "pattern" => initial_state["pattern"] || ($game_player&.pattern || 0),
          "follower" => initial_state["follower"] || "",
          "status" => initial_state["status"],
          "battle_busy" => initial_state["battle_busy"] == true,
          "menu_open" => initial_state["menu_open"] == true,
          "online_id" => (defined?(AnilLanRework) && AnilLanRework.respond_to?(:resolve_online_id) ? AnilLanRework.resolve_online_id : nil),
          "whitelist_code" => (defined?(AnilLanRework) && AnilLanRework.respond_to?(:current_whitelist_code) ? AnilLanRework.current_whitelist_code : nil),
          # =====================================================================
          # ⚠️ ESTE join E O QUE VALE PARA TODA A GENTE.
          #
          # Este connect SUBSTITUI o do MOD 000 sempre que o IP e o da VPS (ou
          # 127.0.0.1) — isto e, no jogo real. O do 000 so corre para outro IP
          # qualquer. Quem acrescentar um campo ao join tem de o acrescentar AQUI
          # tambem, senao ele nunca sai da maquina de ninguem.
          #
          # Foi exactamente o que aconteceu com o ranqueado: o servidor recusava
          # todas as partidas com "algum cliente nao suporta ranqueada" apesar
          # dos dois lados estarem actualizados, porque a marca viajava no join
          # do 000 e nao neste. O sinal que denunciou foi o client_build chegar
          # VAZIO ao servidor — ele tambem so existia no outro join.
          # =====================================================================
          "ranked"       => true,
          "client_build" => (AnilLanRework::CLIENT_BUILD rescue ""),
          "game_version" => (Settings::GAME_VERSION rescue "")
        )
        flush_batch
        start_recv_thread
        wait_for_join_ack(99999.0)
      else
        anil_lan_orig_class_connect(ip,
          internal_id: internal_id,
          display_id: display_id,
          player_name: player_name,
          char_name: char_name,
          is_host: is_host,
          startup: startup
        )
      end
    end
  end
end

module Multiplayer_Whitelist
  # Arquivo de cache local (secundário — a fonte da verdade é o save game)
  LOCAL_HASH_FILE = "Data/client_hash.txt"

  # Helper interno: converte string para UTF-8 sem explodir em encodings mistos
  def self._u(str)
    str.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
  end

  # ─────────────────────────────────────────────────────────────────
  # PONTO DE ENTRADA PRINCIPAL
  # ─────────────────────────────────────────────────────────────────
  def self.iniciar_validacao
    local_hash = carregar_ou_gerar_hash_no_save

    code_from_save = nil
    if defined?($PokemonGlobal) && $PokemonGlobal && $PokemonGlobal.respond_to?(:whitelist_code)
      code_from_save = $PokemonGlobal.whitelist_code.to_s.strip
      code_from_save = nil unless code_from_save =~ /\A\d{6}\z/
    end

    validado = false
    prompt_msg = _u("Digite o codigo de 6 numeros para acessar o Multiplayer:")

    if code_from_save
      AnilLanRework.log("[WHITELIST/AUTO] Tentando validar codigo salvo: #{code_from_save}") rescue nil
      resposta = validar_no_servidor(code_from_save, local_hash)
      if resposta[:sucesso]
        aplicar_validacao(code_from_save, local_hash, resposta[:id_jogador])
        validado = true
        AnilLanRework.log("[WHITELIST/AUTO] Codigo salvo validado com sucesso.") rescue nil
      elsif resposta[:rejeitado]
        AnilLanRework.log("[WHITELIST/AUTO] Codigo salvo rejeitado: #{resposta[:mensagem]}") rescue nil
        limpar_codigo_salvo
        prompt_msg = _u("Codigo invalido/expirado! Digite um novo codigo de 6 numeros:")
      else
        AnilLanRework.log("[WHITELIST/AUTO] Falha de conexao: #{resposta[:mensagem]}") rescue nil
        msg = _u("Erro na Conexao: Nao foi possivel validar seu codigo com o servidor. Tente novamente mais tarde.")
        if defined?(pbMessage)
          pbMessage(msg)
        elsif defined?(Kernel.pbMessage)
          Kernel.pbMessage(msg)
        end
        return false
      end
    end

    while !validado
      codigo_digitado = solicitar_codigo_ao_jogador(prompt_msg)

      if codigo_digitado.nil?
        return false
      end

      if codigo_digitado.to_s.strip.empty? || codigo_digitado.to_s.strip !~ /\A\d{6}\z/
        prompt_msg = _u("Codigo invalido! Digite exatamente 6 numeros:")
        next
      end

      resposta = validar_no_servidor(codigo_digitado, local_hash)

      if resposta[:sucesso]
        aplicar_validacao(codigo_digitado, local_hash, resposta[:id_jogador])
        validado = true
        msg = _u("Login autorizado! Bem-vindo de volta.")
        if defined?(pbMessage)
          pbMessage(msg)
        elsif defined?(Kernel.pbMessage)
          Kernel.pbMessage(msg)
        end
      else
        msg_erro = _u(resposta[:mensagem].to_s)
        if resposta[:rejeitado]
          prompt_msg = _u("Codigo invalido! Digite outro codigo de 6 numeros:")
        else
          prompt_msg = _u("Erro de conexao! Digite novamente o codigo de 6 numeros:")
        end
        msg = _u("Erro: #{msg_erro}")
        if defined?(pbMessage)
          pbMessage(msg)
        elsif defined?(Kernel.pbMessage)
          Kernel.pbMessage(msg)
        end
      end
    end

    true
  end

  # ─────────────────────────────────────────────────────────────────
  # Hash: carrega do save (fonte primária) ou gera novo
  # ─────────────────────────────────────────────────────────────────
  def self.carregar_ou_gerar_hash_no_save
    # Se já geramos um hash para este novo jogo, reutiliza-o
    if $new_game_machine_hash
      return $new_game_machine_hash
    end

    hash_no_save = nil

    if defined?($PokemonGlobal) && $PokemonGlobal
      garantir_atributo($PokemonGlobal, :client_machine_hash)
      hash_no_save = $PokemonGlobal.client_machine_hash.to_s.strip.upcase
      hash_no_save = nil unless hash_no_save =~ /\A[A-Z0-9]{6}\z/
    end

    if defined?($player) && $player && hash_no_save.nil?
      garantir_atributo($player, :client_machine_hash)
      hash_no_save = $player.client_machine_hash.to_s.strip.upcase
      hash_no_save = nil unless hash_no_save =~ /\A[A-Z0-9]{6}\z/
    end

    if hash_no_save.nil? && File.exist?(LOCAL_HASH_FILE)
      begin
        cached = File.read(LOCAL_HASH_FILE).to_s.strip.upcase
        hash_no_save = cached if cached =~ /\A[A-Z0-9]{6}\z/
      rescue
      end
    end

    hash_no_save = gerar_novo_hash if hash_no_save.nil?

    persistir_hash_no_save(hash_no_save)

    begin
      Dir.mkdir("Data") unless Dir.exist?("Data")
      File.open(LOCAL_HASH_FILE, "w:UTF-8") { |f| f.write(hash_no_save) }
    rescue => e
      AnilLanRework.log("[WHITELIST] Aviso: nao foi possivel atualizar cache local: #{e.message}") rescue nil
    end

    hash_no_save
  end

  def self.carregar_ou_gerar_hash_local
    carregar_ou_gerar_hash_no_save
  end

  def self.persistir_hash_no_save(hash)
    if defined?($PokemonGlobal) && $PokemonGlobal
      garantir_atributo($PokemonGlobal, :client_machine_hash)
      $PokemonGlobal.client_machine_hash = hash
    end
    if defined?($player) && $player
      garantir_atributo($player, :client_machine_hash)
      $player.client_machine_hash = hash
    end
  end

  def self.aplicar_validacao(codigo, local_hash, id_jogador)
    $jogador_id_validado = id_jogador

    if defined?(AnilLanRework)
      AnilLanRework.current_whitelist_code = codigo
    end

    if defined?($PokemonGlobal) && $PokemonGlobal
      garantir_atributo($PokemonGlobal, :whitelist_code)
      garantir_atributo($PokemonGlobal, :client_machine_hash)
      $PokemonGlobal.whitelist_code       = codigo
      $PokemonGlobal.client_machine_hash  = local_hash
      $PokemonGlobal.online_id            = local_hash.upcase rescue nil
    end

    if defined?($player) && $player
      garantir_atributo($player, :whitelist_code)
      garantir_atributo($player, :client_machine_hash)
      $player.whitelist_code       = codigo
      $player.client_machine_hash  = local_hash
      $player.online_id            = local_hash.upcase rescue nil
    end

    atualizar_saves_locais(local_hash)

    if defined?($game_temp) && $game_temp && $game_temp.respond_to?(:begun_new_game=)
      $game_temp.begun_new_game = false rescue nil
    end

    if defined?(pbSave)
      pbSave(true) rescue nil
    end
  end

  def self.limpar_codigo_salvo
    if defined?($PokemonGlobal) && $PokemonGlobal && $PokemonGlobal.respond_to?(:whitelist_code)
      $PokemonGlobal.whitelist_code = nil
    end
    if defined?($player) && $player && $player.respond_to?(:whitelist_code)
      $player.whitelist_code = nil
    end
    if defined?(AnilLanRework)
      AnilLanRework.current_whitelist_code = nil rescue nil
    end
    if defined?(pbSave)
      pbSave(true) rescue nil
    end
  end

  def self.garantir_atributo(obj, attr_sym)
    return if obj.respond_to?(attr_sym)
    class << obj
      self
    end.class_eval { attr_accessor attr_sym }
  rescue
  end

  def self.gerar_novo_hash
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

  def self.solicitar_codigo_ao_jogador(prompt)
    25.times do
      Graphics.update rescue nil
      Input.update rescue nil
    end

    prompt_safe = _u(prompt)
    code = nil
    if defined?(pbMessageFreeText)
      code = pbMessageFreeText(prompt_safe, "", false, 6)
    elsif defined?(Kernel.pbMessageFreeText)
      code = Kernel.pbMessageFreeText(prompt_safe, "", false, 6)
    end

    return nil if code.nil? || code.to_s.strip.empty?

    digits = code.to_s.strip.scan(/\d/).join
    return digits if digits =~ /\A\d{6}\z/
    ""
  end

  def self.solicitar_id_ao_jogador(prompt)
    25.times do
      Graphics.update rescue nil
      Input.update rescue nil
    end

    prompt_safe = _u(prompt)
    id = nil
    if defined?(pbMessageFreeText)
      id = pbMessageFreeText(prompt_safe, "", false, 100)
    elsif defined?(Kernel.pbMessageFreeText)
      id = Kernel.pbMessageFreeText(prompt_safe, "", false, 100)
    end

    return nil if id.nil? || id.to_s.strip.empty?
    id.to_s.strip.downcase.gsub(/[^a-z0-9_-]/, '')
  end

  # Envolve a validacao HTTP em retentativas.
  #
  # A primeira tentativa falhava de forma reprodutivel e a segunda passava. Como
  # o erro chega aqui como "rede" (sem resposta do servidor), repetir resolve —
  # e e MUITO importante que resolva: uma falha de rede nesta altura deixa o
  # jogador sem entrar mesmo com o codigo bom, e se a chamada chegou a passar no
  # servidor o codigo ja foi consumido. Ver [[chave-resgate-incompleto]].
  #
  # So se retenta falha de REDE. Se o servidor RESPONDEU a recusar (codigo
  # invalido, ja usado, banido) o resultado seria identico e o jogador so
  # esperava mais tempo pelo mesmo "nao".
  def self.validar_no_servidor(codigo, local_hash, tentativas = 3)
    resultado = nil
    1.upto(tentativas) do |n|
      resultado = validar_no_servidor_uma_vez(codigo, local_hash)
      if resultado[:sucesso]
        AnilLanRework.log("[WHITELIST/VALIDAR] ok na tentativa #{n}/#{tentativas}") rescue nil
        return resultado
      end
      if resultado[:rejeitado]
        AnilLanRework.log("[WHITELIST/VALIDAR] recusado pelo servidor (#{resultado[:mensagem]}) — nao repete") rescue nil
        return resultado
      end
      AnilLanRework.log("[WHITELIST/VALIDAR] tentativa #{n}/#{tentativas} falhou por rede: #{resultado[:mensagem]}") rescue nil
      break if n == tentativas
      # ~0,5s de pausa a 60fps, sem bloquear o desenho do ecra.
      30.times { Graphics.update rescue nil }
    end
    resultado
  end

  def self.validar_no_servidor_uma_vez(codigo, local_hash)
    begin
      ip = AnilLanRework.dedicated_server_ip rescue "127.0.0.1"
      url = "http://#{ip}:7654/api/whitelist?code=#{codigo}&used_by=#{local_hash}"

      headers = {
        "Proxy-Connection" => "Close",
        "Pragma" => "no-cache",
        "User-Agent" => "Mozilla/5.0 (GameClient)"
      }

      res = HTTPLite.get(url, headers)
      if res.is_a?(Hash) && res[:status] == 200
        require "json" rescue nil
        body_str = res[:body].to_s

        parsed = nil
        if defined?(AnilLanPureJSON)
          begin
            parsed = AnilLanPureJSON.decode(body_str)
          rescue
            parsed = parse_whitelist_via_regex(body_str)
          end
        elsif defined?(JSON)
          begin
            parsed = JSON.parse(body_str)
          rescue
            parsed = parse_whitelist_via_regex(body_str)
          end
        else
          parsed = parse_whitelist_via_regex(body_str)
        end

        if parsed && parsed["sucesso"] == true
          return { sucesso: true, id_jogador: parsed["id_jogador"] || local_hash }
        else
          msg = parsed ? _u(parsed["mensagem"].to_s) : "Erro de validacao desconhecido."
          msg = "Codigo invalido ou ja utilizado." if msg.empty?
          return { sucesso: false, mensagem: msg, rejeitado: true }
        end
      else
        status = res.is_a?(Hash) ? res[:status] : "desconhecido"
        return { sucesso: false, mensagem: "Resposta invalida do servidor (HTTP #{status}).", rede: true }
      end
    rescue Exception => e
      AnilLanRework.log("[WHITELIST/ERROR] Falha na conexao: #{e.class}: #{e.message}") rescue nil
      return { sucesso: false, mensagem: "Falha na conexao com o servidor. Tente novamente.", rede: true }
    end
  end

  def self.parse_whitelist_via_regex(body_str)
    info = {}
    if body_str =~ /"sucesso"\s*:\s*(true|false)/i
      info["sucesso"] = ($1.downcase == "true")
    end
    if body_str =~ /"mensagem"\s*:\s*"([^"]+)"/i
      info["mensagem"] = $1
    end
    if body_str =~ /"id_jogador"\s*:\s*"([^"]+)"/i
      info["id_jogador"] = $1
    end
    info
  end

  def self.atualizar_saves_locais(local_hash)
    name = (defined?($player) && $player) ? $player.name.to_s : ""
    clean_name = name.gsub(/[^a-zA-Z0-9_-]/, '').downcase
    clean_name = "jogador" if clean_name.empty?

    is_placeholder = false
    if defined?(AnilLanRework) && AnilLanRework.respond_to?(:placeholder_player_name?)
      is_placeholder = AnilLanRework.placeholder_player_name?(name)
    else
      is_placeholder = %w[unnamed unamed jogador trainer treinador player].include?(clean_name)
    end

    if is_placeholder
      AnilLanRework.log("[WHITELIST] Nome atual é placeholder (#{name.inspect}), cancelando renomeação local.") rescue nil
      return
    end

    new_pid = "#{clean_name}-#{local_hash.downcase}"
    old_save_candidates = []
    old_save_candidates << (DynamicSavePath.multiplayer_path rescue nil)

    begin
      raw_cfg_id = nil
      file = "multiplayer_player.txt"
      if File.exist?(file)
        File.readlines(file, encoding: "UTF-8").each do |line|
          parts = line.strip.split("=", 2)
          next unless parts.size == 2 && parts[0].strip == "id"
          raw_cfg_id = parts[1].to_s.strip
          break
        end
      end

      if raw_cfg_id && !raw_cfg_id.empty?
        legacy_base = raw_cfg_id.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
        unless legacy_base.empty?
          legacy_name = "#{legacy_base}.rxdata"
          legacy_path = File.directory?(System.data_directory) ? File.join(System.data_directory, legacy_name) : "./" + legacy_name
          old_save_candidates << legacy_path
        end
      end
    rescue
    end

    begin
      game_mp_path = File.directory?(System.data_directory) ? File.join(System.data_directory, "Game_mp.rxdata") : "./Game_mp.rxdata"
      old_save_candidates << game_mp_path
    rescue
      old_save_candidates << "./Game_mp.rxdata"
    end

    begin
      file = "multiplayer_player.txt"
      rows = {}
      if File.exist?(file)
        File.readlines(file, encoding: "UTF-8").each do |line|
          parts = line.strip.split("=", 2)
          rows[parts[0].strip] = parts[1].to_s.strip if parts.size == 2
        end
      end
      rows["id"] = new_pid
      File.open(file, "w:UTF-8") do |f|
        f.write(rows.map { |k, v| "#{k}=#{v}\n" }.join)
      end
    rescue => e
      AnilLanRework.log("[WHITELIST] Erro ao gravar multiplayer_player.txt: #{e.message}") rescue nil
    end

    new_save_path = DynamicSavePath.multiplayer_path rescue nil

    if new_save_path
      old_save_candidates.compact.uniq.each do |old_save_path|
        next if old_save_path == new_save_path
        next unless File.exist?(old_save_path)
        begin
          File.rename(old_save_path, new_save_path)
          break
        rescue => e
          AnilLanRework.log("[WHITELIST] Erro ao renomear save local: #{e.message}") rescue nil
        end
      end
    end
  end

  RECOVER_HISTORY_FILE = "multiplayer_recovered_history.txt"

  # Duas, nao dez. O menu e de atalho — quem recuperou dez contas diferentes
  # nesta maquina esta a fazer outra coisa, e a lista longa so atrapalha quem
  # quer voltar a propria partida.
  RECOVER_HISTORY_MAX = 2

  def self.salvar_historico_recuperacao(codigo, player_id, char_name = "")
    cod = codigo.to_s.strip
    pid = player_id.to_s.strip
    # Nao guarda lixo: sem isto uma tentativa falhada entrava no historico e
    # ficava a ser oferecida para sempre.
    return unless cod =~ /\A\d{6}\z/ && !pid.empty?

    entries = ler_historico_recuperacao
    entries.reject! { |e| e[:player_id].to_s.downcase == pid.downcase }
    entries.unshift({
      codigo: cod,
      player_id: pid,
      name: char_name.to_s.strip,
      data: Time.now.strftime("%d/%m/%Y %H:%M")
    })
    entries = entries.first(RECOVER_HISTORY_MAX)
    lines = entries.map { |e| "#{e[:codigo]}|#{e[:player_id]}|#{e[:name]}|#{e[:data]}" }
    File.open(RECOVER_HISTORY_FILE, "w:UTF-8") { |f| f.puts(lines.join("\n")) } rescue nil
  end

  def self.ler_historico_recuperacao
    return [] unless File.exist?(RECOVER_HISTORY_FILE)
    entries = []
    File.readlines(RECOVER_HISTORY_FILE, encoding: "bom|utf-8").each do |line|
      parts = line.strip.split("|")
      next if parts.size < 2
      cod = parts[0].to_s.strip
      pid = parts[1].to_s.strip
      next unless cod =~ /\A\d{6}\z/ && !pid.empty?
      # Ficheiro antigo pode ter o mesmo par repetido.
      next if entries.any? { |e| e[:codigo] == cod && e[:player_id] == pid }
      entries << {
        codigo: cod,
        player_id: pid,
        name: parts[2].to_s.strip,
        data: parts[3].to_s.strip
      }
    end
    entries.first(RECOVER_HISTORY_MAX)
  rescue
    []
  end

  # ─────────────────────────────────────────────────────────────────
  # Recuperar partida do servidor via TCP
  # ─────────────────────────────────────────────────────────────────
  def self.recuperar_partida
    viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    viewport.z = 99998
    bg_sprite = Sprite.new(viewport)
    begin
      bg_sprite.bitmap = Bitmap.new("Graphics/Titles/Backgrounds/multiplayer_menu_bg.png") rescue nil
      if bg_sprite.bitmap
        bg_sprite.x = (Graphics.width - bg_sprite.bitmap.width) / 2
        bg_sprite.y = (Graphics.height - bg_sprite.bitmap.height) / 2
      end

      codigo = nil
      id_jogador = nil

      # Oferece as ultimas recuperacoes bem-sucedidas para escolha rapida.
      historico = ler_historico_recuperacao

      # AVISO, nao pergunta.
      #
      # Quem ja recuperou nesta maquina (tem historico) e o dono da conta a
      # voltar para ela — parar o fluxo com um "deseja continuar?" so acrescenta
      # um clique a cada vez. E o aviso de "substituir a partida local" nem e
      # bem verdade desde o save autoritativo: a copia local e descartavel, a
      # partida de verdade vive na VPS.
      #
      # Sem historico o aviso continua sendo uma PERGUNTA: pode ser a primeira
      # recuperacao nesta maquina, e ai o jogador merece confirmar antes de a
      # partida local sair da frente.
      if SaveData.exists?
        if historico.empty?
          return unless pbConfirmMessage(_u("Aviso: Isso ira substituir sua partida local atual. Deseja continuar?"))
        else
          pbMessage(_u("A partida local sera substituida pela que voce escolher.")) rescue nil
        end
      end

      unless historico.empty?
        opcoes = historico.map do |h|
          rot = h[:name].to_s.empty? ? h[:player_id].to_s : "#{h[:name]} (#{h[:player_id]})"
          _u("#{rot}  [Cod: #{h[:codigo]}]")
        end
        opcoes << _u("Recuperar uma nova partida")
        opcoes << _u("Cancelar")
        idx_nova   = historico.length
        idx_cancel = historico.length + 1

        # pbMessage e NAO pbShowCommands: no nivel global o pbShowCommands espera
        # uma JANELA como 1o argumento, nao texto — e rebenta em .height. O
        # pbMessage cria a janela sozinho e devolve o indice 0-based; o
        # cmdIfCancel e 1-based, entao idx_cancel+1 faz o botao B cair
        # exatamente na opcao "Cancelar".
        escolha = pbMessage(_u("Recuperar qual partida?"), opcoes, idx_cancel + 1)
        if escolha < 0 || escolha == idx_cancel
          return
        elsif escolha < historico.length
          codigo     = historico[escolha][:codigo]
          id_jogador = historico[escolha][:player_id]
        end
        # escolha == idx_nova cai para o fluxo manual abaixo (codigo/id ficam nil)
      end

      if codigo.nil?
        codigo = solicitar_codigo_ao_jogador(_u("Digite o codigo de 6 numeros da sua whitelist para recuperar o save:"))
        if codigo.nil? || codigo.to_s.strip.empty? || codigo.to_s.strip !~ /\A\d{6}\z/
          pbMessage(_u("Operacao cancelada ou codigo invalido."))
          return
        end

        id_jogador = solicitar_id_ao_jogador(_u("Digite o seu ID de jogador (ex: nome-hash):"))
        if id_jogador.nil? || id_jogador.to_s.strip.empty?
          pbMessage(_u("Operacao cancelada ou ID invalido."))
          return
        end
      end

      target_ip = AnilLanRework.dedicated_server_ip rescue "127.0.0.1"
      AnilLanRework.log("[WHITELIST/RECOVER] Conectando a #{target_ip} para recuperar save...")

      begin
        require 'timeout'
        require 'socket'
        require 'json'

        pbMessage(_u("Conectando ao servidor para baixar a partida...\\wtnp[20]"))

        socket = Timeout.timeout(6.0) { TCPSocket.new(target_ip, 7654) }
        req = {
          "type" => "recover_save_file",
          "whitelist_code" => codigo,
          "player_id" => id_jogador
        }
        payload = defined?(AnilLanPureJSON) ? AnilLanPureJSON.encode(req) : req.to_json
        socket.write(payload + "\n")
        socket.flush rescue nil

        # Leitura robusta com buffer acumulado (Joiplay/Android compatível)
        buffer = +""
        response = nil
        deadline = Time.now.to_f + 15.0  # 15 segundos de timeout total

        begin
          while Time.now.to_f < deadline
            # Espera até 5.0 segundos por legibilidade no socket antes de ler
            rs = IO.select([socket], nil, nil, 5.0)
            if rs
              chunk = socket.recv(16384)
              if chunk.nil? || chunk.empty?
                break # EOF
              end
              buffer << chunk.force_encoding("UTF-8")
              if (idx = buffer.index("\n"))
                response = buffer.slice!(0, idx + 1).strip
                break
              end
            else
              # Timeout de 5s sem resposta/dados adicionais
              break
            end
          end
        rescue => e
          # Silencia erros
        end
        response = buffer.strip if response.nil? && !buffer.empty?

        socket.close rescue nil

        if response.nil?
          pbMessage(_u("Erro: Nenhuma resposta recebida do servidor."))
          return
        end

        packet = defined?(AnilLanPureJSON) ? AnilLanPureJSON.decode(response) : JSON.parse(response) rescue nil
        # Recuperar a partida e o que repoe a linhagem: o servidor rodou o
        # testemunho ao entregar, e e este aparelho que fica com ele.
        if packet && packet["type"] == "recover_save_data" && !packet["save_token"].to_s.empty?
          AnilSaveToken.gravar(packet["save_token"]) if defined?(AnilSaveToken)
        end
        if packet && packet["type"] == "recover_save_data" && packet["found"] == true
          encoded_save = packet["save_data"]
          player_id    = packet["player_id"].to_s
          binary_save  = encoded_save.unpack("m0").first
          local_hash   = player_id.split("-").last.to_s.upcase

          file = "multiplayer_player.txt"
          File.open(file, "w:UTF-8") { |f| f.write("id=#{player_id}\n") } rescue nil

          was_multiplayer = (defined?(AnilLanRework) && AnilLanRework.respond_to?(:multiplayer_mode) ? AnilLanRework.multiplayer_mode : false)
          if defined?(AnilLanRework) && AnilLanRework.respond_to?(:multiplayer_mode=)
            AnilLanRework.multiplayer_mode = true
          end
          save_path = SaveData::FILE_PATH.to_s
          if defined?(AnilLanRework) && AnilLanRework.respond_to?(:multiplayer_mode=)
            AnilLanRework.multiplayer_mode = was_multiplayer
          end

          File.open(save_path, "wb") { |f| f.write(binary_save) }

          # ⚠️ O save foi substituido POR FORA do fluxo normal de download.
          #
          # Sem actualizar a versao aqui, este aparelho continuaria a declarar a
          # antiga e o servidor recusaria o proximo upload — logo depois de ter
          # sido ele a entregar este ficheiro. Se o servidor for antigo e nao
          # mandar a versao, esquece-se: sem numero, o guarda e pulado.
          if defined?(AnilSaveVersao)
            if packet["version"].to_i > 0
              AnilSaveVersao.gravar(packet["version"])
            else
              AnilSaveVersao.esquecer(player_id)
            end
          end
          AnilSaveSecoes.limpar! if defined?(AnilSaveSecoes)

          save_data = SaveData.read_from_file(save_path)
          if save_data && save_data[:player]
            save_data[:player].whitelist_code       = codigo
            save_data[:player].client_machine_hash  = local_hash
            save_data[:player].online_id            = local_hash
          end
          if save_data && save_data[:global_metadata]
            save_data[:global_metadata].whitelist_code       = codigo
            save_data[:global_metadata].client_machine_hash  = local_hash
            save_data[:global_metadata].online_id            = local_hash
          end
          if save_data && save_data[:pokemon_system]
            $PokemonSystem = save_data[:pokemon_system]
          end
          File.open(save_path, "wb") { |f| Marshal.dump(save_data, f) }

          # Sincroniza o mtime com o do servidor pós-escrita
          if packet["mtime"].is_a?(Numeric) && packet["mtime"] > 0
            t = Time.at(packet["mtime"])
            File.utime(t, t, save_path) rescue nil
          end

          if defined?(AnilLanRework)
            AnilLanRework.current_whitelist_code = codigo
            AnilLanRework.multiplayer_mode = true
          end

          char_name = (save_data && save_data[:player] ? save_data[:player].name.to_s : "") rescue ""
          salvar_historico_recuperacao(codigo, player_id, char_name)

          pbMessage(_u("Partida recuperada com sucesso! Iniciando jogo..."))
          Game.load(save_data)
          if $game_temp && $game_temp.respond_to?(:anil_pending_multiplayer_instant_connect=)
            $game_temp.anil_pending_multiplayer_instant_connect = true
          end
        else
          msg_erro = _u(packet ? packet["message"].to_s : "Partida nao encontrada para este codigo.")
          pbMessage(_u("Erro na recuperacao: #{msg_erro}"))
        end
      rescue => e
        pbMessage(_u("Falha na conexao: #{e.message}"))
      end
    ensure
      bg_sprite.dispose if bg_sprite
      viewport.dispose if viewport
    end
  end
end

# ─────────────────────────────────────────────────────────────────
# Rebind no módulo AnilLanRework (LÓGICA DA REFERÊNCIA)
# ─────────────────────────────────────────────────────────────────
module AnilLanRework
  class << self
    def persistent_machine_id
      Multiplayer_Whitelist.carregar_ou_gerar_hash_no_save.downcase
    end

    attr_accessor :current_whitelist_code
    alias anil_lan_orig_whitelist_connect connect unless method_defined?(:anil_lan_orig_whitelist_connect)

    def connect(ip, player_id, player_name, char_name, is_host = false, *args)
      vps_ip = AnilLanRework.dedicated_server_ip

      if ip.to_s == "127.0.0.1" && vps_ip != "127.0.0.1"
        ip = vps_ip
      end

      if ip.to_s == "127.0.0.1" || ip.to_s == vps_ip
        AnilLanRework.mark_as_online_session!

        loop_connect = true
        while loop_connect
#region debug-point whitelist-connect-client
          begin
            current_code = Multiplayer_Whitelist.current_code_in_save rescue nil
          rescue
            current_code = nil
          end
          AnilLanRework.log("[WHITELIST/CONNECT] Iniciando ciclo TCP ip=#{ip} incoming_player_id=#{player_id} runtime_id=#{AnilLanRework.get_player_id rescue nil} save_code=#{current_code.inspect} whitelist_mem=#{AnilLanRework.current_whitelist_code.inspect}") rescue nil
          ok_whitelist = Multiplayer_Whitelist.iniciar_validacao
          AnilLanRework.log("[WHITELIST/CONNECT] Resultado iniciar_validacao ok=#{ok_whitelist.inspect} runtime_id=#{AnilLanRework.get_player_id rescue nil} whitelist_mem=#{AnilLanRework.current_whitelist_code.inspect}") rescue nil
          return false unless ok_whitelist

          clean_id = AnilLanRework.get_player_id rescue nil
          player_id = clean_id if clean_id && !clean_id.empty?
          AnilLanRework.log("[WHITELIST/CONNECT] Tentando TCP connect com player_id=#{player_id.inspect} player_name=#{player_name.inspect} online_id=#{$PokemonGlobal.online_id rescue nil}") rescue nil

          ok = anil_lan_orig_whitelist_connect(ip, player_id, player_name, char_name, is_host, *args)

          if ok
            conn = AnilLanRework.connection rescue nil
            if conn && conn.respond_to?(:new_player_id) && conn.new_player_id
              new_pid = conn.new_player_id
              new_oid = conn.new_online_id
              AnilLanRework.log("[WHITELIST/CONNECT] Servidor retornou novo player_id: #{new_pid} (online_id: #{new_oid})") rescue nil
              
              # Atualiza no save
              if defined?($PokemonGlobal) && $PokemonGlobal
                $PokemonGlobal.client_machine_hash = new_oid
                $PokemonGlobal.online_id = new_oid.upcase rescue nil
              end
              if defined?($player) && $player
                $player.client_machine_hash = new_oid
                $player.online_id = new_oid.upcase rescue nil
              end
              
              # Grava no multiplayer_machine_id.txt e atualiza cache em memoria do machine ID
              if new_oid
                begin
                  File.open("multiplayer_machine_id.txt", "w:UTF-8") { |f| f.write(new_oid.upcase) }
                  if AnilLanRework.instance_variable_defined?(:@persistent_machine_id)
                    AnilLanRework.instance_variable_set(:@persistent_machine_id, new_oid.downcase)
                  end
                rescue => e
                  AnilLanRework.log("[WHITELIST] Erro ao gravar multiplayer_machine_id.txt: #{e.message}") rescue nil
                end
              end
              
              # Grava no multiplayer_player.txt
              file = "multiplayer_player.txt"
              begin
                rows = {}
                if File.exist?(file)
                  File.readlines(file, encoding: "UTF-8").each do |line|
                    parts = line.strip.split("=", 2)
                    rows[parts[0].strip] = parts[1].to_s.strip if parts.size == 2
                  end
                end
                rows["id"] = new_pid
                File.open(file, "w:UTF-8") do |f|
                  f.write(rows.map { |k, v| "#{k}=#{v}\n" }.join)
                end
              rescue => e
                AnilLanRework.log("[WHITELIST] Erro ao gravar multiplayer_player.txt: #{e.message}") rescue nil
              end
              
              # Renomeia save local
              new_save_path = DynamicSavePath.multiplayer_path rescue nil
              if new_save_path
                old_save_id = player_id.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
                old_save_name = "#{old_save_id}.rxdata"
                old_save_path = File.directory?(System.data_directory) ? File.join(System.data_directory, old_save_name) : "./" + old_save_name
                if File.exist?(old_save_path) && old_save_path != new_save_path
                  begin
                    File.rename(old_save_path, new_save_path)
                    AnilLanRework.log("[WHITELIST] Renomeado save local de #{old_save_path} para #{new_save_path}") rescue nil
                  rescue => e
                    AnilLanRework.log("[WHITELIST] Erro ao renomear save local: #{e.message}") rescue nil
                  end
                end
              end
              
              if defined?(pbSave)
                pbSave(true) rescue nil
              end
            end
            return true
          else
            err_msg = AnilLanRework.last_error_message.to_s

            if err_msg.start_with?("BANNED:")
              return false
            end

            if err_msg =~ /código|codigo|whitelist|inválido|invalido|utilizado|used/i
              Multiplayer_Whitelist.limpar_codigo_salvo rescue nil

              msg_exibir = Multiplayer_Whitelist._u(err_msg.to_s.strip)
              msg_exibir = "Codigo invalido ou ja utilizado!" if msg_exibir.empty? || msg_exibir.include?("Conexao") || msg_exibir.include?("encerrada") || msg_exibir.include?("fechada")

              if defined?(pbMessage)
                pbMessage(Multiplayer_Whitelist._u("Erro no Acesso: #{msg_exibir}"))
              elsif defined?(Kernel.pbMessage)
                Kernel.pbMessage(Multiplayer_Whitelist._u("Erro no Acesso: #{msg_exibir}"))
              end

              AnilLanRework.log("[WHITELIST/TCP_FAIL] TCP rejeitado por whitelist (#{err_msg}), limpando e re-perguntando.") rescue nil
            else
              AnilLanRework.log("[WHITELIST/TCP_FAIL] Falha de conexao temporaria: #{err_msg}. Mantendo codigo salvo.") rescue nil
              return false
            end
          end
#endregion debug-point whitelist-connect-client
        end
      else
        anil_lan_orig_whitelist_connect(ip, player_id, player_name, char_name, is_host, *args)
      end
    end
  end
end

module Multiplayer_Whitelist
  def self.current_code_in_save
    code = nil
    code = $PokemonGlobal.whitelist_code.to_s.strip if defined?($PokemonGlobal) && $PokemonGlobal && $PokemonGlobal.respond_to?(:whitelist_code)
    code = $player.whitelist_code.to_s.strip if (code.nil? || code.empty?) && defined?($player) && $player && $player.respond_to?(:whitelist_code)
    code = nil if code.to_s.empty?
    code
  end
end

module Game
  class << self
    alias anil_whitelist_orig_start_new start_new unless method_defined?(:anil_whitelist_orig_start_new)

    def start_new
      if defined?(AnilLanRework) && !AnilLanRework.multiplayer_mode
        viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
        viewport.z = 99998
        bg_sprite = Sprite.new(viewport)
        bg_sprite.bitmap = Bitmap.new("Graphics/Titles/Backgrounds/multiplayer_menu_bg.png") rescue nil
        if bg_sprite.bitmap
          bg_sprite.x = (Graphics.width - bg_sprite.bitmap.width) / 2
          bg_sprite.y = (Graphics.height - bg_sprite.bitmap.height) / 2
        end

        # Pergunta ao jogador se deseja iniciar a partida no modo Multiplayer
        if pbConfirmMessage(Multiplayer_Whitelist._u("Deseja ativar o modo Multiplayer para esta nova partida?"))
          # Limpa estado anterior para evitar clonagem de hash
          if defined?(AnilLanRework)
            AnilLanRework.instance_variable_set(:@persistent_machine_id, nil)
            AnilLanRework.instance_variable_set(:@self_internal_id, nil)
            AnilLanRework.current_whitelist_code = nil rescue nil
          end
          # Gera hash novo para esta partida (evita clonagem)
          $new_game_machine_hash = Multiplayer_Whitelist.gerar_novo_hash

          # Inicia validação de whitelist (pede o código aqui na tela de título)
          ok = Multiplayer_Whitelist.iniciar_validacao
          if ok
            AnilLanRework.multiplayer_mode = true
            # NÃO agenda auto-connect aqui — será agendado DEPOIS da intro, quando
            # o código for injetado no $PokemonGlobal (evita pedido duplo)
            # Salva temporariamente para injetar após a inicialização do novo jogo
            @pending_whitelist_code = AnilLanRework.current_whitelist_code
          else
            # Se cancelar/falhar, volta ao menu inicial de títulos
            pbMessage(Multiplayer_Whitelist._u("Operacao cancelada. Retornando ao menu principal."))
            $scene = pbCallTitle
            bg_sprite.dispose rescue nil
            viewport.dispose rescue nil
            $new_game_machine_hash = nil
            return
          end
        else
          AnilLanRework.multiplayer_mode = false
          AnilLanRework.disconnect(false) rescue nil
        end
        bg_sprite.dispose rescue nil
        viewport.dispose rescue nil
      end
      
      anil_whitelist_orig_start_new
      
      # Injeta a whitelist e salva se foi ativado o multiplayer no Novo Jogo
      if defined?(AnilLanRework) && AnilLanRework.multiplayer_mode && @pending_whitelist_code
        code = @pending_whitelist_code
        @pending_whitelist_code = nil
        local_hash = Multiplayer_Whitelist.carregar_ou_gerar_hash_no_save
        Multiplayer_Whitelist.aplicar_validacao(code, local_hash, $jogador_id_validado)
        # AGORA sim agenda o auto-connect (código já injetado no $PokemonGlobal)
        $game_temp.anil_pending_multiplayer_auto_connect = true rescue nil
      end
      
      $new_game_machine_hash = nil
    end
  end
end