#===============================================================================
# MOD: 062_Pokedex_Touch_Modular.rb
#-------------------------------------------------------------------------------
# Adiciona controles de toque específicos da Pokédex (Scrollbar da Lista principal,
# Abas Superiores de Informação e Setas de Formas).
#===============================================================================

# 1. Suporte a Arrastar e Clicar na Barra de Rolagem (Scroll Bar) da Pokédex
class PokemonPokedex_Scene
  alias touch_pokedex_pbUpdate pbUpdate unless method_defined?(:touch_pokedex_pbUpdate)

  def pbUpdate
    touch_pokedex_pbUpdate
    
    itemlist = @sprites["pokedex"] rescue nil
    if itemlist && itemlist.active
      page_rows = itemlist.page_row_max rescue 10
      @dragging_scrollbar ||= false
      
      mousepos = Mouse.getMousePos
      if mousepos
        mx = mousepos[0]
        my = mousepos[1]
        
        # 1. Início do clique na região da barra de rolagem (x: 460..512)
        if Input.trigger?(Input::MOUSELEFT) && mx >= 460 && mx <= 512
          $mouse_click_handled = true
          if my >= 48 && my < 78 # Seta para CIMA
            itemlist.top_row = [0, itemlist.top_row - 1].max
            itemlist.index = [[itemlist.index, itemlist.top_row * itemlist.column_max].max, (itemlist.top_row + page_rows - 1) * itemlist.column_max].min rescue itemlist.index
            itemlist.refresh rescue nil
            pbPlayCursorSE rescue nil
            pbRefresh
          elsif my >= 346 && my <= 376 # Seta para BAIXO
            max_top = [0, itemlist.row_max - page_rows].max
            itemlist.top_row = [max_top, itemlist.top_row + 1].min
            itemlist.index = [[itemlist.index, itemlist.top_row * itemlist.column_max].max, (itemlist.top_row + page_rows - 1) * itemlist.column_max].min rescue itemlist.index
            itemlist.refresh rescue nil
            pbPlayCursorSE rescue nil
            pbRefresh
          elsif my >= 78 && my < 346 # Região do Trilho (Track)
            @dragging_scrollbar = true
          end
        end
        
        # 2. Processamento do arrasto na barra de rolagem
        if Input.press?(Input::MOUSELEFT) && @dragging_scrollbar
          # Calcula o progresso y de 78 a 346 (trilho de 268 pixels)
          track_y = [0.0, [1.0, (my - 78).to_f / 268.0].min].max
          max_top = [0, itemlist.row_max - page_rows].max
          target_top = (track_y * max_top).round
          
          if itemlist.top_row != target_top
            itemlist.top_row = target_top
            itemlist.index = [[itemlist.index, itemlist.top_row * itemlist.column_max].max, (itemlist.top_row + page_rows - 1) * itemlist.column_max].min rescue itemlist.index
            itemlist.refresh rescue nil
            pbRefresh
          end
        end
      end
      
      # Finaliza o arrasto quando soltar o toque
      if @dragging_scrollbar && (!Input.press?(Input::MOUSELEFT) || (Input.release?(Input::MOUSELEFT) rescue false))
        @dragging_scrollbar = false
      end
    end
  end
end

# 2. Suporte a Clique/Toque na Entrada da Pokedex (Abas Superiores & Setas de Formas)
class PokemonPokedexInfo_Scene
  alias touch_orig_pbUpdate pbUpdate unless method_defined?(:touch_orig_pbUpdate)
  def pbUpdate
    touch_orig_pbUpdate
    
    if Input.trigger?(Input::MOUSELEFT)
      mousepos = Mouse.getMousePos
      if mousepos
        mx, my = mousepos[0], mousepos[1]
        
        # 1. Detecção de clique nas abas superiores
        if my < 48 && @page_list && !@page_list.empty?
          xpos, ypos = PAGE_ICONS_POSITION
          w, h       = PAGE_ICON_SIZE
          size       = MAX_PAGE_ICONS - 1
          range      = [@page_list.length, MAX_PAGE_ICONS]
          page       = @page_list.find_index(@page_id)
          startPage  = (page > size) ? page - size : 0
          endPage    = [startPage + size, @page_list.length - 1].min
          
          case PAGE_ICONS_ALIGNMENT
          when :left   then offset = 0
          when :right  then offset = ((Graphics.width - xpos - 42) - (w * range.min)).round
          when :center then offset = ((Graphics.width - xpos - 42) / 2 - (range.min * (w / 2))).round
          end
          
          clicked_page_index = nil
          iconPos = 0
          for i in startPage..endPage
            tab_x_start = xpos + offset + iconPos * (w + 4)
            tab_x_end = tab_x_start + w
            tab_y_start = ypos
            tab_y_end = ypos + h
            
            if mx >= tab_x_start && mx <= tab_x_end && my >= tab_y_start - 6 && my <= tab_y_end + 6
              clicked_page_index = i
              break
            end
            iconPos += 1
          end
          
          if clicked_page_index
            oldpage = @page
            @page = clicked_page_index + 1
            if @page != oldpage
              @page_id = @page_list[@page - 1]
              pbPlayCursorSE rescue nil
              drawPage(@page)
            end
          end
        end
        
        # 2. Detecção de clique nas setas de navegação de formas
        if @page_id == :page_forms && @available && @available.length > 1
          # uparrow: x=242..270, y=268..308
          # downarrow: x=242..270, y=348..388
          if mx >= 238 && mx <= 274
            if my >= 264 && my <= 312
              index = @available.find_index { |x| x[1] == @gender && x[2] == @form }
              if index && index > 0
                $touch_input_trigger_up = true
              end
            elsif my >= 344 && my <= 392
              index = @available.find_index { |x| x[1] == @gender && x[2] == @form }
              if index && index < @available.length - 1
                $touch_input_trigger_down = true
              end
            end
          end
        end
      end
    end
  end
end

class PokemonPokedex_Scene
  alias touch_pokedex_orig_pbStartScene pbStartScene unless method_defined?(:touch_pokedex_orig_pbStartScene)
  alias touch_pokedex_orig_pbEndScene pbEndScene unless method_defined?(:touch_pokedex_orig_pbEndScene)
  
  def pbStartScene(*args)
    $in_pokedex = true
    touch_pokedex_orig_pbStartScene(*args)
  end
  
  def pbEndScene(*args)
    touch_pokedex_orig_pbEndScene(*args)
    $in_pokedex = false
  end
end

class PokemonPokedexInfo_Scene
  alias touch_pokedex_info_orig_pbStartScene pbStartScene unless method_defined?(:touch_pokedex_info_orig_pbStartScene)
  alias touch_pokedex_info_orig_pbEndScene pbEndScene unless method_defined?(:touch_pokedex_info_orig_pbEndScene)
  
  def pbStartScene(*args)
    $in_pokedex = true
    touch_pokedex_info_orig_pbStartScene(*args)
  end
  
  def pbEndScene(*args)
    touch_pokedex_info_orig_pbEndScene(*args)
    $in_pokedex = false
  end
end

