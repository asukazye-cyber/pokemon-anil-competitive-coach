# encoding: UTF-8
#===============================================================================
# MOD: 152_Fix_Evento_Sem_Coordenada
#-------------------------------------------------------------------------------
# Um evento em $game_map.events com @x ou @y a nil derruba o jogo ao entrar num
# mapa ESCURO:
#
#   Excepcion: NoMethodError  undefined method `-' for nil:NilClass
#   [Caruban's Dynamic Darkness] Dynamic Darkness.rb:803 in `get_nearby_events'
#
# A linha 803 do plugin e `dx = event.x - $game_player.x`. Ele percorre
# $game_map.events.each_value e assume que todo o evento tem coordenada — o que
# e verdade para os eventos do mapa em disco, mas nao para os que nos injectamos
# em tempo de execucao. So rebenta em cavernas porque o DarknessSprite so nasce
# quando o mapa tem dark_map.
#
# ⚠️ MESMA FAMILIA DO tile_id NULO.
#
# Ja aconteceu com o "Advanced Items - Field Moves" a rebentar no
# Game_Map#passable?. O padrao repete-se: plugin de terceiros percorre os
# eventos, assume um campo, e o nosso evento nao o tem.
#
# ⚠️ DUAS TENTATIVAS, E PORQUE A PRIMEIRA NAO CHEGOU.
#
# A primeira versao so registava um handler de :on_map_or_spriteset_change,
# contando com a ordem de insercao (scripts modulares carregam antes dos
# plugins, logo o nosso handler corre primeiro). O jogo continuou a rebentar com
# essa versao instalada e confirmada por md5 — portanto a premissa estava
# errada nalgum ponto que nao consegui isolar sem dados.
#
# Agora o saneamento corre TAMBEM imediatamente antes da iteracao do plugin,
# encaixado no proprio get_nearby_events pelo apply_post_plugin_patches (que
# corre depois de os plugins carregarem, quando a classe ja existe). Assim
# deixa de depender de ordem nenhuma: e literalmente a instrucao anterior.
#
# ⚠️ O LOG VAI PARA FICHEIRO PROPRIO, NAO PELO AnilLanRework.log.
#
# Esse sai logo se $anil_debug_log_enabled estiver desligado — e ligar a flag
# global e o que trava o "recuperar partida". Era por isso que a primeira versao
# nao deixou rasto nenhum para diagnosticar.
#===============================================================================

