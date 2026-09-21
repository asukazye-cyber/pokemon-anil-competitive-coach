module Input
  USE      = C
  BACK     = B
  ACTION   = A
  JUMPUP   = X
  JUMPDOWN = Y
  SPECIAL  = Z
  AUX1     = L
  AUX2     = R

  class << self
    unless defined?(mouse_orig_mouse_x)
      alias mouse_orig_mouse_x mouse_x
      alias mouse_orig_mouse_y mouse_y
    end

    def raw_mouse_x
      return (mouse_orig_mouse_x rescue 0)
    end

    def raw_mouse_y
      return (mouse_orig_mouse_y rescue 0)
    end

    def mouse_x
      pos = Mouse.getMousePos(true) rescue nil
      return pos ? pos[0] : (mouse_orig_mouse_x rescue 0)
    end

    def mouse_y
      pos = Mouse.getMousePos(true) rescue nil
      return pos ? pos[1] : (mouse_orig_mouse_y rescue 0)
    end
  end
  
  unless defined?(update_KGC_ScreenCapture)
    class << Input
      alias update_KGC_ScreenCapture update
    end
  end

  def self.update
    update_KGC_ScreenCapture
    pbScreenCapture if trigger?(Input::F8)
  end

  class << self
    unless defined?(INPUT_TOUCH_ALIASED)
      alias touch_orig_update update
      alias touch_orig_trigger? trigger?
      alias touch_orig_press? press?
      INPUT_TOUCH_ALIASED = true
    end

    def update
      if (Input.text_input rescue false)
        touch_orig_update
        return
      end
      # Ao iniciar o frame, verificamos se o clique do frame anterior nao foi tratado
      if ($mouse_left_clicked_this_frame rescue false) && !($mouse_click_handled rescue false)
        $mouse_use_triggered = true
      end

      $mouse_use_active = ($mouse_use_triggered rescue false)
      $mouse_use_triggered = false
      $mouse_back_active = ($mouse_back_triggered rescue false)
      $mouse_back_triggered = false
      $mouse_click_handled = false
      $mouse_left_clicked_this_frame = false
      $active_selectable_window_exists = false # <--- Reset at start of frame
      
      touch_orig_update
      
      # Detecta se houve clique fisico neste frame
      m_key = 18
      begin
        m_key = Input::MOUSELEFT
      rescue
      end
      
      if touch_orig_trigger?(m_key)
        $mouse_left_clicked_this_frame = true
      end

      # ── DIAGNÓSTICO: loga TUDO a cada clique ──
      if touch_orig_trigger?(m_key)
        begin
          rx = Input.raw_mouse_x
          ry = Input.raw_mouse_y
          ww = (Graphics.window_width  rescue "N/A")
          wh = (Graphics.window_height rescue "N/A")
          gw = (Graphics.width  rescue "N/A")
          gh = (Graphics.height rescue "N/A")
          dw = (Graphics.display_width  rescue "N/A")
          dh = (Graphics.display_height rescue "N/A")
          fs = (Graphics.fullscreen rescue "N/A")
          joip = Mouse.is_joiplay?
          line = "[#{Time.now.strftime('%H:%M:%S')}] " \
                 "raw=(#{rx},#{ry}) | " \
                 "window=#{ww}x#{wh} | " \
                 "graphics=#{gw}x#{gh} | " \
                 "display=#{dw}x#{dh} | " \
                 "fullscreen=#{fs} | joiplay=#{joip}\n"
          File.open("mouse_debug.txt", "a") { |f| f.write(line) }
        rescue => e
          File.open("mouse_debug.txt", "a") { |f| f.write("ERRO: #{e.message}\n") } rescue nil
        end
      end
    end

    def trigger?(key)
      if (Input.text_input rescue false)
        return touch_orig_trigger?(key)
      end
      # 1. Bypassear clique se for MOUSELEFT e o bypass estiver ativo
      if key == (Input::MOUSELEFT rescue 18) && ($bypass_original_selectable_mouse rescue false)
        return false
      end

      # 2. Se for a tecla de confirmacao (USE/C)
      if key == Input::USE || key == Input::C
        if ($mouse_use_active rescue false) || ($mouse_use_triggered rescue false)
          $mouse_use_triggered = false
          return true
        end
        
        # Clique instantâneo de alta precisão em diálogos (quando não há menu ativo na tela)
        m_key = 18
        begin
          m_key = Input::MOUSELEFT
        rescue
        end
        
        if touch_orig_trigger?(m_key) && !($mouse_click_handled rescue false)
          if $game_temp && $game_temp.message_window_showing
            $mouse_click_handled = true
            return true
          end
        end
      end

      # 3. Se for a tecla de voltar (BACK/B) e houver clique virtual de BACK pendente
      if key == Input::BACK || key == Input::B
        if ($mouse_back_active rescue false) || ($mouse_back_triggered rescue false)
          $mouse_back_triggered = false
          return true
        end
      end

      # 4. Fallback original
      return touch_orig_trigger?(key)
    end

    def press?(key)
      if (Input.text_input rescue false)
        return touch_orig_press?(key)
      end
      if key == Input::MOUSELEFT && (($disable_selectable_drag rescue false) || ($bypass_original_selectable_mouse rescue false))
        return false
      end
      return touch_orig_press?(key)
    end
  end
