#===============================================================================
# MOD: 127_Coop_Auth_Reprodutor.rb
#-------------------------------------------------------------------------------
# Lado CLIENTE do coop autoritativo: reproduz na cena local a lista de eventos
# que o servidor gravou ao correr a batalha.
#
# ESTADO: INERTE por omissao ($anil_coop_auth = false). So define o reprodutor;
# nada o chama enquanto a flag estiver desligada.
#
#-------------------------------------------------------------------------------
# A IDEIA
#
# O servidor corre a engine REAL do Essentials headless. A cena dele nao desenha
# nada, mas GRAVA todas as chamadas que a batalha lhe faz:
#
#     pbDisplayMessage        "O Charizard aliado usou Pirotecnia!"
#     pbAnimation             FLAMEBURST, de slot2, para slot1
#     pbHitAndHPLossAnimation slot1 perdeu 131
#
# O cliente executa essa lista pela mesma ordem, na SUA cena. Nao simula nada:
# nao ha calculo de dano, nao ha RNG, nao ha estado para reconciliar. E por isso
# que este modelo nao pode dessincronizar — nao existe segunda simulacao.
#
#-------------------------------------------------------------------------------
# REFERENCIAS, E POR QUE IMPORTAM
#
# O servidor nunca manda objetos: manda REFERENCIAS.
#     {"_"=>"slot","i"=>1}   -> o battler no slot 1
#     {"_"=>"move","id"=>..} -> o golpe, por id
# O cliente resolve para os SEUS objetos. Foi a falta disto que causou metade
# dos bugs do coop antigo (indices de party a apontar para Pokemon diferentes em
# cada lado).
#===============================================================================

# DESLIGADO em 2026-07-30. Este modelo (servidor simula, cliente REPRODUZ) nao
# converge e foi substituido pelo lockstep do 125 — ver PLANO_COOP_LOCKSTEP.md.
#
# O que o condenou: a `Battle` local tem as fases anuladas, portanto cada
# transicao de estado do motor tem de ser reimplementada a mao. Ja foram HP,
# estado, desmaio, especie do slot e sprite; faltavam os efeitos, o pokemonIndex
# e os gatilhos de habilidade. Provado no worker: quando os dois aliados
# desmaiam, o SERVIDOR escolhe os substitutos sozinho e o cliente nunca corre o
# pbRecallAndReplace — os sintomas "quando morre, buga" e "a batalha nao espera
# a troca".
#
# Fica como REFERENCIA (o transporte, o handshake e o traduzir_slot sao
# reaproveitaveis). Com a flag a false nada aqui e chamado e o coop antigo volta
# a valer, que e o estado jogavel enquanto o lockstep nao esta pronto.
$anil_coop_auth = false unless defined?($anil_coop_auth)

module CoopAuthCliente
  # Tem de bater com ServidorAnil::CoopAuth::VERSAO. Cliente com versao inferior
  # e recusado pelo servidor e fica no coop antigo — e a retrocompatibilidade.
  VERSAO = 1 unless const_defined?(:VERSAO)
end

