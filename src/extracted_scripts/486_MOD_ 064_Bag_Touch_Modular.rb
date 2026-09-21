#===============================================================================
# MOD: 064_Bag_Touch_Modular.rb
#-------------------------------------------------------------------------------
# Adiciona controles de toque e clique específicos para a Mochila (Window_PokemonBag).
#===============================================================================

class Window_PokemonBag < Window_DrawableCommand
  # Habilita o offset de 16px na lista da mochila
  def pbListYOffset
    return 16
  end

  alias touch_bag_update update unless method_defined?(:touch_bag_update)

  def update
    # 0. Desativar mouse genérico do SpriteWindow_Selectable para a mochila
    $disable_selectable_mouse = true

    # 1. Lógica perfeita de toque/arrasto e clique de soltura para a lista de itens da mochila
    if $cancel_all_clicks
      @bag_drag_start_x = nil
      @bag_drag_start_y = nil
      @bag_drag_start_index = nil
      @bag_has_dragged = false
      @bag_drag_active = false
    end

    if self.active && @item_max > 0 && @index >= 0 && !@ignore_input && !$cancel_all_clicks
      @bag_drag_start_x ||= nil
      @bag_drag_start_y ||= nil
      @bag_drag_start_index ||= nil
      @bag_has_dragged ||= false
      @bag_drag_active ||= false
      
      mousepos = Mouse.getMousePos
      
      if Input.trigger?(Input::MOUSELEFT) && mousepos
        viewport = self.viewport rescue nil
        v_x = (viewport && !viewport.disposed?) ? (viewport.rect.x - viewport.ox) : 0
        v_y = (viewport && !viewport.disposed?) ? (viewport.rect.y - viewport.oy) : 0
        offset = pbListYOffset rescue 0
        y_check = self.y + offset
        h_check = self.height - offset
        if mousepos[0] >= self.x + v_x && mousepos[0] < self.x + v_x + self.width &&
           mousepos[1] >= y_check + v_y && mousepos[1] < y_check + v_y + h_check
          @bag_drag_start_x = mousepos[0]
          @bag_drag_start_y = mousepos[1]
          @bag_drag_start_index = @index
          @bag_has_dragged = false
          @bag_drag_active = true
          $mouse_click_handled = true
        end
      end
      
      if Input.press?(Input::MOUSELEFT) && @bag_drag_active && mousepos && @bag_drag_start_x && @bag_drag_start_y && @bag_drag_start_index
        dx = mousepos[0] - @bag_drag_start_x
        dy = mousepos[1] - @bag_drag_start_y
        
        if dy.abs > 10 || dx.abs > 10
          @bag_has_dragged = true
        end
        
        if @bag_has_dragged
          row_height = self.rowHeight rescue 16
          row_height = 16 if row_height <= 0
          
          if dy.abs >= row_height
            rows_to_scroll = (dy / row_height).to_i
            new_index = @bag_drag_start_index - (rows_to_scroll * @column_max)
            new_index = [0, [new_index, @item_max - 1].min].max
            if @index != new_index
              @index = new_index
              pbPlayCursorSE rescue nil
              update_cursor_rect
            end
            @bag_drag_start_y = mousepos[1]
            @bag_drag_start_x = mousepos[0]
            @bag_drag_start_index = @index
          end
        end
      end
      
      if @bag_drag_active && (!Input.press?(Input::MOUSELEFT) || (Input.release?(Input::MOUSELEFT) rescue false))
        if !@bag_has_dragged && mousepos
          viewport = self.viewport rescue nil
          v_x = (viewport && !viewport.disposed?) ? (viewport.rect.x - viewport.ox) : 0
          v_y = (viewport && !viewport.disposed?) ? (viewport.rect.y - viewport.oy) : 0
          border_x = self.respond_to?(:borderX) ? self.borderX : 32
          border_y = self.respond_to?(:borderY) ? self.borderY : 32
          start_x = self.respond_to?(:startX) ? self.startX : border_x / 2
          start_y = self.respond_to?(:startY) ? self.startY : border_y / 2
          offset = pbListYOffset rescue 0
          
          cx = mousepos[0] - (self.x + v_x + start_x)
          cy = mousepos[1] - (self.y + v_y + start_y) - offset
          
          clicked_item = -1
          top = self.top_item
          limit = [top + self.page_item_max, @item_max].min
          (top...limit).each do |i|
            rect = self.itemRect(i)
            if cx >= rect.x && cx < rect.x + rect.width &&
               cy >= rect.y && cy < rect.y + rect.height
              clicked_item = i
              break
            end
          end
          
          if clicked_item >= 0
            if @index == clicked_item
              pbPlayDecisionSE rescue nil
              $touch_use_ticks = 2
              $mouse_click_handled = true
              
              # if defined?($anil_debug_log_enabled) && $anil_debug_log_enabled
              #   log_line = "[#{Time.now.strftime('%H:%M:%S')}] BAG DECISION CLICK - Item: #{clicked_item} | Mouse: (#{mousepos[0]}, #{mousepos[1]})\n"
              #   File.open("mouse_clicks_log.txt", "a") { |f| f.write(log_line) } rescue nil
              # end
            else
              @index = clicked_item
              pbPlayCursorSE rescue nil
              update_cursor_rect
              $mouse_click_handled = true
              
              # if defined?($anil_debug_log_enabled) && $anil_debug_log_enabled
              #   log_line = "[#{Time.now.strftime('%H:%M:%S')}] BAG CURSOR CLICK - Item: #{clicked_item} | Mouse: (#{mousepos[0]}, #{mousepos[1]})\n"
              #   File.open("mouse_clicks_log.txt", "a") { |f| f.write(log_line) } rescue nil
              # end
            end
          else
            $mouse_click_handled = true
          end
        end
        @bag_drag_start_x = nil
        @bag_drag_start_y = nil
        @bag_drag_start_index = nil
        @bag_has_dragged = false
        @bag_drag_active = false
      end
    end
    
    # Executa o update original com bypass de cliques nativos do mouseleft para evitar conflito
    $bypass_original_selectable_mouse = true
    begin
      touch_bag_update
    ensure
      $bypass_original_selectable_mouse = false
      $disable_selectable_mouse = false
    end
  end
end
