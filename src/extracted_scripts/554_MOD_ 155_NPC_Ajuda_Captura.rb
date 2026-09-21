# encoding: UTF-8
#===============================================================================
# MOD: 155_NPC_Ajuda_Captura
#-------------------------------------------------------------------------------
# Reconstrucao do NPC de ajuda: aparece nas rotas, fica a passear, aborda o
# jogador quando ele chega perto, pede um Pokemon da propria rota, passa a
# segui-lo, e vai-se embora contente quando o recebe.
#
# ⚠️ METADE DISTO JA EXISTIA — E ESTAVA DESLIGADA A MAO.
#
# O `0231_Battle_CatchAndStoreMixin.rb` ja trazia o lado do consumidor: ao
# capturar, o menu ganha "Dar para {nome}", entrega o Pokemon, marca o estado e
# chama pbDeregisterPartner. Mas a condicao estava escrita
#
#     if false && defined?(GlobalNPC_Manager)
#
# e o `GlobalNPC_Manager` nao existia em lado nenhum: nem nos modulares, nem nos
# plugins, nem em 819 Scripts.rxdata compilados (aparece em 811, sempre e so
# como este uso), nem nos eventos dos mapas. Sobrou o gancho, faltava o sistema.
#
# Por isso este ficheiro implementa EXACTAMENTE o contrato que aquele codigo ja
# esperava, em vez de inventar outro:
#
#     GlobalNPC_Manager::NPC_CONFIG[idx][:trainer_name]
#     GlobalNPC_Manager.pbGetNPCLifeSystemData[idx][:capture_quest_state]
#     GlobalNPC_Manager.pbGetNPCLifeSystemData[idx][:quest_captured_species]
#
# ⚠️ O pbGetNPCLifeSystemData TEM de devolver o hash VIVO.
#
# O gancho ESCREVE nele (`npc_state[:capture_quest_state] = :success_pending`).
# Devolver uma copia fazia a entrega parecer funcionar e nao mudar nada.
#
# ⚠️ O EVENTO E EFEMERO; QUEM PERSISTE E O SEGUIDOR.
#
# O boneco no mapa e um evento injectado em $game_map.events, e o $game_map vai
# no save — e eventos injectados no save sao exactamente a familia de bugs do
# [[evento-command-delay-nil]]. Entao o evento e apagado na mudanca de mapa, e
# quem viaja e o SEGUIDOR ($PokemonGlobal.followers), que e o mecanismo proprio
# do jogo para isso. Ha tambem uma limpeza de restos ao entrar em cada mapa.
#===============================================================================

class PokemonGlobalMetadata
  # Estado da quest. Vai no save por Marshal, como tudo o resto aqui.
  attr_accessor :anil_npc_quest
end

