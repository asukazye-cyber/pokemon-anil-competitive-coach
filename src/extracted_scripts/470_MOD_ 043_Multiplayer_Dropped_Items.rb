#===============================================================================
# MOD: 043_Multiplayer_Dropped_Items.rb
#-------------------------------------------------------------------------------
# Permite jogar itens no chão a partir do menu da mochila (Mochila).
# Os itens aparecem fisicamente no mapa como sprites em escala reduzida,
# com brilho pulsante, e podem ser coletados por qualquer jogador!
# Totalmente integrado ao Multiplayer Cooperativo (Sincronização em tempo real)!
#===============================================================================



class PokemonGlobalMetadata
  def dropped_items
    @dropped_items ||= {}
    return @dropped_items
  end

  def dropped_items=(val)
    @dropped_items = val
  end

  unless method_defined?(:anil_dropped_items_initialize) || private_method_defined?(:anil_dropped_items_initialize)
    alias anil_dropped_items_initialize initialize
  end

  def initialize
    begin
      anil_dropped_items_initialize
      @dropped_items = {}
    rescue => e
      AnilLanRework.log("Erro no init global metadata: #{e.message}") rescue nil
    end
  end
end

class Game_Map
  unless method_defined?(:anil_dropped_items_setup) || private_method_defined?(:anil_dropped_items_setup)
    alias anil_dropped_items_setup setup
  end

  def setup(map_id)
    AnilLanRework.log("Game_Map#setup iniciou para mapa #{map_id}") rescue nil
    anil_dropped_items_setup(map_id)
    @panorama_ox = 0
    @panorama_oy = 0
    begin
      AnilLanRework::DroppedItems.spawn_all_for_current_map(self)
      @pending_dropped_items_request = true
    rescue => e
      AnilLanRework.log("Erro no setup de mapa dropped items: #{e.message}\n#{e.backtrace.join("\n")}") rescue nil
    end
  end

  unless method_defined?(:anil_dropped_items_move_panorama) || private_method_defined?(:anil_dropped_items_move_panorama)
    alias anil_dropped_items_move_panorama move_panorama rescue nil
  end

  def move_panorama(x, y)
    @panorama_ox ||= 0
    @panorama_oy ||= 0
    if respond_to?(:anil_dropped_items_move_panorama)
      begin
        anil_dropped_items_move_panorama(x, y)
      rescue => e
        @panorama_ox += x rescue 0
        @panorama_oy += y rescue 0
      end
    else
      @panorama_ox += x rescue 0
      @panorama_oy += y rescue 0
    end
  end

  unless method_defined?(:anil_dropped_items_update) || private_method_defined?(:anil_dropped_items_update)
    alias anil_dropped_items_update update rescue nil
  end

  def update
    if respond_to?(:anil_dropped_items_update)
      anil_dropped_items_update
    end
    if @pending_dropped_items_request
      # ⚠️ A BANDEIRA SO CAI QUANDO O PEDIDO SAI.
      #
      # Antes ela era limpa aqui em cima, e o `connected?` vinha depois. Ao
      # carregar um save o mapa monta-se antes de haver ligacao: a bandeira
      # caia, o pedido nao saia, e nao havia retentativa. O jogador ficava ao
      # lado de um item largado sem o ver.
      if AnilLanRework.connected?
        @pending_dropped_items_request = false
        AnilLanRework.connection.send_packet("request_dropped_items", {
          "map_id" => self.map_id
        }) rescue nil
      end
    end
    begin
      AnilLanRework::DroppedItems.update_connection_sync
    rescue => e
      # Silencioso
    end
    
    # DIAGNOSTIC HOTKEY (F8)
    if $DEBUG && Input.trigger?(Input::F8)
      begin
        AnilLanRework.log("--- DIAGNOSTICO DROPPED ITEMS ---")
        AnilLanRework.log("Connected: #{AnilLanRework.connected?}")
        AnilLanRework.log("Current Map ID: #{self.map_id}")
        if defined?($PokemonGlobal) && $PokemonGlobal
          AnilLanRework.log("Global dropped_items: #{$PokemonGlobal.dropped_items.inspect}")
        else
          AnilLanRework.log("Global dropped_items: $PokemonGlobal is nil/undefined")
        end
        AnilLanRework.log("Game Map Events: #{self.events.keys.select{|k| k >= 900000}.inspect}")
        
        # Check sprites in spriteset
        if $scene.is_a?(Scene_Map)
          spriteset = nil
          if $scene.respond_to?(:spritesets) && $scene.spritesets
            spriteset = $scene.spritesets[self.map_id] rescue nil
          elsif $scene.respond_to?(:spriteset)
            spriteset = $scene.spriteset
          end
          if spriteset && spriteset.respond_to?(:character_sprites)
            sprites = spriteset.character_sprites.select{|s| s.character.is_a?(Game_Event) && s.character.id >= 900000}
            AnilLanRework.log("Sprites in Spriteset: #{sprites.map{|s| s.character.id}.inspect}")
          else
            AnilLanRework.log("Spriteset not found or no character_sprites")
          end
        end
        AnilLanRework.log("--- FIM DIAGNOSTICO ---")
        pbMessage("Diagnóstico gravado em multiplayer_debug.txt!") rescue nil
      rescue => e
        AnilLanRework.log("Erro no diagnostico: #{e.message}\n#{e.backtrace.join("\n")}") rescue nil
      end
    end
  end
