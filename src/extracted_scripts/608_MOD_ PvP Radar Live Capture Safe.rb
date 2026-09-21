# encoding: UTF-8
#===============================================================================
# MOD: PvP Finder seguro/persistente
# Guarda somente peers que o servidor ja entregou legitimamente ao cliente.
# Nao varre canais, nao consulta endpoints privados e nao mistura peers remotos
# em AnilLanRework.players.
#===============================================================================
module AnilPvPFinder
  FILE = "pvp_finder_cache.rxdata"
  MAX_AGE = 30 * 24 * 60 * 60
  module_function

  def cache
    @cache ||= load_cache
  end

  def load_cache
    return {} unless File.file?(FILE)
    obj = Marshal.load(File.binread(FILE)) rescue {}
    obj.is_a?(Hash) ? obj : {}
  rescue
    {}
  end

  def save_cache
    File.open(FILE,"wb") { |f| Marshal.dump(cache,f) }
  rescue => e
    AnilLanRework.log("[PVP FINDER] save #{e.class}: #{e.message}") rescue nil
  end

  def current_channel
    ($PokemonSystem ? $PokemonSystem.multiplayer_channel.to_i : 1)
  rescue
    1
  end

  def remember_current!
    return unless defined?(AnilLanRework) && (AnilLanRework.connected? rescue false)
    now = Time.now.to_i
    ch = current_channel
    (AnilLanRework.players || {}).each do |id,p|
      next unless p
      pid = id.to_s
      next if pid.empty? || pid == (AnilLanRework.self_internal_id.to_s rescue "")
      cache[pid] = {
        :id => pid, :name => p.name.to_s, :channel => ch,
        :map_id => (p.map_id.to_i rescue 0), :last_seen => now
      }
    end
    cache.delete_if { |_id,h| now - h[:last_seen].to_i > MAX_AGE }
    save_cache
  rescue => e
    AnilLanRework.log("[PVP FINDER] remember #{e.class}: #{e.message}") rescue nil
  end

  # Captura imediata: chamado assim que um RemotePeer recebe qualquer pacote
  # legitimo do servidor. Assim, peers revelados durante transferencias/mapas
  # entram no Radar no mesmo instante, sem esperar o tick de 30 frames.
  def remember_peer!(peer, channel = nil)
    return unless peer
    pid = (peer.internal_id.to_s rescue "")
    return if pid.empty? || pid == (AnilLanRework.self_internal_id.to_s rescue "")
    now = Time.now.to_i
    ch = (channel || current_channel).to_i
    old = cache[pid] || {}
    name = (peer.name.to_s rescue "")
    name = old[:name].to_s if name.empty?
    cache[pid] = {
      :id => pid, :name => name, :channel => ch,
      :map_id => (peer.map_id.to_i rescue old[:map_id].to_i), :last_seen => now
    }
    # Agrupa escritas para nao martelar armazenamento a cada player_state.
    @dirty = true
    if !@last_flush || now - @last_flush.to_i >= 3
      save_cache
      @dirty = false
      @last_flush = now
    end
    true
  rescue => e
    AnilLanRework.log("[PVP FINDER] remember_peer #{e.class}: #{e.message}") rescue nil
    false
  end

  def flush!
    return unless @dirty
    save_cache
    @dirty = false
    @last_flush = Time.now.to_i
  rescue
  end

  def map_name(id)
    return "Mapa #{id}" if id.to_i <= 0
    n = pbGetMapNameFromId(id.to_i) rescue nil
    n.to_s.empty? ? "Mapa #{id}" : n.to_s
  end

  def live_peer(id)
    (AnilLanRework.players[id.to_s] rescue nil)
  end

  def ago(ts)
    s = Time.now.to_i - ts.to_i
    return "agora" if s < 60
    return "#{s/60} min" if s < 3600
    return "#{s/3600} h" if s < 86400
    "#{s/86400} d"
  end

  def entries
    remember_current!
    cache.values.sort_by { |h| [-h[:last_seen].to_i, h[:name].to_s.downcase] }
  end

  def switch_channel(ch)
    ch = ch.to_i
    return if ch < 1 || ch > 10
    if $PokemonSystem
      $PokemonSystem.multiplayer_channel = ch
    end
    AnilLanRework.connection.send_packet("change_channel", "channel_id" => ch)
    pbMessage(_INTL("Solicitada mudança para o Canal {1}. Abra o PvP Finder novamente após a confirmação.", ch))
  rescue => e
    pbMessage(_INTL("Não foi possível mudar de canal agora."))
    AnilLanRework.log("[PVP FINDER] channel #{e.class}: #{e.message}") rescue nil
  end

  def interact(h)
    peer = live_peer(h[:id])
    mych = current_channel
    if peer
      cmds=[_INTL("Batalhar"),_INTL("Ver Pokémon"),_INTL("Voltar")]
      c=pbMessage(_INTL("{1} — Canal {2} — {3}",peer.name,mych,map_name(peer.map_id)),cmds,cmds.length)
      case c
      when 0 then AnilLanRework::BattleSync.request_custom_duel(peer)
      when 1 then AnilLanRework::PlayerMarket.open_peer_follower_summary(peer)
      end
      return
    end
    ch=h[:channel].to_i
    if ch != mych && ch.between?(1,10)
      cmds=[_INTL("Ir para Canal {1}",ch),_INTL("Voltar")]
      c=pbMessage(_INTL("{1} foi visto no Canal {2}, {3}, há {4}.\nA presença pode ter mudado.",h[:name],ch,map_name(h[:map_id]),ago(h[:last_seen])),cmds,cmds.length)
      switch_channel(ch) if c==0
    else
      pbMessage(_INTL("{1} foi visto em {2} há {3}, mas não está na lista ao vivo agora.",h[:name],map_name(h[:map_id]),ago(h[:last_seen])))
    end
  end

  def choose_channel
    cur=current_channel
    cmds=(1..10).map { |n| n==cur ? _INTL("Canal {1} (atual)",n) : _INTL("Canal {1}",n) }
    cmds << _INTL("Voltar")
    c=pbMessage(_INTL("Radar PvP — escolha um canal para visitar.\nO radar só registra jogadores que o servidor realmente entregar ao cliente."),cmds,cmds.length)
    return if c < 0 || c >= 10
    target=c+1
    if target==cur
      remember_current!
      pbMessage(_INTL("Canal {1} atualizado. {2} jogador(es) remoto(s) visível(is) agora.",cur,(AnilLanRework.players.size rescue 0)))
    else
      switch_channel(target)
    end
  end

  def open
    remember_current!
    loop do
      arr=entries
      cmds=arr.first(40).map do |h|
        live = !!live_peer(h[:id])
        mark = live ? "●" : "○"
        "#{mark} #{h[:name]}  [C#{h[:channel]}]  #{live ? 'ONLINE AGORA' : ago(h[:last_seen])}"
      end
      player_count=cmds.length
      cmds << _INTL("Atualizar canal atual")
      cmds << _INTL("Radar de canais (manual)")
      cmds << _INTL("Voltar")
      title = _INTL("PvP Radar — Canal {1}\n● = confirmado agora | ○ = visto antes\nCache: {2} jogador(es)",current_channel,arr.length)
      c=pbMessage(title,cmds,cmds.length)
      return if c < 0 || c == cmds.length-1
      if c == player_count
        remember_current!
        next
      elsif c == player_count+1
        choose_channel
        return
      elsif c < player_count
        interact(arr[c])
      end
    end
  rescue => e
    AnilLanRework.log("[PVP FINDER] open #{e.class}: #{e.message}") rescue nil
    pbMessage(_INTL("Não foi possível abrir o PvP Radar agora.")) rescue nil
  end
