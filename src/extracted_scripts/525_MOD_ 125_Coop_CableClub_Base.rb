#===============================================================================
# MOD: 125_Coop_CableClub_Base.rb   —   PASSO P0 de PLANO_COOP_CABLECLUB.md
#-------------------------------------------------------------------------------
# Base do coop reescrito no modelo do plugin Cable Club
# (Data/PluginScripts_Extraidos/031_Cable_Club/[001] Cable Club Client/).
#
# ESTADO: INERTE. Este arquivo apenas DEFINE as classes. Nada as instancia, nada
# chama nada daqui. O coop em uso continua sendo o antigo, sem qualquer alteracao
# de comportamento. Ligar so nos passos P1..P5.
#
#-------------------------------------------------------------------------------
# ISOLAMENTO DO PVP (requisito absoluto do projeto)
#
# Tudo aqui e ADITIVO. Nao ha um unico alias, nem redefinicao de metodo existente:
#   - Battle_CoopCC          -> classe NOVA (subclasse de Battle)
#   - Battle::AI_CoopCC      -> classe NOVA (subclasse de Battle::AI)
#   - CoopCC                 -> modulo NOVO
# O `class Battle` que aparece abaixo existe unicamente para aninhar a classe
# nova AI_CoopCC (o engine espera a AI dentro do namespace Battle). Ele NAO
# redefine nenhum metodo de Battle.
#
# Duas coisas do plugin foram deliberadamente NAO copiadas, porque no original
# vazavam para fora do Cable Club:
#
#  1. `class Battle; def pbChangeTargets` — o plugin REDEFINIA o metodo do engine
#     sem alias. Mesmo com a guarda `is_a?(Battle_CableClub)` no corpo, o metodo
#     do engine era substituido para TODAS as batalhas. Aqui ele virou um
#     override dentro da propria subclasse: fora dela, nada muda.
#
#  2. `class Battle::Move::ReplaceMoveWithTargetLastMoveUsed` (bloqueio do Sketch
#     online) — e uma classe de GOLPE, nao da para escopar numa subclasse de
#     batalha. Fica de fora do P0. Se for preciso depois, a guarda tem de ser
#     `@battle.is_a?(Battle_CoopCC)`, nunca `!@battle.internalBattle`, senao
#     alcanca PVP e single player.
#
#-------------------------------------------------------------------------------
# DIFERENCA D4 JA APLICADA: ordem de slots
#
# No Cable Club os dois jogadores sao ADVERSARIOS: cliente 0 tem os slots 0 e 2,
# cliente 1 tem 1 e 3. No COOP os dois estao no MESMO LADO: os aliados sao os
# slots 0 e 2 (cliente 0 dono do 0, cliente 1 dono do 2) e os inimigos sao 1 e 3
# PARA OS DOIS. Logo a traducao de indices e so a troca 0<->2; 1 e 3 nao mudam.
# As tabelas abaixo refletem isso e sao a unica parte reescrita, nao copiada.
#===============================================================================

