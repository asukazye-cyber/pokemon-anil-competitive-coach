#===============================================================================
# MOD: 121_Roaming_Lendarios.rb
#-------------------------------------------------------------------------------
# Coloca TODOS os lendarios do PBS (flag "Legendary", 71 especies) vagando pelo
# mapa, junto com os 4 que ja estavam configurados a mao no Settings.rb
# (Latias, Latios, Kyogre, Entei — esses ficam intactos, com o BGM e as areas
# proprias que ja tinham).
#
# POR QUE NAO DA PARA FAZER ISSO NO Settings.rb
#   1) O Settings.rb e lido ANTES do GameData.load_all, entao ali ainda nao
#      existe GameData::Species para varrer por flag. Por isso a tabela e
#      preenchida num gancho no proprio load_all.
#   2) Cada entrada e [especie, nivel, switch, tipo_encontro, bgm, areas] e o
#      0265_Overworld_RoamingPokemon so considera o roamer se a switch estiver
#      LIGADA:
#         return if roamData[2] > 0 && !$game_switches[roamData[2]]
#      Ou seja, "so incluir o ID na tabela" nao faz o lendario aparecer — ele
#      precisa de uma switch, e ela precisa estar ligada. A switch usada aqui e
#      a MESMA do evento fixo da especie (ver SWITCH_DO_EVENTO): assim cada
#      lendario so comeca a vagar quando a quest dele abre.
#
# ATENCAO — O EVENTO FIXO CONTINUA LA
#   100 especies tem um evento parado num mapa chamando
#   combate_importante_legendario. Este script NAO mexe nesses eventos, entao
#   hoje o lendario vaga E fica parado no ponto dele ao mesmo tempo. Tirar o
#   ponto fixo e um passo separado.
#
# RARIDADE
#   O 0265 faz do encontro de roamer 25% de TODOS os encontros nos 10 mapas do
#   ROAMING_AREAS. Com 71 lendarios na tabela isso viraria 1 lendario a cada 4
#   encontros. Ver AnilRoamingLendarios::CHANCE_DESEJADA abaixo.
#
# COMPATIVEL COM SAVE ANTIGO
#   O $PokemonGlobal.roamPosition salvo so tem as 4 posicoes antigas, mas o
#   pbRoamPokemonOne e o handler de encontro ja sorteiam a posicao dos indices
#   que ainda nao existem. Nada a migrar.
#===============================================================================

