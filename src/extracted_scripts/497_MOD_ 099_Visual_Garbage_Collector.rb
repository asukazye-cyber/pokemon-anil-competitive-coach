#===============================================================================
# MOD: 099_Visual_Garbage_Collector
#-------------------------------------------------------------------------------
# Provê uma rotina global e segura de limpeza profunda de viewports e sprites
# órfãos (travados de transições antigas), limpando a memória RAM/GPU.
#===============================================================================

module AnilLanRework
  def self.wipe_stuck_graphics!(silent = false)
    log("[WIPE] Iniciando limpeza de viewports e sprites travados... silent=#{silent}")
    
    # Evita executar se estiver em transição, batalha ou menu crítico para não quebrar a UI ativa
    if $game_temp
      if $game_temp.in_menu || $game_temp.message_window_showing || $game_temp.player_transferring
        log("[WIPE] Limpeza cancelada: jogador está em menu, mensagem ou transição.")
        return
      end
    end

    if !$scene.is_a?(Scene_Map)
      log("[WIPE] Limpeza cancelada: cena atual não é Scene_Map.")
      return
    end
    
    # Cache para evitar recursão infinita e duplicados
    visited = {}
    valid_viewports = []
    valid_sprites = []
    
    # Scanner recursivo seguro
    scanner = proc do |obj|
      next unless obj
      next if visited[obj.object_id]
      visited[obj.object_id] = true
      
      if obj.is_a?(Array)
        obj.each do |item|
          if item.is_a?(Viewport)
            valid_viewports << item
          elsif item.is_a?(Sprite) || item.is_a?(Plane)
            valid_sprites << item
          elsif item.is_a?(Window)
            vp = item.viewport rescue nil
            valid_viewports << vp if vp
          end
          scanner.call(item) if item && !item.is_a?(Numeric) && !item.is_a?(String) && !item.is_a?(Symbol)
        end
      elsif obj.is_a?(Hash)
        obj.each do |k, v|
          [k, v].each do |item|
            if item.is_a?(Viewport)
              valid_viewports << item
            elsif item.is_a?(Sprite) || item.is_a?(Plane)
              valid_sprites << item
            elsif item.is_a?(Window)
              vp = item.viewport rescue nil
              valid_viewports << vp if vp
            end
          end
          scanner.call(k) if k && !k.is_a?(Numeric) && !k.is_a?(String) && !k.is_a?(Symbol)
          scanner.call(v) if v && !v.is_a?(Numeric) && !v.is_a?(String) && !v.is_a?(Symbol)
        end
      else
        # Coleta variáveis de instância
        obj.instance_variables.each do |var_sym|
          val = obj.instance_variable_get(var_sym) rescue nil
          next unless val
          
          # 1. Registra o objeto em si na lista correspondente
          if val.is_a?(Viewport)
            valid_viewports << val
          elsif val.is_a?(Sprite) || val.is_a?(Plane)
            valid_sprites << val
          elsif val.is_a?(Window)
            vp = val.viewport rescue nil
            valid_viewports << vp if vp
          end
          
          # 2. Varre recursivamente coleções ou objetos complexos para achar variáveis internas
          scanner.call(val) if !val.is_a?(Numeric) && !val.is_a?(String) && !val.is_a?(Symbol) && !val.is_a?(TrueClass) && !val.is_a?(FalseClass)
        end
      end

      # Coleta variáveis de classe da classe do objeto
      if obj.class.respond_to?(:class_variables)
        obj.class.class_variables.each do |cvar|
          val = obj.class.send(:class_variable_get, cvar) rescue nil
          if val.is_a?(Viewport)
            valid_viewports << val
          elsif val.is_a?(Sprite) || val.is_a?(Plane)
            valid_sprites << val
          elsif val.is_a?(Window)
            vp = val.viewport rescue nil
            valid_viewports << vp if vp
          end
        end rescue nil
      end
    end
    
    # Escaneia objetos críticos ativos no jogo e variáveis globais para preservar gráficos válidos
    begin
      scanner.call($scene) if $scene
      scanner.call($game_temp) if $game_temp
      scanner.call($game_player) if $game_player
      scanner.call($game_map) if $game_map
      
      # Varre todas as variáveis globais para proteger viewports/sprites de UIs globais ou extras
      global_variables.each do |var_sym|
        next if [:$scene, :$game_temp, :$game_player, :$game_map].include?(var_sym)
        val = eval(var_sym.to_s) rescue nil
        next unless val
        next if val.is_a?(Numeric) || val.is_a?(String) || val.is_a?(Symbol) || val.is_a?(TrueClass) || val.is_a?(FalseClass)
        # Evita loops pesados em metadados puros do save
        next if val.class.name && ["PokemonGlobalMetadata", "PokemonSystem", "PokemonBag", "Player", "Game_System"].include?(val.class.name)
        scanner.call(val)
      end rescue nil
    rescue => e
      log("[WIPE] Erro durante o escaneamento de objetos: #{e.message}")
    end

    # Varre explicitamente todas as classes que herdam ou têm nome parecido com Spriteset
    ObjectSpace.each_object(Class) do |klass|
      next unless klass.name && (klass.name.start_with?("Spriteset_") || klass.name == "Spriteset")
      klass.class_variables.each do |cvar|
        val = klass.send(:class_variable_get, cvar) rescue nil
        if val.is_a?(Viewport)
          valid_viewports << val
        elsif val.is_a?(Sprite) || val.is_a?(Plane)
          valid_sprites << val
        elsif val.is_a?(Window)
          vp = val.viewport rescue nil
          valid_viewports << vp if vp
        end
      end rescue nil
    end rescue nil
    
    # Adiciona viewports de todos os sprites/planes válidos coletados
    valid_sprites.each do |s|
      begin
        next if s.disposed? rescue true
        vp = s.viewport
        valid_viewports << vp if vp
      rescue => e
      end
    end
    
    # Protege explicitamente os viewports de transição registrados
    if defined?($active_transition_viewports) && $active_transition_viewports.is_a?(Array)
      $active_transition_viewports.each do |vp|
        valid_viewports << vp if vp && !vp.disposed? rescue false
      end
    end

    valid_viewports.compact!
    valid_viewports.uniq!
    valid_sprites.compact!
    valid_sprites.uniq!
    
    # Varre o ObjectSpace e deleta os objetos órfãos
    sprites_disposed = 0
    viewports_disposed = 0
    
    ObjectSpace.each_object(Sprite) do |sprite|
      begin
        next if sprite.disposed?
        next if valid_sprites.include?(sprite)
        
        sprite.dispose
        sprites_disposed += 1
      rescue => e
        # ignora
      end
    end

    ObjectSpace.each_object(Plane) do |plane|
      begin
        next if plane.disposed? rescue true
        next if valid_sprites.include?(plane)
        
        plane.dispose
        sprites_disposed += 1
      rescue => e
        # ignora
      end
    end
    
    ObjectSpace.each_object(Viewport) do |viewport|
      begin
        next if viewport.disposed? rescue true
        next if valid_viewports.include?(viewport)
        
        # Protege viewports de transição/sistema (z alto) para evitar crash em pbFadeOutIn
        next if viewport.z >= 99900 rescue false
        
        viewport.dispose
        viewports_disposed += 1
      rescue => e
        # ignora
      end
    end
    
    # Limpa o cache de imagens e força coleta de lixo
    RPG::Cache.clear rescue nil
    GC.start
    
    # Se estiver no mapa, solicita a recriação do spriteset
    if $scene.is_a?(Scene_Map)
      if defined?(AnilLanRework) && AnilLanRework.respond_to?(:request_map_graphics_refresh!)
        AnilLanRework.request_map_graphics_refresh!("hotkey_wipe", 4)
      end
    end
    
    log("[WIPE] Concluído! Sprites órfãos destruídos: #{sprites_disposed} | Viewports órfãos destruídos: #{viewports_disposed}")
    
    # Exibe um feedback sutil na tela se estivermos em um contexto onde mensagens funcionam
    if !silent && defined?(pbMessage) && $scene.is_a?(Scene_Map)
      pbMessage(_INTL("Interface e viewports limpos com sucesso!")) rescue nil
    end
  end
end
