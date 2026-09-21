# encoding: utf-8
#===============================================================================
# MOD: 194_Arena_Log_Movimento — o orçamento do atraso visual
#===============================================================================
#
# ⚠️ ISTO MEDE UMA COISA SÓ, E MEDE-A INTEIRA.
#
# Entre o outro jogador carregar numa seta e eu ver o boneco dele mexer-se, há
# quatro esperas em fila. O log de rede (MOD 193) mede a segunda; este mede as
# quatro, e a soma delas é o número que interessa quando se diz "tirar o atraso
# visual". Sem as separar, corta-se onde é mais fácil em vez de onde há mais.
#
#   1. AMOSTRAGEM   ele mexeu-se, mas o pacote só sai no próximo envio.
#                   Com envio a 33 ms isto é 0–33, em média 16.
#
#   2. VIAGEM       o tempo até o pacote chegar cá, e sobretudo a IRREGULARIDADE
#                   desse tempo. Mede-se contra o relógio do remetente (`t_env`),
#                   que já viaja em cada pacote.
#
#   3. COLCHÃO      eu desenho de propósito no passado, para ter dois pontos
#                   entre os quais interpolar. É o `ATRASO_*` do MOD 136.
#
#   4. FRAME        o desenho só aparece no frame seguinte: 0–16 ms a 60 fps,
#                   0–33 no JoiPlay.
#
# ⚠️ O QUE ESTE LOG NÃO PODE MEDIR, E PORQUÊ.
#
# A viagem em valor ABSOLUTO. Os dois relógios não estão acertados um com o
# outro, portanto `chegada - t_env` traz lá dentro um desvio desconhecido e
# constante. O que se faz é o que se faz em qualquer sistema destes: guarda-se o
# MENOR valor observado na janela e trata-se como o zero. O que sobra acima
# desse mínimo é a irregularidade — e é ela, não a latência de base, que faz o
# boneco tremer.
#
# Ligar: /movlog        Desligar: /movlog off        Resumo já: /movlog ja
#===============================================================================

