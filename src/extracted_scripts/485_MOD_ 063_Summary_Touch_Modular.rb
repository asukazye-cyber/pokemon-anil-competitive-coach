#===============================================================================
# MOD: 063_Summary_Touch_Modular.rb
#-------------------------------------------------------------------------------
# Adiciona gestos de arraste e cliques nas abas superiores para a tela de Dados do Pokémon (Summary).
#===============================================================================

class PokemonSummary_Scene
  # Hook no initialize da cena, que não é modificado por plugins de interface
  alias touch_summary_orig_initialize initialize rescue nil
  def initialize(*args)
    if defined?(touch_summary_orig_initialize)
      touch_summary_orig_initialize(*args)
    else
      super(*args) rescue nil
    end
    PokemonSummary_Scene.apply_touch_overrides
  end

  class << self
    def apply_touch_overrides
      return if @touch_overrides_applied
      @touch_overrides_applied = true
      
      class_eval do
        alias touch_summary_orig_pbUpdate pbUpdate unless method_defined?(:touch_summary_orig_pbUpdate)
        
        def pbUpdate
          touch_summary_orig_pbUpdate
          
          # Executa apenas se a viewport e sprites estiverem ativos
          return if !@sprites || @sprites.empty?
          
          mousepos = Mouse.getMousePos
          
          @drag_start_x ||= nil
          @drag_start_y ||= nil
          @drag_active ||= false
          @drag_has_swiped ||= false
          
          if Input.trigger?(Input::MOUSELEFT) && mousepos
            @drag_start_x = mousepos[0]
            @drag_start_y = mousepos[1]
            @drag_active = true
            @drag_has_swiped = false
          end
          
          if Input.press?(Input::MOUSELEFT) && @drag_active && mousepos && @drag_start_x && @drag_start_y
            dx = mousepos[0] - @drag_start_x
            dy = mousepos[1] - @drag_start_y
            
            if !@drag_has_swiped && (dx.abs > 50 || dy.abs > 50)
              @drag_has_swiped = true
              
              # Se for movimento no eixo horizontal
              if dx.abs > dy.abs
                # Movimento horizontal só é permitido se não estiver em sub-menu (como seleção de golpes)
                if !touch_summary_sub_menu_active? && !(@sprites["movesel"] && @sprites["movesel"].visible rescue false)
                  if dx < -50
                    # Arrastou para a esquerda -> Próxima página
                    $touch_input_trigger_right = true
                  elsif dx > 50
                    # Arrastou para a direita -> Página anterior
                    $touch_input_trigger_left = true
                  end
                end
              else
                # Se for movimento no eixo vertical
                if (@sprites["movesel"] && @sprites["movesel"].visible rescue false)
                  # No submenu de seleção de golpes, arrastar vertical move o cursor de golpes
                  if dy < -50
                    # Arrastou para cima -> Simula DOWN (desce na lista)
                    $touch_input_trigger_down = true
                  elsif dy > 50
                    # Arrastou para baixo -> Simula UP (sobe na lista)
                    $touch_input_trigger_up = true
                  end
                elsif !touch_summary_sub_menu_active?
                  # Na navegação principal, arrastar vertical muda o Pokémon selecionado
                  if dy < -50
                    # Arrastou para cima -> Simula DOWN (próximo Pokémon)
                    $touch_input_trigger_down = true
                  elsif dy > 50
                    # Arrastou para baixo -> Simula UP (Pokémon anterior)
                    $touch_input_trigger_up = true
                  end
                end
              end
            end
          end
          
          # Quando o clique/toque é solto
          if @drag_active && (!Input.press?(Input::MOUSELEFT) || ((Input.release?(Input::MOUSELEFT) rescue false)))
            # Se soltou sem ter arrastado (um clique rápido / tap)
            if !@drag_has_swiped && mousepos && !touch_summary_sub_menu_active? && !(@sprites["movesel"] && @sprites["movesel"].visible rescue false)
              mx = mousepos[0]
              my = mousepos[1]
              
              # Lê as constantes de abas com rescue como fallback parenteseado
              xpos, ypos = (PAGE_ICONS_POSITION rescue [216, 2])
              w, h       = (PAGE_ICON_SIZE rescue [28, 28])
              spacing    = 4
              
              # Se clicar na faixa vertical das abas (com margem de segurança)
              if my >= ypos - 5 && my <= ypos + h + 5 && @page_list && !@page_list.empty?
                size       = (((MAX_PAGE_ICONS rescue 6)) - 1)
                range      = [@page_list.length, size + 1]
                page       = @page_list.find_index(@page_id) || 0
                startPage  = (page > size) ? page - size : 0
                endPage    = [startPage + size, @page_list.length - 1].min
                alignment  = (PAGE_ICONS_ALIGNMENT rescue :center)
                
                case alignment
                when :left   then offset = 0
                when :right  then offset = (Graphics.width - xpos + 4) - ((w + spacing) * range.min)
                when :center then offset = (Graphics.width - xpos + 4) / 2 - (range.min * ((w + spacing) / 2))
                end
                
                clicked_tab_index = nil
                iconPos = 0
                for i in startPage..endPage
                  tab_x_start = xpos + offset + (iconPos * (w + spacing))
                  tab_x_end = tab_x_start + w
                  if mx >= tab_x_start && mx <= tab_x_end
                    clicked_tab_index = i
                    break
                  end
                  iconPos += 1
                end
                
                if clicked_tab_index && clicked_tab_index != page
                  @page = clicked_tab_index + 1
                  @page_id = @page_list[clicked_tab_index]
                  (pbPlayCursorSE rescue nil)
                  (@ribbonOffset = 0 rescue nil)
                  (@show_back = false rescue nil)
                  drawPage(@page)
                end
              end
            end
            
            @drag_start_x = nil
            @drag_start_y = nil
            @drag_active = false
            @drag_has_swiped = false
          end
        end
        
        alias touch_summary_orig_showAbilityDescription showAbilityDescription unless method_defined?(:touch_summary_orig_showAbilityDescription)
        def showAbilityDescription(*args)
          @in_ability_description = true
          begin
            touch_summary_orig_showAbilityDescription(*args)
          ensure
            @in_ability_description = false
          end
        end

        alias touch_summary_orig_pbStartScene pbStartScene unless method_defined?(:touch_summary_orig_pbStartScene)
        def pbStartScene(*args)
          $in_summary_screen = true
          touch_summary_orig_pbStartScene(*args)
        end

        alias touch_summary_orig_pbEndScene pbEndScene unless method_defined?(:touch_summary_orig_pbEndScene)
        def pbEndScene(*args)
          touch_summary_orig_pbEndScene(*args)
          $in_summary_screen = false
        end

        def touch_summary_sub_menu_active?
          return true if @in_ability_description
          return true if (@sprites["promptoverlay"] && @sprites["promptoverlay"].visible rescue false)
          return true if (@sprites["markingbg"] && @sprites["markingbg"].visible rescue false)
          return true if (@sprites["ribbonsel"] && @sprites["ribbonsel"].visible rescue false)
          return false
        end
      end
    end
  end
end
