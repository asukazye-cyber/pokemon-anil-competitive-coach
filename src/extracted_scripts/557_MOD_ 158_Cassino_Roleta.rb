# encoding: UTF-8
#===============================================================================
# MOD: 158_Cassino_Roleta
#-------------------------------------------------------------------------------
# Uma roleta de 6 casas que se abre ao usar a Ficha de Cassino. O premio sai da
# MESMA tabela da caixa vermelha; a roleta e a caixa vermelha com a cortina
# aberta.
#
# ⚠️ O PREMIO E DADO ANTES DA ANIMACAO, E ISSO E UMA GARANTIA, NAO UM ATALHO.
#
# Sortear -> por na mochila -> animar. Se o jogo fechar a meio do giro (e o giro
# dura quase tres segundos), o premio ja e do jogador. Ao contrario, um crash a
# meio comia o item, e num telemovel isso ia acontecer.
#
# ⚠️ AS CINCO CASAS PERDEDORAS SAO SORTEADAS DA MESMA TABELA.
#
# Tudo o que aparece na roleta e genuinamente ganhavel — incluindo o
# SUPERSHINYZADOR, que e 1 em 3300. A emocao fica intacta e nao se promete o que
# nao se pode dar. Encher as casas com isco que nao esta na tabela era outra
# coisa: funcionaria uma vez, ate alguem reparar.
#
# ⚠️ A FICHA E REGISTADA EM TEMPO DE EXECUCAO, NAO NO PBS.
#
# Mexer no PBS obriga a regenerar os .dat, e o mesmo ficheiro que os guarda
# (.pbs_compiled_raid_v3) trava o updater. O 100_Rarity_Eggs_System ja resolve
# isto ha muito com GameData::Item.register no on_enter_map — segue-se o mesmo
# caminho, que nao toca em ficheiro nenhum de dados.
#===============================================================================

