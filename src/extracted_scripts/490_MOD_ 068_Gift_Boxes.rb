#===============================================================================
# Sistema de Caixas de Presente (Gift Boxes) - v1.0
# Itens usáveis que abrem no overworld com efeito de fogos de artifício e
# arremessam itens temáticos ao redor do jogador como um chafariz.
#===============================================================================

module GiftBoxSystem
  @mega_stones_pool = []
  class << self
    attr_accessor :mega_stones_pool
  end

  # Pools de itens por cor/tier
  GREEN_POOL = [
    :POKEBALL, :GREATBALL, :POTION, :SUPERPOTION, :HYPERPOTION,
    :REPEL, :SUPERREPEL, :MAXREPEL, :HEALBALL, :NESTBALL, :NETBALL,
    :SITRUSBERRY, :ORANBERRY, :LUMBERRY, :LEPPABERRY,
    :FIRESTONE, :THUNDERSTONE, :WATERSTONE, :LEAFSTONE, :MOONSTONE,
    :SUNSTONE, :DUSKSTONE, :DAWNSTONE, :SHINYSTONE, :ICESTONE,
    :QUICKCLAW, :KINGSROCK, :AMULETCOIN, :METRONOME,
    :TM10, :TM17, :TM20, :TM32, :TM45, :TM54, :TM70, :TM87,
    :SACOMOEDAPEQUENO
  ]

  BLUE_POOL = [
    :ULTRABALL, :DUSKBALL, :QUICKBALL, :TIMERBALL, :DIVEBALL,
    :FULLRESTORE, :MAXPOTION, :REVIVE, :ETHER, :MAXETHER, :ELIXIR,
    :MAXELIXIR, :SACREDASH, :HEARTSCALE, :REDSHARD, :YELLOWSHARD,
    :BLUESHARD, :GREENSHARD, :TINYMUSHROOM, :BIGPEARL, :STARPIECE,
    :NUGGET, :SOOTHEBELL, :EVIOLITE, :DESTINYKNOT, :ROCKYHELMET,
    :ASSAULTVEST, :LIFEORB, :CHOICEBAND, :CHOICESPECS, :CHOICESCARF,
    :FOCUSSASH, :FOCUSBAND, :LIGHTCLAY, :SCOPELENS, :BLACKSLUDGE,
    :WIDELENS, :AIRBALLOON, :EXPERTBELT,
    :TM04, :TM06, :TM08, :TM29, :TM30, :TM73, :TM75, :TM89, :TM90
  ]

  ORANGE_POOL = [
    :PPMAX, :PPUP, :ABILITYCAPSULE, :ABILITYPATCH,
    :RARECANDY, :MAXREVIVE, :OLDAMBER, :HELIXFOSSIL, :DOMEFOSSIL,
    :SCapsula, :ACapsula, :DCapsula, :AECapsula, :DECapsula, :VCapsula,
    :LEFTOVERS, :TM13, :TM24, :TM26, :TM35,
    :SACOMOEDAMEDIO, :POKEMONBOXLINK, :LUCKYEGG
  ]

  LEGENDARY_MEGA_STONES = [
    :MEWTWONITEX, :MEWTWONITEY, :LATIOSITE, :LATIASITE, :DIANCITE,
    :ZYGARDITE, :FLOETTITE, :DARKRANITE, :MAGEARNITE, :HEATRANITE, :ZERAORITE
  ]

  # A caixa vermelha e a unica pool COM PESOS: item => peso relativo.
  # As outras (verde/azul/laranja) continuam listas simples, porque la todos os
  # itens sao do mesmo patamar e o sorteio uniforme e o comportamento desejado.
  #
  # POR QUE PESOS
  # Antes isto era uma lista plana sorteada por rand(length), com "portoes de
  # retencao" costurados em pick_items para segurar MASTERBALL5, as orbes, o
  # SHINYZADOR e o SUPERSHINYZADOR. O esquema tinha dois furos:
  #
  #   1. MASTERBALL (1x) e SHINYCHARM nunca entraram em portao nenhum, entao
  #      saiam com o peso de um item comum: 1/54 = 1,85% por slot.
  #   2. O fallback de cada portao re-sorteava numa lista que INCLUIA esses
  #      dois. Como ~15% de toda a massa era rejeitada pelos portoes e
  #      redistribuida, MASTERBALL e SHINYCHARM subiam para 2,20% por slot.
  #      Na pratica o portao do Shinyzador convertia Shinyzador em Masterball.
  #
  #   Resultado medido: 1 em cada 16 caixas soltava Masterball ou Shiny Charm.
  #
  # Com peso explicito nao ha portao nem fallback, entao nao ha massa vazando
  # de um item para outro: a raridade de cada item e o proprio numero aqui.
  #
  # COMO CALIBRAR
  # A chance por slot e peso/soma_dos_pesos. A soma hoje e 4400 e a caixa da em
  # media 1,35 itens (ver roll_item_count), entao a chance por CAIXA e cerca de
  # 1,35x a chance por slot. Peso 100 = item comum da vermelha (~2,3% do slot).
  RED_POOL = {
    # --- Ultra raros ---------------------------------------------------------
    :SUPERSHINYZADOR => 1,     # ~1 a cada 3.300 caixas
    :SHINYZADOR      => 5,     # ~1 a cada   650 caixas
    :MASTERBALL5     => 16,    # ~1 a cada   200 caixas
    :MASTERBALL      => 33,    # ~1 a cada   100 caixas
    :SHINYCHARM      => 33,    # ~1 a cada   100 caixas
    # --- Orbes Super Shiny ---------------------------------------------------
    :ORBEFLAMEJANTE  => 16, :ORBEDELIMA     => 16, :ORBEDEESMERALDA => 16,
    :ORBETURQUESA    => 16, :ORBEDESAFIRA   => 16, :ORBEDEAMETISTA  => 16,
    :ORBEROSA        => 16,
    # --- Resto do pool (peso comum) ------------------------------------------
    # Sacos de Moedas
    :SACOMOEDAGRANDE => 100,
    # Fusão e Separação
    :DNASPLICERS => 100, :NSOLARIZER => 100, :NLUNARIZER => 100,
    :REINSOFUNITY => 100,
    # Mudança de Forma
    :METEORITE => 100, :GRACIDEA => 100, :REVEALGLASS => 100,
    :PRISONBOTTLE => 100, :ZYGARDECUBE => 100,
    :SCROLLOFDARKNESS => 100, :SCROLLOFWATERS => 100,
    :TEALMASK => 100, :WELLSPRINGMASK => 100, :HEARTHFLAMEMASK => 100,
    :CORNERSTONEMASK => 100,
    :REDNECTAR => 100, :YELLOWNECTAR => 100, :PINKNECTAR => 100,
    :PURPLENECTAR => 100,
    # Orbes Primal, Origem e Equipamentos
    :REDORB => 100, :BLUEORB => 100, :ADAMANTORB => 100,
    :ADAMANTCRYSTAL => 100, :LUSTROUSORB => 100, :LUSTROUSGLOBE => 100,
    :GRISEOUSORB => 100, :GRISEOUSCORE => 100, :RUSTEDSWORD => 100,
    :RUSTEDSHIELD => 100, :SOULDEW => 100,
    # Megapedras Lendárias e Especiais
    :MEWTWONITEX => 100, :MEWTWONITEY => 100, :LATIOSITE => 100,
    :LATIASITE => 100, :DIANCITE => 100,
    :ZYGARDITE => 100, :FLOETTITE => 100, :DARKRANITE => 100,
    :MAGEARNITE => 100, :HEATRANITE => 100, :ZERAORITE => 100
  }

  # Associação item -> pool
  BOX_DATA = {
    :GIFT_GREEN  => { pool: GREEN_POOL,  color: Color.new(80, 200, 80) },
    :GIFT_BLUE   => { pool: BLUE_POOL,   color: Color.new(80, 140, 255) },
    :GIFT_ORANGE => { pool: ORANGE_POOL,  color: Color.new(255, 180, 60) },
    :GIFT_RED    => { pool: RED_POOL,     color: Color.new(255, 60, 60) }
  }

  def self.roll_item_count
    roll = rand(100)
    if roll < 5       # 5%  -> 3 itens
      return 3
    elsif roll < 30   # 25% -> 2 itens
      return 2
    else              # 70% -> 1 item
      return 1
    end
  end

  # Aceita os dois formatos de pool:
  #   Array  (verde/azul/laranja) -> sorteio uniforme, como sempre foi
  #   Hash   (vermelha)           -> sorteio ponderado por {item => peso}
  #
  # Nao ha mais portao de retencao: a raridade vive inteira nos pesos do pool.
  # Portao com re-sorteio era o que vazava probabilidade de um item para outro
  # e inflava MASTERBALL/SHINYCHARM — ver o comentario em RED_POOL.
  def self.pick_items(pool, count)
    items = []
    weighted = pool.is_a?(Hash)
    ids = weighted ? pool.keys : pool

    available = ids.select do |id|
      next true if id == :MEGA_STONE_CHANCE || id == :MASTERBALL5
      begin
        GameData::Item.exists?(id)
      rescue
        false
      end
    end
    return items if available.empty?

    # Os pesos sao lidos DEPOIS do filtro de existencia, entao um item que nao
    # exista no PBS simplesmente sai da conta em vez de furar as proporcoes.
    if weighted
      weights = available.map { |id| [pool[id].to_i, 0].max }
      total   = weights.inject(0) { |soma, w| soma + w }
      return items if total <= 0
    end

    count.times do
      if weighted
        alvo   = rand(total)
        acc    = 0
        picked = available[available.length - 1]   # guarda contra erro de arredondamento
        available.each_with_index do |id, i|
          acc += weights[i]
          if alvo < acc
            picked = id
            break
          end
        end
      else
        picked = available[rand(available.length)]
      end

      if picked == :MEGA_STONE_CHANCE && @mega_stones_pool && !@mega_stones_pool.empty?
        items << @mega_stones_pool[rand(@mega_stones_pool.length)]
      else
        items << picked
      end
    end
    items
  end

  #=============================================================================
  # Carrega o ícone de um item como bitmap 48x48
  #=============================================================================
  def self.load_item_icon(item_id, fallback_color)
    target_id = (item_id == :MASTERBALL5) ? :MASTERBALL : item_id
    filename = GameData::Item.icon_filename(target_id)
    if filename
      begin
        bmp = Bitmap.new(filename)
        if bmp.width > bmp.height
          cropped = Bitmap.new(bmp.height, bmp.height)
          cropped.blt(0, 0, bmp, Rect.new(0, 0, bmp.height, bmp.height))
          bmp.dispose rescue nil
          return cropped
        end
        return bmp
      rescue
      end
    end
    # Fallback: quadrado colorido
    bmp = Bitmap.new(24, 24)
    bmp.fill_rect(0, 0, 24, 24, fallback_color)
    bmp
  end

  #=============================================================================
  # Animação de Abertura Unificada (Caixa -> Brilho -> Partículas e Itens)
  #=============================================================================
  def self.animate_gift_box_open(box_sym, items, box_color)
    cx = $game_player.screen_x
    cy_start = $game_player.screen_y - 16
    cy_end = $game_player.screen_y - 76 # Altura do busy balloon
    ground_y_base = $game_player.screen_y
    base_scale = 0.7 # Caixa menor para ficar harmônica

    viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    viewport.z = 99999

    # Sprite da caixa
    box_sprite = Sprite.new(viewport)
    box_sprite.bitmap = load_item_icon(box_sym, box_color)
    box_sprite.ox = box_sprite.bitmap.width / 2
    box_sprite.oy = box_sprite.bitmap.height / 2
    box_sprite.x = cx
    box_sprite.y = cy_start
    box_sprite.z = 99999
    box_sprite.zoom_x = 0.2
    box_sprite.zoom_y = 0.2
    box_sprite.opacity = 0

    particles = []
    item_sprites = []

    # Estado/Controle do loop
    box_state = :rise # :rise, :glow, :release, :fade, :done
    box_phase_frame = 0
    frame = 0

    # Duração das fases
    rise_duration = 18
    glow_duration = 15
    release_hold_duration = 15 # Tempo que a caixa fica visível após explodir (~0.5s)
    fade_duration = 15         # Tempo de desvanecimento da caixa

    loop do
      Graphics.update
      Input.update
      pbUpdateSceneMap

      # --- FASE DA CAIXA ---
      if box_state == :rise
        t = box_phase_frame.to_f / rise_duration.to_f
        ease_out = Math.sin(t * Math::PI / 2.0)
        box_sprite.y = cy_start - ((cy_start - cy_end) * ease_out).to_i
        box_sprite.opacity = [t * 255 * 1.5, 255].min.to_i
        scale = 0.2 + (base_scale - 0.2) * ease_out
        box_sprite.zoom_x = scale
        box_sprite.zoom_y = scale

        box_phase_frame += 1
        if box_phase_frame >= rise_duration
          box_sprite.y = cy_end
          box_state = :glow
          box_phase_frame = 0
          pbSEPlay("Spark", 80, 130) rescue nil
        end

      elsif box_state == :glow
        box_sprite.y = cy_end
        t = box_phase_frame.to_f / glow_duration.to_f
        pulse_scale = base_scale + Math.sin(t * Math::PI) * 0.20
        box_sprite.zoom_x = pulse_scale
        box_sprite.zoom_y = pulse_scale

        if box_phase_frame == 3
          box_sprite.flash(box_color, 10)
        end

        box_phase_frame += 1
        if box_phase_frame >= glow_duration
          box_state = :release
          box_phase_frame = 0

          # EXPLOSÃO E SPAWN
          pbSEPlay("Explosion7", 75, 110) rescue nil
          
          # Criação das 32 partículas
          32.times do
            p_sp = Sprite.new(viewport)
            size = 4 + rand(4)
            p_sp.bitmap = Bitmap.new(size, size)
            r = [[box_color.red.to_i   + rand(80) - 40, 0].max, 255].min
            g = [[box_color.green.to_i + rand(80) - 40, 0].max, 255].min
            b = [[box_color.blue.to_i  + rand(80) - 40, 0].max, 255].min
            p_sp.bitmap.fill_rect(0, 0, size, size, Color.new(r, g, b, 255))
            p_sp.ox = size / 2
            p_sp.oy = size / 2
            p_sp.x = cx
            p_sp.y = cy_end
            p_sp.z = 99998
            
            # Direção chafariz (ângulo de 220° a 320°)
            angle_deg = 220.0 + rand(100.0)
            angle_rad = angle_deg * Math::PI / 180.0
            speed = 2.5 + rand * 4.0
            
            particles << {
              sprite: p_sp,
              vx: Math.cos(angle_rad) * speed,
              vy: Math.sin(angle_rad) * speed, # negativo (para cima)
              gravity: -0.05, # gravidade negativa para continuarem subindo
              x: cx.to_f,
              y: cy_end.to_f,
              opacity: 255,
              life: 35 # frames de vida das partículas
            }
          end

          # Criação dos itens (chafariz clássico)
          item_count = items.length
          items.each_with_index do |item_id, i|
            it_sp = Sprite.new(viewport)
            it_sp.bitmap = load_item_icon(item_id, box_color)
            it_sp.ox = it_sp.bitmap.width / 2
            it_sp.oy = it_sp.bitmap.height / 2
            it_sp.x = cx
            it_sp.y = cy_end
            it_sp.z = 99990 + i
            it_sp.zoom_x = 0.25
            it_sp.zoom_y = 0.25

            if item_count == 1
              angle_deg = 270.0
            elsif item_count == 2
              angle_deg = (i == 0) ? 245.0 : 295.0
            else
              angle_deg = 220.0 + (100.0 / (item_count - 1).to_f) * i
            end

            angle_rad = angle_deg * Math::PI / 180.0
            speed = 3.5 + rand * 1.5

            item_sprites << {
              sprite: it_sp,
              vx: Math.cos(angle_rad) * speed,
              vy: Math.sin(angle_rad) * speed - 1.0,
              gravity: 0.18,
              x: cx.to_f,
              y: cy_end.to_f,
              frame: 0,
              landed: false,
              ground_y: ground_y_base - 10 + rand(16),
              hold_frame: 0,
              opacity: 255
            }
          end
        end

      elsif box_state == :release
        box_sprite.y = cy_end
        box_sprite.zoom_x = base_scale
        box_sprite.zoom_y = base_scale
        # Permanece visível por release_hold_duration
        box_phase_frame += 1
        if box_phase_frame >= release_hold_duration
          box_state = :fade
          box_phase_frame = 0
        end

      elsif box_state == :fade
        box_sprite.y = cy_end
        box_sprite.zoom_x = base_scale
        box_sprite.zoom_y = base_scale
        # Desvanece a caixa
        t = box_phase_frame.to_f / fade_duration.to_f
        box_sprite.opacity = [255 - (t * 255).to_i, 0].max
        box_phase_frame += 1
        if box_phase_frame >= fade_duration
          box_sprite.opacity = 0
          box_sprite.dispose rescue nil
          box_state = :done
        end
      end

      # --- EFEITO SACUDIR CONTÍNUO ---
      if box_state != :done && box_sprite && !box_sprite.disposed?
        box_sprite.angle = Math.sin(frame * 0.45) * 12
        box_sprite.x = cx + (Math.sin(frame * 0.8) * 3).to_i
      end

      frame += 1

      # --- ATUALIZA PARTICULAS ---
      particles.each do |p|
        next if p[:life] <= 0 || !p[:sprite] || p[:sprite].disposed?
        p[:life] -= 1
        p[:vy] += p[:gravity]
        p[:vx] *= 0.95 # desaceleração lateral
        p[:x] += p[:vx]
        p[:y] += p[:vy]
        p[:sprite].x = p[:x].to_i
        p[:sprite].y = p[:y].to_i
        # Fade out ao longo da vida útil
        p[:opacity] = (p[:life].to_f / 35.0 * 255.0).to_i
        p[:sprite].opacity = p[:opacity]
        if p[:life] <= 0
          p[:sprite].bitmap.dispose rescue nil
          p[:sprite].dispose rescue nil
        end
      end

      # --- ATUALIZA ITENS ---
      item_sprites.each do |data|
        sp = data[:sprite]
        next if !sp || sp.disposed?
        if !data[:landed]
          data[:frame] += 1
          data[:vy] += data[:gravity]
          data[:x] += data[:vx]
          data[:y] += data[:vy]
          # Limita dispersão lateral a 96 pixels (3 tiles)
          data[:x] = [[data[:x], cx + 96].min, cx - 96].max

          sp.x = data[:x].to_i
          sp.y = data[:y].to_i

          # Cresce gradualmente
          progress = [data[:frame] / 15.0, 1.0].min
          scale = 0.25 + 0.45 * progress
          sp.zoom_x = scale
          sp.zoom_y = scale
          sp.angle = (sp.angle + 12) % 360

          # Checagem de colisão com o chão
          if data[:y] >= data[:ground_y] && data[:vy] > 0 && data[:frame] > 8
            data[:landed] = true
            sp.angle = 0
            sp.zoom_x = 0.7
            sp.zoom_y = 0.7
            sp.y = data[:ground_y].to_i
          end
        else
          # Item no chão
          if data[:hold_frame] < 30
            data[:hold_frame] += 1
          else
            # Fade out
            data[:opacity] = [data[:opacity] - 16, 0].max
            sp.opacity = data[:opacity]
            if data[:opacity] <= 0 && sp && !sp.disposed?
              sp.bitmap.dispose rescue nil
              sp.dispose rescue nil
            end
          end
        end
      end

      # Condição de parada: a caixa terminou, todas as partículas morreram e todos os itens terminaram de sumir
      all_done = (box_state == :done) && 
                 particles.all? { |p| p[:life] <= 0 } &&
                 item_sprites.all? { |data| data[:sprite].disposed? rescue true }

      break if all_done
    end

    # Garantia de limpeza
    box_sprite.dispose rescue nil
    particles.each do |p|
      p[:sprite].bitmap.dispose rescue nil
      p[:sprite].dispose rescue nil
    end
    item_sprites.each do |data|
      data[:sprite].bitmap.dispose rescue nil
      data[:sprite].dispose rescue nil
    end
    viewport.dispose rescue nil
  end

  #=============================================================================
  # Abertura completa de uma Gift Box
  #=============================================================================
  #=============================================================================
  # DUPLICACAO DA CAIXA — a janela entre o premio e o consumo
  #=============================================================================
  # ⚠️ Abrir uma caixa e fechar o jogo depressa duplicava-a.
  #
  # A sequencia era esta:
  #
  #   1. open_gift_box faz $bag.add(premio) para cada item;
  #   2. o MOD 040 tem um hook no PokemonBag#add que dispara
  #      save_and_upload_save_file("item_added") — e o autosave grava NESSE
  #      instante, com os premios ja na mochila e a CAIXA AINDA LA;
  #   3. so depois o metodo devolve true, e e ai que o Essentials consome a
  #      caixa (ver o comentario original mais abaixo);
  #   4. o $bag.remove do consumo tambem pede um save, mas esse cai dentro da
  #      janela de 60s do throttle e fica adiado.
  #
  # Quem matava o jogo entre o 2 e o 4 — no Android basta trocar de app —
  # ficava com o estado do passo 2 gravado: premios recebidos e caixa intacta.
  #
  # A correccao tem duas metades. Enquanto a caixa abre, os saves dos premios
  # sao SUPRIMIDOS (nao ha estado consistente para gravar no meio da operacao),
  # e no frame seguinte — quando o Essentials ja consumiu a caixa — grava-se uma
  # vez so, com tudo certo.
  #
  # Os orbes de cor NAO tinham este problema: eles mexem no Pokemon, nao na
  # mochila, portanto nenhum autosave dispara a meio.
  #=============================================================================
  def self.abrindo?; @abrindo == true; end

  def self.agendar_save_pos_caixa!
    @save_pendente = true
    @tentativas = 0
  end

  # Chamado a cada frame pelo Scene_Map. O teste e um booleano, entao o custo
  # de o ter aqui e nenhum.
  def self.escoar_save_pendente!
    return unless @save_pendente
    return if @abrindo
    return unless defined?(AnilLanRework)

    # ⚠️ SO SE DESISTE DEPOIS DE GRAVAR MESMO.
    #
    # A primeira versao limpava a marca antes de tentar, e o
    # save_and_upload_save_file recusa quando o estado nao esta seguro:
    #
    #     unless AnilLanRework.can_save_safely?
    #       AnilLanRework.queue_deferred_autosave!(reason)
    #       return false
    #
    # Logo apos abrir a caixa o jogo ainda esta a fechar a mochila e a mostrar o
    # aviso, entao a gravacao caia nesse ramo e virava um autosave adiado —
    # sujeito a janela de 60s. Quem fechasse o jogo ali perdia a abertura e a
    # caixa voltava intacta, que e exactamente o bug que isto vinha corrigir.
    #
    # Agora insiste-se a cada frame ate o jogo aceitar gravar. O limite existe
    # para nao tentar para sempre se algo ficar preso.
    @tentativas = (@tentativas || 0) + 1
    if @tentativas > 600      # ~15s a 40 FPS
      @save_pendente = false
      @tentativas = 0
      AnilLanRework.log("gift box: desisti de gravar apos 600 tentativas") rescue nil
      return
    end

    return unless AnilLanRework.connected? && AnilLanRework.multiplayer_mode
    return unless AnilLanRework.can_save_safely?

    @save_pendente = false
    @tentativas = 0
    AnilLanRework.save_and_upload_save_file("gift_box")
  rescue => e
    @save_pendente = false
    AnilLanRework.log("gift box save error: #{e.message}") rescue nil
  end


  # E uma Gift Box?
  def self.caixa?(item)
    BOX_DATA.key?(item.is_a?(Symbol) ? item : item.to_s.to_sym)
  rescue
    false
  end

  #=============================================================================
  # USAR A CAIXA — consumo e gravacao ANTES da apresentacao
  #=============================================================================
  # ⚠️ A ORDEM AQUI E O CONSERTO.
  #
  # Antes: premios -> animacao -> aviso -> (Essentials consome) -> save.
  # Entre o primeiro e o ultimo passo passavam-se varios segundos, e quem
  # fechasse o jogo no meio perdia tudo — a caixa voltava intacta.
  #
  # Agora: consome -> premios -> GRAVA -> animacao -> aviso.
  # A partir do momento em que a gravacao termina, o estado ja e o final. O que
  # vem depois e so espectaculo, e pode ser interrompido a vontade.
  #
  # O consumo passa a ser NOSSO. O caminho normal (pbUseKeyItemInField) so
  # remove o item depois de o handler devolver true, e e justamente isso que
  # tornava impossivel gravar cedo: gravar antes dele gravaria a caixa AINDA na
  # mochila, que era o bug da duplicacao.
  def self.usar_caixa(item)
    sym = item.is_a?(Symbol) ? item : item.to_s.to_sym
    return false unless BOX_DATA.key?(sym)
    return false unless $bag && $bag.has?(sym)

    @abrindo = true
    begin
      $bag.remove(sym, 1)
      ok = open_gift_box(sym)
      unless ok
        # Nada foi entregue: devolve a caixa para nao a perder por nada.
        $bag.add(sym, 1) rescue nil
        return false
      end
    ensure
      @abrindo = false
    end
    true
  rescue => e
    @abrindo = false
    AnilLanRework.log("gift box usar_caixa: #{e.class}: #{e.message}") rescue nil
    false
  end

  # Grava AGORA, sem passar pelo can_save_safely?.
  #
  # O caminho normal recusa quando a cena nao esta estavel e transforma o pedido
  # num autosave adiado — sujeito a janela de 60s. Aqui escreve-se o ficheiro
  # directamente, como o execute_trade faz depois de uma troca, e so depois se
  # pede o upload (que pode ser adiado a vontade: o disco ja esta correcto).
  def self.gravar_agora!
    AnilLanRework.gravar_ja!("gift_box")
    AnilLanRework.log("gift box: gravado antes da apresentacao") rescue nil
  rescue => e
    AnilLanRework.log("gift box: falha ao gravar: #{e.class}: #{e.message}") rescue nil
  end

  def self.open_gift_box(box_sym)
    if defined?(AnilLanRework) && (!AnilLanRework.respond_to?(:multiplayer_mode) || !AnilLanRework.multiplayer_mode)
      pbMessage(_INTL("As Caixas de Presente são exclusivas do Modo Multiplayer Online!"))
      return false
    end

    data = BOX_DATA[box_sym]
    return false unless data

    # A partir daqui ate ao fim, nenhum autosave dos premios deve gravar: o
    # estado so volta a ser consistente depois de o Essentials consumir a caixa.
    @abrindo = true

    pool = data[:pool]
    color = data[:color]

    # Rola quantidade de itens
    count = roll_item_count
    items = pick_items(pool, count)
    return false if items.empty?

    # Consome a caixa da bag (removido para evitar consumo duplo, Essentials já consome ao retornar true no UseInField)

    # ENVIA EVENTO MULTIPLAYER PARA OUTROS JOGADORES VEREM A ANIMAÇÃO
    if defined?(AnilLanRework) && AnilLanRework.connected?
      AnilLanRework.connection.send_packet("gift_box_open_broadcast", {
        "sender_id" => AnilLanRework.self_internal_id.to_s,
        "box_sym" => box_sym.to_s,
        "items" => items.map(&:to_s),
        "color" => [color.red.to_i, color.green.to_i, color.blue.to_i]
      }) rescue nil
    end

    # Dá os itens ao jogador com mensagem e fanfare
    items.each do |item_id|
      begin
        actual_item = (item_id == :MASTERBALL5) ? :MASTERBALL : item_id
        qty = (item_id == :MASTERBALL5) ? 5 : 1
        if GameData::Item.exists?(actual_item)
          base_name = GameData::Item.get(actual_item).name rescue actual_item.to_s
          item_name = (item_id == :MASTERBALL5) ? "5x #{base_name}" : base_name
          if $bag.can_add?(actual_item, qty)
            $bag.add(actual_item, qty)
            pbMEPlay("Item get")
            if defined?(AnilLanRework) && AnilLanRework.respond_to?(:add_popup)
              AnilLanRework.add_popup(_INTL("Você recebeu {1} de presente!", item_name), 6.0, actual_item)
            else
              pbMessage(_INTL("\\me[]Você encontrou \\c[1]{1}\\c[0] na caixa de presente!", item_name))
            end
          else
            if defined?(AnilLanRework) && AnilLanRework.respond_to?(:add_popup)
              AnilLanRework.add_popup(_INTL("Mochila cheia! Não foi possível receber {1}.", item_name), 6.0, actual_item)
            else
              pbMessage(_INTL("Sua mochila está cheia! Não foi possível guardar {1}.", item_name))
            end
          end
        end
      rescue => e
        # Proteção contra item inválido
        AnilLanRework.log("gift box add item error: #{e.message}") rescue nil
      end
    end

    # ─────────────────────────────────────────────────────────────────────
    # GRAVA AQUI. Caixa fora da mochila, premios dentro.
    # Tudo o que vem a seguir e apresentacao e pode ser interrompido.
    # ─────────────────────────────────────────────────────────────────────
    gravar_agora!

    # ⚠️ A ANIMACAO SO CORRE DEPOIS DE ESTAR GRAVADO.
    #
    # Ver usar_caixa: a caixa ja saiu da mochila, os premios ja entraram e o
    # save ja foi escrito antes de chegar aqui. Se o jogador fechar o jogo
    # durante a animacao ou o aviso, nao perde nada — e era exactamente isso que
    # acontecia, porque a gravacao vinha depois.
    animate_gift_box_open(box_sym, items, color)

    # Fim. Quem consome a caixa agora e o usar_caixa, ANTES daqui — por isso o
    # save ja aconteceu la em cima, com o estado final.
    @abrindo = false
    return true
  rescue => e
    @abrindo = false
    AnilLanRework.log("gift box open error: #{e.class}: #{e.message}") rescue nil
    return false
  end

  #=============================================================================
  # Processa o pacote recebido de outro jogador abrindo uma Gift Box
  #=============================================================================
  def self.on_receive_gift_box_open(packet)
    sender_id = packet["sender_id"].to_s
    return if sender_id.empty?
    
    # 1. Encontra o peer correspondente
    peer = nil
    if defined?(AnilLanRework) && AnilLanRework.respond_to?(:players)
      peer = AnilLanRework.players[sender_id]
      if !peer
        # Fallback: busca por prefixo do ID do jogador (antes do traço)
        base_sender = sender_id.split("-").first.to_s.downcase
        unless base_sender.empty?
          peer = AnilLanRework.players.values.find do |p|
            p.internal_id.to_s.split("-").first.to_s.downcase == base_sender
          end
        end
      end
    end
    return unless peer
    
    # 2. Só exibe se estiver no mesmo mapa
    return unless peer.map_id == $game_map.map_id
    
    box_sym = packet["box_sym"].to_sym rescue nil
    return unless box_sym
    
    items = Array(packet["items"]).map(&:to_sym) rescue []
    
    color_arr = packet["color"] || [255, 255, 255]
    color = Color.new(color_arr[0], color_arr[1], color_arr[2])
    
    # 3. Encontra o viewport da cena do mapa de forma segura
    viewport = nil
    if $scene.is_a?(Scene_Map)
      if $scene.respond_to?(:spriteset) && $scene.spriteset
        viewport = $scene.spriteset.instance_variable_get(:@viewport1) rescue nil
      elsif $scene.instance_variable_get(:@spritesets) && $game_map
        s_set = $scene.instance_variable_get(:@spritesets)[$game_map.map_id] rescue nil
        viewport = s_set.instance_variable_get(:@viewport1) rescue nil if s_set
      end
    end
    viewport ||= Spriteset_Map.viewport rescue nil
    return unless viewport

    # 4. Cria e adiciona a animação ao gerenciador global unificado do multiplayer
    anim = RemoteGiftBoxAnimation.new(viewport, peer, box_sym, items, color) rescue nil
    if anim && defined?(AnilLanRework) && AnilLanRework.respond_to?(:add_overworld_animation)
      AnilLanRework.add_overworld_animation(anim)
    end
  end
