# encoding: utf-8
#===============================================================================
# MOD: 193_Arena_Log_Rede — o cronómetro da arena
#===============================================================================
#
# ⚠️ ISTO NÃO É UM LOG DE DEPURAÇÃO. É UM INSTRUMENTO DE MEDIÇÃO.
#
# A diferença importa. Um log de depuração conta o que aconteceu; este conta
# QUANDO, QUANTO e COM QUE INTERVALO — porque as três perguntas que temos em
# aberto não se respondem com uma narrativa:
#
#   1. Quantos bytes e quantos pacotes saem e entram por segundo, por tipo?
#   2. Os pacotes chegam com o intervalo com que foram enviados, ou aos molhos?
#   3. Quando o boneco do outro treme, o que faltou — rede ou frames?
#
# ⚠️ NÃO USA OS LOGS GLOBAIS, E ISSO É DE PROPÓSITO.
#
# O `$ENABLE_DEBUG_LOGS` e o `$anil_debug_log_enabled` deste projecto travam o
# "recuperar partida" quando ficam ligados. Este módulo escreve num ficheiro
# próprio, nasce DESLIGADO, e não toca em nenhuma dessas variáveis.
#
# ⚠️ ONDE ESTÃO OS GANCHOS, E PORQUÊ AÍ.
#
# Nos dois lados do CODEC, e não no `send_packet`/`handle_packet`:
#
#   encode(pacote) -> devolve a linha         ... tamanho EXACTO na saída
#   decode(linha)  -> devolve o pacote        ... tamanho EXACTO na entrada
#
# É o único ponto do sistema onde se vê a mesma coisa nas duas formas — o tipo
# (do Hash) e os bytes (da String) — sem voltar a codificar nada para os medir.
# Um gancho no `send_packet` obrigava a codificar duas vezes só para saber o
# peso, e isso mudava aquilo que se está a medir.
#
# Ligar: /arenalog        Desligar: /arenalog off       Resumo já: /arenalog ja
#===============================================================================

