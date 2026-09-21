#===============================================================================
# MOD: 070_Multiplayer_OW_Spawns_Sync
#===============================================================================
# Sincroniza em tempo real os encontros selvagens visíveis no mapa (plugin VOE)
# entre jogadores conectados na mesma sessão LAN/Online.
#===============================================================================

$vower_sync_spawning = false
$vower_pending_spawn_id = nil
$vower_pending_actions = []

#===============================================================================
# Cache O(1) de Spawns para Evitar Varredura no Loop de Movimento/Despawn
#===============================================================================
module AnilLanRework
  module VowerWildSync
    @spawn_to_event = {}

    # Posicoes dos outros jogadores no mapa atual, calculadas UMA vez por frame.
    # Antes cada spawn selvagem varria AnilLanRework.players por conta propria a
    # cada frame (O(spawns x jogadores)); com 8 spawns/jogador isso cresce
    # quadratico com a lotacao do mapa.
    def self.peer_positions_for_current_map
      cf = Graphics.frame_count rescue 0
      return @peer_pos_cache if @peer_pos_frame == cf && @peer_pos_cache
      @peer_pos_frame = cf
      lista = []
      begin
        current_map = $game_map ? $game_map.map_id : nil
        meu_id = AnilLanRework.self_internal_id.to_s
        if current_map && AnilLanRework.connected?
          AnilLanRework.players.each_value do |peer|
            next if peer.internal_id.to_s == meu_id
            next if peer.map_id != current_map
            next if peer.x.nil? || peer.y.nil?
            lista << [peer.x, peer.y]
          end
        end
      rescue
      end
      @peer_pos_cache = lista
    end

    def self.clear_cache
      @spawn_to_event.clear
    end

    def self.register_spawn(spawn_id, event_id)
      @spawn_to_event[spawn_id.to_s] = event_id
    end

    def self.unregister_spawn(spawn_id)
      @spawn_to_event.delete(spawn_id.to_s)
    end

    def self.get_event_id(spawn_id)
      @spawn_to_event[spawn_id.to_s]
    end
  end
end

class Game_Map
  alias vower_sync_original_setup setup unless method_defined?(:vower_sync_original_setup)
  def setup(map_id)
    AnilLanRework::VowerWildSync.clear_cache rescue nil
    vower_sync_original_setup(map_id)
  end
end