module CoopCC
  # ---------------------------------------------------------------------------
  # LOG PROPRIO — sempre escreve, independente de $anil_debug_log_enabled.
  #
  # O projeto tem o 0000_Disable_Debug_Logs, e AnilLanRework.log comeca com
  # `return unless $anil_debug_log_enabled`. Sem isto o CoopCC ficava mudo
  # exatamente quando era preciso saber se ele assumiu a batalha ou nao.
  # Arquivo separado (coopcc_debug.txt) para nao reabrir a torneira de todo o
  # log de multiplayer.
  # ---------------------------------------------------------------------------
  # Nome POR JOGADOR: se os dois clientes rodarem da MESMA pasta (teste local),
  # um so arquivo recebe as linhas dos dois intercaladas e fica impossivel saber
  # o que foi de quem. Com o id no nome, cada um tem o seu.
  def self.arquivo_log
    id = (AnilLanRework.self_internal_id.to_s rescue "")
    id = "sem-id" if id.strip.empty?
    "coopcc_debug_#{id.gsub(/[^A-Za-z0-9_-]/, '_')}.txt"
  rescue
    "coopcc_debug.txt"
  end

  def self.log(msg)
    # Fica atras do MESMO interruptor dos outros diagnosticos. Antes gravava
    # sempre (ver a nota acima) e o coopcc_debug_*.txt reaparecia a cada sessao,
    # mesmo com todo o resto dos logs desligado.
    return unless ($anil_logs_diagnostico == true) || (anil_diagnostico_ligado? rescue false)
    linha = "[#{Time.now.strftime('%H:%M:%S')}] #{msg}"
    File.open(arquivo_log, "a") { |f| f.puts(linha) }
    # Espelha no log geral do projeto QUANDO ele estiver ligado. Nunca chamar
    # CoopCC.log aqui: seria recursao infinita (foi o SystemStackError).
    if defined?(AnilLanRework) && $anil_debug_log_enabled
      AnilLanRework.log("CoopCC #{msg}") rescue nil
    end
  rescue
  end

  # ===========================================================================
  # P3 — ORDEM CANONICA (correcao de rumo em relacao ao P0)
  #
  # No P0 estas tabelas faziam a troca 0<->2, herdada do espelhamento do Cable
  # Club. Isso vale para o modelo ANTIGO, em que cada cliente montava a batalha
  # com a SUA party primeiro — logo o slot 0 era "eu" nos dois lados e era
  # preciso traduzir.
  #
  # O P1 mudou a base: montar_lado_aliado monta @party1 = [cliente 0, cliente 1]
  # IGUAL nos dois clientes. Portanto o slot 0 e o MESMO Pokemon nos dois, o slot
  # 2 tambem, e NAO EXISTE espelhamento. Traduzir aqui passaria a introduzir o
  # desync em vez de evitar.
  #
  # E o ponto todo do modelo Cable Club: as duas simulacoes partem de dados
  # identicos e indices identicos. `client_id` deixa de mapear indices e passa a
  # significar apenas UMA coisa: de qual slot este cliente abre o menu.
  #
  # Isto importa diretamente para o pbCalculatePriority logo abaixo, que usa
  # `randomOrder[i]` indexado pelo indice CRU do battler como desempate de
  # velocidade. Com espelhamento, randomOrder[0] apontaria para Pokemon
  # diferentes em cada cliente e todo empate de Speed sairia invertido.
  # ===========================================================================

  # ===========================================================================
  # D1 RESOLVIDO — o espelhamento VOLTA (o P3 estava errado)
  #
  # A engine EXIGE que player_trainers[0] seja o $player real (e dele que sai
  # pokedex, exp, etc.). O P3 reordenava os treinadores para a ordem canonica
  # [cliente 0, cliente 1] e no cliente 1 punha o NPCTrainer do parceiro no
  # indice 0 -> NoMethodError: undefined method `pokedex' for #<NPCTrainer>.
  #
  # Com trainers[0] == $player em CADA cliente, a party tem de ser
  # [a minha, a do parceiro] em cada um. Logo:
  #
  #     slot 0 = SEMPRE o proprio jogador (nos dois clientes)
  #     slot 2 = SEMPRE o parceiro        (nos dois clientes)
  #     slots 1 e 3 = inimigos, IGUAIS nos dois (a foe_party vem do host)
  #
  # Ou seja os slots ALIADOS sao espelhados entre clientes e os inimigos nao.
  # E exatamente por isto que o Cable Club tem pokemon_order(client_id): la cada
  # jogador tambem e "o player" localmente. O P0 estava certo; o P3 nao.
  # ===========================================================================

  # Ordem canonica de iteracao: a MESMA sequencia logica nos dois clientes
  # (dono 0, dono 1, inimigos crescente), expressa nos indices locais de cada um.
  def self.pokemon_order(client_id)
    if client_id.to_i % 2 == 0
      [0, 2, 4, 1, 3, 5]   # cliente 0: eu=0, parceiro=2
    else
      [2, 0, 4, 1, 3, 5]   # cliente 1: eu=0 mas sou o "dono 1" -> parceiro=2 vem antes
    end
  end

  # Traducao de indice entre clientes: so os aliados trocam (0<->2).
  # Os inimigos (1, 3, 5) ocupam os MESMOS indices dos dois lados.
  def self.pokemon_target_order(_client_id = nil)
    [2, 1, 0, 3, 4, 5]
  end

  def self.traduzir_slot(idx)
    t = pokemon_target_order
    i = idx.to_i
    (i >= 0 && i < t.length) ? t[i] : i
  end

  # Com trainers[0] == $player, o meu slot e SEMPRE 0 e o do parceiro SEMPRE 2,
  # nos dois clientes. client_id deixa de escolher o slot e serve so para a
  # ordem canonica de iteracao acima.
  def self.meu_slot(_client_id = nil)
    0
  end

  def self.slot_parceiro(_client_id = nil)
    2
  end

  # ---------------------------------------------------------------------------
  # P4a — contexto e caixa de entrada
  #
  # Deliberadamente SEPARADO do AnilLanRework::BattleSync.active_context: o coop
  # novo nao deve depender do estado do coop antigo, senao volta o acoplamento
  # que estamos justamente desfazendo.
  # ---------------------------------------------------------------------------
  class << self
    attr_accessor :battle_id
    attr_accessor :partner_id
    attr_accessor :client_id
  end

  def self.limpar_contexto!
    @battle_id = nil
    @partner_id = nil
    @client_id = nil
    @inbox = {}
    @party_inbox = {}
    @party_do_parceiro = nil
    @seed = nil
    @troca_inbox = {}
    @foe_inbox = {}
  end

  def self.inbox
    @inbox ||= {}
  end

  def self.guardar_escolha(pacote)
    return unless pacote.is_a?(Hash)
    chave = "#{pacote['battle_id']}|#{pacote['turn'].to_i}"
    inbox[chave] = pacote
  end

  def self.pegar_escolha(battle_id, turno)
    chave = "#{battle_id}|#{turno.to_i}"
    achado = inbox.delete(chave)
    return achado if achado
    # Limpa restos de turnos passados: no modelo antigo era exatamente isto que
    # virava off-by-one permanente.
    velhos = inbox.keys.select do |k|
      partes = k.split("|")
      partes[0] == battle_id.to_s && partes[1].to_i < turno.to_i
    end
    unless velhos.empty?
      velhos.each { |k| inbox.delete(k) }
      CoopCC.log("descartou #{velhos.length} escolha(s) de turno anterior a #{turno}") if defined?(AnilLanRework)
    end
    nil
  end

  # ===========================================================================
  # P4b ponto 3 — DESLIGAR O COOP LEGADO
  #
  # Nao foi preciso guarda nenhuma. Auditado: os ~80 pontos do coop antigo
  # (mirror de pbReduceHP/pbRecoverHP, snapshot, proto 2/lote de turno,
  # pbCommandPhaseLoop, pbCalculatePriority, gancho da IA) TODOS exigem
  # `AnilLanRework::BattleSync.active_context` — nenhum roda sem ele.
  #
  # Logo, basta o coop novo NAO chamar `activate_context`: os 92 checam falsy e
  # o codigo legado e contornado por construcao. E o motivo de o CoopCC ter
  # contexto proprio (P4a) em vez de reaproveitar o do BattleSync.
  #
  # O metodo abaixo existe para proteger esse invariante: se algum dia os dois
  # contextos ficarem ativos ao mesmo tempo, as duas camadas rodam juntas e o
  # resultado e imprevisivel. Melhor gritar no log do que dessincronizar calado.
  def self.conflito_de_contexto?
    return false unless @battle_id
    legado = (AnilLanRework::BattleSync.active_context rescue nil)
    return false unless legado && legado.mode.to_s == "coop"

    # MESMA batalha = HANDOVER EM CURSO, nao conflito.
    #
    # O bootstrap le battle_id/partner/client_index/seed do contexto legado e so
    # o limpa DEPOIS do handshake (se limpasse antes, um handshake falhado
    # deixaria a batalha sem contexto nenhum). Entao, durante o handover, os dois
    # contextos existem de propósito — com o MESMO battle_id.
    #
    # Sem esta excecao a guarda abortava o proprio handover que devia proteger:
    # "handshake ABORTADO: contexto legado ativo" em toda batalha, e o coop novo
    # nunca chegava a assumir.
    #
    # Conflito a serio e battle_id DIFERENTE: ai sao mesmo duas batalhas.
    return false if legado.battle_id.to_s == @battle_id.to_s

    CoopCC.log("ALERTA: contexto legado de coop ATIVO junto com o novo "       "(battle_id novo=#{@battle_id} legado=#{legado.battle_id rescue '?'}). "       "As duas camadas vao rodar juntas — o coop novo NAO deve chamar activate_context."
    ) rescue nil
    true
  rescue
    false
  end

  # ===========================================================================
  # P4b pontos 2 e 4 — HANDSHAKE DE INICIO E CICLO DE VIDA DO CONTEXTO
  #
  # REQUISITO DURO (vem do ponto 3): este caminho NAO pode chamar
  # AnilLanRework::BattleSync.activate_context. Os 92 pontos do coop legado
  # dependem dele; se for preenchido, as duas camadas rodam juntas.
  # ===========================================================================

  ABRIR_TIMEOUT = 20.0 unless const_defined?(:ABRIR_TIMEOUT)

  # Abre o contexto SEM rede.
  #
  # O abrir_contexto! abaixo troca a party e espera o parceiro — e o que
  # dessincronizava a entrada, porque os dois clientes nao chegam la juntos.
  # Este e a versao usada pelo bootstrap: a decisao de usar lockstep ja veio no
  # battle_start_signal, e a party do parceiro ja foi injetada pelo caminho
  # legado. Nao ha nada a negociar nem a esperar.
  #
  # O abrir_contexto! fica no arquivo por enquanto — nao e mais chamado pelo
  # bootstrap, mas os testes de simulacao (t14) ainda o exercitam.
  def self.abrir_contexto_local!(battle_id:, partner_id:, client_id:, seed: nil)
    limpar_contexto!
    @battle_id  = battle_id.to_s
    @partner_id = partner_id.to_s
    @client_id  = client_id.to_i
    @seed       = seed.to_i if seed
    CoopCC.log("contexto aberto sem handshake: battle=#{@battle_id} client=#{@client_id} seed=#{@seed.inspect}") rescue nil
    true
  rescue => e
    CoopCC.log("abrir_contexto_local! falhou #{e.class}: #{e.message}") rescue nil
    limpar_contexto!
    false
  end

  # Chamado pelos DOIS lados. Devolve a party do parceiro, ja carregada, ou nil
  # se o handshake falhou (nesse caso a batalha nao deve comecar).
  def self.abrir_contexto!(battle_id:, partner_id:, client_id:, minha_party:, seed: nil)
    limpar_contexto!
    @battle_id  = battle_id.to_s
    @partner_id = partner_id.to_s
    @client_id  = client_id.to_i

    if conflito_de_contexto?
      CoopCC.log("handshake ABORTADO: contexto legado ativo") rescue nil
      limpar_contexto!
      return nil
    end

    blobs = dump_party(minha_party)
    AnilLanRework.connection.send_packet("coopcc_party",
      "to_id"       => @partner_id,
      "battle_id"   => @battle_id,
      "client_id"   => @client_id,
      "party"       => blobs,
      "fingerprint" => party_fingerprint(minha_party),
      "seed"        => seed
    )
    @seed = seed.to_i if seed
    CoopCC.log("handshake: enviou #{blobs.length} Pokemon (fp=#{party_fingerprint(minha_party)})") rescue nil

    pacote = esperar_party(@battle_id)
    unless pacote
      CoopCC.log("handshake TIMEOUT esperando a party do parceiro") rescue nil
      limpar_contexto!
      return nil
    end

    party_dele = load_party(pacote["party"])

    # Confere que o que chegou reproduz o que ele tinha. Se o Marshal perdeu algo
    # (versao de cliente diferente, por exemplo), e melhor abortar AQUI do que
    # jogar 20 turnos dessincronizado — foi exatamente esse tipo de perda
    # silenciosa (nivel, PP) que quebrou o coop antigo.
    fp_esperado = pacote["fingerprint"].to_i
    fp_recebido = party_fingerprint(party_dele)
    if fp_esperado != 0 && fp_esperado != fp_recebido
      CoopCC.log("handshake ABORTADO: fingerprint da party nao bate "         "(esperado=#{fp_esperado} recebido=#{fp_recebido}) — cliente do parceiro "         "provavelmente esta em outra versao."
      ) rescue nil
      limpar_contexto!
      return nil
    end

    @party_do_parceiro = party_dele
    @seed = pacote["seed"].to_i if pacote["seed"]
    CoopCC.log("handshake OK: #{party_dele.length} Pokemon do parceiro (fp=#{fp_recebido})") rescue nil
    party_dele
  rescue => e
    CoopCC.log("abrir_contexto! erro #{e.class}: #{e.message}") rescue nil
    limpar_contexto!
    nil
  end

  # Monta o lado aliado SEMPRE na ordem [cliente 0, cliente 1], nos dois lados.
  def self.aliados_em_ordem(minha_party, party_dele, client_id)
    (client_id.to_i % 2 == 0) ? [minha_party, party_dele] : [party_dele, minha_party]
  end

  def self.fechar_contexto!(motivo = nil)
    CoopCC.log("contexto fechado (#{motivo || 'fim'})") rescue nil
    restaurar_party_local!("fechar_contexto")
    limpar_contexto!
  end

  # ───────────────────────────────────────────────────────────────────────────
  # SIMETRIA DAS EQUIPES
  #
  # O inject_partner monta a party do PARCEIRO desserializando o blob dele, mas
  # cada cliente usa os objetos REAIS para a propria. Resultado: o cliente A ve
  # a equipe de A como objetos originais e a de B como copia da rede; em B e ao
  # contrario. Qualquer campo que o serializador nao carregue faz os dois
  # calcularem dano diferente — e a simulacao diverge.
  #
  # Foi exatamente isto que quebrou o PVP tres vezes seguidas. O conserto la
  # (ver 103_Multiplayer_Tournament) foi derivar as DUAS equipes do MESMO funil,
  # e e o mesmo que se faz aqui: a propria equipe passa a atravessar
  # serialize->deserialize, igual a do parceiro.
  #
  # De brinde, os Pokemon do save deixam de entrar na batalha: desserializar
  # cria objetos NOVOS. Nada do que acontecer na luta toca no save.
  # ───────────────────────────────────────────────────────────────────────────
  def self.party_trocada?
    !@party_backup.nil?
  end

  def self.trocar_party_local!
    return false if @party_backup
    return false unless defined?($player) && $player && $player.respond_to?(:party=)

    original = Array($player.party).compact
    return false if original.empty?

    copia = AnilLanRework::Serializer.deserialize_party(
      AnilLanRework::Serializer.serialize_party(original)
    )
    # Copia incompleta e pior do que nao copiar: entrar com meia equipe muda a
    # batalha. Nesse caso segue com os objetos reais (assimetrico, mas inteiro).
    if Array(copia).compact.length != original.length
      CoopCC.log("party local NAO trocada: copia veio com #{Array(copia).compact.length}/#{original.length}") rescue nil
      return false
    end

    @party_backup = $player.party
    $player.party = copia
    CoopCC.log("party local trocada por copia (#{copia.length} Pokemon) — o save nao e tocado") rescue nil
    true
  rescue => e
    CoopCC.log("trocar_party_local! falhou #{e.class}: #{e.message}") rescue nil
    @party_backup = nil
    false
  end

  def self.restaurar_party_local!(motivo = nil)
    return false unless @party_backup
    begin
      $player.party = @party_backup if defined?($player) && $player && $player.respond_to?(:party=)
      CoopCC.log("party local restaurada (#{motivo})") rescue nil
    rescue => e
      CoopCC.log("restaurar_party_local! falhou #{e.class}: #{e.message}") rescue nil
    ensure
      @party_backup = nil
    end
    # Os autosaves recusados durante a batalha (ver a trava no 103) deixaram o
    # resultado so na memoria; grava agora que a equipe real voltou.
    AnilLanRework.save_and_upload_save_file("coop_ended") rescue nil
    true
  end

  def self.guardar_party(pacote)
    return unless pacote.is_a?(Hash)
    @party_inbox ||= {}
    @party_inbox[pacote["battle_id"].to_s] = pacote
  end

  def self.esperar_party(battle_id)
    @party_inbox ||= {}
    inicio = Time.now.to_f
    loop do
      achado = @party_inbox.delete(battle_id.to_s)
      return achado if achado
      break unless (defined?(AnilLanRework) && AnilLanRework.connected?)
      break if Time.now.to_f - inicio >= ABRIR_TIMEOUT
      bombear_rede
      Graphics.update rescue nil
      Input.update rescue nil
    end
    nil
  end

  # Troca forcada (apos desmaio) e desistencia. Sao eventos FORA da fase de
  # comando, entao tem canal proprio — mas com a mesma chave (battle_id, turno)
  # e o mesmo descarte de turno antigo do rendezvous.
  def self.enviar_troca(turno, slot, escolha)
    return unless @battle_id
    AnilLanRework.connection.send_packet("coopcc_troca",
      "to_id" => @partner_id, "battle_id" => @battle_id,
      "turn" => turno.to_i, "slot" => slot.to_i, "escolha" => escolha.to_i)
    CoopCC.log("enviou troca turn=#{turno} slot=#{slot} -> #{escolha}") rescue nil
  rescue => e
    CoopCC.log("enviar_troca erro #{e.class}: #{e.message}") rescue nil
  end

  def self.guardar_troca(pacote)
    return unless pacote.is_a?(Hash)
    @troca_inbox ||= {}
    @troca_inbox["#{pacote['battle_id']}|#{pacote['turn'].to_i}|#{pacote['slot'].to_i}"] = pacote
  end

  # Mesma regra da espera de escolha: mostrar algo. `cena` e opcional para o
  # modulo nao depender da batalha, mas quando vem, a janela aparece.
  def self.esperar_troca(turno, slot, timeout = 20.0, cena = nil)
    @troca_inbox ||= {}
    chave = "#{@battle_id}|#{turno.to_i}|#{slot.to_i}"
    inicio = Time.now.to_f
    janela = nil
    quadro = 0
    if cena
      cena.pbShowWindow(Battle::Scene::MESSAGE_BOX) rescue nil
      janela = (cena.sprites["messageWindow"] rescue nil)
    end
    nome = nome_do_parceiro
    loop do
      achado = @troca_inbox.delete(chave)
      if achado
        if janela
          janela.text = "" rescue nil
          cena.pbHideWindow(Battle::Scene::MESSAGE_BOX) rescue nil
        end
        return achado["escolha"].to_i
      end
      break unless (defined?(AnilLanRework) && AnilLanRework.connected?)
      break if Time.now.to_f - inicio >= timeout
      if janela
        quadro += 1
        janela.text = _INTL("Aguardando {1} trocar{2}", nome, "." * (1 + ((quadro / 8) % 3)))
        cena.pbFrameUpdate(janela) rescue nil
      end
      bombear_rede
      Graphics.update rescue nil
      Input.update rescue nil
    end
    if janela
      janela.text = "" rescue nil
      cena.pbHideWindow(Battle::Scene::MESSAGE_BOX) rescue nil
    end
    CoopCC.log("TIMEOUT esperando troca turn=#{turno} slot=#{slot}") rescue nil
    nil
  end

  def self.enviar_desistencia
    return unless @battle_id
    AnilLanRework.connection.send_packet("coopcc_desistir",
      "to_id" => @partner_id, "battle_id" => @battle_id)
  rescue
  end

  # Nome do parceiro para as mensagens de espera.
  def self.nome_do_parceiro
    peer = (AnilLanRework.players[@partner_id.to_s] rescue nil)
    nome = (peer && peer.name.to_s) || ""
    nome.strip.empty? ? "parceiro" : nome
  rescue
    "parceiro"
  end

  # ---------------------------------------------------------------------------
  # Canal das acoes dos INIMIGOS (host -> guest). Mesma chave (battle_id, turn)
  # e mesmo descarte de turno antigo dos outros canais, mais o slot do foe.
  # ---------------------------------------------------------------------------
  def self.enviar_escolha_foe(turno, slot, escolha)
    return unless @battle_id
    AnilLanRework.connection.send_packet("coopcc_foe",
      "to_id" => @partner_id, "battle_id" => @battle_id,
      "turn" => turno.to_i, "slot" => slot.to_i, "escolha" => escolha)
    log("host enviou acao do foe turn=#{turno} slot=#{slot} kind=#{escolha['kind']}")
  rescue => e
    log("enviar_escolha_foe erro #{e.class}: #{e.message}")
  end

  def self.guardar_escolha_foe(pacote)
    return unless pacote.is_a?(Hash)
    @foe_inbox ||= {}
    @foe_inbox["#{pacote['battle_id']}|#{pacote['turn'].to_i}|#{pacote['slot'].to_i}"] = pacote
  end

  def self.esperar_escolha_foe(turno, slot, cena = nil, timeout = 20.0)
    @foe_inbox ||= {}
    chave = "#{@battle_id}|#{turno.to_i}|#{slot.to_i}"
    inicio = Time.now.to_f
    janela = nil
    quadro = 0
    if cena
      cena.pbShowWindow(Battle::Scene::MESSAGE_BOX) rescue nil
      janela = (cena.sprites["messageWindow"] rescue nil)
    end
    resultado = nil
    loop do
      achado = @foe_inbox.delete(chave)
      if achado
        resultado = achado["escolha"]
        break
      end
      break unless (defined?(AnilLanRework) && AnilLanRework.connected?)
      break if Time.now.to_f - inicio >= timeout
      if janela
        quadro += 1
        janela.text = _INTL("Sincronizando adversario{1}", "." * (1 + ((quadro / 8) % 3)))
        cena.pbFrameUpdate(janela) rescue nil
      end
      bombear_rede
      Graphics.update rescue nil
      Input.update rescue nil
    end
    if janela
      janela.text = "" rescue nil
      cena.pbHideWindow(Battle::Scene::MESSAGE_BOX) rescue nil
    end
    log("TIMEOUT esperando acao do foe turn=#{turno} slot=#{slot}") if resultado.nil?
    resultado
  end

  def self.bombear_rede
    return unless defined?(AnilLanRework) && AnilLanRework.connected?
    AnilLanRework.connection.tick
    AnilLanRework.connection.drain { |pkt| AnilLanRework::Router.route_packet(pkt) }
  rescue
  end

  # Ordem canonica dos alvos de um golpe de area. Como os indices ja significam
  # o mesmo nos dois clientes, isto so garante que a SEQUENCIA de dano tambem
  # seja a mesma, mesmo que o engine devolva a lista em ordem diferente.
  def self.sort_targets(targets, client_id = nil)
    order = pokemon_order(client_id || @client_id)
    targets.sort_by { |b| order.index(b.index) || 999 }
  end

  # ===========================================================================
  # P1 / D5 — TROCA DA PARTY COMPLETA
  #
  # POR QUE MARSHAL E NAO O Serializer DE CAMPOS
  #
  # O coop antigo mandava a party como blob campo-a-campo
  # (Serializer.serialize_pokemon). Todo campo esquecido vira divergencia
  # permanente, e ja custou caro: o nivel chegava errado (Butterfree 39 -> 37) e
  # o PP nunca foi conferido — com nivel errado o pbSpeed diverge e a ORDEM DO
  # TURNO inverte no turno 1, sem nenhuma mecanica exotica envolvida.
  #
  # No modelo Cable Club isso nao pode existir: as duas simulacoes tem de partir
  # de dados IDENTICOS. Marshal reproduz o objeto inteiro — IV, EV, natureza,
  # PP, item, habilidade, forma, status, tudo — sem lista de campos para
  # esquecer. E o mesmo mecanismo que o projeto ja usa para treinadores
  # (Serializer.dump_marshaled).
  #
  # Custo: o pacote fica maior. E uma vez por batalha, nao por turno.
  # ===========================================================================

  def self.dump_party(party)
    blobs = Array(party).compact.map { |pkmn| [Marshal.dump(pkmn)].pack("m0") }
    log("dump_party: " + blobs.length.to_s + " Pokemon, " + blobs.map(&:bytesize).sum.to_s + " bytes de payload")
    return blobs
  rescue => e
    CoopCC.log("dump_party erro #{e.class}: #{e.message}")
    []
  end

  def self.load_party(blobs)
    recebidos = Array(blobs)
    falhas = 0
    saida = recebidos.each_with_index.map do |b, i|
      begin
        Marshal.load(b.to_s.unpack1("m0"))
      rescue => e
        falhas += 1
        log("load_party FALHOU no indice " + i.to_s + ": " + e.class.to_s + ": " + e.message.to_s + " (" + b.to_s.bytesize.to_s + " bytes)")
        nil
      end
    end.compact
    log("load_party: " + recebidos.length.to_s + " blob(s) recebidos, " + saida.length.to_s + " carregados, " + falhas.to_s + " falha(s)")
    saida
  end

  # Monta o @party1 combinado. A ordem e SEMPRE [cliente 0, cliente 1] nos dois
  # clientes — nunca "a minha primeiro". Se cada lado montasse a partir do seu
  # ponto de vista, os dois teriam arrays diferentes e todo indice de party
  # (troca, EXP, Illusion, captura) apontaria para Pokemon distintos.
  # Devolve [party_combinada, starts] onde starts[i] = onde comeca a do dono i.
  def self.montar_lado_aliado(allies)
    combinada = []
    starts    = []
    Array(allies).each do |party|
      starts << combinada.length
      combinada.concat(Array(party).compact)
    end
    [combinada, starts]
  end

  # Confere que os dois clientes montaram a MESMA party. Barato e definitivo:
  # se isto divergir, nada adiante vale, e e melhor abortar do que jogar 20
  # turnos dessincronizado.
  def self.party_fingerprint(party)
    dados = Array(party).compact.map do |pk|
      [
        (pk.species.to_s        rescue ""),
        (pk.level.to_i          rescue 0),
        (pk.personalID.to_i     rescue 0),
        (pk.form.to_i           rescue 0),
        (pk.hp.to_i             rescue 0),
        (pk.totalhp.to_i        rescue 0),
        # item_id (SIMBOLO), nunca pk.item: este devolve um GameData::Item, e
        # GameData nao define to_s — Ruby cai no default #<GameData::Item:0x...>,
        # que inclui o ENDERECO DE MEMORIA. Depois do Marshal o endereco muda e
        # o fingerprint diferia para dados IDENTICOS, abortando todo handshake.
        ((pk.item_id || :NONE).to_s rescue ""),
        (Array(pk.moves).map { |m| m ? [m.id.to_s, m.pp.to_i] : nil }.inspect rescue "")
      ].join("|")
    end.join(";")
    # Rede de seguranca: se algum componente virou "#<Classe:0x...>", o valor
    # carrega o endereco de memoria e o fingerprint NAO e reproduzivel.
    if dados.include?("#<")
      log("AVISO: fingerprint contem inspect de objeto — valor instavel! " + dados[dados.index("#<"), 60].to_s)
    end
    h = 0x811C9DC5
    dados.each_byte { |b| h ^= b; h = (h * 0x01000193) & 0xFFFFFFFF }
    h
  end
