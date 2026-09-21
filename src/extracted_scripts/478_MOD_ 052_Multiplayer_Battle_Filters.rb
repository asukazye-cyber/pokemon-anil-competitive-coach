#===============================================================================
# * Modular Multiplayer - Filtro Visual de Batalha (Clima + Hora do Dia)
#===============================================================================
# Aplica o mesmo tom/filtro do overworld (baseado em clima e hora do dia) 
# sobre a arena de batalha, para que as batalhas reflitam visualmente as
# condições do mapa onde o jogador se encontra.
#
# Também adiciona overlays atmosféricos de névoa animada durante climas
# ativos (neve, nevasca, chuva, tempestade, nublado) para dar profundidade
# e imersão à cena de batalha. Usa sequência de frames extraída de vídeo.
#===============================================================================

module AnilLanRework
  # Número total de frames da animação de fog
  BATTLE_FOG_FRAME_COUNT = 24
  # Velocidade da animação (frames do jogo por frame de fog)
  # Menor = mais rápido. 4 = troca frame a cada 4 game frames (~6fps)
  BATTLE_FOG_ANIM_SPEED = 4
  
  # Calcula o tom de filtro que deve ser aplicado na cena de batalha
  # baseado na hora do dia e no clima ativo do overworld.
  def self.get_battle_filter_tone
    # Só aplica em mapas outdoor
    return Tone.new(0, 0, 0, 0) if !$game_map || !$game_map.metadata || !$game_map.metadata.outdoor_map
    
    # --- Tom base: Hora do dia ---
    base_tone = Tone.new(0, 0, 0, 0)
    if defined?(Settings::TIME_SHADING) && Settings::TIME_SHADING && defined?(PBDayNight)
      base_tone = PBDayNight.getTone rescue Tone.new(0, 0, 0, 0)
    end
    
    is_night = (defined?(PBDayNight) && PBDayNight.isNight?) rescue false
    
    # --- Offsets de clima ---
    weather_offset_red = 0
    weather_offset_green = 0
    weather_offset_blue = 0
    
    if $game_screen
      case $game_screen.weather_type
      when :Rain
        weather_offset_red = -15
        weather_offset_green = -15
        weather_offset_blue = -12
      when :Storm
        weather_offset_red = -25
        weather_offset_green = -25
        weather_offset_blue = -20
      when :Snow, :Blizzard
        weather_offset_red = -15
        weather_offset_green = -15
        weather_offset_blue = -5
      when :Sandstorm
        weather_offset_red = -10
        weather_offset_green = -25
        weather_offset_blue = -30
      when :Fog
        weather_offset_red = -30
        weather_offset_green = -30
        weather_offset_blue = -30
      end
      
      # À noite com chuva/tempestade: tom acinzentado (consistente com o overworld)
      if is_night && [:Rain, :Storm].include?($game_screen.weather_type)
        gray_base = Tone.new(-60, -60, -30, 50)
        weather_offset_red   = (weather_offset_red * 0.3).round
        weather_offset_green = (weather_offset_green * 0.3).round
        weather_offset_blue  = (weather_offset_blue * 0.3).round
        
        return Tone.new(
          (gray_base.red + weather_offset_red).clamp(-255, 255),
          (gray_base.green + weather_offset_green).clamp(-255, 255),
          (gray_base.blue + weather_offset_blue).clamp(-255, 255),
          gray_base.gray
        )
      end
    end
    
    # Moonlight
    is_moonlight = ($forced_weather == :Moonlight || (defined?(AnilLanRework) && $game_map && $game_map.map_id != 0 && AnilLanRework.get_weather_for_map($game_map.map_id) == :Moonlight))
    if is_moonlight
      return Tone.new(-75, -75, -15, 60)
    end
    
    # Tom composto: base (hora do dia) + offsets de clima
    return Tone.new(
      (base_tone.red + weather_offset_red).clamp(-255, 255),
      (base_tone.green + weather_offset_green).clamp(-255, 255),
      (base_tone.blue + weather_offset_blue).clamp(-255, 255),
      base_tone.gray
    )
  end
  
  # Retorna as configurações de overlay de névoa para o clima atual
  def self.get_battle_fog_config
    return nil if !$game_map || !$game_map.metadata || !$game_map.metadata.outdoor_map
    return nil if !$game_screen
    
    case $game_screen.weather_type
    when :Snow
      {
        opacity_front: 55,            # Camada frontal (perto do jogador)
        opacity_back: 35,             # Camada traseira (perto do oponente)
        anim_speed: 4,                # Velocidade da animação (game frames por fog frame)
        tone: Tone.new(20, 20, 30, 0) # Tom levemente azulado/gelado
      }
    when :Blizzard
      {
        opacity_front: 100,           # Nevasca = fog bem denso
        opacity_back: 70,
        anim_speed: 2,                # Animação mais rápida (vento forte)
        tone: Tone.new(30, 30, 40, 0) # Mais branco/gelado
      }
    when :Rain
      {
        opacity_front: 30,            # Chuva leve - névoa sutil
        opacity_back: 18,
        anim_speed: 4,
        tone: Tone.new(-10, -10, 0, 0)
      }
    when :Storm
      {
        opacity_front: 60,            # Tempestade = fog moderado-forte
        opacity_back: 40,
        anim_speed: 3,                # Animação rápida
        tone: Tone.new(-20, -20, -10, 0)
      }
    when :Fog
      {
        opacity_front: 65,            # Nublado = bastante névoa
        opacity_back: 45,
        anim_speed: 6,                # Animação bem lenta (neblina parada)
        tone: Tone.new(-15, -15, -15, 0)
      }
    when :Sandstorm
      {
        opacity_front: 50,
        opacity_back: 30,
        anim_speed: 3,
        tone: Tone.new(15, 5, -20, 0) # Tom amarelado/arenoso
      }
    else
      nil
    end
  end
  
  # Pré-carrega todos os frames de fog em um array de bitmaps
  def self.load_battle_fog_frames
    frames = []
    BATTLE_FOG_FRAME_COUNT.times do |i|
      path = sprintf("Graphics/Fogs/BattleFog/fog_%03d", i)
      begin
        bmp = RPG::Cache.load_bitmap("", path)
        frames << bmp if bmp && !bmp.disposed?
      rescue
        # Se não encontrar o frame, para de carregar
        break
      end
    end
    frames
  end