#===============================================================================
# Aplicação de Patches Pós-Carregamento dos Plugins
#===============================================================================
module AnilLanRework
  class << self
    alias vower_sync_apply_post_plugin_patches apply_post_plugin_patches unless defined?(vower_sync_apply_post_plugin_patches)

    def apply_post_plugin_patches
      vower_sync_apply_post_plugin_patches
      
      begin
        # 0. Correção de segurança para pbCheckBattleAllowed (evita crash quando encounter_type é nil)
        Object.class_eval do
          if defined?(pbCheckBattleAllowed)
            alias vower_sync_original_pbCheckBattleAllowed pbCheckBattleAllowed unless defined?(vower_sync_original_pbCheckBattleAllowed)

            def pbCheckBattleAllowed
              if $game_temp && $game_temp.encounter_type
                encType = GameData::EncounterType.try_get($game_temp.encounter_type) rescue nil
                if encType
                  return false if !$PokemonGlobal.surfing && encType.type == :water && VisibleEncounterSettings::BATTLE_WATER_FROM_SHORE == false
                  return true
                end
              end
              return true
            end
          end
        end

        # 1. Patches dinâmicos para Game_PokeEvent (Sincronização de Movimento e Animação)
        if defined?(Game_PokeEvent)
          Game_PokeEvent.class_eval do
            alias vower_sync_character_update update unless method_defined?(:vower_sync_character_update)
            alias vower_sync_removeThisEventfromMap removeThisEventfromMap unless method_defined?(:vower_sync_removeThisEventfromMap)

            def removeThisEventfromMap
              spawn_id = self.instance_variable_get(:@vower_spawn_id)
              is_local = self.instance_variable_get(:@vower_local_spawn)

              if spawn_id && is_local && AnilLanRework.connected? && !self.instance_variable_get(:@vower_despawn_sent)
                self.instance_variable_set(:@vower_despawn_sent, true)
                AnilLanRework.connection.send_packet("vower_wild_despawn", {
                  "spawn_id" => spawn_id,
                  "map_id"   => ($game_map.map_id rescue 0)
                }) rescue nil
              end

              if spawn_id
                AnilLanRework::VowerWildSync.unregister_spawn(spawn_id) rescue nil
              end

              vower_sync_removeThisEventfromMap
            end

            def vower_near_any_player?
              return false unless $game_player
              return false if self.x.nil? || self.y.nil? || $game_player.x.nil? || $game_player.y.nil?
              # 1. Verifica jogador local primeiro (caso mais comum)
              return true if (self.x - $game_player.x).abs <= 22 && (self.y - $game_player.y).abs <= 22
              
              # 2. Verifica outros jogadores na rede no mesmo mapa
              # (lista pre-computada uma vez por frame e compartilhada entre
              #  todos os spawns — ver peer_positions_for_current_map)
              if AnilLanRework.connected?
                AnilLanRework::VowerWildSync.peer_positions_for_current_map.each do |px, py|
                  return true if (self.x - px).abs <= 22 && (self.y - py).abs <= 22
                end
              end
              false
            end

            def update
              start_t = (defined?(AnilProfiler) && AnilProfiler.enabled) ? System.uptime : nil
              begin
                # Culling de distância: se estiver longe de todos os jogadores, não atualiza!
                return unless vower_near_any_player?

                spawn_id = self.instance_variable_get(:@vower_spawn_id)
                is_local = self.instance_variable_get(:@vower_local_spawn)

                # Se estamos conectados e NÃO somos o "dono" deste spawn:
                if spawn_id && AnilLanRework.connected? && !is_local
                  # Rodar a lógica de interpolação passiva (sem movimentação autônoma do VOE local)
                  AnilLanRework::VowerWildSync.interpolate_wild!(self)
                else
                  # Se somos o dono (ou offline), rodamos a movimentação nativa do VOE
                  old_x = self.x
                  old_y = self.y
                  old_dir = self.direction
                  old_pat = self.pattern

                  vower_sync_character_update

                  # E transmitimos o movimento a cada passo real na rede (ignora rotação in-place para reduzir flood)
                  if (self.x != old_x || self.y != old_y) && AnilLanRework.connected? && AnilLanRework.multiplayer_map?($game_map.map_id)
                    if spawn_id && is_local
                      real_res_x = (Game_Map::REAL_RES_X rescue 128)
                      real_res_y = (Game_Map::REAL_RES_Y rescue 128)
                      AnilLanRework.connection.send_packet("vower_wild_move", {
                        "spawn_id" => spawn_id,
                        "map_id"   => $game_map.map_id,
                        "x"        => self.x,
                        "y"        => self.y,
                        "real_x"   => self.x * real_res_x,
                        "real_y"   => self.y * real_res_y,
                        "dir"      => self.direction,
                        "pattern"  => self.pattern
                      }) rescue nil
                    end
                  end
                end
              ensure
                if start_t
                  AnilProfiler.accumulate_spawn_time(start_t)
                end
              end
            end
          end
          AnilLanRework.log("[POST-PLUGIN] Monkeypatch em Game_PokeEvent para sincronização de movimentos aplicado com sucesso!") rescue nil
        end

        # 2. Patches dinâmicos para pbPlaceEncounter (Spawns e Controles de Dono/Passivo)
        AnilLanRework.log("[POST-PLUGIN] VowerSync: Game_PokeEvent definido? #{defined?(Game_PokeEvent) ? 'SIM' : 'NAO'}") rescue nil
        AnilLanRework.log("[POST-PLUGIN] VowerSync: pbPlaceEncounter definido? #{defined?(pbPlaceEncounter) ? 'SIM' : 'NAO'}") rescue nil
        AnilLanRework.log("[POST-PLUGIN] VowerSync: Object.respond_to?(:pbPlaceEncounter, true)? #{Object.respond_to?(:pbPlaceEncounter, true) ? 'SIM' : 'NAO'}") rescue nil
        AnilLanRework.log("[POST-PLUGIN] VowerSync: Object.method_defined?(:pbPlaceEncounter)? #{Object.method_defined?(:pbPlaceEncounter) ? 'SIM' : 'NAO'}") rescue nil
        AnilLanRework.log("[POST-PLUGIN] VowerSync: Object.private_method_defined?(:pbPlaceEncounter)? #{Object.private_method_defined?(:pbPlaceEncounter) ? 'SIM' : 'NAO'}") rescue nil
        if defined?(pbPlaceEncounter) || Object.private_method_defined?(:pbPlaceEncounter) || Object.method_defined?(:pbPlaceEncounter)
          Object.class_eval do
            # Interceptador para Criação de Spawn no Mapa
            alias vower_sync_pbPlaceEncounter pbPlaceEncounter unless defined?(vower_sync_pbPlaceEncounter)

            def pbPlaceEncounter(x, y, pokemon)
              if AnilLanRework.connected? && $game_map && AnilLanRework.multiplayer_map?($game_map.map_id)
                if $vower_sync_spawning
                  # Spawn vindo da rede: apenas cria o evento localmente
                  vower_sync_pbPlaceEncounter(x, y, pokemon)
                  if $vower_pending_spawn_id
                    map_obj = ($map_factory ? $map_factory.getMap($game_map.map_id) : $game_map) rescue $game_map
                    new_event_id = map_obj.events.keys.max
                    if new_event_id && map_obj.events[new_event_id].is_a?(Game_PokeEvent)
                      event = map_obj.events[new_event_id]
                      event.instance_variable_set(:@vower_spawn_id, $vower_pending_spawn_id)
                      event.instance_variable_set(:@vower_local_spawn, false)
                      # Registro no Cache O(1)
                      AnilLanRework::VowerWildSync.register_spawn($vower_pending_spawn_id, new_event_id)
                      
                      # Como este spawn NÃO pertence a este jogador, desabilita a movimentação nativa local
                      event.event.pages[0].move_type = 0 rescue nil
                      event.instance_variable_set(:@move_type, 0) rescue nil
                      if event.event.pages[0].move_route
                        event.event.pages[0].move_route.list = [RPG::MoveCommand.new] rescue nil
                        event.event.pages[0].move_route.repeat = false rescue nil
                      end
                      event.instance_variable_set(:@move_route, RPG::MoveRoute.new) rescue nil
                    end
                  end
                else
                  # Spawn gerado localmente pelo passo do jogador:
                  # Gera um UUID de spawn único e transmite para a rede
                  self_id = AnilLanRework.self_internal_id.to_s
                  spawn_id = "#{self_id}_#{Time.now.to_f}_#{rand(9999)}"
                  
                  # Cria localmente. O dono mantém a movimentação nativa do VOE ativa (chase/random)
                  vower_sync_pbPlaceEncounter(x, y, pokemon)
                  map_obj = ($map_factory ? $map_factory.getMap($game_map.map_id) : $game_map) rescue $game_map
                  new_event_id = map_obj.events.keys.max
                  if new_event_id && map_obj.events[new_event_id].is_a?(Game_PokeEvent)
                    event = map_obj.events[new_event_id]
                    event.instance_variable_set(:@vower_spawn_id, spawn_id)
                    event.instance_variable_set(:@vower_local_spawn, true)
                    # Registro no Cache O(1)
                    AnilLanRework::VowerWildSync.register_spawn(spawn_id, new_event_id)
                  end

                  # Transmite para os outros jogadores do mapa
                  AnilLanRework.connection.send_packet("vower_wild_spawn", {
                    "spawn_id"    => spawn_id,
                    "map_id"      => $game_map.map_id,
                    "x"           => x,
                    "y"           => y,
                    "species"     => pokemon.species.to_s,
                    "level"       => pokemon.level,
                    "form"        => pokemon.form,
                    "gender"      => pokemon.gender,
                    "shiny"       => pokemon.shiny? ? true : false,
                    "super_shiny" => pokemon.super_shiny? ? true : false,
                    "nature"      => pokemon.nature.to_s,
                    "ability"     => pokemon.ability.to_s
                  }) rescue nil
                end
              else
                # Modo Offline convencional
                #
                # ⚠️ ESTE RAMO NAO ANUNCIA NADA A REDE.
                #
                # Entra-se aqui quando nao ha ligacao OU quando o mapa nao esta
                # na lista de multijogador. Nos dois casos o spawn e so teu e
                # mais ninguem o ve — o que explica a queixa de "os outros nao
                # veem os meus Pokemon" sem haver defeito nenhum no sorteio.
                #
                # Fica registado qual das duas condicoes falhou, porque a olho
                # elas sao indistinguiveis.
                (AnilLogShiny.escrever("#{AnilLogShiny.hora} [local] "                   "#{pokemon.species.to_s} NAO anunciado a rede "                   "(ligado=#{AnilLanRework.connected? ? 1 : 0} "                   "mapa_mp=#{($game_map && AnilLanRework.multiplayer_map?($game_map.map_id)) ? 1 : 0} "                   "mapa=#{($game_map.map_id rescue 0)})") rescue nil)
                vower_sync_pbPlaceEncounter(x, y, pokemon)
              end
            end

            # Interceptador de Captura/Início de Batalha (Despawn imediato para outros)
            alias vower_sync_pbSingleOrDoubleWildBattle pbSingleOrDoubleWildBattle unless defined?(vower_sync_pbSingleOrDoubleWildBattle)

            def pbSingleOrDoubleWildBattle(map_id, x, y, pokemon)
              if AnilLanRework.connected? && $game_map && AnilLanRework.multiplayer_map?(map_id)
                matched_event = nil
                for event in $game_map.events.values
                  if event.is_a?(Game_PokeEvent) && (event.pokemon == pokemon || (event.x == x && event.y == y))
                    matched_event = event
                    break
                  end
                end
                
                if matched_event
                  spawn_id = matched_event.instance_variable_get(:@vower_spawn_id)
                  if spawn_id && !matched_event.instance_variable_get(:@vower_despawn_sent)
                    matched_event.instance_variable_set(:@vower_despawn_sent, true)
                    # Transmite despawn imediato antes de prosseguir com a batalha local
                    AnilLanRework.connection.send_packet("vower_wild_despawn", {
                      "spawn_id" => spawn_id,
                      "map_id"   => map_id
                    }) rescue nil
                  end

                  # Se somos o cliente remoto (não somos o dono do spawn),
                  # podemos remover o evento localmente imediatamente para não ficar visível na transição
                  is_local = matched_event.instance_variable_get(:@vower_local_spawn)
                  if !is_local
                    map_obj = ($map_factory ? $map_factory.getMap(map_id) : $game_map) rescue $game_map
                    map_obj.removeThisEventfromMap(matched_event.id) rescue nil
                  end
                end
              end
              
              vower_sync_pbSingleOrDoubleWildBattle(map_id, x, y, pokemon)
            end

            # Densidade de Spawns: Limite no Multiplayer para Evitar Saturação
            alias vower_sync_pbSpawnOnStepTaken pbSpawnOnStepTaken unless defined?(vower_sync_pbSpawnOnStepTaken)

            def pbSpawnOnStepTaken(repel_active)
              if AnilLanRework.connected? && $game_map && AnilLanRework.multiplayer_map?($game_map.map_id)
                # No multiplayer, limitamos a no máximo 6 Pokémon selvagens no mesmo mapa
                # para evitar congestionamento de pacotes por múltiplos jogadores andando.
                current_spawns = 0
                if $game_map
                  current_spawns = $game_map.events.values.count { |e| e.is_a?(Game_PokeEvent) } rescue 0
                end
                return if current_spawns >= 6
              end
              vower_sync_pbSpawnOnStepTaken(repel_active)
            end
          end

          # Override nil-safe para pbTileIsPossible (evita NoMethodError '-' for NilClass ao andar no overworld)
          if defined?(pbTileIsPossible) && !defined?(voe_nilsafe_pbTileIsPossible)
            alias voe_nilsafe_pbTileIsPossible pbTileIsPossible
            def pbTileIsPossible(x, y)
              return false unless $game_map && $game_map.valid?(x, y)
              tile_terrain_tag = $game_map.terrain_tag(x, y)
              return false unless tile_terrain_tag

              for event in $game_map.events.values
                next unless event
                return false if event.x == x && event.y == y
              end

              for wildpokes in $game_map.events.values
                next unless wildpokes && wildpokes.is_a?(Game_PokeEvent)
                wx = wildpokes.x
                wy = wildpokes.y
                next if wx.nil? || wy.nil?
                return false if (wx - x).abs <= 1 || (wy - y).abs <= 1
              end

              true
            end
          end

          # 3. Patches para Despawn Natural / Remoção de Eventos pós-plugins
          Game_Map.class_eval do
            if method_defined?(:spawnPokeEvent)
              alias vower_sync_original_spawnPokeEvent spawnPokeEvent unless method_defined?(:vower_sync_original_spawnPokeEvent)

              def spawnPokeEvent(x, y, pokemon)
                if $vower_sync_spawning
                  # Preserva os atributos shiny e super_shiny recebidos do pacote
                  backup_shiny = pokemon.shiny?
                  backup_super_shiny = pokemon.super_shiny?

                  # ⚠️ O plugin sorteia outra vez e canta o resultado DELE.
                  #
                  # Num spawn remoto o shiny ja foi decidido no dono; o sorteio
                  # que corre aqui dentro nao vale nada e o clarao que ele toca
                  # e uma mentira. Cala-se durante a criacao — ver o MOD 168.
                  AnilAnuncioSpawn.calado do
                    vower_sync_original_spawnPokeEvent(x, y, pokemon)
                  end
                  
                  # Restaura-os no Pokémon recém-criado
                  pokemon.shiny = backup_shiny
                  pokemon.super_shiny = backup_super_shiny
                  # O shiny de um spawn remoto foi decidido no dono dele; aqui
                  # so se copia. Fica registado para nao contar como escape.
                  (AnilLogShiny.saltado!("remoto", pokemon.species.to_s,
                    "veio do pacote: #{backup_shiny ? 'shiny' : 'normal'}") rescue nil)

                  # Agora sim, com o estado verdadeiro.
                  anunciar_shiny_no_mapa_por_id(@events.keys.max, pokemon)
                  
                  # Força a atualização do sprite e da tonalidade do evento recém-spawnado
                  new_event_id = @events.keys.max
                  if new_event_id && @events[new_event_id].is_a?(Game_PokeEvent)
                    event = @events[new_event_id]
                    graphic_form = (VisibleEncounterSettings::SPRITES[0] && pokemon.form != nil) ? pokemon.form : 0
                    graphic_gender = (VisibleEncounterSettings::SPRITES[1] && pokemon.gender != nil) ? pokemon.gender : 0
                    # ⚠️ SUPER SHINY USA O SPRITE NORMAL, NAO O SHINY.
                    #
                    # O plugin faz `... && !pokemon.super_shiny?` (linha 1465 do
                    # VOE script): o super shiny distingue-se pelo HUE aplicado
                    # por cima do sprite normal. Escolher o sprite shiny E poe-lo
                    # com o hue do super dava uma cor que nao e nenhuma das duas.
                    graphic_shiny = (VisibleEncounterSettings::SPRITES[2] && !pokemon.super_shiny?) ? (pokemon.shiny? ? true : false) : false
                    
                    fname = ow_sprite_filename(pokemon.species.to_s, graphic_form, graphic_gender, graphic_shiny) rescue nil
                    if fname
                      fname.gsub!("Graphics/Characters/", "")
                      event.event.pages[0].graphic.character_name = fname
                      event.character_name = fname rescue nil
                    end
                    
                    if pokemon.super_shiny?
                      event.event.pages[0].graphic.character_hue = pokemon.super_shiny_hue
                      event.character_hue = pokemon.super_shiny_hue rescue nil
                    end
                  end
                else
                  # ⚠️ O PLUGIN APAGA O SHINY QUE JA TINHA SIDO SORTEADO.
                  #
                  # O spawnPokeEvent do VOE comeca por fazer
                  #     pokemon.shiny = false ; pokemon.super_shiny = false
                  # e so depois decide sozinho. Isso deitava fora o resultado do
                  # sorteio do Essentials — e portanto as duas tentativas extra
                  # que o amuleto da la, e tambem o efeito do /event shiny, que
                  # mexe no Settings::SHINY_POKEMON_CHANCE e em mais nada.
                  #
                  # O ramo de cima (spawns REMOTOS) ja fazia este backup; o ramo
                  # local nao, e era justamente o que decide os encontros do
                  # proprio jogador.
                  #
                  # Guarda-se ANTES e repoe-se DEPOIS por OU: fica shiny se
                  # qualquer um dos dois sorteios tiver dado. Nunca se escreve
                  # false, senao apagava-se o sorteio do proprio plugin.
                  # ⚠️ UM SORTEIO SO, E O ULTIMO A FALAR.
                  #
                  # Aqui corriam TRES sorteios sobre o mesmo bicho: o do
                  # Essentials (que eu passei a preservar), o do plugin, e uma
                  # "compensacao" calculada contra o do plugin sozinho. Juntavam
                  # -se por OU, portanto somavam: 1 em 2511 sem cadeia nenhuma,
                  # 1 em 1005 com amuleto. O esperado era 1 em 5000 e 1 em 2500.
                  #
                  # Agora o estado final sai de UM sorteio, ao alvo efectivo —
                  # que ja e o melhor entre o Essentials e a cadeia. Ver o
                  # alvo_efectivo no MOD 135.
                  #
                  # O forcado? le-se ANTES: o plugin consome os interruptores.
                  forcado = (AnilCadeiaCoop.forcado? rescue false)

                  # ⚠️ Calado enquanto ele cria: o anuncio dele sai do sorteio
                  # dele, e o nosso ainda nem correu. Ver o MOD 168.
                  AnilAnuncioSpawn.calado do
                    vower_sync_original_spawnPokeEvent(x, y, pokemon)
                  end

                  # o que o PLUGIN decidiu, e com que ja escolheu o sprite
                  pintado_shiny = (pokemon.shiny? rescue false)
                  pintado_super = (pokemon.super_shiny? rescue false)

                  if forcado
                    (AnilLogShiny.saltado!("local", pokemon.species.to_s,
                      "forcado por interruptor (shinyzador/evento)") rescue nil)
                  else
                    alvo = (AnilCadeiaCoop.alvo_efectivo(pokemon.species) rescue 5000).to_i
                    alvo = 1 if alvo < 1
                    if rand(alvo) == 0
                      pokemon.shiny = true
                      pokemon.super_shiny = (rand(3) == 0)
                    else
                      pokemon.shiny = false
                      pokemon.super_shiny = false
                    end
                    (AnilLogShiny.sorteio!("local", pokemon.species.to_s, alvo,
                      pokemon.shiny?) rescue nil)
                  end

                  # ⚠️ SO SE REPINTA QUANDO O SPRITE FICOU ERRADO.
                  #
                  # O plugin ja escolheu o grafico com o shiny DELE. Se a nossa
                  # decisao for outra — nos dois sentidos, e nao so a ligar — o
                  # evento fica a mostrar uma coisa e o Pokemon a ser outra.
                  if pintado_shiny != (pokemon.shiny? rescue false) ||
                     pintado_super != (pokemon.super_shiny? rescue false)
                    vower_sync_repintar_shiny(pokemon)
                  end

                  # ⚠️ O ANUNCIO SAIU DO REPINTAR.
                  #
                  # Estava la dentro, e o repintar so corre quando a nossa
                  # decisao DIFERE da do plugin. Um shiny em que os dois
                  # concordassem passava sem clarao nenhum. Agora anuncia-se
                  # pelo estado final, uma vez, aconteca o que acontecer antes.
                  anunciar_shiny_no_mapa_por_id(@events.keys.max, pokemon)
                end
              end

              # Repoe o sprite e o tom do evento acabado de criar, para o mapa
              # mostrar o que o Pokemon realmente e. Mesma logica do ramo remoto.
              def vower_sync_repintar_shiny(pokemon)
                novo_id = @events.keys.max
                return unless novo_id && @events[novo_id].is_a?(Game_PokeEvent)
                event = @events[novo_id]
                g_form   = (VisibleEncounterSettings::SPRITES[0] && pokemon.form != nil) ? pokemon.form : 0
                g_gender = (VisibleEncounterSettings::SPRITES[1] && pokemon.gender != nil) ? pokemon.gender : 0
                # Mesma regra do plugin: o super shiny vai de sprite normal
                # com hue, nunca de sprite shiny (ver a nota no ramo remoto).
                g_shiny  = (VisibleEncounterSettings::SPRITES[2] && !pokemon.super_shiny?) ? (pokemon.shiny? ? true : false) : false
                fname = ow_sprite_filename(pokemon.species.to_s, g_form, g_gender, g_shiny) rescue nil
                if fname
                  fname = fname.gsub("Graphics/Characters/", "")
                  event.event.pages[0].graphic.character_name = fname
                  event.character_name = fname rescue nil
                end
                # ⚠️ O TOM TEM DE SER REPOSTO A ZERO, E NAO SO APLICADO.
                #
                # Isto passou a correr tambem quando a nossa decisao DESLIGA o
                # shiny que o plugin tinha ligado. Sem o ramo do else ficava um
                # matiz de super shiny colado a um Pokemon vulgar.
                if pokemon.super_shiny?
                  event.event.pages[0].graphic.character_hue = pokemon.super_shiny_hue
                  event.character_hue = pokemon.super_shiny_hue rescue nil
                else
                  event.event.pages[0].graphic.character_hue = 0
                  event.character_hue = 0 rescue nil
                end
                # ⚠️ O anuncio NAO se faz aqui.
                #
                # Este metodo so corre quando a decisao mudou. Quem anuncia e
                # quem decide, logo a seguir ao sorteio, para o clarao seguir
                # sempre o estado final e nunca um palpite.
              rescue => e
                AnilLanRework.log("[VOWER] repintar shiny falhou: #{e.class}: #{e.message}") rescue nil
              end

              # ⚠️ NAO EXISTIA BRILHO NEM SOM AO APARECER UM SHINY NO MAPA.
              #
              # Procurei nos plugins e nos nossos scripts: o VOE so toca a
              # animacao de farfalhar da erva (RUSTLE_NORMAL_ANIMATION_ID), igual
              # para qualquer Pokemon, e nao ha um unico som ligado a shiny em
              # todo o cliente. O que se via era apenas o SPRITE diferente — e
              # quando o sprite falhava (ou no super shiny, que usa o sprite
              # normal com hue) nao havia sinal nenhum.
              #
              # Fica aqui, no repintar, porque e o unico ponto que corre para
              # spawns proprios e recebidos, e ja depois de o shiny estar
              # decidido.
              # ⚠️ E TAMBEM SE ARRUMA O AUTO-INTERRUPTOR "D".
              #
              # O plugin poe `D = true` no evento quando o sorteio dele da
              # shiny. Como os auto-interruptores sao guardados por
              # [mapa, id_do_evento] e os ids dos spawns sao reaproveitados, um
              # falso alarme deixava um "D" ligado que passava a todos os
              # spawns futuros com aquele id naquele mapa. Repoe-se pelo estado
              # final: ligado se e mesmo shiny, desligado se nao.
              def anunciar_shiny_no_mapa_por_id(novo_id, pokemon)
                return unless novo_id && @events[novo_id].is_a?(Game_PokeEvent)
                event = @events[novo_id]
                e_shiny = (pokemon.shiny? rescue false)
                # ⚠️ So se mexe quando esta MESMO errado.
                #
                # O pbSetSelfSwitch marca o mapa para refrescar sempre que o
                # valor muda — e `nil != false` conta como mudanca. Escrever
                # `false` num evento acabado de nascer forcava um refresh do
                # mapa inteiro por cada spawn, que e exactamente o engasgo que
                # se andou a caçar no matagal.
                actual = ($game_self_switches[[@map_id, event.id, "D"]] == true)
                if actual != e_shiny
                  (pbMapInterpreter.pbSetSelfSwitch(event.id, "D", e_shiny, @map_id) rescue nil)
                end
                anunciar_shiny_no_mapa(event, pokemon) if e_shiny
              rescue => e
                AnilLanRework.log("[VOWER] anuncio de shiny falhou: #{e.class}: #{e.message}") rescue nil
              end

              def anunciar_shiny_no_mapa(event, pokemon)
                return unless $scene && $scene.respond_to?(:spriteset) && $scene.spriteset

                # ⚠️ AS ANIMACOES SAO AS 52 E 53, DO PROPRIO PLUGIN.
                #
                # O VOE ja tem o efeito certo — o mesmo da batalha, com o som
                # incluido nos frames da animacao — no fim do spawnPokeEvent:
                #
                #   if pokemon.super_shiny? then addUserAnimation(53, x, y)
                #   elsif pokemon.shiny?    then addUserAnimation(52, x, y)
                #
                # O problema e que essa decisao corre DENTRO do spawnPokeEvent,
                # e nessa altura o shiny que vem do sorteio do Essentials (ou da
                # nossa compensacao) ainda nao foi reposto — o plugin ve false e
                # nao anima nada. Aqui repete-se a chamada com o estado ja certo.
                #
                # Nao se inventa animacao nem som: usa-se exactamente o que ele
                # usa, senao o efeito nao seria "o mesmo".
                if (pokemon.super_shiny? rescue false)
                  $scene.spriteset.addUserAnimation(53, event.x, event.y)
                elsif (pokemon.shiny? rescue false)
                  $scene.spriteset.addUserAnimation(52, event.x, event.y)
                end
              rescue
                nil
              end
            end

            alias vower_sync_removeThisEventfromMap_id removeThisEventfromMap unless method_defined?(:vower_sync_removeThisEventfromMap_id)

            def removeThisEventfromMap(id)
              if @events.has_key?(id) && @events[id].is_a?(Game_PokeEvent)
                event = @events[id]
                spawn_id = event.instance_variable_get(:@vower_spawn_id)
                if spawn_id
                  AnilLanRework::VowerWildSync.unregister_spawn(spawn_id) rescue nil
                end
                is_local = event.instance_variable_get(:@vower_local_spawn)

                if spawn_id && is_local && AnilLanRework.connected? && AnilLanRework.multiplayer_map?(self.map_id) && !event.instance_variable_get(:@vower_despawn_sent)
                  event.instance_variable_set(:@vower_despawn_sent, true)
                  AnilLanRework.connection.send_packet("vower_wild_despawn", {
                    "spawn_id" => spawn_id,
                    "map_id"   => self.map_id
                  }) rescue nil
                end
              end
              vower_sync_removeThisEventfromMap_id(id)
            end
          end

          AnilLanRework.log("[POST-PLUGIN] Patches de Sincronizacao de Spawns Selvagens (VOE) aplicados com sucesso!") rescue nil
        else
          AnilLanRework.log("[POST-PLUGIN] AVISO: Plugin VOE nao carregado ou pbPlaceEncounter indefinido.") rescue nil
        end
      rescue => e
        AnilLanRework.log("ERRO ao aplicar patches de spawns selvagens VOE pós-plugins: #{e.message}") rescue nil
      end
    end
  end
