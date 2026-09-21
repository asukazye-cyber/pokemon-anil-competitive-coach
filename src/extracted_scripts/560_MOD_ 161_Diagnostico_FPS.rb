# encoding: UTF-8
#===============================================================================
# MOD: 161_Diagnostico_FPS
#-------------------------------------------------------------------------------
# Descobrir ONDE se perde o FPS, em vez de adivinhar.
#
# ⚠️ VEM LIGADO DE PROPOSITO.
#
# Nao ha interruptor a ligar nem actualizacao a reinstalar: quem receber este
# build ja esta a gravar. No PC o custo e invisivel e serve para recolher; no
# telemovel e onde o problema aparece.
#
# ⚠️ NAO USA AS BANDEIRAS GLOBAIS DE DEBUG.
#
# O $ENABLE_DEBUG_LOGS e o $anil_debug_log_enabled travam o "recuperar partida".
# Isto tem bandeira propria e ficheiro proprio, e nao toca em mais nada.
#
# ⚠️ DUAS COISAS DIFERENTES SAO GRAVADAS, E A SEGUNDA E A QUE INTERESSA.
#
#   RESUMO  uma linha por segundo, com a media de cada suspeito. Serve para ver
#           a tendencia (montado contra a pe, mato contra cidade).
#
#   PICO    uma linha por cada frame que passe do limiar, com a repartição
#           DESSE frame. E aqui que se ve o travao: o resumo dilui um frame de
#           300 ms em sessenta frames e faz dele uma media inocente.
#
# Ler o resultado: no PICO, a soma das partes contra o `frame`. O que sobrar
# esta fora do que instrumentei (desenho, som, o proprio motor).
#
# Ficheiro: `anil_fps.log`, na pasta do jogo (mesmo sitio dos outros .log).
#===============================================================================

