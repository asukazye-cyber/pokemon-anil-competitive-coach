#===============================================================================
# MOD: 066_Multiplayer_Chat.rb
#-------------------------------------------------------------------------------
# Chat Online ( MMO Speech Bubbles and Network Messages )
#===============================================================================

# 1. Propriedades nos personagens e nos RemotePeers
class Game_Character
  attr_accessor :chat_bubble_text
  attr_accessor :chat_bubble_time
end

class AnilLanRework::RemotePeer
  attr_accessor :chat_bubble_text
  attr_accessor :chat_bubble_time
end

module AnilLanRework
  # Nome do parceiro de co-op atual (usado pelo canal de GRUPO do chat), ou nil.
  def self.chat_partner_name
    pid = (AnilLanRework.respond_to?(:coop_party_partner_id) ? AnilLanRework.coop_party_partner_id : nil)
    return nil if pid.nil? || pid.to_s.empty?
    peer = (AnilLanRework.players[pid.to_s] rescue nil)
    return nil unless peer
    nm = (peer.name.to_s rescue "")
    nm.empty? ? nil : nm
  end

  module Chat
    def self.send_message(text)
      return if text.to_s.strip.empty?
      clean_text = text.to_s.strip

      if ["/mover", "/destravar", "/unstuck", "/desprender"].include?(clean_text.downcase)
        begin
          healing = $PokemonGlobal.healingSpot
          if healing
            map_id = healing[0]
            x = healing[1]
            y = healing[2]
          else
            map_id = 2
            x = 28
            y = 35
          end

          pbPlayDecisionSE() rescue nil
          if defined?(AnilLanRework) && AnilLanRework.respond_to?(:add_popup)
            AnilLanRework.add_popup(_INTL("Você foi desprendido!"), 5.0)
          else
            pbMessage(_INTL("Você foi desprendido!"))
          end

          AnilLanRework.perform_unstuck_transfer(map_id, x, y, 2)
        rescue => e
          AnilLanRework.log("unstuck command error: #{e.class}: #{e.message}") rescue nil
        end
        return
      end

      if clean_text =~ %r{\A/(resgatar|resgate)\s+(\S+)\z}i
        codigo = $2.to_s.strip
        Thread.new do
          begin
            res = AnilLanRework::ServerSkins.resgatar_codigo_skin(codigo)
            if res.is_a?(Hash) && res["status"] == "success"
              AnilLanRework.add_popup("[Sistema] #{res['message']}", 8.0) rescue nil
            else
              msg = res.is_a?(Hash) ? res["message"] : (res || "Erro ao tentar resgatar código.")
              AnilLanRework.add_popup("[Sistema] #{msg}", 8.0) rescue nil
            end
          rescue => e
            AnilLanRework.add_popup("[Sistema] Erro de conexao.", 8.0) rescue nil
          end
        end
        return
      end

      # ─── CANAIS (toggle) do Rework de Chat ──────────────────────────────────
      # $active_chat_channel pode ser: :global | :local | :group | [:whisper, "Nome"]
      low = clean_text.downcase

      if ["/global", "/g"].include?(low)
        $active_chat_channel = :global
        AnilLanRework.add_corner_popup("[Sistema] Canal ativo: GLOBAL (todos os jogadores).", 8.0) rescue nil
        return
      end

      if ["/local", "/l"].include?(low)
        $active_chat_channel = :local
        AnilLanRework.add_corner_popup("[Sistema] Canal ativo: LOCAL (mesmo mapa).", 8.0) rescue nil
        return
      end

      if ["/grupo", "/grp", "/party"].include?(low)
        $active_chat_channel = :group
        pname = AnilLanRework.chat_partner_name
        if pname
          AnilLanRework.add_corner_popup("[Sistema] Canal ativo: GRUPO (com #{pname}).", 8.0) rescue nil
        else
          AnilLanRework.add_corner_popup("[Sistema] Canal ativo: GRUPO. (Você ainda não está em um grupo de co-op.)", 8.0) rescue nil
        end
        return
      end

      # Sussurro one-shot clássico (compatibilidade): /w nome msg
      if clean_text =~ %r{\A/(w|pm|msg)\s+(\S+)\s+(.+)\z}i
        target_name = $2.to_s.strip
        msg_text = $3.to_s.strip
        return unless AnilLanRework.connected?
        AnilLanRework.connection.send_packet("private_message", {
          "target_name" => target_name,
          "text"        => msg_text,
          "sender_name" => AnilLanRework.self_name
        })
        AnilLanRework.add_corner_popup("[Para #{target_name}]: #{msg_text}", 10.0) rescue nil
        return
      end

      # /Nome [mensagem] → TOGGLE de sussurro. "/joao" passa a falar sempre com o João;
      # "/joao oi" ativa o canal E já manda "oi" (até trocar de canal).
      if clean_text.start_with?("/")
        m = clean_text.match(%r{\A/(\S+)(?:\s+(.+))?\z}m)
        # "clima" esta aqui como rede: o comando e tratado pelo MOD 143, que
        # embrulha este send_message. Se esse embrulho falhar ou for substituido,
        # sem esta linha o "/clima" caia no toggle de sussurro abaixo e passava a
        # falar com um jogador chamado "clima" — foi o que aconteceu em teste.
        reserved = %w[global g local l grupo grp party w pm msg resgatar resgate clima rank chatdebug caverna arenalog movlog horda anim]
        if m && !reserved.include?(m[1].downcase)
          target_name = m[1].to_s.strip
          $active_chat_channel = [:whisper, target_name]
          AnilLanRework.add_corner_popup("[Sistema] Canal ativo: SUSSURRO para #{target_name}.", 8.0) rescue nil
          extra = m[2].to_s.strip
          if !extra.empty? && AnilLanRework.connected?
            AnilLanRework.connection.send_packet("private_message", {
              "target_name" => target_name,
              "text"        => extra,
              "sender_name" => AnilLanRework.self_name
            })
            AnilLanRework.add_corner_popup("[Para #{target_name}]: #{extra}", 10.0) rescue nil
          end
        else
          AnilLanRework.add_corner_popup("[Sistema] Comando desconhecido. Use /global, /local, /grupo ou /nome [msg].", 8.0) rescue nil
        end
        return
      end

      return unless AnilLanRework.connected?
      
      $active_chat_channel ||= :local
      if $active_chat_channel == :global
        # Balão na cabeça do próprio jogador (global é para todos os que o veem).
        pbSpeechBubble(clean_text, 0, 4.0) rescue nil
        AnilLanRework.add_corner_popup("[Global] #{AnilLanRework.self_name}: #{clean_text}", 10.0) rescue nil
        AnilLanRework.connection.send_packet("global_chat_message", {
          "text"        => clean_text,
          "sender_name" => AnilLanRework.self_name
        })
      elsif $active_chat_channel == :group
        pname = AnilLanRework.chat_partner_name
        if pname
          # Balão na cabeça do próprio jogador; a entrega ao balão do parceiro é
          # feita no on_receive_private_message (só quem é do grupo recebe).
          pbSpeechBubble(clean_text, 0, 4.0) rescue nil
          AnilLanRework.connection.send_packet("private_message", {
            "target_name" => pname,
            "text"        => clean_text,
            "sender_name" => AnilLanRework.self_name
          })
          AnilLanRework.add_corner_popup("[Grupo] #{AnilLanRework.self_name}: #{clean_text}", 10.0) rescue nil
        else
          AnilLanRework.add_corner_popup("[Sistema] Você não está em um grupo de co-op. Use /local ou /global.", 8.0) rescue nil
        end

      elsif $active_chat_channel.is_a?(Array) && $active_chat_channel[0] == :whisper
        wname = $active_chat_channel[1].to_s
        AnilLanRework.connection.send_packet("private_message", {
          "target_name" => wname,
          "text"        => clean_text,
          "sender_name" => AnilLanRework.self_name
        })
        AnilLanRework.add_corner_popup("[Para #{wname}]: #{clean_text}", 10.0) rescue nil

      else
        # Exibe na cabeça do próprio jogador local com o novo sistema 9-slice!
        pbSpeechBubble(clean_text, 0, 4.0) rescue nil
        
        # Exibe localmente no popup estético (duração: 10.0s)
        AnilLanRework.add_corner_popup("#{AnilLanRework.self_name}: #{clean_text}", 10.0) rescue nil
        
        # Envia para o servidor que redistribuirá (com coordenadas para otimização de AOI)
        AnilLanRework.connection.send_packet("chat_message", {
          "text"        => clean_text,
          "sender_name" => AnilLanRework.self_name,
          "map_id"      => ($game_map ? $game_map.map_id : -1),
          "x"           => ($game_player ? $game_player.x : 0),
          "y"           => ($game_player ? $game_player.y : 0)
        })
      end
    end

    def self.on_receive_chat(packet)
      sender_id = packet["sender_id"].to_s
      text = packet["text"].to_s
      sender_name = packet["sender_name"].to_s
      sender_name = packet["name"].to_s if sender_name.empty?
      return if sender_id.empty? || text.empty?
      
      peer = AnilLanRework.players[sender_id]
      return unless peer && peer.map_id == $game_map.map_id
      
      dx = (peer.x - $game_player.x).abs
      dy = (peer.y - $game_player.y).abs
      return if [dx, dy].max > AnilLanRework::REMOTE_SPAWN_AUTHORITY_DISTANCE
      
      display_name = peer.name.empty? ? (sender_name.empty? ? "Jogador" : sender_name) : peer.name
      
      # Exibe na cabeça do jogador remoto com o novo sistema 9-slice!
      pbSpeechBubble(text, sender_id, 4.0) rescue nil
      
      # Mostra pop-up estético (duração: 10.0s)
      AnilLanRework.add_corner_popup("#{display_name}: #{text}", 10.0) rescue nil
    end

    def self.on_receive_global_chat(packet)
      sender_id = packet["sender_id"].to_s
      text = packet["text"].to_s
      sender_name = packet["sender_name"].to_s
      sender_name = packet["name"].to_s if sender_name.empty?
      return if text.empty?
      return if sender_id == AnilLanRework.self_internal_id

      # Balão na cabeça do remetente, se ele estiver visível no mesmo mapa/AOI.
      peer = AnilLanRework.players[sender_id]
      if peer && $game_map && peer.map_id == $game_map.map_id
        dx = (peer.x - $game_player.x).abs
        dy = (peer.y - $game_player.y).abs
        pbSpeechBubble(text, sender_id, 4.0) rescue nil if [dx, dy].max <= AnilLanRework::REMOTE_SPAWN_AUTHORITY_DISTANCE
      end

      AnilLanRework.add_corner_popup("[Global] #{sender_name}: #{text}", 10.0) rescue nil
    end

    def self.on_receive_private_message(packet)
      sender_id = packet["sender_id"].to_s
      text = packet["text"].to_s
      sender_name = packet["sender_name"].to_s
      sender_name = packet["name"].to_s if sender_name.empty?
      return if text.empty?

      pbPlayDecisionSE() rescue nil

      # O /grupo envia via private_message APENAS ao parceiro. Se o remetente é o
      # meu parceiro de grupo, trato como GRUPO (balão + rótulo [Grupo]); assim o
      # balão chega só a quem está no grupo, sem precisar de mudança no servidor.
      partner_id = (AnilLanRework.respond_to?(:coop_party_partner_id) ? AnilLanRework.coop_party_partner_id.to_s : "")
      if !partner_id.empty? && sender_id == partner_id
        peer = AnilLanRework.players[sender_id]
        if peer && $game_map && peer.map_id == $game_map.map_id
          dx = (peer.x - $game_player.x).abs
          dy = (peer.y - $game_player.y).abs
          pbSpeechBubble(text, sender_id, 4.0) rescue nil if [dx, dy].max <= AnilLanRework::REMOTE_SPAWN_AUTHORITY_DISTANCE
        end
        AnilLanRework.add_corner_popup("[Grupo] #{sender_name}: #{text}", 10.0) rescue nil
      else
        AnilLanRework.add_corner_popup("[De: #{sender_name}]: #{text}", 12.0) rescue nil
      end
    end

    def self.on_receive_chat_error(packet)
      text = packet["text"].to_s
      return if text.empty?
      AnilLanRework.add_corner_popup("[Sistema]: #{text}", 8.0) rescue nil
    end
  end

  module ChatInputHUD
    @window = nil
    @viewport = nil
    @active = false
    @bg_sprite = nil

    def self.active?
      @active == true
    end

    # O bloqueio de input do jogo estende-se por alguns frames APÓS o fechamento.
    # O Enter que envia a mensagem também é o Input::USE do jogo; sem essa janela
    # de carência ele "vaza" no mesmo frame do fechamento e interage com o NPC.
    # ⚠️ A CARENCIA TEM DE SER IMUNE AO frame_count ANDAR PARA TRAS.
    #
    # O `Graphics.frame_count` vai DENTRO do save e e reposto ao carregar:
    #
    #     load_value { |value| Graphics.frame_count = value }   (0032_Game_SaveValues)
    #
    # Fechar o chat marcava `@input_block_until = frame_count + 3`. Se o contador
    # recuasse a seguir — carregar um save mais antigo, uma reposicao, uma
    # reconexao que recarrega o save — esse alvo ficava num futuro que podia
    # demorar HORAS a chegar. E enquanto ele nao chegasse, o Scene_Map fazia
    #
    #     return if ChatInputHUD.input_blocked?
    #
    # antes de ler o X, o Z e as interaccoes. O jogador ficava sem menu e sem
    # conseguir falar com ninguem, sem nada no ecra a explicar. O F7 continuava
    # a funcionar porque e lido noutro sitio — foi essa a pista.
    #
    # Duas defesas, e ambas simples:
    #   1. se o contador estiver ANTES da marca por mais do que a carencia,
    #      ele recuou: a marca nao presta e deita-se fora;
    #   2. tecto absoluto, para nenhum valor estranho poder prender o jogo.
    CARENCIA_FRAMES = 3
    def self.input_blocked?
      return true if @active == true
      alvo = @input_block_until.to_i
      return false if alvo <= 0
      agora = (Graphics.frame_count rescue 0)
      # O contador recuou (save carregado, reposicao): a marca ficou invalida.
      if agora < alvo - (CARENCIA_FRAMES * 10)
        @input_block_until = 0
        return false
      end
      agora < alvo
    rescue
      false
    end

    def self.open
      return if @active
      return unless AnilLanRework.connected?
      
      @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
      @viewport.z = 99999
      
      width = 400
      height = 100
      x = (Graphics.width - width) / 2
      
      # Verifica se está rodando no Joiplay ou Android
      is_joiplay = defined?($joiplay) && $joiplay
      is_joiplay ||= ENV['ANDROID_ROOT'] || ENV['ANDROID_DATA'] rescue false
      y = is_joiplay ? 80 : 150
      
      # Sprite de fundo branco para contraste
      @bg_sprite = Sprite.new(@viewport)
      @bg_sprite.bitmap = Bitmap.new(width, height)
      @bg_sprite.bitmap.fill_rect(0, 0, width, height, Color.new(255, 255, 255))
      @bg_sprite.x = x
      @bg_sprite.y = y
      @bg_sprite.z = 99998
      
      @window = Window_TextEntry_Keyboard.new("", x, y, width, height, _INTL("Bate-papo (Enter enviar, Esc sair):"), true)
      @window.viewport = @viewport
      @window.z = 99999
      @window.back_opacity = 0 # Fundo transparente para revelar o bg_sprite branco
      @window.active = true
      
      Input.text_input = true rescue nil
      @active = true
      @open_frame = Graphics.frame_count
    end

    def self.close
      return unless @active
      @active = false
      # Mantém os botões de ação suprimidos por alguns frames para que o Enter
      # de envio (== Input::USE) não dispare interação logo após fechar o chat.
      @input_block_until = (Graphics.frame_count rescue 0) + CARENCIA_FRAMES
      Input.text_input = false rescue nil
      @window.dispose if @window rescue nil
      @window = nil
      @bg_sprite.bitmap.dispose rescue nil if @bg_sprite && @bg_sprite.bitmap
      @bg_sprite.dispose rescue nil if @bg_sprite
      @bg_sprite = nil
      @viewport.dispose if @viewport rescue nil
      @viewport = nil
    end

    def self.update
      return unless @active
      @window.update if @window
      
      # Cooldown de frames para ignorar o trigger de abertura
      return if Graphics.frame_count - @open_frame < 3
      
      if (Input.triggerex?(:ESCAPE) rescue false)
        pbPlayCancelSE() rescue nil
        close
      elsif (Input.triggerex?(:RETURN) rescue false)
        text = @window.text.to_s.strip
        close
        if !text.empty?
          AnilLanRework::Chat.send_message(text)
        end
        pbPlayDecisionSE() rescue nil
      end
    end
  end
