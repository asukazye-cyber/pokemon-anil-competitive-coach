# encoding: UTF-8
#===============================================================================
# MOD: 147_Ranqueado  —  lado do cliente
#-------------------------------------------------------------------------------
# Tres coisas:
#
#   1. o PVP deixa de mandar o perdedor para o Centro Pokemon
#   2. quem PERDE reporta ao servidor
#   3. os pontos aparecem no verso do cartao
#
# ⚠️ COMPATIBILIDADE COM CLIENTES ANTIGOS
#
# Quem nao atualizou continua a duelar normalmente. A partida apenas nao pontua
# — o servidor exige que os DOIS lados anunciem `ranked` no join.
#
# Isso nao e delicadeza: como e o PERDEDOR quem reporta, se o servidor aceitasse
# um lado so, ficar na versao velha significaria nunca perder pontos e ainda
# ganhar quando o adversario novo perdesse. Exigindo os dois, ficar para tras
# deixa de ser vantagem.
#===============================================================================

module AnilRanqueado
  class << self
    # Ultimo estado recebido do servidor. O cartao le daqui.
    attr_accessor :estado
  end
  @estado = nil

  module_function

  def pontos;  (@estado && @estado["points"].to_i)  || 0; end
  def rotulo;  (@estado && @estado["rank"].to_s)    || ""; end
  def tier;    (@estado && @estado["tier"].to_i)    || 0; end

  # ---------------------------------------------------------------------------
  # 1. O PERDEDOR NAO VAI PARA O CENTRO POKEMON
  #
  # Sem canLose, o motor chama pbStartOver na derrota (0261:682): teleporta para
  # o Centro e cobra a multa. Faz sentido contra a IA da historia; num duelo
  # entre jogadores, nao — a party nem sequer e a real (o PVP luta com copias
  # niveladas em 50, e o restore_local_pvp_party! devolve a original no fim),
  # portanto nao ha o que curar. Sobrava so o castigo.
  #
  # A raid ja fazia isto pelo mesmo motivo.
  # ---------------------------------------------------------------------------
  def marcar_pvp_sem_derrota!
    setBattleRule("canLose") rescue nil
  end

  # ---------------------------------------------------------------------------
  # 2. REPORTAR A DERROTA
  #
  # So o perdedor reporta. Perder tem custo real, entao ninguem forja uma
  # derrota; ja uma vitoria forjada seria o alvo obvio de um cliente adulterado.
  # O relato caro e o confiavel.
  # ---------------------------------------------------------------------------
  # ⚠️ O registo NAO usa o AnilLanRework.log.
  #
  # Aquele so escreve com $anil_debug_log_enabled ligado, e essa flag nao pode
  # ser ligada — ela trava o "recuperar partida". O resultado era um ponto cego
  # exactamente onde interessa: quem reporta e o PERDEDOR, portanto quando uma
  # partida nao pontua, a maquina que sabe porque e a que nao deixava rasto
  # nenhum. Escreve-se no ficheiro do MOD 144, que nao depende de flag.
  def registar(texto)
    if defined?(AnilEstatisticasMP)
      AnilEstatisticasMP.diag("[RANKED] #{texto}")
    end
  rescue
  end

  def reportar_derrota(battle_id, adversario_id, turnos)
    unless AnilLanRework.connected?
      registar("derrota NAO reportada: sem ligacao ao servidor")
      return
    end
    if adversario_id.to_s.empty?
      registar("derrota NAO reportada: adversario desconhecido (battle=#{battle_id})")
      return
    end
    AnilLanRework.connection.send_packet("ranked_loss", {
      "to_id"     => adversario_id.to_s,
      "battle_id" => battle_id.to_s,
      "turns"     => turnos.to_i
    })
    registar("derrota reportada battle=#{battle_id} vs #{adversario_id} turnos=#{turnos}")
  rescue => e
    registar("falha ao reportar: #{e.class}: #{e.message}")
  end

  # Chega pelo servidor depois de cada partida, e tambem a pedido.
  def receber_estado(packet)
    anterior = @estado
    @estado = packet
    registar("estado recebido: #{packet['rank']} #{packet['points']} pts delta=#{packet['delta'].inspect}")
    # A animacao de promocao compara o estado ANTERIOR desta sessao com o novo.
    # Nao se guarda nada no save de proposito — ver a nota no MOD 149.
    AnilRankSubiu.agendar(anterior, packet) if defined?(AnilRankSubiu) && anterior
    d = packet["delta"]
    return if d.nil?
    d = d.to_i
    return if d.zero?
    texto = d > 0 ? _INTL("+{1} pontos de rank!", d) : _INTL("{1} pontos de rank.", d)
    texto += " (#{packet['rank']})" unless packet["rank"].to_s.empty?
    anunciar(texto)
  rescue
  end

  # ---------------------------------------------------------------------------
  # O AVISO SO APARECE FORA DA BATALHA.
  #
  # ⚠️ Em teste, quem venceu por abandono nao viu ponto nenhum.
  #
  # O motivo: o resultado chega enquanto a batalha ainda esta na tela — o pedido
  # de vitoria sai do proprio encerramento —, e o popup do multiplayer e desenho
  # do mapa. Ele nao aparece por cima da batalha, e quando o mapa volta os 6
  # segundos dele ja passaram. O aviso existia e ninguem o via.
  #
  # Guarda-se e mostra-se no primeiro instante em que se esta mesmo no mapa.
  # ---------------------------------------------------------------------------
  def anunciar(texto)
    if em_batalha?
      @pendentes ||= []
      @pendentes << texto
      return
    end
    mostrar(texto)
  rescue
  end

  def em_batalha?
    return true if $game_temp && $game_temp.in_battle
    ctx = (AnilLanRework::BattleSync.active_context rescue nil)
    !ctx.nil?
  rescue
    false
  end

  def mostrar(texto)
    if AnilLanRework.respond_to?(:add_popup)
      AnilLanRework.add_popup(texto, 6.0) rescue nil
    else
      pbMessage(texto) rescue nil
    end
  rescue
  end

  def escoar_pendentes!
    return if @pendentes.nil? || @pendentes.empty?
    return if em_batalha?
    fila = @pendentes
    @pendentes = []
    fila.each { |t| mostrar(t) }
  rescue
    @pendentes = []
  end

  def pedir_estado
    return unless AnilLanRework.connected?
    AnilLanRework.connection.send_packet("ranked_request", {})
  rescue
  end
