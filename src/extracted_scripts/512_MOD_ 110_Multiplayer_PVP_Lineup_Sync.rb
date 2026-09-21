#===============================================================================
# 110_Multiplayer_PVP_Lineup_Sync
#
# Handshake do PvP customizado com espera visivel e selecao simultanea.
#
# FLUXO
#   1. Quem convida escolhe formato e QUANTOS Pokemon. Nao monta time ainda.
#   2. Convite enviado -> janela "Aguardando resposta de X..." na tela dele,
#      com pump de rede (nao trava o cliente).
#   3. Recusa  -> "X recusou o convite."
#      Aceite  -> os DOIS abrem a tela de selecao ao mesmo tempo.
#   4. O numero ja vem acordado: os dois abrem travados em N, entao ninguem
#      consegue entrar com mais nem com menos.
#   5. Enquanto escolhem, cada um ve ao vivo no rodape o que o outro marcou
#      ("Fulano: 3/4 - Charizard, Gengar, Blastoise") e quando ele confirma.
#   6. Quem confirma primeiro espera o outro; os dois entram juntos.
#
# COMO A SELECAO AO VIVO FUNCIONA
#   O loop do Cable Club (005_CableClubAdditions) chama @scene.pbAnnotate(annot)
#   a cada marcacao. Interceptando pbAnnotate da para ler a selecao sem copiar
#   as ~70 linhas do plugin. E PokemonParty_Scene#update roda todo frame dentro
#   do pbChoosePokemon, entao e ali que entra o pump de rede que torna a tela
#   bloqueante capaz de RECEBER — era esse o bloqueio que eu tinha dado como
#   impeditivo antes.
#
# ORDEM DE CARGA
#   PluginManager.runPlugins roda no Main, DEPOIS de todos os scripts. Por isso
#   o que precisa vencer o plugin e aplicado dentro de um hook de runPlugins,
#   igual ao 999_Disable_Cable_Club. O resto pode ser definido normalmente.
#
# Duelo nao-customizado (torneio, 103) nao passa por aqui.
#===============================================================================

