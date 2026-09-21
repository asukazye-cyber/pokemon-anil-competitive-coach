# encoding: UTF-8
#===============================================================================
# MOD: 187_Evento_Lendario
#-------------------------------------------------------------------------------
#   /evento zapdos shiny 100     solta um Zapdos shiny nivel 100 (admin)
#   /evento zapdos super 100     o mesmo, mas super shiny
#   /evento onde                 diz em que rota ele esta agora (admin)
#   /evento parar                termina o evento (admin)
#   /map zapdos                  atalho para o /evento onde
#
# ⚠️ ESTE MOD NAO DECIDE NADA. SO DESENHA.
#
# Quem sabe onde o lendario esta, quando ele muda de rota e quem o apanhou e o
# servidor. O cliente recebe "esta no mapa X com a semente Y", desenha, e no fim
# da batalha conta como correu. Foi de proposito: o roaming nativo do Essentials
# vive no save de cada jogador, e um evento unico do servidor inteiro nao pode
# depender de 30 copias independentes do mesmo estado.
#
# ⚠️ A SEMENTE E O QUE POE TODA A GENTE A VER O BICHO NA MESMA CASA.
#
# O servidor nao tem os mapas carregados e nao sabe que tiles sao pisaveis. Se
# mandasse so o mapa, cada cliente sorteava a casa por sua conta e dois
# jogadores lado a lado viam o Zapdos em pontos diferentes. Com a semente, todos
# correm o mesmo sorteio sobre a mesma lista de casas — o mapa e igual para
# todos — e chegam ao mesmo tile.
#===============================================================================

