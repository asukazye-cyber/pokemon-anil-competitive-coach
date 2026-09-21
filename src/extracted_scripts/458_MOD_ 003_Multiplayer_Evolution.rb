# encoding: UTF-8
# ==============================================================================
# SISTEMA DE EVOLUCAO SINCRONIZADA EM BATALHA COOP MULTIPLAYER
# Versao 1.0.0 - Monolito Integration (Optimized Edition)
# ==============================================================================

# Multiplayer BattleSyncEvolution Addon
AnilLanRework.log("BattleSyncEvolution Addon LOADED")
module AnilLanRework
  module BattleSyncEvolution
    EVOLUTION_ACK_TIMEOUT = EVOLUTION_LOCK_TIMEOUT rescue 480
    EVOLUTION_GLOW_FRAMES = EVOLUTION_GLOW_FRAMES rescue 48
    EVOLUTION_FLASH_FRAMES = EVOLUTION_FLASH_FRAMES rescue 8
    EVOLUTION_REAPPEAR_FRAMES = EVOLUTION_REAPPEAR_FRAMES rescue 12

    @evolution_in_progress = false
    @evolution_timer = 0
    @evolution_callbacks = {}

    class << self
      attr_accessor :evolution_in_progress
      attr_reader :evolution_timer
    end

    # ================================================================
    # DETECCAO DE EVOLUCAO
    # ================================================================

    def self.check_evolution_and_sync_multipleyer_from_pokemon(pkmn_or_battler)
      pkmn_obj = begin
        if pkmn_or_battler.is_a?(Battle::Battler)
          pkmn_or_battler.pokemon
        else
          pkmn_or_battler
        end
      rescue
        nil
      end
      AnilLanRework.log("check_evolution_and_sync: starting for #{pkmn_obj.name rescue '??'}")
      return unless pkmn_obj
      return unless pkmn_obj.is_a?(Pokemon) rescue false

      ctx = BattleSync.active_context rescue nil
      AnilLanRework.log("check_evolution_and_sync: ctx=#{ctx ? ctx.mode : 'nil'} connected=#{AnilLanRework.connected?}")
      return unless ctx && ctx.mode == :coop
      return unless AnilLanRework.connected?

      if pkmn_obj.hp == 0 || pkmn_obj.fainted? || !pkmn_obj.able?
        AnilLanRework.log("check_evolution_and_sync: skipping fainted pokemon #{pkmn_obj.name}")
        return
      end

      if BattleSync.local_coop_eliminated?(ctx)
        AnilLanRework.log("check_evolution_and_sync: local player is eliminated (spectating), skipping evolution.")
        return
      end

      pkmn = pkmn_obj

      # Usa check_evolution_on_level_up que é o método nativo do Essentials
      # e comprovadamente funciona (detectou Ralts -> KIRLIA nos testes)
      new_species = pkmn.check_evolution_on_level_up rescue nil
      AnilLanRework.log("check_evolution_and_sync: #{pkmn.name} lv#{pkmn.level} check_evolution_on_level_up=#{new_species.inspect}")
      
      if new_species && new_species != pkmn.species
        AnilLanRework.log("evolution DETECTED: #{pkmn.name} (LV#{pkmn.level}) -> #{new_species}")
        start_evolution_host(pkmn, new_species, ctx)
        return
      end
      AnilLanRework.log("check_evolution_and_sync: no evolution criteria met for #{pkmn.name}")
    end

    # ================================================================
    # FLUXO DO HOST
    # ================================================================

    def self.start_evolution_host(pkmn, new_species, ctx)
      return if @evolution_in_progress
      @evolution_in_progress = true

      old_species = pkmn.species
      old_name = pkmn.name.to_s

      battle = ctx.battle rescue nil
      battler = nil
      battler_idx = nil
      if battle
        battle.battlers.each do |b|
          next unless b && b.pokemon && b.pokemon.equal?(pkmn)
          battler = b
          battler_idx = b.index rescue 0
          break
        end
      end

      AnilLanRework.log("evolution HOST: #{old_name} -> #{new_species} battler=#{battler_idx.inspect} in_battle=#{!battler.nil?}")

      # Aplica a evolução no objeto Pokemon
      pkmn.species = new_species
      pkmn.calc_stats
      pkmn.ready_to_evolve = false if pkmn.respond_to?(:ready_to_evolve=)

      # Se o Pokémon está em campo, atualiza o battler
      if battler
        battler.form = pkmn.form if battler.respond_to?(:form=)
        battler.hp = pkmn.hp if battler.respond_to?(:hp=)
        battler.totalhp = pkmn.totalhp if battler.respond_to?(:totalhp=)
        battler.pbUpdate(true) rescue nil
      end

      full_data = AnilLanRework::Serializer.serialize_pokemon_full(pkmn) rescue nil

      BattleSync.begin_manual_lock("evolution:#{old_name}")
      BattleSync.update_manual_lock_reason("evolution:#{old_name}") rescue nil

      # Sincroniza o RNG e referência do battler
      rng_state = (ctx.rng ? ctx.rng.state : nil) rescue nil
      battler_ref = nil
      if battle && battler_idx
        battler_ref = AnilLanRework::BattleSync.serialize_coop_battler_reference(battle, battler_idx) rescue nil
      end

      # Envia o pacote de evolução para o parceiro
      AnilLanRework.connection.send_packet("battle_evolution",
        "to_id"       => ctx.partner_id,
        "battle_id"   => ctx.battle_id,
        "battler_idx" => battler_idx.nil? ? -1 : battler_idx,
        "battler_ref" => battler_ref,
        "old_species" => old_species.to_s,
        "new_species" => new_species.to_s,
        "full_data"   => full_data,
        "in_battle"   => !battler.nil?,
        "rng_state"   => rng_state,
        "timestamp"   => System.uptime.to_f
      )
      AnilLanRework.log("evolution: packet sent to #{ctx.partner_id} for #{new_species} rng_state=#{rng_state.inspect}")

      # Mostra mensagem de evolução na batalha
      if battle && battle.respond_to?(:pbDisplay)
        new_name = begin
          GameData::Species.get(new_species).name
        rescue
          new_species.to_s
        end
        battle.pbDisplay(_INTL("O que? {1} está evoluindo!", old_name)) rescue nil
        battle.pbDisplay(_INTL("{1} evoluiu para {2}!", old_name, new_name)) rescue nil
      end

      # Efeitos visuais apenas se o Pokémon está em campo
      if battler
        begin
          start_evolution_visuals(battler, new_species)
        rescue => e
          AnilLanRework.log("evolution: visual effect error: #{e.class}: #{e.message}")
        end
        wait_for_evolution_ack(ctx, battler_idx, new_species, old_name)
      else
        # Pokémon na party (não em campo) - evolução silenciosa
        AnilLanRework.log("evolution: silent evolution (not in battle field) #{old_name} -> #{new_species}")
        wait_for_evolution_ack_silent(ctx, new_species, old_name)
      end
    end

    def self.wait_for_evolution_ack(ctx, battler_idx, new_species, old_name)
      started = Time.now.to_f
      ack_received = false

      AnilLanRework.log("evolution: waiting for ACK battle_id=#{ctx.battle_id} battler=#{battler_idx}")

      wait_text = AnilLanRework::BattleSync.waiting_text("Aguardando parceiro terminar de assistir à evolução...")
      viewport, window = AnilLanRework::BattleSync.build_wait_window(wait_text)

      begin
        while Time.now.to_f - started < (EVOLUTION_ACK_TIMEOUT / 40.0)
          AnilLanRework.connection.tick rescue nil
          AnilLanRework.connection.drain do |packet|
            AnilLanRework::Router.route_packet(packet)
          end rescue nil

          if @evolution_callbacks["ack_#{ctx.battle_id}_#{battler_idx}"]
            ack_received = true
            break
          end

          AnilLanRework::BattleSync.update_battle_graphics(ctx) rescue nil
          Input.update rescue nil
          window.update rescue nil if window
          sleep(0.016)
        end
      ensure
        AnilLanRework::BattleSync.dispose_wait_window(viewport, window)
      end

      unless ack_received
        AnilLanRework.log("evolution: ACK TIMEOUT battle_id=#{ctx.battle_id} battler=#{battler_idx}")
      end

      finish_evolution_visuals(ctx.battle_id)
      BattleSync.end_manual_lock("evolution:#{old_name}")
      BattleSync.update_manual_lock_reason("exp_phase") rescue nil
      refresh_battler_after_evolution(ctx, battler_idx, new_species) if battler_idx

      @evolution_in_progress = false
      AnilLanRework.log("evolution: complete battle_id=#{ctx.battle_id} ack=#{ack_received}")
      
      # Envia a party atualizada para o outro jogador pós-evolução
      AnilLanRework::TradeSync.send_party_sync if AnilLanRework.connected?
    end

    # Espera ACK silenciosa para Pokémon que não estão em campo
    def self.wait_for_evolution_ack_silent(ctx, new_species, old_name)
      started = Time.now.to_f
      timeout = 5.0  # Timeout curto para evolução silenciosa
      ack_received = false

      AnilLanRework.log("evolution: waiting for silent ACK battle_id=#{ctx.battle_id}")

      wait_text = AnilLanRework::BattleSync.waiting_text("Aguardando parceiro registrar evolução...")
      viewport, window = AnilLanRework::BattleSync.build_wait_window(wait_text)

      begin
        while Time.now.to_f - started < timeout
          AnilLanRework.connection.tick rescue nil
          AnilLanRework.connection.drain do |packet|
            AnilLanRework::Router.route_packet(packet)
          end rescue nil

          if @evolution_callbacks["ack_#{ctx.battle_id}_-1"]
            ack_received = true
            break
          end

          AnilLanRework::BattleSync.update_battle_graphics(ctx) rescue nil
          Input.update rescue nil
          window.update rescue nil if window
          sleep(0.016)
        end
      ensure
        AnilLanRework::BattleSync.dispose_wait_window(viewport, window)
      end

      BattleSync.end_manual_lock("evolution:#{old_name}")
      BattleSync.update_manual_lock_reason("exp_phase") rescue nil
      @evolution_in_progress = false
      AnilLanRework.log("evolution: silent evolution complete battle_id=#{ctx.battle_id} ack=#{ack_received}")
      
      # Envia a party atualizada para o outro jogador pós-evolução
      AnilLanRework::TradeSync.send_party_sync if AnilLanRework.connected?
    end

    # ================================================================
    # MANEJO DO PACOTE PELO CLIENTE
    # ================================================================

    def self.receive_battle_evolution(packet)
      return unless packet.is_a?(Hash)
      ctx = BattleSync.active_context rescue nil
      return unless ctx

      battler_idx = packet["battler_idx"].to_i
      old_species = packet["old_species"].to_s
      new_species = packet["new_species"].to_s
      full_data   = packet["full_data"]
      in_battle   = packet["in_battle"]

      AnilLanRework.log("evolution CLIENT: received #{old_species} -> #{new_species} battler=#{battler_idx} in_battle=#{in_battle}")

      battle = ctx.battle rescue nil

      # Restaura o estado RNG se fornecido no pacote (Cable Club style)
      if ctx.rng && packet["rng_state"]
        if packet["rng_state"].is_a?(Hash)
          ctx.rng.restore(packet["rng_state"])
          battle.anil_rework_rng = ctx.rng if battle && battle.respond_to?(:anil_rework_rng=)
          AnilLanRework.log("evolution CLIENT: RNG state restored from host (Hash) rng_state=#{packet['rng_state']}")
        elsif packet["rng_state"].is_a?(Integer)
          ctx.rng.restore_state(packet["rng_state"])
          battle.anil_rework_rng = ctx.rng if battle && battle.respond_to?(:anil_rework_rng=)
          AnilLanRework.log("evolution CLIENT: RNG state restored from host (Integer) rng_state=#{packet['rng_state']}")
        end
      end

      unless battle
        send_evolution_ack(ctx, battler_idx, new_species)
        return
      end

      # Se o Pokémon NÃO está em campo (evolução silenciosa do parceiro)
      if in_battle == false || battler_idx < 0
        AnilLanRework.log("evolution CLIENT: partner party evolution (not in battle field), applying party update")
        party = Array($PokemonGlobal&.partner && $PokemonGlobal.partner[3])
        pkmn = party.find { |p| p && p.species.to_s == old_species } rescue nil
        if pkmn
          pkmn.species = new_species.to_sym rescue new_species
          pkmn.calc_stats
          pkmn.ready_to_evolve = false if pkmn.respond_to?(:ready_to_evolve=)
          if full_data.is_a?(Hash)
            AnilLanRework::Serializer.deserialize_pokemon_full(full_data, pkmn) rescue nil
          end
          AnilLanRework.log("evolution CLIENT: partner party evolution applied to $PokemonGlobal.partner for #{old_species} -> #{new_species}")

          # Também atualiza na party da batalha ativa se aplicável
          if battle
            battle_party = battle.instance_variable_get(:@party1) rescue nil
            if battle_party
              b_pkmn = battle_party.find { |p| p && p.species.to_s == old_species } rescue nil
              if b_pkmn && b_pkmn != pkmn
                b_pkmn.species = new_species.to_sym rescue new_species
                b_pkmn.calc_stats
                b_pkmn.ready_to_evolve = false if b_pkmn.respond_to?(:ready_to_evolve=)
                if full_data.is_a?(Hash)
                  AnilLanRework::Serializer.deserialize_pokemon_full(full_data, b_pkmn) rescue nil
                end
                AnilLanRework.log("evolution CLIENT: partner party evolution applied to battle.party1 for #{old_species} -> #{new_species}")
              end
            end
          end
        end

        send_evolution_ack(ctx, battler_idx, new_species)
        return
      end

      # Busca pelo battler usando a referência resolvida
      battler = nil
      if packet["battler_ref"]
        resolved_idx = AnilLanRework::BattleSync.resolve_coop_battler_reference(battle, packet["battler_ref"]) rescue nil
        battler = battle.battlers[resolved_idx] if resolved_idx && battle.battlers[resolved_idx]
      end

      # Fallback para busca por espécie se a resolução da referência falhar
      if !battler
        battle.battlers.each do |b|
          next unless b && b.pokemon
          if b.pokemon.species.to_s == old_species
            battler = b
            break
          end
        end
      end

      unless battler && battler.pokemon
        AnilLanRework.log("evolution CLIENT: could not find battler with species #{old_species}, skipping")
        send_evolution_ack(ctx, battler_idx, new_species)
        return
      end

      AnilLanRework.log("evolution CLIENT: found #{old_species} at battler #{battler.index}")

      battler.pokemon.species = new_species.to_sym rescue new_species
      battler.pokemon.calc_stats
      battler.pokemon.ready_to_evolve = false if battler.pokemon.respond_to?(:ready_to_evolve=)
      battler.form = battler.pokemon.form if battler.respond_to?(:form=)

      if full_data.is_a?(Hash)
        AnilLanRework::Serializer.deserialize_pokemon_full(full_data, battler.pokemon) rescue nil
      end

      battler.pokemon.form_simple = battler.pokemon.form if battler.pokemon.respond_to?(:form_simple)

      battler.hp = battler.pokemon.hp if battler.respond_to?(:hp=)
      battler.totalhp = battler.pokemon.totalhp if battler.respond_to?(:totalhp=)
      battler.pbUpdate(true) rescue nil

      begin
        new_species_for_viz = new_species.to_sym rescue new_species
        start_evolution_visuals(battler, new_species_for_viz)
      rescue => e
        AnilLanRework.log("evolution CLIENT: visual effect error: #{e.class}: #{e.message}")
      end

      send_evolution_ack(ctx, battler_idx, new_species)
      AnilLanRework.log("evolution CLIENT: applied #{new_species} for battler=#{battler.index}")
    end

    def self.send_evolution_ack(ctx, battler_idx, new_species)
      AnilLanRework.connection.send_packet("battle_evolution_ack",
        "to_id"       => ctx.partner_id,
        "battle_id"   => ctx.battle_id,
        "battler_idx" => battler_idx,
        "species"     => new_species.to_s
      )
    end

    # ================================================================
    # CALLBACK PARA ACK
    # ================================================================

    def self.receive_evolution_ack(packet)
      return unless packet.is_a?(Hash)
      ctx = BattleSync.active_context rescue nil
      return unless ctx

      battler_idx = packet["battler_idx"].to_i
      species     = packet["species"].to_s
      key         = "ack_#{ctx.battle_id}_#{battler_idx}"

      @evolution_callbacks[key] = {
        species: species,
        time: Time.now.to_f
      }

      AnilLanRework.log("evolution: ACK received for #{species} battler=#{battler_idx}")
    end

    # ================================================================
    # EFEITOS VISUAIS DE EVOLUCAO (estilo Mega Evolução)
    # O sprite brilha branco, troca de forma, e o brilho some.
    # ================================================================

    EVOLUTION_ANIM_DURATION = 60  # 60 frames = 1 segundo

    def self.start_evolution_visuals(battler, new_species)
      return unless battler
      battle = battler.battle rescue nil
      return unless battle
      scene = battle.scene rescue nil
      return unless scene

      idx = battler.index rescue 0
      sprite = scene.sprites["pokemon_#{idx}"] rescue nil
      return unless sprite

      AnilLanRework.log("evolution: glow animation for battler #{idx} -> #{new_species}")
      half = EVOLUTION_ANIM_DURATION / 2

      # FASE 1: Brilhar branco (sprite fica branco gradualmente)
      half.times do |i|
        white = (i.to_f / half * 255).to_i.clamp(0, 255)
        sprite.tone = Tone.new(white, white, white) rescue nil
        Graphics.update rescue nil
        Input.update rescue nil
      end

      # PICO: Totalmente branco - troca o bitmap para a nova espécie
      sprite.tone = Tone.new(255, 255, 255) rescue nil
      begin
        scene.pbChangePokemon(idx, battler.pokemon)
      rescue => e
        AnilLanRework.log("evolution: pbChangePokemon error: #{e.message}")
      end
      # Pequena pausa no branco total
      6.times do
        Graphics.update rescue nil
        Input.update rescue nil
      end

      # FASE 2: Desfazer o brilho (volta ao normal)
      half.times do |i|
        white = (255 * (1.0 - i.to_f / half)).to_i.clamp(0, 255)
        sprite.tone = Tone.new(white, white, white) rescue nil
        Graphics.update rescue nil
        Input.update rescue nil
      end

      # Garante que o tone volta ao normal
      sprite.tone = Tone.new(0, 0, 0) rescue nil

      # Atualiza o data box
      scene.pbRefreshOne(idx) rescue nil

      AnilLanRework.log("evolution: glow animation completed for #{new_species}")
    end

    def self.update_evolution_visuals
      # Animação é síncrona - sem estado persistente
    end

    def self.finish_evolution_visuals(battle_id)
      # Sem cleanup necessário - efeito é instantâneo
    end

    def self.create_evolution_glow_bitmap
      size = 128
      bmp = Bitmap.new(size, size)
      cx = size / 2
      cy = size / 2
      mr = size / 2 - 4

      (1..mr).each do |r|
        progress = r.to_f / mr
        alpha = (255 * (1 - progress * 0.7)).to_i.clamp(0, 255)
        rv = (50 + 200 * progress * 0.8).to_i.clamp(0, 255)
        gv = (200 + 55 * (1 - progress)).to_i.clamp(0, 255)
        bv = (30 * (1 - progress)).to_i.clamp(0, 255)
        bmp.fill_rect(cx - r, cy - r, r * 2, r * 2, Color.new(rv, gv, bv, alpha))
      end

      ring_color = Color.new(255, 255, 200, 120)
      bmp.fill_rect(cx - mr, cy - mr, mr * 2, mr * 2, ring_color)
      bmp.fill_rect(cx - mr + 2, cy - mr + 2, (mr - 2) * 2, (mr - 2) * 2, Color.new(0, 0, 0, 0))
      bmp
    end

    # ================================================================
    # REFRESH DE BATTLERS APOS EVOLUCAO
    # ================================================================

    def self.refresh_battler_after_evolution(ctx, battler_idx, new_species)
      battle = ctx.battle rescue nil
      return unless battle

      battler = battle.battlers[battler_idx] rescue nil
      return unless battler && battler.pokemon

      battler.pokemon.species = new_species.to_sym rescue new_species
      battler.pokemon.calc_stats

      if battler.respond_to?(:pokemon_reset)
        battler.pokemon_reset
      elsif battler.respond_to?(:refresh_form)
        battler.refresh_form
      end

      # Atualiza HP apenas se o battler suporta
      battler.hp = battler.pokemon.hp if battler.respond_to?(:hp=)

      # Atualiza sprite via scene
      begin
        scene = battle.scene rescue nil
        if scene
          if scene.respond_to?(:pbChangePokemon)
            scene.pbChangePokemon(battler, battler.pokemon) rescue nil
          end
          if scene.respond_to?(:pbRefreshOne)
            scene.pbRefreshOne(battler_idx) rescue nil
          end
        end
      rescue => e
        AnilLanRework.log("evolution: refresh sprite error: #{e.message}")
      end

      AnilLanRework.log("evolution: battler #{battler_idx} refreshed to #{new_species}")
    end

    # ================================================================
    # MANUTENCAO / LIMPEZA
    # ================================================================

    def self.clear_evolution_callbacks(battle_id)
      return unless @evolution_callbacks
      @evolution_callbacks.delete_if { |key, _| key.start_with?(battle_id.to_s) }
    end

    def self.clear_all_evolution_data
      @evolution_in_progress = false
      @evolution_timer = 0
      @evolution_callbacks&.clear
      @evolution_effects&.clear
    end
  end