end

#===============================================================================
# Handlers de uso para cada Gift Box
#===============================================================================
if defined?(ItemHandlers)
  # GIFT_GREEN - Retorna 2 = fechar bag e voltar ao overworld, depois UseInField
  ItemHandlers::UseFromBag.add(:GIFT_GREEN, proc { |item|
    next 2
  })
  ItemHandlers::UseInField.add(:GIFT_GREEN, proc { |item|
    next GiftBoxSystem.open_gift_box(:GIFT_GREEN)
  })

  # GIFT_BLUE
  ItemHandlers::UseFromBag.add(:GIFT_BLUE, proc { |item|
    next 2
  })
  ItemHandlers::UseInField.add(:GIFT_BLUE, proc { |item|
    next GiftBoxSystem.open_gift_box(:GIFT_BLUE)
  })

  # GIFT_ORANGE
  ItemHandlers::UseFromBag.add(:GIFT_ORANGE, proc { |item|
    next 2
  })
  ItemHandlers::UseInField.add(:GIFT_ORANGE, proc { |item|
    next GiftBoxSystem.open_gift_box(:GIFT_ORANGE)
  })

  # GIFT_RED
  ItemHandlers::UseFromBag.add(:GIFT_RED, proc { |item|
    next 2
  })
  ItemHandlers::UseInField.add(:GIFT_RED, proc { |item|
    next GiftBoxSystem.open_gift_box(:GIFT_RED)
  })