module AnilArenaLog
  FICHEIRO   = "arena_rede.log"
  RESUMO_SEG = 5.0      # de quantos em quantos segundos sai um balanço
  DESPEJO    = 1.0      # segundos entre gravações em disco
  TECTO_MB   = 8        # acima disto recomeça o ficheiro
  LINHAS_MAX = 4000     # linhas em memória antes de forçar despejo

  # ⚠️ NEM TUDO O QUE PASSA INTERESSA NA MESMA MEDIDA.
  #
  # O fluxo cru serve para forense — ver a sequência exacta de um engasgo. O
  # resumo é o que responde às perguntas. Guardar o fluxo cru de TUDO enche 8 MB
  # em três minutos e não se lê; por isso o cru é dos tipos da arena e o resto
  # entra só nas contas do resumo.
  CRUS = %w[
    player_state caverna_golpe caverna_mob caverna_mobs caverna_morte
    arena_golpe arena_parceiro arena_dano arena_fim
    request_drop_item claim_dropped_item dropped_item_spawn
    claim_dropped_item_result drop_item_result
  ].freeze

  class << self
    attr_accessor :activo

    def ligado?
      @activo == true
    end

    #---------------------------------------------------------------------------
    # LIGAR E DESLIGAR
    #---------------------------------------------------------------------------
    def ligar!
      @activo    = true
      @inicio    = Time.now.to_f
      @linhas    = []
      @ultimo_de = {}     # tipo => instante do último, por sentido
      @contas    = {}     # [sentido, tipo] => [n, bytes, [intervalos]]
      @resumo_em = @inicio + RESUMO_SEG
      @despejo_em = @inicio + DESPEJO
      @frames    = []
      @tick_ms   = []
      @secos     = 0
      @saltos    = 0
      @amostras_buffer = []
      apagar!
      escrever_cabecalho!
      true
    rescue
      false
    end

    def desligar!
      return false unless ligado?
      resumo!("fim da sessão")
      despejar!
      @activo = false
      true
    rescue
      @activo = false
      false
    end

    def caminho
      FICHEIRO
    end

    def apagar!
      File.delete(FICHEIRO) if File.exist?(FICHEIRO)
    rescue
      nil
    end

    def ms
      ((Time.now.to_f - @inicio.to_f) * 1000.0).round
    rescue
      0
    end

    #---------------------------------------------------------------------------
    # AS DUAS PORTAS
    #---------------------------------------------------------------------------
    # ⚠️ O INTERVALO É A MEDIDA QUE INTERESSA, E NÃO O RELÓGIO.
    #
    # Saber que um pacote chegou aos 4213 ms não diz nada sozinho. O que diz é o
    # tempo desde o anterior DO MESMO TIPO: se o `player_state` sai de 33 em 33
    # e chega de 12 em 12 seguido de um de 90, então ele viaja aos molhos — e é
    # isso, e não a média, que faz o boneco tremer.
    def registar(sentido, tipo, bytes)
      return unless ligado?
      agora = Time.now.to_f
      chave = [sentido, tipo]
      anterior = @ultimo_de[chave]
      intervalo = anterior ? ((agora - anterior) * 1000.0) : nil
      @ultimo_de[chave] = agora

      c = (@contas[chave] ||= [0, 0, []])
      c[0] += 1
      c[1] += bytes.to_i
      c[2] << intervalo if intervalo

      return unless CRUS.include?(tipo.to_s)
      @linhas << ("%7d  %s  %-24s %5dB  %s" % [
        ms, (sentido == :out ? "SAI" : "ENT"), tipo.to_s, bytes.to_i,
        intervalo ? ("+%6.1fms" % intervalo) : "      —"
      ])
      despejar! if @linhas.length >= LINHAS_MAX
    rescue
      nil
    end

    #---------------------------------------------------------------------------
    # O RELÓGIO DO JOGO
    #---------------------------------------------------------------------------
    # ⚠️ SEM ISTO NÃO SE DISTINGUE "A REDE ATRASOU-SE" DE "O JOGO PAROU".
    #
    # Os dois dão a mesma imagem no ecrã: o boneco do outro congela. Mas um
    # resolve-se com menos pacotes e o outro com menos trabalho por frame, e são
    # correcções opostas. O tempo entre frames e o tempo gasto DENTRO do tick da
    # arena respondem à pergunta.
    def frame!(dt_ms, tick_ms)
      return unless ligado?
      @frames  << dt_ms
      @tick_ms << tick_ms if tick_ms && tick_ms > 0.0
      agora = Time.now.to_f
      resumo! if agora >= @resumo_em.to_f
      despejar! if agora >= @despejo_em.to_f
    rescue
      nil
    end

    # Chamado por cada peer desenhado: quantos pontos tem o histórico dele e se
    # o relógio de reprodução já passou do fim (buffer seco).
    def buffer!(pontos, seco, salto)
      return unless ligado?
      @amostras_buffer << pontos.to_i
      @secos  += 1 if seco
      @saltos += 1 if salto
    rescue
      nil
    end

    #---------------------------------------------------------------------------
    # O BALANÇO
    #---------------------------------------------------------------------------
    def resumo!(motivo = nil)
      return unless ligado?
      agora = Time.now.to_f
      janela = agora - (@resumo_desde || @inicio).to_f
      janela = 0.001 if janela <= 0
      @resumo_desde = agora
      @resumo_em = agora + RESUMO_SEG

      @linhas << ""
      @linhas << ("=" * 78)
      @linhas << ("RESUMO aos %d ms  (janela de %.1f s)%s" %
                  [ms, janela, motivo ? "  — #{motivo}" : ""])
      @linhas << ("=" * 78)

      # ── rede, por tipo ──────────────────────────────────────────────────────
      @linhas << ("%-4s %-24s %6s %8s %9s %8s %8s %8s" %
                  ["", "tipo", "n", "B/s", "por seg", "med ms", "p95 ms", "max ms"])
      total_out = 0
      total_in  = 0
      @contas.keys.sort_by { |(s, t)| [s.to_s, t.to_s] }.each do |chave|
        sentido, tipo = chave
        n, bytes, intervalos = @contas[chave]
        next if n.zero?
        bs = (bytes / janela)
        sentido == :out ? (total_out += bs) : (total_in += bs)
        med = p95 = mx = 0.0
        unless intervalos.empty?
          ord = intervalos.sort
          med = ord[ord.length / 2]
          p95 = ord[[(ord.length * 0.95).floor, ord.length - 1].min]
          mx  = ord.last
        end
        @linhas << ("%-4s %-24s %6d %8.0f %9.1f %8.1f %8.1f %8.1f" %
                    [(sentido == :out ? "SAI" : "ENT"), tipo.to_s, n, bs,
                     n / janela, med, p95, mx])
      end
      @linhas << ("%-4s %-24s %6s %8.0f" % ["SAI", "TOTAL", "", total_out])
      @linhas << ("%-4s %-24s %6s %8.0f" % ["ENT", "TOTAL", "", total_in])

      # ── o jogo ──────────────────────────────────────────────────────────────
      unless @frames.empty?
        f = @frames.sort
        fps = 1000.0 / [f[f.length / 2], 0.001].max
        pior = f.last
        @linhas << ""
        @linhas << ("frames: %d   mediana %.1f ms (%.0f fps)   pior %.1f ms   acima de 50 ms: %d" %
                    [f.length, f[f.length / 2], fps, pior, f.count { |v| v > 50.0 }])
      end
      unless @tick_ms.empty?
        t = @tick_ms.sort
        @linhas << ("tick da arena: mediana %.2f ms   p95 %.2f ms   pior %.2f ms" %
                    [t[t.length / 2], t[[(t.length * 0.95).floor, t.length - 1].min], t.last])
      end

      # ── a interpolação ──────────────────────────────────────────────────────
      unless @amostras_buffer.empty?
        b = @amostras_buffer.sort
        @linhas << ("buffer dos peers: mediana %d pontos   mínimo %d   " \
                    "vezes seco: %d   saltos de teletransporte: %d" %
                    [b[b.length / 2], b.first, @secos, @saltos])
        if @secos > 0
          @linhas << ("  ^ SECO quer dizer: o relógio de reprodução passou do último ponto " \
                      "recebido. É aqui que o boneco congela.")
        end
      end
      @linhas << ("=" * 78)
      @linhas << ""

      @contas = {}
      @frames = []
      @tick_ms = []
      @amostras_buffer = []
      @secos = 0
      @saltos = 0
    rescue => e
      @linhas << "falha no resumo: #{e.class}: #{e.message}"
    end

    #---------------------------------------------------------------------------
    # DISCO
    #---------------------------------------------------------------------------
    # ⚠️ ESCREVE-SE EM LOTE, PELA MESMA RAZÃO QUE OS PACOTES VÃO EM LOTE.
    #
    # Um `File.open` por pacote seriam 47 aberturas de ficheiro por segundo na
    # thread do jogo — o instrumento passaria a ser o maior gargalo da medição,
    # e mediria a si próprio.
    def despejar!
      @despejo_em = Time.now.to_f + DESPEJO
      return if @linhas.nil? || @linhas.empty?
      lote = @linhas
      @linhas = []
      rodar_se_grande!
      File.open(FICHEIRO, "a") { |f| f.puts(lote) }
    rescue
      nil
    end

    def rodar_se_grande!
      return unless File.exist?(FICHEIRO)
      return if File.size(FICHEIRO) < (TECTO_MB * 1024 * 1024)
      File.delete(FICHEIRO)
      File.open(FICHEIRO, "a") { |f| f.puts("--- ficheiro recomeçado (passou de #{TECTO_MB} MB) ---") }
    rescue
      nil
    end

    def escrever_cabecalho!
      linhas = []
      linhas << ("=" * 78)
      linhas << "ARENA — LOG DE REDE"
      linhas << ("iniciado em %s" % Time.now.strftime("%Y-%m-%d %H:%M:%S"))
      linhas << ("mapa %s   arena activa: %s   caverna: %s" % [
        ($game_map ? $game_map.map_id : "?"),
        (AnilArena.activa? rescue "?"),
        (defined?(AnilRaidCaverna) ? (AnilRaidCaverna.dentro? rescue "?") : "n/d")])
      linhas << ("atraso de interpolação em uso: %.0f ms" %
                 ((AnilMovimentoRemoto.atraso rescue 0.0) * 1000.0))
      linhas << ""
      linhas << "COLUNAS DO FLUXO:  ms desde o início | SAI/ENT | tipo | bytes | intervalo desde o anterior do mesmo tipo"
      linhas << ("=" * 78)
      linhas << ""
      File.open(FICHEIRO, "a") { |f| f.puts(linhas) }
    rescue
      nil
    end
  end
