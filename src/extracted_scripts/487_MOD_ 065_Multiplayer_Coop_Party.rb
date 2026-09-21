#===============================================================================
# MOD: 065_Multiplayer_Coop_Party.rb
#-------------------------------------------------------------------------------
# Sistema de Grupo Cooperativo (Co-op Party) e Exibição de Nomes no Mapa
#===============================================================================

module AnilLanRework
  class << self
    attr_accessor :coop_party_partner_id
  end
  @coop_party_partner_id = nil

  module_function

  # 1. Menu de Interação com Jogador na Mapa
  def handle_peer_interaction_trigger
    # Não abrir o menu de interação com outro jogador enquanto a caixa de chat
    # está capturando texto (ou na carência pós-fechamento). Sem isto, digitar
    # C/T na frente de um peer abria o menu Ver/Trocar/Batalhar.
    return if defined?(AnilLanRework::ChatInputHUD) &&
              AnilLanRework::ChatInputHUD.respond_to?(:input_blocked?) &&
              AnilLanRework::ChatInputHUD.input_blocked?
    if (Input.trigger?(Input::C) rescue false) ||
       (Input.trigger?(Input::T) rescue false)
      return if AnilLanRework.peer_interaction_suppressed?
      dir = $game_player.direction
      facing_x = $game_player.x + (dir == 6 ? 1 : dir == 4 ? -1 : 0)
      facing_y = $game_player.y + (dir == 2 ? 1 : dir == 8 ? -1 : 0)
      AnilLanRework.players.each_value do |peer|
        next unless peer.map_id == $game_map.map_id && peer.x == facing_x && peer.y == facing_y
        next if AnilLanRework::WorldSync.hide_peer_sprite?(peer)
        AnilLanRework.clear_input_buffer
        
        in_party = (AnilLanRework.coop_party_partner_id.to_s == peer.internal_id.to_s)
        
        # ⚠️ A lista e as accoes constroem-se JUNTAS.
        #
        # Antes eram duas listas paralelas — os textos aqui e um `case command`
        # com numeros la em baixo. Acrescentar uma entrada no meio obrigava a
        # renumerar tudo o que vinha a seguir a mao, e um engano ai nao rebenta:
        # troca-se "Batalhar" por "Enviar Item" e ninguem percebe porque.
        # Agora cada entrada traz a sua accao colada.
        accoes = []
        accoes << [_INTL("Ver Pokemon"),   proc { AnilLanRework::PlayerMarket.open_peer_follower_summary(peer) }]
        accoes << [_INTL("Trocar Pokemon"), proc { AnilLanRework::TradeSync.request_trade(peer) }]
        # So aparece se o MOD 181 estiver presente — quem nao o tiver ve o menu
        # de sempre, sem uma opcao que nao faz nada.
        if defined?(AnilTrocaCompleta)
          accoes << [_INTL("Troca Completa"), proc { AnilTrocaCompleta.convidar_peer(peer) }]
        end
        accoes << [_INTL("Enviar Item"),   proc { AnilLanRework::ItemSync.open_bag_for_peer(peer) }]
        accoes << [_INTL("Batalhar"),      proc { AnilLanRework::BattleSync.request_custom_duel(peer) }]
        # ⚠️ A ARENA ENTRA PELA MESMA PORTA QUE A BATALHA NORMAL.
        #
        # Ela ja tinha um convite proprio (`/arena <nome>`), mas um comando
        # escrito nao e como se desafia alguem neste jogo: chega-se ao pe da
        # pessoa e fala-se com ela. Aqui em baixo esta a lista de tudo o que se
        # pode fazer com outro treinador — e e aqui que a arena tem de estar,
        # a seguir a "Batalhar", para se ler como a alternativa que e.
        #
        # So aparece se o MOD 189 estiver carregado: quem nao o tiver ve o menu
        # de sempre, sem uma opcao morta.
        # So aparece a quem tem o Amuleto Teste: enquanto a arena for
        # experimental, quem nao pediu para a testar nao ve que ela existe.
        # ⚠️ O AMULETO, e nao o guarda-chuva: lutar contra outro jogador e
        # batalha directa. Quem so tem o Guia Mestre nao ve esta linha — e nao
        # via nada de util nela, porque o `convidar!` recusava-o logo a seguir.
        if defined?(AnilArena) && (AnilArena.directa? rescue false)
          accoes << [_INTL("Batalha direta"), proc { AnilArena.convidar!(peer.name) }]
        end
        accoes << [in_party ? _INTL("Sair do Grupo") : _INTL("Convidar para Grupo"),
                   proc { in_party ? AnilLanRework.leave_coop_party(peer) : AnilLanRework.invite_to_coop_party(peer) }]
        accoes << [_INTL("Cancelar"), proc { }]

        interaction_commands = accoes.map { |t, _| t }
        command = pbMessage(_INTL("O que desejas fazer com {1}?", peer.name), interaction_commands, interaction_commands.length)
        AnilLanRework.suppress_peer_interaction!
        AnilLanRework.clear_input_buffer
        if command.is_a?(Integer) && command >= 0 && command < accoes.length
          accoes[command][1].call
        end
        AnilLanRework.suppress_peer_interaction!(16)
        AnilLanRework.clear_input_buffer
        break
      end
    end
  end

  # 2. Enviar Convite de Grupo
  PARTY_INVITE_TIMEOUT = 90.0 unless const_defined?(:PARTY_INVITE_TIMEOUT)

  def invite_to_coop_party(peer)
    AnilLanRework.log("Enviando convite de grupo para #{peer.name} (#{peer.internal_id})")
    # Zerado ANTES do envio: uma resposta antiga na variavel encerraria a espera
    # no primeiro frame.
    @party_invite_reply = nil
    AnilLanRework.connection.send_packet("party_invite",
      "to_id"     => peer.internal_id,
      "sender_id" => AnilLanRework.self_internal_id,
      "name"      => AnilLanRework.self_name
    )

    # Espera visivel, como no PvP customizado. Antes o pbMessage dizia "convite
    # enviado" e o controle voltava na hora — quem convidou nao sabia se o outro
    # tinha recebido, recusado ou saido do jogo.
    #
    # O grupo nao tinha estado consultavel (party_accept so setava o parceiro e
    # party_decline so exibia uma mensagem), por isso o @party_invite_reply.
    # Convite novo para a mesma pessoa: a desistencia anterior deixa de valer.
    (@convite_cancelado || {}).delete(peer.internal_id.to_s)

    resultado = AnilLanRework::BattleSync.aguardar_resposta_convite(
      AnilLanRework.ui_format("Aguardando resposta de {1}...", peer.name.to_s),
      PARTY_INVITE_TIMEOUT
    ) { !@party_invite_reply.nil? }

    resposta = @party_invite_reply
    @party_invite_reply = nil

    # As mensagens de aceite/recusa foram adiadas pelos handlers (a faixa
    # cobriria o dialogo); agora que ela saiu, exibe.
    if resposta == :accept
      pbMessage(_INTL("Grupo formado com {1}!", peer.name)) rescue nil
      return
    elsif resposta == :decline
      pbMessage(_INTL("{1} recusou o convite de grupo.", peer.name)) rescue nil
      return
    end

    if resultado == :desconectado
      pbMessage(_INTL("A conexão caiu antes de {1} responder.", peer.name)) rescue nil
    elsif resultado == :cancelado
      # ⚠️ O OUTRO LADO NAO SABE QUE DESISTIMOS.
      #
      # Ele esta parado dentro de um pbConfirmMessage — um dialogo que bloqueia
      # o cliente dele. Enquanto nao carregar em Sim ou Nao, nao processa
      # pacote nenhum, portanto nao ha aviso que lhe tire a caixa do ecra.
      #
      # Marca-se a desistencia e trata-se o "sim" que possa chegar depois. Sem
      # isto ele entrava no grupo sozinho: o party_accept, mais abaixo, poe o
      # parceiro sem perguntar se o convite ainda estava de pe.
      @convite_cancelado ||= {}
      @convite_cancelado[peer.internal_id.to_s] = Time.now.to_f
      pbMessage(_INTL("Você cancelou o convite de grupo.")) rescue nil
    else
      pbMessage(_INTL("{1} não respondeu ao convite de grupo.", peer.name)) rescue nil
    end
  end


  # 3. Sair do Grupo
  def leave_coop_party(peer)
    AnilLanRework.log("Desfazendo grupo com #{peer.name}")
    AnilLanRework.connection.send_packet("party_leave",
      "to_id"     => peer.internal_id,
      "sender_id" => AnilLanRework.self_internal_id
    )
    AnilLanRework.coop_party_partner_id = nil
    AnilCadeiaCoop.limpar! if defined?(AnilCadeiaCoop)
    pbMessage(_INTL("Você desfez o grupo com {1}.", peer.name))
  end

  # 4. Processar Pacotes de Rede do Grupo
  def on_party_packet(packet)
    type = packet["type"].to_s
    sender_id = packet["sender_id"].to_s
    peer = AnilLanRework.players[sender_id]
    sender_name = packet["name"] || peer&.name || "Jogador"
    # Segurança: garante que o pacote de grupo seja de fato direcionado a nós
    if packet["to_id"] && packet["to_id"].to_s != AnilLanRework.self_internal_id.to_s
      AnilLanRework.log("ignored party packet meant for different recipient to_id=#{packet["to_id"]}")
      return
    end
    if ["party_invite", "party_accept", "party_decline"].include?(type)
      if packet["to_id"].to_s != AnilLanRework.self_internal_id.to_s
        AnilLanRework.log("ignored party direct packet #{type} without matching to_id")
        return
      end
    end

    case type
    when "party_invite"
      return unless $scene.is_a?(Scene_Map)
      accepted_raw = pbConfirmMessage(_INTL("{1} convidou você para o grupo. Aceitar?", sender_name))
      accepted = (accepted_raw == true || accepted_raw == 0)
      if accepted
        AnilLanRework.log("Convite de grupo de #{sender_name} ACEITO.")
        AnilLanRework.connection.send_packet("party_accept",
          "to_id"     => sender_id,
          "sender_id" => AnilLanRework.self_internal_id,
          "name"      => AnilLanRework.self_name
        )
        AnilLanRework.coop_party_partner_id = sender_id
        # Cadeia do parceiro comeca do zero: a que estivesse guardada e de
        # outro grupo (MOD 135).
        AnilCadeiaCoop.limpar! if defined?(AnilCadeiaCoop)
        pbMessage(_INTL("Grupo formado com {1}!", sender_name))
      else
        AnilLanRework.log("Convite de grupo de #{sender_name} RECUSADO.")
        AnilLanRework.connection.send_packet("party_decline",
          "to_id"     => sender_id,
          "sender_id" => AnilLanRework.self_internal_id
        )
      end

    when "party_accept"
      # Chegou tarde: nos ja tinhamos desistido. Desfaz-se do lado dele e nao se
      # entra no grupo — senao ficavamos os dois com ideias diferentes sobre
      # quem esta com quem.
      #
      # A janela de 2 minutos e generosa de proposito: ele pode ter deixado a
      # caixa aberta muito tempo. Passado isso, ja e um convite novo qualquer.
      if @convite_cancelado.is_a?(Hash) &&
         (Time.now.to_f - @convite_cancelado[sender_id.to_s].to_f) < 120.0 &&
         @convite_cancelado.key?(sender_id.to_s)
        @convite_cancelado.delete(sender_id.to_s)
        AnilLanRework.log("party_accept de #{sender_name} ignorado: o convite tinha sido cancelado.")
        AnilLanRework.connection.send_packet("party_leave",
          "to_id"     => sender_id,
          "sender_id" => AnilLanRework.self_internal_id
        ) rescue nil
        pbMessage(_INTL("{1} aceitou tarde demais — o convite já tinha sido cancelado.", sender_name)) rescue nil
        return
      end
      AnilLanRework.log("Convite de grupo aceito por #{sender_name}.")
      # Encerra a espera de quem convidou (ver invite_to_coop_party). Vem ANTES
      # do pbMessage: a janela de espera precisa sumir antes do dialogo aparecer.
      @party_invite_reply = :accept
      AnilLanRework.coop_party_partner_id = sender_id
      AnilCadeiaCoop.limpar! if defined?(AnilCadeiaCoop)
      # Adiada enquanto a faixa de espera esta na tela (ela tem z maior e
      # cobriria o dialogo). Quem convidou exibe logo apos a faixa sair.
      unless AnilLanRework::BattleSync.aguardando_convite?
        pbMessage(_INTL("Grupo formado com {1}!", sender_name))
      end

    when "party_decline"
      AnilLanRework.log("Convite de grupo recusado por #{sender_name}.")
      @party_invite_reply = :decline
      unless AnilLanRework::BattleSync.aguardando_convite?
        pbMessage(_INTL("{1} recusou o convite de grupo.", sender_name))
      end

    when "party_leave"
      AnilLanRework.log("Grupo desfeito por #{sender_name}.")
      AnilLanRework.coop_party_partner_id = nil
      # Sem grupo nao ha soma nem bonus — deixar a cadeia velha guardada
      # manteria o -100 a valer sozinho.
      AnilCadeiaCoop.limpar! if defined?(AnilCadeiaCoop)
      pbMessage(_INTL("{1} desfez o grupo cooperativo.", sender_name))
    end
  end
