#===============================================================================
# MOD: 049_Multiplayer_Coop_Full_Sync
#===============================================================================
# Cria o módulo "Coop Completo" que unifica e sincroniza perfeitamente o
# progresso da campanha e do mundo (Switches, Variáveis e Self-Switches) em tempo
# real de forma bidirecional, e integra encontros selvagens cooperativos.
#===============================================================================

class PokemonSystem
  attr_writer :coop_full_sync

  def coop_full_sync
    return 1 # 1 = Não (Desativado)
  end
end

module AnilLanRework
  def self.coop_full_sync?
    return false
  end
end

# MenuHandlers.add(:options_menu, :coop_full_sync, {
#   "name"        => _INTL("Coop Completo"),
#   "order"       => 87,
#   "type"        => EnumOption,
#   "parameters"  => [_INTL("Sim"), _INTL("Não")],
#   "description" => _INTL("Sincroniza Switches, Variáveis, NPCs e encontros selvagens com o parceiro."),
#   "get_proc"    => proc { next $PokemonSystem.coop_full_sync },
#   "set_proc"    => proc { |value, _scene| $PokemonSystem.coop_full_sync = value }
# })


#===============================================================================
# Ganchos de Sincronização Bidirecional em tempo real (Switches, Vars, Self-Sw)
#===============================================================================

class Game_Switches
  alias coop_full_sync_set []= unless method_defined?(:coop_full_sync_set)

  def []=(switch_id, value)
    coop_full_sync_set(switch_id, value)
    if AnilLanRework.connected? && AnilLanRework.coop_full_sync?
      unless Thread.current[:coop_syncing_switch]
        Thread.current[:coop_syncing_switch] = true
        begin
          AnilLanRework.connection.send_packet("coop_sync_switch", {
            "id" => switch_id,
            "val" => value
          }) rescue nil
        ensure
          Thread.current[:coop_syncing_switch] = nil
        end
      end
    end
  end
end

class Game_Variables
  alias coop_full_sync_set []= unless method_defined?(:coop_full_sync_set)

  def []=(variable_id, value)
    coop_full_sync_set(variable_id, value)
    if AnilLanRework.connected? && AnilLanRework.coop_full_sync?
      unless Thread.current[:coop_syncing_variable]
        Thread.current[:coop_syncing_variable] = true
        begin
          AnilLanRework.connection.send_packet("coop_sync_variable", {
            "id" => variable_id,
            "val" => value
          }) rescue nil
        ensure
          Thread.current[:coop_syncing_variable] = nil
        end
      end
    end
  end
end

class Game_SelfSwitches
  alias coop_full_sync_set []= unless method_defined?(:coop_full_sync_set)

  def []=(key, value)
    coop_full_sync_set(key, value)
    if AnilLanRework.connected? && AnilLanRework.coop_full_sync?
      unless Thread.current[:coop_syncing_self_switch]
        Thread.current[:coop_syncing_self_switch] = true
        begin
          cache_key = "#{key[0]}_#{key[1]}_#{key[2]}"
          AnilLanRework.connection.send_packet("coop_sync_self_switch", {
            "key" => cache_key,
            "val" => value
          }) rescue nil
        ensure
          Thread.current[:coop_syncing_self_switch] = nil
        end
      end
    end
  end
end

#===============================================================================
# Módulo de Processamento e Transmissão
#===============================================================================