module AnilLanRework
  module BattleSync
    class << self

      PVP_INVITE_TIMEOUT  = 90.0  unless const_defined?(:PVP_INVITE_TIMEOUT)
      PVP_CONFIRM_TIMEOUT = 300.0 unless const_defined?(:PVP_CONFIRM_TIMEOUT)

      attr_accessor :pvp_lineup_session

      # ----------------------------------------------------------------------
      # Helpers
      # ----------------------------------------------------------------------
      def pvp_eligible_party
        Array($player&.party).reject { |pkmn| pkmn.nil? || (pkmn.egg? rescue false) }
      end

      def pvp_negotiated_rules?(rules)
        normalized = normalize_duel_rules(rules)
        normalized["negotiated_lineup"] == true ||
          normalized["negotiated_lineup"].to_s.downcase == "true"
      end

      def pvp_peer_name(peer_id)
        peer = AnilLanRework.players[peer_id.to_s]
        (peer && !peer.name.to_s.empty?) ? peer.name.to_s : peer_id.to_s
      end

      # Espera bloqueante mas com rede viva — mesmo padrao do wait_for_party.
      # Devolve :done se o bloco virou verdadeiro, :timeout se estourou.
      # ⚠️ DA PARA DESISTIR COM O X, e a dica vai na propria faixa.
      #
      # Antes so havia duas saidas: o outro responder, ou o tempo esgotar. Quem
      # convidasse alguem que estava de costas ficava preso os 20 segundos a
      # olhar para a faixa. E o mesmo tratamento que a troca e o grupo ja tinham
      # — nao havia razao para o PvP ser a excepcao.
      def pvp_wait_with_window(text, timeout)
        texto_com_dica = "#{text}\n" + AnilLanRework.ui_format("(X para cancelar)")
        viewport, window = build_wait_window(texto_com_dica)
        start = Time.now.to_f
        result = :timeout
        begin
          loop do
            Graphics.update rescue nil
            Input.update rescue nil
            pump_network rescue nil
            AnilLanRework.suppress_peer_interaction!(20)
            if yield
              result = :done
              break
            end
            # O X e lido DEPOIS do yield, de proposito: se a resposta chegou
            # neste frame, ela ganha. Cancelar um convite ja aceite deixava os
            # dois lados a discordar sobre o que ia acontecer a seguir.
            if (Input.trigger?(Input::BACK) rescue false)
              result = :cancelado
              break
            end
            break if Time.now.to_f - start > timeout
            break unless AnilLanRework.connected?
          end
        ensure
          window.dispose if window && !window.disposed?
          viewport.dispose if viewport && !viewport.disposed?
        end
        result
      end

      # ----------------------------------------------------------------------
      # Menu de "quantos Pokemon"
      # ----------------------------------------------------------------------
      def prompt_duel_team_size(max_n)
        max_n = [[max_n.to_i, 1].max, 6].min
        return 1 if max_n == 1
        commands = (1..max_n).map { |n| AnilLanRework.ui_format("{1} Pokemon", n) }
        commands << _INTL("Cancelar")
        command = pbMessage(_INTL("Quantos Pokemon cada lado usa?"), commands, commands.length)
        return nil if command < 0 || command >= commands.length - 1
        command + 1
      end

      # ----------------------------------------------------------------------
      # LADO DE QUEM CONVIDA
      # ----------------------------------------------------------------------
      def request_custom_duel(peer)
        return nil unless peer
        return nil unless AnilLanRework.connected?

        style = prompt_custom_duel_style
        return nil unless style

        eligible = pvp_eligible_party
        if eligible.empty?
          pbMessage(_INTL("Nao tens Pokemon disponiveis para um PvP.")) rescue nil
          return nil
        end

        size = prompt_duel_team_size(eligible.length)
        return nil unless size

        battle_style = duel_style_label(duel_style_from_rules({ "style" => style }))
        return nil unless pbConfirmMessage(AnilLanRework.ui_format(
          "Enviar convite de PvP ({1}, {2} Pokemon cada) para {3}?",
          battle_style, size, peer.name.to_s
        ))

        battle_id = send_negotiated_duel_invite(peer, style, size)
        return nil unless battle_id

        peer_name = peer.name.to_s
        @pvp_invite_reply = nil

        # Passo 2: a espera fica VISIVEL, em vez de o jogador ficar sem saber.
        outcome = pvp_wait_with_window(
          AnilLanRework.ui_format("Aguardando resposta de {1}...", peer_name),
          PVP_INVITE_TIMEOUT
        ) { @pvp_invite_reply && @pvp_invite_reply[:battle_id] == battle_id }

        reply = @pvp_invite_reply
        @pvp_invite_reply = nil

        if outcome != :done || !reply
          @outgoing_invites.delete(battle_id)
          # ⚠️ AVISA-SE O OUTRO LADO.
          #
          # Ele esta dentro de um pbConfirmMessage, que bloqueia o cliente dele:
          # o pacote fica na fila ate ele responder. Mas responde — e nessa
          # altura o `receive_decline` dele explica o que houve. Sem isto, ele
          # carregava em "Sim" e ficava a olhar para nada, porque do nosso lado o
          # convite ja tinha sido apagado e o aceite era descartado em silencio.
          pvp_send_decline(peer.internal_id, battle_id,
                           (outcome == :cancelado) ? "cancelled" : "expired") rescue nil
          if outcome == :cancelado
            pbMessage(_INTL("Você cancelou o convite de batalha.")) rescue nil
          else
            pbMessage(AnilLanRework.ui_format("{1} nao respondeu ao convite.", peer_name)) rescue nil
          end
          return nil
        end

        if reply[:status] == :declined
          pbMessage(AnilLanRework.ui_format("{1} recusou o convite.", peer_name)) rescue nil
          return nil
        end

        agreed = reply[:size].to_i
        agreed = size if agreed <= 0

        if pvp_eligible_party.length < agreed
          pvp_send_decline(peer.internal_id, battle_id)
          pbMessage(AnilLanRework.ui_format(
            "Ja nao tens {1} Pokemon disponiveis. O PvP foi cancelado.", agreed
          )) rescue nil
          return nil
        end

        if agreed < size
          pbMessage(AnilLanRework.ui_format(
            "{1} so tem {2} Pokemon, entao o duelo sera de {2} contra {2}.",
            peer_name, agreed
          )) rescue nil
        end

        pvp_run_lineup_selection(
          peer_id:       peer.internal_id.to_s,
          peer_name:     peer_name,
          battle_id:     battle_id,
          size:          agreed,
          seed:          reply[:seed].to_i,
          rules:         reply[:rules],
          client_index:  0,
          foe_full_blob: reply[:foe_full_blob]
        )
      end

      def send_negotiated_duel_invite(peer, style, size)
        duel_rules = normalize_duel_rules({
          "style"              => style,
          "custom_pvp"         => true,
          "negotiated_lineup"  => true,
          "proposed_team_size" => size
        })
        duel_rules["style"] = style

        battle_id = build_battle_id("duel")
        seed      = rand(0x3FFF_FFFF)

        stored_packet = {
          "to_id"     => peer.internal_id,
          "battle_id" => battle_id,
          "mode"      => "pvp",
          "size"      => size,
          "seed"      => seed,
          "rules"     => duel_rules,
          # Party COMPLETA: e o preview. Nao ha selecao ainda — esse e o ponto.
          "party"     => AnilLanRework::Serializer.serialize_party($player.party),
          "sent_at"   => Time.now.to_f
        }

        wire_packet = stored_packet.dup
        wire_packet["rules"] = public_duel_rules(duel_rules)

        @outgoing_invites[battle_id] = stored_packet
        AnilLanRework.log("request_duel(negociado) battle_id=#{battle_id} proposto=#{size}")
        AnilLanRework.connection.send_packet("battle_invite", wire_packet)
        battle_id
      end

      # O `motivo` viaja para o outro lado escolher a frase. Sem ele, quem
      # recebia via "O pedido de duelo foi recusado" — e ele nao tinha pedido
      # nada, foi quem convidou que desistiu. O mesmo pacote serve os dois
      # sentidos; e a razao que os distingue.
      def pvp_send_decline(peer_id, battle_id, motivo = nil)
        return unless AnilLanRework.connected?
        dados = { "to_id" => peer_id.to_s, "battle_id" => battle_id.to_s }
        dados["reason"] = motivo.to_s unless motivo.to_s.empty?
        AnilLanRework.connection.send_packet("battle_decline", dados)
      end

      # Aceite chega enquanto o convidante esta na janela de espera.
      alias anil_lineup_original_receive_accept receive_accept unless method_defined?(:anil_lineup_original_receive_accept)
      def receive_accept(packet)
        battle_id = packet["battle_id"].to_s
        original  = @outgoing_invites[battle_id]
        return anil_lineup_original_receive_accept(packet) unless original
        return anil_lineup_original_receive_accept(packet) unless pvp_negotiated_rules?(original["rules"])

        @outgoing_invites.delete(battle_id)
        peer_id = packet["sender_id"].to_s
        peer    = AnilLanRework.players[peer_id]
        peer.party_blob = Array(packet["party"]) if peer && packet["party"]

        agreed = packet["agreed_size"].to_i
        agreed = original["size"].to_i if agreed <= 0

        @pvp_invite_reply = {
          :battle_id     => battle_id,
          :status        => :accepted,
          :size          => agreed,
          :seed          => original["seed"].to_i,
          :rules         => normalize_duel_rules(original["rules"]),
          :foe_full_blob => Array(packet["party"])
        }
        AnilLanRework.log("receive_accept(negociado) battle_id=#{battle_id} acordado=#{agreed}")
      end

      alias anil_lineup_original_receive_decline receive_decline unless method_defined?(:anil_lineup_original_receive_decline)
      def receive_decline(packet)
        battle_id = packet["battle_id"].to_s
        original  = @outgoing_invites[battle_id]

        if original && pvp_negotiated_rules?(original["rules"])
          @outgoing_invites.delete(battle_id)
          @pvp_invite_reply = { :battle_id => battle_id, :status => :declined }
          return
        end

        # Recusa que chega no meio da selecao: aborta a sessao.
        if @pvp_lineup_session && @pvp_lineup_session[:battle_id] == battle_id
          @pvp_lineup_session[:aborted] = true
        end
        anil_lineup_original_receive_decline(packet)
      end

      # ----------------------------------------------------------------------
      # LADO DE QUEM ACEITA
      # ----------------------------------------------------------------------
      alias anil_lineup_original_update_pending_invite update_pending_invite unless method_defined?(:anil_lineup_original_update_pending_invite)
      def update_pending_invite
        invite = @pending_invite
        return anil_lineup_original_update_pending_invite unless invite
        return anil_lineup_original_update_pending_invite unless pvp_negotiated_rules?(invite["rules"])

        return unless $scene.is_a?(Scene_Map)
        return if $game_temp&.message_window_showing

        @pending_invite = nil
        sender_id    = invite["sender_id"].to_s
        sender_name  = pvp_peer_name(sender_id)
        battle_id    = invite["battle_id"].to_s
        proposed     = invite["size"].to_i
        proposed     = 1 if proposed <= 0
        invite_rules = normalize_duel_rules(invite["rules"])

        unless pbConfirmMessage(duel_invite_message(sender_name, proposed, invite_rules))
          pvp_send_decline(sender_id, battle_id)
          return
        end

        peer = AnilLanRework.players[sender_id]
        peer.party_blob = Array(invite["party"]) if peer && invite["party"]

        eligible = pvp_eligible_party
        if eligible.empty?
          pvp_send_decline(sender_id, battle_id)
          pbMessage(_INTL("Nao tens Pokemon disponiveis para um PvP.")) rescue nil
          return
        end

        # O numero e acordado ANTES de abrir: os dois abrem travados no mesmo N.
        agreed = [proposed, eligible.length].min
        agreed = 1 if agreed < 1
        if agreed < proposed
          pbMessage(AnilLanRework.ui_format(
            "So tens {1} Pokemon disponiveis, entao o duelo sera de {1} contra {1}.", agreed
          )) rescue nil
        end

        AnilLanRework.connection.send_packet("battle_accept",
          "to_id"       => sender_id,
          "battle_id"   => battle_id,
          "agreed_size" => agreed,
          "party"       => AnilLanRework::Serializer.serialize_party($player.party)
        )

        pvp_run_lineup_selection(
          peer_id:       sender_id,
          peer_name:     sender_name,
          battle_id:     battle_id,
          size:          agreed,
          seed:          invite["seed"].to_i,
          rules:         invite_rules,
          client_index:  1,
          foe_full_blob: Array(invite["party"])
        )
      end

      # O alias tem de vir ANTES da redefinicao, senao captura esta propria
      # versao e a chamada vira recursao infinita.
      alias anil_lineup_original_duel_invite_message duel_invite_message unless method_defined?(:anil_lineup_original_duel_invite_message)
      def duel_invite_message(sender_name, size, rules)
        return anil_lineup_original_duel_invite_message(sender_name, size, rules) unless pvp_negotiated_rules?(rules)
        normalized  = normalize_duel_rules(rules)
        battle_type = duel_style_label(duel_style_from_rules(normalized, size))
        AnilLanRework.ui_format(
          "{1} quer um PvP ({2}, {3} Pokemon cada). Aceitar?",
          sender_name, battle_type, size
        )
      end

      # ----------------------------------------------------------------------
      # Selecao simultanea, igual dos dois lados
      # ----------------------------------------------------------------------
      def pvp_run_lineup_selection(peer_id:, peer_name:, battle_id:, size:, seed:,
                                   rules:, client_index:, foe_full_blob:)
        @pvp_lineup_session = {
          :battle_id        => battle_id,
          :peer_id          => peer_id.to_s,
          :peer_name        => peer_name,
          :size             => size,
          :remote_count     => 0,
          :remote_names     => [],
          :remote_confirmed => false,
          :remote_blob      => nil,
          :aborted          => false,
          :last_sent        => nil
        }
        # Recupera o que chegou antes da sessao existir.
        pvp_drain_lineup_inbox(@pvp_lineup_session)

        begin
          duel_rules = normalize_duel_rules(rules)
          duel_rules["negotiated_lineup"] = true
          battle_rules = build_custom_duel_online_rules_sized(duel_rules["style"], size)

          local_party = Array($player&.party)
          unless battle_rules.ruleset.hasRegistrableTeam?(local_party)
            pvp_send_decline(peer_id, battle_id)
            pbMessage(_INTL("Nao tens uma equipe Pokemon valida para esse PvP.")) rescue nil
            return nil
          end

          foe_full = AnilLanRework::Serializer.deserialize_party(Array(foe_full_blob))
          if battle_rules.team_preview? && !foe_full.empty?
            CableClub_Scene.new.pbTeamPreview(
              build_preview_trainer(peer_name), foe_full, battle_rules.team_preview
            )
          end

          pvp_send_progress([], false)
          team_order = CableClub.choose_team(battle_rules.ruleset)

          if @pvp_lineup_session[:aborted]
            pbMessage(AnilLanRework.ui_format("{1} cancelou o PvP.", peer_name)) rescue nil
            return nil
          end

          if !team_order || team_order.empty?
            pvp_send_decline(peer_id, battle_id)
            pbMessage(_INTL("O PvP foi cancelado.")) rescue nil
            return nil
          end

          selected_party = party_from_order(team_order, local_party)
          if selected_party.empty?
            pvp_send_decline(peer_id, battle_id)
            pbMessage(_INTL("Nao foi possivel montar a tua equipe para este PvP.")) rescue nil
            return nil
          end

          local_blob = AnilLanRework::Serializer.serialize_party(selected_party)
          duel_rules["local_party_order"] = team_order

          AnilLanRework.connection.send_packet("battle_lineup_final",
            "to_id"          => peer_id.to_s,
            "battle_id"      => battle_id,
            "selected_party" => local_blob
          )
          pvp_send_progress(selected_party.map { |p| p.name.to_s }, true)

          AnilLanRework.log(
            "pvp lineup final battle_id=#{battle_id} n=#{selected_party.length} " \
            "local=#{party_species_names(selected_party).inspect}"
          )

          # Passo 6: quem confirma primeiro espera; os dois entram juntos.
          unless @pvp_lineup_session[:remote_blob]
            outcome = pvp_wait_with_window(
              AnilLanRework.ui_format("Aguardando {1} confirmar a equipe...", peer_name),
              PVP_CONFIRM_TIMEOUT
            ) { @pvp_lineup_session[:remote_blob] || @pvp_lineup_session[:aborted] }

            if @pvp_lineup_session[:aborted]
              pbMessage(AnilLanRework.ui_format("{1} cancelou o PvP.", peer_name)) rescue nil
              return nil
            end
            if outcome != :done
              pvp_send_decline(peer_id, battle_id)
              pbMessage(AnilLanRework.ui_format("{1} demorou demais. O PvP foi cancelado.", peer_name)) rescue nil
              return nil
            end
          end

          @pending_start = {
            :battle_id    => battle_id,
            :peer_id      => peer_id.to_s,
            :size         => size,
            :seed         => seed,
            :client_index => client_index,
            :rules        => duel_rules,
            :party        => @pvp_lineup_session[:remote_blob],
            :local_party  => local_blob
          }
          AnilLanRework.suppress_peer_interaction!(20)
          battle_id
        ensure
          pvp_lineup_inbox.delete(battle_id.to_s)
          @pvp_lineup_session = nil
        end
      end

      # ----------------------------------------------------------------------
      # Progresso ao vivo
      # ----------------------------------------------------------------------
      def pvp_send_progress(names, confirmed)
        session = @pvp_lineup_session
        return unless session
        return unless AnilLanRework.connected?
        payload = [names.length, confirmed, names]
        return if session[:last_sent] == payload
        session[:last_sent] = payload
        AnilLanRework.connection.send_packet("battle_lineup_progress",
          "to_id"     => session[:peer_id],
          "battle_id" => session[:battle_id],
          "count"     => names.length,
          "names"     => names,
          "confirmed" => confirmed
        )
      rescue => e
        AnilLanRework.log("pvp_send_progress erro #{e}")
      end

      # Chamado pelo pbAnnotate interceptado, a cada marcacao.
      def pvp_report_local_order(order)
        session = @pvp_lineup_session
        return unless session
        party = Array($player&.party)
        names = Array(order).map { |i| party[i]&.name.to_s }.reject(&:empty?)
        pvp_send_progress(names, false)
      rescue => e
        AnilLanRework.log("pvp_report_local_order erro #{e}")
      end

      # O oponente pode confirmar antes de esta ponta abrir a sessao (ele manda
      # battle_accept e ja vai escolher; aqui ainda ha pbMessage/team preview
      # pela frente). Sem isto o final chegava com sessao nula, era descartado,
      # e esta ponta esperava ate o timeout.
      def pvp_lineup_inbox
        @pvp_lineup_inbox ||= {}
      end

      def pvp_stash_lineup(battle_id, key, value)
        slot = (pvp_lineup_inbox[battle_id.to_s] ||= {})
        slot[key] = value
      end

      def pvp_drain_lineup_inbox(session)
        slot = pvp_lineup_inbox.delete(session[:battle_id].to_s)
        return unless slot
        if slot[:progress]
          session[:remote_count]     = slot[:progress][:count]
          session[:remote_names]     = slot[:progress][:names]
          session[:remote_confirmed] = slot[:progress][:confirmed]
        end
        if slot[:final]
          session[:remote_blob]      = slot[:final]
          session[:remote_confirmed] = true
        end
        AnilLanRework.log("pvp lineup inbox drenado battle_id=#{session[:battle_id]}")
      end

      def receive_lineup_progress(packet)
        battle_id = packet["battle_id"].to_s
        data = {
          :count     => packet["count"].to_i,
          :names     => Array(packet["names"]).map(&:to_s),
          :confirmed => (packet["confirmed"] == true || packet["confirmed"].to_s == "true")
        }
        session = @pvp_lineup_session
        unless session && session[:battle_id] == battle_id
          pvp_stash_lineup(battle_id, :progress, data)
          return
        end
        session[:remote_count]     = data[:count]
        session[:remote_names]     = data[:names]
        session[:remote_confirmed] = data[:confirmed]
      rescue => e
        AnilLanRework.log("receive_lineup_progress erro #{e}")
      end

      def receive_lineup_final(packet)
        battle_id = packet["battle_id"].to_s
        blob      = Array(packet["selected_party"])
        session   = @pvp_lineup_session
        unless session && session[:battle_id] == battle_id
          pvp_stash_lineup(battle_id, :final, blob)
          AnilLanRework.log("receive_lineup_final adiantado battle_id=#{battle_id} (guardado)")
          return
        end
        session[:remote_blob]      = blob
        session[:remote_confirmed] = true
        AnilLanRework.log("receive_lineup_final battle_id=#{battle_id}")
      rescue => e
        AnilLanRework.log("receive_lineup_final erro #{e}")
      end

      # Texto do rodape durante a selecao.
      #
      # Ao confirmar, a versao antiga trocava a lista por "confirmou N Pokemon"
      # e os nomes SUMIAM justo no momento em que interessava saber com o que o
      # oponente ia entrar. Agora a lista permanece e quem sinaliza a
      # confirmacao e o icone de certo que a faixa desenha no fim.
      def pvp_lineup_status_text
        session = @pvp_lineup_session
        return nil unless session
        name  = session[:peer_name]
        names = Array(session[:remote_names]).map(&:to_s).reject(&:empty?)

        if names.empty?
          return AnilLanRework.ui_format("{1} confirmou {2} Pokemon.", name, session[:remote_count]) if session[:remote_confirmed]
          return AnilLanRework.ui_format("{1} ainda nao escolheu.", name)
        end

        AnilLanRework.ui_format("{1}: {2}/{3} - {4}",
          name, session[:remote_count], session[:size], names.join(", ")
        )
      rescue
        nil
      end

      def pvp_lineup_remote_confirmed?
        session = @pvp_lineup_session
        session ? (session[:remote_confirmed] ? true : false) : false
      rescue
        false
      end
    end

    @pvp_lineup_session = nil
    @pvp_invite_reply   = nil
    @pvp_lineup_inbox   = {}
  end