end

#-------------------------------------------------------------------------------
# OS GANCHOS DO CODEC
#
# ⚠️ Nomes de alias próprios (`anil_logrede_*`). Dois MODs com o mesmo nome de
# alias já mataram meia dúzia de comandos neste projecto, em silêncio.
#-------------------------------------------------------------------------------
module AnilLanRework
  module Codec
    class << self
      unless method_defined?(:anil_logrede_orig_encode)
        alias_method :anil_logrede_orig_encode, :encode
        def encode(packet)
          linha = anil_logrede_orig_encode(packet)
          if AnilArenaLog.ligado?
            AnilArenaLog.registar(:out, (packet["type"] rescue "?"), linha.bytesize)
          end
          linha
        end
      end

      unless method_defined?(:anil_logrede_orig_decode)
        alias_method :anil_logrede_orig_decode, :decode
        def decode(line)
          pacote = anil_logrede_orig_decode(line)
          if AnilArenaLog.ligado? && pacote.is_a?(Hash)
            AnilArenaLog.registar(:in, (pacote["type"] rescue "?"), line.to_s.bytesize + 1)
          end
          pacote
        end
      end
    end
  end
end

#-------------------------------------------------------------------------------
# O RELÓGIO: quanto tempo entre frames, e quanto se gasta dentro da arena
#-------------------------------------------------------------------------------
module AnilArena
  class << self
    unless method_defined?(:anil_logrede_orig_tick!)
      alias_method :anil_logrede_orig_tick!, :tick!
      def tick!
        return anil_logrede_orig_tick! unless AnilArenaLog.ligado?
        t0 = Time.now.to_f
        r = anil_logrede_orig_tick!
        $anil_logrede_tick_ms = (Time.now.to_f - t0) * 1000.0
        r
      end
    end
  end
