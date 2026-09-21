# encoding: UTF-8
#===============================================================================
# MOD: 154_Pokedex_Cores_Shiny
#-------------------------------------------------------------------------------
# Na pagina FORMAS da Pokedex, deixa ver o Pokemon em todas as coloracoes que
# ele pode ter: Normal, Shiny e as 7 variacoes de Super Shiny — as mesmas 7 que
# os Orbes do MOD 109 aplicam. Vira um mostruario de cores dentro da Pokedex.
#
# ⚠️ AS 7 VARIACOES E AS 7 ORBES SAO A MESMA COISA.
#
# O hue natural de um Super Shiny e derivado da especie, no plugin DBK:
#
#   @cached_super_shiny_hue = ((species_hash % 7) + 1) * 45
#
# Ou seja 45, 90, 135, 180, 225, 270 e 315 — exactamente os hues das 7 Orbes do
# SUPER_SHINY_ORBS_CONFIG. Por isso o mostruario le a configuracao das Orbes em
# vez de repetir a lista: os nomes que aparecem aqui sao os nomes dos itens que
# o jogador tem de arranjar, e nunca podem divergir deles.
#
# A coloracao que a especie da NATURALMENTE fica marcada com uma placa cinzenta
# por tras do icone. Muda de orbe conforme a especie, porque e derivada do nome
# dela — nao e aleatorio, e a cor que aquele Pokemon da sem orbe nenhuma.
#
# ⚠️ A marca da cor natural e a marca da ESCOLHA tem de ser coisas diferentes.
# A escolha e a moldura verde mais o tamanho; a natural e a placa por tras.
# Chegou a ser um ponto no canto do icone e nao servia: as gemas sao estreitas,
# o canto e transparente, e o ponto ficava a flutuar ao lado.
#
# ⚠️ O SUPER SHINY PARTE DO SPRITE SHINY, NAO DO NORMAL.
#
# A regra do plugin VOE (`... && !pokemon.super_shiny?`, que escolhe o sprite
# NORMAL) vale so para o boneco do OVERWORLD. Nas telas — batalha, sumario,
# Pokedex — e ao contrario, e a prova esta no proprio setter:
#
#   def super_shiny=(value)
#     @super_shiny = value
#     @shiny = true if @super_shiny      # super shiny IMPLICA shiny
#   end
#
# Logo `shiny?` da true, o ficheiro carregado e o de "Front shiny", e o
# hue_change do DBK roda POR CIMA dele (setPokemon, [008] Deluxe Bitmap:181).
#
# A diferenca nao e subtil. Medida no Graveler: o sprite normal tem saturacao
# media de 0,17 e o shiny 0,83. Rodar 270 graus a partir do normal da um malva
# pálido — foi o que apareceu na Pokedex e nao batia certo com a party; a partir
# do shiny da o magenta vivo que o jogo mostra em todo o lado.
#
# ⚠️ PORQUE O drawPageForms E SUBSTITUIDO EM VEZ DE ENCADEADO.
#
# O painel branco tem 75 px de altura (y 290..365) e o original ja la escreve
# duas linhas de texto, em 302 e 334. Nao sobra um unico pixel para a fila de
# cores. Entao o painel e desenhado de raiz: nome (com a forma entre parenteses)
# a esquerda, nome da coloracao a direita, e a fila por baixo. Nada se perde —
# a forma passa a viajar ao lado do nome em vez de ocupar uma linha inteira.
#
# ⚠️ TUDO NO apply_post_plugin_patches.
#
# Quem manda nesta pagina e o plugin "Modular UI Scenes", que reescreve o
# drawPage e encadeia o drawPageForms no fim do Main. Remendar no arranque
# apanhava a versao do Essentials, que o plugin substitui a seguir.
#===============================================================================