module CoopAuthCliente
  # Metodos que NAO se reproduzem:
  #  - os que devolvem escolha do jogador (o servidor ja decidiu)
  #  - os que arrancariam ou terminariam a batalha por conta propria
  # Reproduzir estes daria controlo duplicado ou fecharia a cena a meio.
  NAO_REPRODUZIR = %w[
    pbShowCommands pbChooseTarget pbFightMenu pbItemMenu pbPartyScreen
    pbDisplayConfirmMessage pbStartBattle pbEndBattle pbAbort
  ].freeze

  class << self
    attr_accessor :ultimo_erro

    def ligado?
      $anil_coop_auth == true
    end

    # cena    : Battle::Scene local
    # eventos : lista vinda de coopauth_resultado["eventos"]
    # batalha : Battle local (so para resolver referencias de battler)
    # Devolve quantos eventos reproduziu.
    def reproduzir(cena, eventos, batalha = nil)
      return 0 unless cena
      feitos = 0
      Array(eventos).each do |ev|
        next unless ev.is_a?(Hash)
        nome = ev["m"].to_s
        next if nome.empty? || NAO_REPRODUZIR.include?(nome)
        next unless cena.respond_to?(nome)
        args = Array(ev["a"]).map { |a| resolver(a, batalha) }
        begin
          cena.send(nome, *args)
          feitos += 1
        rescue => e
          # Um evento que falhe NAO pode parar os seguintes: perder uma animacao
          # e mau, perder o resto do turno e pior.
          registrar("evento #{nome} falhou: #{e.class}: #{e.message}")
        end
      end
      feitos
    rescue => e
      self.ultimo_erro = "#{e.class}: #{e.message}"
      registrar("reproduzir falhou: #{ultimo_erro}")
      0
    end

    # ------------------------------------------------------------------------
    # ESPELHAMENTO DE SLOTS  (servidor <-> cliente)
    #
    # O servidor tem uma numeracao fixa:   0 = host, 2 = guest, 1 e 3 = inimigos.
    # O cliente NAO pode ter essa: a engine exige que `player_trainers[0]` seja
    # o $player (e quem tem pokedex), portanto CADA cliente se ve a si proprio
    # no slot 0 e ao parceiro no 2.
    #
    # Ou seja, para o host as duas numeracoes coincidem; para o guest estao
    # TROCADAS. Foi exatamente isto que fez os dois jogadores controlarem o
    # mesmo Geodude e deixou o Venusaur da Gaby sem dono: o guest pedia menu
    # para o slot 2, que no ecra dele e o Pokemon do parceiro.
    #
    # Os inimigos (1 e 3) sao iguais nos dois lados — vem do mesmo treinador,
    # pela mesma ordem — e nao se traduzem.
    #
    # A troca e a sua propria inversa, por isso a MESMA funcao serve nos dois
    # sentidos (traduzir o que chega do servidor e o que se envia para la).
    def traduzir_slot(slot)
      s = slot.to_i
      return s if sou_host || s < 0
      return 2 if s == 0
      return 0 if s == 2
      s
    end

    # Converte a referencia do servidor no objeto LOCAL correspondente.
    #
    # TEM DE DESCER PELAS LISTAS. Metodos da cena como pbHitAndHPLossAnimation,
    # pbSendOutBattlers e pbRecall recebem LISTAS (ou listas de pares), com as
    # referencias la dentro. A versao anterior devolvia qualquer Array intacto,
    # entao esses Hashes chegavam crus a cena:
    #     undefined method `index' for {"_"=>"slot","i"=>3}:Hash
    # Cada animacao falhava e, ao fim de alguns turnos, os sprites e as barras
    # de vida desapareciam do ecra.
    def resolver(a, batalha)
      return a.map { |x| resolver(x, batalha) } if a.is_a?(Array)
      return a unless a.is_a?(Hash)
      return a.map { |k, v| [k, resolver(v, batalha)] }.to_h unless a.key?("_")
      case a["_"].to_s
      when "slot"
        i = traduzir_slot(a["i"])
        return i unless batalha && batalha.battlers
        b = batalha.battlers[i]
        sincronizar_battler(b, a, batalha) if b
        b
      when "move"
        id = a["id"].to_s
        id.empty? ? nil : (GameData::Move.try_get(id.to_sym) rescue id.to_sym)
      when "pkmn"
        resolver_pokemon(a["sp"].to_s, batalha)
      else
        nil   # "obj": tipo que o servidor nao soube representar
      end
    rescue
      nil
    end

    # Poe o battler local no mesmo estado do servidor NO MOMENTO do evento.
    #
    # Duas coisas, e as duas sao precisas ANTES de a cena animar:
    #
    #  1. HP — a cena anima do valor antigo (que vem no evento) ate ao hp ATUAL
    #     do battler. Sem isto a barra subia em vez de descer.
    #
    #  2. ESPECIE — quando o servidor substitui um Pokemon (troca ou desmaio), o
    #     battler local continuava a apontar para o anterior: a cena mandava
    #     recolher/enviar um Pokemon que o slot nao tinha e o sprite
    #     desaparecia. Aqui poe-se o Pokemon certo no slot primeiro.
    def sincronizar_battler(b, ref, batalha)
      sp = ref["sp"].to_s
      if !sp.empty? && (b.pokemon.nil? || (b.pokemon.species.to_s != sp rescue true))
        novo = pokemon_local_por_especie(sp, batalha, b)
        if novo && b.respond_to?(:pbInitialize)
          idx = indice_na_party(novo, batalha, b)
          b.pbInitialize(novo, idx.to_i) rescue nil
          atualizar_sprite(batalha, b, novo)
        end
      end
      hp = ref["hp"]
      return if hp.nil?
      hp = hp.to_i
      hp = b.totalhp.to_i if b.totalhp.to_i > 0 && hp > b.totalhp.to_i
      b.hp = hp if b.hp.to_i != hp
    rescue => e
      registrar("sincronizar_battler slot #{ref['i']}: #{e.class}: #{e.message}")
    end

    # Trocar o Pokemon do battler NAO troca o sprite: a cena guarda os seus
    # proprios sprites por slot. Sem isto a troca acontecia mas o Pokemon que
    # entrava nao aparecia no ecra.
    #
    # Fica ISOLADO num metodo com o seu proprio rescue de proposito: quando isto
    # vivia dentro do sincronizar_battler, uma falha da cena saltava para o
    # rescue de fora e o HP deixava de ser aplicado. Um sprite que nao aparece e
    # feio; um HP que nao acompanha e um desync.
    def atualizar_sprite(batalha, b, pkmn)
      cena = (batalha.scene rescue nil)
      return unless cena
      cena.pbChangePokemon(b, pkmn) if cena.respond_to?(:pbChangePokemon)
      cena.pbRefreshOne(b.index)    if cena.respond_to?(:pbRefreshOne)
    rescue => e
      registrar("atualizar_sprite slot #{b.index rescue '?'}: #{e.class}: #{e.message}")
    end

    # Procura na fatia de party DESTE battler — nunca na do parceiro, senao
    # trazia-se o Pokemon do outro jogador para o slot errado.
    def pokemon_local_por_especie(sp, batalha, battler)
      encontrado = nil
      batalha.eachInTeamFromBattlerIndex(battler.index) do |pkmn, _i|
        next if encontrado || pkmn.nil?
        encontrado = pkmn if (pkmn.species.to_s == sp rescue false)
      end
      encontrado
    rescue
      nil
    end

    def indice_na_party(pkmn, batalha, battler)
      idx = nil
      batalha.eachInTeamFromBattlerIndex(battler.index) do |pk, i|
        idx = i if idx.nil? && pk.equal?(pkmn)
      end
      idx || 0
    rescue
      0
    end

    # A cena quer um POKEMON de verdade (chama .species, .poke_ball, .name), nao
    # a especie. Devolver o GameData::Species fazia falhar o pbRecall e o
    # pbSendOutBattlers com `undefined method 'poke_ball'`.
    #
    # Procuramos o Pokemon LOCAL dessa especie: primeiro em campo, depois nas
    # parties (um que vai entrar ainda nao esta em campo). So se nao existir
    # mesmo e que devolvemos a especie, que ainda serve para texto e icones.
    def resolver_pokemon(sp, batalha)
      return nil if sp.empty?
      alvo = sp.to_sym
      if batalha
        Array(batalha.battlers).each do |b|
          next unless b && b.pokemon
          return b.pokemon if (b.pokemon.species.to_s == sp rescue false)
        end
        [(batalha.party1 rescue nil), (batalha.party2 rescue nil)].each do |party|
          Array(party).each do |pk|
            next unless pk
            return pk if (pk.species.to_s == sp rescue false)
          end
        end
      end
      (GameData::Species.try_get(alvo) rescue alvo)
    rescue
      nil
    end

    def resolver_lista(args, batalha)
      Array(args).map { |a| resolver(a, batalha) }
    end

    # Aplica o estado autoritativo por cima, DEPOIS de reproduzir os eventos.
    # Os eventos dao a narrativa; isto garante que o resultado final e o do
    # servidor, mesmo que alguma animacao se tenha perdido pelo caminho.
    def aplicar_estado(batalha, estado)
      return 0 unless batalha && estado.is_a?(Array)
      aplicados = 0
      estado.each do |e|
        next unless e.is_a?(Hash)
        b = (batalha.battlers[traduzir_slot(e["slot"])] rescue nil)
        next unless b
        begin
          hp = e["hp"].to_i
          b.hp = hp if b.hp.to_i != hp
          st = e["status"].to_s
          if st != "" && (b.status.to_s != st)
            b.status = (st == "NONE" ? :NONE : st.to_sym)
          end
          b.pbFaint if e["fainted"] && !(b.fainted? rescue true)
          aplicados += 1
        rescue => err
          registrar("estado slot #{e['slot']} -> local #{traduzir_slot(e['slot'])}: #{err.class}: #{err.message}")
        end
      end
      batalha.scene.pbRefresh rescue nil
      aplicados
    end

    # Reproduz um resultado inteiro: eventos + estado final.
    def aplicar_resultado(batalha, resultado)
      return unless resultado.is_a?(Hash)
      n = reproduzir((batalha && batalha.scene), resultado["eventos"], batalha)
      m = aplicar_estado(batalha, resultado["estado"])
      registrar("turno #{resultado['turno']}: #{n} evento(s), #{m} battler(s) alinhado(s)")
      resultado["fim"] ? :fim : :continua
    end

    # Ficheiro POR JOGADOR. Com um so, os dois clientes escreviam intercalado e
    # era impossivel saber de quem era cada linha — foi o que escondeu que o
    # HOST nunca registava nada.
    def registrar(msg)
      # Escrevia um ficheiro por EVENTO durante a batalha — I/O em laco de jogo.
      # Fica atras do mesmo interruptor global dos outros logs de diagnostico.
      return unless ($anil_logs_diagnostico == true) || (anil_diagnostico_ligado? rescue false)
      id = (AnilLanRework.self_internal_id.to_s rescue "")
      id = "sem-id" if id.strip.empty?
      arq = "coopauth_#{id.gsub(/[^A-Za-z0-9_-]/, '_')}.txt"
      papel = sou_host.nil? ? "?" : (sou_host ? "HOST " : "GUEST")
      File.open(arq, "a") { |f| f.puts("[#{Time.now.strftime('%H:%M:%S')}] #{papel} #{msg}") }
    rescue
    end
  end
