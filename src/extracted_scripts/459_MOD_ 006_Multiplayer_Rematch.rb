# ======================================================================
# MÓDULO: SISTEMA DE REVANCHE
# Fonte: 0452_Multiplayer_Rematch.rb (1256 linhas)
# Cópia fiel 1:1 do script original para facilitar manutenção.
# ======================================================================

# encoding: UTF-8
# ==============================================================================
# SISTEMA DE REVANCHE MULTIPLAYER (Versão 4.5.2 - Blinking Balloons)
# ==============================================================================

module AnilLanRework
  module RematchSystem
    @messages_solo = []
    @messages_coop_accepted = []
    @messages_coop_declined = []
    @messages_waiting = []
    @messages_item = []
    @messages_gift_common = []
    @messages_gift_uncommon = []
    @messages_gift_rare = []
    @messages_gift_legendary = []
    @messages_capture = []
    @messages_evolution = []
    @messages_egg_grey = []
    @messages_egg_green = []
    @messages_egg_blue = []
    @messages_egg_purple = []
    @messages_egg_orange = []
    @gift_sprites = {}
    @rematch_sprites = {}
    @blink_timer = 0
    
    COOLDOWN_TIME = 1200 # 20 minutos
    
    RARE_ITEMS = [:RARECANDY, :PPUP, :MAXREVIVE, :OLDAMBER, :HELIXFOSSIL, :DOMEFOSSIL]
    VERY_RARE_ITEMS = [:PPMAX, :ABILITYCAPSULE, :ABILITYPATCH]
    
    # Categorias de Presentes
    # As Caixas de Presente entram aqui pela raridade do proprio sorteio em
    # roll_for_reward: Verde 5%, Azul 2%, Laranja 0,5%. Sem isto elas caiam no
    # else de get_msg_gift e a Laranja — a mais rara do jogo — ganhava fala de comum.
    GIFT_COMMON = [:POTION, :POKEBALL, :REPEL, :ORANBERRY, :PECHABERRY]
    GIFT_UNCOMMON = [:SUPERPOTION, :GREATBALL, :SUPERREPEL, :SITRUSBERRY]
    GIFT_RARE = [:ULTRABALL, :MAXPOTION, :HYPERPOTION, :FULLRESTORE]
    GIFT_LEGENDARY = [:RARECANDY, :PPMAX]
    EXTRA_PARTY_STAGE_WEIGHTS = {
      :mega         => 5,   # peso relativo mais raro
      :final        => 10,  # peso relativo raro
      :intermediate => 30,  # peso relativo incomum
      :first        => 100  # peso relativo comum
    }

    class << self
      def enabled?
        true
      end

      def log(msg)
        if defined?(AnilLanRework) && AnilLanRework.respond_to?(:log)
          AnilLanRework.log(msg)
        else
          print "REMATCH_LOG: #{msg}\n" if $DEBUG
        end
      end

      def load_all_messages
        @messages_solo ||= []
        return unless @messages_solo.empty?
        
        dat_path = "Data/rematch_data.dat"
        txt_path = "Data/frases_revanche.txt"

        # Tenta carregar do .dat primeiro (mais rápido e protegido)
        if File.exist?(dat_path)
          begin
            data = File.open(dat_path, "rb") { |f| Marshal.load(f) }
            @messages_solo = data[:solo] || []
            @messages_coop_accepted = data[:coop_accepted] || []
            @messages_coop_declined = data[:coop_declined] || []
            @messages_waiting = data[:waiting] || []
            @messages_item = data[:item] || []
            @messages_gift_common = data[:gift_common] || []
            @messages_gift_uncommon = data[:gift_uncommon] || []
            @messages_gift_rare = data[:gift_rare] || []
            @messages_gift_legendary = data[:gift_legendary] || []
            @messages_capture = data[:capture] || []
            @messages_evolution = data[:evolution] || []
            @messages_egg_grey = data[:egg_grey] || []
            @messages_egg_green = data[:egg_green] || []
            @messages_egg_blue = data[:egg_blue] || []
            @messages_egg_purple = data[:egg_purple] || []
            @messages_egg_orange = data[:egg_orange] || []
            log("rematch: #{dat_path} carregado com sucesso.")
            return unless @messages_solo.empty?
          rescue => e
            log("rematch: Erro ao carregar .dat: #{e.message}. Tentando .txt...")
          end
        end

        # Fallback para o .txt e auto-compilação se estiver em Debug
        if File.exist?(txt_path)
          lines = File.readlines(txt_path, encoding: 'bom|utf-8').map(&:strip).reject(&:empty?)
          @messages_solo = lines.select { |l| l.start_with?("[SOLO]") }.map { |l| l.gsub("[SOLO]", "").strip }
          @messages_coop_accepted = lines.select { |l| l.start_with?("[ACEITO]") }.map { |l| l.gsub("[ACEITO]", "").strip }
          @messages_coop_declined = lines.select { |l| l.start_with?("[RECUSADO]") }.map { |l| l.gsub("[RECUSADO]", "").strip }
          @messages_waiting = lines.select { |l| l.start_with?("[AGUARDE]") }.map { |l| l.gsub("[AGUARDE]", "").strip }
          @messages_item = lines.select { |l| l.start_with?("[ITEM]") }.map { |l| l.gsub("[ITEM]", "").strip }
          @messages_gift_common = lines.select { |l| l.start_with?("[GIFT_COMMON]") }.map { |l| l.gsub("[GIFT_COMMON]", "").strip }
          @messages_gift_uncommon = lines.select { |l| l.start_with?("[GIFT_UNCOMMON]") }.map { |l| l.gsub("[GIFT_UNCOMMON]", "").strip }
          @messages_gift_rare = lines.select { |l| l.start_with?("[GIFT_RARE]") }.map { |l| l.gsub("[GIFT_RARE]", "").strip }
          @messages_gift_legendary = lines.select { |l| l.start_with?("[GIFT_LEGENDARY]") }.map { |l| l.gsub("[GIFT_LEGENDARY]", "").strip }
          @messages_capture = lines.select { |l| l.start_with?("[CAPTURA]") }.map { |l| l.gsub("[CAPTURA]", "").strip }
          @messages_evolution = lines.select { |l| l.start_with?("[EVOLUCAO]") }.map { |l| l.gsub("[EVOLUCAO]", "").strip }
          @messages_egg_grey = lines.select { |l| l.start_with?("[OVO_CINZA]") }.map { |l| l.gsub("[OVO_CINZA]", "").strip }
          @messages_egg_green = lines.select { |l| l.start_with?("[OVO_VERDE]") }.map { |l| l.gsub("[OVO_VERDE]", "").strip }
          @messages_egg_blue = lines.select { |l| l.start_with?("[OVO_AZUL]") }.map { |l| l.gsub("[OVO_AZUL]", "").strip }
          @messages_egg_purple = lines.select { |l| l.start_with?("[OVO_ROXO]") }.map { |l| l.gsub("[OVO_ROXO]", "").strip }
          @messages_egg_orange = lines.select { |l| l.start_with?("[OVO_LARANJA]") }.map { |l| l.gsub("[OVO_LARANJA]", "").strip }
          
          # Se estiver no RPG Maker (Editor), compila o .dat automaticamente para o próximo release
          if $DEBUG || defined?(RMXP)
            compile_phrases_to_dat
          end
        end

        # Mensagens padrão de segurança
        @messages_solo = ["Lembro do seu {pkmn}... Vamos de novo?"] if @messages_solo.empty?
        @messages_coop_accepted = ["Trouxe o {parceiro}? Dois contra um?"] if @messages_coop_accepted.empty?
        @messages_coop_declined = ["Ué, o {parceiro} te deixou na mão?"] if @messages_coop_declined.empty?
        @messages_waiting = ["Meus Pokémon precisam descansar. Volte depois!"] if @messages_waiting.empty?
        @messages_item = ["Tome isto por me dar uma luta tão boa!"] if @messages_item.empty?
        @messages_gift_common = ["Fique com isto!"] if @messages_gift_common.empty?
        @messages_gift_uncommon = ["Nao e grande coisa, mas voce mereceu. Leve."] if @messages_gift_uncommon.empty?
        @messages_gift_rare = ["Você merece um presente especial!"] if @messages_gift_rare.empty?
        @messages_gift_legendary = ["Isto é um tesouro raro! Use com sabedoria."] if @messages_gift_legendary.empty?
        @messages_capture = ["Olha só! Capturei um novo amigo no caminho!"] if @messages_capture.empty?
        @messages_evolution = ["Meu {pkmn} está mudando... evoluiu!"] if @messages_evolution.empty?
        @messages_egg_grey = ["Ganhei esse ovo, mas não sei qual Pokémon vai nascer. Fica pra você!"] if @messages_egg_grey.empty?
        @messages_egg_green = ["Bela batalha! Leve este ovo, sinto que ele dará origem a um bom parceiro de jornada."] if @messages_egg_green.empty?
        @messages_egg_blue = ["Incrível! Você merece este ovo incomum. Cuide bem dele!"] if @messages_egg_blue.empty?
        @messages_egg_purple = ["Uau, que força! Esse ovo roxo é muito raro, sinto que ele deve ser seu."] if @messages_egg_purple.empty?
        @messages_egg_orange = ["Este ovo emite uma aura colossal! Ele carrega o potencial de um Pokémon incrível. Por favor, fique com ele!"] if @messages_egg_orange.empty?
      end

      # Compila o arquivo .txt para um binário .dat para proteção e performance
      def compile_phrases_to_dat
        txt_path = "Data/frases_revanche.txt"
        dat_path = "Data/rematch_data.dat"
        return unless File.exist?(txt_path)

        log("rematch: Compilando #{txt_path} para #{dat_path}...")
        lines = File.readlines(txt_path, encoding: 'bom|utf-8').map(&:strip).reject(&:empty?)
        data = {
          solo: lines.select { |l| l.start_with?("[SOLO]") }.map { |l| l.gsub("[SOLO]", "").strip },
          coop_accepted: lines.select { |l| l.start_with?("[ACEITO]") }.map { |l| l.gsub("[ACEITO]", "").strip },
          coop_declined: lines.select { |l| l.start_with?("[RECUSADO]") }.map { |l| l.gsub("[RECUSADO]", "").strip },
          waiting: lines.select { |l| l.start_with?("[AGUARDE]") }.map { |l| l.gsub("[AGUARDE]", "").strip },
          item: lines.select { |l| l.start_with?("[ITEM]") }.map { |l| l.gsub("[ITEM]", "").strip },
          gift_common: lines.select { |l| l.start_with?("[GIFT_COMMON]") }.map { |l| l.gsub("[GIFT_COMMON]", "").strip },
          gift_uncommon: lines.select { |l| l.start_with?("[GIFT_UNCOMMON]") }.map { |l| l.gsub("[GIFT_UNCOMMON]", "").strip },
          gift_rare: lines.select { |l| l.start_with?("[GIFT_RARE]") }.map { |l| l.gsub("[GIFT_RARE]", "").strip },
          gift_legendary: lines.select { |l| l.start_with?("[GIFT_LEGENDARY]") }.map { |l| l.gsub("[GIFT_LEGENDARY]", "").strip },
          capture: lines.select { |l| l.start_with?("[CAPTURA]") }.map { |l| l.gsub("[CAPTURA]", "").strip },
          evolution: lines.select { |l| l.start_with?("[EVOLUCAO]") }.map { |l| l.gsub("[EVOLUCAO]", "").strip },
          egg_grey: lines.select { |l| l.start_with?("[OVO_CINZA]") }.map { |l| l.gsub("[OVO_CINZA]", "").strip },
          egg_green: lines.select { |l| l.start_with?("[OVO_VERDE]") }.map { |l| l.gsub("[OVO_VERDE]", "").strip },
          egg_blue: lines.select { |l| l.start_with?("[OVO_AZUL]") }.map { |l| l.gsub("[OVO_AZUL]", "").strip },
          egg_purple: lines.select { |l| l.start_with?("[OVO_ROXO]") }.map { |l| l.gsub("[OVO_ROXO]", "").strip },
          egg_orange: lines.select { |l| l.start_with?("[OVO_LARANJA]") }.map { |l| l.gsub("[OVO_LARANJA]", "").strip }
        }

        File.open(dat_path, "wb") { |f| Marshal.dump(data, f) }
        log("rematch: Compilação concluída!")
      end

      def get_msg_egg(rarity)
        load_all_messages
        case rarity
        when :orange then @messages_egg_orange.sample
        when :purple then @messages_egg_purple.sample
        when :blue   then @messages_egg_blue.sample
        when :green  then @messages_egg_green.sample
        else              @messages_egg_grey.sample
        end
      end

      def get_msg_gift(item)
        load_all_messages
        item_sym = item.to_sym rescue nil
        if item_sym.to_s.start_with?("EGG_") || item_sym == :EGG
          rarity = :grey
          # start_with? cobre as variantes (_SHINY / _SUPERSHINY) junto da cor base.
          item_str = item_sym.to_s
          rarity = :orange if item_str.start_with?("EGG_ORANGE")
          rarity = :purple if item_str.start_with?("EGG_PURPLE")
          rarity = :blue if item_str.start_with?("EGG_BLUE")
          rarity = :green if item_str.start_with?("EGG_GREEN")
          return get_msg_egg(rarity)
        end
        # Caixas de Presente classificadas AQUI, e nao nas constantes GIFT_*:
        # aquelas listas tambem sao os poolss de sorteio de roll_gift_item, entao
        # incluir as caixas nelas faria o NPC de presente passar a entrega-las —
        # inclusive para jogador offline, que nem consegue abrir (068_Gift_Boxes).
        # A faixa segue a chance real do drop: Verde 5%, Azul 2%, Laranja 0,5%.
        case item_sym
        when :GIFT_ORANGE then return @messages_gift_legendary.sample
        when :GIFT_BLUE   then return @messages_gift_rare.sample
        when :GIFT_GREEN  then return @messages_gift_uncommon.sample
        end

        if GIFT_LEGENDARY.include?(item_sym)
          return @messages_gift_legendary.sample
        elsif GIFT_RARE.include?(item_sym)
          return @messages_gift_rare.sample
        elsif GIFT_UNCOMMON.include?(item_sym)
          return @messages_gift_uncommon.sample
        else
          return @messages_gift_common.sample
        end
      end

      def get_msg_memory(pkmn_name)
        load_all_messages
        pkmn_name ||= $player.party[0].name rescue "Pokémon"
        @messages_solo.sample.gsub("{pkmn}", pkmn_name)
      end

      def get_msg_item
        load_all_messages
        @messages_item.sample
      end

      def get_msg_capture
        load_all_messages
        return @messages_capture.sample || "Vou reforçar meu time!"
      end

      def extract_species_list_from_party(party)
        return [] unless party.respond_to?(:each)
        ret = []
        party.each do |pkmn|
          species = pkmn.species if pkmn && pkmn.respond_to?(:species)
          ret << species if species
        end
        ret
      end

      def build_party_entry_from_pokemon(pkmn)
        return nil unless pkmn && pkmn.respond_to?(:species)
        species = pkmn.species
        form = (pkmn.form rescue 0).to_i
        species_data = nil
        species_data = GameData::Species.get_species_form(species, form) rescue nil
        species_data ||= GameData::Species.get(species) rescue nil
        return build_extra_party_entry(species_data) if species_data
        return species
      end

      def extract_extra_party_entries_from_party(party, base_party_size)
        return [] unless party.respond_to?(:each_with_index)
        ret = []
        party.each_with_index do |pkmn, idx|
          next if idx < base_party_size.to_i
          entry = build_party_entry_from_pokemon(pkmn)
          ret << entry if entry
        end
        ret
      end

      def recorded_base_party_species(data, trainer_data = nil)
        base_party = data[:base_party_species]
        return base_party.compact if base_party.is_a?(Array) && !base_party.empty?
        trainer_data ||= GameData::Trainer.get(data[:type], data[:name], data[:version]) rescue nil
        return [] unless trainer_data
        return trainer_data.pokemon.map { |pkmn| pkmn[:species] }.compact
      end

      def sanitize_evolved_party!(data, base_party_species = nil)
        evolved = data[:evolved_party]
        evolved = {} unless evolved.is_a?(Hash)
        base_party_species ||= recorded_base_party_species(data)
        base_party_species ||= []
        evolved.delete_if do |idx, species|
          slot = idx.to_i
          species.nil? || base_party_species[slot] == species
        end
        data[:evolved_party] = evolved
      end

      def migrate_legacy_party_state!(data, trainer_data = nil)
        had_snapshot = data[:base_party_species].is_a?(Array) && !data[:base_party_species].empty?
        base_party_species = recorded_base_party_species(data, trainer_data)
        data[:base_party_species] = base_party_species if !base_party_species.empty?
        if !had_snapshot && data[:evolved_party].is_a?(Hash) && data[:evolved_party].size > 1
          log("rematch: Limpando estado legado de evolução para #{data[:name]} (snapshot antigo ausente).")
          data[:evolved_party] = {}
        end
        sanitize_evolved_party!(data, base_party_species)
        base_party_species
      end

      def sanitize_level_offsets!(data, total_slots = nil)
        offsets = data[:level_offsets]
        offsets = {} unless offsets.is_a?(Hash)
        sanitized = {}
        offsets.each do |idx, value|
          slot = idx.to_i
          amount = value.to_i
          next if slot < 0 || amount <= 0
          next if total_slots && slot >= total_slots
          sanitized[slot] = amount
        end
        data[:level_offsets] = sanitized
      end

      def migrate_legacy_level_offsets!(data, total_slots)
        sanitize_level_offsets!(data, total_slots)
        legacy_offset = data[:level_offset].to_i
        if legacy_offset > 0 && data[:level_offsets].empty?
          (0...total_slots).each { |idx| data[:level_offsets][idx] = legacy_offset }
        end
        data[:level_offset] = 0
        data[:level_offsets]
      end

      def slot_level_offset(data, idx)
        offsets = data[:level_offsets]
        return 0 unless offsets.is_a?(Hash)
        return offsets[idx.to_i].to_i
      end

      def has_level_up_evolution?(species)
        species_data = GameData::Species.get(species) rescue nil
        return false unless species_data
        species_data.get_evolutions(true).any? do |evo|
          method = evo[1]
          evo_data = GameData::Evolution.get(method) rescue nil
          evo_data && !evo_data.level_up_proc.nil?
        end
      rescue
        false
      end

      def normalize_extra_party_entry(entry)
        if entry.is_a?(Hash)
          species = entry[:species] || entry["species"]
          return nil unless species
          form = (entry[:form] || entry["form"] || 0).to_i
          species = species.to_sym rescue species
          return (form > 0) ? { :species => species, :form => form } : species
        end
        species_data = GameData::Species.get(entry) rescue nil
        return nil unless species_data
        return { :species => species_data.species, :form => species_data.form } if species_data.form > 0
        return species_data.species
      end

      def extra_party_entry_species_data(entry)
        normalized = normalize_extra_party_entry(entry)
        return nil unless normalized
        if normalized.is_a?(Hash)
          species = normalized[:species] || normalized["species"]
          form = (normalized[:form] || normalized["form"] || 0).to_i
          return GameData::Species.get_species_form(species, form) || GameData::Species.get(species)
        end
        return GameData::Species.get(normalized)
      rescue
        nil
      end

      def extra_party_entry_label(entry)
        species_data = extra_party_entry_species_data(entry)
        return species_data.name if species_data
        return entry.inspect
      end

      def build_extra_party_entry(species_data)
        return nil unless species_data
        if species_data.form && species_data.form > 0
          return { :species => species_data.species, :form => species_data.form }
        end
        return species_data.species
      end

      def stage_weight_for_extra_party(species_data)
        return 0 unless species_data
        if species_data.form > 0
          return (species_data.mega_stone || species_data.mega_move) ? EXTRA_PARTY_STAGE_WEIGHTS[:mega] : 0
        end
        previous_species = species_data.get_previous_species
        evolutions = species_data.get_evolutions(true)
        has_previous = previous_species != species_data.species
        has_next = !evolutions.empty?
        return EXTRA_PARTY_STAGE_WEIGHTS[:first] if !has_previous && has_next
        return EXTRA_PARTY_STAGE_WEIGHTS[:intermediate] if has_previous && has_next
        return EXTRA_PARTY_STAGE_WEIGHTS[:final]
      end

      def weighted_extra_party_candidate(candidates)
        total_weight = candidates.inject(0) { |sum, candidate| sum + candidate[1].to_i }
        return nil if total_weight <= 0
        roll = rand(total_weight)
        candidates.each do |entry, weight|
          roll -= weight.to_i
          return entry if roll < 0
        end
        return candidates[-1][0]
      end

      def get_msg_evolution(previous_name, evolved_name = nil)
        load_all_messages
        msg = @messages_evolution.sample || "Meu {pkmn} evoluiu para {evolved}!"
        msg = msg.gsub("{pkmn}", previous_name.to_s)
        msg = msg.gsub("{evolved}", evolved_name.to_s) if evolved_name
        return msg
      end

      def clean_peer_name(raw_name)
        peer = nil
        if raw_name.respond_to?(:name)
          peer = raw_name
        else
          peer = AnilLanRework.players[raw_name.to_s] rescue nil
        end
        if peer && peer.name && peer.name != "" && !peer.name.to_s.include?("Peer")
          return peer.name.to_s.capitalize
        end
        parts = raw_name.to_s.split('-')
        name = parts.last.to_s.capitalize
        name = "Parceiro" if name == "" || name.length < 2 || name.include?("Peer")
        name
      end

      def get_msg_coop_accepted(partner)
        load_all_messages
        name = clean_peer_name(partner)
        @messages_coop_accepted.sample.gsub("{parceiro}", name)
      end

      def get_msg_coop_declined(partner_tried)
        load_all_messages
        name = clean_peer_name(partner_tried)
        msg = @messages_coop_declined.sample
        msg = msg.gsub("{parceiro}", name)
        msg
      end

      def get_msg_waiting
        load_all_messages
        @messages_waiting.sample
      end

      def should_offer_rematch?(event)
        return false unless enabled? && event.is_a?(Game_Event)
        return false if event.instance_variable_get(:@erased) == true
        return false if event.character_name.nil? || event.character_name.to_s.empty?
        return false if event.transparent rescue false
        map_id = $game_map.map_id rescue 0
        sw_a = $game_self_switches[[map_id, event.id, "A"]] rescue false
        sw_b = $game_self_switches[[map_id, event.id, "B"]] rescue false
        
        # Só oferece revanche se tiver dados salvos (ID e Nome conhecidos)
        data = ($PokemonGlobal.defeated_trainers || {})[[map_id, event.id]]
        return false if data.nil?

        # Se as switches A ou B estiverem ON, significa que o treinador já foi vencido no passado
        return false unless sw_a == true || sw_b == true

        # ⚠️ A SWITCH LIGADA NAO QUER DIZER SO "JA O VENCI".
        #
        # As self-switches A e B sao o que TODA a gente usa para marcar progresso
        # — inclusive as missoes. Um NPC que da uma missao E que luta alguma vez
        # fica em defeated_trainers; a partir dai, no momento em que a missao
        # liga a switch A, esta funcao dizia "treinador vencido" e a revanche
        # tomava conta da conversa. O jogador ia falar sobre a missao e recebia
        # uma proposta de luta.
        #
        # Foi o que aconteceu com a mulher que da o cartao dos caes lendarios.
        #
        # A pergunta certa nao e "esta switch esta ligada?" mas sim "a pagina que
        # esta activa AGORA ainda tem alguma coisa para dizer?". Uma pagina de
        # pos-derrota tipica so tem uma fala curta; uma pagina de missao tem
        # ramos, condicoes e entregas. Se a pagina activa ainda faz trabalho,
        # ela ganha — e a revanche fica para quando o evento nao tiver mais nada
        # a fazer.
        pagina_faz_trabalho?(event) ? false : true
      rescue
        false
      end

      # Quantos comandos "de verdade" tem a pagina activa. O 0 e o fim de lista,
      # o 108/408 sao comentarios, e o 101/401 e uma fala — que sozinha e o
      # padrao de uma pagina de pos-derrota.
      COMANDOS_VAZIOS = [0, 108, 408, 101, 401].freeze

      def pagina_faz_trabalho?(event)
        pagina = (event.instance_variable_get(:@page) rescue nil)
        lista = (pagina && pagina.list) rescue nil
        return false unless lista.is_a?(Array)
        lista.any? { |cmd| !COMANDOS_VAZIOS.include?(cmd.code.to_i) }
      rescue
        # Na duvida, deixa o evento correr: perder uma revanche e um aborrecimento,
        # perder uma missao e um jogador preso.
        true
      end

      def get_trainer_with_fallbacks(t_type, t_name, t_version)
        t_type_sym = t_type.to_sym rescue t_type.to_s
        t_type_str = t_type.to_s
        t_name_str = t_name.to_s
        preferred_versions = [t_version.to_i, 0].uniq

        # Estratégia 1: exists? + get com símbolo e string do tipo
        [t_type_sym, t_type_str].each do |tt|
          preferred_versions.each do |v|
            begin
              if GameData::Trainer.exists?(tt, t_name_str, v)
                return GameData::Trainer.get(tt, t_name_str, v).to_trainer
              end
            rescue
            end
          end
        end

        # Estratégia 2: DATA hash direto (Essentials v17/v18)
        begin
          data_hash = GameData::Trainer::DATA rescue nil
          if data_hash
            preferred_versions.each do |wanted_version|
              data_hash.each_value do |td|
                begin
                  td_type = td.respond_to?(:trainer_type) ? td.trainer_type.to_s.upcase : ""
                  td_name = td.respond_to?(:real_name) ? td.real_name.to_s : ""
                  td_name = td.respond_to?(:name) ? td.name.to_s : td_name if td_name.empty?
                  td_version = td.respond_to?(:version) ? td.version.to_i : 0
                  next unless td_version == wanted_version
                  if td_type == t_type_str.upcase && td_name.downcase == t_name_str.downcase
                    log("rematch: Trainer encontrado via DATA hash: #{td_type} #{td_name} v#{td_version}")
                    return td.to_trainer
                  end
                rescue
                end
              end
            end
          end
        rescue
        end

        # Log de diagnóstico: mostra os primeiros tipos/nomes disponíveis no GameData
        begin
          sample = []
          (GameData::Trainer::DATA rescue {}).each_value do |td|
            break if sample.size >= 5
            sample << "#{td.trainer_type rescue '?'}/#{td.real_name rescue td.name rescue '?'}"
          end
          log("rematch: DEBUG - GameData amostras: #{sample.join(', ')}") unless sample.empty?
          log("rematch: DEBUG - Buscando: type=#{t_type_sym.inspect} name=#{t_name_str.inspect}")
        rescue
        end

        nil
      end

      def offer_rematch(event)
        key = [$game_map.map_id, event.id]
        data = ($PokemonGlobal.defeated_trainers || {})[key]
        return false unless data

        # Limpa decisao antiga para nao contaminar este ciclo
        $game_temp.anil_rematch_last_decision = nil

        # Verifica cooldown
        if data[:last_rematch_at]
          time_passed = Time.now.to_i - data[:last_rematch_at]
          if time_passed < COOLDOWN_TIME
            pbMessage(get_msg_waiting)
            return true
          end
        end

        pbMessage(get_msg_memory(data[:winner_pkmn]))
        $PokemonGlobal.anil_rematch_context = [event.id, $game_map.map_id]
        log("rematch: Contexto PERSISTENTE salvo para Evento:#{event.id} Mapa:#{$game_map.map_id}")

        t_type    = data[:type]
        t_name    = data[:name]
        t_version = data[:version] || 0
        log("rematch: TENTANDO CARREGAR #{t_type} #{t_name} v#{t_version}")

        trainer = get_trainer_with_fallbacks(t_type, t_name, t_version)

        if trainer
          apply_trainer_evolution(trainer, data)
          coop_accepted = false
          if AnilLanRework.connected? && $PokemonSystem.coop_trainer_invites != 1
            partner_on_map = AnilLanRework::BattleSync.partner_on_same_map rescue nil
            if partner_on_map && AnilLanRework.players.size > 0
              dist = [(partner_on_map.x.to_i - $game_player.x.to_i).abs,
                      (partner_on_map.y.to_i - $game_player.y.to_i).abs].max rescue 99
              if dist <= 12 && !(Input.press?(Input::CTRL) rescue false)
                  res = AnilLanRework::BattleSync.request_coop_battle(kind: :rematch, foe_trainers: [trainer])
                  if res.is_a?(Hash)
                    coop_accepted = true
                    pbMessage(get_msg_coop_accepted((partner_on_map.internal_id.to_s rescue "Parceiro")))
                    AnilLanRework::BattleSync.send_start_signal(partner_on_map.internal_id) rescue nil
                    AnilLanRework.connection.flush_batch rescue nil
                  else
                    pbMessage(get_msg_coop_declined((partner_on_map.internal_id.to_s rescue nil)))
                    $game_temp.instance_variable_set(:@anil_skip_coop_invite, true) rescue nil
                  end
              end
            end
          end
          begin
            if coop_accepted && TrainerBattle.respond_to?(:anil_rework_original_start)
              TrainerBattle.anil_rework_original_start(trainer)
            else
              $game_temp.instance_variable_set(:@anil_skip_coop_invite, true) rescue nil
              TrainerBattle.start(trainer)
            end
          rescue => e
            log("rematch: Erro ao iniciar batalha via GameData: #{e.message}")
          end
          return true
        else
          # Trainer de rota: nao esta no GameData. Reseta switch A e delega ao evento original.
          # on_end_battle capturara o resultado e atualizara os dados.
          log("rematch: Trainer de rota (#{t_type} #{t_name}) - delegando ao evento original.")
          mid = $game_map.map_id
          $game_self_switches[[mid, event.id, "A"]] = false
          $game_map.need_refresh = true rescue nil
          return false
        end
      end

      def store_defeated_trainer_data(trainer_type, trainer_name, trainer_version, event_id, map_id, winner_name = nil, partner_name = nil, trainer_party = nil)
        $PokemonGlobal.defeated_trainers ||= {}
        key = [map_id.to_i, event_id.to_i]

        # Preserva o tempo da última revanche se estiver apenas atualizando dados de vitória normal
        old_data = $PokemonGlobal.defeated_trainers[key] || {}
        version = trainer_version.nil? ? (old_data[:version] || 0).to_i : trainer_version.to_i
        trainer_data = GameData::Trainer.get(trainer_type.to_sym, trainer_name.to_s, version) rescue nil
        base_party_species = old_data[:base_party_species] if old_data[:base_party_species].is_a?(Array) && !old_data[:base_party_species].empty?
        base_party_species ||= trainer_data ? trainer_data.pokemon.map { |pkmn| pkmn[:species] }.compact : []
        if base_party_species.empty?
          base_party_size = trainer_data ? trainer_data.pokemon.size : nil
          base_party_species = extract_species_list_from_party(trainer_party)
          base_party_species = base_party_species[0, base_party_size] if base_party_size && base_party_size > 0
        end
        base_party_size = base_party_species.size
        evolved_party = old_data[:evolved_party].is_a?(Hash) ? old_data[:evolved_party].dup : {}
        extra_party = old_data[:extra_party].is_a?(Array) ? old_data[:extra_party].dup : []
        level_offsets = old_data[:level_offsets].is_a?(Hash) ? old_data[:level_offsets].dup : {}
        if !base_party_species.empty?
          evolved_party.delete_if { |idx, species| base_party_species[idx.to_i] == species }
        end
        total_slots = base_party_species.size + extra_party.size
        sanitized_level_offsets = {}
        level_offsets.each do |idx, value|
          slot = idx.to_i
          amount = value.to_i
          next if slot < 0 || amount <= 0
          next if total_slots > 0 && slot >= total_slots
          sanitized_level_offsets[slot] = amount
        end

        $PokemonGlobal.defeated_trainers[key] = {
          type:            trainer_type.to_sym,
          name:            trainer_name.to_s,
          version:         version,
          winner_pkmn:     winner_name,
          partner:         partner_name,
          last_rematch_at: old_data[:last_rematch_at],
          level_offset:    old_data[:level_offset] || 0,
          level_offsets:   sanitized_level_offsets,
          extra_party:     extra_party,
          base_party_species: base_party_species,
          evolved_party:   evolved_party
        }
        log("rematch: Dados SALVOS para #{trainer_type} #{trainer_name} (eid=#{event_id} mid=#{map_id})")
      end

      def register_rematch_victory(event_id, map_id)
        $PokemonGlobal.defeated_trainers ||= {}
        key = [map_id.to_i, event_id.to_i]
        if $PokemonGlobal.defeated_trainers[key]
          $PokemonGlobal.defeated_trainers[key][:last_rematch_at] = Time.now.to_i
          log("rematch: vitória em revanche registrada para evento #{event_id} - cooldown iniciado.")
        end
      end

      def get_pre_battle_context
        eid = $game_temp.anil_rematch_pre_battle_event_id.to_i rescue 0
        mid = $game_temp.anil_rematch_pre_battle_map_id.to_i rescue 0

        # Fallback para contexto persistente (offer_rematch), se game_temp estiver vazio
        if eid == 0
          ctx = $PokemonGlobal.anil_rematch_context rescue nil
          eid, mid = ctx if ctx.is_a?(Array) && ctx[0].to_i > 0
        end

        [eid.to_i, mid.to_i]
      end

      def clear_pre_battle_context
        $PokemonGlobal.anil_rematch_context = nil rescue nil
        $game_temp.anil_rematch_pre_battle_event_id = nil rescue nil
        $game_temp.anil_rematch_pre_battle_map_id = nil rescue nil
        $game_temp.anil_current_event_id = nil rescue nil
        $game_temp.anil_current_map_id = nil rescue nil
      end

      def can_show_post_battle_npc_message?(event_id, map_id)
        return false unless $scene.is_a?(Scene_Map) rescue false
        return false if $game_temp&.player_transferring
        return false if $game_temp&.transition_processing
        return false if $game_temp&.message_window_showing
        return false if (pbMapInterpreterRunning? rescue false)
        return false unless $game_map
        return false if $game_map.map_id.to_i != map_id.to_i
        event = $game_map.events[event_id.to_i] rescue nil
        return !event.nil?
      rescue
        false
      end

      def roll_for_evolution(event_id, map_id)
        $PokemonGlobal.defeated_trainers ||= {}
        key = [map_id.to_i, event_id.to_i]
        data = $PokemonGlobal.defeated_trainers[key]
        return unless data
        show_message = can_show_post_battle_npc_message?(event_id, map_id)
        
        # 1. Novo Pokémon (10% chance sempre, até chegar a 6 membros)
        if rand(100) < 10
          data[:extra_party] ||= []
          trainer_data = GameData::Trainer.get(data[:type], data[:name], data[:version]) rescue nil
          current_size = (trainer_data ? trainer_data.pokemon.size : 0) + data[:extra_party].size
          
          if current_size < 6
            new_species = find_themed_species(data)
            if new_species
              data[:extra_party] << new_species
              log("rematch: Treinador #{data[:name]} capturou um #{extra_party_entry_label(new_species)}!")
              pbMessage(get_msg_capture) if show_message
            end
          end
        end

        # 2. Dados por slot: nível e evolução rolam separadamente
        trainer_data ||= GameData::Trainer.get(data[:type], data[:name], data[:version]) rescue nil
        data[:evolved_party] ||= {} # [slot_index] => species_id
        base_party_species = migrate_legacy_party_state!(data, trainer_data)
        total_slots = base_party_species.size + (data[:extra_party] || []).size
        migrate_legacy_level_offsets!(data, total_slots)

        # Roda os dados para cada Pokémon do time (Original + Extras)
        (0...total_slots).each do |idx|
          current_species = nil
          if idx < base_party_species.size
            current_species = data[:evolved_party][idx] || base_party_species[idx]
          else
            extra_idx = idx - base_party_species.size
            extra_entry = normalize_extra_party_entry(data[:extra_party][extra_idx])
            extra_species_data = extra_party_entry_species_data(extra_entry)
            next if !extra_species_data || extra_species_data.form > 0
            current_species = extra_species_data.species
          end
          
          next unless current_species
          
          # Rola nível deste slot de forma independente.
          roll_lv = rand(100)
          added_lv = 0
          if roll_lv < 10 # 10% chance de +5
            added_lv = 5
          elsif roll_lv < 40 # 30% chance de +1 (10 a 39)
            added_lv = 1
          end
          if added_lv > 0
            data[:level_offsets][idx] = slot_level_offset(data, idx) + added_lv
            species_name = GameData::Species.get(current_species).name rescue current_species.to_s
            log("rematch: #{data[:name]} - #{species_name} no slot #{idx} ganhou +#{added_lv} níveis (Total slot: +#{data[:level_offsets][idx]})")
          end

          # A evolução continua com chance própria, usando o nível acumulado deste slot.
          next unless has_level_up_evolution?(current_species)
          next unless rand(100) < 10
          level = slot_level_offset(data, idx) + 20 # Nível base estimado + offset do slot
          temp_pkmn = Pokemon.new(current_species, level)
          new_species = temp_pkmn.check_evolution_on_level_up
          
          if new_species
            if idx < base_party_species.size
              data[:evolved_party][idx] = new_species
            else
              extra_idx = idx - base_party_species.size
              data[:extra_party][extra_idx] = new_species
            end
            log("rematch: #{data[:name]} - Pokémon no slot #{idx} evoluiu para #{new_species}!")
            previous_name = GameData::Species.get(current_species).name rescue current_species.to_s
            evolved_name = GameData::Species.get(new_species).name rescue new_species.to_s
            pbMessage(get_msg_evolution(previous_name, evolved_name)) if show_message
            break # Apenas uma evolução por batalha para não saturar
          end
        end
      end

      def find_themed_species(data)
        # Analisa o time original do treinador para descobrir o tema
        begin
          trainer_data = GameData::Trainer.get(data[:type], data[:name], data[:version])
          base_party_species = recorded_base_party_species(data, trainer_data)
          return nil if base_party_species.empty?
          
          party_types = []
          base_party_species.each do |species|
            spec = GameData::Species.get(species)
            party_types << spec.type1
            party_types << spec.type2
          end
          party_types = party_types.uniq.compact
          
          # Busca espécies que compartilham esses tipos e sorteia por estágio.
          candidates = []
          GameData::Species.all.each do |s|
            next if s.generation > 9
            next if !party_types.include?(s.type1) && !party_types.include?(s.type2)
            next if s.form > 0 && !(s.mega_stone || s.mega_move)
            weight = stage_weight_for_extra_party(s)
            next if weight <= 0
            candidates << [build_extra_party_entry(s), weight]
          end
          
          chosen = weighted_extra_party_candidate(candidates)
          return normalize_extra_party_entry(chosen) if chosen
        rescue
        end
        return normalize_extra_party_entry(GameData::Species.keys.sample) # Fallback aleatório
      end

      def apply_trainer_evolution(trainer, data)
        extras = data[:extra_party] || []
        base_party_species = migrate_legacy_party_state!(data)
        total_slots = base_party_species.size + extras.size
        migrate_legacy_level_offsets!(data, total_slots)
        evolved = data[:evolved_party] || {}

        # 1. Aplica evoluções salvas no time original
        trainer.party.each_with_index do |pkmn, i|
          if evolved[i]
            pkmn.species = evolved[i]
          end
          pkmn.level = [pkmn.level + slot_level_offset(data, i), 100].min
          pkmn.calc_stats
        end

        # 2. Adiciona extras (que já podem estar salvos como evoluídos em data[:extra_party])
        extras.each_with_index do |entry, extra_idx|
          next if trainer.party.size >= 6
          avg_lv = (trainer.party.map(&:level).sum / trainer.party.size).to_i rescue 50
          species_data = extra_party_entry_species_data(entry)
          next unless species_data
          slot_idx = base_party_species.size + extra_idx
          new_pkmn = Pokemon.new(species_data.species, [avg_lv + slot_level_offset(data, slot_idx), 100].min, trainer)
          new_pkmn.form_simple = species_data.form if species_data.form > 0 && new_pkmn.respond_to?(:form_simple=)
          trainer.party << new_pkmn
        end
      end

      # event_id/map_id sao opcionais so por compatibilidade: sem eles a fala sai
      # sem o nome do treinador, mas nada quebra se algum chamador antigo aparecer.
      def roll_for_reward(event_id = nil, map_id = nil)
        roll = rand(1000)
        item = nil
        if roll < 10 # 1% Muito Raro (Muito Raros, Tampinhas e Mega Stones)
          pool = VERY_RARE_ITEMS.dup
          pool += [:SCapsula, :ACapsula, :DCapsula, :AECapsula, :DECapsula, :VCapsula]
          if defined?(GameData) && defined?(GameData::Item)
            mega_stones = GameData::Item.keys.select { |k| GameData::Item.get(k).is_mega_stone? rescue false }
            pool += mega_stones unless mega_stones.empty?
          end
          item = pool.sample
        elsif roll < 15 # 0.5% Gift Box Laranja (10..14)
          item = :GIFT_ORANGE if (GameData::Item.exists?(:GIFT_ORANGE) rescue false)
        elsif roll < 35 # 2% Gift Box Azul (15..34)
          item = :GIFT_BLUE if (GameData::Item.exists?(:GIFT_BLUE) rescue false)
        elsif roll < 85 # 5% Gift Box Verde (35..84)
          item = :GIFT_GREEN if (GameData::Item.exists?(:GIFT_GREEN) rescue false)
        elsif roll < 95 # 1% Ingressos de Raid de Líderes (85..94)
          raid_tickets = [:BILHETEBROCK, :BILHETEMISTY, :BILHETESURGE, :BILHETEERIKA, :BILHETEBLAINE, :BILHETEURANO, :BILHETEGIOVANNI, :BILHETELARANJA]
          available_tickets = raid_tickets.select { |t| GameData::Item.exists?(t) rescue false }
          item = available_tickets.sample unless available_tickets.empty?
        elsif roll < 145 # 5% Raro (95..144)
          item = RARE_ITEMS.sample
        end
        
        if item && GameData::Item.exists?(item)
          # Fala do treinador antes de entregar o drop. Este caminho era mudo: ia
          # direto para o popup, e por isso as 126 frases [ITEM] nunca apareciam
          # (get_msg_item nao tinha um unico chamador no arquivo).
          # Caixa de Presente usa o repertorio por raridade; o resto usa [ITEM],
          # que foi escrito exatamente para a recompensa de pos-batalha.
          begin
            msg = item.to_s.start_with?("GIFT_") ? get_msg_gift(item) : get_msg_item
            if msg && !msg.to_s.empty?
              # So a fala, sem prefixo nem aspas.
              #
              # Antes saia `Nome: "texto"` — e quando o evento nao tinha nome
              # proprio, o prefixo era o literal "NPC", dando `NPC: "texto"` no
              # ecra. A caixa de mensagem do jogo ja deixa claro quem esta a
              # falar (esta-se de frente para ele), entao o prefixo so poluia.
              pbMessage(msg)
            end
          rescue => e
            log("rematch: Erro ao exibir fala do drop: #{e.message}") rescue nil
          end

          item_name = GameData::Item.get(item).name rescue item.to_s
          if $bag.can_add?(item)
            $bag.add(item, 1)
            pbMEPlay("Item get")
            if defined?(AnilLanRework) && AnilLanRework.respond_to?(:add_popup)
              AnilLanRework.add_popup(_INTL("Você recebeu {1} de presente!", item_name), 6.0, item)
            else
              pbMessage(_INTL("\\me[]Você recebeu \\c[1]{1}\\c[0] de presente!", item_name))
            end
          else
            if defined?(AnilLanRework) && AnilLanRework.respond_to?(:add_popup)
              AnilLanRework.add_popup(_INTL("Mochila cheia! Não foi possível receber {1}.", item_name), 6.0, item)
            else
              pbMessage(_INTL("Sua mochila está cheia! Não foi possível receber {1}.", item_name))
            end
          end
          log("rematch: Jogador recebeu item de drop: #{item}")
        end
      end

      # -----------------------------------------------------------------------
      # Sistema de Balões e Presentes
      # -----------------------------------------------------------------------
      def create_balloon_bitmap(type = :rematch)
        filename = "Overworld exclaim.png"
        filename = "emo.png" unless File.exist?("Graphics/Animations/" + filename)
        anim_bmp = RPG::Cache.animation(filename, 0) rescue nil
        
        bmp = Bitmap.new(192, 192)
        if type == :gift # Balão azul "?" (384, 0)
          bmp.blt(0, 0, anim_bmp, Rect.new(384, 0, 192, 192)) if anim_bmp
        else # Balão vermelho "!!" (0, 192)
          bmp.blt(0, 0, anim_bmp, Rect.new(0, 192, 192, 192)) if anim_bmp && anim_bmp.height >= 384
        end
        bmp
      end

      def update_rematch_balloons(spriteset, viewport)
        @rematch_sprites ||= {}
        @gift_sprites ||= {}
        @blink_timer ||= 0

        # Roda a cada 2 frames: o loop percorre todos os eventos do mapa e era
        # executado 60x/s. O balao segue o NPC com ate ~33ms de atraso, invisivel
        # a olho nu. O incremento de 2 preserva a cadencia real da piscada.
        cf = Graphics.frame_count rescue 0
        return if @anil_balloon_last_frame && (cf - @anil_balloon_last_frame) < 2
        @anil_balloon_last_frame = cf
        @blink_timer = (@blink_timer + 2) % 60
        visible = @blink_timer < 40

        # Caches por chamada (antes: Time.now e lookup de hash POR EVENTO)
        agora = Time.now.to_i
        defeated = $PokemonGlobal.defeated_trainers || {}
        map_id_atual = $game_map.map_id
        @anil_trainer_exists_cache ||= {}

        $game_map.events.each do |id, event|
          # 1. Lógica de Revanche (!!)
          is_rematch_npc = should_offer_rematch?(event)
          data = defeated[[map_id_atual, id]]
          in_cooldown = false
          if data && data[:last_rematch_at]
            in_cooldown = (agora - data[:last_rematch_at]) < COOLDOWN_TIME
          end

          # Só mostra se o treinador existir (proteção contra nome corrompido).
          # GameData::Trainer.exists? por frame era caro; o resultado so muda se
          # os dados do treinador mudarem, entao cacheia com TTL de 120 frames.
          exists = false
          if data
            ck = [map_id_atual, id]
            cached = @anil_trainer_exists_cache[ck]
            if cached && (cf - cached[1]) < 120
              exists = cached[0]
            else
              exists = (GameData::Trainer.exists?(data[:type].to_sym, data[:name].to_s, (data[:version] || 0).to_i) rescue false)
              @anil_trainer_exists_cache[ck] = [exists, cf]
            end
          end
          if is_rematch_npc && !in_cooldown && data && exists
            if !@rematch_sprites[id] || (@rematch_sprites[id].disposed? rescue true)
              @rematch_sprites[id] = Sprite.new(viewport) rescue nil
            end
            sprite = @rematch_sprites[id]
            if sprite && (!sprite.disposed? rescue false)
              if sprite.bitmap.nil? || (sprite.bitmap.disposed? rescue true)
                sprite.bitmap = create_balloon_bitmap(:rematch) rescue nil
                sprite.ox, sprite.oy, sprite.z = 96, 192, 200 rescue nil
              end
              sprite.x, sprite.y, sprite.visible = event.screen_x, event.screen_y + 10, visible rescue nil
            end
          else
            (@rematch_sprites.delete(id).dispose rescue nil) if @rematch_sprites[id]
          end

          # 2. Lógica de Presentes (?)
          if should_show_gift?(id, event)
            if !@gift_sprites[id] || (@gift_sprites[id].disposed? rescue true)
              @gift_sprites[id] = Sprite.new(viewport) rescue nil
            end
            sprite = @gift_sprites[id]
            if sprite && (!sprite.disposed? rescue false)
              if sprite.bitmap.nil? || (sprite.bitmap.disposed? rescue true)
                sprite.bitmap = create_balloon_bitmap(:gift) rescue nil
                sprite.ox, sprite.oy, sprite.z = 96, 192, 200 rescue nil
              end
              sprite.x, sprite.y, sprite.visible = event.screen_x, event.screen_y + 10, visible rescue nil
            end
          else
            (@gift_sprites.delete(id).dispose rescue nil) if @gift_sprites[id]
          end
        end
        # Limpeza de sprites de eventos que sumiram do mapa
        [@rematch_sprites, @gift_sprites].each do |collection|
          collection.delete_if do |id, sprite|
            if !$game_map.events[id]
              sprite.dispose rescue nil
              true
            else
              false
            end
          end
        end
      end

      def should_show_gift?(id, event)
        return false unless event
        return false if event.instance_variable_get(:@erased) == true
        return false if event.character_name.nil? || event.character_name.to_s.empty?
        return false if event.transparent rescue false
        $PokemonGlobal.gift_npcs ||= {}
        map_id = $game_map.map_id
        key = [map_id, id]
        
        # 1. Se este NPC já tem um presente salvo, mostra (Persistência)
        return true if $PokemonGlobal.gift_npcs[key]
        
        # 2. LÓGICA DE SORTEIO (Roda uma vez por entrada de mapa para o mapa todo)
        if ($PokemonGlobal.gift_map_rolled != map_id)
          # pending_keys so importa para decidir/logar o sorteio, que roda uma
          # vez por entrada. Calcula-lo fora deste bloco alocava um Array por
          # EVENTO por FRAME no loop dos baloes.
          pending_keys = $PokemonGlobal.gift_npcs.keys.select { |k| k[0] == map_id }
          has_pending = pending_keys.size > 0
          $PokemonGlobal.gift_map_rolled = map_id
          
          if has_pending
            log("gift: [MAPA #{map_id}] Sorteio pulado. Ainda existem #{pending_keys.size} presentes para coletar.")
          else
            npcs_candidatos = 0
            total_sorteados = 0
            log("gift: [MAPA #{map_id}] Iniciando sorteio de 1%...")
            
            candidatos_nomes = []
            $game_map.events.each do |eid, ev|
               next if !ev
               name_ev = ev.name.to_s rescue ""
               
               next if should_offer_rematch?(ev)
               next if name_ev.strip.empty?
               next if name_ev.include?("Vendedor")
               
               next if !ev.trigger || ev.trigger >= 3 
               next if !ev.list || ev.list.size <= 1
               
               # TRÍPLICE DEFESA contra objetos e portas
               
               # Defesa 1: Blacklist de Nomes
               blacklist = [
                 "Porta", "Door", "Transfer", "Teleport", "Entrance", "Saida", "Salida", "Exit", 
                 "Item", "PC", "Warp", "Condo", "Invisible", "Sensor", "Enfermera", "Enfermeira", 
                 "Joy", "Rival", "Foto", "Picture", "Camera", "Pokemon", "Wild", "Selvagem", 
                 "Flecha", "Lixeira", "Trash", "Pedra", "Rock", "Arvore", "Tree", "Placa", 
                 "Sign", "Estante", "Bookshelf", "Poster", "Quadro", "Balcao", "Counter", "Encounter"
               ]
