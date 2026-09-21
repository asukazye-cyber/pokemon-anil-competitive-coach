# encoding: UTF-8
#===============================================================================
# MOD: 146_PVP_Queda_Adversario
#-------------------------------------------------------------------------------
# Quando o adversario some no meio do PVP, encerra a batalha com vitoria de quem
# ficou. E avisa, antes de comecar, para nao sair do jogo.
#
# O PROBLEMA
#
# No Android o jogador troca para o WhatsApp e o sistema SUSPENDE o processo do
# jogo. Nao e uma queda de rede comum: ele para de executar por completo — nao
# envia, nao recebe, e o proprio relogio dele congela. Quando volta, acha que
# nada aconteceu, enquanto o outro lado ja esperou 30 segundos e desistiu.
#
# ⚠️ E O QUE ACONTECIA ATE AGORA ERA PIOR DO QUE PARECE
#
# O estouro do tempo caia aqui (000d, verify_pvp_turn_hash!):
#
#     packet = wait_for_remote_turn_hash(turn)
#     return false unless packet     # <- e so isto
#
# A batalha NAO terminava. Ela continuava, com os dois lados a simular estados
# diferentes, em silencio, ate alguma coisa rebentar. Encerrar com um aviso e
# estritamente melhor do que o comportamento anterior.
#
# COMO SE DISTINGUE "CAIU" DE "REDE LENTA"
#
# Nao se encerra so por o tempo ter estourado — 30 segundos de lag acontecem. So
# se declara queda quando o adversario TAMBEM desapareceu da lista de jogadores
# que o servidor mantem. Ou seja, e o servidor que confirma a ausencia, nao um
# palpite do cliente.
#
# COMO SE DA A VITORIA
#
# NAO se usa pbAbort. Ele levanta BattleAbortedException, e quem a apanha faz
# `@decision = 0` (0152:273) — o desfecho seria "sem resultado", nao vitoria.
#
# Marca-se `battle.decision = 1` e deixa-se o laco terminar sozinho: o
# pbBattleLoop sai com `break if @decision > 0` e corre toda a sequencia normal
# de vitoria. Fica igual a uma vitoria comum para o resto do jogo, incluindo a
# contagem do MOD 144.
#===============================================================================