end

class Game_Event < Game_Character
  unless method_defined?(:anil_dropped_items_refresh) || private_method_defined?(:anil_dropped_items_refresh)
    alias anil_dropped_items_refresh refresh
  end

  def refresh
    begin
      anil_dropped_items_refresh
      if @event && @event.name =~ /^DroppedItem_(.+)$/
        @visible_item_id = $1.to_sym rescue nil
      end
    rescue => e
      AnilLanRework.log("Erro no Game_Event refresh dropped items: #{e.message}") rescue nil
    end
  end
end

class PokemonBag_Scene
  unless method_defined?(:anil_dropped_items_pbShowCommands) || private_method_defined?(:anil_dropped_items_pbShowCommands)
    alias anil_dropped_items_pbShowCommands pbShowCommands
  end

  def pbShowCommands(helptext, commands, index = 0)
    begin
      is_pokemon_menu = commands.any? { |c| c =~ /Dato|Dado|Status|Summary|Coger|Pegar|Take|Mover|Move/i }
      is_item_menu = commands.any? { |c| c =~ /Cancelar|Cancel/i } && !is_pokemon_menu
      
      if is_item_menu && @sprites["itemlist"] && (item = @sprites["itemlist"].item)
        itm = GameData::Item.get(item)
        if !itm.is_important? || $DEBUG
          commands = commands.clone
          cancel_idx = commands.find_index { |c| c =~ /Cancelar|Cancel/i }
          if cancel_idx
            commands.insert(cancel_idx, "Jogar no chão")
            drop_idx = cancel_idx
            
            res = anil_dropped_items_pbShowCommands(helptext, commands, index)
            
            if res == drop_idx
              begin
                AnilLanRework::DroppedItems.drop_item(item)
              rescue => e
                AnilLanRework.log("Erro ao jogar item no chão: #{e.message}") rescue nil
                pbMessage(_INTL("Erro ao jogar item no chão: {1}", e.message)) rescue nil
              end
              return commands.length - 1
            elsif res > drop_idx
              return res - 1
            else
              return res
            end
          end
        end
      end
    rescue => e
      AnilLanRework.log("Erro no menu pbShowCommands dropped items: #{e.message}") rescue nil
    end
    
    anil_dropped_items_pbShowCommands(helptext, commands, index)
  end
end

