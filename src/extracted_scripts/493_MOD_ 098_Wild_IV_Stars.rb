#===============================================================================
# MOD: 098_Wild_IV_Stars.rb
#-------------------------------------------------------------------------------
# Exibe estrelas indicadoras de IVs para Pokémon selvagens na caixa de dados de
# batalha (DataBox).
# Classificação dos 6 stats principais (HP, Ataque, Defesa, Velocidade, Sp. Atk, Sp. Def):
# - 0 a 10: Bronze (Bronze Star)
# - 11 a 20: Prata (Silver Star)
# - 21 a 31: Ouro (Gold Star)
#
# As estrelas possuem tamanho original de 8x8 pixels com espaçamento ampliado (+0.7x).
#===============================================================================

if defined?(Battle::Scene::PokemonDataBox)
  class Battle::Scene::PokemonDataBox
    alias anil_iv_stars_original_refresh refresh unless method_defined?(:anil_iv_stars_original_refresh)
    alias anil_iv_stars_original_dispose dispose unless method_defined?(:anil_iv_stars_original_dispose)
    alias anil_iv_stars_original_update update unless method_defined?(:anil_iv_stars_original_update)
    alias anil_iv_stars_original_set_x x= unless method_defined?(:anil_iv_stars_original_set_x)
    alias anil_iv_stars_original_set_y y= unless method_defined?(:anil_iv_stars_original_set_y)
    alias anil_iv_stars_original_set_z z= unless method_defined?(:anil_iv_stars_original_set_z)
    alias anil_iv_stars_original_set_opacity opacity= unless method_defined?(:anil_iv_stars_original_set_opacity)
    alias anil_iv_stars_original_set_visible visible= unless method_defined?(:anil_iv_stars_original_set_visible)
    alias anil_iv_stars_original_set_color color= unless method_defined?(:anil_iv_stars_original_set_color)

    # Construtor auxiliar de bitmaps caso as imagens customizadas não estejam presentes
    def build_fallback_star_bitmap(border, fill)
      base_bmp = Bitmap.new(8, 8)
      pixels = [
        [3,0,border], [4,0,border],
        [2,1,border], [3,1,fill], [4,1,fill], [5,1,border],
        [1,2,border], [2,2,fill], [3,2,fill], [4,2,fill], [5,2,fill], [6,2,border],
        [0,3,border], [1,3,fill], [2,3,fill], [3,3,fill], [4,3,fill], [5,3,fill], [6,3,fill], [7,3,border],
        [0,4,border], [1,4,fill], [2,4,fill], [3,4,fill], [4,4,fill], [5,4,fill], [6,4,fill], [7,4,border],
        [1,5,border], [2,5,fill], [3,5,fill], [4,5,fill], [5,5,fill], [6,5,border],
        [1,6,border], [2,6,fill], [5,6,fill], [6,6,border],
        [1,7,border], [6,7,border]
      ]
      pixels.each { |p| base_bmp.set_pixel(p[0], p[1], p[2]) }
      
      # Escalado para 14x14
      scaled_bmp = Bitmap.new(14, 14)
      scaled_bmp.stretch_blt(Rect.new(0, 0, 14, 14), base_bmp, Rect.new(0, 0, 8, 8))
      base_bmp.dispose rescue nil
      return scaled_bmp
    end

    # Cache de bitmaps das estrelas customizadas (carregadas de Graphics/Pictures)
    def get_gold_star_bitmap
      @@gold_star_bmp ||= nil
      if !@@gold_star_bmp || @@gold_star_bmp.disposed?
        path = "Graphics/Pictures/iv_star_gold"
        if pbResolveBitmap(path)
          @@gold_star_bmp = Bitmap.new(path)
        else
          # Fallback programático (Dourado/Amarelo)
          @@gold_star_bmp = build_fallback_star_bitmap(Color.new(200, 150, 0), Color.new(255, 223, 0))
        end
      end
      return @@gold_star_bmp
    end

    def get_silver_star_bitmap
      @@silver_star_bmp ||= nil
      if !@@silver_star_bmp || @@silver_star_bmp.disposed?
        path = "Graphics/Pictures/iv_star_silver"
        if pbResolveBitmap(path)
          @@silver_star_bmp = Bitmap.new(path)
        else
          # Fallback programático (Prateado/Cinza)
          @@silver_star_bmp = build_fallback_star_bitmap(Color.new(80, 90, 100), Color.new(192, 192, 192))
        end
      end
      return @@silver_star_bmp
    end

    def get_bronze_star_bitmap
      @@bronze_star_bmp ||= nil
      if !@@bronze_star_bmp || @@bronze_star_bmp.disposed?
        path = "Graphics/Pictures/iv_star_bronze"
        if pbResolveBitmap(path)
          @@bronze_star_bmp = Bitmap.new(path)
        else
          # Fallback programático (Bronze/Cobre)
          @@bronze_star_bmp = build_fallback_star_bitmap(Color.new(110, 50, 20), Color.new(191, 100, 40))
        end
      end
      return @@bronze_star_bmp
    end

    def get_red_star_bitmap
      @@red_star_bmp ||= nil
      if !@@red_star_bmp || @@red_star_bmp.disposed?
        path = "Graphics/Pictures/iv_star_red"
        if pbResolveBitmap(path)
          @@red_star_bmp = Bitmap.new(path)
        else
          # Fallback programático (Vermelho)
          @@red_star_bmp = build_fallback_star_bitmap(Color.new(150, 0, 0), Color.new(255, 30, 30))
        end
      end
      return @@red_star_bmp
    end

    def dispose
      @@gold_star_bmp&.dispose rescue nil
      @@gold_star_bmp = nil
      @@silver_star_bmp&.dispose rescue nil
      @@silver_star_bmp = nil
      @@bronze_star_bmp&.dispose rescue nil
      @@bronze_star_bmp = nil
      @@red_star_bmp&.dispose rescue nil
      @@red_star_bmp = nil
      if @iv_stars_sprite && !@iv_stars_sprite.disposed?
        @iv_stars_sprite.bitmap&.dispose rescue nil
        @iv_stars_sprite.dispose rescue nil
      end
      @iv_stars_sprite = nil
      anil_iv_stars_original_dispose
    end

    def update
      anil_iv_stars_original_update
      update_iv_stars_position
    end

    def x=(value)
      anil_iv_stars_original_set_x(value)
      if @iv_stars_sprite && !@iv_stars_sprite.disposed?
        base_x = @spriteBaseX || 0
        @iv_stars_sprite.x = value + base_x + 24
      end
    end

    def y=(value)
      anil_iv_stars_original_set_y(value)
      if @iv_stars_sprite && !@iv_stars_sprite.disposed?
        @iv_stars_sprite.y = value - 12
      end
    end

    def z=(value)
      anil_iv_stars_original_set_z(value)
      if @iv_stars_sprite && !@iv_stars_sprite.disposed?
        @iv_stars_sprite.z = value + 10
      end
    end

    def opacity=(value)
      anil_iv_stars_original_set_opacity(value)
      if @iv_stars_sprite && !@iv_stars_sprite.disposed?
        @iv_stars_sprite.opacity = value
      end
    end

    def visible=(value)
      anil_iv_stars_original_set_visible(value)
      if @iv_stars_sprite && !@iv_stars_sprite.disposed?
        @iv_stars_sprite.visible = value
      end
    end

    def color=(value)
      anil_iv_stars_original_set_color(value)
      if @iv_stars_sprite && !@iv_stars_sprite.disposed?
        @iv_stars_sprite.color = value
      end
    end

    def update_iv_stars_position
      if @iv_stars_sprite && !@iv_stars_sprite.disposed?
        base_x = @spriteBaseX || 0
        @iv_stars_sprite.x = self.x + base_x + 24
        @iv_stars_sprite.y = self.y - 12  # Viewport alto para nunca cortar a ponta
        @iv_stars_sprite.z = self.z + 10
        @iv_stars_sprite.visible = self.visible && (@sprite.visible rescue true)
        @iv_stars_sprite.opacity = self.opacity rescue 255
        @iv_stars_sprite.color = self.color rescue nil
      end
    end

    def refresh
      anil_iv_stars_original_refresh
      draw_iv_stars
    end

    def draw_iv_stars
      return unless @battler && @battler.pokemon
      # Apenas para oponentes (index ímpar/opostos ao jogador) em batalhas selvagens
      return unless @battler.opposes?(0)
      return if @battler.battle.trainerBattle?
      
      pokemon = @battler.pokemon
      return unless pokemon
      
      iv_hash = pokemon.iv rescue nil
      iv_hash ||= pokemon.ivs rescue nil
      return unless iv_hash.is_a?(Hash)
      
      # Mapeamento robusto dos stats para suportar diferentes versões do Essentials e traduções
      stats_map = {
        :HP => [:HP, :hp],
        :ATTACK => [:ATTACK, :attack],
        :DEFENSE => [:DEFENSE, :defense],
        :SPEED => [:SPEED, :speed],
        :SPECIAL_ATTACK => [:SPECIAL_ATTACK, :special_attack, :SPATK, :spatk],
        :SPECIAL_DEFENSE => [:SPECIAL_DEFENSE, :special_defense, :SPDEF, :spdef]
      }
      
      stats = [:HP, :ATTACK, :DEFENSE, :SPEED, :SPECIAL_ATTACK, :SPECIAL_DEFENSE]
      
      # Cria o sprite dedicado das estrelas de IV se necessário
      if !@iv_stars_sprite || @iv_stars_sprite.disposed?
        @iv_stars_sprite = Sprite.new(self.viewport)
        @iv_stars_sprite.bitmap = Bitmap.new(120, 14) # Espaço para as 6 estrelas (6 * 19 = 114)
      end
      
      @iv_stars_sprite.bitmap.clear
      
      stats.each_with_index do |stat, index|
        iv_val = 0
        possible_keys = stats_map[stat] || [stat]
        possible_keys.each do |k|
          if iv_hash[k]
            iv_val = iv_hash[k].to_i
            break
          end
        end
        
        # Classificação por faixa de IV:
        # - 0 a 10: Bronze
        # - 11 a 20: Prata
        # - 21 a 24: Ouro
        # - 25 a 31: Vermelha
        star_bmp = if iv_val >= 25
          get_red_star_bitmap
        elsif iv_val >= 21
          get_gold_star_bitmap
        elsif iv_val >= 11
          get_silver_star_bitmap
        else
          get_bronze_star_bitmap
        end
        
        # Star size = 14px, Step = 19px (gap de 5px, que é o espaçamento original ampliado em +0.7x)
        @iv_stars_sprite.bitmap.blt(index * 19, 0, star_bmp, Rect.new(0, 0, 14, 14))
      end
      
      update_iv_stars_position
    end
  end
