# encoding: UTF-8
#===============================================================================
# MOD: 157_Pegadas_Montaria
#-------------------------------------------------------------------------------
# Montado, o rasto na areia passa a ser a pegada do POKEMON, e nao a bota do
# treinador.
#
# ⚠️ O SISTEMA DE PEGADAS JA EXISTE. ISTO SO LHE TROCA O DESENHO.
#
# O `Marin's Footprints` esta VIVO no PluginScripts.rxdata (fonte em
# `Data/PluginScripts_Extraidos/009_Marin_s_Footprints/script.rb`). Ele ja trata
# de tudo: repara no tile que se acabou de deixar, confirma que a terrain tag e
# 3 (areia), cria o sprite, segue o scroll do mapa e desvanece-o. Nao ha nada
# disso para reescrever — so o bitmap.
#
# ⚠️ AS MEDIDAS SAO AS DO PROPRIO JOGO, NAO INVENTADAS.
#
# Cada `steps*.png` tem DUAS marcas de bota, nao uma, e cada marca e pequena:
#
#     stepsDown    [ 8..13 x  6..17 ] e [ 18..23 x 14..25 ]   6x12, 56 px
#     stepsUp      [ 18..23 x 6..17 ] e [  8..13 x 14..25 ]   6x12, 56 px
#     stepsLeft    [ 14..25 x 14..19] e [  6..17 x 24..29 ]   12x6, 56 px
#     stepsRight   [  6..17 x 14..19] e [ 14..25 x 24..29 ]   12x6, 56 px
#
# Ou seja: os dois pes estao desencontrados de lado (10 px) E ao longo da marcha
# (8 px) — e isso que se le como "passos" e nao como um carimbo. Colar a pegada
# da Pokedex inteira dava UMA mancha de 32x32 no meio do tile.
#
# Entao a pegada do bicho e encolhida para o mesmo tamanho de uma bota e posta
# num daqueles dois sitios, ALTERNANDO a cada passo. Ao fim de dois passos ve-se
# exactamente o mesmo desenho desencontrado das botas.
#
# ⚠️ A PEGADA DA POKEDEX E PRETO SOLIDO; A DO CHAO E UMA DEPRESSAO.
#
# Medido: os `steps*.png` sao preto a alfa 76, e os 1043
# `Graphics/Pokemon/Footprints/*.png` sao preto a alfa 255. O `blt` e o
# `stretch_blt` do RGSS aceitam opacidade, portanto encolher e esbater sao a
# mesma chamada nativa.
#
# ⚠️ A ROTACAO E ASSADA NO BITMAP, E SOBRE A VERSAO JA ENCOLHIDA.
#
# O desenho da Pokedex aponta para CIMA. Como o plugin poe o sprite pelo canto e
# reescreve o x/y a cada frame, usar `angle` obrigava a brigar com essa
# reposicao. E rodando DEPOIS de encolher, cada volta custa 144 pixeis (12x12)
# em vez de 1024:
#
#     cima     encolhida directa
#     baixo    = 180        esquerda = 90        direita = 270
#
# ⚠️ QUEM NAO VE: OS OUTROS JOGADORES.
#
# O plugin decide pelo `@character.x`, e o `AnilLanRework::RemotePeer` so escreve
# o `@x` na primeira sincronizacao — quem anda de verdade e o `real_x`. Portanto
# os jogadores remotos nunca deixaram rasto, montados ou nao. Isso e do plugin.
#===============================================================================

