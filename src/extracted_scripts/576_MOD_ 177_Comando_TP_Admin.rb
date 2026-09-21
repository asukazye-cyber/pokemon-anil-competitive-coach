# encoding: UTF-8
#===============================================================================
# MOD: 177_Comando_TP_Admin
#-------------------------------------------------------------------------------
#   /tp <nome>            vou ter com essa pessoa
#   /tp <nome> <nome>     trago a primeira ate a segunda
#   /tp <nome> eu         trago essa pessoa ate mim
#
# ⚠️ SO ADMIN, E AQUI ISSO E MESMO SEGURANCA.
#
# Ao contrario do /menu, isto da uma vantagem real: chegar a qualquer sitio do
# mapa sem andar. A lista e a mesma do /clima.
#
# ⚠️ IR TER COM ALGUEM E DIFERENTE DE TRAZER ALGUEM.
#
# Ir eu e local: mexo no meu $game_player e mais nada. Trazer outra pessoa
# obriga a pedir ao CLIENTE dela que se mova — o servidor nao arrasta ninguem.
# Sao dois caminhos distintos, e o segundo depende do outro lado aceitar.
#
# ⚠️ E NAO SE TELEPORTA PARA CIMA DE NINGUEM.
#
# Cair exactamente na casa do outro jogador prende os dois: o motor nao deixa
# dois corpos no mesmo tile e o passo seguinte falha. Procura-se a casa livre
# mais proxima, e so se desiste se nao houver nenhuma a volta.
#===============================================================================

module AnilComandoTP
  ACTIVO = true
  ADMINS = ["wallace-adm100"].freeze

  # Ate que distancia se procura uma casa livre ao lado do destino.
  RAIO = 3

  module_function

  def log(t)
    AnilLanRework.log("[TP] #{t}") rescue nil
  end

  def meu_id
    AnilLanRework.read_cfg("multiplayer_player.txt", "id", "").to_s.strip.downcase
  rescue
    ""
  end

  def admin?
    ADMINS.include?(meu_id)
  end

  def avisar(t)
    if AnilLanRework.respond_to?(:add_popup)
      AnilLanRework.add_popup(t, 8.0) rescue nil
    else
      pbMessage(t) rescue nil
    end
  end

  # ⚠️ Compara pelo nome VISIVEL, e sem distinguir maiusculas.
  #
  # Ninguem escreve "bilaumaster-udepvi" no chat. Aceita-se o nome que aparece
  # por cima da cabeca, e um pedaco dele chega — com varios a condizer, avisa-se
  # em vez de escolher um a sorte.
  def procurar(nome)
    alvo = nome.to_s.strip.downcase
    return [nil, :vazio] if alvo.empty?
    achados = []
    (AnilLanRework.players || {}).each do |id, p|
      next unless p
      n = p.name.to_s.downcase
      next if n.empty?
      achados << [id, p] if n == alvo
    end
    return [achados.first, :ok] if achados.length == 1
    if achados.empty?
      (AnilLanRework.players || {}).each do |id, p|
        next unless p
        n = p.name.to_s.downcase
        achados << [id, p] if !n.empty? && n.include?(alvo)
      end
    end
    return [nil, :nenhum] if achados.empty?
    return [nil, :varios] if achados.length > 1
    [achados.first, :ok]
  rescue
    [nil, :nenhum]
  end

  # Casa livre mais perto de (x, y). Devolve nil se nao houver nenhuma.
  def casa_livre(mapa, x, y)
    return [x, y] if livre?(mapa, x, y)
    (1..RAIO).each do |r|
      (-r..r).each do |dx|
        (-r..r).each do |dy|
          next unless dx.abs == r || dy.abs == r
          nx = x + dx
          ny = y + dy
          return [nx, ny] if livre?(mapa, nx, ny)
        end
      end
    end
    nil
  rescue
    nil
  end

  def livre?(mapa, x, y)
    return false unless mapa && mapa.valid?(x, y)
    return false unless mapa.passable?(x, y, 0)
    t = (mapa.terrain_tag(x, y) rescue nil)
    return false if t && (t.can_surf || t.ledge)
    true
  rescue
    false
  end

  def pode_agora?
    return false unless ($scene.is_a?(Scene_Map) rescue false)
    return false if ($game_temp && $game_temp.in_battle rescue false)
    return false if (pbMapInterpreterRunning? rescue false)
    return false if ($game_player.moving? rescue false)
    true
  rescue
    false
  end

  # ------------------------------------------------------------------ ir eu
  def ir_ter_com(peer)
    mapa_id = peer.map_id.to_i
    if $game_map && $game_map.map_id.to_i == mapa_id
      destino = casa_livre($game_map, peer.x.to_i, peer.y.to_i)
      unless destino
        avisar(_INTL("Nao ha espaco livre ao lado de {1}.", peer.name))
        return true
      end
      $game_player.moveto(destino[0], destino[1])
      $game_player.straighten rescue nil
      avisar(_INTL("Foste ter com {1}.", peer.name))
      log("fui ter com #{peer.name} em #{mapa_id} (#{destino[0]},#{destino[1]})")
      return true
    end

    # Noutro mapa: transferencia normal, com a casa escolhida a chegada.
    $game_temp.player_transferring = true
    $game_temp.player_new_map_id   = mapa_id
    $game_temp.player_new_x        = peer.x.to_i
    $game_temp.player_new_y        = peer.y.to_i + 1
    $game_temp.player_new_direction = 8
    $game_temp.transition_processing = true
    avisar(_INTL("A ir ter com {1}...", peer.name))
    log("transferencia para o mapa #{mapa_id} atras de #{peer.name}")
    true
  rescue => e
    log("falha a ir ter com: #{e.class}: #{e.message}")
    false
  end

  # -------------------------------------------------------------- trazer
  #
  # ⚠️ Nao se arrasta ninguem: PEDE-SE.
  #
  # O servidor nao mexe no $game_player de outro cliente. O que viaja e um
  # pedido; quem o cumpre e o jogo da outra pessoa. Se ela estiver em batalha ou
  # num evento, ele recusa — e isso e o correcto.
  def pedir_para_vir(peer_origem, destino_map, destino_x, destino_y, nome_destino)
    return false unless (AnilLanRework.connected? rescue false)
    AnilLanRework.connection.send_packet("admin_tp",
      "to_id"     => peer_origem.internal_id.to_s,
      "de"        => meu_id,
      "map_id"    => destino_map.to_i,
      "x"         => destino_x.to_i,
      "y"         => destino_y.to_i,
      "para_nome" => nome_destino.to_s
    )
    avisar(_INTL("Pedido enviado: {1} vai ter com {2}.", peer_origem.name, nome_destino))
    log("pedido de tp: #{peer_origem.name} -> #{nome_destino} (#{destino_map}:#{destino_x},#{destino_y})")
    true
  rescue => e
    log("falha a pedir: #{e.class}: #{e.message}")
    false
  end
