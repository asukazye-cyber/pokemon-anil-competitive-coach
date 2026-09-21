# encoding: utf-8
# ==============================================================================
#  104_Multiplayer_Raid_Torre.rb
#  Sistema de Raids da Torre - Guzman e Giovanni
# ==============================================================================

# 0. Compilação automática do PBS no Cliente
begin
  version_file = "Data/.pbs_compiled_raid_v3"
  unless File.exist?(version_file)
    Compiler.compile_all(true)
    File.write(version_file, "compiled")
  end
rescue => e
  echoln "Erro compilar PBS: #{e.message}"
end

# 1. Patch na classe Trainer para permitir nível de IA (skill_level) customizado por instância
class Trainer
  attr_writer :skill_level

  unless method_defined?(:original_skill_level)
    alias original_skill_level skill_level
    def skill_level
      return @skill_level if @skill_level
      return original_skill_level
    end
  end
end

# ==============================================================================
# 2. RAID DE GUZMAN (Bilhete Guzman)
# ==============================================================================
module RaidTorre

  # O jogador venceu a batalha do chefe?
  #
  # ⚠️ NAO comparar com 1 diretamente. O TrainerBattle.start do motor NAO
  # devolve o numero da decisao — devolve um BOOLEANO (0261_Overworld_
  # BattleStarting.rb):
  #
  #     # Return true if the player won the battle, and false if any other result
  #     return outcome == 1
  #
  # Quem escreveu as raids assumiu que vinha o 1/2/5 do @decision e escreveu
  # `if outcome == 1`. Em Ruby `true == 1` e FALSO, entao a vitoria caia sempre
  # no ramo do else: o chefe era derrotado e o jogo dizia que o jogador tinha
  # perdido — e, como a entrega da recompensa vive dentro do if, o bilhete era
  # consumido sem pagar nada.
  #
  # Aceita as duas formas porque o embrulho do multiplayer (000, class <<
  # TrainerBattle) devolve o resultado do original, e nada garante que assim
  # continue: se um dia voltar a ser numerico, isto continua correto.
  def self.venceu?(outcome)
    outcome == true || outcome == 1
  end

  def self.entregar_recompensa_raid(leader_name)
    # 1. Rola a quantidade de slots de recompensa (55% 1, 30% 2, 15% 3).
    #
    # Ajustado em 2026-08-09. Antes era 70/25/5, que dava 1,35 slots por raid;
    # agora dá 1,60. A leitura dos limiares é de cima para baixo, entao o 3 vem
    # primeiro: <15 e 3, <45 e 2 (os 30 seguintes), o resto e 1.
    roll_count = rand(100)
    slot_count = if roll_count < 15
                   3
                 elsif roll_count < 45
                   2
                 else
                   1
                 end

    won_items = []

    # 2. Sorteia cada slot individualmente.
    #
    # Ajustado em 2026-08-09: vermelha 1->3%, laranja 5->8%, azul 15->20%. O
    # Saco de Moeda Grande ficou nos 5%. O vazio caiu de 74% para 64%.
    #
    # Os limiares sao CUMULATIVOS — cada faixa comeca onde a anterior acabou —
    # entao mexer numa desloca todas as de baixo. Os comentarios trazem o
    # intervalo aberto de cada uma para a proxima calibragem nao errar a conta.
    slot_count.times do
      r = rand(100)
      if r < 3 # 3% -> Caixa Vermelha (0..2)
        won_items << :GIFT_RED if (GameData::Item.exists?(:GIFT_RED) rescue false)
      elsif r < 11 # 8% -> Caixa Laranja (3..10)
        won_items << :GIFT_ORANGE if (GameData::Item.exists?(:GIFT_ORANGE) rescue false)
      elsif r < 16 # 5% -> 1x Saco de Moedas Grande (11..15)
        won_items << :SACOMOEDAGRANDE if (GameData::Item.exists?(:SACOMOEDAGRANDE) rescue false)
      elsif r < 36 # 20% -> Caixa Azul (16..35)
        won_items << :GIFT_BLUE if (GameData::Item.exists?(:GIFT_BLUE) rescue false)
      end
      # 64% -> Vazio neste slot
    end

    if won_items.empty?
      pbMessage(_INTL("Parabéns por derrotar {1}! Você concluiu o desafio da Raid com sucesso!", leader_name))
    else
      # Entrega os itens ao jogador
      won_items.each do |item_id|
        $bag.add(item_id, 1) rescue nil
      end

      names = won_items.map do |item_id|
        GameData::Item.get(item_id).name rescue item_id.to_s
      end
      item_list_str = names.join(", ")

      pbMEPlay("Item get") rescue nil
      if defined?(AnilLanRework) && AnilLanRework.respond_to?(:add_popup)
        AnilLanRework.add_popup(_INTL("Recompensa da Raid: {1}!", item_list_str), 6.0, won_items.first)
      else
        pbMessage(_INTL("\\me[]RECOMPENSA DA RAID! Por derrotar {1}, você recebeu: \\c[1]{2}\\c[0]!", leader_name, item_list_str))
      end
    end
  end

  EventHandlers.add(:on_trainer_load, :guzman_raid_ai_boost, proc { |trainer|
    if trainer && trainer.name == "Guzman"
      trainer.skill_level = 120
    end
  })

  def self.resolver_especie(name)
    return nil if name.nil? || name.empty?
    name = name.split("(")[0].strip
    name = name.sub(/^\d+\.\s*/, "")
    parts = name.split("/").map(&:strip)
    parts.each do |part|
      clean = part.upcase
      id = clean.gsub(/[\s-]+/, "_").to_sym
      return id if GameData::Species.exists?(id)
      id2 = clean.gsub(/[\s-]+/, "").to_sym
      return id2 if GameData::Species.exists?(id2)
    end
    return nil
  end

  def self.resolver_item(name)
    return nil if name.nil? || name.empty?
    name = name.split("(")[0].strip
    parts = name.split("/").map(&:strip)
    parts.each do |part|
      clean = part.upcase
      id = clean.gsub(/[\s-]+/, "_").to_sym
      return id if GameData::Item.exists?(id)
      id2 = clean.gsub(/[\s-]+/, "").to_sym
      return id2 if GameData::Item.exists?(id2)
    end
    return nil
  end

  def self.resolver_movimento(name)
    return nil if name.nil? || name.empty?
    name = name.split("(")[0].strip
    parts = name.split("/").map(&:strip)
    parts.each do |part|
      clean = part.upcase
      id = clean.gsub(/[\s-]+/, "_").to_sym
      return id if GameData::Move.exists?(id)
      id2 = clean.gsub(/[\s-]+/, "").to_sym
      return id2 if GameData::Move.exists?(id2)
    end
    return nil
  end

  def self.resolver_habilidade(name)
    return nil if name.nil? || name.empty?
    name = name.split("(")[0].strip
    parts = name.split("/").map(&:strip)
    parts.each do |part|
      clean = part.upcase
      id = clean.gsub(/[\s-]+/, "_").to_sym
      return id if GameData::Ability.exists?(id)
      id2 = clean.gsub(/[\s-]+/, "").to_sym
      return id2 if GameData::Ability.exists?(id2)
    end
    return nil
  end

  def self.resolver_natureza(name)
    return nil if name.nil? || name.empty?
    name = name.split("(")[0].strip
    id = name.upcase.to_sym
    return id if GameData::Nature.exists?(id)
    return nil
  end

  def self.resolver_trainer_type
    # O Guzman NAO tem um tipo com o nome dele: os tres :*_Guzman que estavam
    # aqui nunca existiram no PBS, logo caia-se sempre no Red. A arte dele existe
    # com nome generico — Graphics/Trainers/TB19.png e o mesmo personagem do
    # charset "guzman" do overworld (cabelo branco, oculos amarelos, Team Skull).
    # O tipo TB19 ("Contendiente") esta em trainer_types.txt e nao e usado por
    # nenhum treinador do trainers.txt, portanto da para o adoptar sem colisao.
    [:TB19, :ATLAS1].each do |type|
      return type if GameData::TrainerType.exists?(type)
    end
    return :POKEMONTRAINER_RojoNeutro
  end

  def self.carregar_times_guzman
    dat_path = "Raid da Torre/Guzman.dat"
    if File.exist?(dat_path)
      begin
        return Marshal.load(File.binread(dat_path))
      rescue => e
        echoln "Erro carregar Guzman.dat: #{e.message}"
      end
    end
    echoln("RaidGuzman: #{dat_path} ausente ou ilegivel (modo dat-only, sem fallback .txt).")
    return []
  end

  # ⚠️ UMA RAID NAO PODE SER ASSUMIDA PELA ARENA EM TEMPO REAL.
