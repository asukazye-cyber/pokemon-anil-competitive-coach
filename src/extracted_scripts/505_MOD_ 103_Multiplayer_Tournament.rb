# encoding: UTF-8
#===============================================================================
# MOD: 103_Multiplayer_Tournament
#-------------------------------------------------------------------------------
# Implementa o sistema de nivelamento temporario (Level Cap) e suporte a torneios.
#===============================================================================

module AnilLanRework
  module Tournament
    @level_cap = nil
    @level_snapshot = nil
    @active_match = nil

    class << self
      attr_accessor :level_cap
      attr_accessor :active_match
    end

    # Aplica o nivelamento de level cap na party do jogador de forma temporaria.
    # Todos os Pokemon da equipe serao ajustados para o nivel do cap (para cima ou para baixo).
    def self.apply_level_cap!(party, cap)
      return if cap.nil? || cap.to_i <= 0
      
      AnilLanRework.log("[TOURNAMENT] Aplicando Level Cap #{cap} na equipe...") rescue nil
      @level_snapshot = []
      
      party.each do |pkmn|
        next unless pkmn
        # Guarda o snapshot do estado real do Pokemon
        @level_snapshot << {
          pokemon: pkmn,
          real_level: pkmn.level,
          real_hp: pkmn.hp,
          real_exp: pkmn.exp
        }
        
        # Ajusta para o nivel do cap (tanto para mais quanto para menos)
        pkmn.level = cap.to_i
        
        # Recalcula os stats do Pokemon com base no novo nivel
        pkmn.calc_stats rescue nil
        
        # Cura o Pokemon para o HP maximo correspondente ao nivel 50
        pkmn.hp = pkmn.totalhp
      end
    end

    # Restaura os niveis e estatisticas originais dos Pokemon a partir do snapshot.
    def self.restore_levels!
      return unless @level_snapshot
      
      AnilLanRework.log("[TOURNAMENT] Restaurando niveis reais da equipe pos-torneio...") rescue nil
      
      @level_snapshot.each do |entry|
        pkmn = entry[:pokemon]
        next unless pkmn
        
        pkmn.level = entry[:real_level]
        pkmn.exp   = entry[:real_exp]
        pkmn.calc_stats rescue nil
        
        # Ajusta o HP respeitando o valor real pre-torneio e o novo totalhp
        pkmn.hp = [entry[:real_hp], pkmn.totalhp].min
      end
      
      @level_snapshot = nil
    end

    # Retorna se ha um confronto de torneio ativo que requer cap
    def self.in_tournament_match?
      !@active_match.nil?
    end

    # =========================================================================
    # NIVEL FIXO NO PVP
    #
    # Um duelo entre um nivel 90 e um nivel 40 nao mede nada, entao os dois
    # lados entram no mesmo patamar. Zero desliga e o PVP volta aos niveis reais.
    # =========================================================================
    PVP_FIXED_LEVEL = 50 unless const_defined?(:PVP_FIXED_LEVEL)

    def self.pvp_fixed_level
      PVP_FIXED_LEVEL.to_i
    end

    # Nivela COPIAS. Cura porque o nivel novo muda o totalhp: manter o HP antigo
    # deixaria um Pokemon a 10/40 entrando a 10/130.
    #
    # Escreve @exp e @level DIRETO em vez de usar pkmn.level=. O plugin
    # Level Caps EX sobrescreve esse setter e corta qualquer valor acima do cap
    # de ginasio do jogador (020_Level_Caps_EX/001_Main.rb:35) — dois jogadores
    # com insignias diferentes sairiam com niveis diferentes, que e desync
    # garantido. E o mesmo motivo pelo qual o apply_pokemon_blob escreve o ivar
    # na mao.
    def self.level_party_in_place!(party, level)
      lvl = level.to_i
      return Array(party) if lvl <= 0
      max = (GameData::GrowthRate.max_level rescue 100)
      lvl = max if lvl > max
      Array(party).compact.each do |pkmn|
        begin
          pkmn.instance_variable_set(:@exp, pkmn.growth_rate.minimum_exp_for_level(lvl))
        rescue
        end
        pkmn.instance_variable_set(:@level, lvl)
        pkmn.calc_stats rescue nil
        pkmn.heal rescue nil
      end
      Array(party)
    end

    # Recebe um BLOB de equipe e devolve outro BLOB, nivelado. Devolve nil se
    # nao houver nada para nivelar.
    #
    # Trabalhar em blob, e nao em objetos, e o que faz isto funcionar. A
    # start_pvp_battle que roda de verdade e a do 029_Multiplayer_Patches (ela
    # sobrescreve a do 000d) e ela monta as DUAS equipes desserializando
    # data[:party] e data[:local_party], atribuindo $player.party direto. Ou
    # seja: mexer nos objetos depois nao adianta — quem manda sao os blobs que
    # estao no `data`. Trocando os dois blobs, as duas equipes saem niveladas
    # pelo mesmo caminho, com o mesmo numero de transformacoes, nos dois
    # clientes.
    #
    # E era esse o bug de origem: cada maquina montava a MESMA equipe de fontes
    # diferentes. Os dois blobs ja viajam e ja sao identicos nos dois lados
    # (110_Multiplayer_PVP_Lineup_Sync.rb:435-444 grava em :local_party os
    # mesmos bytes enviados ao oponente), so nao estavam sendo usados dos dois
    # lados.
    #
    # De brinde o save fica seguro: desserializar cria objetos NOVOS, entao o
    # Pokemon que esta no save nunca e tocado e nao ha nada a restaurar se o
    # jogo fechar no meio da luta.
    def self.blob_at_level(blob, level)
      lista = AnilLanRework::Serializer.deserialize_party(Array(blob))
      return nil if Array(lista).compact.empty?
      level_party_in_place!(lista, level)
      AnilLanRework::Serializer.serialize_party(lista)
    rescue => e
      AnilLanRework.log("[LEVELCAP] blob_at_level falhou: #{e.class}: #{e.message}") rescue nil
      nil
    end

    # Limpa as configuracoes de torneio ativo
    def self.clear_match_state!
      @level_cap = nil
      @active_match = nil
      @level_snapshot = nil
    end
  end