end

#-------------------------------------------------------------------------------
# Recepcao dos pacotes do servidor. So guarda; quem consome e o fluxo da
# batalha, ligado num passo seguinte.
#-------------------------------------------------------------------------------
module CoopAuthCliente
  class << self
    def caixa
      @caixa ||= []
    end

    def guardar_resultado(pacote)
      caixa << pacote if pacote.is_a?(Hash)
    end

    def proximo_resultado(battle_id, turno = nil)
      i = caixa.index do |p|
        p["battle_id"].to_s == battle_id.to_s &&
          (turno.nil? || p["turno"].to_i == turno.to_i)
      end
      i ? caixa.delete_at(i) : nil
    end

    def limpar!
      @caixa = []
      self.ultimo_erro = nil
    end
  end
end

#===============================================================================
# INTEGRACAO COM A CENA DE BATALHA DO CLIENTE
#-------------------------------------------------------------------------------
# O truque e o MESMO que o servidor usa, do outro lado:
#
#   servidor: pbStartBattleCore(false)  -> setup, e depois corre as fases
#   cliente : pbStartBattleCore(false)  -> setup, e depois NAO corre nada
#
# O cliente cria uma `Battle` a serio — precisa dela para a cena existir, os
# sprites aparecerem e os battlers terem objetos que a cena saiba desenhar — mas
# NUNCA a deixa resolver um turno. O `pbBattleLoop` e substituido por:
#
#     menu do meu slot -> envia escolha -> espera resultado -> reproduz
#
# Como a Battle local nunca calcula dano nem sorteia nada, nao ha segunda
# simulacao. Ela e so o palco.
#===============================================================================