end

class Game_Player
  # Enquanto o chat captura texto (ou na carência pós-fechamento), as direcionais
  # não podem mover o personagem. O movimento por direcional vem de
  # update_command_new (via Input.dir4). Gateamos SÓ ele — deixando o update
  # normal do Game_Player rodar — para que a câmera continue centralizada e a
  # animação/seguidores funcionem (o override antigo fazia `super; return`, que
  # pulava o update_screen_position e fazia o personagem "sair pela tela").
  alias anil_chat_ucn update_command_new unless method_defined?(:anil_chat_ucn)
  def update_command_new
    return if defined?(AnilLanRework::ChatInputHUD) && AnilLanRework::ChatInputHUD.input_blocked?
    anil_chat_ucn
  end
end

# 2. Interceptador de pacotes no Roteador Multiplayer
module AnilLanRework
  module Router
    class << self
      alias anil_chat_route_packet route_packet unless method_defined?(:anil_chat_route_packet)

      def route_packet(packet)
        packet_type = packet["type"].to_s
        if packet_type == "chat_message"
          AnilLanRework::Chat.on_receive_chat(packet) rescue nil
          return
        elsif packet_type == "global_chat_message"
          AnilLanRework::Chat.on_receive_global_chat(packet) rescue nil
          return
        elsif packet_type == "private_message"
          AnilLanRework::Chat.on_receive_private_message(packet) rescue nil
          return
        elsif packet_type == "chat_error"
          AnilLanRework::Chat.on_receive_chat_error(packet) rescue nil
          return
        elsif packet_type == "announcement"
          text = packet["text"].to_s
          AnilLanRework.add_popup(text, 12.0) rescue nil
          return
        elsif packet_type == "gift_box_open_broadcast"
          if defined?(GiftBoxSystem) && GiftBoxSystem.respond_to?(:on_receive_gift_box_open)
            GiftBoxSystem.on_receive_gift_box_open(packet) rescue nil
          end
          return
        end
        anil_chat_route_packet(packet)
      end
    end
  end
