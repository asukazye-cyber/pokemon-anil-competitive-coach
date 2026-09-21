#===============================================================================
# MOD 180 — Loja em grelha de encaixes
#===============================================================================
# Substitui a LISTA de texto da loja por um tabuleiro com 12 encaixes, com o
# icone de cada item pousado no seu buraco. O escolhido levanta-se, cresce, roda
# devagar de um lado para o outro e pulsa na cor da raridade; o anel do proprio
# encaixe fica verde. Ao mudar de pagina os icones apagam-se num clarao.
#
# Vale na loja normal E no mercado de itens dos jogadores. Fica de fora o
# mercado de POKEMON (OnlinePokemonMarketScene): la cada anuncio tem dono,
# especie e preco proprios, e doze icones iguais nao distinguem nada disso.
#
# O jogador pode voltar a lista antiga nas Opcoes.
#===============================================================================

class PokemonSystem
  attr_writer :loja_grelha
  def loja_grelha
    @loja_grelha = 0 if !@loja_grelha.is_a?(Integer)
    @loja_grelha
  end
end

module AnilLojaGrelha
  IMAGEM = "Graphics/UI/Mart/slots"

  # ⚠️ CAMADA DE BRILHO RECORTADA DO PROPRIO DESENHO.
  #
  # 320x286 com os 12 aneis nas posicoes exactas, dilatados 1px para taparem o
  # azul-marinho por baixo, e a branco — a cor vem do Sprite#color em runtime,
  # que e um tint de hardware e nao custa nada.
  #
  # Isto substitui a elipse que eu desenhava a mao. A elipse era uma
  # APROXIMACAO do desenho: os encaixes nao sao circulos perfeitos (sao
  # poligonos suavizados) e por mais que se acertasse o raio ficava sempre a
  # descoberto num sitio ou outro. Recortado do original, encaixa por
  # construcao.
  BRILHO = "Graphics/UI/Mart/slots_brilho"

  # ⚠️ TAMANHO FIXO NO ECRA, VENHA O PNG QUE VIER.
  #
  # A primeira versao tinha as coordenadas em pixeis da imagem de 306x294. Bastou
  # o updater repor um slots.png de 320x307 por cima para tudo sair do sitio: o
  # tabuleiro passava dos 512 de largura, entrava pela descricao adentro, e os
  # icones afastavam-se dos buracos cada vez mais para as pontas — porque as
  # coordenadas eram de uma imagem e os buracos de outra.
  #
  # Agora o sprite e ESCALADO para este tamanho (zoom = ALVO / bitmap.width), e
  # os centros saem de fraccoes. Medi as duas versoes do desenho e as fraccoes
  # batem a menos de 0,5% — sao uma propriedade da arte, nao do ficheiro. Assim
  # qualquer PNG que aterre fica alinhado.
  # ⚠️ ESTA MEDIDA E O PAINEL DO bg.png, MEDIDO A PIXEL.
  #
  # O que aparecia por tras do tabuleiro nao era a lista antiga: e o proprio
  # Graphics/UI/Mart/bg.png, que TRAZ DESENHADO o painel branco de borda ciano.
  # Nao ha sprite para esconder — ou se cobre, ou vê-se.
  #
  # A borda ciano ocupa x 192..511, y 0..285 (320x286), e a barra verde da
  # descricao comeca em y=286. Por isso o tabuleiro e exactamente 320x286 em
  # (192,0): cobre o painel todo e encosta a barra verde sem a invadir. Com
  # isto a descricao e o icone ficam onde o jogo base os punha e nao se lhes
  # toca.
  #
  # Custo: o painel tem proporcao 1,119 e o desenho 1,041, portanto os encaixes
  # ficam ~7% mais largos que altos. Por isso o anel de seleccao e uma ELIPSE
  # (RAIO_X != RAIO_Y) e nao um circulo — se fosse circulo e que se via.
  ALVO_W = 320
  ALVO_H = 286

  # ⚠️ MEDIDO NO FICHEIRO DE 320x286, NAO CONVERTIDO DO ANTERIOR.
  #
  # As fraccoes vinham do desenho de 306x294 e a primeira linha caiu em y=58
  # quando o centro real e 59,5 — 2px acima, o suficiente para o anel deixar
  # ver o azul-marinho por baixo em cima e nao em baixo. Estes numeros saem de
  # um corte pelo centro de cada encaixe no PROPRIO ficheiro:
  #
  #   corte horizontal: escuro em -32..-28 e +27..+31  -> centro 51,5  raio 32
  #   corte vertical  : escuro em -29..-25 e +26..+30  -> centro 148,5 raio 30
  #
  # A banda escura tem 5px, que e a espessura que o anel usa para a tapar.
  FRAC_COL    = [0.16250, 0.38750, 0.61250, 0.84063]
  FRAC_LIN    = [0.20979, 0.52098, 0.81818]
  FRAC_RAIO_X = 0.10000
  FRAC_RAIO_Y = 0.10490

  COLUNAS = FRAC_COL.map { |f| (f * ALVO_W).round }    # [52, 124, 196, 269]
  LINHAS  = FRAC_LIN.map { |f| (f * ALVO_H).round }    # [60, 149, 234]
  RAIO_X  = (FRAC_RAIO_X * ALVO_W).round               # 32
  RAIO_Y  = (FRAC_RAIO_Y * ALVO_H).round               # 30

  # Caixa do recorte. Os aneis dilatados medem ~67x63; sobra folga dos dois
  # lados para nenhum ficar cortado.
  CORTE_W = 72
  CORTE_H = 68

  POR_PAGINA = COLUNAS.length * LINHAS.length          # 12

  def self.tab_x; Graphics.width - ALVO_W; end         # 192
  def self.tab_y; 0; end

  CORES = {
    # Quase branco de proposito: o encaixe ja e cinzento-azulado, e um cinzento
    # a serio nao se distinguia dele — o anel do item mais barato deixava de
    # ler-se como "seleccionado".
    :grey   => [235, 242, 248],
    :green  => [ 90, 220, 110],
    :blue   => [ 80, 170, 255],
    :purple => [190, 110, 255],
    :orange => [255, 160,  40]
  }

  LARANJA = [
    :MASTERBALL, :PPMAX, :ABILITYCAPSULE, :ABILITYPATCH, :RARECANDY, :PPUP,
    :MAXREVIVE, :OLDAMBER, :HELIXFOSSIL, :DOMEFOSSIL, :SHINYZADOR
  ]

  ARQUIVO = "Data/anil_loja_grelha.txt"

  def self.registar(txt)
    File.open(ARQUIVO, "ab") { |f| f.write("[#{Time.now.strftime('%d/%m %H:%M:%S')}] #{txt}\n") }
  rescue
  end

  def self.ligada?
    ($PokemonSystem.loja_grelha rescue 0) == 0
  end

  # ⚠️ As cenas do mercado vivem em AnilLanRework::PlayerMarket, nao em
  # AnilLanRework. Escrever o caminho a mao ja falhou uma vez; isto procura a
  # constante e devolve nil se ela nao existir, sem rebentar.
  def self.classe(nome)
    Object.const_get(nome)
  rescue
    nil
  end

  def self.cena_mercado_itens
    classe("AnilLanRework::PlayerMarket::OnlineItemMarketScene")
  end

  def self.cena_mercado_pokemon
    classe("AnilLanRework::PlayerMarket::OnlinePokemonMarketScene")
  end

  # A raridade sai do PRECO: e uma loja, e o que custa mais e o que o jogador
  # quer ver a brilhar. A lista de cima entra por cima disso.
  def self.raridade(item, preco)
    sym = (item.to_sym rescue nil)
    return :orange if sym && LARANJA.include?(sym)
    p = preco.to_i
    return :grey   if p <    500
    return :green  if p <   1500
    return :blue   if p <   5000
    return :purple if p <  20000
    :orange
  end

  def self.cor(item, preco)
    CORES[raridade(item, preco)] || CORES[:grey]
  end

  # ⚠️ ANEL ELIPTICO — muda a cor do proprio encaixe.
  #
  # O RGSS nao tem primitiva de elipse: faz-se por linhas, uma fill_rect por y.
  # Sao ~60 chamadas e NAO corre por frame — so quando muda a seleccao (ver
  # @grelha_anel_slot). O que respira por frame e a opacidade, que nao redesenha.
  def self.desenhar_anel(bitmap, cor, rx, ry, espessura)
    bitmap.clear
    cx = bitmap.width  / 2.0
    cy = bitmap.height / 2.0
    rxi = rx - espessura
    ryi = ry - espessura
    c   = Color.new(cor[0], cor[1], cor[2], 255)
    y   = 0
    while y < bitmap.height
      dy = (y + 0.5) - cy
      if dy.abs <= ry
        xe = rx * Math.sqrt([1.0 - ((dy * dy) / (ry * ry).to_f), 0.0].max)
        if ryi > 0 && dy.abs < ryi
          xi   = rxi * Math.sqrt([1.0 - ((dy * dy) / (ryi * ryi).to_f), 0.0].max)
          larg = (xe - xi).round
          if larg > 0
            bitmap.fill_rect((cx - xe).round, y, larg, 1, c)
            bitmap.fill_rect((cx + xi).round, y, larg, 1, c)
          end
        else
          bitmap.fill_rect((cx - xe).round, y, (xe * 2).round, 1, c)
        end
      end
      y += 1
    end
  end
