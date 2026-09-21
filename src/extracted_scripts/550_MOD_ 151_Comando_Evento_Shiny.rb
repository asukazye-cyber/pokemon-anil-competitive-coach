# encoding: UTF-8
#===============================================================================
# MOD: 151_Comando_Evento_Shiny
#-------------------------------------------------------------------------------
# Comando de chat /event, so para administradores, para ligar e desligar o
# evento de shiny em jogo — sem recompilar e para TODA a gente ao mesmo tempo.
#
#   /event                      -> mostra o estado atual
#   /event shiny 2x             -> dobra a chance, sem prazo
#   /event shiny 3x 2h          -> triplica durante 2 horas
#   /event shiny 5x 30m         -> 5x durante 30 minutos
#   /event shiny off            -> volta ao normal
#
# ⚠️ PORQUE ISTO PASSA PELO SERVIDOR, ao contrario do /clima (MOD 143).
#
# O /clima e local de proposito: o clima e derivado de uma semente que todos os
# clientes calculam igual, e forcar num muda so o que aquele jogo desenha. Ja o
# evento de shiny tem de comecar e acabar ao mesmo tempo para todos, senao uns
# apanham ao dobro e outros nao. Por isso o comando MANDA o pedido ao servidor,
# que guarda o estado, avisa toda a gente e devolve o valor a quem entra depois.
#
# ⚠️ A verificacao de administrador AQUI e so para nao gastar rede e dar uma
# mensagem util. Quem decide e o servidor, que confere o player_id da LIGACAO
# contra o admin_ids do server.json. Contornar esta lista local nao serve de
# nada — o pedido e recusado do outro lado.
#
# ⚠️ O sorteio do shiny e client-side (Settings::SHINY_POKEMON_CHANCE, lido a
# cada encontro no 0278_Pokemon.rb). Isto e administracao, nao seguranca: um
# cliente adulterado pode ignorar a taxa, tal como ja podia alterar a compilada.
#===============================================================================