next if blacklist.any? { |word| name_ev.downcase.include?(word.downcase) }

# Defesa 4: Filtro por Grafico (Characters vs Tiles/Invisiveis)
char_name = ev.character_name.to_s rescue ""
tile_id = (ev.tile_id rescue 0) || 0
next if tile_id > 0
next if char_name.empty? && tile_id == 0
object_charsets = ["object", "placa", "sign", "lixeira", "trash", "boulder", "rock", "door", "porta"]
next if object_charsets.any? { |obj| char_name.downcase.include?(obj) }

               # Defesa 2 e 3: Scanner de Lista de Comandos
               is_technical = false
               if ev.list
                 ev.list.each do |cmd|
                   # Defesa 2: Se tiver comando de Transferência (Portas/Transições)
                   if cmd.code == 201 # Transfer Player
                     is_technical = true
                     break
                   end
                   
                   # Defesa 3: Se falar palavras de objeto ou já der item
                   text_to_check = ""
                   if cmd.code == 101 # Show Text
                     text_to_check = cmd.parameters[0].to_s
                   elsif (cmd.code == 355 || cmd.code == 655) && cmd.parameters[0].to_s.include?("pbMessage")
                     text_to_check = cmd.parameters[0].to_s
                   end
                   
                   if !text_to_check.empty?
                     obj_keywords = ["lixo", "trash", "vazio", "empty", "nada", "nothing", "vasculhar", "interagir", "examinar"]
                     if obj_keywords.any? { |w| text_to_check.downcase.include?(w) }
                       is_technical = true
                       break
                     end
                   end
                   
                    if (cmd.code == 355 || cmd.code == 655)
                      script_text = cmd.parameters[0].to_s
                      # Exclui eventos que dão itens
                      if script_text.include?("pbItemBall") || script_text.include?("pbReceiveItem")
                        is_technical = true
                        break
                      end
                      # Exclui eventos de batalha de treinador (história/rival)
                      if script_text.include?("TrainerBattle.start") || script_text.include?("pbTrainerBattle") || script_text.include?("pbTrainerIntro")
                        is_technical = true
                        break
                      end
                    end
                 end
               end
               next if is_technical
               
               npcs_candidatos += 1
               candidatos_nomes << "#{eid}:#{name_ev}"
               
               if rand(100) < 1
                 gift_item = roll_gift_item
                 $PokemonGlobal.gift_npcs[[map_id, eid]] = gift_item
                 total_sorteados += 1
                 log("gift: -> NPC #{eid} (#{name_ev}) GANHOU: #{gift_item}!")
               end
            end
            
            log("gift: [MAPA #{map_id}] Candidatos válidos encontrados: #{candidatos_nomes.join(', ')}")
            
            if total_sorteados > 0
              log("gift: [MAPA #{map_id}] Sorteio concluído! Ganhadores: #{total_sorteados}")
            else
              log("gift: [MAPA #{map_id}] Sorteio concluído. Nenhum dos #{npcs_candidatos} NPCs deu sorte.")
            end
          end
        end
        
        # 3. Sem presente sorteado para este NPC, a resposta e nao — direto.
        # Os filtros que ficavam aqui (should_offer_rematch de novo, varredura de
        # event.list atras de texto, blacklist de nomes) rodavam por evento POR
        # FRAME e terminavam sempre em `!!gift_npcs[key]`, que neste ponto e
        # sempre nil (o caso presente ja retornou true la em cima). Peso morto.
        false
      end

      def roll_gift_item
        roll = rand(100)
        return GIFT_LEGENDARY.sample if roll < 1
        return GIFT_RARE.sample if roll < 10
        return GIFT_UNCOMMON.sample if roll < 30
        GIFT_COMMON.sample
      end

      def has_gift?(id)
        $PokemonGlobal.gift_npcs ||= {}
        key = [$game_map.map_id, id]
        item = $PokemonGlobal.gift_npcs[key]
        return false unless item
        begin
          event = $game_map.events[id] rescue nil
          if event && event.list
            event.list.each do |cmd|
              if (cmd.code == 355 || cmd.code == 655)
                script_text = cmd.parameters[0].to_s
                if script_text.include?("TrainerBattle.start") || script_text.include?("pbTrainerBattle") || script_text.include?("pbTrainerIntro")
                  return false
                end
              end
            end
          end
        rescue
        end
        return true
      end

      def offer_gift(id)
        $PokemonGlobal.gift_npcs ||= {}
        key = [$game_map.map_id, id]
        item = $PokemonGlobal.gift_npcs[key]
        return false unless item
        
        # PROTEÇÃO: Não interceptar eventos que contenham batalhas de treinador
        # Isso evita que lutas de história (ex: rival no laboratório) sejam puladas
        begin
          event = $game_map.events[id] rescue nil
          if event && event.list
            event.list.each do |cmd|
              if (cmd.code == 355 || cmd.code == 655)
                script_text = cmd.parameters[0].to_s
                if script_text.include?("TrainerBattle.start") || script_text.include?("pbTrainerBattle") || script_text.include?("pbTrainerIntro")
                  log("gift: BLOQUEADO - NPC #{id} no mapa #{$game_map.map_id} contém batalha de treinador. Devolvendo gift ao pool.")
                  $PokemonGlobal.gift_npcs.delete(key)
                  return false
                end
              end
            end
          end
        rescue => e
          log("gift: Erro ao verificar evento #{id}: #{e.message}") rescue nil
        end
        
        log("gift: Jogador recebeu #{item} do NPC #{id} no mapa #{$game_map.map_id}")
        
        # Fala do NPC antes de dar o presente — so a fala, sem prefixo nem
        # aspas (ver o mesmo tratamento no drop de pos-batalha).
        begin
          msg = get_msg_gift(item) rescue "Fique com isto!"
          pbMessage(msg)
        rescue => e
          log("gift: Erro ao exibir fala do NPC: #{e.message}") rescue nil
        end
        
        item_name = GameData::Item.get(item).name rescue item.to_s
        if $bag.can_add?(item)
          $bag.add(item, 1)
          pbMEPlay("Item get")
          if defined?(AnilLanRework) && AnilLanRework.respond_to?(:add_popup)
            AnilLanRework.add_popup(_INTL("Você recebeu {1} de presente!", item_name), 6.0, item)
          else
            pbMessage(_INTL("\\me[]Você recebeu \\c[1]{1}\\c[0] de presente!", item_name))
          end
        else
          if defined?(AnilLanRework) && AnilLanRework.respond_to?(:add_popup)
            AnilLanRework.add_popup(_INTL("Mochila cheia! Não foi possível receber {1}.", item_name), 6.0, item)
          else
            pbMessage(_INTL("Sua mochila está cheia! Não foi possível receber {1}.", item_name))
          end
        end
        $PokemonGlobal.gift_npcs.delete(key)
        true
      end

      # -----------------------------------------------------------------------
      # Reset de Treinadores Legados
      # -----------------------------------------------------------------------
      def reset_all_legacy_trainers
        pbMessage(_INTL("Isso irá resetar todos os treinadores que você já venceu, mas que ainda não estão registrados no sistema de revanches."))
        return unless pbConfirmMessage(_INTL("Deseja continuar? O jogo pode travar por alguns segundos."))
        
        log("rematch: Iniciando reset de treinadores legados...")
        count = 0
        
        # Carrega informações de todos os mapas
        map_infos = pbLoadMapInfos rescue nil
        return unless map_infos
        
        map_infos.keys.sort.each_with_index do |map_id, idx|
          Graphics.update if idx % 20 == 0 # Evita freeze total
          
          # Carrega o mapa para inspecionar eventos
          map = load_data(sprintf("Data/Map%03d.rxdata", map_id)) rescue nil
          next unless map
          
          map.events.each do |id, event|
            # Verifica se está derrotado (Switch A)
            key = [map_id, id, "A"]
            next unless $game_self_switches[key]
            
            # Pula se já tem dados no novo sistema
            data_key = [map_id, id]
            next if $PokemonGlobal.defeated_trainers && $PokemonGlobal.defeated_trainers[data_key]
            
            # Analisa se é um treinador de verdade (contém comando de batalha)
            is_trainer = false
            event.pages.each do |page|
              next unless page.list
              page.list.each do |cmd|
                if [355, 655].include?(cmd.code) # Script
                  script = cmd.parameters[0].to_s
                  if script.include?("TrainerBattle.start") || 
                     script.include?("pbTrainerBattle") ||
                     script.include?("pbTrainerIntro")
                    is_trainer = true
                    break
                  end
                end
              end
              break if is_trainer
            end
            
            if is_trainer
              $game_self_switches[key] = false
              $game_self_switches[[map_id, id, "B"]] = false rescue nil
              count += 1
            end
          end
        end
        
        log("rematch: Reset concluído. #{count} treinadores liberados para registro.")
        pbMessage(_INTL("Reset concluído! {1} treinadores foram resetados.", count))
        pbMessage(_INTL("Agora, ao vencê-los novamente, eles ficarão registrados para revanches infinitas!"))
      end

      # -----------------------------------------------------------------------
      # Reset Automático de Mapa (chamado ao entrar em cada mapa)
      # -----------------------------------------------------------------------
      def auto_reset_current_map
        return unless $game_map && $game_map.events
        map_id = $game_map.map_id

        # Ignora ginásios — verifica o nome original (não traduzido) via map_info
        begin
          map_infos = pbLoadMapInfos rescue nil
          if map_infos && map_infos[map_id]
            raw_name = map_infos[map_id].name.to_s
            gym_keywords = ["Gimnasio", "Gym", "Leader", "Lider", "Líder", "Ginásio"]
            return if gym_keywords.any? { |kw| raw_name.include?(kw) }
          end
        rescue
        end

        count = 0
        $game_map.events.each do |id, event|
          key = [map_id, id, "A"]
          next unless $game_self_switches[key]

          # Pula se já está no novo sistema
          next if $PokemonGlobal.defeated_trainers && $PokemonGlobal.defeated_trainers[[map_id, id]]

          # Verifica em TODAS as páginas do evento (não só a ativa)
          is_trainer = false
          begin
            event.event.pages.each do |page|
              next unless page && page.list
              page.list.each do |cmd|
                next unless [355, 655].include?(cmd.code)
                script = cmd.parameters[0].to_s
                if script.include?("TrainerBattle.start") || script.include?("pbTrainerBattle") || script.include?("pbTrainerIntro")
                  is_trainer = true
                  break
                end
              end
              break if is_trainer
            end
          rescue
            nil
          end

          if is_trainer
            $game_self_switches[key] = false
            $game_self_switches[[map_id, id, "B"]] = false rescue nil
            count += 1
          end
        end
        log("rematch: Auto-reset mapa #{map_id}: #{count} treinadores liberados.") if count > 0
      end
    end
  end
