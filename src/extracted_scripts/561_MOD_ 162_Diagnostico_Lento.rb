# encoding: UTF-8
#===============================================================================
# MOD: 162_Diagnostico_Lento
#-------------------------------------------------------------------------------
# Mudar de mapa, abrir a party e sair de batalha: onde e que se perde o tempo.
#
# ⚠️ ISTO NAO E O 161, E NAO PODIA SER.
#
# O 161 mede por FRAME, dentro do Scene_Map#update. Estas tres operacoes correm
# quase todas FORA dele — a party e outra cena, a transferencia bloqueia o ciclo
# — portanto o 161 nunca as via. O que faz falta aqui nao e uma media por
# segundo: e o relogio de UMA operacao, repartido pelas partes que a compoem.
#
# ⚠️ O QUE ISTO ESCREVE E UMA ARVORE, E A INDENTACAO E A RESPOSTA.
#
#   LENTO mudanca_de_mapa 1840ms
#     Scene_Map#transfer_player            1838ms
#       PokemonMapFactory#setup             120ms
#       Spriteset_Map#initialize            910ms
#         Sprite_Character#initialize x47    12ms
#       Graphics.transition                 666ms
#
# Cada linha e o tempo TOTAL daquele passo, ja incluindo os filhos. Procura-se
# de cima para baixo o primeiro sitio onde o tempo do pai nao esta explicado
# pelos filhos — e ai que esta o trabalho.
#
# ⚠️ NEM TUDO O QUE DEMORA E UM DEFEITO.
#
# O `Graphics.transition(40)` sao 40 frames de propósito: e o esbatimento do
# mapa. A 60 fps sao 666 ms que o jogo DEVE gastar. Ele esta instrumentado
# exactamente para nao levarmos essa parte a conta do problema.
#
# ⚠️ SO ESCREVE O QUE PASSAR DO LIMIAR.
#
# Uma mudanca de mapa rapida nao interessa. So se grava a operacao que demorou,
# senao o ficheiro enche-se de ruido e o travao esconde-se no meio.
#
# Ficheiro: `anil_lento.log`, na pasta do jogo.
#===============================================================================

