#===============================================================================
# MOD: 061_Menu_Touch_Modular.rb
#-------------------------------------------------------------------------------
# Adiciona controles de toque e clique do mouse genéricos para todos os menus do jogo. Habilita
# clique de toque no menu de pausa (aberto por X), e corrige o bug de clique
# na mochila usando offsets dinâmicos.
#===============================================================================

# 1. Ajuste no Input removido (consolidado robustamente em 0012_Input.rb)

# 2. Propriedade de offset dinâmico, arrasto suave e ativação por soltura na lista de SpriteWindow_Selectable
class SpriteWindow_Selectable < SpriteWindow_Base
  alias mouse_orig_update update unless method_defined?(:mouse_orig_update)
  alias touch_priv_update_cursor_rect priv_update_cursor_rect unless method_defined?(:touch_priv_update_cursor_rect)
  
  def priv_update_cursor_rect(force = false)
    if $bypass_centering_scroll
      if @index >= 0
        row = @index / @column_max
        dorefresh = false
        if row < self.top_row
          self.top_row = row
          dorefresh = true
        elsif row >= self.top_row + self.page_row_max
          self.top_row = row - self.page_row_max + 1
          dorefresh = true
        end
        cursor_width = (self.width - self.borderX) / @column_max
        x = self.index % @column_max * (cursor_width + @column_spacing)
        y = (self.index / @column_max * @row_height) - @virtualOy
        self.cursor_rect.set(x, y, cursor_width, @row_height)
        self.refresh if dorefresh || force
      end
    else
      touch_priv_update_cursor_rect(force)
    end
  end

  def log_bag(msg)
    # Disabled to save CPU and Disk I/O
  end

  def pbListYOffset
    return 0
  end

  def update
    if (self.active && self.visible rescue false)
      $active_selectable_window_exists = true
    else
      @global_drag_start_x = nil
      @global_drag_start_y = nil
      @global_drag_start_index = nil
      @global_drag_time = nil
      @global_has_dragged = false
      @global_drag_active = false
    end
    if self.is_a?(Window_PokemonBag) || self.is_a?(Window_CommandPokemon)
      $disable_selectable_mouse = true
    end
    # Executa a nossa própria lógica de toque/arrasto e clique de soltura
    if self.active && @item_max > 0 && @index >= 0 && !@ignore_input && !$disable_selectable_mouse
      @global_drag_start_x ||= nil
      @global_drag_start_y ||= nil
      @global_drag_start_index ||= nil
      @global_drag_time ||= nil
      @global_has_dragged ||= false
      @global_drag_active ||= false
      
      mousepos = Mouse.getMousePos
      
      if Input.trigger?(Input::MOUSELEFT) && mousepos
        viewport = self.viewport rescue nil
        v_x = (viewport && !viewport.disposed?) ? (viewport.rect.x - viewport.ox) : 0
        v_y = (viewport && !viewport.disposed?) ? (viewport.rect.y - viewport.oy) : 0
        offset = pbListYOffset rescue 0
        y_check = self.y + offset
        h_check = self.height - offset
        
        log_bag("MOUSE TRIGGER MOUSELEFT: pos=(#{mousepos[0]}, #{mousepos[1]}) | window_y=#{self.y}, y_check=#{y_check}, window_h=#{self.height}, h_check=#{h_check}")
        
        if mousepos[0] >= self.x + v_x && mousepos[0] < self.x + v_x + self.width &&
           mousepos[1] >= y_check + v_y && mousepos[1] < y_check + v_y + h_check
          @global_drag_start_x = mousepos[0]
          @global_drag_start_y = mousepos[1]
          @global_drag_time = System.uptime
          
          # Calcula o item que o usuário tocou inicialmente como ponto de partida
          border_x = self.respond_to?(:borderX) ? self.borderX : 32
          border_y = self.respond_to?(:borderY) ? self.borderY : 32
          start_x = self.respond_to?(:startX) ? self.startX : border_x / 2
          start_y = self.respond_to?(:startY) ? self.startY : border_y / 2
          
          cx = mousepos[0] - (self.x + v_x + start_x)
          cy = mousepos[1] - (self.y + v_y + start_y)
          cy -= offset unless self.is_a?(Window_PokemonBag)
          
          clicked_item = -1
          top = self.top_item
          limit = [top + self.page_item_max, @item_max].min
          (top...limit).each do |i|
            rect = self.itemRect(i)
            if cx >= rect.x && cx < rect.x + rect.width &&
               cy >= rect.y && cy < rect.y + rect.height
              clicked_item = i
              $item_or_button_clicked = true
              break
            end
          end
          
          @global_drag_start_index = clicked_item >= 0 ? clicked_item : @index
          @global_has_dragged = false
          @global_drag_active = true
          $mouse_click_handled = true
          
          log_bag("MOUSELEFT DOWN ACCEPTED: clicked_item=#{clicked_item} | @global_drag_start_index=#{@global_drag_start_index} | @index=#{@index}")
        else
          log_bag("MOUSELEFT DOWN IGNORED (outside bounds)")
        end
      end
      
      if Input.press?(Input::MOUSELEFT) && @global_drag_active && mousepos && @global_drag_start_x && @global_drag_start_y && @global_drag_start_index
        dx = mousepos[0] - @global_drag_start_x
        dy = mousepos[1] - @global_drag_start_y
        
        # Filtro de tempo: evita transição acidental para arrasto em cliques muito rápidos (< 150ms)
        @global_drag_time ||= System.uptime
        elapsed = System.uptime - @global_drag_time
        
        if elapsed > 0.15
          drag_threshold = self.is_a?(Window_PokemonBag) ? 24 : 10
          if dy.abs > drag_threshold || dx.abs > drag_threshold
            unless @global_has_dragged
              log_bag("DRAG COMMENCED: dx=#{dx}, dy=#{dy} | threshold=#{drag_threshold} | elapsed=#{elapsed}s")
            end
            @global_has_dragged = true
          end
        end
        
        if @global_has_dragged
          threshold = self.rowHeight / 2 rescue 16
          threshold = 16 if threshold <= 0
          
          if dy.abs >= threshold
            rows_to_scroll = (dy / threshold).to_i
            new_index = @global_drag_start_index - (rows_to_scroll * @column_max)
            new_index = [0, [new_index, @item_max - 1].min].max
            if @index != new_index
              log_bag("DRAG SCROLLING: new_index=#{new_index} (was #{@index}) | rows_to_scroll=#{rows_to_scroll} | top_row=#{self.top_row}")
              $bypass_centering_scroll = true
              begin
                @index = new_index
                pbPlayCursorSE rescue nil
                update_cursor_rect
              ensure
                $bypass_centering_scroll = false
              end
            end
            @global_drag_start_y = mousepos[1]
            @global_drag_start_x = mousepos[0]
            @global_drag_start_index = @index
          end
        end
      end
      
      # Detecta release (soltura) do clique
      if @global_drag_active && (!Input.press?(Input::MOUSELEFT) || (Input.release?(Input::MOUSELEFT) rescue false))
        log_bag("MOUSE RELEASE DETECTED: mousepos=#{(mousepos.nil? ? 'nil' : mousepos.inspect)} | has_dragged=#{@global_has_dragged}")
        if !@global_has_dragged && mousepos
          # Foi um clique simples (tap)! Localiza o item clicado e ativa
          viewport = self.viewport rescue nil
          v_x = (viewport && !viewport.disposed?) ? (viewport.rect.x - viewport.ox) : 0
          v_y = (viewport && !viewport.disposed?) ? (viewport.rect.y - viewport.oy) : 0
          border_x = self.respond_to?(:borderX) ? self.borderX : 32
          border_y = self.respond_to?(:borderY) ? self.borderY : 32
          start_x = self.respond_to?(:startX) ? self.startX : border_x / 2
          start_y = self.respond_to?(:startY) ? self.startY : border_y / 2
          offset = pbListYOffset rescue 0
          
          cx = mousepos[0] - (self.x + v_x + start_x)
          cy = mousepos[1] - (self.y + v_y + start_y)
          cy -= offset unless self.is_a?(Window_PokemonBag)
          
          clicked_item = -1
          top = self.top_item
          limit = [top + self.page_item_max, @item_max].min
          
          log_bag("RELEASE TAP CALCULATION: cx=#{cx}, cy=#{cy} | top_item=#{top}, limit=#{limit} | @item_max=#{@item_max}")
          
          (top...limit).each do |i|
            rect = self.itemRect(i)
            log_bag("Checking item #{i}: rect=(x:#{rect.x}, y:#{rect.y}, w:#{rect.width}, h:#{rect.height})")
            if cx >= rect.x && cx < rect.x + rect.width &&
               cy >= rect.y && cy < rect.y + rect.height
              clicked_item = i
              break
            end
          end
          
          log_bag("RELEASE TAP RESULT: clicked_item=#{clicked_item} | current_index=#{@index}")
          
          if clicked_item >= 0
            $item_or_button_clicked = true
            if @index == clicked_item
              log_bag("TAP ACTION: Selected again -> trigger USE")
              pbPlayDecisionSE rescue nil
              $touch_use_ticks = 2
              $mouse_click_handled = true
            else
              log_bag("TAP ACTION: Focus new item -> update index to #{clicked_item}")
              $bypass_centering_scroll = true
              begin
                @index = clicked_item
                pbPlayCursorSE rescue nil
                update_cursor_rect rescue nil
              ensure
                $bypass_centering_scroll = false
              end
              $mouse_click_handled = true
            end
            
            # Log click details for analysis
            raw_x = Input.mouse_x
            raw_y = Input.mouse_y
            # if defined?($anil_debug_log_enabled) && $anil_debug_log_enabled
            #   File.open("mouse_clicks_log.txt", "a") { |f| f.write(log_line) } rescue nil
            # end
          else
            log_bag("TAP ACTION: Empty area clicked (no item matched)")
            # Clicou na area vazia da lista -> Volta!
            unless self.is_a?(Window_PokemonBag)
              pbPlayCancelSE rescue nil
              $touch_back_ticks = 2
            end
            $mouse_click_handled = true
          end
        end
        @global_drag_start_x = nil
        @global_drag_start_y = nil
        @global_drag_start_index = nil
        @global_drag_time = nil
        @global_has_dragged = false
        @global_drag_active = false
      end
    end
    
    # Desativa temporariamente a detecção original de clique e arrasto para evitar conflito
    $disable_selectable_drag = true
    $bypass_original_selectable_mouse = true
    
    offset = pbListYOffset rescue 0
    if offset > 0
      old_y = self.y
      old_height = self.height
      self.y = old_y + offset
      self.height = old_height - offset
      begin
        mouse_orig_update
      ensure
        self.y = old_y
        self.height = old_height
        $disable_selectable_mouse = false
        $disable_selectable_drag = false
        $bypass_original_selectable_mouse = false
      end
    else
      begin
        mouse_orig_update
      ensure
        $disable_selectable_mouse = false
        $disable_selectable_drag = false
        $bypass_original_selectable_mouse = false
      end
    end
  end