module AnilLanRework
  module DroppedItems
    module_function

    @last_connection_state = false
    @buffered_item_claims = {}

    def queue_claim_result(packet)
      return unless packet.is_a?(Hash)
      ev_id = packet["event_id"].to_i
      @buffered_item_claims[ev_id] = packet
    end

    # ⚠️ O LARGAR TAMBEM ESPERA CONFIRMACAO.
    #
    # Antes era fire-and-forget: tirava da mochila, mandava o pacote e seguia.
    # Se o pacote se perdesse, o item nao ia para o chao nem voltava — sumia.
    # O apanhar sempre teve wait_for_claim_result; agora os dois sao simetricos.
    @buffered_drop_results = {}

    def queue_drop_result(packet)
      return unless packet.is_a?(Hash)
      @buffered_drop_results ||= {}
      @buffered_drop_results[packet["item_id"].to_s] = packet
    end

    def wait_for_drop_result(item_id, timeout = 5.0)
      @buffered_drop_results ||= {}
      chave = item_id.to_s
      started = Time.now.to_f
      loop do
        return @buffered_drop_results.delete(chave) if @buffered_drop_results.key?(chave)
        return nil unless AnilLanRework.connected?
        return nil if Time.now.to_f - started >= timeout
        AnilLanRework::BattleSync.pump_network rescue nil
        Graphics.update rescue nil
        Input.update rescue nil
      end
    end

    # ⚠️ A MESMA CAIXA DE CORREIO, SEM A SALA DE ESPERA.
    #
    # O `wait_for_claim_result` PARA o jogo ate a resposta chegar — corre
    # `Graphics.update` num laco, ate cinco segundos. No mundo normal isso e
    # aceitavel: quem apanha um item esta parado a apanha-lo. Na caverna
    # apanha-se a fugir, e o jogo congelava a cada item.
    #
    # Isto le a mesma caixa e devolve `nil` se ainda nao chegou nada. Quem
    # chama volta a perguntar no tick seguinte.
    def colher_claim(event_id)
      @buffered_item_claims.delete(event_id.to_i)
    rescue
      nil
    end

    def esquecer_claim(event_id)
      @buffered_item_claims.delete(event_id.to_i)
    rescue
      nil
    end

    def wait_for_claim_result(event_id, timeout = 5.0)
      started = Time.now.to_f
      loop do
        if @buffered_item_claims.key?(event_id)
          return @buffered_item_claims.delete(event_id)
        end
        return nil unless AnilLanRework.connected?
        return nil if Time.now.to_f - started >= timeout
        # Pushes network packets
        AnilLanRework::BattleSync.pump_network rescue nil
        Graphics.update rescue nil
        Input.update rescue nil
      end
    end


    def update_connection_sync
      return unless $game_map
      current_state = AnilLanRework.connected? rescue false
      if current_state && !@last_connection_state
        begin
          AnilLanRework.connection.send_packet("request_dropped_items", {
            "map_id" => $game_map.map_id
          }) rescue nil
        rescue => e
          AnilLanRework.log("Erro no update_connection_sync: #{e.message}") rescue nil
        end
      end
      @last_connection_state = current_state
    end

    def get_dropped_items
      $PokemonGlobal.dropped_items ||= {}
      $PokemonGlobal.dropped_items
    rescue => e
      {}
    end

    def spawn_all_for_current_map(map_obj = nil)
      map_obj ||= $game_map
      return unless map_obj
      map_id = map_obj.map_id
      items = get_dropped_items[map_id] || []
      AnilLanRework.log("spawn_all_for_current_map chamado para mapa #{map_id}. Encontrados #{items.length} itens locais.")
      items.each do |item_data|
        next unless item_data
        id = (item_data[:id] || item_data["id"]).to_i
        item_id = (item_data[:item_id] || item_data["item_id"]).to_sym rescue nil
        x = (item_data[:x] || item_data["x"]).to_i
        y = (item_data[:y] || item_data["y"]).to_i
        next unless item_id && id > 0
        # ⚠️ ITEM QUE NAO EXISTE NAO GANHA EVENTO.
        #
        # Ha itens no chao com ids que o PBS nao conhece — DCAPSULA, VCAPSULA,
        # SCAPSULA (o PBS so tem SUPERCAPSULE e RANDOMABILITYCAPSULE). Ninguem
        # os consegue apanhar: o pickup_item chama GameData::Item.get e rebenta.
        #
        # Ficavam ali para sempre, e cada um custava ~2 s a entrada no mapa no
        # Android, porque o evento usa o grafico "ItemBall" que nao existe em
        # Graphics/Characters. Um item impossivel de apanhar a cobrar dois
        # segundos por visita e o pior negocio do jogo.
        unless (GameData::Item.exists?(item_id) rescue false)
          AnilLanRework.log("  -> IGNORADO: '#{item_id}' nao existe no PBS (evento #{id} em #{x},#{y})") rescue nil
          next
        end
        AnilLanRework.log("  -> Spawning item: #{item_id} (ID: #{id}) em (#{x}, #{y})")
        spawn_local_item_event(id, item_id, x, y, map_obj)
      end
    rescue => e
      AnilLanRework.log("Erro ao spawnar itens no mapa: #{e.message}\n#{e.backtrace.join("\n")}")
    end

    def spawn_local_item_event(event_id, item_id, x, y, map_obj = nil)
      map_obj ||= $game_map
      return if !map_obj
      begin
        # Cria o Evento do RPG Maker
        rpg_event = RPG::Event.new(x, y)
        rpg_event.id = event_id
        rpg_event.name = "DroppedItem_#{item_id}"
        
        page = rpg_event.pages[0]
        page.graphic.character_name = "ItemBall" # Usa ItemBall para ter colisão e ignorar otimização de cache inicial
        page.graphic.character_hue = 0
        page.trigger = 0 # Botão de Ação (C)
        page.step_anime = false
        page.move_type = 0 # Fixo
        page.through = false # Obstáculo físico sólido para interagir de frente!
        
        # Injeta comando de script explícito e robusto para coletar
        page.list = [
          RPG::EventCommand.new(355, 0, ["AnilLanRework::DroppedItems.pickup_item(#{event_id})"]),
          RPG::EventCommand.new(0, 0, [])
        ]

        # Inicializa o Game_Event correspondente passando o map_obj para correto posicionamento moveto!
        game_event = Game_Event.new(map_obj.map_id, rpg_event, map_obj)
        
        # Registra no map_obj.events
        map_obj.events[event_id] = game_event
        
        # Registra no banco de dados do map_obj para compatibilidade total de plugins (panorama, etc.)!
        map_data = map_obj.instance_variable_get(:@map) rescue nil
        if map_data && map_data.respond_to?(:events)
          map_data.events[event_id] = rpg_event
        end
        
        # Força o refresh para carregar a espécie no @visible_item_id
        game_event.refresh
        
        # Sincroniza o Sprite em tempo real
        if $scene.is_a?(Scene_Map)
          sync_sprite(game_event)
        end
      rescue => e
        AnilLanRework.log("Erro ao criar evento local de item: #{e.message}") rescue nil
      end
    end

    def sync_sprite(event)
      return unless event
      return unless $scene.is_a?(Scene_Map)
      begin
        spriteset = nil
        if $scene.respond_to?(:spritesets) && $scene.spritesets
          spriteset = $scene.spritesets[$game_map.map_id] rescue nil
          spriteset ||= $scene.spritesets.values.find { |s| s.respond_to?(:map) && s.map == $game_map } rescue nil
        elsif $scene.respond_to?(:spriteset) && $scene.spriteset
          spriteset = $scene.spriteset
        end
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
        AnilLanRework.log("Erro ao sincronizar sprite de item: #{e.message}") rescue nil
      end
    end

    def drop_item(item_id)
      return unless $game_map
      # A mesma porta, do lado de ca: nao se larga no chao o que nao se pode
      # apanhar de volta. E assim que os ids invalidos deixam de nascer.
      unless (GameData::Item.exists?(item_id) rescue false)
        AnilLanRework.log("drop_item recusado: '#{item_id}' nao existe no PBS") rescue nil
        pbMessage(_INTL("Esse item não pode ser largado.")) rescue nil
        return
      end
      begin
        itm = GameData::Item.get(item_id)
        item_name = itm.name
        
        # Identifica a coordenada na frente do jogador
        front_x = $game_player.x
        front_y = $game_player.y
        case $game_player.direction
        when 2 # Abaixo
          front_y += 1
        when 4 # Esquerda
          front_x -= 1
        when 6 # Direita
          front_x += 1
        when 8 # Acima
          front_y -= 1
        end
        
        # Valida limites do mapa
        if !$game_map.valid?(front_x, front_y)
          pbMessage(_INTL("Não é possível jogar o item aí!"))
          return false
        end
        
        # Confirmação
        return false unless pbConfirmMessage(_INTL("Deseja mesmo jogar {1} no chão?", item_name))
        
        # Remove da mochila
        $bag.remove(item_id)
        
        # Transmite rede coop / online se conectado
        if AnilLanRework.connected?
          AnilLanRework.connection.send_packet("request_drop_item", {
            "map_id" => $game_map.map_id,
            "item_id" => item_id.to_s,
            "x" => front_x,
            "y" => front_y
          })
          AnilLanRework.connection.flush_batch rescue nil

          # ⚠️ ESPERA O SERVIDOR CONFIRMAR ANTES DE DAR POR FEITO.
          #
          # O item ja saiu da mochila. Se o servidor nao confirmar, ele nao foi
          # para o chao — e devolve-se, em vez de o deixar evaporar.
          res_drop = wait_for_drop_result(item_id.to_s)
          if res_drop.nil? || res_drop["success"] != true
            $bag.add(item_id) rescue nil
            motivo = res_drop ? res_drop["reason"].to_s : "sem resposta do servidor"
            AnilLanRework.log("drop: nao confirmado (#{motivo}) — item devolvido") rescue nil
            pbMessage(_INTL("Nao foi possivel largar o item agora. Ele continua com voce."))
            return false
          end

          # Confirmado: grava ANTES da mensagem. Fechar o jogo agora ja nao
          # deixa o item no chao E na mochila.
          AnilLanRework.gravar_ja!("item_largado") rescue nil
          pbSEPlay("GUI storage put item") rescue nil
          pbMessage(_INTL("Você jogou \\c[1]{1}\\c[0] no chão!", item_name))
        else
          # Se não conectado, faz o drop local tradicional com ID gerado localmente
          event_id = 900000 + rand(99999)
          map_id = $game_map.map_id
          get_dropped_items[map_id] ||= []
          get_dropped_items[map_id] << {
            :id => event_id,
            :item_id => item_id,
            :x => front_x,
            :y => front_y
          }
          spawn_local_item_event(event_id, item_id, front_x, front_y)
          pbSEPlay("GUI storage put item")
          pbMessage(_INTL("Você jogou \\c[1]{1}\\c[0] no chão!", item_name))
        end
        
        true
      rescue => e
        AnilLanRework.log("Erro no drop_item: #{e.class}: #{e.message}") rescue nil
        pbMessage(_INTL("Erro no drop: {1}", e.message)) rescue nil
        false
      end
    end

    def pickup_item(event_id)
      return unless $game_map
      begin
        event = $game_map.events[event_id]
        unless event
          AnilLanRework.log("pickup_item: Evento #{event_id} não encontrado no mapa!") rescue nil
          return
        end
        
        item_id = event.instance_variable_get(:@visible_item_id)
        AnilLanRework.log("pickup_item chamado para o evento #{event_id}. item_id inicial: #{item_id.inspect}") rescue nil
        
        unless item_id
          # Autocura inteligente: se o item_id for nil, extraímos do nome do evento
          if event.event && event.event.name =~ /^DroppedItem_(.+)$/
            item_id = $1.to_sym rescue nil
            event.instance_variable_set(:@visible_item_id, item_id)
            AnilLanRework.log("pickup_item: Autocura aplicada! Recuperado item_id do nome do evento: #{item_id.inspect}") rescue nil
          end
        end
        
        unless item_id
          AnilLanRework.log("pickup_item: Falha crítica! ID do item não pôde ser recuperado para o evento #{event_id}") rescue nil
          return
        end
        
        # Confirmação
        itm = GameData::Item.get(item_id)
        item_name = itm.name
        
        if AnilLanRework.connected?
          # Envia a requisição de coleta para a VPS de forma autoritativa
          @buffered_item_claims.delete(event_id)
          AnilLanRework.connection.send_packet("claim_dropped_item", {
            "map_id" => $game_map.map_id.to_s,
            "event_id" => event_id
          })
          
          # Aguarda a VPS autorizar a coleta síncrona
          res_packet = wait_for_claim_result(event_id)
          
          if res_packet && res_packet["success"]
            $bag.add(item_id)
            (AnilRaidCaverna.apanhou!(item_id) rescue nil)
            remove_dropped_item(event_id)
            # ⚠️ GRAVA ANTES DA MENSAGEM.
            #
            # O servidor ja marcou o item como coletado — isso nao volta atras.
            # Fechar o jogo agora, sem gravar, tirava o item do chao sem o por
            # na mochila: desaparecia.
            AnilLanRework.gravar_ja!("item_apanhado") rescue nil
            pbSEPlay("GUI boot selection")
            pbMessage(_INTL("Você pegou \\c[1]{1}\\c[0]!", item_name))
          else
            remove_dropped_item(event_id)
            pbMessage(_INTL("Esse item já foi coletado por outro jogador!"))
          end
        else
          # Se não conectado, faz a coleta tradicional localmente
          $bag.add(item_id)
          (AnilRaidCaverna.apanhou!(item_id) rescue nil)
          remove_dropped_item(event_id)
          pbSEPlay("GUI boot selection")
          pbMessage(_INTL("Você pegou \\c[1]{1}\\c[0]!", item_name))
        end
      rescue => e
        AnilLanRework.log("Erro no pickup_item: #{e.class}: #{e.message}") rescue nil
        pbMessage(_INTL("Erro ao pegar item: {1}", e.message)) rescue nil
      end
    end

    def remove_dropped_item(event_id)
      return unless $game_map
      begin
        event = $game_map.events[event_id]
        
        # Deleta do banco do mapa
        map_data = $game_map.instance_variable_get(:@map) rescue nil
        if map_data && map_data.respond_to?(:events)
          map_data.events.delete(event_id)
        end
        
        # Deleta evento do mapa
        if $game_map.respond_to?(:removeThisEventfromMap)
          $game_map.removeThisEventfromMap(event_id)
        else
          $game_map.events.delete(event_id)
        end
        
        # Deleta sprite
        if event && $scene.is_a?(Scene_Map)
          spriteset = nil
          if $scene.respond_to?(:spriteset)
            spriteset = $scene.spriteset($game_map.map_id) rescue nil
            spriteset ||= $scene.spriteset rescue nil
          end
          if spriteset && spriteset.respond_to?(:character_sprites)
            sprite_idx = spriteset.character_sprites.index { |s| s.character == event }
            if sprite_idx
              sprite = spriteset.character_sprites.delete_at(sprite_idx)
              sprite.dispose if sprite rescue nil
            end
          end
        end
        
        # Deleta do estado global persistente
        map_id = $game_map.map_id
        items = get_dropped_items[map_id] || []
        items.delete_if { |item_data| (item_data[:id] || item_data["id"]).to_i == event_id }
      rescue => e
        AnilLanRework.log("Erro ao remover item dropado do mapa: #{e.message}") rescue nil
      end
    end
  end
