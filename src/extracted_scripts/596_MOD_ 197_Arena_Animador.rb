# encoding: utf-8
#===============================================================================
# O ANIMADOR DA ARENA
#
# ⚠️ PORQUE UM MOTOR NOVO, DEPOIS DE TANTO REMENDO.
#
# O caminho antigo reaproveitava o `PBAnimationPlayerX` do jogo, e isso trazia
# atrás seis sistemas a decidir a mesma coisa:
#
#     setLineTransform      estica os eixos entre duas pontas do palco
#     aplicar_feitio!       repoe as celulas pela regra do editor
#     encolher_animacao!    aperta posicoes e tamanhos
#     seguir_animacao!      desloca tudo pela camara
#     sprite_ancora         fotografa as duas ancoras no disparo
#     CenaFalsa             finge um palco de batalha para o motor
#
# Cada um deles produziu pelo menos um defeito nesta ronda, e vários só
# apareciam quando dois se encontravam. Nenhum estava errado sozinho.
#
# ⚠️ E A RAIZ, QUE NENHUM REMENDO PODIA TAPAR.
#
# Todos eles partiam do mesmo pressuposto: que a animação está desenhada em
# volta das âncoras do palco — quem lança em (128,224), quem leva em (384,96).
# Medido nas 35 animações marcadas "alvo" deste jogo, isso é falso em quase
# todas, e a pior está a 9,65 casas de distância da âncora.
#
# Uma animação do Essentials não é um efeito centrado em alguém. É uma
# composição num ecrã de 512x384, onde o autor pôs as coisas onde lhe deu jeito
# porque os dois combatentes nunca saem do sítio. Mapear esse ecrã para um mapa
# onde os bonecos andam livremente não tem solução exacta — é a pergunta que
# está errada.
#
# ⚠️ A PERGUNTA CERTA, E O QUE ESTE FICHEIRO FAZ DE DIFERENTE.
#
# Não se mapeia o palco. Toma-se a animação como um DESENHO, mede-se o centro
# dele, e põe-se esse centro em cima de quem interessa:
#
#     posicao = ancora + (celula - centro_do_desenho) * escala + ajuste
#
# O `centro_do_desenho` sai da própria animação (a caixa que as celulas ocupam
# no quadro do impacto), e não do palco. Por construção o desenho fica centrado
# no alvo — em qualquer ângulo, a qualquer distância, para qualquer animação,
# esteja ela desenhada onde estiver na folha. Não há eixo para perder porque
# não há eixo emprestado.
#
# O modo "feixe" NÃO passa por aqui: lá a animação é mesmo uma linha entre dois
# pontos, o mapeamento faz sentido, e o caminho antigo já está afinado e
# verificado contra o editor (12 960 comparações, zero divergências).
#===============================================================================
module AnilArenaAnimador
  # O motor corre as animações a 20 quadros por segundo.
  CADENCIA = 20.0

  # O mesmo tecto de tamanho do caminho antigo: uma animação de ecrã inteiro
  # por cima de bonecos de 32 px tapa o combate.
  MANCHA_MAX = 260.0
  PECA_MAX   = 190.0

  # As celulas de foco 4 são clarões que cobrem os 512x384 inteiros. Numa
  # batalha há cenário por trás; num mapa são uma mancha ao lado do golpe.
  FOCO_ECRA = 4

  @efeitos = []

  class << self
    attr_reader :efeitos
  end

  #-----------------------------------------------------------------------------
  # UM EFEITO A CORRER
  #-----------------------------------------------------------------------------
  class Efeito
    # ⚠️ O QUE FAZ UMA COPIA SER UMA COPIA.
    #
    # Para o "gerar com a animacao inteira" preciso de N execucoes da MESMA
    # animacao, cada uma afastada, rodada e redimensionada por sua conta. Em vez
    # de um caminho novo, a `Efeito` ganha um desvio que alguem de fora escreve
    # a cada frame — a receita das particulas — e ela soma-o ao desenho.
    #
    # `desvio_extra` e `[dx, dy, escala, angulo, opacidade]` (0..255), ou nil
    # para uma execucao normal. A opacidade MULTIPLICA a da celula em vez de a
    # substituir: uma celula que a animacao quer invisivel continua invisivel.
    attr_accessor :desvio_extra

    # ⚠️ E AS COPIAS SAO MUDAS, SENAO SAO SEIS TROVOES.
    #
    # Os sons estao marcados por quadro da animacao. Seis copias da mesma
    # animacao tocariam o mesmo som seis vezes no mesmo frame — o que nao soa a
    # um golpe maior, soa a um estalo. So o original fala.
    attr_accessor :mudo

    #---------------------------------------------------------------------------
    # ⚠️ PORQUE E QUE TUDO VOA PARA CIMA E PARA A DIREITA.
    #
    # Uma animacao do Essentials foi desenhada para um palco onde quem lanca
    # esta em (128,224) e o alvo em (384,96). Esse eixo tem um angulo fixo:
    #
    #     atan2(96 - 224, 384 - 128) = -26,57 graus
    #
    # Ou seja, NO PALCO o alvo esta sempre em cima e a direita. Todo o golpe que
    # viaja — o Swift, o Petal Blizzard, qualquer coisa que saia de um e chegue
    # ao outro — foi desenhado a subir nessa diagonal.
    #
    # O animador trata a animacao como um desenho e assenta-lhe o meio no
    # boneco. Para um golpe que rebenta em cima do alvo isso chega. Para um que
    # VIAJA nao chega: ele continua a subir para a direita, esteja o inimigo
    # onde estiver. E o que se ve na oficina — as estrelas a saltar para cima em
    # vez de irem ter com o alvo.
    #
    # Apontar e rodar o desenho de modo a que o eixo do palco caia em cima do
    # eixo verdadeiro, e estica-lo para ele chegar la. Duas contas, e o resto da
    # animacao — as cores, os tempos, os sons — fica exactamente como estava.
    #---------------------------------------------------------------------------
    PALCO_QUEM = [128.0, 224.0].freeze
    PALCO_ALVO = [384.0,  96.0].freeze
    PALCO_ANG  = Math.atan2(PALCO_ALVO[1] - PALCO_QUEM[1],
                            PALCO_ALVO[0] - PALCO_QUEM[0])
    PALCO_DIST = Math.hypot(PALCO_ALVO[0] - PALCO_QUEM[0],
                            PALCO_ALVO[1] - PALCO_QUEM[1])

    def initialize(anim, ancora, cfg, viewport, desde = 0, outro = nil)
      @anim     = anim
      @ancora   = ancora
      # A outra ponta do golpe. So serve para apontar; sem ela, nao se aponta.
      @outro    = outro
      @cfg      = cfg || {}
      @viewport = viewport
      @quadros  = anim.length.to_i
      @quadro   = [desde.to_i, 0].max
      @relogio  = 0.0
      @sprites  = []
      @vivo     = true
      @tocados  = {}
      @folha    = nil
      @desvio_extra = nil
      @mudo     = false
      @apontar  = (@cfg["apontar"] ? true : false) && !@outro.nil?
      montar_folha!
      medir_centro!
      medir_tecto!
      pintar!
    end

    def vivo?; @vivo; end

    # ── a folha ───────────────────────────────────────────────────────────────
    def montar_folha!
      nome = (@anim.graphic.to_s rescue "")
      return if nome.empty?
      @folha = (AnimatedBitmap.new("Graphics/Animations/" + nome,
                                   (@anim.hue.to_i rescue 0)).deanimate rescue nil)
    rescue
      @folha = nil
    end

    # ── o centro do DESENHO, que é a ideia toda ──────────────────────────────
    #
    # ⚠️ NÃO É A MÉDIA DOS QUADROS, É A CAIXA DO QUADRO QUE INTERESSA.
    #
    # A média trata os doze quadros do Wing Attack como se pesassem o mesmo. Só
    # que não são doze versões da mesma pose — são uma asa a descer sobre o
    # alvo. Centrar a média põe o meio do voo no bicho e deixa o impacto ao
    # lado, e o impacto é o único quadro que se olha para julgar se acertou.
    #
    # O quadro de referência é o que tem mais coisa a desenhar — o do
    # rebentamento. Os que vêm antes chegam até lá e os de depois desvanecem,
    # que é o que a animação quer dizer.
    # ⚠️ O EIXO MEDIDO PARTE-SE QUANDO SE GERAM PARTICULAS, E ISSO MEDIU-SE.
    #
    # A regra daqui e "o quadro com mais celulas manda". Ela serve enquanto a
    # animacao e so o golpe: o quadro mais cheio e o do impacto, e o centro dele
    # e o centro do golpe.
    #
    # O gerador de particulas do editor poe 8 a 24 celulas por quadro durante 12
    # a 30 quadros. Um golpe tem 1 a 6 por quadro. Ou seja, a partir do instante
    # em que se gera uma rajada, o quadro de referencia passa a ser SEMPRE um
    # quadro de particulas — e o eixo de tudo, incluindo as celulas originais do
    # golpe, passa a ser o centro da nuvem.
    #
    # Corrido o simulador a serio, com os presets a serio, o desvio que isso
    # causa (origem em 0,0):
    #
    #     Chafariz            0,08 casas
    #     Vortice             0,16 casas
    #     Fumaca              0,47 casas
    #     Tornado             0,42 casas
    #     Caindo do Ceu       4,20 casas   <- quatro casas ao lado
    #
    # Os simetricos quase nao mexem; os que nascem so de um lado arrastam a
    # animacao inteira com eles.
    #
    # A cura nao e adivinhar melhor: e deixar de adivinhar quando alguem sabe.
    # O editor sabe quais as celulas que sao do golpe e quais sao geradas, e
    # grava o eixo no palco. Havendo `ref_x`/`ref_y`, e esse que manda; nao
    # havendo, mede-se como sempre — e nada do que ja estava afinado muda.
    # ── onde a animacao COMECA e onde ACABA ─────────────────────────────────
    #
    # ⚠️ EU SUPUS O EIXO E A SUPOSICAO ESTAVA ERRADA.
    #
    # A primeira versao disto assumia que um golpe que viaja sai de (128,224) e
    # chega a (384,96) — as ancoras do palco. E verdade para muitos, e falso
    # para outros tantos: nada obriga o autor a desenhar as celulas em volta das
    # ancoras, e medido noutro sitio deste projecto so 6 de 17 animacoes "alvo"
    # estao centradas onde deviam.
    #
    # No Supersonic isso via-se: com o eixo preso a (128,224), os aneis nasciam
    # em baixo e a esquerda do Pikachu, porque as celulas dele nao estao la.
    #
    # A animacao sabe o seu proprio eixo: e a linha entre o meio do PRIMEIRO
    # quadro que desenha alguma coisa e o meio do ULTIMO. Nao ha nada a supor —
    # le-se. E se ela nao viajar (comeco e fim no mesmo sitio, como um golpe que
    # rebenta em cima do alvo), cai-se no eixo do palco, que e o melhor palpite
    # que resta.
    def medir_eixo_do_desenho!
      @eixo_p0 = nil
      @eixo_p1 = nil
      primeiro = nil
      ultimo = nil
      # A mancha: o rectangulo que TODAS as celulas ocupam, em todos os quadros.
      # Serve para saber se o deslocamento entre o principio e o fim e grande
      # ou pequeno a escala do proprio desenho.
      x1 = y1 = x2 = y2 = nil
      @quadros.times do |i|
        tem = false
        cada_celula(i) do |c|
          tem = true
          cx = c[AnimFrame::X].to_f
          cy = c[AnimFrame::Y].to_f
          x1 = cx if x1.nil? || cx < x1
          y1 = cy if y1.nil? || cy < y1
          x2 = cx if x2.nil? || cx > x2
          y2 = cy if y2.nil? || cy > y2
        end
        next unless tem
        primeiro = i if primeiro.nil?
        ultimo = i
      end
      if x1
        @caixa_w = (x2 - x1)
        @caixa_h = (y2 - y1)
      end
      return if primeiro.nil?
      @eixo_p0 = centro_do_quadro(primeiro)
      @eixo_p1 = centro_do_quadro(ultimo)
    rescue
      @eixo_p0 = nil
      @eixo_p1 = nil
    end

    def centro_do_quadro(iq)
      x1 = y1 = x2 = y2 = nil
      cada_celula(iq) do |c|
        cx = c[AnimFrame::X].to_f
        cy = c[AnimFrame::Y].to_f
        x1 = cx if x1.nil? || cx < x1
        y1 = cy if y1.nil? || cy < y1
        x2 = cx if x2.nil? || cx > x2
        y2 = cy if y2.nil? || cy > y2
      end
      return nil if x1.nil?
      [(x1 + x2) / 2.0, (y1 + y2) / 2.0]
    rescue
      nil
    end

    # O eixo que a animacao tem mesmo: [x0, y0, angulo, comprimento].
    # Cai no eixo do palco quando ela nao viaja.
    def eixo_do_desenho
      medir_eixo_do_desenho! if @eixo_p0.nil? && @eixo_p1.nil? && !@eixo_medido
      @eixo_medido = true
      p0 = @eixo_p0
      p1 = @eixo_p1
      if p0 && p1
        d = Math.hypot(p1[0] - p0[0], p1[1] - p0[1])
        # ⚠️ DEZASSEIS PIXEIS ERA POUCO, E O PETAL BLIZZARD PROVOU-O.
        #
        # Medido nas animacoes a serio:
        #
        #     Razor Leaf      452,6 px a -25,8 graus   viaja
        #     Swift           287,5 px a -34,7 graus   viaja
        #     Supersonic      273,8 px a -20,8 graus   viaja
        #     Petal Blizzard   19,6 px a  52,3 graus   <- ruido
        #
        # O Petal Blizzard e um remoinho: o meio do primeiro quadro e o do
        # ultimo caem quase no mesmo sitio, e os 19,6 px que os separam sao o
        # bater das petalas, nao um rumo. So que passavam o limiar de 16 — e o
        # golpe era rodado por 52,3 graus tirados do nada. Contra um inimigo a
        # direita, isso punha o remoinho na diagonal: exactamente o que se viu.
        #
        # Duas perguntas em vez de uma, e as duas tem de passar:
        #
        #   longe que chegue    64 px, duas casas. Os que viajam fazem 273 a
        #                       452; o remoinho faz 20.
        #   longe PARA O SEU    a viagem tem de valer pelo menos metade da
        #     TAMANHO           mancha que o desenho ocupa. Uma nuvem de 312 px
        #                       que se desloca 20 nao viajou; andou.
        #
        # A margem entre os dois grupos e enorme (20 contra 273), portanto isto
        # nao e afinacao fina — e uma linha desenhada no meio de um fosso.
        mancha = [(@caixa_w || 0.0), (@caixa_h || 0.0)].max
        viaja = (d >= 64.0) && (mancha <= 0.001 || d >= (mancha * 0.5))
        if viaja
          return [p0[0], p0[1], Math.atan2(p1[1] - p0[1], p1[0] - p0[0]), d, true]
        end
        # ⚠️ NAO VIAJA: PRENDE-SE, MAS NAO SE RODA.
        #
        # Um Supersonic sao aneis que se abrem no sitio; um Petal Blizzard e um
        # remoinho a volta de quem o lanca. Comeco e fim caem no mesmo ponto —
        # nao ha viagem nenhuma, e portanto nao ha rumo que se possa seguir.
        #
        # Rodar na mesma seria rodar por um angulo tirado ao acaso do ruido de
        # meia casa entre dois pontos que deviam ser o mesmo: o efeito ficava
        # virado para um lado diferente a cada golpe, sem nada que o explicasse.
        #
        # Para estes, apontar quer dizer so uma coisa — e e a que o utilizador
        # pediu: o eixo fica em cima de quem lanca. Nem giro, nem esticao.
        return [p0[0], p0[1], nil, nil, false]
      end
      [PALCO_QUEM[0], PALCO_QUEM[1], nil, nil, false]
    rescue
      [PALCO_QUEM[0], PALCO_QUEM[1], nil, nil, false]
    end

    def medir_centro!
      # ⚠️ A APONTAR, O EIXO SAI DA PROPRIA ANIMACAO.
      #
      # O ponto que fica preso a quem lanca e onde a animacao COMECA — o meio do
      # primeiro quadro que desenha alguma coisa. Assim ela nasce nele, seja
      # onde for que o autor a tenha desenhado.
      # ⚠️ SO SE ELA VIAJAR. Senao, apontar nao muda NADA.
      #
      # Uma animacao que nao viaja (o remoinho do Petal Blizzard) foi desenhada
      # a volta de um ponto — e no caso dele esse ponto e a ancora do ALVO, nao
      # a de quem lanca. Mudar-lhe o eixo arrancava-a de cima do inimigo e
      # punha-a em cima de mim.
      #
      # Ticar "apontar" num golpe que nao viaja passa a ser inofensivo: ele
      # comporta-se exactamente como se a caixa estivesse desligada.
      if @apontar
        e = eixo_do_desenho
        if e[4]
          @ref_x = e[0]
          @ref_y = e[1]
          return
        end
      end
      rx = @cfg["ref_x"]
      ry = @cfg["ref_y"]
      if rx && ry
        @ref_x = rx.to_f
        @ref_y = ry.to_f
        return
      end
      iq = quadro_do_impacto
      x1 = y1 = nil
      x2 = y2 = nil
      cada_celula(iq) do |c|
        cx = c[AnimFrame::X].to_f
        cy = c[AnimFrame::Y].to_f
        x1 = cx if x1.nil? || cx < x1
        y1 = cy if y1.nil? || cy < y1
        x2 = cx if x2.nil? || cx > x2
        y2 = cy if y2.nil? || cy > y2
      end
      if x1.nil?
        @ref_x = 256.0
        @ref_y = 192.0
      else
        @ref_x = (x1 + x2) / 2.0
        @ref_y = (y1 + y2) / 2.0
      end
    rescue
      @ref_x = 256.0
      @ref_y = 192.0
    end

    def quadro_do_impacto
      melhor = 0
      conta  = -1
      @quadros.times do |i|
        n = 0
        cada_celula(i) { |_c| n += 1 }
        if n > conta
          conta  = n
          melhor = i
        end
      end
      melhor
    rescue
      0
    end

    # ── o tecto de tamanho ───────────────────────────────────────────────────
    #
    # Mede-se uma vez, no quadro de referência, e vale para a animação inteira:
    # um factor que muda a meio faria a animação pulsar de tamanho.
    def medir_tecto!
      @k = 1.0
      iq = quadro_do_impacto
      x1 = y1 = x2 = y2 = nil
      maior = 0.0
      cada_celula(iq) do |c|
        cx = c[AnimFrame::X].to_f
        cy = c[AnimFrame::Y].to_f
        x1 = cx if x1.nil? || cx < x1
        y1 = cy if y1.nil? || cy < y1
        x2 = cx if x2.nil? || cx > x2
        y2 = cy if y2.nil? || cy > y2
        z = [(c[AnimFrame::ZOOMX].to_f).abs, (c[AnimFrame::ZOOMY].to_f).abs].max / 100.0
        lado = 192.0 * z
        maior = lado if lado > maior
      end
      return if x1.nil?
      mancha = [(x2 - x1), (y2 - y1)].max
      km = (mancha > MANCHA_MAX) ? (MANCHA_MAX / mancha) : 1.0
      kp = (maior  > PECA_MAX)   ? (PECA_MAX / maior)    : 1.0
      @k = [km, kp].min
      @k = 0.5 if @k < 0.5
    rescue
      @k = 1.0
    end

    # ── o que se desenha neste quadro ────────────────────────────────────────
    def cada_celula(iq)
      celulas = (@anim[iq] rescue nil)
      return unless celulas.is_a?(Array)
      esconder_fundo = (@cfg["sem_fundo"] ? true : false)
      celulas.each do |c|
        next unless c.is_a?(Array) && c.length > AnimFrame::FOCUS
        pad = c[AnimFrame::PATTERN]
        next if pad.nil? || pad.to_i < 0
        next if esconder_fundo && c[AnimFrame::FOCUS].to_i == FOCO_ECRA
        yield c
      end
    rescue
      nil
    end

    # ── onde a âncora está AGORA ─────────────────────────────────────────────
    #
    # Lê-se do sprite que o motor desenha, e não de uma conta paralela. O
    # `screen_x/y` sozinho não sabe do balanço de quem anda, do salto, nem da
    # erva alta — e uma conta que discorda da do motor é a origem de metade dos
    # defeitos que trouxeram este ficheiro a existir.
    def ponto_da_ancora
      return [Graphics.width / 2, Graphics.height / 2] unless @ancora
      (AnilArena.centro_do_boneco(@ancora) rescue
        [(@ancora.screen_x rescue 0), (@ancora.screen_y rescue 0) - 16])
    rescue
      [Graphics.width / 2, Graphics.height / 2]
    end

    # ── pintar um quadro ─────────────────────────────────────────────────────
    def pintar!
      return unless @folha && !(@folha.disposed? rescue true)
      ax, ay = ponto_da_ancora
      esc = (((@cfg["escala"] || 100).to_f / 100.0) * @k)
      esc = 0.05 if esc < 0.05
      dvx = (@cfg["desvio_x"] || 0).to_i
      dvy = (@cfg["desvio_y"] || 0).to_i
      eixo = @cfg["eixo_quadros"]
      if eixo.is_a?(Array) && @quadro >= 0 && @quadro < eixo.length
        par = eixo[@quadro]
        if par.is_a?(Array) && par.length >= 2
          dvx += par[0].to_i
          dvy += par[1].to_i
        end
      end

      # O desvio da copia: some-se a posicao, multiplica a escala, roda tudo.
      ex = 0
      ey = 0
      ang_extra = 0
      op_extra = 1.0
      if @desvio_extra.is_a?(Array) && @desvio_extra.length >= 4
        ex = @desvio_extra[0].to_i
        ey = @desvio_extra[1].to_i
        ke = @desvio_extra[2].to_f
        esc *= ke if ke > 0.001
        ang_extra = @desvio_extra[3].to_i
        op_extra = (@desvio_extra[4] || 255).to_f / 255.0
      end

      # ── o giro e o esticao, quando se aponta ──────────────────────────────
      giro = 0.0
      estica = 1.0
      if @apontar
        bx, by = ponto_do_outro
        vx = bx - ax
        vy = by - ay
        d = Math.hypot(vx, vy)
        if d > 0.001
          e = eixo_do_desenho
          if e[4]
            # Viaja: roda-se do eixo QUE A ANIMACAO TEM para o do combate.
            giro = Math.atan2(vy, vx) - e[2]
            # ⚠️ O ESTICAO E SO NA DISTANCIA, NAO NO TAMANHO.
            #
            # Multiplicar a escala fazia a estrela crescer com a distancia: de
            # perto era um ponto, de longe enchia o ecra. O que tem de esticar
            # e o CAMINHO — as pecas mantem o tamanho e espalham-se mais.
            estica = (e[3] > 0.001) ? (d / e[3]) : 1.0
            estica = 0.15 if estica < 0.15
            estica = 3.0  if estica > 3.0
          end
          # Nao viaja: `giro` e `estica` ficam como estao (0 e 1). O unico
          # efeito de apontar e o eixo, que o `medir_centro!` ja pos no comeco
          # do desenho — ou seja, em cima de quem lanca.
        end
      end
      cos_g = Math.cos(giro)
      sin_g = Math.sin(giro)
      giro_graus = -(giro * 180.0 / Math::PI)

      i = 0
      cada_celula(@quadro) do |c|
        sp = (@sprites[i] ||= Sprite.new(@viewport))
        sp.bitmap = @folha
        pad = c[AnimFrame::PATTERN].to_i
        sp.src_rect.set((pad % 5) * 192, (pad / 5) * 192, 192, 192)
        sp.ox = 96
        sp.oy = 96
        sp.blend_type = c[AnimFrame::BLENDTYPE].to_i
        # A peca roda com o caminho: uma estrela desenhada a apontar para cima e
        # para a direita passa a apontar para onde o golpe vai mesmo.
        sp.angle      = c[AnimFrame::ANGLE].to_i + ang_extra + giro_graus.round
        sp.mirror     = (c[AnimFrame::MIRROR].to_i > 0)
        sp.opacity    = (c[AnimFrame::OPACITY].to_i * op_extra).round
        sp.visible    = (c[AnimFrame::VISIBLE].to_i == 1)
        sp.zoom_x     = (c[AnimFrame::ZOOMX].to_f / 100.0) * esc
        sp.zoom_y     = (c[AnimFrame::ZOOMY].to_f / 100.0) * esc
        (sp.color.set(c[AnimFrame::COLORRED].to_i, c[AnimFrame::COLORGREEN].to_i,
                      c[AnimFrame::COLORBLUE].to_i, c[AnimFrame::COLORALPHA].to_i) rescue nil)
        (sp.tone.set(c[AnimFrame::TONERED].to_i, c[AnimFrame::TONEGREEN].to_i,
                     c[AnimFrame::TONEBLUE].to_i, c[AnimFrame::TONEGRAY].to_i) rescue nil)
        # ⚠️ ESTA É A LINHA QUE JUSTIFICA O FICHEIRO TODO.
        #
        # A posição sai da âncora viva mais o desvio da célula em relação ao
        # centro do próprio desenho. Não há palco, não há foco, não há linha, e
        # não há nada que dependa do ângulo entre os dois bonecos.
        # O desvio da celula em relacao ao eixo, rodado e esticado. Sem apontar,
        # `giro` e zero e `estica` e um — a conta e a mesma de sempre.
        ox = (c[AnimFrame::X].to_f - @ref_x) * esc * estica
        oy = (c[AnimFrame::Y].to_f - @ref_y) * esc * estica
        rx_c = (ox * cos_g) - (oy * sin_g)
        ry_c = (ox * sin_g) + (oy * cos_g)
        sp.x = (ax + rx_c + dvx + ex).round
        sp.y = (ay + ry_c + dvy + ey).round
        sp.z = 2000 + c[AnimFrame::PRIORITY].to_i
        i += 1
      end
      # Sobram sprites de um quadro mais cheio.
      while i < @sprites.length
        sp = @sprites[i]
        sp.visible = false if sp && !(sp.disposed? rescue true)
        i += 1
      end
      tocar_sons!
    rescue
      nil
    end

    # Os sons estão marcados por quadro, e um quadro saltado é um som perdido —
    # foi assim que já se perdeu o trovão do Thunder Shock.
    def tocar_sons!
      return if @mudo
      lista = (@anim.timing rescue nil)
      return unless lista.is_a?(Array)
      lista.each do |t|
        next unless (t.frame.to_i == @quadro rescue false)
        next unless (t.timingType.to_i == 0 rescue false)
        next if @tocados[t.object_id]
        @tocados[t.object_id] = true
        nome = (t.name.to_s rescue "")
        next if nome.empty?
        (pbSEPlay("Anim/#{nome}", (t.volume.to_i rescue 100),
                  (t.pitch.to_i rescue 100)) rescue nil)
      end
    rescue
      nil
    end

    # ── o relógio ────────────────────────────────────────────────────────────
    def actualizar(dt)
      return unless @vivo
      @relogio += dt.to_f
      passo = 1.0 / CADENCIA
      mudou = false
      while @relogio >= passo
        @relogio -= passo
        @quadro += 1
        mudou = true
      end
      if @quadro >= @quadros
        largar!
        return
      end
      # Mesmo sem mudar de quadro há trabalho: a âncora pode ter andado, e o
      # desenho tem de a acompanhar. É isto que faz o golpe ficar preso ao
      # bicho em vez de ficar pendurado no mapa.
      # ⚠️ Uma copia com desvio muda A CADA FRAME (a receita anima-a), mesmo com
      # a ancora quieta e o quadro na mesma. Sem esta condicao, as copias
      # ficavam paradas em cima umas das outras e via-se uma so.
      pintar! if mudou || ancora_mexeu? || @desvio_extra
    rescue
      largar!
    end

    # A outra ponta le-se do mesmo sitio que a ancora: o sprite que o motor
    # desenha. Se ela morreu ou saiu, fica-se com o ultimo sitio conhecido —
    # senao o golpe virava-se para o canto do ecra a meio do voo.
    def ponto_do_outro
      return @ultimo_outro || [Graphics.width / 2, Graphics.height / 2] unless @outro
      p = (AnilArena.centro_do_boneco(@outro) rescue
            [(@outro.screen_x rescue 0), (@outro.screen_y rescue 0) - 16])
      @ultimo_outro = p
      p
    rescue
      @ultimo_outro || [Graphics.width / 2, Graphics.height / 2]
    end

    def ancora_mexeu?
      p = ponto_da_ancora
      mexeu = (@ultimo_ponto != p)
      @ultimo_ponto = p
      # A apontar, mexer o ALVO tambem muda o desenho: o golpe tem de continuar
      # a apontar-lhe enquanto ele anda.
      if @apontar
        q = ponto_do_outro
        mexeu ||= (@ultimo_outro_visto != q)
        @ultimo_outro_visto = q
      end
      mexeu
    rescue
      false
    end

    def largar!
      @vivo = false
      @sprites.each do |sp|
        next unless sp
        (sp.dispose rescue nil) unless (sp.disposed? rescue true)
      end
      @sprites = []
      # A folha é nossa (o `deanimate` devolve um bitmap próprio), portanto
      # morre connosco. Deixá-la viva era um bitmap por golpe até ao fim da
      # sessão.
      (@folha.dispose rescue nil) if @folha && !(@folha.disposed? rescue true)
      @folha = nil
    rescue
      nil
    end
  end

  #-----------------------------------------------------------------------------
  # A PORTA
  #-----------------------------------------------------------------------------

  # Toca a animação `idx` centrada em `ancora` (um Game_Character).
  # `cfg` é o remendo do editor; `desde` salta quadros iniciais.
  def self.tocar!(idx, ancora, cfg = nil, desde = 0, outro = nil)
    return nil if idx.to_i <= 0
    # A mesma tabela que o caminho antigo usa, e memoizada la: pedi-la a parte
    # carregaria os 15 MB do `PkmnAnimations.rxdata` uma segunda vez.
    tabela = (AnilArena.animacoes_de_golpe rescue nil)
    return nil unless tabela && (tabela.respond_to?(:[]) rescue false)
    anim = (tabela[idx.to_i] rescue nil)
    return nil unless anim
    vp = (AnilArena.viewport_das_animacoes rescue nil)
    return nil unless vp
    e = Efeito.new(anim, ancora, cfg, vp, desde, outro)
    (@efeitos ||= []) << e
    e
  rescue
    nil
  end

  #-----------------------------------------------------------------------------
  # ESTA ANIMACAO VIAJA?
  #
  # ⚠️ QUEM ESCOLHE A ANCORA PRECISA DE SABER ISTO ANTES DE O EFEITO EXISTIR.
  #
  # O `tocar_no_character!` decide em quem a animacao se prende — e, a apontar,
  # essa escolha muda (passa a ser quem lanca). Mas so faz sentido muda-la se a
  # animacao viajar mesmo; um remoinho tem de ficar onde o modo dele diz.
  #
  # A conta e a mesma do `eixo_do_desenho`, feita uma vez por animacao e
  # guardada: sao 38 quadros a percorrer e isto seria chamado a cada golpe.
  #-----------------------------------------------------------------------------
  def self.viaja?(idx)
    @viaja ||= {}
    k = idx.to_i
    return @viaja[k] if @viaja.key?(k)
    @viaja[k] = medir_viagem(k)
  rescue
    false
  end

  def self.medir_viagem(idx)
    tabela = (AnilArena.animacoes_de_golpe rescue nil)
    return false unless tabela
    anim = (tabela[idx] rescue nil)
    return false unless anim
    n = (anim.length.to_i rescue 0)
    return false if n <= 0
    p0 = nil
    p1 = nil
    x1 = y1 = x2 = y2 = nil
    n.times do |i|
      cs = (anim[i] rescue nil)
      next unless cs.is_a?(Array)
      vis = cs.select do |c|
        c.is_a?(Array) && c.length > AnimFrame::FOCUS &&
          !c[AnimFrame::PATTERN].nil? && c[AnimFrame::PATTERN].to_i >= 0
      end
      next if vis.empty?
      xs = vis.map { |c| c[AnimFrame::X].to_f }
      ys = vis.map { |c| c[AnimFrame::Y].to_f }
      meio = [(xs.min + xs.max) / 2.0, (ys.min + ys.max) / 2.0]
      p0 ||= meio
      p1 = meio
      x1 = xs.min if x1.nil? || xs.min < x1
      y1 = ys.min if y1.nil? || ys.min < y1
      x2 = xs.max if x2.nil? || xs.max > x2
      y2 = ys.max if y2.nil? || ys.max > y2
    end
    return false unless p0 && p1 && x1
    d = Math.hypot(p1[0] - p0[0], p1[1] - p0[1])
    mancha = [(x2 - x1), (y2 - y1)].max
    (d >= 64.0) && (mancha <= 0.001 || d >= (mancha * 0.5))
  rescue
    false
  end

  def self.correr!(dt)
    return if @efeitos.nil? || @efeitos.empty?
    @efeitos.each { |e| e.actualizar(dt) }
    @efeitos.reject! { |e| !e.vivo? }
  rescue
    limpar!
  end

  def self.limpar!
    (@efeitos || []).each { |e| (e.largar! rescue nil) }
    @efeitos = []
  rescue
    @efeitos = []
  end

  def self.a_correr
    (@efeitos || []).length
  end
end