module AnilCassinoRoleta
  # ⚠️ DESLIGADO ATE SE DECIDIR LANCAR.
  #
  # Nao chega nao distribuir o icone: o `registar!` acrescenta a ficha aos
  # baralhos das caixas azul e laranja assim que o jogo arranca, portanto o
  # simples facto de este MOD viajar no Scripts.rxdata fazia a ficha comecar a
  # cair na mao dos jogadores — com o item a existir so em memoria e o icone em
  # falta.
  #
  # Com isto a false: nao se regista o item, nao se toca nos baralhos, e o
  # /roleta responde que esta desligado. A roleta em si fica intacta, pronta a
  # ligar numa palavra.
  ACTIVO = false

  FICHA = :FICHACASSINO

  # A roda tem 6 casas: a que se ganha mais cinco.
  CASAS    = 6
  CELULA   = 88          # largura de cada casa, em pixeis
  ALTURA   = 96
  VOLTAS   = 7           # voltas completas antes de comecar a travar
  DURACAO  = 260         # frames do giro (~4,3 s a 60 fps)
  ESPACO_PONTEIRO = 14   # altura da seta por cima da moldura

  LARGURA_TIRA = CASAS * CELULA        # 528

  # ⚠️ A LARGURA DO ECRA LE-SE NA HORA, NUNCA NUMA CONSTANTE.
  #
  # Isto ja mordeu: `MARGEM_X = (Graphics.width - JANELA) / 2` era avaliado
  # quando o script carrega, e nessa altura o Graphics ainda nao tem a medida
  # final. A tira nascia com a margem de outro tamanho de ecra e aparecia
  # encostada a um lado, cortada no outro. Agora calcula-se dentro do giro.

  # ⚠️ OS ITENS DE TOPO ESTAO SEMPRE NA RODA.
  #
  # Deixar isto ao sorteio nao funciona: mesmo com a vitrine puxada para os
  # raros, o SUPERSHINYZADOR aparecia numa roda em cada quatro. E ele que faz
  # olhar para a roda, portanto entra sempre, e o mesmo vale para os outros
  # premios grandes.
  #
  # Ordem = prioridade. Os primeiros entram primeiro quando ha vagas.
  DESTAQUES = [
    :SUPERSHINYZADOR,   # poção de super shiny
    :MASTERBALL5,       # 5x Master Ball
    :SHINYZADOR,        # poção de shiny
    :SHINYCHARM,        # amuleto brilhante
    :SACOMOEDAGRANDE    # saco de dinheiro grande
  ].freeze

  # ⚠️ ITENS QUE SE PARECEM: NO MAXIMO UM POR RODA.
  #
  # Os 7 orbes de super shiny sao 7 itens diferentes com 7 ficheiros diferentes,
  # mas a 48px num fundo escuro sao sete esferas que so mudam de cor — e a roda
  # aparecia com quatro casas "iguais", que le como avaria. As megapedras
  # lendarias tem o mesmo problema: mesma silhueta, cor diferente.
  #
  # Contam como UMA familia, e da familia entra um so.
  FAMILIAS = [
    [:ORBEFLAMEJANTE, :ORBEDELIMA, :ORBEDEESMERALDA, :ORBETURQUESA,
     :ORBEDESAFIRA, :ORBEDEAMETISTA, :ORBEROSA],
    [:MEWTWONITEX, :MEWTWONITEY, :LATIOSITE, :LATIASITE, :DIANCITE,
     :ZYGARDITE, :FLOETTITE, :DARKRANITE, :MAGEARNITE, :HEATRANITE, :ZERAORITE]
  ].freeze

  # ⚠️ UM DESTAQUE GARANTIDO, OS OUTROS A SORTE.
  #
  # Duas versoes falharam antes desta:
  #
  #   - so pelos pesos reais: o item de topo aparecia numa roda em cada quatro,
  #     e na maioria das vezes a roda eram seis coisas banais;
  #   - a encher com destaques ate sobrarem duas vagas: a roda ficava entupida
  #     de raridades, e quando tudo e raro nada e raro. O olho deixa de parar.
  #
  # A regra boa e a do meio: UM entra sempre, e cada destaque a mais tem 30% de
  # hipotese, em cadeia. Da 70% de rodas com um, 21% com dois, 9% com tres — o
  # suficiente para uma roda com dois valer alguma coisa por ser mais rara.
  #
  # O resto das casas sai do sorteio de VERDADE (pesos reais), portanto sao
  # quase sempre itens comuns. E o contraste com eles que faz o destaque saltar.
  DESTAQUE_EXTRA_PCT = 30
  MAX_DESTAQUES      = 3

  DEF_FICHA = {
    :id               => FICHA,
    :real_name        => "Ficha de Cassino",
    :real_name_plural => "Fichas de Cassino",
    :pocket           => 1,
    :price            => 0,
    :sell_price       => 0,
    :field_use        => 2,       # usavel a partir da mochila
    :battle_use       => 0,
    :flags            => [],
    :consumable       => false,   # o consumo e nosso, ver jogar!
    :show_quantity    => true,
    :real_description => "Uma ficha da roleta. Use para girar e levar um prêmio da mesma tabela da caixa vermelha."
  }

  class << self
    def log(t)
      AnilLanRework.log("[CASSINO] #{t}") rescue nil
    end

    # ------------------------------------------------------------- o sorteio
    # UMA chamada a mesma funcao da caixa vermelha. Nao ha tabela paralela para
    # divergir da outra com o tempo.
    def sortear
      return nil unless defined?(GiftBoxSystem)
      GiftBoxSystem.pick_items(GiftBoxSystem::RED_POOL, 1).first
    rescue
      nil
    end

    # O pool tem dois ids que nao sao itens a serio: o MASTERBALL5 vale cinco
    # Master Balls, e o MEGA_STONE_CHANCE ja e resolvido dentro do pick_items.
    def resolver(id)
      return [:MASTERBALL, 5] if id == :MASTERBALL5
      [id, 1]
    end

    def nome_de(id)
      real, qtd = resolver(id)
      base = (GameData::Item.get(real).name rescue real.to_s)
      qtd > 1 ? "#{qtd}x #{base}" : base
    rescue
      id.to_s
    end

    # Ha caber e ha dar. Separam-se porque a ficha e cobrada ENTRE os dois.
    def pode_dar?(id)
      real, qtd = resolver(id)
      return false unless (GameData::Item.exists?(real) rescue false)
      $bag.can_add?(real, qtd)
    rescue
      false
    end

    def dar!(id)
      real, qtd = resolver(id)
      return false unless (GameData::Item.exists?(real) rescue false)
      return false unless $bag.can_add?(real, qtd)
      $bag.add(real, qtd)
      true
    rescue
      false
    end

    # ---------------------------------------------------------------- as casas
    def familia_de(id)
      FAMILIAS.each_with_index { |f, i| return i if f.include?(id) }
      nil
    end

    # Cabe nesta roda? Nao pode repetir o item nem a familia.
    def cabe?(id, casas, familias)
      return false if id.nil? || casas.include?(id)
      f = familia_de(id)
      return false if f && familias.include?(f)
      true
    end

    def juntar!(id, casas, familias)
      casas << id
      f = familia_de(id)
      familias << f if f
    end

    # Quantos destaques esta roda vai mostrar: um de base, e 30% por cada um a
    # mais, ate ao tecto.
    def quantos_destaques
      n = 1
      n += 1 while n < MAX_DESTAQUES && rand(100) < DESTAQUE_EXTRA_PCT
      n
    end

    # A roda: o premio, um punhado pequeno de destaques, e o resto comum.
    def montar_casas(premio)
      casas = []
      familias = []
      juntar!(premio, casas, familias)

      # o premio, se ja for um destaque, conta para a conta
      alvo = quantos_destaques
      alvo -= 1 if DESTAQUES.include?(premio)

      DESTAQUES.shuffle.each do |id|
        break if alvo <= 0 || casas.length >= CASAS
        next unless (id == :MASTERBALL5 || (GameData::Item.exists?(id) rescue false))
        next unless cabe?(id, casas, familias)
        juntar!(id, casas, familias)
        alvo -= 1
      end

      # ⚠️ O RESTO SAI DO SORTEIO DE VERDADE, NAO DA VITRINE.
      #
      # E aqui que entram os itens comuns. Se estas casas tambem puxassem para
      # os raros, voltava-se ao problema de a roda inteira ser rara.
      120.times do
        break if casas.length >= CASAS
        outro = sortear
        next unless cabe?(outro, casas, familias)
        juntar!(outro, casas, familias)
      end

      # pool pequeno demais para encher a roda: repete-se o premio, que e
      # melhor do que uma casa vazia
      casas << premio while casas.length < CASAS

      casas[0, CASAS].shuffle
    end

    # ⚠️ A TIRA E DESENHADA DUAS VEZES LADO A LADO.
    #
    # E o que faz a volta ser continua com um sprite so: desloca-se o src_rect
    # dentro de uma imagem de duas tiras, e quando o deslocamento passa de uma
    # tira volta ao inicio sem salto nenhum.
    def desenhar_tira(casas)
      tira = Bitmap.new(LARGURA_TIRA * 2, ALTURA)
      CASAS.times do |i|
        icone = (GiftBoxSystem.load_item_icon(casas[i], Color.new(120, 120, 120)) rescue nil)
        2.times do |copia|
          x = (i * CELULA) + (copia * LARGURA_TIRA)
          # moldura da casa
          tira.fill_rect(x + 2, 2, CELULA - 4, ALTURA - 4, Color.new(28, 30, 42, 255))
          tira.fill_rect(x + 3, 3, CELULA - 6, ALTURA - 6, Color.new(52, 56, 78, 255))
          next unless icone && !icone.disposed?
          ix = x + ((CELULA - icone.width) / 2)
          iy = (ALTURA - icone.height) / 2
          tira.blt(ix, iy, icone, Rect.new(0, 0, icone.width, icone.height))
          # O MASTERBALL5 desenha-se com o icone de UMA Master Ball; sem o selo
          # ninguem percebe que a casa vale cinco.
          _real, qtd = resolver(casas[i])
          next if qtd <= 1
          tira.font.size = 18
          tira.font.color = Color.new(0, 0, 0, 255)
          tira.draw_text(x + 3, ALTURA - 27, CELULA - 6, 22, "x#{qtd}", 2)
          tira.font.color = Color.new(255, 214, 90, 255)
          tira.draw_text(x + 2, ALTURA - 28, CELULA - 6, 22, "x#{qtd}", 2)
        end
        icone.dispose if icone && !icone.disposed?
      end
      tira
    end

    # ------------------------------------------------------------- o giro
    # Onde a tira tem de parar para a casa `vencedora` ficar sob o ponteiro.
    #
    #   casa i desenhada em  i*CELULA - deslocamento
    #   centro da casa i     i*CELULA + CELULA/2 - deslocamento
    #   queremos isso == centro
    # Quantas casas cabem, e onde comeca a tira. Impar de proposito: sem casa
    # do meio nao ha onde por o ponteiro.
    def medidas
      larg = (Graphics.width rescue 512)
      visiveis = [larg / CELULA, CASAS].min
      visiveis -= 1 if visiveis.even?
      visiveis = 1 if visiveis < 1
      janela = visiveis * CELULA
      { :janela => janela, :margem => (larg - janela) / 2, :centro => janela / 2 }
    end

    def parada_de(vencedora, centro)
      (VOLTAS * LARGURA_TIRA) + (vencedora * CELULA) + (CELULA / 2) - centro
    end

    def girar!(casas, vencedora)
      vp = Viewport.new(0, 0, Graphics.width, Graphics.height)
      vp.z = 99999
      escuro = Sprite.new(vp)
      escuro.bitmap = Bitmap.new(Graphics.width, Graphics.height)
      escuro.bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(0, 0, 0, 190))

      m = medidas
      janela, margem, centro = m[:janela], m[:margem], m[:centro]

      topo = (Graphics.height - ALTURA) / 2
      tira = desenhar_tira(casas)
      roda = Sprite.new(vp)
      roda.bitmap = tira
      roda.x = margem
      roda.y = topo
      roda.src_rect.set(0, 0, janela, ALTURA)

      ponteiro = Sprite.new(vp)
      ponteiro.bitmap = Bitmap.new(janela, ALTURA + ESPACO_PONTEIRO + 8)
      ponteiro.x = margem
      ponteiro.y = topo - ESPACO_PONTEIRO
      pintar_ponteiro(ponteiro.bitmap, centro)

      total = parada_de(vencedora, centro)
      ultima_casa = -1
      ultimo_som = -99

      DURACAO.times do |f|
        t = (f + 1).to_f / DURACAO
        # desaceleracao cubica: rapido no inicio, quase parado no fim
        p = 1.0 - ((1.0 - t) ** 3)
        deslocamento = (total * p).round % LARGURA_TIRA
        roda.src_rect.set(deslocamento, 0, janela, ALTURA)

        # tique-taque: um som por casa que passa, com travao para nao virar
        # metralhadora no inicio do giro
        casa_agora = (((deslocamento + centro) / CELULA).floor) % CASAS
        if casa_agora != ultima_casa
          ultima_casa = casa_agora
          if f - ultimo_som >= 4
            ultimo_som = f
            pbSEPlay("Slots coin", 70) rescue nil
          end
        end
        Graphics.update
        Input.update
      end

      # garante o alinhamento exacto no fim (o arredondamento do easing podia
      # deixar a casa um pixel torta)
      roda.src_rect.set(total % LARGURA_TIRA, 0, janela, ALTURA)
      pbSEPlay("Slots stop", 90) rescue nil

      # piscar a casa premiada
      6.times do |i|
        ponteiro.opacity = (i.even? ? 140 : 255)
        4.times { Graphics.update; Input.update }
      end
      ponteiro.opacity = 255
      20.times { Graphics.update; Input.update }

      # ⚠️ O viewport vai no FIM da lista de proposito: liberta-lo antes
      # dos sprites que vivem dentro dele rebenta no RGSS.
      [escuro, roda, ponteiro, vp]
    end

    # Uma seta a apontar para baixo, por cima da moldura. Sem ela a moldura
    # sozinha lia-se como "esta casa esta seleccionada" e nao como "e aqui que
    # a roda vai parar" — que e o que faz o olho seguir o sitio certo.
    def pintar_ponteiro(bmp, centro)
      amarelo = Color.new(255, 210, 74, 255)
      escuro  = Color.new(120, 90, 20, 255)
      x0 = centro - (CELULA / 2)
      base_y = ESPACO_PONTEIRO

      # a seta: linhas cada vez mais estreitas, a fechar num bico em baixo
      lado = 11
      lado.times do |i|
        larg = (lado - i) * 2
        bmp.fill_rect(centro - larg / 2, i, larg, 1, i.zero? ? escuro : amarelo)
      end

      # moldura da casa central
      alt = ALTURA + 6
      bmp.fill_rect(x0, base_y - 3, CELULA, 3, amarelo)
      bmp.fill_rect(x0, base_y + alt - 3, CELULA, 3, amarelo)
      bmp.fill_rect(x0, base_y - 3, 3, alt, amarelo)
      bmp.fill_rect(x0 + CELULA - 3, base_y - 3, 3, alt, amarelo)
    end

    def fechar(sprites)
      return unless sprites
      sprites.each do |s|
        next unless s
        if s.is_a?(Viewport)
          s.dispose unless s.disposed?
        else
          s.bitmap.dispose if s.respond_to?(:bitmap) && s.bitmap && !s.bitmap.disposed?
          s.dispose unless s.disposed?
        end
      end
    rescue
      nil
    end

    # ------------------------------------------------------------- a jogada
    # `ficha` a nil = giro de borla (o /roleta do admin). Com ficha, e ela que
    # paga, e e cobrada ANTES de o premio ser revelado.
    def jogar!(ficha = nil)
      premio = sortear
      unless premio
        pbMessage(_INTL("A roleta está fora de serviço.")) rescue nil
        return false
      end

      # ⚠️ A MOCHILA PRIMEIRO. Ver o aviso no topo do ficheiro.
      unless pode_dar?(premio)
        pbMessage(_INTL("Sua mochila está cheia demais para girar a roleta.")) rescue nil
        return false
      end

      # ⚠️ COBRA-SE A FICHA AQUI, E GRAVA-SE ANTES DA ANIMACAO.
      #
      # Nao e pela duplicacao, e pelo SORTEIO. Enquanto a ficha so saisse da
      # mochila no fim, quem visse a roleta parar num premio mau fechava o jogo
      # a meio do giro (sao quase tres segundos, ha tempo de sobra) e voltava a
      # entrar com a ficha intacta para girar outra vez. Um cassino onde se
      # pode repetir a jogada nao cobra nada.
      #
      # A ordem certa e:  cabe? -> cobra -> da -> GRAVA -> anima.
      # Quando a roleta comeca a girar, o resultado ja esta em disco.
      if ficha
        return false unless $bag && $bag.has?(ficha)
        $bag.remove(ficha, 1)
      end

      unless dar!(premio)
        ($bag.add(ficha, 1) rescue nil) if ficha   # nao se fica com a ficha por nada
        pbMessage(_INTL("Sua mochila está cheia demais para girar a roleta.")) rescue nil
        return false
      end

      gravar!

      casas = montar_casas(premio)
      vencedora = casas.index(premio) || 0
      log("girou: #{premio} na casa #{vencedora} de #{casas.inspect}")

      sprites = nil
      begin
        sprites = girar!(casas, vencedora)
      ensure
        fechar(sprites)
      end

      nome = nome_de(premio)
      pbMEPlay("Item get") rescue nil
      if defined?(AnilLanRework) && AnilLanRework.respond_to?(:add_popup)
        real, _q = resolver(premio)
        AnilLanRework.add_popup(_INTL("A roleta parou em {1}!", nome), 6.0, real) rescue nil
      else
        pbMessage(_INTL("\\me[]A roleta parou em \\c[1]{1}\\c[0]!", nome)) rescue nil
      end
      true
    rescue => e
      log("falha na jogada: #{e.class}: #{e.message}")
      false
    end

    # ---------------------------------------------------------------- registo
    # Grava JA, com o premio ja na mochila e a ficha ja fora dela.
    def gravar!
      if defined?(AnilLanRework) && AnilLanRework.respond_to?(:gravar_ja!)
        AnilLanRework.gravar_ja!("cassino_roleta")
      elsif defined?(Game) && Game.respond_to?(:save)
        Game.save
      end
    rescue => e
      log("falha ao gravar: #{e.class}: #{e.message}")
    end

    def registar!
      return unless ACTIVO
      return if $anil_ficha_cassino_registada
      $anil_ficha_cassino_registada = true
      GameData::Item.register(DEF_FICHA) rescue nil

      # ⚠️ A FICHA NAO CAI DE LADO NENHUM, E ISSO E DE PROPOSITO.
      #
      # Eu tinha-a acrescentado aos baralhos das caixas azul e laranja por
      # iniciativa propria; nao fazia parte do pedido. Onde e que ela se ganha
      # ainda esta por decidir, e ate la ninguem a recebe por acidente.
      log("ficha registada (sem fonte de drop)")
    rescue => e
      log("falha ao registar: #{e.class}: #{e.message}")
    end
  end