module AnilDexCores
  # Geometria do painel branco do bg_forms, medida na propria imagem:
  # zona clara de y=290 a y=365, de x=46 a x=465. O icone da especie fica
  # centrado em (82, 328), portanto a fila tem de comecar depois de x=110.
  # Os icones dos itens sao 48x48; encolhem-se para 32 para caberem nove numa
  # fila, com folga para o icone da especie que vive em (82, 328).
  LADO      = 32
  # O escolhido cresce 4 px e ganha moldura. A moldura desenha-se DENTRO destes
  # 36, e nao por fora, senao passava do branco do painel, que acaba em y=365.
  LADO_SEL  = 36
  ESPACO    = 6
  CENTRO_X  = 287    # meio do espaco a direita do icone da especie
  CENTRO_Y  = 347
  # 302, e nao 292. Com 292 o texto encostava a moldura do painel: o branco
  # comeca exactamente em y=290 e a celula de texto tem 32 px de altura. O 302
  # e a altura que o desenho original ja usava para a primeira linha, portanto
  # e a que se sabe que assenta bem.
  TEXTO_Y   = 302
  TEXTO_ESQ = 112
  TEXTO_DIR = 458

  COR_BASE   = Color.new(88, 88, 80)
  COR_SOMBRA = Color.new(168, 184, 184)
  COR_NORMAL = Color.new(176, 176, 168)
  COR_SHINY  = Color.new(248, 208, 80)
  # Verde-agua tirado da propria moldura das caixas de sprite do bg_forms, para
  # o destaque pertencer ao ecra em vez de ser um verde qualquer.
  COR_MARCA  = Color.new(74, 198, 189)
  COR_MARCA2 = Color.new(41, 123, 115)

  module_function

  # [rotulo, item do icone, hue a aplicar (0 = nenhum), usar sprite shiny?,
  #  cor de recurso se o icone faltar]
  #
  # O Normal e o Shiny nao tem Orbe, e por isso pedem emprestado o icone do item
  # que os representa: a Poke Ball para "como ele vem" e o Amuleto Shiny para o
  # shiny. Sao os dois objectos que qualquer jogador ja associa a essas duas
  # coisas — inventar um simbolo novo seria pior.
  def variantes(species = nil, form = 0)
    # ⚠️ Sem _INTL. Estes dois rotulos NAO se traduzem.
    #
    # O catalogo tem "Shiny" a dar "Brilhante", e antes disso o PTBR_TEXT do
    # pbDrawTextPositions dava "normal" em minuscula. Sao nomes proprios de uma
    # lista nossa, a par de "Orbe de Ametista" — e "Shiny" e a palavra que o
    # jogo usa em todo o lado, do amuleto ao anuncio de captura.
    lista = [
      ["Normal", :POKEBALL,   0, false, COR_NORMAL],
      ["Shiny",  :SHINYCHARM, 0, true,  COR_SHINY]
    ]
    orbes.each { |nome, hue, id| lista.push([nome, id, hue, true, cor_do_hue(hue)]) }
    lista
  end

  # Le a configuracao das Orbes, por ordem de hue. Se o MOD 109 nao estiver
  # carregado por alguma razao, cai nos 7 hues do proprio plugin DBK.
  def orbes
    cfg = (defined?(SUPER_SHINY_ORBS_CONFIG) ? SUPER_SHINY_ORBS_CONFIG : nil)
    if cfg.is_a?(Hash) && !cfg.empty?
      return cfg.map { |id, c| [c[:name].to_s, c[:hue].to_i, id] }.sort_by { |v| v[1] }
    end
    (1..7).map { |i| [_INTL("Cor {1}", i), i * 45, nil] }
  end

  # O hue que ESTA especie da naturalmente, para marcar na fila.
  def hue_natural(species, form = 0)
    m = GameData::SpeciesMetrics.get_species_form(species, form)
    h = (m.instance_variable_get(:@super_shiny_hue).to_i rescue 0)
    return h if h && h != 0
    id = GameData::Species.get_species_form(species, form).id
    ((id.to_s.sum % 7) + 1) * 45
  rescue
    0
  end

  # HSV -> RGB, para o circulo mostrar a cor do proprio hue.
  def cor_do_hue(h, s = 0.85, v = 1.0)
    h = h.to_f % 360.0
    c = v * s
    x = c * (1 - ((h / 60.0) % 2 - 1).abs)
    m = v - c
    r, g, b = case (h / 60.0).to_i
              when 0 then [c, x, 0]
              when 1 then [x, c, 0]
              when 2 then [0, c, x]
              when 3 then [0, x, c]
              when 4 then [x, 0, c]
              else        [c, 0, x]
              end
    Color.new(((r + m) * 255).round, ((g + m) * 255).round, ((b + m) * 255).round)
  end

  # Centro do circulo n (0..8).
  #
  # ⚠️ Ha um vao maior entre o 2o e o 3o circulo. Normal e Shiny sao o que o
  # Pokemon e; os 7 seguintes sao Super Shiny, e distinguem-se entre si pela
  # Orbe. Coladas todas com o mesmo espaco, a fila lia-se como nove coisas do
  # mesmo tipo — o vao diz que sao dois grupos sem gastar um pixel de texto.
  SEPARADOR = 12

  def centro(n)
    passo = LADO + ESPACO
    total = (9 * LADO) + (8 * ESPACO) + SEPARADOR
    x0 = CENTRO_X - (total / 2)
    x = x0 + (LADO / 2) + (n * passo)
    x += SEPARADOR if n >= 2
    [x, CENTRO_Y]
  end

  # Escreve com sombra sem passar pela traducao automatica.
  def escrever!(bmp, texto, x, y, alinhamento = :left)
    t = texto.to_s
    tam = bmp.text_size(t)
    x -= tam.width if alinhamento == :right
    x -= tam.width / 2 if alinhamento == :center
    pbDrawShadowText(bmp, x, y, tam.width, tam.height, t, COR_BASE, COR_SOMBRA)
  rescue
    nil
  end

  def circulo!(bmp, cx, cy, r, cor)
    (-r..r).each do |dy|
      dx = Math.sqrt([(r * r) - (dy * dy), 0].max).floor
      bmp.fill_rect(cx - dx, cy + dy, (dx * 2) + 1, 1, cor)
    end
  end

  # Os bitmaps dos icones ficam em cache e NUNCA se libertam.
  #
  # Sao nove ficheiros de 48x48 — uns kilobytes. Liberta-los ao sair da cena
  # obrigava a recarrega-los a cada redesenho da pagina, e a pagina redesenha-se
  # a cada toque num icone. Guardar tambem o nil evita insistir num ficheiro que
  # nao existe.
  def icone(item)
    return nil unless item
    @icones ||= {}
    chave = item.to_s
    return @icones[chave] if @icones.key?(chave)
    nome = (GameData::Item.icon_filename(item) rescue nil)
    bmp = nil
    begin
      bmp = AnimatedBitmap.new(nome) if nome && pbResolveBitmap(nome)
    rescue
      bmp = nil
    end
    @icones[chave] = bmp
  end

  # ⚠️ O ICONE E PRE-ENCOLHIDO PARA UM BITMAP PROPRIO.
  #
  # A primeira versao fazia `stretch_blt(destino, fonte, origem, opacidade)`
  # directamente no overlay, e no jogo sairam os nove circulos de recurso — ou
  # seja falhou nas nove. O stretch_blt com quatro argumentos e o suspeito: e
  # RGSS valido no papel, mas nao o usamos em mais lado nenhum deste projecto e
  # nao ha como o confirmar sem correr o jogo.
  #
  # Aqui usa-se so o que este projecto ja usa noutros sitios: stretch_blt de
  # TRES argumentos para encolher uma vez para um bitmap de 32x32 guardado em
  # cache, e depois blt, que aceita opacidade em qualquer versao. De caminho
  # deixa de encolher a cada redesenho.
  #
  # E regista-se a falha, para nao ficarmos outra vez a adivinhar.
  def icone_escalado(item, lado = LADO)
    return nil unless item
    @escalados ||= {}
    chave = "#{item}:#{lado}"
    return @escalados[chave] if @escalados.key?(chave)
    destino = nil
    begin
      ab = icone(item)
      if ab && ab.bitmap && !ab.bitmap.disposed?
        fonte = ab.bitmap
        n = [fonte.width, fonte.height].min
        destino = Bitmap.new(lado, lado)
        destino.stretch_blt(Rect.new(0, 0, lado, lado), fonte, Rect.new(0, 0, n, n))
      else
        registar_falha(chave, "sem bitmap (ficheiro nao resolvido?)")
      end
    rescue => e
      destino = nil
      registar_falha(chave, "#{e.class}: #{e.message}")
    end
    @escalados[chave] = destino
  end

  def registar_falha(chave, motivo)
    @falhas ||= {}
    return if @falhas[chave]
    @falhas[chave] = true
    AnilLanRework.log("[DEXCORES] icone #{chave} falhou: #{motivo}") rescue nil
  end

  # Devolve false se nao houve icone, para quem chama poder desenhar o circulo
  # de recurso em vez de deixar um buraco.
  def desenhar_icone!(destino, item, cx, cy, opacidade = 255, lado = LADO)
    bmp = icone_escalado(item, lado)
    return false unless bmp && !bmp.disposed?
    destino.blt(cx - (lado / 2), cy - (lado / 2), bmp,
                Rect.new(0, 0, lado, lado), opacidade)
    true
  rescue => e
    registar_falha(item.to_s + ":blt", "#{e.class}: #{e.message}")
    false
  end

  # Moldura de 2 px desenhada nos limites do quadrado, nao por fora.
  def moldura!(bmp, cx, cy, lado)
    x = cx - (lado / 2)
    y = cy - (lado / 2)
    [[COR_MARCA2, 0], [COR_MARCA, 1]].each do |cor, d|
      bmp.fill_rect(x + d, y + d, lado - (d * 2), 1, cor)
      bmp.fill_rect(x + d, y + lado - 1 - d, lado - (d * 2), 1, cor)
      bmp.fill_rect(x + d, y + d, 1, lado - (d * 2), cor)
      bmp.fill_rect(x + lado - 1 - d, y + d, 1, lado - (d * 2), cor)
    end
  end
