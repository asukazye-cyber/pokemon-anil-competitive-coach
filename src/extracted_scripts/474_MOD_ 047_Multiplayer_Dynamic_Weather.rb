#===============================================================================
# * Modular Multiplayer - Sistema de Clima Dinâmico e Determinístico
#===============================================================================
# Este script gerencia a geração de climas no overworld de forma determinística
# e sincronizada entre os jogadores cooperativos, baseado no horário em tempo real
# e perfis geográficos específicos para cada rota ou mapa externo.
#===============================================================================

module AnilLanRework
  class << self
    attr_accessor :server_time_offset

    def server_time
      if defined?(@server_time_offset) && @server_time_offset
        Time.at(Time.now.to_i + @server_time_offset).getlocal("-03:00")
      else
        Time.now.getlocal("-03:00")
      end
    end
  end

  # Duração de cada bloco de clima em horas (ex: a cada 3 horas o clima pode mudar)
  WEATHER_BLOCK_DURATION = 3

  # ---------------------------------------------------------------------------
  # MAPAS FRIOS — lista explicita, nao adivinhacao pelo nome.
  #
  # A deteccao antiga procurava "neve", "snow", "gelo", "glaciar" e "ice" no nome
  # do mapa. Os nomes deste jogo estao em ESPANHOL ("Monte Plateado", "Ciudad
  # Añil", "Ruta 25"), portanto nenhuma dessas palavras casava e as areas de neve
  # caiam no perfil GERAL — que sorteia chuva (15%), sol (10%) e tempestade (5%).
  # Dava chuva com relampagos no cume nevado. O mapa 174 ja estava fixado a mao
  # pelo mesmo motivo: era um remendo para um caso do problema, nao a correcao.
  #
  # A lista saiu do BattleBack declarado em PBS/map_metadata.txt, que e a
  # evidencia de cenario mais fiavel que existe no projeto:
  #
  #   [163] Monte Plateado   BattleBack = Snow
  #   [165] Monte Plateado   BattleBack = CimaNevada
  #   [166] Ruta 25 (Norte)  BattleBack = Snow
  #   [167] Ciudad Añil      BattleBack = Snow
  #   [174] Bosque Celeste   BattleBack = BosqueLila  <- NAO e cenario de neve,
  #         mas ja estava marcado como frio antes desta correcao; mantido para
  #         nao mudar o que ninguem pediu. Tirar daqui devolve-o ao perfil geral.
  #
  # FORA de proposito:
  #   [161] Monte Plateado   BattleBack = Monte     (a parte baixa nao e nevada)
  #   [133-136] Islas Espuma, [198] Cueva Glaciada  (sao interiores: o clima so
  #         corre em mapas outdoor, e neve dentro de gruta nao faria sentido)
  # ── QUANTIDADE DE FLOCOS ──────────────────────────────────────────────────
  #
  # Toda a gente levava potencia 9, e o Game_Screen#weather faz
  #   @weather_max = (power + 1) * RPG::Weather::MAX_SPRITES / 10
  # ou seja (9+1)*60/10 = 60 particulas, o MAXIMO, tanto para neve fraca como
  # para nevasca. Era por isso que as duas eram indistinguiveis.
  #
  # ⚠️ A conta so da multiplos de 6 com potencia inteira (cada passo vale 6
  # particulas). Por isso 30% exactos nao existem aqui: 18 -> 24 sao +33%, e
  # 24 -> 30 seriam +25%. Ficou o 18/24, que e o mais perto dos 30% pedidos E
  # deixa a neve fraca mesmo fraca. Para mudar, mexer so nestes dois numeros.
  POTENCIA_NEVE    = 2   # (2+1)*60/10 = 18 flocos
  POTENCIA_NEVASCA = 3   # (3+1)*60/10 = 24 flocos  (+33% sobre a neve)
  POTENCIA_PADRAO  = 9   # 60 — o resto do clima fica como sempre esteve

  def self.potencia_do_clima(tipo)
    case tipo
    when :Snow     then POTENCIA_NEVE
    when :Blizzard then POTENCIA_NEVASCA
    else                POTENCIA_PADRAO
    end
  end

  MAPAS_FRIOS = [163, 165, 166, 167, 174].freeze

  # Rede para mapas novos, agora com as palavras que os nomes deste jogo usam de
  # facto. Continua a ser um palpite — para garantir, acrescente o ID acima.
  PALAVRAS_FRIAS = [
    "nieve", "nevad", "hielo", "helad", "glaciar", "polar", "invierno",  # espanhol
    "neve", "gelo", "gelad",                                            # portugues
    "snow", "ice", "frost", "glacier"                                   # ingles
  ].freeze

  def self.mapa_frio?(map_id, map_name)
    return true if MAPAS_FRIOS.include?(map_id.to_i)
    nome = map_name.to_s.downcase
    PALAVRAS_FRIAS.any? { |p| nome.include?(p) }
  rescue
    false
  end
  # ---------------------------------------------------------------------------

  # Cache temporal por segundo para evitar picos de FPS no overworld
  @cached_weather ||= {}
  @cached_time ||= nil

  # Retorna o clima determinístico sincronizado para um determinado mapa
  def self.get_weather_for_map(map_id)
    return $forced_weather if $forced_weather
    return :None if !map_id || map_id == 0

    now = (self.respond_to?(:server_time) ? self.server_time : Time.now).to_i
    if @cached_time == now && @cached_weather.has_key?(map_id)
      return @cached_weather[map_id]
    end

    res = self.calculate_weather_for_map(map_id)
    @cached_weather[map_id] = res
    @cached_time = now
    return res
  end

  def self.calculate_weather_for_map(map_id)
    # 1. Verifica se o mapa é externo (outdoor). Se não for, não há clima.
    map_metadata = GameData::MapMetadata.try_get(map_id)
    return :None if !map_metadata || !map_metadata.outdoor_map
    
    # 2. Calcula a semente determinística baseada na data, hora (bloco) e ID do mapa
    time = self.respond_to?(:server_time) ? self.server_time : Time.now
    weather_block = time.hour / WEATHER_BLOCK_DURATION
    seed = (time.year * 10000) + (time.month * 100) + time.day + weather_block + map_id
    
    rng = Random.new(seed)
    roll = rng.rand(100)
    
    # 3. Detecta perfil climático pelo nome do mapa
    map_name = pbGetMapNameFromId(map_id).to_s.downcase

    # Perfis de clima personalizados por região:
    if AnilLanRework.mapa_frio?(map_id, map_name)
      # --- Perfil Frio (Rotas Geladas / Glaciares) ---
      if roll < 35      # 35% chance: Tempo Limpo
        return :None
      elsif roll < 60   # 25% chance: Nublado
        return :Cloudy
      elsif roll < 85   # 25% chance: Neve
        return :Snow
      else              # 15% chance: Nevasca
        return :Blizzard
      end
      
    elsif map_name.include?("deserto") || map_name.include?("desert") || map_name.include?("areia") || map_name.include?("sand") || map_name.include?("ruina")
      # --- Perfil Desértico (Áreas Quentes / Secas) ---
      if roll < 40      # 40% chance: Tempo Limpo
        return :None
      elsif roll < 70   # 30% chance: Sol Forte
        return :Sun
      else              # 30% chance: Tempestade de Areia
        return :Sandstorm
      end
      
    else
      # --- Perfil Externo Geral (Rotas, Cidades e Bosques Padrão) ---
      if roll < 55      # 55% chance: Tempo Limpo
        return :None
      elsif roll < 70   # 15% chance: Nublado
        return :Cloudy
      elsif roll < 80   # 10% chance: Sol Forte
        return :Sun
      elsif roll < 95   # 15% chance: Chuva Comum
        return :Rain
      else              # 5% chance: Tempestade de Raios
        return :Storm
      end
    end
  end
