#===============================================================================
# MOD: 032_Multiplayer_Coop_Lock_Patch.rb
#-------------------------------------------------------------------------------
# Sistema de Trava Manual (Manual Lock Sync)
# Melhora a estabilidade de rede em batalhas cooperativas (coop) e pvp.
# Evita timeouts acidentais enquanto o parceiro estiver em menus longos,
# diálogos de aprendizado de golpes, evoluções ou telas de experiência.
#===============================================================================

module AnilLanRework
  module BattleSync
    class << self
      def manual_lock_supported?(ctx = nil)
        ctx ||= @active_context
        return false unless ctx && [:pvp, :coop].include?(ctx.mode) && AnilLanRework.connected?
        return false if coop_remote_sync_disabled?(ctx)
        true
      rescue
        false
      end

      def local_manual_lock?(ctx = nil)
        ctx ||= @active_context
        return false unless ctx
        ctx.instance_variable_get(:@anil_manual_lock_depth).to_i > 0
      rescue
        false
      end

      # Quanto tempo o lock do parceiro tem de durar antes de ser anunciado.
      ATRASO_MANUAL_LOCK = 2.0 unless const_defined?(:ATRASO_MANUAL_LOCK)

      # O lock so e dado como activo depois de ATRASO_MANUAL_LOCK.
      #
      # A maioria dos locks resolve-se em milissegundos e a faixa so piscava —
      # incluindo o "ganhando experiencia", que era marcado uma vez por Pokemon
      # a cada desmaio. Atrasar AQUI, no portao, e o que resolve: nenhum dos 22
      # chamadores chega sequer a criar faixa, e "nao ha lock" e o estado normal
      # que todos ja sabem tratar.
      #
      # (Uma tentativa anterior atrasou a EXIBICAO em build_wait_window, que e a
      # origem de TODAS as faixas de espera e nao so dos manual locks. Resultado:
      # nenhum aviso aparecia. Aqui o alcance e exactamente o pedido.)
      #
      # O `rescue` devolve o valor CRU de proposito: se algo falhar, o lock
      # aparece como aparecia antes. Falhar a mostrar e melhor do que falhar a
      # esconder — o jogador fica sem saber porque o jogo esta parado.
      def remote_manual_lock?(ctx = nil)
        ctx ||= @active_context
        return false unless ctx
        ligado = ctx.instance_variable_get(:@anil_remote_manual_lock) == true
        unless ligado
          ctx.instance_variable_set(:@anil_remote_lock_desde, nil)
          return false
        end
        desde = ctx.instance_variable_get(:@anil_remote_lock_desde)
        if desde.nil?
          desde = Time.now.to_f
          ctx.instance_variable_set(:@anil_remote_lock_desde, desde)
        end
        (Time.now.to_f - desde.to_f) >= ATRASO_MANUAL_LOCK
      rescue
        (ctx.instance_variable_get(:@anil_remote_manual_lock) == true rescue false)
      end

      def remote_message_active?(ctx = nil)
        ctx ||= @active_context
        return false unless ctx && ctx.partner_id
        peer = AnilLanRework.players[ctx.partner_id.to_s]
        return false unless peer
        peer.busy == true
      rescue
        false
      end

      def manual_wait_text(reason = nil)
        ctx = @active_context
        reason = reason.to_s
        if reason.empty? && ctx
          reason = ctx.instance_variable_get(:@anil_remote_manual_reason).to_s
        end
        partner_name = remote_partner_name
        if reason.start_with?("evolution:")
          pkmn_name = reason.split(":", 2)[1]
          raw_msg = "#{partner_name} está assistindo à evolução de #{pkmn_name}..."
        else
          raw_msg = case reason
          when "exp_phase"        then "Aguardando #{partner_name} terminar a experiência..."
          when "exp_gaining"      then "#{partner_name} ganhando experiência..."
          when "level_up"         then "Pokémon de #{partner_name} subiu de nível!"
          when "level_up_stats"   then "#{partner_name} vendo os atributos do level up..."
          when "learn_move"       then "#{partner_name} escolhendo qual golpe manter..."
          when "choosing_move"    then "#{partner_name} escolhendo qual golpe manter..."
          when "confirm_message"  then "Aguardando resposta de #{partner_name}..."
          when "switch_prompt"    then "Aguardando #{partner_name} escolher Pokémon..."
          when "evolution"        then "Aguardando #{partner_name} terminar de assistir a evolução..."
          else "Aguardando #{partner_name}..."
          end
        end
        return waiting_text(raw_msg)
      end

      def apply_remote_manual_lock_packet(packet, ctx = nil)
        return unless packet.is_a?(Hash)
        ctx ||= @active_context
        return unless ctx
        locked = packet["locked"] == true
        ctx.instance_variable_set(:@anil_remote_manual_lock, locked)
        ctx.instance_variable_set(:@anil_remote_manual_unlock_required, true) if locked
        reason = packet["reason"].to_s
        reason = nil if reason.empty?
        ctx.instance_variable_set(:@anil_remote_manual_reason, reason)
        
        # Log PvP
        if ctx.mode == :pvp
          turn = ctx.battle ? (ctx.battle.turnCount.to_i rescue "nil") : "nil"
          AnilLanRework.log(
            "pvp manual lock rx battle_id=#{ctx.battle_id} mode=pvp client_index=#{ctx.client_index} turn=#{turn} locked=#{locked} reason=#{reason || 'none'}"
          )
        end

        AnilLanRework.log(
          "battle manual lock recv battle_id=#{ctx.battle_id} locked=#{locked} reason=#{reason || 'none'} unlock_required=#{ctx.instance_variable_get(:@anil_remote_manual_unlock_required) == true}"
        )
      rescue => e
        AnilLanRework.log("battle manual lock apply error #{e.class}: #{e.message}")
      end

      def send_manual_lock_state(locked, reason = nil)
        ctx = @active_context
        return unless manual_lock_supported?(ctx)
        
        # Log PvP
        if ctx.mode == :pvp
          turn = ctx.battle ? (ctx.battle.turnCount.to_i rescue "nil") : "nil"
          AnilLanRework.log(
            "pvp manual lock tx battle_id=#{ctx.battle_id} mode=pvp client_index=#{ctx.client_index} turn=#{turn} locked=#{locked ? true : false} reason=#{reason || 'none'}"
          )
        end

        payload = {
          "to_id"     => ctx.partner_id,
          "battle_id" => ctx.battle_id,
          "locked"    => locked ? true : false
        }
        payload["reason"] = reason.to_s if reason && !reason.to_s.empty?
        AnilLanRework.connection.send_packet("battle_manual_lock", payload)
        send_phase_sync("manual_unlock_done", "ready", "reason" => reason.to_s) if !locked
        AnilLanRework.log(
          "battle manual lock send battle_id=#{ctx.battle_id} locked=#{locked ? true : false} reason=#{reason || 'none'}"
        )
      rescue => e
        AnilLanRework.log("battle manual lock send error #{e.class}: #{e.message}")
      end

      # Atualiza apenas o reason do manual lock ativo sem alterar o depth.
      def update_manual_lock_reason(reason)
        ctx = @active_context
        return unless ctx && local_manual_lock?(ctx)
        send_manual_lock_state(true, reason)
      rescue => e
        AnilLanRework.log("update_manual_lock_reason error #{e.class}: #{e.message}")
      end

      def begin_manual_lock(reason = nil, ctx = nil)
        ctx ||= @active_context
        return nil unless manual_lock_supported?(ctx)
        before_snapshot = current_party_sync_snapshot(ctx)
        depth = ctx.instance_variable_get(:@anil_manual_lock_depth).to_i + 1
        ctx.instance_variable_set(:@anil_manual_lock_depth, depth)
        send_manual_lock_state(true, reason) if depth == 1
        before_snapshot
      rescue => e
        AnilLanRework.log("begin_manual_lock error #{e.class}: #{e.message}")
        nil
      end

      def end_manual_lock(reason = nil, before_snapshot = nil, ctx = nil)
        ctx ||= @active_context
        return unless manual_lock_supported?(ctx)
        depth = [ctx.instance_variable_get(:@anil_manual_lock_depth).to_i - 1, 0].max
        ctx.instance_variable_set(:@anil_manual_lock_depth, depth)
        if depth == 0
          queue_outbound_party_sync_if_changed(before_snapshot, reason, ctx)
          send_manual_lock_state(false, reason)
        end
      rescue => e
        AnilLanRework.log("end_manual_lock error #{e.class}: #{e.message}")
      end

      def with_manual_lock(reason = nil)
        ctx = @active_context
        supported = manual_lock_supported?(ctx)
        return yield unless supported
        before_snapshot = begin_manual_lock(reason, ctx)
        with_battle_wait { yield }
      ensure
        end_manual_lock(reason, before_snapshot, ctx) if supported
      end

      def wait_for_remote_manual_lock(waiting_text = nil, timeout = AnilLanRework::TURN_TIMEOUT)
        ctx = @active_context
        return false unless manual_lock_supported?(ctx)
        return false if local_manual_lock?(ctx)
        pump_network
        locked = remote_manual_lock?(ctx)
        return false unless locked

        # Debounce: só mostra a janela de espera se o lock remoto persistir por um
        # tempo mínimo. Locks transitórios (ex.: um battle_manual_lock adiantado/
        # bufferizado aplicado no build do contexto durante um atraso de carregamento
        # do bphase) piscavam com um reason já obsoleto ("exp..."). Se o lock cair
        # dentro dessa janela, não renderizamos nada.
        debounce_until = Time.now.to_f + 0.20
        while Time.now.to_f < debounce_until
          break if coop_remote_sync_disabled?(ctx)
          break if remote_coop_eliminated_marked?(ctx)
          break if ctx.instance_variable_get(:@anil_battle_end_received) == true
          break unless AnilLanRework.connected?
          pump_network
          break unless remote_manual_lock?(ctx)
          AnilLanRework::BattleSync.update_battle_graphics(ctx) rescue nil
          Input.update rescue nil
        end
        # Passado o tempo mínimo, só segue se o lock ainda é real e a batalha continua.
        return false unless remote_manual_lock?(ctx)
        return false if coop_remote_sync_disabled?(ctx) || remote_coop_eliminated_marked?(ctx)
        return false if ctx.instance_variable_get(:@anil_battle_end_received) == true
        return false unless AnilLanRework.connected?

        current_text = waiting_text || manual_wait_text
        viewport, window = build_wait_window(current_text)
        
        # PvP logging
        lock_reason = ctx.instance_variable_get(:@anil_remote_manual_reason) || 'none'
        if ctx.mode == :pvp
          turn = ctx.battle ? (ctx.battle.turnCount.to_i rescue "nil") : "nil"
          AnilLanRework.log(
            "pvp manual lock wait start battle_id=#{ctx.battle_id} mode=pvp client_index=#{ctx.client_index} turn=#{turn} reason=#{lock_reason} timeout=#{timeout}"
          )
        end

        started = Time.now.to_f
        effective_timeout = timeout
        absolute_deadline = nil
        if ctx.mode == :pvp && timeout && timeout > 0
          absolute_deadline = started + (timeout * 2.0)
        end

        with_battle_wait do
          loop do
            break if coop_remote_sync_disabled?(ctx)
            break if remote_coop_eliminated_marked?(ctx)
            pump_network
            break if ctx.instance_variable_get(:@anil_battle_end_received) == true
            locked = remote_manual_lock?(ctx)
            break unless locked
            break unless AnilLanRework.connected?
            
            # --- ATUALIZAÇÃO SUPERIOR: Reset de temporizador ---
            # Impede timeout enquanto o parceiro estiver ativamente em uma tela de diálogo
            started = Time.now.to_f
            if absolute_deadline
              absolute_deadline = started + (effective_timeout * 2.0)
            end
            
            if timeout && timeout > 0 && (Time.now.to_f - started) >= timeout
              if ctx.mode == :pvp
                turn = ctx.battle ? (ctx.battle.turnCount.to_i rescue "nil") : "nil"
                AnilLanRework.log(
                  "pvp manual lock wait timeout battle_id=#{ctx.battle_id} mode=pvp client_index=#{ctx.client_index} turn=#{turn} reason=#{lock_reason} absolute=#{absolute_deadline ? (Time.now.to_f >= absolute_deadline) : false}"
                )
              end
              break
            end
            
            if absolute_deadline && Time.now.to_f >= absolute_deadline
              if ctx.mode == :pvp
                turn = ctx.battle ? (ctx.battle.turnCount.to_i rescue "nil") : "nil"
                AnilLanRework.log(
                  "pvp manual lock wait absolute timeout battle_id=#{ctx.battle_id} mode=pvp client_index=#{ctx.client_index} turn=#{turn} reason=#{lock_reason}"
                )
              end
              break
            end

            # Atualiza o texto da janela de espera caso o parceiro mude o reason (ex: exp_phase -> level_up)
            new_text = manual_wait_text
            if window && new_text != current_text
              window.text = new_text
              center_wait_window!(window, new_text)
              current_text = new_text
            end
            
            AnilLanRework::BattleSync.update_battle_graphics(ctx) rescue nil
            Input.update rescue nil
            window.update rescue nil
          end
        end
        locked
      ensure
        dispose_wait_window(viewport, window)
      end
    end
  end
end

AnilLanRework.log("AnilLanRework_CoopLockPatch (Manual Lock Sync v3) loaded OK")


# Gancho do atraso das faixas REMOVIDO 2026-07-31 (ver nota no build_wait_window
# do 000d): em jogo nao aparecia aviso nenhum.
module AnilLanRework
  ATRASO_DA_FAIXA = 2.0 unless const_defined?(:ATRASO_DA_FAIXA)
end