module AnilPegadasMontaria
  PASTA = "Graphics/Pokemon/Footprints/"
  # Alfa medido nos `steps*.png` do proprio jogo.
  ALFA  = 76
  # Lado maior da marca, em pixeis. E o mesmo 12 da bota.
  LADO  = 12
  # O que se escreve no 5.º campo do passo para nao o tratar duas vezes.
  MARCA = :anil_montaria

  # ⚠️ QUANTO DURA A PEGADA.
  #
  # O plugin tira esta quantidade de opacidade por frame, e comeca em 255: a 6
  # dava 42 frames, sete decimos de segundo — via-se uma marca e ja tinha ido. A
  # 2 sao 128 frames, cerca de 2 segundos, e fica um rasto de cinco ou seis
  # pegadas atras de quem anda. Vale para as botas tambem, de proposito.
  DESVANECER = 2

  # Centro de cada uma das duas marcas, por direccao, medido nos `steps*.png`.
  # A ordem e [primeiro pe, segundo pe]; alterna-se entre os dois.
  CENTROS = {
    2 => [[11, 12], [21, 20]],   # baixo
    8 => [[21, 12], [11, 20]],   # cima
    4 => [[20, 17], [12, 27]],   # esquerda
    6 => [[12, 17], [20, 27]]    # direita
  }.freeze

  @bitmaps = {}

  class << self
    def log(t)
      AnilLanRework.log("[PEGADAS] #{t}") rescue nil
    end

    # ------------------------------------------------------------ construcao
    # A pegada da especie, ja encolhida, esbatida, virada para a direccao e
    # posta no sitio do pe certo. Fica um 32x32 pronto a entrar no sprite.
    def pegada(esp, direccao, pe)
      chave = "#{esp}|#{direccao}|#{pe}"
      return @bitmaps[chave] if @bitmaps.key?(chave)
      @bitmaps[chave] = montar(esp, direccao, pe)
    rescue
      @bitmaps[chave] = nil
    end

    def montar(esp, direccao, pe)
      marca = marca_virada(esp, direccao)
      return nil unless marca
      centros = CENTROS[direccao] || CENTROS[2]
      cx, cy = centros[pe % 2]
      fora = Bitmap.new(32, 32)
      # encostar a marca ao centro pedido, sem a deixar sair do quadro
      x = [[cx - (marca.width / 2), 0].max, 32 - marca.width].min
      y = [[cy - (marca.height / 2), 0].max, 32 - marca.height].min
      fora.blt(x, y, marca, Rect.new(0, 0, marca.width, marca.height))
      fora
    end

    # A marca pequena virada para uma direccao (sem posicao ainda).
    def marca_virada(esp, direccao)
      chave = "v|#{esp}|#{direccao}"
      return @bitmaps[chave] if @bitmaps.key?(chave)
      cima = marca_pequena(esp)
      return (@bitmaps[chave] = nil) unless cima
      @bitmaps[chave] = case direccao
                        when 8 then cima          # o desenho ja aponta para cima
                        when 2 then rodar(cima, 180)
                        when 4 then rodar(cima, 90)
                        when 6 then rodar(cima, 270)
                        else cima
                        end
    end

    # A pegada da Pokedex recortada pelo desenho, encolhida para caber em LADO
    # (mantendo a proporcao) e ja com a opacidade da areia.
    def marca_pequena(esp)
      chave = "p|#{esp}"
      return @bitmaps[chave] if @bitmaps.key?(chave)
      resolvido = (pbResolveBitmap(PASTA + esp.to_s) rescue nil)
      return (@bitmaps[chave] = nil) unless resolvido
      orig = Bitmap.new(resolvido)
      caixa = caixa_opaca(orig)
      # 247 das 1043 pegadas estao VAZIAS — sao os voadores e os que nao tem
      # pernas. Quem nao pisa nao deixa marca, e isso esta certo.
      unless caixa
        orig.dispose
        return (@bitmaps[chave] = nil)
      end
      cw = caixa[2] - caixa[0]
      ch = caixa[3] - caixa[1]
      escala = LADO.to_f / [cw, ch].max
      nw = [1, (cw * escala).round].max
      nh = [1, (ch * escala).round].max
      fora = Bitmap.new(nw, nh)
      # encolher e esbater na mesma chamada: o 4.º argumento e a opacidade
      fora.stretch_blt(Rect.new(0, 0, nw, nh), orig,
                       Rect.new(caixa[0], caixa[1], cw, ch), ALFA)
      orig.dispose
      @bitmaps[chave] = fora
    end

    # ⚠️ 1024 leituras, UMA vez por especie, e so quando ela pisa areia.
    #
    # Sem recortar pelo desenho, uma pegada com muita margem (o ARCEUS tem 32
    # pixeis opacos em 1024) ficava um ponto invisivel depois de encolhida.
    def caixa_opaca(bmp)
      x0 = bmp.width; y0 = bmp.height; x1 = -1; y1 = -1
      bmp.height.times do |y|
        bmp.width.times do |x|
          next if bmp.get_pixel(x, y).alpha == 0
          x0 = x if x < x0
          y0 = y if y < y0
          x1 = x if x > x1
          y1 = y if y > y1
        end
      end
      return nil if x1 < 0
      [x0, y0, x1 + 1, y1 + 1]
    end

    # ⚠️ RODA-SE A PIXEL, MESMO PARA 180 GRAUS.
    #
    # Dava para fazer o 180 com um `stretch_blt` de largura E altura negativas,
    # que e nativo. Mas neste motor so esta comprovado o de largura negativa (e
    # o que o 156 usa para espelhar), e uma altura negativa que nao funcionasse
    # dava um quadro em branco sem erro nenhum. Como a marca ja vem encolhida,
    # sao 144 pixeis (12x12) uma vez por especie e direccao — nao vale a pena
    # apostar em algo que nao se mediu.
    def rodar(src, graus)
      return nil unless src
      w = src.width
      h = src.height
      fora = Bitmap.new(graus == 180 ? w : h, graus == 180 ? h : w)
      h.times do |y|
        w.times do |x|
          c = src.get_pixel(x, y)
          next if c.alpha == 0
          case graus
          when 90  then fora.set_pixel(y, w - 1 - x, c)          # anti-horario
          when 180 then fora.set_pixel(w - 1 - x, h - 1 - y, c)
          else          fora.set_pixel(h - 1 - y, x, c)          # 270
          end
        end
      end
      fora
    end

    def limpar!
      @bitmaps.each_value { |b| b.dispose if b && !b.disposed? }
      @bitmaps = {}
    rescue
      @bitmaps = {}
    end

    # -------------------------------------------------------------- enxerto
    # ⚠️ TEM DE SER NO apply_post_plugin_patches.
    #
    # O alias tem de apanhar o `update` JA com o do plugin por baixo; instalado
    # antes, o plugin redefinia-o por cima e isto nunca corria.
    def instalar!
      return false unless defined?(Sprite_Character)
      return false unless Sprite_Character.method_defined?(:footsteps_update)
      return false if Sprite_Character.method_defined?(:anil_pegada_orig_update)

      # o desvanecer e uma constante do plugin, lida a cada frame — trocar o
      # valor chega, nao e preciso mexer no metodo
      if Sprite_Character.const_defined?(:FADE_OUT_SPEED) &&
         Sprite_Character.const_get(:FADE_OUT_SPEED) != DESVANECER
        Sprite_Character.send(:remove_const, :FADE_OUT_SPEED)
        Sprite_Character.const_set(:FADE_OUT_SPEED, DESVANECER)
      end

      # ⚠️ QUEM CARIMBA MUDA CONFORME SE ESTA MONTADO OU NAO.
      #
      # De origem, `DUPLICATE_FOOTSTEPS_WITH_FOLLOWER = false` faz com que, tendo
      # follower, quem deixa marcas seja o FOLLOWER e nao o jogador. Montado
      # isso da o resultado errado duas vezes: sai a bota do treinador em vez da
      # pata do bicho, e sai na posicao do follower e nao na de quem anda.
      #
      # Entao liga-se o carimbo dos dois, e escolhe-se em codigo qual e que
      # fica: montado vale o do JOGADOR (com a pata), a pe vale o do FOLLOWER
      # (como sempre foi). O que nao vale, apaga-se no trocar_desenho.
      if Sprite_Character.const_defined?(:DUPLICATE_FOOTSTEPS_WITH_FOLLOWER) &&
         !Sprite_Character.const_get(:DUPLICATE_FOOTSTEPS_WITH_FOLLOWER)
        Sprite_Character.send(:remove_const, :DUPLICATE_FOOTSTEPS_WITH_FOLLOWER)
        Sprite_Character.const_set(:DUPLICATE_FOOTSTEPS_WITH_FOLLOWER, true)
      end

      Sprite_Character.class_eval do
        alias_method :anil_pegada_orig_update, :update

        def update
          anil_pegada_orig_update
          @anil_pegada_pe = AnilPegadasMontaria.trocar_desenho(
            @character, @steps, @anil_pegada_pe.to_i)
        rescue
          nil
        end
      end

      log("enxerto instalado (montado, a pegada e do Pokemon; desvanecer=#{DESVANECER})")
      true
    rescue => e
      log("falha ao instalar: #{e.class}: #{e.message}")
      false
    end

    # Troca o desenho dos passos ainda por tratar. Devolve o contador do pe,
    # para o proximo passo sair do outro lado.
    # Quem e este personagem, para efeitos de pegada.
    def papel(personagem)
      return :jogador if defined?($game_player) && $game_player && personagem.equal?($game_player)
      return :follower if defined?(Game_FollowingPkmn) && personagem.is_a?(Game_FollowingPkmn)
      :outro
    rescue
      :outro
    end

    def trocar_desenho(personagem, passos, pe)
      return pe unless passos.is_a?(Array) && !passos.empty?
      return pe unless personagem
      esp = (defined?(AnilMontaria) ? (AnilMontaria.montaria_de(personagem) rescue nil) : nil)
      montado = (defined?(AnilMontaria) ? (AnilMontaria.montado? rescue false) : false)
      quem = papel(personagem)
      # ⚠️ Um dos dois carimbos e sempre de mais — ver a nota no instalar!.
      # Montado manda o jogador; a pe manda o follower.
      a_mais = (quem == :follower && montado) || (quem == :jogador && !montado)
      dir = (personagem.direction rescue 2).to_i
      passos.each do |p|
        next unless p.is_a?(Array) && p[0]
        next if p.length >= 5 && p[4] == MARCA
        # marca-se SEMPRE, mesmo a pe: assim um passo dado a pe nao volta a ser
        # examinado a cada frame ate desaparecer
        p[4] = MARCA
        if a_mais
          # o sprite fica, mas invisivel: o plugin conta com ele na lista e e
          # ele proprio que o liberta quando a opacidade acabar
          (p[0].visible = false) rescue nil
          next
        end
        next unless esp
        bmp = pegada(esp, dir, pe)
        # so conta como passo quando houve mesmo marca; senao um bicho sem
        # pegada (voador) fazia o contador andar e nunca se via nada
        next unless bmp && !bmp.disposed?
        next if p[0].disposed?
        p[0].bitmap = bmp
        pe += 1
      end
      pe
    rescue
      pe
    end
  end
end

module AnilLanRework
  class << self
    unless method_defined?(:anil_pegada_orig_apply_post_plugin_patches)
      alias_method :anil_pegada_orig_apply_post_plugin_patches, :apply_post_plugin_patches rescue nil
    end

    def apply_post_plugin_patches
      anil_pegada_orig_apply_post_plugin_patches rescue nil
      AnilPegadasMontaria.instalar! rescue nil
    end
  end
end
