# encoding: UTF-8
#===============================================================================
# MOD: 192_Raid_Caverna — a caverna instanciada
#===============================================================================
# ⚠️ ISTO É COLA, E NÃO MOTOR. FOI POR ISSO QUE COUBE NUM FICHEIRO.
#
# Antes de escrever uma linha fui ver o que já existia, porque a diferença entre
# "um mês" e "uma tarde" estava toda nessa resposta:
#
#   o combate em tempo real .......... AnilArena, com caça de selvagens
#   um mapa que não está em disco ..... o truque do `load_data` do MAPA_ARENA
#   itens no chão, com rede ........... AnilLanRework::DroppedItems
#   raridade por escalão .............. as pools do GiftBoxSystem
#   entrar por bilhete ................ o padrão de todas as outras raids
#
# As cinco peças estão feitas e testadas. A caverna não inventa nenhuma delas —
# encadeia-as. O que este ficheiro acrescenta é a REGRA: quem entra, o que cai,
# como se sai, e o que se perde ao cair.
#
#-------------------------------------------------------------------------------
# AS REGRAS
#
#   entrar     por bilhete, escolhendo DOIS Pokémon. Só eles entram.
#   lutar      em tempo real, contra o que a caverna cospe.
#   apanhar    cada derrotado pode deixar cair um item; quanto mais forte ele
#              for, melhor o escalão de onde o item sai.
#   sair       só com uma Escape Rope. Não há porta.
#   cair       tudo o que se apanhou lá dentro fica no chão, para quem passar.
#
# ⚠️ A ÚLTIMA REGRA É A QUE FAZ AS OUTRAS VALEREM.
#
# Sem ela, entrar não custa nada e o loot é de graça: mata-se até cansar e sai-se
# com tudo. Com ela, cada minuto lá dentro é uma aposta — o que já se tem só é
# nosso depois de sair. E como outros jogadores entram na mesma instância, o que
# cai de nós é o que eles vieram buscar.
#
# Por isso o inventário da raid é CONTABILIZADO À PARTE (`@ganho`), e não lido da
# mochila: ao cair perde-se o que se ganhou ali, e não o que se trouxe de casa.
# Confundir as duas coisas seria roubar o jogador.
#===============================================================================

