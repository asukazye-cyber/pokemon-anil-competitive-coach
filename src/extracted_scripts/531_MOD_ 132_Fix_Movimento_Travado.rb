#===============================================================================
# MOD: 132_Fix_Movimento_Travado.rb
#-------------------------------------------------------------------------------
# O jogador congela por completo: nao anda, nao abre o menu, nao fala com
# ninguem. Aparece sobretudo em contas novas, no meio da introducao.
#
#-------------------------------------------------------------------------------
# O MECANISMO
#
# `Game_Character#moving?` NAO olha para as coordenadas — devolve apenas
# `!@move_timer.nil?` (0049_Game_Character:348). E quem poe o `@move_timer` a
# nil e so o fim do movimento, em `update_move`:
#
#     if moving? && @move_timer >= @move_time &&
#        @real_x == @x * REAL_RES_X && @real_y == @y * REAL_RES_Y
#       @move_timer = nil
#
# Ou seja, o movimento so termina quando `real` bate certo com `x * 128`. Mas o
# `real_x` so e corrigido pelo lerp de cima:
#
#     if @x != @move_initial_x
#       @real_x = lerp(@move_initial_x, @x, ...) * REAL_RES_X
#
# — que **so corre quando o eixo mudou de casa**. Se `real_x` estiver
# dessincronizado e o passo actual for so vertical (`@x == @move_initial_x`),
# ninguem toca no `real_x`, a condicao de fim nunca fecha, o `@move_timer`
# cresce para sempre e `moving?` fica preso em `true`. Com `moving?` sempre
# true, o `Game_Player` ignora o input: o jogo esta vivo, o boneco e que nunca
# mais aceita um comando.
#
#-------------------------------------------------------------------------------
# DE ONDE VEM A DESSINCRONIZACAO: o `moveto`
#
# `Game_Character#moveto` (0049:376) poe x, y, real_x e real_y — mas **nao
# encerra o movimento que estava a decorrer**: deixa `@move_timer`,
# `@move_initial_x` e `@move_initial_y` do passo antigo. No frame seguinte o
# `update_move` volta a correr com esses restos e reescreve o `real_x` que o
# `moveto` tinha acabado de acertar, com a coordenada ANTIGA.
#
# Reconstruido do save do "Paul2" (13.rxdata), que ficou preso na Casa:
#
#   1. a andar por x=29: @move_initial_x=29, @move_timer=0.0
#   2. no mesmo frame o lerp devolve `start_val` (delta<=0) -> real_x = 29*128
#   3. um teleporte da introducao chama moveto(10,9): x=10, real_x=1280,
#      camera centrada em 10  — mas @move_timer e @move_initial_x=29 sobrevivem
#   4. update_move: 10 != 29 -> lerp(29,10,...) com timer quase 0 -> real_x
#      volta a 3712
#   5. o jogador da UM passo para cima: @move_initial_x = @x = 10
#      -> o ramo horizontal nunca mais corre; real_x fica em 3712 (x=29) e
#         @x em 10. FIM: `moving?` = true para sempre.
#
# O save confirma passo a passo: x=10 real_x=3712, y=9 real_y=1152 (certo),
# move_initial=(10,10), move_timer=204.9s para um move_time de 0.18s, e o
# display do mapa em 320/448 = exactamente `center(10,9)`.
#
# O proprio Essentials ja sabe disto: `Game_Follower#end_movement`
# (0053:115) existe so para "cessar todo o movimento imediatamente... quando o
# lider quer andar outra casa mas este ainda nao acabou o passo anterior" e
# limpa `@move_timer`/`@jump_timer`. Falta o mesmo no `moveto` do pai.
#
# Porque calha sobretudo a iniciantes: a introducao e onde ha mais teleportes
# automaticos encadeados (Intro Oak -> Laboratorio -> Casa), que e precisamente
# a condicao do passo 3.
#
#-------------------------------------------------------------------------------
# A CORRECCAO — duas camadas
#
# 1. RAIZ: `moveto` passa a encerrar o movimento em curso, como o
#    `end_movement` do seguidor. Mata a causa.
#
# 2. REDE DE SEGURANCA: se ainda assim um `@move_timer` passar do tempo
#    previsto do passo com folga larga, forca-se o snap e encerra-se. Isto
#    **desfaz sozinho os saves que ja estao presos**, ao primeiro frame, sem
#    ninguem ter de editar ficheiro nenhum — e cobre qualquer outra origem que
#    ainda nao conhecamos.
#
# A camada 2 grava uma linha em Data/anil_movimento_travado.txt sempre que
# dispara, com o contexto todo, para se descobrir a origem caso reapareca.
# E um ficheiro proprio de proposito: os logs globais nao se ligam, ver
# a nota sobre $ENABLE_DEBUG_LOGS.
#===============================================================================

