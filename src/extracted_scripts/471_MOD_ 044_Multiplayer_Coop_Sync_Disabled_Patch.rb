#===============================================================================
# MOD: 044_Multiplayer_Coop_Sync_Disabled_Patch.rb
#-------------------------------------------------------------------------------
# Garante o funcionamento de batalha em dupla 100% offline local (sem delays de rede)
# no momento em que a sincronizacao remota cooperativa for desabilitada
# (ex: quando o parceiro é eliminado e vai ao Centro Pokemon, ou desconecta).
#===============================================================================

module AnilLanRework
  module BattleSyncEvolution
    class << self
      alias disabled_patch_original_check_evolution_and_sync_multipleyer_from_pokemon check_evolution_and_sync_multipleyer_from_pokemon rescue nil
      def check_evolution_and_sync_multipleyer_from_pokemon(pkmn_or_battler)
        ctx = BattleSync.active_context rescue nil
        if ctx && ctx.mode == :coop && BattleSync.coop_remote_sync_disabled?(ctx)
          AnilLanRework.log("evolution disabled_patch: coop remote sync disabled, bypassing check_evolution_and_sync.")
          return
        end
        if respond_to?(:disabled_patch_original_check_evolution_and_sync_multipleyer_from_pokemon)
          disabled_patch_original_check_evolution_and_sync_multipleyer_from_pokemon(pkmn_or_battler) rescue nil
        end
      end
    end
  end
end

if defined?(Battle)
  class Battle
    # 1. pbCommandPhase (Desativado: incorporado de forma nativa e unificada no 000d)
    # 2. pbCommandPhaseLoop (Desativado: incorporado de forma nativa e unificada no 000d)

    # 3. pbAttackPhaseItems
    alias disabled_patch_original_pbAttackPhaseItems pbAttackPhaseItems unless method_defined?(:disabled_patch_original_pbAttackPhaseItems)
    def pbAttackPhaseItems(*args)
      ctx = AnilLanRework::BattleSync.active_context rescue nil
      if ctx && ctx.mode == :coop && AnilLanRework::BattleSync.coop_remote_sync_disabled?(ctx)
        AnilLanRework.log("disabled_patch: pbAttackPhaseItems bypassing coop sync")
        begin
          return anil_rework_original_pbAttackPhaseItems(*args)
        rescue => e
          AnilLanRework.log("disabled_patch: pbAttackPhaseItems fallback due to #{e.class}: #{e.message}")
          return disabled_patch_original_pbAttackPhaseItems(*args)
        end
      end
      disabled_patch_original_pbAttackPhaseItems(*args)
    end

    # 4. pbAutoChooseMove
    alias disabled_patch_original_pbAutoChooseMove pbAutoChooseMove unless method_defined?(:disabled_patch_original_pbAutoChooseMove)
    def pbAutoChooseMove(*args)
      ctx = AnilLanRework::BattleSync.active_context rescue nil
      if ctx && ctx.mode == :coop && AnilLanRework::BattleSync.coop_remote_sync_disabled?(ctx)
        AnilLanRework.log("disabled_patch: pbAutoChooseMove bypassing coop sync")
        begin
          return anil_rework_original_pbAutoChooseMove(*args)
        rescue => e
          AnilLanRework.log("disabled_patch: pbAutoChooseMove fallback due to #{e.class}: #{e.message}")
          return disabled_patch_original_pbAutoChooseMove(*args)
        end
      end
      disabled_patch_original_pbAutoChooseMove(*args)
    end

    # 5. pbSwitchInBetween
    alias disabled_patch_original_pbSwitchInBetween pbSwitchInBetween unless method_defined?(:disabled_patch_original_pbSwitchInBetween)
    def pbSwitchInBetween(*args)
      ctx = AnilLanRework::BattleSync.active_context rescue nil
      if ctx && ctx.mode == :coop && AnilLanRework::BattleSync.coop_remote_sync_disabled?(ctx)
        AnilLanRework.log("disabled_patch: pbSwitchInBetween bypassing coop sync")
        begin
          return patch_coop_original_pbSwitchInBetween(*args)
        rescue => e
          AnilLanRework.log("disabled_patch: pbSwitchInBetween fallback due to #{e.class}: #{e.message}")
          return disabled_patch_original_pbSwitchInBetween(*args)
        end
      end
      disabled_patch_original_pbSwitchInBetween(*args)
    end

    # 6. pbGetReplacementPokemonIndex
    alias disabled_patch_original_pbGetReplacementPokemonIndex pbGetReplacementPokemonIndex unless method_defined?(:disabled_patch_original_pbGetReplacementPokemonIndex)
    def pbGetReplacementPokemonIndex(*args)
      ctx = AnilLanRework::BattleSync.active_context rescue nil
      if ctx && ctx.mode == :coop && AnilLanRework::BattleSync.coop_remote_sync_disabled?(ctx)
        AnilLanRework.log("disabled_patch: pbGetReplacementPokemonIndex bypassing coop sync")
        begin
          return anil_rework_original_pbGetReplacementPokemonIndex(*args)
        rescue => e
          AnilLanRework.log("disabled_patch: pbGetReplacementPokemonIndex fallback due to #{e.class}: #{e.message}")
          return disabled_patch_original_pbGetReplacementPokemonIndex(*args)
        end
      end
      disabled_patch_original_pbGetReplacementPokemonIndex(*args)
    end

    # 7. pbEORSwitch
    alias disabled_patch_original_pbEORSwitch pbEORSwitch unless method_defined?(:disabled_patch_original_pbEORSwitch)
    def pbEORSwitch(favorDraws = false)
      ctx = AnilLanRework::BattleSync.active_context rescue nil
      if ctx && ctx.mode == :coop && AnilLanRework::BattleSync.coop_remote_sync_disabled?(ctx)
        AnilLanRework.log("disabled_patch: custom pbEORSwitch running for local-only coop mode")
        return if @decision > 0 && !favorDraws
        return if @decision == 5 && favorDraws
        pbJudge
        return if @decision > 0

        switched = []
        loop do
          switched.clear
          local_slot, remote_slot = AnilLanRework::BattleSync.coop_slots_for(self) rescue [0, 2]
          
          @battlers.each do |b|
            next if !b || !b.fainted?
            idxBattler = b.index
            
            # Se for o slot remoto e a batalha reduziu para single, ignora completamente
            if idxBattler == remote_slot && pbSideSize(0) == 1
              next
            end
            
            next if !pbCanChooseNonActive?(idxBattler)
            
            if idxBattler == remote_slot
              # Se for o slot do parceiro e restam 2 inimigos selvagens (batalha dupla),
              # abre diretamente a party screen para o jogador local escolher o substituto sem perguntar "Quer mandar outro Pokemon?".
              idxPlayerPartyNew = pbGetReplacementPokemonIndex(idxBattler)
              if idxPlayerPartyNew >= 0
                pbRecallAndReplace(idxBattler, idxPlayerPartyNew)
                switched.push(idxBattler)
              end
            elsif pbOwnedByPlayer?(idxBattler)
              # Pokémon do próprio jogador local desmaiou
              if trainerBattle?
                idxPlayerPartyNew = pbGetReplacementPokemonIndex(idxBattler)
                pbRecallAndReplace(idxBattler, idxPlayerPartyNew)
                switched.push(idxBattler)
              else
                switch = false
                if pbDisplayConfirm(_INTL("¿Quieres sacar a otro Pokémon?"))
                  switch = true
                else
                  switch = (pbRun(idxBattler, true) <= 0)
                end
                if switch
                  idxPlayerPartyNew = pbGetReplacementPokemonIndex(idxBattler)
                  pbRecallAndReplace(idxBattler, idxPlayerPartyNew)
                  switched.push(idxBattler)
                end
              end
            else
              # Oponente fainted
              next if b.wild?
              idxPartyNew = pbSwitchInBetween(idxBattler)
              pbRecallAndReplace(idxBattler, idxPartyNew)
              switched.push(idxBattler)
            end
          end
          break if switched.length == 0
          pbOnBattlerEnteringBattle(switched)
        end
        return
      end
      disabled_patch_original_pbEORSwitch(favorDraws)
    end
  end