end


# 3. Sobrescrever pbChooseItem removida para usar o script original 0408_0408_Bag_with_interactuable_party.rb

# 4. Integração de clique e toque nos menus de batalha (Runtime Hook tardio para evitar sobrescrita por Plugins)
class Battle::Scene::MenuBase
  attr_reader :sprites
end

class Battle::Scene
  class << self
    attr_accessor :mouse_touch_overrides_applied
  end

  alias mouse_touch_orig_initialize initialize unless method_defined?(:mouse_touch_orig_initialize)
  def initialize(*args)
    mouse_touch_orig_initialize(*args)
    unless Battle::Scene.mouse_touch_overrides_applied
      Battle::Scene.apply_mouse_touch_overrides
      Battle::Scene.mouse_touch_overrides_applied = true
    end
  end

  def self.apply_mouse_touch_overrides
    class_eval do
      # Redefinição de pbCommandMenuEx com suporte total a:
      # - Clique de alta precisão (PC/JoiPlay)
      # - Enhanced Battle UI prompt & info menu (JUMPUP/JUMPDOWN)
      # - Co-op online LAN synchronization
      def pbCommandMenuEx(idxBattler, texts, mode = 0)
        pbRefreshUIPrompt(idxBattler, COMMAND_BOX) rescue nil
        pbShowWindow(COMMAND_BOX)
        cw = @sprites["commandWindow"]
        cw.setTexts(texts)
        cw.setIndexAndMode(@lastCmd[idxBattler], mode)
        pbSelectBattler(idxBattler)
        ret = -1
        promptTimer = System.uptime rescue 0
        loop do
          $active_selectable_window_exists = true
          # Sincronização online/co-op
          if self.respond_to?(:anil_wait_for_remote_manual_unlock)
            anil_wait_for_remote_manual_unlock rescue nil
          end
          
          oldIndex = cw.index
          pbUpdate(cw)
          
          if defined?(Settings::UI_PROMPT_DISPLAY) && Settings::UI_PROMPT_DISPLAY == 2 && (pbShowingPrompt? rescue false)
            if System.uptime - promptTimer > 2
              pbToggleUIPrompt rescue nil
            end
          end
          
          # Detecção de toque/clique nos botões de comando da batalha
          if Input.trigger?(Input::MOUSELEFT)
            mousepos = Mouse.getMousePos
            if mousepos
              $mouse_click_handled = true
              clicked_prompt = false
              
              prompts = @sprites["enhancedUIPrompts"]
              if prompts && prompts.visible && prompts.x >= -20
                viewport = prompts.viewport rescue nil
                v_x = (viewport && !viewport.disposed?) ? (viewport.rect.x - viewport.ox) : 0
                v_y = (viewport && !viewport.disposed?) ? (viewport.rect.y - viewport.oy) : 0
                px = prompts.x + v_x
                py = prompts.y + v_y
                p_w = 164
                bg_sprite = prompts.instance_variable_get(:@bgSprite)
                p_h = bg_sprite ? bg_sprite.src_rect.height : 56
                if mousepos[0] >= px && mousepos[0] < px + p_w && mousepos[1] >= py && mousepos[1] < py + p_h
                  $item_or_button_clicked = true
                  if mousepos[1] >= py && mousepos[1] < py + 28
                    $touch_input_trigger_jumpup = true
                  elsif p_h > 28 && mousepos[1] >= py + 28 && mousepos[1] < py + 56
                    $touch_input_trigger_jumpdown = true
                  end
                  clicked_prompt = true
                end
              end
              
              unless clicked_prompt
                4.times do |i|
                  button = cw.sprites["button_#{i}"] rescue nil
                  if button && !button.disposed? && button.visible
                    bw = button.src_rect.width
                    bh = button.src_rect.height
                    if Mouse.is_over_sprite?(button, mousepos[0], mousepos[1], bw, bh)
                      $item_or_button_clicked = true
                      if cw.index == i
                        pbPlayDecisionSE
                        ret = i
                        @lastCmd[idxBattler] = ret
                      else
                        cw.index = i
                        pbPlayCursorSE
                      end
                      break
                    end
                  end
                end
              end
              break if ret >= 0
            end
          end

          # Teclado/Direcionais
          if Input.trigger?(Input::LEFT)
            cw.index -= 1 if (cw.index & 1) == 1
          elsif Input.trigger?(Input::RIGHT)
            cw.index += 1 if (cw.index & 1) == 0
          elsif Input.trigger?(Input::UP)
            cw.index -= 2 if (cw.index & 2) == 2
          elsif Input.trigger?(Input::DOWN)
            cw.index += 2 if (cw.index & 2) == 0
          end
          pbPlayCursorSE if cw.index != oldIndex
          
          if Input.trigger?(Input::USE)
            pbPlayDecisionSE
            ret = cw.index
            @lastCmd[idxBattler] = ret
            break
          elsif Input.trigger?(Input::BACK) && mode > 0
            pbPlayCancelSE
            break
          elsif Input.trigger?(Input::F9) && $DEBUG
            pbPlayDecisionSE
            pbHideInfoUI rescue nil
            ret = -2
            break
          # Enhanced Battle UI selection menu triggers
          elsif Input.trigger?(Input::JUMPUP) && !(pbInSafari? rescue false)
            if self.respond_to?(:pbToggleBattleInfo)
              pbToggleBattleInfo
              promptTimer = System.uptime
            end
          elsif Input.trigger?(Input::JUMPDOWN) && !(pbInSafari? rescue false)
            if self.respond_to?(:pbToggleBallInfo)
              if pbToggleBallInfo(idxBattler)
                ret = 1
                break
              end
              promptTimer = System.uptime
            end
          end
        end
        return ret
      end

      # Redefinição de pbFightMenu com suporte total a:
      # - Clique de alta precisão nos botões de movimentos
      # - Yields flexíveis compatíveis com DBK e Essentials original
      # - Botão de Ação Especial (Mega, Z-Move, Dynamax, Tera) e Shift
      # - Co-op online LAN synchronization
      # Compact coach HUD. Kept separate from the move window so custom battle
      # UI mods cannot overwrite it during FightMenu#refresh.
      def competitive_coach_show(idxBattler)
        competitive_coach_hide
        rec = @battle.competitive_coach_recommendation(idxBattler) rescue nil
        return if !rec
        sprite = BitmapSprite.new(356, 46, @viewport)
        sprite.x = (Graphics.width - 356) / 2
        sprite.y = 4
        sprite.z = 99999
        bmp = sprite.bitmap
        bmp.fill_rect(0, 0, 356, 46, Color.new(0, 0, 0, 176))
        pbSetNarrowFont(bmp) rescue nil
        best = rec[:best].to_s
        alt  = rec[:alternative].to_s
        best = best[0, 34] + "..." if best.length > 37
        alt  = alt[0, 31] + "..." if alt.length > 34
        base = Color.new(248, 248, 248)
        shadow = Color.new(64, 64, 64)
        accent = Color.new(120, 248, 160)
        pbDrawTextPositions(bmp, [
          ["COACH" + (rec[:confidence_dots] ? " " + ("*" * rec[:confidence_dots].to_i) : ""), 8, 2, :left, accent, shadow],
          [best, 78, 2, :left, base, shadow],
          [(rec[:warning] ? rec[:warning].to_s : "ALT: #{alt}"), 8, 23, :left, base, shadow]
        ]) rescue nil
        @sprites["competitiveCoach"] = sprite
      rescue => e
        PBDebug.log("[CompetitiveCoachHUD] #{e.class}: #{e.message}") rescue nil
      end

      def competitive_coach_hide
        spr = @sprites["competitiveCoach"] rescue nil
        if spr
          spr.dispose rescue nil
          @sprites.delete("competitiveCoach") rescue nil
        end
      end

      def pbFightMenu(idxBattler, specialAction = nil)
        megaEvoPossible = specialAction.is_a?(TrueClass) || specialAction.is_a?(FalseClass) ? specialAction : false
        specialActionObj = specialAction.is_a?(Symbol) || (defined?(Battle::SpecialAction) && specialAction.is_a?(Battle::SpecialAction)) ? specialAction : nil
        
        battler = @battle.battlers[idxBattler]
        cw = @sprites["fightWindow"]
        cw.battler = battler
        moveIndex = 0
        if battler.moves[@lastMove[idxBattler]]&.id
          moveIndex = @lastMove[idxBattler]
        end
        
        if cw.respond_to?(:shiftMode=)
          cw.shiftMode = (@battle.pbCanShift?(idxBattler)) ? 1 : 0
        end
        
        if specialActionObj
          cw.setIndexAndMode(moveIndex, 1)
          pbSetSpecialActionModes(idxBattler, specialActionObj, cw) rescue nil
        else
          cw.setIndexAndMode(moveIndex, megaEvoPossible ? 1 : 0)
        end
        
        cw.refresh rescue nil
        competitive_coach_show(idxBattler) rescue nil
        needFullRefresh = true
        needRefresh = false
        
        loop do
          $active_selectable_window_exists = true
          if needFullRefresh
            pbShowWindow(FIGHT_BOX)
            pbSelectBattler(idxBattler)
            needFullRefresh = false
          end
          
          if needRefresh
            if specialActionObj
              newMode = (@battle.pbBattleMechanicIsRegistered?(idxBattler, specialActionObj)) ? 2 : 1 rescue 1
              if newMode != cw.mode
                cw.mode = newMode
                pbFightMenu_Update(battler, specialActionObj, cw) rescue nil
                cw.refresh rescue nil
              end
            elsif megaEvoPossible
              newMode = (@battle.pbRegisteredMegaEvolution?(idxBattler)) ? 2 : 1 rescue 1
              cw.mode = newMode if newMode != cw.mode rescue nil
            end
            needRefresh = false
          end
          
          # Sincronização online/co-op
          if self.respond_to?(:anil_wait_for_remote_manual_unlock)
            begin
              if anil_wait_for_remote_manual_unlock
                needFullRefresh = true
                next
              end
            rescue
            end
          end
          
          oldIndex = cw.index
          pbUpdate(cw)
          
          # Detecção de toque/clique na tela de luta da batalha
          if Input.trigger?(Input::MOUSELEFT)
            mousepos = Mouse.getMousePos
            if mousepos
              $mouse_click_handled = true
              clicked_prompt = false
              
              prompts = @sprites["enhancedUIPrompts"]
              if prompts && prompts.visible && prompts.x >= -20
                viewport = prompts.viewport rescue nil
                v_x = (viewport && !viewport.disposed?) ? (viewport.rect.x - viewport.ox) : 0
                v_y = (viewport && !viewport.disposed?) ? (viewport.rect.y - viewport.oy) : 0
                px = prompts.x + v_x
                py = prompts.y + v_y
                p_w = 164
                bg_sprite = prompts.instance_variable_get(:@bgSprite)
                p_h = bg_sprite ? bg_sprite.src_rect.height : 56
                if mousepos[0] >= px && mousepos[0] < px + p_w && mousepos[1] >= py && mousepos[1] < py + p_h
                  $item_or_button_clicked = true
                  if mousepos[1] >= py && mousepos[1] < py + 28
                    $touch_input_trigger_jumpup = true
                  elsif p_h > 28 && mousepos[1] >= py + 28 && mousepos[1] < py + 56
                    $touch_input_trigger_jumpdown = true
                  end
                  clicked_prompt = true
                end
              end
              
              unless clicked_prompt
                clicked_any_button = false
                
                # 1. Clique nos movimentos
                clicked_move = -1
                Pokemon::MAX_MOVES.times do |i|
                  button = cw.sprites["button_#{i}"] rescue nil
                  if button && !button.disposed? && button.visible
                     bw = button.src_rect.width
                     bh = button.src_rect.height
                     if Mouse.is_over_sprite?(button, mousepos[0], mousepos[1], bw, bh)
                       $item_or_button_clicked = true
                       clicked_move = i
                       clicked_any_button = true
                       break
                     end
                  end
                end
                
                if clicked_move >= 0
                  if cw.index == clicked_move
                    pbPlayDecisionSE
                    @lastMove[idxBattler] = cw.index
                    if block_given?
                      if specialActionObj
                        break if yield pbFightMenu_Confirm(battler, specialActionObj, cw)
                      else
                        break if yield cw.index
                      end
                    else
                      break if yield cw.index
                    end
                    needFullRefresh = true
                    needRefresh = true
                  else
                    cw.index = clicked_move
                    pbPlayCursorSE
                  end
                end
                
                # 2. Clique no botão de Ação Especial (Mega/Z-Move/Dynamax/Tera)
                action_btn = cw.sprites["actionButton"] || cw.sprites["megaButton"] rescue nil
                if action_btn && !action_btn.disposed? && action_btn.visible
                  aw = action_btn.bitmap ? action_btn.bitmap.width : 130
                  ah = action_btn.src_rect.height rescue 46
                  if Mouse.is_over_sprite?(action_btn, mousepos[0], mousepos[1], aw, ah)
                    $item_or_button_clicked = true
                    clicked_any_button = true
                    if specialActionObj
                      pbPlayActionSE rescue pbPlayDecisionSE
                      break if yield specialActionObj
                      update_zygarde_move(battler, idxBattler, specialActionObj, cw) rescue nil
                      needRefresh = true
                    elsif megaEvoPossible
                      pbPlayDecisionSE
                      break if yield -2
                      needRefresh = true
                    end
                  end
                end
                
                # 3. Clique no botão de Shift (troca)
                shift_btn = cw.sprites["shiftButton"] rescue nil
                if shift_btn && !shift_btn.disposed? && shift_btn.visible
                  sw = shift_btn.bitmap ? shift_btn.bitmap.width : 130
                  sh = shift_btn.src_rect.height rescue 46
                  if Mouse.is_over_sprite?(shift_btn, mousepos[0], mousepos[1], sw, sh)
                    $item_or_button_clicked = true
                    clicked_any_button = true
                    if cw.respond_to?(:shiftMode) && cw.shiftMode > 0
                      pbPlayDecisionSE
                      if block_given?
                        break if yield pbFightMenu_Shift(battler, cw)
                      else
                        break if yield -3
                      end
                      needRefresh = true
                    end
                  end
                end
                
                # Se não clicou em nenhum botão do menu de luta -> Volta!
                if !clicked_any_button
                  pbPlayCancelSE rescue nil
                  $touch_back_ticks = 2
                end
              end
            end
          end

          # Teclado/Direcionais
          if Input.trigger?(Input::LEFT)
            cw.index -= 1 if (cw.index & 1) == 1
          elsif Input.trigger?(Input::RIGHT)
            cw.index += 1 if battler.moves[cw.index + 1]&.id && (cw.index & 1) == 0
          elsif Input.trigger?(Input::UP)
            cw.index -= 2 if (cw.index & 2) == 2
          elsif Input.trigger?(Input::DOWN)
            cw.index += 2 if battler.moves[cw.index + 2]&.id && (cw.index & 2) == 0
          end
          
          if cw.index != oldIndex
            pbPlayCursorSE
            if self.respond_to?(:pbFightMenu_Update)
              pbFightMenu_Update(battler, specialActionObj, cw) rescue nil
            end
          end
          
          # Ações normais de teclado
          if Input.trigger?(Input::USE)
            pbPlayDecisionSE
            if block_given?
              if specialActionObj
                break if yield pbFightMenu_Confirm(battler, specialActionObj, cw)
              else
                break if yield cw.index
              end
            else
              break if yield cw.index
            end
            needFullRefresh = true
            needRefresh = true
          elsif Input.trigger?(Input::BACK)
            if block_given?
              break if yield pbFightMenu_Cancel(battler, specialActionObj, cw)
            else
              pbPlayCancelSE
              break if yield -1
            end
            needRefresh = true
          elsif Input.trigger?(Input::ACTION)
            if specialActionObj
              needFullRefresh = pbFightMenu_Action(battler, specialActionObj, cw) rescue needFullRefresh
              break if yield specialActionObj
              update_zygarde_move(battler, idxBattler, specialActionObj, cw) rescue nil
              needRefresh = true
            elsif megaEvoPossible
              pbPlayDecisionSE
              break if yield -2
              needRefresh = true
            end
          elsif Input.trigger?(Input::SPECIAL)
            if cw.respond_to?(:shiftMode) && cw.shiftMode > 0
              if block_given?
                break if yield pbFightMenu_Shift(battler, cw)
              else
                pbPlayDecisionSE
                break if yield -3
              end
              needRefresh = true
            end
          end
          
          if self.respond_to?(:pbFightMenu_Extra)
            pbFightMenu_Extra(battler, specialActionObj, cw) rescue nil
          end
        end
        
        competitive_coach_hide rescue nil
        if self.respond_to?(:pbFightMenu_End)
          pbFightMenu_End(battler, specialActionObj, cw) rescue nil
        end
        @lastMove[idxBattler] = cw.index
      end

      # Redefinição de pbChooseTarget com suporte a cliques e co-op
      def pbChooseTarget(idxBattler, target_data, visibleSprites = nil)
        pbShowWindow(TARGET_BOX)
        cw = @sprites["targetWindow"]
        texts = pbCreateTargetTexts(idxBattler, target_data)
        mode = (target_data.num_targets == 1) ? 0 : 1
        cw.setDetails(texts, mode)
        cw.index = pbFirstTarget(idxBattler, target_data)
        pbSelectBattler((mode == 0) ? cw.index : texts, 2)
        pbFadeInAndShow(@sprites, visibleSprites) if visibleSprites
        ret = -1
        loop do
          $active_selectable_window_exists = true
          oldIndex = cw.index
          pbUpdate(cw)
          
          # Detecção de toque/clique nos alvos da batalha
          if Input.trigger?(Input::MOUSELEFT)
            mousepos = Mouse.getMousePos
            if mousepos
              $mouse_click_handled = true
              clicked_target = -1
              texts.length.times do |i|
                button = cw.sprites["button_#{i}"] rescue nil
                next if !button || button.disposed? || !button.visible
                bw = button.src_rect.width
                bh = button.src_rect.height
                if Mouse.is_over_sprite?(button, mousepos[0], mousepos[1], bw, bh)
                  $item_or_button_clicked = true
                  if texts[i]
                    clicked_target = i
                    break
                  end
                end
              end
              
              if clicked_target >= 0
                if mode == 0
                  if cw.index == clicked_target
                    ret = cw.index
                    pbPlayDecisionSE
                    break
                  else
                    cw.index = clicked_target
                    pbPlayCursorSE
                    pbSelectBattler(cw.index, 2)
                  end
                else
                  ret = clicked_target
                  pbPlayDecisionSE
                  break
                end
              else
                # Se não clicou em nenhum alvo -> Volta!
                pbPlayCancelSE rescue nil
                $touch_back_ticks = 2
              end
            end
          end

          # Teclado/Direcionais
          if mode == 0
            if Input.trigger?(Input::LEFT) || Input.trigger?(Input::RIGHT)
              inc = (cw.index.even?) ? -2 : 2
              inc *= -1 if Input.trigger?(Input::RIGHT)
              indexLength = @battle.sideSizes[cw.index % 2] * 2
              newIndex = cw.index
              loop do
                newIndex += inc
                break if newIndex < 0 || newIndex >= indexLength
                next if texts[newIndex].nil?
                cw.index = newIndex
                break
              end
            elsif (Input.trigger?(Input::UP) && cw.index.even?) ||
                  (Input.trigger?(Input::DOWN) && cw.index.odd?)
              tryIndex = @battle.pbGetOpposingIndicesInOrder(cw.index)
              tryIndex.each do |idxBattlerTry|
                next if texts[idxBattlerTry].nil?
                cw.index = idxBattlerTry
                break
              end
            end
            if cw.index != oldIndex
              pbPlayCursorSE
              pbSelectBattler(cw.index, 2)
            end
          end
          
          if Input.trigger?(Input::USE)
            ret = cw.index
            pbPlayDecisionSE
            break
          elsif Input.trigger?(Input::BACK)
            ret = -1
            pbPlayCancelSE
            break
          end
        end
        pbSelectBattler(-1)
        return ret
      end

      # Redefinição de pbSelectBallInfo com suporte completo a clique/toque
      def pbSelectBallInfo(idxBattler, pocket)
        return false if @enhancedUIToggle != :ball
        pbHideUIPrompt
        useBall = false
        showDesc = false
        items = $bag.pockets[pocket].clone
        items.push([nil])
        items.unshift([nil])
        index = $bag.last_viewed_index(pocket) + 1
        maxIdx = items.length - 1
        battler = @battle.battlers[idxBattler].pbDirectOpposing(true)
        pbUpdateBallSelection(items, index, showDesc)
        @sprites["leftarrow"].x = 174
        @sprites["leftarrow"].y = @sprites["ball_icon0"].y
        @sprites["rightarrow"].x = 298
        @sprites["rightarrow"].y = @sprites["ball_icon0"].y
        loop do
          pbUpdate
          pbUpdateInfoSprites
          dorefresh = false
          item = items[index][0]
          @sprites["leftarrow"].visible = index > 0
          @sprites["rightarrow"].visible = index < maxIdx

          # Detecção de cliques de toque/mouse no menu de Pokébola
          if Input.trigger?(Input::MOUSELEFT)
            mousepos = Mouse.getMousePos
            if mousepos
              $mouse_click_handled = true
              mx = mousepos[0]
              my = mousepos[1]
              ypos = @sprites["messageBox"].y - 128
              
              # 1. Clique na seta esquerda
              left_arrow = @sprites["leftarrow"]
              if left_arrow && left_arrow.visible && !left_arrow.disposed?
                if Mouse.is_over_sprite?(left_arrow, mx, my)
                  $item_or_button_clicked = true
                  if index > 0
                    index -= 1
                    pbPlayCursorSE
                    dorefresh = true
                  end
                end
              end
              
              # 2. Clique na seta direita
              right_arrow = @sprites["rightarrow"]
              if right_arrow && right_arrow.visible && !right_arrow.disposed?
                if Mouse.is_over_sprite?(right_arrow, mx, my)
                  $item_or_button_clicked = true
                  if index < maxIdx
                    index += 1
                    pbPlayCursorSE
                    dorefresh = true
                  end
                end
              end
              
              # 3. Clique nos ícones de Pokébola e no fundo (círculo amarelo)
              clicked_icon_idx = -1
              5.times do |i|
                icon_sprite = @sprites["ball_icon#{i}"]
                if icon_sprite && icon_sprite.visible && !icon_sprite.disposed?
                  viewport = icon_sprite.viewport rescue nil
                  vx = (viewport && !viewport.disposed?) ? (viewport.rect.x - viewport.ox) : 0
                  vy = (viewport && !viewport.disposed?) ? (viewport.rect.y - viewport.oy) : 0
                  
                  # Centralizado exatamente em (icon_sprite.x, icon_sprite.y) com offset do viewport
                  cx = icon_sprite.x + vx
                  cy = icon_sprite.y + vy
                  
                  # Caixa de 68x68 pixels perfeitamente centrada no ícone e no círculo amarelo
                  if mx >= cx - 34 && mx < cx + 34 && my >= cy - 34 && my < cy + 34
                    $item_or_button_clicked = true
                    clicked_icon_idx = i
                    break
                  end
                end
              end
              
              if clicked_icon_idx >= 0
                new_index = index - 2 + clicked_icon_idx
                if new_index >= 0 && new_index <= maxIdx
                  if new_index != index
                    index = new_index
                    pbPlayCursorSE
                    dorefresh = true
                  else
                    # Clicou no item já selecionado: usa!
                    if !item
                      pbPlayCloseMenuSE
                      break
                    else
                      pbPlayDecisionSE
                      if ItemHandlers.triggerCanUseInBattle(item, battler.pokemon, battler, nil, true, @battle, self)
                        useBall = @battle.pbRegisterItem(idxBattler, item, battler.index)
                        $bag.set_last_viewed_index(pocket, index - 1)
                        break
                      end
                      pbShowWindow(COMMAND_BOX)
                    end
                  end
                end
              end
              
              # 4. Clique na área do botão Z: Detalles
              textY = (showDesc) ? ypos - 55 : ypos + 14
              if mx >= Graphics.width - 120 && my >= textY - 10 && my < textY + 30
                $item_or_button_clicked = true
                showDesc = !showDesc
                pbPlayDecisionSE
                dorefresh = true
              end
              
              # 5. Clique fora da área do menu de pokébola -> cancela/fecha!
              min_y = showDesc ? ypos - 69 : ypos
              max_y = @sprites["messageBox"].y
              if my < min_y || my >= max_y
                pbPlayCloseMenuSE
                break
              end
            end
          end

          # Input por teclado/hotkeys originais
          if Input.trigger?(Input::USE)
            if !item
              pbPlayCloseMenuSE
              break
            end
            pbPlayDecisionSE
            if ItemHandlers.triggerCanUseInBattle(item, battler.pokemon, battler, nil, true, @battle, self)
              useBall = @battle.pbRegisterItem(idxBattler, item, battler.index)
              $bag.set_last_viewed_index(pocket, index - 1)
              break
            end
            pbShowWindow(COMMAND_BOX)
          elsif Input.trigger?(Input::ACTION)
            showDesc = !showDesc
            pbPlayDecisionSE
            dorefresh = true
          elsif Input.trigger?(Input::BACK)
            pbPlayCloseMenuSE
            break
          elsif Input.repeat?(Input::LEFT)
            index -= 1
            index = maxIdx if index < 0
            pbPlayCursorSE
            dorefresh = true
          elsif Input.repeat?(Input::RIGHT) 
            index += 1
            index = 0 if index > maxIdx
            pbPlayCursorSE
            dorefresh = true
          elsif Input.trigger?(Input::JUMPUP) && index > 0
            index = 0
            pbPlayCursorSE
            dorefresh = true
          elsif Input.trigger?(Input::JUMPDOWN) && index < maxIdx
            index = maxIdx
            pbPlayCursorSE
            dorefresh = true
          end
          if dorefresh
            pbUpdateBallSelection(items, index, showDesc)
          end
        end
        pbHideInfoUI
        @sprites["leftarrow"].visible = false
        @sprites["rightarrow"].visible = false
        pbRefreshUIPrompt(idxBattler) if !useBall
        return useBall
      end

      # Redefinição de pbSelectBattlerInfo com suporte completo a clique/toque
      def pbSelectBattlerInfo
        return if @enhancedUIToggle != :battler
        pbHideUIPrompt
        idxSide = 0
        idxPoke = (@battle.pbSideBattlerCount(0) < 3) ? 0 : 1
        battlers = [[], []]
        @battle.allSameSideBattlers.each { |b| battlers[0].push(b) }
        @battle.allOtherSideBattlers.reverse.each { |b| battlers[1].push(b) }
        battler = battlers[idxSide][idxPoke]
        idxBattler = @sprites["enhancedUIPrompts"].battler
        pbShowOutline("info_icon#{battler.index}")
        cw = @sprites["fightWindow"]
        switchUI = 0
        
        loop do
          pbUpdate(cw)
          pbUpdateInfoSprites
          oldSide = idxSide
          oldPoke = idxPoke
          
          do_break = false
          
          # Detecção de cliques de toque/mouse
          if Input.trigger?(Input::MOUSELEFT)
            mousepos = Mouse.getMousePos
            if mousepos
              $mouse_click_handled = true
              mx = mousepos[0]
              my = mousepos[1]
              
              clicked_battler = false
              
              # Verificar cliques nos battlers
              2.times do |side|
                count = @battle.pbSideBattlerCount(side)
                count.times do |i|
                  # Calcular as mesmas coordenadas do select_cursor
                  case side
                  when 0 # Player side
                    case count
                    when 1 then bgX = 173
                    when 2 then bgX = 68 + (208 * i)
                    when 3 then bgX = 4 + (169 * i)
                    end
                    bgY = 68 + 114 - 28 # ypos + 114 - 28 = 154
                  when 1 # Opponent side
                    case count
                    when 1 then bgX = 173
                    when 2 then bgX = 68 + (208 * i)
                    when 3 then bgX = 4 + (169 * i)
                    end
                    bgY = 68 + 38 - 28 # ypos + 38 - 28 = 78
                  end
                  
                  if mx >= bgX && mx < bgX + 166 && my >= bgY && my < bgY + 52
                    clicked_battler = true
                    $item_or_button_clicked = true
                    if idxSide == side && idxPoke == i
                      # Clicou no que já estava selecionado -> Confirma (abre info detalhada)
                      pbPlayDecisionSE
                      ret = pbOpenBattlerInfo(battler, battlers)
                      case ret
                      when Array
                        idxSide, idxPoke = ret[0], ret[1]
                        battler = battlers[idxSide][idxPoke]
                        pbUpdateBattlerSelection(idxSide, idxPoke)
                        pbShowOutline("info_icon#{battler.index}")
                      when Numeric
                        switchUI = ret
                        do_break = true
                      when nil
                        do_break = true
                      end
                    else
                      # Clicou em outro -> Foca
                      idxSide = side
                      idxPoke = i
                      pbPlayCursorSE
                    end
                    break
                  end
                end
                break if clicked_battler || do_break
              end
              
              # Se não clicou em nenhum battler e clicou fora do menu de seleção
              if !clicked_battler && !do_break
                if my < 60 || my >= 270
                  switchUI = 0
                  do_break = true
                end
              end
            end
          end
          
          break if do_break
          
          # Inputs por teclado originais
          if Input.trigger?(Input::BACK) || Input.trigger?(Input::JUMPUP)
            switchUI = 0
            break
          elsif Input.trigger?(Input::USE)
            pbPlayDecisionSE
            ret = pbOpenBattlerInfo(battler, battlers)
            case ret
            when Array
              idxSide, idxPoke = ret[0], ret[1]
              battler = battlers[idxSide][idxPoke]
              pbUpdateBattlerSelection(idxSide, idxPoke)
              pbShowOutline("info_icon#{battler.index}")
            when Numeric
              switchUI = ret
              break
            when nil
              break
            end
          elsif Input.trigger?(Input::LEFT) && @battle.pbSideBattlerCount(idxSide) > 1
            idxPoke -= 1
            idxPoke = @battle.pbSideBattlerCount(idxSide) - 1 if idxPoke < 0
            pbPlayCursorSE
          elsif Input.trigger?(Input::RIGHT) && @battle.pbSideBattlerCount(idxSide) > 1
            idxPoke += 1
            idxPoke = 0 if idxPoke > @battle.pbSideBattlerCount(idxSide) - 1
            pbPlayCursorSE
          elsif Input.trigger?(Input::UP) || Input.trigger?(Input::DOWN)
            idxSide = (idxSide == 0) ? 1 : 0
            if idxPoke > @battle.pbSideBattlerCount(idxSide) - 1
              until idxPoke == @battle.pbSideBattlerCount(idxSide) - 1
                idxPoke -= 1
              end
            end
            pbPlayCursorSE
          elsif Input.trigger?(Input::JUMPDOWN)
            if cw.visible
              switchUI = 1
              break
            elsif @battle.pbCanUsePokeBall?(idxBattler)
              switchUI = 2
              break
            end
          end
          
          if oldSide != idxSide || oldPoke != idxPoke
            pbUpdateBattlerSelection(idxSide, idxPoke)
            battler = battlers[idxSide][idxPoke]
            @battle.allBattlers.each do |b|
              showOutline = b.index == battler.index
              pbShowOutline("info_icon#{b.index}", showOutline)
            end
          end
        end
        
        pbHideInfoUI
        pbUpdateBattlerIcons
        case switchUI
        when 0 then pbPlayCloseMenuSE; pbRefreshUIPrompt
        when 1 then pbToggleMoveInfo(cw.battler, :none, cw)
        when 2 then pbToggleBallInfo(idxBattler)
        end
      end

      # Redefinição de pbOpenBattlerInfo com suporte completo a clique/toque
      def pbOpenBattlerInfo(battler, battlers)
        return if @enhancedUIToggle != :battler
        ret = nil
        idx = 0
        battlerTotal = battlers.flatten
        for i in 0...battlerTotal.length
          idx = i if battler == battlerTotal[i]
        end
        maxSize = battlerTotal.length - 1
        idxEffect = 0
        effects = pbGetDisplayEffects(battler)
        effctSize = effects.length - 1
        pbUpdateBattlerInfo(battler, effects, idxEffect)
        cw = @sprites["fightWindow"]
        @sprites["leftarrow"].x = -2
        @sprites["leftarrow"].y = 71
        @sprites["leftarrow"].visible = true
        @sprites["rightarrow"].x = Graphics.width - 38
        @sprites["rightarrow"].y = 71
        @sprites["rightarrow"].visible = true
        loop do
          pbUpdate(cw)
          pbUpdateInfoSprites
          doRefresh = false
          doFullRefresh = false

          # 1. Detecção de cliques de toque/mouse
          if Input.trigger?(Input::MOUSELEFT)
            mousepos = Mouse.getMousePos
            if mousepos
              $mouse_click_handled = true
              mx = mousepos[0]
              my = mousepos[1]

              left_arrow = @sprites["leftarrow"]
              right_arrow = @sprites["rightarrow"]

              if left_arrow && left_arrow.visible && !left_arrow.disposed? && Mouse.is_over_sprite?(left_arrow, mx, my)
                $item_or_button_clicked = true
                idx -= 1
                idx = maxSize if idx < 0
                doFullRefresh = true
              elsif right_arrow && right_arrow.visible && !right_arrow.disposed? && Mouse.is_over_sprite?(right_arrow, mx, my)
                $item_or_button_clicked = true
                idx += 1
                idx = 0 if idx > maxSize
                doFullRefresh = true
              elsif mx < 28 || mx >= Graphics.width - 28 || my < 24 || my >= Graphics.height - 24
                pbPlayCloseMenuSE
                break
              end
            end
          end

          # 2. Input por teclado originais
          if Input.trigger?(Input::LEFT)
            idx -= 1
            idx = maxSize if idx < 0
            doFullRefresh = true
          elsif Input.trigger?(Input::RIGHT)
            idx += 1
            idx = 0 if idx > maxSize
            doFullRefresh = true
          elsif Input.repeat?(Input::UP) && effects.length > 1
            idxEffect -= 1
            idxEffect = effctSize if idxEffect < 0
            doRefresh = true
          elsif Input.repeat?(Input::DOWN) && effects.length > 1
            idxEffect += 1
            idxEffect = 0 if idxEffect > effctSize
            doRefresh = true
          elsif Input.trigger?(Input::JUMPDOWN)
            if cw.visible
              ret = 1
              break
            elsif @battle.pbCanUsePokeBall?(@sprites["enhancedUIPrompts"].battler)
              ret = 2
              break
            end
          elsif Input.trigger?(Input::JUMPUP) || Input.trigger?(Input::USE)
            ret = []
            if battler.opposes?
              ret.push(1)
              @battle.allOtherSideBattlers.reverse.each_with_index do |b, i| 
                next if b.index != battler.index
                ret.push(i)
              end
            else
              ret.push(0)
              @battle.allSameSideBattlers.each_with_index do |b, i| 
                next if b.index != battler.index
                ret.push(i)
              end
            end
            pbPlayDecisionSE
            break
          elsif Input.trigger?(Input::BACK)
            pbPlayCloseMenuSE
            break
          end

          if doFullRefresh
            battler = battlerTotal[idx]
            effects = pbGetDisplayEffects(battler)
            effctSize = effects.length - 1
            idxEffect = 0
            doRefresh = true
          end

          if doRefresh
            pbPlayCursorSE
            pbUpdateBattlerInfo(battler, effects, idxEffect)
            doRefresh = false
            doFullRefresh = false
          end
        end
        @sprites["leftarrow"].visible = false
        @sprites["rightarrow"].visible = false
        return ret
      end
    end
  end