end

module AnilLanRework
  module Router
    class << self
      alias anil_dropped_items_route_packet route_packet unless method_defined?(:anil_dropped_items_route_packet)
      
      def route_packet(packet)
        packet_type = packet["type"].to_s
        case packet_type
        when "drop_item_result"
          begin
            AnilLanRework::DroppedItems.queue_drop_result(packet)
          rescue => e
            AnilLanRework.log("Erro no route drop_item_result: #{e.message}") rescue nil
          end
          return

        when "claim_dropped_item_result"
          begin
            AnilLanRework::DroppedItems.queue_claim_result(packet)
          rescue => e
            AnilLanRework.log("Erro no route claim_dropped_item_result: #{e.message}") rescue nil
          end
          return

        when "request_dropped_items"
          begin
            map_id = packet["map_id"].to_i
            items = $PokemonGlobal.dropped_items[map_id] || []
            if AnilLanRework.connected?
              AnilLanRework.connection.send_packet("sync_dropped_items", {
                "map_id" => map_id,
                "items" => items
              }) rescue nil
            end
          rescue => e
            AnilLanRework.log("Erro no route request_dropped_items: #{e.message}") rescue nil
          end
          return

        when "sync_dropped_items"
          begin
            map_id = packet["map_id"].to_i
            items = packet["items"] || []
            AnilLanRework.log("sync_dropped_items recebido para mapa #{map_id} com #{items.length} itens da VPS.") rescue nil
            
            $PokemonGlobal.dropped_items ||= {}
            synced_items = []
            
            items.each do |new_item|
              item_id = (new_item["item_id"] || new_item[:item_id]).to_sym rescue nil
              next unless item_id
              synced_items << {
                :id => (new_item["id"] || new_item[:id]).to_i,
                :item_id => item_id,
                :x => (new_item["x"] || new_item[:x]).to_i,
                :y => (new_item["y"] || new_item[:y]).to_i
              }
            end
            
            $PokemonGlobal.dropped_items[map_id] = synced_items
            
            if $game_map && $game_map.map_id == map_id
              # Limpa os eventos de itens locais atuais na tela de forma segura
              local_item_event_ids = $game_map.events.keys.select { |id| id >= 900000 }
              local_item_event_ids.each do |ev_id|
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
                if event && $scene.is_a?(Scene_Map)
                  spriteset = nil
                  if $scene.respond_to?(:spriteset)
                    spriteset = $scene.spriteset($game_map.map_id) rescue nil
                    spriteset ||= $scene.spriteset rescue nil
                  end
                  if spriteset && spriteset.respond_to?(:character_sprites)
                    sprite_idx = spriteset.character_sprites.index { |s| s.character == event }
                    if sprite_idx
                      sprite = spriteset.character_sprites.delete_at(sprite_idx)
                      sprite.dispose if sprite rescue nil
                    end
                  end
                end
              end
              
              # Re-spawn tudo atualizado
              AnilLanRework::DroppedItems.spawn_all_for_current_map($game_map)
            end
          rescue => e
            AnilLanRework.log("Erro no route sync_dropped_items: #{e.message}") rescue nil
          end
          return

        when "dropped_item_spawn"
          begin
            map_id = packet["map_id"].to_i
            event_id = packet["event_id"].to_i
            item_id = packet["item_id"].to_sym
            x = packet["x"].to_i
            y = packet["y"].to_i
            
            $PokemonGlobal.dropped_items ||= {}
            $PokemonGlobal.dropped_items[map_id] ||= []
            
            exists = $PokemonGlobal.dropped_items[map_id].any? { |itm| itm[:id] == event_id }
            unless exists
              $PokemonGlobal.dropped_items[map_id] << {
                :id => event_id,
                :item_id => item_id,
                :x => x,
                :y => y
              }
              if $game_map && $game_map.map_id == map_id
                AnilLanRework::DroppedItems.spawn_local_item_event(event_id, item_id, x, y)
              end
            end
          rescue => e
            AnilLanRework.log("Erro no roteamento dropped_item_spawn: #{e.message}") rescue nil
          end
          return
          
        when "dropped_item_pickup"
          begin
            map_id = packet["map_id"].to_i
            event_id = packet["event_id"].to_i
            
            if $game_map && $game_map.map_id == map_id
              AnilLanRework::DroppedItems.remove_dropped_item(event_id)
            else
              $PokemonGlobal.dropped_items ||= {}
              items = $PokemonGlobal.dropped_items[map_id] || []
              items.delete_if { |item_data| item_data[:id] == event_id }
            end
          rescue => e
            AnilLanRework.log("Erro no roteamento dropped_item_pickup: #{e.message}") rescue nil
          end
          return
        end
        
        anil_dropped_items_route_packet(packet)
      end
    end
  end
