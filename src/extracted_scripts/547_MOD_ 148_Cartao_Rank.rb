# encoding: UTF-8
#===============================================================================
# MOD: 148_Cartao_Rank
#-------------------------------------------------------------------------------
# Na FRENTE do cartao (plugin 046, HGSS):
#
#   1. a linha "PONTOS" passa a mostrar os pontos de rank do PVP
#   2. o emblema do rank aparece no canto do quadro do treinador
#   3. o texto todo desce alguns pixels, para ficar centrado nas faixas
#
#===============================================================================
# 1. A LINHA "PONTOS"
#
# O plugin desenha:
#
#     [_INTL("PUNTOS"), 32, 118 + 32, 0, base, shadow],
#     [sprintf("%d", pbGet(POKEBATTLE_POINTS_VARIABLE)), 302 + 2, ...]
#
# Ou seja, uma variavel de jogo com os Pontos de Batalha — nada a ver com o
# ranqueado. Aqui reescreve-se so aquele numero.
#
#===============================================================================
# 2. O ALINHAMENTO
#
# ⚠️ O deslocamento e uma CONSTANTE para ser afinada olhando o jogo, e nao um
# valor medido. Tentei medir as faixas do card_5.PNG e nao da para confiar: o
# contraste do fundo e sutil demais para detectar as bandas de forma estavel, e
# as metricas de fonte do RGSS nao sao reproduziveis fora dele. O que se ve na
# imagem e que o texto encosta no topo da faixa, entao desce-se um pouco.
#
# Se ainda ficar torto, e UM numero: DESLOCAMENTO_Y.
#
#===============================================================================
# 3. O EMBLEMA
#
# Fica no canto superior esquerdo do quadro do treinador, que comeca em
# (318, 106) — ver @sprites["trainer"] no plugin. 44x44 para nao cobrir o
# boneco. POSICAO_EMBLEMA move, se preciso.
#
# Os ficheiros vivem em Graphics/UI/Trainer Card/rank/. Se faltarem (cliente que
# ainda nao recebeu os assets), nao se desenha nada — o cartao continua a abrir.
#===============================================================================