#
# Com o "Treinador em tempo real" ligado, o `TrainerBattle.start_core` e
# desviado para a arena: a luta passa a acontecer no mapa em vez de abrir o
# ecra de batalha. Para um treinador de rota isso e o que se quer.
#
# Para uma raid nao, e o sintoma e um ecra preto. A razao esta a vista aqui
# em baixo: cada raid chama a batalha DENTRO de um `pbFadeOutIn`.
#
#     pbFadeOutIn { outcome = RaidTorre.batalha_de_raid(...) }
#
# O `pbFadeOutIn` escurece o ecra, corre o bloco, e volta a acender. Se o
# bloco abrir o ecra de batalha, tudo bem — ele acende sozinho. Mas a arena
# nao abre ecra nenhum: devolve o controlo ao mapa e fica a correr la. O fade
# acende sobre um mapa que ninguem preparou, com o roteiro da raid suspenso a
# espera de um `outcome` que so chega muito mais a frente.
#
# Alem do ecra, ha o resto: a equipa do chefe vem dos `.dat` da Raid da
# Torre, e as regras (`canLose`, BGM propria, textos) sao postas pelo
# `TrainerBattle.setBattleRule`. Nada disso existe do lado da arena.
#
# Por agora as raids ficam de fora, como foi pedido. Marca-se a chamada, e o
# 189 pergunta pela marca antes de assumir.
def self.batalha_de_raid(*args)
  antes = ($game_temp.instance_variable_get(:@anil_raid_a_decorrer) rescue nil)
  ($game_temp.instance_variable_set(:@anil_raid_a_decorrer, true) rescue nil)
  begin
    TrainerBattle.start(*args)
  ensure
    # `ensure`, e nao uma linha a seguir: se a batalha rebentar, a marca tem
    # de sair na mesma. Uma marca esquecida faz TODAS as batalhas seguintes
    # ignorarem a arena — muito pior do que o defeito original.
    ($game_temp.instance_variable_set(:@anil_raid_a_decorrer, antes) rescue nil)
  end
end