end


class Battle_CoopCC < Battle
  attr_reader :connection
  attr_reader :battleRNG
  # Override pbSendOut to restore randomized mega abilities when switching in
  def pbSendOut(sendOuts, startBattle = false)
    super(sendOuts, startBattle)
    # Restore mega ability for randomized Pokémon that are already mega evolved
    if defined?(RandomizedChallenge) && RandomizedChallenge.enabled? && RandomizedChallenge.random_abilities?
      sendOuts.each do |b|
        battler = @battlers[b[0]]
        next if !battler || !battler.pokemon
        # If the Pokémon is mega evolved and has a stored mega_ability, restore it
        if battler.mega? && battler.pokemon.mega_ability
          battler.ability = battler.pokemon.mega_ability
        end
      end
    end
  end
  # ---------------------------------------------------------------------------
  # P1 / D1 — CONSTRUTOR NO FORMATO COOP
  #
  # O construtor do plugin era PVP: super(scene, minha_party, party_do_rival,
  # [eu], [rival]) — um jogador de cada lado. No coop os DOIS humanos estao no
  # lado 0 e o lado 1 e a IA (selvagem ou treinador).
  #
  # `allies` = [party_do_cliente_0, party_do_cliente_1] SEMPRE nessa ordem, igual
  # nos dois clientes. Quem monta e o CoopCC.montar_lado_aliado, para os dois
  # construirem exatamente o mesmo @party1 — e a diferenca entre "cada um ve a
  # sua" (o modelo antigo, que divergia) e "os dois veem a mesma coisa".
  #
  # client_id define so o PONTO DE VISTA (quem e o dono de qual slot), nunca o
  # conteudo. Conteudo igual + ponto de vista traduzido = lockstep.
  # ---------------------------------------------------------------------------
  def initialize(connection, client_id, scene, player_party, foe_party,
                 player_trainers, foe_trainers, seed)
    @connection = connection
    @client_id  = client_id.to_i
    # D1: NAO reordenamos nada. A engine ja montou player_party como
    # [a minha, a do parceiro] e player_trainers como [$player, parceiro] —
    # e essa ordem e obrigatoria (trainers[0] tem de ser o $player real).
    super(scene, player_party, foe_party, player_trainers, foe_trainers)
    @battleAI  = Battle::AI_CoopCC.new(self)
    @battleRNG = Random.new(seed)
  end

  # Onde comeca a party de cada dono dentro do @party1 combinado.
  attr_reader :coop_party_starts

  # P1 — os foes rodam a IA LOCALMENTE nos dois clientes (D3 do plano), entao a
  # rolagem da IA TEM de sair do mesmo RNG. No Cable Club isto nao existia porque
  # la a escolha do adversario vinha por pacote; aqui, se a IA sortear de fontes
  # diferentes, os dois clientes escolhem golpes diferentes para o mesmo inimigo.
  def pbAIRandom(x)
    @battleRNG.rand(x)
  end
  # TODA fonte de aleatoriedade da batalha tem de sair do @battleRNG.
  #
  # O 000d patcheia Battle#rand assim:
  #     def rand(x) ; anil_rework_rng ? anil_rework_rng.rand(x) : Kernel.rand(x) ; end
  # No modelo novo o contexto legado esta limpo, entao anil_rework_rng e nil e a
  # chamada caia em Kernel.rand — CADA CLIENTE SORTEAVA O SEU. Era o suficiente
  # para um golpe errar num lado e acertar no outro.
  #
  # Tambem zeramos anil_rework_rng de proposito: se algum patch antigo tentar
  # ler, encontra nil e nao ha duvida sobre qual gerador manda aqui.
  def rand(x = nil)
    x.nil? ? @battleRNG.rand : @battleRNG.rand(x)
  end

  def anil_rework_rng
    nil
  end

  def pbRandom(x)
    valor_rand = @battleRNG.rand(x)
    # p "#{x} #{valor_rand}"
    return valor_rand
  end
  def pbMegaEvolve(idxBattler)
    battler = @battlers[idxBattler]
    return if !battler || !battler.pokemon
    return if !battler.hasMega? || battler.mega?
    $stats.mega_evolution_count += 1 if battler.pbOwnedByPlayer?
    pbDeluxeTriggers(idxBattler, nil, "BeforeMegaEvolution", battler.species, *battler.pokemon.types)
    @scene.pbAnimateSubstitute(idxBattler, :hide)
    old_ability = battler.ability_id
    if battler.hasActiveAbility?(:ILLUSION)
      Battle::AbilityEffects.triggerOnBeingHit(battler.ability, nil, battler, nil, self)
    end
    if battler.wild?
      case battler.pokemon.megaMessage
      when 1
        pbDisplay(_INTL("¡{1} irradia energía!", battler.pbThis))
      else
        pbDisplay(_INTL("¡{2} de {2} irradia energía!", battler.pbThis, battler.itemName))
      end
    else
      trainerName = pbGetOwnerName(idxBattler)
      case battler.pokemon.megaMessage
      when 1
        pbDisplay(_INTL("¡El deseo ferviente de {1} ha alcanzado a {2}!", trainerName, battler.pbThis))
      else
        pbDisplay(_INTL("¡La {2} de {1} está reaccionando al {4} de {3}!",
                        battler.pbThis(true), battler.itemName, trainerName, pbGetMegaRingName(idxBattler)))
      end
    end
    pbAnimateMegaEvolution(battler)
    megaName = battler.pokemon.megaName
    megaName = _INTL("Mega {1}", battler.pokemon.speciesName) if nil_or_empty?(megaName)
    pbDisplay(_INTL("¡{1} ha megaevolucionado en {2}!", battler.pbThis, megaName))
    side  = battler.idxOwnSide
    owner = pbGetOwnerIndexFromBattlerIndex(idxBattler)
    @megaEvolution[side][owner] = -2
    if battler.isSpecies?(:GENGAR) && battler.mega?
      battler.effects[PBEffects::Telekinesis] = 0
    end
    battler.pbOnLosingAbility(old_ability)
    if (defined?(RandomizedChallenge) && RandomizedChallenge.enabled? && RandomizedChallenge.random_abilities?) && battler.pokemon.mega_ability
      battler.ability = battler.pokemon.mega_ability
    end
    battler.pbTriggerAbilityOnGainingIt
    pbCalculatePriority(false, [idxBattler]) if Settings::RECALCULATE_TURN_ORDER_AFTER_MEGA_EVOLUTION
    pbDeluxeTriggers(idxBattler, nil, "AfterMegaEvolution", battler.species, *battler.pokemon.types)
    @scene.pbAnimateSubstitute(idxBattler, :show)
  end
  # Added optional args to not make v18 break.
  # ===========================================================================
  # ADAPTADO PARA COOP — a versao do plugin foi REMOVIDA por inteiro.
  #
  # O original tinha 117 linhas e era quase todo o loop de recepcao do protocolo
  # BINARIO do Cable Club (@connection.update { |record| record.sym }), tratando
  # :forfeit, :switch e :battle_data com seed, mega, Z-move, dynamax, terastal,
  # focus meter e as escolhas do ADVERSARIO HUMANO.
  #
  # Nada disso se aplica ao coop: nao ha humano do outro lado do campo, a
  # connection deste projeto e JSON (send_packet) e nao tem esse writer/reader, e
  # as mecanicas do inimigo sao decididas pela IA local nos dois clientes.
  # Mantido, isto rebentava na primeira troca forcada.
  #
  # Regra coop, alinhada com o rendezvous do P2:
  #   meu slot       -> escolho e ENVIO
  #   slot parceiro  -> ESPERO a escolha dele
  #   inimigo        -> IA local (deterministica: mesmo estado + mesmo RNG)
  # ===========================================================================
  def pbSwitchInBetween(index, checkLaxOnly = false, canCancel = false)
    if index == coopcc_meu_slot
      escolha = super(index, checkLaxOnly, canCancel)
      if !canCancel && escolha && escolha >= 0
        CoopCC.enviar_troca(turnCount.to_i, index, escolha.to_i - coopcc_inicio_dono(0))
      end
      return escolha
    end

    if coopcc_slot_do_parceiro?(index)
      # O parceiro enviou com o slot DELE (0, porque ele tambem e trainers[0]).
      # Aqui esperamos por esse 0, mesmo estando a preencher o nosso slot 2.
      recebido = CoopCC.esperar_troca(turnCount.to_i, CoopCC.traduzir_slot(index), 20.0, @scene)
      if recebido
        idx_local = coopcc_inicio_dono(1) + recebido.to_i
        CoopCC.log("troca forcada do parceiro: relativo=#{recebido} -> local=#{idx_local}")
        return idx_local
      end
      # Sem resposta: escolhe sozinho para nao travar. Os dois lados aplicam a
      # mesma regra deterministica, entao mesmo o fallback tende a coincidir.
      CoopCC.log("troca do parceiro nao chegou (slot=#{index}) - fallback automatico")
      return (pbGetReplacementPokemonIndex(index, false) rescue super(index, checkLaxOnly, canCancel))
    end

    super(index, checkLaxOnly, canCancel)
  end
  def pbRun(idxBattler, duringBattle = false)
    ret = super(idxBattler, duringBattle)
    if ret == 1
      # ADAPTADO (mesma razao da troca): protocolo binario -> send_packet.
      CoopCC.enviar_desistencia
    end
    return ret
  end
  # ===========================================================================
  # P2 — RENDEZVOUS FIXO POR TURNO   (o passo que mata o travamento)
  #
  # ORIGINAL DO PLUGIN (substituido):
  #     last_index = pbGetOpposingIndicesInOrder(0).reverse.last
  #     return true if last_index == idxBattler
  # No Cable Club o outro humano e o ADVERSARIO, entao a troca de escolhas era
  # pendurada no gancho da IA inimiga, e forcar `true` num battler do lado
  # oposto garantia que esse gancho rodasse. No coop o outro humano e ALIADO e
  # os inimigos sao IA de verdade — a ancora tem de ser outra.
  #
  # O DEFEITO QUE ISTO CORRIGE:
  # o coop antigo derivava "envio ou espero?" do pbCanShowCommands? de CADA slot.
  # Golpe de duas fases (Meteor Beam, Solar Beam, Fly, Outrage, recarga) muda
  # esse valor na fase 2 — e quando muda so de um lado, um cliente pula o slot
  # (nao envia) e o outro espera um pacote que nunca vem. As duas telas mostram
  # "Aguardando ..." e a batalha congela ate o timeout; o pbAutoChooseMove do
  # fallback e o que fazia o parceiro "usar Luta".
  #
  # A REGRA NOVA e estrutural, nao derivada de estado:
  #   - eu NUNCA escolho pelo slot do parceiro  -> pbCanShowCommands? = false la
  #   - a troca acontece UMA vez por turno, FORA do laco por slot
  # Assim nenhum estado local (travado, desmaiado, encorado) pode fazer um lado
  # enviar e o outro nao. O pareamento passa a ser 1:1 por construcao.
  # ===========================================================================

  # Onde comeca a party de cada dono dentro da party1 COMBINADA.
  # pbParty(idxBattler) devolve a party1 inteira, logo os indices de troca sao
  # ABSOLUTOS nela — e a party1 e montada como [a minha, a do parceiro] em CADA
  # cliente. O mesmo Pokemon tem indices diferentes nos dois lados; sem traduzir,
  # a troca ia para o Pokemon errado (ou para nenhum, que foi o observado).
  def coopcc_inicio_dono(n)
    starts = (pbPartyStarts(0) rescue nil)
    return starts[n].to_i if starts && starts[n]
    n.to_i == 0 ? 0 : ($player.party.length rescue 6)
  end

  def coopcc_meu_slot
    CoopCC.meu_slot
  end

  def coopcc_slot_parceiro
    CoopCC.slot_parceiro
  end

  def coopcc_slot_do_parceiro?(idxBattler)
    idxBattler.to_i == coopcc_slot_parceiro
  end

  def pbCanShowCommands?(idxBattler)
    # O menu do parceiro nunca abre nesta maquina: a escolha dele chega pronta
    # pelo rendezvous. Sem isto, os dois clientes tentariam escolher pelo mesmo
    # battler.
    return false if coopcc_slot_do_parceiro?(idxBattler)
    super(idxBattler)
  end

  # Ponto unico de troca. Chamado SEMPRE, uma vez por turno, depois que o engine
  # terminou a fase de comando — nao importa o que aconteceu com qualquer slot.
  def pbCommandPhase(*args)
    @coopcc_turno_trocado = false
    resultado = super
    coopcc_sync_escolhas! unless @coopcc_turno_trocado
    resultado
  end

  def coopcc_sync_escolhas!
    return if @coopcc_turno_trocado
    @coopcc_turno_trocado = true

    # Eu sou sempre o slot 0 (trainers[0] == $player). O parceiro tambem se ve
    # como 0 — na MINHA visao ele e o 2. Por isso envio "0" e aplico no "2".
    minha = coopcc_serializar_escolha(coopcc_meu_slot)
    coopcc_enviar_escolha(turnCount.to_i, coopcc_meu_slot, minha)

    dele = coopcc_receber_escolha(turnCount.to_i)
    coopcc_aplicar_escolha(coopcc_slot_parceiro, dele) if dele
  end

  # --- transporte: ligado no P4. Por enquanto sao no-op, o que mantem a classe
  # --- inerte mesmo que alguem a instancie por engano.
  # ===========================================================================
  # P4a — TRANSPORTE DO RENDEZVOUS
  #
  # A chave e (battle_id, turn): no coop antigo o canal de acoes era um shift
  # cego, e bastava UMA assimetria para a fila desalinhar permanentemente — o
  # pacote do turno 3 era consumido pelo pedido do turno 4 e todas as esperas
  # seguintes estouravam. Aqui o pacote so e aceito para o turno que o pediu, e
  # pacote de turno ANTIGO e descartado com log em vez de contaminar.
  #
  # Como o P2 garante 1 envio / 1 espera por turno, este canal nunca deveria
  # desalinhar. A chave existe como rede de seguranca, nao como remendo.
  # ===========================================================================

  def coopcc_serializar_escolha(idxBattler)
    escolha = @choices[idxBattler]
    return { "kind" => "None" } if !escolha || escolha[0] == :None
    case escolha[0]
    when :UseMove
      { "kind" => "UseMove", "move" => escolha[1].to_i, "alvo" => escolha[3] }
    when :SwitchOut
      # Indice na party COMBINADA, que o P1 garante identica nos dois clientes.
      # RELATIVO ao inicio da MINHA party; o receptor soma o offset do parceiro.
      { "kind" => "SwitchOut", "party" => escolha[1].to_i - coopcc_inicio_dono(0) }
    when :UseItem
      { "kind" => "UseItem", "item" => escolha[1].to_s, "alvo" => escolha[2], "move" => escolha[3] }
    when :Run
      { "kind" => "Run" }
    when :Shift
      { "kind" => "Shift" }
    else
      { "kind" => "None" }
    end
  rescue => e
    CoopCC.log("serializar escolha erro #{e.class}: #{e.message}") if defined?(AnilLanRework)
    { "kind" => "None" }
  end

  def coopcc_enviar_escolha(turno, slot, escolha)
    return unless @connection && defined?(AnilLanRework)
    @connection.send_packet("coopcc_escolha",
      "to_id"     => CoopCC.partner_id,
      "battle_id" => CoopCC.battle_id,
      "turn"      => turno.to_i,
      "slot"      => slot.to_i,
      "escolha"   => escolha
    )
    CoopCC.log("enviou escolha turn=#{turno} slot=#{slot} kind=#{escolha['kind']}")
  rescue => e
    CoopCC.log("enviar escolha erro #{e.class}: #{e.message}") if defined?(AnilLanRework)
  end

  # A espera pelo parceiro TEM de mostrar algo. Sem isto o jogo fica parado
  # enquanto o outro decide (12s no teste real) e parece travado — foi o
  # "travou mesmo" reportado. A barreira em si esta correta; faltava o aviso.
  def coopcc_receber_escolha(turno)
    inicio = Time.now.to_f
    limite = (defined?(AnilLanRework::TURN_TIMEOUT) ? AnilLanRework::TURN_TIMEOUT : 30.0)
    janela = nil
    quadro = 0
    begin
      @scene.pbShowWindow(Battle::Scene::MESSAGE_BOX) rescue nil
      janela = (@scene.sprites["messageWindow"] rescue nil)
      nome = (CoopCC.nome_do_parceiro rescue "parceiro")
      loop do
        pacote = CoopCC.pegar_escolha(CoopCC.battle_id, turno)
        return pacote["escolha"] if pacote
        break unless (defined?(AnilLanRework) && AnilLanRework.connected?)
        break if Time.now.to_f - inicio >= limite
        if janela
          quadro += 1
          janela.text = _INTL("Aguardando {1}{2}", nome, "." * (1 + ((quadro / 8) % 3)))
          @scene.pbFrameUpdate(janela) rescue nil
        end
        CoopCC.bombear_rede
        Graphics.update rescue nil
        Input.update rescue nil
      end
      CoopCC.log("TIMEOUT esperando escolha turn=#{turno}")
      nil
    ensure
      if janela
        janela.text = "" rescue nil
        @scene.pbHideWindow(Battle::Scene::MESSAGE_BOX) rescue nil
      end
    end
  end

  def coopcc_aplicar_escolha(slot, escolha)
    return unless escolha.is_a?(Hash)
    case escolha["kind"].to_s
    when "UseMove"
      pbRegisterMove(slot, escolha["move"].to_i, false)
      alvo = escolha["alvo"]
      # D1: os slots ALIADOS sao espelhados entre clientes (0<->2). O parceiro
      # mandou o alvo na perspectiva DELE; aqui traduzimos para a nossa. Os
      # inimigos (1, 3) nao mudam. Sem isto, "ataca o meu parceiro" virava
      # "ataca a mim mesmo" do outro lado.
      unless alvo.nil?
        alvo_local = CoopCC.traduzir_slot(alvo.to_i)
        pbRegisterTarget(slot, alvo_local) if alvo_local >= 0
      end
    when "SwitchOut"
      # So o lado ALIADO precisa de traducao: a party2 (inimigos) vem do host e
      # e identica nos dois clientes, entao o indice dela ja e absoluto e igual.
      idx_local = (opposes?(slot) rescue false) ?
                    escolha["party"].to_i :
                    coopcc_inicio_dono(1) + escolha["party"].to_i
      CoopCC.log("troca aplicada slot=#{slot} relativo=#{escolha['party']} -> local=#{idx_local}")
      pbRegisterSwitch(slot, idx_local)
    when "UseItem"
      @choices[slot][0] = :UseItem
      @choices[slot][1] = escolha["item"].to_s.to_sym
      @choices[slot][2] = escolha["alvo"]
      @choices[slot][3] = escolha["move"]
    when "Run"
      @choices[slot][0] = :Run
    when "Shift"
      @choices[slot][0] = :Shift
    end
    CoopCC.log("aplicou escolha do parceiro slot=#{slot} kind=#{escolha['kind']}") if defined?(AnilLanRework)
  rescue => e
    CoopCC.log("aplicar escolha erro slot=#{slot} #{e.class}: #{e.message}") if defined?(AnilLanRework)
  end
  # avoid unnecessary checks and check in same order
  def pbEORSwitch(favorDraws=false)
    return if @decision>0 && !favorDraws
    return if @decision==5 && favorDraws
    pbJudge
    return if @decision>0
    # Check through each fainted battler to see if that spot can be filled.
    switched = []
    loop do
      switched.clear
      # check in same order
      battlers = []
      order = CoopCC.pokemon_order(@client_id)
      order.each_with_index do |o,i|
        battlers[i] = @battlers[o]
      end
      battlers.each do |b|
        next if !b || !b.fainted?
        idxBattler = b.index
        next if !pbCanChooseNonActive?(idxBattler)
        if !pbOwnedByPlayer?(idxBattler)   # Opponent/ally is switching in
          idxPartyNew = pbSwitchInBetween(idxBattler)
          opponent = pbGetOwnerFromBattlerIndex(idxBattler)
          pbRecallAndReplace(idxBattler,idxPartyNew)
          switched.push(idxBattler)
        else
          idxPlayerPartyNew = pbGetReplacementPokemonIndex(idxBattler)   # Owner chooses
          pbRecallAndReplace(idxBattler,idxPlayerPartyNew)
          switched.push(idxBattler)
        end
      end
      break if switched.length==0
      pbOnBattlerEnteringBattle(switched)
    end
  end