end

#===============================================================================
# * Override da Cena de Batalha para Aplicar Filtro Visual + Fog Animado
#===============================================================================
class Battle::Scene
  #-----------------------------------------------------------------------------
  # Após criar os sprites de backdrop, aplica o tom e cria fog animado
  #-----------------------------------------------------------------------------
  if !method_defined?(:anil_battle_filter_orig_pbCreateBackdropSprites)
    alias anil_battle_filter_orig_pbCreateBackdropSprites pbCreateBackdropSprites
  end

  def pbCreateBackdropSprites
    anil_battle_filter_orig_pbCreateBackdropSprites
    
    # === FILTRO DE TOM (HORA + CLIMA) ===
    filter_tone = AnilLanRework.get_battle_filter_tone rescue Tone.new(0, 0, 0, 0)
    
    factor = 0.8
    battle_tone = Tone.new(
      (filter_tone.red * factor).round,
      (filter_tone.green * factor).round,
      (filter_tone.blue * factor).round,
      (filter_tone.gray * factor).round
    )
    
    if @sprites
      ["battle_bg", "battle_bg2", "battle_base_0", "battle_base_1"].each do |key|
        sprite = @sprites[key]
        if sprite && !sprite.disposed?
          sprite.tone = battle_tone
        end
      end
    end
    
    @battle_filter_tone = battle_tone
    
    # === OVERLAYS DE NÉVOA ANIMADA ===
    create_battle_fog_overlays
  end

  #-----------------------------------------------------------------------------
  # Cria as duas camadas de névoa animada (frames do vídeo convertido)
  #-----------------------------------------------------------------------------
  def create_battle_fog_overlays
    dispose_battle_fog_overlays
    
    fog_config = AnilLanRework.get_battle_fog_config rescue nil
    return if !fog_config
    
    # Carrega os frames da animação
    @battle_fog_frames = AnilLanRework.load_battle_fog_frames rescue []
    return if @battle_fog_frames.empty?
    
    @battle_fog_config = fog_config
    @battle_fog_anim_index = 0          # Frame atual da animação
    @battle_fog_anim_counter = 0        # Contador de game frames
    @battle_fog_fade_in = 0             # Progresso do fade-in
    
    screen_w = Graphics.width   # 512
    screen_h = Graphics.height  # 384
    
    fog_w = @battle_fog_frames[0].width   # 512
    fog_h = @battle_fog_frames[0].height  # 192
    
    @battle_fog_sprites = []
    
    # --- Camada Traseira (perto do oponente, metade superior) ---
    back_sprite = Sprite.new(@viewport)
    back_sprite.bitmap = @battle_fog_frames[0]
    back_sprite.blend_type = 1              # Aditivo: preto = transparente
    back_sprite.opacity = 0                 # Começa invisível (fade-in)
    back_sprite.z = 15                      # Acima do backdrop, abaixo dos pokémon
    back_sprite.x = 0
    back_sprite.y = 10                      # Topo da tela (perto do oponente)
    back_sprite.zoom_x = screen_w.to_f / fog_w
    back_sprite.zoom_y = 0.7               # Um pouco menor (perspectiva de distância)
    back_sprite.tone = fog_config[:tone]
    back_sprite.mirror = true               # Espelhado para variar visualmente
    @battle_fog_sprites << back_sprite
    
    # --- Camada Frontal (perto do jogador, metade inferior) ---
    front_sprite = Sprite.new(@viewport)
    front_sprite.bitmap = @battle_fog_frames[0]
    front_sprite.blend_type = 1
    front_sprite.opacity = 0
    front_sprite.z = 50                     # Acima das bases, abaixo da UI
    front_sprite.x = 0
    front_sprite.y = screen_h - fog_h + 10  # Parte inferior (perto do jogador)
    front_sprite.zoom_x = screen_w.to_f / fog_w
    front_sprite.zoom_y = 1.0               # Tamanho completo (mais perto = maior)
    front_sprite.tone = fog_config[:tone]
    @battle_fog_sprites << front_sprite
    
    @battle_fog_target_opacities = [
      fog_config[:opacity_back],
      fog_config[:opacity_front]
    ]
  end
  
  #-----------------------------------------------------------------------------
  # Remove os overlays de névoa
  #-----------------------------------------------------------------------------
  def dispose_battle_fog_overlays
    if @battle_fog_sprites
      @battle_fog_sprites.each do |sprite|
        sprite.dispose if sprite && !sprite.disposed?
      end
    end
    @battle_fog_sprites = nil
    @battle_fog_frames = nil
    @battle_fog_config = nil
  end

  #-----------------------------------------------------------------------------
  # Atualiza tom + fog animado a cada frame
  #-----------------------------------------------------------------------------
  if !method_defined?(:anil_battle_filter_orig_pbUpdate)
    alias anil_battle_filter_orig_pbUpdate pbUpdate
  end

  def pbUpdate(cw = nil)
    anil_battle_filter_orig_pbUpdate(cw)
    
    # Atualizar fog animado
    update_battle_fog_overlays
  end
  
  #-----------------------------------------------------------------------------
  # Atualiza animação dos frames de névoa e opacidade
  #-----------------------------------------------------------------------------
  def update_battle_fog_overlays
    return if !@battle_fog_sprites || @battle_fog_sprites.empty?
    return if !@battle_fog_frames || @battle_fog_frames.empty?
    return if !@battle_fog_config
    
    config = @battle_fog_config
    anim_speed = config[:anim_speed] || AnilLanRework::BATTLE_FOG_ANIM_SPEED
    
    # --- Fade-in suave (60 frames = ~1.5 segundos) ---
    if @battle_fog_fade_in && @battle_fog_fade_in < 60
      @battle_fog_fade_in += 1
      progress = @battle_fog_fade_in / 60.0
      @battle_fog_sprites.each_with_index do |sprite, i|
        next if !sprite || sprite.disposed?
        target = @battle_fog_target_opacities[i] || 0
        sprite.opacity = (target * progress).round
      end
      if @battle_fog_fade_in >= 60
        @battle_fog_fade_in = nil
      end
    end
    
    # --- Avança a animação ---
    @battle_fog_anim_counter += 1
    if @battle_fog_anim_counter >= anim_speed
      @battle_fog_anim_counter = 0
      @battle_fog_anim_index = (@battle_fog_anim_index + 1) % @battle_fog_frames.length
      
      new_bitmap = @battle_fog_frames[@battle_fog_anim_index]
      if new_bitmap && !new_bitmap.disposed?
        @battle_fog_sprites.each do |sprite|
          next if !sprite || sprite.disposed?
          sprite.bitmap = new_bitmap
        end
      end
      
      # --- A camada traseira (oponente) usa frame defasado para parecer diferente (atualiza apenas quando o frame muda) ---
      if @battle_fog_sprites[0] && !@battle_fog_sprites[0].disposed? && @battle_fog_frames.length > 6
        back_index = (@battle_fog_anim_index + (@battle_fog_frames.length / 2)) % @battle_fog_frames.length
        back_bitmap = @battle_fog_frames[back_index]
        if back_bitmap && !back_bitmap.disposed?
          @battle_fog_sprites[0].bitmap = back_bitmap
        end
      end
    end
  end

  #-----------------------------------------------------------------------------
  # Dispose: limpa fog ao encerrar a batalha
  #-----------------------------------------------------------------------------
  if !method_defined?(:anil_battle_filter_orig_pbEndBattle)
    alias anil_battle_filter_orig_pbEndBattle pbEndBattle
  end

  def pbEndBattle(result)
    dispose_battle_fog_overlays
    anil_battle_filter_orig_pbEndBattle(result)
  end
end

AnilLanRework.log("AnilLanRework_BattleFilters (Filtros + Fog Animado de Batalha) carregado com SUCESSO!") rescue nil