module AnilRaidCaverna
  # ⚠️ A CAVERNA SAO DOIS MAPAS, E AS ESCADAS SAO AS DO MONTE MOON.
  #
  # O 303 e a entrada; o 304 e o fundo, e chega-se la pelas escadas que ja
  # estavam desenhadas no chao do mapa original. O que se apagou dos dois foram
  # as SAIDAS — nao ha uma unica porta para a rua em nenhum dos andares.
  #
  # `MAPA` continua a ser o 303 porque e por ali que se entra; `dentro?` e tudo
  # o resto perguntam pelo conjunto.
  # ⚠️ O MONTE MOON SAIU, E COM ELE SAIU O SEGUNDO ANDAR.
  #
  # A masmorra de pedra era duas copias do Monte Moon (1492 + 1813 casas de
  # chao) coladas por escadas. Passa a ser uma copia do Tunel Rocha: 110x80,
  # 2293 casas num andar so. E maior do que os dois juntos e nao precisa de
  # escadas para o ser.
  #
  # ⚠️ E SAO DOIS ANDARES OUTRA VEZ, MAS POR OUTRA RAZAO.
  #
  # No Monte Moon o segundo andar era "mais fundo e mais duro" — uma escolha. No
  # Tunel Rocha e uma NECESSIDADE de geometria: medido, o andar de cima tem 2289
  # casas de chao repartidas por tres cameras que nao se tocam. Quem passa de
  # uma para a outra desce e volta a subir noutro sitio, e sao essas quatro
  # escadas que fazem do tunel um sitio so em vez de tres becos.
  #
  # Com os dois andares: 5297 casas, 97% e 99% delas alcancaveis da entrada.
  MAPA        = 303          # o Tunel Rocha, onde se entra
  FUNDO       = 304          # o andar de baixo, e o que cose o de cima
  # ⚠️ O SAFARI SAO QUATRO AREAS, E AS SETAS DELAS FICAM TODAS.
  #
  # A caverna apagou os eventos todos e ficou bem, porque a caverna e um mapa
  # desenhado inteiro. O safari nao e: as quatro areas sao um sitio so, cortado
  # em quatro, e quem as cose sao os `FlechaSalida` das bordas. Apaga-los dava
  # uma area sozinha, com um terco dela a ser as outras areas vistas de longe e
  # sem maneira de la chegar.
  #
  # Portanto fica TUDO o que liga area a area, e vai fora exactamente o que
  # abria para fora do safari: as duas casetas dos investigadores e o portao.
  # Dentro anda-se de ponta a ponta; para fora so a Corda.
  #
  # E as setas nao precisaram de codigo novo: o `correr_passagens!` que ja
  # levava o jogador da caverna para o fundo le o destino do proprio evento, e
  # uma seta do safari e um evento igual a uma escada do Monte Moon.
  SAFARI      = 305          # a area de entrada do safari
  MAPAS       = [303, 304, 305, 306, 307, 308].freeze

  # ⚠️ A MASMORRA DEIXA DE SER "A CAVERNA" E PASSA A SER UMA ESCOLHA.
  #
  # Tudo aqui dentro — o bilhete, a corda, o isolamento da mochila, a regra de
  # se perder o saque ao cair, a autoridade do servidor — nao tem nada de
  # caverna: serve qualquer sitio fechado com bichos la dentro. O que era da
  # caverna e so o mapa e o texto da porta.
  #
  # Por isso as duas entram na MESMA tabela e o unico bilhete pergunta para
  # onde. Uma terceira masmorra e uma linha aqui, um mapa em disco e uma grelha
  # no servidor — e mais nada.
  #
  # O safari e o andar de cima em tudo menos no nome: 66x50 em vez de corredor,
  # meia centena de especies em vez de treze, e nivel 42 a 51 em vez de 14 a
  # 22. E a masmorra de quem ja fez a caverna.
  MASMORRAS = {
    :caverna => {
      :mapa    => 303,
      # ⚠️ (43,67) e a mancha mais aberta do tunel: 121 casas livres em 121, ou
      # seja, onze por onze sem uma pedra. Medida com as passagens do tileset E
      # com os eventos que barram, e nao escolhida a olho.
      :entrada => [43, 67],
      :nome    => "Túnel Rocha",
      :escalao => "27-30",
      :sorte   => 1.0,
      :aviso   => "O túnel é fundo e não tem saída: lá dentro não se captura nada, e só se sai com uma Corda da Caverna — que cai dos Pokémon de lá.\nSe você cair, deixa no chão tudo o que apanhou.\nQuer mesmo entrar?"
    },
    :safari => {
      :mapa    => 305,
      :entrada => [14, 13],
      :nome    => "Safari Abandonado",
      :escalao => "42-51",
      # ⚠️ O SAFARI TEM DE PAGAR MAIS, SENAO NINGUEM LA VAI.
      #
      # O escalao ja fazia metade do trabalho sozinho: nivel 42 abre a pool
      # laranja, que a caverna (14-22) so ve em sonhos. Mas a PROBABILIDADE era
      # a mesma nos dois — 7,5% de um Pokemon deixar alguma coisa — e um sitio
      # com o dobro do nivel e o dobro do risco a pagar a mesma taxa nao e uma
      # progressao, e uma alternativa.
      #
      # A sorte multiplica as chances todas. Com 2,5 o safari deixa cair algo em
      # cerca de um em cada cinco, contra um em cada treze da caverna — e como
      # as pools que ele alcanca sao melhores, o que cai tambem vale mais.
      #
      # A vermelha continua a precisar de nivel 55, que os habitantes do safari
      # nao tem. Quem a quiser tem de matar um chefe (70) ou um super (100), e
      # isso e de proposito: uma masmorra tem de ter uma coisa que so se tira a
      # quem se ve de longe.
      :sorte   => 2.5,
      :aviso   => "O safari abandonado são quatro áreas ligadas pelas setas, e o que anda lá é de nível 42 para cima — cada área com os seus.\nAs mesmas regras: não se captura nada, só se sai com uma Corda, e quem cai deixa tudo no chão.\nQuer mesmo entrar?"
    }
  }.freeze

  # Onde se aterra em cada andar. O 304 nao esta aqui de proposito: chega-se la
  # pelas escadas e nao pela porta.
  ENTRADAS = { 303 => [43, 67], 305 => [14, 13] }.freeze
  BASE        = 11           # Monte Moon, o molde
  BILHETE     = :BILHETECAVERNA
  # ⚠️ A SAÍDA TEM DE SER UM ITEM QUE SE GASTE, E A ESCAPE ROPE NÃO É.
  #
  # Neste build a Escape Rope é um Key Item com `consumable = false`: quem a
  # tem, tem-a para sempre. Toda a tensão da caverna vinha de a saída custar
  # alguma coisa — e não custava nada a ninguém que já a tivesse comprado.
  # Pior: era um item que se traz DE FORA, portanto a caverna nem precisava de
  # ser jogada para se sair dela.
  #
  # A corda da caverna nasce e gasta-se aqui dentro. Cai dos Pokémon que se
  # derrota (ver o `CHANCE_CORDA`), o que faz da saída uma coisa que se ganha a
  # lutar, e some ao ser usada.
  SAIDA       = :CORDACAVERNA
  CORDA_FORA  = :ESCAPEROPE   # a de sempre, que aqui dentro não faz nada
  # ⚠️ (20,20) ERA PAREDE. E ISSO SOZINHO EXPLICAVA METADE DO QUE CORREU MAL.
  #
  # O jogador nascia dentro da pedra, e a volta dele havia 5 casas livres em 81
  # — o `casa_livre_perto` do semeador não tinha onde pôr ninguém, e portanto
  # não punha. Zero Pokémon, sem um erro.
  #
  # (62,48) tem 80 casas livres em 81 à volta: é a mancha mais aberta do Monte
  # Moon inteiro. Foi medida com as passagens do tileset, não escolhida a olho.
  ENTRADA     = [43, 67]     # a mancha mais aberta do Tunel Rocha

  # ⚠️ O ESCALÃO SAI DO NÍVEL DE QUEM CAIU, E NÃO DE UM SORTEIO À PARTE.
  #
  # É isso que faz o fundo da caverna valer a pena: um Pokémon de nível 60 dá
  # acesso a coisas que um de nível 10 nunca dá. As pools são as MESMAS das
  # caixas de presente — não há uma segunda tabela de raridade para manter em
  # sincronia, que é como as duas acabariam por divergir.
  ESCALOES = [
    [0,  :verde],      # até 24
    [25, :azul],
    [40, :laranja],
    [55, :vermelha]
  ].freeze

  # ⚠️ CADA DERROTADO É UM SORTEIO DE CAIXA, E NÃO UM SACO GARANTIDO.
  #
  # Estava em 55% com um segundo item a 25%: quase todo o Pokémon deixava algo,
  # e ao fim de dez minutos a mochila valia mais do que o risco de lá estar.
  # Isso mata a caverna de duas maneiras — o saque deixa de ser um prémio, e a
  # regra de perder tudo ao cair deixa de doer, porque repõe-se num instante.
  #
  # As chances passam a ser as MESMAS que as caixas têm no mundo (ver o sorteio
  # da revanche, no MOD 006): verde 5%, azul 2%, laranja 0,5%. A vermelha, que
  # no mundo nem sequer cai assim, fica em 0,1%.
  #
  # O nível não muda a probabilidade: muda QUE caixas estão em jogo. Um Pokémon
  # fraco só pode dar verde; um de nível 55+ sorteia as quatro, uma a uma, da
  # melhor para a pior. No fundo da caverna isso dá 7,6% de deixar alguma
  # coisa — ainda raro, mas com prémios que valem a descida.
  CHANCE_CAIXA = {
    :vermelha => 0.1,
    :laranja  => 0.5,
    :azul     => 2.0,
    :verde    => 5.0
  }.freeze

  # Da melhor para a pior: é a ordem em que se sorteia, e a primeira que sair
  # ganha. Sem isto, sortear a verde primeiro tirava as boas do caminho.
  ORDEM_CAIXAS = [:vermelha, :laranja, :azul, :verde].freeze

  @activa = false
  @ganho  = {}               # item => quantidade, só o que se apanhou aqui

  class << self
    attr_reader :activa, :ganho
  end

  module_function

  # ⚠️ ESTE LOG NUNCA ESCREVEU UMA LINHA, E EU ANDEI A LER O NADA.
  #
  # Ele chamava o `AnilLanRework.log`, que comeca com:
  #
  #     return unless $anil_debug_log_enabled
  #
  # — e esse interruptor esta desligado de proposito neste projecto (ligado,
  # trava o "recuperar partida"). Portanto TODAS as linhas que a caverna
  # escreveu desde o primeiro dia — quem semeou, quem mandava, porque falhou um
  # nascimento — foram para o chao. Quando fui procurar a decisao da posse no
  # `anil_arena.txt`, nao estava la porque nunca esteve.
  #
  # Ficheiro proprio, como os outros tres logs da arena, e sem interruptor
  # nenhum: o que a caverna diz e sempre gravado, porque e pouco e e o que
  # explica o que se ve.
  FICHEIRO_LOG = "arena_caverna.log"

  # ⚠️ PELA MESMA RAZAO DO 189: o diagnostico ja deu o que tinha a dar.
  #
  # Aqui ele escreve a cada 40 linhas ou a cada segundo — mais comportado que o
  # da arena, mas na masmorra e a arena que corre o relogio, portanto o custo
  # cai no mesmo laco. Liga-se pondo isto a `true`.
  LOG_LIGADO = false

  # ⚠️ HA COISAS QUE NAO SE PODEM PERDER POR O LOG ESTAR DESLIGADO.
  #
  # O `LOG_LIGADO` esta a false de proposito — o diagnostico do dia-a-dia ja
  # deu o que tinha a dar e nao vale o custo. Mas quando um jogador perde a
  # masmorra e fica plantado la dentro, o que eu preciso de saber e exactamente
  # o que este interruptor apagou: que porta se tentou, e porque nao abriu.
  #
  # Sao meia duzia de linhas POR DERROTA, nao por frame. Essas escrevem-se
  # sempre, e e a diferenca entre corrigir e adivinhar — o que ja me custou
  # esta ronda inteira.
  def log_sempre(t)
    linha = "%s  %s" % [Time.now.strftime("%Y-%m-%d %H:%M:%S"), t]
    (File.open(FICHEIRO_LOG, "a") { |fh| fh.puts(linha) } rescue nil)
    (AnilLanRework.log("[raid] #{t}") rescue nil)
  rescue
    nil
  end

  def log(t)
    return unless LOG_LIGADO
    linha = "%s  %s" % [Time.now.strftime("%H:%M:%S.%L"), t]
    @linhas_log ||= []
    @linhas_log << linha
    despejar_log! if @linhas_log.length >= 40 ||
                     (Time.now.to_f - @log_despejo.to_f) > 1.0
    (AnilLanRework.log("[raid] #{t}") rescue nil)
  rescue
    nil
  end

  def despejar_log!
    @log_despejo = Time.now.to_f
    return if @linhas_log.nil? || @linhas_log.empty?
    lote = @linhas_log
    @linhas_log = []
    if File.exist?(FICHEIRO_LOG) && File.size(FICHEIRO_LOG) > (4 * 1024 * 1024)
      File.delete(FICHEIRO_LOG) rescue nil
    end
    File.open(FICHEIRO_LOG, "a") { |f| f.puts(lote) }
  rescue
    nil
  end

  def dentro?
    @activa && $game_map && MAPAS.include?($game_map.map_id)
  rescue
    false
  end

  #-----------------------------------------------------------------------------
  # O MAPA
  #
  # O molde é o Monte Moon a sério: dali herda-se o tileset, a música, e as
  # paredes. Só se limpam os EVENTOS — uma instância não tem NPCs nem as escadas
  # do mapa original, senão sair-se-ia por uma delas e a Escape Rope deixava de
  # ser a única porta.
  #-----------------------------------------------------------------------------
  # ⚠️ O MAPA E UM FICHEIRO, E JA NAO UM TRUQUE.
  #
  # O `Map303.rxdata` existe agora em disco, com entrada no `MapInfos` e com
  # encontros próprios no `encounters.dat`. Isso não é arrumação: era a causa
  # de não nascer um único Pokémon. Servir o mapa de memória resolvia o
  # DESENHO e mais nada — o nome e a tabela de encontros vivem noutros
  # ficheiros, e nenhum deles responde a um `load_data` apanhado a meio.
  #
  # O `construir!` fica, sem chamador, como plano B documentado: se um dia o
  # ficheiro faltar no pacote de alguém, sabe-se o que ele fazia.
  def mapa
    File.exist?("Data/Map%03d.rxdata" % destino[:mapa])
  rescue
    false
  end

  def construir!
    base = (Kernel.anil_arena_load_data_original("Data/Map%03d.rxdata" % BASE) rescue nil)
    base ||= load_data("Data/Map%03d.rxdata" % BASE)
    m = Marshal.load(Marshal.dump(base))
    m.events = {}
    log("caverna construida a partir do Map%03d (%dx%d)" % [BASE, m.width, m.height])
    m
  rescue => e
    log("falha a construir a caverna: #{e.class}: #{e.message}")
    nil
  end

  #-----------------------------------------------------------------------------
  # ENTRAR
  #-----------------------------------------------------------------------------
  # ⚠️ SEM AMULETO A CAVERNA NÃO EXISTE — E "NÃO EXISTE" NÃO É "ESTÁ FECHADA".
  #
  # A diferença é toda: um NPC que diz «ainda não podes entrar» ANUNCIA a
  # caverna a quem não a devia sequer conhecer, e a partir daí há gente a
  # perguntar como se arranja o bilhete de uma coisa que ainda está a ser
  # testada. Isto devolve `false` calado, e quem chama sabe que, calado, não
  # deve dizer nada — é por isso que o `disponivel?` está separado do
  # `perguntar!`: o NPC pergunta ANTES de abrir a boca.
  #
  # O amuleto é o mesmo do 189: quem testa a arena testa a caverna.
  # ⚠️ QUEM ADMINISTRA NAO PRECISA DO AMULETO.
  #
  # O amuleto e a porta dos JOGADORES: e ele que decide para quem e que a
  # caverna existe. Um administrador nao esta a jogar — esta a testar, e o
  # primeiro teste e precisamente arranjar o bilhete. Sem isto, o `/caverna
  # bilhete` devolvia false, o texto descia a corrente ate ao chat e saia
  # "Comando desconhecido" para quem tem as chaves da casa.
  #
  # O predicado do admin e o mesmo de todos os outros comandos deste projecto
  # (o id do `multiplayer_player.txt` contra a lista do MOD 151), e nao uma
  # lista nova — uma segunda lista de administradores e uma que fica por
  # actualizar.
  def admin?
    return AnilEventoShinyComando.admin? if defined?(AnilEventoShinyComando)
    false
  rescue
    false
  end

  def disponivel?
    # O item tem de existir de qualquer maneira: sem ele nao ha nada para dar
    # nem para gastar, seja quem for que esteja a pedir.
    return false unless (GameData::Item.exists?(BILHETE) rescue false)
    return true if admin?
    # ⚠️ Na masmorra luta-se em pessoa, do principio ao fim: e batalha directa,
    # e portanto e o amuleto. O Guia Mestre nao abre esta porta — la dentro nao
    # ha caça automatica nenhuma para ele ligar.
    (AnilArena.directa? rescue false)
  rescue
    false
  end

  # ⚠️ COM UMA SO MASMORRA NAO SE PERGUNTA NADA.
  #
  # Um menu de uma escolha e um clique a mais para dizer o que ja se sabia. Se
  # um dia o Map305 faltar no pacote de alguem, a pergunta desaparece sozinha e
  # ele entra na caverna como sempre entrou.
  def masmorras_prontas
    MASMORRAS.select { |_k, d| File.exist?("Data/Map%03d.rxdata" % d[:mapa]) }
  rescue
    { :caverna => MASMORRAS[:caverna] }
  end

  def escolher_masmorra
    prontas = masmorras_prontas
    return nil if prontas.empty?
    return prontas.keys.first if prontas.length == 1
    # ⚠️ UMA LISTA DE NOMES NAO E UMA ESCOLHA.
    #
    # "Caverna Instável" e "Safari Abandonado" lado a lado nao dizem a coisa
    # que decide: uma e de nivel 14 e a outra de 42. Quem entra de nivel 20 no
    # safari nao esta a escolher um sitio diferente, esta a escolher perder — e
    # so descobre isso la dentro, sem bilhete e sem corda. O escalao vai no
    # proprio nome da opcao.
    nomes = prontas.values.map { |d| "#{d[:nome]} (Nv. #{d[:escalao]})" }
    i = pbMessage(_INTL("Para onde?"), nomes + [_INTL("Desistir")], nomes.length + 1) rescue nomes.length
    return nil if i.nil? || i >= nomes.length
    prontas.keys[i]
  rescue
    nil
  end

  def perguntar!
    return false unless disponivel?
    escolha = escolher_masmorra
    return false unless escolha
    @destino = escolha
    ficha = MASMORRAS[escolha]
    return false unless pbConfirmMessage(_INTL(ficha[:aviso])) rescue false
    entrar!
  end

  # O mapa para onde se vai desta vez. Sem escolha feita, e a caverna — que e o
  # que todo o codigo assumia antes de haver duas.
  def destino
    MASMORRAS[@destino || :caverna] || MASMORRAS[:caverna]
  end

  # ⚠️ DOIS POKÉMON, E SÓ ELES.
  #
  # A caverna não é uma batalha por turnos com equipa de seis: é uma luta em
  # tempo real onde se controla UM e o outro ajuda. Escolher os dois à entrada é
  # o momento de decidir, e depois não se muda — trocar a meio seria poder
  # curar-se saindo, que é o contrário do que a Escape Rope significa aqui.
  # ⚠️ DOIS SOZINHO, UM EM GRUPO — E A CONTA E SIMPLES.
  #
  # Quem entra sozinho leva um Pokemon e um ajudante de IA: sao dois contra a
  # caverna. Se um grupo de dois levasse a mesma coisa, eram QUATRO — o dobro
  # do dano, o dobro dos alvos para os inimigos dividirem, e metade do risco.
  # Isso nao e cooperar, e escolher a dificuldade mais baixa.
  #
  # Em grupo, o parceiro humano OCUPA o lugar do ajudante. Continuam a ser dois
  # no campo, como sempre; a diferenca e que o segundo pensa em vez de obedecer
  # a uma rotina — o que ja e vantagem que baste.
  #
  # O grupo le-se ANTES de se escolher: a pergunta que se faz depende disso.
  def entrar!
    com_amigo = !guardar_amigo!.nil?
    equipa = ($player.party.compact.select { |p| !p.egg? && p.hp > 0 } rescue [])
    minimo = com_amigo ? 1 : 2
    if equipa.length < minimo
      pbMessage(_INTL("Precisa de {1} Pokémon em condições para entrar.", minimo)) rescue nil
      return false
    end

    segundo = nil
    if com_amigo
      nome = ((AnilLanRework.players[amigo_id].name rescue nil) || _INTL("seu parceiro"))
      pbMessage(_INTL("Você vai entrar com {1}.\nEm grupo cada um leva só um Pokémon — quem entra sozinho é que leva ajudante.", nome)) rescue nil
      primeiro = escolher_um(equipa, _INTL("Quem vai com você?"))
      return false unless primeiro
    else
      primeiro = escolher_um(equipa, _INTL("Quem vai à frente?"))
      return false unless primeiro
      resto = equipa.reject { |p| p.equal?(primeiro) }
      segundo = escolher_um(resto, _INTL("E quem ajuda?"))
      return false unless segundo
    end

    @activa = true
    @ganho = {}
    @regresso = [$game_map.map_id, $game_player.x, $game_player.y,
                 ($game_player.direction rescue 2)]

    unless saltar_para_caverna!
      @activa = false
      return false
    end
    consumir_bilhete!
    # ⚠️ O `guardar_amigo!` JA CORREU, LA EM CIMA.
    #
    # Ele decide quantos Pokemon se escolhem, portanto tem de ser a primeira
    # coisa que acontece — e nao aqui, depois de as escolhas estarem feitas.
    # A nota de porque e que o grupo se anota a porta fica abaixo.
    #
    # Eu estava a ler o `coop_party_partner_id` no momento do golpe. Isso e
    # perguntar a um sistema que atravessa uma mudanca de mapa, uma remocao do
    # peer da lista e a sua reinsercao — e basta um desses passos correr numa
    # ordem diferente para a resposta vir vazia no instante em que importa. Foi
    # o que se viu: grupo feito la fora, os dois entram, e la dentro nao se
    # reconhecem.
    #
    # A alianca da caverna e uma coisa da CAVERNA: decide-se a porta, com o
    # grupo que existia nesse momento, e nao muda enquanto se la estiver.
    # Desfazer o grupo a meio nao transforma um aliado em inimigo, e um pacote
    # perdido no caminho tambem nao.
    # ⚠️ Isola-se DEPOIS de o bilhete ser consumido, senão o bilhete saía da
    # mochila nova e a verdadeira ficava com ele.
    @chegada = Time.now.to_f
    ligar_logs!
    isolar!([primeiro, segundo].compact)
    AnilArena.entrar!(primeiro, []) rescue nil
    (AnilArena.chamar_aliado!(segundo) rescue nil) if segundo
    pbMessage(_INTL("A entrada desmorona atrás de você.\nSó uma Corda da Caverna tira você daqui — e elas caem dos Pokémon daqui.")) rescue nil
    log(segundo ? "entrou com #{primeiro.name} e #{segundo.name}" :
                  "entrou em grupo, so com #{primeiro.name}")
    true
  rescue => e
    log("falha a entrar: #{e.class}: #{e.message}")
    @activa = false
    false
  end

  def escolher_um(lista, titulo)
    nomes = lista.map { |p| "#{p.name} Nv.#{p.level}" }
    i = pbMessage(titulo, nomes + [_INTL("Desistir")], nomes.length + 1) rescue nomes.length
    return nil if i.nil? || i >= nomes.length
    lista[i]
  rescue
    nil
  end

  def consumir_bilhete!
    ($bag.remove(BILHETE) rescue $PokemonBag.pbDeleteItem(BILHETE)) rescue nil
  end

  # ⚠️ O SALTO TEM DE ESTAR FEITO ANTES DE A ARENA ABRIR.
  #
  # Pôr `player_transferring = true` não muda o mapa: PEDE a mudança, que o
  # motor faz no fim do frame. A arena era montada logo a seguir, ainda no mapa
  # antigo — criava o corpo do treinador nas coordenadas de lá, e só depois o
  # jogador era teleportado. O que se via era o boneco a entrar na caverna
  # partido em dois, com o corpo do treinador deixado para trás.
  #
  # O `transfer_player` dentro do `pbFadeOutIn` faz a mudança ALI, e é o mesmo
  # que o NPC das Raids de Elite já faz para a sala de duelo (mapa 218). Com o
  # ecrã preto por cima, ninguém vê a costura.
  #-----------------------------------------------------------------------------
  # ⚠️ A PORTA E UMA CASA SO, E ELA NAO CABE A DOIS.
  #
  # A entrada e um ponto fixo: toda a gente aterra em (14,13). Com um jogador
  # isso e o que se quer — e a mancha mais aberta do mapa, medida a mao. Com
  # dois, o segundo nasce DENTRO do primeiro, e ficam ali os dois sobrepostos
  # ate um deles andar. O mesmo vale para as setas: quatro casas de seta largam
  # toda a gente na mesma casa do outro lado.
  #
  # Isto corre DEPOIS do salto, ja com o mapa novo carregado — antes dele nao
  # ha como perguntar ao mapa de destino se uma casa e chao.
  #
  # ⚠️ E QUEM SE AFASTA E QUEM CHEGA, e nao quem ja la estava.
  #
  # Assim nao e preciso combinar nada entre as duas maquinas: quem chega ve na
  # lista de peers quem ja esta na casa e escolhe outra. Se chegarem os dois no
  # mesmo instante — que e o unico caso que isto nao apanha — o primeiro passo
  # de qualquer um deles resolve-o, porque a colisao entre jogadores ja existe.
  CHEGADA_VOLTAS = 3      # aneis de casas a procurar a volta da porta

  # ⚠️ E CHEGA-SE DE COSTAS PARA O MAPA, VIRADO PARA A PORTA DE ONDE SE VEIO.
  #
  # As setas do safari nao dizem para que lado virar (o parametro da direccao e
  # 0, "manter"), e o `atravessar!` usa 2 — para baixo — quando nao lhe dizem
  # nada. So que TODAS as chegadas vindas de cima aterram na penultima fila do
  # mapa novo, e a fila abaixo dessa e a seta de volta. Chega-se, fica-se virado
  # para baixo, e a casa da frente e a porta por onde se acabou de entrar.
  #
  # Com o movimento livre nao e preciso andar: o `correr_passagens!` olha para a
  # casa da frente. A unica coisa que adiava o ressalto era a espera de 1,2
  # segundos — e e por isso que se via "aparece la e volta do nada", com um
  # segundo pelo meio.
  #
  # Medido nos quatro mapas: QUINZE das setas aterram assim. Nao e um caso raro,
  # e sao todas as que descem.
  #
  # Vira-se para o lado contrario ao da porta. Se esse tambem der para uma
  # porta — um corredor com saida dos dois lados — tenta-se os outros dois.
  VOLTAS_DIR = { 2 => [0, 1], 4 => [-1, 0], 6 => [1, 0], 8 => [0, -1] }.freeze
  OPOSTA     = { 2 => 8, 8 => 2, 4 => 6, 6 => 4 }.freeze

  def virar_de_costas_para_a_porta!
    return unless $game_map && $game_player
    x = $game_player.x
    y = $game_player.y
    d = ($game_player.direction rescue 2)
    passo = VOLTAS_DIR[d] || [0, 1]
    return unless passagem_na_casa(x + passo[0], y + passo[1])
    ordem = [OPOSTA[d], 4, 6, 2, 8].compact.uniq
    ordem.each do |nd|
      p2 = VOLTAS_DIR[nd]
      next unless p2
      next if passagem_na_casa(x + p2[0], y + p2[1])
      ($game_player.instance_variable_set(:@direction, nd) rescue nil)
      log("cheguei virado para a porta; virei para #{nd}")
      return
    end
  rescue => e
    log("falha a virar na chegada: #{e.class}: #{e.message}")
  end

  def afastar_da_chegada!
    return unless $game_map && $game_player
    virar_de_costas_para_a_porta!
    x = $game_player.x
    y = $game_player.y
    # Aterrar EM CIMA de uma seta e o mesmo problema, por outro caminho: o
    # `correr_passagens!` tambem olha para a casa dos pes.
    return unless alguem_na_casa?(x, y) || passagem_na_casa(x, y)
    (1..CHEGADA_VOLTAS).each do |anel|
      casas = []
      (-anel..anel).each do |dx|
        (-anel..anel).each do |dy|
          next if dx.abs != anel && dy.abs != anel   # so a borda deste anel
          casas << [x + dx, y + dy]
        end
      end
      casas.shuffle!
      casas.each do |(cx, cy)|
        next unless casa_de_chegada?(cx, cy)
        next if alguem_na_casa?(cx, cy)
        ($game_player.moveto(cx, cy) rescue nil)
        log("cheguei a uma casa ocupada; afastei-me para #{cx},#{cy}")
        return
      end
    end
    log("cheguei a uma casa ocupada e nao havia para onde ir")
  rescue => e
    log("falha a afastar da chegada: #{e.class}: #{e.message}")
  end

  def casa_de_chegada?(x, y)
    return false unless $game_map.valid?(x, y)
    return false unless ($game_map.passable?(x, y, 0) rescue false)
    # Nao se aterra em cima de uma seta: era sair pela porta por onde se entrou.
    return false if passagem_na_casa(x, y)
    true
  rescue
    false
  end

  def alguem_na_casa?(x, y)
    aqui = ($game_map.map_id.to_i rescue -1)
    (AnilLanRework.players rescue {}).each_value do |p|
      next unless p && p.respond_to?(:x)
      next unless (p.map_id.to_i == aqui rescue false)
      return true if p.x.to_i == x && p.y.to_i == y
    end
    false
  rescue
    false
  end

  def saltar_para_caverna!
    return false unless mapa
    ida = destino
    alvo = ida[:mapa]
    x, y = ida[:entrada]
    (pbDismountBike rescue nil)
    (FollowingPkmn.toggle_off if defined?(FollowingPkmn)) rescue nil
    pbFadeOutIn(99999) {
      $game_temp.player_new_map_id    = alvo
      $game_temp.player_new_x         = x
      $game_temp.player_new_y         = y
      $game_temp.player_new_direction = 2
      $scene.transfer_player
      $game_map.autoplay
      $game_map.refresh
      afastar_da_chegada!
    }
    ($game_map.map_id == alvo)
  rescue => e
    log("falha a saltar: #{e.class}: #{e.message}")
    false
  end

  #-----------------------------------------------------------------------------
  # O QUE CAI
  #-----------------------------------------------------------------------------
  def escalao_de(nivel)
    escolhido = :verde
    ESCALOES.each { |(min, nome)| escolhido = nome if nivel.to_i >= min }
    escolhido
  end

  # Que caixas é que um Pokémon deste nível pode dar, e qual delas saiu.
  def caixas_ao_alcance(nivel)
    ORDEM_CAIXAS.select do |cor|
      corte = ESCALOES.find { |(_n, c)| c == cor }
      corte && nivel.to_i >= corte[0]
    end
  rescue
    [:verde]
  end

  # Milesimos, como as caixas: com percentagens inteiras o 2,5% da Hyper
  # arredondava e deixava de ser o que esta escrito.
  def sortear_pocao
    POCOES.each do |(item, cura)|
      next unless (GameData::Item.exists?(item) rescue false)
      return item if rand(1000) < (chance_da_pocao(cura) * 10.0)
    end
    nil
  rescue
    nil
  end

  # Quanto e que este sitio paga a mais do que a caverna paga.
  def sorte_daqui
    s = (destino[:sorte] || 1.0).to_f
    (s <= 0.0) ? 1.0 : s
  rescue
    1.0
  end

  # `bonus` e a sorte extra de quem morreu (1.0 para um habitante normal).
  #
  # ⚠️ `sem_topo` fecha a caixa VERMELHA a quem nao tem direito a ela.
  #
  # O chefe fraco e 3% dos habitantes e sorteia tres vezes com o triplo da
  # sorte. Se a vermelha lhe estivesse aberta, ele passava a ser a principal
  # fonte de Masterballs e Pocoes Super Shiny do jogo — mais do que o super, que
  # e vinte vezes mais raro do que ele. Os rarissimos ficam para o dourado.
  def sortear_caixa(nivel, bonus = 1.0, sem_topo = false)
    sorte = sorte_daqui * bonus.to_f
    caixas_ao_alcance(nivel).each do |cor|
      next if sem_topo && cor == :vermelha
      # Milésimos, e não centésimos: com percentagens inteiras a vermelha
      # (0,1%) arredondava para zero e nunca saía.
      return cor if rand(1000) < (CHANCE_CAIXA[cor].to_f * 10.0 * sorte)
    end
    nil
  rescue
    nil
  end

  # ⚠️ De que caixa e que este item veio? Pergunta-se as pools, que sao a
  # unica fonte — assim acrescentar um item a uma pool nao obriga a lembrar-se
  # de mais nada. A vermelha e um Hash (pesos) e as outras sao listas.
  def escalao_do_item(item)
    return nil unless item && defined?(GiftBoxSystem)
    return :vermelha if (GiftBoxSystem::RED_POOL.key?(item) rescue false)
    return :laranja  if Array(GiftBoxSystem::ORANGE_POOL).include?(item)
    return :azul     if Array(GiftBoxSystem::BLUE_POOL).include?(item)
    return :verde    if Array(GiftBoxSystem::GREEN_POOL).include?(item)
    nil
  rescue
    nil
  end

  def sortear_item(escalao)
    return nil unless defined?(GiftBoxSystem)
    case escalao
    when :verde   then Array(GiftBoxSystem::GREEN_POOL).sample
    when :azul    then Array(GiftBoxSystem::BLUE_POOL).sample
    when :laranja then Array(GiftBoxSystem::ORANGE_POOL).sample
    when :vermelha then sortear_com_pesos(GiftBoxSystem::RED_POOL)
    end
  rescue
    nil
  end

  # ⚠️ A POOL VERMELHA TEM PESOS, E IGNORÁ-LOS SERIA DAR MASTERBALLS AO KILO.
  #
  # As outras três são listas simples e um `sample` chega. Esta é um Hash de
  # item => peso, e a soma anda pelos milhares justamente para as coisas raras
  # serem raras. Tratá-la como lista dava a cada entrada a mesma hipótese.
  def sortear_com_pesos(pool)
    return nil unless pool.is_a?(Hash) && !pool.empty?
    total = pool.values.map(&:to_i).reduce(0, :+)
    return nil if total <= 0
    n = rand(total)
    pool.each do |item, peso|
      n -= peso.to_i
      return item if n < 0
    end
    pool.keys.first
  rescue
    nil
  end

  # ⚠️ O ITEM SAI DELE, E NÃO APARECE ONDE ELE ESTAVA.
  #
  # Nascer o item na casa exacta do corpo lê-se mal por duas razões. A primeira
  # é que não se percebe de onde veio: aparece uma bola no chão no instante em
  # que o sprite do Pokémon se desfaz, e as duas coisas confundem-se numa só.
  # A segunda é prática — a casa do corpo é onde o jogador está a bater, e o
  # item nasce debaixo dos pés de quem continua a lutar.
  #
  # Sai para a frente, num arco curto, como se caísse dele. "Curto" é a palavra
  # que interessa: uma casa, duas no máximo. Um chafariz alto atirava o item
  # para dentro de uma parede, ou para o meio dos outros inimigos.
  ALCANCE_QUEDA = 1      # casas à frente do corpo — nunca mais do que isto
  # ⚠️ UMA COISA QUE CAI NAO PARA DE UMA VEZ — RESSALTA.
  #
  # O arco unico punha o item no chao e acabava ali. Lido de fora, isso nao e
  # uma coisa a cair: e uma coisa a ser POUSADA. O que falta e o que acontece
  # depois do impacto — um ressalto curto, com um terco da altura e metade do
  # tempo, e o peso aparece.
  #
  # O som faz a outra metade do trabalho e e o que marca o INSTANTE em que ela
  # toca. Por isso toca na aterragem e nao no lancamento: e a aterragem que se
  # esta a ver.
  CHAFARIZ_VOO   = 0.34   # segundos no ar
  CHAFARIZ_ALTO  = 26.0   # pixeis do ponto mais alto do arco
  CHAFARIZ_TROCO = 0.16   # segundos do ressalto
  CHAFARIZ_TROCA = 8.0    # pixeis do ressalto
  # ⚠️ E CINCO ITENS A CAIR JUNTOS NAO SAO CINCO SONS.
  #
  # Um chefe deixa varias coisas de uma vez, e cinco "toc" no mesmo frame sao um
  # estalo. Um so por janela chega — o que se quer ouvir e que caiu saque, nao
  # quantas unidades.
  QUEDA_PAUSA = 0.12      # segundos entre sons de queda

  #-----------------------------------------------------------------------------
  # A PEPITA
  #
  # ⚠️ SAI DE UMA BOLSA PROPRIA, COMO A CORDA, E PELA MESMA RAZAO.
  #
  # A pepita ja existia — dentro da pool azul, uma entre 49, atras de uma caixa
  # de 2%. Isso da uma a cada 2400 derrotados: ninguem no mundo a viu cair.
  # Subi-la de dentro da pool era pior do que nao a mexer, porque cada ponto que
  # ela ganhasse tirava-o as outras 48 entradas — a Life Orb, a Focus Sash, as
  # TMs. O saque e um bolo de soma fixa.
  #
  # Fora da bolsa do escalao, ela tem a sua propria taxa e nao compete com nada.
  # E o mesmo desenho que ja se tinha usado para a corda de saida, e pela mesma
  # razao que la esta escrita.
  #
  # ⚠️ E NAO E UM ITEM SEGURADO POR NINGUEM.
  #
  # Verificou-se: das 1025 especies do PBS, 303 seguram alguma coisa e NENHUMA
  # segura uma pepita. Ela nao tem outra forma de entrar no jogo por aqui, o que
  # torna este o unico sitio onde faz sentido pola.
  CHANCE_PEPITA = 5      # por cento por derrotado normal
  PEPITA = :NUGGET

  #-----------------------------------------------------------------------------
  # O QUE UM CHEFE PAGA
  #
  # ⚠️ NAO HA TABELA DE CHEFE, HA MAIS BILHETES E UM CHAO.
  #
  # A tentacao e escrever uma pool so para chefes. Seria a mesma tentacao que a
  # nota do `nascer_em!` ja recusou para as especies, e pelo mesmo motivo: duas
  # tabelas divergem, e a que se usa menos e a que se esquece de actualizar.
  #
  # Um chefe sorteia a MESMA tabela mais vezes, e tem um patamar minimo abaixo
  # do qual nao sai. As duas coisas juntas dao o que se quer — ele paga melhor
  # em media E nunca da a sensacao de nao ter valido a pena.
  #
  # ⚠️ O ESCALAO LE-SE DO NIVEL, e isso nao e um truque frágil.
  #
  # Os habitantes normais sobem com os derrotados mas param no `NIVEL_TECTO`,
  # que e 65. Os chefes tem nivel FIXO — 70 e 100 — precisamente porque a nota
  # do `nascer_em!` decidiu que um chefe nao e um habitante mais velho, e um
  # patamar. Logo, nivel >= 70 quer dizer chefe, sem ambiguidade possivel.
  #
  # Ler o nivel em vez de passar a marca poupa mexer em tres assinaturas e no
  # pacote `cav_morte` — o `pkmn` ja viaja em todos eles e ja traz o nivel.
  # ⚠️ A MASTERBALL E AS POCOES SHINY JA ESTAVAM NA MESA — FALTAVA O CHEFE
  # CHEGAR LA.
  #
  # Fui procurar onde acrescentar a Masterball, a Pocao Shiny, a Super Shiny, o
  # Shinycharm e os sete orbes, e encontrei-os todos ja escritos no `RED_POOL`
  # do 068, com pesos pensados (a Super Shiny a 1 em 3300 caixas). Nao ha nada a
  # acrescentar: ha uma caixa vermelha a 0,1% que praticamente nunca sai.
  #
  # Acrescentar uma lista de chefe ao lado era criar uma segunda verdade sobre
  # os mesmos itens — a tentacao que este ficheiro ja recusou duas vezes. O que
  # se mexe e a SORTE do sorteio, e o pool fica a ser o unico dono do que existe
  # e do que e raro.
  #
  # x3 para o chefe e x10 para o super, sobre os bilhetes que ele ja tira:
  #
  #     normal        0,1%  por morte  (1 em 1000)
  #     chefe Nv.70   0,9%  por morte  (3 bilhetes a 0,3%)
  #     super Nv.100  5,8%  por morte  (6 bilhetes a 1,0%)
  #
  # Continua a ser "chance pequena": o super-chefe e 1% dos habitantes, portanto
  # sao precisas ~1700 mortes para uma caixa vermelha por essa via. O que muda e
  # que ela passa a ser uma coisa que se persegue — matar o dourado — em vez de
  # um acidente que acontece a quem calhar.
  CHEFE_SORTE    = { 1 => 3.0, 2 => 10.0 }.freeze         # sorte extra na caixa
  CHEFE_BILHETES = { 1 => 3, 2 => 6 }.freeze              # sorteios de caixa
  CHEFE_MINIMO   = { 1 => :azul, 2 => :laranja }.freeze   # nunca menos que isto
  # ⚠️ AQUI HA UMA TENSAO ENTRE OS DOIS PEDIDOS, E ELA MEDE-SE.
  #
  # Pediu-se "5 pepitas por 100" e pediu-se "chefes a pagar melhor". So que um
  # chefe nao e raro: e 10% dos habitantes. Qualquer pepita que ele traga vale
  # quase duas por 100 no total, e domina a conta.
  #
  # Medido em 200 000 mortes: com os normais a 5% e o chefe a UMA, o conjunto
  # da ~17 por 100. Com o chefe a duas, da ~26.
  #
  # Deixa-se o chefe com uma e o super com quatro. O grosso do que ele paga a
  # mais nao vem daqui — vem dos bilhetes e do chao, que valem muito mais do
  # que uma pepita (um item laranja e uma Rare Candy ou uns Restos).
  #
  # Se o numero que interessa for mesmo 5 no conjunto, o botao e este: pondo o
  # chefe a zero, o total cai para ~5,5 e ele continua a pagar melhor por
  # bilhetes.
  CHEFE_PEPITAS  = { 1 => 1, 2 => 4 }.freeze              # garantidas

  def escalao_do_morto(pkmn)
    n = (pkmn.level.to_i rescue 0)
    # ⚠️ `>=` e nao `==`: o super agora anda entre 100 e 150.
    return 2 if n >= NIVEL_SUPER_MIN
    return 1 if n >= NIVEL_CHEFE
    0
  rescue
    0
  end
  # ⚠️ A CORDA TIRA-SE À SORTE À PARTE, E NÃO DA MESMA BOLSA DO SAQUE.
  #
  # Se ela viesse das pools do escalão, competia com o saque: uma corda no
  # lugar de uma Rare Candy. Pior — como as pools são por escalão, os Pokémon
  # fracos do início dariam cordas de um tipo e os do fundo de outro, e a
  # facilidade de sair mudava com a profundidade sem que isso fosse decisão de
  # ninguém.
  #
  # Ficar sem cordas não é ficar preso: quem cai também sai (deixando tudo), e
  # é essa a segunda saída. Por isso não há garantia nenhuma na primeira morte.
  CHANCE_CORDA = 5       # por cento por derrotado, independente do saque

  # ⚠️ A POCAO NAO E SAQUE: E MUNICAO.
  #
  # Ela nao vai para casa — gasta-se ali, na tecla Q, entre um golpe e o
  # seguinte. Por isso nao entra nas caixas, que sao o premio de levar alguma
  # coisa de la, e cai muito mais vezes do que elas: uma caverna onde nao se
  # pode curar nao e dificil, e curta.
  #
  # ⚠️ E A RARIDADE SAI DA CURA, E NAO DE UMA TABELA ESCRITA A MAO.
  #
  # Cada pocao vale o que enche. A de 20 cai a 15%; as outras caem na mesma
  # proporcao inversa do que curam, portanto uma pocao que cura o triplo aparece
  # um terco das vezes. Assim a VIDA que a caverna oferece por Pokemon
  # derrotado e praticamente a mesma seja qual for a pocao que sai — o que muda
  # e a comodidade de a receber de uma vez.
  #
  #     Potion       20 hp   15,00%
  #     Super Potion 60 hp    5,00%
  #     Hyper Potion 120 hp   2,50%
  #     Max Potion   ~300 hp  1,00%
  #
  # A Max Potion cura tudo, portanto nao tem numero proprio: 300 e o valor
  # nominal que se lhe da para a conta, e da o 1% que se quer para ela.
  #
  # Sorteia-se da melhor para a pior — senao a de 20, que e a mais provavel,
  # levava sempre o lugar antes de as outras serem perguntadas.
  POCAO_BASE_HP     = 20.0
  POCAO_BASE_CHANCE = 15.0   # por cento para a de POCAO_BASE_HP

  POCOES = [
    [:MAXPOTION,   300.0],
    [:HYPERPOTION, 120.0],
    [:SUPERPOTION,  60.0],
    [:POTION,       20.0]
  ].freeze

  def chance_da_pocao(cura)
    POCAO_BASE_CHANCE * (POCAO_BASE_HP / cura.to_f)
  rescue
    0.0
  end

  # Chamado quando um selvagem cai na caverna.
  # `dir` é para onde ele estava virado (2/4/6/8); é para esse lado que as
  # coisas lhe caem da boca.
  def caiu_um!(pkmn, x, y, dir = 2)
    return unless dentro?
    # Conta-se SEMPRE, mesmo quando não cai nada: é o contador que faz o
    # próximo nascer mais forte, e não o saque.
    @abatidos = (@abatidos || 0) + 1
    nivel = (pkmn.level.to_i rescue 5)
    escalao = escalao_do_morto(pkmn)
    saque = []

    # Um normal tira um bilhete; um chefe tira varios da MESMA tabela.
    bilhetes = (escalao > 0) ? CHEFE_BILHETES[escalao].to_i : 1
    bonus = (escalao > 0) ? CHEFE_SORTE[escalao].to_f : 1.0
    # So o chefe fraco tem a vermelha fechada: o normal mantem os seus 0,1%
    # (nao tem sorte extra nenhuma, portanto nao desequilibra nada) e o super
    # e precisamente quem deve pagar os rarissimos.
    sem_topo = (escalao == 1)
    bilhetes.times do
      caixa = sortear_caixa(nivel, bonus, sem_topo)
      next unless caixa
      item = sortear_item(caixa)
      saque << item if item && (GameData::Item.exists?(item) rescue false)
    end

    # ⚠️ E O CHAO: um chefe nunca sai sem nada.
    #
    # Com bilhetes so, um chefe podia falhar os seis e nao deixar nada — e um
    # chefe que nao paga e pior do que um chefe que nao existe, porque o jogador
    # ja pagou o tempo de o matar. O minimo e um item do escalao dele, sorteado
    # da mesma pool, e so entra se os bilhetes nao tiverem dado nada de igual ou
    # melhor.
    if escalao > 0
      minimo = CHEFE_MINIMO[escalao]
      indice = ORDEM_CAIXAS.index(minimo)
      # ⚠️ `index(nil)` devolve nil, e `nil.to_i` e ZERO — que e o indice da
      # caixa VERMELHA. Escrito a pressa, um item que nao esteja em pool
      # nenhuma passava por ser o melhor saque do jogo e o chefe saia sem o
      # minimo dele. Pergunta-se primeiro se ha escalao.
      ja_bom = indice && saque.any? do |it|
        e = escalao_do_item(it)
        i = e && ORDEM_CAIXAS.index(e)
        i && i <= indice
      end
      unless ja_bom
        item = sortear_item(minimo)
        saque << item if item && (GameData::Item.exists?(item) rescue false)
      end
    end

    # As pepitas: taxa propria para os normais, quantidade fixa para os chefes.
    pepitas = (escalao > 0) ? CHEFE_PEPITAS[escalao].to_i :
                              ((rand(100) < CHANCE_PEPITA) ? 1 : 0)
    if pepitas > 0 && (GameData::Item.exists?(PEPITA) rescue false)
      pepitas.times { saque << PEPITA }
    end

    saque << SAIDA if rand(100) < CHANCE_CORDA &&
                      (GameData::Item.exists?(SAIDA) rescue false)
    r = sortear_pocao
    saque << r if r
    return if saque.empty?
    postos = poisos(x, y, dir, saque.length)
    saque.each_with_index do |item, i|
      px, py = postos[i] || [x, y]
      largar_no_chao!(item, px, py, x, y)
      log("nivel #{nivel} deixou #{item} em #{px},#{py}")
    end
  rescue => e
    log("falha no drop: #{e.class}: #{e.message}")
  end

  # ⚠️ UMA CASA OCUPADA NÃO SERVE, E UMA PAREDE MUITO MENOS.
  #
  # O `DroppedItems` põe o evento com `through = false` — sólido — e um item
  # dentro de uma parede fica lá para sempre, visível e impossível de apanhar.
  # Portanto tenta-se a frente, depois as duas diagonais da frente, e só se
  # nenhuma servir é que fica no sítio do corpo, que é feio mas é apanhável.
  def poisos(x, y, dir, quantos)
    dx, dy = case dir
             when 4 then [-1,  0]
             when 6 then [ 1,  0]
             when 8 then [ 0, -1]
             else        [ 0,  1]
             end
    lx, ly = -dy, dx     # o lado, para o leque
    tenta = [[dx, dy], [dx + lx, dy + ly], [dx - lx, dy - ly]]
    bons = []
    tenta.each do |(ax, ay)|
      px = x + (ax * ALCANCE_QUEDA)
      py = y + (ay * ALCANCE_QUEDA)
      next unless casa_livre?(px, py)
      bons << [px, py]
      break if bons.length >= quantos
    end
    bons << [x, y] while bons.length < quantos
    bons
  rescue
    Array.new(quantos) { [x, y] }
  end

  def casa_livre?(x, y)
    return false unless $game_map
    return false if x < 0 || y < 0 || x >= $game_map.width || y >= $game_map.height
    # ⚠️ direcção 2, e nunca 0: com `d = 0` a conta do bit dá `1 << -1` e a casa
    # nunca é passável. Foi o que já pôs o corpo do jogador preso na água.
    return false unless $game_map.passable?(x, y, 2)
    # Nada de dois itens na mesma casa: o de baixo ficava inalcançável.
    return false if $game_map.events.values.any? { |e|
      e && e.x == x && e.y == y && e.name.to_s.start_with?("DroppedItem")
    }
    true
  rescue
    false
  end

  # ⚠️ NASCE NO CHÃO, E NÃO NA MOCHILA.
  #
  # Se fosse direto para a mochila, o jogador ganhava sem se expor — e a regra
  # de perder ao cair deixava de ter dentes, porque bastava matar e correr. No
  # chão, apanhá-lo é uma decisão: pára-se, e enquanto se pára leva-se.
  # ⚠️ UM ITEM QUE SÓ EU VEJO NÃO É UM DROP: É UM DESENHO.
  #
  # A caverna é partilhada, e a regra inteira — "se me vencerem, o que apanhei
  # fica no chão" — só quer dizer alguma coisa se o outro jogador PUDER pegar
  # nele. Com o `spawn_local_item_event` sozinho, o saque nascia na minha
  # máquina e em mais lado nenhum: quem me derrotou via o meu boneco cair e o
  # chão vazio.
  #
  # Quem tem autoridade sobre o chão é o servidor (o `@dropped_items`, com o
  # `claim` a garantir que só um o apanha). Pede-se-lhe que o registe, e ele
  # anuncia o nascimento a toda a gente do canal — a mim inclusive. Por isso
  # NÃO se cria nada localmente aqui: seriam dois itens, e um deles fantasma.
  #
  # Não se espera pela confirmação. O `drop_item_item` do jogo espera porque lá
  # o item saiu da mochila de alguém e tem de voltar se falhar; aqui não saiu de
  # lado nenhum — caiu de um Pokémon — e parar o combate a olhar para o
  # temporizador era pior do que perder um drop de vez em quando.
  def largar_no_chao!(item, x, y, de_x = nil, de_y = nil)
    if (AnilLanRework.connected? rescue false)
      AnilLanRework.connection.send_packet("request_drop_item", {
        "map_id"  => $game_map.map_id,
        "item_id" => item.to_s,
        "x"       => x,
        "y"       => y
      })
      esperar_arco!(item, x, y, de_x, de_y) if de_x
      return
    end
    ev = 900_000 + rand(99_999)
    d = AnilLanRework::DroppedItems
    (d.get_dropped_items[$game_map.map_id] ||= []) << {
      :id => ev, :item_id => item, :x => x, :y => y
    }
    d.spawn_local_item_event(ev, item, x, y)
    fazer_voar!(ev, de_x, de_y, x, y) if de_x
  rescue => e
    log("falha a largar no chao: #{e.class}: #{e.message}")
  end

  # ⚠️ O ARCO ESPERA PELO EVENTO, PORQUE O EVENTO VEM DEPOIS.
  #
  # Pedido o drop ao servidor, o evento nasce quando o `dropped_item_spawn`
  # voltar — daqui a um par de frames, ou a meio segundo se a ligação estiver
  # má. Guarda-se a intenção ("um {item} vai nascer em {x},{y}, vindo dali") e
  # o tick agarra-o mal ele apareça.
  #
  # A espera morre sozinha ao fim de dois segundos: se o servidor recusou o
  # drop, ninguém fica à espera de um evento que nunca vem.
  ESPERA_ARCO = 2.0

  def esperar_arco!(item, x, y, de_x, de_y)
    (@arcos ||= []) << {
      :item => item.to_s, :x => x, :y => y, :ox => de_x, :oy => de_y,
      :ate => Time.now.to_f + ESPERA_ARCO
    }
  rescue
    nil
  end

  def apanhar_arcos!
    return if @arcos.nil? || @arcos.empty?
    agora = Time.now.to_f
    @arcos.reject! { |a| agora >= a[:ate].to_f }
    return if @arcos.empty?
    return unless $game_map
    @voou ||= {}
    achados = []
    @arcos.each do |a|
      alvo = "DroppedItem_#{a[:item]}"
      par = $game_map.events.find { |id, e|
        e && e.x == a[:x] && e.y == a[:y] && !@voou[id] &&
          (e.event && e.event.name.to_s == alvo)
      }
      next unless par
      @voou[par[0]] = true
      fazer_voar!(par[0], a[:ox], a[:oy], a[:x], a[:y])
      achados << a
    end
    achados.each { |a| @arcos.delete(a) }
  rescue
    @arcos = []
  end

  # ⚠️ O EVENTO JÁ ESTÁ NO SÍTIO CERTO; O QUE VOA É O DESENHO DELE.
  #
  # Isto é de propósito, e é o que torna o arco seguro. A casa do evento — o
  # que decide onde se apanha, o que vai na rede para os outros jogadores, o
  # que fica no save — é a de chegada, desde o primeiro frame. O arco mexe só
  # no `@real_x`/`@real_y`, que é a posição em pixeis com que ele se desenha.
  # Se o jogo fechar a meio do voo, ou o jogador sair de mapa, não fica nada
  # por resolver: o item já estava onde havia de estar.
  #
  # É a mesma separação que o chafariz das armadilhas faz no 189.
  # Curto, seco, e um de cada vez.
  def som_da_queda!
    agora = Time.now.to_f
    return if @queda_ate.to_f > agora
    @queda_ate = agora + QUEDA_PAUSA
    (pbSEPlay("Battle ball drop", 55) rescue nil)
  rescue
    nil
  end

  def som_da_apanha!
    (pbSEPlay("GUI storage pick up", 80) rescue nil)
  rescue
    nil
  end

  def fazer_voar!(ev_id, ox, oy, dx, dy)
    e = ($game_map.events[ev_id] rescue nil)
    return unless e
    (@voando ||= []) << {
      :ev => e, :t => 0.0,
      :ox => ox * Game_Map::REAL_RES_X, :oy => oy * Game_Map::REAL_RES_Y,
      :dx => dx * Game_Map::REAL_RES_X, :dy => dy * Game_Map::REAL_RES_Y
    }
  rescue
    nil
  end

  # Corrido pelo tick da arena, que é quem tem o relógio.
  def tick!(delta)
    vigiar_gente!
    apanhar_arcos!
    contar_parado!(delta)
    correr_iman!(delta)
    apanhar_ao_lado!
    correr_pedidos!
    # Corre a cada tick e nao dentro do `apanhar_ao_lado!`: aquele metodo tem
    # saidas antecipadas, e numa sala sem itens nenhuma escada era destrancada.
    atravessar_o_que_nao_e_parede!
    correr_passagens!
    anunciar_dono!
    povoar!
    mover_mobs!
    return if @voando.nil? || @voando.empty?
    fora = []
    @voando.each do |v|
      v[:t] += delta.to_f
      k = v[:t] / CHAFARIZ_VOO
      if k >= 1.0
        # ⚠️ A primeira aterragem nao acaba o voo: comeca o ressalto.
        unless v[:ressaltou]
          v[:ressaltou] = true
          v[:t] = CHAFARIZ_VOO      # o ressalto conta a partir daqui
          som_da_queda!
        end
        r = (v[:t] - CHAFARIZ_VOO) / CHAFARIZ_TROCO
        if r >= 1.0
          fora << v
          # Repor exactamente a casa: um erro de arredondamento aqui deixava o
          # ícone meio pixel ao lado para sempre.
          (v[:ev].instance_variable_set(:@real_x, v[:dx].round) rescue nil)
          (v[:ev].instance_variable_set(:@real_y, v[:dy].round) rescue nil)
          next
        end
        salto = (4.0 * r * (1.0 - r)) * CHAFARIZ_TROCA
        (v[:ev].instance_variable_set(:@real_x, v[:dx].round) rescue nil)
        (v[:ev].instance_variable_set(:@real_y, (v[:dy] - (salto * 4)).round) rescue nil)
        next
      end
      subida = (4.0 * k * (1.0 - k)) * CHAFARIZ_ALTO
      rx = v[:ox] + ((v[:dx] - v[:ox]) * k)
      ry = v[:oy] + ((v[:dy] - v[:oy]) * k) - (subida * 4)
      (v[:ev].instance_variable_set(:@real_x, rx.round) rescue nil)
      (v[:ev].instance_variable_set(:@real_y, ry.round) rescue nil)
    end
    fora.each { |v| @voando.delete(v) }
  rescue
    @voando = []
    @arcos = []
    @voou = {}
  end

  # Cada apanhado na caverna conta para o que se perde ao cair.
  def apanhou!(item)
    return unless dentro?
    @ganho[item] = (@ganho[item] || 0) + 1
  rescue
    nil
  end

  #-----------------------------------------------------------------------------
  # QUEM NASCE LÁ DENTRO
  #
  # ⚠️ O MAPA 303 NÃO TEM TABELA DE ENCONTROS, E NUNCA VAI TER.
  #
  # Era esta a razão de não aparecer um único Pokémon: a arena sabe invocar
  # selvagens (o `spawnar_do_mato!`), mas pergunta-os ao mapa onde está — e o
  # 303 não existe em disco, quanto mais no `encounters.dat`. O
  # `encounter_possible_here?` respondia "não" e o semeador desistia em
  # silêncio, sem um erro.
  #
  # A caverna pede-os ao mapa de onde foi copiada, o Monte Moon, com o
  # `choose_wild_pokemon_for_map` — que existe exactamente para isto. As
  # espécies são as de lá; os níveis são nossos.
  #
  # ⚠️ E O NÍVEL SOBE COM O QUE JÁ SE DERROTOU.
  #
  # Sem isto os escalões de raridade eram código morto: o Monte Moon dá
  # Pokémon de nível 7 a 12, e o primeiro escalão vai até ao 25 — toda a
  # caverna deixaria caixas verdes, para sempre, e as pools azul, laranja e
  # vermelha nunca seriam tocadas. Com o nível a subir a cada abate, descer
  # fundo é o que abre as pools boas, e é isso que dá à caverna uma razão para
  # se ficar lá dentro em vez de entrar e sair com a corda.
  #-----------------------------------------------------------------------------
  # Cinco ao mesmo tempo, um novo a cada dois segundos, era uma enxurrada: o
  # campo enchia mais depressa do que se limpava e não havia como andar.
  # ⚠️ A CAVERNA NASCE POVOADA, E DEPOIS SÓ SE ESVAZIA.
  #
  # Semear ao relógio, à volta de quem joga, tem três defeitos que se veem
  # todos ao mesmo tempo. Nascem em cima do jogador, porque é aí que ele está.
  # Nascem e morrem à vista, porque a conta é de quantos há perto — e isso
  # lê-se como Pokémon a piscar. E não há progresso nenhum: limpar uma sala não
  # muda nada, porque a torneira continua aberta.
  #
  # Uma população fixa, espalhada pelo mapa à entrada, resolve os três de
  # graça. Eles estão lá antes de se chegar, ficam onde estão quando se sai do
  # ecrã, e uma sala limpa fica limpa. Avançar é o que traz mais gente, porque
  # há mais gente adiante — e não porque um relógio disparou.
  #
  # É o mesmo princípio dos Pokémon soltos no mundo: existem, quer se esteja a
  # olhar quer não.
  POPULACAO   = 30     # quantos habitam a caverna
  LONGE_DA_PORTA = 12  # casas: ninguém à espera à entrada
  # O ecrã mostra cerca de 10 casas de largura e 7 de altura a partir do
  # centro. Nascer a 9 ou mais é nascer FORA do que se vê — chegam a andar, e
  # dá para os ouvir vir em vez de aparecerem em cima.
  PERTO_MINIMO = 9     # casas: nunca mais perto do que isto
  LONGE        = 16    # casas: até onde se procura chão livre

  # ⚠️ LIMPAR UMA ZONA TEM DE VALER ALGUMA COISA.
  #
  # Com o semeador a repor por relógio, matar os três da sala não mudava nada:
  # seis segundos depois estava outro em cima do jogador, no mesmo sítio. Não
  # há progresso nenhum nisso — é uma torneira, não uma caverna.
  #
  # A zona é uma âncora: fixa-se onde nasce a primeira vaga, e enquanto o
  # jogador andar por ali não nasce mais ninguém depois dos três. Afastar-se
  # ZONA casas é que abre uma zona nova. Assim limpar a sala esvazia-a mesmo, e
  # avançar é o que traz mais gente — que é o que faz uma caverna ler-se como
  # uma descida e não como uma arena.
  ZONA = 14            # casas do centro da vaga até se considerar outra zona
  NIVEL_BASE  = 12
  NIVEL_PASSO = 3      # por cada derrotado
  NIVEL_TECTO = 65

  def nivel_agora
    n = NIVEL_BASE + ((@abatidos || 0) * NIVEL_PASSO)
    [[n, NIVEL_BASE].max, NIVEL_TECTO].min
  rescue
    NIVEL_BASE
  end

  # ⚠️ SO UMA MAQUINA SEMEIA, E ESCOLHE-SE SEM PERGUNTAR A NINGUEM.
  #
  # Duas maquinas a semear davam duas populacoes: cada um lutava contra os seus
  # e os dois viam-se a bater no vazio. E nao ha aqui um servidor a mandar —
  # este mapa e servido do disco de cada um.
  #
  # O dono e o de id mais baixo entre os que estao la dentro. E uma regra que
  # nao precisa de acordo nenhum: as duas maquinas olham para a mesma lista de
  # pessoas no mapa 303 e chegam a mesma conclusao sozinhas. Quando o dono sai,
  # o seguinte assume no tick a seguir, sem eleicao e sem pacote.
  #
  # E o mesmo desenho do `vower_wild_spawn` do mundo: quem cria, anuncia; os
  # outros repetem o que lhes chega.
  # ⚠️ ESPALHADOS, E NAO ATIRADOS AO ACASO.
  #
  # Trinta casas sorteadas de um saco de 1637 juntam-se em molhos por pura
  # sorte, e ficam buracos enormes noutro sitio. Exige-se uma distancia minima
  # entre eles: cada um afasta os seguintes, e o resultado le-se como uma
  # caverna habitada em vez de um punhado de sal.
  AFASTAMENTO = 6      # casas entre dois habitantes

  # ⚠️ QUEM ACABA DE CHEGAR NAO SABE AINDA QUEM MAIS ESTA LA.
  #
  # O `eu_mando?` compara o meu id com o dos que estao no mapa — e a lista de
  # peers leva um par de segundos a encher depois de uma mudanca de mapa. Nesse
  # intervalo a lista esta vazia, os DOIS jogadores concluem que mandam, e os
  # dois povoam: duas populacoes no mesmo sitio, cada um a lutar com a sua. Foi
  # o que voltou a acontecer.
  #
  # Tres segundos de silencio a chegada resolvem-no sem pacote nenhum: e mais
  # do que o tempo que o mundo leva a dizer quem esta ali, e ninguem da pela
  # espera porque se entra a andar.
  ESPERA_POVOAR = 3.0

  def povoar!
    return unless dentro?
    return if servidor_manda?
    return if @chegada.nil?
    return if (Time.now.to_f - @chegada.to_f) < ESPERA_POVOAR
    return unless eu_mando?
    aqui = ($game_map.map_id rescue MAPA)
    @povoado ||= {}
    return if @povoado[aqui]
    @povoado[aqui] = true
    casas = casas_do_mapa
    if casas.empty?
      log("nao ha chao para povoar o mapa #{MAPA}")
      return
    end
    # A folga da porta so faz sentido onde se entra. No fundo nao ha porta
    # nenhuma — chega-se pelas escadas, e essas ja estao longe de tudo.
    porta = ENTRADAS[aqui] || [-999, -999]
    postos = []
    tentativas = 0
    while postos.length < POPULACAO && tentativas < (POPULACAO * 60)
      tentativas += 1
      c = casas.sample
      next if dist2(c, porta) < (LONGE_DA_PORTA * LONGE_DA_PORTA)
      next if postos.any? { |p| dist2(p, c) < (AFASTAMENTO * AFASTAMENTO) }
      postos << c
    end
    nascidos = 0
    postos.each { |c| nascidos += 1 if nascer_em!(c) }
    log("caverna povoada com #{nascidos} de #{POPULACAO} (#{casas.length} casas de chao)")
  rescue => e
    log("falha a povoar: #{e.class}: #{e.message}")
  end

  def dist2(a, b)
    dx = (a[0] - b[0]).to_f
    dy = (a[1] - b[1]).to_f
    (dx * dx) + (dy * dy)
  rescue
    0.0
  end

  # ⚠️ A LISTA DE CHAO FAZ-SE UMA VEZ E FICA.
  #
  # Sao 7600 casas para perguntar, e a resposta nao muda enquanto se la
  # estiver. Perguntar isto mais do que uma vez por sessao seria desperdicio
  # puro.
  def casas_do_mapa
    aqui = ($game_map.map_id rescue 0)
    @casas ||= {}
    return @casas[aqui] if @casas[aqui]
    fora = []
    return fora unless $game_map
    ($game_map.height).times do |y|
      ($game_map.width).times do |x|
        fora << [x, y] unless (AnilArena.casa_de_pedra?(x, y) rescue true)
      end
    end
    @casas[aqui] = fora
  rescue
    []
  end

  # ⚠️ UM CHEFE E UM HABITANTE COM MAIS ANOS, E NAO UMA CRIATURA A PARTE.
  #
  # A tentacao era uma lista de especies "de chefe" e um sistema proprio. Isso
  # e uma segunda maneira de nascer um Pokemon, com as suas proprias maneiras de
  # correr mal. Um chefe aqui e o mesmo sorteio da tabela com muitos niveis a
  # mais: mais vida, mais dano, e — porque o saque le o nivel — melhores
  # caixas. E le-se de imediato, porque o nome dele aparece quando se aproxima.
  #
  # Um em cada dez habitantes. Com trinta por andar sao tres, o suficiente para
  # se encontrar um sem que deixem de ser um acontecimento.
  # ⚠️ UM CHEFE QUE MORRE A UM GOLPE NAO E UM CHEFE.
  #
  # Subir 18 niveis acima dos vizinhos parecia muito e nao era nada: no andar de
  # cima isso da um Graveler de nivel 35 contra uma equipa que entra ali com o
  # que tem. Um chefe tem de ser uma decisao — parar, ou dar a volta.
  #
  # Sao dois patamares, e nivel FIXO em vez de somado: o chefe e 70, e um em
  # cada dez chefes e um SUPER, de nivel 100. Fixo porque um chefe nao e um
  # habitante crescido, e um marco: quem o encontra tem de saber logo que aquilo
  # nao e para agora, e um numero que depende do que ja se abateu nao diz isso.
  # ⚠️ ERAM 10% E ISSO ENCHIA A MASMORRA DE FALSOS SHINY.
  #
  # A cor de chefe e feita marcando o Pokemon como super shiny — e o unico
  # portao que o motor tem para lhe rodar o matiz do charset (ver a nota em
  # `criar_do_servidor!`). Com um chefe em cada dez habitantes, um decimo de
  # tudo o que anda na masmorra brilha. Do lado de quem joga isso nao se le como
  # "ha muitos chefes": le-se como "ha shiny por todo o lado", e o shiny deixa
  # de valer nada.
  #
  # 4% de chefes, e um quarto deles super: da 3% de chefe fraco e 1% de chefe
  # forte, que sao os numeros pedidos. E, de caminho, o brilho volta a ser raro
  # sem se ter tocado em nada do sistema de shiny.
  CHANCE_CHEFE  = 4     # por cento dos habitantes
  CHANCE_SUPER  = 25    # por cento DOS CHEFES (4% x 25% = 1% do total)
  NIVEL_CHEFE   = 70

  # ⚠️ O CHEFE FORTE PASSA DOS 100, E SO AQUI DENTRO.
  #
  # O tecto de 100 e do jogo todo e nao se mexe: o que se faz e escrever o nivel
  # a mao neste unico sitio. E preciso, porque o `level=` do motor RECUSA:
  #
  #     raise ArgumentError if value > GameData::GrowthRate.max_level
  #
  # Escreve-se o `@level` directamente e recalculam-se os stats — o `calc_stats`
  # le `self.level`, e o getter devolve o `@level` que la esta sem perguntar ao
  # `@exp`. E a mesma tecnica que o PVP de nivel fixo ja usa neste projecto, e
  # pela mesma razao.
  #
  # ⚠️ E NAO VAZA: aqui dentro nao se captura nada. Um destes nunca chega a uma
  # equipa, a um PC nem a um save — a masmorra nao tem bola. Se um dia tiver,
  # este e o primeiro sitio a rever.
  NIVEL_SUPER_MIN = 100
  NIVEL_SUPER_MAX = 150
  NIVEL_SUPER     = NIVEL_SUPER_MIN   # o patamar que distingue um super

  #-----------------------------------------------------------------------------
  # A FORCA DE UM CHEFE
  #
  # ⚠️ MEDI O DANO E A CONTA ESTAVA CERTA. O QUE ESTAVA ERRADO ERA O ADVERSARIO.
  #
  # Com os stats a serio e a formula do jogo, um chefe Nv.70 contra um Venusaur
  # Nv.93 dava isto:
  #
  #     ele bate-me            12% a 19% da minha vida
  #     eu bato-lhe com Power Whip   111% a 165% da vida DELE
  #
  # Ou seja: ele precisa de sete golpes e eu de um. Nao ha nada partido na
  # conta — um nivel 70 e simplesmente mais fraco do que um nivel 93, e a
  # formula esta a dizer a verdade.
  #
  # ⚠️ E PORQUE NAO SE PRENDE O NIVEL DELE AO MEU.
  #
  # A resposta obvia seria "o chefe nasce dez niveis acima do jogador". Nao se
  # pode: na masmorra a dois, o nivel do chefe TEM de dar o mesmo numero nas
  # duas maquinas (e por isso que ele sai da semente, e nao de um `rand`). Se
  # dependesse do nivel de quem olha, dois jogadores de niveis diferentes viam o
  # mesmo monstro com vidas diferentes — o desencontro que esta caverna ja pagou
  # uma vez.
  #
  # O que se faz e o que as raids do jogo ja fazem: multiplicar os stats. E um
  # numero fixo, igual em todas as maquinas, e transforma o chefe num patamar em
  # vez de um habitante mais velho — que e exactamente o que a nota do
  # `nascer_em!` dizia que ele devia ser.
  #
  # Com x2,4 de vida e x1,6 de ataque, aquele mesmo chefe Nv.70 passa a aguentar
  # tres Power Whips e a tirar-me um quarto da vida por golpe. Deixa de ser
  # saque gratis e passa a ser uma decisao.
  # ⚠️ O SUPER NAO LEVA REFORCO DE ATAQUE, E ISSO MEDIU-SE.
  #
  # Comecei por lhe dar x2,0 como ao outro. Medido: um Rhydon Nv.125 assim
  # matava o Venusaur Nv.93 COM UM GOLPE (135% da vida dele) e ainda levava
  # vinte Power Whips a cair. Isso nao e um chefe dificil, e um ecra de fim de
  # jogo com passos extra.
  #
  # O nivel dele ja e o reforco: entre 100 e 150 contra um jogador de 93, a
  # formula sozinha da-lhe 44% a 68% da minha vida por golpe. Multiplicar isso
  # era somar duas vantagens que ja se somam uma vez.
  #
  # Fica so com vida — muita — e bate com o que os stats dele dizem. O que o
  # torna um patamar e o tempo que ele aguenta, nao a velocidade a que mata.
  CHEFE_FORCA = {
    1 => { :vida => 2.4, :ataque => 1.6 },
    2 => { :vida => 2.5, :ataque => 1.0 }
  }.freeze

  # ⚠️ Escreve-se nos stats JA CALCULADOS, e nao nos base stats.
  #
  # Mexer nos base stats era mexer na especie — em TODOS os Pokemon dela, no
  # jogo inteiro, porque o `GameData::Species` e partilhado. Os stats de uma
  # instancia sao dela e de mais ninguem.
  def reforcar_chefe!(pk, escalao)
    f = CHEFE_FORCA[escalao.to_i]
    return pk unless pk && f
    hp = ((pk.totalhp * f[:vida]).round rescue nil)
    if hp && hp > 0
      (pk.instance_variable_set(:@totalhp, hp) rescue nil)
      (pk.instance_variable_set(:@hp, hp) rescue nil)
    end
    [[:@attack, :attack], [:@spatk, :spatk]].each do |(iv, leitor)|
      v = (pk.send(leitor).to_i rescue 0)
      next if v <= 0
      (pk.instance_variable_set(iv, (v * f[:ataque]).round) rescue nil)
    end
    pk
  rescue
    pk
  end

  # Gera um Pokemon que pode estar acima do tecto do jogo.
  def gerar_com_nivel(especie, nivel)
    n = nivel.to_i
    tecto = (GameData::GrowthRate.max_level rescue 100)
    pk = (pbGenerateWildPokemon(especie, [n, tecto].min) rescue nil)
    return nil unless pk
    if n > tecto
      (pk.instance_variable_set(:@level, n) rescue nil)
      (pk.calc_stats rescue nil)
      (pk.heal rescue nil)
    end
    pk
  rescue
    nil
  end

  def nascer_em!(casa)
    tipo = tipo_de_encontro
    return false unless tipo
    # A tabela e a DESTE andar: no fundo os habitantes sao outros.
    aqui = ($game_map.map_id rescue MAPA)
    enc = ($PokemonEncounters.choose_wild_pokemon_for_map(aqui, tipo) rescue nil)
    return false unless enc
    chefe = (rand(100) < CHANCE_CHEFE)
    super_chefe = chefe && (rand(100) < CHANCE_SUPER)
    nivel = if super_chefe
              NIVEL_SUPER_MIN + rand(NIVEL_SUPER_MAX - NIVEL_SUPER_MIN + 1)
            elsif chefe
              NIVEL_CHEFE
            else
              nivel_agora
            end
    # ⚠️ O tecto continua a valer para toda a gente MENOS para o super.
    nivel = 100 if nivel > 100 && !super_chefe
    pk = (gerar_com_nivel(enc[0], nivel) rescue nil)
    return false unless pk
    reforcar_chefe!(pk, super_chefe ? 2 : (chefe ? 1 : 0)) if chefe
    id = (AnilArena.id_de_bicho_livre rescue nil)
    return false unless id
    b = (AnilArena.criar_bicho!(pk, id, LONGE, 1, casa) rescue nil)
    return false unless b
    b[:sid] = novo_sid
    b[:chefe] = (super_chefe ? 2 : 1) if chefe
    anunciar_mob!(b, pk, (super_chefe ? 2 : (chefe ? 1 : 0)))
    log("#{super_chefe ? 'SUPER CHEFE' : 'chefe'}: #{pk.speciesName} Nv.#{nivel}") if chefe
    true
  rescue => e
    log("falha a fazer nascer: #{e.class}: #{e.message}")
    false
  end

  #-----------------------------------------------------------------------------
  # AS ESCADAS
  #
  # ⚠️ ELAS ESTAO LA E SEMPRE ESTIVERAM — O QUE FALTA E QUEM AS PISE.
  #
  # Os eventos das escadas tem `trigger = 1`, que quer dizer "quando o jogador
  # tocar". Quem decide que houve toque e o motor, no fim de um PASSO — e dentro
  # da arena o jogador nao da passos: o movimento livre escreve o `@real_x` a
  # mao, e o `check_event_trigger_here` do motor nunca chega a correr. As
  # escadas ficam desenhadas no chao, visiveis, e mudas.
  #
  # Isto pisa-as por nos: ve se ha uma passagem na casa onde estamos e faz o
  # salto. Le o destino do PROPRIO evento (o comando 201 que la esta), em vez de
  # ter uma tabela de escadas a parte que ficava desactualizada mal alguem
  # mexesse no mapa.
  #-----------------------------------------------------------------------------
  ESPERA_PASSAGEM = 1.2   # segundos antes de a mesma escada valer outra vez

  def passagem_na_casa(x, y)
    return nil unless $game_map
    $game_map.events.each_value do |ev|
      next unless ev && ev.x == x && ev.y == y
      d = destino_da_passagem(ev)
      return [ev, d] if d
    end
    nil
  rescue
    nil
  end

  def destino_da_passagem(ev)
    pg = (ev.event.pages[0] rescue nil)
    return nil unless pg
    (pg.list || []).each do |c|
      next unless c.code.to_i == 201
      p = c.parameters
      return [p[1].to_i, p[2].to_i, p[3].to_i, p[4].to_i]
    end
    nil
  rescue
    nil
  end

  # ⚠️ NAO SE PISA UMA ESCADA: ENCOSTA-SE A ELA.
  #
  # Eu procurava a passagem na casa onde o jogador ESTA, e por isso so as
  # escadas desenhadas em chao andavel e que funcionavam — foi porque as duas
  # de descer sao assim que "descer funcionava e subir nao".
  #
  # As de voltar estao em tiles que o tileset marca como parede. Isso nao e um
  # defeito do mapa: no jogo normal o gatilho e `1 = toque do jogador`, e o
  # motor dispara-o quando se TENTA entrar na casa, mesmo que a entrada seja
  # recusada. Anda-se contra a escada e a passagem abre sem la se chegar a por
  # o pe.
  #
  # Medido nos dois mapas: das quatro chegadas do andar de baixo, TRES nao
  # tinham escada nenhuma na mancha de chao onde caiamos. Nao era um beco por
  # acaso — era o unico caminho de volta a ser uma parede.
  #
  # Portanto olha-se para a casa da frente, que e para onde se esta a andar, e
  # tambem para a de baixo dos pes (algumas sao mesmo pisaveis).
  def casa_a_frente_do_jogador
    d = ($game_player.direction rescue 2)
    dx = (d == 6) ? 1 : ((d == 4) ? -1 : 0)
    dy = (d == 2) ? 1 : ((d == 8) ? -1 : 0)
    [$game_player.x + dx, $game_player.y + dy]
  rescue
    [$game_player.x, $game_player.y]
  end

  def correr_passagens!
    return unless dentro?
    return unless $game_player && $game_map
    agora = Time.now.to_f
    return if agora < @passagem_ate.to_f
    fx, fy = casa_a_frente_do_jogador
    achado = passagem_na_casa(fx, fy)
    achado ||= passagem_na_casa($game_player.x, $game_player.y)
    return unless achado
    _ev, destino = achado
    mapa, x, y, dir = destino
    return unless MAPAS.include?(mapa)
    @passagem_ate = agora + ESPERA_PASSAGEM
    atravessar!(mapa, x, y, dir)
  rescue => e
    log("falha na passagem: #{e.class}: #{e.message}")
  end

  # ⚠️ O ANDAR VELHO FICA PARA TRAS INTEIRO.
  #
  # Os eventos morrem com o mapa, mas as listas sao nossas: os bichos da arena,
  # os arcos de itens a espera, quem estava na sala. Levar isso para o andar
  # seguinte deixava trinta fichas a apontar para eventos mortos.
  def atravessar!(mapa, x, y, dir)
    log("passagem para o mapa #{mapa} (#{x},#{y})")
    (pbSEPlay("Exit Door") rescue nil)
    (AnilArena.largar_bichos! rescue nil)
    # O boneco do ajudante fica no mapa velho; a ficha dele nao. Sem isto ele
    # deixava de seguir depois de uma escada.
    (AnilArena.esquecer_boneco_do_aliado! rescue nil)
    @voando = []
    @arcos  = []
    @voou   = {}
    @gente  = nil
    @mob_avisado = 0
    pbFadeOutIn(99999) {
      ($game_temp.player_new_map_id    = mapa) rescue nil
      ($game_temp.player_new_x         = x) rescue nil
      ($game_temp.player_new_y         = y) rescue nil
      ($game_temp.player_new_direction = (dir.to_i > 0 ? dir.to_i : 2)) rescue nil
      ($scene.transfer_player rescue nil)
      ($game_map.autoplay rescue nil)
      ($game_map.refresh rescue nil)
      afastar_da_chegada!
    }
    @chegada = Time.now.to_f
    true
  rescue => e
    log("falha a atravessar: #{e.class}: #{e.message}")
    false
  end

  #-----------------------------------------------------------------------------
  # QUEM MANDA NO MATO
  #
  # ⚠️ ISTO ERA UMA ELEICAO A CADA TICK, E ERA ESSE O ERRO DE FUNDO.
  #
  # O `eu_mando?` comparava o meu id com os da lista de peers, e era chamado em
  # cinco sitios — um deles sete vezes por segundo. Ou seja: a autoridade era
  # RECALCULADA para sempre, e a lista de peers e a coisa menos estavel que ha
  # aqui dentro. Ela esvazia-se numa mudanca de mapa, volta a encher-se um
  # segundo depois, perde alguem por um `player_disconnect` de troca de andar,
  # e durante um instante tem o proprio jogador la dentro por engano.
  #
  # Cada um desses instantes virava uma mudanca de governo. Dois clientes a
  # concluir que mandam ao mesmo tempo semeiam os dois; dois a concluir que nao
  # mandam deixam os bichos sem ninguem a mexe-los. E isso a alternar varias
  # vezes por segundo — a "guerra de IA".
  #
  # ⚠️ A CORRECCAO NAO E UMA ELEICAO MELHOR: E DEIXAR DE HAVER ELEICOES.
  #
  # Elege-se UMA vez, guarda-se a chave, e ela so muda quando ha um motivo
  # nomeado: o dono saiu da caverna, ou apareceu alguem com mais direito e disse
  # isso em voz alta. Enquanto o dono estiver ca e a falar, ninguem reconta
  # nada — e a lista de peers pode tremer o que quiser.
  #
  # O anuncio e a peca que torna isto solido. Sem ele, quem chega a caverna nao
  # sabe que ja ha dono e elege-se a si proprio; com ele, basta ouvir uma vez.
  #-----------------------------------------------------------------------------
  DONO_ANUNCIO  = 1.0    # segundos entre dois anuncios de quem manda
  # ⚠️ QUATRO SEGUNDOS ERA CURTO DE MAIS, E O LOG MOSTRA PORQUE.
  #
  # A caverna trocou de dono duas vezes numa sessao de dois minutos, e as duas
  # por "quem mandava calou-se ha 4.0s". Nao se calou: os pacotes dele tiveram
  # um intervalo maior do que quatro segundos — o que ja tinhamos medido no log
  # de rede, com falhas de 2,4 a 7,2 segundos no fluxo da caverna.
  #
  # Cada troca destas custava a populacao inteira: quem retomava semeava outros
  # trinta, e ao devolver a posse largava-os. Dez segundos e mais largo do que
  # qualquer falha que medimos e continua a ser curto para quem saiu de verdade.
  DONO_SILENCIO = 10.0   # sem sinal nenhum do dono durante isto, a posse volta

  # ⚠️ A POSSE E UM NUMERO SORTEADO, PORQUE O NOME NAO E DE CONFIANCA.
  #
  # A regra anterior era "o id menor manda", e para a aplicar cada maquina
  # precisa de saber o SEU proprio id. Medido nos logs: os dois clientes
  # anunciaram-se donos ao mesmo tempo, 1 vez por segundo, a sessao inteira, e
  # os dois semearam 30 bichos. Nenhum cedeu.
  #
  # A razao e mais funda do que esta regra. O servidor renomeia o cliente depois
  # de validar a whitelist (`rename_registered_client`) e o `join_ack` nao lhe
  # devolve o nome novo: o cliente fica a achar-se uma coisa enquanto toda a
  # gente lhe chama outra. Foi isso que meteu o proprio jogador na lista de
  # peers dele — as quatro portas que criam peers comparam com o
  # `self_internal_id` e a comparacao falhava sempre.
  #
  # Portanto tira-se o nome da equacao. Cada maquina sorteia um numero a
  # entrada e leva-o no anuncio; o MENOR manda. Cada uma compara o numero que
  # recebe com o seu — ninguem precisa de saber quem e, so de comparar dois
  # numeros. Simetrico, deterministico, e imune ao desencontro de ids.
  #
  # Quando o servidor devolver o id certo no `join_ack` (duas linhas, quando se
  # quiser), isto continua a funcionar tal e qual — nao passa a depender disso.
  # ⚠️ O `rand` DESTE JOGO NAO E DE CONFIANCA PARA ISTO.
  #
  # O projecto tem um gerador sincronizado entre clientes para as batalhas
  # serem deterministas (o MOD 000d substitui o `rand` por um contador com uma
  # semente partilhada). Duas maquinas em coop podem, portanto, tirar o MESMO
  # numero — e duas posses iguais e o unico caso em que a regra do menor nao
  # desempata nada.
  #
  # Com numeros iguais os dois lados chegam a mesma conclusao ao mesmo tempo, e
  # a conclusao pode ser "o outro manda" nos dois — que da o oposto do que se
  # quer: ninguem semeia, ou os dois voltam a reclamar quatro segundos depois,
  # em ciclo.
  #
  # A posse passa a ser construida de coisas que NAO podem coincidir entre duas
  # maquinas: o relogio ao microssegundo, o identificador do objecto em memoria,
  # e o nome do jogador. Mesmo que o `rand` esteja semeado igual dos dois lados,
  # estes tres nao estao.
  def minha_posse
    return @posse if @posse
    semente = (Time.now.to_f * 1_000_000).to_i
    semente ^= (object_id.to_i * 2_654_435_761)
    semente ^= (AnilLanRework.self_internal_id.to_s.each_byte.inject(17) { |a, b| ((a * 31) + b) & 0x3FFFFFFF } rescue 0)
    semente ^= (AnilLanRework.self_name.to_s.each_byte.inject(7) { |a, b| ((a * 31) + b) & 0x3FFFFFFF } rescue 0)
    @posse = (semente & 0x3FFFFFFF)
    log("a minha posse desta sessao e #{@posse}")
    @posse
  rescue
    @posse = rand(1_000_000_000)
  end

  def meu_id
    (AnilLanRework.self_internal_id.to_s rescue "")
  rescue
    ""
  end

  # ⚠️ "SOZINHO" E NAO ESTAR LIGADO. NAO SABER O PROPRIO NOME NAO E SOLIDAO.
  #
  # A versao anterior tratava um id vazio como "estou sozinho, logo mando eu" —
  # e como o id esta errado nas duas maquinas, as duas mandavam sempre. Um id
  # que falta e uma avaria, nao uma ausencia de companhia.
  #-----------------------------------------------------------------------------
  # QUANDO O SERVIDOR MANDA
  #
  # ⚠️ TUDO O QUE ESTA ABAIXO DESTA LINHA DEIXA DE CORRER.
  #
  # A posse, o numero sorteado, a prova de vida, o handover, o semeador — foram
  # cinco tentativas de simular uma autoridade que nao existia. Existindo, nao
  # se afinam: desligam-se. Ficam no ficheiro porque o servidor pode nao ter o
  # modulo (uma versao antiga, o ficheiro em falta), e nesse caso a caverna
  # volta ao que era em vez de ficar sem bichos nenhuns.
  #
  # A deteccao e pelo comportamento e nao por uma opcao: se chegam pacotes do
  # servidor sobre bichos, ele manda. Se pararem de chegar durante
  # SERVIDOR_SILENCIO, volta-se ao modo antigo. Nao ha interruptor para alguem
  # se esquecer de ligar.
  #-----------------------------------------------------------------------------
  SERVIDOR_SILENCIO = 8.0

  def servidor_manda?
    return false if @servidor_visto.nil?
    (Time.now.to_f - @servidor_visto.to_f) < SERVIDOR_SILENCIO
  rescue
    false
  end

  def servidor_falou!
    primeira = !servidor_manda?
    @servidor_visto = Time.now.to_f
    return unless primeira
    log("o SERVIDOR passou a mandar nos bichos — a posse local desliga-se")
    # Largar o que semeamos por nossa conta: a partir daqui a populacao e a
    # dele, e duas populacoes e o defeito que isto veio resolver.
    (AnilArena.largar_bichos! rescue nil)
    @povoado = {}
  rescue
    nil
  end

  #-----------------------------------------------------------------------------
  # ⚠️ O SERVIDOR MANDA UMA SEMENTE, E NAO UM GEODUDE.
  #
  # Ele nao tem o PBS nem as tabelas de especies, e nao vale a pena ensina-lo:
  # a tabela de encontros do mapa 303 ja esta em TODOS os clientes, igual, no
  # mesmo `encounters.dat`. O que viaja e um numero; cada cliente resolve-o na
  # sua tabela e chega ao mesmo Pokemon, porque a conta e a mesma e a tabela e
  # a mesma.
  #
  # E o que mantem o modulo do servidor com trezentas linhas em vez de tres
  # mil, e o que faz uma especie nova no PBS aparecer na caverna sem se tocar
  # no servidor.
  #-----------------------------------------------------------------------------
  def especie_da_semente(semente, chefe)
    tipo = tipo_de_encontro
    return nil unless tipo
    aqui = ($game_map.map_id rescue MAPA)
    dados = (GameData::Encounter.get(aqui, ($PokemonGlobal.encounter_version rescue 0)) rescue nil)
    lista = (dados ? dados.types[tipo] : nil)
    return nil if lista.nil? || lista.empty?
    total = lista.inject(0) { |a, e| a + e[0].to_i }
    return nil if total <= 0
    alvo = semente.to_i % total
    corrido = 0
    escolhida = lista.last
    lista.each do |e|
      corrido += e[0].to_i
      if alvo < corrido
        escolhida = e
        break
      end
    end
    lo = escolhida[2].to_i
    hi = escolhida[3].to_i
    hi = lo if hi < lo
    nivel = lo + ((semente.to_i / 977) % ((hi - lo) + 1))
    # ⚠️ O NIVEL DO SUPER SAI DA SEMENTE, E NAO DE UM `rand`.
    #
    # Este caminho e o do servidor: todas as maquinas resolvem o MESMO bicho a
    # partir do mesmo numero. Um `rand` aqui dava um nivel diferente em cada
    # ecra — o mesmo monstro com vidas diferentes em cada lado, que e a familia
    # de defeito que esta caverna ja pagou uma vez.
    #
    # O 1013 e primo e diferente do 977 usado acima para o nivel normal: com o
    # mesmo divisor, o nivel do super ficava preso ao nivel que ele teria se nao
    # fosse super.
    if chefe.to_i == 2
      vao = NIVEL_SUPER_MAX - NIVEL_SUPER_MIN + 1
      nivel = NIVEL_SUPER_MIN + ((semente.to_i / 1013) % vao)
    elsif chefe.to_i == 1
      nivel = NIVEL_CHEFE
    end
    tecto = (chefe.to_i == 2) ? NIVEL_SUPER_MAX : 100
    [escolhida[1], [[nivel, 1].max, tecto].min]
  rescue => e
    log("falha a resolver a especie: #{e.class}: #{e.message}")
    nil
  end

  #-----------------------------------------------------------------------------
  # OS TRES PACOTES DO SERVIDOR
  #-----------------------------------------------------------------------------
  # ⚠️ `cav_nascer` E O ESTADO COMPLETO, E NAO "os novos".
  #
  # Faz-se a populacao local ficar IGUAL a lista: cria-se o que falta, apaga-se
  # o que sobra. O mesmo pacote serve para o povoamento, para a reposicao a
  # meio e para quem chega tarde — e nao ha maneira de as duas listas
  # divergirem, porque uma e copia da outra.
  def receber_cav_nascer!(p)
    return unless dentro?
    servidor_falou!
    lista = p["lista"]
    return unless lista.is_a?(Array)
    querem = {}
    lista.each do |l|
      next unless l.is_a?(Array) && l.length >= 6
      querem[l[0].to_i] = l
    end

    # Fora os que o servidor ja nao tem.
    (AnilArena.bichos rescue []).dup.each do |b|
      next unless b && b[:sid]
      next if querem.key?(b[:sid].to_i)
      (AnilArena.apagar_por_sid!(b[:sid]) rescue nil)
    end

    # Dentro os que faltam.
    querem.each_value do |l|
      sid = l[0].to_i
      next if (AnilArena.bicho_por_sid(sid) rescue nil)
      criar_do_servidor!(sid, l[1].to_f, l[2].to_f, l[3].to_i, l[4].to_i, l[5].to_i)
    end
    log("populacao do servidor: #{querem.length} bichos")
  rescue => e
    log("falha no cav_nascer: #{e.class}: #{e.message}")
  end

  # ⚠️ UM CHEFE DE NIVEL 70 COM O SPRITE DE UM DE NIVEL 13 NAO E UM CHEFE.
  #
  # Eles estavam a nascer — um em cada dez, e um em cada dez desses de nivel
  # 100 — e ninguem deu por nenhum. Nao ha porque dar: um Graveler de 70 e
  # exactamente igual a um Graveler de 15 no mapa. So se descobria que era
  # chefe ao bater nele e ver que nao morria, o que e a pior altura para
  # descobrir.
  #
  # A cor resolve-o sem sprites novos e sem codigo novo: o motor ja sabe rodar
  # o matiz de um charset (e o que faz um shiny), e isso ja viaja no evento.
  # Um chefe e roxo, um super-chefe e dourado, e a diferenca ve-se do outro
  # lado da sala.
  HUE_CHEFE = 280
  HUE_SUPER = 45

  def criar_do_servidor!(sid, x, y, dir, chefe, semente)
    par = especie_da_semente(semente, chefe)
    return unless par
    pk = (gerar_com_nivel(par[0], par[1]) rescue nil)
    return unless pk
    reforcar_chefe!(pk, chefe.to_i) if chefe.to_i > 0
    # ⚠️ O matiz vai pelo POKEMON e nao pelo evento: o `criar_bicho!` le o
    # `super_shiny_hue` dele para pintar o charset, e assim nao e preciso um
    # caminho novo so para isto.
    # ⚠️ ISTO NUNCA PINTOU NADA, E EU SO DEI POR ELA AGORA.
    #
    # Eu escrevia `@super_shiny_hue`. Esse ivar nao existe: o que o Pokemon tem
    # e `@cached_super_shiny_hue`. E, pior, o metodo que le a cor comeca assim:
    #
    #     def super_shiny_hue
    #       return 0 if !super_shiny?
    #       return @cached_super_shiny_hue if @cached_super_shiny_hue
    #
    # Ou seja, havia DOIS portoes fechados: o ivar errado e, antes dele, a
    # condicao de ser super shiny — que um chefe normal nao era. A cor saia
    # sempre 0 e o charset nunca era rodado. Os chefes existiam, com o nivel
    # certo e a vida certa, e eram visualmente iguais a um Geodude qualquer.
    #
    # Marca-se o Pokemon como super shiny (e o que abre o portao) e escreve-se o
    # ivar certo (e o que escolhe a cor). Nao ha risco de isto vazar para o
    # jogo: aqui dentro nao se captura nada, e o anuncio de shiny do mundo passa
    # pelo `pbPlaceEncounter`, que esta bloqueado na masmorra.
    if chefe.to_i > 0
      hue = (chefe.to_i == 2) ? HUE_SUPER : HUE_CHEFE
      (pk.super_shiny = true) rescue nil
      (pk.shiny = true) rescue nil
      (pk.cached_super_shiny_hue = hue) rescue nil
    end
    id = (AnilArena.id_de_bicho_livre rescue nil)
    return unless id
    b = (AnilArena.criar_bicho!(pk, id, LONGE, 1, [x.round, y.round]) rescue nil)
    return unless b
    b[:sid] = sid
    if chefe.to_i > 0
      b[:chefe] = chefe.to_i
      log("#{chefe.to_i == 2 ? 'SUPER CHEFE' : 'chefe'}: #{pk.speciesName} Nv.#{pk.level} em #{x.round},#{y.round}")
    end
    (AnilArena.pousar_por_sid!(sid,
      (x * Game_Map::REAL_RES_X).round,
      (y * Game_Map::REAL_RES_Y).round, dir) rescue nil)
    b
  rescue => e
    log("falha a criar do servidor: #{e.class}: #{e.message}")
    nil
  end

  # ⚠️ O RETRATO VEM EM CENTESIMOS DE CASA.
  #
  # O servidor guarda a posicao em casas com decimais (mais legivel e mais
  # barato de mover); o jogo desenha em `real_x`, que sao 128 unidades por
  # casa. A conversao faz-se aqui, uma vez, em vez de o servidor ter de saber o
  # que e um `REAL_RES_X`.
  def receber_cav_snap!(p)
    return unless dentro?
    servidor_falou!
    lista = p["lista"]
    return unless lista.is_a?(Array)
    lista.each do |l|
      next unless l.is_a?(Array) && l.length >= 4
      (AnilArena.pousar_por_sid!(l[0],
        ((l[1].to_f / 100.0) * Game_Map::REAL_RES_X).round,
        ((l[2].to_f / 100.0) * Game_Map::REAL_RES_Y).round,
        l[3].to_i) rescue nil)
    end
  rescue
    nil
  end

  # A morte tambem e dele. O saque sai aqui, mas so na maquina de quem bateu —
  # o servidor diz quem foi, e assim nao ha dois saques pelo mesmo cadaver.
  def receber_cav_morte!(p)
    return unless dentro?
    servidor_falou!
    sid = p["sid"]
    b = (AnilArena.bicho_por_sid(sid) rescue nil)
    pkmn = (b ? b[:pkmn] : nil)
    (AnilArena.apagar_por_sid!(sid) rescue nil)
    meu = (AnilLanRework.self_internal_id.to_s rescue "")
    return unless p["quem"].to_s == meu && !meu.empty?
    @abatidos = (@abatidos || 0) + 1
    caiu_um!(pkmn, p["x"].to_f.round, p["y"].to_f.round, p["dir"].to_i) if pkmn
  rescue => e
    log("falha no cav_morte: #{e.class}: #{e.message}")
  end

  # ⚠️ QUEM BATE DIZ QUANTO; A VIDA E DELE.
  def bati_no_bicho!(sid, dano)
    return unless servidor_manda?
    return unless (AnilLanRework.connected? rescue false)
    AnilLanRework.connection.send_packet("cav_dano",
      { "sid" => sid.to_i, "dano" => dano.to_i })
  rescue
    nil
  end

  def eu_mando?
    return true unless (AnilLanRework.connected? rescue false)
    return true if @posse_alheia.nil?
    # A posse alheia caducou: quem a tinha calou-se ou saiu.
    if (Time.now.to_f - @posse_visto.to_f) > DONO_SILENCIO
      log("quem mandava calou-se ha #{DONO_SILENCIO}s — a posse volta para mim")
      @posse_alheia = nil
      return true
    end
    false
  rescue
    true
  end


  # O dono diz que e o dono, uma vez por segundo. E o que impede quem chega de
  # se eleger a si proprio por nao saber que ja ha um.
  def anunciar_dono!
    return unless dentro?
    return if servidor_manda?
    return unless eu_mando?
    agora = Time.now.to_f
    return if (agora - @dono_dito.to_f) < DONO_ANUNCIO
    @dono_dito = agora
    falar!("caverna_dono", { "posse" => minha_posse })
  rescue
    nil
  end

  # ⚠️ QUEM TEM MAIS DIREITO GANHA, E QUEM TEM MENOS LARGA SEM DISCUTIR.
  #
  # A regra e a mesma dos dois lados (o id menor manda), portanto nao ha
  # negociacao: quem ouve um id menor do que o dono que tem, aceita-o. Se eu
  # proprio era o dono, largo — e largo tambem os bichos que semeei, senao
  # ficavam duas populacoes, que e o defeito que isto veio resolver.
  # ⚠️ QUEM TEM O NUMERO MENOR MANDA, E QUEM TEM O MAIOR LARGA SEM DISCUTIR.
  #
  # Os dois lados correm esta mesma linha e chegam a conclusoes opostas — que e
  # exactamente o que se quer de uma regra de desempate. Nao ha negociacao, nao
  # ha ida e volta, e nao ha um terceiro a arbitrar.
  def receber_dono!(p)
    return unless dentro?
    dele = p["posse"]
    # Anuncio de um cliente antigo, sem numero: trata-se como o mais fraco, para
    # nunca destronar quem ja esta a semear.
    dele = 2_000_000_000 if dele.nil?
    dele = dele.to_i
    agora = Time.now.to_f

    if dele > minha_posse
      # Ele e mais fraco: nao muda nada aqui. Ele proprio vai largar quando
      # ouvir o meu anuncio.
      @recusas = (@recusas || 0) + 1
      log("recusei a posse de #{p['sender_id']} (#{dele} > #{minha_posse})") if @recusas <= 3
      return
    end

    # ⚠️ EMPATE: NENHUM DOS DOIS PODE LARGAR.
    #
    # Se os numeros forem iguais e os dois largarem, ficamos sem ninguem a
    # semear — que e pior do que dois. Desempata-se pelo nome, e se ate o nome
    # for igual (dois clientes com o mesmo id, que ja aconteceu neste projecto)
    # fica quem ja tinha: mudar por mudar nao resolve nada.
    if dele == minha_posse
      outro = p["sender_id"].to_s
      meu = (AnilLanRework.self_internal_id.to_s rescue "")
      log("EMPATE de posse (#{dele}) com #{outro}: desempate pelo nome (#{meu} vs #{outro})")
      return if meu.empty? || meu <= outro
    end

    # Ele manda. Se ja era ele, so se renova o relogio.
    if @posse_alheia == dele
      @posse_visto = agora
      return
    end

    era_meu = eu_mando?
    @posse_alheia = dele
    @posse_visto = agora
    log("a posse do mato e de #{p['sender_id']} (numero #{dele} contra o meu #{minha_posse})")
    if era_meu
      aqui = ($game_map.map_id rescue MAPA)
      quantos = (AnilArena.largar_bichos! rescue 0)
      (@povoado || {})[aqui] = false
      log("larguei os meus #{quantos} bichos: quem semeia agora e o outro")
    end
  rescue
    nil
  end

  def semear!(delta)
    return unless dentro?
    return unless (AnilArena.activa? rescue false)
    return unless $game_player
    return unless eu_mando?
    @semente = (@semente || 0.0) + delta.to_f
    return if @semente < SEMEAR_CADA
    @semente = 0.0

    px = $game_player.x
    py = $game_player.y
    # Longe da âncora? Então isto é outra zona, e a conta recomeça.
    if @ancora
      dx = (px - @ancora[0]).to_f
      dy = (py - @ancora[1]).to_f
      if Math.sqrt((dx * dx) + (dy * dy)) >= ZONA
        @ancora = nil
        @na_zona = 0
        log("zona nova em #{px},#{py}")
      end
    end

    vivos = (AnilArena.bichos_vivos.length rescue 0)
    return if vivos >= ALVO_VIVOS
    # ⚠️ A conta é dos NASCIDOS na zona, e não dos que estão de pé. Se fosse
    # dos vivos, matar um chamava outro — que é exactamente o que se queria
    # deixar de fazer.
    return if @ancora && (@na_zona || 0) >= ALVO_VIVOS

    return unless nascer_um!
    @ancora ||= [px, py]
    @na_zona = (@na_zona || 0) + 1
  rescue => e
    log("falha a semear: #{e.class}: #{e.message}")
  end

  # ⚠️ O MONTE MOON E `Cave`, NAO `Land`. ERA ISTO QUE MATAVA O SEMEADOR.
  #
  # Eu tinha escrito `:Land` por hábito, e o `choose_wild_pokemon_for_map`
  # devolve `nil` para um tipo que a tabela não tem — em silêncio, dentro de um
  # `rescue`. Nem um Pokémon, nem uma linha no log.
  #
  # Agora não se adivinha: pergunta-se à tabela do próprio mapa quais os tipos
  # que ela tem e usa-se o primeiro que preste. Se amanhã a caverna passar a
  # ser copiada de um mapa de relva, isto continua a funcionar sozinho.
  PREFERE = [:Cave, :Land, :CaveClassic, :LandDay, :LandNight].freeze

  def tipo_de_encontro
    aqui = ($game_map.map_id rescue MAPA)
    @tipo_enc ||= {}
    return @tipo_enc[aqui] if @tipo_enc[aqui]
    dados = (GameData::Encounter.get(aqui, ($PokemonGlobal.encounter_version rescue 0)) rescue nil)
    tipos = (dados ? dados.types.keys : [])
    escolhido = PREFERE.find { |k| tipos.include?(k) } || tipos.first
    log("tipo de encontro do mapa #{aqui}: #{escolhido.inspect} (tinha #{tipos.inspect})")
    @tipo_enc[aqui] = escolhido
  rescue => e
    log("falha a achar o tipo de encontro: #{e.class}: #{e.message}")
    nil
  end

  def nascer_um!
    tipo = tipo_de_encontro
    unless tipo
      log("sem tabela de encontros para o mapa #{($game_map.map_id rescue MAPA)} — ninguem vai nascer")
      return false
    end
    aqui = ($game_map.map_id rescue MAPA)
    enc = ($PokemonEncounters.choose_wild_pokemon_for_map(aqui, tipo) rescue nil)
    unless enc
      log("a tabela #{tipo} do mapa #{aqui} nao deu ninguem")
      return false
    end
    pk = (pbGenerateWildPokemon(enc[0], nivel_agora) rescue nil)
    return false unless pk
    id = (AnilArena.id_de_bicho_livre rescue nil)
    return false unless id
    b = (AnilArena.criar_bicho!(pk, id, LONGE, PERTO_MINIMO) rescue nil)
    return false unless b
    b[:sid] = novo_sid
    anunciar_mob!(b, pk)
    log("nasceu #{pk.speciesName} Nv.#{pk.level} (#{b[:sid]})")
    true
  rescue => e
    log("falha a fazer nascer: #{e.class}: #{e.message}")
    false
  end

  #-----------------------------------------------------------------------------
  # APANHAR
  #
  # ⚠️ NA CAVERNA NÃO SE CARREGA NUMA TECLA PARA APANHAR.
  #
  # O item do chão é um evento com gatilho de botão: chega-se ao pé, vira-se
  # para ele e carrega-se em C. Isso é o mundo normal, onde se está parado e a
  # decidir. Aqui está-se a fugir de três Pokémon ao mesmo tempo, e parar para
  # alinhar o boneco com uma casa é como não poder apanhar de todo — foi o que
  # se viu: "não está a pegar os itens".
  #
  # Encosta-se, e é seu. A recolha continua a passar pelo `pickup_item` de
  # sempre, que pede autorização ao servidor: sem isso, dois jogadores na mesma
  # caverna apanhavam ambos a mesma coisa.
  #-----------------------------------------------------------------------------
  ESPERA_APANHA = 1.0    # segundos antes de voltar a tentar o mesmo evento

  # ⚠️ O ITEM DO CHÃO ESTAVA A TAPAR A CASA INTEIRA.
  #
  # O `spawn_local_item_event` põe o evento com `through = false` — sólido — e
  # de propósito: no mundo normal é isso que faz o jogador parar à frente dele
  # para carregar em C. Só que sólido quer dizer a CASA toda, 32 px, para um
  # ícone que nem isso ocupa, e num corredor de caverna é uma pedra no caminho.
  # Era isto o "não consigo passar por cima dos itens".
  #
  # Aqui não é preciso nada disso: apanha-se ao encostar. Portanto o item passa
  # a não ter colisão nenhuma — nem a do sprite, nem a da casa. Faz-se no
  # próprio evento e na página dele, porque o `refresh` volta a ler a página.
  # ⚠️ A SETA DA ESCADA ERA SOLIDA, E POR ISSO NUNCA SE CHEGOU A PISA-LA.
  #
  # Isto e a explicacao inteira de "as setas nao aparecem para entrar". Elas
  # aparecem — o que nao se consegue e ir para cima delas. O evento tem
  # `through = false` e um `character_name`, e o `passable?` do motor tem esta
  # linha:
  #
  #     return false if self != $game_player || event.character_name != ""
  #
  # Um evento com desenho de personagem barra a casa mesmo ao jogador. No jogo
  # normal isso nao se nota, porque a passagem dispara no TOQUE — anda-se contra
  # ela, o motor da o passo por dentro e o mapa muda antes de o bloqueio contar.
  # Aqui o movimento e livre e nao ha toque nenhum: fica-se encostado a uma seta
  # que nao deixa passar e nao faz nada.
  #
  # A seta passa a ser atravessavel, como os itens do chao. O `correr_passagens!`
  # e que decide o que acontece quando se esta em cima dela.
  def atravessar_o_que_nao_e_parede!
    return unless $game_map
    # ?? Cada evento e olhado UMA vez. O `destino_da_passagem` percorre a
    # lista de comandos da pagina, e isto corre a cada tick com quarenta
    # eventos no mapa ? sem esta memoria eram milhares de leituras por segundo
    # para responder sempre o mesmo.
    @vistos ||= {}
    chave_mapa = ($game_map.map_id rescue 0)
    if @vistos_mapa != chave_mapa
      @vistos_mapa = chave_mapa
      @vistos = {}
    end
    $game_map.events.each_pair do |eid, e|
      next unless e && e.event
      next if @vistos[eid]
      @vistos[eid] = true
      nome = e.event.name.to_s
      passagem = !destino_da_passagem(e).nil?
      next unless nome.start_with?("DroppedItem") || passagem
      next if (e.instance_variable_get(:@through) rescue false)
      (e.instance_variable_set(:@through, true) rescue nil)
      pag = (e.event.pages[0] rescue nil)
      (pag.through = true) if pag
    end
  rescue
    nil
  end

  #-----------------------------------------------------------------------------
  # O IMAN
  #
  # ⚠️ UM ITEM ONDE NAO SE CHEGA E UM ITEM QUE NAO EXISTE.
  #
  # O saque cai na casa onde o Pokemon caiu, e essa casa nao escolhe: e do outro
  # lado de uma cerca, no meio de agua, numa saliencia. Do lado de quem joga
  # isso nao se le como "tive azar" — le-se como o jogo a mostrar um premio e a
  # nao o dar. E nao ha nada a fazer quanto a isso: nao se pode saltar a cerca.
  #
  # A saida nao e impedir que caia la — e deixar ir busca-lo com o tempo. Quem
  # PARA ao pe dele puxa-o. Parar e o custo: a masmorra e um sitio onde estar
  # quieto e perigoso, portanto isto nao e de graca, e um segundo e meio e tempo
  # que chega para se ser encontrado.
  #
  # Puxa-se a casa do evento e nao so o desenho — de proposito, ao contrario do
  # arco da queda. O arco e um enfeite e a casa verdadeira e a de chegada; aqui
  # o item esta MESMO a vir ter connosco, e quem decide a apanha e a casa. Assim
  # a apanha acontece pelo caminho de sempre, com a autorizacao do servidor, e
  # nao ha um segundo caminho para o mesmo item entrar na mochila.
  #-----------------------------------------------------------------------------
  IMAN_RAIO   = 4.5     # casas: ate onde o iman puxa
  IMAN_ESPERA = 1.5     # segundos parado antes de comecar a puxar
  IMAN_VEL    = 3.2     # casas por segundo a vir

  def contar_parado!(delta)
    return unless $game_player
    rx = ($game_player.instance_variable_get(:@real_x) rescue 0)
    ry = ($game_player.instance_variable_get(:@real_y) rescue 0)
    if @iman_rx == rx && @iman_ry == ry
      @parado_ha = (@parado_ha || 0.0) + delta.to_f
    else
      @parado_ha = 0.0
      @iman_rx = rx
      @iman_ry = ry
    end
  rescue
    nil
  end

  def correr_iman!(delta)
    return unless dentro?
    return unless $game_map && $game_player
    return if @parado_ha.to_f < IMAN_ESPERA
    prx = ($game_player.instance_variable_get(:@real_x) rescue 0).to_f
    pry = ($game_player.instance_variable_get(:@real_y) rescue 0).to_f
    passo = IMAN_VEL * delta.to_f * Game_Map::REAL_RES_X
    limite = IMAN_RAIO * Game_Map::REAL_RES_X
    $game_map.events.each_value do |e|
      next unless e && e.event
      next unless e.event.name.to_s.start_with?("DroppedItem")
      rx = (e.instance_variable_get(:@real_x) rescue 0).to_f
      ry = (e.instance_variable_get(:@real_y) rescue 0).to_f
      dx = prx - rx
      dy = pry - ry
      n = Math.sqrt((dx * dx) + (dy * dy))
      next if n > limite || n < 1.0
      andar = (passo > n) ? n : passo
      nx = rx + ((dx / n) * andar)
      ny = ry + ((dy / n) * andar)
      (e.instance_variable_set(:@real_x, nx.round) rescue nil)
      (e.instance_variable_set(:@real_y, ny.round) rescue nil)
      (e.instance_variable_set(:@x, (nx / Game_Map::REAL_RES_X.to_f).round) rescue nil)
      (e.instance_variable_set(:@y, (ny / Game_Map::REAL_RES_Y.to_f).round) rescue nil)
      (e.calculate_bush_depth rescue nil)
    end
  rescue => e
    log("falha no iman: #{e.class}: #{e.message}")
  end

  def apanhar_ao_lado!
    return unless dentro?
    return unless $game_map && $game_player
    atravessar_o_que_nao_e_parede!
    agora = Time.now.to_f
    @tentado ||= {}
    px = $game_player.x
    py = $game_player.y
    $game_map.events.each do |id, e|
      next unless e && e.event
      next unless e.event.name.to_s.start_with?("DroppedItem")
      next if ((e.x - px).abs + (e.y - py).abs) > 1
      next if agora < @tentado[id].to_f
      @tentado[id] = agora + ESPERA_APANHA
      pedir_item!(id, item_do_evento(e))
      return
    end
  rescue
    nil
  end

  def item_do_evento(e)
    id = (e.instance_variable_get(:@visible_item_id) rescue nil)
    return id if id
    nome = (e.event.name.to_s rescue "")
    return nil unless nome =~ /\ADroppedItem_(.+)\z/
    $1.to_sym
  rescue
    nil
  end

  # ⚠️ PEDE-SE E SEGUE-SE. A RESPOSTA CHEGA QUANDO CHEGAR.
  #
  # O `pickup_item` do jogo faz tres coisas que aqui saem caras: espera pela
  # resposta do servidor com o jogo parado (ate 5 s), grava e SOBE o save, e
  # abre uma caixa de dialogo. Era isso o "lag absurdo ao pegar um item" — e
  # nenhuma das tres e precisa a meio de uma luta.
  #
  # O que se mantem e o que importa: a autorizacao continua a ser do servidor,
  # senao dois jogadores na mesma caverna apanhavam ambos a mesma coisa. So que
  # em vez de esperar por ela, guarda-se o pedido e le-se a caixa de correio no
  # tick seguinte. O item entra na mochila quando o servidor disser que sim.
  #
  # O evento desaparece do MEU ecra logo — senao ficava ali um item que eu ja
  # pedi, e eu voltava a pedi-lo. Se o servidor recusar, ele fica no chao para
  # quem o apanhou primeiro, que e a verdade do que aconteceu.
  ESPERA_RESPOSTA = 6.0

  def pedir_item!(ev_id, item)
    return unless item
    d = AnilLanRework::DroppedItems
    unless (AnilLanRework.connected? rescue false)
      ($bag.add(item) rescue nil)
      (d.remove_dropped_item(ev_id) rescue nil)
      anunciar_apanha!(item)
      return
    end
    (d.esquecer_claim(ev_id) rescue nil)
    AnilLanRework.connection.send_packet("claim_dropped_item", {
      "map_id"   => $game_map.map_id.to_s,
      "event_id" => ev_id
    })
    (@pedidos ||= {})[ev_id] = {
      :item => item, :ate => Time.now.to_f + ESPERA_RESPOSTA
    }
    (d.remove_dropped_item(ev_id) rescue nil)
  rescue => e
    log("falha a pedir item: #{e.class}: #{e.message}")
  end

  def correr_pedidos!
    return if @pedidos.nil? || @pedidos.empty?
    agora = Time.now.to_f
    @pedidos.keys.each do |ev_id|
      p = @pedidos[ev_id]
      next unless p
      r = (AnilLanRework::DroppedItems.colher_claim(ev_id) rescue nil)
      if r
        @pedidos.delete(ev_id)
        if r["success"]
          ($bag.add(p[:item]) rescue nil)
          anunciar_apanha!(p[:item])
        else
          log("#{p[:item]} ja tinha sido apanhado por outro")
        end
      elsif agora >= p[:ate].to_f
        # Sem resposta: nao se inventa o item. Ele ficou no chao para os
        # outros, e nesta maquina ja nao se ve — e o preco de nao esperar.
        @pedidos.delete(ev_id)
        log("sem resposta do servidor sobre #{p[:item]}")
      end
    end
  rescue
    @pedidos = {}
  end

  # ⚠️ UM AVISO, E NAO UMA CAIXA DE DIALOGO.
  #
  # O `pbMessage` PARA o jogo e espera que se carregue numa tecla. A meio de
  # uma luta em tempo real isso e pior do que nao dizer nada: o jogador leva
  # golpes enquanto le. A linha da arena diz o mesmo e nao interrompe.
  def anunciar_apanha!(item)
    nome = (GameData::Item.get(item).name rescue item.to_s)
    (AnilArena.dizer(_INTL("Pegou: {1}", nome)) rescue nil)
    # ⚠️ `GUI boot selection` NAO EXISTE NESTE JOGO.
    #
    # Havia som de apanha desde o principio — so que aponta para um ficheiro
    # que nao esta no Audio/SE. O `pbSEPlay` levanta, o `rescue nil` engole, e
    # o resultado e um silencio que parece deliberado. Era isto o "nao ha
    # barulho quando pega o item": nao faltava o som, faltava o ficheiro.
    som_da_apanha!
  rescue
    nil
  end

  #-----------------------------------------------------------------------------
  # UMA SÓ POPULAÇÃO
  #
  # ⚠️ O QUE VIAJA É O SUFICIENTE PARA O OUTRO CRIAR O MESMO BICHO — E MAIS NADA.
  #
  # Espécie, nível, forma, género e brilho: com isso o `pbGenerateWildPokemon`
  # do outro lado faz um Pokémon igual. O que NÃO viaja são os atributos que
  # ninguém vê (IVs, natureza exacta, movimentos) — eles só mudam contas que
  # cada máquina faz para o seu próprio ecrã, e mandá-los era engordar um
  # pacote que sai a cada nascimento.
  #-----------------------------------------------------------------------------
  MOVER_CADA = 8       # frames entre avisos de posição (60/8 ≈ 7 por segundo)

  # ⚠️ O NOME DE UM BICHO NA REDE NAO PRECISA DE CONTAR A HISTORIA DELE.
  #
  # Era `wallace-adm100_1757462400.123_4821`: 38 bytes com o dono e o relogio
  # dentro. Isso e util num sistema aberto onde qualquer um cria a qualquer
  # momento; aqui ha UM criador de cada vez e no maximo trinta bichos. Um numero
  # chega, e os 38 bytes viravam 2 — repetidos por bicho e por pacote de
  # posicoes, eram 1 140 dos 1 603 bytes desse pacote.
  #
  # Se o dono mudar a meio (o primeiro saiu), o novo continua a contar acima do
  # maior numero que ja viu, em vez de recomecar do um e baptizar dois bichos
  # com o mesmo nome.
  def novo_sid
    @sid_seguinte ||= 0
    @sid_seguinte += 1
  end

  def anotar_sid!(sid)
    n = sid.to_i
    @sid_seguinte = n if n > @sid_seguinte.to_i
  rescue
    nil
  end

  # ⚠️ SEM `x`/`y`, DE PROPOSITO.
  #
  # O servidor decide a entrega pelo que vem no pacote: com `map_id` E
  # coordenadas, entrega so a quem estiver a menos de 25 casas de quem falou;
  # so com `map_id`, entrega ao mapa inteiro.
  #
  # Para os golpes a primeira regra e a certa — um golpe a 40 casas nao
  # interessa a ninguem. Para os bichos e o contrario: um nascimento perdido
  # nunca mais se repete, e o jogador que estava longe ficava para sempre sem
  # aquele Pokemon na lista dele. O mapa e uma sala so, e estes tres pacotes
  # (nascer, mover, morrer) sao para a sala toda.
  def falar!(tipo, dados)
    return unless (AnilLanRework.connected? rescue false)
    return unless $game_map
    AnilLanRework.connection.send_packet(tipo, dados.merge(
      "caverna" => true,
      "map_id"  => $game_map.map_id))
  rescue => e
    log("falha a falar #{tipo}: #{e.class}: #{e.message}")
  end

  def anunciar_mob!(b, pk, chefe = 0)
    ev = b[:ev]
    return unless ev
    dados = {
      "sid"     => b[:sid],
      "especie" => (pk.species.to_s rescue ""),
      "nivel"   => (pk.level.to_i rescue 5),
      "forma"   => (pk.form.to_i rescue 0),
      "genero"  => (pk.gender.to_i rescue 0),
      "brilho"  => ((pk.shiny? rescue false) ? 1 : 0),
      "mx"      => ev.x,
      "my"      => ev.y
    }
    dados["chefe"] = chefe.to_i if chefe.to_i > 0
    falar!("caverna_mob", dados)
  rescue
    nil
  end

  # ⚠️ CRIA-SE COM O `criar_bicho!` DE SEMPRE E DEPOIS MUDA-SE DE SITIO.
  #
  # O `criar_bicho!` escolhe a casa a partir de quem o chama, e aqui a casa ja
  # esta decidida — foi o dono que a escolheu. Criar e mudar e feio mas e
  # honesto: nao ha um segundo caminho de criacao para manter afinado com o
  # primeiro (o sprite, o hue, a pagina do evento, o registo na lista).
  def receber_mob!(p)
    return unless dentro?
    # ⚠️ REDE DE SEGURANCA: SE DOIS POVOARAM, UM DEITA FORA O QUE FEZ.
    #
    # A espera de tres segundos resolve o caso normal, mas nao ha promessa
    # nenhuma de que resolva sempre — uma ligacao lenta, um mapa a carregar
    # devagar. Se eu povoei e chega um nascimento de OUTRA pessoa, um de nos
    # esta a mais; desiste quem tem o id maior, que e a mesma regra do
    # `eu_mando?` e portanto os dois chegam a mesma conclusao.
    # ⚠️ UM NASCIMENTO NAO E UMA RECLAMACAO DE POSSE — E UMA PROVA DE VIDA.
    #
    # Eu mandava isto pelo `receber_dono!`, e como um `caverna_mob` nao leva
    # numero de posse ele era tratado como o mais fraco possivel: o log encheu-
    # se de "recusei a posse de gaby (2000000000 > ...)" a cada nascimento. Nao
    # fazia mal, mas tambem nao fazia o que interessava — renovar o relogio.
    sinal_do_dono!
    aqui = ($game_map.map_id rescue MAPA)
    if (@povoado || {})[aqui] && !eu_mando?
      log("outro povoou este andar: largo os meus e fico com os dele")
      (AnilArena.largar_bichos! rescue nil)
      (@povoado || {})[aqui] = false
    end
    sid = p["sid"].to_s
    return if sid.empty?
    return if (AnilArena.bicho_por_sid(sid) rescue nil)
    especie = p["especie"].to_s
    return if especie.empty?
    pk = (gerar_com_nivel(especie.to_sym, p["nivel"].to_i) rescue nil)
    return unless pk
    # ⚠️ O REFORCO TEM DE SER FEITO AQUI TAMBEM, E ESTE E O SITIO MAIS FACIL DE
    # ESQUECER.
    #
    # Ha tres portas por onde um chefe nasce: a minha (`nascer_em!`), a do
    # servidor (`criar_do_servidor!`) e esta — o nascimento anunciado por OUTRO
    # jogador. Reforcar so as duas primeiras dava um chefe com o triplo da vida
    # na maquina de quem o semeou e com a vida normal na de quem o viu nascer.
    #
    # Os dois batiam no mesmo bicho e contavam vidas diferentes: um via-o cair,
    # o outro via-o de pe. E a mesma familia de desencontro que o nivel pela
    # semente ja evita — nao vale a pena evita-lo num sitio e deixa-lo noutro.
    (reforcar_chefe!(pk, p["chefe"].to_i) rescue nil) if p["chefe"].to_i > 0
    (pk.form = p["forma"].to_i) rescue nil
    (pk.shiny = true) if p["brilho"].to_i == 1 && pk.respond_to?(:shiny=)
    id = (AnilArena.id_de_bicho_livre rescue nil)
    return unless id
    b = (AnilArena.criar_bicho!(pk, id, LONGE, 1) rescue nil)
    return unless b
    b[:sid] = sid
    b[:chefe] = p["chefe"].to_i if p["chefe"].to_i > 0
    anotar_sid!(sid)
    (AnilArena.pousar_por_sid!(sid,
      p["mx"].to_i * Game_Map::REAL_RES_X,
      p["my"].to_i * Game_Map::REAL_RES_Y, 2) rescue nil)
    log("chegou #{especie} Nv.#{p['nivel']} (#{sid})")
  rescue => e
    log("falha a receber mob: #{e.class}: #{e.message}")
  end

  # ⚠️ AS POSICOES SAO DO DONO, E SO ELE AS MANDA.
  #
  # Cada maquina corre a IA dos bichos no seu ecra — e o que os faz atacar quem
  # esta a jogar NELA, e sem isso os inimigos so lutavam contra uma pessoa. O
  # que se sincroniza e onde eles estao: entre a minha conta e a do dono, ganha
  # a do dono. E o mesmo compromisso do `vower_wild_move`.
  def mover_mobs!
    return if servidor_manda?
    return unless eu_mando?
    agora = (Graphics.frame_count rescue 0)
    return if (agora - @mob_avisado.to_i) < MOVER_CADA
    @mob_avisado = agora
    # ⚠️ QUEM ESTA PARADO NAO PRECISA DE DIZER QUE CONTINUA PARADO.
    #
    # Dos trinta habitantes, uns tres estao acordados: acima de `DESPERTA` o
    # `mover_bicho!` nem lhes toca, e mandar as coordenadas deles sete vezes por
    # segundo e repetir um numero que nao mudou. Eram 12 kB/s a dizer nada.
    #
    # ⚠️ E O CRITERIO E "ACORDADO PARA ALGUEM", NAO "ACORDADO PARA MIM".
    #
    # O dono so mexe os que estao perto DELE. Se so mandasse esses, o outro
    # jogador via parados os que so ele tem por perto — e esses sao precisamente
    # os que o estao a atacar. Quem esta perto de qualquer pessoa na caverna
    # entra na lista.
    lista = []
    gente = postos_da_gente
    (AnilArena.bichos rescue []).each do |b|
      ev = b[:ev]
      next unless ev && b[:sid]
      next unless perto_de_alguem?(ev, gente)
      lista << [b[:sid].to_i,
                (ev.instance_variable_get(:@real_x) rescue 0),
                (ev.instance_variable_get(:@real_y) rescue 0),
                (ev.direction rescue 2)]
    end
    return if lista.empty?
    # Um pacote com todos, e nao um por bicho: sao tres bichos, e tres pacotes
    # de sete em sete frames e o triplo do trabalho para a mesma informacao.
    falar!("caverna_mobs", { "lista" => lista })
  rescue
    nil
  end

  # As casas de toda a gente que esta na caverna, eu incluido. Refeita a cada
  # aviso (7,5 por segundo) porque as pessoas andam — sao duas ou tres entradas.
  def postos_da_gente
    fora = []
    fora << [$game_player.x, $game_player.y] if $game_player
    (AnilLanRework.players rescue {}).each_value do |p|
      next unless p
      next unless (p.map_id.to_i == ($game_map.map_id.to_i) rescue false)
      fora << [p.x.to_i, p.y.to_i] rescue nil
    end
    fora
  rescue
    [[$game_player.x, $game_player.y]]
  end

  # O mesmo raio que o 189 usa para decidir quem se mexe, com uma casa de folga:
  # um bicho que acaba de entrar no alcance de alguem ja viaja no aviso anterior.
  RAIO_AVISO = 18

  def perto_de_alguem?(ev, gente)
    ex = ev.x
    ey = ev.y
    gente.any? { |(gx, gy)| ((ex - gx).abs + (ey - gy).abs) <= RAIO_AVISO }
  rescue
    true
  end

  # ⚠️ O DONO PROVA QUE ESTA VIVO DE TODAS AS MANEIRAS, E NAO SO A DIZE-LO.
  #
  # O relogio da posse so era renovado pelo `caverna_dono`, um pacote por
  # segundo. Se esse se perdesse tres vezes seguidas — e perde-se, o fluxo da
  # caverna tem falhas de segundos — o dono era dado como ido, embora as
  # posicoes dos bichos dele estivessem a chegar sem parar, sete vezes por
  # segundo, mesmo ali ao lado.
  #
  # Qualquer coisa que venha dele serve de prova: posicoes, nascimentos,
  # mortes. Isto sozinho torna a troca de posse muito mais rara do que o
  # aumento do tempo — sao sete provas por segundo em vez de uma.
  def sinal_do_dono!
    @posse_visto = Time.now.to_f unless eu_mando?
  rescue
    nil
  end

  def receber_mobs!(p)
    return unless dentro?
    sinal_do_dono!
    lista = p["lista"]
    return unless lista.is_a?(Array)
    lista.each do |linha|
      next unless linha.is_a?(Array) && linha.length >= 4
      (AnilArena.pousar_por_sid!(linha[0], linha[1], linha[2], linha[3]) rescue nil)
    end
  rescue
    nil
  end

  # ⚠️ QUEM MATA AVISA TODA A GENTE; QUEM SEMEOU E QUE SORTEIA O SAQUE.
  #
  # Sao duas decisoes diferentes e so uma delas e partilhada. A morte tem de
  # chegar aos dois ecras, senao um continua a bater num bicho que o outro ja
  # enterrou. O saque e uma so — se cada maquina sorteasse o seu, dois jogadores
  # produziam o dobro dos itens.
  def morreu!(sid, pkmn, x, y, dir = 2)
    return unless dentro?
    falar!("caverna_morte", { "sid" => sid.to_s }) if sid
    caiu_um!(pkmn, x, y, dir) if eu_mando?
  rescue => e
    log("falha a anunciar a morte: #{e.class}: #{e.message}")
  end

  def receber_morte!(p)
    return unless dentro?
    sinal_do_dono!
    (AnilArena.apagar_por_sid!(p["sid"].to_s) rescue nil)
  rescue
    nil
  end

  #-----------------------------------------------------------------------------
  # QUEM MAIS ESTÁ CÁ
  #
  # ⚠️ A PRESENÇA NÃO PRECISA DE PACOTE NENHUM. JÁ ESTÁ NO ECRÃ.
  #
  # A tentação era mandar um "entrei na caverna" a toda a gente e outro ao
  # sair. Seria um tipo de pacote novo, uma rota nova, e duas maneiras novas de
  # a lista ficar errada: quem entrasse a seguir não recebia o aviso de quem já
  # lá estava, e um jogador que caísse a ligação ficava na lista para sempre.
  #
  # A informação já viaja — o mundo diz em que mapa cada um está, e é por isso
  # que se vêem uns aos outros. Basta olhar para essa lista a cada tick e dizer
  # o que mudou desde o tick anterior. Quem chega, quem sai e quem desliga são
  # todos o mesmo acontecimento, e nenhum deles precisa de ser anunciado por
  # quem o faz.
  #
  # A caverna é o mapa 303 para toda a gente, e por isso é a MESMA instância no
  # servidor: o espaço é partilhado de origem, não é uma cópia por jogador.
  #-----------------------------------------------------------------------------
  def gente_ca
    return {} unless dentro?
    fora = {}
    (AnilLanRework.players rescue {}).each do |id, p|
      next unless p
      # Quem esta no OUTRO andar nao esta aqui: nao se ve, nao se acerta, e nao
      # entra na conta de quem manda no mato deste andar.
      next unless (p.map_id.to_i == ($game_map.map_id.to_i) rescue false)
      fora[id.to_s] = (p.name.to_s rescue "")
    end
    fora
  rescue
    {}
  end

  def vigiar_gente!
    return unless dentro?
    agora = gente_ca
    antes = @gente || {}
    # A primeira volta não anuncia nada: seria dar as boas-vindas a quem já lá
    # estava antes de nós, e isso diz-se de outra maneira (ver o `entrar!`).
    if @gente.nil?
      @gente = agora
      contar_quem_ca_esta!
      return
    end
    (agora.keys - antes.keys).each do |id|
      nome = agora[id]
      nome = _INTL("Alguém") if nome.empty?
      if amigo?(id)
        (AnilArena.dizer(_INTL("{1} entrou com você.", nome)) rescue nil)
      else
        (AnilArena.dizer(_INTL("{1} entrou na caverna!", nome)) rescue nil)
      end
      (pbSEPlay("GUI menu open") rescue nil)
    end
    (antes.keys - agora.keys).each do |id|
      nome = antes[id]
      next if nome.empty?
      (AnilArena.dizer(_INTL("{1} saiu da caverna.", nome)) rescue nil)
    end
    @gente = agora
  rescue
    nil
  end

  # ⚠️ UMA CAIXA DE TEXTO TAPA OS BOTOES, E ESTA APARECIA A CADA PASSAGEM.
  #
  # Isto era dito uma vez, a chegada, quando a masmorra era um mapa so. Com as
  # areas do safari ha uma chegada por cada seta atravessada — e o que se via
  # era o `pbMessage` a abrir em baixo, em cima dos golpes, a meio de uma luta
  # que nao parou para esperar por ele. Numa arena em tempo real uma caixa
  # modal e sempre a coisa errada: ela pede um carregar de botao a quem esta
  # ocupado a nao morrer.
  #
  # O aviso passa para o `dizer` da arena — a linha no TOPO do ecra, que ja e
  # por onde passa tudo o resto ("Fulano entrou na caverna!", "Refletido!") e
  # que se apaga sozinha ao fim de segundo e meio.
  #
  # E o "esta sozinho" diz-se uma vez por VISITA e nao uma vez por area: a
  # segunda vez que ele aparece ja nao informa nada, so repete.
  def contar_quem_ca_esta!
    lista = gente_ca.values.reject { |n| n.empty? }
    if lista.empty?
      return if @disse_sozinho
      @disse_sozinho = true
      (AnilArena.dizer(_INTL("Você está sozinho aqui.")) rescue nil)
    else
      @disse_sozinho = false
      (AnilArena.dizer(_INTL("Aqui com você: {1}. Cuidado.", lista.join(", "))) rescue nil)
    end
  rescue
    nil
  end

  #-----------------------------------------------------------------------------
  # A MOCHILA E A EQUIPA SÃO DE LÁ, E SÓ DE LÁ
  #
  # ⚠️ NÃO SE FILTRA O ECRÃ DA MOCHILA: TROCA-SE A MOCHILA.
  #
  # A tentação era esconder na interface o que veio de fora. Isso é uma mentira
  # que se desfaz sozinha — o primeiro sítio que leia `$bag` sem passar pelo
  # filtro (um golpe que usa Berry, o menu rápido, um plugin) devolve a poção
  # que era suposto não existir aqui. Filtrar é preciso acertar em todos os
  # sítios; trocar é acertar num.
  #
  # Lá dentro `$bag` é uma mochila NOVA e vazia, e a equipa são os dois que
  # entraram. Sai-se com o que se apanhou, ou não se sai com nada.
  #
  # ⚠️ E O QUE FICOU DE FORA VIAJA NO SAVE.
  #
  # Esta é a parte que não pode falhar. Se a mochila verdadeira vivesse só numa
  # variável deste módulo, um fecho do jogo lá dentro — um crash, a luz a ir
  # abaixo, o Android a matar a aplicação — levava a mochila inteira do
  # jogador. Guardada no `$PokemonGlobal`, ela vai no save como tudo o resto, e
  # o `vigiar_regresso!` devolve-a no arranque seguinte.
  #-----------------------------------------------------------------------------
  def guardar_amigo!
    id = (AnilLanRework.coop_party_partner_id rescue nil)
    @amigo = (id.nil? ? nil : id.to_s)
    @amigo = nil if @amigo && @amigo.empty?
    nome = @amigo ? ((AnilLanRework.players[@amigo].name rescue "?")) : "ninguem"
    log("entrou em grupo com #{nome} (#{@amigo.inspect})")
    @amigo
  rescue => e
    log("falha a guardar o parceiro: #{e.class}: #{e.message}")
    @amigo = nil
  end

  # O id anotado a porta manda. Se por alguma razao nao houver nenhum (entrou-se
  # sozinho e o grupo fez-se depois), ainda se aceita o que o coop disser agora.
  def amigo_id
    return @amigo if @amigo && !@amigo.empty?
    id = (AnilLanRework.coop_party_partner_id rescue nil)
    return nil if id.nil?
    t = id.to_s
    t.empty? ? nil : t
  rescue
    nil
  end

  def amigo?(id)
    return false if id.nil?
    a = amigo_id
    return false unless a
    a == id.to_s
  rescue
    false
  end

  # ⚠️ UM INSTRUMENTO QUE E PRECISO LEMBRAR DE LIGAR NAO E MEDIDO.
  #
  # Os dois logs nascem desligados de proposito — eles pesam cada pacote do jogo
  # inteiro enquanto correm, e isso nao pode ficar ligado para toda a gente. Mas
  # quem entra na caverna JA passou pela porta do amuleto, e e exactamente a
  # sessao que queremos medir. Ligam-se sozinhos a entrada e desligam-se a
  # saida, que e quando o ficheiro fica pronto para ler.
  #
  # `/arenalog off` continua a valer: quem quiser medir sem eles, desliga.
  # ⚠️ OS TRES LOGS JA DERAM O QUE TINHAM A DAR, E CUSTAM ONDE MAIS DOI.
  #
  # Foram eles que encontraram a trava de 45 ms do servidor, o jogador na sua
  # propria lista de peers e o `largar_bichos!` a deixar bonecos no mapa. Mas
  # enquanto correm pesam CADA pacote do jogo inteiro — e o aparelho onde isso
  # mais se sente e exactamente o mais fraco.
  #
  # Deixam de arrancar sozinhos. Continuam a um comando de distancia
  # (`/arenalog`, `/movlog`, `/intrusolog`) para a proxima vez que houver uma
  # pergunta que so eles respondam.
  def ligar_logs!
    log("logs desligados por omissao — /arenalog, /movlog, /intrusolog para os ligar")
  rescue
    nil
  end

  def desligar_logs!
    (AnilArenaLog.desligar! rescue nil) if defined?(AnilArenaLog)
    (AnilMovLog.desligar! rescue nil)   if defined?(AnilMovLog)
    (AnilArenaIntrusos.desligar! rescue nil) if defined?(AnilArenaIntrusos)
  rescue
    nil
  end

  # ⚠️ OS MESMOS OBJECTOS ERA COMODO E ERA UMA BOMBA.
  #
  # A mochila ja era outra. A equipa nao: eu punha os Pokemon VERDADEIROS no
  # campo, para que a vida que a arena escreve durante a luta aparecesse
  # sozinha na equipa ao sair. Comodo, e errado — porque a partir desse
  # instante os objectos verdadeiros do jogador estao a ser escritos por um
  # sistema em tempo real, e qualquer coisa que grave nesse intervalo grava o
  # estado da masmorra por cima da vida real dele.
  #
  # Se o jogo fechar a meio — crash, falta de luz, o aparelho a matar o
  # processo — o que fica no disco e uma equipa de dois e uma mochila vazia.
  # Foi exactamente o que o utilizador apanhou.
  #
  # Agora entra uma COPIA, como na troca: o que vai para o campo sao Pokemon
  # novos, feitos de um `Marshal` do verdadeiro. Sao iguais em tudo (o mesmo
  # `personalID`, a mesma historia), so que sao outros objectos — e o que lhes
  # acontecer la dentro nao toca nos originais.
  #
  # ⚠️ E A SAIDA LIMPA E QUE TROCA UM PELO OUTRO.
  #
  # O que se ganha la dentro — vida perdida, experiencia, PP gastos — tem de
  # contar. Em vez de copiar campo a campo (e esquecer um), no regresso mete-se
  # a COPIA no lugar do original dentro da equipa. O jogador fica com o Pokemon
  # tal como ele saiu da masmorra, e a copia deixa de ser copia: passa a ser o
  # Pokemon dele.
  #
  # Um crash nao chega a esse passo. Os originais ficam como estavam.
  def copia_funda(pk)
    Marshal.load(Marshal.dump(pk))
  rescue => e
    log("nao consegui copiar #{(pk.name rescue '?')}: #{e.class}; vai o proprio")
    pk
  end

  def isolar!(dois)
    return false unless $PokemonGlobal && $player && $bag
    reais  = dois.compact
    copias = reais.map { |p| copia_funda(p) }
    $PokemonGlobal.anil_caverna = {
      :bag      => $bag,
      :party    => $player.party.dup,
      :reais    => reais,
      :copias   => copias,
      :regresso => @regresso,
      :amigo    => @amigo
    }
    $bag = PokemonBag.new
    $player.party = copias
    log("mochila e equipa isoladas (#{copias.length} copias)")
    true
  rescue => e
    log("falha a isolar: #{e.class}: #{e.message}")
    false
  end

  def repor!(perdeu)
    g = ($PokemonGlobal.anil_caverna rescue nil)
    return false unless g
    ganho = $bag
    $bag = g[:bag]
    # A equipa que volta e a de antes, com as copias no lugar dos originais que
    # foram a masmorra — e assim que a vida, a experiencia e os PP contam.
    lista = (g[:party] || []).dup
    (g[:reais] || []).each_with_index do |r, i|
      c = (g[:copias] || [])[i]
      next unless r && c
      j = lista.index { |p| p.equal?(r) }
      lista[j] = c if j
    end
    $player.party = lista
    @regresso ||= g[:regresso]
    $PokemonGlobal.anil_caverna = nil
    quantos = perdeu ? 0 : entregar_saque!(ganho)
    log(perdeu ? "mochila reposta; o saque ficou lá" :
                 "mochila reposta com #{quantos} item(ns) trazidos")
    true
  rescue => e
    log("falha a repor: #{e.class}: #{e.message}")
    false
  end

  def entregar_saque!(ganho)
    return 0 unless ganho
    n = 0
    ganho.pockets.each do |bolso|
      next unless bolso.is_a?(Array)
      bolso.each do |linha|
        item, qtd = linha
        next unless item
        qtd = qtd.to_i
        qtd = 1 if qtd <= 0
        n += qtd if ($bag.add(item, qtd) rescue false)
      end
    end
    n
  rescue
    0
  end

  # ⚠️ O REGRESSO QUE NINGUÉM PEDIU.
  #
  # Corre a cada frame fora da caverna e quase sempre não faz nada. O caso que
  # apanha é o único que importa: o jogo arrancou com uma mochila guardada, ou
  # seja, alguém fechou o jogo lá dentro. Devolve-se o que era dele e leva-se
  # para fora — o saque perde-se, que é a mesma regra de quem cai.
  # ⚠️ E, ACIMA DE TUDO, NAO SE GRAVA COM A EQUIPA DA MASMORRA NO LUGAR.
  #
  # A copia resolve metade: os objectos verdadeiros deixam de ser escritos. A
  # outra metade e que o `$player.party` e o `$bag` que estao em memoria durante
  # a sessao SAO os da masmorra — dois Pokemon e uma mochila vazia — e qualquer
  # gravacao nesse intervalo escreve isso no disco e manda-o para o servidor.
  #
  # Ha gravacoes que acontecem sozinhas: o autosave da mudanca de mapa, o
  # `gravar_ja!` de uma accao autoritativa, a subida do save para a nuvem. Nao
  # vale a pena caca-las uma a uma. Fecha-se a porta: enquanto houver mochila
  # guardada, nao se grava. Ao sair, grava-se logo — com o estado certo.
  #
  # O que se perde num crash e a sessao. E o que se quer perder.
  def isolado?
    !($PokemonGlobal.anil_caverna rescue nil).nil?
  rescue
    false
  end

  # ⚠️ NAO CHEGA TENTAR SAIR. TEM DE SE CONFERIR QUE SE SAIU.
  #
  # Quantas seguranças este caminho ja levou e ainda assim voltou a acontecer:
  # a arrumacao fora do `rescue`, as duas portas, a conferencia do
  # `dentro_do_mapa?`. Todas elas olham para o instante em que se tenta sair —
  # e uma transferencia agendada pode ser cancelada DEPOIS disso (um evento, um
  # `pbMessage` que ainda corria, uma reconexao a meio).
  #
  # Este olha para o resultado, dois segundos depois, e e o unico que nao pode
  # ser enganado: se a marca da saida esta posta e o boneco continua num mapa da
  # masmorra, entao nao se saiu — seja qual for a razao — e abre-se a porta de
  # emergencia.
  #
  # ⚠️ E POR ISSO E QUE TEM DE HAVER UMA MARCA.
  #
  # Os mapas 303 e 304 sao o Tunel da Rocha a serio: gente que nunca viu uma
  # masmorra anda por la todos os dias. Uma regra do genero "estas num mapa da
  # lista e a sessao nao corre, entao sais" teleportava essas pessoas para o
  # Centro Pokemon a meio do jogo normal. A marca so existe para quem tentou
  # mesmo sair de uma sessao.
  ESPERA_SAIDA = 2.0    # segundos: tempo de sobra para uma transferencia normal

  def vigiar_saida!
    return unless @saida_pendente
    unless dentro_do_mapa?
      @saida_pendente = nil    # saiu: nao ha nada a fazer
      return
    end
    return if ($game_temp.player_transferring rescue false)
    return if ($game_temp.message_window_showing rescue false)
    return if (Time.now.to_f - @saida_pendente.to_f) < ESPERA_SAIDA
    @saida_pendente = nil
    log_sempre("FICOU DENTRO depois de sair (mapa #{($game_map.map_id rescue '?')}); a resgatar")
    unless porta_de_emergencia!
      pbMessage(_INTL("Não foi possível sair da masmorra sozinho.\nUse uma Corda da Caverna ou fale com a administração.")) rescue nil
    end
  rescue => e
    @saida_pendente = nil
    log_sempre("falha no vigia da saida: #{e.class}: #{e.message}")
  end

  def vigiar_regresso!
    vigiar_saida!
    return if @activa
    gravar_de_volta!
    g = ($PokemonGlobal.anil_caverna rescue nil)
    return unless g
    return unless $game_map
    log("mochila guardada encontrada fora de sessão: a repor")
    repor!(true)
    return unless MAPAS.include?($game_map.map_id)
    mapa_id, x, y, dir = (g[:regresso] || [2, 10, 10, 2])
    ($game_temp.player_new_map_id    = mapa_id) rescue nil
    ($game_temp.player_new_x         = x) rescue nil
    ($game_temp.player_new_y         = y) rescue nil
    ($game_temp.player_new_direction = dir) rescue nil
    ($game_temp.player_transferring  = true) rescue nil
    pbMessage(_INTL("A caverna desmoronou enquanto você esteve fora.\nO que tinha apanhado ficou lá.")) rescue nil
  rescue => e
    log("falha no regresso: #{e.class}: #{e.message}")
  end

  #-----------------------------------------------------------------------------
  # SAIR — pela corda, ou pelo chão
  #-----------------------------------------------------------------------------
  # ⚠️ GASTA-SE ANTES DE SAIR, E NÃO DEPOIS.
  #
  # O `voltar!` muda de mapa, e a mudança de mapa não é um sítio onde se possa
  # contar com a ordem das coisas. Tirar a corda do saco primeiro, e só depois
  # sair, é a mesma regra do consumível que já custou caro noutro sítio deste
  # projecto: consome-se e grava-se ANTES de entregar o que se comprou, senão
  # há sempre uma maneira de ficar com as duas coisas.
  def usar_corda!
    return false unless dentro?
    unless ($bag.remove(SAIDA) rescue false)
      pbMessage(_INTL("Você não tem uma Corda da Caverna.")) rescue nil
      return false
    end
    # A corda apanhada aqui dentro contava para o que se perde ao cair; gasta,
    # deixa de contar, senão o `caiu!` tentava largar no chão uma corda que já
    # não existe.
    if @ganho[SAIDA].to_i > 0
      @ganho[SAIDA] -= 1
      @ganho.delete(SAIDA) if @ganho[SAIDA] <= 0
    end
    pbMessage(_INTL("A corda puxa você para fora com o que trouxer.")) rescue nil
    voltar!(true)
    true
  end

  # ⚠️ CAIR NÃO É SAIR. É DEIXAR LÁ O QUE SE VEIO BUSCAR.
  # ⚠️ CAI TUDO O QUE ESTÁ NA MOCHILA DA CAVERNA — E ELA SÓ TEM O DE LÁ.
  #
  # Antes isto percorria o `@ganho`, uma contabilidade à parte que podia
  # divergir da mochila (um item usado, um que não coube). Agora a mochila É a
  # contabilidade: o que está lá dentro foi apanhado aqui, e é isso que fica no
  # chão para quem o quiser.
  # ⚠️ O PRECO DEPENDE DA SESSAO; A SAIDA NAO.
  #
  # Isto era um `return unless dentro?` no topo, e o `dentro?` pergunta pela
  # `@activa`. Com a sessao ja desligada — e ela desliga-se sozinha a meio do
  # `voltar!` — o metodo inteiro nao fazia nada: nem largava nada, nem saia. O
  # jogador ficava de pe numa masmorra morta, que e o relato.
  #
  # As duas metades separam-se, porque tem condicoes diferentes:
  #
  #   largar o saque   so faz sentido HAVENDO sessao. Sem ela o `$bag` ja e o
  #                    verdadeiro, e despejar isso no chao seria roubar ao
  #                    jogador a mochila inteira.
  #   sair             faz sentido sempre que o boneco esteja la dentro, e o
  #                    interruptor nao tem voto nenhum nisso.
  def caiu!
    largar_o_que_trouxe! if dentro?
    return unless dentro_do_mapa?
    voltar!(false, true)
  rescue => e
    # ⚠️ Nao se repete o `voltar!`: ele ja arruma vinte variaveis e repoe a
    # mochila, e chama-lo duas vezes seria desfazer o que a primeira fez. O que
    # falta garantir e so uma coisa — que o boneco sai de la.
    log_sempre("falha ao cair: #{e.class}: #{e.message}")
    (porta_de_emergencia! rescue nil) if dentro_do_mapa?
  end

  def largar_o_que_trouxe!
    perdidos = 0
    ($bag.pockets.each do |bolso|
      next unless bolso.is_a?(Array)
      bolso.dup.each do |linha|
        item, n = linha
        next unless item
        [n.to_i, 1].max.times do
          next unless ($bag.remove(item) rescue false)
          largar_perto!(item)
          perdidos += 1
        end
      end
    end rescue nil)
    log("caiu e deixou #{perdidos} item(s) no chao")
    pbMessage(perdidos.zero? ?
      _INTL("Escapou por pouco, e não trazia nada.") :
      _INTL("Tudo o que apanhou ficou no chão da masmorra.")) rescue nil
  rescue => e
    log_sempre("falha a largar o saque: #{e.class}: #{e.message}")
  end

  def largar_perto!(item)
    # O mesmo cuidado dos drops: uma casa aleatoria a volta pode ser parede, ou
    # ja ter um item em cima. Se nenhuma das nove servir, fica aos pes.
    volta = []
    (-1..1).each { |ax| (-1..1).each { |ay| volta << [$game_player.x + ax, $game_player.y + ay] } }
    volta = volta.shuffle
    posto = volta.find { |(px, py)| casa_livre?(px, py) } || [$game_player.x, $game_player.y]
    largar_no_chao!(item, posto[0], posto[1], $game_player.x, $game_player.y)
  rescue
    nil
  end

  # ⚠️ QUEM PERDEU NAO PODE ACORDAR LA DENTRO COMO SE NADA FOSSE.
  #
  # Havia dois buracos, e davam os dois no mesmo sitio.
  #
  # O primeiro: cair e usar a corda saiam pela MESMA porta — o `@regresso`, a
  # casa de onde se entrou. Mas quem cai nao volta para onde entrou; quem cai
  # perde. Tem de acordar no Centro Pokemon, com a equipa curada, como em
  # qualquer outra derrota do jogo.
  #
  # O segundo, e o pior: este metodo arruma vinte e tal variaveis ANTES de
  # mudar de mapa, e tinha um `rescue nil` a tapar tudo no fim. Bastava uma
  # dessas linhas rebentar — um objecto ja morto, uma lista que ja nao existe —
  # para a saida nunca chegar a acontecer. O `@activa` ja tinha sido posto a
  # false, portanto a masmorra desligava-se e o jogador ficava plantado la
  # dentro num mapa que ja nao era masmorra nenhuma. E exactamente o que o
  # utilizador descreveu: "spawna o personagem la e o jogo dela volta ao
  # normal".
  #
  # Agora a arrumacao esta num bloco que pode falhar a vontade, e a saida
  # acontece a seguir, fora do alcance dela.
  def voltar!(com_tudo, derrota = false)
    begin
    repor!(!com_tudo)
    despejar_log!
    desligar_logs!
    @activa = false
    @ganho = {}
    @gente = nil
    # Uma visita nova volta a merecer o aviso; a visita velha ja o teve.
    @disse_sozinho = false
    # Os eventos do mapa velho morrem com ele; guardar referencias para eles
    # era segurar lixo e mexer em objectos que ja nao contam para nada.
    @voando = []
    @arcos = []
    @voou = {}
    @abatidos = 0
    @semente = 0.0
    @tipo_enc = nil
    @amigo = nil
    @mob_avisado = 0
    @povoado = {}
    @casas = {}
    @chegada = nil
    @passagem_ate = 0.0
    # ⚠️ Numero novo a cada entrada. Guardar o mesmo entre sessoes daria sempre
    # a mesma pessoa a mandar, e um desempate que nunca muda deixa de ser um
    # desempate — passa a ser um privilegio.
    @servidor_visto = nil
    @posse = nil
    @posse_alheia = nil
    @posse_visto = 0.0
    @dono_dito = 0.0
    @vistos = {}
    @vistos_mapa = nil
    @sid_seguinte = 0
    @ancora = nil
    @na_zona = 0
    @tentado = {}
    @pedidos = {}
    (AnilArena.sair! rescue nil)
    rescue => e
      log("falha a arrumar a saida: #{e.class}: #{e.message}")
    end
    # ⚠️ E GRAVA-SE ASSIM QUE FOR SEGURO.
    #
    # Enquanto se esteve la dentro nao se gravou nada — de proposito. Isso quer
    # dizer que o disco ainda tem o estado de ANTES de se entrar: sem o saque,
    # sem a experiencia, com o bilhete que ja foi gasto. Nao se grava aqui
    # porque estamos a meio de uma mudanca de mapa; marca-se, e o relogio de
    # fora grava no primeiro frame em que ja nao ha nada em transito.
    @gravar_ao_sair = true
    # ⚠️ A MARCA POE-SE ANTES, e nao depois.
    #
    # Ela e a unica prova de que esta pessoa estava numa sessao — e e preciso
    # que exista mesmo que o `largar_a_masmorra!` rebente na primeira linha.
    # Posta depois, o caso que ela serve para apanhar era precisamente o caso
    # em que ela nunca chegava a ser posta.
    @saida_pendente = Time.now.to_f
    largar_a_masmorra!(derrota)
  end

  # ⚠️ TRES PORTAS, E A ULTIMA E A QUE NAO PODE FALHAR.
  #
  # Quem perdeu vai ao Centro Pokemon; quem usou a corda volta a casa de onde
  # entrou. Mas nenhuma das duas e garantida — um jogador sem Centro marcado
  # nao tem para onde ir, e um `@regresso` perdido (uma reconexao a meio, um
  # save carregado por cima) deixa a corda sem destino.
  #
  # Por isso confere-se o resultado em vez de se confiar nele: se ainda
  # estivermos num mapa da masmorra depois de tentar, tenta-se a outra porta. E
  # so fica no log se as duas falharem, que e a unica maneira de isto voltar a
  # acontecer sem ninguem saber porque.
  # ⚠️ A TERCEIRA PORTA ESTAVA PROMETIDA NA NOTA ACIMA E NAO EXISTIA NO CODIGO.
  #
  # "TRES PORTAS, E A ULTIMA E A QUE NAO PODE FALHAR" — e depois havia duas, e
  # as duas podem nao fazer nada:
  #
  #   ao_centro!     e o `pbStartOver`, e ele so transfere com
  #                  `$scene.transfer_player if $scene.is_a?(Scene_Map)`. NAO
  #                  liga o `player_transferring`, portanto fora do mapa os
  #                  campos que ele escreve ficam ali a nao servir a ninguem. E
  #                  sem Centro Pokemon marcado ele vai a casa; sem casa no
  #                  metadata, volta sem fazer nada.
  #   pela_entrada!  precisa do `@regresso`, e o proprio metodo poe-no a nil
  #                  antes de o usar.
  #
  # Falhando as duas, o jogador fica de pe dentro de uma masmorra ja desligada,
  # com o boneco de treinador de volta. E o relato, palavra por palavra:
  # "apareceu meu personagem la dentro, bugando todo o meu jogo".
  #
  # Esta porta nao chama nada que decida por ela: escolhe o destino, escreve os
  # campos, e LIGA A BANDEIRA. Com a bandeira ligada quem transfere e o
  # `Scene_Map#update`, no frame seguinte, esteja o `$scene` no que estiver.
  def porta_de_emergencia!
    return false unless dentro_do_mapa?
    d = nil
    if $PokemonGlobal && $PokemonGlobal.pokecenterMapId &&
       $PokemonGlobal.pokecenterMapId.to_i >= 0
      d = [$PokemonGlobal.pokecenterMapId.to_i,
           $PokemonGlobal.pokecenterX.to_i,
           $PokemonGlobal.pokecenterY.to_i,
           ($PokemonGlobal.pokecenterDirection.to_i rescue 2)]
    end
    if d.nil?
      casa = (GameData::PlayerMetadata.get($player.character_ID)&.home rescue nil)
      casa ||= (GameData::Metadata.get.home rescue nil)
      d = [casa[0].to_i, casa[1].to_i, casa[2].to_i, (casa[3].to_i rescue 2)] if casa
    end
    if d.nil? || MAPAS.include?(d[0])
      log_sempre("PORTA DE EMERGENCIA SEM DESTINO (centro e casa em falta)")
      return false
    end
    unless (pbRgssExists?(sprintf("Data/Map%03d.rxdata", d[0])) rescue true)
      log_sempre("PORTA DE EMERGENCIA: o mapa #{d[0]} nao existe")
      return false
    end
    ($game_temp.player_new_map_id    = d[0]) rescue nil
    ($game_temp.player_new_x         = d[1]) rescue nil
    ($game_temp.player_new_y         = d[2]) rescue nil
    ($game_temp.player_new_direction = d[3]) rescue nil
    ($game_temp.player_transferring  = true) rescue nil
    if $scene.is_a?(Scene_Map)
      pbFadeOutIn(99999) {
        $scene.transfer_player
        $game_map.autoplay
        $game_map.refresh
      }
    end
    log_sempre("porta de emergencia: para o mapa #{d[0]} (#{d[1]},#{d[2]})")
    true
  rescue => e
    log_sempre("falha na porta de emergencia: #{e.class}: #{e.message}")
    false
  end

  # ⚠️ A DERROTA E A DO JOGO. NAO HA VERSAO DA MASMORRA DISTO.
  #
  # Eu tinha aqui, para quem perde, o Centro Pokemon e DEPOIS a entrada da
  # masmorra como recurso. A entrada nao e um recurso: e um destino errado. Quem
  # perdeu nao volta para a porta da caverna — desmaia e acorda no Centro, como
  # em qualquer outra derrota deste jogo. Foi isso que se pediu, e tem razao:
  # essa parte do jogo ja esta desenhada e nao precisa de uma versao propria.
  #
  # Ficam duas portas para a derrota, e as duas vao ao mesmo sitio: a do jogo
  # (`pbStartOver`) e, se ela nao levar ninguem, a que escreve os campos e liga
  # a bandeira a mao.
  def largar_a_masmorra!(derrota)
    if derrota
      ao_centro!
      return unless dentro_do_mapa?
      log_sempre("o Centro Pokemon nao levou ninguem; porta de emergencia")
      porta_de_emergencia!
      return
    end
    pela_entrada!
    return unless dentro_do_mapa?
    ao_centro!
    return unless dentro_do_mapa?
    log_sempre("AS DUAS PORTAS FALHARAM (mapa #{($game_map.map_id rescue '?')}); porta de emergencia")
    porta_de_emergencia!
  rescue => e
    log_sempre("falha a largar a masmorra: #{e.class}: #{e.message}")
    (porta_de_emergencia! rescue nil)
  end

  # So o mapa. O `dentro?` pergunta tambem pelo `@activa`, que a esta altura ja
  # foi desligado — e o que interessa saber e se o boneco ainda esta la.
  # Uma vez, no primeiro frame calmo depois de se sair.
  def gravar_de_volta!
    return unless @gravar_ao_sair
    return if isolado?
    return if ($game_temp.player_transferring rescue false)
    @gravar_ao_sair = false
    (AnilLanRework.gravar_ja!("saida_da_masmorra") rescue nil)
    log("gravado a saida da masmorra")
  rescue => e
    @gravar_ao_sair = false
    log("falha a gravar a saida: #{e.class}: #{e.message}")
  end

  def dentro_do_mapa?
    $game_map && MAPAS.include?($game_map.map_id)
  rescue
    false
  end

  # ⚠️ NEM TODOS OS MAPAS DA LISTA SAO MASMORRA. DOIS SAO O JOGO NORMAL.
  #
  # O 303 e o 304 sao o Tunel da Rocha a serio — gente que nunca viu uma
  # masmorra anda por la todos os dias. Os outros quatro sao as instancias:
  # geradas a entrada, so existem enquanto ha sessao, e ninguem passa por elas
  # por acaso.
  #
  # A diferenca importa porque a `@activa` PODE estar errada — e e por isso que
  # esta ronda existe. Estando eu no 306, a sessao ou corre ou se desligou a
  # meio; em qualquer dos casos eu estou dentro da masmorra e nao ha
  # interruptor nenhum que possa dizer o contrario.
  MAPAS_INSTANCIA = [305, 306, 307, 308].freeze

  def so_da_masmorra?
    $game_map && MAPAS_INSTANCIA.include?($game_map.map_id)
  rescue
    false
  end

  def ao_centro!
    # O `repor!` ja correu: a equipa e o saco sao outra vez os verdadeiros, e e
    # essa equipa que o `pbStartOver` cura.
    (pbStartOver(true) rescue nil)
  rescue
    nil
  end

  def pela_entrada!
    return unless @regresso
    mapa_id, x, y, dir = @regresso
    @regresso = nil
    ($game_temp.player_new_map_id    = mapa_id) rescue nil
    ($game_temp.player_new_x         = x)       rescue nil
    ($game_temp.player_new_y         = y)       rescue nil
    ($game_temp.player_new_direction = dir)     rescue nil
    # ⚠️ E A MUDANCA FAZ-SE AQUI, e nao no fim do frame.
    #
    # Com o `player_transferring` sozinho a mudanca fica agendada, e quem a faz
    # e o `Scene_Map#update` — que so corre se ninguem a cancelar pelo caminho.
    # Feita aqui dentro, com o ecra preto por cima, ela ou acontece ou lanca; o
    # que nao faz e desaparecer.
    if $scene.is_a?(Scene_Map)
      pbFadeOutIn(99999) {
        $scene.transfer_player
        $game_map.autoplay
        $game_map.refresh
      }
    else
      ($game_temp.player_transferring = true) rescue nil
    end
  rescue => e
    log("falha a sair pela entrada: #{e.class}: #{e.message}")
  end