def self.iniciar_raid_guzman
    # 1. Carregar os times de Guzman
    teams = carregar_times_guzman
    if teams.empty?
      pbMessage(_INTL("Guzman não possui equipes prontas para batalha!"))
      return 0
    end

    # 2. Escolher um dos times de Guzman de forma aleatória
    selected_team = teams.sample

    # 3. Determinar o nível do inimigo baseado no nível máximo do time do jogador
    player_max_level = 1
    $player.party.each do |pkmn|
      player_max_level = pkmn.level if pkmn.level > player_max_level
    end

    formatted_pokemon = []
    selected_team.each do |pkmn_data|
      ev_hash = {
        :HP              => pkmn_data[:evs][0],
        :ATTACK          => pkmn_data[:evs][1],
        :DEFENSE         => pkmn_data[:evs][2],
        :SPECIAL_ATTACK  => pkmn_data[:evs][3],
        :SPECIAL_DEFENSE => pkmn_data[:evs][4],
        :SPEED           => pkmn_data[:evs][5]
      }
      formatted_pokemon << {
        :species => pkmn_data[:species],
        :level   => player_max_level,
        :item    => pkmn_data[:item],
        :ability => pkmn_data[:ability],
        :nature  => pkmn_data[:nature],
        :moves   => pkmn_data[:moves],
        :form    => pkmn_data[:form] || 0,
        :iv      => {:HP => 31, :ATTACK => 31, :DEFENSE => 31, :SPECIAL_ATTACK => 31, :SPECIAL_DEFENSE => 31, :SPEED => 31},
        :ev      => ev_hash
      }
    end

    trainer_type = resolver_trainer_type
    trainer_name = "Guzman"
    version = pbGetFreeTrainerParty(trainer_type, trainer_name) || 0

    GameData::Trainer.register({
      :id           => [trainer_type, trainer_name, version],
      :trainer_type => trainer_type,
      :real_name    => trainer_name,
      :version      => version,
      # Mega Aro: sem ele pbHasMegaRing? falha e o chefe nunca megaevolui,
      # mesmo segurando a pedra.
      :items        => [:MEGARING, :FULLRESTORE],
      :pokemon      => formatted_pokemon,
    })

    # Configurar as regras estritas da Raid
    TrainerBattle.setBattleRule("nobag")
    TrainerBattle.setBattleRule("setstyle")
    TrainerBattle.setBattleRule("noExp")
    TrainerBattle.setBattleRule("battleBGM", "Batalla Jefe Torre")
    TrainerBattle.setBattleRule("canLose")

    TrainerBattle.setBattleRule("opponentlosetext", _INTL("O quê?! O meu tipo inseto foi esmagado assim?!"))
    TrainerBattle.setBattleRule("opponentwintext", _INTL("É isso aí! O grande Guzman destrói qualquer um!"))

    outcome = 0
    pbMessage(_INTL("Guzman quer batalhar!"))
    pbFadeOutIn {
      outcome = RaidTorre.batalha_de_raid(trainer_type, trainer_name, version)
    }

    if RaidTorre.venceu?(outcome)
      pbMessage(_INTL("Parabéns! Você venceu a Raid do Guzman!"))
      RaidTorre.entregar_recompensa_raid("Guzman")
      return 1
    else
      pbMessage(_INTL("Guzman venceu você. Prepare-se melhor e tente novamente!"))
      return 2
    end
  end
end


# ==============================================================================
# 3. RAID DE GIOVANNI (Bilhete Giovanni)
# ==============================================================================
module RaidGiovanni
  EventHandlers.add(:on_trainer_load, :giovanni_raid_ai_boost, proc { |trainer|
    if trainer && trainer.name == "Giovanni"
      trainer.skill_level = 120
    end
  })

  def self.resolver_trainer_type
    [:GIOVANNI3, :GIOVANNI2, :GIOVANNI1].each do |type|
      return type if GameData::TrainerType.exists?(type)
    end
    return :POKEMONTRAINER_RojoNeutro
  end

  def self.carregar_times_giovanni
    dat_path = "Raid da Torre/Giovanni.dat"
    if File.exist?(dat_path)
      begin
        return Marshal.load(File.binread(dat_path))
      rescue => e
        echoln "Erro carregar Giovanni.dat: #{e.message}"
      end
    end
    echoln("RaidGiovanni: #{dat_path} ausente ou ilegivel (modo dat-only, sem fallback .txt).")
    return []
  end

  def self.iniciar_raid_giovanni
    # 1. Carregar os times de Giovanni
    teams = carregar_times_giovanni
    if teams.empty?
      pbMessage(_INTL("Giovanni não possui equipes prontas para batalha!"))
      return 0
    end

    # 2. Escolher um dos times de Giovanni de forma aleatória
    selected_team = teams.sample

    # 3. Determinar o nível do inimigo baseado no nível máximo do time do jogador
    player_max_level = 1
    $player.party.each do |pkmn|
      player_max_level = pkmn.level if pkmn.level > player_max_level
    end

    formatted_pokemon = []
    selected_team.each do |pkmn_data|
      ev_hash = {
        :HP              => pkmn_data[:evs][0],
        :ATTACK          => pkmn_data[:evs][1],
        :DEFENSE         => pkmn_data[:evs][2],
        :SPECIAL_ATTACK  => pkmn_data[:evs][3],
        :SPECIAL_DEFENSE => pkmn_data[:evs][4],
        :SPEED           => pkmn_data[:evs][5]
      }
      formatted_pokemon << {
        :species => pkmn_data[:species],
        :level   => player_max_level,
        :item    => pkmn_data[:item],
        :ability => pkmn_data[:ability],
        :nature  => pkmn_data[:nature],
        :moves   => pkmn_data[:moves],
        :form    => pkmn_data[:form] || 0,
        :iv      => {:HP => 31, :ATTACK => 31, :DEFENSE => 31, :SPECIAL_ATTACK => 31, :SPECIAL_DEFENSE => 31, :SPEED => 31},
        :ev      => ev_hash
      }
    end

    trainer_type = resolver_trainer_type
    trainer_name = "Giovanni"
    version = pbGetFreeTrainerParty(trainer_type, trainer_name) || 0

    GameData::Trainer.register({
      :id           => [trainer_type, trainer_name, version],
      :trainer_type => trainer_type,
      :real_name    => trainer_name,
      :version      => version,
      # Mega Aro: sem ele pbHasMegaRing? falha e o chefe nunca megaevolui,
      # mesmo segurando a pedra.
      :items        => [:MEGARING, :FULLRESTORE],
      :pokemon      => formatted_pokemon,
    })

    # Configurar as regras estritas da Raid
    TrainerBattle.setBattleRule("nobag")
    TrainerBattle.setBattleRule("setstyle")
    TrainerBattle.setBattleRule("noExp")
    TrainerBattle.setBattleRule("battleBGM", "Batalla Jefe Torre")
    TrainerBattle.setBattleRule("canLose")

    TrainerBattle.setBattleRule("opponentlosetext", _INTL("Inacreditável... O poder da Equipe Rocket falhou?!"))
    TrainerBattle.setBattleRule("opponentwintext", _INTL("Como esperado. O império da Equipe Rocket é invencível!"))

    outcome = 0
    pbMessage(_INTL("Giovanni quer batalhar!"))
    pbFadeOutIn {
      outcome = RaidTorre.batalha_de_raid(trainer_type, trainer_name, version)
    }

    if RaidTorre.venceu?(outcome)
      pbMessage(_INTL("Parabéns! Você venceu a Raid do Giovanni!"))
      RaidTorre.entregar_recompensa_raid("Giovanni")
      return 1
    else
      pbMessage(_INTL("Giovanni venceu você. Prepare-se melhor e tente novamente!"))
      return 2
    end
  end
