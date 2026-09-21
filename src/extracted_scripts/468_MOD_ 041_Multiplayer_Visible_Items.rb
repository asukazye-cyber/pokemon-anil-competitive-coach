#===============================================================================
# MOD: 041_Multiplayer_Visible_Items.rb
#-------------------------------------------------------------------------------
# Sistema de Itens Visíveis no Mapa (Visible Items on Map)
# Transforma as pokébolas de itens no chão em ícones reais dos itens e
# adiciona um efeito de brilho pulsante.
#===============================================================================

Object.send(:remove_const, :VISIBLE_ITEM_ZOOM) rescue nil
VISIBLE_ITEM_ZOOM = 0.7

module AnilLanRework
  def self.is_item_ball_graphic?(char_name)
    name = char_name.to_s.downcase.sub(/\.png$/i, '')
    return false if name.empty?
    return true if name.include?("ball") && !name.include?("caballer") && !name.include?("trainer")
    return true if name.include?("objeto") || name.include?("item") || name.include?("drop") || name.include?("loot") || name.include?("bag")
    return true if name == "healing balls 1" || name == "healing balls 2" || name == "masterball" || name == "object ball" || name == "objetont"
    false
  end

  def self.glow_color_for_item(item_id)
    return Color.new(255, 255, 255) if !item_id
    itm = GameData::Item.get(item_id) rescue nil
    return Color.new(255, 255, 255) if !itm
    
    id_str = item_id.to_s.upcase
    
    # Vermelho (Itens Lendários/Premium da Caixa Vermelha)
    if (defined?(GiftBoxSystem) && GiftBoxSystem.const_defined?(:RED_POOL) && GiftBoxSystem::RED_POOL.include?(item_id)) || id_str == "SUPERSHINYZADOR"
      return Color.new(255, 60, 60)
    end
    
    # Ovos de Raridade
    # start_with? cobre as variantes (_SHINY / _SUPERSHINY) junto da cor base.
    if id_str.start_with?("EGG_GREY")
      return Color.new(150, 150, 150)
    elsif id_str.start_with?("EGG_GREEN")
      return Color.new(50, 255, 50)
    elsif id_str.start_with?("EGG_BLUE")
      return Color.new(50, 150, 255)
    elsif id_str.start_with?("EGG_PURPLE")
      return Color.new(180, 50, 255)
    elsif id_str.start_with?("EGG_ORANGE")
      return Color.new(255, 128, 0)
    end
    
    # Muito Raro (Laranja)
    if id_str.include?("MASTERBALL") || id_str.include?("RARECANDY") || id_str.include?("BOTTLECAP") || 
       id_str.include?("PPMAX") || id_str.include?("PPUP") || id_str.include?("MAXREVIVE") || 
       id_str.include?("ABILITYPATCH") || id_str.include?("ABILITYCAPSULE") || id_str.include?("SACREDASH") ||
       id_str.include?("MEGARING") || id_str.include?("ZRING") || id_str.include?("DYNAMAX") ||
       id_str.include?("CHOICE") || id_str.include?("LIFEORB") || id_str.include?("SASH") || id_str.include?("ASSAVEST")
      return Color.new(255, 128, 0)
    end
    
    # Raro (Azul)
    if id_str.include?("ULTRABALL") || id_str.include?("MAXPOTION") || id_str.include?("REVIVE") || 
       id_str.include?("STONE") || id_str.include?("EXPALL") || id_str.include?("LUCKYEGG") ||
       id_str.include?("AMULETCOIN") || id_str.include?("EXPSHARE") || id_str.include?("VITAMIN") ||
       id_str.include?("CALCIUM") || id_str.include?("CARBOS") || id_str.include?("HPUP") ||
       id_str.include?("IRON") || id_str.include?("PROTEIN") || id_str.include?("ZINC") ||
       id_str.include?("HEARTSCALE") || id_str.include?("GOLD") || id_str.include?("NUGGET") ||
       id_str.include?("BIGPEARL") || id_str.include?("STARPIECE") || id_str.include?("STARDUST") ||
       id_str.include?("BALL")
      if !id_str.include?("GREATBALL") && !id_str.include?("POKEBALL")
        return Color.new(50, 150, 255)
      end
    end
    
    if id_str.include?("STONE") || id_str.include?("HEARTSCALE") || id_str.include?("GOLD") || id_str.include?("NUGGET")
      return Color.new(50, 150, 255)
    end
    
    # Incomum (Verde)
    if id_str.include?("GREATBALL") || id_str.include?("SUPERPOTION") || id_str.include?("ETHER") || 
       id_str.include?("ELIXIR") || id_str.include?("REPEL") || id_str.include?("FLUTE") ||
       id_str.include?("HEAL") || id_str.include?("AWAKENING") || id_str.include?("ANTIDOTE") ||
       id_str.include?("BURNHEAL") || id_str.include?("PARALYZEHEAL") || id_str.include?("ICEHEAL") ||
       id_str.include?("PEARL") || id_str.include?("TINYMUSHROOM")
      return Color.new(50, 255, 50)
    end
    
    # Fallback baseado em preço
    price = itm.price || 0
    if price >= 10000
      Color.new(255, 128, 0)   # Laranja
    elsif price >= 4000
      Color.new(50, 150, 255)  # Azul
    elsif price >= 1000
      Color.new(50, 255, 50)   # Verde
    else
      Color.new(255, 255, 255) # Branco
    end
  end
