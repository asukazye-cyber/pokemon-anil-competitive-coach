#===============================================================================
# MOD: 033_Multiplayer_Coop_Exp_Patch.rb
#-------------------------------------------------------------------------------
# Corrige o ganho de Experiência (EXP) e EVs em batalhas cooperativas (coop).
# Garante que cada jogador ganhe EXP e EVs exclusivamente para os seus próprios Pokémon,
# eliminando o bug que impedia o cliente (segundo jogador) de ganhar experiência.
#===============================================================================

if defined?(Battle)
  class Battle
    # 1. Corrige o pbGainExp para coop e pvp
    alias patch_exp_original_pbGainExp pbGainExp unless method_defined?(:patch_exp_original_pbGainExp)

    def pbGainExp
      ctx = AnilLanRework::BattleSync.active_context rescue nil
      if ctx && ctx.mode == :pvp
        AnilLanRework.log("pvp: XP gain skipped battle_id=#{ctx.battle_id}")
        return
      end

      # Ignora temporariamente NO_EXP_SWITCH se estiver conectado ao multiplayer,
      # prevenindo desyncs de switches locais (ex: switch 661 ativada em uma das máquinas)
      old_no_exp = nil
      if AnilLanRework.connected?
        old_no_exp = $game_switches[NO_EXP_SWITCH] rescue nil
        $game_switches[NO_EXP_SWITCH] = false rescue nil
      end

      begin
        if ctx && ctx.mode == :coop
          if AnilLanRework::BattleSync.coop_remote_sync_disabled?(ctx)
            patch_exp_original_pbGainExp
          else
            AnilLanRework::BattleSync.with_manual_lock("exp_phase") do
              AnilLanRework.log("pbGainExp: entering anil_coop_pbGainExp")
              anil_coop_pbGainExp
            end
            anil_coop_exp_barrier(ctx)
          end
        else
          patch_exp_original_pbGainExp
        end
      ensure
        # Restaura o estado original da switch local
        if old_no_exp != nil
          $game_switches[NO_EXP_SWITCH] = old_no_exp rescue nil
        end
      end
    end

    def anil_coop_exp_barrier(ctx)
      return unless ctx && ctx.mode == :coop && AnilLanRework.connected?
      return if AnilLanRework::BattleSync.coop_remote_sync_disabled?(ctx)

      turn = @turnCount.to_i rescue 0

      AnilLanRework::BattleSync.queue_outbound_party_sync rescue nil
      party_payload = AnilLanRework::BattleSync.consume_outbound_party_sync rescue nil
      if party_payload && ctx.partner_id
        AnilLanRework.connection.send_packet("battle_action",
          "to_id"      => ctx.partner_id,
          "battle_id"  => ctx.battle_id,
          "actions"    => [],
          "party_sync" => party_payload
        )
      end
      AnilLanRework.connection.flush_batch rescue nil

      AnilLanRework::BattleSync.send_phase_sync("exp_complete", "ready", "turn" => turn)
      AnilLanRework.connection.flush_batch rescue nil

      wait_text = AnilLanRework::BattleSync.waiting_text("Aguardando parceiro terminar EXP...")
      viewport, window = AnilLanRework::BattleSync.build_wait_window(wait_text)
      started = Time.now.to_f
      timeout = 120.0

      begin
        loop do
          break if AnilLanRework::BattleSync.coop_remote_sync_disabled?(ctx)
          AnilLanRework::BattleSync.pump_network
          packet = AnilLanRework::BattleSync.next_remote_phase_sync("exp_complete", "ready", turn, ctx)
          if packet
            AnilLanRework::BattleSync.flush_remote_party_refresh rescue nil
            AnilLanRework.log("coop exp barrier synced turn=#{turn}")
            break
          end

          break unless AnilLanRework.connected?

          if AnilLanRework::BattleSync.remote_manual_lock?(ctx)
            started = Time.now.to_f
            lock_text = AnilLanRework::BattleSync.manual_wait_text rescue wait_text
            window.text = lock_text if window
          elsif window && window.text.to_s != wait_text
            window.text = wait_text
          end

          if Time.now.to_f - started >= timeout
            AnilLanRework.log("coop exp barrier timeout turn=#{turn}")
            break
          end

          AnilLanRework::BattleSync.update_battle_graphics(ctx) rescue nil
          Input.update rescue nil
          window.update rescue nil
          sleep(0.016)
        end
      ensure
        AnilLanRework::BattleSync.dispose_wait_window(viewport, window)
      end
    end

    def anil_coop_pbGainExp
      switch_val = $game_switches[NO_EXP_SWITCH] rescue nil
      AnilLanRework.log("anil_coop_pbGainExp: active! NO_EXP_SWITCH=#{switch_val} old_internalBattle=#{@internalBattle} old_expGain=#{@expGain}")
      @internalBattle = true
      @expGain = true
      
      # Bypass total de NO_EXP_SWITCH em cooperativo.
      # A switch NO_EXP_SWITCH já é contornada temporariamente durante a pbGainExp.
      
      @scene.pbWildBattleSuccess if wildBattle? && pbAllFainted?(1) && !pbAllFainted?(0)

      old_lvls = $player.party.map { |p| p.level } rescue []
      expAll = $player.has_exp_all || $bag.has?(:EXPALL) rescue false
      p1 = pbParty(0)
      AnilLanRework.log("anil_coop_pbGainExp: processing #{@battlers.length} battlers. Combined party size: #{p1.length}")

      @battlers.each_with_index do |b, idx|
        next unless b
        next if !b.opposes?
        if b.participants.length == 0
          AnilLanRework.log("XP SKIP: battler #{idx} (#{b.name}) has 0 participants")
          next
        end
        if !b.fainted? && !b.captured
          AnilLanRework.log("XP SKIP: battler #{idx} (#{b.name}) is not fainted/captured")
          next
        end

        AnilLanRework.log("XP TARGET: battler #{idx} (#{b.name}) - Participants: #{b.participants.inspect}")

        # 1. Conta todos os Pokémon aptos que participaram (de ambos os jogadores)
        numPartic = 0
        b.participants.each do |partic|
          next unless p1[partic]&.able?
          numPartic += 1
        end

        # 2. Registra os Pokémon com Exp Share (Item ou Flag expshare) de ambos os jogadores
        expShare = []
        if !expAll
          p1.each_with_index do |pkmn, i|
            next if !pkmn || !pkmn.able?
            item_has = (pkmn.hasItem?(:EXPSHARE) || GameData::Item.try_get(@initialItems[0][i]) == :EXPSHARE rescue false)
            next if !item_has && (!pkmn.respond_to?(:expshare) || !pkmn.expshare)
            expShare.push(i)
          end
        end

        # 3. Processa o ganho de experiência e EVs
        if numPartic > 0 || expShare.length > 0 || expAll
          group_msg = (defined?(Settings::GROUP_EXP_SHARE_MESSAGE) ? Settings::GROUP_EXP_SHARE_MESSAGE : false)
          unGroupMessage = !group_msg && expShare.length > 0 && expShare.length > b.participants.length rescue false

          # A) Ganho de EXP e EVs para participantes e Exp Share ativos
          p1.each_with_index do |pkmn, i|
            next if !pkmn || !pkmn.able?
            next unless b.participants.include?(i) || expShare.include?(i)
            showMessage = b.participants.include?(i) || unGroupMessage ? true : false
            
            # Executa apenas se o Pokémon pertencer ao jogador local desta instância
            if $player.party.include?(pkmn)
              AnilLanRework.log("anil_coop_pbGainExp: calling pbGainExpOne for local pokemon #{pkmn.name} (index #{i})")
              pbGainEVsOne(i, b)
              pbGainExpOne(i, b, numPartic, expShare, expAll, showMessage)
            else
              AnilLanRework.log("anil_coop_pbGainExp: skipping pbGainExpOne for remote pokemon #{pkmn.name} (index #{i})")
            end
          end

          # Mensagem informativa de compartilhamento
          if !unGroupMessage && (expShare.length > numPartic && p1.length > 1) && !expAll
            pbDisplayPaused(_INTL("¡Tus otros Pokémon também ganharam pontos de experiência!")) rescue nil
          end

          # B) Ganho de EXP e EVs para o restante do time se Exp All estiver ativo
          if expAll
            showMessage = true
            p1.each_with_index do |pkmn, i|
              next if !pkmn || !pkmn.able?
              next if b.participants.include?(i) || expShare.include?(i)
              
              if $player.party.include?(pkmn)
                if showMessage && (expShare.length > numPartic && p1.length > 1)
                  pbDisplayPaused(_INTL("¡Tus otros Pokémon também ganharam pontos de experiência!")) rescue nil
                end
                showMessage = false
                pbGainEVsOne(i, b)
                pbGainExpOne(i, b, numPartic, expShare, expAll, false)
              end
            end
          end
        end
        b.participants = []
      end

      new_lvls = $player.party.map { |p| p.level } rescue []
      if old_lvls != new_lvls
        AnilLanRework.log("coop: Level up detected in anil_coop_pbGainExp, forcing party sync")
        AnilLanRework::BattleSync.queue_outbound_party_sync rescue nil
      end
    end

    # 2. Corrige o pbGainExpOne para coop e pvp
    alias patch_exp_original_pbGainExpOne pbGainExpOne unless method_defined?(:patch_exp_original_pbGainExpOne)

    def pbGainExpOne(idxParty, defeatedBattler, numPartic, expShare, expAll, showMessages = true)
      ctx = AnilLanRework::BattleSync.active_context rescue nil
      if ctx && ctx.mode == :pvp
        return nil
      end

      pkmn = pbParty(0)[idxParty] rescue nil
      
      if pkmn && (pkmn.hp == 0 || pkmn.fainted? || !pkmn.able?)
        AnilLanRework.log("pbGainExpOne: skipping fainted pokemon #{pkmn.name}")
        return nil
      end

      if ctx && ctx.mode == :coop && AnilLanRework::BattleSync.local_coop_eliminated?(ctx)
        AnilLanRework.log("pbGainExpOne: local player is eliminated (spectating), skipping XP gain.")
        return nil
      end

      before_lvl = pkmn ? pkmn.level : 0

      result = patch_exp_original_pbGainExpOne(idxParty, defeatedBattler, numPartic, expShare, expAll, showMessages)

      after_lvl = pkmn ? pkmn.level : 0
      if after_lvl > before_lvl && ctx && ctx.mode == :coop && AnilLanRework.connected?
        AnilLanRework.log("pbGainExpOne(coop): Level up detected #{before_lvl} -> #{after_lvl} for #{pkmn.name rescue '??'}")
        (AnilLanRework::EvoLogger.log("[EVO_TRACK] pbGainExpOne(coop): Level up detected #{before_lvl} -> #{after_lvl} for #{pkmn.name rescue '??'}. Chamando check_evolution_and_sync_multipleyer_from_pokemon") rescue nil)
        AnilLanRework::BattleSyncEvolution.check_evolution_and_sync_multipleyer_from_pokemon(pkmn)
      end

      result
    end

    # 3. Corrige o pbGainEVsOne para coop e pvp
    alias patch_exp_original_pbGainEVsOne pbGainEVsOne unless method_defined?(:patch_exp_original_pbGainEVsOne)

    def pbGainEVsOne(idxParty, defeatedBattler)
      ctx = AnilLanRework::BattleSync.active_context rescue nil
      if ctx && ctx.mode == :pvp
        return nil
      end

      pkmn = pbParty(0)[idxParty] rescue nil
      
      if pkmn && (pkmn.hp == 0 || pkmn.fainted? || !pkmn.able?)
        AnilLanRework.log("pbGainEVsOne: skipping fainted pokemon #{pkmn.name}")
        return nil
      end

      if ctx && ctx.mode == :coop && AnilLanRework::BattleSync.local_coop_eliminated?(ctx)
        AnilLanRework.log("pbGainEVsOne: local player is eliminated (spectating), skipping EV gain.")
        return nil
      end

      patch_exp_original_pbGainEVsOne(idxParty, defeatedBattler)
    end
  end
end

AnilLanRework.log("AnilLanRework_CoopExpPatch (EXP & EV Sync v3) loaded OK")