module AnilEventoSemCoordenada
  FICHEIRO = "evento_sem_coordenada.txt"

  module_function

  def registar(texto)
    return unless (anil_diagnostico_ligado? rescue false)
    File.open(FICHEIRO, "a") do |f|
      f.puts("[#{Time.now.strftime("%d/%m %H:%M:%S")}] #{texto}")
    end
  rescue
    nil
  end

  # Repara em vez de apagar: ha codigo que guarda o id do evento e faria
  # $game_map.events[id].alguma_coisa depois. Um evento em 0,0 atravessavel e
  # invisivel e inerte; um nil rebentava noutro sitio qualquer.
  # ⚠️ NAO E SO A COORDENADA: OS CONTADORES TAMBEM VEM PODRES.
  #
  #   Excepcion: TypeError  "coerce must return [x, y]"
  #   0050_Game_Character:1007 in `>=`   ->  `if @stop_count >= @command_delay`
  #
  # O @command_delay so e calculado dentro de move_frequency=; um evento que
  # nunca passe por la fica com ele por definir. E o erro "coerce must return
  # [x, y]" (em vez de um simples nil) diz que la esta um OBJECTO que responde a
  # coerce e devolve lixo — por isso registamos a CLASSE, que e o que falta
  # saber para corrigir a origem.
  #
  # Reparar e barato: pôr o move_frequency outra vez faz o proprio jogo
  # recalcular o command_delay pela formula certa.
  # ⚠️ ESTES EVENTOS VOLTAM DO SAVE COMPLETAMENTE VAZIOS.
  #
  # O log de 24/08 16:39 nao deixa duvidas — ids 72/73/74 do mapa 4, todos
  # Game_PokeEvent (os Pokemon visiveis do VOE):
  #
  #   @stop_count nil, @anime_count nil, @wait_count nil, @delta_t nil,
  #   @move_speed nil, @move_frequency nil, @command_delay nil, x nil, y nil
  #
  # Nao e um campo estragado: e um objecto sem variavel nenhuma, montado pelo
  # Marshal com `allocate` e nunca preenchido. E fica assim para sempre porque o
  # `Game_Map#marshal_load` so chama `refresh` nos eventos que existem no mapa
  # em disco; os Game_PokeEvent tem id dinamico (`@events.keys.max + 1`), ficam
  # de fora, e por isso nunca passam pelos setters que calculam os derivados.
  #
  # ⚠️ HA CAMPOS QUE NAO SE PODEM REPOR A MAO — SO PELO SETTER.
  #
  # Foi o erro da versao anterior deste ficheiro, e custou um crash novo:
  # repunha-se `@move_speed = 3` com instance_variable_set, o que deixa o
  # `@move_time` na mesma a nil, porque quem o calcula e o `move_speed=`. O
  # resultado foi trocar um crash por outro, tres linhas mais acima:
  #
  #   NoMethodError  undefined method `*` for nil:NilClass
  #   0049_Game_Character:140 in `pattern_update_speed`  ->  `@move_time * 2`
  #
  # Sao tres pares campo/derivado, e o do meio tem ainda um curto-circuito:
  #
  #   move_speed=      -> @move_time     (recalcula sempre)
  #   jump_speed=      -> @jump_time     (recalcula sempre)
  #   move_frequency=  -> @command_delay (`return if val == @move_frequency`)
  #
  # Por causa desse guard, reparar com `ev.move_frequency = ev.move_frequency`
  # nao faz absolutamente nada — era o defeito das duas primeiras tentativas.
  # Zera-se o campo antes, para o setter nao sair pela porta do lado.
  DERIVADOS = [
    [:@move_speed,     :move_speed=,     :@move_time,      4, false],
    [:@jump_speed,     :jump_speed=,     :@jump_time,      4, false],
    [:@move_frequency, :move_frequency=, :@command_delay,  6, true]
  ].freeze

  # Valores do Game_Character#initialize. So se escreve onde estiver nil, para
  # nao pisar um false legitimo (@through, @walk_anime e companhia).
  PADROES = {
    :@id => 0, :@original_x => 0, :@original_y => 0,
    :@x_offset => 0, :@y_offset => 0, :@width => 1, :@height => 1,
    :@tile_id => 0, :@character_name => "", :@character_hue => 0,
    :@opacity => 255, :@blend_type => 0, :@direction => 2,
    :@pattern => 0, :@pattern_surf => 0, :@lock_pattern => false,
    :@move_route_forcing => false, :@through => false,
    :@animation_id => 0, :@transparent => false,
    :@original_direction => 2, :@original_pattern => 0, :@move_type => 0,
    :@move_route_index => 0, :@original_move_route_index => 0,
    :@walk_anime => true, :@step_anime => false, :@direction_fix => false,
    :@always_on_top => false, :@anime_count => 0, :@stop_count => 0,
    :@bumping => false, :@jump_peak => 0, :@jump_distance => 0,
    :@jump_fraction => 0, :@jumping_on_spot => false, :@bob_height => 0,
    :@wait_count => 0, :@moved_this_frame => false,
    :@moveto_happened => false, :@locked => false, :@prelock_direction => 0,
    :@delta_t => 0
  }.freeze

  # Devolve a lista do que reparou, para o log. Vazia = estava bom.
  def normalizar!(ev)
    reparados = []

    PADROES.each do |var, padrao|
      next unless (ev.instance_variable_get(var).nil? rescue false)
      ev.instance_variable_set(var, padrao.dup) rescue ev.instance_variable_set(var, padrao)
      reparados << var
    end

    DERIVADOS.each do |var, setter, derivado, padrao, tem_guard|
      val = (ev.instance_variable_get(var) rescue nil)
      ok  = (ev.instance_variable_get(derivado).is_a?(Numeric) rescue false)
      next if val.is_a?(Numeric) && val > 0 && ok
      val = padrao unless val.is_a?(Numeric) && val > 0
      begin
        ev.instance_variable_set(var, nil) if tem_guard
        ev.send(setter, val)
        reparados << derivado
      rescue
        ev.instance_variable_set(var, val)
        ev.instance_variable_set(derivado, 0)
        reparados << derivado
      end
    end

    reparados
  rescue => e
    registar("falha ao normalizar: #{e.class}: #{e.message}")
    []
  end

  def sanear_contadores!(mapa)
    n = 0
    mapa.events.each do |id, ev|
      next unless ev
      reparados = normalizar!(ev)
      next if reparados.empty?
      registar("mapa #{(mapa.map_id rescue "?")}: id=#{id.inspect} "                "#{ev.class} reparado: #{reparados.join(", ")}")
      n += 1
    end
    n
  rescue => e
    registar("falha ao sanear contadores: #{e.class}: #{e.message}")
    0
  end

  def sanear!(mapa = nil)
    mapa ||= $game_map
    return 0 unless mapa && mapa.respond_to?(:events) && mapa.events.is_a?(Hash)

    reparados = 0
    mapa.events.each do |id, ev|
      next unless ev
      sem_x = (ev.x.nil? rescue true)
      sem_y = (ev.y.nil? rescue true)
      next unless sem_x || sem_y

      nome = (ev.name.to_s rescue "?")
      classe = (ev.class.name rescue "?")
      registar("mapa #{(mapa.map_id rescue "?")}: id=#{id.inspect} nome=#{nome.inspect} " \
               "classe=#{classe} x=#{(ev.x rescue "erro").inspect} y=#{(ev.y rescue "erro").inspect}")

      begin
        ev.moveto(0, 0)
      rescue
        ev.instance_variable_set(:@x, 0)
        ev.instance_variable_set(:@y, 0)
      end
      # ⚠️ O real_x/real_y tambem: o moveto define-os, mas se ele proprio falhou
      # ficariam nil e o Sprite_Character rebentava a seguir, com outra mensagem.
      ev.instance_variable_set(:@real_x, 0) if (ev.instance_variable_get(:@real_x).nil? rescue false)
      ev.instance_variable_set(:@real_y, 0) if (ev.instance_variable_get(:@real_y).nil? rescue false)
      ev.instance_variable_set(:@through, true)     rescue nil
      ev.instance_variable_set(:@transparent, true) rescue nil
      reparados += 1
    end

    reparados += sanear_contadores!(mapa)
    reparados
  rescue => e
    registar("falha ao sanear: #{e.class}: #{e.message}")
    0
  end