def pbCalculatePriority(fullCalc = false, indexArray = nil)
    needRearranging = false
    if fullCalc
      @priorityTrickRoom = (@field.effects[PBEffects::TrickRoom] > 0)
      # En lugar de usar RNG local, usar el RNG sincronizado para el orden aleatorio
      randomOrder = Array.new(maxBattlerIndex + 1) { |i| i }
      (randomOrder.length - 1).times do |i|
        # Usar el RNG sincronizado de la batalla online
        r = i + pbRandom(randomOrder.length - i)
        randomOrder[i], randomOrder[r] = randomOrder[r], randomOrder[i]
      end
      @priority.clear
      (0..maxBattlerIndex).each do |i|
        b = @battlers[i]
        next if !b
        # Estructura: [battler, speed, sub-priority from ability, sub-priority from item,
        #             final sub-priority, priority, tie-breaker order]
        # D1: randomOrder e indexado pelo indice CRU do battler, mas os slots
        # aliados sao ESPELHADOS entre clientes — randomOrder[0] apontaria para
        # Pokemon diferentes em cada lado e todo empate de Speed sairia
        # invertido. Indexamos pelo indice CANONICO (visao do cliente 0).
        idx_desempate = (@client_id.to_i % 2 == 0) ? i : CoopCC.traduzir_slot(i)
        entry = [b, b.pbSpeed, 0, 0, 0, 0, randomOrder[idx_desempate]]
        if @choices[b.index][0] == :UseMove || @choices[b.index][0] == :Shift
          # Calcular prioridad del movimiento
          if @choices[b.index][0] == :UseMove
            move = @choices[b.index][2]
            pri = move.pbPriority(b)
            # Efectos de habilidad en prioridad
            if b.abilityActive?
              pri = Battle::AbilityEffects.triggerPriorityChange(b.ability, b, move, pri)
            end
            # Efectos de objeto en prioridad
            if b.itemActive?
              pri = Battle::ItemEffects.triggerPriorityChange(b.item, b, move, pri)
            end
            entry[5] = pri
            @choices[b.index][4] = pri
          end
          # Calcular cambios de sub-prioridad
          # Habilidades (como Stall)
          if b.abilityActive?
            entry[2] = Battle::AbilityEffects.triggerPriorityBracketChange(b.ability, b, self)
          end
          # Objetos (Quick Claw, Custap Berry, Lagging Tail, Full Incense)
          if b.itemActive?
            entry[3] = Battle::ItemEffects.triggerPriorityBracketChange(b.item, b, self)
          end
        end
        @priority.push(entry)
      end
      needRearranging = true
    else
      # Recálculo parcial
      if (@field.effects[PBEffects::TrickRoom] > 0) != @priorityTrickRoom
        needRearranging = true
        @priorityTrickRoom = (@field.effects[PBEffects::TrickRoom] > 0)
      end
      # Revisar velocidades y cambios de prioridad
      @priority.each do |entry|
        next if !entry
        next if indexArray && !indexArray.include?(entry[0].index)
        # Recalcular velocidad
        newSpeed = entry[0].pbSpeed
        needRearranging = true if newSpeed != entry[1]
        entry[1] = newSpeed
        # Recalcular prioridad del movimiento
        choice = @choices[entry[0].index]
        if choice[0] == :UseMove
          move = choice[2]
          pri = move.pbPriority(entry[0])
          if entry[0].abilityActive?
            pri = Battle::AbilityEffects.triggerPriorityChange(entry[0].ability, entry[0], move, pri)
          end
          if entry[0].itemActive?
            pri = Battle::ItemEffects.triggerPriorityChange(entry[0].item, entry[0], move, pri)
          end
          needRearranging = true if pri != entry[5]
          entry[5] = pri
          choice[4] = pri
        end
      end
    end
    # Calcular sub-prioridad final
    @priority.each do |entry|
      entry[0].effects[PBEffects::PriorityAbility] = false
      entry[0].effects[PBEffects::PriorityItem] = false
      subpri = entry[2]   # Sub-prioridad de habilidad
      if (subpri == 0 && entry[3] != 0) ||
         (subpri < 0 && entry[3] >= 1)
        subpri = entry[3]   # Sub-prioridad de objeto
        entry[0].effects[PBEffects::PriorityItem] = true
      elsif subpri != 0
        entry[0].effects[PBEffects::PriorityAbility] = true
      end
      entry[4] = subpri   # Sub-prioridad final
    end
    # Reordenar el array de prioridad
    if needRearranging
      @priority.sort! do |a, b|
        if a[5] != b[5]
          # Ordenar por prioridad (valor más alto primero)
          b[5] <=> a[5]
        elsif a[4] != b[4]
          # Ordenar por sub-prioridad (valor más alto primero)
          b[4] <=> a[4]
        elsif @priorityTrickRoom
          # Ordenar por velocidad (más bajo primero), usar desempate si es necesario
          (a[1] == b[1]) ? b[6] <=> a[6] : a[1] <=> b[1]
        else
          # Ordenar por velocidad (más alto primero), usar desempate si es necesario
          (a[1] == b[1]) ? b[6] <=> a[6] : b[1] <=> a[1]
        end
      end
      # Log de debug mejorado para online
      if fullCalc && $DEBUG
        logMsg = "[Cable Club - Round order] Client #{@client_id}: "
        @priority.each_with_index do |entry, i|
          logMsg += ", " if i > 0
          battler = entry[0]
          move_name = "No move"
          if @choices[battler.index][0] == :UseMove && @choices[battler.index][2]
            move_name = @choices[battler.index][2].name
          end
          logMsg += "#{battler.pbThis(i > 0)} (#{battler.index}) - #{move_name} [Pri: #{entry[5]}, Spd: #{entry[1]}, Tie: #{entry[6]}]"
        end
        PBDebug.log(logMsg)
      end
    end
    # Verificación adicional para debug en modo desarrollador
    if $DEBUG
      puts "=== PRIORITY CALCULATION DEBUG ==="
      puts "Client ID: #{@client_id}"
      puts "Full Calc: #{fullCalc}"
      puts "Trick Room: #{@priorityTrickRoom}"
      @priority.each_with_index do |entry, i|
        battler = entry[0]
        move_name = "No action"
        if @choices[battler.index][0] == :UseMove && @choices[battler.index][2]
          move_name = @choices[battler.index][2].name
        elsif @choices[battler.index][0] == :UseItem
          move_name = "Use Item"
        elsif @choices[battler.index][0] == :SwitchOut
          move_name = "Switch"
        end
        puts "#{i + 1}. #{battler.pbThis} (Index: #{battler.index})"
        puts "   Action: #{move_name}"
        puts "   Priority: #{entry[5]} | Speed: #{entry[1]} | Sub-Pri: #{entry[4]} | Tie-breaker: #{entry[6]}"
      end
      puts "=================================="
    end
  end
  # Movido para DENTRO da subclasse. No plugin isto reabria `class Battle` e
  # REDEFINIA pbChangeTargets sem alias -- passaria por cima do metodo do engine
  # para TODAS as batalhas, inclusive PVP e single player.
  def pbChangeTargets(move, user)
    targets = move.pbTarget(user)
    targets = CoopCC.sort_targets(targets, @client_id) if targets.length > 1
    return targets
  end