end

# Hook passivo no ponto mais abrangente: todo peer que o cliente normal recebe
# passa por RemotePeer#update_from_packet (join_ack, player_state, peer_joined).
# Nao envia consultas extras ao servidor e nao cria peers artificiais.
if defined?(AnilLanRework::RemotePeer) &&
   !AnilLanRework::RemotePeer.method_defined?(:anil_pvpradar_orig_update_from_packet)
  class AnilLanRework::RemotePeer
    alias_method :anil_pvpradar_orig_update_from_packet, :update_from_packet
    def update_from_packet(packet)
      ret = anil_pvpradar_orig_update_from_packet(packet)
      AnilPvPFinder.remember_peer!(self) rescue nil
      ret
    end
  end
end

if defined?(Scene_Map) && !Scene_Map.method_defined?(:anil_pvpfinder_orig_update)
  class Scene_Map
    alias_method :anil_pvpfinder_orig_update, :update
    def update(*a)
      anil_pvpfinder_orig_update(*a)
      @anil_pvpfinder_tick = (@anil_pvpfinder_tick || 0) + 1
      if @anil_pvpfinder_tick >= 30
        @anil_pvpfinder_tick = 0
        AnilPvPFinder.remember_current! rescue nil
        AnilPvPFinder.flush! rescue nil
      end
    end
  end
end
