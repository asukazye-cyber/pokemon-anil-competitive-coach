#===============================================================================
# MOD: 002_Script_Skins.rb
#-------------------------------------------------------------------------------
# Sistema de Skins Customizadas, Upload, Download e Sincronização via Servidor
#===============================================================================

module AnilLanRework
  # Defina como TRUE se quiser habilitar todo o sistema de skins no futuro.
  SKINS_ENABLED = true
  
  # Pasta de skins para sprites de caminhada (walk sprites)
  SKINS_FOLDER = "Graphics/Skins/" unless const_defined?(:SKINS_FOLDER)
end

if defined?(AnilLanRework::SKINS_ENABLED) && AnilLanRework::SKINS_ENABLED

  module AnilLanRework
    class << self
      def clear_specific_skin_cache(skin_name)
        begin
          return unless defined?(RPG::Cache)
          cache = RPG::Cache.instance_variable_get(:@cache) rescue nil
          if cache.is_a?(Hash)
            keys_to_delete = []
            cache.each_key do |k|
              if k.is_a?(String)
                if k.include?(skin_name)
                  keys_to_delete << k
                end
              elsif k.is_a?(Array) && k[0].is_a?(String)
                if k[0].include?(skin_name)
                  keys_to_delete << k
                end
              end
            end
            keys_to_delete.each do |k|
              cache.delete(k)
              log("SkinSync: removido do RPG::Cache: #{k.inspect}") rescue nil
            end
          end
        rescue => e
          log("SkinSync: erro ao limpar cache especifico: #{e.message}") rescue nil
        end
      end

      # A skin faz parte do JOGO (nao e criacao do jogador)?
      #
      # O jogo ja sabe responder a isto: os personagens dele saem de
      # GameData::PlayerMetadata e GameData::TrainerType — e a MESMA fonte que o
      # available_characters usa para o `seen[key]`, que faz a seccao dos
      # ficheiros saltar o que ja veio dos dados do jogo.
      #
      # Sem esta verificacao o cliente reenviava MACARRA, koga, GIOVANNI1... a
      # cada join (manda sempre a skin em uso), o servidor tratava como criacao
      # nova e a fila de aprovacao enchia-se de skins que sempre existiram.
      #
      # Graphics/Characters entra como segunda prova: e o acervo do jogo e o
      # sistema de skins nunca escreve la (downloads vao para Graphics/Skins e
      # Graphics/Trainers).
      def skin_do_jogo?(skin_name)
        nome = skin_name.to_s.strip
        return false if nome.empty?

        @nomes_de_personagens_do_jogo ||= begin
          conjunto = {}
          # ⚠️ Listar a pasta e comparar em minusculas, e NAO usar
          # File.exist?("Graphics/Characters/#{nome}.png"): o ficheiro do jogo e
          # "macarra.png" e o cliente manda "MACARRA". No Windows o File.exist?
          # ignora a caixa e acertava; no Android (Joiplay) distingue, e a skin
          # do jogo passaria a ser enviada so nesses aparelhos — uma diferenca
          # que so apareceria em producao, num subconjunto dos jogadores.
          begin
            if Dir.exist?("Graphics/Characters")
              Dir.entries("Graphics/Characters").each do |f|
                next unless f.downcase.end_with?(".png")
                conjunto[File.basename(f, ".*").downcase] = true
              end
            end
          rescue
          end
          begin
            GameData::PlayerMetadata.each do |meta|
              c = meta.walk_charset.to_s.strip
              conjunto[c.downcase] = true unless c.empty?
            end
          rescue
          end
          begin
            GameData::TrainerType.each do |tt|
              c = charset_name_for_trainer_type(tt.id).to_s.strip
              conjunto[c.downcase] = true unless c.empty?
            end
          rescue
          end
          log("SkinSync: #{conjunto.size} personagens do jogo reconhecidos (nao sobem para o servidor).") rescue nil
          conjunto
        end
        @nomes_de_personagens_do_jogo[nome.downcase] ? true : false
      rescue
        false
      end

      def upload_custom_skin(skin_name)
        return if skin_name.to_s.empty?

        if skin_do_jogo?(skin_name)
          log("SkinSync: '#{skin_name}' e do jogo — upload dispensado.") rescue nil
          return
        end

        local_path = "Graphics/Skins/#{skin_name}.png"
        return unless File.exist?(local_path)
        
        begin
          binary_data = File.open(local_path, "rb") { |f| f.read }
          return if binary_data.empty?
          
          encoded_data = [binary_data].pack("m0")
          
          # Sprite de pe (trainer card / frente na batalha). O jogo procura-o pelo
          # MESMO nome da skin em Graphics/Trainers — ver
          # trainer_sprite_name_for_character. Vai no mesmo pacote; se o jogador
          # nao tiver um, segue vazio e o servidor simplesmente nao grava nada.
          # (Sprite de costas nao existe neste jogo.)
          trainer_encoded = ""
          begin
            trainer_path = "Graphics/Trainers/#{skin_name}.png"
            if File.exist?(trainer_path)
              t_bin = File.open(trainer_path, "rb") { |f| f.read }
              trainer_encoded = [t_bin].pack("m0") unless t_bin.empty?
            end
          rescue => e
            log("SkinSync: nao consegui ler o sprite de treinador de '#{skin_name}': #{e.message}") rescue nil
          end

          # Arte da introducao de batalha (animacao VS). Terceiro ficheiro da
          # skin, e o unico cujo nome local NAO e o nome da skin: o
          # 0261_Overworld_BattleIntroAnim procura-o como
          # Graphics/Transitions/custom_vs_<nome>.png. No servidor volta a ser
          # so "<nome>.png", na pasta skins_vs — o nome da skin e a chave em
          # todo o lado, e a traducao para o nome do jogo fica deste lado.
          vs_encoded = ""
          begin
            vs_path = "Graphics/Transitions/custom_vs_#{skin_name}.png"
            if File.exist?(vs_path)
              v_bin = File.open(vs_path, "rb") { |f| f.read }
              vs_encoded = [v_bin].pack("m0") unless v_bin.empty?
            end
          rescue => e
            log("SkinSync: nao consegui ler a arte VS de '#{skin_name}': #{e.message}") rescue nil
          end

          if AnilLanRework.connected? && AnilLanRework.connection
            packet = {
              "type"         => "upload_custom_skin",
              "skin_name"    => skin_name,
              "skin_data"    => encoded_data,
              "trainer_data" => trainer_encoded,
              "vs_data"      => vs_encoded
            }
            AnilLanRework.connection.send_packet(packet["type"], packet) rescue nil
            log("SkinSync: Upload de skin customizada '#{skin_name}' enviado ao servidor.")
          end
        rescue => e
          log("SkinSync: Erro ao fazer upload de skin: #{e.message}")
        end
      end
    end
  end

  # ⚠️ Log PROPRIO, fora do $anil_debug_log_enabled.
  #
  # Todo o diagnostico do SkinSync passava pelo AnilLanRework.log, que comeca
  # com `return unless $anil_debug_log_enabled`. Essa variavel nao pode ser
  # ligada — trava o "recuperar partida" —, portanto em producao nao existia
  # registo NENHUM de skins: nem pedido, nem envio, nem falha. Diagnosticar um
  # jogador invisivel no telemovel era impossivel.
  #
  # Este ficheiro e pequeno (uma linha por evento de skin) e vive sozinho.
  module AnilSkinLog
    # Em Data/, junto do resto do estado do jogo (o anil_save_versao.txt vive
    # ali e escreve bem tanto no PC como no JoiPlay). Se por alguma razao a
    # pasta nao existir, cai na raiz em vez de perder o registo.
    ARQUIVO = "Data/skin_sync.txt"
    module_function

    def registar(texto)
      return unless (anil_diagnostico_ligado? rescue false)
      destino = Dir.exist?("Data") ? ARQUIVO : "skin_sync.txt"
      File.open(destino, "ab") do |f|
        f.write("[#{Time.now.strftime('%d/%m %H:%M:%S')}] #{texto}
")
      end
    rescue
    end
  end

  # Quando o id do peer finalmente chega, refaz-se o pedido que nao pode ser
  # feito antes. Sem isto, o unico gatilho era a MUDANCA do nome da skin — e
  # quem ja tinha a skin escolhida ao entrar nunca provocava outra.
  module AnilLanRework
    class RemotePeer
      unless method_defined?(:anil_skins_orig_internal_id_set)
        alias anil_skins_orig_internal_id_set internal_id=

        def internal_id=(v)
          antes = @internal_id.to_s
          anil_skins_orig_internal_id_set(v)
          if antes.empty? && !v.to_s.empty? && !@char_name.to_s.empty?
            AnilLanRework::SkinSync.check_and_request(v.to_s, @char_name.to_s) rescue nil
          end
        end
      end
    end
  end

  module AnilLanRework
    module SkinSync
      @downloading = {}
      @requested = {}

      module_function

      def check_and_request(peer_id, skin_name)
        return if skin_name.to_s.empty?

        # ⚠️ SAIDA BARATA.
        #
        # Com o tique de 30s, sem isto cada peer ja resolvido custava tres
        # File.open por tique (o png_valido? le a assinatura de cada ficheiro).
        # Uma vez satisfeita, a skin nao volta a ser verificada — quem limpa
        # esta marca e o esquecer_pedido!, chamado quando a skin muda de estado.
        @ja_tenho ||= {}
        return if @ja_tenho[skin_name.to_s]

        # ⚠️ Sem destinatario nao ha pedido.
        #
        # O RemotePeer nasce com @internal_id = "" e so o recebe depois. Se o
        # nome da skin for atribuido primeiro, o pedido saia com to_id vazio e
        # o servidor nao tinha a quem entregar — no log via-se "ao peer " com
        # o campo em branco. E como o character_name= so dispara quando o nome
        # MUDA, nunca havia segunda oportunidade: o jogador ficava invisivel
        # para aquele peer durante toda a sessao.
        #
        # Aqui tenta-se descobrir o id pelo nome da skin entre os jogadores
        # conhecidos; se mesmo assim nao houver, sai-se SEM marcar como pedido,
        # para que a proxima ocasiao volte a tentar.
        if peer_id.to_s.empty?
          peer_id = begin
            achado = AnilLanRework.players.find { |_, pl| pl && pl.char_name.to_s == skin_name.to_s }
            achado ? achado[0].to_s : ""
          rescue
            ""
          end
        end
        if peer_id.to_s.empty?
          # Uma linha por skin, nao uma por frame: sem isto o ficheiro enchia-se
          # com a mesma mensagem dezenas de vezes por minuto.
          @sem_id ||= {}
          unless @sem_id[skin_name.to_s]
            @sem_id[skin_name.to_s] = true
            AnilSkinLog.registar("nao pedi '#{skin_name}': ainda nao sei o id do peer") rescue nil
          end
          return
        end
        @sem_id.delete(skin_name.to_s) if @sem_id
        return if ["boy_walk", "girl_walk", "boy_run", "girl_run", "boy_surf", "girl_surf"].include?(skin_name.downcase)
        
        base_name = skin_name.to_s
        path_skins = "Graphics/Skins/#{base_name}.png"
        path_chars = "Graphics/Characters/#{base_name}.png"

        # Uma skin sao TRES ficheiros. Antes bastava ter o charset de andar para
        # nunca mais se pedir nada ao peer, e por isso via-se o outro jogador
        # certo no mapa mas com o treinador de omissao no trainer card e na
        # animacao VS — faltavam-lhe os outros dois e nada os ia buscar.
        #
        # O download pela /skins/list nao resolve isto: a skin de outro jogador
        # vem marcada como "oculta" e e saltada de proposito. O peer e a unica
        # fonte, entao tem de trazer o conjunto.
        # ⚠️ png_valido? e nao File.exist?.
        #
        # Este era o ultimo sitio onde a pergunta errada continuava a ser feita.
        # Um PNG corrompido de uma sessao anterior — dos que chegavam mutilados
        # antes do modo base64 — conta como "ja tenho": o cliente nao pede nada
        # ao peer e desenha o vazio. Era isto que mantinha o jogador invisivel
        # mesmo com tudo o resto ja corrigido, e sem deixar rasto no log porque
        # este caminho saia em silencio.
        vale = proc { |c| (ServerSkins.png_valido?(c) rescue false) }
        tem_walk    = vale.call(path_skins) || vale.call(path_chars)

        # ⚠️ Um follower NAO tem sprite de treinador nem arte VS.
        #
        # "Followers/GOLEM" e um Pokemon a andar atras do jogador. Exigir os
        # tres ficheiros para ele significa nunca ficar satisfeito: o pedido
        # repetia-se sem fim, a cada frame em que o boneco fosse desenhado. Para
        # estes, ter o charset e ter tudo.
        e_follower  = base_name.to_s.start_with?("Followers/")
        tem_trainer = e_follower || vale.call("Graphics/Trainers/#{base_name}.png")
        tem_vs      = e_follower || vale.call("Graphics/Transitions/custom_vs_#{base_name}.png")
        if tem_walk && tem_trainer && tem_vs
          # Uma linha por skin, nao uma por tique: com o re-pedido periodico
          # de 30s isto enchia o ficheiro sem dizer nada de novo.
          @ja_tenho ||= {}
          unless @ja_tenho[base_name]
            @ja_tenho[base_name] = true
            AnilSkinLog.registar("nao pedi '#{base_name}': ja tenho os tres ficheiros validos") rescue nil
          end
          return
        end
        @ja_tenho.delete(base_name) if @ja_tenho

        # Ficheiro presente mas invalido: apagar. Enquanto ele existir, o
        # baixar_skin_do_servidor tambem se recusa a substitui-lo.
        [path_skins,
         "Graphics/Trainers/#{base_name}.png",
         "Graphics/Transitions/custom_vs_#{base_name}.png"].each do |c|
          next unless File.exist?(c)
          next if vale.call(c)
          File.delete(c) rescue nil
          AnilSkinLog.registar("apagado '#{c}' (corrompido) antes de pedir ao peer") rescue nil
        end

        now = Time.now.to_i
        return if @requested[base_name] && (now - @requested[base_name] < 60)

        # ⚠️ O INTERVALO DE 60s NAO E UMA DESISTENCIA.
        #
        # Ele so espaca os pedidos; renovando-se a cada tentativa, o pedido
        # repetia-se de minuto a minuto PARA SEMPRE enquanto faltasse um dos
        # tres ficheiros. E ha nomes que nunca vao ter os tres: VETERANO, MIRTO,
        # lance, enigma e companhia sao charsets de TREINADOR do jogo, sem arte
        # VS nem sprite de treinador proprio. O log ficava assim:
        #
        #   02:18:05 PEDIDO 'enigma' ... (tenho walk=true trainer=false vs=false)
        #   02:19:11 PEDIDO 'enigma' ...
        #   02:20:12 PEDIDO 'enigma' ...   (indefinidamente)
        #
        # Mesma ideia do freio que o ServerSkins ja tem para os downloads: tres
        # tentativas por skin e para, ate a sessao seguinte ou ate chegar
        # ficheiro dessa skin (o esquecer_pedido! limpa a contagem).
        @tentativas ||= {}
        @tentativas[base_name] = @tentativas[base_name].to_i + 1
        if @tentativas[base_name] > LIMITE_PEDIDOS_PEER
          if @tentativas[base_name] == LIMITE_PEDIDOS_PEER + 1
            AnilSkinLog.registar(
              "desisto de pedir '#{base_name}' ao peer nesta sessao apos "               "#{LIMITE_PEDIDOS_PEER} tentativas (walk=#{tem_walk} trainer=#{tem_trainer} vs=#{tem_vs})") rescue nil
          end
          return
        end

        @requested[base_name] = now
        AnilLanRework.log("SkinSync: solicitando '#{base_name}' do peer #{peer_id}")
        AnilSkinLog.registar("PEDIDO '#{base_name}' ao peer #{peer_id} (tenho walk=#{tem_walk} trainer=#{tem_trainer} vs=#{tem_vs})")
        
        AnilLanRework.connection.send_packet("request_skin", {
          "to_id" => peer_id,
          "skin"  => base_name
        })
      end

      # ⚠️ DESENGATAR OS TRAVOES DE UMA SKIN.
      #
      # Chamado quando o servidor anuncia que a skin passou a estar aprovada.
      # Ate aqui, o relay P2P era bloqueado em silencio e o pedido NUNCA se
      # repetia: os dois gatilhos (mudanca do char_name do peer e primeira
      # atribuicao do internal_id) disparam uma vez por sessao. Aprovava-se no
      # painel e so quem reiniciasse o jogo e que passava a ver a skin.
      # Tres pedidos por skin e por sessao. O mesmo numero que o LIMITE_FALHAS
      # do ServerSkins usa para os downloads, para o comportamento ser um so.
      LIMITE_PEDIDOS_PEER = 3 unless const_defined?(:LIMITE_PEDIDOS_PEER)

      def esquecer_pedido!(nome)
        n = nome.to_s
        @requested ||= {}
        @requested.delete(n)
        @sem_id.delete(n) if @sem_id
        @ja_tenho.delete(n) if @ja_tenho
        @tentativas.delete(n) if @tentativas
      end

      # Rede de seguranca. O anuncio resolve o caso de quem esta ligado no
      # momento da aprovacao; isto apanha o resto — quem entrou depois, quem
      # perdeu o pacote, ou qualquer falha temporaria do peer.
      #
      # De 30 em 30 segundos, e nunca mais depressa: o proprio
      # check_and_request ja tem um travao de 60s por skin, portanto isto nao
      # gera enxurrada de pedidos.
      def tique_periodico
        return unless (AnilLanRework.connected? rescue false)
        agora = Time.now.to_f
        @proximo_tique ||= 0.0
        return if agora < @proximo_tique
        @proximo_tique = agora + 30.0
        (AnilLanRework.players rescue {}).each do |id, pl|
          next unless pl
          nome = pl.char_name.to_s
          next if nome.empty?
          check_and_request(id.to_s, nome)
        end
      rescue
      end

      def handle_request(packet)
        skin_name = packet["skin"].to_s
        to_id = packet["sender_id"]
        return if skin_name.empty? || !to_id
        
        path_skins = "Graphics/Skins/#{skin_name}.png"
        path_chars = "Graphics/Characters/#{skin_name}.png"
        
        # Se o meu proprio ficheiro estiver corrompido, mandar isso ao peer so
        # propaga o problema. Melhor nao responder: ele volta a pedir mais tarde,
        # e entretanto eu proprio reparo a minha copia no arranque seguinte.
        path = (ServerSkins.png_valido?(path_skins) rescue false) ? path_skins : path_chars
        unless (ServerSkins.png_valido?(path) rescue false)
          AnilLanRework.log("SkinSync: peer #{to_id} pediu skin '#{skin_name}' mas eu nao tenho localmente.")
          AnilSkinLog.registar("NAO ENVIEI '#{skin_name}' a #{to_id}: nao existe nem em Graphics/Skins nem em Graphics/Characters")
          return
        end

        begin
          data = File.open(path, "rb") { |f| f.read }
          encoded = [data].pack("m0")

          # Os outros dois ficheiros da mesma skin. Vao no mesmo pacote e sao
          # opcionais: quem nao os tiver manda vazio e o outro lado ignora.
          ler_extra = proc do |caminho|
            begin
              next "" unless File.exist?(caminho)
              bin = File.open(caminho, "rb") { |f| f.read }
              bin.empty? ? "" : [bin].pack("m0")
            rescue
              ""
            end
          end
          trainer_encoded = ler_extra.call("Graphics/Trainers/#{skin_name}.png")
          vs_encoded      = ler_extra.call("Graphics/Transitions/custom_vs_#{skin_name}.png")

          extras = []
          extras << "treinador" unless trainer_encoded.empty?
          extras << "VS" unless vs_encoded.empty?
          AnilLanRework.log("SkinSync: enviando '#{skin_name}' (#{data.size} bytes#{extras.empty? ? "" : " + " + extras.join(" e ")}) para #{to_id}")
          AnilSkinLog.registar("ENVIEI '#{skin_name}' (#{data.size} B#{extras.empty? ? "" : " + " + extras.join(" e ")}) para #{to_id}")

          AnilLanRework.connection.send_packet("skin_data", {
            "to_id"        => to_id,
            "skin"         => skin_name,
            "data"         => encoded,
            "trainer_data" => trainer_encoded,
            "vs_data"      => vs_encoded
          })
        rescue => e
          AnilLanRework.log("SkinSync: erro ao enviar skin: #{e.message}")
        end
      end

      def handle_data(packet)
        skin_name = packet["skin"].to_s
        encoded = packet["data"].to_s
        return if skin_name.empty? || encoded.empty?
        
        safe_name = skin_name.gsub(/[^a-zA-Z0-9_\-]/, "")
        return if safe_name.empty?

        path = "Graphics/Skins/#{safe_name}.png"
        ja_tem_walk = File.exist?(path) || File.exist?("Graphics/Characters/#{safe_name}.png")

        # Os dois extras gravam-se mesmo quando o charset ja ca estava: e o caso
        # de quem recebeu a skin antes de o peer passar a enviar o conjunto.
        gravar_extra = proc do |b64, destino|
          begin
            next if b64.to_s.empty?
            next if File.exist?(destino)
            bin = b64.unpack1("m0")
            next if bin.nil? || bin.empty?
            Dir.mkdir(File.dirname(destino)) unless Dir.exist?(File.dirname(destino))
            File.open(destino, "wb") { |f| f.write(bin) }
            # ⚠️ A CACHE DE "ESTA SKIN EXISTE?" TEM DE CAIR AQUI.
            #
            # O Sprite_Character#refresh_graphic (0067) deixou de ir ao disco a
            # cada refresco e passou a guardar a resposta em $anil_skin_existe.
            # Uma skin que chegue DEPOIS de alguem ja ter sido desenhado ficaria
            # marcada como inexistente para sempre. Acabou de aparecer um
            # ficheiro novo: a resposta antiga deixou de valer.
            $anil_skin_existe = nil; $anil_resolve_cache = {}
            AnilLanRework.log("SkinSync: '#{safe_name}' — #{File.basename(destino)} gravado (#{bin.size} bytes).")
            AnilSkinLog.registar("RECEBI '#{safe_name}' -> #{destino} (#{bin.size} B)")
            # Chegou alguma coisa: o peer responde, portanto vale a pena voltar
            # a pedir o que ainda falte.
            @tentativas.delete(safe_name) if @tentativas
          rescue => e
            AnilLanRework.log("SkinSync: erro ao gravar #{destino}: #{e.message}")
            AnilSkinLog.registar("FALHA AO GRAVAR #{destino}: #{e.class}: #{e.message}")
          end
        end
        gravar_extra.call(packet["trainer_data"], "Graphics/Trainers/#{safe_name}.png")
        gravar_extra.call(packet["vs_data"],      "Graphics/Transitions/custom_vs_#{safe_name}.png")

        return if ja_tem_walk

        begin
          data = encoded.unpack1("m0")
          Dir.mkdir("Graphics/Skins") unless Dir.exist?("Graphics/Skins")

          File.open(path, "wb") { |f| f.write(data) }
          $anil_skin_existe = nil; $anil_resolve_cache = {}   # ver a nota no primeiro ponto de gravacao
          AnilLanRework.log("SkinSync: skin '#{safe_name}' baixada e salva com sucesso (#{data.size} bytes).")
          
          AnilLanRework.clear_specific_skin_cache(safe_name) rescue nil
          
          $downloaded_skins_cache ||= {}
          $downloaded_skins_cache[safe_name] = true
          
          $newly_downloaded_skins ||= {}
          $newly_downloaded_skins[safe_name] = true
          $newly_downloaded_skins[safe_name.downcase] = true
          
          if $scene.is_a?(Scene_Map)
            $game_map.need_refresh = true rescue nil
          end
        rescue => e
          AnilLanRework.log("SkinSync: erro ao salvar skin recebida: #{e.message}")
        end
      end
    end

    module ServerSkins
      @unlock_callbacks = []

      module_function

      def obter_skins_desbloqueadas
        return [] unless $player && !$player.online_id.empty?
        
        server_ip = (AnilLanRework.respond_to?(:dedicated_server_ip) ? AnilLanRework.dedicated_server_ip : "127.0.0.1")
        url = "http://#{server_ip}:7654/skins/list?online_id=#{$player.online_id}"
        AnilLanRework.log("ServerSkins: obter_skins_desbloqueadas URL: '#{url}'")
        
        headers = {
          "Proxy-Connection" => "Close",
          "Pragma"           => "no-cache",
          "User-Agent"       => "Mozilla/5.0 (GameUpdater)"
        }
        
        begin
          res = HTTPLite.get(url, headers)
          if res.is_a?(Hash) && res[:status] == 200
            require "json" rescue nil
            body_str = res[:body].to_s
            
            skins = []
            if defined?(JSON)
              begin
                skins = JSON.parse(body_str)
              rescue
                skins = parse_skins_via_regex(body_str)
              end
            else
              skins = parse_skins_via_regex(body_str)
            end
            return skins
          end
        rescue Exception => e
          AnilLanRework.log("ServerSkins: Erro ao listar skins do servidor: #{e.message}")
        end
        []
      end

      def parse_skins_via_regex(body_str)
        skins = []
        # O "oculta" e opcional para continuar a ler a resposta de um servidor
        # antigo; quando vem, tem de ser respeitado — sem isto, uma falha do
        # JSON.parse faria a skin exclusiva de outro jogador reaparecer na lista.
        body_str.scan(/\{[^{}]*"char_name"\s*:\s*"([^"]+)"[^{}]*"label"\s*:\s*"([^"]+)"[^{}]*"unlocked"\s*:\s*(true|false)(?:[^{}]*"oculta"\s*:\s*(true|false))?/i) do |char_name, label, unlocked_str, oculta_str|
          skins << {
            "char_name" => char_name,
            "label"     => label,
            "unlocked"  => (unlocked_str.downcase == "true"),
            "oculta"    => (oculta_str.to_s.downcase == "true")
          }
        end
        if skins.empty?
          body_str.scan(/\{[^{}]*"char_name"\s*:\s*"([^"]+)"[^{}]*"label"\s*:\s*"([^"]+)"/i) do |char_name, label|
            skins << { "char_name" => char_name, "label" => label, "unlocked" => false, "oculta" => false }
          end
        end
        skins
      end

      # Diz se a copia local de uma skin ficou para tras da do servidor.
      # `info` e a entrada devolvida por /skins/list (traz "tamanho" e "hash").
      #
      # Conservador de proposito: so responde true quando tem CERTEZA de que
      # difere. Sem os campos do servidor (servidor antigo) devolve false — na
      # duvida nao se mexe no ficheiro do jogador.
      # tipo: :walk (Graphics/Skins), :trainer (Graphics/Trainers) ou
      # :vs (Graphics/Transitions, com o prefixo custom_vs_ que a animacao de
      # introducao de batalha espera).
      def caminho_local_da_skin(safe_name, tipo = :walk)
        case tipo
        when :trainer then "Graphics/Trainers/#{safe_name}.png"
        when :vs      then "Graphics/Transitions/custom_vs_#{safe_name}.png"
        else               "Graphics/Skins/#{safe_name}.png"
        end
      end

      def skin_local_desatualizada?(skin_name, info, tipo = :walk)
        return false unless info.is_a?(Hash)
        safe_name = skin_name.to_s.gsub(/[^a-zA-Z0-9_\-]/, "")
        return false if safe_name.empty?
        local_path = caminho_local_da_skin(safe_name, tipo)
        return false unless File.exist?(local_path)

        campo_tam  = case tipo
                     when :trainer then "trainer_tamanho"
                     when :vs      then "vs_tamanho"
                     else               "tamanho"
                     end
        campo_hash = case tipo
                     when :trainer then "trainer_hash"
                     when :vs      then "vs_hash"
                     else               "hash"
                     end

        # Tamanho primeiro: e barato e pega qualquer redimensionamento.
        tam_servidor = info[campo_tam].to_i
        if tam_servidor > 0
          return true if File.size(local_path) != tam_servidor
        end

        # Tamanho igual pode ser coincidencia; o hash decide.
        hash_servidor = info[campo_hash].to_s
        return false if hash_servidor.empty?
        begin
          require 'digest'
          local_hash = Digest::SHA256.file(local_path).hexdigest[0, hash_servidor.length]
          return local_hash != hash_servidor
        rescue Exception => e
          AnilLanRework.log("ServerSkins: nao consegui comparar o hash de '#{safe_name}': #{e.message}") rescue nil
          return false
        end
      end

      # ⚠️ Freio de tentativas.
      #
      # Quando o download falha de forma persistente — servidor sem a rota,
      # canal que estraga o binario, skin apagada — cada tentativa de DESENHAR
      # dispara outra descarga. O log mostrou dez em vinte segundos, e abrir o
      # seletor (que resolve todas as skins de uma vez) chegava a derrubar o
      # jogo no Android.
      #
      # Tres falhas por skin/tipo e para. Volta a tentar no arranque seguinte,
      # ou quando o `forcar` pedir explicitamente.
      @falhas = {} unless defined?(@falhas) && @falhas
      LIMITE_FALHAS = 3 unless const_defined?(:LIMITE_FALHAS)

      def desistiu?(chave)
        @falhas ||= {}
        @falhas[chave].to_i >= LIMITE_FALHAS
      end

      def anotar_falha(chave)
        @falhas ||= {}
        @falhas[chave] = @falhas[chave].to_i + 1
        if @falhas[chave] == LIMITE_FALHAS
          AnilSkinLog.registar("desisto de '#{chave}' nesta sessao apos #{LIMITE_FALHAS} falhas") rescue nil
        end
      end

      def esquecer_falhas!(nome = nil)
        @falhas ||= {}
        nome ? @falhas.delete_if { |k, _| k.to_s.start_with?("#{nome}:") } : @falhas.clear
      end

      def baixar_skin_do_servidor(skin_name, cache = false, forcar = false, tipo = :walk)
        return if skin_name.to_s.empty?

        safe_name = skin_name.to_s.gsub(/[^a-zA-Z0-9_\-]/, "")
        return if safe_name.empty?

        case tipo
        when :trainer
          dir_path   = "Graphics/Trainers"
          local_path = "#{dir_path}/#{safe_name}.png"
        when :vs
          # Unico caso em que o ficheiro NAO se chama como a skin: a animacao de
          # introducao procura-o por custom_vs_<nome>. Ver caminho_local_da_skin.
          dir_path   = "Graphics/Transitions"
          local_path = "#{dir_path}/custom_vs_#{safe_name}.png"
        else
          dir_path   = cache ? "Graphics/Skins/Cache" : "Graphics/Skins"
          local_path = "#{dir_path}/#{safe_name}.png"
        end
        # `forcar` e o que permite ATUALIZAR uma skin. Sem ele esta linha fazia
        # com que uma versao errada ja baixada nunca mais fosse corrigida.
        return if File.exist?(local_path) && !forcar
        chave_falha = "#{safe_name}:#{tipo}"
        if desistiu?(chave_falha) && !forcar
          return false
        end

        server_ip = (AnilLanRework.respond_to?(:dedicated_server_ip) ? AnilLanRework.dedicated_server_ip : "127.0.0.1")
        # O online_id identifica quem pede: skin custom so e servida ao dono ou a
        # quem recebeu liberacao. O servidor ainda aceita pedido sem id (builds
        # antigos), mas isso deixa a rota aberta — por isso o build novo manda.
        meu_id = ($player ? $player.online_id.to_s : "") rescue ""
        url = "http://#{server_ip}:7654/skins/download?name=#{safe_name}"
        url += "&online_id=#{meu_id}" unless meu_id.empty?
        url += "&tipo=trainer" if tipo == :trainer
        url += "&tipo=vs"      if tipo == :vs
        # Pedir sempre em base64. O HTTPLite do mkxp no Android le a resposta
        # como TEXTO e come os bytes 0x0D: um PNG cru chega mutilado e e
        # descartado pela validacao abaixo, sem erro visivel. Era isto que
        # impedia qualquer skin de chegar ao JoiPlay. Servidor antigo ignora o
        # parametro e devolve o binario de sempre — o lado de baixo aceita as
        # duas formas.
        url += "&b64=1"

        headers = {
          "Proxy-Connection" => "Close",
          "Pragma"           => "no-cache",
          "User-Agent"       => "Mozilla/5.0 (GameUpdater)"
        }

        AnilLanRework.log("ServerSkins: Baixando skin '#{safe_name}' do servidor (cache=#{cache})...")

        begin
          dl = HTTPLite.get(url, headers)
          # ⚠️ Sem isto, uma recusa do servidor nao deixa rasto NENHUM no log do
          # cliente: o ficheiro parecia dizer que nem se tentou, quando na
          # verdade o pedido saiu e voltou 404. Foi exatamente o que aconteceu
          # com o leprechaun — o servidor registava "Negado" e aqui nao havia
          # linha alguma.
          unless dl.is_a?(Hash) && dl[:status] == 200
            AnilSkinLog.registar("'#{safe_name}' (#{tipo}): servidor respondeu #{(dl.is_a?(Hash) ? dl[:status] : dl.inspect)}") rescue nil
          end
          if dl.is_a?(Hash) && dl[:status] == 200
            corpo = dl[:body].to_s
            # Com `forcar` esta escrita SOBREPOE uma skin que ja funcionava.
            # Confirmar que o corpo e mesmo um PNG evita trocar um ficheiro bom
            # por uma pagina de erro ou por uma resposta truncada.
            # ⚠️ Validar os OITO bytes da assinatura, nao quatro.
            #
            # A assinatura de um PNG e 137 P N G CR LF 26 LF — o quinto byte e
            # um CR. O teste antigo olhava so os quatro primeiros, e "137 P N G"
            # sobrevive intacto quando o Android come os CR. Um ficheiro
            # mutilado passava no teste, era gravado, e so se descobria depois
            # que nao abria em lado nenhum: media 59,2 KB em vez de 59,4 KB,
            # a diferenca exata dos CR que faltavam.
            #
            # Com os oito bytes, o corpo cru mutilado e reprovado — e so entao a
            # tentativa de base64 tem a oportunidade de acontecer.
            assinatura = [137, 80, 78, 71, 13, 10, 26, 10].pack("C*")
            valido = proc { |b| !b.nil? && b.bytesize > 8 && b.byteslice(0, 8) == assinatura }

            unless valido.call(corpo)
              decodificado = (corpo.unpack("m0").first rescue nil)
              if valido.call(decodificado)
                AnilSkinLog.registar("'#{safe_name}' (#{tipo}) veio em base64: #{corpo.bytesize} -> #{decodificado.bytesize} B") rescue nil
                corpo = decodificado
              end
            end

            unless valido.call(corpo)
              AnilLanRework.log("ServerSkins: resposta para '#{safe_name}' nao e um PNG valido (#{corpo.bytesize} bytes) - ficheiro local preservado.")
              AnilSkinLog.registar("'#{safe_name}' (#{tipo}) RECUSADO: #{corpo.bytesize} B, assinatura invalida (provavel perda de CR)") rescue nil
              anotar_falha(chave_falha)
              return false
            end
            Dir.mkdir("Graphics/Skins") unless Dir.exist?("Graphics/Skins")
            Dir.mkdir("Graphics/Skins/Cache") unless Dir.exist?("Graphics/Skins/Cache")
            Dir.mkdir("Graphics/Trainers") unless Dir.exist?("Graphics/Trainers")
            Dir.mkdir("Graphics/Transitions") unless Dir.exist?("Graphics/Transitions")
            File.open(local_path, "wb") { |f| f.write(corpo) }
            $anil_skin_existe = nil; $anil_resolve_cache = {}   # ver a nota no primeiro ponto de gravacao
            AnilLanRework.log("ServerSkins: Skin '#{safe_name}' salva em #{dir_path}/ com sucesso!")
            # O caminho COMPLETO no log: e a unica forma de saber se o ficheiro
            # foi parar em Graphics/Skins ou em Graphics/Skins/Cache.
            AnilSkinLog.registar("BAIXEI '#{safe_name}' (#{tipo}) -> #{local_path} (#{corpo.bytesize} B)") rescue nil
            @falhas.delete(chave_falha) if @falhas
            
            AnilLanRework.clear_specific_skin_cache(safe_name) rescue nil
            AnilLanRework.clear_char_cache rescue nil
            
            $downloaded_skins_cache ||= {}
            $downloaded_skins_cache[safe_name] = true
            
            $newly_downloaded_skins ||= {}
            $newly_downloaded_skins[safe_name] = true
            $newly_downloaded_skins[safe_name.downcase] = true
            
            return true
          end
        rescue Exception => e
          AnilLanRework.log("ServerSkins: Erro durante download da skin: #{e.message}")
        end
        false
      end

      def resgatar_codigo_skin(codigo)
        return "Codigo invalido." if codigo.to_s.strip.empty?
        return "Você precisa estar conectado ao modo online!" unless $player && !$player.online_id.empty?

        server_ip = (AnilLanRework.respond_to?(:dedicated_server_ip) ? AnilLanRework.dedicated_server_ip : "127.0.0.1")
        url = "http://#{server_ip}:7654/skins/unlock?code=#{codigo}&online_id=#{$player.online_id}"
        
        headers = {
          "Proxy-Connection" => "Close",
          "Pragma"           => "no-cache",
          "User-Agent"       => "Mozilla/5.0 (GameUpdater)"
        }

        begin
          res = HTTPLite.get(url, headers)
          if res.is_a?(Hash) && res[:status] == 200
            body_str = res[:body].to_s
            
            require "json" rescue nil
            info = nil
            if defined?(JSON)
              begin
                info = JSON.parse(body_str)
              rescue
                info = parse_unlock_via_regex(body_str)
              end
            else
              info = parse_unlock_via_regex(body_str)
            end

            if info && info["status"] == "success"
              baixar_skin_do_servidor(info["skin_name"])
              AnilLanRework.clear_char_cache rescue nil
              return { "status" => "success", "message" => info["message"], "skin_name" => info["skin_name"] }
            else
              msg = info ? info["message"] : "Erro desconhecido ao validar codigo."
              return { "status" => "error", "message" => msg }
            end
          end
        rescue Exception => e
          return { "status" => "error", "message" => "Falha na requisicao: #{e.message}" }
        end
      end

      def parse_unlock_via_regex(body_str)
        info = {}
        if body_str =~ /"status"\s*:\s*"([^"]+)"/i
          info["status"] = $1
        end
        if body_str =~ /"message"\s*:\s*"([^"]+)"/i
          info["message"] = $1
        end
        if body_str =~ /"skin_name"\s*:\s*"([^"]+)"/i
          info["skin_name"] = $1
        end
        info
      end

      # ⚠️ A skin QUE EU ESTOU A USAR tem de existir neste aparelho.
      #
      # O download de skins so era disparado de dentro do available_characters,
      # ou seja, quando o jogador ABRIA o seletor — e ainda com 3 segundos de
      # atraso. Num aparelho novo (instalar no telemovel, por exemplo) o jogo ja
      # sabia o nome da skin, porque vem no save, mas o PNG nunca chegava: o
      # jogador aparecia sem arte e ninguem lha podia pedir, porque ele proprio
      # nao a tinha.
      #
      # Sendo o dono, o /skins/download autoriza (skin_liberada? devolve true
      # para o skin_owner). So faltava pedir na altura certa: ao ligar.
      # ⚠️ "Existe" nao chega: o ficheiro tem de ser um PNG legivel.
      #
      # Publica de proposito — o seletor de personagens tambem precisa dela. La
      # a guarda era so File.exist?, e um PNG mutilado (que existe, mas nao
      # descodifica) rebenta DENTRO do carregador de imagens, fora do alcance do
      # rescue do Ruby. Era o que fechava o jogo no JoiPlay ao abrir o seletor.
      ASSINATURA_PNG = [137, 80, 78, 71, 13, 10, 26, 10].pack("C*")

      def png_valido?(caminho)
        return false unless caminho && File.exist?(caminho)
        return false unless File.size(caminho) > 8
        File.open(caminho, "rb") { |f| f.read(8) } == ASSINATURA_PNG
      rescue
        false
      end

      # ⚠️ NOME DE SKIN -> CAMINHO DE FICHEIRO: SANEAR SEMPRE.
      #
      # O File.exist? do Ruby levanta ArgumentError ("path name contains null
      # byte") quando a string tem um byte nulo, e isso NAO e um erro de I/O
      # apanhe com um rescue de Errno. No seletor de skins ele escapava e
      # derrubava o jogo no JoiPlay (ver 029, refresh_char_preview).
      #
      # Alem do byte nulo, corta separadores de caminho: um nome vindo da rede
      # com "../" atravessaria pastas ao gravar o download.
      #
      # Devolve "" para o que nao for aproveitavel — quem chama ja trata nome
      # vazio como "sem skin".
      def nome_seguro(nome)
        n = nome.to_s
        return "" if n.empty?
        # 0.chr e NAO um literal com escape. Ao remendar este ficheiro por
        # script escreveu-se aqui um byte nulo A SERIO; o `ruby -c` do PC
        # aceitou, mas o parser do JoiPlay le o 0x00 como fim de ficheiro e
        # rebentava com "SyntaxError: unexpected end-of-input" antes do jogo
        # abrir. Construir o byte em tempo de execucao nao tem esse risco.
        n = n.delete(0.chr)
        # Separadores pelo File:: em vez de escrever a barra invertida, que e
        # outra sequencia que se estraga facilmente ao passar por camadas.
        n = n.tr(File::SEPARATOR + File::ALT_SEPARATOR.to_s, "")
        n = n.gsub(/\A[.\s]+|[.\s]+\z/, "")
        return "" if n.empty? || n == "." || n == ".."
        n
      end

      def assegurar_skin_local!
        skin = nome_seguro($player && $player.respond_to?(:multiplayer_skin) ? $player.multiplayer_skin : nil)
        return false if skin.empty?
        # skin_do_jogo? vive em AnilLanRework (class << self), nao aqui no
        # ServerSkins — chamar sem o receptor rebentava com NoMethodError e o
        # metodo inteiro caia no rescue, sem baixar nada.
        return false if (AnilLanRework.skin_do_jogo?(skin) rescue false)

        # ⚠️ EXISTIR nao chega: tem de ser um PNG valido.
        #
        # A primeira versao disto perguntava so File.exist?, e isso da o mesmo
        # "sim" para um ficheiro de 0 bytes ou para um download truncado de uma
        # tentativa anterior. O jogo dizia "ja existe localmente" e mesmo assim
        # nao desenhava nada — nem no seletor nem no mapa —, porque o
        # AnimatedBitmap nao consegue abrir aquilo.
        #
        # Um PNG comeca sempre pelos mesmos 8 bytes (137 P N G CR LF 26 LF).
        # Se a assinatura nao bater, o ficheiro e lixo: apaga-se e pede-se de
        # novo.
        bom = proc do |caminho|
          valido = png_valido?(caminho)
          if File.exist?(caminho)
            AnilSkinLog.registar("#{caminho}: #{File.size(caminho) rescue "?"} B, assinatura #{valido ? "ok" : "INVALIDA"}") rescue nil
          end
          valido
        end

        # ⚠️ Os TRES ficheiros sao verificados em separado.
        #
        # A primeira versao disto devolvia logo que o boneco de andar estivesse
        # bom — e por isso o sprite do cartao de treinador e a arte VS nunca
        # eram pedidos. No jogo dava exatamente isto: o personagem andava certo
        # no mapa e continuava o padrao no cartao e na introducao de batalha.
        alvos = [
          [:walk,    "Graphics/Skins/#{skin}.png",                 "Graphics/Characters/#{skin}.png"],
          [:trainer, "Graphics/Trainers/#{skin}.png",              nil],
          [:vs,      "Graphics/Transitions/custom_vs_#{skin}.png", nil]
        ]

        baixou_algum = false
        alvos.each do |tipo, caminho, alternativo|
          next if bom.call(caminho)
          next if alternativo && bom.call(alternativo)

          # Presente mas corrompido: apagar, senao o baixar_skin_do_servidor
          # salta-o por ja existir e o lixo fica para sempre.
          if File.exist?(caminho)
            File.delete(caminho) rescue nil
            AnilSkinLog.registar("apagado '#{caminho}' (invalido) para poder rebaixar") rescue nil
          end

          # O freio pode ja ter desistido desta skin nesta sessao. Sem dizer
          # isso, o log a seguir culpava o servidor por algo que nem chegou a
          # ser pedido.
          if desistiu?("#{skin}:#{tipo}")
            AnilSkinLog.registar("nao pedi '#{caminho}': ja desisti nesta sessao (3 falhas)") rescue nil
            next
          end
          AnilSkinLog.registar("falta '#{caminho}' — a pedir ao servidor") rescue nil
          baixar_skin_do_servidor(skin, false, false, tipo)

          if bom.call(caminho)
            AnilSkinLog.registar("OK: '#{caminho}' chegou integro") rescue nil
            baixou_algum = true
          else
            # O treinador e o VS sao OPCIONAIS: a maioria das skins nao os tem,
            # e o servidor responde 404. Nao e erro, so nao ha nada para trazer.
            AnilSkinLog.registar("sem '#{caminho}': o servidor respondeu 404 ou o ficheiro veio invalido") rescue nil
          end
        end

        # ⚠️ SAIDA DE EMERGENCIA: skin que nao existe mais em lado nenhum.
        #
        # O save guarda o NOME da skin. Se ela for apagada do servidor — por
        # moderacao, por engano, ou porque foi renomeada — o jogador fica preso:
        # o nome continua no save, nao ha ficheiro para desenhar, e a cada
        # arranque tenta-se um download que devolve 404 para sempre. O
        # personagem fica invisivel e o seletor rebenta ao tentar pre-visualizar
        # o que nao existe.
        #
        # Aqui, quando o boneco de andar ja desistiu (tres falhas) e continua
        # sem ficheiro, volta-se ao visual padrao — o mesmo que o 137 faz com
        # uma skin recusada. Perde-se a aparencia; ganha-se um jogo utilizavel.
        #
        # nil, NAO string vazia: o refresh_charset testa `if multiplayer_skin`
        # e "" e verdadeiro em Ruby, o que deixaria o boneco invisivel outra vez.
        if !bom.call("Graphics/Skins/#{skin}.png") &&
           !bom.call("Graphics/Characters/#{skin}.png") &&
           desistiu?("#{skin}:walk")
          AnilSkinLog.registar("skin '#{skin}' nao existe no servidor nem aqui — a voltar ao visual padrao") rescue nil
          begin
            if $player && $player.respond_to?(:multiplayer_skin=)
              $player.multiplayer_skin = nil
              $game_player.refresh_charset if $game_player.respond_to?(:refresh_charset)
              AnilLanRework.refresh_local_follower!
              AnilLanRework::WorldSync.send_player_state
              AnilLanRework.enqueue_popup(_INTL("A skin '{1}' nao esta mais disponivel. Seu personagem voltou ao visual padrao.", skin), 8.0) rescue nil
            end
          rescue => e
            AnilSkinLog.registar("falhou o regresso ao padrao: #{e.class}: #{e.message}") rescue nil
          end
          return false
        end

        if baixou_algum
          AnilLanRework.clear_specific_skin_cache(skin) rescue nil
          AnilLanRework.clear_char_cache rescue nil
          begin
            $game_player.refresh_charset if $game_player.respond_to?(:refresh_charset)
            AnilLanRework.refresh_local_follower!
          rescue
          end
        end
        baixou_algum
      rescue => e
        AnilSkinLog.registar("erro no assegurar_skin_local!: #{e.class}: #{e.message}") rescue nil
        false
      end

      # ⚠️ ISTO E DISPARADO AO ABRIR O SELECTOR DE PERSONAGEM.
      #
      # Percorre TODAS as skins do servidor e puxa walk + treinador + VS de cada
      # uma, sem pausa. So a arte VS sao ~230 KB em base64 por skin, que ainda
      # tem de ser descodificada em memoria — e tudo isto no exacto momento em
      # que o menu esta a montar centenas de entradas. Num telemovel o sistema
      # mata o processo sem erro nenhum: e o "simplesmente fecha".
      #
      # O comentario do freio de tentativas ja registava que "abrir o seletor
      # derrubava o jogo no Android". Enquanto os downloads falhavam isso nao se
      # via; voltaram a funcionar e o sintoma voltou com eles.
      #
      # Duas travagens, sem mudar o que se descarrega:
      #   1. pausa curta entre skins, para o motor respirar;
      #   2. a arte VS fica para o fim — e a maior e a menos urgente, so faz
      #      falta ao entrar em batalha contra quem a usa.
      PAUSA_ENTRE_SKINS = 0.15 unless const_defined?(:PAUSA_ENTRE_SKINS)

      def verificar_e_baixar_skins_servidor
        Thread.new do
          begin
            sleep 3
            skins = obter_skins_desbloqueadas
            pendentes_vs = []
            unless skins.empty?
              skins.each do |skin_info|
                # Skin exclusiva de outro jogador: o servidor recusaria o
                # download de qualquer forma. Quando ela for precisa para
                # DESENHAR o dono, o SkinSync pede-a ao proprio peer.
                next if skin_info["oculta"]
                skin_name = skin_info["char_name"]
                # Skin que ja esta aqui mas mudou no servidor (o dono corrigiu o
                # tamanho, redesenhou, etc.): rebaixa por cima. Sem isto o
                # jogador ficava preso a primeira versao que recebeu, para
                # sempre, porque todos os caminhos de download saltam ficheiro
                # existente.
                if skin_local_desatualizada?(skin_name, skin_info)
                  AnilLanRework.log("ServerSkins: '#{skin_name}' mudou no servidor — atualizando a copia local.")
                  baixar_skin_do_servidor(skin_name, false, true)
                else
                  baixar_skin_do_servidor(skin_name)
                end

                # Sprite de pe: so quando o servidor diz que existe um. A maioria
                # das skins so tem o charset de andar, e nesse caso nao ha nada
                # para pedir — daí olhar o campo antes de gastar um request.
                if skin_info["trainer_hash"].to_s != ""
                  if skin_local_desatualizada?(skin_name, skin_info, :trainer)
                    AnilLanRework.log("ServerSkins: sprite de treinador de '#{skin_name}' mudou — atualizando.")
                    baixar_skin_do_servidor(skin_name, false, true, :trainer)
                  else
                    baixar_skin_do_servidor(skin_name, false, false, :trainer)
                  end
                end

                # Arte da introducao de batalha (animacao VS). Mesma logica do
                # sprite de treinador: so pede quando o servidor diz que existe.
                # Sem ela a animacao cai no sprite de corpo inteiro, que e o que
                # acontecia com TODAS as skins antes disto sincronizar.
                pendentes_vs << skin_info if skin_info["vs_hash"].to_s != ""
                sleep PAUSA_ENTRE_SKINS
              end

              # A arte VS so agora, com os bonecos todos ja no disco.
              pendentes_vs.each do |info|
                nome_vs = info["char_name"]
                if skin_local_desatualizada?(nome_vs, info, :vs)
                  AnilLanRework.log("ServerSkins: arte VS de '#{nome_vs}' mudou — atualizando.")
                  baixar_skin_do_servidor(nome_vs, false, true, :vs)
                else
                  baixar_skin_do_servidor(nome_vs, false, false, :vs)
                end
                sleep PAUSA_ENTRE_SKINS
              end
            end
          rescue Exception => e
            AnilLanRework.log("ServerSkins AutoDownloader Error: #{e.message}")
          end
        end
      end
    end
  end

  # ==============================================================================
  # Extensão de Scene_CharacterSelect movida para 029_Multiplayer_Patches.rb
  # para evitar NameError devido a ordem de carregamento dos scripts.
  # ==============================================================================

  # ==============================================================================
  # Comando de Chat /resgate e /resgatar movido para 066_Multiplayer_Chat.rb
  # para evitar NameError devido a ordem de carregamento dos scripts.
  # ==============================================================================

  # ==============================================================================
  # Monkey patches para renderização nos Mapas e Batalhas (Skins folder)
  # ==============================================================================
  class Sprite_Character < RPG::Sprite
    alias standard_refresh_graphic refresh_graphic
    def refresh_graphic
      return if @tile_id == @character.tile_id &&
                @character_name == @character.character_name &&
                @character_hue == @character.character_hue &&
                @oldbushdepth == @character.bush_depth
      @tile_id        = @character.tile_id
      @character_name = @character.character_name
      @character_hue  = @character.character_hue
      @oldbushdepth   = @character.bush_depth
      @charbitmap&.dispose
      @charbitmap = nil
      @bushbitmap&.dispose
      @bushbitmap = nil
      
      if @tile_id >= 384
        @charbitmap = pbGetTileBitmap(@character.map.tileset_name, @tile_id,
                                      @character_hue, @character.width, @character.height)
        @charbitmapAnimated = false
        @spriteoffset = false
        @cw = Game_Map::TILE_WIDTH * @character.width
        @ch = Game_Map::TILE_HEIGHT * @character.height
        self.src_rect.set(0, 0, @cw, @ch)
        self.ox = @cw / 2
        self.oy = @ch
      elsif @character_name != ""
        skin_path = "Graphics/Skins/" + @character_name
        exists_png = File.exist?(skin_path + ".png") || File.exist?(skin_path + ".PNG")
        
        # Baixa skin customizada de outro jogador em tempo real se não existir localmente
        if !@character_name.empty?
          $downloaded_skins_cache ||= {}
          if !$downloaded_skins_cache.key?(@character_name)
            exists_char = pbResolveBitmap("Graphics/Characters/" + @character_name) rescue false
            if !exists_png && !exists_char
              $downloaded_skins_cache[@character_name] = true
              Thread.new do
                begin
                  AnilLanRework::ServerSkins.baixar_skin_do_servidor(@character_name)
                  if $scene.is_a?(Scene_Map)
                    $game_map.need_refresh = true rescue nil
                  end
                rescue => e
                  AnilLanRework.log("SkinSync: Erro ao baixar skin ausente '#{@character_name}': #{e.message}")
                end
              end
            else
              $downloaded_skins_cache[@character_name] = false
            end
          end
        end

        if exists_png
          @charbitmap = AnimatedBitmap.new(skin_path + ".png", @character_hue)
          RPG::Cache.retain("Graphics/Skins/", @character_name + ".png", @character_hue) if @character == $game_player
        elsif resolved = pbResolveBitmap(skin_path)
          @charbitmap = AnimatedBitmap.new(resolved, @character_hue)
          RPG::Cache.retain("Graphics/Skins/", File.basename(resolved), @character_hue) if @character == $game_player
        else
          # ⚠️ Ultimo recurso: NUNCA deixar o jogador invisivel.
          #
          # Quando a skin nao resolve — o P2P ainda nao trouxe o PNG, o download
          # falhou, o ficheiro nao existe neste aparelho — este ramo tentava
          # Graphics/Characters/<nome>, que para uma skin custom tambem nao
          # existe. O resultado era um jogador sem sprite nenhum: invisivel.
          #
          # Um boneco errado e um incomodo; um boneco invisivel atrapalha troca,
          # batalha e coop, e ninguem percebe que ha uma skin em falta. Entao,
          # se nem o nome resolver, cai-se num charset que existe de certeza.
          alvo = "Graphics/Characters/" + @character_name
          if !(pbResolveBitmap(alvo) rescue nil)
            reserva = ["rojo2", "azul3"].find { |n| pbResolveBitmap("Graphics/Characters/" + n) rescue nil }
            if reserva
              AnilLanRework.log("SkinSync: '#{@character_name}' nao resolveu em lado nenhum; a desenhar com '#{reserva}' para nao ficar invisivel.") rescue nil
              alvo = "Graphics/Characters/" + reserva
            end
          end
          @charbitmap = AnimatedBitmap.new(alvo, @character_hue)
          RPG::Cache.retain("Graphics/Characters/", @character_name, @character_hue) if @character == $game_player
        end
        @charbitmapAnimated = true
        @spriteoffset = @character_name[/offset/i]
        @cw = @charbitmap.width / 4
        @ch = @charbitmap.height / 4
        self.ox = @cw / 2
        self.oy = @ch
      else
        self.bitmap = nil
        @cw = 0
        @ch = 0
      end
      @character.sprite_size = [@cw, @ch]
    end
  end

  class Sprite_DynamicShadows < RPG::Sprite
    alias standard_update_shadow update
    def update
      return if !@character || !@character.map
      if !@character.is_a?(Game_Event) && @character.transparent
        self.visible = false
        return
      end
      
      # Executa lógica padrão de shadow mas apontando para Graphics/Skins/ se necessário
      super
      if @tile_id != @character.tile_id ||
         @character_name != @character.character_name ||
         @character_hue != @character.character_hue
        @tile_id        = @character.tile_id
        @character_name = @character.character_name
        @character_hue  = @character.character_hue
        @chbitmap&.dispose
        
        if @tile_id >= 384
          @chbitmap = pbGetTileBitmap(@character.map.tileset_name, @tile_id, @character.character_hue)
          self.src_rect.set(0, 0, 32, 32)
          @ch = 32
          @cw = 32
          self.ox = 16
          self.oy = 32
        else
          skin_path = "Graphics/Skins/" + @character.character_name
          if File.exist?(skin_path + ".png") || File.exist?(skin_path + ".PNG")
            @chbitmap = AnimatedBitmap.new(skin_path + ".png", @character.character_hue)
          elsif resolved = pbResolveBitmap(skin_path)
            @chbitmap = AnimatedBitmap.new(resolved, @character.character_hue)
          else
            @chbitmap = AnimatedBitmap.new("Graphics/Characters/" + @character.character_name, @character.character_hue)
          end
          @cw = @chbitmap.width / 4
          @ch = @chbitmap.height / 4
          self.ox = @cw / 2
          self.oy = @ch
        end
      end
      
      this_x = @character.screen_x
      this_x = ((this_x - (Graphics.width / 2)) * TilemapRenderer::ZOOM_X) + (Graphics.width / 2) if TilemapRenderer::ZOOM_X != 1
      self.x = this_x
      this_y = @character.screen_y
      this_y = ((this_y - (Graphics.height / 2)) * TilemapRenderer::ZOOM_Y) + (Graphics.height / 2) if TilemapRenderer::ZOOM_Y != 1
      self.y = this_y - 2
      if @character.is_a?(Game_Player) || @character.is_a?(Game_Event) || @character.is_a?(Game_Follower)
        self.z = 2
      else
        self.z = @character.screen_z(@ch) - 1
      end
      self.visible = @character.transparent ? false : true
      self.opacity = 255
      if @tile_id == 0
        sx = @character.pattern * @cw
        sy = ((@character.direction - 2) / 2) * @ch
        self.src_rect.set(sx, sy, @cw, @ch)
      end
      if @character.is_a?(Game_Event) && @character.name[/regulartone/i]
        self.tone.set(0, 0, 0, 0)
      else
        pbDayNightTint(self)
      end
      if !@character.is_a?(Game_Event)
        self.color = Color.new(0, 0, 0, 80)
      elsif @character.name[/dinamicshadow/i]
        self.color = Color.new(0, 0, 0, 80)
      else
        self.visible = false
      end
    end
  end

  module GameData
    class TrainerType
      class << self
        alias skins_original_player_front_sprite_filename player_front_sprite_filename unless method_defined?(:skins_original_player_front_sprite_filename)
        alias skins_original_player_back_sprite_filename player_back_sprite_filename unless method_defined?(:skins_original_player_back_sprite_filename)

        def player_front_sprite_filename(tr_type)
          if $player && $player.respond_to?(:multiplayer_skin) && $player.multiplayer_skin && !$player.multiplayer_skin.empty?
            sprite_name = AnilLanRework.trainer_sprite_name_for_character($player.multiplayer_skin)
            unless sprite_name.empty?
              ret = "Graphics/Trainers/" + sprite_name
              return ret if pbResolveBitmap(ret)
            end
          end
          skins_original_player_front_sprite_filename(tr_type)
        end

        def player_back_sprite_filename(tr_type)
          if $player && $player.respond_to?(:multiplayer_skin) && $player.multiplayer_skin && !$player.multiplayer_skin.empty?
            sprite_name = AnilLanRework.trainer_sprite_name_for_character($player.multiplayer_skin, true)
            unless sprite_name.empty?
              ret = "Graphics/Trainers/" + sprite_name
              return ret if pbResolveBitmap(ret)
            end
          end
          skins_original_player_back_sprite_filename(tr_type)
        end
      end
    end
  end

  class Battle::Scene
    alias standard_pbCreateTrainerFrontSprite pbCreateTrainerFrontSprite
    def pbCreateTrainerFrontSprite(idxTrainer, trainerType, numTrainers = 1)
      trainer_obj = @battle.opponent[idxTrainer]
      if trainer_obj && trainer_obj.respond_to?(:multiplayer_skin) && trainer_obj.multiplayer_skin && !trainer_obj.multiplayer_skin.empty?
        sprite_name = AnilLanRework.trainer_sprite_name_for_character(trainer_obj.multiplayer_skin)
        trainerFile = "Graphics/Trainers/" + sprite_name
        if !sprite_name.empty? && pbResolveBitmap(trainerFile)
          spriteX, spriteY = Battle::Scene.pbTrainerPosition(1, idxTrainer, numTrainers)
          trainer = pbAddSprite("trainer_#{idxTrainer + 1}", spriteX, spriteY, trainerFile, @viewport)
          if trainer.bitmap
            trainer.z  = 7 + idxTrainer
            trainer.ox = trainer.src_rect.width / 2
            trainer.oy = trainer.bitmap.height
            return
          end
        end
      end
      standard_pbCreateTrainerFrontSprite(idxTrainer, trainerType, numTrainers)
    end
  end

  # ==============================================================================
  # Adiciona aliasing em obter_skins_desbloqueadas no login se o servidor estiver OK
  # ==============================================================================
  module AnilLanRework
    class << self
      alias standard_available_characters available_characters unless method_defined?(:standard_available_characters)
      
      def available_characters
        update_player_config rescue nil
        online_id_str = ($player ? $player.online_id.to_s : "") rescue ""
        log("available_characters: Iniciando busca. Player online_id = '#{online_id_str}'")
        
        if !$skins_synced && $player && !online_id_str.empty?
          $skins_synced = true
          log("available_characters: Iniciando download de skins em background...")
          ServerSkins.verificar_e_baixar_skins_servidor rescue nil
        end
        return @cached_chars if @cached_chars
        
        server_skins_map = {}
        if $player && !online_id_str.empty?
          begin
            log("available_characters: Requisitando obter_skins_desbloqueadas...")
            skins_list = ServerSkins.obter_skins_desbloqueadas
            log("available_characters: skins_list recebido: #{skins_list.inspect}")
            skins_list.each do |s|
              server_skins_map[s["char_name"].to_s.downcase] = s
            end
          rescue => e
            log("available_characters: erro ao obter skins do servidor: #{e.message}")
          end
        else
          log("available_characters: Ignorando busca no servidor (player ou online_id nulo)")
        end

        chars = []
        seen = {}
        # 1. Metadados de Jogador
        GameData::PlayerMetadata.each do |meta|
          char_name = meta.walk_charset.to_s.strip
          next if char_name.empty?
          key = char_name.downcase
          next if seen[key]
          trainer_type = meta.trainer_type
          label = ""
          begin
            label = GameData::TrainerType.get(trainer_type).real_name.to_s
          rescue
            label = ""
          end
          label = char_name if label.empty?
          label = label.gsub('POKEMONTRAINER_', '').gsub('_', ' ')
          chars << {
            "label"          => label,
            "char_name"      => char_name,
            "trainer_sprite" => trainer_sprite_name_for_character(char_name),
            "player_meta_id" => meta.id,
            "unlocked"       => true
          }
          seen[key] = true
        end
        # 2. Tipos de Treinador
        GameData::TrainerType.each do |trainer_type|
          char_name = charset_name_for_trainer_type(trainer_type.id)
          next if char_name.empty?
          key = char_name.downcase
          next if seen[key]
          label = trainer_type.real_name.to_s
          label = trainer_type.id.to_s if label.empty?
          chars << {
            "label"          => label,
            "char_name"      => char_name,
            "trainer_sprite" => trainer_sprite_name_for_character(char_name),
            "player_meta_id" => nil,
            "trainer_type"   => trainer_type.id,
            "unlocked"       => true
          }
          seen[key] = true
        end
        # 3. Pasta de Skins customizadas
        if File.directory?(SKINS_FOLDER)
          Dir.entries(SKINS_FOLDER).each do |f|
            next unless f.downcase.end_with?('.png')
            skin_name = File.basename(f, '.*')
            key = skin_name.downcase
            next if seen[key]
            
            unlocked = true
            display_name = skin_name.gsub('POKEMONTRAINER_', '').gsub('_', ' ')
            if server_skins_map.key?(key)
              # Skin de outro jogador que chegou aqui por P2P (o cliente baixa a
              # skin do peer para conseguir desenha-lo no mapa). O servidor
              # marca-a como oculta e ela nem entra na lista de escolha.
              next if server_skins_map[key]["oculta"]
              unlocked = server_skins_map[key]["unlocked"]
              # O servidor manda o rotulo PRONTO ("Ninja (de gabex)", "[VIP] X").
              # Antes isto era montado aqui e so sabia prefixar "[VIP] ", entao a
              # skin exclusiva de um jogador era anunciada como VIP paga.
              rot = server_skins_map[key]["label"].to_s
              if !rot.empty?
                display_name = rot
              elsif !unlocked
                display_name = "[VIP] " + display_name
              end
            end

            # A skin enviada por este jogador so e visivel por ele ate o painel
            # aprovar. Sem esta marca, ele escolhe-a e sai a andar convencido de
            # que os outros o veem assim (MOD 137).
            if defined?(AnilSkinAprovacao) && AnilSkinAprovacao.pendente?(skin_name)
              display_name = display_name + _INTL(" (aguardando aprovação)")
            end

            chars << {
              "label"          => display_name,
              "char_name"      => skin_name,
              "trainer_sprite" => trainer_sprite_name_for_character(skin_name),
              "player_meta_id" => nil,
              "trainer_type"   => trainer_type_for_character(skin_name, nil),
              "unlocked"       => unlocked
            }
            # ⚠️ ISTO FALTAVA, E ERA A SKIN A DUPLICAR NO SELECTOR.
            #
            # As seccoes 1 e 2 marcam o `seen` depois de acrescentar; esta nao
            # marcava. Resultado: assim que uma skin passava a existir nos DOIS
            # sitios — no disco (esta seccao) e na lista do servidor (seccao 4,
            # "skins do servidor que nao estao locais") — a seccao 4 nao a via
            # como ja listada e acrescentava uma segunda entrada.
            #
            # E por isso que so acontecia DEPOIS de enviar a skin: antes do
            # upload ela so existia no disco, e nao havia com que duplicar.
            seen[key] = true
          end
        end

        # 4. Adiciona skins do servidor que não estão locais
        server_skins_map.each do |key, s|
          next if seen[key]
          next if s["oculta"]   # exclusiva de outro jogador — nem listar
          skin_name = s["char_name"].to_s
          next if skin_name.empty?
          unlocked = s["unlocked"]
          # Mesmo criterio da seccao 3: o rotulo do servidor ja vem completo,
          # so se prefixa "[VIP] " quando ele nao veio (servidor antigo).
          display_name = s["label"].to_s
          if display_name.empty?
            display_name = skin_name.gsub('POKEMONTRAINER_', '').gsub('_', ' ')
            display_name = "[VIP] " + display_name unless unlocked
          end
          
          if defined?(AnilSkinAprovacao) && AnilSkinAprovacao.pendente?(skin_name)
            display_name = display_name + _INTL(" (aguardando aprovação)")
          end

          chars << {
            "label"          => display_name,
            "char_name"      => skin_name,
            "trainer_sprite" => trainer_sprite_name_for_character(skin_name),
            "player_meta_id" => nil,
            "trainer_type"   => trainer_type_for_character(skin_name, nil),
            "unlocked"       => unlocked
          }
          seen[key] = true
        end

        if chars.empty?
          chars = [{
            "label"          => "Treinador Padrao",
            "char_name"      => "POKEMONTRAINER_RojoNeutro",
            "trainer_sprite" => trainer_sprite_name_for_character("POKEMONTRAINER_RojoNeutro"),
            "player_meta_id" => nil,
            "trainer_type"   => trainer_type_for_character("POKEMONTRAINER_RojoNeutro", nil),
            "unlocked"       => true
          }]
        end
        @cached_chars = chars.sort_by { |c| c["label"].to_s }
      end
    end
  end