end

#-------------------------------------------------------------------------------
# O bilhete e a corda, registados em código.
#
# ⚠️ NÃO SE MEXE NO PBS. Sem o `.pbs_compiled_raid_v3` o cliente regenera TODOS
# os .dat na máquina de cada jogador, e isso já partiu coisas neste projecto.
# Registar em código dá o mesmo item sem tocar em ficheiro de dados — é o que o
# 189 já faz com o amuleto de teste.
#-------------------------------------------------------------------------------
module AnilRaidCavernaItens
  module_function

  def registar!
    return unless defined?(GameData::Item)
    return if (GameData::Item.exists?(AnilRaidCaverna::BILHETE) rescue false)
    GameData::Item.register({
      :id          => AnilRaidCaverna::BILHETE,
      :name        => _INTL("Bilhete de Masmorra"),
      :name_plural => _INTL("Bilhetes de Masmorra"),
      :pocket      => 8,
      :price       => 0,
      :description => _INTL("Abre a entrada da caverna instável. Lá dentro só se sai com uma Escape Rope."),
      # 2 = Direct: usa-se do saco e pronto. Com 1 o jogo perguntava em que
      # Pokemon se usava o bilhete, o que nao quer dizer nada.
      :field_use   => 2
    })
  rescue => e
    AnilRaidCaverna.log("falha a registar o bilhete: #{e.class}: #{e.message}")
  end

  # ⚠️ BOLSO 1 E `consumable`, E NÃO BOLSO 8.
  #
  # O bolso 8 é o dos Key Items, e um Key Item não se gasta nem se conta — foi
  # exactamente o defeito da Escape Rope que nos trouxe aqui. Esta é um
  # consumível vulgar, do mesmo feitio do Repel: conta-se quantas se têm, e
  # cada uso leva uma.
  def registar_corda!
    return unless defined?(GameData::Item)
    return if (GameData::Item.exists?(AnilRaidCaverna::SAIDA) rescue false)
    GameData::Item.register({
      :id          => AnilRaidCaverna::SAIDA,
      :name        => _INTL("Corda da Caverna"),
      :name_plural => _INTL("Cordas da Caverna"),
      :pocket      => 1,
      :price       => 0,
      :description => _INTL("Cai dos Pokémon da caverna instável. Só ela tira você de lá, e gasta-se ao usar."),
      :field_use   => 2,
      :consumable  => true
    })
  rescue => e
    AnilRaidCaverna.log("falha a registar a corda: #{e.class}: #{e.message}")
  end