end

# 5. Integração de clique e toque no menu Pokegear
class PokemonPokegear_Scene
  alias mouse_orig_pbScene pbScene unless method_defined?(:mouse_orig_pbScene)
  def pbScene
    ret = -1
    loop do
      $active_selectable_window_exists = true
      Graphics.update
      Input.update
      pbUpdate
      
      # Detecção de toque/clique nos botões do Pokegear
      if Input.trigger?(Input::MOUSELEFT)
        mousepos = Mouse.getMousePos
        if mousepos
          $mouse_click_handled = true
          clicked_idx = -1
          @commands.length.times do |i|
            btn = @sprites["button#{i}"]
            next if !btn || btn.disposed?
            bw = btn.bitmap ? btn.bitmap.width : 260
            bh = btn.bitmap ? btn.bitmap.height : 46
            if Mouse.is_over_sprite?(btn, mousepos[0], mousepos[1], bw, bh)
              $item_or_button_clicked = true
              clicked_idx = i
              break
            end
          end
          if clicked_idx >= 0
            if @index == clicked_idx
              pbPlayDecisionSE
              ret = @index
              break
            else
              @index = clicked_idx
              pbPlayCursorSE if @commands.length > 1
            end
          end
        end
      end
      
      if Input.trigger?(Input::BACK)
        pbPlayCloseMenuSE
        break
      elsif Input.trigger?(Input::USE)
        pbPlayDecisionSE
        ret = @index
        break
      elsif Input.trigger?(Input::UP)
        pbPlayCursorSE if @commands.length > 1
        @index -= 1
        @index = @commands.length - 1 if @index < 0
      elsif Input.trigger?(Input::DOWN)
        pbPlayCursorSE if @commands.length > 1
        @index += 1
        @index = 0 if @index >= @commands.length
      end
    end
    return ret
  end
