#===============================================================================
#
#===============================================================================
class PokemonPauseMenu_Scene
  def pbStartScene
    @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 99999
    @sprites = {}
    @sprites["cmdwindow"] = Window_CommandPokemon.new([])
    @sprites["cmdwindow"].visible = false
    @sprites["cmdwindow"].viewport = @viewport
    @sprites["infowindow"] = Window_UnformattedTextPokemon.newWithSize("", 0, 0, 32, 32, @viewport)
    @sprites["infowindow"].visible = false
    @sprites["helpwindow"] = Window_UnformattedTextPokemon.newWithSize("", 0, 0, 32, 32, @viewport)
    @sprites["helpwindow"].visible = false
    @infostate = false
    @helpstate = false
    pbSEPlay("GUI menu open")
  end

  def pbShowInfo(text)
    @sprites["infowindow"].resizeToFit(text, Graphics.height)
    @sprites["infowindow"].text    = text
    @sprites["infowindow"].visible = true
    @infostate = true
  end

  def pbShowHelp(text)
    @sprites["helpwindow"].resizeToFit(text, Graphics.height)
    @sprites["helpwindow"].text    = text
    @sprites["helpwindow"].visible = true
    pbBottomLeft(@sprites["helpwindow"])
    @helpstate = true
  end

  def pbShowMenu
    @sprites["cmdwindow"].visible = true
    @sprites["infowindow"].visible = @infostate
    @sprites["helpwindow"].visible = @helpstate
  end

  def pbHideMenu
    @sprites["cmdwindow"].visible = false
    @sprites["infowindow"].visible = false
    @sprites["helpwindow"].visible = false
  end

  def pbShowCommands(commands)
    ret = -1
    cmdwindow = @sprites["cmdwindow"]
    cmdwindow.commands = commands
    cmdwindow.index    = $game_temp.menu_last_choice
    cmdwindow.resizeToFit(commands)
    cmdwindow.x        = Graphics.width - cmdwindow.width
    cmdwindow.y        = 0
    cmdwindow.visible  = true
    loop do
      cmdwindow.update
      Graphics.update
      Input.update
      pbUpdateSceneMap
      if Input.trigger?(Input::BACK) || Input.trigger?(Input::ACTION)
        ret = -1
        break
      elsif Input.trigger?(Input::USE)
        ret = cmdwindow.index
        $game_temp.menu_last_choice = ret
        break
      end
    end
    return ret
  end

  def pbEndScene
    pbDisposeSpriteHash(@sprites)
    @viewport.dispose
  end

  def pbRefresh; end
end

#===============================================================================
#
#===============================================================================
class PokemonPauseMenu
  def initialize(scene)
    @scene = scene
  end

  def pbShowMenu
    @scene.pbRefresh
    @scene.pbShowMenu
  end

  def pbShowInfo; end

  def pbStartPokemonMenu
    if !$player
      if $DEBUG
        pbMessage(_INTL("El entrenador del jugador no está definido, por lo que el menú de pausa no se puede mostrar."))
        pbMessage(_INTL("Por favor mira la documentación para aprender cómo definir el entrenador del jugador."))
      end
      return
    end
    @scene.pbStartScene
    # Show extra info window if relevant
    pbShowInfo
    # Get all commands
    command_list = []
    commands = []
    MenuHandlers.each_available(:pause_menu) do |option, hash, name|
      command_list.push(name)
      commands.push(hash)
    end
    # Main loop
    end_scene = false
    loop do
      choice = @scene.pbShowCommands(command_list)
      if choice < 0
        pbPlayCloseMenuSE
        end_scene = true
        break
      end
      break if commands[choice]["effect"].call(@scene)
    end
    @scene.pbEndScene if end_scene
  end
end

#===============================================================================
# Pause menu commands.
#===============================================================================
MenuHandlers.add(:pause_menu, :pokedex, {
  "name"      => _INTL("Pokédex"),
  "order"     => 10,
  "condition" => proc { next $player.has_pokedex && $player.pokedex.accessible_dexes.length > 0 },
  "effect"    => proc { |menu|
    pbPlayDecisionSE
    menu.pbHideMenu
    if Settings::USE_CURRENT_REGION_DEX
      pbFadeOutIn do
        scene = PokemonPokedex_Scene.new
        screen = PokemonPokedexScreen.new(scene)
        screen.pbStartScreen
        menu.pbRefresh
      end
    elsif $player.pokedex.accessible_dexes.length == 1
      $PokemonGlobal.pokedexDex = $player.pokedex.accessible_dexes[0]
      pbFadeOutIn do
        scene = PokemonPokedex_Scene.new
        screen = PokemonPokedexScreen.new(scene)
        screen.pbStartScreen
        menu.pbRefresh
      end
    else
      pbFadeOutIn do
        scene = PokemonPokedexMenu_Scene.new
        screen = PokemonPokedexMenuScreen.new(scene)
        screen.pbStartScreen
        menu.pbRefresh
      end
    end
    menu.pbShowMenu
    next false
  }
})

