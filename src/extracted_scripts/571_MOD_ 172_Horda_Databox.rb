# encoding: UTF-8
#===============================================================================
# MOD: 172_Horda_Databox
#-------------------------------------------------------------------------------
# A caixa de dados fica apertada quando ha tres de um lado. Este MOD limpa-a,
# e SO nesse caso.
#
# ⚠️ FICA A PARTE DE PROPOSITO.
#
# O que aqui se mexe pertence a tres donos diferentes: as estrelas de IV sao
# nossas (MOD 098), os icones de tipo vem do plugin "Type Icons in Battle", e o
# nivel e desenhado pelo Deluxe Battle Kit. Enfiar isto no MOD da horda
# misturava mecanica com apresentacao e obrigava a mexer em tres sitios de cada
# vez que a horda mudasse.
#
# Assim ha um sitio so para o aspecto das batalhas de tres, e a horda nao sabe
# que ele existe.
#
# ⚠️ E POR TAMANHO DE LADO, E NAO POR "SER HORDA".
#
# Uma batalha 3v3 normal tem exactamente o mesmo aperto. Olhar para o
# `pbSideSize` cobre os dois casos com uma regra, e nao deixa a caixa arrumada
# numa horda e amontoada num combate triplo.
#===============================================================================

module AnilHordaDatabox
  ACTIVO = true

  # A partir de quantos por lado e que a caixa fica apertada.
  APERTO = 3

  # Quanto encolhem os icones de tipo. 0.6 poe dois icones no espaco de pouco
  # mais de um.
  ESCALA_TIPOS = 0.6

  module_function

  def apertado?(battler)
    return false unless ACTIVO
    return false unless battler && battler.battle
    n = (battler.battle.pbSideSize(battler.index) rescue 1)
    r = (n >= APERTO)
    # Uma linha por batalha, e nao por frame: so quando o valor muda.
    if @ultimo_visto != [n, r]
      @ultimo_visto = [n, r]
      log("apertado? indice=#{battler.index} sideSize=#{n} -> #{r}")
    end
    r
  rescue
    false
  end
end

#-------------------------------------------------------------------------------
# ⚠️ TUDO ISTO ENTRA NO apply_post_plugin_patches. NAO AQUI EM CIMA.
#
# Os MODs sao inseridos ANTES do Main; os plugins carregam DENTRO dele, mais
# tarde. Um alias feito no corpo deste ficheiro e apanhado e depois deitado fora
# quando o Deluxe Battle Kit redefine a mesma classe — sem erro nenhum, sem
# aviso, e com o codigo a parecer certo.
#
# A primeira versao deste MOD foi assim, e o resultado foi exactamente isso: as
# estrelas de IV desapareceram (esse enxerto sobreviveu por acaso) e os outros
# dois — os icones de tipo e as posicoes — nao fizeram absolutamente nada.
#
# E a terceira vez que este projecto tropeca nisto. Se um enxerto numa classe do
# COMBATE parecer nao ter efeito, e quase sempre esta a razao.
#-------------------------------------------------------------------------------