end

# ⚠️ QUEM EMPURRA E O DONO, E SO ELE E AVISADO.
#
# Uma skin por aprovar e bloqueada no relay P2P. Quem estava por perto ja pediu
# o PNG e levou com o bloqueio em silencio — e o pedido nao se repete, porque os
# dois gatilhos (mudanca do char_name do peer e primeira atribuicao do
# internal_id) disparam uma vez por sessao. Aprovava-se no painel e so quem
# reiniciasse o jogo e que passava a ver a skin.
#
# Nao ha aqui difusao nenhuma: o servidor avisa APENAS o dono, como ja fazia. O
# dono e que empurra o PNG para os peers que tem a vista. Isso e possivel porque
# o handle_data aceita um skin_data que nao foi pedido — e agora o relay deixa
# passar, ja que a skin esta aprovada.
module AnilSkinPush
  module_function

  def empurrar(nome)
    return if nome.to_s.empty?
    return unless (AnilLanRework.connected? rescue false)
    # So a propria skin: nao faz sentido empurrar a de outra pessoa.
    return unless (AnilSkinAprovacao.skin_em_uso rescue "") == nome.to_s

    enviados = 0
    (AnilLanRework.players rescue {}).each do |id, _pl|
      next if id.to_s.empty?
      next if id.to_s == (AnilLanRework.self_internal_id.to_s rescue "")
      AnilLanRework::SkinSync.handle_request({ "skin" => nome.to_s, "sender_id" => id.to_s }) rescue nil
      enviados += 1
    end
    AnilSkinLog.registar("APROVADA '#{nome}': empurrada para #{enviados} peer(s)") rescue nil
  rescue => e
    AnilLanRework.log("AnilSkinPush: #{e.class}: #{e.message}") rescue nil
  end
end

class Scene_Map
  unless method_defined?(:anil_skins_orig_update_tique)
    alias anil_skins_orig_update_tique update
    def update
      anil_skins_orig_update_tique
      AnilLanRework::SkinSync.tique_periodico rescue nil
    end
  end
end