end

module AnilLanRework
  class << self
    unless method_defined?(:anil_dexcores_orig_apply_post_plugin_patches)
      alias_method :anil_dexcores_orig_apply_post_plugin_patches, :apply_post_plugin_patches rescue nil
    end

    def apply_post_plugin_patches
      anil_dexcores_orig_apply_post_plugin_patches rescue nil
      begin
        return unless defined?(PokemonPokedexInfo_Scene)
        return if PokemonPokedexInfo_Scene.method_defined?(:anil_dexcores_orig_drawPageForms)

        PokemonPokedexInfo_Scene.class_eval do
          alias_method :anil_dexcores_orig_drawPageForms, :drawPageForms
          # ⚠️ Condicional. O pbPageCustomUse vem do "Modular UI Scenes"; se um dia
          # nao estiver la, um alias_method a seco rebentava a meio deste
          # class_eval e deixava o drawPageForms por redefinir — com o alias do
          # drawPageForms JA criado, ou seja com o guarda de reentrada activo a
          # impedir nova tentativa. Fica meia instalacao, que e pior que nenhuma.
          if method_defined?(:pbPageCustomUse) || private_method_defined?(:pbPageCustomUse)
            alias_method :anil_dexcores_orig_pbPageCustomUse, :pbPageCustomUse
          else
            define_method(:anil_dexcores_orig_pbPageCustomUse) { |_id| nil }
          end
          alias_method :anil_dexcores_orig_pbUpdateDummyPokemon, :pbUpdateDummyPokemon
          alias_method :anil_dexcores_orig_pbUpdate, :pbUpdate

          # ⚠️ A COLORACAO VOLTA AO NORMAL QUANDO SE TROCA DE POKEMON.
          #
          # Ao principio deixei a escolha fixa entre especies, a pensar nela como
          # ferramenta de comparacao. Na pratica e o contrario: escolhe-se uma
          # Orbe num Pokemon, rola-se a lista, e TODOS os seguintes aparecem
          # tingidos — quem chega ao Graveler ve-o com uma cor que nao e a dele e
          # conclui, com razao, que alguma coisa se estragou.
          #
          # A Pokedex e primeiro um catalogo. A cor verdadeira e o estado normal;
          # as outras sao uma consulta que se pede a cada Pokemon.
          def anil_dexcores_variante
            @anil_dexcores_variante = 0 if @anil_dexcores_variante.nil?
            if @anil_dexcores_especie != @species
              @anil_dexcores_especie = @species
              @anil_dexcores_variante = 0
            end
            lista = AnilDexCores.variantes(@species, @form)
            @anil_dexcores_variante = 0 if @anil_dexcores_variante >= lista.length
            @anil_dexcores_variante
          end

          # Repinta os tres sprites da pagina com a coloracao escolhida.
          #
          # ⚠️ NAO SE POSICIONA NADA. O SITIO E DO PLUGIN, E ELE JA O TRATA.
          #
          # Duas tentativas erradas antes desta, ambas por assumir em vez de ler:
          #
          #   1. Copiar a formula do Essentials, `y = 256 + back_sprite[1] * 2`.
          #      Punha o sprite de costas por baixo da caixa — o Charizard entrava
          #      pelo painel branco. Quem manda e o [DBK] Animated Pokemon System.
          #
          #   2. Chamar o pbSetDisplay do plugin a seguir ao setSpeciesBitmap.
          #      Mas o setSpeciesBitmap do DBK JA o chama por dentro, e o
          #      pbSetDisplay nao e idempotente: com CONSTRICT_POKEMON_SPRITES faz
          #      `@_iconbitmap.constrict_x += offset[0]`, que ACUMULA. Ficava o
          #      deslocamento a dobrar, visivel so nas especies cujo offset nao e
          #      zero — os "alguns pokemon descentralizados".
          #
          # Portanto: pede-se o bitmap novo, roda-se o hue no proprio sitio, e
          # nao se toca em coordenada nenhuma.
          def anil_dexcores_aplicar!
            lista = AnilDexCores.variantes(@species, @form)
            hue        = lista[anil_dexcores_variante][2]
            usar_shiny = lista[anil_dexcores_variante][3]

            if (s = @sprites["formfront"])
              s.setSpeciesBitmap(@species, @gender, @form, usar_shiny)
              anil_dexcores_rodar_hue(s, hue)
              anil_dexcores_recurso_de_posicao(s, false)
            end

            if (s = @sprites["formback"])
              s.setSpeciesBitmap(@species, @gender, @form, usar_shiny, false, true)
              anil_dexcores_rodar_hue(s, hue)
              anil_dexcores_recurso_de_posicao(s, true)
            end

            anil_dexcores_icone_simples(@sprites["formicon"], usar_shiny)
          rescue => e
            AnilLanRework.log("[DEXCORES] falha ao aplicar: #{e.class}: #{e.message}") rescue nil
          end

          # ⚠️ NAO CHAMAR O pbSetDisplay. O setSpeciesBitmap JA O CHAMA.
          #
          # O DBK encadeia-o por dentro:
          #
          #   def setSpeciesBitmap(...)
          #     animated_setSpeciesBitmap(...)
          #     pbSetDisplay([], species_id, back)
          #   end
          #
          # E o pbSetDisplay NAO e idempotente: com CONSTRICT_POKEMON_SPRITES
          # ligado faz `@_iconbitmap.constrict_x += offset[0]`, que ACUMULA.
          # Chama-lo outra vez a seguir aplicava o deslocamento a dobrar — e por
          # isso so se via nas especies cujo offset nao e zero, que foi o
          # "alguns pokemon ficaram descentralizados".
          #
          # Aqui so se trata do caso em que o plugin NAO esta presente: ai o
          # setSpeciesBitmap e o do Essentials, que nao posiciona nada, e as
          # costas precisam da regra dos metrics.
          def anil_dexcores_recurso_de_posicao(sprite, back)
            return if sprite.respond_to?(:pbSetDisplay)
            return unless back
            m = GameData::SpeciesMetrics.get_species_form(@species, @form)
            sprite.y = 256 + (m.back_sprite[1] * 2)
          rescue
            nil
          end

          # ⚠️ O ICONE DA ESPECIE NAO LEVA COR. E DE PROPOSITO.
          #
          # Duas tentativas, as duas com o mesmo defeito de fundo: o
          # PokemonSpeciesIconSprite usa um AnimatedBitmap normal, e esse pega os
          # quadros da RPG::Cache, que sao PARTILHADOS e contados por referencia.
          #
          #   1. `hue_change` no sitio rodava a propria entrada da cache: a
          #      rotacao somava-se a cada toque num orbe e a cor errada escapava
          #      para todo o lado que mostrasse aquele icone.
          #
          #   2. `AnimatedBitmap.new(nome, hue)` mais dispose do anterior parecia
          #      a saida limpa — e o que o DBK faz — mas o `refresh` do proprio
          #      icone JA faz `@animBitmap&.dispose`. Com o nosso dispose por
          #      cima a contagem de referencias desequilibra, e o bitmap base
          #      pode ser libertado enquanto outros sprites ainda o usam. Foi o
          #      que estragou as cores fora da Pokedex.
          #
          # Nao ha aqui forma de tingir sem mexer em memoria partilhada com o
          # resto do jogo. Um icone de 40 px sem tom e um defeito pequeno; a
          # cache corrompida nao e. Fica sem cor — os dois sprites grandes, que
          # sao o que interessa ver, mostram a coloracao na mesma.
          def anil_dexcores_icone_simples(s, usar_shiny)
            return unless s
            s.pbSetParams(@species, @gender, @form, usar_shiny)
          rescue => e
            AnilLanRework.log("[DEXCORES] icone da especie: #{e.class}: #{e.message}") rescue nil
          end

          # ⚠️ NUNCA REATRIBUIR O sprite.bitmap.
          #
          # O hue_change altera os bitmaps NO PROPRIO SITIO, e o sprite ja aponta
          # para eles — nao ha nada a religar. Fazer `sprite.bitmap = ...` reinicia
          # o src_rect, que e justamente o que o recorte (constrict) do DBK usa
          # para mostrar um quadro da animacao.
          #
          # Com hue 0 nao se toca em nada: alem de ser trabalho a troco de nada,
          # o hue_change marca o bitmap com changedHue? e recusa rodar segunda vez.
          def anil_dexcores_rodar_hue(sprite, hue)
            return unless sprite && hue && hue != 0
            alvo = nil
            alvo = sprite.iconBitmap if sprite.respond_to?(:iconBitmap)
            alvo ||= sprite.instance_variable_get(:@_iconbitmap)
            alvo ||= sprite.instance_variable_get(:@animBitmap)
            # ⚠️ DESFEITO: A GUARDA POR changedHue? TIRAVA A COR.
            #
            # Acrescentei-a a pensar que o bitmap podia vir partilhado da
            # RPG::Cache, como acontece no icone pequeno. Nao acontece: o
            # GameData::Species.sprite_bitmap e substituido pelo DBK e devolve
            # sempre um DeluxeBitmapWrapper, que monta os quadros com
            # `Bitmap.new(ficheiro)` — copias proprias, nada de cache. A guarda
            # so podia tirar cor, nunca proteger nada aqui.
            if alvo && alvo.respond_to?(:hue_change)
              alvo.hue_change(hue)
            end
          rescue
            nil
          end

          def pbUpdateDummyPokemon
            anil_dexcores_orig_pbUpdateDummyPokemon
            anil_dexcores_aplicar! if @sprites && @sprites["formfront"]
          end

          def drawPageForms
            @sprites["formfront"].visible = true if @sprites["formfront"]
            @sprites["formback"].visible  = true if @sprites["formback"]
            @sprites["formicon"].visible  = true if @sprites["formicon"]
            anil_dexcores_aplicar!

            overlay = @sprites["overlay"].bitmap
            lista   = AnilDexCores.variantes(@species, @form)
            sel     = anil_dexcores_variante
            natural = AnilDexCores.hue_natural(@species, @form)

            # Nome da especie, com a forma ao lado quando existe.
            formname = ""
            @available.each do |i|
              next unless i[1] == @gender && i[2] == @form
              formname = i[0].to_s
              break
            end
            nome_sp = GameData::Species.get(@species).name.to_s
            titulo  = nome_sp
            titulo += " (#{formname})" if formname && !formname.empty?

            # ⚠️ O nome e o rotulo partilham a mesma linha e podem chocar.
            #
            # Os nomes sozinhos cabem sempre — o pior caso medido, "Crabominable"
            # com "Orbe de Esmeralda", da 328 px dos 346 disponiveis. Mas com a
            # forma ao lado deixam de caber: "Deoxys (Defesa)" com o mesmo rotulo
            # pede 362 px. Nesse caso larga-se a forma, que fica na mesma visivel
            # no seletor de formas, e nunca o rotulo da cor, que e o unico sitio
            # onde se le que Orbe corresponde ao circulo escolhido.
            # As setas so aparecem com o modo de escolha ligado: sao a unica
            # pista de que ESQUERDA e DIREITA agora mudam a cor em vez da pagina.
            rotulo = lista[sel][0].to_s
            rotulo = "< #{rotulo} >" if @anil_dexcores_modo

            begin
              disponivel = AnilDexCores::TEXTO_DIR - AnilDexCores::TEXTO_ESQ
              largura = overlay.text_size(titulo).width +
                        overlay.text_size(rotulo).width + 12
              titulo = nome_sp if largura > disponivel
            rescue
              nil
            end

            # ⚠️ Nao se passa pelo pbDrawTextPositions.
            #
            # Ele comeca por correr todo o texto pelo PTBR_TEXT.t, e a tabela
            # tem "Normal" (o tipo Normal) a dar "normal" em minuscula — era o
            # que se via no ecra. Estes dois rotulos sao nomes proprios de uma
            # lista nossa e nao devem ser traduzidos por ninguem.
            AnilDexCores.escrever!(overlay, titulo,
                                   AnilDexCores::TEXTO_ESQ, AnilDexCores::TEXTO_Y, :left)
            AnilDexCores.escrever!(overlay, rotulo,
                                   AnilDexCores::TEXTO_DIR, AnilDexCores::TEXTO_Y, :right)

            # A escolha marca-se pela OPACIDADE, nao por uma moldura grossa.
            #
            # O painel tem 76 px de altura e a linha de texto ja come 32. Uma
            # moldura a toda a volta de cada icone nao cabia sem encostar ao
            # texto em cima e a borda em baixo. Apagar os nao escolhidos diz o
            # mesmo, nao gasta um unico pixel, e faz o escolhido saltar a vista.
            # O escolhido cresce e ganha moldura verde; os outros ficam
            # apagados. A moldura sozinha nao chegava num icone de 32 px, e o
            # tamanho sozinho lia-se mal entre gemas parecidas.
            @anil_dexcores_alvos = []
            lista.each_with_index do |dados, n|
              item = dados[1]
              hue  = dados[2]
              cor  = dados[4]
              cx, cy = AnilDexCores.centro(n)
              escolhido = (n == sel)
              lado = escolhido ? AnilDexCores::LADO_SEL : AnilDexCores::LADO
              meio = lado / 2
              opac = escolhido ? 255 : 150

              # Placa por tras = a cor que esta especie da naturalmente, sem
              # orbe nenhuma. Fica sempre do tamanho normal, mesmo debaixo do
              # escolhido, para nao competir com a moldura verde.
              if hue != 0 && hue == natural
                m = AnilDexCores::LADO / 2
                overlay.fill_rect(cx - m + 1, cy - m + 1,
                                  AnilDexCores::LADO - 2, AnilDexCores::LADO - 2,
                                  AnilDexCores::COR_SOMBRA)
              end

              unless AnilDexCores.desenhar_icone!(overlay, item, cx, cy, opac, lado)
                # Sem icone no disco, volta-se ao circulo da cor.
                AnilDexCores.circulo!(overlay, cx, cy, meio - 3, cor)
              end

              AnilDexCores.moldura!(overlay, cx, cy, lado) if escolhido

              @anil_dexcores_alvos.push([cx - meio, cy - meio, cx + meio, cy + meio, n])
            end
          rescue => e
            AnilLanRework.log("[DEXCORES] falha ao desenhar: #{e.class}: #{e.message}") rescue nil
            anil_dexcores_orig_drawPageForms rescue nil
          end

          # ⚠️ O MODO DE ESCOLHA E UM CICLO PROPRIO, COMO O pbChooseForm.
          #
          # Nao da para tratar ESQUERDA/DIREITA no pbUpdate: ele corre ANTES das
          # verificacoes do pbScene, e o Input.trigger? nao se consome — o
          # pbScene veria a mesma tecla e mudava de pagina a seguir. Um ciclo
          # proprio, entrado a partir do ramo da tecla C, e o padrao que a
          # propria cena ja usa para escolher a forma, e nao luta com nada.
          #
          # A entrada e pelo pbPageCustomUse, que e o gancho que o plugin
          # "Modular UI Scenes" chama nesse ramo; devolver verdadeiro faz o
          # pbScene saltar o comportamento padrao (que era abrir o seletor de
          # formas) e apenas redesenhar.
          #
          # ⚠️ O seletor de FORMAS nao se perde: passa para dentro do modo, na
          # mesma tecla C, e so para as especies que tem mais do que uma forma.
          # Quem so tem uma sai do modo com C, como se fosse um "pronto".
          def pbPageCustomUse(page_id)
            if page_id == :page_forms
              anil_dexcores_escolher_cor
              return true
            end
            anil_dexcores_orig_pbPageCustomUse(page_id)
          rescue
            anil_dexcores_orig_pbPageCustomUse(page_id) rescue nil
          end

          def anil_dexcores_escolher_cor
            @anil_dexcores_modo = true
            pbPlayDecisionSE rescue nil
            drawPage(@page)
            loop do
              Graphics.update
              Input.update
              pbUpdate
              if Input.trigger?(Input::LEFT)
                anil_dexcores_ir_para(anil_dexcores_variante - 1)
              elsif Input.trigger?(Input::RIGHT)
                anil_dexcores_ir_para(anil_dexcores_variante + 1)
              elsif Input.repeat?(Input::UP) || Input.repeat?(Input::DOWN)
                antigo = @index
                Input.repeat?(Input::UP) ? pbGoToPrevious : pbGoToNext
                if @index != antigo
                  pbUpdateDummyPokemon
                  @available = pbGetAvailableForms
                  pbSEStop rescue nil
                  pbPlayCursorSE rescue nil
                  drawPage(@page)
                end
              elsif Input.trigger?(Input::USE)
                if @available && @available.length > 1
                  pbPlayDecisionSE rescue nil
                  pbChooseForm
                  drawPage(@page)
                else
                  break
                end
              elsif Input.trigger?(Input::BACK)
                break
              end
            end
            @anil_dexcores_modo = false
            pbPlayCloseMenuSE rescue nil
            drawPage(@page)
          rescue => e
            @anil_dexcores_modo = false
            AnilLanRework.log("[DEXCORES] falha no modo de escolha: #{e.class}: #{e.message}") rescue nil
          end

          def anil_dexcores_ir_para(n)
            lista = AnilDexCores.variantes(@species, @form)
            n = n % lista.length
            return if n == anil_dexcores_variante
            @anil_dexcores_variante = n
            pbPlayCursorSE rescue nil
            drawPage(@page)
          end

          # ⚠️ O input vive no pbUpdate, nao no pbScene.
          #
          # O plugin reescreve o pbScene inteiro; copia-lo para lhe acrescentar
          # uma tecla seria herdar a manutencao dele. O pbUpdate e chamado por
          # todos os ciclos da cena — incluindo o do pbChooseForm — e por isso a
          # fila responde tambem enquanto se escolhe a forma.
          #
          # A tecla e a ACTION porque nesta pagina ela nao faz nada: o pbScene so
          # toca o grito quando @page == 1. No telemovel o caminho principal e o
          # toque, e ai carrega-se directamente no circulo que se quer.
          def pbUpdate
            anil_dexcores_orig_pbUpdate
            return unless @page_id == :page_forms

            if Input.trigger?(Input::ACTION)
              anil_dexcores_ir_para(anil_dexcores_variante + 1)
              return
            end

            return unless @anil_dexcores_alvos && Input.trigger?(Input::MOUSELEFT)
            pos = (Mouse.getMousePos rescue nil)
            return unless pos
            mx = pos[0]
            my = pos[1]
            @anil_dexcores_alvos.each do |alvo|
              next unless mx >= alvo[0] && mx <= alvo[2] && my >= alvo[1] && my <= alvo[3]
              $mouse_click_handled = true
              anil_dexcores_ir_para(alvo[4])
              break
            end
          rescue
            nil
          end
        end

        AnilLanRework.log("[DEXCORES] mostruario de cores instalado na pagina FORMAS") rescue nil
      rescue => e
        AnilLanRework.log("[DEXCORES] falha ao instalar: #{e.class}: #{e.message}") rescue nil
      end
    end
  end
end

AnilLanRework.log("154_Pokedex_Cores_Shiny carregado") rescue nil