end

#===============================================================================
# Registra os Gift Box items e adiciona mega stones ao pool
# Precisa rodar DEPOIS de GameData.load_all, por isso está em on_enter_map
#===============================================================================
GIFT_BOX_DEFS = [
  {
    :id               => :GIFT_GREEN,
    :real_name        => "Caixa Verde",
    :real_name_plural => "Caixas Verdes",
    :pocket           => 1,
    :price            => 0,
    :sell_price        => 0,
    :field_use        => 2,
    :battle_use       => 0,
    :flags            => [],
    :consumable       => true,
    :show_quantity    => true,
    :real_description => "Uma caixa de presente verde. Use para abrir e receber itens comuns!"
  },
  {
    :id               => :GIFT_BLUE,
    :real_name        => "Caixa Azul",
    :real_name_plural => "Caixas Azuis",
    :pocket           => 1,
    :price            => 0,
    :sell_price        => 0,
    :field_use        => 2,
    :battle_use       => 0,
    :flags            => [],
    :consumable       => true,
    :show_quantity    => true,
    :real_description => "Uma caixa de presente azul. Use para abrir e receber itens raros!"
  },
  {
    :id               => :GIFT_ORANGE,
    :real_name        => "Caixa Laranja",
    :real_name_plural => "Caixas Laranjas",
    :pocket           => 1,
    :price            => 0,
    :sell_price        => 0,
    :field_use        => 2,
    :battle_use       => 0,
    :flags            => [],
    :consumable       => true,
    :show_quantity    => true,
    :real_description => "Uma caixa de presente laranja. Use para abrir e receber itens super raros!"
  },
  {
    :id               => :GIFT_RED,
    :real_name        => "Caixa Vermelha",
    :real_name_plural => "Caixas Vermelhas",
    :pocket           => 1,
    :price            => 0,
    :sell_price        => 0,
    :field_use        => 2,
    :battle_use       => 0,
    :flags            => [],
    :consumable       => true,
    :show_quantity    => true,
    :real_description => "Uma caixa de presente vermelha. Use para abrir e receber itens lendários e Master Balls!"
  }
]