end

#===============================================================================
# Roteamento dos Novos Pacotes de Overworld com Fila de Ações
#===============================================================================
module AnilLanRework
  module Router
    class << self
      alias vower_sync_route_packet route_packet unless defined?(vower_sync_route_packet)

      def route_packet(packet)
        begin
          case packet["type"]
          when "vower_wild_spawn", "vower_wild_despawn", "vower_wild_move"
            if $scene.is_a?(Scene_Map) && !$game_temp.in_battle && (!$game_temp.respond_to?(:player_transferring) || !$game_temp.player_transferring)
              # Processa imediatamente se estiver ativamente no mapa (inclui durante menus)
              case packet["type"]
              when "vower_wild_spawn"
                AnilLanRework::VowerWildSync.handle_wild_spawn(packet)
              when "vower_wild_despawn"
                AnilLanRework::VowerWildSync.handle_wild_despawn(packet)
              when "vower_wild_move"
                AnilLanRework::VowerWildSync.handle_wild_move(packet)
              end
            else
              # Se estiver em batalha, transição ou transferência, enfileira
              # a ação para processar de forma segura quando retornar ao mapa.
              # Isso evita que sprites fiquem presos sem viewport/spriteset válido.
              $vower_pending_actions << packet
              AnilLanRework.log("VowerWildSync: Acao #{packet["type"]} enfileirada (jogador ocupado).") rescue nil
            end
          end
        rescue => e
          AnilLanRework.log("Erro no roteamento vower wild sync: #{e.message}") rescue nil
        end
        vower_sync_route_packet(packet)
      end
    end
  end