module AnilRoamingLendarios
  # Flag do PBS que define quem entra. "Mythical" NAO entra: miticos continuam
  # exclusivos de evento. Para incluir, acrescente "Mythical" aqui.
  FLAGS = ["Legendary"]

  NIVEL         = 50   # nivel fixo de todo lendario em roaming
  TIPO_ENCONTRO = 0    # 0 = qualquer metodo (grama, caverna, surf, pesca)
  SWITCH_PADRAO = 0    # usado so por quem nao tem evento fixo; 0 = sempre ativo

  # Switch do evento fixo de cada lendario, extraida dos proprios mapas: cada
  # evento chama combate_importante_legendario(:ESPECIE, nivel) numa pagina
  # condicionada a uma switch. Reaproveitar ESSA switch faz o lendario so entrar
  # em roaming quando a quest dele abre — os tres caes, por exemplo, dividem a
  # switch 330 (a do cartao), entao passam a vagar no instante em que a quest
  # comeca, em vez de vagarem desde o inicio do jogo.
  # 0 = o evento nao tem switch (Mew e as tres aves ja nascem disponiveis).
  SWITCH_DO_EVENTO = {
    :ARCEUS         => [288,  80],
    :ARTICUNO       => [  0,  65],
    :ARTICUNO_1     => [331,  80],
    :AZELF          => [283,  80],
    :BLACEPHALON    => [300,  80],
    :BUZZWOLE       => [300,  80],
    :CALYREX        => [314,  80],
    :CELEBI         => [218,  50],
    :CELESTEELA     => [300,  80],
    :CHIENPAO       => [352,  80],
    :CHIYU          => [352,  80],
    :COBALION       => [289,  80],
    :CRESSELIA      => [285,  80],
    :DARKRAI        => [287,  80],
    :DEOXYS         => [282,  80],
    :DIALGA         => [284,  80],
    :DIANCIE        => [297,  80],
    :ENAMORUS       => [290,  80],
    :ENTEI          => [330,  55],
    :ETERNATUS      => [312,  80],
    :FEZANDIPITI    => [354,  80],
    :GENESECT       => [294,  80],
    :GIRATINA       => [284,  80],
    :GLASTRIER      => [314,  80],
    :GOUGINGFIRE    => [357,  80],
    :GROUDON        => [279,  80],
    :GUZZLORD       => [300,  80],
    :HEATRAN        => [285,  80],
    :HOOH           => [219,  75],
    :HOOPA          => [356,  80],
    :IRONBOULDER    => [357,  80],
    :IRONCROWN      => [357,  80],
    :IRONLEAVES     => [357,  80],
    :KARTANA        => [300,  80],
    :KELDEO         => [289,  80],
    :KORAIDON       => [353,  80],
    :KYOGRE         => [279,  80],
    :KYUREM         => [293,  80],
    :LANDORUS       => [290,  80],
    :LATIAS         => [278,  80],
    :LATIOS         => [278,  80],
    :LUGIA          => [220,  75],
    :LUNALA         => [299,  80],
    :MAGEARNA       => [311,  80],
    :MARSHADOW      => [311,  80],
    :MELOETTA       => [294,  80],
    :MESPRIT        => [283,  80],
    :MEW            => [  0,  70],
    :MEWTWO         => [249,  75],
    :MIRAIDON       => [353,  80],
    :MOLTRES        => [  0,  65],
    :MOLTRES_1      => [331,  80],
    :MUNKIDORI      => [354,  80],
    :NECROZMA       => [299,  80],
    :NIHILEGO       => [300,  80],
    :OGERPON        => [355,  80],
    :OKIDOGI        => [354,  80],
    :PALKIA         => [284,  80],
    :PECHARUNT      => [355,  80],
    :PHEROMOSA      => [300,  80],
    :RAGINGBOLT     => [357,  80],
    :RAIKOU         => [330,  55],
    :RAYQUAZA       => [279,  80],
    :REGICE         => [277,  80],
    :REGIDRAGO      => [313,  80],
    :REGIELEKI      => [313,  80],
    :REGIGIGAS      => [285,  80],
    :REGIROCK       => [277,  80],
    :REGISTEEL      => [277,  80],
    :RESHIRAM       => [293,  80],
    :SHAYMIN        => [287,  80],
    :SOLGALEO       => [299,  80],
    :SPECTRIER      => [314,  80],
    :STAKATAKA      => [300,  80],
    :SUICUNE        => [330,  55],
    :TAPUBULU       => [298,  80],
    :TAPUFINI       => [298,  80],
    :TAPUKOKO       => [298,  80],
    :TAPULELE       => [298,  80],
    :TERAPAGOS      => [355,  80],
    :TERRAKION      => [289,  80],
    :THUNDURUS      => [290,  80],
    :TINGLU         => [352,  80],
    :TORNADUS       => [290,  80],
    :UXIE           => [283,  80],
    :VIRIZION       => [289,  80],
    :VOLCANION      => [297,  80],
    :WALKINGWAKE    => [357,  80],
    :WOCHIEN        => [352,  80],
    :XERNEAS        => [295,  80],
    :XURKITREE      => [300,  80],
    :YVELTAL        => [295,  80],
    :ZACIAN         => [312,  80],
    :ZAMAZENTA      => [312,  80],
    :ZAPDOS         => [  0,  65],
    :ZAPDOS_1       => [331,  80],
    :ZARUDE         => [313,  80],
    :ZEKROM         => [293,  80],
    :ZERAORA        => [311,  80],
    :ZYGARDE        => [295,  80],
  }

  # Quem tem o PONTO FIXO trocado pelo roaming. Os outros lendarios continuam
  # entrando na tabela de roaming, mas tambem seguem parados no lugar deles.
  #
  # Comecando so pelos tres caes (todos na switch 330, a do cartao) para dar
  # para testar em jogo sem mexer nos outros 68 de uma vez. Deixe a lista VAZIA
  # para valer em todos.
  ESPECIES_SEM_PONTO_FIXO = [:RAIKOU, :ENTEI, :SUICUNE]

  # Porcentagem de encontros que devem virar um roamer.
  #
  # 2026-08-23: baixado de 3 para 1 — TRES VEZES mais dificil. Com 3% havia
  # gente a apanhar cinco lendarios por dia; o lendario tinha deixado de ser
  # acontecimento. Mexer AQUI e o suficiente: o PORTAO_EM_10K deriva deste
  # valor, e a conta fecha certa em inteiros (1 * 10000 / 25 = 400).
  CHANCE_DESEJADA = 1

  # O 0265 ja aplica a dele por dentro ("next if rand(100) < 75"), e o nosso
  # portao roda ANTES dele — as duas se multiplicam. Entao o portao precisa ser
  # CHANCE_DESEJADA/CHANCE_NATIVA para o efetivo bater com o desejado:
  # 1/25 = 4% de portao x 25% nativo = 1% no fim.
  CHANCE_NATIVA = 25
  PORTAO_EM_10K = [(CHANCE_DESEJADA * 10_000) / CHANCE_NATIVA, 10_000].min

  class << self
    def popular!
      return if @populado
      tabela = Settings::ROAMING_SPECIES
      return unless tabela.is_a?(Array)
      @populado = true

      ja_listados = tabela.map { |entrada| entrada.is_a?(Array) ? entrada[0] : nil }.compact
      adicionados = 0
      sem_switch  = 0

      GameData::Species.each do |dados|
        next unless dados.form == 0                        # so a forma base
        next unless FLAGS.any? { |f| dados.has_flag?(f) }
        id = dados.species
        next if ja_listados.include?(id)
        ja_listados << id
        switch = (SWITCH_DO_EVENTO[id] || [SWITCH_PADRAO])[0].to_i
        tabela << [id, NIVEL, switch, TIPO_ENCONTRO]
        adicionados += 1
        sem_switch += 1 if switch == 0
      end

      log("#{adicionados} lendarios adicionados ao roaming (#{sem_switch} sem switch, sempre ativos). Tabela com #{tabela.length}.")
    rescue => e
      log("falha ao popular a tabela: #{e.class}: #{e.message}")
    end

    # Envolve o handler nativo em vez de recopiar as ~45 linhas dele (que fazem
    # checagem de regiao, nome de mapa e metodo de encontro). Assim a logica do
    # Essentials continua valendo e so a frequencia muda.
    def ajustar_raridade!
      return false if @raridade_ajustada
      eventos = EventHandlers.class_variable_get(:@@events)
      nomeado = eventos && eventos[:on_wild_species_chosen]
      return false unless nomeado
      callbacks = nomeado.instance_variable_get(:@callbacks)
      return false unless callbacks.is_a?(Hash)
      original = callbacks[:roaming_pokemon]
      return false unless original.is_a?(Proc)

      @raridade_ajustada = true
      portao = PORTAO_EM_10K
      callbacks[:roaming_pokemon] = proc do |encounter|
        if rand(10_000) < portao
          original.call(encounter)
        else
          # Precisa zerar aqui tambem. Quem zera normalmente e a primeira linha
          # do handler nativo; pulando ele, um indice de roamer que sobrou do
          # encontro anterior faria o :on_calling_wild_battle disparar uma
          # batalha de roamer em cima de um encontro comum.
          $game_temp.roamer_index_for_encounter = nil if $game_temp
        end
      end

      log("chance de roamer ajustada para ~#{CHANCE_DESEJADA}% (portao #{portao}/10000 sobre os #{CHANCE_NATIVA}% nativos).")
      true
    rescue => e
      log("falha ao ajustar a raridade, seguindo com os #{CHANCE_NATIVA}% nativos: #{e.class}: #{e.message}")
      false
    end

    # ------------------------------------------------------------------
    # Sumir com o ponto fixo de quem ja esta vagando
    # ------------------------------------------------------------------
    # A especie esta efetivamente em roaming agora? Como a switch do roaming e a
    # MESMA do evento fixo, isto e verdade exatamente quando a quest abriu — ou
    # seja, no instante em que o Entei "apareceria" no lugar dele, ele passa a
    # vagar em vez disso.
    def em_roaming?(especie)
      tabela = Settings::ROAMING_SPECIES
      return false unless tabela.is_a?(Array)
      entrada = tabela.find { |e| e.is_a?(Array) && e[0] == especie }
      return false unless entrada
      switch = entrada[2].to_i
      return true if switch <= 0
      $game_switches[switch] ? true : false
    rescue
      false
    end

    # Le a especie que a pagina do evento invoca. O resultado e memorizado pelo
    # object_id da pagina porque o refresh roda muito (a cada mudanca de switch,
    # variavel ou self switch do mapa inteiro).
    def especie_da_pagina(pagina)
      @cache_pagina ||= {}
      chave = pagina.object_id
      return @cache_pagina[chave] if @cache_pagina.key?(chave)

      achado = nil
      lista = (pagina.list rescue nil)
      Array(lista).each do |cmd|
        codigo = (cmd.code rescue 0)
        next unless codigo == 355 || codigo == 655   # Script / Script (continuacao)
        texto = (cmd.parameters[0].to_s rescue "")
        if texto =~ /combate_importante_legendario\(\s*:(\w+)/
          achado = Regexp.last_match(1).to_sym
          break
        end
      end
      @cache_pagina[chave] = achado
    rescue
      nil
    end

    def substituir_ponto_fixo?(especie)
      return false unless ESPECIES_SEM_PONTO_FIXO.empty? || ESPECIES_SEM_PONTO_FIXO.include?(especie)
      em_roaming?(especie)
    rescue
      false
    end

    VAZIO = [].freeze

    # Paginas do evento que INVOCAM um lendario. Nao depende de switch nenhuma,
    # so do conteudo — por isso o Game_Event calcula uma vez por evento e guarda.
    def paginas_com_lendario(paginas)
      return VAZIO unless paginas.is_a?(Array)
      achadas = paginas.select { |pagina| especie_da_pagina(pagina) }
      achadas.empty? ? VAZIO : achadas
    rescue
      VAZIO
    end

    # Dessas, quais estao suprimidas AGORA (depende da switch da quest).
    def paginas_suprimidas(paginas)
      return VAZIO unless paginas.is_a?(Array) && !paginas.empty?
      suprimidas = paginas.select do |pagina|
        especie = especie_da_pagina(pagina)
        especie && substituir_ponto_fixo?(especie)
      end
      suprimidas.empty? ? VAZIO : suprimidas
    rescue
      VAZIO
    end

    # ------------------------------------------------------------------
    # Contabilidade que o evento fixo fazia e que passou a nao rodar
    # ------------------------------------------------------------------
    # O evento chamava registrar_legendario_derrotado, que alimenta o
    # $player.defeated_combats — a lista do Deluxe Battle Kit que, ao passar da
    # Liga, vira combats_to_reset e faz o lendario derrotado (nao capturado)
    # reaparecer. Com o ponto fixo suprimido esse registro nunca aconteceria e o
    # lendario derrotado em roaming sumiria para sempre.
    #
    # O original decide por $game_variables[1] == 1 (o outcomevar do combate do
    # evento), que nao existe numa batalha de roamer. O equivalente confiavel
    # aqui e o proprio roamPokemonCaught, que o pbRoamingPokemonBattle acabou de
    # gravar: derrotado sem captura = entra na lista.
    def registrar_resultado_do_roamer(idx)
      return if idx.nil?
      return unless defined?($player) && $player
      entrada = Settings::ROAMING_SPECIES[idx] rescue nil
      return unless entrada.is_a?(Array)
      return unless $PokemonGlobal.roamPokemon[idx] == true   # a batalha encerrou o roamer
      return if $PokemonGlobal.roamPokemonCaught[idx]         # capturado nao volta

      especie = entrada[0]
      $player.defeated_combats ||= []
      return if $player.defeated_combats.include?(especie)
      $player.defeated_combats << especie
      log("#{especie} derrotado em roaming -> registrado para revanche pos-Liga.")
    rescue => e
      log("falha ao registrar resultado do roamer: #{e.class}: #{e.message}")
    end

    # Contraparte do reiniciar_legendario? que vivia na 2a pagina do evento:
    # depois da Liga, quem esta em combats_to_reset volta a vagar.
    def reprocessar_reinicios!
      return unless defined?($player) && $player
      lista = ($player.combats_to_reset ||= [])
      return if lista.empty?
      tabela = Settings::ROAMING_SPECIES
      return unless tabela.is_a?(Array)
      $PokemonGlobal.roamPokemon       ||= []
      $PokemonGlobal.roamPokemonCaught ||= []

      tabela.each_with_index do |entrada, i|
        next unless entrada.is_a?(Array)
        especie = entrada[0]
        next unless lista.include?(especie)
        next unless $PokemonGlobal.roamPokemon[i] == true
        next if $PokemonGlobal.roamPokemonCaught[i]
        lista.delete(especie)
        $PokemonGlobal.roamPokemon[i]       = nil
        $PokemonGlobal.roamPokemonCaught[i] = nil
        log("#{especie} liberado para voltar ao roaming apos a Liga.")
      end
    rescue => e
      log("falha ao reprocessar reinicios: #{e.class}: #{e.message}")
    end

    def log(msg)
      AnilLanRework.log("[ROAMING/LENDARIOS] #{msg}") rescue nil
    end
  end
end

# Enquanto o lendario esta vagando, a pagina que o coloca parado no mapa e
# escondida do seletor de paginas do Game_Event.
#
# A pagina e RETIRADA da lista antes de chamar o refresh original, em vez de
# apagar o evento depois que ele ja escolheu. A diferenca importa: assim o
# evento cai na pagina DE BAIXO em vez de sumir por completo. Tem evento nesses
# mapas que nao e "um Pokemon parado" — o Map065 ev16 se chama "Urano / Yveltal"
# e vira o lendario so numa pagina posterior; apagando o evento inteiro, o NPC
# sumiria junto e a quest quebrava. Com o fallback, ele volta a ser o NPC.
class Game_Event
  alias anil_roaming_lendarios_refresh refresh unless method_defined?(:anil_roaming_lendarios_refresh)

  def refresh
    # PERFORMANCE: o refresh roda em TODOS os eventos do mapa toda vez que
    # need_refresh e marcado, e no multiplayer o apply_switches/apply_self_switches
    # marca isso a cada pacote de sincronizacao vindo do servidor. Varrer as
    # paginas de cada evento nessa frequencia custa caro a toa.
    #
    # Quais paginas invocam lendario nao muda nunca para um evento, entao isso e
    # decidido UMA vez por evento. Para 99,96% deles (7368 de 7371) o resultado e
    # a constante VAZIO congelada, e o refresh vira um `.empty?` sem alocar nada.
    paginas = (@event.pages rescue nil)
    if @anil_roaming_lend.nil?
      @anil_roaming_lend = AnilRoamingLendarios.paginas_com_lendario(paginas)
    end
    return anil_roaming_lendarios_refresh if @anil_roaming_lend.empty?

    return anil_roaming_lendarios_refresh unless paginas.is_a?(Array)
    suprimir = AnilRoamingLendarios.paginas_suprimidas(@anil_roaming_lend)
    return anil_roaming_lendarios_refresh if suprimir.empty?

    originais = paginas.dup
    begin
      paginas.replace(originais - suprimir)
      anil_roaming_lendarios_refresh
    ensure
      paginas.replace(originais)
    end
  rescue
    anil_roaming_lendarios_refresh
  end
end

# Fecha o ciclo da contabilidade do Deluxe Battle Kit para os roamers.
unless Object.private_method_defined?(:anil_roaming_lendarios_pbRoamingPokemonBattle)
  alias anil_roaming_lendarios_pbRoamingPokemonBattle pbRoamingPokemonBattle
end

def pbRoamingPokemonBattle(pkmn, level = 1)
  # Precisa ser lido ANTES: o original zera o roamer_index_for_encounter no fim.
  idx = ($game_temp.roamer_index_for_encounter rescue nil)
  resultado = anil_roaming_lendarios_pbRoamingPokemonBattle(pkmn, level)
  AnilRoamingLendarios.registrar_resultado_do_roamer(idx)
  resultado
end

EventHandlers.add(:on_enter_map, :roaming_lendarios_reinicio,
  proc { |_old_map_id| AnilRoamingLendarios.reprocessar_reinicios! }
)

# A tabela so pode ser montada depois que as especies existem.
module GameData
  class << self
    alias anil_roaming_lendarios_load_all load_all unless method_defined?(:anil_roaming_lendarios_load_all)

    def load_all
      anil_roaming_lendarios_load_all
      AnilRoamingLendarios.popular!
    end
  end
end

# O 0265 registra o handler no carregamento, e os scripts MOD entram depois
# dele, entao neste ponto ele ja existe para ser envolvido.
AnilRoamingLendarios.ajustar_raridade!
