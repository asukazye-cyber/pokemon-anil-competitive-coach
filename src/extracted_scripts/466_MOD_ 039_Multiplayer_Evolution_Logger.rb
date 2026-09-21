#===============================================================================
# MOD: 039_Multiplayer_Evolution_Logger.rb
#-------------------------------------------------------------------------------
# Logger dedicado para rastrear minuciosamente a fase de evolução.
# O arquivo será salvo na pasta raiz como `multiplayer_evolution_debug.log`.
#===============================================================================

module AnilLanRework
  module EvoLogger
    LOG_FILE = "multiplayer_evolution_debug.log"

    def self.context_snapshot(extra = nil)
      ctx = AnilLanRework::BattleSync.active_context rescue nil
      {
        "mode"              => (ctx&.mode || :solo).to_s,
        "battle_id"         => (ctx&.battle_id || "none").to_s,
        "turn"              => ((ctx&.battle&.turnCount rescue nil) || "n/a").to_s,
        "connected"         => (AnilLanRework.connected? rescue false).to_s,
        "in_battle"         => (($game_temp.in_battle rescue false)).to_s,
        "local_lock_depth"  => ((ctx&.instance_variable_get(:@anil_manual_lock_depth) rescue 0) || 0).to_s,
        "remote_lock"       => ((ctx&.instance_variable_get(:@anil_remote_manual_lock) rescue false)).to_s,
        "remote_reason"     => ((ctx&.instance_variable_get(:@anil_remote_manual_reason) rescue nil) || "none").to_s,
        "fast_evolution"    => ((($PokemonSystem.fast_evolution || 0) rescue "ERROR")).to_s
      }.merge(extra || {})
    rescue
      extra || {}
    end

    def self.format_kv(data)
      return "" if !data || data.empty?
      data.map { |k, v| "#{k}=#{v.inspect}" }.join(" ")
    end

    def self.caller_summary(depth = 6)
      caller_locations(2, depth).map do |loc|
        "#{File.basename(loc.path)}:#{loc.lineno}:#{loc.base_label}"
      end.join(" <- ")
    rescue
      "caller_unavailable"
    end

    def self.log(msg, extra = nil)
      return unless defined?($anil_debug_log_enabled) && $anil_debug_log_enabled
      snapshot = context_snapshot(extra)
      payload = format_kv(snapshot)
      line = payload.empty? ? msg.to_s : "#{msg} #{payload}"

      # Também manda pro log principal pra garantir
      AnilLanRework.log("[EVO_TRACK] #{line}") rescue nil

      begin
        time_str = Time.now.strftime("%Y-%m-%d %H:%M:%S.%L")
        File.open(LOG_FILE, "a") do |f|
          f.puts("[#{time_str}] #{line}")
        end
      rescue => e
        # Falha silenciosa se não conseguir escrever
      end
    end

    def self.phase(phase_name, extra = nil)
      data = context_snapshot(extra || {})
      data["phase"] = phase_name.to_s
      data["caller"] ||= caller_summary
      log("phase", data)
    end
    
    def self.clear
      File.delete(LOG_FILE) if File.exist?(LOG_FILE) rescue nil
    end
  end
end

AnilLanRework::EvoLogger.log("Evolution Logger Inicializado!")