module CoopAuthCliente
  # 45s era demasiado: quando algo corre mal, o jogador fica quase um minuto a
  # olhar para um ecra parado. Com a recusa a chegar aos dois lados, o caso
  # normal de falha e imediato; isto e so o travao para perda de pacote.
  ESPERA_TIMEOUT = 12.0 unless const_defined?(:ESPERA_TIMEOUT)

  class << self
    attr_accessor :battle_id, :meu_slot, :sou_host

    # Monta o objeto da batalha. NAO arranca a cena — ver a nota em `correr`.
    def preparar_batalha(scene, party1, foe_party, ally_trainers, foe_trainers, starts)
      batalha = Battle.new(scene, party1, foe_party, ally_trainers, foe_trainers)
      batalha.party1starts = starts if batalha.respond_to?(:party1starts=)
      batalha.setBattleMode("double") if batalha.respond_to?(:setBattleMode)

      # Blindagem: se algo tentar resolver um turno localmente, nao resolve.
      # E defensivo de proposito — foi a simulacao local em paralelo que
      # produziu todos os desyncs anteriores.
      def batalha.pbAttackPhase(*_a);     nil; end
      def batalha.pbEndOfRoundPhase(*_a); nil; end
      def batalha.pbCommandPhase(*_a);    nil; end

      batalha
    end

    # O laco que substitui o pbBattleLoop.
    #
    # O pbStartBattleCore TEM de correr AQUI DENTRO, e nao na montagem.
    #
    # Na engine, `battle.pbStartBattle` e chamado DENTRO do bloco do
    # pbBattleAnimation, que e quem faz a transicao de ecra e prepara o contexto
    # grafico da batalha. Ao arranca-lo antes (como esta versao fazia), a cena
    # desenhava-se por cima do overworld — o jogador via a batalha sem cenario,
    # com o mapa por baixo — e depois a transicao passava-lhe por cima e deixava
    # o ecra PRETO quando chegava ao menu de comandos.
    #
    # O `false` continua a ser o que nos interessa: faz o setup todo e nao entra
    # no pbBattleLoop, que e o que substituimos.
    def correr(batalha)
      batalha.pbStartBattleCore(false)
      resultado = nil
      loop do
        escolha = pedir_escolha(batalha)
        return :abortada if escolha.nil?

        enviar_escolha(escolha)
        resultado = esperar_resultado
        unless resultado
          registrar("TIMEOUT a espera do servidor")
          return :timeout
        end

        aplicar_resultado(batalha, resultado)
        return :fim if resultado["fim"]
      end
    end

    # Menu normal do Essentials, mas SO para o slot deste jogador.
    # O slot do parceiro e dos inimigos nunca abre menu aqui: quem decide por
    # eles e o parceiro (no cliente dele) e o servidor.
    def pedir_escolha(batalha)
      slot = meu_slot.to_i
      batalha.pbClearChoice(slot) rescue nil
      loop do
        cmd = (batalha.pbCommandMenu(slot, true) rescue 0)
        case cmd
        when 0   # Lutar
          next unless (batalha.pbFightMenu(slot) rescue false)
          escolha = batalha.choices[slot]
          # O alvo sai em numeracao LOCAL e o servidor pensa na dele. Para os
          # inimigos (1 e 3) da no mesmo, mas um golpe dirigido ao PARCEIRO
          # (local 2) tem de chegar ao servidor como o slot certo do dono.
          alvo = (escolha[3].to_i rescue -1)
          return { "kind" => "move",
                   "index" => escolha[1].to_i,
                   "target" => traduzir_slot(alvo) }
        when 2   # Pokemon
          next unless (batalha.pbPartyMenu(slot) rescue false)
          escolha = batalha.choices[slot]
          # Indice RELATIVO a minha propria party. Localmente sou sempre o
          # primeiro treinador, portanto a minha fatia comeca em 0 e o indice do
          # menu ja e relativo. Quem soma o desvio do dono e o servidor — ele e
          # que sabe onde comeca a fatia de cada um na party1 combinada.
          return { "kind" => "switch", "index" => escolha[1].to_i }
        when 3   # Fugir
          return nil if (batalha.pbRunMenu(slot) rescue false)
        end
      end
    rescue => e
      registrar("pedir_escolha: #{e.class}: #{e.message}")
      nil
    end

    # Chamado pelo HOST ao comecar a batalha coop. Manda as tres parties e o
    # servidor monta a batalha. Marshal+base64, o mesmo formato que o projeto ja
    # usa para trocas — reproduz o Pokemon inteiro, sem lista de campos para
    # esquecer (foi assim que o nivel chegava errado no coop antigo).
    def iniciar_batalha(battle_id, guest_id, minha_party, party_parceiro, foes, seed = nil)
      return false unless defined?(AnilLanRework) && AnilLanRework.connected?
      self.battle_id = battle_id.to_s
      self.sou_host  = true
      # O slot que abre menu e sempre LOCAL: cada cliente e o 0 no seu ecra.
      self.meu_slot  = 0
      limpar_caixa_mantendo_contexto!
      AnilLanRework.connection.send_packet("coopauth_iniciar",
        "battle_id"   => self.battle_id,
        "guest_id"    => guest_id.to_s,
        "versao"      => VERSAO,
        "seed"        => seed,
        "host_party"  => empacotar(minha_party),
        "guest_party" => empacotar(party_parceiro),
        "foe_party"   => empacotar(foes))
      registrar("host pediu batalha #{self.battle_id} (guest=#{guest_id})")
      true
    rescue => e
      registrar("iniciar_batalha: #{e.class}: #{e.message}")
      false
    end

    # O guest nao envia parties: quem as junta e o host. So marca o contexto.
    # NAO limpa a caixa: o host pode ter pedido a batalha ANTES de o guest
    # chegar aqui, e nesse caso o "coopauth_pronto" ja esta na caixa. Limpar
    # deitava-o fora e o guest esperava 45s por um pacote que ja tinha recebido.
    # Descartamos so o que for de outra batalha.
    def entrar_como_guest(battle_id)
      self.battle_id = battle_id.to_s
      self.sou_host  = false
      # Slot LOCAL, nao o do servidor. Pedir menu para o 2 (o slot do guest no
      # servidor) abria o menu do PARCEIRO no ecra do guest — os dois jogadores
      # acabavam a controlar o mesmo Pokemon. Ver traduzir_slot.
      self.meu_slot  = 0
      caixa.reject! { |p| p["battle_id"].to_s != self.battle_id }
      self.ultimo_erro = nil
      registrar("guest entrou na batalha #{self.battle_id} (caixa: #{caixa.length} pacote(s) ja recebidos)")
    end

    def abandonar
      return unless defined?(AnilLanRework) && AnilLanRework.connected?
      AnilLanRework.connection.send_packet("coopauth_abandonar", "battle_id" => battle_id)
      registrar("abandonou #{battle_id}")
    rescue
    end

    def empacotar(party)
      Array(party).compact.map { |pk| [Marshal.dump(pk)].pack("m0") }
    rescue
      []
    end

    def limpar_caixa_mantendo_contexto!
      @caixa = []
      self.ultimo_erro = nil
    end

    def enviar_escolha(escolha)
      return unless defined?(AnilLanRework) && AnilLanRework.connected?
      AnilLanRework.connection.send_packet("coopauth_escolha",
        "battle_id" => battle_id, "escolha" => escolha)
      registrar("enviou escolha: #{escolha['kind']}")
    rescue => e
      registrar("enviar_escolha: #{e.class}: #{e.message}")
    end

    # Espera o resultado, mostrando aviso — sem isto a espera parece um crash.
    def esperar_resultado
      inicio = Time.now.to_f
      quadro = 0
      loop do
        r = proximo_resultado(battle_id)
        return r if r
        break unless (defined?(AnilLanRework) && AnilLanRework.connected?)
        break if Time.now.to_f - inicio >= ESPERA_TIMEOUT
        quadro += 1
        bombear_rede
        Graphics.update rescue nil
        Input.update rescue nil
      end
      nil
    end

    def bombear_rede
      return unless defined?(AnilLanRework) && AnilLanRework.connected?
      AnilLanRework.connection.tick
      AnilLanRework.connection.drain { |p| AnilLanRework::Router.route_packet(p) }
    rescue
    end
  end
