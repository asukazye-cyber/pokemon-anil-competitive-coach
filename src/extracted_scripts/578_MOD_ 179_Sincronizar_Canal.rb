# encoding: UTF-8
#===============================================================================
# MOD: 179_Sincronizar_Canal
#-------------------------------------------------------------------------------
# Confirma que o canal que o SERVIDOR nos deu e o mesmo que o jogo mostra.
#
# ⚠️ O CANAL VIVE DENTRO DO SAVE.
#
# O `$PokemonSystem` e uma das seccoes do save (`pokemon_system`), e e ele que
# guarda o `multiplayer_channel`. Antes de o save carregar, o objecto e o de
# fabrica — e o de fabrica e canal 1.
#
# O pacote de entrada leva o canal:
#
#     "channel_id" => ($PokemonSystem ? $PokemonSystem.multiplayer_channel : 1)
#
# Se a ligacao se estabelecer antes de o save assentar, o servidor recebe 1. O
# save carrega a seguir, o menu do F7 passa a dizer 8, e ninguem repara que os
# dois lados discordam.
#
# O sintoma nao e o menu: e tudo o que depende do canal. Itens largados que nao
# aparecem, jogadores que nao se veem, spawns que nao chegam — porque estao a
# ser servidos para o canal 1 enquanto o jogador acha que esta no 8.
#
# ⚠️ NAO SE ADIVINHA QUEM ESTA CERTO: MANDA O JOGO.
#
# O canal que o jogador escolheu esta no save dele. Se os dois discordarem, o
# servidor e que tem de mudar — e para isso ja existe o `change_channel`.
#===============================================================================

module AnilSincCanal
  ACTIVO = true

  # De quantos em quantos frames se confere. Isto nao muda depressa.
  INTERVALO = 60

  module_function

  def log(t)
    AnilLanRework.log("[CANAL] #{t}") rescue nil
  end

  def canal_do_jogo
    ($PokemonSystem ? $PokemonSystem.multiplayer_channel.to_i : 1)
  rescue
    1
  end

  # O que dissemos ao servidor da ultima vez. Guardado a parte de proposito: e a
  # unica forma de saber que os dois lados discordam.
  def canal_anunciado
    @anunciado.to_i
  end

  def marcar_anunciado!(n)
    @anunciado = n.to_i
  end

  def verificar!
    return unless ACTIVO
    return unless (AnilLanRework.connected? rescue false)
    agora = canal_do_jogo
    return if agora <= 0
    return if agora == canal_anunciado

    AnilLanRework.connection.send_packet("change_channel", "channel_id" => agora)
    log("o jogo esta no canal #{agora} e o servidor tinha #{canal_anunciado}; corrigido")
    marcar_anunciado!(agora)

    # ⚠️ E pede-se outra vez o que depende do canal.
    #
    # Mudar de canal nao recarrega o mapa, portanto os itens largados do canal
    # novo nunca chegariam sozinhos. Ver o MOD 178.
    (AnilRefreshItens.marcar!("canal corrigido para #{agora}") rescue nil)
  rescue => e
    log("falha ao verificar: #{e.class}: #{e.message}")
  end
end

#-------------------------------------------------------------------------------
# ⚠️ O canal anunciado marca-se no JOIN, que e o unico sitio que sabe o que foi
# realmente enviado.
#-------------------------------------------------------------------------------
module AnilLanRework
  class Connection
    unless method_defined?(:anil_sinccanal_orig_send_packet)
      alias_method :anil_sinccanal_orig_send_packet, :send_packet

      # A assinatura real e `send_packet(type, payload = {})` — um hash so.
      def send_packet(type, payload = {})
        ret = anil_sinccanal_orig_send_packet(type, payload)
        begin
          t = type.to_s
          if (t == "join" || t == "change_channel") && payload.is_a?(Hash)
            ch = payload["channel_id"] || payload[:channel_id]
            AnilSincCanal.marcar_anunciado!(ch) if ch
          end
        rescue
          nil
        end
        ret
      end
    end
  end
end

#-------------------------------------------------------------------------------
# A verificacao, de segundo a segundo enquanto se joga.
#
# Nao chega faze-la uma vez ao carregar: o save pode assentar depois, e uma
# reconexao volta a pôr o servidor no canal que ele tinha antes.
#-------------------------------------------------------------------------------
if defined?(Scene_Map) && !Scene_Map.method_defined?(:anil_sinccanal_orig_update)
  Scene_Map.class_eval do
    alias_method :anil_sinccanal_orig_update, :update

    def update(*a)
      anil_sinccanal_orig_update(*a)
      begin
        @anil_sinccanal_t = (@anil_sinccanal_t || 0) + 1
        if @anil_sinccanal_t >= AnilSincCanal::INTERVALO
          @anil_sinccanal_t = 0
          AnilSincCanal.verificar!
        end
      rescue
        nil
      end
    end
  end
end