end

#-------------------------------------------------------------------------------
# Tela de party: pump de rede por frame + rodape ao vivo.
# PokemonParty_Scene#update roda dentro do loop do pbChoosePokemon (0303 e o
# override do 060_Party_Touch_Modular), entao e o unico ponto que executa
# enquanto a tela bloqueante esta aberta.
#-------------------------------------------------------------------------------
class PokemonParty_Scene
  alias anil_pvp_lineup_update update unless method_defined?(:anil_pvp_lineup_update)
  def update
    anil_pvp_lineup_update
    session = (AnilLanRework::BattleSync.pvp_lineup_session rescue nil)
    return unless session
    AnilLanRework::BattleSync.pump_network rescue nil
    text = AnilLanRework::BattleSync.pvp_lineup_status_text rescue nil
    return unless text
    confirmado = AnilLanRework::BattleSync.pvp_lineup_remote_confirmed? rescue false

    help = @sprites && @sprites["helpwindow"]
    return unless help && !help.disposed?

    # O rodape fica na helpwindow mesmo, embaixo, como sempre foi. O unico
    # problema era a altura: o pbStartScene a cria com pbBottomLeftLines(..., 1)
    # e, com 6 Pokemon, a lista passa de uma linha e o resto sumia. A
    # Window_UnformattedTextPokemon ja quebra o texto sozinha (getLineBrokenChunks);
    # so faltava deixar a janela crescer, que e o que o resizeHeightToFit faz.
    if help.text != text
      help.text = text
      begin
        help.resizeHeightToFit(text, anil_pvp_largura_rodape)
        help.y = Graphics.height - help.height
      rescue
      end
    end
    help.visible = true

    # O check vai desenhado por cima do contents. Redesenhado todo frame de
    # proposito: qualquer refresh da janela (o proprio plugin chama
    # pbSetHelpText no loop de selecao) limpa o contents e levaria o icone junto.
    anil_pvp_desenhar_check(help) if confirmado
  rescue
    nil
  end

  # A janela vai so ate onde comecam CONFIRMAR/CANCELAR, com uma folga, em vez
  # de atravessar a tela inteira e passar por tras dos botoes. O x vem dos
  # proprios sprites (PokemonPartyConfirmSprite nasce em x=398), assim continua
  # certo se as posicoes mudarem.
  MARGEM_ATE_BOTOES = 6

  def anil_pvp_largura_rodape
    return @anil_pvp_largura_rodape if @anil_pvp_largura_rodape
    limite = Graphics.width
    begin
      (@sprites || {}).each_value do |s|
        next unless defined?(PokemonPartyConfirmCancelSprite) && s.is_a?(PokemonPartyConfirmCancelSprite)
        next if s.disposed?
        limite = s.x if s.x > 0 && s.x < limite
      end
    rescue
    end
    @anil_pvp_largura_rodape = [limite - MARGEM_ATE_BOTOES, 160].max
  rescue
    Graphics.width
  end

  # Canto inferior direito da ultima linha da janela. Nao tento alinhar com o
  # fim do texto porque quem quebra as linhas e a propria janela
  # (getLineBrokenChunks, por dentro do refresh) — daqui nao da para saber onde
  # cada linha terminou sem refazer a conta dela.
  def anil_pvp_desenhar_check(help)
    bmp = help.contents
    return unless bmp
    tamanho = 16
    linhas  = [(bmp.height / 32.0).ceil, 1].max
    AnilLanRework::CheckIcon.desenhar(
      bmp, bmp.width - tamanho - 2, ((linhas - 1) * 32) + 8, tamanho
    )
  rescue
    nil
  end
