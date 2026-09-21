# encoding: UTF-8
#===============================================================================
# MOD: 165_Brilho_Montaria
#-------------------------------------------------------------------------------
# Zonas da montaria que acendem e apagam em ciclo, como cristais incandescentes.
#
# ⚠️ SAO GRUPOS, E NAO UMA ZONA SO.
#
# Uma montaria costuma ter mais do que uma zona luminosa, e elas nao querem os
# mesmos ajustes: no RAYQUAZA os aneis amarelos e as marcas vermelhas sao
# materiais diferentes, com cor e ritmo diferentes. Cada grupo traz as suas
# mascaras (uma por quadro, por direccao) e a sua cor, ciclo, base e
# escurecimento.
#
# ⚠️ O QUE FOI PINTADO ACENDE, POR ESCURO QUE SEJA.
#
#     alfa = piso + (1 - piso) * luminancia_normalizada
#
# A primeira versao fazia o alfa PROPORCIONAL a luminancia, com um corte por
# baixo. Isso servia quando a luz era da cor do proprio pixel — claro acende,
# escuro nao. Assim que a cor passou a mandar, deixou de servir: medido no
# RAYQUAZA, a zona pintada tinha luminancia 0,144 a 0,244, TODA abaixo do corte
# de 0,35, e a camada saia vazia. No editor via-se o marcador de zona e parecia
# estar bom; no jogo nao aparecia nada.
#
# Agora a luminancia faz o SOMBREADO e o piso garante que o pintado acende.
#
# ⚠️ O PULSO NAO TOCA EM PIXEIS. NUNCA.
#
# As camadas sao construidas UMA vez e ficam em cache. Depois disso, por frame,
# muda-se exactamente uma coisa por grupo: a opacidade do sprite. Foi mexer em
# pixeis por frame que custou 45 ms por passo no mato.
#
# ⚠️ SOMA-SE LUZ (blend_type = 1), NAO SE SUBSTITUI O PIXEL.
#
# E o que faz o cristal parecer aceso em vez de pintado. Quando o escurecimento
# esta ligado ha uma segunda camada que SUBTRAI (blend_type = 2) — sem ela,
# somar vermelho a um cristal quase branco da branco, porque o canal ja esta no
# tecto.
#
# ⚠️ A LUZ NAO ESCURECE A NOITE.
#
# O Sprite_Montaria copia o tom do pai. Estas camadas nao: sao luz propria.
#
# ⚠️ ORDEM DE DESENHO.
#
# Cada grupo ocupa dois degraus de `z` entre a montaria e o cavaleiro: um para
# apagar, outro para somar. Dois sprites no mesmo `z` desenham-se por ordem
# indefinida, e o efeito mudava de frame para frame. Ver `deslocamento_z`.
#===============================================================================

