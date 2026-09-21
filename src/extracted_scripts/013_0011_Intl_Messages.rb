PTBR_TXT_PATH = 'Data/messages_hashes/messages_hashes.txt'
PTBR_TXT_DAT  = 'Data/messages_hashes/messages_hashes.dat'
PTBR_FUGITIVE_PATH = 'Data/messages_hashes/textos_fugitivos.txt'
PTBR_ATTACKS_EN_PATH = 'Data/messages_hashes/ataques.txt'
PTBR_ATTACKS_BR_PATH = 'Data/messages_hashes/Ataques_BR.txt'
PTBR_ATTACKS_DAT     = 'Data/messages_hashes/attacks.dat'
PTBR_ABILITIES_EN_PATH = 'Data/messages_hashes/habilidades.txt'
PTBR_ABILITIES_BR_PATH = 'Data/messages_hashes/Habilidades_BR.txt'
PTBR_ABILITIES_DAT     = 'Data/messages_hashes/abilities.dat'
PTBR_NATURES_EN_PATH = 'Data/messages_hashes/naturezas.txt'
PTBR_NATURES_BR_PATH = 'Data/messages_hashes/Naturezas_BR.txt'
PTBR_NATURES_DAT     = 'Data/messages_hashes/natures.dat'
# === 📢 SISTEMA DE ATUALIZAÇÃO AUTOMÁTICA (APENAS AVISO - SEM DOWNLOAD) ===
module PTBR_UPDATER
  URL_VERSAO = "https://raw.githubusercontent.com/coemeteriu/PAPTBR/main/versao.txt"

  def self.obter_versao_local
    ["versao.txt", "versao.txt.txt"].each do |arquivo|
      if File.exist?(arquivo)
        begin
          conteudo = File.read(arquivo).strip
          return conteudo.to_f if conteudo.match?(/^[0-9]+(\.[0-9]+)?$/)
        rescue
        end
      end
    end
    return 1.0 
  end

  def self.checar_e_avisar
    texto = ""
    
    if defined?(pbDownloadToString)
      begin
        texto = pbDownloadToString(URL_VERSAO).to_s.strip
      rescue Exception
      end
    end

    if (!texto || texto.empty?)
      begin
        vbs_code = "Set ws = CreateObject(\"WScript.Shell\")\nws.Run \"cmd /c curl -sL #{URL_VERSAO} -o ptbr_fofoca.txt\", 0, True"
        File.open("ptbr_fofoca.vbs", "w") { |f| f.write(vbs_code) }
        system("wscript", "ptbr_fofoca.vbs")
        if File.exist?("ptbr_fofoca.txt")
          texto = File.read("ptbr_fofoca.txt").strip
          File.delete("ptbr_fofoca.txt") rescue nil
        end
        File.delete("ptbr_fofoca.vbs") rescue nil
      rescue Exception
      end
    end
    
    if texto && texto.match?(/^[0-9]+(\.[0-9]+)?$/)
      versao_online = texto.to_f
      v_local = obter_versao_local
      if versao_online > v_local
        aviso = "Uma nova versão da tradução (v#{versao_online}) está disponível!\nAcesse pokemonanilbr.netlify.app para baixar as novidades!"
        if defined?(pbMessage)
          pbMessage(aviso)
        elsif defined?(Kernel.pbMessage)
          Kernel.pbMessage(aviso)
        else
          print(aviso)
        end
      end
    end
  end
end

if defined?(Game_Player) && !Game_Player.method_defined?(:ptbr_orig_update_fofoq)
  class Game_Player
    alias ptbr_orig_update_fofoq update
    def update
      ptbr_orig_update_fofoq
      unless $ptbr_fofoca_feita
        if Graphics.frame_count % 60 == 0 && $game_map
          map_name = ""
          begin
            if $game_map.respond_to?(:name)
              map_name = $game_map.name.to_s.downcase
            elsif defined?(pbGetMapName)
              map_name = pbGetMapName($game_map.map_id).to_s.downcase
            end
          rescue
          end
          if (map_name.include?("centro") || map_name.include?("center")) && map_name.include?("pok")
            $ptbr_fofoca_feita = true
            PTBR_UPDATER.checar_e_avisar
          end
        end
      end
    end
  end
end
# ==========================================================

