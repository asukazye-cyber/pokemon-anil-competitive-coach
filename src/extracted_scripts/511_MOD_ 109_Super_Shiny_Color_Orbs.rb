#===============================================================================
# MOD: 109_Super_Shiny_Color_Orbs.rb
#-------------------------------------------------------------------------------
# Implementação dos novos itens de Orbes que alteram a cor (hue) de Pokémon
# Super Shiny quando usados pela mochila!
#===============================================================================

SUPER_SHINY_ORBS_CONFIG = {
  :ORBEFLAMEJANTE => {
    name: "Orbe Flamejante",
    plural: "Orbes Flamejantes",
    hue: 45,
    desc: "Um orbe que brilha com tons quentes. Quando usado em um Pokémon Super Shiny, muda sua cor para Laranja/Amarelo."
  },
  :ORBEDELIMA => {
    name: "Orbe de Lima",
    plural: "Orbes de Lima",
    hue: 90,
    desc: "Um orbe que brilha com tons cítricos. Quando usado em um Pokémon Super Shiny, muda sua cor para Verde-Lima."
  },
  :ORBEDEESMERALDA => {
    name: "Orbe de Esmeralda",
    plural: "Orbes de Esmeralda",
    hue: 135,
    desc: "Um orbe que brilha com tons verdejantes. Quando usado em um Pokémon Super Shiny, muda sua cor para Esmeralda."
  },
  :ORBETURQUESA => {
    name: "Orbe Turquesa",
    plural: "Orbes Turquesa",
    hue: 180,
    desc: "Um orbe que brilha com tons celestes. Quando usado em um Pokémon Super Shiny, muda sua cor para Ciano/Turquesa."
  },
  :ORBEDESAFIRA => {
    name: "Orbe de Safira",
    plural: "Orbes de Safira",
    hue: 225,
    desc: "Um orbe que brilha com tons profundos. Quando usado em um Pokémon Super Shiny, muda sua cor para Azul Safira."
  },
  :ORBEDEAMETISTA => {
    name: "Orbe de Ametista",
    plural: "Orbes de Ametista",
    hue: 270,
    desc: "Um orbe que brilha com tons místicos. Quando usado em um Pokémon Super Shiny, muda sua cor para Violeta/Ametista."
  },
  :ORBEROSA => {
    name: "Orbe Rosa",
    plural: "Orbes Rosa",
    hue: 315,
    desc: "Um orbe que brilha com tons vibrantes. Quando usado em um Pokémon Super Shiny, muda sua cor para Rosa/Magenta."
  }
}

SUPER_SHINY_ORBS_CONFIG.each do |item_id, cfg|
  # Registrar dinamicamente no GameData::Item se ainda não existir
  if defined?(GameData::Item)
    unless GameData::Item.exists?(item_id)
      GameData::Item.register({
        :id               => item_id,
        :real_name        => cfg[:name],
        :real_name_plural => cfg[:plural],
        :pocket           => 1,
        :price            => 0,
        :field_use        => 1, # OnPokemon
        :flags            => ["Fling_30"],
        :real_description => cfg[:desc]
      })
    end
  end

  # Handler de uso no Pokémon
  ItemHandlers::UseOnPokemon.add(item_id, proc { |item, qty, pkmn, scene|
    if !pkmn.super_shiny?
      scene.pbDisplay(_INTL("Isso não terá efeito. Este item só pode ser usado em Pokémon Super Shiny!"))
      next false
    end

    current_hue = pkmn.cached_super_shiny_hue || pkmn.super_shiny_hue
    target_hue = cfg[:hue]

    if current_hue == target_hue
      scene.pbDisplay(_INTL("{1} já está com essa coloração!", pkmn.name))
      next false
    end

    pkmn.cached_super_shiny_hue = target_hue
    pbSEPlay("Pkmn healing") rescue nil
    scene.pbDisplay(_INTL("A cor de {1} mudou sob o brilho do {2}!", pkmn.name, cfg[:name]))
    scene.pbHardRefresh rescue nil
    next true
  })
end