end

MenuHandlers.add(:options_menu, :loja_grelha, {
  "name"        => _INTL("Vitrine da Loja"),
  "order"       => 145,
  "type"        => EnumOption,
  "parameters"  => [_INTL("Encaixes"), _INTL("Lista")],
  "description" => _INTL("Escolhe se a loja mostra os itens em encaixes ou na lista antiga."),
  "get_proc"    => proc { next $PokemonSystem.loja_grelha },
  "set_proc"    => proc { |value, _scene| $PokemonSystem.loja_grelha = value }
})

#===============================================================================
# Instalacao depois dos plugins
#===============================================================================
module AnilLanRework
  class << self
    unless method_defined?(:loja_grelha_apply_post_plugin_patches)
      alias loja_grelha_apply_post_plugin_patches apply_post_plugin_patches
    end

    def apply_post_plugin_patches
      loja_grelha_apply_post_plugin_patches
      begin
        AnilLojaGrelha.instalar!
      rescue => e
        AnilLojaGrelha.registar("INSTALAR: falhou #{e.class}: #{e.message}") rescue nil
      end
    end
  end
end

module AnilLojaGrelha
  def self.instalar!
    if !defined?(PokemonMart_Scene)
      registar("INSTALAR: PokemonMart_Scene nao existe")
      return
    end
    if PokemonMart_Scene.method_defined?(:grelha_orig_pbRefresh)
      registar("INSTALAR: ja estava instalado")
      return
    end
    registar("INSTALAR: alias em PokemonMart_Scene")

    PokemonMart_Scene.class_eval do
      alias_method :grelha_orig_start,     :pbStartBuyOrSellScene
      alias_method :grelha_orig_pbRefresh, :pbRefresh
      alias_method :grelha_orig_escolher,  :pbChooseBuyItem
      alias_method :grelha_orig_update,    :update
      alias_method :grelha_orig_fim,       :pbEndBuyScene

      def grelha_activa?
        @grelha_on ? true : false
      end

      # ⚠️ QUEM ENTRA. O mercado de POKEMON fica sempre de fora — ver cabecalho.
      def grelha_elegivel?
        g = AnilLojaGrelha
        pk = g.cena_mercado_pokemon
        return false if pk && self.is_a?(pk)
        return true  if self.instance_of?(PokemonMart_Scene)
        it = g.cena_mercado_itens
        return true  if it && self.instance_of?(it)
        false
      end

      # A entrada da lista pode ser um simbolo de item (loja normal) ou um
      # anuncio (mercado). O adaptador do mercado sabe converter.
      def grelha_icone_de(entrada)
        return nil if entrada.nil?
        if @adapter.respond_to?(:icon_item)
          (@adapter.icon_item(entrada) rescue entrada)
        else
          entrada
        end
      end

      def pbStartBuyOrSellScene(buying, stock, adapter)
        grelha_orig_start(buying, stock, adapter)
        @grelha_on = false
        g = AnilLojaGrelha
        if !buying
          g.registar("LOJA: a vender (#{self.class}) — grelha nao se aplica")
          return
        end
        if !g.ligada?
          g.registar("LOJA: desligada nas Opcoes — fica com a lista")
          return
        end
        if !grelha_elegivel?
          g.registar("LOJA: #{self.class} fora do ambito — fica com a lista")
          return
        end
        if !pbResolveBitmap(g::IMAGEM)
          g.registar("LOJA: FALTA #{g::IMAGEM}.png — fica com a lista")
          return
        end
        g.registar("LOJA: grelha LIGADA em #{self.class}, #{stock.length} item(ns)")
        grelha_montar!
      end

      def grelha_montar!
        g = AnilLojaGrelha
        @grelha_on   = true
        @grelha_pag  = 0
        @grelha_slot = 0
        @grelha_t    = 0
        @grelha_anel_slot = -1

        @sprites["itemwindow"].visible = false

        tab = IconSprite.new(g.tab_x, g.tab_y, @viewport)
        tab.setBitmap(g::IMAGEM)
        # ⚠️ O zoom e o que torna isto imune ao tamanho do ficheiro. Ver o
        # comentario em ALVO_W: com o PNG certo da 1.0 exacto.
        if tab.bitmap && tab.bitmap.width > 0
          tab.zoom_x = g::ALVO_W.to_f / tab.bitmap.width
          tab.zoom_y = g::ALVO_H.to_f / tab.bitmap.height
        end
        tab.z = 50
        @sprites["tabuleiro"] = tab

        # ox/oy no meio: x e y passam a ser o CENTRO do encaixe, sem aritmetica
        # de canto para enganar.
        # A camada e opcional: se faltar, cai-se na elipse desenhada a mao.
        @grelha_brilho = nil
        if pbResolveBitmap(g::BRILHO)
          @grelha_brilho = (AnimatedBitmap.new(g::BRILHO) rescue nil)
        end
        g.registar("BRILHO: #{@grelha_brilho ? 'camada carregada' : 'em falta — elipse a mao'}")

        anel = BitmapSprite.new(g::CORTE_W, g::CORTE_H, @viewport)
        anel.ox = g::CORTE_W / 2
        anel.oy = g::CORTE_H / 2
        anel.z  = 51
        @sprites["gcursor"] = anel

        g::POR_PAGINA.times do |i|
          s = ItemIconSprite.new(0, 0, nil, @viewport)
          s.blankzero = true
          s.setOffset(PictureOrigin::CENTER)
          s.z = 52
          @sprites["gi#{i}"] = s
        end

        # ⚠️ z EXPLICITO: sem ele esta janela fica por baixo do bg.png
        # semi-transparente da loja e o texto sai esbatido, com o mapa a
        # ver-se por tras.
        w = Window_AdvancedTextPokemon.new("")
        pbPrepareWindow(w)
        w.setSkin("Graphics/Windowskins/goldskin")
        w.viewport    = @viewport
        w.x           = 0
        w.y           = 96
        w.width       = 190
        w.height      = 96
        w.baseColor   = Color.new(88, 88, 80)
        w.shadowColor = Color.new(168, 184, 184)
        w.z           = 150
        @sprites["gnome"] = w

        # ⚠️ NAO SE TOCA NA DESCRICAO NEM NO ICONE.
        #
        # Ambos ja estao onde o bg.png os espera: a barra verde comeca em y=286
        # e a caixinha do icone e o quadrado branco em x 8..63, y 306..361. Como
        # o tabuleiro agora acaba em 285, nao ha colisao nenhuma e o layout do
        # jogo base serve tal e qual. Mexer-lhes so criou problemas: numa
        # versao o icone tapava a primeira palavra da descricao, noutra a
        # segunda linha do texto saia cortada.

        grelha_encher!
      end

      def grelha_indice(slot = nil)
        (AnilLojaGrelha::POR_PAGINA * @grelha_pag) + (slot || @grelha_slot)
      end

      def grelha_item(slot = nil)
        i = grelha_indice(slot)
        (i < @stock.length) ? @stock[i] : nil
      end

      def grelha_preco_bruto(entrada)
        return 0 if entrada.nil?
        v = (@adapter.getPrice(entrada) rescue nil)
        return v.to_i if v.is_a?(Numeric)
        # No mercado o preco so vem formatado ("2,000,000"). Tira-se o que nao
        # e digito em vez de desistir — a raridade depende disto.
        t = (@adapter.getDisplayPrice(entrada).to_s rescue "")
        t.gsub(/[^0-9]/, "").to_i
      end

      # ⚠️ O pbRefresh original le o item de @sprites["itemwindow"].item.
      #
      # Em vez de duplicar as janelas de dinheiro, descricao e "Na Mochila",
      # aponta-se o indice da lista escondida ao encaixe escolhido e deixa-se o
      # codigo de sempre fazer o resto. Assim o alias do MOD 058 (loja de
      # moedas) continua a apanhar tudo sem saber que existe uma grelha.
      def pbRefresh
        if grelha_activa?
          iw = @sprites["itemwindow"]
          iw.index = [grelha_indice, @stock.length].min if iw
        end
        grelha_orig_pbRefresh
        grelha_nome! if grelha_activa?
      end

      def grelha_nome!
        w = @sprites["gnome"]
        return if !w
        # ⚠️ NAO ESTAVA ATRAS DA JANELA — ESTAVA ESCURO SOBRE ESCURO.
        #
        # Copiei as cores da criacao do moneywindow, que sao Color(88,88,80)
        # sobre a goldskin. Só que o pbRefresh do jogo REPINTA o moneywindow a
        # branco a cada passagem, e eu nao fiz o mesmo — o nome ficava cinzento
        # escuro sobre um fundo escuro e lia-se como estando por baixo.
        #
        # (O bg.png nao tem culpa: medi o alpha dele em toda a coluna esquerda
        # e e 0 — nao tapa nada.)
        w.baseColor   = Color.new(250, 250, 250)
        w.shadowColor = Color.new(75, 75, 75)
        e = grelha_item
        if e.nil?
          w.text = ""
          return
        end
        nome  = (@adapter.getDisplayName(e)  rescue "")
        preco = (@adapter.getDisplayPrice(e) rescue "")
        w.text = "#{nome}\n<r>#{preco}"
      end

      def update
        grelha_orig_update
        grelha_animar! if grelha_activa?
      end

      # ⚠️ Tudo por FRAME, e o motor corre a 60fps. 0.05 rad/frame da uma volta
      # do balanco em ~2,1s e 0.06 um pulso em ~1,75s. Nao ha outro relogio.
      def grelha_animar!
        g = AnilLojaGrelha
        @grelha_t += 1
        balanco = Math.sin(@grelha_t * 0.05) * 11.0
        pulso   = (Math.sin(@grelha_t * 0.06) * 0.5) + 0.5

        g::POR_PAGINA.times do |i|
          s = @sprites["gi#{i}"]
          next if !s || s.disposed? || !s.visible
          bx = g.tab_x + g::COLUNAS[i % g::COLUNAS.length]
          by = g.tab_y + g::LINHAS[i / g::COLUNAS.length]
          if i == @grelha_slot
            e   = grelha_item(i)
            cor = g.cor(grelha_icone_de(e), grelha_preco_bruto(e))
            s.x      = bx
            s.y      = by - 7
            s.angle  = balanco
            # 1.18 e o tecto: o encaixe tem 60px na vertical (o lado mais
            # apertado) e o icone 48, logo 48*1.18=57 ainda cabe. Mais do que
            # isto transborda por cima do anel.
            s.zoom_x = 1.18
            s.zoom_y = 1.18
            s.color  = Color.new(cor[0], cor[1], cor[2], (35 + (pulso * 115)).to_i)
            s.z      = 53
          else
            s.x      = bx
            s.y      = by
            s.angle  = 0
            s.zoom_x = 1.0
            s.zoom_y = 1.0
            s.color  = Color.new(0, 0, 0, 0)
            s.z      = 52
          end
        end

        c = @sprites["gcursor"]
        if c && !c.disposed?
          # ⚠️ SEM o -7 do levantamento.
          #
          # O anel e o ENCAIXE a acender, nao o item. Levantava com o icone e
          # ficava 7px acima do anel azul-marinho do desenho, o que se lia como
          # estar descentrado. Quem sai do buraco e o item; o buraco fica.
          c.x = g.tab_x + g::COLUNAS[@grelha_slot % g::COLUNAS.length]
          c.y = g.tab_y + g::LINHAS[@grelha_slot / g::COLUNAS.length]
          if @grelha_anel_slot != @grelha_slot
            @grelha_anel_slot = @grelha_slot
            e   = grelha_item
            cor = g.cor(grelha_icone_de(e), grelha_preco_bruto(e))
            c.bitmap.clear
            if @grelha_brilho && @grelha_brilho.bitmap && !@grelha_brilho.bitmap.disposed?
              # ⚠️ Recorta o anel DESTE encaixe da camada.
              #
              # As coordenadas do recorte sao as do desenho (locais a camada),
              # nao as do ecra — a camada e do tamanho do tabuleiro, portanto os
              # centros sao os mesmos COLUNAS/LINHAS sem o tab_x/tab_y.
              c.bitmap.blt(0, 0, @grelha_brilho.bitmap,
                           Rect.new(g::COLUNAS[@grelha_slot % g::COLUNAS.length] - (g::CORTE_W / 2),
                                    g::LINHAS[@grelha_slot / g::COLUNAS.length] - (g::CORTE_H / 2),
                                    g::CORTE_W, g::CORTE_H))
              # A camada e branca; a cor da raridade entra como tint, que e de
              # hardware — nao ha trabalho por pixel nenhum.
              c.color = Color.new(cor[0], cor[1], cor[2], 255)
            else
              c.color = Color.new(0, 0, 0, 0)
              g.desenhar_anel(c.bitmap, cor, g::RAIO_X, g::RAIO_Y, 5)
            end
          end
          c.opacity = (170 + (pulso * 85)).to_i
          c.visible = !grelha_item.nil?
        end
      end

      def grelha_virar_pagina!(passo)
        g = AnilLojaGrelha
        nova = @grelha_pag + passo
        return false if nova < 0
        return false if nova * g::POR_PAGINA >= @stock.length

        9.times do |f|
          a = (f + 1) / 9.0
          g::POR_PAGINA.times do |i|
            s = @sprites["gi#{i}"]
            next if !s || s.disposed? || !s.visible
            s.color   = Color.new(255, 255, 255, (a * 255).to_i)
            s.opacity = ((1.0 - a) * 255).to_i
            s.zoom_x  = s.zoom_y = 1.0 + (a * 0.4)
          end
          @sprites["gcursor"].opacity = ((1.0 - a) * 255).to_i
          Graphics.update
          Input.update
          grelha_orig_update
        end

        @grelha_pag  = nova
        lin          = @grelha_slot / g::COLUNAS.length
        col          = (passo > 0) ? 0 : (g::COLUNAS.length - 1)
        @grelha_slot = (lin * g::COLUNAS.length) + col
        @grelha_slot = 0 if grelha_item.nil?
        grelha_encher!

        9.times do |f|
          a = (f + 1) / 9.0
          g::POR_PAGINA.times do |i|
            s = @sprites["gi#{i}"]
            next if !s || s.disposed? || !s.visible
            s.color   = Color.new(255, 255, 255, ((1.0 - a) * 255).to_i)
            s.opacity = (a * 255).to_i
            s.zoom_x  = s.zoom_y = 1.4 - (a * 0.4)
          end
          @sprites["gcursor"].opacity = (a * 255).to_i
          Graphics.update
          Input.update
          grelha_orig_update
        end
        g::POR_PAGINA.times do |i|
          s = @sprites["gi#{i}"]
          next if !s || s.disposed?
          s.zoom_x = s.zoom_y = 1.0
          s.opacity = 255
        end
        @grelha_anel_slot = -1
        @sprites["gcursor"].opacity = 255
        pbRefresh
        true
      end

      def pbChooseBuyItem
        return grelha_orig_escolher if !grelha_activa?
        g = AnilLojaGrelha
        @sprites["helpwindow"].visible = false
        pbRefresh
        loop do
          Graphics.update
          Input.update
          self.update

          if Input.trigger?(Input::BACK)
            pbPlayCloseMenuSE
            return nil
          elsif Input.trigger?(Input::USE)
            e = grelha_item
            next if e.nil?
            pbPlayDecisionSE
            pbRefresh
            return e
          end

          col   = @grelha_slot % g::COLUNAS.length
          lin   = @grelha_slot / g::COLUNAS.length
          mudou = false

          if Input.repeat?(Input::RIGHT)
            if col < g::COLUNAS.length - 1 && !grelha_item(@grelha_slot + 1).nil?
              @grelha_slot += 1
              mudou = true
            else
              mudou = grelha_virar_pagina!(1)
            end
          elsif Input.repeat?(Input::LEFT)
            if col > 0
              @grelha_slot -= 1
              mudou = true
            else
              mudou = grelha_virar_pagina!(-1)
            end
          elsif Input.repeat?(Input::DOWN)
            if lin < g::LINHAS.length - 1 && !grelha_item(@grelha_slot + g::COLUNAS.length).nil?
              @grelha_slot += g::COLUNAS.length
              mudou = true
            end
          elsif Input.repeat?(Input::UP)
            if lin > 0
              @grelha_slot -= g::COLUNAS.length
              mudou = true
            end
          end

          if mudou
            pbSEPlay("GUI sel cursor") rescue nil
            @grelha_t = 0
            pbRefresh
          end
        end
      end

      def pbEndBuyScene
        @grelha_on = false
        # O pbDisposeSpriteHash trata dos sprites; este bitmap e a parte que
        # nao esta no @sprites e ficaria pendurada.
        if @grelha_brilho
          @grelha_brilho.dispose rescue nil
          @grelha_brilho = nil
        end
        grelha_orig_fim
      end

      def grelha_encher!
        g = AnilLojaGrelha
        g::POR_PAGINA.times do |i|
          s = @sprites["gi#{i}"]
          next if !s || s.disposed?
          entrada = grelha_item(i)
          s.item    = grelha_icone_de(entrada)
          s.visible = !entrada.nil?
          s.opacity = 255
          s.zoom_x  = 1.0
          s.zoom_y  = 1.0
          s.angle   = 0
          s.color   = Color.new(0, 0, 0, 0)
          s.x = g.tab_x + g::COLUNAS[i % g::COLUNAS.length]
          s.y = g.tab_y + g::LINHAS[i / g::COLUNAS.length]
        end
      end
    end

    # ⚠️ O MERCADO DE ITENS TEM pbRefresh PROPRIO.
    #
    # OnlineItemMarketScene redefine o pbRefresh de raiz (nao chama super), por
    # isso o alias feito em PokemonMart_Scene nunca correria la. Fica com um
    # alias so dele. O resto — arranque, escolha, animacao — e herdado e ja
    # esta tratado.
    mercado = cena_mercado_itens
    if mercado && !mercado.method_defined?(:grelha_mercado_orig_pbRefresh)
      registar("INSTALAR: alias em #{mercado}")
      mercado.class_eval do
        # ⚠️ ESTA CENA NAO PASSA PELO pbStartBuyOrSellScene.
        #
        # O OnlineItemMarketScene tem um pbStartBuyScene proprio que monta os
        # sprites todos de raiz — e uma copia do metodo base, nao uma chamada a
        # ele. Por isso o hook posto no pai nunca chegava aqui e o mercado
        # continuava com a lista, mesmo com o alias instalado (o log mostrava a
        # instalacao e nunca uma linha "LOJA:" desta classe).
        alias_method :grelha_mercado_orig_start, :pbStartBuyScene
        def pbStartBuyScene(stock, adapter)
          grelha_mercado_orig_start(stock, adapter)
          @grelha_on = false
          g = AnilLojaGrelha
          if !g.ligada?
            g.registar("MERCADO: desligado nas Opcoes — fica com a lista")
            return
          end
          if !pbResolveBitmap(g::IMAGEM)
            g.registar("MERCADO: FALTA #{g::IMAGEM}.png — fica com a lista")
            return
          end
          g.registar("MERCADO: grelha LIGADA, #{stock.length} anuncio(s)")
          grelha_montar!
        end

        alias_method :grelha_mercado_orig_pbRefresh, :pbRefresh
        def pbRefresh
          if grelha_activa?
            iw = @sprites["itemwindow"]
            iw.index = [grelha_indice, @stock.length].min if iw
          end
          grelha_mercado_orig_pbRefresh
          grelha_nome! if grelha_activa?
        end
      end
    end
  end
end