MenuHandlers.add(:pause_menu, :party, {
  "name"      => _INTL("Pokémon"),
  "order"     => 20,
  "condition" => proc { next $player.party_count > 0 },
  "effect"    => proc { |menu|
    pbPlayDecisionSE
    hidden_move = nil
    menu.pbHideMenu
    pbFadeOutIn do
      sscene = PokemonParty_Scene.new
      sscreen = PokemonPartyScreen.new(sscene, $player.party)
      hidden_move = sscreen.pbPokemonScreen
      (hidden_move) ? menu.pbEndScene : menu.pbRefresh
    end
    menu.pbShowMenu if !hidden_move
    next false if !hidden_move
    $game_temp.in_menu = false
    pbUseHiddenMove(hidden_move[0], hidden_move[1])
    next true
  }
})

MenuHandlers.add(:pause_menu, :bag, {
  "name"      => _INTL("Mochila"),
  "order"     => 30,
  "condition" => proc { next !pbInBugContest? },
  "effect"    => proc { |menu|
    pbPlayDecisionSE
    item = nil
    menu.pbHideMenu
    pbFadeOutIn do
      scene = PokemonBag_Scene.new
      screen = PokemonBagScreen.new(scene, $bag)
      item = screen.pbStartScreen
      (item) ? menu.pbEndScene : menu.pbRefresh
    end
    menu.pbShowMenu if !item
    next false if !item
    $game_temp.in_menu = false
    pbUseKeyItemInField(item)
    next true
  }
})

MenuHandlers.add(:pause_menu, :pokegear, {
  "name"      => _INTL("Pokégear"),
  "order"     => 40,
  "condition" => proc { next $player.has_pokegear },
  "effect"    => proc { |menu|
    pbPlayDecisionSE
    menu.pbHideMenu
    pbFadeOutIn do
      scene = PokemonPokegear_Scene.new
      screen = PokemonPokegearScreen.new(scene)
      screen.pbStartScreen
      ($game_temp.fly_destination) ? menu.pbEndScene : menu.pbRefresh
    end
    menu.pbShowMenu if !$game_temp.fly_destination
    next pbFlyToNewLocation
  }
})

MenuHandlers.add(:pause_menu, :town_map, {
  "name"      => _INTL("Mapa"),
  "order"     => 40,
  "condition" => proc { next !$player.has_pokegear && $bag.has?(:TOWNMAP) },
  "effect"    => proc { |menu|
    pbPlayDecisionSE
    menu.pbHideMenu
    pbFadeOutIn do
      scene = PokemonRegionMap_Scene.new(-1, false)
      screen = PokemonRegionMapScreen.new(scene)
      ret = screen.pbStartScreen
      $game_temp.fly_destination = ret if ret
      ($game_temp.fly_destination) ? menu.pbEndScene : menu.pbRefresh
    end
    menu.pbShowMenu if !$game_temp.fly_destination
    next pbFlyToNewLocation
  }
})

MenuHandlers.add(:pause_menu, :trainer_card, {
  "name"      => proc { next $player.name },
  "order"     => 50,
  "effect"    => proc { |menu|
    pbPlayDecisionSE
    menu.pbHideMenu
    pbFadeOutIn do
      scene = PokemonTrainerCard_Scene.new
      screen = PokemonTrainerCardScreen.new(scene)
      screen.pbStartScreen
      menu.pbRefresh
    end
    menu.pbShowMenu
    next false
  }
})

MenuHandlers.add(:pause_menu, :save, {
  "name"      => _INTL("Guardar"),
  "order"     => 60,
  "condition" => proc {
    next $game_system && !$game_system.save_disabled && !pbInSafari? && !pbInBugContest?
  },
  "effect"    => proc { |menu|
    menu.pbHideMenu
    scene = PokemonSave_Scene.new
    screen = PokemonSaveScreen.new(scene)
    if screen.pbSaveScreen
      menu.pbEndScene
      next true
    end
    menu.pbRefresh
    menu.pbShowMenu
    next false
  }
})

