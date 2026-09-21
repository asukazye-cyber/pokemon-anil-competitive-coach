#===============================================================================
# MOD: 101_Force_Complete_Mode
#-------------------------------------------------------------------------------
# 1. Redireciona a transferência do jogador do mapa 104 (Seleção de modo)
#    diretamente para o mapa 217 (quarto) com o Modo Completo ativado.
# 2. Silencia as mensagens de conexão de rede durante a introdução de novo jogo,
#    exibindo popups no topo da tela em vez de diálogos bloqueantes de NPC.
#===============================================================================

class Scene_Map
  unless method_defined?(:force_complete_transfer_player)
    alias force_complete_transfer_player transfer_player
  end

  def transfer_player(*args)
    if $game_temp && $game_temp.player_new_map_id == 104
      $game_temp.player_new_map_id = 217 rescue nil
      $game_temp.player_new_x = 10 rescue nil
      $game_temp.player_new_y = 7 rescue nil
      $game_temp.player_new_direction = 2 rescue nil

      # Força as configurações do Modo Completo
      # O Modo Completo em Pokémon Añil é caracterizado por ter MODO_CLASICO (64)
      # e MODO_RADICAL (666) definidos como false, bem como outras variantes desativadas.
      if $game_switches
        $game_switches[64] = false   # MODO_CLASICO = OFF
        $game_switches[666] = false  # MODO_RADICAL = OFF
        $game_switches[109] = false  # Helper Switch 109 = OFF
        $game_switches[110] = false  # Helper Switch 110 = OFF
        $game_switches[111] = false  # Helper Switch 111 = OFF
        $game_switches[147] = false  # MODO_VGC = OFF
        $game_switches[148] = false  # MODO_INVERSO = OFF
        $game_switches[149] = false  # MODO_SIN_GRINDEO = OFF
        $game_switches[323] = true   # Switch de controle / inicialização concluída = ON
      end
    end
    
    force_complete_transfer_player(*args)
  end
end

module AnilLanRework
  class << self
    unless method_defined?(:force_complete_trigger_auto_connect)
      alias force_complete_trigger_auto_connect trigger_auto_connect_on_map
    end

    def trigger_auto_connect_on_map(silent = false)
      # Se estiver criando um savegame (Novo Jogo ativo) ou no mapa de introdução/Oak (Mapa 1 ou 104), força silent para true
      is_new_game = $game_temp && $game_temp.respond_to?(:begun_new_game) && $game_temp.begun_new_game
      is_intro_map = $game_map && ($game_map.map_id == 1 || $game_map.map_id == 104 || $game_map.map_id == 29)
      no_save_file = !(SaveData.exists? rescue false)

      if is_new_game || is_intro_map || no_save_file
        silent = true
      end
      force_complete_trigger_auto_connect(silent)
    end
  end
end

# Hook global em Kernel.pbMessage para limpar escape-chars duplicados (evita mostrar literal \wt[45]\^ na tela)
module Kernel
  unless method_defined?(:anil_orig_pbMessage)
    alias anil_orig_pbMessage pbMessage
  end

  def pbMessage(message, *args, &block)
    if message.is_a?(String)
      message = message.gsub("\\\\wt", "\\wt").gsub("\\\\^", "\\^")
    end
    anil_orig_pbMessage(message, *args, &block)
  end
  module_function :pbMessage
end
