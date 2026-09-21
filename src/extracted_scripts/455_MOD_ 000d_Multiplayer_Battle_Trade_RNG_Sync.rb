#===============================================================================
# MODULO: Battle, Trade & RNG Sync (Monkey Patches)
# Separado dos modulos principais online/lan para facil manutencao.
#===============================================================================

module AnilLanRework
  # Check desenhado a mao. As fontes do jogo (power green/clear) nao tem o
  # glifo U+2713, entao um "✓" de texto sairia como caixinha vazia.
  module CheckIcon
    VERDE  = Color.new(110, 235, 130)
    SOMBRA = Color.new(0, 0, 0, 170)

    def self.desenhar(bmp, x, y, size)
      return unless bmp
      grossura = [(size / 4.0).round, 2].max
      vx = x + (size * 0.38)
      vy = y + (size * 0.92)
      traco = lambda do |x1, y1, x2, y2, cor|
        passos = [((x2 - x1).abs + (y2 - y1).abs).to_i, 1].max
        (0..passos).each do |i|
          t = i.to_f / passos
          bmp.fill_rect((x1 + ((x2 - x1) * t)).round, (y1 + ((y2 - y1) * t)).round,
                        grossura, grossura, cor)
        end
      end
      traco.call(x + 1, y + (size * 0.55) + 1, vx + 1, vy + 1, SOMBRA)
      traco.call(vx + 1, vy + 1, x + size + 1, y + (size * 0.12) + 1, SOMBRA)
      traco.call(x, y + (size * 0.55), vx, vy, VERDE)
      traco.call(vx, vy, x + size, y + (size * 0.12), VERDE)
    rescue
    end
  end

  # Faixa de aviso no mesmo estilo da mensagem de broadcast: atravessa a tela
  # inteira, com degrade nas duas pontas e SEM moldura de janela.
  #
  # Substitui a Window_UnformattedTextPokemon que as esperas usavam: ela virava
  # uma tarja quadrada no meio da tela e, quando o texto nao cabia na largura
  # que ela calculava, era o proprio texto que saia cortado. Aqui o texto e
  # quebrado por palavra e a faixa CRESCE em altura para caber tudo.
  #
  # Serve tambem de rodape do PvP (com o icone de confirmado), por isso o
  # ancoramento opcional no topo e o check desenhado no fim da ultima linha.
  class WaitBanner
    LINE_H     = 26
    PAD_Y      = 10
    MARGIN_X   = 28   # respiro para o texto nao encostar no degrade
    CHECK_SIZE = 17

    def initialize(viewport, text, anchor: :center, check: false)
      @sprite = Sprite.new(viewport)
      @sprite.z = 100_001
      @anchor = anchor
      @key = nil
      @text = ""
      set_text(text, check: check)
    end

    # ------------------------------------------------------------------
    # Compatibilidade com Window_UnformattedTextPokemon.
    #
    # A faixa entra no lugar daquela janela dentro do build_wait_window, e os
    # ~25 chamadores das esperas ja mexiam no objeto como se fosse uma Window:
    # liam e escreviam .text, chamavam .update, .visible=, .x/.y/.width/.height
    # e .resizeToFit. Boa parte disso SEM `rescue`, entao faltar um metodo
    # derrubava a batalha inteira — foi o NoMethodError de `text` no
    # wait_for_remote_turn. Estes delegados existem para essa compatibilidade.
    # ------------------------------------------------------------------
    attr_reader :text

    def text=(valor)
      set_text(valor)
    end

    def update; end

    # ------------------------------------------------------------------
    # ATRASO ANTES DE APARECER
    #
    # A maioria das esperas resolve-se em milissegundos e a faixa so piscava —
    # inclusive a de "ganhando experiencia", marcada uma vez por Pokemon a cada
    # desmaio. Com o atraso, essas nunca chegam a ser vistas.
    #
    # O atraso e de VISIBILIDADE, nao de criacao. Recusar criar era o caminho
    # obvio e esta errado: so 5 dos ~27 chamadores repetem o pedido em ciclo, e
    # os outros ~22 ficariam sem faixa nenhuma para sempre. Criada e invisivel,
    # funciona igual para quem pede uma vez e para quem pede em ciclo.
    #
    # `@visivel_desejado` guarda o que os chamadores pediram com `visible=`,
    # para que a revelacao no fim do atraso respeite quem tinha escondido a
    # faixa de proposito.
    # ------------------------------------------------------------------
    def revelar_apos(segundos)
      @revelar_em = Time.now.to_f + segundos.to_f
      @visivel_desejado = true
      @sprite.visible = false unless disposed?
    end

    def pendente?
      !@revelar_em.nil?
    end

    # Chamado uma vez por frame (ver o gancho no Graphics.update, no 032).
    def verificar_revelacao
      return if @revelar_em.nil?
      return if Time.now.to_f < @revelar_em
      @revelar_em = nil
      @sprite.visible = (@visivel_desejado != false) unless disposed?
    rescue
      @revelar_em = nil
    end

    def visible
      disposed? ? false : @sprite.visible
    end

    def visible=(valor)
      @visivel_desejado = valor
      @sprite.visible = valor unless disposed?
    end

    def x;      disposed? ? 0 : @sprite.x; end
    def y;      disposed? ? 0 : @sprite.y; end
    def width;  (disposed? || !@sprite.bitmap) ? 0 : @sprite.bitmap.width;  end
    def height; (disposed? || !@sprite.bitmap) ? 0 : @sprite.bitmap.height; end

    def x=(valor); @sprite.x = valor unless disposed?; end
    def y=(valor); @sprite.y = valor unless disposed?; end

    # A faixa ja ocupa a largura da tela e se dimensiona sozinha; estes existem
    # so para nao estourar em quem os chama.
    def width=(_valor);  end
    def height=(_valor); end

    def resizeToFit(texto, _maxwidth = -1)
      set_text(texto)
    end

    def resizeHeightToFit(texto, _width = -1)
      set_text(texto)
    end

    def disposed?
      @sprite.nil? || @sprite.disposed?
    end

    def dispose
      return if disposed?
      @sprite.bitmap.dispose rescue nil
      @sprite.dispose rescue nil
      @sprite = nil
    end

    def set_text(text, check: false)
      return if disposed?
      txt = text.to_s
      key = [txt, check ? 1 : 0]
      return if @key == key
      @key  = key
      @text = txt

      w     = Graphics.width
      lines = wrap_lines(txt, w - (MARGIN_X * 2) - (check ? CHECK_SIZE + 10 : 0))
      lines = [""] if lines.empty?
      h     = (lines.length * LINE_H) + (PAD_Y * 2)

      @sprite.bitmap.dispose rescue nil
      bmp = Bitmap.new(w, h)
      @sprite.bitmap = bmp
      apply_font(bmp)

      fade_w = (w * 0.25).to_i
      begin
        bmp.gradient_fill_rect(0, 0, fade_w, h, Color.new(0, 0, 0, 0), Color.new(0, 0, 0, 200), false)
        bmp.fill_rect(fade_w, 0, w - (2 * fade_w), h, Color.new(0, 0, 0, 200))
        bmp.gradient_fill_rect(w - fade_w, 0, fade_w, h, Color.new(0, 0, 0, 200), Color.new(0, 0, 0, 0), false)
      rescue
        bmp.fill_rect(0, 0, w, h, Color.new(0, 0, 0, 180)) rescue nil
      end

      lines.each_with_index do |line, i|
        y = PAD_Y + (i * LINE_H)
        begin
          bmp.font.color = Color.new(0, 0, 0, 200)
          bmp.draw_text(1, y + 1, w, LINE_H, line, 1)
          bmp.font.color = Color.new(255, 255, 255)
          bmp.draw_text(0, y, w, LINE_H, line, 1)
        rescue
        end
      end

      if check
        last  = lines.last.to_s
        lw    = (bmp.text_size(last).width rescue 0)
        cx    = ((w + lw) / 2) + 8
        cy    = PAD_Y + ((lines.length - 1) * LINE_H) + ((LINE_H - CHECK_SIZE) / 2)
        cx    = w - CHECK_SIZE - 4 if cx + CHECK_SIZE > w
        AnilLanRework::CheckIcon.desenhar(bmp, cx, cy, CHECK_SIZE)
      end

      @sprite.x = 0
      @sprite.y = (@anchor == :top) ? 0 : ((Graphics.height - h) / 2)
    rescue
      nil
    end

    private

    def apply_font(bmp)
      bmp.font.name = MessageConfig::FONT_NAME rescue (Font.default_name rescue "Arial")
      bmp.font.size = 20
      bmp.font.bold = true
    rescue
    end

    # Quebra por palavra medindo no proprio font. Sem isto, a lista de 6 Pokemon
    # seguia so para a frente e os ultimos nomes ficavam fora da tela.
    def wrap_lines(text, max_w)
      max_w  = 80 if max_w < 80
      scratch = Bitmap.new(1, 1)
      apply_font(scratch)
      out = []
      text.to_s.split("\n").each do |paragraph|
        atual = ""
        paragraph.split(" ").each do |palavra|
          tentativa = atual.empty? ? palavra : "#{atual} #{palavra}"
          if atual.empty? || (scratch.text_size(tentativa).width rescue 0) <= max_w
            atual = tentativa
          else
            out << atual
            atual = palavra
          end
        end
        out << atual
      end
      out
    rescue
      [text.to_s]
    ensure
      scratch.dispose rescue nil
    end

  end

  module BattleSync
    unless const_defined?(:LAN_PASSIVE_ABILITY_TEXT_SUPPRESSIONS)
      LAN_PASSIVE_ABILITY_TEXT_SUPPRESSIONS = [
        :OVERGROW, :TORRENT, :BLAZE, :SWARM, :SOBRECARGA
      ].freeze
    end

    unless const_defined?(:LAN_ENTRY_SPLASH_SUPPRESSIONS)
      LAN_ENTRY_SPLASH_SUPPRESSIONS = [
        :INTIMIDATE, :ESPANTO, :ILLUMINATE
      ].freeze
    end

    unless const_defined?(:LAN_FUGITIVE_TEXT_FRAGMENTS)
      LAN_FUGITIVE_TEXT_FRAGMENTS = [
        "outros pokemon tambem ganharam pontos de experiencia",
        "outros pokémon também ganharam pontos de experiência",
        "otros pokemon tambien ganaron puntos de experiencia",
        "otros pokémon también ganaron puntos de experiencia"
      ].freeze
    end

    module_function

    def online_battle_scene_sync?(battle = nil)
      ctx = active_context rescue nil
      return false unless ctx

      # COOP: a decisao de suprimir texto/splash tem de ser IDENTICA nos dois
      # clientes durante TODA a batalha. Antes ela era reavaliada a cada mensagem
      # e lia AnilLanRework.connected? + a identidade de ctx.battle. Uma queda
      # momentanea de connected? num lado so, ou ctx.battle ainda nao atribuido,
      # fazia um cliente suprimir a mensagem e o outro nao — e os contadores
      # local_text_step / remote_text_step (sync_message_step) divergiam, o que
      # estoura a espera de texto e da a trava de 30s.
      # Agora e uma flag fixada em activate_context, igual nos dois lados.
      if ctx.mode == :coop
        fixada = ctx.instance_variable_get(:@anil_text_sync_fixed)
        return (fixada == true) unless fixada.nil?
      end

      return false unless AnilLanRework.connected?
      return true if battle.nil? || !ctx.respond_to?(:battle) || ctx.battle.nil?
      ctx.battle.equal?(battle)
    rescue
      false
    end

    def suppress_passive_ability_text?(battle, ability)
      return false unless online_battle_scene_sync?(battle)
      LAN_PASSIVE_ABILITY_TEXT_SUPPRESSIONS.include?(ability.to_sym)
    rescue
      false
    end

    def partner_name
      # 1. Tenta pegar do contexto de batalha ativo
      ctx = active_context rescue nil
      peer_id = ctx ? ctx.partner_id.to_s : nil
      
      # 2. Fallback: Se estivermos esperando um início de coop pendente
      if !peer_id && defined?(@pending_coop_start) && @pending_coop_start
        peer_id = @pending_coop_start["sender_id"].to_s
      end
      
      # 3. Fallback: Busca o parceiro mais próximo no mapa
      if !peer_id
        peer = partner_on_same_map rescue nil
        return peer.name.to_s if peer && !peer.name.to_s.empty?
      end

      peer = AnilLanRework.players[peer_id] rescue nil if peer_id
      return peer.name.to_s if peer && !peer.name.to_s.empty?
      
      _INTL("parceiro")
    end

    def waiting_text(message = nil)
      p_name = partner_name
      return _INTL("Aguardando {1}...", p_name) if message.nil? || message.empty?
      return message.gsub("parceiro", p_name).gsub("jogador", p_name).gsub("outro jogador", p_name)
    end

    def suppress_entry_ability_splash?(battle, ability)
      return false unless online_battle_scene_sync?(battle)
      LAN_ENTRY_SPLASH_SUPPRESSIONS.include?(ability.to_sym)
    rescue
      false
    end

    def text_lead_limit(ctx = nil)
      ctx ||= active_context rescue nil
      return LAN_BATTLE_TEXT_LEAD_LIMIT.to_i unless ctx
      return 0 if [:pvp, :coop].include?(ctx.mode)
      LAN_BATTLE_TEXT_LEAD_LIMIT.to_i
    rescue
      LAN_BATTLE_TEXT_LEAD_LIMIT.to_i
    end

    def send_party_sync(to_id = nil)
      return unless defined?(AnilLanRework::TradeSync)
      AnilLanRework::TradeSync.send_party_sync(to_id)
    rescue => e
      AnilLanRework.log("battle sync send_party_sync forward error #{e.class}: #{e.message}")
    end
  end
end

module AnilLanRework
  module RNG
    # POR QUE ESTA CLASSE TEM DOIS MODOS
    #
    # O modo :legacy (Mersenne Twister via Random.new) tem um restore QUEBRADO e
    # nao ha como conserta-lo: ele reconstroi o estado replayando
    # rand(2_147_483_647) N vezes, onde N = call_count. Mas Random#rand(max) do
    # Ruby usa amostragem por rejeicao — o numero de palavras de 32 bits
    # consumidas depende do max (medido: rand(24) gasta ~2, rand(100) gasta ~1).
    # Replayar tudo com um max fixo nao reproduz o estado. Medicao com padrao
    # realista de batalha: 135 de 168 casos divergem (80,4%), tipicamente com o
    # guest UMA chamada atras do host.
    #
    # Isso e grave porque ctx.rng.restore(...) e chamado em TODO evento espelhado
    # (pbReduceHP mirror, pbRecoverHP mirror, battle_foe_turn). O mecanismo criado
    # para corrigir o RNG era a maior fonte de dessincronizacao de RNG do sistema.
    #
    # O modo :counter usa SplitMix64 indexado pelo contador de chamadas: rand(max)
    # consome EXATAMENTE 1 contador, entao o estado E o par (seed, contador) e o
    # restore fica O(1) e bit-exato. Validado: 168/168 correto, ~3200x mais rapido
    # que o replay, distribuicao sa (desvio 0,41% por decil em 1.000.000 sorteios).
    #
    # :legacy so continua existindo para nao quebrar coop com cliente de proto < 3
    # (ver COOP_RNG_PROTO). Host novo + guest antigo cai no comportamento antigo,
    # que e ruim mas e o de hoje. Detalhes: BRIEFING_COOP_DESYNC.md secao 2.
    class BattleRNG
      MASK64 = 0xFFFFFFFFFFFFFFFF

      GOLDEN  = 0x9E3779B97F4A7C15
      MIX_A   = 0xBF58476D1CE4E5B9
      MIX_B   = 0x94D049BB133111EB

      attr_reader :seed
      attr_reader :call_count
      attr_reader :mode

      def initialize(seed, mode = :legacy)
        @seed = seed.to_i
        @mode = (mode.to_s == "counter") ? :counter : :legacy
        @call_count = 0
        @rng = Random.new(@seed) if @mode == :legacy
      end

      # Troca de modo. So deve ser chamada ANTES do primeiro sorteio da batalha
      # (na negociacao de proto, em set_coop_battle_proto): zera o contador.
      def mode=(value)
        novo = (value.to_s == "counter") ? :counter : :legacy
        return @mode if novo == @mode
        @mode = novo
        @rng = (novo == :legacy) ? Random.new(@seed) : nil
        @call_count = 0
        @mode
      end

      def counter?
        @mode == :counter
      end

      def rand(max = nil)
        @call_count += 1
        return legacy_rand(max) if @mode == :legacy
        counter_rand(max)
      end

      # No modo :counter, "calls" e "counter" carregam o MESMO numero (1 chamada =
      # 1 contador), entao o formato do pacote continua identico ao antigo e um
      # cliente legado que receba isto nao quebra pior do que ja quebrava.
      def snapshot
        {
          "seed"    => @seed,
          "calls"   => @call_count,
          "counter" => @call_count,
          "mode"    => @mode.to_s
        }
      end

      def state
        snapshot
      end

      def restore_state(s)
        if s.is_a?(Hash)
          restore(s)
        elsif s.is_a?(Integer)
          if @mode == :counter
            @seed = s.to_i
            @call_count = 0
          else
            @rng.srand(s)
          end
        end
      end

      def restore(snapshot)
        return unless snapshot.is_a?(Hash)
        @seed = snapshot["seed"].to_i
        alvo = (snapshot.key?("counter") ? snapshot["counter"] : snapshot["calls"]).to_i
        alvo = 0 if alvo < 0

        if @mode == :counter
          # O estado E (seed, contador). Restaurar e so atribuir.
          @call_count = alvo
          return
        end

        # Legado: replay aproximado. Sabidamente incorreto (ver comentario acima).
        @rng = Random.new(@seed)
        @call_count = 0
        alvo.times do
          @rng.rand(2_147_483_647)
          @call_count += 1
        end
      end

      private

      def legacy_rand(max)
        return @rng.rand if max.nil?
        @rng.rand(max)
      end

      # Mesma superficie de Random#rand: nil -> float [0,1), Integer -> 0...max,
      # Float -> float [0,max), Range -> inteiro no intervalo.
      def counter_rand(max)
        v = splitmix64(@call_count)
        return v.fdiv(1 << 64) if max.nil?
        case max
        when Range
          lo = max.first.to_i
          hi = max.last.to_i
          hi -= 1 if max.exclude_end?
          return lo if hi <= lo
          lo + (v % (hi - lo + 1))
        when Float
          return 0.0 if max <= 0
          v.fdiv(1 << 64) * max
        else
          m = max.to_i
          m <= 0 ? 0 : v % m
        end
      end

      def splitmix64(n)
        z = (@seed + (n * GOLDEN)) & MASK64
        z = ((z ^ (z >> 30)) * MIX_A) & MASK64
        z = ((z ^ (z >> 27)) * MIX_B) & MASK64
        z ^ (z >> 31)
      end
    end
  end
end


module AnilLanRework
  module BattleSync
    Context = Struct.new(:battle_id, :mode, :client_index, :partner_id, :seed, :rng, :rules, :foe_party, :local_party_blob, :local_party_order, :pending_turns, :pending_switches, :pending_actions, :pending_foe_actions, :pending_foe_turns, :pending_hp_events, :pending_status_events, :pending_called_moves, :pending_capture_results, :pending_text_steps, :pending_text_states, :local_text_step, :remote_text_step, :remote_text_packets, :remote_text_states, :battle, :pending_party_refresh, :outbound_party_sync, :pending_forced_switches, :pending_turn_hashes)

    @active_context = nil
    @pending_invite = nil
    @pending_start = nil
    @outgoing_invites = {}
    @pending_coop_invite = nil
    @pending_coop_start = nil
    @battle_responses = {}
    @buffered_actions = {}
    @buffered_foe_actions = {}
    @buffered_foe_turns = {}
    @buffered_hp_events = {}
    @buffered_status_events = {}
    @buffered_called_moves = {}
    @buffered_capture_results = {}
    @buffered_text_steps = {}
    @buffered_text_states = {}
    @buffered_turns = {}
    @buffered_switches = {}
    @buffered_forced_switches = {}
    @buffered_turn_hashes = {}
    @buffered_manual_locks = {}
    @buffered_phase_sync = {}
    @buffered_field_sync = {}
    @active_context_pending_field_syncs = []
    @pvp_party_backup = nil
    @pvp_party_backup_battle_id = nil
    @buffered_battle_seeds = {}
    @buffered_turn_seeds = {}

    class << self
      attr_accessor :active_context
      attr_accessor :pending_invite
      attr_accessor :pending_start
      attr_accessor :outgoing_invites
      attr_accessor :pending_coop_invite
      attr_accessor :pending_coop_start
    end

    module_function

    def queue_battle_seed(packet)
      return unless packet.is_a?(Hash)
      battle_id = packet["battle_id"].to_s
      @buffered_battle_seeds[battle_id] = packet["seed"].to_i
    end

    def queue_turn_seed(packet)
      return unless packet.is_a?(Hash)
      battle_id = packet["battle_id"].to_s
      turn = packet["turn"].to_i
      (@buffered_turn_seeds[battle_id] ||= {})[turn] = packet["seed"].to_i
    end

    def wait_for_battle_seed(battle_id, timeout = 10.0)
      started = Time.now.to_f
      loop do
        if @buffered_battle_seeds.key?(battle_id.to_s)
          return @buffered_battle_seeds.delete(battle_id.to_s)
        end
        return nil unless AnilLanRework.connected?
        return nil if Time.now.to_f - started >= timeout
        pump_network
        Graphics.update rescue nil
        Input.update rescue nil
      end
    end

    def wait_for_turn_seed(battle_id, turn, timeout = 10.0)
      started = Time.now.to_f
      loop do
        if @buffered_turn_seeds[battle_id.to_s] && @buffered_turn_seeds[battle_id.to_s].key?(turn.to_i)
          return @buffered_turn_seeds[battle_id.to_s].delete(turn.to_i)
        end
        return nil unless AnilLanRework.connected?
        return nil if Time.now.to_f - started >= timeout
        pump_network
        Graphics.update rescue nil
        Input.update rescue nil
      end
    end

    def build_battle_id(prefix)
      "#{prefix}-#{AnilLanRework.self_internal_id}-#{Graphics.frame_count}"
    end

    def activate_context(battle_id:, mode:, client_index:, partner_id:, seed:, rules:, foe_party: nil, local_party_blob: nil, local_party_order: nil)
      ctx = Context.new
      ctx.battle_id = battle_id.to_s
      ctx.mode = mode.to_sym
      ctx.client_index = client_index.to_i
      ctx.partner_id = partner_id.to_s
      ctx.seed = seed.to_i
      ctx.rng = AnilLanRework::RNG::BattleRNG.new(seed.to_i)
      ctx.rules = rules || {}
      ctx.foe_party = foe_party
      ctx.local_party_blob = Array(local_party_blob)
      ctx.local_party_order = sanitize_party_order(local_party_order || normalize_duel_rules(ctx.rules)["local_party_order"])
      ctx.pending_turns = (@buffered_turns.delete(ctx.battle_id) || [])
      ctx.pending_switches = (@buffered_switches.delete(ctx.battle_id) || [])
      ctx.pending_actions = (@buffered_actions.delete(ctx.battle_id) || [])
      ctx.pending_foe_actions = (@buffered_foe_actions.delete(ctx.battle_id) || [])
      ctx.pending_foe_turns = (@buffered_foe_turns.delete(ctx.battle_id) || [])
      ctx.pending_hp_events = (@buffered_hp_events.delete(ctx.battle_id) || [])
      ctx.pending_status_events = (@buffered_status_events.delete(ctx.battle_id) || [])
      ctx.pending_called_moves = (@buffered_called_moves.delete(ctx.battle_id) || [])
      ctx.pending_capture_results = (@buffered_capture_results.delete(ctx.battle_id) || [])
      ctx.pending_text_steps = (@buffered_text_steps.delete(ctx.battle_id) || [])
      ctx.pending_text_states = (@buffered_text_states.delete(ctx.battle_id) || [])
      ctx.pending_forced_switches = (@buffered_forced_switches.delete(ctx.battle_id) || [])
      ctx.pending_turn_hashes = (@buffered_turn_hashes.delete(ctx.battle_id) || [])
      ctx.local_text_step = 0
      ctx.remote_text_step = 0
      ctx.remote_text_packets = {}
      ctx.remote_text_states = {}
      ctx.battle = nil
      ctx.pending_party_refresh = false
      ctx.outbound_party_sync = nil
      ctx.instance_variable_set(:@anil_manual_lock_depth, 0)
      ctx.instance_variable_set(:@anil_remote_manual_lock, false)
      ctx.instance_variable_set(:@anil_remote_manual_reason, nil)
      ctx.instance_variable_set(:@anil_remote_manual_unlock_required, false)
      # Fixa a decisao de supressao de texto para toda a batalha (ver
      # online_battle_scene_sync?). Os dois clientes chegam aqui em coop e
      # conectados, entao a flag e identica nos dois lados.
      ctx.instance_variable_set(:@anil_text_sync_fixed, (ctx.mode == :coop) ? true : nil)
      ctx.instance_variable_set(:@anil_local_coop_eliminated, false)
      ctx.instance_variable_set(:@anil_local_coop_watch_until_end, false)
      ctx.instance_variable_set(:@anil_remote_coop_eliminated, false)
      ctx.instance_variable_set(:@anil_remote_coop_watch_until_end, false)
      ctx.instance_variable_set(:@anil_pending_phase_sync, (@buffered_phase_sync.delete(ctx.battle_id) || []))
      ctx.instance_variable_set(:@anil_command_ready_turn, nil)
      buffered_manual_lock = @buffered_manual_locks.delete(ctx.battle_id)
      apply_remote_manual_lock_packet(buffered_manual_lock, ctx) if buffered_manual_lock
      @buffered_manual_locks.delete_if { |k, _| k != ctx.battle_id }
      consume_remote_text_steps(ctx)
      consume_remote_text_states(ctx)
      @pending_hp_syncs = {}
      @pvp_hp_sync_out_seq = {}
      @pvp_hp_sync_applied = {}
      @active_context_pending_field_syncs = (@buffered_field_sync.delete(ctx.battle_id) || [])
      @active_context = ctx
    end

    # ESTADO DE BOSS: emprestado durante a batalha, devolvido no fim.
    #
    # Ao entrar numa batalha coop, o convidado espelha o estado de boss do
    # anfitriao escrevendo no switch 45 (e no BOSS_BATTLE_SWITCH). Esses switches
    # sao GLOBAIS e vivem no save: escrevia-se e nunca se repunha.
    #
    # Bastava UMA batalha coop contra um boss para o switch ficar ligado para
    # sempre — e a partir dai todas as batalhas, coop ou nao, desenhavam a vida
    # do inimigo como boss. O inverso tambem acontecia: entrar num coop normal
    # apagava um estado de boss legitimo.
    #
    # E nao e so cosmetico. O switch 45 e lido para decidir comportamento de
    # batalha (ver ~9056) e o estado de boss mexe em HP e imunidades. Com um
    # cliente a achar que e boss e o outro nao, os dois calculam dano de forma
    # diferente e a batalha dessincroniza no primeiro golpe.
    def guardar_switches_de_boss!
      return unless $game_switches
      return if @switches_de_boss_guardados   # nao sobrepor um emprestimo em curso
      @switches_de_boss_guardados = { 45 => $game_switches[45] }
      if defined?(BossBattleConstants)
        chave = BossBattleConstants::BOSS_BATTLE_SWITCH
        @switches_de_boss_guardados[chave] = $game_switches[chave]
      end
    rescue
      @switches_de_boss_guardados = nil
    end

    def restaurar_switches_de_boss!
      guardados = @switches_de_boss_guardados
      @switches_de_boss_guardados = nil
      return unless $game_switches
      if guardados
        guardados.each { |chave, valor| $game_switches[chave] = valor }
        AnilLanRework.log("boss switches repostos: #{guardados.inspect}") rescue nil
        return
      end

      # REDE DE SEGURANCA: contexto de coop a fechar SEM emprestimo registado.
      #
      # Significa que alguem escreveu no switch sem passar pelo guardar_ (era o
      # caso do 030, caminho de revanche), ou que o guardar_ nem chegou a correr
      # porque a batalha rebentou antes. Em qualquer dos casos nao ha valor
      # anterior para repor — e como NADA no jogo liga o switch 45 (varrido:
      # zero escritas e zero leituras nos mapas e nos common events; os bosses a
      # serio sao marcados por $game_temp.battle_rules), o switch ligado aqui so
      # pode ser lixo do coop. Desligar e a reposicao correta.
      return unless ($game_switches[45] rescue false)
      $game_switches[45] = false rescue nil
      if defined?(BossBattleConstants)
        $game_switches[BossBattleConstants::BOSS_BATTLE_SWITCH] = false rescue nil
      end
      AnilLanRework.log("boss switch 45 estava ligado sem emprestimo registado — desligado") rescue nil
    rescue
    end

    def clear_context
      restore_local_pvp_party!("clear_context")
      @pending_hp_syncs = {}
      @pvp_hp_sync_out_seq = {}
      @pvp_hp_sync_applied = {}
      clear_pending_coop_start_wait_window
      @active_context_pending_field_syncs = []
      clear_coop_turn_state! rescue nil   # nao deixa lote de turno vazar para a proxima batalha
      clear_coop_v3_state! rescue nil     # idem para ordem de turno e hash (124_Coop_Determinismo_V3)
      # Sem isto a decisao de lockstep de uma batalha valia para a seguinte —
      # inclusive para uma que comecasse com um parceiro que nao a acordou.
      limpar_coop_lockstep! rescue nil
      restaurar_switches_de_boss! rescue nil  # idem para o estado de boss (switch 45)
      @active_context = nil
      sanitize_injected_partner_state!("clear_context")
    end

    def receive_battle_end(packet)
      ctx = @active_context
      if ctx
        ctx.instance_variable_set(:@anil_battle_end_received, true)
        result = packet["result"].to_i
        result = 2 if result == 0
        ctx.instance_variable_set(:@anil_battle_end_result, result)
        AnilLanRework.log("coop spectator received battle_end result=#{result}")
      end
    end

    def is_story_partner?(partner)
      return false unless partner
      return true if partner[4] == false
      type = partner[0]
      return false unless type
      type_sym = type.to_sym rescue nil
      type_str = type.to_s.upcase
      story_types = ["CHERYL", "RILEY", "BUCK", "MARLEY", "MIRA", "MALTA", "QUINOA", "SONIA", "SIRA"]
      return true if story_types.include?(type_str)
      return true if type_sym && [:CHERYL, :RILEY, :BUCK, :MARLEY, :MIRA].include?(type_sym)
      
      # Companheiros de Quest do Life System
      quest_names = ["Ben", "Lucrecia", "Guido", "Angelito", "Amara"]
      return true if partner[1] && quest_names.include?(partner[1])
      quest_types = ["CHICO", "CHICA", "PESCADOR", "CAMPISTO", "CAMPISTA"]
      return true if quest_types.include?(type_str)
      return true if type_sym && [:CHICO, :CHICA, :PESCADOR, :CAMPISTO, :CAMPISTA].include?(type_sym)
      
      false
    end

    def sanitize_injected_partner_state!(reason = nil)
      has_mp_partner = false
      if defined?($PokemonGlobal) && $PokemonGlobal.partner
        if $PokemonGlobal.partner[4] == true || @partner_injected || !is_story_partner?($PokemonGlobal.partner)
          has_mp_partner = true
        end
      end
      return unless has_mp_partner
      return if @active_context && @active_context.mode == :coop
      return if $game_temp&.in_battle
      AnilLanRework.log("remove stale injected partner reason=#{reason}") if reason
      remove_partner
    rescue => e
      AnilLanRework.log("sanitize_injected_partner_state error #{e.class}: #{e.message}")
      @partner_injected = false
    end

    def remote_partner_name
      return "o outro jogador" unless @active_context
      peer = AnilLanRework.players[@active_context.partner_id.to_s]
      name = peer&.name.to_s
      return name unless name.empty?

      # ⚠️ NAO devolver o partner_id como nome.
      #
      # Era o que estava aqui, e aparecia em jogo como "Aguardando
      # wallace-adm100..." — o ID interno, com o sufixo e tudo, no meio de uma
      # faixa de batalha. Alem de feio, expoe o identificador da conta a outro
      # jogador, e esse sufixo e metade do que se precisa para o recuperar
      # partida.
      #
      # E chegar aqui tem um significado proprio: o peer nao esta na lista de
      # jogadores, ou seja, o servidor ja nao o ve. Quem le "o outro jogador"
      # nesta faixa esta, na pratica, a olhar para alguem que caiu.
      "o outro jogador"
    rescue
      "o outro jogador"
    end

    # REVERTIDO 2026-07-31 para o comportamento original.
    #
    # Tinha sido acrescentado (a) um atraso de 2s por visibilidade e (b) uma
    # guarda de "uma faixa de cada vez". Em jogo o resultado foi NENHUM aviso
    # aparecer — pior do que os problemas que iam resolver. A causa exata nao
    # ficou identificada; sem poder testar em jogo, reverter e o certo.
    #
    # Os metodos revelar_apos/verificar_revelacao ficam na WaitBanner, inertes:
    # ninguem os chama. Servem de base para retomar isto com margem para testar.
    def build_wait_window(waiting_text)
      return [nil, nil] if waiting_text.to_s.empty?
      viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
      viewport.z = 99_999
      [viewport, AnilLanRework::WaitBanner.new(viewport, waiting_text)]
    rescue
      [nil, nil]
    end

    # Reaplica o texto quando ele muda no meio da espera (ex.: exp_phase ->
    # level_up). A faixa se redimensiona e recentra sozinha; o ramo antigo fica
    # para o caso de alguem ainda passar uma Window de verdade aqui.
    def center_wait_window!(window, text)
      return unless window
      if window.respond_to?(:set_text)
        window.set_text(text)
        return
      end
      window.resizeToFit(text.to_s, Graphics.width) rescue nil
      window.x = (Graphics.width - window.width) / 2
      window.y = (Graphics.height - window.height) / 2
    rescue
    end

    # Espera VISIVEL por uma resposta de convite, com a rede viva.
    #
    # O PvP customizado ja fazia isso (pvp_wait_with_window, no 110) e era o
    # unico: troca e convite de grupo disparavam o pacote e devolviam o controle
    # na hora, entao quem convidava ficava sem saber se o outro tinha recebido,
    # recusado ou simplesmente sumido.
    #
    # Devolve :done se o bloco virou verdadeiro, :timeout se estourou o tempo e
    # :desconectado se a conexao caiu no meio.
    #
    # O bloco e avaliado a cada frame, entao tem de ser barato — apenas ler o
    # estado que o handler do pacote de resposta ja atualiza.
    # Verdadeiro enquanto a faixa de "aguardando resposta" esta na tela.
    #
    # Os handlers dos pacotes de resposta rodam DENTRO deste laco (via
    # pump_network), e alguns chamam pbMessage. Como a faixa e desenhada com z
    # 100_001, o dialogo apareceria ATRAS dela. Quem consulta isto adia a
    # mensagem, e quem convidou a exibe depois que a faixa sai.
    def aguardando_convite?
      @aguardando_convite == true
    end

    # ⚠️ DA PARA DESISTIR COM O X.
    #
    # Antes so havia duas saidas: o outro responder, ou o timeout. Quem
    # convidasse alguem que estava a jogar de costas ficava preso o minuto
    # inteiro a olhar para a faixa. O X devolve o controlo na hora.
    #
    # O aviso vai na propria faixa: uma tecla que nao se anuncia nao existe.
    def aguardar_resposta_convite(texto, timeout = 60.0)
      texto_com_dica = "#{texto}\n" + AnilLanRework.ui_format("(X para cancelar)")
      viewport, window = build_wait_window(texto_com_dica)
      @aguardando_convite = true
      inicio = Time.now.to_f
      resultado = :timeout
      begin
        loop do
          Graphics.update rescue nil
          Input.update rescue nil
          pump_network rescue nil
          AnilLanRework.suppress_peer_interaction!(20)
          if yield
            resultado = :done
            break
          end
          # Depois do yield, de proposito: se a resposta chegou NESTE frame, ela
          # ganha ao X. Cancelar um convite que ja foi aceite deixava os dois
          # lados a discordar sobre o que aconteceu.
          if (Input.trigger?(Input::BACK) rescue false)
            resultado = :cancelado
            break
          end
          break if Time.now.to_f - inicio > timeout
          unless AnilLanRework.connected?
            resultado = :desconectado
            break
          end
        end
      ensure
        @aguardando_convite = false
        dispose_wait_window(viewport, window)
      end
      resultado
    rescue => e
      @aguardando_convite = false
      AnilLanRework.log("aguardar_resposta_convite erro: #{e.class}: #{e.message}") rescue nil
      :timeout
    end

    def dispose_wait_window(viewport, window)
      window.dispose rescue nil
      viewport.dispose rescue nil
    end

    def clear_pending_coop_start_wait_window
      dispose_wait_window(@pending_coop_start_wait_viewport, @pending_coop_start_wait_window)
      @pending_coop_start_wait_viewport = nil
      @pending_coop_start_wait_window = nil
    end

    def mark_coop_wild_start_pending(battle_id = nil)
      @coop_wild_start_pending_battle_id = battle_id.to_s
    rescue
      @coop_wild_start_pending_battle_id = battle_id
    end

    def coop_wild_start_pending?(battle_id = nil)
      pending = @coop_wild_start_pending_battle_id.to_s
      return false if pending.empty?
      return true if battle_id.nil?
      pending == battle_id.to_s
    rescue
      false
    end

    def clear_coop_wild_start_pending
      @coop_wild_start_pending_battle_id = nil
    end

    def ensure_pending_coop_start_wait_window(waiting_text)
      return clear_pending_coop_start_wait_window if waiting_text.to_s.empty?
      window_missing = !@pending_coop_start_wait_window || (@pending_coop_start_wait_window.disposed? rescue true)
      if window_missing
        @pending_coop_start_wait_viewport, @pending_coop_start_wait_window = build_wait_window(waiting_text)
      else
        @pending_coop_start_wait_window.text = waiting_text rescue nil
      end
      @pending_coop_start_wait_window.update rescue nil
      @pending_coop_start_wait_window
    end

    def waiting_for_coop_start?
      return false unless @pending_coop_start
      sender_id = @pending_coop_start["sender_id"].to_s
      peer = AnilLanRework.players[sender_id]
      return false unless peer
      peer.battle_busy != true
    rescue
      false
    end


    def local_coop_eliminated?(ctx = nil)
      ctx ||= @active_context
      return false unless ctx && ctx.mode == :coop
      return true if ctx.instance_variable_get(:@anil_local_coop_eliminated) == true
      
      # Verificação local robusta: se todos os Pokémon do slot local estão desmaiados
      battle = ctx.battle
      if battle
        local_slot, remote_slot = coop_slots_for(battle) rescue [nil, nil]
        if local_slot
          has_able = false
          battle.eachInTeamFromBattlerIndex(local_slot) do |pkmn, i|
            has_able = true if pkmn && pkmn.able?
          end
          return true unless has_able
        end
      end
      false
    rescue
      false
    end

    def local_coop_watch_until_end?(ctx = nil)
      ctx ||= @active_context
      return false unless ctx && ctx.mode == :coop
      ctx.instance_variable_get(:@anil_local_coop_watch_until_end) == true
    rescue
      false
    end

    def remote_coop_eliminated?(ctx = nil)
      ctx ||= @active_context
      return false unless ctx && ctx.mode == :coop
      return true if ctx.instance_variable_get(:@anil_remote_coop_eliminated) == true
      
      # Verificação local robusta: se todos os Pokémon do slot remoto estão desmaiados
      battle = ctx.battle
      if battle
        local_slot, remote_slot = coop_slots_for(battle) rescue [nil, nil]
        if remote_slot
          has_able = false
          battle.eachInTeamFromBattlerIndex(remote_slot) do |pkmn, i|
            has_able = true if pkmn && pkmn.able?
          end
          return true unless has_able
        end
      end
      false
    rescue
      false
    end

    def remote_coop_watch_until_end?(ctx = nil)
      ctx ||= @active_context
      return false unless ctx && ctx.mode == :coop
      ctx.instance_variable_get(:@anil_remote_coop_watch_until_end) == true
    rescue
      false
    end

    def local_coop_eliminated_marked?(ctx = nil)
      ctx ||= @active_context
      ctx && ctx.mode == :coop && ctx.instance_variable_get(:@anil_local_coop_eliminated) == true
    rescue
      false
    end

    def remote_coop_eliminated_marked?(ctx = nil)
      ctx ||= @active_context
      ctx && ctx.mode == :coop && ctx.instance_variable_get(:@anil_remote_coop_eliminated) == true
    rescue
      false
    end

    def coop_remote_sync_disabled?(ctx = nil)
      ctx ||= @active_context
      return false unless ctx && ctx.mode == :coop
      remote_coop_eliminated_marked?(ctx) && !remote_coop_watch_until_end?(ctx)
    rescue
      false
    end



    def current_party_sync_snapshot(ctx = nil)
      ctx ||= @active_context
      return [] unless ctx && [:pvp, :coop].include?(ctx.mode)
      local_party = if ctx.mode == :pvp
        active_pvp_party(ctx)
      else
        $player.party
      end
      AnilLanRework::Serializer.serialize_party(local_party)
    rescue => e
      AnilLanRework.log("current_party_sync_snapshot error #{e.class}: #{e.message}")
      []
    end

    def queue_outbound_party_sync_if_changed(before_snapshot, reason = nil, ctx = nil)
      ctx ||= @active_context
      return false unless ctx && [:pvp, :coop].include?(ctx.mode)
      after_snapshot = current_party_sync_snapshot(ctx)
      return false if before_snapshot == after_snapshot
      queue_outbound_party_sync
      AnilLanRework.log(
        "manual lock party sync queued battle_id=#{ctx.battle_id} reason=#{reason || 'none'} size=#{Array(after_snapshot).length}"
      )
      true
    rescue => e
      AnilLanRework.log("queue_outbound_party_sync_if_changed error #{e.class}: #{e.message}")
      false
    end



    def wait_text_for_remote_turn
      AnilLanRework.ui_format("Aguardando {1} escolher...", remote_partner_name)
    end

    def wait_text_for_remote_switch
      AnilLanRework.ui_format("Aguardando {1} trocar...", remote_partner_name)
    end

    def send_phase_sync(phase, state = "ready", extra = {})
      ctx = @active_context
      return unless ctx && [:pvp, :coop].include?(ctx.mode) && AnilLanRework.connected?
      payload = {
        "to_id"     => ctx.partner_id,
        "battle_id" => ctx.battle_id,
        "phase"     => phase.to_s,
        "state"     => state.to_s
      }
      extra.each { |key, value| payload[key.to_s] = value } if extra.is_a?(Hash)
      AnilLanRework.connection.send_packet("battle_phase_sync", payload)
      AnilLanRework.log(
        "battle phase sync send battle_id=#{ctx.battle_id} phase=#{phase} state=#{state} extra=#{extra.inspect}"
      )
    rescue => e
      AnilLanRework.log("battle phase sync send error #{e.class}: #{e.message}")
    end

    def queue_remote_phase_sync(packet)
      return unless packet.is_a?(Hash)
      battle_id = packet["battle_id"].to_s
      if packet["phase"].to_s == "manual_unlock_done" && @active_context && @active_context.battle_id == battle_id
        @active_context.instance_variable_set(:@anil_remote_manual_unlock_required, false)
      end
      AnilLanRework.log(
        "battle phase sync recv battle_id=#{battle_id} phase=#{packet['phase']} state=#{packet['state']} turn=#{packet['turn'].inspect} unlock_required=#{@active_context && @active_context.battle_id == battle_id ? (@active_context.instance_variable_get(:@anil_remote_manual_unlock_required) == true) : 'buffered'}"
      )
      if @active_context && @active_context.battle_id == battle_id
        pending = @active_context.instance_variable_get(:@anil_pending_phase_sync) || []
        pending << packet
        @active_context.instance_variable_set(:@anil_pending_phase_sync, pending)
      else
        (@buffered_phase_sync[battle_id] ||= []) << packet
      end
    rescue => e
      AnilLanRework.log("battle phase sync queue error #{e.class}: #{e.message}")
    end

    def next_remote_phase_sync(phase = nil, state = nil, turn = nil, ctx = nil)
      ctx ||= @active_context
      return nil unless ctx
      pending = ctx.instance_variable_get(:@anil_pending_phase_sync) || []
      index = pending.index do |packet|
        next false unless packet.is_a?(Hash)
        next false if phase && packet["phase"].to_s != phase.to_s
        next false if state && packet["state"].to_s != state.to_s
        next false if !turn.nil? && packet["turn"].to_i != turn.to_i
        true
      end
      index ? pending.delete_at(index) : nil
    rescue
      nil
    end

    def sync_coop_command_phase_ready(battle, timeout = AnilLanRework::TURN_TIMEOUT)
      ctx = @active_context
      return true unless ctx && ctx.mode == :coop && AnilLanRework.connected? && battle
      return true if coop_remote_sync_disabled?(ctx)
      # Parceiro eliminado (mesmo assistindo) não tem Pokémon para comandar,
      # então nunca vai enviar command_ready. Pular a sincronização.
      return true if remote_coop_eliminated_marked?(ctx) || local_coop_eliminated_marked?(ctx)
      return false if local_manual_lock?(ctx)
      turn = battle.turnCount.to_i rescue 0
      synced_turn = ctx.instance_variable_get(:@anil_command_ready_turn)
      return true if synced_turn.to_i == turn && !synced_turn.nil?
      needs_remote_unlock = ctx.instance_variable_get(:@anil_remote_manual_unlock_required) == true
      if remote_manual_lock?(ctx) || needs_remote_unlock
        wait_text = "Aguardando parceiro terminar..."
        unlock_viewport, unlock_window = build_wait_window(wait_text)
        started = Time.now.to_f
        lock_text = manual_wait_text
        with_battle_wait do
          loop do
            pump_network
            if next_remote_phase_sync("manual_unlock_done", "ready", nil, ctx)
              ctx.instance_variable_set(:@anil_remote_manual_unlock_required, false)
              break
            end
            break unless AnilLanRework.connected?
            locked = remote_manual_lock?(ctx)
            if locked
              started = Time.now.to_f
              unlock_window.text = lock_text if unlock_window
            elsif unlock_window && unlock_window.text.to_s != wait_text
              unlock_window.text = wait_text
            end
            if timeout && timeout > 0 && (Time.now.to_f - started) >= timeout.to_f
              AnilLanRework.log(
                "battle phase sync manual unlock timeout battle_id=#{ctx.battle_id} turn=#{turn} remote_lock=#{locked} unlock_required=#{ctx.instance_variable_get(:@anil_remote_manual_unlock_required) == true}"
              )
              return false
            end
            Graphics.update rescue nil
            Input.update rescue nil
            unlock_window.update rescue nil
          end
        end
        dispose_wait_window(unlock_viewport, unlock_window)
      end
      send_phase_sync("command_ready", "ready", "turn" => turn)
      ready_text = wait_text_for_remote_turn
      ready_viewport, ready_window = build_wait_window(ready_text)
      started = Time.now.to_f
      with_battle_wait do
        loop do
          pump_network
          packet = next_remote_phase_sync("command_ready", "ready", turn, ctx)
          if packet
            ctx.instance_variable_set(:@anil_command_ready_turn, turn)
            return true
          end
          return false unless AnilLanRework.connected?
          locked = remote_manual_lock?(ctx)
          if locked
            started = Time.now.to_f
            ready_window.text = lock_text if ready_window
          elsif ready_window && ready_window.text.to_s != ready_text
            ready_window.text = ready_text
          end
          return false if timeout && timeout > 0 && (Time.now.to_f - started) >= timeout.to_f
          Graphics.update rescue nil
          Input.update rescue nil
          ready_window.update rescue nil
        end
      end
    ensure
      dispose_wait_window(ready_viewport, ready_window)
    end

    def wait_text_for_turn_hash
      _INTL("Verificando sincronizacao do turno...")
    end

    def pump_network
      return unless AnilLanRework.connected?
      AnilLanRework.connection.tick
      AnilLanRework.connection.drain { |packet| AnilLanRework::Router.route_packet(packet) }
      consume_remote_text_steps
      consume_remote_text_states
      flush_remote_status_events
    end

    def normalize_duel_rules(rules)
      out = {}
      return out unless rules.is_a?(Hash)
      rules.each { |key, value| out[key.to_s] = value }
      out
    end

    def sanitize_party_order(order, source_party = nil)
      source_party = Array(source_party)
      source_party = Array($player&.party) if source_party.empty?
      max_index = source_party.length - 1
      Array(order).map { |index| index.to_i }.select { |index| index >= 0 && index <= max_index }.uniq
    end

    def party_from_order(order, source_party = nil)
      source_party = Array(source_party)
      source_party = Array($player&.party) if source_party.empty?
      sanitize_party_order(order, source_party).map { |index| source_party[index] }.compact
    end

    def party_order_from_party(party, source_party = nil)
      source_party = Array(source_party)
      source_party = Array($player&.party) if source_party.empty?
      used = []
      Array(party).each_with_object([]) do |pkmn, order|
        index = source_party.each_index.find { |i| !used.include?(i) && source_party[i].equal?(pkmn) }
        if index.nil?
          target_blob = AnilLanRework::Serializer.serialize_pokemon(pkmn)
          index = source_party.each_index.find do |i|
            next false if used.include?(i)
            AnilLanRework::Serializer.serialize_pokemon(source_party[i]) == target_blob
          end
        end
        next if index.nil?
        used << index
        order << index
      end
    rescue
      []
    end

    def party_from_blob(blob, source_party = nil)
      source_party = Array(source_party)
      source_party = Array($player&.party) if source_party.empty?
      used = []
      Array(blob).each_with_object([]) do |pkmn_blob, party|
        index = source_party.each_index.find do |i|
          next false if used.include?(i)
          AnilLanRework::Serializer.serialize_pokemon(source_party[i]) == pkmn_blob
        end
        next if index.nil?
        used << index
        party << source_party[index]
      end
    rescue
      []
    end

    def party_species_names(party)
      Array(party).map do |pkmn|
        next nil unless pkmn
        begin
          if pkmn.respond_to?(:speciesName) && !pkmn.speciesName.to_s.empty?
            pkmn.speciesName.to_s
          elsif pkmn.respond_to?(:name) && !pkmn.name.to_s.empty?
            pkmn.name.to_s
          elsif pkmn.respond_to?(:species)
            pkmn.species.to_s
          end
        rescue
          nil
        end
      end.compact
    end

    def selected_pvp_party(ctx)
      return [] unless ctx && ctx.mode == :pvp
      selected = party_from_order(ctx.local_party_order)
      selected = party_from_blob(ctx.local_party_blob) if selected.empty?
      selected = AnilLanRework::Serializer.deserialize_party(ctx.local_party_blob) if selected.empty?
      if selected.empty? && custom_duel_rules?(ctx.rules)
        selected = party_from_order(normalize_duel_rules(ctx.rules)["local_party_order"])
      end
      selected
    rescue
      []
    end

    def active_pvp_party(ctx)
      selected = selected_pvp_party(ctx)
      return selected unless selected.empty?
      battle = ctx&.battle
      return [] unless battle
      idx_start, idx_end = battle.pbTeamIndexRangeFromBattlerIndex(0)
      Array(battle.pbParty(0))[idx_start...idx_end].compact
    rescue
      []
    end

    def pvp_party_index_allowed?(battle, idx_battler, idx_party)
      return false unless battle
      idx_party = idx_party.to_i
      idx_start, idx_end = battle.pbTeamIndexRangeFromBattlerIndex(idx_battler)
      idx_party >= idx_start && idx_party < idx_end
    rescue
      false
    end

    def duel_size_for_style(style)
      case style.to_s.downcase
      when "double", "2v2" then 2
      when "triple", "3v3" then 3
      else 1
      end
    end

    def duel_style_from_rules(rules, size = nil)
      normalized = normalize_duel_rules(rules)
      style = normalized["style"].to_s.downcase
      style = case size.to_i
              when 2 then "double"
              when 3 then "triple"
              else "single"
              end if style.empty?
      case style
      when "double", "2v2" then "double"
      when "triple", "3v3" then "triple"
      else "single"
      end
    end

    def duel_style_label(style)
      case duel_style_from_rules({ "style" => style })
      when "double" then "Batalha Dupla"
      when "triple" then "Batalha Tripla"
      else "Batalha Individual"
      end
    end

    def custom_duel_rules?(rules)
      normalized = normalize_duel_rules(rules)
      normalized["custom_pvp"] == true || normalized["custom_pvp"].to_s.downcase == "true"
    end

    def public_duel_rules(rules)
      sanitized = normalize_duel_rules(rules)
      sanitized.delete("local_party_order")
      sanitized
    end

    def build_preview_trainer(trainer_name)
      trainer_type = begin
        if defined?($player) && $player && $player.respond_to?(:online_trainer_type) && $player.online_trainer_type
          $player.online_trainer_type
        else
          GameData::TrainerType.keys.first
        end
      rescue
        GameData::TrainerType.keys.first
      end
      name = trainer_name.to_s.strip
      name = "Rival" if name.empty?
      begin
        NPCTrainer.new(name, trainer_type)
      rescue
        Trainer.new(name, trainer_type)
      end
    end

    def wait_for_party(peer, timeout = 1.0)
      return true if peer.party_blob && !peer.party_blob.empty?
      return false unless AnilLanRework.connected?
      AnilLanRework.connection.send_packet("party_request", "to_id" => peer.internal_id)
      start = Time.now.to_f
      while Time.now.to_f - start < timeout
        AnilLanRework::BattleSync.pump_network rescue nil
        return true if peer.party_blob && !peer.party_blob.empty?
        Graphics.update rescue nil
        sleep(0.01)
      end
      false
    end

    def build_custom_duel_online_rules(style, team_size = nil)
      rules = PokemonOnlineRules.new
      exact_team_size = team_size.to_i
      if exact_team_size > 0
        rules.setNumberRange(exact_team_size, exact_team_size)
      else
        rules.setNumberRange(1, 6)
      end
      rules.addPokemonRule(NonEggRestriction) if defined?(NonEggRestriction)
      case duel_style_from_rules({ "style" => style })
      when "double"
        rules.addBattleRule(DoubleBattle) if defined?(DoubleBattle)
      when "triple"
        rules.addBattleRule(TripleBattle) if defined?(TripleBattle)
      end
      rules.setTeamPreview(30)
      rules
    end

    def choose_custom_duel_party(style:, opponent_name:, opponent_party:, team_size: nil)
      battle_rules = build_custom_duel_online_rules(style, team_size)
      local_party = Array($player&.party)
      return nil if local_party.empty?
      unless battle_rules.ruleset.hasRegistrableTeam?(local_party)
        pbMessage(_INTL("Nao tens uma equipe Pokemon valida para esse PvP.")) rescue nil
        return nil
      end
      foe_party = Array(opponent_party)
      if battle_rules.team_preview? && !foe_party.empty?
        CableClub_Scene.new.pbTeamPreview(build_preview_trainer(opponent_name), foe_party, battle_rules.team_preview)
      end
      team_order = CableClub.choose_team(battle_rules.ruleset)
      return nil if !team_order || team_order.empty?
      selected_party = party_from_order(team_order, local_party)
      return nil if selected_party.empty?
      [team_order, selected_party]
    end

    def prompt_custom_duel_response_sized(rules, opponent_name, opponent_party, max_size)
      normalized = normalize_duel_rules(rules)
      selection = choose_custom_duel_party_sized(
        style: normalized["style"],
        opponent_name: opponent_name,
        opponent_party: opponent_party,
        max_size: max_size
      )
      return nil unless selection
      order, local_party = selection
      normalized["local_party_order"] = order
      [normalized, local_party]
    end

    def choose_custom_duel_party_sized(style:, opponent_name:, opponent_party:, max_size: 6)
      battle_rules = build_custom_duel_online_rules_sized(style, max_size)
      local_party = Array($player&.party)
      return nil if local_party.empty?
      unless battle_rules.ruleset.hasRegistrableTeam?(local_party)
        pbMessage(_INTL("Nao tens uma equipe Pokemon valida para esse PvP.")) rescue nil
        return nil
      end
      foe_party = Array(opponent_party)
      if battle_rules.team_preview? && !foe_party.empty?
        CableClub_Scene.new.pbTeamPreview(build_preview_trainer(opponent_name), foe_party, battle_rules.team_preview)
      end
      team_order = CableClub.choose_team(battle_rules.ruleset)
      return nil if !team_order || team_order.empty?
      selected_party = party_from_order(team_order, local_party)
      return nil if selected_party.empty?
      [team_order, selected_party]
    end

    def build_custom_duel_online_rules_sized(style, max_size)
      n = [[max_size.to_i, 1].max, 6].min
      rules = PokemonOnlineRules.new
      rules.setNumberRange(n, n)
      rules.addPokemonRule(NonEggRestriction) if defined?(NonEggRestriction)
      case duel_style_from_rules({ "style" => style })
      when "double"
        rules.addBattleRule(DoubleBattle) if defined?(DoubleBattle)
      when "triple"
        rules.addBattleRule(TripleBattle) if defined?(TripleBattle)
      end
      rules.setTeamPreview(30)
      rules
    end

    def prompt_custom_duel_style
      commands = [_INTL("Batalha Individual"), _INTL("Batalha Dupla"), _INTL("Cancelar")]
      command = pbMessage(_INTL("Escolhe o formato do PvP customizado."), commands, commands.length)
      return nil if command < 0 || command >= commands.length - 1
      case command
      when 1 then "double"
      else "single"
      end
    end

    def prompt_custom_duel_setup(peer)
      style = prompt_custom_duel_style
      return nil unless style
      wait_for_party(peer, 0.8)
      selection = choose_custom_duel_party(
        style: style,
        opponent_name: peer&.name.to_s,
        opponent_party: AnilLanRework::Serializer.deserialize_party(peer&.party_blob)
      )
      return nil unless selection
      order, local_party = selection
      [
        {
          "style"            => style,
          "custom_pvp"       => true,
          "selected_party_size" => local_party.length,
          "local_party_order" => order
        },
        local_party
      ]
    end

    def prompt_custom_duel_response(rules, opponent_name, opponent_party, team_size: nil)
      normalized = normalize_duel_rules(rules)
      selection = choose_custom_duel_party(
        style: normalized["style"],
        opponent_name: opponent_name,
        opponent_party: opponent_party,
        team_size: team_size
      )
      return nil unless selection
      order, local_party = selection
      normalized["selected_party_size"] = local_party.length
      normalized["local_party_order"] = order
      [normalized, local_party]
    end

    def duel_invite_message(sender_name, size, rules)
      normalized = normalize_duel_rules(rules)
      if custom_duel_rules?(normalized)
        battle_type = duel_style_label(duel_style_from_rules(normalized, size))
        return AnilLanRework.ui_format("{1} quer um PvP customizado ({2}). Aceitar?", sender_name, battle_type)
      end
      AnilLanRework.ui_format("{1} quer um Duelo {2}v{2}. Aceitar?", sender_name, size)
    end

    # ⚠️ A ESPERA DO CONVITE DE BATALHA E OPCIONAL, E ISSO NAO E PREGUICA.
    #
    # O `request_duel` tambem e chamado pelo TORNEIO (MOD 103), que emparelha
    # gente em cadeia sem ninguem a olhar. Se a espera fosse automatica, o
    # torneio ficava preso 60 segundos por par, com uma faixa no ecra de quem
    # nem sabia que tinha convidado alguem. Por isso quem espera e o caminho
    # INTERACTIVO, que e o unico onde ha um jogador a olhar para o ecra.
    #
    # A condicao le o proprio `@outgoing_invites`: o `receive_accept` e o
    # `receive_decline` apagam a entrada, portanto "ja nao esta la" quer dizer
    # "ja houve resposta", seja ela qual for. Nao ha bandeira nova para manter
    # em sincronia.
    def esperar_resposta_do_duelo!(battle_id, peer)
      return unless battle_id && @outgoing_invites[battle_id]
      nome = peer.respond_to?(:name) ? peer.name.to_s : battle_id.to_s
      resultado = aguardar_resposta_convite(
        AnilLanRework.ui_format("Aguardando resposta de {1}...", nome),
        AnilLanRework::BATTLE_INVITE_TIMEOUT
      ) { @outgoing_invites[battle_id].nil? }

      return if resultado == :done   # aceitou ou recusou; quem trata e o receive_*

      convite = @outgoing_invites[battle_id]
      destino = convite ? convite["to_id"].to_s : (peer.respond_to?(:internal_id) ? peer.internal_id.to_s : "")
      @outgoing_invites.delete(battle_id)

      # ⚠️ AVISA-SE O OUTRO LADO, mesmo sabendo que ele so o le mais tarde.
      #
      # Ele esta dentro de um pbConfirmMessage, que bloqueia o cliente dele — o
      # pacote fica na fila. Mas assim que responder, o `receive_decline` dele
      # corre e a mensagem explica o que aconteceu. Sem isto, ele carregava em
      # "Sim" e ficava a olhar para nada: do nosso lado o convite ja nao existe
      # e o `receive_accept` descarta-o em silencio.
      unless destino.empty?
        AnilLanRework.connection.send_packet("battle_decline",
          "to_id"     => destino,
          "battle_id" => battle_id,
          "reason"    => (resultado == :cancelado) ? "cancelled" : "expired"
        ) rescue nil
      end

      case resultado
      when :cancelado    then pbMessage(_INTL("Você cancelou o convite de batalha.")) rescue nil
      when :desconectado then pbMessage(AnilLanRework.ui_format("A conexão caiu antes de {1} responder.", nome)) rescue nil
      else                    pbMessage(AnilLanRework.ui_format("{1} não respondeu ao convite de batalha.", nome)) rescue nil
      end
    rescue => e
      AnilLanRework.log("esperar_resposta_do_duelo! erro: #{e.class}: #{e.message}") rescue nil
    end

    def request_custom_duel(peer)
      setup = prompt_custom_duel_setup(peer)
      return nil unless setup
      rules, local_party = setup
      return nil if local_party.empty?
      battle_style = duel_style_label(duel_style_from_rules(rules))
      team_size = local_party.length
      if pbConfirmMessage(AnilLanRework.ui_format("Enviar convite de PvP customizado ({1}, {2} Pokemon) para {3}?", battle_style, team_size, peer.name.to_s))
        # ⚠️ ESTE CAMINHO NAO E O QUE CORRE.
        #
        # O MOD 110 (PVP Lineup Sync) redefine o `request_custom_duel` inteiro e
        # carrega depois deste, portanto e a versao DELE que o jogo usa — e e la
        # que estao a espera e o cancelamento. Isto fica como estava, para o caso
        # de o 110 ser desligado; mexer aqui era escrever codigo morto.
        request_duel(peer,
          size: duel_size_for_style(rules["style"]),
          party: local_party,
          full_party: $player.party,
          rules: rules
        )
      end
    end

    def request_duel(peer, size: 1, party: nil, full_party: nil, rules: nil)
      duel_rules = normalize_duel_rules(rules)
      duel_rules["style"] = duel_style_from_rules(duel_rules, size)
      selected_party = Array(party)
      selected_party = $player.party if selected_party.empty?
      preview_party = Array(full_party)
      preview_party = $player.party if preview_party.empty?

      effective_size = selected_party.length
      effective_size = size if effective_size <= 0

      battle_id = build_battle_id("duel")
      seed = nil
      if AnilLanRework.connected?
        AnilLanRework.connection.send_packet("request_battle_seed", {
          "battle_id" => battle_id
        })
        seed = wait_for_battle_seed(battle_id)
      end
      seed ||= rand(0x3FFF_FFFF)
      stored_packet = {
        "to_id"         => peer.internal_id,
        "battle_id"     => battle_id,
        "mode"          => "pvp",
        "size"          => effective_size,
        "seed"          => seed,
        "sent_at"       => Time.now.to_f,
        "rules"         => duel_rules,
        "party"         => AnilLanRework::Serializer.serialize_party(preview_party),
        "selected_party" => AnilLanRework::Serializer.serialize_party(selected_party)
      }
      wire_packet = stored_packet.dup
      wire_packet["rules"] = public_duel_rules(duel_rules)
      @outgoing_invites[battle_id] = stored_packet
      AnilLanRework.log("request_duel battle_id=#{battle_id} size=#{size} rules=#{duel_rules.inspect} local_party=#{party_species_names(selected_party).inspect}")
      AnilLanRework.connection.send_packet("battle_invite", wire_packet)
    end

    def nearby_peer_on_same_map(include_unavailable: false)
      return nil unless $game_map && $game_player
      AnilLanRework.players.values.find do |peer|
        next false if peer.map_id.to_i != $game_map.map_id.to_i
        if !include_unavailable
          next false if peer.battle_busy == true
          next false if peer.menu_open == true
        end
        dx = (peer.x.to_i - $game_player.x.to_i).abs
        dy = (peer.y.to_i - $game_player.y.to_i).abs
        next false if [dx, dy].max > AnilLanRework::REMOTE_SPAWN_AUTHORITY_DISTANCE
        true
      end
    end

    def partner_on_same_map
      nearby_peer_on_same_map(include_unavailable: false)
    end

    def local_player_menu_open?
      ($game_temp && $game_temp.in_menu) ? true : false
    rescue
      false
    end

    def local_player_available_for_coop_invite?
      return false if local_player_busy?
      # return false if local_player_menu_open? # Permitir que o convite fique na fila
      return false unless $scene.is_a?(Scene_Map) || $scene.is_a?(Scene_Menu) || $scene.is_a?(Scene_Bag)
      return false if (pbMapInterpreterRunning? rescue false)
      true
    rescue
      false
    end

    def local_player_busy?
      return true if @active_context
      return true if $game_temp&.in_battle
      return true if $game_temp&.player_transferring
      # return true if $scene && !$scene.is_a?(Scene_Map) # Removido para permitir coop em menus
      false
    end

    def peer_unavailable_reason(peer)
      return nil unless peer
      return :battle if peer.battle_busy == true
      return :menu if peer.menu_open == true
      nil
    end

    def battle_response_unavailable_reason(packet)
      return nil unless packet.is_a?(Hash)
      return :menu if packet["menu_open"] == true
      return :battle if packet["busy"] == true
      nil
    end

    def trigger_peer_busy_balloon(peer)
      return unless peer
      return unless $scene && $scene.respond_to?(:spriteset)
      spriteset = $scene.spriteset
      return unless spriteset
      now = (System.uptime rescue Time.now.to_f).to_f
      @peer_busy_balloon_at ||= {}
      key = peer.internal_id.to_s
      last = @peer_busy_balloon_at[key].to_f
      return if last > 0.0 && (now - last) < AnilLanRework::REMOTE_BUSY_BALLOON_COOLDOWN
      @peer_busy_balloon_at[key] = now
      AnilLanRework.log("triggering busy balloon for peer #{peer.name} (blink: #{AnilLanRework::REMOTE_BUSY_BALLOON_BLINK_ENABLED})")
      spriteset.show_busy_balloon_for_peer(key, peer) if spriteset.respond_to?(:show_busy_balloon_for_peer)
    end

    def notify_unavailable_peer(peer, reason = nil)
      return unless peer
      return unless AnilLanRework.players.key?(peer.internal_id.to_s)
      trigger_peer_busy_balloon(peer)
      message = case reason
                when :battle then AnilLanRework.ui_format("{1} esta em batalha agora.", peer.name.to_s)
                when :menu   then AnilLanRework.ui_format("{1} esta com um menu aberto agora.", peer.name.to_s)
                else              AnilLanRework.ui_format("{1} nao esta disponivel agora.", peer.name.to_s)
                end
      pbMessage(message) rescue nil
    end

    def suppress_local_wild_battle?
      false
    end

    def inject_partner(peer, party_blob = nil, battle_id = nil)
      return unless peer
      peer.party_blob = Array(party_blob) if party_blob
      partner_party = AnilLanRework::Serializer.deserialize_party(peer.party_blob)
      active_battle_id = battle_id.to_s
      active_battle_id = @active_context&.battle_id.to_s if active_battle_id.empty?
      AnilLanRework.log("inject_partner battle_id=#{active_battle_id} peer=#{peer.internal_id} blob_size=#{Array(peer.party_blob).length} party_size=#{partner_party.length}")
      
      if partner_party.empty?
        AnilLanRework.log("coop: Partner #{peer.internal_id} has an empty party! Generating fallback Magikarp to prevent engine crash.")
        partner_party << Pokemon.new(:MAGIKARP, 1)
      end
      
      trainer_type = AnilLanRework.trainer_type_for_character(peer.char_name, GameData::TrainerType.keys.first)
      trainer_name = peer.name.to_s.empty? ? "Parceiro" : peer.name.to_s
      $PokemonGlobal.partner = [trainer_type, trainer_name, rand(65_535), partner_party, true]
      @partner_injected = true
    rescue => e
      AnilLanRework.log("inject_partner error #{e}")
    end

    def remove_partner
      if defined?($PokemonGlobal)
        $PokemonGlobal.partner = nil
      end
      @partner_injected = false
    rescue
      @partner_injected = false
    end

    def clear_peer_party_cache(peer, reason = nil)
      return unless peer
      peer.party_blob = []
      AnilLanRework.log("clear_peer_party_cache peer=#{peer.internal_id} reason=#{reason}") if reason
    rescue => e
      AnilLanRework.log("clear_peer_party_cache error #{e.class}: #{e.message}")
    end

    def request_coop_battle(kind:, foe_party: nil, foe_trainers: nil, can_override: false)
      return nil if local_player_busy?
      peer = nearby_peer_on_same_map(include_unavailable: true)
      return nil unless peer
      battle_id = build_battle_id(kind.to_s)
      seed = nil
      if AnilLanRework.connected?
        AnilLanRework.connection.send_packet("request_battle_seed", {
          "battle_id" => battle_id
        })
        seed = wait_for_battle_seed(battle_id)
      end
      seed ||= rand(0x3FFF_FFFF)
      AnilLanRework.log("request_coop_battle start battle_id=#{battle_id} kind=#{kind} peer=#{peer.internal_id} foes=#{Array(foe_party).length}")
      boss_flag = false
      if defined?(BossBattleConstants) && $game_switches && ($game_switches[BossBattleConstants::BOSS_BATTLE_SWITCH] rescue false)
        boss_flag = true
      elsif $game_switches && ($game_switches[45] rescue false)
        boss_flag = true
      elsif $game_temp && $game_temp.battle_rules && ($game_temp.battle_rules["boss"] || $game_temp.battle_rules["midbattleScript"] || $game_temp.battle_rules["databoxStyle"] rescue false)
        boss_flag = true
      end

      AnilLanRework.connection.send_packet("battle_request",
        "to_id"         => peer.internal_id,
        "battle_id"     => battle_id,
        "kind"          => kind.to_s,
        "seed"          => seed,
        "can_override"  => can_override ? true : false,
        "battle_proto"  => AnilLanRework::BattleSync::COOP_BATTLE_PROTO,
        "boss_battle"   => boss_flag,
        "battle_rules"  => ($game_temp.battle_rules rescue {}),
        "foes"          => AnilLanRework::Serializer.serialize_party(foe_party),
        "foe_trainers"  => AnilLanRework::Serializer.serialize_trainers(foe_trainers),
        "party"         => AnilLanRework::Serializer.serialize_party($player.party)
      )
      response = wait_for_battle_response(battle_id, peer.internal_id)
      AnilLanRework.log("request_coop_battle response battle_id=#{battle_id} accepted=#{response.is_a?(Hash) ? response['accepted'].inspect : response.inspect}")
      accepted = response.is_a?(Hash) ? (response["accepted"] == true || response["accepted"] == "true") : (response == true)
      if accepted == true
        peer.party_blob = Array(response["party"]) if response.is_a?(Hash) && response["party"]
        activate_context(
          battle_id: battle_id,
          mode: :coop,
          client_index: 0,
          partner_id: peer.internal_id,
          seed: seed,
          rules: {},
          foe_party: foe_party
        )
        # Proto negociado = o menor entre os dois lados. Guest antigo nao manda o
        # campo (nil -> 1), entao a batalha cai no fluxo legado e nao quebra.
        guest_proto = (response.is_a?(Hash) ? response["battle_proto"].to_i : 1)
        set_coop_battle_proto(@active_context, guest_proto)
        inject_partner(peer, nil, battle_id)
        mark_coop_wild_start_pending(battle_id) if kind.to_s == "wild"

        # DECISAO DO MODO — tomada aqui, pelo host, e enviada pronta.
        # Exige a flag ligada NESTE cliente e um convidado que fale o proto novo.
        # O guest_proto ja foi lido acima (set_coop_battle_proto), entao nao ha
        # round-trip extra.
        usa_lockstep = begin
          (defined?(CoopCC) && CoopCC.ligado?) &&
            guest_proto.to_i >= AnilLanRework::BattleSync::COOP_BATTLE_PROTO
        rescue
          false
        end
        definir_coop_lockstep!(usa_lockstep)
        AnilLanRework.log("coop host decidiu lockstep=#{usa_lockstep} (guest_proto=#{guest_proto})")
        send_start_signal(peer.internal_id, usa_lockstep) rescue nil
        AnilLanRework.connection.flush_batch rescue nil
        return { battle_id: battle_id, seed: seed, peer: peer }
      end
      unavailable_reason = battle_response_unavailable_reason(response)
      if unavailable_reason
        clear_peer_party_cache(peer, "coop_unavailable_#{unavailable_reason}")
        notify_unavailable_peer(peer, unavailable_reason)
        return false
      end
      if response.is_a?(Hash) && response.key?("accepted") && accepted == false
        clear_peer_party_cache(peer, "coop_declined")
        # pbMessage(_INTL("Convite recusado.")) rescue nil
        return :declined
      end
      clear_peer_party_cache(peer, "coop_no_response")
      nil
    end

    def store_battle_response(packet)
      return unless packet.is_a?(Hash)
      @battle_responses[packet["battle_id"].to_s] = packet
    end

    def wait_for_battle_response(battle_id, peer_id = nil)
      started = Time.now.to_f
      viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
      viewport.z = 99_999
      window = Window_UnformattedTextPokemon.newWithSize(AnilLanRework::BattleSync.waiting_text("Aguardando parceiro..."), 0, 0, 360, 64, viewport)
      window.x = (Graphics.width - window.width) / 2
      window.y = (Graphics.height - window.height) / 2
      begin
        loop do
          return @battle_responses.delete(battle_id.to_s) if @battle_responses.key?(battle_id.to_s)
          return nil unless AnilLanRework.connected?
          return nil if peer_id && !AnilLanRework.players.key?(peer_id.to_s)
          return nil if Time.now.to_f - started >= 60.0
          AnilLanRework.connection.tick
          AnilLanRework.connection.drain { |packet| AnilLanRework::Router.route_packet(packet) }
          Graphics.update
          Input.update
          window.update rescue nil
        end
      ensure
        window.dispose rescue nil
        viewport.dispose rescue nil
      end
    end

    def store_coop_request(packet)
      return unless packet.is_a?(Hash)
      sender_id = packet["sender_id"].to_s
      return if sender_id.empty? || sender_id == AnilLanRework.self_internal_id

      # ⚠️ O CONVITE TEM DE SER PARA MIM.
      #
      # Faltava esta verificacao e era so aqui: o convite de DUELO
      # (store_incoming_invite) e o de TROCA (receive_invite) ja recusavam
      # convite alheio. So o coop e que aceitava qualquer battle_request que
      # lhe chegasse, viesse de quem viesse — dai receber convite de gente com
      # quem nunca se esteve em grupo.
      destino = packet["to_id"].to_s
      if destino != AnilLanRework.self_internal_id.to_s
        AnilLanRework.log("[COOP] convite ignorado: era para to_id=#{destino.inspect}, nao para mim (de #{sender_id})") rescue nil
        return
      end
      peer = (AnilLanRework.players[sender_id] ||= AnilLanRework::RemotePeer.new)
      peer.internal_id = sender_id
      peer.party_blob = Array(packet["party"]) if packet["party"]
      unless local_player_available_for_coop_invite?
        AnilLanRework.connection.send_packet("battle_response",
          "to_id"      => sender_id,
          "battle_id"  => packet["battle_id"].to_s,
          "accepted"   => false,
          "busy"       => true,
          "menu_open"  => local_player_menu_open? ? true : false
        )
        return
      end
      @pending_coop_invite = packet
    end

    def update_pending_coop_invite
      return unless @pending_coop_invite
      # Só mostra a janelinha se estiver no mapa e sem menu aberto
      return unless $scene.is_a?(Scene_Map)
      return if local_player_menu_open?
      return if (pbMapInterpreterRunning? rescue false)
      return if $game_temp&.message_window_showing

      packet = @pending_coop_invite
      @pending_coop_invite = nil
      sender_id = packet["sender_id"].to_s
      peer = AnilLanRework.players[sender_id]
      sender_name = peer && !peer.name.to_s.empty? ? peer.name.to_s : sender_id
      battle_kind = packet["kind"].to_s == "trainer" ? "batalha contra treinador" : "batalha selvagem"
      accepted_raw = pbConfirmMessage(AnilLanRework.ui_format("{1} quer iniciar uma {2} em coop. Participar?", sender_name, battle_kind))
      accepted = (accepted_raw == true || accepted_raw == 0)
      AnilLanRework.connection.send_packet("battle_response",
        "to_id"        => sender_id,
        "battle_id"    => packet["battle_id"].to_s,
        "accepted"     => accepted,
        "battle_proto" => AnilLanRework::BattleSync::COOP_BATTLE_PROTO,
        "party"        => accepted ? AnilLanRework::Serializer.serialize_party($player.party) : nil
      )
      if accepted
        packet["accepted_at"] = Time.now.to_f
        @pending_coop_start = packet
      else
        @pending_coop_start = nil
        @coop_start_ready_from.delete(sender_id) if @coop_start_ready_from
        clear_peer_party_cache(peer, "local_decline")
        clear_pending_coop_start_wait_window
      end
    end

    def update_pending_coop_start
      return unless @pending_coop_start
      return unless $scene.is_a?(Scene_Map)

      packet    = @pending_coop_start
      sender_id = packet["sender_id"].to_s
      peer      = AnilLanRework.players[sender_id]

      if !peer
        clear_pending_coop_start_wait_window
        @pending_coop_start = nil
        return
      end

      is_wild   = packet["kind"].to_s == "wild"
      is_ready  = @coop_start_ready_from && @coop_start_ready_from[sender_id]

      # Inicia imediatamente se já recebemos o sinal start do host.
      # Isso cobre batalhas normais onde o host envia send_start_signal antes
      # de entrar na batalha (e portanto antes de peer.battle_busy ser true).
      if is_ready
        clear_pending_coop_start_wait_window
        return if $game_temp&.player_transferring
        @pending_coop_start = nil
        @coop_start_ready_from.delete(sender_id) if @coop_start_ready_from
        start_coop_battle(packet)
        return
      end

      # Fluxo legado: revanche com diálogo — host fica busy enquanto o NPC fala,
      # cliente espera o host sair do diálogo (battle_busy muda para true na batalha).
      if peer.battle_busy != true && !is_wild
        accepted_at = packet["accepted_at"].to_f
        if accepted_at > 0.0 && Time.now.to_f - accepted_at >= 60.0
          clear_pending_coop_start_wait_window
          @pending_coop_start = nil
          pbMessage(_INTL("A batalha em coop não foi iniciada a tempo.")) rescue nil
          return
        end
        unless packet["kind"].to_s == "wild"
          ensure_pending_coop_start_wait_window(waiting_text("Aguardando parceiro iniciar a batalha..."))
        end
        return
      end

      clear_pending_coop_start_wait_window
      return if $game_temp&.message_window_showing
      return if $game_temp&.player_transferring
      @pending_coop_start = nil
      @coop_start_ready_from.delete(sender_id) if @coop_start_ready_from
      start_coop_battle(packet)
    end

    # O sinal de start leva a DECISAO do modo de batalha, nao so o "estou pronto".
    #
    # Porque isto importa: o convidado nao pode decidir sozinho se usa lockstep.
    # A primeira tentativa (2026-08-07) deixava cada lado negociar por conta
    # propria dentro do start_core, com timeout de 20s — e como o host entra na
    # batalha na hora enquanto o convidado ainda esta no prompt de aceite, um
    # estourava o tempo e caia no coop antigo enquanto o outro entrava no
    # lockstep. Dois motores, duas batalhas ("inicia na tela de um e o outro
    # entra sozinho").
    #
    # Aqui quem decide e o HOST, que nesse ponto ja sabe tudo: leu o
    # `battle_proto` do convidado na resposta do convite (ver request_coop_battle)
    # ANTES de mandar este sinal. O convidado so obedece. Nao ha handshake para
    # falhar, nem timeout, nem como os dois divergirem.
    #
    # Cliente antigo nao entende o campo -> nil -> false -> os dois no legado.
    # Mesmo padrao do battle_proto.
    def send_start_signal(partner_id, lockstep = false)
      return unless partner_id && AnilLanRework.connected?
      AnilLanRework.connection.send_packet("battle_start_signal", {
        "to_id"    => partner_id.to_s,
        "lockstep" => (lockstep ? true : false)
      })
    end

    def receive_start_signal(packet)
      sender_id = packet["sender_id"].to_s
      @coop_start_ready_from ||= {}
      @coop_start_ready_from[sender_id] = true
      @coop_lockstep_decidido = (packet["lockstep"] == true)
      AnilLanRework.log("receive_start_signal from #{sender_id} lockstep=#{@coop_lockstep_decidido}")
    end

    # A decisao que veio no sinal (convidado) ou que este cliente tomou (host).
    # Lida pelo 125 na hora de escolher a classe da batalha.
    def coop_lockstep_decidido?
      @coop_lockstep_decidido == true
    end

    def definir_coop_lockstep!(valor)
      @coop_lockstep_decidido = (valor ? true : false)
    end

    def limpar_coop_lockstep!
      @coop_lockstep_decidido = false
    end

    def mark_local_coop_eliminated!(battle = nil, watch_until_end = nil)
      ctx = @active_context
      return false unless ctx && ctx.mode == :coop
      return false if local_coop_eliminated_marked?(ctx)
      watch_until_end = AnilLanRework.coop_watch_battle_until_end? if watch_until_end.nil?
      watch_until_end = (watch_until_end == true)
      ctx.instance_variable_set(:@anil_local_coop_eliminated, true)
      ctx.instance_variable_set(:@anil_local_coop_watch_until_end, watch_until_end)
      if AnilLanRework.connected?
        AnilLanRework.connection.send_packet("battle_coop_eliminated",
          "to_id"           => ctx.partner_id,
          "battle_id"       => ctx.battle_id,
          "watch_until_end" => watch_until_end
        )
      end
      AnilLanRework.log(
        "coop local eliminated battle_id=#{ctx.battle_id} watch_until_end=#{watch_until_end} battlers=#{coop_slots_debug(battle)}"
      )
      true
    rescue => e
      AnilLanRework.log("mark_local_coop_eliminated error #{e.class}: #{e.message}")
      false
    end

    def receive_coop_eliminated(packet)
      return unless packet.is_a?(Hash)
      ctx = @active_context
      return unless ctx && ctx.mode == :coop
      return unless ctx.battle_id.to_s == packet["battle_id"].to_s
      watch_until_end = (packet["watch_until_end"] == true)
      ctx.instance_variable_set(:@anil_remote_coop_eliminated, true)
      ctx.instance_variable_set(:@anil_remote_coop_watch_until_end, watch_until_end)
      unless watch_until_end
        ctx.instance_variable_set(:@anil_remote_manual_lock, false)
        ctx.instance_variable_set(:@anil_remote_manual_reason, nil)
        ctx.instance_variable_set(:@anil_remote_manual_unlock_required, false)
      end
      AnilLanRework.log(
        "coop remote eliminated battle_id=#{ctx.battle_id} watch_until_end=#{watch_until_end}"
      )
    rescue => e
      AnilLanRework.log("receive_coop_eliminated error #{e.class}: #{e.message}")
    end

    def start_coop_battle(packet)
      sender_id = packet["sender_id"].to_s
      peer = AnilLanRework.players[sender_id]
      return unless peer
      AnilLanRework.log("start_coop_battle battle_id=#{packet['battle_id']} kind=#{packet['kind']} peer=#{sender_id} foes=#{Array(packet['foes']).length}")
      activate_context(
        battle_id: packet["battle_id"].to_s,
        mode: :coop,
        client_index: 1,
        partner_id: sender_id,
        seed: packet["seed"].to_i,
        rules: {},
        foe_party: nil
      )
      # Proto do host veio no battle_request; negocia o menor. Host antigo nao
      # manda (nil -> 1) e a batalha roda no fluxo legado.
      host_proto = packet["battle_proto"].to_i
      set_coop_battle_proto(@active_context, host_proto)
      inject_partner(peer, packet["party"], packet["battle_id"])
      # 1. Espelha as battle_rules do host (ex: regras de boss, backdrop, cannotRun, midbattle)
      if packet["battle_rules"].is_a?(Hash) && !packet["battle_rules"].empty?
        $game_temp.clear_battle_rules rescue nil
        packet["battle_rules"].each do |rule_key, rule_val|
          if rule_key.to_s == "midbattleScript" && rule_val
            val_sym = rule_val.to_s.sub(/^:/, "").to_sym
            setBattleRule("midbattleScript", val_sym) rescue nil
          elsif rule_val.nil? || rule_val == true
            setBattleRule(rule_key.to_s) rescue nil
          else
            setBattleRule(rule_key.to_s, rule_val) rescue nil
          end
        end
        AnilLanRework.log("start_coop_battle synced battle_rules=#{packet['battle_rules'].inspect}")
      end

      # 2. Espelha o estado de boss do host (Switch 45 / BOSS_BATTLE_SWITCH)
      # O anfitriao diz explicitamente se e boss. O midbattleScript so serve de
      # recurso para anfitrioes ANTIGOS, que nao mandavam a chave: usa-lo sempre
      # marcava como boss qualquer batalha com script de meio-combate, e havia
      # muitas que nao tem nada de boss.
      if packet.key?("boss_battle")
        boss_on = (packet["boss_battle"] == true || packet["boss_battle"].to_s == "true")
      else
        boss_on = !!(packet["battle_rules"].is_a?(Hash) &&
                     packet["battle_rules"]["midbattleScript"])
      end
      guardar_switches_de_boss!
      if $game_switches
        $game_switches[45] = boss_on rescue nil
        if defined?(BossBattleConstants)
          $game_switches[BossBattleConstants::BOSS_BATTLE_SWITCH] = boss_on rescue nil
        end
      end
      AnilLanRework.log("start_coop_battle boss_battle=#{boss_on}")
      if packet["kind"].to_s == "trainer"
        trainers = AnilLanRework::Serializer.deserialize_trainers(packet["foe_trainers"])
        ensure_trainer_rule
        # Synchronize host's explicit battle size (e.g. "double" for Gym Leaders with 1 trainer object)
        if packet["battle_size"] && !packet["battle_size"].to_s.empty?
          setBattleRule(packet["battle_size"].to_s) rescue nil
        end
        if TrainerBattle.respond_to?(:anil_rework_original_start_core)
          TrainerBattle.anil_rework_original_start_core(*trainers)
        elsif TrainerBattle.respond_to?(:start_core)
          TrainerBattle.start_core(*trainers)
        end
      else
        foes = AnilLanRework::Serializer.deserialize_party(packet["foes"])
        ensure_wild_rule(foes)
        if WildBattle.respond_to?(:anil_rework_original_start)
          foes.empty? ? WildBattle.anil_rework_original_start(can_override: packet["can_override"] == true) :
                        WildBattle.anil_rework_original_start(*foes, can_override: packet["can_override"] == true)
        else
          foes.empty? ? WildBattle.start(can_override: packet["can_override"] == true) :
                        WildBattle.start(*foes, can_override: packet["can_override"] == true)
        end
      end
    rescue => e
      AnilLanRework.log("start_coop_battle error #{e}")
      if defined?(BossBattleConstants) && $game_switches
        $game_switches[BossBattleConstants::BOSS_BATTLE_SWITCH] = false rescue nil
      end
      $game_temp.clear_battle_rules rescue nil
      remove_partner
      clear_context
      AnilLanRework.request_map_graphics_refresh!("coop_start_error", 3)
    end

    def ensure_wild_rule(foe_party)
      rules = ($game_temp.battle_rules rescue {})
      return if rules && rules["size"]
      setBattleRule("2v#{[Array(foe_party).length, 1].max}") rescue nil
    end

    def ensure_trainer_rule
      rules = ($game_temp.battle_rules rescue {})
      return if rules && rules["size"]
      setBattleRule("double") rescue nil
    end

    # ITEM 2.1 DO BRIEFING — CHAVE (turn, slot) NO CANAL DE ACOES.
    #
    # Antes o canal era uma FIFA cega: send_battle_action empilhava e
    # next_remote_action dava shift. Uma unica assimetria (um lado envia e o
    # outro nao, ou vice-versa) desalinhava a fila PARA SEMPRE — o pacote do
    # turno 3 era consumido pelo pedido do turno 4, e a partir dai cada espera
    # estourava o timeout. O sintoma visivel disso e o parceiro "usando Luta":
    # o timeout dispara pbAutoChooseMove no slot do outro.
    #
    # Agora cada acao carrega (turn, slot) e so e consumida por quem pediu
    # exatamente aquele par. Pacote de turno ANTIGO e descartado com log em vez
    # de contaminar o pedido atual.
    def send_battle_action(actions, slot = nil)
      return unless @active_context && AnilLanRework.connected?
      turno = (@active_context.battle ? @active_context.battle.turnCount.to_i : -1) rescue -1
      payload = {
        "to_id"     => @active_context.partner_id,
        "battle_id" => @active_context.battle_id,
        "actions"   => actions,
        "turn"      => turno,
        "slot"      => (slot.nil? ? nil : slot.to_i),
        "rng"       => @active_context.rng.snapshot
      }
      party_sync = battle_party_sync_payload
      payload["party_sync"] = party_sync if party_sync
      AnilLanRework.connection.send_packet("battle_action", payload)
    end

    def send_coop_foe_action(idx_battler, action)
      return unless @active_context && @active_context.mode == :coop && AnilLanRework.connected?
      payload = {
        "to_id"     => @active_context.partner_id,
        "battle_id" => @active_context.battle_id,
        "battler"   => idx_battler.to_i,
        "action"    => action,
        "rng"       => @active_context.rng.snapshot
      }
      AnilLanRework.connection.send_packet("battle_foe_action", payload)
    end

    def send_coop_hp_event(packet)
      return unless @active_context && @active_context.mode == :coop && AnilLanRework.connected?
      payload = packet.merge(
        "to_id"               => @active_context.partner_id,
        "battle_id"           => @active_context.battle_id,
        "sender_client_index" => @active_context.client_index.to_i
      )
      AnilLanRework.connection.send_packet("battle_hp_event", payload)
    end

    def send_coop_capture_result(packet)
      return unless @active_context && @active_context.mode == :coop && AnilLanRework.connected?
      payload = packet.merge(
        "to_id"               => @active_context.partner_id,
        "battle_id"           => @active_context.battle_id,
        "sender_client_index" => @active_context.client_index.to_i
      )
      AnilLanRework.connection.send_packet("battle_capture_result", payload)
    end

    BATTLER_EFFECT_IDS = PBEffects.constants.map { |name| PBEffects.const_get(name) rescue nil }.compact.select do |id|
      (0..116).include?(id) || (400..416).include?(id)
    end.sort.freeze
    POSITION_EFFECT_IDS = PBEffects.constants.map { |name| PBEffects.const_get(name) rescue nil }.compact.select { |id| (700..708).include?(id) }.sort.freeze
    SIDE_EFFECT_IDS     = PBEffects.constants.map { |name| PBEffects.const_get(name) rescue nil }.compact.select { |id| (800..821).include?(id) }.sort.freeze
    FIELD_EFFECT_IDS    = PBEffects.constants.map { |name| PBEffects.const_get(name) rescue nil }.compact.select { |id| (900..912).include?(id) }.sort.freeze

    EFFECT_BATTLER_INDEX_IDS = [
      PBEffects::Attract,
      PBEffects::BideTarget,
      PBEffects::CounterTarget,
      PBEffects::DestinyBondTarget,
      PBEffects::JawLock,
      PBEffects::LeechSeed,
      PBEffects::LockOnPos,
      PBEffects::MeanLook,
      PBEffects::MirrorCoatTarget,
      PBEffects::Octolock,
      PBEffects::PerishSongUser,
      PBEffects::SkyDrop,
      PBEffects::TrappingUser,
      PBEffects::FutureSightUserIndex,
      PBEffects::SyrupyUser
    ].freeze

    def effect_ids_for_scope(scope)
      case scope
      when :battler  then BATTLER_EFFECT_IDS
      when :position then POSITION_EFFECT_IDS
      when :side     then SIDE_EFFECT_IDS
      when :field    then FIELD_EFFECT_IDS
      else []
      end
    end

    def serialize_packet_value(value)
      case value
      when NilClass
        { "__anil_kind" => "nil" }
      when TrueClass, FalseClass, Integer, Float, String
        value
      when Symbol
        { "__anil_kind" => "symbol", "value" => value.to_s }
      when Array
        { "__anil_kind" => "array", "values" => value.map { |entry| serialize_packet_value(entry) } }
      when Hash
        {
          "__anil_kind" => "hash",
          "entries"     => value.map { |key, entry| [serialize_packet_value(key), serialize_packet_value(entry)] }
        }
      else
        if value.respond_to?(:id)
          serialize_packet_value(value.id)
        else
          { "__anil_kind" => "unsupported", "class" => value.class.name.to_s }
        end
      end
    end

    def deserialize_packet_value(payload)
      return payload unless payload.is_a?(Hash) && payload["__anil_kind"]
      case payload["__anil_kind"]
      when "nil"
        nil
      when "symbol"
        payload["value"].to_s.empty? ? nil : (payload["value"].to_sym rescue payload["value"])
      when "array"
        Array(payload["values"]).map { |entry| deserialize_packet_value(entry) }
      when "hash"
        Array(payload["entries"]).each_with_object({}) do |entry, hash|
          next unless entry.is_a?(Array) && entry.length == 2
          hash[deserialize_packet_value(entry[0])] = deserialize_packet_value(entry[1])
        end
      else
        nil
      end
    end

    def translate_snapshot_battler_index(index, sender_client_index, battle)
      idx = index.to_i
      return idx if idx < 0
      translate_remote_battler_index(idx, sender_client_index, battle)
    rescue
      idx
    end

    def serialize_effect_value(scope, effect_id, value, owner = nil)
      return { "__anil_kind" => "battler_index", "value" => value.to_i } if EFFECT_BATTLER_INDEX_IDS.include?(effect_id.to_i)
      if scope == :battler && effect_id.to_i == PBEffects::Illusion
        party = owner ? (owner.battle.pbParty(owner.index) rescue nil) : nil
        party_index = Array(party).index(value)
        # personalID junto do indice: pbParty(owner.index) devolve partys
        # DIFERENTES em cada cliente do coop (a do host tem os Pokemon dele
        # primeiro), entao o indice sozinho apontava para outro Pokemon do outro
        # lado. O personalID e estavel; o indice fica so como fallback.
        pid = (value.respond_to?(:personalID) ? value.personalID.to_i : nil) rescue nil
        if !party_index.nil? || !pid.nil?
          return { "__anil_kind" => "illusion", "party_index" => party_index, "personal_id" => pid }
        end
      end
      if scope == :battler && effect_id.to_i == PBEffects::Commander
        return {
          "__anil_kind" => "commander",
          "values"      => Array(value).each_with_index.map { |entry, idx| idx == 0 ? { "__anil_kind" => "battler_index", "value" => entry.to_i } : serialize_packet_value(entry) }
        }
      end
      serialize_packet_value(value)
    rescue => e
      AnilLanRework.log("serialize_effect_value error scope=#{scope} effect=#{effect_id} #{e.class}: #{e.message}")
      { "__anil_kind" => "unsupported", "class" => value.class.name.to_s }
    end

    def deserialize_effect_value(scope, effect_id, payload, sender_client_index, battle, owner = nil)
      if payload.is_a?(Hash) && payload["__anil_kind"] == "battler_index"
        return translate_snapshot_battler_index(payload["value"], sender_client_index, battle)
      end
      if scope == :battler && effect_id.to_i == PBEffects::Illusion &&
         payload.is_a?(Hash) && payload["__anil_kind"] == "illusion"
        party = owner ? (owner.battle.pbParty(owner.index) rescue nil) : nil
        pid = payload["personal_id"]
        unless pid.nil?
          achado = Array(party).compact.find { |pk| (pk.personalID.to_i rescue nil) == pid.to_i }
          return achado if achado
        end
        return nil if payload["party_index"].nil?
        return Array(party)[payload["party_index"].to_i]
      end
      if scope == :battler && effect_id.to_i == PBEffects::Commander &&
         payload.is_a?(Hash) && payload["__anil_kind"] == "commander"
        return Array(payload["values"]).each_with_index.map do |entry, idx|
          idx == 0 ? deserialize_effect_value(scope, effect_id, entry, sender_client_index, battle, owner) : deserialize_packet_value(entry)
        end
      end
      deserialize_packet_value(payload)
    end

    def serialize_effect_entries(scope, effects, owner = nil)
      effect_ids_for_scope(scope).map do |effect_id|
        {
          "id"    => effect_id.to_i,
          "value" => serialize_effect_value(scope, effect_id, effects[effect_id], owner)
        }
      end
    end

    def apply_effect_entries_to_collection(collection, scope, entries, sender_client_index, battle, owner = nil)
      Array(entries).each do |entry|
        next unless entry.is_a?(Hash)
        effect_id = entry["id"].to_i
        bruto = entry["value"]

        # Um valor que o serializer nao soube representar chega como
        # {"__anil_kind" => "unsupported"} e deserializa para nil. Escrever esse
        # nil por cima APAGA estado local valido (era assim que uma Illusion
        # ativa virava nil no outro cliente). Nesses casos, preserva o local.
        if bruto.is_a?(Hash) && bruto["__anil_kind"].to_s == "unsupported"
          AnilLanRework.log("efeito #{effect_id} (#{scope}) veio como 'unsupported' — mantendo valor local")
          next
        end

        collection[effect_id] = deserialize_effect_value(scope, effect_id, bruto, sender_client_index, battle, owner)
      end
    rescue => e
      AnilLanRework.log("apply_effect_entries_to_collection error scope=#{scope} #{e.class}: #{e.message}")
    end

    # Campos de ESTADO DE BATALHA que faltavam no snapshot. Sem eles nenhuma das
    # mecanicas abaixo era reparavel — o snapshot corrigia HP/status/forma e
    # deixava o resto divergir para sempre (0 de 40 mecanicas cobertas):
    #
    #   stages       -> Intimidate, Defiant, Competitive, Mirror Armor, Icy Wind,
    #                   Sticky Web, Bulldoze, Speed Boost, Weak Armor, Steam
    #                   Engine, Moody, Meteor Beam/Geomancy (stat da carga).
    #                   Tambem entra em pbSpeed => ORDEM DO TURNO.
    #   item         -> Power Herb, White/Mental Herb, Focus Sash, Life Orb,
    #                   Rocky Helmet, berries, Choice lock, Quick Claw/Custap,
    #                   Eject Button/Pack, Red Card, Booster Energy, Unburden.
    #   ability      -> Trace, Mummy, Skill Swap, Entrainment, Gastro Acid,
    #                   Neutralizing Gas, Power of Alchemy, Dancer.
    #   types        -> Soak, Forest's Curse, Trick-or-Treat, Burn Up, Double
    #                   Shock, Conversion, Reflect Type, Protean/Libero.
    #   moves        -> Struggle por PP divergente, Disable/Encore/Torment.
    #   took*/lastHP -> Focus Punch, Shell Trap, Beak Blast, Rage Fist,
    #                   Assurance, Avalanche, Counter, Mirror Coat, Metal Burst,
    #                   Berserk, Emergency Exit, Wimp Out, Anger Point.
    #
    # O host e a fonte de verdade do ESTADO DE SIMULACAO (assim como ja era do HP).
    # Cada cliente continua dono da IDENTIDADE dos seus proprios Pokemon (nivel,
    # IV/EV, stats) — isso vem pelo party_sync, nao por aqui.
    def serialize_battler_snapshot(battler)
      status_id = battler.status rescue nil
      status_id = nil if status_id.to_s.empty? || status_id.to_sym == :NONE rescue false
      stages = (battler.stages rescue nil)
      {
        "battler"      => battler.index.to_i,
        "hp"           => (battler.hp.to_i rescue nil),
        "totalhp"      => (battler.totalhp.to_i rescue nil),
        "status"       => status_id ? status_id.to_s : nil,
        "status_count" => (battler.statusCount.to_i rescue 0),
        # Sem forma/especie aqui, uma transformacao de boss (mega, Zen Mode, School
        # Form, Power Construct, stance change) fica visivel so para quem a executou,
        # e os dois lados passam a calcular dano com stats diferentes.
        "species"      => (battler.species.to_s rescue nil),
        "form"         => (battler.form.to_i rescue nil),
        "effects"      => serialize_effect_entries(:battler, battler.effects, battler),

        # --- estado de simulacao (proto >= 3) ---
        # Nomes conforme Battle::Battler da engine (0163_Battle_Battler.rb):
        # ability_id / item_id sao attr_accessor; NAO existe "tookDamage" — sao
        # tookMoveDamageThisRound (Focus Punch) e tookDamageThisRound.
        #
        # NAO entra aqui de proposito:
        #  - participants: sao INDICES DE PARTY, e a party do parceiro e diferente
        #    em cada cliente. Copiar cru corromperia a distribuicao de EXP.
        #  - damageState: e resetado a cada golpe, entao um snapshot de fim de
        #    fase nao significa nada.
        "stages"       => (stages.is_a?(Hash) ? stages.keys.map(&:to_s).sort.map { |k| [k, (stages[k.to_sym] || stages[k]).to_i] } : nil),
        "ability_id"   => (battler.ability_id.to_s rescue nil),
        "item_id"      => (battler.item_id.to_s rescue nil),
        "types"        => (Array(battler.types).map(&:to_s) rescue nil),
        "moves"        => (Array(battler.moves).map { |m| m ? { "id" => m.id.to_s, "pp" => m.pp.to_i } : nil } rescue nil),
        "fainted"      => ((battler.fainted? rescue false) ? true : false),
        "turn_count"   => (battler.turnCount.to_i rescue 0),
        "took_move_dmg" => ((battler.tookMoveDamageThisRound rescue false) ? true : false),
        "took_dmg"      => ((battler.tookDamageThisRound rescue false) ? true : false),
        "took_phys"     => ((battler.tookPhysicalHit rescue false) ? true : false),
        "last_hp_lost"  => (battler.lastHPLost.to_i rescue 0),
        "last_hp_foe"   => (battler.lastHPLostFromFoe.to_i rescue 0),
        "last_move"     => (battler.lastMoveUsed.to_s rescue nil),
        "last_reg_move" => (battler.lastRegularMoveUsed.to_s rescue nil),
        "last_round"    => (battler.lastRoundMoved.to_i rescue -1),
        "move_failed"      => ((battler.lastMoveFailed rescue false) ? true : false),
        "round_failed"     => ((battler.lastRoundMoveFailed rescue false) ? true : false),
        "below_half"       => ((battler.droppedBelowHalfHP rescue false) ? true : false),
        "below_third"      => ((battler.droppedBelowThirdHP rescue false) ? true : false),
        "stats_dropped"    => ((battler.statsDropped rescue false) ? true : false),
        "stats_raised_rd"  => ((battler.statsRaisedThisRound rescue false) ? true : false),
        "stats_lowered_rd" => ((battler.statsLoweredThisRound rescue false) ? true : false)
      }
    end

    # Aplica os campos de estado de simulacao acima. Chamado pelo applier do
    # snapshot, DEPOIS de forma/especie e ANTES do pbUpdate (o pbUpdate recalcula
    # stats, e stats dependem de stages/ability/item).
    # ESCOPO: NUNCA aplicar isto nos battlers que o PROPRIO receptor controla.
    #
    # O snapshot vem do host e inclui TODOS os battlers — inclusive a copia
    # deserializada que o host tem dos Pokemon do guest. Aplicar esses campos de
    # volta no guest sobrescreve o original com uma copia possivelmente defasada.
    # Foi assim que apareceu "O Golem aliado usou Luta!": o PP da copia que o
    # host tinha estava errado, e como o applier escreve tambem no realMove (o
    # objeto Pokemon persistente, nao so na copia de batalha), o Pokemon do
    # jogador ficava REALMENTE sem PP e caia em Struggle.
    #
    # Regra: cada cliente e dono da identidade dos seus proprios Pokemon.
    #   - foes                -> aplica (host e autoridade)
    #   - slot do parceiro    -> aplica (do lado do guest esse slot E o Pokemon
    #                            do host, que e a autoridade sobre ele)
    #   - slot local          -> NAO aplica
    def coop_battler_proprio?(battle, battler)
      ctx = @active_context
      return false unless ctx && ctx.mode == :coop && battle && battler
      local_slot, _remote_slot = coop_slots_for(battle)
      return false if local_slot.nil?
      battler.index.to_i == local_slot.to_i
    rescue
      false
    end

    def apply_remote_battle_state_to_battler(battler, entry, battle = nil)
      return unless battler && entry.is_a?(Hash)
      if battle && coop_battler_proprio?(battle, battler)
        AnilLanRework.log("snapshot: estado de simulacao IGNORADO para o battler proprio #{battler.index}")
        return
      end

      if entry["stages"].is_a?(Array) && battler.stages.is_a?(Hash)
        entry["stages"].each do |par|
          next unless par.is_a?(Array) && par.length == 2
          chave = par[0].to_s
          chave = chave.to_sym if battler.stages.key?(chave.to_sym)
          next unless battler.stages.key?(chave)
          battler.stages[chave] = par[1].to_i
        end
      end

      if entry.key?("ability_id") && !entry["ability_id"].to_s.empty?
        battler.ability_id = entry["ability_id"].to_s.to_sym
      end

      if entry.key?("item_id")
        raw = entry["item_id"].to_s
        battler.item_id = raw.empty? ? nil : raw.to_sym
      end

      if entry["types"].is_a?(Array) && !entry["types"].empty?
        battler.types = entry["types"].map { |t| t.to_s.to_sym }
      end

      # PP: o objeto de batalha guarda a sua propria copia, e o Pokemon real
      # guarda a dele (realMove). Os dois precisam bater, senao o proximo
      # pbReducePP diverge de novo.
      if entry["moves"].is_a?(Array)
        entry["moves"].each_with_index do |m, i|
          next unless m.is_a?(Hash)
          move = Array(battler.moves)[i]
          next unless move && move.id.to_s == m["id"].to_s
          alvo = m["pp"].to_i
          move.pp = alvo
          real = (move.realMove rescue nil)
          real.pp = alvo if real && real.respond_to?(:pp=)
        end
      end

      battler.turnCount = entry["turn_count"].to_i if entry.key?("turn_count")

      {
        "took_move_dmg"    => :tookMoveDamageThisRound=,
        "took_dmg"         => :tookDamageThisRound=,
        "took_phys"        => :tookPhysicalHit=,
        "move_failed"      => :lastMoveFailed=,
        "round_failed"     => :lastRoundMoveFailed=,
        "below_half"       => :droppedBelowHalfHP=,
        "below_third"      => :droppedBelowThirdHP=,
        "stats_dropped"    => :statsDropped=,
        "stats_raised_rd"  => :statsRaisedThisRound=,
        "stats_lowered_rd" => :statsLoweredThisRound=
      }.each do |chave, setter|
        next unless entry.key?(chave)
        battler.send(setter, entry[chave] ? true : false) if battler.respond_to?(setter)
      end

      battler.lastHPLost        = entry["last_hp_lost"].to_i if entry.key?("last_hp_lost")
      battler.lastHPLostFromFoe = entry["last_hp_foe"].to_i  if entry.key?("last_hp_foe")
      battler.lastRoundMoved    = entry["last_round"].to_i   if entry.key?("last_round")

      { "last_move" => :lastMoveUsed=, "last_reg_move" => :lastRegularMoveUsed= }.each do |chave, setter|
        next unless entry.key?(chave)
        raw = entry[chave].to_s
        battler.send(setter, raw.empty? ? nil : raw.to_sym) if battler.respond_to?(setter)
      end
    rescue => e
      AnilLanRework.log("apply_remote_battle_state_to_battler error battler=#{battler.index rescue '?'} #{e.class}: #{e.message}")
    end

    # weather/terrain entram AQUI (e nao so no battle_field_sync do fim do EOR)
    # porque este snapshot tambem sai no fim da fase de ataque e nos entry hazards.
    # Clima divergente no meio do turno quebra Solar Beam/Solar Blade (pulam a
    # carga no sol), Weather Ball, Terrain Pulse e todas as habilidades de Speed
    # dependentes de clima (Swift Swim, Chlorophyll, Sand Rush, Slush Rush,
    # Surge Surfer) — e Speed divergente inverte a ordem do turno.
    def serialize_coop_status_snapshot(battle)
      {
        "battlers"  => battle.battlers.compact.map { |battler| serialize_battler_snapshot(battler) },
        "positions" => Array(battle.positions).each_with_index.map { |position, index| { "position" => index, "effects" => serialize_effect_entries(:position, position.effects) } },
        "sides"     => Array(battle.sides).each_with_index.map { |side, index| { "side" => index, "effects" => serialize_effect_entries(:side, side.effects) } },
        "field"     => { "effects" => serialize_effect_entries(:field, battle.field.effects) },
        "field_state" => {
          "weather"          => (battle.field.weather ? battle.field.weather.to_s : "None"),
          "weather_duration" => (battle.field.weatherDuration.to_i rescue 0),
          "terrain"          => (battle.field.terrain ? battle.field.terrain.to_s : "None"),
          "terrain_duration" => (battle.field.terrainDuration.to_i rescue 0)
        },
        "turn" => (battle.turnCount.to_i rescue 0)
      }
    rescue
      {
        "battlers"  => [],
        "positions" => [],
        "sides"     => [],
        "field"     => { "effects" => [] }
      }
    end

    def apply_remote_field_state(battle, field_state)
      return unless battle && field_state.is_a?(Hash)
      w = field_state["weather"].to_s
      battle.field.weather = (w.empty? || w == "None") ? :None : (w.to_sym rescue :None)
      battle.field.weatherDuration = field_state["weather_duration"].to_i
      t = field_state["terrain"].to_s
      battle.field.terrain = (t.empty? || t == "None") ? :None : (t.to_sym rescue :None)
      battle.field.terrainDuration = field_state["terrain_duration"].to_i
    rescue => e
      AnilLanRework.log("apply_remote_field_state error #{e.class}: #{e.message}")
    end

    def send_battle_status_snapshot(battle)
      return unless @active_context && AnilLanRework.connected? && battle
      snapshot = serialize_coop_status_snapshot(battle)
      payload = {
        "to_id"               => @active_context.partner_id,
        "battle_id"           => @active_context.battle_id,
        "sender_client_index" => @active_context.client_index.to_i
      }.merge(snapshot)
      AnilLanRework.log("SEND battle_status_event battle_id=#{@active_context.battle_id} battlers=#{Array(snapshot['battlers']).length} positions=#{Array(snapshot['positions']).length} sides=#{Array(snapshot['sides']).length} field_effects=#{Array(snapshot.dig('field', 'effects')).length}")
      AnilLanRework.connection.send_packet("battle_status_event", payload)
    end

    def canonical_hash_value(value)
      case value
      when Hash
        "{" + value.keys.sort_by { |key| key.to_s }.map { |key| "#{key}=#{canonical_hash_value(value[key])}" }.join("|") + "}"
      when Array
        "[" + value.map { |entry| canonical_hash_value(entry) }.join(",") + "]"
      when NilClass
        "nil"
      when TrueClass
        "true"
      when FalseClass
        "false"
      else
        value.to_s
      end
    end

    def fnv1a32(str)
      hash = 0x811C9DC5
      str.to_s.each_byte do |byte|
        hash ^= byte
        hash = (hash * 0x01000193) & 0xFFFFFFFF
      end
      hash
    end

    def serialize_pvp_battler_state(battler)
      stages = (battler.stages rescue {})
      {
        "battler"      => battler.index.to_i,
        "pokemon_idx"  => (battler.pokemonIndex.to_i rescue -1),
        "species"      => (battler.species.to_s rescue ""),
        "form"         => (battler.form.to_i rescue 0),
        "level"        => (battler.level.to_i rescue 0),
        "hp"           => (battler.hp.to_i rescue 0),
        "totalhp"      => (battler.totalhp.to_i rescue 0),
        "status"       => ((battler.status || :NONE).to_s rescue "NONE"),
        "status_count" => (battler.statusCount.to_i rescue 0),
        "ability"      => (battler.ability_id.to_s rescue battler.ability.to_s rescue ""),
        "item"         => (battler.item_id.to_s rescue battler.item.to_s rescue ""),
        "stages"       => stages.keys.map(&:to_s).sort.map { |key| [key, stages[key.to_sym] || stages[key]] },
        "effects"      => serialize_effect_entries(:battler, battler.effects, battler),
        "moves"        => Array(battler.moves).map do |move|
          {
            "id"   => (move&.id.to_s rescue ""),
            "pp"   => (move&.pp.to_i rescue 0),
            "ppup" => (move&.ppup.to_i rescue 0)
          }
        end
      }
    rescue => e
      AnilLanRework.log("serialize_pvp_battler_state error #{e.class}: #{e.message}")
      { "battler" => (battler&.index.to_i rescue -1), "error" => e.class.name.to_s }
    end

    def serialize_pvp_turn_state(battle)
      {
        "turn"      => (battle.turnCount.to_i rescue 0),
        "decision"  => (battle.decision.to_i rescue 0),
        "battlers"  => battle.battlers.compact.map { |battler| serialize_pvp_battler_state(battler) },
        "positions" => Array(battle.positions).each_with_index.map { |position, index| { "position" => index, "effects" => serialize_effect_entries(:position, position.effects) } },
        "sides"     => Array(battle.sides).each_with_index.map { |side, index| { "side" => index, "effects" => serialize_effect_entries(:side, side.effects) } },
        "field"     => { "effects" => serialize_effect_entries(:field, battle.field.effects) }
      }
    rescue => e
      AnilLanRework.log("serialize_pvp_turn_state error #{e.class}: #{e.message}")
      { "turn" => (battle.turnCount.to_i rescue 0), "error" => e.class.name.to_s }
    end

    def pvp_turn_state_hash(battle)
      fnv1a32(canonical_hash_value(serialize_pvp_turn_state(battle)))
    end

    def send_pvp_turn_hash(battle)
      return nil unless battle && @active_context && @active_context.mode == :pvp && AnilLanRework.connected?
      turn = battle.turnCount.to_i
      state_hash = pvp_turn_state_hash(battle)
      AnilLanRework.connection.send_packet("battle_turn_hash",
        "to_id"      => @active_context.partner_id,
        "battle_id"  => @active_context.battle_id,
        "turn"       => turn,
        "state_hash" => state_hash
      )
      state_hash
    end

    def queue_remote_turn_hash(packet)
      return unless packet.is_a?(Hash)
      battle_id = packet["battle_id"].to_s
      if @active_context && battle_id == @active_context.battle_id
        @active_context.pending_turn_hashes << packet
      else
        (@buffered_turn_hashes[battle_id] ||= []) << packet
      end
    end

    def next_remote_turn_hash(expected_turn = nil)
      return nil unless @active_context
      return @active_context.pending_turn_hashes.shift if expected_turn.nil?
      
      # Usar uma fila priorizada baseada em turno e sequência
      index = @active_context.pending_turn_hashes.index { |packet| packet["turn"].to_i == expected_turn.to_i }
      
      if index
        # Remover e retornar o pacote encontrado
        packet = @active_context.pending_turn_hashes.delete_at(index)
        
        # Se encontramos o pacote esperado, também processar pacotes anteriores que possam estar atrasados
        process_delayed_packets(expected_turn)
        
        return packet
      end
      
      nil
    end

    def process_delayed_packets(current_turn)
      # Processar pacotes de turnos anteriores que possam ter chegado atrasados
      delayed_packets = @active_context.pending_turn_hashes.select { |packet|
        packet["turn"].to_i < current_turn.to_i
      }
      
      delayed_packets.each do |delayed_packet|
        AnilLanRework.log("processing delayed packet turn=#{delayed_packet['turn']} current=#{current_turn}")
        # Processar o pacote atrasado
        @active_context.pending_turn_hashes.delete(delayed_packet)
      end
    end

    def process_delayed_turn_packets(current_turn)
      # Processar pacotes de turnos anteriores que possam ter chegado atrasados (para turns)
      delayed_packets = @active_context.pending_turns.select { |packet|
        packet["turn"].to_i < current_turn.to_i
      }
      
      delayed_packets.each do |delayed_packet|
        AnilLanRework.log("processing delayed turn packet turn=#{delayed_packet['turn']} current=#{current_turn}")
        # Processar o pacote atrasado
        @active_context.pending_turns.delete(delayed_packet)
      end
    end

    def check_future_turn_packets(expected_turn)
      return nil unless @active_context
      
      # Verificar se temos pacotes de turnos futuros
      future_packets = @active_context.pending_turn_hashes.select { |packet|
        packet["turn"].to_i > expected_turn.to_i
      }
      
      future_packets.first
    end

    def calculate_adaptive_timeout(retries)
      base_timeout = AnilLanRework::TURN_TIMEOUT
      # Aumentar timeout se estamos tendo problemas
      base_timeout * (1 + retries * 0.5)
    end

    def wait_for_remote_turn_hash(expected_turn, max_retries = 3)
      retries = 0
      
      begin
        started = Time.now.to_f
        viewport, window = build_wait_window(wait_text_for_turn_hash)
        
        loop do
          pump_network
          
          # Tentar obter o pacote esperado
          packet = next_remote_turn_hash(expected_turn)
          return packet if packet
          
          # Se não conseguimos o pacote esperado, verificar se temos pacotes de turnos futuros
          future_packet = check_future_turn_packets(expected_turn)
          if future_packet
            AnilLanRework.log("future packet received early, buffering turn=#{future_packet['turn']} expected=#{expected_turn}")
            return nil # Sinalizar que precisamos esperar mais
          end
          
          return nil unless AnilLanRework.connected?
          
          # Timeout adaptativo - aumentar se estamos tendo problemas de rede
          timeout = calculate_adaptive_timeout(retries)
          return nil if Time.now.to_f - started >= timeout
          
          Graphics.update
          Input.update
          window.update rescue nil
        end
      ensure
        dispose_wait_window(viewport, window)
      end
    end

    def verify_battle_state_integrity(battle, turn)
      return true unless battle && @active_context && @active_context.mode == :pvp
      
      # Calcular hash do estado atual
      current_hash = calculate_battle_state_hash(battle)
      
      # Verificar se o estado está consistente
      expected_hash = @expected_battle_hashes[turn] if @expected_battle_hashes
      
      if expected_hash && current_hash != expected_hash
        AnilLanRework.log("battle state integrity check failed turn=#{turn} expected=#{expected_hash} current=#{current_hash}")
        
        # Tentar recuperar o estado
        recover_battle_state_integrity(battle, turn)
        return false
      end
      
      # Armazenar hash esperado para comparações futuras
      @expected_battle_hashes ||= {}
      @expected_battle_hashes[turn] = current_hash
      
      true
    end

    def calculate_battle_state_hash(battle)
      # Calcular um hash simples do estado da batalha
      # Isso pode ser expandido para incluir mais detalhes do estado
      state_string = ""
      
      # Adicionar informações básicas dos battlers
      battle.battlers.each_with_index do |battler, index|
        next unless battler
        state_string += "#{index}:#{battler.hp}:#{battler.status}:#{battler.species}"
      end
      
      # Adicionar turno atual
      state_string += "turn:#{battle.turnCount}"
      
      # Gerar hash simples
      state_string.hash
    end

    def recover_battle_state_integrity(battle, turn)
      # Função para tentar recuperar o estado da batalha quando há inconsistência
      AnilLanRework.log("attempting to recover battle state integrity turn=#{turn}")
      
      # Limpar buffers que podem estar inconsistentes
      @pending_hp_syncs = {}
      @pvp_hp_sync_out_seq = {}
      @pvp_hp_sync_applied = {}
      
      # Solicitar snapshot do estado se estivermos em modo PvP
      if @active_context && @active_context.mode == :pvp && AnilLanRework.connected?
        send_battle_status_snapshot(battle)
      end
    end

    def verify_pvp_turn_hash!(battle)
      return true unless battle && @active_context && @active_context.mode == :pvp && AnilLanRework.connected?
      turn = battle.turnCount.to_i
      
      # Verificar integridade do estado antes de processar
      return false unless verify_battle_state_integrity(battle, turn)
      
      local_hash = send_pvp_turn_hash(battle)
      packet = wait_for_remote_turn_hash(turn)
      return false unless packet
      remote_hash = packet["state_hash"].to_i & 0xFFFFFFFF
      return true if remote_hash == local_hash
      AnilLanRework.log("pvp turn hash mismatch battle_id=#{@active_context.battle_id} turn=#{turn} local=#{local_hash} remote=#{remote_hash}")
      recover_pvp_state_after_hash_mismatch(battle, turn)
      battle.pbDisplayBrief(_INTL("Dessincronizacao detectada no turno {1}.", turn)) rescue nil
      false
    end

    def recover_pvp_state_after_hash_mismatch(battle, turn = nil)
      ctx = @active_context
      return unless battle && ctx && ctx.mode == :pvp && AnilLanRework.connected?
      if ctx.client_index.to_i == 0
        AnilLanRework.log("pvp mismatch recovery send snapshot battle_id=#{ctx.battle_id} turn=#{turn}")
        send_battle_status_snapshot(battle)
        return
      end
      started = Time.now.to_f
      loop do
        pump_network
        break if ctx.pending_status_events && !ctx.pending_status_events.empty?
        break if Time.now.to_f - started >= 1.0
        Graphics.update rescue nil
        Input.update rescue nil
      end
      if ctx.pending_status_events && !ctx.pending_status_events.empty?
        AnilLanRework.log("pvp mismatch recovery apply snapshot battle_id=#{ctx.battle_id} turn=#{turn}")
        flush_remote_status_events
      else
        AnilLanRework.log("pvp mismatch recovery snapshot timeout battle_id=#{ctx.battle_id} turn=#{turn}")
      end
    rescue => e
      AnilLanRework.log("recover_pvp_state_after_hash_mismatch error #{e.class}: #{e.message}")
    end

    def send_called_move_resolution(battle, idx_battler, move_id, resolved_target = nil)
      return unless battle && move_id
      ctx = @active_context
      return unless ctx && [:pvp, :coop].include?(ctx.mode) && AnilLanRework.connected?
      payload = {
        "to_id"         => ctx.partner_id,
        "battle_id"     => ctx.battle_id,
        "battler"       => idx_battler.to_i,
        "source_move"   => "METRONOME",
        "resolved_move" => move_id.to_s,
        "sender_client_index" => ctx.client_index.to_i
      }
      payload["rng"] = ctx.rng.snapshot if ctx.rng
      payload["resolved_target"] = resolved_target if !resolved_target.nil?
      AnilLanRework.log("SEND battle_called_move battle_id=#{ctx.battle_id} battler=#{idx_battler} move=#{move_id} target=#{resolved_target.inspect} rng=#{payload['rng'].inspect}")
      AnilLanRework.connection.send_packet("battle_called_move", payload)
    end

    def serialize_called_move_target(battle, idx_battler, move_id)
      return nil unless battle && move_id
      battler = battle.battlers[idx_battler.to_i] rescue nil
      return nil unless battler
      move = Battle::Move.from_pokemon_move(battle, Pokemon::Move.new(move_id))
      return nil unless move
      choice = [:UseMove, -1, move, -1]
      rng_snapshot = @active_context&.rng&.snapshot
      begin
        targets = battler.pbFindTargets(choice, move, battler)
      ensure
        @active_context&.rng&.restore(rng_snapshot) if rng_snapshot
      end
      target_index = targets&.first&.index
      serialize_remote_target(battle, idx_battler, target_index)
    rescue => e
      AnilLanRework.log("serialize_called_move_target error #{e}")
      nil
    end

    def send_coop_foe_turn(actions, rng_state = nil)
      return unless @active_context && @active_context.mode == :coop && AnilLanRework.connected?
      payload = {
        "to_id"     => @active_context.partner_id,
        "battle_id" => @active_context.battle_id,
        "actions"   => actions
      }
      payload["rng_state"] = rng_state if rng_state
      AnilLanRework.connection.send_packet("battle_foe_turn", payload)
    end

    def queue_remote_action(packet)
      return unless packet.is_a?(Hash)
      battle_id = packet["battle_id"].to_s
      AnilLanRework.log("coop queue action battle_id=#{battle_id} actions=#{Array(packet['actions']).inspect}")
      apply_embedded_party_sync(packet)
      packet_rng = packet["rng_state"] || packet["rng"]
      actions = Array(packet["actions"]).map do |action|
        if packet_rng && action.is_a?(Hash)
          action.merge("__anil_rng_state" => packet_rng)
        else
          action
        end
      end
      return if actions.empty?
      # A chave viaja junto do lote (o consumidor casa por ela).
      envelope = {
        "turn"    => (packet.key?("turn") ? packet["turn"].to_i : nil),
        "slot"    => (packet["slot"].nil? ? nil : packet["slot"].to_i),
        "actions" => actions
      }
      if @active_context && @active_context.battle_id == battle_id
        @active_context.pending_actions << envelope
      else
        (@buffered_actions[battle_id] ||= []) << envelope
      end
    end

    def queue_remote_foe_action(packet)
      return unless packet.is_a?(Hash)
      battle_id = packet["battle_id"].to_s
      battler = packet["battler"].to_i
      action = packet["action"]
      AnilLanRework.log("coop queue foe action battle_id=#{battle_id} battler=#{battler} kind=#{action.is_a?(Hash) ? action['kind'] : action.inspect}")
      if @active_context && @active_context.battle_id == battle_id
        @active_context.pending_foe_actions << packet
      else
        (@buffered_foe_actions[battle_id] ||= []) << packet
      end
    end

    def queue_remote_hp_event(packet)
      return unless packet.is_a?(Hash)
      battle_id = packet["battle_id"].to_s
      battler = packet["battler"].to_i
      kind = packet["hp_kind"].to_s
      translated_battler = battler
      if @active_context && @active_context.mode == :coop
        sender_client_index = if packet.key?("sender_client_index")
          packet["sender_client_index"].to_i
        else
          @active_context.client_index.to_i == 0 ? 1 : 0
        end
        translated_battler = if packet["battler_ref"].is_a?(Hash)
          resolve_coop_battler_reference(@active_context.battle, packet["battler_ref"], battler)
        else
          translate_coop_battler_index(
            battler,
            sender_client_index,
            @active_context.client_index.to_i,
            @active_context.battle
          )
        end
      end
      packet = packet.merge(
        "remote_battler" => battler,
        "battler"        => translated_battler
      )
      AnilLanRework.log("coop queue hp event battle_id=#{battle_id} battler=#{translated_battler} remote_battler=#{battler} kind=#{kind} old=#{packet['old_hp'].inspect} new=#{packet['new_hp'].inspect} delta=#{packet['delta'].inspect}")
      if @active_context && @active_context.battle_id == battle_id
        @active_context.pending_hp_events << packet
      else
        (@buffered_hp_events[battle_id] ||= []) << packet
      end
    end

    def queue_remote_status_event(packet)
      return unless packet.is_a?(Hash)
      battle_id = packet["battle_id"].to_s
      sender_client_index = if packet.key?("sender_client_index")
        packet["sender_client_index"].to_i
      elsif @active_context
        @active_context.client_index.to_i == 0 ? 1 : 0
      else
        0
      end
      packet = packet.merge("sender_client_index" => sender_client_index)
      AnilLanRework.log("coop queue status event battle_id=#{battle_id} battlers=#{Array(packet['battlers'] || packet['statuses']).length} positions=#{Array(packet['positions']).length} sides=#{Array(packet['sides']).length} field_effects=#{Array(packet.dig('field', 'effects')).length}")
      if @active_context && @active_context.battle_id == battle_id
        @active_context.pending_status_events << packet
      else
        (@buffered_status_events[battle_id] ||= []) << packet
      end
    end

    def queue_remote_text_step(packet)
      return unless packet.is_a?(Hash)
      battle_id = packet["battle_id"].to_s
      step = packet["step"].to_i
      packet = packet.merge("step" => step)
      if @active_context && @active_context.battle_id == battle_id
        @active_context.pending_text_steps << packet
      else
        (@buffered_text_steps[battle_id] ||= []) << packet
      end
    end

    def queue_remote_text_state(packet)
      return unless packet.is_a?(Hash)
      battle_id = packet["battle_id"].to_s
      step = packet["step"].to_i
      state = packet["state"].to_s
      return if step <= 0 || state.empty?
      packet = packet.merge("step" => step, "state" => state)
      if @active_context && @active_context.battle_id == battle_id
        @active_context.pending_text_states << packet
      else
        (@buffered_text_states[battle_id] ||= []) << packet
      end
    end

    def queue_remote_manual_lock(packet)
      return unless packet.is_a?(Hash)
      battle_id = packet["battle_id"].to_s
      if @active_context && @active_context.battle_id == battle_id
        apply_remote_manual_lock_packet(packet, @active_context)
      else
        @buffered_manual_locks[battle_id] = packet
      end
    rescue => e
      AnilLanRework.log("battle manual lock queue error #{e.class}: #{e.message}")
    end

    def consume_remote_text_steps(ctx = nil)
      ctx ||= @active_context
      return unless ctx
      ctx.pending_text_steps ||= []
      ctx.remote_text_packets ||= {}
      while !ctx.pending_text_steps.empty?
        packet = ctx.pending_text_steps.shift
        step = packet["step"].to_i
        next if step <= 0
        ctx.remote_text_packets[step] = packet
        if step > ctx.remote_text_step.to_i
          ctx.remote_text_step = step
          AnilLanRework.log("battle text step recv battle_id=#{ctx.battle_id} step=#{step}")
        end
      end
      min_step = ctx.remote_text_step.to_i - 6
      ctx.remote_text_packets.delete_if { |step, _packet| step.to_i < min_step } if min_step > 0
    end

    def consume_remote_text_states(ctx = nil)
      ctx ||= @active_context
      return unless ctx
      ctx.pending_text_states ||= []
      ctx.remote_text_states ||= {}
      while !ctx.pending_text_states.empty?
        packet = ctx.pending_text_states.shift
        step = packet["step"].to_i
        state = packet["state"].to_s
        next if step <= 0 || state.empty?
        ctx.remote_text_states[step] ||= {}
        ctx.remote_text_states[step][state] = packet
        AnilLanRework.log("battle text state recv battle_id=#{ctx.battle_id} step=#{step} state=#{state}")
      end
      min_step = [ctx.local_text_step.to_i, ctx.remote_text_step.to_i].max - 6
      ctx.remote_text_states.delete_if { |step, _states| step.to_i < min_step } if min_step > 0
    end

    def normalize_text_step_message(message)
      text = message.to_s.dup
      text.gsub!(/\\wt\[\d+\]/i, "")
      text.gsub!(/\s+/, " ")
      text.strip!
      text
    rescue
      message.to_s
    end

    def authoritative_text_sender?(ctx = nil)
      ctx ||= @active_context
      return false unless ctx
      ctx.client_index.to_i == 0
    end

    def anil_is_manual_message?(msg)
      m = normalize_text_step_message(msg).downcase
      return true if m.include?("subiu para o n")   # nível / nivel
      return true if m.include?("subiu ao nivel")
      return true if m.include?("subio al nivel")
      return true if m.include?("subió al nivel")
      return true if m.include?("aprendeu")
      return true if m.include?("aprendio")
      return true if m.include?("aprendió")
      return true if m.include?("tentando aprender")
      return true if m.include?("quiere aprender")
      return true if m.include?("deseja esquecer")
      return true if m.include?("quer esquecer")
      return true if m.include?("olvide un movimiento")
      return true if m.include?("esqueceu")
      return true if m.include?("olvido")
      return true if m.include?("olvidó")
      return true if m.include?("deixou de aprender")
      return true if m.include?("no aprendio")
      return true if m.include?("no aprendió")
      false
    end

    def anil_is_fugitive_message?(msg)
      normalized = normalize_text_step_message(msg).downcase
      return false if normalized.empty?
      LAN_FUGITIVE_TEXT_FRAGMENTS.any? { |fragment| normalized.include?(fragment) }
    rescue
      false
    end

    def anil_should_skip_local_battle_message?(msg, ctx = nil)
      ctx ||= @active_context
      return false unless ctx && ctx.mode == :coop
      anil_is_fugitive_message?(msg)
    rescue
      false
    end

    def sync_message_step(message = nil)
      ctx = @active_context
      return message unless ctx && [:pvp, :coop].include?(ctx.mode) && AnilLanRework.connected?
      return message if coop_remote_sync_disabled?(ctx)
      if anil_should_skip_local_battle_message?(message, ctx)
        preview = normalize_text_step_message(message)[0, 80]
        AnilLanRework.log("battle fugitive text suppressed battle_id=#{ctx.battle_id} msg=#{preview.inspect}")
        return :__anil_skip_local_message__
      end
      consume_remote_text_steps(ctx)
      ctx.local_text_step = ctx.local_text_step.to_i + 1
      local_step = ctx.local_text_step.to_i
      resolved_message = message
      normalized_message = normalize_text_step_message(message)
      preview = normalized_message[0, 60]
      AnilLanRework.connection.send_packet("battle_text_step",
        "to_id"     => ctx.partner_id,
        "battle_id" => ctx.battle_id,
        "step"      => local_step,
        "message"   => message.to_s,
        "msg_key"   => normalized_message
      )
      AnilLanRework.log("battle text step send battle_id=#{ctx.battle_id} step=#{local_step} msg=#{preview}")
      minimum_remote_step = local_step - text_lead_limit(ctx)
      return resolved_message if minimum_remote_step <= 0
      started = Time.now.to_f
      while ctx.remote_text_step.to_i < minimum_remote_step
        break unless AnilLanRework.connected?
        break if Time.now.to_f - started >= AnilLanRework::LAN_BATTLE_TEXT_SYNC_TIMEOUT
        pump_network
        flush_remote_party_refresh
        flush_remote_status_events
        consume_remote_text_steps(ctx)
        Graphics.update
        Input.update
      end
      remote_packet = ctx.remote_text_packets[local_step] rescue nil
      if remote_packet
        remote_key = remote_packet["msg_key"].to_s
        remote_message = remote_packet["message"].to_s
        if !normalized_message.empty? && !remote_key.empty? && remote_key != normalized_message
          AnilLanRework.log(
            "battle text step mismatch battle_id=#{ctx.battle_id} step=#{local_step} " \
            "local=#{normalized_message.inspect} remote=#{remote_key.inspect}"
          )
          if ctx.mode == :coop
            side = authoritative_text_sender?(ctx) ? "remote_fugitive_or_divergent" : "local_fugitive_or_divergent"
            AnilLanRework.log("battle text mismatch classified battle_id=#{ctx.battle_id} step=#{local_step} side=#{side}")
          end
          if ctx.mode == :coop && !authoritative_text_sender?(ctx) && !remote_message.empty?
            resolved_message = remote_message
          end
        end
      elsif ctx.mode == :coop
        AnilLanRework.log(
          "battle text missing remote step battle_id=#{ctx.battle_id} step=#{local_step} " \
          "authoritative=#{authoritative_text_sender?(ctx)} local=#{normalized_message.inspect}"
        )
      end
      resolved_message
    rescue => e
      AnilLanRework.log("battle text sync error #{e.class}: #{e.message}")
      message
    end

    def sync_text_display_state(step, state, kind = nil, wait_for_remote = true)
      ctx = @active_context
      return true unless ctx && [:pvp, :coop].include?(ctx.mode) && AnilLanRework.connected?
      return true if coop_remote_sync_disabled?(ctx)
      step = step.to_i
      state = state.to_s
      kind = kind.to_s
      return true if step <= 0 || state.empty?
      consume_remote_text_states(ctx)
      AnilLanRework.connection.send_packet("battle_text_state",
        "to_id"     => ctx.partner_id,
        "battle_id" => ctx.battle_id,
        "step"      => step,
        "state"     => state,
        "kind"      => kind
      )
      AnilLanRework.log("battle text state send battle_id=#{ctx.battle_id} step=#{step} state=#{state} kind=#{kind}")
      return true unless wait_for_remote
      started = Time.now.to_f
      while !(ctx.remote_text_states[step] && ctx.remote_text_states[step][state])
        break unless AnilLanRework.connected?
        break if Time.now.to_f - started >= AnilLanRework::LAN_BATTLE_TEXT_SYNC_TIMEOUT
        pump_network
        flush_remote_party_refresh
        flush_remote_status_events
        consume_remote_text_steps(ctx)
        consume_remote_text_states(ctx)
        Graphics.update
        Input.update
      end
      synced = !!(ctx.remote_text_states[step] && ctx.remote_text_states[step][state])
      if !synced
        AnilLanRework.log("battle text state timeout battle_id=#{ctx.battle_id} step=#{step} state=#{state} kind=#{kind}")
      end
      synced
    rescue => e
      AnilLanRework.log("battle text state sync error #{e.class}: #{e.message}")
      true
    end

    def remote_text_state_synced?(step, state, ctx = nil)
      ctx ||= @active_context
      return false unless ctx
      step = step.to_i
      state = state.to_s
      return false if step <= 0 || state.empty?
      consume_remote_text_states(ctx)
      !!(ctx.remote_text_states[step] && ctx.remote_text_states[step][state])
    rescue
      false
    end

    def queue_remote_capture_result(packet)
      return unless packet.is_a?(Hash)
      battle_id = packet["battle_id"].to_s
      battler = packet["battler"].to_i
      AnilLanRework.log("coop queue capture result battle_id=#{battle_id} battler=#{battler} shakes=#{packet['num_shakes'].inspect} critical=#{packet['critical'].inspect}")
      if @active_context && @active_context.battle_id == battle_id
        @active_context.pending_capture_results << packet
      else
        (@buffered_capture_results[battle_id] ||= []) << packet
      end
    end

    def queue_remote_called_move(packet)
      return unless packet.is_a?(Hash)
      battle_id = packet["battle_id"].to_s
      battler = packet["battler"].to_i
      translated_battler = battler
      if @active_context && [:pvp, :coop].include?(@active_context.mode)
        sender_client_index = if packet.key?("sender_client_index")
          packet["sender_client_index"].to_i
        else
          @active_context.client_index.to_i == 0 ? 1 : 0
        end
        translated_battler = translate_remote_battler_index(
          battler,
          sender_client_index,
          @active_context.battle
        )
      end
      packet = packet.merge(
        "remote_battler" => battler,
        "battler"        => translated_battler
      )
      local_rng = @active_context&.rng&.snapshot rescue nil
      AnilLanRework.log("coop queue called move battle_id=#{battle_id} battler=#{translated_battler} remote_battler=#{battler} move=#{packet['resolved_move']} target=#{packet['resolved_target'].inspect} packet_rng=#{packet['rng'].inspect} local_rng=#{local_rng.inspect}")
      if @active_context && @active_context.battle_id == battle_id
        @active_context.pending_called_moves << packet
      else
        (@buffered_called_moves[battle_id] ||= []) << packet
      end
    end

    def queue_remote_foe_turn(packet)
      return unless packet.is_a?(Hash)
      battle_id = packet["battle_id"].to_s
      action_count = Array(packet["actions"]).length
      AnilLanRework.log("coop queue foe turn battle_id=#{battle_id} count=#{action_count}")
      if @active_context && @active_context.battle_id == battle_id
        @active_context.pending_foe_turns << packet
      else
        (@buffered_foe_turns[battle_id] ||= []) << packet
      end
    end

    # expected_slot vem na perspectiva de QUEM ESPERA; o remetente mandou o
    # indice na perspectiva DELE, entao traduzimos antes de comparar.
    def next_remote_action(expected_turn = nil, expected_slot = nil)
      ctx = @active_context
      return nil unless ctx
      fila = ctx.pending_actions
      return nil if fila.nil? || fila.empty?

      # Compatibilidade: envelope antigo (Array puro) ou sem chave -> FIFO.
      idx = fila.index do |env|
        next true unless env.is_a?(Hash)
        t = env["turn"]
        s = env["slot"]
        casa_turno = expected_turn.nil? || t.nil? || t.to_i == expected_turn.to_i
        casa_slot  = true
        if !expected_slot.nil? && !s.nil?
          traduzido = (translate_remote_battler_index(s.to_i, nil, ctx.battle) rescue s.to_i)
          casa_slot = (traduzido.to_i == expected_slot.to_i)
        end
        casa_turno && casa_slot
      end

      if idx.nil?
        # Nada casa. Se ha lixo de turno ANTIGO na fila, joga fora agora: manter
        # e o que produz o off-by-one permanente.
        if !expected_turn.nil?
          antes = fila.length
          fila.reject! { |env| env.is_a?(Hash) && !env["turn"].nil? && env["turn"].to_i < expected_turn.to_i }
          if fila.length != antes
            AnilLanRework.log("coop acao: descartados #{antes - fila.length} pacote(s) de turno anterior a #{expected_turn}")
          end
        end
        return nil
      end

      env = fila.delete_at(idx)
      env.is_a?(Hash) ? env["actions"] : env
    end

    def next_remote_foe_action(idx_battler = nil)
      return nil unless @active_context
      return @active_context.pending_foe_actions.shift if idx_battler.nil?
      index = @active_context.pending_foe_actions.index { |packet| packet["battler"].to_i == idx_battler.to_i }
      index ? @active_context.pending_foe_actions.delete_at(index) : nil
    end

    def next_remote_hp_event(idx_battler = nil, hp_kind = nil)
      return nil unless @active_context
      return @active_context.pending_hp_events.shift if idx_battler.nil? && hp_kind.nil?
      index = @active_context.pending_hp_events.index do |packet|
        battler_match = idx_battler.nil? || packet["battler"].to_i == idx_battler.to_i
        kind_match = hp_kind.nil? || packet["hp_kind"].to_s == hp_kind.to_s
        battler_match && kind_match
      end
      index ? @active_context.pending_hp_events.delete_at(index) : nil
    end

    def pending_remote_hp_event_for_other_battler?(idx_battler, hp_kind = nil)
      return false unless @active_context
      @active_context.pending_hp_events.any? do |packet|
        next false if hp_kind && packet["hp_kind"].to_s != hp_kind.to_s
        packet["battler"].to_i != idx_battler.to_i
      end
    rescue
      false
    end

    def pending_remote_hp_event_summary
      return "" unless @active_context
      @active_context.pending_hp_events.map do |packet|
        "#{packet['battler']}:#{packet['hp_kind']}:#{packet['old_hp']}->#{packet['new_hp']}"
      end.join(",")
    rescue
      ""
    end

    def pending_remote_hp_event_for_battler?(idx_battler, hp_kind = nil)
      return false unless @active_context
      @active_context.pending_hp_events.any? do |packet|
        battler_match = packet["battler"].to_i == idx_battler.to_i
        kind_match = hp_kind.nil? || packet["hp_kind"].to_s == hp_kind.to_s
        battler_match && kind_match
      end
    rescue
      false
    end

    def extract_valid_remote_hp_event(idx_battler, hp_kind)
      loop do
        packet = next_remote_hp_event(idx_battler, hp_kind)
        return nil unless packet
        battle = @active_context&.battle
        battler = battle&.battlers&.[](idx_battler.to_i) rescue nil
        if battler && packet.key?("old_hp") && battler.hp.to_i != packet["old_hp"].to_i
          # No modo COOP, permitimos divergência de HP para evitar travamentos de 30 segundos,
          # pois o próprio pacote irá reconciliar e corrigir o HP do parceiro.
          if @active_context && @active_context.mode == :coop
            AnilLanRework.log("coop hp mismatch resolved battle_id=#{@active_context.battle_id} battler=#{idx_battler} current=#{battler.hp.to_i} packet_old=#{packet['old_hp'].to_i} -> Reconciling!")
            return packet
          end

          AnilLanRework.log("coop stale hp event detected battle_id=#{@active_context&.battle_id} battler=#{idx_battler} kind=#{hp_kind} current=#{battler.hp.to_i} packet_old=#{packet['old_hp'].to_i} packet_new=#{packet['new_hp'].to_i}")
          
          # Em vez de descartar, tentar bufferizar o pacote para reordenação
          if packet["turn"] && packet["seq"]
            buffer_out_of_order_hp_packet(packet)
          end
          
          next
        end
        return packet
      end
    end

    def next_remote_foe_turn
      return nil unless @active_context
      @active_context.pending_foe_turns.shift
    end

    def next_remote_called_move(idx_battler = nil)
      return nil unless @active_context
      return @active_context.pending_called_moves.shift if idx_battler.nil?
      index = @active_context.pending_called_moves.index do |packet|
        packet["battler"].to_i == idx_battler.to_i
      end
      index ? @active_context.pending_called_moves.delete_at(index) : nil
    end

    def next_remote_capture_result(idx_battler = nil)
      return nil unless @active_context
      return @active_context.pending_capture_results.shift if idx_battler.nil?
      index = @active_context.pending_capture_results.index do |packet|
        packet["battler"].to_i == idx_battler.to_i
      end
      index ? @active_context.pending_capture_results.delete_at(index) : nil
    end

    def wait_for_remote_actions(waiting_text = nil, timeout_override = nil, expected_turn = nil, expected_slot = nil)
      return nil if coop_remote_sync_disabled?(@active_context)
      # Parceiro eliminado (mesmo assistindo) não envia ações
      return nil if remote_coop_eliminated_marked?(@active_context)
      started = Time.now.to_f
      viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
      viewport.z = 99_999
      base_text = waiting_text || "Aguardando parceiro..."
      window = Window_UnformattedTextPokemon.newWithSize(base_text, 0, 0, Graphics.width, 64, viewport)
      window.y = (Graphics.height - window.height) / 2
      lock_text = manual_wait_text
      lock_active = false
      begin
        loop do
          actions = next_remote_action(expected_turn, expected_slot)
          return actions if actions
          return nil unless AnilLanRework.connected?

          lock_active = remote_manual_lock?
          if lock_active
            started = Time.now.to_f
            window.text = lock_text if window
          elsif window && window.text != base_text
            window.text = base_text
          end

          # timeout_override: usado quando o slot remoto esta TRAVADO (golpe de
          # duas fases, recarga, Outrage...). Nesse caso nao ha humano escolhendo
          # do outro lado — o parceiro auto-escolhe na hora —, entao esperar
          # 60s por um pacote que nao vem so congela a batalha. Com escolha
          # humana o timeout longo continua valendo: o jogador pode demorar.
          limite = timeout_override || (
            (@active_context && @active_context.mode == :coop) ?
              AnilLanRework::COOP_COMMAND_TIMEOUT :
              AnilLanRework::TURN_TIMEOUT
          )
          return nil if Time.now.to_f - started >= limite
          AnilLanRework.connection.tick
          AnilLanRework.connection.drain { |packet| AnilLanRework::Router.route_packet(packet) }
          flush_remote_party_refresh
          flush_remote_status_events
          Graphics.update
          Input.update
          window.update rescue nil
        end
      ensure
        window.dispose rescue nil
        viewport.dispose rescue nil
      end
    end

    def wait_for_remote_foe_action(idx_battler, waiting_text = nil)
      started = Time.now.to_f
      viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
      viewport.z = 99_999
      base_text = waiting_text || "Sincronizando inimigo..."
      window = Window_UnformattedTextPokemon.newWithSize(base_text, 0, 0, Graphics.width, 64, viewport)
      window.y = (Graphics.height - window.height) / 2
      lock_text = manual_wait_text
      lock_active = false
      begin
        loop do
          packet = next_remote_foe_action(idx_battler)
          return packet if packet
          return nil unless AnilLanRework.connected?

          lock_active = remote_manual_lock?
          if lock_active
            started = Time.now.to_f
            window.text = lock_text if window
          elsif window && window.text != base_text
            window.text = base_text
          end

          return nil if Time.now.to_f - started >= AnilLanRework::TURN_TIMEOUT
          AnilLanRework.connection.tick
          AnilLanRework.connection.drain { |remote_packet| AnilLanRework::Router.route_packet(remote_packet) }
          flush_remote_party_refresh
          flush_remote_status_events
          Graphics.update
          Input.update
          window.update rescue nil
        end
      ensure
        window.dispose rescue nil
        viewport.dispose rescue nil
      end
    end

    def wait_for_remote_hp_event(idx_battler, hp_kind)
      started = Time.now.to_f
      loop do
        packet = extract_valid_remote_hp_event(idx_battler, hp_kind)
        return packet if packet
        return nil unless AnilLanRework.connected?

        started = Time.now.to_f if remote_manual_lock?

        return nil if Time.now.to_f - started >= AnilLanRework::TURN_TIMEOUT
        AnilLanRework.connection.tick
        AnilLanRework.connection.drain { |remote_packet| AnilLanRework::Router.route_packet(remote_packet) }
        flush_remote_party_refresh
        flush_remote_status_events
        packet = extract_valid_remote_hp_event(idx_battler, hp_kind)
        return packet if packet
        if @active_context && !@active_context.pending_status_events.empty?
          AnilLanRework.log("battle hp wait skip by status battle_id=#{@active_context&.battle_id} battler=#{idx_battler} kind=#{hp_kind}")
          return :authoritative_none
        end
        Graphics.update
        Input.update rescue nil
      end
    end

    def wait_for_remote_foe_turn
      started = Time.now.to_f
      base_text = "Sincronizando inimigos..."
      viewport, window = build_wait_window(base_text)
      lock_text = manual_wait_text
      lock_active = false
      loop do
        pump_network
        return nil if @active_context && @active_context.instance_variable_get(:@anil_battle_end_received) == true
        packet = next_remote_foe_turn
        return packet if packet
        return nil unless AnilLanRework.connected?

        lock_active = remote_manual_lock?
        if lock_active
          started = Time.now.to_f
          window.text = lock_text if window
        elsif window && window.text != base_text
          window.text = base_text
        end

        return nil if Time.now.to_f - started >= AnilLanRework::TURN_TIMEOUT
        pump_network
        Graphics.update
        Input.update
        window.update rescue nil
      end
    ensure
      dispose_wait_window(viewport, window)
    end

    def wait_for_remote_called_move(idx_battler)
      started = Time.now.to_f
      loop do
        packet = next_remote_called_move(idx_battler)
        return packet if packet
        return nil unless AnilLanRework.connected?

        started = Time.now.to_f if remote_manual_lock?

        return nil if Time.now.to_f - started >= AnilLanRework::TURN_TIMEOUT
        pump_network
        flush_remote_party_refresh
        flush_remote_status_events
        consume_remote_text_steps(@active_context)
        Graphics.update rescue nil
        Input.update rescue nil
      end
    end

    def wait_for_remote_capture_result(idx_battler)
      started = Time.now.to_f
      loop do
        packet = next_remote_capture_result(idx_battler)
        return packet if packet
        return nil unless AnilLanRework.connected?

        started = Time.now.to_f if remote_manual_lock?

        return nil if Time.now.to_f - started >= AnilLanRework::TURN_TIMEOUT
        pump_network
        flush_remote_party_refresh
        flush_remote_status_events
        consume_remote_text_steps(@active_context)
        Graphics.update rescue nil
        Input.update rescue nil
      end
    end

    def coop_slots_for(battle)
      ally_indices = battle.battlers.compact.map(&:index).select do |slot|
        !(battle.opposes?(slot) rescue true)
      end
      ally_indices = ally_indices.sort
      if @active_context && @active_context.mode == :coop && ally_indices.length >= 2
        # In the local battle view, this client's active battler is always rendered
        # in the first ally slot, while the injected partner occupies the second.
        local_slot = ally_indices.first
        remote_slot = ally_indices[1]
        return [local_slot, remote_slot]
      end

      local_slot = ally_indices.find { |slot| battle.pbOwnedByPlayer?(slot) rescue false }
      local_slot ||= begin
        battle.pbOwnedByPlayer?(0) ? 0 : 2
      rescue
        [0, 2].find { |slot| battle.pbOwnedByPlayer?(slot) rescue false } || ally_indices.first || 0
      end
      remote_slot = ally_indices.find { |slot| slot != local_slot }
      [local_slot, remote_slot]
    end

    def translate_coop_battler_index(index, from_client_index, to_client_index, battle = nil)
      idx = index.to_i
      return idx if from_client_index.to_i == to_client_index.to_i

      ally_indices = if battle
        battle.battlers.compact.map(&:index).select { |slot| !(battle.opposes?(slot) rescue true) }.sort
      else
        [0, 2]
      end
      return idx unless ally_indices.length >= 2 && ally_indices.include?(idx)

      ally_indices.find { |slot| slot != idx } || idx
    rescue
      idx
    end

    def translate_remote_battler_index(index, from_client_index = nil, battle = nil)
      idx = index.to_i
      ctx = @active_context
      return idx unless ctx

      sender_client_index = if from_client_index.nil?
        ctx.client_index.to_i == 0 ? 1 : 0
      else
        from_client_index.to_i
      end

      case ctx.mode
      when :coop
        translate_coop_battler_index(idx, sender_client_index, ctx.client_index.to_i, battle || ctx.battle)
      when :pvp
        return idx if sender_client_index == ctx.client_index.to_i
        AnilLanRework::CableOrder.flip_index(idx)
      else
        idx
      end
    rescue
      idx
    end

    def coop_slots_debug(battle)
      battle.battlers.compact.map do |battler|
        idx = battler.index
        side = (battle.opposes?(idx) rescue false) ? "foe" : ((battle.pbOwnedByPlayer?(idx) rescue false) ? "player" : "partner")
        name = (battler.pokemon&.name || battler.name rescue "?").to_s
        "#{idx}:#{side}:#{name}"
      end.join(", ")
    rescue
      ""
    end

    def coop_initiator_slot_for(battle)
      ctx = @active_context
      return nil unless ctx && ctx.mode == :coop
      local_slot, remote_slot = coop_slots_for(battle)
      return nil if local_slot.nil? || remote_slot.nil?
      ctx.client_index.to_i == 0 ? local_slot : remote_slot
    rescue
      nil
    end

    def coop_non_initiator_slot_for(battle)
      ctx = @active_context
      return nil unless ctx && ctx.mode == :coop
      local_slot, remote_slot = coop_slots_for(battle)
      return nil if local_slot.nil? || remote_slot.nil?
      ctx.client_index.to_i == 0 ? remote_slot : local_slot
    rescue
      nil
    end

    def local_battler_for_called_move?(battle, idx_battler)
      ctx = @active_context
      return false unless ctx && battle
      idx = idx_battler.to_i
      if ctx.mode == :coop
        is_foe = begin
          battle.opposes?(idx)
        rescue
          false
        end
        if is_foe
          return ctx.client_index.to_i == 0
        end
        local_slot, _remote_slot = coop_slots_for(battle)
        return idx == local_slot.to_i
      end
      battle.pbOwnedByPlayer?(idx) rescue false
    rescue
      false
    end

    def coop_target_identity_for(battle, idx_target)
      initiator_slot = coop_initiator_slot_for(battle)
      partner_slot = coop_non_initiator_slot_for(battle)
      return "coop_initiator" if !initiator_slot.nil? && idx_target.to_i == initiator_slot
      return "coop_partner" if !partner_slot.nil? && idx_target.to_i == partner_slot
      nil
    rescue
      nil
    end

    def coop_party_start_for(battle, idx_battler)
      ctx = @active_context
      return 0 unless ctx && ctx.mode == :coop
      return 0 if battle.opposes?(idx_battler) rescue true
      local_slot, remote_slot = coop_slots_for(battle)
      return 0 if idx_battler == local_slot
      return Array($player&.party).length if idx_battler == remote_slot
      0
    rescue
      0
    end

    def coop_relative_party_index_for(battle, idx_battler, idx_party)
      idx_party.to_i - coop_party_start_for(battle, idx_battler).to_i
    rescue
      idx_party.to_i
    end

    def coop_absolute_party_index_for(battle, idx_battler, idx_party)
      coop_party_start_for(battle, idx_battler).to_i + idx_party.to_i
    rescue
      idx_party.to_i
    end

    def serialize_coop_item_target(battle, idx_battler, battle_use, raw_target)
      return nil if raw_target.nil?
      case battle_use.to_i
      when 1, 2, 3
        if @active_context&.mode == :coop && !(battle.opposes?(idx_battler) rescue false)
          return {
            "kind"  => "party_relative",
            "index" => coop_relative_party_index_for(battle, idx_battler, raw_target)
          }
        end
        return raw_target.to_i
      when 4
        return serialize_remote_target(battle, idx_battler, raw_target)
      when 5
        idx = raw_target.to_i
        return idx if idx < 0
        return serialize_remote_target(battle, idx_battler, raw_target)
      else
        return raw_target.to_i
      end
    rescue
      raw_target
    end

    def resolve_coop_item_target(battle, idx_battler, battle_use, raw_target)
      return nil if raw_target.nil?
      case battle_use.to_i
      when 1, 2, 3
        if raw_target.is_a?(Hash) && raw_target["kind"].to_s == "party_relative"
          return coop_absolute_party_index_for(battle, idx_battler, raw_target["index"])
        end
        return raw_target.to_i
      when 4, 5
        return raw_target.to_i unless raw_target.is_a?(Hash)
        return resolve_remote_target(battle, idx_battler, raw_target)
      else
        return raw_target.to_i unless raw_target.is_a?(Hash)
        return resolve_remote_target(battle, idx_battler, raw_target)
      end
    rescue
      raw_target.is_a?(Hash) ? nil : raw_target.to_i
    end

    def serialize_coop_choice(battle, idx_battler)
      choice = battle.choices[idx_battler]
      return { "kind" => "None" } if !choice || choice[0] == :None
      if choice[0] == :UseMove
        target_index = normalized_choice_target_for_move(battle, idx_battler, choice[1].to_i, choice[3])
        if !target_index.nil? && target_index >= 0 && choice[3] != target_index
          battle.pbRegisterTarget(idx_battler, target_index) rescue nil
        end
        mega = false
        begin
          if (battle.pbRegisteredMegaEvolution?(idx_battler) rescue false)
            mega = true
          elsif battle.megaEvolution && (idx_battler >= 0)
            side = battle.battlers[idx_battler].idxOwnSide
            owner = battle.pbGetOwnerIndexFromBattlerIndex(idx_battler)
            mega = true if battle.megaEvolution[side] && battle.megaEvolution[side][owner] == idx_battler
          end
        rescue
          mega = false
        end
        return {
          "kind"       => "UseMove",
          "move_index" => choice[1].to_i,
          "choice_idx" => choice[1].to_i,
          "target"     => serialize_remote_target(battle, idx_battler, target_index),
          "mega"       => mega
        }
      elsif choice[0] == :SwitchOut
        switch_index = choice[1].to_i
        switch_relative = if (@active_context&.mode == :coop) && !(battle.opposes?(idx_battler) rescue false)
          coop_relative_party_index_for(battle, idx_battler, switch_index)
        end
        return {
          "kind"            => "SwitchOut",
          "switch_index"    => switch_index,
          "switch_relative" => switch_relative,
          "choice_idx"      => switch_index
        }
      elsif choice[0] == :UseItem
        item_id = choice[1]
        battle_use = begin
          GameData::Item.get(item_id).battle_use
        rescue
          0
        end
        return {
          "kind"       => "UseItem",
          "item"       => item_id.to_s,
          "battle_use" => battle_use.to_i,
          "target"     => serialize_coop_item_target(battle, idx_battler, battle_use, choice[2]),
          "move_index" => choice[3]
        }
      elsif choice[0] == :Run
        return { "kind" => "Run" }
      end
      { "kind" => "None" }
    end

    def serialize_remote_target(battle, idx_battler, target_index)
      return nil if target_index.nil?
      if target_index.is_a?(String)
        raw_target = target_index.strip
        return nil if raw_target.empty?
        return nil if raw_target !~ /\A-?\d+\z/
        idx = raw_target.to_i
      else
        idx = target_index.to_i
      end
      return nil if idx < 0
      return { "kind" => "self" } if idx == idx_battler
      if (@active_context&.mode == :coop) && (battle.opposes?(idx_battler) rescue false) &&
         (battle.opposes?(idx, idx_battler) rescue false)
        coop_kind = coop_target_identity_for(battle, idx)
        return { "kind" => coop_kind } if coop_kind
      end
      if (@active_context&.mode == :coop) && (battle.opposes?(idx, idx_battler) rescue false)
        return { "kind" => "coop_foe_index", "index" => idx }
      end
      if !battle.opposes?(idx, idx_battler)
        allies = ally_indices_for(battle, idx_battler)
        slot = allies.index(idx)
        return slot ? { "kind" => "ally", "slot" => slot } : nil
      end
      opposing = battle.pbGetOpposingIndicesInOrder(idx_battler)
      slot = opposing.index(idx)
      result = slot ? { "kind" => "foe", "slot" => slot } : nil
      if @active_context&.mode == :pvp && battle.pbSideSize(0) == 3 && battle.pbSideSize(1) == 3
        AnilLanRework.log("pvp triple serialize target battle_id=#{@active_context&.battle_id} battler=#{idx_battler} target=#{idx} opposing=#{opposing.inspect} result=#{result.inspect}")
      end
      return result
    rescue
      nil
    end

    def serialize_coop_battler_reference(battle, idx_battler)
      idx = idx_battler.to_i
      return { "kind" => "absolute", "index" => idx } unless @active_context&.mode == :coop && battle
      coop_kind = coop_target_identity_for(battle, idx)
      return { "kind" => coop_kind } if coop_kind
      if (battle.opposes?(idx) rescue false)
        return { "kind" => "coop_foe_index", "index" => idx }
      end
      { "kind" => "absolute", "index" => idx }
    rescue
      { "kind" => "absolute", "index" => idx_battler.to_i }
    end

    def resolve_coop_battler_reference(battle, reference, fallback = nil)
      return fallback if reference.nil?
      return fallback unless reference.is_a?(Hash)
      case reference["kind"].to_s
      when "absolute"
        reference["index"].to_i
      when "coop_initiator"
        coop_initiator_slot_for(battle)
      when "coop_partner"
        coop_non_initiator_slot_for(battle)
      when "coop_foe_index"
        reference["index"].to_i
      else
        fallback
      end
    rescue
      fallback
    end

    def resolve_remote_target(battle, idx_battler, target)
      return nil if target.nil?
      return target.to_i unless target.is_a?(Hash)
      result = case target["kind"].to_s
               when "absolute"
                 target["index"].to_i
               when "self"
                 idx_battler
               when "coop_initiator"
                 coop_initiator_slot_for(battle)
               when "coop_partner"
                 coop_non_initiator_slot_for(battle)
               when "coop_foe_index"
                 target["index"].to_i
               when "ally"
                 allies = ally_indices_for(battle, idx_battler)
                 allies[target["slot"].to_i]
               when "foe"
                 opposing = battle.pbGetOpposingIndicesInOrder(idx_battler)
                 opposing[target["slot"].to_i]
               else
                 nil
               end
      if @active_context&.mode == :pvp && battle.pbSideSize(0) == 3 && battle.pbSideSize(1) == 3
        AnilLanRework.log("pvp triple resolve target battle_id=#{@active_context&.battle_id} battler=#{idx_battler} target=#{target.inspect} result=#{result.inspect}")
      end
      result
    rescue
      nil
    end

    def normalize_target_index_value(target)
      return nil if target.nil?
      return target.index if target.respond_to?(:index)
      if target.is_a?(String)
        stripped = target.strip
        return nil if stripped.empty?
        return nil if stripped !~ /\A-?\d+\z/
        return stripped.to_i
      end
      target.to_i
    rescue
      nil
    end

    def normalized_choice_target_for_move(battle, idx_battler, move_index, raw_target)
      battler = battle.battlers[idx_battler] rescue nil
      move = begin
        registered_move = battle.choices[idx_battler][2] rescue nil
        registered_move || battler&.moves&.[](move_index)
      rescue
        battler&.moves&.[](move_index)
      end
      target_data = move&.pbTarget(battler)
      target_index = normalize_target_index_value(raw_target)
      return target_index if target_data.nil?
      return target_index if target_data.num_targets.to_i <= 0
      if !target_index.nil? && target_index >= 0 &&
         (battle.pbMoveCanTarget?(idx_battler, target_index, target_data) rescue false)
        return target_index
      end
      fallback_target = battle.battlers.compact.map(&:index).find do |candidate|
        battle.pbMoveCanTarget?(idx_battler, candidate, target_data) rescue false
      end
      if fallback_target && @active_context&.mode == :pvp
        AnilLanRework.log(
          "local move target normalized battle_id=#{@active_context&.battle_id} battler=#{idx_battler} move=#{move_index} " \
          "raw=#{raw_target.inspect} normalized=#{fallback_target}"
        )
      end
      fallback_target
    rescue => e
      AnilLanRework.log("normalized_choice_target_for_move error #{e.class}: #{e.message}")
      normalize_target_index_value(raw_target)
    end

    def resolved_remote_target_for_action(battle, idx_battler, action, move_index)
      target_index = resolve_remote_target(battle, idx_battler, action["target"])
      battler = battle.battlers[idx_battler] rescue nil
      move = battler&.moves&.[](move_index)
      target_data = begin
        registered_move = battle.choices[idx_battler][2] rescue nil
        registered_move ? registered_move.pbTarget(battler) : move&.pbTarget(battler)
      rescue
        move&.pbTarget(battler)
      end
      return target_index if target_data.nil?
      return target_index if target_data.num_targets.to_i <= 0
      if !target_index.nil? && target_index >= 0 &&
         (battle.pbMoveCanTarget?(idx_battler, target_index, target_data) rescue false)
        return target_index
      end
      fallback_target = battle.battlers.compact.map(&:index).find do |candidate|
        battle.pbMoveCanTarget?(idx_battler, candidate, target_data) rescue false
      end
      if fallback_target
        AnilLanRework.log(
          "remote move target fallback battle_id=#{@active_context&.battle_id} battler=#{idx_battler} move=#{move_index} " \
          "target_raw=#{action['target'].inspect} translated=#{target_index.inspect} fallback=#{fallback_target}"
        )
      end
      fallback_target
    rescue => e
      AnilLanRework.log("resolved_remote_target_for_action error #{e.class}: #{e.message}")
      nil
    end

    def ally_indices_for(battle, idx_battler)
      allies = []
      battle.battlers.each do |battler|
        next if !battler
        ally_index = battler.index
        next if ally_index == idx_battler
        next if battle.opposes?(ally_index, idx_battler)
        allies << ally_index
      end
      allies
    end

    def apply_remote_action(battle, idx_battler, action)
      fallback = proc do
        battle_ai = battle.instance_variable_get(:@battleAI) rescue nil
        if battle_ai && battle_ai.respond_to?(:anil_rework_original_pbDefaultChooseEnemyCommand)
          battle_ai.send(:anil_rework_original_pbDefaultChooseEnemyCommand, idx_battler) rescue nil
        else
          battle.pbAutoChooseMove(idx_battler) rescue nil
        end
      end
      return fallback.call unless action.is_a?(Hash)
      if (@active_context&.mode == :coop) && action["__anil_rng_state"]
        if action["__anil_rng_state"].is_a?(Integer)
          @active_context.rng.restore_state(action["__anil_rng_state"]) if @active_context&.rng
        elsif action["__anil_rng_state"].is_a?(Hash)
          @active_context.rng.restore(action["__anil_rng_state"]) if @active_context&.rng
        end
      end
      case action["kind"].to_s
      when "", "None"
        return
      when "UseMove"
        move_index = (action["move_index"] || action["choice_idx"]).to_i
        if battle.pbRegisterMove(idx_battler, move_index, false)
          target_index = resolved_remote_target_for_action(battle, idx_battler, action, move_index)
          AnilLanRework.log("remote move choice battle_id=#{@active_context&.battle_id} battler=#{idx_battler} move=#{move_index} target_raw=#{action['target'].inspect} translated=#{target_index.inspect} mega=#{action['mega']}") if @active_context&.mode == :coop
          battle.pbRegisterTarget(idx_battler, target_index) if !target_index.nil? && target_index >= 0
          battle.pbRegisterMegaEvolution(idx_battler) if action["mega"] == true && battle.respond_to?(:pbRegisterMegaEvolution)
        else
          # Fallback if move cannot be registered (e.g. out of PP, but should be synced)
          battle.choices[idx_battler][0] = :UseMove
          battle.choices[idx_battler][1] = move_index
          battle.choices[idx_battler][2] = nil # Move object will be fetched by engine
          battle.choices[idx_battler][3] = resolved_remote_target_for_action(battle, idx_battler, action, move_index)
          battle.pbRegisterMegaEvolution(idx_battler) if action["mega"] == true && battle.respond_to?(:pbRegisterMegaEvolution)
        end
      when "SwitchOut"
        raw_switch_index = (action["switch_index"] || action["choice_idx"])
        switch_index = if (@active_context&.mode == :coop) && !(battle.opposes?(idx_battler) rescue false) &&
                          action.key?("switch_relative")
          coop_absolute_party_index_for(battle, idx_battler, action["switch_relative"])
        else
          raw_switch_index.to_i
        end
        if !(battle.pbRegisterSwitch(idx_battler, switch_index) rescue false)
          # O REMETENTE ja validou esta troca na tela dele. Quando o registro
          # falha aqui, e por checagem LOCAL que nao se aplica a uma acao ja
          # decidida do outro lado: dono do battler (pbIsOwner?) ou efeitos de
          # trapping com default espurio (Commander=[] e truthy em Ruby;
          # MeanLook/JawLock/Octolock=0 e >= 0, logo "preso").
          #
          # Antes: o coop forcava o registro, mas o PVP caia no fallback — que e
          # a IA escolhendo um GOLPE. Ou seja, o remetente trocava de Pokemon e o
          # receptor atacava: desync garantido no mesmo turno. E o snapshot de HP
          # da recuperacao nao conserta isso, porque o Pokemon ativo fica errado.
          #
          # Agora vale para os DOIS modos: o receptor REPRODUZ, nao julga — a
          # mesma disciplina do Cable Club, que escreve battle.choices direto,
          # sem validar (003_Battle_CableClub.rb, bloco :choice).
          party = battle.pbParty(idx_battler) rescue []
          pkmn = party[switch_index] rescue nil
          if pkmn && !pkmn.fainted? && !pkmn.egg?
            battle.choices[idx_battler][0] = :SwitchOut
            battle.choices[idx_battler][1] = switch_index
            battle.choices[idx_battler][2] = nil
            AnilLanRework.log("remote switch forced mode=#{@active_context&.mode} battle_id=#{@active_context&.battle_id} battler=#{idx_battler} switch_index=#{switch_index} pkmn=#{pkmn.name}")
          else
            # Aqui o Pokemon realmente nao existe / nao pode entrar: e divergencia
            # de ESTADO, nao de permissao. Nao ha opcao melhor que o fallback.
            AnilLanRework.log("invalid remote switch battle_id=#{@active_context&.battle_id} battler=#{idx_battler} raw=#{raw_switch_index.inspect} relative=#{action['switch_relative'].inspect} translated=#{switch_index} party_size=#{(party.length rescue -1)}")
            fallback.call
          end
        end
      when "UseItem"
        item_id = action["item"]
        item_id = item_id.to_sym if item_id.respond_to?(:to_sym)
        battle_use = action["battle_use"].to_i
        target_index = resolve_coop_item_target(battle, idx_battler, battle_use, action["target"])
        move_index = action["move_index"]
        if register_remote_item_choice(battle, idx_battler, item_id, target_index, move_index)
          AnilLanRework.log(
            "remote item choice patched battle_id=#{@active_context&.battle_id} " \
            "battler=#{idx_battler} item=#{item_id} battle_use=#{battle_use} " \
            "target_raw=#{action['target'].inspect} target=#{target_index.inspect}"
          )
        else
          AnilLanRework.log("invalid remote item battle_id=#{@active_context&.battle_id} battler=#{idx_battler} item=#{item_id}")
          fallback.call
        end
      when "Run"
        ctx = @active_context
        if ctx && ctx.mode == :coop
          # Roda animação de recall do Pokémon do parceiro
          if idx_battler && battle.battlers[idx_battler] && !battle.battlers[idx_battler].fainted?
            battle.scene.pbRecall(idx_battler) rescue nil
            battle.battlers[idx_battler].pbAbilitiesOnSwitchOut rescue nil
          end
          
          # Exibe a mensagem de fuga
          partner_name = remote_partner_name rescue "O parceiro"
          battle.pbDisplay(_INTL("{1} fugiu da batalha...", partner_name))

          # Marca o parceiro como eliminado, fugiu e sem assistir
          ctx.instance_variable_set(:@anil_remote_coop_eliminated, true)
          ctx.instance_variable_set(:@anil_remote_coop_fled, true)
          ctx.instance_variable_set(:@anil_remote_coop_watch_until_end, false)
          
          # Zera o HP do battler remoto para ele contar como fainted
          if idx_battler && battle.battlers[idx_battler]
            battle.battlers[idx_battler].hp = 0
          end

          # Zera o HP de todos os Pokémon da party do parceiro na batalha para tirá-los do time
          if battle.respond_to?(:party1starts) && battle.party1starts && battle.party1starts[1]
            start_idx = battle.party1starts[1]
            party0 = battle.pbParty(0) rescue nil
            if party0
              (start_idx...party0.length).each do |i|
                pkmn = party0[i]
                pkmn.hp = 0 if pkmn
              end
            end
          end

          # Força atualização de layout cooperativo dinamicamente
          battle.anil_rework_force_valid_coop_layout!("remote_run_action") if battle.respond_to?(:anil_rework_force_valid_coop_layout!)
        else
          battle.decision = 3
          battle.pbAbort if battle.respond_to?(:pbAbort)
        end
      else
        fallback.call
      end
    end

    def register_remote_item_choice(battle, idx_battler, item, idx_target = nil, idx_move = nil)
      choices = battle.instance_variable_get(:@choices)
      return false unless choices
      choices[idx_battler] ||= []
      choices[idx_battler][0] = :UseItem
      choices[idx_battler][1] = item
      choices[idx_battler][2] = idx_target
      choices[idx_battler][3] = idx_move
      true
    rescue
      false
    end

    def on_party_sync(peer_id, party_blob)
      ctx = @active_context
      return unless ctx
      return unless ctx.partner_id.to_s == peer_id.to_s
      if ctx.mode == :pvp
        AnilLanRework.log("ignore standalone party_sync during pvp battle_id=#{ctx.battle_id} peer=#{peer_id}")
        return
      end
      apply_remote_party_sync(Array(party_blob))
    end

    def apply_remote_party_sync(party_blob)
      ctx = @active_context
      return unless ctx
      battle = ctx.battle
      party = nil
      if ctx.mode == :pvp
        party = ctx.foe_party
      elsif ctx.mode == :coop
        peer = AnilLanRework.players[ctx.partner_id.to_s] rescue nil
        peer.party_blob = Array(party_blob) if peer
        party = Array($PokemonGlobal&.partner && $PokemonGlobal.partner[3])
        if party.empty? && peer
          hydrated_party = AnilLanRework::Serializer.deserialize_party(peer.party_blob)
          if $PokemonGlobal&.partner
            $PokemonGlobal.partner[3] = hydrated_party
            party = Array($PokemonGlobal.partner[3])
          else
            party = hydrated_party
          end
        end
      end
      return unless party.is_a?(Array)
      Array(party_blob).each_with_index do |blob, party_index|
        next if blob.nil?

        # Preserve the active battler's current HP and status to prevent race conditions
        # (e.g. async party syncs from level-ups) from resetting correct battle values.
        active_battler = nil
        current_hp = nil
        current_status = nil
        current_status_count = nil
        if battle && battle.battlers
          active_battler = battle.battlers.find { |b| b && b.pokemon == party[party_index] }
          if active_battler
            current_hp = active_battler.hp
            current_status = active_battler.status
            current_status_count = active_battler.statusCount
          end
        end

        updated = if party[party_index]
                    AnilLanRework::Serializer.deserialize_pokemon(blob, party[party_index])
                  else
                    AnilLanRework::Serializer.deserialize_pokemon(blob)
                  end

        if updated && active_battler
          updated.hp = current_hp if current_hp
          updated.status = current_status if current_status
          updated.statusCount = current_status_count if current_status_count
        end

        if updated
          party[party_index] = updated
          
          # Sincroniza a referência do objeto Pokemon dentro da party ativa da batalha
          if battle
            if ctx.mode == :coop
              battle_party = battle.instance_variable_get(:@party1) rescue nil
              if battle_party
                start_idx = Array($player&.party).length
                b_idx = start_idx + party_index
                if b_idx >= 0 && b_idx < battle_party.length
                  battle_party[b_idx] = updated
                end
              end
            elsif ctx.mode == :pvp
              battle_party = battle.instance_variable_get(:@party2) rescue nil
              if battle_party && party_index >= 0 && party_index < battle_party.length
                battle_party[party_index] = updated
              end
            end
          end
        end
      end
      ctx.pending_party_refresh = true
      refresh_remote_party_battlers
    end

    def queue_outbound_party_sync
      ctx = @active_context
      return unless ctx && [:pvp, :coop].include?(ctx.mode)
      local_party = if ctx.mode == :pvp
        active_pvp_party(ctx)
      else
        $player.party
      end
      ctx.outbound_party_sync = AnilLanRework::Serializer.serialize_party(local_party)
      AnilLanRework::TradeSync.send_party_sync if AnilLanRework.connected?
      AnilLanRework.log("queue_outbound_party_sync battle_id=#{ctx.battle_id} mode=#{ctx.mode} size=#{Array(ctx.outbound_party_sync).length} party=#{party_species_names(local_party).inspect}")
    rescue => e
      AnilLanRework.log("queue_outbound_party_sync error #{e}")
    end

    def consume_outbound_party_sync
      ctx = @active_context
      return nil unless ctx
      payload = ctx.outbound_party_sync
      ctx.outbound_party_sync = nil if payload
      payload
    end

    def battle_party_sync_payload
      ctx = @active_context
      return nil unless ctx && [:pvp, :coop].include?(ctx.mode)
      consume_outbound_party_sync
    rescue
      nil
    end

    def apply_embedded_party_sync(packet)
      return unless packet.is_a?(Hash)
      party_blob = packet["party_sync"]
      return if party_blob.nil?
      apply_remote_party_sync(Array(party_blob))
    end

    def extract_effect_entry_value(entries, effect_id)
      Array(entries).each do |entry|
        next unless entry.is_a?(Hash)
        next unless entry["id"].to_i == effect_id.to_i
        return entry["value"]
      end
      nil
    end

    def sync_battler_status_fields(battler, status_id, status_count, toxic_counter = nil)
      return unless battler
      status_id = nil if status_id.to_s.empty?
      status_id = status_id.to_sym if status_id && status_id.respond_to?(:to_sym)
      status_count = status_count.to_i
      current_toxic = begin
        battler.effects[PBEffects::Toxic].to_i
      rescue
        0
      end
      toxic_counter = current_toxic if toxic_counter.nil?

      if status_id.nil? || status_id == :NONE
        battler.instance_variable_set(:@status, :NONE)
        battler.instance_variable_set(:@statusCount, 0)
        battler.effects[PBEffects::Toxic] = 0 rescue nil
        if battler.pokemon
          battler.pokemon.heal_status rescue nil
          battler.pokemon.statusCount = 0 rescue nil
        end
      else
        battler.instance_variable_set(:@statusCount, status_count)
        battler.instance_variable_set(:@status, status_id)
        if battler.pokemon
          battler.pokemon.status = status_id rescue nil
          battler.pokemon.statusCount = status_count rescue nil
        end
        if status_id == :POISON && status_count > 0
          battler.effects[PBEffects::Toxic] = [toxic_counter.to_i, 0].max rescue nil
        else
          battler.effects[PBEffects::Toxic] = 0 rescue nil
        end
      end
    rescue => e
      AnilLanRework.log("sync battler status fields error #{e.class}: #{e.message}")
    end

    def refresh_remote_party_battlers
      ctx = @active_context
      battle = ctx && ctx.battle
      return unless ctx && battle
      battle.battlers.each do |battler|
        next unless battler && battler.pokemon
        should_refresh = case ctx.mode
                         when :pvp
                           !battle.pbOwnedByPlayer?(battler.index)
                         when :coop
                           !battle.opposes?(battler.index) && !battle.pbOwnedByPlayer?(battler.index)
                         else
                           false
                         end
        next unless should_refresh

        # Sincroniza a referência do objeto Pokemon se ele foi recriado (ex: devido a evolução/troca de espécie)
        begin
          if ctx.mode == :coop
            party = Array($PokemonGlobal&.partner && $PokemonGlobal.partner[3])
            start_index = Array($player&.party).length
            party_index = battler.pokemonIndex - start_index
            if party_index >= 0 && party_index < party.length && party[party_index]
              if battler.pokemon != party[party_index]
                AnilLanRework.log("refresh_remote_party_battlers: updating battler #{battler.index} pokemon reference to new evolved instance")
                battler.pokemon = party[party_index]
              end
            end
          elsif ctx.mode == :pvp
            party = ctx.foe_party
            party_index = battler.pokemonIndex
            if party_index >= 0 && party_index < party.length && party[party_index]
              if battler.pokemon != party[party_index]
                AnilLanRework.log("refresh_remote_party_battlers pvp: updating battler #{battler.index} pokemon reference to new evolved instance")
                battler.pokemon = party[party_index]
              end
            end
          end
        rescue => e
          AnilLanRework.log("refresh_remote_party_battlers reference sync error: #{e.message}")
        end

        sync_battler_status_fields(
          battler,
          battler.pokemon.status,
          battler.pokemon.statusCount
        )
        battler.refresh_moves rescue nil
        
        # Sincroniza HP/HP Máximo do battler após a evolução/level up remoto
        battler.hp = battler.pokemon.hp if battler.respond_to?(:hp=)
        battler.totalhp = battler.pokemon.totalhp if battler.respond_to?(:totalhp=)
        
        begin
          if battler.species != battler.pokemon.species || battler.form != battler.pokemon.form
            battler.pbUpdate(true)
          else
            battler.pbUpdate(false)
          end
        rescue
          battler.pbUpdate(false) rescue nil
        end
        battle.scene.pbRefreshOne(battler.index) rescue nil
      end
      battle.scene.pbRefresh rescue nil
      battle.scene.pbUpdate rescue nil
    end

    def flush_remote_party_refresh
      ctx = @active_context
      return unless ctx && ctx.pending_party_refresh
      ctx.pending_party_refresh = false
      refresh_remote_party_battlers
    end

    # Alinha a forma do battler com a do parceiro. Campo ausente (cliente antigo)
    # e simplesmente ignorado, entao isto e retrocompativel.
    def apply_remote_form_to_battler(battler, entry)
      return unless battler && entry.is_a?(Hash) && entry.key?("form")
      return if entry["form"].nil?
      target_form = entry["form"].to_i
      return if (battler.fainted? rescue false)
      # Transform tem regra propria: pbChangeForm recusa e a copia vem do efeito.
      return if (battler.effects[PBEffects::Transform] rescue false)
      current_form = (battler.form.to_i rescue nil)
      return if current_form.nil? || current_form == target_form
      battler.pbChangeForm(target_form, "")
      AnilLanRework.log("coop form sync battler=#{battler.index} #{current_form} -> #{target_form}")
    rescue => e
      AnilLanRework.log("apply_remote_form_to_battler error #{e.class}: #{e.message}")
    end

    def apply_remote_status_to_battler(battler, packet)
      return unless battler
      status_id = packet["status"]
      status_id = nil if status_id.to_s.empty?
      status_id = status_id.to_sym if status_id && status_id.respond_to?(:to_sym)
      
      toxic_counter = extract_effect_entry_value(packet["effects"], PBEffects::Toxic)
      
      if packet.key?("status_count")
        status_count = packet["status_count"].to_i
      else
        status_count = (battler.status == status_id) ? (battler.statusCount.to_i rescue 0) : 0
        if status_id == :POISON && toxic_counter.to_i > 0
          status_count = 1 if status_count == 0
        end
      end
      
      if status_id == :POISON && toxic_counter.to_i > 0 && status_count <= 0
        status_count = 1
      end
      
      old_hp = (battler.hp.to_i rescue 0)
      old_status = (battler.status rescue nil)
      old_count = (battler.statusCount.to_i rescue 0)
      sync_battler_status_fields(battler, status_id, status_count, toxic_counter)
      hp_applied = apply_remote_snapshot_hp(battler, packet)
      new_hp = (battler.hp.to_i rescue 0)
      AnilLanRework.log("battle apply status event battle_id=#{@active_context&.battle_id} battler=#{battler.index} remote_battler=#{packet['remote_battler']} old_hp=#{old_hp} new_hp=#{new_hp} hp_applied=#{hp_applied ? true : false} old=#{old_status || 'NONE'}/#{old_count} new=#{status_id || 'NONE'}/#{status_count}")
    rescue => e
      AnilLanRework.log("battle apply status event error #{e.class}: #{e.message}")
    end

    def snapshot_hp_payload_valid?(packet, battler = nil)
      return false unless packet.is_a?(Hash)
      return false unless packet.key?("hp") || packet.key?("totalhp")

      hp_value = packet["hp"]
      totalhp_value = packet["totalhp"]
      return false if hp_value.nil? || totalhp_value.nil?

      hp = hp_value.to_i
      totalhp = totalhp_value.to_i
      return false if totalhp <= 0
      return false if hp < 0 || hp > totalhp

      if battler
        local_totalhp = (battler.totalhp.to_i rescue 0)
        return false if local_totalhp > 0 && totalhp != local_totalhp
      end
      true
    rescue
      false
    end

    def apply_remote_snapshot_hp(battler, packet)
      return false unless battler
      return false unless packet.is_a?(Hash)

      unless snapshot_hp_payload_valid?(packet, battler)
        if packet.key?("hp") || packet.key?("totalhp")
          AnilLanRework.log(
            "battle status hp ignored battle_id=#{@active_context&.battle_id} " +
            "battler=#{battler.index} remote_battler=#{packet['remote_battler']} " +
            "hp=#{packet['hp'].inspect} totalhp=#{packet['totalhp'].inspect} " +
            "local_hp=#{battler.hp.to_i} local_totalhp=#{battler.totalhp.to_i rescue 0}"
          )
        end
        return false
      end

      hp = packet["hp"].to_i
      changed = (battler.hp.to_i rescue 0) != hp
      battler.hp = hp rescue battler.instance_variable_set(:@hp, hp)
      if battler.pokemon
        battler.pokemon.hp = hp rescue nil
      end
      changed
    rescue => e
      AnilLanRework.log("battle status hp apply error #{e.class}: #{e.message}")
      false
    end

    def apply_remote_status_snapshot(battle, packet)
      sender_client_index = if packet.key?("sender_client_index")
        packet["sender_client_index"].to_i
      elsif @active_context
        @active_context.client_index.to_i == 0 ? 1 : 0
      else
        0
      end

      Array(packet["battlers"]).each do |entry|
        next unless entry.is_a?(Hash)
        remote_battler = entry["battler"].to_i
        local_battler = translate_snapshot_battler_index(remote_battler, sender_client_index, battle)
        battler = battle.battlers[local_battler] rescue nil
        next unless battler
        # Forma primeiro: pbChangeForm recalcula totalhp, e o HP autoritativo do
        # snapshot e aplicado logo em seguida, por cima.
        apply_remote_form_to_battler(battler, entry)
        apply_remote_status_to_battler(battler, entry.merge("remote_battler" => remote_battler, "battler" => local_battler))
        apply_effect_entries_to_collection(battler.effects, :battler, entry["effects"], sender_client_index, battle, battler)
        # Estado de simulacao (stages/ability/item/types/PP/flags de dano) antes do
        # pbUpdate: o pbUpdate recalcula stats, e stats leem stages/ability/item.
        apply_remote_battle_state_to_battler(battler, entry, battle) if coop_determinismo_v3?
        battler.refresh_moves rescue nil
        begin
          if battler.species != battler.pokemon.species || battler.form != battler.pokemon.form
            battler.pbUpdate(true)
          else
            battler.pbUpdate(false)
          end
        rescue
          battler.pbUpdate(false) rescue nil
        end
        battle.scene.pbRefreshOne(battler.index) rescue nil
      end

      Array(packet["positions"]).each do |entry|
        next unless entry.is_a?(Hash)
        remote_position = entry["position"].to_i
        local_position = translate_snapshot_battler_index(remote_position, sender_client_index, battle)
        position = battle.positions[local_position] rescue nil
        next unless position
        apply_effect_entries_to_collection(position.effects, :position, entry["effects"], sender_client_index, battle)
      end

      Array(packet["sides"]).each do |entry|
        next unless entry.is_a?(Hash)
        side_idx = entry["side"].to_i
        if @active_context && @active_context.mode == :pvp
          side_idx = 1 - side_idx
        end
        side = battle.sides[side_idx] rescue nil
        next unless side
        apply_effect_entries_to_collection(side.effects, :side, entry["effects"], sender_client_index, battle)
      end

      field_effects = packet.dig("field", "effects")
      apply_effect_entries_to_collection(battle.field.effects, :field, field_effects, sender_client_index, battle) if field_effects
      apply_remote_field_state(battle, packet["field_state"]) if packet["field_state"]

      # DESMAIO AUTORITATIVO.
      # O snapshot escrevia hp=0 e parava por ai — ninguem chamava pbFaint. O
      # unico lugar do codigo que desmaiava a partir do HP do host era o
      # apply_coop_turn_batch (proto 2). Resultado, com o proto 2 desligado:
      # numa dupla coop o inimigo morria so na tela de quem deu o golpe, e no
      # outro cliente ficava de pe com 0 de HP ("ficou uma zona").
      # Aqui vale para qualquer proto e para PVP tambem.
      battle.battlers.each do |battler|
        next unless battler
        next if (battler.hp.to_i rescue 1) > 0
        next if (battler.fainted? rescue true)
        begin
          battler.pbFaint
          AnilLanRework.log("snapshot: desmaio autoritativo aplicado battler=#{battler.index}")
        rescue => e
          AnilLanRework.log("snapshot: falha ao desmaiar battler=#{battler.index} #{e.class}: #{e.message}")
        end
      end

      battle.scene.pbRefresh rescue nil
      battle.scene.pbUpdate rescue nil
    rescue => e
      AnilLanRework.log("coop apply status snapshot error #{e.class}: #{e.message}")
    end

    def apply_legacy_remote_status_packet(battle, packet)
      sender_client_index = if packet.key?("sender_client_index")
        packet["sender_client_index"].to_i
      elsif @active_context
        @active_context.client_index.to_i == 0 ? 1 : 0
      else
        0
      end

      Array(packet["statuses"]).each do |entry|
        next unless entry.is_a?(Hash)
        remote_battler = entry["battler"].to_i
        local_battler = translate_snapshot_battler_index(remote_battler, sender_client_index, battle)
        battler = battle.battlers[local_battler] rescue nil
        next unless battler
        apply_remote_status_to_battler(battler, entry.merge("remote_battler" => remote_battler, "battler" => local_battler))
        battle.scene.pbRefreshOne(battler.index) rescue nil
      end
      battle.scene.pbRefresh rescue nil
      battle.scene.pbUpdate rescue nil
    rescue => e
      AnilLanRework.log("coop apply legacy status packet error #{e.class}: #{e.message}")
    end

    def flush_remote_status_events
      ctx = @active_context
      battle = ctx && ctx.battle
      return unless ctx && battle
      return if !ctx.pending_status_events || ctx.pending_status_events.empty?
      until ctx.pending_status_events.empty?
        packet = ctx.pending_status_events.shift
        if packet.is_a?(Hash) && (packet["battlers"] || packet["positions"] || packet["sides"] || packet["field"])
          apply_remote_status_snapshot(battle, packet)
        else
          apply_legacy_remote_status_packet(battle, packet)
        end
      end
      battle.scene.pbRefresh rescue nil
      battle.scene.pbUpdate rescue nil
    end

    def sync_party_if_needed(before_blob, after_blob, force = false)
      ctx = @active_context
      return if !force && before_blob == after_blob
      return unless ctx && [:pvp, :coop].include?(ctx.mode) && AnilLanRework.connected?
      queue_outbound_party_sync
    end

    def store_incoming_invite(packet)
      return unless packet.is_a?(Hash)
      if packet["to_id"].to_s == AnilLanRework.self_internal_id.to_s
        @pending_invite = packet
      else
        AnilLanRework.log("ignored battle invite meant for different recipient to_id=#{packet["to_id"]}")
      end
    end

    def receive_accept(packet)
      battle_id = packet["battle_id"].to_s
      original = @outgoing_invites[battle_id]
      return unless original
      peer_id = packet["sender_id"].to_s

      # ⚠️ QUEM ACEITA TEM DE SER QUEM EU CONVIDEI.
      #
      # Antes casava-se so pelo battle_id, e a equipa do adversario saia crua de
      # packet["party"] — ou seja, quem soubesse um battle_id podia forjar um
      # aceite e escolher com que equipa eu ia lutar. O battle_id traz o
      # self_internal_id de quem convida (ver build_battle_id), portanto
      # colisao acidental nao existe; o risco e falsificacao.
      #
      # NAO consumir o convite quando o remetente nao bate: se fosse `delete`
      # logo no inicio, um pacote intruso derrubava o duelo legitimo antes de a
      # resposta verdadeira chegar.
      convidado = original["to_id"].to_s
      if peer_id != convidado
        AnilLanRework.log("[PVP] aceite ignorado em #{battle_id}: veio de #{peer_id.inspect}, o convite era para #{convidado.inspect}") rescue nil
        return
      end
      @outgoing_invites.delete(battle_id)
      peer = AnilLanRework.players[peer_id]
      peer.party_blob = Array(packet["party"]) if peer && packet["party"]
      pending_rules = normalize_duel_rules(original["rules"])
      local_party_blob = Array(original["selected_party"] || original["party"])
      foe_party_blob = Array(packet["selected_party"] || packet["party"])
      AnilLanRework.log("receive_accept battle_id=#{battle_id} rules=#{pending_rules.inspect} local_party=#{party_species_names(AnilLanRework::Serializer.deserialize_party(local_party_blob)).inspect} foe_party=#{party_species_names(AnilLanRework::Serializer.deserialize_party(foe_party_blob)).inspect}")
      @pending_start = {
        :battle_id    => battle_id,
        :peer_id      => peer_id,
        :size         => original["size"].to_i,
        :seed         => original["seed"].to_i,
        :client_index => 0,
        :rules        => pending_rules,
        :party        => foe_party_blob,
        :local_party  => local_party_blob
      }
    end

    def receive_decline(packet)
      @outgoing_invites.delete(packet["battle_id"].to_s)
      message = case packet["reason"].to_s
                when "expired"   then _INTL("O convite de batalha expirou.")
                # Quem convidou desistiu antes de nos respondermos. A frase tem
                # de ser esta e nao "foi recusado": o mesmo pacote serve os dois
                # sentidos, e dizer a alguem que o pedido DELE foi recusado
                # quando foi o outro a desistir e simplesmente falso.
                when "cancelled" then _INTL("O convite de batalha foi cancelado.")
                else                  _INTL("O pedido de duelo foi recusado.")
                end
      pbMessage(message) rescue nil
    end

    def expire_outgoing_invites
      return if @outgoing_invites.empty?
      now = Time.now.to_f
      expired = @outgoing_invites.select do |_battle_id, packet|
        now - packet["sent_at"].to_f >= AnilLanRework::BATTLE_INVITE_TIMEOUT
      end
      expired.each do |battle_id, packet|
        @outgoing_invites.delete(battle_id)
        next unless AnilLanRework.connected?
        AnilLanRework.connection.send_packet("battle_decline",
          "to_id"     => packet["to_id"],
          "battle_id" => battle_id,
          "reason"    => "expired"
        )
      end
    end

    def serialize_turn_bundle(battle)
      our_indices = battle.pbGetOpposingIndicesInOrder(1).reverse
      # No PvP, precisamos inverter os indices para o outro jogador
      target_order = [1, 0, 3, 2] # Padrao para Single/Double PvP
      
      # Envia o estado interno do RNG (Cable Club style)
      # Random#srand retorna o estado atual do gerador — muito mais preciso
      # que seed+call_count porque reflete o estado exato neste momento
      rng_state = @active_context&.rng&.state rescue nil
      
      payload = {
        "battle_id"  => @active_context.battle_id.to_s,
        "turn"       => battle.turnCount.to_i,
        "rng_state"  => rng_state,
        "mechanics"  => serialize_mechanics(battle),
        "choices"    => our_indices.map { |idx| 
           choice = serialize_coop_choice(battle, idx)
           # Inverte o alvo para o receptor
           choice["target"] = target_order[choice["target"]] rescue choice["target"]
           choice
        }
      }
      party_sync = battle_party_sync_payload
      payload["party_sync"] = party_sync if party_sync
      payload
    end

    def sync_pvp_turn_bundle(battle, reason = nil)
      ctx = @active_context
      return false unless battle && ctx && ctx.mode == :pvp && AnilLanRework.connected?
      AnilLanRework.log("pvp turn sync start battle_id=#{ctx.battle_id} turn=#{battle.turnCount} reason=#{reason}")
      
      # Envia nossas escolhas
      payload = serialize_turn_bundle(battle)
      AnilLanRework.connection.send_packet("battle_turn", payload)
      
      # Espera as escolhas dele
      packet = wait_for_remote_turn(battle.turnCount.to_i)
      return false unless packet
      
      # === SERVER RNG SEEDING ===
      # Request turn seed from the server to guarantee perfect synchronization
      AnilLanRework.connection.send_packet("request_turn_seed", {
        "battle_id" => ctx.battle_id,
        "turn" => battle.turnCount.to_i
      })
      server_packet = wait_for_turn_seed(ctx.battle_id, battle.turnCount.to_i)
      if server_packet
        seed = server_packet.to_i
        ctx.rng.restore({ "seed" => seed, "calls" => 0 })
        battle.anil_rework_rng = ctx.rng if battle.respond_to?(:anil_rework_rng=)
        AnilLanRework.log("pvp: RNG re-seeded from server seed=#{seed} turn=#{battle.turnCount}")
      end

      # === RNG SYNC (Cable Club style) ===
      # O host envia o estado interno do seu RNG via Random#srand.
      # O cliente restaura com restore_state — sem recriar o objeto,
      # apenas reposicionando o gerador para o mesmo ponto exato.
      # Executado apenas se NÃO obtivemos semente do servidor (fallback para LAN/sem resposta).
      if !server_packet && ctx.client_index != 0
        if packet["rng_state"].is_a?(Hash)
          ctx.rng.restore(packet["rng_state"])
          battle.anil_rework_rng = ctx.rng if battle.respond_to?(:anil_rework_rng=)
          AnilLanRework.log("pvp: RNG state synced from host (fallback) rng_state=#{packet['rng_state']} turn=#{battle.turnCount}")
        elsif packet["rng_state"].is_a?(Integer)
          ctx.rng.restore_state(packet["rng_state"])
          battle.anil_rework_rng = ctx.rng if battle.respond_to?(:anil_rework_rng=)
          AnilLanRework.log("pvp: RNG state synced from host (fallback) rng_state=#{packet['rng_state']} turn=#{battle.turnCount}")
        end
      end
      
      apply_remote_turn_to_battle(battle, packet)
      true
    end

    def pvp_hp_sync_order_after?(turn_a, seq_a, turn_b, seq_b)
      return true if turn_b.nil? || seq_b.nil?
      
      # Converter para inteiros para evitar problemas de tipo
      turn_a_int = turn_a.to_i
      turn_b_int = turn_b.to_i
      seq_a_int = seq_a.to_i
      seq_b_int = seq_b.to_i
      
      # Se os turnos são diferentes, o turno maior vem depois
      return true if turn_a_int > turn_b_int
      return false if turn_a_int < turn_b_int
      
      # Se os turnos são iguais, comparar pela sequência
      seq_a_int > seq_b_int
    end

    def detect_multi_hit_in_progress(ctx, battler)
      return false unless ctx && ctx.battle && battler
      
      # Verificar se o último movimento usado foi um multi-hit
      last_move = battler.lastMoveUsed
      return false unless last_move
      
      # Obter informações do movimento
      move_data = GameData::Move.try_get(last_move)
      return false unless move_data
      
      # Verificar se é um multi-hit move
      move_object = Battle::Move.from_pokemon_move(ctx.battle, battler, Pokemon::Move.new(last_move))
      return move_object&.multiHitMove? || false
    rescue
      false
    end

    def next_pvp_hp_sync_sequence(battler_index)
      @pvp_hp_sync_out_seq ||= {}
      key = battler_index.to_i
      
      # Para multi-hit moves, garantir que não haja saltos na sequência
      current_seq = @pvp_hp_sync_out_seq.fetch(key, 0).to_i
      
      # Verificar se há pacotes pendentes para este battler
      pending = @pending_hp_syncs&.dig(key)
      if pending && !pending.empty?
        last_pending = pending.max_by { |p| [p["turn"].to_i, p["seq"].to_i] }
        expected_seq = last_pending["seq"].to_i + 1
        
        # Se a sequência atual for menor que a esperada, usar a esperada
        if current_seq < expected_seq
          @pvp_hp_sync_out_seq[key] = expected_seq
          return expected_seq
        end
      end
      
      # Incrementar normalmente
      @pvp_hp_sync_out_seq[key] = current_seq + 1
    end

    def pvp_hp_sync_stale?(battler_index, turn, seq)
      @pvp_hp_sync_applied ||= {}
      last = @pvp_hp_sync_applied[battler_index.to_i]
      return false unless last.is_a?(Hash)
      !pvp_hp_sync_order_after?(turn, seq, last["turn"], last["seq"])
    end

    def mark_pvp_hp_sync_applied(battler_index, packet)
      return unless packet.is_a?(Hash)
      @pvp_hp_sync_applied ||= {}
      @pvp_hp_sync_applied[battler_index.to_i] = {
        "turn" => packet["turn"].to_i,
        "seq"  => packet["seq"].to_i
      }
    end

    def buffer_out_of_order_hp_packet(packet)
      return unless packet.is_a?(Hash)
      
      battler_index = packet["battler"].to_i
      turn = packet["turn"].to_i
      seq = packet["seq"].to_i
      
      # Criar buffer de reordenação se não existir
      @hp_reorder_buffer ||= {}
      @hp_reorder_buffer[battler_index] ||= []
      
      # Adicionar pacote ao buffer
      @hp_reorder_buffer[battler_index] << packet
      
      # Ordenar o buffer
      @hp_reorder_buffer[battler_index].sort_by! { |p| [p["turn"].to_i, p["seq"].to_i] }
      
      # Processar pacotes em ordem
      process_reordered_hp_packets(battler_index)
    end

    def process_reordered_hp_packets(battler_index)
      return unless @hp_reorder_buffer && @hp_reorder_buffer[battler_index]
      
      buffer = @hp_reorder_buffer[battler_index]
      last_applied = @pvp_hp_sync_applied[battler_index]
      
      buffer.each do |packet|
        turn = packet["turn"].to_i
        seq = packet["seq"].to_i
        
        # Verificar se este pacote pode ser aplicado
        if !last_applied || pvp_hp_sync_order_after?(turn, seq, last_applied["turn"], last_applied["seq"])
          apply_pvp_hp_sync_packet(packet)
          buffer.delete(packet)
        end
      end
    end

    def apply_pvp_hp_sync_packet(packet)
      return unless packet.is_a?(Hash)
      
      battle = @active_context&.battle
      return unless battle
      
      idx_battler = packet["battler"].to_i
      new_hp = (packet["hp"] || packet["new_hp"]).to_i
      hp_kind = packet["hp_kind"].to_s
      turn = packet["turn"].to_i
      seq = packet["seq"].to_i
      
      battler = battle.battlers[idx_battler] rescue nil
      return unless battler
      
      # Aplicar as mudanças de HP
      old_hp = battler.hp
      if hp_kind == "damage"
        battler.hp = new_hp
        AnilLanRework.log("applied buffered hp damage battle_id=#{@active_context.battle_id} battler=#{idx_battler} old=#{old_hp} new=#{new_hp} turn=#{turn} seq=#{seq}")
      elsif hp_kind == "heal"
        battler.hp = new_hp
        AnilLanRework.log("applied buffered hp heal battle_id=#{@active_context.battle_id} battler=#{idx_battler} old=#{old_hp} new=#{new_hp} turn=#{turn} seq=#{seq}")
      end
      
      # Marcar como aplicado
      mark_pvp_hp_sync_applied(idx_battler, packet)
    end

    def sync_hp_after_damage(battler, old_hp, new_hp, ctx, kind = "damage")
      return unless ctx && ctx.mode == :pvp && AnilLanRework.connected?
      return if old_hp == new_hp
      # === HOST-ONLY AUTHORITY ===
      # Somente o host envia hp_sync. Ele é a autoridade para TODOS os battlers.
      # O cliente nunca envia — apenas recebe e aplica.
      return unless ctx.client_index == 0
      
      turn = begin
        ctx.battle ? ctx.battle.turnCount.to_i : 0
      rescue
        0
      end
      
      species = (battler.pokemon&.species.to_s rescue battler.species.to_s rescue "")
      pokemon_idx = (battler.pokemonIndex.to_i rescue -1)
      
      sync_packet = {
        "type"      => "battle_hp_sync",
        "battle_id" => ctx.battle_id.to_s,
        "battler"   => battler.index.to_i,
        "hp"        => battler.hp.to_i,
        "maxhp"     => battler.totalhp.to_i,
        "status"    => (battler.status.id rescue battler.status).to_s,
        "hp_kind"   => kind.to_s,
        "turn"      => turn,
        "seq"       => next_pvp_hp_sync_sequence(battler.index),
        "auth"      => true,
        "species"   => species,
        "pokemon_idx" => pokemon_idx
      }
      AnilLanRework.connection.send_packet("battle_hp_sync", sync_packet) rescue nil
    end

    def receive_hp_sync(packet)
      ctx = active_context rescue nil
      return unless ctx && ctx.battle && ctx.battle_id.to_s == packet["battle_id"].to_s
      
      idx = packet["battler"].to_i
      idx = AnilLanRework::CableOrder.flip_index(idx) if ctx.mode == :pvp
      
      hp_kind = packet["hp_kind"].to_s
      hp_kind = "damage" if hp_kind.empty?
      turn = packet["turn"].to_i
      seq = packet["seq"].to_i
      remote_species = packet["species"].to_s
      
      # === VALIDAÇÃO DE ESPÉCIE ===
      # Se o pacote inclui species, validar que o Pokémon no slot local
      # é o mesmo. Se não for, descartar para evitar aplicar HP no Pokémon errado.
      if !remote_species.empty?
        local_battler = ctx.battle.battlers[idx] rescue nil
        if local_battler
          local_species = (local_battler.pokemon&.species.to_s rescue local_battler.species.to_s rescue "")
          if !local_species.empty? && local_species != remote_species
            AnilLanRework.log(
              "pvp: hp sync SPECIES MISMATCH battler=#{idx} local=#{local_species} remote=#{remote_species} hp=#{packet['hp']} - descartando"
            )
            return
          end
        end
      end
      
      # Verificar se o pacote está stale
      if pvp_hp_sync_stale?(idx, turn, seq)
        AnilLanRework.log("pvp: hp sync stale detected battler=#{idx} kind=#{hp_kind} turn=#{turn} seq=#{seq} target_hp=#{packet['hp'].to_i}")
        # Pacotes autoritários do host forçam aplicação mesmo se stale
        battler = ctx.battle.battlers[idx] rescue nil
        if battler && battler.hp != packet["hp"].to_i
          AnilLanRework.log("pvp: forcing authoritative stale packet application")
          # Injetar o índice flipado para que apply_pvp_hp_sync_packet use o battler correto
          fixed_packet = packet.dup
          fixed_packet["battler"] = idx
          apply_pvp_hp_sync_packet(fixed_packet)
        end
        return
      end

      # Buffer hp_sync packets by battler and event ordering.
      @pending_hp_syncs ||= {}
      pending = (@pending_hp_syncs[idx] ||= [])
      duplicate = pending.any? do |entry|
        entry.is_a?(Hash) &&
          entry["turn"].to_i == turn &&
          entry["seq"].to_i == seq &&
          entry["hp_kind"].to_s == hp_kind
      end
      return if duplicate
      pending << {
        "hp"      => packet["hp"].to_i,
        "hp_kind" => hp_kind,
        "turn"    => turn,
        "seq"     => seq,
        "species" => remote_species
      }
      pending.sort_by! { |entry| [entry["turn"].to_i, entry["seq"].to_i] }
      AnilLanRework.log("pvp: hp sync buffered battler=#{idx} kind=#{hp_kind} turn=#{turn} seq=#{seq} target_hp=#{packet['hp'].to_i}")
    end

    def consume_pending_hp_sync(battler_index, expected_kind = nil, expected_turn = nil)
      @pending_hp_syncs ||= {}
      pending = @pending_hp_syncs[battler_index.to_i]
      return nil if !pending || pending.empty?
      expected_kind = expected_kind.to_s if expected_kind
      index = pending.index do |entry|
        next false unless entry.is_a?(Hash)
        next false if expected_kind && entry["hp_kind"].to_s != expected_kind
        next false if !expected_turn.nil? && entry["turn"].to_i != expected_turn.to_i
        !pvp_hp_sync_stale?(battler_index, entry["turn"], entry["seq"])
      end
      return nil unless index
      packet = pending.delete_at(index)
      @pending_hp_syncs.delete(battler_index.to_i) if pending.empty?
      packet
    end

    def apply_all_pending_hp_syncs
      ctx = active_context rescue nil
      return unless ctx && ctx.battle
      @pending_hp_syncs ||= {}
      current_turn = begin
        ctx.battle.turnCount.to_i
      rescue
        0
      end
      @pending_hp_syncs.keys.each do |idx|
        pending = Array(@pending_hp_syncs[idx]).select do |entry|
          entry.is_a?(Hash) &&
            entry["turn"].to_i <= current_turn &&
            !pvp_hp_sync_stale?(idx, entry["turn"], entry["seq"])
        end
        next if pending.empty?
        packet = pending.max_by { |entry| [entry["turn"].to_i, entry["seq"].to_i] }
        battler = ctx.battle.battlers[idx]
        next unless battler
        target_hp = packet["hp"].to_i
        if battler.hp != target_hp
          AnilLanRework.log(
            "pvp: hp sync apply (deferred) battler=#{idx} kind=#{packet['hp_kind']} turn=#{packet['turn']} seq=#{packet['seq']} old=#{battler.hp} new=#{target_hp}"
          )
          battler.hp = target_hp
        end
        mark_pvp_hp_sync_applied(idx, packet)
        @pending_hp_syncs[idx] = Array(@pending_hp_syncs[idx]).reject do |entry|
          next false unless entry.is_a?(Hash)
          !pvp_hp_sync_order_after?(entry["turn"], entry["seq"], packet["turn"], packet["seq"])
        end
        @pending_hp_syncs.delete(idx) if @pending_hp_syncs[idx].empty?
      end
    end

    # ================================================================
    # PvP Turn-End HP Handshake
    # Protocolo sincronizado: cliente envia seus HPs, host compara,
    # host envia correções, cliente aplica e confirma. Repete até bater.
    # ================================================================
    def pvp_end_of_turn_hp_reconciliation(battle)
      ctx = active_context rescue nil
      return unless ctx && ctx.mode == :pvp && ctx.client_index == 0 && AnilLanRework.connected?
      return unless battle

      # Drenar qualquer hp_sync pendente residual
      @pending_hp_syncs = {}

      turn = battle.turnCount.to_i rescue 0
      battler_states = []
      battle.battlers.each_with_index do |battler, idx|
        next unless battler
        battler_states << {
          "idx"     => idx,
          "hp"      => battler.hp.to_i,
          "maxhp"   => battler.totalhp.to_i,
          "status"  => (battler.status.id rescue battler.status).to_s,
          "species" => (battler.pokemon&.species.to_s rescue "")
        }
      end

      snapshot = {
        "type"      => "pvp_hp_snapshot",
        "battle_id" => ctx.battle_id.to_s,
        "to_id"     => ctx.partner_id,
        "turn"      => turn,
        "battlers"  => battler_states
      }
      AnilLanRework.log(
        "pvp: end-of-turn HP snapshot sent turn=#{turn} " +
        "battlers=#{battler_states.map { |b| "#{b['idx']}:#{b['hp']}/#{b['maxhp']}" }.join(' | ')}"
      )
      AnilLanRework.connection.send_packet("pvp_hp_snapshot", snapshot) rescue nil
    end

    def pvp_client_end_of_turn_sync(battle)
      ctx = active_context rescue nil
      return unless ctx && ctx.mode == :pvp && ctx.client_index != 0 && AnilLanRework.connected?
      return unless battle

      # Drenar qualquer hp_sync pendente residual
      @pending_hp_syncs = {}

      turn = battle.turnCount.to_i rescue 0

      # Se o snapshot já chegou durante o switch prompt, aplicar imediatamente
      if @pending_hp_snapshot
        snapshot = @pending_hp_snapshot
        @pending_hp_snapshot = nil
        corrections = apply_hp_snapshot_to_battle(battle, snapshot, turn)
        if corrections > 0
          AnilLanRework.log("pvp: client applied #{corrections} HP corrections (early) turn=#{turn}")
        else
          AnilLanRework.log("pvp: client HP matches host snapshot (early) turn=#{turn}")
        end
        return
      end

      started = Time.now.to_f
      initial_timeout = 3.0
      snapshot = nil
      viewport = nil
      window = nil
      request_sent = false

      begin
        loop do
          pump_network
          if @pending_hp_snapshot
            snapshot = @pending_hp_snapshot
            @pending_hp_snapshot = nil
            break
          end
          break unless AnilLanRework.connected?

          elapsed = Time.now.to_f - started
          if elapsed >= initial_timeout && !request_sent
            # Timeout inicial - mostrar mensagem e pedir ao host
            viewport, window = build_wait_window("Aguardando conex\u00e3o...")
            send_hp_request_to_host(ctx, turn)
            request_sent = true
            AnilLanRework.log("pvp: client requesting HP snapshot from host turn=#{turn}")
          end

          # Se já pediu, reenvia a cada 2s
          if request_sent && (Time.now.to_f - started) > initial_timeout
            interval = ((Time.now.to_f - started - initial_timeout) / 2.0).floor
            if interval > 0 && (Time.now.to_f - started - initial_timeout) % 2.0 < 0.1
              send_hp_request_to_host(ctx, turn)
            end
          end

          Graphics.update rescue nil
          Input.update rescue nil
          window.update rescue nil if window
        end
      ensure
        dispose_wait_window(viewport, window)
      end

      if snapshot
        corrections = apply_hp_snapshot_to_battle(battle, snapshot, turn)
        if corrections > 0
          AnilLanRework.log("pvp: client applied #{corrections} HP corrections from host snapshot turn=#{turn}")
        else
          AnilLanRework.log("pvp: client HP matches host snapshot turn=#{turn} - no corrections needed")
        end
      else
        AnilLanRework.log("pvp: client lost connection before receiving HP snapshot turn=#{turn}")
      end
    end

    # ================================================================
    # PvP Attack Phase Barrier
    # Ambos os lados devem confirmar "pronto" antes de executar os
    # ataques do turno. Isso garante que as animações começam juntas.
    # ================================================================
    def pvp_attack_phase_barrier(battle)
      ctx = active_context rescue nil
      return unless ctx && ctx.mode == :pvp && AnilLanRework.connected?
      return unless battle

      turn = battle.turnCount.to_i rescue 0

      # O host inclui o estado RNG DEPOIS de todas as escolhas de AI
      # Este é o ponto definitivo de sync RNG - ambos os lados devem
      # estar no mesmo estado antes de executar os ataques
      extra = { "turn" => turn }
      if ctx.client_index == 0 && ctx.rng
        rng_s = ctx.rng.state
        extra["rng_state"] = rng_s
        AnilLanRework.log("pvp: attack barrier RNG state=#{rng_s} turn=#{turn}")
      end

      AnilLanRework.log("pvp: attack barrier send turn=#{turn} client=#{ctx.client_index}")
      send_phase_sync("pvp_attack_ready", "ready", extra)

      # Aguardar o sinal do parceiro (com window de espera)
      started = Time.now.to_f
      timeout = 8.0
      viewport, window = build_wait_window(AnilLanRework::BattleSync.waiting_text("Aguardando jogador..."))

      begin
        loop do
          pump_network
          remote = next_remote_phase_sync("pvp_attack_ready", "ready", turn)
          if remote
            # Cliente restaura o estado RNG do host (Cable Club style)
            if ctx.client_index != 0 && remote.is_a?(Hash)
              if remote["rng_state"].is_a?(Hash)
                ctx.rng.restore(remote["rng_state"])
                battle.anil_rework_rng = ctx.rng if battle.respond_to?(:anil_rework_rng=)
                AnilLanRework.log("pvp: attack barrier RNG restored state=#{remote['rng_state']} turn=#{turn}")
              elsif remote["rng_state"].is_a?(Integer)
                ctx.rng.restore_state(remote["rng_state"])
                battle.anil_rework_rng = ctx.rng if battle.respond_to?(:anil_rework_rng=)
                AnilLanRework.log("pvp: attack barrier RNG restored state=#{remote['rng_state']} turn=#{turn}")
              end
            end
            AnilLanRework.log("pvp: attack barrier recv turn=#{turn} - both ready")
            break
          end
          break unless AnilLanRework.connected?
          if Time.now.to_f - started >= timeout
            AnilLanRework.log("pvp: attack barrier timeout turn=#{turn} - proceeding anyway")
            break
          end
          Graphics.update rescue nil
          Input.update rescue nil
          window.update rescue nil if window
        end
      ensure
        dispose_wait_window(viewport, window)
      end
    end

    def send_hp_request_to_host(ctx, turn)
      return unless ctx && AnilLanRework.connected?
      AnilLanRework.connection.send_packet("pvp_hp_request", {
        "type"      => "pvp_hp_request",
        "battle_id" => ctx.battle_id.to_s,
        "to_id"     => ctx.partner_id,
        "turn"      => turn
      }) rescue nil
    end

    def receive_hp_request(packet)
      ctx = active_context rescue nil
      return unless ctx && ctx.battle && ctx.client_index == 0
      return unless ctx.battle_id.to_s == packet["battle_id"].to_s
      AnilLanRework.log("pvp: host received HP request from client turn=#{packet['turn']} - resending snapshot")
      pvp_end_of_turn_hp_reconciliation(ctx.battle)
    end

    def receive_hp_snapshot(packet)
      ctx = active_context rescue nil
      return unless ctx && ctx.battle && ctx.battle_id.to_s == packet["battle_id"].to_s
      return unless ctx.mode == :pvp
      @pending_hp_snapshot = packet
    end

    def apply_hp_snapshot_to_battle(battle, packet, expected_turn)
      ctx = active_context rescue nil
      return 0 unless ctx && battle

      turn = packet["turn"].to_i
      battler_states = Array(packet["battlers"])
      corrections = 0

      battler_states.each do |entry|
        next unless entry.is_a?(Hash)
        remote_idx = entry["idx"].to_i
        local_idx = AnilLanRework::CableOrder.flip_index(remote_idx)
        battler = battle.battlers[local_idx] rescue nil
        next unless battler

        # Validar species
        remote_species = entry["species"].to_s
        local_species = (battler.pokemon&.species.to_s rescue "")
        if !remote_species.empty? && !local_species.empty? && remote_species != local_species
          AnilLanRework.log(
            "pvp: snapshot SPECIES MISMATCH battler=#{local_idx} local=#{local_species} remote=#{remote_species} - skip"
          )
          next
        end

        target_hp = entry["hp"].to_i
        if battler.hp != target_hp
          AnilLanRework.log(
            "pvp: end-of-turn HP correction turn=#{turn} battler=#{local_idx}" \
            ":#{battler.pokemon&.name rescue '?'} local=#{battler.hp} host=#{target_hp}"
          )
          battler.hp = target_hp
          corrections += 1
        end
      end
      corrections
    rescue => e
      AnilLanRework.log("pvp: apply_hp_snapshot error #{e.class}: #{e.message}")
      0
    end

    def serialize_mechanics(battle)
      out = {}
      out["mega"] = AnilLanRework::CableOrder.flip_index(battle.megaEvolution[0][0]) if battle.respond_to?(:megaEvolution)
      out["zmove"] = AnilLanRework::CableOrder.flip_index(battle.zMove[0][0]) if battle.respond_to?(:zMove)
      out["dynamax"] = AnilLanRework::CableOrder.flip_index(battle.dynamax[0][0]) if battle.respond_to?(:dynamax)
      out["tera"] = AnilLanRework::CableOrder.flip_index(battle.terastallize[0][0]) if battle.respond_to?(:terastallize)
      out
    end

    def serialize_choice_for_remote_view(battle, battler_index, target_order)
      serialize_coop_choice(battle, battler_index)
    end

    def queue_remote_turn(packet)
      return unless packet.is_a?(Hash)
      battle_id = packet["battle_id"].to_s
      if @active_context && battle_id == @active_context.battle_id
        apply_embedded_party_sync(packet)
        @active_context.pending_turns << packet
      else
        (@buffered_turns[battle_id] ||= []) << packet
      end
    end

    def queue_remote_switch(packet)
      return unless packet.is_a?(Hash)
      battle_id = packet["battle_id"].to_s
      if @active_context && battle_id == @active_context.battle_id
        apply_embedded_party_sync(packet)
        @active_context.pending_switches << packet
      else
        (@buffered_switches[battle_id] ||= []) << packet
      end
    end

    def queue_remote_forced_switch(packet)
      return unless packet.is_a?(Hash)
      battle_id = packet["battle_id"].to_s
      if @active_context && battle_id == @active_context.battle_id
        @active_context.pending_forced_switches << packet
      else
        (@buffered_forced_switches[battle_id] ||= []) << packet
      end
    end

    def queue_field_state_sync(packet)
      return unless packet.is_a?(Hash)
      battle_id = packet["battle_id"].to_s
      if @active_context && battle_id == @active_context.battle_id
        (@active_context_pending_field_syncs ||= []) << packet
      else
        (@buffered_field_sync[battle_id] ||= []) << packet
      end
    end

    def next_field_state_sync(expected_turn)
      return nil unless @active_context
      b_id = @active_context.battle_id.to_s
      if @buffered_field_sync[b_id]
        @active_context_pending_field_syncs ||= []
        @active_context_pending_field_syncs.concat(@buffered_field_sync.delete(b_id))
      end
      return nil unless @active_context_pending_field_syncs
      
      idx = @active_context_pending_field_syncs.index { |p| p["turn"].to_i == expected_turn.to_i }
      if idx
        return @active_context_pending_field_syncs.delete_at(idx)
      end
      nil
    end

    def wait_for_field_state_sync(expected_turn, timeout = 10.0)
      started = Time.now.to_f
      base_text = waiting_text("Aguardando sincronização de campo...")
      viewport, window = build_wait_window(base_text)
      begin
        loop do
          pump_network
          flush_remote_party_refresh
          packet = next_field_state_sync(expected_turn)
          return packet if packet
          return nil unless AnilLanRework.connected?

          return nil if Time.now.to_f - started >= timeout

          Graphics.update
          Input.update
          window.update rescue nil
        end
      ensure
        dispose_wait_window(viewport, window)
      end
    end

    def serialize_mega_evolution_state(battle)
      mega_ev = []
      if battle.respond_to?(:megaEvolution) && battle.megaEvolution
        battle.megaEvolution.each_with_index do |side_array, side_idx|
          next unless side_array
          side_array.each_with_index do |battler_idx, owner_idx|
            next if battler_idx.nil? || battler_idx < 0
            mega_ev << {
              "side" => side_idx,
              "owner" => owner_idx,
              "battler" => battler_idx
            }
          end
        end
      end
      mega_ev
    rescue => e
      AnilLanRework.log("serialize_mega_evolution_state error: #{e.message}")
      []
    end

    def apply_field_state_sync(battle, packet)
      return unless battle && packet.is_a?(Hash)
      
      sender_client_index = packet["sender_client_index"].to_i
      
      # 1. Weather
      weather_str = packet["weather"]
      weather_sym = (weather_str.nil? || weather_str == "None") ? :None : weather_str.to_sym rescue :None
      battle.field.weather = weather_sym
      battle.field.weatherDuration = packet["weather_duration"].to_i
      
      # 2. Terrain
      terrain_str = packet["terrain"]
      terrain_sym = (terrain_str.nil? || terrain_str == "None") ? :None : terrain_str.to_sym rescue :None
      battle.field.terrain = terrain_sym
      battle.field.terrainDuration = packet["terrain_duration"].to_i
      
      # 3. Mega Evolution
      if battle.respond_to?(:megaEvolution) && battle.megaEvolution
        battle.megaEvolution.each_with_index do |side_array, side_idx|
          next unless side_array
          side_array.each_with_index do |_, owner_idx|
            battle.megaEvolution[side_idx][owner_idx] = -1
          end
        end
        Array(packet["mega_evolution"]).each do |entry|
          next unless entry.is_a?(Hash)
          side_idx = entry["side"].to_i
          owner_idx = entry["owner"].to_i
          if @active_context && @active_context.mode == :pvp
            side_idx = 1 - side_idx
            owner_idx = 0
          end
          local_battler = translate_snapshot_battler_index(entry["battler"], sender_client_index, battle)
          if battle.megaEvolution[side_idx]
            battle.megaEvolution[side_idx][owner_idx] = local_battler
          end
        end
      end
      
      # 4. Status Snapshot
      snapshot = packet["snapshot"]
      if snapshot.is_a?(Hash)
        apply_remote_status_snapshot(battle, snapshot.merge("sender_client_index" => sender_client_index))
      end
      
      AnilLanRework.log("apply_field_state_sync done: weather=#{battle.field.weather}/#{battle.field.weatherDuration} terrain=#{battle.field.terrain}/#{battle.field.terrainDuration}")
    rescue => e
      AnilLanRework.log("apply_field_state_sync error #{e.class}: #{e.message}")
    end

    def sync_field_state(battle)
      ctx = @active_context
      return unless ctx && AnilLanRework.connected?
      
      turn = battle.turnCount.to_i
      AnilLanRework.log("sync_field_state start turn=#{turn} client_index=#{ctx.client_index}")
      
      if ctx.client_index == 0
        # Host sends the state
        payload = {
          "battle_id"           => ctx.battle_id.to_s,
          "turn"                => turn,
          "sender_client_index" => 0,
          "weather"             => (battle.field.weather ? battle.field.weather.to_s : "None"),
          "weather_duration"    => battle.field.weatherDuration.to_i,
          "terrain"             => (battle.field.terrain ? battle.field.terrain.to_s : "None"),
          "terrain_duration"    => battle.field.terrainDuration.to_i,
          "mega_evolution"      => serialize_mega_evolution_state(battle),
          "snapshot"            => serialize_coop_status_snapshot(battle)
        }
        AnilLanRework.log("sync_field_state: HOST sending field_sync packet for turn #{turn}")
        AnilLanRework.connection.send_packet("battle_field_sync", payload)
      else
        # Client waits and applies the state
        AnilLanRework.log("sync_field_state: CLIENT waiting for field_sync packet for turn #{turn}")
        packet = wait_for_field_state_sync(turn)
        if packet
          AnilLanRework.log("sync_field_state: CLIENT applying field_sync packet for turn #{turn}")
          apply_field_state_sync(battle, packet)
        else
          AnilLanRework.log("sync_field_state: CLIENT failed to receive field_sync packet for turn #{turn} (timeout)")
        end
      end
    end

    def next_remote_turn(expected_turn = nil)
      return nil unless @active_context
      return @active_context.pending_turns.shift if expected_turn.nil?
      
      # Usar sistema de fila priorizada similar ao next_remote_turn_hash
      idx = @active_context.pending_turns.index { |p| p["turn"].to_i == expected_turn.to_i }
      
      if idx
        # Remover e retornar o pacote encontrado
        packet = @active_context.pending_turns.delete_at(idx)
        
        # Processar pacotes atrasados se houver
        process_delayed_turn_packets(expected_turn)
        
        return packet
      end
      
      nil
    end

    def next_remote_switch(expected_slot = nil)
      return nil unless @active_context
      return @active_context.pending_switches.shift if expected_slot.nil?

      index = @active_context.pending_switches.index { |packet| packet["slot"].to_i == expected_slot.to_i }
      index ? @active_context.pending_switches.delete_at(index) : nil
    end

    def next_remote_forced_switch(expected_idx = nil)
      return nil unless @active_context
      return @active_context.pending_forced_switches.shift if expected_idx.nil?
      
      # Sincroniza indices de battler em modo cooperativo para perspectivas espelhadas
      @active_context.pending_forced_switches.each do |packet|
        if packet.is_a?(Hash) && packet.key?("idxBattler") && !packet["__anil_idx_translated"]
          sender_client_index = @active_context.client_index.to_i == 0 ? 1 : 0
          packet["idxBattler"] = translate_remote_battler_index(packet["idxBattler"], sender_client_index) rescue packet["idxBattler"]
          packet["__anil_idx_translated"] = true
        end
      end

      index = @active_context.pending_forced_switches.index { |packet| packet["idxBattler"].to_i == expected_idx.to_i }
      index ? @active_context.pending_forced_switches.delete_at(index) : nil
    end

    def send_forced_switch_packet(idx_battler, idx_party)
      return unless @active_context && AnilLanRework.connected?
      AnilLanRework.log("battle send forced_switch battle_id=#{@active_context.battle_id} battler=#{idx_battler} party=#{idx_party}")
      AnilLanRework.connection.send_packet("battle_forced_switch",
        "to_id"      => @active_context.partner_id,
        "battle_id"  => @active_context.battle_id,
        "idxBattler" => idx_battler.to_i,
        "idxParty"   => idx_party.to_i
      )
    end

    def wait_for_remote_forced_switch(idx_battler)
      started = Time.now.to_f
      base_text = wait_text_for_remote_switch
      viewport, window = build_wait_window(base_text)
      lock_text = manual_wait_text
      loop do
        return nil if coop_remote_sync_disabled?
        return nil if remote_coop_eliminated_marked?
        pump_network
        packet = next_remote_forced_switch(idx_battler)
        if packet
          AnilLanRework.log("battle recv forced_switch battle_id=#{@active_context.battle_id} battler=#{idx_battler} party=#{packet['idxParty']}")
          return packet
        end
        return nil unless AnilLanRework.connected?

        if remote_manual_lock?
          started = Time.now.to_f
          if window
            w_text = remote_message_active? ? "Aguardando diálogo do parceiro..." : lock_text
            window.text = w_text if window.text != w_text
          end
        else
          if window && window.text != base_text
            window.text = base_text
          end
        end

        return nil if Time.now.to_f - started >= AnilLanRework::TURN_TIMEOUT
        Graphics.update
        Input.update
        window.update rescue nil
      end
    ensure
      dispose_wait_window(viewport, window)
    end

    def wait_for_remote_turn(max_retries = 3)
      retries = 0

      begin
        started = Time.now.to_f
        base_text = wait_text_for_remote_turn
        viewport, window = build_wait_window(base_text)
        lock_text = manual_wait_text

        loop do
          pump_network
          flush_remote_party_refresh
          packet = next_remote_turn
          return packet if packet
          return nil unless AnilLanRework.connected?

          if remote_manual_lock?
            started = Time.now.to_f
            window.text = lock_text if window
          elsif window && window.text != base_text
            window.text = base_text
          end

          # Timeout adaptativo
          timeout = calculate_adaptive_timeout(retries)
          return nil if Time.now.to_f - started >= timeout

          Graphics.update
          Input.update
          window.update rescue nil
        end
      ensure
        dispose_wait_window(viewport, window)
      end
    end

    def wait_for_remote_switch(expected_slot = nil)
      started = Time.now.to_f
      base_text = wait_text_for_remote_switch
      viewport, window = build_wait_window(base_text)
      loop do
        return nil if coop_remote_sync_disabled?
        return nil if remote_coop_eliminated_marked?
        pump_network
        return nil if @active_context && @active_context.instance_variable_get(:@anil_battle_end_received) == true
        flush_remote_party_refresh
        packet = next_remote_switch(expected_slot)
        return packet if packet
        return nil unless AnilLanRework.connected?

        if remote_manual_lock?
          started = Time.now.to_f
          if window
            w_text = remote_message_active? ? "Aguardando diálogo do parceiro..." : manual_wait_text
            window.text = w_text if window.text != w_text
          end
        elsif window && window.text != base_text
          window.text = base_text
        end

        return nil if Time.now.to_f - started >= AnilLanRework::TURN_TIMEOUT
        Graphics.update
        Input.update
        window.update rescue nil
      end
    ensure
      dispose_wait_window(viewport, window)
    end

    def apply_remote_turn_to_battle(battle, packet)
      return unless packet.is_a?(Hash)
      return unless @active_context
      expected_turn = (battle.turnCount.to_i rescue 0)
      remote_turn = packet["turn"].to_i
      if packet.key?("turn") && remote_turn != expected_turn
        AnilLanRework.log("pvp remote turn mismatch battle_id=#{@active_context.battle_id} local_turn=#{expected_turn} remote_turn=#{remote_turn}")
      end
      @active_context.rng.restore(packet["rng"]) if packet["rng"].is_a?(Hash)
      apply_mechanics_to_battle(battle, packet["mechanics"])
      their_indices = battle.pbGetOpposingIndicesInOrder(0).reverse
      Array(packet["choices"]).each do |choice_hash|
        their_index = their_indices.shift
        break unless their_index
        apply_remote_action(battle, their_index, choice_hash)
      end
    end

    def apply_mechanics_to_battle(battle, mechanics)
      return unless mechanics.is_a?(Hash)
      battle.megaEvolution[1][0] = mechanics["mega"].to_i if mechanics.key?("mega") && battle.respond_to?(:megaEvolution)
      battle.zMove[1][0] = mechanics["zmove"].to_i if mechanics.key?("zmove") && battle.respond_to?(:zMove)
      battle.dynamax[1][0] = mechanics["dynamax"].to_i if mechanics.key?("dynamax") && battle.respond_to?(:dynamax)
      battle.terastallize[1][0] = mechanics["tera"].to_i if mechanics.key?("tera") && battle.respond_to?(:terastallize)
    end

    def apply_choice_to_battle(battle, battler_index, choice_hash)
      apply_remote_action(battle, battler_index, choice_hash)
    end

    def send_switch_choice(battle, idx_battler, idx_party)
      return unless @active_context && AnilLanRework.connected?
      slot = if @active_context.mode == :coop
        0
      else
        order = begin
          battle.pbGetOpposingIndicesInOrder(1).reverse
        rescue
          [idx_battler]
        end
        order.index(idx_battler) || 0
      end
      AnilLanRework.connection.send_packet("battle_switch",
        {
          "to_id"           => @active_context.partner_id,
          "battle_id"       => @active_context.battle_id,
          "slot"            => slot,
          "switch_index"    => idx_party.to_i,
          "switch_relative" => (@active_context.mode == :coop ? coop_relative_party_index_for(battle, idx_battler, idx_party) : nil)
        }.tap do |payload|
          party_sync = battle_party_sync_payload
          payload["party_sync"] = party_sync if party_sync
        end
      )
    end

    def update_pending_invite
      return unless @pending_invite
      return unless $scene.is_a?(Scene_Map)
      return if $game_temp&.message_window_showing

      invite    = @pending_invite
      @pending_invite = nil

      # Segurança: Garante que o convite de batalha seja de fato para nós
      if invite["to_id"].to_s != AnilLanRework.self_internal_id.to_s
        AnilLanRework.log("ignored pending battle invite meant for different recipient to_id=#{invite["to_id"]}")
        return
      end

      sender_id = invite["sender_id"].to_s
      peer      = AnilLanRework.players[sender_id]
      sender_name = peer && !peer.name.to_s.empty? ? peer.name.to_s : sender_id
      if invite["sent_at"] && (Time.now.to_f - invite["sent_at"].to_f) >= AnilLanRework::BATTLE_INVITE_TIMEOUT
        AnilLanRework.connection.send_packet("battle_decline",
          "to_id"     => sender_id,
          "battle_id" => invite["battle_id"].to_s,
          "reason"    => "expired"
        )
        pbMessage(_INTL("O convite de batalha expirou.")) rescue nil
        return
      end

      size         = invite["size"].to_i
      invite_rules = normalize_duel_rules(invite["rules"])

      return unless pbConfirmMessage(duel_invite_message(sender_name, size, invite_rules))

      peer.party_blob = Array(invite["party"]) if peer && invite["party"]
      host_selected_blob = Array(invite["selected_party"] || invite["party"])
      host_selected      = AnilLanRework::Serializer.deserialize_party(host_selected_blob)

      local_party = $player.party

      if custom_duel_rules?(invite_rules)
        response = prompt_custom_duel_response_sized(
          invite_rules,
          sender_name,
          host_selected,
          size
        )
        unless response
          AnilLanRework.connection.send_packet("battle_decline",
            "to_id" => sender_id, "battle_id" => invite["battle_id"].to_s
          )
          pbMessage(_INTL("O convite de PvP customizado foi cancelado.")) rescue nil
          return
        end
        invite_rules, local_party = response
        if local_party.empty?
          AnilLanRework.connection.send_packet("battle_decline",
            "to_id" => sender_id, "battle_id" => invite["battle_id"].to_s
          )
          pbMessage(_INTL("Nao foi possivel montar a tua equipe para este PvP.")) rescue nil
          return
        end
      end

      local_party_blob = AnilLanRework::Serializer.serialize_party(local_party)
      AnilLanRework.log("accept_duel battle_id=#{invite['battle_id']} local=#{party_species_names(local_party).inspect} foe=#{party_species_names(host_selected).inspect}")

      AnilLanRework.connection.send_packet("battle_accept",
        "to_id"          => sender_id,
        "battle_id"      => invite["battle_id"].to_s,
        "party"          => AnilLanRework::Serializer.serialize_party($player.party),
        "selected_party" => local_party_blob
      )

      @pending_start = {
        :battle_id    => invite["battle_id"].to_s,
        :peer_id      => sender_id,
        :size         => size,
        :seed         => invite["seed"].to_i,
        :client_index => 1,
        :rules        => invite_rules,
        :party        => host_selected_blob,
        :local_party  => local_party_blob
      }
    end

    def update_pending_start
      return unless @pending_start
      return unless $scene.is_a?(Scene_Map)
      return if $game_temp&.message_window_showing
      data = @pending_start

      if !AnilLanRework.host?
        if !data[:map_id_check]
          expected_peer_id = data[:peer_id].to_s
          expected_peer = AnilLanRework.players[expected_peer_id]
          if !expected_peer || expected_peer.map_id.to_i <= 0
            host_id = AnilLanRework.connection&.host_id.to_s
            expected_peer = AnilLanRework.players[host_id]
          end
          if expected_peer && expected_peer.map_id.to_i > 0
            data[:expected_map_id] = expected_peer.map_id.to_i
            data[:map_id_check] = true
            AnilLanRework.log("pvp start waiting for map transfer to map_id=#{expected_peer.map_id} peer_id=#{expected_peer_id}")
          end
        end

        if data[:expected_map_id]
          current_map = $game_map&.map_id.to_i
          expected_map = data[:expected_map_id].to_i
          AnilLanRework.suppress_peer_interaction!(20)
          return if current_map != expected_map
          return if $game_temp&.player_transferring
          AnilLanRework.log("pvp start map ok map_id=#{current_map}, proceeding")
        end
      end
      @pending_start = nil
      start_pvp_battle(data)
    end

    def start_pvp_battle(data)
      # --- FIX: Forçar ID do Batalha para evitar Desync de ID ---
      battle_id = data[:battle_id].to_s
      
      peer = AnilLanRework.players[data[:peer_id].to_s]
      foe_party = AnilLanRework::Serializer.deserialize_party(data[:party] || (peer && peer.party_blob))
      if foe_party.empty?
        AnilLanRework.log("start_pvp_battle ERROR: foe_party is empty!")
        return 
      end

      trainer_type = AnilLanRework.trainer_type_for_character(peer&.char_name, GameData::TrainerType.keys.first)
      trainer_name = (peer && !peer.name.to_s.empty?) ? peer.name.to_s : "Rival"
      foe_trainer = begin
        NPCTrainer.new(trainer_name, trainer_type)
      rescue
        Trainer.new(trainer_name, trainer_type)
      end
      foe_trainer.party = foe_party
      foe_trainer.multiplayer_skin = peer.char_name if peer && foe_trainer.respond_to?(:multiplayer_skin)
      local_rules = normalize_duel_rules(data[:rules])
      local_party_order = sanitize_party_order(local_rules["local_party_order"])
      local_party = party_from_order(local_party_order)
      local_party = party_from_blob(data[:local_party]) if local_party.empty?
      local_party = AnilLanRework::Serializer.deserialize_party(data[:local_party]) if local_party.empty?
      AnilLanRework.log("start_pvp_battle battle_id=#{data[:battle_id]} client_index=#{data[:client_index]} rules=#{normalize_duel_rules(data[:rules]).inspect} local_party=#{party_species_names(local_party).inspect} foe_party=#{party_species_names(foe_party).inspect}")

      activate_context(
        battle_id: data[:battle_id],
        mode: :pvp,
        client_index: data[:client_index],
        partner_id: data[:peer_id],
        seed: data[:seed],
        rules: data[:rules],
        foe_party: foe_trainer.party,
        local_party_blob: data[:local_party],
        local_party_order: local_party_order
      )
      prepare_local_pvp_party!(data[:battle_id], local_party)

      battle_style = duel_style_from_rules(data[:rules], data[:size])
      AnilLanRework.log("pvp pre-battle: setBattleRule style=#{battle_style}")
      setBattleRule(battle_style) rescue nil
      setBattleRule("nopartner") rescue nil
      AnilLanRework.log("pvp pre-battle: calling TrainerBattle.start_core foe=#{foe_trainer&.name} party_size=#{foe_trainer&.party&.length}")
      if TrainerBattle.respond_to?(:start_core)
        TrainerBattle.start_core(foe_trainer)
      elsif TrainerBattle.respond_to?(:mp_orig_start_core)
        TrainerBattle.mp_orig_start_core(foe_trainer)
      else
        AnilLanRework.log("pvp pre-battle ERROR: TrainerBattle has no start_core method!")
      end
      AnilLanRework.log("pvp post-battle: start_core returned battle_id=#{data[:battle_id]}")
    rescue => e
      AnilLanRework.log("start_pvp_battle error #{e.class}: #{e.message}")
      AnilLanRework.log("start_pvp_battle backtrace: #{e.backtrace&.first(5)&.join(' | ')}")
      $game_temp.clear_battle_rules rescue nil
      remove_partner if respond_to?(:remove_partner)
      clear_context
      AnilLanRework.request_map_graphics_refresh!("pvp_start_error", 3)
      pbMessage(_INTL("O duelo online foi cancelado porque este mapa/interior nao tem posicoes validas para esse tipo de batalha.")) rescue nil
    end

    def prepare_local_pvp_party!(battle_id, local_party)
      local_party = Array(local_party).compact
      return if local_party.empty?
      return unless defined?($player) && $player && $player.respond_to?(:party=)
      return if @pvp_party_backup && @pvp_party_backup_battle_id.to_s == battle_id.to_s
      @pvp_party_backup = Array($player.party)
      @pvp_party_backup_battle_id = battle_id.to_s
      $player.party = local_party
      AnilLanRework.log("prepare_local_pvp_party battle_id=#{battle_id} size=#{local_party.length} party=#{party_species_names(local_party).inspect}")
    rescue => e
      AnilLanRework.log("prepare_local_pvp_party error #{e}")
    end

    def restore_local_pvp_party!(reason = nil)
      backup = @pvp_party_backup
      return unless backup
      return unless defined?($player) && $player && $player.respond_to?(:party=)
      $player.party = backup
      AnilLanRework.log("restore_local_pvp_party reason=#{reason} size=#{backup.length}") if reason
    rescue => e
      AnilLanRework.log("restore_local_pvp_party error #{e}")
    ensure
      @pvp_party_backup = nil
      @pvp_party_backup_battle_id = nil
    end
  end
end


module AnilLanRework
  module TradeSync
    # :autoritativa  -> o servidor marcou o trade_confirm, entao ha quem mande o
    #                   trade_ok e nos NAO mexemos na party sem ele.
    # :servidor_ok   -> o trade_ok ja chegou. Pode chegar ANTES de os dois
    #                   confirms se acertarem (o servidor comita e so depois
    #                   reencaminha o confirm), por isso e uma bandeira e nao um
    #                   salto directo de fase.
    # :espera_desde  -> instante em que se comecou a esperar, para o timeout.
    # :pkmn_recebido -> o Pokemon do parceiro, congelado na confirmacao.
    #
    #   O execute_trade ia buscá-lo ao party_blob VIVO do parceiro. Isso passava
    #   quando os dois trocavam ao mesmo tempo, mas agora espera-se pelo servidor
    #   — e se entretanto chegar um sync da party dele (ja trocada), o indice
    #   remoto passa a apontar para outro Pokemon, e receber-se-ia o proprio de
    #   volta. Congelar aqui remove a corrida.
    Session = Struct.new(:peer_id, :phase, :local_index, :remote_index, :local_confirmed, :remote_confirmed, :outgoing,
                         :autoritativa, :servidor_ok, :espera_desde, :pkmn_recebido)

    # Quanto se espera pelo trade_ok antes de desistir. O commit do servidor e
    # sincrono e local ao processo dele; se nao vier em 20s, caiu a ligacao.
    TRADE_OK_TIMEOUT = 20.0 unless const_defined?(:TRADE_OK_TIMEOUT)

    @pending_invite = nil
    @session = nil

    class << self
      attr_accessor :pending_invite
      attr_accessor :session
    end

    module_function

    def busy?
      !@session.nil?
    end

    def send_party_sync(to_id = nil)
      return unless AnilLanRework.connected?
      return unless defined?($player) && $player
      payload = {
        "party" => AnilLanRework::Serializer.serialize_party($player.party)
      }
      payload["to_id"] = to_id if to_id
      # Inclui map_id para que o servidor roteie apenas para a instância do mapa,
      # evitando broadcast global cross-map que degrada FPS em canais lotados.
      payload["map_id"] = $game_map.map_id if $game_map
      AnilLanRework.connection.send_packet("party_sync", payload)
    rescue => e
      AnilLanRework.log("party_sync error #{e}")
    end

    TRADE_INVITE_TIMEOUT = 90.0 unless const_defined?(:TRADE_INVITE_TIMEOUT)

    def request_trade(peer)
      return unless peer.is_a?(AnilLanRework::RemotePeer)
      return if busy?
      session = Session.new(peer.internal_id.to_s, :await_accept, nil, nil, false, false, true)
      @session = session
      # Sobe o save ANTES de a troca comecar: o servidor confere a posse do
      # Pokemon contra o save em disco, e uma captura recente ainda agrupada pelo
      # throttle faria a troca ser recusada. Ver AUTOSAVE_IMEDIATO no MOD 101.
      AnilLanRework.save_and_upload_save_file("trade_started") rescue nil
      AnilLanRework.connection.send_packet("trade_invite",
        "to_id" => peer.internal_id,
        "party" => AnilLanRework::Serializer.serialize_party_posicional($player.party)
      )

      # Espera visivel, como no PvP customizado. Sem isto o controle voltava na
      # hora e quem convidou nao sabia se o outro tinha recebido ou recusado.
      #
      # A condicao le a propria maquina de estados da troca: o receive_accept
      # troca a fase de :await_accept, e o receive_cancel zera a sessao. Nao ha
      # flag nova para manter em sincronia.
      peer_name = peer.name.to_s
      resultado = AnilLanRework::BattleSync.aguardar_resposta_convite(
        AnilLanRework.ui_format("Aguardando resposta de {1}...", peer_name),
        TRADE_INVITE_TIMEOUT
      ) { @session.nil? || @session.phase != :await_accept }

      if @session.nil?
        # Recusou/cancelou. O receive_cancel adiou a mensagem porque a faixa
        # ainda estava na tela; agora que ela saiu, avisa.
        pbMessage(_INTL("{1} recusou o convite de troca.", peer_name)) rescue nil
        return
      end
      return if @session.phase != :await_accept   # aceitou: segue o fluxo normal

      # Continua em :await_accept — ninguem respondeu.
      @session = nil
      if resultado == :desconectado
        pbMessage(_INTL("A conexão caiu antes de {1} responder.", peer_name)) rescue nil
      else
        # O trade_cancel serve os dois casos: desistir e esgotar o tempo. A
        # sessao do outro lado cai da mesma maneira.
        AnilLanRework.connection.send_packet("trade_cancel", "to_id" => peer.internal_id) rescue nil
        if resultado == :cancelado
          pbMessage(_INTL("Você cancelou o convite de troca.")) rescue nil
        else
          pbMessage(_INTL("{1} não respondeu ao convite de troca.", peer_name)) rescue nil
        end
      end
    end

    def peer_for(session = @session)
      return nil unless session
      AnilLanRework.players[session.peer_id.to_s]
    end

    def clear_session(message = nil)
      @session = nil
      @pending_invite = nil if @pending_invite && !busy?
      pbMessage(message) if message && !message.to_s.empty?
    rescue
      @session = nil
      @pending_invite = nil
    end

    def ensure_scene_ready?
      $scene.is_a?(Scene_Map) && !($game_temp&.message_window_showing) && !(pbMapInterpreterRunning? rescue false)
    end

    def on_packet(packet)
      case packet["type"]
      when "party_sync"
        update_peer_party(packet)
      when "trade_invite"
        receive_invite(packet)
      when "trade_accept"
        receive_accept(packet)
      when "trade_pick"
        receive_pick(packet)
      when "trade_confirm"
        receive_confirm(packet)
      when "trade_ok"
        receive_server_ok(packet)
      when "trade_cancel"
        receive_cancel(packet)
      end
    end

    def update_peer_party(packet)
      peer_id = (packet["sender_id"] || packet["internal_id"] || packet["peer_id"]).to_s
      return if peer_id.empty? || peer_id == AnilLanRework.self_internal_id

      # Rede de diagnostico. Nao consegui provar qual caminho fez um duelo
      # aparecer com a MINHA equipa do lado do adversario; a contaminacao do
      # party_blob por um party_sync atribuido ao id errado e uma das duas
      # hipoteses. Se os dois campos discordarem, fica registado — com o
      # servidor a carimbar o sender_id, isto nunca deveria disparar.
      outro = packet["internal_id"].to_s
      if !outro.empty? && outro != peer_id
        AnilLanRework.log("[PARTY_SYNC] AVISO id ambiguo: sender_id=#{peer_id.inspect} internal_id=#{outro.inspect} — usei o sender_id") rescue nil
      end
      peer = (AnilLanRework.players[peer_id] ||= AnilLanRework::RemotePeer.new)
      peer.internal_id = peer_id
      peer.party_blob = Array(packet["party"])
      if peer.respond_to?(:follower_char=)
        peer.follower_char = AnilLanRework.resolve_peer_follower_char(peer) rescue ""
      end
      AnilLanRework::BattleSync.on_party_sync(peer_id, peer.party_blob)
    end


    def receive_invite(packet)
      # Segurança: Garante que o convite de troca seja de fato para nós
      if packet["to_id"].to_s != AnilLanRework.self_internal_id.to_s
        AnilLanRework.log("ignored trade invite meant for different recipient to_id=#{packet["to_id"]}")
        return
      end
      if busy?
        AnilLanRework.connection.send_packet("trade_cancel",
          "to_id" => packet["sender_id"].to_s,
          "reason" => "busy"
        )
        return
      end
      @pending_invite = packet
    end

    def receive_accept(packet)
      return unless @session && @session.peer_id.to_s == packet["sender_id"].to_s
      peer = peer_for
      peer.party_blob = Array(packet["party"]) if peer && packet["party"]
      @session.phase = :choose_local
    end

    def receive_pick(packet)
      return unless @session && @session.peer_id.to_s == packet["sender_id"].to_s
      peer = peer_for
      peer.party_blob = Array(packet["party"]) if peer && packet["party"]
      @session.remote_index = packet["idx"].to_i
      @session.phase = :confirm if @session.local_index && @session.remote_index
    end

    def receive_confirm(packet)
      return unless @session && @session.peer_id.to_s == packet["sender_id"].to_s
      # A marca de capacidade viaja aqui. Chega sempre antes de qualquer um dos
      # lados ter os dois confirms — ver o comentario no server_runtime.rb.
      @session.autoritativa = true if packet["server_authoritative_trade"]
      if packet["status"].to_s == "accepted"
        @session.remote_confirmed = true
        avancar_apos_confirmacao if @session.local_confirmed
      else
        clear_session(_INTL("A troca foi cancelada pelo outro jogador."))
      end
    end

    # O servidor comitou na nuvem. So a partir daqui e que se pode mexer na party.
    def receive_server_ok(packet)
      return unless @session && @session.peer_id.to_s == packet["sender_id"].to_s
      @session.autoritativa = true
      @session.servidor_ok = true
      AnilLanRework.log("trade: trade_ok recebido do servidor")
      avancar_apos_confirmacao if @session.local_confirmed && @session.remote_confirmed
    end

    # Unico sitio que decide quando se passa a :execute.
    #
    # O trade_ok pode chegar ANTES do confirm reencaminhado: o servidor comita
    # dentro do mutex e so depois e que reencaminha. Por isso nao se salta de
    # fase quando o trade_ok chega — guarda-se a bandeira e volta-se a passar por
    # aqui. Sem isto, quem confirmou primeiro perdia o trade_ok e ficava pendurado.
    def avancar_apos_confirmacao
      session = @session
      return unless session
      if session.autoritativa && !session.servidor_ok
        return if session.phase == :aguardar_servidor
        session.phase = :aguardar_servidor
        session.espera_desde = Time.now.to_f
        AnilLanRework.log("trade: a aguardar confirmacao do servidor")
        return
      end
      session.phase = :execute
    end

    def receive_cancel(packet)
      invite_sender = @pending_invite && @pending_invite["sender_id"].to_s
      return unless (@session && @session.peer_id.to_s == packet["sender_id"].to_s) || invite_sender == packet["sender_id"].to_s
      # Durante a espera do convite a mensagem e adiada: ver aguardando_convite?.
      # Quem convidou exibe o aviso depois que a faixa sai da tela.
      if AnilLanRework::BattleSync.aguardando_convite?
        clear_session
      else
        clear_session(_INTL("A troca foi cancelada."))
      end
    end

    def update_pending
      if @pending_invite && ensure_scene_ready?
        handle_pending_invite
      end
      return unless @session && ensure_scene_ready?
      case @session.phase
      when :choose_local
        choose_local_pokemon
      when :confirm
        confirm_trade
      when :aguardar_servidor
        aguardar_servidor
      when :execute
        execute_trade
      end
    end

    # Fase nova: os dois ja confirmaram, mas a party so muda depois do trade_ok.
    #
    # Se estourar o tempo NAO se troca nada. Com o save autoritativo na nuvem, se
    # o servidor tiver comitado e nos nao ouvimos, o save local e reconciliado a
    # partir da nuvem no proximo arranque; se nao comitou, nada aconteceu. Trocar
    # aqui por conta propria e que seria o erro — era exactamente isso que
    # duplicava o Pokemon.
    def aguardar_servidor
      session = @session
      return unless session
      return if Time.now.to_f - session.espera_desde.to_f < TRADE_OK_TIMEOUT
      AnilLanRework.log("trade: timeout a espera do trade_ok — troca abortada sem mexer na party")
      clear_session(_INTL("O servidor nao confirmou a troca. Nada foi alterado."))
    end

    def handle_pending_invite
      invite = @pending_invite
      @pending_invite = nil
      sender_id = invite["sender_id"].to_s
      peer = AnilLanRework.players[sender_id]
      sender_name = peer && !peer.name.to_s.empty? ? peer.name.to_s : sender_id
      if pbConfirmMessage(AnilLanRework.ui_format("{1} quer trocar Pokemon contigo. Aceitar?", sender_name))
        session = Session.new(sender_id, :choose_local, nil, nil, false, false, false)
        @session = session
        peer.party_blob = Array(invite["party"]) if peer && invite["party"]
        # Mesma razao do request_trade: quem aceita tambem tem a posse conferida
        # contra o save em disco do servidor.
        AnilLanRework.save_and_upload_save_file("trade_started") rescue nil
        AnilLanRework.connection.send_packet("trade_accept",
          "to_id" => sender_id,
          "party" => AnilLanRework::Serializer.serialize_party_posicional($player.party)
        )
      else
        AnilLanRework.connection.send_packet("trade_cancel",
          "to_id" => sender_id,
          "reason" => "declined"
        )
      end
    end

    def choose_local_pokemon
      session = @session
      return unless session
      chosen_idx = -1
      pbFadeOutIn do
        scene = PokemonParty_Scene.new
        screen = PokemonPartyScreen.new(scene, $player.party)
        screen.pbStartScene(_INTL("Escolha o Pokemon para trocar"), false)
        chosen_idx = screen.pbChoosePokemon
        screen.pbEndScene
      end
      if chosen_idx.nil? || chosen_idx.to_i < 0
        AnilLanRework.connection.send_packet("trade_cancel",
          "to_id" => session.peer_id,
          "reason" => "choose_cancel"
        )
        clear_session
        return
      end
      session.local_index = chosen_idx.to_i
      AnilLanRework.connection.send_packet("trade_pick",
        "to_id" => session.peer_id,
        "idx"   => session.local_index,
        # Posicional como o convite e o aceite. Este pacote chega DEPOIS deles e
        # sobrescreve o party_blob do parceiro; se viesse compactado, o blob que
        # o confirm acaba por ler nao teria as posicoes preservadas e o "idx"
        # daqui — que e uma posicao na party real — deixaria de casar com ele.
        "party" => AnilLanRework::Serializer.serialize_party_posicional($player.party)
      )
      session.phase = session.remote_index ? :confirm : :await_remote_pick
    end

    def confirm_trade
      session = @session
      peer = peer_for(session)
      return clear_session(_INTL("Parceiro de troca invalido.")) unless session && peer
      their_party = AnilLanRework::Serializer.deserialize_party_posicional(peer.party_blob)
      my_pkmn = $player.party[session.local_index]
      their_pkmn = their_party[session.remote_index.to_i]
      return clear_session(_INTL("Nao foi possivel validar a troca.")) unless my_pkmn && their_pkmn

      if pbConfirmMessage(AnilLanRework.ui_format("Enviar {1} por {2}?",
                                            AnilLanRework.nome_e_especie(my_pkmn),
                                            AnilLanRework.nome_e_especie(their_pkmn)))
        # Congela o que se vai receber. E este objecto, e nao o blob vivo, que o
        # execute_trade usa depois da luz verde do servidor.
        session.pkmn_recebido = their_pkmn
        session.local_confirmed = true
        AnilLanRework.connection.send_packet("trade_confirm",
          "to_id"   => session.peer_id,
          "status"  => "accepted",
          "idx"     => session.local_index
        )
        if session.remote_confirmed
          avancar_apos_confirmacao
        else
          session.phase = :await_remote_confirm
        end
      else
        AnilLanRework.connection.send_packet("trade_confirm",
          "to_id"  => session.peer_id,
          "status" => "canceled"
        )
        clear_session
      end
    end

    def execute_trade
      session = @session
      peer = peer_for(session)
      return clear_session(_INTL("Parceiro de troca invalido.")) unless session && peer
      my_idx = session.local_index.to_i
      my_pkmn = $player.party[my_idx]
      # O congelado da confirmacao manda. O blob vivo so serve de rede se, por
      # algum caminho antigo, a sessao tiver chegado aqui sem ele.
      their_pkmn = session.pkmn_recebido
      if their_pkmn.nil?
        their_party = AnilLanRework::Serializer.deserialize_party_posicional(peer.party_blob)
        their_pkmn = their_party[session.remote_index.to_i]
      end
      return clear_session(_INTL("Nao foi possivel concluir a troca.")) unless my_pkmn && their_pkmn

      # =====================================================================
      # PRIMEIRO GRAVA, DEPOIS ANIMA.
      #
      # ⚠️ A ordem antiga era o contrario: animacao -> troca -> save. E a
      # animacao de troca demora vários segundos, o que abria uma janela enorme
      # entre "o servidor ja comitou" e "este jogo ja gravou". Quem caisse ali
      # ficava fora de sincronia com o servidor.
      #
      # Aconteceu em 16/08 (guima x lorena): o servidor comitou, um lado
      # aplicou e o outro nunca soube. Resultado — o Mudkip ficou duplicado e o
      # Zigzagoon desapareceu do mundo, na MESMA troca.
      #
      # Invertendo, a janela passa a ser o tempo entre o trade_ok e um
      # Game.save, que e uma fraccao de segundo. Nao fecha o buraco por
      # completo (so o servidor sendo dono do Pokemon fecharia), mas encolhe-o
      # de "a duracao da animacao" para "o tempo de gravar um ficheiro".
      # =====================================================================

      # As mutacoes que o pbStartTrade faria no recebido. Como a party e
      # alterada aqui em cima, ele deixa de poder faze-las — e sem isto o
      # Pokemon ficaria sem dono estrangeiro e sem obtain_method de trocado.
      begin
        their_pkmn.owner = Pokemon::Owner.new_foreign(peer.name.to_s, 0)
        their_pkmn.obtain_method = 2
        their_pkmn.record_first_moves
      rescue => e
        AnilLanRework.log("trade: falha ao carimbar o recebido: #{e.class}: #{e.message}")
      end

      $player.party[my_idx] = their_pkmn
      # Conta a troca ANTES do save: o Game.save logo abaixo grava o numero
      # junto com a party nova, entao o cartao e o save nunca discordam.
      # (O $stats.trade_count do jogo base so e tocado pelo ecra de troca do
      # 0330 e pelo TradeFromPC; esta troca tem caminho proprio e nunca contou.)
      AnilEstatisticasMP.registrar_troca if defined?(AnilEstatisticasMP)
      ($stats.trade_count += 1) rescue nil
      AnilLanRework.refresh_local_follower! rescue nil
      send_party_sync
      if defined?(Game) && Game.respond_to?(:save)
        Game.save
        AnilLanRework.log("auto-save after trade (antes da animacao)")
      elsif defined?(SaveData) && SaveData.respond_to?(:save_to_file)
        SaveData.save_to_file(SaveData::FILE_PATH)
        AnilLanRework.log("auto-save after trade (SaveData, antes da animacao)")
      end

      # Agora sim, a animacao — puramente decorativa a esta altura.
      #
      # NAO se chama o pbStartTrade: ele le `$player.party[pokemonIndex]` para
      # saber quem esta a sair, e a essa altura esse lugar ja tem o Pokemon
      # NOVO. Ele mostraria o recebido a ser enviado. Chama-se a cena
      # directamente, com os dois objectos que ja temos em mao.
      begin
        pbFadeOutIn do
          pbFadeOutInWithMusic do
            cena = PokemonTrade_Scene.new
            cena.pbStartScreen(my_pkmn, their_pkmn, $player.name, peer.name.to_s)
            cena.pbTrade
            cena.pbEndScreen
          end
        end
      rescue => e
        # Se a animacao falhar, a troca JA esta gravada — nada se perde.
        AnilLanRework.log("trade: animacao falhou (a troca ja estava gravada): #{e.class}: #{e.message}")
      end

      clear_session
    end
  end
end


module AnilLanRework
  @battle_wait_depth = 0

  class << self
    attr_accessor :battle_wait_depth

    def in_battle_wait?
      @battle_wait_depth.to_i > 0
    end

    def enter_battle_wait!
      @battle_wait_depth = @battle_wait_depth.to_i + 1
    end

    def leave_battle_wait!
      @battle_wait_depth = [@battle_wait_depth.to_i - 1, 0].max
    end
  end
end


module AnilLanRework
  module BattleSync
    def self.with_battle_wait
      AnilLanRework.enter_battle_wait!
      yield
    ensure
      AnilLanRework.leave_battle_wait!
    end

    class << self
      alias anil_freeze_patch_original_wait_for_remote_actions wait_for_remote_actions unless method_defined?(:anil_freeze_patch_original_wait_for_remote_actions)
      alias anil_freeze_patch_original_wait_for_remote_foe_action wait_for_remote_foe_action unless method_defined?(:anil_freeze_patch_original_wait_for_remote_foe_action)
      alias anil_freeze_patch_original_wait_for_remote_foe_turn wait_for_remote_foe_turn unless method_defined?(:anil_freeze_patch_original_wait_for_remote_foe_turn)
      alias anil_freeze_patch_original_wait_for_remote_turn wait_for_remote_turn unless method_defined?(:anil_freeze_patch_original_wait_for_remote_turn)
      alias anil_freeze_patch_original_wait_for_remote_turn_hash wait_for_remote_turn_hash unless method_defined?(:anil_freeze_patch_original_wait_for_remote_turn_hash)
      alias anil_freeze_patch_original_wait_for_remote_switch wait_for_remote_switch unless method_defined?(:anil_freeze_patch_original_wait_for_remote_switch)
      alias anil_freeze_patch_original_send_pvp_turn_hash send_pvp_turn_hash unless method_defined?(:anil_freeze_patch_original_send_pvp_turn_hash)
      alias anil_freeze_patch_original_queue_remote_turn_hash queue_remote_turn_hash unless method_defined?(:anil_freeze_patch_original_queue_remote_turn_hash)
      alias anil_freeze_patch_original_flush_remote_status_events flush_remote_status_events unless method_defined?(:anil_freeze_patch_original_flush_remote_status_events)
      alias anil_freeze_patch_original_sync_message_step sync_message_step unless method_defined?(:anil_freeze_patch_original_sync_message_step)

      def anil_freeze_patch_wait_deadlines(timeout = nil)
        effective_timeout = timeout.to_f
        effective_timeout = AnilLanRework::TURN_TIMEOUT.to_f if effective_timeout <= 0
        started = Time.now.to_f
        absolute_deadline = started + (effective_timeout * 2.0)
        [started, effective_timeout, absolute_deadline]
      rescue
        started = Time.now.to_f
        [started, AnilLanRework::TURN_TIMEOUT.to_f, started + (AnilLanRework::TURN_TIMEOUT.to_f * 2.0)]
      end

      def anil_freeze_patch_wait_timed_out?(started, timeout, absolute_deadline)
        now = Time.now.to_f
        # Se acabamos de voltar do segundo plano, não disparar timeout
        # para dar tempo da rede se restabelecer
        resume_grace = AnilLanRework.instance_variable_get(:@resume_grace_until) rescue nil
        if resume_grace && now < resume_grace.to_f
          return false
        end
        return true if absolute_deadline && now >= absolute_deadline
        return false if !timeout || timeout.to_f <= 0
        (now - started) >= timeout.to_f
      rescue
        false
      end

      def anil_freeze_patch_context_details(ctx = nil)
        ctx ||= @active_context
        battle = ctx && ctx.battle
        turn = battle ? (battle.turnCount.to_i rescue "nil") : "nil"
        "battle_id=#{ctx&.battle_id || 'nil'} mode=#{ctx&.mode || 'nil'} client_index=#{ctx&.client_index || 'nil'} turn=#{turn}"
      rescue
        "battle_id=nil mode=nil client_index=nil turn=nil"
      end

      def anil_freeze_patch_log_pvp_wait(label, message, ctx = nil)
        ctx ||= @active_context
        return unless ctx && ctx.mode == :pvp
        AnilLanRework.log("#{label} #{anil_freeze_patch_context_details(ctx)} #{message}")
      rescue
      end

      def send_pvp_turn_hash(battle)
        state_hash = anil_freeze_patch_original_send_pvp_turn_hash(battle)
        ctx = @active_context
        if state_hash && ctx && ctx.mode == :pvp
          turn = battle ? (battle.turnCount.to_i rescue 0) : 0
          AnilLanRework.log(
            "pvp turn hash tx #{anil_freeze_patch_context_details(ctx)} expected_turn=#{turn} state_hash=#{state_hash}"
          )
        end
        state_hash
      end

      def queue_remote_turn_hash(packet)
        if packet.is_a?(Hash)
          ctx = @active_context
          battle_id = packet["battle_id"].to_s
          if ctx && ctx.mode == :pvp && ctx.battle_id.to_s == battle_id
            AnilLanRework.log(
              "pvp turn hash rx #{anil_freeze_patch_context_details(ctx)} packet_turn=#{packet['turn'].to_i} state_hash=#{packet['state_hash'].to_i & 0xFFFFFFFF}"
            )
          end
        end
        anil_freeze_patch_original_queue_remote_turn_hash(packet)
      end

      def wait_for_remote_actions(waiting_text = nil, timeout_override = nil, expected_turn = nil, expected_slot = nil)
        return nil if coop_remote_sync_disabled?
        with_battle_wait { anil_freeze_patch_original_wait_for_remote_actions(waiting_text, timeout_override, expected_turn, expected_slot) }
      end

      def wait_for_remote_foe_action(idx_battler, waiting_text = nil)
        return nil if coop_remote_sync_disabled?
        with_battle_wait { anil_freeze_patch_original_wait_for_remote_foe_action(idx_battler, waiting_text) }
      end

      def wait_for_remote_hp_event(idx_battler, hp_kind)
        return nil if coop_remote_sync_disabled?
        with_battle_wait do
          started, effective_timeout, absolute_deadline = anil_freeze_patch_wait_deadlines(AnilLanRework::TURN_TIMEOUT)
          loop do
            return nil if coop_remote_sync_disabled?
            packet = extract_valid_remote_hp_event(idx_battler, hp_kind)
            return packet if packet
            return nil unless AnilLanRework.connected?
            started = Time.now.to_f if remote_manual_lock?
            if anil_freeze_patch_wait_timed_out?(started, effective_timeout, absolute_deadline)
              lock_active = remote_manual_lock?
              AnilLanRework.log(
                "battle hp wait timeout #{anil_freeze_patch_context_details} battler=#{idx_battler} kind=#{hp_kind} " \
                "manual_lock=#{lock_active} absolute=#{Time.now.to_f >= absolute_deadline}"
              )
              return nil
            end
            AnilLanRework.connection.tick
            AnilLanRework.connection.drain { |remote_packet| AnilLanRework::Router.route_packet(remote_packet) }
            flush_remote_party_refresh
            aplicou_status = flush_remote_status_events_safe
            packet = extract_valid_remote_hp_event(idx_battler, hp_kind)
            return packet if packet
            # Antes esta condicao lia pending_status_events.empty? — que era SEMPRE
            # verdadeira, porque o flush acima acabara de esvaziar a fila. A valvula
            # de escape nunca disparava e o cliente 2 ficava os 30s de TURN_TIMEOUT
            # esperando um evento de HP que o host nunca ia mandar (caso classico:
            # veneno que existe so no lado dele). Agora usamos o retorno do flush:
            # se o host ja mandou snapshot, ele passou do ponto — para de esperar.
            # Carencia curta: em operacao normal o evento de HP chega em
            # milissegundos, entao so tratamos a snapshot como "o host passou do
            # ponto" depois de meio segundo sem resposta. Evita abortar uma espera
            # legitima que ia se resolver no proximo pacote, e ainda assim troca
            # os 30s de trava por ~0,5s.
            if aplicou_status && (Time.now.to_f - started) >= 0.5
              AnilLanRework.log("battle hp wait skip by status battle_id=#{@active_context&.battle_id} battler=#{idx_battler} kind=#{hp_kind}")
              return :authoritative_none
            end
            Graphics.update rescue nil
            Input.update rescue nil
          end
        end
      end

      def wait_for_remote_foe_turn
        return nil if coop_remote_sync_disabled?
        with_battle_wait { anil_freeze_patch_original_wait_for_remote_foe_turn }
      end

      def wait_for_remote_called_move(idx_battler)
        return nil if coop_remote_sync_disabled?
        with_battle_wait do
          started = Time.now.to_f
          loop do
            return nil if coop_remote_sync_disabled?
            packet = next_remote_called_move(idx_battler)
            return packet if packet
            return nil unless AnilLanRework.connected?
            return nil if Time.now.to_f - started >= AnilLanRework::TURN_TIMEOUT
            pump_network
            flush_remote_party_refresh
            flush_remote_status_events_safe
            consume_remote_text_steps(@active_context)
            Graphics.update rescue nil
            Input.update rescue nil
          end
        end
      end

      def wait_for_remote_capture_result(idx_battler)
        return nil if coop_remote_sync_disabled?
        with_battle_wait do
          started, effective_timeout, absolute_deadline = anil_freeze_patch_wait_deadlines(AnilLanRework::TURN_TIMEOUT)
          loop do
            return nil if coop_remote_sync_disabled?
            packet = next_remote_capture_result(idx_battler)
            return packet if packet
            return nil unless AnilLanRework.connected?
            started = Time.now.to_f if remote_manual_lock?
            if anil_freeze_patch_wait_timed_out?(started, effective_timeout, absolute_deadline)
              lock_active = remote_manual_lock?
              AnilLanRework.log(
                "battle capture wait timeout #{anil_freeze_patch_context_details} battler=#{idx_battler} " \
                "manual_lock=#{lock_active} absolute=#{Time.now.to_f >= absolute_deadline}"
              )
              return nil
            end
            pump_network
            flush_remote_party_refresh
            flush_remote_status_events_safe
            consume_remote_text_steps(@active_context)
            Graphics.update rescue nil
            Input.update rescue nil
          end
        end
      end

      def wait_for_remote_turn(expected_turn = nil)
        return nil if coop_remote_sync_disabled?
        started, effective_timeout, absolute_deadline = anil_freeze_patch_wait_deadlines(AnilLanRework::TURN_TIMEOUT)
        base_text = wait_text_for_remote_turn
        viewport, window = build_wait_window(base_text)
        anil_freeze_patch_log_pvp_wait("pvp wait remote turn start", "turn=#{expected_turn} timeout=#{effective_timeout}")
        with_battle_wait do
          loop do
            return nil if coop_remote_sync_disabled?
            pump_network
            flush_remote_party_refresh
            packet = next_remote_turn(expected_turn)
            if packet
              choices = Array(packet["choices"]).length
              anil_freeze_patch_log_pvp_wait("pvp wait remote turn recv", "turn=#{packet['turn']} choices=#{choices}")
              return packet
            end
            return nil unless AnilLanRework.connected?
            locked = remote_manual_lock?
            if locked || remote_message_active?
              started = Time.now.to_f
              window.text = remote_message_active? ? "Aguardando diálogo do parceiro..." : manual_wait_text if window
            elsif window && window.text != base_text
              window.text = base_text
            end
            if anil_freeze_patch_wait_timed_out?(started, effective_timeout, absolute_deadline)
              anil_freeze_patch_log_pvp_wait(
                "pvp wait remote turn timeout",
                "expected_turn=#{expected_turn} pending_turns=#{@active_context&.pending_turns&.length || 0} manual_lock=#{locked} absolute=#{Time.now.to_f >= absolute_deadline}"
              )
              return nil
            end
            Graphics.update rescue nil
            Input.update rescue nil
            window.update rescue nil
          end
        end
      ensure
        dispose_wait_window(viewport, window)
      end

      def wait_for_remote_turn_hash(expected_turn)
        return nil if coop_remote_sync_disabled?
        started, effective_timeout, absolute_deadline = anil_freeze_patch_wait_deadlines(AnilLanRework::TURN_TIMEOUT)
        viewport, window = build_wait_window(wait_text_for_turn_hash)
        anil_freeze_patch_log_pvp_wait("pvp wait turn hash start", "expected_turn=#{expected_turn} timeout=#{effective_timeout}")
        with_battle_wait do
          loop do
            return nil if coop_remote_sync_disabled?
            pump_network
            packet = next_remote_turn_hash(expected_turn)
            if packet
              anil_freeze_patch_log_pvp_wait(
                "pvp wait turn hash recv",
                "expected_turn=#{expected_turn} packet_turn=#{packet['turn'].to_i} state_hash=#{packet['state_hash'].to_i & 0xFFFFFFFF}"
              )
              return packet
            end
            return nil unless AnilLanRework.connected?
            locked = remote_manual_lock?
            if locked || remote_message_active?
              started = Time.now.to_f
              window.text = remote_message_active? ? "Aguardando sincronização de diálogos..." : manual_wait_text if window
            end
            if anil_freeze_patch_wait_timed_out?(started, effective_timeout, absolute_deadline)
              anil_freeze_patch_log_pvp_wait(
                "pvp wait turn hash timeout",
                "expected_turn=#{expected_turn} pending_hashes=#{@active_context&.pending_turn_hashes&.length || 0} absolute=#{Time.now.to_f >= absolute_deadline}"
              )
              return nil
            end
            Graphics.update rescue nil
            Input.update rescue nil
            window.update rescue nil
          end
        end
      ensure
        dispose_wait_window(viewport, window)
      end

      def wait_for_remote_switch(expected_slot = nil)
        return nil if coop_remote_sync_disabled?
        return nil if remote_coop_eliminated_marked?
        with_battle_wait { anil_freeze_patch_original_wait_for_remote_switch(expected_slot) }
      end

      # Devolve TRUE se aplicou algum snapshot de status nesta chamada.
      # Quem espera evento de HP precisa desse retorno: a checagem
      # "pending_status_events.empty?" feita DEPOIS deste flush e sempre falsa,
      # porque o proprio flush acabou de esvaziar a fila. Ver o comentario em
      # wait_for_remote_hp_event.
      def flush_remote_status_events_safe
        ctx = @active_context
        battle = ctx && ctx.battle
        return false unless ctx && battle
        return false if !ctx.pending_status_events || ctx.pending_status_events.empty?
        aplicou = false
        until ctx.pending_status_events.empty?
          packet = ctx.pending_status_events.shift
          if packet.is_a?(Hash) && (packet["battlers"] || packet["positions"] || packet["sides"] || packet["field"])
            apply_remote_status_snapshot(battle, packet)
          else
            apply_legacy_remote_status_packet(battle, packet)
          end
          aplicou = true
        end
        ctx.pending_party_refresh = true
        aplicou
      end

      def flush_remote_status_events
        anil_freeze_patch_original_flush_remote_status_events
      end

      def pump_network
        return unless AnilLanRework.connected?
        AnilLanRework.connection.tick
        AnilLanRework.connection.drain { |packet| AnilLanRework::Router.route_packet(packet) }
        consume_remote_text_steps
        consume_remote_text_states
        if AnilLanRework.in_battle_wait?
          flush_remote_status_events_safe
        else
          flush_remote_status_events
        end
      end

      def sync_message_step(message = nil)
        return nil if coop_remote_sync_disabled?
        with_battle_wait { anil_freeze_patch_original_sync_message_step(message) }
      end
    end
  end
end


if defined?(Battle) && defined?(Battle::AI)
  class Battle::AI
    alias anil_rework_original_pbDefaultChooseEnemyCommand pbDefaultChooseEnemyCommand unless method_defined?(:anil_rework_original_pbDefaultChooseEnemyCommand)

    def pbDefaultChooseEnemyCommand(idxBattler, *args, **kwargs, &block)
      ctx = AnilLanRework::BattleSync.active_context
      if ctx && ctx.mode == :coop
        if (@battle.opposes?(idxBattler) rescue false)
          return anil_rework_original_pbDefaultChooseEnemyCommand(idxBattler, *args, **kwargs, &block)
        end

        local_slot, remote_slot = AnilLanRework::BattleSync.coop_slots_for(@battle)
        AnilLanRework.log("coop ai enter battle_id=#{ctx.battle_id} idxBattler=#{idxBattler} local_slot=#{local_slot.inspect} remote_slot=#{remote_slot.inspect} owned=#{@battle.pbOwnedByPlayer?(idxBattler) rescue 'err'}")
        if remote_slot.nil?
          AnilLanRework.log("coop ai no remote slot battle_id=#{ctx.battle_id} idxBattler=#{idxBattler} battlers=[#{AnilLanRework::BattleSync.coop_slots_debug(@battle)}]")
        elsif idxBattler == remote_slot
          AnilLanRework.log("coop ai slot match battle_id=#{ctx.battle_id} local_slot=#{local_slot} remote_slot=#{remote_slot} battlers=[#{AnilLanRework::BattleSync.coop_slots_debug(@battle)}]")
        end
        if idxBattler == remote_slot
          if AnilLanRework::BattleSync.remote_coop_eliminated?(ctx)
            AnilLanRework.log("coop ai remote eliminated battle_id=#{ctx.battle_id} remote_slot=#{idxBattler}")
            return
          end
          existing_choice = @battle.choices[idxBattler] rescue nil
          if existing_choice && existing_choice[0] != :None
            AnilLanRework.log("coop ai remote already registered battle_id=#{ctx.battle_id} remote_slot=#{idxBattler} kind=#{existing_choice[0]}")
            return
          end
          my_choice = @battle.choices[local_slot]
          if !my_choice || my_choice[0] == :None
            wait_until = Time.now.to_f + 0.25
            while Time.now.to_f < wait_until
              Graphics.update
              Input.update
              my_choice = @battle.choices[local_slot]
              break if my_choice && my_choice[0] != :None
            end
          end

          action = if my_choice && my_choice[0] != :None
                     AnilLanRework::BattleSync.serialize_coop_choice(@battle, local_slot)
                   else
                     { "kind" => "None" }
                   end
          AnilLanRework.log("coop ai send action battle_id=#{ctx.battle_id} local_slot=#{local_slot} remote_slot=#{remote_slot} kind=#{action['kind']}")
          AnilLanRework::BattleSync.send_battle_action([action], local_slot)

          remote_actions = AnilLanRework::BattleSync.wait_for_remote_actions(
            AnilLanRework::BattleSync.waiting_text("Aguardando parceiro..."), nil,
            (@battle.turnCount.to_i rescue nil), idxBattler
          )
          if remote_actions && remote_actions[0]
            AnilLanRework.log("coop ai recv action battle_id=#{ctx.battle_id} remote_slot=#{idxBattler} kind=#{remote_actions[0]['kind']}")
            AnilLanRework::BattleSync.apply_remote_action(@battle, idxBattler, remote_actions[0])
            return
          end

          AnilLanRework.log("coop ai timeout fallback battle_id=#{ctx.battle_id} remote_slot=#{idxBattler}")
        end
      end
      anil_rework_original_pbDefaultChooseEnemyCommand(idxBattler, *args, **kwargs, &block)
    end
  end

  class Battle::AI_LanCableRework < Battle::AI
    def pbDefaultChooseEnemyCommand(index)
      ctx = AnilLanRework::BattleSync.active_context
      return super unless ctx && ctx.mode == :pvp
      return if @battle.instance_variable_get(:@anil_rework_pvp_turn_synced)

      their_indices = begin
        @battle.pbGetOpposingIndicesInOrder(0).reverse
      rescue
        [index]
      end

      # Exchange the whole remote turn on the first AI hook that actually runs.
      # Automatic turns such as Rollout/Outrage may skip later hooks entirely,
      # and the command-phase fallback below covers the case where every foe is
      # locked and no AI hook runs this round.
      if AnilLanRework::BattleSync.sync_pvp_turn_bundle(@battle, "enemy_hook_#{index}")
        @battle.instance_variable_set(:@anil_rework_pvp_turn_synced, true)
        return
      end

      AnilLanRework.log("battle_turn timeout fallback battle_id=#{ctx.battle_id}")
      @battle.instance_variable_set(:@anil_rework_pvp_turn_synced, true)
      their_indices.each { |enemy_index| super(enemy_index) }
    end
  end
end

# Evolution code moved to 0449_1_BattleSyncEvolution.rb
if defined?(Battle)
  class Battle
    attr_accessor :anil_rework_rng

    def self.anil_safe_alias(new_name, old_name)
      return if method_defined?(new_name) || private_method_defined?(new_name)
      return unless method_defined?(old_name) || private_method_defined?(old_name)
      alias_method new_name, old_name rescue nil
    end

    anil_safe_alias :anil_rework_original_pbRandom, :pbRandom
    anil_safe_alias :anil_rework_original_pbAIRandom, :pbAIRandom
    anil_safe_alias :anil_rework_original_pbStartBattle, :pbStartBattle
    anil_safe_alias :anil_rework_original_pbStartBattleCore, :pbStartBattleCore
    anil_safe_alias :anil_rework_original_pbEndOfBattle, :pbEndOfBattle
    anil_safe_alias :anil_rework_original_pbItemMenu, :pbItemMenu
    anil_safe_alias :anil_rework_original_pbAutoChooseMove, :pbAutoChooseMove
    anil_safe_alias :anil_rework_original_pbSwitchInBetween, :pbSwitchInBetween
    anil_safe_alias :anil_rework_original_pbEORSwitch, :pbEORSwitch
    anil_safe_alias :anil_rework_original_pbGetReplacementPokemonIndex, :pbGetReplacementPokemonIndex
    anil_safe_alias :anil_rework_original_pbGainExpOne, :pbGainExpOne
    anil_safe_alias :anil_rework_original_pbUsePokeBallInBattle, :pbUsePokeBallInBattle
    anil_safe_alias :anil_rework_original_pbThrowPokeBall, :pbThrowPokeBall
    anil_safe_alias :anil_rework_original_pbCaptureCalc, :pbCaptureCalc
    anil_safe_alias :anil_rework_original_pbAttackPhaseItems, :pbAttackPhaseItems
    anil_safe_alias :anil_rework_original_pbCalculatePriority, :pbCalculatePriority
    anil_safe_alias :anil_rework_original_pbIsOwner, :pbIsOwner?
    anil_safe_alias :anil_rework_original_pbOwnedByPlayer, :pbOwnedByPlayer?
    anil_safe_alias :anil_rework_original_pbReplace, :pbReplace
    anil_safe_alias :anil_rework_original_pbTeamIndexRange, :pbTeamIndexRangeFromBattlerIndex

    def pbTeamIndexRangeFromBattlerIndex(idxBattler)
      ctx = AnilLanRework::BattleSync.active_context rescue nil
      if ctx && ctx.mode == :coop && !(opposes?(idxBattler) rescue true)
        if AnilLanRework::BattleSync.coop_remote_sync_disabled?(ctx)
          # Se o parceiro foi derrotado e saiu (solo mode), toda a equipe ativa local é restrita a 0..5
          return 0, 6
        end
      end
      anil_rework_original_pbTeamIndexRange(idxBattler)
    end

    def pbOwnedByPlayer?(idxBattler)
      ctx = AnilLanRework::BattleSync.active_context rescue nil
      if ctx && ctx.mode == :coop
        local_slot, remote_slot = AnilLanRework::BattleSync.coop_slots_for(self) rescue [nil, nil]
        
        # Se o parceiro foi eliminado e o sync de rede foi desativado (solo mode):
        # O jogador sobrevivente local assume total controle local de ambos os slots do lado aliado!
        if AnilLanRework::BattleSync.coop_remote_sync_disabled?(ctx)
          return !opposes?(idxBattler)
        end

        # Se estamos na fase de ataque (execução do turno), ambos os slots aliados pertencem ao lado do jogador
        # para simulação de batalha idêntica (ex: obediência, afeto, badge boosts).
        if @anil_rework_in_attack_phase
          return !opposes?(idxBattler)
        end

        # Se o parceiro foi eliminado, o jogador ativo assume o controle do slot remoto dele.
        # Logo, ambos os slots são considerados como owned pelo jogador local ativo!
        if idxBattler == remote_slot && AnilLanRework::BattleSync.remote_coop_eliminated?(ctx)
          return true
        end
        if idxBattler == local_slot && AnilLanRework::BattleSync.local_coop_eliminated?(ctx)
          return true
        end

        # No fluxo coop normal, o local_slot pertence ao jogador local
        return true if idxBattler == local_slot
        return false if idxBattler == remote_slot
      end
      anil_rework_original_pbOwnedByPlayer(idxBattler)
    end

    def pbReplace(idxBattler, idxParty, batonPass = false)
      ctx = AnilLanRework::BattleSync.active_context rescue nil
      if ctx && ctx.mode == :coop && !(opposes?(idxBattler) rescue true)
        local_slot, remote_slot = AnilLanRework::BattleSync.coop_slots_for(self) rescue [nil, nil]
        partner_eliminated = AnilLanRework::BattleSync.remote_coop_eliminated?(ctx) rescue false
        local_eliminated = AnilLanRework::BattleSync.local_coop_eliminated?(ctx) rescue false
        
        # Se o slot pertence a um parceiro que foi eliminado da batalha:
        # Para evitar o embaralhamento e roubo de posse dos Pokémon no party compartilhado,
        # nós NÃO alteramos/trocamos a ordem do party (partyOrder), apenas inicializamos e enviamos!
        if (idxBattler == remote_slot && partner_eliminated) || (idxBattler == local_slot && local_eliminated)
          AnilLanRework.log("coop pbReplace bypass party order swap for eliminated partner slot=#{idxBattler} party_idx=#{idxParty}")
          party = pbParty(idxBattler)
          @battlers[idxBattler].pbInitialize(party[idxParty], idxParty, batonPass)
          pbSendOut([[idxBattler, party[idxParty]]])
          pbCalculatePriority(false, [idxBattler]) if Settings::RECALCULATE_TURN_ORDER_AFTER_SPEED_CHANGES
          return
        end
      end
      anil_rework_original_pbReplace(idxBattler, idxParty, batonPass)
    end

    # =========================================================================
    # Patch pbIsOwner? para modo coop
    # No coop, o parceiro é injetado como um segundo trainer no lado do jogador.
    # O PE original verifica ownership comparando trainer indices, mas isso falha
    # porque o battler do parceiro (do ponto de vista dele) está no slot 0, e
    # os Pokémon dele estão em indices 6+ no party combinado.
    # Este patch garante que cada battler aliado pode acessar os Pokémon do
    # próprio time range (definido por pbTeamIndexRangeFromBattlerIndex).
    # =========================================================================
    def pbIsOwner?(idxBattler, idxParty)
      ctx = AnilLanRework::BattleSync.active_context rescue nil
      if ctx && ctx.mode == :coop && !(opposes?(idxBattler) rescue true)
        begin
          local_slot, remote_slot = AnilLanRework::BattleSync.coop_slots_for(self)
          
          # Se a rede de coop remoto está desativada (parceiro saiu/blackout):
          # O jogador local ativo assume controle de ambos os slots usando apenas a sua própria equipe (0..5)!
          if AnilLanRework::BattleSync.coop_remote_sync_disabled?(ctx)
            return idxParty >= 0 && idxParty < 6
          end

          # Se o parceiro foi eliminado, o jogador local assume o controle do slot remoto.
          # Logo, os Pokémon do jogador local são válidos para o slot remoto!
          if idxBattler == remote_slot && AnilLanRework::BattleSync.remote_coop_eliminated?(ctx)
            idxStart, idxEnd = pbTeamIndexRangeFromBattlerIndex(local_slot)
            return true if idxParty >= idxStart && idxParty < idxEnd
          end
          
          # Se o jogador local foi eliminado, o parceiro assume o controle do slot local.
          # Logo, os Pokémon do parceiro são válidos para o slot local!
          if idxBattler == local_slot && AnilLanRework::BattleSync.local_coop_eliminated?(ctx)
            idxStart, idxEnd = pbTeamIndexRangeFromBattlerIndex(remote_slot)
            return true if idxParty >= idxStart && idxParty < idxEnd
          end

          # Comportamento padrão de propriedade coop
          idxStart, idxEnd = pbTeamIndexRangeFromBattlerIndex(idxBattler)
          return true if idxParty >= idxStart && idxParty < idxEnd
        rescue
        end
      end
      anil_rework_original_pbIsOwner(idxBattler, idxParty)
    end

    alias anil_rework_original_pbCanSwitchIn pbCanSwitchIn? unless method_defined?(:anil_rework_original_pbCanSwitchIn)

    def pbCanSwitchIn?(idxBattler, idxParty, partyScene = nil)
      ctx = AnilLanRework::BattleSync.active_context rescue nil
      if ctx && ctx.mode == :coop && !(opposes?(idxBattler) rescue true)
        party = pbParty(idxBattler)
        pkmn = party[idxParty] rescue nil
        is_owner = pbIsOwner?(idxBattler, idxParty)
        in_battle = pbFindBattler(idxParty, idxBattler)
        AnilLanRework.log(
          "coop pbCanSwitchIn? battler=#{idxBattler} idxParty=#{idxParty} " \
          "party_size=#{party.length} pkmn=#{pkmn&.name || 'nil'} " \
          "able=#{pkmn&.able?} egg=#{pkmn&.egg?} fainted=#{pkmn&.fainted?} " \
          "is_owner=#{is_owner} in_battle=#{in_battle&.index.inspect} " \
          "team_range=#{(pbTeamIndexRangeFromBattlerIndex(idxBattler) rescue 'err').inspect}"
        )
      end
      anil_rework_original_pbCanSwitchIn(idxBattler, idxParty, partyScene)
    end

    alias anil_rework_original_pbCanSwitchOut pbCanSwitchOut? unless method_defined?(:anil_rework_original_pbCanSwitchOut)

    # Efeitos de trapping FANTASMA.
    #
    # O battler montado a partir da party serializada nasce com Commander=[]
    # (truthy em Ruby) e MeanLook/JawLock/Octolock=0 em vez dos defaults
    # nil/-1. Como nesses tres um valor >= 0 significa "preso pelo battler de
    # indice N", o jogo lia lixo de inicializacao como prisao real e recusava a
    # troca — a mensagem de "nao podes trocar" no meio da batalha.
    #
    # Antes isto so valia para ctx.mode == :coop. O PvP passava batido e era
    # exatamente onde o jogador ficava preso. Agora vale para os dois.
    #
    # A checagem e POR LADO, nao por "== 0": um indice de captor que aponta para
    # o proprio lado do preso e impossivel numa prisao de verdade (Mean Look,
    # Block e Spider Web sempre vem do lado contrario), entao so nesse caso o
    # valor e lixo. Assim um trapping legitimo do oponente continua prendendo,
    # que e o que importa num PvP competitivo.
    def anil_neutralize_phantom_traps(battler, idxBattler)
      return {} unless battler
      saved = {}
      cm = battler.effects[PBEffects::Commander] rescue nil
      if cm.is_a?(Array) && cm.empty?
        saved[:Commander] = cm
        battler.effects[PBEffects::Commander] = nil
      end
      {
        :MeanLook => PBEffects::MeanLook,
        :JawLock  => PBEffects::JawLock,
        :Octolock => PBEffects::Octolock
      }.each do |nome, efeito|
        valor = battler.effects[efeito] rescue -1
        next unless valor.is_a?(Integer) && valor >= 0
        next if (opposes?(idxBattler, valor) rescue false)   # prisao real
        saved[nome] = valor
        battler.effects[efeito] = -1
      end
      saved
    rescue
      {}
    end

    def anil_restore_phantom_traps(battler, saved)
      return unless battler && saved.is_a?(Hash)
      battler.effects[PBEffects::Commander] = saved[:Commander] if saved.key?(:Commander)
      battler.effects[PBEffects::MeanLook]  = saved[:MeanLook]  if saved.key?(:MeanLook)
      battler.effects[PBEffects::JawLock]   = saved[:JawLock]   if saved.key?(:JawLock)
      battler.effects[PBEffects::Octolock]  = saved[:Octolock]  if saved.key?(:Octolock)
    rescue
    end

    def anil_phantom_trap_mode?(ctx)
      return false unless ctx
      ctx.mode == :coop || ctx.mode == :pvp
    rescue
      false
    end

    def pbCanSwitchOut?(idxBattler, partyScene = nil)
      ctx = AnilLanRework::BattleSync.active_context rescue nil
      if anil_phantom_trap_mode?(ctx) && !(opposes?(idxBattler) rescue true)
        battler = @battlers[idxBattler]
        if battler
          AnilLanRework.log(
            "#{ctx.mode} pbCanSwitchOut? battler=#{idxBattler} " \
            "MeanLook=#{(battler.effects[PBEffects::MeanLook] rescue '?').inspect} " \
            "Commander=#{(battler.effects[PBEffects::Commander] rescue '?').inspect} " \
            "trapped=#{(battler.trappedInBattle? rescue '?')}"
          )

          saved = anil_neutralize_phantom_traps(battler, idxBattler)
          if saved.any?
            AnilLanRework.log("#{ctx.mode} pbCanSwitchOut fix battler=#{idxBattler} neutralized=#{saved.keys.join(',')}")
          end

          result = anil_rework_original_pbCanSwitchOut(idxBattler, partyScene)
          anil_restore_phantom_traps(battler, saved)

          AnilLanRework.log("#{ctx.mode} pbCanSwitchOut result battler=#{idxBattler} result=#{result}")
          return result
        end
      end
      anil_rework_original_pbCanSwitchOut(idxBattler, partyScene)
    end


    alias anil_rework_original_pbCanSwitch pbCanSwitch? unless method_defined?(:anil_rework_original_pbCanSwitch)

    def pbCanSwitch?(idxBattler, idxParty = -1, partyScene = nil)
      ctx = AnilLanRework::BattleSync.active_context rescue nil
      # O Commander=[] (truthy) causa crash no pbCanSwitch? original porque a
      # linha 429 usa 'battler' (variável inexistente nesse escopo).
      # Neutralizamos antes de chamar o original — os mesmos efeitos fantasma do
      # pbCanSwitchOut?, e pelo mesmo motivo tambem valem para o PvP.
      if anil_phantom_trap_mode?(ctx) && !(opposes?(idxBattler) rescue true)
        battler = @battlers[idxBattler]
        saved   = anil_neutralize_phantom_traps(battler, idxBattler)

        result = anil_rework_original_pbCanSwitch(idxBattler, idxParty, partyScene)

        anil_restore_phantom_traps(battler, saved)

        if idxParty >= 0
          AnilLanRework.log(
            "#{ctx.mode} pbCanSwitch? battler=#{idxBattler} idxParty=#{idxParty} result=#{result}"
          )
        end
        return result
      end
      anil_rework_original_pbCanSwitch(idxBattler, idxParty, partyScene)
    end

    def pbRandom(x)
      if anil_rework_rng
        anil_rework_rng.rand(x)
      else
        anil_rework_original_pbRandom(x)
      end
    end

    def pbAIRandom(x)
      if anil_rework_rng
        anil_rework_rng.rand(x)
      else
        anil_rework_original_pbAIRandom(x)
      end
    end if method_defined?(:anil_rework_original_pbAIRandom)

    def rand(x = nil)
      if anil_rework_rng
        anil_rework_rng.rand(x)
      else
        Kernel.rand(x)
      end
    end

    def anil_rework_force_valid_coop_layout!(source = nil)
      ctx = AnilLanRework::BattleSync.active_context rescue nil
      return unless ctx && ctx.mode == :coop
      player_count = Array(@player).length
      return if player_count < 2

      remote_sync_disabled = AnilLanRework::BattleSync.coop_remote_sync_disabled?(ctx) rescue false
      remote_eliminated = AnilLanRework::BattleSync.remote_coop_eliminated_marked?(ctx) rescue false

      foe_count = Array(@party2).compact.count do |pkmn|
        pkmn && (!pkmn.respond_to?(:able?) || pkmn.able?)
      end

      # Se o parceiro foi eliminado (saiu ou está assistindo) e só sobrou 1 oponente, vira "single"
      partner_out = remote_sync_disabled || remote_eliminated
      desired_rule = if partner_out && foe_count <= 1
        "single"
      else
        foe_count <= 1 ? "2v1" : "double"
      end

      current_rule = "#{pbSideSize(0)}v#{pbSideSize(1)}"
      desired_size = case desired_rule
      when "single" then [1, 1]
      when "2v1" then [2, 1]
      else [2, 2]
      end

      return if @sideSizes == desired_size

      setBattleMode(desired_rule)
      begin
        $game_temp.battle_rules["size"] = desired_rule if defined?($game_temp) && $game_temp
      rescue
      end
      AnilLanRework.log("battle coop layout fix battle_id=#{ctx.battle_id} source=#{source} from=#{current_rule} to=#{desired_rule} foe_count=#{foe_count}")
    end

    def pbStartBattle(*args)
      anil_rework_force_valid_coop_layout!("pbStartBattle")
      AnilLanRework.clear_popups rescue nil
      AnilLanRework::ChatInputHUD.close rescue nil
      anil_rework_original_pbStartBattle(*args)
    end

    def pbStartBattleCore(*args)
      ctx = AnilLanRework::BattleSync.active_context
      AnilLanRework.clear_skip_battle_evolution_once
      AnilLanRework::WorldSync.send_player_state if AnilLanRework.connected?
      if ctx
        self.anil_rework_rng = ctx.rng
        ctx.battle = self
        @battleAI = Battle::AI_LanCableRework.new(self) if ctx.mode == :pvp
        AnilLanRework.log("battle hook start battle_id=#{ctx.battle_id} client_index=#{ctx.client_index} mode=#{ctx.mode} rules=#{($game_temp&.battle_rules || {}).inspect} partner=#{$PokemonGlobal&.partner ? Array($PokemonGlobal.partner[3]).length : 0}")
        AnilLanRework::BattleSync.refresh_remote_party_battlers
      else
        self.anil_rework_rng = nil
      end
      anil_rework_original_pbStartBattleCore(*args)
    rescue => e
      AnilLanRework.log("battle hook error battle_id=#{ctx&.battle_id} error=#{e.class}: #{e}")
      begin
        bt = Array(e.backtrace).first(8)
        AnilLanRework.log("battle hook backtrace battle_id=#{ctx&.battle_id} trace=#{bt.join(' | ')}")
      rescue
      end
      raise
    end

    def pbCalculatePriority(fullCalc = false, indexArray = nil)
      ctx = AnilLanRework::BattleSync.active_context
      # Se nao for PvP nem Coop ou nao estivermos no recalculo completo, usar a logica original
      unless ctx && [:pvp, :coop].include?(ctx.mode) && fullCalc
        return anil_rework_original_pbCalculatePriority(fullCalc, indexArray)
      end

      # =========================================================================
      # LOGICA DE PRIORIDADE DETERMINISTICA PARA PVP/COOP (Baseado no Cable Club)
      # Garante que Speed Ties sejam resolvidas exatamente da mesma forma nos dois
      # clientes, usando o anil_rework_rng que já está sincronizado.
      # =========================================================================
      needRearranging = false
      @priorityTrickRoom = (@field.effects[PBEffects::TrickRoom] > 0)
      
      # Geramos a lista aleatória SINCRONIZADA usando o rng compartilhado
      randomOrder = Array.new(maxBattlerIndex + 1) { |i| i }
      (randomOrder.length - 1).times do |i|
        r = i + pbRandom(randomOrder.length - i)
        randomOrder[i], randomOrder[r] = randomOrder[r], randomOrder[i]
      end
      
      @priority.clear
      (0..maxBattlerIndex).each do |i|
        b = @battlers[i]
        next if !b
        
        # O cliente 1 inverte a leitura para ser justa contra o host no desempate
        tie_breaker_index = i
        if ctx.client_index == 1
          if ctx.mode == :coop
            if i == 0
              tie_breaker_index = 2
            elsif i == 2
              tie_breaker_index = 0
            end
          else # :pvp
            tie_breaker_index = i ^ 1
          end
        end
        tie_breaker_value = randomOrder[tie_breaker_index]
        
        entry = [b, b.pbSpeed, 0, 0, 0, 0, tie_breaker_value]
        
        if @choices[b.index][0] == :UseMove || @choices[b.index][0] == :Shift
          if @choices[b.index][0] == :UseMove
            move = @choices[b.index][2]
            pri = move.pbPriority(b)
            
            if b.abilityActive?
              pri = Battle::AbilityEffects.triggerPriorityChange(b.ability, b, move, pri)
            end
            if b.itemActive?
              pri = Battle::ItemEffects.triggerPriorityChange(b.item, b, move, pri)
            end
            
            entry[5] = pri
            @choices[b.index][4] = pri
          end
          
          if b.abilityActive?
            entry[2] = Battle::AbilityEffects.triggerPriorityBracketChange(b.ability, b, self)
          end
          if b.itemActive?
            entry[3] = Battle::ItemEffects.triggerPriorityBracketChange(b.item, b, self)
          end
        end
        
        @priority.push(entry)
      end
      needRearranging = true

      @priority.each do |entry|
        entry[0].effects[PBEffects::PriorityAbility] = false
        entry[0].effects[PBEffects::PriorityItem] = false      
        subpri = entry[2]
        if (subpri == 0 && entry[3] != 0) || (subpri < 0 && entry[3] >= 1)
          subpri = entry[3]
          entry[0].effects[PBEffects::PriorityItem] = true
        elsif subpri != 0
          entry[0].effects[PBEffects::PriorityAbility] = true
        end
        entry[4] = subpri
      end
      
      if needRearranging
        @priority.sort! do |a, b|
          if a[5] != b[5]
            b[5] <=> a[5]
          elsif a[4] != b[4]
            b[4] <=> a[4]
          elsif @priorityTrickRoom
            (a[1] == b[1]) ? b[6] <=> a[6] : a[1] <=> b[1]
          else
            (a[1] == b[1]) ? b[6] <=> a[6] : b[1] <=> a[1]
          end
        end
        
        if $DEBUG
          logMsg = "[AnilLanRework Priority] Client #{ctx.client_index}: "
          @priority.each_with_index do |entry, i|
            logMsg += ", " if i > 0
            battler = entry[0]
            logMsg += "#{battler.pbThis(i > 0)} (Tie: #{entry[6]})"
          end
          AnilLanRework.log(logMsg)
        end
      end
    end


    def pbEndOfBattle(*args)
      ctx = AnilLanRework::BattleSync.active_context
      forced_local_coop_loss = (ctx && ctx.mode == :coop && AnilLanRework::BattleSync.local_coop_eliminated?(ctx))
      @decision = 2 if forced_local_coop_loss
      result = anil_rework_original_pbEndOfBattle(*args)
      if ctx && AnilLanRework.connected? && !forced_local_coop_loss
        AnilLanRework.connection.send_packet("battle_end",
          "battle_id" => ctx.battle_id,
          "to_id"     => ctx.partner_id,
          "result"    => result,
          "mode"      => ctx.mode.to_s
        )
        if ctx.mode == :coop && result == 1 # Victory in co-op
          AnilLanRework.log("Co-op victory detected, triggering sync and save")
          AnilLanRework.last_battle_end_frame = Graphics.frame_count
          AnilLanRework::WorldSync.send_snapshot_if_host if AnilLanRework.host?
          if defined?(Game) && Game.respond_to?(:save)
            Game.save
          elsif defined?(SaveData) && SaveData.respond_to?(:save_to_file)
            SaveData.save_to_file(SaveData::FILE_PATH)
          end
        end
      end
      result
    ensure
      self.anil_rework_rng = nil
      ctx.battle = nil if ctx
      AnilLanRework::BattleSync.restore_local_pvp_party!("pbEndOfBattle") if ctx && ctx.mode == :pvp
      AnilLanRework::BattleSync.remove_partner if ctx && ctx.mode == :coop
      AnilLanRework::BattleSync.clear_context
      AnilLanRework::BattleSyncEvolution.clear_evolution_callbacks(ctx.battle_id) if ctx
      AnilLanRework::BattleSyncEvolution.update_evolution_visuals
      AnilLanRework::WorldSync.send_player_state if AnilLanRework.connected?
    end

    def anil_rework_handle_local_coop_elimination
      ctx = AnilLanRework::BattleSync.active_context
      return false unless ctx && ctx.mode == :coop && @decision == 0
      return false if AnilLanRework::BattleSync.local_coop_eliminated_marked?(ctx)
      local_slot, = AnilLanRework::BattleSync.coop_slots_for(self)
      return false if local_slot.nil?
      
      # Verifica se todos os Pokémon da equipe própria local estão desmaiados
      has_able = false
      eachInTeamFromBattlerIndex(local_slot) do |pkmn, i|
        has_able = true if pkmn && pkmn.able?
      end
      return false if has_able

      return false unless AnilLanRework::BattleSync.mark_local_coop_eliminated!(self)
      
      # Se o parceiro também já foi derrotado/eliminado, não há ninguém para assistir!
      # A partida acabou para ambos e deve ser encerrada imediatamente como derrota.
      partner_eliminated = AnilLanRework::BattleSync.remote_coop_eliminated?(ctx) rescue false
      if partner_eliminated
        AnilLanRework.log("coop both players fainted blackout triggered battle_id=#{ctx.battle_id}")
        @decision = 2
        return true
      end

      return false if AnilLanRework::BattleSync.local_coop_watch_until_end?(ctx)
      AnilLanRework.log("coop local blackout triggered battle_id=#{ctx.battle_id} local_slot=#{local_slot}")
      @decision = 2
      true
    rescue => e
      AnilLanRework.log("anil_rework_handle_local_coop_elimination error #{e.class}: #{e.message}")
      false
    end

    def pbGainExpOne(idxParty, defeatedBattler, numPartic, expShare, expAll, showMessages = true)
      AnilLanRework.log("pbGainExpOne: ENTER idxParty=#{idxParty}")
      pkmn = pbParty(0)[idxParty] rescue nil
      before_blob = pkmn ? AnilLanRework::Serializer.serialize_pokemon(pkmn) : nil
      before_level = pkmn ? pkmn.level.to_i : 0
      # Atualiza a mensagem contextual para o parceiro
      ctx = AnilLanRework::BattleSync.active_context rescue nil
      partner_injected = (AnilLanRework::BattleSync.instance_variable_get(:@partner_injected) rescue false)
      if ctx && ctx.mode == :coop && AnilLanRework.connected? && partner_injected
        AnilLanRework::BattleSync.update_manual_lock_reason("exp_gaining")
      end
      result = anil_rework_original_pbGainExpOne(idxParty, defeatedBattler, numPartic, expShare, expAll, showMessages)
      pkmn = pbParty(0)[idxParty] rescue nil
      after_blob = pkmn ? AnilLanRework::Serializer.serialize_pokemon(pkmn) : nil
      after_level = pkmn ? pkmn.level.to_i : before_level
      leveled_up = after_level > before_level
      
      if leveled_up
        ctx = AnilLanRework::BattleSync.active_context rescue nil
        is_coop_active = (ctx && ctx.mode == :coop && partner_injected)

        if AnilLanRework.connected? && is_coop_active
          # Sinaliza level up para o parceiro ver mensagem contextual
          AnilLanRework::BattleSync.update_manual_lock_reason("level_up")
          party_sync = AnilLanRework::Serializer.serialize_party($player.party)
          AnilLanRework.connection.send_packet("battle_action",
            "to_id"      => ctx.partner_id,
            "battle_id"  => ctx.battle_id,
            "actions"    => [],
            "party_sync" => party_sync
          )
          AnilLanRework.log("coop level-up party_sync sent battle_id=#{ctx.battle_id} level=#{after_level}")
          
          # NOTA: A evolução é tratada pelo 003_Multiplayer_Evolution.rb
          # Não chamar check_evolution_and_sync_multipleyer_from_pokemon aqui
          # para evitar conflitos de evolução duplicada
        end
      else
        AnilLanRework::BattleSync.sync_party_if_needed(before_blob, after_blob, false)
      end
      result
    end

    def pbItemMenu(idxBattler, firstAction)
      ctx = AnilLanRework::BattleSync.active_context
      if ctx && ctx.mode == :pvp
        pbDisplay(_INTL("A Mochila esta desativada no duelo LAN."))
        return false
      end
      anil_rework_original_pbItemMenu(idxBattler, firstAction)
    end

    def anil_rework_ball_context_for(user_index)
      ctx = AnilLanRework::BattleSync.active_context
      return nil unless ctx && ctx.mode == :coop
      local_slot, remote_slot = AnilLanRework::BattleSync.coop_slots_for(self)
      return nil if local_slot.nil? || remote_slot.nil?
      if user_index.to_i == remote_slot.to_i
        return {
          "battle_id"    => ctx.battle_id.to_s,
          "mode"         => "remote_mirror",
          "thrower_name" => AnilLanRework::BattleSync.remote_partner_name.to_s,
          "user_slot"    => remote_slot.to_i
        }
      end
      return {
        "battle_id" => ctx.battle_id.to_s,
        "mode"      => "local_authoritative",
        "user_slot" => local_slot.to_i
      } if user_index.to_i == local_slot.to_i
    rescue
      nil
    end

    def pbUsePokeBallInBattle(item, idxBattler, userBattler)
      @anil_rework_ball_context = anil_rework_ball_context_for(userBattler.index)
      anil_rework_original_pbUsePokeBallInBattle(item, idxBattler, userBattler)
    ensure
      @anil_rework_ball_context = nil
    end

    def pbCaptureCalc(pkmn, battler, catch_rate, ball)
      ball_ctx = @anil_rework_ball_context
      if ball_ctx && ball_ctx["mode"].to_s == "remote_mirror"
        packet = AnilLanRework::BattleSync.wait_for_remote_capture_result(battler.index)
        if packet
          @criticalCapture = packet["critical"] == true
          shakes = packet["num_shakes"].to_i
          AnilLanRework.log("coop mirrored capture result battle_id=#{ball_ctx['battle_id']} battler=#{battler.index} shakes=#{shakes} critical=#{@criticalCapture}")
          return shakes
        end
        AnilLanRework.log("coop mirrored capture result timeout battle_id=#{ball_ctx['battle_id']} battler=#{battler.index}")
        shakes = anil_rework_original_pbCaptureCalc(pkmn, battler, catch_rate, ball)
      else
        shakes = anil_rework_original_pbCaptureCalc(pkmn, battler, catch_rate, ball)
        if ball_ctx && ball_ctx["mode"].to_s == "local_authoritative"
          critical = @criticalCapture == true
          AnilLanRework::BattleSync.send_coop_capture_result(
            "battler"    => battler.index.to_i,
            "ball"       => ball.to_s,
            "num_shakes" => shakes.to_i,
            "critical"   => critical
          )
          AnilLanRework.log("coop authoritative capture result battle_id=#{ball_ctx['battle_id']} battler=#{battler.index} ball=#{ball} shakes=#{shakes} critical=#{critical}")
        end

        # Envia animação de captura para outros jogadores se capturou com sucesso
        if shakes == 4 && defined?(AnilLanRework) && AnilLanRework.connected?
          AnilLanRework.connection.send_packet("player_capture", {
            "sender_id" => AnilLanRework.self_internal_id.to_s,
            "species"   => pkmn.species.to_s,
            "name"      => pkmn.name.to_s,
            "ball"      => ball.to_s
          }) rescue nil
        end
      end
      shakes
    end

    def pbThrowPokeBall(idxBattler, ball, catch_rate = nil, showPlayer = false)
      remote_ball_ctx = @anil_rework_ball_context
      return anil_rework_original_pbThrowPokeBall(idxBattler, ball, catch_rate, showPlayer) unless remote_ball_ctx && remote_ball_ctx["mode"].to_s == "remote_mirror"

      battler = nil
      if opposes?(idxBattler)
        battler = @battlers[idxBattler]
      else
        battler = @battlers[idxBattler].pbDirectOpposing(true)
      end
      battler = battler.allAllies[0] if battler.fainted?

      item_name = GameData::Item.get(ball).name
      thrower_name = remote_ball_ctx["thrower_name"].to_s
      thrower_name = "Seu parceiro" if thrower_name.empty?
      throw_text = _INTL("{1} jogou {2}!", thrower_name, item_name)

      if battler.fainted?
        pbDisplay(throw_text)
        pbDisplay(_INTL("Mas nao havia alvo..."))
        return
      end
      pbDisplayBrief(throw_text)

      if trainerBattle? && !(GameData::Item.get(ball).is_snag_ball? && battler.shadowPokemon?)
        @scene.pbThrowAndDeflect(ball, 1)
        pbDisplay(_INTL("O Treinador bloqueou a Ball! Roubar Pokemon e errado!"))
        return
      end

      pkmn = battler.pokemon
      @criticalCapture = false
      num_shakes = pbCaptureCalc(pkmn, battler, catch_rate, ball)
      PBDebug.log("[Threw Pok Ball][Remote Mirror] #{item_name}, #{num_shakes} shakes (4=capture)")
      @scene.pbThrow(ball, num_shakes, @criticalCapture, battler.index, showPlayer)

      case num_shakes
      when 0
        pbDisplay(_INTL("Oh, nao! O Pokemon escapou!"))
        Battle::PokeBallEffects.onFailCatch(ball, self, battler)
      when 1
        pbDisplay(_INTL("Parece que ia pegar..."))
        Battle::PokeBallEffects.onFailCatch(ball, self, battler)
      when 2
        pbDisplay(_INTL("Quase!"))
        Battle::PokeBallEffects.onFailCatch(ball, self, battler)
      when 3
        pbDisplay(_INTL("Quase conseguiu!"))
        Battle::PokeBallEffects.onFailCatch(ball, self, battler)
      when 4
        pbDisplayBrief(_INTL("{1} capturou {2}!", thrower_name, pkmn.name))
        @scene.pbThrowSuccess
        pbRemoveFromParty(battler.index, battler.pokemonIndex)
        if Settings::GAIN_EXP_FOR_CAPTURE
          battler.captured = true
          pbGainExp
          battler.captured = false
        end
        battler.pbReset
        @decision = (trainerBattle?) ? 1 : 4 if pbAllFainted?(battler.index)
        Battle::PokeBallEffects.onCatch(ball, self, pkmn)
        pkmn.poke_ball = ball
        pkmn.makeUnmega if pkmn.mega?
        pkmn.makeUnprimal
        pkmn.update_shadow_moves if pkmn.shadowPokemon?
        pkmn.record_first_moves
        pkmn.forced_form = nil if MultipleForms.hasFunction?(pkmn.species, "getForm")
        @peer.pbOnLeavingBattle(self, pkmn, true, true)
        @scene.pbHideCaptureBall(idxBattler)
        AnilLanRework.log("remote mirror capture battle_id=#{remote_ball_ctx['battle_id']} thrower=#{thrower_name} species=#{pkmn.species}")
      end

      if num_shakes != 4
        @first_poke_ball = ball if !@poke_ball_failed
        @poke_ball_failed = true
      end
    end

    def anil_rework_choice_is_pokeball?(idx_battler)
      choice = @choices[idx_battler] rescue nil
      return false unless choice && choice[0] == :UseItem
      item_id = choice[1]
      return false if item_id.nil?
      GameData::Item.get(item_id).is_poke_ball?
    rescue
      false
    end

    def anil_rework_coop_item_priority
      ordered = pbPriority.dup
      initiator_slot = AnilLanRework::BattleSync.coop_initiator_slot_for(self)
      other_slot = AnilLanRework::BattleSync.coop_non_initiator_slot_for(self)
      return ordered if initiator_slot.nil? || other_slot.nil?
      return ordered unless anil_rework_choice_is_pokeball?(initiator_slot)
      return ordered unless anil_rework_choice_is_pokeball?(other_slot)

      initiator_battler = ordered.find { |b| b && b.index == initiator_slot }
      other_battler = ordered.find { |b| b && b.index == other_slot }
      return ordered unless initiator_battler && other_battler

      reordered = [initiator_battler]
      ordered.each do |battler|
        next if !battler
        next if battler.index == initiator_slot || battler.index == other_slot
        reordered << battler
      end
      reordered << other_battler
      AnilLanRework.log("coop item priority override battle_id=#{AnilLanRework::BattleSync.active_context&.battle_id} initiator_slot=#{initiator_slot} second_slot=#{other_slot}")
      reordered
    rescue => e
      AnilLanRework.log("coop item priority override error #{e.class}: #{e}")
      pbPriority.dup
    end

    def pbAttackPhaseItems
      ctx = AnilLanRework::BattleSync.active_context
      return anil_rework_original_pbAttackPhaseItems unless ctx && ctx.mode == :coop

      anil_rework_coop_item_priority.each do |b|
        next unless @choices[b.index][0] == :UseItem && !b.fainted?
        b.lastMoveFailed = false
        item = @choices[b.index][1]
        next if !item
        case GameData::Item.get(item).battle_use
        when 1, 2
          pbUseItemOnPokemon(item, @choices[b.index][2], b) if @choices[b.index][2] >= 0
        when 3
          pbUseItemOnBattler(item, @choices[b.index][2], b)
        when 4
          pbUsePokeBallInBattle(item, @choices[b.index][2], b)
        when 5
          pbUseItemInBattle(item, @choices[b.index][2], b)
        else
          next
        end
        return if @decision > 0
      end
      pbCalculatePriority if Settings::RECALCULATE_TURN_ORDER_AFTER_SPEED_CHANGES
    end

    def pbAutoChooseMove(idxBattler, *args)
      ctx = AnilLanRework::BattleSync.active_context
      return anil_rework_original_pbAutoChooseMove(idxBattler, *args) unless ctx && ctx.mode == :coop
      anil_rework_original_pbAutoChooseMove(idxBattler, *args)
    end

    def pbSwitchInBetween(idxBattler, checkLaxOnly = false, canCancel = false)
      ctx = AnilLanRework::BattleSync.active_context
      return anil_rework_original_pbSwitchInBetween(idxBattler, checkLaxOnly, canCancel) unless ctx

      if ctx.mode == :coop
        local_slot, remote_slot = AnilLanRework::BattleSync.coop_slots_for(self)
        if idxBattler == local_slot
          AnilLanRework.log("coop local switch prompt battle_id=#{ctx.battle_id} battler=#{idxBattler} local_slot=#{local_slot.inspect} remote_slot=#{remote_slot.inspect}")
          # Mantem o parceiro esperando enquanto o menu de troca estiver aberto.
          choice = AnilLanRework::BattleSync.with_manual_lock("switch_prompt") do
            anil_rework_original_pbSwitchInBetween(idxBattler, checkLaxOnly, canCancel)
          end
          AnilLanRework::BattleSync.send_switch_choice(self, idxBattler, choice) if choice && choice >= 0
          return choice
        elsif idxBattler == remote_slot
          AnilLanRework.log("coop remote switch wait battle_id=#{ctx.battle_id} battler=#{idxBattler} local_slot=#{local_slot.inspect} remote_slot=#{remote_slot.inspect}")
          packet = AnilLanRework::BattleSync.wait_for_remote_switch(remote_slot)
          if packet
            return if !packet["switch_index"] && !packet["switch_relative"]
            if packet.key?("switch_relative")
              translated = AnilLanRework::BattleSync.coop_absolute_party_index_for(self, idxBattler, packet["switch_relative"])
              AnilLanRework.log("coop remote switch recv battle_id=#{ctx.battle_id} battler=#{idxBattler} raw=#{packet['switch_index'].inspect} relative=#{packet['switch_relative'].inspect} translated=#{translated.inspect}")
              return translated
            end
            AnilLanRework.log("coop remote switch recv battle_id=#{ctx.battle_id} battler=#{idxBattler} raw=#{packet['switch_index'].inspect} relative=nil translated=#{packet['switch_index'].to_i}")
            return packet["switch_index"].to_i if packet["switch_index"]
          end
          AnilLanRework.log("coop remote switch timeout fallback battle_id=#{ctx.battle_id}")
        end
        return anil_rework_original_pbSwitchInBetween(idxBattler, checkLaxOnly, canCancel)
      end

      return anil_rework_original_pbSwitchInBetween(idxBattler, checkLaxOnly, canCancel) unless ctx.mode == :pvp

      if pbOwnedByPlayer?(idxBattler)
        choice = anil_rework_original_pbSwitchInBetween(idxBattler, checkLaxOnly, canCancel)
        if choice && choice >= 0
          unless AnilLanRework::BattleSync.pvp_party_index_allowed?(self, idxBattler, choice)
            AnilLanRework.log("pvp local switch rejected battle_id=#{ctx.battle_id} battler=#{idxBattler} party_index=#{choice}")
            return (canCancel ? -1 : nil)
          end
          AnilLanRework::BattleSync.send_switch_choice(self, idxBattler, choice)
        elsif !canCancel
          AnilLanRework.log("switch canceled unexpectedly battle_id=#{ctx.battle_id}")
        end
        return choice
      end

      remote_order = begin
        pbGetOpposingIndicesInOrder(0).reverse
      rescue
        [idxBattler]
      end
      slot = remote_order.index(idxBattler) || 0
      packet = AnilLanRework::BattleSync.wait_for_remote_switch(slot)
      if packet && packet["switch_index"]
        choice = packet["switch_index"].to_i
        if AnilLanRework::BattleSync.pvp_party_index_allowed?(self, idxBattler, choice)
          return choice
        end
        AnilLanRework.log("pvp remote switch rejected battle_id=#{ctx.battle_id} battler=#{idxBattler} party_index=#{choice}")
        return nil
      end

      AnilLanRework.log("remote switch timeout fallback battle_id=#{ctx.battle_id} slot=#{slot}")
      anil_rework_original_pbSwitchInBetween(idxBattler, checkLaxOnly, canCancel)
    end

    def pbGetReplacementPokemonIndex(idxBattler, random = false)
      ctx = AnilLanRework::BattleSync.active_context
      return anil_rework_original_pbGetReplacementPokemonIndex(idxBattler, random) if !ctx || random

      is_local = false
      if ctx.mode == :pvp
        is_local = pbOwnedByPlayer?(idxBattler)
      elsif ctx.mode == :coop
        local_slot, remote_slot = AnilLanRework::BattleSync.coop_slots_for(self)
        if idxBattler == local_slot
          is_local = true
        elsif idxBattler == remote_slot
          is_local = false
        else
          is_local = AnilLanRework::BattleSync.authoritative_text_sender?(ctx)
        end
      end

      if is_local
        # Troca forcada por faint tambem precisa travar o parceiro para nao estourar timeout.
        choice = if ctx.mode == :coop
          AnilLanRework::BattleSync.with_manual_lock("switch_prompt") do
            anil_rework_original_pbGetReplacementPokemonIndex(idxBattler, random)
          end
        else
          anil_rework_original_pbGetReplacementPokemonIndex(idxBattler, random)
        end
        AnilLanRework::BattleSync.send_forced_switch_packet(idxBattler, choice) if choice && choice >= 0
        return choice
      else
        packet = AnilLanRework::BattleSync.wait_for_remote_forced_switch(idxBattler)
        if packet
          bruto = packet["idxParty"].to_i

          # COOP: o indice do parceiro NAO serve como veio.
          #
          # Em coop as duas equipas vivem num UNICO array (pbPartyStarts): a
          # minha comeca em 0, a do parceiro comeca no comprimento da minha. Mas
          # QUEM ENVIA e sempre o dono do slot local, e para ele o inicio e 0 —
          # portanto o numero que chega e relativo a equipa DELE, sempre 0..5.
          # Aplicado aqui em cru, o 0 do parceiro aponta para o MEU primeiro
          # Pokemon. Era isto que fazia o Passar Bastao trazer o meu em vez do
          # dele.
          #
          # Em PVP nao acontece porque cada lado tem o seu proprio array e os
          # indices ja coincidem — dai o mesmo golpe funcionar la.
          #
          # O pbSwitchInBetween ja fazia esta traducao (via "switch_relative");
          # so este caminho — o das trocas FORCADAS — e que tinha ficado de fora.
          # Passam por aqui, alem do Passar Bastao: U-turn, Volt Switch, Flip
          # Turn, Parting Shot, Teleport, Rugido/Remolino, Emergency Exit, Wimp
          # Out, Eject Button, Eject Pack e Red Card.
          #
          # Traduz-se no LEITOR, e nao no emissor, de proposito: assim tambem
          # fica certo quando o parceiro ainda esta num cliente sem esta
          # correcao, que continua a mandar o indice cru.
          if ctx.mode == :coop
            traduzido = AnilLanRework::BattleSync.coop_absolute_party_index_for(self, idxBattler, bruto)
            AnilLanRework.log("coop forced switch recv battle_id=#{ctx.battle_id} battler=#{idxBattler} raw=#{bruto} translated=#{traduzido}")
            return traduzido
          end
          return bruto
        end
        return anil_rework_original_pbGetReplacementPokemonIndex(idxBattler, random)
      end
    end

    def pbEORSwitch(favorDraws = false)
      ctx = AnilLanRework::BattleSync.active_context
      return anil_rework_original_pbEORSwitch(favorDraws) unless ctx

      if ctx.mode == :coop
        return if @decision > 0 && !favorDraws
        return if @decision == 5 && favorDraws
        pbJudge
        anil_rework_handle_local_coop_elimination
        return if @decision > 0

        loop do
          switched = []
          local_slot, remote_slot = AnilLanRework::BattleSync.coop_slots_for(self)
          order = []
          order << local_slot if !local_slot.nil?
          order << remote_slot if !remote_slot.nil? && remote_slot != local_slot
          @battlers.compact.map(&:index).sort.each do |idx|
            order << idx unless order.include?(idx)
          end
          AnilLanRework.log("coop eor switch battle_id=#{ctx.battle_id} order=#{order.inspect} local=#{local_slot.inspect} remote=#{remote_slot.inspect}")

          order.each do |idx_battler|
            battler = @battlers[idx_battler]
            next if !battler || !battler.fainted?
            next if !pbCanChooseNonActive?(idx_battler)
            idx_party_new = pbSwitchInBetween(idx_battler)
            next if idx_party_new.nil? || idx_party_new < 0
            AnilLanRework.log("coop eor switch apply battle_id=#{ctx.battle_id} battler=#{idx_battler} party_index=#{idx_party_new}")
            pbRecallAndReplace(idx_battler, idx_party_new)
            switched << idx_battler
          end

          break if switched.empty?
          pbOnBattlerEnteringBattle(switched)
        end
        return
      end

      return anil_rework_original_pbEORSwitch(favorDraws) unless ctx.mode == :pvp

      return if @decision > 0 && !favorDraws
      return if @decision == 5 && favorDraws
      pbJudge
      return if @decision > 0

      switched = []
      loop do
        switched.clear
        battlers = []
        order = AnilLanRework::CableOrder.pokemon_order(ctx.client_index)
        order.each_with_index do |ordered_index, i|
          battlers[i] = @battlers[ordered_index]
        end
        battlers.each do |battler|
          next if !battler || !battler.fainted?
          idx_battler = battler.index
          next if !pbCanChooseNonActive?(idx_battler)
          idx_party_new = pbSwitchInBetween(idx_battler)
          next if idx_party_new.nil? || idx_party_new < 0
          pbRecallAndReplace(idx_battler, idx_party_new)
          switched << idx_battler
        end
        break if switched.empty?
        pbOnBattlerEnteringBattle(switched)
      end
    end
  end
end


if defined?(Battle)
  class Battle
    alias anil_rework_original_pbCommandPhase pbCommandPhase unless method_defined?(:anil_rework_original_pbCommandPhase)
    alias anil_rework_original_pbCommandPhaseLoop pbCommandPhaseLoop unless method_defined?(:anil_rework_original_pbCommandPhaseLoop)
    alias anil_rework_original_pbCommandMenu pbCommandMenu unless method_defined?(:anil_rework_original_pbCommandMenu)
    alias anil_rework_original_pbFightMenu pbFightMenu unless method_defined?(:anil_rework_original_pbFightMenu)
    alias anil_rework_original_pbSetUpSides pbSetUpSides unless method_defined?(:anil_rework_original_pbSetUpSides)
    alias anil_rework_original_pbStartBattleSendOut pbStartBattleSendOut unless method_defined?(:anil_rework_original_pbStartBattleSendOut)
    alias anil_rework_original_pbBattleLoop pbBattleLoop unless method_defined?(:anil_rework_original_pbBattleLoop)

    def pbCommandPhase(*args)
      ctx = AnilLanRework::BattleSync.active_context
      if ctx && ctx.mode == :pvp && AnilLanRework.connected?
        instance_variable_set(:@anil_rework_pvp_turn_synced, false)
      end

      AnilLanRework::BattleSync.wait_for_remote_manual_lock(AnilLanRework::BattleSync.waiting_text("Aguardando parceiro...")) rescue nil

      result = anil_rework_original_pbCommandPhase(*args)

      if ctx && ctx.mode == :pvp && AnilLanRework.connected? && !instance_variable_get(:@anil_rework_pvp_turn_synced)
        return result if @decision != 0 # Battle ended
        # Automatic turns can skip the AI hook entirely, so exchange the turn
        # bundle here if nothing synced during the normal command loop.
        AnilLanRework.log("pvp: forcing turn sync (command_phase_fallback) battle_id=#{ctx.battle_id}")
        AnilLanRework::BattleSync.sync_pvp_turn_bundle(self, "command_phase_fallback")
        instance_variable_set(:@anil_rework_pvp_turn_synced, true)
      end
      result
    end

    def anil_wait_for_remote_command_phase_unlock(ctx = nil)
      ctx ||= AnilLanRework::BattleSync.active_context
      return false unless ctx && ctx.mode == :coop && AnilLanRework.connected?
      return false if AnilLanRework::BattleSync.coop_remote_sync_disabled?(ctx)
      return false if AnilLanRework::BattleSync.remote_coop_eliminated_marked?(ctx)
      return false if AnilLanRework::BattleSync.local_manual_lock?(ctx)
      waited = false
      loop do
        break unless AnilLanRework::BattleSync.remote_manual_lock?(ctx)
        waited = true
        AnilLanRework.log(
          "coop command phase blocked by manual lock battle_id=#{ctx.battle_id} reason=#{ctx.instance_variable_get(:@anil_remote_manual_reason) || 'none'}"
        )
        AnilLanRework::BattleSync.wait_for_remote_manual_lock(
          AnilLanRework::BattleSync.manual_wait_text
        ) rescue nil
        AnilLanRework::BattleSync.pump_network rescue nil
        break unless AnilLanRework.connected?
      end
      if @decision == 0
        synced = AnilLanRework::BattleSync.sync_coop_command_phase_ready(self)
        waited ||= synced
      end
      waited
    rescue
      false
    end

    def pbCommandPhaseLoop(isPlayer, *args)
      ctx = AnilLanRework::BattleSync.active_context
      if ctx && ctx.mode == :pvp && isPlayer
        instance_variable_set(:@anil_rework_pvp_turn_synced, false)
      end

      if ctx && ctx.mode == :coop && !isPlayer
        foe_indices = @battlers.compact.map(&:index).select do |idx|
          (opposes?(idx) rescue false) && @choices[idx][0] == :None && pbCanShowCommands?(idx)
        end
        return if foe_indices.empty?

        if ctx.client_index.to_i == 0
          result = anil_rework_original_pbCommandPhaseLoop(isPlayer, *args)
          actions = foe_indices.map do |idx|
            { "battler" => idx, "action" => AnilLanRework::BattleSync.serialize_coop_choice(self, idx) }
          end
          action_summary = actions.map { |entry| "#{entry['battler']}:#{entry['action']['kind']}" }.join(",")
          AnilLanRework.log("coop foe turn authoritative battle_id=#{ctx.battle_id} actions=#{action_summary}")
          AnilLanRework::BattleSync.send_coop_foe_turn(actions, ctx.rng.state)
          return result
        end

        packet = AnilLanRework::BattleSync.wait_for_remote_foe_turn
        if packet
          if packet["rng_state"].is_a?(Hash)
            ctx.rng.restore(packet["rng_state"])
          elsif packet["rng_state"].is_a?(Integer)
            ctx.rng.restore_state(packet["rng_state"])
          elsif packet["rng"].is_a?(Hash)
            ctx.rng.restore(packet["rng"])
          end
          Array(packet["actions"]).each do |entry|
            next unless entry.is_a?(Hash)
            idx = entry["battler"].to_i
            next unless foe_indices.include?(idx)
            action = entry["action"]
            AnilLanRework.log("coop foe turn mirrored battle_id=#{ctx.battle_id} battler=#{idx} kind=#{action.is_a?(Hash) ? action['kind'] : action.inspect}")
            AnilLanRework::BattleSync.apply_remote_action(self, idx, action)
          end
          return
        end

        AnilLanRework.log("coop foe turn timeout battle_id=#{ctx.battle_id}")
        return anil_rework_original_pbCommandPhaseLoop(isPlayer, *args)
      end

      if ctx && ctx.mode == :coop && isPlayer
        # Solo fail-safe: se a sincronização remota estiver desabilitada, executa localmente.
        if AnilLanRework::BattleSync.coop_remote_sync_disabled?(ctx)
          return anil_rework_original_pbCommandPhaseLoop(isPlayer, *args)
        end

        local_slot, remote_slot = AnilLanRework::BattleSync.coop_slots_for(self)
        actioned = []
        idxBattler = -1
        loop do
          break if @decision != 0
          idxBattler += 1
          break if idxBattler >= @battlers.length
          next if !@battlers[idxBattler]
          next if idxBattler != local_slot && idxBattler != remote_slot

          # ---------------------------------------------------------------------
          # PAREAMENTO ENVIA/ESPERA (deadlock do Meteor Beam)
          #
          # Este `next if @choices[...] != :None` pulava o slot inteiro quando a
          # escolha ja estava registrada. O problema: golpe de duas fases
          # (Meteor Beam, Solar Beam, Fly, Outrage, Rollout, Uproar, recarga de
          # Hyper Beam...) tem a escolha PRE-REGISTRADA na fase 2, e nao
          # necessariamente nos dois clientes ao mesmo tempo.
          #
          # Quando isso acontece so de um lado, o pareamento quebra: um cliente
          # pula o slot (nao envia nada) e o outro fica esperando um pacote que
          # nunca vem -> as duas telas exibem "Aguardando <parceiro>..." ao mesmo
          # tempo e a batalha congela ate o timeout.
          #
          # A regra passa a ser ESTRUTURAL, e nao dependente do estado local:
          #   - slot local  -> SEMPRE envia uma acao (mesmo ja registrada)
          #   - slot remoto -> SEMPRE consome uma acao do parceiro
          # Assim o pareamento e 1:1 por construcao, e uma divergencia de estado
          # local deixa de virar deadlock.
          # ---------------------------------------------------------------------
          # -------------------------------------------------------------------
          # 2026-08-01 — DUAS CORRECOES AQUI (freeze de 30s + desync do Meteor
          # Beam). Ver tambem a tentativa falhada mais abaixo nesta nota.
          #
          # (1) O `if coop_determinismo_v3?` que embrulhava tudo isto CAIU.
          #     A flag esta desligada ($anil_coop_v3 = false em
          #     124_Coop_Determinismo_V3), logo o bloco inteiro era codigo morto:
          #     no turno de saida do golpe travado nenhum dos lados enviava nem
          #     consumia nada, e cada cliente ficava a jogar a copia LOCAL da
          #     escolha do parceiro — a que ele proprio registou no turno da
          #     carga. Qualquer divergencia nessa copia (alvo, indice do golpe)
          #     so aparecia no turno da libertacao, ja sem hipotese de correcao.
          #     Era o desync observado: "escolhi o meu ataque e bugou o outro
          #     jogador que tinha usado Meteor Beam".
          #     O pareamento estrutural nao tem nada a ver com determinismo v3;
          #     e o que garante 1 envio / 1 consumo por turno, e vale sempre.
          #
          # (2) A barreira de turno passou a ser chamada TAMBEM aqui, antes do
          #     `next`. Sem isto o slot local travado saltava por cima dela e
          #     nunca mandava `command_ready` — o parceiro, esse com menu para
          #     abrir, ficava os 30s de TURN_TIMEOUT a mostrar "Aguardando..." a
          #     pedir um ataque que a engine nao me deixa escolher.
          #
          #     NAO mover esta chamada para fora do laco. Foi a primeira
          #     tentativa: matava o freeze mas trocava a ordem entre a barreira e
          #     o processamento do slot remoto, e a batalha dessincronizava. A
          #     barreira tem de continuar a correr na MESMA posicao da iteracao
          #     em que sempre correu (no slot local), so que agora tambem no
          #     caminho travado.
          #
          # Pareamento resultante, com so um dos lados travado (o caso real):
          #   cliente do travado -> slot local travado: ENVIA a escolha pre-
          #                         registada; slot remoto livre: espera normal.
          #   cliente do outro   -> slot local livre: menu e ENVIA;
          #                         slot remoto travado: CONSOME (espera curta).
          # 1:1 nos dois lados, e a copia do parceiro e reescrita a partir da
          # autoridade dele em vez de ficar a apodrecer localmente.
          # -------------------------------------------------------------------
          if @choices[idxBattler][0] != :None
            anil_wait_for_remote_command_phase_unlock(ctx) if idxBattler == local_slot
            if idxBattler == local_slot
              action = AnilLanRework::BattleSync.serialize_coop_choice(self, idxBattler)
              AnilLanRework.log("coop loop escolha ja registrada slot=#{idxBattler} (local) — enviando mesmo assim kind=#{action['kind']}")
              AnilLanRework::BattleSync.send_battle_action([action], idxBattler)
            elsif !AnilLanRework::BattleSync.remote_coop_eliminated?(ctx)
              AnilLanRework.log("coop loop escolha ja registrada slot=#{idxBattler} (remoto) — consumindo acao do parceiro")
              remote_actions = AnilLanRework::BattleSync.wait_for_remote_actions(
                AnilLanRework::BattleSync.waiting_text("Aguardando parceiro..."),
                AnilLanRework::COOP_LOCKED_SLOT_TIMEOUT,
                self.turnCount.to_i, idxBattler
              )
              if remote_actions && remote_actions[0]
                AnilLanRework::BattleSync.apply_remote_action(self, idxBattler, remote_actions[0])
              end
            end
            next
          end

          # Se o jogador local é espectador, para o seu próprio slot (desmaiado), não precisa esperar nada.
          if idxBattler == local_slot && AnilLanRework::BattleSync.local_coop_eliminated?(ctx)
            AnilLanRework.log("coop loop spectator auto-choose local slot=#{local_slot} battle_id=#{ctx.battle_id}")
            pbAutoChooseMove(local_slot) rescue nil
            next
          end

          anil_wait_for_remote_command_phase_unlock(ctx) if idxBattler == local_slot

          if !pbCanShowCommands?(idxBattler)
            if idxBattler == remote_slot
              if AnilLanRework::BattleSync.remote_coop_eliminated?(ctx)
                pbAutoChooseMove(remote_slot) rescue nil
                next
              end
              AnilLanRework.log("coop loop wait remote auto slot=#{remote_slot} battle_id=#{ctx.battle_id} (slot travado: espera curta)")
              remote_actions = AnilLanRework::BattleSync.wait_for_remote_actions(
                AnilLanRework::BattleSync.waiting_text("Aguardando parceiro..."),
                AnilLanRework::COOP_LOCKED_SLOT_TIMEOUT,
                self.turnCount.to_i, remote_slot
              )
              if remote_actions && remote_actions[0]
                action = remote_actions[0]
                AnilLanRework.log("coop loop recv remote auto action slot=#{remote_slot} kind=#{action['kind']} battle_id=#{ctx.battle_id}")
                AnilLanRework::BattleSync.apply_remote_action(self, remote_slot, action)
              else
                AnilLanRework.log("coop loop remote auto timeout slot=#{remote_slot} fallback battle_id=#{ctx.battle_id}")
                pbAutoChooseMove(remote_slot) rescue nil
              end
            else
              pbAutoChooseMove(idxBattler) rescue nil
              action = AnilLanRework::BattleSync.serialize_coop_choice(self, idxBattler)
              AnilLanRework.log("coop loop send local auto action slot=#{idxBattler} kind=#{action['kind']} battle_id=#{ctx.battle_id}")
              AnilLanRework::BattleSync.send_battle_action([action], idxBattler)
            end
            next
          end

          if idxBattler == remote_slot
            if AnilLanRework::BattleSync.remote_coop_eliminated?(ctx)
              AnilLanRework.log("coop loop remote eliminated - choosing auto action slot=#{remote_slot} battle_id=#{ctx.battle_id}")
              pbAutoChooseMove(remote_slot) rescue nil
              action = AnilLanRework::BattleSync.serialize_coop_choice(self, remote_slot)
              unless AnilLanRework::BattleSync.coop_remote_sync_disabled?(ctx)
                AnilLanRework::BattleSync.send_battle_action([action], remote_slot)
              end
              next
            end

            AnilLanRework.log("coop loop wait remote slot=#{remote_slot} battle_id=#{ctx.battle_id}")
            remote_actions = AnilLanRework::BattleSync.wait_for_remote_actions(
              AnilLanRework::BattleSync.waiting_text("Aguardando parceiro..."), nil,
              self.turnCount.to_i, remote_slot
            )
            if remote_actions && remote_actions[0]
              action = remote_actions[0]
              AnilLanRework.log("coop loop recv remote action slot=#{remote_slot} kind=#{action['kind']} battle_id=#{ctx.battle_id}")
              AnilLanRework::BattleSync.apply_remote_action(self, remote_slot, action)
            else
              AnilLanRework.log("coop loop remote timeout slot=#{remote_slot} fallback battle_id=#{ctx.battle_id}")
              pbAutoChooseMove(remote_slot) rescue nil
            end
            next
          end

          actioned.push(idxBattler)
          commandsEnd = false
          loop do
            cmd = pbCommandMenu(idxBattler, actioned.length == 1)
            if cmd > 0 && @battlers[idxBattler].effects[PBEffects::SkyDrop] >= 0
              pbDisplay(_INTL("¡Caída Libre no deja cambiar a #{@battlers[idxBattler].pbThis(true)}!"))
              next
            end
            case cmd
            when 0
              break if pbFightMenu(idxBattler)
            when 1
              if pbItemMenu(idxBattler, actioned.length == 1)
                used_item = @choices[idxBattler] && @choices[idxBattler][1]
                if used_item && (pbItemUsesAllActions?(used_item) rescue false)
                  commandsEnd = true
                end
                break
              end
            when 2
              break if pbPartyMenu(idxBattler)
            when 3
              if pbRunMenu(idxBattler)
                commandsEnd = true
                break
              end
            when 4
              break if pbCallMenu(idxBattler)
            when -2
              pbDebugMenu
              next
            when -1
              next if actioned.length <= 1
              actioned.pop
              idxBattler = actioned.last - 1
              pbCancelChoice(idxBattler + 1)
              actioned.pop
              break
            end
            pbCancelChoice(idxBattler)
          end

          if @choices[idxBattler] && @choices[idxBattler][0] != :None
            action = AnilLanRework::BattleSync.serialize_coop_choice(self, idxBattler)
            AnilLanRework.log("coop loop send local action slot=#{idxBattler} kind=#{action['kind']} battle_id=#{ctx.battle_id}")
            AnilLanRework::BattleSync.send_battle_action([action], idxBattler)
          end

          break if commandsEnd
        end
        return
      end
      
      result = anil_rework_original_pbCommandPhaseLoop(isPlayer, *args)
      
      if ctx && ctx.mode == :pvp && !isPlayer && !instance_variable_get(:@anil_rework_pvp_turn_synced)
        if @decision == 0
          AnilLanRework.log("pvp: forcing turn sync (command_phase_fallback) battle_id=#{ctx.battle_id}")
          AnilLanRework::BattleSync.sync_pvp_turn_bundle(self, "command_phase_fallback")
          instance_variable_set(:@anil_rework_pvp_turn_synced, true)
        end
      end
      
      result
    end

    def pbCommandMenu(idxBattler, firstAction)
      anil_rework_original_pbCommandMenu(idxBattler, firstAction)
    end

    def pbFightMenu(idxBattler)
      anil_rework_original_pbFightMenu(idxBattler)
    end

    def pbSetUpSides(*args)
      ctx = AnilLanRework::BattleSync.active_context
      AnilLanRework.log("battle setup sides start battle_id=#{ctx&.battle_id} mode=#{ctx&.mode} size=#{@sideSizes.inspect} players=#{Array(@player).length} opponents=#{Array(@opponent).length}")
      result = anil_rework_original_pbSetUpSides(*args)
      battlers = @battlers.compact.map { |b| "#{b.index}:#{b.name}" }.join(", ")
      AnilLanRework.log("battle setup sides done battle_id=#{ctx&.battle_id} sendOuts=#{result.inspect} battlers=[#{battlers}]")
      result
    end

    def pbStartBattleSendOut(sendOuts, *args)
      ctx = AnilLanRework::BattleSync.active_context
      AnilLanRework.log("battle sendout start battle_id=#{ctx&.battle_id} sendOuts=#{sendOuts.inspect}")
      result = anil_rework_original_pbStartBattleSendOut(sendOuts, *args)
      AnilLanRework.log("battle sendout done battle_id=#{ctx&.battle_id}")
      result
    end

    def pbBattleLoop(*args)
      ctx = AnilLanRework::BattleSync.active_context
      AnilLanRework.log("battle loop enter battle_id=#{ctx&.battle_id}")
      anil_rework_original_pbBattleLoop(*args)
    end
  end
end


if defined?(Battle)
  class Battle
    alias anil_phase_probe_original_pbCommandPhase pbCommandPhase unless method_defined?(:anil_phase_probe_original_pbCommandPhase)
    alias anil_phase_probe_original_pbAttackPhase pbAttackPhase unless method_defined?(:anil_phase_probe_original_pbAttackPhase)
    alias anil_phase_probe_original_pbEndOfRoundPhase pbEndOfRoundPhase unless method_defined?(:anil_phase_probe_original_pbEndOfRoundPhase)
    alias anil_phase_probe_original_pbEORSwitch pbEORSwitch unless method_defined?(:anil_phase_probe_original_pbEORSwitch)
    alias anil_phase_probe_original_pbSwitchInBetween pbSwitchInBetween unless method_defined?(:anil_phase_probe_original_pbSwitchInBetween)
    alias anil_phase_probe_original_pbGetReplacementPokemonIndex pbGetReplacementPokemonIndex unless method_defined?(:anil_phase_probe_original_pbGetReplacementPokemonIndex)
    alias anil_phase_probe_original_pbJudge pbJudge unless method_defined?(:anil_phase_probe_original_pbJudge)

    def anil_phase_probe_ctx
      AnilLanRework::BattleSync.active_context rescue nil
    end

    def anil_phase_probe_pvp?
      ctx = anil_phase_probe_ctx
      ctx && ctx.mode == :pvp
    rescue
      false
    end

    def anil_phase_probe_battlers
      @battlers.compact.map do |b|
        name = (b.pokemon&.name || b.name rescue "?").to_s
        status = (b.status || :NONE).to_s rescue "NONE"
        fainted = b.fainted? rescue false
        "#{b.index}:#{name}:#{b.hp}/#{b.totalhp}:#{status}:#{fainted ? 'KO' : 'UP'}"
      end.join(" | ")
    rescue
      "battlers=unavailable"
    end

    def anil_phase_probe_log(label, extra = nil)
      ctx = anil_phase_probe_ctx
      return unless ctx && ctx.mode == :pvp
      turn = self.turnCount.to_i rescue 0
      decision = @decision rescue nil
      suffix = extra.to_s
      suffix = " #{suffix}" unless suffix.empty?
      AnilLanRework.log(
        "#{label} battle_id=#{ctx.battle_id} client_index=#{ctx.client_index} turn=#{turn} decision=#{decision.inspect}#{suffix}"
      )
    rescue => e
      AnilLanRework.log("phase probe log error #{e.class}: #{e.message}")
    end

    def pbCommandPhase(*args)
      anil_phase_probe_log("pvp phase enter pbCommandPhase", "battlers=#{anil_phase_probe_battlers}") if anil_phase_probe_pvp?
      result = anil_phase_probe_original_pbCommandPhase(*args)
      anil_phase_probe_log("pvp phase exit pbCommandPhase", "battlers=#{anil_phase_probe_battlers}") if anil_phase_probe_pvp?
      result
    end

    def pbAttackPhase(*args)
      anil_phase_probe_log("pvp phase enter pbAttackPhase", "battlers=#{anil_phase_probe_battlers}") if anil_phase_probe_pvp?
      # Barreira gráfica: ambos esperam antes de executar os ataques
      AnilLanRework::BattleSync.pvp_attack_phase_barrier(self) if anil_phase_probe_pvp? rescue nil
      result = anil_phase_probe_original_pbAttackPhase(*args)
      anil_phase_probe_log("pvp phase exit pbAttackPhase", "battlers=#{anil_phase_probe_battlers}") if anil_phase_probe_pvp?
      result
    end

    def pbEndOfRoundPhase(*args)
      anil_phase_probe_log("pvp phase enter pbEndOfRoundPhase", "battlers=#{anil_phase_probe_battlers}") if anil_phase_probe_pvp?
      result = anil_phase_probe_original_pbEndOfRoundPhase(*args)
      anil_phase_probe_log("pvp phase exit pbEndOfRoundPhase", "battlers=#{anil_phase_probe_battlers}") if anil_phase_probe_pvp?
      # Host reconcilia HP de todos os battlers no final do turno
      ctx = AnilLanRework::BattleSync.active_context rescue nil
      if ctx && ctx.mode == :pvp && AnilLanRework.connected?
        if ctx.client_index == 0
          AnilLanRework::BattleSync.pvp_end_of_turn_hp_reconciliation(self)
        else
          AnilLanRework::BattleSync.pvp_client_end_of_turn_sync(self)
        end
      end
      result
    end

    def pbEORSwitch(favorDraws = false)
      anil_phase_probe_log(
        "pvp phase enter pbEORSwitch",
        "favorDraws=#{favorDraws ? true : false} battlers=#{anil_phase_probe_battlers}"
      ) if anil_phase_probe_pvp?
      result = anil_phase_probe_original_pbEORSwitch(favorDraws)
      anil_phase_probe_log("pvp phase exit pbEORSwitch", "battlers=#{anil_phase_probe_battlers}") if anil_phase_probe_pvp?
      result
    end

    def pbSwitchInBetween(idxBattler, checkLaxOnly = false, canCancel = false)
      anil_phase_probe_log(
        "pvp switch enter pbSwitchInBetween",
        "idxBattler=#{idxBattler} checkLaxOnly=#{checkLaxOnly ? true : false} canCancel=#{canCancel ? true : false}"
      ) if anil_phase_probe_pvp?
      result = anil_phase_probe_original_pbSwitchInBetween(idxBattler, checkLaxOnly, canCancel)
      anil_phase_probe_log(
        "pvp switch exit pbSwitchInBetween",
        "idxBattler=#{idxBattler} result=#{result.inspect}"
      ) if anil_phase_probe_pvp?
      result
    end

    def pbGetReplacementPokemonIndex(idxBattler, random = false)
      anil_phase_probe_log(
        "pvp switch enter pbGetReplacementPokemonIndex",
        "idxBattler=#{idxBattler} random=#{random ? true : false}"
      ) if anil_phase_probe_pvp?
      result = anil_phase_probe_original_pbGetReplacementPokemonIndex(idxBattler, random)
      anil_phase_probe_log(
        "pvp switch exit pbGetReplacementPokemonIndex",
        "idxBattler=#{idxBattler} random=#{random ? true : false} result=#{result.inspect}"
      ) if anil_phase_probe_pvp?
      result
    end

    def pbJudge(*args)
      # Apply any buffered hp_sync values before judging faint status
      AnilLanRework::BattleSync.apply_all_pending_hp_syncs rescue nil
      anil_phase_probe_log("pvp judge enter pbJudge", "battlers=#{anil_phase_probe_battlers}") if anil_phase_probe_pvp?
      result = anil_phase_probe_original_pbJudge(*args)
      anil_phase_probe_log("pvp judge exit pbJudge", "battlers=#{anil_phase_probe_battlers}") if anil_phase_probe_pvp?
      anil_rework_handle_local_coop_elimination
      
      # Força atualização de layout cooperativo dinamicamente
      anil_rework_force_valid_coop_layout!("pbJudge") if respond_to?(:anil_rework_force_valid_coop_layout!)

      return @decision if @decision > 0
      result
    end

    alias anil_rework_original_pbRun pbRun unless method_defined?(:anil_rework_original_pbRun)

    def pbRun(idxBattler, duringBattle = false)
      ctx = AnilLanRework::BattleSync.active_context rescue nil
      if ctx && ctx.mode == :coop && !opposes?(idxBattler)
        if trainerBattle?
          pbDisplayPaused(_INTL("Não é possível fugir de batalhas contra treinadores!"))
          return 0
        end
        if !@canRun
          pbDisplayPaused(_INTL("¡No puedes escapar!"))
          return 0
        end

        # Calcula a probabilidade de fuga
        speedPlayer = @battlers[idxBattler].speed
        speedEnemy = 1
        allOtherSideBattlers(idxBattler).each do |b|
          speed = b.speed
          speedEnemy = speed if speedEnemy < speed
        end

        can_escape = false
        if @battlers[idxBattler].pbHasType?(:GHOST) && Settings::MORE_TYPE_EFFECTS
          can_escape = true
        elsif @battlers[idxBattler].abilityActive? && Battle::AbilityEffects.triggerCertainEscapeFromBattle(@battlers[idxBattler].ability, @battlers[idxBattler])
          can_escape = true
        elsif @battlers[idxBattler].itemActive? && Battle::ItemEffects.triggerCertainEscapeFromBattle(@battlers[idxBattler].item, @battlers[idxBattler])
          can_escape = true
        else
          @runCommand += 1 if !duringBattle
          if speedPlayer > speedEnemy
            rate = 256
          else
            rate = (speedPlayer * 128) / speedEnemy
            rate += @runCommand * 30
          end
          can_escape = (rate >= 256 || @battleAI.pbAIRandom(256) < rate)
        end

        if can_escape
          pbSEPlay("Battle flee")
          pbDisplayPaused(_INTL("¡Escapas sin problemas!"))

          # Envia pacote Run
          if AnilLanRework.connected?
            AnilLanRework.connection.send_packet("battle_action", {
              "to_id" => ctx.partner_id,
              "battle_id" => ctx.battle_id,
              "actions" => [{ "kind" => "Run" }]
            })
            AnilLanRework.connection.tick rescue nil
          end

          @decision = 3
          return 1
        else
          pbDisplayPaused(_INTL("¡No puedes huir!"))
          # Envia pacote None para não travar o parceiro
          if AnilLanRework.connected?
            AnilLanRework.connection.send_packet("battle_action", {
              "to_id" => ctx.partner_id,
              "battle_id" => ctx.battle_id,
              "actions" => [{ "kind" => "None" }]
          })
          end
          return -1
        end
      end

      anil_rework_original_pbRun(idxBattler, duringBattle)
    end
  end
end

if defined?(Battle)
  class Battle
    if method_defined?(:pbAttackPhase)
      alias anil_rework_original_pbAttackPhase pbAttackPhase unless method_defined?(:anil_rework_original_pbAttackPhase)

      def pbAttackPhase(*args)
        @anil_rework_in_attack_phase = true
        begin
          ctx = AnilLanRework::BattleSync.active_context rescue nil
          if ctx && AnilLanRework.connected?
            if ctx.mode == :pvp
              unless instance_variable_get(:@anil_rework_pvp_turn_synced)
                # Fail-safe: ensure turn bundles are exchanged before ANY move is processed.
                AnilLanRework.log("pvp: fail-safe turn sync (attack_phase_start) battle_id=#{ctx.battle_id}")
                AnilLanRework::BattleSync.sync_pvp_turn_bundle(self, "attack_phase_fallback")
                instance_variable_set(:@anil_rework_pvp_turn_synced, true)
              end
            elsif ctx.mode == :coop
              # Coop mode: request turn seed from the server!
              # O servidor so libera a seed quando os DOIS jogadores pedem, e a
              # guarda por (battle_id, turn) — entao repetir o pedido e seguro e
              # devolve sempre a mesma seed. Sem o retry, uma unica resposta
              # perdida fazia o turno rodar sem sincronia de RNG, em silencio.
              turn_no = self.turnCount.to_i
              server_packet = nil
              tentativas = 3
              tentativas.times do |n|
                AnilLanRework.connection.send_packet("request_turn_seed", {
                  "battle_id" => ctx.battle_id,
                  "turn" => turn_no
                })
                server_packet = AnilLanRework::BattleSync.wait_for_turn_seed(ctx.battle_id, turn_no, 5.0)
                break if server_packet
                break unless AnilLanRework.connected?
                AnilLanRework.log("coop: turn seed TIMEOUT tentativa #{n + 1}/#{tentativas} battle_id=#{ctx.battle_id} turn=#{turn_no}")
              end
              if server_packet
                seed = server_packet.to_i
                ctx.rng.restore({ "seed" => seed, "calls" => 0 })
                self.anil_rework_rng = ctx.rng if respond_to?(:anil_rework_rng=)
                AnilLanRework.log("coop: RNG re-seeded from server seed=#{seed} turn=#{turn_no}")
              else
                AnilLanRework.log("coop: SEM SEED apos #{tentativas} tentativas battle_id=#{ctx.battle_id} turn=#{turn_no} — o turno vai rodar SEM sincronia de RNG (risco de desync)")
              end
            end
          end
          result = anil_rework_original_pbAttackPhase(*args)
          if ctx && ctx.mode == :pvp && AnilLanRework.connected?
            AnilLanRework::BattleSync.verify_pvp_turn_hash!(self)
          elsif ctx && ctx.client_index.to_i == 0
            AnilLanRework::BattleSync.send_battle_status_snapshot(self)
          end
          result
        ensure
          @anil_rework_in_attack_phase = false
        end
      end
    end

    if method_defined?(:pbEntryHazards)
      alias anil_rework_original_pbEntryHazards pbEntryHazards unless method_defined?(:anil_rework_original_pbEntryHazards)

      def pbEntryHazards(battler)
        result = anil_rework_original_pbEntryHazards(battler)
        ctx = AnilLanRework::BattleSync.active_context rescue nil
        if ctx && ctx.mode == :coop && ctx.client_index.to_i == 0 && AnilLanRework.connected?
          # Hazards alter side/battler state without always generating an HP event.
          AnilLanRework::BattleSync.send_battle_status_snapshot(self)
        end
        result
      end
    end

    if method_defined?(:pbEndOfRoundPhase)
      alias anil_rework_original_pbEndOfRoundPhase pbEndOfRoundPhase unless method_defined?(:anil_rework_original_pbEndOfRoundPhase)

      def pbEndOfRoundPhase(*args)
        result = anil_rework_original_pbEndOfRoundPhase(*args)
        ctx = AnilLanRework::BattleSync.active_context rescue nil
        # PVP HP reconciliation é feita no phase_probe hook (pbEndOfRoundPhase probe)
        # para evitar duplicação. Aqui só fazemos o snapshot COOP.
        if ctx && ctx.mode == :coop && ctx.client_index.to_i == 0 && AnilLanRework.connected?
          # Keep counters such as Toxic/Trapping/ProtectRate and side/field effects aligned.
          AnilLanRework::BattleSync.send_battle_status_snapshot(self)
        end
        result
      end
    end
  end
end



if defined?(Battle) && defined?(Battle::Move::UseRandomMove)
  class Battle::Move::UseRandomMove
    alias anil_rework_original_use_random_move_pbMoveFailed? pbMoveFailed? unless method_defined?(:anil_rework_original_use_random_move_pbMoveFailed?)
    alias anil_rework_original_use_random_move_pbEffectGeneral pbEffectGeneral unless method_defined?(:anil_rework_original_use_random_move_pbEffectGeneral)

    def pbMoveFailed?(user, targets)
      battle = @battle rescue nil
      ctx = AnilLanRework::BattleSync.active_context rescue nil
      @anil_rework_synced_target = nil
      if !ctx || !battle || ![:pvp, :coop].include?(ctx.mode) || !AnilLanRework.connected?
        return anil_rework_original_use_random_move_pbMoveFailed?(user, targets)
      end

      idx_battler = user.index.to_i rescue -1
      if AnilLanRework::BattleSync.local_battler_for_called_move?(battle, idx_battler)
        failed = anil_rework_original_use_random_move_pbMoveFailed?(user, targets)
        if !failed && @metronomeMove
          synced_target = AnilLanRework::BattleSync.serialize_called_move_target(battle, idx_battler, @metronomeMove)
          # Use the same resolved target locally that will be sent to the peer.
          @anil_rework_synced_target = AnilLanRework::BattleSync.resolve_remote_target(battle, idx_battler, synced_target)
          AnilLanRework.log("metronome resolved locally battle_id=#{ctx.battle_id} battler=#{idx_battler} move=#{@metronomeMove}")
          AnilLanRework::BattleSync.send_called_move_resolution(battle, idx_battler, @metronomeMove, synced_target)
        end
        return failed
      end

      packet = AnilLanRework::BattleSync.wait_for_remote_called_move(idx_battler)
      if packet && packet["resolved_move"]
        @metronomeMove = packet["resolved_move"].to_sym rescue packet["resolved_move"]
        local_rng_before = ctx.rng.state if ctx.rng
        if packet["rng_state"].is_a?(Hash)
          ctx.rng.restore(packet["rng_state"])
        elsif packet["rng_state"].is_a?(Integer)
          ctx.rng.restore_state(packet["rng_state"])
        elsif packet["rng"].is_a?(Hash)
          ctx.rng.restore(packet["rng"])
        end
        local_rng_after = ctx.rng.state if ctx.rng
        @anil_rework_synced_target = AnilLanRework::BattleSync.resolve_remote_target(battle, idx_battler, packet["resolved_target"])
        AnilLanRework.log("metronome resolved remotely battle_id=#{ctx.battle_id} battler=#{idx_battler} remote_battler=#{packet['remote_battler']} move=#{@metronomeMove} target=#{@anil_rework_synced_target.inspect} local_rng_before=#{local_rng_before.inspect} packet_rng=#{packet['rng_state'].inspect} local_rng_after=#{local_rng_after.inspect}")
        return false
      end

      AnilLanRework.log("metronome sync timeout battle_id=#{ctx.battle_id} battler=#{idx_battler}")
      anil_rework_original_use_random_move_pbMoveFailed?(user, targets)
    end

    def pbEffectGeneral(user)
      target = @anil_rework_synced_target
      @anil_rework_synced_target = nil
      return anil_rework_original_use_random_move_pbEffectGeneral(user) if target.nil?
      battle = user.instance_variable_get(:@battle) rescue nil
      ctx = AnilLanRework::BattleSync.active_context rescue nil
      target_battler = battle.battlers[target] rescue nil
      if ctx && ctx.mode == :pvp && battle
        trace = {
          "source" => "metronome",
          "user"   => user.index.to_i,
          "target" => target.to_i,
          "move"   => @metronomeMove.to_s
        }
        battle.instance_variable_set(:@anil_rework_debug_move_trace, trace)
        user_before = "#{user.hp.to_i}/#{user.totalhp.to_i} status=#{(user.status || :NONE).to_s}"
        target_before = if target_battler
          "#{target_battler.hp.to_i}/#{target_battler.totalhp.to_i} status=#{(target_battler.status || :NONE).to_s}"
        else
          "nil"
        end
        AnilLanRework.log("pvp metronome execute start battle_id=#{ctx.battle_id} user=#{user.index}:#{(user.pokemon&.name || user.name rescue '?')} move=#{@metronomeMove} target=#{target}:#{(target_battler&.pokemon&.name || target_battler&.name rescue '?')} user_before=#{user_before} target_before=#{target_before}")
      end
      begin
        result = user.pbUseMoveSimple(@metronomeMove, target)
        if ctx && ctx.mode == :pvp && battle
          user_after = "#{user.hp.to_i}/#{user.totalhp.to_i} status=#{(user.status || :NONE).to_s}"
          target_after = if target_battler
            "#{target_battler.hp.to_i}/#{target_battler.totalhp.to_i} status=#{(target_battler.status || :NONE).to_s}"
          else
            "nil"
          end
          AnilLanRework.log("pvp metronome execute end battle_id=#{ctx.battle_id} user=#{user.index}:#{(user.pokemon&.name || user.name rescue '?')} move=#{@metronomeMove} target=#{target}:#{(target_battler&.pokemon&.name || target_battler&.name rescue '?')} user_after=#{user_after} target_after=#{target_after}")
        end
        result
      ensure
        battle.instance_variable_set(:@anil_rework_debug_move_trace, nil) if ctx && ctx.mode == :pvp && battle
      end
    end
  end
end

if defined?(Battle) && defined?(Battle::Battler)
  class Battle::Battler
    alias anil_rework_original_battler_pbReduceHP pbReduceHP unless method_defined?(:anil_rework_original_battler_pbReduceHP)
    alias anil_rework_original_battler_pbRecoverHP pbRecoverHP unless method_defined?(:anil_rework_original_battler_pbRecoverHP)

    def anil_rework_debug_battler_name
      (pokemon&.name || name rescue "?").to_s
    end

    # Rede de seguranca: o HP espelhado do parceiro pode exceder o totalhp local
    # quando os dois clientes montaram o battler de forma diferente (ex.: boss com
    # hp_level so aplicado em um lado). Sem isso, estoura "PS maior que PS total".
    def anil_clamp_mirror_hp(value)
      hp = value.to_i
      max = (self.totalhp.to_i rescue 0)
      return [hp, 0].max if max <= 0
      if hp > max
        AnilLanRework.log("coop mirrored hp clamped battler=#{self.index} hp=#{hp} totalhp=#{max}") rescue nil
      end
      [[hp, 0].max, max].min
    end

    def anil_rework_debug_pvp_hp_log(kind, amount, old_hp, new_hp)
      ctx = AnilLanRework::BattleSync.active_context rescue nil
      return unless ctx && ctx.mode == :pvp
      battle = instance_variable_get(:@battle) rescue nil
      trace = battle.instance_variable_get(:@anil_rework_debug_move_trace) if battle
      status = (self.status || :NONE).to_s rescue "NONE"
      trace_text = if trace.is_a?(Hash)
        " trace_source=#{trace['source']} trace_user=#{trace['user']} trace_target=#{trace['target']} trace_move=#{trace['move']}"
      else
        ""
      end
      AnilLanRework.log("pvp hp #{kind} battle_id=#{ctx.battle_id} battler=#{index}:#{anil_rework_debug_battler_name} old=#{old_hp} new=#{new_hp} delta=#{amount} status=#{status}#{trace_text}")
      fields = AnilLanRework.battler_log_fields(self, "target").merge(
        "kind"         => kind,
        "old_hp"       => old_hp,
        "new_hp"       => new_hp,
        "delta"        => amount,
        "trace_source" => (trace["source"] rescue nil),
        "trace_user"   => (trace["user"] rescue nil),
        "trace_target" => (trace["target"] rescue nil),
        "trace_move"   => (trace["move"] rescue nil)
      )
      AnilLanRework.battle_log("pvp_hp_#{kind}", fields, battle, ctx)
    rescue => e
      AnilLanRework.log("pvp hp #{kind} log error #{e.class}: #{e.message}")
    end

    def pbReduceHP(*args, **kwargs, &block)
      ctx = AnilLanRework::BattleSync.active_context rescue nil
      if ctx && ctx.mode == :pvp
        amount = args[0].to_i
        old_hp = self.hp.to_i
        current_turn = begin
          ctx.battle ? ctx.battle.turnCount.to_i : 0
        rescue
          0
        end
        result = anil_rework_original_battler_pbReduceHP(*args, **kwargs, &block)
        new_hp = self.hp.to_i
        anil_rework_debug_pvp_hp_log("damage", amount, old_hp, new_hp) if amount > 0 && new_hp != old_hp
        # Host envia HP autoritário para o cliente
        AnilLanRework::BattleSync.sync_hp_after_damage(self, old_hp, new_hp, ctx, "damage")
        # Não consumimos hp_sync inline - a reconciliação final de turno corrige tudo
        return result
      end
      return anil_rework_original_battler_pbReduceHP(*args, **kwargs, &block) unless ctx && ctx.mode == :coop

      amount = args[0].to_i
      return anil_rework_original_battler_pbReduceHP(*args, **kwargs, &block) if amount <= 0

      if ctx.client_index.to_i == 0
        old_hp = self.hp.to_i
        new_hp = [old_hp - amount, 0].max
        AnilLanRework.battle_log(
          "coop_hp_damage_send",
          AnilLanRework.battler_log_fields(self, "target").merge(
            "old_hp" => old_hp,
            "new_hp" => new_hp,
            "delta"  => amount
          ),
          ctx.battle,
          ctx
        )
        AnilLanRework::BattleSync.send_coop_hp_event(
          "battler" => self.index.to_i,
          "battler_ref" => AnilLanRework::BattleSync.serialize_coop_battler_reference(ctx.battle, self.index),
          "hp_kind" => "damage",
          "old_hp"  => old_hp,
          "new_hp"  => new_hp,
          "delta"   => amount,
          "rng_state" => ctx.rng.state
        )
        return anil_rework_original_battler_pbReduceHP(*args, **kwargs, &block)
      end

      packet = AnilLanRework::BattleSync.wait_for_remote_hp_event(self.index, "damage")
      if packet == :authoritative_none
        AnilLanRework.log("coop mirrored damage skipped battle_id=#{ctx.battle_id} battler=#{self.index} local=#{amount}")
        return 0
      end

      if packet
        if packet["rng_state"].is_a?(Hash)
          ctx.rng.restore(packet["rng_state"])
        elsif packet["rng_state"].is_a?(Integer)
          ctx.rng.restore_state(packet["rng_state"])
        elsif packet["rng"].is_a?(Hash)
          ctx.rng.restore(packet["rng"])
        end
        old_hp = packet["old_hp"].to_i
        delta = packet["delta"].to_i
        new_hp = packet["new_hp"].to_i
        old_hp = anil_clamp_mirror_hp(old_hp)
        self.hp = old_hp rescue self.instance_variable_set(:@hp, old_hp)
        args[0] = delta
        result = anil_rework_original_battler_pbReduceHP(*args, **kwargs, &block)
        new_hp = anil_clamp_mirror_hp(new_hp)
        self.hp = new_hp rescue self.instance_variable_set(:@hp, new_hp)
        AnilLanRework.log("coop mirrored damage battle_id=#{ctx.battle_id} battler=#{self.index} old=#{old_hp} new=#{new_hp} delta=#{delta}")
        AnilLanRework.battle_log(
          "coop_hp_damage_mirror",
          AnilLanRework.battler_log_fields(self, "target").merge(
            "old_hp" => old_hp,
            "new_hp" => new_hp,
            "delta"  => delta
          ),
          ctx.battle,
          ctx
        )
        return result
      end

      AnilLanRework.log("coop hp damage timeout battle_id=#{ctx.battle_id} battler=#{self.index} local=#{amount}")
      AnilLanRework.battle_log(
        "coop_hp_damage_timeout",
        AnilLanRework.battler_log_fields(self, "target").merge("local_amount" => amount),
        ctx.battle,
        ctx
      )
      anil_rework_original_battler_pbReduceHP(*args, **kwargs, &block)
    end

    def pbRecoverHP(*args, **kwargs, &block)
      ctx = AnilLanRework::BattleSync.active_context rescue nil
      if ctx && ctx.mode == :pvp
        amount = args[0].to_i
        old_hp = self.hp.to_i
        current_turn = begin
          ctx.battle ? ctx.battle.turnCount.to_i : 0
        rescue
          0
        end
        result = anil_rework_original_battler_pbRecoverHP(*args, **kwargs, &block)
        new_hp = self.hp.to_i
        anil_rework_debug_pvp_hp_log("recovery", amount, old_hp, new_hp) if amount > 0 && new_hp != old_hp
        # Host envia HP autoritário para o cliente
        AnilLanRework::BattleSync.sync_hp_after_damage(self, old_hp, new_hp, ctx, "heal")
        # Não consumimos hp_sync inline - a reconciliação final de turno corrige tudo
        return result
      end
      return anil_rework_original_battler_pbRecoverHP(*args, **kwargs, &block) unless ctx && ctx.mode == :coop

      amount = args[0].to_i
      return anil_rework_original_battler_pbRecoverHP(*args, **kwargs, &block) if amount <= 0

      if ctx.client_index.to_i == 0
        old_hp = self.hp.to_i
        max_hp = self.totalhp.to_i rescue old_hp + amount
        new_hp = [old_hp + amount, max_hp].min
        AnilLanRework.battle_log(
          "coop_hp_heal_send",
          AnilLanRework.battler_log_fields(self, "target").merge(
            "old_hp" => old_hp,
            "new_hp" => new_hp,
            "delta"  => amount
          ),
          ctx.battle,
          ctx
        )
        AnilLanRework::BattleSync.send_coop_hp_event(
          "battler" => self.index.to_i,
          "battler_ref" => AnilLanRework::BattleSync.serialize_coop_battler_reference(ctx.battle, self.index),
          "hp_kind" => "heal",
          "old_hp"  => old_hp,
          "new_hp"  => new_hp,
          "delta"   => amount,
          "rng_state" => ctx.rng.state
        )
        return anil_rework_original_battler_pbRecoverHP(*args, **kwargs, &block)
      end

      packet = AnilLanRework::BattleSync.wait_for_remote_hp_event(self.index, "heal")
      if packet == :authoritative_none
        AnilLanRework.log("coop mirrored heal skipped battle_id=#{ctx.battle_id} battler=#{self.index} local=#{amount}")
        return 0
      end

      if packet
        if packet["rng_state"].is_a?(Hash)
          ctx.rng.restore(packet["rng_state"])
        elsif packet["rng_state"].is_a?(Integer)
          ctx.rng.restore_state(packet["rng_state"])
        elsif packet["rng"].is_a?(Hash)
          ctx.rng.restore(packet["rng"])
        end
        old_hp = packet["old_hp"].to_i
        delta = packet["delta"].to_i
        new_hp = packet["new_hp"].to_i
        old_hp = anil_clamp_mirror_hp(old_hp)
        self.hp = old_hp rescue self.instance_variable_set(:@hp, old_hp)
        args[0] = delta
        result = anil_rework_original_battler_pbRecoverHP(*args, **kwargs, &block)
        new_hp = anil_clamp_mirror_hp(new_hp)
        self.hp = new_hp rescue self.instance_variable_set(:@hp, new_hp)
        AnilLanRework.log("coop mirrored heal battle_id=#{ctx.battle_id} battler=#{self.index} old=#{old_hp} new=#{new_hp} delta=#{delta}")
        AnilLanRework.battle_log(
          "coop_hp_heal_mirror",
          AnilLanRework.battler_log_fields(self, "target").merge(
            "old_hp" => old_hp,
            "new_hp" => new_hp,
            "delta"  => delta
          ),
          ctx.battle,
          ctx
        )
        return result
      end

      AnilLanRework.log("coop hp heal timeout battle_id=#{ctx.battle_id} battler=#{self.index} local=#{amount}")
      AnilLanRework.battle_log(
        "coop_hp_heal_timeout",
        AnilLanRework.battler_log_fields(self, "target").merge("local_amount" => amount),
        ctx.battle,
        ctx
      )
      anil_rework_original_battler_pbRecoverHP(*args, **kwargs, &block)
    end
  end
end

if defined?(Battle)
  class Battle
    alias anil_verbose_original_pbShowAbilitySplash pbShowAbilitySplash unless method_defined?(:anil_verbose_original_pbShowAbilitySplash)
    alias anil_verbose_original_pbHideAbilitySplash pbHideAbilitySplash unless method_defined?(:anil_verbose_original_pbHideAbilitySplash)

    def pbShowAbilitySplash(*args, **kwargs, &block)
      battler = args[0] rescue nil
      AnilLanRework.battle_log(
        "ability_splash_show",
        AnilLanRework.battler_log_fields(battler, "ability_user"),
        self
      )
      anil_verbose_original_pbShowAbilitySplash(*args, **kwargs, &block)
    end

    def pbHideAbilitySplash(*args, **kwargs, &block)
      battler = args[0] rescue nil
      AnilLanRework.battle_log(
        "ability_splash_hide",
        AnilLanRework.battler_log_fields(battler, "ability_user"),
        self
      )
      anil_verbose_original_pbHideAbilitySplash(*args, **kwargs, &block)
    end
  end
end


module AnilLanRework
  module BattleSync
    def self.reload_multiplayer_scripts
      return if @reloading_scripts
      @reloading_scripts = true
      
      log_file = "multiplayer_reload_errors.txt"
      File.open(log_file, "w") do |lf|
        lf.puts "========================================================================="
        lf.puts "RELATÓRIO DE RECARREGAMENTO DE SCRIPTS MULTIPLAYER (F5)"
        lf.puts "Executado em: #{Time.now.strftime('%d/%m/%Y %H:%M:%S.%L')}"
        lf.puts "=========================================================================\n"
      end

      success_count = 0
      error_count = 0
      errors_summary = []

      Dir.glob("Data/Scripts_Modular_Multiplayer/*.rb").sort.each do |f|
        begin
          code = File.read(f)
          binding_to_use = (defined?(TOPLEVEL_BINDING) ? TOPLEVEL_BINDING : nil)
          eval(code, binding_to_use, f)
          File.open(log_file, "a") do |lf|
            lf.puts "[✓ OK] #{File.basename(f)}"
          end
          success_count += 1
        rescue Exception => e
          error_count += 1
          err_msg = "[❌ ERRO] #{File.basename(f)}\n  #{e.class}: #{e.message}\n  Backtrace:\n"
          e.backtrace[0..15].each do |line|
            err_msg += "    #{line}\n"
          end
          err_msg += "-------------------------------------------------------------------------\n"
          
          File.open(log_file, "a") do |lf|
            lf.puts err_msg
          end
          
          errors_summary << "#{File.basename(f)} (#{e.class})"
        end
      end

      # Escreve o resumo final no arquivo de log
      File.open(log_file, "a") do |lf|
        lf.puts "\n========================================================================="
        lf.puts "RESUMO DE EXECUÇÃO:"
        lf.puts "  Total de arquivos: #{success_count + error_count}"
        lf.puts "  Com sucesso: #{success_count}"
        lf.puts "  Com erro: #{error_count}"
        if error_count > 0
          lf.puts "\nARQUIVOS COM ERRO:"
          errors_summary.each { |item| lf.puts "  - #{item}" }
        end
        lf.puts "========================================================================="
      end

      # Mostra a mensagem na tela do jogo
      if error_count > 0
        popup_msg = "Recarregamento concluído com #{error_count} erros!\nDetalhes gravados em: #{log_file}\n\nPrimeiro erro:\n#{errors_summary[0]}"
        if defined?(pbMessage)
          pbMessage(_INTL(popup_msg)) rescue nil
        else
          AnilLanRework.log(popup_msg)
        end
      else
        popup_msg = "Todos os #{success_count} scripts recarregados com sucesso!"
        if defined?(pbMessage)
          pbMessage(_INTL(popup_msg)) rescue nil
        else
          AnilLanRework.log(popup_msg)
        end
      end
      
      @reloading_scripts = false
    end
  end
end


module Input
  class << self
    unless method_defined?(:anil_rework_original_update_reload)
      alias anil_rework_original_update_reload update
    end
    
    def update
      anil_rework_original_update_reload
      if !$InCommandLine && !(Input.text_input rescue false)
        if (triggerex?(:F5) rescue false) || (trigger?(Input::F5) rescue false)
          # Só permite se estiver livre no mapa para evitar corromper o estado do jogo / batalhas
          safe_to_reload = false
          if $scene.is_a?(Scene_Map)
            if $game_temp
              safe_to_reload = !$game_temp.in_menu && !$game_temp.message_window_showing && !$game_temp.player_transferring
            else
              safe_to_reload = true
            end
          end
          
          if safe_to_reload
            # Limpa viewports e sprites travados (órfãos) de transições anteriores
            AnilLanRework.wipe_stuck_graphics! rescue nil
          else
            AnilLanRework.log("[HOTKEY] F5 ignorado: jogador em menu, batalha ou transição ativa.") rescue nil
          end
        end
      end
    end
  end
end




#===============================================================================
# COOP — TURNO AUTORITATIVO DO HOST  (experimental, 2026-07-19)
#-------------------------------------------------------------------------------
# EVOLUCAO do "fim de turno autoritativo": agora cobre o TURNO INTEIRO (fase de
# ataque + fim de round). O host e a unica fonte de verdade de HP e status;
# o guest suprime o proprio calculo e aplica o lote do host por fase.
#
# POR QUE: o golpe do inimigo/boss ja era escolhido pelo host (pbCommandPhaseLoop
# ~6867), mas a EXECUCAO do golpe (dano, efeitos) rodava nos dois lados com RNG
# que diverge no meio do turno. Efeitos deterministicos (tempestade totalhp/16)
# quebravam igual. Com o host autoritativo, nada disso importa: o guest recebe
# o resultado pronto.
#
# GATE DUPLO: so ativa quando (a) $anil_coop_eor_authoritative != false E
# (b) o proto negociado da batalha >= 2 (os dois clientes sao novos). Host novo
# + guest antigo cai no fluxo legado — nao quebra o servidor de producao.
#
# LIMITACOES conhecidas (primeiro corte, precisa de teste com 2 clientes):
#  - O HP do guest aplica no FIM DE CADA FASE (ataque, round), nao golpe-a-golpe.
#    Visualmente as barras do guest atualizam em lote no fim da fase. Correto no
#    estado final; refinavel para granularidade por golpe depois.
#  - Decisoes locais do guest dependentes de HP no meio da fase (ex.: alvo por
#    menor HP) usam HP defasado. Raro; o estado final e sempre o do host.
#===============================================================================

module AnilLanRework
  module BattleSync
    # proto 3 = RNG contador-base (SplitMix64) + ordem de turno autoritativa +
    #           snapshot completo + hash de turno. Ver BRIEFING_COOP_DESYNC.md.
    COOP_BATTLE_PROTO = 3 unless const_defined?(:COOP_BATTLE_PROTO)

    # A partir deste proto os dois lados usam o RNG contador-base. Abaixo dele o
    # RNG fica no modo :legacy, porque o ALGORITMO tem de ser identico nos dois
    # clientes — nao ha meio-caminho: legacy x counter dessincroniza 100% dos
    # turnos, nao 80%.
    COOP_RNG_PROTO = 3 unless const_defined?(:COOP_RNG_PROTO)

    class << self
      # Guarda o proto negociado (menor entre os dois lados) no contexto.
      def set_coop_battle_proto(ctx, other_proto)
        return unless ctx
        mine = COOP_BATTLE_PROTO
        theirs = other_proto.to_i
        theirs = 1 if theirs < 1
        negotiated = [mine, theirs].min
        ctx.instance_variable_set(:@coop_battle_proto, negotiated)

        # Modo do RNG. Feito AQUI porque activate_context ja criou o ctx.rng mas a
        # batalha ainda nao sorteou nada — trocar o modo agora e seguro.
        if ctx.rng && ctx.rng.respond_to?(:mode=)
          modo = (negotiated >= COOP_RNG_PROTO && $anil_coop_v3 != false) ? :counter : :legacy
          ctx.rng.mode = modo
          AnilLanRework.log("coop rng modo=#{modo} seed=#{ctx.rng.seed} battle_id=#{ctx.battle_id rescue '?'}")
        end

        AnilLanRework.log("coop proto negociado=#{negotiated} (meu=#{mine} outro=#{theirs}) battle_id=#{ctx.battle_id rescue '?'}")
        negotiated
      end

      # proto >= 3 nos dois lados: da para confiar em ordem de turno autoritativa,
      # snapshot completo e hash de turno.
      def coop_determinismo_v3?(ctx = nil)
        return false if $anil_coop_v3 == false   # interruptor geral (124_Coop_Determinismo_V3)
        ctx ||= @active_context
        return false unless ctx && ctx.mode == :coop && AnilLanRework.connected?
        coop_battle_proto(ctx) >= COOP_RNG_PROTO
      end

      def coop_battle_proto(ctx = nil)
        ctx ||= @active_context
        return 1 unless ctx
        (ctx.instance_variable_get(:@coop_battle_proto) || 1).to_i
      end

      # O turno autoritativo so vale se ligado E se os dois lados sao proto >= 2.
      def coop_turn_authoritative?(ctx = nil)
        ctx ||= @active_context
        return false unless ctx && ctx.mode == :coop && AnilLanRework.connected?
        return false if $anil_coop_eor_authoritative == false
        coop_battle_proto(ctx) >= 2
      end

      def coop_turn_host?
        ctx = @active_context
        coop_turn_authoritative?(ctx) && ctx.client_index.to_i == 0
      end

      def coop_turn_guest?
        ctx = @active_context
        coop_turn_authoritative?(ctx) && ctx.client_index.to_i != 0
      end

      # ---- coletor / supressor (compartilhado entre fase de ataque e EOR) ----
      def coop_turn_suppressing?
        @coop_turn_suppress == true
      end

      def coop_turn_collecting?
        @coop_turn_collecting == true
      end

      def coop_turn_begin_host!
        @coop_turn_batch = []
        @coop_turn_collecting = true
      end

      def coop_turn_record(battler, kind, old_hp, new_hp)
        return unless @coop_turn_collecting
        @coop_turn_batch << {
          "battler" => battler.index.to_i,
          "kind"    => kind.to_s,
          "old_hp"  => old_hp.to_i,
          "new_hp"  => new_hp.to_i
        }
      rescue
      end

      def coop_turn_end_host!(fase)
        return unless @coop_turn_collecting
        @coop_turn_collecting = false
        ctx = @active_context
        return unless ctx
        lote = @coop_turn_batch || []
        AnilLanRework.connection.send_packet("coop_turn_batch",
          "to_id"     => ctx.partner_id,
          "battle_id" => ctx.battle_id,
          "fase"      => fase.to_s,
          "turn"      => (ctx.battle ? ctx.battle.turnCount.to_i : 0),
          "events"    => lote
        )
        AnilLanRework.log("coop turn host enviou lote fase=#{fase} eventos=#{lote.length} battle_id=#{ctx.battle_id}")
      rescue => e
        AnilLanRework.log("coop turn erro ao enviar lote: #{e.class}: #{e.message}")
      ensure
        @coop_turn_batch = nil
      end

      def queue_coop_turn_batch(packet)
        return unless packet.is_a?(Hash)
        @coop_turn_inbox ||= {}
        chave = "#{packet['battle_id']}|#{packet['fase']}"
        (@coop_turn_inbox[chave] ||= []) << packet
        AnilLanRework.log("coop turn lote recebido fase=#{packet['fase']} eventos=#{Array(packet['events']).length} battle_id=#{packet['battle_id']}")
      end

      def take_coop_turn_batch(battle_id, fase)
        @coop_turn_inbox ||= {}
        chave = "#{battle_id}|#{fase}"
        fila = @coop_turn_inbox[chave]
        return nil if fila.nil? || fila.empty?
        fila.shift
      end

      def clear_coop_turn_state!
        @coop_turn_batch = nil
        @coop_turn_collecting = false
        @coop_turn_suppress = false
        @coop_turn_inbox = {}
      end

      # Guest: roda a fase com HP suprimido, depois espera UMA vez o lote e aplica.
      def coop_turn_run_guest!(battle, fase)
        ctx = @active_context
        return yield unless coop_turn_authoritative?(ctx)

        @coop_turn_suppress = true
        begin
          resultado = yield
        ensure
          @coop_turn_suppress = false
        end

        lote = nil
        started, timeout, absolute = anil_freeze_patch_wait_deadlines(AnilLanRework::TURN_TIMEOUT)
        loop do
          lote = take_coop_turn_batch(ctx.battle_id, fase)
          break if lote
          break unless AnilLanRework.connected?
          started = Time.now.to_f if remote_manual_lock?
          if anil_freeze_patch_wait_timed_out?(started, timeout, absolute)
            AnilLanRework.log("coop turn timeout esperando lote fase=#{fase} battle_id=#{ctx.battle_id}")
            break
          end
          pump_network
          Graphics.update rescue nil
          Input.update rescue nil
        end

        apply_coop_turn_batch(battle, lote) if lote
        resultado
      end

      def apply_coop_turn_batch(battle, packet)
        return unless battle && packet.is_a?(Hash)
        eventos = Array(packet["events"])
        AnilLanRework.log("coop turn aplicando #{eventos.length} evento(s) fase=#{packet['fase']} battle_id=#{packet['battle_id']}")
        eventos.each do |ev|
          battler = battle.battlers[ev["battler"].to_i] rescue nil
          next unless battler
          alvo = ev["new_hp"].to_i
          max = (battler.totalhp.to_i rescue 0)
          alvo = [[alvo, 0].max, max].min if max > 0
          begin
            battler.hp = alvo
          rescue
            battler.instance_variable_set(:@hp, alvo)
          end
        end
        eventos.each do |ev|
          battler = battle.battlers[ev["battler"].to_i] rescue nil
          next unless battler
          battler.pbFaint if battler.hp <= 0 && !battler.fainted? rescue nil
        end
        battle.scene.pbRefresh rescue nil
      rescue => e
        AnilLanRework.log("coop turn erro ao aplicar lote: #{e.class}: #{e.message}")
      end
    end
  end
end

#-------------------------------------------------------------------------------
# Wrappers de fase. Precisam ser a camada MAIS EXTERNA -> por isso no fim do
# arquivo, depois de todas as outras defs de pbAttackPhase/pbEndOfRoundPhase.
#-------------------------------------------------------------------------------
if defined?(Battle)
  class Battle
    unless method_defined?(:anil_turnauth_original_pbAttackPhase)
      alias anil_turnauth_original_pbAttackPhase pbAttackPhase
    end
    def pbAttackPhase(*args)
      bs = AnilLanRework::BattleSync
      if bs.coop_turn_host?
        bs.coop_turn_begin_host!
        begin
          anil_turnauth_original_pbAttackPhase(*args)
        ensure
          bs.coop_turn_end_host!("attack")
        end
      elsif bs.coop_turn_guest?
        bs.coop_turn_run_guest!(self, "attack") { anil_turnauth_original_pbAttackPhase(*args) }
      else
        anil_turnauth_original_pbAttackPhase(*args)
      end
    end

    unless method_defined?(:anil_turnauth_original_pbEndOfRoundPhase)
      alias anil_turnauth_original_pbEndOfRoundPhase pbEndOfRoundPhase
    end
    def pbEndOfRoundPhase(*args)
      bs = AnilLanRework::BattleSync
      if bs.coop_turn_host?
        bs.coop_turn_begin_host!
        begin
          anil_turnauth_original_pbEndOfRoundPhase(*args)
        ensure
          bs.coop_turn_end_host!("eor")
        end
      elsif bs.coop_turn_guest?
        bs.coop_turn_run_guest!(self, "eor") { anil_turnauth_original_pbEndOfRoundPhase(*args) }
      else
        anil_turnauth_original_pbEndOfRoundPhase(*args)
      end
    end
  end
end

#-------------------------------------------------------------------------------
# HP no turno autoritativo:
#   guest  -> SUPRIME (nao aplica, nao espera evento nenhum)
#   host   -> aplica pela BASE (bypass do mirror por-evento, senao enviaria
#             pacote duplo) e REGISTRA no lote.
#-------------------------------------------------------------------------------
if defined?(Battle::Battler)
  class Battle::Battler
    unless method_defined?(:anil_turnauth_original_pbReduceHP)
      alias anil_turnauth_original_pbReduceHP pbReduceHP
    end
    unless method_defined?(:anil_turnauth_original_pbRecoverHP)
      alias anil_turnauth_original_pbRecoverHP pbRecoverHP
    end

    def pbReduceHP(*args, **kwargs, &block)
      bs = AnilLanRework::BattleSync
      return 0 if bs.coop_turn_suppressing?
      if bs.coop_turn_collecting?
        antes = self.hp.to_i
        r = anil_rework_original_battler_pbReduceHP(*args, **kwargs, &block)
        bs.coop_turn_record(self, "damage", antes, self.hp.to_i)
        return r
      end
      anil_turnauth_original_pbReduceHP(*args, **kwargs, &block)
    end

    def pbRecoverHP(*args, **kwargs, &block)
      bs = AnilLanRework::BattleSync
      return 0 if bs.coop_turn_suppressing?
      if bs.coop_turn_collecting?
        antes = self.hp.to_i
        r = anil_rework_original_battler_pbRecoverHP(*args, **kwargs, &block)
        bs.coop_turn_record(self, "heal", antes, self.hp.to_i)
        return r
      end
      anil_turnauth_original_pbRecoverHP(*args, **kwargs, &block)
    end
  end
end

# ===============================================================================
# MULTIPLAYER CO-OP BOSS & MIDBATTLE SYNC PATCH
# ===============================================================================
if defined?(MidbattleHandlers)
  module MidbattleHandlers
    class << self
      alias anil_coop_boss_original_exists? exists? unless method_defined?(:anil_coop_boss_original_exists?)
      alias anil_coop_boss_original_trigger trigger unless method_defined?(:anil_coop_boss_original_trigger)

      def exists?(midbattle, id)
        res = anil_coop_boss_original_exists?(midbattle, id)
        if !res && id.is_a?(String)
          res = anil_coop_boss_original_exists?(midbattle, id.sub(/^:/, "").to_sym)
        end
        res
      end

      def trigger(midbattle, id, battle, idxBattler, idxTarget, params)
        if id.is_a?(String) && !anil_coop_boss_original_exists?(midbattle, id)
          id_sym = id.sub(/^:/, "").to_sym
          id = id_sym if anil_coop_boss_original_exists?(midbattle, id_sym)
        end
        anil_coop_boss_original_trigger(midbattle, id, battle, idxBattler, idxTarget, params)
      end
    end
  end
end

if defined?(Battle::Scene::PokemonDataBox)
  class Battle::Scene::PokemonDataBox
    alias anil_coop_boss_original_boss_battle_active? boss_battle_active? rescue nil
    def boss_battle_active?
      return true if $game_switches && ($game_switches[45] || (defined?(BossBattleConstants) && $game_switches[BossBattleConstants::BOSS_BATTLE_SWITCH]))
      rules = ($game_temp.battle_rules rescue nil)
      if rules.is_a?(Hash) && (rules["boss"] || rules["midbattleScript"] || rules["databoxStyle"])
        return true
      end
      if respond_to?(:anil_coop_boss_original_boss_battle_active?) && method(:anil_coop_boss_original_boss_battle_active?).arity != 0
        return anil_coop_boss_original_boss_battle_active?
      end
      false
    end
  end
end

if defined?(Battle)
  class Battle
    alias anil_coop_mega_original_pbHasMegaRing? pbHasMegaRing? rescue nil
    def pbHasMegaRing?(idxBattler)
      ctx = AnilLanRework::BattleSync.active_context rescue nil
      if ctx && ctx.mode == :coop && !pbOwnedByPlayer?(idxBattler) && !(opposes?(idxBattler) rescue true)
        return true
      end
      if respond_to?(:anil_coop_mega_original_pbHasMegaRing?)
        return anil_coop_mega_original_pbHasMegaRing?(idxBattler)
      end
      true
    end

    alias anil_coop_mega_original_pbCanMegaEvolve? pbCanMegaEvolve? rescue nil
    def pbCanMegaEvolve?(idxBattler)
      ctx = AnilLanRework::BattleSync.active_context rescue nil
      if ctx && ctx.mode == :coop && !pbOwnedByPlayer?(idxBattler) && !(opposes?(idxBattler) rescue true)
        battler = @battlers[idxBattler]
        return false if !battler || !battler.pokemon || battler.fainted?
        return false if $game_switches && $game_switches[Settings::NO_MEGA_EVOLUTION] rescue false
        return false if !battler.hasMega? || battler.mega?
        side  = battler.idxOwnSide
        owner = pbGetOwnerIndexFromBattlerIndex(idxBattler)
        return @megaEvolution[side][owner] == -1
      end
      if respond_to?(:anil_coop_mega_original_pbCanMegaEvolve?)
        return anil_coop_mega_original_pbCanMegaEvolve?(idxBattler)
      end
      false
    end
  end
end
