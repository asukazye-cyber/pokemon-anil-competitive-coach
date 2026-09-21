#===============================================================================
# Save Size Optimizer - Strips PokéAPI Cache from Save Files
#===============================================================================

#===============================================================================
# Corte das seccoes no momento da gravacao.
#
# ⚠️ Porque isto existe: o upload parcial fatiava o save fazendo
# `Marshal.load` do FICHEIRO e voltando a dumpar cada peca. So que carregar nao
# e uma operacao neutra — o `Game_Map#marshal_load` daqui de baixo le os
# `Data/MapXXX.rxdata` do disco e chama `refresh` em cada evento, o que mexe em
# @page, @list e @starting. O grafo saia da carga diferente de como entrou, e a
# peca resultante nunca batia com o original. Era isso que enchia o log de
# divergencias no `map_factory`, e nao qualquer coisa de ordenacao ou de tempo.
#
# Alem de errado, era caro: um load completo do save mais leituras de disco a
# cada upload, na thread principal, num telemovel.
#
# Aqui as pecas saem dos objectos VIVOS, no mesmo instante em que o save e
# montado. Sem load, sem disco, sem refresh a alterar nada.
#===============================================================================
module AnilSaveCorte
  module_function

  # Guardar o corte custa memoria (~o tamanho do save) e uma segunda passagem de
  # serializacao. So vale a pena se houver quem o consuma, ou seja, se o upload
  # parcial estiver de pe.
  def interessa?
    return false unless defined?(AnilSaveSecoes)
    # Offline nao ha upload nenhum, e o corte seria uma segunda passagem de
    # serializacao por cada autosave — e o autosave corre em toda troca de mapa.
    return false unless (AnilLanRework.connected? rescue false)
    true
  end

  def guardar(hash)
    return unless hash.is_a?(Hash)
    pecas = {}
    hash.each do |k, v|
      begin
        pecas[k.to_s] = Marshal.dump(v)
      rescue
        # Uma peca que nao serializa isolada invalida o corte inteiro: melhor
        # cair no caminho antigo do que enviar um conjunto incompleto.
        @pecas = nil
        return
      end
    end
    @pecas = pecas
  rescue
    @pecas = nil
  end

  # ⚠️ NAO se apaga ao ler.
  #
  # Apagar parecia limpo e estava errado: um mesmo save gera mais do que um
  # upload (o par item_added + save_hook), e o segundo ficava sem corte e caia
  # no caminho antigo. Como as duas formas de fatiar produzem bytes diferentes
  # — e essa e a descoberta toda —, os CRCs alternavam de referencia e TODAS as
  # seccoes passavam a parecer alteradas. Media-se 50 KB de "diferencas" num
  # save de 65 KB.
  #
  # O corte fica valido ate a gravacao seguinte o substituir.
  def actual
    @pecas
  end

  def limpar!
    @pecas = nil
  end
end

module SaveData
  class << self
    if !method_defined?(:anil_save_size_original_compile_save_hash)
      alias_method :anil_save_size_original_compile_save_hash, :compile_save_hash
      
      def compile_save_hash
        # Cache PERSISTENTE entre saves: os Data/MapXXX.rxdata nao mudam em
        # runtime (build de release), entao recarrega-los do disco a cada
        # autosave — que roda em TODA troca de mapa — era puro custo de I/O na
        # thread principal. Custo de memoria: ~30KB por mapa visitado na sessao.
        $save_optimizer_maps_cache ||= {}
        # Migrate PokeAPI cache from $PokemonGlobal if it is loaded
        if defined?(PokeAPI) && PokeAPI.respond_to?(:initialize_cache)
          PokeAPI.initialize_cache rescue nil
        end
        # Remove `@pokeapi_cache` instance variable from $PokemonGlobal if it exists
        if $PokemonGlobal && $PokemonGlobal.instance_variable_defined?(:@pokeapi_cache)
          $PokemonGlobal.instance_eval { remove_instance_variable(:@pokeapi_cache) rescue nil }
        end
        # Call original compile_save_hash
        # (o cache de mapas fica vivo para o proximo save — ver comentario acima)
        resultado = anil_save_size_original_compile_save_hash
        # As peças saem daqui, dos objectos vivos, e não de um load do ficheiro.
        AnilSaveCorte.guardar(resultado) if AnilSaveCorte.interessa?
        resultado
      end
    end

    if !method_defined?(:anil_save_size_original_load_all_values)
      alias_method :anil_save_size_original_load_all_values, :load_all_values
      
      def load_all_values(save_data)
        res = anil_save_size_original_load_all_values(save_data)
        # Migrate and remove pokeapi_cache immediately after load
        if defined?(PokeAPI) && PokeAPI.respond_to?(:initialize_cache)
          PokeAPI.initialize_cache rescue nil
        end
        if $PokemonGlobal && $PokemonGlobal.instance_variable_defined?(:@pokeapi_cache)
          $PokemonGlobal.instance_eval { remove_instance_variable(:@pokeapi_cache) rescue nil }
        end

        # Reconstruct Game_Event static references (@event, @page, @list) post-load
        if $map_factory && $map_factory.respond_to?(:maps) && $map_factory.maps
          $map_factory.maps.each do |map|
            next unless map.is_a?(Game_Map)
            next unless map.events
            raw_map = map.instance_variable_get(:@map)
            next unless raw_map && raw_map.respond_to?(:events)
            map.events.each do |id, event|
              next unless event.is_a?(Game_Event)
              if raw_map.events.key?(id)
                event.instance_variable_set(:@event, raw_map.events[id])
                event.refresh rescue nil
              end
            end
          end
        end
        if $game_map && $game_map.is_a?(Game_Map) && $game_map.events
          raw_map = $game_map.instance_variable_get(:@map)
          if raw_map && raw_map.respond_to?(:events)
            $game_map.events.each do |id, event|
              next unless event.is_a?(Game_Event)
              if raw_map.events.key?(id)
                event.instance_variable_set(:@event, raw_map.events[id])
                event.refresh rescue nil
              end
            end
          end
        end

        res
      end
    end
  end