end

#===============================================================================
# GANCHO NO FLUXO DE CONVITE
#-------------------------------------------------------------------------------
# Reutiliza o padrao que ja se provou no 125: o coop antigo monta tudo (convite,
# regras, parceiro injetado) e chama activate_context com battle_id, partner_id,
# client_index e seed. Lemos esses valores no arranque da batalha em vez de
# duplicar a montagem toda.
#
# Como o coop antigo chama `anil_rework_original_start_core` (o alias do metodo
# CRU, capturado antes de qualquer wrapper), e ESSE que temos de intercetar —
# intercetar so o start_core nao chegava para batalhas de treinador.
#
# Se qualquer coisa falhar, devolve false e a batalha segue pelo caminho antigo.
#===============================================================================

module CoopAuthCliente
  class << self
    # ------------------------------------------------------------------------
    # O LACO AUTORITATIVO
    #
    # Substitui o pbBattleLoop. Monta a cena e a Battle local (que serve so de
    # palco — as fases dela sao no-op, ver preparar_batalha) e depois:
    #     menu do meu slot -> envia -> espera o servidor -> reproduz
    #
    # A montagem copia o TrainerBattle.start_core do engine
    # (Overworld_BattleStarting ~548), trocando so o loop.
    # ------------------------------------------------------------------------
    def correr_batalha_de_treinador(foe_trainers, foe_items, foe_party, foe_starts, _args)
      outcome_variable = $game_temp.battle_rules["outcomeVar"] || 1
      can_lose         = $game_temp.battle_rules["canLose"] || false
      if BattleCreationHelperMethods.skip_battle?
        return BattleCreationHelperMethods.skip_battle(outcome_variable, true)
      end
      EventHandlers.trigger(:on_start_battle)

      player_trainers, ally_items, player_party, player_starts =
        BattleCreationHelperMethods.set_up_player_trainers(foe_party)

      scene   = BattleCreationHelperMethods.create_battle_scene
      batalha = preparar_batalha(scene, player_party, foe_party,
                                 player_trainers, foe_trainers, player_starts)
      batalha.party2starts = foe_starts if batalha.respond_to?(:party2starts=)
      batalha.ally_items   = ally_items if batalha.respond_to?(:ally_items=)
      batalha.items        = foe_items  if batalha.respond_to?(:items=)
      BattleCreationHelperMethods.prepare_battle(batalha)
      $game_temp.clear_battle_rules

      resultado = nil
      pbBattleAnimation(pbGetTrainerBattleBGM(foe_trainers), (batalha.singleBattle? ? 1 : 3), foe_trainers) do
        pbSceneStandby { resultado = correr(batalha) }
        BattleCreationHelperMethods.after_battle(batalha.decision.to_i, can_lose)
      end
      Input.update
      BattleCreationHelperMethods.set_outcome(batalha.decision.to_i, outcome_variable, true)
      registrar("batalha terminou: #{resultado.inspect} decisao=#{batalha.decision}")
      encerrar_contexto!
      batalha.decision.to_i
    end

    def encerrar_contexto!
      self.battle_id = nil
      self.meu_slot  = nil
      self.sou_host  = nil
      limpar!
    rescue
    end

    def contexto_legado
      ctx = (AnilLanRework::BattleSync.active_context rescue nil)
      return nil unless ctx && ctx.mode.to_s == "coop"
      ctx
    rescue
      nil
    end

    # Prepara o contexto a partir do coop antigo. true = assumimos a batalha.
    def assumir!(foes)
      return registrar_falha("coop autoritativo desligado") unless ligado?
      ctx = contexto_legado
      return registrar_falha("sem contexto coop do 000d (active_context vazio ou mode != coop)") unless ctx

      eu_sou_host = (ctx.client_index.to_i == 0)
      if eu_sou_host
        parceiro = party_do_parceiro
        return registrar_falha("sem party do parceiro") if parceiro.nil? || parceiro.empty?
        ok = iniciar_batalha(ctx.battle_id, ctx.partner_id, $player.party, parceiro, foes, ctx.seed)
        return false unless ok
      else
        entrar_como_guest(ctx.battle_id)
      end

      # O coop antigo tem de sair de cena: os ~92 pontos dele dependem todos do
      # active_context. Zerar basta (ver 125, P4b ponto 3). NAO usar
      # clear_context, que remove o parceiro injetado.
      AnilLanRework::BattleSync.instance_variable_set(:@active_context, nil) rescue nil

      esperar_pronto
    end

    # A party do parceiro ja foi injetada pelo coop antigo em $PokemonGlobal.partner.
    def party_do_parceiro
      p = ($PokemonGlobal && $PokemonGlobal.partner) ? $PokemonGlobal.partner[3] : nil
      Array(p).compact
    rescue
      []
    end

    # O host espera a confirmacao do servidor antes de abrir a cena; o guest
    # espera o mesmo pacote, que o servidor manda aos dois.
    def esperar_pronto
      inicio = Time.now.to_f
      quadro = 0
      # Sem aviso, o jogador ve o ecra parado e assume que crashou — foi
      # exatamente o "o outro travou" reportado no primeiro teste.
      janela = abrir_aviso("Preparando batalha no servidor")
      begin
        loop do
          p = proximo_resultado(battle_id)
          if p
            case p["type"].to_s
            when "coopauth_pronto"
              registrar("servidor confirmou #{battle_id}")
              return true
            when "coopauth_recusado"
              return registrar_falha("servidor recusou: #{p['motivo']}")
            end
          end
          break unless (defined?(AnilLanRework) && AnilLanRework.connected?)
          break if Time.now.to_f - inicio >= ESPERA_TIMEOUT
          quadro += 1
          atualizar_aviso(janela, "Preparando batalha no servidor" + ("." * (1 + ((quadro / 8) % 3))))
          bombear_rede
          Graphics.update rescue nil
          Input.update rescue nil
        end
        registrar_falha("timeout a espera do servidor")
      ensure
        fechar_aviso(janela)
      end
    end

    # Aviso simples, independente da cena de batalha (que ainda nao existe
    # quando esperamos pelo "pronto").
    def abrir_aviso(texto)
      vp = Viewport.new(0, 0, Graphics.width, Graphics.height)
      vp.z = 99_999
      j = Window_UnformattedTextPokemon.newWithSize(texto, 0, 0, Graphics.width, 64, vp)
      j.y = (Graphics.height - j.height) / 2
      [vp, j]
    rescue
      nil
    end

    def atualizar_aviso(par, texto)
      return unless par
      par[1].text = texto rescue nil
      par[1].update rescue nil
    rescue
    end

    def fechar_aviso(par)
      return unless par
      par[1].dispose rescue nil
      par[0].dispose rescue nil
    rescue
    end

    def registrar_falha(msg)
      registrar("NAO assumiu: #{msg} — segue pelo coop antigo")
      self.battle_id = nil
      false
    end
  end