module AnilLanRework
  module CoopFullSync
    def self.request_full_coop_sync
      return unless AnilLanRework.connected?
      return if AnilLanRework.host? # Apenas o Client solicita
      AnilLanRework.connection.send_packet("coop_full_sync_request", {}) rescue nil
      AnilLanRework.log("CoopFullSync: Solicitada sincronização completa de progresso do Host") rescue nil
    end

    def self.update_connection_sync
      current_state = AnilLanRework.connected? rescue false
      @last_connection_state ||= false
      if current_state && !@last_connection_state
        if !AnilLanRework.host? && AnilLanRework.coop_full_sync?
          request_full_coop_sync
        end
      end
      @last_connection_state = current_state
    end

    def self.handle_sync_switch(packet)
      return unless packet.is_a?(Hash)
      switch_id = packet["id"].to_i
      val = packet["val"]
      return if switch_id <= 0
      Thread.current[:coop_syncing_switch] = true
      begin
        $game_switches[switch_id] = val
        $game_map.need_refresh = true rescue nil
      ensure
        Thread.current[:coop_syncing_switch] = nil
      end
    end

    def self.handle_sync_variable(packet)
      return unless packet.is_a?(Hash)
      variable_id = packet["id"].to_i
      val = packet["val"]
      return if variable_id <= 0
      Thread.current[:coop_syncing_variable] = true
      begin
        $game_variables[variable_id] = val
        $game_map.need_refresh = true rescue nil
      ensure
        Thread.current[:coop_syncing_variable] = nil
      end
    end

    def self.handle_sync_self_switch(packet)
      return unless packet.is_a?(Hash)
      key_str = packet["key"].to_s
      val = packet["val"]
      parts = key_str.split("_")
      return unless parts.length == 3
      parsed_key = [parts[0].to_i, parts[1].to_i, parts[2].to_s]
      Thread.current[:coop_syncing_self_switch] = true
      begin
        $game_self_switches[parsed_key] = val
        $game_map.need_refresh = true rescue nil
      ensure
        Thread.current[:coop_syncing_self_switch] = nil
      end
    end

    def self.handle_full_sync_request(sender_id)
      return unless AnilLanRework.host?
      # Prepara o dump completo
      sw_data = $game_switches.instance_variable_get(:@data) rescue []
      var_data = $game_variables.instance_variable_get(:@data) rescue []
      self_sw_data = $game_self_switches.instance_variable_get(:@data) rescue {}

      self_sw_serialized = {}
      self_sw_data.each do |key, val|
        next unless key.is_a?(Array) && key.length == 3
        cache_key = "#{key[0]}_#{key[1]}_#{key[2]}"
        self_sw_serialized[cache_key] = val
      end

      AnilLanRework.connection.send_packet("coop_full_sync_data", {
        "to_id" => sender_id,
        "sw" => sw_data,
        "var" => var_data,
        "self_sw" => self_sw_serialized
      }) rescue nil
      AnilLanRework.log("CoopFullSync: Enviado dump completo do progresso para o parceiro #{sender_id}") rescue nil
    end

    def self.handle_full_sync_data(packet)
      return if AnilLanRework.host?
      Thread.current[:coop_syncing_switch] = true
      Thread.current[:coop_syncing_variable] = true
      Thread.current[:coop_syncing_self_switch] = true
      begin
        # Aplica os switches
        if packet["sw"].is_a?(Array)
          packet["sw"].each_with_index do |val, idx|
            next if idx == 0
            $game_switches[idx] = val rescue nil
          end
        end

        # Aplica as variáveis
        if packet["var"].is_a?(Array)
          packet["var"].each_with_index do |val, idx|
            next if idx == 0
            $game_variables[idx] = val rescue nil
          end
        end

        # Aplica os self switches
        if packet["self_sw"].is_a?(Hash)
          packet["self_sw"].each do |key_str, val|
            parts = key_str.to_s.split("_")
            next unless parts.length == 3
            parsed_key = [parts[0].to_i, parts[1].to_i, parts[2].to_s]
            $game_self_switches[parsed_key] = val rescue nil
          end
        end

        $game_map.need_refresh = true rescue nil
        AnilLanRework.log("CoopFullSync: Recebido e sincronizado o progresso total do Host com sucesso!") rescue nil
      ensure
        Thread.current[:coop_syncing_switch] = nil
        Thread.current[:coop_syncing_variable] = nil
        Thread.current[:coop_syncing_self_switch] = nil
      end
    end
  end
end

#===============================================================================
# Ganchos de Conexão e Roteamento de Pacotes
#===============================================================================

module AnilLanRework
  module Router
    class << self
      alias coop_full_sync_route_packet route_packet unless method_defined?(:coop_full_sync_route_packet)

      def route_packet(packet)
        if AnilLanRework.coop_full_sync?
          begin
            case packet["type"]
            when "coop_sync_switch"
              AnilLanRework::CoopFullSync.handle_sync_switch(packet)
            when "coop_sync_variable"
              AnilLanRework::CoopFullSync.handle_sync_variable(packet)
            when "coop_sync_self_switch"
              AnilLanRework::CoopFullSync.handle_sync_self_switch(packet)
            when "coop_full_sync_request"
              AnilLanRework::CoopFullSync.handle_full_sync_request(packet["sender_id"].to_s)
            when "coop_full_sync_data"
              AnilLanRework::CoopFullSync.handle_full_sync_data(packet)
            end
          rescue => e
            AnilLanRework.log("Erro no roteamento coop full sync: #{e.message}") rescue nil
          end
        end
        coop_full_sync_route_packet(packet)
      end
    end
  end
end

class Game_Map
  alias coop_full_sync_setup setup unless method_defined?(:coop_full_sync_setup)

  def setup(map_id)
    coop_full_sync_setup(map_id)
    @pending_coop_full_sync_request = true
  end
end

class Scene_Map
  alias coop_full_sync_update update unless method_defined?(:coop_full_sync_update)

  def update
    coop_full_sync_update
    if $game_map && $game_map.instance_variable_get(:@pending_coop_full_sync_request)
      $game_map.instance_variable_set(:@pending_coop_full_sync_request, false)
      if AnilLanRework.connected? && AnilLanRework.coop_full_sync? && !AnilLanRework.host?
        AnilLanRework::CoopFullSync.request_full_coop_sync
      end
    end
    if AnilLanRework.connected? && AnilLanRework.coop_full_sync?
      AnilLanRework::CoopFullSync.update_connection_sync
    end
  end
end

#===============================================================================
# Sincronização Perfeita de Encontros Selvagens (Supressão de encontros no Cliente)
#===============================================================================

module AnilLanRework
  module BattleSync
    class << self
      alias coop_full_sync_suppress_local_wild_battle suppress_local_wild_battle? unless method_defined?(:coop_full_sync_suppress_local_wild_battle)

      def suppress_local_wild_battle?
        if AnilLanRework.connected? && AnilLanRework.coop_full_sync? && !AnilLanRework.host?
          return true
        end
        coop_full_sync_suppress_local_wild_battle
      end
    end
  end
end

AnilLanRework.log("AnilLanRework_CoopFullSync (Full Coop System v1) loaded OK")