end

#===============================================================================
# Monkey Patches para Otimização de Serialização
#===============================================================================

class Game_Map
  # Omitimos dados estáticos redundantes (RPG::Map e tabelas do tileset)
  def marshal_dump
    vars = {}
    instance_variables.each do |var|
      next if [:@map, :@passages, :@priorities, :@terrain_tags].include?(var)
      # Relogio da rolagem da neblina: e um System.uptime, muda a cada frame.
      # Mesma razao dos contadores do Game_Event aqui em baixo — ver o comentario
      # longo no marshal_dump de la. Grava-se nil porque o proprio Game_Map o
      # reinicializa: `@fog_scroll_last_update_timer = uptime_now if !@fog_...`.
      if var == :@fog_scroll_last_update_timer
        vars[var] = nil
        next
      end
      vars[var] = instance_variable_get(var)
    end
    vars
  end

  def marshal_load(vars)
    vars.each do |var, val|
      instance_variable_set(var, val)
    end
    @display_x = 0 if @display_x.nil?
    @display_y = 0 if @display_y.nil?
    @events = {} if @events.nil?

    # NAO purgar eventos daqui. Foi tentado em 2026-08-04 (remover de @events os
    # objetos sem @x/@y, o lixo que rebenta o at_coordinate?) e o jogo passou a
    # ficar preso na tela de "Carregando...". Este metodo corre DENTRO do
    # Marshal.load do save, com o grafo de objetos ainda a montar-se — apagar
    # entradas aqui nao e seguro. A blindagem em runtime (tile_id e
    # at_coordinate? no 040_Multiplayer_Post_Plugin_Patches) ja evita o crash sem
    # tocar em dados. Ver [[eventos-injetados-tile-id-nil]].

    # Re-inicializa a informação estática do mapa a partir do arquivo
    begin
      @map = load_data(sprintf("Data/Map%03d.rxdata", @map_id))
      updateTileset
      # Re-vincula os eventos IMEDIATAMENTE durante a desserialização!
      if @events
        @events.each do |id, event|
          next unless event.is_a?(Game_Event)
          if @map && @map.respond_to?(:events) && @map.events.key?(id)
            event.instance_variable_set(:@event, @map.events[id])
            event.refresh rescue nil
          end
        end
      end
    rescue => e
      echoln "[SaveSizeOptimizer] Erro ao re-inicializar mapa #{@map_id}: #{e.message}" rescue nil
    end
  end
end