end


# ==============================================================================
# 4. RAID DE MISTY (Bilhete Misty)
# ==============================================================================
module RaidMisty
  EventHandlers.add(:on_trainer_load, :misty_raid_ai_boost, proc { |trainer|
    if trainer && trainer.name == "Misty"
      trainer.skill_level = 120
    end
  })

  def self.resolver_trainer_type
    # LIDER2 e a Misty ([LIDER2,Misty] no PBS). Ver a nota no resolver do Brock.
    [:LIDER2, :LIDER2REVANCHA].each do |type|
      return type if GameData::TrainerType.exists?(type)
    end
    return :POKEMONTRAINER_RojoNeutro
  end

  def self.carregar_times_misty
    dat_path = "Raid da Torre/Misty.dat"
    if File.exist?(dat_path)
      begin
        return Marshal.load(File.binread(dat_path))
      rescue => e
        echoln "Erro carregar Misty.dat: #{e.message}"
      end
    end
    echoln("RaidMisty: #{dat_path} ausente ou ilegivel (modo dat-only, sem fallback .txt).")
    return []
  end

  def self.iniciar_raid_misty
    # 1. Carregar os times de Misty
    teams = carregar_times_misty
    if teams.empty?
      pbMessage(_INTL("Misty não possui equipes prontas para batalha!"))
      return 0
    end

    # 2. Escolher um dos times de Misty de forma aleatória
    selected_team = teams.sample

    # 3. Determinar o nível do inimigo baseado no nível máximo do time do jogador
    player_max_level = 1
    $player.party.each do |pkmn|
      player_max_level = pkmn.level if pkmn.level > player_max_level
    end

    formatted_pokemon = []
    selected_team.each do |pkmn_data|
      ev_hash = {
        :HP              => pkmn_data[:evs][0],
        :ATTACK          => pkmn_data[:evs][1],
        :DEFENSE         => pkmn_data[:evs][2],
        :SPECIAL_ATTACK  => pkmn_data[:evs][3],
        :SPECIAL_DEFENSE => pkmn_data[:evs][4],
        :SPEED           => pkmn_data[:evs][5]
      }
      formatted_pokemon << {
        :species => pkmn_data[:species],
        :level   => player_max_level,
        :item    => pkmn_data[:item],
        :ability => pkmn_data[:ability],
        :nature  => pkmn_data[:nature],
        :moves   => pkmn_data[:moves],
        :form    => pkmn_data[:form] || 0,
        :iv      => {:HP => 31, :ATTACK => 31, :DEFENSE => 31, :SPECIAL_ATTACK => 31, :SPECIAL_DEFENSE => 31, :SPEED => 31},
        :ev      => ev_hash
      }
    end

    trainer_type = resolver_trainer_type
    trainer_name = "Misty"
    version = pbGetFreeTrainerParty(trainer_type, trainer_name) || 0

    GameData::Trainer.register({
      :id           => [trainer_type, trainer_name, version],
      :trainer_type => trainer_type,
      :real_name    => trainer_name,
      :version      => version,
      # Mega Aro: sem ele pbHasMegaRing? falha e o chefe nunca megaevolui,
      # mesmo segurando a pedra.
      :items        => [:MEGARING, :FULLRESTORE],
      :pokemon      => formatted_pokemon,
    })

    # Configurar as regras estritas da Raid
    TrainerBattle.setBattleRule("nobag")
    TrainerBattle.setBattleRule("setstyle")
    TrainerBattle.setBattleRule("noExp")
    TrainerBattle.setBattleRule("battleBGM", "Batalla Jefe Torre")
    TrainerBattle.setBattleRule("canLose")

    TrainerBattle.setBattleRule("opponentlosetext", _INTL("Oh, não! Minha estratégia aquática foi superada!"))
    TrainerBattle.setBattleRule("opponentwintext", _INTL("Você ainda não está pronto para a força dos meus tipos água!"))

    outcome = 0
    pbMessage(_INTL("Misty quer batalhar!"))
    pbFadeOutIn {
      outcome = RaidTorre.batalha_de_raid(trainer_type, trainer_name, version)
    }

    if RaidTorre.venceu?(outcome)
      pbMessage(_INTL("Parabéns! Você venceu a Raid da Misty!"))
      RaidTorre.entregar_recompensa_raid("Misty")
      return 1
    else
      pbMessage(_INTL("Misty venceu você. Prepare-se melhor e tente novamente!"))
      return 2
    end
  end