module AnilHordaDatabox
  # Espaco a seguir a barra, para a estrela de shiny/super shiny caber.
  MARGEM_TIPOS = 22
  # Quanto o nome desce, para ficar encostado a barra de vida.
  NOME_DESCE = 14

  # ⚠️ O NIVEL VAI PARA BAIXO DA BARRA, A ESQUERDA.
  #
  # Ele NAO e desenhado pelo Deluxe: vem do `draw_level` do proprio jogo
  # (0196_Battle_Scene_Objects), com a posicao escrita a mao:
  #
  #     offset = nameWidth > 116 ? 155 : 142
  #     pbDrawTextPositions(..., @spriteBaseX + offset, 12, ...)
  #
  # Por isso e que ele nao acompanhou o nome quando se mexeu no @displayPos —
  # nao le posicao nenhuma, tem a dele cravada. Foi preciso procura-lo em tres
  # plugins antes de perceber que estava nos scripts do jogo.
  #
  # Aqui redefine-se so o `draw_level`, e so no caso apertado. Fora dele chama-se
  # o original sem tocar em nada.
  # ⚠️ O Y VEM DOS NUMEROS DE VIDA, PARA FICAREM NA MESMA LINHA.
  #
  # O jogo poe o sprite dos numeros em `@hpNumbers.y = value + 52`. Usando o
  # mesmo 52 aqui, o nivel e a vida leem-se como uma linha so:
  #
  #     Nv. 11          31/31
  NIVEL_X = 4      # colado a esquerda, por baixo do icone da pokebola
  NIVEL_Y = 52     # a mesma altura dos numeros de vida

  # Folga entre o texto do nivel e o simbolo do sexo, que vem logo a seguir.
  SEXO_FOLGA = 4

  # Os icones de tipo descem, para nao ficarem colados ao topo da barra.
  TIPOS_DESCE = 6

  # ⚠️ UM TIPO SO NAO PRECISA DE ENCOLHER.
  #
  # A escala existe para dois icones caberem na altura da barra. Um Pokemon de
  # tipo unico ocupa metade do espaco, e encolhe-lo so o torna dificil de ler
  # sem ganhar nada. Fica maior, e o centro vertical passa a cair sobre ele.
  ESCALA_TIPO_UNICO = 0.85
  # So a caixa do meio avanca: e o desalinhamento que da a leitura de "tres
  # coisas" em vez de "um bloco".
  MEIO_AVANCA = 10

  # ⚠️ A PRIMEIRA CAIXA ESTAVA MAIS AFASTADA QUE AS OUTRAS DUAS.
  #
  # A tabela de deslocamentos do jogo (0196_Battle_Scene_Objects) e esta:
  #
  #     @spriteY += [-42, -51, 4, 5, 50, 51][@battler.index]
  #
  # Os inimigos sao os indices 1, 3 e 5 -> -51, 5, 51. Isso da 56 px entre a
  # primeira e a segunda, e 46 entre a segunda e a terceira. Nao e um espaco
  # decorativo: e so a tabela nao ser regular, porque foi pensada para os dois
  # lados ao mesmo tempo.
  #
  # Baixar a primeira em 10 iguala os dois intervalos.
  PRIMEIRA_DESCE = 10

  module_function

  # ⚠️ FICHEIRO PROPRIO, E SEMPRE LIGADO ENQUANTO ISTO SE AFINA.
  #
  # Tres builds seguidos nao mudaram nada no ecra e nao havia como saber porque:
  # se o enxerto nao entrou, se entrou e o `apertado?` diz false, ou se o
  # aparelho nem sequer esta a correr este build. Cada uma dessas causas exige
  # uma correccao diferente, e adivinhar entre elas foi o que falhou.
  #
  # Escreve em Data/anil_horda_caixa.txt. Se o ficheiro nao existir depois de
  # uma horda, o codigo nao chegou ao aparelho.
  ARQUIVO = "Data/anil_horda_caixa.txt"

  # Regista UMA vez qual dos dois caminhos de desenho esta activo. Sem isto,
  # so a olho e que se sabia — e a olho os dois parecem iguais.
  def marcar_caminho(qual)
    return if @caminho == qual
    @caminho = qual
    log("caminho de desenho: #{qual}")
  rescue
    nil
  end

  def log(t)
    return unless (anil_diagnostico_ligado? rescue false)
    File.open(ARQUIVO, "a:UTF-8") { |fh| fh.puts("[#{Time.now.strftime('%H:%M:%S')}] #{t}") }
  rescue
    nil
  end

  # ⚠️ AS CONSTANTES DA CLASSE NAO SE VEEM DE DENTRO DE UM class_eval COM BLOCO.
  #
  # `NAME_BASE_COLOR` esta definido DENTRO de Battle::Scene::PokemonDataBox. Num
  # `class_eval do ... end`, as constantes resolvem-se pelo escopo LEXICO do
  # bloco — o topo deste ficheiro — e nao pela classe. O resultado era um
  # NameError apanhado pelo meu proprio `rescue`, que chamava o original e punha
  # tudo de volta como estava. Sem erro no ecra, sem nada no log: o metodo
  # corria, falhava, e fingia que nao tinha acontecido.
  #
  # Buscar as cores com `const_get` resolve, e serve tambem de aviso: um
  # `rescue` que repoe o comportamento antigo esconde exactamente este tipo de
  # falha.
  def cor(nome, alternativa)
    Battle::Scene::PokemonDataBox.const_get(nome)
  rescue
    alternativa
  end

  def cor_base;   @cor_base   ||= cor(:NAME_BASE_COLOR,   Color.new(255, 255, 255)); end
  def cor_sombra; @cor_sombra ||= cor(:NAME_SHADOW_COLOR, Color.new(0, 0, 0));       end

  def instalar!
    log("instalar! chamado")
    unless defined?(Battle::Scene::PokemonDataBox)
      log("  Battle::Scene::PokemonDataBox NAO existe — nada instalado")
      return false
    end
    klass = Battle::Scene::PokemonDataBox
    if klass.method_defined?(:anil_hdbx_orig_refresh)
      log("  ja estava instalado; nada a fazer")
      return false
    end

    klass.class_eval do
      # --- as estrelas de IV saem: com tres caixas nao cabem, e numa horda nao
      # servem para nada (nao se escolhe qual dos tres enfrentar).
      if method_defined?(:draw_iv_stars)
        alias_method :anil_hdbx_orig_draw_iv_stars, :draw_iv_stars
        def draw_iv_stars
          return if (AnilHordaDatabox.apertado?(@battler) rescue false)
          anil_hdbx_orig_draw_iv_stars
        end
      end

      # --- os icones de tipo: encolher e encaixar
      #
      # A posicao e MEDIDA a partir da barra de vida, e nao escrita a mao: se a
      # caixa mudar de estilo, os icones acompanham sem se lhes tocar.
      def anil_hdbx_encaixar_tipos!
        s = (@types_sprite rescue nil)
        return if s.nil? || (s.disposed? rescue true)
        unless AnilHordaDatabox.apertado?(@battler)
          if @anil_hdbx_encolhido
            s.zoom_x = 1.0
            s.zoom_y = 1.0
            @anil_hdbx_encolhido = false
          end
          return
        end
        # Quantos tipos tem mesmo este Pokemon (e nao quantos cabem na folha).
        n = ((@battler.pokemon.types.length rescue 2) rescue 2)
        escala = (n <= 1) ? AnilHordaDatabox::ESCALA_TIPO_UNICO
                          : AnilHordaDatabox::ESCALA_TIPOS
        s.zoom_x = escala
        s.zoom_y = escala
        @anil_hdbx_encolhido = true

        barra = (@hpBar rescue nil)
        return if barra.nil? || (barra.disposed? rescue true)
        bmp = (barra.bitmap rescue nil)
        return if bmp.nil? || (bmp.disposed? rescue true)
        alt_icones = ((s.bitmap ? s.bitmap.height : 0) * s.zoom_y).round
        alt_barra  = (barra.src_rect.height rescue bmp.height)
        s.x = barra.x + bmp.width + AnilHordaDatabox::MARGEM_TIPOS
        s.y = barra.y + ((alt_barra - alt_icones) / 2) + AnilHordaDatabox::TIPOS_DESCE
      rescue
        nil
      end

      alias_method :anil_hdbx_orig_refresh, :refresh
      def refresh
        anil_hdbx_orig_refresh
        anil_hdbx_encaixar_tipos!
      end

      # Os setters da caixa reposicionam o sprite dos tipos, portanto o encaixe
      # tem de correr DEPOIS deles — o refresh sozinho nao chega.
      alias_method :anil_hdbx_orig_set_x, :x=
      alias_method :anil_hdbx_orig_set_y, :y=
      def x=(value)
        anil_hdbx_orig_set_x(value)
        anil_hdbx_encaixar_tipos!
      end
      def y=(value)
        anil_hdbx_orig_set_y(value)
        anil_hdbx_encaixar_tipos!
      end

      # --- ⚠️ O NOME VEM DO draw_name, E NAO DO @displayPos.
      #
      # O log disse "sem estilo": o `@style` e nil, portanto o caminho do Deluxe
      # nunca corre e o `@displayPos` nem sequer e lido. Quem desenha o nome e o
      # `draw_name` do jogo, com o y = 12 cravado no codigo — tal como o nivel.
      #
      # Mexer no @displayPos era, desde o inicio, mexer numa coisa que ninguem
      # estava a ler. O enxerto la em baixo fica, para o caso de outro build
      # correr com estilo, mas quem manda aqui e este.
      if method_defined?(:draw_name)
        alias_method :anil_hdbx_orig_draw_name, :draw_name
        def draw_name
          unless (AnilHordaDatabox.apertado?(@battler) rescue false)
            return anil_hdbx_orig_draw_name
          end
          largura = self.bitmap.text_size(@battler.name).width
          desvio = (largura > 116) ? (largura - 127) : 0
          pbDrawTextPositions(self.bitmap,
            [[@battler.name, @spriteBaseX + 8 - desvio,
              12 + AnilHordaDatabox::NOME_DESCE, :left,
              AnilHordaDatabox.cor_base, AnilHordaDatabox.cor_sombra, :outline]])
        rescue
          (anil_hdbx_orig_draw_name rescue nil)
        end
      end

      # --- ⚠️ O @displayPos E RECALCULADO A CADA REFRESH.
      #
      # Mexer nele no `initializeDataBoxGraphic` — que corre UMA vez — nao serve
      # de nada: o `update_style` do Deluxe repoe o valor do estilo em cada
      # refresh, e a alteracao desaparece antes de alguem a desenhar.
      #
      # Foi isto que fez tres builds seguidos "nao mudarem nada". Nao havia
      # ninguem a competir connosco: era o mesmo valor a ser reposto sessenta
      # vezes por segundo. Entao aplica-se DEPOIS de ele o repor.
      if method_defined?(:update_style)
        alias_method :anil_hdbx_orig_update_style, :update_style
        def update_style
          anil_hdbx_orig_update_style
          begin
            return unless AnilHordaDatabox.apertado?(@battler)
            if @displayPos.is_a?(Hash) && @displayPos[:name].is_a?(Array)
              @displayPos[:name][1] += AnilHordaDatabox::NOME_DESCE
            end
          rescue
            nil
          end
        end
      end

      # --- ⚠️ QUEM DESENHA O NIVEL DEPENDE DO CAMINHO.
      #
      # Com estilo, o Deluxe desenha por `draw_style_text` e o `draw_level` do
      # jogo nunca e chamado; sem estilo, corre o `dx_refresh`, que o chama.
      # Como nao da para saber daqui qual dos dois esta activo, cobre-se o
      # segundo caminho e regista-se qual deles correu — a proxima batalha
      # responde, em vez de mais um palpite.
      if method_defined?(:draw_style_text)
        alias_method :anil_hdbx_orig_draw_style_text, :draw_style_text
        def draw_style_text
          anil_hdbx_orig_draw_style_text
          begin
            return unless AnilHordaDatabox.apertado?(@battler)
            AnilHordaDatabox.marcar_caminho("draw_style_text (estilo activo)")
            pbDrawTextPositions(self.bitmap,
              [["Nv." + @battler.level.to_s,
                @spriteBaseX + AnilHordaDatabox::NIVEL_X,
                AnilHordaDatabox::NIVEL_Y, :left,
                AnilHordaDatabox.cor_base, AnilHordaDatabox.cor_sombra, :outline]])
          rescue
            nil
          end
        end
      end

      # --- o simbolo do sexo acompanha o nivel
      #
      # ⚠️ A largura mede-se, e nao se estima.
      #
      # "Nv.7" e "Nv.100" nao ocupam o mesmo espaco. Perguntar ao bitmap quanto
      # mede o texto ja escrito poe o simbolo encostado nos dois casos, em vez
      # de ficar afastado num e por cima no outro.
      if method_defined?(:draw_gender)
        alias_method :anil_hdbx_orig_draw_gender, :draw_gender
        def draw_gender
          unless (AnilHordaDatabox.apertado?(@battler) rescue false)
            return anil_hdbx_orig_draw_gender
          end
          sexo = @battler.displayGender
          return if ![0, 1].include?(sexo)
          texto = (sexo == 0) ? _INTL("♂") : _INTL("♀")
          base   = AnilHordaDatabox.cor(sexo.zero? ? :MALE_BASE_COLOR : :FEMALE_BASE_COLOR,
                                        Color.new(255, 255, 255))
          sombra = AnilHordaDatabox.cor(sexo.zero? ? :MALE_SHADOW_COLOR : :FEMALE_SHADOW_COLOR,
                                        Color.new(0, 0, 0))
          nivel = "Nv." + @battler.level.to_s
          largura = (self.bitmap.text_size(nivel).width rescue 30)
          pbDrawTextPositions(self.bitmap,
            [[texto,
              @spriteBaseX + AnilHordaDatabox::NIVEL_X + largura + AnilHordaDatabox::SEXO_FOLGA,
              AnilHordaDatabox::NIVEL_Y, :left, base, sombra, :outline]])
        rescue
          (anil_hdbx_orig_draw_gender rescue nil)
        end
      end

      # --- o nivel muda de canto
      #
      # Copia-se o desenho original (uma linha de texto) com coordenadas novas.
      # E uma copia, sim — mas de UMA linha, e do jogo, que nao se actualiza por
      # baixo de nos como um plugin se actualizaria.
      if method_defined?(:draw_level)
        alias_method :anil_hdbx_orig_draw_level, :draw_level
        def draw_level
          unless (AnilHordaDatabox.apertado?(@battler) rescue false)
            return anil_hdbx_orig_draw_level
          end
          AnilHordaDatabox.marcar_caminho("draw_level (sem estilo)")
          # Se o draw_style_text ja o desenhou neste refresh, nao se repete.
          return if @anil_hdbx_nivel_feito
          pbDrawTextPositions(self.bitmap,
            [["Nv." + @battler.level.to_s,
              @spriteBaseX + AnilHordaDatabox::NIVEL_X,
              AnilHordaDatabox::NIVEL_Y, :left,
              AnilHordaDatabox.cor_base, AnilHordaDatabox.cor_sombra, :outline]])
        rescue
          (anil_hdbx_orig_draw_level rescue nil)
        end
      end

      # --- nome mais baixo, e a caixa do meio avancada
      #
      # Mexe-se nos DADOS de posicao que o desenho vai ler, e nao no desenho.
      alias_method :anil_hdbx_orig_init_graphic, :initializeDataBoxGraphic
      def initializeDataBoxGraphic(sideSize)
        anil_hdbx_orig_init_graphic(sideSize)
        begin
          return unless AnilHordaDatabox.apertado?(@battler)
          @spriteX += AnilHordaDatabox::MEIO_AVANCA if @battler.index == 3
          @spriteY += AnilHordaDatabox::PRIMEIRA_DESCE if @battler.index == 1
          if @displayPos.is_a?(Hash) && @displayPos[:name].is_a?(Array)
            @displayPos[:name][1] += AnilHordaDatabox::NOME_DESCE
          end
        rescue
          nil
        end
      end
    end

    log("ENXERTOS INSTALADOS. draw_level=#{klass.method_defined?(:anil_hdbx_orig_draw_level)} "         "refresh=#{klass.method_defined?(:anil_hdbx_orig_refresh)} "         "init=#{klass.method_defined?(:anil_hdbx_orig_init_graphic)} "         "tipos=#{klass.method_defined?(:anil_hdbx_encaixar_tipos!)}")
    true
  rescue => e
    log("falha a instalar: #{e.class}: #{e.message}")
    false
  end
end

module AnilLanRework
  class << self
    unless method_defined?(:anil_hdbx_orig_apply_post_plugin_patches)
      alias_method :anil_hdbx_orig_apply_post_plugin_patches, :apply_post_plugin_patches rescue nil
    end

    def apply_post_plugin_patches
      anil_hdbx_orig_apply_post_plugin_patches rescue nil
      AnilHordaDatabox.instalar! rescue nil
    end
  end
end
