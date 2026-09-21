# encoding: UTF-8
#===============================================================================
# MOD: 164_Fix_Ordem_Equipa_Batalha
#-------------------------------------------------------------------------------
# Apanhar um Pokemon a meio de uma batalha e depois abrir o ecra da equipa
# deixava de rebentar.
#
# ⚠️ A EQUIPA CRESCE, A ORDEM DE EXIBICAO NAO.
#
# O Battle#initialize (0150_Battle, linha 134) faz:
#
#     @party1      = p1                                  # a MESMA lista do jogador
#     @party1order = Array.new(@party1.length) { |i| i }  # uma copia do tamanho
#
# O `@party1` nao e uma copia: e o proprio `$player.party`. E o
# 0230_Battle_CatchAndStoreMixin, ao guardar uma captura, faz
# `pbPlayer.party << pkmn`. A equipa passa a ter mais um; a ordem fica com os
# de antes.
#
# A partir dai, qualquer ecra de equipa NESSA batalha estoira:
#
#     ret[partyOrders[i] - idxStart] = pkmn
#     NoMethodError: undefined method `-' for nil:NilClass
#
# porque o `partyOrders[i]` do slot novo nao existe. E o rasto que apareceu:
#
#     0150_Battle:369 pbPlayerDisplayParty
#     0150_Battle:447 eachInTeamFromBattlerIndex
#     0192_Scene_ChooseCommands:146 pbPartyScreen
#     0154_Battle_ActionSwitching:123 pbSwitchInBetween
#
# Para acontecer, a batalha tem de CONTINUAR depois da captura — batalha dupla,
# ou horda. Apanha-se um, o outro derruba o nosso (ou usa um golpe de troca), o
# jogo pede o substituto, e o ecra da equipa rebenta. A especie nao tem nada a
# ver com isto; o Mamoswine era so quem la estava.
#
# ⚠️ CORRIGE-SE NO GARGALO, E NAO EM CADA CHAMADOR.
#
# Ha nove sitios a ler a ordem (Battle, StartAndEnd, ActionSwitching,
# Scene_ChooseCommands, e a mochila com equipa interactiva), e TODOS passam pelo
# pbPartyOrder. Emendar aqui cobre-os a todos, e cobre tambem qualquer outra
# forma de a equipa crescer que ainda nao conhecamos.
#
# O que se acrescenta e exactamente o que o initialize teria posto: o indice
# igual a si proprio. O Pokemon apanhado entra no fim da equipa e no fim da
# ordem, que e onde o jogador espera ve-lo.
#===============================================================================

module AnilOrdemEquipa
  ACTIVO = true

  class << self
    def log(t)
      AnilLanRework.log("[ORDEM] #{t}") rescue nil
    end

    def instalar!
      return false unless ACTIVO
      return false unless defined?(Battle)
      return false if Battle.method_defined?(:anil_ordem_orig_pbPartyOrder)
      Battle.class_eval do
        alias_method :anil_ordem_orig_pbPartyOrder, :pbPartyOrder

        def pbPartyOrder(idxBattler)
          ordem = anil_ordem_orig_pbPartyOrder(idxBattler)
          equipa = (opposes?(idxBattler) ? @party2 : @party1)
          if ordem.is_a?(Array) && equipa.is_a?(Array) && ordem.length < equipa.length
            # ⚠️ Escreve-se NA lista devolvida, de proposito.
            #
            # Ela e o proprio @party1order/@party2order. Devolver uma copia
            # corrigida deixava o original curto e o proximo ecra rebentava na
            # mesma — e ha quem guarde a referencia.
            (ordem.length...equipa.length).each { |i| ordem[i] = i }
            AnilOrdemEquipa.log("ordem esticada para #{equipa.length} (equipa cresceu durante a batalha)")
          end
          ordem
        rescue
          anil_ordem_orig_pbPartyOrder(idxBattler)
        end
      end
      log("enxerto instalado no pbPartyOrder")
      true
    rescue => e
      log("falha a instalar: #{e.class}: #{e.message}")
      false
    end
  end
end

module AnilLanRework
  class << self
    unless method_defined?(:anil_ordem_orig_apply_post_plugin_patches)
      alias_method :anil_ordem_orig_apply_post_plugin_patches, :apply_post_plugin_patches rescue nil
    end

    def apply_post_plugin_patches
      anil_ordem_orig_apply_post_plugin_patches rescue nil
      AnilOrdemEquipa.instalar! rescue nil
    end
  end
end