module AnilMovLog
  FICHEIRO   = "arena_movimento.log"
  RESUMO_SEG = 5.0
  DESPEJO    = 1.0
  TECTO_MB   = 8
  LINHAS_MAX = 4000

  # ⚠️ UMA AMOSTRA POR FRAME POR PEER ENCHE O FICHEIRO E NÃO ACRESCENTA NADA.
  #
  # A 60 fps com dois peers são 120 linhas por segundo a dizer quase o mesmo. O
  # fluxo cru guarda uma amostra a cada N frames — o suficiente para se ver a
  # forma da curva — e as CONTAS usam todas as amostras, que é onde a precisão
  # faz falta.
  CRU_CADA = 12

  class << self
    attr_accessor :activo

    def ligado?
      @activo == true
    end

    def ligar!
      @activo     = true
      @inicio     = Time.now.to_f
      @linhas     = []
      @resumo_em  = @inicio + RESUMO_SEG
      @despejo_em = @inicio + DESPEJO
      @conta_frames = 0
      zerar_janela!
      apagar!
      cabecalho!
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

    def caminho; FICHEIRO; end

    def zerar_janela!
      @amostragem = []    # (1) ms entre a posição mudar e o pacote sair
      @viagem     = []    # (2) ms acima do mínimo observado
      @colchao    = {}    # (3) por peer: idade do que se desenha
      @frames     = []    # (4) ms entre frames
      @modo       = Hash.new(0)   # interpola / segura / preve / espera
      @secos      = 0
      @saltos     = 0
      @dist_atras = []    # px entre o desenhado e o último conhecido
      @resumo_desde = Time.now.to_f
    rescue
      nil
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
    # (1) AMOSTRAGEM — do lado de quem envia
    #---------------------------------------------------------------------------
    # ⚠️ ESTA ESPERA É NOSSA E É A MAIS FÁCIL DE CORTAR.
    #
    # Não depende da rede nem do outro: depende só de quantas vezes por segundo
    # decidimos falar. Se der 16 ms de mediana, subir o ritmo de envio corta-a
    # ao meio sem tocar em mais nada — e é aí que se deve mexer primeiro, porque
    # é a única das quatro que não tem contrapartida.
    def mexeu!(rx, ry)
      return unless ligado?
      if @pos_ant && (rx != @pos_ant[0] || ry != @pos_ant[1])
        @mudou_em ||= Time.now.to_f
      end
      @pos_ant = [rx, ry]
    rescue
      nil
    end

    def enviei!
      return unless ligado?
      if @mudou_em
        @amostragem << ((Time.now.to_f - @mudou_em) * 1000.0)
        @mudou_em = nil
      end
    rescue
      nil
    end

    #---------------------------------------------------------------------------
    # (2) VIAGEM — do lado de quem recebe
    #---------------------------------------------------------------------------
    def chegou!(t_env_ms, chegada_s)
      return unless ligado?
      return unless t_env_ms
      bruto = (chegada_s * 1000.0) - t_env_ms.to_f
      @viagem_min = bruto if @viagem_min.nil? || bruto < @viagem_min
      @viagem << (bruto - @viagem_min)
    rescue
      nil
    end

    #---------------------------------------------------------------------------
    # (3) COLCHÃO — o que se desenha e que idade tem
    #---------------------------------------------------------------------------
    def desenhou!(id, idade_ms, modo, pontos, dist)
      return unless ligado?
      (@colchao[id.to_s] ||= []) << idade_ms
      @modo[modo] += 1
      @secos  += 1 if modo == :segura || modo == :preve
      @dist_atras << dist if dist
      @conta_frames += 1
      return unless (@conta_frames % CRU_CADA).zero?
      @linhas << ("%7d  peer %-14s idade %6.1fms  %-8s pontos %2d  atrás %5.0fpx" %
                  [ms, id.to_s[0, 14], idade_ms, modo.to_s, pontos.to_i, dist.to_f])
      despejar! if @linhas.length >= LINHAS_MAX
    rescue
      nil
    end

    def saltou!
      @saltos += 1 if ligado?
    rescue
      nil
    end

    #---------------------------------------------------------------------------
    # (4) FRAME
    #---------------------------------------------------------------------------
    def frame!(dt_ms)
      return unless ligado?
      @frames << dt_ms if dt_ms > 0.0
      agora = Time.now.to_f
      resumo! if agora >= @resumo_em.to_f
      despejar! if agora >= @despejo_em.to_f
    rescue
      nil
    end

    #---------------------------------------------------------------------------
    # O ORÇAMENTO
    #---------------------------------------------------------------------------
    def med(a)
      return 0.0 if a.nil? || a.empty?
      o = a.sort
      o[o.length / 2]
    end

    def p95(a)
      return 0.0 if a.nil? || a.empty?
      o = a.sort
      o[[(o.length * 0.95).floor, o.length - 1].min]
    end

    def resumo!(motivo = nil)
      return unless ligado?
      agora = Time.now.to_f
      janela = agora - @resumo_desde.to_f
      janela = 0.001 if janela <= 0
      @resumo_em = agora + RESUMO_SEG

      colchao_todos = @colchao.values.flatten
      linhas = []
      linhas << ""
      linhas << ("=" * 78)
      linhas << ("ORÇAMENTO DE ATRASO VISUAL aos %d ms  (janela de %.1f s)%s" %
                 [ms, janela, motivo ? "  — #{motivo}" : ""])
      linhas << ("=" * 78)
      linhas << ("%-34s %10s %10s %8s" % ["etapa", "mediana", "p95", "n"])
      linhas << ("%-34s %9.1f %9.1f %8d" %
                 ["1. amostragem (mexeu -> enviou)", med(@amostragem), p95(@amostragem), @amostragem.length])
      linhas << ("%-34s %9.1f %9.1f %8d" %
                 ["2. viagem (acima do mínimo)", med(@viagem), p95(@viagem), @viagem.length])
      linhas << ("%-34s %9.1f %9.1f %8d" %
                 ["3. colchão (idade do desenho)", med(colchao_todos), p95(colchao_todos), colchao_todos.length])
      linhas << ("%-34s %9.1f %9.1f %8d" %
                 ["4. frame", med(@frames), p95(@frames), @frames.length])
      linhas << ("-" * 78)
      linhas << ("%-34s %9.1f %9.1f" %
                 ["TOTAL VISÍVEL",
                  med(@amostragem) + med(@viagem) + med(colchao_todos) + med(@frames),
                  p95(@amostragem) + p95(@viagem) + p95(colchao_todos) + p95(@frames)])
      linhas << ""

      # ── como é que o desenho foi obtido ─────────────────────────────────────
      total_modo = @modo.values.inject(0) { |s, v| s + v }
      if total_modo > 0
        linhas << "de onde veio cada frame desenhado:"
        [[:interpola, "entre dois pontos (o bom)"],
         [:segura,    "parado no último (buffer seco)"],
         [:preve,     "adivinhado (extrapolação)"],
         [:espera,    "antes do início do histórico"]].each do |(k, txt)|
          n = @modo[k]
          next if n.zero?
          linhas << ("  %-32s %7d  %5.1f%%" % [txt, n, 100.0 * n / total_modo])
        end
        if @modo[:segura] > 0
          linhas << ("  ^ cada um destes frames é um frame em que o boneco do outro NÃO se mexeu")
          linhas << ("    porque não havia dados. É a causa directa do 'trava e teletransporta'.")
        end
      end

      unless @dist_atras.empty?
        linhas << ("distância entre o desenhado e o último conhecido: mediana %.0f px   p95 %.0f px" %
                   [med(@dist_atras), p95(@dist_atras)])
      end
      linhas << ("saltos de teletransporte (acima de %d casas): %d" %
                 [(AnilMovimentoRemoto::TELEPORTE_TILES rescue 15), @saltos])
      linhas << ("colchão configurado agora: %.0f ms" %
                 ((AnilMovimentoRemoto.atraso rescue 0.0) * 1000.0))

      # ── onde cortar ─────────────────────────────────────────────────────────
      linhas << ""
      linhas << "onde há mais para cortar:"
      ordem = [["amostragem — subir o ritmo de envio", med(@amostragem)],
               ["viagem — só melhora com menos pacotes ou UDP", med(@viagem)],
               ["colchão — baixar o ATRASO, ao preço de secar mais", med(colchao_todos)],
               ["frame — depende do FPS do aparelho", med(@frames)]]
      ordem.sort_by { |(_t, v)| -v }.each_with_index do |(t, v), i|
        linhas << ("  %d. %-46s %6.1f ms" % [i + 1, t, v])
      end
      linhas << ("=" * 78)
      linhas << ""

      @linhas.concat(linhas)
      zerar_janela!
    rescue => e
      @linhas << "falha no resumo: #{e.class}: #{e.message}"
    end

    #---------------------------------------------------------------------------
    # DISCO
    #---------------------------------------------------------------------------
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
      File.open(FICHEIRO, "a") { |f| f.puts("--- recomeçado (passou de #{TECTO_MB} MB) ---") }
    rescue
      nil
    end

    def cabecalho!
      l = []
      l << ("=" * 78)
      l << "ARENA — LOG DE MOVIMENTO"
      l << ("iniciado em %s" % Time.now.strftime("%Y-%m-%d %H:%M:%S"))
      l << ("colchão em uso: %.0f ms   ritmo de envio na arena: 33 ms" %
            ((AnilMovimentoRemoto.atraso rescue 0.0) * 1000.0))
      l << ""
      l << "FLUXO:  ms | peer | idade do que se desenha | modo | pontos no histórico | px atrás"
      l << "RESUMO: a cada #{RESUMO_SEG.to_i} s, com as quatro esperas separadas."
      l << ("=" * 78)
      l << ""
      File.open(FICHEIRO, "a") { |f| f.puts(l) }
    rescue
      nil
    end
  end
