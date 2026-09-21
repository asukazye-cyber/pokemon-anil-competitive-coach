#===============================================================================
# TELA DE TÍTULO CUSTOMIZADA (FORÇADA)
# Sobrescreve o sistema de plugins para garantir a carga do time do save.
#===============================================================================

class ModularTitleScreen
  def random?
    @random
  end

  def initialize
    # defines viewport
    @viewport = Viewport.new(0,0,Graphics.width,Graphics.height)
    @viewport.z = 99999
    # defines sprite hash
    @sprites = {}
    @intro = nil
    @currentFrame = 0
    @mods = ModularTitle::MODIFIERS rescue []
    bg = "BG0"
    backdrop = "nil"
    bg_selected = false
    
    #---------------------------------------------------------------------------
    # setting up Save Data
    save_trainer = nil
    save_party = []
    if SaveData.exists?
      begin
        save_data = SaveData.read_from_file(SaveData::FILE_PATH)
        if save_data && save_data[:player]
          save_trainer = save_data[:player]
          save_party = save_trainer.party
        end
      rescue
      end
    end
    
    #---------------------------------------------------------------------------
    # setting up Pokemon Sprites
    @random = RandomizedChallenge.enabled? if defined?(RandomizedChallenge) 
    RandomizedChallenge.pause_random_species if random? && defined?(RandomizedChallenge)

    # 1. Sprite de Equipe (Slot 1)
    species1 = (save_party[0] && save_party[0].species) ? save_party[0].species : :VENUSAUR
    pokemon1 = save_party[0] ? save_party[0] : Pokemon.new(species1, 1)
    @sprites["poke_sprite"] = PokemonSprite.new(@viewport)
    @sprites["poke_sprite"].setPokemonBitmap(pokemon1)
    @sprites["poke_sprite"].setOffset(PictureOrigin::BOTTOM)
    @sprites["poke_sprite"].z = 100
    @sprites["poke_sprite"].x = 90
    @sprites["poke_sprite"].y = @viewport.rect.height - 40
    @sprites["poke_sprite"].zoom_x = 0.97
    @sprites["poke_sprite"].zoom_y = 0.97
    
    # 2. Sprite de Equipe (Slot 2)
    species2 = (save_party[1] && save_party[1].species) ? save_party[1].species : :CHARIZARD
    pokemon2 = save_party[1] ? save_party[1] : Pokemon.new(species2, 1)
    @sprites["poke_sprite2"] = PokemonSprite.new(@viewport)
    @sprites["poke_sprite2"].setPokemonBitmap(pokemon2)
    @sprites["poke_sprite2"].setOffset(PictureOrigin::BOTTOM)
    @sprites["poke_sprite2"].z = 101
    @sprites["poke_sprite2"].x = @viewport.rect.width/2 + 40
    @sprites["poke_sprite2"].y = @viewport.rect.height - 80
    @sprites["poke_sprite2"].zoom_x = 0.97
    @sprites["poke_sprite2"].zoom_y = 0.97

    # 3. Sprite de Treinador (Centro)
    if save_trainer
      meta = GameData::PlayerMetadata.get(save_trainer.character_ID)
      filename = pbResolvePlayerCharsetName(save_trainer.multiplayer_skin)
      filename ||= pbGetPlayerCharset(meta.walk_charset, save_trainer, true)
      @sprites["poke_sprite3"] = TrainerWalkingCharSprite.new(filename, @viewport)
      spr_tr = @sprites["poke_sprite3"]
      def spr_tr.setPokemonBitmap(pkmn); end
      @sprites["poke_sprite3"].z = 105
      @sprites["poke_sprite3"].x = @viewport.rect.width/2 + 10
      @sprites["poke_sprite3"].y = @viewport.rect.height - 20
    else
      @sprites["poke_sprite3"] = PokemonSprite.new(@viewport)
      pokemon3 = Pokemon.new(:PIKACHU_16,1)
      @sprites["poke_sprite3"].setPokemonBitmap(pokemon3)
      @sprites["poke_sprite3"].setOffset(PictureOrigin::BOTTOM)
      @sprites["poke_sprite3"].z = 105
      @sprites["poke_sprite3"].x = @viewport.rect.width/2 + 10
      @sprites["poke_sprite3"].y = @viewport.rect.height - 20
    end

    # 4. Sprite de Equipe (Slot 3)
    species4 = (save_party[2] && save_party[2].species) ? save_party[2].species : :BLASTOISE
    pokemon4 = save_party[2] ? save_party[2] : Pokemon.new(species4, 1)
    @sprites["poke_sprite4"] = PokemonSprite.new(@viewport)
    @sprites["poke_sprite4"].setPokemonBitmap(pokemon4)
    @sprites["poke_sprite4"].setOffset(PictureOrigin::BOTTOM)
    @sprites["poke_sprite4"].z = 100
    @sprites["poke_sprite4"].x = @viewport.rect.width - 70
    @sprites["poke_sprite4"].y = @viewport.rect.height - 50

    # Logo e Fundo (Fallback se o plugin falhar)
    @sprites["bg"] = IconSprite.new(0,0,@viewport)
    @sprites["bg"].setBitmap("Graphics/Titles/background5") rescue nil
    
    @sprites["logo"] = IconSprite.new(0,0,@viewport)
    @sprites["logo"].setBitmap("Graphics/Titles/logo") rescue nil
    @sprites["logo"].x = @viewport.rect.width/2 - @sprites["logo"].bitmap.width/2 rescue 0
    @sprites["logo"].y = 20

    @sprites["start"] = Sprite.new(@viewport)
    @sprites["start"].bitmap = pbBitmap("Graphics/Titles/start")
    @sprites["start"].x = @viewport.rect.width/2 - @sprites["start"].bitmap.width/2
    @sprites["start"].y = @viewport.rect.height * 0.85
    @sprites["start"].z = 999
    @fade = 8
  end

  def update
    @currentFrame ||= 0
    @currentFrame += 1
    for key in @sprites.keys
      @sprites[key].update if @sprites[key].respond_to?(:update)
    end
    @sprites["start"].opacity -= @fade
    @fade *= -1 if @sprites["start"].opacity <= 0 || @sprites["start"].opacity >= 255
  end

  def dispose
    for key in @sprites.keys
      @sprites[key].dispose
    end
    @viewport.dispose
  end

  def playBGM
    bgm = $data_system.title_bgm.name rescue "Title"
    pbBGMPlay(bgm)
  end

  def intro
    @sprites["start"].visible = true
  end
end

# Sobrescrever a Scene_Intro para usar a nossa classe acima
class Scene_Intro
  def main
    Graphics.transition(0)
    @screen = ModularTitleScreen.new
    @screen.playBGM
    @screen.intro
    loop do
      @screen.update
      Graphics.update
      Input.update
      break if Input.trigger?(Input::C) || (defined?($mouse) && $mouse.leftClick?)
    end
    pbSEPlay(GameData::Species.cry_filename(:PIKACHU)) rescue nil
    @screen.dispose
    sscene = PokemonLoad_Scene.new
    sscreen = PokemonLoadScreen.new(sscene)
    sscreen.pbStartLoadScreen
  end
end
