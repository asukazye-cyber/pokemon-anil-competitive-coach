# encoding: UTF-8
#===============================================================================
# MOD: 170_Neblina_Baixa
#-------------------------------------------------------------------------------
# Neblina de mapa, do tipo de Lavender Town: um veu que passa por cima da cena e
# desliza sozinho, preso ao MUNDO e nao a camara.
#
# ⚠️ PORQUE E UM SPRITE SO, DEPOIS DE TER SIDO DEZASSEIS.
#
# A primeira versao dividia o ecra numa tira por linha, cada uma com o z da sua
# linha, para a neblina se enfiar entre o tronco e a copa das arvores. A ideia
# funcionava no papel e a aritmetica estava certa, mas em jogo apareciam cortes
# horizontais — e cada correccao empurrava o corte para outro sitio em vez de o
# apagar. Um efeito de clima nao pode ter costuras, e nenhuma quantidade de
# afinacao ia tirar uma costura de um desenho feito de pedacos.
#
# Um sprite unico nao tem onde ter uma. Perde-se a passagem por baixo das copas;
# ganha-se uma neblina que se le como neblina.
#
# ⚠️ ELA E DO MUNDO, NAO DA CAMARA.
#
# So com deriva, ficava colada ao ecra: o jogador andava e ela ia atras, como se
# estivesse pintada no vidro. Somando o deslocamento do mapa ao recorte, ela
# prende-se ao chao — o jogador ATRAVESSA-A. A deriva fica por cima disso, e e
# so ela que se ve com o jogador parado.
#
# ⚠️ NAO SE DESENHA NADA POR FRAME.
#
# A folha e montada uma vez, maior que o ecra, com o desenho repetido. Por frame
# mexe-se o src_rect e mais nada. E a folha nem se larga ao sair do mapa: montar
# custa dezenas de blt e ela nunca muda.
#===============================================================================

#-------------------------------------------------------------------------------
# O CLIMA "NUBLADO", QUE ATE AQUI NAO EXISTIA
#-------------------------------------------------------------------------------
# ⚠️ O :Fog FAZIA OS DOIS PAPEIS, E ISSO E QUE OS PARTIA.
#
# Nao havia clima de ceu encoberto. Usava-se o :Fog e escondiam-se as particulas
# de nevoeiro nos mapas exteriores, ficando so o tom cinzento e as sombras de
# nuvem. Funcionava enquanto ninguem quisesse nevoeiro a serio.
#
# Assim que a neblina rasteira passou a existir, os dois papeis colidiram: quem
# pedia neblina levava dez sombras de nuvem por cima, e quem queria nublado nao
# tinha como o pedir sem nevoeiro.
#
# Agora sao dois:
#
#     :Fog     -> neblina rasteira, sem sombras de nuvem
#     :Cloudy  -> ceu encoberto, sem nevoeiro nenhum
#
# ⚠️ A CATEGORIA E :None DE PROPOSITO.
#
# A categoria e o que a BATALHA le para decidir efeitos (chuva sobe Agua, sol
# sobe Fogo). Ceu encoberto nao muda nada em combate — e so ver o ceu. Pondo-o
# na categoria :Fog, ele ligaria a neblina deste MOD, que e o contrario do que
# se quer.
#-------------------------------------------------------------------------------
if defined?(GameData::Weather) && !(GameData::Weather.try_get(:Cloudy) rescue nil)
  begin
    GameData::Weather.register({
      :id        => :Cloudy,
      :category  => :None,
      :id_number => 9,
      :tone_proc => proc { |strength| next Tone.new(-30, -30, -30, 0) }
    })
  rescue
    nil
  end
end