end

module AnilComandoTP
  module_function

  def tratar(texto)
    return false unless ACTIVO
    t = texto.to_s.strip
    return false unless t =~ %r{\A/tp(?:\s+(.+))?\z}i
    args = $1.to_s.strip

    unless admin?
      avisar(_INTL("[Sistema] Comando disponivel apenas para administradores."))
      return true
    end

    if args.empty?
      avisar(_INTL("Usa: /tp <nome>  ou  /tp <nome> <nome>"))
      return true
    end

    unless pode_agora?
      avisar(_INTL("So da para teletransportar no mapa, parado e fora de batalha."))
      return true
    end

    # ⚠️ Dois nomes separam-se pelo ULTIMO espaco, e nao pelo primeiro.
    #
    # Ha jogadores com espaco no nome ("Bilau Master"). Partir pelo primeiro
    # espaco fazia "/tp Bilau Master" virar "trazer o Bilau ate ao Master" —
    # duas pessoas que nem existem. Com o ultimo, o caso de dois nomes so falha
    # se AMBOS tiverem espacos, e ai avisa-se em vez de adivinhar.
    if args.include?(" ")
      origem_nome, destino_nome = args.rpartition(" ").values_at(0, 2)
      (achado_o, est_o) = procurar(origem_nome)
      (achado_d, est_d) = procurar(destino_nome)

      # Se a segunda parte nao e ninguem, provavelmente o nome tinha espaco.
      if est_d != :ok && est_o != :ok
        (achado_u, est_u) = procurar(args)
        if est_u == :ok
          return ir_ter_com(achado_u[1]) ? true : true
        end
      end

      unless est_o == :ok
        # Nao esta na lista local: o servidor resolve, e leva o destino consigo.
        perguntar_ao_servidor(origem_nome, destino_nome)
        return true
      end

      # "eu" como destino: traz a pessoa para o meu lado.
      if destino_nome.downcase == "eu" || destino_nome.downcase == "mim"
        d = casa_livre($game_map, $game_player.x, $game_player.y)
        unless d
          avisar(_INTL("Nao ha espaco livre ao teu lado."))
          return true
        end
        pedir_para_vir(achado_o[1], $game_map.map_id, d[0], d[1], _INTL("ti"))
        return true
      end

      unless est_d == :ok
        avisar(msg_estado(est_d, destino_nome))
        return true
      end

      alvo = achado_d[1]
      pedir_para_vir(achado_o[1], alvo.map_id.to_i, alvo.x.to_i, alvo.y.to_i + 1, alvo.name)
      return true
    end

    # ⚠️ SE NAO ESTIVER NA LISTA LOCAL, PERGUNTA-SE AO SERVIDOR.
    #
    # A lista de peers do cliente so tem quem ele conhece: o snapshot de entrada
    # mais quem apareceu no mapa dele. Alguem noutro mapa que entrou depois nao
    # esta la — e o /tp dizia "nao esta online" sobre alguem que o painel
    # mostrava online. Funcionava uma vez, logo apos entrar, e nunca mais.
    #
    # Quem sabe mesmo e o servidor. A lista local fica como atalho (resposta
    # imediata para quem esta ao lado); quando ela falha, pergunta-se.
    (achado, estado) = procurar(args)
    if estado == :ok
      ir_ter_com(achado[1])
      return true
    end
    perguntar_ao_servidor(args, nil)
    true
  rescue => e
    log("falha no comando: #{e.class}: #{e.message}")
    avisar(_INTL("Nao consegui teletransportar agora."))
    true
  end

  def msg_estado(estado, nome)
    case estado
    when :nenhum then _INTL("Nao encontrei ninguem chamado \"{1}\" online.", nome)
    when :varios then _INTL("Ha mais do que um jogador com \"{1}\" no nome. Se mais especifico.", nome)
    else              _INTL("Nome invalido.")
    end
  end