module AnilPvpQueda
  # Quantas vezes o parceiro tem de aparecer como ausente antes de se declarar
  # a queda. A lista de jogadores e atualizada por pacotes; um unico instante
  # sem ele pode ser so o intervalo entre duas atualizacoes.
  CONFIRMACOES = 2

  # Tem de bater com o PVP_QUEDA_GRACA do servidor. Se o cliente esperasse mais,
  # pediria a vitoria depois de o registo de queda ja ter expirado.
  CARENCIA = 30

  # De quanto em quanto tempo se tenta reconectar, do lado de quem caiu. Menos
  # do que isto so serve para empilhar tentativas de TCP em cima umas das outras.
  INTERVALO_RECONEXAO = 4.0

  module_function

  # ---------------------------------------------------------------------------
  # AVISOS DO SERVIDOR
  #
  # Tres pacotes, todos vindos do servidor (nunca do outro jogador):
  #
  #   battle_peer_lost  -> o socket dele fechou; comeca a contagem
  #   battle_peer_back  -> ele voltou e retomou; a batalha segue
  #   battle_resume_ok  -> EU voltei e o servidor aceitou a minha retomada
  # ---------------------------------------------------------------------------
  def on_packet(packet)
    case packet["type"].to_s
    when "battle_peer_lost"
      @peer_caiu     = true
      @peer_voltou   = false
      @peer_nome     = packet["peer_name"].to_s
      @peer_caiu_em  = Time.now.to_f
      registar("servidor avisou: #{packet['peer_id']} caiu")
    when "battle_peer_back"
      @peer_caiu   = false
      @peer_voltou = true
      registar("servidor avisou: #{packet['peer_id']} voltou")
    when "battle_resume_ok"
      @retomada_ok = true
      registar("minha retomada foi aceite (battle=#{packet['battle_id']})")
    when "battle_rejoin_ack"
      # O caminho que o jogo JA usava. O servidor manda este pacote aos DOIS
      # lados: a quem voltou com status "ok", e ao parceiro com o partner_id.
      # Qualquer um dos dois significa que o duelo esta de pe outra vez.
      if packet["status"].to_s == "ok" || !packet["partner_id"].to_s.empty?
        @retomada_ok = true
        @peer_caiu   = false
        registar("battle_rejoin_ack: duelo re-atado (battle=#{packet['battle_id']})")
      else
        registar("battle_rejoin_ack recusado: status=#{packet['status']}")
      end
    end
  rescue
  end

  def peer_caiu?;   @peer_caiu   == true; end
  def peer_voltou?; @peer_voltou == true; end

  # ⚠️ QUEM VOLTOU TAMBEM TEM DE SAIR DA ESPERA.
  #
  # Os dois lados recebem sinais DIFERENTES quando uma retomada da certo:
  #
  #   quem ficou  -> battle_peer_back   (o outro voltou)
  #   quem voltou -> battle_resume_ok   (a minha volta foi aceite)
  #
  # A primeira versao so olhava para o peer_voltou?, que e o sinal de quem
  # FICOU. Resultado em teste: a jogadora religou o wifi, reconectou, o servidor
  # aceitou a retomada — e o laco dela continuou a contar ate aos 30s, quando
  # encerrou por abandono. Como a ligacao dela ja estava boa nessa altura, o
  # teste de vida passou e ela foi declarada VENCEDORA da batalha que tinha
  # abandonado. O broadcast anunciou isso ao servidor inteiro.
  def retomei?; @retomada_ok == true; end

  # Qualquer um dos dois sinais significa "a batalha continua".
  def duelo_retomado?; peer_voltou? || retomei?; end

  # Quanto tempo sem receber NADA do servidor antes de considerar a minha
  # propria ligacao morta. O servidor manda um ping a cada 5s, portanto 20s de
  # silencio absoluto nao e lentidao.
  SILENCIO_MAXIMO = 20.0

  # ---------------------------------------------------------------------------
  # A MINHA LIGACAO ESTA VIVA?
  #
  # ⚠️ O `connected?` NAO serve para responder a isto.
  #
  # Ele olha para o objecto do socket, e desligar o wifi nao fecha socket
  # nenhum: o TCP so descobre a ausencia muito mais tarde. Quem desligou o wifi
  # continuava a ver `connected? == true` e, no fim da espera, era declarado
  # VENCEDOR por desistencia do outro — os dois lados a comemorar a mesma
  # batalha. O servidor recusava o pedido dela, mas o ecra ja tinha mentido.
  #
  # O que nao mente e a data do ultimo pacote RECEBIDO.
  # ---------------------------------------------------------------------------
  def ligacao_viva?
    return false unless AnilLanRework.connected?
    conn = AnilLanRework.connection
    return false unless conn
    ultimo = conn.instance_variable_get(:@last_packet_time).to_f
    return true if ultimo <= 0    # sem dado nenhum, nao se acusa
    (Time.now.to_f - ultimo) < SILENCIO_MAXIMO
  rescue
    false
  end

  # Log sem depender da flag global de debug — ver a nota no MOD 147.
  def registar(texto)
    AnilEstatisticasMP.diag("[PVP_QUEDA] #{texto}") if defined?(AnilEstatisticasMP)
  rescue
  end

  def peer_id_atual
    ctx = (AnilLanRework::BattleSync.active_context rescue nil)
    return nil unless ctx
    pid = (ctx.partner_id.to_s rescue "")
    pid.empty? ? nil : pid
  rescue
    nil
  end

  # O servidor ainda ve este jogador? nil = nao da para saber (nao se conclui
  # nada nesse caso — melhor deixar a batalha seguir do que encerrar por engano).
  def parceiro_online?(pid)
    return nil unless pid
    lista = (AnilLanRework.players rescue nil)
    return nil unless lista.is_a?(Hash)
    lista.key?(pid.to_s)
  rescue
    nil
  end

  def confirmar_queda(pid)
    @faltas ||= {}
    presente = parceiro_online?(pid)
    if presente.nil?
      @faltas[pid] = 0
      return false
    end
    if presente
      @faltas[pid] = 0
      return false
    end
    @faltas[pid] = @faltas[pid].to_i + 1
    @faltas[pid] >= CONFIRMACOES
  rescue
    false
  end

  def limpar!
    @faltas = {}
    @peer_caiu = false
    @peer_voltou = false
    @peer_nome = nil
    @retomada_ok = false
    @proxima_tentativa = nil
  end

  def nome_do_peer
    n = @peer_nome.to_s
    return n unless n.empty?
    pid = peer_id_atual
    p = pid ? (AnilLanRework.players[pid] rescue nil) : nil
    n = (p && p.name.to_s) || ""
    n.empty? ? _INTL("O adversario") : n
  rescue
    _INTL("O adversario")
  end

  # ---------------------------------------------------------------------------
  # A ESPERA VISIVEL
  #
  # Devolve :voltou (retomar a batalha) ou :desistir (encerrar por abandono).
  #
  # ⚠️ A rede TEM de continuar a andar aqui dentro.
  #
  # Um laco que so conte segundos deixa o cliente cego: os pacotes chegam a
  # thread de recepcao mas ninguem os encaminha, portanto nem o regresso do
  # adversario nem o aviso do servidor seriam vistos — e a tela ficaria
  # congelada de verdade em vez de mostrar o contador. Por isso usa-se o
  # pump_network do 000d, que ja e o mecanismo das outras esperas do jogo
  # (turno, convite, troca) e esta em producao ha muito tempo.
  # ---------------------------------------------------------------------------
  def esperar_retorno!(battle)
    inicio = Time.now.to_f
    nome = nome_do_peer
    viewport = window = nil
    sync = AnilLanRework::BattleSync
    begin
      viewport, window = sync.send(:build_wait_window, texto_da_espera(nome, CARENCIA))
      ultimo_desenhado = -1

      loop do
        restante = CARENCIA - (Time.now.to_f - inicio)
        break if restante <= 0

        # Bombeia a rede: sem isto nao se ve o adversario voltar.
        begin
          sync.send(:pump_network)
        rescue
        end

        if duelo_retomado?
          # Avisa NA HORA, dentro da batalha. O popup de canto do jogo so se ve
          # no mapa, portanto ali seria noticia velha.
          sync.send(:center_wait_window!, window, _INTL("{1} reconectou! Retomando...", nome))
          24.times { Graphics.update; Input.update }
          return :voltou
        end

        # Do lado de QUEM CAIU nao ha ligacao para bombear — tenta-se refazer.
        tentar_reconectar!

        seg = restante.ceil
        if seg != ultimo_desenhado
          ultimo_desenhado = seg
          sync.send(:center_wait_window!, window, texto_da_espera(nome, seg))
        end

        Graphics.update
        Input.update
      end
      :desistir
    ensure
      window.dispose rescue nil
      viewport.dispose rescue nil
    end
  rescue => e
    registar("falha na espera: #{e.class}: #{e.message}")
    :desistir
  end

  def texto_da_espera(nome, segundos)
    if ligacao_viva?
      _INTL("{1} perdeu a conexao. Aguardando {2}s...", nome, segundos.to_i)
    else
      # Quem caiu fui EU. Dizer "o adversario caiu" aqui seria mentira, e a
      # pessoa nao saberia que o problema esta do lado dela.
      _INTL("Conexao perdida. Reconectando... {1}s", segundos.to_i)
    end
  rescue
    _INTL("Aguardando... {1}s", segundos.to_i)
  end

  # ---------------------------------------------------------------------------
  # RECONEXAO DE QUEM CAIU
  #
  # ⚠️ NAO se usa o trigger_auto_connect_on_map.
  #
  # Aquele e o caminho da transicao de mapa e vem embrulhado em patches que
  # destravam o jogador e podem accionar a recuperacao de save — houve uma epoca
  # em que reconectar teleportava toda a gente para Pallet. No meio de um duelo
  # isso estragaria tudo em silencio. Aqui chama-se so o connect e, se ele
  # passar, anuncia-se a retomada.
  #
  # A batalha em si nao precisa de ser reconstruida: no Android o processo e
  # SUSPENSO, nao morto, e ela continua inteira na memoria. So o socket morreu.
  # ---------------------------------------------------------------------------
  # ---------------------------------------------------------------------------
  # RECONEXAO — usando a maquina que o jogo JA tem.
  #
  # ⚠️ NAO se abre ligacao nova aqui. A primeira versao chamava o connect
  # directamente e estava errada por duas razoes:
  #
  #   1. Ja existe um subsistema completo de reconexao — start_reconnection,
  #      uma thread em segundo plano, e o update_reconnection que instala a
  #      ligacao nova e ainda manda o `battle_rejoin` para re-atar o duelo.
  #      Ligar por fora dele deixava dois caminhos a disputar o mesmo objecto.
  #
  #   2. O connect do MOD 100 (o que vale para a VPS) termina em
  #      `wait_for_join_ack(99999.0)` — bloqueante, sem limite util. Chamar isso
  #      de dentro do laco da batalha e convite a congelar o jogo.
  #
  # O QUE FALTAVA ERA SO BOMBEAR.
  #
  # O update_connection_watchdog e chamado a partir do Scene_Map#update. Dentro
  # de uma batalha o Scene_Map nao corre, portanto a maquina de reconexao ficava
  # PARADA ate a batalha acabar — era por isso que a mensagem "Parceiro
  # reconectado a batalha!" so aparecia depois, ja no mapa. A ligacao ate
  # voltava; ninguem a instalava a tempo.
  # ---------------------------------------------------------------------------
  def tentar_reconectar!
    AnilLanRework.update_connection_watchdog($scene)
  rescue => e
    registar("falha ao bombear a reconexao: #{e.class}: #{e.message}")
  end

  # Encerra o duelo depois de a carencia esgotar.
  #
  # ⚠️ NEM SEMPRE E VITORIA.
  #
  # Se quem perdeu a ligacao fui EU, dizer "voce venceu" seria mentira e ainda
  # por cima contradiria o servidor, que vai registar uma derrota minha — o
  # cartao mostraria uma coisa e a tabela outra. Quem esta offline perdeu.
  def encerrar_por_queda!(battle)
    return false unless battle
    nome = nome_do_peer
    eu_cai = !ligacao_viva?

    if eu_cai
      begin
        battle.pbDisplayPaused(_INTL("Voce perdeu a conexao!"))
        battle.pbDisplayPaused(_INTL("A batalha foi encerrada."))
      rescue
      end
      battle.decision = 2   # derrota; o canLose do MOD 147 evita o Centro Pokemon
      registar("eu perdi a ligacao e nao consegui voltar — derrota")
      return true
    end

    begin
      battle.pbDisplayPaused(_INTL("{1} perdeu a conexao!", nome))
      battle.pbDisplayPaused(_INTL("Voce venceu por desistencia."))
    rescue
    end
    battle.decision = 1   # o pbBattleLoop sai com `break if @decision > 0`

    # Pede a vitoria por abandono. O servidor so aceita se ELE proprio tiver
    # visto o socket do adversario fechar — ver aplicar_vitoria_por_abandono.
    pedir_vitoria_por_abandono(battle)

    AnilLanRework.log("[PVP] adversario ausente confirmado — vitoria por desistencia") rescue nil
    true
  rescue => e
    AnilLanRework.log("[PVP] falha ao encerrar por queda: #{e.class}: #{e.message}") rescue nil
    false
  end

  # O pedido de vitoria por abandono.
  #
  # Vai com os turnos porque a pontuacao depende deles: uma queda no primeiro
  # turno nao premeia quem ficou (senao dois combinados encadeavam duelos de um
  # turno com quedas de proposito), embora puna sempre quem caiu.
  def pedir_vitoria_por_abandono(battle)
    return unless ligacao_viva?
    pid = peer_id_atual
    return if pid.to_s.empty?
    ctx = (AnilLanRework::BattleSync.active_context rescue nil)
    bid = (ctx && ctx.battle_id.to_s) || ""
    turnos = (battle.turnCount.to_i rescue 0)
    AnilLanRework.connection.send_packet("ranked_win_abandono", {
      "to_id"     => pid.to_s,
      "battle_id" => bid,
      "turns"     => turnos
    })
    registar("vitoria por abandono pedida (vs #{pid}, battle=#{bid}, turnos=#{turnos})")
  rescue => e
    registar("falha ao pedir vitoria por abandono: #{e.class}: #{e.message}")
  end

  # Aviso antes do duelo. Uma vez por sessao: repetir a cada batalha vira ruido
  # e o jogador deixa de ler.
  def avisar_uma_vez
    return if @avisou
    @avisou = true
    texto = _INTL("Nao saia do jogo durante a batalha!")
    if defined?(pbMessage)
      pbMessage(texto) rescue nil
    end
  rescue
  end

  def instalar!
    return if @instalado
    return unless defined?(AnilLanRework::BattleSync)
    @instalado = true

    # -------------------------------------------------------------------------
    # 1. O ponto onde a queda REALMENTE aparece: o fallback para IA.
    #
    # ⚠️ A primeira versao deste MOD envolvia o verify_pvp_turn_hash!, e nunca
    # disparou em jogo. A razao esta no pbDefaultChooseEnemyCommand do 000d:
    #
    #     AnilLanRework.log("battle_turn timeout fallback ...")
    #     @battle.instance_variable_set(:@anil_rework_pvp_turn_synced, true)
    #     their_indices.each { |enemy_index| super(enemy_index) }
    #
    # Quando a troca do turno nao completa, ele marca o turno como sincronizado
    # e deixa a IA jogar pelo adversario. O turno FECHA — portanto a verificacao
    # de hash a seguir passa, e o meu codigo nunca via falha nenhuma. Era esse o
    # "caiu na IA": a batalha continuava com o robo no lugar do jogador.
    #
    # Aqui a decisao e tomada ANTES de entregar o turno a IA.
    # -------------------------------------------------------------------------
    # ⚠️ A classe certa e a Battle::AI_LanCableRework, NAO a Battle::AI.
    #
    # O 000d define as duas: o pbDefaultChooseEnemyCommand do coop fica na
    # Battle::AI (6757) e o do PVP na Battle::AI_LanCableRework (6820), que
    # herda da primeira e SOBRESCREVE o metodo. Um alias na classe pai ficaria
    # sombreado pela filha e nunca correria num duelo.
    alvo_ia = if defined?(Battle::AI_LanCableRework)
                Battle::AI_LanCableRework
              elsif defined?(Battle::AI)
                Battle::AI
              end

    if alvo_ia
      alvo_ia.class_eval do
        unless method_defined?(:anil_queda_orig_pbDefaultChooseEnemyCommand)
          alias_method :anil_queda_orig_pbDefaultChooseEnemyCommand, :pbDefaultChooseEnemyCommand

          # =================================================================
          # ⚠️ NO PVP A IA NAO JOGA. NUNCA.
          #
          # A versao anterior deste gancho so agia SE detectasse a queda, e
          # caia no metodo original em qualquer outro caso — e e o original que
          # entrega o turno a IA:
          #
          #     AnilLanRework.log("battle_turn timeout fallback ...")
          #     @battle.instance_variable_set(:@anil_rework_pvp_turn_synced, true)
          #     their_indices.each { |enemy_index| super(enemy_index) }
          #
          # Ou seja, a IA assumir nao dependia de a deteccao falhar: era o
          # comportamento por omissao sempre que o turno nao fechava. Com o wifi
          # desligado o socket fica aberto, `connected?` responde true e o peer
          # continua na lista — nenhum sinal de queda aparece, e a IA entrava.
          #
          # Aqui o original NAO e chamado em PVP. O turno ou sincroniza, ou
          # espera, ou a batalha acaba. Nao ha quarta saida.
          # =================================================================
          def pbDefaultChooseEnemyCommand(*args, **kw, &blk)
            ctx = (AnilLanRework::BattleSync.active_context rescue nil)
            unless ctx && (ctx.mode rescue nil) == :pvp
              return anil_queda_orig_pbDefaultChooseEnemyCommand(*args, **kw, &blk)
            end
            return if @battle.instance_variable_get(:@anil_rework_pvp_turn_synced)

            sync  = AnilLanRework::BattleSync
            index = args[0]

            # 1. Caminho normal: trocar o turno com o outro lado.
            if sync.sync_pvp_turn_bundle(@battle, "enemy_hook_#{index}")
              @battle.instance_variable_set(:@anil_rework_pvp_turn_synced, true)
              return
            end

            # 2. Nao fechou. Isto E a queda — venha ela por socket fechado,
            #    por wifi desligado ou por o aparelho ter sido suspenso. Nao se
            #    espera pelo aviso do servidor para comecar a contar: o proprio
            #    silencio do turno ja e prova suficiente.
            AnilPvpQueda.registar("turno nao sincronizou — espera de #{AnilPvpQueda::CARENCIA}s")
            if AnilPvpQueda.esperar_retorno!(@battle) == :voltou
              # Voltou. A batalha esteve PARADA dos dois lados, entao nao ha
              # estado divergente — basta refazer a troca do turno.
              if sync.sync_pvp_turn_bundle(@battle, "retomada")
                @battle.instance_variable_set(:@anil_rework_pvp_turn_synced, true)
                AnilPvpQueda.limpar!
                return
              end
              AnilPvpQueda.registar("voltou mas o turno continuou sem fechar — encerrando")
            end

            # 3. Encerra. Vitoria de quem ficou, derrota de quem caiu.
            AnilPvpQueda.encerrar_por_queda!(@battle)
          end
        end
      end
      AnilLanRework.log("[PVP] queda: gancho instalado em #{alvo_ia}") rescue nil
    else
      AnilLanRework.log("[PVP] queda: nenhuma classe de IA encontrada") rescue nil
    end

    AnilLanRework::BattleSync.singleton_class.class_eval do
      # 2. Aviso ao abrir um duelo, e limpeza do contador.
      unless method_defined?(:anil_queda_orig_request_duel)
        alias_method :anil_queda_orig_request_duel, :request_duel

        def request_duel(*args, **kw)
          AnilPvpQueda.limpar!
          AnilPvpQueda.avisar_uma_vez
          anil_queda_orig_request_duel(*args, **kw)
        end
      end
    end
    AnilLanRework.log("146_PVP_Queda_Adversario instalado") rescue nil
  rescue => e
    AnilLanRework.log("[PVP] falha ao instalar queda de adversario: #{e.class}: #{e.message}") rescue nil
  end
end

if defined?(AnilLanRework)
  module AnilLanRework
    class << self
      if !method_defined?(:anil_queda_orig_apply_post_plugin_patches)
        alias_method :anil_queda_orig_apply_post_plugin_patches, :apply_post_plugin_patches rescue nil
      end

      def apply_post_plugin_patches
        anil_queda_orig_apply_post_plugin_patches if respond_to?(:anil_queda_orig_apply_post_plugin_patches)
        AnilPvpQueda.instalar!
      end
    end
  end
end

AnilLanRework.log("146_PVP_Queda_Adversario carregado") rescue nil