end


# --- 1. PATCHES ESTÁTICOS INICIAIS ---

class Game_Event < Game_Character
  attr_accessor :visible_item_id
  attr_reader   :page

  alias visible_items_refresh refresh unless method_defined?(:visible_items_refresh)
  def refresh
    visible_items_refresh
    @visible_item_id = nil
    return if @erased || !@page
    
    is_item_graphic = AnilLanRework.is_item_ball_graphic?(@page.graphic.character_name)
    is_item_name = self.name.to_s.downcase.include?("item") || self.name.to_s.downcase.include?("drop")
    
    if is_item_graphic || is_item_name
      @visible_item_id = pbExtractItemID
    end
  end
  
  def pbExtractItemID
    # Suporte para itens jogados no chao (Dropped Items) do multiplayer coop
    if self.name.to_s =~ /^DroppedItem_(.+)$/
      item_raw = $1
      item_id = item_raw.to_s.match?(/^\d+$/) ? item_raw.to_i : item_raw.to_sym
      return item_id if GameData::Item.exists?(item_id)
    end

    return nil if !@list
    full_script = ""
    @list.each do |cmd|
      if cmd.code == 355 || cmd.code == 655
        full_script += cmd.parameters[0].to_s + " "
      end
    end
    if full_script =~ /pbItemBall\s*\(\s*(?::([^\s,\)\'\"]+)|"([^"]+)"|'([^']+)'|[A-Za-z0-9_:]+::([^\s,\)\'\"]+)|(\d+))/ ||
       full_script =~ /pbReceiveItem\s*\(\s*(?::([^\s,\)\'\"]+)|"([^"]+)"|'([^']+)'|[A-Za-z0-9_:]+::([^\s,\)\'\"]+)|(\d+))/
      item_raw = $1 || $2 || $3 || $4 || $5
      item_id = item_raw.to_s.match?(/^\d+$/) ? item_raw.to_i : item_raw.to_sym
      return item_id if GameData::Item.exists?(item_id)
    end
    return nil
  end
end

class Sprite_Character < RPG::Sprite
  alias visible_items_refresh_graphic refresh_graphic unless method_defined?(:visible_items_refresh_graphic)
  def refresh_graphic
    self.zoom_x = 1.0
    self.zoom_y = 1.0
    
    # INICIO VISIBLE ITEMS
    if @character.is_a?(Game_Event) && @character.respond_to?(:visible_item_id) && @character.visible_item_id
      item_id = @character.visible_item_id
      return if @tile_id == 0 && @character_name == "ITEM_#{item_id}" && @oldbushdepth == @character.bush_depth
      @tile_id = 0
      @character_name = "ITEM_#{item_id}"
      @character_hue = 0
      @oldbushdepth = @character.bush_depth
      
      @charbitmap&.dispose
      @charbitmap = nil
      @bushbitmap&.dispose
      @bushbitmap = nil
      
      icon_path = GameData::Item.icon_filename(item_id)
      
      # ⚠️ NAO SE PROCURA UM FICHEIRO A TENTAR ABRI-LO.
      #
      # O que estava aqui pedia `RPG::Cache.load_bitmap("Graphics/Items/", "TM81")`
      # e usava o `rescue` como resposta. So que Graphics/Items/TM81.png nao existe
      # — as TMs partilham um icone por tipo, `machine_BUG.png` — portanto as DUAS
      # tentativas (normal e maiuscula) rebentavam sempre, em todos os refrescos.
      #
      # Isso nem se guarda em cache: o `fromCache` da nil, o BitmapWrapper levanta a
      # excepcao, e nada fica registado. Na entrada seguinte repete-se tudo.
      #
      # No Android, uma leitura de ficheiro que falha custa segundos — foi assim que
      # o `ItemBall` custava 2 s por evento. Medido na Rota 13: o evento 25, uma
      # Poke Ball com uma TM81, gastava 5077 ms sozinho, 88% de todo o tempo de
      # sprites, e a entrada no mapa passava de 650 ms para 5,9 s. Invisivel na lista
      # de ficheiros mais caros porque `load_bitmap` nao e `AnimatedBitmap`.
      #
      # O `pbResolveBitmap` responde a mesma pergunta sem levantar excepcao nenhuma,
      # ja tem cache propria, e devolve o caminho pronto a usar. Quando o icone
      # proprio existe, isto ainda poupa uma leitura: antes lia-se o ficheiro aqui e
      # outra vez no AnimatedBitmap logo abaixo.
      if (achado = (pbResolveBitmap("Graphics/Items/#{item_id}") rescue nil))
        icon_path = achado
      elsif (achado = (pbResolveBitmap("Graphics/Items/#{item_id.to_s.upcase}") rescue nil))
        icon_path = achado
      end
      
      @charbitmap = AnimatedBitmap.new(icon_path)
      @charbitmapAnimated = true
      @spriteoffset = false
      @cw = @charbitmap.width
      @ch = @charbitmap.height
      self.bitmap = @charbitmap.bitmap
      self.src_rect.set(0, 0, @cw, @ch)
      self.ox = @cw / 2
      self.oy = @ch - 4
      self.zoom_x = VISIBLE_ITEM_ZOOM
      self.zoom_y = VISIBLE_ITEM_ZOOM
      @character.sprite_size = [@cw, @ch]
      return
    end
    # FIM VISIBLE ITEMS
    
    visible_items_refresh_graphic
  end

  # INICIO VISIBLE ITEMS UPDATE
  alias visible_items_update update unless method_defined?(:visible_items_update)
  def update
    visible_items_update
    if @character.is_a?(Game_Event) && @character.respond_to?(:visible_item_id) && @character.visible_item_id
      if @charbitmap && @tile_id == 0
        self.src_rect.set(0, 0, @cw, @ch)
      end
      self.zoom_x = VISIBLE_ITEM_ZOOM
      self.zoom_y = VISIBLE_ITEM_ZOOM
      update_item_glow
    end
  end

  def update_item_glow
    return if self.disposed? || !self.visible
    interval = 200 
    timer = Graphics.frame_count % interval
    if timer < 20
      alpha = (Math.sin(timer * Math::PI / 20) * 160).to_i
      item_id = @character.visible_item_id
      c = AnilLanRework.glow_color_for_item(item_id) rescue Color.new(255, 255, 255)
      self.color.set(c.red, c.green, c.blue, alpha)
    else
      self.color.set(0, 0, 0, 0) if self.color.alpha > 0
    end
  end
  # FIM VISIBLE ITEMS UPDATE
end

# --- 2. PATCHES DINÂMICOS PÓS-PLUGINS ---

module AnilLanRework
  class << self
    alias anil_visible_items_original_apply_post_plugin_patches apply_post_plugin_patches unless method_defined?(:anil_visible_items_original_apply_post_plugin_patches)
    
    def apply_post_plugin_patches
      anil_visible_items_original_apply_post_plugin_patches rescue nil
      
      # Patch dinâmico para Sprite_Character
      if defined?(Sprite_Character)
        Sprite_Character.class_eval do
          alias anil_visible_items_post_plugin_refresh_graphic refresh_graphic unless method_defined?(:anil_visible_items_post_plugin_refresh_graphic)
          alias anil_visible_items_post_plugin_update update unless method_defined?(:anil_visible_items_post_plugin_update)
          
          def refresh_graphic
            self.zoom_x = 1.0
            self.zoom_y = 1.0
            if @character.is_a?(Game_Event) && @character.respond_to?(:visible_item_id) && @character.visible_item_id
              item_id = @character.visible_item_id
              return if @tile_id == 0 && @character_name == "ITEM_#{item_id}" && @oldbushdepth == @character.bush_depth
              @tile_id = 0
              @character_name = "ITEM_#{item_id}"
              @character_hue = 0
              @oldbushdepth = @character.bush_depth
              
              @charbitmap&.dispose
              @charbitmap = nil
              @bushbitmap&.dispose
              @bushbitmap = nil
              
              icon_path = GameData::Item.icon_filename(item_id)
              
              # ⚠️ NAO SE PROCURA UM FICHEIRO A TENTAR ABRI-LO.
              #
              # O que estava aqui pedia `RPG::Cache.load_bitmap("Graphics/Items/", "TM81")`
              # e usava o `rescue` como resposta. So que Graphics/Items/TM81.png nao existe
              # — as TMs partilham um icone por tipo, `machine_BUG.png` — portanto as DUAS
              # tentativas (normal e maiuscula) rebentavam sempre, em todos os refrescos.
              #
              # Isso nem se guarda em cache: o `fromCache` da nil, o BitmapWrapper levanta a
              # excepcao, e nada fica registado. Na entrada seguinte repete-se tudo.
              #
              # No Android, uma leitura de ficheiro que falha custa segundos — foi assim que
              # o `ItemBall` custava 2 s por evento. Medido na Rota 13: o evento 25, uma
              # Poke Ball com uma TM81, gastava 5077 ms sozinho, 88% de todo o tempo de
              # sprites, e a entrada no mapa passava de 650 ms para 5,9 s. Invisivel na lista
              # de ficheiros mais caros porque `load_bitmap` nao e `AnimatedBitmap`.
              #
              # O `pbResolveBitmap` responde a mesma pergunta sem levantar excepcao nenhuma,
              # ja tem cache propria, e devolve o caminho pronto a usar. Quando o icone
              # proprio existe, isto ainda poupa uma leitura: antes lia-se o ficheiro aqui e
              # outra vez no AnimatedBitmap logo abaixo.
              if (achado = (pbResolveBitmap("Graphics/Items/#{item_id}") rescue nil))
                icon_path = achado
              elsif (achado = (pbResolveBitmap("Graphics/Items/#{item_id.to_s.upcase}") rescue nil))
                icon_path = achado
              end
              
              @charbitmap = AnimatedBitmap.new(icon_path)
              @charbitmapAnimated = true
              @spriteoffset = false
              @cw = @charbitmap.width
              @ch = @charbitmap.height
              self.bitmap = @charbitmap.bitmap
              self.src_rect.set(0, 0, @cw, @ch)
              self.ox = @cw / 2
              self.oy = @ch - 4
              self.zoom_x = VISIBLE_ITEM_ZOOM
              self.zoom_y = VISIBLE_ITEM_ZOOM
              @character.sprite_size = [@cw, @ch]
              return
            end
            
            anil_visible_items_post_plugin_refresh_graphic
          end
          
          def update
            anil_visible_items_post_plugin_update
            if @character.is_a?(Game_Event) && @character.respond_to?(:visible_item_id) && @character.visible_item_id
              if @charbitmap && @tile_id == 0
                self.src_rect.set(0, 0, @cw, @ch)
              end
              self.zoom_x = VISIBLE_ITEM_ZOOM
              self.zoom_y = VISIBLE_ITEM_ZOOM
              update_item_glow
            end
          end
          
          def update_item_glow
            return if self.disposed? || !self.visible
            interval = 200 
            timer = Graphics.frame_count % interval
            if timer < 20
              alpha = (Math.sin(timer * Math::PI / 20) * 160).to_i
              item_id = @character.visible_item_id
              c = AnilLanRework.glow_color_for_item(item_id) rescue Color.new(255, 255, 255)
              self.color.set(c.red, c.green, c.blue, alpha)
            else
              self.color.set(0, 0, 0, 0) if self.color.alpha > 0
            end
          end
        end
        AnilLanRework.log("[VISIBLE ITEMS] Patches dinâmicos de renderização para Sprite_Character aplicados com sucesso!")
      end
      
      # Patch dinâmico para Game_Event
      if defined?(Game_Event)
        Game_Event.class_eval do
          alias anil_visible_items_post_plugin_refresh refresh unless method_defined?(:anil_visible_items_post_plugin_refresh)

          def refresh
            anil_visible_items_post_plugin_refresh
            @visible_item_id = nil
            return if @erased || !@page
            
            is_item_graphic = AnilLanRework.is_item_ball_graphic?(@page.graphic.character_name)
            is_item_name = self.name.to_s.downcase.include?("item") || self.name.to_s.downcase.include?("drop")
            
            if is_item_graphic || is_item_name
              @visible_item_id = pbExtractItemID
            end
          end
          
          def pbExtractItemID
            # Suporte para itens jogados no chao (Dropped Items) do multiplayer coop
            if self.name.to_s =~ /^DroppedItem_(.+)$/
              item_raw = $1
              item_id = item_raw.to_s.match?(/^\d+$/) ? item_raw.to_i : item_raw.to_sym
              return item_id if GameData::Item.exists?(item_id)
            end

            return nil if !@list
            full_script = ""
            @list.each do |cmd|
              if cmd.code == 355 || cmd.code == 655
                full_script += cmd.parameters[0].to_s + " "
              end
            end
            if full_script =~ /pbItemBall\s*\(\s*(?::([^\s,\)\'\"]+)|"([^"]+)"|'([^']+)'|[A-Za-z0-9_:]+::([^\s,\)\'\"]+)|(\d+))/ ||
               full_script =~ /pbReceiveItem\s*\(\s*(?::([^\s,\)\'\"]+)|"([^"]+)"|'([^']+)'|[A-Za-z0-9_:]+::([^\s,\)\'\"]+)|(\d+))/
              item_raw = $1 || $2 || $3 || $4 || $5
              item_id = item_raw.to_s.match?(/^\d+$/) ? item_raw.to_i : item_raw.to_sym
              return item_id if GameData::Item.exists?(item_id)
            end
            return nil
          end
        end
        AnilLanRework.log("[VISIBLE ITEMS] Patches dinâmicos para Game_Event aplicados com sucesso!")
      end
    end
  end
end

AnilLanRework.log("AnilLanRework_VisibleItems (Itens Visíveis no Mapa) carregado com SUCESSO!")