$gift_boxes_registered = false

EventHandlers.add(:on_enter_map, :gift_box_register_and_test, proc { |_old_map_id|
  # Registra os Gift Boxes no GameData (só 1 vez por sessão)
  if !$gift_boxes_registered
    $gift_boxes_registered = true
    GIFT_BOX_DEFS.each do |item_hash|
      GameData::Item.register(item_hash)
    end
    # Adiciona apenas mega stones normais (não lendárias) ao pool laranja
    begin
      mega_stones = GameData::Item.keys.select do |k|
        begin
          GameData::Item.get(k).is_mega_stone? && !LEGENDARY_MEGA_STONES.include?(k)
        rescue
          false
        end
      end
      GiftBoxSystem.mega_stones_pool = mega_stones
      GiftBoxSystem::ORANGE_POOL << :MEGA_STONE_CHANCE unless mega_stones.empty?
    rescue
    end
  end
})

#===============================================================================
# Renderizador Assíncrono de Caixas de Presente Abertas por Jogadores Remotos
#===============================================================================
class RemoteGiftBoxAnimation
  attr_reader :disposed

  def initialize(viewport, peer, box_sym, items, box_color)
    @viewport = viewport
    @peer = peer
    @box_sym = box_sym
    @items = items
    @box_color = box_color
    @disposed = false

    # Coordenadas iniciais
    @cx = @peer.screen_x rescue 0
    @cy_start = (@peer.screen_y rescue 0) - 16
    @cy_end = (@peer.screen_y rescue 0) - 76
    @ground_y_base = (@peer.screen_y rescue 0)
    @base_scale = 0.7

    # Sprite da caixa
    @box_sprite = Sprite.new(@viewport)
    @box_sprite.bitmap = GiftBoxSystem.load_item_icon(@box_sym, @box_color) rescue nil
    if @box_sprite.bitmap
      @box_sprite.ox = @box_sprite.bitmap.width / 2
      @box_sprite.oy = @box_sprite.bitmap.height / 2
    end
    @box_sprite.x = @cx
    @box_sprite.y = @cy_start
    @box_sprite.z = 99999
    @box_sprite.zoom_x = 0.2
    @box_sprite.zoom_y = 0.2
    @box_sprite.opacity = 0

    @particles = []
    @item_sprites = []

    @box_state = :rise
    @box_phase_frame = 0
    @frame = 0

    @rise_duration = 18
    @glow_duration = 15
    @release_hold_duration = 15
    @fade_duration = 15
    @last_display_x = $game_map ? $game_map.display_x : 0
    @last_display_y = $game_map ? $game_map.display_y : 0
  end

  def disposed?
    @disposed
  end

  def update
    return if @disposed

    display_x = $game_map ? $game_map.display_x : 0
    display_y = $game_map ? $game_map.display_y : 0
    @last_display_x ||= display_x
    @last_display_y ||= display_y
    scroll_x = ((display_x - @last_display_x) / (Game_Map::X_SUBPIXELS rescue 4)).round rescue 0
    scroll_y = ((display_y - @last_display_y) / (Game_Map::Y_SUBPIXELS rescue 4)).round rescue 0
    @last_display_x = display_x
    @last_display_y = display_y

    if scroll_x != 0 || scroll_y != 0
      @cy_start -= scroll_y rescue nil
      @particles.each do |p|
        p[:x] -= scroll_x
        p[:y] -= scroll_y
      end
      @item_sprites.each do |data|
        data[:x] -= scroll_x
        data[:y] -= scroll_y
        data[:ground_y] -= scroll_y
      end
    end
    
    # Atualiza as coordenadas em tempo real caso o remote player esteja se movendo!
    if @peer && (!@peer.respond_to?(:disposed?) || !@peer.disposed?)
      @cx = @peer.screen_x rescue @cx
      @cy_end = (@peer.screen_y - 76) rescue @cy_end
      @ground_y_base = @peer.screen_y rescue @ground_y_base
    end

    # --- FASE DA CAIXA ---
    if @box_state == :rise
      t = @box_phase_frame.to_f / @rise_duration.to_f
      ease_out = Math.sin(t * Math::PI / 2.0)
      if @box_sprite
        @box_sprite.y = @cy_start - ((@cy_start - @cy_end) * ease_out).to_i
        @box_sprite.opacity = [t * 255 * 1.5, 255].min.to_i
        scale = 0.2 + (@base_scale - 0.2) * ease_out
        @box_sprite.zoom_x = scale
        @box_sprite.zoom_y = scale
      end
      @box_phase_frame += 1
      if @box_phase_frame >= @rise_duration
        @box_sprite.y = @cy_end if @box_sprite
        @box_state = :glow
        @box_phase_frame = 0
        pbSEPlay("Spark", 80, 130) rescue nil
      end

    elsif @box_state == :glow
      @box_sprite.y = @cy_end if @box_sprite
      t = @box_phase_frame.to_f / @glow_duration.to_f
      pulse_scale = @base_scale + Math.sin(t * Math::PI) * 0.20
      if @box_sprite
        @box_sprite.zoom_x = pulse_scale
        @box_sprite.zoom_y = pulse_scale
      end
      if @box_phase_frame == 3 && @box_sprite
        @box_sprite.flash(@box_color, 10)
      end
      @box_phase_frame += 1
      if @box_phase_frame >= @glow_duration
        pbSEPlay("Explosion7", 75, 110) rescue nil
        @box_state = :release
        @box_phase_frame = 0

        # EXPLOSÃO E SPAWN PARTICULAS
        32.times do
          p_sp = Sprite.new(@viewport)
          size = 4 + rand(4)
          p_sp.bitmap = Bitmap.new(size, size)
          r = [[@box_color.red.to_i   + rand(80) - 40, 0].max, 255].min
          g = [[@box_color.green.to_i + rand(80) - 40, 0].max, 255].min
          b = [[@box_color.blue.to_i  + rand(80) - 40, 0].max, 255].min
          p_sp.bitmap.fill_rect(0, 0, size, size, Color.new(r, g, b, 255))
          p_sp.ox = size / 2
          p_sp.oy = size / 2
          p_sp.x = @cx
          p_sp.y = @cy_end
          p_sp.z = 99998
          
          angle_deg = 220.0 + rand(100.0)
          angle_rad = angle_deg * Math::PI / 180.0
          speed = 2.5 + rand * 4.0
          
          @particles << {
            sprite: p_sp,
            vx: Math.cos(angle_rad) * speed,
            vy: Math.sin(angle_rad) * speed,
            gravity: -0.05,
            x: @cx.to_f,
            y: @cy_end.to_f,
            opacity: 255,
            life: 35
          }
        end

        # Spawn dos itens arremessados
        item_count = @items.length
        @items.each_with_index do |item_id, i|
          it_sp = Sprite.new(@viewport)
          it_sp.bitmap = GiftBoxSystem.load_item_icon(item_id, @box_color) rescue nil
          if it_sp.bitmap
            it_sp.ox = it_sp.bitmap.width / 2
            it_sp.oy = it_sp.bitmap.height / 2
          end
          it_sp.x = @cx
          it_sp.y = @cy_end
          it_sp.z = 99990 + i
          it_sp.zoom_x = 0.25
          it_sp.zoom_y = 0.25

          if item_count == 1
            angle_deg = 270.0
          elsif item_count == 2
            angle_deg = (i == 0) ? 245.0 : 295.0
          else
            angle_deg = 220.0 + (100.0 / (item_count - 1).to_f) * i
          end

          angle_rad = angle_deg * Math::PI / 180.0
          speed = 3.5 + rand * 1.5

          @item_sprites << {
            sprite: it_sp,
            vx: Math.cos(angle_rad) * speed,
            vy: Math.sin(angle_rad) * speed - 1.0,
            gravity: 0.18,
            x: @cx.to_f,
            y: @cy_end.to_f,
            frame: 0,
            landed: false,
            ground_y: @ground_y_base - 10 + rand(16),
            hold_frame: 0,
            opacity: 255
          }
        end
      end

    elsif @box_state == :release
      if @box_sprite
        @box_sprite.y = @cy_end
        @box_sprite.zoom_x = @base_scale
        @box_sprite.zoom_y = @base_scale
      end
      @box_phase_frame += 1
      if @box_phase_frame >= @release_hold_duration
        @box_state = :fade
        @box_phase_frame = 0
      end

    elsif @box_state == :fade
      if @box_sprite
        @box_sprite.y = @cy_end
        @box_sprite.zoom_x = @base_scale
        @box_sprite.zoom_y = @base_scale
        t = @box_phase_frame.to_f / @fade_duration.to_f
        @box_sprite.opacity = [255 - (t * 255).to_i, 0].max
      end
      @box_phase_frame += 1
      if @box_phase_frame >= @fade_duration
        @box_sprite.dispose rescue nil if @box_sprite
        @box_sprite = nil
        @box_state = :done
      end
    end

    # Efeito de sacudir
    if @box_state != :done && @box_sprite && !@box_sprite.disposed?
      @box_sprite.angle = Math.sin(@frame * 0.45) * 12
      @box_sprite.x = @cx + (Math.sin(@frame * 0.8) * 3).to_i
    end

    @frame += 1

    # Atualiza as partículas
    @particles.each do |p|
      next if p[:life] <= 0 || !p[:sprite] || p[:sprite].disposed?
      p[:life] -= 1
      p[:vy] += p[:gravity]
      p[:vx] *= 0.95
      p[:x] += p[:vx]
      p[:y] += p[:vy]
      p[:sprite].x = p[:x].to_i
      p[:sprite].y = p[:y].to_i
      p[:opacity] = (p[:life].to_f / 35.0 * 255.0).to_i
      p[:sprite].opacity = p[:opacity]
      if p[:life] <= 0
        p[:sprite].bitmap.dispose rescue nil
        p[:sprite].dispose rescue nil
      end
    end

    # Atualiza os itens
    @item_sprites.each do |data|
      sp = data[:sprite]
      next if !sp || sp.disposed?
      if !data[:landed]
        data[:frame] += 1
        data[:vy] += data[:gravity]
        data[:x] += data[:vx]
        data[:y] += data[:vy]
        # Segue o player horizontalmente
        data[:x] = [[data[:x], @cx + 96].min, @cx - 96].max
        sp.x = data[:x].to_i
        sp.y = data[:y].to_i

        progress = [data[:frame] / 15.0, 1.0].min
        scale = 0.25 + 0.45 * progress
        sp.zoom_x = scale
        sp.zoom_y = scale
        sp.angle = (sp.angle + 12) % 360

        if data[:y] >= data[:ground_y] && data[:vy] > 0 && data[:frame] > 8
          data[:landed] = true
          sp.angle = 0
          sp.zoom_x = 0.7
          sp.zoom_y = 0.7
          sp.y = data[:ground_y].to_i
        end
      else
        if data[:hold_frame] < 30
          data[:hold_frame] += 1
        else
          data[:opacity] = [data[:opacity] - 16, 0].max
          sp.opacity = data[:opacity]
          if data[:opacity] <= 0
            sp.bitmap.dispose rescue nil
            sp.dispose rescue nil
          end
        end
      end
    end

    # Condição de parada
    all_done = (@box_state == :done) && 
               @particles.all? { |p| p[:life] <= 0 } &&
               @item_sprites.all? { |data| data[:sprite].disposed? rescue true }

    if all_done
      dispose
    end
  end

  def dispose
    return if @disposed
    @disposed = true
    @box_sprite.dispose rescue nil if @box_sprite
    @particles.each do |p|
      p[:sprite].bitmap.dispose rescue nil if p[:sprite]
      p[:sprite].dispose rescue nil if p[:sprite]
    end
    @item_sprites.each do |data|
      data[:sprite].bitmap.dispose rescue nil if data[:sprite]
      data[:sprite].dispose rescue nil if data[:sprite]
    end
  end