end

#-------------------------------------------------------------------------------
# Ganchos. Todos tarde, no `apply_post_plugin_patches`, e todos por alias com
# guarda — ver a lição no MOD 190.
#-------------------------------------------------------------------------------
module AnilLanRework
  class << self
    unless method_defined?(:anil_raidcav_orig_apply_post_plugin_patches)
      alias anil_raidcav_orig_apply_post_plugin_patches apply_post_plugin_patches
      def apply_post_plugin_patches
        anil_raidcav_orig_apply_post_plugin_patches
        AnilRaidCavernaItens.registar!
        AnilRaidCavernaItens.registar_corda!
        # ⚠️ O `ligar_ao_load_data!` DEIXOU DE SER CHAMADO.
        #
        # Com o Map303.rxdata em disco, apanhar o `load_data` a meio só serviria
        # para servir uma cópia de memória por cima do ficheiro verdadeiro —
        # duas fontes para a mesma coisa, que é como se perde uma tarde a
        # perceber qual delas está a ganhar.
      end
    end
  end
end

module AnilRaidCaverna
  module_function

  # O mesmo truque do campo da arena: o motor pede o mapa por `load_data`, e um
  # `load_data` pode ser respondido.
  def ligar_ao_load_data!
    return if @ligado
    @ligado = true
    Kernel.module_eval do
      class << self
        unless method_defined?(:anil_raidcav_load_data_original)
          alias_method :anil_raidcav_load_data_original, :load_data
          def load_data(ficheiro)
            if ficheiro.to_s =~ /Map#{AnilRaidCaverna::MAPA}\.rxdata/
              m = (AnilRaidCaverna.mapa rescue nil)
              return m if m
            end
            anil_raidcav_load_data_original(ficheiro)
          end
        end
      end
      unless method_defined?(:anil_raidcav_load_data_original_i)
        alias_method :anil_raidcav_load_data_original_i, :load_data
        def load_data(ficheiro)
          if ficheiro.to_s =~ /Map#{AnilRaidCaverna::MAPA}\.rxdata/
            m = (AnilRaidCaverna.mapa rescue nil)
            return m if m
          end
          anil_raidcav_load_data_original_i(ficheiro)
        end
      end
    end
    log("caverna ligada ao load_data (mapa #{MAPA})")
  rescue => e
    log("falha a ligar ao load_data: #{e.class}: #{e.message}")
  end
