#===============================================================================
# MÓDULO MULTIPLAYER: LAN & CO-OP LOCAL (REWORK)
# Contém o servidor local, lobby de redes locais e descoberta por UDP
#===============================================================================
require 'socket'
unless defined?(Mutex)
  class Mutex
    def synchronize
      yield
    end
  end
end

unless defined?(LanCableReworkServer)
  class LanCableReworkServer
    def initialize(bind_ip = "0.0.0.0")
      @bind_ip = bind_ip
      @clients = {}
      @mutex = Mutex.new
      @host_id = nil
      @session_token = nil
      @last_snapshot = nil
      @server_socket = nil
      @discovery_socket = nil
      @host_machine_name = begin Socket.gethostname.to_s rescue "Host" end
      @battle_turn_seeds = {}
      @seeds_mutex = Mutex.new
      @items_mutex = Mutex.new
      @dropped_items = {}
    end

    def run
      unless @server_socket
        # Sempre escutamos em todas as redes para evitar bloqueios de firewall específicos,
        # mas usamos o @bind_ip para nos identificarmos na rede (discovery).
        @server_socket = TCPServer.new("0.0.0.0", AnilLanRework::SERVER_PORT)
        @server_socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, true) rescue nil
      end
      start_discovery_listener
      AnilLanRework.log("embedded server listening on ALL (0.0.0.0) port=#{AnilLanRework::SERVER_PORT} advertising=#{@bind_ip}")
      loop do
        socket = @server_socket.accept
        Thread.new(socket) { |client_socket| handle_client(client_socket) }
      end
    end

    def start_discovery_listener
      return if @discovery_thread&.alive?
      @discovery_thread = Thread.new do
        @discovery_socket ||= UDPSocket.new
        @discovery_socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, true) rescue nil
        @discovery_socket.bind("0.0.0.0", AnilLanRework::DISCOVERY_PORT)
        loop do
          begin
            data, addr = @discovery_socket.recvfrom(4096)
          rescue SystemCallError
            next
          rescue
            next
          end
          packet = AnilLanPureJSON.decode(data.to_s.strip)
          next unless packet.is_a?(Hash) && packet["type"].to_s == "discover_host" && packet["magic"].to_s == AnilLanRework::DISCOVERY_MAGIC
          response = discovery_response
          @discovery_socket.send(AnilLanPureJSON.encode(response), 0, addr[3], addr[1]) rescue nil if response
        end
      end
    end

    def discovery_response
      host_row, host_id, session_token = nil, nil, nil
      @mutex.synchronize do
        host_id = @host_id || "host"
        session_token = @session_token || "token"
        host_row = @clients[host_id]
      end
      
      # Detectar e priorizar IP Wi-Fi/LAN local
      all_ips = AnilLanRework.local_ipv4_candidates rescue []
      wifi_ips = all_ips.select { |ip| AnilLanRework.detect_network_type(ip).include?("Wi-Fi") || AnilLanRework.detect_network_type(ip) == "LAN" }
      
      # Se houver IPs Wi-Fi, usa o primeiro como anunciado principal
      if !wifi_ips.empty?
        announced_ip = wifi_ips.first
      elsif @bind_ip && @bind_ip != "0.0.0.0"
        announced_ip = @bind_ip
      else
        announced_ip = (Socket.ip_address_list.find { |ai| ai.ipv4? && !ai.ipv4_loopback? }&.ip_address || "")
      end

      net_type = AnilLanRework.detect_network_type(announced_ip)
      AnilLanRework.log("discovery_response announcing ip=#{announced_ip} type=#{net_type} all_ips=#{all_ips.inspect}")
      
      {
        "type"          => "discover_ack",
        "magic"         => AnilLanRework::DISCOVERY_MAGIC,
        "server_port"   => AnilLanRework::SERVER_PORT,
        "ip"            => announced_ip,
        "network_type"  => net_type,
        "all_ips"       => all_ips,
        "host_id"       => host_id.to_s,
        "display_id"    => host_row ? host_row[:display_id].to_s : "",
        "host_name"     => host_row ? host_row[:name].to_s : @host_machine_name,
        "session_token" => session_token.to_s
      }
    end

    def handle_client(socket)
      player_id = nil
      buffer = +""
      loop do
        begin
          chunk = socket.recv(4096)
        rescue Errno::ECONNRESET, Errno::EPIPE, IOError => e
          AnilLanRework.log("client recv error #{e.class}: #{e.message}") rescue nil
          break
        rescue => e
          AnilLanRework.log("client unexpected error #{e.class}: #{e.message}") rescue nil
          break
        end
        break if chunk.nil? || chunk.empty?
        buffer << chunk
        while (idx = buffer.index("\n"))
          line = buffer.slice!(0..idx).to_s.strip
          next if line.empty?
          packet = AnilLanPureJSON.decode(line)
          next unless packet.is_a?(Hash)

          if player_id
            packet["sender_id"] ||= player_id
            packet["peer_id"] ||= player_id
          end

          case packet["type"]
          when "join"
            joined_id = handle_join(socket, packet)
            player_id = joined_id if joined_id && !joined_id.to_s.empty?
            if player_id
              packet["sender_id"] ||= player_id
              packet["peer_id"] ||= player_id
            end
          when "player_state"
            next if player_id.to_s.empty?
            update_player_state(packet)
            broadcast(packet, except: player_id)
          when "world_snapshot"
            next if player_id.to_s.empty?
            if player_id == @host_id
              @last_snapshot = packet
              broadcast(packet, except: player_id)
            end
          when "ping"
            send_to(player_id, { "type" => "pong", "session" => @session_token })
          when "request_battle_seed"
            handle_request_battle_seed(socket, packet)
          when "request_turn_seed"
            handle_request_turn_seed(player_id, packet)
          when "request_dropped_items"
            handle_request_dropped_items(socket, packet)
          when "request_drop_item"
            handle_request_drop_item(player_id, packet)
          when "claim_dropped_item"
            handle_claim_dropped_item(socket, player_id, packet)
          else
            next if player_id.to_s.empty?
            packet["to_id"] ? send_to(packet["to_id"].to_s, packet) : broadcast(packet, except: player_id)
          end
        end
      end
    ensure
      remove_client(player_id, socket) if player_id
      socket.close rescue nil
    end

    def handle_join(socket, packet)
      player_id = packet["internal_id"].to_s
      is_host = packet["host"] == true
      duplicate = false
      replaced_socket = nil

      @mutex.synchronize do
        if @clients.key?(player_id)
          if is_host
            duplicate = true
          else
            replaced_socket = @clients[player_id][:socket]
          end
        end
        unless duplicate
          @clients[player_id] = {
            :socket      => socket,
            :internal_id => player_id,
            :display_id  => packet["display_id"].to_s,
            :name        => packet["name"].to_s,
            :map_id      => packet["map_id"].to_i,
            :x           => packet["x"].to_i,
            :y           => packet["y"].to_i,
            :real_x      => packet["real_x"].to_i,
            :real_y      => packet["real_y"].to_i,
            :dir         => packet["dir"].to_i <= 0 ? 2 : packet["dir"].to_i,
            :pattern     => packet["pattern"].to_i,
            :char        => packet["char"].to_s,
            :follower    => packet["follower"].to_s,
            :status      => packet["status"].to_s,
            :battle_busy => packet["battle_busy"] == true,
            :menu_open   => packet["menu_open"] == true,
            :occupied_status => packet["occupied_status"] ? packet["occupied_status"].to_s : nil
          }
          if is_host || @host_id.nil?
            @host_id = player_id
            @session_token = make_token
          end
        end
      end

      if duplicate
        socket.write(AnilLanPureJSON.encode({ "type" => "error", "message" => "ID duplicado" }) + "\n") rescue nil
        return nil
      end

      if replaced_socket && replaced_socket != socket
        replaced_socket.close rescue nil
      end

      send_to(player_id, {
        "type"          => "join_ack",
        "host_id"       => @host_id,
        "session_token" => @session_token,
        "server_time"   => Time.now.to_i,
        "players"       => snapshot_players
      })
      broadcast({
        "type"        => "peer_joined",
        "peer_id"     => player_id,
        "internal_id" => player_id,
        "display_id"  => packet["display_id"].to_s,
        "name"        => packet["name"].to_s,
        "map_id"      => packet["map_id"].to_i,
        "x"           => packet["x"].to_i,
        "y"           => packet["y"].to_i,
        "real_x"      => packet["real_x"].to_i,
        "real_y"      => packet["real_y"].to_i,
        "dir"         => packet["dir"].to_i,
        "pattern"     => packet["pattern"].to_i,
        "char"        => packet["char"].to_s,
        "follower"    => packet["follower"].to_s,
        "status"      => packet["status"],
        "battle_busy" => packet["battle_busy"] == true,
        "menu_open"   => packet["menu_open"] == true,
        "occupied_status" => packet["occupied_status"] ? packet["occupied_status"].to_s : nil
      }, except: player_id)
      send_to(player_id, @last_snapshot) if @last_snapshot && player_id != @host_id
      player_id
    end

    def update_player_state(packet)
      @mutex.synchronize do
        sender_id = (packet["sender_id"] || packet["internal_id"] || packet["peer_id"]).to_s
        row = @clients[sender_id]
        if row
          row[:map_id] = packet["map_id"].to_i
          row[:x] = packet["x"].to_i
          row[:y] = packet["y"].to_i
          row[:real_x] = packet["real_x"].to_i if packet.key?("real_x")
          row[:real_y] = packet["real_y"].to_i if packet.key?("real_y")
          row[:dir] = packet["dir"].to_i
          row[:pattern] = packet["pattern"].to_i if packet.key?("pattern")
          row[:char] = packet["char"].to_s
          row[:follower] = packet["follower"].to_s
          row[:status] = packet["status"].to_s if packet.key?("status")
          row[:battle_busy] = packet["battle_busy"] == true if packet.key?("battle_busy")
          row[:menu_open] = packet["menu_open"] == true if packet.key?("menu_open")
          row[:occupied_status] = packet["occupied_status"].to_s if packet.key?("occupied_status")
          row[:coop_wild_invites_enabled] = (packet["coop_wild_invites_enabled"] != false) if packet.key?("coop_wild_invites_enabled")
          row[:coop_trainer_invites_enabled] = (packet["coop_trainer_invites_enabled"] != false) if packet.key?("coop_trainer_invites_enabled")
        end
      end
    end

    def snapshot_players
      @mutex.synchronize do
        @clients.values.map do |row|
          {
            "internal_id" => row[:internal_id],
            "display_id"  => row[:display_id],
            "name"        => row[:name],
            "map_id"      => row[:map_id],
            "x"           => row[:x],
            "y"           => row[:y],
            "real_x"      => row[:real_x],
            "real_y"      => row[:real_y],
            "dir"         => row[:dir],
            "pattern"     => row[:pattern],
            "char"        => row[:char],
            "follower"    => row[:follower],
            "status"      => row[:status],
            "battle_busy" => row[:battle_busy] == true,
            "menu_open"   => row[:menu_open] == true,
            "occupied_status" => row[:occupied_status] ? row[:occupied_status].to_s : nil,
            "coop_wild_invites_enabled" => row[:coop_wild_invites_enabled] != false,
            "coop_trainer_invites_enabled" => row[:coop_trainer_invites_enabled] != false
          }
        end
      end
    end

    def send_to(player_id, packet)
      socket = nil
      @mutex.synchronize { row = @clients[player_id]; socket = row[:socket] if row }
      socket.write(AnilLanPureJSON.encode(packet) + "\n") if socket
    rescue
    end

    def broadcast(packet, except: nil)
      sockets = []
      @mutex.synchronize { @clients.each { |id, row| sockets << row[:socket] unless id == except } }
      encoded = AnilLanPureJSON.encode(packet) + "\n"
      sockets.each { |sock| sock.write(encoded) rescue nil }
    end

    def remove_client(player_id, socket = nil)
      reassigned_host = nil
      removed = false
      @mutex.synchronize do
        row = @clients[player_id]
        if row && (!socket || row[:socket] == socket)
          @clients.delete(player_id)
          removed = true
          if @host_id == player_id
            @host_id = @clients.keys.first
            if @host_id
              @session_token = make_token
              reassigned_host = @host_id
            else
              @session_token = nil
              @last_snapshot = nil
            end
          end
        end
      end
      return unless removed
      broadcast({ "type" => "peer_left", "peer_id" => player_id })
      if reassigned_host
        broadcast({
          "type"          => "session_rehost",
          "host_id"       => reassigned_host,
          "session_token" => @session_token
        })
      end
    end

    def make_token
      "%08x%08x" % [rand(0x1_0000_0000), rand(0x1_0000_0000)]
    end

    def handle_request_battle_seed(socket, packet)
      battle_id = packet["battle_id"].to_s
      seed = rand(0x3FFF_FFFF)
      resp = {
        "type" => "battle_seed_response",
        "battle_id" => battle_id,
        "seed" => seed
      }
      socket.write(AnilLanPureJSON.encode(resp) + "\n") rescue nil
    end

    def handle_request_turn_seed(sender_id, packet)
      battle_id = packet["battle_id"].to_s
      turn = packet["turn"].to_i
      
      @battle_turn_seeds ||= {}
      @seeds_mutex ||= Mutex.new
      
      key = "#{battle_id}_#{turn}"
      
      @seeds_mutex.synchronize do
        @battle_turn_seeds[key] ||= []
        @battle_turn_seeds[key] << sender_id unless @battle_turn_seeds[key].include?(sender_id)
        
        if @battle_turn_seeds[key].length >= 2
          turn_seed = rand(0x3FFF_FFFF)
          resp = {
            "type" => "turn_seed_response",
            "battle_id" => battle_id,
            "turn" => turn,
            "seed" => turn_seed
          }
          @battle_turn_seeds[key].each do |pid|
            send_to(pid, resp)
          end
          @battle_turn_seeds.delete(key)
        end
      end
    end

    def handle_request_dropped_items(socket, packet)
      map_id = packet["map_id"].to_s
      @dropped_items ||= {}
      items = @dropped_items[map_id] || []
      resp = {
        "type" => "sync_dropped_items",
        "map_id" => map_id.to_i,
        "items" => items
      }
      socket.write(AnilLanPureJSON.encode(resp) + "\n") rescue nil
    end

    def handle_request_drop_item(sender_id, packet)
      map_id = packet["map_id"].to_s
      item_id = packet["item_id"].to_s
      x = packet["x"].to_i
      y = packet["y"].to_i
      
      @dropped_items ||= {}
      @items_mutex ||= Mutex.new
      event_id = nil
      
      @items_mutex.synchronize do
        @dropped_items[map_id] ||= []
        loop do
          event_id = 900000 + rand(99999)
          break unless @dropped_items[map_id].any? { |itm| itm["id"] == event_id }
        end
        
        item_data = {
          "id" => event_id,
          "item_id" => item_id,
          "x" => x,
          "y" => y
        }
        @dropped_items[map_id] << item_data
      end
      
      broadcast({
        "type" => "dropped_item_spawn",
        "map_id" => map_id.to_i,
        "event_id" => event_id,
        "item_id" => item_id,
        "x" => x,
        "y" => y
      })
    end

    def handle_claim_dropped_item(socket, sender_id, packet)
      map_id = packet["map_id"].to_s
      event_id = packet["event_id"].to_i
      
      @dropped_items ||= {}
      @items_mutex ||= Mutex.new
      success = false
      item_id = nil
      
      @items_mutex.synchronize do
        if @dropped_items[map_id]
          idx = @dropped_items[map_id].index { |itm| itm["id"] == event_id }
          if idx
            item_id = @dropped_items[map_id][idx]["item_id"]
            @dropped_items[map_id].delete_at(idx)
            success = true
          end
        end
      end
      
      if success
        socket.write(AnilLanPureJSON.encode({
          "type" => "claim_dropped_item_result",
          "event_id" => event_id,
          "item_id" => item_id,
          "success" => true
        }) + "\n") rescue nil
        
        broadcast({
          "type" => "dropped_item_pickup",
          "map_id" => map_id.to_i,
          "event_id" => event_id
        }, except: sender_id)
      else
        socket.write(AnilLanPureJSON.encode({
          "type" => "claim_dropped_item_result",
          "event_id" => event_id,
          "success" => false
        }) + "\n") rescue nil
      end
    end
  end
