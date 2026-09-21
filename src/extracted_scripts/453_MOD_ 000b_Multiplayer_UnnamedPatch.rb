#===============================================================================
# AnilLanRework — Patch: "Unnamed" como nome nulo
#
# PROBLEMA:
#   O jogo inicia com $player.name = "Unnamed" antes do jogador escolher
#   o nick. O update_player_config gera o ID a partir do nome:
#     id = "jogador-#{clean_name}"  →  "jogador-Unnamed"
#   Quando o jogador escolhe o nome real, o ID muda para "jogador-MeuNome",
#   e o servidor VPS recusa a conexão porque o par nome+ID da whitelist
#   não bate com o que foi registrado antes.
#
# SOLUÇÃO:
#   1. update_player_config: se o nome for "Unnamed", não gera nem sobrescreve
#      o ID — mantém o que já estiver salvo no arquivo. O ID só é gerado/
#      atualizado quando o jogador tiver um nome real.
#
#   2. Watcher de mudança de nome (Scene_Map update): ignora transições que
#      envolvem "Unnamed" para não limpar sessões nem reconfigurar
#      desnecessariamente durante o início do jogo.
#
#   3. Todos os pontos que leem player_name para conexão substituem "Unnamed"
#      por "Jogador" como display name (não afeta o ID).
#
# ESCOPO: só altera comportamento quando nome == "Unnamed".
#         Não toca no código normal do PC (pbEnterPlayerName, etc).
#         Não afeta JoiPlay nem PC de formas diferentes entre si.
#===============================================================================

module AnilLanRework

  # Nome considerado "não escolhido ainda" — case-insensitive
  UNNAMED_PLACEHOLDER = "Unnamed"

  def self.unnamed_name?(name)
    name.to_s.strip.casecmp(UNNAMED_PLACEHOLDER) == 0
  end

  # Retorna o nome de display seguro para envio ao servidor.
  # Se o nome for "Unnamed", usa "Jogador" como fallback de exibição,
  # mas o ID permanece intacto (não é derivado deste valor).
  def self.safe_display_name(raw_name)
    return "Jogador" if unnamed_name?(raw_name)
    raw_name.to_s
  end

  def self.default_trainer_type
    if defined?(GameData) && defined?(GameData::TrainerType)
      if GameData::TrainerType.exists?(:POKEMONTRAINER_RojoNeutro)
        return :POKEMONTRAINER_RojoNeutro
      end
      return GameData::TrainerType.keys.first
    end
    :POKEMONTRAINER_RojoNeutro
  end

  class << self
    alias_method :anil_unnamed_orig_trainer_type_for_character, :trainer_type_for_character rescue nil
    def trainer_type_for_character(char_name, fallback = nil)
      if fallback == (defined?(GameData::TrainerType) ? GameData::TrainerType.keys.first : nil)
        fallback = default_trainer_type
      end
      ret = anil_unnamed_orig_trainer_type_for_character(char_name, fallback) rescue nil

      # ⚠️ fallback nil = "diz-me a VERDADE, mesmo que seja nao ha tipo".
      #
      # Sem esta saida, este patch tapava o nil com o RojoNeutro e partia todas
      # as skins customizadas: o trainer_sprite_name_for_character passa nil de
      # proposito, porque e o nil que o faz cair no ramo seguinte e procurar
      # Graphics/Trainers/<nome>.png. Recebendo um tipo, ele usava o sprite
      # desse tipo e a skin aparecia com o treinador do Rojo no seletor, no
      # trainer card e na animacao VS — so o boneco do mapa ficava certo,
      # porque esse vem do charset e nao passa por aqui.
      #
      # Os chamadores que QUEREM um valor por omissao passam
      # GameData::TrainerType.keys.first (as batalhas e os peers), e para esses
      # a correcao continua igual — que e o caso para que este patch nasceu.
      return ret if fallback.nil?

      if ret.nil? || ret == (defined?(GameData::TrainerType) ? GameData::TrainerType.keys.first : nil)
        ret = default_trainer_type
      end
      ret
    end

    alias_method :anil_unnamed_orig_build_preview_trainer, :build_preview_trainer rescue nil
    def build_preview_trainer(trainer_name)
      trainer = anil_unnamed_orig_build_preview_trainer(trainer_name) rescue nil
      if trainer && (trainer.trainer_type == (defined?(GameData::TrainerType) ? GameData::TrainerType.keys.first : nil))
        trainer.trainer_type = default_trainer_type
      end
      trainer
    end
  end