end

if defined?(EventHandlers) && EventHandlers.respond_to?(:add)
  EventHandlers.add(:on_enter_map, :anil_cassino_registar, proc { |_antigo|
    AnilCassinoRoleta.registar!
  })
end

#-------------------------------------------------------------------------------
# /roleta — girar sem gastar ficha, para testar.
#
# ⚠️ O PREMIO E DADO NA MESMA.
#
# E de proposito: se o comando so mostrasse a animacao, nao estaria a testar o
# caminho que interessa (sortear, caber na mochila, dar, animar). Um teste que
# salta o passo que pode falhar nao e um teste.
#
#   /roleta            gira uma vez
#   /roleta 5          gira cinco vezes seguidas
#   /roleta ficha      poe 10 fichas na mochila, para testar pelo menu
#   /roleta estado     diz se o item existe e quantas fichas ha
#-------------------------------------------------------------------------------
module AnilRoletaComando
  module_function

  def admin?
    return AnilEventoShinyComando.admin? if defined?(AnilEventoShinyComando)
    true
  rescue
    true
  end

  def avisar(txt)
    if AnilLanRework.respond_to?(:add_popup)
      AnilLanRework.add_popup(txt, 6.0) rescue nil
    else
      pbMessage(txt) rescue nil
    end
  end

  def tratar(texto)
    t = texto.to_s.strip
    return false unless t =~ %r{\A/roleta(?:\s+(.*))?\z}i
    arg = $1.to_s.strip.downcase

    unless admin?
      avisar(_INTL("[Roleta] Apenas administradores."))
      return true
    end

    unless AnilCassinoRoleta::ACTIVO
      avisar(_INTL("[Roleta] Desligada (AnilCassinoRoleta::ACTIVO = false)."))
      return true
    end

    # A ficha so nasce no on_enter_map; num teste logo ao arrancar ela pode
    # ainda nao existir, e ai o comando nao tinha o que consumir nem que dar.
    AnilCassinoRoleta.registar! rescue nil

    if arg == "estado"
      existe = (GameData::Item.exists?(AnilCassinoRoleta::FICHA) rescue false)
      quantas = ($bag.quantity(AnilCassinoRoleta::FICHA) rescue 0)
      avisar(_INTL("[Roleta] item={1} fichas={2} pool={3}",
                   existe ? "sim" : "NAO", quantas,
                   (defined?(GiftBoxSystem) ? GiftBoxSystem::RED_POOL.length : 0)))
      return true
    end

    if arg == "ficha" || arg == "fichas"
      if $bag.can_add?(AnilCassinoRoleta::FICHA, 10)
        $bag.add(AnilCassinoRoleta::FICHA, 10)
        avisar(_INTL("[Roleta] 10 fichas na mochila."))
      else
        avisar(_INTL("[Roleta] Não coube na mochila."))
      end
      return true
    end

    vezes = arg.to_i
    vezes = 1 if vezes <= 0
    vezes = 10 if vezes > 10
    vezes.times { AnilCassinoRoleta.jogar! }
    true
  rescue => e
    AnilCassinoRoleta.log("falha no comando: #{e.class}: #{e.message}")
    false
  end