end


# --- Scene_MultiplayerLobby_Rework ---
class Scene_MultiplayerLobby_Rework
  PLAYER_CFG = "multiplayer_player.txt"
  IP_CFG     = "multiplayer_ip.txt"

  def main
    @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 99_999
    @sprites = {}
    create_background
    create_windows
    load_config
    $anil_fade_viewport&.dispose rescue nil
    $anil_fade_viewport = nil
    Graphics.transition(20)
    @exit = false
    loop do
      Graphics.update
      Input.update
      update
      break if @exit || $scene != self
    end
    Graphics.freeze
    dispose
  end

  def main_with_action(action)
    @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 99_999
    @sprites = {}
    @action_succeeded = false
    create_background
    create_action_windows
    load_config
    $anil_fade_viewport&.dispose rescue nil
    $anil_fade_viewport = nil
    Graphics.transition(20)
    @exit = false

    case action
    when :host
      do_host
    when :join
      do_join
    end

    if @exit
      dispose
      return @action_succeeded
    end

    loop do
      Graphics.update
      Input.update
      update_action_result
      break if @exit || $scene != self
    end
    Graphics.freeze unless @action_succeeded
    dispose
    @action_succeeded
  end

  def create_background
    @sprites["bg"] = BitmapSprite.new(Graphics.width, Graphics.height, @viewport)
    @sprites["bg"].bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(12, 12, 28))
  end

  def create_windows
    @sprites["title"] = Window_UnformattedTextPokemon.newWithSize(
      _INTL("Multijogador LAN (Rework)"), 0, 4, Graphics.width, 40, @viewport
    )
    @sprites["title"].baseColor = Color.new(255, 220, 50)
    @sprites["status"] = Window_UnformattedTextPokemon.newWithSize(
      "", 8, 50, Graphics.width - 16, 180, @viewport
    )
    commands = [
      _INTL("Host (rework)"),
      _INTL("Entrar (rework)"),
      _INTL("Trocar Personagem"),
      _INTL("Desconectar"),
      _INTL("Fechar")
    ]
    @sprites["cmd"] = Window_CommandPokemon.new(commands)
    @sprites["cmd"].viewport = @viewport
    @sprites["cmd"].x = (Graphics.width - @sprites["cmd"].width) / 2
    @sprites["cmd"].y = 240
  end

  def create_action_windows
    @sprites["title"] = Window_UnformattedTextPokemon.newWithSize(
      _INTL("Multijogador LAN (Rework)"), 0, 4, Graphics.width, 40, @viewport
    )
    @sprites["title"].baseColor = Color.new(255, 220, 50)
    @sprites["status"] = Window_UnformattedTextPokemon.newWithSize(
      "", 8, 50, Graphics.width - 16, 220, @viewport
    )
  end

  def dispose
    pbDisposeSpriteHash(@sprites)
    @viewport.dispose
  end

  def set_status(text)
    @sprites["status"].text = text rescue nil
  end

  def load_config
    AnilLanRework.update_player_config
    @player_id   = read_cfg(PLAYER_CFG, "id", "jogador#{rand(9000) + 1000}")
    @player_name = read_cfg(PLAYER_CFG, "nome", "Treinador")
    @player_char = read_cfg(PLAYER_CFG, "char", "POKEMONTRAINER_RojoArio")
    @server_ip   = read_cfg(IP_CFG, "ip", "127.0.0.1")
    status = AnilLanRework.ui_format("Jogador: {1}\n", @player_name)
    status += AnilLanRework.ui_format("IP do host: {1}\n\n", @server_ip)
    if AnilLanRework.connected?
      status += _INTL("STATUS: Conectado")
    else
      status += _INTL("STATUS: Desconectado\nEste lobby usa o rework isolado.")
    end
    set_status(status)
  end

  def read_cfg(file, key, default)
    return default unless File.exist?(file)
    File.readlines(file, encoding: "UTF-8").each do |line|
      parts = line.strip.split("=", 2)
      return parts[1].strip if parts.size == 2 && parts[0].strip == key
    end
    default
  end

  def write_cfg(file, key, value)
    rows = {}
    if File.exist?(file)
      File.readlines(file, encoding: "UTF-8").each do |line|
        parts = line.strip.split("=", 2)
        rows[parts[0].strip] = parts[1].to_s.strip if parts.size == 2
      end
    end
    rows[key.to_s] = value.to_s
    File.open(file, "wb") do |f|
      f.write(rows.map { |cfg_key, cfg_value| "#{cfg_key}=#{cfg_value}\n" }.join.encode(Encoding::UTF_8))
    end
  rescue => e
    AnilLanRework.log("write_cfg error #{e.class}: #{e.message}")
  end

  def update
    @sprites["cmd"].update
    if Input.trigger?(Input::BACK)
      pbPlayCancelSE
      @exit = true
      return
    end
    return unless Input.trigger?(Input::USE)
    pbPlayDecisionSE
    case @sprites["cmd"].index
    when 0 then do_host
    when 1 then do_join
    when 2 then do_character_select
    when 3 then do_disconnect
    when 4
      @exit = true
    end
  end

  def update_action_result
    return unless Input.trigger?(Input::BACK) || Input.trigger?(Input::USE)
    pbPlayCancelSE
    @exit = true
  end

  def resolved_player_internal_id
    AnilLanRework.resolve_internal_id(@player_id)
  rescue
    @player_id.to_s
  end

  def remember_connected_session(ip, hint = nil)
    host_id = AnilLanRework.connection&.host_id.to_s
    return if host_id.empty?
    host_name = ""
    display_id = ""
    if hint.is_a?(Hash)
      host_name = hint["host_name"].to_s
      display_id = hint["display_id"].to_s
    end
    if host_name.empty?
      peer = AnilLanRework.players[host_id]
      host_name = peer.name.to_s if peer && !peer.name.to_s.empty?
    end
    host_name = ip.to_s if host_name.empty?
    AnilLanRework::RememberedSessions.remember_session(
      ip,
      host_id: host_id,
      host_name: host_name,
      display_id: display_id,
      session_token: (AnilLanRework.connection&.session_token.to_s)
    )
  end

  def remembered_session_status_label(entry, probe)
    online = probe.is_a?(Hash) && probe["ok"] == true && probe["host_id"].to_s == entry["host_id"].to_s
    pending = probe.is_a?(Hash) ? probe["pending_amount"].to_i : 0
    state = online ? "online" : "offline"
    seller = entry["host_name"].to_s
    seller = entry["display_id"].to_s if seller.empty?
    seller = entry["host_id"].to_s if seller.empty?
    label = "#{seller} - #{entry['last_ip']} [#{state}]"
    label += " $#{pending}" if pending > 0
    label
  end

  def do_host
    # Traz a escolha do IP pro Lobby
    ips = AnilLanRework.local_ipv4_candidates
    ip_commands = ips.map { |ip| "#{ip} [#{AnilLanRework.detect_network_type(ip)}]" }
    ip_commands << _INTL("Todas as redes (0.0.0.0)")
    ip_commands << _INTL("Cancelar")

    choice = pbMessage(_INTL("Em qual rede deseja abrir o servidor?"), ip_commands, ip_commands.length)
    return if choice < 0 || choice == ip_commands.length - 1

    bind_ip = (choice == ip_commands.length - 2) ? "0.0.0.0" : ips[choice]
    connect_ip = (bind_ip == "0.0.0.0") ? "127.0.0.1" : bind_ip

    set_status(_INTL("A iniciar servidor em {1}...", bind_ip))
    Graphics.update

    unless @server_thread&.alive?
      server_error = nil
      @server_thread = Thread.new do
        begin
          LanCableReworkServer.new(bind_ip).run
        rescue => e
          server_error = "#{e.class}: #{e.message}"
          AnilLanRework.log("server thread error #{e.class}: #{e.message}")
        end
      end

      ready = false
      start_time = Time.now.to_f
      while Time.now.to_f - start_time < 3.0
        break unless @server_thread&.alive?
        begin
          probe = TCPSocket.new(connect_ip, AnilLanRework::SERVER_PORT)
          probe.close
          ready = true
          break
        rescue => e
          sleep(0.05)
        end
      end

      unless ready
        set_status(AnilLanRework.ui_format("ERRO: servidor nao iniciou no IP {1}.\nPressione X/Z para fechar.", bind_ip))
        return
      end
    end

    ok = begin
      AnilLanRework.connect(connect_ip, @player_id, @player_name, @player_char, true)
    rescue => e
      false
    end

    if ok
      @action_succeeded = true
      set_status(AnilLanRework.ui_format(
        "Servidor do rework iniciado em {1}. Es o host desta sessao.",
        connect_ip
      ))
      Graphics.update
      AnilLanRework.request_same_map_transfer!("host_connect_same_map", 4)
      $scene = Scene_Map.new
      @exit = true
    else
      set_status(AnilLanRework.ui_format("ERRO: {1}\n\nPressiona X/Z para fechar.", AnilLanRework.last_error_message.to_s))
    end
  end

  def do_character_select
    pbFadeOutIn do
      AnilLanRework.clear_input_buffer
      scene = Scene_CharacterSelect.new
      scene.main
      AnilLanRework.wipe_stuck_graphics! rescue nil
      AnilLanRework.clear_input_buffer
      # Re-carrega configurações após a mudança de personagem
      load_config
    end
  end

  def do_join
    set_status(_INTL("A procurar hosts na rede local..."))
    Graphics.update

    hosts = AnilLanRework.discover_hosts

    if hosts.empty?
      set_status(AnilLanRework.ui_format(
        "Nenhum host LAN respondeu.\nA tentar IP salvo: {1}...",
        @server_ip
      ))
      Graphics.update
      target_ip = @server_ip.to_s
      chosen = nil
    else
      commands = hosts.map { |h| AnilLanRework.discovered_host_label(h) }
      commands << _INTL("Usar IP salvo ({1})", @server_ip)
      commands << _INTL("Cancelar")

      choice = pbMessage(_INTL("Escolha um Host online:"), commands, commands.length)
      if choice < 0 || choice == commands.length - 1
        @exit = true
        return
      elsif choice == commands.length - 2
        target_ip = @server_ip.to_s
        chosen = nil
      else
        chosen = hosts[choice]
        target_ip = chosen["ip"].to_s
        @server_ip = target_ip
        write_cfg(IP_CFG, "ip", @server_ip)
      end
    end
    Graphics.update

    alt_ips = chosen ? Array(chosen["alt_ips"]) : []
    ok = begin
      AnilLanRework.connect(target_ip, @player_id, @player_name, @player_char, false, alt_ips)
    rescue Errno::EPIPE, Errno::ECONNRESET, IOError => e
      AnilLanRework.log("join connect broken pipe #{e.class}: #{e.message}")
      false
    rescue => e
      AnilLanRework.log("join connect error #{e.class}: #{e.message}")
      false
    end

    if ok
      @action_succeeded = true
      remember_connected_session(target_ip, chosen)
      net_type = AnilLanRework.detect_network_type(target_ip)
      set_status(AnilLanRework.ui_format("Ligado ao rework via {1} ({2}).", net_type, target_ip))
      Graphics.update
      if $joiplay
        AnilLanRework.log("joiplay join_connect: queueing same-map transfer")
      end
      AnilLanRework.request_same_map_transfer!("join_connect_same_map", 4)
      $scene = Scene_Map.new
      @exit = true
    else
      set_status(AnilLanRework.ui_format(
        "ERRO: {1}\n\nPressiona X/Z para fechar.",
        AnilLanRework.last_error_message.to_s
      ))
    end
  end

  def do_sessions
    entries = AnilLanRework::RememberedSessions.load_entries
    if entries.empty?
      set_status(_INTL("Ainda nao ha sessoes guardadas."))
      return
    end
    set_status(_INTL("A consultar sessoes guardadas..."))
    Graphics.update
    player_internal_id = resolved_player_internal_id
    probes = entries.map { |entry| AnilLanRework::RememberedSessions.probe_session(entry, player_internal_id) }
    commands = entries.each_with_index.map { |entry, idx| remembered_session_status_label(entry, probes[idx]) }
    commands << _INTL("Cancelar")
    choice = pbMessage(_INTL("Sessoes Online"), commands, commands.length)
    return if choice < 0 || choice >= entries.length

    entry = entries[choice]
    probe = probes[choice]
    if probe.is_a?(Hash) && !probe["host_name"].to_s.empty?
      entry = AnilLanRework::RememberedSessions.remember_session(
        entry["last_ip"],
        host_id: entry["host_id"],
        host_name: probe["host_name"],
        display_id: entry["display_id"],
        session_token: entry["session_token"]
      ) || entry
    end

    action = pbMessage(
      AnilLanRework.ui_format("Sessao: {1}", AnilLanRework::RememberedSessions.host_label(entry)),
      [_INTL("Entrar"), _INTL("Sincronizar creditos"), _INTL("Esquecer"), _INTL("Cancelar")],
      4
    )
    case action
    when 0
      if AnilLanRework.connected?
        set_status(_INTL("Desconecta da sessao atual antes de entrar noutra sessao guardada."))
        return
      end
      target_ip = entry["last_ip"].to_s
      set_status(AnilLanRework.ui_format("A ligar a sessao guardada em {1}...", target_ip))
      Graphics.update
      if AnilLanRework.connect(target_ip, @player_id, @player_name, @player_char, false)
        remember_connected_session(target_ip, probe)
        set_status(_INTL("Ligado a sessao guardada."))
        Graphics.update
        AnilLanRework.request_same_map_transfer!("join_saved_session_same_map", 4)
        $scene = Scene_Map.new
        @exit = true
      else
        set_status(AnilLanRework.ui_format("ERRO: {1}", AnilLanRework.last_error_message.to_s))
      end
    when 1
      set_status(AnilLanRework.ui_format("A sincronizar creditos com {1}...", entry["last_ip"]))
      Graphics.update
      packet = AnilLanRework::RememberedSessions.pull_saved_payout(entry, player_internal_id)
      if packet.is_a?(Hash) && packet["ok"] == true
        if packet["amount"].to_i > 0
          AnilLanRework::RememberedSessions.remember_session(
            entry["last_ip"],
            host_id: entry["host_id"],
            host_name: packet["host_name"].to_s.empty? ? entry["host_name"].to_s : packet["host_name"].to_s,
            display_id: entry["display_id"],
            session_token: entry["session_token"]
          )
          amount = AnilLanRework::MailboxSync.apply_results([{
            "host_id"   => entry["host_id"].to_s,
            "host_name" => packet["host_name"].to_s,
            "last_ip"   => entry["last_ip"].to_s,
            "amount"    => packet["amount"].to_i
          }])
          set_status(AnilLanRework.ui_format("Sincronizacao concluida. Recebeste ${1}.", amount))
        else
          set_status(_INTL("Nao ha creditos pendentes nessa sessao."))
        end
      else
        set_status(_INTL("Sessao offline, diferente da guardada ou inacessivel neste momento."))
      end
    when 2
      AnilLanRework::RememberedSessions.forget_session(entry["host_id"])
      set_status(_INTL("Sessao removida da lista do F5."))
    end
  end

  def do_emergency_rescue
    rescue_loc = nil
    if $PokemonGlobal&.pokecenterMapId && $PokemonGlobal.pokecenterMapId.to_i >= 0
      rescue_loc = {
        :map_id => $PokemonGlobal.pokecenterMapId.to_i,
        :x      => $PokemonGlobal.pokecenterX.to_i,
        :y      => $PokemonGlobal.pokecenterY.to_i,
        :dir    => $PokemonGlobal.pokecenterDirection.to_i
      }
    else
      home = GameData::PlayerMetadata.get($player.character_ID)&.home rescue nil
      home = GameData::Metadata.get.home if !home
      if home
        rescue_loc = {
          :map_id => home[0].to_i,
          :x      => home[1].to_i,
          :y      => home[2].to_i,
          :dir    => home[3].to_i
        }
      end
    end

    unless rescue_loc
      set_status(_INTL("Nao foi encontrado ponto seguro para resgate neste save."))
      return
    end

    label = AnilLanRework.ui_format("mapa {1} ({2}, {3})", rescue_loc[:map_id], rescue_loc[:x], rescue_loc[:y])
    return unless pbConfirmMessage(AnilLanRework.ui_format("Resgatar este save para {1}?", label))

    AnilLanRework.pending_return_location = rescue_loc
    AnilLanRework.request_map_graphics_refresh!("manual_rescue", 4)
    set_status(AnilLanRework.ui_format("Resgate agendado para {1}.", label))
    AnilLanRework.fade_to_black_and_freeze
    $scene = Scene_Map.new
  rescue => e
    AnilLanRework.log("emergency rescue error #{e.class}: #{e.message}")
    set_status(_INTL("Falha ao preparar o resgate deste save."))
  end

  def do_disconnect
    if AnilLanRework.connected?
      AnilLanRework.disconnect
      set_status(_INTL("Desconectado do rework."))
    else
      set_status(_INTL("Nao ha nenhuma sessao rework ativa."))
    end
  end