class Game_Event
  # Omitimos o evento estático, página atual e lista de comandos apenas para eventos estáticos (do mapa rxdata)
  def marshal_dump
    vars = {}
    is_static = false
    begin
      map_id = @map_id
      if map_id && map_id > 0
        $save_optimizer_maps_cache ||= {}
        raw_map = $save_optimizer_maps_cache[map_id]
        if !raw_map
          raw_map = load_data(sprintf("Data/Map%03d.rxdata", map_id)) rescue nil
          $save_optimizer_maps_cache[map_id] = raw_map if raw_map
        end
        is_static = raw_map.events.key?(@id) if raw_map && raw_map.respond_to?(:events)
      end
    rescue => e
    end

    instance_variables.each do |var|
      if is_static && [:@event, :@page, :@list].include?(var)
        next
      end
      # Contadores de frame vao SEMPRE a zero.
      #
      # @stop_count e @anime_count sao somados a cada frame em Game_Character
      # (`@stop_count += @delta_t`), portanto mudam mesmo com o jogador parado.
      # Isso fazia a seccao `map_factory` nunca conseguir ficar igual entre dois
      # saves: era reenviada a cada upload por causa de um cronometro de NPC.
      #
      # Zerar e seguro porque e o estado de um jogo recem-carregado — sao "tempo
      # desde que parou de andar" e "tempo desde que trocou de sprite", ambos
      # reiniciados na pratica quando o mapa e montado. Grava-se 0 em vez de
      # omitir para que o marshal_load nao os deixe nil (nil + float rebenta).
      if [:@stop_count, :@anime_count, :@wait_count].include?(var)
        vars[var] = 0
        next
      end
      # ⚠️ ZERAR OS TRES DE CIMA NAO CHEGAVA.
      #
      # Medido em 19/08 comparando dois uploads do mesmo jogador com 6 segundos
      # de intervalo (badi, v942 -> v943): mudaram em 39 dos 39 eventos do mapa
      #
      #   @last_update_time   39/39   @delta_t   39/39   @stop_count   39/39
      #
      # Os dois primeiros nao estavam na lista, e sao os que mais pesam. Sao
      # Floats, e o Marshal grava Float como texto decimal de comprimento
      # VARIAVEL ("4228.882963999999" contra "4232.215085"), portanto a seccao
      # mudava de tamanho nos dois sentidos a cada frame. Era a razao de o
      # `map_factory` divergir em 98,3% dos uploads no relatorio de seccoes.
      #
      # Aqui vai nil, e nao 0, porque o Game_Character trata o nil sozinho no
      # inicio do update:
      #
      #   @last_update_time = time_now if !@last_update_time || ...
      #   @delta_t = time_now - @last_update_time
      #
      # Zerar com 0 daria um @delta_t gigante no primeiro frame; com nil o
      # relogio arranca do instante da carga. O @delta_t vai a 0 na mesma para
      # nunca ficar nil — ele e recalculado antes de qualquer uso, mas ha somas
      # (`@move_timer += @delta_t`) que nao sobrevivem a um nil se a ordem mudar.
      #
      # Guarda confirmada em TODOS os builds, incluindo o de 01/08, portanto um
      # save gravado assim carrega tambem em clientes que ainda nao atualizaram.
      if var == :@last_update_time
        vars[var] = nil
        next
      end
      if var == :@delta_t
        vars[var] = 0
        next
      end
      vars[var] = instance_variable_get(var)
    end
    vars
  end

  def marshal_load(vars)
    vars.each do |var, val|
      instance_variable_set(var, val)
    end
    # Saves gravados antes desta mudanca trazem os contadores cheios; e um save
    # antigo continua a carregar sem problema, mas normaliza-se aqui para que o
    # estado pos-carga seja o mesmo nos dois casos.
    @stop_count  = 0 if @stop_count.nil?
    @anime_count = 0 if @anime_count.nil?
    @wait_count  = 0 if @wait_count.nil?

    # ⚠️ OS CAMPOS DERIVADOS TAMBEM, E ESSES SO O SETTER SABE CALCULAR.
    #
    #   move_speed=      -> @move_time      (usado em pattern_update_speed)
    #   jump_speed=      -> @jump_time
    #   move_frequency=  -> @command_delay  (usado em update_command_new)
    #
    # Um evento montado pelo Marshal nao passa pelo initialize, e o
    # `Game_Map#marshal_load` so chama `refresh` nos eventos que existem no mapa
    # em disco — os dinamicos (Game_PokeEvent do VOE, id = @events.keys.max + 1)
    # ficam de fora e nunca veem nenhum destes setters. Andam pelo jogo com os
    # derivados a nil ate alguem lhes tocar, e ai rebentam com o jogador parado:
    #
    #   ArgumentError  comparison of Integer with nil failed   (@command_delay)
    #   NoMethodError  undefined method `*` for nil:NilClass   (@move_time)
    #
    # E como o dump copia as ivars tal e qual, o nil viaja de save em save.
    #
    # ⚠️ O move_frequency= tem `return if val == @move_frequency`, portanto
    # repo-lo com o valor que ja la esta nao faz nada. Zera-se antes.
    begin
      if !@move_time.is_a?(Numeric) || !@move_speed.is_a?(Numeric)
        v = @move_speed.is_a?(Numeric) && @move_speed > 0 ? @move_speed : 4
        self.move_speed = v
      end
      if !@jump_time.is_a?(Numeric)
        v = @jump_speed.is_a?(Numeric) && @jump_speed > 0 ? @jump_speed : 4
        self.jump_speed = v
      end
      if !@command_delay.is_a?(Numeric) || !@move_frequency.is_a?(Numeric)
        v = @move_frequency.is_a?(Numeric) && @move_frequency > 0 ? @move_frequency : 6
        @move_frequency = nil
        self.move_frequency = v
      end
    rescue
      @move_speed     = 4    unless @move_speed.is_a?(Numeric)
      @move_time      = 0.125 unless @move_time.is_a?(Numeric)
      @jump_time      = 0.125 unless @jump_time.is_a?(Numeric)
      @move_frequency = 6    unless @move_frequency.is_a?(Numeric)
      @command_delay  = 0    unless @command_delay.is_a?(Numeric)
    end
  end

  # Recuperação segura sob demanda de @event para evitar crashes de ordem de carregamento ou F5
  def event
    if !@event && @map_id && @id
      map_obj = nil
      if $game_map && $game_map.map_id == @map_id
        map_obj = $game_map
      elsif $map_factory
        map_obj = $map_factory.getMap(@map_id) rescue nil
      end
      if map_obj
        raw_map = map_obj.instance_variable_get(:@map)
        @event = raw_map.events[@id] if raw_map && raw_map.respond_to?(:events)
      end
    end
    @event
  end

  def name
    ev = self.event
    return ev ? ev.name : ""
  end

  def id
    ev = self.event
    return ev ? ev.id : @id
  end

  # Garante que @event esteja carregado antes de qualquer refresh de página/comandos
  if !method_defined?(:anil_save_size_original_refresh)
    alias_method :anil_save_size_original_refresh, :refresh rescue nil
    def refresh
      self.event
      anil_save_size_original_refresh rescue nil
    end
  end

  if !method_defined?(:anil_save_size_original_pbCheckEventTriggerAfterTurning)
    alias_method :anil_save_size_original_pbCheckEventTriggerAfterTurning, :pbCheckEventTriggerAfterTurning rescue nil
    def pbCheckEventTriggerAfterTurning
      return if !self.event
      anil_save_size_original_pbCheckEventTriggerAfterTurning
    end
  end

  if !method_defined?(:anil_save_size_original_over_trigger?)
    alias_method :anil_save_size_original_over_trigger?, :over_trigger? rescue nil
    def over_trigger?
      return false if !self.event
      anil_save_size_original_over_trigger?
    end
  end

  if !method_defined?(:anil_save_size_original_check_event_trigger_touch)
    alias_method :anil_save_size_original_check_event_trigger_touch, :check_event_trigger_touch rescue nil
    def check_event_trigger_touch(dir)
      return if !self.event
      anil_save_size_original_check_event_trigger_touch(dir)
    end
  end
