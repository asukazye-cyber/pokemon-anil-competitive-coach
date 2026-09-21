#===============================================================================
# MOD: 031_Multiplayer_Coop_Battle_Patch.rb
#-------------------------------------------------------------------------------
# Corrige a dessincronização nas trocas de Pokémon (Switch) durante batalhas coop.
# Restaura o comportamento original e testado do motor coop decompilado.
#===============================================================================

module AnilLanRework
  module BattleSync
    class << self
      # 1. Ajusta o envio da escolha de troca para coop (sempre slot = 0)
      def send_switch_choice(battle, idx_battler, idx_party)
        return unless @active_context && AnilLanRework.connected?
        
        slot = if @active_context.mode == :coop
          0
        else
          order = begin
            battle.pbGetOpposingIndicesInOrder(1).reverse
          rescue
            [idx_battler]
          end
          order.index(idx_battler) || 0
        end

        AnilLanRework.log("battle send switch battle_id=#{@active_context.battle_id} battler=#{idx_battler} party=#{idx_party} slot=#{slot}")
        AnilLanRework.connection.send_packet("battle_switch",
          "to_id"           => @active_context.partner_id,
          "battle_id"       => @active_context.battle_id,
          "slot"            => slot,
          "switch_index"    => idx_party.to_i,
          "switch_relative" => (@active_context.mode == :coop ? coop_relative_party_index_for(battle, idx_battler, idx_party) : nil)
        )
        AnilLanRework.connection.flush_batch
      end

      # 2. Retorna a busca simples do pacote de troca sem tradução (direct search)
      def next_remote_switch(expected_slot = nil)
        return nil unless @active_context
        return @active_context.pending_switches.shift if expected_slot.nil?
        index = @active_context.pending_switches.index { |packet| packet["slot"].to_i == expected_slot.to_i }
        index ? @active_context.pending_switches.delete_at(index) : nil
      end
    end
  end
end

if defined?(Battle)
  class Battle
    alias patch_coop_original_pbSwitchInBetween pbSwitchInBetween unless method_defined?(:patch_coop_original_pbSwitchInBetween)

    def pbSwitchInBetween(idxBattler, checkLaxOnly = false, canCancel = false)
      ctx = AnilLanRework::BattleSync.active_context rescue nil
      return patch_coop_original_pbSwitchInBetween(idxBattler, checkLaxOnly, canCancel) unless ctx

      if ctx.mode == :coop
        local_slot, remote_slot = AnilLanRework::BattleSync.coop_slots_for(self)

        # 1. Caso o slot seja do parceiro remoto e ele já foi eliminado:
        # O jogador ativo local deve preencher o slot usando a sua própria equipe!
        if idxBattler == remote_slot && AnilLanRework::BattleSync.remote_coop_eliminated?(ctx)
          if ctx.instance_variable_get(:@anil_remote_coop_fled) == true
            pbDisplay(_INTL("Seu parceiro fugiu! Escolha um Pokémon de sua equipe para continuar lutando!"))
          else
            pbDisplay(_INTL("Seu parceiro foi derrotado! Escolha um Pokémon de sua equipe para continuar lutando!"))
          end
          choice = anil_rework_original_pbSwitchInBetween(idxBattler, checkLaxOnly, canCancel)
          # Envia a escolha para o parceiro que está assistindo (se conectado/assistindo)
          if choice && choice >= 0 && !AnilLanRework::BattleSync.coop_remote_sync_disabled?(ctx)
            AnilLanRework::BattleSync.send_switch_choice(self, idxBattler, choice)
          end
          return choice
        end

        # 2. Caso o jogador local já esteja eliminado e esteja assistindo (spectator):
        # Ele deve esperar que o parceiro ativo envie o Pokémon para preencher o slot local.
        if idxBattler == local_slot && AnilLanRework::BattleSync.local_coop_eliminated?(ctx)
          AnilLanRework.log("coop fainted local slot wait for remote active player choice")
          packet = AnilLanRework::BattleSync.wait_for_remote_switch(0)
          if packet
            return if !packet["switch_index"] && !packet["switch_relative"]
            if packet.key?("switch_relative")
              translated = AnilLanRework::BattleSync.coop_absolute_party_index_for(self, remote_slot, packet["switch_relative"])
              AnilLanRework.log("coop fainted local slot recv remote switch translated=#{translated.inspect}")
              return translated
            end
            return packet["switch_index"].to_i if packet["switch_index"]
          end
          return nil
        end

        # 3. Fluxo cooperativo padrão quando ambos estão ativos:
        if idxBattler == local_slot
          AnilLanRework.log("coop local switch prompt battle_id=#{ctx.battle_id} battler=#{idxBattler} local_slot=#{local_slot.inspect} remote_slot=#{remote_slot.inspect}")
          choice = if AnilLanRework::BattleSync.respond_to?(:with_manual_lock)
            AnilLanRework::BattleSync.with_manual_lock("switch_prompt") do
              anil_rework_original_pbSwitchInBetween(idxBattler, checkLaxOnly, canCancel)
            end
          else
            anil_rework_original_pbSwitchInBetween(idxBattler, checkLaxOnly, canCancel)
          end
          AnilLanRework::BattleSync.send_switch_choice(self, idxBattler, choice) if choice && choice >= 0
          return choice
        elsif idxBattler == remote_slot
          AnilLanRework.log("coop remote switch wait battle_id=#{ctx.battle_id} battler=#{idxBattler} local_slot=#{local_slot.inspect} remote_slot=#{remote_slot.inspect}")
          packet = AnilLanRework::BattleSync.wait_for_remote_switch(0)
          if packet
            return if !packet["switch_index"] && !packet["switch_relative"]
            if packet.key?("switch_relative")
              translated = AnilLanRework::BattleSync.coop_absolute_party_index_for(self, idxBattler, packet["switch_relative"])
              AnilLanRework.log("coop remote switch recv battle_id=#{ctx.battle_id} battler=#{idxBattler} translated=#{translated.inspect}")
              return translated
            end
            return packet["switch_index"].to_i if packet["switch_index"]
          end
          AnilLanRework.log("coop remote switch timeout fallback battle_id=#{ctx.battle_id}")
        end
        return anil_rework_original_pbSwitchInBetween(idxBattler, checkLaxOnly, canCancel)
      end

      patch_coop_original_pbSwitchInBetween(idxBattler, checkLaxOnly, canCancel)
    end
  end
end

AnilLanRework.log("AnilLanRework_CoopBattlePatch (Switching Sync v3) loaded OK")
