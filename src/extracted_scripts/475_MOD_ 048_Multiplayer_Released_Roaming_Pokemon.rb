#===============================================================================
# MOD: 048_Multiplayer_Released_Roaming_Pokemon.rb
#-------------------------------------------------------------------------------
# Permite que ao liberar um Pokémon no PC (Storage), ele apareça fisicamente
# no gramado da rota mais próxima (ou caverna mais próxima), escolhendo uma
# coordenada de grama válida de forma orgânica. Qualquer jogador (em modo
# Solo ou Cooperativo) pode interagir com o Pokémon, ouvir seu grito e entrar
# em uma batalha selvagem contra essa exata instância de Pokémon (com mesmo
# nível, moveset, IVs, EVs, shininess e nickname) para recapturá-lo!
# Totalmente integrado ao Multiplayer Cooperativo (Sincronização em tempo real)!
#===============================================================================

class PokemonGlobalMetadata
  attr_accessor :released_roaming_pokemon

  unless method_defined?(:anil_released_roaming_initialize) || private_method_defined?(:anil_released_roaming_initialize)
    alias anil_released_roaming_initialize initialize
  end

  def initialize
    begin
      anil_released_roaming_initialize
      @released_roaming_pokemon = {}
    rescue => e
      AnilLanRework.log("Erro no init global metadata released roaming: #{e.message}") rescue nil
    end
  end
end

class PokemonGlobalMetadata
  def released_roaming_pokemon
    @released_roaming_pokemon ||= {}
    return @released_roaming_pokemon
  end

  def released_roaming_pokemon=(val)
    @released_roaming_pokemon = val
  end
end

class Game_Map
  unless method_defined?(:anil_released_roaming_setup) || private_method_defined?(:anil_released_roaming_setup)
    alias anil_released_roaming_setup setup
  end

  def setup(map_id)
    anil_released_roaming_setup(map_id)
    begin
      AnilLanRework::ReleasedRoaming.spawn_all_for_current_map(self)
      @pending_released_roaming_request = true
    rescue => e
      AnilLanRework.log("Erro no setup de mapa released roaming: #{e.message}") rescue nil
    end
  end

  unless method_defined?(:anil_released_roaming_update) || private_method_defined?(:anil_released_roaming_update)
    alias anil_released_roaming_update update rescue nil
  end

  def update
    if respond_to?(:anil_released_roaming_update, true)
      anil_released_roaming_update
    end
    if @pending_released_roaming_request
      @pending_released_roaming_request = false
      if AnilLanRework.connected?
        AnilLanRework.connection.send_packet("request_released_roaming_pokemon", {
          "map_id" => self.map_id
        }) rescue nil
      end
    end
    begin
      AnilLanRework::ReleasedRoaming.update_connection_sync
    rescue => e
      # Silencioso
    end
  end
end

class PokemonStorageScreen
  unless method_defined?(:anil_released_roaming_pbRelease) || private_method_defined?(:anil_released_roaming_pbRelease)
    alias anil_released_roaming_pbRelease pbRelease
  end

  def pbRelease(selected, heldpoke)
    box = selected[0]
    index = selected[1]
    pokemon = (heldpoke) ? heldpoke : @storage[box, index]

    result = anil_released_roaming_pbRelease(selected, heldpoke)

    if pokemon
      still_present = false
      if heldpoke
        still_present = (@heldpkmn == pokemon)
      else
        still_present = (@storage[box, index] == pokemon)
      end

      if !still_present
        # Pokémon foi liberado com sucesso! Spawna no mapa de encontros mais próximo!
        begin
          target_map_id = AnilLanRework::ReleasedRoaming.release_pokemon_to_overworld(pokemon)
          if target_map_id
            pbDisplay(_INTL("{1} olha para você com carinho e parece dizer:\n\"A gente se vê por aí!\"", pokemon.name))
          end
        rescue => e
          AnilLanRework.log("Erro ao spawnar pokemon solto: #{e.message}") rescue nil
        end
      end
    end

    return result
  end