end

#===============================================================================
# Hooks para interceptar e injetar o Level Cap nas batalhas PvP
#===============================================================================
if defined?(AnilLanRework) && defined?(AnilLanRework::BattleSync)
  module AnilLanRework
    module BattleSync
      class << self
        alias anil_tourney_orig_start_pvp_battle start_pvp_battle unless method_defined?(:anil_tourney_orig_start_pvp_battle)

        # Nivel desta luta: o cap do torneio manda; fora de torneio, o fixo do PVP.
        def anil_pvp_battle_level(rules)
          normalizado = (normalize_duel_rules(rules) rescue {})
          cap = normalizado["level_cap"].to_i
          if cap <= 0 && (normalizado["tournament_match"] == true || AnilLanRework::Tournament.in_tournament_match?)
            cap = AnilLanRework::Tournament.level_cap.to_i
          end
          cap = AnilLanRework::Tournament.pvp_fixed_level if cap <= 0
          cap
        end

        # Enquanto o duelo corre, $player.party NAO e a equipe do jogador: e a
        # selecao, feita de copias niveladas. Um autosave nessa janela gravaria
        # ISSO como se fosse o save. O on_start_battle do MOD 040 dispara
        # exatamente ai.
        #
        # Bandeira propria em vez de olhar o @pvp_party_backup: esse ivar e do
        # prepare_local_pvp_party! do 000d, que a start_pvp_battle do 029 nao
        # chama — la a troca e feita com variavel local.
        def anil_pvp_party_swapped?
          @anil_pvp_em_duelo == true
        rescue
          false
        end

        def start_pvp_battle(data)
          nivel = anil_pvp_battle_level(data[:rules])

          if nivel > 0
            # Os DOIS blobs, pelo mesmo caminho. A start_pvp_battle do 029
            # desserializa data[:party] e data[:local_party] e monta a batalha
            # com o resultado — trocar os blobs aqui e o que faz as duas equipes
            # entrarem niveladas nos dois clientes.
            foe   = AnilLanRework::Tournament.blob_at_level(data[:party], nivel)
            minha = AnilLanRework::Tournament.blob_at_level(data[:local_party], nivel)
            if foe && minha
              data[:party]       = foe
              data[:local_party] = minha
              AnilLanRework.log("[LEVELCAP] Duelo #{data[:battle_id]} nivelado em #{nivel}.") rescue nil
            else
              # Nivelar so um lado e pior do que nao nivelar nenhum: as duas
              # simulacoes divergem no primeiro golpe.
              AnilLanRework.log("[LEVELCAP] Blob ausente (foe=#{!foe.nil?} local=#{!minha.nil?}); duelo #{data[:battle_id]} segue SEM nivelamento.") rescue nil
            end
          end

          @anil_pvp_em_duelo = true
          begin
            anil_tourney_orig_start_pvp_battle(data)
          ensure
            @anil_pvp_em_duelo = false
            AnilLanRework::Tournament.clear_match_state! if AnilLanRework::Tournament.in_tournament_match?
            AnilLanRework.save_and_upload_save_file("pvp_ended") rescue nil
          end
        end
      end
    end
  end
end