end

#-------------------------------------------------------------------------------
# O bilhete abre a caverna; a corda tira de lá.
#-------------------------------------------------------------------------------
ItemHandlers::UseInField.add(AnilRaidCaverna::BILHETE, proc { |_item|
  next 0 unless AnilRaidCaverna.perguntar!
  1
}) rescue nil

ItemHandlers::UseInField.add(AnilRaidCaverna::SAIDA, proc { |_item|
  unless AnilRaidCaverna.dentro?
    pbMessage(_INTL("Esta corda só serve dentro da caverna.")) rescue nil
    next 0
  end
  AnilRaidCaverna.usar_corda! ? 1 : 0
}) rescue nil

# ⚠️ E A ESCAPE ROPE DE SEMPRE NÃO PODE SERVIR DE ATALHO.
#
# Ela teleporta para o último centro Pokémon, e cá dentro isso era sair com
# tudo o que se apanhou sem gastar nada — a caverna inteira contornada por um
# Key Item que toda a gente traz no bolso. Fora da caverna este gancho devolve
# `nil` e a corda faz exactamente o que sempre fez.
ItemHandlers::UseInField.add(AnilRaidCaverna::CORDA_FORA, proc { |_item|
  next nil unless AnilRaidCaverna.dentro?
  pbMessage(_INTL("A caverna não deixa esta corda funcionar. Só a Corda da Caverna tira você daqui.")) rescue nil
  next 0
}) rescue nil

