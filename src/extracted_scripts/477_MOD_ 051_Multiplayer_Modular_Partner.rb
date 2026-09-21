#===============================================================================
# MOD: 051_Multiplayer_Modular_Partner.rb
#-------------------------------------------------------------------------------
# Gerenciador Unificado de Parceiros (Modular Partner System)
#
# Centraliza o registro, geração e compatibilização de treinadores parceiros
# (offline e multiplayer) garantindo que:
# - Parceiros offline nunca sejam deletados pelo sincronismo de rede coop.
# - A geração de times e evolução de Pokémon seja modular e previsível.
# - Redireciona chamadas globais de pbRegisterPartner para este módulo.
#===============================================================================

module ModularPartner
  module_function

  # Registra um parceiro unificado (seja escolta, NPC Life ou multiplayer)
  def register(trainer_type, trainer_name, party_or_pkmn = nil, map_id = nil, is_multiplayer = false)
    begin
      QuestDebugLogger.log("ModularPartner", "Registering partner: type=#{trainer_type}, name=#{trainer_name}, map_id=#{map_id}, is_multiplayer=#{is_multiplayer}")
    rescue
    end
    
    # Sanitiza tipo de treinador
    trainer_type = trainer_type.to_sym rescue :CAMPISTO
    if !GameData::TrainerType.exists?(trainer_type)
      trainer_type = :CAMPISTO
    end

    # Sanitiza nome do treinador
    if !trainer_name || trainer_name.to_s.empty?
      trainer_name = GameData::TrainerType.get(trainer_type).name rescue "Aventureiro"
    end

    party = []
    if party_or_pkmn.is_a?(Array)
      party = party_or_pkmn
    elsif party_or_pkmn.is_a?(Pokemon)
      party = [party_or_pkmn]
    elsif party_or_pkmn.nil? || (party_or_pkmn.empty? rescue true)
      # Tenta carregar treinador do banco de dados (PBS/trainers.txt)
      begin
        trainer = pbLoadTrainer(trainer_type, trainer_name, 0)
        if trainer
          EventHandlers.trigger(:on_trainer_load, trainer)
          party = trainer.party
        end
      rescue
        # Se falhar, gera um Pokémon selvagem adequado para a rota/bioma
        map_id ||= ($game_map ? $game_map.map_id : 1)
        species = generate_dynamic_pokemon_species(map_id)
        pkmn = generate_escort_pokemon(species, map_id)
        party = [pkmn] if pkmn
      end
    end

    if party.empty?
      begin
        QuestDebugLogger.log("ModularPartner", "Failed to register partner: party is empty!")
      rescue
      end
      return false
    end

    # Define o proprietário (owner) e recalcula os stats para cada Pokémon do parceiro
    party.each do |pkmn|
      next unless pkmn.is_a?(Pokemon)
      begin
        pkmn.owner = Pokemon::Owner.new(0, trainer_name, 2, trainer_type)
      rescue
        begin; pkmn.owner = Pokemon::Owner.new(trainer_name, trainer_name, 1); rescue; end
      end
      pkmn.calc_stats
    end

    pbCancelVehicles rescue nil
    
    # Armazena o partner no formato do Essentials:
    # [trainer_type, trainer_name, trainer_id, party, is_multiplayer]
    # O 5º elemento como 'false' garante que seja interpretado como parceiro de história local,
    # impedindo que o sincronismo de multiplayer o apague durante batalhas offline.
    $PokemonGlobal.partner = [trainer_type, trainer_name, 0, party, is_multiplayer]
    begin
      pkmn_str = party.map { |p| "#{p.species}(L#{p.level})" }.join(", ")
      QuestDebugLogger.log("ModularPartner", "Partner registered successfully. Team: #{pkmn_str}")
    rescue
    end
    true
  end

  # Remove o parceiro ativo
  def deregister
    begin
      QuestDebugLogger.log("ModularPartner", "Deregistering partner")
    rescue
    end
    $PokemonGlobal.partner = nil
  end

  # Retorna se há um parceiro ativo
  def active?
    !$PokemonGlobal.partner.nil? rescue false
  end

  # Retorna os dados do parceiro ativo
  def get
    $PokemonGlobal.partner
  end

  # Auxiliar: escolhe uma espécie adequada para a rota/mapa
  def generate_dynamic_pokemon_species(map_id)
    if defined?(DynamicRouteEvents_Manager)
      biome = DynamicRouteEvents_Manager.map_biome(map_id) rescue :route
      DynamicRouteEvents_Manager.random_pokemon_for_biome(biome) rescue :RATTATA
    else
      :RATTATA
    end
  end

  # Auxiliar: gera um Pokémon de nível adequado e com chance de evolução
  def generate_escort_pokemon(species, map_id)
    if defined?(DynamicRouteEvents_Manager)
      DynamicRouteEvents_Manager.generate_escort_pokemon(species, map_id) rescue Pokemon.new(species, 15)
    else
      Pokemon.new(species, 15)
    end
  end
end

#===============================================================================
# Redirecionamento de Métodos Globais do Essentials
#===============================================================================
def pbRegisterPartner(tr_type, tr_name, tr_id = 0)
  ModularPartner.register(tr_type, tr_name, nil, nil, false)
end

def pbDeregisterPartner
  ModularPartner.deregister
end

#===============================================================================
# Override de Segurança no Sistema Multiplayer
#===============================================================================
module AnilLanRework
  module BattleSync
    class << self
      # Alias/override seguro do método de checagem de parceiros de história
      if !method_defined?(:modular_partner_orig_is_story_partner?)
        alias modular_partner_orig_is_story_partner? is_story_partner?
      end
    end

    def self.is_story_partner?(partner)
      return false unless partner
      # Se o 5º elemento do array de partner for 'false', ele é um companheiro offline local (história).
      # Se for 'true', ele é explicitamente injetado pela rede multiplayer coop.
      return true if partner[4] == false
      
      # Fallback para as validações nativas e por nomes/tipos específicos do jogo base
      modular_partner_orig_is_story_partner?(partner)
    end
  end
end



#===============================================================================
# Fix: Corrige tamanho de batalha quando parceiro de quest está registrado
# mas a batalha foi inicializada como single (ex: pesca, encontro selvagem).
# Sem isso, pbEnsureParticipants crasheia porque há 2 trainers mas só 1 posição.
#===============================================================================
if defined?(Battle)
  class Battle
    unless method_defined?(:modular_partner_original_pbStartBattle)
      alias modular_partner_original_pbStartBattle pbStartBattle
    end

    def pbStartBattle(*args)
      # Se há 2+ trainers do lado do jogador mas o layout é 1v1, corrige para 2v1
      if @player && @player.length >= 2 && @sideSizes[0] == 1
        foe_size = @sideSizes[1]
        new_player_size = [2, foe_size].max
        new_player_size = 2 if new_player_size > 3
        @sideSizes[0] = new_player_size
        # Garante que o lado inimigo tenha pelo menos 1
        @sideSizes[1] = [foe_size, 1].max
      end
      modular_partner_original_pbStartBattle(*args)
    end
  end
end

