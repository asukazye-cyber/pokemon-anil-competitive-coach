#===============================================================================
# MOD: 116_Pokemon_Box_Link.rb
#-------------------------------------------------------------------------------
# Faz o Pokemon Box Link (versao Objeto Clave) ter "Usar" e "Registrar".
#
# POR QUE ELE FICAVA INERTE
# O item nunca teve handler nenhum: funcionava so de forma PASSIVA, porque
# PokemonPartyScreen#pbPokemonScreen (UI_Party) checa apenas se o jogador o
# POSSUI para liberar o acesso ao PC pela tela de equipe. Sem handler:
#
#   "Usar"      exige ItemHandlers.hasOutHandler  -> UseFromBag/UseInField/UseOnPokemon
#   "Registrar" exige ItemHandlers.hasUseInFieldHandler -> UseInField, especificamente
#
# ...entao a mochila nao mostrava nenhuma das duas e o item parecia quebrado.
#
# SAO NECESSARIOS OS DOIS HANDLERS
# Nao basta um: pbUseItem roteia por field_use, e no ramo "Direct" (2) ele chama
# triggerUseFromBag — ou seja, usar pela mochila passa por UseFromBag. Ja o
# "Registrar" so olha para UseInField. Registrar apenas UseInField mostraria o
# botao "Usar" que nao faria nada.
#
# Junto com isto, o FieldUse do item passou de vazio (0) para Direct (2) no PBS
# e no items.dat; com 0, pbUseItem cai no "Aqui no se puede usar".
#
# O item nao e consumido: consumable=false e a flag KeyItem impede o
# consumed_after_use?.
#===============================================================================

def anil_abrir_box_link
  # Mesmas restricoes que o UI_Party respeita para liberar o acesso ao PC.
  bloqueado = false
  begin
    bloqueado = true if defined?(Settings::DISABLE_BOX_LINK_SWITCH) &&
                        $game_switches[Settings::DISABLE_BOX_LINK_SWITCH]
    bloqueado = true if $game_map.metadata&.has_flag?("DisableBoxLink")
  rescue
  end
  if bloqueado
    pbMessage(_INTL("O Link do Box não funciona aqui.")) rescue nil
    return 0
  end

  # Abre o ARMAZENAMENTO direto. Mesmo trecho que o UI_Party executa quando se
  # aperta a tecla especial na tela de equipe tendo o Box Link (UI_Party.rb:828):
  # PokemonStorageScene + pbStartScreen(0), sendo 0 o modo "Organizar", que e o
  # unico que deixa mover livremente entre equipe e caixas.
  #
  # A primeira versao abria pbPokemonScreen (a tela de EQUIPE, que so habilita o
  # atalho para o PC). Funcionava, mas exigia um passo a mais do jogador — nao e
  # o que se espera de um item chamado "Box Link".
  pbFadeOutIn do
    scene  = PokemonStorageScene.new
    screen = PokemonStorageScreen.new(scene, $PokemonStorage)
    screen.pbStartScreen(0)
  end
  1
rescue => e
  AnilLanRework.log("116_Pokemon_Box_Link: #{e}") rescue nil
  0
end

if defined?(ItemHandlers)
  # Usar pela mochila.
  ItemHandlers::UseFromBag.add(:KEYPOKEMONBOXLINK, proc { |item|
    next anil_abrir_box_link
  }) rescue nil

  # Habilita o "Registrar" e o uso pela tecla depois de registrado.
  ItemHandlers::UseInField.add(:KEYPOKEMONBOXLINK, proc { |item|
    next anil_abrir_box_link
  }) rescue nil
end