end

$mouse_use_triggered = false
$mouse_back_triggered = false
$mouse_click_handled = false
$mouse_left_clicked_this_frame = false

if !defined?($mouse_y_offset)
  $mouse_y_offset = 0
end
if !defined?($mouse_x_offset)
  $mouse_x_offset = 0
end

module Mouse
  module_function

  def x
    pos = getMousePos
    return pos ? pos[0] : 0
  end

  def y
    pos = getMousePos
    return pos ? pos[1] : 0
  end

  def press_calibration_0?
    return Input.press?(Input::CTRL) rescue false
  end

  def press_calibration_5?
    return Input.press?(Input::CTRL) rescue false
  end

  def press_calibration_any?
    return true if Input.press?(Input::CTRL) rescue false
    return true if Mouse.is_joiplay? && (Input.press?(Input::AUX1) || Input.press?(Input::AUX2)) rescue false
    return false
  end

  def handle_calibration_click(raw_x, raw_y, target_x = nil, target_y = nil)
    s0_exists = File.exist?("mouse_s0_raw.txt")
    s5_exists = File.exist?("mouse_s5_raw.txt")
    
    if s0_exists && !s5_exists
      # Ponto 5 (s5)
      if target_x && target_y
        File.write("mouse_s5_raw.txt", "#{raw_x},#{raw_y},#{target_x},#{target_y}") rescue nil
      else
        File.write("mouse_s5_raw.txt", "#{raw_x},#{raw_y}") rescue nil
      end
      compiled = check_and_compile_calibration
      return [5, compiled]
    else
      # Ponto 0 (s0)
      File.delete("mouse_s5_raw.txt") rescue nil
      if target_x && target_y
        File.write("mouse_s0_raw.txt", "#{raw_x},#{raw_y},#{target_x},#{target_y}") rescue nil
      else
        File.write("mouse_s0_raw.txt", "#{raw_x},#{raw_y}") rescue nil
      end
      return [0, false]
    end
  end

  def is_joiplay?
    return true if defined?($joiplay) && $joiplay
    return true if ENV['ANDROID_ROOT'] || ENV['ANDROID_DATA']
    return true if File.exist?("/system/app") || Dir.exist?("/sdcard") rescue false
    return true if System.platform =~ /android/i rescue false
    return false
  end

  def save_calibration
    File.write("mouse_calibration.txt", "#{$mouse_x_offset},#{$mouse_y_offset}") rescue nil
  end

  def save_two_point_calibration(s0_raw_x, s0_raw_y, s5_raw_x, s5_raw_y)
    save_two_point_calibration_generic(s0_raw_x, s0_raw_y, 128.0, 49.0, s5_raw_x, s5_raw_y, 384.0, 257.0)
  end

  def save_two_point_calibration_generic(p0_raw_x, p0_raw_y, p0_log_x, p0_log_y, p1_raw_x, p1_raw_y, p1_log_x, p1_log_y)
    dx_log = p1_log_x - p0_log_x
    dy_log = p1_log_y - p0_log_y
    
    dx_raw = p1_raw_x - p0_raw_x
    dy_raw = p1_raw_y - p0_raw_y
    
    $mouse_scale_x = dx_log != 0 ? (dx_raw.to_f / dx_log).abs : 1.25
    $mouse_scale_y = dy_log != 0 ? (dy_raw.to_f / dy_log).abs : 1.25
    
    $mouse_scale_x = 1.25 if $mouse_scale_x <= 0.1 || $mouse_scale_x > 5.0
    $mouse_scale_y = 1.25 if $mouse_scale_y <= 0.1 || $mouse_scale_y > 5.0
    
    $mouse_border_x = p0_raw_x - (p0_log_x * $mouse_scale_x)
    $mouse_border_y = p0_raw_y - (p0_log_y * $mouse_scale_y)
    
    is_fs = (Graphics.fullscreen rescue false)
    if Mouse.is_joiplay?
      filename = "mouse_calibration_params_joiplay.txt"
    elsif is_fs
      filename = "mouse_calibration_params_fullscreen.txt"
    else
      filename = "mouse_calibration_params.txt"
    end
    File.write(filename, "#{$mouse_scale_x},#{$mouse_scale_y},#{$mouse_border_x},#{$mouse_border_y}") rescue nil
    File.write("mouse_calibration_raw.txt", "#{p0_raw_x},#{p0_raw_y},#{p1_raw_x},#{p1_raw_y}") rescue nil
    
    # Atualiza as variáveis base dividindo pela escala se for modo janela
    gs = 1.0
    if !Mouse.is_joiplay? && !is_fs
      gs = (Graphics.scale rescue 1.0)
      gs = 1.0 if gs <= 0.1
    end
    $base_mouse_scale_x = $mouse_scale_x / gs
    $base_mouse_scale_y = $mouse_scale_y / gs
    $base_mouse_border_x = $mouse_border_x / gs
    $base_mouse_border_y = $mouse_border_y / gs
  end

  def check_and_compile_calibration
    s0 = nil
    s5 = nil
    if File.exist?("mouse_s0_raw.txt")
      data = File.read("mouse_s0_raw.txt").split(",") rescue nil
      if data
        if data.length == 4
          s0 = [data[0].to_i, data[1].to_i, data[2].to_f, data[3].to_f]
        elsif data.length == 2
          s0 = [data[0].to_i, data[1].to_i, 128.0, 49.0]
        end
      end
    end
    if File.exist?("mouse_s5_raw.txt")
      data = File.read("mouse_s5_raw.txt").split(",") rescue nil
      if data
        if data.length == 4
          s5 = [data[0].to_i, data[1].to_i, data[2].to_f, data[3].to_f]
        elsif data.length == 2
          s5 = [data[0].to_i, data[1].to_i, 384.0, 257.0]
        end
      end
    end
    if s0 && s5
      save_two_point_calibration_generic(s0[0], s0[1], s0[2], s0[3], s5[0], s5[1], s5[2], s5[3])
      return true
    end
    return false
  end

  def log_click(raw_x, raw_y, log_x, log_y)
    pressed_keys = []
    if Input.respond_to?(:pressex?)
      [:A, :B, :C, :D, :E, :F, :G, :H, :I, :J, :K, :L, :M, :N, :O, :P, :Q, :R, :S, :T, :U, :V, :W, :X, :Y, :Z].each do |k|
        pressed_keys << k.to_s if Input.pressex?(k) rescue nil
      end
    end
    log_line = "[#{Time.now.strftime('%H:%M:%S')}] CLICK - Raw Mouse: (#{raw_x}, #{raw_y}) | Logical: (#{log_x}, #{log_y}) | Scale: (#{$mouse_scale_x rescue 'nil'}, #{$mouse_scale_y rescue 'nil'}) | Border: (#{$mouse_border_x rescue 'nil'}, #{$mouse_border_y rescue 'nil'})"
    log_line += " | Pressed Keys: #{pressed_keys.join(',')}" unless pressed_keys.empty?
    log_line += "\n"
    File.open("mouse_clicks_log.txt", "a") do |f|
      f.write(log_line)
    end rescue nil
  end

  def load_calibration
    # Valores padrão embutidos (calibração de referência modo janela)
    $mouse_scale_x = 1.2890625
    $mouse_scale_y = 1.2740384615384615
    $mouse_border_x = 1.0
    $mouse_border_y = 5.572115384615387
    $mouse_x_offset = 0
    $mouse_y_offset = 0

    if Mouse.is_joiplay?
      # JoiPlay: usa arquivo específico do JoiPlay
      f = "mouse_calibration_params_joiplay.txt"
    elsif (Graphics.fullscreen rescue false)
      # PC tela cheia: preferência para arquivo fullscreen, fallback para padrão
      f = File.exist?("mouse_calibration_params_fullscreen.txt") ?
            "mouse_calibration_params_fullscreen.txt" :
            "mouse_calibration_params.txt"
    else
      # PC modo janela
      f = "mouse_calibration_params.txt"
    end

    if File.exist?(f)
      data = File.read(f).split(",") rescue nil
      if data && data.length == 4
        $mouse_scale_x = data[0].to_f
        $mouse_scale_y = data[1].to_f
        $mouse_border_x = data[2].to_f
        $mouse_border_y = data[3].to_f
      end
    end

    if File.exist?("mouse_calibration.txt")
      data = File.read("mouse_calibration.txt").split(",") rescue nil
      if data && data.length == 2
        $mouse_x_offset = data[0].to_i
        $mouse_y_offset = data[1].to_i
      end
    end

    $base_mouse_scale_x = $mouse_scale_x
    $base_mouse_scale_y = $mouse_scale_y
    $base_mouse_border_x = $mouse_border_x
    $base_mouse_border_y = $mouse_border_y
  end

  def log_calibration(type, name, raw_x, raw_y, target_x, target_y, offset_x, offset_y)
    log_line = "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] Tipo: #{type} | Nome/Pos: #{name} | Raw Mouse: (#{raw_x}, #{raw_y}) | Target Center: (#{target_x}, #{target_y}) | Offset: (X: #{offset_x}, Y: #{offset_y})\n"
    File.open("mouse_calibration_log.txt", "a") do |f|
      f.write(log_line)
    end rescue nil
  end

  def is_over_sprite?(sprite, mx = nil, my = nil, logical_w = nil, logical_h = nil)
    return false if !sprite || sprite.disposed?
    
    # If no coordinates are passed, get them from Mouse.getMousePos
    if !mx || !my
      mousepos = Mouse.getMousePos
      return false if !mousepos
      mx = mousepos[0]
      my = mousepos[1]
    end
    
    # lx, ly are logical sprite coordinates
    lx = sprite.x - (sprite.ox rescue 0)
    ly = sprite.y - (sprite.oy rescue 0)
    viewport = sprite.viewport rescue nil
    if viewport && !viewport.disposed?
      lx += (viewport.rect.x - viewport.ox)
      ly += (viewport.rect.y - viewport.oy)
    end
    
    lw = logical_w
    lh = logical_h
    if !lw || !lh
      bg = sprite.instance_variable_get(:@panelbgsprite) || sprite.instance_variable_get(:@bgsprite)
      if bg && !bg.disposed? && bg.bitmap
        lw ||= bg.bitmap.width
        lh ||= bg.bitmap.height
      end
      if sprite.bitmap && !sprite.bitmap.disposed?
        lw ||= sprite.bitmap.width
        lh ||= sprite.bitmap.height
      end
    end
    
    if !lw || !lh
      # Fallbacks for specific party panel classes
      sprite_class = sprite.class.name rescue ""
      if sprite_class == "PokemonPartyPanel" || sprite_class == "PokemonPartyBlankPanel"
        lw = 256
        lh = 98
      elsif sprite_class == "PokemonPartyConfirmSprite" || sprite_class == "PokemonPartyCancelSprite2"
        lw = 112
        lh = 36
      elsif sprite_class == "PokemonPartyCancelSprite"
        lw = 112
        lh = 48
      end
    end
    
    lw ||= 256
    lh ||= 98
    
    return (mx >= lx && mx < lx + lw && my >= ly && my < ly + lh)
  end

  # Obter o DPI da janela ou do sistema
  def get_window_dpi(hwnd)
    begin
      user32 = Fiddle::Handle.new('user32.dll')
      begin
        get_dpi = Fiddle::Function.new(
          user32['GetDpiForWindow'],
          [Fiddle::TYPE_LONG],
          Fiddle::TYPE_INT
        )
        dpi = get_dpi.call(hwnd)
        return dpi if dpi && dpi > 0
      rescue Exception
        # Fallback para versões antigas do Windows
      end
      
      # Fallback: GetDC e GetDeviceCaps
      gdi32 = Fiddle::Handle.new('gdi32.dll')
      get_dc = Fiddle::Function.new(user32['GetDC'], [Fiddle::TYPE_LONG], Fiddle::TYPE_LONG)
      release_dc = Fiddle::Function.new(user32['ReleaseDC'], [Fiddle::TYPE_LONG, Fiddle::TYPE_LONG], Fiddle::TYPE_INT)
      get_device_caps = Fiddle::Function.new(gdi32['GetDeviceCaps'], [Fiddle::TYPE_LONG, Fiddle::TYPE_INT], Fiddle::TYPE_INT)
      
      hdc = get_dc.call(0)
      dpi = get_device_caps.call(hdc, 88) # LOGPIXELSX
      release_dc.call(0, hdc)
      return dpi if dpi && dpi > 0
      
      return 96
    rescue Exception
      return 96
    end
  end

  # ── Obtém o HWND da janela do jogo ──
  def get_game_window_hwnd
    return nil if Mouse.is_joiplay?
    begin
      require 'fiddle' unless defined?(Fiddle)
      user32 = Fiddle::Handle.new('user32.dll')

      find_window = Fiddle::Function.new(
        user32['FindWindowA'],
        [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
        Fiddle::TYPE_LONG
      )
      
      hwnd = 0
      ['SDL_app', 'RGSS Player', 'RGSS PLAYER', 'mkxp', 'mkxp-z'].each do |cls|
        h = find_window.call(cls, nil)
        if h && h != 0
          hwnd = h
          break
        end
      end

      if hwnd == 0
        title = nil
        if File.exist?("Game.ini")
          File.read("Game.ini").each_line do |line|
            if line =~ /^\s*Title\s*=\s*(.+)$/i
              title = $1.strip
              break
            end
          end
        end
        if title
          h = find_window.call(nil, title)
          hwnd = h if h && h != 0
        end
      end

      if hwnd == 0
        get_active = Fiddle::Function.new(
          user32['GetActiveWindow'],
          [],
          Fiddle::TYPE_LONG
        )
        h = get_active.call
        hwnd = h if h && h != 0
      end

      return hwnd
    rescue
      return 0
    end
  end

  # ── Obtém as dimensões físicas e posição do mouse via APIs Win32 (Fiddle) ──
  def get_physical_mouse_and_client_size(hwnd)
    return nil if Mouse.is_joiplay? || !hwnd || hwnd == 0
    begin
      require 'fiddle' unless defined?(Fiddle)
      user32 = Fiddle::Handle.new('user32.dll')

      get_client = Fiddle::Function.new(
        user32['GetClientRect'],
        [Fiddle::TYPE_LONG, Fiddle::TYPE_VOIDP],
        Fiddle::TYPE_INT
      )
      client_to_screen = Fiddle::Function.new(
        user32['ClientToScreen'],
        [Fiddle::TYPE_LONG, Fiddle::TYPE_VOIDP],
        Fiddle::TYPE_INT
      )
      get_cursor_pos = Fiddle::Function.new(
        user32['GetCursorPos'],
        [Fiddle::TYPE_VOIDP],
        Fiddle::TYPE_INT
      )

      # 1. Obter dimensões lógicas do ClientRect
      rect = "\0" * 16
      return nil if get_client.call(hwnd, rect) == 0
      left, top, right, bottom = rect.unpack('l4')
      cw = right - left
      ch = bottom - top
      return nil if cw <= 0 || ch <= 0

      # 2. Converter Top-Left (0,0) para coordenadas de tela físicas
      pt_tl = [0, 0].pack('l2')
      return nil if client_to_screen.call(hwnd, pt_tl) == 0
      cs_x, cs_y = pt_tl.unpack('l2')

      # 3. Converter Bottom-Right (cw,ch) para coordenadas de tela físicas
      pt_br = [cw, ch].pack('l2')
      return nil if client_to_screen.call(hwnd, pt_br) == 0
      br_x, br_y = pt_br.unpack('l2')

      # 4. Obter posição física do cursor na tela
      cur = [0, 0].pack('l2')
      return nil if get_cursor_pos.call(cur) == 0
      cur_x, cur_y = cur.unpack('l2')

      # 5. Calcular tamanho físico do cliente e posição do mouse relativa a ele
      phys_w = br_x - cs_x
      phys_h = br_y - cs_y
      phys_mx = cur_x - cs_x
      phys_my = cur_y - cs_y

      return phys_w, phys_h, phys_mx, phys_my
    rescue Exception => e
      File.open("fiddle_err.txt", "w") { |f| f.write("#{e.class}: #{e.message}\n#{e.backtrace.join("\n")}") } rescue nil
      return nil
    end
  end

  def get_window_client_size
    return nil if Mouse.is_joiplay?
    begin
      hwnd = Mouse.get_game_window_hwnd
      return nil if !hwnd || hwnd == 0

      require 'fiddle' unless defined?(Fiddle)
      user32 = Fiddle::Handle.new('user32.dll')
      get_client = Fiddle::Function.new(
        user32['GetClientRect'],
        [Fiddle::TYPE_LONG, Fiddle::TYPE_VOIDP],
        Fiddle::TYPE_INT
      )
      rect = "\0" * 16
      res = get_client.call(hwnd, rect)
      return nil if res == 0

      left, top, right, bottom = rect.unpack('l4')
      w = right - left
      h = bottom - top
      return nil if w <= 0 || h <= 0

      dpi = Mouse.get_window_dpi(hwnd)
      dpi_scale = dpi.to_f / 96.0

      w = (w * dpi_scale).round
      h = (h * dpi_scale).round

      return w, h
    rescue Exception => e
      File.open("fiddle_err.txt", "w") { |f| f.write("#{e.class}: #{e.message}\n#{e.backtrace.join("\n")}") } rescue nil
      return nil
    end
  end



  # ── Converte dimensões físicas → escala/borda para o espaço lógico 512×384 ──
  # ⚠️ A RESOLUCAO DO JOGO PERGUNTA-SE, NAO SE ESCREVE.
  #
  # Isto tinha 512x384 cravado. Bate certo com o mkxp.json de hoje, mas e uma
  # COPIA: mudar a resolucao la em cima deslocava todo o toque, e ninguem ia
  # ligar as duas coisas — o sintoma aparece no telemovel de um jogador semanas
  # depois, e o dedo acerta sempre ao lado.
  #
  # O Graphics.width/height sao a fonte de verdade e ja existem. Cair para
  # 512x384 so quando eles nao responderem mantem o comportamento antigo como
  # ultimo recurso, em vez de o ter como regra.
  def calc_scale_from_screen(screen_w, screen_h)
    game_w = (Graphics.width rescue 0).to_f
    game_h = (Graphics.height rescue 0).to_f
    game_w = 512.0 if game_w <= 64
    game_h = 384.0 if game_h <= 64
    aspect_game   = game_w / game_h
    aspect_screen = screen_w.to_f / screen_h.to_f

    if aspect_screen > aspect_game
      # Pillarbox: barras laterais, altura ocupa tudo
      scale    = screen_h.to_f / game_h
      border_x = (screen_w.to_f - game_w * scale) / 2.0
      border_y = 0.0
    else
      # Letterbox: barras acima/abaixo, largura ocupa tudo
      scale    = screen_w.to_f / game_w
      border_x = 0.0
      border_y = (screen_h.to_f - game_h * scale) / 2.0
    end

    scale    = 1.0 if scale <= 0.1
    border_x = [0.0, border_x].max
    border_y = [0.0, border_y].max
    return scale, border_x, border_y
  end

  # ── Rastreio de resolução física para JoiPlay (sem Win32) ──
  def update_joiplay_screen_bounds(raw_x, raw_y)
    $joiplay_raw_max_x ||= 0
    $joiplay_raw_max_y ||= 0
    $joiplay_raw_max_x = raw_x if raw_x > $joiplay_raw_max_x
    $joiplay_raw_max_y = raw_y if raw_y > $joiplay_raw_max_y
  end

  # Devuelve la posición del mouse con respecto a la ventana del juego.
  def getMousePos(catch_anywhere = false)
    begin
      in_window = true
      if !Mouse.is_joiplay? && Input.respond_to?(:mouse_in_window)
        in_window = Input.mouse_in_window
      end
      return nil unless in_window || catch_anywhere

      x = Input.raw_mouse_x
      y = Input.raw_mouse_y

      is_fs = (Graphics.fullscreen rescue false)
      phys = nil

      # Tenta obter via API nativa do Windows (Fiddle) primeiro
      unless Mouse.is_joiplay?
        hwnd = Mouse.get_game_window_hwnd rescue 0
        if hwnd && hwnd != 0
          phys = Mouse.get_physical_mouse_and_client_size(hwnd) rescue nil
        end
      end

      if Mouse.is_joiplay?
        dw = (Graphics.display_width rescue 0)
        dh = (Graphics.display_height rescue 0)
        # ⚠️ SEGUNDA FONTE PARA O TAMANHO DO ECRA, ANTES DE DESISTIR.
        #
        # Quando o display_width nao responde, caia-se na calibracao manual —
        # que e um par de numeros medidos NOUTRO telemovel e gravados a mao. Num
        # aparelho com outro formato, o dedo acerta sempre ao lado, e nao ha
        # nada no ecra a dizer porque.
        #
        # O Graphics.window_size cobre parte desses casos e nao custa nada
        # tentar. A calibracao passa a ser o ultimo recurso, e nao o primeiro
        # desvio.
        if dw <= 64 || dh <= 64
          ws = (Graphics.window_size rescue nil)
          if ws.is_a?(Array) && ws.length >= 2 && ws[0].to_i > 64 && ws[1].to_i > 64
            dw = ws[0].to_i
            dh = ws[1].to_i
          end
        end
        if dw > 64 && dh > 64
          scale, border_x, border_y = Mouse.calc_scale_from_screen(dw, dh)
          x = ((x - border_x) / scale).to_i
          y = ((y - border_y) / scale).to_i
        elsif defined?($mouse_scale_x) && $mouse_scale_x && $mouse_scale_y
          x = ((x - $mouse_border_x) / $mouse_scale_x).to_i
          y = ((y - $mouse_border_y) / $mouse_scale_y).to_i
        end
      elsif phys
        phys_w, phys_h, phys_mx, phys_my = phys
        scale, border_x, border_y = Mouse.calc_scale_from_screen(phys_w, phys_h)
        x = ((phys_mx - border_x) / scale).to_i
        y = ((phys_my - border_y) / scale).to_i
      else
        # Fallback se a API Win32/Fiddle falhar (ou se não for Windows)
        if is_fs
          dw = (Graphics.display_width rescue 1920)
          dh = (Graphics.display_height rescue 1080)
          scale, border_x, border_y = Mouse.calc_scale_from_screen(dw, dh)
          x = ((x - border_x) / scale).to_i
          y = ((y - border_y) / scale).to_i
        else
          gs = (Graphics.scale rescue 1.0)
          gs = 1.0 if gs <= 0.1
          
          scale_x = ($base_mouse_scale_x || 1.2890625) * gs
          scale_y = ($base_mouse_scale_y || 1.2740384615384615) * gs
          border_x = ($base_mouse_border_x || 1.0) * gs
          border_y = ($base_mouse_border_y || 5.572115384615387) * gs

          x = ((x - border_x) / scale_x).to_i
          y = ((y - border_y) / scale_y).to_i
        end
      end

      x = [0, [x, 511].min].max
      y = [0, [y, 383].min].max

      # Diagnóstico: só loga posições DIFERENTES
      if x != ($prev_diag_x || -1) || y != ($prev_diag_y || -1)
        $prev_diag_x = x
        $prev_diag_y = y
        $mouse_diag_count2 ||= 0
        if $mouse_diag_count2 < 30
          $mouse_diag_count2 += 1
          begin
            raw_rx = Input.raw_mouse_x
            raw_ry = Input.raw_mouse_y
            File.open("mouse_debug.txt", "a") { |f|
              f.write("[#{Time.now.strftime('%H:%M:%S')}] raw=(#{raw_rx},#{raw_ry}) → final=(#{x},#{y}) fs=#{is_fs} gs=#{(Graphics.scale rescue 'err')} phys_w=#{(phys ? phys[0] : 'nil')} phys_h=#{(phys ? phys[1] : 'nil')} phys_mx=#{(phys ? phys[2] : 'nil')} phys_my=#{(phys ? phys[3] : 'nil')}\n")
            }
          rescue; end
        end
      end

      return x, y
    rescue
      return nil
    end
  end


end





# Classe adaptadora clássica para compatibilidade com plugins legados
class LegacyMouseAdapter
  def x
    pos = Mouse.getMousePos
    return pos ? pos[0] : 0
  end

  def y
    pos = Mouse.getMousePos
    return pos ? pos[1] : 0
  end

  def click?
    if Input.trigger?(Input::MOUSELEFT)
      $mouse_click_handled = true
      return true
    end
    return false
  end

  def leftClick?
    return self.click?
  end

  def inArea?(area_x, area_y, area_w, area_h)
    mx = self.x
    my = self.y
    return mx >= area_x && mx < area_x + area_w && my >= area_y && my < area_y + area_h
  end
end

# Instanciar o adaptador legado para compatibilidade do DP_PauseMenu e outros
$mouse = LegacyMouseAdapter.new

begin
  log = []
  log << "Graphics methods: #{(Graphics.methods - Object.methods).sort.inspect}"
  log << "System methods: #{(System.methods - Object.methods).sort.inspect}"
  log << "Input methods: #{(Input.methods - Object.methods).sort.inspect}"
  File.write("engine_methods.txt", log.join("\n") + "\n")
rescue Exception => e
  File.write("engine_methods.txt", "Error: #{e.message}\n#{e.backtrace.join("\n")}")
end

Mouse.load_calibration







