# encoding: utf-8
#===============================================================================
# OS BONECOS RESPIRAM — E RESPIRAM PELO PEITO
#
# ⚠️ DUAS TENTATIVAS FALHADAS, E O QUE CADA UMA ENSINOU.
#
# 1ª — zoom no sprite inteiro, continuo (0,022). Suave na conta, tremido no
#      ecra: o `mkxp.json` tem o `smoothScaling` desligado, portanto a escala e
#      por vizinho mais proximo. Num boneco de 32 px, 1,022 da 32,7 -> o
#      renderizador arruma para 33, e a onda passa a vida a atravessar essa
#      fronteira. Nao se via respiracao, via-se uma linha de pixeis a piscar.
#
# 2ª — o mesmo, mas em degraus de um pixel inteiro. Acabou o tremido e ficou um
#      corte seco: o boneco TODO salta um pixel de uma vez, o que le-se como um
#      soluço e nao como um folego.
#
# O que as duas tem em comum, e que e o erro de fundo: elas escalam o BONECO
# INTEIRO. Numa escala uniforme em volta dos pes, a cabeca move-se o DOBRO do
# peito — ela esta ao dobro da distancia do pivo. Ou seja, as duas versoes
# faziam a cabeca subir mais do que o peito, que e o contrario de respirar.
#
# ⚠️ A SAIDA: SO O TRONCO E QUE ESTICA.
#
# Nao ha maneira de esticar metade de um sprite com um sprite so. Ha com dois —
# e este ficheiro (0067_Sprite_Character) ja usa esse padrao no
# `@anil_moonlight_sprite`, que duplica o boneco para o clarao da lua.
#
# Faz-se igual: um segundo sprite que mostra APENAS as linhas abaixo da cabeca,
# assente nos pes, esticado para cima. Como ele e maior do que o pedaco que
# tapa, cobre-o por inteiro; e como so estica na vertical, os lados continuam
# alinhados e nao ha costura. O unico sitio onde se ve diferenca e no ombro, a
# subir contra um pescoco que nao se mexe — que e exactamente o gesto.
#
# E aqui a escala pode voltar a ser CONTINUA, que era a que ficava melhor: o
# degrau do pixel agora acontece num tronco de ~19 px em vez de no boneco todo,
# e mexe um pixel no peito em vez de levantar a cabeca.
#
# ⚠️ E ISTO NAO TOCA EM NENHUM BITMAP.
#
# Mexer em cor ou tom de um `AnimatedBitmap` contamina a `RPG::Cache`
# partilhada e escapa para o jogo inteiro — ja aconteceu neste projecto. O
# segundo sprite aponta para o MESMO bitmap sem lhe tocar; o que muda e o
# `src_rect` e o `zoom_y`, que sao do sprite.
#===============================================================================
module AnilRespiracao
  # Pôr a `false` desliga tudo, sem tirar os ganchos.
  LIGADO = true

  # ⚠️ ONDE ACABA A CABECA.
  #
  # Fraccao da altura do quadro, a contar de cima. Nos charsets deste jogo a
  # cabeca e os ombros ocupam pouco menos de metade; 0,42 apanha o pescoco sem
  # comer o ombro, que e onde o movimento tem de comecar.
  CABECA      = 0.42

  # Quanto o tronco estica, em fraccao da altura DELE (nao do boneco).
  # Num boneco de 32 o tronco tem ~19 px, portanto isto da pouco menos de um
  # pixel — o suficiente para se sentir, pouco para distrair.
  AMPLITUDE   = 0.05

  # Uma respiracao a cada ~2,6 segundos. O reflexo da agua usa 1 Hz porque a
  # agua mexe depressa; um bicho parado nao.
  RITMO       = 0.38

  # ⚠️ TODOS A RESPIRAR AO MESMO TEMPO LE-SE COMO UM SCRIPT, NAO COMO VIDA.
  #
  # A fase sai do `object_id`: estavel para o mesmo sprite, diferente entre
  # sprites, e nao precisa de guardar nada.
  def self.fase(sprite)
    ((sprite.object_id >> 3) % 1000) / 1000.0 * Math::PI * 2.0
  rescue
    0.0
  end

  # ⚠️ QUEM RESPIRA: GENTE. NAO POKEMON, NAO OBJECTOS.
  #
  # Um Pokemon ja tem animacao propria e somar respiracao da-lhe dois ritmos ao
  # mesmo tempo. E um mapa esta cheio de `Game_Event` que sao cenario: item
  # balls, pedras de Rock Smash, arbustos de Cut.
  FORA = /^Followers\/|^Followers shiny\/|ItemBall|^Object|Boulder|Rock|Cut|Tree|Headbutt|Smash/i

  def self.respira?(character)
    return false unless character
    return false if defined?(Game_Follower) && character.is_a?(Game_Follower)
    return false if defined?(Game_FollowingPkmn) && character.is_a?(Game_FollowingPkmn)
    return false if defined?(Game_PokeEvent) && character.is_a?(Game_PokeEvent)
    nome = (character.character_name.to_s rescue "")
    return false if nome.empty?
    return false if nome =~ FORA
    return true if character == $game_player
    return true if (character.instance_variable_get(:@anil_outro_jogador) ? true : false)
    return true if defined?(Game_Event) && character.is_a?(Game_Event)
    false
  rescue
    false
  end

  # O factor de esticao de agora: 1,0 em repouso, ate 1+AMPLITUDE no cimo da
  # inspiracao. So a metade de cima da onda levanta — um bicho parado nao
  # encolhe abaixo do tamanho dele.
  def self.folego(sprite)
    t = (System.uptime rescue (Graphics.frame_count / 60.0))
    onda = Math.sin((2 * Math::PI * RITMO * t) + fase(sprite))
    return 1.0 if onda <= 0.0
    1.0 + (onda * AMPLITUDE)
  rescue
    1.0
  end