end

#-------------------------------------------------------------------------------
# 1. Patch em update_player_config
#    Quando nome == "Unnamed", preserva o ID que já está no arquivo.
#    O ID só é atualizado (gerado de novo) quando o nome for real.
#-------------------------------------------------------------------------------
module AnilLanRework
  class << self
    alias_method :anil_unnamed_patch_original_update_player_config, :update_player_config

    def update_player_config
      return unless defined?($player) && $player

      name = $player.name.to_s

      # Se o nome ainda é "Unnamed", executa update normalmente MAS
      # sem sobrescrever o ID salvo — mantém o ID antigo se já existir.
      if AnilLanRework.unnamed_name?(name)
        file = AnilLanRework::PLAYER_CFG rescue "multiplayer_player.txt"
        char = ($game_player.character_name.to_s rescue "trainer_m")

        rows = {}
        if File.exist?(file)
          File.readlines(file, encoding: "UTF-8").each do |line|
            parts = line.strip.split("=", 2)
            rows[parts[0].strip] = parts[1].to_s.strip if parts.size == 2
          end
        end

        # Se não tem ID ainda, gera um baseado no machine_token puro
        # (sem nome, para não "travar" em jogador-Unnamed)
        unless rows.key?("id") && !rows["id"].to_s.strip.empty?
          token = AnilLanRework.machine_token.to_s rescue "jogador#{rand(9000)+1000}"
          rows["id"] = "jogador-#{token}"
        end
        # NÃO atualiza rows["id"] — mantém o que já está salvo

        # Atualiza nome e char normalmente
        rows["nome"] = name
        rows["char"] = char

        coop_partial_key = AnilLanRework::COOP_PARTIAL_CFG_KEY rescue "coop_partial"
        coop_total_key   = AnilLanRework::COOP_TOTAL_CFG_KEY   rescue "coop_total"
        rows[coop_partial_key] = "1" unless rows.key?(coop_partial_key)
        rows[coop_total_key]   = "0" unless rows.key?(coop_total_key)

        begin
          File.open(file, "wb") do |f|
            f.write(rows.map { |k, v| "#{k}=#{v}\n" }.join.encode(Encoding::UTF_8))
          end
          log("update_player_config (Unnamed — ID preservado): #{rows['id']}")
        rescue => e
          log("update_player_config (Unnamed) error: #{e}")
        end

        return  # não chama o original para este caso
      end

      # Nome real → comportamento original
      anil_unnamed_patch_original_update_player_config
    end
  end
end

#-------------------------------------------------------------------------------
# 2. Patch no watcher de mudança de nome (Scene_Map / main update loop)
#    Ignora transições que envolvam "Unnamed" para não limpar sessões.
#
#    O watcher original (no core) é:
#      if $player.name.to_s != $anil_last_player_name.to_s
#        $anil_last_player_name = $player.name.to_s
#        AnilLanRework.update_player_config
#        File.delete("multiplayer_sessions_rework.json") if ...
#      end
#
#    Solução: sobrescreve $anil_last_player_name com "Unnamed" na inicialização
#    para que a primeira transição (Unnamed → Nome Real) não trigger o delete.
#    O delete só ocorre quando ambos os nomes são reais (nenhum é "Unnamed").
#-------------------------------------------------------------------------------
module AnilLanRework
  module UnnamedWatcherPatch
    def self.apply!
      # Garante que $anil_last_player_name começa como "Unnamed"
      # para neutralizar a primeira detecção de mudança ao escolher o nick.
      $anil_last_player_name ||= AnilLanRework::UNNAMED_PLACEHOLDER
    end
  end
end

# Aplica ao carregar
AnilLanRework::UnnamedWatcherPatch.apply!