end

#===============================================================================
# * Injeção de Segurança e Persistência Direta na Engine
#===============================================================================
class Game_Screen
  if !method_defined?(:anil_weather_orig_update)
    alias anil_weather_orig_update update
  end

  def update
    anil_weather_orig_update

    # Ignora atualizações automáticas se estiver em batalha
    return if $game_temp && $game_temp.in_battle

    # Garante a sincronia de clima determinístico em tempo real
    if $game_map && $game_map.map_id && $game_map.map_id != 0
      map_metadata = GameData::MapMetadata.try_get($game_map.map_id)
      # O clima APENAS roda em mapas externos (outdoor_map == true). Mapas internos (casas/cavernas) são sempre limpos!
      if map_metadata && map_metadata.outdoor_map
        expected = AnilLanRework.get_weather_for_map($game_map.map_id)
        target_weather = (expected == :Moonlight) ? :None : expected
        if @weather_type != target_weather
          # Aplica a mudança de forma suave (60 frames = ~1.5 segundos)
          # ⚠️ A potencia tambem alimenta o tone_proc (o `strength`), portanto
          # menos flocos = ecra menos lavado de cinzento. E o efeito desejado:
          # com o veu fora, o cinzento por cima era o que restava do "filtro".
          # ⚠️ QUALIFICADO. Este bloco corre dentro de `class Game_Screen`, nao
          # dentro do module — sem o prefixo era NoMethodError em todo o mapa
          # exterior, e o clima deixava de mudar.
          weather(target_weather, AnilLanRework.potencia_do_clima(target_weather), 60)
        end

        # --- Sincronização e Reprodução Suave do Som de Fundo (BGS - Altíssima Compatibilidade OGG) ---
        expected_bgs = case expected
                       when :Rain then "Rain"
                       when :Storm then "Storm"
                       when :Sandstorm then "Sandstorm"
                       when :Snow, :Blizzard then "Wind"
                       else nil
                       end
                       
        if expected_bgs
          playing_bgs = $game_system.playing_bgs
          if !playing_bgs || playing_bgs.name != expected_bgs
            # Define volumes personalizados e super confortáveis (metade do volume padrão)
            volume = case expected
                     when :Rain then 30
                     when :Storm then 35
                     when :Sandstorm then 25
                     when :Snow, :Blizzard then 25
                     else 50
                     end
            pbBGSPlay(expected_bgs, volume, 100) rescue nil
          end
        else
          # Para o som do clima se o clima acabou
          playing_bgs = $game_system.playing_bgs
          if playing_bgs && ["Rain", "Storm", "Sandstorm", "Wind"].include?(playing_bgs.name)
            pbBGSStop(1.0) rescue nil
          end
        end
      else
        # Se for mapa interno (casa/caverna), força a remoção imediata do clima e BGS
        if @weather_type != :None
          weather(:None, 0, 0)
        end
        playing_bgs = $game_system.playing_bgs
        if playing_bgs && ["Rain", "Storm", "Sandstorm", "Wind"].include?(playing_bgs.name)
          pbBGSStop(0.5) rescue nil
        end
      end
    end
  end