end

if defined?(MenuHandlers)
  MenuHandlers.add(:pause_menu, :multiplayer_cable_rework, {
    "name"  => _INTL("Multijogador (Rework)"),
    "order" => 65,
    "effect" => proc { |menu|
      pbPlayDecisionSE
      Scene_Map_MultiplayerMainMenu.open
      menu.pbRefresh
      next false
    }
  })
end

#===============================================================================
# Coop local world patches
# - Desliga o WorldSync continuo para o coop atual.
# - Persiste progresso cooperativo no save local de cada jogador.
# - Exponibiliza helpers para eventos roteirizados aguardarem o parceiro.
#===============================================================================
module AnilLanRework
  COOP_LOCAL_WORLD_MODE = true unless const_defined?(:COOP_LOCAL_WORLD_MODE)

  def self.coop_local_world?
    COOP_LOCAL_WORLD_MODE == true
  end

  def self.world_sync_enabled?
    !coop_local_world?
  end
end

module AnilLanRework
  module WorldSync
    class << self
      alias anil_coop_world_original_send_snapshot_if_host send_snapshot_if_host unless method_defined?(:anil_coop_world_original_send_snapshot_if_host)
      alias anil_coop_world_original_send_event_stream_if_host send_event_stream_if_host unless method_defined?(:anil_coop_world_original_send_event_stream_if_host)
      alias anil_coop_world_original_queue_snapshot queue_snapshot unless method_defined?(:anil_coop_world_original_queue_snapshot)
      alias anil_coop_world_original_queue_event_stream queue_event_stream unless method_defined?(:anil_coop_world_original_queue_event_stream)
      alias anil_coop_world_original_apply_pending_snapshot apply_pending_snapshot unless method_defined?(:anil_coop_world_original_apply_pending_snapshot)
      alias anil_coop_world_original_apply_pending_event_stream apply_pending_event_stream unless method_defined?(:anil_coop_world_original_apply_pending_event_stream)
      alias anil_coop_world_original_authoritative_for? authoritative_for? unless method_defined?(:anil_coop_world_original_authoritative_for?)
      alias anil_coop_world_original_remote_spawn_authority_active? remote_spawn_authority_active? unless method_defined?(:anil_coop_world_original_remote_spawn_authority_active?)

      def send_snapshot_if_host
        return unless AnilLanRework.world_sync_enabled?
        anil_coop_world_original_send_snapshot_if_host
      end

      def send_event_stream_if_host
        return unless AnilLanRework.world_sync_enabled?
        anil_coop_world_original_send_event_stream_if_host
      end

      def queue_snapshot(packet)
        if !AnilLanRework.world_sync_enabled?
          @pending_snapshot = nil
          return
        end
        anil_coop_world_original_queue_snapshot(packet)
      end

      def queue_event_stream(packet)
        if !AnilLanRework.world_sync_enabled?
          # Permite event streams vindos do servidor dedicado mesmo com world sync desativado
          if packet.is_a?(Hash) && (packet["server_auth"] == true || packet["sender_id"] == "server-world" || packet["type"] == "world_event_stream")
            anil_coop_world_original_queue_event_stream(packet)
            return
          end
          @pending_event_stream = nil
          return
        end
        anil_coop_world_original_queue_event_stream(packet)
      end

      def apply_pending_snapshot
        if !AnilLanRework.world_sync_enabled?
          @pending_snapshot = nil
          return
        end
        anil_coop_world_original_apply_pending_snapshot
      end

      def apply_pending_event_stream
        if !AnilLanRework.world_sync_enabled?
          # Permite aplicar se o stream veio do servidor dedicado
          if @pending_event_stream.is_a?(Hash) && (@pending_event_stream["server_auth"] == true || @pending_event_stream["sender_id"] == "server-world" || @pending_event_stream["type"] == "world_event_stream")
            anil_coop_world_original_apply_pending_event_stream
            return
          end
          @pending_event_stream = nil
          return
        end
        anil_coop_world_original_apply_pending_event_stream
      end

      def authoritative_for?(map_id)
        return false unless AnilLanRework.world_sync_enabled?
        anil_coop_world_original_authoritative_for?(map_id)
      end

      def remote_spawn_authority_active?(map_id)
        return false unless AnilLanRework.world_sync_enabled?
        anil_coop_world_original_remote_spawn_authority_active?(map_id)
      end
    end
  end