end

#===============================================================================
# OVERRIDE: pbDisplayIVRatings para o Summary / Stats / Storage padrão
#===============================================================================
def pbDisplayIVRatings(pokemon, overlay, xpos, ypos, horizontal = false)
  return if !pokemon
  imagepos = []
  offset_x = (horizontal) ? 16 : 0
  offset_y = (horizontal) ? 0  : 32
  
  i = 0
  stats_keys = [:HP, :ATTACK, :DEFENSE, :SPECIAL_ATTACK, :SPECIAL_DEFENSE, :SPEED]
  
  stats_keys.each do |s_id|
    stat = pokemon.iv[s_id] || 0
    
    # Classificação atualizada:
    # - 0 a 10: Bronze
    # - 11 a 20: Prata
    # - 21 a 24: Ouro
    # - 25 a 31: Vermelha
    star_bmp_path = if stat >= 25
      "Graphics/Pictures/iv_star_red"
    elsif stat >= 21
      "Graphics/Pictures/iv_star_gold"
    elsif stat >= 11
      "Graphics/Pictures/iv_star_silver"
    else
      "Graphics/Pictures/iv_star_bronze"
    end
    
    imagepos.push([star_bmp_path, xpos + (i * offset_x), ypos + (i * offset_y)])
    
    if s_id == :HP && !horizontal
      # Mantém compatibilidade de layout com outros plugins de summary
      ypos += (PluginManager.installed?("BW Summary Screen")) ? 18 : 12 rescue ypos += 12
    end
    i += 1
  end
  pbDrawImagePositions(overlay, imagepos)