end

#===============================================================================
# * Injeção de Efeito de Som de Trovão e Flash Otimizado na Renderização de Clima
#===============================================================================
module RPG
  class Weather
    if !method_defined?(:anil_weather_orig_update)
      alias anil_weather_orig_update update
    end
    if !method_defined?(:anil_weather_orig_dispose)
      alias anil_weather_orig_dispose dispose
    end
    if !method_defined?(:anil_cloudy_update_tile_position)
      alias anil_cloudy_update_tile_position update_tile_position
    end
    if !method_defined?(:anil_weather_orig_update_screen_tone)
      alias anil_weather_orig_update_screen_tone update_screen_tone
    end

    def update_screen_tone
      metadata = $game_map ? GameData::MapMetadata.try_get($game_map.map_id) : nil
      if metadata && !metadata.outdoor_map
        @viewport.tone.set(0, 0, 0, 0)
      else
        anil_weather_orig_update_screen_tone
      end
    end

    def update_tile_position(sprite, index)
      # ⚠️ AS PARTICULAS DE NEVOEIRO DO MOTOR CALAM-SE SEMPRE (MOD 170).
      #
      # Isto era so para mapas exteriores, e existia porque :Fog fazia de conta
      # que era "nublado" — escondiam-se as tiles e ficava so o tom cinzento.
      # Agora o nublado e um clima proprio (:Cloudy) e a neblina e desenhada
      # pelo MOD 170, num veu unico. Deixar estas tiles ligadas dava DUAS
      # neblinas sobrepostas, que foi exactamente a queixa de 30/08.
      if (@type == :Fog || @target_type == :Fog)
        if sprite
          sprite.visible = false
          sprite.opacity = 0
        end
        return
      end
      anil_cloudy_update_tile_position(sprite, index)
    end

    def update
      # Se for tempestade e não estiver dando fade, nós controlamos os trovões e os flashes!
      if @type == :Storm && !@fading
        # Controlamos o timer de raio nós mesmos!
        @time_until_flash = 999 if !@time_until_flash || @time_until_flash <= 0
        @custom_time_until_flash ||= rand(6..18)

        @custom_time_until_flash -= 1.0 / Graphics.frame_rate
        if @custom_time_until_flash <= 0
          # Toca o som de trovão original do mod (agora super leve e comprimido sem lag!)
          thunders = ["PRSFX- Thunder1", "PRSFX- Thunder2", "PRSFX- Thunder3", "PRSFX- Thunder4"]
          pbSEPlay(thunders.sample, 65, 100) rescue nil

          # Dispara o flash azul claro com opacidade de 10!
          if @viewport && !(pbDisposed?(@viewport) rescue true)
            @viewport.flash(Color.new(135, 206, 250, 10), rand(15..30))
          end

          # Próximo trovão em 6 a 18 segundos
          @custom_time_until_flash = rand(6..18)
        end

        # Mantém a variável nativa sempre positiva para bloquear o flash unoptimized nativo
        @time_until_flash = 10.0
      else
        # Limpa o tint do viewport se não estiver mais em tempestade
        if @viewport && !(pbDisposed?(@viewport) rescue true)
          @viewport.color.set(0, 0, 0, 0)
        end
      end
      
      anil_weather_orig_update
    end

    def dispose
      if @viewport && !(pbDisposed?(@viewport) rescue true)
        @viewport.color.set(0, 0, 0, 0)
      end
      anil_weather_orig_dispose
    end
  end