end

#-------------------------------------------------------------------------------
class Sprite_Character
  unless method_defined?(:anil_respira_orig_update) ||
         private_method_defined?(:anil_respira_orig_update)

    alias_method :anil_respira_orig_update, :update

    def update(*args)
      anil_respira_orig_update(*args)
      (anil_respirar! rescue nil)
    end

    def anil_largar_peito!
      if @anil_peito
        (@anil_peito.dispose rescue nil) unless (@anil_peito.disposed? rescue true)
        @anil_peito = nil
      end
    rescue
      @anil_peito = nil
    end

    def anil_respirar!
      unless AnilRespiracao::LIGADO && @character &&
             AnilRespiracao.respira?(@character) &&
             self.visible && self.bitmap && !(self.bitmap.disposed? rescue true)
        return anil_largar_peito!
      end
      # A parar. Quem anda ja tem a animacao das pernas a dar-lhe vida, e somar
      # respiracao por cima faz o passo parecer a coxear.
      if (@character.moving? rescue false) || (@character.jumping? rescue false)
        return anil_largar_peito!
      end

      alt = (self.src_rect.height rescue 0).to_i
      larg = (self.src_rect.width rescue 0).to_i
      return anil_largar_peito! if alt < 16 || larg <= 0

      corte = (alt * AnilRespiracao::CABECA).round
      tronco = alt - corte
      return anil_largar_peito! if tronco < 6

      if @anil_peito.nil? || (@anil_peito.disposed? rescue true)
        @anil_peito = Sprite.new(self.viewport)
      end
      sp = @anil_peito
      sp.bitmap = self.bitmap
      # ⚠️ SO AS LINHAS ABAIXO DA CABECA.
      sp.src_rect.set((self.src_rect.x rescue 0),
                      (self.src_rect.y rescue 0) + corte, larg, tronco)
      # Assente no proprio pe, para que esticar o empurre para CIMA e nao para
      # dentro do chao.
      sp.ox = larg / 2
      sp.oy = tronco
      sp.x = self.x
      sp.y = self.y
      sp.z = self.z + 1
      sp.zoom_x = self.zoom_x
      sp.zoom_y = self.zoom_y * AnilRespiracao.folego(self)
      sp.opacity = self.opacity
      sp.visible = self.visible
      sp.blend_type = self.blend_type
      # A tinta do dia/noite e a cor (o brilho de shiny, o flash de dano) tem de
      # vir com ele: sem isto o tronco ficava aceso a noite, colado a uma cabeca
      # escura.
      (sp.tone.set(self.tone.red, self.tone.green, self.tone.blue, self.tone.gray) rescue nil)
      (sp.color.set(self.color.red, self.color.green, self.color.blue, self.color.alpha) rescue nil)
    rescue
      anil_largar_peito!
    end
  end

  # ⚠️ UM SPRITE A MAIS POR BONECO TEM DE MORRER COM ELE.
  #
  # Sem isto fica um tronco solto no ecra a cada mudanca de mapa — e o mesmo
  # defeito dos sprites esquecidos que ja se caçou na arena.
  unless method_defined?(:anil_respira_orig_dispose) ||
         private_method_defined?(:anil_respira_orig_dispose)
    alias_method :anil_respira_orig_dispose, :dispose
    def dispose
      (anil_largar_peito! rescue nil)
      anil_respira_orig_dispose
    end
  end
end