module PTBR_TEXT
  CATEGORY_TRANSLATION_FILES = {
    :moves     => { :pt => PTBR_ATTACKS_BR_PATH,    :en => PTBR_ATTACKS_EN_PATH },
    :abilities => { :pt => PTBR_ABILITIES_BR_PATH, :en => PTBR_ABILITIES_EN_PATH },
    :natures   => { :pt => PTBR_NATURES_BR_PATH,   :en => PTBR_NATURES_EN_PATH }
  }
  SPECIAL_MESSAGE_TYPE_TO_CATEGORY = {
    5  => :moves,
    10 => :abilities
  }

  @map = {}
  @clean_map = {}
  @context_map = {}
  @clean_context_map = {}
  @partials = []
  @loaded = false
  @cache = {}
  @missing_logged = {}
  @fugitives_loaded = false
  @category_maps = {}

  def self.apply_message_hooks
    return if @message_hooks_applied
    @message_hooks_applied = true

    ::Object.class_eval do
      # Hook pbMessage
      if (private_method_defined?(:pbMessage) || method_defined?(:pbMessage)) && !private_method_defined?(:"__ptbr_pbMessage_original") && !method_defined?(:"__ptbr_pbMessage_original")
        alias_method :"__ptbr_pbMessage_original", :pbMessage
        def pbMessage(message, commands = nil, *args, &block)
          translated_message = PTBR_TEXT.translate(message, nil)
          translated_commands = commands
          if commands.is_a?(Array)
            translated_commands = commands.map { |cmd| cmd.is_a?(String) ? PTBR_TEXT.translate(cmd, nil) : cmd }
          end
          __ptbr_pbMessage_original(translated_message, translated_commands, *args, &block)
        end
      end

      # Hook pbConfirmMessage
      if (private_method_defined?(:pbConfirmMessage) || method_defined?(:pbConfirmMessage)) && !private_method_defined?(:"__ptbr_pbConfirmMessage_original") && !method_defined?(:"__ptbr_pbConfirmMessage_original")
        alias_method :"__ptbr_pbConfirmMessage_original", :pbConfirmMessage
        def pbConfirmMessage(message, *args, &block)
          translated_message = PTBR_TEXT.translate(message, nil)
          __ptbr_pbConfirmMessage_original(translated_message, *args, &block)
        end
      end

      # Hook pbConfirmMessageSerious
      if (private_method_defined?(:pbConfirmMessageSerious) || method_defined?(:pbConfirmMessageSerious)) && !private_method_defined?(:"__ptbr_pbConfirmMessageSerious_original") && !method_defined?(:"__ptbr_pbConfirmMessageSerious_original")
        alias_method :"__ptbr_pbConfirmMessageSerious_original", :pbConfirmMessageSerious
        def pbConfirmMessageSerious(message, *args, &block)
          translated_message = PTBR_TEXT.translate(message, nil)
          __ptbr_pbConfirmMessageSerious_original(translated_message, *args, &block)
        end
      end

      # Hook pbShowCommands
      if (private_method_defined?(:pbShowCommands) || method_defined?(:pbShowCommands)) && !private_method_defined?(:"__ptbr_pbShowCommands_original") && !method_defined?(:"__ptbr_pbShowCommands_original")
        alias_method :"__ptbr_pbShowCommands_original", :pbShowCommands
        def pbShowCommands(msgwindow, commands = nil, *args, &block)
          first_arg = msgwindow
          if first_arg.is_a?(String)
            first_arg = PTBR_TEXT.translate(first_arg, nil)
          end
          translated_commands = commands
          if commands.is_a?(Array)
            translated_commands = commands.map { |cmd| cmd.is_a?(String) ? PTBR_TEXT.translate(cmd, nil) : cmd }
          end
          __ptbr_pbShowCommands_original(first_arg, translated_commands, *args, &block)
        end
      end

      # Hook pbMessageChooseNumber
      if (private_method_defined?(:pbMessageChooseNumber) || method_defined?(:pbMessageChooseNumber)) && !private_method_defined?(:"__ptbr_pbMessageChooseNumber_original") && !method_defined?(:"__ptbr_pbMessageChooseNumber_original")
        alias_method :"__ptbr_pbMessageChooseNumber_original", :pbMessageChooseNumber
        def pbMessageChooseNumber(message, *args, &block)
          translated_message = PTBR_TEXT.translate(message, nil)
          __ptbr_pbMessageChooseNumber_original(translated_message, *args, &block)
        end
      end

      # Hook pbMessageFreeText
      if (private_method_defined?(:pbMessageFreeText) || method_defined?(:pbMessageFreeText)) && !private_method_defined?(:"__ptbr_pbMessageFreeText_original") && !method_defined?(:"__ptbr_pbMessageFreeText_original")
        alias_method :"__ptbr_pbMessageFreeText_original", :pbMessageFreeText
        def pbMessageFreeText(message, *args, &block)
          translated_message = PTBR_TEXT.translate(message, nil)
          __ptbr_pbMessageFreeText_original(translated_message, *args, &block)
        end
      end

      # Hook pbMessageWithHelp
      if (private_method_defined?(:pbMessageWithHelp) || method_defined?(:pbMessageWithHelp)) && !private_method_defined?(:"__ptbr_pbMessageWithHelp_original") && !method_defined?(:"__ptbr_pbMessageWithHelp_original")
        alias_method :"__ptbr_pbMessageWithHelp_original", :pbMessageWithHelp
        def pbMessageWithHelp(message, help, commands = nil, *args, &block)
          translated_message = PTBR_TEXT.translate(message, nil)
          translated_help = help.is_a?(String) ? PTBR_TEXT.translate(help, nil) : help
          translated_commands = commands
          if commands.is_a?(Array)
            translated_commands = commands.map { |cmd| cmd.is_a?(String) ? PTBR_TEXT.translate(cmd, nil) : cmd }
          end
          __ptbr_pbMessageWithHelp_original(translated_message, translated_help, translated_commands, *args, &block)
        end
      end
    end
  end

  def self.decode_text_field(str)
    str.to_s.gsub('\n', "\n").gsub('\r', "\r").gsub("…", "...").force_encoding("UTF-8")
  end

  def self.encode_text_field(str)
    str.to_s.gsub("\r", '\r').gsub("\n", '\n')
  end

  def self.normalize_lookup_text(str)
    decode_text_field(str)
  end

  def self.clean_lookup_text(str)
    normalize_lookup_text(str).gsub(/[\n\r]+/, " ").gsub(/\s+/, " ").strip
  end

  def self.ensure_fugitive_index
    return if @fugitives_loaded
    @fugitives_loaded = true
    return unless File.exist?(PTBR_FUGITIVE_PATH)
    File.foreach(PTBR_FUGITIVE_PATH, encoding: "bom|utf-8") do |line|
      parts = line.chomp.split("|||", 3)
      next if parts.length < 2
      raw_ctx = parts[0].to_s.strip
      # Extract just the numeric context (without origin info) for dedup
      ctx = raw_ctx.sub(/\s*\[.*\]\s*$/, "").strip
      ctx = "0" if ctx.empty?
      text = clean_lookup_text(parts[1])
      @missing_logged[[ctx, text]] = true
    end
  rescue
  end

  def self.load_map
    return if @loaded
    @loaded = true

    # Tenta carregar binário .dat primeiro
    if File.exist?(PTBR_TXT_DAT)
      begin
        data = File.open(PTBR_TXT_DAT, "rb") { |f| Marshal.load(f) }
        @map = data[:map] || {}
        @clean_map = data[:clean_map] || {}
        @context_map = data[:context_map] || {}
        @clean_context_map = data[:clean_context_map] || {}
        @partials = data[:partials] || []
        return
      rescue
      end
    end

    # Fallback para .txt
    return unless File.exist?(PTBR_TXT_PATH)
    File.foreach(PTBR_TXT_PATH, encoding: "bom|utf-8") do |line|
      partes = line.chomp.split("|||", 3)
      if partes.length == 3
        if partes[0] == "SUB"
          @partials << [decode_text_field(partes[1]), decode_text_field(partes[2])]
        else
          ctx = partes[0].to_s.strip
          key = normalize_lookup_text(partes[1])
          val = decode_text_field(partes[2])
          @context_map[ctx] ||= {}
          @clean_context_map[ctx] ||= {}
          @context_map[ctx][key] = val
          @clean_context_map[ctx][clean_lookup_text(key)] = val
          @map[key] = val unless @map.key?(key)
          @clean_map[clean_lookup_text(key)] = val unless @clean_map.key?(clean_lookup_text(key))
        end
      end
    end
    # Auto-compila se estiver em Debug
    compile_all_to_dat if $DEBUG || defined?(RMXP)
  rescue
  end

  def self.clear_runtime_cache!
    @cache.clear
  end

  def self.translation_enabled_for?(category)
    return true if !$PokemonSystem
    case category
    when :moves
      return $PokemonSystem.translate_moves != 1
    when :abilities
      return $PokemonSystem.translate_abilities != 1
    when :natures
      return $PokemonSystem.translate_natures != 1
    end
    true
  end

  def self.translation_variant_for(category)
    return translation_enabled_for?(category) ? :pt : :en
  end

  def self.load_category_map(category)
    return @category_maps[category] if @category_maps[category]
    
    # Tenta carregar binário específico
    dat_path = nil
    case category
    when :moves then dat_path = PTBR_ATTACKS_DAT
    when :abilities then dat_path = PTBR_ABILITIES_DAT
    when :natures then dat_path = PTBR_NATURES_DAT
    end

    if dat_path && File.exist?(dat_path)
      begin
        @category_maps[category] = File.open(dat_path, "rb") { |f| Marshal.load(f) }
        return @category_maps[category]
      rescue
      end
    end

    files = CATEGORY_TRANSLATION_FILES[category]
    return nil if !files
    data = { :entries => {}, :index => {} }
    files.each do |variant, path|
      next if !File.exist?(path)
      File.foreach(path, encoding: "bom|utf-8") do |line|
        parts = line.chomp.split("|||", 3)
        next if parts.length < 3
        source = decode_text_field(parts[1]).to_s.strip
        target = decode_text_field(parts[2]).to_s.strip
        next if source.empty? || target.empty?
        source_key = clean_lookup_text(source)
        entry = (data[:entries][source_key] ||= { :source => source, :pt => nil, :en => nil })
        entry[variant] = target
      end
    end
    data[:entries].each_value do |entry|
      [entry[:source], entry[:pt], entry[:en]].compact.each do |candidate|
        data[:index][clean_lookup_text(candidate)] = entry
      end
    end
    @category_maps[category] = data
    return @category_maps[category]
  rescue
    @category_maps[category] = nil
    return nil
  end

  def self.compile_all_to_dat
    puts "Iniciando compilação total das traduções..."
    
    # 1. Mensagens Principais
    map = {}
    clean_map = {}
    context_map = {}
    clean_context_map = {}
    partials = []
    if File.exist?(PTBR_TXT_PATH)
      File.foreach(PTBR_TXT_PATH, encoding: "bom|utf-8") do |line|
        partes = line.chomp.split("|||", 3)
        if partes.length == 3
          if partes[0] == "SUB"
            partials << [decode_text_field(partes[1]), decode_text_field(partes[2])]
          else
            ctx = partes[0].to_s.strip
            key = normalize_lookup_text(partes[1])
            val = decode_text_field(partes[2])
            context_map[ctx] ||= {}
            clean_context_map[ctx] ||= {}
            context_map[ctx][key] = val
            clean_context_map[ctx][clean_lookup_text(key)] = val
            map[key] = val unless map.key?(key)
            clean_map[clean_lookup_text(key)] = val unless clean_map.key?(clean_lookup_text(key))
          end
        end
      end
      File.open(PTBR_TXT_DAT, "wb") { |f| Marshal.dump({map:map, clean_map:clean_map, context_map:context_map, clean_context_map:clean_context_map, partials:partials}, f) }
    end

    # 2. Categorias
    [:moves, :abilities, :natures].each do |cat|
      files = CATEGORY_TRANSLATION_FILES[cat]
      dat_path = (cat == :moves ? PTBR_ATTACKS_DAT : (cat == :abilities ? PTBR_ABILITIES_DAT : PTBR_NATURES_DAT))
      next if !files
      data = { :entries => {}, :index => {} }
      files.each do |variant, path|
        next if !File.exist?(path)
        File.foreach(path, encoding: "bom|utf-8") do |line|
          parts = line.chomp.split("|||", 3)
          next if parts.length < 3
          source = decode_text_field(parts[1]).to_s.strip
          target = decode_text_field(parts[2]).to_s.strip
          next if source.empty? || target.empty?
          source_key = clean_lookup_text(source)
          entry = (data[:entries][source_key] ||= { :source => source, :pt => nil, :en => nil })
          entry[variant] = target
        end
      end
      data[:entries].each_value do |entry|
        [entry[:source], entry[:pt], entry[:en]].compact.each do |candidate|
          data[:index][clean_lookup_text(candidate)] = entry
        end
      end
      File.open(dat_path, "wb") { |f| Marshal.dump(data, f) }
    end
    puts "Compilação concluída!"
  end

  def self.translate_named_entry(category, *candidates)
    data = load_category_map(category)
    return nil if !data
    entry = nil
    candidates.compact.each do |candidate|
      next if candidate.to_s.empty?
      entry = data[:index][clean_lookup_text(candidate)]
      break if entry
    end
    return nil if !entry
    variant = translation_variant_for(category)
    return entry[variant] || entry[:source]
  end

  def self.translate_special_message(type, original_key, current_text = nil)
    category = SPECIAL_MESSAGE_TYPE_TO_CATEGORY[type]
    return nil if !category
    return translate_named_entry(category, original_key, current_text)
  end

  def self.translate_nature_name(name)
    return translate_named_entry(:natures, name) || translate(name, nil)
  end

  def self.lookup_in_maps(raw_text, direct_map, clean_map)
    return nil unless direct_map && clean_map
    return direct_map[raw_text] if direct_map.key?(raw_text)
    stripped = raw_text.strip
    return raw_text.sub(stripped, direct_map[stripped]) if raw_text != stripped && direct_map.key?(stripped)
    clean_text = clean_lookup_text(raw_text)
    return clean_map[clean_text] if clean_map.key?(clean_text)
    nil
  end

  def self.lookup_translation(str, context_id = nil)
  load_map
  ctx = context_id.to_s.strip
  if !ctx.empty?
    translated = lookup_in_maps(str, @context_map[ctx], @clean_context_map[ctx])
    return translated if translated
  end
  lookup_in_maps(str, @map, @clean_map)