# Monkey-patch no método que contém o watcher, se acessível via Scene_Map
# (proteção extra: só redefine se o módulo existir)
if defined?(Scene_Map)
  class Scene_Map
    unless method_defined?(:anil_unnamed_original_update_multiplayer_context) ||
           private_method_defined?(:anil_unnamed_original_update_multiplayer_context)

      # Tenta localizar o método que contém o watcher de nome
      # (pode ser update, update_multiplayer, etc. — depende da versão)
      target = [:update_multiplayer_context, :update_multiplayer, :anil_tick_player_name_watch].find do |m|
        method_defined?(m) || private_method_defined?(m)
      end

      if target
        alias_method :anil_unnamed_original_update_multiplayer_context, target

        define_method(target) do |*args, &block|
          # Antes de chamar o original, sincroniza o last_name para evitar
          # que uma transição de/para Unnamed dispare o clear de sessões.
          cur = (defined?($player) && $player) ? $player.name.to_s : ""
          last = $anil_last_player_name.to_s

          if AnilLanRework.unnamed_name?(cur) || AnilLanRework.unnamed_name?(last)
            # Atualiza o tracker sem fazer mais nada (evita o delete de sessão)
            $anil_last_player_name = cur
            return
          end

          anil_unnamed_original_update_multiplayer_context(*args, &block)
        end
      end
    end
  end
end

#-------------------------------------------------------------------------------
# 3. Patch nos pontos de conexão: substitui "Unnamed" por "Jogador" como
#    player_name enviado ao servidor (display name apenas — não afeta o ID).
#
#    Isso evita que o servidor registre o par (id=X, nome="Unnamed") na
#    whitelist, o que causaria rejeição quando o nome real fosse usado.
#-------------------------------------------------------------------------------
module AnilLanRework
  class << self
    alias_method :anil_unnamed_patch_original_connect, :connect

    def connect(ip, player_id, player_name, char_name, is_host = false, alt_ips = nil, startup: false)
      safe_name = AnilLanRework.safe_display_name(player_name)
      if safe_name != player_name.to_s
        log("connect: nome '#{player_name}' substituído por '#{safe_name}' (Unnamed placeholder)")
      end
      anil_unnamed_patch_original_connect(ip, player_id, safe_name, char_name, is_host, alt_ips, startup: startup)
    end
  end
end

#===============================================================================
# Patch: machine_token inválido no JoiPlay ("localhost")
#
# PROBLEMA:
#   No JoiPlay/Android, Socket.gethostname retorna "localhost", que é um
#   hostname genérico — igual em todos os dispositivos. Isso faz com que
#   o machine_token seja "localhost" e o ID final seja "jogador-Nome-localhost",
#   colide com todos os outros jogadores no JoiPlay.
#
#   Saves antigos sem campo "id" no multiplayer_player.txt também usam
#   machine_token como fallback, herdando o problema.
#
# SOLUÇÃO:
#   1. machine_token: detecta hostnames inválidos ("localhost", "127.0.0.1",
#      strings vazias, "android", "linux", etc.) e gera/reutiliza um token
#      persistente salvo em arquivo (multiplayer_device_token.txt).
#      No PC o comportamento é idêntico ao original.
#
#   2. read_cfg para "id": se o valor lido contiver um token inválido
#      (ex: termina com "-localhost"), trata como se não houvesse ID —
#      força geração de um novo ID estável.
#===============================================================================

module AnilLanRework

  DEVICE_TOKEN_FILE = "multiplayer_device_token.txt"

  # Hostnames genéricos que o JoiPlay/Android retorna e que não servem
  # como identificador único de dispositivo.
  INVALID_MACHINE_TOKENS = %w[
    localhost localhost.localdomain
    127.0.0.1 ::1
    android linux unix unknown
    localhost.home localhost.local
  ].freeze

  def self.machine_token_invalid?(token)
    t = token.to_s.strip.downcase
    return true if t.empty?
    return true if INVALID_MACHINE_TOKENS.include?(t)
    # Hostnames numéricos puros (ex: "127001") também são suspeitos
    return true if t =~ /\A\d+\z/
    false
  end

  # Gera ou lê um token persistente único por dispositivo.
  # Salvo em arquivo para sobreviver restarts do jogo.
  def self.persistent_device_token
    if File.exist?(DEVICE_TOKEN_FILE)
      tok = File.read(DEVICE_TOKEN_FILE, encoding: "UTF-8").strip rescue ""
      return tok unless tok.empty? || machine_token_invalid?(tok)
    end
    # Gera novo token: timestamp + rand, compacto e alfanumérico
    new_tok = "dev#{Time.now.to_i.to_s(36)}#{rand(0xFFFF).to_s(36)}"
    begin
      File.open(DEVICE_TOKEN_FILE, "w:UTF-8") { |f| f.write(new_tok) }
    rescue => e
      log("persistent_device_token write error: #{e}")
    end
    new_tok
  end

  class << self
    alias_method :anil_localhost_patch_original_machine_token, :machine_token

    def machine_token
      raw_token = anil_localhost_patch_original_machine_token
      if machine_token_invalid?(raw_token)
        log("machine_token: '#{raw_token}' é inválido (JoiPlay/localhost) — usando token persistente") if raw_token != @_last_logged_bad_token
        @_last_logged_bad_token = raw_token
        persistent_device_token
      else
        raw_token
      end
    end
  end