end
class Battle
  class AI_CoopCC < AI
# ===================================================================
# D2/D3 ? ADAPTADO PARA COOP (o original do plugin foi REMOVIDO)
#
# No Cable Club este metodo era o coracao da troca: o "inimigo" e o
# OUTRO HUMANO, entao aqui ele serializava as escolhas e mandava pela
# connection (writer.sym(:battle_data), seed, mecanicas...).
#
# No COOP isso esta errado por completo: os inimigos sao IA de verdade
# (selvagem ou treinador), nao ha humano do outro lado para trocar nada.
# Manter a versao do plugin fazia o cliente falar protocolo Cable Club
# com ninguem E, pior, NAO escolher os golpes dos inimigos pela IA
# normal ? o que muda o consumo de RNG e dessincroniza tudo a jusante
# (foi o que produziu paralisia/veneno acontecendo so num dos lados).
#
# A escolha dos foes NAO precisa de pacote nenhum: os dois clientes
# rodam a MESMA IA sobre o MESMO estado com o MESMO RNG
# (Battle_CoopCC#pbAIRandom sai do @battleRNG compartilhado), logo
# chegam a mesma decisao sozinhos. E a troca das escolhas dos dois
# JOGADORES ja acontece no rendezvous do P2, noutro lugar.
# ===================================================================
def pbDefaultChooseEnemyCommand(index)
        # =================================================================
        # D3 CORRIGIDO — as escolhas dos INIMIGOS vem do host.
        #
        # A versao anterior era so `super`, apoiada na premissa do plano de que
        # "mesmo estado + mesmo RNG => mesma decisao". Essa premissa MORREU
        # quando o D1 repos o espelhamento: a IA, no cliente A, ve "aliado do
        # slot 0 = Venusaur"; no cliente B ve "aliado do slot 0 = Charizard".
        # A decisao logica e a mesma ("ataca o aliado do slot 0") e o golpe cai
        # em Pokemon DIFERENTES — foi a paralisia a aparecer no mon errado.
        #
        # Os slots dos foes (1, 3) sao iguais nos dois (a foe_party vem do host),
        # entao `index` nao precisa de traducao; o ALVO precisa, e a traducao
        # acontece no coopcc_aplicar_escolha.
        # =================================================================
        return super unless CoopCC.ativo?

        if CoopCC.client_id.to_i == 0
          super
          escolha = @battle.coopcc_serializar_escolha(index)
          CoopCC.enviar_escolha_foe(@battle.turnCount.to_i, index, escolha)
        else
          escolha = CoopCC.esperar_escolha_foe(@battle.turnCount.to_i, index, (@battle.scene rescue nil))
          if escolha
            @battle.coopcc_aplicar_escolha(index, escolha)
          else
            CoopCC.log("SEM escolha do host para o foe #{index} — decidindo local (risco de desync)")
            super
          end
        end
      end
    def pbDefaultChooseNewEnemy(index, party)
      raise "Expected this to be unused."
    end
  end