module AnilEventoLendario
  ACTIVO = true
  ID_EVENTO = 8000

  module_function

  def log(t)
    AnilLanRework.log("[EVENTO] #{t}") rescue nil
  end

  def avisar(t)
    if AnilLanRework.respond_to?(:add_popup)
      AnilLanRework.add_popup(t, 10.0) rescue nil
    else
      pbMessage(t) rescue nil
    end
  end

  def meu_id
    AnilLanRework.read_cfg("multiplayer_player.txt", "id", "").to_s.strip.downcase
  rescue
    ""
  end

  def admin?
    $anil_sou_admin == true
  end

  # O que o servidor nos disse da ultima vez.
  def dados;        @dados;        end
  def dados=(v);    @dados = v;    end
  def trancado?;    @trancado == true; end
  def trancado=(v); @trancado = (v == true); end

  #-----------------------------------------------------------------------------
  # A CASA ONDE ELE FICA
  #-----------------------------------------------------------------------------
  # Mesma varredura do MOD 048, mas o sorteio final e pela semente do servidor
  # em vez de `sample`. A lista de candidatos sai sempre pela mesma ordem (dois
  # ciclos encaixados sobre o mesmo mapa), portanto o mesmo indice da a mesma
  # casa em todos os clientes.
  def casa_no_mapa(map_id, semente)
    mapa = nil
    if $game_map && $game_map.map_id == map_id
      mapa = $game_map
    elsif $map_factory
      mapa = ($map_factory.getMap(map_id) rescue nil)
    end
    return [10, 10] unless mapa

    candidatos = []
    (0...mapa.width).each do |tx|
      (0...mapa.height).each do |ty|
        next unless mapa.valid?(tx, ty)
        terreno = (mapa.terrain_tag(tx, ty) rescue nil)
        next if terreno && (terreno.can_surf || terreno.ledge)
        next unless mapa.passable?(tx, ty, 0)
        # Grama primeiro: e onde um selvagem faz sentido estar.
        candidatos << [tx, ty] if terreno && terreno.land_wild_encounters
      end
    end

    if candidatos.empty?
      (0...mapa.width).each do |tx|
        (0...mapa.height).each do |ty|
          next unless mapa.valid?(tx, ty)
          terreno = (mapa.terrain_tag(tx, ty) rescue nil)
          next if terreno && (terreno.can_surf || terreno.ledge)
          candidatos << [tx, ty] if mapa.passable?(tx, ty, 0)
        end
      end
    end
    return [10, 10] if candidatos.empty?
    candidatos[semente.to_i.abs % candidatos.length]
  rescue
    [10, 10]
  end

  #-----------------------------------------------------------------------------
  # O BICHO
  #-----------------------------------------------------------------------------
  def construir_pokemon(d)
    especie = d["especie"].to_s.upcase.to_sym
    return nil unless (GameData::Species.exists?(especie) rescue false)
    pkmn = Pokemon.new(especie, [[d["nivel"].to_i, 1].max, 100].min)
    if d["super"] == true
      (pkmn.super_shiny = true) rescue nil
      (pkmn.shiny = true) rescue nil
    elsif d["shiny"] == true
      (pkmn.shiny = true) rescue nil
    end
    pkmn
  rescue => e
    log("falha ao construir o pokemon: #{e.class}: #{e.message}")
    nil
  end

  #-----------------------------------------------------------------------------
  # DESENHAR E APAGAR
  #-----------------------------------------------------------------------------
  def apagar!
    return unless $game_map
    ev = $game_map.events[ID_EVENTO]
    return unless ev
    begin
      dados_mapa = ($game_map.instance_variable_get(:@map) rescue nil)
      dados_mapa.events.delete(ID_EVENTO) if dados_mapa && dados_mapa.respond_to?(:events)
      if $game_map.respond_to?(:removeThisEventfromMap)
        $game_map.removeThisEventfromMap(ID_EVENTO)
      else
        $game_map.events.delete(ID_EVENTO)
      end
      if $scene.is_a?(Scene_Map)
        conj = ($scene.spriteset($game_map.map_id) rescue nil)
        conj ||= ($scene.spriteset rescue nil)
        if conj && conj.respond_to?(:character_sprites)
          i = conj.character_sprites.index { |sp| sp.character == ev }
          (conj.character_sprites.delete_at(i).dispose rescue nil) if i
        end
      end
    rescue => e
      log("falha ao apagar: #{e.class}: #{e.message}")
    end
  end

  # Desenha no mapa actual, se for o mapa certo. Chamado quando chega o pacote e
  # tambem sempre que se entra num mapa.
  def desenhar!
    return unless ACTIVO && $game_map
    d = dados
    apagar!
    return unless d
    # Um passo silencioso e um passo que nao se pode investigar: no primeiro
    # teste nao havia como saber se o pacote nao chegou ou se ele estava noutra
    # rota. Duas causas opostas, o mesmo ecra vazio.
    if d["map_id"].to_i != $game_map.map_id
      log("nao desenho: ele esta no mapa #{d['map_id']} e eu estou no #{$game_map.map_id}")
      return
    end

    pkmn = construir_pokemon(d)
    return unless pkmn
    x, y = casa_no_mapa($game_map.map_id, d["semente"])

    begin
      char = (AnilLanRework::ReleasedRoaming.resolve_pokemon_character_path(pkmn) rescue "ItemBall")

      rpg = RPG::Event.new(x, y)
      rpg.id = ID_EVENTO
      rpg.name = "EventoLendario"
      pag = rpg.pages[0]
      pag.graphic.character_name = char
      pag.graphic.character_hue  = (pkmn.super_shiny_hue.to_i rescue 0)
      pag.trigger    = 0     # botao de accao
      pag.step_anime = true
      pag.move_type  = 1     # anda a esmo, para nao parecer uma estatua
      pag.move_speed = 3
      pag.through    = false
      pag.list = [
        RPG::EventCommand.new(355, 0, ["AnilEventoLendario.interagir!"]),
        RPG::EventCommand.new(0, 0, [])
      ]

      game_ev = Game_Event.new($game_map.map_id, rpg, $game_map)
      $game_map.events[ID_EVENTO] = game_ev
      dados_mapa = ($game_map.instance_variable_get(:@map) rescue nil)
      dados_mapa.events[ID_EVENTO] = rpg if dados_mapa && dados_mapa.respond_to?(:events)
      game_ev.refresh
      (AnilLanRework::ReleasedRoaming.sync_sprite(game_ev) rescue nil) if $scene.is_a?(Scene_Map)
      log("desenhado #{d['especie']} em #{$game_map.map_id} (#{x},#{y})")
    rescue => e
      log("falha ao desenhar: #{e.class}: #{e.message}")
    end
  end

  #-----------------------------------------------------------------------------
  # A BATALHA
  #-----------------------------------------------------------------------------
  def interagir!
    d = dados
    return unless d
    if trancado?
      pbMessage(_INTL("Outro treinador já está enfrentando esse Pokémon!")) rescue nil
      return
    end
    pkmn = construir_pokemon(d)
    return unless pkmn

    (pkmn.play_cry rescue nil)
    return unless pbConfirmMessage(_INTL("Um {1} selvagem apareceu! Enfrentar?", pkmn.speciesName))

    # ⚠️ PEDE-SE A TRANCA AO SERVIDOR E ESPERA-SE PELA RESPOSTA.
    #
    # Dois jogadores no mesmo mapa carregam em C ao mesmo tempo. Se cada um
    # entrasse em batalha por sua conta, os dois podiam captura-lo — nasciam dois
    # de um evento que era unico. Quem chega em segundo recebe "nao" e fica-se
    # por aqui.
    @lock = nil
    unless (AnilLanRework.connected? rescue false)
      pbMessage(_INTL("Você precisa estar conectado.")) rescue nil
      return
    end
    AnilLanRework.connection.send_packet("evento_lock", "event_id" => ID_EVENTO) rescue nil

    fim = Time.now.to_f + 5.0
    while @lock.nil? && Time.now.to_f < fim
      Graphics.update rescue nil
      Input.update rescue nil
      # O `pump_network` vive no BattleSync e traz coisas de batalha atras.
      # Aqui basta a drenagem crua: ler o socket e encaminhar o que vier.
      begin
        AnilLanRework.connection.tick
        AnilLanRework.connection.drain { |p| AnilLanRework::Router.route_packet(p) }
      rescue
      end
    end

    if @lock != true
      pbMessage(_INTL("Outro treinador chegou primeiro!")) rescue nil
      return
    end

    ev = $game_map.events[ID_EVENTO]
    (ev.turn_toward_player rescue nil) if ev

    resultado = (WildBattle.start_core(pkmn) rescue 0)
    palavra = case resultado
              when 4 then "capturado"
              when 1 then "derrotado"
              when 2 then "perdeu"
              when 3 then "fugiu"
              else        "desistiu"
              end

    # ⚠️ GRAVA ANTES DE CONTAR AO SERVIDOR.
    #
    # Assim que o servidor souber que foi capturado, ele termina o evento para
    # toda a gente — isso nao volta atras. Fechar o jogo nesse instante, sem
    # gravar, tirava o lendario do mundo sem o por na box de ninguem.
    if palavra == "capturado"
      (AnilLanRework.gravar_ja!("evento_lendario") rescue nil)
    end

    AnilLanRework.connection.send_packet("evento_resultado",
      "event_id" => ID_EVENTO, "resultado" => palavra) rescue nil
    log("resultado enviado: #{palavra}")
  rescue => e
    log("falha na interaccao: #{e.class}: #{e.message}")
  end

  def lock_resposta!(ok)
    @lock = (ok == true)
  end

  #-----------------------------------------------------------------------------
  # OS COMANDOS
  #-----------------------------------------------------------------------------
  def pedir_estado!
    return unless (AnilLanRework.connected? rescue false)
    AnilLanRework.connection.send_packet("evento_pedir") rescue nil
  end

  def tratar(texto)
    return false unless ACTIVO
    t = texto.to_s.strip
    return false unless t.start_with?("/")
    m = t.match(%r{\A/(evento|map)\s*(.*)\z}i)
    return false unless m
    # Para quem nao e admin isto nao e um comando: o texto segue o caminho
    # normal do chat, tal como se este MOD nao existisse.
    return false unless admin?

    partes = m[2].to_s.strip.split(/\s+/)
    if m[1].downcase == "map" || partes[0].to_s.downcase == "onde"
      AnilLanRework.connection.send_packet("evento_onde", "de" => meu_id) rescue nil
      # ⚠️ E TAMBEM O QUE ESTE CLIENTE SABE.
      #
      # A resposta do servidor diz onde o bicho esta. Nao diz se ESTE cliente
      # chegou a receber o pacote de spawn — e essa e a diferenca entre "esta
      # noutra rota" e "o pacote nao chega ca". Sem as duas linhas lado a lado,
      # nao ha como distinguir sem ler o log da VPS.
      d = dados
      local = if d.nil?
        _INTL("Aqui: nao recebi nenhum spawn.")
      else
        _INTL("Aqui: {1} no mapa {2}, e eu estou no {3}.",
              d["especie"].to_s, d["map_id"].to_i, ($game_map ? $game_map.map_id : 0))
      end
      avisar(local)
      return true
    end
    if partes[0].to_s.downcase == "parar"
      AnilLanRework.connection.send_packet("evento_parar", "de" => meu_id) rescue nil
      return true
    end
    if partes.empty?
      avisar(_INTL("Use /evento <espécie> [shiny|super] [nível], /evento onde ou /evento parar."))
      return true
    end

    especie = partes[0].to_s.upcase
    shiny   = partes.any? { |p| p.downcase == "shiny" }
    super_s = partes.any? { |p| p.downcase == "super" }
    nivel   = (partes.find { |p| p =~ /\A\d+\z/ } || "50").to_i

    unless (GameData::Species.exists?(especie.to_sym) rescue false)
      avisar(_INTL("Espécie desconhecida: {1}", especie))
      return true
    end

    AnilLanRework.connection.send_packet("evento_iniciar",
      "de"      => meu_id,
      "especie" => especie,
      "shiny"   => (shiny || super_s),
      "super"   => super_s,
      "nivel"   => nivel) rescue nil
    true
  rescue => e
    avisar(_INTL("Erro no comando: {1}", e.message))
    true
  end