end


# ==============================================================================
# 5. RAID DE BROCK (Bilhete Brock)
# ==============================================================================
module RaidBrock
  EventHandlers.add(:on_trainer_load, :brock_raid_ai_boost, proc { |trainer|
    if trainer && trainer.name == "Brock"
      trainer.skill_level = 120
    end
  })

  def self.resolver_trainer_type
    # LIDER1 e o Brock — confirmado pelo PBS/trainers.txt ([LIDER1,Brock]).
    # Os :LEADER_* que estavam aqui NAO EXISTEM em trainer_types.txt, portanto
    # caia-se sempre no fallback :POKEMONTRAINER_RojoNeutro — era por isso que
    # aparecia o Red no lugar do chefe, e a transicao nao corria (ela exige
    # Graphics/Transitions/hgss_vs_<TIPO>.png para o tipo REAL).
    [:LIDER1, :LIDER1REVANCHA].each do |type|
      return type if GameData::TrainerType.exists?(type)
    end
    return :POKEMONTRAINER_RojoNeutro
  end

  def self.carregar_times_brock
    dat_path = "Raid da Torre/Brock.dat"
    if File.exist?(dat_path)
      begin
        return Marshal.load(File.binread(dat_path))
      rescue => e
        echoln "Erro carregar Brock.dat: #{e.message}"
      end
    end
    echoln("RaidBrock: #{dat_path} ausente ou ilegivel (modo dat-only, sem fallback .txt).")
    return []
  end

  def self.iniciar_raid_brock
    # 1. Carregar os times de Brock
    teams = carregar_times_brock
    if teams.empty?
      pbMessage(_INTL("Brock não possui equipes prontas para batalha!"))
      return 0
    end

    # 2. Escolher um dos times de Brock de forma aleatória
    selected_team = teams.sample

    # 3. Determinar o nível do inimigo baseado no nível máximo do time do jogador
    player_max_level = 1
    $player.party.each do |pkmn|
      player_max_level = pkmn.level if pkmn.level > player_max_level
    end

    formatted_pokemon = []
    selected_team.each do |pkmn_data|
      ev_hash = {
        :HP              => pkmn_data[:evs][0],
        :ATTACK          => pkmn_data[:evs][1],
        :DEFENSE         => pkmn_data[:evs][2],
        :SPECIAL_ATTACK  => pkmn_data[:evs][3],
        :SPECIAL_DEFENSE => pkmn_data[:evs][4],
        :SPEED           => pkmn_data[:evs][5]
      }
      formatted_pokemon << {
        :species => pkmn_data[:species],
        :level   => player_max_level,
        :item    => pkmn_data[:item],
        :ability => pkmn_data[:ability],
        :nature  => pkmn_data[:nature],
        :moves   => pkmn_data[:moves],
        :form    => pkmn_data[:form] || 0,
        :iv      => {:HP => 31, :ATTACK => 31, :DEFENSE => 31, :SPECIAL_ATTACK => 31, :SPECIAL_DEFENSE => 31, :SPEED => 31},
        :ev      => ev_hash
      }
    end

    trainer_type = resolver_trainer_type
    trainer_name = "Brock"
    version = pbGetFreeTrainerParty(trainer_type, trainer_name) || 0

    GameData::Trainer.register({
      :id           => [trainer_type, trainer_name, version],
      :trainer_type => trainer_type,
      :real_name    => trainer_name,
      :version      => version,
      # Mega Aro: sem ele pbHasMegaRing? falha e o chefe nunca megaevolui,
      # mesmo segurando a pedra.
      :items        => [:MEGARING, :FULLRESTORE],
      :pokemon      => formatted_pokemon,
    })

    # Configurar as regras estritas da Raid
    TrainerBattle.setBattleRule("nobag")
    TrainerBattle.setBattleRule("setstyle")
    TrainerBattle.setBattleRule("noExp")
    TrainerBattle.setBattleRule("battleBGM", "Batalla Jefe Torre")
    TrainerBattle.setBattleRule("canLose")

    TrainerBattle.setBattleRule("opponentlosetext", _INTL("Você me derrotou... Sua força é dura como uma rocha!"))
    TrainerBattle.setBattleRule("opponentwintext", _INTL("Minha defesa impenetrável superou seus ataques!"))

    outcome = 0
    pbMessage(_INTL("Brock quer batalhar!"))
    pbFadeOutIn {
      outcome = RaidTorre.batalha_de_raid(trainer_type, trainer_name, version)
    }

    if RaidTorre.venceu?(outcome)
      pbMessage(_INTL("Parabéns! Você venceu a Raid do Brock!"))
      RaidTorre.entregar_recompensa_raid("Brock")
      return 1
    else
      pbMessage(_INTL("Brock venceu você. Prepare-se melhor e tente novamente!"))
      return 2
    end
  end
end