end

CoopCC.log("=== 125_Coop_CableClub_Base carregado | flag=#{$anil_coop_cablecub.inspect} ===")

#===============================================================================
# P4b ponto 1 — INSTANCIACAO
#
# A engine chama `Battle.new` DIRETO em dois lugares (Overworld_BattleStarting:
# WildBattle.start_core ~445 e TrainerBattle.start_core ~565) e nao expoe factory.
# Por isso o unico caminho e alias + replicar o trecho, trocando so a linha da
# construcao. E o mesmo padrao que o coop antigo ja usa neste projeto
# (anil_rework_original_start / anil_rework_original_start_core).
#
# ATENCAO A QUEM MANTIVER: o corpo abaixo e copia de Overworld_BattleStarting.rb.
# Se a engine mudar esses metodos, este trecho precisa acompanhar.
#
# GATE: so entra aqui com $anil_coop_cablecub == true E contexto CoopCC aberto.
# Com a flag desligada (padrao), nada disto roda e o coop antigo segue intacto.
#===============================================================================

# LIGADO de novo em 2026-08-08, depois de a entrada ser reescrita (ver abaixo).
#
# ─── historico, para nao se repetir o erro ───
# 1a tentativa (07/08): SINTOMA "inicia na tela de um e o outro entra sozinho".
#
# CAUSA: nao e o timeout — e o FALLBACK ser individual. O handshake do
# bootstrap_do_legado! roda dentro do start_core, e os dois clientes nao chegam
# la ao mesmo tempo (o convidado tem passos a mais). Quem chega primeiro espera
# ABRIR_TIMEOUT, estoura, devolve false e segue pelo coop ANTIGO; quem chega
# depois encontra a party ja em buffer, tem sucesso, e entra no Battle_CoopCC.
# Resultado: os dois ficam em MOTORES diferentes, cada um na sua batalha.
#
# Ou seja: uma rede de seguranca que protege um lado so nao e rede, e um divisor.
# Ou os DOIS caem para o legado, ou os DOIS entram no lockstep.
#
# CONSERTO (08/08): a entrada deixou de ser negociada. O HOST decide o modo no
# request_coop_battle — onde ja conhece o battle_proto do convidado — e manda a
# decisao dentro do battle_start_signal. O convidado le e obedece. Como esse
# sinal precede a criacao da batalha nos DOIS lados, ambos sabem qual classe
# instanciar antes de comecar: ou os dois no lockstep, ou os dois no legado.
# Nao ha handshake para falhar nem timeout para estourar.
#
# Para REVERTER: `false` + compilar. O gate cobre a instanciacao inteira.
$anil_coop_cablecub = true unless defined?($anil_coop_cablecub)

