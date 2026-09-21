#===============================================================================
#
#===============================================================================
class BushBitmap
  def initialize(bitmap, isTile, depth)
    @bitmaps  = []
    @bitmap   = bitmap
    @isTile   = isTile
    @isBitmap = @bitmap.is_a?(Bitmap)
    @depth    = depth
  end

  def dispose
    @bitmaps.each { |b| b&.dispose }
  end

  def bitmap
    thisBitmap = (@isBitmap) ? @bitmap : @bitmap.bitmap
    current = (@isBitmap) ? 0 : @bitmap.currentIndex
    if !@bitmaps[current]
      if @isTile
        @bitmaps[current] = pbBushDepthTile(thisBitmap, @depth)
      else
        @bitmaps[current] = pbBushDepthBitmap(thisBitmap, @depth)
      end
    end
    return @bitmaps[current]
  end

  def pbBushDepthBitmap(bitmap, depth)
    ret = Bitmap.new(bitmap.width, bitmap.height)
    charheight = ret.height / 4
    cy = charheight - depth - 2
    4.times do |i|
      y = i * charheight
      if cy >= 0
        ret.blt(0, y, bitmap, Rect.new(0, y, ret.width, cy))
        ret.blt(0, y + cy, bitmap, Rect.new(0, y + cy, ret.width, 2), 170)
      end
      ret.blt(0, y + cy + 2, bitmap, Rect.new(0, y + cy + 2, ret.width, 2), 85) if cy + 2 >= 0
    end
    return ret
  end

  def pbBushDepthTile(bitmap, depth)
    ret = Bitmap.new(bitmap.width, bitmap.height)
    charheight = ret.height
    cy = charheight - depth - 2
    y = charheight
    if cy >= 0
      ret.blt(0, y, bitmap, Rect.new(0, y, ret.width, cy))
      ret.blt(0, y + cy, bitmap, Rect.new(0, y + cy, ret.width, 2), 170)
    end
    ret.blt(0, y + cy + 2, bitmap, Rect.new(0, y + cy + 2, ret.width, 2), 85) if cy + 2 >= 0
    return ret
  end
end