end

#===============================================================================
# Scene_Map: Esvazia a fila de ações pendentes ao atualizar
#===============================================================================
class Scene_Map
  alias vower_sync_scene_map_update update unless defined?(vower_sync_scene_map_update)

  def update
    vower_sync_scene_map_update
    return if !$vower_pending_actions || $vower_pending_actions.empty?
    return unless $scene.is_a?(Scene_Map)
    return if $game_temp.in_battle
    return if $game_temp.respond_to?(:player_transferring) && $game_temp.player_transferring

    actions_to_run = $vower_pending_actions.dup
    $vower_pending_actions.clear
    actions_to_run.each do |packet|
      begin
        case packet["type"]
        when "vower_wild_spawn"
          AnilLanRework::VowerWildSync.handle_wild_spawn(packet)
        when "vower_wild_despawn"
          AnilLanRework::VowerWildSync.handle_wild_despawn(packet)
        when "vower_wild_move"
          AnilLanRework::VowerWildSync.handle_wild_move(packet)
        end
      rescue => e
        AnilLanRework.log("Erro ao processar acao VOE pendente: #{e.message}") rescue nil
      end
    end
  end
end

#===============================================================================
# Módulo VowerWildSync para Processamento Local dos Pacotes
#===============================================================================
module AnilLanRework
  module VowerWildSync
    def self.handle_wild_spawn(packet)
      return unless $game_map
      return unless packet["map_id"].to_i == $game_map.map_id
      
      spawn_id = packet["spawn_id"].to_s
      # Evita duplicatas se o spawn já foi gerado (O(1) cache check)
      event_id = get_event_id(spawn_id)
      if event_id && $game_map.events.key?(event_id)
        return
      end
      
      # Gera o Pokémon correspondente
      species = packet["species"].to_sym rescue :PIDGEY
      level = packet["level"].to_i
      pokemon = Pokemon.new(species, level)
      pokemon.form = packet["form"].to_i rescue 0
      pokemon.gender = packet["gender"].to_i rescue 0
      pokemon.shiny = packet["shiny"] == true
      pokemon.super_shiny = packet["super_shiny"] == true
      pokemon.nature = packet["nature"].to_sym rescue :HARDY
      pokemon.ability = packet["ability"].to_sym rescue nil
      
      x = packet["x"].to_i
      y = packet["y"].to_i
      
      # Define flags globais antes de posicionar para evitar retransmissões recursivas
      $vower_sync_spawning = true
      $vower_pending_spawn_id = spawn_id
      begin
        pbPlaceEncounter(x, y, pokemon)
        
        # Inicializa imediatamente as coordenadas de interpolação remota
        new_event_id = $game_map.events.keys.max
        if new_event_id && $game_map.events[new_event_id].is_a?(Game_PokeEvent)
          event = $game_map.events[new_event_id]
          real_res_x = (Game_Map::REAL_RES_X rescue 128)
          real_res_y = (Game_Map::REAL_RES_Y rescue 128)
          event.instance_variable_set(:@vower_target_x, x)
          event.instance_variable_set(:@vower_target_y, y)
          event.instance_variable_set(:@vower_target_real_x, x * real_res_x)
          event.instance_variable_set(:@vower_target_real_y, y * real_res_y)
          event.instance_variable_set(:@vower_target_dir, event.direction)
          event.instance_variable_set(:@vower_target_pattern, 0)
          
          # Registro no Cache O(1)
          register_spawn(spawn_id, new_event_id)
        end
      ensure
        $vower_sync_spawning = false
        $vower_pending_spawn_id = nil
      end
    end

    def self.handle_wild_despawn(packet)
      return unless $game_map
      return unless packet["map_id"].to_i == $game_map.map_id
      
      spawn_id = packet["spawn_id"].to_s
      matched_event_id = get_event_id(spawn_id)
      
      if matched_event_id && $game_map.events.key?(matched_event_id)
        if !$map_factory
          $game_map.removeThisEventfromMap(matched_event_id) rescue nil
        else
          $map_factory.getMap($game_map.map_id).removeThisEventfromMap(matched_event_id) rescue nil
        end
        AnilLanRework.log("VowerWildSync: Encontro selvagem #{spawn_id} capturado/removido do mapa.") rescue nil
      end
    end

    def self.handle_wild_move(packet)
      return unless $game_map
      return unless packet["map_id"].to_i == $game_map.map_id
      
      spawn_id = packet["spawn_id"].to_s
      matched_event_id = get_event_id(spawn_id)
      
      if matched_event_id && $game_map.events.key?(matched_event_id)
        matched_event = $game_map.events[matched_event_id]
        # Define os alvos de interpolação no evento remoto com precisão de subpixel
        matched_event.instance_variable_set(:@vower_target_x, packet["x"].to_i)
        matched_event.instance_variable_set(:@vower_target_y, packet["y"].to_i)
        matched_event.instance_variable_set(:@vower_target_real_x, packet["real_x"].to_i)
        matched_event.instance_variable_set(:@vower_target_real_y, packet["real_y"].to_i)
        matched_event.instance_variable_set(:@vower_target_dir, packet["dir"].to_i)
        matched_event.instance_variable_set(:@vower_target_pattern, packet["pattern"].to_i)
      end
    end

    #===========================================================================
    # Interpolação Dinâmica Suave (Pixel-Perfect) para Encontros Remotos
    #===========================================================================
    def self.interpolate_wild!(event)
      target_real_x = event.instance_variable_get(:@vower_target_real_x)
      target_real_y = event.instance_variable_get(:@vower_target_real_y)
      return if target_real_x.nil? || target_real_y.nil?

      real_res_x = (Game_Map::REAL_RES_X rescue 128)
      real_res_y = (Game_Map::REAL_RES_Y rescue 128)
      current_real_x = event.real_x.to_i
      current_real_y = event.real_y.to_i
      dx = target_real_x.to_i - current_real_x
      dy = target_real_y.to_i - current_real_y
      dist = [dx.abs, dy.abs].max

      # Sincroniza direção, frame/pattern do sprite e gráfico atual
      event.direction = event.instance_variable_get(:@vower_target_dir).to_i
      event.pattern = event.instance_variable_get(:@vower_target_pattern).to_i rescue 0

      return if dist == 0

      # Se a distância for muito grande (ex: teleporte ou desvio brusco), teleporta direto
      threshold_px = 3 * [real_res_x, real_res_y].max
      if dist > threshold_px
        event.instance_variable_set(:@real_x, target_real_x.to_i)
        event.instance_variable_set(:@real_y, target_real_y.to_i)
        event.instance_variable_set(:@x, target_real_x.to_i / real_res_x)
        event.instance_variable_set(:@y, target_real_y.to_i / real_res_y)
        event.calculate_bush_depth rescue nil
        return
      end

      # Caso contrário, desloca o sprite de forma fluida a cada frame
      # O tamanho do passo se adapta à velocidade de movimento nativa do monstro
      speed = (event.move_speed rescue 3)
      step_size = 2 ** speed rescue 8
      step_x = [dx.abs, step_size].min
      step_y = [dy.abs, step_size].min
      
      current_real_x += (dx > 0 ? step_x : -step_x)
      current_real_y += (dy > 0 ? step_y : -step_y)

      event.instance_variable_set(:@real_x, current_real_x)
      event.instance_variable_set(:@real_y, current_real_y)
      event.instance_variable_set(:@x, current_real_x / real_res_x)
      event.instance_variable_set(:@y, current_real_y / real_res_y)
      event.calculate_bush_depth rescue nil
    end
  end
end

AnilLanRework.log("MOD: 070_Multiplayer_OW_Spawns_Sync loaded successfully")