MenuHandlers.add(:pause_menu, :options, {
  "name"      => _INTL("Opciones"),
  "order"     => 70,
  "effect"    => proc { |menu|
    pbPlayDecisionSE
    menu.pbHideMenu
    pbFadeOutIn do
      scene = PokemonOption_Scene.new
      screen = PokemonOptionScreen.new(scene)
      screen.pbStartScreen
      pbUpdateSceneMap
      menu.pbRefresh
    end
    menu.pbShowMenu
    next false
  }
})

MenuHandlers.add(:pause_menu, :debug, {
  "name"      => _INTL("Debug"),
  "order"     => 80,
  "condition" => proc { next $DEBUG },
  "effect"    => proc { |menu|
    pbPlayDecisionSE
    menu.pbHideMenu
    pbFadeOutIn do
      pbDebugMenu
      menu.pbRefresh
    end
    menu.pbShowMenu
    next false
  }
})

MenuHandlers.add(:pause_menu, :quit_game, {
  "name"      => _INTL("Cerrar Juego"),
  "order"     => 90,
  "effect"    => proc { |menu|
    menu.pbHideMenu
    if pbConfirmMessage(_INTL("¿Estás segur{1} de que quieres cerrar el juego?", $player.female? ? 'a' : 'o'))
      scene = PokemonSave_Scene.new
      screen = PokemonSaveScreen.new(scene)
      screen.pbSaveScreen
      $scene = nil
      menu.pbEndScene
      next true
    end
    menu.pbRefresh
    menu.pbShowMenu
    next false
  }
})


#===============================================================================
# Competitive Team Lab - local party editor without enabling $DEBUG/$TEST.
# Does not alter multiplayer authentication, debug flags, or network checks.
#===============================================================================
module AnilTeamLab
  BACKUP_IVAR = :@anil_team_lab_party_backup

  def self.deep_copy(obj)
    Marshal.load(Marshal.dump(obj))
  rescue
    nil
  end

  def self.backup_exists?
    return false if !defined?($PokemonGlobal) || !$PokemonGlobal
    data = $PokemonGlobal.instance_variable_get(BACKUP_IVAR) rescue nil
    data.is_a?(Array) && !data.empty?
  end

  def self.backup_party(show_message = true)
    return false if !defined?($player) || !$player || !$player.party
    copy = deep_copy($player.party)
    if !copy
      pbMessage(_INTL("No se pudo crear la copia de seguridad del equipo.")) if show_message
      return false
    end
    $PokemonGlobal.instance_variable_set(BACKUP_IVAR, copy)
    pbMessage(_INTL("Equipo actual guardado. Podrás restaurarlo desde Team Lab.")) if show_message
    true
  end

  def self.ensure_backup
    backup_exists? || backup_party(false)
  end

  def self.restore_party
    if !backup_exists?
      pbMessage(_INTL("No hay ningún equipo guardado por Team Lab."))
      return
    end
    return if !pbConfirmMessage(_INTL("¿Restaurar el equipo guardado? El equipo actual será reemplazado."))
    copy = deep_copy($PokemonGlobal.instance_variable_get(BACKUP_IVAR))
    if copy
      $player.party.replace(copy)
      $player.party.each { |pkmn| pkmn.calc_stats rescue nil }
      pbMessage(_INTL("Equipo original restaurado."))
    else
      pbMessage(_INTL("No se pudo restaurar la copia de seguridad."))
    end
  end

  def self.edit_pokemon
    if !$player || !$player.party || $player.party.empty?
      pbMessage(_INTL("No tienes Pokémon en el equipo."))
      return
    end
    ensure_backup
    screen = PokemonDebugPartyScreen.new
    begin
      names = $player.party.each_with_index.map { |p, i| _INTL("{1}. {2} Nv.{3}", i + 1, p.name, p.level) }
      idx = screen.pbShowCommands(_INTL("Team Lab: elige un Pokémon."), names, 0)
      return if idx.nil? || idx < 0
      pkmn = $player.party[idx]
      screen.pbPokemonDebug(pkmn, idx, nil, false)
      pkmn.calc_stats rescue nil
    ensure
      screen.pbEndScreen rescue nil
    end
  end

  def self.add_pokemon
    ensure_backup
    species = pbChooseSpeciesList
    return if !species
    params = ChooseNumberParams.new
    params.setRange(1, GameData::GrowthRate.max_level)
    params.setInitialValue(50)
    params.setCancelValue(0)
    level = pbMessageChooseNumber(_INTL("Elige el nivel del Pokémon."), params)
    return if level <= 0
    goes_to_party = !$player.party_full?
    if pbAddPokemonSilent(species, level)
      if goes_to_party
        pbMessage(_INTL("Pokémon añadido. Usa 'Editar Pokémon' para configurar IVs, EVs, naturaleza, habilidad, movimientos e ítem."))
      else
        pbMessage(_INTL("El equipo estaba lleno; el Pokémon fue enviado al PC."))
      end
    else
      pbMessage(_INTL("No se pudo añadir el Pokémon."))
    end
  end

  def self.open
    ensure_backup
    loop do
      commands = [
        _INTL("Editar Pokémon"),
        _INTL("Añadir Pokémon"),
        _INTL("Guardar equipo actual como backup"),
        _INTL("Restaurar equipo guardado"),
        _INTL("Salir")
      ]
      choice = pbMessage(_INTL("TEAM LAB\nEl modo Debug global permanece desactivado."), commands, -1)
      break if choice.nil? || choice < 0 || choice == 4
      case choice
      when 0 then edit_pokemon
      when 1 then add_pokemon
      when 2 then backup_party(true)
      when 3 then restore_party
      end
    end
  end