end

# 3. Desenho estético do Chat Bubble acima da cabeça dos jogadores
if defined?(Sprite_Character)
  class Sprite_Character < RPG::Sprite
    alias anil_chat_bubble_update update unless method_defined?(:anil_chat_bubble_update)
    alias anil_chat_bubble_dispose dispose unless method_defined?(:anil_chat_bubble_dispose)

    def dispose
      @chat_bubble_sprite&.bitmap&.dispose rescue nil
      @chat_bubble_sprite&.dispose rescue nil
      @chat_bubble_sprite = nil
      anil_chat_bubble_dispose
    end

    def update
      anil_chat_bubble_update
      # Chat bubbles disabled by user request.
    end
  end
end

# ─────────────────────────────────────────────────────────────────────────────
# FIX — Backspace no teclado virtual do Joiplay/Android.
#
# O update original só apaga via Input.triggerex?(:BACKSPACE)/repeatex?, ou seja,
# depende do scancode físico de backspace. No teclado virtual do Joiplay esse
# scancode não chega: o apagar vem como caractere de controle (\b = 0x08 ou
# DEL = 0x7F) dentro do fluxo de texto do Input.gets. Aqui reimplementamos o
# update preservando 100% do comportamento original e, no caminho do Input.gets,
# convertendo \b/DEL em "apagar" em vez de inserir lixo.
# ─────────────────────────────────────────────────────────────────────────────
# ───────────────────────────────────────────────────────────────────────────────
# O BOTÃO DE APAGAR, TOCÁVEL
#
# ⚠️ POR QUE É QUE NÃO SE CONSEGUE LER O BACKSPACE DO ANDROID.
#
# O teclado do sistema (Gboard e afins) trata o apagar DENTRO do IME: ele edita
# o buffer dele e não emite carácter nenhum para o jogo. Não é um evento que
# chegue mal — é um evento que não chega. Nenhuma leitura do Input.gets, por
# mais esperta que fosse, podia inventar o que não foi enviado.
#
# O botão B do gamepad virtual resolve, mas só quem sabe é que o usa, e ninguém
# adivinha que o B apaga.
#
# ⚠️ ENTÃO A SAÍDA É NÃO PASSAR PELO TECLADO DE TODO.
#
# Um botão desenhado no ecrã e tocado com o dedo não é um evento de teclado —
# é um toque. Não há IME no meio para o engolir, e funciona em qualquer
# teclado, incluindo os que ainda nem existem.
#
# Fica ao lado do campo de texto e ACIMA dele, porque o teclado do sistema sobe
# do fundo do ecrã e taparia qualquer coisa colocada por baixo.
# ───────────────────────────────────────────────────────────────────────────────
module AnilBotaoApagar
  ACTIVO = true

  # ⚠️ TEXTO, E NAO SIMBOLO. A SEGUNDA TENTATIVA FOI PIOR.
  #
  # Houve uma versao com um quadrado de 30px e o simbolo do backspace desenhado
  # a mao. Em jogo ficou pequeno e ilegivel — num telemovel, um alvo de trinta
  # pixeis a competir com o teclado do sistema nao se acerta nem se percebe.
  #
  # "APAGAR" ocupa mais espaco e resolve as duas coisas: le-se sem duvida e da
  # um alvo grande para o dedo. Num botao que so aparece dentro do chat, o
  # espaco nao esta em falta.
  LARGURA = 70
  ALTURA  = 30
  TEXTO   = "APAGAR"

  # A partir do canto superior direito da caixa: por cima dela, encostado a
  # direita. Fica fora do caminho do texto e longe do teclado, que sobe do
  # fundo do ecra.
  DESVIO_X = 0
  DESVIO_Y = -34

  module_function

  def bitmap
    return @bitmap if @bitmap && !(@bitmap.disposed? rescue true)
    b = Bitmap.new(LARGURA, ALTURA)
    b.fill_rect(0, 0, LARGURA, ALTURA, Color.new(0, 0, 0, 180))
    b.fill_rect(1, 1, LARGURA - 2, ALTURA - 2, Color.new(52, 56, 68, 235))
    b.font.name = (Font.default_name rescue b.font.name)
    b.font.size = 15
    b.font.color = Color.new(240, 244, 252)
    b.draw_text(0, 0, LARGURA, ALTURA, TEXTO, 1)
    @bitmap = b
  rescue
    @bitmap = nil
  end

  # ⚠️ O BOTAO TEM DE MORRER COM A JANELA. FOI ASSIM QUE ELE FOI PARAR AO TITULO.
  #
  # A primeira versao criava o sprite quando a janela estava activa e escondia-o
  # quando deixava de estar. Mas se a janela e DESTRUIDA enquanto activa — que e
  # o que acontece ao fechar o chat, ou ao mudar de cena — o `update` deixa de
  # correr e nao ha ninguem para o esconder. O sprite ficava vivo no viewport,
  # orfao, e aparecia por cima de tudo o que viesse a seguir. No ecra de titulo,
  # por exemplo.
  #
  # Sao precisas as duas metades: o enxerto no `dispose` (mais abaixo) e esta
  # verificacao, que refaz o sprite se a janela mudou ou se o viewport dele
  # morreu por baixo — que e o que fazia o botao "parar de funcionar" no Joiplay
  # depois de fechar e reabrir o chat.
  def mostrar!(janela)
    return unless ACTIVO && janela
    return esconder! if (janela.disposed? rescue true)
    bm = bitmap
    return unless bm

    vp = (janela.viewport rescue nil)
    # ⚠️ O viewport pode MORRER mantendo a mesma referencia.
    #
    # O teste antigo era `@viewport.equal?(vp)` — compara a identidade, e uma
    # identidade continua igual depois de o objecto ser destruido. Um sprite
    # dentro de um viewport morto nao se desenha e, pior, o calculo do alvo em
    # `dentro?` cai para offset 0: o botao ou some ou fica com a area de toque
    # noutro sitio. E exactamente o sintoma de "apagava e de repente parou".
    vp = nil if vp && (vp.disposed? rescue true)
    morto  = @sprite.nil? || (@sprite.disposed? rescue true)
    morto ||= begin
      svp = @sprite.viewport
      !svp.nil? && (svp.disposed? rescue true)
    rescue
      true
    end
    trocou = (!morto && (!@janela.equal?(janela) || !@viewport.equal?(vp)))
    if morto || trocou
      AnilChatDiag.registar_evento("botao recriado (morto=#{morto} trocou=#{trocou})") rescue nil
      (@sprite.dispose rescue nil) if @sprite
      @sprite = Sprite.new(vp)
      @sprite.bitmap = bm
      @viewport = vp
    end

    @sprite.x = (janela.x + janela.width - LARGURA + DESVIO_X)
    @sprite.y = (janela.y + DESVIO_Y)
    @sprite.z = (janela.z rescue 0) + 10
    @sprite.visible = true
    @janela = janela
  rescue
    esconder!
  end

  def esconder!
    largar_estado!
    (@sprite.dispose rescue nil) if @sprite
    @sprite = nil
    @janela = nil
    @viewport = nil
  rescue
    @sprite = nil
  end

  # So larga se o botao for MESMO daquela janela: duas caixas de texto ao mesmo
  # tempo (o chat e um pedido de nome, por exemplo) nao se podem desligar uma a
  # outra.
  def largar_se_for_de(janela)
    esconder! if @janela && janela && @janela.equal?(janela)
  rescue
    esconder!
  end

  # ⚠️ O toque vem em coordenadas do ECRÃ; o sprite vive num viewport.
  #
  # Sem somar a origem do viewport, o alvo fica deslocado — e no Android, com a
  # imagem escalada, o desvio é grande o suficiente para o botão nunca acertar.
  # O Mouse.getMousePos já devolve a posição corrigida pela calibração.
  # ⚠️ MEDIDO NO APARELHO: O TECLADO DO ANDROID NAO DA PARA REPETIR.
  #
  # O diagnostico de 02/09 mostrou o apagar do teclado a chegar assim:
  #
  #     75.959  BACKSPACE inicio (pressex=true trigger=true)
  #     97.334  BACKSPACE inicio (pressex=true trigger=true)
  #    105.080  BACKSPACE inicio (pressex=true trigger=true)
  #
  # SO linhas de "inicio", nunca uma repeticao — ou seja, no frame seguinte o
  # pressex? ja era falso. O IME deixa passar um PULSO de um frame, avulso, de
  # segundos a segundos. Nao ha estado de "tecla premida" nenhum sobre o qual
  # construir repeticao: nao da para saber que o dedo continua em cima.
  #
  # O toque no ecra da. Um toque reporta estado enquanto o dedo la esta, e por
  # isso e AQUI que a repeticao se faz — no caminho que o aparelho realmente
  # suporta, em vez de insistir no que ele nao manda.
  ATRASO   = 0.35   # segurar isto antes de comecar a repetir
  CADENCIA = 0.05   # depois, 20 letras por segundo

  # Onde o botao esta, em coordenadas de ECRA. Separado do teste para o
  # diagnostico poder dizer "o dedo estava aqui, o botao estava ali".
  def caixa_do_botao
    return nil unless @sprite && !(@sprite.disposed? rescue true)
    vp = (@sprite.viewport rescue nil)
    vivo = vp && !(vp.disposed? rescue true)
    vx = vivo ? (vp.rect.x - vp.ox) : 0
    vy = vivo ? (vp.rect.y - vp.oy) : 0
    [@sprite.x + vx, @sprite.y + vy, LARGURA, ALTURA, vivo ? "vp" : "sem vp"]
  rescue
    nil
  end

  def dentro?(pos)
    c = caixa_do_botao
    return false unless pos && c
    pos[0] >= c[0] && pos[0] < c[0] + c[2] &&
      pos[1] >= c[1] && pos[1] < c[1] + c[3]
  end

  # Devolve true nos frames em que se deve apagar uma letra: uma vez ao tocar,
  # e depois em cadencia enquanto o dedo nao sair de cima do botao.
  def tocado?
    unless ACTIVO && @sprite && !(@sprite.disposed? rescue true)
      AnilChatDiag.registar_evento("botao SEM SPRITE (activo=#{ACTIVO} sprite=#{!@sprite.nil?})") rescue nil
      @desde = nil
      return false
    end
    pos      = (Mouse.getMousePos rescue nil)
    # ⚠️ Os dois: press? para segurar, trigger? como rede.
    #
    # Normalmente o trigger? e um subconjunto do press?, mas se num aparelho o
    # estado de "premido" nao for reportado de forma fiavel, o toque simples
    # ainda passa pelo trigger?. Custa nada e tira um modo de falha em que o
    # botao simplesmente nao reage.
    premido  = (Input.press?(Input::MOUSELEFT) rescue false) ||
               (Input.trigger?(Input::MOUSELEFT) rescue false)
    em_cima  = premido && dentro?(pos)

    # ⚠️ So se regista quando ha dedo em baixo: sem isto seriam 60 linhas por
    # segundo. Assim o ficheiro so cresce quando alguem carrega e nada acontece,
    # que e precisamente o caso a investigar.
    if premido && !em_cima
      AnilChatDiag.registar_evento(
        "toque FORA do botao: dedo=#{pos.inspect} "         "botao=#{caixa_do_botao.inspect}") rescue nil
    end

    unless em_cima
      @desde = nil
      return false
    end

    agora = (System.uptime rescue 0.0)
    if @desde.nil?
      @desde  = agora
      @ultimo = agora
      return true
    end
    if (agora - @desde) >= ATRASO && (agora - @ultimo) >= CADENCIA
      @ultimo = agora
      return true
    end
    false
  rescue
    false
  end

  # O botao desaparece com o chat; o estado de "a segurar" tem de ir com ele,
  # senao o primeiro toque da vez seguinte era lido como continuacao.
  def largar_estado!
    @desde = nil
    @ultimo = nil
  end