module AnilEventoShinyComando
  # Espelho do admin_ids do server.json. Se divergirem, manda o servidor.
  ADMINS   = ["wallace-adm100"].freeze
  MULT_MAX = 5
  # Valor de fabrica do Settings (0003_Settings.rb): 1 em 5041.
  BASE     = 13

  @estado = nil

  class << self
    attr_reader :estado

    def meu_id
      AnilLanRework.read_cfg("multiplayer_player.txt", "id", "").to_s.strip.downcase
    rescue
      ""
    end

    def admin?
      ADMINS.include?(meu_id)
    end

    def avisar(texto)
      if AnilLanRework.respond_to?(:enqueue_popup)
        AnilLanRework.enqueue_popup(texto, 8.0) rescue nil
      else
        pbMessage(texto) rescue nil
      end
    end

    def um_em(taxa)
      t = taxa.to_i
      return "?" if t <= 0
      65_536 / t
    end

    # Troca a constante em tempo de execucao. O remove_const antes do const_set
    # e o que evita o aviso de "already initialized constant" a cada mudanca.
    def aplicar_taxa!(taxa)
      t = taxa.to_i
      return if t <= 0
      return if (Settings::SHINY_POKEMON_CHANCE rescue nil) == t
      Settings.send(:remove_const, :SHINY_POKEMON_CHANCE) if Settings.const_defined?(:SHINY_POKEMON_CHANCE)
      Settings.const_set(:SHINY_POKEMON_CHANCE, t)
      AnilLanRework.log("[EVENTO_SHINY] taxa aplicada: #{t} (1 em #{um_em(t)})") rescue nil
    rescue => e
      AnilLanRework.log("[EVENTO_SHINY] falha ao aplicar a taxa: #{e.class}: #{e.message}") rescue nil
    end

    def aplicar_estado(est)
      return unless est.is_a?(Hash)
      @estado = est
      taxa = est["taxa"].to_i
      taxa = BASE if taxa <= 0
      aplicar_taxa!(taxa)
    end

    def texto_do_estado
      est = @estado
      unless est.is_a?(Hash)
        atual = (Settings::SHINY_POKEMON_CHANCE rescue BASE)
        return "[Evento] Ainda sem resposta do servidor. Localmente: 1 em #{um_em(atual)}."
      end
      mult = est["multiplicador"].to_i
      taxa = est["taxa"].to_i
      if mult <= 1
        "[Evento] Sem evento. Chance normal: 1 em #{um_em(taxa)}."
      else
        prazo = est["termina_em"] ?
          " Termina #{Time.at(est["termina_em"].to_i).strftime("%d/%m as %H:%M")}." : " Sem prazo."
        "[Evento] Shiny #{mult}x — 1 em #{um_em(taxa)}.#{prazo}"
      end
    end

    # "2h" -> 120, "30m" -> 30, "1d" -> 1440. Sem sufixo assume horas.
    def minutos_de(txt)
      return 0 if txt.nil? || txt.to_s.strip.empty?
      t = txt.to_s.strip.downcase
      return 0 unless t =~ /\A(\d+)\s*([mhd]?)\z/
      n = $1.to_i
      case $2
      when "m" then n
      when "d" then n * 1440
      else          n * 60
      end
    end

    def ajuda
      "[Evento] Use: /event shiny 2x   |   /event shiny 3x 2h   |   /event shiny off\n" \
      "Multiplicadores de 1x a #{MULT_MAX}x. Prazo opcional: 30m, 2h, 1d."
    end

    # true = tratei o texto, e ele NAO deve virar mensagem de chat.
    def tratar(texto)
      t = texto.to_s.strip
      return false unless t =~ %r{\A/event(?:\s+(.*))?\z}i
      resto = $1.to_s.strip

      if resto.empty?
        avisar(texto_do_estado + "\n" + ajuda)
        return true
      end

      partes = resto.split(/\s+/)
      unless partes[0].to_s.downcase == "shiny"
        avisar("[Evento] So existe o evento 'shiny'.\n" + ajuda)
        return true
      end

      arg = partes[1].to_s.downcase
      if arg.empty?
        avisar(texto_do_estado + "\n" + ajuda)
        return true
      end

      unless admin?
        avisar("[Evento] Comando disponivel apenas para administradores.")
        return true
      end

      unless (AnilLanRework.connected? rescue false)
        avisar("[Evento] Sem ligacao ao servidor — o evento nao pode ser mudado offline.")
        return true
      end

      mult = nil
      if %w[off 0 nao no desligar normal].include?(arg)
        mult = 1
      elsif arg =~ /\A(\d+)x?\z/
        mult = $1.to_i
      end

      if mult.nil?
        avisar("[Evento] Nao percebi '#{partes[1]}'.\n" + ajuda)
        return true
      end
      if mult < 1 || mult > MULT_MAX
        avisar("[Evento] O multiplicador tem de estar entre 1x e #{MULT_MAX}x.")
        return true
      end

      minutos = minutos_de(partes[2])
      # Pre-visualizacao imediata: o servidor ainda vai confirmar, mas quem
      # digitou ve logo o que pediu, que era metade do ponto do comando.
      alvo = BASE * mult
      previa = (mult <= 1) ? "voltar ao normal (1 em #{um_em(BASE)})" :
                             "#{mult}x — 1 em #{um_em(alvo)}"
      previa += minutos > 0 ? ", durante #{minutos} min" : ", sem prazo"
      avisar("[Evento] A pedir ao servidor: #{previa}...")

      AnilLanRework.connection.send_packet("evento_shiny_set",
        "multiplicador" => mult, "minutos" => minutos)
      true
    rescue => e
      AnilLanRework.log("[EVENTO_SHINY] falha no comando: #{e.class}: #{e.message}") rescue nil
      false
    end
  end
end

#-------------------------------------------------------------------------------
# Entrada do comando pelo chat, encadeada como o 143 faz.
#-------------------------------------------------------------------------------
module AnilLanRework
  module Chat
    class << self
      unless method_defined?(:anil_evento_orig_send_message)
        alias_method :anil_evento_orig_send_message, :send_message rescue nil
      end

      def send_message(text)
        return if AnilEventoShinyComando.tratar(text)
        anil_evento_orig_send_message(text)
      end
    end
  end
end

#-------------------------------------------------------------------------------
# Chegada do estado: pelo broadcast (evento_shiny) e pelo join_ack, para quem
# entra a meio do evento.
#-------------------------------------------------------------------------------
module AnilLanRework
  module Router
    class << self
      unless method_defined?(:anil_evento_orig_route_packet)
        alias_method :anil_evento_orig_route_packet, :route_packet rescue nil
      end

      def route_packet(packet)
        if packet.is_a?(Hash) && packet["type"].to_s == "evento_shiny"
          AnilEventoShinyComando.aplicar_estado(packet) rescue nil
          return
        end
        anil_evento_orig_route_packet(packet)
      end
    end
  end

  class Connection
    unless method_defined?(:anil_evento_orig_handle_packet)
      alias_method :anil_evento_orig_handle_packet, :handle_packet rescue nil
    end

    def handle_packet(packet)
      if packet.is_a?(Hash) && packet["type"] == "join_ack" && packet["evento_shiny"]
        AnilEventoShinyComando.aplicar_estado(packet["evento_shiny"]) rescue nil
      end
      anil_evento_orig_handle_packet(packet)
    end
  end
end

AnilLanRework.log("151_Comando_Evento_Shiny carregado") rescue nil
