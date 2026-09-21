# encoding: UTF-8
#===============================================================================
# MOD: 186_Canal_ADM
#-------------------------------------------------------------------------------
#   /canal            diz em que canal estou
#   /canal 3          vai para o canal 3
#   /canal adm        vai para o canal fechado dos administradores
#
# ⚠️ PARA QUE SERVE O CANAL FECHADO.
#
# E um mundo a parte para ensaiar eventos com jogadores a serio — anuncios,
# capturas, disputas entre dois — sem que o servidor de verdade veja a mecanica
# antes de tempo. Tudo o que e por canal (jogadores visiveis, itens largados,
# spawns, anuncios) ja respeita essa separacao, portanto o isolamento sai de
# graca: o que la acontece nao sai de la.
#
# ⚠️ QUEM DECIDE QUEM E ADMIN E O SERVIDOR.
#
# A lista vive no `config/server.json`. Aqui nao ha lista nenhuma: o `join_ack`
# traz um `admin => true/false` e e so isso que este MOD olha. Assim, acrescentar
# um administrador novo nao obriga a compilar nem a distribuir nada — e os nomes
# deles nao ficam dentro de um Scripts.rxdata que toda a gente tem.
#
# ⚠️ E NAO SE MOVE ANTES DE O SERVIDOR CONFIRMAR.
#
# O `$PokemonSystem.multiplayer_channel` so muda quando chega o
# `channel_change_ack` com o numero do canal. Se o servidor ignorar o pedido —
# que e o que faz a quem nao e admin — o jogo fica onde estava. Escrever o 99
# no save antes da confirmacao deixava o cliente a dizer 99 e o servidor a dizer
# 1, que e precisamente o desencontro que o MOD 179 anda a apanhar.
#===============================================================================

module AnilCanalADM
  ACTIVO = true
  CANAL_ADM = 99

  module_function

  def log(t)
    AnilLanRework.log("[CANAL ADM] #{t}") rescue nil
  end

  # ⚠️ DUAS FONTES, E DE PROPOSITO.
  #
  # A boa e o `admin` que vem no `join_ack`: o servidor e que sabe quem esta no
  # `admin_ids`, e assim acrescentar um administrador nao obriga a recompilar
  # nem a distribuir nada.
  #
  # Mas se o servidor ainda for o antigo, esse campo nao existe, o `admin?` da
  # falso, e o comando desaparece sem dizer porque — cai no sussurro, como se
  # este MOD nao existisse. Foi exactamente o que aconteceu no primeiro teste, e
  # do lado de ca nao havia nada no ecra que distinguisse "nao es admin" de "o
  # servidor ainda nao foi actualizado".
  #
  # A lista local serve so para o comando APARECER. Quem deixa mesmo entrar no
  # canal e o servidor, que confere a lista DELE — por um nome aqui nao da
  # acesso a coisa nenhuma.
  ADMINS_LOCAIS = ["wallace-adm100"].freeze

  def admin?
    return true if $anil_sou_admin == true
    ADMINS_LOCAIS.include?(meu_id)
  end

  def meu_id
    AnilLanRework.read_cfg("multiplayer_player.txt", "id", "").to_s.strip.downcase
  rescue
    ""
  end

  def avisar(t)
    if AnilLanRework.respond_to?(:add_popup)
      AnilLanRework.add_popup(t, 8.0) rescue nil
    else
      pbMessage(t) rescue nil
    end
  end

  def canal_actual
    ($PokemonSystem ? $PokemonSystem.multiplayer_channel.to_i : 1)
  rescue
    1
  end

  def nome_do_canal(n)
    (n.to_i == CANAL_ADM) ? _INTL("ADM") : n.to_s
  end

  def pedir!(n)
    unless (AnilLanRework.connected? rescue false)
      avisar(_INTL("Sem conexão com o servidor."))
      return
    end
    @pedido = n.to_i
    AnilLanRework.connection.send_packet("change_channel", "channel_id" => n.to_i)
    log("pedido o canal #{n}")
  rescue => e
    log("falha ao pedir: #{e.class}: #{e.message}")
  end

  # Devolve true quando o texto era para nos.
  def tratar(texto)
    return false unless ACTIVO
    t = texto.to_s.strip
    return false unless t.start_with?("/")
    m = t.match(%r{\A/canal(?:\s+(\S+))?\s*\z}i)
    return false unless m
    # ⚠️ Para quem nao e admin, isto NAO e um comando.
    #
    # Devolver false deixa o texto seguir o caminho normal do chat, que e
    # exactamente o que aconteceria se este MOD nao existisse. Uma recusa
    # explicita — ou ate um silencio — dizia a quem tentasse que ha aqui alguma
    # coisa escondida.
    return false unless admin?

    arg = m[1].to_s.strip.downcase
    if arg.empty?
      avisar(_INTL("Você está no canal {1}.", nome_do_canal(canal_actual)))
      return true
    end

    if arg == "adm" || arg == "admin"
      if canal_actual == CANAL_ADM
        avisar(_INTL("Você já está no canal ADM."))
      else
        pedir!(CANAL_ADM)
        avisar(_INTL("Entrando no canal ADM..."))
      end
      return true
    end

    n = arg.to_i
    if n >= 1 && n <= 10
      if canal_actual == n
        avisar(_INTL("Você já está no canal {1}.", n))
      else
        pedir!(n)
        avisar(_INTL("Entrando no canal {1}...", n))
      end
    else
      avisar(_INTL("Canal inválido. Use /canal 1 a 10, ou /canal adm."))
    end
    true
  rescue => e
    avisar(_INTL("Erro no comando: {1}", e.message))
    true
  end

  # Chega a confirmacao: agora sim o jogo muda de canal.
  def confirmado!(n)
    n = n.to_i
    return if n <= 0
    ($PokemonSystem.multiplayer_channel = n) rescue nil
    (AnilSincCanal.marcar_anunciado!(n) rescue nil)
    # Mudar de canal nao recarrega o mapa: os itens largados do canal novo nunca
    # chegariam sozinhos. E o mesmo cuidado que o MOD 179 tem.
    (AnilRefreshItens.marcar!("mudanca de canal confirmada") rescue nil)
    log("confirmado o canal #{n}")
    avisar(_INTL("Você está no canal {1}.", nome_do_canal(n))) if @pedido == n
    @pedido = nil
  rescue => e
    log("falha ao confirmar: #{e.class}: #{e.message}")
  end