end

#===============================================================================
# * Limpeza de Hooks Antigos para evitar redundâncias
#===============================================================================
if defined?(EventHandlers)
  begin
    EventHandlers.remove(:on_enter_map, :set_weather)
  rescue => e
    AnilLanRework.log("DynamicWeather: Erro ao remover manipulador nativo: #{e.message}") rescue nil
  end
end

#===============================================================================
# * Força a Ativação do Ciclo Dia/Noite Nativo (Time Shading)
#===============================================================================
Settings::TIME_SHADING = true if defined?(Settings)

#===============================================================================
# * Sobrescrita de pbDayNightTint com Escurecimento Atmosférico ao Chover
#===============================================================================
$current_pbDayNightTint_frame = nil
$current_pbDayNightTint_tone = nil

def pbDayNightTint(object)
  return if !$scene.is_a?(Scene_Map)
  
  # Se já calculamos o tom para este frame, aplica diretamente!
  current_frame = Graphics.frame_count rescue nil
  if current_frame && $current_pbDayNightTint_frame == current_frame && $current_pbDayNightTint_tone
    object.tone.set(
      $current_pbDayNightTint_tone.red,
      $current_pbDayNightTint_tone.green,
      $current_pbDayNightTint_tone.blue,
      $current_pbDayNightTint_tone.gray
    )
    return
  end

  calculated_tone = Tone.new(0, 0, 0, 0)
  
  if $game_map && $game_map.metadata && $game_map.metadata.outdoor_map
    # Se for noite de luar (Moonlight), usa um tom prateado azulado super místico!
    is_moonlight = ($forced_weather == :Moonlight || (defined?(AnilLanRework) && $game_map && $game_map.map_id != 0 && AnilLanRework.get_weather_for_map($game_map.map_id) == :Moonlight))
    if is_moonlight
      calculated_tone.set(-75, -75, -15, 60)
    else
      # Pega o tom de cor correspondente ao ciclo de Dia/Noite nativo
      tone = Settings::TIME_SHADING ? PBDayNight.getTone : Tone.new(0, 0, 0)
      
      # Detecta se é noite para aplicar tratamento especial
      is_night = (defined?(PBDayNight) && PBDayNight.isNight?) rescue false
      
      # Define o escurecimento conforme o clima ativo
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
        when :Cloudy # Céu encoberto: cinzento suave, e as sombras de nuvem por cima
          weather_offset_red = -30
          weather_offset_green = -30
          weather_offset_blue = -30
        when :Fog # Neblina rasteira: escurece MENOS, porque o véu já a esbate
          weather_offset_red = -14
          weather_offset_green = -14
          weather_offset_blue = -14
        end
        
        # À noite com chuva/tempestade: tom acinzentado ao invés do azulado da lua
        # Reduz os offsets de clima (já está escuro) e neutraliza o azul da noite
        if is_night && [:Rain, :Storm].include?($game_screen.weather_type)
          # Substitui o tom base da noite por um tom acinzentado (como luar, mas cinza)
          # Noite normal: (-70, -90, 15, 55) → muito azulada
          # Noite chuvosa: (-45, -45, -20, 45) → mais clara, tipo luar, mas menos azul
          gray_base = Tone.new(-45, -45, -20, 45)
          # Reduz offsets de clima à noite (já está escuro o bastante)
          weather_offset_red   = (weather_offset_red * 0.3).round
          weather_offset_green = (weather_offset_green * 0.3).round
          weather_offset_blue  = (weather_offset_blue * 0.3).round
          
          calculated_tone.set(
            (gray_base.red + weather_offset_red).clamp(-255, 255),
            (gray_base.green + weather_offset_green).clamp(-255, 255),
            (gray_base.blue + weather_offset_blue).clamp(-255, 255),
            gray_base.gray
          )
        else
          calculated_tone.set(
            (tone.red + weather_offset_red).clamp(-255, 255),
            (tone.green + weather_offset_green).clamp(-255, 255),
            (tone.blue + weather_offset_blue).clamp(-255, 255),
            tone.gray
          )
        end
      else
        calculated_tone.set(
          tone.red.clamp(-255, 255),
          tone.green.clamp(-255, 255),
          tone.blue.clamp(-255, 255),
          tone.gray
        )
      end
    end
  else
    # Mapas internos (casas, cavernas, ginásios) ficam sempre com a iluminação neutra e clara!
    calculated_tone.set(0, 0, 0, 0)
  end

  # Salva no cache do frame
  if current_frame
    $current_pbDayNightTint_frame = current_frame
    $current_pbDayNightTint_tone = calculated_tone
  end

  object.tone.set(
    calculated_tone.red,
    calculated_tone.green,
    calculated_tone.blue,
    calculated_tone.gray
  )