end

module AnilLanRework
  module ReleasedRoaming
    module_function

    @last_connection_state = false

    def update_connection_sync
      return unless $game_map
      current_state = AnilLanRework.connected? rescue false
      if current_state && !@last_connection_state
        begin
          AnilLanRework.connection.send_packet("request_released_roaming_pokemon", {
            "map_id" => $game_map.map_id
          }) rescue nil
        rescue => e
          AnilLanRework.log("Erro no update_connection_sync: #{e.message}") rescue nil
        end
      end
      @last_connection_state = current_state
    end

    def get_released_pokemon
      $PokemonGlobal.released_roaming_pokemon ||= {}
      $PokemonGlobal.released_roaming_pokemon
    rescue => e
      {}
    end

    def find_starting_overworld_map(start_map_id)
      # 1. Se o mapa atual já é Outdoor (ao ar livre), começamos dele!
      metadata = GameData::MapMetadata.try_get(start_map_id) rescue nil
      return start_map_id if metadata && metadata.outdoor_map

      # 2. Se o mapa atual tem um local de cura (como Centros Pokémon que guardam a entrada da cidade)
      if metadata && metadata.teleport_destination
        dest_map = metadata.teleport_destination[0] rescue nil
        dest_metadata = GameData::MapMetadata.try_get(dest_map) rescue nil
        return dest_map if dest_metadata && dest_metadata.outdoor_map
      end

      # 3. Varre o histórico de mapas recentes visitados ($PokemonGlobal.mapTrail) de trás para frente (mais recente primeiro)
      if $PokemonGlobal && $PokemonGlobal.mapTrail
        $PokemonGlobal.mapTrail.each do |trail_map|
          next if trail_map == start_map_id
          trail_metadata = GameData::MapMetadata.try_get(trail_map) rescue nil
          return trail_map if trail_metadata && trail_metadata.outdoor_map
        end
      end

      # 4. Fallback para o último ponto de cura global se for outdoor
      if $PokemonGlobal && $PokemonGlobal.healingSpot
        heal_map = $PokemonGlobal.healingSpot[0] rescue nil
        heal_metadata = GameData::MapMetadata.try_get(heal_map) rescue nil
        return heal_map if heal_metadata && heal_metadata.outdoor_map
      end

      # 5. Se mesmo assim não achou nada outdoor, retorna o próprio start_map_id
      return start_map_id
    end

    def find_nearest_encounter_map(start_map_id)
      # Resolve o mapa de início para garantir que seja um mapa outdoor/overworld
      resolved_start = find_starting_overworld_map(start_map_id) rescue start_map_id
      resolved_start = start_map_id if resolved_start.nil?

      queue = [resolved_start]
      visited = { resolved_start => true }
      depth = { resolved_start => 0 }

      while !queue.empty?
        curr = queue.shift
        curr_depth = depth[curr]

        # Verifica se o mapa possui encontros em terra ou cavernas definidos
        enc = GameData::Encounter.get(curr, ($PokemonGlobal.encounter_version rescue 0)) rescue nil
        if enc && enc.types && enc.types.any? { |type, list| [:Land, :LandMorning, :LandDay, :LandNight, :Cave].include?(type) && list && list.length > 0 }
          return curr
        end

        break if curr_depth >= 4 # Limite de busca BFS para prevenir loops longos

        neighbors = []
        MapFactoryHelper.eachConnectionForMap(curr) do |conn|
          neighbors << conn[0] if conn[0]
          neighbors << conn[3] if conn[3]
        end rescue nil
        neighbors.uniq! if neighbors

        if neighbors
          neighbors.each do |n|
            next if visited[n]
            visited[n] = true
            depth[n] = curr_depth + 1
            queue << n
          end
        end
      end

      return resolved_start # Fallback
    end

    def find_encounter_tile_in_map(map_id)
      map_obj = nil
      if $game_map && $game_map.map_id == map_id
        map_obj = $game_map
      elsif $map_factory
        map_obj = $map_factory.getMap(map_id) rescue nil
      end

      if map_obj
        # Verifica se o mapa possui encontros do tipo Caverna
        is_cave = false
        enc = GameData::Encounter.get(map_id, ($PokemonGlobal.encounter_version rescue 0)) rescue nil
        if enc && enc.types && enc.types.any? { |type, list| [:Cave].include?(type) && list && list.length > 0 }
          is_cave = true
        end

        width = map_obj.width
        height = map_obj.height
        candidates = []

        (0...width).each do |tx|
          (0...height).each do |ty|
            next if !map_obj.valid?(tx, ty)

            terrain = map_obj.terrain_tag(tx, ty) rescue nil
            next if terrain && (terrain.can_surf || terrain.ledge)

            if is_cave
              if map_obj.passable?(tx, ty, 0)
                candidates << [tx, ty]
              end
            else
              # Em rotas normais, damos total preferência aos blocos de grama/encontros selvagens
              if terrain && terrain.land_wild_encounters && map_obj.passable?(tx, ty, 0)
                candidates << [tx, ty]
              end
            end
          end
        end

        if !candidates.empty?
          return candidates.sample
        end

        # Fallback 1: se não achar grama, busca qualquer tile caminhável normal do mapa
        (0...width).each do |tx|
          (0...height).each do |ty|
            next if !map_obj.valid?(tx, ty)
            terrain = map_obj.terrain_tag(tx, ty) rescue nil
            next if terrain && (terrain.can_surf || terrain.ledge)
            if map_obj.passable?(tx, ty, 0)
              return [tx, ty]
            end
          end
        end
      end

      # Fallback final de coordenadas seguras
      return [10, 10]
    end

    def spawn_all_for_current_map(map_obj = nil)
      map_obj ||= $game_map
      return unless map_obj
      map_id = map_obj.map_id
      pokes = get_released_pokemon[map_id] || []
      pokes.each do |poke_data|
        spawn_local_poke_event(poke_data[:id], poke_data[:pokemon], poke_data[:x], poke_data[:y], map_obj)
      end
    rescue => e
      AnilLanRework.log("Erro ao spawnar pokemon no mapa: #{e.message}") rescue nil
    end

    def spawn_local_poke_event(event_id, pokemon, x, y, map_obj = nil)
      map_obj ||= $game_map
      return if !map_obj
      begin
        char_name = resolve_pokemon_character_path(pokemon)

        rpg_event = RPG::Event.new(x, y)
        rpg_event.id = event_id
        rpg_event.name = "ReleasedPoke_#{event_id}"

        page = rpg_event.pages[0]
        page.graphic.character_name = char_name
        # Estava fixo em 0, entao um super shiny solto no mapa aparecia sem cor.
        # O pokemon chega por Marshal completo, entao o hue proprio
        # (@cached_super_shiny_hue) esta disponivel aqui. Mesmo tratamento do
        # 070_Multiplayer_OW_Spawns_Sync. O getter ja devolve 0 se nao for super
        # shiny, e deriva pela especie quando nao ha hue proprio.
        page.graphic.character_hue = (pokemon.super_shiny_hue.to_i rescue 0)
        page.trigger = 0 # Botão de Ação (C)
        page.step_anime = true # Animação contínua (idle anim)
        page.move_type = 1 # Wandering/Andar aleatório para ficar vivo e elegante!
        page.move_speed = 3 # Velocidade lenta e natural
        page.through = false # Obstáculo físico sólido

        page.list = [
          RPG::EventCommand.new(355, 0, ["AnilLanRework::ReleasedRoaming.interact_roaming_pokemon(#{event_id})"]),
          RPG::EventCommand.new(0, 0, [])
        ]

        game_event = Game_Event.new(map_obj.map_id, rpg_event, map_obj)
        map_obj.events[event_id] = game_event

        map_data = map_obj.instance_variable_get(:@map) rescue nil
        if map_data && map_data.respond_to?(:events)
          map_data.events[event_id] = rpg_event
        end

        # Aplica estado travado/invisível se já estiver bloqueado na rede
        map_id = map_obj.map_id
        pokes = get_released_pokemon[map_id] || []
        poke_data = pokes.find { |p| p[:id] == event_id }
        if poke_data && poke_data[:locked]
          game_event.opacity = 0
          game_event.through = true
          game_event.instance_variable_set(:@temp_disabled, true)
        end

        game_event.refresh

        if $scene.is_a?(Scene_Map)
          sync_sprite(game_event)
        end
      rescue => e
        AnilLanRework.log("Erro ao criar evento local de pokemon: #{e.message}") rescue nil
      end
    end

    def sync_sprite(event)
      return unless event
      return unless $scene.is_a?(Scene_Map)
      return unless $scene.respond_to?(:spritesets)
      begin
        spritesets = $scene.spritesets
        return unless spritesets
        spriteset = spritesets[$game_map.map_id] rescue nil
        spriteset ||= spritesets.values.find { |s| s.respond_to?(:map) && s.map == $game_map } rescue nil
        return unless spriteset
        return unless spriteset.respond_to?(:character_sprites)

        already_present = spriteset.character_sprites.any? { |sprite| sprite.character == event } rescue false
        return if already_present

        viewport = nil
        spriteset.instance_variables.each do |var|
          val = spriteset.instance_variable_get(var)
          if val.is_a?(Viewport)
            viewport = val
            break
          end
        end
        viewport ||= Spriteset_Map.viewport rescue nil
        return unless viewport

        spriteset.character_sprites.push(Sprite_Character.new(viewport, event))
      rescue => e
        AnilLanRework.log("Erro ao sincronizar sprite de pokemon: #{e.message}") rescue nil
      end
    end

    def resolve_pokemon_character_path(pkmn)
      species = pkmn.species.to_s
      form = (pkmn.respond_to?(:form_simple) ? pkmn.form_simple : pkmn.form).to_i rescue 0
      suffix = form > 0 ? "_#{form}" : ""

      if pkmn.shiny?
        shiny_path = "Followers shiny/#{species}#{suffix}"
        return shiny_path if pbResolveBitmap("Graphics/Characters/#{shiny_path}") rescue nil
      end

      default_path = "Followers/#{species}#{suffix}"
      return default_path if pbResolveBitmap("Graphics/Characters/#{default_path}") rescue nil

      fallback_path = "Followers/#{species}"
      return fallback_path if pbResolveBitmap("Graphics/Characters/#{fallback_path}") rescue nil

      # Fallback usando o número de ID da espécie
      num_str = sprintf("%03d", GameData::Species.get(pkmn.species).id_number) rescue nil
      if num_str
        if pkmn.shiny?
          shiny_path = "Followers shiny/#{num_str}#{suffix}"
          return shiny_path if pbResolveBitmap("Graphics/Characters/#{shiny_path}") rescue nil
        end
        default_path = "Followers/#{num_str}#{suffix}"
        return default_path if pbResolveBitmap("Graphics/Characters/#{default_path}") rescue nil

        return num_str if pbResolveBitmap("Graphics/Characters/#{num_str}") rescue nil
      end

      return "ItemBall"
    end

    def release_pokemon_to_overworld(pokemon)
      return nil unless $game_map
      begin
        # MARCA DE ABANDONO — o selo de verificado nao sobrevive a uma soltura.
        #
        # Carimba-se AQUI, no momento de soltar, e nao na recaptura: o objecto e
        # o mesmo do inicio ao fim (a recaptura usa WildBattle.start_core com
        # este proprio Pokemon, nao cria outro), portanto a marca acompanha-o
        # para sempre e para qualquer dono seguinte.
        #
        # Sem isto, um Pokemon obtido depois do corte podia ser solto e apanhado
        # por outra pessoa continuando a exibir o selo — e quem o tem nao fez
        # nada para o merecer. A data sozinha nao resolvia: ela e preservada na
        # soltura, entao continuaria a passar no teste.
        pokemon.instance_variable_set(:@anil_solto_em, Time.now.to_i) rescue nil
        # Encontra a rota ou caverna com encontros selvagens mais próxima de nós!
        target_map_id = find_nearest_encounter_map($game_map.map_id)
        
        # Encontra um bloco de grama (ou tile transitável na caverna) válido e aleatório
        dest_x, dest_y = find_encounter_tile_in_map(target_map_id)

        event_id = 800000 + rand(99999)

        get_released_pokemon[target_map_id] ||= []
        if get_released_pokemon[target_map_id].length >= 1
          AnilLanRework.log("Release to overworld skipped: map #{target_map_id} already has a released pokemon.") rescue nil
          return nil
        end
        get_released_pokemon[target_map_id] << {
          :id => event_id,
          :pokemon => pokemon,
          :x => dest_x,
          :y => dest_y,
          # Marca a hora de soltura: e o que permite o TTL de 24h. Antes o
          # servidor zerava tudo de hora em hora por nao saber a idade.
          :released_at => Time.now.to_i
        }

        # Se o mapa de destino for o mesmo atual em que estamos, spawna fisicamente na tela na hora!
        if target_map_id == $game_map.map_id
          spawn_local_poke_event(event_id, pokemon, dest_x, dest_y)
        end

        # Transmissão de rede coop (sincroniza o spawn em tempo real na rota de destino)
        if AnilLanRework.connected?
          serialized_poke = [Marshal.dump(pokemon)].pack("m0")
          AnilLanRework.connection.send_packet("released_roaming_pokemon_spawn", {
            "map_id" => target_map_id,
            "event_id" => event_id,
            "pokemon_blob" => serialized_poke,
            "x" => dest_x,
            "y" => dest_y,
            # Sem isto o outro lado carimbaria a hora de RECEBIMENTO, e o TTL
            # de 24h reiniciaria a cada jogador que entrasse no mapa.
            "released_at" => Time.now.to_i
          })
        end

        return target_map_id
      rescue => e
        AnilLanRework.log("Erro em release_pokemon_to_overworld: #{e.message}") rescue nil
        return nil
      end
    end

    def interact_roaming_pokemon(event_id)
      return unless $game_map
      begin
        event = $game_map.events[event_id]
        return unless event
        return if event.instance_variable_get(:@temp_disabled)

        map_id = $game_map.map_id
        pokes = get_released_pokemon[map_id] || []
        poke_data = pokes.find { |p| p[:id] == event_id }
        return unless poke_data
        return if poke_data[:locked]

        pokemon = poke_data[:pokemon]
        return unless pokemon

        # Grito da espécie
        pokemon.play_cry rescue nil

        nickname_text = pokemon.name
        if pokemon.name != pokemon.speciesName
          nickname_text = "#{pokemon.name} (#{pokemon.speciesName})"
        end

        if pbConfirmMessage(_INTL("Você encontrou um \\c[1]{1}\\c[0] abandonado! Deseja capturá-lo?", nickname_text))
          # Bloqueia o pokemon na rede para evitar dupla interação
          poke_data[:locked] = true
          if AnilLanRework.connected?
            AnilLanRework.connection.send_packet("released_roaming_pokemon_lock", {
              "map_id" => map_id,
              "event_id" => event_id,
              "lock" => true
            }) rescue nil
          end

          event.turn_toward_player rescue nil
          outcome = WildBattle.start_core(pokemon)

          if outcome == 1 || outcome == 4
            # Derrotado ou capturado!
            remove_released_roaming_pokemon(event_id)

            if AnilLanRework.connected?
              AnilLanRework.connection.send_packet("released_roaming_pokemon_remove", {
                "map_id" => map_id,
                "event_id" => event_id
              }) rescue nil
            end
          else
            # Fugiu ou perdeu, desbloqueia na rede
            poke_data[:locked] = false
            if AnilLanRework.connected?
              AnilLanRework.connection.send_packet("released_roaming_pokemon_lock", {
                "map_id" => map_id,
                "event_id" => event_id,
                "lock" => false
              }) rescue nil
            end
          end
        end
      rescue => e
        AnilLanRework.log("Erro ao interagir com pokemon solto: #{e.message}") rescue nil
      end
    end

    def remove_released_roaming_pokemon(event_id)
      return unless $game_map
      begin
        event = $game_map.events[event_id]

        map_data = $game_map.instance_variable_get(:@map) rescue nil
        if map_data && map_data.respond_to?(:events)
          map_data.events.delete(event_id)
        end

        if $game_map.respond_to?(:removeThisEventfromMap)
          $game_map.removeThisEventfromMap(event_id)
        else
          $game_map.events.delete(event_id)
        end

        if event && $scene.is_a?(Scene_Map) && $scene.respond_to?(:spritesets)
          spriteset = $scene.spritesets[$game_map.map_id] rescue nil
          spriteset ||= $scene.spritesets.values.find { |s| s.respond_to?(:map) && s.map == $game_map } rescue nil
          if spriteset && spriteset.respond_to?(:character_sprites)
            sprite_idx = spriteset.character_sprites.index { |s| s.respond_to?(:character) && s.character == event }
            if sprite_idx
              sprite = spriteset.character_sprites.delete_at(sprite_idx)
              sprite.dispose if sprite rescue nil
            end
          end
        end

        map_id = $game_map.map_id
        get_released_pokemon[map_id] ||= []
        get_released_pokemon[map_id].delete_if { |p| p[:id] == event_id }
      rescue => e
        AnilLanRework.log("Erro ao remover pokemon solto: #{e.message}") rescue nil
      end
    end
  end