end

# 6. Integração de clique e toque no PC Storage System (PC de Box)
class PokemonStorageScene
  alias mouse_orig_pbSelectBoxInternal pbSelectBoxInternal unless method_defined?(:mouse_orig_pbSelectBoxInternal)
  def pbSelectBoxInternal(party)
    selection = @selection
    pbSetArrow(@sprites["arrow"], selection)
    pbUpdateOverlay(selection)
    pbSetMosaic(selection)
    loop do
      $active_selectable_window_exists = true
      Graphics.update
      Input.update
      
      # Detecção de cliques de toque/mouse no PC de Box
      if Input.trigger?(Input::MOUSELEFT)
        mousepos = Mouse.getMousePos
        if mousepos
          $mouse_click_handled = true
          mx = mousepos[0]
          my = mousepos[1]
          
          # 1. Clique nos 30 Slots da Box
          if mx >= 194 && mx < 482 && my >= 48 && my < 288
            k = ((mx - 194) / 48).to_i
            j = ((my - 48) / 48).to_i
            clicked_idx = j * 6 + k
            if clicked_idx >= 0 && clicked_idx < 30
              $item_or_button_clicked = true
              if selection == clicked_idx
                pbPlayDecisionSE
                @selection = selection
                return [@storage.currentBox, selection]
              else
                selection = clicked_idx
                pbPlayCursorSE
                pbSetArrow(@sprites["arrow"], selection)
                pbUpdateOverlay(selection)
                pbSetMosaic(selection)
              end
            end
            
          # 2. Clique no cabeçalho da Box (Setas de mudar Box e Nome da Box)
          elsif mx >= 184 && mx < 508 && my >= 10 && my < 48
            $item_or_button_clicked = true
            if mx < 240 # Seta Esquerda
              pbPlayCursorSE
              nextbox = (@storage.currentBox + @storage.maxBoxes - 1) % @storage.maxBoxes
              pbSwitchBoxToLeft(nextbox)
              @storage.currentBox = nextbox
              selection = -1
              pbSetArrow(@sprites["arrow"], selection)
              pbUpdateOverlay(selection)
              pbSetMosaic(selection)
            elsif mx > 450 # Seta Direita
              pbPlayCursorSE
              nextbox = (@storage.currentBox + 1) % @storage.maxBoxes
              pbSwitchBoxToRight(nextbox)
              @storage.currentBox = nextbox
              selection = -1
              pbSetArrow(@sprites["arrow"], selection)
              pbUpdateOverlay(selection)
              pbSetMosaic(selection)
            else # Nome da Box
              if selection == -1
                pbPlayDecisionSE
                @selection = selection
                return [-4, -1]
              else
                selection = -1
                pbPlayCursorSE
                pbSetArrow(@sprites["arrow"], selection)
                pbUpdateOverlay(selection)
                pbSetMosaic(selection)
              end
            end
            
          # 3. Clique nos botões inferiores ("Ver Equipo" e "Salir")
          elsif my >= 326 && my < 366
            $item_or_button_clicked = true
            if mx >= 184 && mx < 340 # Ver Equipo
              if selection == -2
                pbPlayDecisionSE
                @selection = selection
                return [-2, -1]
              else
                selection = -2
                pbPlayCursorSE
                pbSetArrow(@sprites["arrow"], selection)
                pbUpdateOverlay(selection)
                pbSetMosaic(selection)
              end
            elsif mx >= 350 && mx < 508 # Salir
              if selection == -3
                pbPlayDecisionSE
                @selection = selection
                return [-3, -1]
              else
                selection = -3
                pbPlayCursorSE
                pbSetArrow(@sprites["arrow"], selection)
                pbUpdateOverlay(selection)
                pbSetMosaic(selection)
              end
            end
          end
        end
      end
      
      key = -1
      key = Input::DOWN if Input.repeat?(Input::DOWN)
      key = Input::RIGHT if Input.repeat?(Input::RIGHT)
      key = Input::LEFT if Input.repeat?(Input::LEFT)
      key = Input::UP if Input.repeat?(Input::UP)
      if key >= 0
        pbPlayCursorSE
        selection = pbChangeSelection(key, selection)
        pbSetArrow(@sprites["arrow"], selection)
        case selection
        when -4
          nextbox = (@storage.currentBox + @storage.maxBoxes - 1) % @storage.maxBoxes
          pbSwitchBoxToLeft(nextbox)
          @storage.currentBox = nextbox
        when -5
          nextbox = (@storage.currentBox + 1) % @storage.maxBoxes
          pbSwitchBoxToRight(nextbox)
          @storage.currentBox = nextbox
        end
        selection = -1 if [-4, -5].include?(selection)
        pbUpdateOverlay(selection)
        pbSetMosaic(selection)
      end
      self.update
      if Input.trigger?(Input::JUMPUP)
        pbPlayCursorSE
        nextbox = (@storage.currentBox + @storage.maxBoxes - 1) % @storage.maxBoxes
        pbSwitchBoxToLeft(nextbox)
        @storage.currentBox = nextbox
        pbUpdateOverlay(selection)
        pbSetMosaic(selection)
      elsif Input.trigger?(Input::JUMPDOWN)
        pbPlayCursorSE
        nextbox = (@storage.currentBox + 1) % @storage.maxBoxes
        pbSwitchBoxToRight(nextbox)
        @storage.currentBox = nextbox
        pbUpdateOverlay(selection)
        pbSetMosaic(selection)
      elsif Input.trigger?(Input::AUX2)
        if selection != -1
          pbPlayCursorSE
          selection = -1
          pbSetArrow(@sprites["arrow"], selection)
          pbUpdateOverlay(selection)
          pbSetMosaic(selection)
        end
      elsif Input.trigger?(Input::SPECIAL)
        pbSearch
      elsif Input.trigger?(Input::ACTION) && @command == 0
        pbPlayDecisionSE
        pbSetQuickSwap(!@quickswap)
      elsif Input.trigger?(Input::BACK)
        @selection = selection
        return nil
      elsif Input.trigger?(Input::USE)
        @selection = selection
        if selection >= 0
          return [@storage.currentBox, selection]
        elsif selection == -1
          return [-4, -1]
        elsif selection == -2
          return [-2, -1]
        elsif selection == -3
          return [-3, -1]
        end
      end
    end
  end

  alias mouse_orig_pbSelectPartyInternal pbSelectPartyInternal unless method_defined?(:mouse_orig_pbSelectPartyInternal)
  def pbSelectPartyInternal(party, depositing)
    selection = @selection
    pbPartySetArrow(@sprites["arrow"], selection)
    pbUpdateOverlay(selection, party)
    pbSetMosaic(selection)
    lastsel = 1
    loop do
      $active_selectable_window_exists = true
      Graphics.update
      Input.update
      
      # Detecção de cliques de toque/mouse no menu pop-up da Party do PC
      if Input.trigger?(Input::MOUSELEFT)
        mousepos = Mouse.getMousePos
        if mousepos
          $mouse_click_handled = true
          mx = mousepos[0]
          my = mousepos[1]
          clicked_idx = -1
          
          # Verificar os 6 slots de Pokémon da Party
          max_party_size.times do |i|
            px = 182 + (18 + (72 * (i % 2)))
            py = 32 + (2 + (16 * (i % 2)) + (64 * (i / 2)))
            pw = 64
            ph = 64
            if mx >= px && mx < px + pw && my >= py && my < py + ph
              clicked_idx = i
              break
            end
          end
          
          # Verificar botão "Atrás"
          if clicked_idx < 0
            if mx >= 200 && mx < 340 && my >= 260 && my < 300
              clicked_idx = max_party_size
            end
          end
          
          if clicked_idx >= 0
            $item_or_button_clicked = true
            if selection == clicked_idx
              pbPlayDecisionSE
              @selection = selection
              if selection == max_party_size
                return -1
              else
                return selection
              end
            else
              selection = clicked_idx
              pbPlayCursorSE
              pbPartySetArrow(@sprites["arrow"], selection)
              lastsel = selection if selection > 0 && selection < max_party_size
              pbUpdateOverlay(selection, party)
              pbSetMosaic(selection)
            end
          end
        end
      end
      
      key = -1
      key = Input::DOWN if Input.repeat?(Input::DOWN)
      key = Input::RIGHT if Input.repeat?(Input::RIGHT)
      key = Input::LEFT if Input.repeat?(Input::LEFT)
      key = Input::UP if Input.repeat?(Input::UP)
      if key >= 0
        pbPlayCursorSE
        newselection = pbPartyChangeSelection(key, selection)
        case newselection
        when -1
          return -1 if !depositing
        when -2
          selection = lastsel
        else
          selection = newselection
        end
        pbPartySetArrow(@sprites["arrow"], selection)
        lastsel = selection if selection > 0
        pbUpdateOverlay(selection, party)
        pbSetMosaic(selection)
      end
      self.update
      if Input.trigger?(Input::ACTION) && @command == 0
        pbPlayDecisionSE
        pbSetQuickSwap(!@quickswap)
      elsif Input.trigger?(Input::BACK)
        @selection = selection
        return -1
      elsif Input.trigger?(Input::USE)
        @selection = selection
        if selection == max_party_size
          return -1
        else
          return selection
        end
      end
    end
  end