module AnilNPCAjuda
  NOME_EVENTO   = "AnilNPCAjuda"
  NOME_SEGUIDOR = "anil_npc_ajuda"
  IDX           = 1

  # A que distancia (em tiles) o NPC repara no jogador e vai ter com ele.
  DISTANCIA_ABORDAGEM = 5
  # E a que distancia desiste de tentar chegar, para nao ficar preso num muro.
  PASSOS_MAX_ABORDAGEM = 40
  # Chance de aparecer um NPC ao entrar numa rota elegivel, em 100.
  #
  # ⚠️ Esteve em 12 e era de mais: com um teste por cada entrada em rota, o NPC
  # aparecia quase de mapa a mapa e a quest deixava de ser um acontecimento.
  # A 3 aparece uma vez em cada ~33 rotas, e continua a haver o descanso de
  # ESPERA_ENTRE_QUESTS por cima.
  CHANCE_SPAWN = 3
  # Segundos de descanso depois de uma quest terminada, para nao encher o jogo.
  ESPERA_ENTRE_QUESTS = 900
  # A verificacao de proximidade nao precisa de correr a 60 fps.
  FRAMES_ENTRE_VERIFICACOES = 8

  # ⚠️ A SKIN VEM DO MAPA, PELO NOME DELE.
  #
  # Os nomes dos mapas estao em espanhol ("Bosque Verde" e a Floresta de
  # Viridian, mapa 8). Casar pelo NOME e nao por uma lista de ids porque a lista
  # envelhece a cada mapa novo, e o nome ja diz o que o sitio e.
  #
  # Cada entrada e [ficheiro do charset, nome que o NPC usa]. Todos os ficheiros
  # foram confirmados em Graphics/Characters.
  ELENCO = [
    [/bosque|forest|selva/i, [
      ["cazabichos", "Caçador de Insetos"],
      ["cazabichas", "Caçadora de Insetos"]
    ]],
    [/monte|t[uú]nel|cueva|cave|roca|rock/i, [
      ["montanero", "Montanhista"]
    ]],
    [/mar\b|isla|playa|puerto|muelle|agua/i, [
      ["pescador",    "Pescador"],
      ["pescadoraow", "Pescadora"]
    ]]
  ].freeze

  ELENCO_PADRAO = [
    ["campista",  "Campista"],
    ["campistaa", "Campista"],
    ["nino",      "Garoto"],
    ["chica1",    "Garota"],
    ["chica2",    "Garota"],
    ["hombre1",   "Rapaz"],
    ["mujer1",    "Moça"],
    ["mujer2",    "Moça"]
  ].freeze

  class << self
    # ------------------------------------------------------------------ estado
    def estado
      return {} unless $PokemonGlobal
      $PokemonGlobal.anil_npc_quest ||= { :capture_quest_state => :not_started }
      $PokemonGlobal.anil_npc_quest
    end

    def fase
      estado[:capture_quest_state] || :not_started
    end

    def fase=(v)
      estado[:capture_quest_state] = v
    end

    def activa?
      [:aguardando, :success_pending, :despedida].include?(fase)
    end

    def log(txt)
      AnilLanRework.log("[NPCAJUDA] #{txt}") rescue nil
    end

    # ------------------------------------------------------------------- skins
    def elenco_do_mapa(nome_mapa)
      ELENCO.each { |regra, lista| return lista if nome_mapa.to_s =~ regra }
      ELENCO_PADRAO
    end

    def nome_do_mapa(mapa = nil)
      mapa ||= $game_map
      return "" unless mapa
      (mapa.name.to_s rescue "")
    rescue
      ""
    end

    # --------------------------------------------------------------- especies
    # Pede um Pokemon que REALMENTE aparece ali. Sem isso a quest era impossivel
    # de cumprir sem sair da rota, que e o contrario do que se quer.
    def especie_pedida(map_id)
      [:Land, :LandDay, :LandNight, :Cave, :Water].each do |tipo|
        par = ($PokemonEncounters.choose_wild_pokemon_for_map(map_id, tipo) rescue nil)
        next unless par && par[0]
        return par[0]
      end
      dados = (GameData::Encounter.get(map_id, ($PokemonGlobal.encounter_version rescue 0)) rescue nil)
      return nil unless dados && dados.types
      dados.types.each_value do |lista|
        next unless lista.is_a?(Array) && !lista.empty?
        entrada = lista.sample
        return entrada[1] if entrada
      end
      nil
    rescue
      nil
    end

    def nome_especie(sym)
      GameData::Species.get(sym).name.to_s
    rescue
      sym.to_s
    end

    # O mapa serve para uma quest se tiver encontros — sem isso nao ha o que
    # pedir. E fica de fora tudo o que for interior (o metadata diz).
    def mapa_elegivel?(mapa = nil)
      mapa ||= $game_map
      return false unless mapa
      # ⚠️ UMA MASMORRA NAO E UM SITIO ONDE SE PASSEIA.
      #
      # O criterio aqui era "tem tabela de encontros e nao e interior". As
      # masmorras passaram a ter tabela propria — foi preciso, para o servidor
      # saber que especies semear — e com isso passaram a parecer uma rota
      # qualquer a este sistema. O que se viu foi a NPC a pedir um Pokemon no
      # meio do safari abandonado, onde nao se captura nada e de onde so se sai
      # com uma corda.
      #
      # E o mesmo principio do `travar_mato_do_mundo!` do MOD 192: o que vem de
      # fora bloqueia-se a porta, e nao se anda a apanhar depois de entrado.
      return false if (defined?(AnilRaidCaverna) && AnilRaidCaverna.dentro? rescue false)
      md = (mapa.metadata rescue nil)
      return false if md && md.respond_to?(:outdoor_map) && md.outdoor_map == false
      !especie_pedida(mapa.map_id).nil?
    rescue
      false
    end

    # ---------------------------------------------------------------- terreno
    # Um tile onde o NPC possa mesmo ficar, longe do jogador para dar tempo de
    # o ver a passear antes de ser abordado.
    def tile_livre(mapa, longe_de_jogador = 6)
      px = ($game_player.x rescue 0)
      py = ($game_player.y rescue 0)
      candidatos = []
      largura = mapa.width
      altura  = mapa.height
      200.times do
        x = rand(largura)
        y = rand(altura)
        next unless mapa.valid?(x, y)
        next unless mapa.passable?(x, y, 0)
        t = (mapa.terrain_tag(x, y) rescue nil)
        next if t && (t.can_surf || t.ledge)
        next if ((x - px).abs + (y - py).abs) < longe_de_jogador
        next if mapa.events.each_value.any? { |e| e && e.x == x && e.y == y }
        candidatos << [x, y]
        break if candidatos.length >= 8
      end
      candidatos.sample
    rescue
      nil
    end

    # ---------------------------------------------------------------- o evento
    def evento_actual
      id = estado[:evento_id]
      return nil unless id && $game_map
      ev = $game_map.events[id]
      return nil unless ev
      return nil unless (ev.name.to_s == NOME_EVENTO rescue false)
      ev
    rescue
      nil
    end

    # `saida = true` faz um boneco mudo e quieto, so para a despedida: sem
    # trigger de conversa e sem passeio ao calhas a lutar com a rota forcada.
    def criar_evento!(mapa, x, y, skin, saida = false)
      id = ((mapa.events.keys.max || 0) + 1)
      rpg = RPG::Event.new(x, y)
      rpg.id   = id
      rpg.name = NOME_EVENTO

      pg = rpg.pages[0]
      pg.graphic.character_name = skin
      pg.graphic.character_hue  = 0
      pg.trigger        = 0      # falar com C
      pg.walk_anime     = true
      pg.step_anime     = false
      pg.move_type      = saida ? 0 : 1      # 1 = passear ao calhas
      pg.move_speed     = 3
      pg.move_frequency = 3
      # ⚠️ Sem THROUGH, tambem na saida. Ela atravessava sebes e cercas a ir
      # embora, e lia-se como um erro de colisao — que e o que era.
      pg.through        = false
      pg.list = if saida
                  [RPG::EventCommand.new(0, 0, [])]
                else
                  [RPG::EventCommand.new(355, 0, ["AnilNPCAjuda.falar"]),
                   RPG::EventCommand.new(0, 0, [])]
                end

      ev = Game_Event.new(mapa.map_id, rpg, mapa)
      mapa.events[id] = ev

      # ⚠️ Tambem no mapa CRU, senao o Game_Event#event devolve nil e meio jogo
      # rebenta a seguir — foi assim que o 048 o fez e e por isso que funciona.
      bruto = (mapa.instance_variable_get(:@map) rescue nil)
      bruto.events[id] = rpg if bruto && bruto.respond_to?(:events)

      ev.refresh rescue nil
      sincronizar_sprite(ev)
      id
    rescue => e
      log("falha ao criar o evento: #{e.class}: #{e.message}")
      nil
    end

    def sincronizar_sprite(evento)
      return unless evento && $scene.is_a?(Scene_Map) && $scene.respond_to?(:spritesets)
      conjuntos = $scene.spritesets
      return unless conjuntos
      conjunto = (conjuntos[$game_map.map_id] rescue nil)
      conjunto ||= (conjuntos.values.first rescue nil)
      return unless conjunto && conjunto.respond_to?(:character_sprites)
      return if conjunto.character_sprites.any? { |s| s.character == evento }
      vp = nil
      conjunto.instance_variables.each do |var|
        val = conjunto.instance_variable_get(var)
        if val.is_a?(Viewport)
          vp = val
          break
        end
      end
      vp ||= (Spriteset_Map.viewport rescue nil)
      return unless vp
      conjunto.character_sprites.push(Sprite_Character.new(vp, evento))
    rescue
      nil
    end

    def apagar_evento!(id = nil)
      id ||= estado[:evento_id]
      return unless id && $game_map
      ev = $game_map.events[id]
      if ev && $scene.is_a?(Scene_Map) && $scene.respond_to?(:spritesets)
        conjunto = ($scene.spritesets[$game_map.map_id] rescue nil)
        if conjunto && conjunto.respond_to?(:character_sprites)
          conjunto.character_sprites.each do |s|
            next unless s.character == ev
            conjunto.character_sprites.delete(s)
            s.dispose rescue nil
            break
          end
        end
      end
      $game_map.events.delete(id)
      bruto = ($game_map.instance_variable_get(:@map) rescue nil)
      bruto.events.delete(id) if bruto && bruto.respond_to?(:events)
      estado[:evento_id] = nil
    rescue
      nil
    end

    # Restos de sessoes anteriores: o evento e efemero, mas um autosave pode
    # apanha-lo vivo e ele volta com o mapa. Varre-se a entrada de cada mapa.
    def limpar_restos!(excepto = nil)
      return unless $game_map && $game_map.events.is_a?(Hash)
      $game_map.events.keys.each do |id|
        next if excepto && id == excepto
        ev = $game_map.events[id]
        next unless ev
        next unless (ev.name.to_s == NOME_EVENTO rescue false)
        apagar_evento!(id)
      end
    rescue
      nil
    end

    # ---------------------------------------------------------------- aparecer
    def pode_aparecer?
      return false unless $game_map && $PokemonGlobal
      return false if (defined?(AnilRaidCaverna) && AnilRaidCaverna.dentro? rescue false)
      return false if activa?
      return false if evento_actual
      ate = estado[:descanso_ate]
      return false if ate && Time.now.to_i < ate.to_i
      true
    rescue
      false
    end

    # forcado = veio do comando; ignora a sorte e o descanso.
    def tentar_aparecer!(forcado = false, especie_forcada = nil)
      return false unless $game_map
      limpar_restos!
      unless forcado
        return false unless pode_aparecer?
        return false unless mapa_elegivel?
        return false unless rand(100) < CHANCE_SPAWN
      end
      return false if activa? || evento_actual

      # ⚠️ A especie forcada nao passa pela tabela de encontros.
      #
      # E de proposito: o comando de admin serve para testar o que o jogo
      # normal nao da com facilidade — um bicho de outra rota para ver a fala do
      # "nao era bem isto", por exemplo.
      especie = especie_forcada || especie_pedida($game_map.map_id)
      unless especie
        log("mapa #{$game_map.map_id} sem tabela de encontros; nao da para pedir nada")
        return false
      end

      skin, nome = elenco_do_mapa(nome_do_mapa).sample
      pos = tile_livre($game_map, forcado ? 3 : 6)
      unless pos
        log("sem tile livre no mapa #{$game_map.map_id}")
        return false
      end

      id = criar_evento!($game_map, pos[0], pos[1], skin)
      return false unless id

      estado[:evento_id]   = id
      estado[:trainer_name] = nome
      estado[:skin]        = skin
      estado[:especie]     = especie
      estado[:mapa]        = $game_map.map_id
      estado[:passos]      = 0
      self.fase = :not_started
      estado[:quest_captured_species] = nil
      GlobalNPC_Manager.definir_nome(nome)
      log("apareceu #{nome} (#{skin}) no mapa #{$game_map.map_id} em #{pos.inspect}, quer #{especie}")
      true
    rescue => e
      log("falha ao aparecer: #{e.class}: #{e.message}")
      false
    end

    # Quantos frames seguidos de calma antes de o NPC puxar conversa depois da
    # entrega. ~0,75s a 60fps: o suficiente para o fade de regresso acabar.
    FRAMES_CALMA = 45

    # Nada disto pode estar a acontecer para se considerar o ecra assente.
    def calmo?
      return false unless $scene.is_a?(Scene_Map)
      return false unless $game_temp
      return false if ($game_temp.in_battle rescue false)
      return false if ($game_temp.transition_processing rescue false)
      return false if ($game_temp.player_transferring rescue false)
      return false if ($game_temp.message_window_showing rescue false)
      return false if (pbMapInterpreterRunning? rescue true)
      return false if $game_player && ($game_player.moving? rescue false)
      return false if $game_player && ($game_player.move_route_forcing rescue false)
      true
    rescue
      false
    end

    # ------------------------------------------------------------------- ciclo
    def tick
      return unless $game_map && $scene.is_a?(Scene_Map)
      return if $game_temp && ($game_temp.message_window_showing rescue false)
      return if $game_player && ($game_player.moving? rescue false) && fase == :success_pending

      # ⚠️ A DESPEDIDA CONTA-SE AQUI, E NAO DENTRO DELA.
      #
      # Enquanto eles andam, isto corre a cada frame como tudo o resto. Quando a
      # hora chega, apagam-se os dois. Sem esperas bloqueantes: ver a nota do
      # partida! sobre re-entrar no pbUpdateSceneMap.
      if fase == :despedida
        # ⚠️ Acaba quando a ROTA acaba, e o relogio e so o tecto.
        #
        # Um tempo fixo obrigava a adivinhar quantos segundos sao 20 passos, e
        # errava nos dois sentidos: apagava-os a meio do caminho num mapa
        # grande, ou deixava-os parados na beira num mapa pequeno.
        npc = (estado[:evento_id] ? $game_map.events[estado[:evento_id]] : nil)
        andando = npc && (npc.move_route_forcing rescue false)
        if !andando || estado[:saida_ate].nil? || Time.now.to_f >= estado[:saida_ate].to_f
          terminar_despedida!
        end
        return
      end

      # ⚠️ O AGRADECIMENTO ESPERA O ECRA ASSENTAR.
      #
      # A entrega acontece no ecra da captura, e a fase fica em success_pending
      # ainda dentro da batalha. Este handler corre por frame, portanto no
      # primeiro frame de mapa que apanhe — que e no meio do fade de regresso —
      # ele abria a caixa de mensagem por cima de um ecra meio escuro e o jogo
      # parecia travado. Exige-se um bocado de calma seguida antes de comecar.
      if fase == :success_pending
        if calmo?
          @calma = (@calma || 0) + 1
        else
          @calma = 0
        end
        return if (@calma || 0) < FRAMES_CALMA
        @calma = 0
        # Trava de re-entrada: o concluir! mostra mensagens, e mensagens fazem
        # correr frames, e frames voltam aqui.
        return if @a_concluir
        begin
          @a_concluir = true
          concluir!
        ensure
          @a_concluir = false
        end
        return
      end

      @contador = (@contador || 0) + 1
      return if @contador % FRAMES_ENTRE_VERIFICACOES != 0

      return unless fase == :not_started
      ev = evento_actual
      return unless ev
      return unless ev.x && ev.y

      dist = (ev.x - $game_player.x).abs + (ev.y - $game_player.y).abs
      if dist <= DISTANCIA_ABORDAGEM
        # ⚠️ Aproximar-se, nao teletransportar-se. Passa a andar em direccao ao
        # jogador (move_type 0 = parado, controlado por nos) e so puxa conversa
        # quando esta encostado. O contador de passos e a desistencia: sem ele,
        # um NPC do outro lado de um muro tentava para sempre.
        ev.instance_variable_set(:@move_type, 0) rescue nil
        estado[:passos] = (estado[:passos] || 0) + 1
        if dist <= 1
          ev.turn_toward_player rescue nil
          ev.start rescue nil
        elsif estado[:passos] > PASSOS_MAX_ABORDAGEM
          ev.instance_variable_set(:@move_type, 1) rescue nil
          estado[:passos] = 0
        elsif !(ev.moving? rescue false)
          ev.move_toward_player rescue nil
        end
      end
    rescue => e
      log("falha no tick: #{e.class}: #{e.message}")
    end

    # ---------------------------------------------------------------- conversa
    def falar
      case fase
      when :not_started then pedir!
      when :aguardando  then lembrar!
      when :refused     then pbMessage(_INTL("...")) rescue nil
      end
    rescue => e
      log("falha ao falar: #{e.class}: #{e.message}")
    end

    def pedir!
      nome = estado[:trainer_name].to_s
      esp  = nome_especie(estado[:especie])
      pbMessage(_INTL("\\PN? Opa, com licença!")) rescue nil
      pbMessage(_INTL("{1}: Eu vim até aqui atrás de um {2}, mas não levo jeito para capturar...", nome, esp)) rescue nil
      sim = (pbConfirmMessage(_INTL("{1}: Você captura um {2} para mim? Eu te acompanho!", nome, esp)) rescue false)
      unless sim
        self.fase = :refused
        pbMessage(_INTL("{1}: Tudo bem... vou continuar tentando sozinho.", nome)) rescue nil
        ev = evento_actual
        ev.instance_variable_set(:@move_type, 1) rescue nil if ev
        return
      end
      self.fase = :aguardando
      GlobalNPC_Manager.definir_nome(nome)
      pbMessage(_INTL("{1}: Valeu mesmo! Vou logo atrás de você.", nome)) rescue nil
      virar_seguidor!
    end

    def lembrar!
      nome = estado[:trainer_name].to_s
      esp  = nome_especie(estado[:especie])
      pbMessage(_INTL("{1}: Ainda estou contando com aquele {2}!", nome, esp)) rescue nil
    end

    # --------------------------------------------------------------- seguidor
    def virar_seguidor!
      ev = evento_actual
      return unless ev
      begin
        $game_temp.followers.add_follower(ev, NOME_SEGUIDOR)
      rescue => e
        log("nao consegui por a seguir: #{e.class}: #{e.message}")
      end
      apagar_evento!
    rescue
      nil
    end

    def largar_seguidor!
      $game_temp.followers.remove_follower_by_name(NOME_SEGUIDOR)
    rescue
      nil
    end

    # ------------------------------------------------------------- a despedida
    # ⚠️ O CHARSET DO POKEMON E O DO FOLLOWER, E TEM DE TER TRES SAIDAS.
    #
    # Nem toda a especie tem sprite com forma ou variante shiny. Tenta-se do
    # mais especifico para o menos, e se nada existir nao se cria bicho nenhum —
    # o NPC sai sozinho, que e feio mas nao rebenta.
    def charset_do_entregue
      esp = estado[:quest_captured_species]
      return nil unless esp
      forma  = estado[:entregue_forma].to_i
      sufixo = forma > 0 ? "_#{forma}" : ""
      hipoteses = []
      hipoteses << "Followers shiny/#{esp}#{sufixo}" if estado[:entregue_shiny]
      hipoteses << "Followers shiny/#{esp}" if estado[:entregue_shiny]
      hipoteses << "Followers/#{esp}#{sufixo}"
      hipoteses << "Followers/#{esp}"
      hipoteses.each do |c|
        return c if (pbResolveBitmap("Graphics/Characters/#{c}") rescue nil)
      end
      nil
    rescue
      nil
    end

    # Um evento so para o boneco: sem falar, sem passear, so para andar atras.
    def criar_evento_pokemon!(dono)
      return nil unless dono && $game_map
      skin = charset_do_entregue
      return nil unless skin
      mapa = $game_map
      id = ((mapa.events.keys.max || 0) + 1)
      rpg = RPG::Event.new(dono.x, dono.y)
      rpg.id   = id
      rpg.name = NOME_EVENTO   # entra na varredura do limpar_restos!
      pg = rpg.pages[0]
      pg.graphic.character_name = skin
      pg.graphic.character_hue  = 0
      pg.trigger        = 0
      pg.walk_anime     = true
      pg.step_anime     = false
      pg.move_type      = 0
      pg.move_speed     = 3
      pg.move_frequency = 3
      pg.through        = true
      pg.list = [RPG::EventCommand.new(0, 0, [])]
      ev = Game_Event.new(mapa.map_id, rpg, mapa)
      # ⚠️ Nasce EM CIMA do dono e so depois se afasta.
      #
      # Poe-lo ja atras exigia saber para que lado ele vai andar, e isso so se
      # sabe quando a rota comeca. Nascendo no mesmo tile, o primeiro passo
      # separa-os sozinho e a leitura fica "saiu de perto dele".
      ev.moveto(dono.x, dono.y)
      ev.through = true
      mapa.events[id] = ev
      bruto = (mapa.instance_variable_get(:@map) rescue nil)
      bruto.events[id] = rpg if bruto && bruto.respond_to?(:events)
      ev.refresh rescue nil
      sincronizar_sprite(ev)
      id
    rescue => e
      log("falha ao criar o boneco do entregue: #{e.class}: #{e.message}")
      nil
    end

    # ⚠️ SAIR A ANDAR, EM VEZ DE DESAPARECER.
    #
    # Duas armadilhas aqui, e a primeira custou a encontrar.
    #
    # 1) ELE JA NAO ESTA NO MAPA. O `virar_seguidor!` entrega o evento ao
    #    sistema de followers e, na ultima linha, faz `apagar_evento!` — tira-o
    #    de `$game_map.events` e limpa o `estado[:evento_id]`. A partir desse
    #    momento o `evento_actual` devolve nil. A primeira versao disto pedia o
    #    evento por ai, nao encontrava nada, e saltava directa para o ramo de
    #    recurso: ele desaparecia, sem Pokemon e sem passo nenhum. O boneco tem
    #    de vir do `get_follower_by_name`, e depois recria-se um evento normal
    #    na posicao dele.
    #
    # 2) ISTO CORRE DENTRO DE UM FRAME HANDLER. Um `pbWait` aqui volta a entrar
    #    no `pbUpdateSceneMap`, que volta a disparar o `on_frame_update`, que
    #    volta a chamar o `tick` — e como a fase ainda nao mudou, chamava o
    #    `concluir!` outra vez, em cima de si proprio. Por isso a saida e
    #    ASSINCRONA: monta-se, marca-se a hora de fim, e quem apaga e o tick.
    # ⚠️ ELA ANDA COMO UMA PESSOA: PELO CHAO, A CONTORNAR AS COISAS.
    #
    # As duas tentativas anteriores falharam pela mesma razao de fundo — nenhuma
    # delas olhava para o mapa:
    #
    #   1) `AWAY_FROM_PLAYER` nos dois: a direccao e calculada por CADA evento a
    #      partir da posicao DELE, portanto em tiles diferentes davam respostas
    #      diferentes e eles separavam-se.
    #   2) Uma direccao unica ate a beira mais proxima: em linha recta, e como o
    #      `pbMoveRoute` liga o THROUGH por sua conta, ela atravessava sebes,
    #      arvores e cercas. Ficava pior do que desaparecer.
    #
    # Agora ha uma busca em largura a partir do tile dela, so por sitios onde ela
    # PODE mesmo pisar (`can_move_from_coordinate?`, que ja conta com o terreno e
    # com os outros eventos), ate encontrar um tile de beira — que e, na pratica,
    # por onde se sai do mapa. O caminho encontrado vira a lista de passos.
    #
    # Nao ha THROUGH em lado nenhum: a rota e montada a mao, sem o
    # `pbMoveRoute`, precisamente para nao levar o THROUGH_ON que ele injecta.
    #
    # Se nao houver saida alcancavel (um recinto fechado), vai-se ao tile mais
    # LONGE que a busca conseguiu tocar: ela afasta-se o que pode e desvanece.
    MAX_BUSCA  = 800    # tiles expandidos, tecto para nao engasgar no telemovel
    MAX_PASSOS = 40     # comprimento maximo do caminho
    # Tecto de tempo. Normalmente acaba antes, quando a rota termina.
    TEMPO_SAIDA = 12.0

    DIR_PARA_ROTA = {
      2 => PBMoveRoute::DOWN, 4 => PBMoveRoute::LEFT,
      6 => PBMoveRoute::RIGHT, 8 => PBMoveRoute::UP
    }.freeze

    # Por onde se pode sair de um tile, calculado uma vez e guardado.
    #
    # ⚠️ Este e o unico sitio caro de tudo isto: cada pergunta destas percorre
    # os eventos todos do mapa. A memoria e o que permite fazer DUAS buscas
    # (a folgada e a normal) quase pelo preco de uma — a segunda quase so le o
    # que a primeira ja perguntou.
    def saidas_de(ev, x, y, memo)
      memo[[x, y]] ||= begin
        h = {}
        [2, 4, 6, 8].each { |d| h[d] = (ev.can_move_from_coordinate?(x, y, d) rescue false) }
        h
      end
    end

    # Um tile e "folgado" quando se pode sair dele para os quatro lados: isso
    # quer dizer que nao esta encostado a nada.
    def folgado?(ev, x, y, memo)
      saidas_de(ev, x, y, memo).values.all?
    end

    # ⚠️ DUAS BUSCAS: PRIMEIRO A BONITA, DEPOIS A QUE SERVE.
    #
    # O caminho mais curto encosta-se sempre ao obstaculo — e por fora da sebe
    # que se anda menos. Fica correcto e parece mal: ela ia a raspar na parede.
    #
    # Entao tenta-se primeiro um caminho que so passe por tiles FOLGADOS (com um
    # tile livre de cada lado), o que a obriga a contornar por fora. Se esse
    # caminho nao existir — um carreiro estreito, uma ponte, uma porta — repete-
    # se a busca sem essa exigencia, que e sempre melhor do que nao sair.
    #
    # O tile de beira e a excepcao: e o destino, e nunca vai ter os quatro lados
    # livres porque um deles ja e fora do mapa.
    def caminho_para_fora(ev, sx, sy)
      return [] unless ev && $game_map
      memo = {}
      passos = busca_ate_a_beira(ev, sx, sy, memo, true)
      if passos.empty?
        passos = busca_ate_a_beira(ev, sx, sy, memo, false)
        log("sem caminho folgado; vai pelo curto") unless passos.empty?
      end
      passos
    rescue => e
      log("falha a procurar saida: #{e.class}: #{e.message}")
      []
    end

    def busca_ate_a_beira(ev, sx, sy, memo, so_folgados)
      larg = $game_map.width.to_i
      alt  = $game_map.height.to_i
      return [] if larg <= 0 || alt <= 0

      inicio = [sx, sy]
      veio_de = { inicio => nil }
      fundura = { inicio => 0 }
      fila = [inicio]
      expandidos = 0
      beira = nil
      fundo = inicio

      # ⚠️ A beira testa-se ao METER na fila, e nao ao tirar: parar assim que se
      # lhe TOCA poupa a camada inteira que ainda faltava expandir.
      until fila.empty? || beira
        actual = fila.shift
        expandidos += 1
        break if expandidos > MAX_BUSCA
        x, y = actual
        d = fundura[actual]
        fundo = actual if d > fundura[fundo]
        next if d >= MAX_PASSOS
        saidas = saidas_de(ev, x, y, memo)
        [2, 4, 6, 8].each do |dir|
          next unless saidas[dir]
          nx = x + (dir == 6 ? 1 : (dir == 4 ? -1 : 0))
          ny = y + (dir == 2 ? 1 : (dir == 8 ? -1 : 0))
          seguinte = [nx, ny]
          next if veio_de.key?(seguinte)
          next unless $game_map.valid?(nx, ny)
          na_beira = (nx <= 0 || ny <= 0 || nx >= larg - 1 || ny >= alt - 1)
          next if so_folgados && !na_beira && !folgado?(ev, nx, ny, memo)
          veio_de[seguinte] = [actual, dir]
          fundura[seguinte] = d + 1
          if na_beira
            beira = seguinte
            break
          end
          fila.push(seguinte)
        end
      end

      # ⚠️ Sem beira alcancavel, a busca FOLGADA nao serve de consolo.
      #
      # O "tile mais longe" dela seria um sitio arbitrario no meio do campo. So
      # a busca normal e que pode devolver o afastamento como recurso — e so
      # depois de ter tentado a bonita.
      alvo = beira || (so_folgados ? nil : fundo)
      return [] if alvo.nil? || alvo == inicio

      caminho = []
      no = alvo
      while (v = veio_de[no])
        caminho.unshift(v[1])
        no = v[0]
      end
      log("saida #{so_folgados ? "folgada" : "curta"}: #{caminho.length} passos, #{beira ? "ate a beira" : "so a afastar"} (#{expandidos} tiles)")
      caminho
    rescue => e
      log("falha na busca: #{e.class}: #{e.message}")
      []
    end

    # ⚠️ A ROTA E MONTADA A MAO.
    #
    # O `pbMoveRoute` do jogo comeca sempre por `THROUGH_ON`. Para quem tem de
    # respeitar as paredes isso e exactamente o contrario do que se quer, e nao
    # ha maneira de lhe pedir que nao o faca. Sao seis linhas; monta-se aqui.
    def forcar_rota(ev, comandos)
      return unless ev
      rota = RPG::MoveRoute.new
      rota.repeat    = false
      rota.skippable = true
      rota.list.clear
      comandos.each do |c|
        if c.is_a?(Array)
          rota.list.push(RPG::MoveCommand.new(c[0], c[1..-1]))
        else
          rota.list.push(RPG::MoveCommand.new(c))
        end
      end
      rota.list.push(RPG::MoveCommand.new(0))
      ev.force_move_route(rota)
    rescue => e
      log("falha a forcar a rota: #{e.class}: #{e.message}")
    end

    # O desvanecer do fim, igual para os dois.
    def cauda_do_fade
      [[PBMoveRoute::OPACITY, 170], [PBMoveRoute::WAIT, 2],
       [PBMoveRoute::OPACITY, 85],  [PBMoveRoute::WAIT, 2],
       [PBMoveRoute::OPACITY, 0]]
    end

    def partida!
      # Onde e para que lado ele esta, agora que e um follower.
      seg = ($game_temp.followers.get_follower_by_name(NOME_SEGUIDOR) rescue nil)
      sx = (seg ? seg.x : nil)
      sy = (seg ? seg.y : nil)
      largar_seguidor!

      if sx.nil? && evento_actual
        sx = evento_actual.x
        sy = evento_actual.y
      end
      apagar_evento!

      if sx.nil? || !$game_map
        terminar_despedida!
        return
      end

      skin = estado[:skin].to_s
      npc_id = (skin.empty? ? nil : criar_evento!($game_map, sx, sy, skin, true))
      poke_id = npc_id ? criar_evento_pokemon!($game_map.events[npc_id]) : nil

      npc  = npc_id  ? $game_map.events[npc_id]  : nil
      poke = poke_id ? $game_map.events[poke_id] : nil

      # ⚠️ NINGUEM SAI DOS LIMITES DO MAPA, NEM COM THROUGH.
      #
      # O `passable?` (0050_Game_Character) testa `map.valid?` ANTES de olhar
      # para o @through, portanto o ultimo tile e mesmo a beira. Chegados la,
      # desvanecem-se em vez de sumirem de golpe.
      passos = caminho_para_fora(npc, sx, sy)
      andar = passos.map { |d| DIR_PARA_ROTA[d] }.compact

      forcar_rota(npc, andar + cauda_do_fade) if npc
      # ⚠️ O Pokemon leva o MESMO caminho, um passo atras.
      #
      # Nao ha calculo nenhum do lado dele: repete os passos dela. A espera
      # inicial e o que o poe a seguir em vez de sobreposto, ja que nasce no
      # tile dela. E como o evento dele nasce com through, ela nunca lhe barra o
      # caminho nem ele a ela.
      forcar_rota(poke, [[PBMoveRoute::WAIT, 6]] + andar + cauda_do_fade) if poke

      estado[:evento_id]      = npc_id
      estado[:evento_poke_id] = poke_id
      estado[:saida_ate]      = Time.now.to_f + TEMPO_SAIDA
      self.fase = :despedida
      log("despedida a decorrer (npc=#{npc_id.inspect} poke=#{poke_id.inspect})")
    rescue => e
      log("falha na despedida: #{e.class}: #{e.message}")
      terminar_despedida!
    end

    # Apaga o que sobrou e arruma o estado. Corre no fim da saida, e tambem
    # como ramo de recurso quando ela nem chega a comecar.
    def terminar_despedida!
      # ⚠️ Os dois ids leem-se ANTES de apagar seja o que for.
      #
      # O `apagar_evento!` limpa o `estado[:evento_id]` no fim, sempre. Apagar o
      # Pokemon primeiro deixava o id do NPC a nil e ele ficava no mapa, parado,
      # para sempre — a andar em circulos ate o jogador mudar de mapa.
      npc_id  = estado[:evento_id]
      poke_id = estado[:evento_poke_id]
      estado[:evento_poke_id] = nil
      (largar_seguidor! rescue nil)
      (apagar_evento!(npc_id) rescue nil) if npc_id
      (apagar_evento!(poke_id) rescue nil) if poke_id
      self.fase = :completed
      estado[:descanso_ate] = Time.now.to_i + ESPERA_ENTRE_QUESTS
      estado[:evento_id] = nil
      estado[:saida_ate] = nil
      GlobalNPC_Manager.definir_nome("")
      log("concluida; proxima so depois de #{ESPERA_ENTRE_QUESTS}s")
    rescue => e
      log("falha ao arrumar a despedida: #{e.class}: #{e.message}")
      self.fase = :completed
    end

    # --------------------------------------------------------------- desfecho
    def concluir!
      nome = estado[:trainer_name].to_s
      esp  = nome_especie(estado[:quest_captured_species] || estado[:especie])
      estrelas = estado[:estrelas].to_i
      certo    = (estado[:era_o_pedido] != false)
      item, dinheiro = sortear_premio(estrelas, certo)
      pbMessage(fala_da_qualidade(nome, esp, estrelas, certo)) rescue nil
      if item
        ($bag.add(item) rescue nil)
        nome_item = (GameData::Item.get(item).name rescue item.to_s)
        pbMessage(_INTL("{1} te deu {2}!", nome, nome_item)) rescue nil
      elsif dinheiro > 0
        $player.money += dinheiro rescue nil
        pbMessage(_INTL("{1} te deu ${2} pela ajuda!", nome, dinheiro.to_s)) rescue nil
      end
      log("premio: estrelas=#{estrelas} certo=#{certo} item=#{item.inspect} dinheiro=#{dinheiro}")
      pbMessage(_INTL("{1}: Vou correndo mostrar para a minha família. Até mais!", nome)) rescue nil
      # O resto do estado so se arruma quando ele acabar de sair do ecra —
      # ver o terminar_despedida!, chamado pelo tick.
      partida!
    rescue => e
      log("falha ao concluir: #{e.class}: #{e.message}")
      terminar_despedida!
    end

    # ⚠️ A ESTRELA VERMELHA JA ESTA DEFINIDA NO JOGO: IV >= 25.
    #
    # Nao se inventa aqui um criterio novo. O MOD 098 (Wild_IV_Stars) e quem
    # desenha as estrelas na caixa de dados da batalha, e a regra dele e:
    #
    #     0..10 bronze   11..20 prata   21..24 ouro   25..31 VERMELHA
    #
    # O jogador ve essas estrelas no selvagem ANTES de o apanhar. Usar o mesmo
    # numero aqui e o que faz a mecanica ser legivel: ele olha para o bicho,
    # conta as vermelhas, e ja sabe o que vale entrega-lo.
    IV_ESTRELA_VERMELHA = 25

    # Quantas das seis estrelas sao vermelhas.
    def estrelas_vermelhas(pkmn)
      return 0 unless pkmn
      n = 0
      GameData::Stat.each_main { |st| n += 1 if pkmn.iv[st.id].to_i >= IV_ESTRELA_VERMELHA }
      n
    rescue
      0
    end

    # ⚠️ A CAIXA VERMELHA SORTEIA-SE PRIMEIRO, E SO ELA.
    #
    # Se a pepita corresse antes, comia 25% das vezes em que a caixa vermelha
    # podia sair e os 10% prometidos ao 6 estrelas viravam 7,5%. Sorteando o
    # premio maior primeiro, as probabilidades anunciadas sao exactamente as
    # que o jogador recebe, e a pepita reparte o que sobra.
    CHANCE_CAIXA_VERMELHA = { 5 => 1, 6 => 10 }.freeze

    # Depois da caixa vermelha, um quarto das entregas paga em pepita. E o
    # premio de consolo com valor de venda, para nenhuma entrega parecer vazia.
    CHANCE_PEPITA = 25

    # O premio normal de cada escalao. Escolhe-se um ao acaso da lista.
    PREMIOS = {
      0 => [],                                   # dinheiro, ver recompensa_dinheiro
      1 => [],
      2 => [],
      3 => [:GIFT_GREEN, :SACOMOEDAPEQUENO],
      4 => [:GIFT_BLUE, :SACOMOEDAMEDIO],
      5 => [:GIFT_ORANGE],
      6 => [:GIFT_ORANGE, :SACOMOEDAGRANDE]
    }.freeze

    # ⚠️ Devolve [item_ou_nil, dinheiro]. Nunca os dois cheios.
    # O que ele paga por um Pokemon que nao era o que pediu. Aceita-o na mesma —
    # ja andou a pedir ajuda, nao vai recusar — mas nao ha caixa nem pepita.
    CONSOLACAO = 1000

    def sortear_premio(estrelas, era_o_pedido = true)
      return [nil, CONSOLACAO] unless era_o_pedido
      e = estrelas.to_i
      pv = CHANCE_PEPITA
      cv = CHANCE_CAIXA_VERMELHA[e].to_i
      return [:GIFT_RED, 0] if cv > 0 && rand(100) < cv
      if rand(100) < pv
        # A pepita grande so a partir das 5 vermelhas: e o degrau que separa um
        # bicho bom de um bicho de competicao.
        return [(e >= 5 ? :BIGNUGGET : :NUGGET), 0]
      end
      lista = PREMIOS[e] || []
      return [nil, recompensa_dinheiro] if lista.empty?
      [lista.sample, 0]
    rescue
      [nil, recompensa_dinheiro]
    end

    def recompensa_dinheiro
      base = 1500
      insignias = ($player.badge_count rescue 0).to_i
      base + (insignias * 700)
    rescue
      1500
    end
    # Nome antigo, para nao partir quem o chame de fora.
    def recompensa
      recompensa_dinheiro
    end

    # ⚠️ A FALA VEM DAS ESTRELAS, E NAO DO ITEM.
    #
    # Se o texto saisse do premio, o jogador que entregasse um 6 estrelas e
    # calhasse a pepita ouvia a reaccao de um bicho vulgar. O NPC reage ao que
    # VIU — o Pokemon — e so depois entrega o que calhou.
    def fala_da_qualidade(nome, esp, estrelas, era_o_pedido = true)
      unless era_o_pedido
        pedida = nome_especie(estado[:especie])
        return _INTL("{1}: Ah... um {2}. Não era bem o {3} que eu procurava, mas... obrigado assim mesmo.",
                     nome, esp, pedida)
      end
      case estrelas.to_i
      when 0, 1
        _INTL("{1}: É ele mesmo! Um {2}! Muito obrigado!", nome, esp)
      when 2, 3
        _INTL("{1}: Um {2}! E parece bem criado, olha só esses genes!", nome, esp)
      when 4
        _INTL("{1}: Nossa... esse {2} é forte de verdade. Não era o que eu esperava!", nome, esp)
      when 5
        _INTL("{1}: Eu... eu nunca vi um {2} assim de perto. Isso é coisa de campeonato!", nome, esp)
      else
        _INTL("{1}: Um {2} PERFEITO?! Não, isso é demais, eu não posso aceitar... quer dizer, posso, mas leva isto aqui!", nome, esp)
      end
    rescue
      _INTL("{1}: É ele mesmo! Muito obrigado!", nome, esp)
    end

    # Pergunta se ESTA especie serve, para nao deixar o jogador entregar (e
    # perder) um Pokemon que nao era o pedido.
    def aceita_especie?(especie)
      return false unless fase == :aguardando
      pedida = estado[:especie]
      return false unless pedida
      especie.to_s == pedida.to_s
    rescue
      false
    end
    # ⚠️ ELE ACEITA QUALQUER UM — SO NAO FICA IGUALMENTE CONTENTE.
    #
    # Antes so aparecia a opcao de entregar quando a especie batia certo, e o
    # jogador que trouxesse outra coisa nao tinha sequer como tentar. Agora a
    # opcao esta sempre la enquanto houver pedido; o que muda e a reaccao e o
    # premio. O `aceita_especie?` fica a valer o que sempre valeu — "era este
    # que ele pediu?" — e e essa pergunta que decide o desfecho.
    def quer_este?(pkmn)
      return false unless pkmn
      fase == :aguardando && !pkmn.nil?
    rescue
      false
    end

    # ⚠️ AS ESTRELAS CONTAM-SE AQUI, NAO NA ENTREGA.
    #
    # O premio so se sorteia quando o jogador volta a falar com o NPC, e a essa
    # altura o Pokemon ja nao existe em lado nenhum — foi dado. O numero tem de
    # ficar guardado no momento em que ainda ha bicho para contar.
    def registar_entrega!(pkmn)
      estado[:quest_captured_species] = (pkmn.species rescue nil)
      estado[:estrelas] = estrelas_vermelhas(pkmn)
      estado[:era_o_pedido] = aceita_especie?(pkmn.species) ? true : false
      # ⚠️ Guarda-se o RETRATO, nao o Pokemon.
      #
      # Na despedida ele sai do ecra com o bicho atras. A essa altura o Pokemon
      # ja nao existe — foi dado — portanto o que se guarda e so o que faz
      # falta para desenhar um boneco: especie, forma, genero e se e shiny.
      estado[:entregue_forma]  = (pkmn.form rescue 0).to_i
      estado[:entregue_genero] = (pkmn.gender rescue 0).to_i
      estado[:entregue_shiny]  = ((pkmn.shiny? rescue false) ? true : false)
      self.fase = :success_pending
      log("entregue #{estado[:quest_captured_species]}")
    rescue
      nil
    end

    # ⚠️ O MENU DA CAPTURA TEM DE SER UM GANCHO, NAO UMA EDICAO DO SCRIPT.
    #
    # O `0231_Battle_CatchAndStoreMixin.rb` tinha la o menu "Dar para {nome}" e
    # nunca aparecia, por uma razao que nao se ve a olhar para ele: o plugin
    # `[v21.1 Hotfixes] Battle bug fixes.rb` REDEFINE o pbStorePokemon de raiz —
    # sem alias, linha 317 — e os plugins carregam depois de todos os scripts.
    # A nossa versao do metodo era substituida inteira antes de o jogo comecar.
    #
    # Ja tinha acontecido o mesmo com o anuncio de shiny (MOD 134). O padrao que
    # resolve e este: envolver o metodo FINAL, seja ele de quem for, e reinstalar
    # no apply_post_plugin_patches. O @seq da um nome novo a cada instalacao,
    # para nunca se envolver duas vezes o mesmo alias; e a comparacao do
    # instance_method torna a chamada idempotente.
    #
    # Pergunta-se ANTES de guardar. Se o jogador disser que sim, o Pokemon nao
    # e guardado em lado nenhum — foi dado.
    def instalar_gancho_captura!
      return false unless defined?(Battle::CatchAndStoreMixin)
      m = Battle::CatchAndStoreMixin
      actual = m.instance_method(:pbStorePokemon)
      return false if @gancho && @gancho == actual
      @seq = (@seq || 0) + 1
      antigo = :"anil_npc_pbStorePokemon_#{@seq}"
      m.send(:alias_method, antigo, :pbStorePokemon)
      m.send(:define_method, :pbStorePokemon) do |pkmn|
        # ⚠️ UM MENU, E NAO UM "SIM/NAO".
        #
        # Era uma pergunta seca antes de guardar, e ficava deslocada: o jogador
        # acaba de apanhar um Pokemon e o que ele espera a seguir e a escolha do
        # costume — equipa, caixa, ver os dados. A entrega passa a ser mais uma
        # linha nessa lista, no fim, onde nao atrapalha quem so quer ficar com o
        # bicho.
        #
        # ⚠️ E O "ADICIONAR A EQUIPA" DELEGA, NAO COPIA.
        #
        # Com a equipa cheia, por o Pokemon dentro obriga a mandar outro para a
        # caixa — e isso arrasta estado da batalha (@initialItems, os niveis de
        # antes, os criticos por slot) que so o metodo original sabe arrumar.
        # Copia-lo aqui era garantir que um dia ficava dessincronizado. Entao
        # essa opcao chama o original e deixa-o fazer o que ja faz bem; nesse
        # caso, com a equipa cheia, aparece o ecra de troca dele a seguir.
        if AnilNPCAjuda.quer_este?(pkmn)
          nome = AnilNPCAjuda.estado[:trainer_name].to_s
          escolha = nil
          loop do
            cmds = [
              _INTL("Adicionar à equipe"),
              _INTL("Enviar para uma caixa"),
              _INTL("Ver os dados de {1}", pkmn.name),
              _INTL("Dar para {1}", nome)
            ]
            cmd = pbShowCommands(_INTL("O que fazer com {1}?", pkmn.name), cmds, 99)
            case cmd
            when 3   # dar ao NPC
              # ⚠️ Um aviso quando NAO e o que ele pediu.
              #
              # Entregar e irreversivel e o premio de um bicho errado e uma
              # gorjeta. Sem isto, bastava um toque a mais no menu para dar um
              # Pokemon bom por mil moedas. Quando E o pedido nao se pergunta
              # nada: ai o jogador sabe bem o que esta a fazer.
              unless AnilNPCAjuda.aceita_especie?(pkmn.species)
                pedida = AnilNPCAjuda.nome_especie(AnilNPCAjuda.estado[:especie])
                next unless pbConfirmMessage(
                  _INTL("{1} pediu um {2}. Dar {3} mesmo assim?", nome, pedida, pkmn.name))
              end
              AnilNPCAjuda.registar_entrega!(pkmn)
              pbDisplayPaused(_INTL("Você entregou {1} para {2}!", pkmn.name, nome))
              escolha = :dado
              break
            when 2   # ver os dados, e volta ao menu
              pbFadeOutIn do
                cena = PokemonSummary_Scene.new
                ecra = PokemonSummaryScreen.new(cena, true)
                ecra.pbStartScreen([pkmn], 0)
              end
              next
            when 1   # caixa
              caixa = @peer.pbStorePokemon(pbPlayer, pkmn)
              nome_caixa = @peer.pbBoxName(caixa)
              if pkmn.item && pbConfirmMessage(_INTL("{1} está segurando {2}. Quer guardar o item na mochila?", pkmn.name, pkmn.item.name))
                $bag.add(pkmn.item)
                pkmn.item = nil
              end
              pbDisplayPaused(_INTL("{1} foi enviado para a Caixa \"{2}\"!", pkmn.name, nome_caixa))
              escolha = :caixa
              break
            else     # 0 = equipa, 99 = cancelou
              escolha = :original
              break
            end
          end
          next nil if escolha == :dado || escolha == :caixa
        end
        send(antigo, pkmn)
      end
      @gancho = m.instance_method(:pbStorePokemon)
      log("gancho de captura instalado (#{@seq})")
      true
    rescue => e
      log("falha ao instalar o gancho de captura: #{e.class}: #{e.message}")
      false
    end
  end