end

class PokemonGlobalMetadata
  attr_accessor :defeated_trainers
  attr_accessor :anil_rematch_context
  attr_accessor :gift_npcs
  attr_accessor :gift_map_rolled
  attr_accessor :online_id
end
class Game_Temp
  attr_accessor :anil_rematch_pre_battle_event_id, :anil_rematch_pre_battle_map_id
  attr_accessor :anil_rematch_last_decision
  attr_accessor :anil_current_event_id, :anil_current_map_id
  attr_accessor :anil_rematch_pending_roll # [eid, mid, decision]
end

EventHandlers.add(:on_enter_map, :reset_gift_roll, proc { |_old_map_id|
  AnilLanRework.log("gift: Entrou no mapa #{$game_map.map_id}. Resetando trava de sorteio.") rescue nil
  $PokemonGlobal.gift_map_rolled = 0
})

EventHandlers.add(:on_start_battle, :rematch_save_context, proc {
  # Limpa contexto de revanche antigo para não contaminar batalhas normais
  $PokemonGlobal.anil_rematch_context = nil rescue nil

  # Ignora se for PvP
  if defined?(AnilLanRework::BattleSync)
    ctx = AnilLanRework::BattleSync.active_context rescue nil
    next if ctx && ctx.mode == :pvp
  end

  # Não sobrescreve se offer_rematch já gravou o contexto neste tick
  next if $game_temp.anil_rematch_pre_battle_event_id.to_i > 0

  # Usa o event_id rastreado no Game_Event#start (mais confiável que o interpreter)
  eid = ($game_temp.anil_current_event_id || 0).to_i
  mid = ($game_temp.anil_current_map_id || ($game_map&.map_id) || 0).to_i
  $game_temp.anil_rematch_pre_battle_event_id = eid
  $game_temp.anil_rematch_pre_battle_map_id   = mid
})

