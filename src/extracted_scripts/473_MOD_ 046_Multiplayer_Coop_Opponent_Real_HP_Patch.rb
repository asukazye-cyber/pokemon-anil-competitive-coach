#===============================================================================
# MOD: 046_Multiplayer_Coop_Opponent_Real_HP_Patch
#-------------------------------------------------------------------------------
# Altera a exibição do HP dos oponentes em batalha para mostrar o HP Real
# (ex: 80/112) ao invés da porcentagem (ex: 71%), facilitando o planejamento
# estratégico cooperativo e deixando a interface muito mais clara!
#===============================================================================

if defined?(Battle::Scene::PokemonDataBox)
  class Battle::Scene::PokemonDataBox
    alias opponent_hp_original_initializeDataBoxGraphic initializeDataBoxGraphic unless method_defined?(:opponent_hp_original_initializeDataBoxGraphic)
    
    def initializeDataBoxGraphic(sideSize)
      opponent_hp_original_initializeDataBoxGraphic(sideSize)
      
      # Se o battler for do oponente (index ímpar), exibe o HP real em números ao invés de porcentagem
      if @battler && !@battler.index.even?
        @show_hp_numbers = true
        @show_hp_percent = false
      end
    end
  end
end