module AnilFixMovimentoTravado
  # Folga por cima do tempo previsto do passo. Um passo normal a velocidade 3.5
  # demora 0,18 s; um evento lento nao passa de ~1 s. Um segundo inteiro de
  # margem nunca apanha movimento legitimo.
  FOLGA_SEGUNDOS = 1.0

  LOG = "Data/anil_movimento_travado.txt"
  MAX_LINHAS_LOG = 200

  class << self
    def registar(personagem, previsto)
      @linhas ||= 0
      return if @linhas >= MAX_LINHAS_LOG
      @linhas += 1
      quem = case personagem
             when Game_Player then "jogador"
             else "#{personagem.class}##{(personagem.id rescue '?')}"
             end
      File.open(LOG, "a") do |f|
        f.puts("[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] #{quem} " \
               "mapa=#{($game_map.map_id rescue '?')} " \
               "x=#{personagem.x} y=#{personagem.y} " \
               "real=(#{personagem.real_x},#{personagem.real_y}) " \
               "esperado=(#{personagem.x * Game_Map::REAL_RES_X}," \
               "#{personagem.y * Game_Map::REAL_RES_Y}) " \
               "inicial=(#{personagem.instance_variable_get(:@move_initial_x)}," \
               "#{personagem.instance_variable_get(:@move_initial_y)}) " \
               "timer=#{personagem.instance_variable_get(:@move_timer)} " \
               "previsto=#{previsto.round(3)}")
      end
    rescue
    end
  end
end

class Game_Character
  #-----------------------------------------------------------------------------
  # 1. RAIZ — teleportar encerra o passo que estava a decorrer.
  #
  # Sem isto, o lerp do passo antigo corre no frame seguinte e desfaz o
  # real_x/real_y que o moveto acabou de acertar.
  #-----------------------------------------------------------------------------
  unless method_defined?(:anil_fixmov_orig_moveto)
    alias anil_fixmov_orig_moveto moveto

    def moveto(*args)
      resultado = anil_fixmov_orig_moveto(*args)
      @move_timer      = nil
      @jump_timer      = nil
      @move_initial_x  = @x
      @move_initial_y  = @y
      @jump_initial_x  = @x if instance_variable_defined?(:@jump_initial_x)
      @jump_initial_y  = @y if instance_variable_defined?(:@jump_initial_y)
      @jump_peak       = 0
      @jump_distance   = 0
      @jump_fraction   = 0
      @jumping_on_spot = false
      @bumping         = false
      resultado
    end
  end

  #-----------------------------------------------------------------------------
  # 2. REDE DE SEGURANCA — nenhum passo pode durar para sempre.
  #
  # Corre DEPOIS do update_move original, portanto so age sobre um movimento
  # que ele proprio ja devia ter encerrado.
  #-----------------------------------------------------------------------------
  unless method_defined?(:anil_fixmov_orig_update_move)
    alias anil_fixmov_orig_update_move update_move

    def update_move
      anil_fixmov_orig_update_move
      return unless @move_timer

      # Tempo previsto para este passo, pela mesma conta do update_move.
      dist = [(@move_initial_x.to_i - @x).abs, (@move_initial_y.to_i - @y).abs, 1].max
      previsto = @move_time.to_f * dist
      return if @move_timer < previsto + AnilFixMovimentoTravado::FOLGA_SEGUNDOS

      AnilFixMovimentoTravado.registar(self, previsto)

      @real_x          = @x * Game_Map::REAL_RES_X
      @real_y          = @y * Game_Map::REAL_RES_Y
      @move_initial_x  = @x
      @move_initial_y  = @y
      @move_timer      = nil
      @bumping         = false
    rescue
      # Nunca deixar este remendo rebentar o update do mapa.
      @move_timer = nil
    end
  end
end