end

# ================================================================
# MONKEY-PATCH: BattleSync methods for evolution
# ================================================================
unless AnilLanRework::BattleSync.respond_to?(:receive_battle_evolution)
  module AnilLanRework
    module BattleSync
      def self.receive_battle_evolution(packet)
        AnilLanRework::BattleSyncEvolution.receive_battle_evolution(packet)
      end

      def self.receive_evolution_ack(packet)
        AnilLanRework::BattleSyncEvolution.receive_evolution_ack(packet)
      end

      def self.check_evolution_and_sync_multipleyer(battler)
        AnilLanRework::BattleSyncEvolution.check_evolution_and_sync_multipleyer_from_pokemon(battler)
      end
    end
  end
end

# ================================================================
# MONKEY-PATCH: check_evolution_and_sync_multipleyer no Battle::Battler
# ================================================================
unless defined?(Battle::Battler) && Battle::Battler.method_defined?(:check_evolution_and_sync_multipleyer)
  class Battle::Battler
    def check_evolution_and_sync_multipleyer
      AnilLanRework::BattleSyncEvolution.check_evolution_and_sync_multipleyer_from_pokemon(self)
    end
  end
end

# ================================================================
# OVERRIDES MOVIDOS DO MONOLITO
# ================================================================
if defined?(pbEvolutionCheck) && !defined?(anil_suppress_evolution_in_battle_pbEvolutionCheck)
  alias anil_suppress_evolution_in_battle_pbEvolutionCheck pbEvolutionCheck

  def pbEvolutionCheck(*args)
    # Suprime evolução durante batalhas multiplayer ativas.
    # Quando a batalha termina, $game_temp.in_battle vira false e a evolução roda normalmente.
    if $game_temp.in_battle && AnilLanRework.connected?
      ctx = AnilLanRework::BattleSync.active_context rescue nil
      if ctx && ctx.mode == :coop
        AnilLanRework.log("pbEvolutionCheck suprimido durante a batalha COOP (multiplayer ativo). O addon BattleSyncEvolution deve cuidar disso.")
        return
      end
    end
    anil_suppress_evolution_in_battle_pbEvolutionCheck(*args)
  end