end

# Guardas de segurança robustas para evitar crashes induzidos por F5 (Soft Reset) no Deluxe Battle Kit
class Battle
  unless method_defined?(:anil_dropped_items_pbMidbattleScripting) || private_method_defined?(:anil_dropped_items_pbMidbattleScripting)
    alias anil_dropped_items_pbMidbattleScripting pbMidbattleScripting rescue nil
  end

  def pbMidbattleScripting(idxBattler, idxTarget, trigger_array)
    @midbattleChoices ||= []
    @activated_triggers ||= []
    @midbattleFailSafe ||= false
    @midbattleVariable ||= 0
    if respond_to?(:anil_dropped_items_pbMidbattleScripting)
      begin
        anil_dropped_items_pbMidbattleScripting(idxBattler, idxTarget, trigger_array)
      rescue => e
        # Evita travar a batalha se houver qualquer outro inconsistente no Deluxe Battle Kit
        PBDebug.log("Erro recuperado em pbMidbattleScripting: #{e.message}") rescue nil
      end
    end
  end
end

# Ajuste da velocidade de animação do sprite do parceiro cooperativo (dinâmico e alinhado a pixels)
class AnilLanRework::RemotePeer
  def update_anim
    return unless $game_map && $game_player
    dx_tiles = (@x - $game_player.x).abs rescue 0
    dy_tiles = (@y - $game_player.y).abs rescue 0
    return if [dx_tiles, dy_tiles].max > 50

    subpixels_x = (Game_Map::X_SUBPIXELS rescue 4)
    dx = @target_x - @real_x
    dy = @target_y - @real_y
    distance = [dx.abs, dy.abs].max

    # Garante alinhamento de pixel inicial
    @real_x = (@real_x.to_f / subpixels_x).round * subpixels_x
    @real_y = (@real_y.to_f / subpixels_x).round * subpixels_x

    # Velocidade ideal para cobrir a distância de forma síncrona
    base_step = subpixels_x * 4 # Mínimo 16 subpixels (4 pixels/frame)
    step = (distance / 6.0).ceil
    step = (step.to_f / subpixels_x).round * subpixels_x
    step = base_step if step < base_step && distance > 0
    step = subpixels_x * 16 if step > subpixels_x * 16 # Máximo 64 subpixels

    if dx.abs > 0 || dy.abs > 0
      @real_x += (dx > 0 ? [step, dx].min : [-step, dx].max)
      @real_y += (dy > 0 ? [step, dy].min : [-step, dy].max)
      @moving = true
    else
      @moving = false
    end
    @x = @real_x / trx
    @y = @real_y / try

    if @moving
      @anim_count += 1
      # Limiar de frames para atualizar a perna (desacelerado substancialmente para teste: 120 frames caminhada, 72 frames corrida).
      anim_threshold = (trx / (step * 0.0625 rescue 1)).clamp(72, 120).to_i
      if @anim_count >= anim_threshold
        @anim_count = 0
        @pattern = (@pattern + 1) % 4
      end
    else
      @pattern = 0
      @anim_count = 0
    end
  end
