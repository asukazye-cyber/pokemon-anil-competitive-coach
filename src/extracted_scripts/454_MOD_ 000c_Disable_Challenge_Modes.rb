#===============================================================================
# MOD: 000c_Disable_Challenge_Modes.rb
#-------------------------------------------------------------------------------
# Desativa permanentemente os modos de desafio (Nuzlocke/Permalocke) e o
# randomizador (Randomizer) no início do jogo, e remove as opções de escolha
# de modo (o jogo roda apenas no modo completo padrão).
# Também bloqueia a abertura do menu de regras no PC do quarto.
#===============================================================================

module ChallengeModes
  class << self
    def running?
      false
    end

    def on?(rule = nil)
      false
    end

    def start
      # Não faz nada - impede a abertura do menu ao iniciar um Novo Jogo
    end

    def open_rules_menu
      pbMessage(_INTL("O jogo está rodando no modo completo. As regras de desafios estão desativadas."))
    end

    def select_mode(preselected_rules = [])
      []
    end

    def select_custom_rules(preselected_rules = [])
      []
    end

    def display_rules(rules = [])
      # Não faz nada
    end
  end
end

module RandomizedChallenge
  class << self
    def enabled?
      false
    end

    def randomize_pokemon?
      false
    end

    def random_abilities?
      false
    end

    def moves_on?
      false
    end

    def tm_compat_on?
      false
    end

    def progressive?
      false
    end

    def types_on?
      false
    end

    def randomize_trainers?
      false
    end

    def randomize_starters?
      false
    end

    def semi_random_mode?
      false
    end

    def remember_trainer_teams?
      false
    end

    def randomize_trainers_items?
      false
    end
  end
end

module RandomizerConfigurator
  class << self
    def open_configurator(display = false, preselected_rules = {})
      pbMessage(_INTL("O jogo está rodando no modo completo. O modo Randomizer está desativado."))
      false
    end

    def select_mode(preselected_rules = {})
      {}
    end

    def select_custom_rules(preselected_rules = {}, rules_hash = {})
      {}
    end
  end
end