end

if defined?(Window_TextEntry_Keyboard)
  class Window_TextEntry_Keyboard
    # ⚠️ A OUTRA METADE DO CICLO DE VIDA (ver AnilBotaoApagar).
    #
    # Fechar o chat destroi a janela sem passar pelo `update`. Sem isto, o
    # sprite do botao sobrevivia a cena e aparecia por cima do que viesse a
    # seguir — foi assim que ele foi parar ao ecra de titulo.
    unless method_defined?(:anil_botao_orig_dispose)
      alias_method :anil_botao_orig_dispose, :dispose
      def dispose
        (AnilBotaoApagar.largar_se_for_de(self) rescue nil)
        anil_botao_orig_dispose
      end
    end

    def update
      cursor_to_show = ((System.uptime - @cursor_timer_start) / 0.35).to_i.even?
      if cursor_to_show != @cursor_shown
        @cursor_shown = cursor_to_show
        refresh
      end
      unless self.active
        AnilBotaoApagar.esconder! rescue nil
        return
      end

      # O botao segue o campo: se a janela mudar de sitio, ele vai atras.
      (AnilBotaoApagar.mostrar!(self) rescue nil)
      if (AnilBotaoApagar.tocado? rescue false)
        AnilChatDiag.registar_evento("apagar pelo botao")
        apagar_uma_letra
        return
      end
      # Mover cursor / apagar via tecla física (desktop) — inalterado
      if Input.triggerex?(:LEFT) || Input.repeatex?(:LEFT)
        if @helper.cursor > 0
          @helper.cursor -= 1
          @cursor_timer_start = System.uptime
          @cursor_shown = true
          self.refresh
        end
        return
      elsif Input.triggerex?(:RIGHT) || Input.repeatex?(:RIGHT)
        if @helper.cursor < self.text.scan(/./m).length
          @helper.cursor += 1
          @cursor_timer_start = System.uptime
          @cursor_shown = true
          self.refresh
        end
        return
      elsif (apagar_por_tecla? rescue false)
        return
      elsif (Input.triggerex?(:RETURN) || Input.triggerex?(:ESCAPE)) && (!Input.triggerex?(0x30) || !Input.repeatex?(0x30))
        return
      end
      # ─────────────────────────────────────────────────────────────────────
      # APAGAR PELO BOTÃO B (gamepad virtual do Joiplay).
      #
      # ⚠️ Isto existe porque o teclado do ANDROID não avisa que apagou.
      #
      # O tratamento de \b/DEL abaixo cobre o teclado do próprio Joiplay, que
      # manda o caractere de controle no fluxo do Input.gets. Já o teclado do
      # sistema (Gboard e afins) trata o apagar dentro do IME: ele edita o
      # buffer dele e NÃO emite caractere nenhum para o jogo. Do lado daqui não
      # chega evento algum — não há o que interpretar, e por isso nenhuma
      # correção no Input.gets podia resolver esse caso.
      #
      # O botão B do gamepad virtual não passa pelo IME, então funciona em
      # qualquer teclado. Com texto escrito ele apaga; com o campo vazio volta
      # ao comportamento normal de cancelar, para não prender o jogador dentro
      # do chat.
      # ─────────────────────────────────────────────────────────────────────
      if Input.triggerex?(Input::BACK) || Input.repeatex?(Input::BACK)
        AnilChatDiag.registar_evento("botao B (gamepad)")
        if @helper.cursor > 0
          apagar_uma_letra
          return
        end
      end

      # Caminho do teclado virtual (Joiplay/Android): texto chega via Input.gets.
      # \b (0x08) e DEL (0x7F) são convertidos em apagar; o resto é inserido.
      typed = (Input.gets rescue nil)
      return if typed.nil? || typed.empty?

      AnilChatDiag.registrar(typed)

      typed.each_char do |c|
        code = (c.ord rescue 0)
        if code == 8 || code == 127
          AnilChatDiag.registar_evento("apagar pelo gets (codigo #{code})")
          apagar_uma_letra
        else
          insert(c)
        end
      end
    end

      # ⚠️ O APAGAR DO TECLADO DO ANDROID NAO REPETE — E NAO DA PARA FINGIR.
      #
      # Medido no aparelho em 02/09. Intervalos entre pulsos, em segundos:
      #
      #     21,38   7,75   1,16   22,12   3,85   5,04
      #
      # Um auto-repeat de teclado seria regular e na casa dos 0,05-0,10s. Isto
      # sao PRESSOES SEPARADAS: o IME engole o apagar e so deixa passar um pulso
      # de UM frame quando lhe apetece. No frame seguinte o pressex? ja e falso.
      #
      # Por isso nao se repete a partir daqui, por muito que desse jeito: um
      # toque simples e um dedo em cima produzem exactamente o mesmo pulso, e
      # sao indistinguiveis. Repetir a partir de um pulso apagaria meia
      # mensagem a quem so quis tirar uma letra — e nao ha como desfazer.
      #
      # Cada pulso apaga uma letra, pelo MESMO caminho do botao. Quem quer
      # apagar muito segura o APAGAR no ecra, que reporta o dedo em cima e por
      # isso pode repetir (ver AnilBotaoApagar).
      def apagar_por_tecla?
        return false unless (Input.triggerex?(:BACKSPACE) rescue false) ||
                            (Input.repeatex?(:BACKSPACE) rescue false)
        AnilChatDiag.registar_evento("apagar pela tecla")
        apagar_uma_letra
        true
      end

      def apagar_uma_letra
        return if @helper.cursor <= 0
        self.delete
        @cursor_timer_start = System.uptime
        @cursor_shown = true
      end
  end