#===============================================================================
#
#===============================================================================
class Sprite_Character < RPG::Sprite
  attr_accessor :character

  def initialize(viewport, character = nil)
    super(viewport)
    @character    = character
    @oldbushdepth = 0
    @spriteoffset = false
    if !character || character == $game_player || (character.name[/reflection/i] rescue false)
      @reflection = Sprite_Reflection.new(self, viewport)
    end
    @surfbase = Sprite_SurfBase.new(self, viewport) if character == $game_player
    self.zoom_x = TilemapRenderer::ZOOM_X
    self.zoom_y = TilemapRenderer::ZOOM_Y
    @shiny_stars = []
    @shiny_timer = rand(400)
    update
  end

  def groundY
    return @character.screen_y_ground
  end

  def visible=(value)
    super(value)
    @reflection.visible = value if @reflection
  end

  def dispose
    if @shiny_stars
      @shiny_stars.each { |s| s.dispose if s && !s.disposed? }
      @shiny_stars.clear
    end
    @anil_moonlight_sprite&.dispose rescue nil
    @anil_moonlight_sprite = nil
    @bushbitmap&.dispose
    @bushbitmap = nil
    @charbitmap&.dispose
    @charbitmap = nil
    @reflection&.dispose
    @reflection = nil
    @surfbase&.dispose
    @surfbase = nil
    @character = nil
    super
  end

  def refresh_graphic
    return if @tile_id == @character.tile_id &&
              @character_name == @character.character_name &&
              @character_hue == @character.character_hue &&
              @oldbushdepth == @character.bush_depth
    @tile_id        = @character.tile_id
    @character_name = @character.character_name
    @character_hue  = @character.character_hue
    @oldbushdepth   = @character.bush_depth
    @is_player_follower_cached = nil
    @is_shiny_character_cached = nil
    @is_super_shiny_character_cached = nil
    @charbitmap&.dispose
    @charbitmap = nil
    @bushbitmap&.dispose
    @bushbitmap = nil
    if @tile_id >= 384
      @charbitmap = pbGetTileBitmap(@character.map.tileset_name, @tile_id,
                                    @character_hue, @character.width, @character.height)
      @charbitmapAnimated = false
      @spriteoffset = false
      @cw = Game_Map::TILE_WIDTH * @character.width
      @ch = Game_Map::TILE_HEIGHT * @character.height
      self.src_rect.set(0, 0, @cw, @ch)
      self.ox = @cw / 2
      self.oy = @ch
    elsif @character_name != ""
      # Tentar carregar skin da pasta Graphics/Skins/ primeiro (skins multiplayer)
      skin_path = "Graphics/Skins/" + @character_name
      
      # ⚠️ ISTO CORRE SEMPRE QUE UM SPRITE E REFRESCADO, E ISSO E MUITO.
      #
      # Estavam aqui duas escritas de debug em `multiplayer_debug.txt` sem flag
      # nenhuma. Como o ficheiro nem sequer chega a existir na pasta do jogo, o
      # File.open falhava e o `rescue nil` apanhava — ou seja, duas EXCEPCOES
      # levantadas e apanhadas por cada refresco de cada sprite. Levantar uma
      # excepcao em Ruby e das coisas mais caras que ha.
      #
      # E o File.exist? em duplicado e uma ida ao disco por refresco, que num
      # telemovel nao e de graca. A resposta nunca muda enquanto o jogo corre,
      # portanto guarda-se por nome de skin.
      $anil_skin_existe ||= {}
      exists_png = if $anil_skin_existe.key?(skin_path)
        $anil_skin_existe[skin_path]
      else
        $anil_skin_existe[skin_path] =
          (File.exist?(skin_path + ".png") || File.exist?(skin_path + ".PNG"))
      end
      
      if exists_png
        @charbitmap = AnimatedBitmap.new(skin_path, @character_hue)
        RPG::Cache.retain("Graphics/Skins/", @character_name, @character_hue) if @character == $game_player
      elsif pbResolveBitmap(skin_path)
        @charbitmap = AnimatedBitmap.new(skin_path, @character_hue)
        RPG::Cache.retain("Graphics/Skins/", @character_name, @character_hue) if @character == $game_player
      else
        @charbitmap = AnimatedBitmap.new(
          "Graphics/Characters/" + @character_name, @character_hue
        )
        RPG::Cache.retain("Graphics/Characters/", @character_name, @character_hue) if @character == $game_player
      end
      @charbitmapAnimated = true
      @spriteoffset = @character_name[/offset/i]
      if defined?(AnilLanRework::RemotePeer) && @character.is_a?(AnilLanRework::RemotePeer) && !@character.remote_follower_visual
        @cw = @charbitmap.width / 14
       else
        @cw = @charbitmap.width / 4
      end
      @ch = @charbitmap.height / 4
      self.ox = @cw / 2
    else
      self.bitmap = nil
      @cw = 0
      @ch = 0
    end
    @character.sprite_size = [@cw, @ch]
  end

  def update
    return if @character.is_a?(Game_Event) && !@character.should_update?
    super
    refresh_graphic
    return if !@charbitmap
    @charbitmap.update if @charbitmapAnimated
    bushdepth = @character.bush_depth
    if bushdepth == 0
      self.bitmap = (@charbitmapAnimated) ? @charbitmap.bitmap : @charbitmap
    else
      @bushbitmap = BushBitmap.new(@charbitmap, (@tile_id >= 384), bushdepth) if !@bushbitmap
      self.bitmap = @bushbitmap.bitmap
    end
    self.visible = !@character.transparent
    if @tile_id == 0
      sx = @character.pattern * @cw
      sy = ((@character.direction - 2) / 2) * @ch
      self.src_rect.set(sx, sy, @cw, @ch)
      self.oy = (@spriteoffset rescue false) ? @ch - 16 : @ch
      self.oy -= @character.bob_height
    end
    if self.visible
      if @character.is_a?(Game_Event) && @character.name[/regulartone/i]
        self.tone.set(0, 0, 0, 0)
      else
        pbDayNightTint(self)
      end
    end
    this_x = @character.screen_x
    this_x = ((this_x - (Graphics.width / 2)) * TilemapRenderer::ZOOM_X) + (Graphics.width / 2) if TilemapRenderer::ZOOM_X != 1
    self.x = this_x
    this_y = @character.screen_y
    this_y = ((this_y - (Graphics.height / 2)) * TilemapRenderer::ZOOM_Y) + (Graphics.height / 2) if TilemapRenderer::ZOOM_Y != 1
    self.y = this_y
    self.z = @character.screen_z(@ch)
    self.opacity = @character.opacity
    self.blend_type = @character.blend_type
    if @character.animation_id != 0
      animation = $data_animations[@character.animation_id]
      animation(animation, true)
      @character.animation_id = 0
    end
    unless MAPAS_SIN_REFLEJO.include?($game_map.map_id)
      @reflection&.visible = true
      @reflection&.update
    else
      @reflection&.visible = true
    end
    @surfbase&.update

    # --- EFEITO DE NOITE DE LUAR (MOONLIGHT RIM LIGHT) ---
    $current_is_moonlight_frame ||= nil
    $current_is_moonlight_value ||= nil
    current_frame = Graphics.frame_count rescue nil
    if current_frame && $current_is_moonlight_frame != current_frame
      $current_is_moonlight_frame = current_frame
      $current_is_moonlight_value = ($forced_weather == :Moonlight || (defined?(AnilLanRework) && $game_map && $game_map.map_id != 0 && AnilLanRework.get_weather_for_map($game_map.map_id) == :Moonlight))
    end
    is_moonlight = current_frame ? $current_is_moonlight_value : ($forced_weather == :Moonlight || (defined?(AnilLanRework) && $game_map && $game_map.map_id != 0 && AnilLanRework.get_weather_for_map($game_map.map_id) == :Moonlight))

    if is_moonlight && self.bitmap && !self.bitmap.disposed? && self.visible
      if !@anil_moonlight_sprite || @anil_moonlight_sprite.disposed?
        @anil_moonlight_sprite = Sprite.new(self.viewport)
      end
      @anil_moonlight_sprite.bitmap = self.bitmap
      @anil_moonlight_sprite.src_rect.set(self.src_rect.x, self.src_rect.y, self.src_rect.width, self.src_rect.height)
      @anil_moonlight_sprite.ox = self.ox
      @anil_moonlight_sprite.oy = self.oy
      @anil_moonlight_sprite.zoom_x = self.zoom_x
      @anil_moonlight_sprite.zoom_y = self.zoom_y
      @anil_moonlight_sprite.visible = self.visible && !@character.transparent
      @anil_moonlight_sprite.opacity = (15 * self.opacity / 255.0).to_i
      @anil_moonlight_sprite.color.set(255, 255, 255, 255)
      @anil_moonlight_sprite.blend_type = 1 # ADD para efeito iluminado
      @anil_moonlight_sprite.z = self.z + 1
      @anil_moonlight_sprite.x = self.x
      @anil_moonlight_sprite.y = self.y
    else
      if @anil_moonlight_sprite
        @anil_moonlight_sprite.dispose rescue nil
        @anil_moonlight_sprite = nil
      end
    end
    update_shiny_particles
  end

  def update_shiny_particles
    @shiny_stars ||= []
    
    if @is_shiny_character_cached.nil?
      is_shiny = false
      is_super_shiny = false
      if @character && !@character.transparent
        char_name = @character.character_name.to_s
        if char_name.downcase.include?("shiny")
          is_shiny = true
          is_super_shiny = true if char_name.downcase.include?("super_shiny") || char_name.downcase.include?("radiant")
        end

        # ⚠️ O NOME DO FICHEIRO NAO CHEGA PARA O SUPER SHINY.
        #
        # O brilho decidia-se so por "shiny" no nome do sprite. Isso funciona
        # para o shiny normal, que usa os graficos de "Followers shiny/" — mas
        # NAO para o super shiny, que por desenho usa o sprite NORMAL com um hue
        # por cima (ver a regra do VOE: `... && !pokemon.super_shiny?`). Nome sem
        # "shiny" => nunca brilhava, e era o caso que passava em branco.
        #
        # Perguntar ao proprio Pokemon resolve os dois casos e nao depende de
        # como o sprite foi escolhido.
        if !is_shiny && @character.respond_to?(:pokemon)
          pk = (@character.pokemon rescue nil)
          if pk
            if (pk.super_shiny? rescue false)
              is_shiny = true
              is_super_shiny = true
            elsif (pk.shiny? rescue false)
              is_shiny = true
            end
          end
        end
        
        # Tenta identificar se o evento é o follower do jogador
        if @is_player_follower_cached.nil?
          is_pf = @character.is_a?(Game_Follower)
          if !is_pf && @character.is_a?(Game_Event)
            if @character.name && (@character.name.downcase.include?("follower") || @character.name.downcase.include?("dependent"))
              is_pf = true
            elsif $PokemonGlobal && $PokemonGlobal.followers && $PokemonGlobal.followers.any? { |f| f.event_id == @character.id && f.current_map_id == @character.map.map_id }
              is_pf = true
            end
          end
          @is_player_follower_cached = is_pf
        end
        is_player_follower = @is_player_follower_cached
        
        if is_player_follower
          pkmn = ($player && $player.party && $player.party[0]) rescue nil
          if pkmn && pkmn.shiny?
            is_shiny = true
            if defined?(Settings::SUPER_SHINY) && Settings::SUPER_SHINY && pkmn.respond_to?(:super_shiny?)
              is_super_shiny = true if pkmn.super_shiny?
            elsif pkmn.respond_to?(:super_shiny?)
              is_super_shiny = true if pkmn.super_shiny?
            end
          end
          # ⚠️ Sem flag, isto criava um debug_particles.txt no disco do jogador.
          # Uma linha por sprite de follower — e os sprites sao refeitos a cada
          # mudanca de mapa, portanto o ficheiro crescia a sessao toda. Fica
          # atras da mesma flag da irma dela, mais abaixo.
          if $anil_debug_particulas && @logged_follower_status.nil?
            @logged_follower_status = true
            File.open("debug_particles.txt", "a") { |f| f.puts "[#{Time.now}] FOLLOWER DETECTED! id=#{@character.id}, class=#{@character.class} | shiny? #{is_shiny}, radiant? #{is_super_shiny}, pkmn exists? #{!pkmn.nil?}, pkmn.shiny? #{pkmn ? pkmn.shiny? : 'nil'}" } rescue nil
          end
        elsif defined?(AnilLanRework::RemotePeer) && @character.is_a?(AnilLanRework::RemotePeer)
          if @character.follower_super_shiny || char_name.downcase.include?("shiny")
            is_shiny = true
            is_super_shiny = true if @character.follower_super_shiny
          end
        end
      end
      # ⚠️ UM "NAO" GUARDADO CEDO DE MAIS DURA PARA SEMPRE.
      #
      # A resposta e memorizada na primeira vez que o sprite corre. Mas um
      # spawn do mundo nasce em dois tempos: o evento primeiro, o Pokemon
      # logo a seguir. Se o sprite for actualizado no meio disso, o
      # `@character.pokemon` ainda e nil, conclui-se "nao brilha", e isso
      # fica gravado — o bicho pode ser o shiny mais raro do jogo que nunca
      # mais tem estrelas.
      #
      # Nao se guarda um NAO enquanto o boneco tiver um Pokemon por
      # responder. O SIM guarda-se sempre: esse ja e uma resposta.
      if !@is_player_follower_cached
        pode_guardar = true
        if !is_shiny && @character.respond_to?(:pokemon)
          pode_guardar = false if (@character.pokemon rescue nil).nil?
        end
        if pode_guardar
          @is_shiny_character_cached = is_shiny
          @is_super_shiny_character_cached = is_super_shiny
        end
      end
    else
      is_shiny = @is_shiny_character_cached
      is_super_shiny = @is_super_shiny_character_cached
    end

    if is_shiny && self.visible && self.opacity > 0
      @shiny_timer = 800 if @shiny_timer.nil?
      @shiny_timer += 1
      force = (@character.respond_to?(:force_sparkle) && @character.force_sparkle)
      if @shiny_timer >= 800 || force
        # ⚠️ Este File.open corria a CADA disparo de brilho, sem qualquer flag.
        # Um ficheiro a crescer no disco do jogador por causa de um Pokemon a
        # cintilar. Fica atras da mesma flag do resto do debug.
        if $anil_debug_particulas
          File.open("debug_particles.txt", "a") { |f| f.puts "[#{Time.now}] SPARKLE TRIGGERED! force=#{force}, is_shiny=#{is_shiny}" } rescue nil
        end
        # SEM som aqui de proposito: o efeito de aparecer um shiny e a
        # animacao 52 (ou 53 no super), disparada no spawn, e ela ja traz o som
        # nos proprios frames. Tocar tambem aqui daria som a dobrar, e este
        # bloco reemite a cada 20 segundos enquanto o Pokemon esta no ecra.
        @shiny_timer = 0
        @character.force_sparkle = false if force
        @emitting_frames = 400 # Emite durante 10 segundos (40fps)
      end
      
      if @emitting_frames && @emitting_frames > 0
        @emitting_frames -= 1
        
        # Emite 1 partícula a cada 20 frames se estiver abaixo do limite de 65
        if @emitting_frames % 20 == 0 && @shiny_stars.size < 65
          subpixels_x = (Game_Map::X_SUBPIXELS rescue 4)
          subpixels_y = (Game_Map::Y_SUBPIXELS rescue 4)
          
          particle_type = is_super_shiny ? :radiant : :shiny
          x_off = rand(-16..16)
          # O Pokémon é 1x (32 pixels) mais baixo do que estava calculado.
          # Alteramos de rand(-24..4) para rand(8..40) para nascerem mais abaixo.
          y_off = rand(8..40)
          max_a = 80 + rand(80) # Duração entre 2 e 4 segundos (a 40fps)
          
          # Calcula a coordenada real absoluta no mapa (ancorada ao tile/coordenada de spawn ATUAL)
          p_real_x = @character.real_x + (x_off * subpixels_x)
          # Subtrai o offset de origem vertical para alinhar com o sprite do Pokémon
          p_real_y = @character.real_y + ((y_off - self.oy) * subpixels_y)
          
          particle = ShinyStarParticle.new(self.viewport, p_real_x, p_real_y, max_a, 0, particle_type)
          @shiny_stars.push(particle)
        end
      end
    else
      @shiny_timer = rand(800) if @shiny_timer
      @emitting_frames = 0
    end

    @shiny_stars.reject! do |star|
      if star.disposed?
        true
      else
        if star.delay > 0
          star.delay -= 1
          star.visible = false
          next false
        end
        
        star.visible = self.visible && !@character.transparent
        star.age += 1
        
        subpixels_x = (Game_Map::X_SUBPIXELS rescue 4)
        subpixels_y = (Game_Map::Y_SUBPIXELS rescue 4)
        
        # Flutua suavemente como vagalumes (vx, vy) + Efeito "Sambando" (wobble)
        wobble = Math.sin(star.age * star.wobble_speed) * star.wobble_amp
        star.map_x += (star.vx + wobble) * subpixels_x
        star.map_y += star.vy * subpixels_y
        
        img_num = 1 + (star.age / 3) % 7
        $star_bitmaps ||= []
        if $star_bitmaps.empty?
          (1..7).each { |i| $star_bitmaps[i] = Bitmap.new("Graphics/Titles/Particles/star00#{i}.png") rescue nil }
        end
        star.bitmap = $star_bitmaps[img_num]
        
        half_life = star.max_age / 2.0
        max_opacity = 160
        if star.age < half_life
          star.opacity = (max_opacity * star.age / half_life).to_i
        else
          star.opacity = (max_opacity * (star.max_age - star.age) / half_life).to_i
        end
        
        # Converte as coordenadas reais absolutas do mapa para a tela do jogador (efeito rastro perfeito)
        px = ((star.map_x.to_f - $game_map.display_x) / subpixels_x).round + (Game_Map::TILE_WIDTH rescue 32) / 2
        py = ((star.map_y.to_f - $game_map.display_y) / subpixels_y).round + (Game_Map::TILE_HEIGHT rescue 32)
        
        # Aplica o zoom da câmera
        px = ((px - (Graphics.width / 2)) * TilemapRenderer::ZOOM_X) + (Graphics.width / 2) if TilemapRenderer::ZOOM_X != 1
        py = ((py - (Graphics.height / 2)) * TilemapRenderer::ZOOM_Y) + (Graphics.height / 2) if TilemapRenderer::ZOOM_Y != 1
        
        star.x = px
        star.y = py
        star.z = self.z + 1
        star.zoom_x = self.zoom_x * star.base_zoom
        star.zoom_y = self.zoom_y * star.base_zoom
        
        if star.age >= star.max_age
          star.dispose
          true
        else
          false
        end
      end
    end
  end