end

module AnilLanRework
  module CoopWorld
    @pending_event_state = {}
    @pending_event_starts = {}

    class << self
      def storage
        return empty_storage unless defined?($PokemonGlobal) && $PokemonGlobal
        data = $PokemonGlobal.instance_variable_get(:@anil_coop_world_progress)
        unless data.is_a?(Hash)
          data = empty_storage
          $PokemonGlobal.instance_variable_set(:@anil_coop_world_progress, data)
        end
        data["trainers"] ||= {}
        data["events"] ||= {}
        data
      rescue
        empty_storage
      end

      def empty_storage
        { "trainers" => {}, "events" => {} }
      end

      def peer_on_same_map(peer_id = nil)
        if peer_id
          peer = AnilLanRework.players[peer_id.to_s]
          return peer if peer && peer.map_id.to_i == ($game_map&.map_id.to_i)
          return nil
        end
        current_map_id = $game_map&.map_id.to_i
        return nil if current_map_id.to_i <= 0
        AnilLanRework.players.values.find do |peer|
          next false unless peer
          next false if peer.internal_id.to_s.empty? || peer.internal_id.to_s == AnilLanRework.self_internal_id.to_s
          peer.map_id.to_i == current_map_id
        end
      rescue
        nil
      end

      def normalize_event_key(event_key)
        event_key.to_s.strip
      end

      def trainer_key(map_id: nil, event_id: nil, trainer_type: nil, trainer_name: nil)
        map_part = map_id.to_i > 0 ? map_id.to_i : ($game_map&.map_id.to_i)
        pieces = ["map:#{map_part}"]
        pieces << "event:#{event_id.to_i}" if event_id.to_i > 0
        pieces << "type:#{trainer_type.to_s}" unless trainer_type.to_s.empty?
        pieces << "name:#{trainer_name.to_s.strip.downcase}" unless trainer_name.to_s.strip.empty?
        pieces.join("|")
      end

      def trainer_key_for(trainer, map_id = nil)
        return nil unless trainer
        trainer_type = nil
        trainer_name = nil
        trainer_event = nil
        trainer_type = trainer.trainer_type if trainer.respond_to?(:trainer_type)
        trainer_name = trainer.name if trainer.respond_to?(:name)
        trainer_event = trainer.id if trainer.respond_to?(:id)
        trainer_key(
          map_id: map_id,
          event_id: trainer_event,
          trainer_type: trainer_type,
          trainer_name: trainer_name
        )
      rescue
        nil
      end

      def trainer_defeated?(trainer_key_value)
        key = trainer_key_value.to_s
        return false if key.empty?
        storage["trainers"][key] == true
      rescue
        false
      end

      def event_completed?(event_key)
        key = normalize_event_key(event_key)
        return false if key.empty?
        entry = storage["events"][key]
        entry.is_a?(Hash) && entry["completed"] == true
      rescue
        false
      end

      def build_sync_payload(switch_ids: [], self_switches: [], variable_ids: [])
        payload = {}
        switch_payload = {}
        Array(switch_ids).each do |switch_id|
          idx = switch_id.to_i
          next if idx <= 0
          switch_payload[idx.to_s] = ($game_switches[idx] rescue false) ? true : false
        end
        payload["switches"] = switch_payload unless switch_payload.empty?

        self_switch_payload = {}
        Array(self_switches).each do |entry|
          next unless entry.is_a?(Array) && entry.length >= 3
          map_id = entry[0].to_i
          event_id = entry[1].to_i
          letter = entry[2].to_s
          next if map_id <= 0 || event_id <= 0 || letter.empty?
          key = "#{map_id}_#{event_id}_#{letter}"
          self_switch_payload[key] = ($game_self_switches[[map_id, event_id, letter]] rescue false) ? true : false
        end
        payload["self_switches"] = self_switch_payload unless self_switch_payload.empty?

        variable_payload = {}
        Array(variable_ids).each do |variable_id|
          idx = variable_id.to_i
          next if idx <= 0
          variable_payload[idx.to_s] = $game_variables[idx] rescue nil
        end
        payload["variables"] = variable_payload unless variable_payload.empty?
        payload
      rescue => e
        AnilLanRework.log("coop build_sync_payload error #{e.class}: #{e.message}")
        {}
      end

      def apply_payload(payload)
        return if !payload.is_a?(Hash) || payload.empty?

        if payload["switches"].is_a?(Hash)
          payload["switches"].each do |key, value|
            $game_switches[key.to_i] = value rescue nil
          end
        end

        if payload["self_switches"].is_a?(Hash)
          payload["self_switches"].each do |key, value|
            parts = key.to_s.split("_", 3)
            next unless parts.length == 3
            $game_self_switches[[parts[0].to_i, parts[1].to_i, parts[2]]] = value rescue nil
          end
        end

        if payload["variables"].is_a?(Hash)
          payload["variables"].each do |key, value|
            $game_variables[key.to_i] = value rescue nil
          end
        end

        $game_map.need_refresh = true rescue nil
      rescue => e
        AnilLanRework.log("coop apply_payload error #{e.class}: #{e.message}")
      end

      def send_progress_packet(peer_id, trainers: nil, events: nil)
        return unless AnilLanRework.connected?
        return if peer_id.to_s.empty?
        payload = { "to_id" => peer_id.to_s }
        payload["trainers"] = Array(trainers).map(&:to_s).reject(&:empty?) if trainers
        payload["events"] = Array(events) if events
        AnilLanRework.connection.send_packet("coop_progress_sync", payload)
      rescue => e
        AnilLanRework.log("coop send_progress_packet error #{e.class}: #{e.message}")
      end

      def mark_trainers_defeated(trainer_keys, peer_id: nil, sync: true)
        keys = Array(trainer_keys).map(&:to_s).reject(&:empty?).uniq
        return if keys.empty?
        keys.each { |key| storage["trainers"][key] = true }
        if sync
          peer = peer_on_same_map(peer_id) || AnilLanRework.players[peer_id.to_s]
          send_progress_packet(peer&.internal_id, trainers: keys)
        end
      rescue => e
        AnilLanRework.log("coop mark_trainers_defeated error #{e.class}: #{e.message}")
      end

      def complete_scripted_event(event_key, payload: nil, switch_ids: [], self_switches: [], variable_ids: [], peer_id: nil, sync: true)
        key = normalize_event_key(event_key)
        return false if key.empty?
        payload = build_sync_payload(switch_ids: switch_ids, self_switches: self_switches, variable_ids: variable_ids) if payload.nil?
        storage["events"][key] = {
          "completed" => true,
          "payload"    => payload
        }
        apply_payload(payload)
        if sync
          peer = peer_on_same_map(peer_id) || AnilLanRework.players[peer_id.to_s]
          if peer
            send_progress_packet(peer.internal_id, events: [{ "key" => key, "payload" => payload }])
            send_event_signal(key, "complete", peer.internal_id, payload: payload)
          end
        end
        true
      rescue => e
        AnilLanRework.log("coop complete_scripted_event error #{e.class}: #{e.message}")
        false
      end

      def event_start_authority?(peer_id)
        return true if AnilLanRework.respond_to?(:primary_host?) && AnilLanRework.primary_host?
        AnilLanRework.self_internal_id.to_s <= peer_id.to_s
      rescue
        true
      end

      def remote_ready_for_event?(event_key, peer_id, map_id)
        entry = @pending_event_state.dig(event_key.to_s, peer_id.to_s)
        return false unless entry.is_a?(Hash)
        entry["state"].to_s == "ready" && entry["map_id"].to_i == map_id.to_i
      end

      def send_event_signal(event_key, state, peer_id, payload: nil, map_id: nil)
        return unless AnilLanRework.connected?
        return if peer_id.to_s.empty?
        packet = {
          "to_id"     => peer_id.to_s,
          "event_key" => event_key.to_s,
          "state"     => state.to_s,
          "map_id"    => (map_id || ($game_map&.map_id)).to_i
        }
        packet["payload"] = payload if payload
        AnilLanRework.connection.send_packet("coop_event_signal", packet)
      rescue => e
        AnilLanRework.log("coop send_event_signal error #{e.class}: #{e.message}")
      end

      def wait_for_partner(event_key, wait_message: nil, peer_id: nil)
        return true unless AnilLanRework.connected?
        key = normalize_event_key(event_key)
        return true if key.empty?
        peer = peer_on_same_map(peer_id)
        message = wait_message.to_s.empty? ? AnilLanRework::BattleSync.waiting_text("Aguardando outro jogador...") : wait_message.to_s
        unless peer
          pbMessage(message) rescue nil
          return false
        end

        map_id = $game_map&.map_id.to_i
        @pending_event_state[key] ||= {}
        @pending_event_state[key][AnilLanRework.self_internal_id.to_s] = {
          "state"  => "ready",
          "map_id" => map_id
        }
        send_event_signal(key, "ready", peer.internal_id, map_id: map_id)

        if remote_ready_for_event?(key, peer.internal_id, map_id) && event_start_authority?(peer.internal_id)
          @pending_event_starts[key] = true
          send_event_signal(key, "start", peer.internal_id, map_id: map_id)
        end

        started = @pending_event_starts.delete(key) == true
        return true if started

        pbMessage(message) do
          loop do
            started = true if @pending_event_starts.delete(key) == true
            break if started
            break unless AnilLanRework.connected?
            break unless $scene.is_a?(Scene_Map)
            AnilLanRework::BattleSync.pump_network rescue nil
            Graphics.update
            Input.update
          end
        end
        started
      rescue => e
        AnilLanRework.log("coop wait_for_partner error #{e.class}: #{e.message}")
        false
      end

      def finish_coop_battle(ctx)
        return unless ctx && ctx.mode == :coop
        trainer_keys = Array(ctx.rules && (ctx.rules["coop_trainer_keys"] || ctx.rules[:coop_trainer_keys]))
        return if trainer_keys.empty?
        mark_trainers_defeated(trainer_keys, peer_id: ctx.partner_id, sync: true)
      rescue => e
        AnilLanRework.log("coop finish_coop_battle error #{e.class}: #{e.message}")
      end

      def on_packet(packet)
        return unless packet.is_a?(Hash)
        case packet["type"].to_s
        when "coop_progress_sync"
          Array(packet["trainers"]).each do |trainer_key_value|
            next if trainer_key_value.to_s.empty?
            storage["trainers"][trainer_key_value.to_s] = true
          end
          Array(packet["events"]).each do |entry|
            next unless entry.is_a?(Hash)
            key = normalize_event_key(entry["key"])
            next if key.empty?
            storage["events"][key] = {
              "completed" => true,
              "payload"    => entry["payload"]
            }
            apply_payload(entry["payload"])
          end
        when "coop_event_signal"
          key = normalize_event_key(packet["event_key"])
          return if key.empty?
          @pending_event_state[key] ||= {}
          @pending_event_state[key][packet["sender_id"].to_s] = {
            "state"  => packet["state"].to_s,
            "map_id" => packet["map_id"].to_i
          }
          case packet["state"].to_s
          when "start"
            @pending_event_starts[key] = true
          when "complete"
            complete_scripted_event(key, payload: packet["payload"], peer_id: nil, sync: false)
          end
        end
      rescue => e
        AnilLanRework.log("coop on_packet error #{e.class}: #{e.message}")
      end
    end
  end