end

#-------------------------------------------------------------------------------
# 3. O VERSO DO CARTAO
#
# O plugin 046 desenha ali "Combates Online" e "Intercambios Online". Sobra a
# linha de baixo — a mesma que o proprio plugin deixou comentada a espera de um
# uso ("Customize $game_variables[100] to use whatever you'd like").
#-------------------------------------------------------------------------------
module AnilRanqueado
  module_function

  def instalar!
    return if @instalado
    return unless defined?(PokemonTrainerCard_Scene)
    @instalado = true

    PokemonTrainerCard_Scene.class_eval do
      unless method_defined?(:anil_rank_orig_pbDrawTrainerCardBack)
        if method_defined?(:pbDrawTrainerCardBack) || private_method_defined?(:pbDrawTrainerCardBack)
          alias_method :anil_rank_orig_pbDrawTrainerCardBack, :pbDrawTrainerCardBack

          def pbDrawTrainerCardBack
            anil_rank_orig_pbDrawTrainerCardBack
            return if AnilRanqueado.rotulo.empty?
            ov = @sprites && @sprites["overlay"] && @sprites["overlay"].bitmap
            return unless ov
            base   = Color.new(72, 72, 72)
            sombra = Color.new(160, 160, 160)
            # Mesma grelha das duas linhas que o plugin ja desenha: rotulo em
            # x=32, valor alinhado a direita na coluna dos numeros. A altura e a
            # linha seguinte a "Intercambios Online".
            y = 118 + 32 - 16 + 64
            pbDrawTextPositions(ov, [
              [_INTL("Rank"), 32, y, 0, base, sombra],
              [AnilRanqueado.rotulo, 44 + 111 * 2, y, 1, base, sombra],
              ["#{AnilRanqueado.pontos} pts", 302 + 2 + 48 + 63 * 2, y, 1, base, sombra]
            ])
          rescue => e
            AnilLanRework.log("[RANKED] falha ao desenhar o cartao: #{e.class}: #{e.message}") rescue nil
          end
        end
      end
    end
    # Escoa a fila assim que o mapa volta a andar. O Scene_Map#update corre a
    # cada frame e o teste e um Array vazio — custo desprezavel.
    if defined?(Scene_Map)
      Scene_Map.class_eval do
        unless method_defined?(:anil_rank_orig_update)
          alias_method :anil_rank_orig_update, :update

          def update(*args)
            anil_rank_orig_update(*args)
            AnilRanqueado.escoar_pendentes! if defined?(AnilRanqueado)
          end
        end
      end
    end

    AnilLanRework.log("147_Ranqueado instalado") rescue nil
  rescue => e
    AnilLanRework.log("[RANKED] falha ao instalar: #{e.class}: #{e.message}") rescue nil
  end
end

if defined?(AnilLanRework)
  module AnilLanRework
    class << self
      if !method_defined?(:anil_rank_orig_apply_post_plugin_patches)
        alias_method :anil_rank_orig_apply_post_plugin_patches, :apply_post_plugin_patches rescue nil
      end

      def apply_post_plugin_patches
        anil_rank_orig_apply_post_plugin_patches if respond_to?(:anil_rank_orig_apply_post_plugin_patches)
        AnilRanqueado.instalar!
      end
    end
  end
end

AnilLanRework.log("147_Ranqueado carregado") rescue nil
