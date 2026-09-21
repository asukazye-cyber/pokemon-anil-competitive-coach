# ==============================================================================
# SISTEMA DE EVOLUÇÃO E CORREÇÕES POS-PLUGINS
# Garante que os patches funcionem mesmo com plugins que sobrescrevem métodos (ex: Level Caps EX)
# ==============================================================================

begin
  require 'timeout'
rescue LoadError
end

unless defined?(Timeout)
  module Timeout
    class Error < RuntimeError; end
    def self.timeout(sec)
      yield
    end
  end
end

module PluginManager
  class << self
    alias anil_evo_original_runPlugins runPlugins unless method_defined?(:anil_evo_original_runPlugins)
    
    def runPlugins
      anil_evo_original_runPlugins
      begin
        AnilLanRework.apply_post_plugin_patches
      rescue => e
        AnilLanRework.log("ERRO ao aplicar patches pos-plugins: #{e.message}")
        puts e.backtrace
      end
    end
  end
end

module AnilLanRework
  def self.apply_post_plugin_patches
    self.log("--- INICIANDO APLICAÇÃO DE PATCHES PÓS-PLUGINS ---")

    # -1. tile_id nulo em evento injetado  ->  crash em TODO movimento
    #
    # O Game_Map#passable? do 0047 ja trata isto (ver anil_tile_id_de: nil vale
    # 0), mas esse cuidado e CODIGO MORTO em runtime: o plugin "Advanced Items -
    # Field Moves" reescreve Game_Map#passable? do zero, e os plugins correm no
    # PluginManager.runPlugins, no fim do Main — depois de todos os scripts. A
    # versao do plugin faz `next if event.tile_id <= 0` sem rede, e um evento com
    # tile_id nil rebenta ali com "undefined method '<=' for nil:NilClass",
    # levando consigo qualquer passo do jogador ou do follower.
    #
    # Em vez de reescrever o passable? do plugin (que teria de ser mantido em
    # sincronia com ele para sempre), corta-se o problema na origem: tile_id
    # nunca devolve nil. Zero e o valor correto e nao inventado — significa
    # "evento com grafico de personagem, nao de tile", e e exatamente o que o
    # anil_tile_id_de ja tinha decidido. Com isto o evento partido passa a ser
    # SALTADO pelo `<= 0`, em vez de derrubar o jogo.
    #
    # Fica aqui, e nao no 0047, porque este e o unico ponto que corre DEPOIS dos
    # plugins. Ver [[eventos-injetados-tile-id-nil]].
    begin
      if defined?(Game_Character)
        Game_Character.class_eval do
          unless method_defined?(:anil_tile_id_sem_rede)
            alias_method :anil_tile_id_sem_rede, :tile_id
            def tile_id
              anil_tile_id_sem_rede || 0
            end
          end
        end
        self.log("[POST-PLUGIN] Game_Character#tile_id blindado contra nil (pos-plugin).")
      end
    rescue => e
      self.log("[POST-PLUGIN] ERRO ao blindar tile_id: #{e.message}")
    end

    # -1b. O mesmo evento partido, um passo adiante: posicao nula.
    #
    # Com o tile_id resolvido, o `next if tile_id <= 0` deixa de rebentar mas o
    # evento chega ao at_coordinate?, que faz `check_x >= @x` — e com @x nil da
    # "comparison of Integer with nil failed". Sao DOIS cicios diferentes a
    # percorrer os eventos (o Game_Map#passable? do plugin e o
    # Game_Character#passable? do 0049), por isso a blindagem tem de estar no
    # metodo, nao em cada ciclo.
    #
    # "Sem posicao" e "nao esta nesta coordenada" sao a mesma coisa: devolver
    # false e a resposta correta, nao um remendo. Os dois ciclos passam a saltar
    # o evento, que e o que ja fariam se ele estivesse noutro sitio.
    #
    # @width/@height entram na conta porque o `@x + @width` da linha seguinte
    # rebenta igual, e um objeto sem ivars nenhum tambem os tem nulos.
    # Esteve DESLIGADA algumas horas em 2026-08-04, enquanto se procurava a causa
    # do cliente ficar preso na tela "Carregando...". Nao era isto: a causa era a
    # condicao `!multiplayer_mode` no agendador do autoconnect, que deixava o
    # caminho do Multi Save sem nunca agendar a ligacao. Religada.
    begin
      if defined?(Game_Character)
        Game_Character.class_eval do
          unless method_defined?(:anil_at_coordinate_sem_rede)
            alias_method :anil_at_coordinate_sem_rede, :at_coordinate?
            def at_coordinate?(check_x, check_y)
              return false if @x.nil? || @y.nil? || @width.nil? || @height.nil?
              anil_at_coordinate_sem_rede(check_x, check_y)
            end
          end
        end
        self.log("[POST-PLUGIN] Game_Character#at_coordinate? blindado contra posicao nula.")
      end
    rescue => e
      self.log("[POST-PLUGIN] ERRO ao blindar at_coordinate?: #{e.message}")
    end

    # 0. Proteção: pbGetOwnerItems DEVE sempre retornar Array.
    #    Quando o parceiro foge em coop, ally_items pode conter `true`
    #    ao invés de um array, causando crash na AI_UseItem (NoMethodError: 'length' for true).
    if defined?(Battle)
      Battle.class_eval do
        alias_method :anil_safe_pbGetOwnerItems, :pbGetOwnerItems unless method_defined?(:anil_safe_pbGetOwnerItems)
        def pbGetOwnerItems(idxBattler)
          result = anil_safe_pbGetOwnerItems(idxBattler)
          result.is_a?(Array) ? result : []
        end
      end
    end

    # 1. Patch dinâmico para pbGainExpOne
    if defined?(Battle)
      Battle.class_eval do
        alias_method :anil_post_plugin_original_pbGainExpOne, :pbGainExpOne unless method_defined?(:anil_post_plugin_original_pbGainExpOne)
        
        def pbGainExpOne(idxParty, defeatedBattler, numPartic, expShare, expAll, showMessages = true)
          ctx = AnilLanRework::BattleSync.active_context rescue nil
          if ctx && ctx.mode == :pvp
            return nil
          end
          
          pkmn = pbParty(0)[idxParty] rescue nil
          
          if pkmn && (pkmn.hp == 0 || pkmn.fainted? || !pkmn.able?)
            AnilLanRework.log("[POST-PLUGIN] pbGainExpOne: skipping fainted pokemon #{pkmn.name}")
            return nil
          end

          if ctx && ctx.mode == :coop && AnilLanRework::BattleSync.local_coop_eliminated?(ctx)
            AnilLanRework.log("[POST-PLUGIN] pbGainExpOne: local player is eliminated (spectating), skipping XP gain.")
            return nil
          end

          before_lvl = pkmn ? pkmn.level : 0
          before_exp = pkmn ? pkmn.exp : 0
          
          AnilLanRework.log("[POST-PLUGIN] pbGainExpOne: ENTER idxParty=#{idxParty} pokemon=#{pkmn ? pkmn.name : 'nil'} lv=#{before_lvl}")
          (AnilLanRework::EvoLogger.log("[EVO_TRACK] [POST-PLUGIN] pbGainExpOne: ENTER idxParty=#{idxParty} pokemon=#{pkmn ? pkmn.name : 'nil'} lv=#{before_lvl}") rescue nil)
          
          # Executa o pbGainExpOne ativo (que agora é o do Level Caps EX)
          result = anil_post_plugin_original_pbGainExpOne(idxParty, defeatedBattler, numPartic, expShare, expAll, showMessages)
          
          after_lvl = pkmn ? pkmn.level : 0
          after_exp = pkmn ? pkmn.exp : 0
          exp_delta = after_exp - before_exp
          
          AnilLanRework.log("[POST-PLUGIN] pbGainExpOne: EXIT idxParty=#{idxParty} pokemon=#{pkmn ? pkmn.name : 'nil'} level=#{before_lvl}->#{after_lvl} delta_exp=#{exp_delta}")
          
          if after_lvl > before_lvl && ctx && ctx.mode == :coop && AnilLanRework.connected?
            AnilLanRework.log("[POST-PLUGIN] Level up detected #{before_lvl} -> #{after_lvl} para #{pkmn.name rescue '??'}. Chamando verificação de evolução...")
            (AnilLanRework::EvoLogger.log("[EVO_TRACK] [POST-PLUGIN] Level up detected #{before_lvl} -> #{after_lvl} para #{pkmn.name rescue '??'}. Chamando check_evolution_and_sync_multipleyer_from_pokemon") rescue nil)
            
            AnilLanRework::BattleSyncEvolution.check_evolution_and_sync_multipleyer_from_pokemon(pkmn)
          end
          
          result
        end
      end
      
      self.log("[POST-PLUGIN] Patch para pbGainExpOne aplicado com sucesso!")
    else
      self.log("[POST-PLUGIN] AVISO: Classe Battle não encontrada para patch.")
    end

    # 2. Patch dinâmico para evitar crash no Plugin Marin Side Stairs
    begin
      if defined?(Game_Event)
        Game_Event.class_eval do
          def mss_check_events
            return if !($game_map && $game_map.events)
            return if !($game_map.respond_to?(:side_stairs) && $game_map.side_stairs)
            return if (self.is_stair_event? rescue true)
            map_id = $game_map.map_id
            return if !map_id
            side_stairs = $game_map.side_stairs[map_id]
            return if side_stairs.nil?
            for event in side_stairs
              next if event.nil?
              if !on_stair? && (@real_x / Game_Map::REAL_RES_X).round == event.x &&
                  (@real_y / Game_Map::REAL_RES_Y).round == event.y
                is_stair = (event.is_stair_event? rescue false)
                if is_stair
                  next if $game_player.x == event.x && $game_player.y == event.y
                  self.slope(*event.get_stair_data) rescue nil
                  return
                end
              end
            end    
          rescue
            # Silencia qualquer inconsistência durante o carregamento do mapa
          end
        end
        self.log("[POST-PLUGIN] Patch de seguranca para Marin Side Stairs (mss_check_events) aplicado!")
      end

      if defined?(Game_Map)
        Game_Map.class_eval do
          def add_side_stair(map_id, event)
            @side_stairs ||= {}
            @side_stairs[map_id] ||= []
            is_stair = (event.is_stair_event? rescue false)
            @side_stairs[map_id] << event if event && is_stair
          rescue
          end
        end
        self.log("[POST-PLUGIN] Patch de seguranca para Marin Side Stairs (add_side_stair) aplicado!")
      end
    rescue => e
      self.log("[POST-PLUGIN] ERRO ao aplicar patch de escadas: #{e.message}")
    end

    # 3. Patch dinâmico para restaurar os hooks de multiplayer e dropped items no setup de mapa
    begin
      if defined?(Game_Map)
        Game_Map.class_eval do
          alias_method :anil_post_plugin_original_setup, :setup unless method_defined?(:anil_post_plugin_original_setup)
          # ⚠️ ESTA REDE DE SEGURANCA ESTAVA A FAZER TUDO DUAS VEZES.
          #
          # Os MODs 043 (dropped items), 048 (roaming) e 049 (coop) tambem fazem
          # alias do Game_Map#setup, ao CARREGAR. Este daqui e aplicado DEPOIS
          # dos plugins, portanto fica por fora de todos eles — e a corrente
          # inteira corre a cada troca de mapa:
          #
          #   040 -> 070 -> 049 -> 048 -> 043 -> original
          #
          # O 043 ja fazia o spawn dos itens e o 048 o dos roaming; este repetia
          # os dois. Cada repeticao volta a construir um RPG::Event e um
          # Game_Event por item, sobrepoe map_obj.events[id] com o objeto novo e
          # deixa o anterior orfao — com o sprite dele possivelmente ja criado
          # pelo sync_sprite. Trabalho a dobrar e sprites a mais, a cada mapa.
          #
          # Mas apagar daqui nao serve: esta copia existe porque um plugin pode
          # redefinir o setup de raiz e varrer os alias do 043/048 (e a razao de
          # ser deste ficheiro). Ela tem de continuar a valer QUANDO o elo
          # interno nao sobreviveu.
          #
          # A propria flag responde a isso. O 043 poe @pending_dropped_items_request
          # a true logo a seguir ao spawn; o 048 e o 049 fazem o mesmo com as
          # suas. Limpa-se antes de chamar a corrente e ve-se depois: se voltou a
          # true, o elo interno esta vivo e ja fez o trabalho — nao se repete. Se
          # ficou nil, foi clobbered e a rede de seguranca entra.
          def setup(map_id)
            @pending_dropped_items_request    = nil
            @pending_released_roaming_request = nil
            @pending_coop_full_sync_request   = nil

            anil_post_plugin_original_setup(map_id)
            @panorama_ox = 0 rescue nil
            @panorama_oy = 0 rescue nil
            begin
              if defined?(AnilLanRework::DroppedItems) && !@pending_dropped_items_request
                AnilLanRework::DroppedItems.spawn_all_for_current_map(self)
                @pending_dropped_items_request = true
              end
            rescue => e
              AnilLanRework.log("Erro no setup dropped items: #{e.message}") rescue nil
            end
            
            begin
              if defined?(AnilLanRework::ReleasedRoaming) && !@pending_released_roaming_request
                AnilLanRework::ReleasedRoaming.spawn_all_for_current_map(self)
                @pending_released_roaming_request = true
              end
            rescue => e
              AnilLanRework.log("Erro no setup roaming: #{e.message}") rescue nil
            end
            
            @pending_coop_full_sync_request = true if defined?(AnilLanRework::CoopFullSync)
          end
        end
        self.log("[POST-PLUGIN] Patch dinâmico para Game_Map#setup aplicado!")
      end
    rescue => e
      self.log("[POST-PLUGIN] ERRO ao aplicar patch de Game_Map#setup: #{e.message}")
    end

    # 4. Sincronização de Saves na Nuvem (Cloud Save)
    begin
      # 4.1. Definições globais no módulo AnilLanRework
      AnilLanRework.class_eval do
        def self.save_and_upload_save_file(reason = "")
          return false unless defined?(AnilLanRework) && AnilLanRework.connected? && AnilLanRework.multiplayer_mode
          
          # 1. Salva o jogo localmente no arquivo multiplayer
          begin
            if defined?(Game) && Game.respond_to?(:save)
              Game.save
            elsif defined?(SaveData) && SaveData.respond_to?(:save_to_file)
              SaveData.save_to_file(SaveData::FILE_PATH)
            end
          rescue => e
            log("Erro ao salvar localmente para upload (#{reason}): #{e.message}")
            return false
          end

          # 2. Upload para a VPS via TCP
          if connected? && @connection
            # SaveData::FILE_PATH e um DynamicSavePath: ele reavalia online x
            # offline a CADA .to_s. Resolver o caminho aqui, na thread principal
            # e com o estado online ja validado acima, e o que garante que a
            # thread envie o save que existia neste instante. Resolver la dentro
            # (depois do wait_for_save, que e um join sem timeout) permitia que
            # uma desconexao no meio da janela virasse o caminho para
            # Game.rxdata — e o save OFFLINE subia carimbado com o id online.
            upload_path = (SaveData::FILE_PATH.to_s rescue "")

            # Cinto de seguranca: sob nenhuma circunstancia o save offline deve
            # ser enviado como se fosse o save da nuvem.
            if defined?(DynamicSavePath) && upload_path == (DynamicSavePath.offline_path rescue nil)
              log("[CLOUD_SAVE/ABORT] Upload (#{reason}) cancelado: o caminho resolveu para o save OFFLINE (#{upload_path}). O save online nao foi tocado.")
              return false
            end

            upload_proc = proc {
              begin
                AnilAsyncSave.wait_for_save if defined?(AnilAsyncSave)
                filepath = upload_path
                if File.exist?(filepath)
                  binary_data = File.open(filepath, "rb") { |f| f.read } rescue nil
                  if binary_data
                    # ⚠️ Este caminho ficou para tras quando a compressao foi
                    # adicionada aos outros tres uploaders. Media-se no log:
                    # o mesmo save saia daqui com 236 KB (`battle_started`) e
                    # 2 segundos depois com 65 KB pelo `save_hook`. 3,6x.
                    encoded_data, save_comprimido = if defined?(AnilSaveZip)
                                                      AnilSaveZip.empacotar(binary_data)
                                                    else
                                                      [[binary_data].pack("m0"), false]
                                                    end
                    if defined?(AnilLanRework) && AnilLanRework.connected? && AnilLanRework.connection
                      AnilLanRework.connection.send_packet("upload_save_file", {
                        "player_id" => self.self_internal_id,
                        "save_data" => encoded_data,
                        # Sem esta marca o servidor le o binario comprimido como
                        # se fosse Marshal e manda o save para a quarentena.
                        "save_gzip" => (save_comprimido == true),
                        "reason"    => reason,
                        # Sem isto ESTE uploader seria o unico recusado quando o
                        # SAVE_TOKEN_ENFORCE ligasse — sao quatro caminhos de
                        # upload no cliente e todos tem de declarar o mesmo.
                        "save_token" => (defined?(AnilSaveToken) ? (AnilSaveToken.ler rescue "") : ""),
                        # Sem mtime o servidor pula a comparacao de save_count
                        # inteira (o if la exige client_mtime > 0), e qualquer
                        # upload sobrescreve o save da nuvem sem checagem.
                        "mtime"     => (File.mtime(filepath).to_i rescue 0)
                      }) rescue nil
                      AnilLanRework.connection.flush_batch rescue nil
                      log("[CLOUD_SAVE] Upload de save enviado (#{reason}, #{binary_data.bytesize} bytes, #{File.basename(filepath)})")
                    end
                  end
                end
              rescue => e
                log("Erro no upload do save (#{reason}): #{e.message}")
              end
            }

            # Se for saída de jogo ou desconexão, rodamos de forma síncrona para garantir entrega.
            # Para eventos normais de jogo (mapa, item, etc), rodamos em background (Thread) para evitar travamentos.
            if reason == "game_exit" || reason == "disconnect"
              upload_proc.call
            else
              Thread.new { upload_proc.call }
            end
          end
          true
        end

        def self.download_and_overwrite_save_file
          return unless defined?(AnilLanRework) && AnilLanRework.respond_to?(:multiplayer_mode) && AnilLanRework.multiplayer_mode
          update_player_config
          # Prioriza ler o ID direto do multiplayer_player.txt se existir
          player_id = read_cfg("multiplayer_player.txt", "id", "").to_s.strip
          # Se não existir ou estiver vazio, cai no fallback canônico (self_internal_id)
          if player_id.empty?
            player_id = (self.self_internal_id.to_s rescue "")
          end
          return if player_id.empty?
          target_ip = (AnilLanRework.respond_to?(:dedicated_server_ip) ? AnilLanRework.dedicated_server_ip : "127.0.0.1")
          
          log("[CLOUD_SAVE] Iniciando download do save para player_id=#{player_id} de #{target_ip}...")
          begin
            require 'timeout'
            socket = Timeout.timeout(1.2) { TCPSocket.new(target_ip, 7654) }
            req = {
              "type" => "download_save_file",
              "player_id" => player_id
            }
            payload = AnilLanPureJSON.encode(req)
            socket.write(payload + "\n")
            socket.flush rescue nil
            
            # Leitura robusta com buffer acumulado (Joiplay/Android compatível)
            buffer = +""
            response_data = nil
            deadline = Time.now.to_f + 15.0  # 15 segundos de timeout total

            begin
              while Time.now.to_f < deadline
                # Espera até 5.0 segundos por legibilidade no socket antes de ler
                rs = IO.select([socket], nil, nil, 5.0)
                if rs
                  chunk = socket.recv(16384)
                  if chunk.nil? || chunk.empty?
                    break # EOF
                  end
                  buffer << chunk.force_encoding("UTF-8")
                  if (idx = buffer.index("\n"))
                    response_data = buffer.slice!(0, idx + 1).strip
                    break
                  end
                else
                  # Timeout de 5s sem resposta/dados adicionais
                  break
                end
              end
            rescue => e
              # Silencia erros
            end
            response_data = buffer.strip if response_data.nil? && !buffer.empty?

            socket.close rescue nil
            
            return unless response_data
            packet = AnilLanPureJSON.decode(response_data)
            if packet && packet["type"] == "save_file_data" && packet["found"] == true
              encoded_save = packet["save_data"]
              binary_save = encoded_save.unpack("m0").first
              
              mp_path = SaveData::FILE_PATH.to_s
              File.open(mp_path, "wb") { |f| f.write(binary_save) }
              log("[CLOUD_SAVE] Save baixado da nuvem com sucesso! Tamanho: #{binary_save.bytesize} bytes. Gravado em: #{mp_path}")
            else
              log("[CLOUD_SAVE] Nenhum save na nuvem encontrado para o player_id=#{player_id}. Usará o local ou iniciará novo.")
            end
          rescue => e
            log("[CLOUD_SAVE] Erro no download do save da nuvem: #{e.message}")
          end
        end
      end
      
      # Hook final ao fechar o jogo para salvar e fazer upload síncrono
      at_exit do
        if defined?(AnilLanRework) && AnilLanRework.connected? && AnilLanRework.multiplayer_mode
          AnilLanRework.log("[ExitHook] Jogo fechando. Executando salvamento e upload síncrono final...") rescue nil
          AnilLanRework.save_and_upload_save_file("game_exit") rescue nil
          AnilLanRework.disconnect(false) rescue nil
        end
      end

      self.log("[POST-PLUGIN] Funções de Cloud Save injetadas no módulo AnilLanRework!")
    rescue => e
      self.log("[POST-PLUGIN] ERRO ao aplicar patch de Game_Map#setup: #{e.message}")
    end

    # 5. Monkeypatches de Eventos Críticos para Auto-Save Contínuo
    begin
      # 5.1. Bag Add/Remove
      if defined?(PokemonBag)
        PokemonBag.class_eval do
          alias anil_save_add add unless method_defined?(:anil_save_add)
          def add(item, qty = 1)
            res = anil_save_add(item, qty)
            # ⚠️ Nao salvar no meio da abertura de uma Gift Box.
            #
            # Os premios entram na mochila ANTES de o Essentials consumir a
            # caixa, entao um save aqui grava premios + caixa — e quem fechasse
            # o jogo nesse instante ficava com as duas coisas. O MOD 068 agenda
            # um save unico para o frame seguinte, ja com a caixa consumida.
            caixa_abrindo = (defined?(GiftBoxSystem) && GiftBoxSystem.abrindo?) rescue false
            if res && !caixa_abrindo && defined?(AnilLanRework) &&
               AnilLanRework.connected? && AnilLanRework.multiplayer_mode
              AnilLanRework.save_and_upload_save_file("item_added")
            end
            res
          end

          alias anil_save_remove remove unless method_defined?(:anil_save_remove)
          def remove(item, qty = 1)
            res = anil_save_remove(item, qty)
            if res && defined?(AnilLanRework) && AnilLanRework.connected? && AnilLanRework.multiplayer_mode
              AnilLanRework.save_and_upload_save_file("item_removed")
            end
            res
          end
        end
        self.log("[POST-PLUGIN] Monkeypatch em PokemonBag aplicado!")
      end

      # 5.1b. MEXER NA CAIXA DO PC TAMBEM TEM DE GRAVAR
      #
      # ⚠️ SO SE GRAVAVA AO CAPTURAR, NAO AO ARRUMAR.
      #
      # O `pbStoreCaught` (logo abaixo) cobre o Pokemon que entra por captura.
      # Tirar um da caixa para a equipa, ou arrumar um, nao passava por lado
      # nenhum que gravasse — o save do servidor ficava com o bicho na caixa
      # enquanto o jogador o tinha na equipa.
      #
      # Isso rebentava a troca: o servidor procura o personalID no `@party` da
      # copia DELE (resolve_trade_slot), nao encontrava, e recusava com
      # "Pokemon nao localizado no save do servidor". Depois de uma batalha
      # qualquer passava a funcionar — porque o `battle_started` grava — e essa
      # foi a pista que deu com o problema.
      #
      # ⚠️ GRAVA-SE A SAIR DO PC, E NAO A CADA MOVIMENTO.
      #
      # Quem arruma a caixa faz dez, vinte movimentos seguidos. Um upload por
      # movimento seria uma enxurrada, e o save e um retrato do jogo inteiro: o
      # ultimo cobre todos os anteriores. Marca-se que houve mexida e grava-se
      # uma vez, ao fechar o PC — que e exactamente o instante antes de o
      # jogador ir trocar.
      begin
        if defined?(PokemonStorage)
          PokemonStorage.class_eval do
            [:pbMove, :pbMoveCaughtToParty, :pbDelete].each do |m|
              next unless method_defined?(m)
              orig = :"anil_pcsave_orig_#{m}"
              next if method_defined?(orig) || private_method_defined?(orig)
              alias_method orig, m
              define_method(m) do |*a, &b|
                r = send(orig, *a, &b)
                $anil_pc_mexeu = true
                r
              end
            end
          end
        end

        if defined?(PokemonStorageScreen)
          PokemonStorageScreen.class_eval do
            unless method_defined?(:anil_pcsave_orig_pbStartScreen) ||
                   private_method_defined?(:anil_pcsave_orig_pbStartScreen)
              alias_method :anil_pcsave_orig_pbStartScreen, :pbStartScreen
              def pbStartScreen(command)
                $anil_pc_mexeu = false
                r = anil_pcsave_orig_pbStartScreen(command)
                if $anil_pc_mexeu && defined?(AnilLanRework) &&
                   AnilLanRework.connected? && AnilLanRework.multiplayer_mode
                  AnilLanRework.save_and_upload_save_file("pc_box") rescue nil
                end
                $anil_pc_mexeu = false
                r
              end
            end
          end
        end
        self.log("[POST-PLUGIN] Gravacao ao sair do PC aplicada!")
      rescue => e
        self.log("[POST-PLUGIN] ERRO ao aplicar a gravacao do PC: #{e.message}")
      end

      # 5.2. Store Pokémon in Storage
      if defined?(PokemonStorage)
        PokemonStorage.class_eval do
          alias anil_save_pbStoreCaught pbStoreCaught unless method_defined?(:anil_save_pbStoreCaught)
          def pbStoreCaught(pkmn)
            res = anil_save_pbStoreCaught(pkmn)
            if res && defined?(AnilLanRework) && AnilLanRework.connected? && AnilLanRework.multiplayer_mode
              AnilLanRework.save_and_upload_save_file("pokemon_stored")
            end
            res
          end
        end
        self.log("[POST-PLUGIN] Monkeypatch em PokemonStorage aplicado!")
      end

      # 5.3. pbAddPokemon e pbAddPokemonSilent
      begin
        Object.class_eval do
          if Object.method_defined?(:pbAddPokemon) || Object.private_method_defined?(:pbAddPokemon)
            alias anil_save_pbAddPokemon pbAddPokemon unless Object.method_defined?(:anil_save_pbAddPokemon) || Object.private_method_defined?(:anil_save_pbAddPokemon)
            def pbAddPokemon(pkmn, level = 1, see_form = true)
              res = anil_save_pbAddPokemon(pkmn, level, see_form)
              if res && defined?(AnilLanRework) && AnilLanRework.connected? && AnilLanRework.multiplayer_mode
                AnilLanRework.save_and_upload_save_file("pokemon_added")
              end
              res
            end
          end

          if Object.method_defined?(:pbAddPokemonSilent) || Object.private_method_defined?(:pbAddPokemonSilent)
            alias anil_save_pbAddPokemonSilent pbAddPokemonSilent unless Object.method_defined?(:anil_save_pbAddPokemonSilent) || Object.private_method_defined?(:anil_save_pbAddPokemonSilent)
            def pbAddPokemonSilent(pkmn, level = 1, see_form = true)
              res = anil_save_pbAddPokemonSilent(pkmn, level, see_form)
              if res && defined?(AnilLanRework) && AnilLanRework.connected? && AnilLanRework.multiplayer_mode
                AnilLanRework.save_and_upload_save_file("pokemon_added_silent")
              end
              res
            end
          end
        end
        self.log("[POST-PLUGIN] Monkeypatch em pbAddPokemon/Silent aplicado globalmente no Object!")
      rescue => e
        self.log("[POST-PLUGIN] Erro ao aplicar patch em pbAddPokemon/Silent: #{e.message}")
      end
    rescue => e
      self.log("[POST-PLUGIN] ERRO ao aplicar monkeypatches de Auto-Save: #{e.message}")
    end

    # 6. Event Handlers para Fim de Batalha e Mudança de Mapa
    begin
      if defined?(EventHandlers)
        EventHandlers.add(:on_end_battle, :anil_coop_autosave_battle_end, proc { |_decision, _canLose, _battle|
          if defined?(AnilLanRework) && AnilLanRework.connected? && AnilLanRework.multiplayer_mode
            AnilLanRework.save_and_upload_save_file("battle_ended")
          end
        })

        EventHandlers.add(:on_enter_map, :anil_coop_autosave_map_enter, proc { |_old_map_id|
          if defined?(AnilLanRework) && AnilLanRework.connected? && AnilLanRework.multiplayer_mode
            # Throttle: salvar em TODA troca de mapa fazia transicoes em sequencia
            # travarem (compile+Marshal na thread principal, e o write_async ainda
            # bloqueia se a gravacao anterior nao terminou). Atravessar 3 mapas em
            # 10s gerava 3 saves; agora gera 1. Batalha/game_exit nao passam aqui
            # e continuam salvando sempre.
            agora = Time.now.to_f
            if !$anil_last_map_autosave_at || (agora - $anil_last_map_autosave_at) >= 10.0
              $anil_last_map_autosave_at = agora
              AnilLanRework.save_and_upload_save_file("map_entered")
            end
          end
        })

        EventHandlers.add(:on_start_battle, :anil_coop_autosave_battle_start, proc {
          if defined?(AnilLanRework) && AnilLanRework.connected? && AnilLanRework.multiplayer_mode
            AnilLanRework.save_and_upload_save_file("battle_started")
          end
        })
        self.log("[POST-PLUGIN] EventHandlers de Auto-Save registrados!")
      end
    rescue => e
      self.log("[POST-PLUGIN] ERRO ao registrar EventHandlers de Auto-Save: #{e.message}")
    end

    # 7. Sistema de Balões de Fala (Speech Bubbles) no Scene_Map
    begin
      if defined?(Scene_Map)
        Scene_Map.class_eval do
          alias anil_speech_original_update update unless method_defined?(:anil_speech_original_update)
          def update
            if defined?(AnilLanRework::ChatInputHUD) && AnilLanRework::ChatInputHUD.active?
              AnilLanRework::ChatInputHUD.update rescue nil
            end
            anil_speech_original_update
            @speech_bubbles ||= []
            @speech_bubbles.delete_if { |b| b.disposed? rescue true }
            @speech_bubbles.each { |b| b.update rescue nil }
            @speech_bubbles.delete_if { |b| b.disposed? rescue true }
          end

          alias anil_speech_original_dispose dispose unless method_defined?(:anil_speech_original_dispose)
          def dispose
            @speech_bubbles ||= []
            @speech_bubbles.each { |b| b.dispose rescue nil }
            @speech_bubbles.clear
            anil_speech_original_dispose
          end

          def add_speech_bubble(text, char_id, duration)
            @speech_bubbles ||= []
            # Remove balão anterior do mesmo personagem para evitar sobreposição
            @speech_bubbles.delete_if do |b|
              if b.char_id == char_id
                b.dispose rescue nil
                true
              else
                false
              end
            end
            
            # Obtém o viewport principal do mapa do spriteset ativo
            viewport = nil
            if respond_to?(:spriteset) && spriteset
              viewport = spriteset.instance_variable_get(:@viewport1) rescue nil
            elsif @spritesets && $game_map
              s_set = @spritesets[$game_map.map_id] rescue nil
              viewport = s_set.instance_variable_get(:@viewport1) rescue nil if s_set
            end
            viewport ||= Spriteset_Map.viewport rescue nil
            
            @speech_bubbles << SpeechBubble.new(viewport, text, char_id, duration)
          end
        end
        self.log("[POST-PLUGIN] Integração de Speech Bubbles no Scene_Map aplicada!")
      end
    rescue => e
      self.log("[POST-PLUGIN] ERRO ao aplicar Speech Bubbles no Scene_Map: #{e.message}")
    end

    # 7.5. Watchdog de Conexão no Topo do Scene_Map#update
    begin
      if defined?(Scene_Map)
        Scene_Map.class_eval do
          alias anil_watchdog_original_update update unless method_defined?(:anil_watchdog_original_update)
          
          def update
            begin
              # 1. Watchdog para queda inesperada de conexão no multiplayer (delegação ao AnilLanRework)
              if AnilLanRework.respond_to?(:update_connection_watchdog)
                AnilLanRework.update_connection_watchdog(self)
              end

              # 2. Executa o resto da cadeia (que inclui o coordinate fix, speech bubbles, etc.)
              anil_watchdog_original_update
              
            rescue AnilMainMenuRedirectException
              AnilLanRework.log("Scene_Map#update: Redirecionando para a tela de título devido a desconexão.")
              $scene = pbCallTitle
            end
          end
        end
        AnilLanRework.log("[POST-PLUGIN] Watchdog de Conexão injetado no topo de Scene_Map#update!") rescue nil
      end
    rescue => e
      AnilLanRework.log("[POST-PLUGIN] ERRO ao injetar watchdog no Scene_Map#update: #{e.message}") rescue nil
    end

    # 8. Hook no PokemonSaveScreen para remover o overlay de fade preto do save e tratar LAN/Online
    begin
      if defined?(PokemonSaveScreen)
        PokemonSaveScreen.class_eval do
          alias_method :anil_abs_orig_pbSaveScreen, :pbSaveScreen unless method_defined?(:anil_abs_orig_pbSaveScreen)
          def pbSaveScreen(exiting = false)
            if defined?(AnilLanRework) && AnilLanRework.respond_to?(:online_session?) && AnilLanRework.online_session?
              # Modo Online (VPS): Força o slot online Game_mp
              ret = false
              @scene.pbStartScreen
              if pbConfirmMessage(_INTL("¿Quieres guardar la partida?"))
                pbSEPlay("GUI save choice") rescue nil
                ret = doSave("Game_mp")
              end
              @scene.pbEndScreen
              if defined?(AnilAntiBlackScreen)
                AnilAntiBlackScreen.dispose_save_black_overlay! rescue nil
              end
              return ret
            else
              # Modo LAN / Offline: Desativa temporariamente a flag multiplayer para exibir os slots normais no menu de salvar
              was_mp = AnilLanRework.multiplayer_mode
              begin
                AnilLanRework.multiplayer_mode = false
                ret = anil_abs_orig_pbSaveScreen(exiting)
              ensure
                AnilLanRework.multiplayer_mode = was_mp
              end
              if defined?(AnilAntiBlackScreen)
                AnilAntiBlackScreen.dispose_save_black_overlay! rescue nil
              end
              return ret
            end
          end
        end
        self.log("[POST-PLUGIN] Hook no PokemonSaveScreen aplicado com sucesso!")
      end
    rescue => e
      self.log("[POST-PLUGIN] ERRO ao aplicar hook no PokemonSaveScreen: #{e.message}")
    end

    # 9. Redução de 70% no dinheiro obtido de treinadores rivais
    begin
      if defined?(Trainer)
        Trainer.class_eval do
          alias_method :anil_orig_base_money, :base_money unless method_defined?(:anil_orig_base_money)
          def base_money
            original = anil_orig_base_money || 30
            return (original * 0.3).round
          end
        end
        self.log("[POST-PLUGIN] Redução de 70% no dinheiro de treinadores rival aplicado!")
      end
    rescue => e
      self.log("[POST-PLUGIN] ERRO ao aplicar redução de dinheiro dos treinadores: #{e.message}")
    end

    # 10. Correção de disposed sprite no TrainerSensor após varreduras de memória
    begin
      if defined?(TrainerSensor)
        TrainerSensor.singleton_class.class_eval do
          alias_method :anil_orig_sensor_create, :create unless method_defined?(:anil_orig_sensor_create)
          alias_method :anil_orig_sensor_update, :update unless method_defined?(:anil_orig_sensor_update)

          def create(distance)
            if !@top || (@top.disposed? rescue true) || !@bottom || (@bottom.disposed? rescue true)
              @top = Sprite.new rescue nil
              @top.z = 1 rescue nil
              @bottom = Sprite.new rescue nil
              @bottom.z = 1 rescue nil
              @created = false
            end
            anil_orig_sensor_create(distance)
          end

          def update
            if !@created || (@top.disposed? rescue true) || (@bottom.disposed? rescue true)
              @created = false
              return
            end
            anil_orig_sensor_update
          end
        end
        self.log("[POST-PLUGIN] Patch no TrainerSensor para evitar disposed sprite aplicado!")
      end
    rescue => e
      self.log("[POST-PLUGIN] ERRO ao aplicar patch no TrainerSensor: #{e.message}")
    end

    # 11. Filtragem de Saves Multiplayer no Modo Offline/LAN
    begin
      if defined?(SaveData)
        SaveData.singleton_class.class_eval do
          alias anil_economy_orig_each_slot each_slot unless method_defined?(:anil_economy_orig_each_slot)
          def each_slot
            if defined?(AnilLanRework) && AnilLanRework.respond_to?(:online_session?) && AnilLanRework.online_session?
              pid = nil
              if defined?(AnilLanRework) && AnilLanRework.respond_to?(:get_player_id)
                pid = AnilLanRework.get_player_id rescue nil
              end
              pid = "Game_mp" if pid.nil? || pid.empty? || pid.downcase.include?("localhost")
              pid = pid.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
              yield pid
            else
              # ANIL 2026-08-01: INVERTIDO. Antes descartava os saves de CONTA
              # fora de sessao online, deixando so os offline ("Partida N").
              # Agora e o contrario: o modo offline sai do jogo, entao a lista
              # mostra apenas os saves de conta (nome-id).
              #
              # Este patch corre DEPOIS do plugin e sobrepoe-se a ele: mexer so
              # no Multi Save nao tinha efeito nenhum, porque esta filtragem
              # desfazia-o uma camada acima.
              anil_economy_orig_each_slot do |slot|
                next if slot.to_s.downcase == "game_mp"
                next unless slot.to_s.downcase =~ /^[a-z0-9_-]+-([a-z0-9]{6}|localhost)$/i
                yield slot
              end
            end
          end

          alias anil_economy_orig_get_newest_save_slot get_newest_save_slot unless method_defined?(:anil_economy_orig_get_newest_save_slot)
          def get_newest_save_slot
            if defined?(AnilLanRework) && AnilLanRework.respond_to?(:online_session?) && AnilLanRework.online_session?
              pid = nil
              if defined?(AnilLanRework) && AnilLanRework.respond_to?(:get_player_id)
                pid = AnilLanRework.get_player_id rescue nil
              end
              pid = "Game_mp" if pid.nil? || pid.empty? || pid.downcase.include?("localhost")
              pid = pid.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
              return pid if File.file?(get_full_path(pid))
              return nil
            else
              # ANIL: so recusa o "game_mp"; o save de CONTA passa a ser valido
              # (era ele que ficava de fora e deixava a lista sem seleccionado).
              slot = anil_economy_orig_get_newest_save_slot
              return nil if slot.to_s.downcase == "game_mp"
              slot
            end
          end
        end
        self.log("[POST-PLUGIN] Patches de filtragem no SaveData aplicados!")
      end

      if defined?(PokemonLoadScreen)
        PokemonLoadScreen.class_eval do
          alias anil_economy_orig_initialize initialize unless method_defined?(:anil_economy_orig_initialize)
          def initialize(scene)
            anil_economy_orig_initialize(scene)
            # Se estivermos no menu offline/LAN, limpa qualquer seleção de save que seja multiplayer
            unless defined?(AnilLanRework) && AnilLanRework.respond_to?(:online_session?) && AnilLanRework.online_session?
              # ANIL: nao limpar a seleccao por ser um save de conta — e agora o
              # unico tipo listado. So o "game_mp" continua a ser descartado.
              if @selected_file.to_s.downcase == "game_mp"
                @selected_file = SaveData.get_newest_save_slot
              end
            end
          end
        end
      end
    rescue => e
      self.log("[POST-PLUGIN] ERRO ao aplicar patches de filtragem de save: #{e.message}")
    end

    # 12. Monkey Patches de Game.save e Game.auto_save compatíveis com Multi-Save e LAN
    begin
      if defined?(Game)
        Game.singleton_class.class_eval do
          alias_method :anil_lan_multi_save_orig_save, :save unless method_defined?(:anil_lan_multi_save_orig_save)
          def save(slot = nil, auto = false, safe: false)
            if defined?(AnilLanRework) && AnilLanRework.respond_to?(:multiplayer_mode) && AnilLanRework.multiplayer_mode
              if !AnilLanRework.online_session?
                # Modo LAN: Desativa temporariamente a flag de multiplayer para usar o slot local off-line
                was_mp = AnilLanRework.multiplayer_mode
                begin
                  AnilLanRework.multiplayer_mode = false
                  result = anil_lan_multi_save_orig_save(slot, auto, safe: safe)
                ensure
                  AnilLanRework.multiplayer_mode = was_mp
                end
                return result
              else
                # Modo Online (VPS): Força o slot online único do jogador
                pid = AnilLanRework.get_player_id rescue "Game_mp"
                pid = "Game_mp" if pid.nil? || pid.empty? || pid.downcase.include?("localhost")
                pid = pid.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
                
                was_mp = AnilLanRework.multiplayer_mode
                begin
                  AnilLanRework.multiplayer_mode = false
                  result = anil_lan_multi_save_orig_save(pid, auto, safe: safe)
                ensure
                  AnilLanRework.multiplayer_mode = was_mp
                end
                return result
              end
            else
              # Caso normal / off-line
              slot = slot.to_s if slot && !slot.is_a?(String)
              return anil_lan_multi_save_orig_save(slot, auto, safe: safe)
            end
          end

          if respond_to?(:auto_save)
            alias_method :anil_lan_multi_save_orig_auto_save, :auto_save unless method_defined?(:anil_lan_multi_save_orig_auto_save)
            def auto_save
              if defined?(AnilLanRework) && AnilLanRework.respond_to?(:multiplayer_mode) && AnilLanRework.multiplayer_mode && !AnilLanRework.online_session?
                was_mp = AnilLanRework.multiplayer_mode
                begin
                  AnilLanRework.multiplayer_mode = false
                  result = anil_lan_multi_save_orig_auto_save
                ensure
                  AnilLanRework.multiplayer_mode = was_mp
                end
                return result
              else
                anil_lan_multi_save_orig_auto_save
              end
            end
          end
        end
        self.log("[POST-PLUGIN] Patches em Game.save e Game.auto_save aplicados!")
      end
    rescue => e
      self.log("[POST-PLUGIN] ERRO ao aplicar patches em Game.save/auto_save: #{e.message}")
    end

    # 2. Patch dinâmico para Sprite_Character#refresh_graphic (Resolução de Skins pós-plugins)
    begin
      if defined?(Sprite_Character)
        Sprite_Character.class_eval do
          alias_method :anil_skins_post_plugin_refresh_graphic, :refresh_graphic unless method_defined?(:anil_skins_post_plugin_refresh_graphic)
          
          def refresh_graphic
            return if !@character
            char_name_no_ext = @character.character_name.to_s.gsub(/\.(bmp|png|gif|jpg|jpeg)$/i, "")
            is_new = $newly_downloaded_skins && ($newly_downloaded_skins[char_name_no_ext] || $newly_downloaded_skins[char_name_no_ext.downcase])

            unless is_new
              return if @tile_id == @character.tile_id &&
                        @character_name == @character.character_name &&
                        @character_hue == @character.character_hue &&
                        @oldbushdepth == @character.bush_depth
            end

            if is_new
              $newly_downloaded_skins[char_name_no_ext] = false
              $newly_downloaded_skins[char_name_no_ext.downcase] = false
            end

            if (@character.is_a?(Game_Event) && @character.respond_to?(:visible_item_id) && @character.visible_item_id) || @character.tile_id >= 384
              anil_skins_post_plugin_refresh_graphic
              return
            end
            
            char_name = @character.character_name.to_s
            if char_name.empty?
              anil_skins_post_plugin_refresh_graphic
              return
            end

            noext = char_name.gsub(/\.(bmp|png|gif|jpg|jpeg)$/i, "")
            skin_path = "Graphics/Skins/" + noext
            cache_path = "Graphics/Skins/Cache/" + noext

            # ⚠️ ESTE E O refresh_graphic QUE MANDA, E ERA O QUE MAIS BATIA NO DISCO.
            #
            # E o mais exterior da cadeia: corre para TODA a personagem normal.
            # Quando a skin nao aparece, ainda cai no do 029 — que fazia outras
            # quatro. Ate oito `File.exist?` por refresco, 268 refrescos numa
            # entrada de mapa com 53 personagens: mais de dois mil acessos ao
            # disco para responder a uma pergunta cuja resposta nao muda.
            #
            # Na Rota 13 isso deu 6,1 s contra os 720 ms da mesma rota noutro
            # momento — o mesmo numero de refrescos (268) e o mesmo tempo de
            # bitmaps (176 ms). Todo o resto estava aqui. E piora quando a
            # thread do autosave esta a escrever ao lado, que e exactamente
            # quando o jogo muda de mapa.
            #
            # A cache e a `$anil_skin_existe`, a mesma do motor, e quem grava
            # uma skin nova ja a limpa (`$anil_skin_existe = nil` no 002).
            # As faltas ficam contadas como `skin:disco` no diagnostico. Se a
            # Rota 13 continuar lenta e este contador vier a zero, o tempo esta
            # noutro sitio e nao se perde outra ronda a adivinhar.
            $anil_skin_existe ||= {}
            exists_png = if $anil_skin_existe.key?(skin_path)
              $anil_skin_existe[skin_path]
            else
              t0 = (AnilDiagLento.agora rescue nil)
              r = (File.exist?(skin_path + ".png") || File.exist?(skin_path + ".PNG"))
              (AnilDiagLento.contar(:"skin:disco", AnilDiagLento.agora - t0) rescue nil) if t0
              $anil_skin_existe[skin_path] = r
            end
            exists_cache = if $anil_skin_existe.key?(cache_path)
              $anil_skin_existe[cache_path]
            else
              t0 = (AnilDiagLento.agora rescue nil)
              r = (File.exist?(cache_path + ".png") || File.exist?(cache_path + ".PNG"))
              (AnilDiagLento.contar(:"skin:disco", AnilDiagLento.agora - t0) rescue nil) if t0
              $anil_skin_existe[cache_path] = r
            end
            
            skins_enabled = defined?(AnilLanRework::SKINS_ENABLED) && AnilLanRework::SKINS_ENABLED
            if skins_enabled
              $downloaded_skins_cache ||= {}
              if !$downloaded_skins_cache.key?(noext)
                exists_char = pbResolveBitmap("Graphics/Characters/" + noext) rescue false
                if !exists_png && !exists_cache && !exists_char
                  $downloaded_skins_cache[noext] = true
                  Thread.new do
                    begin
                      if defined?(AnilLanRework::ServerSkins)
                        AnilLanRework.log("SkinSync: Baixando skin ausente '#{noext}' em tempo real...")
                        # ⚠️ cache = FALSE.
                        #
                        # Estava `true`, o que mandava o ficheiro para
                        # Graphics/Skins/Cache/. So que o resto do sistema — o
                        # check_and_request, o assegurar_skin_local!, o upload e
                        # a versao do refresh_graphic no 002 — olha para
                        # Graphics/Skins/. A skin descia e ficava numa pasta que
                        # metade do codigo nao consulta.
                        AnilLanRework::ServerSkins.baixar_skin_do_servidor(noext, false)
                        if $scene.is_a?(Scene_Map)
                          $game_map.need_refresh = true rescue nil
                        end
                      end
                    rescue => e
                      AnilLanRework.log("SkinSync: Erro ao baixar skin ausente '#{noext}': #{e.message}")
                    end
                  end
                else
                  $downloaded_skins_cache[noext] = false
                end
              end
            end

            if exists_png || exists_cache || pbResolveBitmap(skin_path)
              begin
                @tile_id        = @character.tile_id
                @character_name = char_name
                @character_hue  = @character.character_hue
                @oldbushdepth   = @character.bush_depth
                @charbitmap&.dispose
                @charbitmap = nil
                @bushbitmap&.dispose
                @bushbitmap = nil

                if exists_png
                  @charbitmap = AnimatedBitmap.new(skin_path + ".png", @character_hue)
                  RPG::Cache.retain("Graphics/Skins/", noext + ".png", @character_hue) if @character == $game_player
                elsif exists_cache
                  @charbitmap = AnimatedBitmap.new(cache_path + ".png", @character_hue)
                  RPG::Cache.retain("Graphics/Skins/Cache/", noext + ".png", @character_hue) if @character == $game_player
                else
                  resolved = pbResolveBitmap(skin_path)
                  @charbitmap = AnimatedBitmap.new(resolved, @character_hue)
                  RPG::Cache.retain("Graphics/Skins/", File.basename(resolved), @character_hue) if @character == $game_player
                end

                @charbitmapAnimated = true
                @spriteoffset = char_name[/offset/i]
                @cw = @charbitmap.width / 4
                @ch = @charbitmap.height / 4
                self.ox = @cw / 2
                self.oy = @ch
                @character.sprite_size = [@cw, @ch]
              rescue => e
                AnilLanRework.log("Post-Plugin skin load error: #{e.message}. Falling back to default graphic.") rescue nil
                @character_name = "POKEMONTRAINER_RojoArio" rescue nil
                if @character
                  @character.character_name = "POKEMONTRAINER_RojoArio" rescue nil
                end
                begin
                  anil_skins_post_plugin_refresh_graphic
                rescue => err
                  self.bitmap = nil
                  @cw = 0
                  @ch = 0
                end
              end
            else
              begin
                anil_skins_post_plugin_refresh_graphic
              rescue => e
                AnilLanRework.log("Post-Plugin refresh_graphic fallback error: #{e.message}. Using safe default.") rescue nil
                @character_name = "POKEMONTRAINER_RojoArio" rescue nil
                if @character
                  @character.character_name = "POKEMONTRAINER_RojoArio" rescue nil
                end
                begin
                  anil_skins_post_plugin_refresh_graphic
                rescue => err
                  self.bitmap = nil
                  @cw = 0
                  @ch = 0
                end
              end
            end
          end
        end
        self.log("[POST-PLUGIN] Patches em Sprite_Character#refresh_graphic para Skins aplicados!")
      end
    rescue => e
      self.log("[POST-PLUGIN] ERRO ao aplicar patches em Sprite_Character: #{e.message}")
    end

    self.log("--- APLICAÇÃO DE PATCHES PÓS-PLUGINS CONCLUÍDA ---")
  end
end