end

class Game_Screen
  # Salvamos apenas as imagens ativas para economizar espaço
  def marshal_dump
    vars = {}
    instance_variables.each do |var|
      if var == :@pictures
        active_pics = []
        @pictures.each_with_index do |pic, idx|
          if pic && pic.name != ""
            active_pics << [idx, pic]
          end
        end
        vars[var] = active_pics
      else
        vars[var] = instance_variable_get(var)
      end
    end
    vars
  end

  def marshal_load(vars)
    # Re-inicializa as 100 imagens padrão por segurança para evitar que fique nil
    @pictures = [nil]
    (1..100).each { |i| @pictures.push(Game_Picture.new(i)) }

    # Inicializa variáveis críticas com valores padrão por segurança
    @weather_type      = :None
    @weather_max       = 0.0
    @weather_duration  = 0
    @brightness        = 255
    @tone              = Tone.new(0, 0, 0, 0)
    @flash_color       = Color.new(0, 0, 0, 0)
    @shake             = 0

    vars.each do |var, val|
      if var == :@pictures
        next if val.nil?
        # Restaura as imagens ativas
        val.each do |idx, pic|
          @pictures[idx] = pic if idx < @pictures.size
        end
      else
        instance_variable_set(var, val)
      end
    end

    # Garante que variáveis críticas não fiquem nil ou nulas após ler do save
    @weather_type      = :None if @weather_type.nil?
    @weather_max       = 0.0 if @weather_max.nil?
    @weather_duration  = 0 if @weather_duration.nil?
    @brightness        = 255 if @brightness.nil?
    @tone              = Tone.new(0, 0, 0, 0) if @tone.nil?
    @flash_color       = Color.new(0, 0, 0, 0) if @flash_color.nil?
    @shake             = 0 if @shake.nil?
  end
end