end


#===============================================================================
# 5. Suporte a Toque na Tela de Carregar Jogo (Load/Save Screen / Multi Save)
#===============================================================================
class PokemonLoad_Scene
  alias touch_orig_pbStartScene pbStartScene unless method_defined?(:touch_orig_pbStartScene)

  def pbStartScene(commands, show_continue, trainer, stats, map_id)
    # Garante que aplicamos a injeção do pbChoose após o carregamento de todos os plugins
    unless self.class.method_defined?(:touch_hooked_pbChoose)
      self.class.class_eval do
        alias touch_orig_pbChoose pbChoose rescue nil
        
        def pbChoose(commands, continue_idx = 0)
          @sprites["cmdwindow"].commands = commands
          loop do
            $active_selectable_window_exists = true
            Graphics.update
            Input.update
            pbUpdate
            
            # Detecção de toque nos painéis e setas
            if Input.trigger?(Input::MOUSELEFT)
              mousepos = Mouse.getMousePos
              if mousepos
                $mouse_click_handled = true
                # 1. Verificar clique nas setas de troca de Save (esquerda/direita)
                left_arrow = @sprites["leftarrow"]
                if left_arrow && left_arrow.visible && !left_arrow.disposed?
                  if mousepos[0] >= left_arrow.x && mousepos[0] < left_arrow.x + 40 &&
                     mousepos[1] >= left_arrow.y && mousepos[1] < left_arrow.y + 28
                    $item_or_button_clicked = true
                    pbPlayCursorSE rescue nil
                    return -3 # Retorna -3 para trocar para o save à esquerda
                  end
                end
                
                right_arrow = @sprites["rightarrow"]
                if right_arrow && right_arrow.visible && !right_arrow.disposed?
                  if mousepos[0] >= right_arrow.x && mousepos[0] < right_arrow.x + 40 &&
                     mousepos[1] >= right_arrow.y && mousepos[1] < right_arrow.y + 28
                    $item_or_button_clicked = true
                    pbPlayCursorSE rescue nil
                    return -2 # Retorna -2 para trocar para o save à direita
                  end
                end
                
                # 2. Verificar clique nos painéis de comando (Continuar, Partida Nueva, etc.)
                commands.length.times do |i|
                  panel = @sprites["panel#{i}"]
                  next if !panel || panel.disposed?
                  p_w = panel.bitmap ? panel.bitmap.width : 384
                  p_h = panel.bitmap ? panel.bitmap.height : 48
                  
                  if mousepos[0] >= panel.x && mousepos[0] < panel.x + p_w &&
                     mousepos[1] >= panel.y && mousepos[1] < panel.y + p_h
                    $item_or_button_clicked = true
                    if @sprites["cmdwindow"].index == i
                      pbPlayDecisionSE rescue nil
                      return i # Confirma a seleção do painel clicado
                    else
                      @sprites["cmdwindow"].index = i
                      pbPlayCursorSE rescue nil
                    end
                    break
                  end
                end
              end
            end
            
            if Input.trigger?(Input::USE)
              return @sprites["cmdwindow"].index
            elsif @sprites["cmdwindow"].index == continue_idx
              if Input.trigger?(Input::LEFT)
                return -3
              elsif Input.trigger?(Input::RIGHT)
                return -2
              end
            end
          end
        end
        
        define_method(:touch_hooked_pbChoose) { true }
      end
    end
    
    touch_orig_pbStartScene(commands, show_continue, trainer, stats, map_id)
  end