module AnilBrilhoMontaria
  ACTIVO = true

  # Tecto de pixeis examinados POR CELULA da folha (4x4 = 16 celulas). Rede de
  # seguranca para o caso de alguem pintar a montaria inteira; uma celula normal
  # nem chega perto. Ver a nota no ciclo: era um tecto unico para a folha toda, e
  # isso fazia as ultimas celulas perderem o brilho sem aviso nenhum.
  MAX_PIXEIS = 60_000

  # Quantos grupos se leem. O limite existe por causa dos degraus de `z`.
  MAX_GRUPOS = 4

  @cache = {}

  class << self
    def log(t)
      AnilLanRework.log("[BRILHO] #{t}") rescue nil
    end

    def agora
      System.uptime
    rescue
      Time.now.to_f
    end

    # ------------------------------------------------------------- as receitas
    def cfg(esp, d)
      r = (AnilMontaria.receitas[esp.to_s.upcase] rescue nil)
      return nil unless r.is_a?(Hash)
      c = r[AnilMontaria::DIRECOES[d]]
      c.is_a?(Hash) ? c : nil
    rescue
      nil
    end

    # ⚠️ As receitas gravadas antes dos grupos tinham uma zona so, em campos
    # soltos (`brilho_mascaras`, `brilho_cor`, ...). Sao lidas na mesma: viram o
    # grupo 0, sem ninguem ter de reconverter ficheiros.
    def grupos(esp, d)
      c = cfg(esp, d)
      return [] unless c
      lst = c["brilhos"]
      return lst if lst.is_a?(Array)
      antigas = c["brilho_mascaras"]
      return [] unless antigas.is_a?(Array) && antigas.length == 4
      return [] unless antigas.any? { |q| q.is_a?(Array) && !q.empty? }
      [{
        "mascaras"  => antigas,
        "cor"       => c["brilho_cor"],
        "cor_forca" => c["brilho_cor_forca"],
        "periodo"   => c["brilho_periodo"],
        "minimo"    => c["brilho_minimo"],
        "maximo"    => c["brilho_maximo"],
        "limiar"    => c["brilho_limiar"],
        "piso"      => c["brilho_piso"],
        "escurecer" => c["brilho_escurecer"]
      }]
    rescue
      []
    end

    # O maior numero de grupos entre as quatro direccoes: uma zona pode existir
    # so de frente.
    def quantos(esp)
      n = 0
      4.times do |d|
        m = grupos(esp, d).length
        n = m if m > n
      end
      n > MAX_GRUPOS ? MAX_GRUPOS : n
    rescue
      0
    end

    def grupo(esp, d, i)
      g = grupos(esp, d)[i]
      g.is_a?(Hash) ? g : nil
    rescue
      nil
    end

    def marcas(esp, d, i, quadro)
      g = grupo(esp, d, i)
      return nil unless g
      m = g["mascaras"]
      return nil unless m.is_a?(Array) && m.length == 4
      lista = m[quadro]
      (lista.is_a?(Array) && !lista.empty?) ? lista : nil
    rescue
      nil
    end

    # ⚠️ O ajuste vem do GRUPO, e procura-se nas quatro direccoes.
    #
    # O editor escreve o mesmo valor nas quatro, mas uma receita mexida a mao
    # pode ter a zona so numa. Aceita-se o primeiro que apareca.
    def ajuste(esp, i, chave, padrao)
      4.times do |d|
        g = grupo(esp, d, i)
        next unless g
        v = g[chave]
        return v unless v.nil?
      end
      padrao
    rescue
      padrao
    end

    def num(esp, i, chave, padrao)
      ajuste(esp, i, chave, padrao).to_f
    rescue
      padrao
    end

    def tem_brilho?(esp, i)
      4.times do |d|
        4.times { |q| return true if marcas(esp, d, i, q) }
      end
      false
    rescue
      false
    end

    # A cor do grupo, ja com a forca. nil = fica a cor propria do pixel.
    def tinta(esp, i)
      forca = num(esp, i, "cor_forca", 1.0)
      return nil if forca <= 0.0
      forca = 1.0 if forca > 1.0
      txt = ajuste(esp, i, "cor", nil)
      return nil unless txt
      t = txt.to_s.sub(/\A#/, "")
      t = t.chars.map { |ch| ch * 2 }.join if t.length == 3
      return nil unless t.length >= 6
      [t[0, 2].to_i(16), t[2, 2].to_i(16), t[4, 2].to_i(16), forca]
    rescue
      nil
    end

    # --------------------------------------------------------- a camada de luz
    # ⚠️ Construida a partir da folha JA RODADA.
    #
    # As marcas foram pintadas no editor sobre o quadro rodado, portanto as
    # fraccoes referem-se a esse. Sair dali faz as duas pontas baterem certo sem
    # nenhuma conversao.
    def folha(esp, i, shiny = false, hue = 0)
      return nil unless ACTIVO
      chave = "luz|#{esp}|#{i}|#{shiny ? 1 : 0}|#{hue}"
      return @cache[chave] if @cache.key?(chave) && (@cache[chave].nil? || !@cache[chave].disposed?)
      return (@cache[chave] = nil) unless tem_brilho?(esp, i)

      base = (AnilMontaria.montaria_rodada(esp, shiny, hue) rescue nil)
      return (@cache[chave] = nil) unless base && !base.disposed?

      mw = base.width / 4
      mh = base.height / 4
      pintura = tinta(esp, i)
      limiar = num(esp, i, "limiar", 0.0)
      limiar = 0.0 if limiar < 0.0
      limiar = 0.99 if limiar > 0.99
      piso = num(esp, i, "piso", 0.6)
      piso = 0.0 if piso < 0.0
      piso = 1.0 if piso > 1.0
      escala = 1.0 / (1.0 - limiar)

      fora = Bitmap.new(base.width, base.height)
      total = 0
      cortado = nil

      4.times do |d|
        4.times do |c|
          lista = marcas(esp, d, i, c)
          next unless lista
          ox = c * mw
          oy = d * mh
          # ⚠️ O TECTO E POR CELULA, E NAO PARA A FOLHA TODA.
          #
          # Era um so contador para as dezasseis celulas, mas o corte dava-se na
          # ordem do ciclo: quem vinha primeiro gastava o orcamento e quem vinha
          # depois desaparecia em silencio. Numa montaria grande e muito pintada
          # — o Giratina — bastava isso para o peitoral da pose de frente nao
          # acender, sem erro nenhum a apontar o dedo. O que faltava nao tinha
          # nada de especial: era so o que calhou ficar do lado errado do tecto.
          #
          # Com o contador por celula, nenhuma rouba o orcamento a outra. E o
          # total continua limitado: o `vistos` ja garante que cada pixel e lido
          # uma vez e as celulas nao se sobrepoem, portanto no pior caso
          # examina-se a folha inteira e mais nada.
          #
          # Isto tambem nao pesa: a folha e construida UMA vez e fica em cache.
          total = 0
          # ⚠️ Um pixel so e examinado uma vez, mesmo que duas marcas o cubram.
          # As pinceladas sobrepoem-se muito (o traco e feito de circulos
          # encostados), e sem isto o mesmo pixel era lido dezenas de vezes.
          vistos = {}
          lista.each do |m|
            next unless m.is_a?(Array) && m.length >= 3
            r = m[2].to_f * mh
            r = 0.5 if r < 0.5
            x0 = (m[0].to_f * mw - r).round
            y0 = (m[1].to_f * mh - r).round
            lado = [1, (r * 2).round].max
            (y0...(y0 + lado)).each do |y|
              next if y < 0 || y >= mh
              (x0...(x0 + lado)).each do |x|
                next if x < 0 || x >= mw
                chave_px = (y * mw) + x
                next if vistos[chave_px]
                vistos[chave_px] = true
                if total >= MAX_PIXEIS
                  cortado = "d#{d}c#{c}"
                  next
                end
                total += 1
                cor = base.get_pixel(ox + x, oy + y)
                a = cor.alpha
                next if a <= 0
                lum = ((0.299 * cor.red) + (0.587 * cor.green) + (0.114 * cor.blue)) / 255.0
                n = (lum - limiar) * escala
                n = 0.0 if n < 0.0
                n = 1.0 if n > 1.0
                f = piso + ((1.0 - piso) * n)
                next if f <= 0.0
                cr = cor.red
                cg = cor.green
                cb = cor.blue
                if pintura
                  mistura = pintura[3]
                  cr = (cr + ((pintura[0] - cr) * mistura)).round
                  cg = (cg + ((pintura[1] - cg) * mistura)).round
                  cb = (cb + ((pintura[2] - cb) * mistura)).round
                end
                fora.set_pixel(ox + x, oy + y, Color.new(cr, cg, cb, (f * a).round))
              end
            end
          end
        end
      end

      log("camada #{i} de #{esp}: #{total} pixeis#{cortado ? " — celula #{cortado} CORTADA no tecto" : ''}")
      @cache[chave] = fora
    rescue => e
      log("falha a construir #{esp}/#{i}: #{e.class}: #{e.message}")
      @cache[chave] = nil
    end

    # ------------------------------------------------- a camada que escurece
    # ⚠️ Nao se coze isto na folha da montaria.
    #
    # Essa folha e PARTILHADA com o charset do cavaleiro e com quem nao tem
    # brilho — escurece-la estragava os dois. Fica num sprite proprio, a
    # subtrair, com opacidade fixa: tambem aqui nao ha trabalho por frame.
    def folha_escura(esp, i, shiny = false, hue = 0)
      quanto = num(esp, i, "escurecer", 0.0)
      return nil if quanto <= 0.0
      quanto = 1.0 if quanto > 1.0
      chave = "escuro|#{esp}|#{i}|#{shiny ? 1 : 0}|#{hue}|#{(quanto * 100).round}"
      return @cache[chave] if @cache.key?(chave) && (@cache[chave].nil? || !@cache[chave].disposed?)

      luz = folha(esp, i, shiny, hue)
      base = (AnilMontaria.montaria_rodada(esp, shiny, hue) rescue nil)
      return (@cache[chave] = nil) unless luz && base
      return (@cache[chave] = nil) if luz.disposed? || base.disposed?

      fora = Bitmap.new(base.width, base.height)
      base.height.times do |y|
        base.width.times do |x|
          next if luz.get_pixel(x, y).alpha <= 0
          c = base.get_pixel(x, y)
          fora.set_pixel(x, y, Color.new((c.red * quanto).round,
                                         (c.green * quanto).round,
                                         (c.blue * quanto).round, 255))
        end
      end
      @cache[chave] = fora
    rescue => e
      log("falha a escurecer #{esp}/#{i}: #{e.class}: #{e.message}")
      @cache[chave] = nil
    end

    # ------------------------------------------------------------------ o pulso
    # Relogio global de proposito: montarias iguais pulsam juntas, o que se le
    # como intencional em vez de caotico.
    def intensidade(esp, i)
      periodo = num(esp, i, "periodo", 4.0)
      periodo = 0.5 if periodo < 0.5
      minimo  = num(esp, i, "minimo", 0.15)
      maximo  = num(esp, i, "maximo", 1.0)
      fase = (agora % periodo) / periodo
      onda = 0.5 - (0.5 * Math.cos(2 * Math::PI * fase))
      v = minimo + ((maximo - minimo) * onda)
      v = 0.0 if v < 0.0
      v = 1.0 if v > 1.0
      v
    rescue
      0.0
    end

    # ⚠️ Quantos degraus de `z` a montaria tem de descer.
    #
    # Cada grupo precisa de dois (apagar e somar) e o cavaleiro fica no topo:
    #
    #     montaria (-2n-1) ... apagar somar ... cavaleiro (0)
    def deslocamento_z(esp)
      (quantos(esp) * 2) + 1
    rescue
      1
    end

    def limpar!
      @cache.each_value { |b| b.dispose if b && !(b.disposed? rescue true) }
      @cache = {}
    rescue
      @cache = {}
    end
  end
end

#-------------------------------------------------------------------------------
# Os sprites da luz, colados ao da montaria.
#-------------------------------------------------------------------------------
if defined?(Sprite_Montaria)
  class Sprite_Montaria
    unless method_defined?(:anil_brilho_orig_update)
      alias_method :anil_brilho_orig_update, :update
      alias_method :anil_brilho_orig_dispose, :dispose

      def update
        anil_brilho_orig_update
        return if disposed?
        actualizar_brilho
      rescue
        nil
      end

      def actualizar_brilho
        esp = (AnilMontaria.montaria_de(personagem) rescue nil)
        if esp.nil? || @sprite.nil? || (@sprite.disposed? rescue true)
          largar_brilho
          return
        end

        cor = [AnilMontaria.montaria_shiny?(personagem),
               AnilMontaria.montaria_hue(personagem)]
        if @brilho_esp != esp || @brilho_cor != cor
          largar_brilho
          @brilho_esp = esp
          @brilho_cor = cor
          @brilho_n = AnilBrilhoMontaria.quantos(esp)
        end
        return if @brilho_n.nil? || @brilho_n <= 0

        @brilho_sprites ||= []
        @escuro_sprites ||= []

        @brilho_n.times do |i|
          luz = AnilBrilhoMontaria.folha(esp, i, cor[0], cor[1])
          next unless luz && !(luz.disposed? rescue true)

          # a que apaga vem primeiro, e fica por baixo da que soma
          escuro = AnilBrilhoMontaria.folha_escura(esp, i, cor[0], cor[1])
          if escuro && !(escuro.disposed? rescue true)
            e = (@escuro_sprites[i] ||= criar_camada(escuro, 2))
            pousar_camada(e, (i * 2) + 1)
            e.opacity = @sprite.opacity
          end

          s = (@brilho_sprites[i] ||= criar_camada(luz, 1))
          pousar_camada(s, (i * 2) + 2)
          # ⚠️ NAO se copia o tom do pai: isto e luz propria.
          s.opacity = (@sprite.opacity * AnilBrilhoMontaria.intensidade(esp, i)).round
        end
      rescue
        nil
      end

      def criar_camada(bmp, mistura)
        s = Sprite.new(@viewport)
        s.bitmap = bmp
        s.blend_type = mistura
        s
      end

      # Segue a montaria em tudo — mesmo recorte, mesma ancora, mesma posicao.
      # So o `z` e que sobe, um degrau por camada.
      def pousar_camada(s, degrau)
        return unless s && !(s.disposed? rescue true)
        s.src_rect.set(@sprite.src_rect.x, @sprite.src_rect.y,
                       @sprite.src_rect.width, @sprite.src_rect.height)
        s.x = @sprite.x
        s.y = @sprite.y
        s.ox = @sprite.ox
        s.oy = @sprite.oy
        s.z = @sprite.z + degrau
        s.visible = @sprite.visible
      rescue
        nil
      end

      def largar_brilho
        (@brilho_sprites || []).each { |s| s.dispose if s && !(s.disposed? rescue true) }
        (@escuro_sprites || []).each { |s| s.dispose if s && !(s.disposed? rescue true) }
        @brilho_sprites = nil
        @escuro_sprites = nil
        @brilho_esp = nil
        @brilho_cor = nil
        @brilho_n = nil
      rescue
        nil
      end

      def dispose
        largar_brilho
        anil_brilho_orig_dispose
      end
    end
  end
end

AnilLanRework.log("165_Brilho_Montaria carregado") rescue nil