end

#===============================================================================
# * Efeito Atmosférico de Sombras de Nuvens Passando no Overworld
#===============================================================================
class CloudShadow
  attr_reader :id, :map_x, :map_y, :speed_x, :speed_y, :current_opacity, :disposed

  def zoom
    @sprite ? @sprite.zoom_x : 1.0
  end

  def initialize(viewport, pre_spawn = false, saved_state = nil)
    @viewport = viewport
    @sprite = Sprite.new(@viewport)
    @disposed = false
    
    # Pega o clima atual do game_screen
    weather = $game_screen ? $game_screen.weather_type : :None
    
    # Em dias de chuva ou tempestade, não devemos criar nuvens individuais
    if [:Rain, :Storm].include?(weather)
      dispose
      return
    end
    
    if saved_state
      @id = saved_state[:id]
      @map_x = saved_state[:map_x]
      @map_y = saved_state[:map_y]
      @speed_x = saved_state[:speed_x]
      @speed_y = saved_state[:speed_y]
      zoom_val = saved_state[:zoom]
      @current_opacity = saved_state[:current_opacity]
    else
      # Seleciona aleatoriamente uma das 34 nuvens extraídas de alta qualidade
      @id = rand(1..34)
    end
    
    bitmap_path = pbResolveBitmap("Graphics/Fogs/PRSFX-CloudShadow#{@id}")
    if bitmap_path
      @sprite.bitmap = Bitmap.new(bitmap_path) rescue nil
    end
    
    # Se falhar em carregar a imagem, marca como disposed
    if !@sprite.bitmap
      dispose
      return
    end
    
    # Dimensões da imagem original
    @width = @sprite.bitmap.width
    @height = @sprite.bitmap.height
    
    # Configurações estéticas de sombra
    @sprite.z = 950 # Fica acima das rotas e do jogador, mas abaixo de mensagens e climas
    @sprite.blend_type = 0 # Normal
    
    unless saved_state
      # Define um tamanho/escala aleatório para cada nuvem (de 0.6x a 1.5x) para extrema diversidade!
      zoom_val = rand(60..150) / 100.0
    end
    @sprite.zoom_x = zoom_val
    @sprite.zoom_y = zoom_val
    
    # Cria o reflexo branco de nuvem que fica visível apenas na água!
    # z = -50 fica perfeitamente acima da água (z = -100) mas abaixo do gramado/chão (z = 0)!
    @reflection_sprite = Sprite.new(@viewport)
    @reflection_sprite.bitmap = @sprite.bitmap
    @reflection_sprite.zoom_x = zoom_val
    @reflection_sprite.zoom_y = zoom_val
    @reflection_sprite.z = -50
    @reflection_sprite.blend_type = 0 # Normal
    # Tom azul-celeste brilhante muito sutil para simular reflexo real do céu na água!
    @reflection_sprite.color = Color.new(240, 248, 255, 255)
    
    unless saved_state
      # Velocidades de movimentação individual da nuvem (vento suave majestoso)
      if weather == :Fog # Clima Nublado (Nuvens carregadas flutuam de forma super lenta!)
        @speed_x = rand(4..8) / 100.0   # Drift horizontal super lento (0.04 a 0.08 pixels/frame)
        @speed_y = rand(2..4) / 100.0   # Drift vertical super lento (0.02 a 0.04 pixels/frame)
      else # Ensolarado / Limpo / Outros (Vento lento e muito sutil)
        @speed_x = rand(10..20) / 100.0 # Drift horizontal lento (0.1 a 0.2 pixels/frame)
        @speed_y = rand(5..10) / 100.0  # Drift vertical lento (0.05 a 0.1 pixels/frame)
      end
      
      # Posições no mapa ancoradas com precisão de pixel no solo!
      camera_xf = $game_map.display_x.to_f / Game_Map::X_SUBPIXELS.to_f
      camera_yf = $game_map.display_y.to_f / Game_Map::Y_SUBPIXELS.to_f
      
      if pre_spawn
        # Pré-spawn: espalha a nuvem em uma coordenada aleatória da tela
        screen_x = rand(-100..(Graphics.width - 50))
        screen_y = rand(-100..(Graphics.height - 50))
        @map_x = camera_xf + screen_x
        @map_y = camera_yf + screen_y
        
        base_max = (weather == :Fog) ? 110.0 : 80.0
        @current_opacity = rand(20..base_max.round) # Começa parcialmente opaca
      else
        # Spawn normal: começa fora da tela na borda superior ou direita
        if rand(2) == 0
          screen_x = Graphics.width + 100
          screen_y = rand(-100..(Graphics.height - 200))
        else
          screen_x = rand(0..(Graphics.width - 150))
          screen_y = -@height * zoom_val - 100
        end
        @map_x = camera_xf + screen_x
        @map_y = camera_yf + screen_y
        @current_opacity = 0.0 # Começa invisível e faz fade-in suave
      end
    else
      camera_xf = $game_map.display_x.to_f / Game_Map::X_SUBPIXELS.to_f
      camera_yf = $game_map.display_y.to_f / Game_Map::Y_SUBPIXELS.to_f
      screen_x = (@map_x - camera_xf).round
      screen_y = (@map_y - camera_yf).round
    end
    
    @sprite.x = screen_x
    @sprite.y = screen_y
    @sprite.opacity = @current_opacity.round
    
    if @reflection_sprite
      @reflection_sprite.x = screen_x
      @reflection_sprite.y = screen_y
      @reflection_sprite.opacity = (@current_opacity * 0.6).round
    end
  end
 
  def update
    return if @disposed || !@sprite || @sprite.disposed?
    # Movimenta a nuvem no mapa (drift diagonal constante)
    @map_x -= @speed_x
    @map_y += @speed_y
    
    # Converte a exibição do mapa para coordenadas de pixel contínuas (floats)
    camera_xf = $game_map.display_x.to_f / Game_Map::X_SUBPIXELS.to_f
    camera_yf = $game_map.display_y.to_f / Game_Map::Y_SUBPIXELS.to_f
    
    # Nuvens 100% fixadas ao solo! Sem paralaxe, movendo-se exatamente junto com o cenário!
    screen_x = (@map_x - camera_xf).round
    screen_y = (@map_y - camera_yf).round
    
    @sprite.x = screen_x
    @sprite.y = screen_y
    
    # Define a opacidade alvo com base no clima
    weather = $game_screen ? $game_screen.weather_type : :None
    
    # Se o clima mudou para chuva ou tempestade no meio do caminho, faz fade-out rápido e descarta
    if [:Rain, :Storm].include?(weather)
      @current_opacity -= 1.0
      if @current_opacity <= 0
        dispose
        return
      end
    else
      base_max_opacity = 80.0
      if weather == :Fog # Nublado (Nuvens bem escuras e marcantes!)
        base_max_opacity = 110.0
      else # Ensolarado / Dia limpo (Sombras de nuvens bem definidas e escuras)
        base_max_opacity = 80.0
      end
      
      # Suaviza a transição de opacidade (fade-in/fade-out)
      if @current_opacity < base_max_opacity
        @current_opacity += 0.8
        @current_opacity = base_max_opacity if @current_opacity > base_max_opacity
      elsif @current_opacity > base_max_opacity
        @current_opacity -= 0.8
        @current_opacity = base_max_opacity if @current_opacity < base_max_opacity
      end
    end
    
    @sprite.opacity = @current_opacity.round
    
    if @reflection_sprite && !@reflection_sprite.disposed?
      @reflection_sprite.x = screen_x
      @reflection_sprite.y = screen_y
      @reflection_sprite.opacity = (@current_opacity * 0.6).round
      @reflection_sprite.visible = @sprite.visible
    end
    
    # Descarte inteligente quando sai totalmente dos limites ampliados da tela
    zoom = @sprite.zoom_x
    if screen_x < -@width * zoom - 250 || screen_x > Graphics.width + 250 ||
       screen_y < -@height * zoom - 250 || screen_y > Graphics.height + 250
      dispose
    end
  end

  def dispose
    return if @disposed
    if @sprite
      @sprite.bitmap.dispose rescue nil if @sprite.bitmap
      @sprite.dispose
    end
    @sprite = nil
    if @reflection_sprite
      @reflection_sprite.dispose rescue nil
      @reflection_sprite = nil
    end
    @disposed = true
  end