end

#-------------------------------------------------------------------------------
# Perguntar ao servidor sempre que se entra num mapa.
#
# ⚠️ ISTO TEM DE SER INSTALADO DEPOIS DOS PLUGINS, E NAO AQUI EM CIMA.
#
# Os plugins correm no `PluginManager.runPlugins`, chamado dentro do `Main` — ou
# seja, DEPOIS de todos os MODs. E o proprio MOD 040 volta a redefinir o
# `Game_Map#setup` dentro do `apply_post_plugin_patches`. Um patch a esta classe
# feito no corpo do MOD e simplesmente apagado, sem erro nenhum.
#
# Foi exactamente o que aconteceu no primeiro teste: o servidor criou o Zapdos,
# moveu-o de dois em dois minutos e registou tudo no log, e o jogador percorreu
# as rotas sem nunca o ver. O pacote de spawn ate chegava ao cliente — mas so no
# instante em que ele mudava de rota. Quem entrasse no mapa depois disso nunca
# pedia nada, e portanto nunca desenhava.
#
# O `apply_post_plugin_patches` e o unico sitio que corre depois de toda a gente.
#-------------------------------------------------------------------------------
module AnilLanRework
  class << self
    unless method_defined?(:anil_evtlend_orig_apply_post_plugin_patches)
      alias_method :anil_evtlend_orig_apply_post_plugin_patches, :apply_post_plugin_patches rescue nil
    end

    def apply_post_plugin_patches
      anil_evtlend_orig_apply_post_plugin_patches rescue nil
      begin
        Game_Map.class_eval do
          unless method_defined?(:anil_evtlend_orig_setup) || private_method_defined?(:anil_evtlend_orig_setup)
            alias_method :anil_evtlend_orig_setup, :setup
          end
          def setup(map_id)
            anil_evtlend_orig_setup(map_id)
            # Marca-se e trata-se no update: durante o setup o mapa ainda esta a
            # ser montado, e desenhar um evento por cima disso e pedir sarilhos.
            @anil_evento_pendente = true
          end

          unless method_defined?(:anil_evtlend_orig_update) || private_method_defined?(:anil_evtlend_orig_update)
            alias_method :anil_evtlend_orig_update, :update
          end
          def update
            anil_evtlend_orig_update
            if @anil_evento_pendente
              @anil_evento_pendente = false
              # Pede ao servidor o estado actual, E desenha ja com o que se sabe:
              # o pacote pode ter chegado enquanto se estava noutro mapa.
              (AnilEventoLendario.pedir_estado! rescue nil)
              (AnilEventoLendario.desenhar! rescue nil)
            end
          end
        end
        AnilLanRework.log("[EVENTO] gancho do Game_Map instalado depois dos plugins") rescue nil
      rescue => e
        AnilLanRework.log("[EVENTO] falha ao instalar o gancho do Game_Map: #{e.class}: #{e.message}") rescue nil
      end
    end
  end
