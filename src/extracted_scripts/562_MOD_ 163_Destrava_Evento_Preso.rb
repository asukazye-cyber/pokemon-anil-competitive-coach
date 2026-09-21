# encoding: UTF-8
#===============================================================================
# MOD: 163_Destrava_Evento_Preso
#-------------------------------------------------------------------------------
# Um evento que ficou a meio deixa de travar o jogador — e, sobretudo, deixa de
# travar o SAVE.
#
# ⚠️ O ESTRAGO NAO E O EVENTO. E O SAVE PARAR DE SUBIR.
#
# O `running?` do interpretador e literalmente `!@list.nil?`. Fechar o jogo
# dentro de uma batalha comecada por evento deixa a lista de comandos gravada, e
# ao carregar ele volta "a correr" e nunca mais sai desse estado.
#
# A partir dai, o can_save_safely? (MOD 101) devolve false para sempre:
#
#     return false if pbMapInterpreterRunning?
#
# E isso nao atrasa o save — mata-o. O save_and_upload_save_file desiste, e os
# DOIS caminhos de recuperacao (flush_deferred_autosaves! e
# flush_autosave_atrasado!) testam a mesma condicao. O jogador passa a jogar sem
# copia na nuvem, e perde o progresso a cada reconexao.
#
# O sintoma visivel e outro, e foi por ele que se descobriu: TODA troca era
# cancelada. O servidor confere a posse contra o save em disco
# (player_owns_pokemon?), o save nunca mais chegou la, e a troca saia com
# "o Pokemon selecionado nao foi encontrado na sua partida salva" — para os dois
# lados. Destravar o save pelo painel resolvia; isto evita ter de o fazer.
#
# ⚠️ PORQUE E UM VIGIA E NAO UMA LIMPEZA NO ARRANQUE.
#
# Limpar o interpretador ao carregar seria simples e estaria ERRADO: existe o
# comando de evento 352 (Gravar Jogo), portanto um save legitimo PODE ter uma
# lista pendente, e apaga-la abortava a cutscene a meio.
#
# Um evento vivo anda. Este vigia olha de segundo a segundo e so age quando o
# interpretador esta parado no MESMO ponto ha muito tempo E nao ha nada que o
# possa fazer andar. Um evento a funcionar muda de assinatura e nunca chega a
# ser tocado — a seguranca vem da propria construcao, nao de uma lista de casos.
#===============================================================================

