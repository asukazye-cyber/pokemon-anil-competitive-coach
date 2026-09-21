# ==============================================================================
# Patch to disable the Cable Club (Battle and Trade) in Pokemon Centers
# ==============================================================================

module PluginManager
  class << self
    alias __disable_cable_club_runPlugins runPlugins unless method_defined?(:__disable_cable_club_runPlugins)
    def runPlugins(*args)
      __disable_cable_club_runPlugins(*args)
      
      ::Object.class_eval do
        def pbCableClub(*args)
          pbMessage(_INTL("Estamos fechados, sinto muito."))
          return false
        end

        def pbChangeOnlineTrainerType(*args)
          pbMessage(_INTL("Estamos fechados, sinto muito."))
          return false
        end

        def pbChangeOnlineWinText(*args)
          pbMessage(_INTL("Estamos fechados, sinto muito."))
          return false
        end

        def pbChangeOnlineLoseText(*args)
          pbMessage(_INTL("Estamos fechados, sinto muito."))
          return false
        end
      end
    end
  end
end

module Game
  class << self
    alias __disable_cable_club_initialize initialize unless method_defined?(:__disable_cable_club_initialize)
    def initialize(*args)
      __disable_cable_club_initialize(*args)
      
      # Override Common Event 12 (NPC Online Antiguo) command list to show the closed message immediately
      if $data_common_events && $data_common_events[12]
        cmd_text = RPG::EventCommand.new
        cmd_text.instance_variable_set(:@code, 101)
        cmd_text.instance_variable_set(:@indent, 0)
        cmd_text.instance_variable_set(:@parameters, ["Estamos fechados, sinto muito."])
        
        cmd_end = RPG::EventCommand.new
        cmd_end.instance_variable_set(:@code, 0)
        cmd_end.instance_variable_set(:@indent, 0)
        cmd_end.instance_variable_set(:@parameters, [])
        
        $data_common_events[12].instance_variable_set(:@list, [cmd_text, cmd_end])
      end
    end
  end
end