module AnilNeblinaBaixa
  ACTIVO = true

  # 128x128, feito para repetir sem costura.
  GRAFICO = "Graphics/Weather/fog_tile"

  # ⚠️ O numero que manda no aspecto todo. Entre 80 e 120 le-se como neblina;
  # acima de 150 vira leite e o mapa desaparece por baixo.
  OPACIDADE = 105

  # Pixeis por frame. Devagar de proposito: neblina que corre parece fumo.
  DERIVA_X = 0.25
  DERIVA_Y = 0.04

  # Acima de tudo o que o mapa desenha. O tile mais alto de todos anda pelos
  # 600; 3000 e o valor que o fog classico do RMXP usava, e sobra de longe.
  Z = 3000

  class << self
    def largura; (Settings::SCREEN_WIDTH rescue 512); end
    def altura;  (Settings::SCREEN_HEIGHT rescue 384); end

    def clima_de_neblina?
      return false unless ACTIVO
      t = ($game_screen.weather_type rescue nil)
      return false if t.nil? || t == :None
      (GameData::Weather.get(t).category rescue nil) == :Fog
    rescue
      false
    end

    def folha
      return @folha if @folha && !(@folha.disposed? rescue true)
      cam = (pbResolveBitmap(GRAFICO) rescue nil)
      return nil unless cam
      azulejo = (Bitmap.new(cam) rescue nil)
      return nil unless azulejo
      @azulejo_w = azulejo.width
      @azulejo_h = azulejo.height
      # Uma folga de um azulejo em cada lado: o recorte desliza ate essa
      # distancia antes de o modulo o trazer de volta ao principio.
      lw = largura + @azulejo_w
      lh = altura  + @azulejo_h
      @folha = Bitmap.new(lw, lh)
      y = 0
      while y < lh
        x = 0
        while x < lw
          @folha.blt(x, y, azulejo, Rect.new(0, 0, @azulejo_w, @azulejo_h))
          x += @azulejo_w
        end
        y += @azulejo_h
      end
      azulejo.dispose
      @folha
    rescue
      @folha = nil
    end

    def montar!(vp)
      return if @veu && !(@veu.disposed? rescue true)
      f = folha
      return unless f
      @veu = Sprite.new(vp)
      @veu.bitmap  = f
      @veu.x       = 0
      @veu.y       = 0
      @veu.z       = Z
      @veu.opacity = OPACIDADE
      @veu.src_rect.set(0, 0, largura, altura)
      @dx = 0.0
      @dy = 0.0
    rescue
      largar!
    end

    def largar!
      (@veu.dispose rescue nil) if @veu
      @veu = nil
    rescue
      @veu = nil
    end

    def esquecer_tudo!
      largar!
      (@folha.dispose rescue nil) if @folha
      @folha = nil
    rescue
      nil
    end

    def actualizar!(vp)
      unless clima_de_neblina? && vp
        largar!
        return
      end
      montar!(vp)
      return unless @veu && !(@veu.disposed? rescue true)

      @dx = (@dx || 0.0) + DERIVA_X
      @dy = (@dy || 0.0) + DERIVA_Y
      mx = ($game_map.display_x.to_f / Game_Map::X_SUBPIXELS rescue 0.0)
      my = ($game_map.display_y.to_f / Game_Map::Y_SUBPIXELS rescue 0.0)
      ox = ((@dx + mx) % @azulejo_w.to_f).to_i
      oy = ((@dy + my) % @azulejo_h.to_f).to_i
      @veu.src_rect.set(ox, oy, largura, altura)
    rescue
      largar!
    end
  end
end

#-------------------------------------------------------------------------------
# Enxerto no update do Scene_Map, como o MOD 166. Nao ha EventHandler para "um
# frame do mapa"; o guarda evita apanhar o alias duas vezes se recarregar.
#-------------------------------------------------------------------------------
if defined?(Scene_Map) && !Scene_Map.method_defined?(:anil_neblina_orig_update)
  Scene_Map.class_eval do
    alias_method :anil_neblina_orig_update, :update

    def update(*a)
      anil_neblina_orig_update(*a)
      begin
        AnilNeblinaBaixa.actualizar!(Spriteset_Map.viewport)
      rescue
        nil
      end
    end
  end
end