end

# ─────────────────────────────────────────────────────────────────────────────
# DIAGNÓSTICO DO QUE O TECLADO REALMENTE MANDA
#
# Serve para responder, com dados de aparelho real, a pergunta que não dá para
# responder daqui: o teclado do Android emite ALGUMA coisa ao apagar?
#
# Grava num ficheiro próprio — o log global do jogo não pode ser ligado, porque
# trava o "recuperar partida". Fica desligado por omissão; liga-se com
# /chatdebug e escreve os códigos de cada caractere recebido.
# ─────────────────────────────────────────────────────────────────────────────
module AnilChatDiag
  ARQUIVO = "Data/anil_chat_teclado.txt"

  module_function

  def ligado?; @ligado == true; end

  def alternar!
    @ligado = !ligado?
    registar_linha("--- diagnostico #{@ligado ? 'LIGADO' : 'desligado'} ---")
    @ligado
  end

  def registrar(texto)
    return unless ligado?
    codigos = texto.each_char.map { |c| (c.ord rescue 0) }
    registar_linha("gets #{texto.inspect} codigos=#{codigos.inspect}")
  rescue
  end

  # ⚠️ O DIAGNOSTICO SO VIA METADE DA HISTORIA.
  #
  # O `registrar` era chamado no caminho do Input.gets, que vem DEPOIS de todos
  # os `return` das teclas fisicas. Se o apagar do Android chegasse como
  # BACKSPACE — e a observacao de que segurar o dedo apaga uma letra diz que
  # alguma coisa chega — o diagnostico nunca o via, e a conclusao escrita neste
  # ficheiro ("nao chega evento algum") foi tirada de um teste cego a esse caso.
  #
  # Com o instante de cada evento da para ver a cadencia: se o IME manda um
  # evento solto ou se reporta a tecla premida.
  def registar_evento(texto)
    return unless ligado?
    registar_linha(format("%8.3f  %s", (System.uptime rescue 0.0), texto))
  rescue
  end

  def registar_linha(linha)
    File.open(ARQUIVO, "a:UTF-8") { |f| f.puts("[#{Time.now.strftime('%d/%m %H:%M:%S')}] #{linha}") }
  rescue
  end
end

module AnilLanRework
  module Chat
    class << self
      if !method_defined?(:anil_chatdiag_orig_send_message)
        alias_method :anil_chatdiag_orig_send_message, :send_message rescue nil
      end

      def send_message(text)
        if text.to_s.strip =~ %r{\A/chatdebug\z}i
          estado = AnilChatDiag.alternar!
          AnilLanRework.add_popup("[Chat] Diagnóstico de teclado #{estado ? 'LIGADO' : 'desligado'}.\n" \
                                  "Arquivo: #{AnilChatDiag::ARQUIVO}", 8.0) rescue nil
          return
        end
        anil_chatdiag_orig_send_message(text)
      end
    end
  end
end

AnilLanRework.log("AnilLanRework_Chat (Premium Speech Bubbles) loaded OK")