module CoopCC
  def self.ligado?
    $anil_coop_cablecub == true
  end

  # Ha uma batalha coop nova em curso? Exige contexto aberto pelo handshake.
  def self.ativo?
    ligado? && !@battle_id.nil?
  end

  # ---------------------------------------------------------------------------
  # BOOTSTRAP — a peca que faltava para o interruptor funcionar de verdade.
  #
  # O fluxo coop antigo (start_coop_battle / request_coop_battle) ja monta tudo o
  # que a batalha precisa: regras, injecao do parceiro, switch de boss, e chama
  # activate_context com battle_id / partner_id / client_index / seed. So depois
  # e que chama WildBattle|TrainerBattle.start_core.
  #
  # Em vez de duplicar essa montagem toda, aproveitamos: no momento do
  # start_core, lemos esses 4 valores do contexto legado, abrimos o contexto
  # PROPRIO com o handshake, e LIMPAMOS o legado — para que os 92 pontos do coop
  # antigo nao disparem (ver P4b ponto 3).
  #
  # Se o handshake falhar, nao limpamos nada e devolvemos false: a batalha segue
  # pelo caminho antigo, exatamente como hoje.
  # ---------------------------------------------------------------------------
  def self.bootstrap_do_legado!
    return true  if ativo?
    return false unless ligado?

    ctx = (AnilLanRework::BattleSync.active_context rescue nil)
    return false unless ctx && ctx.mode.to_s == "coop"

    # ─────────────────────────────────────────────────────────────────
    # A DECISAO JA VEIO PRONTA — nao se negocia nada aqui.
    #
    # Antes este ponto chamava abrir_contexto!, que mandava a party e esperava
    # 20s pela do parceiro. Como os dois clientes nao chegam aqui juntos (o
    # convidado tem o prompt de aceite a mais), quem chegava primeiro estourava
    # o tempo, devolvia false e seguia pelo coop ANTIGO, enquanto o outro
    # entrava no lockstep. Motores diferentes, batalhas separadas.
    #
    # Agora o host decide no request_coop_battle e manda a decisao dentro do
    # battle_start_signal; o convidado le e obedece. Como o sinal precede a
    # criacao da batalha nos DOIS lados, ambos ja sabem qual classe instanciar
    # — e a subclasse Battle_CoopCC continua a ser a forma de isolamento (o PVP
    # segue na Battle de origem, intocado).
    # ─────────────────────────────────────────────────────────────────
    unless (AnilLanRework::BattleSync.coop_lockstep_decidido? rescue false)
      CoopCC.log("bootstrap: lockstep NAO acordado para esta batalha — segue no coop antigo") rescue nil
      return false
    end

    CoopCC.log("bootstrap: assumindo a batalha coop #{ctx.battle_id}") rescue nil

    # A party do parceiro ja veio pelo caminho legado (inject_partner) e esta em
    # $PokemonGlobal.partner[3]. Nao ha o que esperar.
    party_dele = begin
      Array($PokemonGlobal.partner[3]) rescue []
    end

    if party_dele.empty?
      CoopCC.log("bootstrap: parceiro sem party injetada — segue no coop antigo") rescue nil
      return false
    end

    abrir_contexto_local!(
      battle_id:  ctx.battle_id,
      partner_id: ctx.partner_id,
      client_id:  ctx.client_index.to_i,
      seed:       ctx.seed
    )

    # A partir daqui o coop antigo tem de sair de cena.
    #
    # NAO usar BattleSync.clear_context: ele chama sanitize_injected_partner_state!,
    # que remove o PARCEIRO injetado. As duas guardas de la nao protegem neste
    # momento — `@active_context` acabou de ser zerado pelo proprio clear_context,
    # e `$game_temp.in_battle` ainda e false porque o prepare_battle so roda
    # depois. Resultado: o parceiro coop era removido um instante antes de a
    # batalha ser montada.
    #
    # Zerar o @active_context e TUDO o que precisamos: os 92 pontos do coop
    # legado dependem dele (P4b ponto 3). Nada mais do clear_context nos serve.
    begin
      AnilLanRework::BattleSync.instance_variable_set(:@active_context, nil)
    rescue => e
      CoopCC.log("falha ao zerar contexto legado #{e.class}: #{e.message}")
      fechar_contexto!("nao consegui desligar o legado")
      return false
    end
    # ⚠️ NAO se troca a party local aqui, ao contrario do que se faz no PVP.
    #
    # No PVP as copias sao descartadas no fim: nao ha exp, nao ha nada a
    # guardar, e trocar e so ganho. No COOP o resultado TEM de persistir — e o
    # BattleCreationHelperMethods.after_battle (que da exp, sobe nivel e evolui)
    # roda ANTES do fechar_contexto!. Com a party trocada, ele daria tudo isso as
    # COPIAS, e a restauracao logo a seguir devolveria os Pokemon reais como
    # estavam: o jogador perderia a experiencia da batalha inteira.
    #
    # Os metodos trocar_party_local!/restaurar_party_local! ficam prontos acima,
    # mas so servem se um dia houver o passo de trazer os resultados de volta
    # (exp, nivel, HP, PP, itens, evolucao) das copias para os originais.
    #
    # Enquanto isso o coop mantem a assimetria de sempre (propria equipe real, a
    # do parceiro desserializada) — que e como ele sempre funcionou.
    CoopCC.log("bootstrap OK — contexto legado limpo, assumindo o controle") rescue nil
    true
  rescue => e
    CoopCC.log("bootstrap erro #{e.class}: #{e.message}") rescue nil
    fechar_contexto!("erro no bootstrap")
    false
  end

  # REMOVIDO no D1: reordenar treinadores quebrava a exigencia da engine de
  # player_trainers[0] == $player. A ordem passa a ser sempre a da engine.
  def self.aliados_e_treinadores(minha_party, party_dele, meus_tr, tr_dele, client_id)
    if client_id.to_i % 2 == 0
      [[minha_party, party_dele], [meus_tr, tr_dele].flatten.compact]
    else
      [[party_dele, minha_party], [tr_dele, meus_tr].flatten.compact]
    end
  end