end

if defined?(Battle::Battler)
  class Battle::Battler
    # 8. pbReduceHP
    alias disabled_patch_original_pbReduceHP pbReduceHP unless method_defined?(:disabled_patch_original_pbReduceHP)
    def pbReduceHP(*args)
      ctx = AnilLanRework::BattleSync.active_context rescue nil
      if ctx && ctx.mode == :coop && AnilLanRework::BattleSync.coop_remote_sync_disabled?(ctx)
        AnilLanRework.log("disabled_patch: pbReduceHP bypassing coop sync for #{self.name rescue 'pkmn'}")
        begin
          return anil_rework_original_battler_pbReduceHP(*args)
        rescue => e
          AnilLanRework.log("disabled_patch: pbReduceHP fallback due to #{e.class}: #{e.message}")
          return disabled_patch_original_pbReduceHP(*args)
        end
      end
      disabled_patch_original_pbReduceHP(*args)
    end

    # 9. pbRecoverHP
    alias disabled_patch_original_pbRecoverHP pbRecoverHP unless method_defined?(:disabled_patch_original_pbRecoverHP)
    def pbRecoverHP(*args)
      ctx = AnilLanRework::BattleSync.active_context rescue nil
      if ctx && ctx.mode == :coop && AnilLanRework::BattleSync.coop_remote_sync_disabled?(ctx)
        AnilLanRework.log("disabled_patch: pbRecoverHP bypassing coop sync for #{self.name rescue 'pkmn'}")
        begin
          return anil_rework_original_battler_pbRecoverHP(*args)
        rescue => e
          AnilLanRework.log("disabled_patch: pbRecoverHP fallback due to #{e.class}: #{e.message}")
          return disabled_patch_original_pbRecoverHP(*args)
        end
      end
      disabled_patch_original_pbRecoverHP(*args)
    end
  end
end