module AnilDestravaEvento
  ACTIVO    = true
  # Quanto tempo parado no mesmo ponto, sem nada por que esperar, para se
  # considerar morto. Generoso de proposito: o custo de esperar de mais e um
  # atraso; o de agir cedo de mais e cortar um evento bom.
  LIMITE    = 20.0
  INTERVALO = 1.0    # de quanto em quanto tempo se observa

  @ultimo  = nil     # [assinatura, momento em que apareceu]
  @proxima = 0.0
  @contadas = 0

  class << self
    attr_reader :contadas

    def log(t)
      AnilLanRework.log("[DESTRAVA] #{t}") rescue nil
    end

    def agora
      System.uptime
    rescue
      Time.now.to_f
    end

    def iv(obj, nome)
      obj.instance_variable_get(nome)
    rescue
      nil
    end

    # ⚠️ QUALQUER COISA QUE POSSA FAZER O EVENTO ANDAR TORNA-O LEGITIMO.
    #
    # Uma caixa de texto a espera de um toque fica parada horas se o jogador
    # for almocar — e continua a ser um evento bom. O mesmo para um percurso de
    # movimento, uma espera por botao ou um contador de espera a decorrer.
    def espera_legitima?(i)
      return true if iv(i, :@message_waiting)
      return true if iv(i, :@move_route_waiting)
      return true if iv(i, :@buttonInput)
      return true if iv(i, :@wait_count).to_i > 0
      return true if ($game_temp && $game_temp.message_window_showing rescue false)
      return true if ($game_temp && ($game_temp.in_battle ||
                                     $game_temp.transition_processing ||
                                     $game_temp.player_transferring) rescue false)
      return true unless ($scene.is_a?(Scene_Map) rescue false)
      f = iv(i, :@child_interpreter)
      return espera_legitima?(f) if f && (f.running? rescue false)
      false
    rescue
      true    # na duvida, nao se mexe
    end

    # Onde e que ele esta. Se isto mudar, o evento andou.
    def assinatura(i)
      f = iv(i, :@child_interpreter)
      [(iv(i, :@list).object_id rescue 0),
       iv(i, :@index),
       iv(i, :@event_id),
       (f ? (iv(f, :@index)) : nil)]
    rescue
      nil
    end

    def observar!
      return unless ACTIVO
      t = agora
      return if t < @proxima
      @proxima = t + INTERVALO

      i = (pbMapInterpreter rescue nil)
      unless i && (i.running? rescue false)
        @ultimo = nil
        return
      end
      if espera_legitima?(i)
        @ultimo = nil
        return
      end

      a = assinatura(i)
      if @ultimo.nil? || @ultimo[0] != a
        @ultimo = [a, t]
        return
      end
      return if (t - @ultimo[1]) < LIMITE

      destravar!(i)
      @ultimo = nil
    rescue
      nil
    end

    # Os mesmos campos que o painel de admin limpa no force_unstuck_save_data!,
    # para o resultado ser identico ao do botao.
    def destravar!(i)
      i.instance_variable_set(:@list, nil)
      i.instance_variable_set(:@index, 0)
      i.instance_variable_set(:@event_id, 0)
      i.instance_variable_set(:@message_waiting, false)
      i.instance_variable_set(:@move_route_waiting, false)
      i.instance_variable_set(:@buttonInput, false)
      i.instance_variable_set(:@wait_count, 0)
      i.instance_variable_set(:@child_interpreter, nil)

      # ⚠️ O JOGADOR PODE TER FICADO PRESO COM ELE.
      #
      # Um evento tranca o boneco enquanto corre. Limpar o interpretador sem
      # soltar o jogador deixava-o de pe sem andar — trocava um problema por
      # outro, e mais visivel.
      if defined?($game_player) && $game_player
        $game_player.instance_variable_set(:@locked, false) rescue nil
        $game_player.instance_variable_set(:@move_route_forcing, false) rescue nil
        $game_player.instance_variable_set(:@move_route, nil) rescue nil
      end
      if defined?($game_system) && $game_system
        $game_system.instance_variable_set(:@menu_disabled, false) rescue nil
        $game_system.instance_variable_set(:@save_disabled, false) rescue nil
      end

      @contadas += 1
      log("evento preso ha #{LIMITE.to_i}s sem nada por que esperar; limpo (#{@contadas} nesta sessao)")

      # ⚠️ E o mais importante: por o save a andar OUTRA VEZ.
      #
      # Enquanto esteve preso nao subiu nada. Assim que destranca, sobe — senao
      # o jogador continuava sem copia ate ao proximo motivo de autosave.
      (AnilLanRework.save_and_upload_save_file("destravado") rescue nil)
    rescue => e
      log("falha ao destravar: #{e.class}: #{e.message}")
    end

    # ⚠️ Entra depois dos plugins, como os outros: o Scene_Map#update e
    # reescrito por mais do que um deles.
    def instalar!
      return false unless ACTIVO
      return false unless defined?(Scene_Map)
      return false if Scene_Map.method_defined?(:anil_destrava_orig_update)
      Scene_Map.class_eval do
        alias_method :anil_destrava_orig_update, :update
        def update(*a)
          ret = anil_destrava_orig_update(*a)
          AnilDestravaEvento.observar!
          ret
        end
      end
      log("vigia instalado (limite #{LIMITE.to_i}s)")
      true
    rescue => e
      log("falha a instalar: #{e.class}: #{e.message}")
      false
    end
  end
end

module AnilLanRework
  class << self
    unless method_defined?(:anil_destrava_orig_apply_post_plugin_patches)
      alias_method :anil_destrava_orig_apply_post_plugin_patches, :apply_post_plugin_patches rescue nil
    end

    def apply_post_plugin_patches
      anil_destrava_orig_apply_post_plugin_patches rescue nil
      AnilDestravaEvento.instalar! rescue nil
    end
  end
end