end

#-------------------------------------------------------------------------------
# Patch em do_host_on_map e do_join_on_map:
# Se o player_id lido do arquivo contiver um token inválido (save antigo
# com "localhost"), descarta e força geração de novo ID limpo.
#-------------------------------------------------------------------------------
module AnilLanRework

  # Retorna true se o ID salvo em arquivo foi gerado com um machine_token
  # inválido (ex: "jogador-MeuNome-localhost") e deve ser regenerado.
  def self.saved_id_has_invalid_token?(id_str)
    return true if id_str.to_s.strip.empty?
    suffix = id_str.to_s.split("-").last.to_s.downcase
    machine_token_invalid?(suffix)
  end

  # Resolve o player_id correto: lê do cfg, descarta se inválido, gera novo.
  def self.resolve_player_id_from_cfg
    raw_id = read_cfg(PLAYER_CFG, "id", "").to_s.strip

    if raw_id.empty? || saved_id_has_invalid_token?(raw_id)
      if !raw_id.empty?
        log("resolve_player_id_from_cfg: ID '#{raw_id}' tem token inválido (localhost/antigo) — gerando novo")
      end
      # Gera ID estável usando o machine_token corrigido
      new_id = update_player_config_and_get_id
      return new_id
    end

    raw_id
  end

  # Força update_player_config e retorna o ID que foi escrito.
  # Usado para regenerar o ID quando o salvo está inválido.
  def self.update_player_config_and_get_id
    update_player_config rescue nil
    read_cfg(PLAYER_CFG, "id", "jogador#{rand(9000)+1000}").to_s.strip
  end

end

#-------------------------------------------------------------------------------
# Monkey-patch em do_host_on_map e do_join_on_map para usar resolve_player_id.
# Também cobre trigger_auto_connect_on_map e qualquer outro ponto que leia
# o player_id do cfg com machine_token como fallback.
#
# Ao invés de reescrever os métodos inteiros, substituímos o padrão:
#   player_id = AnilLanRework.read_cfg(PLAYER_CFG, "id", machine_token)
#   player_id = machine_token if player_id.empty?
# pelo método resolve_player_id_from_cfg que já trata tudo.
#-------------------------------------------------------------------------------
if defined?(Scene_Map_MultiplayerMainMenu)
  module Scene_Map_MultiplayerMainMenu

    if method_defined?(:do_host_on_map) && !method_defined?(:anil_localhost_original_do_host_on_map)
      alias_method :anil_localhost_original_do_host_on_map, :do_host_on_map

      def do_host_on_map
        # Injeta o ID corrigido antes de chamar o original
        # O original lê o ID via read_cfg — ao chamar update_player_config
        # antes, garantimos que o arquivo já tem o ID correto.
        AnilLanRework.resolve_player_id_from_cfg rescue nil
        anil_localhost_original_do_host_on_map
      end
    end

    if method_defined?(:do_join_on_map) && !method_defined?(:anil_localhost_original_do_join_on_map)
      alias_method :anil_localhost_original_do_join_on_map, :do_join_on_map

      def do_join_on_map
        AnilLanRework.resolve_player_id_from_cfg rescue nil
        anil_localhost_original_do_join_on_map
      end
    end

  end
end

# Também cobre trigger_auto_connect_on_map (usado no auto-connect por mapa)
module AnilLanRework
  class << self
    begin
      alias_method :anil_localhost_original_trigger_auto_connect, :trigger_auto_connect_on_map

      def trigger_auto_connect_on_map(silent = false)
        resolve_player_id_from_cfg rescue nil
        anil_localhost_original_trigger_auto_connect(silent)
      end
    rescue NameError
      # trigger_auto_connect_on_map não existe nesta versão — sem problema
    end
  end
end

