#===============================================================================
# MOD: 113_KeyItem_Tickets.rb (Conversor de Itens Comuns em Objetos Clave)
#-------------------------------------------------------------------------------
# Permite que itens comuns dropados das caixas (como Amuleto Íris e Pokémon Box Link)
# sejam consumidos ao clicar em "Usar", transferindo a versão Objeto Clave
# definitiva para a aba de Objetos Clave (Bolso 8).
# Se o jogador já possuir a versão Objeto Clave, o uso é recusado e o item comum
# permanece na mochila para venda nas lojas por $50.000 ou trocas no mercado.
#===============================================================================

KEY_ITEM_CONVERSIONS = {
  :SHINYCHARM     => :KEYSHINYCHARM,
  :POKEMONBOXLINK => :KEYPOKEMONBOXLINK,
  :ZYGARDECUBE    => :KEYZYGARDECUBE,
  :DNASPLICERS    => :KEYDNASPLICERS,
  :NSOLARIZER     => :KEYNSOLARIZER,
  :NLUNARIZER     => :KEYNLUNARIZER,
  :REINSOFUNITY   => :KEYREINSOFUNITY,
  :REVEALGLASS    => :KEYREVEALGLASS,
  :PRISONBOTTLE   => :KEYPRISONBOTTLE,
  :TEALMASK       => :KEYTEALMASK
}

KEY_ITEM_CONVERSIONS.each do |common_id, key_id|
  ItemHandlers::UseFromBag.add(common_id, proc { |item|
    if $bag.has?(key_id)
      name_key = GameData::Item.get(key_id).name rescue key_id.to_s
      pbMessage(_INTL("Você já possui {1} nos seus Objetos Clave! Guarde este item para negociar no mercado de jogadores ou venda-o na loja por $50.000.", name_key))
      next 0 # Não consome o item comum da mochila
    else
      $bag.add(key_id)
      name_key = GameData::Item.get(key_id).name rescue key_id.to_s
      pbMessage(_INTL("{1} foi ativado e adicionado aos seus Objetos Clave!", name_key))
      next 1 # Consome o item comum da mochila
    end
  })
end

# Handlers de efeito em Pokémon para as versões KEY... dos itens de fusão/mudança de forma
KEY_FORM_ITEMS = {
  :KEYDNASPLICERS      => :DNASPLICERS,
  :KEYDNASPLICERSUSED  => :DNASPLICERSUSED,
  :KEYNSOLARIZER       => :NSOLARIZER,
  :KEYNSOLARIZERUSED   => :NSOLARIZERUSED,
  :KEYNLUNARIZER       => :NLUNARIZER,
  :KEYNLUNARIZERUSED   => :NLUNARIZERUSED,
  :KEYREINSOFUNITY     => :REINSOFUNITY,
  :KEYREINSOFUNITYUSED => :REINSOFUNITYUSED,
  :KEYREVEALGLASS      => :REVEALGLASS,
  :KEYPRISONBOTTLE     => :PRISONBOTTLE,
  :KEYZYGARDECUBE      => :ZYGARDECUBE,
  :KEYTEALMASK         => :TEALMASK
}

KEY_FORM_ITEMS.each do |key_id, orig_id|
  ItemHandlers::UseOnPokemon.add(key_id, proc { |item, qty, pkmn, scene|
    handler = ItemHandlers::UseOnPokemon[orig_id]
    if handler
      handler.call(orig_id, qty, pkmn, scene)
    else
      next false
    end
  })
end