#===============================================================================
# Trava de autosave durante o PvP
#-------------------------------------------------------------------------------
# Ver anil_pvp_party_swapped?. Vale mesmo com o nivelamento desligado: a troca
# de party para a selecao do duelo ja existia antes deste MOD.
#
# A instalacao NAO pode ser um alias solto no corpo do arquivo: o MOD 040
# redefine save_and_upload_save_file em RUNTIME, dentro de
# apply_post_plugin_patches, e o MOD 101 reinjeta a versao dele logo depois. Um
# alias feito no carregamento seria apagado pelos dois. Entao a instalacao entra
# no fim dessa mesma cadeia, como o 101 faz.
#===============================================================================
module AnilLanRework
  class << self
    def anil_levelcap_install_save_guard!
      return unless respond_to?(:save_and_upload_save_file)
      atual = method(:save_and_upload_save_file)
      # Ja e a nossa? Sai. Sem isto, uma segunda passagem faria o alias apontar
      # para a propria versao guardada e a chamada viraria recursao infinita.
      return if @anil_levelcap_guarded_method && @anil_levelcap_guarded_method == atual

      singleton_class.class_eval do
        alias_method :anil_levelcap_orig_save_and_upload_save_file, :save_and_upload_save_file

        def save_and_upload_save_file(reason = "")
          if defined?(AnilLanRework::BattleSync) &&
             AnilLanRework::BattleSync.respond_to?(:anil_pvp_party_swapped?) &&
             AnilLanRework::BattleSync.anil_pvp_party_swapped?
            AnilLanRework.log("[LEVELCAP] Autosave recusado durante o PvP (razao: #{reason})") rescue nil
            return false
          end
          # Mesma protecao para o coop em lockstep: enquanto a party e a copia,
          # um autosave gravaria as COPIAS por cima da equipe real do jogador.
          if defined?(CoopCC) && CoopCC.respond_to?(:party_trocada?) && CoopCC.party_trocada?
            AnilLanRework.log("[LEVELCAP] Autosave recusado durante o coop (razao: #{reason})") rescue nil
            return false
          end
          anil_levelcap_orig_save_and_upload_save_file(reason)
        end
      end

      @anil_levelcap_guarded_method = method(:save_and_upload_save_file)
      log("[LEVELCAP] Trava de autosave do PvP instalada.") rescue nil
    rescue => e
      log("[LEVELCAP] Falha ao instalar a trava de autosave: #{e.class}: #{e.message}") rescue nil
    end

    if !method_defined?(:anil_levelcap_orig_apply_post_plugin_patches)
      alias_method :anil_levelcap_orig_apply_post_plugin_patches, :apply_post_plugin_patches rescue nil
    end

    def apply_post_plugin_patches
      anil_levelcap_orig_apply_post_plugin_patches if respond_to?(:anil_levelcap_orig_apply_post_plugin_patches)
      anil_levelcap_install_save_guard!
    end
  end
end

# Caso o pos-plugin ja tenha rodado quando este arquivo carregou.
begin
  AnilLanRework.anil_levelcap_install_save_guard!
rescue => e
  AnilLanRework.log("[LEVELCAP] Instalacao imediata da trava falhou: #{e.message}") rescue nil
end

# O save de "pvp_ended" e disparado no `ensure` da start_pvp_battle acima, assim
# que a bandeira cai — os autosaves do meio do duelo foram recusados, entao sem
# ele o resultado da luta ficaria so na memoria ate a proxima troca de mapa.

#===============================================================================
# Adiciona tratadores de pacotes de torneio vindos do servidor
#===============================================================================
if defined?(AnilLanRework) && defined?(AnilLanRework::Router)
  module AnilLanRework
    module Router
      # Pacote enviado pelo servidor quando uma partida do torneio e sorteada
      # Contem o oponente, o level cap e o ID do confronto
      def self.handle_tournament_match(packet)
        peer_id    = packet["opponent_id"].to_s
        peer_name  = packet["opponent_name"].to_s
        level_cap  = packet["level_cap"].to_i
        match_id   = packet["match_id"].to_s
        format     = packet["format"] || "single"

        AnilLanRework.log("[TOURNAMENT] Recebida partida contra #{peer_name} (ID: #{peer_id}) com Cap #{level_cap}") rescue nil

        # Salva o estado do confronto
        AnilLanRework::Tournament.level_cap = level_cap
        AnilLanRework::Tournament.active_match = {
          opponent_id: peer_id,
          opponent_name: peer_name,
          match_id: match_id
        }

        # Exibe mensagem informativa na tela do jogador
        pbPlayDecisionSE() rescue nil
        pbMessage(_INTL("\\r[Torneio Ativo!]\\n\\nSua proxima partida e contra \\c[2]#{peer_name}\\c[0] (Cap Nivel #{level_cap}).")) rescue nil

        # Abre automaticamente a tela de selecao de equipe/duelo contra o peer
        peer = AnilLanRework.players[peer_id]
        if peer
          # Cria as regras para a batalha respeitando o estilo
          rules = {
            "style" => format,
            "tournament_match" => true,
            "level_cap" => level_cap
          }
          # Triga o pedido de duelo
          AnilLanRework::BattleSync.request_duel(peer, size: (format == "double" ? 2 : 1), rules: rules)
        else
          pbMessage(_INTL("O oponente #{peer_name} nao foi encontrado no mapa. Va para a Arena de Torneio!")) rescue nil
        end
      end

      # Trata comunicados informativos de chaveamento e resultados do torneio
      def self.handle_tournament_broadcast(packet)
        text = packet["text"].to_s
        # Exibe como um popup ou banner no jogo do usuario
        if defined?(AnilLanRework.add_popup)
          AnilLanRework.add_popup(text, 6.0)
        else
          pbMessage(_INTL("\\r[Organizador do Torneio]\\n\\n#{text}")) rescue nil
        end
      end
    end
  end
end