EventHandlers.add(:on_end_battle, :rematch_capture_winner, proc { |decision, canLose, battle|
  # Ignora se for PvP
  if defined?(AnilLanRework::BattleSync)
    ctx = AnilLanRework::BattleSync.active_context rescue nil
    next if ctx && ctx.mode == :pvp
  end

  # decision 1 = Vitória do jogador
  begin
    eid, mid = AnilLanRework::RematchSystem.get_pre_battle_context
    AnilLanRework.log("rematch end_battle: decidon=#{decision} eid=#{eid} mid=#{mid}") rescue nil
    
    # Salva a decisão para o overworld processar
    $game_temp.anil_rematch_last_decision = decision
    
    if decision == 1 && battle && battle.trainerBattle?
      trainer = battle.opponent[0]
      if trainer
        winner_pkmn = nil
        battle.battlers.each { |b| (winner_pkmn = b.name; break) if b && !b.opposes? && b.pokemon }
        winner_pkmn ||= $player.party[0].name rescue "Pokémon"
        partner_name = (ctx = AnilLanRework::BattleSync.active_context; ctx && ctx.mode == :coop ? ctx.peer.to_s : nil) rescue nil
        
        if eid > 0
          # 1. Salva os dados básicos do treinador e vencedor
          AnilLanRework::RematchSystem.store_defeated_trainer_data(trainer.trainer_type, trainer.name, trainer.version, eid, mid, winner_pkmn, partner_name, trainer.party)
          
          # 2. Registra a vitória e inicia o COOLDOWN
          AnilLanRework::RematchSystem.register_rematch_victory(eid, mid)
          AnilLanRework.log("rematch: vitória em revanche registrada para evento #{eid} - cooldown iniciado.")
          
          # 3. Agenda a recompensa e evolução para quando o mapa carregar (evita tela preta)
          $game_temp.anil_rematch_pending_roll = [eid, mid, decision]
        end
      end
    end
  rescue => e
    AnilLanRework.log("rematch end_battle error: #{e.message}") rescue nil
  ensure
    AnilLanRework::RematchSystem.clear_pre_battle_context
  end
})

