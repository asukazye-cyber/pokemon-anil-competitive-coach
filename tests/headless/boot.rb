# encoding: UTF-8
#===============================================================================
# Headless boot: loads the REAL Añil/Essentials battle engine + real PBS data
# so Engine 2.0 code and tests run against genuine game rules.
#
# Layout (mounted at /work):
#   /work/src/extracted_scripts/NNN_*.rb   the game's scripts (source of truth)
#   /work/data/*.dat                       real PBS marshal data
#   /work/Data/*.dat                       same + generated types.dat (tracked)
#   /work/engine2/*.rb                     Engine 2.0 sources (loaded last)
#===============================================================================

ROOT = "/work"
HEAD = File.join(ROOT, "tests", "headless")

$LOAD_VERBOSE = true

def script_by_index(idx)
  files = Dir.glob(File.join(ROOT, "src", "extracted_scripts", "#{format('%03d', idx)}_*.rb"))
  raise "no script at index #{idx}" if files.empty?
  raise "ambiguous index #{idx}: #{files.inspect}" if files.size > 1
  files.first
end

def load_script_idx(idx)
  path = script_by_index(idx)
  code = File.read(path, mode: "rb")
  code.force_encoding("UTF-8") if code.encoding == Encoding::ASCII_8BIT
  begin
    eval(code, TOPLEVEL_BINDING, path)
  rescue ScriptError, StandardError => e
    raise $!, "#{$!.class} while loading #{File.basename(path)}: #{$!.message}", $!.backtrace
  end
  puts "[boot] loaded #{File.basename(path)}" if $LOAD_VERBOSE
end

def load_engine2
  Dir.glob(File.join(ROOT, "engine2", "*.rb")).sort.each do |path|
    eval(File.read(path, mode: "rb"), TOPLEVEL_BINDING, path)
    puts "[boot] loaded engine2/#{File.basename(path)}" if $LOAD_VERBOSE
  end
end

# --- 1. stubs -----------------------------------------------------------------
require File.join(HEAD, "stubs.rb")

# --- 2. settings / utilities (in original load order) --------------------------
[
  3,    # 0001 ____Settings___ (section header)
  4,    # 0002 Settings
  5,    # 0003 BattleSettings
  6,    # 0004 Settings_Extra_Base
  8,    # 0006 Switches_y_variables (MODO_SIN_GRINDEO etc.; Pokemon#calcHP reads it)
  12,   # 0010 RubyUtilities
  13,   # 0011 Intl_Messages (MessageTypes, _INTL, pbGetMessageFromHash)
  19,   # 0017 PBDebug
  42,   # 0040 Event_NamedEvents (NamedEvent)
  22,   # 0020 Validation (validate helper used by GameData.get)
  42,   # 0040 Event_Handlers (Event base)
  43,   # 0041 Event_HandlerCollections (EventHandlers)
].each { |i| load_script_idx(i) }

# --- 3. GameData classes (all; definitions only, .load called later) -----------
(107..148).each { |i| load_script_idx(i) }

# --- 3b. Pokemon model ---------------------------------------------------------
[
  279,  # 0277 Pokemon
  280,  # 0278 Pokemon_MegaEvolution
  282,  # 0280 Pokemon_Move
  283,  # 0281 Pokemon_Owner
  286,  # 0284 FormHandlers (MultipleForms)
  281,  # 0279 Pokemon_ShadowPokemon (shadowPokemon?/heart gauge methods)
].each { |i| load_script_idx(i) }