# ==============================================================================
# 6. RAID DE LT. SURGE (Bilhete Surge)
# ==============================================================================
module RaidSurge
  EventHandlers.add(:on_trainer_load, :surge_raid_ai_boost, proc { |trainer|
    if trainer && trainer.name == "Teniente Surge"
      trainer.skill_level = 120
    end
  })

  def self.resolver_trainer_type
    [:LIDER3, :LIDER3REVANCHA].each do |type|
      return type if GameData::TrainerType.exists?(type)
    end
    return :POKEMONTRAINER_RojoNeutro
  end

  def self.carregar_times_surge
    dat_path = "Raid da Torre/Surge.dat"
    if File.exist?(dat_path)
      begin
        return Marshal.load(File.binread(dat_path))
      rescue => e
        echoln "Erro carregar Surge.dat: #{e.message}"
      end
    end
    echoln("RaidSurge: #{dat_path} ausente ou ilegivel (modo dat-only, sem fallback .txt).")
    return []
  end

  def self.iniciar_raid_surge
    # 1. Carregar os times de Surge
    teams = carregar_times_surge
    if teams.empty?
      pbMessage(_INTL("Lt. Surge não possui equipes prontas para batalha!"))
      return 0
    end

    # 2. Escolher um dos times de Surge de forma aleatória
    selected_team = teams.sample

    # 3. Determinar o nível do inimigo baseado no nível máximo do time do jogador
    player_max_level = 1
    $player.party.each do |pkmn|
      player_max_level = pkmn.level if pkmn.level > player_max_level
    end

    formatted_pokemon = []
    selected_team.each do |pkmn_data|
      ev_hash = {
        :HP              => pkmn_data[:evs][0],
        :ATTACK          => pkmn_data[:evs][1],
        :DEFENSE         => pkmn_data[:evs][2],
        :SPECIAL_ATTACK  => pkmn_data[:evs][3],
        :SPECIAL_DEFENSE => pkmn_data[:evs][4],
        :SPEED           => pkmn_data[:evs][5]
      }
      formatted_pokemon << {
        :species => pkmn_data[:species],
        :level   => player_max_level,
        :item    => pkmn_data[:item],
        :ability => pkmn_data[:ability],
        :nature  => pkmn_data[:nature],
        :moves   => pkmn_data[:moves],
        :form    => pkmn_data[:form] || 0,
        :iv      => {:HP => 31, :ATTACK => 31, :DEFENSE => 31, :SPECIAL_ATTACK => 31, :SPECIAL_DEFENSE => 31, :SPEED => 31},
        :ev      => ev_hash
      }
    end

    trainer_type = resolver_trainer_type
    trainer_name = "Teniente Surge"
    version = pbGetFreeTrainerParty(trainer_type, trainer_name) || 0

    GameData::Trainer.register({
      :id           => [trainer_type, trainer_name, version],
      :trainer_type => trainer_type,
      :real_name    => trainer_name,
      :version      => version,
      # Mega Aro: sem ele pbHasMegaRing? falha e o chefe nunca megaevolui,
      # mesmo segurando a pedra.
      :items        => [:MEGARING, :FULLRESTORE],
      :pokemon      => formatted_pokemon,
    })

    # Configurar as regras estritas da Raid
    TrainerBattle.setBattleRule("nobag")
    TrainerBattle.setBattleRule("setstyle")
    TrainerBattle.setBattleRule("noExp")
    TrainerBattle.setBattleRule("battleBGM", "Batalla Jefe Torre")
    TrainerBattle.setBattleRule("canLose")

    TrainerBattle.setBattleRule("opponentlosetext", _INTL("Você é realmente um soldado brilhante! Minha voltagem caiu a zero!"))
    TrainerBattle.setBattleRule("opponentwintext", _INTL("Sua estratégia não tem energia suficiente para me vencer!"))

    outcome = 0
    pbMessage(_INTL("Lt. Surge quer batalhar!"))
    pbFadeOutIn {
      outcome = RaidTorre.batalha_de_raid(trainer_type, trainer_name, version)
    }

    if RaidTorre.venceu?(outcome)
      pbMessage(_INTL("Parabéns! Você venceu a Raid do Lt. Surge!"))
      RaidTorre.entregar_recompensa_raid("Lt. Surge")
      return 1
    else
      pbMessage(_INTL("Lt. Surge venceu você. Prepare-se melhor e tente novamente!"))
      return 2
    end
  end
end