end

# Otimização de descoberta ultra-rápida Wi-Fi/LAN local (conecta instantaneamente ao achar)
module AnilLanRework
  class << self
    alias anil_original_discover_hosts discover_hosts unless method_defined?(:anil_original_discover_hosts)

    def discover_hosts(timeout = DISCOVERY_TIMEOUT)
      socket = UDPSocket.new
      socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_BROADCAST, true) rescue nil
      socket.bind("0.0.0.0", 0)

      packet = { "type" => "discover_host", "magic" => DISCOVERY_MAGIC, "display_id" => @self_display_id.to_s }
      payload = AnilLanPureJSON.encode(packet)

      discovery_broadcast_targets.each do |target|
        socket.send(payload, 0, target, DISCOVERY_PORT) rescue nil
      end

      hosts = {}
      deadline = Time.now.to_f + timeout.to_f
      while (remaining = deadline - Time.now.to_f) > 0
        ready = IO.select([socket], nil, nil, remaining)
        break unless ready
        begin
          data, addr = socket.recvfrom(4096)
        rescue SystemCallError
          next
        rescue
          next
        end
        msg = AnilLanPureJSON.decode(data.to_s)
        next unless msg.is_a?(Hash) && msg["type"] == "discover_ack" && msg["magic"] == DISCOVERY_MAGIC
        
        udp_source_ip = addr[3].to_s
        announced_ip  = msg["ip"].to_s
        
        ip = udp_source_ip.empty? ? announced_ip : udp_source_ip
        
        alt_ips = [announced_ip, udp_source_ip].map(&:to_s).reject(&:empty?).uniq - [ip]
        all_ips = Array(msg["all_ips"])
        alt_ips = (alt_ips + all_ips).uniq - [ip] unless all_ips.empty?
        
        log("discover_host found ip=#{ip} udp_src=#{udp_source_ip} announced=#{announced_ip} alt=#{alt_ips.inspect}") rescue nil
        
        hosts[ip] = {
          "ip"            => ip,
          "alt_ips"       => alt_ips,
          "host_id"       => msg["host_id"].to_s,
          "host_name"     => msg["host_name"].to_s
        }
        
        # Conexão Imediata Wi-Fi/LAN: se o tipo de rede for local, não perde tempo esperando o timeout expirar!
        net_type = msg["network_type"].to_s
        if net_type.include?("Wi-Fi") || net_type == "LAN"
          log("discover_host: Wi-Fi/LAN local detectado! Conectando imediatamente em milissegundos.") rescue nil
          break
        end
      end
      hosts.values
    ensure
      socket.close rescue nil if socket
    end
  end
end