end

module AnilLanRework
  module Router
    class << self
      alias anil_released_roaming_route_packet route_packet unless method_defined?(:anil_released_roaming_route_packet)

      def route_packet(packet)
        packet_type = packet["type"].to_s
        case packet_type
        when "clear_released_roaming_pokemon"
          begin
            # "cutoff" e o TTL vindo do servidor (unix time). Com ele, expira-se
            # SO quem passou das 24h; sem ele (servidor antigo) limpa-se tudo,
            # que era o comportamento anterior.
            cutoff = packet["cutoff"].to_i
            ids_expirados = nil

            if cutoff > 0
              dados         = ($PokemonGlobal.released_roaming_pokemon ||= {})
              restante      = {}
              ids_expirados = []
              mapa_atual    = ($game_map ? $game_map.map_id : nil)
              dados.each do |map_id, lista|
                vivos = Array(lista).select do |entrada|
                  ts = (entrada.is_a?(Hash) ? entrada[:released_at].to_i : 0)
                  vivo = (ts > 0 && ts > cutoff)
                  if !vivo && entrada.is_a?(Hash) && map_id == mapa_atual
                    ids_expirados << entrada[:id]
                  end
                  vivo
                end
                restante[map_id] = vivos unless vivos.empty?
              end
              $PokemonGlobal.released_roaming_pokemon = restante
            else
              $PokemonGlobal.released_roaming_pokemon = {}
            end

            if $game_map
              local_roaming_event_ids = $game_map.events.keys.select { |id| id >= 800000 && id < 900000 }
              # Na expiracao seletiva, so somem da tela os que venceram.
              local_roaming_event_ids &= ids_expirados if ids_expirados
              local_roaming_event_ids.each do |ev_id|
                map_data = $game_map.instance_variable_get(:@map) rescue nil
                if map_data && map_data.respond_to?(:events)
                  map_data.events.delete(ev_id)
                end
                if $game_map.respond_to?(:removeThisEventfromMap)
                  $game_map.removeThisEventfromMap(ev_id) rescue nil
                else
                  $game_map.events.delete(ev_id)
                end
              end
              # Reconstruir spriteset e caro e da engasgo visivel. A varredura
              # agora roda de hora em hora e quase sempre nao expira nada, entao
              # so se refaz a cena quando algum evento realmente saiu.
              if !local_roaming_event_ids.empty? &&
                 $scene.is_a?(Scene_Map) && $scene.respond_to?(:disposeSpritesets) && $scene.respond_to?(:createSpritesets)
                $scene.disposeSpritesets rescue nil
                $scene.createSpritesets rescue nil
              end
            end
            if ids_expirados
              AnilLanRework.log("Pokemon soltos expirados removidos: #{ids_expirados.length}.") rescue nil
            else
              AnilLanRework.log("Todos os Pokemon soltos foram limpos por ordem do servidor.") rescue nil
            end
          rescue => e
            AnilLanRework.log("Erro ao limpar Pokemon soltos por comando do servidor: #{e.message}") rescue nil
          end
          return

        when "request_released_roaming_pokemon"
          begin
            map_id = packet["map_id"].to_i
            pokes = $PokemonGlobal.released_roaming_pokemon[map_id] || []

            serialized_pokes = pokes.map do |p|
              {
                "id" => p[:id],
                "pokemon_blob" => [Marshal.dump(p[:pokemon])].pack("m0"),
                "x" => p[:x],
                "y" => p[:y],
                "locked" => p[:locked] ? true : false,
                "released_at" => p[:released_at].to_i
              }
            end

            if AnilLanRework.connected?
              AnilLanRework.connection.send_packet("sync_released_roaming_pokemon", {
                "map_id" => map_id,
                "pokes" => serialized_pokes
              }) rescue nil
            end
          rescue => e
            AnilLanRework.log("Erro no route request_released_roaming_pokemon: #{e.message}") rescue nil
          end
          return

        when "sync_released_roaming_pokemon"
          begin
            map_id = packet["map_id"].to_i
            pokes = packet["pokes"] || []

            $PokemonGlobal.released_roaming_pokemon ||= {}
            existing_pokes = $PokemonGlobal.released_roaming_pokemon[map_id] || []

            pokes.each do |new_poke|
              parsed_id = new_poke["id"].to_i
              exists = existing_pokes.any? { |p| p[:id] == parsed_id }
              unless exists
                if existing_pokes.length >= 1
                  AnilLanRework.log("Released roaming sync ignored on map #{map_id}: limit of 1 reached.") rescue nil
                  next
                end
                pokemon_obj = Marshal.load(new_poke["pokemon_blob"].unpack("m0")[0]) rescue nil
                if pokemon_obj
                  existing_pokes << {
                    :id => parsed_id,
                    :pokemon => pokemon_obj,
                    :x => new_poke["x"].to_i,
                    :y => new_poke["y"].to_i,
                    :locked => new_poke["locked"] ? true : false,
                    # Peer antigo nao manda released_at: assume agora, senao a
                    # entrada nasceria ja vencida do lado de quem recebe.
                    :released_at => (new_poke["released_at"].to_i > 0 ? new_poke["released_at"].to_i : Time.now.to_i)
                  }
                end
              end
            end

            $PokemonGlobal.released_roaming_pokemon[map_id] = existing_pokes

            if $game_map && $game_map.map_id == map_id
              local_roaming_event_ids = $game_map.events.keys.select { |id| id >= 800000 && id < 900000 }
              local_roaming_event_ids.each do |ev_id|
                event = $game_map.events[ev_id]
                map_data = $game_map.instance_variable_get(:@map) rescue nil
                if map_data && map_data.respond_to?(:events)
                  map_data.events.delete(ev_id)
                end
                if $game_map.respond_to?(:removeThisEventfromMap)
                  $game_map.removeThisEventfromMap(ev_id)
                else
                  $game_map.events.delete(ev_id)
                end
                if event && $scene.is_a?(Scene_Map) && $scene.respond_to?(:spritesets)
                  spriteset = $scene.spritesets[$game_map.map_id] rescue nil
                  spriteset ||= $scene.spritesets.values.find { |s| s.respond_to?(:map) && s.map == $game_map } rescue nil
                  if spriteset && spriteset.respond_to?(:character_sprites)
                    sprite_idx = spriteset.character_sprites.index { |s| s.respond_to?(:character) && s.character == event }
                    if sprite_idx
                      sprite = spriteset.character_sprites.delete_at(sprite_idx)
                      sprite.dispose if sprite rescue nil
                    end
                  end
                end
              end

              AnilLanRework::ReleasedRoaming.spawn_all_for_current_map($game_map)
            end
          rescue => e
            AnilLanRework.log("Erro no route sync_released_roaming_pokemon: #{e.message}") rescue nil
          end
          return

        when "released_roaming_pokemon_spawn"
          begin
            map_id = packet["map_id"].to_i
            event_id = packet["event_id"].to_i
            x = packet["x"].to_i
            y = packet["y"].to_i

            $PokemonGlobal.released_roaming_pokemon ||= {}
            $PokemonGlobal.released_roaming_pokemon[map_id] ||= []

            exists = $PokemonGlobal.released_roaming_pokemon[map_id].any? { |p| p[:id] == event_id }
            unless exists
              if $PokemonGlobal.released_roaming_pokemon[map_id].length >= 1
                AnilLanRework.log("Released roaming spawn ignored on map #{map_id}: limit of 1 reached.") rescue nil
                return
              end
              pokemon_obj = Marshal.load(packet["pokemon_blob"].unpack("m0")[0]) rescue nil
              if pokemon_obj
                $PokemonGlobal.released_roaming_pokemon[map_id] << {
                  :id => event_id,
                  :pokemon => pokemon_obj,
                  :x => x,
                  :y => y,
                  :released_at => (packet["released_at"].to_i > 0 ? packet["released_at"].to_i : Time.now.to_i)
                }
                if $game_map && $game_map.map_id == map_id
                  AnilLanRework::ReleasedRoaming.spawn_local_poke_event(event_id, pokemon_obj, x, y)
                end
              end
            end
          rescue => e
            AnilLanRework.log("Erro no roteamento released_roaming_pokemon_spawn: #{e.message}") rescue nil
          end
          return

        when "released_roaming_pokemon_remove"
          begin
            map_id = packet["map_id"].to_i
            event_id = packet["event_id"].to_i

            if $game_map && $game_map.map_id == map_id
              AnilLanRework::ReleasedRoaming.remove_released_roaming_pokemon(event_id)
            else
              $PokemonGlobal.released_roaming_pokemon ||= {}
              pokes = $PokemonGlobal.released_roaming_pokemon[map_id] || []
              pokes.delete_if { |p| p[:id] == event_id }
            end
          rescue => e
            AnilLanRework.log("Erro no roteamento released_roaming_pokemon_remove: #{e.message}") rescue nil
          end
          return

        when "released_roaming_pokemon_lock"
          begin
            map_id = packet["map_id"].to_i
            event_id = packet["event_id"].to_i
            is_locked = packet["lock"] ? true : false

            $PokemonGlobal.released_roaming_pokemon ||= {}
            pokes = $PokemonGlobal.released_roaming_pokemon[map_id] || []
            poke_data = pokes.find { |p| p[:id] == event_id }
            if poke_data
              poke_data[:locked] = is_locked
            end

            if $game_map && $game_map.map_id == map_id
              event = $game_map.events[event_id]
              if event
                if is_locked
                  event.opacity = 0
                  event.through = true
                  event.instance_variable_set(:@temp_disabled, true)
                else
                  event.opacity = 255
                  event.through = false
                  event.instance_variable_set(:@temp_disabled, false)
                end
              end
            end
          rescue => e
            AnilLanRework.log("Erro no roteamento released_roaming_pokemon_lock: #{e.message}") rescue nil
          end
          return
        end

        anil_released_roaming_route_packet(packet)
      end
    end
  end
end