end

# Scene_Map hooks removidos - animações agora gerenciadas de forma unificada no AnilLanRework


module AnilLanRework
  module Router
    class << self
      alias anil_gift_box_route_packet route_packet unless method_defined?(:anil_gift_box_route_packet)
      
      def route_packet(packet)
        if packet["type"] == "gift_box_open_broadcast"
          GiftBoxSystem.on_receive_gift_box_open(packet) rescue nil
          return
        end
        anil_gift_box_route_packet(packet)
      end
    end
  end
end





#===============================================================================
# O save que fecha a janela de duplicacao.
#
# Corre no frame SEGUINTE ao da abertura, quando o Essentials ja consumiu a
# caixa. Um booleano por frame — custo nenhum.
#===============================================================================
if defined?(Scene_Map)
  class Scene_Map
    unless method_defined?(:anil_giftbox_orig_update)
      alias_method :anil_giftbox_orig_update, :update

      def update(*args)
        anil_giftbox_orig_update(*args)
        GiftBoxSystem.escoar_save_pendente! if defined?(GiftBoxSystem)
      end
    end
  end
end


#===============================================================================
# O USO DA CAIXA PASSA POR AQUI
#===============================================================================
# ⚠️ Substitui o pbUseKeyItemInField SO para as Gift Boxes.
#
# O caminho normal e: handler devolve true -> Essentials remove o item. Isso
# obriga a gravar depois de tudo, porque gravar antes registaria a caixa ainda
# na mochila (o bug da duplicacao). Assumindo o consumo aqui, a ordem inverte-se
# e o save acontece com o estado ja final.
#
# Os outros itens seguem inalterados pelo caminho original.
#===============================================================================
if defined?(pbUseKeyItemInField)
  alias anil_giftbox_orig_pbUseKeyItemInField pbUseKeyItemInField unless defined?(anil_giftbox_orig_pbUseKeyItemInField)

  def pbUseKeyItemInField(item)
    if defined?(GiftBoxSystem) && GiftBoxSystem.caixa?(item)
      return GiftBoxSystem.usar_caixa(item)
    end
    anil_giftbox_orig_pbUseKeyItemInField(item)
  end
end