# --- 5. Battle engine slice (indices from SCRIPT_MANIFEST.tsv) -----------------
[
  151,  # 0149 ____Battle___ (header)
  152,  # 0150 Battle
  153,  # 0151 Battle_StartAndEnd
  154,  # 0152 Battle_ExpAndMoveLearning
  155,  # 0153 Battle_ActionAttacksPriority
  156,  # 0154 Battle_ActionSwitching
  157,  # 0155 Battle_ActionUseItem
  158,  # 0156 Battle_ActionRunning
  159,  # 0157 Battle_ActionOther
  160,  # 0158 Battle_CommandPhase
  161,  # 0159 Battle_AttackPhase
  162,  # 0160 Battle_EndOfRoundPhase
  163,  # 0161 header
  164,  # 0162 ____Battler___ header
  165,  # 0163 Battle_Battler
  166,  # 0164 Battler_Initialize
  167,  # 0165 Battler_ChangeSelf
  168,  # 0166 Battler_Statuses
  169,  # 0167 Battler_StatStages
  170,  # 0168 Battler_AbilityAndItem
  171,  # 0169 Battler_UseMove
  172,  # 0170 Battler_UseMoveTargeting
  173,  # 0171 Battler_UseMoveSuccessChecks
  174,  # 0172 Battler_UseMoveTriggerEffects
  175,  # 0173 header
  176,  # 0174 ____Move___ header
  177,  # 0175 Battle_Move
  178,  # 0176 Move_Usage
  179,  # 0177 Move_UsageCalculations
  180,  # 0178 Move_BaseEffects
  181,  # 0179 MoveEffects_Misc
  182,  # 0180 MoveEffects_BattlerStats
  183,  # 0181 MoveEffects_BattlerOther
  184,  # 0182 MoveEffects_MoveAttributes
  185,  # 0183 MoveEffects_MultiHit
  186,  # 0184 MoveEffects_Healing
  187,  # 0185 MoveEffects_Items
  188,  # 0186 MoveEffects_ChangeMoveEffect
  189,  # 0187 MoveEffects_SwitchingActing
  226,  # 0224 header
  227,  # 0225 ____Other_battle_code___ header
  228,  # 0226 PBEffects
  229,  # 0227 Battle_ActiveField
  230,  # 0228 Battle_DamageState
  231,  # 0229 Battle_Peers
  232,  # 0230 Battle_CatchAndStoreMixin
  233,  # 0231 Battle_Clauses
  235,  # 0233 Battle_AbilityEffects
  236,  # 0234 Battle_ItemEffects
  237,  # 0235 Battle_PokeBallEffects
].each { |i| load_script_idx(i) }

# --- 6. AI (used by OpponentModel + coach damage baseline) ---------------------
[
  202,  # 0200 header
  203,  # 0201 ____AI___ header
  204,  # 0202 Battle_AI
  205,  # 0203 AI_Switch
  206,  # 0204 AI_UseItem
  207,  # 0205 AI_MegaEvolve
  208,  # 0206 AI_ChooseMove
  209,  # 0207 AI_ChooseMove_GenericEffects
  210,  # 0208 AI_ChooseMove_OtherScores
  211,  # 0209 AI_Utilities
  212,  # 0210 AITrainer
  213,  # 0211 AIBattler
  214,  # 0212 AIMove
  215,  # 0213 header
  216,  # 0214 ____AI_MoveEffects___ header
  217,  # 0215 AI_MoveEffects_Misc
  218,  # 0216 AI_MoveEffects_BattlerStats
  219,  # 0217 AI_MoveEffects_BattlerOther
  220,  # 0218 AI_MoveEffects_MoveAttributes
  221,  # 0219 AI_MoveEffects_MultiHit
  222,  # 0220 AI_MoveEffects_Healing
  223,  # 0221 AI_MoveEffects_Items
  224,  # 0222 AI_MoveEffects_ChangeMoveEffect
  225,  # 0223 AI_MoveEffects_SwitchingActing
].each { |i| load_script_idx(i) }

# The engine's pbReduceDamage references PBEffects::Endure_boss (custom boss
# endure mechanic); the constant itself is defined in the game's
# PluginScripts.rxdata, which is not part of this pack. Define it with a free
# index (effects arrays auto-extend; unset entries are nil i.e. false).
unless PBEffects.const_defined?(:Endure_boss)
  _max = PBEffects.constants.map { |c| PBEffects.const_get(c) }.max
  PBEffects.const_set(:Endure_boss, _max + 1)
end

# --- 6b. Battle types that depend on the AI being defined ----------------------
load_script_idx(262)  # 0260 Overworld_BattleStarting (Game_Temp battle accessors)
load_script_idx(269)  # 0267 Item_Utilities (ItemHandlers, needed by 287)
[
  243,  # 0241 BattleArenaBattle (also defines Battle::SuccessState used by pbCreateBattler)
  287,  # 0285 ShadowPokemon_Other (Battle::Battler#pbHyperModeObedience etc.)
].each { |i| load_script_idx(i) }

# --- 7. load real PBS data ------------------------------------------------------
{
  "types"    => :Type,
  "abilities" => :Ability,
  "species"  => :Species,
  "moves"    => :Move,
  "items"    => :Item,
  "ribbons"  => :Ribbon,
}.each do |label, kname|
  begin
    klass = GameData.const_get(kname)
    klass.load
    puts "[boot] data loaded: #{label} (#{klass.count} entries)"
  rescue => e
    puts "[boot] data load skipped: #{label} (#{e.class}: #{e.message[0, 60]})"
  end
end

puts "[boot] battle engine loaded: GameData species=#{GameData::Species.count} moves=#{GameData::Move.count} abilities=#{GameData::Ability.count} items=#{GameData::Item.count}"