end

#-------------------------------------------------------------------------------
# Leitura da selecao local sem copiar o loop do plugin.
#
# O loop do Cable Club monta annot[i] = ordinals[statuses[i]], com statuses >= 3
# significando "escolhido em Nº lugar". Reconstruindo a MESMA lista de ordinais
# (mesmos literais, mesmo _INTL) da para inverter annot -> ordem sem tocar no
# plugin. Precisa rodar depois do runPlugins porque o plugin so existe ali.
#-------------------------------------------------------------------------------
module PluginManager
  class << self
    alias __pvp_lineup_runPlugins runPlugins unless method_defined?(:__pvp_lineup_runPlugins)
    def runPlugins(*args)
      __pvp_lineup_runPlugins(*args)

      ::PokemonParty_Scene.class_eval do
        alias anil_pvp_lineup_annotate pbAnnotate unless method_defined?(:anil_pvp_lineup_annotate)
        def pbAnnotate(annot)
          anil_pvp_lineup_annotate(annot)
          return unless AnilLanRework::BattleSync.pvp_lineup_session
          return unless annot.is_a?(Array)
          ordinals = [
            _INTL("NO APTO"), _INTL("NO ELEGIDO"), _INTL("BANEADO"),
            _INTL("PRIMERO"), _INTL("SEGUNDO"), _INTL("TERCERO"),
            _INTL("CUARTO"), _INTL("QUINTO"), _INTL("SEXTO")
          ]
          order = []
          annot.each_with_index do |txt, i|
            idx = ordinals.index(txt)
            order[idx - 3] = i if idx && idx >= 3
          end
          AnilLanRework::BattleSync.pvp_report_local_order(order.compact)
        rescue
          nil
        end
      end
    end
  end
end