# Hook para aplicar evolução em treinadores de rota carregados pelo Essentials
EventHandlers.add(:on_trainer_load, :rematch_evolve_route_trainers, proc { |trainer|
  ctx = $PokemonGlobal.anil_rematch_context rescue nil
  if ctx && ctx.is_a?(Array) && ctx.size >= 2
    eid, mid = ctx
    if mid == ($game_map.map_id rescue -1)
      key = [mid, eid]
      data = ($PokemonGlobal.defeated_trainers || {})[key]
      if data && data[:type] == trainer.trainer_type && data[:name] == trainer.name
        # Aplica a evolução ao objeto trainer que acabou de ser carregado
        AnilLanRework::RematchSystem.apply_trainer_evolution(trainer, data) rescue nil
        AnilLanRework.log("rematch: Evolução aplicada com sucesso para #{trainer.full_name} (Eid:#{eid})")
      end
    end
  end
})

class Game_Event
  attr_accessor :pending_gift
  
  alias anil_rematch_v452_orig_start start unless method_defined?(:anil_rematch_v452_orig_start)
  def start
    return if !@list
    # Rastreia qual evento está sendo executado ANTES da batalha começar
    if $game_temp && @id.to_i > 0
      $game_temp.anil_current_event_id = @id
      $game_temp.anil_current_map_id   = $game_map&.map_id || 0
    end
    if defined?(AnilLanRework::RematchSystem) && AnilLanRework::RematchSystem.has_gift?(@id)
      # Oferece o presente imediatamente. Se entregue com sucesso, não executa o evento original do NPC (fala normal).
      if AnilLanRework::RematchSystem.offer_gift(@id)
        return
      end
    end
    if AnilLanRework::RematchSystem.should_offer_rematch?(self)
      return if AnilLanRework::RematchSystem.offer_rematch(self)
    end
    anil_rematch_v452_orig_start
  end