end

#-------------------------------------------------------------------------------
# O gancho no chat, com o mesmo padrao dos outros comandos.
#-------------------------------------------------------------------------------
module AnilLanRework
  module Chat
    class << self
      if !method_defined?(:anil_tp_orig_send_message)
        alias_method :anil_tp_orig_send_message, :send_message rescue nil
      end

      def send_message(text)
        return if AnilComandoTP.tratar(text)
        anil_tp_orig_send_message(text)
      end
    end
  end
end

#-------------------------------------------------------------------------------
# O LADO DE QUEM E CHAMADO
#
# ⚠️ Confere-se que o pedido vem mesmo de um admin.
#
# O pacote chega pela rede como qualquer outro. Sem esta verificacao, um cliente
# adulterado podia arrastar qualquer jogador para onde quisesse. A lista e a
# mesma, e vive no cliente — nao e uma barreira forte, mas e a que existe para
# os outros comandos e nao vale a pena fingir que e mais.
#-------------------------------------------------------------------------------
module AnilLanRework
  module Router
    class << self
      alias_method :anil_tp_orig_route_packet, :route_packet unless method_defined?(:anil_tp_orig_route_packet)

      def route_packet(packet)
        if packet.is_a?(Hash) && packet["type"].to_s == "admin_tp"
          begin
            de = packet["de"].to_s.strip.downcase
            if AnilComandoTP::ADMINS.include?(de)
              AnilComandoTP.receber_pedido(packet)
            else
              AnilComandoTP.log("pedido de tp recusado: #{de} nao e admin")
            end
          rescue
            nil
          end
          return
        end
        anil_tp_orig_route_packet(packet)
      end
    end
  end
end

module AnilComandoTP
  module_function

  def receber_pedido(packet)
    unless pode_agora?
      log("pedido de tp ignorado: nao da agora")
      return
    end
    mapa = packet["map_id"].to_i
    x = packet["x"].to_i
    y = packet["y"].to_i
    nome = packet["para_nome"].to_s

    if $game_map && $game_map.map_id.to_i == mapa
      d = casa_livre($game_map, x, y) || [x, y]
      $game_player.moveto(d[0], d[1])
      $game_player.straighten rescue nil
    else
      $game_temp.player_transferring = true
      $game_temp.player_new_map_id   = mapa
      $game_temp.player_new_x        = x
      $game_temp.player_new_y        = y
      $game_temp.player_new_direction = 8
      $game_temp.transition_processing = true
    end
    avisar(_INTL("Um administrador levou-te ate {1}.", nome))
    log("fui levado para #{mapa} (#{x},#{y})")
  rescue => e
    log("falha ao receber pedido: #{e.class}: #{e.message}")
  end