end

#-------------------------------------------------------------------------------
# Reinstalar o gancho DEPOIS dos plugins, que e quando o pbStorePokemon final
# existe. Sem isto o menu nunca aparecia.
#-------------------------------------------------------------------------------
module AnilLanRework
  class << self
    unless method_defined?(:anil_npcajuda_orig_apply_post_plugin_patches)
      alias_method :anil_npcajuda_orig_apply_post_plugin_patches, :apply_post_plugin_patches rescue nil
    end

    def apply_post_plugin_patches
      anil_npcajuda_orig_apply_post_plugin_patches rescue nil
      AnilNPCAjuda.instalar_gancho_captura! rescue nil
    end
  end
end

#-------------------------------------------------------------------------------
# O contrato que o 0231_Battle_CatchAndStoreMixin esperava, mantido para quem o
# leia — mas quem faz a entrega e o gancho aqui de cima.
#-------------------------------------------------------------------------------
module GlobalNPC_Manager
  NPC_CONFIG = { AnilNPCAjuda::IDX => { :trainer_name => "" } }

  def self.definir_nome(nome)
    NPC_CONFIG[AnilNPCAjuda::IDX][:trainer_name] = nome.to_s
  rescue
    nil
  end

  # ⚠️ Devolve o hash VIVO: o gancho escreve nele.
  def self.pbGetNPCLifeSystemData
    { AnilNPCAjuda::IDX => AnilNPCAjuda.estado }
  end

  def self.aceita_especie?(_idx, especie)
    AnilNPCAjuda.aceita_especie?(especie)
  end
