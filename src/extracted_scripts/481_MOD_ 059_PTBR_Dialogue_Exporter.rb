#===============================================================================
# * PT-BR Dialogue Exporter Module (F7 Option)
#===============================================================================
module DialogueExporter
  module_function

  def get_translation(section_id, key, map_id = nil)
    if section_id == 0
      # Context ID for event texts in PTBR_TEXT is "0_#{map_id}"
      return PTBR_TEXT.translate(key, "0_#{map_id}")
    elsif section_id == 1 # SPECIES_NAMES
      # Check if PTBR_TEXT already has a translation for it
      special = PTBR_TEXT.translate_special_message(section_id, key, key) rescue nil
      return special if special && special != key && !special.to_s.empty?
      
      trans = PTBR_TEXT.translate(key, section_id)
      return trans if trans && trans != key && !trans.to_s.empty?
      
      # If no translation, translate Spanish Paradox/custom names to Portuguese
      spanish_to_portuguese = {
        "Código Cero" => "Tipo: Nulo",
        "Colmilargo" => "Presa Grande",
        "Colagrito" => "Cauda Gritante",
        "Furioseta" => "Capuz Bruto",
        "Melenaleteo" => "Juba Flutuante",
        "Reptalada" => "Asa Rastejante",
        "Pelarena" => "Choque de Areia",
        "Ferrodada" => "Rastro de Ferro",
        "Ferrosaco" => "Pacote de Ferro",
        "Ferropalmas" => "Mãos de Ferro",
        "Ferrocuello" => "Pescoço de Ferro",
        "Ferropolilla" => "Mariposa de Ferro",
        "Ferropúas" => "Espinhos de Ferro",
        "Bramaluna" => "Lua Rugidora",
        "Ferropaladín" => "Valente de Ferro",
        "Ondulagua" => "Ondas do Despertar",
        "Ferroverdor" => "Folhas de Ferro",
        "Flamariete" => "Fogo Perfurante",
        "Electrofuria" => "Raio Furioso",
        "Ferromole" => "Rocha de Ferro",
        "Ferrotesta" => "Coroa de Ferro"
      }
      return spanish_to_portuguese[key] if spanish_to_portuguese.key?(key)
      return key
    else
      # Check for special category translations (like moves or abilities)
      special = PTBR_TEXT.translate_special_message(section_id, key, key) rescue nil
      return special if special && !special.to_s.empty?
      
      # Fallback to general translation with section context
      return PTBR_TEXT.translate(key, section_id)
    end
  end

  def export_all_dialogues
    # 1. Ask for mode of export
    commands = [
      _INTL("Apenas Sem Tradução (Fugitivos)"),
      _INTL("Todos os Textos (Completo)"),
      _INTL("Cancelar")
    ]
    choice = pbMessage(_INTL("Como deseja exportar os textos do jogo?"), commands, commands.length)
    return if choice == 2 # Cancel

    only_untranslated = (choice == 0)

    # 2. Setup progress message window
    msg_window = pbCreateMessageWindow rescue nil
    if msg_window
      pbMessageDisplay(msg_window, "\\ts[]" + _INTL("Carregando textos e preparando exportação... Por favor, aguarde.") + "\\wtnp[0]")
    end

    # 3. Create destination directory if it doesn't exist
    export_dir = "Traduções/Anil"
    Dir.mkdir("Traduções") unless Dir.exist?("Traduções")
    Dir.mkdir(export_dir) unless Dir.exist?(export_dir)
    export_filepath = File.join(export_dir, "messages_game_extracted.txt")

    begin
      # 4. Load original Spanish messages
      MessageTypes.load_default_messages
      messages_obj = MessageTypes.class_variable_get(:@@messages)
      default_game_msgs = messages_obj.default_game_messages

      if !default_game_msgs || default_game_msgs.length == 0
        if msg_window
          pbMessageDisplay(msg_window, _INTL("Erro: messages_game.dat original não pôde ser carregado!"))
        end
        return
      end

      # 5. Open output file and write BOM
      File.open(export_filepath, "wb") do |f|
        # Write UTF-8 BOM
        f.write("\xEF\xBB\xBF")

        line_count = 0
        total_sections = default_game_msgs.length

        total_sections.times do |section_id|
          # Refresh screen periodically and show progress
          if msg_window
            pbMessageDisplay(msg_window, "\\ts[]" + _INTL("Processando seção {1}/{2}...", section_id + 1, total_sections) + "\\wtnp[0]")
          else
            Graphics.update rescue nil
          end

          original_msgs = default_game_msgs[section_id]
          next if !original_msgs

          # Get section name constant (e.g. EVENT_TEXTS, SPECIES_NAMES, etc.)
          section_name = getConstantName(MessageTypes, section_id, false) rescue nil
          section_name ||= "SECTION_#{section_id}"

          entries_to_write = []

          if section_id == 0 # EVENT_TEXTS
            # original_msgs is an Array where index is map_id, and original_msgs[map_id] is a Hash
            original_msgs.each_with_index do |map_msgs, map_id|
              next if !map_msgs || map_msgs.length == 0

              map_msgs.each_key do |key|
                next if key.to_s.empty?

                # Check if it already has a translation
                if only_untranslated
                  has_trans = false
                  special = PTBR_TEXT.translate_special_message(0, key, key) rescue nil
                  if special && special != key
                    has_trans = true
                  end
                  if !has_trans
                    has_trans = !PTBR_TEXT.lookup_translation(key, "0_#{map_id}").nil?
                  end
                  next if has_trans
                end

                spanish_text = PTBR_TEXT.encode_text_field(key)
                portuguese_text = PTBR_TEXT.encode_text_field(get_translation(0, key, map_id))

                entries_to_write << "MAP_#{map_id} ||| #{spanish_text} ||| #{portuguese_text}"
              end
            end
          else # Standard sections (Array or Hash)
            case original_msgs
            when Array
              original_msgs.each_with_index do |item, idx|
                next if item.to_s.empty?

                if section_id == 1 # SPECIES_NAMES
                  next unless ["Código Cero", "Colmilargo", "Colagrito", "Furioseta", "Melenaleteo", "Reptalada", "Pelarena", "Ferrodada", "Ferrosaco", "Ferropalmas", "Ferrocuello", "Ferropolilla", "Ferropúas", "Bramaluna", "Ferropaladín", "Ondulagua", "Ferroverdor", "Flamariete", "Electrofuria", "Ferromole", "Ferrotesta"].include?(item)
                end

                if only_untranslated
                  has_trans = false
                  special = PTBR_TEXT.translate_special_message(section_id, item, item) rescue nil
                  if special && special != item
                    has_trans = true
                  end
                  if !has_trans
                    has_trans = !PTBR_TEXT.lookup_translation(item, section_id).nil?
                  end
                  next if has_trans
                end

                spanish_text = PTBR_TEXT.encode_text_field(item)
                portuguese_text = PTBR_TEXT.encode_text_field(get_translation(section_id, item))

                entries_to_write << "#{spanish_text} ||| #{portuguese_text}"
              end
            when Hash
              original_msgs.each_key do |key|
                next if key.to_s.empty?

                if section_id == 1 # SPECIES_NAMES
                  next unless ["Código Cero", "Colmilargo", "Colagrito", "Furioseta", "Melenaleteo", "Reptalada", "Pelarena", "Ferrodada", "Ferrosaco", "Ferropalmas", "Ferrocuello", "Ferropolilla", "Ferropúas", "Bramaluna", "Ferropaladín", "Ondulagua", "Ferroverdor", "Flamariete", "Electrofuria", "Ferromole", "Ferrotesta"].include?(key)
                end

                if only_untranslated
                  has_trans = false
                  special = PTBR_TEXT.translate_special_message(section_id, key, key) rescue nil
                  if special && special != key
                    has_trans = true
                  end
                  if !has_trans
                    has_trans = !PTBR_TEXT.lookup_translation(key, section_id).nil?
                  end
                  next if has_trans
                end

                spanish_text = PTBR_TEXT.encode_text_field(key)
                portuguese_text = PTBR_TEXT.encode_text_field(get_translation(section_id, key))

                entries_to_write << "#{spanish_text} ||| #{portuguese_text}"
              end
            end
          end

          # Write header and entries if there's anything to write
          if entries_to_write.length > 0
            f.write("=== SECTION: #{section_name} (ID: #{section_id}) ===\r\n")
            entries_to_write.each do |entry|
              f.write("#{entry}\r\n")
              line_count += 1
              if line_count % 200 == 0
                Graphics.update rescue nil
              end
            end
          end
        end

        # 6. Show success message
        if msg_window
          msg_window.textspeed = MessageConfig.pbSettingToTextSpeed($PokemonSystem.textspeed) rescue -1
          pbMessageDisplay(msg_window, _INTL("Exportação concluída com sucesso!"))
          pbMessageDisplay(msg_window, _INTL("Total de {1} textos exportados.", line_count))
          pbMessageDisplay(msg_window, _INTL("Arquivo gerado em: Traduções/Anil/messages_game_extracted.txt"))
        end
      end
    rescue => e
      # Log error and show message
      AnilLanRework.log("DialogueExporter error: #{e.class} - #{e.message}") rescue nil
      if msg_window
        pbMessageDisplay(msg_window, _INTL("Erro durante a exportação: {1}", e.message))
      end
    ensure
      pbDisposeMessageWindow(msg_window) if msg_window
    end
  end
end