end




  def self.looks_like_spanish_text?(str)
    sample = str.to_s.dup
    sample.gsub!(/\\c\[[0-9]+\]/i, "")
    sample.gsub!(/\\[a-z]+\[[^\]]*\]/i, "")
    sample.gsub!(/\\[a-z]+/i, "")
    sample.gsub!(/<[^>]+>/, "")
    sample = sample.gsub(/[\n\r]+/, " ").gsub(/\s+/, " ").strip.downcase
    return false if sample.empty? || sample.length < 3
    return false unless sample.match?(/[[:alpha:]]/)
    return true if sample.match?(/[¡¿ñáéíóú]/i)
    return true if sample.match?(/\b(guardar|mochila|bolsa|objeto|objetos|ataque|defensa|velocidad|habilidad|nivel|equipo|pc|caja|retirar|depositar|usar|tirar|dar|quitar|coger|entrenador|batalla|salvaje|grupo|huevo|compatible|opciones|cancelar|elegir|quieres|recibir|enviar)\b/i)
    false
  end

  def self.record_fugitive_text(context_id, str)
    return if str.to_s.empty?
    ensure_fugitive_index
    ctx = context_id.to_s.strip
    ctx = "0" if ctx.empty?
    text_key = clean_lookup_text(str)
    cache_key = [ctx, text_key]
    return if @missing_logged[cache_key]
    @missing_logged[cache_key] = true

    # Extract call stack context to find original file/line
    origin = ""
    stack_trace = caller || []
    skip_patterns = /Intl_Messages|_Main|pbMessage|pbConfirmMessage|pbShowCommands|__ptbr_/i

    stack_trace.each do |frame|
      # Format 1: Standard Ruby paths (e.g. Scripts_Extraidos/0430_Incubadora.rb:45)
      if frame =~ /(?:Scripts_Extraidos|Scripts_Modular_Multiplayer)[\/\\]([^\/\\]+):([\d]+)/i
        filename = $1
        line_num = $2
        next if filename =~ skip_patterns
        origin = "[#{filename}:L#{line_num}]"
        break
      end
      # Format 2: RGSS compiled scripts (e.g. 011:0430_Incubadora:45:in `method')
      if frame =~ /^(\d+):([^:]+):(\d+)/
        section_num = $1
        script_name = $2
        line_num = $3
        next if script_name =~ skip_patterns
        origin = "[#{script_name}:L#{line_num}]"
        break
      end
      # Format 3: Standard .rb file paths
      if frame =~ /[\/\\]([^\/\\]+\.rb):(\d+)/i
        filename = $1
        line_num = $2
        next if filename =~ skip_patterns
        origin = "[#{filename}:L#{line_num}]"
        break
      end
    end

    origin = "[stack:#{stack_trace[0].to_s[0,80]}]" if origin.empty? && stack_trace[0]

    File.open(PTBR_FUGITIVE_PATH, "a:UTF-8") do |f|
      full_ctx = ctx
      full_ctx = "#{ctx} #{origin}" unless origin.empty?
      f.puts("#{full_ctx}|||#{encode_text_field(normalize_lookup_text(str))}|||")
    end
  rescue
  end

  def self.translate(str, context_id = nil)
    apply_message_hooks rescue nil
    return str if !str || !str.is_a?(String) || str.empty?
    cache_key = [context_id.to_s, str]
    return @cache[cache_key] if @cache.key?(cache_key)

    orig_str = str.dup

    system_words = [
      "info", "skills", "moves", "egg", "allstats", "memo",
      "red", "blue", "green", "yellow", "black", "white", "gray", "grey",
      "orange", "purple", "pink", "brown", "cyan", "magenta", "transparent",
      "bag", "party", "summary", "pokegear", "pokedex", "trainer", "save", "options"
    ]

    if str.match?(/^(Graphics|Pictures|Audio|Data|System|Fonts)\//i) ||
       str.match?(/\.(png|jpg|jpeg|gif|bmp|rxdata|dat|txt)$/i) ||
       system_words.include?(str.downcase.strip)
      @cache[cache_key] = str
      return str
    end

    res = str.dup
    
    res.gsub!("…", "...")

    translated = lookup_translation(res, context_id)
    res = translated if translated

    @partials.each do |es, pt|
      if res.include?(es)
        res.gsub!(es, pt)
      end
    end

    # === 💥 A GUILHOTINA DE GOLPES (DE VOLTA E MAIS FORTE) ===
    res.gsub!("{1} ha olvidado cómo utilizar {2} y...", "{1} esqueceu como usar {2} e...")
    res.gsub!(/\{1\}\s*ha olvidado c[oó]mo utilizar\s*\{2\}\s*y\.\.\./i, "{1} esqueceu como usar {2} e...")
    res.gsub!(/(.*?)\s*ha olvidado c[oó]mo utilizar\s*(.*?)\s*y\.\.\./i, '\1 esqueceu como usar \2 e...')
    res.gsub!(/ha olvidado c[oó]mo utilizar/i, "esqueceu como usar")
    res.gsub!(/\} y\.\.\./i, "} e...")
    res.gsub!(/1,\s*2\s*y\.\.\./i, "1, 2, e...")
    res.gsub!(/y\.\.\.\s*¡(.*?) aprendi[oó]/i, 'e... ¡\1 aprendeu')
    res.gsub!(/¡(.*?) aprendi[oó]/i, '¡\1 aprendeu')
    
    res.gsub!("¡{1} subió al Nivel {2}!", "{1} subiu para o nível {2}!")
    res.gsub!("¡{1} subió al Nível {2}!", "{1} subiu para o nível {2}!")
    res.gsub!(/¡(.*?) subi[oó] al N[ií]vel (.*?)!/i, '\1 subiu para o nível \2!')
    
    res.gsub!(/¡Has obtenido la /i, "Você obteve a ")
    res.gsub!(/¡Has obtenido el /i, "Você obteve o ")
    res.gsub!(/¡Has obtenido /i, "Você obteve ")

    # === ⚔️ DESCRIÇÕES DE ATAQUES FUGITIVOS ===
    res.gsub!(/Embiste con todo el cuerpo/i, "Investe com todo o corpo")
    res.gsub!(/Embiste con el cuerpo/i, "Investe com o corpo")
    # ========================================

    res.gsub!(/\bNivel\b/i, "Nível")
    
    res.gsub!(/Has(?:\\n|\\r|\s)+guardado/i, "Você guardou")
    res.gsub!(/en(?:\\n|\\r|\s)+el(?:\\n|\\r|\s)+bolsillo/i, "no bolso")
    res.gsub!(/el(?:\\n|\\r|\s)+bolsillo/i, "o bolso")
    res.gsub!(/\ben(?:\\n|\\r|\s)+o(?:\\n|\\r|\s)+bolso/i, "no bolso")

    res.gsub!(/Estadísticas Generales/i, "Estatísticas Gerais")
    res.gsub!(/Ratio de Captura/i, "Taxa de Captura")
    res.gsub!(/Prob\. de género/i, "Prob. de gênero")
    res.gsub!(/sin género/i, "sem gênero")
    res.gsub!(/\bHembra\b/i, "Fêmea")
    res.gsub!(/\bMacho\b/i, "Macho")
    res.gsub!(/Encuentros/i, "Encontros")
    res.gsub!(/Derrotados/i, "Derrotados")
    res.gsub!(/Capturados/i, "Capturados")
    res.gsub!(/Morfolog[ií]a/i, "Morfologia")
    res.gsub!(/H[aá]bit[aá]t/i, "Habitat")
    res.gsub!(/\bCrianza\b/i, "Cruzamento")
    res.gsub!(/Ramas evolutivas/i, "Ramificações evolutivas")
    res.gsub!(/Método de Evolución/i, "Método de Evolução")

    res.gsub!(/El color principal de la especie es el/i, "A cor principal da espécie é o")
    res.gsub!(/Tiene forma de/i, "Possui a forma de")
    res.gsub!(/Tiene forma/i, "Possui a forma")

    res.gsub!(/(Esta|Esa|Essa)\s+especie\s+(se puede encontrar|puede ser encontrada)/i, "Esta espécie pode ser encontrada")
    res.gsub!(/en zonas escarpadas de/i, "em zonas escarpadas de")
    res.gsub!(/en zonas escarpadas/i, "em zonas escarpadas")
    res.gsub!(/en escarpadas áreas/i, "em áreas escarpadas")
    res.gsub!(/en densas áreas/i, "em densas áreas")
    res.gsub!(/circulando por áreas/i, "circulando por áreas")
    res.gsub!(/cerca de áreas/i, "perto de áreas")
    res.gsub!(/en áreas de/i, "em áreas de")
    res.gsub!(/en lugares desconocidos/i, "em locais desconhecidos")

    res.gsub!(/\bPS M[aá]x\.?\b/i, "HP")
    res.gsub!(/\bAtaque\b/i, "Ataque")
    res.gsub!(/\bDefensa\b/i, "Defesa")
    res.gsub!(/\bVelocidad\b/i, "Velocidade")
    res.gsub!(/\bAt\.?\s*Esp\.?\b/i, "Atq. Esp")
    res.gsub!(/\bDef\.?\s*Esp\.?\b/i, "Def. Esp")

    res.gsub!(/Especie compatible con los grupos/i, "Espécie compatível com os grupos")
    res.gsub!(/Especie compatible con los grupos/i, "Espécie compatível com os grupos")
    res.gsub!(/Especie compatible con el grupo/i, "Espécie compatível com o grupo")
    res.gsub!(/Es compatible con los grupos/i, "É compatível com os grupos")
    res.gsub!(/Es compatible con el grupo/i, "É compatível com o grupo")
    res.gsub!(/está en el grupo/i, "está no grupo")
    res.gsub!(/compatible con todos excepto/i, "compatível com todos exceto")
    res.gsub!(/no tiene género y solo es compatible con el grupo/i, "não tem gênero e só é compatível com o grupo")
    res.gsub!(/y no puede criar/i, "e não pode cruzar")

    res.gsub!(/Si el juego te va MUY RÁPIDO o MUY LENTO/i, "Se o jogo estiver MUITO RÁPIDO o MUITO LENTO")
    res.gsub!(/ve a Opciones y cambia la opción/i, "vá em Opções e altere a configuração")

    begin
      ctx = res.dup
      ctx.gsub!(/\\c\[[0-9]+\]/i, "")
      ctx.gsub!(/\\[a-z]+\[[^\]]*\]/i, "")
      ctx.gsub!(/\\[a-z]+/i, "")
      ctx.gsub!(/<[^>]+>/, "")
      ctx = ctx.downcase

      if ctx.match?(/grupo|grupos|cruz|crian|huevo|egg|compatib|compat[ií]vel|género|genero/i)
        spacer = /(?:\s+|\\c\[[0-9]+\]|\\[a-z]+\[[^\]]*\]|\\[a-z]+|<[^>]+>)*/
        res.gsub!(/#{spacer}\by\b#{spacer}/i) do |m|
          left_codes  = m.sub(/(?i)\by\b.*\z/m, "")
          right_codes = m.sub(/\A.*(?i)\by\b/m, "")
          "#{left_codes} e #{right_codes}"
        end
      end
    rescue
    end

    res.gsub!(/Subir de nivel a/i, "Subir de nível de")
    res.gsub!(/Sube de nivel a/i, "Sobe de nível de")
    res.gsub!(/con gran felicidad/i, "com muita felicidad")
    res.gsub!(/durante el día/i, "durante o dia")
    res.gsub!(/durante la noche/i, "durante a noite")
    res.gsub!(/conociendo el movimiento/i, "conhecendo o movimiento")
    res.gsub!(/conociendo un movimiento de tipo/i, "conhecendo um ataque do tipo")
    res.gsub!(/equipado con/i, "equipado com")
    res.gsub!(/llevando/i, "segurando")

    {"rojo"=>"vermelho", "azul"=>"azul", "amarillo"=>"amarelo", "verde"=>"verde",
     "negro"=>"preto", "blanco"=>"branco", "marrón"=>"marrom", "rosa"=>"rosa",
     "gris"=>"cinza", "morado"=>"roxo"}.each do |es, pt|
      res.gsub!(/\b#{es}\b/i) do |matched|
        if matched == matched.upcase
          pt.upcase
        elsif matched[0] == matched[0].upcase
          pt.capitalize
        else
          pt
        end
      end
    end

    res.gsub!(/cabeza y cuerpo/i, "cabeça e corpo")
    res.gsub!(/cabeza y brazos/i, "cabeça e braços")
    res.gsub!(/cabeza y base/i, "cabeça e base")
    res.gsub!(/cuadrúpedo/i, "quadrúpede")
    res.gsub!(/alas/i, "asas")
    res.gsub!(/tentáculos/i, "tentáculos")
    res.gsub!(/insectoide/i, "insetóide")
    res.gsub!(/serpentino/i, "serpentino")
    res.gsub!(/aletas/i, "barbatanas")
    res.gsub!(/varios cuerpos/i, "vários corpos")

    record_fugitive_text(context_id, orig_str) if translated.nil? && looks_like_spanish_text?(orig_str)
    @cache[cache_key] = res
    return res
  end

  def self.t(str)
    translate(str, nil)
  end
end

if defined?(Window_Base) && !Window_Base.method_defined?(:ptbr_orig_draw_text)
  class Window_Base
    alias ptbr_orig_draw_text draw_text
    def draw_text(*args)
      t_idx = args[0].is_a?(Numeric) ? 4 : 1
      args[t_idx] = PTBR_TEXT.t(args[t_idx]) if args[t_idx].is_a?(String)
      ptbr_orig_draw_text(*args)
    end
  end
end

unless defined?($PTBR_HOOK_MAPNAMES)
  $PTBR_HOOK_MAPNAMES = true

  [
    :pbGetMapName,
    :pbGetMapNameFromId,
    :pbGetMapNameFromID,
    :pbGetBasicMapNameFromID,
    :pbMapName,
    :pbGetMapDisplayName
  ].each do |m|
    if defined?(Kernel) && Kernel.method_defined?(m)
      Kernel.module_eval do
        alias_method :"__ptbr_#{m}_original", m
        define_method(m) do |*a|
          r = send(:"__ptbr_#{m}_original", *a)
          r.is_a?(String) ? PTBR_TEXT.translate(r, nil) : r
        end
      end
    end
  end

  if defined?(Game_Map) && Game_Map.method_defined?(:name)
    Game_Map.class_eval do
      alias __ptbr_gamemap_name_original name
      def name
        r = __ptbr_gamemap_name_original
        r.is_a?(String) ? PTBR_TEXT.translate(r, nil) : r
      end
    end
  end

  if defined?(RPG) && defined?(RPG::MapInfo) && RPG::MapInfo.method_defined?(:name)
    RPG::MapInfo.class_eval do
      alias __ptbr_mapinfo_name_original name
      def name
        r = __ptbr_mapinfo_name_original
        r.is_a?(String) ? PTBR_TEXT.translate(r, nil) : r
      end
    end
  end
end

#===============================================================================
#
#===============================================================================
module Translator
  module_function

  def gather_script_and_event_texts
    Graphics.update
    begin
      t = System.uptime
      texts = []
      # Obtener textos de script desde Scripts.rxdata
      $RGSS_SCRIPTS.each do |script|
        if System.uptime - t >= 5
          t += 5
          Graphics.update
        end
        scr = Zlib::Inflate.inflate(script[2])
        find_translatable_text_from_RGSS_script(texts, scr)
      end
      # Si Scripts.rxdata solo tiene 1 sección, los scripts han sido extraídos. Obtén
      # textos de los archivos .rb en Data/Scripts
      if $RGSS_SCRIPTS.length == 1
        Dir.all("Data/Scripts").each do |script_file|
          if System.uptime - t >= 5
            t += 5
            Graphics.update
          end
          File.open(script_file, "rb") do |f|
            find_translatable_text_from_RGSS_script(texts, f.read)
          end
        end
      end
      # Get script texts from plugin script files
      if FileTest.exist?("Data/PluginScripts.rxdata")
        plugin_scripts = load_data("Data/PluginScripts.rxdata")
        plugin_scripts.each do |plugin|
          plugin[2].each do |script|
            if System.uptime - t >= 5
              t += 5
              Graphics.update
            end
            scr = Zlib::Inflate.inflate(script[1]).force_encoding(Encoding::UTF_8)
            find_translatable_text_from_RGSS_script(texts, scr)
          end
        end
      end
      MessageTypes.addMessagesAsHash(MessageTypes::SCRIPT_TEXTS, texts)
      # Find all text in common events and add them to messages
      commonevents = load_data("Data/CommonEvents.rxdata")
      items = []
      choices = []
      commonevents.compact.each do |event|
        if System.uptime - t >= 5
          t += 5
          Graphics.update
        end
        begin
          neednewline = false
          lastitem = ""
          event.list.size.times do |j|
            list = event.list[j]
            if neednewline && list.code != 401   # Continuation of 101 Show Text
              if lastitem != ""
                lastitem.gsub!(/([^\.\!\?])\s\s+/) { |m| $1 + " " }
                items.push(lastitem)
                lastitem = ""
              end
              neednewline = false
            end
            if list.code == 101   # Show Text
              lastitem += list.parameters[0].to_s
              neednewline = true
            elsif list.code == 102   # Show Choices
              list.parameters[0].length.times do |k|
                choices.push(list.parameters[0][k])
              end
              neednewline = false
            elsif list.code == 401   # Continuation of 101 Show Text
              lastitem += " " if lastitem != ""
              lastitem += list.parameters[0].to_s
              neednewline = true
            elsif list.code == 355 || list.code == 655   # Script or script continuation line
              find_translatable_text_from_event_script(items, list.parameters[0])
            elsif list.code == 111 && list.parameters[0] == 12   # Conditional Branch
              find_translatable_text_from_event_script(items, list.parameters[1])
            elsif list.code == 209   # Set Move Route
              route = list.parameters[1]
              route.list.size.times do |k|
                if route.list[k].code == PBMoveRoute::SCRIPT
                  find_translatable_text_from_event_script(items, route.list[k].parameters[0])
                end
              end
            end
          end
          if neednewline && lastitem != ""
            items.push(lastitem)
            lastitem = ""
          end
        end
      end
      if System.uptime - t >= 5
        t += 5
        Graphics.update
      end
      items |= []
      choices |= []
      items.concat(choices)
      MessageTypes.setMapMessagesAsHash(0, items)
      # Find all text in map events and add them to messages
      mapinfos = pbLoadMapInfos
      mapinfos.each_key do |id|
        if System.uptime - t >= 5
          t += 5
          Graphics.update
        end
        filename = sprintf("Data/Map%03d.rxdata", id)
        next if !pbRgssExists?(filename)
        map = load_data(filename)
        items = []
        choices = []
        map.events.each_value do |event|
          if System.uptime - t >= 5
            t += 5
            Graphics.update
          end
          begin
            event.pages.size.times do |i|
              neednewline = false
              lastitem = ""
              event.pages[i].list.size.times do |j|
                list = event.pages[i].list[j]
                if neednewline && list.code != 401   # Continuation of 101 Show Text
                  if lastitem != ""
                    lastitem.gsub!(/([^\.\!\?])\s\s+/) { |m| $1 + " " }
                    items.push(lastitem)
                    lastitem = ""
                  end
                  neednewline = false
                end
                if list.code == 101   # Show Text
                  lastitem += list.parameters[0].to_s
                  neednewline = true
                elsif list.code == 102   # Show Choices
                  list.parameters[0].length.times do |k|
                    choices.push(list.parameters[0][k])
                  end
                  neednewline = false
                elsif list.code == 401   # Continuation of 101 Show Text
                  lastitem += " " if lastitem != ""
                  lastitem += list.parameters[0].to_s
                  neednewline = true
                elsif list.code == 355 || list.code == 655   # Script or script continuation line
                  find_translatable_text_from_event_script(items, list.parameters[0])
                elsif list.code == 111 && list.parameters[0] == 12   # Conditional Branch
                  find_translatable_text_from_event_script(items, list.parameters[1])
                elsif list.code == 209   # Set Move Route
                  route = list.parameters[1]
                  route.list.size.times do |k|
                    if route.list[k].code == PBMoveRoute::SCRIPT
                      find_translatable_text_from_event_script(items, route.list[k].parameters[0])
                    end
                  end
                end
              end
              if neednewline && lastitem != ""
                items.push(lastitem)
                lastitem = ""
              end
            end
          end
        end
        if System.uptime - t >= 5
          t += 5
          Graphics.update
        end
        items |= []
        choices |= []
        items.concat(choices)
        MessageTypes.setMapMessagesAsHash(id, items) if items.length > 0
        if System.uptime - t >= 5
          t += 5
          Graphics.update
        end
      end
    rescue Hangup
    end
    Graphics.update
  end

  def find_translatable_text_from_RGSS_script(items, script)
    script.force_encoding(Encoding::UTF_8)
    script.scan(/(?:_INTL|_ISPRINTF)\s*\(\s*\"((?:[^\\\"]*\\\"?)*[^\"]*)\"/) do |s|
      string = s[0]
      string.gsub!(/\\r/, "\r")
      string.gsub!(/\\n/, "\n")
      string.gsub!(/\\1/, "\1")
      string.gsub!(/\\\"/, "\"")
      string.gsub!(/\\\\/, "\\")
      items.push(string)
    end
  end

  def find_translatable_text_from_event_script(items, script)
    script.force_encoding(Encoding::UTF_8)
    script.scan(/(?:_I)\s*\(\s*\"((?:[^\\\"]*\\\"?)*[^\"]*)\"/) do |s|
      string = s[0]
      string.gsub!(/\\\"/, "\"")
      string.gsub!(/\\\\/, "\\")
      items.push(string)
    end
  end

  def normalize_value(value)
    if value[/[\r\n\t\x01]|^[\[\]]/]
      ret = value.dup
      ret.gsub!(/\r/, "<<r>>")
      ret.gsub!(/\n/, "<<n>>")
      ret.gsub!(/\t/, "<<t>>")
      ret.gsub!(/\[/, "<<[>>")
      ret.gsub!(/\]/, "<<]>>")
      ret.gsub!(/\x01/, "<<1>>")
      return ret
    end
    return value
  end

  def denormalize_value(value)
    if value[/<<[rnt1\[\]]>>/]
      ret = value.dup
      ret.gsub!(/<<1>>/, "\1")
      ret.gsub!(/<<r>>/, "\r")
      ret.gsub!(/<<n>>/, "\n")
      ret.gsub!(/<<\[>>/, "[")
      ret.gsub!(/<<\]>>/, "]")
      ret.gsub!(/<<t>>/, "\t")
      return ret
    end
    return value
  end

  #-----------------------------------------------------------------------------

  def extract_text(language_name = "default", core_text = false, separate_map_files = false)
    dir_name = sprintf("Text_%s_%s", language_name, (core_text) ? "core" : "game")
    msg_window = pbCreateMessageWindow
    # Obtener texto para extracción
    orig_messages = Translation.new(language_name)
    if core_text
      language_messages = orig_messages.core_messages
      default_messages = orig_messages.default_core_messages
      if !default_messages || default_messages.length == 0
        pbMessageDisplay(msg_window, _INTL("No se ha encontrado el archivo principal predeterminado \"messages_core.dat\"."))
        pbDisposeMessageWindow(msg_window)
        return
      end
    else
      language_messages = orig_messages.game_messages
      default_messages = orig_messages.default_game_messages
      if !default_messages || default_messages.length == 0
        pbMessageDisplay(msg_window, _INTL("No se ha encontrado el archivo predeterminado de mensajes del juego \"messages_game.dat\"."))
        pbDisposeMessageWindow(msg_window)
        return
      end
    end
    # Create folder for extracted text files, or delete existing text files from
    # existing destination folder
    if Dir.safe?(dir_name)
      has_files = false
      Dir.all(dir_name).each do |f|
        has_files = true
        break
      end
      if has_files && !pbConfirmMessageSerious(_INTL("¿Reemplazar todos los archivos de texto en la carpeta '{1}'?", dir_name))
        pbDisposeMessageWindow(msg_window)
        return
      end
      Dir.all(dir_name).each { |f| File.delete(f) }
    else
      Dir.create(dir_name)
    end
    # Cree una función lambda que ayude a escribir archivos de texto
    write_header = lambda do |f, with_line|
      f.write(0xEF.chr)
      f.write(0xBB.chr)
      f.write(0xBF.chr)
      f.write("# Para traducir este texto a un idioma en concreto, por favor" + "\r\n")
      f.write("# traduce las segundas líneas de este archivo." + "\r\n")
      f.write("\#-------------------------------\r\n") if with_line
    end
    # Extraer el texto
    pbMessageDisplay(msg_window, "\\ts[]" + _INTL("Extrayendo texto, por favor espera.") + "\\wtnp[0]")
    # Obtenga todos los ID de sección para recorrerlos
    max_section_id = default_messages.length
    max_section_id = language_messages.length if language_messages && language_messages.length > max_section_id
    max_section_id.times do |i|
      section_name = getConstantName(MessageTypes, i, false)
      next if !section_name
      if i == MessageTypes::EVENT_TEXTS
        if separate_map_files
          map_infos = pbLoadMapInfos
          default_messages[i].each_with_index do |map_msgs, map_id|
            next if !map_msgs || map_msgs.length == 0
            filename = sprintf("Map%03d", map_id)
            filename += " " + map_infos[map_id].name if map_infos[map_id]
            File.open(dir_name + "/" + filename + ".txt", "wb") do |f|
              write_header.call(f, true)
              translated_msgs = language_messages[i][map_id] if language_messages && language_messages[i]
              write_section_texts_to_file(f, sprintf("Map%03d", map_id), translated_msgs, map_msgs)
            end
          end
        else
          next if !default_messages[i] || default_messages[i].length == 0
          no_difference = true
          default_messages[i].each do |map_msgs|
            no_difference = false if map_msgs && map_msgs.length > 0
            break if !map_msgs
          end
          next if no_difference
          File.open(dir_name + "/" + section_name + ".txt", "wb") do |f|
            write_header.call(f, false)
            default_messages[i].each_with_index do |map_msgs, map_id|
              next if !map_msgs || map_msgs.length == 0
              f.write("\#-------------------------------\r\n")
              translated_msgs = (language_messages && language_messages[i]) ? language_messages[i][map_id] : nil
              write_section_texts_to_file(f, sprintf("Map%03d", map_id), translated_msgs, map_msgs)
            end
          end
        end
      else   # secciones de MessageTypes
        next if !default_messages[i] || default_messages[i].length == 0
        File.open(dir_name + "/" + section_name + ".txt", "wb") do |f|
          write_header.call(f, true)
          translated_msgs = (language_messages) ? language_messages[i] : nil
          write_section_texts_to_file(f, section_name, translated_msgs, default_messages[i])
        end
      end
    end
    msg_window.textspeed = MessageConfig.pbSettingToTextSpeed($PokemonSystem.textspeed)
    if core_text
      pbMessageDisplay(msg_window, _INTL("Todo el texto principal se extrajo a archivos en la carpeta \"{1}\".", dir_name) + "\1")
    else
      pbMessageDisplay(msg_window, _INTL("Todo el texto del juego se extrajo a archivos en la carpeta \"{1}\".", dir_name) + "\1")
    end
    pbMessageDisplay(msg_window, _INTL("Para localizar este texto, traduzca cada segunda línea de esos archivos.") + "\1")
    pbMessageDisplay(msg_window, _INTL("Después de traducir, elige \"Compilar texto traducido\" en el menú Debug."))
    pbDisposeMessageWindow(msg_window)
  end

  def write_section_texts_to_file(f, section_name, language_msgs, original_msgs = nil)
    return if !original_msgs
    case original_msgs
    when Array
      f.write("[#{section_name}]\r\n")
      original_msgs.length.times do |j|
        next if nil_or_empty?(original_msgs[j])
        f.write("#{j}\r\n")
        f.write(normalize_value(original_msgs[j]) + "\r\n")
        text = (language_msgs && language_msgs[j]) ? language_msgs[j] : original_msgs[j]
        f.write(normalize_value(text) + "\r\n")
      end
    when Hash
      f.write("[#{section_name}]\r\n")
      keys = original_msgs.keys
      keys.each do |key|
        next if nil_or_empty?(original_msgs[key])
        f.write(normalize_value(key) + "\r\n")
        text = (language_msgs && language_msgs[key]) ? language_msgs[key] : original_msgs[key]
        f.write(normalize_value(text) + "\r\n")
      end
    end
  end

  #-----------------------------------------------------------------------------

  def compile_text(dir_name, dat_filename)
    msg_window = pbCreateMessageWindow
    pbMessageDisplay(msg_window, "\\ts[]" + _INTL("Compilando texto, por favor espera.") + "\\wtnp[0]")
    outfile = File.open("Data/messages_" + dat_filename + ".dat", "wb")
    all_text = []
    begin
      text_files = Dir.get("Text_" + dir_name, "*.txt")
      text_files.each { |file| compile_text_from_file(file, all_text) }
      Marshal.dump(all_text, outfile)
    rescue
      raise
    ensure
      outfile.close
    end
    msg_window.textspeed = MessageConfig.pbSettingToTextSpeed($PokemonSystem.textspeed)
    pbMessageDisplay(msg_window,
       _INTL("Los archivos de texto en la carpeta \"Text_{1}\" se han compilado con éxito en el archivo \"Data/messages_{2}.dat\".", dir_name, dat_filename))
    pbMessageDisplay(msg_window, _INTL("Es posible que tengas que cerrar el juego para ver los cambios en los mensajes."))
    pbDisposeMessageWindow(msg_window)
  end

  def compile_text_from_file(text_file, all_text)
    begin
      file = File.open(text_file, "rb")
    rescue
      raise _INTL("No se puede encontrar o abrir '{1}'.", text_file)
    end
    begin
      Compiler.pbEachSection(file) do |contents, section_name|
        next if contents.length == 0
        # Obtener el número de sección y si la sección contiene el texto del evento de un mapa
        section_id = -1
        is_map = false
        if section_name.to_i != 0   # Section name is a number
          section_id = section_name.to_i
        elsif hasConst?(MessageTypes, section_name)   # Section name is a constant from MessageTypes
          section_id = getConst(MessageTypes, section_name)
        elsif section_name[/^Map(\d+)$/i]   # Section name is a map number (event text)
          is_map = true
          section_id = $~[1].to_i
        end
        raise _INTL("Nombre de sección {1} no válido", section_name) if section_id < 0
        # Decidir si la sección contiene texto almacenado en una lista ordenada
        # (un array) o un hash ordenado.
        item_length = 0
        if contents[0][/^\d+$/]   # If first line is a number, text is stored in an array
          text_hash = []
          item_length = 3
          if is_map
            raise _INTL("La sección {1} no puede ser una lista ordenada (la sección fue reconocida como una lista ordenada porque su primera línea es un número).", section_name)
          end
          if contents.length % 3 != 0
            raise _INTL("El recuento de líneas de la sección {1} no es divisible por 3 (la sección se reconoció como una lista ordenada porque su primera línea es un número).", section_name)
          end
        else   # El texto se almacena en un hash
          text_hash = {}
          item_length = 2
          if contents.length.odd?
            raise _INTL("La sección {1} tiene un número impar de entradas (la sección se reconoció como un hash porque su primera línea no es un número).", section_name)
          end
        end
        # Agregar texto en la sección a la lista/hash ordenados
        i = 0
        loop do
          if item_length == 3
            if !contents[i][/^\d+$/]
              raise _INTL("Se esperaba un número en la sección {1}, en su lugar se obtuvo {2}", section_name, contents[i])
            end
            key = contents[i].to_i
            i += 1
          else
            key = denormalize_value(contents[i])
            key = Translation.stringToKey(key)
          end
          text_hash[key] = denormalize_value(contents[i + 1])
          i += 2
          break if i >= contents.length
        end
        # Añadir una lista ordenada/hash (`text_hash`) a un array de todo el texto (`all_text`).
        all_text[MessageTypes::EVENT_TEXTS] = [] if is_map && !all_text[MessageTypes::EVENT_TEXTS]
        target_section = (is_map) ? all_text[MessageTypes::EVENT_TEXTS][section_id] : all_text[section_id]
        if target_section
          if text_hash.is_a?(Hash)
            text_hash.each_key { |key| target_section[key] = text_hash[key] if text_hash[key] }
          else   # text_hash es un array
            text_hash.each_with_index { |line, j| target_section[j] = line if line }
          end
        elsif is_map
          all_text[MessageTypes::EVENT_TEXTS][section_id] = text_hash
        else
          all_text[section_id] = text_hash
        end
      end
    ensure
      file.close
    end
  end
end

#===============================================================================
#
#===============================================================================
class Translation
  attr_reader :core_messages, :game_messages

  def self.stringToKey(str)
    if str && str[/[\r\n\t\1]|^\s+|\s+$|\s{2,}/]
      key = str.clone
      key.gsub!(/^\s+/, "")
      key.gsub!(/\s+$/, "")
      key.gsub!(/\s{2,}/, " ")
      return key
    end
    return str
  end

  def initialize(filename = nil, delay_load = false)
    @default_core_messages = nil
    @default_game_messages = nil
    @core_messages = nil   # Un archivo de traducción
    @game_messages = nil   # Un archivo de traducción
    @filename = filename
    load_message_files(@filename) if @filename && !delay_load
  end

  def default_core_messages
    load_default_messages
    return @default_core_messages
  end

  def default_game_messages
    load_default_messages
    return @default_game_messages
  end

  def load_message_files(filename)
    begin
      core_filename = sprintf("Data/messages_%s_core.dat", filename)
      if FileTest.exist?(core_filename)
        pbRgssOpen(core_filename, "rb") { |f| @core_messages = Marshal.load(f) }
      end
      @core_messages = nil if !@core_messages.is_a?(Array)
      game_filename = sprintf("Data/messages_%s_game.dat", filename)
      if FileTest.exist?(game_filename)
        pbRgssOpen(game_filename, "rb") { |f| @game_messages = Marshal.load(f) }
      end
      @game_messages = nil if !@game_messages.is_a?(Array)
    rescue
      @core_messages = nil
      @game_messages = nil
    end
  end

  def load_default_messages
    return if @default_core_messages
    begin
      if FileTest.exist?("Data/messages_core.dat")
        pbRgssOpen("Data/messages_core.dat", "rb") { |f| @default_core_messages = Marshal.load(f) }
      end
      @default_core_messages = [] if !@default_core_messages.is_a?(Array)
      if FileTest.exist?("Data/messages_game.dat")
        pbRgssOpen("Data/messages_game.dat", "rb") { |f| @default_game_messages = Marshal.load(f) }
      end
      @default_game_messages = [] if !@default_game_messages.is_a?(Array)
    rescue
      @default_core_messages = []
      @default_game_messages = []
    end
  end

  def save_default_messages
    File.open("Data/messages_core.dat", "wb") { |f| Marshal.dump(@default_core_messages, f) }
    File.open("Data/messages_game.dat", "wb") { |f| Marshal.dump(@default_game_messages, f) }
  end

  def setMessages(type, array)
    load_default_messages
    @default_game_messages[type] = priv_add_to_array(type, array, nil)
  end

  def addMessages(type, array)
    load_default_messages
    @default_game_messages[type] = priv_add_to_array(type, array, @default_game_messages[type])
  end

  def setMessagesAsHash(type, array)
    load_default_messages
    @default_game_messages[type] = priv_add_to_hash(type, array, nil)
  end

  def addMessagesAsHash(type, array)
    load_default_messages
    @default_game_messages[type] = priv_add_to_hash(type, array, @default_game_messages[type])
  end

  def setMapMessagesAsHash(map_id, array)
    load_default_messages
    @default_game_messages[MessageTypes::EVENT_TEXTS] ||= []
    @default_game_messages[MessageTypes::EVENT_TEXTS][map_id] = priv_add_to_hash(
      MessageTypes::EVENT_TEXTS, array, nil, map_id
    )
  end

  def addMapMessagesAsHash(map_id, array)
    load_default_messages
    @default_game_messages[MessageTypes::EVENT_TEXTS] ||= []
    @default_game_messages[MessageTypes::EVENT_TEXTS][map_id] = priv_add_to_hash(
      MessageTypes::EVENT_TEXTS, array, @default_game_messages[MessageTypes::EVENT_TEXTS][map_id], map_id
    )
  end

  def get(type, id)
    delayed_load_message_files
    if @game_messages && @game_messages[type] && @game_messages[type][id]
      return @game_messages[type][id]
    end
    if @core_messages && @core_messages[type] && @core_messages[type][id]
      return @core_messages[type][id]
    end
    return ""
  end

  def getFromHash(type, text)
    delayed_load_message_files
    key = Translation.stringToKey(text)
    return text if nil_or_empty?(key)
    if @game_messages && @game_messages[type] && @game_messages[type][key]
      return @game_messages[type][key]
    end
    if @core_messages && @core_messages[type] && @core_messages[type][key]
      return @core_messages[type][key]
    end
    return text
  end

  def getFromMapHash(map_id, text)
    delayed_load_message_files
    key = Translation.stringToKey(text)
    return text if nil_or_empty?(key)
    if @game_messages && @game_messages[MessageTypes::EVENT_TEXTS]
      if @game_messages[MessageTypes::EVENT_TEXTS][map_id] && @game_messages[MessageTypes::EVENT_TEXTS][map_id][key]
        return @game_messages[MessageTypes::EVENT_TEXTS][map_id][key]
      elsif @game_messages[MessageTypes::EVENT_TEXTS][0] && @game_messages[MessageTypes::EVENT_TEXTS][0][key]
        return @game_messages[MessageTypes::EVENT_TEXTS][0][key]
      end
    end
    if @core_messages && @core_messages[MessageTypes::EVENT_TEXTS]
      if @core_messages[MessageTypes::EVENT_TEXTS][map_id] && @core_messages[MessageTypes::EVENT_TEXTS][map_id][key]
        return @core_messages[MessageTypes::EVENT_TEXTS][map_id][key]
      elsif @core_messages[MessageTypes::EVENT_TEXTS][0] && @core_messages[MessageTypes::EVENT_TEXTS][0][key]
        return @core_messages[MessageTypes::EVENT_TEXTS][0][key]
      end
    end
    return text
  end

  #-----------------------------------------------------------------------------

  private

  def delayed_load_message_files
    return if !@filename || @core_messages
    load_message_files(@filename)
    @filename = nil
  end

  def priv_add_to_array(type, array, ret)
    @default_core_messages[type] ||= []
    ret = [] if !ret
    array.each_with_index do |text, i|
      ret[i] = text if !nil_or_empty?(text) && @default_core_messages[type][i] != text
    end
    return ret
  end

  def priv_add_to_hash(type, array, ret, map_id = 0)
    if type == MessageTypes::EVENT_TEXTS
      @default_core_messages[type] ||= []
      @default_core_messages[type][map_id] ||= {}
      default_keys = @default_core_messages[type][map_id].keys
    else
      @default_core_messages[type] ||= {}
      default_keys = @default_core_messages[type].keys
    end
    ret = {} if !ret
    array.each do |text|
      next if !text
      key = Translation.stringToKey(text)
      ret[key] = text if !default_keys.include?(key)
    end
    return ret
  end
end

#===============================================================================
#
#===============================================================================
module MessageTypes
  # NOTA: Estas constantes no están numeradas en un orden específico, pero estos
  #       números se conservan por compatibilidad con versiones antiguas de archivos
  #       de texto extraídos.
  EVENT_TEXTS                  = 0   # Se utiliza para texto tanto en eventos 
                                     # comunes como en eventos de mapas.
  SPECIES_NAMES                = 1
  SPECIES_CATEGORIES           = 2
  POKEDEX_ENTRIES              = 3
  SPECIES_FORM_NAMES           = 4
  MOVE_NAMES                   = 5
  MOVE_DESCRIPTIONS            = 6
  ITEM_NAMES                   = 7
  ITEM_NAME_PLURALS            = 8
  ITEM_DESCRIPTIONS            = 9
  ABILITY_NAMES                = 10
  ABILITY_DESCRIPTIONS         = 11
  TYPE_NAMES                   = 12
  TRAINER_TYPE_NAMES           = 13
  TRAINER_NAMES                = 14
  FRONTIER_INTRO_SPEECHES      = 15
  FRONTIER_END_SPEECHES_WIN    = 16
  FRONTIER_END_SPEECHES_LOSE   = 17
  REGION_NAMES                 = 18
  REGION_LOCATION_NAMES        = 19
  REGION_LOCATION_DESCRIPTIONS = 20
  MAP_NAMES                    = 21
  PHONE_MESSAGES               = 22
  TRAINER_SPEECHES_LOSE        = 23
  SCRIPT_TEXTS                 = 24
  RIBBON_NAMES                 = 25
  RIBBON_DESCRIPTIONS          = 26
  STORAGE_CREATOR_NAME         = 27
  ITEM_PORTION_NAMES           = 28
  ITEM_PORTION_NAME_PLURALS    = 29
  POKEMON_NICKNAMES            = 30
  TRAINER_SPEECHES_LOSE_F      = 31
  @@messages = Translation.new

  def self.load_default_messages
    @@messages.load_default_messages
  end

  def self.load_message_files(filename)
    @@messages.load_message_files(filename)
  end

  def self.save_default_messages
    @@messages.save_default_messages
  end

  def self.setMessages(type, array)
    @@messages.setMessages(type, array)
  end

  def self.addMessages(type, array)
    @@messages.addMessages(type, array)
  end

  def self.setMessagesAsHash(type, array)
    @@messages.setMessagesAsHash(type, array)
  end

  def self.addMessagesAsHash(type, array)
    @@messages.addMessagesAsHash(type, array)
  end

  def self.setMapMessagesAsHash(type, array)
    @@messages.setMapMessagesAsHash(type, array)
  end

  def self.addMapMessagesAsHash(type, array)
    @@messages.addMapMessagesAsHash(type, array)
  end

  def self.get(type, id)
    return @@messages.get(type, id)
  end

  def self.getFromHash(type, key)
    return @@messages.getFromHash(type, key)
  end

  def self.getFromMapHash(type, key)
    return @@messages.getFromMapHash(type, key)
  end
end

#===============================================================================
#
#===============================================================================
def pbGetMessage(type, id)
  res = MessageTypes.get(type, id) rescue ''
  return res unless res.is_a?(String)
  return PTBR_TEXT.translate(res, type)
  return MessageTypes.get(type, id)
end

def pbGetMessageFromHash(type, id)
  res = MessageTypes.getFromHash(type, id) rescue ''
  return res unless res.is_a?(String)
  special = PTBR_TEXT.translate_special_message(type, id, res)
  return special if special
  return PTBR_TEXT.translate(res, type)
  return MessageTypes.getFromHash(type, id)
end

# Reemplaza el primer argumento con una versión localizada y formatea los otros
# parámetros reemplazando {1}, {2}, etc. con esos marcadores de posición.
def _INTL(*arg)
  arg.each_with_index { |v, i| arg[i] = PTBR_TEXT.translate(v, nil) if v.is_a?(String) }
  begin
    string = MessageTypes.getFromHash(MessageTypes::SCRIPT_TEXTS, arg[0])
  rescue
    string = arg[0]
  end
  string = string.clone
  (1...arg.length).each do |i|
    string.force_encoding(Encoding::UTF_8)
    text_aux = arg[i].to_s.dup
    text_aux.force_encoding(Encoding::UTF_8)
    string.gsub!(/\{#{i}\}/, text_aux)
  end
  return string
end

# Reemplaza el primer argumento con una versión localizada y formatea los otros
# parámetros reemplazando {1}, {2}, etc. con esos marcadores de posición.
# Esta versión actúa más como sprintf, soporta por ejemplo {1:d} o {2:s}.
def _ISPRINTF(*arg)
  begin
    string = MessageTypes.getFromHash(MessageTypes::SCRIPT_TEXTS, arg[0])
  rescue
    string = arg[0]
  end
  string = string.clone
  (1...arg.length).each do |i|
    string.gsub!(/\{#{i}\:([^\}]+?)\}/) do |m|
      format_spec = $1
      value = arg[i]
      # Si el formato es para entero (%d, %i, %o, %x, %X) pero el valor es una cadena
      # que representa un número, convertirlo cuidadosamente
      if format_spec.match?(/[dioxX]/) && value.is_a?(String) && value.match?(/^\d+$/)
        # Convertir la cadena a entero de base 10 explícitamente
        value = value.to_i(10)
      end
      begin
        next sprintf("%" + format_spec, value)
      rescue ArgumentError
        # Si falla la conversión, usar el valor como string
        next sprintf("%s", value.to_s)
      end
    end
  end
  return string
end

def _I(str, *arg)
  return _MAPINTL($game_map.map_id, str, *arg)
end

def _MAPINTL(mapid, *arg)
  arg.each_with_index { |v, i| arg[i] = PTBR_TEXT.translate(v, nil) if v.is_a?(String) }
  string = MessageTypes.getFromMapHash(mapid, arg[0])
  string = string.clone
  (1...arg.length).each do |i|
    string.gsub!(/\{#{i}\}/, arg[i].to_s)
  end
  return string
end

def _MAPISPRINTF(mapid, *arg)
  string = MessageTypes.getFromMapHash(mapid, arg[0])
  string = string.clone
  (1...arg.length).each do |i|
    string.gsub!(/\{#{i}\:([^\}]+?)\}/) { |m| next sprintf("%" + $1, arg[i]) }
  end
  return string
end