end

class DynamicCloudShadowsManager
  def initialize(viewport)
    @viewport = viewport
    @clouds = []
    
    # Cooldown inicial aleatório para o primeiro spawner
    @spawn_cooldown = rand(200..400)
    
    # Apenas pré-spawna nuvens se não estiver chovendo/tempestuando
    weather = $game_screen ? $game_screen.weather_type : :None
    if ![:Rain, :Storm].include?(weather)
      if $game_temp && $game_temp.respond_to?(:persistent_clouds) && 
         $game_temp.persistent_clouds && $game_temp.persistent_clouds_map_id == $game_map.map_id
        
        $game_temp.persistent_clouds.each do |saved_state|
          cloud = CloudShadow.new(@viewport, false, saved_state)
          @clouds.push(cloud) if !cloud.disposed
        end
        $game_temp.persistent_clouds = nil
        $game_temp.persistent_clouds_map_id = nil
      else
        # Se for Nublado (Fog), começa com 3 a 5 nuvens já espalhadas
        count = (weather == :Fog) ? rand(3..5) : rand(1..2)
        count.times do
          cloud = CloudShadow.new(@viewport, true)
          @clouds.push(cloud) if !cloud.disposed
        end
      end
    end
  end

  def save_state
    return if @clouds.empty?
    return unless $game_temp
    
    if !$game_temp.respond_to?(:persistent_clouds)
      class << $game_temp
        attr_accessor :persistent_clouds
        attr_accessor :persistent_clouds_map_id
      end
    end
    
    saved = []
    @clouds.each do |c|
      next if c.disposed
      saved << {
        id: c.id,
        map_x: c.map_x,
        map_y: c.map_y,
        speed_x: c.speed_x,
        speed_y: c.speed_y,
        zoom: c.zoom,
        current_opacity: c.current_opacity
      }
    end
    $game_temp.persistent_clouds = saved
    $game_temp.persistent_clouds_map_id = $game_map.map_id
  end

  def update
    weather = $game_screen ? $game_screen.weather_type : :None
    
    # Se estiver chovendo ou tempestuando, limpa/faz fade-out de todas as nuvens de sombra individuais
    #
    # ⚠️ A NEBLINA ENTROU PARA ESTA LISTA (MOD 170).
    #
    # Ela punha DEZ sombras a passar — mais do que qualquer outro clima. Fazia
    # sentido quando :Fog queria dizer "nublado"; deixou de fazer quando passou
    # a haver neblina de verdade por cima do mapa. Sombra de nuvem por baixo de
    # um veu de neblina nao se le como ceu encoberto, le-se como sujidade a
    # deslizar.
    #
    # Nao se poe max_clouds a zero: isto faz fade-out das que ja andam no ecra,
    # em vez de as apagar de repente a meio do mapa.
    if [:Rain, :Storm, :Fog].include?(weather)
      if !@clouds.empty?
        @clouds.each(&:update)
        @clouds.select! { |c| !c.disposed }
      end
      @spawn_cooldown = 100 # Mantém o cooldown resetado
      return
    end
    
    # Define a densidade de nuvens ativa conforme o clima
    if weather == :Cloudy
      max_clouds = 10     # ceu encoberto: sombras constantes a passar
      min_cooldown = 120
      max_cooldown = 240
    else
      # Limpo, sol, neve. Raras e subtis — um charme, e nao um efeito.
      max_clouds = 2
      min_cooldown = 600  # 15 a 30 segundos entre nuvens
      max_cooldown = 1200
    end
    
    # Atualiza todas as nuvens e remove as inativas
    @clouds.each(&:update)
    @clouds.select! { |c| !c.disposed }
    
    # Geração controlada
    if @clouds.size < max_clouds
      if @spawn_cooldown > 0
        @spawn_cooldown -= 1
      else
        # Cria uma nova nuvem com as propriedades do clima atual
        cloud = CloudShadow.new(@viewport, false)
        @clouds.push(cloud) if !cloud.disposed
        @spawn_cooldown = rand(min_cooldown..max_cooldown)
      end
    end
  end

  def dispose
    @clouds.each(&:dispose)
    @clouds.clear
  end
