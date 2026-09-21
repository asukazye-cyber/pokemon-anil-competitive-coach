# encoding: utf-8
#===============================================================================
# 0000_Disable_Debug_Logs.rb
#-------------------------------------------------------------------------------
# Kill-switch central para TODA a escrita de logs de debug em disco.
#
# Vários scripts fazem File.open("...debug.txt","a") direto, gerando arquivos
# gigantes no PC do jogador. Este patch intercepta File.open / File.new /
# File.write / IO.write APENAS para os nomes de arquivo de debug conhecidos
# (por basename); qualquer outro arquivo (saves, configs, etc.) passa intacto.
#
# Para reativar os logs em desenvolvimento: defina  $ENABLE_DEBUG_LOGS = true
#===============================================================================
begin
  require 'stringio'
rescue LoadError
end

# NAO ligar isto para diagnosticar um bug pontual. Foi tentado em 2026-08-01 e
# travou o "recuperar partida": isto desbloqueia TODOS os ficheiros da lista
# BLOCKED de uma vez (cloud_save_debug.txt, multiplayer_packet_log.txt, etc.), e
# o append_log_line abre e fecha o ficheiro A CADA LINHA. No recover, que ja
# escreve o save inteiro e recarrega o mapa, isso e disco suficiente para o jogo
# parecer congelado.
#
# Para diagnosticar, usar antes um ficheiro PROPRIO com nome novo (fora da lista
# BLOCKED) — e o que o 129_Boss_Switch_Repair e o CoopCC fazem. Grava na mesma,
# custa quase nada e nao afeta mais nada.
$ENABLE_DEBUG_LOGS = false if $ENABLE_DEBUG_LOGS.nil?

module DebugLogSink
  # Somente arquivos de SAÍDA de debug. NÃO inclua configs (multiplayer_ip.txt,
  # multiplayer_session.ini, machine_id, vps_ip, player.txt) — esses são lidos/usados.
  BLOCKED = %w[
    menu_debug.txt multiplayer_packet_log.txt cloud_save_debug.txt mouse_debug.txt
    mouse_clicks_log.txt mouse_calibration_log.txt debug_particles.txt egg_debug.txt
    multiplayer_debug.txt multiplayer_battle_debug.txt animated_bitmap_error.txt
    engine_methods.txt title_debug.txt debug.txt unstuck_debug.log
    multiplayer_evolution_debug.log multiplayer_reload_errors.txt
    multiplayer_fps_debug.log joiplay_path_debug.txt npc_life_debug.txt
    detailed_battle_log.txt
    anil_eventos_quebrados.txt
  ].each_with_object({}) { |n, h| h[n.downcase] = true }.freeze

  # anil_eventos_quebrados.txt: diagnostico do Game_Map#anil_avisar_evento_quebrado
  # (evento injetado por mod chegando sem x/y/tile_id). Ja identificou o culpado
  # — Game_PokeEvent sem nenhum ivar — entao fica silenciado. Para investigar de
  # novo, basta $ENABLE_DEBUG_LOGS = true, como qualquer outro daqui.
  #
  # NAO entra na lista: mouse_calibration.txt, mouse_calibration_raw.txt,
  # mouse_s0_raw.txt e mouse_s5_raw.txt. Apesar do nome, guardam estado da
  # calibragem do mouse e sao LIDOS de volta pelo jogo.

  def self.write_mode?(mode)
    return false unless mode.is_a?(String)
    m = mode.downcase
    m.include?("w") || m.include?("a")
  end

  def self.blocked?(path)
    return false if $ENABLE_DEBUG_LOGS
    return false unless path.is_a?(String)
    base = (File.basename(path) rescue nil).to_s.downcase
    BLOCKED[base] ? true : false
  end
end

module DebugLogIOPatch
  # File.open / IO.open
  def open(path, *args, &block)
    begin
      if DebugLogSink.blocked?(path) && DebugLogSink.write_mode?(args[0])
        sink = (defined?(StringIO) ? StringIO.new : nil)
        if sink
          if block
            begin
              return block.call(sink)
            ensure
              sink.close rescue nil
            end
          else
            return sink
          end
        end
      end
    rescue
      # Nunca deixa a interceptação quebrar I/O normal: cai no fluxo original.
    end
    super
  end

  # File.new
  def new(path, *args, &block)
    begin
      if DebugLogSink.blocked?(path) && DebugLogSink.write_mode?(args[0]) && defined?(StringIO)
        return StringIO.new
      end
    rescue
    end
    super
  end

  # File.write / IO.write
  def write(path, *args)
    begin
      return 0 if DebugLogSink.blocked?(path)
    rescue
    end
    super
  end
end

class << File
  prepend DebugLogIOPatch
end
class << IO
  prepend DebugLogIOPatch
end
