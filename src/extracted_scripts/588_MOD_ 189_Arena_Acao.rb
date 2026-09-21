# encoding: UTF-8
#===============================================================================
# MOD: 189_Arena_Acao  —  batalha em tempo real no overworld (PROTOTIPO)
#-------------------------------------------------------------------------------
#   /arena            contra a IA
#   /arena <nome>     desafia outro jogador no mesmo mapa
#   /arena a <nome>   o mesmo, mas os dois com um Pokemon sorteado
#   /arena sair       termina
#
# Controlos: setas para andar, A / S / D / Shift para os quatro golpes.
#
# ⚠️ ISTO E UM PROTOTIPO DE SENSACAO, NAO UM SISTEMA DE BATALHA.
#
# O objectivo e responder a uma pergunta: "e divertido controlar o Pokemon e
# acertar golpes no mapa?". Tudo o que nao serve essa pergunta ficou de fora, e
# de proposito:
#
#   - Nao ha rede. Um so jogador contra uma IA. O PvP em tempo real tem um
#     problema de autoridade (com latencia, os dois clientes acham que
#     acertaram primeiro) que este projecto ja pagou caro no coop. Resolve-se
#     depois de se saber se vale a pena.
#   - O HP e uma COPIA. Nao se toca no Pokemon real: perder aqui nao desmaia
#     nada nem gasta poçoes. Um prototipo nao pode custar nada ao jogador.
#   - O dano e uma formula reduzida. O `pbCalcDamage` do motor precisa de um
#     objecto Battle inteiro; aqui usa-se nivel/poder/ataque/defesa e o tipo.
#     Nao bate certo com a batalha por turnos ao ultimo ponto de HP — e nem
#     devia: uma arena de accao nao se equilibra como um turno.
#
# ⚠️ O QUE JA EXISTIA E FEZ ISTO SER BARATO.
#
# 1. `Game_Character#animation_id`: por-lhe um numero faz o `Sprite_Character`
#    tocar a animacao por cima do boneco, no mapa (0067:224). As animacoes de
#    golpe sao as mesmas da batalha — o `move2anim.dat` da o indice e nao e
#    preciso batalha nenhuma para o ler.
# 2. Os sprites `Followers/<ESPECIE>` existem para toda a gente.
# 3. O `move_toward_player` do motor da a IA de perseguicao de graca.
#
# ⚠️ OS ALCANCES SAO UMA PRIMEIRA APROXIMACAO.
#
# Fisicos batem a uma casa, especiais em linha ate cinco, e os que atingem
# varios fazem area a volta de quem ataca. Golpes com forma propria — o Rollout
# a rolar, o Fly a subir — vao precisar de tratamento individual. Isso e
# trabalho de desenho, nao de motor, e faz-se em cima disto.
#===============================================================================

module AnilArena
  ACTIVO = true

  #-----------------------------------------------------------------------------
  # A CHAVE
  #
  # ⚠️ SEM O AMULETO, NADA DISTO EXISTE.
  #
  # A arena mexe em coisas de que o jogo normal depende — o boneco do jogador, o
  # movimento, os spawns do mato. Enquanto ela e experimental, quem nao pediu
  # para a testar nao deve sequer ver que ela existe: sem o item, o menu do
  # seguidor volta a ser o de sempre, o menu do outro treinador nao ganha linha
  # nenhuma, e os comandos respondem como um comando que nao existe.
  #
  # ⚠️ E O ITEM NASCE EM RUBY, NAO NO PBS.
  #
  # Acrescentar uma linha ao `PBS/items.txt` obriga a regerar o `items.dat` — e o
  # guarda `.pbs_compiled_raid_v3` faz com que isso REGERE TODOS os .dat na
  # maquina de cada jogador, o que ja partiu coisas neste projecto (ver o MOD
  # 123). Registar em codigo da o mesmo item sem tocar em ficheiro de dados.
  ITEM = :AMULETOTESTE

  def self.registar_item!
    return unless defined?(GameData::Item)
    return if (GameData::Item.exists?(ITEM) rescue false)
    GameData::Item.register({
      :id               => ITEM,
      :real_name        => "Amuleto Teste",
      :real_name_plural => "Amuletos Teste",
      :pocket           => 8,          # objectos importantes
      :price            => 0,
      :field_use        => 0,
      :flags            => [],
      :real_description => "Permite lutar no mapa, em tempo real, com o Pokémon à frente. Em testes."
    })
  rescue => e
    (AnilArena.log("falha a registar o amuleto: #{e.class}: #{e.message}") rescue nil)
  end

  # ⚠️ UM ITEM ERA UMA PERMISSAO SO, E ERAM DUAS COISAS DIFERENTES.
  #
  # O amuleto respondia a pergunta "esta pessoa pode usar a arena?" e essa
  # pergunta servia tudo: a batalha directa, a automatica, a masmorra, o convite
  # a outro jogador. Quando o Guia Mestre apareceu, ele foi posto POR CIMA do
  # amuleto — para caçar sozinho era preciso ter os dois, e isso nao e o que os
  # dois itens querem dizer.
  #
  # Sao permissoes independentes, e a partir daqui le-se cada uma pelo nome:
  #
  #     Amuleto Teste   a batalha DIRECTA: eu viro o Pokemon e luto. Selvagens,
  #                     treinadores do mapa, outros jogadores, e a masmorra —
  #                     que e a mesma luta noutro sitio.
  #     Guia Mestre     a batalha AUTOMATICA: eu continuo eu, e mando o Pokemon
  #                     caçar sozinho enquanto ando.
  #
  # Ter um nao da o outro, e nao ter nenhum e o que sempre foi: a arena nao
  # existe. O `libertada?` fica como o guarda-chuva — e o que decide se a pessoa
  # chega a VER a arena (o menu do Pokemon, os comandos) — e cada porta a seguir
  # pergunta pela sua chave.
  def self.directa?
    return false unless ACTIVO
    ($bag && $bag.has?(ITEM)) ? true : false
  rescue
    false
  end

  def self.automatica_livre?
    return false unless ACTIVO
    (AnilArenaChaves.guia? rescue false)
  rescue
    false
  end

  def self.libertada?
    directa? || automatica_livre?
  rescue
    false
  end

  # ⚠️ DUAS CONDICOES, E NAO UMA.
  #
  # O amuleto diz se a arena EXISTE para este jogador; a opcao diz se ele QUER
  # que os treinadores do mapa usem esta batalha. Quem tem o amuleto para testar
  # a batalha directa nao fica preso a lutar todos os ginasios em tempo real
  # sem ter pedido — a opcao nasce desligada.
  def self.modo_treinador?
    # Lutar contra o treinador do mapa e batalha directa: e o amuleto que manda.
    return false unless directa?
    return false unless $PokemonSystem
    # ⚠️ UMA RAID DE BILHETE NAO PASSA POR AQUI. FICA COM O ECRA DE BATALHA.
    #
    # Ela chama a luta dentro de um `pbFadeOutIn` e traz consigo a equipa dos
    # `.dat` da Torre, a musica propria, o `canLose` e os textos — nada disso
    # existe do lado da arena. Assumida por ela, o que se ve e um ecra preto.
    #
    # O `RaidTorre.batalha_de_raid` poe a marca a volta da chamada; isto so tem
    # de a respeitar.
    return false if ($game_temp.instance_variable_get(:@anil_raid_a_decorrer) rescue false)
    ($PokemonSystem.arena_treinador rescue 1) == 0
  rescue
    false
  end

  ID_INIMIGO   = 8100   # id do evento da IA no mapa; alto para nao chocar
  ID_MARCADOR  = 8101   # evento invisivel que ancora as animacoes no chao
  ID_CORPO     = 8102   # o treinador, parado, enquanto o Pokemon luta
  ID_ALIADO    = 8103   # o segundo Pokemon, o que ajuda
  ID_PARCEIRO  = 8104   # o ajudante DO OUTRO, desenhado no meu ecra

  # ⚠️ A BANDA DA ARENA NAO CHEGA, E AINDA POR CIMA CHOCA COM ELA PROPRIA.
  #
  # O `ID_INIMIGO` e 8100 e o tecto sao 8 lugares: 8100..8107. So que o
  # marcador, o treinador, o ajudante e o ajudante do outro vivem em
  # 8101..8104, dentro dessa mesma banda. Na pratica sobravam QUATRO lugares
  # para selvagens — e ninguem tinha dado por isso porque a arena nunca pediu
  # mais do que quatro ao mesmo tempo.
  #
  # A caverna pede trinta. Tem banda propria, comecada bem acima e larga o
  # suficiente para nunca esbarrar em nada.
  # ⚠️ O SEGUNDO MARCADOR EXISTE PORQUE UMA ANIMACAO TEM DUAS PONTAS.
  #
  # O `ID_MARCADOR` ancora o ALVO num ponto do chao. Faltava o par: ancorar
  # QUEM LANCA num ponto do chao. Sem ele, quando o boneco do atacante nao esta
  # na lista de peers, a ponta de partida caia no valor por omissao — o
  # `$game_player` — e o golpe do outro era desenhado a sair do MEU Pokemon.
  #
  # Fica em 8199 e nao em 8105: e o ultimo numero antes da banda da caverna, e
  # assim nao ha maneira de esbarrar nos trinta habitantes.
  ID_MARCADOR2 = 8199   # ancora de PARTIDA num ponto do chao
  # ⚠️ ESTE TECTO E UMA BANDA DE IDS, E ELA TEM DE CHEGAR PARA O MAIOR MAPA.
  #
  # O 60 foi medido contra a caverna, que tem 30 habitantes — o dobro, de
  # folga. O safari tem 55, e 60 deixava de ser folga para passar a ser um
  # limite a um passo de ser atingido: bastava um corpo por apagar ou um bicho
  # a mais para o `id_de_bicho_livre` devolver nil e o habitante seguinte nao
  # nascer, em silencio.
  #
  # 8200 a 8319 nao choca com nada: o que esta reservado acaba no 8199.
  ID_CAVERNA   = 8200
  MAX_CAVERNA  = 120
  FRAMES_TICK  = 1
  ALCANCE_LINHA = 5     # casas de um golpe especial
  RAIO_AREA     = 2     # casas de um golpe de area
  RECARGA_BASE  = 40    # frames entre golpes (60 = 1 segundo)
  IA_CADENCIA   = 24    # frames entre decisoes da IA
  # Frames que um golpe a distancia demora a chegar. E o mesmo valor que a
  # animacao usa para o segundo tempo, para o impacto bater certo com o que
  # se ve. Subir isto da mais tempo para desviar.
  ATRASO_VIAGEM = 12

  # ⚠️ Input::A NAO E A TECLA "A".
  #
  # No RGSS as constantes sao nomes de BOTAO de comando, nao de tecla: o
  # `Input::A` e o Shift, o `Input::C` e o Enter/Espaco, e as teclas A, S e D do
  # teclado sao o `Input::X`, `Input::Y` e `Input::Z`. Eu rotulei os golpes com
  # os nomes das constantes e o jogador carregou nas teclas com esse nome — que
  # sao outras. Nada acontecia, e parecia que os golpes nao funcionavam.
  #
  # Agora o rotulo e a TECLA que se carrega, que e a unica coisa que interessa a
  # quem esta a jogar. No JoiPlay sao os botoes A, S, D e Z do teclado no ecra.
  #
  # O `Input::C` ficou de fora de proposito: e o botao de falar com eventos, e
  # atacar em cima de um NPC abria a conversa dele a meio da luta.
  TECLAS = [
    [:X, "A"],       # tecla A
    [:Y, "S"],       # tecla S
    [:Z, "D"],       # tecla D
    [:A, "Shift"]    # Shift
  ].freeze

  module_function

  def log(t)
    AnilLanRework.log("[ARENA] #{t}") rescue nil
    registar(t)
  end

  # ⚠️ FICHEIRO PROPRIO, E SEM O INTERRUPTOR DE DIAGNOSTICO.
  #
  # O log global esta desligado (e nem se pode ligar: trava o "recuperar
  # partida"), e as mensagens do painel apagam-se umas as outras — o
  # diagnostico do golpe era escrito por cima pelo "errou!" na linha seguinte.
  # Enquanto a arena e um prototipo, escreve-se sempre, com tecto de linhas para
  # nao crescer sem fim.
  MAX_LINHAS_LOG = 400

  # ⚠️ DESLIGADO, E ISTO E UMA DECISAO E NAO UM ESQUECIMENTO.
  #
  # O diagnostico valeu o que custou: foi assim que se apanhou a gravacao do
  # save a correr dentro do frame, o `alcance` de 2,2 casas do Wing Attack e o
  # modo do editor a nao chegar a IA. Nenhuma dessas se via a olho.
  #
  # Mas ele nao e de graca. Mesmo com a escrita juntada em memoria, cada linha
  # custa a interpolacao da string ANTES de `registar` ser chamado — e num
  # feixe isso acontece a cada tique. O trabalho esta feito; a partir daqui so
  # paga.
  #
  # As chamadas ficam todas onde estao. Voltar a ligar e mudar isto para `true`
  # e recompilar — e no dia em que aparecer outro sintoma esquisito, e o
  # primeiro sitio a que se volta.
  LOG_LIGADO = false

  # ⚠️ ABRIR UM FICHEIRO A MEIO DO FRAME E O QUE TRAVA O JOGO.
  #
  # Isto abria e fechava o `anil_arena.txt` A CADA CHAMADA. Uma chamada nao se
  # sente; o problema e que um golpe nao faz uma — faz um punhado, todas dentro
  # do mesmo frame:
  #
  #     golpe ...            1
  #     tocar: OK ...        1 por animacao (uma onda solta uma dezena)
  #     lancou ...           1 por particula lancada
  #     feixe desenha para   1 por QUADRO enquanto o feixe estiver a sair
  #
  # E o tecto de 400 linhas nao salvava nada, porque o contador e posto a zero
  # no arranque de cada arena (`@linhas_log = 0`): todas as batalhas comecam com
  # o orcamento cheio outra vez. Daí o "rodava liso" — rodava, ate se comecar a
  # lutar a serio.
  #
  # Passa a juntar em memoria e a despejar tudo de uma vez, no maximo de dois em
  # dois segundos. O mesmo texto, o mesmo ficheiro, o mesmo tecto — mas uma
  # abertura de disco em vez de trinta, e nunca no frame em que o golpe sai.
  ESPERA_LOG = 2.0

  def registar(texto)
    return unless ACTIVO && LOG_LIGADO
    @linhas_log = (@linhas_log || 0) + 1
    return if @linhas_log > MAX_LINHAS_LOG
    (@fila_log ||= []) << "[#{Time.now.strftime('%H:%M:%S')}] #{texto}"
    agora = Time.now.to_f
    @log_ate ||= 0.0
    return if agora < @log_ate && @fila_log.length < 60
    @log_ate = agora + ESPERA_LOG
    despejar_log!
  rescue
    nil
  end

  def despejar_log!
    return unless LOG_LIGADO
    return if @fila_log.nil? || @fila_log.empty?
    linhas = @fila_log
    @fila_log = []
    File.open("Data/anil_arena.txt", "a:UTF-8") { |fh| fh.puts(linhas) }
  rescue
    nil
  end

  # ⚠️ O BONECO DO JOGADOR VAI DENTRO DO SAVE.
  #
  # O `@charset` da arena e uma variavel minha e morre quando o jogo fecha. Mas o
  # `character_name` do `$game_player` e estado do jogo e e GRAVADO: se o save
  # automatico apanhar o jogador a meio de uma batalha direta, ele volta a
  # carregar como Pokemon. Nada o corrige sozinho, porque o `refresh_charset` so
  # corre quando alguma coisa muda (correr, andar de bicicleta, surfar) — foi por
  # isso que o Z de correr "resolvia".
  #
  # Aqui, uma vez por arranque e por mapa, pergunta-se: nao estou na arena e o
  # meu boneco e um `Followers/...`? Entao isto e restolho de uma sessao
  # anterior; o proprio motor sabe recalcular o boneco certo.
  def reparar_boneco!
    return if @activa
    return unless $game_player && $game_map
    chave = ($game_map.map_id rescue 0)
    return if @reparado == chave
    @reparado = chave
    nome = ($game_player.character_name.to_s rescue "")
    return unless nome.downcase.start_with?("followers/")
    ($game_player.refresh_charset rescue nil)
    (AnilArenaIntrusos.anotar(:boneco_do_jogador_reposto, nome) rescue nil)
    log("boneco de Pokemon restolhado de uma sessao anterior: reposto")
  rescue
    nil
  end

  def activa?;         @activa == true;  end

  # ⚠️ O MODO EM QUE O JOGADOR NAO E O POKEMON.
  #
  # A batalha directa troca-me pelo bicho: eu passo a ser ele, eu e que ataco.
  # Este e o contrario — eu continuo eu, ando como sempre andei, e quem luta e
  # ele. Tudo o que na directa e meu (o boneco, as teclas de golpe, a barra de
  # vida) aqui nao existe, e por isso a maior parte das guardas deste ficheiro
  # perguntam por isto antes de mexerem no jogador.
  def automatica?;     @auto == true;    end
  # Um duelo e uma arena contra OUTRO JOGADOR. E a unica em que o seguidor
  # estorva (ver o entrar!), e por isso a unica que o esconde na rede.
  def duelo?;          @activa == true && !@pvp_id.nil?; end
  def meu_pokemon;     @meu;             end
  def charset_jogador; @charset;         end
  def pvp?;            !@pvp_id.nil?;    end

  # ⚠️ A CAVERNA E UMA ARENA COM OUTRAS REGRAS, E O 189 SO PRECISA DE SABER
  # QUAIS.
  #
  # Duas coisas mudam la dentro: nao se apanha nada, e quem cai cai a serio (em
  # vez de ficar grogue a espera da bola). Ambas se decidem aqui, num sitio so,
  # e com o MOD 192 ausente isto e sempre falso — a arena de sempre nao muda um
  # bocadinho que seja.
  def caverna?
    defined?(AnilRaidCaverna) && AnilRaidCaverna.dentro?
  rescue
    false
  end

  #-----------------------------------------------------------------------------
  # ARENA CONTRA OUTRO JOGADOR
  #
  # ⚠️ QUEM DECIDE QUE FOI ATINGIDO E A VITIMA, E SO ELA.
  #
  # Este e o unico ponto de desenho que importa no PvP em tempo real, e a razao
  # de ele ser simples aqui e ter sido um pesadelo no coop.
  #
  # Com latencia, os dois clientes veem posicoes diferentes: eu vejo-te uma casa
  # atras de onde tu te ves. Se cada um calculasse os acertos do SEU lado, os
  # dois acertavam e ninguem levava — ou pior, cada um contava uma historia
  # diferente do mesmo combate.
  #
  # A regra e: quem ataca so ANUNCIA o golpe (qual, de onde, para onde). Quem
  # leva e que confere, na SUA posicao, se aquilo o apanha; se apanhar, tira-se
  # a si proprio a vida e diz quanto ficou. O atacante limita-se a acreditar.
  #
  # Isto torna a batota possivel — um cliente adulterado pode recusar todos os
  # golpes. Para uma arena de diversao sem premios e o preco certo: elimina o
  # desync por completo, que e o defeito que estraga o jogo para toda a gente.
  # Se um dia a arena der recompensas, isto tem de mudar para o servidor.
  #-----------------------------------------------------------------------------
  def adversario_remoto
    return nil unless @pvp_id
    (AnilLanRework.players[@pvp_id.to_s] rescue nil)
  end

  # ⚠️ NA CAVERNA NAO HA ADVERSARIO: HA QUEM LA ESTIVER.
  #
  # O `enviar!` do duelo escreve a UMA pessoa, a do `@pvp_id`. Na caverna nao
  # existe esse par — sao dois, tres, os que entraram, e um golpe atinge quem
  # estiver no caminho, seja quem for.
  #
  # Sem `to_id`, mas com `map_id`/`x`/`y`, o servidor entrega o pacote a toda a
  # gente que esta naquele mapa a menos de 25 casas. Isto ja existia e nao
  # precisa de uma linha do lado do servidor: o mapa da caverna e o 303 para
  # todos, e por isso todos partilham a mesma instancia.
  #
  # A regra da arena mantem-se INTEIRA: isto anuncia um golpe, nao aplica
  # nenhum. Quem decide se levou continua a ser quem esta a levar.
  def anunciar_na_caverna!(dados)
    return unless caverna?
    return unless (AnilLanRework.connected? rescue false)
    # ⚠️ QUEM EU CONSIDERO AMIGO VIAJA NO PACOTE.
    #
    # Sem isto a alianca dependia de os DOIS lados terem o grupo registado no
    # mesmo instante. Se um deles ainda nao tinha (o pacote do grupo chegou
    # tarde, o peer foi removido e reinserido na mudanca de mapa), esse batia
    # no outro — e a briga comecava por um lado so, que e a pior maneira de
    # isto falhar.
    #
    # Declarando-o, basta que UM dos dois saiba: quem leva ve escrito no pacote
    # que o atacante o tem por amigo e recusa o golpe na mesma.
    AnilLanRework.connection.send_packet("caverna_golpe",
      dados.merge("caverna" => true,
                  "map_id"  => $game_map.map_id,
                  "amigo_de" => (AnilRaidCaverna.amigo_id rescue nil)).reject { |_k, val| val.nil? })
  rescue => e
    registar("falha a anunciar na caverna: #{e.class}: #{e.message}")
  end

  # ⚠️ NA CAVERNA NEM TODA A GENTE E INIMIGO: O PARCEIRO DE COOP NAO E.
  #
  # A regra da caverna e "quem la estiver e inimigo", e faz sentido para quem
  # se encontra la por acaso. Duas pessoas que entraram JUNTAS, em coop, sao
  # outra coisa — entrar de maos dadas e comecar a bater um no outro seria uma
  # armadilha, nao uma regra.
  #
  # O parceiro nao se adivinha por proximidade nem por nome: o multiplayer ja
  # sabe quem e (`coop_party_partner_id`), e e a mesma fonte que o mapa
  # partilhado e a troca usam. Sem coop nao ha parceiro, e a caverna volta a
  # ser de todos contra todos.
  # ⚠️ QUEM SABE E A CAVERNA, PORQUE FOI ELA QUE ANOTOU A PORTA.
  #
  # Isto lia o `coop_party_partner_id` no instante do golpe — e esse valor
  # atravessa uma mudanca de mapa e uma remocao e reinsercao do peer na lista.
  # Bastava um desses passos cair no momento errado para dois parceiros se
  # baterem. Agora pergunta-se ao MOD 192, que guardou o grupo a entrada e nao
  # o larga enquanto se la estiver.
  def coop_amigo?(id)
    return false if id.nil?
    return (AnilRaidCaverna.amigo?(id) rescue false) if defined?(AnilRaidCaverna)
    pid = (AnilLanRework.coop_party_partner_id rescue nil)
    return false if pid.nil? || pid.to_s.empty?
    pid.to_s == id.to_s
  rescue
    false
  end

  # O atacante disse, no proprio pacote, que o parceiro dele sou eu.
  def amizade_declarada?(pacote)
    dele = pacote["amigo_de"]
    return false if dele.nil? || dele.to_s.empty?
    dele.to_s == (AnilLanRework.self_internal_id.to_s rescue "")
  rescue
    false
  end

  # Quem mandou o pacote, para lhe tocar a animacao e para o empurrao saber de
  # que lado veio. No duelo e sempre o mesmo; aqui vem escrito no pacote.
  def quem_mandou(pacote)
    id = pacote["sender_id"].to_s
    return nil if id.empty?
    (AnilLanRework.players[id] rescue nil)
  rescue
    nil
  end

  def enviar!(tipo, dados = {})
    return unless @pvp_id
    return unless (AnilLanRework.connected? rescue false)
    AnilLanRework.connection.send_packet(tipo, dados.merge("to_id" => @pvp_id.to_s))
  rescue => e
    registar("falha a enviar #{tipo}: #{e.class}: #{e.message}")
  end

  #-----------------------------------------------------------------------------
  # ENTRAR E SAIR
  #-----------------------------------------------------------------------------
  def entrar!(pkmn, inimigo, pvp_id = nil)
    return false unless pkmn && inimigo
    # ⚠️ UMA LISTA VAZIA E UM MODO, NAO UM ERRO.
    #
    # Na batalha direta ninguem entra com adversario: os selvagens aparecem
    # depois, do mato, enquanto se anda. Passar `[]` e como se diz isso.
    lista = inimigo.is_a?(Array) ? inimigo.compact : [inimigo]
    return false if lista.empty? && !inimigo.is_a?(Array)
    inimigo = lista.first
    @activa   = true
    @pvp_id   = (pvp_id && !pvp_id.to_s.empty?) ? pvp_id.to_s : nil
    @meu      = pkmn
    @inimigo  = inimigo
    # ⚠️ Entra com a vida QUE TEM. Comecar sempre cheio, agora que a vida da
    # arena e escrita de volta na equipa, era uma cura de graca a cada
    # entrada — e a maneira mais facil de nunca precisar de um Centro.
    @hp_meu   = [(pkmn.hp.to_i rescue pkmn.totalhp), 1].max
    @hp_dele     = (inimigo ? inimigo.totalhp : 0)
    @hp_dele_max = (inimigo ? inimigo.totalhp : 1)
    @prontos = [0.0, 0.0, 0.0, 0.0]
    @ia_relogio = IA_CADENCIA
    @bola_pronta = 0.0
    @investida_pronta = 0.0
    @investida = nil
    @aliado = nil
    @buffs = {}
    @sem_bolas = false
    @avisou_shiny = nil
    @disse_lancar = false
    @shiny_visto_em = 0.0
    @prontos_ia = [0.0, 0.0, 0.0, 0.0]
    @ia_proximo = 0.0
    @energia_ia = ENERGIA_MAX
    @cansada_ia = false
    @mensagem = nil
    @mensagem_ate = 0
    @adiadas = []
    @impactos = []
    @lancamentos = []
    limpar_projecteis!
    @projecteis = []
    limpar_armadilhas!
    @flashes = {}
    @linhas_log = 0
    (File.delete("Data/anil_arena.txt") rescue nil)
    registar("=== arena: #{pkmn.speciesName} vs #{inimigo ? inimigo.speciesName : 'o mato'} ===")

    # ⚠️ Guarda-se o estado ANTES de mexer, e repoe-se sempre no sair!.
    # Sair a meio com o boneco de um Pikachu e um bug que so se nota depois.
    # ⚠️ E ISTO E O QUE SE REPOE A SAIDA — nao pode ser um Pokemon.
    #
    # Se o jogador ja entrou como Pokemon (restolho de uma sessao anterior),
    # guardar esse nome aqui fazia com que sair da arena o deixasse... Pokemon.
    # O `reparar_boneco!` acabava por o repor no mapa seguinte, mas so no mapa
    # seguinte — e ate la o jogador andava pelo mundo como um Venusaur.
    @charset_antigo = ($game_player.character_name.to_s rescue "")
    @charset_antigo = "" if @charset_antigo.downcase.start_with?("followers/")
    @veloc_antiga   = ($game_player.move_speed rescue 4)

    # ⚠️ O TREINADOR TEM DE NASCER ANTES DE O BONECO MUDAR.
    #
    # Eu criava-o la mais abaixo, depois do `refresh_charset`, e nessa altura o
    # `character_name` ja era o do Pokemon — o evento ficava com um grafico
    # vazio ou errado e nao se via nada. Aqui em cima o jogador ainda e o
    # treinador, e le-se o boneco dele directamente.
    # ⚠️ NA CAVERNA NAO HA TREINADOR NO CAMPO.
    #
    # O corpo existe para dar a ler quem esta a comandar: o treinador fica
    # parado a ver, e o Pokemon luta. Numa caverna a rastejar de inimigos isso
    # e outra coisa — um segundo boneco a seguir o jogador pelos corredores,
    # que nao luta, nao leva dano e estorva a passagem nas casas estreitas. Foi
    # o que se viu: "o personagem esta a seguir-me".
    travar_gravacoes!
    travar_gravacoes!
    # ⚠️ NA AUTOMATICA NAO SE CRIA CORPO NENHUM.
    #
    # O `criar_corpo!` existe para a directa: como eu passo a ser o Pokemon,
    # fica um boneco do treinador para tras a marcar onde eu "estou" de
    # verdade. Aqui eu nunca deixo de ser o treinador, portanto um segundo
    # treinador no mapa seria so um estorvo a tapar a passagem.
    criar_corpo! unless pvp? || caverna? || automatica?

    # ⚠️ NAO SE ESCREVE O @character_name A MAO.
    #
    # O `Game_Player#refresh_charset` recalcula-o a partir da skin e do estado
    # (surf, bicicleta, mergulho) e corre sozinho a cada mudanca. Escrever o
    # valor por baixo funcionava ate ao proximo refresh e depois o Pokemon
    # voltava a ser o treinador, sem aviso. Quem manda e o gancho no proprio
    # metodo, instalado depois dos plugins.
    # ⚠️ E ISTO E O QUE FAZ O JOGADOR VIRAR POKEMON. NA AUTOMATICA, NAO VIRA.
    #
    # O gancho do `refresh_charset` le este `@charset`: com ele posto, o meu
    # boneco passa a ser o do bicho. E a batalha directa inteira num campo so.
    #
    # Deixando-o vazio, o motor recalcula o boneco a partir do estado normal
    # (a skin, o surf, a bicicleta) e eu continuo o treinador — que e a
    # diferenca entre os dois modos.
    @charset = automatica? ? nil : caminho_do_sprite(pkmn)
    @veloc_base = velocidade_para_passo(pkmn)
    @vel_livre = velocidade_livre(pkmn)
    # Entrar a meio de um passo deixava o motor a puxar o boneco para a casa
    # seguinte enquanto o movimento livre o puxava para outro lado.
    ($game_player.instance_variable_set(:@move_timer, nil) rescue nil)
    @estado_dele = nil
    @energia = ENERGIA_MAX
    @estado = nil
    @a_correr = false
    @a_segurar = nil
    @escudo_ate = 0.0
    @espelho_ate = 0.0
    @segurar_desde = nil
    @segurar_travado = false
    @ultimo_tick = Time.now.to_f
    # ⚠️ A VELOCIDADE E O BONECO SAO DO POKEMON, E NA AUTOMATICA EU NAO SOU ELE.
    #
    # O `@veloc_base` sai do Pokemon que luta; aplica-lo ao jogador na directa
    # faz sentido (eu SOU ele) e aqui nao — eu ando ao meu passo. O
    # `refresh_charset` fica: ele recalcula o boneco certo a partir do estado,
    # e como na automatica o `@charset` e nil, ele devolve-me o treinador.
    $game_player.move_speed = @veloc_base unless automatica?
    ($game_player.refresh_charset rescue nil)

    # ⚠️ NAO VOLTAR A DEIXAR O SEGUIDOR DE PE. JA TENTEI, E FOI UM DESASTRE.
    #
    # O raciocinio errado era "contra selvagens o seguidor e o companheiro, faz
    # parte da cena". Nao faz: o seguidor do jogo E o `first_able_pokemon`, ou
    # seja, E EXACTAMENTE O POKEMON QUE O JOGADOR ESTA A CONTROLAR. Deixa-lo
    # visivel na batalha directa desenha uma copia paralisada do proprio
    # lutador, plantada a frente do boneco e a olhar para ele.
    #
    # E piora: o `empurrar!` usa o `jump` do motor, e o sistema de seguidores
    # reposiciona-se a cada salto — cada golpe recebido cuspia mais uma copia.
    #
    # O movimento livre tambem nao mexe seguidores (nao passa pelo `move_*`),
    # portanto a copia fica parada no sitio enquanto tudo o resto anda.
    #
    # Esconde-se SEMPRE, em qualquer arena. A queixa do PVP resolve-se do lado
    # da rede (ver o campo "follower" no 000), nao aqui.
    (Followers.hide_followers rescue nil)

    # Contra outro jogador nao ha evento nenhum a criar: o adversario ja esta no
    # mapa, desenhado pelo sistema de jogadores, e o boneco de Pokemon dele
    # chega sozinho no `player_state` (o campo "char").
    unless pvp?
      apagar_inimigo!
      lista.each_with_index { |pk, i| criar_bicho!(pk, ID_INIMIGO + i, 4 + i) }
      actualizar_foco!
    end
    criar_hud!
    log("entrou: #{pkmn.speciesName} vs #{inimigo ? inimigo.speciesName : 'selvagens'}")
    true
  rescue => e
    log("falha ao entrar: #{e.class}: #{e.message}")
    sair!
    false
  end

  #-----------------------------------------------------------------------------
  # GRAVAR NAO CABE DENTRO DE UM FRAME
  #
  # ⚠️ O `save_and_upload_save_file` SERIALIZA O JOGO E SOBE-O A REDE. A DIREITO.
  #
  # Fora da arena isso e invisivel: acontece entre ecrans, quando ja se esta a
  # espera de uma pausa. Aqui nao — aqui ha um laco a 60 por segundo com bonecos
  # a mover-se, e um save no meio dele e o jogo inteiro parado enquanto o disco
  # escreve e a rede responde. E um segundo, as vezes mais, e nao ha nada que
  # o esconda.
  #
  # E na batalha direta ha muitos motivos para gravar: apanhar um bicho, receber
  # um item, a vida da equipa a ser reescrita. O `AUTOSAVE_PISO_BATALHA` de 30 s
  # que protege as batalhas normais nao apanha isto, porque para o jogo isto NAO
  # e uma batalha — nao ha `Scene_Battle`, estamos no mapa, e o
  # `can_save_safely?` responde que sim.
  #
  # A masmorra ja resolve o mesmo problema no `192` (`travar_gravacoes!`), so
  # que la a gravacao e RECUSADA, e com razao: a equipa de la e uma simulacao e
  # nao pode chegar ao disco. Aqui e o contrario — o que se grava e verdadeiro e
  # tem de chegar la. So nao tem de chegar AGORA.
  #
  # Portanto: enquanto a arena corre, a gravacao e anotada e nao executada; ao
  # sair, faz-se uma, com o motivo que ficou pendente. O jogador nao perde nada
  # e o combate nao para.
  def travar_gravacoes!
    return if @gravacoes_travadas
    @gravacoes_travadas = true
    return unless defined?(AnilLanRework) &&
                  AnilLanRework.respond_to?(:save_and_upload_save_file)
    AnilLanRework.singleton_class.class_eval do
      unless method_defined?(:anil_arena_orig_subir_save)
        alias_method :anil_arena_orig_subir_save, :save_and_upload_save_file
        def save_and_upload_save_file(*args)
          # O fecho do jogo e a queda da ligacao nunca esperam por nada.
          motivo = args.first.to_s
          if (AnilArena.activa? rescue false) &&
             !["game_exit", "disconnect"].include?(motivo)
            (AnilArena.adiar_gravacao!(motivo) rescue nil)
            return false
          end
          anil_arena_orig_subir_save(*args)
        end
      end
    end
  rescue => e
    registar("falha a travar as gravacoes: #{e.class}: #{e.message}")
  end

  def adiar_gravacao!(motivo)
    @gravacao_adiada = (motivo.to_s.empty? ? "arena" : motivo.to_s)
    nil
  end

  def gravar_o_que_ficou!
    motivo = @gravacao_adiada
    @gravacao_adiada = nil
    return unless motivo
    return unless defined?(AnilLanRework) &&
                  AnilLanRework.respond_to?(:anil_arena_orig_subir_save)
    registar("gravacao adiada durante a arena; a fazer agora (#{motivo})")
    (AnilLanRework.anil_arena_orig_subir_save(motivo) rescue nil)
  rescue => e
    registar("falha a gravar o que ficou: #{e.class}: #{e.message}")
  end

  def sair!(texto = nil)
    limpar_spawns_do_mapa! if @directa || @caca
    encaixar_na_casa!
    dispensar_aliado!
    voltar_ao_corpo!
    apagar_corpo!
    @caca = false
    @directa = false
    @auto = false
    @treinador = nil
    gravar_o_que_ficou!
    @estado_dele = nil
    (@bitmaps_bola || []).each { |bm| (bm.dispose rescue nil) }
    @bitmaps_bola = []
    @derrota_ate = nil
    # ⚠️ E O ESTADO DE CAIDO TAMBEM SAI COM A ARENA.
    #
    # Sem isto, quem sai com o /arena sair enquanto estava caido levava o
    # `@caido_ate` para a proxima entrada — e nascia la dentro sem poder andar
    # nem bater, sem nada no ecra que explicasse porque. E o boneco ficava
    # inclinado, porque o `angle` do sprite nao volta ao zero sozinho.
    endireitar_caido! if @caido_ate
    @caido_ate = nil
    (AnilArenaRessurreicao.limpar! rescue nil)
    ($game_player.opacity = 255) rescue nil
    # A vez de quem ataca nao sobrevive a arena: ao voltar, escolhe-se de novo.
    # Avisa-se o outro antes de sair, senao fica com a minha sombra no mapa.
    (enviar!("arena_parceiro", "fora" => true) rescue nil) if pvp?
    apagar_parceiro!
    @parceiro_avisado = nil
    @agressor = nil
    @agressor_ate = nil
    @pausa_ia_ate = nil
    @feixe_alvo = nil
    @feixe_rumo = nil
    @feixe_alcance = nil
    @feixe_dano = []
    limpar_sementes!
    limpar_efeitos_do_corpo!
    largar_escudo!
    apagar_clone!
    encerrar_captura!
    limpar_desmaios!
    limpar_flutuantes!
    @imune_ate = 0.0
    (@bmp_botoes.dispose rescue nil) if @bmp_botoes && !(@bmp_botoes.disposed? rescue true)
    @bmp_botoes = nil
    (@bmp_folha_bola.dispose rescue nil) if @bmp_folha_bola && !(@bmp_folha_bola.disposed? rescue true)
    @bmp_folha_bola = nil
    (@bmps_ui || {}).each_value { |bm| (bm.dispose rescue nil) if bm }
    @bmps_ui = {}
    @cartoes_bola = {}
    limpar_armadilhas!
    limpar_animacoes!
    apagar_inimigo!
    apagar_marcador!
    apagar_hud!
    (Followers.put_followers_on_player rescue nil)
    if @activa
      ($game_player.move_speed = (@veloc_antiga || 4)) rescue nil
      sp = sprite_de($game_player)
      (sp.color.set(0, 0, 0, 0) rescue nil) if sp
      @estado = nil
      @a_correr = false
      @a_segurar = nil
      @activa  = false   # antes do refresh, senao o gancho volta a por o Pokemon
      @charset = nil
      ($game_player.refresh_charset rescue nil)
    end
    @activa = false
    @pvp_id = nil
    @adiadas = []
    @impactos = []
    @meu = nil
    @inimigo = nil
    @charset = nil
    pbMessage(texto) rescue nil if texto
    log("saiu")
  rescue => e
    log("falha ao sair: #{e.class}: #{e.message}")
  end

  # O follower da especie; se nao houver, o do numero; em ultimo caso o proprio
  # boneco do treinador, para nunca ficar invisivel.
  def caminho_do_sprite(pkmn)
    if defined?(AnilLanRework::ReleasedRoaming)
      c = (AnilLanRework::ReleasedRoaming.resolve_pokemon_character_path(pkmn) rescue nil)
      return c if c && c != "ItemBall"
    end
    "Followers/#{pkmn.species}"
  rescue
    "Followers/#{pkmn.species}"
  end

  # Velocidade do Pokemon -> passo do overworld. O motor so tem escalao inteiro,
  # portanto isto e grosso de proposito: 3 (lento), 4 (normal), 5 (rapido).
  # ⚠️ O MOVIMENTO JA E CONTINUO. O QUE PARECIA SALTO ERA LENTIDAO.
  #
  # Eu tinha dito que andar ao pixel obrigava a reescrever o `update_move` e a
  # refazer a colisao. Estava desactualizado: isso era o RMXP antigo. O
  # Essentials v21 interpola:
  #
  #     @real_x = lerp(@move_initial_x, @x, @move_time * dist, @move_timer) * REAL_RES_X
  #
  # O boneco desliza entre casas ao longo do tempo — nao ha saltos de 32 px. O
  # `move_speed` traduz-se em SEGUNDOS POR CASA (`2.0 / 2**val`), e aceita
  # fraccoes. O que se sentia como "aos saltos" era o quarto de segundo que uma
  # casa demora a andar: tempo suficiente para o olho ver a paragem no fim de
  # cada uma.
  #
  # Encurtando esse tempo, a paragem desaparece — e sem tocar em colisoes,
  # eventos de toque ou seguidores, que era o que tornava a reescrita cara.
  #
  # ⚠️ E NAO SE USA 5 NEM 6 EXACTOS.
  #
  # A tabela do motor tem excepcoes escritas a mao para esses dois valores
  # (5 => 0.1, 6 => 0.05) que quebram a monotonia: 5.5 pela formula da 0.044,
  # ou seja MAIS RAPIDO que o 6. Ficar nas fraccoes evita essa armadilha.
  #
  #   4.0 -> 0.125 s por casa   (8 casas/s)   lento
  #   4.4 -> 0.095 s            (10,5/s)      normal
  #   4.8 -> 0.072 s            (14/s)        rapido
  def velocidade_para_passo(pkmn)
    v = (pkmn.speed.to_i rescue 100)
    return 4.8 if v >= 140
    return 4.0 if v <= 60
    4.4
  rescue
    4.4
  end

  #-----------------------------------------------------------------------------
  # O ADVERSARIO
  #-----------------------------------------------------------------------------
  #-----------------------------------------------------------------------------
  # OS BICHOS
  #
  # ⚠️ ERA UM INIMIGO SO PORQUE A ARENA COMECOU COMO UM DUELO.
  #
  # `@inimigo`, `@hp_dele`, um evento com um id fixo. Para cacar num mapa isso
  # nao serve: sao varios ao mesmo tempo, cada um com a sua vida, o seu folego,
  # as suas recargas e o seu estado. Agora ha uma lista, e cada bicho carrega
  # tudo o que era global.
  #
  # O `@inimigo`/`@hp_dele` continuam a existir como ESPELHO do bicho mais
  # proximo, actualizado a cada tick — e por isso o painel, o calculo de dano e
  # o PVP nao precisaram de saber que isto mudou.
  #-----------------------------------------------------------------------------
  MAX_BICHOS      = 8
  RAIO_EXPLOSAO   = 2.0    # casas atingidas por um golpe de area

  def bichos
    (@bichos ||= [])
  end

  # ⚠️ O `sid` E O NOME DO BICHO NA REDE, E O `id` E O NUMERO DO EVENTO.
  #
  # Os dois nao podem ser a mesma coisa: o id do evento e escolhido por cada
  # maquina (o primeiro livre a partir do `ID_INIMIGO`) e nao ha razao nenhuma
  # para bater certo entre duas. O `sid` vem de quem semeou e viaja no pacote —
  # e por ele que as duas maquinas sabem que estao a falar do mesmo Pokemon.
  # ⚠️ MUDAR DE ANDAR DEIXA A LISTA CHEIA DE FANTASMAS.
  #
  # Os eventos morrem com o mapa velho, mas a `bichos` e nossa e sobrevive: fica
  # com trinta fichas a apontar para eventos que ja nao existem. O foco escolhe
  # um deles, a IA tenta move-lo, e o andar novo nasce com trinta inimigos
  # invisiveis a competir com os verdadeiros.
  # ⚠️ ISTO LARGAVA A FICHA E DEIXAVA O BONECO NO MAPA.
  #
  # Era exactamente o "Pokemon presos no mapa como objectos". O metodo punha
  # `b[:ev] = nil` e limpava a lista — mas o EVENTO continuava em
  # `$game_map.events`, com sprite, com colisao, e sem ninguem para o mover:
  # a lista que a IA percorre e a `bichos`, e ele ja nao estava nela.
  #
  # Num handover de posse isto largava a populacao inteira de uma vez. O log
  # apanhou "larguei os meus 59 bichos" — cinquenta e nove estatuas a ocupar
  # corredores, para sempre, ate se sair do andar.
  #
  # Largar a autoridade sobre um bicho e largar o bicho: apaga-se o evento
  # ANTES de perder a referencia para ele, que e o unico momento em que ainda
  # se sabe qual e.
  def largar_bichos!
    quantos = bichos.length
    bichos.each do |b|
      next unless b
      apagar_evento_bicho!(b[:id]) if b[:id]
      b[:ev] = nil
    end
    bichos.clear
    esquecer_vivos!
    @agressor = nil
    @foco = nil
    quantos
  rescue
    0
  end

  def bicho_por_sid(sid)
    return nil if sid.nil?
    chave = sid.to_s
    bichos.find { |b| b[:sid].to_s == chave }
  rescue
    nil
  end

  def apagar_por_sid!(sid)
    b = bicho_por_sid(sid)
    return false unless b
    b[:morto] = true
    animar_desmaio!(b[:ev]) if b[:ev]
    apagar_evento_bicho!(b[:id])
    b[:ev] = nil
    b[:hp] = 0
    bichos.delete(b)
    esquecer_vivos!
    actualizar_foco!
    true
  rescue
    false
  end

  # A posicao que o dono da caverna manda. Escreve-se por cima do que a nossa
  # propria IA calculou: entre a nossa conta e a do dono, manda a do dono.
  #-----------------------------------------------------------------------------
  # OS HABITANTES DO SERVIDOR, DESENHADOS A 60 E NAO A 10
  #
  # ⚠️ ELES TREMIAM PORQUE ESTAVAM A SER TELEPORTADOS, DEZ VEZES POR SEGUNDO.
  #
  # O servidor manda um retrato a cada 100 ms, e isto punha o boneco exactamente
  # onde o retrato dizia. Entre dois retratos ele ficava PARADO, e depois dava
  # um salto de um quarto de casa de uma so vez. Seis frames quieto, um frame a
  # saltar, seis frames quieto — isso nao se le como andar devagar, le-se como
  # tremer.
  #
  # E nao e um defeito do servidor: dez retratos por segundo chegam e sobram
  # para dizer ONDE ele esta. O que faltava era desenhar o caminho ENTRE dois
  # retratos, que e trabalho de quem desenha. Guarda-se para onde ele vai e a
  # que velocidade tem de ir para la chegar antes do retrato seguinte, e depois
  # anda-se todos os frames — sessenta passos pequenos em vez de dez grandes.
  #
  # ⚠️ E UM SALTO GRANDE NAO SE INTERPOLA.
  #
  # Nascer, ressuscitar ou ser reposto depois de um pacote perdido mete o bicho
  # a dez casas de onde estava. Deslizar isso seria vê-lo atravessar o mapa a
  # voar por cima das paredes. Acima de um limite curto, poe-se onde deve estar
  # e pronto — que e o que o teleporte sempre fez, e para o que ele serve.
  INTERP_CAV    = 0.1     # segundos entre retratos do servidor
  INTERP_SALTO  = 2.0     # casas: acima disto nao se desliza
  INTERP_TECTO  = 9.0     # casas por segundo: o mais depressa que se desliza

  def pousar_por_sid!(sid, rx, ry, dir)
    b = bicho_por_sid(sid)
    return false unless b && b[:ev]
    ev = b[:ev]
    # A partir do primeiro retrato, este boneco e do servidor e a IA local nao
    # lhe toca mais.
    b[:do_servidor] = true
    ev.instance_variable_set(:@direction, dir.to_i) if dir.to_i > 0
    ax = (ev.instance_variable_get(:@real_x) rescue 0).to_f
    ay = (ev.instance_variable_get(:@real_y) rescue 0).to_f
    dx = rx.to_f - ax
    dy = ry.to_f - ay
    n = Math.sqrt((dx * dx) + (dy * dy))
    casas = n / Game_Map::REAL_RES_X.to_f
    if casas > INTERP_SALTO || casas < 0.004
      b[:ir_rx] = nil
      return plantar_bicho!(ev, rx, ry)
    end
    b[:ir_rx] = rx.to_f
    b[:ir_ry] = ry.to_f
    # A velocidade que o faz chegar mesmo a tempo do retrato seguinte. Com
    # tecto, para um pacote atrasado nao o disparar pelo mapa fora.
    v = n / INTERP_CAV
    tecto = INTERP_TECTO * Game_Map::REAL_RES_X
    b[:ir_vel] = (v > tecto) ? tecto : v
    true
  rescue
    false
  end

  def plantar_bicho!(ev, rx, ry)
    ev.instance_variable_set(:@real_x, rx.to_i)
    ev.instance_variable_set(:@real_y, ry.to_i)
    ev.instance_variable_set(:@x, (rx.to_f / Game_Map::REAL_RES_X).round)
    ev.instance_variable_set(:@y, (ry.to_f / Game_Map::REAL_RES_Y).round)
    (ev.calculate_bush_depth rescue nil)
    true
  rescue
    false
  end

  # O passo de cada frame em direccao ao ultimo retrato. Corre no tique, com os
  # outros movimentos, e so na masmorra — em mais lado nenhum ha bichos do
  # servidor.
  def correr_bichos_do_servidor!
    return unless caverna?
    dt = [(@delta || (1.0 / 60.0)), 0.1].min
    bichos.each do |b|
      ev = b[:ev]
      next unless ev && b[:ir_rx]
      rx = (ev.instance_variable_get(:@real_x) rescue 0).to_f
      ry = (ev.instance_variable_get(:@real_y) rescue 0).to_f
      dx = b[:ir_rx] - rx
      dy = b[:ir_ry] - ry
      n = Math.sqrt((dx * dx) + (dy * dy))
      if n < 1.0
        b[:ir_rx] = nil
        next
      end
      passo = b[:ir_vel].to_f * dt
      if passo >= n
        plantar_bicho!(ev, b[:ir_rx], b[:ir_ry])
        b[:ir_rx] = nil
      else
        plantar_bicho!(ev, rx + ((dx / n) * passo), ry + ((dy / n) * passo))
      end
      # As pernas tambem sao nossas: sem isto ele desliza sem dar um passo.
      animar_evento!(ev)
    end
  rescue
    nil
  end

  # ⚠️ TRINTA E UM SITIOS PEDEM ESTA LISTA, E ELA ERA REFEITA EM TODOS.
  #
  # Cada chamada percorre os bichos e constroi um array novo. Num frame de
  # combate isto e pedido pela IA, pela mira, pelo alcance do feixe, pelo teste
  # de area, pelo "vale a pena", pelo foco... facilmente dez vezes. Dez arrays
  # por frame, 600 por segundo, todos deitados fora a seguir — e o apanhador de
  # lixo do RGSS nao e de graca; e ele que se sente como um solavanco.
  #
  # A lista nao pode mudar a meio de um frame: nada morre nem nasce entre duas
  # linhas do mesmo tique. Portanto calcula-se uma vez e serve o frame todo.
  #
  # A chave e o numero do frame. Nao ha invalidacao a fazer a mao — no frame
  # seguinte o numero e outro e a lista refaz-se sozinha. Isso e de proposito:
  # um cache que e preciso lembrar de limpar acaba sempre por servir dados
  # velhos, e aqui isso seria um Pokemon morto a continuar a levar golpes.
  def bichos_vivos
    agora = (Graphics.frame_count rescue 0)
    return @vivos_cache if @vivos_frame == agora && @vivos_cache
    @vivos_frame = agora
    @vivos_cache = bichos.select { |b| b[:hp].to_i > 0 && b[:ev] }
  end

  # Quem mata ou faz nascer alguem dentro do frame chama isto. E o unico caso
  # em que a lista muda a meio, e sao poucos.
  def esquecer_vivos!
    @vivos_frame = nil
    @vivos_cache = nil
  end

  def bicho_focado
    vivos = bichos_vivos
    return nil if vivos.empty?
    vivos.min_by { |b| distancia_casas(b[:ev], $game_player) }
  end

  def bicho_do_evento(ev)
    return nil unless ev
    bichos.find { |b| b[:ev].equal?(ev) }
  end

  # O espelho. Corre no principio do tick, antes de tudo o resto olhar para ele.
  def actualizar_foco!
    b = bicho_focado
    return unless b
    @inimigo         = b[:pkmn]
    @hp_dele         = b[:hp]
    @hp_dele_max     = b[:hp_max]
    @estado_dele     = b[:estado]
    @estado_dele_ate = b[:estado_ate]
  rescue
    nil
  end

  # ⚠️ NAO SE ESCREVE DIRECTO NO `$game_map.events`. NUNCA.
  #
  # O Ruby proibe acrescentar uma chave a um Hash que esta a ser percorrido, e
  # o `Game_Map#update` percorre exactamente este:
  #
  #     @events.each_value { |event| event.update }
  #
  # Enquanto a arena nascia de um menu isto nunca deu problema — um menu corre
  # fora do laco. Mas a batalha de treinador nasce DE DENTRO do evento do
  # treinador, ou seja, no meio desse `each_value`. Resultado: todos os
  # `$game_map.events[id] = ev` rebentavam com
  #
  #     RuntimeError: can't add a new key into hash during iteration
  #
  # e nao nascia nada — nem os Pokemon dele, nem o ajudante, nem o marcador das
  # animacoes, nem o corpo do treinador (que por isso se "repunha" uma vez por
  # segundo, para sempre). Uma so causa, e o modo inteiro parecia partido.
  #
  # A saida nao e adiar: e nao tocar no hash que esta a ser lido. Faz-se uma
  # COPIA com o evento novo la dentro e troca-se a referencia. Quem esta a
  # percorrer continua a percorrer o antigo em paz ate ao fim do frame; do
  # frame seguinte em diante o mapa ja e o novo. (Apagar nao precisa disto —
  # o Ruby so se importa com chaves NOVAS.)
  def pousar_evento!(id, ev, rpg = nil)
    return false unless $game_map && ev
    actuais = ($game_map.events rescue nil)
    if actuais.is_a?(Hash)
      copia = actuais.dup
      copia[id] = ev
      $game_map.instance_variable_set(:@events, copia)
    end
    if rpg
      dados = ($game_map.instance_variable_get(:@map) rescue nil)
      if dados && dados.respond_to?(:events) && dados.events.is_a?(Hash)
        copia = dados.events.dup
        copia[id] = rpg
        begin
          dados.events = copia
        rescue
          # Se o objecto do mapa nao deixar trocar a referencia, escreve-se a
          # chave — este hash nao e o que o motor percorre a cada frame.
          (dados.events[id] = rpg) rescue nil
        end
      end
    end
    true
  rescue => e
    log("falha a pousar o evento #{id}: #{e.class}: #{e.message}")
    false
  end

  # ⚠️ QUEM SABE A CASA DIZ A CASA — E NAO NASCE NOUTRA PARA DEPOIS SE MUDAR.
  #
  # Quando o bicho vem da rede, a casa ja esta decidida pelo dono da caverna.
  # Eu criava-o na casa livre mais perto de QUEM RECEBE e mudava-o a seguir
  # para o sitio certo: um frame ao pe do jogador, o seguinte longe. Lido no
  # ecra, isso e um Pokemon a piscar e a desaparecer, que foi o que se
  # descreveu.
  def criar_bicho!(pkmn, id, longe = 4, minimo = 1, casa = nil)
    return nil unless $game_map && $game_player && pkmn
    if casa
      x, y = casa
    else
      x, y = casa_livre_perto($game_player.x, $game_player.y, longe, minimo)
      # Se a distancia minima nao couber (um corredor fechado, um canto), vale
      # mais nascer perto do que nao nascer de todo.
      x, y = casa_livre_perto($game_player.x, $game_player.y, longe) unless x
    end
    return nil unless x

    rpg = RPG::Event.new(x, y)
    rpg.id   = id
    rpg.name = "ArenaInimigo"
    pag = rpg.pages[0]
    pag.graphic.character_name = caminho_do_sprite(pkmn)
    pag.graphic.character_hue  = (pkmn.super_shiny_hue.to_i rescue 0)
    pag.trigger    = -1        # nunca dispara sozinho: quem manda e o tick
    # ⚠️ O `step_anime` BRIGA COM O `parar_evento!`, E O QUE SE VE E UM TREMOR.
    #
    # Com `step_anime = true`, o `Game_Character#update` do motor avanca o
    # `@pattern` a CADA frame, ande o boneco ou nao. O `parar_evento!` repoe o
    # padrao de descanso. Os dois correm no mesmo frame, um a seguir ao outro,
    # para sempre: o motor adianta, nos repomos, o motor adianta. O sprite
    # salta entre dois desenhos sessenta vezes por segundo — e isso le-se como
    # um boneco a tremer, nao como um boneco parado.
    #
    # Nao e preciso: o `animar_evento!` ja move as pernas a mao, e so e chamado
    # quando o boneco anda mesmo. Desligar o `step_anime` tira o motor da
    # equacao e deixa uma so mao a mandar no padrao.
    pag.step_anime = false    # o `animar_evento!` e que move as pernas
    pag.move_type  = 0
    pag.through    = false
    pag.list = [RPG::EventCommand.new(0, 0, [])]

    ev = Game_Event.new($game_map.map_id, rpg, $game_map)
    # ⚠️ SEM ISTO O BRILHO NUNCA APANHA UM BICHO DA ARENA.
    #
    # O `Sprite_Character` decide se desenha as estrelas assim:
    #
    #     if !is_shiny && @character.respond_to?(:pokemon)
    #       pk = @character.pokemon
    #       ... pk.super_shiny? / pk.shiny?
    #
    # Ou seja, ele PERGUNTA ao boneco que Pokemon e que ele traz. Os spawns do
    # mundo sao `Game_PokeEvent` e sabem responder; os da arena sao eventos
    # feitos a mao e nao sabem — portanto nenhum bicho criado por nos alguma vez
    # brilhou, por mais shiny que fosse. Os chefes da masmorra levavam o matiz
    # no charset (isso passa pelo `character_hue`) e nao levavam estrela
    # nenhuma, que e a metade que se ve ao longe.
    #
    # Uma linha: o evento passa a responder a pergunta. Nao se herda nada nem se
    # toca no motor — so se acrescenta o acessor que ele procura.
    (ev.define_singleton_method(:pokemon) { pkmn } rescue nil)
    pousar_evento!(id, ev, rpg)
    ev.move_speed = velocidade_para_passo(pkmn)
    ev.refresh
    (AnilLanRework::ReleasedRoaming.sync_sprite(ev) rescue nil) if $scene.is_a?(Scene_Map)

    bicho = {
      :pkmn => pkmn, :hp => pkmn.totalhp, :hp_max => pkmn.totalhp,
      :id => id, :ev => ev,
      :estado => nil, :estado_ate => 0.0, :estado_tique => 0.0,
      :energia => ENERGIA_MAX, :cansada => false,
      :prontos => [0.0, 0.0, 0.0, 0.0], :proximo => 0.0, :passo => 0.0
    }
    bichos << bicho
    esquecer_vivos!
    bicho
  rescue => e
    log("falha a criar bicho: #{e.class}: #{e.message}")
    nil
  end

  def criar_inimigo!(pkmn)
    apagar_inimigo!
    criar_bicho!(pkmn, ID_INIMIGO)
  end

  # ⚠️ QUEM ANDA E O POKEMON; O TREINADOR FICA ONDE ESTAVA.
  #
  # Ate agora o boneco do jogador VIRAVA o Pokemon e o treinador desaparecia do
  # mundo — o que se lia como "transformei-me", e nao como "mandei o meu Pokemon
  # lutar". Sao coisas diferentes e a segunda e a que faz sentido.
  #
  # O truque e simples: o `$game_player` continua a ser quem se mexe (a camara,
  # a colisao e os passos ja sabem trabalhar com ele) mas usa o boneco do
  # Pokemon; e no sitio onde a batalha comecou fica um evento com o boneco do
  # treinador, parado, a ver. No fim o Pokemon volta para junto dele.
  def criar_corpo!
    return unless $game_map && $game_player
    apagar_corpo!
    # Le-se do jogador AGORA — e nao da variavel — porque e o unico momento em
    # que ele ainda esta com o boneco do treinador.
    # ⚠️ AQUI NASCIA A "ESTATUA": UM SEGUNDO POKEMON IGUAL AO MEU, PARADO.
    #
    # Este corpo e o treinador — o boneco que marca onde eu "estou" de verdade
    # enquanto ando pelo mapa como Pokemon. O comentario acima diz que se le do
    # jogador AGORA "porque e o unico momento em que ele ainda esta com o boneco
    # do treinador". Isso e verdade quando se entra na arena de fresco.
    #
    # Nao e verdade quando o `character_name` do jogador JA e um `Followers/...`
    # — e isso acontece mais do que parece. O proprio `reparar_boneco!`, ali em
    # cima, existe por causa disso: o `character_name` e estado GRAVADO, e um
    # autosave apanhado a meio de uma batalha directa traz o jogador de volta
    # como Pokemon. Basta tambem re-entrar na arena antes de o `refresh_charset`
    # ter corrido.
    #
    # Nesse caso o corpo nascia com o sprite do MEU Pokemon. E como ele so vem
    # atras de mim a partir de `CORPO_SEGUE` (cinco casas), o que se ve e um
    # clone meu parado no sitio — e, quando um golpe me atira para tras, ele
    # fica exactamente onde eu levei o golpe. Que e, palavra por palavra, o que
    # foi descrito.
    #
    # A cura e a mesma do `reparar_boneco!`: manda-se o motor recalcular o
    # boneco, com o `@charset` limpo para o gancho nao voltar a por o Pokemon
    # por cima. E no fim ha uma ultima rede — se AINDA vier um `Followers/`,
    # usa-se o boneco de treinador por omissao. Um treinador errado nota-se e
    # corrige-se; um clone do jogador parado no mapa le-se como o jogo partido.
    # ⚠️ "COMECA POR Followers/" NAO E A PERGUNTA CERTA, E EU JA TINHA A CERTA
    # A MAO.
    #
    # O `caminho_do_sprite` — que e quem escolhe o boneco de Pokemon do jogador
    # — so cai no `"Followers/#{especie}"` COMO ULTIMO RECURSO:
    #
    #     c = AnilLanRework::ReleasedRoaming.resolve_pokemon_character_path(pkmn)
    #     return c if c && c != "ItemBall"
    #     "Followers/#{pkmn.species}"
    #
    # Havendo um boneco proprio registado para aquela especie, o caminho nao
    # comeca por `Followers/` — e o teste deixava passar. O corpo nascia com o
    # MEU Pokemon, e como ele so vem atras de mim a partir de cinco casas, o que
    # fica e um clone meu parado onde a luta comecou. Assim que um golpe me
    # atira para longe, ve-se: "fica um clone do meu pokemon no local".
    #
    # Eu ja sei qual e o boneco do Pokemon — e o `@charset`, que fui eu que la
    # pus. Comparar com ele responde a pergunta de verdade ("este nome e o do
    # Pokemon?") em vez de a uma aproximacao dela.
    e_do_pokemon = lambda do |n|
      t = n.to_s
      next true if t.empty?
      next true if t.downcase.start_with?("followers/")
      next true if !@charset.to_s.empty? && t == @charset.to_s
      false
    end
    nome = ($game_player.character_name.to_s rescue "")
    if e_do_pokemon.call(nome)
      guardado = @charset
      @charset = nil
      ($game_player.refresh_charset rescue nil)
      nome = ($game_player.character_name.to_s rescue "")
      @charset = guardado
      registar("o corpo ia nascer com o boneco do Pokemon; boneco recalculado")
    end
    nome = "" if e_do_pokemon.call(nome)
    nome = @charset_antigo.to_s if nome.empty?
    nome = "" if e_do_pokemon.call(nome)
    nome = "trchar000" if nome.empty?
    @corpo_charset = nome
    @corpo_x = $game_player.x
    @corpo_y = $game_player.y
    @corpo_dir = ($game_player.direction rescue 2)

    rpg = RPG::Event.new(@corpo_x, @corpo_y)
    rpg.id   = ID_CORPO
    # ⚠️ UM EVENTO PARADO E SEM "UPDATE" NO NOME NAO E DESENHADO.
    #
    # Eu ja tinha tropecado nisto com o evento marcador e escrevi a nota — e
    # voltei a cair no mesmo buraco. O `Sprite_Character#update` desiste logo:
    #
    #     return if @character.is_a?(Game_Event) && !@character.should_update?
    #
    # e o `should_update?` (0051:245) so devolve true para quem se mexeu no
    # frame anterior, tem gatilho 3/4, esta a ser forcado a andar... ou tem a
    # palavra "update" no nome. Os selvagens passam porque andam; o treinador
    # ficava parado, e por isso nunca chegava a haver sprite. Nao e que ele
    # estivesse escondido: e que ninguem o desenhava.
    rpg.name = "ArenaTreinadorUpdate"
    pag = rpg.pages[0]
    pag.graphic.character_name = nome
    pag.graphic.direction = @corpo_dir
    pag.trigger    = -1
    pag.move_type  = 0
    # ⚠️ O `step_anime` BRIGA COM O `parar_evento!`, E O QUE SE VE E UM TREMOR.
    #
    # Com `step_anime = true`, o `Game_Character#update` do motor avanca o
    # `@pattern` a CADA frame, ande o boneco ou nao. O `parar_evento!` repoe o
    # padrao de descanso. Os dois correm no mesmo frame, um a seguir ao outro,
    # para sempre: o motor adianta, nos repomos, o motor adianta. O sprite
    # salta entre dois desenhos sessenta vezes por segundo — e isso le-se como
    # um boneco a tremer, nao como um boneco parado.
    #
    # Nao e preciso: o `animar_evento!` ja move as pernas a mao, e so e chamado
    # quando o boneco anda mesmo. Desligar o `step_anime` tira o motor da
    # equacao e deixa uma so mao a mandar no padrao.
    pag.step_anime = false    # o `animar_evento!` e que move as pernas
    pag.through    = true     # nao se tropeca no proprio treinador
    pag.list = [RPG::EventCommand.new(0, 0, [])]

    ev = Game_Event.new($game_map.map_id, rpg, $game_map)
    ev.through = true
    pousar_evento!(ID_CORPO, ev, rpg)
    ev.refresh
    (ev.instance_variable_set(:@direction, @corpo_dir) rescue nil)
    (AnilLanRework::ReleasedRoaming.sync_sprite(ev) rescue nil) if $scene.is_a?(Scene_Map)
  rescue => e
    log("falha a deixar o treinador: #{e.class}: #{e.message}")
  end

  # ⚠️ UM EVENTO POSTO A MAO NAO E DONO DA SUA PROPRIA VIDA.
  #
  # Uma mudanca de pagina, um refresh do mapa ou a sincronizacao de eventos do
  # multijogador podem varre-lo. Em vez de descobrir qual foi, confere-se de
  # segundo a segundo se ele ainda la esta e repoe-se — custa uma consulta a um
  # hash e o treinador deixa de sumir.
  # ⚠️ UM TREINADOR PLANTADO NO SITIO E UM TREINADOR PERDIDO.
  #
  # Ele ficava exactamente onde a luta comecou; ao fim de meia rota estava tao
  # longe que voltar para falar com ele era uma caminhada. Um treinador segue o
  # seu Pokemon — de longe, sem se meter no meio, e sem correr: oito casas atras
  # e perto o suficiente para se ir la encerrar a luta, e longe o suficiente
  # para nao aparecer nas animacoes.
  CORPO_SEGUE   = 5.0    # casas: a partir daqui ele vem atras (era 7)
  CORPO_VELOC   = 3.4    # casas por segundo: um passo tranquilo

  # ⚠️ QUEM PARA VOLTA AO QUADRO DE PE.
  #
  # Eu avanço o `@pattern` a mao enquanto o boneco anda, mas nunca o repunha ao
  # parar: ele ficava congelado com uma perna no ar, no quadro em que calhou. O
  # motor faz isto sozinho no `update_pattern` (`@pattern = @original_pattern`)
  # — so que esse caminho nao corre para quem eu movo a mao. O `original_pattern`
  # vem da pagina do evento e e o quadro parado dele; zero e a rede para quando
  # ele nao existir.
  def parar_evento!(ev)
    return unless ev
    parado = ((ev.instance_variable_get(:@original_pattern) rescue nil) || 0).to_i
    return if (ev.pattern rescue 0).to_i == parado
    (ev.instance_variable_set(:@pattern, parado) rescue nil)
  rescue
    nil
  end

  def mover_corpo!
    return if pvp?
    return unless @activa && @corpo_x && $game_map && $game_player
    ev = $game_map.events[ID_CORPO]
    return unless ev
    dt = [(@delta || (1.0 / 60.0)), 0.1].min
    rx = (ev.instance_variable_get(:@real_x) rescue 0).to_f
    ry = (ev.instance_variable_get(:@real_y) rescue 0).to_f
    prx = ($game_player.instance_variable_get(:@real_x) rescue 0).to_f
    pry = ($game_player.instance_variable_get(:@real_y) rescue 0).to_f
    dx = prx - rx
    dy = pry - ry
    n = Math.sqrt((dx * dx) + (dy * dy))
    if (n / Game_Map::REAL_RES_X.to_f) <= CORPO_SEGUE || n < 0.001
      parar_evento!(ev)
      return
    end
    dx /= n
    dy /= n
    nova = (dx.abs > dy.abs) ? ((dx > 0) ? 6 : 4) : ((dy > 0) ? 2 : 8)
    (ev.instance_variable_set(:@direction, nova) rescue nil)
    passo = CORPO_VELOC * Game_Map::REAL_RES_X * dt
    nx = rx + (dx * passo)
    rx = nx if casa_livre_para_evento?(ev, nx, ry)
    ny = ry + (dy * passo)
    ry = ny if casa_livre_para_evento?(ev, rx, ny)
    ev.instance_variable_set(:@real_x, rx)
    ev.instance_variable_set(:@real_y, ry)
    ev.instance_variable_set(:@x, (rx / Game_Map::REAL_RES_X.to_f).round)
    ev.instance_variable_set(:@y, (ry / Game_Map::REAL_RES_Y.to_f).round)
    (ev.calculate_bush_depth rescue nil)
    animar_evento!(ev)
    # ⚠️ E a marca de onde ele esta tem de andar com ele: e por ela que se sabe
    # se estamos ao pe dele para encerrar, e para onde o Pokemon volta no fim.
    @corpo_x = ev.x
    @corpo_y = ev.y
    @corpo_dir = nova
  rescue
    nil
  end

  def garantir_corpo!
    return if pvp? || caverna?
    return unless @activa && @corpo_x && $game_map
    agora = (Graphics.frame_count rescue 0)
    return if (agora - @corpo_visto.to_i) < 60
    @corpo_visto = agora
    return if $game_map.events[ID_CORPO]
    registar("o treinador tinha desaparecido; reposto")
    repor_corpo!
  rescue
    nil
  end

  def repor_corpo!
    return unless @corpo_x && $game_map
    rpg = RPG::Event.new(@corpo_x, @corpo_y)
    rpg.id   = ID_CORPO
    rpg.name = "ArenaTreinadorUpdate"
    pag = rpg.pages[0]
    pag.graphic.character_name = @corpo_charset.to_s
    pag.graphic.direction = @corpo_dir.to_i
    pag.trigger    = -1
    pag.move_type  = 0
    # ⚠️ O `step_anime` BRIGA COM O `parar_evento!`, E O QUE SE VE E UM TREMOR.
    #
    # Com `step_anime = true`, o `Game_Character#update` do motor avanca o
    # `@pattern` a CADA frame, ande o boneco ou nao. O `parar_evento!` repoe o
    # padrao de descanso. Os dois correm no mesmo frame, um a seguir ao outro,
    # para sempre: o motor adianta, nos repomos, o motor adianta. O sprite
    # salta entre dois desenhos sessenta vezes por segundo — e isso le-se como
    # um boneco a tremer, nao como um boneco parado.
    #
    # Nao e preciso: o `animar_evento!` ja move as pernas a mao, e so e chamado
    # quando o boneco anda mesmo. Desligar o `step_anime` tira o motor da
    # equacao e deixa uma so mao a mandar no padrao.
    pag.step_anime = false    # o `animar_evento!` e que move as pernas
    pag.through    = true
    pag.list = [RPG::EventCommand.new(0, 0, [])]
    ev = Game_Event.new($game_map.map_id, rpg, $game_map)
    ev.through = true
    pousar_evento!(ID_CORPO, ev, rpg)
    ev.refresh
    (ev.instance_variable_set(:@direction, @corpo_dir.to_i) rescue nil)
    (AnilLanRework::ReleasedRoaming.sync_sprite(ev) rescue nil) if $scene.is_a?(Scene_Map)
  rescue => e
    registar("falha a repor o treinador: #{e.class}: #{e.message}")
  end

  # ⚠️ VOLTA-SE FALANDO COM ELE, e nao por um comando escrito.
  #
  # Ele ficou ali a espera; ir ter com ele e dizer "acabou" fecha o circulo que
  # a entrada abriu — foi a falar com o Pokemon que isto comecou.
  def perto_do_corpo?
    return false unless @corpo_x && $game_player
    fx, fy = casa_a_frente(1)
    (fx == @corpo_x && fy == @corpo_y) ||
      ($game_player.x == @corpo_x && $game_player.y == @corpo_y)
  rescue
    false
  end

  def talvez_falar_com_corpo!
    return if pvp?
    return unless @activa && @corpo_x
    return unless perto_do_corpo?
    botao = (Input::USE rescue nil)
    return unless botao
    lido = if Input.respond_to?(:anil_arena_orig_trigger?)
             (Input.anil_arena_orig_trigger?(botao) rescue false)
           else
             (Input.trigger?(botao) rescue false)
           end
    return unless lido
    sair!
    pbMessage(_INTL("Batalha direta encerrada.")) rescue nil
  rescue
    nil
  end

  # ⚠️ NA AUTOMATICA NAO HA COM QUEM FALAR PARA PARAR.
  #
  # A directa tem o corpo do treinador: chega-se ao pe dele, carrega-se no C, e
  # a batalha acaba (`talvez_falar_com_corpo!`). Na automatica nao ha corpo — eu
  # SOU o treinador — e o seguidor esta escondido, portanto o menu de falar com
  # o Pokemon tambem nao aparece. Ficava so o `/arena sair`, que e escrever um
  # comando para acabar uma coisa que se comecou a falar com o bicho.
  #
  # O evento do ajudante tem `trigger = -1` e nao responde ao C por si. Faz-se
  # como o corpo: le-se a tecla aqui, com o mesmo gancho de input da arena, e
  # pergunta-se.
  def talvez_falar_com_ajudante!
    return unless automatica? && aliado_vivo?
    ev = @aliado[:ev]
    return unless ev
    return if distancia_casas(ev, $game_player) > 1.6
    botao = (Input::USE rescue nil)
    return unless botao
    lido = if Input.respond_to?(:anil_arena_orig_trigger?)
             (Input.anil_arena_orig_trigger?(botao) rescue false)
           else
             (Input.trigger?(botao) rescue false)
           end
    return unless lido
    nome = (@aliado[:pkmn].name rescue "")
    opcoes = [_INTL("Parar de caçar"), _INTL("Deixar como está")]
    escolha = (pbMessage(AnilLanRework.ui_format("{1} está caçando.", nome),
                         opcoes, 2) rescue 1)
    return unless escolha == 0
    sair!
    pbMessage(AnilLanRework.ui_format("{1} voltou para você.", nome)) rescue nil
  rescue
    nil
  end

  def apagar_corpo!
    return unless $game_map && $game_map.events[ID_CORPO]
    apagar_evento_bicho!(ID_CORPO)
  rescue
    nil
  end

  # O Pokemon volta para junto do treinador — foi de la que saiu.
  def voltar_ao_corpo!
    return unless @corpo_x && $game_player
    ($game_player.moveto(@corpo_x, @corpo_y) rescue nil)
    ($game_player.instance_variable_set(:@direction, @corpo_dir.to_i) rescue nil)
    ($game_map.display_x = ($game_player.instance_variable_get(:@real_x) - Game_Player::SCREEN_CENTER_X)) rescue nil
    ($game_map.display_y = ($game_player.instance_variable_get(:@real_y) - Game_Player::SCREEN_CENTER_Y)) rescue nil
  rescue
    nil
  ensure
    @corpo_x = nil
    @corpo_y = nil
  end

  def apagar_evento_bicho!(id)
    return unless $game_map
    ev = $game_map.events[id]
    return unless ev
    dados = ($game_map.instance_variable_get(:@map) rescue nil)
    dados.events.delete(id) if dados && dados.respond_to?(:events)
    if $game_map.respond_to?(:removeThisEventfromMap)
      $game_map.removeThisEventfromMap(id)
    else
      $game_map.events.delete(id)
    end
    if $scene.is_a?(Scene_Map)
      conj = ($scene.spriteset($game_map.map_id) rescue nil) || ($scene.spriteset rescue nil)
      if conj && conj.respond_to?(:character_sprites)
        i = conj.character_sprites.index { |sp| sp.character == ev }
        (conj.character_sprites.delete_at(i).dispose rescue nil) if i
      end
    end
  rescue
    nil
  end

  def apagar_inimigo!
    (@bichos || []).each do |b|
      if b[:balao]
        (b[:balao].bitmap.dispose rescue nil)
        (b[:balao].dispose rescue nil)
        b[:balao] = nil
      end
      largar_barra_de_vida!(b)
      # Um selvagem adoptado e do mapa, nao meu: devolve-se a rotina dele em vez
      # de o apagar. Apagar seria tirar do mundo um encontro que a Gaby tambem
      # esta a ver.
      if b[:adoptado]
        soltar_bicho!(b)
      else
        apagar_evento_bicho!(b[:id])
      end
    end
    # Um id perdido de uma sessao anterior tambem sai daqui.
    MAX_BICHOS.times { |i| apagar_evento_bicho!(ID_INIMIGO + i) }
    # A banda da caverna tambem, senao trinta eventos ficavam no mapa depois de
    # se sair — invisiveis para o codigo da arena e bem visiveis no ecra.
    MAX_CAVERNA.times { |i| apagar_evento_bicho!(ID_CAVERNA + i) }
    apagar_evento_bicho!(ID_MARCADOR2) if $game_map && $game_map.events[ID_MARCADOR2]
    @bichos = []
  rescue
    @bichos = []
  end

  # Tira UM bicho do mapa e da lista. Quando o ultimo cai, a caca acabou.
  # ⚠️ SUMIR NAO E CAIR.
  #
  # O evento era apagado e o boneco desaparecia no meio do passo — parecia um
  # bug, nao uma vitoria. Copia-se o quadro em que ele estava para um sprite
  # solto e deixa-se esse cair: afunda, achata e apaga-se, como o desmaio da
  # batalha. O evento ja pode ir embora por baixo.
  # ⚠️ MORRER NAO E SER ESMAGADO.
  #
  # O desmaio encolhia o boneco na vertical (`zoom_y` de 1 para 0,25) enquanto
  # desvanecia — que e o gesto do jogo de sempre, onde o Pokemon "afunda" no
  # fundo do ecra de batalha. Num mapa visto de cima isso nao le como morrer:
  # le como o boneco a entortar-se.
  #
  # O que se le como morrer, num mapa, e o brilho vermelho da ultima pancada a
  # apagar-se. Fica o desvanecer, sai o encolher, e entra o vermelho a pulsar —
  # mais depressa no fim, como um coracao a parar.
  DESMAIO_FRAMES = 40
  DESMAIO_PISCAS = 3.5     # quantas piscadelas cabem no desvanecer

  # ⚠️ UM CORPO FICA ONDE CAIU, E O ECRA E QUE ANDA.
  #
  # O sprite era posto em `ev.screen_x` — coordenadas de ECRA — e ficava la. Ao
  # andar, a camara movia-se e o corpo vinha atras, colado: arrastava-se o
  # cadaver pelo mapa fora. Uma coisa que morreu naquela casa tem de ficar
  # naquela casa.
  #
  # Guarda-se a posicao do MAPA (`real_x`/`real_y`) e refaz-se a do ecra a cada
  # frame, com a mesma conta do motor. E o mesmo que o `Game_Character#screen_x`
  # faz, e e por isso que o corpo fica exactamente onde o boneco estava.
  #
  # ⚠️ E MORRER TEM TRES TEMPOS, NAO UM.
  #
  # O som, o salto para tras, e so depois o desvanecer. Sem o salto a morte
  # acontece sem peso — o bicho apaga-se como se tivesse sido desligado. Com
  # ele ha uma ultima coisa a acontecer-lhe: leva a pancada, e so a seguir e
  # que cai.
  SALTO_FRAMES = 9        # o pulo para tras
  SALTO_PIXEIS = 14.0     # ate onde vai

  def animar_desmaio!(ev, de = nil)
    return unless ev
    nome = (ev.character_name.to_s rescue "")
    return if nome.empty?
    bmp = (RPG::Cache.character(nome, (ev.character_hue.to_i rescue 0)) rescue nil)
    return unless bmp && !(bmp.disposed? rescue true)
    cw = bmp.width / 4
    ch = bmp.height / 4
    sp = Sprite.new(viewport_das_animacoes)
    sp.bitmap = bmp     # e da cache: deita-se fora o sprite, nunca o bitmap
    sp.src_rect.set(((ev.pattern rescue 0) % 4) * cw,
                    ((((ev.direction rescue 2) / 2) - 1) % 4) * ch, cw, ch)
    sp.ox = cw / 2
    sp.oy = ch

    rx = (ev.instance_variable_get(:@real_x) rescue 0).to_f
    ry = (ev.instance_variable_get(:@real_y) rescue 0).to_f

    # Para onde salta: ao contrario de quem lhe bateu. Sem referencia, salta
    # para tras da cara dele.
    quem = de || $game_player
    fx = (rx - ((quem.instance_variable_get(:@real_x) rescue rx).to_f))
    fy = (ry - ((quem.instance_variable_get(:@real_y) rescue ry).to_f))
    n = Math.sqrt((fx * fx) + (fy * fy))
    if n < 1.0
      d = (ev.direction rescue 2)
      fx = (d == 4) ? 1.0 : ((d == 6) ? -1.0 : 0.0)
      fy = (d == 8) ? 1.0 : ((d == 2) ? -1.0 : 0.0)
    else
      fx /= n
      fy /= n
    end

    (pbSEPlay("Battle faint", 80) rescue nil)
    agora = (Graphics.frame_count rescue 0)
    # ⚠️ DE QUEM E ESTE CORPO.
    #
    # Sem isto nao ha maneira de ligar o sprite da queda ao bicho que caiu — e
    # e precisamente isso que um golpe ainda a sair precisa de saber para nao o
    # largar a meio do tombo.
    (@desmaios ||= []) << { :sp => sp, :ev => ev, :rx => rx, :ry => ry,
                            :fx => fx, :fy => fy,
                            :salto_ate => agora + SALTO_FRAMES,
                            :ate => agora + SALTO_FRAMES + DESMAIO_FRAMES }
    pousar_desmaio!(@desmaios.last, 0.0)
  rescue => e
    registar("falha no desmaio: #{e.class}: #{e.message}")
  end

  # ⚠️ REFEITO A CADA FRAME, A PARTIR DA POSICAO DO MAPA.
  #
  # E a mesma conta do `Game_Character#screen_x`: a posicao real menos o canto
  # do ecra, a dividir pelos subpixeis, mais meia casa. Enquanto isto correr, o
  # corpo fica preso ao chao e a camara passa por cima dele.
  def pousar_desmaio!(d, k)
    sp = d[:sp]
    return if sp.nil? || (sp.disposed? rescue true)
    subida = (4.0 * k * (1.0 - k)) * 10.0           # o arco do pulo
    avanco = (k * SALTO_PIXEIS)
    rx = d[:rx] + (d[:fx] * avanco * Game_Map::X_SUBPIXELS)
    ry = d[:ry] + (d[:fy] * avanco * Game_Map::Y_SUBPIXELS)
    sp.x = ((rx - $game_map.display_x).to_f / Game_Map::X_SUBPIXELS).round +
           (Game_Map::TILE_WIDTH / 2)
    sp.y = ((ry - $game_map.display_y).to_f / Game_Map::Y_SUBPIXELS).round +
           Game_Map::TILE_HEIGHT - subida.round
  rescue
    nil
  end

  def correr_desmaios!
    return if @desmaios.nil? || @desmaios.empty?
    agora = (Graphics.frame_count rescue 0)
    fora = []
    @desmaios.each do |d|
      sp = d[:sp]
      if sp.nil? || (sp.disposed? rescue true) || agora >= d[:ate]
        (sp.dispose rescue nil) if sp && !(sp.disposed? rescue true)
        fora << d
        next
      end
      if d[:fantasma]
        sp.opacity = (sp.opacity * 0.85).to_i
        pousar_desmaio!(d, 1.0)
        next
      end
      if d[:salto_ate] && agora < d[:salto_ate]
        # ⚠️ O SALTO E UM ARCO, E NAO UM ESCORREGAR.
        #
        # `4k(1-k)` sobe e desce dentro do mesmo tempo: sai do chao, chega ao
        # alto a meio, e volta a pousar no fim. Um deslocamento linear lia-se
        # como o boneco a ser empurrado, e nao como a levar.
        k = 1.0 - ((d[:salto_ate] - agora).to_f / SALTO_FRAMES)
        k = 0.0 if k < 0.0
        sp.opacity = 255
        (sp.color.set(255, 60, 60, 180) rescue nil)
        pousar_desmaio!(d, k)
        next
      end
      janela = (d[:ate] - (d[:salto_ate] || d[:ate])).to_f
      janela = DESMAIO_FRAMES if janela <= 0
      resta = (d[:ate] - agora).to_f / janela
      resta = 0.0 if resta < 0.0
      sp.opacity = (255 * resta).to_i
      # ⚠️ O vermelho acelera. Um pulso constante le-se como um efeito ligado;
      # um que aperta le-se como uma coisa a acabar.
      fase = (1.0 - resta) * DESMAIO_PISCAS * (1.0 + (1.0 - resta))
      brilho = ((Math.sin(fase * Math::PI * 2.0) + 1.0) / 2.0)
      (sp.color.set(255, 40, 40, (200 * brilho * resta).to_i) rescue nil)
      pousar_desmaio!(d, 1.0)
    end
    @desmaios -= fora
  rescue => e
    # ⚠️ AQUI ESTAVA A "COPIA MINHA PRESA NO MAPA".
    #
    # Esta lista tem sprites vivos: o corpo de quem caiu, e o RASTO do salto —
    # que e desenhado com o charset do JOGADOR. Deitar a lista fora com um
    # `@desmaios = []` nao deita fora os sprites: deita fora a unica referencia
    # que havia para eles. Ficam no ecra, com a opacidade que tinham no
    # instante em que isto rebentou, e ja ninguem os pode apagar — uma copia
    # nossa, parada, para o resto da sessao.
    #
    # E um `rescue` que engolia o erro e criava outro pior. Agora deita-se fora
    # o que ha para deitar, e a causa fica no log em vez de virar um fantasma.
    registar("falha nos desmaios: #{e.class}: #{e.message}")
    limpar_desmaios!
  end

  def limpar_desmaios!
    (@desmaios || []).each { |d| (d[:sp].dispose rescue nil) if d[:sp] }
    @desmaios = []
  rescue
    @desmaios = []
  end

  #-----------------------------------------------------------------------------
  # EXPERIENCIA
  #
  # ⚠️ A CONTA E A DA SERIE, SEM OS MULTIPLICADORES QUE AQUI NAO EXISTEM.
  #
  # base_exp x nivel / 5 e a formula base; o que fica de fora sao coisas que a
  # arena nao tem — participantes, treinador adversario, item da sorte. Sobe-se
  # a experiencia e deixa-se o motor recalcular o nivel: o `exp=` limpa o nivel
  # em cache de proposito, e a seguir basta refazer as estatisticas.
  #-----------------------------------------------------------------------------
  # ⚠️ DEPOIS DE EVOLUIR, TRES COISAS FICAM A APONTAR PARA O BICHO ANTIGO.
  #
  # A especie mudou no objecto `Pokemon`, mas nada no mapa sabe disso:
  #
  #   o boneco do evento   continua a ser o charset da especie antiga
  #   a barra de vida      tem o maximo antigo guardado no `@aliado[:hp_max]`
  #   o HUD                nao redesenha porque a chave dele nao mudou
  #
  # O `202` faz a evolucao e chama isto; a arrumacao e daqui, porque e aqui que
  # essas tres coisas vivem.
  def evolucao_aconteceu!(pkmn, evento)
    return unless pkmn
    if evento && !evento.equal?($game_player)
      nome = caminho_do_sprite(pkmn)
      (evento.instance_variable_set(:@character_name, nome) rescue nil)
      (evento.instance_variable_set(:@character_hue,
                                    (pkmn.super_shiny_hue.to_i rescue 0)) rescue nil)
    end
    # O boneco do jogador (na batalha directa, eu SOU ele) passa pelo gancho do
    # `refresh_charset`, que le o `@charset`.
    if @charset && @meu && @meu.equal?(pkmn)
      @charset = caminho_do_sprite(pkmn)
      ($game_player.refresh_charset rescue nil)
    end
    if aliado_vivo? && @aliado[:pkmn].equal?(pkmn)
      @aliado[:hp_max] = pkmn.totalhp.to_i
      @aliado[:hp] = [@aliado[:hp], @aliado[:hp_max]].min
    end
    @hud_chave = nil    # forca o HUD a redesenhar com os numeros novos
  rescue
    nil
  end

  def dar_exp!(b)
    return unless @meu && b && b[:pkmn]
    base = (GameData::Species.get(b[:pkmn].species).base_exp.to_i rescue 60)
    base = 60 if base <= 0
    ganho = ((base * [b[:pkmn].level.to_i, 1].max) / 5.0).round
    ganho = 1 if ganho < 1
    antes = @meu.level.to_i
    vida_antes = @meu.totalhp.to_i
    tecto = (@meu.growth_rate.maximum_exp rescue nil)
    novo_exp = @meu.exp.to_i + ganho
    novo_exp = tecto if tecto && novo_exp > tecto
    @meu.exp = novo_exp
    flutuar!("+#{ganho} XP", Color.new(255, 230, 90))
    if @meu.level.to_i > antes
      (@meu.calc_stats rescue nil)
      # Subir de nivel aumenta a vida MAXIMA; na serie a vida actual sobe na
      # mesma medida, senao subir de nivel a meio de uma luta parecia um castigo.
      ganho_vida = @meu.totalhp.to_i - vida_antes
      # ⚠️ NA AUTOMATICA A VIDA QUE SOBE E A DO AJUDANTE.
      #
      # O `@meu` e o `@aliado[:pkmn]` sao o mesmo objecto neste modo, mas as
      # CONTAS sao duas: o `@hp_meu` nao esta em jogo e o `@aliado[:hp]` esta.
      # Somar o ganho ao lado errado deixava a barra dele parada num nivel novo.
      if automatica? && aliado_vivo?
        @aliado[:hp_max] = @meu.totalhp.to_i
        @aliado[:hp] = [@aliado[:hp] + [ganho_vida, 0].max, @aliado[:hp_max]].min
        (@aliado[:pkmn].hp = @aliado[:hp]) rescue nil
      else
        @hp_meu = [@hp_meu + [ganho_vida, 0].max, @meu.totalhp].min
      end
      flutuar!(_INTL("Nível {1}!", @meu.level), Color.new(120, 255, 140))
      (pbSEPlay("Pkmn level up") rescue nil)
      # ⚠️ E SUBIR DE NIVEL E O UNICO MOMENTO EM QUE SE PERGUNTA PELA EVOLUCAO.
      #
      # Perguntar a cada tique seria conveniente e errado: o
      # `check_evolution_on_level_up` chama-se assim porque e isso que ele
      # responde — "com o nivel que ACABOU de subir, evolui?".
      quem = (automatica? && aliado_vivo?) ? @aliado[:ev] : $game_player
      (AnilArenaEvolucao.talvez_evoluir!(@meu, quem) rescue nil)
    end
  rescue => e
    registar("falha na exp: #{e.class}: #{e.message}")
  end

  # Um numero que sobe e apaga por cima do Pokemon. E o unico sitio onde a
  # arena escreve fora do painel, e e de proposito: o que se ganha tem de
  # aparecer onde se olha.
  FLUTUA_FRAMES = 46

  def flutuar!(texto, cor = nil)
    bmp = Bitmap.new(160, 28)
    (pbSetSystemFont(bmp) rescue nil)
    bmp.font.size = 18 rescue nil
    bmp.font.color = Color.new(0, 0, 0)
    bmp.draw_text(1, 1, 158, 26, texto.to_s, 1)
    bmp.font.color = (cor || Color.new(255, 255, 255))
    bmp.draw_text(0, 0, 158, 26, texto.to_s, 1)
    sp = Sprite.new(viewport_das_animacoes)
    sp.bitmap = bmp
    sp.ox = 80
    sp.oy = 26
    sp.x = ($game_player.screen_x rescue 0)
    sp.y = ($game_player.screen_y rescue 0) - 30
    (@flutuantes ||= []) << { :sp => sp, :y0 => sp.y,
                              :ate => (Graphics.frame_count rescue 0) + FLUTUA_FRAMES }
  rescue
    nil
  end

  def correr_flutuantes!
    return if @flutuantes.nil? || @flutuantes.empty?
    agora = (Graphics.frame_count rescue 0)
    fora = []
    @flutuantes.each do |d|
      sp = d[:sp]
      if sp.nil? || (sp.disposed? rescue true) || agora >= d[:ate]
        if sp && !(sp.disposed? rescue true)
          (sp.bitmap.dispose rescue nil)
          (sp.dispose rescue nil)
        end
        fora << d
        next
      end
      resta = (d[:ate] - agora).to_f / FLUTUA_FRAMES
      sp.opacity = (255 * [resta * 2.0, 1.0].min).to_i
      sp.y = d[:y0] - ((1.0 - resta) * 22).round
    end
    @flutuantes -= fora
  rescue
    @flutuantes = []
  end

  def limpar_flutuantes!
    (@flutuantes || []).each do |d|
      next unless d[:sp] && !(d[:sp].disposed? rescue true)
      (d[:sp].bitmap.dispose rescue nil)
      (d[:sp].dispose rescue nil)
    end
    @flutuantes = []
  rescue
    @flutuantes = []
  end

  #-----------------------------------------------------------------------------
  # OS TONTOS
  #
  # ⚠️ UM SELVAGEM DERROTADO NAO DEVE DESAPARECER: DEVE FICAR ALI, GROGUE.
  #
  # Ate agora ele evaporava no fim do golpe e a captura era um acidente — quem
  # quisesse apanha-lo tinha de acertar a bola ANTES de o matar, o que e o
  # contrario de como se joga Pokemon. Agora ele fica: para de andar, para de
  # atacar, oscila como uma arvore ao vento e leva um ponto de interrogacao por
  # cima. E so sai do mapa quando SE DECIDE — com a bola ou sem ela.
  #
  # Ele continua na lista dos bichos, mas com vida zero: e por isso que o resto
  # do combate deixa de o ver (o `bichos_vivos` filtra por vida), sem eu ter de
  # espalhar um `if tonto` por toda a parte.
  #-----------------------------------------------------------------------------
  TONTO_LIMITE   = 30.0   # segundos ate ele acordar e fugir sozinho
  TONTO_ALCANCE  = 6.0    # casas: a partir daqui ja se lhe pode atirar a bola
  TONTO_BALANCO  = 13.0   # graus de oscilacao

  # ⚠️ O GROGUE E UMA OFERTA, E COM A CADEIA CHEIA ELA DEIXA DE VALER.
  #
  # Um selvagem derrotado fica grogue trinta segundos a oscilar, com uma
  # interrogacao por cima, a pedir uma bola. Isso e certo enquanto apanha-lo
  # ainda serve para alguma coisa — cada captura sobe a cadeia, e a cadeia e o
  # que faz nascer o shiny.
  #
  # Com a cadeia no tecto a oferta esta feita: apanhar mais um do mesmo nao
  # acrescenta nada, e o que fica no ecra sao corpos a abanar aos montes, a
  # tapar o chao e a mira, numa altura em que o que interessa e continuar a
  # matar depressa a espera do que brilha.
  #
  # Entao com a cadeia cheia, e so na batalha direta, quem cai e nao brilha
  # desaparece num segundo. Quem brilha fica — esse e sempre uma oferta, tenha a
  # cadeia o numero que tiver.
  CADEIA_CHEIA   = 40     # e onde o bonus da cadeia para de subir
  TONTO_DEPRESSA = 1.0    # segundos, com a cadeia cheia

  # A cadeia que conta: a somada com o parceiro, se o coop estiver a somar;
  # senao a nossa. Ler directamente o `catchcombo` daria um numero mais baixo
  # do que o que o jogo esta mesmo a usar para sortear o shiny.
  def cadeia_agora(especie)
    if defined?(AnilCadeiaCoop)
      n = (AnilCadeiaCoop.cadeia_somada(especie) rescue nil)
      return n.to_i if n
    end
    c = ($PokemonGlobal.catchcombo rescue nil)
    return 0 unless c.is_a?(Array)
    (c[1].to_s == especie.to_s) ? c[0].to_i : 0
  rescue
    0
  end

  #-----------------------------------------------------------------------------
  # A CADEIA, NA BATALHA DIRETA
  #
  # ⚠️ ELA NAO SUBIA. E NAO ERA UM DEFEITO — ERA UMA AUSENCIA.
  #
  # A cadeia do jogo move-se num sitio so:
  #
  #     EventHandlers.add(:on_wild_battle_end, ...) { |especie, _nivel, decisao| ... }
  #
  # Ou seja, so uma BATALHA a serio que acabe em vitoria ou captura. Na batalha
  # directa nao ha batalha nenhuma: os selvagens caem no mapa, sem ecra de
  # combate e sem esse evento. Resultado: cacar duas horas em directa deixava a
  # cadeia exactamente onde estava, e o F7 nao mostrava nada porque nao havia
  # nada para mostrar — a linha da cadeia so se desenha com cadeia maior que
  # zero.
  #
  # ⚠️ E O QUE NAO E DA CADEIA NAO A PARTE.
  #
  # No mundo, apanhar outra especie reinicia a contagem — e certo, porque la
  # escolhe-se o que se enfrenta. Aqui nao se escolhe: o que aparece a volta
  # aparece, e ha quatro ao mesmo tempo. Reiniciar por causa de um Pidgey que
  # entrou na briga sem ser convidado seria castigar o jogador por uma coisa que
  # nao foi decisao dele.
  #
  # Entao: quem e da especie da cadeia soma; quem nao e, nao faz nada. Trocar de
  # especie faz-se como sempre se fez — capturando uma, que passa pelo caminho
  # normal do jogo e reinicia a contagem com a especie nova.
  def somar_cadeia!(pk)
    return unless @directa
    return unless pk
    esp = (pk.species rescue nil)
    return unless esp
    $PokemonGlobal.catchcombo = [0, 0] if ($PokemonGlobal.catchcombo rescue nil).nil?
    combo = $PokemonGlobal.catchcombo
    if combo[0].to_i <= 0
      # Sem cadeia nenhuma, o primeiro que cai comeca a dela.
      combo[0] = 0
      combo[1] = esp
    elsif combo[1].to_s != esp.to_s
      return                      # de outra especie: nao soma e nao parte
    end
    combo[0] = combo[0].to_i + 1
    $PokemonGlobal.catchcombo = combo
    (AnilCadeiaCoop.anunciar! rescue nil) if defined?(AnilCadeiaCoop)
    n = cadeia_agora(esp)
    dizer(_INTL("Cadeia {1}: {2}", n, (pk.speciesName rescue esp.to_s))) if (n % 10).zero?
  rescue => e
    registar("falha a somar a cadeia: #{e.class}: #{e.message}")
  end

  def grogue_dura(b)
    return TONTO_LIMITE unless @directa
    pk = b[:pkmn]
    return TONTO_LIMITE unless pk
    return TONTO_LIMITE if (pk.shiny? rescue false) || (pk.super_shiny? rescue false)
    return TONTO_LIMITE if cadeia_agora(pk.species) < CADEIA_CHEIA
    TONTO_DEPRESSA
  rescue
    TONTO_LIMITE
  end

  def bichos_tontos
    bichos.select { |b| b[:tonto] && b[:ev] }
  end

  def tonto_a_mao
    lista = bichos_tontos
    return nil if lista.empty?
    perto = lista.min_by { |b| distancia_casas(b[:ev], $game_player) }
    return nil unless perto
    return nil if distancia_casas(perto[:ev], $game_player) > TONTO_ALCANCE
    perto
  rescue
    nil
  end

  def atordoar!(b)
    # ⚠️ Soma-se ANTES de medir a duracao: e o abate deste que pode levar a
    # cadeia ao tecto, e e o tecto que decide se ele fica um segundo ou trinta.
    somar_cadeia!(b[:pkmn])
    dura = grogue_dura(b)
    b[:tonto] = true
    b[:depressa] = (dura < TONTO_LIMITE)
    b[:tonto_ate] = Time.now.to_f + dura
    b[:hp] = 0
    esquecer_vivos!
    b[:estado] = nil
    sp = sprite_de(b[:ev])
    (sp.color.set(0, 0, 0, 0) rescue nil) if sp
    (pbSEPlay("Battle faint") rescue nil)
    # Com a cadeia cheia nao se anuncia: sao dezenas por minuto, e um aviso que
    # aparece dezenas de vezes por minuto deixa de ser um aviso.
    dizer(_INTL("{1} está grogue!", (b[:pkmn].speciesName rescue ""))) unless b[:depressa]
    actualizar_foco!
  rescue
    nil
  end

  def correr_tontos!
    lista = bichos_tontos
    return if lista.empty?
    agora = Time.now.to_f
    t = agora * 7.0
    fora = []
    lista.each do |b|
      if agora >= b[:tonto_ate].to_f
        fora << b
        next
      end
      next if @captura && @captura[:b].equal?(b)
      sp = sprite_de(b[:ev])
      next unless sp
      # A oscilacao e no sprite, nao no evento: o evento esta parado e e assim
      # que tem de ficar.
      (sp.angle = Math.sin(t + b[:id].to_i) * TONTO_BALANCO) rescue nil
      marcar_interrogacao!(b, sp)
    end
    fora.each do |b|
      # Quem foi marcado para sair depressa nao "fugiu": foi derrotado e
      # desapareceu, como acontece numa guerra. So se anuncia quem escapou
      # mesmo, que e o caso em que o jogador perdeu alguma coisa.
      dizer(_INTL("{1} fugiu!", (b[:pkmn].speciesName rescue ""))) unless b[:depressa]
      soltar_tonto!(b)
    end
  rescue
    nil
  end

  # ⚠️ O JOGO JA TEM UM BALAO DE INTERROGACAO: e a animacao de mapa numero 4,
  # "Question bubble", da folha `Follower_Emote2`. Vale mais do que o "?" que eu
  # desenhei a mao — e a mesma que o jogo usa em toda a parte, e ja esta no
  # sitio certo por cima da cabeca. Repete-se de dois em dois segundos enquanto
  # ele estiver grogue.
  ANIM_INTERROGACAO = 4

  #-----------------------------------------------------------------------------
  # A VIDA DE CADA INIMIGO, POR CIMA DELE
  #
  # ⚠️ UM SPRITE PEQUENO POR BICHO, E NAO UM DESENHO NO PAINEL.
  #
  # A tentacao era desenhar isto no bitmap do painel, que ja existe. Nao se
  # pode: o painel so se repinta quando a chave dele muda (ver o `@hud_chave`),
  # e os inimigos andam a cada frame — as barras ficariam para tras do boneco.
  # Po-las na chave obrigava a repintar um bitmap do tamanho do ecra sessenta
  # vezes por segundo, que e o defeito que essa chave existe para evitar.
  #
  # Um sprite de 30x5 por bicho custa uma posicao por frame (nao um desenho), e
  # so se redesenha quando a vida muda. E o mesmo desenho do balao de
  # interrogacao, que ja vive assim ali em baixo.
  #-----------------------------------------------------------------------------
  VIDA_LARG = 30
  VIDA_ALT  = 5
  VIDA_SOBE = 6     # pixeis acima do topo do boneco

  #-----------------------------------------------------------------------------
  # ⚠️ QUEM SEGURA A BARRA NAO PODE SER O BICHO.
  #
  # Eu guardei o sprite em `b[:vida_sp]` e limpei-o nos dois sitios onde me
  # lembrei. So que um bicho sai da lista por NOVE caminhos diferentes — morrer,
  # fugir, ser apanhado, ser adoptado pelo mapa, o andar mudar, a arena fechar.
  # Nos outros sete, o `b` era simplesmente deitado fora com o sprite dentro:
  # ninguem ficava com uma referencia para o largar, e a barra ficava no ecra
  # para sempre. E o que se ve na imagem — barras verdes a pairar sobre o nada.
  #
  # A lista e que tem de segurar as barras, e nao cada bicho a sua. A cada frame
  # aponta-se quem foi visto; o que nao aparecer nesta volta ja nao existe, seja
  # qual for o caminho por onde saiu. Nao e preciso lembrar-me dos nove.
  #-----------------------------------------------------------------------------
  def correr_barras_de_vida!
    @barras ||= {}
    unless @activa
      largar_barras_de_vida!
      return
    end
    vistos = {}
    bichos_vivos.each do |b|
      next unless b[:ev]
      next if b[:hp].to_i <= 0
      # ⚠️ Longe, a barra ESCONDE-SE mas nao se deita fora.
      #
      # Deita-la fora obrigava a criar um bitmap novo sempre que o jogador
      # cruzasse a fronteira das catorze casas — e numa luta anda-se para a
      # frente e para tras. Esconder custa um booleano.
      if longe_para_tratar?(b)
        d = (@barras || {})[b.object_id]
        (d[:sp].visible = false) rescue nil if d && d[:sp]
        vistos[b.object_id] = true if d
        next
      end
      sp = sprite_de(b[:ev])
      next unless sp && (sp.visible rescue false)
      chave = b.object_id
      bar = barra_de(chave, b)
      next unless bar
      vistos[chave] = true
      bar.visible = true
      alt_sp = ((sp.src_rect.height rescue 32) * (sp.zoom_y rescue 1)).abs
      bar.x = (sp.x - (VIDA_LARG / 2)).round
      bar.y = (sp.y - alt_sp - VIDA_SOBE).round
      bar.z = (sp.z rescue 0) + 1
    end
    # O que nao foi visto neste frame saiu de cena — por onde quer que tenha
    # sido.
    (@barras.keys - vistos.keys).each { |k| largar_barra_por_chave!(k) }
  rescue
    nil
  end

  # ⚠️ So se redesenha quando a vida MUDA. Um `fill_rect` por bicho por frame
  # seria trabalho a repetir para dar sempre o mesmo desenho.
  def barra_de(chave, b)
    total = [b[:hp_max].to_i, 1].max
    viva  = [[b[:hp].to_i, 0].max, total].min
    fatia = ((viva * VIDA_LARG) / total.to_f).round
    d = @barras[chave]
    d = nil if d && (d[:sp].nil? || (d[:sp].disposed? rescue true))
    if d.nil?
      bmp = Bitmap.new(VIDA_LARG, VIDA_ALT)
      sp = Sprite.new(viewport_das_animacoes)
      sp.bitmap = bmp
      d = @barras[chave] = { :sp => sp, :fatia => nil }
    end
    return d[:sp] if d[:fatia] == fatia
    bmp = d[:sp].bitmap
    bmp.clear
    # Contorno escuro para a barra se ler contra qualquer chao.
    bmp.fill_rect(0, 0, VIDA_LARG, VIDA_ALT, Color.new(0, 0, 0, 190))
    # Verde ate metade, amarelo ate um quarto, vermelho abaixo — a mesma
    # leitura das caixas do jogo.
    cor = if viva * 2 > total
            Color.new(90, 220, 110)
          elsif viva * 4 > total
            Color.new(240, 210, 70)
          else
            Color.new(235, 80, 80)
          end
    bmp.fill_rect(1, 1, [fatia - 2, 0].max, VIDA_ALT - 2, cor)
    d[:fatia] = fatia
    d[:sp]
  rescue
    nil
  end

  def largar_barra_por_chave!(chave)
    d = (@barras || {}).delete(chave)
    return unless d && d[:sp]
    (d[:sp].bitmap.dispose rescue nil)
    (d[:sp].dispose rescue nil)
  rescue
    nil
  end

  def largar_barras_de_vida!
    (@barras || {}).keys.each { |k| largar_barra_por_chave!(k) }
    @barras = {}
  rescue
    @barras = {}
  end

  # Fica por compatibilidade: quem ja chamava isto continua a chamar, e agora
  # e a lista que trata do resto sozinha.
  def largar_barra_de_vida!(b)
    largar_barra_por_chave!(b.object_id) if b
  rescue
    nil
  end

  def marcar_interrogacao!(b, sp)
    # A do jogo, se existir mesmo na tabela; senao, o "?" desenhado a mao fica
    # como rede — e melhor um interrogacao feia do que um bicho grogue sem sinal
    # nenhum de que esta a espera de uma bola.
    if ($data_animations && $data_animations[ANIM_INTERROGACAO] rescue false)
      agora = Time.now.to_f
      if (agora - b[:balao_ate].to_f) > 2.0
        b[:balao_ate] = agora
        (b[:ev].animation_id = ANIM_INTERROGACAO) rescue nil
      end
      return
    end
    b[:balao] = nil if b[:balao] && (b[:balao].disposed? rescue true)
    unless b[:balao]
      bmp = Bitmap.new(24, 28)
      (pbSetSystemFont(bmp) rescue nil)
      (bmp.font.size = 22) rescue nil
      bmp.font.color = Color.new(0, 0, 0)
      bmp.draw_text(1, 1, 22, 26, "?", 1)
      bmp.font.color = Color.new(255, 230, 90)
      bmp.draw_text(0, 0, 22, 26, "?", 1)
      novo = Sprite.new(viewport_das_animacoes)
      novo.bitmap = bmp
      novo.ox = 12
      novo.oy = 28
      b[:balao] = novo
    end
    bal = b[:balao]
    bal.x = sp.x
    bal.y = sp.y - (sp.src_rect.height rescue 32) - 2 + (Math.sin(Time.now.to_f * 4.0) * 3).round
  rescue
    nil
  end

  def soltar_tonto!(b)
    curar_selvagem!(b)
    (b[:balao].bitmap.dispose rescue nil) if b[:balao]
    (b[:balao].dispose rescue nil) if b[:balao]
    b[:balao] = nil
    largar_barra_de_vida!(b)
    sp = sprite_de(b[:ev])
    (sp.angle = 0) rescue nil if sp
    animar_desmaio!(b[:ev])
    apagar_evento_bicho!(b[:id])
    b[:ev] = nil
    b[:tonto] = false
    bichos.delete(b)
    esquecer_vivos!
    fechar_se_acabou!
  rescue
    nil
  end

  def fechar_se_acabou!
    return unless bichos_vivos.empty? && bichos_tontos.empty?
    # ⚠️ CAMPO VAZIO NAO E VITORIA QUANDO HA UM TREINADOR DO OUTRO LADO.
    #
    # Este metodo assume que ficar sem inimigos no mapa significa que acabou —
    # e verdade contra selvagens. Contra um treinador nao: ele tem mais na
    # equipa, e o campo fica vazio por um instante entre um cair e o seguinte
    # entrar. Sem esta saida, derrubar os dois do campo encerrava a arena a
    # meio da batalha e o evento recebia uma vitoria que nao houve.
    #
    # Quem decide o fim de uma batalha de treinador e o `repor_do_treinador!`,
    # que e o unico que sabe se ainda ha fila.
    # ⚠️ A CAVERNA NUNCA "ACABA" POR FICAR VAZIA.
    #
    # Sem esta linha ela fechava-se sozinha no instante em que abria: entra-se
    # com zero inimigos no campo, e campo vazio le-se aqui como vitoria — o
    # `terminar_vitoria!` corria antes de o primeiro Pokemon nascer.
    #
    # Quem repoe o campo la e o semeador do MOD 192, ao ritmo dele. A saida da
    # caverna e pela corda ou pelo chao, nunca por se limpar a sala.
    return if caverna?
    if @directa
      actualizar_foco!
    elsif @caca
      @caca = false
      sair!
      pbMessage(_INTL("Área limpa!")) rescue nil
    else
      terminar_vitoria!
    end
  rescue
    nil
  end

  def matar_bicho!(b)
    return unless b
    # ⚠️ Contra a IA ele nao morre: fica grogue, a espera da bola. No PVP nao ha
    # nada para apanhar, e ai desaparece como sempre.
    # Num treinador o Pokemon tem dono: desmaia e sai, e o dono manda o
    # seguinte. Grogue e o estado de quem se pode apanhar.
    if treinador?
      matar_do_treinador!(b)
      return
    end
    # ⚠️ NA CAVERNA NAO HA GROGUE, PORQUE NAO HA BOLA.
    #
    # O estado grogue existe para dar tempo de atirar a bola. Sem captura ele
    # nao serve nada: ficava um corpo a balancar no meio do caminho, com uma
    # interrogacao por cima, ate o `TONTO_LIMITE` o levar. Aqui cai como cai no
    # PVP — e ao cair deixa o que trazia, no chao, a frente dele.
    if caverna?
      # ⚠️ COM O SERVIDOR A MANDAR, A MORTE E UM PEDIDO E NAO UMA DECISAO.
      #
      # A vida do bicho e dele. Isto diz-lhe quanto levou; ele decide se chega,
      # e se chegar manda o `cav_morte` a toda a gente. O corpo so desaparece
      # quando essa resposta voltar — que e o que impede dois jogadores de
      # matarem o mesmo Pokemon e de sortearem dois saques pelo mesmo cadaver.
      #
      # Enquanto a resposta nao chega o bicho fica de pe com a vida a zero na
      # nossa conta. E um instante, e e preferivel a fazer um funeral que pode
      # nao ser confirmado.
      if (AnilRaidCaverna.servidor_manda? rescue false)
        unless b[:pedido]
          b[:pedido] = true
          (AnilRaidCaverna.bati_no_bicho!(b[:sid], 9999) rescue nil)
        end
        return
      end
      # ⚠️ UM SO FUNERAL POR BICHO.
      #
      # Um feixe bate no mesmo alvo varias vezes no mesmo frame, e a lista de
      # vivos e um cache por frame: o segundo golpe encontrava-o ainda na lista,
      # via a vida a zero e mandava-o morrer OUTRA VEZ. Cada morte sorteia o
      # saque — era por isso que a caverna estava a encher-se de pocoes.
      return if b[:morto]
      b[:morto] = true
      dar_exp!(b)
      ex, ey, edir = nil, nil, nil
      if b[:ev]
        ex = b[:ev].x
        ey = b[:ev].y
        edir = (b[:ev].direction rescue 2)
      end
      animar_desmaio!(b[:ev])
      apagar_evento_bicho!(b[:id])
      b[:ev] = nil
      b[:hp] = 0
      esquecer_vivos!
      bichos.delete(b)
      esquecer_vivos!
      # ⚠️ QUEM MATA AVISA; QUEM SEMEOU E QUE SORTEIA.
      #
      # Se cada maquina sorteasse o saque do bicho que viu morrer, dois
      # jogadores na mesma caverna produziam o dobro dos itens — foi metade da
      # enxurrada de pocoes. O sorteio e uma decisao, e uma decisao tem de ter
      # um dono so.
      (AnilRaidCaverna.morreu!(b[:sid], b[:pkmn], ex, ey, edir) rescue nil) if ex
      fechar_se_acabou!
      actualizar_foco!
      return
    end
    unless pvp?
      dar_exp!(b)
      atordoar!(b)
      return
    end
    animar_desmaio!(b[:ev])
    # Derrotado sai do mapa, adoptado ou nao: nao faz sentido continuar ali um
    # Rattata que ja caiu.
    apagar_evento_bicho!(b[:id])
    b[:ev] = nil
    b[:hp] = 0
    esquecer_vivos!
    bichos.delete(b)
    esquecer_vivos!
    fechar_se_acabou!
    actualizar_foco!
  rescue
    nil
  end

  # ⚠️ TODO O DANO A UM BICHO PASSA POR AQUI.
  #
  # Antes o dano era `@hp_dele -= d` espalhado por seis sitios, e com varios
  # inimigos isso ia sempre bater no espelho em vez de bater em quem levou. Um
  # sitio so: acerta na ficha certa, aplica estado, empurra, e mata se for caso.
  def ferir_bicho!(b, d, mv = nil, nome = nil)
    return unless b
    d = d.to_i
    # ⚠️ DANO NEGATIVO CURA. (ver a nota do `dano`)
    if d < 0
      b[:hp] = [b[:hp] - d, b[:hp_max].to_i].min
      return
    end
    # ⚠️ A SASH E A BAND DECIDEM-SE AQUI, ANTES DE A VIDA DESCER.
    #
    # Sao os unicos itens cuja pergunta — "este golpe matava?" — so tem resposta
    # no instante do dano. Um tique nao serve: quando ele corresse, o bicho ja
    # estava morto.
    #
    # So com `mv`: a Sash nao salva de veneno nem de queimadura, e o dano de
    # estado chega aqui sem golpe nenhum.
    if mv && d > 0 && b[:pkmn]
      antes_do_item = d
      d = (AnilArenaItens.aguenta_o_golpe(b[:pkmn], b[:hp], b[:hp_max], d) rescue d)
      dizer(_INTL("Aguentou o golpe!")) if d < antes_do_item
    end
    # ⚠️ O ROUBO ACONTECE QUANDO O GOLPE ACERTA, E SO ENTAO.
    #
    # Poe-lo no disparo daria o item mesmo quando o golpe falha. Aqui ja se sabe
    # que bateu.
    if mv && d > 0
      (AnilArenaHabilidades.talvez_roubar!(mv, b[:pkmn], b[:ev]) rescue nil)
      # ⚠️ O DRENO E A UNICA FAMILIA DE EFEITO QUE SE PAGA A SI PROPRIA.
      #
      # Nove golpes, uma fraccao lida do `function_code`, e o resultado vai para
      # a vida de quem bateu. Como aqui nao se sabe QUEM bateu (pode ser eu ou o
      # ajudante), devolve-se o numero e quem chamou trata — e por isso isto
      # guarda em vez de aplicar.
      # ⚠️ DRENA-SE METADE DO DANO DADO, E NAO METADE DO DANO CALCULADO.
      #
      # Era isto que enchia a vida toda com uma pancada num bicho fraco. O
      # Giga Drain calcula 300 contra um Caterpie com 20 de vida: o Caterpie
      # morre com 20, mas a conta usava os 300 e devolvia 150 de cura.
      #
      # No jogo o dreno e sempre sobre o dano EFECTIVAMENTE causado, que nao
      # pode passar da vida que o alvo ainda tinha. Aparado aqui, aquele mesmo
      # golpe cura 10 — que e o que curaria numa batalha normal.
      #
      # Guarda-se tambem o numero para o Shell Bell, que precisa exactamente do
      # mesmo valor e nao tem outra forma de o saber.
      dado = [d, [b[:hp].to_i, 0].max].min
      @dano_feito_pendente = dado
      @dreno_pendente = (dado * (AnilArenaHabilidades.fraccao_de_dreno(mv) rescue 0.0)).round
      # ⚠️ E O CONTACTO RESPONDE A QUEM TOCOU.
      #
      # Static, Flame Body, Rough Skin: so disparam se o golpe for de contacto,
      # que e uma flag do PBS que a arena ja le.
      if (contacto?(mv) rescue false)
        est, chance, recuo = (AnilArenaHabilidades.ao_tocar(b[:pkmn]) rescue [nil, 0, 0.0])
        @contacto_pendente = [est, chance, recuo]
      else
        @contacto_pendente = nil
      end
      # O dono foi marcado por quem lancou o golpe (`@dono_do_golpe`). Sem
      # marca, assume-se que fui eu — que e o caso da esmagadora maioria.
      recolher_troco!(@dono_do_golpe || :eu)
    end
    b[:hp] = [b[:hp] - d, 0].max
    esquecer_vivos!
    # ⚠️ UM SELVAGEM COM ZERO DE VIDA NO MAPA REBENTA A BATALHA NORMAL.
    #
    # Numa batalha selvagem o motor faz `@sideSizes = [contagem_selvagem,
    # contagem_selvagem]` — o lado selvagem decide o tamanho DOS DOIS. Um
    # Pokemon de spawn com a vida a zero conta como zero, e o jogo tenta montar
    # uma batalha 0x0 e rebenta. Foi o erro do evento 8130.
    #
    # A vida da arena e minha e pode chegar a zero (e assim que ele fica
    # grogue); a vida do POKEMON que fica no mundo nunca desce abaixo de 1.
    (b[:pkmn].hp = [b[:hp], 1].max) rescue nil
    # ⚠️ Quem dorme acorda com a pancada. Sem isto, adormecer era uma sentenca:
    # o alvo ficava preso ate o tempo acabar e nao havia como o salvar.
    b[:estado] = nil if d > 0 && b[:estado] == :adormecido
    aplicar_estado_no_bicho!(b, mv.id) if mv && (d > 0 || golpe_de_estado?(mv))
    # ⚠️ O BRILHO ESTAVA PRESO AO EMPURRAO, E O EMPURRAO DESISTE MUITO.
    #
    # O `piscar_vermelho!` ja existia — mas dentro do `empurrar!`, que sai logo
    # a porta se o alvo estiver a meio de um salto. Levando pancada em
    # sequencia (um feixe, um multi-hit), o bicho nunca chegava a piscar: cada
    # golpe apanhava-o ainda no salto do anterior.
    #
    # Piscar e a resposta a LEVAR DANO, e nao a ser empurrado. Fica aqui, onde
    # o dano acontece, e vale para todos os caminhos de uma vez.
    piscar_vermelho!(b[:ev]) if d > 0 && b[:ev]
    # ⚠️ VENENO E QUEIMADURA NAO TEM MAO PARA EMPURRAR NINGUEM.
    #
    # O empurrao existe para dar peso a um golpe: quem leva uma cabecada anda
    # para tras. Mas o dano de estado corre de segundo a segundo, sozinho, e
    # empurrava na mesma — um Pokemon envenenado ia-se afastando aos saltinhos
    # sem ninguem lhe tocar. Isso nao e peso, e ruido.
    sem_mao = (mv.nil? || @dano_de_estado)
    empurrar!(b[:ev], $game_player, empurrao_de(mv)) if d > 0 && b[:ev] && !sem_mao
    narrar(mensagem_do_acerto(nome, d, mv)) if nome
    actualizar_foco!
    matar_bicho!(b) if b[:hp] <= 0
  rescue => e
    registar("falha a ferir: #{e.class}: #{e.message}")
  end

  # ⚠️ UM GOLPE DE AREA ATINGE QUEM ESTIVER LA, E NAO SO O ALVO.
  #
  # O Razor Leaf tem alvo `AllNearFoes` no PBS — na batalha por turnos bate em
  # todos os inimigos. Aqui isso e literal: rebenta e apanha tudo dentro de duas
  # casas do sitio onde caiu. E o que faz valer a pena juntar os selvagens antes
  # de disparar.
  def ferir_em_area!(cx, cy, raio, mv, nome, base_dano = nil)
    atingidos = bichos_vivos.select do |b|
      next false unless b[:ev]
      dx = b[:ev].x - cx
      dy = b[:ev].y - cy
      Math.sqrt((dx * dx) + (dy * dy)) <= raio
    end
    if atingidos.empty?
      narrar("#{nome}... errou!") if nome
      return 0
    end
    atingidos.each_with_index do |b, i|
      d = base_dano || dano_no_bicho(b, mv)
      ferir_bicho!(b, d, mv, (i.zero? ? nome : nil))
    end
    atingidos.length
  rescue => e
    registar("falha na area: #{e.class}: #{e.message}")
    0
  end

  def dano_no_bicho(b, mv)
    return 0 if golpe_de_estado?(mv)
    dano(@meu, b[:pkmn], mv)
  rescue
    0
  end

  # O empurrao cresce com a forca do golpe: um Hyper Beam atira para longe, um
  # Ember quase nao mexe.
  def empurrao_de(mv)
    return 1 unless mv
    pw = (GameData::Move.get(mv.id).power.to_i rescue 0)
    return 3 if pw >= 120
    return 2 if pw >= 80
    1
  rescue
    1
  end

  # Anima daqui a `atraso` frames, na casa dada. E o que da a sensacao de o
  # golpe ter percorrido a distancia.
  def adiar_animacao!(anim, x, y, atraso)
    @adiadas ||= []
    @adiadas << [(Graphics.frame_count rescue 0) + atraso.to_i, anim.to_i, x.to_i, y.to_i]
  rescue
    nil
  end

  def correr_adiadas!
    return if @adiadas.nil? || @adiadas.empty?
    agora = (Graphics.frame_count rescue 0)
    prontas = @adiadas.select { |a| a[0] <= agora }
    return if prontas.empty?
    @adiadas -= prontas
    prontas.each { |(_, anim, x, y)| tocar_no_chao!(anim, x, y) }
  rescue
    @adiadas = []
  end

  # A casa a `passos` de distancia na direccao em que o jogador olha.
  def casa_a_frente(passos = 1)
    x = $game_player.x
    y = $game_player.y
    case $game_player.direction
    when 2 then y += passos
    when 8 then y -= passos
    when 4 then x -= passos
    when 6 then x += passos
    end
    [x, y]
  rescue
    [$game_player.x, $game_player.y]
  end

  # ⚠️ AS ANIMACOES DE GOLPE NAO ESTAO NO $data_animations.
  #
  # Esta foi a razao de nada aparecer, e nao se via porque nao havia erro
  # nenhum. O `$data_animations` e carregado de `Animations.rxdata` — as
  # animacoes de MAPA (relva a mexer, o efeito do Surf). As animacoes de golpe
  # vivem em `PkmnAnimations.rxdata`, um ficheiro a parte, que so a batalha
  # carrega.
  #
  # O `move2anim.dat` da um indice para a SEGUNDA tabela. Ao por esse numero no
  # `animation_id`, o motor ia buscá-lo a PRIMEIRA: ou nao existia (nil, e o
  # `animation(nil)` nao faz nada nem se queixa) ou era uma animacao qualquer
  # sem relacao com o golpe.
  #
  # Por isso o `animation_id` deixa de servir: ele so sabe indexar a tabela do
  # mapa. Carrega-se o ficheiro dos golpes uma vez e chama-se o `animation` do
  # proprio sprite com o OBJECTO, que e o que o RPG::Sprite quer de qualquer
  # maneira.
  # ⚠️ O FICHEIRO NAO E UM ARRAY, E EU DEITEI-O FORA POR ISSO.
  #
  # O log apanhou-me em flagrante: "carregado: 1550 entradas" e, na linha
  # seguinte, "VAZIO ou nao carregou". As duas eram minhas. Eu media o tamanho
  # com `length` — que funciona em Array e em Hash — e a seguir fazia
  #
  #     @anims_golpe = [] unless @anims_golpe.is_a?(Array)
  #
  # O `PkmnAnimations.rxdata` do Essentials v21 nao e um Array: as animacoes vem
  # numa coleccao indexada por id. O `is_a?(Array)` dava falso e eu substituia
  # 1550 animacoes por uma lista vazia, um passo depois de as ter carregado.
  #
  # O que interessa nao e a classe, e saber responder a `[]`. E o que se exige
  # agora.
  def animacoes_de_golpe
    return @anims_golpe if @anims_golpe
    begin
      carregado = load_data("Data/PkmnAnimations.rxdata")
      tamanho = (carregado.respond_to?(:length) ? carregado.length : "?")
      registar("PkmnAnimations: #{carregado.class} com #{tamanho} entradas, indexavel=#{carregado.respond_to?(:[])}")
      @anims_golpe = carregado.respond_to?(:[]) ? carregado : []
    rescue => e
      registar("PkmnAnimations NAO carregou: #{e.class}: #{e.message}")
      @anims_golpe = []
    end
    @anims_golpe
  end

  # ⚠️ MEIA CASA NAO E METADE DE UM BONECO.
  #
  # As duas pontas de um golpe eram tiradas com `screen_y - TILE_HEIGHT / 2`, ou
  # seja, 16 pixeis acima dos pes. Isso e metade de uma CASA — e so por acaso e
  # que e metade de alguma coisa desenhada.
  #
  # Os bonecos desta arena sao Pokemon, e as folhas deles nao tem 32 px de alto:
  # um Onix, um Gyarados, um Dragonite chegam ao dobro ou ao triplo. O golpe
  # saia sempre dos tornozelos de quem o dava e ia aos tornozelos do outro,
  # enquanto na oficina ele estava afinado de centro a centro. Era esta a
  # diferenca que sobrava depois de tudo o resto estar direito.
  #
  # O `Sprite_Character` ja sabe a altura do quadro: ele poe `oy` na altura
  # inteira (o boneco assenta nos pes) e desenha em `screen_y`. Metade do `oy` e
  # o centro verdadeiro daquele boneco, seja ele do tamanho que for.
  #
  # O marcador fica de fora. Ele nao e um boneco — e uma casa do chao com um
  # grafico invisivel por cima, so para o motor o deixar tocar animacoes. Subir
  # meio Pikachu a um impacto no chao punha-o a flutuar.
  # ⚠️ NAO SE CALCULA ONDE O BONECO ESTA. PERGUNTA-SE AO SPRITE QUE O DESENHA.
  #
  # Eu andava a refazer a conta do motor: `screen_x`, `screen_y`, e uma altura
  # tirada do `src_rect`. Refazer uma conta e prometer que ela vai ser igual a
  # do outro lado — e nao e, porque o `Sprite_Character` mete pelo meio coisas
  # que o `screen_x/y` sozinhos nao sabem:
  #
  #   x_offset / y_offset   o balanco de quem anda, o salto, o empurrao
  #   bush_depth            afunda o boneco na erva alta
  #   oy                    muda com a folha; nem todos os Pokemon tem 32 px
  #
  # Dai as duas queixas, que sao a mesma: o golpe saia ao lado do lancador, e a
  # mira "orbitava" o inimigo em vez de ficar quieta nele. Nenhuma das duas era
  # aleatoria — era a minha conta e a do motor a discordarem um bocadinho, e a
  # discordarem de forma diferente a cada frame conforme o boneco andava.
  #
  # O sprite ja tem a resposta certa: `sp.x` e o pixel onde ele esta desenhado,
  # e `sp.y - sp.oy / 2` e o meio do corpo, porque o `oy` e a altura inteira do
  # quadro (o boneco assenta nos pes). Nao ha nada a recalcular e nada que possa
  # divergir.
  #
  # A conta antiga fica como rede, para quando o sprite ainda nao existe — o
  # primeiro frame de um bicho acabado de nascer, por exemplo.
  def centro_do_boneco(character)
    return [0, 0] unless character
    if (character.id rescue nil) != ID_MARCADOR
      sp = sprite_de(character)
      if sp && !(sp.disposed? rescue true)
        alto = (sp.oy rescue 0).to_i
        alto = Game_Map::TILE_HEIGHT if alto <= 0
        return [(sp.x rescue 0).to_i, (sp.y rescue 0).to_i - (alto / 2)]
      end
      # ⚠️ UM BICHO QUE CAIU AINDA ESTA NO ECRA, E AINDA E O ALVO.
      #
      # Quando a vida chega a zero, o evento sai do mapa — e com ele o
      # `Sprite_Character`. Mas o boneco nao desaparece: o `animar_desmaio!`
      # fica com um sprite proprio mais meio segundo, a dar um salto para tras e
      # a desvanecer.
      #
      # Sem isto, tudo o que estava apontado a ele congelava no sitio onde ele
      # estava, enquanto se via o corpo a ser atirado para longe dali. Como
      # ESTE metodo e por onde passam todas as ancoras — o motor novo, as pontas
      # do feixe, a mira — arranja-se uma vez e vale para todos.
      corpo = (@desmaios || []).find { |x| x[:ev] && x[:ev].equal?(character) }
      if corpo
        csp = corpo[:sp]
        if csp && !(csp.disposed? rescue true)
          calto = (csp.oy rescue 0).to_i
          calto = Game_Map::TILE_HEIGHT if calto <= 0
          return [(csp.x rescue 0).to_i, (csp.y rescue 0).to_i - (calto / 2)]
        end
      end
    end
    [(character.screen_x rescue 0),
     (character.screen_y rescue 0) - (Game_Map::TILE_HEIGHT / 2)]
  rescue
    [(character.screen_x rescue 0),
     (character.screen_y rescue 0) - (Game_Map::TILE_HEIGHT / 2)]
  end

  # O Sprite_Character que desenha um dado character. E preciso porque o
  # `animation` e um metodo do SPRITE, nao do character.
  # ⚠️ O JOGADOR NUNCA ESTEVE NO `character_sprites`, E ISTO DEVOLVIA NIL A VIDA
  # INTEIRA PARA ELE.
  #
  # O `Spriteset_Map#initialize` constroi a lista a partir de UMA coisa so:
  #
  #     @map.events.keys.sort.each { |i| @character_sprites.push(Sprite_Character.new(...)) }
  #
  # Eventos. So eventos. O boneco do jogador vive noutro sitio — no
  # `Spriteset_Global`, num `@playersprite` proprio, e e por isso que ele
  # continua desenhado quando se muda de mapa.
  #
  # Portanto `sprite_de($game_player)` respondia `nil` SEMPRE, e como toda a
  # gente aqui escreve `if sp`, nunca houve um erro — houve coisas que
  # simplesmente nao aconteciam:
  #
  #   o bambear de quem cai   o selvagem bambeia (e evento), eu nao. Foi assim
  #                           que isto apareceu: "nao balancou igual os
  #                           selvagens depois de derrotados".
  #   o tombo e o empurrao    o `correr_efeitos_do_corpo!` desistia de mim no
  #                           primeiro `unless sp`.
  #   o centro do meu boneco  o `centro_do_boneco` caia na conta de recurso, a
  #                           que a nota dele proprio diz que diverge da do
  #                           motor — e e a ancora de TODAS as animacoes.
  #
  # Uma pergunta a mais, e no sitio certo: o jogador primeiro, porque e o unico
  # que nao esta na lista dos outros.
  def sprite_de(character)
    return nil unless character && $scene.is_a?(Scene_Map)
    g = ($scene.spritesetGlobal rescue nil)
    if g && g.respond_to?(:playersprite)
      psp = (g.playersprite rescue nil)
      if psp && !(psp.disposed? rescue true) && ((psp.character == character) rescue false)
        return psp
      end
    end
    conj = ($scene.spriteset($game_map.map_id) rescue nil) || ($scene.spriteset rescue nil)
    return nil unless conj && conj.respond_to?(:character_sprites)
    conj.character_sprites.find { |sp| (sp.character == character rescue false) }
  rescue
    nil
  end

  #-----------------------------------------------------------------------------
  # O MOTOR DAS ANIMACOES DE GOLPE
  #
  # ⚠️ ELAS NAO SAO RPG::Animation, E POR ISSO O `animation` NUNCA IA FUNCIONAR.
  #
  # O `PkmnAnimations.rxdata` traz uma `PBAnimations` — uma coleccao propria do
  # Essentials — cheia de `PBAnimation`. O `RPG::Sprite#animation` do motor do
  # RPG Maker nao sabe ler esse formato: quem o toca e o `PBAnimationPlayerX`,
  # que e a "engine que nao estavamos a conseguir capturar".
  #
  # (E ha uma armadilha a mais: `PBAnimations < Array`, mas os dados vivem num
  # `@array` interno. Ela sobrepoe `length` e `[]` e NAO sobrepoe `empty?` —
  # portanto `length` da 1550 e `empty?` da true ao mesmo tempo. Foi assim que
  # eu deitei fora a tabela logo a seguir a carrega-la.)
  #
  # O jogador precisa de uma "cena" com `viewport` e `sprites["pokemon_N"]`, e
  # de dois lutadores com `index`. Nada disso existe no mapa — constroi-se aqui.
  #
  # ⚠️ OS SPRITES DE ANCORA SAO POSTICOS, E DE PROPOSITO.
  #
  # O jogador usa `@animsprites[0] = @usersprite` e MEXE nesse sprite (abana-o,
  # desloca-o, muda-lhe o tom). Em batalha e o que se quer. No mapa, dar-lhe o
  # `Sprite_Character` verdadeiro deixaria o boneco do jogador deslocado ou
  # colorido depois do golpe. Por isso criam-se dois sprites invisiveis, do
  # tamanho do boneco, so para servir de ponto de referencia.
  #-----------------------------------------------------------------------------
  class Lutador
    attr_reader :index
    def initialize(i); @index = i; end
    # O jogador chama coisas do battler (o grito, o pokemon). Nada disso existe
    # aqui, e devolver nil e melhor do que rebentar a meio de uma animacao.
    def method_missing(*_a); nil; end
    def respond_to_missing?(*_a); true; end
  end

  class CenaFalsa
    attr_reader :viewport, :sprites
    def initialize(viewport); @viewport = viewport; @sprites = {}; end
    def method_missing(*_a); nil; end
    def respond_to_missing?(*_a); true; end
  end

  # ⚠️ ESTAS SOMAM-SE A ANIMACAO. NAO A SUBSTITUEM.
  #
  # A receita do percurso TROCA o que voa por particulas — la nao ha animacao
  # nenhuma a proteger, so uma bola. Aqui ha: a animacao do golpe continua a
  # ser desenhada tal e qual, e estas partem-lhe por cima. Substitui-la era
  # deitar fora o desenho que se veio afinar no editor.
  #
  # Nascem da mesma celula representativa que o arremesso usa (o `cartao`), com
  # o bitmap PARTILHADO: seis particulas custam seis posicoes por frame e nao
  # seis recortes. E por isso tambem que nenhuma delas pode deitar fora o
  # bitmap — a segunda apagava o que a primeira ainda usa.
  #-----------------------------------------------------------------------------
  # AS PARTICULAS DO ANIMADOR NOVO
  #
  # ⚠️ DUAS FORMAS DE REBENTAR, E A DIFERENCA E O QUE SE COPIA.
  #
  #   normal    copia-se UMA celula representativa da animacao (o "cartao") e
  #             fazem-se N dela. E barato e serve para faiscas e estilhacos.
  #
  #   inteira   copiam-se N execucoes da ANIMACAO TODA, cada uma afastada,
  #             rodada e encolhida pela receita. Um Razor Leaf com cinco folhas
  #             a girar em vez de cinco recortes de uma folha parada.
  #
  # A segunda nao precisou de motor novo: o `AnilArenaAnimador` ja sabe tocar a
  # animacao presa a um boneco, e ganhou so um desvio por copia. Toda a conta de
  # onde cada copia esta e a MESMA do `dispor_particulas` que o editor mostra —
  # se fosse outra, o editor passava a mentir.
  #-----------------------------------------------------------------------------
  COPIAS_INTEIRAS_MAX = 6   # seis animacoes ao mesmo tempo ja e muito desenho

  def soltar_particulas_do_animador!(ef, anim, ancora, de)
    r = receita_final_da_anim(anim)
    return unless receita_vale?(r)
    n = receita_normal(r)
    # O rumo do golpe, guardado agora: de quem lanca para quem leva. Guardado
    # porque daqui a meio segundo o alvo pode ja nao estar la — e um rumo que se
    # recalcula a cada frame faz o rebentamento girar sozinho.
    vx, vy = rumo_entre(de, ancora)
    if n["inteira"]
      inteiras_do_animador!(ef, anim, ancora, r, vx, vy)
    else
      ax, ay = (centro_do_boneco(ancora) rescue
                [(ancora.screen_x rescue 0), (ancora.screen_y rescue 0) - 16])
      soltar_particulas_finais!(ef, anim, ax, ay, ancora)
      d = (@finais_de || {})[ef]
      if d
        d[:vx] = vx
        d[:vy] = vy
        # ⚠️ Coloca-se JA. O `sprite_do_projectil` nasce na coordenada crua da
        # celula — que e a do palco da batalha — e so o primeiro `mover` o traz
        # para o mapa. Sem esta linha via-se um piscar no canto errado do ecra.
        mover_particulas_finais!(ef)
      end
    end
  rescue => e
    registar("falha nas particulas do animador: #{e.class}: #{e.message}")
  end

  def rumo_entre(de, ate)
    ax, ay = (centro_do_boneco(ate) rescue [0, 0])
    bx, by = (centro_do_boneco(de) rescue [0, 0])
    vx = (ax - bx).to_f
    vy = (ay - by).to_f
    n = Math.sqrt((vx * vx) + (vy * vy))
    return [vx / n, vy / n] if n > 0.001
    # Sem distancia entre os dois (um golpe sobre o proprio), o rumo e a cara.
    case ((de.direction rescue 2))
    when 8 then [0.0, -1.0]
    when 4 then [-1.0, 0.0]
    when 6 then [1.0, 0.0]
    else        [0.0, 1.0]
    end
  rescue
    [1.0, 0.0]
  end

  def inteiras_do_animador!(ef, anim, ancora, receita, vx, vy)
    n = receita_normal(receita)["quantas"].to_i
    n = COPIAS_INTEIRAS_MAX if n > COPIAS_INTEIRAS_MAX
    cfg = (palco_da_anim(anim) rescue nil)
    copias = [ef]
    # ⚠️ O ORIGINAL CONTA COMO A PRIMEIRA COPIA.
    #
    # Ele ja esta a tocar e ja tem a ancora certa; faze-lo de lado e deixa-lo
    # parado no meio dava N+1 desenhos, com um deles sempre no centro.
    (n - 1).times do
      c = (AnilArenaAnimador.tocar!(anim, ancora, cfg, 0) rescue nil)
      next unless c
      (c.mudo = true) rescue nil
      copias << c
    end
    return if copias.length <= 1
    (@inteiras ||= []) << {
      :copias => copias, :receita => receita, :nascido => Time.now.to_f,
      :vx => vx, :vy => vy
    }
    correr_inteiras!
  rescue
    nil
  end

  # Corre a cada frame, ao lado do `AnilArenaAnimador.correr!`.
  def correr_inteiras!
    return if @inteiras.nil? || @inteiras.empty?
    agora = Time.now.to_f
    @inteiras.each do |d|
      postos = dispor_particulas(d[:receita], agora - d[:nascido].to_f, d[:vx], d[:vy])
      d[:copias].each_with_index do |c, i|
        next unless c && (c.vivo? rescue false)
        posto = postos[i]
        next unless posto
        (c.desvio_extra = [posto[:dx].round, posto[:dy].round,
                           posto[:escala].to_f, posto[:angulo].to_i,
                           posto[:opacidade].to_i]) rescue nil
      end
    end
    # Um conjunto morre quando nenhuma das copias dele continua viva.
    @inteiras.reject! { |d| d[:copias].none? { |c| (c.vivo? rescue false) } }
  rescue
    @inteiras = []
  end

  def largar_inteiras!
    (@inteiras || []).each do |d|
      (d[:copias] || []).each { |c| (c.largar! rescue nil) }
    end
    @inteiras = []
  rescue
    @inteiras = []
  end

  def soltar_particulas_finais!(jogador, anim, ax, ay, quem)
    r = receita_final_da_anim(anim)
    unless receita_vale?(r)
      # Diz-se quando ha receita mas ela nao pede nada: senao fica a parecer
      # que o jogo a ignorou, quando na verdade ela esta vazia.
      @sem_receita ||= {}
      unless @sem_receita[anim]
        @sem_receita[anim] = true
        registar("particulas finais: anim #{anim} sem receita util") if r
      end
      return
    end
    n = receita_normal(r)["quantas"].to_i
    modelo = sprite_do_projectil(anim.to_i)
    unless modelo
      # Sem celula representativa nao ha de que fazer particulas.
      registar("particulas finais: anim #{anim} nao deu cartao")
      return
    end
    sprites = [modelo]
    (n - 1).times do
      c = Sprite.new(viewport_das_animacoes)
      c.bitmap = modelo.bitmap        # partilhado de proposito
      c.src_rect = (modelo.src_rect.dup rescue nil)
      c.ox = modelo.ox
      c.oy = modelo.oy
      c.blend_type = modelo.blend_type
      c.zoom_x = modelo.zoom_x
      c.zoom_y = modelo.zoom_y
      sprites << c
    end
    (@finais_de ||= {})[jogador] = {
      :sprites => sprites, :receita => r, :nascido => Time.now.to_f,
      :x => ax, :y => ay, :zx => modelo.zoom_x, :zy => modelo.zoom_y,
      :quem => quem,
      :x0 => (quem ? (quem.screen_x rescue 0) : 0),
      :y0 => (quem ? (quem.screen_y rescue 0) : 0)
    }
    registar("particulas finais: #{sprites.length} em anim #{anim}")
  rescue => e
    registar("falha nas particulas finais: #{e.class}: #{e.message}")
  end

  # Corre a CADA frame, e nao a cada quadro da animacao: estas nao sao
  # reescritas pelo motor, portanto podem andar aos 60 em vez dos 20.
  def mover_particulas_finais!(jogador)
    d = (@finais_de || {})[jogador]
    return unless d
    # Acompanham quem levou o golpe, tal como a animacao acompanha (a camara
    # tambem anda, e sem isto elas ficavam coladas ao ecra).
    ox = 0
    oy = 0
    if d[:quem]
      ox = ((d[:quem].screen_x rescue d[:x0]) - d[:x0])
      oy = ((d[:quem].screen_y rescue d[:y0]) - d[:y0])
    end
    # ⚠️ O RUMO E O DO INSTANTE DO GOLPE, E NAO O DE AGORA.
    #
    # Isto media, a cada frame, do `$game_player` ate ao ponto do rebentamento.
    # Duas coisas corriam mal: quem lanca nem sempre sou eu (o ajudante e os
    # selvagens tambem batem), e eu ando enquanto o rebentamento decorre — o
    # leque das particulas rodava sozinho atras de mim.
    #
    # Quem sabe o rumo e quem disparou, no momento em que disparou. Guarda-se
    # la (`:vx`, `:vy`); aqui so se le. A conta antiga fica como rede para os
    # caminhos que ainda nao o guardam.
    vx = d[:vx]
    vy = d[:vy]
    if vx.nil? || vy.nil?
      vx = (d[:x] - ($game_player.screen_x rescue 0)).to_f
      vy = (d[:y] - ($game_player.screen_y rescue 0)).to_f
      nn = Math.sqrt((vx * vx) + (vy * vy))
      if nn > 0.001
        vx /= nn
        vy /= nn
      else
        vx = 1.0
        vy = 0.0
      end
    end
    postos = dispor_particulas(d[:receita], Time.now.to_f - d[:nascido].to_f, vx, vy)
    return if postos.empty?
    d[:sprites].each_with_index do |sp, i|
      next unless sp && !(sp.disposed? rescue true)
      posto = postos[i]
      unless posto
        sp.visible = false
        next
      end
      sp.visible = true
      sp.x = d[:x] + ox + posto[:dx].round
      sp.y = d[:y] + oy + posto[:dy].round
      sp.angle = posto[:angulo]
      sp.opacity = posto[:opacidade]
      sp.zoom_x = d[:zx] * posto[:escala]
      sp.zoom_y = d[:zy] * posto[:escala]
    end
  rescue
    nil
  end

  def largar_particulas_finais!(jogador)
    d = ((@finais_de || {}).delete(jogador))
    return unless d
    (d[:sprites] || []).each do |sp|
      next unless sp
      (sp.bitmap = nil) rescue nil     # o bitmap e partilhado: so o sprite morre
      (sp.dispose rescue nil) unless (sp.disposed? rescue true)
    end
  rescue
    nil
  end

  def viewport_das_animacoes
    return @vp_anim if @vp_anim && !(@vp_anim.disposed? rescue true)
    @vp_anim = Viewport.new(0, 0, Graphics.width, Graphics.height)
    # Acima do mapa e dos bonecos, abaixo do painel da arena (99998).
    @vp_anim.z = 99990
    @vp_anim
  end

  # ⚠️ ANCORAS NOVAS A CADA GOLPE, E NAO DUAS PARTILHADAS.
  #
  # Havia duas ancoras reutilizadas (:user e :alvo) que eu reposicionava a cada
  # ataque. Uma animacao ainda a decorrer ficava agarrada a essas ancoras — e
  # quando o Pokemon andava, o Rock Slide andava com ele. As pedras tem de cair
  # onde foram lancadas.
  #
  # Agora cada animacao leva o seu par, criado no momento e deitado fora com
  # ela. Ficam paradas no sitio, que e o que uma pedra a cair faz.
  def sprite_ancora(chave, character)
    @ancoras ||= {}
    sp = Sprite.new(viewport_das_animacoes)
    sp.bitmap = Bitmap.new(64, 64)   # tamanho tipico de um boneco; so ancora
    sp.opacity = 0
    (@ancoras[chave] ||= []) << sp
    if character
      # ⚠️ O `screen_y` de um character e nos PES. As animacoes sao pensadas
      # para o centro do corpo, portanto sobe-se meio boneco — senao tudo sai
      # desenhado no chao.
      cx, cy = centro_do_boneco(character)
      sp.x = cx
      sp.y = cy
      sp.ox = 32
      sp.oy = 32
    end
    sp
  rescue
    nil
  end

  def limpar_animacoes!
    (AnilArenaAnimador.limpar! rescue nil)
    largar_inteiras!
    largar_barras_de_vida!
    (AnilArenaHabilidades.limpar! rescue nil)
    (AnilArenaEvolucao.limpar! rescue nil)
    # As particulas do rebentamento morrem ANTES dos jogadores: elas sao
    # indexadas por jogador, e depois de o mapa se ir embora ja nao ha quem as
    # va buscar. Um sprite esquecido aqui fica no ecra para sempre.
    (@finais_de || {}).keys.each { |p| largar_particulas_finais!(p) }
    @finais_de = {}
    (@jogadores_anim || []).each { |p| (p.dispose rescue nil) }
    @jogadores_anim = []
    (@ancoras || {}).each_value do |lista|
      Array(lista).each { |sp| next unless sp; (sp.bitmap.dispose rescue nil); (sp.dispose rescue nil) }
    end
    @ancoras = {}
    @ancoras_de = {}
    @seguir_de = {}
    @feitio_de = {}
    limpar_projecteis!
    # Os bitmaps dos cartoes sao nossos (deanimate faz uma copia), portanto
    # deitam-se fora aqui — mas so DEPOIS dos projecteis, que os partilham.
    (@cartoes || {}).each_value { |c| (c[:bmp].dispose rescue nil) if c }
    @cartoes = {}
    # As caixas sao indexadas pelo object_id do bitmap, que o Ruby reaproveita
    # depois de o deitar fora: ficar com elas daria recortes de outra folha.
    @caixas = {}
    (@vp_anim.dispose rescue nil) if @vp_anim && !(@vp_anim.disposed? rescue true)
    @vp_anim = nil
    (@vp_chao.dispose rescue nil) if @vp_chao && !(@vp_chao.disposed? rescue true)
    @vp_chao = nil
    # A cena morre com o viewport dela. Ver a nota no tocar_no_character!.
    @cena_anim = nil
  rescue
    nil
  end

  # ⚠️ AS ANIMACOES TRAZEM CENARIO, E NO MAPA O CENARIO JA EXISTE.
  #
  # Muitos golpes (Giga Drain, Earthquake, Solar Beam) escurecem o ecra inteiro
  # ou poem uma imagem de fundo por tras dos combatentes. Num palco de batalha
  # isso e o efeito; por cima do mapa e uma cortina que tapa a cidade e estraga
  # a ideia toda de estarmos a lutar NO mundo.
  #
  # O jogador de animacoes guarda quatro planos de ecra inteiro — cor e imagem,
  # a frente e atras. Zeram-se a CADA FRAME, e nao so uma vez: o proprio
  # `update` volta a acender-lhes a opacidade quando a animacao o manda. O que
  # sobra sao os sprites do golpe, que e exactamente o que se quer ver.
  PLANOS_DE_FUNDO = [:@bgColor, :@bgGraphic, :@foColor, :@foGraphic].freeze

  # Um fotograma que ocupa quase o ecra todo nao e o golpe: e cenario.
  LIMIAR_ECRA = 0.6

  def apagar_fundo!(jogador)
    PLANOS_DE_FUNDO.each do |iv|
      plano = (jogador.instance_variable_get(iv) rescue nil)
      next unless plano
      (plano.opacity = 0) rescue nil
    end

    # ⚠️ NEM TODO O FUNDO VEM NOS PLANOS.
    #
    # O Moonblast (e outros) desenha o clarao como um FOTOGRAMA normal, esticado
    # ate cobrir o ecra. Esse nao passa pelos quatro planos e sobrevivia a
    # limpeza — via-se a tela toda a mudar de cor por cima da cidade.
    #
    # Nao ha como distinguir "cenario" de "efeito" nos dados; o que se pode
    # medir e o tamanho. Um fotograma que cobre mais de 60% do ecra nao e uma
    # pedra nem uma folha, e escondê-lo deixa o resto do golpe intacto.
    sprites = (jogador.instance_variable_get(:@animsprites) rescue nil)
    return unless sprites.is_a?(Array)
    largura_max = Graphics.width * LIMIAR_ECRA
    altura_max  = Graphics.height * LIMIAR_ECRA
    # Os dois primeiros sao as ancoras (utilizador e alvo) e ja estao invisiveis.
    sprites.each_with_index do |sp, i|
      next if i < 2
      next unless sp && !(sp.disposed? rescue true)
      next unless sp.visible
      larg = ((sp.src_rect.width rescue 0) * (sp.zoom_x rescue 1)).abs
      alt  = ((sp.src_rect.height rescue 0) * (sp.zoom_y rescue 1)).abs
      sp.visible = false if larg >= largura_max && alt >= altura_max
    end
  rescue
    nil
  end

  # ⚠️ ANDEI A APAGAR ANIMACOES UMA A UMA. O PROBLEMA E DE TAMANHO, E E DE TODAS.
  #
  # Fui tirando a animacao do Razor Leaf, depois a do Earthquake, depois a dos
  # feixes — e o Nasty Plot continuou gigante, porque nunca lhe toquei. Elas sao
  # TODAS desenhadas para um palco de 512x384 com dois combatentes grandes; por
  # cima de bonecos de 32 px, qualquer uma delas tapa o mapa.
  #
  # Em vez de as ir caçando uma a uma, poe-se um tecto: mede-se o maior
  # fotograma e, se passar de 88 px, encolhe-se a animacao INTEIRA — o desenho e
  # as posicoes — em volta de quem a lancou. Uma animacao encolhida a metade
  # continua a ser ela propria, so que a caber no mundo.
  #
  # E em volta da ANCORA, e nao do canto: encolher so o zoom deixava as peças
  # pequenas mas espalhadas pelo ecra todo, como se tivessem fugido umas das
  # outras.
  # ⚠️ O TECTO NAO PODE OLHAR SO PARA A MAIOR PECA.
  #
  # Media o maior fotograma e encolhia por ele — e isso castiga as animacoes
  # certas: um golpe feito de VINTE faiscas pequenas espalhadas ocupa meio ecra
  # e passava sem tocar, enquanto um golpe com uma peca so, grande mas sozinha,
  # era encolhido a metade sem precisar.
  #
  # O que interessa e quanto do ecra a coisa toda ocupa. Mede-se a mancha — o
  # rectangulo que cobre tudo o que esta visivel — e so se encolhe se ELA passar
  # do tamanho. Ha ainda um tecto por peca, mais largo, para o caso de uma so
  # imagem gigante; manda o mais apertado dos dois.
  # ⚠️ UM GOLPE QUE CAI DO CEU EM VARIOS SITIOS TEM DE OCUPAR ECRA.
  #
  # Com a mancha limitada a 190 px, o Thunder Shock — que sao varios raios a
  # cair espalhados — batia no tecto e era encolhido ao minimo, ficando um
  # chuvisco de nada. O tecto existe para nao tapar o mapa, e nao para achatar
  # o que e para ser grande: 280 px sao oito casas e meia, ainda se ve o mundo
  # por baixo. E o chao do encolhimento sobe para metade — abaixo disso ja nao
  # se percebe o que aconteceu.
  MANCHA_MAX_GOLPE  = 280.0   # px: a animacao inteira
  CELULA_MAX_GOLPE  = 150.0   # px: uma peca sozinha

  # ⚠️ ENCOLHER TUDO EM VOLTA DE QUEM LANCA ESTAVA ERRADO.
  #
  # Este tecto puxa TODAS as celulas para a ancora numero zero — a de quem
  # lanca. Como seguranca contra tapar o mapa serve, porque so precisa de
  # tornar a coisa mais pequena.
  #
  # Mas o editor nao faz isto. La cada celula encolhe em volta da SUA ancora: a
  # que esta presa ao alvo aperta-se em volta do alvo, a do ecra em volta do
  # meio do ecra. Foi por isso que a Folha Navalha ficou espalhada pelo mapa no
  # jogo e certinha na oficina — as folhas sao do alvo, e o jogo arrastava-as
  # todas para o Pokemon que as lancou.
  #
  # Portanto: quem tem tamanho escolhido no editor nao passa por aqui. O
  # `aplicar_feitio!` trata dele com as ancoras certas, e uma escolha explicita
  # ja e um tecto — nao precisa de outro por cima, e muito menos de um que
  # desloca as coisas.
  def encolher_animacao!(jogador)
    sprites = (jogador.instance_variable_get(:@animsprites) rescue nil)
    return unless sprites.is_a?(Array)
    ancora = sprites[0]
    return unless ancora && !(ancora.disposed? rescue true)
    maior = 0.0
    x1 = nil
    y1 = nil
    x2 = nil
    y2 = nil
    sprites.each_with_index do |sp, i|
      next if i < 2
      next unless sp && !(sp.disposed? rescue true) && sp.visible
      w = ((sp.src_rect.width rescue 0) * (sp.zoom_x rescue 1)).abs
      h = ((sp.src_rect.height rescue 0) * (sp.zoom_y rescue 1)).abs
      maior = w if w > maior
      maior = h if h > maior
      ex1 = sp.x - (w / 2.0)
      ey1 = sp.y - (h / 2.0)
      ex2 = sp.x + (w / 2.0)
      ey2 = sp.y + (h / 2.0)
      x1 = ex1 if x1.nil? || ex1 < x1
      y1 = ey1 if y1.nil? || ey1 < y1
      x2 = ex2 if x2.nil? || ex2 > x2
      y2 = ey2 if y2.nil? || ey2 > y2
    end
    return if x1.nil?
    mancha = [(x2 - x1), (y2 - y1)].max
    k_mancha = (mancha > MANCHA_MAX_GOLPE) ? (MANCHA_MAX_GOLPE / mancha) : 1.0
    k_peca   = (maior > CELULA_MAX_GOLPE) ? (CELULA_MAX_GOLPE / maior) : 1.0
    k = [k_mancha, k_peca].min
    k = 0.5 if k < 0.5

    # ⚠️ O TAMANHO DO EDITOR ENTRA AQUI, E SO PARA ENCOLHER.
    #
    # Eu tentei aplica-lo celula a celula no `aplicar_feitio!`, com a ancora de
    # cada foco, para copiar o que o editor faz. Em teoria era mais fiel; na
    # pratica desmanchou as animacoes todas e, pior, desligou este tecto — e
    # sem tecto o que era grande passou a ser gigantesco.
    #
    # Aqui e uma multiplicacao sobre um encolhimento que ja funciona ha muito.
    # Menos fiel ao editor, mas fiel ao jogo, que e o que se ve.
    cfg_e = ((@feitio_de || {})[jogador] || {})[:cfg]
    if cfg_e && cfg_e["escala"]
      e = cfg_e["escala"].to_f / 100.0
      e = 0.1 if e < 0.1
      e = 1.0 if e > 1.0     # so encolhe: aumentar tapa o mapa
      k *= e
    end

    return if k >= 0.999
    # ⚠️ NUM FEIXE, ENCOLHER AS POSICOES E ENCURTAR O ALCANCE.
    #
    # Este metodo aperta tudo em volta da ancora. Para uma explosao isso e o
    # que se quer. Para um feixe nao: as celulas dele SAO o comprimento, e
    # aperta-las a 66% deixa a chama a dois tercos do caminho.
    #
    # E o dano nao encolhe com ela — usa o `@feixe_alcance` inteiro. Uma chama
    # mais curta do que o dano e literalmente o "o desenho nao concorda com o
    # dano" que se anda a perseguir desde o principio desta ronda.
    #
    # Portanto num feixe encolhem-se as PECAS e deixa-se a linha em paz. O
    # `aplicar_feitio!` corre a seguir e repoe as posicoes dele de qualquer
    # maneira; o que aqui se evitava era mexer-lhes duas vezes.
    # ⚠️ QUEM TEM REMENDO JA E COLOCADO PELA REGRA DA OFICINA.
    #
    # Este metodo aperta as POSICOES em volta da ancora para o golpe nao tapar
    # o mapa. Isso e uma segunda colocacao por cima da primeira — e como a
    # oficina nao a faz, era mais uma fonte de divergencia entre o que se ve la
    # e o que se ve aqui.
    #
    # Nas animacoes com remendo encolhem-se so as PECAS (o zoom, que a oficina
    # tambem faz no `peca_transformada`) e deixa-se a colocacao ao feitio, que
    # ja aplica a `escala` do painel do sitio certo.
    cfg_f = ((@feitio_de || {})[jogador] || {})[:cfg]
    so_pecas = cfg_f ? true : false

    # ⚠️ ENCOLHER TUDO PARA QUEM LANCA ARRASTA O QUE E DO ALVO.
    #
    # Este tecto apertava todas as celulas em volta da ancora zero — a de quem
    # lanca. Para um golpe que sai de nos isso e certo. Para um que rebenta em
    # cima do inimigo nao: as celulas de foco 1 pertencem ao ALVO, e encolher
    # em volta do atacante puxa-as para o meio do caminho.
    #
    # O Rock Slide tem 100% de celulas de foco 1 e esta a 51% de tamanho: as
    # pedras caiam a meia distancia, "antes do Pokemon". Nao era a mira nem a
    # escala — era a ancora errada a fazer de centro.
    #
    # Agora cada celula encolhe em volta da SUA: foco 1 no alvo, o resto em quem
    # lanca. Sem dados das celulas (nao ha remendo, ou o quadro nao se leu),
    # mantem-se o de sempre — nunca fica pior do que estava.
    celulas_e = nil
    if (d_e = (@feitio_de || {})[jogador])
      q_e = (jogador.instance_variable_get(:@frame) rescue -1)
      celulas_e = (d_e[:obj][q_e] rescue nil) if q_e >= 0
      celulas_e = nil unless celulas_e.is_a?(Array)
    end

    ax = ancora.x
    ay = ancora.y
    alvo_sp = sprites[1]
    bx = (alvo_sp ? (alvo_sp.x rescue ax) : ax)
    by = (alvo_sp ? (alvo_sp.y rescue ay) : ay)

    sprites.each_with_index do |sp, i|
      next if i < 2
      next unless sp && !(sp.disposed? rescue true) && sp.visible
      sp.zoom_x = (sp.zoom_x rescue 1.0) * k
      sp.zoom_y = (sp.zoom_y rescue 1.0) * k
      next if so_pecas
      cx = ax
      cy = ay
      cel_e = (celulas_e ? celulas_e[i] : nil)
      if cel_e.is_a?(Array) && cel_e[AnimFrame::FOCUS].to_i == 1
        cx = bx
        cy = by
      end
      sp.x = cx + ((sp.x - cx) * k).round
      sp.y = cy + ((sp.y - cy) * k).round
    end
  rescue
    nil
  end

  # Desloca a animacao inteira pela distancia que o alvo andou no ecra desde que
  # ela comecou. Inclui a camara: se o mapa desliza, o `screen_x` do alvo muda e
  # a animacao vai com ele — que e o que se quer, porque ela e DELE.
  #-----------------------------------------------------------------------------
  # O FEITIO: o que o editor decidiu, aplicado quadro a quadro
  #
  # ⚠️ ISTO CORRE DEPOIS DE O MOTOR TER POSTO OS SPRITES.
  #
  # O `PBAnimationPlayerX` reescreve a posicao de cada sprite em cada quadro
  # novo. Mexer neles antes disso nao serve de nada; mexer TODOS os frames
  # tambem nao (ver a nota do `encolher_animacao!` — o zoom acumulava). O sitio
  # certo e este: uma vez por quadro da animacao, logo a seguir ao motor.
  #
  # A celula `i` da animacao corresponde ao sprite `i` do jogador — as duas
  # primeiras sao as ancoras, invisiveis.
  #-----------------------------------------------------------------------------
  FOCO_ECRA = 4

  # O centro da tela de batalha (512x384). E a ancora das celulas de foco 4 na
  # oficina (`Compositor.MEIO_DO_PALCO`).
  MEIO_PALCO_X = 256
  MEIO_PALCO_Y = 192

  # Ate que fraccao da linha uma celula ainda conta como "de quem lanca".
  # Ver a nota no laco do `aplicar_feitio!`.
  PRESO_DA_BOCA  = 0.15
  SOLTO_NA_LINHA = 0.32

  # ?? DESLIGADA ? E ISTO E UMA DECISAO, NAO UM ESQUECIMENTO.
  #
  # Alargar a rotacao a todos os modos tirava mesmo a deformacao por angulo,
  # que era real e esta medida na nota do `rodar_isto`. Mas mexia nas 1550
  # animacoes de uma vez, e o remedio saiu pior do que a doenca: as que ja
  # estavam boas por terem sido desenhadas para a diagonal do palco pioraram.
  #
  # A parte do desvio que se podia corrigir sem tocar em nenhuma delas era o
  # arredondamento do ponto de destino ? ate 3,5 graus conforme o angulo ? e
  # essa esta resolvida no `tocar_no_ponto!`, com a precisao da Pokebola.
  #
  # O codigo fica: a conta esta certa e testada, e se um dia se quiser um modo
  # NOVO que rode, e so pedi-lo. Ligar isto outra vez para os modos antigos e
  # que nao.
  ROTACAO_LIGADA = false

  # ⚠️ A COLOCACAO PELO FOCO DO PALCO, NUM SITIO SO.
  #
  # Ela e precisa em dois lugares: nos modos que nao sao feixe, e — dentro do
  # feixe — nas celulas que o "so a linha se deita" manda ficar direitas. Ter
  # a conta escrita duas vezes era garantir que uma delas ficava para tras no
  # proximo acerto, e foi isso que acabou de acontecer.
  #
  # E a regra do `_posicionar` do `desenho.py` quando ele NAO roda:
  #
  #     foco 1  preso ao ALVO         ancora = leva, base = (384, 96)
  #     foco 3  esticado entre os dois
  #     foco 4  do ECRA               fica no meio do ecra
  #     outro   preso a QUEM LANCA    ancora = quem, base = (128, 224)
  def pousar_por_foco!(sp, cel, d, foco, esc, dvx, dvy)
    cx = cel[AnimFrame::X].to_f
    cy = cel[AnimFrame::Y].to_f
    case foco
    when 1
      bx, by = Battle::Scene::FOCUSTARGET_X, Battle::Scene::FOCUSTARGET_Y
      anx, any = d[:ax], d[:ay]
    when 3
      odx = (Battle::Scene::FOCUSTARGET_X - Battle::Scene::FOCUSUSER_X).to_f
      ody = (Battle::Scene::FOCUSTARGET_Y - Battle::Scene::FOCUSUSER_Y).to_f
      tx = (odx.abs < 0.001) ? 0.0 : ((cx - Battle::Scene::FOCUSUSER_X) / odx)
      ty = (ody.abs < 0.001) ? 0.0 : ((cy - Battle::Scene::FOCUSUSER_Y) / ody)
      px = d[:ux] + (tx * (d[:ax] - d[:ux]))
      py = d[:uy] + (ty * (d[:ay] - d[:uy]))
      sp.x = (d[:ux] + ((px - d[:ux]) * esc) + dvx).round
      sp.y = (d[:uy] + ((py - d[:uy]) * esc) + dvy).round
      return
    when 4
      bx, by = MEIO_PALCO_X, MEIO_PALCO_Y
      anx, any = (Graphics.width / 2), (Graphics.height / 2)
    else
      bx, by = Battle::Scene::FOCUSUSER_X, Battle::Scene::FOCUSUSER_Y
      anx, any = d[:ux], d[:uy]
    end
    sp.x = (anx + ((cx - bx) * esc) + dvx).round
    sp.y = (any + ((cy - by) * esc) + dvy).round
  rescue
    nil
  end

  def aplicar_feitio!(jogador)
    d = (@feitio_de || {})[jogador]
    return unless d
    cfg = d[:cfg]
    sprites = (jogador.instance_variable_get(:@animsprites) rescue nil)
    return unless sprites.is_a?(Array)
    quadro = (jogador.instance_variable_get(:@frame) rescue -1)
    return if quadro < 0
    celulas = (d[:obj][quadro] rescue nil)
    return unless celulas.is_a?(Array)

    esconder_fundo = (cfg["sem_fundo"] ? true : false)
    dvx = (cfg["desvio_x"] || 0).to_i
    dvy = (cfg["desvio_y"] || 0).to_i
    # ⚠️ UM DESVIO A MAO NAO CORRIGE UMA ANIMACAO QUE ANDA.
    #
    # A folha de uma animacao nao e obrigada a estar desenhada em volta da
    # ancora — medido, 11 das 17 marcadas "alvo" nao estao. O arrasto do editor
    # soma o mesmo numero a todos os quadros: chega para uma animacao parada e
    # nao chega para uma que VARRE.
    #
    # O Wing Attack varre. As celulas dele nascem tres casas acima do alvo e
    # descem ate ele ao longo de doze quadros. Com o melhor arrasto possivel, o
    # primeiro quadro fica a 3,06 casas do bicho e o oitavo a 0,37 — centra-se
    # o meio e as pontas ficam de fora. Era o "segue tudo torto".
    #
    # O `eixo_quadros` e a outra escolha da oficina: uma correccao POR QUADRO,
    # que cola cada um a ancora. Mata o deslocamento da animacao e em troca
    # nenhum quadro fica fora. Quem edita escolhe qual dos dois quer; vazio
    # (o caso normal) isto nao faz nada.
    eixo = cfg["eixo_quadros"]
    if eixo.is_a?(Array) && quadro >= 0 && quadro < eixo.length
      par = eixo[quadro]
      if par.is_a?(Array) && par.length >= 2
        dvx += par[0].to_i
        dvy += par[1].to_i
      end
    end
    e_feixe = (cfg["modo"].to_s == "feixe")
    persegue = (e_feixe && cfg["feixe_persegue"])
    # A mesma escala da oficina: aplica-se ao DESVIO em relacao a ancora, e nao
    # a posicao absoluta — senao mudar o tamanho arrastava o golpe pelo ecra.
    esc = ((cfg["escala"] || 100).to_f / 100.0)
    esc = 0.1 if esc < 0.1

    # ⚠️ O MOTOR NAO RODA A ANIMACAO: ELE ESTICA-A. E ISSO DEFORMA POR ANGULO.
    #
    # O `transformPoint` mede cada eixo como fraccao e repoe-a NO MESMO EIXO.
    # A folha foi desenhada numa linha de 256 por -128 — dois para um, a -26,6
    # graus. So nesse angulo e que a conta nao deforma. Medido:
    #
    #     -30 graus -> 1,15x   (o angulo da folha; quase certo)
    #     +-45      -> 2,00x
    #     +-60      -> 3,46x
    #     +-75      -> 7,46x
    #       0 e 90  -> achatada
    #
    # O pior caso e a horizontal e a vertical — que num mapa em casas sao o caso
    # NORMAL, nao a excepcao. Era isto que fazia os golpes parecerem tortos e
    # fora de sitio conforme a posicao do inimigo.
    #
    # A rotacao nao tem esse defeito: e uniforme, e o angulo deixa de importar.
    # Ja estava escrita e testada — era so do feixe. Agora e de todos.
    #
    # Fica ligavel por golpe (`rodar`, ligado por omissao) para se poder
    # comparar lado a lado e desligar num golpe que fique pior.
    # O interruptor geral. Se a rotacao estragar mais do que arranja, poe-se
    # isto a false e o jogo volta exactamente ao esticao do motor, sem tocar em
    # mais nada ? os remendos por golpe ficam gravados a espera.
    # ⚠️ AS ANCORAS SAO LIDAS AGORA, E NAO NO INSTANTE DO DISPARO.
    #
    # Sao elas que fazem a animacao seguir quem lhe diz respeito: quem lanca em
    # `quem`, quem leva em `leva`. Uma fotografia tirada no disparo deixa o
    # golpe pendurado no mapa assim que alguem da um passo — e a camara anda
    # sempre, portanto "alguem" e toda a gente.
    quem = (d[:de_quem] ? centro_do_boneco(d[:de_quem]) : [d[:ux], d[:uy]])
    leva = (d[:no_quem] ? centro_do_boneco(d[:no_quem]) : [d[:ax], d[:ay]])
    # ⚠️ NUM FEIXE, O `no_quem` E O MARCADOR — E O MARCADOR E UMA CASA DO CHAO.
    #
    # O feixe e tocado pelo `tocar_no_ponto!`, que poe o marcador numa casa a
    # frente e toca ali. Portanto a ancora do ALVO de um feixe nao e o inimigo:
    # e um ponto do mapa, calculado no disparo e parado desde entao.
    #
    # As celulas presas ao alvo (foco 1) agarram-se a essa ancora. Num feixe com
    # "so a linha se deita" — as bolhas do Poison Sting, o clarao da ponta —
    # elas ficavam no sitio onde o inimigo estava no instante do tiro, enquanto
    # ele andava ou saltava para longe.
    #
    # Havendo bicho travado, e ELE a ancora. E a mesma resposta do comprimento:
    # as duas pontas de um feixe tem de ser vivas.
    if (cfg["modo"].to_s == "feixe") && !d[:rumo_fixo]
      vivo = (ponto_do_alvo_do_feixe rescue nil)
      leva = vivo if vivo
    end
    d[:ux] = quem[0]
    d[:uy] = quem[1]
    d[:ax] = leva[0]
    d[:ay] = leva[1]

    # ⚠️ FORA DO FEIXE, A COLOCACAO E A DA OFICINA. TODA.
    #
    # Isto estava atras do `ROTACAO_LIGADA`, que esta a `false` — ou seja, fora
    # do feixe o feitio nao colocava nada e as celulas ficavam onde o motor as
    # tinha posto, ja deformadas pelo `setLineTransform`. Agora o motor nao
    # lhes toca e e aqui que elas sao postas, pela regra do `_posicionar` do
    # `desenho.py`, celula a celula.
    rodar_isto = ROTACAO_LIGADA &&
                 (cfg.key?("rodar") ? (cfg["rodar"] ? true : false) : true)

    if !e_feixe && rodar_isto
      # Fora do feixe a linha vai de quem lanca ate a ancora do alvo — os dois
      # pontos que o motor ja usa. So que em vez de esticar entre eles, roda-se
      # o desenho para apontar la, o que preserva a forma.
      vx0 = (d[:ax] - d[:ux]).to_f
      vy0 = (d[:ay] - d[:uy]).to_f
      n0 = Math.sqrt((vx0 * vx0) + (vy0 * vy0))
      if n0 > 0.001
        d[:rumo_actual] = [vx0 / n0, vy0 / n0]
        # O comprimento e a distancia real, em casas, para a conta la em baixo
        # ser a mesma do feixe.
        d[:casas] = n0 / Game_Map::TILE_WIDTH.to_f
      else
        rodar_isto = false     # os dois no mesmo sitio: nao ha para onde rodar
      end
    end

    if e_feixe
      # ⚠️ E AQUI O FEIXE VOLTA A SER MEU, A CADA FRAME.
      #
      # A origem deixa de ser a fotografia do disparo e passa a ser onde o dono
      # esta agora. Junto com o rumo — que ja era recalculado para o alvo — as
      # duas pontas ficam presas: sai de mim, aponta a ele, e andar qualquer um
      # dos dois nao solta nada.
      #
      # O meio-boneco de subida e o mesmo do `sprite_ancora`: as animacoes sao
      # pensadas para o centro do corpo e o `screen_y` de um character e nos pes.
      # O desenho sai do MESMO numero que o dano: o rumo travado no disparo.
      #
      # O "acompanha o alvo" e a excepcao pedida — ai o jogador quer que a linha
      # persiga, e ela recalcula-se a cada quadro em coordenadas de ecra.
      # A cada quadro aponta-se a quem esta la. Era isto que fazia o
      # Flamethrower seguir o inimigo, e foi isto que eu tirei sem ninguem
      # pedir. O `feixe_persegue` continua a ser o que guarda a CURVA no rasto.
      rumo = nil
      # O alvo DESTE tiro, e nao o mais proximo de agora (ver `travar_rumo!`).
      # Se ele ja caiu, `rumo` fica nil e mais abaixo herda-se a ultima
      # direccao — o fogo que ja saiu acaba onde ia, sem saltar para outro.
      ponto = d[:rumo_fixo] ? nil : ponto_do_alvo_do_feixe
      if ponto
        dx = (ponto[0] - d[:ux]).to_f
        dy = (ponto[1] - d[:uy]).to_f
        n = Math.sqrt((dx * dx) + (dy * dy))
        if n > 0.001
          rumo = [dx / n, dy / n]
          # ⚠️ EU ANDAVA A CORRIGIR A DIRECCAO E A DEIXAR O COMPRIMENTO PRESO.
          #
          # O rumo ja acompanhava o bicho — mas o `d[:casas]` era medido UMA vez,
          # no disparo, e nunca mais mudava. Um feixe assim aponta ao inimigo e
          # acaba onde ele ESTAVA: ele anda uma casa para a frente e a chama
          # atravessa-o; salta para tras ao cair e a chama fica a meio caminho.
          #
          # Era isto o "continua sem seguir". A direccao seguia; a PONTA nao.
          #
          # O modo "alvo" e super funcional precisamente porque nao tem esta
          # separacao: ele ancora no boneco e pronto. Um feixe tem duas pontas e
          # as duas tem de ser vivas — a de tras em quem lanca (ja estava), a da
          # frente no bicho.
          #
          # O tecto continua a ser o alcance do editor: dentro dele a ponta cola
          # no bicho; alem dele o feixe para onde alcanca, que e honesto e
          # mantem o desenho de acordo com o dano.
          tecto = ((@feixe_alcance || (cfg["feixe_casas"] || ALCANCE_FEIXE)).to_f)
          vivo = n / Game_Map::TILE_WIDTH.to_f
          d[:casas] = (vivo > tecto) ? tecto : vivo
        end
      end
      rumo ||= d[:rumo_actual]     # o alvo caiu: fica-se onde se estava
      rumo ||= @feixe_rumo
      rumo ||= rumo_da_cara
      # ⚠️ DOIS FLOATS QUASE NUNCA SAO IGUAIS.
      #
      # A comparacao era `!=` sobre o rumo em virgula flutuante: bastava o alvo
      # mexer-se um pixel para dar diferente, e isso e todos os quadros. A linha
      # saia dezenas de vezes por segundo e enchia o tecto de 400 linhas em
      # meio minuto de luta, tapando tudo o resto.
      #
      # O que interessa saber e se ele mudou de RUMO, nao se mudou de casa
      # decimal. Um oitavo de volta chega para se ver no ecra.
      antes = d[:rumo_actual]
      if antes.nil? ||
         (((antes[0] * rumo[0]) + (antes[1] * rumo[1])) < 0.92)
        registar("feixe desenha para #{rumo[0].round(2)},#{rumo[1].round(2)}")
      end
      d[:rumo_actual] = rumo
      if persegue
        d[:rumos] << rumo
        d[:rumos].shift while d[:rumos].length > 24
      end
    end

    celulas.each_with_index do |cel, i|
      sp = sprites[i]
      next unless sp && !(sp.disposed? rescue true)
      next unless cel.is_a?(Array)
      foco = cel[AnimFrame::FOCUS].to_i

      # O desvio a mao entra mais abaixo, UMA vez: a direito nos modos normais,
      # rodado no feixe. Ja esteve aqui em cima tambem, e somava-se duas vezes.

      # ⚠️ O FUNDO DE UMA ANIMACAO E DESENHADO PARA UM ECRA DE BATALHA.
      #
      # As celulas de foco 4 sao clarões que cobrem os 512x384 inteiros. Numa
      # batalha ha cenario por tras; num mapa sao uma mancha enorme ao lado do
      # golpe. No Blue Flare sao 65 delas, e o efeito lia-se como dois ataques
      # a serem disparados ao mesmo tempo.
      #
      # O `apagar_fundo!` ja apanha as grandes por tamanho; isto apanha-as pelo
      # que ELAS DIZEM QUE SAO, que e exacto.
      if esconder_fundo && foco == FOCO_ECRA
        (sp.opacity = 0) rescue nil
        next
      end

      next if i < 2   # as ancoras nao se mexem

      # ⚠️ O DESVIO A MAO VALE EM TODOS OS MODOS.
      #
      # Ele estava so no ramo do feixe, portanto arrastar a animacao no editor
      # nao fazia nada no jogo em mais nenhum modo — o Power Whip tem 12,-49
      # gravado que nunca chegou a ser aplicado. O `compor` do editor soma-o a
      # TODAS as celulas; aqui tem de ser igual, senao a oficina mente.
      # Quem nao roda leva so o desvio a mao e sai. Nos que rodam, o desvio
      # entra la em baixo ja virado com a animacao.
      # ⚠️ A REGRA DO `_posicionar`, PORTADA A LETRA.
      #
      #     foco 1  preso ao ALVO         ancora = leva, base = (384, 96)
      #     foco 2  preso a QUEM LANCA    ancora = quem, base = (128, 224)
      #     foco 3  esticado entre os dois
      #     foco 4  do ECRA, de ninguem   fica no meio do ecra
      #     outro   sem foco: quem lanca
      #
      #     posicao = ancora + (celula - base) * escala
      #
      # E uma soma. Nao ha divisao por eixo nenhum, portanto nao ha angulo que
      # a possa achatar nem esticar — um golpe de "alvo" nasce em cima do
      # inimigo esteja ele onde estiver, que e a pergunta que o utilizador fez:
      # "como errar isso?". Errava-se porque nao era isto que corria.
      #
      # Se um dia esta conta e a do `desenho.py` divergirem, a oficina passa a
      # mentir. Sao as duas metades da mesma regra e mudam juntas.
      unless e_feixe || rodar_isto
        pousar_por_foco!(sp, cel, d, foco, esc, dvx, dvy)
        next
      end
      # ⚠️ ESTA REGRA NAO SE PODE ADIVINHAR. TEM DE SE ESCOLHER.
      #
      # Passei esta linha para tras e para a frente quatro vezes, e a razao e
      # que os dois casos que a puxam sao indistinguiveis pelos dados:
      #
      #     Wing Attack    foco1 = 100%   quer deitar-se ao longo do feixe
      #     Poison Sting   foco1 =  84%   as bolhas querem ficar direitas
      #
      # Mesmo perfil, vontades opostas. Nao ha conta que os separe — o que
      # separa e o que a animacao QUER DIZER, e isso e autoria, nao geometria.
      # Cada vez que eu escolhi por regra, arranjei um e parti o outro.
      #
      # Portanto vai para o editor, com o valor por omissao a ser o que ja
      # estava bom: deita-se tudo. Quem tiver bolhas liga a excepcao nesse
      # golpe, e mais nenhum e afectado.
      # ⚠️ AQUI ESTAVA O REGRESSO, E A CULPA E MINHA E RECENTE.
      #
      # Esta linha era `next` e nada mais: a celula ficava de fora da rotacao do
      # feixe, e quem a colocava era o `setLineTransform` do motor. Mal, mas
      # colocava — as bolhas do Poison Sting ficavam direitas em cima de quem
      # lanca, que e o que o "so a linha se deita" existe para garantir.
      #
      # Quando tirei o `setLineTransform` a todas as animacoes com remendo,
      # tirei-lho tambem a estas — e passaram a NAO TER NINGUEM que as
      # coloque. Ficam onde o `pbSpriteSetAnimFrame` as pos: nas coordenadas
      # cruas do palco, a um canto do ecra, longe de toda a gente.
      #
      # Nao basta saltar; e preciso poe-las. Pela regra do palco, que e o que
      # "ficar direita" quer dizer e o que a oficina faz no mesmo caso.
      so_linha = (cfg["so_linha"] ? true : false)
      if e_feixe && so_linha && foco != 3
        pousar_por_foco!(sp, cel, d, foco, esc, dvx, dvy)
        next
      end

      # ⚠️ (a nota antiga fica, porque explica como se chegou aqui)
      #
      # `next if e_feixe && foco != 3` deixa de fora todas as celulas que nao
      # sejam de foco 3. Parece inofensivo — foco 3 sao as que se esticam entre
      # os dois, logo sao "as da linha". Nao e verdade:
      #
      #     Wing Attack  foco1 = 100%
      #     Air Slash    foco1 = 100%
      #     Thunder Shock foco1 = 100%
      #
      # Num golpe assim NENHUMA celula passa por aqui, e nenhuma e recolocada.
      # Mas o `tocar_no_ponto!` ja poe a ancora do alvo na ponta do feixe, e as
      # celulas de foco 1 agarram-se a ela — o efeito inteiro aterra a 6,5
      # casas, atravessando quem estava no meio. Foi isto que se viu no Wing
      # Attack, e foi isto que ja se tinha visto no Thunder Shock.
      #
      # Quem marca "feixe" esta a dizer que a animacao INTEIRA e uma linha. O
      # foco de cada celula deixa de mandar — e essa a escolha.

      # ⚠️ NUM FEIXE, O FOCO DA CELULA DEIXA DE MANDAR.
      #
      # Isto so tratava as celulas de foco 3, e a razao parecia boa: sao elas
      # que se esticam entre os dois. Mas o "feixe" nao e uma variante do palco
      # de batalha — e substitui-lo. Quem marca feixe esta a dizer "esta
      # animacao e uma linha que sai de mim e vai ate ali", e isso vale para
      # todas as celulas dela, venham com o foco que vierem.
      #
      # Foi o experimento do jogador que mostrou isto, e ele isolou-o melhor do
      # que eu:
      #
      #   Bite          sem remendo  foco1 100%  -> certo
      #   Thunder Fang  feixe 2,5    foco1 100%  -> certo (a linha e curta)
      #   Volt Switch   voo_anim     foco3 100%  -> certo
      #   Thunder Shock feixe 6,5    foco1 100%  -> LONGE
      #
      # O Thunder Shock nao tem uma unica celula de foco 3. Nenhuma passava por
      # aqui, portanto nenhuma era rodada nem reposicionada — mas o
      # `tocar_no_chao!` ja tinha atirado a ancora do alvo para 6,5 casas a
      # frente, e as celulas de foco 1 agarram-se a ela. O efeito inteiro ia
      # parar a ponta da linha.
      #
      # O Thunder Fang escapava por acaso: 2,5 casas de linha e perto que
      # chegue para ninguem reparar.

      # ⚠️ O FOGO QUE JA SAIU NAO MUDA DE IDEIAS.
      #
      # Se a linha inteira apontasse ao alvo a cada quadro, ela saltava de golpe
      # quando ele se mexia. Cada pedaco usa a direccao que havia QUANDO ELE
      # SAIU: e isso que desenha uma curva atras de quem foge, em vez de um
      # ponteiro rigido.
      #
      # A fraccao vem do x da celula entre as duas ancoras do palco (128 e 384),
      # que e onde o desenho diz que aquele pedaco esta na linha.
      # ⚠️ UM FEIXE APONTA PARA ONDE SE MIRA, E O MOTOR NAO SABE FAZER ISSO.
      #
      # O `transformPoint` nao roda nada: mede cada eixo como uma fraccao e
      # repoe-a no eixo correspondente. Numa batalha chega, porque os dois
      # combatentes estao sempre na mesma arrumacao — o alvo em cima e a
      # direita. Num mapa nao: apontar na horizontal dava chamas a subir para a
      # direita, que foi exactamente o que se viu.
      #
      # Para um feixe a leitura certa e a geometrica: pega-se no desenho e
      # aponta-se para onde se mira, como virar uma lanterna. E o mesmo calculo
      # que o editor faz (ferramentas/editor/desenho.py, `_rodar_ponto`) — se um
      # dia divergirem, o editor passa a mentir.
      vx = cel[AnimFrame::X].to_f - Battle::Scene::FOCUSUSER_X
      vy = cel[AnimFrame::Y].to_f - Battle::Scene::FOCUSUSER_Y
      odx = (Battle::Scene::FOCUSTARGET_X - Battle::Scene::FOCUSUSER_X).to_f
      ody = (Battle::Scene::FOCUSTARGET_Y - Battle::Scene::FOCUSUSER_Y).to_f
      comp_origem = Math.sqrt((odx * odx) + (ody * ody))
      comp_origem = 1.0 if comp_origem < 0.001

      # A que fraccao da linha do palco esta celula esta — e isso que diz qual
      # pedaco do rasto ela e.
      t = ((vx * odx) + (vy * ody)) / (comp_origem * comp_origem)
      t = 0.0 if t < 0.0
      t = 1.0 if t > 1.0

      # A direccao: a de agora, ou — se ele persegue — a que havia quando este
      # pedaco saiu. O fogo que ja saiu nao muda de ideias.
      rumo = d[:rumo_actual]
      if persegue && !d[:rumos].empty?
        k = (t * (d[:rumos].length - 1)).round
        rumo = d[:rumos][-1 - k] || d[:rumos].last
      end
# ?? SEM RUMO NAO SE RODA ? MAS TAMBEM NAO SE DEIXA A CELULA NO AR.
#
# O mesmo erro do "so a linha se deita", tres linhas acima: antes o
# `setLineTransform` apanhava quem saltasse daqui; agora nao ha ninguem
# atras. Sem rumo (o alvo caiu e nunca houve um travado), coloca-se pela
# regra do palco, que e o mais parecido com estar quieto.
unless rumo
  pousar_por_foco!(sp, cel, d, foco, esc, dvx, dvy)
  next
end

      # ⚠️ UM FEIXE NASCE NUM PONTO FIXO E ACABA NOUTRO. SO O MEIO ESTICA.
      #
      # A conta antiga rodava e escalava TUDO pelo mesmo k = distancia real a
      # dividir pela distancia do palco. Isso estica a animacao inteira, e nao
      # so o comprimento dela. Medido, para uma celula a 40 px DE LADO da linha
      # (a espessura do efeito):
      #
      #     inimigo a  2 casas -> espessura  8,9 px
      #     inimigo a  6 casas -> espessura 26,8 px
      #     inimigo a 13 casas -> espessura 58,1 px
      #
      # ... quando devia ser 40 px sempre. E o mesmo acontece a quem nasce
      # ATRAS de quem lanca (t negativo): uma celula 30 px atras aparece a 6,7
      # px com o inimigo perto e a 43,6 px com ele longe. Ou seja: o ponto onde
      # o golpe NASCE muda conforme onde o inimigo esta.
      #
      # E exactamente isso que se via — "nao fica fixo no ponto de origem, e
      # muito menos no ponto de destino".
      #
      # A correccao e separar as duas coisas que estavam misturadas:
      #
      #   AO COMPRIDO  a fraccao t da linha. Esta SIM acompanha o inimigo: e o
      #                que faz t=0 cair em quem lanca e t=1 cair no alvo. As
      #                duas pontas ficam presas por construcao.
      #
      #   AO TRAVES    a distancia perpendicular, em PIXEIS DA FOLHA. Esta NAO
      #                acompanha nada: a espessura de um lanca-chamas nao muda
      #                porque o alvo se afastou.
      #
      # O t nao se corta aqui de proposito: um t negativo e uma celula desenhada
      # atras de quem lanca, e ela tem de ficar atras dele — a mesma distancia,
      # esteja o inimigo onde estiver.
      t_linha = ((vx * odx) + (vy * ody)) / (comp_origem * comp_origem)
      traves  = ((vx * -ody) + (vy * odx)) / comp_origem
      comp_destino = d[:casas] * Game_Map::TILE_WIDTH
      # ?? SO O MIOLO ESTICA. AS PONTAS SAO RIGIDAS.
      #
      # Uma celula com t entre 0 e 1 esta ENTRE os dois: essa acompanha, e e o
      # que faz o feixe alongar-se ate ao alvo.
      #
      # Uma com t < 0 esta desenhada ATRAS da boca ? e o fumo, o clarao do
      # disparo, a mao que empurra. Uma com t > 1 passa alem do alvo. Essas nao
      # sao "parte do caminho": sao acessorios presos a uma das pontas, e a
      # distancia delas a ponta e a que a folha desenhou, em pixeis, sempre.
      #
      # Sem isto o clarao do disparo nascia a 6,7 px da boca com o inimigo
      # perto e a 43,6 px com ele longe ? o golpe parecia nascer noutro sitio
      # conforme quem estava a frente.
      ao_longo =
        if t_linha < 0.0
          t_linha * comp_origem
        elsif t_linha > 1.0
          comp_destino + ((t_linha - 1.0) * comp_origem)
        else
          t_linha * comp_destino
        end
      # ⚠️ O QUE E DE QUEM LANCA NAO RODA COM A MIRA. FICA ONDE FOI DESENHADO.
      #
      # A conta de cima roda o traves junto com o rumo, e isso esta certo para o
      # CORPO do feixe: a largura de uma chama e perpendicular a chama.
      #
      # So que perto da boca ha celulas que nao sao o feixe — sao o anel de
      # fogo, o clarao, a pose de quem lanca. Elas tem t quase zero e traves
      # grande, e sao indistinguiveis do "feixe visto de lado" para a conta.
      # Rodar o traves faz o anel ORBITAR a volta do boneco:
      #
      #     uma celula desenhada em 0,-45 (por cima da cabeca) acaba em
      #       alvo a direita ->  +19, -40
      #       alvo em baixo  ->  +40, +19     <- passou para o lado
      #       alvo em cima   ->  -40, -19
      #
      # ... quando devia estar sempre em 0,-45. E exactamente a orbita que se
      # via: alvo em frente, anel a volta; alvo em baixo, anel deslocado.
      #
      # A regra: quem esta a menos de PRESO_ATE da boca pertence a QUEM LANCA, e
      # desenha-se com o desvio da folha tal e qual, sem rodar nada. Quem esta
      # alem de SOLTO_DESDE pertence a linha e roda. Entre os dois mistura-se
      # aos poucos, senao havia um degrau visivel a meio do golpe.
      # ⚠️ PERTO DA BOCA RODA-SE SEMPRE. O QUE NAO SE FAZ E ESTICAR.
      #
      # Eu tinha resolvido a orbita do anel tirando a ROTACAO as celulas perto
      # da boca: elas passavam a ser desenhadas com o desvio cru da folha. Isso
      # parou a orbita e criou outro defeito, pior de ler — com o inimigo ATRAS,
      # a chama continuava a sair para a frente e so depois a linha dava a volta.
      # A folha desenha o fogo a apontar para o alvo do PALCO (em cima e a
      # direita); sem rodar, ele aponta sempre para la.
      #
      # O diagnostico certo e mais fino. A orbita nunca foi culpa da rotacao:
      # uma rotacao leva um circulo nele proprio, e o anel nem daria por ela. A
      # culpa era do `ao_longo` ser multiplicado pelo comprimento REAL, o que
      # deforma o circulo numa elipse conforme o inimigo se afasta:
      #
      #     alvo a  2 casas -> raio 40,5      (a folha desenhou 45)
      #     alvo a  8,5     -> raio 44,6
      #     alvo a 13       -> raio 49,8
      #
      # Com o comprimento da FOLHA o raio e 45,0 nos tres casos.
      #
      # Portanto: roda-se sempre — e o que mantem a chama virada para onde se
      # aponta — e perto da boca usa-se o comprimento da folha, que e o que
      # impede a forma de deformar. Longe usa-se o real, que e o que faz o feixe
      # alongar-se ate ao alvo. Entre os dois mistura-se, senao ha um degrau.
      ao_longo_rigido = t_linha * comp_origem
      if t_linha <= PRESO_DA_BOCA
        usar = ao_longo_rigido
      elsif t_linha >= SOLTO_NA_LINHA
        usar = ao_longo
      else
        k = (t_linha - PRESO_DA_BOCA) / (SOLTO_NA_LINHA - PRESO_DA_BOCA)
        usar = (ao_longo_rigido * (1.0 - k)) + (ao_longo * k)
      end
      # ⚠️ "SO A LINHA SE DEITA" NAO CHEGAVA A EXISTIR PARA METADE DOS GOLPES.
      #
      # A regra era `foco != 3`: poupava-se da rotacao a celula que nao fosse de
      # foco 3, e essa ficava direita. Isso resolve o Poison Sting (84% foco 1) e
      # NAO RESOLVE NADA em quem so tem foco 3 — e sao muitos:
      #
      #     Flamethrower  foco3 = 90/90     Hyper Beam  foco3 = 594/594
      #     Hypnosis      foco3 = 110/110   Leech Seed  foco3 = 120/120
      #     Mega Drain    foco3 = 326/326
      #
      # Com a caixa ligada, zero celulas eram poupadas e tudo continuava a rodar
      # com o inimigo — as bolhas que deviam subir iam para o lado, que foi o
      # relato.
      #
      # A opcao passa a dizer o que o nome dela diz, e a dizer-lho por
      # geometria em vez de por foco. Cada celula ja esta partida em duas:
      #
      #     AO COMPRIDO  onde ela esta ao longo da linha. E a LINHA. Deita-se.
      #     AO TRAVES    o quanto ela esta de lado. Nao e a linha. Fica direita.
      #
      # Marcada a caixa, o traves e somado no rumo do PALCO — a direccao em que
      # a folha o desenhou — em vez do rumo da mira. Uma bolha 100 px acima da
      # linha, com o inimigo a direita:
      #
      #     sem a caixa   (+44,7 , -89,4)   sobe inclinada 27 graus
      #     com a caixa   ( +4,7 , -80,0)   sobe a direito
      #
      # ... e com o inimigo em BAIXO, que era o caso mau:
      #
      #     sem a caixa   (+89,4 , +44,7)   a bolha DESCE para a direita
      #     com a caixa   (-40,0 , -35,3)   continua a subir
      #
      # A linha em si nao muda: o `usar` e o mesmo dos dois lados, portanto o
      # feixe continua a esticar-se ate ao alvo. So o que estava de lado deixa
      # de andar a roda.
      #
      # Quem nao marca a caixa nao sente nada — e a razao de isto ser uma
      # escolha e nao uma regra esta na nota do `so_linha`, la em cima: o mesmo
      # perfil de dados serve duas vontades opostas.
      if so_linha
        travx = -ody / comp_origem
        travy = odx / comp_origem
      else
        travx = -rumo[1]
        travy = rumo[0]
      end
      rx = (rumo[0] * usar) + (travx * traves)
      ry = (rumo[1] * usar) + (travy * traves)

      # (a nota que aqui estava dizia o contrario; ver a de baixo)
      #
      # Estava a ser somado em pixeis do ecra, quieto. Num golpe parado isso
      # esta certo; num feixe nao, porque a animacao roda para onde se aponta e
      # o desvio nao. Quem centrava a chama a apontar para cima via-a sair do
      # sitio assim que se virava para o lado, com o MESMO ajuste — "consertei
      # pra cima, pro lado ficou ruim".
      #
      # O desvio passa a ser dito no sistema do feixe (ao comprido e ao traves)
      # e roda com a mesma conta das celulas. Centra-se uma vez, vale para as
      # quatro direccoes. E o mesmo que o editor faz no `_desvio_rodado`.
      # ⚠️ O AJUSTE A MAO NAO RODA. E UMA POSICAO, NAO UMA DIRECCAO.
      #
      # Eu tinha-o a rodar com a mira, com o argumento de que "centra-se uma vez
      # e vale para as quatro direccoes". Soa bem e esta errado, e foi o
      # jogador que deu com isso da maneira mais clara possivel: com o desvio a
      # ZERO a animacao ficava perfeita em qualquer direccao; bastava arrasta-la
      # um bocadinho para voltar a orbitar o lancador.
      #
      # A razao e simples quando se ve: zero rodado continua zero. O defeito
      # nunca esteve na conta das celulas — estava aqui, e so aparecia quando
      # havia ajuste para rodar.
      #
      # E o arrasto nao e uma direccao: e o sitio onde a animacao tem de ficar
      # em relacao a quem lanca. Esse sitio nao muda porque o inimigo mudou de
      # lado. Soma-se a direito, como em todos os outros modos.
      sp.x = (d[:ux] + rx + dvx).round
      sp.y = (d[:uy] + ry + dvy).round

      # ⚠️ AS PECAS NAO RODAM. SO AS POSICOES.
      #
      # Eu tinha posto cada peca a rodar com o feixe, achando que "virar uma
      # lanterna vira tudo". Numa lanterna sim; num desenho feito de sprites
      # nao: cada peca roda em volta do seu proprio centro, e o conjunto sai
      # torcido e envergado — as chamas ficam a apontar para dentro umas das
      # outras em vez de formarem uma linha.
      #
      # O eixo do DESENHO tem de ser sempre o mesmo, seja qual for a direccao
      # do tiro. O que roda e a colocacao das pecas ao longo da linha; o angulo
      # de cada uma continua a ser o que a folha diz.
      #
      # (Ficou aqui a nota porque isto ja foi tentado nos dois sentidos: sem
      # rotacao nenhuma o chicote sai deitado, com rotacao por peca sai
      # envergado. O deitado e o menor dos males e foi o escolhido.)
    end
  rescue => e
    registar("falha no feitio da animacao: #{e.class}: #{e.message}")
  end

  # ⚠️ ISTO SO CORRIA QUANDO O QUADRO DA ANIMACAO MUDAVA, E DAI O ARRASTO.
  #
  # A animacao esta presa a um sitio do MAPA — a casa onde o golpe bateu. Como
  # a camara anda com o jogador, manter o desenho parado no mapa quer dizer
  # move-lo no ecra, a cada frame, pelo mesmo tanto que a camara andou.
  #
  # So que isto corria uma vez por quadro da animacao, a 20 por segundo. Nos
  # dois frames pelo meio o desenho ficava colado ao ECRA e viajava connosco;
  # no terceiro voltava ao sitio. Andar durante um golpe arrastava o efeito e
  # depois via-se ele a saltar para tras — que e exactamente o que se descreveu.
  #
  # Agora corre a cada frame. Para poder correr a cada frame tem de ser
  # INCREMENTAL: aplica-se so o que falta desde a ultima vez, senao somava-se o
  # deslocamento inteiro tres vezes por quadro e a animacao fugia do mapa.
  #
  # O `@quadro_visto` zera o acumulado quando o motor reescreve os sprites, que
  # e o unico momento em que o que ja foi aplicado deixa de contar.
  # Onde uma posicao do mapa cai no ecra. Sem o meio-tile nem o `x_offset` do
  # `screen_x`: isto so serve para DIFERENCAS, e nelas as constantes cortam-se.
  def ecra_da_casa(rx, ry)
    [((rx.to_f - $game_map.display_x) / Game_Map::X_SUBPIXELS).round,
     ((ry.to_f - $game_map.display_y) / Game_Map::Y_SUBPIXELS).round]
  rescue
    [0, 0]
  end

  def seguir_animacao!(jogador)
    d = (@seguir_de || {})[jogador]
    return unless d
    return if d[:fixo_no_dono]
    if d[:mapa_x]
      ex, ey = ecra_da_casa(d[:mapa_x], d[:mapa_y])
    else
      return unless d[:quem]
      ex = (d[:quem].screen_x rescue d[:x0])
      ey = (d[:quem].screen_y rescue d[:y0])
    end
    total_x = (ex - d[:x0]).to_i
    total_y = (ey - d[:y0]).to_i
    ja_x = d[:aplicado_x].to_i
    ja_y = d[:aplicado_y].to_i
    dx = total_x - ja_x
    dy = total_y - ja_y
    return if dx.zero? && dy.zero?
    sprites = (jogador.instance_variable_get(:@animsprites) rescue nil)
    return unless sprites.is_a?(Array)
    sprites.each do |sp|
      next unless sp && !(sp.disposed? rescue true)
      sp.x += dx
      sp.y += dy
    end
    d[:aplicado_x] = total_x
    d[:aplicado_y] = total_y
  rescue
    nil
  end

  # Corre no tick: avanca cada animacao e deita fora as que acabaram.
  # ⚠️ ESTE ERA O ESTRAGO, E ELE VINHA DE UMA COISA QUE EU NAO SABIA DO MOTOR.
  #
  # O `PBAnimationPlayerX#update` desiste logo se o quadro nao mudou:
  #
  #     return if @frame == @old_frame
  #
  # Ou seja, as posicoes e os tamanhos das celulas so sao REESCRITOS quando a
  # animacao avanca — a 20 quadros por segundo. Nos frames pelo meio, os sprites
  # ficam exactamente como estao.
  #
  # Eu tinha dois metodos a mexer neles a CADA frame: o `encolher_animacao!`
  # (que multiplica o zoom por k) e o `seguir_animacao!` (que soma o quanto o
  # alvo andou). Entre dois quadros da animacao, isso corria tres ou quatro
  # vezes sem ninguem repor nada: o zoom virava k x k x k, e o deslocamento
  # somava-se sobre si proprio. Ao fim de meio segundo as celulas estavam
  # minusculas e espalhadas — "um ao lado do outro em vez de animadas", como o
  # jogador descreveu, e sem nunca parecerem uma animacao.
  #
  # A correccao e so uma: mexer nelas UMA vez por quadro da animacao, logo a
  # seguir a o motor as ter reescrito. Guarda-se o numero do quadro e compara-se.
  def actualizar_animacoes!
    return if @jogadores_anim.nil? || @jogadores_anim.empty?
    @quadro_visto ||= {}
    acabadas = []
    @jogadores_anim.each do |p|
      begin
        p.update
        mover_particulas_finais!(p)
        quadro = (p.instance_variable_get(:@frame) rescue -1)
        if @quadro_visto[p] != quadro
          @quadro_visto[p] = quadro
          # O motor acabou de reescrever as posicoes: o que ja se tinha somado
          # deixou de estar la, portanto a conta recomeca do zero.
          if (dd = (@seguir_de || {})[p])
            dd[:aplicado_x] = 0
            dd[:aplicado_y] = 0
          end
          # ⚠️ E O SEGUIMENTO E O ULTIMO, SENAO O FEITIO APAGA-O.
          #
          # O `aplicar_feitio!` escreve a posicao dos sprites de um feixe em
          # ABSOLUTO (`sp.x = ux + rx + dvx`). Correndo depois do seguimento,
          # deitava fora o deslocamento que este acabara de somar — mas o
          # seguimento ja tinha apontado no caderno que o aplicara, portanto
          # nos frames seguintes so somava a diferenca e nunca o repunha.
          #
          # Resultado: uma animacao com remendo de feixe ficava presa as
          # coordenadas de ECRA do instante do disparo, enquanto a camara — que
          # anda sempre, porque segue o jogador — deslizava o mundo por baixo
          # dela. Um golpe de um segundo com o jogador a correr acabava varias
          # casas ao lado do inimigo.
          #
          # A ordem certa e a natural: o motor desenha, encolhe-se, da-se-lhe o
          # feitio no referencial do disparo, e so no fim se leva o conjunto
          # para onde ele tem de estar agora.
          apagar_fundo!(p)
          encolher_animacao!(p)
          aplicar_feitio!(p)
          seguir_animacao!(p)
        else
          # Nos frames pelo meio o motor nao mexe em nada — so a camara anda.
          # Compensa-se so isso, e e barato: uma soma por sprite.
          seguir_animacao!(p)
        end
        acabadas << p if p.animDone?
      rescue => e
        registar("animacao rebentou no update: #{e.class}: #{e.message}")
        acabadas << p
      end
    end
    acabadas.each do |p|
      largar_particulas_finais!(p)
      (p.dispose rescue nil)
      @jogadores_anim.delete(p)
      @quadro_visto.delete(p)
      (@seguir_de || {}).delete(p)
      (@feitio_de || {}).delete(p)
      ((@ancoras_de || {}).delete(p) || []).each do |sp|
        next unless sp
        (sp.bitmap.dispose rescue nil)
        (sp.dispose rescue nil)
      end
    end
  rescue
    @jogadores_anim = []
  end

  # ⚠️ CADA PASSO DIZ SE PASSOU. Ate agora falhavam todos em silencio.
  # ⚠️ DESLIGAR ISTO VOLTA AO CAMINHO ANTIGO, INTEIRO.
  #
  # O animador novo (`193_Arena_Animador.rb`) nao substitui nada: ele corre ao
  # lado. Pondo isto a `false`, tudo o que esta abaixo volta a correr como
  # corria, com o `PBAnimationPlayerX`, o `setLineTransform` e o `feitio`. E o
  # que permite comparar os dois lado a lado em vez de acreditar.
  ANIMADOR_NOVO = true

  # O feixe fica de fora de proposito. La a animacao E uma linha entre dois
  # pontos, o mapeamento do palco faz sentido, e o caminho antigo esta afinado
  # e verificado contra o editor — 12 960 comparacoes, zero divergencias.
  # Trocar-lhe o motor seria deitar fora a unica parte que ja funciona.
  def animador_novo?(cfg)
    return false unless ANIMADOR_NOVO
    return false unless cfg
    # ⚠️ Apontar e uma propriedade do desenho, nao um modo a parte: um golpe
    # pode ser "alvo" E apontar. Sem esta linha, marcar "apontar" num golpe
    # cujo modo o animador novo nao leva nao fazia nada — e nao havia nada no
    # ecra que explicasse porque.
    return true if cfg["apontar"]
    m = cfg["modo"].to_s
    m == "alvo" || m == "quem" || m == "chao"
  rescue
    false
  end

  def tocar_no_character!(character, anim, desde = 0, de = nil)
    idx = anim.to_i
    if idx <= 0
      registar("tocar: indice 0, nada a fazer")
      return
    end
    # ⚠️ A ANCORA E ESCOLHIDA AQUI, E E A UNICA DECISAO QUE O NOVO MOTOR PRECISA.
    #
    # "quem" desenha-se sobre quem lanca; "alvo" e "chao" sobre quem leva (ou
    # sobre o marcador, que e uma casa do chao). Nao ha mais nada a decidir —
    # nem linha, nem foco, nem comprimento.
    cfg_novo = (palco_da_anim(idx) rescue nil)
    if animador_novo?(cfg_novo)
      quem_ancora = (cfg_novo["modo"].to_s == "quem") ? (de || $game_player) : character
      # ⚠️ A APONTAR SAO PRECISAS AS DUAS PONTAS, E A ANCORA E QUEM LANCA.
      #
      # Um golpe que viaja sai de quem o deu. Ancorado no alvo, ele nascia em
      # cima do alvo e apontava para tras — o contrario do que se quer.
      outra_ponta = nil
      # ⚠️ E so se ela VIAJAR. Um remoinho fica onde o modo dele manda — ver o
      # `viaja?`. Sem esta pergunta, o Petal Blizzard saltava de cima do
      # inimigo para cima de mim assim que se ticasse a caixa.
      if cfg_novo["apontar"] && (AnilArenaAnimador.viaja?(idx) rescue false)
        quem_ancora = (de || $game_player)
        outra_ponta = character
        outra_ponta = nil if outra_ponta.equal?(quem_ancora)
      end
      ef = AnilArenaAnimador.tocar!(idx, quem_ancora, cfg_novo, desde, outra_ponta)
      if ef
        # ⚠️ AQUI ESTAVA O DEFEITO, E ELE ERA UM `return`.
        #
        # O rebentamento em particulas do editor e montado la em baixo, no
        # caminho antigo. Este `return` — que existe desde que o animador novo
        # entrou — sai por cima dele.
        #
        # Consequencia: as particulas so alguma vez funcionaram nos modos que o
        # animador novo NAO leva, ou seja `feixe` e `voo`. Em `alvo`, `quem` e
        # `chao` — que sao a esmagadora maioria das animacoes — a receita era
        # gravada, o editor mostrava-a, e no jogo nao saia nada.
        #
        # Por isso o que se via no jogo era so a animacao. E a queixa de que
        # "fica na posicao errada da batalha comum" tem a mesma origem: sem
        # particulas, o que sobra e a animacao a correr, e qualquer estranheza
        # de posicao dela nao tinha nada a ver com o gerador.
        soltar_particulas_do_animador!(ef, idx, quem_ancora, de || $game_player)
        return
      end
    end
    tabela = animacoes_de_golpe
    # `empty?` so se pergunta a quem sabe responder: uma coleccao propria do
    # motor pode nao ter esse metodo e a pergunta rebentava aqui.
    # ⚠️ NAO SE PERGUNTA `empty?` A ESTA COLECCAO.
    #
    # `PBAnimations < Array` mas guarda tudo num `@array` interno: o `empty?`
    # herdado olha para a parte Array, que esta mesmo vazia, e responde `true`
    # com 1550 animacoes la dentro. O `length` esta sobreposto e diz a verdade.
    tam = (tabela.respond_to?(:length) ? tabela.length.to_i : 0)
    if tabela.nil? || tam <= 0
      registar("tocar: PkmnAnimations sem entradas (#{tabela.class})")
      dizer("PkmnAnimations não carregou")
      return
    end
    obj = tabela[idx]
    unless obj
      tam = (tabela.respond_to?(:length) ? tabela.length : "?")
      registar("tocar: indice #{idx} sem animacao (tabela #{tabela.class} tem #{tam})")
      dizer("animação #{idx} não existe")
      return
    end
    quem = (character == $game_player) ? "jogador" : "evento#{(character.id rescue '?')}"
    begin
      vp = viewport_das_animacoes
      # ⚠️ A CENA NAO PODE SOBREVIVER AO VIEWPORT DELA.
      #
      # Isto era um `@cena_anim ||= CenaFalsa.new(vp)`: criada UMA vez, guardava
      # o viewport da PRIMEIRA arena. Ao sair, o `limpar_animacoes!` deita esse
      # viewport fora — e a cena ficava a apontar para um viewport morto. Na
      # arena seguinte o PBAnimationPlayerX criava os sprites nele e nao se via
      # absolutamente nada, sem erro nenhum.
      #
      # Era exactamente a assinatura: funcionava na primeira batalha depois de
      # abrir o jogo e em mais nenhuma.
      if @cena_anim.nil? || @cena_anim.viewport.nil? ||
         (@cena_anim.viewport.disposed? rescue true) || !@cena_anim.viewport.equal?(vp)
        @cena_anim = CenaFalsa.new(vp)
        registar("cena de animacoes (re)criada")
      end
      cena = @cena_anim
      # O utilizador da animacao e sempre o jogador; o alvo e quem leva com ela.
      @ancoras ||= {}
      # ⚠️ O SINAL DE ESTADO SAIA SEMPRE DA MINHA CABECA.
      #
      # "Quem lanca" e sempre o jogador — e certo para um golpe, porque um
      # golpe sai mesmo de nos. Mas os sinais de estado (`Common:Sleep` e
      # companhia) sao 100% celulas de foco 2, que se agarram a quem LANCA.
      # Resultado: o inimigo adormecia e os Zs subiam da minha cabeca.
      #
      # Quem chama pode agora dizer de quem parte. Sem dizer nada, e o jogador,
      # como sempre foi.
      cena.sprites["pokemon_0"] = sprite_ancora(:user, de || $game_player)
      cena.sprites["pokemon_1"] = sprite_ancora(:alvo, character)

      jogador = PBAnimationPlayerX.new(obj, Lutador.new(0), Lutador.new(1), cena, false, false)

      # ⚠️ E AQUI QUE A ANIMACAO GANHA DIRECCAO E TAMANHO.
      #
      # Os frames sao desenhados em coordenadas do PALCO DE BATALHA: o
      # utilizador em (128,224) e o alvo em (384,96) — em baixo a esquerda e em
      # cima a direita. Mover as ancoras so DESLOCA o desenho; e por isso que as
      # folhas iam sempre para cima e para a direita, olhasse eu para onde
      # olhasse.
      #
      # O `setLineTransform` mapeia a linha utilizador->alvo do palco para a
      # linha utilizador->alvo REAL. Como e uma transformacao da linha inteira,
      # resolve as duas coisas de uma vez:
      #
      #   direccao — a linha aponta para onde estou virado;
      #   tamanho  — a linha do mapa e muito mais curta que a do palco (256 px
      #              contra ~285), e tudo encolhe na mesma proporcao.
      #
      # Sem isto a animacao sai do tamanho de um combate a ecra inteiro por cima
      # de bonecos de 32 px, que era o outro problema.
      sp_user = cena.sprites["pokemon_0"]
      sp_alvo = cena.sprites["pokemon_1"]
      ux = (sp_user.x rescue $game_player.screen_x)
      uy = (sp_user.y rescue $game_player.screen_y)
      ax = (sp_alvo.x rescue ux)
      ay = (sp_alvo.y rescue uy)

      # ⚠️ A PONTA DE DESTINO NAO SE AJUSTA. ELA PERTENCE AO ALVO.
      #
      # Havia aqui um `desvio_alvo_x/y`: o editor deixava arrastar a ponta e o
      # jogo somava-o. A intencao era endireitar folhas tortas; o efeito foi o
      # contrario do que se quer — a ponta deixava de estar em cima do inimigo.
      #
      # E mentia em silencio. O comprimento do feixe continuava a ser medido
      # ate ao alvo VERDADEIRO (`alcance_ate_bater`), portanto a regua dizia
      # "parou no alvo" e o rebentamento aparecia noutro sitio. O numero certo,
      # o desenho nao — e num sistema com dois lados isso e o pior tipo de erro,
      # porque nenhum dos dois parece estar errado sozinho.
      #
      # Endireitar uma folha torta faz-se pela ORIGEM (o `desvio_x/y`, que
      # tambem ja nao roda). Mover a origem nao desprende a ponta do alvo; mover
      # a ponta desprende.

      # ⚠️ O FEIXE NAO APONTA AO INIMIGO — APONTA PARA A FRENTE.
      #
      # Um lanca-chamas alcanca o que alcanca. A linha da animacao ja traz o
      # desenho todo (no Blue Flare ve-se o x das celulas a marchar de 192 ate
      # 432); o que o editor decide e o COMPRIMENTO dela no mapa.
      #
      # Por isso aqui nao se usa a posicao do alvo: usa-se a direccao dele e um
      # alcance fixo em casas. Sem remendo nada disto corre, e a animacao e
      # colocada como sempre foi.
      # ⚠️ O `@feixe_alcance` E DO JOGADOR, E SO DELE.
      #
      # Ele e escrito pelo `travar_rumo!` quando EU disparo, e diz ate onde o
      # MEU feixe chegou. Abaixo era lido sem perguntar de quem e o golpe: um
      # feixe de um selvagem ou do ajudante ficava com o comprimento do meu
      # ultimo tiro, e com a direccao da MINHA mira (ver o `alvo_travado` no
      # `aplicar_feitio!`). Duas coisas de outra pessoa a mandar no desenho.
      #
      # Quando o dono nao sou eu, as duas pontas ja vem certas de quem chamou —
      # a origem e o bicho, a ponta e a casa que ele mediu — e nao ha nada a
      # corrigir aqui.
      cfg = palco_da_anim(idx)
      meu_feixe = (de.nil? || de.equal?($game_player))
      if cfg && cfg["modo"].to_s == "feixe" && meu_feixe
        # ⚠️ AQUI DESFAZIA-SE O ENCURTAMENTO, TRES LINHAS DEPOIS DE O FAZER.
        #
        # O `usar_golpe!` mede a distancia ao primeiro que esta no corredor
        # (`alcance_ate_bater`) e poe o marcador LA. Bom. Depois chama isto — e
        # isto pegava na direccao, deitava fora o comprimento, e reesticava ate
        # ao `feixe_casas` da tabela.
        #
        # O resultado e o que se ve: aponta certo e passa ao lado do inimigo
        # que esta no caminho, indo morrer bem la a frente. E o dano ficava
        # curto (usa o `@feixe_alcance`) enquanto o desenho ia longo — outra
        # vez o desenho a discordar do dano, agora ao contrario.
        #
        # Se o tiro ja mediu, e essa medida que manda. O `feixe_casas` fica
        # para quem chega aqui sem tiro medido (a copia do adversario, por
        # exemplo, que so recebe a animacao).
        casas = (@feixe_alcance || cfg["feixe_casas"] || 6.5).to_f
        dx = ax - ux
        dy = ay - uy
        n = Math.sqrt((dx * dx) + (dy * dy))
        if n < 0.001
          case ($game_player.direction rescue 2)
          when 2 then dx, dy, n = 0.0,  1.0, 1.0
          when 8 then dx, dy, n = 0.0, -1.0, 1.0
          when 4 then dx, dy, n = -1.0, 0.0, 1.0
          else        dx, dy, n = 1.0,  0.0, 1.0
          end
        end
        comp = casas * Game_Map::TILE_WIDTH
        ax = ux + ((dx / n) * comp).round
        ay = uy + ((dy / n) * comp).round
      end

      # ⚠️ NUNCA UMA LINHA DE COMPRIMENTO ZERO.
      #
      # Se o alvo estivesse em cima do utilizador, a transformacao dividia por
      # zero e a animacao rebentava. Da-se-lhe uma casa de distancia na direccao
      # em que se olha, que e o minimo que faz sentido para um golpe.
      if (ax - ux).abs < 4 && (ay - uy).abs < 4
        case $game_player.direction
        when 2 then ay = uy + Game_Map::TILE_HEIGHT
        when 8 then ay = uy - Game_Map::TILE_HEIGHT
        when 4 then ax = ux - Game_Map::TILE_WIDTH
        else        ax = ux + Game_Map::TILE_WIDTH
        end
      end

      # ⚠️ E NUNCA UMA LINHA COM UM EIXO ACHATADO — QUE E MAIS SUBTIL E PIOR.
      #
      # Comprimento zero eu ja tinha tapado. O que nao tinha visto e que basta
      # UM dos eixos ser zero para a animacao se desmanchar. Olhe-se ao que o
      # motor faz (0233_BattleAnimationPlayer.rb):
      #
      #     tx = (dx == 0) ? 0.0 : (px - x1) / dx     # divide pela ORIGEM
      #     x  = x3 + (tx * (x4 - x3))                # MULTIPLICA pelo destino
      #
      # A guarda esta so na origem, porque e la que se divide. O destino e
      # multiplicado sem guarda nenhuma — e numa batalha isso nunca da problema,
      # porque os dois combatentes estao sempre nas posicoes fixas do palco.
      #
      # Aqui nao: com movimento livre eles ficam lado a lado a toda a hora. Com
      # `ay == uy`, TODA a celula de foco 3 recebe o mesmo y e a animacao achata
      # numa risca horizontal; um por cima do outro, achata na vertical. Foi
      # medido: altura 0 num caso, largura 0 no outro.
      #
      # A saida nao e esticar a esmo. Quando um eixo desaparece devolve-se-lhe a
      # PROPORCAO DO PALCO — a animacao foi desenhada para uma linha de 256 por
      # -128, e e com essa forma que ela faz sentido. Fica igual ao que se ve em
      # batalha, so que colocada entre os dois pontos verdadeiros.
      begin
        odx = (Battle::Scene::FOCUSTARGET_X - Battle::Scene::FOCUSUSER_X).to_f
        ody = (Battle::Scene::FOCUSTARGET_Y - Battle::Scene::FOCUSUSER_Y).to_f
        odx = 1.0 if odx == 0.0
        ody = 1.0 if ody == 0.0
        minimo = 16.0    # meia casa: abaixo disto o eixo conta como perdido
        dx = ax - ux
        dy = ay - uy
        # ⚠️ AQUI ESTAVA O ERRO GRANDE, E ELE ERA MEU.
        #
        # Eu dava ao eixo plano a PROPORCAO DO PALCO, para a animacao nao sair
        # achatada. So que a proporcao e 256 por 128 — dois para um. Com o
        # inimigo mesmo por cima (dx = 0), a largura passava a ser o dobro da
        # distancia vertical, e a ancora do alvo ia parar a DEZ CASAS de lado
        # com o inimigo a cinco casas de distancia.
        #
        # Medido:
        #   3 casas a direita -> a ancora desviava 1,5 casas
        #   5 casas acima     -> a ancora desviava 10 casas
        #
        # E num mapa em casas estar alinhado e o caso NORMAL, nao a excepcao.
        # Por isso todas as animacoes pareciam disparadas ao calhas, e por isso
        # a oficina parecia certa: la o alvo arrasta-se para sitios na diagonal,
        # onde isto nunca chega a disparar.
        #
        # Um eixo plano so precisa de deixar de ser ZERO — o `transformPoint`
        # divide por ele. Meia casa chega. A animacao fica mais achatada do que
        # no palco de batalha, e fica NO SITIO, que e o que importa.
        if dx.abs < minimo
          dx = (dx >= 0) ? minimo : -minimo
          ax = ux + dx
        end
        if dy.abs < minimo
          # O sinal vem do palco: la o alvo esta ACIMA de quem lanca, e e com
          # essa ideia que todas as animacoes foram desenhadas.
          dy = (ody < 0) ? -minimo : minimo
          ay = uy + dy
        end
      rescue
        nil
      end

      # ⚠️ UMA ANIMACAO "DO PROPRIO" NAO TEM LINHA PARA ESTICAR.
      #
      # O `setLineTransform` existe para golpes que VAO de alguem para alguem: a
      # linha do palco passa a ser a linha real, e com ela vem a direccao e o
      # tamanho. E o que faz um lanca-chamas apontar para onde estamos virados.
      #
      # Num golpe desenhado em cima de quem o da — o modo "o proprio, sem
      # direccao" do editor — nao ha segunda ponta. Eu estava a inventar uma
      # (uma casa na diagonal) so para a transformacao nao dividir por zero, e o
      # resultado e o que se ve: a animacao esticada e deslocada nessa diagonal,
      # longe da posicao que foi afinada na oficina. Com o Surf ve-se bem — as
      # ondas nascem em cima e a direita do boneco, e nao nele.
      #
      # Sem linha, a animacao fica onde o motor a desenha e o `desvio_x/y` do
      # editor manda sozinho, que e exactamente o que "sem direccao" quer dizer.
      # O tamanho continua a vir da `escala`, que e outro campo e nao depende
      # disto.
      # ⚠️ O MOTOR E A OFICINA NAO PODEM AMBOS COLOCAR A ANIMACAO.
      #
      # Isto e a raiz de tudo o que se andou a remendar nas ultimas rondas, e
      # so se ve olhando para os dois lados ao mesmo tempo.
      #
      # O `setLineTransform` manda o motor fazer o que ele faz numa batalha:
      # medir cada eixo como uma fraccao entre as duas pontas e repo-la NO
      # MESMO EIXO. Isso nao e uma rotacao — e um esticao independente em x e
      # em y. Numa batalha nao se nota, porque os dois combatentes estao sempre
      # na mesma arrumacao (o alvo em cima e a direita). Num mapa, onde eles
      # ficam em qualquer angulo, deforma conforme o angulo:
      #
      #     -30 graus (o angulo do palco)  1,15x   quase certo
      #     +-45                           2,00x
      #     +-60                           3,46x
      #     0 e 90 (alinhados)             achatada
      #
      # E alinhado e o caso NORMAL num mapa em casas, nao a excepcao. Dai o
      # "dependendo da posicao do inimigo a animacao distorce, perde os eixos".
      #
      # A oficina nunca fez nada disto. O `_posicionar` do `desenho.py` e uma
      # TRANSLACAO por celula: pega no foco, escolhe a ancora, e soma o desvio
      # que a folha desenhou. Nao ha esticao nenhum, e por isso la nada distorce
      # em angulo nenhum — que e exactamente o que o utilizador relata.
      #
      # Portanto: quem tem remendo nao passa por aqui. O `aplicar_feitio!`
      # coloca as celulas pela regra da oficina, a mesma conta, com os mesmos
      # numeros. Quem NAO tem remendo (as 659 animacoes que ninguem afinou)
      # continua com o motor, como sempre esteve.
      unless cfg
        jogador.setLineTransform(
          Battle::Scene::FOCUSUSER_X,   Battle::Scene::FOCUSUSER_Y,
          Battle::Scene::FOCUSTARGET_X, Battle::Scene::FOCUSTARGET_Y,
          ux, uy, ax, ay
        ) rescue nil
      end

      # E o mesmo para os golpes desenhados em torno do alvo (FOCUS 1), que nao
      # passam pela transformacao da linha.
      (jogador.set_target_origin(ax, ay) rescue nil)

      jogador.start
      # ⚠️ SALTAR QUADROS FAZ-SE NO RELOGIO, NAO NO CONTADOR.
      #
      # O `@frame` do jogador e recalculado a cada update a partir do instante
      # de arranque (`(uptime - inicio) * 20`), portanto escrever nele nao
      # servia de nada — no frame seguinte voltava a zero. Recua-se o instante
      # de arranque e a animacao acorda ja a meio.
      if desde.to_i > 0
        (jogador.instance_variable_set(:@timer_start,
          System.uptime - (desde.to_i / CADENCIA_ANIM)) rescue nil)
      end
      @jogadores_anim ||= []
      @jogadores_anim << jogador
      # O que o gancho de cada quadro precisa de saber sobre esta animacao.
      if cfg
        (@feitio_de ||= {})[jogador] = {
          :cfg => cfg, :obj => obj, :ux => ux, :uy => uy,
          # ⚠️ QUEM DA O GOLPE, PARA SE PODER PERGUNTAR ONDE ELE ESTA AGORA.
          #
          # O `ux/uy` e uma fotografia: onde o lancador estava, no ecra, no
          # instante do disparo. Enquanto ninguem anda da no mesmo. Mas basta
          # dar um passo — e a camara anda comigo — para o feixe deixar de sair
          # de mim e ficar pendurado no mapa a arder sozinho.
          #
          # Guardando o boneco, a fotografia passa a poder ser tirada outra vez
          # a cada frame.
          :de_quem => (de || $game_player),
          # ⚠️ E TAMBEM QUEM LEVA, PELO MESMO MOTIVO.
          #
          # Guardar so o lancador prendia metade da animacao. As celulas de foco
          # 1 pertencem ao ALVO — se ele anda e a ancora dele e uma fotografia,
          # o golpe fica a rebentar onde ele esteve. E com o `Rapid Spin`, que e
          # todo do proprio, era a MINHA ponta que estava congelada: rodopiava-se
          # e a animacao ficava para tras.
          :no_quem => character,
          # A ancora do ALVO, em coordenadas de ecra. A rotacao precisa dela:
          # e o ponto para onde a linha da folha tem de apontar.
          :ax => ax, :ay => ay,
          # ?? O COMPRIMENTO DA LINHA TEM DE SER O QUE SE MEDIU, E NAO O DA TABELA.
          #
          # Aqui ficava sempre o `feixe_casas` do editor ? o alcance maximo. So
          # que o `aplicar_feitio!` usa este numero para reposicionar TODAS as
          # celulas de foco 3 ao longo da linha: ele mandava-as ate ao alcance
          # inteiro, desfazendo o encurtamento que se tinha acabado de calcular.
          #
          # Era por isso que o feixe continuava a passar ao lado de quem estava
          # no caminho: a casa de destino ja estava certa, e a seguir esta conta
          # esticava o desenho para la dela outra vez.
          :casas => ((cfg["modo"].to_s == "feixe" && meu_feixe && @feixe_alcance) ?
                     @feixe_alcance.to_f :
                     (Math.sqrt((((ax - ux)**2) + ((ay - uy)**2)).to_f) /
                      Game_Map::TILE_WIDTH.to_f)),
          # Um feixe que nao e meu nao segue a minha mira: fica no rumo com que
          # saiu, que e o unico que diz respeito a quem o deu.
          :rumo_fixo => !meu_feixe,
          :rumos => []
        }
      end
      # O rebentamento em particulas, se o editor pediu um. Sai do MESMO ponto
      # onde a animacao vai rebentar (`ax, ay` e a ancora do alvo), senao viam-se
      # as particulas num sitio e a explosao noutro.
      soltar_particulas_finais!(jogador, idx, ax, ay, character)

      # As ancoras deste golpe morrem quando ele acabar.
      (@ancoras_de ||= {})[jogador] = [cena.sprites["pokemon_0"], cena.sprites["pokemon_1"]]
      # ⚠️ AS ANCORAS SAO TIRADAS UMA VEZ, EM COORDENADAS DE ECRA.
      #
      # Enquanto ninguem se mexe isso e igual a estar preso ao mapa. Mas basta a
      # camara andar — e ela anda sempre, porque ela segue o Pokemon — para a
      # animacao ficar colada ao ECRA e viajar com ele. Guarda-se quem ela devia
      # seguir e onde ele estava; a cada frame desloca-se tudo pela diferenca.
      # ⚠️ AQUI ESTAVA O DESVIO, E ERA O MARCADOR PARTILHADO.
      #
      # Ha UM unico evento de servico (`ID_MARCADOR`) e 29 sitios que lhe
      # chamam: toda a animacao que acontece numa CASA — o rebentamento de um
      # projectil, uma pedra da onda, um impacto no chao — e posta com ele. O
      # `tocar_no_chao!` faz-lhe `moveto(x, y)` e toca ali.
      #
      # Ate aqui tudo bem: a animacao nasce no sitio certo. O problema e o que
      # vem a seguir, porque esta linha guardava o MARCADOR como a coisa a
      # seguir, e depois o `seguir_animacao!` desloca a animacao inteira por
      # tudo o que ele andar.
      #
      # So que o marcador nao e desta animacao. E de todas. Basta um segundo
      # impacto acontecer enquanto a primeira ainda corre — e na arena isso e o
      # NORMAL, com o aliado, os selvagens, as particulas da onda e os feixes —
      # para o marcador saltar para a outra casa, e a animacao que ainda estava
      # a correr salta com ele. Nao se desloca um bocadinho: viaja a distancia
      # inteira entre os dois impactos.
      #
      # E exactamente o que se descreveu: "o ataque aparece do outro lado da
      # tela com o inimigo em outra posicao". O editor nunca teve culpa nenhuma
      # — a colocacao inicial esta certa, e depois a coisa e levada aos ombros
      # para outro sitio.
      #
      # Uma animacao numa casa pertence a CASA. Guarda-se a posicao no mapa e
      # calcula-se o ecra a partir dela; o marcador pode ir para onde quiser.
      # Quem toca num bicho de verdade continua a segui-lo, que e o que se quer.
      if (character.id rescue nil) == ID_MARCADOR
        mx = (character.instance_variable_get(:@real_x) rescue 0)
        my = (character.instance_variable_get(:@real_y) rescue 0)
        e0 = ecra_da_casa(mx, my)
        (@seguir_de ||= {})[jogador] = {
          :mapa_x => mx, :mapa_y => my, :x0 => e0[0], :y0 => e0[1]
        }
      else
        (@seguir_de ||= {})[jogador] = {
          :quem => character,
          :x0 => (character.screen_x rescue 0),
          :y0 => (character.screen_y rescue 0)
        }
      end
      # ⚠️ NUM FEIXE, QUEM COLOCA OS SPRITES E O FEITIO — E SO ELE.
      #
      # O `aplicar_feitio!` escreve as posicoes em ABSOLUTO, a partir do dono.
      # Somar-lhe por cima o deslocamento da casa seria mover a mesma coisa duas
      # vezes, por dois motivos diferentes, e o feixe fugia ao dobro.
      if cfg && cfg["modo"].to_s == "feixe"
        (@seguir_de[jogador] ||= {})[:fixo_no_dono] = true
      end
      # ⚠️ UM FEIXE TOCA ISTO A CADA TIQUE, E O LOG ENCHE-SE SO COM ELE.
      #
      # No ultimo ficheiro foram quatro segundos de Rapid Spin a escrever duas
      # linhas por tique — mais de trinta linhas iguais, que e quase um decimo
      # do tecto de 400 gasto num golpe so. O que interessa saber e ONDE a
      # animacao foi parar, e isso escreve-se uma vez por combinacao.
      chave = [idx, quem]
      @tocados ||= {}
      unless @tocados[chave]
        @tocados[chave] = true
        alvo_r = (character ? casa_real(character) : nil)
        registar("tocar: idx=#{idx} modo=#{(cfg ? cfg['modo'] : 'sem remendo').inspect} " \
                 "ancora=#{quem} em (#{alvo_r ? alvo_r.map { |v| v.round(2) }.join(',') : '?'}) " \
                 "ecra=(#{ax},#{ay}) eu=(#{ux},#{uy})")
      end
    rescue => e
      registar("tocar: o PBAnimationPlayerX REBENTOU: #{e.class}: #{e.message}")
      dizer("animação falhou: #{e.class}")
    end
  rescue => e
    registar("tocar: erro geral: #{e.class}: #{e.message}")
  end

  # Toca uma animacao numa casa do mapa, usando o evento invisivel de servico.
  # ⚠️ A BOLA NUNCA ERRA E A ANIMACAO ERRA. A DIFERENCA E O ARREDONDAMENTO.
  #
  # O jogador reparou nisto antes de mim: a Pokebola vai certeira em qualquer
  # direccao, e as animacoes perdem-se. Foi ver porque.
  #
  # A bola guarda a posicao em casas FRACCIONARIAS (`p[:x]`, `p[:y]`) e converte
  # para o ecra a cada frame, como o motor faz com toda a gente:
  #
  #     sp.x = ((p[:x] * REAL_RES_X - display_x) / X_SUBPIXELS) + TILE_WIDTH/2
  #
  # A animacao ia por outro caminho: `tocar_no_chao!` chamava `moveto`, e o
  # `moveto` so aceita CASA INTEIRA. O ponto a 6,03 / 2,43 casas virava 6 / 2 —
  # e o angulo com ele. Medido, a 6,5 casas de distancia:
  #
  #     +15 graus -> erra 3,4     +30 -> erra 3,4     +60 -> erra 3,4
  #     +22       -> erra 3,6     +45 -> erra 0,0 (cai na diagonal exacta)
  #
  # Tres graus e meio a seis casas sao quase meia casa de desvio na ponta. Nao
  # e a causa unica do que se viu, mas e uma que estava calada debaixo de todas
  # as outras, e nao ha afinacao que a compense — ela muda com o angulo.
  #
  # Isto poe o marcador no ponto exacto, escrevendo os sub-pixeis a mao em vez
  # de pedir uma casa ao `moveto`. E a mesma precisao da bola.
  # O gemeo do `garantir_marcador!`, com outro id. Duplicado de proposito: sao
  # dez linhas, e faze-lo generico obrigava a mexer no primeiro, que esta a
  # funcionar e tem tres notas por cima a explicar porque.
  def garantir_marcador2!
    return $game_map.events[ID_MARCADOR2] if $game_map && $game_map.events[ID_MARCADOR2]
    return nil unless $game_map && $game_player
    rpg = RPG::Event.new($game_player.x, $game_player.y)
    rpg.id   = ID_MARCADOR2
    rpg.name = "ArenaMarcador2Update"
    pag = rpg.pages[0]
    pag.graphic.character_name = (@charset.to_s.empty? ? "Followers/PIKACHU" : @charset.to_s)
    pag.graphic.opacity = 0
    pag.trigger = -1
    pag.through = true
    pag.list = [RPG::EventCommand.new(0, 0, [])]
    ev = Game_Event.new($game_map.map_id, rpg, $game_map)
    ev.through = true
    ev.opacity = 0
    pousar_evento!(ID_MARCADOR2, ev, rpg)
    ev.refresh
    (AnilLanRework::ReleasedRoaming.sync_sprite(ev) rescue nil) if $scene.is_a?(Scene_Map)
    ev
  rescue => e
    log("falha a criar o marcador 2: #{e.class}: #{e.message}")
    nil
  end

  # ⚠️ DE UM PONTO DO CHAO PARA UM BONECO.
  #
  # E o que faltava para desenhar o golpe de alguem que ainda nao esta na lista
  # de peers: a partida vem das coordenadas que ele escreveu no pacote, e o
  # alvo somos nos. A linha da animacao fica dele -> mim, que e a verdade do
  # que aconteceu.
  def tocar_do_ponto!(anim, ux, uy, alvo, desde = 0)
    return if anim.to_i <= 0
    ev = garantir_marcador2!
    return tocar_no_character!(alvo, anim, desde) unless ev
    ev.instance_variable_set(:@real_x, (ux.to_f * Game_Map::REAL_RES_X).round)
    ev.instance_variable_set(:@real_y, (uy.to_f * Game_Map::REAL_RES_Y).round)
    ev.instance_variable_set(:@x, ux.to_f.round)
    ev.instance_variable_set(:@y, uy.to_f.round)
    (ev.calculate_bush_depth rescue nil)
    tocar_no_character!(alvo, anim, desde, ev)
  rescue => e
    log("falha a tocar do ponto: #{e.class}: #{e.message}")
  end

  def tocar_no_ponto!(anim, fx, fy, desde = 0, de = nil)
    return if anim.to_i <= 0
    ev = garantir_marcador!
    return unless ev
    rx = (fx.to_f * Game_Map::REAL_RES_X).round
    ry = (fy.to_f * Game_Map::REAL_RES_Y).round
    ev.instance_variable_set(:@real_x, rx)
    ev.instance_variable_set(:@real_y, ry)
    ev.instance_variable_set(:@x, fx.to_f.round)
    ev.instance_variable_set(:@y, fy.to_f.round)
    (ev.calculate_bush_depth rescue nil)
    tocar_no_character!(ev, anim, desde, de)
  rescue => e
    log("falha a tocar no ponto: #{e.class}: #{e.message}")
  end

  # ⚠️ UMA ANIMACAO QUE NAO APONTA A NINGUEM AINDA TEM DE APONTAR PARA ALGUM LADO.
  #
  # O palco de batalha desenha tudo entre dois pontos fixos: quem lanca em
  # (128,224) e quem leva em (384,96) — em baixo a esquerda e em cima a direita.
  # O `setLineTransform` mapeia ESSA linha para a linha real, e e assim que a
  # animacao ganha direccao e tamanho no mapa.
  #
  # Um golpe que gira a volta de quem o da nao tem alvo, e entao punha-se o
  # mesmo boneco nas duas pontas. Uma linha de comprimento zero nao se pode
  # transformar, portanto ha uma guarda que empurra a ponta uma casa PARA ONDE
  # O JOGADOR OLHA — e ai esta o problema, porque quem gira muda de cara quatro
  # vezes por segundo. Se o tufao comecar num quadro em que se olha para a
  # esquerda, a linha real aponta ao contrario da linha do palco e a
  # transformacao ESPELHA o desenho inteiro. Era isto o "furacao invertido": nao
  # e sempre, e so quando a volta calha para o lado errado.
  #
  # A ponta passa a ser fixa e a condizer com o palco — uma casa para a direita
  # e uma para cima. A linha real fica com a mesma orientacao da linha desenhada,
  # nao ha espelho nenhum, e o desenho sai igual a cada volta.
  def tocar_ancorado_em!(quem, anim, desde = 0)
    return if anim.to_i <= 0
    return unless quem
    fx = (quem.x rescue 0) + 1
    fy = (quem.y rescue 0) - 1
    tocar_no_ponto!(anim, fx, fy, desde, quem)
  rescue => e
    log("falha a tocar ancorado: #{e.class}: #{e.message}")
  end

  # O ponto exacto a `casas` de distancia no rumo dado — sem arredondar.
  def ponto_no_rumo(rumo, casas)
    [$game_player.x + (rumo[0] * casas.to_f),
     $game_player.y + (rumo[1] * casas.to_f)]
  rescue
    casa_a_frente(casas.to_f.round)
  end

  def tocar_no_chao!(anim, x, y, desde = 0, de = nil)
    return if anim.to_i <= 0
    ev = garantir_marcador!
    return unless ev
    (ev.moveto(x, y) rescue nil)
    tocar_no_character!(ev, anim, desde, de)
  rescue => e
    log("falha a tocar no chao: #{e.class}: #{e.message}")
  end

  def garantir_marcador!
    return $game_map.events[ID_MARCADOR] if $game_map && $game_map.events[ID_MARCADOR]
    return nil unless $game_map && $game_player
    # ⚠️ UM EVENTO SEM GRAFICO NAO TOCA ANIMACOES.
    #
    # O `Sprite_Character#update` desiste logo no principio:
    #
    #     return if @character.is_a?(Game_Event) && !@character.should_update?   (188)
    #     return if !@charbitmap                                                 (191)
    #
    # e a animacao so e tratada na linha 224. Um marcador invisivel morria nas
    # duas portas: sem `character_name` nao ha `@charbitmap`, e um evento parado
    # que nao se move nao entra no `should_update?`.
    #
    # A saida e dar-lhe um grafico A SERIO e escondê-lo pela opacidade — o
    # `animation` do RGSS desenha em sprites proprios, portanto a opacidade zero
    # do boneco nao apaga a animacao. E o nome leva "Update" porque o
    # `should_update?` devolve true para eventos cujo nome tenha essa palavra
    # (0051:250) — e a unica forma limpa de o manter sempre vivo.
    rpg = RPG::Event.new($game_player.x, $game_player.y)
    rpg.id   = ID_MARCADOR
    rpg.name = "ArenaMarcadorUpdate"
    pag = rpg.pages[0]
    pag.graphic.character_name = (@charset.to_s.empty? ? "Followers/PIKACHU" : @charset.to_s)
    pag.graphic.opacity = 0
    pag.trigger = -1
    pag.through = true
    pag.list = [RPG::EventCommand.new(0, 0, [])]
    ev = Game_Event.new($game_map.map_id, rpg, $game_map)
    ev.through = true
    ev.opacity = 0
    pousar_evento!(ID_MARCADOR, ev, rpg)
    ev.refresh
    (AnilLanRework::ReleasedRoaming.sync_sprite(ev) rescue nil) if $scene.is_a?(Scene_Map)
    ev
  rescue => e
    log("falha a criar o marcador: #{e.class}: #{e.message}")
    nil
  end

  def apagar_marcador!
    return unless $game_map && $game_map.events[ID_MARCADOR]
    ev = $game_map.events[ID_MARCADOR]
    dados = ($game_map.instance_variable_get(:@map) rescue nil)
    dados.events.delete(ID_MARCADOR) if dados && dados.respond_to?(:events)
    if $game_map.respond_to?(:removeThisEventfromMap)
      $game_map.removeThisEventfromMap(ID_MARCADOR)
    else
      $game_map.events.delete(ID_MARCADOR)
    end
    if $scene.is_a?(Scene_Map)
      conj = ($scene.spriteset($game_map.map_id) rescue nil) || ($scene.spriteset rescue nil)
      if conj && conj.respond_to?(:character_sprites)
        i = conj.character_sprites.index { |sp| sp.character == ev }
        (conj.character_sprites.delete_at(i).dispose rescue nil) if i
      end
    end
  rescue
    nil
  end

  # Contra a IA e o evento; contra um jogador e o proprio boneco dele. Os dois
  # respondem a x, y e screen_x/screen_y, que e tudo o que a arena precisa.
  # Contra a IA e o evento do bicho mais proximo; contra um jogador e o boneco
  # dele. Os dois respondem a x, y e screen_x/screen_y, que e tudo o que a arena
  # precisa.
  # ⚠️ NA CAVERNA UM JOGADOR HOSTIL E UM ALVO, E A MIRA NAO O VIA.
  #
  # A mira escolhe o `bichos_vivos` mais perto — e um jogador nunca esta nessa
  # lista, porque ela e dos selvagens da IA. Resultado: com o inimigo humano
  # colado a nos, o golpe saia na direccao de um Geodude do outro lado da sala.
  # Foi isso o "eramos inimigos e nao nos atacamos": nao e que o dano fosse
  # recusado, e que os golpes nunca apontaram um para o outro.
  #
  # Aqui juntam-se os dois mundos e ganha o mais PROXIMO. O parceiro de coop
  # fica de fora da lista — nele nao se mira, e por isso nao se acerta por
  # acidente quando ele passa a frente.
  def jogadores_hostis
    return [] unless caverna?
    fora = []
    aqui = ($game_map.map_id.to_i rescue -1)
    (AnilLanRework.players rescue {}).each_pair do |pid, p|
      next unless p && p.respond_to?(:x)
      next unless (p.map_id.to_i == aqui rescue false)
      next if coop_amigo?(pid)
      fora << p
    end
    fora
  rescue
    []
  end

  # ⚠️ O MAIS PROXIMO, E PONTO. SEM EXCEPCOES.
  #
  # Eu tinha posto aqui uma: um jogador hostil a dez casas ou menos ganhava
  # sempre, mesmo com um selvagem colado a nos. A intencao era boa e o resultado
  # nao: quando ha um bicho a morder-nos a cara, a mira tem de estar nele — seja
  # quem for que esteja do outro lado da sala.
  #
  # Uma regra de mira so serve se for previsivel. "O mais proximo" e uma regra
  # que se le do ecra sem pensar: olha-se para quem esta mais perto e sabe-se
  # para onde o golpe vai. Qualquer excepcao, por melhor que soe escrita, obriga
  # o jogador a saber de cor uma tabela de prioridades a meio de uma luta.
  #
  # Selvagens e pessoas entram na MESMA lista e competem so pela distancia.
  def evento_inimigo
    return adversario_remoto if pvp?
    b = bicho_focado
    perto = b ? b[:ev] : nil
    return perto unless caverna?
    melhor = perto
    d_melhor = melhor ? distancia_casas(melhor, $game_player) : 9_999.0
    jogadores_hostis.each do |p|
      d = (distancia_casas(p, $game_player) rescue 9_999.0)
      next unless d < d_melhor
      d_melhor = d
      melhor = p
    end
    melhor
  rescue
    nil
  end

  # ⚠️ `raio` E UM TECTO, NAO UMA DISTANCIA — E ISSO ENGANOU-ME.
  #
  # Isto procura do anel 1 para fora e devolve o PRIMEIRO que sirva, portanto
  # pedir raio 12 nao poe ninguem a 12 casas: poe na primeira casa livre, que
  # e quase sempre colada ao jogador. Era o que fazia os selvagens da caverna
  # nascerem em cima de quem la estava — nao era a IA a ser agressiva, era o
  # sitio onde eles apareciam.
  #
  # O `minimo` diz de que anel se comeca a procurar. Fica opcional e a 1, que e
  # o que sempre fez, para nao mexer em quem ja chamava isto.
  def casa_livre_perto(cx, cy, raio, minimo = 1)
    inicio = [[minimo.to_i, 1].max, raio].min
    (inicio..raio).each do |r|
      (-r..r).each do |dx|
        (-r..r).each do |dy|
          next unless dx.abs == r || dy.abs == r
          x = cx + dx
          y = cy + dy
          next unless $game_map.valid?(x, y)
          # Nascer dentro de agua era o mesmo defeito, so que a estreia: o
          # ajudante aparecia no lago e ficava la.
          next if terreno_proibido?(x, y)
          next unless [2, 4, 6, 8].any? { |d| ($game_map.passable?(x, y, d) rescue false) }
          return [x, y]
        end
      end
    end
    nil
  rescue
    nil
  end

  #-----------------------------------------------------------------------------
  # GOLPES
  #-----------------------------------------------------------------------------
  # O indice da animacao do golpe, tirado do mesmo ficheiro que a batalha usa.
  def animacao_do_golpe(move_id)
    tabela = (pbLoadMoveToAnim rescue nil)
    return 0 unless tabela && tabela[0]
    real = (GameData::Move.try_get(move_id)&.id rescue move_id)
    (tabela[0][real] || 0).to_i
  rescue
    0
  end

  # ⚠️ A FORMA DO GOLPE E O QUE FAZ ISTO SER UM JOGO DE ACCAO.
  #
  # Um golpe fisico bate a uma casa a frente — obriga a aproximar. Um especial
  # vai em linha ate cinco — obriga a apontar. Um que atinge varios faz area a
  # volta de quem ataca — obriga a afastar. Sao tres regras, e ja dao tres
  # maneiras diferentes de jogar.
  #
  # Golpes com forma propria (Rollout a rolar, Fly a subir, Dig a esconder) vao
  # querer tratamento individual. Ficam para depois, em cima destas tres.
  # ⚠️ UMA ANIMACAO INTEIRA PARA DIZER "NAO ACERTEI" E BARULHO.
  #
  # O codigo mandava tocar sempre, e a nota que eu proprio la deixei dizia que
  # isso ensinava o alcance ao jogador. Ensina — nas primeiras cinco vezes.
  # Depois de se saber o alcance, cada golpe dado no vazio e meio segundo de
  # ecra tapado por uma explosao que nao aconteceu, e num combate a correr isso
  # esconde o que interessa: onde eles estao.
  #
  # A distancia aqui e generosa de proposito. O acerto verdadeiro decide-se a
  # chegada (`resolver_acerto!`), com o corredor apertado; isto so responde "ha
  # alguem perto que chegue para valer a pena?". Um quase-acerto continua a
  # desenhar-se; o que se corta e o golpe dado sozinho no meio do mapa.
  FOLGA_VALE_A_PENA = 1.5   # casas: um quase-acerto ainda se desenha

  # ⚠️ ESTE PORTAO SO CONHECIA SELVAGENS, E NA MASMORRA HA PESSOAS.
  #
  # Ele existe para nao se tocar uma animacao inteira por um golpe dado no
  # vazio, e a pergunta que faz e "ha alguem perto que chegue?". So que "alguem"
  # eram os `bichos_vivos` — os selvagens da IA. Um jogador inimigo nao esta
  # nessa lista, logo numa sala ja limpa a resposta era `vivos.empty?` e o golpe
  # morria aqui, sem animacao, sem projectil e sem uma palavra.
  #
  # Visto de dentro do jogo isso le-se exactamente como o utilizador o
  # descreveu: "o inimigo nao esta sendo um alvo". E nao tinha nada que ver com
  # tipos nem com o golpe — dependia de haver, ou nao, um selvagem por perto no
  # momento em que se carregou no botao. Com um Geodude ao lado o mesmo golpe
  # saia; sem ele, nao.
  def vale_a_pena_golpe?(forma, modo_ed, mv, anim)
    return true if pvp?               # do outro lado esta uma pessoa
    vivos = bichos_vivos.select { |b| b[:ev] }
    # Na masmorra, quem nao e do grupo e alvo como qualquer selvagem.
    vivos += jogadores_hostis.map { |p| { :ev => p } } if caverna?
    return false if vivos.empty?
    alcance =
      if modo_ed == "feixe"
        ((palco_da_anim(anim) || {})["feixe_casas"] || ALCANCE_FEIXE).to_f
      elsif modo_ed == "voo" || modo_ed == "voo_anim" || lancamento?(mv)
        alcance_do_lancamento(mv).to_f
      else
        case forma
        when :area  then RAIO_AREA.to_f
        when :linha then ALCANCE_LINHA.to_f
        else             1.0
        end
      end
    # ⚠️ UMA FOLGA FIXA E ENORME NUM GOLPE CURTO.
    #
    # A folga existe para um quase-acerto se desenhar na mesma. Uma casa e meia
    # sobre um golpe de dez e nada; sobre o Wing Attack, que alcanca 2,2, e 68%
    # a mais — e entre 2,2 e 3,7 casas o golpe SAIA sempre e FALHAVA sempre, com
    # a animacao a rebentar no vazio onde o projectil se esgotou.
    #
    # A folga passa a ser um quarto do alcance do proprio golpe, com o tecto de
    # antes. Um golpe curto deixa de prometer o que nao alcanca, e diz "sem
    # alcance!" como ja dizia para os outros.
    alcance += [FOLGA_VALE_A_PENA, alcance * 0.25].min
    vivos.any? { |b| b[:ev] && distancia_casas(b[:ev], $game_player) <= alcance }
  rescue
    true
  end

  def forma_do_golpe(mv)
    dados = (GameData::Move.get(mv.id) rescue nil)
    return :corpo unless dados
    alvo = (GameData::Target.get(dados.target) rescue nil)
    return :area if alvo && (alvo.num_targets > 1 || alvo.affects_foe_side)
    # ⚠️ ISTO SO PROMOVIA OS ESPECIAIS, E DEIXAVA OS DE STATUS NO CHAO.
    #
    # Categoria 1 e especial; categoria 2 e STATUS. Como so o 1 subia a :linha,
    # todos os golpes de status caiam em :corpo — que exige o alvo exactamente
    # uma casa a frente, no eixo. Medido: das 81 posicoes possiveis num raio de
    # cinco casas, o Somnifero acertava em UMA.
    #
    # Nao era o efeito que estava partido: era o golpe que nunca encostava. E
    # valia para o Toxico, a Onda Trueno, o Fogo-Fatuo, as Drenadoras — todos.
    #
    # Um po que se sopra, uma onda que se manda, um raio confuso: nada disso e
    # corpo a corpo. Vao pelo corredor, que ja existe e ja esta afinado.
    return :linha if dados.category == 1 || dados.category == 2
    :corpo
  rescue
    :corpo
  end

  def em_alcance?(forma, ax, ay, dir, bx, by)
    dx = bx - ax
    dy = by - ay
    case forma
    when :area
      return dx.abs <= RAIO_AREA && dy.abs <= RAIO_AREA
    when :linha
      # ⚠️ EXIGIR O EIXO EXACTO E EXIGIR UMA COISA QUASE IMPOSSIVEL.
      #
      # Isto pedia `dx == 0` — o alvo na mesma coluna, a casa certa. Medido:
      # dentro de cinco casas ha 81 posicoes possiveis e este teste aceitava 5.
      # O golpe errava em 94% dos sitios onde o jogador o via acertar, e a
      # sensacao que fica e "as vezes falha sem razao".
      #
      # A mesma regra do feixe, que ja funciona: mede-se ao COMPRIDO (ate ao
      # alcance) e ao TRAVES (a largura do golpe). Quem estiver dentro do
      # corredor leva. Continua a interessar apontar — quem esta atras ou de
      # lado nao e apanhado — mas deixa de ser preciso estar na casa exacta.
      ux = 0.0
      uy = 0.0
      case dir
      when 2 then uy = 1.0
      when 8 then uy = -1.0
      when 4 then ux = -1.0
      else        ux = 1.0
      end
      ao_longo = (dx * ux) + (dy * uy)
      de_lado  = ((dx * -uy) + (dy * ux)).abs
      return ao_longo > 0 && ao_longo <= ALCANCE_LINHA && de_lado <= LARGURA_FEIXE
    else
      case dir
      when 2 then return dx == 0 && dy == 1
      when 8 then return dx == 0 && dy == -1
      when 4 then return dy == 0 && dx == -1
      when 6 then return dy == 0 && dx == 1
      end
      false
    end
  rescue
    false
  end

  # ⚠️ O PP E O TRAVAO, E FAZ MAIS SENTIDO DO QUE UM NUMERO FIXO.
  #
  # Com uma recarga igual para todos, o golpe mais forte e sempre o melhor e o
  # jogo vira carregar no mesmo botao. O PP ja e a medida que o jogo usa para
  # dizer "isto e raro": um Scratch tem 35, um Hyper Beam tem 5. Herdar essa
  # escala da variedade de graca, sem inventar uma tabela nova para manter.
  #
  #   40 PP -> 5 s     20 PP -> 7,9 s     5 PP -> 10 s
  #
  # ⚠️ CINCO SEGUNDOS E MUITO, E E DE PROPOSITO.
  #
  # Com recargas de um segundo o combate virava carregar em tudo o que estivesse
  # pronto, e a posicao deixava de importar. Com cinco, cada golpe e uma
  # decisao: falhar custa a espera inteira, e o tempo entre golpes passa a ser
  # jogado a andar e a desviar — que e onde esta a graca de ser em tempo real.
  RECARGA_MIN_S = 2.0
  RECARGA_MAX_S = 10.0

  # ⚠️ O PP NAO E A FORCA — E ERA PELO PP QUE EU MEDIA.
  #
  # Um Tackle tem 35 PP e 40 de forca; um Hyper Beam tem 5 PP e 150. Medir pelo
  # PP dava ao Tackle quase seis segundos de espera, o que nao faz sentido
  # nenhum: e o golpe mais banal que existe. O jogador esperava que o tempo
  # viesse da FORCA, e tem razao — e a forca que diz o que um golpe vale.
  #
  #   40 de forca ou menos -> 2 s      (Tackle, Scratch, Ember)
  #   80 de forca          -> 6 s      (Shadow Ball, Seed Bomb)
  #   120 ou mais          -> 10 s     (Hyper Beam, Earthquake e afins)
  #
  # Golpes sem forca (estado, escudo, buff) ficam nos 4 s: nao fazem dano, mas
  # tambem nao podem ser martelados sem parar.
  RECARGA_SEM_FORCA = 4.0

  def recarga_do_golpe(mv)
    poder = (GameData::Move.get(mv.id).power.to_i rescue 0)
    if poder <= 0
      return (RECARGA_SEM_FORCA * 60.0).round
    end
    poder = [[poder, 40].max, 120].min
    seg = RECARGA_MIN_S + ((poder - 40) * ((RECARGA_MAX_S - RECARGA_MIN_S) / 80.0))
    (seg * 60.0).round
  rescue
    (RECARGA_MIN_S * 60).round
  end

  # Formula reduzida. Ver a nota de topo: nao e o pbCalcDamage.
  # ⚠️ A CONTA SECA EXISTE PARA A IA PODER PENSAR.
  #
  # O `dano` tem sorte dentro: a variacao de 85-100% e o critico. Chamar isso
  # para COMPARAR golpes seria pedir a IA que decidisse a moeda ao ar — e o
  # critico ainda deixava o `@critico` sujo para a mensagem seguinte. Aqui esta
  # a mesma formula sem sorte nenhuma; o `dano` e esta conta mais os dados.
  def dano_seco(atacante, defensor, mv)
    dados = (GameData::Move.get(mv.id) rescue nil)
    return [0.0, 1.0] unless dados
    poder = dados.power.to_i
    return [0.0, 1.0] if poder <= 0
    especial = (dados.category == 1)
    atq = especial ? atacante.spatk.to_i : atacante.attack.to_i
    atq = (atq * buff_de(atacante, especial ? :spatk : :atk))
    def_ = especial ? defensor.spdef.to_i : defensor.defense.to_i
    def_ = (def_ * buff_de(defensor, especial ? :spdef : :def))
    # ⚠️ O COLETE E O EVIOLITE SAO DEFESA, E ENTRAM NA DEFESA.
    #
    # Podiam entrar como um divisor no fim e dar o mesmo numero. Entram aqui
    # porque e o que eles sao — se um dia alguem ler esta conta a procura de
    # "porque e que este bicho aguenta tanto", quer encontra-lo na defesa dele.
    def_ = (def_ * (AnilArenaItens.factor_de_defesa(defensor, especial) rescue 1.0))
    def_ = 1.0 if def_ <= 0
    base = (((2.0 * atacante.level / 5.0 + 2.0) * poder * atq / def_) / 50.0) + 2.0
    tipos = [defensor.types].flatten.compact rescue []
    mult = (Effectiveness.calculate(dados.type, *tipos) rescue 1.0)
    # ⚠️ GUARDADA ANTES DO STAB, POR CAUSA DO EXPERT BELT.
    #
    # "Super-eficaz" e uma propriedade da tabela de tipos, e nao do total. Um
    # golpe neutro com STAB da 1.5 e nao e super-eficaz nenhum; se o Belt lesse
    # o `mult` depois desta linha, disparava em metade dos golpes do jogo.
    eficacia = mult
    meus = [atacante.types].flatten.compact rescue []
    mult *= 1.5 if meus.include?(dados.type)
    # ⚠️ AQUI ENTRAM AS HABILIDADES QUE MEXEM NO DANO. Ver o 201.
    #
    # E o unico sitio por onde TODO o dano passa — o meu, o do ajudante e o dos
    # selvagens —, portanto e o unico onde vale a pena por isto. Um `mult` de
    # zero quer dizer imunidade e quem chama ja sabe tratar disso.
    imu = (AnilArenaHabilidades.imunidade(defensor, dados.type) rescue nil)
    if imu == :nada
      mult = 0.0
    elsif imu == :cura
      # Curar com o golpe do outro: devolve-se negativo e o `dano` converte.
      mult = -1.0
    else
      mult *= (AnilArenaHabilidades.factor_de_dano(atacante, dados.type) rescue 1.0)
      # ⚠️ E OS ITENS DE QUEM BATE, no mesmo sitio e pela mesma razao: esta e a
      # unica porta por onde passa o dano de toda a gente. Um item posto aqui
      # vale para mim, para o ajudante e para os selvagens sem mais nada.
      #
      # Nada do que entra aqui se CONSOME — ver a nota do topo do 203 sobre a
      # IA usar esta mesma funcao para imaginar golpes.
      mult *= (AnilArenaItens.factor_de_ataque(atacante, dados, especial, eficacia) rescue 1.0)
    end
    [base, mult]
  rescue
    [0.0, 1.0]
  end

  def dano(atacante, defensor, mv)
    dados = (GameData::Move.get(mv.id) rescue nil)
    base, mult = dano_seco(atacante, defensor, mv)
    if base <= 0.0
      # Golpe sem forca: o efeito dele e o efeito, e nao um arranhao.
      return 0 if dados && (dados.category == 2 || dados.power.to_i <= 0)
      base = 2.0
    end
    if dados
      @critico = false
      taxa_crit = ((dados.flags rescue []) || []).any? { |x| x.to_s.downcase == "highcriticalhitrate" } ? 8 : 16
      if rand(taxa_crit).zero?
        mult *= 2.0
        @critico = true
      end
    end
    # ⚠️ ZERO VEZES E ZERO, E NAO UM.
    #
    # O `[total, 1].max` estava a transformar toda a imunidade num pontinho de
    # dano: Thunder Shock no Swampert (Terra) tirava 1 de vida em vez de nada, e
    # visto de fora parecia que os golpes nao matavam ninguem. A tabela de tipos
    # da arena e a mesma da batalha; se ela diz que nao afecta, nao afecta.
    # ⚠️ UM `mult` NEGATIVO E UMA ABSORCAO, NAO UM ERRO.
    #
    # O Volt Absorb e o Water Absorb curam com o golpe que levavam. Em vez de um
    # caminho a parte, a conta devolve dano negativo e quem fere ja sabe somar
    # em vez de subtrair — uma linha em cada sitio, em vez de um ramo novo.
    if mult < 0.0
      cura = (base * 0.25).round
      return -[cura, 1].max
    end
    return 0 if mult <= 0.0
    total = (base * mult * (0.85 + rand * 0.15)).round
    [total, 1].max
  rescue
    1
  end

  # ⚠️ NUNCA FALHA EM SILENCIO.
  #
  # Na primeira versao, se o golpe nao existisse ou estivesse a recarregar, isto
  # devolvia sem dizer nada — e do lado do jogador "carreguei e nao aconteceu
  # nada" tem cinco causas possiveis e nenhuma pista. Agora cada saida escreve o
  # motivo no painel. Custa uma linha e poupa uma ronda de perguntas.
  def usar_golpe!(indice, rotulo = "?")
    return unless @activa
    return if @derrota_ate
    if caido?
      dizer(_INTL("Você está caído — espere por um parceiro."))
      return
    end
    if distraido?
      dizer(_INTL("Apaixonado! Não conseguiu atacar."))
      return
    end
    if impedido?
      dizer(estado_activo == :congelado ?
            _INTL("Congelado — não consegue se mexer!") :
            _INTL("Paralisado — não consegue se mexer!"))
      return
    end
    # ⚠️ RECARGA EM SEGUNDOS, E NAO EM FRAMES.
    #
    # Estava a descontar 1 por passagem do `tick!`. So que o `Scene_Map#update`
    # nao corre exactamente uma vez por frame — em alguns caminhos corre duas ou
    # tres — e a recarga escoava-se a dobrar ou a triplicar. Dava para carregar
    # sem parar, que foi o que se viu.
    #
    # Um instante no relogio nao tem esse problema: seja o tick chamado uma vez
    # ou dez, o golpe so volta quando o tempo passar. E os numeros passam a
    # querer dizer o que dizem — 1,4 s e 1,4 s.
    @prontos ||= [0.0, 0.0, 0.0, 0.0]
    agora = Time.now.to_f
    if @prontos[indice].to_f > agora
      dizer("#{rotulo}: recarregando (#{(@prontos[indice] - agora).round(1)}s)")
      return
    end
    mv = (@meu.moves[indice] rescue nil)
    if mv.nil? || mv.id.nil?
      dizer("#{rotulo}: sem golpe neste botão")
      return
    end
    # ⚠️ SO O ESCUDO E QUE NAO SE USA A TOQUE.
    #
    # Um escudo com recarga era absurdo: o mesmo carregar que o levantava
    # gastava-lhe dez segundos de espera. Ele vive so no `correr_segurar!`.
    #
    # O feixe e outra coisa — o toque atira-o, e segurar continua a despejar.
    return if seguravel(mv) == :escudo

    # ⚠️ A recusa DIZ-SE. (ver a nota do topo desta funcao: nunca falhar em
    # silencio.) Carregar num botao e nao acontecer nada, com um item que o
    # jogador escolheu por, e do lado de la indistinguivel de um bug.
    unless escolha_permite?(@meu, mv)
      travado = golpe_travado(@meu)
      nome_t = (GameData::Move.get(travado).name rescue travado.to_s)
      item_t = (AnilArenaItens.nome_do_item(@meu.item_id) rescue "item")
      dizer(AnilLanRework.ui_format("O {1} só deixa usar {2}!", item_t, nome_t)) rescue nil
      return
    end
    marcar_escolha!(@meu, mv)

    @prontos[indice] = Time.now.to_f + (recarga_do_golpe(mv) / 60.0)
    forma = forma_do_golpe(mv)
    anim  = animacao_do_golpe(mv.id)
    ev    = evento_inimigo

    # ⚠️ UM LANCAMENTO NAO PASSA POR AQUI ABAIXO.
    #
    # O resto deste metodo desenha a animacao e marca um impacto para daqui a
    # tantos frames. Um arremesso nao tem impacto marcado: tem uma bola no mapa
    # que ainda nao sabe onde vai bater. Sai por cima, e a explosao vem depois,
    # de onde quer que ela pare.
    if clone?(mv)
      criar_clone!
      tocar_no_character!($game_player, anim) if anim.to_i > 0
      narrar((GameData::Move.get(mv.id).name rescue mv.id.to_s))
      return
    end

    if buff?(mv)
      if aplicar_buff!(@meu, mv)
        tocar_no_character!($game_player, anim) if anim.to_i > 0
        nome_b = (GameData::Move.get(mv.id).name rescue mv.id.to_s)
        dizer("#{nome_b}! #{buffs_activos(@meu).join(' ')}")
        return
      end
    end

    if armadilha?(mv)
      nome_a = (GameData::Move.get(mv.id).name rescue mv.id.to_s)
      # Sorteia-se PRIMEIRO e anuncia-se a seguir: o pacote leva as casas que
      # sairam, para o outro ecra ter o mesmo chao que este.
      casas = semear_armadilhas!(mv, nome_a, anim, true, $game_player.x, $game_player.y)
      if pvp?
        enviar!("arena_armadilha", "move" => mv.id.to_s, "anim" => anim.to_i,
                                   "ox" => $game_player.x, "oy" => $game_player.y,
                                   "casas" => casas)
      end
      return
    end

    # ⚠️ UM GOLPE MARCADO COMO FEIXE NAO ARREMESSA TAMBEM.
    #
    # O Flamethrower fazia as duas coisas ao mesmo tempo: o toque lancava um
    # projectil (o `lancou FLAMETHROWER` do log) e segurar tocava o feixe. Com o
    # feixe a ser agora a animacao inteira, ver as duas coisas juntas era a
    # confusao que se viu no ecra.
    #
    # E e tambem o que faltava ao Flame Burst: ele nao esta na lista FEIXES,
    # portanto nunca passava pelo `tique_do_feixe!` — marcar "feixe" no editor
    # nao tinha qualquer caminho no jogo. Agora tem: qualquer golpe marcado
    # assim toca a animacao ao longo da linha, esteja ou nao na lista.
    # ⚠️ O EDITOR OFERECIA SEIS MODOS E O JOGO SO CONHECIA UM.
    #
    # O painel deixa escolher entre "o proprio", "o alvo", "uma casa", "onde o
    # golpe acertar", "a propria animacao voa" e "feixe a frente" — e o codigo
    # do jogo so comparava com "feixe". Os outros cinco eram desenhados na
    # oficina, gravados no ficheiro, lidos pelo jogo... e deitados fora sem uma
    # palavra. Nao havia erro para se ver: o golpe caia na colocacao que o
    # `forma_do_golpe` adivinhou, e parecia que a oficina mentia.
    modo_ed = (palco_da_anim(anim) || {})["modo"].to_s

    # ⚠️ ISTO ESTAVA DEPOIS DO RAMO DO FEIXE, QUE RETORNA.
    #
    # Portanto o "sem alcance" nunca chegava a ser perguntado a um feixe — e os
    # feixes sao justamente os que mais enchem o ecra quando se disparam para o
    # nada. Era por isso que o aviso "nao funcionava": funcionava, mas so nos
    # golpes que nao precisavam dele.
    #
    # Sobe para antes de qualquer ramo que retorne. Um golpe que nao alcanca
    # ninguem nao desenha nada, seja de que tipo for.
    # ⚠️ SEIS CAMINHOS, E NENHUM DELES DIZIA O NOME.
    #
    # Um golpe pode sair por aqui como feixe, como lancamento, como onda, como
    # leque, como area ou pela colocacao do editor — e ate agora a unica maneira
    # de saber qual deles tinha sido era ler o codigo e adivinhar. Adivinhei
    # duas vezes no Surf e falhei as duas.
    #
    # Esta linha custa nada e responde de uma vez: o que o editor pediu, o que o
    # jogo acha que o golpe e, e por onde ele vai sair. Vai para o
    # `Data/anil_arena.txt`, que nao depende de interruptor nenhum.
    # ⚠️ E ESCREVE-SE UMA VEZ POR GOLPE, NAO UMA VEZ POR TIQUE.
    #
    # O `registar` abre e fecha o ficheiro a cada chamada. Num golpe de toque
    # isso e uma escrita e nao se sente; num FEIXE, que dispara a cada tique
    # enquanto se segura a tecla, sao dezenas de aberturas de ficheiro por
    # segundo — e o disco a ser aberto no meio do laco de desenho e exactamente
    # o que trava o jogo. O utilizador apanhou-o: "agora trava bastante ao
    # lancar ataques, pode ser o seu log". Era.
    #
    # A ficha de um golpe nao muda entre disparos: o que ela responde e "por
    # onde e que ESTE golpe sai", e isso e igual da primeira a centesima vez.
    # Uma por golpe chega, e a partir dai custa uma consulta a um Hash.
    @fichado ||= {}
    unless @fichado[mv.id]
      @fichado[mv.id] = true
      registar("golpe #{mv.id}: anim=#{anim} modo_editor=#{modo_ed.inspect} " \
               "forma=#{forma} seguravel=#{(seguravel(mv) rescue nil).inspect} " \
               "lancamento=#{(lancamento?(mv) rescue '?')} " \
               "em_volta=#{(em_volta?(mv) rescue '?')} area=#{(area?(mv) rescue '?')}")
    end
    unless vale_a_pena_golpe?(forma, modo_ed, mv, anim)
      dizer("#{(GameData::Move.get(mv.id).name rescue mv.id.to_s)}... sem alcance!")
      return
    end

    # Vira-se ANTES de tudo o que desenha: a mira do feixe e a casa da frente
    # leem a direccao, e queremos que leiam a nova.
    encarar_e_botar!(ev)

    saida = saida_do_golpe(mv, anim)
    if saida == :feixe
      cfg_f = palco_da_anim(anim)
      # ⚠️ UM FEIXE VAI ATE ONDE ALCANCA, E NAO ATE ONDE O INIMIGO ESTA.
      #
      # Ancorar a animacao NELE (o `tocar_no_character!` que aqui estava)
      # esticava-a ate ele — e com ele a andar, a linha esticava e encolhia
      # sozinha. A mira aponta o rumo; o comprimento e sempre o que o editor
      # definiu.
      unless feixe_a_correr?
        casas = ((cfg_f["feixe_casas"] || ALCANCE_FEIXE).to_f.round)
        casas = 1 if casas < 1
        casas = 20 if casas > 20
        # Desenha-se com o comprimento a que ele REALMENTE chega.
        travar_rumo!(casas)
        cx, cy = ponto_no_rumo(@feixe_rumo, @feixe_alcance)
        tocar_no_ponto!(anim, cx, cy)
        @feixe_anim = (@jogadores_anim || []).last
        @feixe_anim_idx = anim.to_i
      end
      nome_f = (GameData::Move.get(mv.id).name rescue mv.id.to_s)

      # ⚠️ O FEIXE NAO DIZIA NADA AO ADVERSARIO. NEM DANO NEM DESENHO.
      #
      # O `ferir_na_linha!` so magoa `bichos_vivos` — os selvagens. Num duelo o
      # adversario nao esta nessa lista: ele e uma pessoa, e a regra da arena e
      # que quem decide se levou e a VITIMA.
      #
      # Portanto um feixe, em PvP, nao lhe tirava vida nenhuma e nem sequer
      # aparecia no ecra dele. Como quase todos os golpes afinados no editor
      # estao marcados como feixe, isso da "nao vejo os ataques dele e ele nao
      # ve os meus" — que e o que se reportou.
      #
      # Manda-se o mesmo pacote dos outros golpes, com a forma "linha": ele ja
      # sabe desenhar e ja sabe decidir se o corredor o apanha.
      if pvp?
        enviar!("arena_golpe",
          "move"   => mv.id.to_s,
          "x"      => $game_player.x,
          "y"      => $game_player.y,
          "dir"    => $game_player.direction,
          "forma"  => "linha",
          "anim"   => anim.to_i,
          "atraso" => atraso_do_golpe(:linha, adversario_remoto, anim),
          "nivel"  => (@meu.level.to_i rescue 50),
          "atk"    => (@meu.attack.to_i rescue 50),
          "spatk"  => (@meu.spatk.to_i rescue 50))
        narrar(nome_f)
      else
        anunciar_na_caverna!(
          "move"   => mv.id.to_s,
          "x"      => $game_player.x,
          "y"      => $game_player.y,
          "dir"    => $game_player.direction,
          "forma"  => "linha",
          "anim"   => anim.to_i,
          "atraso" => 0,
          "nivel"  => (@meu.level.to_i rescue 50),
          "atk"    => (@meu.attack.to_i rescue 50),
          "spatk"  => (@meu.spatk.to_i rescue 50))
        ferir_na_linha!(mv, nome_f, @feixe_alcance)
      end
      return
    end

    # ⚠️ O EDITOR OFERECIA SEIS MODOS E O JOGO SO CONHECIA UM.
    #
    # Isto e a raiz de metade do que correu mal nesta ronda. O painel deixa
    # escolher entre "o proprio", "o alvo", "uma casa", "onde o golpe acertar",
    # "a propria animacao voa" e "feixe a frente" — e o codigo do jogo so
    # comparava com "feixe". Os outros cinco eram desenhados na oficina,
    # gravados no ficheiro, lidos pelo jogo... e deitados fora sem uma palavra.
    #
    # Nao havia erro nenhum para se ver: o golpe caia na colocacao que o
    # `forma_do_golpe` sempre adivinhou, portanto parecia que o editor mentia.
    # Mentia mesmo — mas o mentiroso era este lado.
    # ⚠️ O RAZOR LEAF MATAVA ANTES DE AS FOLHAS SAIREM, E A CULPA E DA TABELA.
    #
    # O `forma_do_golpe` decide pela categoria do golpe: especial e :linha (tem
    # viagem, logo tem atraso), o resto e :corpo (imediato, e so acerta na casa
    # colada). O Razor Leaf e FISICO — portanto caia em :corpo, e o dano saia no
    # instante em que se carregava no botao, com as folhas ainda na boca.
    #
    # A categoria diz como se calcula o dano, e nao a que distancia o golpe
    # acontece. Quem sabe isso e quem colocou a animacao: se ela e desenhada em
    # cima do ALVO, o golpe atravessa o campo, e o dano tem de esperar que ela
    # chegue la.
    #
    # Uma escolha na oficina vale mais do que um palpite pela categoria.
    forma = :linha if modo_ed == "alvo" && forma == :corpo

    # "Onde o golpe acertar" e "a propria animacao voa" sao lancamentos: a coisa
    # atravessa o campo e so rebenta quando toca. Se o editor pede isso, e isso
    # que se faz — mesmo que a tabela do jogo nao classifique o golpe como
    # lancamento.
    if saida == :voo
      lancar_meu_golpe!(mv, (GameData::Move.get(mv.id).name rescue mv.id.to_s), anim, ev)
      return
    end
    registar("golpe #{mv.id} forma=#{forma} anim=#{anim} inimigo=#{ev ? "(#{ev.x},#{ev.y})" : "NENHUM"} eu=(#{$game_player.x},#{$game_player.y}) dir=#{$game_player.direction}")

    # ⚠️ CADA FORMA NASCE NUM SITIO DIFERENTE, E ISSO E METADE DO JOGO.
    #
    # Um arranhao tem de aparecer NA CASA A FRENTE de quem ataca, mesmo que la
    # nao esteja ninguem — e isso que mostra o alcance e ensina a posicionar-se.
    # Um raio cai em cima do alvo. Uma area sai de quem a lanca.
    #
    # O motor so sabe tocar uma animacao em cima de um CHARACTER, e nao numa
    # casa qualquer. Por isso ha um evento invisivel de servico, que se muda
    # para a casa certa antes de tocar. Um so, reutilizado — criar e destruir um
    # evento por golpe enchia o mapa de lixo.
    # ?? O EDITOR OFERECIA SEIS MODOS E O JOGO SO CONHECIA UM.
    #
    # O painel deixa escolher entre "o proprio", "o alvo", "uma casa", "onde o
    # golpe acertar", "a propria animacao voa" e "feixe a frente" ? e este
    # codigo so comparava com "feixe". Os outros cinco eram desenhados na
    # oficina, gravados no ficheiro, lidos pelo jogo... e deitados fora sem uma
    # palavra. Nao havia erro para se ver: o golpe caia na colocacao que o
    # `forma_do_golpe` sempre adivinhou, e parecia que a oficina mentia.
    #
    # O que se escolheu vence o palpite. O `forma_do_golpe` fica para quem
    # nunca abriu o editor, que e a maioria dos 1550 golpes.
    case modo_ed
    when "quem"
      # ⚠️ AS DUAS ANCORAS NO MESMO SITIO E UMA LINHA DE COMPRIMENTO ZERO.
      #
      # E ha uma guarda que a desfaz empurrando a ponta uma casa PARA ONDE O
      # JOGADOR OLHA — o que quer dizer que a mesma animacao sai virada de
      # maneira diferente conforme a cara dele, e espelhada quando ele olha para
      # a esquerda ou para cima. Foi assim que o tufao do Rapid Spin aparecia
      # invertido.
      #
      # O `tocar_ancorado_em!` poe a ponta num sitio FIXO que condiz com a linha
      # do palco de batalha: sempre a mesma orientacao, sem espelho.
      tocar_ancorado_em!($game_player, anim) if anim > 0
    when "alvo"
      if anim > 0
        # ⚠️ UM GOLPE DE AREA ACERTA EM VARIOS E SO SE DESENHAVA NUM.
        #
        # O Razor Leaf apanha todos os que estao a volta — e desenhava-se em
        # cima do mais proximo apenas. Via-se um golpe a bater num Pokemon e
        # tres a cair, o que nao se le como golpe de area: le-se como bug.
        #
        # Quando a forma e :area, toca-se em cada um dos que vao levar. E o
        # mesmo desenho, so que onde ele acontece de verdade.
        #
        # Com tecto: quatro animacoes ao mesmo tempo ja e muito ecra, e mais do
        # que isso e sprites a mais por um golpe so.
        vitimas = (forma == :area) ? alvos_de_area(mv) : []
        if vitimas.length > 1
          vitimas.first(AREA_MAX_ANIMS).each { |e| tocar_no_character!(e, anim) }
        else
          ev_a = vitimas.first || evento_inimigo
          ev_a ? tocar_no_character!(ev_a, anim) : tocar_no_chao!(anim, *casa_a_frente(2))
        end
      end
    when "chao"
      tocar_no_chao!(anim, *casa_a_frente(1)) if anim > 0
    else
      case forma
      when :area
        # Sem remendo no editor, um golpe de area tambem se desenha em todos.
        # ⚠️ ISTO RETORNAVA, E O RETORNO SALTAVA O ANUNCIO AO ADVERSARIO.
        #
        # Eu tinha aqui uma copia do agendamento do impacto e um `return`. A
        # copia funcionava, mas o `return` passava por cima do bloco do PvP la
        # em baixo — e num duelo o golpe de area deixava de existir para o
        # outro lado.
        #
        # Desenha-se em todos e deixa-se seguir. O resto do metodo trata do
        # dano e do anuncio, e trata melhor do que uma copia.
        ja_desenhou = false
        vits = alvos_de_area(mv)
        if vits.length > 1 && anim > 0
          vits.first(AREA_MAX_ANIMS).each { |e| tocar_no_character!(e, anim) }
          ja_desenhou = true
        end
        # ⚠️ ANCORA IGUAL PARA OS DOIS = ANIMACAO SEM DIRECCAO.
        #
        # Aqui eu passava o proprio jogador como ALVO da animacao. Com os dois
        # pontos no mesmo sitio, a linha tem comprimento zero, o transform nao
        # sabe para onde apontar e a animacao sai centrada — e, pior, o motor
        # espelha as celulas quando acha a linha invertida. Era o Growl ao
        # contrario. Aponta-se ao inimigo mais proximo, como a batalha faz.
        unless ja_desenhou
          alvo_anim = evento_inimigo
          if alvo_anim
            tocar_no_character!(alvo_anim, anim)
          else
            tocar_no_chao!(anim, *casa_a_frente(2))
          end
        end
      when :linha
        # ⚠️ DOIS TEMPOS, PARA SE VER QUE VIAJOU.
        #
        # O ideal seria um projectil de verdade — as folhas do Razor Leaf a
        # atravessar o ecra. Isso e um sistema de sprites proprio, com posicao por
        # frame e colisao a meio do caminho; nao cabe neste prototipo.
        #
        # O que cabe, e le-se quase tao bem, e tocar a MESMA animacao duas vezes:
        # primeiro em quem ataca, e um instante depois no alvo. O olho junta as
        # duas e ve um golpe que saiu dali e foi bater ali.
        tocar_no_character!($game_player, anim)
        alvo_x, alvo_y = ev ? [ev.x, ev.y] : casa_a_frente(ALCANCE_LINHA)
        adiar_animacao!(anim, alvo_x, alvo_y, atraso_do_golpe(:linha, ev)) if anim > 0
      else
        # Corpo a corpo: SEMPRE na casa da frente, acerte ou nao.
        tocar_no_chao!(anim, *casa_a_frente(1)) if anim > 0
      end
    end

    nome = (GameData::Move.get(mv.id).name rescue mv.id.to_s)
    # Se o golpe nao tem animacao no move2anim.dat, diz-se — senao parecia que o
    # botao nao funcionava, quando o que faltava era o desenho.
    dizer("#{nome}: sem animação (anim=0)") if anim.to_i <= 0
    # ⚠️ UM GOLPE A DISTANCIA SO ACERTA QUANDO CHEGA.
    #
    # Antes, o acerto era decidido no instante em que se carregava no botao, mas
    # a animacao so alcanca o alvo 12 frames depois. Quem se mexesse nesse
    # intervalo era atingido a mesma, e quem la estava e saiu escapava — o que
    # se via era uma Sludge Bomb a explodir onde ja nao esta ninguem, e a contar
    # como acerto.
    #
    # Agora o disparo e o impacto sao dois momentos: o golpe sai, viaja, e so a
    # chegada e que se pergunta quem esta la. E o que torna desviar-se possivel,
    # que era o ponto todo da ideia.
    #
    # Corpo a corpo continua imediato: la nao ha viagem nenhuma.
    atraso = atraso_do_golpe(forma, ev, anim)

    if pvp?
      # So se anuncia — quem decide e a vitima. O atraso viaja no pacote para os
      # dois lados perguntarem "acertou?" no MESMO momento da animacao.
      enviar!("arena_golpe",
        "move"   => mv.id.to_s,
        "x"      => $game_player.x,
        "y"      => $game_player.y,
        "dir"    => $game_player.direction,
        "forma"  => forma.to_s,
        "anim"   => anim.to_i,
        "atraso" => atraso,
        "nivel"  => (@meu.level.to_i rescue 50),
        "atk"    => (@meu.attack.to_i rescue 50),
        "spatk"  => (@meu.spatk.to_i rescue 50))
      narrar(nome)
    else
      anunciar_na_caverna!(
        "move"   => mv.id.to_s,
        "x"      => $game_player.x,
        "y"      => $game_player.y,
        "dir"    => $game_player.direction,
        "forma"  => forma.to_s,
        "anim"   => anim.to_i,
        "atraso" => atraso,
        "nivel"  => (@meu.level.to_i rescue 50),
        "atk"    => (@meu.attack.to_i rescue 50),
        "spatk"  => (@meu.spatk.to_i rescue 50))
      if atraso <= 0
        resolver_acerto!(forma, mv, nome, $game_player.x, $game_player.y, $game_player.direction)
      else
        (@impactos ||= []) << {
          :em    => (Graphics.frame_count rescue 0) + atraso,
          :forma => forma, :mv => mv, :nome => nome,
          :x     => $game_player.x, :y => $game_player.y, :dir => $game_player.direction
        }
      end
    end
  rescue => e
    log("falha no golpe: #{e.class}: #{e.message}")
  end

  # ⚠️ O TEMPO DE VOO DEPENDE DA DISTANCIA, E TEM ARRANQUE.
  #
  # Um atraso fixo de 12 frames dava dois defeitos ao mesmo tempo. Perto, o
  # dano chegava ANTES de a bola sair do Pokemon — foi o que se viu no Volt
  # Switch. Longe, a bola ainda ia a meio caminho e o alvo ja tinha levado.
  #
  # Agora ha duas parcelas: um arranque, que e o tempo que a animacao leva a
  # sair de quem ataca, e o voo propriamente dito, proporcional as casas
  # percorridas. E o mais perto de uma hitbox que se consegue sem simular o
  # projectil casa a casa — e a diferenca sente-se: de perto o golpe e quase
  # imediato, de longe da tempo de sair da frente.
  ARRANQUE      = 8    # frames ate o golpe sair de quem ataca
  VOO_POR_CASA  = 4    # frames por casa percorrida

  # ⚠️ O EDITOR SABE QUANDO A ANIMACAO BATE. ISTO ADIVINHAVA.
  #
  # O atraso era uma conta sobre a distancia: arranque mais tantos frames por
  # casa. Serve para um projectil, que viaja mesmo. Nao serve para uma animacao
  # tocada em cima do alvo — essa nao viaja, ela DESENVOLVE-SE, e o momento em
  # que ela bate esta na propria animacao.
  #
  # O editor ja marca esse momento: e o "quando acertar, a animacao comeca no
  # quadro N" (`impacto_desde`). Se ele esta la, o dano espera por ele; a
  # cadencia e a do motor das animacoes, 20 quadros por segundo, portanto cada
  # quadro vale 3 frames de jogo.
  #
  # Era isto que faltava para o Pokemon parar de cair antes de a animacao
  # acabar. A conta da distancia fica para quem nao afinou o golpe.
  IMPACTO_A_MEIO = 0.45   # fraccao da animacao ate ela bater, quando nao se diz

  def quantos_quadros(anim)
    obj = animacoes_de_golpe[anim.to_i]
    return 0 unless obj
    n = (obj.length rescue 0)
    n.to_i
  rescue
    0
  end

  def atraso_do_golpe(forma, alvo, anim = 0)
    desde = impacto_desde_da_anim(anim).to_i
    if desde > 0
      quadros = (desde * (60.0 / CADENCIA_ANIM)).round
      return [[quadros, 0].max, 90].min
    end

    # ⚠️ NINGUEM MARCOU O QUADRO DO IMPACTO — E ISSO E O NORMAL.
    #
    # O `impacto_desde` esta a zero em todos os golpes afinados ate agora, o
    # que faz sentido: e um numero que obriga a ver a animacao quadro a quadro
    # para o descobrir. Nao se pode pedir isso 1550 vezes.
    #
    # Entao tira-se da propria animacao. Um golpe bate a meio do que desenha —
    # antes disso e a preparacao, depois e o rescaldo. Nao e exacto, mas e
    # PROPORCIONAL AO QUE SE VE, que a conta da distancia nunca foi: um golpe
    # colado dava zero frames de espera e o bicho caia com a animacao ainda a
    # comecar.
    #
    # Quem quiser exacto marca o quadro no editor, e essa escolha vence.
    quadros = quantos_quadros(anim)
    if quadros > 0
      espera = ((quadros * IMPACTO_A_MEIO) * (60.0 / CADENCIA_ANIM)).round
      return [[espera, 0].max, 90].min
    end

    return 0 if forma == :corpo
    casas = 1
    if alvo
      casas = ((alvo.x - $game_player.x).abs + (alvo.y - $game_player.y).abs)
      casas = 1 if casas < 1
    end
    ARRANQUE + (casas * VOO_POR_CASA)
  rescue
    ARRANQUE + VOO_POR_CASA
  end

  # Pergunta "quem esta aqui agora?" e aplica. Usa-se as coordenadas de ONDE o
  # golpe saiu — um projectil ja lancado nao muda de rumo porque o atacante
  # andou — mas a posicao do alvo e a DESTE momento.
  # Pergunta "quem esta aqui agora?" e aplica. Usa-se as coordenadas de ONDE o
  # golpe saiu — um projectil ja lancado nao muda de rumo porque o atacante
  # andou — mas a posicao do alvo e a DESTE momento.
  AREA_MAX_ANIMS = 4    # quatro animacoes ao mesmo tempo ja enchem o ecra

  # Quem um golpe de area vai apanhar, pela MESMA regra que o dano usa. Se
  # divergissem, voltava o descompasso entre o que se ve e o que acerta.
  def alvos_de_area(mv)
    px = $game_player.x
    py = $game_player.y
    dir = $game_player.direction
    bichos_vivos.select { |b| b[:ev] && em_alcance?(:area, px, py, dir, b[:ev].x, b[:ev].y) }
                .sort_by { |b| distancia_casas(b[:ev], $game_player) }
                .map { |b| b[:ev] }
  rescue
    []
  end

  # ⚠️ O TROCO DE UM GOLPE DE CONTACTO, E O DRENO, VOLTAM PARA QUEM BATEU.
  #
  # O `ferir_bicho!` sabe o que aconteceu mas nao sabe de quem foi o golpe — ele
  # e chamado por mim, pelo ajudante e por projecteis. Por isso ele anota, e
  # quem bateu recolhe aqui, que e onde essa informacao existe.
  #
  # `quem` e :eu ou :aliado.
  def recolher_troco!(quem)
    dreno = @dreno_pendente.to_i
    cont  = @contacto_pendente
    feito = @dano_feito_pendente.to_i
    @dreno_pendente = 0
    @contacto_pendente = nil
    @dano_feito_pendente = 0
    # ⚠️ O SHELL BELL E O LIFE ORB SAO O MESMO GESTO DO DRENO: pagam-se a quem
    # bateu, e so aqui se sabe quem foi. Por isso viajam com ele.
    #
    # E usam o `feito`, o dano que o alvo REALMENTE levou — pela mesma razao
    # pela qual o dreno passou a usa-lo. Um Shell Bell a curar 1/8 de um numero
    # que ninguem levou seria o mesmo defeito com outro nome.
    if feito > 0
      quem_bateu = (quem == :aliado) ? ((@aliado && @aliado[:pkmn]) rescue nil) : @meu
      maximo = (quem == :aliado) ? (@aliado && @aliado[:hp_max].to_i) : (@meu && @meu.totalhp.to_i)
      if quem_bateu && maximo.to_i > 0
        cura_i, perda_i = (AnilArenaItens.troco_de_quem_bateu(quem_bateu, feito, maximo) rescue [0, 0])
        if cura_i > 0
          if quem == :aliado && aliado_vivo?
            @aliado[:hp] = [@aliado[:hp] + cura_i, @aliado[:hp_max].to_i].min
            (@aliado[:pkmn].hp = @aliado[:hp]) rescue nil
          elsif quem == :eu && @meu
            @hp_meu = [@hp_meu + cura_i, @meu.totalhp.to_i].min
          end
        end
        if perda_i > 0
          if quem == :aliado && aliado_vivo?
            ferir_aliado!(perda_i, nil, nil)
          elsif quem == :eu && @meu
            @hp_meu = [@hp_meu - perda_i, 0].max
            terminar_derrota! if @hp_meu <= 0
          end
        end
      end
    end
    if dreno > 0
      if quem == :aliado && aliado_vivo?
        @aliado[:hp] = [@aliado[:hp] + dreno, @aliado[:hp_max].to_i].min
        (@aliado[:pkmn].hp = @aliado[:hp]) rescue nil
      elsif quem == :eu && @meu
        @hp_meu = [@hp_meu + dreno, @meu.totalhp.to_i].min
      end
      dizer(AnilLanRework.ui_format("Drenou {1} de vida!", dreno)) rescue nil
    end
    return unless cont
    est, chance, recuo = cont
    if recuo.to_f > 0.0
      # Espinhos: quem tocou leva uma fatia da propria vida maxima.
      if quem == :aliado && aliado_vivo?
        perda = [(@aliado[:hp_max].to_f / recuo).round, 1].max
        ferir_aliado!(perda, nil, nil)
      elsif quem == :eu && @meu
        perda = [(@meu.totalhp.to_f / recuo).round, 1].max
        @hp_meu = [@hp_meu - perda, 0].max
        terminar_derrota! if @hp_meu <= 0
      end
    end
    if est && rand(100) < chance.to_i
      # So o jogador tem maquina de estados propria; o ajudante nao, e por isso
      # fica de fora ate ela existir para ele.
      # A maquina de estados da arena trabalha por golpe, nao por estado solto;
      # sem uma porta para "aplica ESTE estado", o contacto so marca o efeito e
      # fica a espera de uma. Nao se inventa uma meia porta aqui.
      dizer(_INTL("O contato teve efeito!")) if quem == :eu
    end
  rescue
    nil
  end

  def resolver_acerto!(forma, mv, nome, ax, ay, dir)
    apanhados = bichos_vivos.select do |b|
      b[:ev] && em_alcance?(forma, ax, ay, dir, b[:ev].x, b[:ev].y)
    end
    if apanhados.empty?
      narrar("#{nome}... errou!")
      return
    end
    apanhados.each_with_index do |b, i|
      ferir_bicho!(b, dano_no_bicho(b, mv), mv, (i.zero? ? nome : nil))
    end
  rescue => e
    registar("falha a resolver acerto: #{e.class}: #{e.message}")
  end

  def correr_impactos_pvp!
    return if @impactos_pvp.nil? || @impactos_pvp.empty?
    agora = (Graphics.frame_count rescue 0)
    prontos = @impactos_pvp.select { |i| i[:em] <= agora }
    return if prontos.empty?
    @impactos_pvp -= prontos
    prontos.each { |i| receber_golpe!(i[:p]) }
  rescue
    @impactos_pvp = []
  end

  def correr_impactos!
    return if @impactos.nil? || @impactos.empty?
    agora = (Graphics.frame_count rescue 0)
    prontos = @impactos.select { |i| i[:em] <= agora }
    return if prontos.empty?
    @impactos -= prontos
    prontos.each { |i| resolver_acerto!(i[:forma], i[:mv], i[:nome], i[:x], i[:y], i[:dir]) }
  rescue
    @impactos = []
  end

  #-----------------------------------------------------------------------------
  # ENERGIA, CORRIDA, ESTADOS E GOLPES SEGURAVEIS
  #
  # ⚠️ A ENERGIA E O QUE FAZ A POSICAO IMPORTAR.
  #
  # Com recargas de cinco segundos, o tempo entre golpes ja e jogado a andar. A
  # energia da a esse tempo uma decisao: correr para fugir custa, aguentar o
  # escudo custa, segurar o lanca-chamas custa — e sao a mesma reserva. Quem
  # gasta tudo a fugir nao tem como se defender a seguir.
  #-----------------------------------------------------------------------------
  ENERGIA_MAX      = 100.0
  ENERGIA_REGEN    = 22.0    # por segundo, parado ou a andar normal
  ENERGIA_CORRIDA  = 26.0    # por segundo a correr
  ENERGIA_ESCUDO   = 34.0    # por segundo com o escudo em pe
  ENERGIA_FEIXE    = 24.0    # por segundo a segurar um feixe

  # Duas batidas na mesma direccao dentro desta janela = corrida.
  JANELA_BATIDA    = 18      # frames
  CORRIDA_BONUS    = 0.8     # somado ao move_speed enquanto corre

  # ⚠️ LISTA EXPLICITA, E NAO UMA REGRA ESPERTA.
  #
  # Tentei deduzir "isto e seguravel" do function_code e da categoria, e o
  # resultado era arbitrario: metade dos golpes de estado viravam escudo. Uma
  # lista curta e honesta — diz-se o que se sabe e acrescenta-se conforme se
  # descobre — e melhor do que uma regra que acerta a medias.
  ESCUDOS = [:PROTECT, :DETECT, :KINGSSHIELD, :SPIKYSHIELD, :BANEFULBUNKER,
             :OBSTRUCT, :SILKTRAP].freeze
  # ⚠️ O ESPELHO E O UNICO QUE NAO SE DEFENDE: ELE DEVOLVE.
  #
  # Numa batalha por turnos o Reflect e um numero a dividir o dano. Aqui, com
  # tudo a voar, ha uma leitura muito melhor e muito mais literal: o que vinha
  # para mim inverte o rumo e vai de volta para quem o mandou, com o dano dele.
  ESPELHOS = [:REFLECT, :MIRRORCOAT, :COUNTER, :MAGICCOAT, :LIGHTSCREEN].freeze
  # ⚠️ O GIRO NAO E UM GOLPE: E UM ESTADO EM QUE SE ANDA.
  #
  # Na batalha por turnos o Rapid Spin faz tres coisas de uma vez — bate, limpa
  # as armadilhas do proprio lado, e solta-se de quem o prendeu. Sao tres coisas
  # que num turno acontecem juntas por acaso, e que aqui podem acontecer juntas
  # por SENTIDO: um Pokemon a girar varre o que esta no chao por onde passa, e
  # o que lhe vem de encontro bate na rotacao e sai desviado.
  #
  # Por isso ele nao e um toque; e um botao que se mantem, como o escudo. A
  # diferenca — e e a diferenca toda — e que com este se ANDA.
  RODOPIOS = [:RAPIDSPIN, :MORTALSPIN].freeze
  FEIXES  = [:FLAMETHROWER, :THUNDERBOLT, :ICEBEAM, :HYDROPUMP, :SURF,
             :PSYBEAM, :BUBBLEBEAM, :AURORABEAM, :SOLARBEAM, :HYPERBEAM,
             :FLASHCANNON, :DRAGONBREATH, :POWERGEM, :ENERGYBALL].freeze

  # Enquanto se segura um feixe, ele bate a cada tantos frames — mais fraco do
  # que um golpe unico, mas continuo.
  FEIXE_CADENCIA   = 12
  FEIXE_FORCA      = 0.35    # fraccao do dano normal por tique

  #-- energia ------------------------------------------------------------------
  def energia;      (@energia || ENERGIA_MAX);            end
  def energia=(v);  @energia = [[v, 0.0].max, ENERGIA_MAX].min; end

  def gastar_energia!(por_segundo)
    custo = por_segundo * (@delta || (1.0 / 60.0))
    return false if energia < custo
    self.energia = energia - custo
    true
  end

  def repor_energia!
    ganho = ENERGIA_REGEN * (@delta || (1.0 / 60.0))
    # Nao se recupera enquanto se esta a segurar alguma coisa: senao o escudo
    # pagava-se a si proprio e ficava de pe para sempre.
    return if @a_segurar
    self.energia = energia + ganho
  end

  #-- estados ------------------------------------------------------------------
  # ⚠️ O ESTADO VEM DO TIPO DO GOLPE, E NAO DO function_code.
  #
  # O motor guarda o efeito de cada golpe num codigo que so a batalha por turnos
  # sabe interpretar, e traduzi-lo era construir uma tabela de centenas de
  # entradas para manter. O tipo ja diz o que se espera: um golpe electrico
  # paralisa, um de gelo congela, um venenoso envenena, um de fogo queima. Le-se
  # bem, acerta no que importa, e nao ha tabela nenhuma para envelhecer.
  ESTADOS_POR_TIPO = {
    :ELECTRIC => :paralisado,
    :ICE      => :congelado,
    :POISON   => :envenenado,
    :FIRE     => :queimado
  }.freeze

  # ⚠️ TRINTA POR CENTO x QUATRO ATACANTES E UM ATORDOAMENTO PERMANENTE.
  #
  # Cada golpe elctrico tinha 30% de me paralisar por 3 s. Com quatro selvagens
  # a bater, a probabilidade de eu estar SEMPRE paralisado era quase um. Nao era
  # o nivel 5 deles que me matava — era eu nunca poder jogar.
  #
  # Duas travas: metade da chance, e uma janela de imunidade depois de cada
  # estado passar. Assim um estado e um susto, e nao uma corrente.
  CHANCE_ESTADO = 15     # por cento
  IMUNE_APOS    = 4.0    # segundos sem poder voltar a ficar preso
  DOT_FRACAO    = 24.0   # veneno/queimadura por segundo

  # ⚠️ DORMIR E PAIXAO NAO SE LEEM NO TIPO — LEEM-SE NA FUNCAO.
  #
  # Os quatro de cima vem do tipo do golpe (electrico paralisa, gelo congela) e
  # e por isso que nao precisam de lista. Estes dois nao tem tipo proprio: um
  # Sing e NORMAL e um Attract tambem. O que os identifica e o `function_code`,
  # que o motor ja escreve — `SleepTarget`, `AttractTarget` — e e de la que se
  # leem, sem lista de golpes nenhuma.
  ESTADOS_POR_FUNCAO = {
    "SleepTarget"   => :adormecido,
    "AttractTarget" => :apaixonado
  }.freeze

  ESTADO_DURACAO = {     # segundos
    :paralisado => 3.0,
    :congelado  => 2.5,
    :envenenado => 8.0,
    :queimado   => 8.0,
    :adormecido => 5.0,
    :apaixonado => 6.0
  }.freeze

  ESTADO_COR = {
    :adormecido => [120, 130, 200],
    :apaixonado => [255, 140, 190],
    :paralisado => [230, 210, 40],
    :congelado  => [120, 200, 255],
    :envenenado => [180, 80, 200],
    :queimado   => [255, 120, 40]
  }.freeze

  def estado_do_golpe(dados)
    fc = dados.function_code.to_s
    ESTADOS_POR_FUNCAO.each { |chave, est| return est if fc.include?(chave) }
    ESTADOS_POR_TIPO[dados.type]
  rescue
    nil
  end

  def talvez_aplicar_estado!(move_id)
    dados = (GameData::Move.get(move_id) rescue nil)
    return unless dados
    estado = estado_do_golpe(dados)
    return unless estado
    return if rand(100) >= chance_de_estado(dados)
    return if Time.now.to_f < @imune_ate.to_f
    # Nao se acumula: um segundo golpe do mesmo tipo renova o tempo.
    @estado = estado
    @estado_ate = Time.now.to_f + ESTADO_DURACAO[estado].to_f
    @estado_tique = Time.now.to_f
    dizer(nome_do_estado(estado))
  rescue
    nil
  end

  # ⚠️ O ADVERSARIO TAMBEM ADOECE — sem isto metade do sistema nao existia.
  #
  # Ate agora so eu e que podia ficar paralisado ou queimado: os estados eram
  # aplicados na vitima, e contra a IA a vitima era sempre eu. Quem batia com um
  # golpe electrico nao via efeito nenhum e a conclusao obvia era "os de efeito
  # nao funcionam" — e estava certa.
  def aplicar_estado_no_bicho!(b, move_id)
    return unless b
    dados = (GameData::Move.get(move_id) rescue nil)
    return unless dados
    estado = estado_do_golpe(dados)
    return unless estado
    return if rand(100) >= chance_de_estado(dados)
    b[:estado] = estado
    b[:estado_ate] = Time.now.to_f + ESTADO_DURACAO[estado].to_f
    b[:estado_tique] = Time.now.to_f
    narrar("#{(b[:pkmn].speciesName rescue 'Inimigo')}: #{nome_do_estado(estado)}")
    actualizar_foco!
  rescue
    nil
  end

  def talvez_aplicar_estado_no_inimigo!(move_id)
    aplicar_estado_no_bicho!(bicho_focado, move_id)
  end

  # ⚠️ UM GOLPE DE ESTADO NAO PODE DEPENDER DE 30%.
  #
  # A Thunder Wave, o Will-O-Wisp e o Toxic nao fazem dano nenhum: e o efeito ou
  # e nada. Falhar dois em cada tres deixava-os a valer zero. Os golpes que ja
  # fazem dano mantem a chance pequena, que e o que os torna um bonus e nao uma
  # garantia.
  def chance_de_estado(dados)
    (dados.category == 2) ? 100 : CHANCE_ESTADO
  rescue
    CHANCE_ESTADO
  end

  def bicho_impedido?(b)
    return false unless b
    return false unless [:congelado, :paralisado, :adormecido].include?(b[:estado])
    Time.now.to_f < b[:estado_ate].to_f
  rescue
    false
  end

  def inimigo_impedido?
    bicho_impedido?(bicho_focado)
  end

  # Um golpe sem forca tem efeito; um golpe com forca e dano zero foi barrado
  # pelo tipo. Sao coisas diferentes e o painel tem de as separar, senao o
  # jogador nao sabe se acertou mal ou se nao acertou de todo.
  def golpe_de_estado?(mv)
    return false unless mv
    dados = (GameData::Move.get(mv.id) rescue nil)
    return false unless dados
    dados.category == 2 || dados.power.to_i <= 0
  rescue
    false
  end

  def mensagem_do_acerto(nome, d, mv)
    return "#{nome}! CRÍTICO -#{d}" if d > 0 && @critico
    return "#{nome}! -#{d}" if d > 0
    return "#{nome}!" if golpe_de_estado?(mv)
    "#{nome}... não afeta!"
  rescue
    nome.to_s
  end

  # Um golpe de estado nao tira vida: se tirasse, a Thunder Wave passava a ser
  # um ataque fraco em vez de uma paralisia.
  def dano_de_golpe(mv)
    dados = (GameData::Move.get(mv.id) rescue nil)
    return 0 if dados && (dados.category == 2 || dados.power.to_i <= 0)
    dano(@meu, @inimigo, mv)
  rescue
    0
  end

  def correr_estado_inimigo!
    agora = Time.now.to_f
    bichos_vivos.each do |b|
      next unless b[:estado]
      # ⚠️ O RELOGIO DO ESTADO NAO PARA — so o DESENHO e que espera.
      #
      # Saltar a volta inteira faria um bicho envenenado longe ficar envenenado
      # para sempre e sem perder vida: o veneno deixava de correr enquanto
      # ninguem olhasse. O que se salta e a cor do sprite e o sinal por cima da
      # cabeca, que sao a parte que so serve para ser vista.
      longe = longe_para_tratar?(b)
      sp = sprite_de(b[:ev])
      if agora >= b[:estado_ate].to_f
        b[:estado] = nil
        (sp.color.set(0, 0, 0, 0) rescue nil) if sp
        next
      end
      b[:sinal] = sinalizar_estado!(b[:ev], b[:estado], b[:sinal]) unless longe
      if sp && !longe && (@flashes.nil? || !@flashes.key?(sp))
        c = ESTADO_COR[b[:estado]]
        (sp.color.set(c[0], c[1], c[2], 90) rescue nil) if c
      end
      next unless [:envenenado, :queimado].include?(b[:estado])
      next if (agora - b[:estado_tique].to_f) < 1.0
      b[:estado_tique] = agora
      d = [(b[:hp_max] / DOT_FRACAO).round, 1].max
      @dano_de_estado = true
      begin
        ferir_bicho!(b, d)
      ensure
        @dano_de_estado = false
      end
    end
    actualizar_foco!
  rescue
    nil
  end

  #-----------------------------------------------------------------------------
  # OS ITENS QUE TRABALHAM DE TURNO A TURNO
  #
  # ⚠️ TRES SEGUNDOS SAO UM TURNO, E O NUMERO NAO E MEU.
  #
  # O veneno aqui ao lado tira `hp_max / DOT_FRACAO` por segundo, com
  # `DOT_FRACAO = 24`. No jogo o veneno tira 1/8 por turno. 24 = 8 x 3 — ou
  # seja, a arena ja tinha decidido, ha muito, que um turno vale tres segundos.
  #
  # Seguir esse numero em vez de escolher um novo e o que faz os Restos curarem
  # 1/16 por turno como no jogo. Se eu tivesse posto 1/16 por SEGUNDO, uns
  # Restos curavam o triplo do que devem e passavam a ser o melhor item do jogo
  # por uma distancia absurda.
  #
  # ⚠️ E o relogio e por Pokemon, nao global.
  #
  # Um relogio unico faria o bicho que entrou agora apanhar o tique do anterior
  # e curar-se no primeiro instante de vida. Cada um conta o seu.
  def correr_itens!
    return unless defined?(AnilArenaItens) && AnilArenaItens::LIGADO
    agora = Time.now.to_f
    @itens_tique ||= {}

    # ── eu ──────────────────────────────────────────────────────────────────
    if @meu && @hp_meu.to_i > 0
      if vez_do_item?(:eu, agora)
        maximo = @meu.totalhp.to_i
        var, msg = (AnilArenaItens.regeneracao(@meu, @hp_meu, maximo) rescue [0, nil])
        if var != 0
          @hp_meu = [[@hp_meu + var, maximo].min, 0].max
          dizer(msg) if msg
          terminar_derrota! if @hp_meu <= 0
        end
        cura, limpa, msgb = (AnilArenaItens.talvez_baga!(@meu, @hp_meu, maximo, estado_activo) rescue [0, false, nil])
        if cura > 0
          @hp_meu = [@hp_meu + cura, maximo].min
        end
        if limpa
          @estado = nil
          sp = sprite_de($game_player)
          (sp.color.set(0, 0, 0, 0) rescue nil) if sp
        end
        dizer(msgb) if msgb
      end
    end

    # ── o ajudante ──────────────────────────────────────────────────────────
    #
    # Sem estado proprio (ver a nota do contacto em `recolher_troco!`), por isso
    # a Lum nao tem aqui o que curar e devolve zero sozinha.
    if aliado_vivo? && @aliado[:pkmn]
      if vez_do_item?(:aliado, agora)
        maximo = @aliado[:hp_max].to_i
        var, msg = (AnilArenaItens.regeneracao(@aliado[:pkmn], @aliado[:hp], maximo) rescue [0, nil])
        cura, _l, msgb = (AnilArenaItens.talvez_baga!(@aliado[:pkmn], @aliado[:hp], maximo, nil) rescue [0, false, nil])
        total = var + cura
        if total != 0
          if total < 0
            ferir_aliado!(-total, nil, nil)
          else
            @aliado[:hp] = [@aliado[:hp] + total, maximo].min
            (@aliado[:pkmn].hp = @aliado[:hp]) rescue nil
          end
          dizer(msg) if msg
          dizer(msgb) if msgb
        end
      end
    end

    # ── os selvagens ────────────────────────────────────────────────────────
    bichos_vivos.each do |b|
      next unless b[:pkmn]
      next unless vez_do_item?(b.object_id, agora)
      maximo = b[:hp_max].to_i
      var, _m = (AnilArenaItens.regeneracao(b[:pkmn], b[:hp], maximo) rescue [0, nil])
      cura, limpa, _mb = (AnilArenaItens.talvez_baga!(b[:pkmn], b[:hp], maximo, b[:estado]) rescue [0, false, nil])
      b[:estado] = nil if limpa
      total = var + cura
      next if total == 0
      if total < 0
        # Pelo `ferir_bicho!`, para a morte e o resto correrem como sempre.
        ferir_bicho!(b, -total)
      else
        b[:hp] = [b[:hp] + total, maximo].min
        (b[:pkmn].hp = [b[:hp], 1].max) rescue nil
      end
    end
    actualizar_foco!
  rescue
    nil
  end

  def vez_do_item?(chave, agora)
    @itens_tique ||= {}
    ultimo = @itens_tique[chave]
    if ultimo.nil?
      # ⚠️ Quem chega agora nao ganha um tique de borla: comeca a contar.
      @itens_tique[chave] = agora
      return false
    end
    return false if (agora - ultimo.to_f) < AnilArenaItens::TURNO_SEG
    @itens_tique[chave] = agora
    true
  rescue
    false
  end

  #-----------------------------------------------------------------------------
  # UM CHEFE E MAIOR
  #
  # A cor ja o distinguia de longe; o tamanho diz de que TAMANHO de problema se
  # trata. Um dourado de nivel 140 nao deve ler-se igual a um roxo de 70.
  #
  # ⚠️ SO SE MEXE NUM SPRITE QUE AINDA ESTA A 1.0.
  #
  # O `zoom_y` nao e so meu: o desmaio encolhe-o de 1 para 0,25, e um dia a
  # respiracao pode passar por aqui. Escrever a escala a cada frame era ficar a
  # lutar com quem estiver a animar o boneco, e o resultado seria um sprite a
  # saltar entre dois tamanhos.
  #
  # Escreve-se uma vez, quando o sprite nasce (e volta a nascer a cada refresh do
  # mapa, e por isso isto continua a correr no tique em vez de ser so na
  # criacao). A partir dai o zoom ja nao e 1.0 e este metodo nao lhe toca mais.
  #
  # ⚠️ E cresce para CIMA, de graca.
  #
  # O `oy` de um Sprite_Character esta nos pes do boneco, nao no meio. Escalar
  # dali mantem-no assente na casa dele e faz o corpo subir — que e o que se
  # quer de uma coisa grande. Se o `oy` fosse ao centro, ele afundava meio corpo
  # no chao e havia que compensar a mao.
  CHEFE_ZOOM = { 1 => 1.2, 2 => 1.6 }.freeze

  def escalar_chefes!
    return unless caverna?
    bichos_vivos.each do |b|
      z = CHEFE_ZOOM[b[:chefe].to_i]
      next unless z
      next if longe_para_tratar?(b)
      next unless b[:ev]
      sp = sprite_de(b[:ev])
      next unless sp
      next unless (sp.zoom_x - 1.0).abs < 0.001
      (sp.zoom_x = z) rescue nil
      (sp.zoom_y = z) rescue nil
    end
  rescue
    nil
  end

  def nome_do_estado(e)
    case e
    when :adormecido then return _INTL("Dormindo!")
    when :apaixonado then return _INTL("Apaixonado!")
    when :paralisado then _INTL("Paralisado!")
    when :congelado  then _INTL("Congelado!")
    when :envenenado then _INTL("Envenenado!")
    when :queimado   then _INTL("Queimado!")
    else ""
    end
  end

  def estado_activo
    return nil unless @estado
    if Time.now.to_f >= @estado_ate.to_f
      # A imunidade so vale para os que tiram o controlo das maos.
      @imune_ate = Time.now.to_f + IMUNE_APOS if [:paralisado, :congelado].include?(@estado)
      @estado = nil
      sp = sprite_de($game_player)
      (sp.color.set(0, 0, 0, 0) rescue nil) if sp
      return nil
    end
    @estado
  end

  # ⚠️ ESTES SINAIS JA EXISTEM NO `Animations.rxdata`, E SAO DE MAPA.
  #
  # A 10 e o raio ("Trueno"), a 40 e a bolha de veneno, a 13 e o fogo, a 32 e o
  # coracao, a 36 e a bolha de pensar — que e a que mais se parece com os Zs de
  # quem dorme. Como sao animacoes DE MAPA, saem no tamanho certo por cima da
  # cabeca sem passar pelo meu redimensionador, e repetem-se de dois em dois
  # segundos enquanto o estado durar.
  # ⚠️ EU FUI BUSCAR SINAIS AO FICHEIRO ERRADO.
  #
  # Eu tinha ido ao `Animations.rxdata` — as animacoes de MAPA — e escolhido
  # o que mais se parecia: o raio do "Trueno" para a paralisia, uma bolha de
  # pensar para o sono. Foi o que havia: sao 55 animacoes de mapa e NENHUMA
  # e de gelo, por isso o congelado ficou sem sinal nenhum. So a tinta azul.
  #
  # Os sinais a serio estao no OUTRO ficheiro, o `PkmnAnimations.rxdata`, que
  # e o que a arena ja usa para os golpes. O Essentials tras os cinco feitos:
  #
  #     5 Common:Sleep      18 quadros
  #     7 Common:Poison     20 quadros
  #     9 Common:Burn        7 quadros
  #    10 Common:Paralysis  13 quadros
  #    11 Common:Frozen      8 quadros
  #
  # Sao os mesmos que aparecem na batalha por turnos, portanto ja se conhecem
  # de olhos fechados. E ha um para o gelo, que era o que faltava.
  #
  # A paixao nao tem um destes — fica com o coracao do mapa, que serve bem.
  SINAL_DO_GOLPE = {
    :adormecido => 5,
    :envenenado => 7,
    :queimado   => 9,
    :paralisado => 10,
    :congelado  => 11
  }.freeze
  SINAL_DO_MAPA = {
    :apaixonado => 32     # o coracao; nao ha equivalente nas de golpe
  }.freeze
  SINAL_CADENCIA = 2.0

  def sinalizar_estado!(character, estado, marca)
    return marca unless character && estado
    agora = Time.now.to_f
    return marca if (agora - marca.to_f) < SINAL_CADENCIA

    if (idx = SINAL_DO_GOLPE[estado])
      # As duas ancoras em quem tem o estado: o sinal e dele, nao vem de
      # ninguem. Sem isto sai da cabeca de quem lancou o golpe.
      tocar_no_character!(character, idx, 0, character)
      return agora
    end
    id = SINAL_DO_MAPA[estado]
    return marca unless id
    return marca unless ($data_animations && $data_animations[id] rescue false)
    (character.animation_id = id) rescue nil
    agora
  rescue
    marca
  end

  def correr_estado!
    e = estado_activo
    return unless e
    @sinal_meu = sinalizar_estado!($game_player, e, @sinal_meu)
    # A cor fica enquanto o estado durar. O flash de dano sobrepoe-se por uns
    # frames e depois isto volta a pintar — sao camadas do mesmo `color`.
    sp = sprite_de($game_player)
    if sp && (@flashes.nil? || !@flashes.key?(sp))
      c = ESTADO_COR[e]
      (sp.color.set(c[0], c[1], c[2], 90) rescue nil) if c
    end
    # Veneno e queimadura tiram vida de segundo a segundo.
    if [:envenenado, :queimado].include?(e) && (Time.now.to_f - @estado_tique.to_f) >= 1.0
      @estado_tique = Time.now.to_f
      d = [(@meu.totalhp / DOT_FRACAO).round, 1].max
      @hp_meu = [@hp_meu - d, 0].max
      dizer("-#{d}")
      if @hp_meu <= 0
        enviar!("arena_fim", "perdi" => true) if pvp?
        sair!
        pbMessage(_INTL("Seu Pokémon foi derrotado na arena.")) rescue nil
      end
    end
  rescue
    nil
  end

  # ⚠️ PARALISADO E PARADO, E NAO "UM POUCO MAIS LENTO".
  #
  # Antes a paralisia tirava velocidade e falhava um golpe em cada tres. Numa
  # luta em tempo real isso e invisivel: o jogador leva um golpe electrico,
  # continua a andar e a atacar, e conclui — com razao — que os golpes de
  # estado nao fazem nada. Tres segundos parado sao tres segundos que se veem, e
  # sao curtos que baste para nao roubar a luta a ninguem.
  def impedido?
    e = estado_activo
    e == :congelado || e == :paralisado || e == :adormecido
  end

  # ⚠️ A PAIXAO NAO PRENDE: ATRAPALHA.
  #
  # Prender ja e o que o gelo e a paralisia fazem, e um terceiro igual nao
  # acrescenta nada. Apaixonado anda e ataca — so que metade das vezes o golpe
  # nao sai, e diz-se porque. E a leitura da serie, e da para jogar contra.
  def distraido?
    estado_activo == :apaixonado && rand(2).zero?
  end

  #-- corrida ------------------------------------------------------------------
  def correr_corrida!
    return if impedido?
    dir = ($game_player.direction rescue 2)
    agora = (Graphics.frame_count rescue 0)

    # ⚠️ A SEGUNDA BATIDA CONTA-SE NO `trigger?`, NAO NO `press?`.
    #
    # Com `press?` uma direccao segurada estava "carregada" em todos os frames, e
    # a janela nunca fechava: um unico toque virava corrida logo. O `trigger?` so
    # e verdade no frame em que a tecla desce — que e exactamente o que uma
    # "batida" quer dizer.
    #
    # A corrida dura enquanto a direccao ficar em baixo; largar cancela.
    [2, 4, 6, 8].each do |d|
      botao = botao_da_direccao(d)
      next unless (Input.anil_arena_orig_trigger?(botao) rescue false)
      if @ultima_dir == d && (agora - @ultima_batida.to_i) <= JANELA_BATIDA
        # Com o Agility a correr, o duplo-toque nao e correr: e saltar.
        if pode_investir?
          investida!
        else
          @a_correr = true
        end
      end
      @ultima_dir = d
      @ultima_batida = agora
    end
    # O dedo no botao vale como corrida enquanto la estiver.
    if dedo_no_correr? || tecla_do_correr?
      @a_correr = true
    elsif @a_correr && !(Input.anil_arena_orig_press?(botao_da_direccao(@ultima_dir.to_i)) rescue false)
      # Largou a direccao com que arrancou? Acabou a corrida.
      @a_correr = false
    end

    # A corrida so gasta energia; a velocidade e lida no movimento livre, que ja
    # nao passa pelo `move_speed` do motor.
    @a_correr = false if @a_correr && !gastar_energia!(ENERGIA_CORRIDA)
  rescue
    nil
  end

  #-----------------------------------------------------------------------------
  # A POKEBOLA
  #
  # ⚠️ APANHAR NUM COMBATE SEM TURNOS NAO PODE SER UM MENU.
  #
  # Na batalha normal a captura e uma escolha do turno: abre-se a mochila, e o
  # jogo pausa a espera. Aqui nao ha pausa nenhuma para abrir. A bola e mais um
  # arremesso — sai da mao, voa, e se acertar faz a conta. Quem quer apanhar tem
  # de enfraquecer primeiro e depois acertar, que e exactamente o que a captura
  # sempre quis dizer.
  #
  # A conta e a da serie, simplificada: a vida que resta pesa, a taxa da especie
  # pesa, a bola pesa, e um bicho adormecido ou paralisado vale mais.
  #-----------------------------------------------------------------------------
  TECLA_BOLA = :L        # Q no teclado; L no ecra do JoiPlay
  BOLA_VEL   = 9.0
  BOLA_ALCANCE = 8.0

  # ⚠️ A MESMA LISTA SERVE PARA ESCOLHER E PARA MOSTRAR.
  #
  # A ordem estava escrita dentro do `bola_no_saco` e so ele a via. Agora o
  # leque tambem precisa dela — e duas copias da mesma ordem seriam duas coisas
  # para manter de acordo.
  BOLAS_ORDEM = [:POKEBALL, :GREATBALL, :ULTRABALL, :PREMIERBALL, :NESTBALL,
                 :NETBALL, :DIVEBALL, :TIMERBALL, :QUICKBALL, :DUSKBALL,
                 :REPEATBALL, :LUXURYBALL, :HEALBALL, :LEVELBALL, :LUREBALL,
                 :MOONBALL, :FRIENDBALL, :LOVEBALL, :HEAVYBALL, :FASTBALL,
                 :SPORTBALL, :SAFARIBALL, :DREAMBALL, :BEASTBALL].freeze

  def bolas_na_mochila
    BOLAS_ORDEM.select { |id| ($bag.has?(id) rescue false) }
  rescue
    []
  end

  # ⚠️ ESCOLHIDA A MAO GANHA, E GUARDA-SE PELO ITEM.
  #
  # A mesma regra das pocoes: gastar a ultima Great Ball muda a lista de sitio,
  # e um indice guardado passava a apontar para outra bola sem ninguem lhe
  # tocar. Guarda-se QUAL; se ela acabar, volta a escolha automatica.
  def bola_escolhida
    return @bola_escolhida if @bola_escolhida && ($bag.has?(@bola_escolhida) rescue false)
    @bola_escolhida = nil
  end

  def rodar_bola!
    lista = bolas_na_mochila
    return if lista.length < 2
    i = (lista.index(bola_escolhida || bola_automatica) || 0)
    @bola_escolhida = lista[(i + 1) % lista.length]
    (pbSEPlay("GUI sel cursor", 70) rescue nil)
    dizer((GameData::Item.get(@bola_escolhida).name rescue "?"))
  rescue
    nil
  end

  def bola_no_saco
    b = bola_escolhida
    return b if b
    bola_automatica
  end

  def bola_automatica
    return nil unless $bag
    # A primeira bola que houver na mochila, da mais fraca para a mais forte:
    # gastar a Master numa Rattata por engano seria imperdoavel.
    ordem = [:POKEBALL, :GREATBALL, :ULTRABALL, :PREMIERBALL, :NESTBALL,
             :NETBALL, :DIVEBALL, :TIMERBALL, :QUICKBALL, :DUSKBALL,
             :REPEATBALL, :LUXURYBALL, :HEALBALL, :LEVELBALL, :LUREBALL,
             :MOONBALL, :FRIENDBALL, :LOVEBALL, :HEAVYBALL, :FASTBALL,
             :SPORTBALL, :SAFARIBALL, :DREAMBALL, :BEASTBALL]
    ordem.each { |id| return id if ($bag.has?(id) rescue false) }
    nil
  rescue
    nil
  end

  def multiplicador_da_bola(id)
    case id
    when :MASTERBALL              then 255.0
    when :ULTRABALL, :BEASTBALL   then 2.0
    when :GREATBALL, :SAFARIBALL, :SPORTBALL then 1.5
    else 1.0
    end
  end

  # ⚠️ O ICONE DE UM ITEM TEM 48 PX. UM POKEMON NO MAPA TEM 32.
  #
  # Eu punha o icone da bola no mapa sem lhe tocar no tamanho — e uma bola maior
  # do que o Pokemon a quem e atirada nao e uma bola, e um meteoro. Encolhe-se
  # para 20 px, que e mais ou menos o que ela mede na mao de um treinador.
  BOLA_PX = 20.0

  # ⚠️ E AS ANIMACOES DE PRENDER JA EXISTEM NO JOGO.
  #
  # O `Animations.rxdata` tem 55 animacoes DE MAPA — as do relvado a mexer, as
  # dos baloes de emocao — e entre elas estao a 26/27/30 ("Pokemon Ball Out") e
  # a 29 ("Pokemon Ball In"), da folha `Follower_ComeInOut`. Sao exactamente as
  # que se veem quando se solta ou recolhe um seguidor, ja desenhadas a escala
  # do mapa. Nao ha nada a inventar: e por-lhe o numero no `animation_id`, que e
  # o caminho normal do motor para animacoes de mapa.
  ANIM_PRENDER = 29

  # ⚠️ UMA BOLA NO CHAO E UM OBJECTO DO MAPA, NAO UM EFEITO POR CIMA DELE.
  #
  # Tudo o que esta arena desenha vive num viewport a z=99990, acima de tudo —
  # e o certo para uma animacao de golpe, que tem de se ver sempre. Mas uma bola
  # pousada no chao tem de ficar ATRAS de quem passa a frente dela, senao
  # parece colada ao ecra.
  #
  # O mapa e os personagens vivem no `Spriteset_Map.viewport` (z=0), e ordenam-se
  # entre si pelo `screen_z`, que cresce com a altura no ecra. Poe-se a bola la,
  # com o z de quem esta na casa dela menos um, e o motor ordena-a sozinho.
  # ⚠️ O VIEWPORT DO MAPA TRAZ O TOM DO MAPA — E ELE PINTA TUDO O QUE LA ESTA.
  #
  # Eu pus a bola no viewport dos personagens para ela poder ser tapada por quem
  # passasse a frente. Só que esse viewport leva o tom do dia e da noite, e das
  # grutas: a bola saia escurecida e lavada, e o icone dela e 100% opaco (fui
  # confirmar os pixeis do PNG — so tem alfa 0 e 255). Nao era opacidade minha,
  # era o mundo a pintar por cima.
  #
  # Um viewport so dela, logo acima do mapa e muito abaixo das animacoes, sai
  # com a cor verdadeira. Perde-se o ser tapada por quem passa a frente — mas
  # ganha-se ficar por cima de quem esta a ser apanhado, que e o que importa
  # ver, e a cor certa.
  def viewport_do_chao
    return @vp_chao if @vp_chao && !(@vp_chao.disposed? rescue true)
    @vp_chao = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @vp_chao.z = 90
    @vp_chao
  rescue
    viewport_das_animacoes
  end

  def sprite_da_bola(id, no_chao = false)
    caminho = (GameData::Item.icon_filename(id) rescue nil)
    return nil unless caminho && (pbResolveBitmap(caminho) rescue nil)
    sp = Sprite.new(no_chao ? viewport_do_chao : viewport_das_animacoes)
    sp.bitmap = (AnimatedBitmap.new(caminho).deanimate rescue nil)
    return nil unless sp.bitmap
    # ⚠️ A opacidade a mao: o valor herdado nao e de confianca depois de o
    # sprite passar por um viewport que nao e o nosso, e a bola aparecia
    # lavada, como se estivesse a 70%.
    sp.opacity = 255
    sp.blend_type = 0
    lado = [sp.bitmap.width, sp.bitmap.height].max.to_f
    lado = 48.0 if lado <= 0
    sp.zoom_x = BOLA_PX / lado
    sp.zoom_y = BOLA_PX / lado
    sp.ox = sp.bitmap.width / 2
    sp.oy = sp.bitmap.height / 2
    (@bitmaps_bola ||= []) << sp.bitmap
    sp
  rescue
    nil
  end

  # ⚠️ A MESMA TECLA FAZ DUAS COISAS, E E O TEMPO QUE AS SEPARA.
  #
  # Nao ha teclas a sobrar: os quatro golpes, o correr e esta. Por isso o Q faz
  # as duas coisas que uma pocao precisa — usar e escolher — e o que as separa e
  # quanto tempo o dedo fica la.
  #
  # Um toque usa. Segurar roda o leque, e a partir do momento em que rodou o
  # LARGAR ja nao usa nada: senao trocar de pocao gastava sempre a ultima para
  # onde se rodou, que e o contrario de escolher.
  REMEDIO_SEGURA = 0.3    # segundos ate isto deixar de ser um toque
  REMEDIO_RODA   = 0.28   # segundos entre pocoes enquanto se segura

  def correr_tecla_do_remedio!(botao)
    agora = Time.now.to_f
    carregada = if Input.respond_to?(:anil_arena_orig_press?)
                  (Input.anil_arena_orig_press?(botao) rescue false)
                else
                  (Input.press?(botao) rescue false)
                end
    unless carregada
      if @q_desde && !@q_rodou
        # Um toque: na masmorra cura, fora dela atira.
        caverna? ? usar_remedio! : atirar_bola!
      end
      @q_desde = nil
      @q_rodou = false
      @q_proxima = 0.0
      return
    end
    unless @q_desde
      @q_desde = agora
      @q_proxima = agora + REMEDIO_SEGURA
      return
    end
    return if agora < @q_proxima.to_f
    @q_proxima = agora + REMEDIO_RODA
    caverna? ? rodar_remedio! : rodar_bola!
    @q_rodou = true
  rescue
    nil
  end

  def atirar_bola!
    return unless @activa
    # ⚠️ NA CAVERNA NAO SE APANHA. E O PRECO DE LA SE PODER PERDER TUDO.
    #
    # O que se leva de la e o que se apanha do chao, e isso pode-se perder ao
    # cair. Um Pokemon apanhado nao se perde — ficava no PC, fora do alcance da
    # regra — e entao a caverna passava a ser a maneira mais barata de encher a
    # caixa: entra-se, apanha-se, sai-se de corda.
    # ⚠️ A TECLA NAO FICA MORTA: PASSA A CURAR.
    #
    # Na caverna nao ha nada para apanhar, e uma tecla que so serve para dizer
    # "nao da" e uma tecla desperdicada — ainda por cima a unica que sobrava
    # depois dos quatro golpes. Curar a meio da luta e precisamente o que falta
    # la dentro, e nao ha como fazer isso: abrir a mochila para uma pocao
    # significa parar o jogo enquanto tres Pokemon batem.
    if caverna?
      usar_remedio!
      return
    end
    if @captura
      dizer(_INTL("A bola está balançando!"))
      return
    end
    if pvp?
      dizer(_INTL("Não dá para capturar o Pokémon de outro treinador."))
      return
    end
    agora = Time.now.to_f
    if agora < @bola_pronta.to_f
      dizer(_INTL("Bola: {1}s", (@bola_pronta - agora).round(1))) rescue nil
      return
    end
    id = bola_no_saco
    unless id
      dizer(_INTL("Sem Poké Bolas na mochila."))
      return
    end
    # Primeiro os que ja estao grogues: e neles que a bola pega.
    b = tonto_a_mao || bicho_focado
    unless b
      dizer(_INTL("Não há ninguém para capturar."))
      return
    end
    @bola_pronta = agora + 2.0
    # ⚠️ QUEM ATIRA A BOLA E O TREINADOR, E NAO O POKEMON.
    #
    # Ele esta parado a ver a luta; e da mao dele que a bola sai, atravessa o
    # campo e bate no bicho. Sem isto a bola saia do proprio Pokemon, que e
    # quem esta a lutar — e nenhum treinador manda o Pikachu atirar a bola.
    ox = (@corpo_x || $game_player.x)
    oy = (@corpo_y || $game_player.y)
    lancar!(:x => ox, :y => oy, :dir => $game_player.direction,
            :alvo => b[:ev], :anim => 0, :infalivel => true,
            :move_id => id, :mv => nil, :nome => "Bola", :meu => true,
            :bola => id, :bicho => b, :alcance => BOLA_ALCANCE + 12.0, :curto => false,
            :vel => BOLA_VEL, :sp_pronto => sprite_da_bola(id))
    dizer(_INTL("Você lançou uma bola!"))
  rescue => e
    registar("falha a atirar bola: #{e.class}: #{e.message}")
  end

  # ⚠️ UM SHINY NAO ESPERA PELA MIRA.
  #
  # Perder um shiny porque a bola saiu tarde e o tipo de coisa que estraga uma
  # tarde inteira. Assim que um aparece, a bola vai — de imediato e a cada vez
  # que a mao volta a estar livre, ate ele ser apanhado, fugir, ou acabarem as
  # bolas. Nao se gasta a melhor bola: o `bola_no_saco` comeca sempre na mais
  # fraca.
  # O shiny de servico: o evento que esta a ser cacado a bola. Confere-se que
  # ainda existe e ainda esta perto, senao o alvo era um fantasma.
  def shiny_a_vista
    ev = @shiny_ev
    return nil unless ev
    if $game_map.nil? || $game_map.events[ev.id] != ev
      @shiny_ev = nil
      return nil
    end
    if distancia_casas(ev, $game_player) > (ADOPCAO_RAIO * 2)
      return nil
    end
    ev
  rescue
    nil
  end

  # ⚠️ UMA TABELA, E NAO O `ItemHandlers`.
  #
  # O caminho normal de uma pocao (`UseOnPokemon`) abre ecras, pergunta em quem
  # se usa e escreve no `pkmn.hp` — tres coisas que aqui nao servem: o jogo nao
  # pode parar, o alvo e sempre quem se controla, e a vida que conta e a
  # `@hp_meu` da arena (o `escrever_vida_na_equipa!` e que a leva ao Pokemon).
  #
  # Vao da mais fraca para a mais forte, e usa-se a PRIMEIRA que chegue para
  # encher — nao se gasta uma Max Potion para curar 20. O `nil` cura tudo.
  REMEDIOS = [
    [:POTION,      20],
    [:SUPERPOTION, 60],
    [:HYPERPOTION, 120],
    [:MAXPOTION,   nil],
    [:FULLRESTORE, nil]
  ].freeze

  REMEDIO_ESPERA = 1.5   # segundos entre curas

  def usar_remedio!
    return unless @meu
    agora = Time.now.to_f
    if agora < @remedio_pronto.to_f
      dizer(_INTL("Espere {1}s", (@remedio_pronto - agora).round(1))) rescue nil
      return
    end
    maximo = (@meu.totalhp.to_i rescue 1)
    if @hp_meu.to_i >= maximo
      dizer(_INTL("Já está com a vida cheia."))
      return
    end
    falta = maximo - @hp_meu.to_i
    escolhido = nil
    quanto = 0
    # ⚠️ ESCOLHIDA A MAO GANHA A ESCOLHA AUTOMATICA.
    #
    # Quem rodou o leque ate a Hyper quer a Hyper, mesmo que uma Potion chegue
    # para encher. A conta automatica so volta a mandar quando a escolhida
    # acabar — e ai o `indice_do_remedio` ja a esqueceu sozinho.
    escolhida = @remedio_escolhido
    if escolhida && (GameData::Item.exists?(escolhida) rescue false) &&
       ($bag.has?(escolhida) rescue false)
      escolhido = escolhida
      cura = (REMEDIOS.find { |(id, _c)| id == escolhida } || [])[1]
      quanto = cura ? cura : falta
    else
      REMEDIOS.each do |(id, cura)|
        next unless (GameData::Item.exists?(id) rescue false)
        next unless ($bag.has?(id) rescue false)
        escolhido = id
        quanto = cura ? cura : falta
        # A primeira que chegue para encher serve; se nenhuma chegar, fica a
        # ultima que houver, que e a mais forte da mochila.
        break if quanto >= falta
      end
    end
    unless escolhido
      dizer(_INTL("Sem poções na mochila."))
      return
    end
    unless ($bag.remove(escolhido) rescue false)
      dizer(_INTL("Sem poções na mochila."))
      return
    end
    @remedio_pronto = agora + REMEDIO_ESPERA
    curou = [quanto, falta].min
    @hp_meu = [@hp_meu.to_i + curou, maximo].min
    # Na automatica a minha vida nao esta em jogo — a que conta e a do ajudante,
    # e ela ja e escrita por quem trata dele.
    escrever_vida_na_equipa!
    tocar_no_character!($game_player, ANIM_CURA, 0, $game_player) if ANIM_CURA > 0
    (pbSEPlay("Pkmn healing") rescue nil)
    dizer(_INTL("+{1} de vida!", curou))
  rescue => e
    registar("falha a curar: #{e.class}: #{e.message}")
  end

  # A animacao de cura do motor. Zero = nenhuma, e nao rebenta nada se este
  # jogo nao a tiver.
  ANIM_CURA = 0

  # Quanto tempo se deixa ver o shiny antes de a bola sair.
  ESPERA_SHINY = 1.5

  def talvez_bola_automatica!
    # ⚠️ SEM POCHETE NAO HA BOLA SOZINHA.
    #
    # Sai logo a porta, antes de procurar shinies, de medir distancias ou de
    # mexer no relogio da espera: um portao que so decide no fim ainda paga o
    # trabalho todo a cada tique, e isto corre 60 vezes por segundo.
    return unless (AnilArenaChaves.pochete? rescue true)
    return unless @activa && !pvp?
    # A mesma regra, e sobretudo aqui: esta bola sai SOZINHA, e sem esta linha
    # a caverna apanhava shinies sem o jogador carregar em nada.
    return if caverna?
    return if @captura
    ev = shiny_a_vista
    return unless ev
    return if @sem_bolas
    return if Time.now.to_f < @bola_pronta.to_f
    pk = (ev.pokemon rescue nil)
    return unless pk
    # ⚠️ O MOMENTO QUE SE ESTA A CAÇAR NAO PODE DURAR UM FRAME.
    #
    # A bola saia no mesmo tique em que o shiny era detectado. Do lado de quem
    # joga isso e um clarao e uma mensagem — o bicho que se passou meia hora a
    # procurar nao chega a ser visto. A recompensa de uma caçada e VER aquilo
    # ali, e o codigo estava a cobrar o preco e a saltar o premio.
    #
    # Um segundo e meio: chega para o olho pousar no boneco e ler a cor, e e
    # curto de mais para dar tempo de ele fugir.
    unless @avisou_shiny == ev.id
      @avisou_shiny = ev.id
      @shiny_visto_em = Time.now.to_f
      dizer(_INTL("SHINY!"))
      (pbSEPlay("Anim/Shiny") rescue nil)
    end
    # ⚠️ E A ESPERA E POR AVISTAMENTO, NAO UM TEMPORIZADOR GLOBAL.
    #
    # Presa ao `@avisou_shiny`, ela reinicia sozinha quando aparece OUTRO shiny.
    # Um relogio global faria o segundo shiny herdar o tempo ja passado do
    # primeiro e a bola voltava a sair de imediato.
    return if Time.now.to_f < (@shiny_visto_em.to_f + ESPERA_SHINY)
    dizer(_INTL("Lançando bola!")) if @avisou_shiny == ev.id && !@disse_lancar
    @disse_lancar = true
    id = bola_no_saco
    unless id
      @sem_bolas = true
      dizer(_INTL("Sem Poké Bolas!"))
      return
    end
    @bola_pronta = Time.now.to_f + 2.0
    lancar!(:x => $game_player.x, :y => $game_player.y, :dir => $game_player.direction,
            :alvo => ev, :anim => 0, :infalivel => true,
            :move_id => id, :mv => nil, :nome => "Bola", :meu => true,
            :bola => id, :evento_shiny => ev, :alcance => BOLA_ALCANCE + 4.0,
            :curto => false, :vel => BOLA_VEL, :sp_pronto => sprite_da_bola(id))
  rescue
    nil
  end

  def resolver_bola!(p)
    # ⚠️ UM SHINY NAO E UM BICHO: e um evento do mapa que ninguem tocou.
    #
    # Ele nunca entrou na lista de adversarios (ver o adoptar_do_mato!), por
    # isso nao tem ficha nenhuma — a conta faz-se com o Pokemon do evento, com a
    # vida cheia. Para nao ser impossivel a vida cheia, um shiny vale o triplo
    # na conta da bola: e o preco de nao se poder enfraquecer.
    if p[:evento_shiny]
      resolver_bola_shiny!(p)
      return
    end
    # ⚠️ UM GROGUE TEM VIDA ZERO — e e exactamente nele que a bola pega.
    #
    # A guarda antiga exigia vida acima de zero e passou a recusar todas as
    # capturas depois de o bicho cair, que e agora o caso normal.
    apanhavel = proc { |x| x && (x[:hp].to_i > 0 || x[:tonto]) }
    b = p[:bicho]
    b = bicho_do_evento(p[:alvo]) unless apanhavel.call(b)
    unless p[:acertou] && apanhavel.call(b)
      dizer(_INTL("A bola não acertou."))
      return
    end
    id = p[:bola]
    ($bag.remove(id) rescue nil)

    pkmn = b[:pkmn]
    taxa = (GameData::Species.get(pkmn.species).catch_rate.to_i rescue 45)
    taxa = 45 if taxa <= 0
    fraccao = b[:hp].to_f / [b[:hp_max], 1].max
    # Vida cheia ~ 1/3 da conta; quase morto ~ o triplo disso.
    conta = ((3.0 - (2.0 * fraccao)) * taxa * multiplicador_da_bola(id)) / 3.0
    # Um Pokemon grogue no chao nao se debate como um de pe.
    conta *= 2.0 if b[:tonto]
    conta *= 2.0 if [:adormecido, :congelado].include?(b[:estado])
    conta *= 1.5 if [:paralisado, :envenenado, :queimado].include?(b[:estado])
    hipotese = [[conta / 255.0, 0.03].max, 0.98].min
    registar("bola #{id} em #{pkmn.speciesName}: hp=#{(fraccao * 100).round}% taxa=#{taxa} chance=#{(hipotese * 100).round}%")
    # O resultado sai agora, mas quem o mostra e a sequencia.
    iniciar_captura!(b, id, (rand < hipotese))
  rescue => e
    registar("falha na bola: #{e.class}: #{e.message}")
  end

  # A animacao de mapa que recolhe um Pokemon para a bola, tocada em cima de
  # quem levou com ela. E o mesmo caminho do motor que o relvado a mexer usa.
  def animar_prender!(ev)
    return unless ev
    (ev.animation_id = ANIM_PRENDER) rescue nil
    (pbSEPlay("Battle ball hit") rescue nil)
  rescue
    nil
  end

  #-----------------------------------------------------------------------------
  # A CAPTURA
  #
  # ⚠️ DECIDIR NUM FRAME NAO E CAPTURAR: E SO SABER O RESULTADO.
  #
  # A bola batia e o bicho evaporava — nem a animacao de prender chegava a
  # aparecer, porque eu apagava o evento no mesmo instante em que lhe punha a
  # animacao. O motor nunca teve um frame para a desenhar.
  #
  # A captura de uma serie Pokemon e uma SEQUENCIA, e e ela que cria a tensao:
  # o bicho entra na bola, a bola cai no chao, abana tres vezes, e so entao se
  # sabe. Isso nao cabe numa funcao que corre e devolve — precisa de estados e
  # de relogio, como tudo o resto nesta arena.
  #
  # O resultado JA ESTA decidido quando a sequencia comeca (foi sorteado no
  # impacto). Os tres abanos nao sao um sorteio a acontecer: sao a maneira de o
  # contar. E honesto e e o que a serie faz.
  #-----------------------------------------------------------------------------
  ANIM_SOLTAR    = 26     # "Pokemon Ball Out"
  ANIM_BRILHO    = 52     # "Shiny" — serve de clarao de captura
  CAPTURA_ABANOS = 3

  def iniciar_captura!(b, bola_id, sucesso)
    return unless b && b[:ev]
    @captura = { :b => b, :bola => bola_id, :sucesso => sucesso,
                 :fase => :bater, :ate => Time.now.to_f + BATER_TEMPO,
                 :abanos => 0, :padrao => nil, :feixe => nil,
                 :sp => sprite_da_bola(bola_id, true) }
    (pbSEPlay("Battle jump to ball") rescue nil)
    # Enquanto a bola decide, ele nao acorda nem foge.
    b[:tonto_ate] = Time.now.to_f + 9999.0
  rescue
    @captura = nil
  end

  # ⚠️ A ORDEM E O QUE FAZ ISTO PARECER UMA CAPTURA.
  #
  # Nao e "a bola chega e o bicho some". E: a bola BATE nele, salta um pouco
  # para o alto, e so entao o prende — o Pokemon brilha, vira fumo e e engolido
  # enquanto a bola desce. Ela pousa, abana tres vezes, e ai sim se sabe.
  #
  # Cada uma destas coisas e uma fase com o seu tempo. Sem as fases tudo
  # acontecia no mesmo frame e nada disto se via.
  BATER_TEMPO  = 0.22
  BATER_ALTURA = 26.0
  ENTRAR_TEMPO = 0.55

  # ⚠️ A BOLA QUE SE ABRE JA ESTA DESENHADA — E EU ESTAVA A USAR O ICONE.
  #
  # A folha `Follower_ComeInOut.png` (5x2 celulas de 192) e a que as animacoes
  # 26 e 29 usam, e nela estao os quadros todos: o p0 e a bola FECHADA, e os
  # p5, p6 e p7 sao a bola aberta com o feixe a puxar (e a sequencia que a
  # animacao "Pokemon Ball In" percorre). Usando esta folha em vez do icone do
  # item, a bola abre e fecha com o desenho do jogo, e nao com um truque meu.
  #
  # O feixe vermelho, o brilho e o funil sao aplicados ao SPRITE do Pokemon: a
  # cor, a opacidade e o zoom. E por isso que a coisa toda encaixa — o motor
  # desenha o boneco e eu escrevo por cima, no mesmo frame, todos os frames.
  FOLHA_BOLA     = "Graphics/Animations/Follower_ComeInOut"
  BOLA_FECHADA   = 0
  BOLA_ABERTA    = [7, 6, 5].freeze   # a ordem em que ela puxa
  ABRIR_TEMPO    = 0.18
  SUGAR_TEMPO    = 0.62
  FECHAR_TEMPO   = 0.22
  ENGOLIDO_OPACIDADE = 153            # 60% de 255: ele ja e luz, nao corpo
  ENGOLIDO_ZOOM      = 0.28

  def cartao_da_folha_bola(padrao)
    @cartoes_bola ||= {}
    return @cartoes_bola[padrao] if @cartoes_bola.key?(padrao)
    @cartoes_bola[padrao] = begin
      bmp = (AnimatedBitmap.new(FOLHA_BOLA).deanimate rescue nil)
      raise "sem folha" unless bmp
      @bmp_folha_bola = bmp
      cx = caixa_do_padrao(bmp, padrao.to_i)
      cx ? [bmp, cx] : nil
    rescue => e
      registar("folha da bola falhou: #{e.class}: #{e.message}")
      nil
    end
  end

  # ⚠️ TROCAR O BITMAP DE UM SPRITE A MEIO E COMO TROCAR DE SAPATOS A CORRER.
  #
  # Eu reaproveitava o mesmo sprite para a bola fechada e para os quadros do
  # feixe, e a cada troca tinha de reescrever o recorte, a ancora e o zoom. Bastou
  # um deles ficar do quadro anterior para sair o que o jogador viu: uma coisa
  # grande, escura e que nao era uma bola.
  #
  # Sao duas coisas diferentes; passam a ser dois sprites. A bola e sempre o
  # icone do item, que ja estava certo. O feixe e um sprite a parte, que aparece
  # por cima dela enquanto ela suga e desaparece quando fecha. Nenhum dos dois
  # muda de bitmap a meio da vida.
  FEIXE_PX_MAX = 42.0

  def sprite_do_feixe(padrao)
    cart = cartao_da_folha_bola(padrao)
    return nil unless cart
    bmp, cx = cart
    sp = Sprite.new(viewport_do_chao)
    sp.bitmap = bmp
    sp.src_rect.set(((padrao % 5) * CEL_ANIM) + cx[0], ((padrao / 5) * CEL_ANIM) + cx[1], cx[2], cx[3])
    sp.ox = cx[2] / 2
    sp.oy = cx[3] / 2
    lado = [cx[2], cx[3]].max.to_f
    lado = 32.0 if lado <= 0
    # ⚠️ NUNCA AUMENTAR. Uma celula pequena esticada fica borrada e enorme —
    # foi assim que a bola virou um borrao escuro do tamanho de uma casa.
    z = [FEIXE_PX_MAX / lado, 1.0].min
    sp.zoom_x = z
    sp.zoom_y = z
    sp.opacity = 255
    sp.blend_type = 1        # aditivo: e luz, nao um objecto
    sp
  rescue
    nil
  end


  def trocar_quadro_do_feixe!(c, padrao)
    return if c[:padrao] == padrao
    velho = c[:feixe]
    novo = sprite_do_feixe(padrao)
    c[:feixe] = novo
    c[:padrao] = padrao
    (velho.dispose rescue nil) if velho && !(velho.disposed? rescue true)
  rescue
    nil
  end

  def apagar_feixe!(c)
    return unless c && c[:feixe]
    (c[:feixe].dispose rescue nil) unless (c[:feixe].disposed? rescue true)
    c[:feixe] = nil
    c[:padrao] = nil
  rescue
    nil
  end

  # O Pokemon a virar luz: fica vermelho, perde corpo e afunila para dentro da
  # bola. `t` vai de 0 a 1.
  def pintar_engolido!(c, ev, t)
    sp = sprite_de(ev)
    unless sp
      # ⚠️ Se o sprite do bicho nao for encontrado, nada disto acontece — e sem
      # log eu voltaria a adivinhar porque e que ele nao ficou vermelho.
      unless @avisei_sem_sprite
        @avisei_sem_sprite = true
        registar("engolido: NAO encontrei o sprite do evento #{(ev.id rescue '?')}")
      end
      return
    end
    unless @avisei_engolido
      @avisei_engolido = true
      registar("engolido: a pintar o sprite do evento #{(ev.id rescue '?')}")
    end
    t = [[t, 0.0].max, 1.0].min
    forca = [t * 1.6, 1.0].min
    (sp.color.set(255, 45, 45, (255 * forca).to_i) rescue nil)
    # O `tone` e outra camada, e ninguem mais lhe toca: se alguma coisa estiver
    # a reescrever a `color` a cada frame, o vermelho aparece na mesma.
    (sp.tone.set((120 * forca).to_i, (-60 * forca).to_i, (-60 * forca).to_i, 0) rescue nil)
    (ev.opacity = (255 - ((255 - ENGOLIDO_OPACIDADE) * t)).to_i) rescue nil
    escala = 1.0 - ((1.0 - ENGOLIDO_ZOOM) * t)
    (sp.zoom_x = escala) rescue nil
    (sp.zoom_y = escala) rescue nil
    bola = c[:sp]
    if bola && !(bola.disposed? rescue true)
      (sp.x = (sp.x + ((bola.x - sp.x) * t)).round) rescue nil
      (sp.y = (sp.y + ((bola.y - sp.y) * t)).round) rescue nil
    end
  rescue
    nil
  end

  def limpar_engolido!(ev)
    sp = sprite_de(ev)
    return unless sp
    (sp.color.set(0, 0, 0, 0) rescue nil)
    (sp.tone.set(0, 0, 0, 0) rescue nil)
    (sp.zoom_x = 1.0) rescue nil
    (sp.zoom_y = 1.0) rescue nil
    (ev.opacity = 255) rescue nil
  rescue
    nil
  end

  SUGAR_TEMPO_LONGO = 0.95

  def correr_captura!
    return unless @captura
    c = @captura
    b = c[:b]
    ev = b ? b[:ev] : nil
    return encerrar_captura! unless ev
    agora = Time.now.to_f
    posicionar_bola_da_captura!(c, ev, agora)

    case c[:fase]
    when :bater
      return if agora < c[:ate]
      trocar_quadro_do_feixe!(c, BOLA_ABERTA[0])
      (pbSEPlay("Battle recall") rescue nil)
      c[:fase] = :abrir
      c[:ate] = agora + ABRIR_TEMPO
    when :abrir
      return if agora < c[:ate]
      c[:fase] = :sugar
      c[:ate] = agora + SUGAR_TEMPO_LONGO
    when :sugar
      t = 1.0 - [[(c[:ate] - agora) / SUGAR_TEMPO_LONGO, 0.0].max, 1.0].min
      quadro = BOLA_ABERTA[[(t * BOLA_ABERTA.length).to_i, BOLA_ABERTA.length - 1].min]
      trocar_quadro_do_feixe!(c, quadro)
      # ⚠️ ELE TEM DE ACABAR DE SER SUGADO ANTES DE A BOLA CAIR.
      #
      # O funil termina aos 80% da fase; o resto e a bola fechada, ainda no ar,
      # antes de descer. Sem essa pausa a bola comecava a cair com o Pokemon
      # ainda a meio de ser absorvido.
      pintar_engolido!(c, ev, [t / 0.8, 1.0].min)
      return if agora < c[:ate]
      (ev.opacity = 0) rescue nil
      apagar_feixe!(c)
      (pbSEPlay("Battle jump to ball") rescue nil)
      c[:fase] = :fechar
      c[:ate] = agora + FECHAR_TEMPO
    when :fechar
      return if agora < c[:ate]
      (pbSEPlay("Battle ball drop") rescue nil)
      c[:fase] = :abanar
      c[:ate] = agora + 0.55
    when :abanar
      return if agora < c[:ate]
      c[:abanos] += 1
      (pbSEPlay("Battle ball shake") rescue nil)
      if c[:abanos] >= CAPTURA_ABANOS
        c[:fase] = :decidir
        c[:ate] = agora + 0.4
      else
        c[:ate] = agora + 0.55
      end
    when :decidir
      return if agora < c[:ate]
      if c[:sucesso]
        (ev.animation_id = ANIM_BRILHO) rescue nil
        # ⚠️ APANHAR UM SHINY NAO PODE SOAR COMO APANHAR UM RATTATA.
        #
        # O `Pkmn get` e o mesmo de qualquer captura, e e curto — dois segundos
        # de "conseguiste" para uma coisa que acontece a cada dez minutos. Para
        # a coisa que acontece uma vez por sessao, soa a nada.
        #
        # O `Battle capture success` e o jingle que o jogo ja usa quando uma
        # captura E o acontecimento (a Mystery Gift, o fim de uma troca): mais
        # longo, e com a subida que o momento pede. Nao ha ficheiro novo a
        # acrescentar, e portanto nao ha nada que possa falhar no update — que
        # so entrega dois ficheiros.
        if (captura_de_shiny?(c) rescue false)
          (pbMEPlay("Battle capture success") rescue nil)
          anunciar_shiny_apanhado!(c)
        else
          (pbSEPlay("Pkmn get") rescue nil)
        end
        c[:fase] = :brilhar
        c[:ate] = agora + 0.75
      else
        limpar_engolido!(ev)
        (ev.animation_id = ANIM_SOLTAR) rescue nil
        (pbSEPlay("Battle recall") rescue nil)
        dizer(_INTL("{1} escapou da bola!", (b[:pkmn].speciesName rescue "")))
        b[:tonto_ate] = agora + TONTO_LIMITE
        encerrar_captura!
      end
    when :brilhar
      return if agora < c[:ate]
      ficha = c[:b]
      bola = c[:bola]
      encerrar_captura!
      apanhar!(ficha, bola)
    end
  rescue => e
    registar("falha na captura: #{e.class}: #{e.message}")
    encerrar_captura!
  end

  # ⚠️ A ALTURA NAO E UM NUMERO FIXO: E A DO BONECO.
  #
  # O `screen_y` de um personagem sao os PES dele. Somando sempre a mesma altura
  # a bola batia no pe de um Onix e por cima de um Diglett. O sprite sabe quanto
  # mede — largura e altura da celula, ja com o zoom aplicado — e e de la que
  # sai a cabeca. Dois tercos da altura e o ponto onde uma bola bate num bicho,
  # seja ele do tamanho que for.
  def altura_do_alvo(ev)
    sp = sprite_de(ev)
    return 24 unless sp
    alt = ((sp.src_rect.height rescue 32) * (sp.zoom_y rescue 1)).abs
    alt = 32 if alt < 8
    (alt * 0.66).round
  rescue
    24
  end

  def posicionar_bola_da_captura!(c, ev, agora)
    sp = c[:sp]
    # O feixe acompanha a bola, sempre por cima dela.
    if c[:feixe] && !(c[:feixe].disposed? rescue true) && sp && !(sp.disposed? rescue true)
      c[:feixe].x = sp.x
      c[:feixe].y = sp.y
      (c[:feixe].z = sp.z + 1) rescue nil
    end
    return unless sp && !(sp.disposed? rescue true)
    sp.x = (ev.screen_x rescue 0)
    chao = (ev.screen_y rescue 0) - 4
    cabeca = chao - altura_do_alvo(ev)
    base = (c[:fase] == :abanar || c[:fase] == :decidir || c[:fase] == :brilhar) ? chao : cabeca
    # ⚠️ POR CIMA DE QUEM ESTA A SER APANHADO, e nao por baixo: e a bola dele
    # que se ve, nao ele. Como o z segue a altura no ecra, quem estiver mais a
    # frente no mapa continua a tapa-la.
    (sp.z = (ev.screen_z rescue 0) + 1) rescue nil

    case c[:fase]
    when :bater
      # Bate na cabeca e salta um pouco mais para cima.
      t = 1.0 - [[(c[:ate] - agora) / BATER_TEMPO, 0.0].max, 1.0].min
      sp.y = (cabeca - (Math.sin(t * Math::PI * 0.5) * 14.0)).round
      sp.angle = t * 90.0
    when :abrir, :sugar
      # Fica no alto, aberta, a puxar — a altura da cabeca dele.
      sp.y = (cabeca - 14).round
      sp.angle = 0
    when :fechar
      # Desce da cabeca ate ao chao, e nao "um bocado": e a queda a serio.
      t = 1.0 - [[(c[:ate] - agora) / FECHAR_TEMPO, 0.0].max, 1.0].min
      sp.y = (cabeca + ((chao - cabeca) * t)).round
      sp.angle = t * 180.0
    when :abanar
      # ⚠️ RODAR NAO E ABANAR.
      #
      # O `angle` roda em volta da ancora, e a ancora estava no CENTRO do
      # sprite: o que se via era a bola a piruetar no ar. Uma bola pousada
      # deita-se para um lado e para o outro, e o pivo disso e o CHAO — o ponto
      # onde ela toca. Baixa-se a ancora para a base, inclina-se pouco, e
      # acompanha-se com um passo de lado, que e o que uma bola com bicho la
      # dentro faz.
      # ⚠️ O PIVO E O PONTO QUE TOCA O CHAO.
      #
      # Eu baixei a ancora mas continuei a por o `y` no meio: o resultado era a
      # bola a rodar em volta de um ponto no ar. Com a ancora na BASE, o `y` tem
      # de ser o chao — e ai a inclinacao acontece a volta de onde ela assenta,
      # que e o unico sitio onde uma bola pousada pode rodar.
      metade = ((sp.src_rect.height rescue 24) * (sp.zoom_y rescue 1) / 2.0).round
      sp.oy = (sp.src_rect.height rescue 24)
      inclinacao = Math.sin(agora * 11.0)
      sp.angle = inclinacao * 18.0
      sp.x = (ev.screen_x rescue 0) + (inclinacao * 4.0).round
      sp.y = base + metade
    else
      sp.y = base
      sp.angle = 0
    end
  rescue
    nil
  end

  # ⚠️ A PERGUNTA E SOBRE O BICHO, E NAO SOBRE COMO A BOLA FOI ATIRADA.
  #
  # Um shiny tambem se apanha a mao, com o Q, sem passar pela bola automatica.
  # Perguntar "veio da captura automatica?" deixaria de fora justamente a
  # captura de que o jogador mais se lembra — a que ele fez de proposito.
  def captura_de_shiny?(c)
    pk = ((c[:b] && c[:b][:pkmn]) rescue nil)
    return false unless pk
    return true if (pk.shiny? rescue false)
    return true if (pk.super_shiny? rescue false)
    false
  rescue
    false
  end

  #-----------------------------------------------------------------------------
  # O SHINY APANHADO DIZ-SE A TODA A GENTE
  #
  # ⚠️ NAO SE INVENTOU PACOTE NENHUM, E ESSA E A PARTE QUE INTERESSA.
  #
  # A tentacao era um tipo novo — "shiny_captured" — com o servidor a saber
  # trata-lo. So que o servidor e um deploy a parte: ate ele subir, o pacote
  # cairia no vazio e o anuncio nao chegava a ninguem. E o servidor ja distribui
  # o `global_chat_message` por todo o canal, e o cliente ja o sabe mostrar.
  #
  # Usar o que ja atravessa a rede inteira significa que isto funciona no
  # instante em que o Scripts.rxdata chegar, sem tocar no servidor.
  #
  # ⚠️ E anuncia-se a CAPTURA, nao o avistamento.
  #
  # O `070` ja faz um efeito local quando um shiny nasce no mapa — brilho e som,
  # so para quem esta la. Isso e outra coisa: ver um shiny e sorte, apanha-lo e
  # o acontecimento. Anunciar o avistamento a toda a gente so serviria para
  # mandar meio servidor a correr para o mesmo matagal.
  # ⚠️ O CANAL DO SHINY JA EXISTIA, E EU TINHA FEITO UM SEGUNDO.
  #
  # Na ronda passada mandei isto por `global_chat_message`, com a justificacao
  # de nao inventar um pacote novo para nao depender de um deploy do servidor.
  # A justificacao estava certa; a pesquisa e que ficou curta. Ha um pacote
  # PROPRIO, o `shiny_capturado`, que o servidor ja trata — e trata melhor do
  # que um chat alguma vez trataria:
  #
  #   - limita a um anuncio por jogador a cada 30 s;
  #   - CALA-SE quando o shiny e a captura de um evento lendario a decorrer,
  #     para o anuncio banal nao roubar o peso ao que conta;
  #   - limpa o nome da especie antes de o mostrar a toda a gente.
  #
  # Nada disso existia no meu caminho pelo chat. E o cliente ja tem o
  # `AnilAnuncioShiny.anunciar`, com o seu proprio intervalo — chama-se esse, e
  # nao o pacote a mao, senao ficavam dois guardas a discordar.
  #
  # ⚠️ E NAO E DUPLICADO: a arena guarda com `pbAddPokemonSilent`, e o gancho
  # do MOD 134 esta no `pbStorePokemon`, que so a batalha normal usa. Verificado
  # antes de ligar isto — era o unico risco a serio de o fazer por aqui.
  def anunciar_shiny_apanhado!(c)
    pk = ((c[:b] && c[:b][:pkmn]) rescue nil)
    return unless pk
    (AnilAnuncioShiny.anunciar(pk) rescue nil)
  rescue => e
    registar("falha a anunciar o shiny: #{e.class}: #{e.message}")
  end

  def encerrar_captura!
    apagar_feixe!(@captura) if @captura
    if @captura && @captura[:sp] && !(@captura[:sp].disposed? rescue true)
      (@captura[:sp].dispose rescue nil)
    end
    @captura = nil
  rescue
    @captura = nil
  end

  SHINY_BONUS_BOLA = 3.0

  def resolver_bola_shiny!(p)
    ev = p[:evento_shiny]
    pk = (ev.pokemon rescue nil)
    unless p[:acertou] && pk && $game_map && $game_map.events[ev.id] == ev
      # ⚠️ "NAO ACERTOU" ERA VERDADE E NAO SERVIA PARA NADA.
      #
      # Ha tres maneiras diferentes de isto falhar e a mensagem era a mesma nas
      # tres. Sao coisas completamente diferentes: uma e pontaria, outra e o
      # alvo ter desaparecido do mapa, outra e o evento ja nao ter Pokemon. O
      # log passa a separa-las — foi a unica maneira de descobrir que o alvo
      # estava a ser varrido a meio do voo.
      razao = if !p[:acertou] then "a bola nao chegou ao alvo"
              elsif !pk then "o evento ja nao tem Pokemon"
              elsif $game_map.nil? then "nao ha mapa"
              else "o alvo ja nao esta no mapa (foi varrido?)"
              end
      registar("bola shiny falhou: #{razao}")
      dizer(_INTL("A bola não acertou."))
      return
    end
    id = p[:bola]
    ($bag.remove(id) rescue nil)
    taxa = (GameData::Species.get(pk.species).catch_rate.to_i rescue 45)
    taxa = 45 if taxa <= 0
    conta = (taxa * multiplicador_da_bola(id) * SHINY_BONUS_BOLA) / 3.0
    hipotese = [[conta / 255.0, 0.05].max, 0.98].min
    registar("bola shiny #{id} em #{pk.speciesName}: chance=#{(hipotese * 100).round}%")
    # ⚠️ O shiny nao e um bicho da lista, por isso nao tem ficha para a
    # sequencia agarrar. Faz-se-lhe uma de emprestimo, so para a captura: e o
    # mesmo desenho, o mesmo tempo, os mesmos tres abanos.
    ficha = { :pkmn => pk, :ev => ev, :id => ev.id, :hp => 0, :hp_max => 1,
              :tonto => true, :tonto_ate => Time.now.to_f + 9999.0,
              :shiny_solto => true }
    iniciar_captura!(ficha, id, (rand < hipotese))
  rescue => e
    registar("falha na bola shiny: #{e.class}: #{e.message}")
  end

  def apanhar!(b, bola_id)
    if b[:shiny_solto]
      pk = b[:pkmn]
      (pk.poke_ball = bola_id.to_s rescue nil)
      (pk.obtain_method = 0 rescue nil)
      (pk.obtain_map = ($game_map ? $game_map.map_id : 0) rescue nil)
      apagar_evento_bicho!(b[:id])
      @shiny_ev = nil
      @avisou_shiny = nil
      @disse_lancar = false
      (pbAddPokemonSilent(pk) rescue nil)
      dizer(_INTL("SHINY {1} capturado!", pk.speciesName))
      return
    end
    (b[:balao].bitmap.dispose rescue nil) if b[:balao]
    (b[:balao].dispose rescue nil) if b[:balao]
    b[:balao] = nil
    sp = sprite_de(b[:ev])
    (sp.angle = 0) rescue nil if sp
    pkmn = b[:pkmn]
    (pkmn.poke_ball = bola_id.to_s rescue nil)
    (pkmn.heal rescue nil)
    (pkmn.obtain_method = 0 rescue nil)
    (pkmn.obtain_map = ($game_map ? $game_map.map_id : 0) rescue nil)
    apagar_evento_bicho!(b[:id])
    b[:ev] = nil
    b[:hp] = 0
    esquecer_vivos!
    bichos.delete(b)
    esquecer_vivos!
    dizer(_INTL("{1} foi capturado!", pkmn.speciesName))
    # ⚠️ O `pbAddPokemon` abre janelas e o mapa esta a correr por baixo.
    #
    # Ele pergunta o apelido e mostra a Pokedex; com a arena viva por tras, os
    # controlos ficavam nos dois sitios ao mesmo tempo. Guarda-se para quando a
    # caca acabar, ou faz-se em silencio se ainda houver bichos no mapa.
    #
    # A batalha direta nao para para nada: guarda-se em silencio e segue-se.
    if @directa
      (pbAddPokemonSilent(pkmn) rescue nil)
      dizer(_INTL("{1} foi para a sua equipe!", pkmn.speciesName))
      actualizar_foco!
      return
    end
    if bichos_vivos.empty?
      pbMessage(_INTL("\se[Pkmn get]{1} foi capturado!", pkmn.speciesName)) rescue nil
      (pbAddPokemon(pkmn) rescue pbAddPokemonSilent(pkmn)) rescue nil
      @caca = false
      sair!
      pbMessage(_INTL("Área limpa!")) rescue nil
    else
      (pbAddPokemonSilent(pkmn) rescue nil)
      actualizar_foco!
    end
    fechar_se_acabou!
  rescue => e
    registar("falha a apanhar: #{e.class}: #{e.message}")
  end

  #-----------------------------------------------------------------------------
  # OS GOLPES QUE SOBEM ATRIBUTOS
  #
  # ⚠️ 58 GOLPES NAO FAZIAM ABSOLUTAMENTE NADA.
  #
  # Swords Dance, Agility, Iron Defense e companhia caiam no caminho normal, nao
  # tinham forca, nao tinham alvo — e o resultado era um botao que gastava a
  # recarga e mostrava "errou". Numa batalha por turnos um degrau de ataque e um
  # numero na ficha; aqui e tempo: quinze segundos a bater mais forte.
  #
  # O nome da funcao ja diz tudo o que e preciso — RaiseUserAttack1,
  # RaiseUserSpeed2, RaiseUserAtkSpAtk1. Le-se o que sobe e quanto, e nao ha
  # lista de golpes nenhuma para manter.
  #
  # ⚠️ E LE-SE PELA ORDEM CERTA: "SpAtk" contem "Atk" e "SpDef" contem "Def".
  # Procurar "Atk" primeiro punha Special Attack a subir o ataque fisico.
  BUFF_DURACAO = 15.0
  BUFF_ESCADA  = { 1 => 1.5, 2 => 2.0, 3 => 2.5 }.freeze

  def buff?(mv)
    return false unless mv && mv.id
    fc = (GameData::Move.get(mv.id).function_code.to_s rescue "")
    fc.start_with?("RaiseUser")
  rescue
    false
  end

  def buffs_do_golpe(mv)
    fc = (GameData::Move.get(mv.id).function_code.to_s rescue "")
    return {} unless fc.start_with?("RaiseUser")
    degraus = (fc[/(\d)/, 1] || "1").to_i
    degraus = 1 if degraus < 1
    mult = BUFF_ESCADA[[degraus, 3].min] || 1.5
    resto = fc.dup
    fora = {}
    if resto.include?("SpAtk") || resto.include?("SpecialAttack")
      fora[:spatk] = mult
      resto = resto.gsub("SpAtk", "").gsub("SpecialAttack", "")
    end
    if resto.include?("SpDef") || resto.include?("SpecialDefense")
      fora[:spdef] = mult
      resto = resto.gsub("SpDef", "").gsub("SpecialDefense", "")
    end
    fora[:atk] = mult if resto.include?("Atk") || resto.include?("Attack")
    fora[:def] = mult if resto.include?("Def") || resto.include?("Defense")
    fora[:spd] = mult if resto.include?("Speed") || resto.include?("Spd")
    fora
  rescue
    {}
  end

  def buff_de(pkmn, chave)
    tab = (@buffs ||= {})[pkmn]
    return 1.0 unless tab
    v = tab[chave]
    return 1.0 unless v
    return 1.0 if Time.now.to_f >= v[1].to_f
    v[0].to_f
  rescue
    1.0
  end

  def tem_buff?(pkmn)
    tab = (@buffs ||= {})[pkmn]
    return false unless tab
    agora = Time.now.to_f
    tab.any? { |_, v| v[1].to_f > agora }
  rescue
    false
  end

  def aplicar_buff!(pkmn, mv)
    lista = buffs_do_golpe(mv)
    return false if lista.empty?
    ate = Time.now.to_f + BUFF_DURACAO
    tab = ((@buffs ||= {})[pkmn] ||= {})
    lista.each { |chave, mult| tab[chave] = [mult, ate] }
    true
  rescue
    false
  end

  def buffs_activos(pkmn)
    tab = (@buffs ||= {})[pkmn]
    return [] unless tab
    agora = Time.now.to_f
    nomes = { :atk => "ATQ", :def => "DEF", :spatk => "ATE", :spdef => "DFE", :spd => "VEL" }
    tab.select { |_, v| v[1].to_f > agora }.keys.map { |k| nomes[k] }.compact
  rescue
    []
  end

  #-----------------------------------------------------------------------------
  # O AJUDANTE
  #
  # ⚠️ E UM BICHO — SO QUE DO MEU LADO.
  #
  # Ele tem exactamente a mesma ficha de um selvagem: vida, recargas por golpe,
  # folego, estado. A unica diferenca esta em duas perguntas — quem persegue e
  # quem leva. Reaproveitar a ficha em vez de inventar uma segunda quer dizer
  # que tudo o que ja funciona (os projecteis, as areas, os estados, o desmaio)
  # funciona para ele no dia em que nasce, e nao ha uma segunda copia das mesmas
  # regras para manter em sincronia.
  #
  # Ele nao e um seguidor do jogo: o seguidor e decoracao e nao sabe lutar. Este
  # e um evento nosso, com IA nossa.
  #-----------------------------------------------------------------------------
  ALIADO_SEGUE     = 2.5    # casas: a que distancia me acompanha
  ALIADO_ENGAJA    = 6.5    # casas: a partir daqui vai atras do inimigo
  ALIADO_PARAGEM   = 1.2    # casas: onde para, ao pe do alvo
  ALIADO_INTERVALO = 2.0    # segundos entre golpes dele

  def aliado_vivo?
    @aliado && @aliado[:hp].to_i > 0 && @aliado[:ev]
  rescue
    false
  end

  def chamar_aliado!(pkmn)
    return false unless pkmn && $game_map && $game_player
    dispensar_aliado!
    x, y = casa_livre_perto($game_player.x, $game_player.y, 2)
    return false unless x

    rpg = RPG::Event.new(x, y)
    rpg.id   = ID_ALIADO
    rpg.name = "ArenaAliado"
    pag = rpg.pages[0]
    pag.graphic.character_name = caminho_do_sprite(pkmn)
    pag.graphic.character_hue  = (pkmn.super_shiny_hue.to_i rescue 0)
    pag.trigger    = -1
    # ⚠️ O `step_anime` BRIGA COM O `parar_evento!`, E O QUE SE VE E UM TREMOR.
    #
    # Com `step_anime = true`, o `Game_Character#update` do motor avanca o
    # `@pattern` a CADA frame, ande o boneco ou nao. O `parar_evento!` repoe o
    # padrao de descanso. Os dois correm no mesmo frame, um a seguir ao outro,
    # para sempre: o motor adianta, nos repomos, o motor adianta. O sprite
    # salta entre dois desenhos sessenta vezes por segundo — e isso le-se como
    # um boneco a tremer, nao como um boneco parado.
    #
    # Nao e preciso: o `animar_evento!` ja move as pernas a mao, e so e chamado
    # quando o boneco anda mesmo. Desligar o `step_anime` tira o motor da
    # equacao e deixa uma so mao a mandar no padrao.
    pag.step_anime = false    # o `animar_evento!` e que move as pernas
    pag.move_type  = 0
    pag.through    = true     # nao se tropeca no proprio ajudante
    pag.list = [RPG::EventCommand.new(0, 0, [])]

    ev = Game_Event.new($game_map.map_id, rpg, $game_map)
    ev.through = true
    pousar_evento!(ID_ALIADO, ev, rpg)
    ev.refresh
    (AnilLanRework::ReleasedRoaming.sync_sprite(ev) rescue nil) if $scene.is_a?(Scene_Map)

    @aliado = {
      :pkmn => pkmn, :hp => [(pkmn.hp.to_i rescue pkmn.totalhp), 1].max,
      :hp_max => pkmn.totalhp, :id => ID_ALIADO, :ev => ev,
      :estado => nil, :estado_ate => 0.0, :estado_tique => 0.0,
      :prontos => [0.0, 0.0, 0.0, 0.0], :proximo => Time.now.to_f + 1.0
    }
    dizer(_INTL("{1} entrou para ajudar!", pkmn.name))
    true
  rescue => e
    log("falha a chamar o ajudante: #{e.class}: #{e.message}")
    false
  end

  # ⚠️ O ALIADO ERA O UNICO EVENTO MEU SEM REDE DE SEGURANCA.
  #
  # O treinador tem o `garantir_corpo!`: de segundo a segundo pergunta se o mapa
  # ainda o tem e, se nao tiver, repoe-o. O aliado nao tinha nada disso — e ele
  # e um evento injectado exactamente como o treinador, sujeito as mesmas
  # varreduras (o VOE, a sincronizacao de spawns, um refresh do mapa).
  #
  # E ha uma segunda maneira de o perder, mais traicoeira do que o desaparecer:
  # um refresh do mapa reconstroi os `Game_Event` a partir dos dados brutos.
  # Nasce um objecto NOVO no id 8103, e o meu `@aliado[:ev]` continua a apontar
  # para o velho. Ninguem apagou nada, mas eu passo a mover um boneco que ja nao
  # esta no mapa: o que se ve e um aliado plantado no sitio, que nao anda nem
  # ataca — ou nada, se o novo tambem se perder.
  #
  # Por isso a pergunta nao e "existe?", e "e ESTE?".
  # ⚠️ UMA MUDANCA DE MAPA LEVA O BONECO DO AJUDANTE, MAS NAO A FICHA DELE.
  #
  # O evento morre com o mapa velho; o `@aliado` continua a apontar para um
  # objecto que ja nao esta em `$game_map.events`. O `garantir_aliado!` procura
  # o evento pelo ID e encontra... nada, ou pior, um evento novo do mapa novo
  # com o mesmo numero. Ele deixava de seguir porque, do ponto de vista do
  # codigo, ele ja nao esta ali.
  #
  # Isto e uma chamada a mais e nao um sistema novo: perde-se a referencia, e o
  # `garantir_aliado!` faz o que ja sabia fazer — replantar o boneco ao pe de
  # nos.
  def esquecer_boneco_do_aliado!
    return unless @aliado
    @aliado[:ev] = nil
    @parceiro_ev = nil
    @parceiro_visto = 0
    # Zerar o relogio para ele nao esperar um segundo inteiro a olhar para o
    # nada antes de se replantar.
    @aliado_visto = 0
    true
  rescue
    nil
  end

  # ⚠️ A TRAVA CONTRA O AJUDANTE SE PERDER, SEJA QUAL FOR A CAUSA.
  #
  # Ja se corrigiram duas derivas (o empurrao que vinha de mim, e o recuo sem
  # limite) e ele voltou a sumir. Portanto ha, ou houve, uma terceira — e a
  # hipotese do utilizador e a mais provavel: ele saiu do mapa.
  #
  # Em vez de continuar a caçar causas uma a uma, poe-se o travao no fim: seja
  # o que for que o leve para onde nao devia, ele volta. Tres casos, e todos
  # dao o mesmo sintoma (um Pokemon que nao esta em lado nenhum):
  #
  #   fora do mapa  o `casa_livre_para_evento?` deixa passar um movimento
  #                 dentro da mesma casa sem conferir os limites, e a conta de
  #                 recuo escreve o `@real_x` a mao.
  #
  #   coordenada    basta uma divisao por zero algures para o `@real_x` ficar
  #   invalida      NaN. NaN falha TODAS as comparacoes, portanto nenhuma
  #                 logica de distancia o traz de volta — ele fica invisivel e
  #                 nenhum teste repara. E o pior dos tres.
  #
  #   longe de mais uma deriva lenta que ninguem trava.
  #
  # O teste corre a cada frame e custa tres comparacoes quando esta tudo bem.
  TRELA_DURA = 14.0    # casas: alem disto, volta para o pe de mim

  def numero_bom?(v)
    return false unless v.is_a?(Numeric)
    return false if v.respond_to?(:nan?) && v.nan?
    return false if v.respond_to?(:infinite?) && v.infinite?
    true
  rescue
    false
  end

  def prender_aliado!
    return unless @activa && aliado_vivo? && $game_map && $game_player
    ev = @aliado[:ev]
    return unless ev
    rx = (ev.instance_variable_get(:@real_x) rescue nil)
    ry = (ev.instance_variable_get(:@real_y) rescue nil)
    mau = !numero_bom?(rx) || !numero_bom?(ry)
    unless mau
      tx = (rx / Game_Map::REAL_RES_X.to_f).round
      ty = (ry / Game_Map::REAL_RES_Y.to_f).round
      mau = true unless ($game_map.valid?(tx, ty) rescue false)
      unless mau
        d = distancia_casas(ev, $game_player)
        mau = true if !numero_bom?(d) || d > TRELA_DURA
      end
    end
    return unless mau
    x, y = casa_livre_perto($game_player.x, $game_player.y, 3, 1)
    x, y = [$game_player.x, $game_player.y] unless x
    (ev.moveto(x, y) rescue nil)
    # O `moveto` arruma o `@real_x` a partir do `@x`, portanto isto tambem
    # limpa um NaN — que e a razao de ser `moveto` e nao uma escrita a mao.
    (ev.instance_variable_set(:@move_timer, nil) rescue nil)
    registar("o ajudante saiu do mapa (ou ficou sem coordenadas); reposto")
  rescue
    nil
  end

  def garantir_aliado!
    return unless @activa && @aliado && $game_map
    return if @aliado[:hp].to_i <= 0
    agora = (Graphics.frame_count rescue 0)
    return if (agora - @aliado_visto.to_i) < 60
    @aliado_visto = agora
    actual = $game_map.events[ID_ALIADO]
    return if actual && actual.equal?(@aliado[:ev])
    if actual
      # O mapa refez o evento: fico com o dele, na posicao onde o meu estava.
      rx = (@aliado[:ev].instance_variable_get(:@real_x) rescue nil)
      ry = (@aliado[:ev].instance_variable_get(:@real_y) rescue nil)
      if rx && ry
        actual.instance_variable_set(:@real_x, rx)
        actual.instance_variable_set(:@real_y, ry)
        actual.instance_variable_set(:@x, (rx / Game_Map::REAL_RES_X.to_f).round)
        actual.instance_variable_set(:@y, (ry / Game_Map::REAL_RES_Y.to_f).round)
      end
      actual.through = true
      @aliado[:ev] = actual
      registar("o ajudante tinha sido refeito pelo mapa; reatado")
      return
    end
    repor_aliado!
  rescue
    nil
  end

  # O mesmo desenho do `repor_corpo!`: replanta-se o evento ao pe do jogador e
  # ata-se a ficha que ja existe, sem lhe tocar na vida nem nas recargas.
  #-----------------------------------------------------------------------------
  # O AJUDANTE DO OUTRO LADO
  #
  # ⚠️ O AJUDANTE ERA COMPLETAMENTE LOCAL, E NINGUEM DAVA POR ISSO.
  #
  # Ele e um `Game_Event` no id 8103, criado, movido e morto na maquina de quem
  # o chamou. Nao havia pacote nenhum sobre ele — nem de nascimento, nem de
  # posicao. Num 2v2 isso quer dizer que cada jogador via tres bonecos num
  # combate de quatro, e o que faltava era sempre o mesmo: o parceiro do outro.
  #
  # A solucao segue a regra que a arena ja usa em todo o lado: o dono manda o
  # que sabe, e quem ve limita-se a desenhar. O boneco de ca e uma SOMBRA — nao
  # decide nada, nao ataca, nao leva dano. O dano dele continua a ser decidido
  # na maquina do dono, como o de toda a gente.
  #
  # Manda-se a 10 vezes por segundo. E pouco para um jogo de precisao e muito
  # para o que isto e: um boneco a andar. Entre pacotes ele fica parado, e a
  # 100 ms ninguem repara.
  # ⚠️ O QUE FAZ 15 POR SEGUNDO CHEGAR NAO E O RITMO. E A INTERPOLACAO.
  #
  # Eu escrevia a posicao recebida directamente no boneco. Assim, cada pacote e
  # um salto: ele fica parado 100 ms e depois aparece 3 casas a frente. Subir o
  # ritmo disfarca o salto mas nao o tira, e paga-se em rede a cada aumento.
  #
  # Os jogos que correm bem a 15 avisos por segundo nao mandam mais — eles
  # DESENHAM O QUE FALTA. Guarda-se para onde ele vai e desliza-se para la ao
  # longo dos frames seguintes. O resultado a 15 Hz com deslize e melhor do que
  # a 30 Hz sem ele, e custa metade da rede.
  #
  # O deslize e sempre um bocadinho atrasado em relacao a verdade — e o preco, e
  # e o preco certo: uma sombra atrasada 60 ms le-se como um boneco a andar, uma
  # sombra pontual aos saltos le-se como um bug.
  PARCEIRO_CADENCIA = 4      # frames entre dois avisos (60/4 = 15 por segundo)
  PARCEIRO_ESQUECE  = 180    # frames sem noticias ate o apagar (3 segundos)
  PARCEIRO_DESLIZE  = 0.25   # quanto da distancia que falta se anda por frame

  # ⚠️ NA CAVERNA O AJUDANTE TAMBEM SE ANUNCIA — SO QUE A TODA A GENTE.
  #
  # Isto so corria em duelo, com destinatario certo. Na caverna nao ha
  # destinatario: ha quem la estiver. Sem isto via-se o outro jogador e nao se
  # via o Pokemon dele — dois bonecos a lutar contra um.
  #
  # ⚠️ E SO HA UMA SOMBRA, PORQUE SO HA UM `ID_PARCEIRO`.
  #
  # Com dois jogadores na caverna chega e esta certo. Com tres, ve-se o
  # ajudante de quem falou por ultimo. Fica dito: alargar isto e dar um id por
  # jogador, e nao ha nada aqui que o impeca.
  def anunciar_parceiro!
    return unless pvp? || caverna?
    agora = (Graphics.frame_count rescue 0)
    # ⚠️ NUM DUELO ISTO E UMA CARTA; NA CAVERNA E UM ALTIFALANTE.
    #
    # Em duelo o pacote vai a UMA pessoa. Na caverna vai a toda a gente que
    # esteja no mapa, e 15 por segundo de cada jogador soma depressa. Metade
    # chega: quem ve o ajudante do outro nao precisa de o ver ao frame.
    cadencia = caverna? ? (PARCEIRO_CADENCIA * 2) : PARCEIRO_CADENCIA
    return if (agora - @parceiro_avisado.to_i) < cadencia
    @parceiro_avisado = agora

    unless aliado_vivo?
      # Uma vez chega, mas manda-se enquanto ele nao estiver ca: um pacote
      # perdido deixava a sombra no mapa do outro para sempre.
      if caverna?
        anunciar_na_caverna!("parceiro" => true, "fora" => true,
                             "x" => $game_player.x, "y" => $game_player.y)
      else
        enviar!("arena_parceiro", "fora" => true)
      end
      return
    end
    ev = @aliado[:ev]
    char = caminho_do_sprite(@aliado[:pkmn]).to_s
    hue  = (@aliado[:pkmn].super_shiny_hue.to_i rescue 0)
    dados = {
      "fora"   => false,
      "char"   => char,
      "hue"    => hue,
      "x"      => ev.x,
      "y"      => ev.y,
      "rx"     => (ev.instance_variable_get(:@real_x) rescue 0),
      "ry"     => (ev.instance_variable_get(:@real_y) rescue 0),
      "dir"    => (ev.direction rescue 2),
      "map"    => ($game_map.map_id rescue 0) }
    if caverna?
      # ⚠️ O QUE NAO MUDA NAO SE REPETE SETE VEZES POR SEGUNDO.
      #
      # O nome do boneco e a cor sao os mesmos durante toda a sessao — o Pokemon
      # ajudante escolhe-se a porta e nao se troca la dentro. Mandavam-se na
      # mesma, sete vezes por segundo, e sao os dois campos mais compridos do
      # pacote.
      #
      # Agora so viajam quando MUDAM (ou seja: uma vez, a primeira). E o `x`/`y`
      # saem de vez — sao o `rx`/`ry` divididos por 128, e quem recebe ja faz
      # essa conta. O `map` tambem: o `map_id` do envelope diz o mesmo.
      if @parceiro_char != char || @parceiro_hue != hue
        @parceiro_char = char
        @parceiro_hue  = hue
      else
        dados.delete("char")
        dados.delete("hue")
      end
      dados.delete("x")
      dados.delete("y")
      dados.delete("map")
      # ⚠️ O ESCUDO E DO DONO E SO ELE SABIA DELE.
      #
      # O `correr_escudo!` desenha a bolha em cima do `$game_player` — no MEU
      # ecra. Do lado do outro nunca houve nada: ele via os golpes dele a passar
      # por mim sem tirar vida e sem uma razao visivel, que e a pior maneira de
      # um escudo funcionar.
      #
      # Vai a boleia do aviso do ajudante, que ja sai 7,5 vezes por segundo:
      # um campo de um caractere quando esta de pe, ausente quando nao esta. O
      # escudo dura 0,2 s de cada vez que se carrega, portanto sete avisos por
      # segundo apanham-no com folga.
      dados["esc"] = 1 if (escudo_de_pe? rescue false)
      dados["esp"] = 1 if (espelho_de_pe? rescue false)
      anunciar_na_caverna!(dados.merge("parceiro" => true))
    else
      enviar!("arena_parceiro", dados)
    end
  rescue => e
    registar("falha a anunciar o ajudante: #{e.class}: #{e.message}")
  end

  def receber_parceiro!(pacote)
    da_caverna = (pacote["caverna"] ? true : false)
    return unless @activa && (da_caverna ? caverna? : pvp?)
    anotar_escudo_alheio!(pacote)
    return unless $game_map && $scene.is_a?(Scene_Map)
    if pacote["fora"]
      apagar_parceiro!
      return
    end
    # O pacote da caverna nao traz `map`: o mapa dele e o do envelope, e um
    # pacote de outro mapa nem sequer chega aqui (o servidor entrega por mapa).
    mapa_dito = pacote["map"] || pacote["map_id"]
    return if mapa_dito && mapa_dito.to_i != ($game_map.map_id.to_i rescue -1)
    @parceiro_visto = (Graphics.frame_count rescue 0)

    ev = $game_map.events[ID_PARCEIRO]
    ev = nil unless ev && ev.equal?(@parceiro_ev)
    ev = criar_parceiro!(pacote) unless ev
    return unless ev

    # A posicao vem em sub-pixeis, como a de toda a gente: escrever so a casa
    # dava um boneco aos saltos de 32 em 32.
    #
    # E nao se escreve JA: guarda-se para onde ele vai, e o `mover_parceiro!`
    # leva-o la ao longo dos frames seguintes.
    @parceiro_destino = [pacote["rx"].to_i, pacote["ry"].to_i]
    (ev.instance_variable_set(:@direction, pacote["dir"].to_i)) rescue nil

    # Se ele esta a mais de duas casas do sitio onde deve estar, nao vale a pena
    # deslizar: foi um teletransporte, uma reentrada, ou a ligacao esteve fora.
    # Deslizar isso desenhava-o a atravessar meio mapa a passo.
    rx = (ev.instance_variable_get(:@real_x) rescue 0).to_i
    ry = (ev.instance_variable_get(:@real_y) rescue 0).to_i
    salto = (rx - @parceiro_destino[0]).abs + (ry - @parceiro_destino[1]).abs
    if salto > (2 * Game_Map::REAL_RES_X)
      ev.instance_variable_set(:@real_x, @parceiro_destino[0])
      ev.instance_variable_set(:@real_y, @parceiro_destino[1])
      ev.instance_variable_set(:@x, casa_do_pacote(pacote, :x))
      ev.instance_variable_set(:@y, casa_do_pacote(pacote, :y))
      (ev.calculate_bush_depth rescue nil)
    end
  rescue => e
    registar("falha a receber o ajudante do outro: #{e.class}: #{e.message}")
  end

  # ⚠️ A CASA DEDUZ-SE DAS COORDENADAS REAIS, E NAO VEM NO PACOTE.
  #
  # O `x`/`y` de um evento e o `real_x`/`real_y` a dividir por 128, arredondado
  # — a mesma conta que o motor faz. Mandar os dois era mandar a mesma coisa
  # duas vezes, e sao dois campos em sete que saem sete vezes por segundo.
  #
  # Aceita-se o `x` se ele vier (o pacote do DUELO ainda o manda, e clientes
  # mais antigos tambem); so se calcula quando falta.
  def casa_do_pacote(pacote, eixo)
    dado = pacote[eixo.to_s]
    return dado.to_i if dado
    real = (eixo == :x) ? pacote["rx"] : pacote["ry"]
    res  = (eixo == :x) ? Game_Map::REAL_RES_X : Game_Map::REAL_RES_Y
    (real.to_f / res).round
  rescue
    0
  end

  def criar_parceiro!(pacote)
    rpg = RPG::Event.new(casa_do_pacote(pacote, :x), casa_do_pacote(pacote, :y))
    rpg.id   = ID_PARCEIRO
    rpg.name = "ArenaParceiro"
    pag = rpg.pages[0]
    pag.graphic.character_name = pacote["char"].to_s
    pag.graphic.character_hue  = pacote["hue"].to_i
    pag.trigger    = -1
    # ⚠️ O `step_anime` BRIGA COM O `parar_evento!`, E O QUE SE VE E UM TREMOR.
    #
    # Com `step_anime = true`, o `Game_Character#update` do motor avanca o
    # `@pattern` a CADA frame, ande o boneco ou nao. O `parar_evento!` repoe o
    # padrao de descanso. Os dois correm no mesmo frame, um a seguir ao outro,
    # para sempre: o motor adianta, nos repomos, o motor adianta. O sprite
    # salta entre dois desenhos sessenta vezes por segundo — e isso le-se como
    # um boneco a tremer, nao como um boneco parado.
    #
    # Nao e preciso: o `animar_evento!` ja move as pernas a mao, e so e chamado
    # quando o boneco anda mesmo. Desligar o `step_anime` tira o motor da
    # equacao e deixa uma so mao a mandar no padrao.
    pag.step_anime = false    # o `animar_evento!` e que move as pernas
    pag.move_type  = 0
    pag.through    = true      # e uma sombra: nao se tropeca nela
    pag.list = [RPG::EventCommand.new(0, 0, [])]
    ev = Game_Event.new($game_map.map_id, rpg, $game_map)
    ev.through = true
    pousar_evento!(ID_PARCEIRO, ev, rpg)
    ev.refresh
    (AnilLanRework::ReleasedRoaming.sync_sprite(ev) rescue nil)
    @parceiro_ev = ev
    registar("o ajudante do adversario apareceu (#{pacote['char']})")
    ev
  rescue => e
    registar("falha a criar o ajudante do outro: #{e.class}: #{e.message}")
    nil
  end

  # Anda-se um quarto do que falta por frame. Isso apanha 95% da distancia em
  # onze frames — menos de dois avisos — portanto ele nunca fica para tras, e
  # o movimento sai suave em vez de aos degraus.
  def mover_parceiro!
    ev = @parceiro_ev
    return unless ev && @parceiro_destino
    rx = (ev.instance_variable_get(:@real_x) rescue 0).to_f
    ry = (ev.instance_variable_get(:@real_y) rescue 0).to_f
    dx = @parceiro_destino[0] - rx
    dy = @parceiro_destino[1] - ry
    if dx.abs < 1.0 && dy.abs < 1.0
      return if @parceiro_parado
      @parceiro_parado = true
      parar_evento!(ev)
      return
    end
    @parceiro_parado = false
    nx = rx + (dx * PARCEIRO_DESLIZE)
    ny = ry + (dy * PARCEIRO_DESLIZE)
    ev.instance_variable_set(:@real_x, nx.round)
    ev.instance_variable_set(:@real_y, ny.round)
    ev.instance_variable_set(:@x, (nx / Game_Map::REAL_RES_X.to_f).round)
    ev.instance_variable_set(:@y, (ny / Game_Map::REAL_RES_Y.to_f).round)
    (ev.calculate_bush_depth rescue nil)
    animar_evento!(ev)
  rescue
    nil
  end

  def apagar_parceiro!
    apagar_evento_bicho!(ID_PARCEIRO) if $game_map && $game_map.events[ID_PARCEIRO]
    @parceiro_ev = nil
    @parceiro_visto = nil
    @parceiro_destino = nil
    @parceiro_parado = nil
  rescue
    nil
  end

  # ⚠️ UMA SOMBRA SEM DONO FICA NO MAPA PARA SEMPRE.
  #
  # Se o outro fechar o jogo, perder a ligacao, ou se o pacote do "fora" se
  # perder, ninguem me diz para a apagar. Por isso ela tem prazo: tres segundos
  # sem noticias e desaparece.
  def esquecer_parceiro!
    return unless @parceiro_ev
    agora = (Graphics.frame_count rescue 0)
    return if (agora - @parceiro_visto.to_i) < PARCEIRO_ESQUECE
    registar("o ajudante do adversario deixou de dar noticias; apagado")
    apagar_parceiro!
  rescue
    nil
  end

  def repor_aliado!
    return unless @aliado && $game_map && $game_player
    x, y = casa_livre_perto($game_player.x, $game_player.y, 2)
    return unless x
    rpg = RPG::Event.new(x, y)
    rpg.id   = ID_ALIADO
    rpg.name = "ArenaAliado"
    pag = rpg.pages[0]
    pag.graphic.character_name = caminho_do_sprite(@aliado[:pkmn])
    pag.graphic.character_hue  = (@aliado[:pkmn].super_shiny_hue.to_i rescue 0)
    pag.trigger    = -1
    # ⚠️ O `step_anime` BRIGA COM O `parar_evento!`, E O QUE SE VE E UM TREMOR.
    #
    # Com `step_anime = true`, o `Game_Character#update` do motor avanca o
    # `@pattern` a CADA frame, ande o boneco ou nao. O `parar_evento!` repoe o
    # padrao de descanso. Os dois correm no mesmo frame, um a seguir ao outro,
    # para sempre: o motor adianta, nos repomos, o motor adianta. O sprite
    # salta entre dois desenhos sessenta vezes por segundo — e isso le-se como
    # um boneco a tremer, nao como um boneco parado.
    #
    # Nao e preciso: o `animar_evento!` ja move as pernas a mao, e so e chamado
    # quando o boneco anda mesmo. Desligar o `step_anime` tira o motor da
    # equacao e deixa uma so mao a mandar no padrao.
    pag.step_anime = false    # o `animar_evento!` e que move as pernas
    pag.move_type  = 0
    pag.through    = true
    pag.list = [RPG::EventCommand.new(0, 0, [])]
    ev = Game_Event.new($game_map.map_id, rpg, $game_map)
    ev.through = true
    pousar_evento!(ID_ALIADO, ev, rpg)
    ev.refresh
    (AnilLanRework::ReleasedRoaming.sync_sprite(ev) rescue nil) if $scene.is_a?(Scene_Map)
    @aliado[:ev] = ev
    registar("o ajudante tinha desaparecido; reposto")
  rescue => e
    registar("falha a repor o ajudante: #{e.class}: #{e.message}")
  end

  def dispensar_aliado!
    if @aliado
      # A vida dele volta para a equipa, como a minha.
      valor = [[@aliado[:hp].to_i, 0].max, @aliado[:pkmn].totalhp.to_i].min
      if valor <= 0
        outros = ($player.party.compact.count { |p| !p.equal?(@aliado[:pkmn]) && !p.egg? && p.hp > 0 } rescue 0)
        valor = 1 if outros <= 0
      end
      (@aliado[:pkmn].hp = valor) rescue nil
      apagar_evento_bicho!(@aliado[:id])
    end
    apagar_evento_bicho!(ID_ALIADO) if $game_map && $game_map.events[ID_ALIADO]
    @aliado = nil
    @aliado_visto = nil
  rescue
    @aliado = nil
  end

  # ⚠️ AQUI ESTAVA O POKEMON A DESAPARECER, E A LINHA E DE UMA SO PALAVRA ERRADA.
  #
  # O segundo argumento do `empurrar!` e QUEM BATE — e dele que se calcula a
  # direccao do recuo. Isto passava `$game_player`, portanto o ajudante era
  # empurrado para longe de MIM a cada golpe que levava, e nunca de quem lhe
  # bateu.
  #
  # Numa batalha directa isso ja e estranho e passa: ele leva dois ou tres
  # golpes e volta a encostar-se. Na automatica e fatal, porque a luta e toda
  # dele — cada golpe recebido afasta-o mais uma casa de mim, sempre no mesmo
  # sentido, sem nada que o traga de volta enquanto estiver a combater. Dez
  # golpes sao dez casas: fora do ecra, "desaparecido".
  #
  # Para o JOGADOR o codigo sempre passou o atacante certo — `b[:ev]`, `ev`,
  # `outro`, nos tres sitios. So o ajudante e que tinha esta. E o tipo de
  # defeito que so se ve pondo os dois lados lado a lado.
  #
  # De caminho, a distancia tambem passa a ser a do golpe (`empurrao_de`), como
  # ja era do outro lado, em vez de uma casa fixa.
  def ferir_aliado!(d, mv = nil, atacante = nil)
    return unless aliado_vivo?
    d = d.to_i
    @aliado[:hp] = [@aliado[:hp] - d, 0].max
    (@aliado[:pkmn].hp = @aliado[:hp]) rescue nil
    if d > 0 && atacante
      empurrar!(@aliado[:ev], atacante, (empurrao_de(mv) rescue 1))
    end
    if @aliado[:hp] <= 0
      nome = (@aliado[:pkmn].name rescue "")
      animar_desmaio!(@aliado[:ev])
      # ⚠️ NA AUTOMATICA, ELE CAIR E O FIM DA BATALHA.
      #
      # Na directa o ajudante e um extra: cai, e eu continuo a lutar. Na
      # automatica ele e o UNICO que luta — dispensa-lo e deixar o jogador em
      # combate sem ninguem em campo, com os selvagens a andar por ali e nada
      # que os enfrente. Visto de dentro do jogo, e o Pokemon a "desaparecer".
      #
      # Guarda-se o modo antes do `dispensar_aliado!`, que limpa tudo.
      era_automatica = automatica?
      dispensar_aliado!
      dizer(_INTL("{1} desmaiou!", nome))
      if era_automatica
        sair!
        pbMessage(AnilLanRework.ui_format(
          "{1} não aguenta mais.\nA caça terminou.", nome)) rescue nil
      end
    end
  rescue
    nil
  end

  # Ele vai atras do inimigo mais proximo se houver briga por perto; senao anda
  # atras de mim. Sem a segunda metade, um ajudante ficava plantado no sitio
  # onde matou o ultimo bicho.
  # A posicao verdadeira do ajudante, que e de onde o recuo parte.
  def rx_ry_do_aliado(ev)
    [(ev.instance_variable_get(:@real_x) rescue 0).to_f,
     (ev.instance_variable_get(:@real_y) rescue 0).to_f]
  rescue
    [0.0, 0.0]
  end

  # Recuar sem virar as costas — continua a olhar para o inimigo, como o
  # `recuar_bicho!` faz do outro lado. Um bicho que foge de costas le-se como
  # fuga; de frente, le-se como quem espera a abertura.
  # ⚠️ FUGIR DO MAIS PROXIMO NAO E FUGIR DO PERIGO.
  #
  # O recuo apontava ao inimigo mais perto e ignorava os outros — e com dois ou
  # tres a volta, "para longe daquele" e muitas vezes "para cima destes". Ele
  # recuava e ficava colado a outro, que e onde o utilizador o viu: parado de
  # frente para um selvagem, sem golpe, a levar de graca.
  #
  # A soma das repulsoes resolve isto sem logica nenhuma de decisao: cada
  # inimigo dentro do raio empurra-o, e ele anda na soma. Com um so, e igual ao
  # que era; com varios, sai pela abertura que houver — que e o que um bicho
  # cercado faz.
  #
  # O peso e maior para quem esta mais perto (1/d): quem esta a uma casa importa
  # mais do que quem esta a tres, e sem isso a soma tratava-os por igual.
  RECUO_MINIMO = 2.0    # casas: o afastamento que se quer garantir de cada um

  def rumo_de_fuga(ev, rx, ry)
    sx = 0.0
    sy = 0.0
    bichos_vivos.each do |b|
      e = b[:ev]
      next unless e
      ox = (e.instance_variable_get(:@real_x) rescue nil)
      oy = (e.instance_variable_get(:@real_y) rescue nil)
      next unless ox && oy
      dx = rx - ox.to_f
      dy = ry - oy.to_f
      d = Math.sqrt((dx * dx) + (dy * dy)) / Game_Map::REAL_RES_X.to_f
      next if d > DISTANCIA_MEDO
      # Em cima um do outro: empurra-se para qualquer lado, senao dividia por
      # zero e ele ficava.
      if d < 0.05
        sx += (rand - 0.5)
        sy += (rand - 0.5)
        next
      end
      peso = 1.0 / [d, RECUO_MINIMO].min
      sx += (dx / (d * Game_Map::REAL_RES_X.to_f)) * peso
      sy += (dy / (d * Game_Map::REAL_RES_X.to_f)) * peso
    end
    n = Math.sqrt((sx * sx) + (sy * sy))
    return nil if n < 0.0001
    [sx / n, sy / n]
  rescue
    nil
  end

  def recuar_aliado!(inimigo, dt, ev, pos)
    rx, ry = pos
    fuga = rumo_de_fuga(ev, rx, ry)
    irx = (inimigo.instance_variable_get(:@real_x) rescue rx).to_f
    iry = (inimigo.instance_variable_get(:@real_y) rescue ry).to_f
    dx = fuga ? fuga[0] : (rx - irx)
    dy = fuga ? fuga[1] : (ry - iry)
    n = Math.sqrt((dx * dx) + (dy * dy))
    if n < 0.001
      parar_evento!(ev)
      return
    end
    ux = dx / n
    uy = dy / n
    # Olha para o inimigo enquanto anda para tras.
    nova = (ux.abs > uy.abs) ? ((ux > 0) ? 4 : 6) : ((uy > 0) ? 8 : 2)
    (ev.instance_variable_set(:@direction, nova) rescue nil)
    vel = [velocidade_livre(@aliado[:pkmn]), 1.0].max * 0.75
    passo = vel * Game_Map::REAL_RES_X * dt
    nx = rx + (ux * passo)
    rx = nx if casa_livre_para_evento?(ev, nx, ry)
    ny = ry + (uy * passo)
    ry = ny if casa_livre_para_evento?(ev, rx, ny)
    (ev.instance_variable_set(:@real_x, rx) rescue nil)
    (ev.instance_variable_set(:@real_y, ry) rescue nil)
    (ev.instance_variable_set(:@x, (rx / Game_Map::REAL_RES_X).round) rescue nil)
    (ev.instance_variable_set(:@y, (ry / Game_Map::REAL_RES_Y).round) rescue nil)
    animar_evento!(ev)
  rescue
    nil
  end

  def mover_aliado!
    return unless aliado_vivo?
    dt = [(@delta || (1.0 / 60.0)), 0.1].min
    ev = @aliado[:ev]
    alvo = bicho_focado
    # ⚠️ O AJUDANTE SEGUIA A MESMA LOGICA DE AVANCO, SEM O MESMO CUIDADO.
    #
    # Ele engaja assim que o inimigo entra no raio, tenha ou nao com que bater.
    # Na batalha automatica isso e o combate inteiro — ele e o unico que luta —
    # e ve-se bem: gasta os quatro golpes, continua encostado, e leva a recarga
    # toda de borla.
    #
    # Com nada pronto, o inimigo deixa de ser um destino e passa a ser uma
    # coisa de que se foge: ele recua ate a `DISTANCIA_MEDO` e so volta a
    # entrar quando tiver golpe. O `pensar_aliado!` continua a decidir o que
    # usar — isto so trata de onde ele poe os pes.
    # ⚠️ FOGE-SE DO MAIS PERTO, E NAO DO QUE ESTAVA A SER ATACADO.
    #
    # O `bicho_focado` e a escolha de quem ATACAR — e isso e outra pergunta. Com
    # tres bichos em volta, o focado pode ser o que esta mais longe, e recuar
    # dele podia ser andar para cima dos outros dois. Quem manda no recuo e a
    # ameaca imediata.
    pronto = algum_golpe_pronto?(@aliado[:pkmn], @aliado[:prontos])
    unless pronto
      perto = (bichos_vivos.select { |x| x[:ev] }
                           .min_by { |x| distancia_casas(x[:ev], ev) } rescue nil)
      # ⚠️ E O RECUO TEM TRELA. FUGIR PARA SEMPRE E A MESMA COISA QUE SUMIR.
      #
      # O recuo que escrevi nao tinha limite nenhum: com um bicho a persegui-lo
      # e a recarga a demorar, ele afastava-se de mim casa a casa sem nada que o
      # travasse. O sintoma e o mesmo do empurrao errado aqui em cima — o
      # Pokemon acaba fora do ecra — e por isso os dois tinham de ser vistos na
      # mesma ronda.
      #
      # Passada a trela, ele deixa de fugir e volta para mim. Prefere levar um
      # golpe a perder-se: eu sou o sitio seguro, e um ajudante que nao consegue
      # voltar nao serve para nada.
      if perto && distancia_casas(perto[:ev], ev) < DISTANCIA_MEDO &&
         distancia_casas($game_player, ev) <= ALIADO_TRELA
        recuar_aliado!(perto[:ev], dt, ev, rx_ry_do_aliado(ev))
        return
      end
    end
    # ⚠️ O ENGAJAMENTO NAO TINHA TRELA, E O RECUO TINHA. FALTAVA METADE.
    #
    # A regra era: ha um inimigo a menos de 6,5 casas DELE? Entao vai la. Sem
    # olhar uma vez para onde eu estou.
    #
    # Na pratica isso quer dizer que basta um selvagem aparecer para ele deixar
    # de me seguir — eu ando para longe, ele fica a bater-se, e a distancia
    # entre nos cresce sem limite. Foi o que se reportou: "nem me segue quando
    # me afasto, so fica ali".
    #
    # A mesma trela do recuo (`ALIADO_TRELA`) passa a valer aqui. Perto de mim,
    # ele luta; longe de mais, volta — mesmo com o inimigo ao lado. Eu sou o
    # ponto de referencia dele, e um ajudante que se perde a lutar nao ajuda.
    perto_de_mim = (distancia_casas($game_player, ev) <= ALIADO_TRELA)
    if alvo && alvo[:ev] && pronto && perto_de_mim &&
       distancia_casas(alvo[:ev], ev) <= ALIADO_ENGAJA
      destino = alvo[:ev]
      paragem = ALIADO_PARAGEM
    else
      destino = $game_player
      paragem = ALIADO_SEGUE
    end
    rx = (ev.instance_variable_get(:@real_x) rescue 0).to_f
    ry = (ev.instance_variable_get(:@real_y) rescue 0).to_f
    drx = (destino.instance_variable_get(:@real_x) rescue 0).to_f
    dry = (destino.instance_variable_get(:@real_y) rescue 0).to_f
    dx = drx - rx
    dy = dry - ry
    n = Math.sqrt((dx * dx) + (dy * dy))
    if (n / Game_Map::REAL_RES_X.to_f) <= paragem || n < 0.001
      parar_evento!(ev)
      return
    end
    dx /= n
    dy /= n
    nova = (dx.abs > dy.abs) ? ((dx > 0) ? 6 : 4) : ((dy > 0) ? 2 : 8)
    (ev.instance_variable_set(:@direction, nova) rescue nil)
    vel = [velocidade_livre(@aliado[:pkmn]), 1.0].max
    passo = vel * Game_Map::REAL_RES_X * dt

    # ⚠️ SEM VISTA, ANDA-SE COMO UM PERSONAGEM: PELOS CORREDORES.
    #
    # A perseguicao em linha recta funciona em campo aberto e e ridicula numa
    # caverna: o bicho encosta-se a parede e desliza ao longo dela com a cara
    # colada, porque o eixo bloqueado perde-se e o outro continua. Foi o que se
    # viu — "andam com a cara a arrastar na parede".
    #
    # Quando nao ha linha de vista, ele deixa de deslizar e passa a andar por
    # casas: alinha-se ao centro do corredor e avanca por um eixo de cada vez,
    # tentando primeiro o que mais falta. E o suficiente para dobrar esquinas e
    # sair de vaos, sem o custo de um algoritmo de caminhos a correr por bicho
    # e por frame.
    # ⚠️ O `b` NAO EXISTE AQUI, E FOI POR ISSO QUE ELE NUNCA SE MEXEU.
    #
    # Este bloco veio copiado do movimento dos selvagens, onde `b` e a ficha do
    # bicho que se esta a mover. No ajudante a ficha chama-se `@aliado` e `b`
    # nao e nada — `NameError` a cada frame, apanhado pelo `rescue nil` do fim
    # do metodo, que o engole sem uma linha de log. O ajudante nascia e ficava
    # onde nasceu, para sempre, sem um erro a dizer porque.
    #
    # E a vista mede-se contra o DESTINO e nao contra o jogador: quando ele vai
    # a um inimigo, o que decide se pode ir a direito e a parede entre ele e o
    # inimigo, nao a parede entre ele e nos.
    # ⚠️ O `andar_por_casas!` FICA, MAS SO COMO REDE.
    #
    # Ele resolve o obstaculo de um passo e mais nada — e por isso que o
    # ajudante raspava na parede tal e qual os selvagens. Quando ha campo, o
    # campo manda; quando nao ha (o destino esta fora da vista, ou dentro da
    # pedra), cai-se no que ja existia em vez de ficar parado.
    unless vista_livre_cache?(ev, destino, [:aliado, :andar])
      atalho = rumo_do_campo(ev, destino, rx, ry)
      unless atalho
        andar_por_casas!(@aliado, dx, dy, rx, ry, passo)
        return
      end
      dx = atalho[0]
      dy = atalho[1]
      nova = (dx.abs > dy.abs) ? ((dx > 0) ? 6 : 4) : ((dy > 0) ? 2 : 8)
      (ev.instance_variable_set(:@direction, nova) rescue nil)
    end
    # ⚠️ DOIS TESTES DE COLISAO QUE DISCORDAM, E NINGUEM DAVA POR ISSO.
    #
    # A decisao de ir a direito vem do `vista_livre?`, que olha SO para o
    # terreno (`casa_de_pedra?`). O passo, esse, passa pelo
    # `casa_livre_para_evento?`, que olha para o terreno E para os corpos E para
    # os limites do campo.
    #
    # Quando discordam — um selvagem no caminho, um evento do mapa com grafico
    # de charset (que o `Game_Map#passable?` nem sequer ve, porque so conhece
    # eventos com tile_id) — acontece isto: a vista diz "esta livre", ele
    # escolhe a linha recta, o passo e recusado, e ele fica a empurrar contra
    # aquilo para sempre. O desvio nunca chega a ser tentado porque, do ponto
    # de vista dele, nao ha nada para desviar.
    #
    # Nao vale a pena tentar por os dois testes de acordo: um e uma linha e o
    # outro e um passo, e ha sempre um caso em que divergem. O que vale e olhar
    # para o RESULTADO — se o passo nao produziu deslocamento nenhum, a linha
    # recta nao serve, seja porque for, e tenta-se contornar.
    return if destravar!(@aliado, rx, ry, passo)
    rx0 = rx
    ry0 = ry
    nx = rx + (dx * passo)
    rx = nx if casa_livre_para_evento?(ev, nx, ry)
    ny = ry + (dy * passo)
    ry = ny if casa_livre_para_evento?(ev, rx, ny)
    if (rx - rx0).abs < 0.01 && (ry - ry0).abs < 0.01
      andar_por_casas!(@aliado, dx, dy, rx0, ry0, passo)
      return
    end
    ev.instance_variable_set(:@real_x, rx)
    ev.instance_variable_set(:@real_y, ry)
    ev.instance_variable_set(:@x, (rx / Game_Map::REAL_RES_X.to_f).round)
    ev.instance_variable_set(:@y, (ry / Game_Map::REAL_RES_Y.to_f).round)
    (ev.calculate_bush_depth rescue nil)
    animar_evento!(ev)
  rescue
    nil
  end

  def pensar_aliado!
    return unless aliado_vivo?
    agora = Time.now.to_f
    return if agora < @aliado[:proximo].to_f
    ev = @aliado[:ev]
    # ⚠️ A LISTA ERA SO DOS SELVAGENS, E NUM DUELO NAO HA SELVAGENS.
    #
    # `bichos_vivos` sao os bichos da IA. Num 2v2 entre jogadores o adversario e
    # uma PESSOA e o parceiro dele e uma sombra — nenhum dos dois esta nessa
    # lista. O aliado procurava, nao encontrava ninguem, e devolvia. Andava
    # (o movimento usa outro caminho) mas nunca atacava: "entrou e ficou
    # parado".
    #
    # O `alvos_do_aliado` junta os dois mundos numa lista so, com a mesma forma
    # de sempre — um Hash com :ev e :pkmn — para o resto do metodo nao dar por
    # nada.
    alvo = alvos_do_aliado.min_by { |b| distancia_casas(b[:ev], ev) }
    return unless alvo
    dist = distancia_casas(alvo[:ev], ev)

    # A mesma cabeca dos selvagens: ele tambem escolhe o golpe que rende mais.
    escolha = escolher_golpe(@aliado, alvo[:pkmn], alvo[:hp], dist, !alvo[:estado].nil?)
    return unless escolha
    i, mv = escolha
    @aliado[:prontos][i] = agora + (recarga_do_golpe(mv) / 60.0)
    @aliado[:proximo] = agora + ALIADO_INTERVALO
    if buff?(mv)
      aplicar_buff!(@aliado[:pkmn], mv)
      # Num reforco quem lanca e quem leva sao o mesmo: e o que ja acontece
      # quando somos nos a reforcar-nos.
      tocar_no_character!(@aliado[:ev], animacao_do_golpe(mv.id), 0, @aliado[:ev])
      dizer(_INTL("{1} se preparou!", (@aliado[:pkmn].name rescue "")))
      return
    end
    atacar_aliado!(alvo, mv)
  rescue => e
    registar("falha a pensar (aliado): #{e.class}: #{e.message}")
  end

  # Contra quem o ajudante pode lutar: os selvagens, e — em duelo — o outro
  # jogador e a sombra do parceiro dele.
  def alvos_do_aliado
    lista = bichos_vivos.select { |b| b[:ev] }
    # ⚠️ NA CAVERNA QUEM LA ESTIVER E INIMIGO, E O AJUDANTE TEM DE SABER.
    #
    # Ele so olhava para os selvagens e para o adversario de um duelo. Na
    # caverna o outro jogador nao e nem uma coisa nem outra — e o ajudante
    # passava ao lado dele como se nao existisse, enquanto o dono levava.
    if caverna?
      (AnilLanRework.players rescue {}).each_pair do |pid, p|
        next unless p && (p.map_id.to_i == $game_map.map_id.to_i rescue false)
        next unless p.respond_to?(:x)
        next if coop_amigo?(pid)
        lista += [{ :ev => p, :pkmn => @meu, :hp => 1, :hp_max => 1,
                    :estado => nil, :remoto => true }]
      end
      lista += [{ :ev => @parceiro_ev, :pkmn => @meu, :hp => 1, :hp_max => 1,
                  :estado => nil, :remoto => true }] if @parceiro_ev
      return lista
    end
    if pvp?
      outro = adversario_remoto
      if outro && outro.respond_to?(:x)
        lista += [{ :ev => outro, :pkmn => @inimigo, :hp => @hp_dele,
                    :hp_max => @hp_dele_max, :estado => @estado_dele,
                    :remoto => true }]
      end
      sombra = @parceiro_ev
      if sombra
        lista += [{ :ev => sombra, :pkmn => @inimigo, :hp => @hp_dele,
                    :hp_max => @hp_dele_max, :estado => nil, :remoto => true }]
      end
    end
    lista
  rescue
    bichos_vivos.select { |b| b[:ev] }
  end

  # ⚠️ A MARCA DO DONO SAI SEMPRE, POR `ensure`, E NAO A MAO.
  #
  # Este metodo punha `@dono_do_golpe = :aliado` no inicio e limpava-o na ultima
  # linha. Funcionava para tres dos quatro ramos — o ramo do FEIXE tem um
  # `return` proprio e saia por cima da limpeza.
  #
  # A partir do primeiro feixe que o ajudante disparasse, a marca ficava presa
  # em `:aliado` PARA SEMPRE. E como o meu proprio caminho de ataque nunca
  # escreve esta marca (conta com o `|| :eu` la no `ferir_bicho!`), todos os
  # golpes MEUS a partir dai passavam a ser creditados a ele.
  #
  # O que se ve em jogo: eu uso Giga Drain, e quem enche a vida e o ajudante. O
  # bicho dele parecia nao levar dano nenhum, porque o dreno dos meus golpes
  # andava a repor-lhe a vida a cada pancada.
  #
  # Limpar a mao em cada `return` resolvia este caso e deixava a armadilha
  # montada para o proximo ramo que alguem acrescente. O `ensure` corre haja o
  # que houver — `return`, excepcao, ramo novo — e portanto a marca deixa de
  # poder escapar.
  def atacar_aliado!(alvo, mv)
    marcar_dono_aliado!(alvo, mv)
  ensure
    @dono_do_golpe = nil
  end

  def marcar_dono_aliado!(alvo, mv)
    ev = @aliado[:ev]
    nome = (GameData::Move.get(mv.id).name rescue mv.id.to_s)
    # ⚠️ DAQUI PARA A FRENTE, O GOLPE E DELE.
    #
    # O `ferir_bicho!` usa esta marca para saber a quem devolver o dreno e em
    # quem descarregar os espinhos. Limpa-se no fim, senao o proximo golpe meu
    # seria creditado ao ajudante.
    @dono_do_golpe = :aliado
    anim = animacao_do_golpe(mv.id)
    saida = saida_do_golpe(mv, anim)
    if saida == :feixe
      feixe_de_alguem!(ev, (alvo && alvo[:ev]), anim)
      ferir_bicho!(alvo, dano_do_aliado(alvo, mv), mv, nil) if alvo
      narrar(_INTL("{1} usou {2}!", (@aliado[:pkmn].name rescue ""), nome))
      return
    end
    if saida == :voo
      inf = infalivel?(mv.id)
      dar_bote!(ev, (alvo[:ev].x rescue ev.x), (alvo[:ev].y rescue ev.y)) if contacto?(mv)
      lancar!(:x => ev.x, :y => ev.y, :dir => (ev.direction rescue 2),
              :alvo => alvo[:ev], :anim => anim.to_i, :infalivel => inf,
              :move_id => mv.id, :mv => mv, :nome => nome, :meu => false,
              :aliado => true, :bicho => alvo,
              :alcance => alcance_do_lancamento(mv), :curto => contacto?(mv),
              :vel => velocidade_do_lancamento(mv, inf))
    elsif area?(mv) || em_volta?(mv)
      # ⚠️ UM GOLPE DE AREA DO AJUDANTE SAIA COMO UM GOLPE NORMAL, NUM ALVO SO.
      #
      # O `atacar_aliado!` so conhecia dois casos: lancamento e corpo a corpo.
      # Um Razor Leaf caia no segundo — uma animacao, um alvo, e o resto dos
      # inimigos a perder vida sem nada lhes ter tocado. Visto de fora parecia
      # que o golpe tinha saido de mim, porque era o unico gesto no ecra que
      # explicava tres inimigos a cair.
      #
      # Agora e o mesmo desenho do `leque!` do jogador, com a ancora nele: o
      # gesto de lancar em cima do ajudante, e depois uma rajada por inimigo,
      # cada folha a perseguir o seu.
      tocar_no_character!(ev, anim, 0, ev) if anim.to_i > 0
      perto = bichos_vivos.select do |x|
        x[:ev] && distancia_casas(x[:ev], ev) <= alcance_do_lancamento(mv)
      end
      perto = [alvo] if perto.empty? && alvo
      perto.each_with_index do |x, i|
        next unless x && x[:ev]
        RAJADA_POR_ALVO.times do |k|
          (@lancamentos ||= []) << {
            :em => (Graphics.frame_count rescue 0) + (i * 2) + (k * RAJADA_INTERVALO),
            :mv => mv, :nome => nil, :anim => 0, :bicho => x, :de_aliado => true
          }
        end
        ferir_bicho!(x, dano_do_aliado(x, mv), mv, nil)
      end
    else
      # ⚠️ O QUARTO ARGUMENTO E QUEM ATACA, E FALTAVA.
      #
      # O `tocar_no_character!` monta a animacao com duas ancoras: quem lanca e
      # quem leva. Sem o quarto argumento, quem lanca e sempre o `$game_player`
      # — portanto o golpe do AJUDANTE era desenhado a sair do MEU Pokemon, com
      # a linha inteira (direccao e comprimento) medida a partir de mim.
      #
      # Com dois Pokemon nossos no campo isso e ilegivel: ve-se um golpe sair
      # de quem nao o deu. A ancora certa e o boneco dele.
      tocar_no_character!(alvo[:ev], anim, 0, @aliado[:ev]) if anim.to_i > 0
      ferir_bicho!(alvo, dano_do_aliado(alvo, mv), mv, nil)
    end
    narrar(_INTL("{1} usou {2}!", (@aliado[:pkmn].name rescue ""), nome))
    @dono_do_golpe = nil
  rescue => e
    @dono_do_golpe = nil
    registar("falha a atacar (aliado): #{e.class}: #{e.message}")
  end

  def dano_do_aliado(b, mv)
    return 0 if golpe_de_estado?(mv)
    dano(@aliado[:pkmn], b[:pkmn], mv)
  rescue
    0
  end

  # ⚠️ COM UM AJUDANTE NO MAPA, O INIMIGO TEM DE ESCOLHER.
  #
  # Antes toda a gente batia no jogador porque so havia o jogador. Agora vai ao
  # mais proximo — e e isso que faz o ajudante valer a pena: ele PUXA golpes que
  # vinham para mim.
  # ⚠️ QUEM E QUE OS SELVAGENS PODEM ATACAR. UMA LISTA, E SO UMA.
  #
  # Havia duas respostas a esta pergunta e elas nao concordavam:
  #
  #   o `alvo_da_ia`   escolhia entre mim e o ajudante, pelo mais proximo
  #   o `mover_bicho!` perseguia o `$game_player`, sempre, sem perguntar nada
  #
  # E a segunda desfazia a primeira: como eles andavam SEMPRE para mim, eu
  # acabava sempre por ser o mais proximo, e o ajudante nunca chegava a ser
  # escolhido. Ele podia estar encostado a um Geodude que o Geodude continuava
  # a atravessar o mapa atras de mim.
  #
  # E na batalha automatica isso e pior do que injusto: la eu sou o TREINADOR,
  # nao um lutador. Um selvagem a vir para cima de mim nesse modo nao e um
  # alvo mal escolhido — e um alvo que nao devia existir.
  def alvos_da_ia
    lista = []
    # Na automatica eu saio da lista. E a regra inteira do modo: quem luta e
    # ele, quem anda sou eu.
    #
    # ⚠️ E CAIDO TAMBEM SE SAI DELA.
    #
    # Bater num Pokemon que ja esta no chao a espera de socorro nao e
    # dificuldade: e uma matilha a impedir que alguem venha levanta-lo, e sem
    # forma nenhuma de responder. Quem esta caido e isento ate se levantar.
    lista << $game_player unless automatica? || caido?
    lista << @aliado[:ev] if aliado_vivo?
    lista.compact
  rescue
    [$game_player]
  end

  # ⚠️ E A ESCOLHA TEM DE TER MEMORIA, SENAO ELES GAGUEJAM.
  #
  # Com dois alvos quase a mesma distancia, "o mais proximo" troca de resposta a
  # cada passo — e o bicho fica a virar-se para um e para o outro sem nunca
  # chegar a nenhum. E o mesmo defeito do "tremer", agora na cabeca em vez de
  # nos pes.
  #
  # Guarda-se a escolha e so se muda quando o outro estiver claramente mais
  # perto. Uma casa e meia chega para a troca se ler como uma decisao.
  TROCA_DE_ALVO = 1.5

  def alvo_da_ia(b)
    lista = alvos_da_ia
    return nil if lista.empty?
    return lista.first unless b && b[:ev]
    actual = b[:alvo_ia]
    actual = nil unless actual && lista.any? { |a| a.equal?(actual) }
    melhor = lista.min_by { |a| distancia_casas(a, b[:ev]) }
    if actual && melhor && !melhor.equal?(actual)
      dm = distancia_casas(melhor, b[:ev])
      da = distancia_casas(actual, b[:ev])
      melhor = actual if (da - dm) < TROCA_DE_ALVO
    end
    b[:alvo_ia] = melhor || lista.first
  rescue
    (automatica? ? (aliado_vivo? ? @aliado[:ev] : nil) : $game_player)
  end

  def escolher_ajudante!(excepto)
    equipa = ($player.party.compact.select { |p| !p.egg? && p.hp > 0 && !p.equal?(excepto) } rescue [])
    return nil if equipa.empty?
    nomes = equipa.map { |p| "#{p.name} Nv.#{p.level}" }
    nomes << _INTL("Ninguém")
    escolha = pbMessage(_INTL("Levar um ajudante?"), nomes, nomes.length)
    return nil if escolha < 0 || escolha >= equipa.length
    equipa[escolha]
  rescue
    nil
  end

  #-----------------------------------------------------------------------------
  # BATALHA DIRETA
  #
  # ⚠️ AQUI NAO SE INVOCAM SELVAGENS: DEIXA-SE O MAPA INVOCA-LOS.
  #
  # A cacada (`/cacar`) enche o ecra de uma vez e serve para limpar uma area.
  # Isto e o contrario: entra-se sozinho e anda-se pelo mato como sempre, so
  # que o encontro, em vez de abrir o ecra de batalha, poe o bicho AO LADO. E a
  # mesma pergunta que o jogo faz a cada passo na relva — o `encounter_type` do
  # sitio onde se esta, a tabela do mapa, a taxa do mapa — respondida no mesmo
  # sitio de sempre. Muda so o que acontece a seguir.
  #
  # ⚠️ E o passo tem de ser contado a mao.
  #
  # O movimento livre nao chama `increase_steps`, portanto o `pbOnStepTaken` do
  # motor nunca dispara — o que e bom (nao queremos a batalha por turnos a
  # aparecer por cima), mas quer dizer que ninguem conta os passos. Conta-se
  # aqui, pela distancia mesmo andada.
  #-----------------------------------------------------------------------------
  # ⚠️ OITO AO MESMO TEMPO NAO E DIFICIL: E IMPOSSIVEL.
  #
  # Com oito a atacar de 3,2 em 3,2 segundos chega um golpe a cada 0,4 s. Nao ha
  # Pokemon que aguente isso, e nao e o nivel deles que decide — e a aritmetica.
  # Quatro de cada vez, e destes so os tres mais proximos e que atacam: os
  # outros aproximam-se e esperam a vez, como numa briga a serio.
  DIRECTA_MAX   = 4      # quantos podem estar em cima de nos ao mesmo tempo
  ATACAM_AO_MESMO_TEMPO = 3
  DIRECTA_PASSO = 1.0    # casas andadas entre duas perguntas
  # ⚠️ CATORZE CASAS E MEIO ECRA: ele reparava em nos antes de caber na tela.
  # Cinco e mais ou menos "estou aqui ao lado" — da para atravessar uma rota sem
  # arrastar meia rota atras.
  ADOPCAO_RAIO  = 5.0    # casas: a partir daqui ele repara em nos
  DESISTE_RAIO  = 12.0   # e a partir daqui desiste e volta a vida dele
  ADOPCAO_CADENCIA = 20  # frames entre varreduras do mapa

  # ⚠️ OS SELVAGENS JA ESTAO NO MAPA — NAO SE INVENTAM OUTROS.
  #
  # Este jogo mostra os encontros no mundo (o plugin VOE, sincronizado entre
  # jogadores pelo MOD 070): aquele Rattata a andar na relva e um `Game_PokeEvent`
  # com um Pokemon verdadeiro dentro. Eu estava a criar copias minhas ao lado
  # dele, o que dava dois bichos para o mesmo encontro e nenhum deles era o que
  # a Gaby via.
  #
  # Adoptar e o certo, e resolve o multijogador de borla: o evento e o MESMO nos
  # dois ecrans, porque a sincronizacao dos spawns ja existia muito antes desta
  # arena.
  #
  # Enquanto adoptado, cala-se a rotina de passeio dele (`@move_type`) — senao
  # o plugin puxa-o para um lado e a perseguicao puxa-o para o outro. Ao sair,
  # devolve-se como estava.
  def selvagem_do_mapa?(ev)
    defined?(Game_PokeEvent) && ev.is_a?(Game_PokeEvent)
  rescue
    false
  end

  def adoptar!(ev, pk)
    # ⚠️ A VIDA E A DELE, NAO UMA COPIA CHEIA.
    #
    # Um selvagem do mapa e um Pokemon a serio, com a vida que tem. Comecar
    # sempre cheio fazia a arena contar uma historia diferente da do jogo — e
    # ao ferir escreve-se de volta, para uma batalha normal a seguir encontrar
    # o bicho como o deixamos.
    b = {
      :pkmn => pk, :hp => [(pk.hp.to_i rescue pk.totalhp), 1].max, :hp_max => pk.totalhp,
      :id => ev.id, :ev => ev, :adoptado => true,
      :move_type_antigo => (ev.instance_variable_get(:@move_type) rescue 0),
      :estado => nil, :estado_ate => 0.0, :estado_tique => 0.0,
      :energia => ENERGIA_MAX, :cansada => false,
      :prontos => [0.0, 0.0, 0.0, 0.0], :proximo => Time.now.to_f + 1.0
    }
    (ev.instance_variable_set(:@move_type, 0) rescue nil)
    bichos << b
    esquecer_vivos!
    registar("adoptou #{pk.speciesName} (evento #{ev.id})")
    dizer(_INTL("{1} selvagem vem para cima!", pk.speciesName))
    b
  rescue => e
    registar("falha a adoptar: #{e.class}: #{e.message}")
    nil
  end

  # ⚠️ QUEM VOLTA AO MATO VOLTA INTEIRO.
  #
  # A luta da arena foi nossa; o Pokemon que fica no mundo nao devia sair dela
  # marcado. Alem de justo, e o que impede um spawn ferido de andar por ai a
  # espera de partir a proxima batalha normal.
  def soltar_bicho!(b)
    curar_selvagem!(b)
    ev = b[:ev]
    return unless ev
    (ev.instance_variable_set(:@move_type, b[:move_type_antigo].to_i) rescue nil)
  end

  def curar_selvagem!(b)
    return unless b && b[:pkmn]
    pk = b[:pkmn]
    if pk.respond_to?(:heal)
      (pk.heal rescue nil)
    else
      (pk.hp = pk.totalhp) rescue nil
    end
  rescue
    nil
  end

  # Quem ficou muito para tras deixa de nos perseguir e volta ao passeio — senao
  # bastava andar um bocado para acabar com meia rota em fila indiana atras.
  # ⚠️ O PLUGIN APAGA O SPAWN E EU FICO COM O FANTASMA.
  #
  # O VOE tira do mapa os selvagens que ficam longe do jogador — apaga o evento
  # e deita fora o sprite. A minha lista continua a segurar aquele objecto: sem
  # sprite ninguem o ve, mas ele ainda esta na lista, ainda pensa e ainda ataca.
  # Era isso que o jogador via — golpes a vir do nada.
  #
  # A pergunta certa nao e "esta longe?", e "ainda e este o evento que o mapa
  # tem neste id?". Se o mapa ja nao o conhece, ele nao existe.
  def evento_ainda_no_mapa?(b)
    return false unless b && b[:ev] && $game_map
    $game_map.events[b[:id]].equal?(b[:ev])
  rescue
    false
  end

  def largar_os_distantes!
    bichos.dup.each do |b|
      unless evento_ainda_no_mapa?(b)
        registar("largou #{(b[:pkmn].speciesName rescue '?')}: o mapa ja nao o tem")
        (b[:balao].dispose rescue nil) if b[:balao]
        b[:ev] = nil
        bichos.delete(b)
        esquecer_vivos!
        next
      end
      # ⚠️ QUEM ENTROU NA LUTA NAO SE VAI EMBORA A MEIO DELA.
      #
      # O `DESISTE_RAIO` largava um selvagem que se afastasse doze casas, e
      # isso faz sentido para o mundo: nao se arrasta meia rota atras de nos.
      #
      # Numa luta nao faz. Um adversario que desaparece porque nos afastamos
      # nao e um adversario — e um cenario. E pior: bastava recuar para o fazer
      # sumir, o que transforma "fugir" na melhor jogada de todas.
      #
      # Enquanto a arena estiver de pe, quem entrou fica. Sai quando cair, ou
      # quando se sair do modo — e ai o `sair!` trata de todos de uma vez.
      #
      # A limpeza de cima (o evento que o mapa ja nao tem) continua a valer: ali
      # nao ha escolha nenhuma a fazer, o boneco deixou mesmo de existir.
      next if @activa
      next unless b[:adoptado]
      next if distancia_casas(b[:ev], $game_player) <= DESISTE_RAIO
      soltar_bicho!(b)
      bichos.delete(b)
      esquecer_vivos!
      registar("largou #{(b[:pkmn].speciesName rescue '?')}: ficou longe")
    end
    actualizar_foco!
  rescue
    nil
  end

  # ⚠️ A LIMPEZA ESTAVA PRESA A BATALHA DIRETA, E O MATO NAO SABE DISSO.
  #
  # O primeiro `return unless @directa` mandava embora tudo o que vinha a
  # seguir — incluindo a limpeza. Numa cacada (`/cacar`), ou numa luta com
  # ajudante que comecou por outra porta, o plugin continuava a semear e ninguem
  # varria. A adopcao e que e exclusiva da batalha direta; a limpeza e de
  # qualquer luta no mapa.
  # ⚠️ APAGAR DEPOIS DE NASCER E TARDE: VE-SE NASCER.
  #
  # A varredura corre de 20 em 20 frames, portanto um spawn que o plugin criava
  # ficava um terco de segundo no ecra antes de eu o apagar. Multiplicado pelo
  # ritmo a que ele semeia, o mato ficava a piscar — exactamente o que o jogador
  # descreveu.
  #
  # A limpeza depois do facto era o remendo; a trava e dizer NAO na porta. O
  # `spawnPokeEvent` do mapa e por onde todo o spawn visivel passa (e por onde a
  # sincronizacao entre jogadores tambem passa), e e ai que se recusa.
  #
  # A regra e a mesma da varredura, so que aplicada antes: numa cacada ou num
  # duelo nao nasce nada; na batalha direta so nasce o que cabe na luta e esta
  # perto o suficiente para entrar nela. A varredura fica como rede, para o que
  # ja estava no mapa quando a luta comecou.
  # ⚠️ EU TRAVEI NO SITIO ERRADO — O ESPECTACULO COMECA ANTES.
  #
  # Fui ler o plugin (Visible Overworld Wild Encounters). A tentativa de spawn e
  # o `pbSpawnOnStepTaken`, e ela faz esta sequencia:
  #
  #     escolhe a casa  ->  sorteia o encontro  ->  mexe a relva
  #       ->  spawnPokeEvent  ->  pbPlayCryOnOverworld   (o grito)
  #
  # O meu gancho estava no `spawnPokeEvent`, que e o QUARTO passo. Tudo o que
  # vem antes ja aconteceu: a relva mexeu, e o grito toca logo a seguir sem
  # sequer perguntar se o bicho nasceu. Era isso que se via e ouvia — o teatro
  # todo de um spawn que nao existiu.
  #
  # A trava certa e na porta da rua: `pbSpawnOnStepTaken`. Recusando ali, nao ha
  # casa escolhida, nao ha relva, nao ha grito e nao ha evento. E o "mudar
  # realmente o modo" que o jogador pediu.
  #
  # ⚠️ E ela e uma funcao de TOPO, portanto vive no `Object` — nao no Kernel.
  # (Ja houve um gancho neste projecto que ficou em `module Kernel` e nunca
  # correu; ver a nota do pbMessage.)
  def travar_mato?
    return false unless @activa
    return true if pvp?
    return true unless @directa
    bichos.length >= limite_de_selvagens
  rescue
    false
  end

  # ⚠️ ESTA PERGUNTA TEM DE PODER SER FEITA ANTES DA RELVA MEXER.
  #
  # Ela vivia dentro do `recusa_spawn?`, que so corre no `spawnPokeEvent` — o
  # quarto passo do plugin. Separada, pode ser feita no primeiro.
  def casa_longe_de_mais?(x, y)
    return false unless $game_player
    dx = (x.to_i - $game_player.x).to_f
    dy = (y.to_i - $game_player.y).to_f
    Math.sqrt((dx * dx) + (dy * dy)) > ADOPCAO_RAIO
  rescue
    false
  end

  def recusa_spawn?(x, y)
    return false unless @activa
    return true if pvp?
    return true unless @directa
    return true if bichos.length >= limite_de_selvagens
    casa_longe_de_mais?(x, y)
  rescue
    false
  end

  def adoptar_do_mato!
    return if pvp?
    return unless @activa
    return unless $game_map
    agora = (Graphics.frame_count rescue 0)
    return if (agora - @varrido.to_i) < ADOPCAO_CADENCIA
    @varrido = agora
    largar_os_distantes!
    # (nao ha `return` por lista cheia: mesmo cheia, a varredura tem de correr
    # para apagar os spawns que o plugin semeou entretanto.)
    # ⚠️ QUATRO SELVAGENS EM CIMA DE UM NIVEL 5 NAO E DIFICULDADE.
    #
    # Quem sai de Pallet com um inicial nao tem como aguentar um grupo — e a
    # arena passaria a ser uma coisa que so serve para quem ja esta no fim do
    # jogo. O numero de adversarios cresce com o nivel de quem esta a lutar: um
    # ate ao 9, dois ate ao 19, tres ate ao 29, quatro dai para cima.
    limite = limite_de_selvagens
    # ⚠️ LIMPAR UMA VEZ NAO CHEGA: O PLUGIN NAO PARA DE SEMEAR.
    #
    # Eu limpava o mato na entrada e dava-me por satisfeito. Mas o VOE continua a
    # criar spawns enquanto o jogador anda — e faz bem, e o trabalho dele. Ao fim
    # de uns passos o mapa estava outra vez cheio de encontros do modo normal, a
    # espera de serem pisados.
    #
    # A limpeza tem de ser CONTINUA: a cada varredura, quem couber na luta e
    # adoptado; quem sobrar sai do mapa. Assim os unicos selvagens visiveis sao
    # sempre os que estao a lutar comigo, e nunca ha um encontro do outro modo
    # escondido no meio deles.
    sobram = []
    $game_map.events.each_value do |ev|
      next unless selvagem_do_mapa?(ev)
      next if bicho_do_evento(ev)
      # ⚠️ O SHINY E CONFERIDO PRIMEIRO QUE TUDO, E ANTES NAO ERA.
      #
      # A regra "um shiny nunca vira adversario" existia — mas estava escrita no
      # FIM desta volta, atras de tres portoes que apagam o evento antes de se
      # chegar la: fora da batalha directa sai toda a gente; com a luta cheia
      # sai toda a gente; mais longe do que o raio de adopcao sai toda a gente.
      #
      # Qualquer um dos tres apagava o shiny do mapa. E a bola automatica ja ia
      # a caminho dele: quando ela chega, o `resolver_bola_shiny!` procura o
      # evento, nao o encontra, e diz "A bola nao acertou" — que e verdade e nao
      # explica nada. O alvo tinha sido varrido pelas minhas costas.
      #
      # Na agua nota-se mais porque os encontros de agua nascem mais longe, e
      # entao o portao da distancia dispara quase sempre. Mas o defeito nunca
      # foi da agua.
      #
      # Um shiny e uma excepcao a tudo: nao entra na luta, nao e apagado, nao
      # conta para o limite. Fica no mapa ate ser apanhado ou ate ir embora
      # sozinho.
      if evento_shiny?(ev)
        @shiny_ev = ev
        next
      end
      # Fora da batalha direta ninguem e adoptado: todos saem.
      unless @directa
        sobram << ev.id
        next
      end
      if bichos.length >= limite
        sobram << ev.id
        next
      end
      pk = (ev.pokemon rescue nil)
      unless pk
        sobram << ev.id
        next
      end
      if distancia_casas(ev, $game_player) > ADOPCAO_RAIO
        sobram << ev.id
        next
      end
      # ⚠️ UM SHINY NUNCA VIRA ADVERSARIO — e o teste ja foi feito la em cima.
      #
      # Se ele entrasse na briga como os outros, uma onda de Earthquake ou uma
      # folha perdida matava-o sem ninguem ter escolhido isso — e um shiny morto
      # por engano nao volta. Fica de fora da lista: nao ataca, nao e atacado,
      # e nem sequer conta para a mira. A unica coisa que se lhe faz e atirar
      # bolas, automaticamente.
      #
      # O teste estava AQUI, no fim, e por isso nao valia nada: os portoes que
      # apagam o evento vem todos antes. Subiu para o principio da volta; aqui
      # ja nao chega um shiny nenhum.
      adoptar!(ev, pk)
    end
    # Os que nao entraram na luta nao ficam a decorar o mato.
    sobram.each { |id| apagar_evento_bicho!(id) }
  rescue => e
    registar("falha a adoptar do mato: #{e.class}: #{e.message}")
  end

  # Um evento do mato que traz um Pokemon que brilha. Pergunta-se ao Pokemon e
  # nao a uma lista nossa: quem decide o que brilha e ele.
  def evento_shiny?(ev)
    pk = (ev.pokemon rescue nil)
    return false unless pk
    (pk.shiny? rescue false) || (pk.super_shiny? rescue false)
  rescue
    false
  end

  def limite_de_selvagens
    nivel = (@meu ? @meu.level.to_i : 5)
    n = 1 + (nivel / 10)
    [[n, 1].max, DIRECTA_MAX].min
  rescue
    1
  end

  def id_de_bicho_livre
    base  = caverna? ? ID_CAVERNA : ID_INIMIGO
    tecto = caverna? ? MAX_CAVERNA : MAX_BICHOS
    tecto.times do |i|
      id = base + i
      next if bichos.any? { |b| b[:id] == id }
      next if $game_map && $game_map.events[id]
      return id
    end
    nil
  end

  def contar_passo!(dt)
    rx = ($game_player.instance_variable_get(:@real_x) rescue 0).to_f
    ry = ($game_player.instance_variable_get(:@real_y) rescue 0).to_f
    if @passo_rx
      d = Math.sqrt(((rx - @passo_rx)**2) + ((ry - @passo_ry)**2)) / Game_Map::REAL_RES_X.to_f
      @andado = (@andado || 0.0) + d
    end
    @passo_rx = rx
    @passo_ry = ry
  rescue
    nil
  end

  # ⚠️ PLANO B: so quando o mapa NAO mostra selvagens.
  #
  # Onde o VOE nao poe ninguem a andar (mapas sem spawns visiveis), a batalha
  # direta continua a funcionar — invoca-se um a partir da tabela de encontros
  # do sitio, que e a mesma pergunta que o jogo faz a cada passo na relva.
  def spawnar_do_mato!
    return unless @directa
    return if pvp?
    return if defined?(Game_PokeEvent) && mapa_tem_selvagens?
    contar_passo!(@delta)
    return if (@andado || 0.0) < DIRECTA_PASSO
    @andado = 0.0
    return if bichos_vivos.length >= limite_de_selvagens
    return unless ($PokemonEncounters.encounter_possible_here? rescue false)
    tipo = ($PokemonEncounters.encounter_type rescue nil)
    return unless tipo
    # `triggered_by_step` a false: o acumulador de passos do motor nao esta a
    # correr aqui, e usa-lo dava numeros de outro sitio.
    return unless ($PokemonEncounters.encounter_triggered?(tipo, false, false) rescue false)
    enc = ($PokemonEncounters.choose_wild_pokemon(tipo) rescue nil)
    return unless enc
    pk = (pbGenerateWildPokemon(enc[0], enc[1]) rescue nil)
    return unless pk
    id = id_de_bicho_livre
    return unless id
    b = criar_bicho!(pk, id, 5)
    return unless b
    dizer(_INTL("{1} selvagem apareceu!", pk.speciesName))
    (pbSEPlay("Battle recall") rescue nil)
  rescue => e
    registar("falha a spawnar: #{e.class}: #{e.message}")
  end

  def mapa_tem_selvagens?
    return false unless $game_map
    $game_map.events.each_value { |ev| return true if selvagem_do_mapa?(ev) }
    false
  rescue
    false
  end

  # ⚠️ OS DOIS MODOS NAO PODEM PARTILHAR O MATO.
  #
  # Um spawn que ficou de antes da batalha direta e um encontro do modo normal a
  # espera de ser pisado: basta andar por cima e abre-se o ecra de batalha por
  # cima da luta em tempo real. E ao sair acontece o contrario — os selvagens que
  # a arena magoou, adoptou ou deixou grogues ficavam no mapa com a vida
  # estranha.
  #
  # Limpa-se o mato nas duas pontas. O plugin repoe os spawns como sempre fez,
  # e cada modo comeca com um mapa que e so dele.
  def limpar_spawns_do_mapa!
    return 0 unless $game_map && defined?(Game_PokeEvent)
    ids = $game_map.events.values.select { |ev| ev.is_a?(Game_PokeEvent) }.map { |ev| ev.id }
    ids.each { |id| apagar_evento_bicho!(id) }
    unless ids.empty?
      registar("mato limpo: #{ids.length} spawn(s) removidos")
      (AnilArenaIntrusos.anotar(:mato_do_mundo_limpo, "#{ids.length} evento(s)") rescue nil)
    end
    ids.length
  rescue => e
    registar("falha a limpar o mato: #{e.class}: #{e.message}")
    0
  end

  # ⚠️ O POKEMON CAÇA E EU ANDO. A LISTA DO QUE ISTO PRECISA E CURTA.
  #
  # Reaproveita-se tudo o que ja existe: o ajudante ja sabe seguir-me
  # (`mover_aliado!`), escolher alvo e atacar (`pensar_aliado!`,
  # `atacar_aliado!`), e os selvagens do mundo ja sao adoptados pelo
  # `adoptar_do_mato!`. O que este modo faz e so nao me transformar.
  #
  # E por isso que ele nasce pequeno: se a caça funcionar na directa, funciona
  # aqui — e o mesmo codigo.
  # ⚠️ SO O GUIA. O AMULETO NAO ENTRA NESTA PORTA.
  #
  # Aqui estavam as duas perguntas, uma a seguir a outra, e a primeira era o
  # amuleto: quem tivesse o Guia e nao tivesse o amuleto saia por ela sem
  # sequer ver a mensagem do Guia. O item que compraram para caçar sozinho nao
  # funcionava sem outro que nao lhes diz respeito.
  def entrar_automatica!
    unless AnilArena.automatica_livre?
      pbMessage(_INTL("Você precisa do Guia Mestre para mandá-lo caçar sozinho.")) rescue nil
      return false
    end
    if activa?
      pbMessage(_INTL("Você já está em batalha. Use /arena sair.")) rescue nil
      return false
    end
    meu = ($player.first_able_pokemon rescue nil)
    meu ||= ($player.party.compact.find { |p| !p.egg? && p.hp > 0 } rescue nil)
    unless meu
      pbMessage(_INTL("Você precisa de um Pokémon com vida.")) rescue nil
      return false
    end
    @auto    = true
    @directa = true      # e a mesma caça da directa: o mato vem ate nos
    @andado  = 0.0
    @passo_rx = nil
    limpar_spawns_do_mapa!
    # ⚠️ O QUE LUTA E O AJUDANTE, E ELE E O PRIMEIRO DA EQUIPA.
    #
    # Na directa o ajudante e o SEGUNDO Pokemon, porque o primeiro sou eu. Aqui
    # eu nao sou nenhum, portanto quem entra a lutar e o da frente.
    unless entrar!(meu, [])
      @auto = false
      @directa = false
      return false
    end
    unless chamar_aliado!(meu)
      pbMessage(_INTL("Não há espaço aqui para ele lutar.")) rescue nil
      sair!
      return false
    end
    pbMessage(AnilLanRework.ui_format(
      "{1} vai caçar sozinho!\nAnde à vontade: ele segue você e ataca o que aparecer.\n/arena sair para acabar.",
      meu.name)) rescue nil
    true
  rescue => e
    log("falha na batalha automatica: #{e.class}: #{e.message}")
    @auto = false
    @directa = false
    false
  end

  def entrar_directa!
    unless AnilArena.directa?
      pbMessage(_INTL("Você precisa do Amuleto Teste para lutar você mesmo.")) rescue nil
      return false
    end
    if activa?
      pbMessage(_INTL("Você já está em batalha. Use /arena sair.")) rescue nil
      return false
    end
    meu = ($player.first_able_pokemon rescue nil)
    meu ||= ($player.party.compact.find { |p| !p.egg? && p.hp > 0 } rescue nil)
    unless meu
      pbMessage(_INTL("Você precisa de um Pokémon com vida.")) rescue nil
      return false
    end
    @directa = true
    @andado = 0.0
    @passo_rx = nil
    limpar_spawns_do_mapa!
    ajudante = escolher_ajudante!(meu)
    unless entrar!(meu, [])
      @directa = false
      return false
    end
    chamar_aliado!(ajudante) if ajudante
    pbMessage(AnilLanRework.ui_format(
      "Batalha direta com {1}!\nAnde pelo mato: os selvagens vêm até você.\nA/S/D/Shift para golpes, Q para a bola, /arena sair para acabar.",
      meu.name)) rescue nil
    true
  rescue => e
    log("falha na batalha direta: #{e.class}: #{e.message}")
    false
  end

  #-----------------------------------------------------------------------------
  # A CACA
  #
  # ⚠️ OS SELVAGENS SAIEM DA TABELA DO MAPA, e nao de uma lista minha.
  #
  # Quem estiver na Rota 3 caca o que a Rota 3 tem, com os niveis da Rota 3.
  # O motor ja sabe responder a isso — e a mesma pergunta que ele faz quando se
  # anda na relva.
  #-----------------------------------------------------------------------------
  def cacar!(quantos = 4)
    unless AnilArena.directa?
      pbMessage(_INTL("Você precisa do Amuleto Teste para lutar você mesmo.")) rescue nil
      return false
    end
    return false unless $game_map && $game_player
    equipa = ($player.party.compact.select { |p| !p.egg? && p.hp > 0 } rescue [])
    if equipa.empty?
      pbMessage(_INTL("Você precisa de um Pokémon com vida.")) rescue nil
      return false
    end
    nomes = equipa.map { |p| "#{p.name} Nv.#{p.level}" }
    nomes << _INTL("Cancelar")
    escolha = pbMessage(_INTL("Quem entra na caçada?"), nomes, nomes.length)
    return false if escolha < 0 || escolha >= equipa.length

    tipo = ($PokemonEncounters.encounter_type rescue nil)
    tipo ||= :Land
    selvagens = []
    quantos = [[quantos.to_i, 1].max, MAX_BICHOS].min
    quantos.times do
      enc = ($PokemonEncounters.choose_wild_pokemon(tipo) rescue nil)
      next unless enc
      pk = (pbGenerateWildPokemon(enc[0], enc[1]) rescue nil)
      selvagens << pk if pk
    end
    if selvagens.empty?
      pbMessage(_INTL("Não há Pokémon selvagens por aqui.")) rescue nil
      return false
    end

    @caca = true
    unless entrar!(equipa[escolha], selvagens)
      @caca = false
      return false
    end
    pbMessage(AnilLanRework.ui_format(
      "Caçada: {1} selvagens!\nSetas para andar, A/S/D/Shift para golpes, Q para a bola.\n/arena sair para desistir.",
      selvagens.length.to_s)) rescue nil
    true
  rescue => e
    log("falha na caca: #{e.class}: #{e.message}")
    false
  end

  #-----------------------------------------------------------------------------
  # ARMADILHAS DE CHAO
  #
  # ⚠️ SPIKES NAO E UM GOLPE QUE ACERTA: E UM SITIO QUE PASSA A DOER.
  #
  # Estes golpes nao tem alvo — na batalha por turnos eles marcam o LADO do
  # campo adversario, e por isso o motor da-lhes um alvo que "afecta o lado
  # inimigo". E essa a bandeira que se le aqui, e nao uma lista de nomes: quem
  # acrescentar um golpe novo de campo ao PBS ganha a mecanica de graca.
  #
  # No mapa isso vira o que a palavra sempre quis dizer: fica ali, no chao, ate
  # alguem passar por cima. Larga-se duas casas a frente — poe-se onde se quer,
  # e e por isso que compensa pensar em posicao.
  #-----------------------------------------------------------------------------
  ARMADILHA_CASAS  = 2      # a quantas casas a frente cai
  ARMADILHA_VIDA   = 45.0   # segundos ate se desfazer sozinha
  ARMADILHA_FRACAO = 16.0   # "um pouco de vida": 1/16, o resto e o veneno
  ARMADILHA_PX     = 26.0   # mais pequena do que um golpe: e cenario, nao efeito

  def armadilha?(mv)
    dados = (GameData::Move.get(mv.id) rescue nil)
    return false unless dados
    alvo = (GameData::Target.get(dados.target) rescue nil)
    return false unless alvo
    (alvo.affects_foe_side rescue false) ? true : false
  rescue
    false
  end

  #-----------------------------------------------------------------------------
  # O CHAFARIZ
  #
  # ⚠️ UMA ARMADILHA NUMA CASA SO NAO E UMA ARMADILHA.
  #
  # As Púas Tóxicas caiam numa unica casa, duas a frente. Isso nao e uma
  # armadilha — e um alvo. Bastava andar ao lado. Numa batalha por turnos o
  # golpe cobre o LADO inteiro do adversario; a traducao honesta disso para um
  # campo aberto nao e um ponto, e uma AREA negada.
  #
  # Entao ele espalha: de 4 a 6 espinhos saltam de quem o lancou, cada um por
  # cima do seu proprio arco, e cada um cai na sua casa. O que fica no chao e
  # uma mancha por onde nao se anda a vontade — e e isso que muda a maneira de
  # se andar na luta, que era o ponto todo.
  #
  # Os espinhos VOAM antes de assentar. Se aparecessem ja no chao, nao se veria
  # de onde vieram nem se perceberia que foi um golpe; o arco e o que liga a
  # causa ao efeito.
  #-----------------------------------------------------------------------------
  CHAFARIZ_MIN    = 4      # quantos espinhos, no minimo
  CHAFARIZ_MAX    = 6      # e no maximo
  CHAFARIZ_PERTO  = 1.0    # casas: o mais perto que um cai
  CHAFARIZ_LONGE  = 3.0    # casas: o mais longe
  CHAFARIZ_VOO    = 0.42   # segundos no ar
  CHAFARIZ_ALTURA = 40.0   # pixeis do ponto mais alto do arco

  def sementes; (@sementes ||= []); end

  # ⚠️ O SORTEIO SO PODE ACONTECER NUMA DAS MAQUINAS.
  #
  # As casas sao escolhidas ao acaso. Se cada lado sorteasse as suas, os dois
  # jogadores veriam manchas de espinhos DIFERENTES no mesmo chao — e como quem
  # decide se pisou uma armadilha e a vitima, o adversario levaria dano de
  # espinhos que na tela dele nao estavam ali.
  #
  # Sorteia quem lanca; o outro recebe a lista pronta e so a replica. Por isso
  # este metodo devolve as casas, e tambem sabe aceita-las de fora.
  def semear_armadilhas!(mv, nome, anim, dona_minha, ox = nil, oy = nil, casas = nil)
    return [] unless $game_player && $game_map
    ox ||= $game_player.x
    oy ||= $game_player.y
    escolhidas = []

    if casas.is_a?(Array) && !casas.empty?
      # Veio de fora: nao se sorteia nada, replica-se.
      casas.each { |c| escolhidas << [c[0].to_i, c[1].to_i] }
    else
      quantos = CHAFARIZ_MIN + rand(CHAFARIZ_MAX - CHAFARIZ_MIN + 1)
      # Um angulo de partida ao acaso para que dois lancamentos seguidos nao
      # desenhem a mesma estrela no chao.
      base = rand * 2 * Math::PI
      quantos.times do |i|
        ang = base + (i * 2 * Math::PI / quantos) + ((rand - 0.5) * 0.6)
        raio = CHAFARIZ_PERTO + (rand * (CHAFARIZ_LONGE - CHAFARIZ_PERTO))
        tx = (ox + (Math.cos(ang) * raio)).round
        ty = (oy + (Math.sin(ang) * raio)).round
        next unless ($game_map.valid?(tx, ty) rescue false)
        next if fora_do_campo?(tx, ty)
        # Duas na mesma casa e um espinho desperdicado.
        next if escolhidas.include?([tx, ty])
        next if sementes.any? { |g| g[:tx] == tx && g[:ty] == ty }
        next if (@armadilhas || []).any? { |a| a[:x] == tx && a[:y] == ty }
        escolhidas << [tx, ty]
      end
    end

    escolhidas.each do |(tx, ty)|
      sementes << { :ox => ox, :oy => oy, :tx => tx, :ty => ty, :t => 0.0,
                    :mv => mv, :nome => nome.to_s, :anim => anim.to_i,
                    :minha => (dona_minha ? true : false), :sp => nil }
    end

    # Se nao coube nenhum (encostado a uma arvore, num canto), poe-se ao menos um
    # a frente — um golpe que nao faz nada nenhum e pior do que um golpe fraco.
    if escolhidas.empty?
      cx, cy = casa_a_frente(ARMADILHA_CASAS)
      por_armadilha!(mv, nome, anim, dona_minha, cx, cy, true)
    end
    dizer(dona_minha ? "#{nome}!" : nome.to_s)
    (pbSEPlay("Battle throw") rescue nil)
    registar("chafariz de #{mv ? mv.id : '?'}: #{escolhidas.length} espinho(s) no ar")
    escolhidas
  rescue => e
    registar("falha no chafariz: #{e.class}: #{e.message}")
    []
  end

  def correr_sementes!
    return if sementes.empty?
    dt = [(@delta || (1.0 / 60.0)), 0.1].min
    caidas = []
    sementes.each do |g|
      g[:t] += dt
      if g[:t] >= CHAFARIZ_VOO
        caidas << g
        next
      end
      k = g[:t] / CHAFARIZ_VOO
      # A posicao anda em linha recta; a ALTURA e que faz o arco. Uma parabola
      # simples: zero no inicio, zero no fim, maxima a meio.
      cx = g[:ox] + ((g[:tx] - g[:ox]) * k)
      cy = g[:oy] + ((g[:ty] - g[:oy]) * k)
      subida = (4.0 * k * (1.0 - k)) * CHAFARIZ_ALTURA
      unless g[:sp]
        cart = cartao_do_projectil(g[:anim], true, nil)
        if cart
          sp = Sprite.new(viewport_das_animacoes)
          sp.bitmap = cart[:bmp]
          aplicar_passo!(sp, cart, cart[:passos][0])
          escala = ARMADILHA_PX / [cart[:passos][0][:cx][2], cart[:passos][0][:cx][3]].max.to_f
          sp.zoom_x = escala
          sp.zoom_y = escala
          sp.oy = cart[:passos][0][:cx][3]
          g[:sp] = sp
        end
      end
      sp = g[:sp]
      next unless sp && !(sp.disposed? rescue true)
      sp.x = ((cx * Game_Map::REAL_RES_X - $game_map.display_x) / Game_Map::X_SUBPIXELS).round +
             (Game_Map::TILE_WIDTH / 2)
      sp.y = ((cy * Game_Map::REAL_RES_Y - $game_map.display_y) / Game_Map::Y_SUBPIXELS).round +
             Game_Map::TILE_HEIGHT - subida.round
      # Roda enquanto voa: um espinho a girar le-se como atirado, e nao como
      # arrastado.
      (sp.angle = (k * 540.0) % 360.0) rescue nil
    end
    caidas.each do |g|
      (g[:sp].dispose rescue nil) if g[:sp] && !(g[:sp].disposed? rescue true)
      sementes.delete(g)
      # Caladas: quem fala e o `semear_armadilhas!`, uma vez so. Seis mensagens
      # iguais seguidas enchiam o painel e escondiam o resto da luta.
      por_armadilha!(g[:mv], g[:nome], g[:anim], g[:minha], g[:tx], g[:ty], true)
      # Uma semente vinda da rede nao traz o objecto do golpe, so o id dele — e
      # e o id que decide se aquilo enverena ou so espeta.
      if g[:move_id] && @armadilhas && @armadilhas.last
        @armadilhas.last[:move_id] = g[:move_id]
      end
    end
  rescue => e
    registar("falha a semear: #{e.class}: #{e.message}")
  end

  def limpar_sementes!
    sementes.each { |g| (g[:sp].dispose rescue nil) if g[:sp] && !(g[:sp].disposed? rescue true) }
    @sementes = []
  rescue
    @sementes = []
  end

  def por_armadilha!(mv, nome, anim, dona_minha, x = nil, y = nil, calado = false)
    if x.nil?
      x, y = casa_a_frente(ARMADILHA_CASAS)
    end
    cart = cartao_do_projectil(anim.to_i, false, nil)
    sp = nil
    if cart
      sp = Sprite.new(viewport_das_animacoes)
      sp.bitmap = cart[:bmp]
      aplicar_passo!(sp, cart, cart[:passos][0])
      # ⚠️ A armadilha e do CHAO: encolhe-se e ancora-se pelos pes, senao ficava
      # a pairar a meia casa de altura como se fosse um golpe a voar.
      escala = ARMADILHA_PX / [cart[:passos][0][:cx][2], cart[:passos][0][:cx][3]].max.to_f
      sp.zoom_x = escala
      sp.zoom_y = escala
      sp.oy = cart[:passos][0][:cx][3]
      sp.opacity = 220
    end
    (@armadilhas ||= []) << {
      :x => x, :y => y, :move_id => mv ? mv.id : nil, :mv => mv, :anim => anim.to_i,
      :nome => nome.to_s, :minha => (dona_minha ? true : false),
      :ate => Time.now.to_f + ARMADILHA_VIDA, :sp => sp, :cartao => cart
    }
    posicionar_armadilhas!
    dizer(dona_minha ? "#{nome} no chão!" : nome.to_s) unless calado
    registar("armadilha #{mv ? mv.id : '?'} em (#{x},#{y}) minha=#{dona_minha}")
  rescue => e
    registar("falha a por armadilha: #{e.class}: #{e.message}")
  end

  # As armadilhas estao paradas no MAPA, e o mapa desliza: a posicao no ecra tem
  # de ser recalculada a cada passo, senao elas andavam com a camara.
  def posicionar_armadilhas!
    (@armadilhas || []).each do |a|
      sp = a[:sp]
      next unless sp && !(sp.disposed? rescue true)
      sp.x = ((a[:x] * Game_Map::REAL_RES_X - $game_map.display_x) / Game_Map::X_SUBPIXELS).round +
             (Game_Map::TILE_WIDTH / 2)
      sp.y = ((a[:y] * Game_Map::REAL_RES_Y - $game_map.display_y) / Game_Map::Y_SUBPIXELS).round +
             Game_Map::TILE_HEIGHT
    end
  rescue
    nil
  end

  # ⚠️ A ANIMACAO DE SEMEAR CONTA UMA COISA QUE JA ACONTECEU.
  #
  # Ao pisar uma armadilha tocava-se a animacao do golpe outra vez — e a do
  # Toxic Spike e um chafariz que atira TRES espinhos. Quem pisa um espinho ve
  # nascerem mais tres, o que nao e o que aconteceu e engana sobre o estado do
  # chao.
  #
  # Num golpe que so poe estado, o efeito ja tem quem o mostre: o sinal do
  # veneno sobe da cabeca de quem pisou. Nao ha nada a acrescentar.
  #
  # Num que faz DANO a serio (Stealth Rock e afins) a animacao ainda vale — ali
  # ela le-se como "levaste", e nao como "nasceram mais".
  def armadilha_muda?(move_id)
    return false unless move_id
    dados = (GameData::Move.get(move_id) rescue nil)
    return false unless dados
    dados.category == 2 || dados.power.to_i <= 0
  rescue
    false
  end

  def correr_armadilhas!
    return if @armadilhas.nil? || @armadilhas.empty?
    posicionar_armadilhas!
    agora = Time.now.to_f
    fora = []
    ev = evento_inimigo
    @armadilhas.each do |a|
      if agora >= a[:ate].to_f
        fora << a
        next
      end
      if a[:minha]
        # A minha arma o inimigo; contra outro jogador quem decide e ele, por
        # isso a minha copia so espera que ele proprio anuncie o estrago.
        next if pvp?
        pisou = bichos_vivos.find { |b| b[:ev] && b[:ev].x == a[:x] && b[:ev].y == a[:y] }
        next unless pisou
        d = [(pisou[:hp_max] / ARMADILHA_FRACAO).round, 1].max
        if a[:anim] > 0 && !armadilha_muda?(a[:move_id])
          tocar_no_chao!(a[:anim], a[:x], a[:y])
        end
        narrar("#{a[:nome]}! -#{d}")
        aplicar_estado_no_bicho!(pisou, a[:move_id]) if a[:move_id]
        ferir_bicho!(pisou, d)
        fora << a
      else
        next unless $game_player.x == a[:x] && $game_player.y == a[:y]
        d = mordida_da_armadilha(a, (@meu.totalhp rescue 100))
        @hp_meu = [@hp_meu - d, 0].max
        talvez_aplicar_estado!(a[:move_id]) if a[:move_id]
        if a[:anim] > 0 && !armadilha_muda?(a[:move_id])
          tocar_no_chao!(a[:anim], a[:x], a[:y])
        end
        dizer("Pisou #{a[:nome]}! -#{d}")
        if pvp?
          enviar!("arena_dano", "dano" => d, "hp" => @hp_meu, "hp_max" => (@meu.totalhp.to_i rescue 1))
        end
        if @hp_meu <= 0
          enviar!("arena_fim", "perdi" => true) if pvp?
          sair!
          pbMessage(_INTL("Seu Pokémon foi derrotado na arena.")) rescue nil
        end
        fora << a
      end
    end
    return if fora.empty?
    @armadilhas -= fora
    fora.each { |a| (a[:sp].dispose rescue nil) if a[:sp] }
  rescue => e
    registar("falha nas armadilhas: #{e.class}: #{e.message}")
    limpar_armadilhas!
  end

  # Spikes e companhia nao tem forca nenhuma: o estrago e uma fatia da vida,
  # como na batalha por turnos.
  def mordida_da_armadilha(a, total)
    dados = (GameData::Move.get(a[:move_id]) rescue nil)
    if dados && dados.power.to_i > 0 && a[:mv]
      return dano(@meu, @inimigo, a[:mv]) if a[:minha]
    end
    [(total / ARMADILHA_FRACAO).round, 1].max
  rescue
    1
  end

  def limpar_armadilhas!
    (@armadilhas || []).each { |a| (a[:sp].dispose rescue nil) if a[:sp] }
    @armadilhas = []
  rescue
    @armadilhas = []
  end

  #-----------------------------------------------------------------------------
  # MOVIMENTO LIVRE
  #
  # ⚠️ ANDAR SEM CASAS NAO E ANDAR DEPRESSA ENTRE CASAS.
  #
  # Da primeira vez eu subi o `move_speed` e disse que estava feito. Nao estava:
  # o motor continuava a mover de casa em casa, so que mais depressa, e ficou
  # exactamente o que o jogador nao queria — o mesmo salto quadrado, agora
  # nervoso. E tambem foi por ai que os Pokemon ficaram rapidos de mais: um
  # move_speed de 4,4 sao dez casas e meia por segundo, mais do que a corrida do
  # jogo.
  #
  # O movimento a serio ignora a grelha. A posicao verdadeira de um personagem e
  # o `@real_x`/`@real_y`, em 128 unidades por casa; o `@x`/`@y` e so a casa em
  # que ele calha estar. Aqui escreve-se directamente na posicao verdadeira, com
  # a velocidade em casas por segundo e o tempo real do relogio, e o `@x`/`@y`
  # vai atras, arredondado, para o resto do jogo (colisao, eventos, os outros
  # jogadores) continuar a ver um Pokemon numa casa.
  #
  # Fica de graca o que faltava: diagonais, e parar a meio de uma casa.
  #-----------------------------------------------------------------------------
  # ⚠️ A JANELA ERA ESTREITA DE MAIS PARA SE NOTAR.
  #
  # Estava a espalhar todos os Pokemon entre 3,2 e 5,5 casas por segundo a
  # partir de uma Speed de 20 a 200 — so que na pratica quase toda a gente tem
  # entre 60 e 130, e portanto quase toda a gente andava a 3,9. Com a janela
  # apertada nos valores que existem mesmo, um Jolteon passa a andar ao dobro de
  # um Snorlax, que e o que a Speed devia querer dizer.
  VEL_MIN    = 2.6    # casas por segundo (a andar do jogo sao 4)
  VEL_MAX    = 6.8    # (a correr do jogo sao 8)
  VEL_DASH   = 2.2    # somado enquanto se corre
  PASSO_ANIM = 0.13   # segundos por quadro das pernas

  def velocidade_livre(pkmn)
    v = (pkmn.speed.to_i rescue 100)
    v = [[v, 40].max, 250].min
    base = VEL_MIN + (((v - 40) / 210.0) * (VEL_MAX - VEL_MIN))
    # Um Agility no mapa e literalmente andar mais depressa.
    # E um Choice Scarf tambem: aqui a velocidade nao decide ordem nenhuma, decide
    # quantas casas por segundo o boneco anda — que e a leitura mais honesta que
    # o item pode ter num jogo sem turnos.
    base * [buff_de(pkmn, :spd), 2.0].min *
      (AnilArenaItens.factor_de_velocidade(pkmn) rescue 1.0)
  rescue
    VEL_MIN
  end

  def mover_livre!
    return unless @activa && $game_player && $game_map
    return if @derrota_ate  # a queda tem o seu tempo
    return if caido?        # e quem esta caido esta caido
    return if @investida    # a investida manda enquanto durar
    return if impedido?
    dt = [(@delta || (1.0 / 60.0)), 0.1].min
    dx = 0.0
    dy = 0.0
    dx -= 1.0 if (Input.anil_arena_orig_press?(Input::LEFT) rescue false)
    dx += 1.0 if (Input.anil_arena_orig_press?(Input::RIGHT) rescue false)
    dy -= 1.0 if (Input.anil_arena_orig_press?(Input::UP) rescue false)
    dy += 1.0 if (Input.anil_arena_orig_press?(Input::DOWN) rescue false)
    return if dx == 0.0 && dy == 0.0
    # Uma diagonal nao pode andar mais do que uma recta: normaliza-se.
    n = Math.sqrt((dx * dx) + (dy * dy))
    dx /= n
    dy /= n
    # O boneco olha para a componente que manda — e nunca por `turn_generic`,
    # que dispara os avisos de encontro e os eventos do mapa.
    nova = (dx.abs > dy.abs) ? ((dx > 0) ? 6 : 4) : ((dy > 0) ? 2 : 8)
    ($game_player.instance_variable_set(:@direction, nova) rescue nil)
    passo = velocidade_actual * Game_Map::REAL_RES_X * dt
    andar_em!(dx * passo, dy * passo)
    animar_boneco!
  rescue => e
    registar("falha no movimento livre: #{e.class}: #{e.message}")
  end

  # ⚠️ UM EIXO DE CADA VEZ.
  #
  # Testar os dois juntos fazia colar a uma parede em diagonal: o passo inteiro
  # era recusado e o Pokemon parava, quando o natural e deslizar ao longo dela.
  # Separando, o eixo bloqueado perde-se e o outro anda.
  def andar_em!(px, py)
    gp = $game_player
    rx = (gp.instance_variable_get(:@real_x) rescue 0).to_f
    ry = (gp.instance_variable_get(:@real_y) rescue 0).to_f
    nx = rx + px
    rx = nx if casa_livre_para?(nx, ry)
    ny = ry + py
    ry = ny if casa_livre_para?(rx, ny)
    gp.instance_variable_set(:@real_x, rx)
    gp.instance_variable_set(:@real_y, ry)
    gp.instance_variable_set(:@x, (rx / Game_Map::REAL_RES_X.to_f).round)
    gp.instance_variable_set(:@y, (ry / Game_Map::REAL_RES_Y.to_f).round)
    (gp.calculate_bush_depth rescue nil)
    seguir_camara!(rx, ry)
  rescue
    nil
  end

  # O Pokemon que se controla obedece as mesmas regras dos outros: a direccao
  # zero nao serve (ver a nota do `casa_livre_para_evento?`), e agua e desniveis
  # sao parede para ele tambem — ele esta a lutar, nao a surfar.
  # ⚠️ O `passable?` PERGUNTA-SE SOBRE A CASA DE ONDE SE SAI, E NAO A DE CHEGADA.
  #
  # Esta e a raiz de "a colisao esta pessima". O metodo do motor e
  # `passable?(x, y, d)` e faz esta conta la dentro:
  #
  #     new_x = x + (d == 6 ? 1 : d == 4 ? -1 : 0)
  #     ... confere (x,y) E (new_x,new_y)
  #
  # Ou seja: recebe a casa ONDE SE ESTA e a direccao do passo. Eu passava-lhe a
  # casa de DESTINO — portanto ele conferia o destino e a casa a SEGUIR ao
  # destino. A colisao ficava adiantada uma casa inteira no sentido da marcha:
  # parava-se uma casa antes das paredes, nao se entrava em vaos de uma casa, e
  # nao se chegava aos itens encostados a pedra.
  #
  # Com a casa certa, isto passa a ser exactamente a fisica do personagem a
  # andar — que e o que se pediu, e sem inventar nada: e a mesma chamada que o
  # motor faz a cada passo do jogo normal.
  # ⚠️ A REGRA DA AGUA ERA DOS BICHOS, E APANHOU O JOGADOR.
  #
  # A nota do `TERRENO_PAREDE` diz o que a regra e: "um Pokemon da arena nao e o
  # jogador: nao surfa e nao salta desniveis". Certo — so que eu pus a regra num
  # sitio por onde o JOGADOR tambem passa. A partir do momento em que ele esta
  # em cima da agua, todas as casas a volta dele sao agua, todas dao proibidas, e
  # ele fica preso em cima do Lapras sem conseguir mexer um pixel. E exactamente
  # o "os personagens ficam travados".
  #
  # A quem surfa, a agua nao e parede — e o chao. E quem sabe isso e o
  # `Game_Player#passable?`, que ja conhece o estado de surf e ja e consultado
  # duas linhas abaixo. Portanto a surfar nao se pergunta a etiqueta do terreno:
  # deixa-se a decisao a quem tem a informacao toda.
  # ⚠️ E MELHOR PERGUNTAR AO CHAO DO QUE A BANDEIRA.
  #
  # O `$PokemonGlobal.surfing` e a resposta certa — quando esta certa. Mas ha
  # plugins nesta base que mexem no estado do surf, e uma bandeira que alguem
  # esquece de por deixa isto tudo a responder "terra" com o boneco em cima da
  # agua. Nao vale a pena depender disso quando ha uma fonte que nao mente: a
  # casa onde o jogador esta.
  #
  # Se ele esta numa casa de agua, esta na agua. Nao ha estado nenhum que possa
  # contradizer isso.
  def a_surfar?
    return true if ($PokemonGlobal.surfing rescue false)
    return true if ($PokemonGlobal.diving rescue false)
    return true if $game_player && agua?($game_player.x, $game_player.y)
    false
  rescue
    false
  end

  def casa_livre_para?(rx, ry)
    tx = (rx / Game_Map::REAL_RES_X.to_f).round
    ty = (ry / Game_Map::REAL_RES_Y.to_f).round
    return true if tx == $game_player.x && ty == $game_player.y
    return false if !a_surfar? && terreno_proibido?(tx, ty)
    d = rumo_do_passo($game_player, tx, ty)
    return false unless ($game_player.passable?($game_player.x, $game_player.y, d) rescue false)
    return false if fora_do_campo?(tx, ty)
    # Tambem nao se anda por cima de um selvagem: eles tem corpo.
    corpo_livre?($game_player, rx, ry)
  rescue
    false
  end

  # ⚠️ A CAMARA TEM DE SER EMPURRADA A MAO.
  #
  # O `update_screen_position` do motor so mexe o ecra quando o personagem
  # "andou" pelas contas dele — e nos passos livres nao andou. Sem isto o
  # Pokemon saia do ecra e o mapa ficava parado.
  def seguir_camara!(rx, ry)
    ($game_map.display_x = rx - Game_Player::SCREEN_CENTER_X) rescue nil
    ($game_map.display_y = ry - Game_Player::SCREEN_CENTER_Y) rescue nil
  rescue
    nil
  end

  # As pernas tambem sao nossas: o `update_pattern` do motor so avanca o quadro
  # a quem esta a dar um passo de casa em casa, e aqui nao ha passos desses.
  def animar_boneco!
    agora = Time.now.to_f
    return if (agora - @passo_relogio.to_f) < PASSO_ANIM
    @passo_relogio = agora
    gp = $game_player
    pat = (((gp.pattern rescue 0).to_i + 1) % 4)
    (gp.instance_variable_set(:@pattern, pat) rescue nil)
  rescue
    nil
  end

  # Ao sair, encaixa-se na casa mais proxima: um jogador a meio de uma casa e um
  # save que o motor nao sabe ler de volta.
  def encaixar_na_casa!
    gp = $game_player
    return unless gp
    tx = ((gp.instance_variable_get(:@real_x) rescue 0).to_f / Game_Map::REAL_RES_X).round
    ty = ((gp.instance_variable_get(:@real_y) rescue 0).to_f / Game_Map::REAL_RES_Y).round
    (gp.moveto(tx, ty) rescue nil)
    (gp.instance_variable_set(:@move_timer, nil) rescue nil)
  rescue
    nil
  end

  #-----------------------------------------------------------------------------
  # O CLONE (Double Team)
  #
  # ⚠️ NUMA BATALHA POR TURNOS O DOUBLE TEAM E UM NUMERO — AQUI PODE SER UM CORPO.
  #
  # Por turnos ele sobe a evasao: uma probabilidade invisivel que o jogador so
  # sente ao fim de tres falhas seguidas. No mapa ha uma leitura melhor e
  # literal: aparece OUTRO igual a nos, ao lado. O proximo golpe que nos ia
  # atingir atinge-o a ele, e ele desfaz-se — um golpe comido, visivel, sem
  # sorteio nenhum.
  #
  # Ele nao anda nem ataca: e uma imagem. E por isso que nao entra na lista de
  # bichos nem tem ficha — o unico estado dele e "existe" ou "nao existe".
  CLONE_VIDA = 20.0     # segundos ate se desfazer sozinho

  def clone?(mv)
    fc = (GameData::Move.get(mv.id).function_code.to_s rescue "")
    fc.include?("RaiseUserEvasion") || fc.include?("DoubleTeam")
  rescue
    false
  end

  def criar_clone!
    apagar_clone!
    return false unless $game_map && $game_player
    x, y = casa_livre_perto($game_player.x, $game_player.y, 2)
    return false unless x
    nome = (@charset.to_s.empty? ? ($game_player.character_name.to_s rescue "") : @charset.to_s)
    return false if nome.empty?
    bmp = (RPG::Cache.character(nome, 0) rescue nil)
    return false unless bmp && !(bmp.disposed? rescue true)
    sp = Sprite.new(viewport_do_chao)
    sp.bitmap = bmp     # da cache: nunca se deita fora
    cw = bmp.width / 4
    ch = bmp.height / 4
    sp.src_rect.set(0, ((($game_player.direction rescue 2) / 2) - 1) * ch, cw, ch)
    sp.ox = cw / 2
    sp.oy = ch
    sp.opacity = 190
    @clone = { :x => x, :y => y, :sp => sp, :ate => Time.now.to_f + CLONE_VIDA }
    posicionar_clone!
    dizer(_INTL("Um clone apareceu!"))
    true
  rescue => e
    registar("falha no clone: #{e.class}: #{e.message}")
    false
  end

  def posicionar_clone!
    return unless @clone && @clone[:sp] && !(@clone[:sp].disposed? rescue true)
    sp = @clone[:sp]
    sp.x = ((@clone[:x] * Game_Map::REAL_RES_X - $game_map.display_x) / Game_Map::X_SUBPIXELS).round +
           (Game_Map::TILE_WIDTH / 2)
    sp.y = ((@clone[:y] * Game_Map::REAL_RES_Y - $game_map.display_y) / Game_Map::Y_SUBPIXELS).round +
           Game_Map::TILE_HEIGHT
    (sp.z = sp.y) rescue nil
  rescue
    nil
  end

  def correr_clone!
    return unless @clone
    posicionar_clone!
    apagar_clone! if Time.now.to_f >= @clone[:ate].to_f
  rescue
    nil
  end

  def apagar_clone!
    return unless @clone
    (@clone[:sp].dispose rescue nil) if @clone[:sp] && !(@clone[:sp].disposed? rescue true)
    @clone = nil
  rescue
    @clone = nil
  end

  # ⚠️ O CLONE E CONFERIDO ANTES DO ESCUDO E ANTES DA VIDA.
  #
  # Ele existe para comer um golpe inteiro: se o dano chegasse a passar por ele,
  # ele nao seria um clone, seria uma decoracao.
  def clone_comeu?(quem_atacou = nil)
    return false unless @clone
    tocar_no_chao!(0, @clone[:x], @clone[:y])
    piscar = @clone[:sp]
    dizer(_INTL("O clone se desfez!"))
    (pbSEPlay("Battle recall") rescue nil)
    apagar_clone!
    true
  rescue
    apagar_clone!
    true
  end

  #-----------------------------------------------------------------------------
  # A INVESTIDA
  #
  # ⚠️ "MAIS VELOCIDADE" NAO SE VE. UM SALTO DE CINCO CASAS VE-SE.
  #
  # O Agility subia o atributo e mais nada: andar 1,5x mais depressa e uma coisa
  # que so se nota com um cronometro na mao, e o jogador reparou nisso logo.
  # Enquanto o buff de velocidade durar, o duplo-toque deixa de ser corrida e
  # passa a ser um salto — cinco casas de uma vez, com o boneco a brilhar e a
  # deixar copias de si pelo caminho.
  #
  # ⚠️ Ele PARA na primeira parede, e nao a atravessa.
  #
  # Testa-se casa a casa e conta-se so as que passam: um salto que atravessasse
  # paredes seria a maneira mais rapida de sair do mapa e ficar preso dentro de
  # uma montanha.
  INVESTIDA_CASAS   = 5
  INVESTIDA_CUSTO   = 32.0    # energia
  INVESTIDA_ESPERA  = 0.7     # segundos entre saltos
  FANTASMA_FRAMES   = 22

  def pode_investir?
    buff_de(@meu, :spd) > 1.0
  rescue
    false
  end

  # ⚠️ SALTAR NAO E CHEGAR: E ATRAVESSAR DEPRESSA.
  #
  # A primeira versao punha o boneco cinco casas a frente num frame e espalhava
  # as copias pelo caminho. Como o boneco chegava primeiro, as copias apareciam
  # A FRENTE dele — e o que se via era um teletransporte com uns fantasmas ao
  # lado, exactamente como o jogador descreveu.
  #
  # Agora e movimento a serio, so que muito rapido: a distancia inteira em 0,16
  # segundos, com a posicao a ser escrita a cada frame como no andar normal. As
  # copias nascem onde ele JA passou, portanto ficam atras. E como e movimento,
  # ele pode ser travado a meio por uma parede que apareca.
  INVESTIDA_TEMPO   = 0.16   # segundos para percorrer tudo
  FANTASMA_CADENCIA = 0.025  # segundos entre copias

  def investida!
    return false unless pode_investir?
    agora = Time.now.to_f
    return false if agora < @investida_pronta.to_f
    return false if @investida
    return false if energia < INVESTIDA_CUSTO
    gp = $game_player
    ux, uy = case (gp.direction rescue 2)
             when 2 then [0.0, 1.0]
             when 8 then [0.0, -1.0]
             when 4 then [-1.0, 0.0]
             else        [1.0, 0.0]
             end
    # Quantas casas cabem mesmo antes de uma parede.
    rx = (gp.instance_variable_get(:@real_x) rescue 0).to_f
    ry = (gp.instance_variable_get(:@real_y) rescue 0).to_f
    passos = 0
    tx = rx
    ty = ry
    INVESTIDA_CASAS.times do
      nx = tx + (ux * Game_Map::REAL_RES_X)
      ny = ty + (uy * Game_Map::REAL_RES_Y)
      break unless casa_livre_para?(nx, ny)
      tx = nx
      ty = ny
      passos += 1
    end
    return false if passos.zero?

    self.energia = energia - INVESTIDA_CUSTO
    @investida_pronta = agora + INVESTIDA_ESPERA
    distancia = passos * Game_Map::REAL_RES_X.to_f
    @investida = { :ux => ux, :uy => uy, :restante => distancia,
                   :vel => (distancia / INVESTIDA_TEMPO), :fantasma => 0.0 }
    piscar_cor!(gp, 200, 240, 255, 16)
    (pbSEPlay("Battle recall") rescue nil)
    dizer(_INTL("Investida!"))
    true
  rescue => e
    registar("falha na investida: #{e.class}: #{e.message}")
    false
  end

  def correr_investida!
    return unless @investida
    gp = $game_player
    return (@investida = nil) unless gp
    dt = [(@delta || (1.0 / 60.0)), 0.1].min
    passo = @investida[:vel] * dt
    passo = @investida[:restante] if passo > @investida[:restante]
    rx = (gp.instance_variable_get(:@real_x) rescue 0).to_f
    ry = (gp.instance_variable_get(:@real_y) rescue 0).to_f
    nx = rx + (@investida[:ux] * passo)
    ny = ry + (@investida[:uy] * passo)
    # Uma parede que apareca a meio trava a investida onde ela esta.
    unless casa_livre_para?(nx, ny)
      @investida = nil
      return
    end
    gp.instance_variable_set(:@real_x, nx)
    gp.instance_variable_set(:@real_y, ny)
    gp.instance_variable_set(:@x, (nx / Game_Map::REAL_RES_X.to_f).round)
    gp.instance_variable_set(:@y, (ny / Game_Map::REAL_RES_Y.to_f).round)
    (gp.calculate_bush_depth rescue nil)
    seguir_camara!(nx, ny)

    @investida[:fantasma] += dt
    if @investida[:fantasma] >= FANTASMA_CADENCIA
      @investida[:fantasma] = 0.0
      fantasma!(rx, ry, 0)     # onde ele ESTAVA, nao onde vai
    end

    @investida[:restante] -= passo
    @investida = nil if @investida[:restante] <= 0.0
  rescue
    @investida = nil
  end

  # Uma copia do boneco deixada para tras, a apagar. Sao elas que dao a sensacao
  # de velocidade — o salto em si acontece num frame e sem isto nem se via.
  def fantasma!(rx, ry, ordem)
    gp = $game_player
    nome = (gp.character_name.to_s rescue "")
    return if nome.empty?
    bmp = (RPG::Cache.character(nome, (gp.character_hue.to_i rescue 0)) rescue nil)
    return unless bmp && !(bmp.disposed? rescue true)
    cw = bmp.width / 4
    ch = bmp.height / 4
    sp = Sprite.new(viewport_das_animacoes)
    sp.bitmap = bmp     # da cache: nunca se deita fora
    sp.src_rect.set(((gp.pattern rescue 0) % 4) * cw,
                    ((((gp.direction rescue 2) / 2) - 1) % 4) * ch, cw, ch)
    sp.ox = cw / 2
    sp.oy = ch
    sp.x = ((rx - $game_map.display_x) / Game_Map::X_SUBPIXELS).round + (Game_Map::TILE_WIDTH / 2)
    sp.y = ((ry - $game_map.display_y) / Game_Map::Y_SUBPIXELS).round + Game_Map::TILE_HEIGHT
    # Achatadas na direccao do movimento: e o "espremer" de quem vai depressa.
    sp.zoom_x = 0.85
    sp.zoom_y = 1.15
    sp.opacity = 190
    (sp.color.set(180, 230, 255, 90) rescue nil)
    # ⚠️ O RASTO MARCA UM SITIO POR ONDE SE PASSOU, LOGO TEM DE FICAR LA.
    #
    # Nasce com a posicao do ecra certa, mas a camara anda logo a seguir — e o
    # rasto vinha atras, colado ao ecra, a apontar para onde ja nao se passou.
    # Guardam-se as coordenadas do MAPA e refaz-se o ecra a cada frame, como se
    # faz com os corpos. O deslocamento e zero: um rasto nao salta.
    (@desmaios ||= []) << { :sp => sp, :y0 => sp.y, :rx => rx.to_f, :ry => ry.to_f,
                            :fx => 0.0, :fy => 0.0,
                            :ate => (Graphics.frame_count rescue 0) + FANTASMA_FRAMES,
                            :fantasma => true }
  rescue
    nil
  end

  def botao_da_direccao(dir)
    case dir
    when 2 then Input::DOWN
    when 8 then Input::UP
    when 4 then Input::LEFT
    else        Input::RIGHT
    end
  rescue
    Input::DOWN
  end

  def velocidade_base
    @vel_livre || VEL_MIN
  end

  # Em casas por segundo. Paralisado anda mais devagar; a correr, mais depressa.
  def velocidade_actual
    v = velocidade_base
    v += VEL_DASH if @a_correr
    [v, 1.0].max
  end

  #-- segurar golpes -----------------------------------------------------------
  def seguravel(mv)
    return nil unless mv && mv.id
    id = mv.id.to_s.upcase.to_sym
    return :escudo  if ESCUDOS.include?(id)
    return :rodopio if RODOPIOS.include?(id)
    return :espelho if ESPELHOS.include?(id)
    return :feixe   if FEIXES.include?(id)
    nil
  rescue
    nil
  end

  # ⚠️ SEGURAR PARA SEMPRE NAO E UMA ESCOLHA — E UM BOTAO ENCOSTADO.
  #
  # Sem limite, a resposta certa era sempre deixar o dedo no escudo. Um segundo
  # e o suficiente para aparar um golpe que se viu chegar, e curto de mais para
  # se viver atras dele. Passado esse segundo o golpe fecha-se sozinho e so
  # volta depois de a tecla ser LARGADA — senao bastava nao tirar o dedo.
  SEGURAR_MAX = 1.0

  def correr_segurar!
    @a_segurar = nil
    return if automatica?
    return if impedido?
    algum = false
    TECLAS.each_with_index do |(tecla, rotulo), i|
      botao = (Input.const_get(tecla) rescue nil)
      next unless botao
      next unless (Input.anil_arena_orig_press?(botao) rescue false)
      algum = true
      mv = (@meu.moves[i] rescue nil)
      modo = seguravel(mv)
      next unless modo
      # ⚠️ O FEIXE NAO OLHAVA PARA A RECARGA, E ERA O UNICO QUE NAO OLHAVA.
      #
      # A recarga e conferida no `usar_golpe!`, que e por onde passam os golpes
      # de TOQUE. Um feixe nao passa por la enquanto esta a ser segurado: corre
      # aqui, a cada tique. Resultado: o botao ficava apagado a dizer "nao da",
      # e bastava manter o dedo em cima para ele continuar a sair — com
      # animacao, com som e com dano.
      #
      # O escudo continua de fora, e a nota abaixo explica porque: ele nunca
      # teve recarga, vive so daqui.
      if modo == :feixe
        @prontos ||= [0.0, 0.0, 0.0, 0.0]
        next if @prontos[i].to_f > Time.now.to_f
      end
      next if @segurar_travado

      agora = Time.now.to_f
      @segurar_desde ||= agora
      # ⚠️ O TECTO NAO PODE SER O MESMO PARA TODOS.
      #
      # Um segundo e a medida certa para um ESCUDO: o suficiente para aparar um
      # golpe que se viu chegar, e curto de mais para se viver atras dele. Mas o
      # rodopio nao e uma parede — e uma maneira de andar. Com um segundo ele
      # nao chegava a ser um modo, era um esticao.
      #
      # O travao dele e outro, e e melhor: a energia. A 30 por segundo esvazia
      # a barra cheia em pouco mais de tres segundos, e a barra so volta a
      # encher se ele parar. Quem gira paga por girar.
      if (agora - @segurar_desde) > tecto_de_segurar(modo)
        @segurar_travado = true
        @escudo_ate = 0.0
        @espelho_ate = 0.0
        parar_de_girar!
        dizer(_INTL("Acabou o fôlego do golpe!"))
        break
      end

      case modo
      when :escudo
        if gastar_energia!(ENERGIA_ESCUDO)
          @a_segurar = :escudo
          # ⚠️ A ANIMACAO SO NO INSTANTE EM QUE ABRE, E NAO A CADA FRAME.
          #
          # Isto corre 60 vezes por segundo enquanto a tecla estiver premida.
          # Tocar a animacao aqui sem guarda punha sessenta Protects empilhados
          # por segundo — que e como nao se ver nenhum, e ainda por cima caro.
          abrir_escudo!(mv) if @escudo_ate.to_f <= agora
          @escudo_ate = agora + 0.2   # vale mais uns instantes que a tecla
          dizer(_INTL("Protegendo!"))
        end
      when :espelho
        if gastar_energia!(ENERGIA_ESCUDO)
          @a_segurar = :espelho
          @espelho_ate = agora + 0.2
          dizer(_INTL("Refletindo!"))
        end
      when :rodopio
        # Sem folego nao ha giro: o `gastar_energia!` devolve false e cai-se no
        # `parar_de_girar!` a seguir, em vez de se ficar a rodar de graca.
        parar_de_girar! unless energia > 0.0
        if gastar_energia!(ENERGIA_RODOPIO)
          @a_segurar = :rodopio
          @rodopio_ate = agora + 0.2
          # ⚠️ O DESVIO E O MESMO ESPELHO, e nao um sistema novo.
          #
          # Ja existe um sitio, e um so, onde um projectil que ia acertar em mim
          # pode ser devolvido — no instante do toque. Reaproveita-se: girar
          # levanta o espelho. Assim o Rapid Spin devolve golpes pela mesma
          # porta por onde o Reflect os devolve, com as mesmas regras.
          @espelho_ate = agora + 0.2
          girar!
        end
      else
        if gastar_energia!(ENERGIA_FEIXE)
          @a_segurar = :feixe
          tique_do_feixe!(mv, rotulo)
        end
      end
      break
    end
    unless algum
      # Largou tudo: o relogio zera e o golpe volta a poder ser segurado.
      @segurar_desde = nil
      @segurar_travado = false
      # E quem estava a girar volta a olhar para onde anda.
      parar_de_girar!
    end
  rescue
    nil
  end

  ENERGIA_RODOPIO = 30.0   # por segundo: mais caro que o escudo, porque anda
  RODOPIO_CADENCIA = 3     # frames entre cada quarto de volta
  RODOPIO_ANIM     = 22    # frames entre um tufao e o seguinte
  RODOPIO_VARRE    = 1.4   # casas: o alcance da vassoura

  # As quatro direccoes na ordem em que se giram. Nao e 2-4-6-8 (essa ordem
  # abana em vez de rodar): e o sentido dos ponteiros do relogio.
  VOLTA = [2, 4, 8, 6].freeze

  RODOPIO_MAX = 4.0   # segundos: o dobro do dobro do escudo, e ainda assim finito

  def tecto_de_segurar(modo)
    (modo == :rodopio) ? RODOPIO_MAX : SEGURAR_MAX
  rescue
    SEGURAR_MAX
  end

  def parar_de_girar!
    return unless @rodopio_passo
    @rodopio_passo = nil
    @rodopio_ate = 0.0
    # Nao se endireita a direccao a mao: o proximo passo do movimento livre
    # escreve-a a partir das setas, e um boneco parado fica virado para onde a
    # rotacao o deixou — que e exactamente como uma peca a parar de girar.
  rescue
    nil
  end

  def rodopio_de_pe?
    @rodopio_ate.to_f > Time.now.to_f
  rescue
    false
  end

  # ⚠️ QUEM GIRA O BONECO E ISTO, E NAO O MOVIMENTO.
  #
  # O `mover_livre!` escreve a direccao a partir das setas — e por isso quem
  # anda fica virado para onde anda. Isto corre DEPOIS, no mesmo tick, e
  # sobrepoe-se: as setas continuam a mandar para onde se vai, mas ja nao mandam
  # para onde se olha. E o que deixa andar e girar ao mesmo tempo.
  def girar!
    agora = (Graphics.frame_count rescue 0)
    if (agora - @rodopio_quadro.to_i) >= RODOPIO_CADENCIA
      @rodopio_quadro = agora
      @rodopio_passo = (@rodopio_passo.to_i + 1) % VOLTA.length
      ($game_player.instance_variable_set(:@direction, VOLTA[@rodopio_passo]) rescue nil)
      # As pernas tambem andam: um boneco a rodar com a perna parada parece um
      # cartaz a ser virado.
      animar_evento!($game_player)
    end
    # O tufao volta a ser tocado de tempos a tempos — a animacao do golpe dura
    # menos do que se costuma segurar o botao.
    if (agora - @rodopio_anim.to_i) >= RODOPIO_ANIM
      @rodopio_anim = agora
      mv = golpe_de_rodopio
      if mv
        anim = animacao_do_golpe(mv.id)
        tocar_ancorado_em!($game_player, anim)
        # ⚠️ E O PARCEIRO NUNCA VIU ISTO, PORQUE ISTO NUNCA SAIU DAQUI.
        #
        # Todos os outros golpes passam pelo `usar_golpe!`, que anuncia. O
        # rodopio nao: e um modo de segurar, desenha-se aqui e acaba aqui. Do
        # lado do parceiro o boneco girava sem nada a volta — e um golpe que so
        # um dos dois ve nao e um golpe partilhado.
        anunciar_animacao_propria!(mv, anim)
      end
    end
    varrer_o_chao!
  rescue
    nil
  end

  def golpe_de_rodopio
    (@meu.moves.compact.find { |m| RODOPIOS.include?(m.id.to_s.upcase.to_sym) } rescue nil)
  rescue
    nil
  end

  # ⚠️ A VASSOURA LIMPA OS DOIS LADOS, e isso e de proposito.
  #
  # Na batalha por turnos o Rapid Spin so tira as armadilhas do MEU lado. Aqui
  # nao ha lados: ha um chao. Uma armadilha que eu varro deixa de me morder a
  # mim e de morder o outro — e quem gira no meio do campo de espinhos do
  # adversario esta a pagar por isso em energia e em estar parado a girar.
  def varrer_o_chao!
    return if @armadilhas.nil? || @armadilhas.empty?
    px = $game_player.x
    py = $game_player.y
    varridas = @armadilhas.select do |a|
      dx = a[:x] - px
      dy = a[:y] - py
      Math.sqrt((dx * dx) + (dy * dy)) <= RODOPIO_VARRE
    end
    return if varridas.empty?
    varridas.each do |a|
      tocar_no_chao!(a[:anim], a[:x], a[:y]) if a[:anim].to_i > 0
      (a[:sp].dispose rescue nil) if a[:sp] && !(a[:sp].disposed? rescue true)
      @armadilhas.delete(a)
    end
    dizer(_INTL("Varreu o chão!"))
    (pbSEPlay("Battle ball drop") rescue nil)
    registar("rodopio varreu #{varridas.length} armadilha(s)")
  rescue
    nil
  end

  def espelho_de_pe?
    @espelho_ate.to_f > Time.now.to_f
  rescue
    false
  end

  # ⚠️ UM ESCUDO QUE APARA GASTA-SE.
  #
  # Ele pulsa — um clarao azul no boneco — e cai logo a seguir. Aparar passa a
  # ser um instante bem escolhido e nao uma parede que se mantem: quem aparou um
  # golpe tem de voltar a levantar para aparar o proximo.
  def aparar!
    dizer(_INTL("Bloqueado!"))
    piscar_cor!($game_player, 150, 210, 255, 14)
    (pbSEPlay("Battle ball hit") rescue nil)
    @escudo_ate = 0.0
    @segurar_travado = true
  rescue
    nil
  end

  # O Protect tem animacao propria no jogo — a mesma que se ve numa batalha por
  # turnos. Ela toca uma vez, em cima de quem se protege, e a bolha fica depois
  # dela a dizer que continua de pe.
  def abrir_escudo!(mv)
    anim = (animacao_do_golpe(mv.id) rescue 0)
    tocar_no_character!($game_player, anim, 0, $game_player) if anim.to_i > 0
    (pbSEPlay("Battle Protect") rescue pbSEPlay("GUI sel buzzer") rescue nil)
  rescue
    nil
  end

  def escudo_de_pe?
    @escudo_ate.to_f > Time.now.to_f
  end

  # ⚠️ UM FEIXE E UM CORREDOR, E NAO UMA RECTA MATEMATICA.
  #
  # O `em_alcance?(:linha, ...)` exige alinhamento EXACTO:
  #
  #     when 2 then return dx == 0 && dy > 0 && dy <= ALCANCE_LINHA
  #
  # Esse `dx == 0` foi escrito para um mundo em casas, onde toda a gente esta
  # sempre num eixo. Esta arena anda em PIXEIS: o inimigo esta em 34,7 e nao em
  # 34, e a conta da quase sempre falso. O feixe desenhava-se por cima dele e
  # nao acertava em ninguem — que foi o que se viu.
  #
  # O que se ve tem de ser o que acerta. Mede-se ao longo da direccao em que o
  # feixe aponta (ate ao alcance) e de lado (a largura da chama). Quem estiver
  # dentro do rectangulo leva.
  LARGURA_FEIXE = 1.1   # casas para cada lado: um pouco mais que a chama

  # ⚠️ A MIRA E ASSISTIDA, MAS SO PARA A FRENTE.
  #
  # Eu tinha isto de duas maneiras, e as duas estavam mal.
  #
  # Primeiro apontava ao inimigo MAIS PROXIMO, sem mais condicao nenhuma. Como
  # "o mais proximo" pode estar atras de nos ou a quinze casas, o feixe saia na
  # diagonal para tras e matava alguem num canto por onde nunca passou.
  #
  # Depois tirei-lhe a mira toda e obriguei a apontar a mao. Ficou honesto e
  # ficou mau de jogar: num jogo em tempo real, estar sempre a endireitar o
  # boneco para o inimigo e trabalho a mais e estraga o combate.
  #
  # O que faltava nao era escolher entre as duas — era o CONE. A mira agarra
  # quem esta a frente (45 graus para cada lado) e ao alcance do golpe; quem
  # esta atras ou de lado nao existe para ela. Aponta-se com o corpo, e o resto
  # afina-se sozinho.
  #
  # E decide-se AQUI, num sitio so, porque o desenho e o dano tem de sair deste
  # mesmo numero. Foi por terem cada um a sua conta que o que se via e o que
  # acertava andaram separados a ronda toda.
  # ⚠️ EU JA TINHA ISTO CERTO E DESFI-LO DUAS VEZES.
  #
  # O build que funcionava apontava ao inimigo mais proximo, sem condicao
  # nenhuma. Eu vi um caso mau (um golpe que matou alguem num canto) e tirei-lhe
  # a mira toda; ficou impossivel de jogar. Depois pus um cone de 45 graus a
  # achar que era o meio-termo — e o cone recusa exactamente os alvos que estao
  # ao nosso lado, que sao a maioria num combate a correr. Dai "ataco o pokemon
  # do meu lado e nao acerta".
  #
  # A mira e o inimigo mais proximo. Ponto. Se ha uma correccao a fazer um dia,
  # nao e estreitar o cone: e o alcance, que ja e medido a parte.
  FOLGA_MIRA = 1.0      # casas: pode agarrar quem esta mesmo na ponta

  # A direccao em que se esta virado, em vector.
  def rumo_da_cara
    case ($game_player.direction rescue 2)
    when 2 then [0.0, 1.0]
    when 8 then [0.0, -1.0]
    when 4 then [-1.0, 0.0]
    else        [1.0, 0.0]
    end
  end

  def rumo_do_feixe(alcance)
    px = $game_player.x.to_f
    py = $game_player.y.to_f
    melhor = nil
    melhor_d = nil
    bichos_vivos.each do |b|
      next unless b[:ev]
      dx = b[:ev].x - px
      dy = b[:ev].y - py
      n = Math.sqrt((dx * dx) + (dy * dy))
      next if n < 0.001
      next if n > alcance.to_f + FOLGA_MIRA
      next if melhor_d && n >= melhor_d
      melhor = [dx / n, dy / n]
      melhor_d = n
    end
    melhor || rumo_da_cara
  rescue
    rumo_da_cara
  end

  # A casa onde a chama vai bater, no rumo que a mira escolheu.
  def casa_no_rumo(rumo, casas)
    [($game_player.x + (rumo[0] * casas)).round,
     ($game_player.y + (rumo[1] * casas)).round]
  rescue
    casa_a_frente(casas)
  end

  # ⚠️ UM ATAQUE PARA ONDE BATE, E NAO ONDE A TABELA DIZ.
  #
  # O golpe tem um alcance em casas, e eu usava-o sempre inteiro: a chama saia
  # com seis casas e meia de comprimento estivesse o inimigo a seis casas ou
  # colado a nos. Resultado: atravessa-o e vai morrer do outro lado, como se
  # ele fosse feito de ar. E nao e so feio — desfaz a leitura do golpe, porque
  # quem ve nao percebe em quem e que ele bateu.
  #
  # Mede-se ANTES de disparar. O alcance efectivo e a distancia ao primeiro que
  # esta no corredor, e a animacao e desenhada com esse comprimento — encolhe
  # sozinha, como ja fazia na oficina. O que se ve passa a ser o que aconteceu.
  #
  # Passa-se um bocadinho alem do corpo (`PARAR_ALEM`), senao a chama morre a
  # meia casa dele e parece que falhou.
  # ⚠️ A PONTA E O CENTRO DO INIMIGO. NAO UM BOCADO ALEM DELE.
  #
  # Isto foi 0,6 casas — 19 px — com o argumento de que a chama devia cobrir o
  # corpo em vez de morrer antes dele. Para o DESENHO DA CHAMA soa bem, e para
  # tudo o resto e errado: esta ponta nao e so onde o fogo acaba, e a ANCORA DO
  # ALVO. E a partir dela que se coloca o rebentamento inteiro.
  #
  # Com 19 px de folga, um golpe que devia estourar em cima do inimigo estoura
  # 19 px depois dele — quase uma casa, num sprite que tem 24 px de largura. Foi
  # o que se viu com a cruz vermelha a cair ao lado do Geodude.
  #
  # A ancora e o centro. O que a chama faz depois de la chegar e assunto do
  # desenho, nao da colocacao.
  PARAR_ALEM = 0.0      # casas: a ponta e o centro de quem esta la
  FEIXE_MINIMO = 1.0    # casas: abaixo disto a animacao nao se le

  def alcance_ate_bater(rumo, alcance)
    ux, uy = rumo
    px = $game_player.x.to_f
    py = $game_player.y.to_f
    perto = nil
    bichos_vivos.each do |b|
      next unless b[:ev]
      dx = b[:ev].x - px
      dy = b[:ev].y - py
      ao_longo = (dx * ux) + (dy * uy)
      de_lado  = ((dx * -uy) + (dy * ux)).abs
      next unless ao_longo >= 0.0 && ao_longo <= alcance && de_lado <= LARGURA_FEIXE
      perto = ao_longo if perto.nil? || ao_longo < perto
    end
    return alcance.to_f unless perto
    parado = perto + PARAR_ALEM
    parado = FEIXE_MINIMO if parado < FEIXE_MINIMO
    (parado < alcance.to_f) ? parado : alcance.to_f
  rescue
    alcance.to_f
  end

  # Prende o rumo E o comprimento enquanto o tiro dura: se fossem recalculados
  # a cada tique, o desenho (que so se faz uma vez) e o dano (que corre sempre)
  # voltavam a discordar assim que alguem desse um passo.
  #
  # Devolve o alcance efectivo, que e o que se desenha e o que fere.
  # ⚠️ UM TIRO ESCOLHE O ALVO UMA VEZ, NO PRINCIPIO.
  #
  # O desenho reapontava a `evento_inimigo` — "o mais proximo AGORA" — a cada
  # quadro. Enquanto ninguem morre, isso e o que faz o Flamethrower seguir. Mas
  # se o alvo cai a meio (um Solar Beam demora a carregar), o "mais proximo"
  # passa a ser outro e a animacao vira-se para ele — enquanto o dano continua
  # a ir para onde o tiro foi travado.
  #
  # Fica-se com um feixe a apontar a um Pokemon e a matar outro. E o pior tipo
  # de erro: nao ha nada de errado no ecra, so nao e verdade.
  #
  # Guarda-se QUEM se escolheu. Enquanto ele viver, segue-se ele; quando morre,
  # o tiro fica com a ultima direccao que tinha e acaba — nao salta.
  def travar_rumo!(alcance)
    @feixe_rumo = rumo_do_feixe(alcance)
    @feixe_alcance = alcance_ate_bater(@feixe_rumo, alcance)
    @feixe_alvo = evento_inimigo
  end

  # O evento que este tiro escolheu, se ainda estiver de pe.
  def alvo_travado
    ev = @feixe_alvo
    return nil unless ev
    return nil unless bichos_vivos.any? { |b| b[:ev].equal?(ev) }
    ev
  rescue
    nil
  end

  # A animacao que este feixe esta a tocar, para se saber quanto tempo ela dura.
  # ⚠️ O ALVO DESAPARECIA UM SEGUNDO ANTES DO SPRITE DELE.
  #
  # O `alvo_travado` responde pelos `bichos_vivos`, e um bicho sai dessa lista
  # no INSTANTE em que a vida chega a zero. Mas o boneco dele nao desaparece
  # nesse instante: o `animar_desmaio!` fica com ele mais meio segundo, a dar um
  # salto para tras e a desvanecer.
  #
  # Resultado: o feixe perdia o alvo com o corpo ainda no ar, herdava a ultima
  # direccao, e ficava apontado ao sitio onde o bicho ESTAVA enquanto se via o
  # bicho a ser atirado para longe dali. Era o "ficam fixos na tela".
  #
  # A pergunta certa nao e "ele esta vivo?" — e "onde e que ele esta a ser
  # desenhado?". Vivo, e no boneco; a cair, e no sprite da queda. So quando
  # nem isso existe e que o golpe fica com o rumo que tinha.
  #
  # (Isto e so para o DESENHO. O dano continua a perguntar pelos vivos, que e o
  # que tem de ser: um bicho caido nao leva mais.)
  def ponto_do_alvo_do_feixe
    ev = @feixe_alvo
    return nil unless ev
    return centro_do_boneco(ev) if bichos_vivos.any? { |b| b[:ev].equal?(ev) }
    d = (@desmaios || []).find { |x| x[:ev] && x[:ev].equal?(ev) }
    return nil unless d
    sp = d[:sp]
    return nil if sp.nil? || (sp.disposed? rescue true)
    # O sprite da queda assenta nos pes (`oy = ch`), tal como o boneco. Metade
    # disso e o meio do corpo — a mesma medida do `centro_do_boneco`.
    [(sp.x rescue 0), (sp.y rescue 0) - (((sp.oy rescue 0).to_i) / 2)]
  rescue
    nil
  end

  def anim_do_feixe
    @feixe_anim_idx.to_i
  rescue
    0
  end

  def ferir_na_linha!(mv, nome, casas = nil)
    # O alcance ja vem encurtado por quem disparou (ver `alcance_ate_bater`).
    # Se vier vazio, e porque o tiro nao passou por la — mede-se agora.
    alcance = (casas || @feixe_alcance || ALCANCE_FEIXE).to_f
    # ⚠️ O DESENHO PARA NO CENTRO; O DANO PRECISA DE UM DEDO DE MARGEM.
    #
    # O `alcance_ate_bater` devolve agora a distancia EXACTA ao alvo, para a
    # ancora cair no centro dele. So que o teste la em baixo e `ao_longo <=
    # alcance`, e quem esta exactamente no limite pode escapar por um erro de
    # virgula flutuante — o golpe desenhava-se em cima dele e nao lhe tocava.
    #
    # Meio corpo de margem resolve, e nao alarga o alcance de forma sensivel:
    # quem esta meia casa alem ja estava dentro do corredor de qualquer modo.
    alcance += 0.5
    px = $game_player.x.to_f
    py = $game_player.y.to_f

    # O rumo vem do `travar_rumo!`, que o desenho tambem usou. Se por alguma
    # razao ainda nao existir, calcula-se agora — mas o normal e ja estar la.
    ux, uy = (@feixe_rumo || rumo_do_feixe(alcance))

    atingidos = []
    bichos_vivos.each do |b|
      next unless b[:ev]
      dx = b[:ev].x - px
      dy = b[:ev].y - py
      ao_longo = (dx * ux) + (dy * uy)          # quanto avancou pelo feixe
      de_lado  = ((dx * -uy) + (dy * ux)).abs   # quanto se desviou dele
      next unless ao_longo >= -0.5 && ao_longo <= alcance && de_lado <= LARGURA_FEIXE
      atingidos << [b, [ao_longo, 0.0].max]
    end
    # Do mais perto para o mais longe: e por essa ordem que a chama os alcanca.
    atingidos.sort_by! { |(_, d)| d }

    if atingidos.empty?
      narrar("#{nome}...")
      registar("feixe #{mv.id} nao apanhou ninguem (alcance #{alcance.round(1)} casas)")
      return
    end
    # ⚠️ MORRER ANTES DA ANIMACAO CHEGAR E UM DEFEITO, NAO UM PORMENOR.
    #
    # O dano saia todo no instante em que se carregava na tecla, enquanto a
    # chama ainda estava a sair da boca. Quem estava a seis casas caia antes de
    # a chama o alcancar — e a leitura fica ao contrario: parece que o golpe
    # matou por magia e a animacao veio depois pedir desculpa.
    #
    # Cada alvo leva quando a chama chega A ELE: o atraso e a distancia a que
    # esta, na velocidade a que o fogo anda.
    # ⚠️ A CHAMA VIAJA DEPRESSA. A ANIMACAO NAO.
    #
    # O atraso saia so da velocidade do fogo (14 casas por segundo). Isso e
    # honesto para uma chama, e completamente errado para o que se VE:
    #
    #     alvo a 1 casa  -> dano aos 0,07 s
    #     alvo a 3 casas -> dano aos 0,22 s
    #     alvo a 6 casas -> dano aos 0,43 s
    #
    # ... e o Flamethrower tem 19 quadros, que a 20 por segundo sao 0,95 s. A 3
    # casas o bicho caia aos 0,22 s, com a animacao ainda a comecar. Dai o
    # "morre antes do golpe atingir".
    #
    # Poe-se um PISO: o dano nunca chega antes de a animacao ter andado o
    # bastante para se ler como um golpe. O piso e o mesmo numero que os outros
    # golpes usam (`atraso_do_golpe`), portanto e uma regra so para o jogo todo.
    #
    # Acima do piso a distancia continua a mandar — quem esta longe leva depois
    # de quem esta perto, que e o que faz a chama parecer uma chama.
    piso = atraso_do_golpe(:linha, nil, anim_do_feixe)
    atingidos.each_with_index do |(b, dist), i|
      frames = ((dist / VEL_FEIXE) * 60.0).round
      frames = piso if frames < piso
      frames = 0 if frames < 0
      frames = 90 if frames > 90
      (@feixe_dano ||= []) << [(Graphics.frame_count rescue 0) + frames, b, mv,
                               (i.zero? ? nome : nil)]
    end
    registar("feixe #{mv.id} apanhou #{atingidos.length} " \
             "(rumo #{ux.round(2)},#{uy.round(2)} alcance #{alcance.round(1)})")
  rescue => e
    registar("falha no feixe: #{e.class}: #{e.message}")
  end

  VEL_FEIXE = 14.0   # casas por segundo: a que velocidade a chama avanca

  # O dano que estava a espera de a chama chegar.
  def correr_feixe_dano!
    return if @feixe_dano.nil? || @feixe_dano.empty?
    agora = (Graphics.frame_count rescue 0)
    prontos = @feixe_dano.select { |a| a[0] <= agora }
    return if prontos.empty?
    @feixe_dano -= prontos
    prontos.each do |(_, b, mv, nome)|
      next unless b && b[:hp].to_i > 0 && b[:ev]
      ferir_bicho!(b, dano_no_bicho(b, mv), mv, nome)
    end
  rescue
    @feixe_dano = []
  end

  def feixe_a_correr?
    return false unless @feixe_anim
    vivo = (@jogadores_anim || []).include?(@feixe_anim) &&
           !(@feixe_anim.animDone? rescue true)
    @feixe_anim = nil unless vivo
    vivo
  rescue
    @feixe_anim = nil
    false
  end

  def tique_do_feixe!(mv, _rotulo)
    agora = (Graphics.frame_count rescue 0)
    return if (agora - @feixe_tique.to_i) < FEIXE_CADENCIA
    @feixe_tique = agora
    anim = animacao_do_golpe(mv.id)
    ev = evento_inimigo
    alvo_x, alvo_y = ev ? [ev.x, ev.y] : casa_a_frente(ALCANCE_LINHA)
    # ⚠️ Era ISTO que ficava colado ao Pokemon.
    #
    # A cada 12 frames de botao em baixo tocava-se a animacao inteira da batalha
    # em cima dele. Agora sai uma particula, que e o que um jacto continuo e.
    # ⚠️ UM GOLPE MARCADO COMO FEIXE NO EDITOR TOCA A ANIMACAO, E NAO JORRA.
    #
    # Um lanca-chamas era desenhado aqui como um jacto de particulas — o que se
    # justificava, porque tocar a animacao inteira de batalha a cada 12 frames
    # ficava colada ao Pokemon, e o jorro veio resolver isso.
    #
    # So que agora ha uma terceira via: o editor sabe colocar a animacao ao
    # longo de uma linha, com o comprimento em casas que se escolher. Quem
    # configurou assim quer VER a animacao, e nao as particulas — e a escolha
    # dele tem de vencer o palpite do codigo.
    #
    # Esta era a peca que faltava para o remendo se notar. O `cfg` e lido dentro
    # do `tocar_no_character!`, e por este caminho ele nunca chegava a ser
    # chamado: o ficheiro era lido, a configuracao estava certa, e nao acontecia
    # nada — porque a animacao nao chegava a ser tocada.
    cfg_feixe = palco_da_anim(anim)
    marcado_feixe = (cfg_feixe && cfg_feixe["modo"].to_s == "feixe")

    if marcado_feixe && anim > 0
      # ⚠️ UMA DE CADA VEZ. FOI ISTO QUE EU RE-INTRODUZI.
      #
      # O jorro de particulas existe porque tocar a animacao inteira a cada 12
      # frames a deixava colada ao Pokemon. Eu voltei a toca-la — e sem travao
      # nenhum: sete animacoes a correr ao mesmo tempo, empilhadas umas por
      # cima das outras. O log dizia-o em letra gorda ("7 a correr").
      #
      # Um feixe e UM efeito continuo, e nao sete. Enquanto a anterior nao
      # acabar, nao se comeca outra.
      unless feixe_a_correr?
        # Ver a nota do `usar_golpe!`. As duas entradas do feixe tem de mirar
        # pela mesma regra, senao segurar a tecla dava um tiro diferente de
        # tocar nela.
        casas = ((cfg_feixe["feixe_casas"] || ALCANCE_FEIXE).to_f.round)
        casas = 1 if casas < 1
        casas = 20 if casas > 20
        travar_rumo!(casas)
        cx, cy = ponto_no_rumo(@feixe_rumo, @feixe_alcance)
        tocar_no_ponto!(anim, cx, cy)
        @feixe_anim = (@jogadores_anim || []).last
        @feixe_anim_idx = anim.to_i
      end
    elsif jorro_de_fogo?(mv)
      soltar_particula_de_jorro!(mv, anim) unless pvp?
    elsif anim > 0 && ev
      # Um feixe que nao e de fogo mostra a animacao dele, no alvo.
      tocar_no_character!(ev, anim)
    end
    if pvp?
      enviar!("arena_golpe",
        "move" => mv.id.to_s, "x" => $game_player.x, "y" => $game_player.y,
        "dir" => $game_player.direction, "forma" => "linha", "anim" => 0,
        "atraso" => 0, "forca" => FEIXE_FORCA,
        "nivel" => (@meu.level.to_i rescue 50),
        "atk" => (@meu.attack.to_i rescue 50), "spatk" => (@meu.spatk.to_i rescue 50))
    else
      anunciar_na_caverna!(
        "move" => mv.id.to_s, "x" => $game_player.x, "y" => $game_player.y,
        "dir" => $game_player.direction, "forma" => "linha", "anim" => 0,
        "atraso" => 0, "forca" => FEIXE_FORCA,
        "nivel" => (@meu.level.to_i rescue 50),
        "atk" => (@meu.attack.to_i rescue 50), "spatk" => (@meu.spatk.to_i rescue 50))
      bichos_vivos.each do |b|
        next unless b[:ev]
        next unless em_alcance?(:linha, $game_player.x, $game_player.y, $game_player.direction, b[:ev].x, b[:ev].y)
        d = [(dano_no_bicho(b, mv) * FEIXE_FORCA).round, 1].max
        ferir_bicho!(b, d)
      end
    end
  rescue
    nil
  end

  #-----------------------------------------------------------------------------
  # PROJECTEIS
  #
  # ⚠️ UM LANCAMENTO E UMA COISA QUE VOA, E NAO UM TEMPORIZADOR.
  #
  # Ate aqui um golpe a distancia era um atraso calculado: somava-se o arranque
  # com as casas e, passados tantos frames, perguntava-se "acertou?". Funcionava
  # como aritmetica e falhava como jogo — a Shadow Ball nao existia no mapa
  # entre o disparo e o impacto, portanto nao havia nada para ver, nada para
  # desviar, e nada que pudesse acertar a meio caminho.
  #
  # Agora e um objecto: nasce em quem ataca, atravessa o mapa a uma velocidade
  # em casas por segundo, e so rebenta quando encontra alguem ou quando fica
  # sem alcance.
  #-----------------------------------------------------------------------------
  PROJ_VEL      = 7.0     # casas por segundo
  PROJ_VEL_MIRA = 8.5     # um golpe infalivel voa um pouco mais depressa
  PROJ_ALCANCE  = 14.0    # casas percorridas ate cair sozinho
  PROJ_RAIO     = 0.6     # casas: quao perto tem de passar para bater
  PROJ_VIRAGEM  = 3.5     # radianos por segundo de correccao de rumo
  PROJ_CURVA    = 1.2     # casas: raio maximo da curva, seja qual for a pressa
  PROJ_TAMANHO  = 40.0    # px: pouco mais de uma casa
  CEL_ANIM      = 192     # o lado de uma celula na folha de animacao

  # Um lancamento e um golpe com forca que NAO toca no alvo. O motor ja sabe
  # dizer isso: a bandeira "Contact" separa a dentada do arremesso, e e a mesma
  # leitura que a batalha por turnos faz.
  # ⚠️ UM FEIXE TAMBEM SE ATIRA — segurar e o EXTRA, nao o unico modo.
  #
  # O Flamethrower estava fora dos lancamentos por ser seguravel, e o resultado
  # era um golpe que so existia com o botao em baixo: um toque nao fazia nada.
  # Agora o toque atira a labareda a seis casas, como qualquer outro; quem
  # continuar a segurar continua a despejar, que era a ideia original.
  def lancamento?(mv)
    return false unless mv && mv.id
    dados = (GameData::Move.get(mv.id) rescue nil)
    return false unless dados
    # ⚠️ UM GOLPE DE ESTADO TAMBEM E UM ARREMESSO.
    #
    # Estavam de fora por nao terem forca, e o resultado era um botao morto: a
    # Thunder Wave nao voava, nao acertava e nao paralisava nada. O que ela tem
    # nao e dano, e efeito — e o efeito ja se sabe ler pelo tipo. Se o tipo dela
    # da um estado, ela voa como as outras e aplica-o a chegada.
    if dados.power.to_i <= 0
      return false unless dados.category == 2
      return false unless ESTADOS_POR_TIPO[dados.type]
    end
    # ⚠️ UM GOLPE QUE NAO APONTA A NINGUEM NAO SE ATIRA.
    #
    # Sunny Day e do tipo FOGO, tem forca zero e e de estado — exactamente o
    # feitio que eu tinha aberto para a Thunder Wave voar. Resultado: o Sunny Day
    # saia como uma bola de fogo que queimava o adversario, e o Hail congelava.
    # Nenhum deles aponta a nada: o alvo deles e o campo, ou o proprio.
    return false if NAO_APONTAM.include?(dados.target)
    alvo = (GameData::Target.get(dados.target) rescue nil)
    # O que marca o lado do campo e armadilha, nao arremesso. Mas atingir varios
    # inimigos ja nao impede de voar: o Razor Leaf sai, viaja, e rebenta em area.
    return false if alvo && alvo.affects_foe_side
    true
  rescue
    false
  end

  # ⚠️ ATE UM ARRANHAO E UM LANCAMENTO — SO QUE DE DUAS CASAS.
  #
  # Um golpe de contacto que so batia na casa colada nao dava jogo nenhum: ou o
  # inimigo estava exactamente ali, ou nao havia nada a fazer. Com duas casas de
  # alcance e um bote rapido, aproximar-se e afastar-se passa a ser a decisao —
  # que e o que torna o combate ganhavel a andar em vez de a carregar em botoes.
  #
  # E o alcance curto tambem e o que impede o Scratch de perseguir alguem pelo
  # mapa fora: perto de mais, e o bote cai no chao.
  ALCANCE_CORPO = 2.2     # casas
  VEL_CORPO     = 12.0    # casas por segundo: um bote, nao um voo

  def contacto?(mv)
    dados = (GameData::Move.get(mv.id) rescue nil)
    return false unless dados
    bandeiras = (dados.flags rescue []) || []
    bandeiras.any? { |b| b.to_s.downcase == "contact" }
  rescue
    false
  end

  ALCANCE_FEIXE = 6.5   # casas: um jacto nao atravessa o mapa

  # Alvos que nao sao ninguem: o campo, o proprio, os aliados.
  NAO_APONTAM = [:User, :UserSide, :BothSides, :None, :UserAndAllies,
                 :Ally, :NearAlly, :UserOrNearAlly, :AllAllies].freeze

  # ⚠️ "ATINGE VARIOS" SAO TRES COISAS DIFERENTES, E O PBS JA AS SEPARA.
  #
  # Eu tinha metido tudo o que apanha mais de um alvo no mesmo saco e mandado
  # tudo voar. So que um Earthquake nao voa: ele abre o chao DEBAIXO de toda a
  # gente, incluindo de quem esta ao lado. Contadas no moves.txt deste jogo, sao
  # tres familias:
  #
  #   AllNearFoes    48 com dano   Razor Leaf, Dazzling Gleam, Eruption, Snarl…
  #                                saem de mim para os inimigos -> rajada
  #   AllNearOthers  17 com dano   Earthquake, Discharge, Explosion, Lava Plume,
  #                                Boomburst, Sludge Wave, Bulldoze, Magnitude…
  #                                rebentam A MINHA VOLTA -> onda, sem projectil
  #   RandomNearFoe   5            Outrage, Thrash, Petal Dance, Uproar…
  #                                um alvo, sorteado -> tiro normal
  #
  # Nao ha lista de nomes nenhuma aqui: o alvo de cada golpe ja diz a que
  # familia pertence, e um golpe novo no PBS cai sozinho na certa.
  EM_VOLTA      = [:AllNearOthers, :AllBattlers, :AllNearOthersAndAllies].freeze
  SORTEADO      = [:RandomNearFoe].freeze
  RAIO_EM_VOLTA = 3.0    # casas que uma onda alcanca

  def area?(mv)
    dados = (GameData::Move.get(mv.id) rescue nil)
    return false unless dados
    return false if EM_VOLTA.include?(dados.target)
    return false if SORTEADO.include?(dados.target)
    alvo = (GameData::Target.get(dados.target) rescue nil)
    alvo ? (alvo.num_targets > 1) : false
  rescue
    false
  end

  def em_volta?(mv)
    dados = (GameData::Move.get(mv.id) rescue nil)
    dados ? EM_VOLTA.include?(dados.target) : false
  rescue
    false
  end

  def sorteado?(mv)
    dados = (GameData::Move.get(mv.id) rescue nil)
    dados ? SORTEADO.include?(dados.target) : false
  rescue
    false
  end

  # ⚠️ UMA ONDA NAO TEM PROJECTIL: ELA JA ESTA EM TODA A PARTE.
  #
  # Nada viaja — a animacao toca em cima de quem usa e o estrago e imediato em
  # tudo o que estiver dentro do raio. Fazer o Earthquake atirar pedrinhas
  # seria bonito e errado: quem esta colado a mim tem de levar na mesma.
  # ⚠️ UMA ONDA TAMBEM NAO E A ANIMACAO DE BATALHA.
  #
  # O Earthquake desenhado para o palco ocupa a tela inteira: por cima do mapa
  # sao pedras do tamanho de casas, tapando tudo — foi o "sprites gigantes" que
  # o jogador viu. O que uma onda quer dizer no mapa e outra coisa: pedras a
  # sair DE MIM para todos os lados, e o chao a tremer.
  #
  # As pedras sao as mesmas particulas da rajada, sem alvo nenhum — cada uma
  # segue o seu rumo e cai. O dano ja foi aplicado no instante zero (uma onda
  # nao viaja), portanto elas sao so o que se ve.
  ONDA_PEDRAS = 10

  def explodir_em_volta!(mv, nome, anim)
    # Num duelo o estrago e decidido pela vitima; aqui so se abre o chao.
    ferir_em_area!($game_player.x, $game_player.y, RAIO_EM_VOLTA, mv, nome) unless pvp?
    dizer(nome) if pvp? && nome
    # A tela treme: forca, velocidade, duracao em frames.
    ($game_screen.start_shake(6, 9, 24) rescue nil)
    tipo = (GameData::Move.get(mv.id).type rescue nil)
    som = [:GROUND, :ROCK].include?(tipo) ? "Anim/Earth3" : "Battle damage super"
    (pbSEPlay(som) rescue (pbSEPlay("Battle damage super") rescue nil))
    # ⚠️ A ONDA TINHA UM DESENHO PROPRIO E PASSAVA POR CIMA DA OFICINA.
    #
    # Dez pedras em roda, uma a cada 36 graus. Foi feito para o Earthquake, e
    # para o Earthquake esta certo. Mas isto dispara para QUALQUER golpe cujo
    # alvo seja `AllNearOthers` — e o Surf e um deles. Quem afinou o Surf no
    # editor escolheu "o proprio, sem direccao", gravou, e o jogo respondeu com
    # um circulo de pedras que ninguem pediu: era o "jogou a animacao em
    # espiral".
    #
    # Este ficheiro ja tem a regra escrita para um caso parecido, duas centenas
    # de linhas acima: "uma escolha na oficina vale mais do que um palpite pela
    # categoria". Ela vale aqui pela mesma razao. O que muda e so o DESENHO — o
    # estrago, o tremor e o som sao da onda e continuam a ser, porque esses vem
    # do golpe e nao da animacao.
    escolha = (palco_da_anim(anim) || {})["modo"].to_s
    if anim > 0 && escolha == "quem"
      # A animacao do golpe, em cima de quem o deu, sem direccao nenhuma.
      tocar_ancorado_em!($game_player, anim)
    elsif anim > 0 && escolha == "alvo"
      vitimas = bichos_vivos.select do |b|
        b[:ev] && distancia_casas(b[:ev], $game_player) <= RAIO_EM_VOLTA
      end
      if vitimas.empty?
        tocar_ancorado_em!($game_player, anim)
      else
        vitimas.first(AREA_MAX_ANIMS).each { |b| tocar_no_character!(b[:ev], anim) }
      end
    elsif anim > 0 && escolha == "chao"
      tocar_no_chao!(anim, $game_player.x, $game_player.y)
    else
      ONDA_PEDRAS.times do |i|
        ang = ((Math::PI * 2.0) / ONDA_PEDRAS) * i
        lancar!(:x => $game_player.x, :y => $game_player.y,
                :dir => $game_player.direction, :alvo => nil, :anim => 0,
                :infalivel => false, :pequeno => true, :cartao_de => anim,
                :ux => Math.cos(ang), :uy => Math.sin(ang),
                :move_id => mv.id, :mv => mv, :nome => nil, :meu => true,
                :so_desenho => true, :alcance => RAIO_EM_VOLTA,
                :curto => false, :vel => PROJ_VEL * 0.8)
      end
    end

    # Explosion e Self-Destruct cobram o preco de sempre; Mind Blown cobra
    # metade. Sem isto o golpe mais forte do jogo era de graca.
    fc = (GameData::Move.get(mv.id).function_code.to_s rescue "")
    if fc.include?("UserFaintsExplosive")
      @hp_meu = 0
      terminar_derrota!
    elsif fc.include?("UserLosesHalfOfTotalHPExplosive")
      @hp_meu = [@hp_meu - ((@meu.totalhp / 2.0).round), 0].max
      terminar_derrota! if @hp_meu <= 0
    end
  rescue => e
    registar("falha na onda: #{e.class}: #{e.message}")
  end

  # ⚠️ MAIS UM CAMPO DO EDITOR QUE NINGUEM LIA.
  #
  # O painel tem um `alcance` e ele esta gravado em 204 animacoes — o Swift com
  # 14 casas, o Wing Attack com 2,2. O jogo nunca o leu: respondia sempre pela
  # tabela, e a tabela diz que um golpe de CONTACTO alcanca `ALCANCE_CORPO`,
  # que sao 2,2 casas.
  #
  # Foi isso que o utilizador viu. O Wing Attack e de contacto, portanto o
  # projectil dele morre a 2,2 casas — e a animacao de impacto e tocada onde
  # ele morreu. Com o inimigo mais longe do que isso, o golpe rebenta no ar, a
  # duas casas de ninguem. "as vezes 2 casas de distancia" e literalmente o
  # numero que esta aqui.
  #
  # Quem afinou o golpe na oficina que decida o alcance dele. Sem remendo, a
  # tabela responde como sempre respondeu.
  def alcance_do_lancamento(mv, anim = nil)
    a = ((palco_da_anim(anim || animacao_do_golpe(mv.id)) || {})["alcance"] rescue nil)
    return a.to_f if a && a.to_f > 0.0
    return ALCANCE_CORPO if contacto?(mv)
    return ALCANCE_FEIXE if seguravel(mv) == :feixe
    PROJ_ALCANCE
  rescue
    PROJ_ALCANCE
  end

  # ⚠️ O EDITOR TINHA UM DESLIZADOR DE VELOCIDADE QUE NAO LIGAVA A NADA.
  #
  # Isto devolvia constantes e nunca perguntava ao palco. O editor grava o
  # `veloc` desde sempre — 136 das 200 animacoes ja tem um valor proprio la
  # dentro — e nenhum deles chegou alguma vez ao jogo. Mexia-se, via-se mudar no
  # editor (que simula com os seus numeros), gravava-se, e o golpe saia
  # exactamente a mesma velocidade de antes.
  #
  # Do banco de quem afina isso le-se como "o jogo nao esta a ler o que eu
  # gravei" — e a conclusao estava certa, so que o que nao era lido era este
  # campo, nao o ficheiro.
  #
  # As constantes ficam como omissao, para uma animacao sem afinacao continuar
  # a sair como sempre saiu.
  def palco_do_golpe(mv)
    return nil unless mv
    palco_da_anim(animacao_do_golpe(mv.id))
  rescue
    nil
  end

  def velocidade_do_lancamento(mv, infalivel)
    cfg = palco_do_golpe(mv)
    v = cfg ? cfg["veloc"].to_f : 0.0
    return v if v > 0.1
    return VEL_CORPO if contacto?(mv)
    infalivel ? PROJ_VEL_MIRA : PROJ_VEL
  end

  # ⚠️ 100% DE PRECISAO QUER DIZER QUE NAO ERRA — E ISSO E MIRA, NAO SORTE.
  #
  # Um golpe de 100% que falhasse porque o alvo andou seria mentira: na batalha
  # por turnos ele acerta sempre. Aqui isso traduz-se em perseguicao perfeita —
  # a bola corrige o rumo todos os frames e voa mais depressa do que qualquer
  # Pokemon corre, portanto acaba sempre por o apanhar. Os golpes abaixo de
  # 100% corrigem devagar (podem perder a curva) e ainda passam por um sorteio
  # a chegada. No Essentials, precisao 0 tambem quer dizer "nunca falha".
  def precisao(move_id)
    a = (GameData::Move.get(move_id).accuracy.to_i rescue 100)
    a <= 0 ? 100 : a
  end

  def infalivel?(move_id)
    a = (GameData::Move.get(move_id).accuracy.to_i rescue 100)
    a <= 0 || a >= 100
  rescue
    false
  end

  # ⚠️ O QUE VOA E A COISA GRANDE, E VOA A ANIMAR.
  #
  # A primeira versao apanhava a PRIMEIRA celula visivel da animacao. Numa
  # Thunder Shock isso e a faisca inicial — uma bolinha de nada — e era isso que
  # atravessava o ecra, para o golpe a serio so aparecer no fim. Estava errado
  # nas duas pontas: voava o que nao interessa, e a explosao repetia a parte do
  # arremesso, como se o Pokemon atirasse a bola grande DEPOIS de a pequena ja
  # ter acertado.
  #
  # Agora a animacao le-se em duas metades. O quadro com mais celulas visiveis e
  # o rebentamento (o pico); tudo o que vem antes e o voo. Do voo tira-se a
  # MAIOR celula de cada quadro — a navalha do Air Cutter, a bola do Volt Switch
  # — e monta-se um flip-book que roda enquanto o projectil viaja. Do
  # rebentamento guarda-se o numero do quadro, para a explosao comecar ali e nao
  # no principio: quando a coisa acerta, ela dissipa-se, nao volta a ser
  # lancada.
  #
  # ⚠️ E CADA CELULA E RECORTADA AO CONTEUDO.
  #
  # Dentro dos 192x192 de uma celula o desenho ocupa uma fatia pequena e o resto
  # e transparente. Sem recortar, o zoom encolhia o vazio junto com a imagem e
  # tudo saia minusculo — foi metade da razao de a bolinha ser "minima". Mede-se
  # onde estao mesmo os pixeis e e essa caixa que se leva.
  AMOSTRA_PIXEL = 4     # de quantos em quantos pixeis se procura conteudo
  MAX_PADROES   = 10    # celulas distintas que vale a pena medir
  CADENCIA_ANIM = 20.0  # quadros por segundo, a mesma do motor das animacoes

  def celula_visivel?(cel)
    return false unless cel.is_a?(Array)
    return false unless cel[AnimFrame::VISIBLE].to_i == 1
    return false unless cel[AnimFrame::OPACITY].to_i > 128
    cel[AnimFrame::PATTERN].to_i >= 0
  rescue
    false
  end

  # A caixa dos pixeis que existem mesmo dentro de uma celula.
  def caixa_do_padrao(bmp, padrao)
    @caixas ||= {}
    chave = [bmp.object_id, padrao]
    return @caixas[chave] if @caixas.key?(chave)
    ox = (padrao % 5) * CEL_ANIM
    oy = (padrao / 5) * CEL_ANIM
    # ⚠️ NEM TODAS AS FOLHAS TEM CINCO COLUNAS.
    #
    # O indice de uma celula assume uma grelha de 5 x 192 = 960 px, e e assim que
    # o motor a le. Mas so 391 das folhas deste jogo tem 960 de largura: ha 146
    # com 512, 54 com 768, e por ai fora. Numa folha de 512 a coluna 2 esta
    # cortada ao meio e a 3 nem existe.
    #
    # Eu recusava a celula inteira nesse caso e devolvia nil — e sem celula nao
    # ha particula nenhuma. Era isto que deixava o Make It Rain e o Earthquake
    # sem pedras: as folhas deles nao sao das largas. Agora mede-se so o pedaco
    # que existe mesmo, que e exactamente o que o motor tambem desenha.
    larg = [CEL_ANIM, bmp.width - ox].min
    alt  = [CEL_ANIM, bmp.height - oy].min
    return (@caixas[chave] = nil) if larg <= 8 || alt <= 8
    passo = AMOSTRA_PIXEL
    x1 = CEL_ANIM
    y1 = CEL_ANIM
    x2 = -1
    y2 = -1
    yy = 0
    while yy < alt
      xx = 0
      while xx < larg
        if bmp.get_pixel(ox + xx, oy + yy).alpha > 40
          x1 = xx if xx < x1
          x2 = xx if xx > x2
          y1 = yy if yy < y1
          y2 = yy if yy > y2
        end
        xx += passo
      end
      yy += passo
    end
    @caixas[chave] = (x2 < 0) ? nil : [x1, y1, (x2 - x1) + passo, (y2 - y1) + passo]
  rescue
    (@caixas ||= {})[[bmp.object_id, padrao]] = nil
  end

  # ⚠️ PARA UM LEQUE, A CELULA CERTA E A MAIS PEQUENA.
  #
  # A regra normal escolhe a MAIOR celula visivel, e para uma Shadow Ball isso e
  # exactamente a bola. Mas a folha do Razor Leaf esta desenhada varias vezes na
  # folha de animacao — uma por folha — e a maior de todas e o molho inteiro.
  # Levar esse molho como projectil deu o que o jogador viu: uma mancha unica a
  # rodar, em vez de folhas.
  #
  # Quando o golpe sai em leque pede-se a MENOR celula com tamanho de gente: e
  # uma folha so, e saem muitas.
  TAMANHO_FOLHA = 22.0

  # ⚠️ UMA TABELA DE EXCEPCOES, E ASSUMIDA COMO TAL.
  #
  # A regra da mediana acerta na esmagadora maioria dos 851 golpes, mas ha
  # animacoes em que a celula certa nao e a do meio — o autor desenhou tres
  # variantes da mesma coisa e so uma e "o objecto". No Bubble Beam sao os
  # padroes 28, 29 e 30 do `PRAS- Water.png`, e a bolha e a 28 (aparece 144
  # vezes; as outras duas, 24 cada).
  #
  # Isto e escolha a olho, como a lista dos escudos e a dos feixes. Fica aqui,
  # curta e visivel, em vez de disfarcada de heuristica: quem quiser corrigir um
  # golpe acrescenta uma linha e nao mexe em mais nada.
  PARTICULA_FIXA = {
    :BUBBLEBEAM => 28
  }.freeze

  def cartao_do_projectil(anim, pequeno = false, padrao_fixo = nil)
    @cartoes ||= {}
    chave = [anim, pequeno, padrao_fixo]
    return @cartoes[chave] if @cartoes.key?(chave)
    t0 = Time.now.to_f
    @cartoes[chave] = begin
      obj = animacoes_de_golpe[anim.to_i]
      raise "sem animacao #{anim}" unless obj
      folha = obj.graphic.to_s
      raise "animacao #{anim} sem folha" if folha.empty?
      # O hue vai ao CONSTRUTOR: rodar a cor depois estraga o bitmap partilhado
      # da cache e a mancha escapa para o jogo todo.
      bmp = AnimatedBitmap.new("Graphics/Animations/" + folha, obj.hue.to_i).deanimate

      # (a) onde e o rebentamento: o quadro com mais celulas ao mesmo tempo
      contas = []
      obj.length.times do |i|
        quadro = obj[i]
        n = 0
        quadro.each { |cel| n += 1 if celula_visivel?(cel) } if quadro.is_a?(Array)
        contas << n
      end
      pico = 0
      contas.each_with_index { |n, i| pico = i if n > contas[pico].to_i }
      impacto = [pico - 2, 0].max
      fim_voo = (pico > 0) ? pico : obj.length

      # ⚠️ PARA UMA PARTICULA NAO HA "VOO" ONDE PROCURAR.
      #
      # Eu media apenas as celulas dos quadros ANTES do rebentamento, porque e
      # de la que sai a coisa que viaja. Num golpe como o Earthquake ou o Make
      # It Rain o rebentamento e logo no principio — sobravam um ou dois quadros
      # para medir, muitas vezes nenhum, e o cartao saia vazio.
      #
      # Uma particula so precisa de UMA celula representativa, venha ela de onde
      # vier. Quando o cartao e para particulas, olha-se a animacao toda.
      ate_onde = pequeno ? obj.length : fim_voo
      uso = Hash.new(0)
      ate_onde.times do |i|
        quadro = obj[i]
        next unless quadro.is_a?(Array)
        quadro.each { |cel| uso[cel[AnimFrame::PATTERN].to_i] += 1 if celula_visivel?(cel) }
      end
      caixas = {}
      uso.keys.sort_by { |pd| -uso[pd] }[0, MAX_PADROES].each do |pd|
        cx = caixa_do_padrao(bmp, pd)
        next unless cx
        # ⚠️ O FILTRO DE "CELULA CHEIA" NAO VALE PARA AS PARTICULAS.
        #
        # Para um projectil normal, uma celula que enche os 192x192 e clarao de
        # fundo e deita-se fora. Mas as pedras do Earthquake SAO desenhadas
        # assim — grandes, porque no palco de batalha elas ocupam o ecra. Ao
        # rejeita-las eu ficava sem nenhuma celula e o terremoto saia sem pedra
        # nenhuma, que foi o que o jogador viu. Aqui elas servem: encolhem-se
        # para 22 px e viram particula.
        next if !pequeno && cx[2] >= CEL_ANIM * 0.85 && cx[3] >= CEL_ANIM * 0.85
        caixas[pd] = cx
      end

      # (c) o flip-book: a maior celula de cada quadro do voo
      passos = []
      ultimo = nil
      fim_voo.times do |i|
        quadro = obj[i]
        next unless quadro.is_a?(Array)
        melhor = nil
        melhor_area = 0.0
        quadro.each do |cel|
          next unless celula_visivel?(cel)
          cx = caixas[cel[AnimFrame::PATTERN].to_i]
          next unless cx
          zoom = (cel[AnimFrame::ZOOMX].to_i.abs / 100.0)
          zoom = 1.0 if zoom <= 0.0
          area = cx[2] * cx[3] * zoom
          if area > melhor_area
            melhor_area = area
            melhor = [cel[AnimFrame::PATTERN].to_i, cx]
          end
        end
        next unless melhor
        next if ultimo == melhor[0]
        ultimo = melhor[0]
        passos << { :p => melhor[0], :cx => melhor[1] }
      end

      # Sem voo aproveitavel, leva-se a maior celula da animacao inteira: e
      # melhor uma bola parada do que nada nenhum a atravessar o mapa.
      if passos.empty? && !caixas.empty?
        maior = caixas.max_by { |_, cx| cx[2] * cx[3] }
        passos << { :p => maior[0], :cx => maior[1] }
      end

      # ⚠️ NEM A MAIOR NEM A MAIS PEQUENA: A DO MEIO.
      #
      # A maior e o molho de folhas todo (foi o primeiro erro). A mais pequena
      # e um fragmento ou uma faisca de nada — foi o que ficou a voar depois, e
      # e por isso que a folha parecia "uma folha normal" e nao a navalha. A
      # mediana das celulas medidas e, quase sempre, o desenho de UMA folha:
      # e o que o autor da animacao repetiu varias vezes.
      # A escolha a mao vence tudo o resto — mas so se a celula existir mesmo
      # na folha; se nao existir, cai-se na regra normal em vez de ficar sem
      # particula nenhuma.
      if padrao_fixo
        cx_fixa = caixa_do_padrao(bmp, padrao_fixo.to_i)
        passos = [{ :p => padrao_fixo.to_i, :cx => cx_fixa }] if cx_fixa
      end

      if pequeno && !caixas.empty? && !padrao_fixo
        uteis = caixas.select { |_, cx| cx[2] >= 10 && cx[3] >= 10 }
        uteis = caixas if uteis.empty?
        ordenadas = uteis.sort_by { |_, cx| cx[2] * cx[3] }
        meio = ordenadas[ordenadas.length / 2]
        passos = [{ :p => meio[0], :cx => meio[1] }]
      end

      if passos.empty?
        (bmp.dispose rescue nil)
        registar("projectil sem celula util (anim #{anim} folha=#{folha} " \
                 "pequeno=#{pequeno} quadros=#{obj.length} caixas=#{caixas.length})")
        nil
      else
        lado = passos.map { |pa| [pa[:cx][2], pa[:cx][3]].max }.max.to_f
        lado = CEL_ANIM.to_f if lado <= 0
        alvo_px = pequeno ? TAMANHO_FOLHA : PROJ_TAMANHO
        cart = { :bmp => bmp, :passos => passos, :escala => (alvo_px / lado),
                 :impacto => impacto }
        registar("cartao anim=#{anim} folha=#{folha} pequeno=#{pequeno} " \
                 "caixas=#{caixas.length} passos=#{passos.length} " \
                 "pico=#{pico} impacto=#{impacto} lado=#{lado.round} " \
                 "em #{((Time.now.to_f - t0) * 1000).round}ms")
        cart
      end
    rescue => e
      registar("projectil sem imagem (anim #{anim}): #{e.class}: #{e.message}")
      nil
    end
  end

  def aplicar_passo!(sp, cart, passo)
    cx = passo[:cx]
    pd = passo[:p]
    sp.src_rect.set(((pd % 5) * CEL_ANIM) + cx[0], ((pd / 5) * CEL_ANIM) + cx[1], cx[2], cx[3])
    sp.ox = cx[2] / 2
    sp.oy = cx[3] / 2
    sp.zoom_x = cart[:escala]
    sp.zoom_y = cart[:escala]
  rescue
    nil
  end

  def sprite_do_projectil(anim, pequeno = false, padrao_fixo = nil)
    cart = cartao_do_projectil(anim, pequeno, padrao_fixo)
    return nil unless cart
    sp = Sprite.new(viewport_das_animacoes)
    # ⚠️ O bitmap e da cache dos cartoes e e PARTILHADO: deita-se fora o sprite,
    # nunca o bitmap. Quem o deitar fora aqui apaga a bola de todos os golpes
    # seguintes.
    sp.bitmap = cart[:bmp]
    aplicar_passo!(sp, cart, cart[:passos][0])
    sp
  rescue => e
    registar("falha a criar sprite do projectil: #{e.class}: #{e.message}")
    nil
  end

  # ⚠️ COR POR TIPO — E UMA TABELA DE PINTURA, NAO DE REGRAS.
  #
  # Em todo o resto eu evitei listas e li as familias dos dados. Aqui nao ha o
  # que ler: o motor nao guarda uma cor por tipo, e nenhuma regra a deduz. Como
  # isto so decide o brilho de um sprite, uma tabela e honesta — se faltar um
  # tipo, o projectil fica sem pulso e mais nada se parte.
  COR_DO_TIPO = {
    :NORMAL => [200, 200, 180], :FIRE => [255, 110, 40],  :WATER => [70, 150, 255],
    :ELECTRIC => [255, 220, 60], :GRASS => [110, 220, 100], :ICE => [140, 225, 255],
    :FIGHTING => [220, 90, 60],  :POISON => [180, 90, 200], :GROUND => [210, 175, 100],
    :FLYING => [170, 190, 255],  :PSYCHIC => [255, 110, 170], :BUG => [170, 210, 70],
    :ROCK => [190, 165, 110],    :GHOST => [130, 100, 190], :DRAGON => [110, 110, 240],
    :DARK => [110, 90, 90],      :STEEL => [180, 190, 200], :FAIRY => [255, 160, 220]
  }.freeze

  PROJ_GIRO   = 1.4    # voltas por segundo
  PROJ_PULSO  = 5.0    # batidas por segundo
  PROJ_BRILHO = 90     # alfa maximo do pulso

  # O flip-book anda ao ritmo do motor das animacoes, em ciclo: a navalha do Air
  # Cutter gira enquanto atravessa o mapa. Por cima disso a coisa roda sobre si
  # propria e pulsa na cor do tipo — e o que separa uma bola a deslizar de uma
  # bola LANCADA.
  def animar_projectil!(p)
    cart = p[:cartao]
    sp = p[:sp]
    return unless sp && !(sp.disposed? rescue true)

    unless p[:bola]
      sp.angle = (sp.angle - (360.0 * (p[:giro] || PROJ_GIRO) * (@delta || (1.0 / 60.0)))) % 360
      cor = p[:cor] ||= (COR_DO_TIPO[(GameData::Move.get(p[:move_id]).type rescue nil)] || [255, 255, 255])
      alfa = (PROJ_BRILHO * ((Math.sin(p[:tempo].to_f * PROJ_PULSO * Math::PI) + 1.0) / 2.0)).to_i
      (sp.color.set(cor[0], cor[1], cor[2], alfa) rescue nil)
    end

    return unless cart
    passos = cart[:passos]
    return if passos.length <= 1
    i = (p[:tempo].to_f * CADENCIA_ANIM).to_i % passos.length
    return if i == p[:passo]
    p[:passo] = i
    aplicar_passo!(sp, cart, passos[i])
  rescue
    nil
  end

  # ⚠️ NEM TUDO O QUE VOA OBEDECE A PEDRA.
  #
  # O arco passa POR CIMA: um Rock Slide ou um Toxic Spikes sao atirados ao ar
  # e caem no destino, e uma parede pelo caminho nao os devia parar. O mesmo
  # vale para as copias que sao so desenho — elas nao magoam ninguem, e
  # apaga-las a meio deixava um golpe pela metade no ecra de quem leva.
  # Uma casa por onde nao se anda: parede, agua, desnivel, fora do mapa. E a
  # mesma pergunta que o `casa_livre_perto` faz quando poe alguem a nascer, e
  # por isso as duas concordam sobre o que e chao.
  # ⚠️ ISTO CORRIA MILHARES DE VEZES POR SEGUNDO, E O MAPA NAO MUDA.
  #
  # Cada pergunta faz ate cinco consultas ao mapa (o terreno e as quatro
  # direccoes). A linha de vista pergunta por cada meia casa, e era chamada
  # duas vezes por bicho por frame — com tres bichos dava perto de mil
  # consultas por frame, so para saber uma coisa que e sempre a mesma: se
  # aquela casa e pedra.
  #
  # A resposta guarda-se, com a chave do mapa por perto: mudar de mapa deita a
  # tabela fora. Nao ha caso nenhum em que uma parede se torne chao a meio de
  # uma sessao — e se houvesse (um evento a abrir passagem), era so limpar isto
  # nesse momento.
  # ⚠️ E NA AGUA NAO VOAVA NADA — NEM UMA POKEBOLA.
  #
  # O `calcular_pedra?` pergunta ao `terreno_proibido?`, que trata agua como
  # parede. Isso e certo para os selvagens de terra, e foi para eles que a regra
  # foi escrita. Mas o voo de um projectil passa pelo MESMO metodo: a surfar,
  # todas as casas a volta sao agua, e cada golpe — e cada bola — morria no
  # primeiro passo, a um pixel de quem o lancou.
  #
  # Visto de dentro do jogo nao ha sequer um tiro falhado: nao sai nada. Era o
  # "dentro dagua nao ta lancando a pokebola automatica, nem apertando Q".
  #
  # A surfar, a agua e o chao: nao e pedra para nada. E como a resposta muda com
  # o estado do surf, a memoria tem de ser esquecida quando ele muda — senao
  # entrava-se na agua com as respostas de terra guardadas.
  def casa_de_pedra?(tx, ty)
    id = ($game_map.map_id rescue 0)
    mar = a_surfar?
    if @pedra_mapa != id || @pedra_surf != mar
      @pedra_mapa = id
      @pedra_surf = mar
      @pedra = {}
    end
    chave = (tx << 12) | (ty & 0xfff)
    r = @pedra[chave]
    return r unless r.nil?
    @pedra[chave] = calcular_pedra?(tx, ty)
  rescue
    false
  end

  # ⚠️ EU TAPEI A ETIQUETA E DEIXEI A LINHA SEGUINTE ABERTA.
  #
  # A ronda passada tirei a agua do `terreno_proibido?` quando se surfa, e isso
  # era preciso — mas nao chegava, e o utilizador mostrou-o com um print: a bola
  # bate numa parede invisivel a meio do lago.
  #
  # A linha que a mata e esta:
  #
  #     ![2, 4, 6, 8].any? { |d| $game_map.passable?(tx, ty, d) }
  #
  # O `passable?` le as passagens do TILESET, e no tileset a agua e
  # intransponivel — e exactamente por isso que ela precisa de Surf. Portanto
  # numa casa de agua ele responde "nao" as quatro direccoes, o `!` transforma
  # isso em "e pedra", e o projectil morre ali.
  #
  # A surfar, uma casa de agua e chao e acabou. O `passable?` so continua a
  # mandar em terra — onde ele esta certo, e onde uma parede e mesmo uma parede.
  def calcular_pedra?(tx, ty)
    return true unless ($game_map.valid?(tx, ty) rescue false)
    if a_surfar?
      return false if agua?(tx, ty)
      return ![2, 4, 6, 8].any? { |d| ($game_map.passable?(tx, ty, d) rescue false) }
    end
    return true if terreno_proibido?(tx, ty)
    ![2, 4, 6, 8].any? { |d| ($game_map.passable?(tx, ty, d) rescue false) }
  rescue
    false
  end

  # ⚠️ VER O ALVO E PODER TRACAR UMA LINHA ATE ELE SEM TOCAR EM PEDRA.
  #
  # Anda-se a linha de meia casa em meia casa. Meia casa e o passo certo: com
  # uma casa inteira passa-se por cima de uma parede fina na diagonal, e com
  # menos gasta-se tempo a confirmar o que ja se sabe.
  PASSO_VISTA = 0.5

  # ⚠️ E A PROPRIA RESPOSTA SO PRECISA DE SER REFEITA DE VEZ EM QUANDO.
  #
  # Entre dois frames ninguem anda meia casa: refazer a linha sessenta vezes
  # por segundo e gastar tempo para obter o mesmo resultado. Um quinto de
  # segundo e curto o suficiente para nao se notar (o bicho reage a dobrar uma
  # esquina em 12 frames) e longo o suficiente para o custo desaparecer.
  VISTA_VALIDADE = 0.2

  def vista_livre_cache?(a, b, chave)
    agora = Time.now.to_f
    @vistas ||= {}
    guardado = @vistas[chave]
    return guardado[1] if guardado && agora < guardado[0]
    r = vista_livre?(a, b)
    @vistas[chave] = [agora + VISTA_VALIDADE, r]
    r
  rescue
    true
  end

  def vista_livre?(a, b)
    return false unless a && b
    ax = (a.instance_variable_get(:@real_x).to_f / Game_Map::REAL_RES_X)
    ay = (a.instance_variable_get(:@real_y).to_f / Game_Map::REAL_RES_Y)
    bx = (b.instance_variable_get(:@real_x).to_f / Game_Map::REAL_RES_X)
    by = (b.instance_variable_get(:@real_y).to_f / Game_Map::REAL_RES_Y)
    dx = bx - ax
    dy = by - ay
    n = Math.sqrt((dx * dx) + (dy * dy))
    return true if n < PASSO_VISTA
    passos = (n / PASSO_VISTA).ceil
    ux = dx / passos
    uy = dy / passos
    (1...passos).each do |i|
      return false if casa_de_pedra?((ax + (ux * i)).round, (ay + (uy * i)).round)
    end
    true
  rescue
    true
  end

  #-----------------------------------------------------------------------------
  # O CAMPO DE CAMINHOS
  #
  # ⚠️ "DESVIAR" E "TER UM CAMINHO" NAO SAO A MESMA COISA, E EU SO TINHA O
  # PRIMEIRO.
  #
  # Ate aqui, um bicho sem vista do alvo tentava o eixo que mais faltava, depois
  # o outro, e por fim um passo de lado (`contornar!`) guardado por meio
  # segundo. Isso e um desvio LOCAL: ele so sabe o que tem a um passo de
  # distancia, e portanto so sabe resolver obstaculos do tamanho de um passo.
  #
  # Contra uma parede a serio o comportamento e sempre o mesmo e e o que se
  # relatou: o eixo que aponta ao alvo fica bloqueado, o outro continua livre, e
  # ele desliza ao longo da pedra com a cara colada ate a parede acabar. Se ela
  # nao acabar — um beco, uma quina em L, um pilar com o alvo do outro lado —
  # ele oscila ali para sempre, porque a um passo de distancia as duas hipoteses
  # sao igualmente mas.
  #
  # Nenhuma afinacao do desvio local resolve isto. O que falta e a informacao:
  # ele precisa de saber a que distancia REAL do alvo fica cada casa a volta,
  # dando a volta a pedra. Com isso, contornar deixa de ser um palpite e passa a
  # ser "ir para a casa vizinha que esta mais perto pelo caminho".
  #
  # ⚠️ E O CAMPO E DO ALVO, NAO DO BICHO — E DAI ELE SER BARATO.
  #
  # A conta faz-se uma vez A PARTIR do alvo e serve TODOS os bichos que andam
  # atras dele. Numa caverna com quinze selvagens em cima de nos e uma conta,
  # nao quinze. Feita duas vezes por segundo, sobre as 29x29 casas que cabem na
  # vista, custa menos do que os testes de colisao que ja se faziam.
  #
  # ⚠️ E A PAREDE CUSTA CARO DE PROPOSITO.
  #
  # Um caminho pelo mais curto passa colado a pedra — porque o mais curto e
  # mesmo por ai. Visto de fora continua a ser um bicho a raspar na parede, so
  # que agora com razao. Cada casa encostada a pedra custa CAMPO_ENCOSTO passos
  # a mais, portanto ele so se encosta quando isso lhe poupa mais do que isso:
  # num corredor estreito passa na mesma (nao ha alternativa), em campo aberto
  # anda pelo meio.
  #-----------------------------------------------------------------------------
  # ⚠️ O RAIO E O DO ECRA, NAO O DA VISTA. E A DIFERENCA CUSTA METADE DO TEMPO.
  #
  # O primeiro valor foi 14, para bater certo com o `VISTA_TICK`. Medido, um
  # campo de 29x29 leva 2,9 ms — quase um quinto de um frame, duas vezes por
  # segundo e por alvo. Nao parte nada, mas e um solavanco que nao se paga.
  #
  # O ecra tem 16x12 casas, portanto do alvo ate ao canto vao 10. Um bicho mais
  # longe do que isso nao se ve a contornar coisa nenhuma — e a 11 o campo ja
  # cobre tudo o que esta em cena e custa 1,9 ms. Quem ficar de fora cai no
  # desvio local de sempre, que e o que ele tinha antes disto existir.
  CAMPO_RAIO      = 11     # casas a volta do alvo (o ecra tem 16x12)
  CAMPO_VALIDADE  = 0.45   # segundos que o campo serve antes de se refazer
  CAMPO_ENCOSTO   = 3      # passos de castigo por casa encostada a pedra
  CAMPO_CASAS_MAX = 600    # tecto de seguranca: 23x23 e 529

  VIZINHOS_4 = [[1, 0], [-1, 0], [0, 1], [0, -1]].freeze
  VIZINHOS_8 = [[1, 0], [-1, 0], [0, 1], [0, -1],
                [1, 1], [1, -1], [-1, 1], [-1, -1]].freeze

  # ⚠️ Escrito a mao, sem o `VIZINHOS_8.each`: e a pergunta mais repetida do
  # campo inteiro, e cada volta do ciclo custava um bloco e um par desfeito.
  def casa_encostada?(x, y)
    e = x - 1
    d = x + 1
    c = y - 1
    b = y + 1
    casa_de_pedra?(d, y) || casa_de_pedra?(e, y) ||
      casa_de_pedra?(x, b) || casa_de_pedra?(x, c) ||
      casa_de_pedra?(d, b) || casa_de_pedra?(d, c) ||
      casa_de_pedra?(e, b) || casa_de_pedra?(e, c)
  rescue
    false
  end

  # Dijkstra com baldes: os custos sao inteiros pequenos (1 ou 1+CAMPO_ENCOSTO),
  # portanto um vector de listas indexado pelo custo faz de fila de prioridade
  # sem precisar de arvore nenhuma.
  def calcular_campo(cx, cy)
    custo = {}
    return custo if casa_de_pedra?(cx, cy)
    raiz = (cx << 12) | (cy & 0xfff)
    custo[raiz] = 0
    baldes = [[raiz]]
    v = 0
    vistas = 0
    # ⚠️ O CASTIGO MEDE-SE UMA VEZ POR CASA, NAO UMA VEZ POR VISITA.
    #
    # Cada casa e alcancada pelos quatro lados, e o `casa_encostada?` faz oito
    # perguntas de cada vez: sao 32 perguntas por casa para obter sempre a mesma
    # resposta. Medido nas 29x29 casas com pilares, so isto levava o campo de
    # 7,3 ms para 1,4 — e 7 ms e meio frame.
    castigo = {}
    while v < baldes.length
      fila = baldes[v]
      if fila.nil? || fila.empty?
        v += 1
        next
      end
      k = fila.pop
      # Entrada velha: esta casa ja foi alcancada por mais barato.
      next unless custo[k] == v
      vistas += 1
      break if vistas > CAMPO_CASAS_MAX
      x = k >> 12
      y = k & 0xfff
      VIZINHOS_4.each do |(ox, oy)|
        nx = x + ox
        ny = y + oy
        next if (nx - cx).abs > CAMPO_RAIO || (ny - cy).abs > CAMPO_RAIO
        next if casa_de_pedra?(nx, ny)
        nk = (nx << 12) | (ny & 0xfff)
        c = castigo[nk]
        if c.nil?
          c = casa_encostada?(nx, ny) ? CAMPO_ENCOSTO : 0
          castigo[nk] = c
        end
        nv = v + 1 + c
        ja = custo[nk]
        next if ja && ja <= nv
        custo[nk] = nv
        (baldes[nv] ||= []) << nk
      end
    end
    custo
  rescue
    {}
  end

  # O campo deste alvo, refeito quando envelhece ou quando ele muda de casa.
  def campo_do_alvo(alvo)
    return nil unless alvo
    agora = Time.now.to_f
    mapa = ($game_map.map_id rescue 0)
    cx = alvo.x
    cy = alvo.y
    @campos ||= {}
    c = @campos[alvo.object_id]
    return c[4] if c && c[0] > agora && c[1] == cx && c[2] == cy && c[3] == mapa
    campo = calcular_campo(cx, cy)
    # Alvos morrem e nascem; a chave e o object_id e nao ha quem a limpe.
    @campos = {} if @campos.length > 8
    @campos[alvo.object_id] = [agora + CAMPO_VALIDADE, cx, cy, mapa, campo]
    campo
  rescue
    nil
  end

  # Para onde ir para chegar mais perto PELO CAMINHO. Devolve um rumo unitario
  # apontado ao centro da casa escolhida — apontar ao centro e o que o poe a
  # andar pelo meio do corredor em vez de pela borda.
  def rumo_do_campo(ev, alvo, rx, ry)
    custo = campo_do_alvo(alvo)
    return nil if custo.nil? || custo.empty?
    x = ev.x
    y = ev.y
    melhor = nil
    melhor_v = custo[(x << 12) | (y & 0xfff)]
    VIZINHOS_8.each do |(ox, oy)|
      nx = x + ox
      ny = y + oy
      next if casa_de_pedra?(nx, ny)
      # Na diagonal so se as duas ortogonais tambem estiverem livres: senao ele
      # corta a quina e volta a raspar nela, que e o defeito que se veio tirar.
      if ox != 0 && oy != 0
        next if casa_de_pedra?(x + ox, y) || casa_de_pedra?(x, y + oy)
      end
      v = custo[(nx << 12) | (ny & 0xfff)]
      next if v.nil?
      next if melhor_v && v >= melhor_v
      melhor_v = v
      melhor = [nx, ny]
    end
    return nil unless melhor
    ax = (melhor[0] * Game_Map::REAL_RES_X) - rx
    ay = (melhor[1] * Game_Map::REAL_RES_Y) - ry
    n = Math.sqrt((ax * ax) + (ay * ay))
    return nil if n < 0.001
    [ax / n, ay / n]
  rescue
    nil
  end

  def parede_no_voo?(p, ax, ay)
    return false if p[:arco]
    return false if p[:so_desenho]
    # ⚠️ UMA BOLA E ATIRADA POR CIMA, NAO DISPARADA A DIREITO.
    #
    # A regra da pedra existe para os GOLPES: um jacto de agua nao atravessa a
    # parede da caverna, e e isso que faz valer a pena posicionar-se. Uma
    # Pokebola nao e um golpe — e um objecto que se lanca em arco, e um
    # treinador atira-a por cima de um arbusto sem pensar duas vezes.
    #
    # Com a regra aplicada, ela parava no primeiro tronco entre nos e o bicho, e
    # o "a bola errou" nao tinha nada que ver com pontaria: tinha que ver com a
    # arvore que estava no caminho. Num mapa de relva alta isso e quase sempre.
    #
    # O `:arco` acima ja isenta as particulas que sobem; a bola voa rasa por
    # causa do desenho (o arco dela e feito no `posicionar_projectil!`, subindo
    # o sprite), portanto precisa da isencao dita por extenso.
    return false if p[:bola]
    tx = p[:x].round
    ty = p[:y].round
    return false if tx == ax.round && ty == ay.round
    casa_de_pedra?(tx, ty)
  rescue
    false
  end

  # ⚠️ O MODO DO EDITOR SO VALIA PARA MIM. OS OUTROS TRES IGNORAVAM-NO.
  #
  # O `usar_golpe!` — o meu botao — le o `modo` do palco e, se disser "feixe",
  # desenha a linha e nao lanca nada. Bom. So que ha mais tres sitios de onde
  # saem golpes: o selvagem (`atacar_ia!`), o ajudante (`atacar_aliado!`) e a
  # copia do golpe do outro jogador. Esses perguntavam so `lancamento?(mv)` —
  # uma funcao que olha para a tabela do PBS e nunca para o editor.
  #
  # Resultado, e e exactamente o que se viu no BubbleBeam: eu disparo e sai um
  # feixe; o inimigo dispara o MESMO golpe e sai uma bola a voar, e so quando
  # ela bate e que aparecem as bolhas. O log conta a historia toda —
  # "lancou BUBBLEBEAM ... sprite=sim" seguido de "tocar: OK idx=80" — e nao ha
  # uma unica linha de `golpe BUBBLEBEAM: modo_editor=` porque o meu botao nunca
  # esteve envolvido.
  #
  # Nao era leitura nenhuma a falhar. O ficheiro esta certo, o `palco_da_anim`
  # devolve "feixe"; o que faltava era estes caminhos fazerem a pergunta.
  # ⚠️ COMO UM GOLPE SAI NAO PODE DEPENDER DE QUEM O DEU.
  #
  # Havia quatro routers diferentes — um por dono. O meu botao perguntava ao
  # editor; o selvagem, o ajudante e a copia do outro jogador perguntavam so
  # `lancamento?(mv)`, que le a tabela do PBS e nunca a oficina. Por isso o
  # mesmo BubbleBeam era um feixe nas minhas maos e uma bola a voar nas do
  # ajudante.
  #
  # Nao foi uma decisao: foi o meu botao ter aprendido os modos do editor e os
  # outros tres terem ficado como estavam. Um golpe editado tem de sair igual,
  # seja quem for que o use — e isso quer dizer UMA funcao, e nao quatro
  # concordarem por acaso.
  #
  # A ordem e a que o meu botao ja usava, agora escrita uma vez:
  #
  #   feixe   a oficina marcou "feixe a frente"        -> linha, nada voa
  #   voo     "onde o golpe acertar" / "a animacao voa" -> projectil
  #           ... ou a tabela do PBS diz que e arremesso
  #   perto   o resto                                   -> acontece onde esta
  #
  # O "feixe" ganha de propósito: quem marcou a animacao como uma linha esta a
  # dizer que o golpe E a linha, e isso vale mais do que o palpite da tabela.
  def saida_do_golpe(mv, anim)
    modo = (palco_da_anim(anim) || {})["modo"].to_s
    return :feixe if modo == "feixe" && anim.to_i > 0
    return :voo   if modo == "voo" || modo == "voo_anim"
    return :voo   if lancamento?(mv)
    :perto
  rescue
    :perto
  end

  def feixe_do_editor?(anim)
    (palco_da_anim(anim) || {})["modo"].to_s == "feixe"
  rescue
    false
  end

  # Desenha o feixe de quem NAO e o jogador: sai dele, vai na direccao do alvo,
  # e para no mais curto entre a distancia real e o alcance que o editor deu.
  def feixe_de_alguem!(ev, alvo, anim)
    return false if anim.to_i <= 0 || ev.nil?
    casas = ((palco_da_anim(anim) || {})["feixe_casas"] || ALCANCE_FEIXE).to_f
    ax = (alvo ? alvo.x.to_f : ev.x.to_f)
    ay = (alvo ? alvo.y.to_f : ev.y.to_f)
    dx = ax - ev.x
    dy = ay - ev.y
    n = Math.sqrt((dx * dx) + (dy * dy))
    if n < 0.001
      case (ev.direction rescue 2)
      when 8 then dx, dy, n = 0.0, -1.0, 1.0
      when 4 then dx, dy, n = -1.0, 0.0, 1.0
      when 6 then dx, dy, n = 1.0,  0.0, 1.0
      else        dx, dy, n = 0.0,  1.0, 1.0
      end
    end
    d = [n, casas].min
    d = 1.0 if d < 1.0
    tocar_no_ponto!(anim, ev.x + ((dx / n) * d), ev.y + ((dy / n) * d), 0, ev)
    true
  rescue
    false
  end

  def lancar!(o)
    x = o[:x].to_f
    y = o[:y].to_f
    alvo = o[:alvo]
    inf = o[:infalivel] ? true : false
    vel = (o[:vel] || (inf ? PROJ_VEL_MIRA : PROJ_VEL)).to_f
    # Aponta-se ao alvo desde o principio; sem alvo, segue-se a direccao em que
    # se olha, para o golpe sair na mesma e falhar de forma visivel.
    vx = 0.0
    vy = 0.0
    if alvo
      dx = (alvo.x.to_f - x)
      dy = (alvo.y.to_f - y)
      d = Math.sqrt((dx * dx) + (dy * dy))
      if d > 0.001
        vx = dx / d
        vy = dy / d
      end
    end
    if vx == 0.0 && vy == 0.0
      case o[:dir].to_i
      when 2 then vy = 1.0
      when 8 then vy = -1.0
      when 4 then vx = -1.0
      else        vx = 1.0
      end
    end
    # Um rumo dado a mao (as pedras de uma onda saem em roda).
    if o[:ux] || o[:uy]
      vx = o[:ux].to_f
      vy = o[:uy].to_f
      n3 = Math.sqrt((vx * vx) + (vy * vy))
      if n3 > 0.001
        vx /= n3
        vy /= n3
      end
    end
    # ⚠️ O ARCO E O QUE FAZ AS FOLHAS "SUBIREM".
    #
    # Uma particula que parte ja apontada ao alvo desliza em linha recta e
    # parece um tiro de laser. Estas partem para CIMA, com uma abertura ao
    # acaso, e so a meio caminho e que a perseguicao as vira — o que se ve e um
    # punhado a saltar do Pokemon e a cair sobre quem esta a frente.
    if o[:arco]
      vx = (rand - 0.5) * 1.4
      vy = -1.0
      n2 = Math.sqrt((vx * vx) + (vy * vy))
      vx /= n2
      vy /= n2
    end
    # ⚠️ A MIRA SO PODE TIRAR, NUNCA POR.
    #
    # Quem decide se um golpe persegue e a precisao dele: 100% quer dizer que
    # nao erra, e isso traduz-se em perseguicao perfeita. O `mira` do editor
    # entra como um VETO por cima disso — desligado, o golpe deixa de perseguir
    # e passa a poder falhar.
    #
    # Nao faz o contrario de proposito. Das duzentas animacoes, 152 tem o `mira`
    # ligado — se ele pudesse LIGAR a perseguicao, cento e cinquenta e dois
    # golpes que hoje se desviam passavam a acertar sempre, de um dia para o
    # outro, sem ninguem ter pedido isso. As 49 que o tem desligado foram
    # desligadas a mao, e e essa a intencao que se respeita.
    cfg_palco = (o[:move_id] ? (palco_da_anim(animacao_do_golpe(o[:move_id])) rescue nil) : nil)
    if cfg_palco && cfg_palco.key?("mira") && !cfg_palco["mira"]
      inf = false
    end
    # A correccao de rumo, se o editor a tiver afinado.
    viragem = (cfg_palco && cfg_palco["viragem"].to_f > 0.01) ? cfg_palco["viragem"].to_f : nil
    p = {
      :x => x, :y => y, :vx => vx * vel, :vy => vy * vel, :vel => vel,
      :alvo => alvo, :infalivel => inf, :anim => o[:anim].to_i,
      :viragem => viragem, :rastro => (cfg_palco ? cfg_palco["rastro"].to_i : 0),
      :rastro_forca => (cfg_palco ? cfg_palco["rastro_forca"].to_f : 0.0),
      :move_id => o[:move_id], :mv => o[:mv], :nome => o[:nome].to_s,
      :meu => (o[:meu] ? true : false), :pacote => o[:pacote],
      :ia => (o[:ia] ? true : false),
      # ⚠️ O LADO NAO SE ADIVINHA PELO `:meu`, E FOI ESSA A ARMADILHA.
      #
      # A copia visivel de um golpe que vem contra mim nasce com `:meu => true`
      # — porque quem a desenha sou eu, na minha maquina. Quem lesse o `:meu`
      # para saber de que lado esta o golpe punha as particulas do inimigo do
      # meu lado e elas nunca embatiam em nada. O lado e um campo proprio, posto
      # por quem lanca, que e o unico que sabe a verdade.
      :lado => (o[:lado] || ((o[:ia] || o[:pacote]) ? :deles : :nosso)),
      :andado => 0.0, :acertou => false, :tempo => 0.0, :passo => 0,
      :alcance => (o[:alcance] || PROJ_ALCANCE).to_f, :curto => (o[:curto] ? true : false),
      :dist_total => (alvo ? Math.sqrt(((alvo.x - x)**2) + ((alvo.y - y)**2)) : 4.0),
      :raio => o[:raio].to_f, :bicho => o[:bicho], :bola => o[:bola],
      :evento_shiny => o[:evento_shiny],
      :aliado => (o[:aliado] ? true : false), :no_aliado => (o[:no_aliado] ? true : false),
      :so_desenho => (o[:so_desenho] ? true : false),
      :cartao => (o[:invisivel] ? nil : cartao_do_projectil((o[:cartao_de] || o[:anim]).to_i, o[:pequeno], PARTICULA_FIXA[o[:move_id]])),
      :arco => (o[:arco] ? true : false), :forca => o[:forca],
      :vagueia => o[:vagueia].to_f, :fase => (rand * 6.28),
      :giro => (o[:giro] || PROJ_GIRO).to_f,
      :sp => (o[:invisivel] ? nil : (o[:sp_pronto] || sprite_do_projectil((o[:cartao_de] || o[:anim]).to_i, o[:pequeno], PARTICULA_FIXA[o[:move_id]])))
    }
    posicionar_projectil!(p)
    montar_rasto!(p)
    (@projecteis ||= []) << p
    # ⚠️ AS COPIAS SAO IRMAS DO SPRITE PRINCIPAL, E NAO SUBSTITUTAS.
    #
    # O `p[:sp]` continua a ser o que ja era: a particula da frente. As copias
    # sao sprites a mais, com o MESMO bitmap — nao se recorta nem se carrega
    # nada de novo, so se desenha o mesmo pedaco em varios sitios. Assim uma
    # receita de seis copias custa seis posicoes por frame, e nao seis
    # recortes.
    #
    # Sem receita, `quantas` e 1 e nao se cria copia nenhuma: quem nao abriu o
    # editor tem exactamente o jogo de antes.
    p[:receita] = receita_da_anim(o[:anim])
    p[:nascido] = Time.now.to_f
    if p[:receita] && p[:sp]
      n = receita_normal(p[:receita])["quantas"].to_i
      if n > 1
        p[:copias] = []
        (n - 1).times do
          c = Sprite.new(viewport_das_animacoes)
          c.bitmap = p[:sp].bitmap        # partilhado de proposito
          c.src_rect = p[:sp].src_rect.dup rescue nil
          c.ox = p[:sp].ox
          c.oy = p[:sp].oy
          c.blend_type = p[:sp].blend_type
          p[:copias] << c
        end
      end
    end

    registar("lancou #{o[:move_id]} de (#{x.round},#{y.round}) infalivel=#{inf} alvo=#{alvo ? "(#{alvo.x},#{alvo.y})" : "nenhum"} sprite=#{p[:sp] ? "sim" : "NAO"} copias=#{(p[:copias] || []).length}")
  rescue => e
    registar("falha a lancar: #{e.class}: #{e.message}")
  end

  #-----------------------------------------------------------------------------
  # OS REMENDOS DO EDITOR
  #
  # O editor de ataques (ferramentas/editor_ataques.py) grava aqui o que se
  # afinou golpe a golpe: quantas particulas voam, se giram, se flutuam, e a
  # partir de que quadro a animacao rebenta.
  #
  # ⚠️ LE-SE O .json DIRECTAMENTE — E NAO, ISSO NAO PRECISA DE BIBLIOTECA.
  #
  # A minha primeira versao convertia o .json num Marshal, com medo do Android:
  # la nao ha `require "json"`, e um `require` que falha so no telemovel e o
  # pior tipo de erro que ha.
  #
  # So que este jogo JA resolveu esse problema uma vez. O MOD das montarias tem
  # um leitor de JSON escrito a mao — `AnilMontariaJSON.parse` — precisamente
  # por isto, e ele le o montarias.json em todos os aparelhos ha meses.
  #
  # Reaproveita-se. Assim ha UM ficheiro em vez de dois: o mesmo que o editor
  # grava e o que o jogo le, legivel, comparavel e sem passo de conversao pelo
  # meio para alguem se esquecer de correr.
  #
  # ⚠️ E SEM O FICHEIRO NAO ACONTECE NADA.
  #
  # Quem nunca abriu o editor tem o jogo exactamente como estava. Uma receita
  # vazia tambem: ela reproduz o comportamento de hoje por construcao, e por
  # isso pode ser aplicada a todos os golpes sem estragar nenhum.
  #-----------------------------------------------------------------------------
  REMENDOS_JSON = "Data/arena_animacoes.json"

  # ⚠️ O DIAGNOSTICO DISTO ESTAVA ATRAS DO INTERRUPTOR QUE NAO SE PODE LIGAR.
  #
  # Havia um `log("remendos do editor: N")` aqui — e ele nunca apareceu em lado
  # nenhum, porque o `AnilArena.log` desagua no log global do multijogador, que
  # esta desligado por desenho (ligar-lo parte o "recuperar partida"). Ou seja:
  # a unica linha que dizia se o ficheiro tinha sido lido era invisivel.
  #
  # Gastamos varias voltas a adivinhar entre "o updater sobrepoe", "um plugin
  # reverte" e "o jogo nao le" — quando o jogo podia simplesmente ter dito. Este
  # ficheiro nao depende de interruptor nenhum: e escrito sempre, tem uma
  # linha por leitura, e diz o que se leu e de onde.
  ESTADO_REMENDOS = "Data/arena_animacoes_estado.txt"

  def anotar_remendos!(quantas, motivo)
    return unless LOG_LIGADO
    caminho = File.expand_path(REMENDOS_JSON)
    existe = (File.exist?(REMENDOS_JSON) rescue false)
    tam = existe ? (File.size(REMENDOS_JSON) rescue -1) : -1
    quando = existe ? (File.mtime(REMENDOS_JSON).strftime("%Y-%m-%d %H:%M:%S") rescue "?") : "-"
    File.open(ESTADO_REMENDOS, "ab") do |f|
      f.write("[#{Time.now.strftime('%H:%M:%S')}] #{motivo}: #{quantas} animacao(oes)\n")
      f.write("    ficheiro: #{caminho}\n")
      f.write("    existe=#{existe} tamanho=#{tam} gravado_em=#{quando}\n")
      f.write("    parser AnilMontariaJSON: #{defined?(AnilMontariaJSON) ? 'sim' : 'NAO'}\n")
      # Duas animacoes de referencia, para se ver se o conteudo e o novo.
      [991, 672].each do |k|
        r = (@remendos || {})[k.to_s] || (@remendos || {})[k]
        if r.nil?
          f.write("    #{k}: sem remendo\n")
        else
          pal = r["palco"] || {}
          f.write("    #{k}: chaves=#{r.keys.inspect} modo=#{pal['modo'].inspect} " \
                  "desvio=#{pal['desvio_x'].inspect},#{pal['desvio_y'].inspect} " \
                  "escala=#{pal['escala'].inspect}\n")
        end
      end
    end
  rescue
    nil
  end

  def remendos
    return @remendos if @remendos
    motivo = "lido"
    # ⚠️ NUM TELEMOVEL ESTE FICHEIRO NAO EXISTE, E NUNCA PODIA EXISTIR.
    #
    # O updater entrega `Scripts.rxdata` e `PluginScripts.rxdata`, e mais nada
    # (ver `server_runtime.rb`, `/update/scripts`). O `arena_animacoes.json`
    # nao tem como viajar: o que esta no aparelho e o que veio na instalacao,
    # ou nada.
    #
    # Sem ele, `palco_da_anim` devolve nil para tudo, o `animador_novo?` diz
    # que nao, e cada golpe sai pela colocacao crua do Essentials. Foi isto:
    # "entrei pelo JoiPlay, mesmo atualizado, o wingattack ainda rodou o
    # antigo". O build estava certo; faltava-lhe a afinacao.
    #
    # O `gerar_remendos_embutidos.rb` escreve a mesma configuracao como um MOD,
    # portanto ela viaja dentro do Scripts.rxdata. Aqui escolhe-se entre as
    # duas pela DATA, e a regra e a que preserva o trabalho de quem edita:
    #
    #   disco mais novo que o build  ->  o disco (acabou de se gravar na oficina)
    #   disco mais velho, ou ausente ->  o embutido (e o do build, e o bom)
    embutido = nil
    if defined?(AnilArenaRemendosEmbutidos)
      disco = (File.exist?(REMENDOS_JSON) ? (File.mtime(REMENDOS_JSON).to_i rescue 0) : 0)
      if disco <= AnilArenaRemendosEmbutidos.gerado_em.to_i
        embutido = AnilArenaRemendosEmbutidos.texto rescue nil
      end
    end

    @remendos = begin
      if embutido
        motivo = "embutido no build"
        d = (AnilMontariaJSON.parse(embutido) rescue nil)
        d.is_a?(Hash) ? d : {}
      elsif !File.exist?(REMENDOS_JSON)
        motivo = "SEM FICHEIRO"
        {}
      elsif !defined?(AnilMontariaJSON)
        motivo = "SEM PARSER (AnilMontariaJSON ainda nao existe)"
        {}
      else
        texto = File.binread(REMENDOS_JSON).force_encoding("utf-8")
        d = AnilMontariaJSON.parse(texto)
        if d.is_a?(Hash)
          d
        else
          motivo = "PARSER DEVOLVEU #{d.class}"
          {}
        end
      end
    rescue => e
      # Um ficheiro estragado nao pode impedir a arena de correr: perde-se o
      # afinamento, nao a batalha.
      motivo = "ILEGIVEL (#{e.class}: #{e.message})"
      log("remendos ilegiveis, a seguir sem eles: #{e.class}: #{e.message}")
      {}
    end
    log("remendos do editor: #{@remendos.length} animacao(oes)")
    anotar_remendos!(@remendos.length, motivo)
    @remendos
  end

  # ⚠️ LIDOS UMA VEZ POR SESSAO, E ISSO TORNA O EDITOR INUTILIZAVEL.
  #
  # O `@remendos` e memorizado: le-se o JSON na primeira vez que alguem pergunta
  # e nunca mais. Faz sentido — sao duzentas animacoes e nao muda nada durante
  # uma partida.
  #
  # So que durante o AFINAMENTO muda a toda a hora. O ciclo real e: mexer no
  # editor, gravar, ver no jogo, corrigir. Com o ficheiro lido so ao arrancar, o
  # "ver no jogo" custa fechar e abrir o jogo de cada vez — e como o editor
  # tambem tinha um passo de copia que se podia esquecer, o que se via era
  # "gravei e nao mudou nada", tres vezes seguidas, sem nada a explicar porque.
  #
  # Isto larga tudo o que foi lido do ficheiro e tambem os cartoes — os recortes
  # das folhas que dependem da configuracao. Na pergunta seguinte tudo se
  # carrega de novo, do disco.
  def recarregar_remendos!
    antes = (@remendos ? @remendos.length : 0)
    @remendos = nil
    # Os cartoes sao recortes feitos a partir do palco de cada animacao: se o
    # palco muda, eles tem de ser refeitos, senao ve-se a configuracao nova com
    # o desenho velho.
    (@cartoes || {}).each_value { |c| (c[:bmp].dispose rescue nil) if c }
    @cartoes = {}
    (@cartoes_bola || {}).each_value { |b| (b.dispose rescue nil) if b }
    @cartoes_bola = {}
    depois = remendos.length
    log("remendos recarregados: #{antes} -> #{depois}")
    anotar_remendos!(depois, "recarregado pelo /anim")
    depois
  rescue => e
    log("falha a recarregar os remendos: #{e.class}: #{e.message}")
    -1
  end

  def remendo_da_anim(anim)
    remendos[anim.to_i.to_s] || remendos[anim.to_i]
  rescue
    nil
  end

  # ⚠️ UM GOLPE TEM DOIS MOMENTOS, E SO UM DELES TINHA TRATAMENTO.
  #
  # Havia uma receita, e ela so chegava ao que VOA. Um golpe que nao arremessa
  # nada — um feixe, um que rebenta em cima do alvo, um que se desenha sobre
  # quem lanca — nao tinha forma nenhuma de receber particulas: a receita
  # existia mas nao havia caminho por onde ela passasse.
  #
  # Sao agora duas. O PERCURSO e o que ja era (o que atravessa o mapa). O FINAL
  # e novo e vale em QUALQUER modo, porque se agarra a animacao e nao ao
  # projectil.
  #
  # A chave antiga continua a ser o percurso, portanto nada do que ja se gravou
  # muda de sentido.
  def receita_da_anim(anim)
    r = remendo_da_anim(anim)
    r && r["particula"]
  rescue
    nil
  end

  def receita_final_da_anim(anim)
    r = remendo_da_anim(anim)
    r && r["particula_final"]
  rescue
    nil
  end

  # Vale a pena montar particulas para esta receita?
  def receita_vale?(r)
    return false unless r.is_a?(Hash)
    n = receita_normal(r)
    # Uma copia so da animacao inteira e a animacao normal: nao vale o custo.
    return n["quantas"].to_i > 1 if n["inteira"]
    return true if n["quantas"].to_i > 1
    ["espalhar", "girar", "flutuar", "pulsar"].any? { |c| n[c].to_f.abs > 0.001 }
  rescue
    false
  end

  # A configuracao de palco: como esta animacao deve ser COLOCADA.
  #
  # O editor grava aqui o modo (o proprio, o alvo, uma casa, o voo, o feixe), o
  # alcance do feixe em casas, se ele acompanha o alvo, e se o fundo se esconde.
  def palco_da_anim(anim)
    r = remendo_da_anim(anim)
    (r && r["palco"]) || nil
  rescue
    nil
  end

  def impacto_desde_da_anim(anim)
    r = remendo_da_anim(anim)
    ((r && r["palco"] && r["palco"]["impacto_desde"]) || 0).to_i
  rescue
    0
  end

  #-----------------------------------------------------------------------------
  # A RECEITA, PASSO A PASSO
  #
  # ⚠️ ESTA CONTA E A MESMA QUE ESTA NO ferramentas/editor/particulas.py.
  #
  # Sao duas implementacoes da mesma regra, uma em Python e outra aqui. Elas
  # divergirem quer dizer que o editor passa a mostrar uma coisa que o jogo nao
  # faz — que e exactamente o que a ferramenta existe para evitar. Mexe-se nas
  # duas ao mesmo tempo, ou em nenhuma.
  #
  # Cada copia tem uma FASE fixa. Nao e sorteio: se as diferencas mudassem a
  # cada frame o efeito tremia, e se fossem iguais as copias sobrepunham-se e
  # via-se uma so.
  #-----------------------------------------------------------------------------
  # ⚠️ O QUE NAO ESTIVER AQUI E DEITADO FORA.
  #
  # O `receita_normal` copia da receita gravada apenas as chaves que existam
  # nesta tabela — e uma limpeza deliberada, para uma receita antiga nao trazer
  # lixo. Mas quer dizer que uma chave NOVA tem de ser acrescentada aqui, senao
  # ela e gravada pelo editor, viaja no remendo, e desaparece em silencio a um
  # passo de ser usada.
  RECEITA_OMISSAO = {
    "quantas" => 1, "tamanho" => 40, "variacao" => 0.0, "espalhar" => 0.0,
    "rasto" => 0.0, "girar" => 0.0, "flutuar" => 0.0, "flutuar_hz" => 2.0,
    "pulsar" => 0.0, "opacidade" => 255, "desvanecer" => 1,
    # Copiar a ANIMACAO INTEIRA em vez de uma celula dela. Ver o
    # `inteiras_do_animador!`.
    "inteira" => false
  }.freeze

  def receita_normal(r)
    c = RECEITA_OMISSAO.dup
    (r || {}).each { |k, v| c[k.to_s] = v if c.key?(k.to_s) }
    n = c["quantas"].to_i
    c["quantas"] = (n < 1) ? 1 : ((n > 8) ? 8 : n)
    c
  rescue
    RECEITA_OMISSAO.dup
  end

  def dispor_particulas(receita, tempo, rumo_x, rumo_y)
    r = receita_normal(receita)
    n = r["quantas"].to_i
    # O perpendicular ao rumo: e para ai que a particula flutua.
    px = -rumo_y
    py = rumo_x
    saida = []
    n.times do |i|
      fase = (i.to_f / n) * 2 * Math::PI
      atraso = (r["rasto"].to_f / 20.0) * i    # os quadros do motor sao 1/20 s
      t = tempo - atraso
      t = 0.0 if t < 0.0

      dx = Math.cos(fase) * r["espalhar"].to_f
      dy = Math.sin(fase) * r["espalhar"].to_f

      recuo = r["rasto"].to_f * i * 2.0
      dx -= rumo_x * recuo
      dy -= rumo_y * recuo

      if r["flutuar"].to_f > 0.0
        onda = Math.sin((t * r["flutuar_hz"].to_f * 2 * Math::PI) + fase)
        dx += px * onda * r["flutuar"].to_f
        dy += py * onda * r["flutuar"].to_f
      end

      escala = 1.0
      escala *= 1.0 + (Math.cos(fase) * r["variacao"].to_f) if r["variacao"].to_f > 0.0
      escala *= 1.0 + (Math.sin((t * 4.0) + fase) * r["pulsar"].to_f) if r["pulsar"].to_f > 0.0
      escala = 0.1 if escala < 0.1

      angulo = (r["girar"].to_f != 0.0) ? ((t * r["girar"].to_f * 360.0) % 360.0) : 0.0

      opac = r["opacidade"].to_f
      opac *= 1.0 - ((i.to_f / n) * 0.75) if r["desvanecer"].to_i != 0 && n > 1
      opac = 0.0 if opac < 0.0
      opac = 255.0 if opac > 255.0

      saida << { :dx => dx, :dy => dy, :escala => escala,
                 :angulo => angulo, :opacidade => opac.round }
    end
    saida
  rescue
    []
  end

  #-----------------------------------------------------------------------------
  # O RASTO
  #
  # ⚠️ ISTO NAO EXISTIA — NEM MAL, NEM BEM. SIMPLESMENTE NAO EXISTIA.
  #
  # O editor tem dois deslizadores para o rasto e grava-os desde sempre. O jogo
  # nunca teve uma linha a le-los: das duzentas animacoes, as duzentas tem
  # `rastro: 0`, porque mexer nele nao fazia nada e ninguem insistiu.
  #
  # ⚠️ E NAO SE CONFUNDE COM AS COPIAS DA RECEITA.
  #
  # As copias da receita sao um ENXAME: varias particulas ao mesmo tempo, cada
  # uma no seu sitio, todas no presente. O rasto e a mesma particula no PASSADO
  # — onde ela esteve ha dois, quatro, seis frames. Sao ideias diferentes e por
  # isso sao sprites diferentes; misturar as duas dava um enxame a arrastar-se,
  # que nao e nem uma coisa nem outra.
  #
  # Guarda-se um caminho curto das ultimas posicoes e poe-se um sprite em cada
  # uma, cada vez mais apagado. O custo e uma lista de pares de floats por
  # projectil, e um `x`/`y` por sprite e por frame.
  #-----------------------------------------------------------------------------
  RASTO_MAX     = 8      # sprites: acima disto e uma mancha, nao um rasto
  RASTO_ESPACO  = 3      # frames entre uma sombra e a seguinte

  def montar_rasto!(p)
    n = p[:rastro].to_i
    return if n <= 0
    n = RASTO_MAX if n > RASTO_MAX
    base = p[:sp]
    return unless base && base.bitmap && !(base.bitmap.disposed? rescue true)
    p[:rasto_sp] = []
    n.times do
      sp = Sprite.new(viewport_das_animacoes)
      # ⚠️ O bitmap e o MESMO do principal, partilhado. Nunca se deita fora a
      # partir daqui — e a mesma regra das copias, e ja custou um ecra em branco.
      sp.bitmap = base.bitmap
      sp.src_rect.set(base.src_rect.x, base.src_rect.y,
                      base.src_rect.width, base.src_rect.height) rescue nil
      sp.ox = base.ox
      sp.oy = base.oy
      sp.zoom_x = base.zoom_x
      sp.zoom_y = base.zoom_y
      sp.blend_type = base.blend_type
      sp.visible = false
      p[:rasto_sp] << sp
    end
    p[:trilho] = []
  rescue
    p[:rasto_sp] = nil
  end

  def correr_rasto!(p)
    sps = p[:rasto_sp]
    return if sps.nil? || sps.empty?
    base = p[:sp]
    return unless base && !(base.disposed? rescue true)
    trilho = (p[:trilho] ||= [])
    trilho.unshift([base.x, base.y, base.angle])
    limite = (sps.length * RASTO_ESPACO) + 1
    trilho.pop while trilho.length > limite
    # A forca decide quao visivel fica a sombra mais recente; as de tras
    # desvanecem em proporcao, para o rasto ter cauda em vez de degraus.
    forca = p[:rastro_forca].to_f
    forca = 0.55 if forca <= 0.0
    sps.each_with_index do |sp, i|
      next unless sp && !(sp.disposed? rescue true)
      posto = trilho[(i + 1) * RASTO_ESPACO]
      unless posto
        sp.visible = false
        next
      end
      sp.visible = true
      sp.x = posto[0]
      sp.y = posto[1]
      sp.angle = posto[2]
      sp.z = base.z - 1 - i
      queda = 1.0 - ((i + 1).to_f / (sps.length + 1))
      sp.opacity = (base.opacity * forca * queda).round
      sp.zoom_x = base.zoom_x * (0.94 ** (i + 1))
      sp.zoom_y = base.zoom_y * (0.94 ** (i + 1))
    end
  rescue
    nil
  end

  def largar_rasto!(p)
    (p[:rasto_sp] || []).each do |sp|
      next unless sp
      (sp.bitmap = nil) rescue nil
      (sp.dispose rescue nil) unless (sp.disposed? rescue true)
    end
    p[:rasto_sp] = nil
    p[:trilho] = nil
  rescue
    nil
  end

  # As copias seguem o principal, com o desvio que a receita mandar.
  def posicionar_copias!(p)
    copias = p[:copias]
    return if copias.nil? || copias.empty?
    base = p[:sp]
    return unless base && !(base.disposed? rescue true)
    vx = p[:vx].to_f
    vy = p[:vy].to_f
    n = Math.sqrt((vx * vx) + (vy * vy))
    if n > 0.001
      vx /= n
      vy /= n
    else
      vx = 1.0
      vy = 0.0
    end
    tempo = Time.now.to_f - p[:nascido].to_f
    postos = dispor_particulas(p[:receita], tempo, vx, vy)
    return if postos.empty?

    # O primeiro posto e do sprite principal; as copias levam os seguintes.
    principal = postos[0]
    base.x += principal[:dx].round
    base.y += principal[:dy].round
    base.angle = principal[:angulo]
    base.opacity = principal[:opacidade]
    base.zoom_x = (p[:zoom_base_x] ||= base.zoom_x) * principal[:escala]
    base.zoom_y = (p[:zoom_base_y] ||= base.zoom_y) * principal[:escala]

    copias.each_with_index do |c, i|
      next unless c && !(c.disposed? rescue true)
      posto = postos[i + 1]
      unless posto
        c.visible = false
        next
      end
      c.visible = true
      c.x = base.x - principal[:dx].round + posto[:dx].round
      c.y = base.y - principal[:dy].round + posto[:dy].round
      c.z = base.z
      c.angle = posto[:angulo]
      c.opacity = posto[:opacidade]
      c.zoom_x = p[:zoom_base_x] * posto[:escala]
      c.zoom_y = p[:zoom_base_y] * posto[:escala]
    end
  rescue
    nil
  end

  def largar_copias!(p)
    (p[:copias] || []).each do |c|
      # ⚠️ O BITMAP E PARTILHADO: se cada copia o deitasse fora, a segunda
      # apagava o que a primeira ainda estava a usar. So o sprite se descarta.
      (c.bitmap = nil) rescue nil
      (c.dispose rescue nil) if c && !(c.disposed? rescue true)
    end
    p[:copias] = nil
  rescue
    nil
  end

  # ⚠️ UM GOLPE NAO SAI DO CHAO: SAI DO PEITO DE QUEM O DA.
  #
  # Um projectil vive em coordenadas de casa e era desenhado no meio da casa —
  # ou seja, aos pes de toda a gente. As animacoes, essas, sao ancoradas no
  # centro do boneco. Duas alturas diferentes para a mesma coisa: a particula
  # rasteja pelo chao e a animacao rebenta a meia altura.
  #
  # Sobe-se meio boneco, com a mesma medida das ancoras. Quem nao tem dono
  # (uma pedra de onda, um espinho no chao) fica onde estava.
  def altura_do_lancador(p)
    quem = quem_lancou(p)
    return 0 unless quem
    cy = centro_do_boneco(quem)[1]
    pes = (quem.screen_y rescue cy)
    d = (pes - cy).to_i
    (d > 0 && d < 96) ? d : 0
  rescue
    0
  end

  def posicionar_projectil!(p)
    sp = p[:sp]
    return unless sp && !(sp.disposed? rescue true)
    p[:alto] = altura_do_lancador(p) unless p.key?(:alto)
    sp.x = ((p[:x] * Game_Map::REAL_RES_X - $game_map.display_x) / Game_Map::X_SUBPIXELS).round +
           (Game_Map::TILE_WIDTH / 2)
    sp.y = ((p[:y] * Game_Map::REAL_RES_Y - $game_map.display_y) / Game_Map::Y_SUBPIXELS).round +
           (Game_Map::TILE_HEIGHT / 2) - p[:alto].to_i
    # ⚠️ UMA BOLA ARREMESSADA FAZ UM ARCO, e nao vai a direito como um tiro.
    #
    # E o arco que faz aquilo parecer atirado por uma pessoa. Ela sobe ate meio
    # caminho, cai depois, e acaba mais alta do que o chao — a altura da cabeca
    # de quem a leva, que e onde ela bate. A rotacao vem por cima, devagar.
    posicionar_copias!(p)
    correr_rasto!(p)
    if p[:bola]
      total = p[:dist_total].to_f
      t = (total > 0.1) ? [[p[:andado].to_f / total, 0.0].max, 1.0].min : 1.0
      altura = (Math.sin(Math::PI * t) * 34.0) + (t * 18.0)
      sp.y -= altura.round
      sp.angle = (sp.angle - (360.0 * 1.1 * (@delta || (1.0 / 60.0)))) % 360
    end
  rescue
    nil
  end

  # ⚠️ UM FRAME LONGO NAO PODE TELEPORTAR UM GOLPE.
  #
  # O passo de um projectil e `velocidade x dt`. Num frame normal (1/60 s) isso
  # e um quinto de casa e nao ha problema nenhum. Mas quando o jogo engasga — e
  # engasga: uma mudanca de mapa, um save, o meu proprio log a abrir ficheiros —
  # o `dt` de um frame pode ser dez vezes maior, e o golpe da um salto de duas
  # casas de uma so vez.
  #
  # Com tecto, um engasgo faz o golpe abrandar em vez de saltar. Abrandar
  # ninguem nota; saltar faz-lhe passar por cima do alvo.
  # ⚠️ O `.x` DE UM CHARACTER NAO E ONDE ELE ESTA. E ONDE ELE JA SE INSCREVEU.
  #
  # O motor tem dois numeros para a mesma coisa. O `@x` e a casa, e salta para a
  # seguinte no INICIO do passo; o `@real_x` e a posicao a serio, e leva o passo
  # inteiro a la chegar. Entre um e outro vai ate uma casa de diferenca — 32
  # pixeis — e e o `@real_x` que manda no que se VE, porque o `screen_x` sai
  # dele.
  #
  # Perseguir o `.x` era perseguir uma casa onde o bicho ainda nao esta. Com ele
  # parado nao ha diferenca nenhuma (e por isso isto passou despercebido tanto
  # tempo); com ele a andar, o golpe aponta sistematicamente a frente dele, e
  # para que lado depende do rumo em que ele ia.
  #
  # Isto devolve a posicao verdadeira, em casas, com casas decimais. E o mesmo
  # numero de que o desenho vive.
  def casa_real(quem)
    return nil unless quem
    rx = (quem.instance_variable_get(:@real_x) rescue nil)
    ry = (quem.instance_variable_get(:@real_y) rescue nil)
    return [quem.x.to_f, quem.y.to_f] if rx.nil? || ry.nil?
    [rx.to_f / Game_Map::REAL_RES_X, ry.to_f / Game_Map::REAL_RES_Y]
  rescue
    [(quem.x.to_f rescue 0.0), (quem.y.to_f rescue 0.0)]
  end

  def correr_projecteis!
    return if @projecteis.nil? || @projecteis.empty?
    dt = [(@delta || (1.0 / 60.0)), 0.05].min
    fora = []
    @projecteis.each do |p|
      alvo = p[:alvo]
      ac = (alvo ? casa_real(alvo) : nil)
      ax = ac && ac[0]
      ay = ac && ac[1]
      if ax && ay
        dx = ax - p[:x]
        dy = ay - p[:y]
        dist = Math.sqrt((dx * dx) + (dy * dy))
        if dist > 0.001
          dx /= dist
          dy /= dist
          if p[:infalivel] && !p[:arco]
            # Perseguicao perfeita: aponta-se ao alvo a cada passo. Como a bola
            # e mais rapida do que qualquer Pokemon a correr, converge sempre.
            p[:vx] = dx * p[:vel]
            p[:vy] = dy * p[:vel]
          else
            actual = Math.atan2(p[:vy], p[:vx])
            desejado = Math.atan2(dy, dx)
            giro = desejado - actual
            giro -= 2 * Math::PI while giro > Math::PI
            giro += 2 * Math::PI while giro < -Math::PI
            # ⚠️ QUEM VOA MAIS DEPRESSA TEM DE VIRAR MAIS DEPRESSA, SENAO ORBITA.
            #
            # A `viragem` esta em radianos por segundo, e uma coisa que anda a
            # `v` casas por segundo e vira `w` radianos por segundo descreve uma
            # curva de raio `v / w`. Com os 7.0 casas/s de sempre e os 3.5 rad/s
            # do editor isso dava duas casas de raio, apertado o suficiente para
            # apanhar quem esta perto.
            #
            # Quando as velocidades do editor passaram a valer, o Wing Attack
            # subiu para 12.0 casas/s — e como a viragem ficou nos mesmos 3.5, o
            # raio da curva passou para tres casas e meia. Um golpe assim NAO
            # CONSEGUE acertar em nada que esteja a menos disso: anda a volta do
            # alvo, nunca entra, esgota o alcance e vai rebentar onde calhar. Era
            # o "aparecendo em lugares aleatorios", e explica o "antes funcionava
            # bem" — antes a velocidade do editor era ignorada.
            #
            # O tecto e o RAIO, nao o angulo: a curva nunca abre mais do que
            # `PROJ_CURVA` casas, ande o golpe a 7 ou a 20. E nunca vira menos do
            # que o editor mandou — isto so acrescenta, nunca corta.
            base_vir = p[:viragem] || PROJ_VIRAGEM
            base_vir = [base_vir, p[:vel].to_f / PROJ_CURVA].max if p[:vel].to_f > 0.0
            limite = (p[:arco] ? base_vir * 2.2 : base_vir) * dt
            giro = (giro > 0 ? limite : -limite) if giro.abs > limite
            ang = actual + giro
            p[:vx] = Math.cos(ang) * p[:vel]
            p[:vy] = Math.sin(ang) * p[:vel]
          end
        end
      end

      # ⚠️ NADA NA NATUREZA VOA EM LINHA RECTA.
      #
      # Seis particulas com o mesmo rumo sao uma linha, nao um jacto. Cada uma
      # leva uma fase propria e o rumo dela oscila devagar: o conjunto abre e
      # fecha, como o vento sobre uma chama.
      if p[:vagueia].to_f > 0.0
        ang = Math.atan2(p[:vy], p[:vx])
        ang += Math.sin((p[:tempo].to_f * 7.0) + p[:fase].to_f) * p[:vagueia] * dt
        p[:vx] = Math.cos(ang) * p[:vel]
        p[:vy] = Math.sin(ang) * p[:vel]
      end
      # ⚠️ UM GOLPE LANCADO PARA NA PEDRA, COMO TUDO O RESTO.
      #
      # Os projecteis andavam em coordenadas livres e nunca perguntavam ao
      # mapa: uma Water Gun atravessava a parede da caverna e ia acertar em
      # quem estava do outro lado, sem que houvesse linha de vista nenhuma.
      # Num mapa aberto isso quase nao se nota; num corredor de caverna e o
      # que decide as lutas.
      #
      # Confere-se a casa DEPOIS do passo. Um projectil que nasce em cima de
      # quem o lancou nunca comeca dentro de pedra, portanto nao ha o caso de
      # morrer logo a saida.
      antes_x = p[:x]
      antes_y = p[:y]
      p[:x] += p[:vx] * dt
      p[:y] += p[:vy] * dt
      if parede_no_voo?(p, antes_x, antes_y)
        fora << p
        next
      end
      p[:andado] += p[:vel] * dt
      p[:tempo] += dt
      posicionar_projectil!(p)
      animar_projectil!(p)

      if ax && ay
        dx = ax - p[:x]
        dy = ay - p[:y]
        if perto_do_caminho?(antes_x, antes_y, p[:x], p[:y], ax, ay)
          # ⚠️ O ESPELHO E CONFERIDO NO INSTANTE DO TOQUE, e nao ao lancar.
          #
          # E aqui que se sabe que aquilo ia mesmo acertar em mim — e aqui que
          # faz sentido devolver. O projectil nao morre: troca de dono, inverte
          # o rumo e passa a perseguir quem o mandou.
          if p[:ia] && !p[:reflectido] && alvo.equal?($game_player) && espelho_de_pe?
            reflectir!(p)
            next
          end
          p[:acertou] = true
          fora << p
          next
        end
      end
      # Um golpe infalivel de longe tem trela larga: nao desiste enquanto houver
      # alvo. Um bote de contacto nunca a tem — o alcance curto E o travao.
      limite_casas = p[:alcance]
      limite_casas *= 4 if p[:infalivel] && ax && !p[:curto]
      fora << p if p[:andado] >= limite_casas
    end
    embates!(fora)
    return if fora.empty?
    @projecteis -= fora
    fora.each { |p| rebentar_projectil!(p) }
  rescue => e
    registar("falha nos projecteis: #{e.class}: #{e.message}")
    limpar_projecteis!
  end

  #-----------------------------------------------------------------------------
  # QUANDO DOIS GOLPES SE ENCONTRAM A MEIO
  #
  # ⚠️ ATRAVESSAREM-SE E O QUE SE VIA, E LIA-SE COMO UM ERRO.
  #
  # Duas bolas a passar uma pela outra sem se tocarem dizem ao jogador que o
  # espaco entre ele e o inimigo nao conta para nada — que so importa quem
  # chega primeiro. Passando a haver embate, a linha de tiro passa a ser um
  # sitio disputado: vale a pena atirar contra o que vem, e vale a pena sair da
  # frente em vez de trocar golpe por golpe.
  #
  # ⚠️ E O EMBATE COME OS DOIS, INCLUINDO O QUE NAO SE VE.
  #
  # Um golpe que vem de fora anda em DOIS projecteis: um invisivel, que e o que
  # decide o dano, e uma copia desenhada ao lado dele. Apagar so o que se ve
  # daria uma faisca no ar e a vida a descer na mesma — o pior dos dois mundos.
  # Por isso o embate limpa tambem o que estiver mesmo ao lado e do mesmo lado:
  # o par invisivel morre com a copia, e um jorro de seis particulas gasta-se
  # todo naquele ponto em vez de gastar uma de cada vez.
  #-----------------------------------------------------------------------------
  EMBATE_RAIO   = 0.55    # casas: quao perto tem de passar para se darem
  EMBATE_LIMPA  = 1.10    # casas: o que mais se leva do mesmo lado
  EMBATE_PAUSA  = 0.18    # segundos entre animacoes de embate
  EMBATE_ANULA  = true    # false = so a faisca, os golpes seguem

  def embates!(fora)
    return if @projecteis.nil? || @projecteis.length < 2
    nossos = []
    deles  = []
    @projecteis.each do |p|
      next if p[:bola]              # uma Pokebola nao e um golpe
      next if fora.include?(p)
      ((p[:lado] == :deles) ? deles : nossos) << p
    end
    return if nossos.empty? || deles.empty?
    nossos.each do |a|
      next if fora.include?(a)
      deles.each do |b|
        next if fora.include?(b)
        dx = a[:x] - b[:x]
        dy = a[:y] - b[:y]
        next if ((dx * dx) + (dy * dy)) > (EMBATE_RAIO * EMBATE_RAIO)
        fx = (a[:x] + b[:x]) * 0.5
        fy = (a[:y] + b[:y]) * 0.5
        tocar_embate!(fx, fy)
        break unless EMBATE_ANULA
        [a, b].each do |q|
          q[:embateu] = true
          fora << q unless fora.include?(q)
        end
        # O que vinha a boleia — o par invisivel, as particulas do mesmo jorro.
        @projecteis.each do |q|
          next if fora.include?(q) || q[:bola]
          next unless q[:lado] == a[:lado] || q[:lado] == b[:lado]
          ex = q[:x] - fx
          ey = q[:y] - fy
          next if ((ex * ex) + (ey * ey)) > (EMBATE_LIMPA * EMBATE_LIMPA)
          q[:embateu] = true
          fora << q
        end
        break
      end
    end
  rescue => e
    registar("falha no embate: #{e.class}: #{e.message}")
  end

  # ⚠️ UMA FAISCA DE CADA VEZ, E NAO UMA POR PARTICULA.
  #
  # Um Razor Leaf sao seis folhas a chegar quase juntas. Sem travao, seis
  # embates sao seis animacoes empilhadas no mesmo sitio e meio segundo de ecra
  # branco. Com um travao curto ve-se um embate — que e o que aconteceu.
  def tocar_embate!(fx, fy)
    agora = Time.now.to_f
    return if @embate_ate.to_f > agora
    @embate_ate = agora + EMBATE_PAUSA
    @anim_embate = animacao_do_golpe(:LEER) if @anim_embate.nil?
    return if @anim_embate.to_i <= 0
    tocar_no_ponto!(@anim_embate, fx, fy)
    (pbSEPlay("Battle ball hit", 70) rescue nil)
  rescue
    nil
  end

  # ⚠️ O ACERTO OLHAVA PARA ONDE O GOLPE PAROU, E NAO POR ONDE ELE PASSOU.
  #
  # A pergunta era "a distancia entre o projectil e o alvo cabe no raio?", feita
  # uma vez por frame, depois do passo. Isso funciona enquanto o passo for mais
  # curto do que o raio. Deixa de funcionar quando nao e — e ha duas maneiras de
  # nao ser: um golpe afinado para voar mais depressa no editor, ou um frame
  # longo por causa de um engasgo.
  #
  # Nesses casos o projectil esta a um lado do alvo num frame e do outro lado no
  # seguinte, sem nunca ter estado PERTO em nenhum dos dois. Nao acerta, segue
  # caminho, e vai rebentar longe — e a animacao do impacto aparece num sitio
  # que nao tem nada a ver com nada. Foi o "aparecendo em lugares aleatorios", e
  # nota-se mais desde que as velocidades do editor passaram a valer.
  #
  # A pergunta certa e sobre o SEGMENTO que ele percorreu: a que distancia do
  # alvo passou a trajectoria deste frame? E a projeccao do alvo sobre o
  # segmento, presa entre as duas pontas. Custa seis multiplicacoes e nao deixa
  # escapar nada, por mais depressa que a coisa ande.
  def perto_do_caminho?(x1, y1, x2, y2, ax, ay)
    dx = x2 - x1
    dy = y2 - y1
    n2 = (dx * dx) + (dy * dy)
    if n2 < 0.000001
      d = Math.sqrt(((ax - x2)**2) + ((ay - y2)**2))
      return d <= PROJ_RAIO
    end
    t = (((ax - x1) * dx) + ((ay - y1) * dy)) / n2
    t = 0.0 if t < 0.0
    t = 1.0 if t > 1.0
    px = x1 + (dx * t)
    py = y1 + (dy * t)
    Math.sqrt(((ax - px)**2) + ((ay - py)**2)) <= PROJ_RAIO
  rescue
    false
  end

  def reflectir!(p)
    dono = p[:bicho]
    p[:ia] = false
    p[:meu] = true
    p[:reflectido] = true
    p[:no_aliado] = false
    p[:alvo] = (dono && dono[:ev]) ? dono[:ev] : nil
    p[:vx] = -p[:vx]
    p[:vy] = -p[:vy]
    p[:andado] = 0.0
    p[:infalivel] = true          # devolvido, vai direito a quem atirou
    p[:nome] = nil
    dizer(_INTL("Refletido!"))
    piscar_cor!($game_player, 150, 210, 255, 14)
    (pbSEPlay("Battle ball hit") rescue nil)
    @espelho_ate = 0.0
    @segurar_travado = true
  rescue
    nil
  end

  # A explosao e a animacao verdadeira do golpe, tocada na casa onde a bola
  # parou — acerte ou nao. Errar tem de se ver.
  # A explosao e a animacao verdadeira do golpe, tocada na casa onde a bola
  # parou — acerte ou nao. Errar tem de se ver.
  # ⚠️ ESTA E A MESMA PEDRA, PELA QUARTA VEZ.
  #
  # Ja a apanhei no golpe do adversario, no do parceiro e no rodopio, e escrevi
  # a nota nos tres: `tocar_no_character!` monta a animacao entre DUAS ancoras —
  # quem lanca e quem leva — e sem o quarto argumento quem lanca e sempre o
  # `$game_player`.
  #
  # Faltava o sitio por onde passam quase todos os golpes do jogo: o
  # REBENTAMENTO de um projectil. Ele tocava a animacao com um `tocar_no_chao!`
  # de quatro argumentos, portanto a linha era sempre "do meu Pokemon ate ao
  # ponto de impacto". Numa animacao de modo feixe — e o Volt Switch e uma — a
  # linha E o desenho: ve-se um raio a sair de mim, com o alcance medido de mim,
  # para um golpe que o AJUDANTE deu. O utilizador descreveu-o exactamente
  # assim: "meu poliwhirl sequer aprende voltswitch".
  #
  # O projectil ja sabe de quem e. So nunca ninguem lhe tinha perguntado.
  def quem_lancou(p)
    return @aliado[:ev] if p[:aliado] && aliado_vivo?
    if p[:ia]
      b = p[:bicho]
      return b[:ev] if b && b[:ev]
    end
    if p[:pacote]
      outro = (quem_mandou(p[:pacote]) rescue nil)
      return outro if outro
    end
    $game_player
  rescue
    $game_player
  end

  def rebentar_projectil!(p)
    sp = p[:sp]
    largar_copias!(p)
    largar_rasto!(p)
    (sp.dispose rescue nil) if sp && !(sp.disposed? rescue true)
    # Quem se deu de caras com outro golpe ja teve a sua animacao: a do embate.
    # A do proprio golpe por cima seria a explosao de uma coisa que nao chegou
    # a lado nenhum.
    return if p[:embateu]

    if p[:bola]
      resolver_bola!(p)
      return
    end

    # ⚠️ EU MATEI A ANIMACAO DE IMPACTO A TENTAR MATAR O EFEITO DUPLO. ERRADO.
    #
    # A regra que pus era "se ha desenho a voar, nao se toca a animacao". Ela
    # apagou o Thunder Shock inteiro: o que se via de bom naquele golpe era a
    # animacao de raios a cair no alvo, e a particula que voa e so o aviso de
    # que ele vem a caminho.
    #
    # O efeito duplo nunca esteve aqui. Ele vinha das PARTICULAS — o jorro, a
    # rajada, as pedras da onda — e essas ja nascem com `anim => 0` porque elas
    # proprias sao o golpe. Quem tem animacao para tocar e o projectil unico, e
    # esse deve toca-la, como sempre tocou.
    # ⚠️ SALTAR PARA O QUADRO DO REBENTAMENTO CORTOU O GOLPE AO MEIO.
    #
    # Eu fazia a animacao comecar no pico para nao repetir o arremesso. So que
    # num golpe como o Thunder Shock o arremesso NAO existe: a animacao inteira
    # e os raios a cair do ceu, e o "pico" que eu detecto e o clarao final. Ao
    # comecar la, deitava fora tudo o que valia a pena — e com os quadros
    # tambem os SONS, porque o crack do trovao esta marcado num quadro do
    # principio e o motor so toca os que passam.
    #
    # Um projectil unico toca a animacao do inicio, sempre. O salto continua
    # disponivel, mas ninguem o usa por agora.
    # ⚠️ ALGUNS GOLPES TRAZEM O ARREMESSO DENTRO DA PROPRIA ANIMACAO.
    #
    # Num bumerangue os primeiros quadros SAO o atirar — e isso ja aconteceu no
    # mapa, com a particula a voar. Toca-la desde o inicio mostrava o golpe a
    # ser atirado outra vez depois de ja ter acertado. O editor deixa marcar em
    # que quadro o rebentamento comeca; zero e o de sempre, toca tudo.
    #
    # (E o editor avisa quais marcas de som ficam de fora, porque ja perdemos o
    # trovao do Thunder Shock exactamente assim.)
# ⚠️ UM GOLPE MARCADO "ALVO" REBENTA NO ALVO. NAO ONDE A BOLA PAROU.
#
# Isto tocava sempre a animacao na CASA onde o projectil morreu. Para um
# golpe de "onde o golpe acertar" esta certo — o sitio do impacto e mesmo o
# assunto. Para um marcado "alvo" nao.
#
# E a razao nao e o raio de acerto nem o arredondamento: medi os dois e dao
# erro ZERO com o bicho parado, em qualquer direccao. Eu ia jurar que era
# isso e os numeros disseram que nao. O que rompe e mais fundo:
#
#     o projectil persegue o `alvo.x`   -> a CASA do bicho, um inteiro
#     a animacao e desenhada no sprite  -> o `@real_x`, continuo
#
# O `@x` de um character salta para a casa nova no INICIO do passo; o
# `@real_x` leva o passo inteiro a la chegar. Enquanto ele anda, os dois
# numeros discordam:
#
#     a  0% do passo   1,00 casa  =  32 px
#     a 50% do passo   0,50 casa  =  16 px
#     a 99% do passo   0,01 casa  =   0 px
#
# Ou seja: a animacao caia no sitio certo com o bicho parado ou a acabar um
# passo, e ate uma casa ao lado com ele a meio de um — e para que lado
# dependia do rumo em que ele ia. Dai "de cima para baixo ficou em cima do
# alvo, em outras posicoes todo errado".
#
# Nao ha conta a corrigir: a casa do impacto e a resposta a outra pergunta.
# Quem marcou "alvo" esta a dizer "isto desenha-se em cima dele", e entao a
# ancora tem de ser ELE — o boneco, com o mesmo centro lido do sprite que a
# oficina usa. Assim nao ha casa, nem raio, nem arredondamento pelo meio.
#
# Quem falhou nao tem alvo e volta a casa onde parou, como deve ser: uma
# explosao no vazio acontece onde a coisa caiu.
    if p[:anim].to_i > 0
      # ⚠️ E NAO SE EXIGE QUE TENHA ACERTADO.
      #
      # Eu tinha posto `p[:acertou] &&` aqui, e isso desfaz metade da correccao:
      # e justamente quando o projectil NAO chega ao fim que ele morre longe e a
      # animacao vai parar ao vazio. Exigir o acerto era so tratar o caso que ja
      # estava bem.
      #
      # "Alvo" e uma promessa sobre o DESENHO: isto ve-se em cima dele. Se havia
      # alvo, e nele que se desenha. Quem nao tinha alvo nenhum — um golpe dado
      # ao vazio — e que rebenta onde a coisa caiu.
      no_alvo = (p[:alvo] &&
                 (palco_da_anim(p[:anim]) || {})["modo"].to_s == "alvo")
      if no_alvo
        tocar_no_character!(p[:alvo], p[:anim],
                            impacto_desde_da_anim(p[:anim]), quem_lancou(p))
      else
        tocar_no_chao!(p[:anim], p[:x].round, p[:y].round,
                       impacto_desde_da_anim(p[:anim]),
                       quem_lancou(p))
      end
    end

    # Uma pedra de onda ja fez o estrago dela no instante em que a onda saiu:
    # aqui e so cair e desaparecer.
    return if p[:so_desenho]

    # Um projectil guarda quem o lancou; a marca acompanha-o ate ao impacto,
    # que pode acontecer segundos depois de o ajudante ter atacado.
    @dono_do_golpe = p[:aliado] ? :aliado : :eu
    if p[:aliado]
      # Golpe do ajudante: bate no bicho que ele escolheu.
      return unless p[:acertou]
      b = p[:bicho] || bicho_do_evento(p[:alvo])
      return unless b
      d = dano_do_aliado(b, p[:mv])
      d = [(d * p[:forca].to_f).round, 1].max if p[:forca] && d > 0
      ferir_bicho!(b, d, p[:mv], nil)
      return
    end

    if p[:ia] && p[:no_aliado]
      return unless p[:acertou]
      b = p[:bicho]
      ferir_aliado!(b ? dano(b[:pkmn], @aliado[:pkmn], p[:mv]) : 0, p[:mv],
                    (b ? b[:ev] : nil)) if aliado_vivo?
      return
    end

    if p[:ia]
      # Golpe de um selvagem, resolvido nesta maquina.
      return unless p[:acertou]
      if !p[:infalivel] && rand(100) >= precisao(p[:move_id])
        narrar("#{p[:nome]}... errou!")
        return
      end
      return if clone_comeu?
      if escudo_de_pe?
        aparar!
        return
      end
      b = p[:bicho] || bicho_focado
      d = b ? dano_do_bicho(b, p[:mv]) : 0
      @hp_meu = [@hp_meu - d, 0].max
      talvez_aplicar_estado!(p[:move_id]) if d > 0 || golpe_de_estado?(p[:mv])
      empurrar!($game_player, (b ? b[:ev] : nil), empurrao_de(p[:mv])) if d > 0 && b && b[:ev]
      nome_dele = (b && b[:pkmn] ? "#{b[:pkmn].speciesName}: " : "")
      narrar(mensagem_do_acerto("#{nome_dele}#{p[:nome]}", d, p[:mv]))
      terminar_derrota! if @hp_meu <= 0
      return
    end

    if p[:meu]
      # Contra outro jogador o meu projectil e so o desenho: quem decide o dano
      # e a vitima, com a copia que ela propria simula.
      return if pvp?
      if !p[:acertou] && p[:raio].to_f <= 0
        narrar("#{p[:nome]}... errou!") if p[:nome]
        return
      end
      if !p[:infalivel] && rand(100) >= precisao(p[:move_id])
        narrar("#{p[:nome]}... errou!") if p[:nome]
        return
      end
      if p[:raio].to_f > 0 && !p[:reflectido]
        ferir_em_area!(p[:x].round, p[:y].round, p[:raio], p[:mv], p[:nome])
      else
        b = p[:bicho] || bicho_do_evento(p[:alvo]) || bicho_focado
        return unless b
        d = dano_no_bicho(b, p[:mv])
        d = [(d * p[:forca].to_f).round, 1].max if p[:forca] && d > 0
        ferir_bicho!(b, d, p[:mv], p[:nome])
      end
      return
    end

    # Copia do golpe do adversario humano, simulada do MEU lado.
    return unless p[:acertou]
    if !p[:infalivel] && rand(100) >= precisao(p[:move_id])
      registar("projectil #{p[:move_id]}: falhou na precisao")
      enviar!("arena_dano", "dano" => 0, "hp" => @hp_meu, "hp_max" => (@meu.totalhp.to_i rescue 1))
      return
    end
    aplicar_golpe_recebido!(p[:pacote])
  rescue => e
    registar("falha a rebentar: #{e.class}: #{e.message}")
  end

  def limpar_projecteis!
    (@projecteis || []).each { |p| largar_rasto!(p) }
    (@projecteis || []).each { |p| largar_copias!(p) }
    (@projecteis || []).each do |p|
      sp = p[:sp]
      (sp.dispose rescue nil) if sp && !(sp.disposed? rescue true)
    end
    @projecteis = []
  rescue
    @projecteis = []
  end

  # ⚠️ "DUAS A CINCO VEZES" TEM DE SER DUAS A CINCO COISAS A VOAR.
  #
  # O motor guarda isso no `function_code` — HitTwoTimes, HitTwoToFiveTimes — e
  # na batalha por turnos e so um numero a multiplicar. Aqui nao pode ser: se
  # sair uma bola so, o Bullet Seed e o Rock Blast ficam iguais a um golpe
  # fraco qualquer. Saem varias, espacadas por uns frames, e cada uma acerta ou
  # falha por si — quem se desviar a tempo apanha menos.
  MULTI_INTERVALO = 7   # frames entre cada toque

  def repeticoes(mv)
    fc = (GameData::Move.get(mv.id).function_code.to_s rescue "")
    return 1 unless fc.include?("Times")
    return 2 + rand(4) if fc.include?("TwoToFive")
    return 3 if fc.include?("ThreeTimes")
    return 2 if fc.include?("TwoTimes")
    1
  rescue
    1
  end

  def correr_lancamentos!
    return if @lancamentos.nil? || @lancamentos.empty?
    agora = (Graphics.frame_count rescue 0)
    prontos = @lancamentos.select { |l| l[:em] <= agora }
    return if prontos.empty?
    @lancamentos -= prontos
    prontos.each do |l|
      if l[:copia]
        soltar_copia_visual!(l[:copia])
      elsif l[:jorro]
        soltar_particula_de_jorro!(l[:mv], l[:anim])
      elsif l[:bicho]
        # A rajada do ajudante parte do boneco dele; a do jogador, do jogador.
        # Sem isto as folhas do ajudante saiam dos meus pes.
        if l[:de_aliado] && aliado_vivo?
          disparar_do_aliado!(l[:mv], l[:anim], l[:bicho])
        else
          disparar_num!(l[:mv], l[:nome], l[:anim], l[:bicho])
        end
      else
        disparar_um!(l[:mv], l[:nome], l[:anim])
      end
    end
  rescue
    @lancamentos = []
  end

  # Uma particula que sai do ajudante e persegue um inimigo. E o `disparar_num!`
  # com outra origem — nao se generalizou o original porque ele e o caminho de
  # quase todos os golpes do jogo e tem seis notas por cima a explicar porque.
  def disparar_do_aliado!(mv, anim, bicho)
    return unless aliado_vivo? && bicho && bicho[:ev]
    ev = @aliado[:ev]
    inf = infalivel?(mv.id)
    lancar!(:x => ev.x, :y => ev.y, :dir => (ev.direction rescue 2),
            :alvo => bicho[:ev], :anim => anim.to_i, :infalivel => inf,
            :move_id => mv.id, :mv => nil, :nome => nil, :meu => false,
            :aliado => true, :so_desenho => true,
            :alcance => alcance_do_lancamento(mv), :curto => contacto?(mv),
            :vel => velocidade_do_lancamento(mv, inf))
  rescue
    nil
  end

  def lancar_meu_golpe!(mv, nome, anim, ev)
    # A cabecada acompanha o golpe de contacto. Nao substitui o projectil de
    # alcance curto que ja existia — e ele que continua a fazer o dano; isto e
    # o corpo a acompanhar o que a mao faz.
    if contacto?(mv)
      alvo_x, alvo_y = ev ? [ev.x, ev.y] : casa_a_frente(1)
      dar_bote!($game_player, alvo_x, alvo_y)
    end
    disparar_um!(mv, nome, anim)
    n = repeticoes(mv)
    if n > 1
      agora = (Graphics.frame_count rescue 0)
      (1...n).each do |k|
        (@lancamentos ||= []) << { :em => agora + (k * MULTI_INTERVALO),
                                   :mv => mv, :nome => nome, :anim => anim }
      end
      narrar("#{nome} x#{n}!")
    end
  rescue => e
    registar("falha a lancar o meu golpe: #{e.class}: #{e.message}")
  end

  # ⚠️ UM GOLPE DE AREA NAO E UMA BOLA GRANDE: SAO VARIAS PEQUENAS.
  #
  # O Razor Leaf, na batalha a serio, atira as folhas para o ar a partir de quem
  # ataca e depois elas caem sobre TODOS. Rebentar uma vez num raio dava o dano
  # certo e a leitura errada — nao se via para quem ia. Agora toca-se a animacao
  # em cima do proprio Pokemon (o gesto de lancar) e sai uma particula por alvo,
  # cada uma a perseguir o seu. Com quatro selvagens a volta, saem quatro.
  # ⚠️ UMA RAJADA, E NAO UMA FOLHA POR ALVO.
  #
  # Da primeira vez saiu UMA particula para cada alvo — e uma folha grande e
  # solitaria a rodar nao le como Razor Leaf nenhum. O que se ve na batalha e um
  # punhado a subir e a sair disparado. Sao quatro por alvo, uma a cada tres
  # frames, cada uma com um quarto do dano: o mesmo estrago, muito mais coisa no
  # ar. Com quatro selvagens a volta sao dezasseis folhas.
  RAJADA_POR_ALVO = 4
  RAJADA_INTERVALO = 3    # frames entre folhas do mesmo alvo

  # ⚠️ EU ESTAVA A REFAZER A MAO UMA ANIMACAO QUE JA ESTAVA FEITA — E MELHOR.
  #
  # O Razor Leaf tem DOIS tempos desenhados: primeiro as folhas sobem em cima de
  # quem ataca, depois sao disparadas contra o alvo. Isso nao e um acaso do
  # desenho — e a estrutura das animacoes deste motor. Cada celula traz um
  # `FOCUS`: 2 = presa a quem ataca, 1 = presa ao alvo, 3 = na linha entre os
  # dois. E o `PBAnimationPlayerX` que resolve isso, e e por isso que a mesma
  # animacao serve para qualquer par de combatentes.
  #
  # Eu vi as folhas "por cima do meu Pokemon" e concluí que a animacao estava no
  # sitio errado. Nao estava: aquele era o PRIMEIRO tempo, e eu deitei-o fora
  # para pôr no lugar uma rajada de particulas minha — que so sabe fazer o
  # segundo tempo, e mal.
  #
  # Aqui a animacao volta inteira, ancorada de mim para o alvo, que e como a
  # batalha a toca. O dano continua a ser meu: apanha toda a gente no raio,
  # porque e um golpe de area.
  def leque!(mv, nome, anim)
    alvo_ev = if pvp?
                adversario_remoto
              else
                b = bichos_vivos.select { |x| x[:ev] }
                                .min_by { |x| distancia_casas(x[:ev], $game_player) }
                b ? b[:ev] : nil
              end

    if anim.to_i > 0
      if alvo_ev
        tocar_no_character!(alvo_ev, anim)
      else
        # Sem ninguem a frente, o segundo tempo aponta para onde eu olho.
        tocar_no_chao!(anim, *casa_a_frente(3))
      end
    end
    dizer(nome) if nome

    return if pvp?    # o estrago e de quem leva
    alvos = bichos_vivos.select do |x|
      x[:ev] && distancia_casas(x[:ev], $game_player) <= alcance_do_lancamento(mv)
    end
    return if alvos.empty?
    # ⚠️ UM GOLPE DE AREA NAO E UM NUMERO A CAIR EM VARIOS SITIOS.
    #
    # O dano ia para todos ao mesmo tempo e nao saia nada de visivel — a
    # animacao das folhas tocava uma vez, num alvo, e os outros perdiam vida
    # sem que nada os tivesse tocado. Quem joga ve tres inimigos a cair e um
    # golpe a acontecer num deles.
    #
    # Depois do gesto de lancar, sai uma RAJADA por inimigo: quatro folhas
    # cada, uma a cada tres frames, cada uma a perseguir o seu. Com tres
    # inimigos a volta sao doze folhas no ar — que e o que o Razor Leaf faz na
    # batalha a serio, e e o que torna legivel de onde veio o estrago.
    alvos.each_with_index do |x, i|
      RAJADA_POR_ALVO.times do |k|
        (@lancamentos ||= []) << {
          :em => (Graphics.frame_count rescue 0) + (i * 2) + (k * RAJADA_INTERVALO),
          :mv => mv, :nome => nil, :anim => 0, :bicho => x
        }
      end
      ferir_bicho!(x, dano_no_bicho(x, mv), mv, nil)
    end
  rescue => e
    registar("falha na area: #{e.class}: #{e.message}")
  end

  def adiar_lancamento!(frames, mv, nome, anim, bicho)
    if frames <= 0
      disparar_num!(mv, nome, anim, bicho)
      return
    end
    (@lancamentos ||= []) << { :em => (Graphics.frame_count rescue 0) + frames,
                               :mv => mv, :nome => nome, :anim => anim,
                               :bicho => bicho, :sem_anim => true }
  end

  def disparar_num!(mv, nome, anim, bicho)
    return unless bicho && bicho[:ev]
    lancar!(:x => $game_player.x, :y => $game_player.y, :dir => $game_player.direction,
            :alvo => bicho[:ev], :anim => 0,
            # ⚠️ Uma folha nunca e "infalivel": a mira perfeita punha-a a apontar
            # ao alvo desde o primeiro frame e matava o arco. Elas sobem, viram,
            # e so depois e que vao.
            :infalivel => false, :arco => true, :pequeno => true,
            :forca => (1.0 / RAJADA_POR_ALVO), :so_desenho => pvp?,
            :move_id => mv.id, :mv => mv, :nome => nil, :meu => true,
            :bicho => bicho, :cartao_de => anim,
            :alcance => alcance_do_lancamento(mv) + 3.0, :curto => false,
            :vel => velocidade_do_lancamento(mv, false))
  rescue => e
    registar("falha a disparar particula: #{e.class}: #{e.message}")
  end

  # ⚠️ UM JACTO E MUITA COISA PEQUENA, E NAO UMA BOLA SO.
  #
  # O Flamethrower e o Bubble Beam saiam como um unico sprite — e ao lado disso
  # o `correr_segurar!` tocava a animacao INTEIRA por cima do Pokemon, que e o
  # que se via: uma nuvem colada a ele, como se o golpe nao saisse. Agora saem
  # seis particulas em fila, uma a cada dois frames, com um bailado lateral que
  # as impede de irem em linha recta — a labareda espalha-se e o jacto le-se
  # como jacto.
  JORRO_PARTICULAS = 6
  JORRO_INTERVALO  = 2      # frames entre particulas
  VAGUEIA_FEIXE    = 2.6    # quanto o rumo oscila

  def jorro!(mv, nome, anim)
    JORRO_PARTICULAS.times do |k|
      adiar_jorro!(k * JORRO_INTERVALO, mv, anim)
    end
    dizer(nome) if nome
    piscar_cor!($game_player, 255, 235, 180, 8)
  rescue => e
    registar("falha no jorro: #{e.class}: #{e.message}")
  end

  def adiar_jorro!(frames, mv, anim)
    if frames <= 0
      soltar_particula_de_jorro!(mv, anim)
      return
    end
    (@lancamentos ||= []) << { :em => (Graphics.frame_count rescue 0) + frames,
                               :mv => mv, :nome => nil, :anim => anim, :jorro => true }
  end

  def soltar_particula_de_jorro!(mv, anim)
    alvo = evento_inimigo
    lancar!(:x => $game_player.x, :y => $game_player.y, :dir => $game_player.direction,
            :alvo => alvo, :anim => 0, :infalivel => false, :pequeno => true,
            :cartao_de => anim, :vagueia => VAGUEIA_FEIXE,
            :forca => (1.0 / JORRO_PARTICULAS), :so_desenho => pvp?,
            :move_id => mv.id, :mv => mv, :nome => nil, :meu => true,
            :alcance => ALCANCE_FEIXE, :curto => false,
            :vel => PROJ_VEL * 1.15)
  rescue
    nil
  end

  # ⚠️ O PVP TINHA UM VISUAL SO DELE, E ERA O ANTIGO.
  #
  # Todos os desenhos novos — o jorro de particulas, a rajada de folhas, as
  # pedras da onda — estavam atras de um `&& !pvp?`, porque sao os mesmos
  # metodos que aplicam o dano e no PVP quem decide o dano e a vitima. Ao passar
  # ao lado deles, um duelo caia no caminho antigo: UMA bola a voar e, na
  # chegada, a animacao inteira da batalha. Era isso que se via.
  #
  # A separacao certa nao e "PVP tem outro visual": e visual e dano serem coisas
  # diferentes. As particulas passam a sair sempre; no PVP saem marcadas como
  # `so_desenho`, e quem conta a vida continua a ser o pacote e a vitima.
  #-----------------------------------------------------------------------------
  # O QUE OS OUTROS VEEM
  #
  # ⚠️ UMA LUTA QUE SO O DONO VE NAO E UMA LUTA PARTILHADA.
  #
  # No duelo ha um pacote por golpe porque ha alguem a levar com ele. Contra
  # selvagens nao havia pacote nenhum: cada um lutava sozinho na sua maquina, e
  # o parceiro so via o resultado — o bicho a desmaiar, do nada. Cacar a dois
  # sem ver o que o outro faz e cacar ao lado dele, nao com ele.
  #
  # ⚠️ E ISTO NAO E DANO: E DESENHO.
  #
  # O pacote nao leva forca, nem nivel, nem estados — nada com que a maquina do
  # outro possa mexer na luta. Leva o que se ve: qual o golpe, de onde saiu, e
  # para onde. Quem o recebe toca a animacao e mais nada. Nao ha nada a
  # sincronizar, portanto nao ha nada que possa dessincronizar.
  ESPECTADOR_RAIO = 20   # casas: mais longe do que isto ninguem esta a ver

  def mostrar_aos_outros!(mv, anim, alvo_ev)
    return unless (AnilLanRework.connected? rescue false)
    return if pvp?    # ali ja vai um pacote proprio, com o dano
    return unless @directa || @caca
    meu_mapa = ($game_map.map_id rescue nil)
    return unless meu_mapa
    dados = {
      "move" => mv.id.to_s,
      "anim" => anim.to_i,
      "x"    => $game_player.x,
      "y"    => $game_player.y,
      "dir"  => $game_player.direction,
      "ax"   => (alvo_ev ? alvo_ev.x : nil),
      "ay"   => (alvo_ev ? alvo_ev.y : nil),
      "map"  => meu_mapa
    }
    AnilLanRework.players.each_value do |peer|
      next if peer.map_id.to_i != meu_mapa.to_i
      dx = (peer.x.to_i - $game_player.x).abs
      dy = (peer.y.to_i - $game_player.y).abs
      next if dx > ESPECTADOR_RAIO || dy > ESPECTADOR_RAIO
      AnilLanRework.connection.send_packet("arena_mostra",
        dados.merge("to_id" => peer.internal_id.to_s))
    end
  rescue => e
    registar("falha a mostrar aos outros: #{e.class}: #{e.message}")
  end

  # Do lado de quem ve: so a animacao, e so se estivermos no mesmo mapa.
  def receber_espectaculo!(pacote)
    return unless $game_map && $scene.is_a?(Scene_Map)
    return if pacote["map"].to_i != $game_map.map_id.to_i
    anim = pacote["anim"].to_i
    return if anim <= 0
    # ⚠️ A MESMA PEDRA, E AQUI TAMBEM.
    #
    # Isto e o que se ve quando OUTRO jogador ataca ao pe de nos, fora de duelo:
    # so a animacao, sem dano. Ela era ancorada no chao com o utilizador por
    # omissao — ou seja, o golpe dele era desenhado a sair de mim, que e o mesmo
    # defeito de sempre num sitio a mais.
    #
    # Quem lanca e ele, e o pacote diz onde ele estava (`x`/`y`). O alvo e o
    # ponto que ele apontou (`ax`/`ay`), ou a casa dele se nao apontou nada.
    sx = pacote["x"].to_i
    sy = pacote["y"].to_i
    ax = pacote["ax"]
    ay = pacote["ay"]
    de = marcador_no_ponto(sx, sy)
    if ax && ay
      tocar_no_ponto!(anim, ax.to_i, ay.to_i, 0, de)
    else
      tocar_no_ponto!(anim, sx, sy, 0, de)
    end
  rescue => e
    registar("falha a ver o golpe de outro: #{e.class}: #{e.message}")
  end

  # ⚠️ ISTO NAO E UM GOLPE NO FIO: E UMA ANIMACAO.
  #
  # Nao leva forca, nem forma, nem projectil — nada com que a maquina do outro
  # possa mexer na luta. Leva "fulano esta a girar, ali". Quem recebe desenha a
  # volta DELE e mais nada, e por isso nao ha nada a sincronizar.
  RODOPIO_AVISO = 0.30   # segundos entre avisos, que o tufao repete-se

  def anunciar_animacao_propria!(mv, anim)
    return unless pvp? || caverna?
    agora = Time.now.to_f
    return if @aviso_proprio.to_f > agora
    @aviso_proprio = agora + RODOPIO_AVISO
    dados = { "move" => mv.id.to_s, "anim" => anim.to_i,
              "x" => $game_player.x, "y" => $game_player.y,
              "dir" => $game_player.direction, "em_mim" => true }
    if pvp?
      enviar!("arena_golpe", dados)
    else
      anunciar_na_caverna!(dados)
    end
  rescue => e
    registar("falha a anunciar a animacao propria: #{e.class}: #{e.message}")
  end

  def anunciar_golpe!(mv, anim, inf)
    return unless pvp? || caverna?
    dados = {
        "move"      => mv.id.to_s,
        "x"         => $game_player.x,
        "y"         => $game_player.y,
        "dir"       => $game_player.direction,
        # ⚠️ A forma verdadeira, e nao "linha" sempre: e com ela que a vitima
        # decide se foi apanhada, e uma onda apanha em volta, nao em frente.
        "forma"     => ((area?(mv) || em_volta?(mv)) ? "area" : "linha"),
        "anim"      => anim.to_i,
        "proj"      => true,
        "infalivel" => inf,
        "curto"     => contacto?(mv),
        "alcance"   => alcance_do_lancamento(mv),
        "vel"       => velocidade_do_lancamento(mv, inf),
        "atraso"    => 0,
        "nivel"     => (@meu.level.to_i rescue 50),
        "atk"       => (@meu.attack.to_i rescue 50),
        "spatk"     => (@meu.spatk.to_i rescue 50) }
    # ⚠️ O PACOTE DIZIA DE ONDE SAIU E NUNCA DIZIA PARA ONDE IA.
    #
    # Para quem LEVA isso chegava, porque o alvo era obviamente quem recebia. Um
    # parceiro nao: ele recebe o mesmo pacote e nao tem como saber contra quem e
    # que o golpe foi — e entao desenhava-o contra a unica ponta que conhecia,
    # que era ele proprio.
    #
    # Duas casas a mais no pacote e o parceiro ja pode desenhar a verdade.
    alvo_ev = evento_inimigo
    if alvo_ev
      dados["ax"] = (alvo_ev.x rescue nil)
      dados["ay"] = (alvo_ev.y rescue nil)
    end
    if pvp?
      enviar!("arena_golpe", dados)
    else
      anunciar_na_caverna!(dados)
    end
  rescue => e
    registar("falha a anunciar: #{e.class}: #{e.message}")
  end

  # ⚠️ SO O FOGO SAI EM PARTICULAS. O RESTO E A ANIMACAO DO JOGO.
  #
  # As particulas foram uma boa ideia para uma labareda, que e mesmo um jacto
  # continuo de coisas pequenas. Para tudo o resto elas SUBSTITUIAM a animacao —
  # e com ela iam-se os dois tempos, os sons marcados nos quadros (por isso o
  # Bubble Beam e o Dragon Breath ficaram mudos) e o trabalho de quem as
  # desenhou. O jogo ja sabe desenhar estes golpes; a arena so tem de os por no
  # sitio certo.
  def jorro_de_fogo?(mv)
    return false unless seguravel(mv) == :feixe
    (GameData::Move.get(mv.id).type rescue nil) == :FIRE
  rescue
    false
  end

  def disparar_um!(mv, nome, anim)
    inf = infalivel?(mv.id)
    anunciar_golpe!(mv, anim, inf)
    mostrar_aos_outros!(mv, anim, evento_inimigo)

    if jorro_de_fogo?(mv)
      jorro!(mv, nome, anim)
      return
    end
    if em_volta?(mv)
      explodir_em_volta!(mv, nome, anim)
      return
    end
    if area?(mv) && (pvp? || !bichos_vivos.empty?)
      leque!(mv, nome, anim)
      return
    end
    # Outrage e companhia escolhem um alvo ao acaso, e nao o mais proximo.
    ev = if sorteado?(mv) && !pvp?
           b = bichos_vivos.sample
           b ? b[:ev] : evento_inimigo
         else
           evento_inimigo
         end
    # ⚠️ ERRO MEU: O PROBLEMA DO DRILL ERA A MIRA, NAO O DESENHO.
    #
    # A animacao do Hyper Drill ja fazia a coisa certa — varias celulas
    # empilhadas a formar uma ponta, a rodar. O unico defeito era apontar para o
    # meu proprio boneco em vez de apontar para quem eu ataquei. Eu troquei a
    # animacao inteira por uma celula a voar, o que resolveu a mira e deitou
    # fora o golpe.
    #
    # O `setLineTransform` mapeia a linha utilizador->alvo do palco para a linha
    # utilizador->alvo REAL: basta dar-lhe o ALVO CERTO. Quando ha inimigo, e o
    # boneco dele; quando nao ha, e a casa duas a frente. A animacao volta
    # inteira e passa a sair na direccao certa.
    #
    # O projectil continua a existir por baixo, invisivel: e ele que carrega a
    # caixa de colisao das duas casas e o tempo do golpe. O que se ve e a
    # animacao; o que decide e ele.
    corpo = contacto?(mv)
    if corpo && anim.to_i > 0
      if ev
        tocar_no_character!(ev, anim)
      else
        tocar_no_chao!(anim, *casa_a_frente(2))
      end
    end
    lancar!(:x => $game_player.x, :y => $game_player.y, :dir => $game_player.direction,
            :alvo => ev, :anim => (corpo ? 0 : anim.to_i), :infalivel => inf,
            :cartao_de => (corpo ? nil : anim), :invisivel => corpo,
            :move_id => mv.id, :mv => mv, :nome => nome, :meu => true,
            # No PVP o meu projectil e so o desenho; a conta e do outro lado.
            :so_desenho => pvp?,
            :alcance => alcance_do_lancamento(mv), :curto => corpo,
            :raio => (area?(mv) ? RAIO_EXPLOSAO : 0.0),
            :vel => velocidade_do_lancamento(mv, inf))
    dizer(nome)
  rescue => e
    registar("falha a disparar: #{e.class}: #{e.message}")
  end

  #-----------------------------------------------------------------------------
  # A IA
  #-----------------------------------------------------------------------------
  # Persegue e bate quando chega ao lado. Nao e esperta de proposito: o que se
  # esta a testar e a sensacao dos controlos, nao o adversario.
  # ⚠️ A IA JOGAVA SEM NENHUMA DAS REGRAS QUE EU IMPUS AO JOGADOR.
  #
  # Ela escolhia um golpe ao acaso e batia — sem recarga, sem energia, sem
  # alcance, sem nada a voar. Enquanto o jogador esperava cinco a dez segundos
  # por golpe e gastava energia a correr, ela batia a cada 0,4 s, para sempre,
  # colada. Nao era uma IA dificil: era uma IA que jogava outro jogo.
  #
  # Agora e a mesma mesa. As recargas saem do mesmo `recarga_do_golpe`, os
  # golpes dela voam pelo mesmo sistema de projecteis — e portanto podem ser
  # desviados —, e ela so ataca com o que estiver pronto e ao alcance. Se nada
  # estiver, ela reposiciona-se, que e o que o jogador tambem tem de fazer.
  IA_INTERVALO = 1.2    # segundos, no minimo, entre dois golpes dela

  def distancia_casas(a, b)
    dx = (a.x - b.x).to_f
    dy = (a.y - b.y).to_f
    Math.sqrt((dx * dx) + (dy * dy))
  rescue
    99.0
  end

  def alcance_ia(mv)
    return alcance_do_lancamento(mv) if lancamento?(mv)
    1.4
  rescue
    1.4
  end

  # ⚠️ UM SELVAGEM NAO PODE JOGAR COMO UM DUELISTA.
  #
  # Na caca sao varios ao mesmo tempo, e as regras do duelo (1,2 s entre golpes,
  # folego para seis segundos de corrida) somadas por quatro bichos dao uma
  # chuva constante. Na caca cada um pensa mais devagar, corre mais devagar e
  # cansa-se mais depressa — o desafio esta no numero deles, nao em cada um ser
  # uma parede.
  CACA_INTERVALO = 3.2    # segundos entre golpes de cada selvagem
  CACA_VELOCIDADE = 0.8   # fraccao da velocidade normal
  CACA_FOLEGO    = 26.0   # gasta mais depressa: aguenta ~4 s de perseguicao

  # ⚠️ O INTERVALO LENTO EXISTIA POR CAUSA DA MULTIDAO, QUE JA NAO HA.
  #
  # Os 3,2 s da caca foram postos porque varios atacavam ao mesmo tempo: tres
  # bichos a 3,2 s davam um golpe a cada segundo, que ja era muito. Agora ataca
  # um so — se ele mantivesse os 3,2 s, a pressao caia a um terco e a caca
  # passava a ser uma espera.
  #
  # Quem esta na vez duela ao ritmo do duelo. Os outros nao atacam de todo,
  # portanto a conta fecha: um golpe a cada 1,2 s em vez de um a cada 1,1 s —
  # praticamente a mesma pressao, mas vinda de UM adversario que se ve.
  def intervalo_da_ia(b = nil)
    return IA_INTERVALO if b.nil? || agressor?(b)
    @caca ? CACA_INTERVALO : IA_INTERVALO
  end

  def factor_de_caca
    @caca ? CACA_VELOCIDADE : 1.0
  end

  def custo_de_folego
    @caca ? CACA_FOLEGO : IA_FOLEGO_CUSTO
  end

  # ⚠️ TRES A BATER AO MESMO TEMPO NAO E DIFICIL, E CONFUSO.
  #
  # Eu ja tinha limitado os atacantes a tres — o que resolveu a aritmetica do
  # dano e nao resolveu nada do que se ve. Os oito continuam a vir todos por
  # cima ao mesmo tempo, param todos a uma casa, e o que fica no ecra e uma
  # bola de bonecos onde nao se percebe quem esta a atacar nem de onde vem o
  # golpe. Nao ha jogo nenhum a acontecer ali: ha uma multidao.
  #
  # Uma briga a serio tem um a entrar e os outros a rodear. Isso da uma coisa
  # que a multidao nao dava — um adversario de cada vez, com cara, que se pode
  # ler e ao qual se pode responder. E os outros continuam a fazer pressao,
  # porque estao ali, e porque a vez deles chega.
  #
  # O agressor roda: quando morre, quando se afasta, ou ao fim de uns segundos.
  # Rodar e o que impede isto de virar uma fila de espera previsivel.
  RENDICAO_IA   = 6.5    # segundos ate a vez passar a outro
  ESPERA_ANEL   = 4.5    # casas: a que distancia os outros rodeiam
  LARGA_AGRESSOR = 9.0   # casas: tao longe que ja nao esta na briga

  def agressor_valido?(b)
    return false unless b && b[:ev] && b[:hp].to_i > 0
    return false unless bichos_vivos.include?(b)
    distancia_casas(b[:ev], $game_player) <= LARGA_AGRESSOR
  rescue
    false
  end

  # ⚠️ MATAR UM E LEVAR DO SEGUINTE NO MESMO INSTANTE NAO E DIFICULDADE.
  #
  # Sem isto, o proximo da fila entrava no frame a seguir a o anterior cair — e
  # como ele ja estava por perto a rodear, o golpe dele podia chegar antes de a
  # animacao da morte acabar. Do lado de ca parece que se levou duas vezes pelo
  # mesmo golpe.
  #
  # Um segundo chega para se ver que um caiu e que vem outro. E o intervalo que
  # transforma "uma multidao" em "uma fila de adversarios".
  LUTO_IA = 1.0    # segundos de pausa depois de um deles cair

  # ⚠️ NA CAVERNA OS MESMOS NUMEROS LEEM-SE DE OUTRA MANEIRA.
  #
  # Na arena o jogador escolhe entrar numa briga e fica ali; os selvagens sao
  # quatro, de nivel baixo, e o anel a 4,5 casas cabe no ecra. Na caverna
  # anda-se por corredores, com Pokemon de nivel 60, e um anel de 4,5 casas
  # significa que TUDO o que se ve esta em cima do jogador — foi o que se
  # relatou: "vem para cima como se nao houvesse amanha".
  #
  # Nao muda a IA: muda o espaco onde ela acontece. O anel afasta-se, a vez do
  # agressor passa mais depressa (ele recua e outro entra, em vez de ser o
  # mesmo colado durante seis segundos e meio), e o luto entre mortes e maior.
  ANEL_CAVERNA     = 7.5   # casas
  RENDICAO_CAVERNA = 4.0   # segundos
  LUTO_CAVERNA     = 2.0   # segundos

  def luto_ia;      caverna? ? LUTO_CAVERNA     : LUTO_IA;      end
  def rendicao_ia;  caverna? ? RENDICAO_CAVERNA : RENDICAO_IA;  end
  def anel_ia;      caverna? ? ANEL_CAVERNA     : ESPERA_ANEL;  end

  def agressor
    agora = Time.now.to_f
    if agressor_valido?(@agressor) && @agressor_ate.to_f > agora
      return @agressor
    end

    # Se o anterior deixou de servir por ter MORRIDO (e nao por a vez dele ter
    # acabado), a fila respeita o luto antes de mandar o proximo.
    if @agressor && !agressor_valido?(@agressor) && @agressor[:hp].to_i <= 0
      @pausa_ia_ate = agora + luto_ia if @pausa_ia_ate.to_f < agora
      @agressor = nil
    end
    return nil if @pausa_ia_ate.to_f > agora

    # A vez e de quem esta mais perto — mas nunca do mesmo duas vezes seguidas,
    # havendo outro. Senao o mais rapido do grupo ficava com a briga toda.
    fila = bichos_vivos.select { |b| b[:ev] && !bicho_adormecido?(b) }
                       .sort_by { |b| distancia_casas(b[:ev], $game_player) }
    return nil if fila.empty?
    novo = fila.find { |b| !b.equal?(@agressor) } || fila.first
    if !novo.equal?(@agressor)
      registar("agressor: #{(novo[:pkmn].speciesName rescue '?')}")
    end
    @agressor = novo
    @agressor_ate = agora + rendicao_ia
    @agressor
  rescue
    nil
  end

  def agressor?(b)
    a = @agressor
    a && b.equal?(a)
  end

  def pensar_ia!
    return if pvp?    # do outro lado esta uma pessoa
    quem = agressor
    return unless quem
    pensar_bicho!(quem)
  rescue => e
    log("falha na IA: #{e.class}: #{e.message}")
  end

  #-----------------------------------------------------------------------------
  # A CABECA DELES
  #
  # ⚠️ ESCOLHER AO ACASO ENTRE OS GOLPES PRONTOS NAO E UMA IA.
  #
  # Era o que estava: sorteava-se um golpe ao alcance e pronto. O resultado e o
  # que o jogador descreveu — todos iguais, todos a vir para cima, um Charmander
  # a dar cabecadas num Bulbasaur em vez de o queimar.
  #
  # Agora cada golpe leva uma NOTA e joga-se o melhor. A nota tem quatro
  # parcelas, e todas saem de dados que ja existem:
  #
  #   dano      — a percentagem da vida do alvo que aquele golpe tira, com a
  #               tabela de tipos ja dentro. E daqui que sai "usar fogo contra
  #               planta": nao ha regra nenhuma sobre isso, e so a conta.
  #   estado    — paralisar ou adormecer vale muito, e vale MAIS contra alguem
  #               mais forte: e a unica forma de um nivel 5 magoar um nivel 50.
  #   distancia — quem tem golpe de longe prefere-o e mantem-se longe.
  #   preparo   — subir os proprios atributos, mas so no principio e so uma vez.
  #
  # ⚠️ E ha ruido de proposito. Uma IA que joga sempre o melhor golpe e
  # previsivel ao segundo combate; 15% de desvio na nota faz com que ela erre de
  # vez em quando, como um treinador erra.
  #-----------------------------------------------------------------------------
  ALCANCE_LONGO = 5.0    # a partir daqui um golpe conta como "de longe"
  RUIDO_IA      = 0.15

  def forca_relativa(meu_pkmn, dele_pkmn)
    a = ((meu_pkmn.level.to_i + 1) * (meu_pkmn.totalhp.to_i + 1)).to_f
    b = ((dele_pkmn.level.to_i + 1) * (dele_pkmn.totalhp.to_i + 1)).to_f
    return 1.0 if a <= 0
    b / a
  rescue
    1.0
  end

  def nota_do_golpe(ficha, alvo_pkmn, alvo_hp, mv, dist, alvo_tem_estado)
    dados = (GameData::Move.get(mv.id) rescue nil)
    return -1.0 unless dados
    alcance = alcance_ia(mv)
    return -1.0 if dist > alcance

    nota = 0.0

    # 1. quanto tira, em percentagem da vida que resta ao alvo
    base, mult = dano_seco(ficha[:pkmn], alvo_pkmn, mv)
    if base > 0.0
      d = base * mult
      return -1.0 if mult <= 0.0        # nao afecta: nunca vale a pena
      nota += (d / [alvo_hp.to_f, 1.0].max) * 100.0
    end

    # 2. o efeito. Contra alguem mais forte, prender vale mais do que arranhar.
    #
    # ⚠️ AQUI PERGUNTAVA-SE SO PELO TIPO, E QUEM APLICA PERGUNTA POR MAIS.
    #
    # O `aplicar_estado_no_bicho!` decide pelo `estado_do_golpe`, que olha
    # PRIMEIRO para o `function_code` (`SleepTarget`, `AttractTarget`) e so
    # depois cai no tipo. Esta linha olhava so para o tipo.
    #
    # Os dois discordavam exactamente nos golpes que adormecem e encantam: o
    # Sleep Powder e do tipo Planta, que nao esta no `ESTADOS_POR_TIPO`. Logo
    # esta conta nao lhe dava bonus nenhum — e um golpe sem forca tambem nao
    # ganha nada na parte do dano. Ficava com nota ZERO, e o `next if n <= 0.0`
    # la em cima atirava-o fora.
    #
    # Resultado visto em jogo: um Venusaur com Razor Leaf, Sleep Powder, Leech
    # Seed e Growth usava o Razor Leaf e mais nada — o Growth uma vez, e os
    # outros dois nunca. Do lado de quem joga isso le-se como "ele so usa o
    # primeiro ataque", e foi confundido com a trava dos Choice (que esta
    # inocente: testei-a, e ela so conhece Band, Specs e Scarf).
    #
    # Atingia todo o adormecer e encantar do jogo: Spore, Hypnosis, Sing,
    # Lovely Kiss, Grass Whistle, Dark Void, Attract. A IA nunca os escolheu.
    #
    # Passa a perguntar pela MESMA porta por onde o efeito e aplicado. Enquanto
    # as duas perguntas forem a mesma funcao, nao podem voltar a divergir.
    estado = estado_do_golpe(dados)
    if estado && !alvo_tem_estado
      superior = forca_relativa(ficha[:pkmn], alvo_pkmn)
      nota += 20.0
      nota += 25.0 if superior > 1.6      # o alvo e bem mais forte
      nota += 15.0 if dados.category == 2 # e um golpe SO de estado: e para isso
    end

    # 3. distancia: pode bater sem levar de volta
    nota += 12.0 if alcance >= ALCANCE_LONGO && dist > 2.0
    nota -= 6.0 if alcance <= ALCANCE_CORPO && dist > 1.5   # cai perto

    # 4. preparar-se, mas so com o combate a comecar e uma vez so
    if buff?(mv)
      nota = tem_buff?(ficha[:pkmn]) ? -1.0 : 26.0
    end

    nota * (1.0 + ((rand - 0.5) * 2 * RUIDO_IA))
  rescue
    -1.0
  end

  #-----------------------------------------------------------------------------
  # A TRAVA DOS CHOICE
  #
  # Band, Specs e Scarf dao +50% e, no jogo, prendem o Pokemon ao primeiro golpe
  # que ele usar. A trava entrou por escolha do utilizador — na ronda anterior
  # so tinha entrado o bonus.
  #
  # ⚠️ A TRAVA MORRE COM O ITEM, E ISSO NAO E UM DETALHE.
  #
  # A pergunta "esta travado?" nao le uma marca antiga, le o item que ele tem
  # AGORA. Assim um Thief ou um Knock Off que lhe leve o Scarf devolve-lhe os
  # quatro golpes no mesmo instante — que e exactamente o que acontece no jogo,
  # e sai de graca por se ter feito a pergunta pela ordem certa.
  #
  # ⚠️ E a marca e por Pokemon, nao por lado.
  #
  # Eu, o ajudante e cada selvagem podem trazer um Choice ao mesmo tempo. Uma
  # marca unica prendia-os todos ao golpe do primeiro que disparasse.
  def golpe_travado(pkmn)
    return nil unless pkmn
    return nil unless (AnilArenaItens.trava_de_escolha?(pkmn) rescue false)
    (@choice_trava ||= {})[pkmn.object_id]
  rescue
    nil
  end

  def escolha_permite?(pkmn, mv)
    t = golpe_travado(pkmn)
    return true if t.nil?
    t == (mv.id rescue nil)
  rescue
    true
  end

  def marcar_escolha!(pkmn, mv)
    return unless pkmn && mv
    return unless (AnilArenaItens.trava_de_escolha?(pkmn) rescue false)
    @choice_trava ||= {}
    @choice_trava[pkmn.object_id] ||= (mv.id rescue nil)
  rescue
    nil
  end

  def escolher_golpe(ficha, alvo_pkmn, alvo_hp, dist, alvo_tem_estado)
    agora = Time.now.to_f
    melhor = nil
    melhor_nota = 0.0
    4.times do |i|
      mv = (ficha[:pkmn].moves[i] rescue nil)
      next unless mv && mv.id
      next if ficha[:prontos][i].to_f > agora
      next if seguravel(mv) == :escudo
      next if armadilha?(mv)
      # A IA obedece a trava como eu obedeço: se ha Choice, so este golpe existe.
      next unless escolha_permite?(ficha[:pkmn], mv)
      n = nota_do_golpe(ficha, alvo_pkmn, alvo_hp, mv, dist, alvo_tem_estado)
      next if n <= 0.0
      if n > melhor_nota
        melhor_nota = n
        melhor = [i, mv]
      end
    end
    # ⚠️ MARCA-SE AQUI PORQUE AQUI E QUE E UMA DECISAO.
    #
    # Esta funcao tem dois chamadores e ambos usam o que ela devolve — ela nao
    # serve para imaginar, ao contrario do `dano_seco`. O golpe que sai daqui vai
    # mesmo ser usado, e portanto e este que prende.
    marcar_escolha!(ficha[:pkmn], melhor[1]) if melhor
    melhor
  rescue
    nil
  end

  def pensar_bicho!(b)
    return if bicho_impedido?(b)
    ev = b[:ev]
    return unless ev
    agora = Time.now.to_f
    return if agora < b[:proximo].to_f
    # Sem folego nao se ataca: e a janela para contra-atacar.
    return if b[:cansada]

    alvo_ev = alvo_da_ia(b)
    # ⚠️ AGORA PODE NAO HAVER ALVO NENHUM.
    #
    # Ate aqui esta funcao devolvia sempre alguem — no pior caso o jogador. Na
    # batalha automatica ela pode devolver nada: eu sai da lista, e se o
    # ajudante cair nao sobra ninguem para atacar. Sem esta linha, a pergunta
    # seguinte (`vista_livre_cache?`) recebia nil e rebentava a cada tique.
    return unless alvo_ev
    # ⚠️ QUEM NAO VE NAO ATIRA.
    #
    # Sem isto eles disparavam com uma parede pela frente: o golpe rebentava na
    # pedra a uma casa da boca e o Pokemon ficava ali a insistir. Nao e
    # dificuldade nenhuma — e um boneco a fazer uma coisa que qualquer um ve
    # que nao vai resultar. Sem vista, ele anda (ver o `mover_bicho!`).
    return unless vista_livre_cache?(ev, alvo_ev, [b[:id], :atacar])
    contra_aliado = !alvo_ev.equal?($game_player)
    alvo_pkmn = contra_aliado ? (@aliado ? @aliado[:pkmn] : @meu) : @meu
    alvo_hp   = contra_aliado ? (@aliado ? @aliado[:hp] : @hp_meu) : @hp_meu
    tem_estado = contra_aliado ? false : !estado_activo.nil?
    return unless alvo_pkmn
    dist = distancia_casas(ev, alvo_ev)

    escolha = escolher_golpe(b, alvo_pkmn, alvo_hp, dist, tem_estado)
    return unless escolha
    i, mv = escolha
    b[:prontos][i] = agora + (recarga_do_golpe(mv) / 60.0)
    b[:proximo] = agora + intervalo_da_ia(b)
    if buff?(mv)
      aplicar_buff!(b[:pkmn], mv)
      tocar_no_character!(ev, animacao_do_golpe(mv.id))
      narrar("#{(b[:pkmn].speciesName rescue '')} se preparou!")
      return
    end
    atacar_ia!(b, mv)
  rescue => e
    log("falha a pensar: #{e.class}: #{e.message}")
  end

  def atacar_ia!(b, mv)
    ev = b[:ev]
    return unless ev
    nome = (GameData::Move.get(mv.id).name rescue mv.id.to_s)
    anim = animacao_do_golpe(mv.id)
    alvo = alvo_da_ia(b)
    return unless alvo
    no_aliado = !alvo.equal?($game_player)
    # Marcado como feixe na oficina: nao voa nada. Desenha-se a linha e o dano
    # sai por baixo, pelo caminho de sempre dos golpes imediatos.
    saida = saida_do_golpe(mv, anim)
    e_feixe = (saida == :feixe)
    feixe_de_alguem!(ev, alvo, anim) if e_feixe
    if saida == :voo
      inf = infalivel?(mv.id)
      dar_bote!(ev, (alvo.x rescue ev.x), (alvo.y rescue ev.y)) if contacto?(mv)
      lancar!(:x => ev.x, :y => ev.y, :dir => (ev.direction rescue 2),
              :alvo => alvo, :anim => anim.to_i, :infalivel => inf,
              :move_id => mv.id, :mv => mv, :nome => nome, :meu => false, :ia => true,
              :bicho => b, :no_aliado => no_aliado,
              :alcance => alcance_do_lancamento(mv), :curto => contacto?(mv),
              :vel => velocidade_do_lancamento(mv, inf))
      narrar("#{(b[:pkmn].speciesName rescue '')} usou #{nome}!")
      return
    end
    # ⚠️ Uma animacao tocada com o alvo IGUAL ao utilizador nao tem linha: o
    # `setLineTransform` recebe dois pontos no mesmo sitio e o golpe fica
    # desenhado em cima de quem o lancou, sem direccao. E preciso que a ancora
    # de quem ataca seja ELE e a do alvo sejamos nos — e, aqui, quem toca a
    # animacao e sempre o jogador, portanto o alvo e o que se passa.
    if no_aliado
      tocar_no_character!(alvo, anim) unless e_feixe
      ferir_aliado!(dano(b[:pkmn], @aliado[:pkmn], mv), mv, ev)
      narrar("#{(b[:pkmn].speciesName rescue '')}: #{nome}")
      return
    end
    tocar_no_character!($game_player, anim) unless e_feixe
    return if clone_comeu?
    if escudo_de_pe?
      aparar!
      return
    end
    d = dano_do_bicho(b, mv)
    @hp_meu = [@hp_meu - d, 0].max
    talvez_aplicar_estado!(mv.id) if d > 0 || golpe_de_estado?(mv)
    empurrar!($game_player, ev, empurrao_de(mv)) if d > 0
    dizer(mensagem_do_acerto("#{(b[:pkmn].speciesName rescue '')}: #{nome}", d, mv))
    terminar_derrota! if @hp_meu <= 0
  rescue => e
    log("falha a atacar (IA): #{e.class}: #{e.message}")
  end

  def dano_do_bicho(b, mv)
    return 0 if golpe_de_estado?(mv)
    dano(b[:pkmn], @meu, mv)
  rescue
    0
  end

  def dano_do_inimigo(mv)
    b = bicho_focado
    b ? dano_do_bicho(b, mv) : 0
  end

  def dano_do_inimigo(mv)
    return 0 if golpe_de_estado?(mv)
    dano(@inimigo, @meu, mv)
  rescue
    0
  end

  # ⚠️ O INIMIGO ANDAVA PELO MOTOR, E O MOTOR SO SABE ANDAR EM CASAS.
  #
  # Eu tinha tirado a grelha ao jogador e deixado o adversario com o
  # `move_toward_player`, que da um passo de casa inteira de cada vez. Ficava um
  # a deslizar e o outro aos saltos — e como e o inimigo que persegue, era o
  # movimento dele que se via mais. Anda pela mesma conta: posicao verdadeira,
  # casas por segundo, relogio.
  #
  # Ele para a uma casa de distancia: e dali que os golpes de contacto dele
  # alcancam, e assim nao fica em cima do jogador.
  PARAGEM_IA = 1.1          # casas
  IA_FOLEGO_CUSTO  = 16.0   # energia por segundo a perseguir (~6 s de corrida)
  IA_FOLEGO_REGEN  = 10.0   # a recuperar enquanto se arrasta
  IA_CANSADA_FACTOR = 0.45  # a que velocidade anda sem folego

  #-----------------------------------------------------------------------------
  # QUEM NAO SE VE NAO SE TRATA
  #
  # ⚠️ 93% DO TRABALHO POR FRAME ERA PARA NINGUEM, E ISSO MEDIU-SE.
  #
  # A caverna tem trinta habitantes (`POPULACAO`) espalhados por um mapa de
  # 110x80. O ecra ve 16x12 casas — o canto mais afastado que se ve esta a dez
  # casas do jogador.
  #
  # Contado com as grelhas de colisao a serio, em 4000 posicoes ao acaso por
  # mapa:
  #
  #     Tunel Rocha       1,6 dos 30 no ecra    95% fora
  #     Safari Planicie   2,5 dos 30 no ecra    92% fora
  #     media             2,0 no ecra           93% fora
  #
  # E a cada um desses vinte e oito que ninguem ve fazia-se, sessenta vezes por
  # segundo: um passo com colisao, o contorno de obstaculos, o destravador, a
  # cor do sprite, o sinal de estado e a posicao da barra de vida.
  #
  # ⚠️ CATORZE CASAS, E NAO DEZ.
  #
  # Dez e o que se ve. Com dez exacto, um bicho acordava no instante em que
  # entrasse no ecra — e entrava parado, porque ainda nao tinha dado o primeiro
  # passo. As quatro casas a mais sao a margem para ele ja vir a andar quando
  # aparece.
  #
  # ⚠️ E NAO E "DESLIGAR A IA": E ADIAR.
  #
  # Ninguem sai da lista, ninguem perde vida, estado nem alvo. Quando o jogador
  # se aproxima, o bicho continua exactamente de onde estava. A diferenca entre
  # isto e o `DESISTE_RAIO` (que LARGA quem se afasta doze casas) e essa: aquele
  # esquece, este adormece.
  VISTA_TICK = 14.0   # casas: a partir daqui o bicho fica em pausa

  def longe_para_tratar?(b)
    return false unless $game_player
    ev = b[:ev]
    return false unless ev
    dx = (ev.x - $game_player.x).abs
    return true if dx > VISTA_TICK
    dy = (ev.y - $game_player.y).abs
    dy > VISTA_TICK
  rescue
    false
  end

  def mover_inimigo!
    return if pvp?
    dt = [(@delta || (1.0 / 60.0)), 0.1].min
    bichos_vivos.each do |b|
      next if longe_para_tratar?(b)
      mover_bicho!(b, dt)
    end
  rescue => e
    registar("falha a mover: #{e.class}: #{e.message}")
  end

  # ⚠️ UMA CAVERNA POVOADA NAO PODE PENSAR POR TODOS AO MESMO TEMPO.
  #
  # Com trinta Pokemon no mapa, correr a perseguicao de todos a cada frame e
  # trabalho a mais para nada: vinte e tal deles estao a dezenas de casas, fora
  # do ecra, e ninguem ve o que eles fazem.
  #
  # Quem esta longe fica onde esta. Nao e uma simplificacao visivel — ninguem
  # o ve — e e o que permite ter uma caverna com gente em vez de uma torneira a
  # despejar tres de cada vez ao pe de nos.
  DESPERTA = 16.0   # casas: a partir daqui um selvagem ganha vida

  def bicho_adormecido?(b)
    return false unless b && b[:ev] && $game_player
    distancia_casas(b[:ev], $game_player) > DESPERTA
  rescue
    false
  end

  # ⚠️ ERAM DOIS MOTORES A MEXER NO MESMO BONECO, E ESSE E O TREMOR.
  #
  # Quando a autoridade passou para o servidor, ficou a faltar desligar isto: a
  # perseguicao local continuou a correr, a 60 vezes por segundo, a empurrar o
  # bicho na direccao do jogador — enquanto dez vezes por segundo chegava um
  # retrato do servidor e o puxava de volta para onde ele REALMENTE esta.
  #
  # Empurra, puxa, empurra, puxa, dez vezes por segundo. Nao e um problema de
  # rede nem de suavizacao: sao duas cabecas a discutir a mesma casa, e o que
  # se ve e o boneco a vibrar entre as duas respostas. Era tambem isto que o
  # encostava as paredes — a IA local empurrava-o contra a pedra nos 90 ms em
  # que mandava.
  #
  # Quem manda manda sozinho. O `:do_servidor` e posto no primeiro retrato que
  # chega para aquele bicho, portanto os adoptados e os que nascem so do lado
  # de ca continuam a mexer-se como sempre.
  def mover_bicho!(b, dt)
    return if b[:do_servidor] && (AnilRaidCaverna.servidor_manda? rescue false)
    return if bicho_impedido?(b)
    return if bicho_adormecido?(b)
    ev = b[:ev]
    return unless ev
    return if (ev.jumping? rescue false)
    # O passeio do plugin usa o lerp do motor; deixa-lo a correr por baixo da
    # perseguicao dava um boneco a tremer entre dois destinos.
    (ev.instance_variable_set(:@move_timer, nil) rescue nil) if b[:adoptado]
    # ⚠️ E SE ELE JA ESTIVER DENTRO DA PEDRA, TIRA-SE DE LA.
    #
    # O empurrao deixou de o meter em sitios impossiveis, mas isso nao arranja
    # quem ja la esta — de um build anterior, de um salto do motor, de um mapa
    # que mudou por baixo dele. Um bicho numa casa fechada fica a empurrar
    # contra a parede para sempre, e visto de fora parece que a IA partiu.
    #
    # A rede corre aqui porque este e o sitio por onde todos passam, a cada
    # frame, e custa uma consulta a um cache quando esta tudo bem.
    if casa_de_pedra?(ev.x, ev.y)
      livre = casa_livre_perto(ev.x, ev.y, 4, 1)
      if livre
        (ev.moveto(livre[0], livre[1]) rescue nil)
        (ev.instance_variable_set(:@move_timer, nil) rescue nil)
      end
      return
    end
    rx = (ev.instance_variable_get(:@real_x) rescue 0).to_f
    ry = (ev.instance_variable_get(:@real_y) rescue 0).to_f
    # ⚠️ PERSEGUIR SEMPRE O JOGADOR ERA O QUE ANULAVA A ESCOLHA DE ALVO.
    #
    # Havia duas respostas a "quem e o inimigo": o `alvo_da_ia` escolhia pelo
    # mais proximo, e esta funcao vinha atras do jogador sem perguntar nada. A
    # segunda desfazia a primeira — andando sempre para mim, eu acabava sempre
    # por ser o mais proximo, e o ajudante nunca chegava a ser escolhido.
    #
    # Andar atras de um e bater noutro nao faz sentido nenhum. A mesma pergunta
    # serve as duas coisas.
    alvo_ia = alvo_da_ia(b)
    if alvo_ia.nil?
      # Sem ninguem para atacar (a automatica com o ajudante caido), ele fica
      # onde esta em vez de vir ter comigo.
      parar_evento!(ev)
      return
    end
    prx = (alvo_ia.instance_variable_get(:@real_x) rescue 0).to_f
    pry = (alvo_ia.instance_variable_get(:@real_y) rescue 0).to_f
    dx = prx - rx
    dy = pry - ry
    dist = Math.sqrt((dx * dx) + (dy * dy)) / Game_Map::REAL_RES_X.to_f

    # ⚠️ QUEM PODE BATER DE LONGE NAO SE COLA A NOS.
    #
    # Todos vinham para cima porque a distancia de paragem era sempre uma casa.
    # Um Pokemon com Water Gun pronto nao tem motivo nenhum para chegar ao pe de
    # quem lhe pode dar uma dentada: fica a quatro casas e dispara. E se nos
    # aproximamos, recua — que e a diferenca entre uma parede e um adversario.
    paragem = distancia_desejada(b)
    b[:energia] = ENERGIA_MAX if b[:energia].nil?
    if dist < (paragem - 1.0) && !b[:cansada]
      recuar_bicho!(b, dt, dx, dy, rx, ry)
      return
    end
    if dist <= paragem
      b[:energia] = [b[:energia] + (ENERGIA_REGEN * dt), ENERGIA_MAX].min
      b[:cansada] = false if b[:energia] >= ENERGIA_MAX * 0.5
      parar_evento!(ev)
      return
    end
    if b[:cansada]
      b[:energia] = [b[:energia] + (IA_FOLEGO_REGEN * dt), ENERGIA_MAX].min
      b[:cansada] = false if b[:energia] >= ENERGIA_MAX * 0.5
    else
      b[:energia] -= custo_de_folego * dt
      if b[:energia] <= 0.0
        b[:energia] = 0.0
        b[:cansada] = true
        dizer("#{(b[:pkmn].speciesName rescue 'Inimigo')} está sem fôlego!") if b.equal?(bicho_focado)
      end
    end

    # ⚠️ COM VISTA VAI-SE A DIREITO; SEM VISTA, PELO CAMINHO.
    #
    # A linha recta e o que se ve num campo aberto, e e ela que da a perseguicao
    # a cara dela — nao se troca por um caminho calculado enquanto ela servir.
    # So quando a recta atravessa pedra e que ela deixa de ser um caminho e
    # passa a ser uma parede, e e ai que o campo manda.
    #
    # Assim que ele dobra a esquina e volta a ver o alvo, a recta volta: o
    # caminho serve para CHEGAR a ter vista livre, nao para substituir a caca.
    unless vista_livre_cache?(ev, alvo_ia, [b[:id], :caminho])
      atalho = rumo_do_campo(ev, alvo_ia, rx, ry)
      if atalho
        dx = atalho[0]
        dy = atalho[1]
      end
    end
    n = Math.sqrt((dx * dx) + (dy * dy))
    return if n < 0.001
    dx /= n
    dy /= n
    nova = (dx.abs > dy.abs) ? ((dx > 0) ? 6 : 4) : ((dy > 0) ? 2 : 8)
    (ev.instance_variable_set(:@direction, nova) rescue nil)
    vel = [velocidade_livre(b[:pkmn]), 1.0].max
    vel *= factor_de_caca
    vel *= IA_CANSADA_FACTOR if b[:cansada]
    passo = vel * Game_Map::REAL_RES_X * dt
    # ⚠️ O SELVAGEM NEM SEQUER TENTAVA DESVIAR. ANDAVA SEMPRE A DIREITO.
    #
    # O ajudante ja tinha o `andar_por_casas!` por tras da vista; este nao tinha
    # nada — o passo era recusado e ele ficava ali, sem plano B nenhum. E como
    # ele e quem persegue, e o movimento dele que se ve mais.
    #
    # A regra e a mesma que se pos no ajudante, e pelo mesmo motivo: nao se
    # tenta adivinhar PORQUE o passo falhou (terreno, corpo, evento do mapa sem
    # tile_id que o `passable?` nem ve) — olha-se para o resultado. Nao andou,
    # entao a linha recta nao serve, e contorna-se.
    # Chegou aqui: ele QUER andar. E o momento certo de perguntar se anda.
    return if destravar!(b, rx, ry, passo)
    rx0 = rx
    ry0 = ry
    nx = rx + (dx * passo)
    rx = nx if casa_livre_para_evento?(ev, nx, ry)
    ny = ry + (dy * passo)
    ry = ny if casa_livre_para_evento?(ev, rx, ny)
    if (rx - rx0).abs < 0.01 && (ry - ry0).abs < 0.01
      andar_por_casas!(b, dx, dy, rx0, ry0, passo)
      return
    end
    ev.instance_variable_set(:@real_x, rx)
    ev.instance_variable_set(:@real_y, ry)
    ev.instance_variable_set(:@x, (rx / Game_Map::REAL_RES_X.to_f).round)
    ev.instance_variable_set(:@y, (ry / Game_Map::REAL_RES_Y.to_f).round)
    # ⚠️ A RELVA CORTA O BONECO AO MEIO, E QUEM DESFAZ ISSO E O `update_move`.
    #
    # O `bush_depth` esconde a metade de baixo de quem esta dentro do mato, e so
    # e recalculado quando o motor da um passo. Nos escrevemos a posicao a mao e
    # nunca damos esse passo — por isso o corte ficava colado ao boneco depois
    # de ele sair da relva, como o jogador viu. Recalcula-se a cada passo nosso.
    (ev.calculate_bush_depth rescue nil)
    animar_evento!(ev)
  rescue
    nil
  end

  # Puxa um valor para o centro da casa mais proxima, no maximo `passo`.
  def para_o_centro(v, res, passo)
    centro = (v / res.to_f).round * res.to_f
    d = centro - v
    return centro if d.abs <= passo
    v + ((d > 0) ? passo : -passo)
  rescue
    v
  end

  def andar_por_casas!(b, dx, dy, rx, ry, passo)
    ev = b[:ev]
    ordem = (dx.abs > dy.abs) ? [:x, :y] : [:y, :x]
    ordem.each do |eixo|
      if eixo == :x
        next if dx.abs < 0.05
        ny = para_o_centro(ry, Game_Map::REAL_RES_Y, passo)
        nx = rx + ((dx > 0 ? 1.0 : -1.0) * passo)
        next unless casa_livre_para_evento?(ev, nx, ny)
        pousar_a_mao!(ev, nx, ny, (dx > 0) ? 6 : 4)
        return true
      else
        next if dy.abs < 0.05
        nx = para_o_centro(rx, Game_Map::REAL_RES_X, passo)
        ny = ry + ((dy > 0 ? 1.0 : -1.0) * passo)
        next unless casa_livre_para_evento?(ev, nx, ny)
        pousar_a_mao!(ev, nx, ny, (dy > 0) ? 2 : 8)
        return true
      end
    end
    # ⚠️ OS DOIS EIXOS BLOQUEADOS NAO QUEREM DIZER "NAO HA CAMINHO".
    #
    # Ate aqui tentavam-se so os dois eixos que APONTAM ao alvo. Com uma arvore
    # exactamente no meio e o alvo na diagonal, os dois falham — e o bicho para,
    # encostado ao tronco, a empurrar contra ele para sempre. E o que se viu:
    # "ele vai em linha reta, nao tem IA para desviar".
    #
    # Falta o gesto obvio: dar um passo de LADO e tentar outra vez pelo outro
    # lado do obstaculo. Sao duas hipoteses (as perpendiculares ao rumo), e uma
    # delas quase sempre resolve.
    #
    # ⚠️ E ELE TEM DE SE COMPROMETER COM UM LADO.
    #
    # Escolhendo a melhor a cada frame, ele oscila: contorna pela esquerda, o
    # eixo principal desbloqueia por um instante, ele volta, bloqueia outra vez,
    # tenta pela direita. O que se ve e um bicho a tremer contra a arvore — o
    # mesmo sintoma do "tremer" que ja caçamos duas vezes, agora por indecisao
    # em vez de dois donos.
    #
    # Guardado o lado por meio segundo, o contorno le-se como uma decisao.
    contornar!(b, dx, dy, rx, ry, passo)
  rescue
    false
  end

  CONTORNO_SEG = 0.55   # quanto tempo ele mantem o lado escolhido

  def contornar!(b, dx, dy, rx, ry, passo)
    ev = b[:ev]
    return false unless ev
    agora = Time.now.to_f
    # O lado de antes, enquanto ainda vale.
    lado = (b[:contorno_ate].to_f > agora) ? b[:contorno] : nil
    # As duas perpendiculares ao rumo, em casas.
    perp = (dx.abs > dy.abs) ? [[0.0, 1.0], [0.0, -1.0]] : [[1.0, 0.0], [-1.0, 0.0]]
    ordem = lado ? [lado] : perp
    ordem.each do |(ux, uy)|
      nx = rx + (ux * passo)
      ny = ry + (uy * passo)
      next unless casa_livre_para_evento?(ev, nx, ny)
      b[:contorno] = [ux, uy]
      b[:contorno_ate] = agora + CONTORNO_SEG
      pousar_a_mao!(ev, nx, ny,
                    (ux.abs > uy.abs) ? ((ux > 0) ? 6 : 4) : ((uy > 0) ? 2 : 8))
      return true
    end
    # O lado guardado deixou de servir: esquece-se e tenta-se o outro no frame
    # seguinte, em vez de ficar preso a uma escolha que ja nao passa.
    if lado
      b[:contorno] = nil
      b[:contorno_ate] = 0.0
    end
    parar_evento!(ev)
    false
  rescue
    false
  end

  #-----------------------------------------------------------------------------
  # O DESTRAVADOR
  #
  # ⚠️ DEIXEI DE TENTAR ADIVINHAR PORQUE E QUE ELE PRENDE.
  #
  # Ja se corrigiram quatro causas diferentes para o mesmo sintoma: a colisao
  # sem saida, a assimetria do corpo do ajudante, os dois testes que discordavam,
  # e os eventos do mapa que o `passable?` nem ve. E ele prendeu outra vez.
  #
  # Isso e sinal de que a lista nao esta fechada — e provavelmente nunca estara,
  # porque o mapa tem coisas que nenhum destes testes conhece. Portanto para-se
  # de enumerar causas e trata-se do SINTOMA, que e sempre o mesmo e e facil de
  # medir: ele quer andar e a coordenada nao muda.
  #
  # Tres degraus, do mais suave ao mais bruto:
  #
  #   0,7 s   tenta um passo em qualquer direccao que o mapa deixe passar —
  #           inclusive nas diagonais, que o andar normal nunca usa e que
  #           resolvem a maioria dos cantos.
  #
  #   3,0 s   nenhuma das oito serviu. Nao ha caminho a pe: procura-se a casa
  #           livre mais proxima e poe-se la, de uma vez.
  #
  # O degrau grande e feio de proposito. Um boneco que salta uma casa nota-se
  # meio segundo; um boneco preso para sempre estraga a partida toda — e o
  # utilizador ja o viu tres vezes.
  #-----------------------------------------------------------------------------
  # ⚠️ AS UNIDADES AQUI SAO REAIS, E EU TRATEI-AS COMO CASAS.
  #
  # `passo = vel * Game_Map::REAL_RES_X * dt` — ou seja, rx/ry contam-se em
  # unidades reais, e uma casa vale 128 delas. O `MOVEU_MIN = 1.0` que estava
  # aqui nao era "uma casa": era 1/128 de casa, meio pixel.
  #
  # Com esse limiar, QUALQUER estremecao contava como ter andado. A ancora
  # voltava a ser posta na posicao do momento, o relogio reiniciava, e o
  # destravador respondia "ele esta a andar, nao e preciso nada" — exactamente
  # ao bicho que treme encostado a arvore, que e o unico caso para que ele foi
  # escrito. Estava desligado de raiz e a funcionar como desligado.
  #
  # 48 unidades e pouco mais de um terco de casa. Um passo a serio faz centenas;
  # um tremor faz meia duzia. Fica larga a distincao entre as duas coisas.
  MOVEU_MIN    = 48.0    # unidades reais (128 = uma casa)
  PRESO_SEG    = 0.7     # sem sair do sitio, tenta outro rumo
  PRESO_LIMITE = 3.0     # sem sair do sitio, muda-se de sitio a forca

  # ⚠️ E O SAFANAO NAO PODE REINICIAR O RELOGIO DO DEGRAU GRANDE.
  #
  # O degrau 1 punha `preso_desde = agora`. Como ele corre a cada 0,7 s e o
  # degrau 2 so acorda aos 3,0 s, o degrau 2 nunca chegava a acontecer: cada
  # safanao adiava-o mais 0,7 s, para sempre. O escape a forca existia no
  # codigo e era inalcancavel.
  #
  # Agora sao dois relogios independentes. O do safanao mede a cadencia dos
  # safanoes; o da ancora mede PROGRESSO, e so o deslocamento a mexe.
  SAFANAO_DURA = 0.45    # quanto tempo ele mantem o rumo do safanao

  # ⚠️ E UM SAFANAO DE UM FRAME NAO E UM DESVIO, E UM ESTREMECAO.
  #
  # O safanao antigo dava um empurrao de `passo * 1.6` — o valor de um frame — e
  # no frame seguinte a IA voltava a apontar ao alvo e desfazia-o. Repetido,
  # isto E o tremor que se ve no ecra. O que faz dele um desvio e comprometer-se
  # com o rumo o tempo suficiente para sair mesmo do sitio, como ja se fez no
  # `contornar!` pelo mesmo motivo.
  #
  # A velocidade continua a ser a de andar (um `passo` por frame). O que muda e
  # a duracao, nao a distancia por frame — senao ele teleportava-se de lado.

  # ⚠️ E HA O OSCILADOR, QUE ENGANA QUALQUER LIMIAR FINO.
  #
  # Safanao para fora, a IA puxa de volta, safanao para fora. A ancora fina ve
  # movimento real de cada vez e reinicia — e o bicho anda a vida inteira entre
  # duas casas sem nunca chegar ao degrau 2. Por isso ha uma segunda ancora,
  # larga e lenta: se em 6 segundos a QUERER andar ele nao se afastou duas
  # casas do sitio onde estava, nao interessa quanto se mexeu pelo caminho —
  # nao esta a ir a lado nenhum.
  VOLTA_RAIO   = 256.0   # duas casas
  VOLTA_SEG    = 6.0
  SAFANOES_MAX = 5       # safanoes sem progresso antes de desistir do pe

  # ⚠️ SO CONTA COMO PRESO QUEM ESTAVA A TENTAR ANDAR.
  #
  # Um bicho parado de proposito — a manter distancia, a espera da recarga —
  # tambem nao muda de coordenada. Sem esta distincao, o destravador punha-o a
  # saltitar quando ele estava exactamente onde queria estar.
  def destravar!(b, rx, ry, passo)
    return false unless b && b[:ev]
    ev = b[:ev]
    agora = Time.now.to_f

    # ── a ancora larga: sai daqui de vez, ou nao sai ─────────────────────────
    lx = b[:longe_x]
    ly = b[:longe_y]
    if lx.nil? ||
       (((rx - lx) * (rx - lx)) + ((ry - ly) * (ry - ly))) >= (VOLTA_RAIO * VOLTA_RAIO)
      b[:longe_x] = rx
      b[:longe_y] = ry
      b[:longe_desde] = agora
      b[:safanoes] = 0
    end
    b[:longe_desde] ||= agora
    teimoso = (agora - b[:longe_desde].to_f) >= VOLTA_SEG

    # ── a ancora fina: mediu-se em distancia, e nao eixo a eixo ──────────────
    #
    # O teste antigo era `(rx-ex).abs > MIN || (ry-ey).abs > MIN`: por eixo. Uma
    # diagonal de 0,9 casa em cada eixo — quase uma casa e meia andadas — dava
    # "nao andou" nos dois. A distancia nao tem esse buraco.
    ex = b[:preso_x]
    ey = b[:preso_y]
    if ex.nil? ||
       (((rx - ex) * (rx - ex)) + ((ry - ey) * (ry - ey))) >= (MOVEU_MIN * MOVEU_MIN)
      b[:preso_x] = rx
      b[:preso_y] = ry
      b[:preso_desde] = agora
      b[:safanao_rumo] = nil
      b[:safanao_ate] = 0.0
      return false
    end
    b[:preso_desde] ||= agora
    parado = agora - b[:preso_desde].to_f
    return false if parado < PRESO_SEG

    # ── degrau 2: nem a pe se sai daqui ──────────────────────────────────────
    #
    # Tres portas, e basta uma: parado o tempo todo, safanoes a mais sem sair
    # do sitio, ou o oscilador (a andar, sem nunca se afastar).
    if parado >= PRESO_LIMITE ||
       b[:safanoes].to_i >= SAFANOES_MAX ||
       (teimoso && b[:safanoes].to_i >= 2)
      alvo = casa_livre_perto(ev.x, ev.y, 4, 1)
      if alvo
        (ev.moveto(alvo[0], alvo[1]) rescue nil)
        (ev.instance_variable_set(:@move_timer, nil) rescue nil)
        registar("destravado a forca: #{ev.id} para (#{alvo[0]},#{alvo[1]})")
      end
      b[:preso_x] = nil
      b[:preso_desde] = agora
      b[:longe_x] = nil
      b[:longe_desde] = agora
      b[:safanoes] = 0
      b[:safanao_rumo] = nil
      b[:safanao_ate] = 0.0
      return true
    end

    # ── degrau 1: manter o rumo ja escolhido, enquanto ele passar ────────────
    #
    # ⚠️ Note-se o que NAO se faz aqui: mexer no `preso_desde`. O relogio do
    # degrau 2 corre por baixo do safanao, que e a unica razao por que o degrau
    # 2 alguma vez acontece.
    if b[:safanao_ate].to_f > agora && b[:safanao_rumo]
      ux, uy = b[:safanao_rumo]
      nx = rx + (ux * passo)
      ny = ry + (uy * passo)
      if casa_livre_para_evento?(ev, nx, ny)
        pousar_a_mao!(ev, nx, ny,
                      (ux.abs > uy.abs) ? ((ux > 0) ? 6 : 4) : ((uy > 0) ? 2 : 8))
        return true
      end
      # O rumo deixou de servir a meio: escolhe-se outro ja a seguir.
      b[:safanao_rumo] = nil
      b[:safanao_ate] = 0.0
    end

    # ── degrau 1: escolher rumo novo ─────────────────────────────────────────
    #
    # As diagonais entram porque o andar normal so usa os quatro eixos, e um
    # canto em L bloqueia os dois eixos uteis ao mesmo tempo. Sorteia-se a
    # ordem para dois bichos presos no mesmo sitio nao escolherem o mesmo lado
    # e continuarem a empurrar-se.
    rumos = [[1.0, 0.0], [-1.0, 0.0], [0.0, 1.0], [0.0, -1.0],
             [0.7, 0.7], [-0.7, 0.7], [0.7, -0.7], [-0.7, -0.7]].shuffle
    rumos.each do |(ux, uy)|
      nx = rx + (ux * passo)
      ny = ry + (uy * passo)
      next unless casa_livre_para_evento?(ev, nx, ny)
      pousar_a_mao!(ev, nx, ny,
                    (ux.abs > uy.abs) ? ((ux > 0) ? 6 : 4) : ((uy > 0) ? 2 : 8))
      b[:safanao_rumo] = [ux, uy]
      b[:safanao_ate] = agora + SAFANAO_DURA
      b[:safanoes] = b[:safanoes].to_i + 1
      return true
    end
    false
  rescue
    false
  end

  def pousar_a_mao!(ev, rx, ry, dir)
    ev.instance_variable_set(:@direction, dir)
    ev.instance_variable_set(:@real_x, rx)
    ev.instance_variable_set(:@real_y, ry)
    ev.instance_variable_set(:@x, (rx / Game_Map::REAL_RES_X.to_f).round)
    ev.instance_variable_set(:@y, (ry / Game_Map::REAL_RES_Y.to_f).round)
    (ev.calculate_bush_depth rescue nil)
    animar_evento!(ev)
  rescue
    nil
  end

  # A distancia a que este bicho QUER estar: se tem um golpe de longe pronto,
  # quatro casas; senao, colado, porque so a dentada e que alcanca.
  DISTANCIA_LONGE = 4.0

  # ⚠️ AVANÇAR SEM NADA NA MAO NAO E CORAGEM, E UM ERRO DE LEITURA.
  #
  # Um Pokemon que gastou os quatro golpes nao tem nada com que responder
  # durante a recarga. Continuar a andar para cima do inimigo nesse estado e
  # oferecer-se: ele leva o que vier e nao devolve nada.
  #
  # O que um bicho faz — e o que se ve em qualquer jogo de luta — e afastar-se
  # ate ter com que bater. Isso ja da textura ao combate sozinho: a luta ganha
  # um ritmo de aproximar e recuar em vez de ser dois bonecos colados a trocar
  # dano.
  #
  # A pergunta e a mesma para toda a gente, e por isso e uma funcao so. Um
  # golpe de armadilha nao conta: ele poe-se no chao e nao defende de nada.
  def algum_golpe_pronto?(pkmn, prontos)
    return true unless pkmn && prontos.is_a?(Array)
    agora = Time.now.to_f
    4.times do |i|
      mv = (pkmn.moves[i] rescue nil)
      next unless mv && mv.id
      next if prontos[i].to_f > agora
      next if (armadilha?(mv) rescue false)
      return true
    end
    false
  rescue
    true
  end

  # A que distancia se fica enquanto se espera pela recarga. Longe o suficiente
  # para nao levar de um golpe de contacto, perto o suficiente para voltar a
  # entrar assim que houver com que.
  DISTANCIA_MEDO = 5.0

  # Ate onde o ajudante se pode afastar de mim a recuar. Passado isto, volta
  # para mim mesmo com um bicho em cima.
  ALIADO_TRELA   = 7.0

  def distancia_desejada(b)
    # ⚠️ ISTO VEM ANTES DE TUDO O RESTO, INCLUINDO DO PAPEL DE AGRESSOR.
    #
    # Nao interessa se e a vez dele de atacar: sem golpe pronto nao ha vez
    # nenhuma. Se ficasse depois, o agressor continuava a encostar-se a nos com
    # as maos vazias, que e justamente o caso que mais se nota.
    return DISTANCIA_MEDO unless algum_golpe_pronto?(b[:pkmn], b[:prontos])
    # Quem nao esta na vez rodeia. Continua a andar e a fazer pressao — o que
    # nao faz e empilhar-se em cima de nos a espera de atacar.
    return anel_ia unless agressor?(b)
    agora = Time.now.to_f
    4.times do |i|
      mv = (b[:pkmn].moves[i] rescue nil)
      next unless mv && mv.id
      next if b[:prontos][i].to_f > agora
      next if armadilha?(mv)
      return DISTANCIA_LONGE if alcance_ia(mv) >= ALCANCE_LONGO
    end
    PARAGEM_IA
  rescue
    PARAGEM_IA
  end

  # Recuar e andar para tras sem virar as costas: continua a olhar para nos,
  # que e o que um bicho a manter distancia faz.
  def recuar_bicho!(b, dt, dx, dy, rx, ry)
    ev = b[:ev]
    n = Math.sqrt((dx * dx) + (dy * dy))
    return if n < 0.001
    ux = -(dx / n)
    uy = -(dy / n)
    vel = [velocidade_livre(b[:pkmn]), 1.0].max * factor_de_caca * 0.75
    passo = vel * Game_Map::REAL_RES_X * dt
    nx = rx + (ux * passo)
    rx = nx if casa_livre_para_evento?(ev, nx, ry)
    ny = ry + (uy * passo)
    ry = ny if casa_livre_para_evento?(ev, rx, ny)
    ev.instance_variable_set(:@real_x, rx)
    ev.instance_variable_set(:@real_y, ry)
    ev.instance_variable_set(:@x, (rx / Game_Map::REAL_RES_X.to_f).round)
    ev.instance_variable_set(:@y, (ry / Game_Map::REAL_RES_Y.to_f).round)
    (ev.calculate_bush_depth rescue nil)
    animar_evento!(ev)
  rescue
    nil
  end

  # ⚠️ O `passable?` DO MAPA NAO SABE DE QUEM ESTA LA.
  #
  # Ele responde sobre o CHAO — se aquela casa e relva ou parede. Quem impede
  # dois personagens de se sobreporem, no motor, e o `can_move_from_coordinate?`
  # do proprio movimento por casas... que nos deixamos de usar quando passamos a
  # escrever a posicao a mao. Resultado: os selvagens empilhavam-se todos na
  # mesma casa, e quatro deles pareciam um.
  #
  # A lista de quem esta onde e nossa e e curta (quatro bichos, um ajudante, o
  # jogador): percorre-la e mais barato do que qualquer coisa que o motor faca.
  # ⚠️ UM CORPO PRESO A GRADE E MAIOR DO QUE O BONECO QUE SE VE.
  #
  # O `casa_ocupada?` compara CASAS: `ev.x == tx`. Como o `.x` de um evento e a
  # posicao real arredondada, cada um ocupa uma casa inteira, encaixada na
  # grade — e a nossa posicao tambem arredonda. Resultado: para passar entre
  # dois Pokemon e preciso que o meu centro caia dentro da casa vazia, e nao ha
  # meio-caminho. O sprite tem 24 px de largura e o corpo tem 32, alinhado.
  #
  # Aqui o corpo passa a ser um circulo, medido nas posicoes REAIS. Dois corpos
  # tocam-se a 0,72 casas, portanto entre dois vizinhos a uma casa sobram 9 px
  # de passagem: estreito o suficiente para nao se atravessar por acidente, e
  # largo o suficiente para se passar de proposito.
  #
  # Isto vale so para o corpo a corpo. Paredes e agua continuam por casa, que e
  # como o mapa e desenhado.
  CORPO_RAIO = 0.36    # casas: o valor de recurso, quando nao ha sprite

  # ⚠️ O CORPO TEM O TAMANHO DO BONECO, E NAO O DA CASA.
  #
  # Um raio fixo trata um Caterpie e um Onix como a mesma coisa. Quem joga ve o
  # desenho, e o desenho e que tem de bater com o que empurra: um bicho pequeno
  # com um corpo de 32 px le-se como "ha uma parede invisivel a volta dele".
  #
  # O charset tem quatro colunas (os quatro passos), portanto um quadro tem um
  # quarto da largura da folha. Metade disso e o raio, com uma folga de 15% —
  # os bonecos tem ar transparente nas bordas, e sem a folga tocavam-se antes
  # de os desenhos se tocarem.
  FOLGA_CORPO = 0.85
  RAIO_MINIMO = 0.20   # casas: nem o mais pequeno passa atraves de outro
  RAIO_MAXIMO = 0.55   # casas: nem o maior fecha um corredor sozinho

  def raio_do_corpo(quem)
    return CORPO_RAIO unless quem
    nome = (quem.character_name.to_s rescue "")
    return CORPO_RAIO if nome.empty?
    @raios ||= {}
    r = @raios[nome]
    return r if r
    bmp = (RPG::Cache.character(nome, (quem.character_hue rescue 0)) rescue nil)
    largura = (bmp && bmp.width > 0) ? (bmp.width / 4.0) : (Game_Map::TILE_WIDTH.to_f)
    r = ((largura * 0.5 * FOLGA_CORPO) / Game_Map::TILE_WIDTH.to_f)
    r = RAIO_MINIMO if r < RAIO_MINIMO
    r = RAIO_MAXIMO if r > RAIO_MAXIMO
    @raios[nome] = r
  rescue
    CORPO_RAIO
  end

  # ⚠️ UMA COLISAO SEM SAIDA E UMA ARMADILHA, NAO UMA COLISAO.
  #
  # O teste era "a posicao NOVA toca em alguem?". Parece certo e tem um buraco
  # enorme: se o boneco JA esta dentro de outro, todas as posicoes a volta dele
  # tocam em alguem — e a resposta e "nao" para todos os lados. Ele fica preso
  # para sempre, e nem sequer a fugir consegue sair.
  #
  # Foi exactamente o que se viu: o selvagem entrou no ajudante e os dois
  # ficaram agarrados, sem se separarem e sem seguirem ninguem.
  #
  # A regra certa nao e "nao toques" — e "nao te aproximes mais". Estando ja
  # sobreposto, aceita-se qualquer passo que AUMENTE a distancia. E o que
  # transforma um encravamento permanente num encontrao que se desfaz sozinho.
  def corpo_livre?(quem, rx, ry)
    meu_raio = raio_do_corpo(quem)
    ex = (quem.instance_variable_get(:@real_x) rescue nil)
    ey = (quem.instance_variable_get(:@real_y) rescue nil)
    perto = lambda do |outro|
      next false unless outro
      next false if outro.equal?(quem)
      ox = (outro.instance_variable_get(:@real_x) rescue nil)
      oy = (outro.instance_variable_get(:@real_y) rescue nil)
      next false unless ox && oy
      dx = (rx - ox).to_f
      dy = (ry - oy).to_f
      # A soma dos dois raios: e a distancia a que os dois DESENHOS se tocam.
      lim = (meu_raio + raio_do_corpo(outro)) * Game_Map::REAL_RES_X
      novo = (dx * dx) + (dy * dy)
      next false if novo >= (lim * lim)
      # Ja estava dentro dele? Entao so se recusa o passo que APERTA mais.
      if ex && ey
        agora = ((ex - ox)**2) + ((ey - oy)**2)
        next false if agora < (lim * lim) && novo > agora
      end
      true
    end
    # ⚠️ O AJUDANTE NAO TEM CORPO, E ISSO E UMA DECISAO E NAO UM ESQUECIMENTO.
    #
    # Ele anda colado a nos de propria vontade — e o trabalho dele. Com corpo,
    # esse mesmo comportamento vira uma parede que nos segue: fecha corredores,
    # empurra-nos para os inimigos e faz perder golpes por nao se poder recuar.
    # O mesmo vale para a sombra do ajudante do outro jogador.
    #
    # O que se perde e pouco: dois bonecos nossos podem sobrepor-se um instante
    # ao cruzarem-se. O que se ganha e poder andar.
    #
    # Os INIMIGOS continuam com corpo. E neles que a colisao faz jogo — sao
    # eles que se quer contornar, e e entre eles que se quer passar.
    return false if perto.call($game_player)
    bichos.each { |b| return false if perto.call(b[:ev]) }
    # ⚠️ A DECISAO DE CIMA ESTA CERTA, MAS ERA SO METADE DELA.
    #
    # "O ajudante nao tem corpo" foi escrito a pensar em QUEM ANDA CONTRA ELE
    # sendo o jogador — e ai continua certo: com corpo, ele vira uma parede que
    # nos segue.
    #
    # So que a regra ficou a valer para toda a gente, e um SELVAGEM tambem
    # passava a atravessa-lo. E a assimetria que encrava: o selvagem entra no
    # ajudante sem resistencia, e o ajudante — que ve o corpo dos selvagens —
    # fica preso dentro dele, sem poder sair para lado nenhum.
    #
    # Portanto o ajudante tem corpo para os inimigos e nao tem para nos. E o
    # que o torna um combatente sem o tornar um obstaculo.
    if quem && !quem.equal?($game_player) && aliado_vivo? &&
       !quem.equal?(@aliado[:ev])
      return false if perto.call(@aliado[:ev])
    end
    true
  rescue
    true
  end

  def casa_ocupada?(quem, tx, ty)
    return true if fora_do_campo?(tx, ty)
    if $game_player && !$game_player.equal?(quem)
      return true if $game_player.x == tx && $game_player.y == ty
    end
    if @aliado && @aliado[:ev] && !@aliado[:ev].equal?(quem)
      return true if @aliado[:ev].x == tx && @aliado[:ev].y == ty
    end
    bichos.each do |b|
      ev = b[:ev]
      next unless ev
      next if ev.equal?(quem)
      return true if ev.x == tx && ev.y == ty
    end
    false
  rescue
    false
  end

  # ⚠️ A DIRECCAO ZERO DESLIGA A COLISAO TODA. E EU PASSAVA ZERO.
  #
  # O `Game_Map#passable?` calcula o bit de passagem assim:
  #
  #     bit = (1 << ((d / 2) - 1)) & 0x0f
  #
  # e depois pergunta `passage & bit != 0`. Com uma direccao a serio isso da
  # 1, 2, 4 ou 8. Com `d = 0` da `1 << -1`, que em Ruby e ZERO — e um `& 0`
  # nunca e diferente de zero. A pergunta passa a ser sempre "sim, podes".
  #
  # Era por isso que os Pokemon atravessavam agua e paredes: a colisao estava
  # a ser chamada, respondia, e a resposta nao queria dizer nada.
  #
  # A arena anda em duas dimensoes ao mesmo tempo, portanto a direccao sai do
  # passo que se esta a dar — o eixo que mais andou manda.
  def rumo_do_passo(ev, tx, ty)
    dx = tx - ev.x
    dy = ty - ev.y
    return 2 if dx.zero? && dy.zero?
    if dx.abs > dy.abs
      (dx > 0) ? 6 : 4
    else
      (dy > 0) ? 2 : 8
    end
  end

  # ⚠️ AGUA E DESNIVEIS NAO SE VEEM NA TABELA DE PASSAGEM.
  #
  # A agua e atravessavel para quem surfa, e o motor deixa isso ao `Game_Player`
  # decidir. Um desnivel (Ledge) e passavel de cima para baixo e mais nada — e
  # essa regra tambem so existe no jogador.
  #
  # Um Pokemon da arena nao e o jogador: nao surfa e nao salta desniveis. Para
  # ele os dois sao parede. Le-se pela etiqueta do terreno, que e onde o mapa
  # guarda essa informacao.
  TERRENO_PAREDE = [:Water, :StillWater, :DeepWater, :Waterfall,
                    :WaterfallCrest, :Ledge].freeze

  # ⚠️ NEM TUDO O QUE E PAREDE E AGUA, E A DIFERENCA IMPORTA.
  #
  # O `TERRENO_PAREDE` junta agua e desniveis porque, para um selvagem de terra,
  # os dois sao parede. Mas a agua tem uma propriedade que um desnivel nao tem:
  # ela VIRA chao para quem surfa, e para quem nasceu nela. Um desnivel nunca
  # vira nada.
  TERRENO_AGUA = [:Water, :StillWater, :DeepWater, :Waterfall,
                  :WaterfallCrest].freeze

  def agua?(x, y)
    tag = ($game_map.terrain_tag(x, y) rescue nil)
    return false unless tag
    id = (tag.respond_to?(:id) ? tag.id : tag)
    TERRENO_AGUA.include?(id)
  rescue
    false
  end

  def terreno_proibido?(x, y)
    tag = ($game_map.terrain_tag(x, y) rescue nil)
    return false unless tag
    id = (tag.respond_to?(:id) ? tag.id : tag)
    TERRENO_PAREDE.include?(id)
  rescue
    false
  end

  #-----------------------------------------------------------------------------
  # A FOLGA DAS QUINAS
  #
  # ⚠️ O TESTE PERGUNTA POR UMA CASA; O BONECO OCUPA UM PEDACO DE MAPA.
  #
  # O `casa_livre_para_evento?` faz `(rx / 128.0).round` — ou seja, decide pela
  # casa onde esta o CENTRO do boneco. Com o arredondamento, um bicho pode ter
  # 49% do corpo dentro da casa seguinte e o teste continuar a dizer que ele
  # esta na sua. So quando o centro passa a fronteira e que a parede aparece.
  #
  # Visto de fora: ele encosta-se a quina, meio corpo ja dentro dela, e fica ali
  # a raspar. Nao e a IA a insistir — e o teste a so reparar na parede quando
  # ele ja la esta meio metido.
  #
  # A folga resolve-o com uma pergunta a mais: alem da casa do centro, olha-se
  # para a casa onde a BORDA da frente vai cair. Se essa estiver fechada, o
  # passo nao vale. Ele passa a virar um pouco antes, e a quina deixa de o
  # apanhar.
  #
  # ⚠️ E o valor tem de ficar abaixo de meia casa.
  #
  # A 0,5 a borda cairia sempre na casa seguinte e nada passava por corredores
  # de uma casa — as portas da masmorra fechavam-se todas. A 0,30 sobra folga
  # suficiente num corredor e chega para nao raspar numa quina.
  FOLGA_QUINA = 0.30

  # ⚠️ Isto corre a cada passo de cada bicho, varias vezes por frame. Nao se
  # chama o teste completo outra vez (ele confere corpos, agua, campo): so a
  # pergunta do mapa, que e a que decide uma quina.
  def quina_livre?(ev, rx, ry)
    orx = (ev.instance_variable_get(:@real_x) rescue rx).to_f
    ory = (ev.instance_variable_get(:@real_y) rescue ry).to_f
    dx = rx - orx
    dy = ry - ory
    n = Math.sqrt((dx * dx) + (dy * dy))
    return true if n < 0.001
    passo_x = (dx / n) * FOLGA_QUINA * Game_Map::REAL_RES_X
    passo_y = (dy / n) * FOLGA_QUINA * Game_Map::REAL_RES_Y
    tx = ((rx + passo_x) / Game_Map::REAL_RES_X.to_f).round
    ty = ((ry + passo_y) / Game_Map::REAL_RES_Y.to_f).round
    return true if tx == ev.x && ty == ev.y
    return true unless ($game_map.valid?(tx, ty) rescue false)
    # A agua segue a mesma excepcao do teste principal: quem vive nela nao ve
    # parede nenhuma na agua, e a borda dele tambem nao.
    return true if agua?(ev.x, ev.y) && agua?(tx, ty)
    return false if terreno_proibido?(tx, ty) && !agua?(ev.x, ev.y)
    d = rumo_do_passo(ev, tx, ty)
    ($game_map.passable?(tx, ty, 10 - d, ev) rescue true)
  rescue
    true
  end

  def casa_livre_para_evento?(ev, rx, ry)
    tx = (rx / Game_Map::REAL_RES_X.to_f).round
    ty = (ry / Game_Map::REAL_RES_Y.to_f).round
    return true if tx == ev.x && ty == ev.y
    return false unless ($game_map.valid?(tx, ty) rescue false)
    # ⚠️ E UM MAGIKARP NAO ANDA EM TERRA, MAS TAMBEM NAO E PAREDE PARA ELE.
    #
    # Com o jogador a surfar, os selvagens que o VOE poe a volta sao encontros de
    # AGUA — nascem na agua. Se a agua for parede para eles, ficam presos no
    # sitio onde nasceram e a luta no mar e uma luta contra estatuas.
    #
    # A regra que se aplica sozinha, sem lista nem bandeira: quem ja esta em cima
    # de agua pode andar em agua. Nao e preciso saber de que tipo ele e nem como
    # nasceu — o sitio onde esta diz tudo. E um que nasceu em terra continua a
    # ter a agua como parede, que e a regra de sempre.
    # ⚠️ E A MESMA ARMADILHA, PELA SEGUNDA VEZ NO MESMO METODO.
    #
    # Eu tinha dado a agua aos bichos que nascem nela — mas so na etiqueta. As
    # duas linhas do `passable?` logo a seguir voltavam a fecha-la, porque o
    # tileset diz que agua nao se atravessa. Um Magikarp continuava estatua, com
    # a regra "quem esta na agua anda na agua" escrita mesmo por cima dele.
    #
    # Quem vive na agua salta as duas perguntas quando o destino tambem e agua.
    # Em terra nada muda: as perguntas continuam a valer inteiras.
    aquatico = agua?(ev.x, ev.y)
    return false if terreno_proibido?(tx, ty) && !aquatico
    unless aquatico && agua?(tx, ty)
      # A mesma correccao do `casa_livre_para?`: pergunta-se sobre a casa de onde
      # se sai. Aqui e o `Game_Map#passable?`, que confere so a casa que recebe —
      # por isso conferem-se as duas, a de saida na direccao do passo e a de
      # chegada no sentido contrario, que e o que o motor faz.
      d = rumo_do_passo(ev, tx, ty)
      return false unless ($game_map.passable?(ev.x, ev.y, d, ev) rescue true)
      return false unless ($game_map.passable?(tx, ty, 10 - d, ev) rescue true)
    end
    return false if fora_do_campo?(tx, ty)
    return false unless quina_livre?(ev, rx, ry)
    corpo_livre?(ev, rx, ry)
  rescue
    false
  end

  # ⚠️ UM RELOGIO PARA TODOS OS BONECOS E UM BONECO A ANDAR E OS OUTROS A DESLIZAR.
  #
  # Isto guardava o instante do ultimo passo num `@passo_ia` do MODULO — um so,
  # partilhado por todos. Quem chegasse primeiro a cada 0,13 s avancava o quadro
  # e zerava o relogio; todos os outros encontravam-no acabado de zerar e
  # ficavam com as pernas paradas. Com um selvagem em campo era o treinador que
  # deslizava; com quatro, quase toda a gente.
  #
  # O relogio passa a viver em CADA evento. Sao independentes porque as pernas
  # deles sao independentes.
  def animar_evento!(ev)
    return unless ev
    agora = Time.now.to_f
    ultimo = ((ev.instance_variable_get(:@anil_passo) rescue nil) || 0.0).to_f
    return if (agora - ultimo) < PASSO_ANIM
    (ev.instance_variable_set(:@anil_passo, agora) rescue nil)
    pat = (((ev.pattern rescue 0).to_i + 1) % 4)
    (ev.instance_variable_set(:@pattern, pat) rescue nil)
  rescue
    nil
  end

  # ⚠️ UM SALTO PARA TRAS, E O MOTOR JA SABE FAZE-LO.
  #
  # O `Game_Character#jump` do RMXP salta um numero de casas e — o que importa
  # aqui — CONFERE se a casa de destino e pisavel: se houver uma parede atras,
  # o golpe simplesmente nao empurra, em vez de enfiar o boneco na pedra.
  #
  # A direccao sai da posicao relativa dos dois, e nao da direccao em que o
  # atacante olha: quem apanha um golpe de lado tem de ser atirado para o lado,
  # nao para tras das costas de quem bateu.
  #
  # Nao se empurra quem ja esta a saltar, senao os golpes em cadeia acumulavam
  # saltos e o boneco atravessava o mapa.
  # ⚠️ QUANTAS CASAS E QUE ELE PODE MESMO RECUAR.
  #
  # Anda-se uma a uma e para-se na ultima livre. Uma so pergunta serve para
  # todos, porque a `casa_de_pedra?` e a mesma que governa o movimento da arena
  # — se ela diz que da para andar, da para ser empurrado; se diz que nao, o
  # empurrao tambem nao pode.
  #
  # Devolve 0 quando nao ha para onde ir, e aí nao se empurra de todo.
  def empurrao_possivel(quem, sx, sy)
    return 0 unless quem
    passos = [sx.abs, sy.abs].max
    return 0 if passos <= 0
    ux = (sx <=> 0)
    uy = (sy <=> 0)
    bons = 0
    (1..passos).each do |i|
      nx = quem.x + (ux * i)
      ny = quem.y + (uy * i)
      break unless ($game_map.valid?(nx, ny) rescue false)
      break if casa_de_pedra?(nx, ny)
      bons = i
    end
    bons
  rescue
    0
  end

  def empurrar!(quem, atacante, casas = 1)
    return unless quem && atacante
    # O gesto de encaixar o golpe vem antes de qualquer coisa: mesmo quem nao
    # pode ser empurrado (a saltar, encostado a uma arvore) inclina-se.
    inclinar!(quem, atacante)
    return if (quem.jumping? rescue true)
    dx = quem.x - atacante.x
    dy = quem.y - atacante.y
    if dx.abs >= dy.abs
      sx = (dx >= 0) ? casas : -casas
      sy = 0
    else
      sx = 0
      sy = (dy >= 0) ? casas : -casas
    end
    # Se estiverem exactamente em cima um do outro, empurra-se para longe de
    # quem bate, usando a direccao dele.
    if sx == 0 && sy == 0
      case (atacante.direction rescue 2)
      when 2 then sy = casas
      when 8 then sy = -casas
      when 4 then sx = -casas
      else        sx = casas
      end
    end
    # ⚠️ O SALTO VIRA O BONECO, E NAO E ISSO QUE SE QUER.
    #
    # O `jump` do motor aponta o personagem na direccao do salto: levar um golpe
    # nas costas fazia o Pokemon rodar para tras e depois voltar, como se
    # estivesse a olhar em volta. Quem leva um empurrao continua a olhar para
    # onde estava — e o recuo le-se melhor assim, porque se ve o boneco a ser
    # atirado de costas.
    # ⚠️ O `jump` DO MOTOR CONFERE A PASSAGEM — E NAO CHEGA.
    #
    # Ele tem um `passable?` la dentro e recusa o salto se a casa estiver
    # ocupada. So que a primeira linha do `passable?` e esta:
    #
    #     return true if @through
    #
    # E quase toda a gente nesta arena anda em `through`: o ajudante (para nao
    # tropecar em nos), o corpo do treinador, o clone. Para esses, "confere a
    # passagem" quer dizer "diz sempre que sim" — e o empurrao atira-os para
    # dentro de uma arvore, de onde so saem a custo porque o movimento livre da
    # arena tem a sua propria colisao e essa ja os prende.
    #
    # E o motor tambem nao sabe do `terreno_proibido?` da arena, que e o que
    # distingue agua de chao quando se surfa.
    #
    # Portanto a pergunta tem de ser feita com a regua da ARENA (a mesma do
    # `mover_bicho!` e do voo dos golpes), e casa a casa: o empurrao para na
    # ultima casa livre em vez de saltar por cima de tudo ate ao fim.
    passos = empurrao_possivel(quem, sx, sy)
    if passos.zero?
      # Encostado a alguma coisa: fica o gesto de encaixar o golpe, que ja foi
      # dado la em cima, e mais nada. Melhor um bicho que nao recua do que um
      # bicho dentro de um tronco.
      piscar_vermelho!(quem)
      return
    end
    sx = (sx <=> 0) * passos
    sy = (sy <=> 0) * passos
    olhava = (quem.direction rescue 2)
    (quem.jump(sx, sy) rescue nil)
    (quem.instance_variable_set(:@direction, olhava) rescue nil)
    piscar_vermelho!(quem)
  rescue
    nil
  end

  # ⚠️ O VERMELHO E NO SPRITE, NAO NO BITMAP.
  #
  # Pintar o bitmap estragava a imagem partilhada da cache e o Pokemon ficava
  # vermelho em todo o lado (ja aconteceu neste projecto com o hue). O `color`
  # do sprite e uma camada por cima, so daquele sprite, e desaparece sozinho
  # quando se repoe.
  FLASH_FRAMES = 18

  def piscar_vermelho!(quem)
    piscar_cor!(quem, 255, 40, 40, FLASH_FRAMES)
  end

  # O mesmo mecanismo, com a cor a escolha: o vermelho e dano, o branco e um
  # golpe a sair.

  #-----------------------------------------------------------------------------
  # O CORPO FALA: O BOTE, O TOMBO E O ESCUDO
  #
  # ⚠️ ESTES TRES EFEITOS SAO DO SPRITE, E NAO DO PERSONAGEM.
  #
  # A tentacao era mexer no `real_x`/`real_y` para o Pokemon dar a cabecada a
  # serio. Nao se pode: essa posicao e a MESMA que o movimento livre escreve a
  # cada frame e que a colisao le. Um bote escrito ali seria uma luta entre duas
  # mãos pela mesma variavel — e, pior, um Pokemon a atravessar paredes durante
  # dois decimos de segundo.
  #
  # O que se mexe e o SPRITE. O `Sprite_Character#update` reescreve `x`, `y` e
  # `zoom` a partir do personagem em cada frame; como o tick da arena corre
  # DEPOIS disso, basta somar o desvio por cima e ele dura exactamente um frame.
  # No frame seguinte volta a somar-se, com o valor novo. Nada fica sujo, nada
  # precisa de ser limpo, e a colisao nunca soube de nada.
  #-----------------------------------------------------------------------------
  BOTE_CASAS  = 1.0     # a cabecada avanca uma casa, e volta
  BOTE_IDA    = 0.09    # segundos a ir
  BOTE_VOLTA  = 0.15    # segundos a voltar — a volta e mais lenta que o golpe
  TOMBO_TEMPO = 0.26    # segundos a endireitar-se depois de apanhar
  TOMBO_GRAUS = 18.0    # quanto se inclina para tras

  def efeitos_do_corpo; (@efeitos_corpo ||= {}); end

  def ficha_do_corpo(quem)
    efeitos_do_corpo[quem] ||= {}
  end

  # ⚠️ A CABECADA E DE QUEM TEM CONTACTO, E SO DESSES.
  #
  # O Tackle, o Scratch, a Mordida — os golpes com a bandeira `contact` no PBS —
  # sao os que o Pokemon da com o corpo. Um Shadow Ball nao se atira com a
  # cabeca, e por isso nao leva bote nenhum: a leitura do combate vem justamente
  # de se ver a diferenca entre quem avanca e quem lanca.
  # ⚠️ ATACAR SEM SE VIRAR PARA O ALVO LE-SE COMO UM BUG, MESMO QUANDO ACERTA.
  #
  # O golpe ja mira sozinho (a mira agarra o inimigo mais proximo), portanto
  # acertava de costas — e o que se via era um Pokemon a olhar para um lado e a
  # ferir alguem que estava do outro. Vira-lo custa uma linha e resolve a
  # leitura toda: quem esta a levar passa a ser obvio, e o feixe passa a sair de
  # onde o boneco esta a olhar.
  #
  # O bote e a outra metade: um passo curto na direccao do golpe, que e o que
  # da peso ao gesto. Ja existia para os golpes de contacto; passa a ser de
  # todos.
  #
  # ⚠️ ISTO E DESFAZIVEL DE PROPOSITO. Foi pedido assim.
  #
  #   BOTE_AO_ATACAR = false   -> ninguem se vira nem avanca; volta ao de antes
  #   VIRAR_AO_ATACAR = false  -> mantem o bote e deixa de virar
  #
  # Sao duas porque sao duas ideias: uma e sobre para onde se olha, a outra
  # sobre o corpo se mexer. Pode-se querer uma sem a outra.
  BOTE_AO_ATACAR  = true
  VIRAR_AO_ATACAR = true

  def encarar!(alvo)
    return unless VIRAR_AO_ATACAR && alvo && $game_player
    dx = (alvo.x - $game_player.x)
    dy = (alvo.y - $game_player.y)
    return if dx.zero? && dy.zero?
    d = (dx.abs > dy.abs) ? ((dx > 0) ? 6 : 4) : ((dy > 0) ? 2 : 8)
    return if (($game_player.direction rescue 0) == d)
    ($game_player.instance_variable_set(:@direction, d)) rescue nil
  rescue
    nil
  end

  # Vira-se e da-se o passo, na ordem certa: o bote sai na direccao NOVA.
  def encarar_e_botar!(alvo)
    return unless BOTE_AO_ATACAR || VIRAR_AO_ATACAR
    alvo ||= evento_inimigo
    return unless alvo
    encarar!(alvo)
    # Um golpe de contacto ja da a cabecada inteira pelo seu proprio caminho;
    # aqui e so o gesto de lancar.
    dar_bote!($game_player, alvo.x, alvo.y, BOTE_MINI) if BOTE_AO_ATACAR
  rescue
    nil
  end

  # ⚠️ UMA CABECADA E UM GESTO DE ATACAR NAO TEM O MESMO TAMANHO.
  #
  # O bote foi feito para os golpes de contacto: uma casa inteira, que e o que
  # se ve numa cabecada. Usar o mesmo para TODOS os golpes daria um Pokemon a
  # atirar-se ao inimigo de cada vez que baforasse fogo de longe.
  #
  # O tamanho passa a viajar com o bote. Quem nao diz nada fica com a cabecada
  # de sempre.
  BOTE_MINI = 0.32      # casas: o gesto de lancar, so o peso do movimento

  def dar_bote!(quem, ax, ay, casas = nil)
    return unless quem
    ficha = ficha_do_corpo(quem)
    dx = ax.to_f - quem.x
    dy = ay.to_f - quem.y
    n = Math.sqrt((dx * dx) + (dy * dy))
    if n < 0.001
      # Sem alvo util, usa-se para onde ele esta virado.
      case (quem.direction rescue 2)
      when 2 then dx, dy = 0.0,  1.0
      when 8 then dx, dy = 0.0, -1.0
      when 4 then dx, dy = -1.0, 0.0
      else        dx, dy = 1.0,  0.0
      end
      n = 1.0
    end
    ficha[:bote] = { :ux => dx / n, :uy => dy / n, :t => 0.0,
                     :casas => (casas || BOTE_CASAS).to_f }
  rescue
    nil
  end

  # ⚠️ QUEM APANHA, INCLINA-SE. QUALQUER GOLPE, QUALQUER UM DOS TRES LADOS.
  #
  # Isto entra no `empurrar!` porque o `empurrar!` ja e o sitio por onde passa
  # TODA a pancada que acerta — a minha no selvagem, a dele em mim, a de
  # qualquer um no ajudante. Um so ponto, e os tres lados ganham o gesto.
  def inclinar!(quem, atacante)
    return unless quem
    ficha = ficha_do_corpo(quem)
    lado = 1.0
    if atacante
      dx = quem.x - atacante.x
      # Inclina-se para longe de quem bateu: quem apanha pela esquerda cai para
      # a direita. Com o atacante em cima, escolhe-se um lado qualquer.
      lado = (dx >= 0) ? 1.0 : -1.0
    end
    ficha[:tombo] = { :t => 0.0, :lado => lado }
  rescue
    nil
  end

  # Corre no tick, depois do motor ter desenhado. Aplica o que houver e limpa o
  # que acabou.
  def correr_efeitos_do_corpo!
    return if efeitos_do_corpo.empty?
    dt = [(@delta || (1.0 / 60.0)), 0.1].min
    mortos = []
    efeitos_do_corpo.each do |quem, ficha|
      sp = sprite_de(quem)
      unless sp && !(sp.disposed? rescue true)
        mortos << quem
        next
      end

      if (bote = ficha[:bote])
        bote[:t] += dt
        total = BOTE_IDA + BOTE_VOLTA
        if bote[:t] >= total
          ficha.delete(:bote)
        else
          # Vai depressa e volta devagar: e o que faz parecer um impacto e nao
          # um passinho para a frente e para tras.
          fraccao = if bote[:t] <= BOTE_IDA
                      bote[:t] / BOTE_IDA
                    else
                      1.0 - ((bote[:t] - BOTE_IDA) / BOTE_VOLTA)
                    end
          avanco = (bote[:casas] || BOTE_CASAS) * fraccao * Game_Map::TILE_WIDTH
          sp.x += (bote[:ux] * avanco).round
          sp.y += (bote[:uy] * avanco).round
        end
      end

      if (tombo = ficha[:tombo])
        tombo[:t] += dt
        if tombo[:t] >= TOMBO_TEMPO
          ficha.delete(:tombo)
          (sp.angle = 0) rescue nil
        else
          # Bate de uma vez e endireita-se aos poucos.
          resta = 1.0 - (tombo[:t] / TOMBO_TEMPO)
          # O sprite roda em volta dos PES (o `oy` e a base), portanto isto le-se
          # como um tronco a ir para tras, e nao como um boneco a girar.
          (sp.angle = TOMBO_GRAUS * resta * tombo[:lado]) rescue nil
        end
      end

      mortos << quem if ficha.empty?
    end
    mortos.each do |quem|
      sp = sprite_de(quem)
      (sp.angle = 0) rescue nil if sp && !(sp.disposed? rescue true)
      efeitos_do_corpo.delete(quem)
    end
  rescue
    nil
  end

  def limpar_efeitos_do_corpo!
    efeitos_do_corpo.each_key do |quem|
      sp = sprite_de(quem)
      (sp.angle = 0) rescue nil if sp && !(sp.disposed? rescue true)
    end
    @efeitos_corpo = {}
  rescue
    @efeitos_corpo = {}
  end

  #-----------------------------------------------------------------------------
  # O CAMPO DE FORCA DO PROTECT
  #
  # ⚠️ O TAMANHO NAO PODE SER UM NUMERO FIXO.
  #
  # Uma bolha de 48 px fica ridicula num Wailord e engole um Joltik. Ela e
  # medida a partir do sprite que esta no ecra — `src_rect` vezes o `zoom` — e
  # por isso um Pokemon grande ganha um escudo grande, sem eu ter de saber nada
  # sobre especies.
  #
  # A bolha e desenhada a mao em vez de vir de uma folha de animacao: assim o
  # diametro e exactamente o que eu quero, e nao o que a folha tinha.
  #-----------------------------------------------------------------------------
  ESCUDO_FOLGA    = 1.30   # quanto a bolha e maior do que o boneco
  ESCUDO_MIN      = 44
  ESCUDO_MAX      = 220
  # ⚠️ 105 DE OPACIDADE NUM SPRITE ADITIVO SOBRE UMA CAVERNA E QUASE NADA.
  #
  # O modo aditivo soma a cor ao que esta por baixo: sobre relva clara le-se,
  # sobre a pedra escura do Monte Moon quase desaparece — e foi ai que se
  # reparou. Uma defesa que nao se ve nao e uma defesa: nao da para saber se
  # levantou a tempo, e passa a ser fe.
  #
  # Sobe para 180, e o pulso com ela. E, mais importante do que os numeros: o
  # golpe toca a animacao DELE quando abre (ver o `abrir_escudo!`), que e o que
  # o jogador conhece de uma batalha normal.
  ESCUDO_OPAC     = 180    # o corpo da bolha
  ESCUDO_PULSO    = 55     # quanto ela respira
  ESCUDO_VELOC    = 6.5    # rapidez do pulso

  def bitmap_do_escudo(diametro)
    @bitmaps_escudo ||= {}
    return @bitmaps_escudo[diametro] if @bitmaps_escudo[diametro]
    d = diametro
    r = d / 2.0
    bmp = Bitmap.new(d, d)
    d.times do |y|
      dy = (y + 0.5) - r
      dentro = (r * r) - (dy * dy)
      next if dentro <= 0
      meia = Math.sqrt(dentro)
      x0 = (r - meia).round
      larg = (meia * 2).round
      next if larg <= 0
      # O interior e um azul muito ténue; o rebordo e mais forte, que e o que
      # da a leitura de "campo de forca" e nao de "mancha".
      bmp.fill_rect(x0, y, larg, 1, Color.new(120, 200, 255, 60))
      raio_interno = r * 0.86
      d_int = (raio_interno * raio_interno) - (dy * dy)
      if d_int > 0
        meia_int = Math.sqrt(d_int)
        esp = (meia - meia_int).round
        if esp > 0
          bmp.fill_rect(x0, y, esp, 1, Color.new(190, 235, 255, 210))
          bmp.fill_rect((r + meia_int).round, y, esp, 1, Color.new(190, 235, 255, 210))
        end
      else
        # Nas calotes de cima e de baixo a fatia inteira e rebordo.
        bmp.fill_rect(x0, y, larg, 1, Color.new(190, 235, 255, 210))
      end
    end
    @bitmaps_escudo[diametro] = bmp
    bmp
  rescue
    nil
  end

  def diametro_do_escudo(quem)
    sp = sprite_de(quem)
    return ESCUDO_MIN unless sp && !(sp.disposed? rescue true)
    larg = ((sp.src_rect.width rescue 32) * (sp.zoom_x rescue 1.0)).abs
    alt  = ((sp.src_rect.height rescue 32) * (sp.zoom_y rescue 1.0)).abs
    d = ([larg, alt].max * ESCUDO_FOLGA).round
    [[d, ESCUDO_MIN].max, ESCUDO_MAX].min
  rescue
    ESCUDO_MIN
  end

  #-----------------------------------------------------------------------------
  # OS ESCUDOS DOS OUTROS
  #
  # ⚠️ GUARDA-SE UM PRAZO E NAO UM ESTADO.
  #
  # Se fosse "ligado/desligado", um aviso perdido no momento de largar a tecla
  # deixava a bolha acesa para sempre no ecra dos outros. Com um prazo curto,
  # renovado a cada aviso, ela apaga-se sozinha quando os avisos param — que e
  # o que acontece quando o dono a larga, e tambem quando ele se desliga.
  #-----------------------------------------------------------------------------
  ESCUDO_ALHEIO_DURA = 0.45   # segundos: pouco mais do que dois avisos

  def anotar_escudo_alheio!(pacote)
    id = pacote["sender_id"].to_s
    return if id.empty?
    @escudos_alheios ||= {}
    if pacote["esc"] || pacote["esp"]
      @escudos_alheios[id] = [Time.now.to_f + ESCUDO_ALHEIO_DURA,
                              pacote["esp"] ? :espelho : :escudo]
    else
      @escudos_alheios.delete(id)
    end
  rescue
    nil
  end

  def desenhar_escudos_alheios!
    @escudos_alheios ||= {}
    @sp_escudos ||= {}
    agora = Time.now.to_f
    @escudos_alheios.keys.each { |k| @escudos_alheios.delete(k) if @escudos_alheios[k][0] < agora }
    # Apagar os que ja nao ha
    (@sp_escudos.keys - @escudos_alheios.keys).each do |k|
      sp = @sp_escudos.delete(k)
      (sp.dispose rescue nil) if sp && !(sp.disposed? rescue true)
    end
    return if @escudos_alheios.empty?
    @escudos_alheios.each do |id, (_ate, tipo)|
      peer = (AnilLanRework.players[id] rescue nil)
      next unless peer && peer.respond_to?(:screen_x)
      sp = @sp_escudos[id]
      if sp.nil? || (sp.disposed? rescue true)
        bmp = bitmap_do_escudo(ESCUDO_MIN)
        next unless bmp
        sp = Sprite.new(viewport_do_escudo)
        sp.bitmap = bmp
        sp.ox = ESCUDO_MIN / 2
        sp.oy = ESCUDO_MIN / 2
        sp.blend_type = 1
        @sp_escudos[id] = sp
      end
      sp.x = (peer.screen_x rescue 0)
      sp.y = (peer.screen_y rescue 0) - 16
      t = (Graphics.frame_count rescue 0) / 60.0
      respira = Math.sin(t * ESCUDO_VELOC)
      sp.opacity = (ESCUDO_OPAC + (ESCUDO_PULSO * respira)).round
      # O espelho e mais quente, para nao se confundir com o escudo.
      if tipo == :espelho
        (sp.color.set(255, 200, 120, 90) rescue nil)
      else
        (sp.color.set(0, 0, 0, 0) rescue nil)
      end
    end
  rescue
    nil
  end

  def largar_escudos_alheios!
    (@sp_escudos || {}).each_value { |sp| (sp.dispose rescue nil) if sp && !(sp.disposed? rescue true) }
    @sp_escudos = {}
    @escudos_alheios = {}
  rescue
    nil
  end

  def correr_escudo!
    desenhar_escudos_alheios!
    de_pe = (escudo_de_pe? rescue false)
    unless de_pe
      apagar_escudo!
      return
    end
    quem = $game_player
    sp_dono = sprite_de(quem)
    return unless sp_dono && !(sp_dono.disposed? rescue true)

    d = diametro_do_escudo(quem)
    if @escudo_sprite.nil? || (@escudo_sprite.disposed? rescue true) || @escudo_diam != d
      apagar_escudo!
      bmp = bitmap_do_escudo(d)
      return unless bmp
      @escudo_diam = d
      @escudo_sprite = Sprite.new(viewport_do_escudo)
      @escudo_sprite.bitmap = bmp
      @escudo_sprite.ox = d / 2
      @escudo_sprite.oy = d / 2
      @escudo_sprite.blend_type = 1   # aditivo: brilha em vez de sujar
    end

    # No meio do boneco, e nao nos pes: o `y` do sprite e a base dele.
    altura = ((sp_dono.src_rect.height rescue 32) * (sp_dono.zoom_y rescue 1.0)).abs
    @escudo_sprite.x = sp_dono.x
    @escudo_sprite.y = sp_dono.y - (altura / 2).round

    t = (Graphics.frame_count rescue 0) / 60.0
    respira = Math.sin(t * ESCUDO_VELOC)
    @escudo_sprite.opacity = (ESCUDO_OPAC + (ESCUDO_PULSO * respira)).round
    escala = 1.0 + (0.04 * respira)
    @escudo_sprite.zoom_x = escala
    @escudo_sprite.zoom_y = escala
  rescue => e
    registar("falha no escudo: #{e.class}: #{e.message}")
  end

  def viewport_do_escudo
    if @vp_escudo.nil? || (@vp_escudo.disposed? rescue true)
      @vp_escudo = Viewport.new(0, 0, Graphics.width, Graphics.height)
      # 95 punha-o por cima dos bonecos mas por baixo das animacoes de golpe
      # (que correm no viewport das animacoes). Numa troca de golpes a bolha
      # ficava tapada exactamente quando era precisa. Sobe para 120: continua
      # por baixo do painel (que esta bem acima) e ja nao se esconde.
      @vp_escudo.z = 120
    end
    @vp_escudo
  end

  # Ao sair da arena vao-se os escudos dos outros com o nosso: os sprites
  # vivem num viewport que tambem se fecha, e um sprite orfao fica no ecra.
  def apagar_escudo!
    largar_escudos_alheios!
    (@escudo_sprite.dispose rescue nil) if @escudo_sprite && !(@escudo_sprite.disposed? rescue true)
    @escudo_sprite = nil
    @escudo_diam = nil
  rescue
    @escudo_sprite = nil
  end

  def largar_escudo!
    apagar_escudo!
    (@bitmaps_escudo || {}).each_value { |bm| (bm.dispose rescue nil) }
    @bitmaps_escudo = {}
    (@vp_escudo.dispose rescue nil) if @vp_escudo && !(@vp_escudo.disposed? rescue true)
    @vp_escudo = nil
  rescue
    nil
  end
  def piscar_cor!(quem, r, g, bb, frames)
    sp = sprite_de(quem)
    return unless sp
    (@flashes ||= {})[sp] = { :ate => (Graphics.frame_count rescue 0) + frames,
                              :cor => [r, g, bb], :vida => frames }
  rescue
    nil
  end

  def correr_flashes!
    return if @flashes.nil? || @flashes.empty?
    agora = (Graphics.frame_count rescue 0)
    @flashes.keys.each do |sp|
      d = @flashes[sp]
      fim = d.is_a?(Hash) ? d[:ate].to_i : d.to_i
      if sp.nil? || (sp.disposed? rescue true) || agora >= fim
        (sp.color.set(0, 0, 0, 0) rescue nil) if sp && !(sp.disposed? rescue true)
        @flashes.delete(sp)
        next
      end
      cor = d.is_a?(Hash) ? d[:cor] : [255, 40, 40]
      vida = d.is_a?(Hash) ? d[:vida].to_f : FLASH_FRAMES.to_f
      vida = FLASH_FRAMES.to_f if vida <= 0
      # Desvanece: forte no impacto, a apagar no fim.
      resta = (fim - agora).to_f / vida
      (sp.color.set(cor[0], cor[1], cor[2], (200 * resta).to_i) rescue nil)
    end
  rescue
    @flashes = {}
  end

  # Chega um golpe do adversario. Aqui e que se decide se acertou.
  def receber_golpe!(pacote)
    # O pacote da caverna entra pela mesma porta e segue o mesmo caminho — o
    # que muda e de quem veio e o que acontece quando a vida acaba.
    da_caverna = (pacote["caverna"] ? true : false)
    return unless @activa && (da_caverna ? caverna? : pvp?)
    # ⚠️ ERA AQUI QUE OS GOLPES DO PARCEIRO DESAPARECIAM.
    #
    # Eu recusava o pacote inteiro a porta, com o argumento de que um golpe que
    # se ve e nao magoa parece um erro. O efeito foi pior e obvio depois de
    # visto: assim que dois jogadores viravam parceiros, deixavam de ver os
    # golpes UM DO OUTRO — so os dos inimigos e que apareciam.
    #
    # Um golpe e duas coisas: um desenho e um dano. So o dano e que e
    # amigo-ou-inimigo. O desenho e sempre bem-vindo — e por ele que se sabe
    # que o parceiro esta a fazer alguma coisa, para que lado, e contra quem.
    #
    # Portanto marca-se, e segue. Quem aplica o dano e que olha para a marca.
    if da_caverna && (coop_amigo?(pacote["sender_id"]) || amizade_declarada?(pacote))
      pacote = pacote.merge("amigo" => true)
    end
    forma = pacote["forma"].to_s.to_sym
    anim  = pacote["anim"].to_i
    ax    = pacote["x"].to_i
    ay    = pacote["y"].to_i
    dir   = pacote["dir"].to_i

    # A animacao ve-se sempre, acerte ou nao — e o que da a ler o combate. Mas
    # so uma vez: quando o impacto vier da fila, o desenho ja foi feito.
    if !pacote["ja_esperou"] && !pacote["proj"]
      outro = da_caverna ? quem_mandou(pacote) : adversario_remoto
      if da_caverna
        # ⚠️ QUEM LANCA E ELE. EU SOU O ALVO.
        #
        # Isto desenhava com as ancoras trocadas: `tocar_no_character!(outro,
        # anim)` poe o OUTRO como alvo e deixa o utilizador no valor por
        # omissao, que e o `$game_player` — ou seja, o golpe dele era desenhado
        # a sair de mim e a ir para ele. Com dois jogadores lado a lado isso
        # le-se como se eu estivesse a atacar o meu proprio parceiro.
        #
        # A linha da animacao e utilizador -> alvo, e aqui e dele -> mim: e o
        # quarto argumento que diz de quem parte.
        # ⚠️ A ANIMACAO SOZINHA NAO CHEGA, E O BUBBLE E A PROVA.
        #
        # Uma animacao do motor e desenhada entre duas ancoras — quem lanca e
        # quem leva. Se uma delas nao resolver (o boneco do atacante ainda nao
        # esta na lista de peers, o indice da animacao vem a zero para aquele
        # golpe, o `setLineTransform` degenera com os dois pontos no mesmo
        # sitio), nao ha aviso nenhum: fica o som e mais nada. E o que se
        # relatou, e ha semanas.
        #
        # A copia visual nao depende disso. E o mesmo caminho que os
        # LANCAMENTOS do adversario ja usavam: uma particula que sai de onde ele
        # disse que estava e voa na direccao que ele disse — com o desenho da
        # folha do golpe, sem ancoras e sem contas de palco. Ela nao magoa
        # ninguem (o dano continua a ser decidido por quem leva); serve so para
        # se VER que ele atacou, e de onde.
        #
        # Mantem-se a animacao por cima quando ela resolve — as duas juntas sao
        # o que se ve num golpe proprio.
        # ⚠️ UM GOLPE DO PARCEIRO NAO E UM GOLPE CONTRA MIM.
        #
        # Isto punha `$game_player` como ALVO de tudo o que chegava — e para um
        # inimigo esta certo, o alvo sou mesmo eu. Para um parceiro esta errado
        # de uma maneira que se ve: a animacao e desenhada entre duas ancoras, e
        # os golpes que tem uma segunda parte (o X-Scissor tem) tocam essa parte
        # em cima do ALVO. Ou seja: a tesourada do meu parceiro fechava-se na
        # minha cara, como se eu fosse o que ele estava a atacar.
        #
        # Agora o pacote diz contra quem foi (o `ax`/`ay`), e o golpe de um
        # amigo desenha-se dele para ESSE ponto. Eu deixo de ser uma das pontas.
        # Sem coordenadas — um pacote antigo, ou um golpe sem alvo — usa-se uma
        # casa a frente dele, na direccao que ele escreveu: tambem nao sou eu.
        if anim > 0 && pacote["em_mim"]
          # Uma animacao que e so dele: a volta dele, e nada mais.
          tocar_ancorado_em!(outro, anim) if outro
        elsif anim > 0 && pacote["amigo"]
          px, py = ponto_do_golpe_alheio(pacote, ax, ay, dir)
          if outro
            tocar_no_ponto!(anim, px, py, 0, outro)
          else
            tocar_no_chao!(anim, px.round, py.round, 0)
          end
        elsif anim > 0
          if outro
            tocar_no_character!($game_player, anim, 0, outro)
          else
            # ⚠️ ERA AQUI QUE O GOLPE DELE SAIA DO MEU POKEMON.
            #
            # O `tocar_no_chao!` ancora o ALVO no chao e deixa a ponta de
            # PARTIDA por omissao, que e o `$game_player` ? eu. Relatado como
            # "o bubblebeam que eu uso sai do Pokemon dele, que nem tem o
            # ataque". Estava certo em toda a parte menos na ponta que conta.
            #
            # Agora e ao contrario: a partida e o ponto que ele escreveu no
            # pacote, e o alvo sou eu.
            tocar_do_ponto!(anim, ax, ay, $game_player, 0)
          end
        end
        # Uma animacao propria nao tem projectil nem copia: acabou aqui.
        return if pacote["em_mim"]
        desenhar_golpe_recebido!(pacote["move"].to_s.to_sym, anim, ax, ay, dir, pacote)
      else
        tocar_no_character!(outro, anim) if outro && anim > 0
        tocar_no_character!($game_player, anim) if anim > 0 && forma != :area
      end
    end
    outro ||= (da_caverna ? quem_mandou(pacote) : adversario_remoto)

    # ⚠️ O PROJECTIL DO OUTRO CORRE NA MINHA MAQUINA, MIRADO EM MIM.
    #
    # Nao se recebe "o adversario acertou-te": recebe-se "o adversario lancou
    # isto, dali, contra ti". A bola e simulada aqui, do meu lado, a perseguir o
    # MEU boneco — e so quando ela me alcanca e que eu me tiro vida. Os dois
    # ecrans mostram a mesma bola porque partem dos mesmos dados do golpe, e a
    # decisao continua a ser de quem leva, que e a regra de toda a arena.
    if pacote["proj"]
      # ⚠️ O QUE DECIDE E INVISIVEL; O QUE SE VE E UMA COPIA.
      #
      # A vitima precisa de um projectil com a caixa de colisao certa para saber
      # quando levou — mas esse nao precisa de ter desenho nenhum. O desenho vem
      # a parte, no mesmo estilo que o atacante viu: particulas se o golpe for
      # de jorro ou de area, uma bola se for uma bola. Assim os dois ecrans
      # mostram a mesma coisa e nenhum deles mostra duas.
      id_mv = pacote["move"].to_s.to_sym
      lancar!(:x => ax, :y => ay, :dir => dir, :alvo => $game_player,
              :anim => 0, :infalivel => pacote["infalivel"], :invisivel => true,
              :move_id => id_mv,
              :nome => nil, :meu => false, :pacote => pacote,
              :alcance => (pacote["alcance"] || PROJ_ALCANCE).to_f,
              :curto => pacote["curto"], :vel => pacote["vel"])
      desenhar_golpe_recebido!(id_mv, anim, ax, ay, dir, pacote)
      return
    end

    # ⚠️ A VITIMA ESPERA O MESMO TEMPO QUE O PROJECTIL DEMORA A CHEGAR.
    #
    # Se ela conferisse assim que o pacote chega, um golpe a distancia acertava
    # antes de a animacao sequer sair do atacante — e do lado dela nao havia
    # forma de se desviar. O atraso vem no pacote para os dois lados fazerem a
    # pergunta no mesmo ponto da animacao.
    atraso = pacote["atraso"].to_i
    if atraso > 0 && !pacote["ja_esperou"]
      (@impactos_pvp ||= []) << {
        :em => (Graphics.frame_count rescue 0) + atraso,
        :p  => pacote.merge("ja_esperou" => true)
      }
      return
    end

    acertou = em_alcance?(forma, ax, ay, dir, $game_player.x, $game_player.y)
    unless acertou
      registar("golpe recebido #{pacote['move']} de (#{ax},#{ay}) dir=#{dir}: nao apanhou")
      return
    end

    aplicar_golpe_recebido!(pacote)
  rescue => e
    registar("falha a receber golpe: #{e.class}: #{e.message}")
  end

  # A copia visual do golpe do adversario, feita nesta maquina com as regras
  # desta maquina. Nada aqui tira vida a ninguem: e so o que se ve.
  # Contra quem e que o golpe dele foi. Pela ordem da confianca: o que ele
  # escreveu no pacote; senao uma casa a frente dele, no rumo que ele escreveu.
  def ponto_do_golpe_alheio(pacote, ax, ay, dir)
    if pacote["ax"] && pacote["ay"]
      return [pacote["ax"].to_f, pacote["ay"].to_f]
    end
    case dir.to_i
    when 2 then [ax.to_f, ay.to_f + 1.0]
    when 8 then [ax.to_f, ay.to_f - 1.0]
    when 4 then [ax.to_f - 1.0, ay.to_f]
    else        [ax.to_f + 1.0, ay.to_f]
    end
  rescue
    [ax.to_f + 1.0, ay.to_f]
  end

  def desenhar_golpe_recebido!(id_mv, anim, ax, ay, dir, pacote)
    return if anim.to_i <= 0
    mv_falso = (GameData::Move.get(id_mv) rescue nil)
    return unless mv_falso
    # ⚠️ O GOLPE DELE TEM DE SE VER COMO O MEU SE VE.
    #
    # Esta era a quarta copia da decisao, e a mais facil de esquecer porque so
    # aparece quando ha outra pessoa no mapa. Marcado como feixe na oficina, o
    # golpe do outro jogador saia daqui como um enxame de particulas — ele via
    # uma linha no ecra dele e eu via bolas a voar no meu, pelo mesmo golpe.
    if saida_do_golpe(mv_falso, anim) == :feixe
      autor = (quem_mandou(pacote) || adversario_remoto)
      if autor
        px, py = ponto_do_golpe_alheio(pacote, ax, ay, dir)
        d = Math.sqrt((((px - ax)**2) + ((py - ay)**2)).to_f)
        casas = ((palco_da_anim(anim) || {})["feixe_casas"] || ALCANCE_FEIXE).to_f
        d = casas if d < 0.001 || d > casas
        rx = (px - ax)
        ry = (py - ay)
        n = Math.sqrt((rx * rx) + (ry * ry))
        if n < 0.001
          case dir.to_i
          when 2 then rx, ry, n = 0.0,  1.0, 1.0
          when 8 then rx, ry, n = 0.0, -1.0, 1.0
          when 4 then rx, ry, n = -1.0, 0.0, 1.0
          else        rx, ry, n = 1.0,  0.0, 1.0
          end
        end
        tocar_no_ponto!(anim, ax + ((rx / n) * d), ay + ((ry / n) * d), 0, autor)
        return
      end
    end
    quantas = 1
    pequeno = false
    vagueia = 0.0
    forma = pacote["forma"].to_s
    if FEIXES.include?(id_mv) && (mv_falso.type == :FIRE rescue false)
      quantas = JORRO_PARTICULAS
      pequeno = true
      vagueia = VAGUEIA_FEIXE
    end
    quantas.times do |k|
      (@lancamentos ||= []) << {
        :em => (Graphics.frame_count rescue 0) + (k * JORRO_INTERVALO),
        # ⚠️ Uma copia unica leva a animacao de impacto; um enxame de copias nao.
        #
        # Sao seis particulas de jorro a chegar quase juntas: se cada uma tocasse
        # a animacao inteira, seriam seis animacoes empilhadas. Com uma copia so,
        # ela E o golpe e tem de acabar como o golpe acaba.
        # ⚠️ E A PARTICULA DELE TAMBEM NAO VOA PARA MIM.
        #
        # Ela era lancada com `:alvo => $game_player` — o que esta certo para um
        # golpe que vem contra nos e errado para o do parceiro, que ia atras de
        # mim pelo mapa fora como se eu fosse a presa. Quando e de um amigo, ela
        # vai para onde ele apontou.
        :copia => { :x => ax, :y => ay, :dir => dir, :anim => anim.to_i,
                    :impacto => (quantas == 1 ? anim.to_i : 0),
                    :move_id => id_mv, :pequeno => pequeno, :vagueia => vagueia,
                    :amigo => (pacote["amigo"] ? true : false),
                    :px => (pacote["ax"] ? pacote["ax"].to_f : nil),
                    :py => (pacote["ay"] ? pacote["ay"].to_f : nil) }
      }
    end
  rescue => e
    registar("falha a desenhar o golpe recebido: #{e.class}: #{e.message}")
  end

  def soltar_copia_visual!(c)
    alvo = $game_player
    if c[:amigo]
      # Um amigo nao me persegue: a particula dele segue para onde ele apontou,
      # e se ele nao disse, segue em frente e morre no alcance.
      alvo = (c[:px] && c[:py]) ? marcador_no_ponto(c[:px], c[:py]) : nil
    end
    lancar!(:x => c[:x], :y => c[:y], :dir => c[:dir], :alvo => alvo,
            :anim => c[:impacto].to_i, :cartao_de => c[:anim], :pequeno => c[:pequeno],
            :vagueia => c[:vagueia], :infalivel => false, :so_desenho => true,
            :move_id => c[:move_id], :mv => nil, :nome => nil, :meu => true,
            :lado => (c[:amigo] ? :nosso : :deles),
            :alcance => PROJ_ALCANCE, :curto => false, :vel => PROJ_VEL)
  rescue
    nil
  end

  # Um ponto do chao que serve de alvo a um projectil. E o marcador 2, que ja
  # existe para ancorar animacoes e nao esta a ser usado para nada durante um
  # voo — dois projecteis a pedi-lo ao mesmo tempo partilham-no, e como eles so
  # leem a posicao no frame em que passam por la, isso e exactamente o que se
  # quer: cada um vai para onde o seu dono apontou.
  def marcador_no_ponto(fx, fy)
    ev = garantir_marcador2!
    return nil unless ev
    ev.instance_variable_set(:@real_x, (fx.to_f * Game_Map::REAL_RES_X).round)
    ev.instance_variable_set(:@real_y, (fy.to_f * Game_Map::REAL_RES_Y).round)
    ev.instance_variable_set(:@x, fx.to_f.round)
    ev.instance_variable_set(:@y, fy.to_f.round)
    ev
  rescue
    nil
  end

  # Tudo o que acontece a quem leva, seja o golpe marcado no tempo ou uma bola
  # que chegou. Fica num sitio so para as duas portas contarem a mesma historia.
  def aplicar_golpe_recebido!(pacote)
    return unless pacote
    da_caverna = (pacote["caverna"] ? true : false)
    return unless @activa && (da_caverna ? caverna? : pvp?)
    # O desenho ja foi feito la atras; o que se recusa aqui e o dano.
    return if da_caverna && pacote["amigo"]
    outro = da_caverna ? quem_mandou(pacote) : adversario_remoto

    # ⚠️ O ESCUDO E CONFERIDO AQUI, do lado de quem leva.
    #
    # E a mesma regra de todo o resto: quem decide se foi atingido e a vitima.
    # Se o escudo fosse verificado no atacante, ele teria de saber em tempo real
    # se o outro esta a segurar o botao — informacao que so chega com atraso e
    # que daria golpes a passar atraves de escudos levantados a tempo.
    if clone_comeu?
      enviar!("arena_dano", "dano" => 0, "hp" => @hp_meu, "hp_max" => (@meu.totalhp.to_i rescue 1))
      return
    end
    if escudo_de_pe?
      aparar!
      enviar!("arena_dano", "dano" => 0, "hp" => @hp_meu, "hp_max" => (@meu.totalhp.to_i rescue 1))
      return
    end

    d = dano_recebido(pacote)
    d = [(d * pacote["forca"].to_f).round, 1].max if pacote["forca"]
    talvez_aplicar_estado!(pacote["move"].to_s.to_sym)
    @hp_meu = [@hp_meu - d, 0].max
    empurrar!($game_player, outro) if outro && d > 0
    dizer(d > 0 ? "Levaste #{d}!" : "Efeito!")
    # Diz-se sempre como se ficou: e por esta mensagem que o outro desenha a
    # barra. Se ela nao chegasse, ele via-me com a vida cheia para sempre.
    enviar!("arena_dano", "dano" => d, "hp" => @hp_meu, "hp_max" => (@meu.totalhp.to_i rescue 1))
    if @hp_meu <= 0
      # ⚠️ NA CAVERNA CAIR NAO E SAIR: E PERDER O QUE SE APANHOU.
      #
      # O `sair!` do duelo fecha a arena e devolve o jogador ao mundo com tudo
      # o que tem. Cair na caverna tem um preco, e quem o cobra e o
      # `terminar_derrota!` — e ele que, quando nao houver mais ninguem de pe,
      # chama o `caiu!` e larga o saque no chao para quem o quiser.
      if da_caverna
        terminar_derrota!
      else
        enviar!("arena_fim", "perdi" => true)
        sair!
        pbMessage(_INTL("Seu Pokémon foi derrotado na arena.")) rescue nil
      end
    end
  rescue => e
    registar("falha a aplicar golpe: #{e.class}: #{e.message}")
  end

  # O atacante manda os numeros dele; a defesa e minha. Confia-se no que ele
  # diz sobre o ataque dele, porque so ele o sabe — mas os limites sao meus,
  # senao um cliente adulterado mandava um ataque de um milhao.
  def dano_recebido(pacote)
    nivel = [[pacote["nivel"].to_i, 1].max, 100].min
    dados = (GameData::Move.get(pacote["move"].to_s.to_sym) rescue nil)
    poder = dados ? dados.power.to_i : 40
    # Sem forca e um golpe de estado: o efeito ja foi aplicado, dano e zero.
    return 0 if dados && (dados.category == 2 || dados.power.to_i <= 0)
    poder = 40 if poder <= 0
    especial = (dados && dados.category == 1)
    atq = especial ? pacote["spatk"].to_i : pacote["atk"].to_i
    atq = [[atq, 1].max, 999].min
    def_ = especial ? (@meu.spdef.to_i rescue 50) : (@meu.defense.to_i rescue 50)
    def_ = 1 if def_ <= 0
    base = (((2.0 * nivel / 5.0 + 2.0) * poder * atq / def_) / 50.0) + 2.0
    mult = 1.0
    if dados
      tipos = [(@meu.types rescue [])].flatten.compact
      mult = (Effectiveness.calculate(dados.type, *tipos) rescue 1.0)
    end
    return 0 if mult <= 0.0
    [((base * mult * (0.85 + rand * 0.15)).round), 1].max
  rescue
    1
  end

  # A armadilha do adversario existe na MINHA maquina com a marca dele: quando
  # eu passo por cima, sou eu que me tiro a vida e anuncio. Mesma regra do resto
  # — quem leva e que decide.
  def receber_armadilha!(pacote)
    return unless @activa && pvp?
    id = pacote["move"].to_s.to_sym
    nome = (GameData::Move.get(id).name rescue pacote["move"].to_s)
    casas = pacote["casas"]
    if casas.is_a?(Array) && !casas.empty?
      semear_armadilhas!(nil, nome, pacote["anim"].to_i, false,
                         pacote["ox"].to_i, pacote["oy"].to_i, casas)
      # O `move_id` e o que faz a armadilha saber envenenar ou so espetar; as
      # sementes ainda estao no ar, por isso a marca vai nelas.
      sementes.each { |g| g[:move_id] = id }
    else
      # Um cliente antigo ainda manda uma casa so. Aceita-se: e melhor um
      # espinho no sitio certo do que um golpe que nao aconteceu.
      por_armadilha!(nil, nome, pacote["anim"].to_i, false,
                     pacote["x"].to_i, pacote["y"].to_i)
      (@armadilhas.last[:move_id] = id) if @armadilhas && @armadilhas.last
    end
  rescue => e
    registar("falha a receber armadilha: #{e.class}: #{e.message}")
  end

  def receber_dano!(pacote)
    return unless @activa && pvp?
    @hp_dele = [pacote["hp"].to_i, 0].max
    @hp_dele_max = [pacote["hp_max"].to_i, 1].max
    d = pacote['dano'].to_i
    dizer(d > 0 ? "Acertaste #{d}!" : "Não pegou!")
    if @hp_dele <= 0
      sair!
      pbMessage(_INTL("Você venceu a arena!")) rescue nil
    end
  rescue
    nil
  end

  #-----------------------------------------------------------------------------
  # O CONVITE
  #
  # ⚠️ Nao se reaproveita o convite de PvP normal (MOD 110) de proposito: aquele
  # negoceia equipas, tamanhos e regras, e acaba numa batalha por turnos. Aqui e
  # outra coisa — dois bonecos no mapa — e misturar as duas maquinas de estados
  # so ia dar confusao nas duas.
  #-----------------------------------------------------------------------------
  # ⚠️ UM POKEMON DE SORTEIO, PARA TESTAR SEM PREPARAR NADA.
  #
  # A escolher da equipa, cada teste comeca com dois menus e acaba sempre com os
  # mesmos bichos — e o que se quer ver e como se sente contra coisas
  # diferentes. No modo aleatorio ninguem escolhe: os dois recebem um sorteado
  # ao mesmo nivel, e basta aceitar.
  #
  # Nivel fixo de proposito: com niveis da equipa real, um lado abria com 100 e
  # o outro com 12, e o que se testava passava a ser a diferenca de niveis em
  # vez dos controlos.
  NIVEL_SORTEIO = 50

  def sortear_pokemon
    especies = (GameData::Species.keys rescue [])
    especies = especies.reject { |e| e.to_s.include?("_") }   # sem formas alternativas
    especies = [:PIKACHU] if especies.empty?
    10.times do
      p = (Pokemon.new(especies.sample, NIVEL_SORTEIO) rescue nil)
      # Um Pokemon sem golpes de ataque nao da combate nenhum.
      next unless p && p.moves.compact.any? { |m| (GameData::Move.get(m.id).power.to_i rescue 0) > 0 }
      return p
    end
    (Pokemon.new(:PIKACHU, NIVEL_SORTEIO) rescue nil)
  rescue
    nil
  end

  def escolher_da_equipa(texto)
    equipa = ($player.party.compact rescue [])
    return nil if equipa.empty?
    nomes = equipa.map { |p| "#{p.name} Nv.#{p.level}" }
    nomes << _INTL("Cancelar")
    i = pbMessage(texto, nomes, nomes.length)
    return nil if i < 0 || i >= equipa.length
    equipa[i]
  rescue
    nil
  end

  # Resumo do Pokemon que viaja no convite: chega para a barra de vida e para o
  # nome. O objecto inteiro nao vai — nao ha razao para dar a outro cliente os
  # IVs, os golpes e o personalID do meu bicho.
  def resumo(pkmn)
    {
      "especie" => pkmn.species.to_s,
      "nome"    => pkmn.name.to_s,
      "nivel"   => pkmn.level.to_i,
      "hp"      => pkmn.totalhp.to_i
    }
  rescue
    { "especie" => "PIKACHU", "nome" => "?", "nivel" => 50, "hp" => 100 }
  end

  def pokemon_do_resumo(r)
    esp = r["especie"].to_s.upcase.to_sym
    esp = :PIKACHU unless (GameData::Species.exists?(esp) rescue false)
    p = Pokemon.new(esp, [[r["nivel"].to_i, 1].max, 100].min)
    p
  rescue
    nil
  end

  def convidar!(nome_alvo, aleatorio = false)
    unless AnilArena.directa?
      avisar(_INTL("Você não tem o Amuleto Teste."))
      return
    end
    unless (AnilLanRework.connected? rescue false)
      avisar(_INTL("Você precisa estar conectado."))
      return
    end
    if activa?
      avisar(_INTL("Você já está na arena."))
      return
    end
    alvo = nome_alvo.to_s.strip.downcase
    peer = (AnilLanRework.players.values.find { |p| p.name.to_s.downcase == alvo } rescue nil)
    peer ||= (AnilLanRework.players.values.find { |p| p.name.to_s.downcase.include?(alvo) } rescue nil)
    unless peer
      avisar(_INTL("Não encontrei ninguém com esse nome por perto."))
      return
    end
    if (peer.map_id.to_i != $game_map.map_id.to_i rescue true)
      avisar(_INTL("{1} precisa estar no mesmo mapa.", peer.name.to_s))
      return
    end

    # ⚠️ O MODO E DECIDIDO POR QUEM CONVIDA, E VIAJA NO CONVITE.
    #
    # Se cada lado escolhesse o seu, um jogava a dois e o outro sozinho — e a
    # luta nascia torta sem ninguem ter feito nada de errado. Quem convida
    # propoe; quem aceita ve no texto do convite o que vai jogar e escolhe os
    # SEUS Pokemon para esse modo.
    dupla = false
    unless aleatorio
      modos = [_INTL("Um contra um"), _INTL("Dupla (2 contra 2)"), _INTL("Cancelar")]
      escolha_modo = (pbMessage(_INTL("Que tipo de batalha?"), modos, 3) rescue 2)
      return if escolha_modo < 0 || escolha_modo >= 2
      dupla = (escolha_modo == 1)
    end

    meu = aleatorio ? sortear_pokemon : escolher_da_equipa(_INTL("Quem entra na arena?"))
    return unless meu
    ajuda = nil
    if dupla
      ajuda = escolher_ajudante!(meu)
      unless ajuda
        avisar(_INTL("Sem um segundo Pokémon não dá para lutar em dupla."))
        return
      end
    end
    @convite_meu = { :peer => peer.internal_id.to_s, :pkmn => meu, :ajuda => ajuda }
    AnilLanRework.connection.send_packet("arena_convite",
      "to_id"     => peer.internal_id.to_s,
      "aleatorio" => (aleatorio ? true : false),
      "dupla"     => dupla,
      "pkmn"      => resumo(meu)) rescue nil
    avisar(AnilLanRework.ui_format("Convite de arena enviado a {1}...", peer.name.to_s))
  rescue => e
    registar("falha a convidar: #{e.class}: #{e.message}")
  end

  def receber_convite!(pacote)
    # Quem nao tem o amuleto nao pode ser arrastado para uma arena por outro.
    # E o Guia Mestre nao serve: lutar contra outro jogador e batalha directa.
    return unless AnilArena.directa?
    de = pacote["sender_id"].to_s
    peer = (AnilLanRework.players[de] rescue nil)
    nome = peer ? peer.name.to_s : de
    r = pacote["pkmn"] || {}
    if activa?
      AnilLanRework.connection.send_packet("arena_recusa", "to_id" => de) rescue nil
      return
    end
    dupla = (pacote["dupla"] == true)
    texto = if pacote["aleatorio"] == true
      AnilLanRework.ui_format("{1} quer uma arena ALEATÓRIA (ele levou {2}). Você recebe um sorteado. Aceitar?",
                              nome, r["nome"].to_s)
    elsif dupla
      AnilLanRework.ui_format("{1} quer uma batalha EM DUPLA com {2} Nv.{3}. Você leva dois: um seu e um da IA. Aceitar?",
                              nome, r["nome"].to_s, r["nivel"].to_i)
    else
      AnilLanRework.ui_format("{1} quer uma batalha de arena com {2} Nv.{3}. Aceitar?",
                              nome, r["nome"].to_s, r["nivel"].to_i)
    end
    unless (pbConfirmMessage(texto) rescue false)
      AnilLanRework.connection.send_packet("arena_recusa", "to_id" => de) rescue nil
      return
    end
    # No modo aleatorio nao ha escolha nenhuma: aceitar ja e entrar.
    meu = (pacote["aleatorio"] == true) ? sortear_pokemon :
                                          escolher_da_equipa(_INTL("Quem entra na arena?"))
    unless meu
      AnilLanRework.connection.send_packet("arena_recusa", "to_id" => de) rescue nil
      return
    end
    ajuda = nil
    if dupla
      ajuda = escolher_ajudante!(meu)
      unless ajuda
        avisar(_INTL("Sem um segundo Pokémon não dá para lutar em dupla."))
        AnilLanRework.connection.send_packet("arena_recusa", "to_id" => de) rescue nil
        return
      end
    end
    AnilLanRework.connection.send_packet("arena_aceite",
      "to_id" => de, "pkmn" => resumo(meu), "dupla" => dupla) rescue nil
    inimigo = pokemon_do_resumo(r)
    return unless inimigo
    entrar!(meu, inimigo, de)
    chamar_aliado!(ajuda) if ajuda
    @hp_dele = [r["hp"].to_i, 1].max
    @hp_dele_max = @hp_dele
    avisar(AnilLanRework.ui_format("Arena contra {1}! A/S/D/Shift para os golpes.", nome))
  rescue => e
    registar("falha a receber convite: #{e.class}: #{e.message}")
  end

  def receber_aceite!(pacote)
    return unless @convite_meu
    de = pacote["sender_id"].to_s
    return unless de == @convite_meu[:peer]
    meu = @convite_meu[:pkmn]
    # ⚠️ O ajudante so entra AGORA. Chama-lo ao convidar punha um Pokemon no
    # mapa a espera de uma luta que podia nunca acontecer — e a recusa do outro
    # deixava-o la, sem dono.
    ajuda = @convite_meu[:ajuda]
    @convite_meu = nil
    r = pacote["pkmn"] || {}
    inimigo = pokemon_do_resumo(r)
    return unless inimigo
    entrar!(meu, inimigo, de)
    chamar_aliado!(ajuda) if ajuda
    @hp_dele = [r["hp"].to_i, 1].max
    @hp_dele_max = @hp_dele
    peer = (AnilLanRework.players[de] rescue nil)
    avisar(AnilLanRework.ui_format("Arena contra {1}! A/S/D/Shift para os golpes.",
                                   peer ? peer.name.to_s : de))
  rescue => e
    registar("falha a receber aceite: #{e.class}: #{e.message}")
  end

  def recusar_convite!
    return unless @convite_meu
    AnilLanRework.connection.send_packet("arena_recusa", "to_id" => @convite_meu[:peer]) rescue nil
    @convite_meu = nil
    avisar(_INTL("Convite de arena cancelado."))
  rescue
    nil
  end

  def receber_recusa!(_pacote)
    @convite_meu = nil
    avisar(_INTL("O convite de arena foi recusado."))
  rescue
    nil
  end

  def receber_fim!(_pacote)
    return unless @activa && pvp?
    sair!
    pbMessage(_INTL("Você venceu a arena!")) rescue nil
  rescue
    nil
  end

  def terminar_vitoria!
    sair!
    pbMessage(_INTL("Você venceu a arena!")) rescue nil
  end

  # ⚠️ A ARENA NAO PODE DEIXAR O JOGADOR SEM NINGUEM DE PE.
  #
  # A vida daqui vai para a equipa — e isso e o que se quer. Mas se o ULTIMO
  # Pokemon capaz cair aqui, o jogo fica num estado que ele so sabe criar dentro
  # de uma batalha a serio: sem ninguem para lutar e sem ter passado pelo
  # "voce perdeu" que teleporta para o Centro. O proximo encontro selvagem
  # rebenta a montar uma batalha 0x0 — foi o erro que apareceu no evento 8129.
  #
  # Enquanto houver outro Pokemon capaz, quem cai aqui cai a serio. Sendo o
  # ultimo, fica com 1 de vida: nao venceu, mas o mundo continua a funcionar.
  def escrever_vida_na_equipa!
    return unless @meu
    valor = [[@hp_meu.to_i, 0].max, @meu.totalhp.to_i].min
    if valor <= 0
      outros = ($player.party.compact.count { |p| !p.equal?(@meu) && !p.egg? && p.hp > 0 } rescue 0)
      valor = 1 if outros <= 0
    end
    (@meu.hp = valor) rescue nil
  rescue
    nil
  end

  # ⚠️ MORRER NAO PODE SER UM CORTE A MEIO DE UM FRAME.
  #
  # O `sair!` desmontava tudo no instante em que a vida chegava a zero: a
  # animacao do golpe que matou desaparecia a meio, o boneco sumia sem cair, e a
  # janela de texto abria por cima de um mapa que ja nao tinha luta nenhuma.
  #
  # Uma derrota precisa de um segundo para ser lida. Marca-se o fim, deixa-se o
  # Pokemon cair como qualquer outro cai, e so depois se desmonta — pelo mesmo
  # caminho do relogio que todo o resto usa.
  DERROTA_TEMPO = 1.4

  # ⚠️ TRES DEFEITOS, UMA SO CAUSA: CAIR NAO ERA UM ESTADO.
  #
  # O `@derrota_ate` e um relogio de 1,4 s — o tombo. Quando ele acaba, o
  # `fechar_derrota!` limpa-o e decide o que fazer. Na masmorra com companhia,
  # decide ficar caido a espera de socorro... e deixa o `@hp_meu` a ZERO com o
  # `@derrota_ate` ja nulo.
  #
  # A partir daí qualquer coisa que volte a ferir-me — e os selvagens continuam
  # a bater-me, porque eu continuava na lista de alvos deles — entra outra vez
  # aqui, encontra `@derrota_ate` nulo, e comeca um tombo NOVO. O ciclo repete-
  # se enquanto houver um bicho por perto.
  #
  # E isso explica as tres queixas de uma vez:
  #
  #   "a mensagem repete-se sem parar"    e um tombo novo de cada vez
  #   "nao me leva ao centro Pokemon"     o `caiu!` do tombo anterior e
  #                                       interrompido pelo seguinte
  #   "continuam a ver-me como alvo"      eu nunca sai da lista
  #   (e o balanco nao se via porque o estado era desfeito e refeito)
  #
  # Basta uma linha: quem ja esta caido nao volta a cair.
  def terminar_derrota!
    return if @derrota_ate
    return if caido?
    @hp_meu = 0
    escrever_vida_na_equipa!
    @derrota_ate = Time.now.to_f + DERROTA_TEMPO
    animar_desmaio!($game_player)
    dizer(_INTL("{1} desmaiou!", (@meu.name rescue "")))
    # O boneco fica invisivel enquanto a copia dele cai — senao viam-se dois.
    ($game_player.opacity = 0) rescue nil
  rescue
    fechar_derrota!
  end

  def correr_derrota!
    return unless @derrota_ate
    return if Time.now.to_f < @derrota_ate.to_f
    fechar_derrota!
  rescue
    nil
  end

  def fechar_derrota!
    nome = (@meu.name rescue _INTL("Seu Pokémon"))
    @derrota_ate = nil
    ($game_player.opacity = 255) rescue nil
    # Numa batalha de treinador a queda de um Pokemon e uma TROCA, nao um fim.
    # So se perde quando nao sobrar mais ninguem de pe.
    # O ajudante primeiro: se ele esta de pe, a luta continua com ele. Vale
    # tanto contra um treinador como contra outro jogador — em qualquer dos
    # casos ainda ha alguem nosso no campo.
    return if assumir_aliado!
    if treinador?
      return if trocar_o_meu!
      terminar_treinador!(2)
      return
    end
    # ⚠️ NA CAVERNA A DERROTA NAO E SO O FIM DA LUTA: E O PRECO.
    #
    # Aqui e o unico sitio onde a queda esta mesmo decidida — depois de o
    # ajudante ter sido chamado e de nao haver mais ninguem de pe. Antes disto
    # ainda ha luta; a seguir a isto ja se saiu do mapa.
    #
    # O `caiu!` larga no chao o que se apanhou la dentro e trata da saida
    # (chama o `sair!` por dentro), por isso nao se chama o `sair!` aqui.
    # ⚠️ ESTA DECISAO TEM DE DEIXAR RASTO, E NAO DEIXAVA.
    #
    # Quando o jogador diz "cai e nao bambeou nada, e o meu boneco apareceu la
    # dentro", eu nao tenho maneira nenhuma de saber por qual dos dois ramos e
    # que ele passou — e a diferenca entre os dois e a diferenca entre um bug
    # na ressurreicao e um bug na saida. Passei uma ronda inteira a adivinhar
    # entre as duas coisas.
    #
    # Uma linha por derrota. E o custo de nunca mais ter de adivinhar isto.
    # ⚠️ E AQUI O INTERRUPTOR TAMBEM NAO PODE MANDAR SOZINHO.
    #
    # O `caverna?` pergunta pela `@activa` da masmorra. Estando ela errada — e
    # e o que se anda a perseguir — a derrota caia no ramo de baixo: um `sair!`
    # e um "desmaiou", sem sair do mapa e sem ir a lado nenhum. O jogador ficava
    # de pe la dentro com a arena ja fechada, que e exactamente o print.
    #
    # Os mapas de instancia nao precisam de interruptor: ninguem esta no 306 por
    # acaso.
    if caverna? || (AnilRaidCaverna.so_da_masmorra? rescue false)
      companhia = (AnilArenaRessurreicao.ha_companhia? rescue false)
      (AnilRaidCaverna.log_sempre(
        "DERROTA: companhia=#{companhia} ligado=#{(AnilLanRework.connected? rescue false)} " \
        "gente=#{((AnilLanRework.players || {}).length rescue -1)} " \
        "mapa=#{($game_map.map_id rescue '?')} " \
        "#{(AnilArenaRessurreicao.retrato_da_gente rescue '[?]')}") rescue nil)
      # ⚠️ COM COMPANHIA, A QUEDA E UMA ESPERA.
      #
      # Sozinho nada muda: perde-se o que se trazia e sai-se. Com outro jogador
      # la dentro, ha trinta segundos em que ainda se pode ser salvo — e e isso
      # que transforma a masmorra a dois numa coisa diferente da masmorra a um.
      if companhia
        cair_a_espera_de_socorro!(nome)
        return
      end
      pbMessage(_INTL("{1} desmaiou!", nome)) rescue nil
      (AnilRaidCaverna.caiu! rescue nil)
      return
    end
    sair!
    pbMessage(_INTL("{1} desmaiou!", nome)) rescue nil
    if ($player.able_pokemon_count rescue 1) <= 0
      pbMessage(_INTL("Você não tem mais Pokémon em condições de lutar!")) rescue nil
    end
  rescue
    nil
  end

  #-----------------------------------------------------------------------------
  # CAIDO, A ESPERA DE SOCORRO
  #
  # ⚠️ NAO SE SAI DA ARENA. E essa a diferenca toda.
  #
  # Se eu fechasse a arena e reabrisse ao ser revivido, perdia-se a populacao da
  # sala, a posse do semeador, os projecteis no ar e o mapa servido de memoria —
  # e o jogador voltava a um sitio que ja nao era o mesmo. A arena continua a
  # correr; o que muda e que eu, durante trinta segundos, nao ando nem bato.
  #-----------------------------------------------------------------------------
  def caido?
    !@caido_ate.nil?
  end

  def cair_a_espera_de_socorro!(nome)
    # Rede a mais: se por alguma razao isto for chamado duas vezes, o relogio
    # nao recomeca e a caixa de texto nao volta a aparecer.
    return if @caido_ate
    @tonto_visto = 0.0
    @caido_ate = Time.now.to_f + AnilArenaRessurreicao::ESPERA
    @hp_meu = 0
    ($game_player.opacity = 255) rescue nil
    # ⚠️ A PARTIR DAQUI JA SE ANUNCIOU A QUEDA, E NADA A PODE DESFAZER.
    #
    # O `rescue` la em baixo apaga o `@caido_ate` e manda-me embora. Isso esta
    # certo se a queda rebentar ANTES de existir; esta errado assim que o outro
    # jogador ja me viu cair — ele fica a correr com um Max Revive na mao para
    # um sitio de onde eu ja sai, e do meu lado nao ha bambear nenhum que
    # explique porque.
    #
    # O `dizer` estava a descoberto (o `anunciar_queda!` e o `pbMessage` ao lado
    # dele ja tinham o seu `rescue`), e bastava ele para atirar a queda inteira
    # para o caminho de quem esta sozinho.
    begin
      (AnilArenaRessurreicao.anunciar_queda! rescue nil)
      (dizer(_INTL("{1} caiu! Um parceiro pode reanimá-lo.", nome)) rescue nil)
      (AnilRaidCaverna.log_sempre("caiu a espera de socorro (#{AnilArenaRessurreicao::ESPERA.round}s)") rescue nil)
      pbMessage(_INTL("{1} caiu!\nUm parceiro com um Max Revive pode reanimá-lo em {2} segundos.",
                      nome, AnilArenaRessurreicao::ESPERA.round)) rescue nil
    rescue
      nil
    end
  rescue
    @caido_ate = nil
    (AnilRaidCaverna.log_sempre("a queda a espera de socorro falhou; a cair a serio") rescue nil)
    (AnilRaidCaverna.caiu! rescue nil)
  end

  # ⚠️ O BALANCO E DESENHADO NO SPRITE, E TEM DE SER DESFEITO.
  #
  # O `angle` de um Sprite_Character nao volta ao zero sozinho: quem o poe tem
  # de o tirar. Sem isso, um jogador revivido andava o resto da sessao inclinado
  # — e a causa estaria a catorze mil linhas de distancia de onde se notava.
  # ⚠️ A MARCA DE QUEM CAIU E DO MAPA, NAO DA BATALHA. E ERA ESSE O ERRO.
  #
  # Isto tocava a animacao 13 do `PkmnAnimations` — a `Common:Confusion` da
  # batalha. Duas coisas correm mal com essa escolha, e a segunda e pior:
  #
  #   1. uma animacao de batalha e desenhada para um ecra de batalha. No mapa
  #      ela tapa o boneco inteiro — "os pintinhos enormes na cabeca".
  #
  #   2. o indice 13 e um indice como outro qualquer na oficina, e a oficina JA
  #      TEM UMA FICHA PARA ELE: `modo quem`, escala 58, `feixe_casas 6.5`,
  #      `feixe_persegue true`. Ou seja, a marca de "estou caido" estava a ser
  #      desenhada como um feixe de seis casas e meia que persegue alguem.
  #
  # O selvagem grogue ja resolve isto ha muito e resolve-o bem: usa a animacao
  # de MAPA numero 4 (`Question bubble`, da folha `Follower_Emote2`), pelo
  # `animation_id` do proprio motor. Sai do tamanho certo porque foi desenhada
  # para o mapa, e nenhuma ficha da oficina lhe toca.
  #
  # Passa a ser a mesma, com o mesmo balanco e a mesma cadencia do selvagem —
  # que e exactamente o que se pediu: "balancar igual os selvagens depois de
  # derrotados".
  TONTO_CADENCIA = 2.0    # a mesma do `marcar_interrogacao!`

  def correr_caido!
    return unless @caido_ate
    sp = sprite_de($game_player)
    if sp
      # Os mesmos dois numeros do `correr_tontos!`. Se um dia divergirem, o
      # caido volta a bambear de maneira diferente de toda a gente.
      t = Time.now.to_f * 7.0
      (sp.angle = Math.sin(t) * TONTO_BALANCO) rescue nil
    end
    agora_t = Time.now.to_f
    if (agora_t - @tonto_visto.to_f) >= TONTO_CADENCIA
      @tonto_visto = agora_t
      if ($data_animations && $data_animations[ANIM_INTERROGACAO] rescue false)
        ($game_player.animation_id = ANIM_INTERROGACAO) rescue nil
      end
    end
    return if Time.now.to_f < @caido_ate.to_f
    # O tempo acabou e ninguem veio.
    endireitar_caido!
    @caido_ate = nil
    (AnilArenaRessurreicao.anunciar_levantado! rescue nil)
    nome = (@meu.name rescue _INTL("Seu Pokémon"))
    pbMessage(_INTL("{1} desmaiou!", nome)) rescue nil
    (AnilRaidCaverna.caiu! rescue nil)
  rescue
    nil
  end

  def endireitar_caido!
    sp = sprite_de($game_player)
    (sp.angle = 0) rescue nil
  rescue
    nil
  end

  # Chamado quando o PEDIDO de um parceiro chega. So o proprio se levanta.
  def aceitar_ressurreicao!(quem, fraccao = 1.0)
    return false unless @caido_ate
    endireitar_caido!
    @caido_ate = nil
    maximo = (@meu.totalhp.to_i rescue 1)
    # Um Revive levanta com metade; um Max Revive com tudo. Nunca menos de 1,
    # senao levantava-se morto.
    @hp_meu = [(maximo * fraccao.to_f).round, 1].max
    (@meu.hp = @hp_meu) rescue nil
    escrever_vida_na_equipa!
    (AnilArenaRessurreicao.anunciar_levantado! rescue nil)
    (pbSEPlay("Pkmn heal") rescue nil)
    ($game_player.animation_id = ANIM_BRILHO) rescue nil
    quem = _INTL("Um parceiro") if quem.nil? || quem.empty?
    dizer(AnilLanRework.ui_format("{1} reanimou você!", quem)) rescue nil
    actualizar_foco!
    true
  rescue
    false
  end

  #-----------------------------------------------------------------------------
  # DO OUTRO LADO: CHEGAR-SE A UM CAIDO E CARREGAR
  #
  # ⚠️ A INTERACCAO E FEITA AQUI, E NAO PELO SISTEMA DE EVENTOS DO MAPA.
  #
  # Um jogador remoto nao e um evento: nao ha nada em que o `check_event_trigger`
  # possa bater. Encontrei no 000 um `suppress_peer_interaction!` que parecia
  # prometer um sistema de interaccao entre jogadores — mas nao e chamado de
  # lado nenhum, e portanto nao existe.
  #
  # A arena ja le o teclado a cada frame e ja sabe onde toda a gente esta.
  # Perguntar aqui e uma linha; construir um sistema de interaccao entre
  # jogadores era um projecto, e este nao e o momento.
  #-----------------------------------------------------------------------------
  def talvez_reviver!
    return unless caverna?
    # ⚠️ ANTES do `caido?`: a memoria tem de estar fresca no instante em que se
    # cai, e a partir desse instante este metodo ja nao corre.
    (AnilArenaRessurreicao.notar_companhia! rescue nil)
    return if caido?
    (AnilArenaRessurreicao.esquecer_velhos! rescue nil)
    par = (AnilArenaRessurreicao.caido_ao_alcance rescue nil)
    return unless par
    id, ficha = par
    nome = ficha[:nome].to_s
    nome = _INTL("o parceiro") if nome.empty?
    par_item = (AnilArenaRessurreicao.item_para_reviver rescue nil)
    unless par_item
      dizer(AnilLanRework.ui_format("{1} caiu — é preciso um Revive ou Max Revive.", nome)) rescue nil
      return
    end
    item_id, fraccao = par_item
    nome_item = (AnilArenaItens.nome_do_item(item_id) rescue item_id.to_s)
    # ⚠️ A TECLA DIZ-SE PELO NOME, e o nome vem do mesmo sitio que o resto do
    # painel usa. Escrever "A" a mao era mentir assim que alguem remapeasse.
    dizer(AnilLanRework.ui_format("Pressione C para usar {1} em {2}.",
                                  nome_item, nome)) rescue nil
    return unless (Input.anil_arena_orig_trigger?(Input::USE) rescue false)
    # ⚠️ O ITEM SO SE GASTA DEPOIS DE O PEDIDO SAIR, e nunca antes.
    #
    # Ao contrario, uma falha no envio comia o Max Revive e nao reanimava
    # ninguem. Assim o pior caso e o pedido chegar tarde de mais — o item
    # perde-se, mas por uma razao que se percebe.
    (AnilArenaRessurreicao.pedir_ressurreicao!(id, fraccao) rescue nil)
    ($bag.remove(item_id) rescue nil)
    (AnilArenaRessurreicao.caidos || {}).delete(id)
    dizer(AnilLanRework.ui_format("Usou {1} em {2}!", nome_item, nome)) rescue nil
  rescue
    nil
  end

  #-----------------------------------------------------------------------------
  # O RELOGIO
  #-----------------------------------------------------------------------------
  # ⚠️ O INPUT TEM DE SER LIDO ANTES DO RESTO DO JOGO.
  #
  # A tecla A alterna o seguidor e a D abre os itens-chave. Se a arena lesse o
  # input DEPOIS do `Scene_Map#update`, essas accoes ja tinham acontecido — era
  # o que se via: carregar em A guardava o Pokemon e carregar em D abria a
  # mochila, tudo a meio da luta.
  #
  # Por isso ha dois momentos: o `tick_antes!` le e consome as teclas, e o
  # gancho no `Input.trigger?` responde "nao" a quem perguntar depois. As quatro
  # teclas passam a ser da arena, e de mais ninguem, enquanto ela dura.
  def teclas_da_arena
    @teclas_ids ||= TECLAS.map { |(t, _)| (Input.const_get(t) rescue nil) }.compact
  end

  def engolir?(botao)
    return false unless ACTIVO && @activa
    teclas_da_arena.include?(botao)
  rescue
    false
  end

  def tick_antes!
    return unless ACTIVO && @activa
    return unless $scene.is_a?(Scene_Map)
    return unless $game_map && $game_player
    # ⚠️ ESTA GUARDA ERA UM `return` NO TOPO, E ISSO MATAVA O RESTO DO METODO.
    #
    # Na automatica as quatro teclas de golpe voltam a ser do jogo — isso esta
    # certo. Mas este metodo nao trata so delas: mais abaixo estao a fala com o
    # ajudante (que e a unica forma de parar o modo sem comando), a tecla da
    # bola e a apanha de tontos. Um `return` a entrada levava tudo a frente.
    #
    # Foi um `next`/`return` mal colocado do tipo que ja me custou uma ronda
    # nesta sessao: a guarda certa cobre o laco das teclas, e nao o metodo.
    TECLAS.each_with_index do |(tecla, rotulo), i|
      break if automatica?
      botao = (Input.const_get(tecla) rescue nil)
      next unless botao
      # ?? Le-se pelo caminho ORIGINAL, senao a arena ficava cega pelo seu
      # proprio filtro. Se o gancho ainda nao estiver instalado (arranque, ou
      # plugins a recarregar), cai-se no metodo normal, que nessa altura ainda
      # nao engole nada.
      lido = if Input.respond_to?(:anil_arena_orig_trigger?)
               (Input.anil_arena_orig_trigger?(botao) rescue false)
             else
               (Input.trigger?(botao) rescue false)
             end
      next unless lido
      usar_golpe!(i, rotulo)
    end
    # X (Input::B) manda o grogue embora sem gastar bola.
    if (b = tonto_a_mao)
      botao_sair = (Input::B rescue nil)
      if botao_sair
        lido = if Input.respond_to?(:anil_arena_orig_trigger?)
                 (Input.anil_arena_orig_trigger?(botao_sair) rescue false)
               else
                 (Input.trigger?(botao_sair) rescue false)
               end
        if lido
          dizer(_INTL("Você deixou {1} ir.", (b[:pkmn].speciesName rescue "")))
          soltar_tonto!(b)
          return
        end
      end
    end
    talvez_falar_com_corpo!
    talvez_falar_com_ajudante!
    return unless @activa
    botao_bola = (Input.const_get(TECLA_BOLA) rescue nil)
    if botao_bola
      correr_tecla_do_remedio!(botao_bola)
    end
  rescue => e
    log("falha no tick_antes: #{e.class}: #{e.message}")
  end

  #-----------------------------------------------------------------------------
  # O CRONOMETRO DO TICK
  #
  # ⚠️ "AS VEZES TRAVA" NAO SE RESOLVE A OLHO. MEDE-SE.
  #
  # O tick tem quarenta etapas. Um engasgo de um segundo esta numa delas, e
  # adivinhar qual e o que ja custou varias rondas — a ultima vez era o meu
  # proprio log, e eu tinha apontado para outro lado.
  #
  # Cada etapa passa a ser cronometrada. Enquanto o frame couber no tecto, isto
  # custa duas leituras do relogio por etapa e nao escreve nada. Quando um frame
  # estoira, escreve-se UMA linha com o total e com as tres etapas mais lentas —
  # e ai deixa de haver palpite nenhum.
  #
  # O tecto e generoso de proposito: 100 ms e seis frames perdidos, ja se ve, e
  # nao apanha o arranque da arena (que e lento uma vez so, e nao interessa).
  # 40 ms sao dois frames e meio perdidos — ja se sente, e foi o que sobrou
  # depois de a gravacao sair do laco. Os 100 ms de antes nao apanharam nada.
  TECTO_FRAME = 0.040

  # Sem chamadores por agora, de proposito. Para voltar a medir, embrulha-se a
  # etapa suspeita: `crono(:mover_inimigo) { mover_inimigo! }`.
  def crono(nome)
    return yield unless ACTIVO && LOG_LIGADO
    t0 = Time.now.to_f
    r = yield
    (@tempos ||= {})[nome] = Time.now.to_f - t0
    r
  end

  def fechar_crono!(t0)
    total = Time.now.to_f - t0
    if total >= TECTO_FRAME && @tempos && !@tempos.empty?
      piores = @tempos.sort_by { |_, v| -v }.first(3)
      registar("FRAME LENTO #{(total * 1000).round} ms :: " +
               piores.map { |n, v| "#{n} #{(v * 1000).round}" }.join("  "))
    end
    @tempos.clear if @tempos
  rescue
    nil
  end

  def tick!
    return unless ACTIVO && @activa
    return unless $scene.is_a?(Scene_Map)
    return unless $game_map && $game_player

    # ⚠️ O DELTA VEM DO RELOGIO, NAO DOS FRAMES.
    #
    # Mesma licao da recarga: o tick pode correr mais do que uma vez por frame, e
    # a energia escoava-se a dobrar. Mede-se quanto tempo passou mesmo.
    agora_t = Time.now.to_f
    @delta = [(agora_t - (@ultimo_tick || agora_t)), 0.1].min
    @ultimo_tick = agora_t
    crono_t0 = agora_t

    # ⚠️ O ARCO DO ITEM PRECISA DE UM RELOGIO, E O RELOGIO E ESTE.
    #
    # A caverna nao tem `update` proprio: e a arena que corre, e e ela que mede
    # o tempo que passou de verdade (ver a licao do delta, mesmo aqui em cima).
    # Dar-lhe um segundo relogio era arriscar o mesmo defeito da recarga, com o
    # arco a andar a dobrar nos frames em que o tick corre duas vezes.
    (AnilRaidCaverna.tick!(@delta) rescue nil) if caverna?

    # ⚠️ A VIDA DA ARENA E A VIDA DA EQUIPA, e nao um numero a parte.
    #
    # `@hp_meu` era so da arena: dava para levar uma sova, sair, e continuar com
    # o Pokemon intacto na equipa. Agora escreve-se de volta a cada tick — quem
    # cai aqui fica caido na equipa, como cairia numa batalha normal.
    # ⚠️ ISTO ESTAVA A CURAR O AJUDANTE A CADA FRAME, E EU TINHA-O "GUARDADO".
    #
    # A guarda que escrevi na ronda passada caiu no `usar_remedio!` — o `sub!`
    # apanhou a primeira ocorrencia e eu nao confirmei a funcao de destino. O
    # `tick!` ficou como estava, e a consequencia e grande:
    #
    # Na automatica, o `@meu` e o `@aliado[:pkmn]` sao O MESMO OBJECTO (o modo
    # entra com o primeiro da equipa e da-o ao ajudante). O `@hp_meu` nunca leva
    # dano nenhum — eu nao luto. Portanto esta linha, a 60 por segundo, escrevia
    # a vida CHEIA por cima da vida ferida do ajudante.
    #
    # Da os dois sintomas de uma vez, e por isso demorei a ligar:
    #
    #   o Pokemon "sumia"  o `@aliado[:hp]` continuava a descer (e uma conta a
    #                      parte), chegava a zero, e o `dispensar_aliado!`
    #                      tirava-o do mapa — enquanto o bicho da equipa estava
    #                      intacto. Nao morreu nem desapareceu: foi dispensado.
    #
    #   voltava com vida   porque nunca a chegou a perder de verdade.
    #   cheia
    #
    # Na automatica a vida que conta e a do ajudante, e ela ja e escrita por
    # quem trata dele (`ferir_aliado!` e `dispensar_aliado!`).
    escrever_vida_na_equipa! unless automatica?
    actualizar_foco!
    correr_estado!
    correr_estado_inimigo!
    correr_barras_de_vida!
    correr_itens!
    escalar_chefes!
    correr_caido!
    talvez_reviver!
    mover_inimigo!
    garantir_aliado!
    prender_aliado!
    mover_aliado!
    anunciar_parceiro!
    mover_parceiro!
    esquecer_parceiro!
    pensar_aliado!
    correr_armadilhas!
    correr_lancamentos!
    garantir_corpo!
    mover_corpo!
    adoptar_do_mato!
    talvez_bola_automatica!
    spawnar_do_mato!
    correr_corrida!
    correr_segurar!
    repor_energia!
    correr_adiadas!
    correr_impactos!
    correr_investida!
    correr_flashes!
    correr_derrota!
    correr_feixe_dano!
    correr_sementes!
    correr_escudo!
    correr_efeitos_do_corpo!
    correr_clone!
    correr_captura!
    correr_pocoes!
    correr_mira!
    correr_bichos_do_servidor!
    correr_tontos!
    correr_desmaios!
    correr_flutuantes!
    correr_impactos_pvp!
    correr_projecteis!
    actualizar_animacoes!
    (AnilArenaAnimador.correr!(@delta) rescue nil)
    correr_inteiras!
    (AnilArenaHabilidades.correr_voos!(@delta) rescue nil)
    (AnilArenaEvolucao.correr!(@delta) rescue nil)

    @ia_relogio -= 1
    if @ia_relogio <= 0
      @ia_relogio = IA_CADENCIA
      pensar_ia!
    end

    desenhar_hud!
    fechar_crono!(crono_t0) if LOG_LIGADO
  rescue => e
    log("falha no tick: #{e.class}: #{e.message}")
    sair!
  end

  #-----------------------------------------------------------------------------
  # O PAINEL
  #-----------------------------------------------------------------------------
  def criar_hud!
    apagar_hud!
    @vp = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @vp.z = 99998
    @hud = Sprite.new(@vp)
    @hud.bitmap = Bitmap.new(Graphics.width, Graphics.height)
    (pbSetSystemFont(@hud.bitmap) rescue nil)
    @hud_chave = nil
  rescue => e
    log("falha no hud: #{e.class}: #{e.message}")
  end

  def apagar_hud!
    largar_pocoes!
    largar_mira_e_desenho!
    (@hud.bitmap.dispose if @hud && @hud.bitmap && !@hud.bitmap.disposed?) rescue nil
    (@hud.dispose if @hud && !@hud.disposed?) rescue nil
    # Os bitmaps onde a caixa e composta antes de encolher. Sao dois (o meu e o
    # do inimigo) e vivem tanto quanto o HUD: saem com ele.
    (@caixa_tmp || {}).each_value { |bm| (bm.dispose if bm && !bm.disposed?) rescue nil }
    @caixa_tmp = nil
    (@vp.dispose if @vp && !@vp.disposed?) rescue nil
    @hud = nil
    @vp = nil
  rescue
    nil
  end

  #-----------------------------------------------------------------------------
  # A NARRACAO DE COMBATE
  #
  # ⚠️ ISTO NAO SE APAGOU, DESLIGOU-SE — E A DIFERENCA IMPORTA.
  #
  # "Pidgey! -35", "Rattata usou Tackle!", "Zubat... errou!" — numa batalha por
  # turnos isto E a batalha, porque nao ha nada a ver. Aqui ha: o golpe sai do
  # sprite, acerta no sprite, o bicho pisca a vermelho e a barra desce. O texto
  # esta a descrever, uma linha atrasado, uma coisa que o jogador acabou de ver.
  #
  # E a catorze sitios de distancia uns dos outros. Apagar as catorze chamadas
  # era mexer em catorze sitios para uma decisao que e UMA — e se um dia se
  # quiser algum de volta, era procura-los todos outra vez. Passam por aqui, e
  # a decisao fica num sitio, com o motivo escrito ao lado.
  #
  # O painel continua a servir para o que ele e bom: o que NAO se ve. "Sem
  # alcance", "recarregando 1,4s", "SHINY!", uma evolucao. Essas continuam a
  # chamar o `dizer` directamente.
  NARRAR_COMBATE = false

  def narrar(texto)
    dizer(texto) if NARRAR_COMBATE
  end

  def dizer(texto)
    @mensagem = texto.to_s
    @mensagem_ate = (Graphics.frame_count rescue 0) + 90
  end

  # Quem esta em campo e quem conta: na automatica e o ajudante, senao sou eu.
  def exp_do_hud
    pk = automatica? ? ((@aliado && @aliado[:pkmn]) rescue nil) : @meu
    return 0.0 unless pk
    (pk.exp_fraction.to_f rescue 0.0)
  rescue
    0.0
  end

  def desenhar_hud!
    return unless @hud && @hud.bitmap && !@hud.bitmap.disposed?
    # ⚠️ So se redesenha quando algo muda. Repintar 60 vezes por segundo um
    # bitmap do tamanho do ecra e a forma mais facil de matar o FPS no telemovel.
    chave = [@hp_meu, @hp_dele, bichos_vivos.length, (energia / 5).round, @estado, @a_correr,
             perto_do_corpo?, (aliado_vivo? ? @aliado[:hp] : -1), buffs_activos(@meu),
             @a_correr,
             !tonto_a_mao.nil?,
             (@prontos || []).map { |t| t.to_f > Time.now.to_f }, @mensagem,
             # Sem isto o contador de poções ficava congelado no numero que
             # tinha quando outra coisa qualquer mudou.
             # Sem isto o painel so se repintava quando outra coisa mudasse, e a
             # cadeia ficava congelada no numero que tinha nessa altura.
             (@directa ? ($PokemonGlobal.catchcombo.inspect rescue nil) : nil),
             (caverna? ? remedio_a_mao : nil),
             (caverna? ? ($bag.quantity(remedio_a_mao) rescue 0) : 0),
             # ⚠️ O QUE NAO ESTA NA CHAVE NAO SE REPINTA.
             #
             # O HUD so se redesenha quando esta lista muda — e por isso tudo o
             # que e novo no desenho tem de entrar aqui, senao fica congelado no
             # valor que tinha da ultima vez que outra coisa mexeu. Foi o que ja
             # aconteceu ao contador de pocoes e a cadeia, duas vezes.
             #
             # A experiencia entra arredondada a centesima: ela sobe a cada
             # golpe e, crua, punha o ecra inteiro a repintar-se por causa de
             # meio pixel de barra — que e exactamente o que esta chave existe
             # para evitar.
             ((exp_do_hud * 100).round),
             # E o inimigo agora tem nome, nivel e vida propria na caixa, e nao
             # so um numero de vida.
             (bicho_focado ? [(bicho_focado[:pkmn].name rescue nil),
                              (bicho_focado[:pkmn].level rescue nil),
                              bicho_focado[:hp]] : nil),
             (Graphics.frame_count rescue 0) > @mensagem_ate.to_i]
    return if chave == @hud_chave
    @hud_chave = chave

    b = @hud.bitmap
    b.clear
    branco = Color.new(255, 255, 255)
    preto  = Color.new(0, 0, 0)

    # ⚠️ AS BARRAS FINAS SAIRAM; A CAIXA DA BATALHA VOLTOU, ENCOLHIDA.
    #
    # Aqui esteve escrito que a caixa tapava o mundo e que por isso se voltava
    # as barras finas. A largura era mesmo um problema — metade do ecra — mas a
    # solucao certa era encolher, e nao trocar por desenho proprio: as barras
    # finas nao diziam quanta vida em numeros nem mostravam experiencia nenhuma.
    #
    # A 68% a caixa ocupa pouco mais de um terco da largura e cabem as duas, a
    # minha a esquerda e a do inimigo a direita, como numa batalha.
    # ⚠️ NA AUTOMATICA HA UM POKEMON EM CAMPO, E O HUD MOSTRAVA DOIS.
    #
    # As barras de cima sao as da batalha directa: a minha vida (eu sou o
    # Pokemon) e a minha energia de corrida. Na automatica eu nao sou nenhum dos
    # dois — o unico que luta e o ajudante, e a vida dele ja tem barra propria
    # tres linhas abaixo.
    #
    # O resultado era o que se ve no ecra: duas barras verdes empilhadas a
    # esquerda, como se houvesse dois Pokemon meus, e uma delas a nao
    # corresponder a nada que esteja a acontecer.
    #
    # Aqui a barra de cima passa a ser a DELE, no sitio de destaque, e a de
    # energia sai — ela mede o folego de corrida do Pokemon do jogador, que
    # neste modo nao existe.
    cx_l = largura_da_caixa
    cx_a = altura_da_caixa
    if automatica?
      if aliado_vivo?
        caixa_pequena!(b, 2, 2, @aliado[:pkmn], @aliado[:hp], @aliado[:hp_max], false, true)
      end
    else
      caixa_pequena!(b, 2, 2, @meu, @hp_meu, (@meu.totalhp rescue 1), false, true)
      # ⚠️ A BARRA DA ENERGIA SAIU, E NAO SE PERDEU NADA COM ISSO.
      #
      # Ela mostrava o folego de corrida entre as duas caixas de vida — e a
      # mesma energia JA esta desenhada dentro do botao "W correr", em baixo a
      # direita, onde ela interessa: ao pe da tecla que a gasta.
      #
      # Eram duas leituras do mesmo numero em sitios diferentes do ecra, e a de
      # cima estava no pior sitio possivel — entre a minha vida e a do
      # ajudante, a separar as duas coisas que se querem comparar de relance.
    end
    # O texto vive entre as duas caixas; comecava em 176 e agora a caixa da
    # esquerda vai ate `cx_l`.
    txt_x = cx_l + 6
    txt_w = [Graphics.width - cx_l - cx_l - 12, 80].max
    activos = buffs_activos(@meu)
    unless activos.empty?
      texto_b = "▲ " + activos.join(" ")
      b.font.color = preto
      b.draw_text(txt_x + 1, 5, txt_w, 22, texto_b)
      b.font.color = Color.new(255, 210, 90)
      b.draw_text(txt_x, 4, txt_w, 22, texto_b)
    end
    # Na automatica ele ja esta em cima, no lugar principal: repetir aqui era a
    # mesma vida desenhada duas vezes.
    # ⚠️ O AJUDANTE LUTA COMO EU, E PASSA A SER MOSTRADO COMO EU.
    #
    # Ele tinha uma barra fina e o nome escrito ao lado. Isso dizia "quanta
    # vida" mas nao dizia quanta EM NUMEROS, nem o nivel, nem a experiencia — e
    # ele leva dano, ganha niveis e evolui como o meu. Nao havia razao para ele
    # ter meia caixa; so nunca a tinha tido.
    #
    # Fica por baixo da minha, na mesma coluna, na mesma escala. A ordem no
    # ecra passa a dizer o que a batalha diz: o de cima sou eu, o de baixo e o
    # meu parceiro.
    if aliado_vivo? && !automatica?
      # Encostada a minha: sem a barra pelo meio, as duas vidas leem-se como um
      # par. Dois pixeis de folga chegam para nao parecerem uma so caixa.
      caixa_pequena!(b, 2, cx_a + 2, @aliado[:pkmn],
                     @aliado[:hp], @aliado[:hp_max], false, true)
    end
    if (e = estado_activo)
      b.font.color = preto
      b.draw_text(txt_x + 1, 15, txt_w, 24, nome_do_estado(e))
      c = ESTADO_COR[e]
      b.font.color = Color.new(c[0], c[1], c[2])
      b.draw_text(txt_x, 14, txt_w, 24, nome_do_estado(e))
    end
    # ⚠️ O INIMIGO TAMBEM TEM CAIXA, E E A `_foe` — a mesma da batalha, sem
    # numeros, que e como o jogo sempre mostrou a vida de quem esta do outro
    # lado. Estava aqui uma barra vermelha desenhada a mao.
    # ⚠️ A CAIXA DO INIMIGO SAIU: A VIDA DELE ESTA AGORA POR CIMA DELE.
    #
    # Uma caixa no canto obriga a olhar para dois sitios ao mesmo tempo — o
    # bicho, para nao levar, e o canto, para saber quanto lhe falta. E numa
    # luta com nove selvagens a caixa so falava de um deles.
    #
    # A barra em cima da cabeca resolve as duas coisas: esta onde os olhos ja
    # estao, e ha uma por cada inimigo. Ver o `correr_barras_de_vida!`.
    #
    # No PVP a caixa fica: la e um adversario so, ele nao e um `bicho` desta
    # lista, e o `@hp_dele` e o unico sitio onde a vida dele existe.
    if pvp?
      barra(b, Graphics.width - 168, 8, @hp_dele, (@hp_dele_max || 1), Color.new(230, 90, 90))
    end
    if !pvp? && bichos.length > 1
      b.font.color = preto
      b.draw_text(Graphics.width - 167, cx_a - 6, 160, 22, _INTL("restam {1}", bichos_vivos.length), 2)
      b.font.color = branco
      b.draw_text(Graphics.width - 168, cx_a - 7, 160, 22, _INTL("restam {1}", bichos_vivos.length), 2)
    end
    # ⚠️ NA MASMORRA A POCAO VALE SEMPRE, E A DICA DELA NAO APARECIA.
    #
    # Esta linha e do tempo em que a dica era "Q: capturar" — e capturar so faz
    # sentido a cacar ou num combate directo. Na masmorra a mesma tecla e a
    # pocao, que se usa a qualquer momento, e sobretudo quando NAO se esta em
    # combate: e entre lutas que se recupera. O portao estava a esconder
    # exactamente a altura em que ela era precisa.
    desenhar_cadeia!(b, branco, preto) if @directa
    if caverna? || @caca || @directa
      desenhar_dicas!(b, branco, preto)
    end

    desenhar_botoes!(b, branco, preto)

    if @mensagem && (Graphics.frame_count rescue 0) <= @mensagem_ate.to_i
      b.font.color = preto
      b.draw_text(1, 41, Graphics.width, 28, @mensagem, 1)
      b.font.color = branco
      b.draw_text(0, 40, Graphics.width, 28, @mensagem, 1)
    end
  rescue => e
    log("falha a desenhar: #{e.class}: #{e.message}")
  end

  #-----------------------------------------------------------------------------
  # OS BOTOES DOS GOLPES
  #
  # ⚠️ SAO OS MESMOS BOTOES DA BATALHA, e nao um desenho novo.
  #
  # O `cursor_fight.png` que a batalha usa tem uma linha por TIPO — e por isso
  # que na batalha o botao do Thunder Shock e amarelo e o do Razor Leaf e verde.
  # Aqui usa-se a mesma folha, o mesmo indice (`icon_position` do tipo), so que
  # encolhida para caber num canto: quem joga reconhece a cor de longe e nao
  # precisa de ler.
  #
  # Encolher e `stretch_blt`, que faz o motor esticar por nos — desenhar botao a
  # botao a mao seria o mesmo trabalho com pior resultado.
  BOTAO_W = 192          # tamanho na folha original
  BOTAO_H = 46
  BOTAO_ESCALA = 0.82    # legivel sem tapar o mapa
  # ⚠️ ESCOLHI 38 PIXEIS E "Shift" NAO CABE LA.
  #
  # As tres primeiras teclas sao uma letra (A, S, D) e cabiam de sobra. A quarta
  # e "Shift", com cinco letras — transbordava a calha e ia direita ao nome do
  # golpe. No ecra lia-se "ShifSwords Dance", que e o mesmo defeito que eu tinha
  # acabado de corrigir, agora por a calha ser pequena em vez de nao existir.
  #
  # Um numero escolhido a olho volta a partir-se no dia em que alguem remapear
  # uma tecla. A calha passa a ser medida no proprio texto, e o valor fixo fica
  # so como piso para as teclas de uma letra nao ficarem coladas a borda.
  GOLPE_GUTTER = 38

  def bitmap_dos_botoes
    return @bmp_botoes if @bmp_botoes && !(@bmp_botoes.disposed? rescue true)
    @bmp_botoes = (AnimatedBitmap.new("Graphics/UI/Battle/cursor_fight").deanimate rescue nil)
  rescue
    nil
  end

  # ⚠️ UM ICONE DIZ O QUE UMA LETRA SO PROMETE.
  #
  # "Q: bola" obriga a ler; uma Poke Ball desenhada ao lado do Q le-se de
  # relance, que e o que uma dica no canto do ecra tem de ser.
  # ⚠️ UM ICONE DE POKE BALL ONDE A TECLA CURA E UMA MENTIRA DESENHADA.
  #
  # Dentro da caverna o Q nao captura — usa uma pocao. Deixar la a bola era pior
  # do que nao ter icone nenhum: quem olha de relance ve "capturar" e nao chega
  # a experimentar a unica tecla que o pode salvar a meio de uma luta.
  #
  # O icone e o do PROPRIO item que vai ser usado — a Potion ou a Max Potion,
  # conforme a que esta na mochila — e ao lado vai quantas restam. Sao as duas
  # coisas que se precisa de saber sem parar: que tecla, e se ainda ha.
  #-----------------------------------------------------------------------------
  # O LEQUE DAS POCOES
  #
  # ⚠️ UM NUMERO DIZ QUANTAS HA; UM LEQUE DIZ O QUE HA.
  #
  # O "Q: pocao x2" respondia a pergunta errada. Com cinco tipos de pocao na
  # mochila, o que se precisa de saber a meio de uma luta nao e quantas restam —
  # e QUAL e que vai sair, e se ha melhor atras dela. Um numero nao diz nem uma
  # coisa nem outra.
  #
  # A da frente, grande e a balancar, e a que vai ser usada. As de tras, mais
  # pequenas e mais apagadas, sao as outras que ha — em leque, para se ver de
  # relance que ha mais de uma sem se ter de ler nada.
  #-----------------------------------------------------------------------------
  # ⚠️ O LEQUE NAO E UMA ESCADA A SUBIR — E UMAS ENCOSTADAS AS OUTRAS.
  #
  # A primeira versao mandava as de tras para cima e para a direita, cada vez
  # mais pequenas: lia-se como uma lista em perspectiva, nao como um punhado de
  # frascos na mao. O desenho que o utilizador mandou e outra coisa — tres
  # frascos lado a lado, encostados, quase do mesmo tamanho, cada um um bocado
  # mais atras e um bocado torto.
  #
  # E por isso que as de tras sao quase tao grandes como a da frente: num
  # punhado, o que esta atras nao encolhe, so se esconde. A inclinacao e o que
  # tira aquilo de parecer um icone de inventario alinhado a regua.
  POCAO_GRANDE  = 46      # pixeis do icone da frente
  POCAO_PEQUENA = 40      # pixeis dos de tras: quase igual, so um pouco atras
  POCAO_LEQUE_X = 27      # quanto cada uma de tras se afasta para o lado
  POCAO_LEQUE_Y = 4       # e quanto desce, para nao ficarem em linha
  POCAO_ANGULO  = 9       # graus de inclinacao por frasco
  POCAO_ATRAS   = 3       # quantas se veem atras da escolhida
  POCAO_BALANCO = 3.0     # pixeis do sobe-e-desce
  POCAO_RITMO   = 2.4     # radianos por segundo

  # As que ha mesmo na mochila, pela ordem da tabela — da mais fraca para a mais
  # forte, que e a ordem em que o leque faz sentido.
  def remedios_na_mochila
    fora = []
    REMEDIOS.each do |(id, cura)|
      next unless (GameData::Item.exists?(id) rescue false)
      next unless ($bag.has?(id) rescue false)
      fora << [id, cura]
    end
    fora
  rescue
    []
  end

  def viewport_das_pocoes
    return @vp_pocoes if @vp_pocoes && !(@vp_pocoes.disposed? rescue true)
    @vp_pocoes = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @vp_pocoes.z = 99999
    @vp_pocoes
  rescue
    nil
  end

  # ⚠️ O MESMO LEQUE PARA AS DUAS COISAS.
  #
  # Na masmorra o Q e a pocao; fora dela e a bola. Sao a mesma pergunta — "o que
  # e que esta tecla vai gastar, e o que mais ha?" — e por isso sao o mesmo
  # desenho. Um segundo leque, com o seu proprio sobe-e-desce e a sua propria
  # lista, seria a mesma coisa escrita duas vezes e a divergir na terceira
  # afinacao.
  def leque_agora
    return nil unless @activa
    if caverna?
      lista = remedios_na_mochila
      return nil if lista.empty?
      i = indice_do_remedio(lista)
      return [lista[i][0]] + lista.rotate(i + 1).first(POCAO_ATRAS).map { |e| e[0] }
    end
    # Fora da masmorra so faz sentido com o Q a servir para atirar.
    return nil unless @caca || @directa
    lista = bolas_na_mochila
    return nil if lista.empty?
    esc = bola_escolhida || bola_automatica
    i = (lista.index(esc) || 0)
    [lista[i]] + lista.rotate(i + 1).first(POCAO_ATRAS)
  rescue
    nil
  end

  def correr_pocoes!
    ordem = leque_agora
    if ordem.nil? || ordem.empty?
      largar_pocoes! if @sp_pocoes
      return
    end
    vp = viewport_das_pocoes
    return unless vp
    @sp_pocoes ||= []
    # Com os icones a 46 px, a base de antes cortava-os no fundo do ecra.
    base_x = 14
    base_y = Graphics.height - 40
    t = (Graphics.frame_count rescue 0) / 60.0
    # ⚠️ Desenha-se de TRAS para a frente: o ultimo a ser criado fica por cima,
    # e quem tem de ficar por cima e a escolhida.
    (ordem.length - 1).downto(0) do |n|
      id = ordem[n]
      next unless id
      sp = (@sp_pocoes[n] ||= Sprite.new(vp))
      bmp = bitmap_da_pocao(id)
      next unless bmp
      sp.bitmap = bmp
      lado = (n.zero? ? POCAO_GRANDE : POCAO_PEQUENA)
      sp.zoom_x = lado.to_f / [bmp.width, 1].max
      sp.zoom_y = lado.to_f / [bmp.height, 1].max
      sp.ox = bmp.width / 2
      sp.oy = bmp.height / 2
      # Encostadas para o lado, a descer um bocadinho e cada vez mais tortas.
      sp.x = base_x + 30 + (n * POCAO_LEQUE_X)
      sp.y = base_y + 6 + (n * POCAO_LEQUE_Y)
      sp.angle = -(n * POCAO_ANGULO)
      # So a da frente e que respira. As de tras a mexer tambem seriam ruido.
      sp.y -= (Math.sin(t * POCAO_RITMO) * POCAO_BALANCO).round if n.zero?
      # Quase opacas: num punhado, o que esta atras esta tapado, nao apagado.
      sp.opacity = (n.zero? ? 255 : [235 - (n * 25), 150].max)
      sp.visible = true
    end
    # Sobram sprites de quando havia mais tipos na mochila.
    (ordem.length...@sp_pocoes.length).each do |n|
      sp = @sp_pocoes[n]
      sp.visible = false if sp && !(sp.disposed? rescue true)
    end
  rescue => e
    log("falha nas pocoes: #{e.class}: #{e.message}")
  end

  #-----------------------------------------------------------------------------
  # A MIRA
  #
  # ⚠️ A REGRA DE ALVO E BOA, MAS NAO SE VE.
  #
  # O golpe vai sempre ao mais proximo. A regra e simples de dizer e impossivel
  # de ler a meio de uma luta com cinco bichos a mexer: dois quase a mesma
  # distancia trocam de lugar sem aviso, e o golpe sai para o que nao se
  # esperava. Nao e a regra que esta errada — e ela ser invisivel.
  #
  # A mira responde a pergunta antes de se carregar no botao. Fica a 50% para
  # nao tapar o boneco, e pulsa devagar porque uma coisa parada no meio de um
  # combate a mexer desaparece da vista.
  #-----------------------------------------------------------------------------
  MIRA_LADO      = 44    # pixeis do desenho
  MIRA_BRACO     = 13    # comprimento de cada canto
  MIRA_GROSSO    = 3     # espessura do traco
  MIRA_OPACIDADE = 85    # mais discreta do que os 50% da primeira tentativa
  MIRA_PISCA     = 38    # quanto sobe e desce a opacidade
  MIRA_RITMO     = 4.2   # batidas por segundo do pulsar
  MIRA_RESPIRA   = 0.12  # quanto o tamanho abre e fecha
  MIRA_COR       = Color.new(235, 45, 45, 255)

  # Quatro cantos e um ponto ao meio. Feito a mao com rectangulos: nao depende
  # de folha nenhuma e nao ha nada para ir buscar ao disco.
  def bitmap_da_mira
    return @bmp_mira if @bmp_mira && !(@bmp_mira.disposed? rescue true)
    l = MIRA_LADO
    b = MIRA_BRACO
    bmp = Bitmap.new(l, l)
    # Um contorno escuro por baixo do branco: sobre um boneco claro, branco puro
    # desaparece.
    camadas = [[Color.new(0, 0, 0, 130), MIRA_GROSSO + 2],
               [MIRA_COR, MIRA_GROSSO]]
    camadas.each do |cor, esp|
      cantos = [[0, 0, 1, 1], [l - esp, 0, -1, 1],
                [0, l - esp, 1, -1], [l - esp, l - esp, -1, -1]]
      cantos.each do |x, y, sx, sy|
        bx = (sx > 0) ? x : (x + esp - b)
        by = (sy > 0) ? y : (y + esp - b)
        bmp.fill_rect(bx, y, b, esp, cor)
        bmp.fill_rect(x, by, esp, b, cor)
      end
    end
    bmp.fill_rect((l / 2) - 1, (l / 2) - 1, 3, 3, MIRA_COR)
    @bmp_mira = bmp
  rescue
    nil
  end

  def correr_mira!
    ev = (@activa ? (evento_inimigo rescue nil) : nil)
    if ev.nil?
      largar_mira!
      return
    end
    vp = viewport_das_animacoes
    return unless vp
    bmp = bitmap_da_mira
    return unless bmp
    sp = (@sp_mira ||= Sprite.new(vp))
    sp.bitmap = bmp
    sp.ox = bmp.width / 2
    sp.oy = bmp.height / 2
    # No centro do boneco, pela mesma medida das ancoras dos golpes: a mira tem
    # de marcar exactamente o ponto onde o golpe vai bater.
    cx, cy = centro_do_boneco(ev)
    sp.x = cx
    sp.y = cy
    t = (Graphics.frame_count rescue 0) / 60.0
    onda = Math.sin(t * MIRA_RITMO)
    # ⚠️ O TAMANHO A MEXER LIA-SE COMO A MIRA A MEXER.
    #
    # Um zoom em volta do `ox/oy` nao desloca nada — a conta esta certa. Mas o
    # que se ve e o contorno a afastar-se e a aproximar-se do centro, e o olho
    # nao distingue isso de a propria mira andar. Junto com o desvio de posicao
    # que havia, dava a "orbita".
    #
    # O piscar sozinho chega para ela nao desaparecer no meio do combate, e nao
    # tem como ser confundido com movimento.
    sp.zoom_x = 1.0
    sp.zoom_y = 1.0
    # Pisca em volta dos 50%, sem nunca apagar de todo — se apagasse, havia
    # frames em que a pergunta "quem vai levar?" ficava sem resposta.
    sp.opacity = (MIRA_OPACIDADE + (onda * MIRA_PISCA)).round
    sp.z = 1
    sp.visible = true
  rescue => e
    log("falha na mira: #{e.class}: #{e.message}")
  end

  def largar_mira!
    (@sp_mira.dispose rescue nil) if @sp_mira && !(@sp_mira.disposed? rescue true)
    @sp_mira = nil
  rescue
    nil
  end

  def largar_mira_e_desenho!
    largar_mira!
    (@bmp_mira.dispose rescue nil) if @bmp_mira && !(@bmp_mira.disposed? rescue true)
    @bmp_mira = nil
  rescue
    nil
  end

  def bitmap_da_pocao(id)
    @bmp_pocoes ||= {}
    return @bmp_pocoes[id] if @bmp_pocoes.key?(id)
    bmp = (RPG::Cache.load_bitmap("Graphics/Items/", id.to_s) rescue nil)
    bmp ||= (pbGetItemIcon(id) rescue nil)
    @bmp_pocoes[id] = bmp
  rescue
    nil
  end

  def largar_pocoes!
    (@sp_pocoes || []).each { |sp| (sp.dispose rescue nil) if sp && !(sp.disposed? rescue true) }
    @sp_pocoes = nil
    (@vp_pocoes.dispose rescue nil) if @vp_pocoes && !(@vp_pocoes.disposed? rescue true)
    @vp_pocoes = nil
  rescue
    nil
  end

  # ⚠️ A ESCOLHA GUARDA-SE PELO ITEM E NAO PELA POSICAO.
  #
  # Gastar a ultima Potion muda a lista toda de sitio. Guardando o indice, quem
  # tinha escolhido a Hyper passava a ter escolhida outra coisa sem ter tocado
  # em nada. Guarda-se QUAL, e se ela acabar volta-se a escolha automatica.
  def indice_do_remedio(lista)
    i = lista.index { |(id, _c)| id == @remedio_escolhido }
    return i if i
    @remedio_escolhido = nil
    i = lista.index { |(id, _c)| id == remedio_automatico }
    i || 0
  rescue
    0
  end

  def rodar_remedio!
    lista = remedios_na_mochila
    return if lista.length < 2
    i = (indice_do_remedio(lista) + 1) % lista.length
    @remedio_escolhido = lista[i][0]
    (pbSEPlay("GUI sel cursor", 70) rescue nil)
    dizer((GameData::Item.get(@remedio_escolhido).name rescue "?"))
  rescue
    nil
  end

  def icone_do_remedio
    id = remedio_a_mao
    return [nil, 0] unless id
    n = ($bag.quantity(id) rescue 0)
    bmp = (RPG::Cache.load_bitmap("Graphics/Items/", id.to_s) rescue nil)
    bmp ||= (pbGetItemIcon(id) rescue nil)
    [bmp, n]
  rescue
    [nil, 0]
  end

  # A primeira que chegue para encher, tal como o `usar_remedio!` escolhe.
  def remedio_a_mao
    return @remedio_escolhido if @remedio_escolhido &&
                                 ($bag.has?(@remedio_escolhido) rescue false)
    remedio_automatico
  end

  def remedio_automatico
    return nil unless @meu
    falta = (@meu.totalhp.to_i rescue 1) - @hp_meu.to_i
    escolhido = nil
    REMEDIOS.each do |(id, cura)|
      next unless (GameData::Item.exists?(id) rescue false)
      next unless ($bag.has?(id) rescue false)
      escolhido = id
      break if (cura ? cura : 99_999) >= falta
    end
    escolhido
  rescue
    nil
  end

  # ⚠️ A CADEIA TEM DE ESTAR NO PAINEL DA ARENA, E NAO SO NO DO JOGO.
  #
  # A linha "Cadeia NN" vive na HUD do multijogador, que se ve com o F7. Mas
  # durante a batalha directa o ecra e o da arena, e quem esta a cacar precisa
  # de saber duas coisas sem largar as teclas: se a caca esta a contar, e em
  # quanto vai. Obrigar a abrir um menu para isso e obrigar a parar de jogar
  # exactamente no modo que nao pode parar.
  #
  # Fica em cima, a esquerda, por baixo das barras de vida — e so na directa,
  # que e onde a cadeia se mexe.
  def desenhar_cadeia!(b, branco, preto)
    c = ($PokemonGlobal.catchcombo rescue nil)
    return unless c.is_a?(Array) && c[0].to_i > 0
    esp = c[1]
    n = cadeia_agora(esp)
    nome = (GameData::Species.get(esp).name rescue esp.to_s)
    texto = format("Cadeia %02d  %s", n, nome)
    texto += "  (cheia)" if n >= CADEIA_CHEIA
    tamanho = b.font.size
    b.font.size = 18
    b.font.color = preto
    b.draw_text(9, 57, 300, 24, texto)
    b.font.color = (n >= CADEIA_CHEIA) ? Color.new(255, 205, 40) : Color.new(110, 235, 130)
    b.draw_text(8, 56, 300, 24, texto)
    b.font.size = tamanho
    b.font.color = branco
  rescue
    nil
  end

  def desenhar_dicas!(b, branco, preto)
    y = Graphics.height - 30
    x = 8
    if caverna?
      # ⚠️ O DESENHO DAS POCOES NAO E DESTE BITMAP, E E DE PROPOSITO.
      #
      # Este bitmap so se repinta quando alguma coisa muda — e a nota la em cima
      # explica porque: repintar um bitmap do tamanho do ecra sessenta vezes por
      # segundo e a maneira mais facil de matar o FPS num telemovel. Mas o leque
      # balanca, e balancar e mudar TODOS os frames.
      #
      # Por isso o leque sao sprites proprios (ver `correr_pocoes!`): balancar
      # passa a ser escrever um `y`, e nao repintar meio ecra. Aqui fica so a
      # letra, que nao mexe.
      b.font.bold = true
      b.font.color = preto
      b.draw_text(x + 1, y + 1, 40, 24, "Q")
      b.font.color = Color.new(120, 240, 130)
      b.draw_text(x, y, 40, 24, "Q")
      b.font.bold = false
      b.font.color = branco
      return
    end
    # ⚠️ O LEQUE JA DIZ QUAL E A BOLA — o texto passou a repetir-se.
    #
    # Fora da masmorra havia um icone de Pokebola e "Q: capturar". Agora ha um
    # punhado de bolas desenhado ao lado, com a escolhida a frente: o icone
    # fixo dizia menos e ocupava o mesmo sitio. Fica so a letra, como na
    # masmorra, e as duas telas passam a ler-se da mesma maneira.
    b.font.bold = true
    b.font.color = preto
    b.draw_text(x + 1, y + 1, 40, 24, "Q")
    b.font.color = Color.new(120, 240, 130)
    b.draw_text(x, y, 40, 24, "Q")
    b.font.bold = false
    b.font.color = branco

    return unless tonto_a_mao
    x += 108
    # Um X desenhado: duas barras cruzadas dizem "nao" sem palavra nenhuma.
    vermelho = Color.new(220, 70, 70)
    6.times do |i|
      b.fill_rect(x + 3 + i, y + 5 + i, 3, 2, vermelho)
      b.fill_rect(x + 3 + i, y + 16 - i, 3, 2, vermelho)
    end
    b.font.color = preto
    b.draw_text(x + 17, y + 1, 130, 24, _INTL("X: deixar ir"))
    b.font.color = branco
    b.draw_text(x + 16, y, 130, 24, _INTL("X: deixar ir"))
  rescue
    nil
  end

  #-----------------------------------------------------------------------------
  # O BOTAO DE CORRER
  #
  # ⚠️ DUPLO-TOQUE E UM GESTO DE TECLADO.
  #
  # No teclado bate-se duas vezes na seta sem pensar. Num ecra tactil, com o
  # dedo por cima de um botao desenhado, esse gesto e desconfortavel e falha
  # metade das vezes — a segunda batida cai fora do sitio. Um botao de manter
  # premido resolve, e nao tira nada a quem joga no teclado: o duplo-toque
  # continua a funcionar.
  #
  # ⚠️ E ELE E TOCADO PELO RATO, e nao por uma tecla.
  #
  # O JoiPlay entrega o toque como posicao de rato (ja calibrada pelo motor —
  # ver o `Input.mouse_x`), portanto o botao e uma area do ecra: se o dedo esta
  # em cima dela e carregado, corre-se. E o mesmo caminho que o menu tactil do
  # jogo usa.
  CORRER_L = 58
  CORRER_A = 22

  # ⚠️ A TECLA Z JA ESTA OCUPADA — E NAO POR MIM.
  #
  # No RGSS as letras nao sao os nomes das constantes: o Z do teclado E o
  # `Input::C` (o "confirmar"), que aqui e o que fala com o treinador para
  # encerrar a batalha. Dar-lhe tambem a corrida punha as duas coisas a acontecer
  # com a mesma tecla, e a que encerra a luta nao pode ser tocada por engano.
  #
  # O W (`Input::R`) esta livre, fica ao lado do Q da bola, e o botao no ecra
  # continua a funcionar para quem joga com o dedo.
  TECLA_CORRER = :R
  ROTULO_CORRER = "W"

  def caixa_do_correr
    larg = (BOTAO_W * BOTAO_ESCALA).round
    alt  = (BOTAO_H * BOTAO_ESCALA).round
    # Encostado a direita, mesmo por cima da coluna dos golpes — que agora tem
    # quatro botoes de altura em vez de dois.
    x = Graphics.width - CORRER_L
    y = Graphics.height - (alt * 4) - 6 - CORRER_A - 3
    [x, y, CORRER_L, CORRER_A]
  rescue
    [0, 0, 0, 0]
  end

  def tecla_do_correr?
    botao = (Input.const_get(TECLA_CORRER) rescue nil)
    return false unless botao
    (Input.anil_arena_orig_press?(botao) rescue (Input.press?(botao) rescue false))
  rescue
    false
  end

  def dedo_no_correr?
    return false unless @activa
    x, y, l, a = caixa_do_correr
    return false if l <= 0
    botao = (Input::MOUSELEFT rescue 18)
    return false unless (Input.press?(botao) rescue false)
    mx = (Input.mouse_x rescue -1)
    my = (Input.mouse_y rescue -1)
    return false if mx < 0 || my < 0
    mx >= x && mx <= (x + l) && my >= y && my <= (y + a)
  rescue
    false
  end

  def desenhar_correr!(b, branco, preto)
    # O W acelera o POKEMON, e na automatica eu nao sou ele — ando ao meu passo
    # e a energia que a barra mostra nem sequer e minha.
    return if automatica?
    x, y, l, a = caixa_do_correr
    return if l <= 0
    activo = @a_correr
    b.fill_rect(x - 1, y - 1, l + 2, a + 2, Color.new(0, 0, 0, 180))
    b.fill_rect(x, y, l, a, activo ? Color.new(70, 130, 200, 230) : Color.new(50, 50, 60, 210))
    # A barra de dentro mostra quanta energia resta para correr.
    cheio = ((l - 4) * [[energia / ENERGIA_MAX, 0.0].max, 1.0].min).round
    b.fill_rect(x + 2, y + a - 5, cheio, 3, Color.new(90, 200, 255))
    b.font.color = preto
    b.draw_text(x + 1, y + 1, l, a - 4, ROTULO_CORRER + _INTL(" correr"), 1)
    b.font.color = activo ? Color.new(200, 240, 255) : branco
    b.draw_text(x, y, l, a - 4, ROTULO_CORRER + _INTL(" correr"), 1)
  rescue
    nil
  end

  def desenhar_botoes!(b, branco, preto)
    # Na automatica as quatro teclas nao fazem nada (ver o `tick_antes!`).
    # Desenhar botoes que nao respondem e pior do que nao ter botoes: convida a
    # carregar neles e a achar que o jogo esta partido.
    return if automatica?
    desenhar_correr!(b, branco, preto)
    folha = bitmap_dos_botoes
    larg = (BOTAO_W * BOTAO_ESCALA).round
    alt  = (BOTAO_H * BOTAO_ESCALA).round
    # ⚠️ UMA COLUNA, E NAO DUAS.
    #
    # Em dois por dois os botoes ocupavam 314 px de largura num ecra de 512 —
    # dois tercos da base do ecra, e e na base que esta o chao por onde se anda.
    # Em coluna ocupam 157: a mesma informacao, metade do mapa tapado.
    #
    # Em altura passam de 76 para 152 px, mas encostados a direita — e a coluna
    # da direita e a que menos importa numa luta em que o jogador esta quase
    # sempre ao centro.
    # ⚠️ Encostados a direita, sem margem: o botao tem a ponta triangular desse
    # lado, e essa ponta foi desenhada para encaixar na borda do ecra. Com seis
    # pixeis de folga ficava uma tira de mapa entre a ponta e a borda — e o que
    # se via era a ponta a apontar para o nada.
    base_x = Graphics.width - larg
    base_y = Graphics.height - (alt * 4) - 6

    # A calha e a do rotulo MAIS LARGO, para as quatro ficarem alinhadas: uma
    # calha por botao dava os nomes a comecar em sitios diferentes.
    calha = GOLPE_GUTTER
    TECLAS.each do |(_, rot)|
      l = ((b.text_size(rot.to_s).width rescue 0) + 16)
      calha = l if l > calha
    end
    calha = (larg / 2) if calha > (larg / 2)

    TECLAS.each_with_index do |(_, rotulo), i|
      mv = (@meu.moves[i] rescue nil)
      tem = (mv && mv.id) ? true : false
      nome = tem ? (GameData::Move.get(mv.id).name rescue "-") : "-"
      pronto = ((@prontos || [])[i].to_f <= Time.now.to_f)
      x = base_x
      y = base_y + (i * alt)

      if folha && tem
        # A linha da folha e a do TIPO do golpe — a mesma conta da batalha.
        linha = (GameData::Type.get(GameData::Move.get(mv.id).type).icon_position rescue 0)
        # ⚠️ A SEGUNDA COLUNA DA FOLHA E QUASE VAZIA, E ERA ISSO O "SOME A HUD".
        #
        # O desenho usava a coluna 0 para pronto e a coluna 1 para a recarga. A
        # coluna 1 da folha nao tem o botao desenhado como deve ser — o que se
        # via era o botao a DESAPARECER assim que o golpe era usado, e a voltar
        # sozinho uns segundos depois. Um botao que some le-se como um golpe que
        # se perdeu, e nao como um golpe a arrefecer.
        #
        # Usa-se sempre a coluna do botao a serio. A indisponibilidade passa a
        # ser dita por cima: um veu cinzento que lava a cor (fica a parecer
        # preto e branco) e um escurecimento por cima dele. O botao continua la,
        # com o nome e a tecla legiveis — so que apagado.
        origem = Rect.new(0, linha * BOTAO_H, BOTAO_W, BOTAO_H)
        b.stretch_blt(Rect.new(x, y, larg, alt), folha, origem)
        unless pronto
          b.fill_rect(x, y, larg, alt, Color.new(130, 130, 130, 150))
          b.fill_rect(x, y, larg, alt, Color.new(0, 0, 0, 90))
        end
      else
        b.fill_rect(x, y, larg, alt, Color.new(40, 40, 40, 180))
      end

      # ⚠️ O NOME CENTRAVA-SE NO BOTAO INTEIRO, E A TECLA ESTAVA POR BAIXO DELE.
      #
      # A tecla e desenhada encostada a esquerda; o nome era centrado em
      # `larg - 2`, ou seja, no botao TODO — incluindo o pedaco onde a tecla ja
      # estava. Com um rotulo de duas letras e um nome comprido, os dois
      # encontravam-se: via-se "ShSweet Scent", com o S do nome por cima do
      # rotulo.
      #
      # O nome passa a centrar-se no espaco QUE SOBRA depois da tecla. Fica
      # centrado — que e o que se quer — mas centrado no sitio dele, e nunca
      # mais pode encavalitar-se no rotulo por mais comprido que seja.
      nx = x + calha
      nl = larg - calha - 6
      b.font.color = preto
      b.draw_text(x + 9, y + 5, calha - 4, alt - 6, rotulo)
      b.draw_text(nx + 1, y + 5, nl, alt - 6, nome, 1)
      b.font.color = pronto ? branco : Color.new(170, 170, 170)
      b.draw_text(x + 8, y + 4, calha - 4, alt - 6, rotulo)
      b.draw_text(nx, y + 4, nl, alt - 6, nome, 1)
    end
  rescue => e
    log("falha a desenhar botoes: #{e.class}: #{e.message}")
  end

  #-----------------------------------------------------------------------------
  # A CAIXA DE DADOS
  #
  # ⚠️ NAO SE DESENHA UMA BARRA DE VIDA QUANDO O JOGO JA TEM UMA.
  #
  # As minhas barras eram dois rectangulos e um contorno preto: legiveis, mas de
  # outro jogo. A batalha usa a `databox_normal.png`, a `overlay_hp.png` (tres
  # barras empilhadas — verde, amarela, vermelha) e a `icon_numbers.png` para os
  # digitos, e as posicoes exactas estao no `Battle::Scene::PokemonDataBox`:
  # a barra em (+102, +40), os numeros em (+80, +52), o nome em (+8, +12), o
  # nivel em (+142, +12).
  #
  # Copiar essas coordenadas e mais honesto do que inventar as minhas: quem joga
  # ve a mesma caixa que ve na batalha, porque E a mesma caixa.
  # ⚠️ FALTAVA O `@spriteBaseX`, E ERA ELE QUE PUNHA A BARRA EM CIMA DO TEXTO.
  #
  # Eu li as coordenadas do `PokemonDataBox` e copiei os numeros — mas copiei so
  # metade de cada um. No motor eles sao assim:
  #
  #     @hpBar.x     = value + @spriteBaseX + 102
  #     @hpNumbers.x = value + @spriteBaseX + 80
  #     @expBar.x    = value + @spriteBaseX + 6
  #
  # e o `@spriteBaseX` NAO e zero: e 34 na caixa de quem joga e 16 na do
  # inimigo. Eu tinha ficado com o 102 e deitado fora o 34.
  #
  # O resultado e exactamente o que se viu: tudo 34 pixeis a esquerda de onde
  # devia, com a barra a entrar por cima dos numeros de HP.
  #
  # A prova de que 34 e o numero certo esta na propria imagem: com ele, a barra
  # (136+96), os numeros (184+48) e a experiencia (40+192) acabam TODOS em 232,
  # a mesma margem direita dos 260 px da caixa. Sem ele, nenhum dos tres
  # acabava no mesmo sitio — que era o sinal de que estava errado, e que eu nao
  # vi por nao ter somado.
  CAIXA_BASE  = { false => 34, true => 16 }   # a minha, e a do inimigo
  CAIXA_X    = 102   # onde a barra de vida comeca, DEPOIS da base
  CAIXA_Y    = 40
  CAIXA_NUM_X = 80
  CAIXA_NUM_Y = 52
  CAIXA_NUM_DY = 2   # o motor desenha os digitos 2 px abaixo do topo do sprite
  DIGITO_L   = 16
  DIGITO_A   = 14

  def bitmap_caixa(nome)
    @bmps_ui ||= {}
    return @bmps_ui[nome] if @bmps_ui.key?(nome)
    @bmps_ui[nome] = (AnimatedBitmap.new("Graphics/UI/Battle/#{nome}").deanimate rescue nil)
  end

  # Os digitos vem da folha da batalha: 12 caracteres de 16x14, sendo o 10 a
  # barra "/" e o 11 o "%".
  def desenhar_numero!(b, valor, x, y, direita = false)
    folha = bitmap_caixa("icon_numbers")
    return unless folha
    digitos = (valor == :barra) ? [10] : valor.to_i.abs.to_s.chars.map(&:to_i)
    largura = digitos.length * DIGITO_L
    px = direita ? (x - largura) : x
    digitos.each do |d|
      b.blt(px, y, folha, Rect.new(d * DIGITO_L, 0, DIGITO_L, DIGITO_A))
      px += DIGITO_L
    end
    largura
  rescue
    0
  end

  # ⚠️ A CAIXA VOLTOU, MAS ENCOLHIDA — E A OBJECCAO ANTIGA CONTINUA VALIDA.
  #
  # A nota aqui em cima dizia que a caixa da batalha tapa o mundo, e dizia bem:
  # 260x84 num ecra de 512 e metade da largura. O que estava errado era a
  # conclusao — a resposta nao era deitar fora a caixa, era encolhe-la.
  #
  # ⚠️ ENCOLHE-SE A CAIXA JA COMPOSTA, E NAO CADA PEDACO.
  #
  # A tentacao e desenhar tudo com coordenadas a escala. Nao resulta: os
  # digitos da `icon_numbers` sao recortes de 16x14 de uma folha, e o texto do
  # nome nao tem tamanho fraccionario. Cada pedaco encolhido por sua conta
  # desalinha-se do vizinho.
  #
  # Compoe-se a caixa em tamanho verdadeiro, num bitmap a parte, e estica-se a
  # imagem inteira de uma vez. Tudo o que la esta encolhe junto e nada se
  # desalinha, porque as posicoes relativas sao as mesmas do jogo — continuam a
  # ser as do `Battle::Scene::PokemonDataBox`, so que vistas mais de longe.
  #
  # O bitmap intermedio e criado uma vez e reaproveitado. O HUD so se repinta
  # quando alguma coisa muda (ver o `@hud_chave`), mas "alguma coisa" inclui a
  # vida — ou seja, a cada golpe. Um `Bitmap.new` por golpe era lixo a gerar-se
  # durante toda a luta.
  ESCALA_CAIXA = 0.68

  def caixa_pequena!(b, x, y, pkmn, hp, hp_max, inimigo, com_exp = false)
    fundo = bitmap_caixa(inimigo ? "databox_normal_foe" : "databox_normal")
    return 0 unless fundo
    @caixa_tmp ||= {}
    tmp = @caixa_tmp[inimigo]
    if tmp.nil? || tmp.disposed? || tmp.width != fundo.width || tmp.height != fundo.height
      tmp = @caixa_tmp[inimigo] = Bitmap.new(fundo.width, fundo.height)
    end
    tmp.clear
    desenhar_caixa!(tmp, 0, 0, pkmn, hp, hp_max, inimigo, com_exp)
    lw = (fundo.width * ESCALA_CAIXA).round
    lh = (fundo.height * ESCALA_CAIXA).round
    b.stretch_blt(Rect.new(x, y, lw, lh), tmp, Rect.new(0, 0, tmp.width, tmp.height))
    lw
  rescue => e
    log("falha a encolher a caixa: #{e.class}: #{e.message}")
    0
  end

  def largura_da_caixa
    fundo = bitmap_caixa("databox_normal")
    return 180 unless fundo
    (fundo.width * ESCALA_CAIXA).round
  rescue
    180
  end

  def altura_da_caixa
    fundo = bitmap_caixa("databox_normal")
    return 58 unless fundo
    (fundo.height * ESCALA_CAIXA).round
  rescue
    58
  end

  def desenhar_caixa!(b, x, y, pkmn, hp, hp_max, inimigo, com_exp = false)
    fundo = bitmap_caixa(inimigo ? "databox_normal_foe" : "databox_normal")
    return unless fundo
    b.blt(x, y, fundo, Rect.new(0, 0, fundo.width, fundo.height))

    base = CAIXA_BASE[inimigo ? true : false].to_i
    nome = (pkmn.respond_to?(:name) ? pkmn.name : pkmn.to_s) rescue "?"
    nivel = (pkmn.level.to_i rescue 0)
    pbDrawTextPositions(b, [
      [nome.to_s, x + base + 8, y + 12, :left, Color.new(255, 255, 255), Color.new(75, 75, 75), :outline],
      ["Nv." + nivel.to_s, x + base + 142, y + 12, :left, Color.new(255, 255, 255), Color.new(75, 75, 75), :outline]
    ]) rescue nil

    barra_bmp = bitmap_caixa("overlay_hp")
    if barra_bmp
      alt = barra_bmp.height / 3
      total = [hp_max.to_i, 1].max
      viva = [[hp.to_i, 0].max, total].min
      larg = 0
      if viva > 0
        larg = (barra_bmp.width.to_f * viva / total)
        larg = 1.0 if larg < 1.0
        larg = ((larg / 2.0).round) * 2
      end
      cor = 0
      cor = 1 if viva <= total / 2
      cor = 2 if viva <= total / 4
      b.blt(x + base + CAIXA_X, y + CAIXA_Y, barra_bmp, Rect.new(0, cor * alt, larg, alt))
    end

    # Os numeros so aparecem do meu lado, como na batalha.
    return if inimigo
    # 54 / 54 / 70 sao as posicoes DENTRO do sprite de numeros do motor
    # (`pbDrawNumber(hp, bmp, 54, 2, :right)`), e o sprite esta em base+80.
    nx = x + base + CAIXA_NUM_X
    ny = y + CAIXA_NUM_Y + CAIXA_NUM_DY
    desenhar_numero!(b, hp.to_i, nx + 54, ny, true)
    desenhar_numero!(b, :barra, nx + 54, ny)
    desenhar_numero!(b, hp_max.to_i, nx + 70, ny)

    # ⚠️ A EXPERIENCIA — as coordenadas sao as do jogo, nao minhas.
    #
    # O `PokemonDataBox` poe a barra em (+6, +74) e enche-a com
    # `exp_fraction * largura`, arredondado a par. Copia-se, pela mesma razao
    # pela qual se copiaram as da vida: quem joga ve a mesma caixa que ve na
    # batalha porque E a mesma caixa.
    #
    # A largura vai a par de proposito: a `overlay_exp` e uma barra com borda, e
    # um pixel impar corta-a a meio de um degrade e fica com um serrilhado que
    # se nota justamente quando ela esta quase cheia.
    return unless com_exp
    exp_bmp = bitmap_caixa("overlay_exp")
    return unless exp_bmp
    fr = (pkmn.exp_fraction.to_f rescue 0.0)
    fr = 0.0 if fr < 0.0
    fr = 1.0 if fr > 1.0
    w = ((exp_bmp.width * fr / 2.0).round) * 2
    return if w <= 0
    b.blt(x + base + 6, y + 74, exp_bmp, Rect.new(0, 0, w, exp_bmp.height))
  rescue => e
    log("falha a desenhar a caixa: #{e.class}: #{e.message}")
  end


  #-----------------------------------------------------------------------------
  # BATALHA DE TREINADOR EM TEMPO REAL
  #
  # O evento do treinador continua a ser o do jogo: ele desafia, o dialogo dele
  # corre, e no fim ele reage a ter ganho ou perdido. O que muda e o MEIO — em
  # vez de abrir o ecra de batalha, ele solta os Pokemon no mapa e luta-se ali.
  #
  # ⚠️ O PROBLEMA DIFICIL AQUI E O TEMPO, E NAO A LUTA.
  #
  # O `TrainerBattle.start_core` e chamado de DENTRO do interpretador do evento,
  # e tem de devolver um resultado (1 ganhou, 2 perdeu) para o resto da pagina
  # continuar. Ou seja: e preciso segurar o interpretador sem congelar o jogo.
  #
  # A tentacao e chamar `$scene.update` no laco de espera. NAO SE PODE: o
  # `Scene_Map#update` corre o interpretador, e o interpretador esta parado
  # DENTRO deste metodo — seria reentrancia, e o mesmo evento comecaria outra
  # vez a meio de si proprio.
  #
  # A peca certa e o `miniupdate` (Scene_Map): actualiza o jogador, os mapas e
  # os sprites, e NAO toca no interpretador. E exactamente o que o motor usa
  # quando uma caixa de texto esta aberta e o mundo tem de continuar vivo. O
  # tick da arena chama-se a mao, na mesma ordem do `Scene_Map#update`.
  #-----------------------------------------------------------------------------
  TREINADOR_CAMPO  = 2      # quantos dele estao no campo ao mesmo tempo
  TREINADOR_ESPERA = 0.9    # segundos entre um cair e o seguinte entrar

  # ⚠️ ISTO ERA CHAMADO EM DEZ SITIOS E NUNCA EXISTIU.
  #
  # Todo o caminho do convite de arena (`/arena <nome>`) morria em
  # `NoMethodError: undefined method 'avisar'` — e como cada chamador tem o seu
  # `rescue`, o erro so aparecia no log e o convite falhava em silencio.
  #
  # E uma mensagem ao jogador: se a arena estiver a correr vai para o painel
  # dela (que fica por cima de tudo), senao e uma caixa normal.
  def avisar(texto)
    if @activa
      dizer(texto.to_s)
    else
      pbMessage(texto.to_s) rescue nil
    end
  rescue
    nil
  end


  #-----------------------------------------------------------------------------
  # O CAMPO DE BATALHA
  #
  # ⚠️ UMA ROTA NAO E UM SITIO PARA LUTAR.
  #
  # Uma luta em tempo real precisa de espaco aberto e de nada mais: sem cercas a
  # partir a linha de tiro, sem um NPC no meio, sem o mato a tentar cuspir
  # selvagens, sem a ponte onde nao se pode recuar. Nas rotas do jogo isso nunca
  # acontece — elas foram desenhadas para se ANDAR, e nao para se lutar nelas.
  #
  # Entao a luta muda de sitio. Ao comecar uma batalha de treinador o jogador vai
  # para um campo quadrado, so relva, fechado por bosque; no fim volta ao passo
  # exacto de onde saiu, virado para onde estava, como se nunca tivesse ido.
  #
  # ⚠️ O MAPA NAO EXISTE EM DISCO, E DE PROPOSITO.
  #
  # Gravar um Map302.rxdata obrigava a mexer no MapInfos, a fazer o ficheiro
  # viajar em cada actualizacao, e a mante-lo em sincronia com o resto. Nada
  # disso e preciso: o motor pede o mapa por `load_data`, e um `load_data` pode
  # ser respondido. O mapa nasce na memoria a primeira vez que alguem entra e
  # fica em cache dali para a frente.
  #
  # A tecnica ja tinha sido usada neste projecto pelo gerador procedural
  # (990_Procedural_IA_Maps), e e de la que vem o molde: o tileset e o do
  # Map008, a relva e o tile 384, e a arvore e um bloco de 2x6 espalhado por
  # duas camadas.
  #-----------------------------------------------------------------------------
  MAPA_ARENA   = 302     # nao ha Map302.rxdata; e servido de memoria
  ARENA_CAMPO  = 40      # o quadrado limpo, em casas
  ARENA_BOSQUE = 6       # a moldura de arvores, de cada lado (altura de 1 arvore)
  ARENA_LADO   = ARENA_CAMPO + (ARENA_BOSQUE * 2)

  # [camada 1, camada 2] de cada uma das 6 linhas de uma arvore. As duas ultimas
  # linhas trazem o TRONCO (528/536 e 529/537), que e a parte solida.
  ARVORE = [
    [[0, 2048], [0, 2049]],
    [[0, 2056], [0, 2057]],
    [[0, 2064], [0, 2065]],
    [[0, 2072], [0, 2073]],
    [[528, 2080], [529, 2081]],
    [[536, 2088], [537, 2089]]
  ].freeze

  def mapa_da_arena
    @mapa_arena ||= construir_arena!
  end

  def construir_arena!
    # O molde vem de um mapa de exterior verdadeiro: dali herda-se o tileset, o
    # panorama, a musica e tudo o resto que um mapa precisa de ter.
    base = (Kernel.anil_arena_load_data_original("Data/Map008.rxdata") rescue nil)
    base ||= load_data("Data/Map008.rxdata")
    mapa = Marshal.load(Marshal.dump(base))
    lado = ARENA_LADO
    mapa.width  = lado
    mapa.height = lado
    mapa.events = {}
    mapa.data = Table.new(lado, lado, 3)

    lado.times do |y|
      lado.times do |x|
        mapa.data[x, y, 0] = 384   # relva, e so relva
        mapa.data[x, y, 1] = 0
        mapa.data[x, y, 2] = 0
      end
    end

    # A moldura: arvores em cima, em baixo e dos dois lados. Sao plantadas de 2
    # em 2 casas na horizontal e de 6 em 6 na vertical, que e o tamanho delas.
    plantar = lambda do |x, y|
      return if x < 0 || y < 0 || (x + 1) >= lado || (y + 5) >= lado
      6.times do |dy|
        2.times do |dx|
          c1, c2 = ARVORE[dy][dx]
          mapa.data[x + dx, y + dy, 1] = c1
          mapa.data[x + dx, y + dy, 2] = c2
        end
      end
    end

    (0...lado).step(2) do |x|
      plantar.call(x, 0)                      # cima
      plantar.call(x, lado - ARENA_BOSQUE)    # baixo
    end
    (0...lado).step(6) do |y|
      (0...ARENA_BOSQUE).step(2) do |dx|
        plantar.call(dx, y)                          # esquerda
        plantar.call(lado - ARENA_BOSQUE + dx, y)    # direita
      end
    end

    log("campo de batalha construido: #{lado}x#{lado}, campo limpo de #{ARENA_CAMPO}")
    mapa
  rescue => e
    log("falha a construir o campo: #{e.class}: #{e.message}")
    nil
  end

  # ⚠️ AS ARVORES SAO O CENARIO; A PAREDE E ESTA.
  #
  # Uma arvore so e solida no TRONCO, que sao as duas ultimas das suas seis
  # linhas — a copa passa-se por baixo, e e assim que deve ser. Isso da uma
  # moldura bonita mas com buracos: pelo lado de baixo entrava-se quatro casas
  # dentro do bosque antes de bater em alguma coisa.
  #
  # Como o campo e meu e e um quadrado conhecido, a fronteira nao precisa de ser
  # adivinhada a partir do tileset: e um rectangulo, e diz-se qual e. O
  # movimento livre pergunta aqui antes de deixar passar.
  def fora_do_campo?(tx, ty)
    return false unless no_campo?
    tx < ARENA_BOSQUE || ty < ARENA_BOSQUE ||
      tx >= (ARENA_BOSQUE + ARENA_CAMPO) || ty >= (ARENA_BOSQUE + ARENA_CAMPO)
  rescue
    false
  end

  def no_campo?
    @volta_do_campo && $game_map && $game_map.map_id == MAPA_ARENA
  rescue
    false
  end

  def ir_para_o_campo!
    return false unless $game_map && $game_player && $scene.is_a?(Scene_Map)
    return false if $game_map.map_id == MAPA_ARENA
    return false unless mapa_da_arena
    @volta_do_campo = [$game_map.map_id, $game_player.x, $game_player.y,
                       ($game_player.direction rescue 2)]
    meio = ARENA_BOSQUE + (ARENA_CAMPO / 2)
    saltar_para!(MAPA_ARENA, meio, meio + 5, 8)
    registar("foi para o campo de batalha")
    true
  rescue => e
    log("falha a ir para o campo: #{e.class}: #{e.message}")
    @volta_do_campo = nil
    false
  end

  def voltar_do_campo!
    return unless @volta_do_campo
    mid, x, y, dir = @volta_do_campo
    @volta_do_campo = nil
    saltar_para!(mid, x, y, dir)
    registar("voltou do campo de batalha")
    despejar_log!
  rescue => e
    log("falha a voltar do campo: #{e.class}: #{e.message}")
    @volta_do_campo = nil
  end

  # ⚠️ QUEM FAZ A MUDANCA DE MAPA E O `miniupdate`, E NAO EU.
  #
  # Marcar `player_transferring` so agenda; quem a executa e o `Scene_Map`. E
  # como isto corre com o interpretador do treinador suspenso la dentro, o
  # `update` normal esta fora de questao (ver a nota do laco). O `miniupdate`
  # trata da mudanca de mapa — tem um ciclo proprio so para isso — e nao toca no
  # interpretador. E a mesma peca que ja segura o laco da luta.
  def saltar_para!(mid, x, y, dir)
    $game_temp.player_new_map_id   = mid
    $game_temp.player_new_x        = x
    $game_temp.player_new_y        = y
    $game_temp.player_new_direction = dir
    $game_temp.player_transferring = true
    12.times do
      break unless $game_temp.player_transferring
      Graphics.update
      ($scene.miniupdate rescue nil)
    end
    ($game_player.instance_variable_set(:@move_timer, nil) rescue nil)
  rescue
    nil
  end
  def formato_do_treinador(treinadores)
    regra = ($game_temp.battle_rules["size"].to_s rescue "")
    return 2 if regra.start_with?("2") || regra == "double"
    return 1 if regra.start_with?("1") || regra == "single"
    n = (treinadores || []).compact.length
    [[n, 1].max, TREINADOR_CAMPO].min
  rescue
    1
  end

  def campo_do_treinador
    ((@treinador && @treinador[:campo]) || 1).to_i
  rescue
    1
  end

  def treinador?
    @activa == true && !@treinador.nil?
  rescue
    false
  end

  def entrar_treinador!(treinadores, equipa_inimiga)
    return false unless AnilArena.directa?
    return false if activa?
    equipa = (equipa_inimiga || []).compact
    return false if equipa.empty?
    meu = ($player.first_able_pokemon rescue nil)
    meu ||= ($player.party.compact.find { |p| !p.egg? && p.hp > 0 } rescue nil)
    return false unless meu

    nome = _INTL("Treinador")
    begin
      t = (treinadores || []).compact.first
      nome = t.full_name.to_s if t && t.respond_to?(:full_name)
    rescue
    end

    # ⚠️ O MATO TEM DE SUMIR ANTES DE ELE SOLTAR NADA.
    #
    # Um selvagem do modo normal parado na relva durante uma batalha de
    # treinador e um encontro a espera de ser pisado: bastava andar por cima
    # para abrir o ecra de batalha por cima da luta. Limpa-se aqui, e dai para a
    # frente o `travar_mato?` impede que nasca outro (ele so deixa nascer na
    # batalha directa).
    limpar_spawns_do_mapa!
    # A mudanca de mapa vem ANTES de tudo o que se cria: o corpo do
    # treinador, o ajudante e os Pokemon dele tem de nascer no campo, e
    # nao na rota de onde se saiu.
    ir_para_o_campo!

    # ⚠️ O FORMATO E O DA BATALHA, E NAO UM NUMERO MEU.
    #
    # Eu punha sempre dois de cada lado. Mas a esmagadora maioria dos
    # treinadores do jogo e individual: um contra um, ele manda o seguinte
    # quando o dele cai. Perguntar por um ajudante numa batalha individual e
    # oferecer uma vantagem que a batalha nao tem — e o jogador reparou logo.
    #
    # Quem sabe o formato e a propria batalha: o motor faz
    # `setBattleRule("#{foe_trainers.length}v#{foe_trainers.length}")`, ou seja,
    # o numero de TREINADORES do outro lado e que diz se e dupla. Uma regra
    # explicita ("2v2" posta pelo evento) vence isso.
    campo = formato_do_treinador(treinadores)
    @treinador = {
      :nome => nome, :treinadores => treinadores, :campo => campo,
      :fila => equipa.dup, :fim => nil, :proximo_em => 0.0,
      :caidos => 0, :total => equipa.length
    }
    primeiros = []
    campo.times { primeiros << @treinador[:fila].shift if @treinador[:fila].any? }

    # Ajudante so numa batalha em dupla. Individual e individual.
    ajudante = (campo >= 2) ? escolher_ajudante!(meu) : nil
    unless entrar!(meu, primeiros)
      @treinador = nil
      return false
    end
    chamar_aliado!(ajudante) if ajudante
    dizer(_INTL("{1} quer batalhar!", nome))
    true
  rescue => e
    log("falha a entrar na batalha de treinador: #{e.class}: #{e.message}")
    @treinador = nil
    false
  end

  # Um dele caiu: o seguinte entra passado um instante. Sem a pausa, o proximo
  # nascia no mesmo frame da queda e nao se percebia que houve troca.
  def repor_do_treinador!
    return unless treinador?
    return if @treinador[:fim]
    agora = Time.now.to_f
    vivos = bichos_vivos.length
    if vivos <= 0 && @treinador[:fila].empty?
      terminar_treinador!(1)
      return
    end
    return if vivos >= campo_do_treinador
    return if @treinador[:fila].empty?
    return if agora < @treinador[:proximo_em].to_f
    @treinador[:proximo_em] = agora + TREINADOR_ESPERA
    pk = @treinador[:fila].shift
    return unless pk
    b = criar_bicho!(pk, proximo_id_de_bicho, 5)
    unless b
      # Nao havia casa livre: devolve-se a fila e tenta-se outra vez a seguir.
      @treinador[:fila].unshift(pk)
      return
    end
    actualizar_foco!
    dizer(_INTL("{1} enviou {2}!", @treinador[:nome], (pk.name rescue "?")))
  rescue => e
    registar("falha a repor o treinador: #{e.class}: #{e.message}")
  end

  # ⚠️ O ID DE UM BICHO NOVO NAO PODE SER `bichos.length`.
  #
  # Os ids sao ID_INIMIGO + n. Com trocas a meio, dois vivos podem estar nos
  # ids 0 e 2; `length` daria 2 outra vez, e o novo apagava o antigo do mapa.
  def proximo_id_de_bicho
    usados = bichos.map { |b| b[:id].to_i }
    n = 0
    n += 1 while usados.include?(ID_INIMIGO + n) && n < MAX_BICHOS
    ID_INIMIGO + n
  rescue
    ID_INIMIGO
  end

  # ⚠️ O POKEMON DE UM TREINADOR NAO FICA GROGUE.
  #
  # Grogue e o estado de quem se pode apanhar, e um Pokemon com dono nao se
  # apanha. Ele desmaia, sai do mapa, e o dono manda o seguinte.
  def matar_do_treinador!(b)
    dar_exp!(b)
    animar_desmaio!(b[:ev])
    dizer(_INTL("{1} desmaiou!", (b[:pkmn].name rescue "?")))
    apagar_evento_bicho!(b[:id])
    b[:ev] = nil
    b[:hp] = 0
    esquecer_vivos!
    bichos.delete(b)
    esquecer_vivos!
    @treinador[:caidos] = @treinador[:caidos].to_i + 1
    @treinador[:proximo_em] = Time.now.to_f + TREINADOR_ESPERA
    actualizar_foco!
    terminar_treinador!(1) if bichos_vivos.empty? && @treinador[:fila].empty?
  rescue
    nil
  end

  # ⚠️ PERDER UM POKEMON NAO E PERDER A BATALHA.
  #
  # Fora deste modo, ficar sem vida acaba tudo — contra um selvagem nao ha para
  # onde ir. Aqui ha: manda-se o seguinte da equipa, como em qualquer batalha.
  # So se perde quando nao sobrar ninguem de pe.
  # ⚠️ CAIR COM O PARCEIRO DE PE E SAIR DA LUTA A MEIO DELA.
  #
  # O ajudante ja esta no campo, ja tem vida e ja esta a lutar — so nao e
  # controlado por ninguem. Quando o Pokemon do jogador cai, mandava-se o
  # jogador embora e o ajudante ficava la sozinho, controlado pela IA, numa
  # luta que era dele. Do lado de ca isso le-se como "perdi", quando na verdade
  # ainda ha metade da equipa de pe.
  #
  # Assumir o controlo dele e a leitura certa: o corpo do jogador passa a ser
  # aquele Pokemon, e o evento do ajudante desaparece porque ja nao ha um
  # segundo boneco — ha um so, e agora e nosso.
  def assumir_aliado!
    return false unless aliado_vivo?
    novo = @aliado[:pkmn]
    return false unless novo
    hp = [@aliado[:hp].to_i, 1].max

    # O boneco do jogador vai para onde o ajudante estava: e o corpo dele que
    # se assume, e nao um teletransporte para o sitio onde o outro morreu.
    ev = @aliado[:ev]
    if ev
      begin
        $game_player.instance_variable_set(:@real_x, (ev.instance_variable_get(:@real_x) rescue 0))
        $game_player.instance_variable_set(:@real_y, (ev.instance_variable_get(:@real_y) rescue 0))
        $game_player.instance_variable_set(:@x, ev.x)
        $game_player.instance_variable_set(:@y, ev.y)
        ($game_player.center(ev.x, ev.y) rescue nil)
      rescue
        nil
      end
    end

    dispensar_aliado!     # o evento sai: o boneco passa a ser este

    @meu        = novo
    @hp_meu     = hp
    @prontos    = [0.0, 0.0, 0.0, 0.0]
    @buffs      = {}
    @estado     = nil
    @energia    = ENERGIA_MAX
    @charset    = caminho_do_sprite(novo)
    @veloc_base = velocidade_para_passo(novo)
    @vel_livre  = velocidade_livre(novo)
    ($game_player.refresh_charset rescue nil)
    ($game_player.opacity = 255) rescue nil
    dizer(_INTL("Agora és tu, {1}!", novo.name))
    registar("assumiu o ajudante: #{(novo.name rescue '?')} com #{hp} de vida")
    true
  rescue => e
    registar("falha a assumir o ajudante: #{e.class}: #{e.message}")
    false
  end

  def trocar_o_meu!
    return false unless treinador?
    seguinte = ($player.party.compact.find do |p|
      !p.egg? && p.hp > 0 && !p.equal?(@meu) &&
        !(aliado_vivo? && p.equal?(@aliado[:pkmn]))
    end rescue nil)
    return false unless seguinte
    @meu = seguinte
    @hp_meu = [(seguinte.hp.to_i rescue seguinte.totalhp), 1].max
    @prontos = [0.0, 0.0, 0.0, 0.0]
    @buffs = {}
    @estado = nil
    @energia = ENERGIA_MAX
    @charset = caminho_do_sprite(seguinte)
    @veloc_base = velocidade_para_passo(seguinte)
    @vel_livre = velocidade_livre(seguinte)
    ($game_player.refresh_charset rescue nil)
    ($game_player.opacity = 255) rescue nil
    dizer(_INTL("Vai, {1}!", seguinte.name))
    true
  rescue => e
    registar("falha a trocar: #{e.class}: #{e.message}")
    false
  end

  # O fim MARCA-SE; quem desmonta e o laco de espera, que esta la fora a
  # segurar o evento. Desmontar aqui deixava-o a olhar para uma arena morta.
  def terminar_treinador!(resultado)
    return unless @treinador
    return if @treinador[:fim]
    @treinador[:fim] = resultado.to_i
    dizer(resultado.to_i == 1 ? _INTL("Você venceu!") : _INTL("Você perdeu..."))
  rescue
    nil
  end

  # ⚠️ AS FALAS AQUI ERAM MINHAS, E JA HA QUEM AS DIGA.
  #
  # Enquanto o `on_start_battle` nao disparava, o roteiro de pos-batalha do jogo
  # nunca corria — e eu tinha tapado esse buraco a escrever a fala de derrota a
  # mao. Agora que o roteiro corre (o NPC fala, sorteia o presente, arranca o
  # cooldown da revanche), as minhas falas passaram a ser uma segunda voz por
  # cima da primeira. Saem.
  #
  # O que NAO sai e o premio. O `pbGainMoney` e da propria batalha — conta o
  # Amuleto da Sorte, a Happy Hour e o Pay Day — e ninguem mais o chama, porque
  # quem o chamaria era o fim de batalha do ecra, que aqui nao existe. Tirá-lo
  # seria deixar de pagar as batalhas de treinador, e isso ninguem pediu.
  #
  # Fica sem aviso na tela: a mensagem do dinheiro tambem e do ecra de batalha,
  # e uma escrita por mim seria outra vez uma voz a mais.
  # ⚠️ A FALA DE DERROTA NAO E MINHA — E DELE, E EU SO A PONHO NO ECRA.
  #
  # Tirei-a junto com a mensagem do dinheiro, e foi erro: sao coisas diferentes.
  # A do dinheiro era texto meu, escrito por mim. Esta e o `lose_text` do PBS, o
  # mesmo texto que apareceria numa batalha normal — quem o mostra e o ecra de
  # batalha, e aqui nao ha ecra nenhum. Se eu nao o mostrar, ninguem mostra, e o
  # treinador perde calado.
  #
  # O sorteio de recompensa do MOD das revanches nao substitui isto: e um
  # sorteio, e da item em cerca de 14% das vezes. A fala de derrota e sempre.
  def desfecho_do_treinador!(resultado, batalha, treinadores)
    return unless resultado.to_i == 1
    (treinadores || []).compact.each do |t|
      fala = (t.lose_text.to_s rescue "")
      pbMessage(fala) rescue nil unless fala.empty?
    end
    return unless batalha
    (batalha.pbGainMoney rescue nil)
  rescue => e
    log("falha no desfecho do treinador: #{e.class}: #{e.message}")
  end

  def treinador_acabou?
    return true unless @activa
    return true unless @treinador
    !@treinador[:fim].nil?
  rescue
    true
  end

  # Uma luta que nunca acaba e um bug, e um bug nao pode prender o jogador para
  # sempre dentro de um evento.
  TREINADOR_TECTO = 60 * 60 * 15   # 15 minutos em frames

  def correr_batalha_de_treinador!(batalha = nil)
    limite = (Graphics.frame_count rescue 0) + TREINADOR_TECTO
    loop do
      Graphics.update
      Input.update
      (tick_antes! rescue nil)
      # O `miniupdate` mexe o jogador, os mapas e os sprites; nao mexe no
      # interpretador. Sem ele o mundo ficava congelado por baixo da luta.
      ($scene.miniupdate rescue nil) if $scene.is_a?(Scene_Map)
      (tick! rescue nil)
      (repor_do_treinador! rescue nil)
      break if treinador_acabou?
      if (Graphics.frame_count rescue 0) > limite
        registar("batalha de treinador passou do tecto de tempo; encerrada")
        terminar_treinador!(2)
        break
      end
    end
    resultado = ((@treinador && @treinador[:fim]) || 2).to_i
    # Guarda-se antes de desmontar: o `sair!` deita fora o @treinador todo.
    lista = ((@treinador && @treinador[:treinadores]) || [])
    @treinador = nil
    sair!
    # Depois do `sair!`: ele arruma o boneco e apaga os eventos no mapa onde
    # eles estao, que ainda e o campo.
    voltar_do_campo!
    registar("batalha de treinador terminou com resultado #{resultado}")
    desfecho_do_treinador!(resultado, batalha, lista)
    resultado
  rescue => e
    log("falha no laco do treinador: #{e.class}: #{e.message}")
    @treinador = nil
    (sair! rescue nil)
    2
  end

  def barra(b, x, y, actual, total, cor, altura = 12)
    larg = 160
    total = 1 if total.to_i <= 0
    cheio = (larg * [[actual.to_f / total, 0.0].max, 1.0].min).round
    b.fill_rect(x - 1, y - 1, larg + 2, altura + 2, Color.new(0, 0, 0))
    b.fill_rect(x, y, larg, altura, Color.new(60, 60, 60))
    b.fill_rect(x, y, cheio, altura, cor)
  rescue
    nil
  end
end

#-------------------------------------------------------------------------------
# O RELOGIO TEM DE SER INSTALADO DEPOIS DOS PLUGINS.
#
# O `Scene_Map#update` e disputado por meio mundo. Um alias feito no corpo do MOD
# e apagado quando os plugins carregam — a mesma armadilha que ja apanhou o
# evento do lendario.
#-------------------------------------------------------------------------------
module AnilLanRework
  class << self
    unless method_defined?(:anil_arena_orig_apply_post_plugin_patches)
      alias_method :anil_arena_orig_apply_post_plugin_patches, :apply_post_plugin_patches rescue nil
    end

    def apply_post_plugin_patches
      anil_arena_orig_apply_post_plugin_patches rescue nil
      (AnilArena.registar_item! rescue nil)
      # ⚠️ AQUI, E NAO NO CORPO DO FICHEIRO.
      #
      # Os plugins carregam depois de tudo, e o `MultipleForms` e deles. Um
      # `register` escrito a solta no ficheiro corria antes de o modulo existir
      # e era codigo morto — e a licao ja esta escrita nos apontamentos deste
      # projecto (os remendos ao Game_Map fora do apply_post_plugin_patches).
      (AnilArenaChaves.registar! rescue nil)
      (AnilArenaChaves.registar_forma! rescue nil)

      # ⚠️ O MAPA DO CAMPO E SERVIDO, NAO LIDO.
      #
      # O motor pede sempre `load_data("Data/Map302.rxdata")`. Esse ficheiro nao
      # existe e nao vai existir: em vez de o gravar em disco (e de o ter de pôr
      # no MapInfos, e de o fazer viajar em cada actualizacao), responde-se ao
      # pedido com o mapa que a arena constroi na memoria.
      #
      # O gancho e em `Kernel` E na classe `Kernel`, porque `load_data` e chamado
      # das duas maneiras conforme o sitio: como funcao de topo dentro de
      # objectos, e como `Kernel.load_data` a partir de codigo de modulo.
      begin
        unless Kernel.respond_to?(:anil_arena_load_data_original)
          Kernel.module_eval do
            class << self
              alias_method :anil_arena_load_data_original, :load_data
              def load_data(ficheiro)
                if ficheiro.to_s =~ /Map#{AnilArena::MAPA_ARENA}\.rxdata/
                  mapa = (AnilArena.mapa_da_arena rescue nil)
                  return mapa if mapa
                end
                anil_arena_load_data_original(ficheiro)
              end
            end

            alias_method :anil_arena_load_data_original_i, :load_data
            def load_data(ficheiro)
              if ficheiro.to_s =~ /Map#{AnilArena::MAPA_ARENA}\.rxdata/
                mapa = (AnilArena.mapa_da_arena rescue nil)
                return mapa if mapa
              end
              anil_arena_load_data_original_i(ficheiro)
            end
          end
          AnilArena.log("campo de batalha ligado ao load_data (mapa #{AnilArena::MAPA_ARENA})")
        end
      rescue => e
        AnilArena.log("falha a ligar o campo ao load_data: #{e.class}: #{e.message}")
      end

      # Sem uma ficha de mapa o motor nao sabe se ali se anda de bicicleta, se o
      # nome aparece ao entrar, nem se e interior. `announce_location` fica a
      # false: um cartaz com o nome do sitio a abrir no inicio de cada luta seria
      # ruido.
      begin
        if defined?(GameData::MapMetadata) && !GameData::MapMetadata::DATA[AnilArena::MAPA_ARENA]
          GameData::MapMetadata::DATA[AnilArena::MAPA_ARENA] = GameData::MapMetadata.new(
            :id                => AnilArena::MAPA_ARENA,
            :real_name         => "Campo de Batalha",
            :outdoor_map       => true,
            :announce_location => false,
            :can_bicycle       => false
          )
          AnilArena.log("ficha do campo de batalha registada")
        end
      rescue => e
        AnilArena.log("falha a registar a ficha do campo: #{e.class}: #{e.message}")
      end

      # ⚠️ O GANCHO DO TREINADOR TEM DE FICAR POR FORA DE TODOS OS OUTROS.
      #
      # O `TrainerBattle.start_core` ja e disputado por tres MODs (o 125 do
      # Cable Club, o 127 do coop autoritativo, e o legado). Instalando aqui,
      # depois dos plugins, este alias fica a ENVOLVER a cadeia toda: quando eu
      # assumo a batalha, nenhum deles chega a correr — e e isso que se quer,
      # porque nao ha ecra de batalha nenhum para eles sincronizarem.
      #
      # Quando eu NAO assumo (opcao desligada, sem amuleto, sem Pokemon de pe,
      # ou qualquer falha), chama-se o original e o jogo segue exactamente como
      # sempre seguiu. Esta e a regra de ouro deste MOD inteiro.
      begin
        if defined?(TrainerBattle) && TrainerBattle.respond_to?(:start_core)
          class << TrainerBattle
            unless method_defined?(:anil_arena_orig_start_core) ||
                   private_method_defined?(:anil_arena_orig_start_core)
              alias_method :anil_arena_orig_start_core, :start_core
              def start_core(*args)
                # ⚠️ UMA BATALHA DENTRO DE OUTRA E O PIOR SITIO ONDE ISTO PODE IR PARAR.
                #
                # Enquanto o laco da luta corre, o mundo continua vivo: o jogador
                # anda e carrega no C. Se ele encostar noutro treinador — ou no
                # MESMO, que na revanche esta ali ao lado — o `Game_Event#start`
                # dispara e chama-se outro `start_core` por dentro deste.
                #
                # Cair no metodo original era o pior dos dois: abria-se o ecra de
                # batalha por cima da luta em tempo real, com o interpretador do
                # primeiro evento ainda suspenso dentro de mim. Nao ha volta boa
                # a partir dai.
                #
                # Recusa-se, e devolve-se 0 — que e o codigo de "indecidido" do
                # proprio motor (o mesmo que ele usa quando uma batalha e
                # abortada). Quem chamou trata isso como "nao houve batalha", que
                # e a verdade: ja ha uma a decorrer.
                if (AnilArena.treinador? rescue false)
                  AnilArena.log("recusou uma batalha de treinador dentro de outra")
                  return 0
                end
                assumida = false
                batalha  = nil
                treinadores = nil
                begin
                  if (AnilArena.modo_treinador? rescue false) &&
                     !(AnilArena.activa? rescue true)
                    # ⚠️ COMECAR UMA BATALHA E MAIS DO QUE MONTA-LA.
                    #
                    # O `start_core` original dispara isto antes de tudo, e eu
                    # tinha-o saltado por completo:
                    #
                    #     EventHandlers.trigger(:on_start_battle)
                    #
                    # E ai que o motor guarda os niveis da equipa para a
                    # verificacao de evolucao do fim, e — o que se estava a ver —
                    # e ai que o MOD das revanches grava QUAL evento e que
                    # comecou a batalha:
                    #
                    #     EventHandlers.add(:on_start_battle, :rematch_save_context, ...)
                    #         $game_temp.anil_rematch_pre_battle_event_id = eid
                    #
                    # Sem esse gravar, o `get_pre_battle_context` do fim devolve
                    # zero, e o bloco inteiro do roteiro de pos-batalha —
                    # registo do vencido, arranque do cooldown, e o sorteio do
                    # presente (`anil_rematch_pending_roll`) — esta todo dentro
                    # de um `if eid > 0`. Ou seja: a batalha corria, ganhava-se, e
                    # nao acontecia nada a seguir.
                    #
                    # Um comeco a meio nao pode dar um fim inteiro.
                    EventHandlers.trigger(:on_start_battle)

                    # As equipas saem do MESMO sitio de onde a batalha normal as
                    # tirava. Sem isto eu estaria a inventar treinadores em vez
                    # de usar os que o PBS tem.
                    treinadores, itens, equipa, inicios = generate_foes(*args)
                    assumida = AnilArena.entrar_treinador!(treinadores, equipa)
                    if assumida
                      # ⚠️ A BATALHA TEM DE EXISTIR MESMO, E NAO SO O RESULTADO.
                      #
                      # Sem um objecto de batalha verdadeiro, o `on_end_battle`
                      # dispara com `battle` a nil e todo o sistema que escuta o
                      # fim de uma batalha desiste — foi por isso que o sistema
                      # de revanches nunca registava o treinador como vencido
                      # (`if decision == 1 && battle && battle.trainerBattle?`).
                      #
                      # Constroi-se a batalha como o `start_core` original a
                      # constroi, com as equipas e os treinadores reais. A unica
                      # troca e o palco: o `DebugSceneNoVisuals` e a cena muda do
                      # proprio motor, feita para haver batalha sem ecra. Quem
                      # decide o vencedor e a luta no mapa; tudo o resto — o
                      # premio, os avisos, a papelada do fim — continua a ser o
                      # motor a fazer, com os dados dele.
                      jogadores, itens_aliado, equipa_jog, inicios_jog =
                        BattleCreationHelperMethods.set_up_player_trainers(equipa)
                      batalha = Battle.new(Battle::DebugSceneNoVisuals.new,
                                           equipa_jog, equipa, jogadores, treinadores)
                      batalha.party1starts = inicios_jog
                      batalha.party2starts = inicios
                      batalha.ally_items   = itens_aliado
                      batalha.items        = itens
                      if $game_temp.battle_rules["size"].nil?
                        setBattleRule("#{treinadores.length}v#{treinadores.length}")
                      end
                      BattleCreationHelperMethods.prepare_battle(batalha)
                    end
                  end
                rescue => e
                  AnilArena.log("gancho do treinador falhou: #{e.class}: #{e.message}")
                  # Se a batalha nao se conseguiu montar, a arena tambem nao pode
                  # ficar aberta: desmonta-se e devolve-se o jogo ao caminho
                  # normal, que e sempre a saida segura deste MOD.
                  (AnilArena.sair! rescue nil) if assumida
                  assumida = false
                end
                unless assumida
                  return anil_arena_orig_start_core(*args)
                end

                variavel    = ($game_temp.battle_rules["outcomeVar"] || 1)
                pode_perder = ($game_temp.battle_rules["canLose"] || false)
                resultado   = AnilArena.correr_batalha_de_treinador!(batalha)
                $game_temp.clear_battle_rules rescue nil
                # O `after_battle` desfaz megas, limpa o veneno grave e dispara o
                # `on_end_battle` — agora com a batalha verdadeira, que e o que
                # faz as revanches e as estatisticas reconhecerem esta vitoria.
                # Estas duas linhas sao as unicas que distinguem "o meu lado
                # falhou" de "o lado das revanches falhou", e custam nada.
                begin
                  eid, mid = AnilLanRework::RematchSystem.get_pre_battle_context
                  AnilArena.log("contexto de revanche no fim: evento=#{eid} mapa=#{mid} " \
                                "batalha_de_treinador=#{(batalha.trainerBattle? rescue '?')}")
                rescue => e
                  AnilArena.log("nao consegui ler o contexto de revanche: #{e.class}: #{e.message}")
                end
                (BattleCreationHelperMethods.after_battle(resultado, pode_perder) rescue nil)
                (BattleCreationHelperMethods.set_outcome(resultado, variavel, true) rescue nil)
                # ⚠️ PERDER TEM CONSEQUENCIA. Sem isto, quem perdesse ficava no
                # mapa com a equipa no chao e o treinador ali a olhar.
                if resultado == 2 && !pode_perder
                  (pbStartOver rescue nil)
                end
                Input.update
                AnilArena.log("start_core do treinador devolve #{resultado}")
                # ⚠️ E ESTE `resultado` QUE LIGA A SELF-SWITCH.
                #
                # O evento do treinador tem um ramo condicional com
                # `TrainerBattle.start(...)`, e o `start` devolve `outcome == 1`.
                # Devolver o numero certo daqui e o que faz o ramo correr, a
                # switch A ligar, e o treinador passar a ser um treinador
                # vencido. Nao ha nada que eu deva ligar a mao.
                resultado
              end
            end
          end
          AnilArena.log("gancho do treinador em tempo real instalado")
        end
      rescue => e
        AnilArena.log("falha a enganchar o treinador: #{e.class}: #{e.message}")
      end

      # ⚠️ ESTE GANCHO TEM DE SER O ULTIMO DA CADEIA.
      #
      # O MOD 070 ja embrulha o `spawnPokeEvent` para sincronizar os spawns
      # entre jogadores. Carregando o 189 depois dele, este alias fica por FORA
      # do dele: quando eu recuso, nada acontece — nem a criacao, nem o pacote
      # de sincronizacao. Se fosse ao contrario, eu recusava a criacao mas o
      # anuncio ja tinha saido, e os outros jogadores viam um bicho que aqui
      # nao existe.
      # ⚠️ SAO DOIS CAMINHOS, E EU SO TINHA TAPADO UM.
      #
      # O `pbOnStepTaken` do plugin escolhe entre dois mundos:
      #
      #     if salvajes_visibles_en_ow == 1 && var[55] >= 5
      #       pbBattleOnStepTaken(...)   # encontro invisivel, ecra de batalha
      #     else
      #       pbSpawnOnStepTaken(...)    # encontro visivel, bicho no mapa
      #     end
      #
      # Eu tapei o segundo. Quem tivesse a definicao no outro valor caia no
      # primeiro — e um encontro classico a abrir por cima da luta em tempo real
      # e pior do que um bicho a piscar.
      #
      # ⚠️ E ha uma fonte de passos que eu nao contava: o EMPURRAO.
      #
      # O movimento livre nao chama `increase_steps`, portanto eu assumia que
      # `pbOnStepTaken` nunca corria durante a arena. So que o `empurrar!` usa o
      # `jump` do motor — e um salto E um passo para o jogo. Cada golpe que me
      # atirava para tras podia sortear um encontro.
      #
      # Tapando o `pbOnStepTaken`, tapam-se os dois mundos e todas as fontes de
      # passo de uma vez. Os outros dois gancho ficam como rede.
      begin
        if Object.private_method_defined?(:pbOnStepTaken) ||
           Object.method_defined?(:pbOnStepTaken)
          Object.class_eval do
            unless private_method_defined?(:anil_arena_orig_pbOnStepTaken) ||
                   method_defined?(:anil_arena_orig_pbOnStepTaken)
              alias_method :anil_arena_orig_pbOnStepTaken, :pbOnStepTaken
              def pbOnStepTaken(eventTriggered)
                if (AnilArena.activa? rescue false)
                  # Os eventos do passo continuam a correr (contadores, veneno
                  # do mapa, o que mais houver); o que nao corre e o encontro.
                  (EventHandlers.trigger(:on_step_taken, $game_player) rescue nil)
                  return
                end
                anil_arena_orig_pbOnStepTaken(eventTriggered)
              end
            end
          end
          AnilArena.log("trava do mato instalada em pbOnStepTaken")
        end
      rescue => e
        AnilArena.log("falha a travar o passo: #{e.class}: #{e.message}")
      end

      begin
        if Object.private_method_defined?(:pbSpawnOnStepTaken) ||
           Object.method_defined?(:pbSpawnOnStepTaken)
          Object.class_eval do
            unless private_method_defined?(:anil_arena_orig_pbSpawnOnStepTaken) ||
                   method_defined?(:anil_arena_orig_pbSpawnOnStepTaken)
              alias_method :anil_arena_orig_pbSpawnOnStepTaken, :pbSpawnOnStepTaken
              def pbSpawnOnStepTaken(repel_active)
                return if (AnilArena.travar_mato? rescue false)
                anil_arena_orig_pbSpawnOnStepTaken(repel_active)
              end
            end
          end
          AnilArena.log("trava do mato instalada em pbSpawnOnStepTaken")
        else
          AnilArena.log("AVISO: pbSpawnOnStepTaken nao existe; o mato so e travado no spawnPokeEvent")
        end
      rescue => e
        AnilArena.log("falha a travar o passo do mato: #{e.class}: #{e.message}")
      end

      # ⚠️ A RELVA MEXIA POR UM BICHO QUE JA TINHA SIDO RECUSADO.
      #
      # Eu ja tinha mudado a trava do `spawnPokeEvent` para o
      # `pbSpawnOnStepTaken` por esta mesma razao — e deixei metade dela para
      # tras. O `travar_mato?` (ha bichos a mais?) subiu; o teste de DISTANCIA
      # ficou no `spawnPokeEvent`, que e o quarto passo.
      #
      # A sequencia do plugin e esta, e o `pbPlaceEncounter` vem ANTES da
      # animacao:
      #
      #     pbChooseTileOnStepTaken   <- escolhe a casa        (1)
      #     encounter_triggered?      <- sorteia               (2)
      #     pbPlaceEncounter          <- CRIA o evento         (3)  <- eu recusava aqui
      #     addUserAnimation(relva)   <- mexe a relva          (4)  <- e isto corria na mesma
      #
      # Ou seja: longe da relva, o jogo escolhia uma casa la longe, eu recusava
      # o bicho, e a relva mexia na mesma. Repetido a cada passo, e o "fica
      # piscando varios lugares como se fosse spawnar alguem, mas falha".
      #
      # O primeiro passo devolve a casa, e o plugin tem um `return if !pos` logo
      # a seguir. Recusando ali, nao ha bicho, nao ha relva e nao ha grito.
      begin
        if Object.private_method_defined?(:pbChooseTileOnStepTaken) ||
           Object.method_defined?(:pbChooseTileOnStepTaken)
          Object.class_eval do
            unless private_method_defined?(:anil_arena_orig_escolher_casa) ||
                   method_defined?(:anil_arena_orig_escolher_casa)
              alias_method :anil_arena_orig_escolher_casa, :pbChooseTileOnStepTaken
              def pbChooseTileOnStepTaken(*args)
                casa = anil_arena_orig_escolher_casa(*args)
                return casa unless casa.is_a?(Array) && casa.length >= 2
                return nil if (AnilArena.activa? rescue false) &&
                              (AnilArena.casa_longe_de_mais?(casa[0], casa[1]) rescue false)
                casa
              end
            end
          end
          AnilArena.log("trava da distancia instalada em pbChooseTileOnStepTaken")
        else
          AnilArena.log("AVISO: pbChooseTileOnStepTaken nao existe; a relva pode mexer a toa")
        end
      rescue => e
        AnilArena.log("falha a travar a escolha da casa: #{e.class}: #{e.message}")
      end

      # A segunda porta: os spawns que chegam pela sincronizacao entre jogadores
      # nao passam pelo `pbSpawnOnStepTaken`, e por isso esta continua a valer.
      begin
        if defined?(Game_Map) && Game_Map.method_defined?(:spawnPokeEvent)
          Game_Map.class_eval do
            unless method_defined?(:anil_arena_orig_spawnPokeEvent)
              alias_method :anil_arena_orig_spawnPokeEvent, :spawnPokeEvent
              def spawnPokeEvent(x, y, pokemon)
                return if (AnilArena.recusa_spawn?(x, y) rescue false)
                anil_arena_orig_spawnPokeEvent(x, y, pokemon)
              end
            end
          end
        end
      rescue => e
        AnilArena.log("falha a travar os spawns: #{e.class}: #{e.message}")
      end

      # ⚠️ O MENU NASCE NO SEGUIDOR, e por isso tem de vir DEPOIS dos plugins.
      #
      # Falar com o proprio Pokemon e a porta mais natural para isto: ele esta
      # ali atras, e e ele que vai lutar. O `interact` original corre o evento
      # comum do seguidor (a fala); mete-se um menu a frente e so se chama o
      # original se a pessoa escolher conversar.
      begin
        if defined?(FollowerData)
          FollowerData.class_eval do
            unless method_defined?(:anil_arena_orig_interact)
              alias_method :anil_arena_orig_interact, :interact
              def interact(event)
                return anil_arena_orig_interact(event) if (AnilArena.activa? rescue false)
                # Sem chave nenhuma, falar com o Pokemon e o que sempre foi.
                return anil_arena_orig_interact(event) unless (AnilArena.libertada? rescue false)
                # ⚠️ O MENU MOSTRA O QUE SE PODE FAZER, E NAO O QUE EXISTE.
                #
                # Com as duas linhas fixas, quem so tinha o Guia via "Batalha
                # direta" e levava com uma recusa; quem so tinha o amuleto via
                # "Batalha automatica" e levava com outra. Uma opcao que so
                # serve para dizer que nao e pior do que nao estar la.
                opcoes = [_INTL("Conversar")]
                accoes = [:conversar]
                if (AnilArena.directa? rescue false)
                  opcoes << _INTL("Batalha direta")
                  accoes << :directa
                end
                if (AnilArena.automatica_livre? rescue false)
                  opcoes << _INTL("Batalha automática")
                  accoes << :automatica
                end
                opcoes << _INTL("Cancelar")
                accoes << :cancelar
                escolha = (pbMessage(_INTL("O que você quer fazer?"), opcoes, opcoes.length) rescue -1)
                case accoes[escolha]
                when :conversar  then anil_arena_orig_interact(event)
                when :directa    then (AnilArena.entrar_directa! rescue nil)
                when :automatica then (AnilArena.entrar_automatica! rescue nil)
                end
              end
            end
          end
        end
      rescue => e
        AnilArena.log("falha a enganchar o seguidor: #{e.class}: #{e.message}")
      end
      begin
        Scene_Map.class_eval do
          unless method_defined?(:anil_arena_orig_update) || private_method_defined?(:anil_arena_orig_update)
            alias_method :anil_arena_orig_update, :update
            def update
              # O input primeiro: ver a nota no tick_antes!.
              (AnilArena.tick_antes! rescue nil)
              anil_arena_orig_update
              (AnilArena.reparar_boneco! rescue nil)
              (AnilArena.tick! rescue nil)
            end
          end
        end

        # ⚠️ AS QUATRO TECLAS PASSAM A SER DA ARENA.
        #
        # Depois de a arena as consumir, toda a gente que perguntar recebe
        # "nao". E o que impede o seguidor de ser guardado e a mochila de abrir a
        # meio de um combate. Fora da arena nada muda: o `engolir?` da falso.
        Input.singleton_class.class_eval do
          unless method_defined?(:anil_arena_orig_trigger?)
            alias_method :anil_arena_orig_trigger?, :trigger?
            def trigger?(botao)
              return false if (AnilArena.engolir?(botao) rescue false)
              anil_arena_orig_trigger?(botao)
            end
          end
          unless method_defined?(:anil_arena_orig_press?)
            alias_method :anil_arena_orig_press?, :press?
            def press?(botao)
              return false if (AnilArena.engolir?(botao) rescue false)
              anil_arena_orig_press?(botao)
            end
          end
          unless method_defined?(:anil_arena_orig_repeat?)
            alias_method :anil_arena_orig_repeat?, :repeat?
            def repeat?(botao)
              return false if (AnilArena.engolir?(botao) rescue false)
              anil_arena_orig_repeat?(botao)
            end
          end
        end
        Game_Player.class_eval do
          unless method_defined?(:anil_arena_orig_refresh_charset) ||
                 private_method_defined?(:anil_arena_orig_refresh_charset)
            alias_method :anil_arena_orig_refresh_charset, :refresh_charset
            def refresh_charset
              nome = (AnilArena.activa? ? AnilArena.charset_jogador : nil)
              if nome && !nome.to_s.empty?
                @character_name = nome
                return
              end
              anil_arena_orig_refresh_charset
            end
          end

          # ⚠️ O refresh_charset NAO E O UNICO A ESCREVER O BONECO.
          #
          # O `set_movement_type` tambem o faz, e corre sempre que se comeca a
          # andar ou a correr — para reaplicar a skin do multiplayer. Era por
          # isso que o Pokemon voltava a ser o treinador ao primeiro passo: eu
          # tapei um caminho e deixei o outro aberto.
          unless method_defined?(:anil_arena_orig_set_movement_type) ||
                 private_method_defined?(:anil_arena_orig_set_movement_type)
            # ⚠️ O ANDAR POR CASAS DESLIGA-SE AQUI, e so dentro da arena.
            #
            # O `update_command_new` e onde o motor le as setas e manda dar um
            # passo de uma casa. Enquanto a arena estiver a correr, ele nao
            # chega a correr: quem le as setas e o movimento livre, que escreve
            # na posicao verdadeira. Fora da arena o metodo original volta
            # intacto — o jogo normal continua a andar de casa em casa, que e
            # como os mapas, os eventos e a pesca esperam.
            # (o gancho do seguidor fica mais abaixo, fora do Game_Player)
            unless method_defined?(:anil_arena_orig_update_command_new) ||
                   private_method_defined?(:anil_arena_orig_update_command_new)
              alias_method :anil_arena_orig_update_command_new, :update_command_new
              def update_command_new
                if (AnilArena.activa? rescue false)
                  AnilArena.mover_livre!
                  return
                end
                anil_arena_orig_update_command_new
              end
            end
            alias_method :anil_arena_orig_set_movement_type, :set_movement_type
            def set_movement_type(type)
              r = anil_arena_orig_set_movement_type(type)
              nome = (AnilArena.activa? ? AnilArena.charset_jogador : nil)
              @character_name = nome if nome && !nome.to_s.empty?
              r
            end
          end
        end
        AnilLanRework.log("[ARENA] relogio e charset instalados depois dos plugins") rescue nil
      rescue => e
        AnilLanRework.log("[ARENA] falha a instalar o relogio: #{e.message}") rescue nil
      end
    end
  end
end

#-------------------------------------------------------------------------------
# O COMANDO
#-------------------------------------------------------------------------------
module AnilArenaComando
  module_function

  def tratar(texto)
    t = texto.to_s.strip
    # Sem o amuleto, estes comandos nao existem: devolve-se false para o texto
    # seguir o seu caminho (chat normal), como qualquer palavra escrita.
    return false if t =~ %r{\A/(arena|ca[cç]ar|dire[tc]a|aliado)\b}i && !AnilArena.libertada?
    if t =~ %r{\A/aliado\z}i
      if !AnilArena.activa?
        pbMessage(_INTL("Só dentro de uma batalha.")) rescue nil
      else
        escolhido = AnilArena.escolher_ajudante!(AnilArena.meu_pokemon)
        if escolhido
          AnilArena.chamar_aliado!(escolhido)
        else
          AnilArena.dispensar_aliado!
        end
      end
      return true
    end
    if t =~ %r{\A/dire[tc]a\z}i
      AnilArena.entrar_directa!
      return true
    end
    if t =~ %r{\A/ca[cç]ar(?:\s+(\d+))?\z}i
      quantos = $1 ? $1.to_i : 4
      if AnilArena.activa?
        pbMessage(_INTL("Você já está na arena. Use /arena sair.")) rescue nil
      else
        AnilArena.cacar!(quantos)
      end
      return true
    end
    return false unless t =~ %r{\A/arena(?:\s+(.*))?\z}i
    arg = $1.to_s.strip.downcase

    if arg == "sair"
      AnilArena.sair!(_INTL("Arena encerrada.")) if AnilArena.activa?
      AnilArena.recusar_convite!
      return true
    end
    unless arg.empty?
      # "/arena a Gaby" -> sorteado dos dois lados. O "a" e de aleatorio.
      partes = arg.split(/\s+/)
      if ["a", "aleatorio", "aleatório", "random"].include?(partes[0].to_s.downcase) && partes.length > 1
        AnilArena.convidar!(partes[1..-1].join(" "), true)
      else
        AnilArena.convidar!(arg)
      end
      return true
    end
    if AnilArena.activa?
      pbMessage(_INTL("Você já está na arena. Use /arena sair.")) rescue nil
      return true
    end

    equipa = ($player.party.compact rescue [])
    if equipa.empty?
      pbMessage(_INTL("Você precisa de um Pokémon na equipe.")) rescue nil
      return true
    end

    nomes = equipa.map { |p| "#{p.name} Nv.#{p.level}" }
    nomes << _INTL("Cancelar")
    escolha = pbMessage(_INTL("Quem entra na arena?"), nomes, nomes.length)
    return true if escolha < 0 || escolha >= equipa.length

    meu = equipa[escolha]
    # ⚠️ O adversario e uma COPIA de um Pokemon selvagem, nao um da equipa.
    # Nivel igual ao seu, para o teste ser sobre os controlos e nao sobre estar
    # a bater num bebe ou num monstro.
    especie = (GameData::Species.keys.sample rescue :RATTATA)
    inimigo = (Pokemon.new(especie, meu.level) rescue nil)
    unless inimigo
      pbMessage(_INTL("Não consegui criar o adversário.")) rescue nil
      return true
    end

    if AnilArena.entrar!(meu, inimigo)
      pbMessage(AnilLanRework.ui_format(
        "Arena: {1} contra {2}!\nSetas para andar, A/S/D/Shift para os golpes.\n/arena sair para desistir.",
        meu.name, inimigo.speciesName)) rescue nil
    end
    true
  rescue => e
    AnilArena.log("falha no comando: #{e.class}: #{e.message}")
    true
  end
end

module AnilLanRework
  module Router
    class << self
      alias_method :anil_arena_orig_route_packet, :route_packet unless method_defined?(:anil_arena_orig_route_packet)

      def route_packet(packet)
        if packet.is_a?(Hash)
          case packet["type"].to_s
          when "arena_convite" then (AnilArena.receber_convite!(packet) rescue nil); return
          when "arena_aceite"  then (AnilArena.receber_aceite!(packet)  rescue nil); return
          when "arena_recusa"  then (AnilArena.receber_recusa!(packet)  rescue nil); return
          when "arena_golpe"   then (AnilArena.receber_golpe!(packet)   rescue nil); return
          when "caverna_mob"   then (AnilRaidCaverna.receber_mob!(packet)   rescue nil); return
          when "caverna_mobs"  then (AnilRaidCaverna.receber_mobs!(packet)  rescue nil); return
          when "caverna_morte" then (AnilRaidCaverna.receber_morte!(packet) rescue nil); return
          when "caverna_dono"  then (AnilRaidCaverna.receber_dono!(packet)  rescue nil); return
          when "caverna_caido"     then (AnilArenaRessurreicao.receber_caido!(packet)     rescue nil); return
          when "caverna_levantado" then (AnilArenaRessurreicao.receber_levantado!(packet) rescue nil); return
          when "caverna_revive"    then (AnilArenaRessurreicao.receber_pedido!(packet)    rescue nil); return
          when "cav_nascer"    then (AnilRaidCaverna.receber_cav_nascer!(packet) rescue nil); return
          when "cav_snap"      then (AnilRaidCaverna.receber_cav_snap!(packet)   rescue nil); return
          when "cav_morte"     then (AnilRaidCaverna.receber_cav_morte!(packet)  rescue nil); return
          when "caverna_golpe"
            # O mesmo tipo de pacote leva as duas coisas: um golpe, ou a
            # posicao do ajudante. Distingue-se pela marca, e nao por um tipo
            # novo — um tipo novo era outra rota para manter em dois sitios.
            if packet["parceiro"]
              (AnilArena.receber_parceiro!(packet) rescue nil)
            else
              (AnilArena.receber_golpe!(packet) rescue nil)
            end
            return
          when "arena_dano"    then (AnilArena.receber_dano!(packet)    rescue nil); return
          when "arena_armadilha" then (AnilArena.receber_armadilha!(packet) rescue nil); return
          when "arena_mostra"  then (AnilArena.receber_espectaculo!(packet) rescue nil); return
          when "arena_parceiro" then (AnilArena.receber_parceiro!(packet) rescue nil); return
          when "arena_fim"     then (AnilArena.receber_fim!(packet)     rescue nil); return
          end
        end
        anil_arena_orig_route_packet(packet)
      end
    end
  end
end

module AnilLanRework
  module Chat
    class << self
      if !method_defined?(:anil_arena_orig_send_message)
        alias_method :anil_arena_orig_send_message, :send_message rescue nil
      end

      def send_message(text)
        return if AnilArenaComando.tratar(text)
        anil_arena_orig_send_message(text)
      end
    end
  end
end

#===============================================================================
# A OPCAO NO MENU
#
# ⚠️ NASCE DESLIGADA, e de proposito.
#
# Ligar isto muda TODAS as batalhas de treinador do jogo. Uma mudanca dessas
# nao pode acontecer a alguem so por ter o amuleto no bolso — tem de ser uma
# escolha, e tem de se poder desfazer no mesmo sitio onde se fez.
#
# O valor e 0 = Sim e 1 = Nao porque e assim que o `EnumOption` do motor conta
# (o indice na lista), e nao um booleano.
#===============================================================================
class PokemonSystem
  attr_writer :arena_treinador

  def arena_treinador
    @arena_treinador = 1 if @arena_treinador.nil?
    @arena_treinador
  end
end

if defined?(MenuHandlers)
  MenuHandlers.add(:options_menu, :arena_treinador, {
    "name"        => _INTL("Treinador em tempo real"),
    "order"       => 87,
    "type"        => EnumOption,
    "parameters"  => [_INTL("Sim"), _INTL("Não")],
    "description" => _INTL("Batalhas contra treinadores acontecem no mapa, em tempo real, em vez da tela de batalha."),
    "get_proc"    => proc { next $PokemonSystem.arena_treinador },
    "set_proc"    => proc { |value, _scene| $PokemonSystem.arena_treinador = value }
  })
end