end


#===============================================================================
# 6. Suporte a Arrastar e Clicar na Tela de Opções (Roll de Arrastar e Cliques)
#===============================================================================
class Window_PokemonOption < Window_DrawableCommand
  alias touch_options_update update unless method_defined?(:touch_options_update)
  
  def update
    if self.visible && self.active && @options && @options.length > 0
      @opt_drag_start_y ||= nil
      @opt_drag_start_index ||= nil
      @opt_has_dragged ||= false
      @opt_drag_active ||= false
      
      mousepos = Mouse.getMousePos
      
      # 1. Detectar início do toque / clique do mouse
      if Input.trigger?(Input::MOUSELEFT) && mousepos
        viewport = self.viewport rescue nil
        v_x = (viewport && !viewport.disposed?) ? (viewport.rect.x - viewport.ox) : 0
        v_y = (viewport && !viewport.disposed?) ? (viewport.rect.y - viewport.oy) : 0
        
        # Verifica se o clique está dentro dos limites da janela de opções
        if mousepos[0] >= self.x + v_x && mousepos[0] < self.x + v_x + self.width &&
           mousepos[1] >= self.y + v_y && mousepos[1] < self.y + v_y + self.height
          @opt_drag_start_y = mousepos[1]
          @opt_drag_start_index = self.top_row rescue 0
          @opt_has_dragged = false
          @opt_drag_active = true
          $mouse_click_handled = true
        else
          # Clicou FORA da janela de opções! Volta/Fecha!
          pbPlayCancelSE rescue nil
          $touch_back_ticks = 2
          $mouse_click_handled = true
        end
      end
      
      # 2. Processar arrasto vertical (drag-to-scroll / roll de arrastar)
      if Input.press?(Input::MOUSELEFT) && @opt_drag_active && mousepos && @opt_drag_start_y
        dy = mousepos[1] - @opt_drag_start_y
        if dy.abs > 10
          @opt_has_dragged = true
        end
        
        if @opt_has_dragged
          # Cada 32 pixels de arrasto vertical rola um item da lista
          row_height = @row_height || 32
          rows_to_scroll = (dy / row_height).to_i
          new_top = @opt_drag_start_index - rows_to_scroll
          max_top = [0, self.row_max - self.page_row_max].max rescue 0
          new_top = [0, [new_top, max_top].min].max
          
          if self.top_row != new_top
            self.top_row = new_top
            # Ajusta o índice selecionado para que fique visível na tela
            page_size = self.page_item_max rescue 7
            if self.index < self.top_row
              self.index = self.top_row
            elsif self.index >= self.top_row + page_size
              self.index = self.top_row + page_size - 1
            end
            refresh
          end
        end
      end
      
      # 3. Finalizar clique / Soltar (Tap simples para alterar valores)
      if @opt_drag_active && (!Input.press?(Input::MOUSELEFT) || (Input.release?(Input::MOUSELEFT) rescue false))
        if !@opt_has_dragged && mousepos
          # Foi um clique simples (tap)!
          viewport = self.viewport rescue nil
          v_x = (viewport && !viewport.disposed?) ? (viewport.rect.x - viewport.ox) : 0
          v_y = (viewport && !viewport.disposed?) ? (viewport.rect.y - viewport.oy) : 0
          cx = mousepos[0] - (self.x + v_x + self.startX)
          cy = mousepos[1] - (self.y + v_y + self.startY)
          
          clicked_item = -1
          top = self.top_item
          limit = [top + self.page_item_max, @options.length + 1].min
          (top...limit).each do |i|
            rect = self.itemRect(i)
            if cx >= rect.x && cx < rect.x + rect.width &&
               cy >= rect.y && cy < rect.y + rect.height
              clicked_item = i
              $item_or_button_clicked = true
              break
            end
          end
          
          if clicked_item >= 0
            if self.index == clicked_item
              # Se clicou no item já selecionado e não é o botão de fechar/atrás, avança o valor
              if clicked_item < @options.length
                if !@options[clicked_item].is_a?(ButtonOption)
                  self[clicked_item] = @options[clicked_item].next(self[clicked_item])
                  @value_changed = true
                  pbPlayDecisionSE rescue nil
                  refresh
                elsif @options[clicked_item].is_a?(ButtonOption)
                  # Botão de submenu
                  pbPlayDecisionSE rescue nil
                  $touch_use_ticks = 2
                  $mouse_click_handled = true
                end
              else
                # Clicou em "Cerrar" / "Atrás"
                pbPlayDecisionSE rescue nil
                $touch_use_ticks = 2
                $mouse_click_handled = true
              end
            else
              # Se clicou em outra opção, apenas muda o foco para ela
              self.index = clicked_item
              pbPlayCursorSE rescue nil
              $mouse_click_handled = true
            end
          else
            # Clicou em area vazia da janela de opcoes -> Volta/Fecha!
            pbPlayCancelSE rescue nil
            $touch_back_ticks = 2
            $mouse_click_handled = true
          end
        end
        
        @opt_drag_start_y = nil
        @opt_drag_start_index = nil
        @opt_has_dragged = false
        @opt_drag_active = false
      end
    end
    
    # Desativa temporariamente a detecção modular padrão para evitar conflitos na tela de opções
    if self.visible && self.active
      $disable_selectable_mouse = true
      begin
        touch_options_update
      ensure
        $disable_selectable_mouse = false
      end
    else
      touch_options_update
    end
  end