end

# O GUEST entra pelo alias legado (o coop antigo chama-o de proposito, saltando
# wrappers). O HOST entra pelo start_core NORMAL — ele caminha ate ao treinador
# como em qualquer batalha. Enganchar so um deixava o host a jogar pelo caminho
# antigo e o guest a esperar por um "pronto" que nunca era pedido.
module CoopAuthCliente
  def self.tratar_start_core(klass, args, legacy)
    # Estas saidas nao podem ser silenciosas. Quando o gancho do guest nao
    # disparava, o log do cliente nao tinha UMA linha a explicar porque — so a
    # ausencia de linhas, que nao distingue "nao entrou" de "entrou e desistiu".
    unless ligado?
      registrar("gancho #{legacy}: coop autoritativo desligado — segue pelo antigo")
      return :nao
    end
    registrar("gancho #{legacy} disparou")
    foe_trainers, foe_items, foe_party, foe_starts = klass.generate_foes(*args)
    return :nao unless assumir!(foe_party)
    registrar("assumiu batalha de treinador — laco autoritativo")
    [:sim, correr_batalha_de_treinador(foe_trainers, foe_items, foe_party, foe_starts, args)]
  rescue => e
    registrar("gancho falhou: #{e.class}: #{e.message} — caindo no antigo")
    encerrar_contexto!
    :nao
  end
