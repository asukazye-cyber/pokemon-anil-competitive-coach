#===============================================================================
# MOD: 067_Pokemon_Center_Mug_Fix.rb
#-------------------------------------------------------------------------------
# Limita a interação com a xícara do Centro Pokémon (Evento Comum 6)
# para que conceda 10 Doce Raro apenas uma vez por ID do Jogador no servidor.
# Executa uma animação de despedaçamento e oculta a xícara do mapa.
#===============================================================================

class Game_Temp
  attr_accessor :rare_candy_claimed
end

# Remove o tile 475 da camada 2 (que representa a xícara física no balcão)
# MODIFICADO: A xícara agora permanece visível no balcão de forma permanente.
def hide_claimed_mug
  # Não faz nada para manter a xícara visível
end

# Animação personalizada de quebra (efeito chafariz suave de partículas)
# MODIFICADA: Desativada para evitar problemas de sprites no Joiplay.
def break_mug_animation(event)
  # Não faz nada, a xícara permanece intacta
end

module AnilLanRework
  module Router
    class << self
      alias anil_mug_fix_route_packet route_packet unless method_defined?(:anil_mug_fix_route_packet)
      
      def route_packet(packet)
        if packet["type"] == "rare_candy_status"
          $game_temp.rare_candy_claimed = packet["claimed"] ? true : false
          # Não ocultamos mais a xícara
          return
        end
        anil_mug_fix_route_packet(packet)
      end
    end
  end
end

def get_rare_candies
  # Se já foi pego localmente (Switch 800) ou no servidor, exibe a mensagem de indisponibilidade
  if $game_switches && $game_switches[800]
    pbMessage(_INTL("Não tem mais nada aqui..."))
    return
  end
  if defined?(AnilLanRework) && AnilLanRework.connected?
    if defined?($game_temp.rare_candy_claimed) && $game_temp.rare_candy_claimed == true
      pbMessage(_INTL("Não tem mais nada aqui..."))
      return
    end
    
    # Se ainda não recebemos a resposta da rede, requisita e aguarda
    if defined?($game_temp.rare_candy_claimed) && $game_temp.rare_candy_claimed.nil?
      AnilLanRework.connection.send_packet("check_rare_candy", {
        "player_id" => AnilLanRework.self_internal_id
      }) rescue nil
      
      start_time = Time.now.to_f
      while (defined?($game_temp.rare_candy_claimed) ? $game_temp.rare_candy_claimed.nil? : true) && (Time.now.to_f - start_time < 1.5)
        Graphics.update rescue nil
        Input.update rescue nil
        if AnilLanRework.respond_to?(:connection) && AnilLanRework.connection
          AnilLanRework.connection.update rescue nil
          AnilLanRework.connection.drain { |packet| AnilLanRework::Router.route_packet(packet) } rescue nil
        end
        sleep(0.02)
      end
    end
    
    # Exibe a mensagem de indisponibilidade se o servidor confirmar que já foi pego
    if defined?($game_temp.rare_candy_claimed) && $game_temp.rare_candy_claimed == true
      pbMessage(_INTL("Não tem mais nada aqui..."))
      return
    end
  end

  # Fluxo de recebimento (apenas 10 Rare Candies)
  if pbReceiveItem(:RARECANDY, 10)
    $game_switches[800] = true if $game_switches
    
    # Sem animação visual de quebra para evitar bugs no Joiplay
    
    if defined?(AnilLanRework) && AnilLanRework.connected?
      AnilLanRework.connection.send_packet("claim_rare_candy", {
        "player_id" => AnilLanRework.self_internal_id
      }) rescue nil
      $game_temp.rare_candy_claimed = true if defined?($game_temp)
    end
  end
end

EventHandlers.add(:on_enter_map, :prefetch_rare_candy, proc { |_old_map_id|
  # Não ocultamos mais a xícara ao entrar no mapa
  
  if defined?(AnilLanRework) && AnilLanRework.connected?
    $game_temp.rare_candy_claimed = nil if defined?($game_temp)
    AnilLanRework.connection.send_packet("check_rare_candy", {
      "player_id" => AnilLanRework.self_internal_id
    }) rescue nil
  end
})