end

# ⚠️ REDE 0: EM RUNTIME, PORQUE O EVENTO NAO SE ESTRAGA NUM MOMENTO.
#
# As duas redes abaixo (handler de mudanca de mapa e gancho no DarknessSprite)
# so correm em MOMENTOS. Mas o crash apanha o jogador PARADO, e ate com o jogo
# em segundo plano — o evento ja vem estragado do save e basta o loop chegar-lhe.
#
# Sao duas casas, nao uma, porque os campos derivados sao lidos em sitios
# diferentes e nem todos passam pelo mesmo caminho:
#
#   @command_delay  ->  update_command_new    `@stop_count >= @command_delay`
#   @move_time      ->  pattern_update_speed  `@move_time * 2`
#
# O `update` cobre o caso geral; o `pattern_update_speed` fica guardado a parte
# porque ha plugins ([Marin Side Stairs]) que chamam o `update_pattern` de
# dentro do proprio update, e nao ha garantia de que o nosso `update` ja tenha
# corrido nesse frame.
#
# O custo sao dois is_a?(Numeric) por personagem por frame, e ambos falham so
# uma vez por evento — a normalizacao repara tudo de uma assentada.
#
# Regista UMA vez por evento, senao um evento partido enchia o ficheiro.
class Game_Character
  def anil_evt_verificar!
    return if @command_delay.is_a?(Numeric) && @move_time.is_a?(Numeric)
    reparados = (AnilEventoSemCoordenada.normalizar!(self) rescue [])
    unless @anil_evt_avisado
      @anil_evt_avisado = true
      AnilEventoSemCoordenada.registar(
        "runtime: #{self.class} id=#{(@id rescue "?")} mapa=#{(@map_id rescue "?")} "         "nome=#{(name rescue "?").inspect} reparado: #{reparados.join(", ")}") rescue nil
    end
  rescue
    @command_delay = 0 unless @command_delay.is_a?(Numeric)
    @move_time     = 0.25 unless @move_time.is_a?(Numeric)
  end

  unless method_defined?(:anil_evt_orig_update)
    alias_method :anil_evt_orig_update, :update
    def update
      anil_evt_verificar!
      anil_evt_orig_update
    end
  end

  unless method_defined?(:anil_evt_orig_pattern_update_speed)
    alias_method :anil_evt_orig_pattern_update_speed, :pattern_update_speed
    def pattern_update_speed
      anil_evt_verificar!
      anil_evt_orig_pattern_update_speed
    end
  end
end

# Rede 1: no handler, como antes. Barato e apanha o caso comum.
EventHandlers.add(:on_map_or_spriteset_change, :anil_sanear_eventos_sem_coordenada,
  proc { |_scene, _map_changed|
    AnilEventoSemCoordenada.sanear!
  }
)

# Rede 2: colado ao proprio plugin, para nao depender de ordem de handlers.
module AnilLanRework
  class << self
    unless method_defined?(:anil_evtcoord_orig_apply_post_plugin_patches)
      alias_method :anil_evtcoord_orig_apply_post_plugin_patches, :apply_post_plugin_patches rescue nil
    end

    def apply_post_plugin_patches
      anil_evtcoord_orig_apply_post_plugin_patches rescue nil
      begin
        if defined?(DarknessSprite) && DarknessSprite.method_defined?(:get_nearby_events) &&
           !DarknessSprite.method_defined?(:anil_evtcoord_orig_get_nearby_events)
          DarknessSprite.class_eval do
            alias_method :anil_evtcoord_orig_get_nearby_events, :get_nearby_events
            def get_nearby_events
              AnilEventoSemCoordenada.sanear! rescue nil
              anil_evtcoord_orig_get_nearby_events
            end
          end
          AnilEventoSemCoordenada.registar("gancho instalado no DarknessSprite#get_nearby_events")
        else
          AnilEventoSemCoordenada.registar(
            "DarknessSprite NAO encontrado no apply_post_plugin_patches " \
            "(defined=#{defined?(DarknessSprite) ? "sim" : "nao"})")
        end
      rescue => e
        AnilEventoSemCoordenada.registar("falha ao instalar o gancho: #{e.class}: #{e.message}")
      end
    end
  end
end

AnilEventoSemCoordenada.registar("152 carregado")