end

module AnilLanRework
  module BattleSync
    class << self
      alias anil_coop_world_original_request_coop_battle request_coop_battle unless method_defined?(:anil_coop_world_original_request_coop_battle)
      alias anil_coop_world_original_start_coop_battle start_coop_battle unless method_defined?(:anil_coop_world_original_start_coop_battle)

      def request_coop_battle(kind:, foe_party: nil, foe_trainers: nil, can_override: false)
        return nil if local_player_busy?
        peer = nearby_peer_on_same_map(include_unavailable: true)
        return nil unless peer
        battle_id = build_battle_id(kind.to_s)
        seed = rand(0x3FFF_FFFF)
        trainer_keys = Array(foe_trainers).map { |trainer| AnilLanRework::CoopWorld.trainer_key_for(trainer) }.compact
        rules = {}
        rules["coop_trainer_keys"] = trainer_keys unless trainer_keys.empty?
        AnilLanRework.log("request_coop_battle start battle_id=#{battle_id} kind=#{kind} peer=#{peer.internal_id} foes=#{Array(foe_party).length} trainer_keys=#{trainer_keys.inspect}")
        boss_flag = false
        if defined?(BossBattleConstants) && $game_switches && ($game_switches[BossBattleConstants::BOSS_BATTLE_SWITCH] rescue false)
          boss_flag = true
        elsif $game_switches && ($game_switches[45] rescue false)
          boss_flag = true
        elsif $game_temp && $game_temp.battle_rules && ($game_temp.battle_rules["boss"] || $game_temp.battle_rules["midbattleScript"] || $game_temp.battle_rules["databoxStyle"] rescue false)
          boss_flag = true
        end

        AnilLanRework.connection.send_packet("battle_request",
          "to_id"         => peer.internal_id,
          "battle_id"     => battle_id,
          "kind"          => kind.to_s,
          "seed"          => seed,
          "can_override"  => can_override ? true : false,
          "boss_battle"   => boss_flag,
          "battle_rules"  => ($game_temp.battle_rules rescue {}),
          "foes"          => AnilLanRework::Serializer.serialize_party(foe_party),
          "foe_trainers"  => AnilLanRework::Serializer.serialize_trainers(foe_trainers),
          "trainer_keys"  => trainer_keys,
          "battle_size"   => ($game_temp.battle_rules["size"] rescue nil),
          "party"         => AnilLanRework::Serializer.serialize_party($player.party)
        )
        AnilLanRework.connection.flush_batch
        response = wait_for_battle_response(battle_id, peer.internal_id)
        AnilLanRework.log("request_coop_battle response battle_id=#{battle_id} accepted=#{response.is_a?(Hash) ? response['accepted'].inspect : response.inspect}")
        accepted = response.is_a?(Hash) ? (response["accepted"] == true || response["accepted"] == "true") : (response == true)
        if accepted == true
          peer.party_blob = Array(response["party"]) if response.is_a?(Hash) && response["party"]
          
          # Fallback check
          if peer.party_blob.empty?
            AnilLanRework.log("request_coop_battle: received accepted but empty party blob. Client may be outdated.")
          end

          activate_context(
            battle_id: battle_id,
            mode: :coop,
            client_index: 0,
            partner_id: peer.internal_id,
            seed: seed,
            rules: rules,
            foe_party: foe_party
          )
          inject_partner(peer, nil, battle_id)
          return { battle_id: battle_id, seed: seed, peer: peer }
        end
        unavailable_reason = battle_response_unavailable_reason(response)
        if unavailable_reason
          clear_peer_party_cache(peer, "coop_unavailable_#{unavailable_reason}")
          notify_unavailable_peer(peer, unavailable_reason)
          return false
        end
        if response.is_a?(Hash) && response.key?("accepted") && accepted == false
          clear_peer_party_cache(peer, "coop_declined")
          # pbMessage(_INTL("Convite recusado.")) rescue nil
          return :declined
        end
        clear_peer_party_cache(peer, "coop_no_response")
        nil
      end

      def start_coop_battle(packet)
        sender_id = packet["sender_id"].to_s
        peer = AnilLanRework.players[sender_id]
        return unless peer
        trainer_keys = Array(packet["trainer_keys"]).map(&:to_s).reject(&:empty?)
        rules = {}
        rules["coop_trainer_keys"] = trainer_keys unless trainer_keys.empty?
        AnilLanRework.log("start_coop_battle battle_id=#{packet['battle_id']} kind=#{packet['kind']} peer=#{sender_id} foes=#{Array(packet['foes']).length} trainer_keys=#{trainer_keys.inspect}")
        activate_context(
          battle_id: packet["battle_id"].to_s,
          mode: :coop,
          client_index: 1,
          partner_id: sender_id,
          seed: packet["seed"].to_i,
          rules: rules,
          foe_party: nil
        )
        inject_partner(peer, packet["party"], packet["battle_id"])
        # 1. Espelha as battle_rules do host (ex: regras de boss, backdrop, cannotRun, midbattle)
        if packet["battle_rules"].is_a?(Hash) && !packet["battle_rules"].empty?
          $game_temp.clear_battle_rules rescue nil
          packet["battle_rules"].each do |rule_key, rule_val|
            if rule_key.to_s == "midbattleScript" && rule_val
              val_sym = rule_val.to_s.sub(/^:/, "").to_sym
              setBattleRule("midbattleScript", val_sym) rescue nil
            elsif rule_val.nil? || rule_val == true
              setBattleRule(rule_key.to_s) rescue nil
            else
              setBattleRule(rule_key.to_s, rule_val) rescue nil
            end
          end
          AnilLanRework.log("start_coop_battle (001) synced battle_rules=#{packet['battle_rules'].inspect}")
        end

        # 2. Espelha o estado de boss do host (Switch 45 / BOSS_BATTLE_SWITCH)
        # Mesma correcao do 000d (ver la a nota longa): o anfitriao diz se e
        # boss; o midbattleScript so vale para anfitrioes antigos que nao mandam
        # a chave. E os switches sao GUARDADOS aqui e repostos no clear_context —
        # sao globais e vivem no save, escrevia-se e nunca se repunha.
        if packet.key?("boss_battle")
          boss_on = (packet["boss_battle"] == true || packet["boss_battle"].to_s == "true")
        else
          boss_on = !!(packet["battle_rules"].is_a?(Hash) &&
                       packet["battle_rules"]["midbattleScript"])
        end
        AnilLanRework::BattleSync.guardar_switches_de_boss! rescue nil
        if $game_switches
          $game_switches[45] = boss_on rescue nil
          if defined?(BossBattleConstants)
            $game_switches[BossBattleConstants::BOSS_BATTLE_SWITCH] = boss_on rescue nil
          end
        end
        AnilLanRework.log("start_coop_battle (001) boss_battle=#{boss_on}")

        if packet["kind"].to_s == "trainer"
          trainers = AnilLanRework::Serializer.deserialize_trainers(packet["foe_trainers"])
          AnilLanRework.log("start_coop_battle trainers=#{trainers.length}")
          ensure_trainer_rule
          # Synchronize host's explicit battle size (e.g. "double" for Gym Leaders with 1 trainer object)
          if packet["battle_size"] && !packet["battle_size"].to_s.empty?
            setBattleRule(packet["battle_size"].to_s) rescue nil
          end
          if TrainerBattle.respond_to?(:anil_rework_original_start_core)
            TrainerBattle.anil_rework_original_start_core(*trainers)
          elsif TrainerBattle.respond_to?(:start_core)
            TrainerBattle.start_core(*trainers)
          end
        else
          foes = AnilLanRework::Serializer.deserialize_party(packet["foes"])
          ensure_wild_rule(foes)
          if WildBattle.respond_to?(:anil_rework_original_start)
            foes.empty? ? WildBattle.anil_rework_original_start(can_override: packet["can_override"] == true) :
                          WildBattle.anil_rework_original_start(*foes, can_override: packet["can_override"] == true)
          else
            foes.empty? ? WildBattle.start(can_override: packet["can_override"] == true) :
                          WildBattle.start(*foes, can_override: packet["can_override"] == true)
          end
        end
      rescue => e
        AnilLanRework.log("start_coop_battle error #{e}")
        $game_temp.clear_battle_rules rescue nil
        remove_partner
        clear_context
        AnilLanRework.request_map_graphics_refresh!("coop_start_error", 3)
      end
    end
  end