end


#===============================================================================
# 8. Suporte a Clique Direto no Menu de Pausa (Window_CommandPokemon)
#===============================================================================
class Window_CommandPokemon < Window_DrawableCommand
  alias touch_pause_menu_update update unless method_defined?(:touch_pause_menu_update)
  
  def update
    @global_drag_start_x = nil
    @global_drag_start_y = nil
    @global_drag_start_index = nil
    @global_has_dragged = false
    @global_drag_active = false
    
    if self.visible && self.active && @commands && @commands.length > 0
      mousepos = Mouse.getMousePos
      if mousepos
        viewport = self.viewport rescue nil
        v_x = (viewport && !viewport.disposed?) ? (viewport.rect.x - viewport.ox) : 0
        v_y = (viewport && !viewport.disposed?) ? (viewport.rect.y - viewport.oy) : 0
        
        # 1. Pressionamento inicial (Toque inicial)
        if Input.trigger?(Input::MOUSELEFT)
          @cmd_drag_start_x = mousepos[0]
          @cmd_drag_start_y = mousepos[1]
          @cmd_drag_start_index = self.index
          @cmd_has_dragged = false
          @cmd_drag_active = true
          $mouse_click_handled = true
        end
        
        # 2. Monitoramento de arrasto enquanto pressiona
        if Input.press?(Input::MOUSELEFT) && @cmd_drag_active && @cmd_drag_start_x && @cmd_drag_start_y
          dx = mousepos[0] - @cmd_drag_start_x
          dy = mousepos[1] - @cmd_drag_start_y
          if dx.abs > 15 || dy.abs > 15
            @cmd_has_dragged = true
          end
        end
        
        # 3. Soltura do clique (Release) - Executa a lógica apenas se for clique estático
        if @cmd_drag_active && (!Input.press?(Input::MOUSELEFT) || (Input.release?(Input::MOUSELEFT) rescue false))
          @cmd_drag_active = false
          
          if !@cmd_has_dragged
            if mousepos[0] >= self.x + v_x && mousepos[0] < self.x + v_x + self.width &&
               mousepos[1] >= self.y + v_y && mousepos[1] < self.y + v_y + self.height
               
              cx = mousepos[0] - (self.x + v_x + self.startX)
              cy = mousepos[1] - (self.y + v_y + self.startY)
              
              clicked_item = -1
              top = self.top_item
              limit = [top + self.page_item_max, @commands.length].min
              (top...limit).each do |i|
                rect = self.itemRect(i)
                if cx >= rect.x && cx < rect.x + rect.width &&
                   cy >= rect.y && cy < rect.y + rect.height
                  clicked_item = i
                  $item_or_button_clicked = true
                  break
                end
              end
              
              if clicked_item >= 0
                if self.index == clicked_item
                  pbPlayDecisionSE rescue nil
                  $touch_use_ticks = 2
                else
                  self.index = clicked_item
                  pbPlayCursorSE rescue nil
                end
              else
                # Clicou em area vazia da janela do menu principal -> Volta!
                pbPlayCancelSE rescue nil
                $touch_back_ticks = 2
              end
            else
              # Clicou fora da janela do Menu de Pausa -> Fecha o menu!
              pbPlayCancelSE rescue nil
              $touch_back_ticks = 2
              $mouse_click_handled = true
            end
          end
        end
      end
    end
    
    touch_pause_menu_update
    
    # Trava o índice no inicial se estiver ativamente arrastando/deslizando
    if @cmd_drag_active && @cmd_has_dragged && @cmd_drag_start_index
      self.index = @cmd_drag_start_index
    end
  end
end


#===============================================================================
# 9. Suporte Dinâmico a Clique Direto no Menu de Pausa Diamond/Pearl (DP_PauseMenu)
#===============================================================================
def touch_apply_dp_pause_menu_overrides
  return if $touch_dp_pause_menu_overrides_applied
  
  if defined?(DP_PauseMenu)
    DP_PauseMenu.class_eval do
      # Cálculo robusto e dinâmico de coordenadas Y dos atalhos
      def touch_get_shortcut_y_positions
        y_positions = {}
        curr_y = 4
        
        # 1. Pokerider
        if $bag.has?(:POKERIDER) && ADD_POKERIDER_SHORTCUT_IN_MENU
          y_positions[:pokerider] = curr_y
          curr_y += 70
        end
        
        # 2. Vial
        if $bag.has?(:VIAL) || $bag.has?(:EMPTYVIAL)
          y_positions[:vial] = curr_y
          curr_y += 70
        end
        
        # 3. Radar
        if $bag.has?(:RADAR) && (!RandomizedChallenge.enabled? || RandomizedChallenge.consistent_wild_encounters?)
          y_positions[:radar] = curr_y
          curr_y += 70
        end
        
        # 4. Repel
        if $bag.has?(:INFREPEL) || $bag.has?(:INFREPELOFF)
          y_positions[:repel] = curr_y
          curr_y += 70
        end
        
        y_positions
      end

      alias touch_orig_update update unless method_defined?(:touch_orig_update)
      def update
        touch_orig_update
        
        # Detecção de toque/mouse no menu principal DP
        if Input.trigger?(Input::MOUSELEFT)
          mousepos = Mouse.getMousePos
          if mousepos
            mx = mousepos[0]
            my = mousepos[1]
            
            # 1. Verificar cliques nas opções do menu principal (x >= 308 && x <= 508)
            if mx >= 308 && mx <= 508
              for i in 0...@count
                y_start = 10 + 48 * i
                if my >= y_start && my < y_start + 48
                  $mouse_click_handled = true
                  $item_or_button_clicked = true
                  if @option == i
                    pbPlayDecisionSE rescue nil
                    @options[@option][3].call
                    Input.update
                  else
                    @option = i
                    pbSEPlay("Voltorb Flip mark") rescue nil
                    $PokemonGlobal.last_menu_index = @option
                    path = @options[@option][2]
                    path = path[$player.gender] if path.is_a?(Array)
                    @sprites[@options[@option][0].to_sym].bmp("Graphics/Pictures/DP Pause Menu/#{path}")
                    @sprites[:sel].y = 10 + 48 * @option
                    @scaling = 0
                    @i = 0
                  end
                  break
                end
              end
              
            # 2. Verificar cliques nos atalhos do lado esquerdo (x >= 4 && x <= 204)
            elsif mx >= 4 && mx <= 204
              y_positions = touch_get_shortcut_y_positions
              
              # Pokerider
              if y_positions[:pokerider]
                ry = y_positions[:pokerider]
                if my >= ry && my < ry + 64
                  $mouse_click_handled = true
                  $item_or_button_clicked = true
                  pbPlayDecisionSE rescue nil
                  if pokerider
                    @sprites.visible = false
                    @done = true
                    pokerider_fly
                  end
                  return
                end
              end
              
              # Vial
              if y_positions[:vial]
                vy = y_positions[:vial]
                if my >= vy && my < vy + 64
                  $mouse_click_handled = true
                  $item_or_button_clicked = true
                  pbPlayDecisionSE rescue nil
                  if use_pokevial
                    draw_vial_shortcut(true)
                  end
                  return
                end
              end
              
              # Radar
              if y_positions[:radar]
                ray = y_positions[:radar]
                if my >= ray && my < ray + 64
                  $mouse_click_handled = true
                  $item_or_button_clicked = true
                  pbPlayDecisionSE rescue nil
                  pbStartRadar
                  return
                end
              end
              
              # Repel
              if y_positions[:repel]
                rey = y_positions[:repel]
                if my >= rey && my < rey + 64
                  $mouse_click_handled = true
                  $item_or_button_clicked = true
                  pbPlayDecisionSE rescue nil
                  pbToggleInfiniteRepel
                  draw_repel_shortcut(true)
                  return
                end
              end
              
            # 3. Clicou em área vazia (fora do menu e fora dos atalhos) -> Fecha o menu!
            else
              $mouse_click_handled = true
              pbPlayCancelSE rescue nil
              @done = true
            end
          end
        end
      end
    end
    $touch_dp_pause_menu_overrides_applied = true
  end
end

class Scene_Map
  alias touch_orig_call_menu call_menu unless method_defined?(:touch_orig_call_menu)
  def call_menu(*args)
    # Aplica os overrides dinamicamente quando o jogador chamar o menu de pausa pela primeira vez
    touch_apply_dp_pause_menu_overrides
    touch_orig_call_menu(*args)
  end
end

