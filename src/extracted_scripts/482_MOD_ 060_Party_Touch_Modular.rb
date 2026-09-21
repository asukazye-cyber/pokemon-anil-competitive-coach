#===============================================================================
# MOD: 060_Party_Touch_Modular.rb
#-------------------------------------------------------------------------------
# Adiciona controles de toque e clique do mouse para a tela de Party (Pokémon).
#===============================================================================

class PokemonParty_Scene
  def pbChoosePokemon(switching = false, initialsel = -1, canswitch = 0)
    # Settings::MAX_PARTY_SIZE.times do |i|
    max_party_size.times do |i|
      @sprites["pokemon#{i}"].preselected = (switching && i == @activecmd)
      @sprites["pokemon#{i}"].switching   = switching
    end
    @activecmd = initialsel if initialsel >= 0
    pbRefresh
    loop do
      Graphics.update
      Input.update
      self.update
      oldsel = @activecmd
      key = -1
      key = Input::DOWN if Input.repeat?(Input::DOWN)
      key = Input::RIGHT if Input.repeat?(Input::RIGHT)
      key = Input::LEFT if Input.repeat?(Input::LEFT)
      key = Input::UP if Input.repeat?(Input::UP)
      if key >= 0
        @activecmd = pbChangeSelection(key, @activecmd)
      end
      if Input.trigger?(Input::MOUSELEFT)
        mousepos = Mouse.getMousePos
        if mousepos
          # Detecção de long press (segurar toque por 0.4s)
          is_long_press = false
          start_time = System.uptime
          loop do
            Graphics.update
            Input.update
            self.update rescue nil
            if !Input.press?(Input::MOUSELEFT)
              break
            end
            if System.uptime - start_time >= 0.4
              is_long_press = true
              break
            end
          end

          raw_mx = Input.mouse_x
          raw_my = Input.mouse_y
          Mouse.log_click(raw_mx, raw_my, mousepos[0], mousepos[1])
          
          if Mouse.press_calibration_any?
            s0_exists = File.exist?("mouse_s0_raw.txt")
            s5_exists = File.exist?("mouse_s5_raw.txt")
            
            if !s0_exists || (s0_exists && s5_exists)
              # Registering Point 0 (Slot 0)
              sprite = @sprites["pokemon0"]
              if sprite && !sprite.disposed?
                viewport = sprite.viewport rescue nil
                v_x = (viewport && !viewport.disposed?) ? (viewport.rect.x - viewport.ox) : 0
                v_y = (viewport && !viewport.disposed?) ? (viewport.rect.y - viewport.oy) : 0
                x = sprite.x + v_x
                y = sprite.y + v_y
                bg = sprite.instance_variable_get(:@panelbgsprite) || sprite.instance_variable_get(:@bgsprite)
                w = bg && !bg.disposed? && bg.bitmap ? bg.bitmap.width : 256
                h = bg && !bg.disposed? && bg.bitmap ? bg.bitmap.height : 98
                target_center_x = x + w / 2
                target_center_y = y + h / 2
                
                point, compiled = Mouse.handle_calibration_click(raw_mx, raw_my, target_center_x, target_center_y)
                pbPlayDecisionSE
                pbMessage(_INTL("Ponto 0 registrado (Slot 0)! Agora segure CTRL e clique no Slot 5 (ultimo Pokemon) para concluir."))
                next
              end
            else
              # Registering Point 5 (Slot 5)
              sprite = @sprites["pokemon5"] rescue nil
              sprite ||= @sprites["pokemon#{max_party_size-1}"] rescue nil
              if sprite && !sprite.disposed?
                viewport = sprite.viewport rescue nil
                v_x = (viewport && !viewport.disposed?) ? (viewport.rect.x - viewport.ox) : 0
                v_y = (viewport && !viewport.disposed?) ? (viewport.rect.y - viewport.oy) : 0
                x = sprite.x + v_x
                y = sprite.y + v_y
                bg = sprite.instance_variable_get(:@panelbgsprite) || sprite.instance_variable_get(:@bgsprite)
                w = bg && !bg.disposed? && bg.bitmap ? bg.bitmap.width : 256
                h = bg && !bg.disposed? && bg.bitmap ? bg.bitmap.height : 98
                target_center_x = x + w / 2
                target_center_y = y + h / 2
                
                point, compiled = Mouse.handle_calibration_click(raw_mx, raw_my, target_center_x, target_center_y)
                pbPlayDecisionSE
                if compiled
                  pbMessage(_INTL("Ponto 5 registrado (Slot 5)! Calibracao global ATIVADA com sucesso!"))
                else
                  pbMessage(_INTL("Ponto 5 registrado, mas a calibracao falhou."))
                end
                next
              end
            end
          elsif Input.press?(Input::SPECIAL)
            sprite = @sprites["pokemon#{@activecmd}"]
            if sprite && !sprite.disposed?
              viewport = sprite.viewport rescue nil
              v_x = (viewport && !viewport.disposed?) ? (viewport.rect.x - viewport.ox) : 0
              v_y = (viewport && !viewport.disposed?) ? (viewport.rect.y - viewport.oy) : 0
              x = sprite.x + v_x
              y = sprite.y + v_y
              bg = sprite.instance_variable_get(:@panelbgsprite) || sprite.instance_variable_get(:@bgsprite)
              w = bg && !bg.disposed? && bg.bitmap ? bg.bitmap.width : 256
              h = bg && !bg.disposed? && bg.bitmap ? bg.bitmap.height : 98
              
              target_x = x + w / 2
              target_y = y + h / 2
              
              $mouse_x_offset = target_x - raw_mx
              $mouse_y_offset = target_y - raw_my
              
              pkmn = sprite.pokemon rescue nil
              pkmn_name = pkmn ? pkmn.name : "Vazio"
              Mouse.log_calibration("Party", "Slot #{@activecmd} (#{pkmn_name})", raw_mx, raw_my, target_x, target_y, $mouse_x_offset, $mouse_y_offset)
              
              Mouse.save_calibration
              pbPlayDecisionSE
              pbMessage(_INTL("Mouse calibrado (offset unico)! Novo Desvio X: {1}, Y: {2}", $mouse_x_offset, $mouse_y_offset))
              next
            end
          end
          clicked_idx = -1
          numsprites = max_party_size + ((@multiselect) ? 2 : 1)
          numsprites.times do |i|
            sprite = @sprites["pokemon#{i}"]
            next if !sprite || sprite.disposed?
            if Mouse.is_over_sprite?(sprite, mousepos[0], mousepos[1])
              if i < max_party_size
                next if !@party[i]
              end
              clicked_idx = i
              break
            end
          end
          if clicked_idx >= 0
            @activecmd = clicked_idx
            numsprites.times do |i|
              @sprites["pokemon#{i}"].selected = (i == @activecmd)
            end
            cancelsprite = max_party_size + ((@multiselect) ? 1 : 0)
            if @activecmd == cancelsprite
              (switching) ? pbPlayDecisionSE : pbPlayCloseMenuSE
              return -1
            else
              pbPlayDecisionSE
              if is_long_press && canswitch == 1
                return [1, @activecmd] # Mover / Quick Switch!
              else
                return @activecmd
              end
            end
          end
        end
      end
      if @activecmd != oldsel   # Changing selection
        pbPlayCursorSE
        numsprites = max_party_size + ((@multiselect) ? 2 : 1)
        numsprites.times do |i|
          @sprites["pokemon#{i}"].selected = (i == @activecmd)
        end
      end
      cancelsprite = max_party_size + ((@multiselect) ? 1 : 0)
      if Input.trigger?(Input::SPECIAL) && @can_access_storage && canswitch != 2
        pbPlayDecisionSE
        pbFadeOutIn do
          scene = PokemonStorageScene.new
          screen = PokemonStorageScreen.new(scene, $PokemonStorage)
          screen.pbStartScreen(0)
          pbHardRefresh
        end
      elsif Input.trigger?(Input::ACTION) && canswitch == 1 && @activecmd != cancelsprite
        pbPlayDecisionSE
        return [1, @activecmd]
      elsif Input.trigger?(Input::ACTION) && canswitch == 2
        return -1
      elsif Input.trigger?(Input::BACK)
        pbPlayCloseMenuSE if !switching
        return -1
      elsif Input.trigger?(Input::USE)
        if @activecmd == cancelsprite
          (switching) ? pbPlayDecisionSE : pbPlayCloseMenuSE
          return -1
        else
          pbPlayDecisionSE
          return @activecmd
        end
      end
    end
  end
end

class PokemonParty_Scene
  alias touch_party_orig_pbStartScene pbStartScene unless method_defined?(:touch_party_orig_pbStartScene)
  alias touch_party_orig_pbEndScene pbEndScene unless method_defined?(:touch_party_orig_pbEndScene)

  def pbStartScene(*args)
    $in_party_menu = true
    touch_party_orig_pbStartScene(*args)
  end

  def pbEndScene(*args)
    touch_party_orig_pbEndScene(*args)
    $in_party_menu = false
  end
end