# ==============================================================================
# 7. RAID DE BLAINE (Bilhete Blaine)
# ==============================================================================
module RaidBlaine
  EventHandlers.add(:on_trainer_load, :blaine_raid_ai_boost, proc { |trainer|
    if trainer && trainer.name == "Blaine"
      trainer.skill_level = 120
    end
  })

  def self.resolver_trainer_type
    [:LIDER7, :LIDER7REVANCHA].each do |type|
      return type if GameData::TrainerType.exists?(type)
    end
    return :POKEMONTRAINER_RojoNeutro
  end

  def self.carregar_times_blaine
    dat_path = "Raid da Torre/Blaine.dat"
    if File.exist?(dat_path)
      begin
        return Marshal.load(File.binread(dat_path))
      rescue => e
        echoln "Erro carregar Blaine.dat: #{e.message}"
      end
    end
    echoln("RaidBlaine: #{dat_path} ausente ou ilegivel (modo dat-only, sem fallback .txt).")
    return []
  end

  def self.iniciar_raid_blaine
    # 1. Carregar os times de Blaine
    teams = carregar_times_blaine
    if teams.empty?
      pbMessage(_INTL("Blaine não possui equipes prontas para batalha!"))
      return 0
    end

    # 2. Escolher um dos times de Blaine de forma aleatória
    selected_team = teams.sample

    # 3. Determinar o nível do inimigo baseado no nível máximo do time do jogador
    player_max_level = 1
    $player.party.each do |pkmn|
      player_max_level = pkmn.level if pkmn.level > player_max_level
    end

    formatted_pokemon = []
    selected_team.each do |pkmn_data|
      ev_hash = {
        :HP              => pkmn_data[:evs][0],
        :ATTACK          => pkmn_data[:evs][1],
        :DEFENSE         => pkmn_data[:evs][2],
        :SPECIAL_ATTACK  => pkmn_data[:evs][3],
        :SPECIAL_DEFENSE => pkmn_data[:evs][4],
        :SPEED           => pkmn_data[:evs][5]
      }
      formatted_pokemon << {
        :species => pkmn_data[:species],
        :level   => player_max_level,
        :item    => pkmn_data[:item],
        :ability => pkmn_data[:ability],
        :nature  => pkmn_data[:nature],
        :moves   => pkmn_data[:moves],
        :form    => pkmn_data[:form] || 0,
        :iv      => {:HP => 31, :ATTACK => 31, :DEFENSE => 31, :SPECIAL_ATTACK => 31, :SPECIAL_DEFENSE => 31, :SPEED => 31},
        :ev      => ev_hash
      }
    end

    trainer_type = resolver_trainer_type
    trainer_name = "Blaine"
    version = pbGetFreeTrainerParty(trainer_type, trainer_name) || 0

    GameData::Trainer.register({
      :id           => [trainer_type, trainer_name, version],
      :trainer_type => trainer_type,
      :real_name    => trainer_name,
      :version      => version,
      # Mega Aro: sem ele pbHasMegaRing? falha e o chefe nunca megaevolui,
      # mesmo segurando a pedra.
      :items        => [:MEGARING, :FULLRESTORE],
      :pokemon      => formatted_pokemon,
    })

    # Configurar as regras estritas da Raid
    TrainerBattle.setBattleRule("nobag")
    TrainerBattle.setBattleRule("setstyle")
    TrainerBattle.setBattleRule("noExp")
    TrainerBattle.setBattleRule("battleBGM", "Batalla Jefe Torre")
    TrainerBattle.setBattleRule("canLose")

    TrainerBattle.setBattleRule("opponentlosetext", _INTL("Incrível! Fui reduzido a cinzas pela sua genialidade!"))
    TrainerBattle.setBattleRule("opponentwintext", _INTL("Minhas chamas são quentes demais para as suas estratégias!"))

    outcome = 0
    pbMessage(_INTL("Blaine quer batalhar!"))
    pbFadeOutIn {
      outcome = RaidTorre.batalha_de_raid(trainer_type, trainer_name, version)
    }

    if RaidTorre.venceu?(outcome)
      pbMessage(_INTL("Parabéns! Você venceu a Raid do Blaine!"))
      RaidTorre.entregar_recompensa_raid("Blaine")
      return 1
    else
      pbMessage(_INTL("Blaine venceu você. Prepare-se melhor e tente novamente!"))
      return 2
    end
  end
end


# ==============================================================================
# 8. RAID DE URANO (Bilhete Urano)
# ==============================================================================
module RaidUrano
  EventHandlers.add(:on_trainer_load, :urano_raid_ai_boost, proc { |trainer|
    if trainer && trainer.name == "Urano"
      trainer.skill_level = 120
    end
  })

  def self.resolver_trainer_type
    [:LIDER8, :LIDER8REVANCHA].each do |type|
      return type if GameData::TrainerType.exists?(type)
    end
    return :POKEMONTRAINER_RojoNeutro
  end

  def self.carregar_times_urano
    dat_path = "Raid da Torre/Urano.dat"
    if File.exist?(dat_path)
      begin
        return Marshal.load(File.binread(dat_path))
      rescue => e
        echoln "Erro carregar Urano.dat: #{e.message}"
      end
    end
    echoln("RaidUrano: #{dat_path} ausente ou ilegivel (modo dat-only, sem fallback .txt).")
    return []
  end

  def self.iniciar_raid_urano
    # 1. Carregar os times de Urano
    teams = carregar_times_urano
    if teams.empty?
      pbMessage(_INTL("Urano não possui equipes prontas para batalha!"))
      return 0
    end

    # 2. Escolher um dos times de Urano de forma aleatória
    selected_team = teams.sample

    # 3. Determinar o nível do inimigo baseado no nível máximo do time do jogador
    player_max_level = 1
    $player.party.each do |pkmn|
      player_max_level = pkmn.level if pkmn.level > player_max_level
    end

    formatted_pokemon = []
    selected_team.each do |pkmn_data|
      ev_hash = {
        :HP              => pkmn_data[:evs][0],
        :ATTACK          => pkmn_data[:evs][1],
        :DEFENSE         => pkmn_data[:evs][2],
        :SPECIAL_ATTACK  => pkmn_data[:evs][3],
        :SPECIAL_DEFENSE => pkmn_data[:evs][4],
        :SPEED           => pkmn_data[:evs][5]
      }
      formatted_pokemon << {
        :species => pkmn_data[:species],
        :level   => player_max_level,
        :item    => pkmn_data[:item],
        :ability => pkmn_data[:ability],
        :nature  => pkmn_data[:nature],
        :moves   => pkmn_data[:moves],
        :form    => pkmn_data[:form] || 0,
        :iv      => {:HP => 31, :ATTACK => 31, :DEFENSE => 31, :SPECIAL_ATTACK => 31, :SPECIAL_DEFENSE => 31, :SPEED => 31},
        :ev      => ev_hash
      }
    end

    trainer_type = resolver_trainer_type
    trainer_name = "Urano"
    version = pbGetFreeTrainerParty(trainer_type, trainer_name) || 0

    GameData::Trainer.register({
      :id           => [trainer_type, trainer_name, version],
      :trainer_type => trainer_type,
      :real_name    => trainer_name,
      :version      => version,
      # Mega Aro: sem ele pbHasMegaRing? falha e o chefe nunca megaevolui,
      # mesmo segurando a pedra.
      :items        => [:MEGARING, :FULLRESTORE],
      :pokemon      => formatted_pokemon,
    })

    # Configurar as regras estritas da Raid
    TrainerBattle.setBattleRule("nobag")
    TrainerBattle.setBattleRule("setstyle")
    TrainerBattle.setBattleRule("noExp")
    TrainerBattle.setBattleRule("battleBGM", "Batalla Jefe Torre")
    TrainerBattle.setBattleRule("canLose")

    TrainerBattle.setBattleRule("opponentlosetext", _INTL("Incrível! Fui superado pela força dos seus insetos e estratégias!"))
    TrainerBattle.setBattleRule("opponentwintext", _INTL("A determinação dos meus tipos inseto é inquebrável!"))

    outcome = 0
    pbMessage(_INTL("Urano quer batalhar!"))
    pbFadeOutIn {
      outcome = RaidTorre.batalha_de_raid(trainer_type, trainer_name, version)
    }

    if RaidTorre.venceu?(outcome)
      pbMessage(_INTL("Parabéns! Você venceu a Raid do Urano!"))
      RaidTorre.entregar_recompensa_raid("Urano")
      return 1
    else
      pbMessage(_INTL("Urano venceu você. Prepare-se melhor e tente novamente!"))
      return 2
    end
  end
