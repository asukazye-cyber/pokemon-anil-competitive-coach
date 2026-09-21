#==============================================================================
# * Scene_Controls
#------------------------------------------------------------------------------
# Muestra una pantalla de ayuda que enumera los controles del teclado.
# Mostrar con:
#      pbEventScreen(ButtonEventScene)
#==============================================================================
class ButtonEventScene < EventScene
  def initialize(viewport = nil)
    super
    Graphics.freeze
    @current_screen = 1
    @labels = []
    @label_screens = []
    @keys = []
    @key_screens = []
    
    
    textpos = []
    @sprites = {}
    textpos.push(
    ["CONTROLES",Graphics.width/2,24,2,Color.new(248, 248, 248), Color.new(168, 184, 184)])
    @sprites["overlay"] = BitmapSprite.new(Graphics.width,Graphics.height,@viewport)
    @overlay = @sprites["overlay"].bitmap
    pbSetSystemFont(@overlay)
    @overlay.font.size = 30
    pbDrawTextPositions(@overlay,textpos)
    addImageForScreen(1, 0, 0, "Graphics/UI/Controls help" + _INTL("/bg_controles"))

    set_up_screen(@current_screen)
    Graphics.transition
    # Ir a la siguiente pantalla cuando el usuario presiona USAR
    onCTrigger.set(method(:pbOnScreenEnd))
  end

  def addLabelForScreen(number, x, y, width, text)
    @labels.push(addLabel(x, y, width, text))
    @label_screens.push(number)
    @picturesprites[@picturesprites.length - 1].opacity = 0
  end

  def addImageForScreen(number, x, y, filename)
    @keys.push(addImage(x, y, filename))
    @key_screens.push(number)
    @picturesprites[@picturesprites.length - 1].opacity = 0
  end

  def set_up_screen(number)
    @label_screens.each_with_index do |screen, i|
      @labels[i].moveOpacity((screen == number) ? 10 : 0, 10, (screen == number) ? 255 : 0)
    end
    @key_screens.each_with_index do |screen, i|
      @keys[i].moveOpacity((screen == number) ? 10 : 0, 10, (screen == number) ? 255 : 0)
    end
    pictureWait   # Actualizar escena de evento con los cambios
  end

  def pbOnScreenEnd(scene, *args)
    last_screen = 1 #[@label_screens.max, @key_screens.max].max
    if @current_screen >= last_screen
      # Terminar escena
      $game_temp.background_bitmap = Graphics.snap_to_bitmap
      Graphics.freeze
      @viewport.color = Color.black  # Asegurarse de que la pantalla esté en negro
      Graphics.transition(8, "fadetoblack")
      $game_temp.background_bitmap.dispose
      scene.dispose
    else
      # Siguiente pantalla
      @current_screen += 1
      onCTrigger.clear
      set_up_screen(@current_screen)
      onCTrigger.set(method(:pbOnScreenEnd))
    end
  end
end