end

#===============================================================================
# OVERRIDE: pbDisplayIVRatingsSV no PokemonSummary_Scene do SV Summary Screen
#===============================================================================
class PokemonSummary_Scene
  def pbDisplayIVRatingsSV(pokemon, overlay, evivpage)
    return if !pokemon
    imagepos = []
    
    xpos = if evivpage
      { 
        :HP => 400, :hp => 400,
        :SPECIAL_ATTACK => 496, :SPATK => 496, :spatk => 496,
        :SPECIAL_DEFENSE => 496, :SPDEF => 496, :spdef => 496,
        :ATTACK => 216, :attack => 216,
        :DEFENSE => 216, :defense => 216,
        :SPEED => 400, :SPE => 400, :speed => 400
      }
    else
      {
        :HP => 412, :hp => 412,
        :SPECIAL_ATTACK => 458, :SPATK => 458, :spatk => 458,
        :SPECIAL_DEFENSE => 458, :SPDEF => 458, :spdef => 458,
        :ATTACK => 252, :attack => 252,
        :DEFENSE => 252, :defense => 252,
        :SPEED => 388, :SPE => 388, :speed => 388
      }
    end
    
    ypos = { 
      :HP => 72, :hp => 72, 
      :SPECIAL_ATTACK => 130, :SPATK => 130, :spatk => 130, 
      :SPECIAL_DEFENSE => 190, :SPDEF => 190, :spdef => 190, 
      :ATTACK => 130, :attack => 130, 
      :DEFENSE => 190, :defense => 190, 
      :SPEED => 248, :speed => 248 
    }
    
    GameData::Stat.each_main do |s|
      stat = pokemon.iv[s.id] || 0
      x_pos = xpos[s.id] || 0
      y_pos = ypos[s.id] || 0
      
      # Classificação atualizada:
      # - 0 a 10: Bronze
      # - 11 a 20: Prata
      # - 21 a 24: Ouro
      # - 25 a 31: Vermelha
      star_bmp_path = if stat >= 25
        "Graphics/Pictures/iv_star_red"
      elsif stat >= 21
        "Graphics/Pictures/iv_star_gold"
      elsif stat >= 11
        "Graphics/Pictures/iv_star_silver"
      else
        "Graphics/Pictures/iv_star_bronze"
      end
      
      # Ajuste de +1 no X e Y para centralização ideal das nossas estrelas customizadas 14x14px
      imagepos.push([star_bmp_path, x_pos + 1, y_pos + 1])
    end
    pbDrawImagePositions(overlay, imagepos)
  end
end
