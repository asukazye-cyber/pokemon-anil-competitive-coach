# encoding: UTF-8
#===============================================================================
# MOD: 102_Multiplayer_Lag_Killer
#-------------------------------------------------------------------------------
# Realiza a limpeza periódica e preventiva de conexões de outros jogadores
# inativos para evitar gargalo e lag por acúmulo.
#===============================================================================

class Spriteset_Map
  alias lag_killer_original_update update unless method_defined?(:lag_killer_original_update)

  def update
    lag_killer_original_update

    # 1. Se desconectado, limpa a lista global de players para evitar lixo acumulado de sessões antigas
    if !AnilLanRework.connected?
      if AnilLanRework.players && !AnilLanRework.players.empty?
        AnilLanRework.players.clear
      end
      return
    end

    return unless AnilLanRework.enabled? && $game_map && @map.map_id == $game_map.map_id

    # 2. Limpeza periódica de peers inativos (a cada 120 frames / ~3 segundos)
    cf = Graphics.frame_count rescue 0
    if (cf % 120) == 0
      now_time = Time.now.to_f
      stale_peers = []
      current_map_id = $game_map.map_id
      AnilLanRework.players.each do |peer_id, peer|
        next if peer_id.to_s == AnilLanRework.self_internal_id.to_s
        peer.last_update_time ||= now_time
        limit = (peer.map_id == current_map_id) ? 300.0 : 60.0
        if now_time - peer.last_update_time > limit
          stale_peers << peer_id
        end
      end
      stale_peers.each do |peer_id|
        AnilLanRework.players.delete(peer_id)
      end
    end
  end
end
