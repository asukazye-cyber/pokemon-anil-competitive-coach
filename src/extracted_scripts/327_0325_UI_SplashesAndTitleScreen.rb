#===============================================================================
# Tela de Título Dinâmica com Equipe do Save
#===============================================================================
class IntroEventScene < EventScene
  # Imagens de splash
  SPLASH_IMAGES         = ["splash2"]
  # Imagem de fundo principal
  TITLE_BG_IMAGE        = "title"
  TITLE_START_IMAGE     = "start"
  TITLE_START_IMAGE_X   = 0
  TITLE_START_IMAGE_Y   = 322 + 20
  SECONDS_PER_SPLASH    = 1
  TICKS_PER_ENTER_FLASH = 40
  FADE_TICKS            = 8

  def initialize(viewport = nil)
    super(viewport)
    @pic = addImage(0, 0, "")
    @pic.setOpacity(0, 0)
    @pic2 = addImage(0, 0, "")
    @pic2.setOpacity(0, 0)
    @index = 0
    @dynamic_sprites = {} # Armazena sprites do save
    if SPLASH_IMAGES.empty?
      open_title_screen(self, nil)
    else
      open_splash(self, nil)
    end
  end

  def dispose
    if @intro_fireflies
      @intro_fireflies.each { |p| p.dispose }
    end
    pbDisposeSpriteHash(@dynamic_sprites)
    super
  end

  def open_splash(_scene, *args)
    onCTrigger.clear
    @pic.name = "Graphics/Titles/" + SPLASH_IMAGES[@index]
    @pic.moveOpacity(0, FADE_TICKS, 255)
    pictureWait
    @timer = System.uptime
    onUpdate.set(method(:splash_update))
    onCTrigger.set(method(:close_splash))
  end

  def close_splash(scene, args)
    onUpdate.clear
    onCTrigger.clear
    @pic.moveOpacity(0, FADE_TICKS, 0)
    pictureWait
    @index += 1
    if @index >= SPLASH_IMAGES.length
      open_title_screen(scene, args)
    else
      open_splash(scene, args)
    end
  end

  def splash_update(scene, args)
    close_splash(scene, args) if System.uptime - @timer >= SECONDS_PER_SPLASH
  end

  def open_title_screen(_scene, *args)
    onUpdate.clear
    onCTrigger.clear
    @pic.name = "Graphics/Titles/" + TITLE_BG_IMAGE
    @pic.moveOpacity(0, FADE_TICKS, 255)
    
    # Aplica tom de noite se for noite
    if PBDayNight.isNight?(pbGetTimeNow)
      @pic.setTone(0, Tone.new(-85, -85, -50, 68))
      @is_night_intro = true
    end
    
    @pic2.name = "Graphics/Titles/" + TITLE_START_IMAGE
    @pic2.setXY(0, TITLE_START_IMAGE_X, TITLE_START_IMAGE_Y)
    @pic2.setVisible(0, true)
    @pic2.moveOpacity(0, FADE_TICKS, 255)
    
    @intro_fireflies = []
    
    # Adicionar sprites do save
    pbSetTitleSaveSprites
    
    pictureWait
    pbBGMPlay($data_system.title_bgm)
    onUpdate.set(method(:title_screen_update))
    onCTrigger.set(method(:close_title_screen))
  end

  # Nova função para carregar e exibir dados do save na intro
  def pbSetTitleSaveSprites
    return if !SaveData.exists?
    begin
      save_data = SaveData.read_from_file(SaveData::FILE_PATH)
      return if !save_data || !save_data[:player]
      
      trainer = save_data[:player]
      party = trainer.party
      
      # 1. Carregar Treinador
      meta = GameData::PlayerMetadata.get(trainer.character_ID)
      if meta
        filename = pbResolvePlayerCharsetName(trainer.multiplayer_skin)
        filename ||= pbGetPlayerCharset(meta.walk_charset, trainer, true)
        
        @dynamic_sprites["player"] = TrainerWalkingCharSprite.new(filename, @viewport)
        charwidth  = @dynamic_sprites["player"].bitmap.width
        charheight = @dynamic_sprites["player"].bitmap.height
        @dynamic_sprites["player"].x = (Graphics.width / 2) - (charwidth / 8)
        @dynamic_sprites["player"].y = 240 # Posicionado acima do "Press Enter"
        @dynamic_sprites["player"].z = 50
        @dynamic_sprites["player"].opacity = 0
      end
      
      # 2. Carregar Equipe (em arco)
      party.each_with_index do |pkmn, i|
        @dynamic_sprites["party#{i}"] = PokemonIconSprite.new(pkmn, @viewport)
        @dynamic_sprites["party#{i}"].setOffset(PictureOrigin::CENTER)
        
        # Cálculo de arco
        angle = (i * Math::PI / (party.length - 1)) - Math::PI if party.length > 1
        angle ||= -Math::PI / 2 # Único Pokémon fica no topo
        
        radius_x = 120
        radius_y = 60
        @dynamic_sprites["party#{i}"].x = (Graphics.width / 2) + Math.cos(angle) * radius_x
        @dynamic_sprites["party#{i}"].y = 260 + Math.sin(angle) * radius_y
        @dynamic_sprites["party#{i}"].z = 51
        @dynamic_sprites["party#{i}"].opacity = 0
      end
    rescue
      # Se houver erro no save, apenas ignora para não travar a abertura do jogo
    end
  end

  def fade_out_title_screen(scene)
    onUpdate.clear
    onCTrigger.clear
    species_keys = GameData::Species.keys
    species_data = GameData::Species.get(species_keys.sample)
    Pokemon.play_cry(species_data.species, species_data.form)
    @pic.moveXY(0, 20, 0, 0)
    pictureWait
    
    @pic.moveOpacity(0, FADE_TICKS, 0)
    @pic2.clearProcesses
    @pic2.moveOpacity(0, FADE_TICKS, 0)
    
    # Fade out dos sprites dinâmicos
    @dynamic_sprites.each_value { |s| s.opacity = 0 if s }
    
    if @intro_fireflies
      @intro_fireflies.each { |p| p.opacity = 0 }
    end
    
    pbBGMStop(1.0)
    pictureWait
    scene.dispose
  end

  def close_title_screen(scene, *args)
    fade_out_title_screen(scene)
    sscene = PokemonLoad_Scene.new
    sscreen = PokemonLoadScreen.new(sscene)
    sscreen.pbStartLoadScreen
  end

  def close_title_screen_delete(scene, *args)
    fade_out_title_screen(scene)
    sscene = PokemonLoad_Scene.new
    sscreen = PokemonLoadScreen.new(sscene)
    sscreen.pbStartDeleteScreen
  end

  def title_screen_update(scene, args)
    # Animação dos vagalumes noturnos
    if @is_night_intro
      if rand(100) < 10 # Emite alguns vagalumes aleatoriamente
        particle = IntroFireflyParticle.new(@viewport)
        @intro_fireflies.push(particle)
      end
      @intro_fireflies.reject! do |p|
        if p.disposed? || p.age >= p.max_age
          p.dispose
          true
        else
          p.update_particle
          false
        end
      end
    end
    
    # Animação dos sprites dinâmicos (fade in suave)
    @dynamic_sprites.each_value do |s|
      s.opacity += 25 if s.opacity < 255
      s.update if s.respond_to?(:update)
    end
    
    if !@pic2.running?
      @pic2.moveOpacity(TICKS_PER_ENTER_FLASH * 2 / 10, TICKS_PER_ENTER_FLASH * 4 / 10, 0)
      @pic2.moveOpacity(TICKS_PER_ENTER_FLASH * 6 / 10, TICKS_PER_ENTER_FLASH * 4 / 10, 255)
    end
    if Input.press?(Input::DOWN) && Input.press?(Input::BACK) && Input.press?(Input::CTRL)
      close_title_screen_delete(scene, args)
    end
  end
