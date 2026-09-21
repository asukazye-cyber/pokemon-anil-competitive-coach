#===============================================================================
# MOD: 030_Multiplayer_Coop_Invite_Patch.rb
#-------------------------------------------------------------------------------
# Sobrescreve o comportamento de início e convite de batalha cooperativa (coop)
# para diferenciar revanches (rematch) de batalhas comuns.
# - Batalhas normais e selvagens disparam instantaneamente sem esperar.
# - Revanches (rematch) aguardam o host pressionar C para fechar o diálogo.
#===============================================================================

module AnilLanRework
  module BattleSync
    class << self
      # 1. Sobrescreve o convite para aceitar a classe "rematch"
      alias patch_original_update_pending_coop_invite update_pending_coop_invite unless method_defined?(:patch_original_update_pending_coop_invite)
      
      def update_pending_coop_invite
        return unless @pending_coop_invite
        return unless $scene.is_a?(Scene_Map)
        return if local_player_menu_open?
        return if (pbMapInterpreterRunning? rescue false)
        return if $game_temp&.message_window_showing

        packet = @pending_coop_invite
        @pending_coop_invite = nil
        sender_id = packet["sender_id"].to_s
        peer = AnilLanRework.players[sender_id]
        sender_name = peer && !peer.name.to_s.empty? ? peer.name.to_s : sender_id
        
        # Traduz a revanche e a batalha de treinador para o mesmo texto amigável
        is_trainer = ["trainer", "rematch"].include?(packet["kind"].to_s)
        battle_kind = is_trainer ? "batalha contra treinador" : "batalha selvagem"
        
        accepted_raw = pbConfirmMessage(AnilLanRework.ui_format("{1} quer iniciar uma {2} em coop. Participar?", sender_name, battle_kind))
        accepted = (accepted_raw == true || accepted_raw == 0)
        
        AnilLanRework.connection.send_packet("battle_response",
          "to_id"      => sender_id,
          "battle_id"  => packet["battle_id"].to_s,
          "accepted"   => accepted,
          "party"      => accepted ? AnilLanRework::Serializer.serialize_party($player.party) : nil
        )
        if accepted
          packet["accepted_at"] = Time.now.to_f
          @pending_coop_start = packet
        else
          @pending_coop_start = nil
          @coop_start_ready_from.delete(sender_id) if @coop_start_ready_from rescue nil
          clear_peer_party_cache(peer, "local_decline")
          clear_pending_coop_start_wait_window
        end
      end

      # 2. Sobrescreve o início pendente para aguardar apenas em caso de revanche
      def update_pending_coop_start
        return unless @pending_coop_start
        return unless $scene.is_a?(Scene_Map)

        packet = @pending_coop_start
        is_rematch = (packet["kind"].to_s == "rematch")

        # Se for revanche, aguarda o sinal de start do host (após ele fechar o diálogo)
        if is_rematch
          is_ready = @coop_start_ready_from && @coop_start_ready_from[packet["sender_id"].to_s]
          if !is_ready
            return if $game_temp&.message_window_showing
            ensure_pending_coop_start_wait_window(waiting_text("Aguardando parceiro iniciar a revanche..."))
            return
          end
        else
          # Batalha comum (treinador comum ou selvagem): não pode ficar presa se houver alguma janela de diálogo do cliente aberta
          return if $game_temp&.message_window_showing
        end

        return if $game_temp&.player_transferring

        # Dispara
        @pending_coop_start = nil
        clear_pending_coop_start_wait_window
        sender_id = packet["sender_id"].to_s
        @coop_start_ready_from.delete(sender_id) if @coop_start_ready_from rescue nil
        start_coop_battle(packet)
      end

      # 3. Garante que "rematch" seja processada como "trainer" no início da batalha
      alias patch_original_start_coop_battle start_coop_battle unless method_defined?(:patch_original_start_coop_battle)

      def start_coop_battle(packet)
        if packet["kind"].to_s == "rematch"
          sender_id = packet["sender_id"].to_s
          peer = AnilLanRework.players[sender_id]
          return unless peer
          
          trainer_keys = Array(packet["trainer_keys"]).map(&:to_s).reject(&:empty?)
          rules = {}
          rules["coop_trainer_keys"] = trainer_keys unless trainer_keys.empty?
          
          AnilLanRework.log("start_coop_battle (rematch) battle_id=#{packet['battle_id']} peer=#{sender_id} trainer_keys=#{trainer_keys.inspect}")
          
          activate_context(
            battle_id: packet["battle_id"].to_s,
            mode: :coop,
            client_index: 1,
            partner_id: sender_id,
            seed: packet["seed"].to_i,
            rules: rules,
            foe_party: nil
          )
          inject_partner(peer, packet["party"], packet["battle_id"])
          
          if packet["battle_rules"].is_a?(Hash) && !packet["battle_rules"].empty?
            $game_temp.clear_battle_rules rescue nil
            packet["battle_rules"].each do |rule_key, rule_val|
              if rule_val.nil? || rule_val == true
                setBattleRule(rule_key.to_s) rescue nil
              else
                setBattleRule(rule_key.to_s, rule_val) rescue nil
              end
            end
          end
          boss_on = (packet["boss_battle"] == true || packet["boss_battle"].to_s == "true")
          # O switch de boss e GLOBAL e vive no save. Este caminho (revanche)
          # escrevia sem guardar o valor anterior, e o restaurar_switches_de_boss!
          # do clear_context nao tinha nada para repor — uma revanche coop contra
          # um boss deixava o switch 45 ligado PARA SEMPRE, e dai em diante todas
          # as batalhas, coop ou nao, desenhavam a vida do inimigo como boss.
          # Os outros dois pontos de escrita (000d e 001) ja guardavam; faltava este.
          AnilLanRework::BattleSync.guardar_switches_de_boss! rescue nil
          if defined?(BossBattleConstants) && $game_switches
            $game_switches[BossBattleConstants::BOSS_BATTLE_SWITCH] = boss_on rescue nil
          end

          trainers = AnilLanRework::Serializer.deserialize_trainers(packet["foe_trainers"])
          ensure_trainer_rule
          if packet["battle_size"] && !packet["battle_size"].to_s.empty?
            setBattleRule(packet["battle_size"].to_s) rescue nil
          end
          
          if TrainerBattle.respond_to?(:anil_rework_original_start_core)
            TrainerBattle.anil_rework_original_start_core(*trainers)
          elsif TrainerBattle.respond_to?(:start_core)
            TrainerBattle.start_core(*trainers)
          end
        else
          patch_original_start_coop_battle(packet)
        end
      rescue => e
        AnilLanRework.log("start_coop_battle (patch) error #{e.class}: #{e.message}")
        $game_temp.clear_battle_rules rescue nil
        remove_partner
      end
    end
  end
end

AnilLanRework.log("AnilLanRework_CoopInvitePatch (Separate Module Rematch Sync v3) loaded OK")