end

module AnilComandoTP
  module_function

  # Guarda o que se pediu, para saber o que fazer quando a resposta chegar.
  def perguntar_ao_servidor(nome, destino_nome)
    unless (AnilLanRework.connected? rescue false)
      avisar(_INTL("Sem ligacao ao servidor."))
      return
    end
    @pedido = (Time.now.to_f * 1000).to_i.to_s
    @pedido_destino = destino_nome
    AnilLanRework.connection.send_packet("admin_tp_query",
      "de" => meu_id, "nome" => nome.to_s, "pedido" => @pedido)
    avisar(_INTL("A procurar {1}...", nome))
  rescue => e
    log("falha a perguntar: #{e.class}: #{e.message}")
  end

  def receber_resposta(packet)
    return unless packet["pedido"].to_s == @pedido.to_s
    @pedido = nil
    destino_nome = @pedido_destino
    @pedido_destino = nil

    case packet["estado"].to_s
    when "nenhum"
      avisar(_INTL("Nao encontrei ninguem com esse nome online."))
      return
    when "varios"
      nomes = Array(packet["nomes"]).join(", ")
      avisar(_INTL("Ha varios: {1}. Se mais especifico.", nomes))
      return
    end

    nome   = packet["nome"].to_s
    id     = packet["id"].to_s
    mapa   = packet["map_id"].to_i
    x      = packet["x"].to_i
    y      = packet["y"].to_i
    canal  = packet["canal"].to_i

    # ⚠️ Avisa-se quando o canal difere, em vez de teleportar em silencio.
    #
    # Ir ter com alguem noutro canal poe-me no sitio certo do mapa errado — eu
    # nao o veria, e nao saberia porque. Melhor dizer.
    meu_canal = ($PokemonSystem.multiplayer_channel.to_i rescue 1)
    if canal > 0 && canal != meu_canal
      avisar(_INTL("{1} esta no canal {2} e tu no {3}. Muda de canal primeiro.", nome, canal, meu_canal))
      return
    end

    if destino_nome.nil?
      # Ir eu: monta-se um peer temporario com o que o servidor disse.
      fake = AnilLanRework::RemotePeer.new
      fake.name = nome
      fake.map_id = mapa
      fake.x = x
      fake.y = y
      ir_ter_com(fake)
      return
    end

    # Trazer: resolve-se o destino aqui (eu, ou alguem que eu ja veja).
    if destino_nome.to_s.downcase == "eu" || destino_nome.to_s.downcase == "mim"
      d = casa_livre($game_map, $game_player.x, $game_player.y) || [$game_player.x, $game_player.y]
      trazer!(id, nome, $game_map.map_id, d[0], d[1], _INTL("ti"))
      return
    end
    (achado_d, est_d) = procurar(destino_nome)
    unless est_d == :ok
      avisar(_INTL("Nao encontrei o destino \"{1}\".", destino_nome))
      return
    end
    alvo = achado_d[1]
    trazer!(id, nome, alvo.map_id.to_i, alvo.x.to_i, alvo.y.to_i + 1, alvo.name)
  rescue => e
    log("falha na resposta: #{e.class}: #{e.message}")
  end

  def trazer!(alvo_id, alvo_nome, mapa, x, y, nome_destino)
    AnilLanRework.connection.send_packet("admin_tp_trazer",
      "de" => meu_id, "alvo_id" => alvo_id,
      "map_id" => mapa.to_i, "x" => x.to_i, "y" => y.to_i)
    avisar(_INTL("{1} foi levado ate {2}.", alvo_nome, nome_destino))
    log("trouxe #{alvo_nome} para #{mapa}:#{x},#{y}")
  rescue => e
    log("falha a trazer: #{e.class}: #{e.message}")
  end
end

module AnilLanRework
  module Router
    class << self
      alias_method :anil_tpq_orig_route_packet, :route_packet unless method_defined?(:anil_tpq_orig_route_packet)

      def route_packet(packet)
        if packet.is_a?(Hash) && packet["type"].to_s == "admin_tp_resposta"
          (AnilComandoTP.receber_resposta(packet) rescue nil)
          return
        end
        anil_tpq_orig_route_packet(packet)
      end
    end
  end
end