end

if defined?(TrainerBattle)
  class TrainerBattle
    class << self
      # ATENCAO AO `method_defined?` — aqui dentro NAO se pode usar respond_to?.
      #
      # Dentro de `class << self`, o `self` e a SINGLETON CLASS. `respond_to?`
      # pergunta se esse objeto responde ao metodo; mas o que procuramos e um
      # metodo de INSTANCIA da singleton class (= metodo de classe de
      # TrainerBattle). Logo respond_to? devolve sempre false.
      #
      # O estrago: a guarda do guest (2) nunca era verdadeira e o gancho do
      # GUEST NUNCA chegou a ser instalado — o jogador 2 caia sempre no coop
      # antigo e ficava no "aguardando X escolher" enquanto o host jogava pelo
      # caminho novo. Nos logs do cliente nao havia UMA linha GUEST.
      # Na guarda (1) o efeito era o inverso e mais traicoeiro: dava sempre
      # false, o alias corria sempre, e um segundo carregamento apontaria o
      # alias para o proprio wrapper (recursao infinita).
      #
      # O 125 acertava porque testava `TrainerBattle.respond_to?` FORA do
      # `class << self`, onde o self e a classe.

      # 1) caminho do HOST
      unless method_defined?(:coopauth_original_start_core)
        alias coopauth_original_start_core start_core
      end
      def start_core(*args)
        r = CoopAuthCliente.tratar_start_core(TrainerBattle, args, :start_core)
        return r[1] if r.is_a?(Array)
        coopauth_original_start_core(*args)
      end

      # 2) caminho do GUEST (o coop antigo chama este alias directamente)
      if method_defined?(:anil_rework_original_start_core)
        unless method_defined?(:coopauth_legacy_start_core)
          alias coopauth_legacy_start_core anil_rework_original_start_core
        end
        def anil_rework_original_start_core(*args)
          r = CoopAuthCliente.tratar_start_core(TrainerBattle, args, :legacy)
          return r[1] if r.is_a?(Array)
          coopauth_legacy_start_core(*args)
        end
      end
    end
  end

  # Confirma que os DOIS ganchos ficaram instalados. Sao precisos os dois: o
  # host entra pelo start_core normal e o guest pelo alias legado. Faltar um
  # nao rebenta nada — apenas poe os dois jogadores em caminhos diferentes, que
  # e o pior desync possivel e o mais dificil de ler nos logs.
  begin
    sing  = TrainerBattle.singleton_class
    host  = sing.method_defined?(:coopauth_original_start_core)
    guest = sing.method_defined?(:coopauth_legacy_start_core)
    CoopAuthCliente.registrar("ganchos instalados: host=#{host} guest=#{guest}" \
                              "#{(host && guest) ? '' : '  <<< ATENCAO: gancho em falta'}")
  rescue
  end
end