end

class Spriteset_Map
  alias anil_rematch_orig_update update unless method_defined?(:anil_rematch_orig_update)
  def update
    anil_rematch_orig_update
    if defined?(AnilLanRework::RematchSystem) && AnilLanRework::RematchSystem.enabled?
      AnilLanRework::RematchSystem.update_rematch_balloons(self, @viewport1)
    end
    
    # Quando há um roll pendente, converte para contagem regressiva
    if $game_temp && $game_temp.anil_rematch_pending_roll
      @anil_pending_roll_data = $game_temp.anil_rematch_pending_roll
      @anil_pending_roll_timer = 60  # Espera 60 frames (~1 segundo) para o mapa aparecer
      $game_temp.anil_rematch_pending_roll = nil
    end
    
    # Contagem regressiva: só mostra mensagens quando o mapa estiver 100% visível
    if @anil_pending_roll_timer && @anil_pending_roll_timer > 0
      @anil_pending_roll_timer -= 1
    elsif @anil_pending_roll_data
      eid, mid, decision = @anil_pending_roll_data
      @anil_pending_roll_data = nil
      @anil_pending_roll_timer = nil
      if decision == 1
        AnilLanRework::RematchSystem.roll_for_reward(eid, mid) rescue nil
        AnilLanRework::RematchSystem.roll_for_evolution(eid, mid) rescue nil
      end
    end
  end

  alias anil_rematch_orig_dispose dispose unless method_defined?(:anil_rematch_orig_dispose)
  def dispose
    anil_rematch_orig_dispose
    [@rematch_sprites, @gift_sprites].each do |collection|
      if collection
        collection.each { |id, sprite| sprite.dispose rescue nil }
        collection.clear
      end
    end
  end
end

EventHandlers.add(:on_enter_map, :rematch_auto_reset, proc { |_old_map_id|
  AnilLanRework::RematchSystem.auto_reset_current_map rescue nil
})

class Interpreter
  alias anil_rematch_orig_command_end command_end unless method_defined?(:anil_rematch_orig_command_end)
  def command_end
    if @event_id > 0 && $game_map && $game_map.events[@event_id]
      event = $game_map.events[@event_id]
      if event.respond_to?(:pending_gift) && event.pending_gift
        event.pending_gift = false
        AnilLanRework::RematchSystem.offer_gift(event.id) rescue nil
      end
    end
    anil_rematch_orig_command_end
  end
end

AnilLanRework.log("RematchSystem v4.5.3 (Auto-Reset & Fixes) ATIVO")