end

#===============================================================================
# Sobrescrever Descoberta de Parceiro Co-op (Filtro por Grupo)
#===============================================================================
module AnilLanRework
  module BattleSync
    class << self
      alias anil_party_original_partner_on_same_map partner_on_same_map unless method_defined?(:anil_party_original_partner_on_same_map)
      
      def partner_on_same_map
        # Se estiver em um grupo, retorna especificamente o parceiro se ele estiver por perto
        if defined?(AnilLanRework) && AnilLanRework.respond_to?(:coop_party_partner_id) && AnilLanRework.coop_party_partner_id
          partner_id = AnilLanRework.coop_party_partner_id.to_s
          peer = AnilLanRework.players[partner_id]
          if peer && peer.map_id.to_i == $game_map.map_id.to_i && peer.battle_busy == false && peer.menu_open == false
            dx = (peer.x.to_i - $game_player.x.to_i).abs
            dy = (peer.y.to_i - $game_player.y.to_i).abs
            if [dx, dy].max <= AnilLanRework::REMOTE_SPAWN_AUTHORITY_DISTANCE
              return peer
            end
          end
        end
        # Se não tiver grupo ou parceiro não estiver elegível, não entra em coop selvagem/treinador automático
        return nil
      end
    end
  end
end

#===============================================================================
# Desenhar Nomes no Mapa acima dos Sprites dos Jogadores (Rich Aesthetics)
#===============================================================================
if defined?(Sprite_Character)
  class Sprite_Character < RPG::Sprite
    alias anil_party_name_update update unless method_defined?(:anil_party_name_update)
    alias anil_party_name_dispose dispose unless method_defined?(:anil_party_name_dispose)

    def dispose
      @peer_name_sprite&.bitmap&.dispose rescue nil
      @peer_name_sprite&.dispose rescue nil
      @peer_name_sprite = nil
      anil_party_name_dispose
    end

    def update
      anil_party_name_update
      if @character.is_a?(AnilLanRework::RemotePeer)
        current_name = @character.name.to_s
        if current_name.empty?
          if @peer_name_sprite
            @peer_name_sprite.visible = false
          end
        else
          if !@peer_name_sprite || @peer_name_sprite.disposed? || @drawn_peer_name != current_name
            @peer_name_sprite&.bitmap&.dispose rescue nil
            @peer_name_sprite&.dispose rescue nil
            
            @peer_name_sprite = Sprite.new(self.viewport)
            @peer_name_sprite.z = self.z + 1000
            
            # Criação premium do nameplate
            bmp = Bitmap.new(160, 32)
            bmp.font.name = "Arial"
            bmp.font.size = 16 # Aumentado em 0.5x (de 11 para 16)
            bmp.font.bold = true
            
            # Desenho discreto de sombra (Text Shadow para excelente contraste)
            bmp.font.color = Color.new(0, 0, 0, 200)
            bmp.draw_text(1, 1, 160, 28, current_name, 1)
            
            # Nome com tonalidade azul bonita (Premium styling)
            bmp.font.color = Color.new(30, 144, 255) # Azul bonito (Dodger Blue)
            bmp.draw_text(0, 0, 160, 28, current_name, 1)
            
            @peer_name_sprite.bitmap = bmp
            @peer_name_sprite.ox = 80
            @peer_name_sprite.oy = 32
            @drawn_peer_name = current_name
          end
          
          # Copiar o zoom dinâmico da câmera para o nameplate (evita que fique minúsculo no PC)
          @peer_name_sprite.zoom_x = self.zoom_x rescue 1.0
          @peer_name_sprite.zoom_y = self.zoom_y rescue 1.0
          
          # Posicionamento dinâmico baseado na altura do charset do jogador (altura 0.9x)
          @peer_name_sprite.x = self.x
          # ⚠️ Descontar o ceu vazio da celula de quem esta montado.
          #
          # O `oy` e a altura da celula do charset. No charset de montaria ela
          # leva 72 px de margem por cima para o cavaleiro caber, e o nome
          # subia essa margem toda — ficava a pairar acima do jogador.
          altura_util = self.oy - (defined?(AnilMontaria) ? (AnilMontaria.folga_da_celula(@character) rescue 0) : 0)
          altura_util = self.oy if altura_util <= 0
          @peer_name_sprite.y = self.y - ((altura_util * 0.6) * self.zoom_y rescue altura_util * 0.6) - 4
          @peer_name_sprite.visible = self.visible && !@character.transparent
        end
      else
        if @peer_name_sprite
          @peer_name_sprite.bitmap&.dispose rescue nil
          @peer_name_sprite.dispose rescue nil
          @peer_name_sprite = nil
        end
      end
    end
  end
end

AnilLanRework.log("AnilLanRework_CoopParty (Nameplates and Custom Party Sync) loaded OK")
