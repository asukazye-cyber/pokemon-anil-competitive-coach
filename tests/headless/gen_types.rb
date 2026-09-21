# encoding: UTF-8
# Generates Data/types.dat for the headless harness using the game's own
# GameData::Type class and the standard Gen 9 type chart.
#
# NOTE: The pack only shipped abilities/items/moves/species .dat files.
# types.dat is RECONSTRUCTED here from the canonical Gen 9 chart. If the real
# game's types.dat differs (custom types/interactions), differential tests
# against the real engine would surface it; the loader prefers an existing
# file, so dropping the authentic types.dat into tests/headless/Data/ wins.

# 1. Which type symbols does the game's own data actually reference?
used = []
GameData::Species.each { |s| used.concat(s.types.compact) }
GameData::Move.each { |m| used << m.type if m.type }
used.uniq!
puts "[gen_types] types referenced by game data: #{used.inspect}"
unknown = used.reject { |t| [:SHADOW, :QMARKS].include?(t) }
known = %i[NORMAL FIRE WATER GRASS ELECTRIC ICE FIGHTING POISON GROUND
           FLYING PSYCHIC BUG ROCK GHOST DRAGON DARK STEEL FAIRY]
custom = unknown - known
puts "[gen_types] CUSTOM types (not in standard 18): #{custom.inspect}"
raise "custom types present; chart needs authoring" unless custom.empty?
# Essentials pseudo-type used by e.g. the unknown "???" placeholder; neutral.
data = {}
data[:QMARKS] = GameData::Type.new(
  id: :QMARKS, real_name: "???", icon_position: 36,
  special_type: false, pseudo_type: true,
  weaknesses: [], resistances: [], immunities: [], flags: []
)

# 2. Standard Gen 9 chart as {attacker => {defender => multiplier}}
CHART = {
  NORMAL:   { ROCK: 0.5, GHOST: 0, STEEL: 0.5 },
  FIRE:     { FIRE: 0.5, WATER: 0.5, GRASS: 2, ICE: 2, BUG: 2, ROCK: 0.5, DRAGON: 0.5, STEEL: 2 },
  WATER:    { FIRE: 2, WATER: 0.5, GRASS: 0.5, GROUND: 2, ROCK: 2, DRAGON: 0.5 },
  GRASS:    { FIRE: 0.5, WATER: 2, GRASS: 0.5, POISON: 0.5, GROUND: 2, FLYING: 0.5, BUG: 0.5, ROCK: 2, DRAGON: 0.5, STEEL: 0.5 },
  ELECTRIC: { WATER: 2, GRASS: 0.5, ELECTRIC: 0.5, GROUND: 0, FLYING: 2, DRAGON: 0.5 },
  ICE:      { FIRE: 0.5, WATER: 0.5, GRASS: 2, ICE: 0.5, GROUND: 2, FLYING: 2, DRAGON: 2, STEEL: 0.5 },
  FIGHTING: { NORMAL: 2, ICE: 2, POISON: 0.5, FLYING: 0.5, PSYCHIC: 0.5, BUG: 0.5, ROCK: 2, GHOST: 0, DARK: 2, STEEL: 2, FAIRY: 0.5 },
  POISON:   { GRASS: 2, POISON: 0.5, GROUND: 0.5, ROCK: 0.5, GHOST: 0.5, STEEL: 0, FAIRY: 2 },
  GROUND:   { FIRE: 2, GRASS: 0.5, ELECTRIC: 2, POISON: 2, FLYING: 0, BUG: 0.5, ROCK: 2, STEEL: 2 },
  FLYING:   { GRASS: 2, ELECTRIC: 0.5, FIGHTING: 2, BUG: 2, ROCK: 0.5, STEEL: 0.5 },
  PSYCHIC:  { FIGHTING: 2, POISON: 2, PSYCHIC: 0.5, DARK: 0, STEEL: 0.5 },
  BUG:      { FIRE: 0.5, GRASS: 2, FIGHTING: 0.5, POISON: 0.5, FLYING: 0.5, PSYCHIC: 2, GHOST: 0.5, DARK: 2, STEEL: 0.5, FAIRY: 0.5 },
  ROCK:     { FIRE: 2, ICE: 2, FIGHTING: 0.5, GROUND: 0.5, FLYING: 2, BUG: 2, STEEL: 0.5 },
  GHOST:    { NORMAL: 0, PSYCHIC: 2, GHOST: 2, DARK: 0.5 },
  DRAGON:   { DRAGON: 2, STEEL: 0.5, FAIRY: 0 },
  DARK:     { FIGHTING: 0.5, PSYCHIC: 2, GHOST: 2, DARK: 0.5, STEEL: 0.5, FAIRY: 0.5 },
  STEEL:    { FIRE: 0.5, WATER: 0.5, ELECTRIC: 0.5, ICE: 2, ROCK: 2, STEEL: 0.5, FAIRY: 2 },
  FAIRY:    { FIRE: 0.5, FIGHTING: 2, POISON: 0.5, DRAGON: 2, DARK: 2, STEEL: 0.5 },
}.transform_keys(&:to_sym).transform_values { |h| h.transform_keys(&:to_sym) }

SPECIAL = { FIRE: true, WATER: true, GRASS: true, ELECTRIC: true, PSYCHIC: true, ICE: true, DRAGON: true, DARK: true, FAIRY: true }

# 3. Build GameData::Type instances via the game's own class.
data = {}
known.each_with_index do |t, i|
  weak = CHART.select { |_atk, defs| (defs[t] || 1) > 1 }.keys
  res  = CHART.select { |_atk, defs| (defs[t] || 1) < 1 && (defs[t] || 1) > 0 }.keys
  imm  = CHART.select { |_atk, defs| (defs[t] || 1) == 0 }.keys
  data[t] = GameData::Type.new(
    id: t, real_name: t.to_s.capitalize, icon_position: i * 2,
    special_type: SPECIAL[t] || false, pseudo_type: false,
    weaknesses: weak, resistances: res, immunities: imm, flags: []
  )
end

path = "/work/Data/types.dat"
File.binwrite(path, Marshal.dump(data))
puts "[gen_types] wrote #{path} with #{data.size} types"

# 4. Reload and sanity check via the game's Effectiveness module.
GameData::Type.load
puts "[gen_types] Effectiveness: FIRE->GRASS x#{Effectiveness.calculate(:FIRE, :GRASS)}"
puts "[gen_types] Effectiveness: GROUND->FLYING x#{Effectiveness.calculate(:GROUND, :FLYING)}"
puts "[gen_types] Effectiveness: GHOST->NORMAL x#{Effectiveness.calculate(:GHOST, :NORMAL)}"
puts "[gen_types] Effectiveness: ELECTRIC->WATER x#{Effectiveness.calculate(:ELECTRIC, :WATER)}"
raise "chart sanity failed" unless
  Effectiveness.calculate(:FIRE, :GRASS) == 2 &&
  Effectiveness.calculate(:GROUND, :FLYING) == 0 &&
  Effectiveness.calculate(:GHOST, :NORMAL) == 0 &&
  Effectiveness.calculate(:ELECTRIC, :WATER) == 2
puts "[gen_types] OK"