end

#-------------------------------------------------------------------------------
# (1) O LADO DE QUEM ENVIA
#-------------------------------------------------------------------------------
module AnilLanRework
  module WorldSync
    class << self
      unless method_defined?(:anil_movlog_orig_send_player_state)
        alias_method :anil_movlog_orig_send_player_state, :send_player_state
        def send_player_state
          r = anil_movlog_orig_send_player_state
          AnilMovLog.enviei! if AnilMovLog.ligado?
          r
        end
      end
    end
  end
end

#-------------------------------------------------------------------------------
# (2) O LADO DE QUEM RECEBE
#
# ⚠️ O gancho é no `registrar!` e não no `handle_packet`: é ali que o `t_env` já
# está escrito no peer e que se sabe a hora exacta de chegada. Medir no
# `handle_packet` traria o tempo de processamento de tudo o resto lá dentro.
#-------------------------------------------------------------------------------
module AnilMovimentoRemoto
  class << self
    unless method_defined?(:anil_movlog_orig_registrar!)
      alias_method :anil_movlog_orig_registrar!, :registrar!
      def registrar!(peer)
        AnilMovLog.chegou!((peer.t_env rescue nil), Time.now.to_f) if AnilMovLog.ligado?
        anil_movlog_orig_registrar!(peer)
      end
    end

    #---------------------------------------------------------------------------
    # (3) O COLCHÃO — e é aqui que se vê a verdade sobre ele
    #
    # ⚠️ A IDADE MEDE-SE, NÃO SE ASSUME.
    #
    # A constante diz 33 ms; o que se desenha pode ter 90 se os pacotes não
    # chegaram. É a diferença entre o relógio de reprodução e o ponto mais
    # recente recebido — o número real, frame a frame.
    #---------------------------------------------------------------------------
    unless method_defined?(:anil_movlog_orig_estado)
      alias_method :anil_movlog_orig_estado, :estado
      def estado(peer)
        r = anil_movlog_orig_estado(peer)
        return r unless AnilMovLog.ligado?
        begin
          pontos = (peer && peer.mov_pontos) || []
          unless pontos.empty? || peer.mov_relogio.nil?
            instante = peer.mov_relogio
            fim = pontos.last[0]
            idade = (fim - instante) * 1000.0
            modo = if instante <= pontos.first[0] then :espera
                   elsif instante >= fim then ((atraso <= 0.0) ? :preve : :segura)
                   else :interpola
                   end
            dist = if r
                     ((r[1].to_f - pontos.last[1].to_f).abs +
                      (r[2].to_f - pontos.last[2].to_f).abs) / 4.0
                   end
            AnilMovLog.desenhou!((peer.internal_id rescue peer.object_id),
                                 idade, modo, pontos.length, dist)
          end
        rescue
          nil
        end
        r
      end
    end
  end
