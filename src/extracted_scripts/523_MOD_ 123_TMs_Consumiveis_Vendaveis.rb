#===============================================================================
# MOD: 123_TMs_Consumiveis_Vendaveis.rb
#-------------------------------------------------------------------------------
# Torna as MTs (TMs) CONSUMIVEIS e VENDAVEIS, como nas geracoes ate a 4.
#
# COMO ERA
#   O Essentials v21.1 segue a regra da 5a geracao em diante: MT e reutilizavel
#   infinitamente. Isso vem de UMA linha no 0133_Item.rb:
#
#     def is_important?
#       return true if is_key_item? || is_HM? || is_TM?    # <- a MT entra aqui
#     end
#
#   E "importante" cascateia para tudo:
#     consumed_after_use?  -> false  (nao gasta ao ensinar)
#     canSell? (PokeMart)  -> false  (nao aparece para vender)
#     show_quantity?       -> false  (bolsa nao mostra "x3")
#     bolsa "Tirar"        -> "Eso es muy importante para tirarlo!"
#
# POR QUE NAO BASTA MEXER NO is_important?
#   O @consumable de cada item ja vem GRAVADO no Data/items.dat compilado:
#
#     TM01: consumable=false field_use=3 price=5500 sell=1375
#
#   O 0133_Item.rb so calcula @consumable = !is_important? quando ele e nil, e
#   aqui ele e false explicito. Entao o consumed_after_use? continuaria falso
#   mesmo com a MT deixando de ser importante. Por isso os DOIS metodos sao
#   sobrescritos aqui — assim nao e preciso recompilar o PBS nem redistribuir o
#   items.dat (que, pelo guarda .pbs_compiled_raid_v3, regeraria todos os .dat
#   dos jogadores).
#
# O QUE MUDA NA PRATICA
#   - ensinar um movimento GASTA a MT (o codigo de consumo ja existia em
#     pbUseItemOnPokemon: "$bag.remove(item) if itm.consumed_after_use?")
#   - MT pode ser vendida na loja por 1375 (price 5500 / ITEM_SELL_PRICE_DIVISOR
#     = 4, porque MECHANICS_GENERATION = 9)
#   - a bolsa passa a mostrar a quantidade e permite empilhar e descartar
#
# O QUE NAO MUDA (de proposito)
#   - MO (HM) continua importante: nao vende, nao descarta, nao gasta
#   - MT continua NAO podendo ser equipada. Sem o can_hold? abaixo ela viraria
#     item de porte junto com o resto, e as MTs tem flag Fling_120/Fling_90 no
#     PBS — dava para arremessar MT em batalha por 120 de dano.
#===============================================================================

module GameData
  class Item
    # A MT sai da lista de "importantes". MO e item-chave continuam.
    def is_important?
      return true if is_key_item? || is_HM?
      false
    end

    # O @consumable do items.dat esta como false para MT; forcamos aqui em vez
    # de recompilar o PBS.
    def consumed_after_use?
      return true if is_TM?
      !is_important? && @consumable
    end

    # Mantem MT/MO fora dos itens equipaveis (ver comentario do cabecalho).
    def can_hold?
      return false if is_machine?
      !is_important?
    end
  end
end