module AnilCartaoRank
  # Quanto o texto da frente desce. Positivo = para baixo.
  DESLOCAMENTO_Y = 4

  # ---------------------------------------------------------------------------
  # O QUADRO DO TREINADOR
  #
  # Medido no card_5.PNG (256x192, desenhado a 2x -> 512x384): a moldura comeca
  # em y=96 e a sua borda esquerda em x=336. O emblema fica DENTRO dela, e o
  # boneco desloca-se para a direita para nao ficarem por cima um do outro.
  #
  # Os tres numeros abaixo sao para afinar olhando o jogo — nao ha como medir a
  # posicao final do sprite do treinador fora do RGSS, porque ela depende do
  # tamanho de cada skin.
  # ---------------------------------------------------------------------------
  POSICAO_EMBLEMA = [340, 106]

  # Quanto o boneco anda para a direita, abrindo espaco para o emblema.
  DESLOCAMENTO_TREINADOR_X = 26

  # A letra da divisao (A/B/C) DENTRO do escudo — DESLIGADA por decisao do
  # administrador (2026-08-16): ficou visualmente ruim sobre a arte.
  #
  # Fica so a chave, e nao o codigo apagado, porque os ficheiros divisao_*.png
  # continuam la e o posicionamento ja esta afinado. Voltar a ligar e mudar
  # false para true — a divisao continua visivel no texto do rank, no verso do
  # cartao ("Lider B"), portanto nao se perdeu informacao nenhuma.
  MOSTRAR_DIVISAO = false

  LETRA_DX = 16
  LETRA_DY = 28
  PASTA_DIVISAO = "Graphics/UI/Trainer Card/rank/divisao_"

  # tier -> ficheiro. A ordem seguiu a progressao dos materiais dos emblemas:
  # madeira, bronze, PRATA, OURO, coroa. O terceiro veio nomeado "elite_4" na
  # origem, mas pela progressao e o LIDER — quem gerou as imagens nao tinha esse
  # rank na lista e chamou os dois ultimos de "parte 1 e 2".
  EMBLEMAS = {
    0 => "rank_treinador",
    1 => "rank_desafiante",
    2 => "rank_lider",
    3 => "rank_elite4",
    4 => "rank_campeao"
  }.freeze

  PASTA = "Graphics/UI/Trainer Card/rank/"

  module_function

  def caminho_do_emblema
    return nil unless defined?(AnilRanqueado)
    nome = EMBLEMAS[AnilRanqueado.tier.to_i]
    return nil unless nome
    caminho = PASTA + nome
    # Sem o ficheiro nao se desenha: um cliente que recebeu o Scripts.rxdata mas
    # ainda nao os assets nao pode rebentar por causa de um enfeite.
    return nil unless (pbResolveBitmap(caminho) rescue nil)
    caminho
  rescue
    nil
  end

  # A letra da divisao sai do rotulo ("Lider B" -> "b"). Elite 4 e Campeao nao
  # tem divisao, e ai o rotulo nao termina em letra solta — devolve nil.
  def caminho_da_divisao
    return nil unless MOSTRAR_DIVISAO
    return nil unless defined?(AnilRanqueado)
    rot = AnilRanqueado.rotulo.to_s.strip
    return nil if rot.empty?
    ultima = rot[-1, 1].to_s.upcase
    return nil unless %w[A B C].include?(ultima)
    return nil unless rot[-2, 1] == " "   # "Lider B", nao uma palavra acabada em A
    caminho = PASTA_DIVISAO + ultima.downcase
    return nil unless (pbResolveBitmap(caminho) rescue nil)
    caminho
  rescue
    nil
  end

  def instalar!
    return if @instalado
    return unless defined?(PokemonTrainerCard_Scene)
    @instalado = true

    PokemonTrainerCard_Scene.class_eval do
      unless method_defined?(:anil_cartao_orig_pbDrawTrainerCardFront)
        alias_method :anil_cartao_orig_pbDrawTrainerCardFront, :pbDrawTrainerCardFront

        def pbDrawTrainerCardFront
          anil_cartao_orig_pbDrawTrainerCardFront
          ov = @sprites && @sprites["overlay"] && @sprites["overlay"].bitmap
          return unless ov
          base   = Color.new(72, 72, 72)
          sombra = Color.new(160, 160, 160)
          dy     = AnilCartaoRank::DESLOCAMENTO_Y

          # --- a linha PONTOS ---
          #
          # Apaga-se so o numero (a direita) e reescreve-se. O rotulo "PONTOS"
          # fica onde esta: ele ja serve para o ranqueado tambem.
          if defined?(AnilRanqueado) && !AnilRanqueado.rotulo.empty?
            y = 118 + 32
            ov.fill_rect(180, y - 2, 130, 30, Color.new(0, 0, 0, 0))
            pbDrawTextPositions(ov, [
              [AnilRanqueado.pontos.to_s, 302 + 2, y + dy, 1, base, sombra]
            ])
          end

          # --- o emblema, com a letra da divisao por baixo ---
          cam = AnilCartaoRank.caminho_do_emblema
          if cam
            x, y = AnilCartaoRank::POSICAO_EMBLEMA
            imagens = [[cam, x, y]]
            letra = AnilCartaoRank.caminho_da_divisao
            if letra
              imagens << [letra,
                          x + AnilCartaoRank::LETRA_DX,
                          y + AnilCartaoRank::LETRA_DY]
            end
            pbDrawImagePositions(ov, imagens)
          end

          # --- o boneco sai da frente ---
          #
          # Move-se o SPRITE, nao se redesenha nada: o plugin ja o colocou, e
          # mexer no x dele e a forma mais barata de abrir espaco. Guarda-se a
          # marca para nao empurrar duas vezes se o desenho repetir.
          spr = @sprites && @sprites["trainer"]
          if cam && spr && !spr.disposed? && !spr.instance_variable_get(:@anil_rank_movido)
            spr.x += AnilCartaoRank::DESLOCAMENTO_TREINADOR_X
            spr.instance_variable_set(:@anil_rank_movido, true)
          end
        rescue => e
          AnilLanRework.log("[CARTAO] falha ao desenhar o rank: #{e.class}: #{e.message}") rescue nil
        end
      end
    end
    AnilLanRework.log("148_Cartao_Rank instalado") rescue nil
  rescue => e
    AnilLanRework.log("[CARTAO] falha ao instalar: #{e.class}: #{e.message}") rescue nil
  end
end

if defined?(AnilLanRework)
  module AnilLanRework
    class << self
      if !method_defined?(:anil_cartao_orig_apply_post_plugin_patches)
        alias_method :anil_cartao_orig_apply_post_plugin_patches, :apply_post_plugin_patches rescue nil
      end

      def apply_post_plugin_patches
        anil_cartao_orig_apply_post_plugin_patches if respond_to?(:anil_cartao_orig_apply_post_plugin_patches)
        AnilCartaoRank.instalar!
      end
    end
  end
end

AnilLanRework.log("148_Cartao_Rank carregado") rescue nil