module AnilDiagLento
  # DESLIGADO. Com isto a false o instalar! desiste a entrada e NENHUM dos 45
  # enxertos e sequer instalado — nao ha ficheiro a crescer nem um relogio lido.
  # ⚠️ Ligado pelo mesmo interruptor de todos os diagnosticos: basta existir o
  # ficheiro `Data/anil_debug.txt`. Assim nao se distribui um build com isto
  # sempre ligado — quem nao tem o ficheiro nao paga nem um `if` a mais, porque
  # a constante fica false e os guardas saem logo a entrada.
  #
  # Le-se aqui, no arranque: o anil_diagnostico_ligado? ja vem do MOD 000, que
  # carrega antes deste, e ele proprio guarda o resultado em cache.
  ACTIVO     = (anil_diagnostico_ligado? rescue false)
  FICHEIRO   = "anil_lento.log"
  LIMIAR     = 0.150   # so se grava a operacao que passar disto (150 ms)
  # ⚠️ O SPAWN NUNCA IA APARECER COM O LIMIAR GERAL.
  #
  # Nascer um selvagem custa dezenas de milissegundos, nao centenas — passava
  # sempre por baixo dos 150 ms e o log ficava calado sobre ele. Mas no telemovel
  # dezenas de ms sao dois ou tres frames perdidos, que e a "travadinha".
  # Cada operacao pode ter o seu proprio limiar.
  LIMIARES   = { "spawn" => 0.030 }
  MAX_NOS    = 400     # travao contra arvores gigantes (mapas com muitos eventos)
  MAX_LINHAS = 60      # quantos passos se escrevem, os mais demorados primeiro

  @nos    = []
  @nivel  = 0
  @contas = Hash.new(0)
  # ⚠️ QUEM E QUE ESTA A SER RECARREGADO, E NAO SO QUANTOS.
  #
  # "676 bitmaps ao abrir a party" nao diz o que fazer. "o mesmo icone 113
  # vezes" diz. Conta-se por caminho de ficheiro, e sai o top no despejo.
  @caminhos = {}
  # ⚠️ QUAL SPRITE, E NAO SO "OS SPRITES".
  #
  # A Rota 13 gasta 6,5 s em 268 refrescos com 200 ms de imagens. Ou sao 268
  # refrescos a 24 ms cada — e entao e uma lentidao geral — ou e UM refresco a
  # gastar seis segundos, como foi o ItemBall. Sao causas opostas e a contagem
  # agregada nao as distingue. Aqui conta-se por personagem.
  @sprites = {}
  @instalado = false
  @postos = []

  class << self
    def agora
      System.uptime
    rescue
      Time.now.to_f
    end

    def escrever(l)
      File.open(FICHEIRO, "a") { |f| f.puts(l) }
    rescue
      nil
    end

    # ------------------------------------------------------------ o cronometro
    # ⚠️ O `ensure` nao e decoracao: se o passo rebentar a meio, o nivel TEM de
    # voltar atras. Sem isso a arvore seguinte nascia torta e o log passava a
    # mentir em vez de faltar.
    def medir(etiqueta)
      return yield unless ACTIVO
      # ⚠️ SO A THREAD PRINCIPAL MEDE.
      #
      # O @nivel, o @nos e o @contas sao de modulo, portanto partilhados. O
      # MOD 101 grava o save numa Thread a parte, e essa thread passa por
      # metodos enxertados (save:gravar, autosave:gzip). Enquanto a principal
      # estava dentro de um passo, a thread do save entrava aqui, via
      # @nivel == 0, e fazia @nos.clear — o indice que a principal tinha na mao
      # deixava de existir e o `ensure` rebentava com
      #
      #     undefined method `[]=' for nil:NilClass  (162:114)
      #
      # ...matando o jogo por causa do DIAGNOSTICO. Um medidor nunca pode ser a
      # causa da avaria. Fora da thread principal nao se mede nada.
      return yield unless (Thread.current == Thread.main rescue true)
      # ⚠️ Zerar ao ABRIR, e nao so ao fechar. Senao os bitmaps e sprites
      # criados no jogo normal, antes da operacao comecar, apareciam na conta
      # dela — e a party levava a culpa de trabalho que nao era dela.
      if @nivel == 0
        @nos.clear
        @contas.clear
        @caminhos.clear
        @sprites.clear
      end
      indice = nil
      if @nos.length < MAX_NOS
        indice = @nos.length
        @nos << [etiqueta, @nivel, 0.0]
      end
      @nivel += 1
      t0 = agora
      begin
        yield
      ensure
        d = agora - t0
        @nivel -= 1
        # Nunca indexar as cegas: se o no ja nao la estiver, perde-se um tempo
        # no log — o que e infinitamente melhor do que perder a partida.
        no = (@nos[indice] if indice)
        no[2] = d if no
        if @nivel <= 0
          @nivel = 0
          fechar!(d)
        end
      end
    end

    # Contagens sem no proprio: coisas que acontecem as centenas (sprites,
    # eventos, bitmaps). Um no por cada uma afogava a arvore.
    def contar(chave, tempo = 0.0)
      return unless ACTIVO
      @contas[chave] += 1
      @contas[:"#{chave}_ms"] += tempo
    rescue
      nil
    end

    def medir_contando(chave)
      return yield unless ACTIVO
      t0 = agora
      begin
        yield
      ensure
        contar(chave, agora - t0)
      end
    end

    # ⚠️ POR TEMPO, E NAO SO POR CONTAGEM.
    #
    # A lista ordenada por numero de pedidos escondia justamente o suspeito: um
    # ficheiro pesado carregado UMA vez fica no fim da lista, atras de uma sombra
    # de 2 KB pedida setenta vezes. E o mapa 2 gastava 7 s em 91 imagens
    # enquanto o mapa 4 gastava 250 ms em 120 — a diferenca tem de estar num
    # ficheiro concreto, e so o tempo por ficheiro a mostra.
    def anotar_caminho(c, tempo = 0.0)
      return unless ACTIVO
      return unless c
      k = c.to_s
      v = (@caminhos[k] ||= [0, 0.0])
      v[0] += 1
      v[1] += tempo
    rescue
      nil
    end

    # A chave leva o numero do evento: quero saber se sao todos ou se e um so.
    # Dois eventos com o mesmo grafico ficam em linhas separadas de proposito.
    def anotar_sprite(ch, tempo = 0.0)
      return unless ACTIVO
      return unless ch
      nome = (ch.character_name.to_s rescue "")
      k = if ((ch.tile_id.to_i rescue 0) >= 384)
        "tile##{ch.tile_id rescue "?"}"
      elsif nome.empty?
        "(sem grafico)"
      else
        nome
      end
      k = "ev#{ch.id rescue "?"}:#{k}" if (ch.is_a?(Game_Event) rescue false)
      v = (@sprites[k] ||= [0, 0.0])
      v[0] += 1
      v[1] += tempo
    rescue
      nil
    end

    def ms(v)
      (v * 1000.0).round(1)
    end

    def fechar!(total)
      raiz_etq = @nos.empty? ? nil : @nos.first[0].to_s
      limiar = LIMIARES.fetch(raiz_etq) { LIMIAR }
      if total >= limiar && !@nos.empty?
        raiz = @nos.first
        escrever("")
        escrever("LENTO #{Time.now.strftime("%H:%M:%S")} #{raiz[0]} #{ms(total)}ms#{contexto}")
        # ⚠️ A ARVORE VAI POR ORDEM DE EXECUCAO, E NAO POR TEMPO.
        #
        # Ordenada por duracao ficava mais facil de espreitar, mas a indentacao
        # deixava de querer dizer o que diz — um filho podia aparecer antes do
        # pai. E a indentacao e justamente a informacao: e ela que mostra o que
        # esta dentro de que.
        #
        # Os passos abaixo de 2 ms nao entram: nao explicam nada e sao eles que
        # empurram o culpado para fora do limite de linhas.
        mostrados = 0
        @nos.each do |etq, nivel, d|
          next if nivel > 0 && d < 0.002
          if mostrados >= MAX_LINHAS
            escrever("        ... (#{@nos.length - mostrados} passos nao mostrados)")
            break
          end
          mostrados += 1
          escrever("        #{"  " * [nivel, 6].min}#{etq} #{ms(d)}ms")
        end
        # e ainda assim, os cinco maiores em cima da mesa
        maiores = @nos.sort_by { |(_, _, d)| -d }.first(5)
                      .reject { |(_, _, d)| d < 0.002 }
                      .map { |etq, _, d| "#{etq}=#{ms(d)}ms" }
        escrever("        maiores: #{maiores.join("  ")}") unless maiores.empty?
        escrever("        contagens: #{resumo_contagens}") unless @contas.empty?
        unless @caminhos.empty?
          por_tempo = @caminhos.sort_by { |_, v| -v[1] }.first(10)
          escrever("        MAIS CAROS: " +
                   por_tempo.map { |c, v| "#{c.split("/").last} #{ms(v[1])}ms/x#{v[0]}" }.join("  "))
          por_conta = @caminhos.sort_by { |_, v| -v[0] }.first(6)
          escrever("        mais pedidos: " +
                   por_conta.map { |c, v| "#{c.split("/").last} x#{v[0]}" }.join("  "))
          repetidos = @caminhos.count { |_, v| v[0] > 1 }
          escrever("        (#{@caminhos.length} ficheiros distintos, #{repetidos} pedidos mais de uma vez)")
        end
        unless @sprites.empty?
          caros = @sprites.sort_by { |_, v| -v[1] }.first(8)
          escrever("        SPRITES MAIS CAROS: " +
                   caros.map { |c, v| "#{c} #{ms(v[1])}ms/x#{v[0]}" }.join("  "))
        end
      end
      @nos.clear
      @contas.clear
      @caminhos.clear
      @sprites.clear
    rescue
      @nos.clear
      @contas.clear
      @caminhos.clear
      @sprites.clear
    end

    def resumo_contagens
      @contas.keys.reject { |k| k.to_s.end_with?("_ms") }.map { |k|
        t = @contas[:"#{k}_ms"]
        t > 0 ? "#{k} x#{@contas[k]} (#{ms(t)}ms)" : "#{k} x#{@contas[k]}"
      }.join("  ")
    rescue
      "?"
    end

    def contexto
      mapa = ($game_map ? $game_map.map_id : "?") rescue "?"
      " [mapa=#{mapa} ligado=#{(AnilLanRework.connected? rescue false)}]"
    rescue
      ""
    end

    # ---------------------------------------------------------------- enxertos
    # Envolve um metodo se ele existir. Devolver false em vez de rebentar e o
    # que permite ter uma lista de alvos generosa sem partir o jogo quando um
    # deles nao existe nesta versao.
    def envolver(dono, metodo, etiqueta, singleton = false, so_contar = false)
      alvo = singleton ? dono.singleton_class : dono
      return false unless alvo.method_defined?(metodo) || alvo.private_method_defined?(metodo)
      apelido = :"anil_lento_orig_#{metodo}"
      return false if alvo.method_defined?(apelido) || alvo.private_method_defined?(apelido)
      privado = alvo.private_method_defined?(metodo)
      alvo.send(:alias_method, apelido, metodo)
      if so_contar
        alvo.send(:define_method, metodo) do |*a, &b|
          AnilDiagLento.medir_contando(etiqueta) { send(apelido, *a, &b) }
        end
      else
        alvo.send(:define_method, metodo) do |*a, &b|
          AnilDiagLento.medir(etiqueta) { send(apelido, *a, &b) }
        end
      end
      alvo.send(:private, metodo) if privado
      @postos << etiqueta
      true
    rescue
      false
    end

    def instalar!
      return false unless ACTIVO
      return false if @instalado
      @instalado = true
      @postos = []

      escrever("")
      escrever("===== arranque #{Time.now.strftime("%d/%m %H:%M:%S")} " \
               "limiar=#{(LIMIAR * 1000).round}ms =====")

      # -------- mudanca de mapa
      envolver(Scene_Map, :transfer_player,    "Scene_Map#transfer_player")   if defined?(Scene_Map)
      envolver(Scene_Map, :createSpritesets,   "Scene_Map#createSpritesets")  if defined?(Scene_Map)
      envolver(Scene_Map, :disposeSpritesets,  "Scene_Map#disposeSpritesets") if defined?(Scene_Map)
      envolver(Scene_Map, :updateSpritesets,   "Scene_Map#updateSpritesets")  if defined?(Scene_Map)
      envolver(Scene_Map, :autofade,           "Scene_Map#autofade")          if defined?(Scene_Map)
      if defined?(PokemonMapFactory)
        envolver(PokemonMapFactory, :setup,           "MapFactory#setup")
        envolver(PokemonMapFactory, :getMapNoAdd,     "MapFactory#getMapNoAdd")
        envolver(PokemonMapFactory, :setMapChanged,   "MapFactory#setMapChanged")
        envolver(PokemonMapFactory, :setSceneStarted, "MapFactory#setSceneStarted")
      end
      if defined?(Game_Map)
        envolver(Game_Map, :setup,   "Game_Map#setup")
        envolver(Game_Map, :refresh, "Game_Map#refresh")
      end
      if defined?(Spriteset_Map)
        envolver(Spriteset_Map, :initialize, "Spriteset_Map#initialize")
        envolver(Spriteset_Map, :dispose,    "Spriteset_Map#dispose")
      end

      # ⚠️ O esbatimento e para ser lento. Mede-se para o PODER DESCONTAR.
      if defined?(Graphics)
        envolver(Graphics, :transition, "Graphics.transition", true)
        envolver(Graphics, :freeze,     "Graphics.freeze",     true)
      end

      # -------- nascer um selvagem (limiar proprio, ver LIMIARES)
      #
      # O `spawn` e a raiz; o que estiver dentro dele aparece por baixo. Isto
      # cobre os dois lados: o VOE que cria o evento, e o nosso MOD 070 que o
      # sincroniza pela rede.
      envolver(Object, :pbPlaceEncounter,       "spawn")
      envolver(Object, :spawnPokeEvent,         "spawn")
      envolver(Object, :pbSpawnOnStepTaken,     "spawn:passo")
      envolver(Object, :pbGenerateWildPokemon,  "spawn:gerar")
      envolver(Object, :ow_sprite_filename,     "spawn:nome_do_sprite")

      # ⚠️ SONDAR O DISCO CONTRA DESCODIFICAR O PNG.
      #
      # No JoiPlay, 91 imagens custaram 6,1 s. Falta saber se o tempo esta em
      # PROCURAR o ficheiro (o pbResolveBitmap sonda .png e .gif por cada raiz,
      # e sonda na mesma quando falha) ou em LER e descodificar. Sao correccoes
      # completamente diferentes, e ate agora as duas estavam no mesmo numero.
      #
      # O `resolve_sem_cache` so conta o que a cache nao apanhou: se ele ficar
      # perto de zero, a cache resolveu e o resto e descodificacao.
      # a reserva de tilesets: quero ver o pbGetTileset a deixar de ser chamado
      envolver(Object, :pbGetTileset,                  "tileset:ler_do_disco")
      envolver(Object, :pbResolveBitmap,               :resolve,            false, true)
      envolver(Object, :anil_resolve_bitmap_sem_cache, :resolve_sem_cache,  false, true)

      # -------- menu da party
      envolver(Object, :pbPokemonScreen, "pbPokemonScreen")
      if defined?(PokemonParty_Scene)
        envolver(PokemonParty_Scene, :pbStartScene, "Party_Scene#pbStartScene")
        envolver(PokemonParty_Scene, :pbEndScene,   "Party_Scene#pbEndScene")
        envolver(PokemonParty_Scene, :pbRefresh,    "Party_Scene#pbRefresh")
      end
      if defined?(PokemonPartyScreen)
        envolver(PokemonPartyScreen, :pbStartScene, "PartyScreen#pbStartScene")
        envolver(PokemonPartyScreen, :pbEndScene,   "PartyScreen#pbEndScene")
      end
      envolver(PokemonPartyPanel, :initialize, :painel_da_party, false, true) if defined?(PokemonPartyPanel)

      # -------- os suspeitos que atravessam as tres operacoes
      envolver(Sprite_Character, :initialize, :sprite_personagem, false, true) if defined?(Sprite_Character)
      # ⚠️ 73 sprites a 7,4 ms cada, e so 1 ms disso e bitmap. Falta saber o
      # que sao os outros 6. Estas sao as pecas que o initialize monta.
      envolver(Sprite_Character, :update,          :sprite_update,     false, true) if defined?(Sprite_Character)
      # ⚠️ ESTE NAO PASSA PELO `envolver`: precisa do @character para saber quem e.
      #
      # O `envolver` embrulha um metodo qualquer e so sabe contar. Aqui quer-se
      # o mesmo que o `bitmap_animado` faz com os caminhos: alem do tempo total,
      # o nome de quem o gastou. Foi assim que o ItemBall apareceu.
      if defined?(Sprite_Character) && !Sprite_Character.private_method_defined?(:anil_lento_orig_refresh_graphic) &&
         !Sprite_Character.method_defined?(:anil_lento_orig_refresh_graphic)
        Sprite_Character.class_eval do
          alias_method :anil_lento_orig_refresh_graphic, :refresh_graphic
          def refresh_graphic(*a, &b)
            t0 = AnilDiagLento.agora
            begin
              AnilDiagLento.medir_contando(:sprite_refresh) { anil_lento_orig_refresh_graphic(*a, &b) }
            ensure
              AnilDiagLento.anotar_sprite(@character, AnilDiagLento.agora - t0)
            end
          end
        end
        @postos << "sprite_refresh(+quem)"
      end
      envolver(Sprite_Reflection, :initialize,     :reflexo,           false, true) if defined?(Sprite_Reflection)
      envolver(Sprite_SurfBase,   :initialize,     :base_de_surf,      false, true) if defined?(Sprite_SurfBase)
      envolver(Game_Event,       :initialize, :evento_do_mapa,    false, true) if defined?(Game_Event)
      if defined?(AnimatedBitmap) && !AnimatedBitmap.private_method_defined?(:anil_lento_orig_initialize)
        AnimatedBitmap.class_eval do
          alias_method :anil_lento_orig_initialize, :initialize
          def initialize(*a, &b)
            t0 = AnilDiagLento.agora
            begin
              AnilDiagLento.medir_contando(:bitmap_animado) { anil_lento_orig_initialize(*a, &b) }
            ensure
              AnilDiagLento.anotar_caminho(a[0], AnilDiagLento.agora - t0)
            end
          end
          private :initialize
        end
        @postos << "bitmap_animado(+caminho)"
      end

      # -------- o save na nuvem (o jogador diz que aqui nao ha save; confirma-se)
      if defined?(AnilLanRework) && AnilLanRework.respond_to?(:save_and_upload_save_file)
        envolver(AnilLanRework, :save_and_upload_save_file, "AUTOSAVE", true)
      end
      # ⚠️ O upload ja corre em Thread.new — essa parte nao trava o jogo. O que
      # trava e o caminho SINCRONO: esperar pela gravacao em curso e serializar
      # o jogo inteiro. Foram 2006 ms medidos, e so 12 deles eram gzip.
      if defined?(AnilLanRework) && AnilLanRework.respond_to?(:save_and_upload_synchronously)
        envolver(AnilLanRework, :save_and_upload_synchronously, "save:sincrono", true)
      end
      envolver(AnilAsyncSave, :wait_for_save,     "save:esperar_disco", true) if defined?(AnilAsyncSave)
      if defined?(SaveData)
        envolver(SaveData, :compile_save_hash, "save:serializar", true)
        envolver(SaveData, :save_to_file,      "save:gravar",     true)
      end
      envolver(AnilSaveZip,    :empacotar,          "autosave:gzip",     true) if defined?(AnilSaveZip)
      envolver(AnilSaveSecoes, :seccoes_alteradas,  "autosave:seccoes",  true) if defined?(AnilSaveSecoes)

      # -------- a rede, que escreve no socket na thread do jogo
      if defined?(AnilLanRework::Connection)
        envolver(AnilLanRework::Connection, :send_packet,  :pacote_enviado, false, true)
        envolver(AnilLanRework::Connection, :read_packets, :pacotes_lidos,  false, true)
      end

      escrever("===== enxertos (#{@postos.length}): #{@postos.join(", ")} =====")
      true
    rescue => e
      escrever("FALHA a instalar: #{e.class}: #{e.message}")
      false
    end
  end
end

#-------------------------------------------------------------------------------
# Entra depois de toda a gente, para medir o que os outros MODs ja la puseram.
#-------------------------------------------------------------------------------
module AnilLanRework
  class << self
    unless method_defined?(:anil_lento_orig_apply_post_plugin_patches)
      alias_method :anil_lento_orig_apply_post_plugin_patches, :apply_post_plugin_patches rescue nil
    end

    def apply_post_plugin_patches
      anil_lento_orig_apply_post_plugin_patches rescue nil
      AnilDiagLento.instalar! rescue nil
    end
  end
end