end

class Scene_Map
  unless method_defined?(:anil_logrede_orig_update) ||
         private_method_defined?(:anil_logrede_orig_update)
    alias_method :anil_logrede_orig_update, :update
    def update
      anil_logrede_orig_update
      return unless AnilArenaLog.ligado?
      agora = Time.now.to_f
      dt = ($anil_logrede_frame ? (agora - $anil_logrede_frame) * 1000.0 : 0.0)
      $anil_logrede_frame = agora
      AnilArenaLog.frame!(dt, $anil_logrede_tick_ms)
      $anil_logrede_tick_ms = nil
    end
  end
end

#-------------------------------------------------------------------------------
# A INTERPOLAÇÃO: quantos pontos há no histórico e se ela ficou sem chão
#-------------------------------------------------------------------------------
module AnilMovimentoRemoto
  class << self
    unless method_defined?(:anil_logrede_orig_estado)
      alias_method :anil_logrede_orig_estado, :estado
      def estado(peer)
        r = anil_logrede_orig_estado(peer)
        if AnilArenaLog.ligado?
          pontos = (peer && peer.mov_pontos) || []
          # Seco = o relógio de reprodução passou do último ponto recebido. É
          # exactamente o instante em que o boneco deixa de ter para onde ir.
          seco = (!pontos.empty? && peer.mov_relogio &&
                  peer.mov_relogio >= pontos.last[0]) rescue false
          AnilArenaLog.buffer!(pontos.length, seco, false)
        end
        r
      end
    end
  end
end

#-------------------------------------------------------------------------------
# O COMANDO
#-------------------------------------------------------------------------------
module AnilArenaLogComando
  module_function

  def tratar(texto)
    t = texto.to_s.strip
    return false unless t =~ %r{\A/arenalog(?:\s+(.*))?\z}i
    arg = $1.to_s.strip.downcase
    # Mesma porta do resto: quem testa a arena testa o instrumento.
    a_mais = (defined?(AnilRaidCaverna) && (AnilRaidCaverna.admin? rescue false))
    unless a_mais || (AnilArena.libertada? rescue false)
      return false
    end

    case arg
    when "off", "desligar", "parar"
      if AnilArenaLog.desligar!
        pbMessage(_INTL("Log de rede desligado.\nO ficheiro é {1}, na pasta do jogo.",
                        AnilArenaLog.caminho)) rescue nil
      else
        pbMessage(_INTL("O log já estava desligado.")) rescue nil
      end
    when "ja", "já", "resumo"
      if AnilArenaLog.ligado?
        AnilArenaLog.resumo!("pedido à mão")
        AnilArenaLog.despejar!
        pbMessage(_INTL("Resumo escrito em {1}.", AnilArenaLog.caminho)) rescue nil
      else
        pbMessage(_INTL("O log não está a correr. Use /arenalog para o ligar.")) rescue nil
      end
    else
      AnilArenaLog.ligar!
      pbMessage(_INTL("Log de rede LIGADO.\nGrava tudo o que entra e sai, com intervalos, em {1}.\nUm balanço a cada {2} segundos.\n/arenalog off para parar.",
                      AnilArenaLog.caminho, AnilArenaLog::RESUMO_SEG.to_i)) rescue nil
    end
    true
  rescue => e
    (AnilLanRework.log("[ARENALOG] falha: #{e.class}: #{e.message}") rescue nil)
    true
  end
end

module AnilLanRework
  module Chat
    class << self
      if !method_defined?(:anil_logrede_orig_send_message)
        alias_method :anil_logrede_orig_send_message, :send_message rescue nil
      end

      def send_message(text)
        return if AnilArenaLogComando.tratar(text)
        anil_logrede_orig_send_message(text)
      end
    end
  end
end