end

class ShinyStarParticle < Sprite
  attr_accessor :map_x, :map_y, :age, :max_age, :delay, :type, :vx, :vy
  attr_accessor :base_zoom, :wobble_speed, :wobble_amp
  
  def initialize(viewport, map_x, map_y, max_a, del, type = :shiny)
    super(viewport)
    @map_x = map_x
    @map_y = map_y
    @age = 0
    @max_age = max_a
    @delay = del
    @type = type
    
    # Velocidade horizontal leve (reduzido pela metade)
    @vx = (rand(10) - 5) / 80.0 
    # Flutua para cima de forma leve e variada (reduzido pela metade)
    @vy = -0.025 - (rand(15) / 100.0) 
    
    # Variação de tamanho reduzida pela metade (0.25x a 0.75x)
    @base_zoom = 0.25 + (rand(11) / 20.0)
    
    # Parâmetros de "Sambar" (Dança de Vagalume) - reduzido pela metade
    @wobble_speed = rand(10..30) / 200.0
    @wobble_amp = rand(5..15) / 200.0
    
    self.opacity = 0
    self.blend_type = 1
    
    # Tonalidades intensas sem estourar o branco
    if @type == :radiant
      self.tone.set(-50, 50, 150, 0) # Azul clarinho intenso
    else
      self.tone.set(100, 50, -100, 0) # Amarelo Dourado intenso
    end
  end
end