end

if defined?(WildBattle)
  class WildBattle
    class << self
      alias coopcc_original_start_core start_core unless method_defined?(:coopcc_original_start_core)

      def start_core(*args)
        return coopcc_original_start_core(*args) unless CoopCC.bootstrap_do_legado!

        outcome_variable = $game_temp.battle_rules["outcomeVar"] || 1
        can_lose         = $game_temp.battle_rules["canLose"] || false
        if BattleCreationHelperMethods.skip_battle?
          return BattleCreationHelperMethods.skip_battle(outcome_variable)
        end
        EventHandlers.trigger(:on_start_battle)
        foe_party = WildBattle.generate_foes(*args)
        player_trainers, ally_items, player_party, player_party_starts =
          BattleCreationHelperMethods.set_up_player_trainers(foe_party)

        # --- unica diferenca real em relacao a engine ---
        # A engine monta player_party como [a minha, a do parceiro] — o que da
        # arrays DIFERENTES nos dois clientes. O modelo Cable Club exige que os
        # dois partam de dados identicos, entao reordenamos para a ordem
        # canonica [cliente 0, cliente 1] em ambos.
        # D1: a party e os treinadores vem da engine, na ordem dela.
        scene  = BattleCreationHelperMethods.create_battle_scene
        battle = Battle_CoopCC.new(AnilLanRework.connection, CoopCC.client_id,
                                   scene, player_party, foe_party,
                                   player_trainers, nil, CoopCC.seed)
        battle.party1starts = player_party_starts
        battle.ally_items   = ally_items
        if $game_temp.battle_rules["size"].nil?
          setBattleRule("#{foe_party.length}v#{foe_party.length}")
        end
        BattleCreationHelperMethods.prepare_battle(battle)
        $game_temp.clear_battle_rules
        outcome = 0
        pbBattleAnimation(pbGetWildBattleBGM(foe_party), (foe_party.length == 1) ? 0 : 2, foe_party) do
          pbSceneStandby { outcome = battle.pbStartBattle }
          BattleCreationHelperMethods.after_battle(outcome, can_lose)
        end
        Input.update
        BattleCreationHelperMethods.set_outcome(outcome, outcome_variable)
        CoopCC.fechar_contexto!("fim da batalha selvagem")
        outcome
      rescue => e
        CoopCC.log("start_core erro #{e.class}: #{e.message} — caindo no fluxo antigo") rescue nil
        CoopCC.fechar_contexto!("erro")
        coopcc_original_start_core(*args)
      end
    end
  end
end

module CoopCC
  class << self
    attr_accessor :party_do_parceiro
    attr_accessor :seed
  end
end

#-------------------------------------------------------------------------------
# Caminho de TREINADOR. E o que realmente importa no coop deste jogo (ginasios,
# bosses, Raid da Torre) — selvagem e o caso menor.
#
# Copia de Overworld_BattleStarting.rb TrainerBattle.start_core (~548). Mesma
# regra do caminho selvagem: so a linha do Battle.new muda, e a reordenacao do
# lado aliado para a ordem canonica [cliente 0, cliente 1].
#
# Diferencas em relacao ao selvagem, que precisam existir aqui:
#   - foe_trainers / foe_items / party2starts (o selvagem nao tem)
#   - skip_battle e set_outcome levam o argumento `true` (batalha de treinador)
#   - a regra de tamanho vem de foe_trainers.length, nao de foe_party.length
#   - BGM e animacao de treinador
#-------------------------------------------------------------------------------
if defined?(TrainerBattle)
  class TrainerBattle
    class << self
      alias coopcc_original_start_core start_core unless method_defined?(:coopcc_original_start_core)

      def start_core(*args)
        return coopcc_original_start_core(*args) unless CoopCC.bootstrap_do_legado!

        outcome_variable = $game_temp.battle_rules["outcomeVar"] || 1
        can_lose         = $game_temp.battle_rules["canLose"] || false
        if BattleCreationHelperMethods.skip_battle?
          return BattleCreationHelperMethods.skip_battle(outcome_variable, true)
        end
        EventHandlers.trigger(:on_start_battle)
        foe_trainers, foe_items, foe_party, foe_party_starts = TrainerBattle.generate_foes(*args)
        player_trainers, ally_items, player_party, player_party_starts =
          BattleCreationHelperMethods.set_up_player_trainers(foe_party)

        # D1: party e treinadores na ordem da engine, sem reordenar.
        scene  = BattleCreationHelperMethods.create_battle_scene
        battle = Battle_CoopCC.new(AnilLanRework.connection, CoopCC.client_id,
                                   scene, player_party, foe_party,
                                   player_trainers, foe_trainers, CoopCC.seed)
        battle.party1starts = player_party_starts
        battle.party2starts = foe_party_starts
        battle.ally_items   = ally_items
        battle.items        = foe_items
        setBattleRule("#{foe_trainers.length}v#{foe_trainers.length}") if $game_temp.battle_rules["size"].nil?
        BattleCreationHelperMethods.prepare_battle(battle)
        $game_temp.clear_battle_rules
        outcome = 0
        pbBattleAnimation(pbGetTrainerBattleBGM(foe_trainers), (battle.singleBattle?) ? 1 : 3, foe_trainers) do
          pbSceneStandby { outcome = battle.pbStartBattle }
          BattleCreationHelperMethods.after_battle(outcome, can_lose)
        end
        Input.update
        BattleCreationHelperMethods.set_outcome(outcome, outcome_variable, true)
        CoopCC.fechar_contexto!("fim da batalha de treinador")
        outcome
      rescue => e
        CoopCC.log("trainer start_core erro #{e.class}: #{e.message} — caindo no fluxo antigo") rescue nil
        CoopCC.fechar_contexto!("erro")
        coopcc_original_start_core(*args)
      end
    end
  end
end

#-------------------------------------------------------------------------------
# PONTE PARA O ALIAS LEGADO
#
# O coop antigo NAO chama TrainerBattle.start_core: chama
# `TrainerBattle.anil_rework_original_start_core` (000d ~1915), que e o alias do
# metodo CRU da engine, capturado antes do meu. Ou seja, ele pula de proposito o
# wrapper do 000d — e, sem esta ponte, pulava tambem o meu, e a batalha de
# treinador em coop nunca chegava ao caminho novo.
#
# (No selvagem o coop chama `anil_rework_original_start`, que por dentro passa
#  por start_core, entao aquele caminho ja funcionava.)
#
# Aqui interceptamos o proprio alias legado: se o bootstrap assumir, seguimos
# para o wrapper novo; se nao, cai no metodo cru como sempre.
#-------------------------------------------------------------------------------
if defined?(TrainerBattle) && TrainerBattle.respond_to?(:anil_rework_original_start_core)
  class TrainerBattle
    class << self
      unless method_defined?(:coopcc_legacy_trainer_start_core) || respond_to?(:coopcc_legacy_trainer_start_core)
        alias coopcc_legacy_trainer_start_core anil_rework_original_start_core
      end

      def anil_rework_original_start_core(*args)
        unless CoopCC.bootstrap_do_legado!
          return coopcc_legacy_trainer_start_core(*args)
        end
        CoopCC.log("interceptou o alias legado de treinador")
        # start_core aqui e o wrapper do CoopCC; o bootstrap ja esta ativo, entao
        # ele segue direto para a construcao da Battle_CoopCC.
        start_core(*args)
      end
    end
  end
end