end

#===============================================================================
# * Injeção de Sombras de Nuvens no Spriteset_Map
#===============================================================================
class Spriteset_Map
  if !method_defined?(:anil_clouds_initialize)
    alias anil_clouds_initialize initialize
    alias anil_clouds_update update
    alias anil_clouds_dispose dispose
  end

  def initialize(map = nil)
    @map = (map) ? map : $game_map
    if @map && GameData::MapMetadata.try_get(@map.map_id)&.outdoor_map
      # Não limpa a panorama/sombra nativa se for o Bosque Viridian (Map 8)
      if @map.map_id != 8 && @map.respond_to?(:panorama_name)
        @map.instance_variable_set(:@panorama_name, "") rescue nil
      end
    end
    
    anil_clouds_initialize(map)
    
    # Cria as nuvens se o mapa for externo (outdoor_map), mas NÃO se for o Bosque Viridian (Map 8)
    # pois lá só podem ser exibidas as sombras nativas (canopy/árvores).
    if @map && GameData::MapMetadata.try_get(@map.map_id)&.outdoor_map && @map.map_id != 8
      # Utiliza o viewport padrão do mapa (@@viewport1) para as nuvens
      @cloud_shadows = DynamicCloudShadowsManager.new(@@viewport1)
    end
  end

  def update
    anil_clouds_update
    @cloud_shadows.update if @cloud_shadows
  end

  def dispose
    if @cloud_shadows
      @cloud_shadows.save_state rescue nil
      @cloud_shadows.dispose
    end
    @cloud_shadows = nil
    anil_clouds_dispose
  end
end

#===============================================================================
# * Sobrescrita de pbGetTimeNow para utilizar o horário do Servidor
#===============================================================================
def pbGetTimeNow
  if defined?(AnilLanRework) && AnilLanRework.respond_to?(:server_time)
    return AnilLanRework.server_time
  else
    return Time.now
  end
end