end

MenuHandlers.add(:pause_menu, :team_lab, {
  "name"      => _INTL("Team Lab"),
  "order"     => 75,
  "condition" => proc { next defined?($player) && $player },
  "effect"    => proc { |menu|
    pbPlayDecisionSE
    menu.pbHideMenu
    pbFadeOutIn do
      AnilTeamLab.open
      menu.pbRefresh
    end
    menu.pbShowMenu
    next false
  }
})

#===============================================================================
# Team Lab Safe - consistency preflight for multiplayer testing.
# Does NOT alter online authentication, debug/test flags, ban handling or packets.
#===============================================================================
module AnilTeamLab
  STAT_KEYS = [:HP, :ATTACK, :DEFENSE, :SPECIAL_ATTACK, :SPECIAL_DEFENSE, :SPEED]

  def self.normalize_pokemon!(pkmn)
    return [false, ["Pokémon inválido."]] if !pkmn
    issues = []
    # Keep level/experience internally coherent. Level is the user's selected truth.
    lvl = pkmn.level.to_i
    max_lvl = GameData::GrowthRate.max_level.to_i rescue 100
    lvl = [[lvl, 1].max, max_lvl].min
    begin
      pkmn.instance_variable_set(:@level, lvl)
      pkmn.instance_variable_set(:@exp, pkmn.growth_rate.minimum_exp_for_level(lvl))
    rescue => e
      issues << "No se pudo sincronizar nivel/EXP: #{e.message}"
    end

    # Clamp IVs and EVs to ordinary competitive limits. If EV total exceeds 510,
    # reduce deterministically from the last stats until the total is legal.
    begin
      STAT_KEYS.each do |s|
        pkmn.iv[s] = [[pkmn.iv[s].to_i, 0].max, 31].min
        pkmn.ev[s] = [[pkmn.ev[s].to_i, 0].max, 252].min
      end
      excess = STAT_KEYS.sum { |s| pkmn.ev[s].to_i } - 510
      if excess > 0
        STAT_KEYS.reverse_each do |s|
          break if excess <= 0
          cut = [pkmn.ev[s].to_i, excess].min
          pkmn.ev[s] -= cut
          excess -= cut
        end
      end
    rescue => e
      issues << "No se pudieron normalizar IV/EV: #{e.message}"
    end

    # Remove malformed moves/items rather than transmitting invalid IDs.
    begin
      pkmn.moves = Array(pkmn.moves).compact.select { |m| m && GameData::Move.exists?(m.id) }[0, 4]
      pkmn.moves.each do |m|
        data = GameData::Move.get(m.id)
        m.ppup = [[m.ppup.to_i, 0].max, 3].min if m.respond_to?(:ppup=)
        m.pp = [[m.pp.to_i, 0].max, m.total_pp.to_i].min if m.respond_to?(:pp=)
      end
    rescue => e
      issues << "No se pudieron validar movimientos: #{e.message}"
    end
    begin
      pkmn.item = nil if pkmn.item_id && !GameData::Item.exists?(pkmn.item_id)
    rescue => e
      issues << "No se pudo validar el objeto: #{e.message}"
    end

    # Let the game's own engine calculate battle stats; never inject raw stats.
    begin
      old_total = pkmn.totalhp.to_i
      old_hp = pkmn.hp.to_i
      pkmn.calc_stats
      pkmn.hp = pkmn.totalhp if old_hp >= old_total || old_hp <= 0
      pkmn.hp = [[pkmn.hp.to_i, 1].max, pkmn.totalhp.to_i].min
    rescue => e
      issues << "No se pudieron recalcular stats: #{e.message}"
    end
    [issues.empty?, issues]
  end

  def self.round_trip_check(pkmn)
    errors = []
    begin
      blob = AnilLanRework::Serializer.serialize_pokemon(pkmn)
      return [false, ["El serializador PvP rechazó el Pokémon."]] if !blob.is_a?(Hash)
      clone = AnilLanRework::Serializer.deserialize_pokemon(blob)
      return [false, ["El receptor PvP no pudo reconstruir el Pokémon."]] if !clone
      blob2 = AnilLanRework::Serializer.serialize_pokemon(clone)
      critical = %w[species level exp form totalhp stats ability_index ability nature nature_for_stats item iv ev moves]
      critical.each do |key|
        a = blob[key]
        b = blob2[key]
        errors << "Divergencia en #{key}." if a != b
      end
    rescue => e
      errors << "Error de preflight: #{e.class}: #{e.message}"
    end
    [errors.empty?, errors]
  end

  def self.safe_preflight(show_success = true)
    return false if !$player || !$player.party || $player.party.empty?
    all_errors = []
    $player.party.each_with_index do |pkmn, i|
      ok, issues = normalize_pokemon!(pkmn)
      issues.each { |x| all_errors << "#{i + 1}. #{pkmn.name}: #{x}" } unless ok
      ok2, issues2 = round_trip_check(pkmn)
      issues2.each { |x| all_errors << "#{i + 1}. #{pkmn.name}: #{x}" } unless ok2
    end
    if !all_errors.empty?
      pbMessage(_INTL("PREFLIGHT BLOQUEADO.\n{1}", all_errors[0, 8].join("\n")))
      return false
    end
    pbMessage(_INTL("Preflight OK. Los 6 Pokémon son coherentes con el serializador PvP de este cliente.")) if show_success
    true
  end

  class << self
    alias team_lab_unsafe_open open unless method_defined?(:team_lab_unsafe_open)
  end

  def self.open
    ensure_backup
    loop do
      commands = [
        _INTL("Editar Pokémon"),
        _INTL("Añadir Pokémon"),
        _INTL("Validar/normalizar equipo para PvP"),
        _INTL("Guardar equipo actual como backup"),
        _INTL("Restaurar equipo guardado"),
        _INTL("Salir")
      ]
      choice = pbMessage(_INTL("TEAM LAB SAFE\nNo modifica Debug, autenticación ni detección online."), commands, -1)
      break if choice.nil? || choice < 0 || choice == 5
      case choice
      when 0
        edit_pokemon
        safe_preflight(false)
      when 1
        add_pokemon
        safe_preflight(false)
      when 2 then safe_preflight(true)
      when 3 then backup_party(true)
      when 4 then restore_party
      end
    end
  end