end

module AnilLanRework
  module Router
    class << self
      alias_method :anil_evtlend_orig_route_packet, :route_packet unless method_defined?(:anil_evtlend_orig_route_packet)

      def route_packet(packet)
        if packet.is_a?(Hash)
          case packet["type"].to_s
          when "evento_spawn"
            AnilEventoLendario.dados = packet
            AnilEventoLendario.trancado = (packet["trancado"] == true)
            (AnilEventoLendario.desenhar! rescue nil)
            return
          when "evento_remove"
            AnilEventoLendario.dados = nil
            (AnilEventoLendario.apagar! rescue nil)
            return
          when "evento_trancado"
            AnilEventoLendario.trancado = (packet["trancado"] == true)
            return
          when "evento_lock_resposta"
            (AnilEventoLendario.lock_resposta!(packet["ok"]) rescue nil)
            return
          when "evento_aviso"
            (AnilEventoLendario.avisar(packet["texto"].to_s) rescue nil)
            return
          end
        end
        anil_evtlend_orig_route_packet(packet)
      end
    end
  end
end

module AnilLanRework
  module Chat
    class << self
      if !method_defined?(:anil_evtlend_orig_send_message)
        alias_method :anil_evtlend_orig_send_message, :send_message rescue nil
      end

      def send_message(text)
        return if AnilEventoLendario.tratar(text)
        anil_evtlend_orig_send_message(text)
      end
    end
  end
end
