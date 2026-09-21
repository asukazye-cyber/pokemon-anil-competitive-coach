# encoding: UTF-8
#===============================================================================
# MOD: 142_Neve_Opacidade
#-------------------------------------------------------------------------------
# Faz cada floco NASCER e MORRER em opacidade, em vez de aparecer e sumir seco.
#
# Antes, o motor punha `sprite.opacity = 255` no reset e nunca mais mexia — para
# a neve o particle_delta_opacity e 0. Todos os flocos estavam sempre a 100%, e
# apareciam/desapareciam de repente.
#
# ⚠️ A ARMADILHA DO 64
#
# No fim do update_sprite_position original (0256_Overworld_Weather.rb) esta:
#
#     if sprite.opacity < 64 || x < -sprite.bitmap.width || y > Graphics.height
#       reset_sprite_position(sprite, index, is_new_sprite)
#     end
#
# Ou seja, o motor destroi qualquer particula abaixo de 64 de opacidade — ele usa
# isso como sinal de "acabou". Uma entrada suave a partir do zero seria morta no
# frame seguinte, e o floco nunca chegaria a aparecer.
#
# A saida NAO e limitar o fade a 64 (isso daria um salto visivel). E neutralizar
# o teste: poe-se 255 ANTES de chamar o original — o teste de opacidade nunca
# dispara, e continuam a valer os de fora do ecra, que sao os que interessam — e
# so depois se escreve a opacidade verdadeira. Assim da para descer ate 0.
#
# COMO A CURVA E CALCULADA
#
# O motor guarda o tempo RESTANTE de cada particula (@sprite_lifetimes), nunca o
# total, entao nao da para saber em que ponto da vida ela esta. Guarda-se o total
# no reset e a fraccao sai de (total - restante) / total.
#
# Os tres numeros abaixo sao os botoes para afinar depois do teste.
#===============================================================================

module RPG
  class Weather
    # Opacidade no auge. 178 = 70% de 255.
    ANIL_NEVE_PICO = 178

    # Fatia inicial da vida a nascer, e fatia final a desaparecer.
    # A entrada e curta de proposito: a particula nasce FORA do ecra (o
    # reset_sprite_position poe-na a direita ou acima), portanto uma entrada
    # longa seria gasta onde ninguem ve. A saida e longa porque essa sim
    # acontece com o floco em cena.
    ANIL_NEVE_ENTRADA = 0.12
    ANIL_NEVE_SAIDA   = 0.35

    # So a neve. O granizo, a chuva e a tempestade de areia ficam como estao.
    ANIL_NEVE_TIPOS = [:Snow, :Blizzard]

    if !method_defined?(:anil_neve_orig_reset_sprite_position)
      alias anil_neve_orig_reset_sprite_position reset_sprite_position
    end
    if !method_defined?(:anil_neve_orig_update_sprite_position)
      alias anil_neve_orig_update_sprite_position update_sprite_position
    end

    def anil_neve_tipo?(is_new_sprite)
      ANIL_NEVE_TIPOS.include?(is_new_sprite ? @target_type : @type)
    rescue
      false
    end

    def anil_neve_totais(is_new_sprite)
      if is_new_sprite
        @anil_neve_totais_novos ||= []
      else
        @anil_neve_totais_atuais ||= []
      end
    end

    def reset_sprite_position(sprite, index, is_new_sprite = false)
      anil_neve_orig_reset_sprite_position(sprite, index, is_new_sprite)

      # ⚠️ Grava-se o total em TODO reset, mesmo quando o clima nao e neve.
      #
      # Gravar so para a neve parecia economico e estava errado. O clima dinamico
      # (MOD 047) troca de tipo em jogo; enquanto esta chuva, as particulas
      # continuam a ser recicladas mas o total nao era actualizado. Ao voltar a
      # neve, o total guardado era de uma vida ANTERIOR — tipicamente muito mais
      # longa — e a fraccao dava logo perto do fim: o floco nascia com ~20% de
      # opacidade e ia apagando, em vez de brilhar. Era a neve que "caia uns
      # segundos e sumia".
      #
      # Gravar sempre custa uma atribuicao por reset e mantem os dois vectores
      # sincronizados por construcao, seja qual for o clima.
      vidas = is_new_sprite ? @new_sprite_lifetimes : @sprite_lifetimes
      anil_neve_totais(is_new_sprite)[index] = vidas[index].to_f

      sprite.opacity = 0 if sprite && anil_neve_tipo?(is_new_sprite)   # nasce invisivel
    rescue
    end

    def update_sprite_position(sprite, index, is_new_sprite = false)
      neve = sprite && anil_neve_tipo?(is_new_sprite)
      # Ver "A ARMADILHA DO 64" no cabecalho: sem isto o motor mata o floco
      # assim que a opacidade real desce, e o fade nunca se ve.
      opacidade_real = sprite.opacity if neve
      sprite.opacity = 255 if neve

      anil_neve_orig_update_sprite_position(sprite, index, is_new_sprite)

      return unless neve
      return if !sprite.visible || !sprite.bitmap

      totais = anil_neve_totais(is_new_sprite)
      restante = (is_new_sprite ? @new_sprite_lifetimes : @sprite_lifetimes)[index].to_f
      total = totais[index].to_f

      # ⚠️ AUTO-CORRECAO DO TOTAL — nao tirar.
      #
      # O total so e gravado no reset, e so quando o clima ja e neve. Se o clima
      # mudar para outro tipo e voltar (o clima dinamico do MOD 047 faz isso), o
      # total guardado e de uma vida ANTERIOR e nao tem relacao com o restante
      # atual. Quando o total velho e maior, a fraccao da perto de 1, o fator vai
      # a zero e o floco fica INVISIVEL — e como aqui se neutraliza o teste dos
      # 64, o motor tambem nao o recicla. Resultado: a neve caia uns segundos e
      # desaparecia sem motivo aparente.
      #
      # Um total menor que o restante e impossivel numa vida coerente, entao isso
      # e a assinatura de valor velho: re-semeia-se com o restante e a particula
      # recomeca a curva a partir dali, sem esperar pelo fim da vida.
      if total <= 0 || total < restante
        total = restante
        totais[index] = total
      end
      if total <= 0
        sprite.opacity = opacidade_real || ANIL_NEVE_PICO
        return
      end

      fraccao = (total - restante) / total
      fraccao = 0.0 if fraccao < 0.0
      fraccao = 1.0 if fraccao > 1.0

      fator = if fraccao < ANIL_NEVE_ENTRADA
                fraccao / ANIL_NEVE_ENTRADA
              elsif fraccao > 1.0 - ANIL_NEVE_SAIDA
                (1.0 - fraccao) / ANIL_NEVE_SAIDA
              else
                1.0
              end
      sprite.opacity = (ANIL_NEVE_PICO * fator).round
    rescue
      # Numa duvida qualquer, deixar visivel e melhor que deixar invisivel.
      sprite.opacity = ANIL_NEVE_PICO if sprite
    end
  end
end

AnilLanRework.log("142_Neve_Opacidade carregado") rescue nil