#===============================================================================
# 1. Extensões Genéricas de Simulação de Entrada (Skip de Texto e Hold-to-Exit)
#===============================================================================
module Input
  class << self
    def pbchooseitem_caller?
      if defined?(caller_locations)
        # Obter os últimos 15 frames para achar pbChooseItem robustamente
        frames = caller_locations(2, 15) || []
        found_choose = false
        has_update_after = false
        frames.each do |loc|
          next unless loc
          label = loc.base_label
          if label == "pbChooseItem"
            found_choose = true
            break
          elsif label.downcase.include?("update")
            has_update_after = true
          end
        end
        return found_choose && !has_update_after
      else
        frames = caller(2, 15) || []
        found_choose = false
        has_update_after = false
        frames.each do |c|
          next unless c
          if c.include?("pbChooseItem")
            found_choose = true
            break
          elsif c.downcase.include?("update")
            has_update_after = true
          end
        end
        return found_choose && !has_update_after
      end
    end

    alias modular_menu_orig_trigger? trigger? unless method_defined?(:modular_menu_orig_trigger?)
    def trigger?(button)
      if (Input.text_input rescue false)
        return modular_menu_orig_trigger?(button)
      end
      if button == (Input::MOUSELEFT rescue 18)
        # Se for clique nas abas do pocket, ativa flag para rastrear todo o ciclo de clique sem bypass
        mousepos = Mouse.getMousePos
        if mousepos && mousepos[0] >= 372 && mousepos[0] < 504 && mousepos[1] >= 0 && mousepos[1] < 54
          $pocket_click_active = true
        else
          $pocket_click_active = false
        end
        
        if pbchooseitem_caller? && !$pocket_click_active
          return false
        end
      end
      if button == (Input::JUMPUP rescue nil) && $touch_input_trigger_jumpup
        $touch_input_trigger_jumpup = false
        return true
      end
      if button == (Input::JUMPDOWN rescue nil) && $touch_input_trigger_jumpdown
        $touch_input_trigger_jumpdown = false
        return true
      end
      if button == Input::LEFT && $touch_input_trigger_left
        $touch_input_trigger_left = false
        return true
      end
      if button == Input::RIGHT && $touch_input_trigger_right
        $touch_input_trigger_right = false
        return true
      end
      if button == Input::UP && $touch_input_trigger_up
        $touch_input_trigger_up = false
        return true
      end
      if button == Input::DOWN && $touch_input_trigger_down
        $touch_input_trigger_down = false
        return true
      end
      if button == Input::USE
        if $touch_input_trigger_use
          $touch_input_trigger_use = false
          return true
        end
        if $touch_use_ticks && $touch_use_ticks > 0
          $touch_use_ticks = 0
          return true
        end
        # Avança / Skip de diálogo de NPC com clique esquerdo na tela
        if Input.trigger?(Input::MOUSELEFT) && $game_temp && $game_temp.message_window_showing && !$active_selectable_window_exists
          return true
        end
      end
      
      if button == Input::BACK
        if $touch_input_trigger_back
          $touch_input_trigger_back = false
          return true
        end
        if $touch_back_ticks && $touch_back_ticks > 0
          $touch_back_ticks = 0
          return true
        end
      end
      modular_menu_orig_trigger?(button)
    end

    alias modular_menu_orig_repeat? repeat? unless method_defined?(:modular_menu_orig_repeat?)
    def repeat?(button)
      if (Input.text_input rescue false)
        return modular_menu_orig_repeat?(button)
      end
      if button == (Input::MOUSELEFT rescue 18) && pbchooseitem_caller? && !$pocket_click_active
        return false
      end
      if button == (Input::JUMPUP rescue nil) && $touch_input_trigger_jumpup
        $touch_input_trigger_jumpup = false
        return true
      end
      if button == (Input::JUMPDOWN rescue nil) && $touch_input_trigger_jumpdown
        $touch_input_trigger_jumpdown = false
        return true
      end
      if button == Input::LEFT && $touch_input_trigger_left
        $touch_input_trigger_left = false
        return true
      end
      if button == Input::RIGHT && $touch_input_trigger_right
        $touch_input_trigger_right = false
        return true
      end
      if button == Input::UP && $touch_input_trigger_up
        $touch_input_trigger_up = false
        return true
      end
      if button == Input::DOWN && $touch_input_trigger_down
        $touch_input_trigger_down = false
        return true
      end
      modular_menu_orig_repeat?(button)
    end

    alias modular_menu_orig_press? press? unless method_defined?(:modular_menu_orig_press?)
    def press?(button)
      if (Input.text_input rescue false)
        return modular_menu_orig_press?(button)
      end
      if button == (Input::MOUSELEFT rescue 18) && pbchooseitem_caller? && !$pocket_click_active
        return false
      end
      if button == (Input::JUMPUP rescue nil) && $touch_input_trigger_jumpup
        $touch_input_trigger_jumpup = false
        return true
      end
      if button == (Input::JUMPDOWN rescue nil) && $touch_input_trigger_jumpdown
        $touch_input_trigger_jumpdown = false
        return true
      end
      if button == Input::LEFT && $touch_input_trigger_left
        $touch_input_trigger_left = false
        return true
      end
      if button == Input::RIGHT && $touch_input_trigger_right
        $touch_input_trigger_right = false
        return true
      end
      if button == Input::UP && $touch_input_trigger_up
        $touch_input_trigger_up = false
        return true
      end
      if button == Input::DOWN && $touch_input_trigger_down
        $touch_input_trigger_down = false
        return true
      end
      modular_menu_orig_press?(button)
    end

    alias modular_menu_orig_release? release? rescue nil
    def release?(button)
      if (Input.text_input rescue false)
        if defined?(modular_menu_orig_release?)
          return modular_menu_orig_release?(button)
        end
        return false
      end
      if button == (Input::MOUSELEFT rescue 18)
        was_pocket_click = $pocket_click_active
        $pocket_click_active = false
        
        if pbchooseitem_caller? && !was_pocket_click
          return false
        end
        
        if defined?(modular_menu_orig_release?)
          return modular_menu_orig_release?(button)
        end
        return false
      end
      
      if defined?(modular_menu_orig_release?)
        return modular_menu_orig_release?(button)
      end
      return false
    end

    alias modular_menu_orig_update update unless method_defined?(:modular_menu_orig_update)
    def update
      if (Input.text_input rescue false)
        modular_menu_orig_update
        return
      end
      # Decrementar contadores de clique virtual
      $touch_use_ticks = ($touch_use_ticks && $touch_use_ticks > 0) ? $touch_use_ticks - 1 : 0
      $touch_back_ticks = ($touch_back_ticks && $touch_back_ticks > 0) ? $touch_back_ticks - 1 : 0

      # Resetar flags de janela selecionável
      $active_selectable_window_exists = false
      $disable_selectable_mouse = false
      
      was_item_clicked = $item_or_button_clicked
      $item_or_button_clicked = false
      
      was_click_handled = $mouse_click_handled
      $mouse_click_handled = false
      
      modular_menu_orig_update
      
      # Garante a aplicação do patch no DP_PauseMenu na primeira oportunidade
      if defined?(DP_PauseMenu) && !$touch_dp_pause_menu_overrides_applied
        touch_apply_dp_pause_menu_overrides rescue nil
      end
      
      # 1. Rastrear clique duplo (Double-Click) para Simular tecla BACK / Abrir Menu de Pausa
      if modular_menu_orig_trigger?((Input::MOUSELEFT rescue 18))
        now = System.uptime
        @last_mouse_click_time ||= 0
        if now - @last_mouse_click_time < 0.3
          if !was_item_clicked
            $touch_input_trigger_back = true
            pbPlayCloseMenuSE rescue nil
          end
          @last_mouse_click_time = 0
        else
          @last_mouse_click_time = now
        end
      end
      
      # 2. Rastrear segurar o clique (Hold-to-Exit / Simular tecla BACK)
      if press?(Input::MOUSELEFT)
        mousepos = Mouse.getMousePos
        if mousepos
          @mouse_held_start ||= System.uptime
          @mouse_held_start_x ||= mousepos[0]
          @mouse_held_start_y ||= mousepos[1]
          
          # Se o mouse se mover mais de 10 pixels em qualquer direção, considera-se arrasto/scroll
          dx = mousepos[0] - @mouse_held_start_x
          dy = mousepos[1] - @mouse_held_start_y
          if dx.abs > 10 || dy.abs > 10
            @mouse_held_dragged = true
          end
          
          if System.uptime - @mouse_held_start >= 0.5 && !@mouse_held_dragged && (!$in_party_menu || $in_pokedex || $in_summary_screen)
            if !@long_press_back_triggered
              $touch_input_trigger_back = true
              @long_press_back_triggered = true
              pbPlayCloseMenuSE rescue nil
            end
          end
        end
      else
        @mouse_held_start = nil
        @mouse_held_start_x = nil
        @mouse_held_start_y = nil
        @mouse_held_dragged = false
        @long_press_back_triggered = false
      end
    end
  end
end

#===============================================================================
# 3. Suporte a Toque no Mapa da Região / Menu de Viagem (Region Map & Vuelo)
#===============================================================================
class PokemonRegionMap_Scene
  alias touch_orig_pbUpdate pbUpdate unless method_defined?(:touch_orig_pbUpdate)
  def pbUpdate
    touch_orig_pbUpdate
    
    if Input.trigger?(Input::MOUSELEFT)
      mousepos = Mouse.getMousePos
      if mousepos
        mx, my = mousepos[0], mousepos[1]
        
        # 1. Clique no botão de Ação / Modo de Voo (Canto Superior Direito)
        if !@wallmap && !@fly_map && pbCanFly? && mx >= Graphics.width - 180 && my <= 32
          $mouse_click_handled = true
          $item_or_button_clicked = true
          pbPlayDecisionSE rescue nil
          @mode = (@mode == 1) ? 0 : 1
          refresh_fly_screen
          return
        end
        
        # 2. Clique em qualquer local do Grid
        map_offset_x = (Graphics.width - @sprites["map"].bitmap.width) / 2
        map_offset_y = (Graphics.height - @sprites["map"].bitmap.height) / 2
        
        x = ((mx - map_offset_x + SQUARE_WIDTH / 2.0) / SQUARE_WIDTH).floor
        y = ((my - map_offset_y + SQUARE_HEIGHT / 2.0) / SQUARE_HEIGHT).floor
        
        if x >= LEFT && x <= RIGHT && y >= TOP && y <= BOTTOM
          $mouse_click_handled = true
          $item_or_button_clicked = true
          if @map_x == x && @map_y == y
            # Clique duplo ou clique no ponto já selecionado: Confirma Viagem!
            $touch_input_trigger_use = true
          else
            # Move o cursor e atualiza dados
            @map_x = x
            @map_y = y
            @sprites["cursor"].x = point_x_to_screen_x(x)
            @sprites["cursor"].y = point_y_to_screen_y(y)
            @sprites["mapbottom"].maplocation = pbGetMapLocation(@map_x, @map_y)
            @sprites["mapbottom"].mapdetails  = pbGetMapDetails(@map_x, @map_y)
            pbPlayCursorSE rescue nil
          end
        end
      end
    end
  end
end