end

module AnilLanRework
  module Chat
    class << self
      unless method_defined?(:anil_roleta_orig_send_message)
        alias_method :anil_roleta_orig_send_message, :send_message rescue nil
      end

      def send_message(text)
        return if AnilRoletaComando.tratar(text)
        anil_roleta_orig_send_message(text)
      end
    end
  end
end

# ⚠️ Os handlers so se podem instalar DEPOIS de o item existir, e o item so
# nasce no primeiro on_enter_map. Instalam-se aqui a mesma, porque o
# ItemHandlers guarda por simbolo e nao exige que o item ja esteja registado.
if defined?(ItemHandlers)
  ItemHandlers::UseFromBag.add(AnilCassinoRoleta::FICHA, proc { |_item|
    next (AnilCassinoRoleta.jogar!(AnilCassinoRoleta::FICHA) ? 1 : 0)   # 1 = nao fecha a mochila
  })
  # ⚠️ SO O UseFromBag.
  #
  # O UseInField e para itens-chave registados no atalho do campo, e o retorno
  # dele nao consome nada. Numa ficha consumivel isso era uma volta de graca se
  # algum dia o caminho ficasse alcancavel. Uma porta so, e e a que cobra.
end

AnilLanRework.log("158_Cassino_Roleta carregado") rescue nil