end

#===============================================================================
# Team Lab Safe PvP v2 - mirrors the client-side PvP registration rules and
# simulates the fixed-level (Lv.50) copy path before any online connection.
# This does not alter authentication, debug/test reporting, bans or packets.
#===============================================================================
module AnilTeamLab
  def self.pvp_rules_check
    errors = []
    party = Array($player && $player.party).compact
    return [false, ["El equipo está vacío."]] if party.empty?
    begin
      n = [[party.length, 1].max, 6].min
      rules = PokemonOnlineRules.new
      rules.setNumberRange(n, n)
      rules.addPokemonRule(NonEggRestriction) if defined?(NonEggRestriction)
      unless rules.ruleset.hasRegistrableTeam?(party)
        errors << "PokemonOnlineRules#hasRegistrableTeam? rechazó el equipo."
      end
    rescue => e
      errors << "No se pudieron ejecutar las reglas PvP locales: #{e.class}: #{e.message}"
    end
    [errors.empty?, errors]
  end

  def self.fixed_level_simulation_check(pkmn, target_level = 50)
    errors = []
    begin
      # Use the same network boundary first: serialize -> deserialize a COPY.
      blob = AnilLanRework::Serializer.serialize_pokemon(pkmn)
      copy = AnilLanRework::Serializer.deserialize_pokemon(blob)
      return [false, ["No se pudo crear la copia PvP."]] if !copy
      lvl = target_level.to_i
      max = (GameData::GrowthRate.max_level rescue 100).to_i
      lvl = [[lvl, 1].max, max].min
      copy.instance_variable_set(:@exp, copy.growth_rate.minimum_exp_for_level(lvl))
      copy.instance_variable_set(:@level, lvl)
      copy.calc_stats
      copy.heal rescue nil

      errors << "La copia PvP no quedó en Nv.#{lvl}." if copy.level.to_i != lvl
      begin
        expected_exp = copy.growth_rate.minimum_exp_for_level(lvl).to_i
        errors << "EXP incoherente tras normalización PvP." if copy.exp.to_i != expected_exp
      rescue
      end
      errors << "HP/Stats inválidos tras normalización PvP." if copy.totalhp.to_i <= 0

      # Ensure the normalized copy can cross the serializer again unchanged.
      b1 = AnilLanRework::Serializer.serialize_pokemon(copy)
      c2 = AnilLanRework::Serializer.deserialize_pokemon(b1)
      b2 = AnilLanRework::Serializer.serialize_pokemon(c2)
      %w[species level exp form totalhp stats ability_index ability nature nature_for_stats item iv ev moves].each do |key|
        errors << "Divergencia PvP Nv.#{lvl} en #{key}." if b1[key] != b2[key]
      end
    rescue => e
      errors << "Fallo al simular PvP Nv.#{target_level}: #{e.class}: #{e.message}"
    end
    [errors.empty?, errors]
  end

  def self.safe_preflight(show_success = true)
    return false if !$player || !$player.party || $player.party.empty?
    all_errors = []

    $player.party.each_with_index do |pkmn, i|
      ok, issues = normalize_pokemon!(pkmn)
      issues.each { |x| all_errors << "#{i + 1}. #{pkmn.name}: #{x}" } unless ok

      ok2, issues2 = round_trip_check(pkmn)
      issues2.each { |x| all_errors << "#{i + 1}. #{pkmn.name}: #{x}" } unless ok2

      ok3, issues3 = fixed_level_simulation_check(pkmn, 50)
      issues3.each { |x| all_errors << "#{i + 1}. #{pkmn.name}: #{x}" } unless ok3
    end

    ok_rules, rule_issues = pvp_rules_check
    rule_issues.each { |x| all_errors << "Equipo: #{x}" } unless ok_rules

    if !all_errors.empty?
      pbMessage(_INTL("PREFLIGHT PVP BLOQUEADO.\n{1}", all_errors[0, 10].join("\n")))
      return false
    end
    if show_success
      pbMessage(_INTL("PREFLIGHT PVP OK.\nEquipo válido para las reglas PvP de este cliente, round-trip estable y copia Nv.50 simulada correctamente.\n\nEsto no verifica reglas privadas del servidor."))
    end
    true
  end
end

#===============================================================================
# Team Lab Safe - F8 map hotkey (does not enable global Debug)
# F8 is also used by this build for screenshots; on the overworld it additionally
# opens Team Lab Safe. No multiplayer/debug/test flags are modified here.
#===============================================================================
class Scene_Map
  unless method_defined?(:anil_team_lab_safe_f8_update)
    alias anil_team_lab_safe_f8_update update
    def update
      anil_team_lab_safe_f8_update
      begin
        f8_pressed = Input.trigger?(Input::F8)
      rescue
        f8_pressed = (Input.triggerex?(:F8) rescue false)
      end
      if f8_pressed && defined?(AnilTeamLab) && defined?($player) && $player
        # Do not open on top of a running message/interpreter event.
        busy = false
        busy ||= ($game_temp && $game_temp.message_window_showing) rescue false
        busy ||= ($game_system && $game_system.map_interpreter && $game_system.map_interpreter.running?) rescue false
        unless busy
          pbPlayDecisionSE rescue nil
          AnilTeamLab.open
        end
      end
    end
  end
end
