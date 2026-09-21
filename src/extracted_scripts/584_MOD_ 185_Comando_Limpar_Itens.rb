# encoding: UTF-8
#===============================================================================
# MOD: 185_Comando_Limpar_Itens
#-------------------------------------------------------------------------------
#   /limparitens          apaga todos os itens largados no mapa onde estou
#   /clearitem            o mesmo, para quem tem o teclado em ingles na cabeca
#
# ⚠️ QUEM MANDA E O SERVIDOR, E TEM DE SER.
#
# Os itens largados vivem no `storage/dropped_items.json` da VPS, por canal e
# por mapa. Apagar so no cliente nao servia de nada: o proximo
# `request_dropped_items` — que corre a cada entrada num mapa — trazia-os todos
# de volta. Por isso o comando pede, o servidor apaga, e so depois e que o
# cliente limpa o que tem no ecra.
#
# ⚠️ E NAO E COSMETICA: OS ITENS LARGADOS SAO O QUE ESTA A TRAVAR AS VIAGENS.
#
# Cada item injecta um evento com o grafico "ItemBall". Esse ficheiro nao existe
# em `Graphics/Characters/`, e no Android cada tentativa falhada custa cerca de
# dois segundos. Medido em Pallet: `ItemBall 5631ms/x3` — tres itens, cinco
# segundos e meio de ecra preto. Marengo, que nao tem itens nenhuns, entra em
# 650 ms. Este comando e, para ja, a forma de devolver esse tempo a um mapa.
#
# ⚠️ SO ADMIN.
#
# Nao ha aqui perigo de duplicacao — apaga, nao cria — mas apaga o que outros
# jogadores largaram, e isso nao se poe na mao de toda a gente.
#===============================================================================

module AnilLimparItens
  ACTIVO = true
  ADMINS = ["wallace-adm100"].freeze

  module_function

  def log(t)
    AnilLanRework.log("[LIMPAR ITENS] #{t}") rescue nil
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

  # Devolve true quando o texto era para nos — nesse caso nao segue para o chat.
  def tratar(texto)
    return false unless ACTIVO
    t = texto.to_s.strip
    return false unless t.start_with?("/")
    # "/clear item" com espaco tambem entra: foi assim que o comando foi pedido.
    corpo = t[1..-1].to_s.strip.downcase.gsub(/\s+/, "")
    return false unless ["limparitens", "clearitem", "limparitem", "clearitems"].include?(corpo)

    unless admin?
      avisar(_INTL("Esse comando é só para administradores."))
      return true
    end
    unless (AnilLanRework.connected? rescue false)
      avisar(_INTL("Sem conexão com o servidor."))
      return true
    end
    unless $game_map
      avisar(_INTL("Você não está em um mapa."))
      return true
    end

    @pedido = (Time.now.to_f * 1000).to_i.to_s
    AnilLanRework.connection.send_packet("admin_limpar_itens",
      "de"     => meu_id,
      "map_id" => $game_map.map_id.to_s,
      "pedido" => @pedido)
    avisar(_INTL("Limpando os itens do mapa {1}...", $game_map.map_id))
    log("pedido enviado para o mapa #{$game_map.map_id}")
    true
  rescue => e
    avisar(_INTL("Erro no comando: {1}", e.message))
    true
  end

  # A resposta traz a lista de event_ids que o servidor apagou. Percorre-se essa
  # lista em vez de adivinhar: se dois admins mandarem o comando ao mesmo tempo,
  # cada um limpa exactamente o que o servidor lhe disse que saiu.
  def receber_resposta(packet)
    return unless packet["pedido"].to_s == @pedido.to_s
    @pedido = nil
    ids = Array(packet["event_ids"]).map { |x| x.to_i }
    ids.each do |eid|
      AnilLanRework::DroppedItems.remove_dropped_item(eid) rescue nil
    end
    # O banco local do mapa tambem tem de ficar vazio: o `remove_dropped_item`
    # so tira um a um, e um item que ja nao tivesse evento no ecra ficava la.
    begin
      AnilLanRework::DroppedItems.get_dropped_items[$game_map.map_id] = []
    rescue
      nil
    end
    if ids.empty?
      avisar(_INTL("Não havia nenhum item largado neste mapa."))
    else
      avisar(_INTL("{1} item(ns) largado(s) apagado(s) deste mapa.", ids.length))
    end
    log("apagados: #{ids.inspect}")
  rescue => e
    log("falha ao receber resposta: #{e.class}: #{e.message}")
  end
end

#-------------------------------------------------------------------------------
# O aviso que chega aos OUTROS jogadores que estao no mesmo mapa.
#
# O servidor reaproveita o `dropped_item_pickup`, que o MOD 043 ja sabe cumprir,
# portanto do lado deles nao ha protocolo novo nenhum — os itens simplesmente
# desaparecem, como se alguem os tivesse apanhado.
#-------------------------------------------------------------------------------
module AnilLanRework
  module Router
    class << self
      alias_method :anil_limpitens_orig_route_packet, :route_packet unless method_defined?(:anil_limpitens_orig_route_packet)

      def route_packet(packet)
        if packet.is_a?(Hash) && packet["type"].to_s == "admin_limpar_itens_resposta"
          (AnilLimparItens.receber_resposta(packet) rescue nil)
          return
        end
        anil_limpitens_orig_route_packet(packet)
      end
    end
  end
end

module AnilLanRework
  module Chat
    class << self
      if !method_defined?(:anil_limpitens_orig_send_message)
        alias_method :anil_limpitens_orig_send_message, :send_message rescue nil
      end

      def send_message(text)
        return if AnilLimparItens.tratar(text)
        anil_limpitens_orig_send_message(text)
      end
    end
  end
end