end

module AnilLanRework
  module Router
    class << self
      alias_method :anil_canaladm_orig_route_packet, :route_packet unless method_defined?(:anil_canaladm_orig_route_packet)

      def route_packet(packet)
        if packet.is_a?(Hash)
          case packet["type"].to_s
          when "channel_change_ack"
            (AnilCanalADM.confirmado!(packet["canal"]) rescue nil) if packet["canal"]
          end
        end
        anil_canaladm_orig_route_packet(packet)
      end
    end
  end
end

module AnilLanRework
  module Chat
    class << self
      if !method_defined?(:anil_canaladm_orig_send_message)
        alias_method :anil_canaladm_orig_send_message, :send_message rescue nil
      end

      def send_message(text)
        return if AnilCanalADM.tratar(text)
        anil_canaladm_orig_send_message(text)
      end
    end
  end
end

#-------------------------------------------------------------------------------
# ⚠️ O join_ack NAO PASSA PELO Router.
#
# Ele e tratado no `AnilLanRework::Connection#handle_packet`, que tem um `case`
# proprio e nunca reencaminha esse tipo. O gancho estava no Router e por isso
# nunca via nada — o `$anil_sou_admin` ficava sempre falso, mesmo com o servidor
# certo do outro lado.
#
# Aqui so se LE o campo; o pacote segue o caminho normal logo a seguir.
#-------------------------------------------------------------------------------
class AnilLanRework::Connection
  unless method_defined?(:anil_canaladm_orig_handle_packet) ||
         private_method_defined?(:anil_canaladm_orig_handle_packet)
    alias_method :anil_canaladm_orig_handle_packet, :handle_packet rescue nil
  end

  def handle_packet(packet)
    if packet.is_a?(Hash) && packet["type"].to_s == "join_ack"
      $anil_sou_admin = (packet["admin"] == true)
      (AnilCanalADM.log("o servidor diz que sou admin: #{$anil_sou_admin}") rescue nil)
    end
    anil_canaladm_orig_handle_packet(packet)
  end
end