end

module AnilLanRework
  module Router
    class << self
      alias anil_coop_world_original_route_packet route_packet unless method_defined?(:anil_coop_world_original_route_packet)

      def route_packet(packet)
        packet_type = packet["type"].to_s
        if packet_type == "coop_progress_sync" || packet_type == "coop_event_signal"
          merge_peer_from_packet(packet)
          AnilLanRework::CoopWorld.on_packet(packet)
          return
        end
        anil_coop_world_original_route_packet(packet)
      end
    end
  end
end

if defined?(Battle)
  class Battle
    alias anil_coop_world_original_pbEndOfBattle pbEndOfBattle unless method_defined?(:anil_coop_world_original_pbEndOfBattle)

    def pbEndOfBattle(*args)
      ctx = AnilLanRework::BattleSync.active_context
      result = anil_coop_world_original_pbEndOfBattle(*args)
      if ctx && ctx.mode == :coop && result == 1
        AnilLanRework::CoopWorld.finish_coop_battle(ctx)
      end
      result
    end
  end
end

class Interpreter
  def pbCoopEventKey(event_key = nil)
    key = event_key.to_s.strip
    return key unless key.empty?
    "story:map:#{@map_id}:event:#{@event_id}"
  end

  def pbCoopWaitForPartner(event_key = nil, wait_message = nil)
    AnilLanRework::CoopWorld.wait_for_partner(
      pbCoopEventKey(event_key),
      wait_message: wait_message
    )
  end

  def pbCoopWaitForPartner!(event_key = nil, wait_message = nil)
    started = pbCoopWaitForPartner(event_key, wait_message)
    @index = @list.length unless started
    started
  end

  def pbCoopCompleteEvent(event_key = nil, switch_ids: [], self_switches: nil, variable_ids: [])
    tracked_self_switches = self_switches || [[@map_id, @event_id, "A"]]
    AnilLanRework::CoopWorld.complete_scripted_event(
      pbCoopEventKey(event_key),
      switch_ids: switch_ids,
      self_switches: tracked_self_switches,
      variable_ids: variable_ids
    )
  end

  def pbCoopEventCompleted?(event_key = nil)
    AnilLanRework::CoopWorld.event_completed?(pbCoopEventKey(event_key))
  end
end