#-------------------------------------------------------------------------------
# O COMANDO
#
# ⚠️ O NOME DO ALIAS TEM DE SER ÚNICO, E ISTO NÃO É UM DETALHE DE ESTILO.
#
# O 189 já embrulha o `send_message` com `anil_arena_orig_send_message`. Dois
# MODs a usarem o mesmo nome de alias já mataram o /event, o /tp, o /dexshiny e
# o /canal neste projecto — em silêncio, sem um erro, porque o segundo alias
# aponta para o primeiro embrulho e a corrente fecha-se num círculo. Daí o
# `anil_raidcav_orig_send_message`, que não existe em mais lado nenhum.
#
# A ordem é a que salva o resto: o 192 carrega depois do 189, portanto este
# embrulho apanha o do 189, e o texto que aqui não for tratado desce a corrente
# inteira até ao chat normal.
#-------------------------------------------------------------------------------
module AnilRaidCavernaComando
  module_function

  def tratar(texto)
    t = texto.to_s.strip
    return false unless t =~ %r{\A/caverna(?:\s+(.*))?\z}i
    arg = $1.to_s.strip.downcase
    # Sem amuleto o comando NÃO EXISTE — devolve-se false e o texto segue para
    # o chat como qualquer palavra escrita. Mesma regra da mensagem do NPC: a
    # caverna não se anuncia a quem não a devia conhecer.
    return false unless AnilRaidCaverna.disponivel?

    case arg
    when "bilhete"
      dar!(AnilRaidCaverna::BILHETE, _INTL("Bilhete de Masmorra"))
    when "corda"
      dar!(AnilRaidCaverna::SAIDA, _INTL("Corda da Caverna"))
    when "quem"
      lista = AnilRaidCaverna.gente_ca.values.reject { |n| n.to_s.empty? }
      if !AnilRaidCaverna.dentro?
        pbMessage(_INTL("Você não está na caverna.")) rescue nil
      elsif lista.empty?
        pbMessage(_INTL("Só você.")) rescue nil
      else
        pbMessage(_INTL("Na caverna: {1}.", lista.join(", "))) rescue nil
      end
    when "sair"
      if AnilRaidCaverna.dentro?
        AnilRaidCaverna.usar_corda!
      else
        pbMessage(_INTL("Você não está na caverna.")) rescue nil
      end
    when ""
      AnilRaidCaverna.perguntar!
    else
      pbMessage(_INTL("/caverna, /caverna bilhete, /caverna corda, /caverna quem, /caverna sair")) rescue nil
    end
    true
  rescue => e
    AnilRaidCaverna.log("falha no comando: #{e.class}: #{e.message}")
    true
  end

  # ⚠️ GRAVA-SE LOGO. Um item que entra na mochila e não chega ao disco é um
  # item que desaparece se o jogo fechar — e a única maneira de o recuperar é
  # pedir outro, o que só se percebe depois de reparar que ele sumiu.
  def dar!(id, nome)
    unless (GameData::Item.exists?(id) rescue false)
      pbMessage(_INTL("Esse item ainda não existe neste cliente.")) rescue nil
      return
    end
    unless ($bag.add(id) rescue false)
      pbMessage(_INTL("Não coube na mochila.")) rescue nil
      return
    end
    (AnilLanRework.gravar_ja!("caverna_item") rescue nil)
    (pbSEPlay("Item get") rescue nil)
    pbMessage(_INTL("Você recebeu: {1}.", nome)) rescue nil
  rescue
    nil
  end