end

#-------------------------------------------------------------------------------
# Ganchos do jogo.
#-------------------------------------------------------------------------------
EventHandlers.add(:on_map_or_spriteset_change, :anil_npc_ajuda,
  proc { |_scene, mudou|
    next unless mudou
    AnilNPCAjuda.limpar_restos!
    AnilNPCAjuda.tentar_aparecer!
  }
)

EventHandlers.add(:on_frame_update, :anil_npc_ajuda,
  proc { AnilNPCAjuda.tick }
)

#-------------------------------------------------------------------------------
# Comando de chat: /npc — faz aparecer um aqui, para testar.
#
# E LOCAL de proposito, ao contrario do /event: este NPC e inteiramente do lado
# do cliente e nao existe para mais ninguem, portanto nao ha nada a combinar com
# o servidor. A verificacao de admin e so para nao andar toda a gente a invocar.
#-------------------------------------------------------------------------------
module AnilNPCAjudaComando
  ADMINS = ["wallace-adm100"].freeze

  module_function

  def admin?
    return AnilEventoShinyComando.admin? if defined?(AnilEventoShinyComando)
    id = AnilLanRework.read_cfg("multiplayer_player.txt", "id", "").to_s.strip.downcase
    ADMINS.include?(id)
  rescue
    false
  end

  def avisar(txt)
    if AnilLanRework.respond_to?(:add_popup)
      AnilLanRework.add_popup(txt, 6.0) rescue nil
    else
      pbMessage(txt) rescue nil
    end
  end

  def tratar(texto)
    t = texto.to_s.strip
    return false unless t =~ %r{\A/npc(?:\s+(.*))?\z}i
    resto = $1.to_s.strip.downcase

    unless admin?
      avisar(_INTL("[NPC] Comando disponível apenas para administradores."))
      return true
    end

    if resto == "off" || resto == "limpar"
      AnilNPCAjuda.largar_seguidor!
      AnilNPCAjuda.apagar_evento!
      AnilNPCAjuda.limpar_restos!
      AnilNPCAjuda.fase = :completed
      AnilNPCAjuda.estado[:descanso_ate] = nil
      avisar(_INTL("[NPC] Limpo."))
      return true
    end

    if AnilNPCAjuda.activa?
      avisar(_INTL("[NPC] Já existe um pedido em andamento. Use /npc off para limpar."))
      return true
    end

    # /npc <especie> forca o que ele pede; /npc sozinho deixa a rota escolher.
    forcada = nil
    unless resto.empty?
      sym = resto.upcase.gsub(/[^A-Z0-9_]/, "").to_sym
      if (GameData::Species.exists?(sym) rescue false)
        forcada = sym
      else
        avisar(_INTL("[NPC] Não conheço a espécie \"{1}\". Use /npc ou /npc <espécie>.", resto))
        return true
      end
    end

    if AnilNPCAjuda.tentar_aparecer!(true, forcada)
      esp = AnilNPCAjuda.nome_especie(AnilNPCAjuda.estado[:especie])
      avisar(_INTL("[NPC] {1} apareceu aqui e quer um {2}.",
                   AnilNPCAjuda.estado[:trainer_name].to_s, esp))
    else
      avisar(_INTL("[NPC] Não deu para criar aqui (mapa sem encontros ou sem espaço livre)."))
    end
    true
  rescue => e
    AnilNPCAjuda.log("falha no comando: #{e.class}: #{e.message}")
    false
  end
end

module AnilLanRework
  module Chat
    class << self
      unless method_defined?(:anil_npcajuda_orig_send_message)
        alias_method :anil_npcajuda_orig_send_message, :send_message rescue nil
      end

      def send_message(text)
        return if AnilNPCAjudaComando.tratar(text)
        anil_npcajuda_orig_send_message(text)
      end
    end
  end
end

AnilLanRework.log("155_NPC_Ajuda_Captura carregado") rescue nil