end

#-------------------------------------------------------------------------------
# (1b) e (4) — a posição própria a cada frame, e o relógio do desenho
#-------------------------------------------------------------------------------
class Scene_Map
  unless method_defined?(:anil_movlog_orig_update) ||
         private_method_defined?(:anil_movlog_orig_update)
    alias_method :anil_movlog_orig_update, :update
    def update
      anil_movlog_orig_update
      return unless AnilMovLog.ligado?
      if $game_player
        AnilMovLog.mexeu!(($game_player.real_x rescue 0), ($game_player.real_y rescue 0))
      end
      agora = Time.now.to_f
      dt = ($anil_movlog_frame ? (agora - $anil_movlog_frame) * 1000.0 : 0.0)
      $anil_movlog_frame = agora
      AnilMovLog.frame!(dt)
    end
  end
end

#-------------------------------------------------------------------------------
# O COMANDO
#-------------------------------------------------------------------------------
module AnilMovLogComando
  module_function

  def tratar(texto)
    t = texto.to_s.strip
    return false unless t =~ %r{\A/movlog(?:\s+(.*))?\z}i
    arg = $1.to_s.strip.downcase
    a_mais = (defined?(AnilRaidCaverna) && (AnilRaidCaverna.admin? rescue false))
    return false unless a_mais || (AnilArena.libertada? rescue false)

    case arg
    when "off", "desligar", "parar"
      if AnilMovLog.desligar!
        pbMessage(_INTL("Log de movimento desligado.\nFicheiro: {1}", AnilMovLog.caminho)) rescue nil
      else
        pbMessage(_INTL("Já estava desligado.")) rescue nil
      end
    when "ja", "já", "resumo"
      if AnilMovLog.ligado?
        AnilMovLog.resumo!("pedido à mão")
        AnilMovLog.despejar!
        pbMessage(_INTL("Orçamento escrito em {1}.", AnilMovLog.caminho)) rescue nil
      else
        pbMessage(_INTL("Não está a correr. Use /movlog para ligar.")) rescue nil
      end
    else
      AnilMovLog.ligar!
      pbMessage(_INTL("Log de movimento LIGADO.\nSepara as quatro esperas entre o outro mexer-se e você ver.\nFicheiro: {1}   ·   /movlog off para parar.",
                      AnilMovLog.caminho)) rescue nil
    end
    true
  rescue => e
    (AnilLanRework.log("[MOVLOG] falha: #{e.class}: #{e.message}") rescue nil)
    true
  end
end

module AnilLanRework
  module Chat
    class << self
      if !method_defined?(:anil_movlog_orig_send_message)
        alias_method :anil_movlog_orig_send_message, :send_message rescue nil
      end

      def send_message(text)
        return if AnilMovLogComando.tratar(text)
        anil_movlog_orig_send_message(text)
      end
    end
  end
end