end

module AnilLanRework
  module Chat
    class << self
      if !method_defined?(:anil_raidcav_orig_send_message)
        alias_method :anil_raidcav_orig_send_message, :send_message rescue nil
      end

      def send_message(text)
        return if AnilRaidCavernaComando.tratar(text)
        anil_raidcav_orig_send_message(text)
      end
    end
  end
end

#-------------------------------------------------------------------------------
# ONDE A MOCHILA VERDADEIRA ESPERA
#
# ⚠️ NO `$PokemonGlobal`, PORQUE E O QUE VAI NO SAVE.
#
# E o mesmo sitio onde o MOD 043 guarda os itens do chao, e pela mesma razao:
# tudo o que tem de sobreviver a um fecho do jogo vive aqui. Uma variavel de
# modulo bastava enquanto o jogo estivesse aberto — e era exactamente no caso
# em que ele nao esta que se perdia a mochila inteira do jogador.
#-------------------------------------------------------------------------------
class PokemonGlobalMetadata
  def anil_caverna
    @anil_caverna
  end

  def anil_caverna=(val)
    @anil_caverna = val
  end
end

#-------------------------------------------------------------------------------
# O RELOGIO DE FORA
#
# ⚠️ ALIAS PROPRIO. O 189 ja embrulha o `Scene_Map#update`, e dois embrulhos com
# o mesmo nome fecham-se num circulo — ver a licao dos comandos de chat.
#
# Isto corre a cada frame e quase sempre nao faz nada: so acorda se houver uma
# mochila guardada e a sessao da caverna nao estiver a correr, que e a
# assinatura de quem fechou o jogo la dentro.
#-------------------------------------------------------------------------------
class Scene_Map
  unless method_defined?(:anil_raidcav_orig_update) ||
         private_method_defined?(:anil_raidcav_orig_update)
    alias_method :anil_raidcav_orig_update, :update
    def update
      anil_raidcav_orig_update
      (AnilRaidCaverna.vigiar_regresso! rescue nil)
    end
  end