end

# ==============================================================================
# 9. RAID DE ERIKA (Bilhete Erika)
# ==============================================================================
module RaidErika
  EventHandlers.add(:on_trainer_load, :erika_raid_ai_boost, proc { |trainer|
    if trainer && trainer.name == "Erika"
      trainer.skill_level = 120
    end
  })

  def self.resolver_trainer_type
    [:LIDER4, :LIDER4REVANCHA].each do |type|
      return type if GameData::TrainerType.exists?(type)
    end
    return :POKEMONTRAINER_RojoNeutro
  end

  def self.carregar_times_erika
    dat_path = "Raid da Torre/Erika.dat"
    if File.exist?(dat_path)
      begin
        return Marshal.load(File.binread(dat_path))
      rescue => e
        echoln "Erro carregar Erika.dat: #{e.message}"
      end
    end
    echoln("RaidErika: #{dat_path} ausente ou ilegivel (modo dat-only, sem fallback .txt).")
    return []
  end

  def self.iniciar_raid_erika
    # 1. Carregar os times de Erika
    teams = carregar_times_erika
    if teams.empty?
      pbMessage(_INTL("Erika não possui equipes prontas para batalha!"))
      return 0
    end

    # 2. Escolher um dos times de Erika de forma aleatória
    selected_team = teams.sample

    # 3. Determinar o nível do inimigo baseado no nível máximo do time do jogador
    player_max_level = 1
    $player.party.each do |pkmn|
      player_max_level = pkmn.level if pkmn.level > player_max_level
    end

    formatted_pokemon = []
    selected_team.each do |pkmn_data|
      ev_hash = {
        :HP              => pkmn_data[:evs][0],
        :ATTACK          => pkmn_data[:evs][1],
        :DEFENSE         => pkmn_data[:evs][2],
        :SPECIAL_ATTACK  => pkmn_data[:evs][3],
        :SPECIAL_DEFENSE => pkmn_data[:evs][4],
        :SPEED           => pkmn_data[:evs][5]
      }
      formatted_pokemon << {
        :species => pkmn_data[:species],
        :level   => player_max_level,
        :item    => pkmn_data[:item],
        :ability => pkmn_data[:ability],
        :nature  => pkmn_data[:nature],
        :moves   => pkmn_data[:moves],
        :form    => pkmn_data[:form] || 0,
        :iv      => {:HP => 31, :ATTACK => 31, :DEFENSE => 31, :SPECIAL_ATTACK => 31, :SPECIAL_DEFENSE => 31, :SPEED => 31},
        :ev      => ev_hash
      }
    end

    trainer_type = resolver_trainer_type
    trainer_name = "Erika"
    version = pbGetFreeTrainerParty(trainer_type, trainer_name) || 0

    GameData::Trainer.register({
      :id           => [trainer_type, trainer_name, version],
      :trainer_type => trainer_type,
      :real_name    => trainer_name,
      :version      => version,
      # Mega Aro: sem ele pbHasMegaRing? falha e o chefe nunca megaevolui,
      # mesmo segurando a pedra.
      :items        => [:MEGARING, :FULLRESTORE],
      :pokemon      => formatted_pokemon,
    })

    # Configurar as regras estritas da Raid
    TrainerBattle.setBattleRule("nobag")
    TrainerBattle.setBattleRule("setstyle")
    TrainerBattle.setBattleRule("noExp")
    TrainerBattle.setBattleRule("battleBGM", "Batalla Jefe Torre")
    TrainerBattle.setBattleRule("canLose")

    TrainerBattle.setBattleRule("opponentlosetext", _INTL("Que batalha perfumada... Suas estratégias floresceram incrivelmente!"))
    TrainerBattle.setBattleRule("opponentwintext", _INTL("A natureza sempre encontra um caminho para a vitória!"))

    outcome = 0
    pbMessage(_INTL("Erika quer batalhar!"))
    pbFadeOutIn {
      outcome = RaidTorre.batalha_de_raid(trainer_type, trainer_name, version)
    }

    if RaidTorre.venceu?(outcome)
      pbMessage(_INTL("Parabéns! Você venceu a Raid da Erika!"))
      RaidTorre.entregar_recompensa_raid("Erika")
      return 1
    else
      pbMessage(_INTL("Erika venceu você. Prepare-se melhor e tente novamente!"))
      return 2
    end
  end
end




