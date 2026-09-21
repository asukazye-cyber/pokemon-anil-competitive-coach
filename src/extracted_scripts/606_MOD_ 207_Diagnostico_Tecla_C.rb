# encoding: UTF-8
#===============================================================================
# MOD: 207_Diagnostico_Tecla_C
#-------------------------------------------------------------------------------
# PORQUE E QUE O C NAO FAZ NADA LOGO A SEGUIR A ENTRAR.
#
# ⚠️ ISTO NAO CORRIGE NADA. E UM TESTEMUNHO, E E DE PROPOSITO.
#
# O relato e claro e reprodutivel — "assim que entro no jogo o C nao funciona;
# mudo de mapa e volto e passa a funcionar" — mas o caminho do C tem SETE
# portoes, e qualquer um deles produz exactamente o mesmo sintoma: nada. Passei
# esta ronda a eliminar hipoteses por leitura e cheguei a lista curta sem
# conseguir escolher dentro dela:
#
#     $game_temp.message_window_showing   uma caixa de texto que ficou aberta
#     ChatInputHUD.input_blocked?         o chat, ou a carencia pos-fecho
#     pbMapInterpreterRunning?            um evento preso no save
#     $PokemonGlobal.forced_movement?     gelo ou queda de agua a meio
#     $game_temp.in_menu / in_mini_update bandeiras que ficaram levantadas
#     um gancho no Input.trigger?         alguem a responder "nao" por nos
#     $game_system.menu_disabled          (so afecta o menu, mas fica no registo)
#
# E eu ja adivinhei de mais neste projecto esta semana. Uma linha escrita no
# momento em que o C e carregado e recusado vale mais do que outra ronda inteira
# de deducao — diz o portao pelo nome e acaba com a conversa.
#
# ⚠️ LE-SE A TECLA FISICA, E NAO O BOTAO.
#
# Se o problema for um gancho no `Input.trigger?` a responder "nao", perguntar
# pelo `Input::USE` nao da por nada: o proprio diagnostico levava a mesma
# resposta falsa que anda a investigar. O `triggerex?(:C)` le a tecla do
# teclado, antes de qualquer mapeamento e fora do alcance de todos os ganchos.
#
# Quando isto estiver resolvido, poe-se o ACTIVO a false (ou tira-se o ficheiro).
#===============================================================================

module AnilDiagTeclaC
  ACTIVO   = true
  FICHEIRO = "anil_tecla_c.log"
  # Uma linha por carregar na tecla chega e sobra. O tecto existe para o
  # ficheiro nao crescer se alguem deixar o dedo em cima do C uma tarde inteira.
  TECTO    = 300
  ESPACO   = 0.4    # segundos entre duas linhas

  @escritas = 0
  @ultima   = 0.0
  @confirmadas = 0

  class << self
    def agora
      Time.now.to_f
    rescue
      0.0
    end

    def escrever(t)
      return if @escritas >= TECTO
      @escritas += 1
      linha = "%s  %s" % [Time.now.strftime("%H:%M:%S.%L"), t]
      (File.open(FICHEIRO, "a") { |f| f.puts(linha) } rescue nil)
    rescue
      nil
    end

    def sim_nao(v)
      v ? "SIM" : "nao"
    rescue
      "?"
    end

    # Todos os portoes, pela ordem por que o `Scene_Map#update` lhes bate.
    def portoes
      p = []
      p << ["mensagem_aberta", ($game_temp && $game_temp.message_window_showing rescue false)]
      p << ["chat_bloqueia", (defined?(AnilLanRework::ChatInputHUD) &&
                              AnilLanRework::ChatInputHUD.respond_to?(:input_blocked?) &&
                              AnilLanRework::ChatInputHUD.input_blocked? rescue false)]
      p << ["evento_a_correr", (pbMapInterpreterRunning? ? true : false rescue false)]
      p << ["movimento_forcado", ($PokemonGlobal && $PokemonGlobal.forced_movement? rescue false)]
      p << ["no_menu", ($game_temp && $game_temp.in_menu rescue false)]
      p << ["mini_update", ($game_temp && $game_temp.in_mini_update rescue false)]
      p << ["em_batalha", ($game_temp && $game_temp.in_battle rescue false)]
      p << ["rota_forcada", ($game_player && $game_player.move_route_forcing rescue false)]
      p << ["a_transferir", ($game_temp && $game_temp.player_transferring rescue false)]
      # ⚠️ O botao contra a tecla: se a tecla esta em baixo e o botao diz que
      # nao, ha um gancho a engolir — e o nome dele e a resposta toda.
      p << ["botao_recusado", !((Input.trigger?(Input::USE) rescue false))]
      p
    rescue
      []
    end

    # O que mais vale a pena saber quando um portao fecha.
    def detalhe
      i = (pbMapInterpreter rescue nil)
      d = []
      d << "cena=#{$scene.class}"
      d << "mapa=#{($game_map.map_id rescue '?')}"
      d << "texto_activo=#{sim_nao((Input.text_input rescue false))}"
      d << "arena=#{sim_nao((AnilArena.activa? rescue false))}"
      if i
        d << ("evento[idx=%s id=%s msg=%s rota=%s botao=%s espera=%s]" % [
          (i.instance_variable_get(:@index) rescue "?"),
          (i.instance_variable_get(:@event_id) rescue "?"),
          sim_nao((i.instance_variable_get(:@message_waiting) rescue false)),
          sim_nao((i.instance_variable_get(:@move_route_waiting) rescue false)),
          sim_nao((i.instance_variable_get(:@buttonInput) rescue false)),
          (i.instance_variable_get(:@wait_count) rescue "?")])
      end
      if defined?(AnilLanRework::ChatInputHUD)
        d << ("chat[activo=%s ate=%s frames=%s]" % [
          sim_nao((AnilLanRework::ChatInputHUD.active? rescue false)),
          (AnilLanRework::ChatInputHUD.instance_variable_get(:@input_block_until) rescue "?"),
          (Graphics.frame_count rescue "?")])
      end
      d.join("  ")
    rescue
      "(sem detalhe)"
    end

    def observar!
      return unless ACTIVO
      return unless $scene.is_a?(Scene_Map)
      return unless (Input.triggerex?(:C) rescue false)
      t = agora
      return if (t - @ultima) < ESPACO
      @ultima = t

      fechados = portoes.select { |(_n, v)| v }.map { |(n, _v)| n }
      if fechados.empty?
        # ⚠️ As primeiras confirmacoes tambem se escrevem.
        #
        # Sem elas, um ficheiro vazio tem duas leituras opostas — "nunca houve
        # problema" e "o diagnostico nunca correu" — e nao ha maneira de as
        # distinguir. Tres linhas resolvem isso e depois cala-se.
        return if @confirmadas >= 3
        @confirmadas += 1
        escrever("C aceite (nenhum portao fechado)  #{detalhe}")
        return
      end
      escrever("C RECUSADO por: #{fechados.join(', ')}  #{detalhe}")
    rescue
      nil
    end
  end
end

#-------------------------------------------------------------------------------
# ⚠️ Alias proprio, como todos os outros deste projecto: o `Scene_Map#update` ja
# leva o embrulho do 189 e o do 192, e dois com o mesmo nome fecham-se num
# circulo (ver a licao dos comandos de chat).
#-------------------------------------------------------------------------------
class Scene_Map
  unless method_defined?(:anil_diag_c_orig_update) ||
         private_method_defined?(:anil_diag_c_orig_update)
    alias_method :anil_diag_c_orig_update, :update
    def update
      anil_diag_c_orig_update
      (AnilDiagTeclaC.observar! rescue nil)
    end
  end
end
