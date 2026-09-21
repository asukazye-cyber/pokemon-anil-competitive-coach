# encoding: UTF-8
#===============================================================================
# MOD: 173_Horda_Captura
#-------------------------------------------------------------------------------
# Permite atirar Pokebolas numa horda. Nas outras batalhas de mais de um, a
# regra do motor fica exactamente como estava.
#
# ⚠️ O MOTOR DE CAPTURA JA SUPORTA ISTO. SO A PORTA ESTAVA FECHADA.
#
# Ao capturar, o `pbThrowPokeBall` faz:
#
#     pbRemoveFromParty(battler.index, battler.pokemonIndex)
#     battler.pbReset
#     if pbAllFainted?(battler.index)
#       @decision = 4                      # so AQUI e que a batalha acaba
#     end
#
# Ou seja: capturar um de tres deixa os outros dois de pe e a batalha continua
# sozinha, com eles a atacar no turno seguinte. Nao e um caso especial — e como
# as batalhas duplas sempre funcionaram.
#
# O que impedia era so isto, no Item_BattleEffects (e repetido pelo plugin
# Challenge Modes, que e a versao que estava a disparar):
#
#     if battle.pbOpposingBattlerCount > 1
#       "E impossivel mirar quando ha mais de um Pokemon!"
#       next false
#
# ⚠️ A REGRA NAO SE APAGA: RE-REGISTA-SE.
#
# O `addIf` guarda por chave (`@add_ifs[sym] = [...]`), portanto registar
# `:poke_balls` outra vez substitui o anterior em vez de acumular. Tem de ser
# DEPOIS dos plugins, senao o Challenge Modes volta a por a dele por cima.
#
# ⚠️ E SO PARA HORDAS.
#
# Numa batalha dupla normal a regra continua a valer. Abrir isto para tudo
# mudaria o jogo inteiro sem ninguem ter pedido — e a horda e que foi desenhada
# para permitir apanhar mais do que um.
#===============================================================================

module AnilHordaCaptura
  ACTIVO = true

  module_function

  def log(t)
    AnilHordaDatabox.log("[captura] #{t}") rescue nil
  end

  # ⚠️ Pergunta-se aos INIMIGOS, e nao ao estado do perfume.
  #
  # A batalha pode ter comecado ha um minuto e o perfume ja ter acabado. O que
  # define uma horda a esta altura e o que esta do outro lado: um dos batalhadores
  # veio marcado do spawn.
  def horda_a_decorrer?(battle)
    return false unless ACTIVO && battle
    return false unless (battle.wildBattle? rescue false)
    (battle.allOtherSideBattlers(0) rescue []).any? do |b|
      AnilHorda.horda?(b.pokemon) rescue false
    end
  rescue
    false
  end

  def instalar!
    # ⚠️ REGISTAR ANTES DE QUALQUER SAIDA.
    #
    # A primeira versao saia em silencio se o ItemHandlers nao existisse — sem
    # sucesso e sem falha. Quando o log ficou vazio, isso tanto podia querer
    # dizer "saiu ali" como "o build nem chegou ao aparelho", e as duas coisas
    # pedem accoes opostas. Uma linha no inicio distingue-as.
    log("instalar! chamado")
    unless defined?(ItemHandlers::CanUseInBattle)
      log("  ItemHandlers::CanUseInBattle nao existe — nada re-registado")
      return false
    end
    ItemHandlers::CanUseInBattle.addIf(:poke_balls,
      proc { |item| GameData::Item.get(item).is_poke_ball? },
      proc { |item, _pokemon, _battler, _move, firstAction, battle, scene, showMessages|
        proximo = true
        if !firstAction
          scene.pbDisplay(_INTL("Ya has usado un objeto en este turno.")) if showMessages
          proximo = false
        elsif (battle.trainerBattle? rescue false) &&
              !(GameData::Item.get(item).is_snag_ball? rescue false)
          scene.pbDisplay(_INTL("¡No puedes robar los Pokémon de otros Entrenadores!")) if showMessages
          proximo = false
        elsif (battle.pbOpposingBattlerCount > 1 rescue false) &&
              !horda_a_decorrer?(battle)
          # A regra original, palavra por palavra — so deixa de valer na horda.
          if (battle.pbOpposingBattlerCount == 2 rescue false)
            scene.pbDisplay(_INTL("¡Es imposible apuntar cuando hay dos Pokémon!")) if showMessages
          elsif showMessages
            scene.pbDisplay(_INTL("¡Es imposible apuntar cuando hay más de un Pokémon!"))
          end
          proximo = false
        end
        next proximo
      }
    )
    log("regra das Pokebolas re-registada (hordas permitidas)")
    true
  rescue => e
    log("falha ao instalar: #{e.class}: #{e.message}")
    false
  end
end

module AnilLanRework
  class << self
    unless method_defined?(:anil_hcap_orig_apply_post_plugin_patches)
      alias_method :anil_hcap_orig_apply_post_plugin_patches, :apply_post_plugin_patches rescue nil
    end

    def apply_post_plugin_patches
      anil_hcap_orig_apply_post_plugin_patches rescue nil
      AnilHordaCaptura.instalar! rescue nil
    end
  end
end