#-------------------------------------------------------------------------------
# 4. Bypass de tradução para nomes de jogadores (Evitar Chico -> Jovem)
#-------------------------------------------------------------------------------
if defined?(PTBR_TEXT)
  module PTBR_TEXT
    class << self
      alias_method :anil_translate_original_name_bypass, :translate unless method_defined?(:anil_translate_original_name_bypass)
      # Normaliza para UTF-8 valido. Sem isso, uma string com bytes Windows-1252
      # (nomes/textos vindos de save ou de rede) estoura Encoding error no gsub
      # la dentro do Intl_Messages.
      def anil_normalize_utf8(str)
        return str unless str.is_a?(String)
        begin
          if str.encoding != Encoding::UTF_8
            return str.encode(Encoding::UTF_8, :invalid => :replace, :undef => :replace, :replace => "")
          end
          return str if str.valid_encoding?
          guess = str.dup.force_encoding(Encoding::WINDOWS_1252)
          if guess.valid_encoding?
            return guess.encode(Encoding::UTF_8, :invalid => :replace, :undef => :replace, :replace => "")
          end
          return str.scrub("")
        rescue
          return (str.scrub("") rescue str)
        end
      end

      def translate(str, context_id = nil)
        str = anil_normalize_utf8(str)
        if str.is_a?(String)
          # Protege o nome do jogador atual
          if defined?($player) && $player && $player.respond_to?(:name)
            pname = $player.name.to_s rescue ""
            if !pname.empty? && str.downcase == pname.downcase
              return str
            end
          end
          # Protege o nome dos jogadores conectados no lobby/multiplayer (O(1) cache atualizado uma vez por frame)
          if defined?(AnilLanRework) && AnilLanRework.respond_to?(:players) && AnilLanRework.players
            cf = Graphics.frame_count rescue 0
            if !@last_player_names_update_frame || cf != @last_player_names_update_frame
              @last_player_names_update_frame = cf
              @player_names_cache = {}
              AnilLanRework.players.each_value do |peer|
                name = peer.name.to_s rescue ""
                next if name.empty?
                @player_names_cache[name.downcase] = true
              end
            end
            if @player_names_cache && @player_names_cache[str.downcase]
              return str
            end
          end
        end
        anil_translate_original_name_bypass(str, context_id)
      end
    end
  end
end

#-------------------------------------------------------------------------------
# 5. Handler de Pacote Cliente: admin_edit_bag
#-------------------------------------------------------------------------------
if defined?(AnilLanRework) && defined?(AnilLanRework::Router)
  module AnilLanRework
    module Router
      class << self
        alias_method :anil_unnamed_orig_route_packet, :route_packet unless method_defined?(:anil_unnamed_orig_route_packet)
        def route_packet(packet)
          if packet && packet["type"] == "admin_edit_bag"
            begin
              item_str = packet["item"].to_s.strip.upcase
              qty = packet["qty"].to_i
              sender = packet["sender"].to_s
              sender = "ADMINISTRADOR" if sender.empty?
              
              if $bag && !item_str.empty?
                item_sym = item_str.to_sym rescue nil
                if item_sym && GameData::Item.exists?(item_sym)
                  cur_qty = $bag.quantity(item_sym)
                  if qty <= 0
                    if cur_qty > 0
                      $bag.remove(item_sym, cur_qty)
                    end
                    pbPlayDecisionSE() rescue nil
                    pbMessage(_INTL("\\c[4][#{sender}]\\c[0] removeu todos os \\c[2]{1}\\c[0] da sua mochila!", GameData::Item.get(item_sym).name)) rescue nil
                  else
                    if qty > cur_qty
                      $bag.add(item_sym, qty - cur_qty)
                    elsif qty < cur_qty
                      $bag.remove(item_sym, cur_qty - qty)
                    end
                    pbPlayDecisionSE() rescue nil
                    pbMessage(_INTL("\\c[4][#{sender}]\\c[0] alterou \\c[2]{1}\\c[0] na sua mochila para \\c[2]x{2}\\c[0]!", GameData::Item.get(item_sym).name, qty)) rescue nil
                  end
                  if defined?(Game) && Game.respond_to?(:save)
                    Game.save rescue nil
                  end
                end
              end
            rescue => e
              AnilLanRework.log("admin_edit_bag error: #{e.message}")
            end
            return
          end
          anil_unnamed_orig_route_packet(packet)
        end
      end
    end
  end
end