end

class IntroFireflyParticle < Sprite
  attr_accessor :age, :max_age, :vx, :vy

  def initialize(viewport)
    super(viewport)
    @age = 0
    @max_age = 150 + rand(150) # Vivem entre 3.75s e 7.5s (a 40fps)
    self.bitmap = Bitmap.new("Graphics/Titles/Particles/special001.png") rescue nil
    self.x = rand(Graphics.width)
    self.y = rand(Graphics.height)
    self.z = 100
    self.opacity = 0
    self.blend_type = 1 # ADD para brilhar
    
    # Cores verdes conforme solicitado
    self.tone.set(0, 255, -50, 0)
    
    @vx = (rand(20) - 10) / 10.0
    @vy = (rand(20) - 10) / 10.0
    
    zoom = 0.5 + rand(10) / 10.0
    self.zoom_x = zoom
    self.zoom_y = zoom
  end

  def update_particle
    @age += 1
    
    # Movimento aleatório caótico (voando para cima/baixo/lados aleatoriamente)
    @vx += (rand(11) - 5) / 20.0
    @vy += (rand(11) - 5) / 20.0
    # Limita a velocidade máxima
    @vx = [[@vx, -2.0].max, 2.0].min
    @vy = [[@vy, -2.0].max, 2.0].min
    
    self.x += @vx
    self.y += @vy
    
    # Blink (piscar e acender diminuindo)
    half_life = @max_age / 2.0
    base_opacity = 0
    if @age < half_life
      base_opacity = (255 * @age / half_life).to_i
    else
      base_opacity = (255 * (@max_age - @age) / half_life).to_i
    end
    
    # Oscilação extra para "piscar" enquanto acende/apaga
    blink = (Math.sin(@age * 0.2) * 50).to_i
    self.opacity = base_opacity + blink
  end
end

class Scene_Intro
  def main
    Graphics.transition(0)
    @eventscene = IntroEventScene.new
    @eventscene.main
    Graphics.freeze
  end
end