end
if defined?(Game_Player)
  class Game_Player
    unless method_defined?(:anil_rework_safe_check_event_trigger_there) || private_method_defined?(:anil_rework_safe_check_event_trigger_there)
      alias anil_rework_safe_check_event_trigger_there check_event_trigger_there
    end

    def check_event_trigger_there(triggers)
      return false if $game_temp&.player_transferring
      return false if $game_temp&.transition_processing
      return false if @x.nil? || @y.nil? || @direction.nil?
      return false unless $game_map && $game_map.respond_to?(:data) && $game_map.data
      anil_rework_safe_check_event_trigger_there(triggers)
    rescue TypeError => e
      AnilLanRework.log("check_event_trigger_there guarded #{e.class}: #{e.message}")
      false
    end
  end
end

if defined?(Game_Map)
  class Game_Map
    unless method_defined?(:anil_rework_safe_counter) || private_method_defined?(:anil_rework_safe_counter)
      alias anil_rework_safe_counter counter?
    end

    def counter?(x, y)
      return false if x.nil? || y.nil?
      return false unless respond_to?(:data) && data
      return false unless valid?(x, y)
      anil_rework_safe_counter(x, y)
    rescue TypeError => e
      AnilLanRework.log("counter? guarded #{e.class}: #{e.message} x=#{x.inspect} y=#{y.inspect} map_id=#{@map_id.inspect}")
      false
    end
  end
end

if defined?(Pokemon)
  class Pokemon
    unless method_defined?(:anil_suppress_mid_battle_evolution_check_evolution_on_level_up) || private_method_defined?(:anil_suppress_mid_battle_evolution_check_evolution_on_level_up)
      alias anil_suppress_mid_battle_evolution_check_evolution_on_level_up check_evolution_on_level_up
    end
    unless method_defined?(:anil_suppress_mid_battle_evolution_check_evolution_after_battle) || private_method_defined?(:anil_suppress_mid_battle_evolution_check_evolution_after_battle)
      alias anil_suppress_mid_battle_evolution_check_evolution_after_battle check_evolution_after_battle
    end

    def check_evolution_on_level_up(*args)
      # Permitir evolução durante coop - o BattleSyncEvolution cuida da sincronização
      anil_suppress_mid_battle_evolution_check_evolution_on_level_up(*args)
    end

    def check_evolution_after_battle(*args)
      # Permitir evolução durante coop - o BattleSyncEvolution cuida da sincronização
      anil_suppress_mid_battle_evolution_check_evolution_after_battle(*args)
    end
  end
end