module AnilDiagFPS
  # ⚠️ DESLIGADO PARA OS JOGADORES. Poe a true para voltar a medir.
  #
  # Com isto a false o instalar! desiste logo a entrada, portanto NENHUM alias e
  # sequer instalado: o Scene_Map, o Spriteset_Map, o Sprite_Character, o
  # Game_Map, o Game_Player, o Interpreter, a rede e o autosave ficam exactamente
  # como estavam. Nao ha ficheiro a crescer no disco de ninguem, nem um unico
  # relogio a ser lido por frame. O custo em jogo e zero, e nao apenas pequeno.
  ACTIVO    = false
  FICHEIRO  = "anil_fps.log"
  INTERVALO = 1.0        # segundos entre linhas de RESUMO
  LIMIAR    = 0.040      # frame acima disto (40 ms) gera uma linha de PICO
  # Cronometrar sprite a sprite custa duas leituras de relogio por sprite e por
  # frame. E o que permite separar a montaria do resto; poe a false se houver
  # duvidas de que a propria medicao esteja a pesar.
  DETALHE   = true

  # As gavetas. Nomes curtos porque vao para o ficheiro tal e qual.
  CHAVES = [:cena, :spriteset, :sprites, :refresh, :charset, :rodada,
            :sprmont, :pegadas, :rede,
            # partes do Scene_Map, para o pico que nao estava em lado nenhum
            :mapa, :jogador, :interp, :save, :zip, :seccoes].freeze

  @frame  = Hash.new(0.0)   # o frame que esta a correr agora
  @fcnt   = Hash.new(0)
  @soma   = Hash.new(0.0)   # acumulado desde a ultima linha de RESUMO
  @scnt   = Hash.new(0)
  @frames = 0
  @pior   = 0.0
  @t_resumo = nil
  @t_frame  = nil
  @picos    = 0
  @instalado = false

  class << self
    # ⚠️ SEM ALOCAR. O Time.now cria um objecto por chamada, e isto corre
    # dezenas de vezes por frame — mediria o proprio recolector de lixo.
    def agora
      System.uptime
    rescue
      Time.now.to_f
    end

    def escrever(linha)
      File.open(FICHEIRO, "a") { |f| f.puts(linha) }
    rescue
      nil
    end

    # Um cronometro. Devolve o que o bloco devolver, aconteca o que acontecer.
    def medir(chave)
      return yield unless ACTIVO
      t0 = agora
      begin
        yield
      ensure
        d = agora - t0
        @frame[chave] += d
        @fcnt[chave]  += 1
      end
    end

    # Contar sem cronometrar (para o que e caro de medir mas barato de contar).
    def contar(chave, n = 1)
      @fcnt[chave] += n
    end

    # ⚠️ PORQUE E QUE A MONTARIA FOI REFEITA.
    #
    # Guarda-se o motivo do frame corrente para sair na linha de PICO, e conta-se
    # quantas vezes cada motivo apareceu para sair no RESUMO. Um motivo que se
    # repete e uma causa; um que aparece uma vez e ruido.
    def motivo(txt)
      return unless ACTIVO
      @motivo_frame = txt
      @motivos ||= Hash.new(0)
      @motivos[txt] += 1
    rescue
      nil
    end

    def ms(v)
      (v * 1000.0).round(1)
    end

    # ------------------------------------------------------------ por frame
    # Chamado uma vez por frame, no fim do Scene_Map#update.
    def fechar_frame!
      return unless ACTIVO
      t = agora
      @t_frame ||= t
      periodo = t - @t_frame
      @t_frame = t
      @t_resumo ||= t

      # o primeiro frame depois de uma transicao nao conta: o periodo inclui o
      # tempo do ecra de carregamento e nao ha travao nenhum a relatar
      if periodo > 0.0 && periodo < 2.0
        @frames += 1
        @pior = periodo if periodo > @pior

        if periodo >= LIMIAR
          @picos += 1
          escrever("PICO  #{carimbo}  frame=#{ms(periodo)}ms  #{repartir(@frame, @fcnt)}  "                    "#{contexto}#{@motivo_frame ? "  motivo=[#{@motivo_frame}]" : ""}")
        end
      end

      CHAVES.each { |k| @soma[k] += @frame[k]; @scnt[k] += @fcnt[k] }
      @frame.clear
      @fcnt.clear
      @motivo_frame = nil

      if (t - @t_resumo) >= INTERVALO
        resumir!(t - @t_resumo)
        @t_resumo = t
      end
    end

    def repartir(soma, cnt)
      CHAVES.map { |k|
        next nil if soma[k] <= 0.0 && cnt[k] <= 0
        "#{k}=#{ms(soma[k])}/#{cnt[k]}"
      }.compact.join(" ")
    end

    def resumir!(decorrido)
      fps = decorrido > 0 ? (@frames / decorrido).round(1) : 0
      escrever("RESUMO #{carimbo} fps=#{fps} frames=#{@frames} pior=#{ms(@pior)}ms " \
               "picos=#{@picos} #{repartir(@soma, @scnt)} #{contexto} #{cenario}#{motivos_do_resumo}")
      @soma.clear
      @scnt.clear
      @frames = 0
      @pior = 0.0
      @picos = 0
      @motivos = nil
    end

    def motivos_do_resumo
      return "" if @motivos.nil? || @motivos.empty?
      " motivos={" + @motivos.map { |k, v| "#{k} x#{v}" }.join("; ") + "}"
    rescue
      ""
    end

    def carimbo
      Time.now.strftime("%H:%M:%S")
    rescue
      "?"
    end

    # O que estava a acontecer. Sem isto uma linha de PICO nao diz nada.
    def contexto
      m = (AnilMontaria.montado rescue nil)
      "montado=#{m ? m : "nao"}"
    rescue
      "montado=?"
    end

    # Contagens caras: uma vez por segundo, nunca por frame.
    def cenario
      mapa = ($game_map ? $game_map.map_id : 0) rescue 0
      selv = 0
      begin
        $game_map.events.each_value { |e| selv += 1 if defined?(Game_PokeEvent) && e.is_a?(Game_PokeEvent) }
      rescue
        selv = -1
      end
      spr = (($scene.spriteset.instance_variable_get(:@character_sprites).length rescue nil) ||
             ($scene.spritesets.values.first.instance_variable_get(:@character_sprites).length rescue nil) || -1)
      gc = (GC.count rescue -1)
      "mapa=#{mapa} selvagens=#{selv} sprites=#{spr} gc=#{gc}"
    rescue
      "cenario=?"
    end

    # ---------------------------------------------------------------- enxertos
    # ⚠️ TEM DE SER O ULTIMO A ENTRAR.
    #
    # Se estes alias entrassem antes dos do 156 e do 157, media-se o metodo
    # original e nao o que eles la puseram — ou seja, media-se tudo menos o que
    # se quer medir. Por isso isto vive no apply_post_plugin_patches, e o 161
    # carrega depois deles.
    def instalar!
      return false unless ACTIVO
      return false if @instalado
      @instalado = true
      @postos = []

      escrever("")
      escrever("===== arranque #{Time.now.strftime("%d/%m %H:%M:%S")} " \
               "limiar=#{(LIMIAR * 1000).round}ms detalhe=#{DETALHE} =====")

      enxertar_cena!
      enxertar_spriteset!
      enxertar_sprites! if DETALHE
      enxertar_montaria!
      enxertar_pegadas!
      enxertar_rede!
      enxertar_partes_da_cena!
      enxertar_save!

      escrever("===== enxertos: #{@postos.join(", ")} =====")
      true
    rescue => e
      escrever("FALHA a instalar: #{e.class}: #{e.message}")
      false
    end

    def posto(nome)
      @postos ||= []
      @postos << nome
    end

    def enxertar_cena!
      return unless defined?(Scene_Map)
      return if Scene_Map.method_defined?(:anil_fps_orig_update)
      Scene_Map.class_eval do
        alias_method :anil_fps_orig_update, :update
        def update(*a)
          AnilDiagFPS.medir(:cena) { anil_fps_orig_update(*a) }
        ensure
          AnilDiagFPS.fechar_frame!
        end
      end
      posto("cena")
    rescue
      nil
    end

    def enxertar_spriteset!
      return unless defined?(Spriteset_Map)
      return if Spriteset_Map.method_defined?(:anil_fps_orig_update)
      Spriteset_Map.class_eval do
        alias_method :anil_fps_orig_update, :update
        def update(*a)
          AnilDiagFPS.medir(:spriteset) { anil_fps_orig_update(*a) }
        end
      end
      posto("spriteset")
    rescue
      nil
    end

    def enxertar_sprites!
      return unless defined?(Sprite_Character)
      return if Sprite_Character.method_defined?(:anil_fps_orig_update)
      Sprite_Character.class_eval do
        alias_method :anil_fps_orig_update, :update
        alias_method :anil_fps_orig_refresh_graphic, :refresh_graphic
        def update(*a)
          AnilDiagFPS.medir(:sprites) { anil_fps_orig_update(*a) }
        end
        def refresh_graphic(*a)
          AnilDiagFPS.medir(:refresh) { anil_fps_orig_refresh_graphic(*a) }
        end
      end
      posto("sprites+refresh")
    rescue
      nil
    end

    # O suspeito principal: o charset do cavaleiro e a folha da montaria. A
    # CONTAGEM importa tanto como o tempo — se isto aparecer com contagem alta
    # por frame, o estado solido nao esta a agarrar.
    def enxertar_montaria!
      if defined?(AnilMontaria)
        AnilMontaria.singleton_class.class_eval do
          unless method_defined?(:anil_fps_orig_charset_do_cavaleiro)
            alias_method :anil_fps_orig_charset_do_cavaleiro, :charset_do_cavaleiro
            def charset_do_cavaleiro(*a)
              AnilDiagFPS.medir(:charset) { anil_fps_orig_charset_do_cavaleiro(*a) }
            end
          end
          unless method_defined?(:anil_fps_orig_montaria_rodada)
            alias_method :anil_fps_orig_montaria_rodada, :montaria_rodada
            def montaria_rodada(*a)
              AnilDiagFPS.medir(:rodada) { anil_fps_orig_montaria_rodada(*a) }
            end
          end
        end
        posto("charset+rodada")
      end
      if defined?(Sprite_Montaria) && !Sprite_Montaria.method_defined?(:anil_fps_orig_update)
        Sprite_Montaria.class_eval do
          alias_method :anil_fps_orig_update, :update
          def update(*a)
            AnilDiagFPS.medir(:sprmont) { anil_fps_orig_update(*a) }
          end
        end
        posto("sprite_montaria")
      end
    rescue
      nil
    end

    def enxertar_pegadas!
      return unless defined?(AnilPegadasMontaria)
      AnilPegadasMontaria.singleton_class.class_eval do
        unless method_defined?(:anil_fps_orig_trocar_desenho)
          alias_method :anil_fps_orig_trocar_desenho, :trocar_desenho
          def trocar_desenho(*a)
            AnilDiagFPS.medir(:pegadas) { anil_fps_orig_trocar_desenho(*a) }
          end
        end
      end
      posto("pegadas")
    rescue
      nil
    end

    # A rede corre na thread do jogo: se o socket bloquear, o travao aparece
    # aqui e nao no desenho.
    # ⚠️ O PICO DE ~100 ms ESTAVA DENTRO DO Scene_Map#update E FORA DE TUDO.
    #
    # O `cena` mede o update inteiro; o que nao estava em `sprites`, `spriteset`
    # nem `rede` ficava invisivel. Estas tres sao as outras pecas grandes que la
    # correm: o mapa (eventos, spawns), o jogador, e o interpretador de eventos.
    def enxertar_partes_da_cena!
      if defined?(Game_Map) && !Game_Map.method_defined?(:anil_fps_orig_update)
        Game_Map.class_eval do
          alias_method :anil_fps_orig_update, :update
          def update(*a)
            AnilDiagFPS.medir(:mapa) { anil_fps_orig_update(*a) }
          end
        end
        posto("game_map")
      end
      if defined?(Game_Player) && !Game_Player.method_defined?(:anil_fps_orig_update)
        Game_Player.class_eval do
          alias_method :anil_fps_orig_update, :update
          def update(*a)
            AnilDiagFPS.medir(:jogador) { anil_fps_orig_update(*a) }
          end
        end
        posto("game_player")
      end
      if defined?(Interpreter) && !Interpreter.method_defined?(:anil_fps_orig_update)
        Interpreter.class_eval do
          alias_method :anil_fps_orig_update, :update
          def update(*a)
            AnilDiagFPS.medir(:interp) { anil_fps_orig_update(*a) }
          end
        end
        posto("interpreter")
      end
    rescue
      nil
    end

    # O autosave para a nuvem: Marshal do jogo, gzip e escrita no socket, tudo
    # na thread do jogo. Ja medi 27-60 ms so de compressao num PC.
    def enxertar_save!
      if defined?(AnilSaveZip)
        AnilSaveZip.singleton_class.class_eval do
          unless method_defined?(:anil_fps_orig_empacotar)
            alias_method :anil_fps_orig_empacotar, :empacotar
            def empacotar(*a)
              AnilDiagFPS.medir(:zip) { anil_fps_orig_empacotar(*a) }
            end
          end
        end
        posto("save_zip")
      end
      if defined?(AnilSaveSecoes)
        AnilSaveSecoes.singleton_class.class_eval do
          unless method_defined?(:anil_fps_orig_seccoes_alteradas)
            alias_method :anil_fps_orig_seccoes_alteradas, :seccoes_alteradas
            def seccoes_alteradas(*a)
              AnilDiagFPS.medir(:seccoes) { anil_fps_orig_seccoes_alteradas(*a) }
            end
          end
        end
        posto("save_seccoes")
      end
      if defined?(AnilLanRework) && AnilLanRework.respond_to?(:save_and_upload_save_file)
        AnilLanRework.singleton_class.class_eval do
          unless method_defined?(:anil_fps_orig_save_and_upload_save_file)
            alias_method :anil_fps_orig_save_and_upload_save_file, :save_and_upload_save_file
            def save_and_upload_save_file(*a)
              AnilDiagFPS.medir(:save) { anil_fps_orig_save_and_upload_save_file(*a) }
            end
          end
        end
        posto("autosave")
      end
    rescue
      nil
    end

    def enxertar_rede!
      return unless defined?(AnilLanRework::Connection)
      return if AnilLanRework::Connection.method_defined?(:anil_fps_orig_read_packets)
      AnilLanRework::Connection.class_eval do
        alias_method :anil_fps_orig_read_packets, :read_packets
        alias_method :anil_fps_orig_flush_batch, :flush_batch
        def read_packets(*a)
          AnilDiagFPS.medir(:rede) { anil_fps_orig_read_packets(*a) }
        end
        def flush_batch(*a)
          AnilDiagFPS.medir(:rede) { anil_fps_orig_flush_batch(*a) }
        end
      end
      posto("rede")
    rescue
      nil
    end
  end
end

#-------------------------------------------------------------------------------
# Entra depois de toda a gente.
#-------------------------------------------------------------------------------
module AnilLanRework
  class << self
    unless method_defined?(:anil_fps_orig_apply_post_plugin_patches)
      alias_method :anil_fps_orig_apply_post_plugin_patches, :apply_post_plugin_patches rescue nil
    end

    def apply_post_plugin_patches
      anil_fps_orig_apply_post_plugin_patches rescue nil
      AnilDiagFPS.instalar! rescue nil
    end
  end
end