end

#-------------------------------------------------------------------------------
# O MATO DO JOGO NORMAL NAO ENTRA AQUI
#
# ⚠️ O 303 E UM MAPA A SERIO, E ISSO TEM UM PRECO QUE EU NAO HAVIA CONTADO.
#
# Quando a caverna era servida de memoria, o resto do jogo nao sabia que ela
# existia. Desde que passou a ser um ficheiro em disco, com nome no MapInfos e
# tabela de encontros propria, ela e um mapa como os outros — e o sistema de
# encontros do overworld (o VOE) trata-a como tal: a cada passo do jogador ele
# pergunta se ha um encontro ali e, quando ha, PLANTA um Pokemon do mundo no
# meio da nossa caverna.
#
# O que se ve disso e o boneco a piscar. Eles nascem, o `limpar_spawns_do_mapa!`
# da arena apaga-os, o VOE volta a planta-los — e cada nascimento reconstroi
# sprites e manda um `vower_wild_spawn` para a rede. E trabalho, e pacotes, e
# desenho, tudo por causa de habitantes que ninguem pediu e que a arena nem
# sabe controlar.
#
# ⚠️ E BLOQUEIA-SE NA PORTA DE ENTRADA, E NAO A LIMPAR DEPOIS.
#
# Ha exactamente um sitio por onde um encontro do mundo entra num mapa: o
# `pbPlaceEncounter`. Recusar ali e uma condicao; apanhar os eventos depois de
# nascidos e uma perseguicao que nunca acaba — foi o que estavamos a fazer sem
# dar por isso.
#
# A caverna tem os seus proprios habitantes (o `povoar!`), e esses nao passam
# por aqui: sao criados pelo `AnilArena.criar_bicho!`, que e outro caminho.
#-------------------------------------------------------------------------------
module AnilLanRework
  class << self
    unless method_defined?(:anil_caverna_orig_apply_post_plugin_patches)
      alias anil_caverna_orig_apply_post_plugin_patches apply_post_plugin_patches
      def apply_post_plugin_patches
        anil_caverna_orig_apply_post_plugin_patches
        AnilRaidCaverna.travar_mato_do_mundo!
        AnilRaidCaverna.travar_gravacoes!
      end
    end
  end
end

module AnilRaidCaverna
  module_function

  # ⚠️ DOIS SITIOS, E OS DOIS SAO PRECISOS.
  #
  # O `save_to_file` e por onde o jogo escreve no disco — apanha o autosave, o
  # menu de guardar e o `gravar_ja!`. A subida para a nuvem e outra porta: ela
  # le o ficheiro, mas tambem e chamada em sitios onde o ficheiro acabou de ser
  # escrito por outra via. Fecham-se as duas.
  #
  # ⚠️ E FALHA-SE ABERTO, NUNCA FECHADO.
  #
  # Se o embrulho rebentar, o jogo tem de continuar a gravar. Um erro meu aqui a
  # trancar as gravacoes de um jogador seria muito pior do que o problema que
  # isto resolve — e a licao ja esta escrita no updater, que uma vez se trancou
  # por dentro exactamente assim.
  def travar_gravacoes!
    return if @gravacoes_travadas
    @gravacoes_travadas = true

    if defined?(SaveData) && SaveData.respond_to?(:save_to_file)
      SaveData.singleton_class.class_eval do
        unless method_defined?(:anil_raidcav_orig_save_to_file)
          alias_method :anil_raidcav_orig_save_to_file, :save_to_file
          def save_to_file(*args)
            if (AnilRaidCaverna.isolado? rescue false)
              (AnilRaidCaverna.log("gravacao no disco recusada: a equipa e a da masmorra") rescue nil)
              return false
            end
            anil_raidcav_orig_save_to_file(*args)
          end
        end
      end
    end

    if defined?(AnilLanRework) && AnilLanRework.respond_to?(:save_and_upload_save_file)
      AnilLanRework.singleton_class.class_eval do
        unless method_defined?(:anil_raidcav_orig_subir_save)
          alias_method :anil_raidcav_orig_subir_save, :save_and_upload_save_file
          def save_and_upload_save_file(*args)
            if (AnilRaidCaverna.isolado? rescue false)
              (AnilRaidCaverna.log("subida do save recusada: a equipa e a da masmorra") rescue nil)
              return false
            end
            anil_raidcav_orig_subir_save(*args)
          end
        end
      end
    end

    log("gravacoes travadas enquanto a masmorra estiver aberta")
  rescue => e
    log("falha a travar as gravacoes: #{e.class}: #{e.message}")
  end

  def travar_mato_do_mundo!
    return if @mato_travado
    return unless Object.private_method_defined?(:pbPlaceEncounter) ||
                  Object.method_defined?(:pbPlaceEncounter)
    @mato_travado = true
    Object.class_eval do
      unless method_defined?(:anil_caverna_orig_pbPlaceEncounter) ||
             private_method_defined?(:anil_caverna_orig_pbPlaceEncounter)
        alias_method :anil_caverna_orig_pbPlaceEncounter, :pbPlaceEncounter
        def pbPlaceEncounter(x, y, pokemon)
          # ⚠️ Instala-se DEPOIS do 070 de proposito: assim este embrulho fica
          # por FORA do dele, e um encontro recusado aqui nunca chega a ser
          # anunciado a rede.
          if (defined?(AnilRaidCaverna) && AnilRaidCaverna.dentro? rescue false)
            (AnilArenaIntrusos.anotar(:spawner_do_mundo_recusado,
                                      "#{pokemon.respond_to?(:speciesName) ? pokemon.speciesName : pokemon} em (#{x},#{y})") rescue nil)
            return nil
          end
          anil_caverna_orig_pbPlaceEncounter(x, y, pokemon)
        end
      end
    end
    log("mato do mundo travado dentro da caverna")
  rescue => e
    log("falha a travar o mato: #{e.class}: #{e.message}")
  end
end
