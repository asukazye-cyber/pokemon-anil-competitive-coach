#===============================================================================
# MOD: 055_Multiplayer_Speech_Bubbles.rb
#-------------------------------------------------------------------------------
# Sistema de Balões de Fala (Speech Bubbles) Pixel-Perfect com 9-Slice Scaling,
# efeito de revelação progressiva (Máquina de Escrever) e animações suaves.
#===============================================================================

class SpeechBubble < Sprite
  attr_reader :disposed
  attr_reader :char_id

  def disposed?
    return true if @disposed
    begin
      return super
    rescue
      return true
    end
  end

  MAX_WIDTH = 220 # Largura máxima do balão na tela
  CORNER_SIZE = 24 # Tamanho dos cantos fixos na textura de 96x96
  CENTER_SIZE = 48 # Tamanho da região central esticável

  def initialize(viewport, text, char_id = 0, duration = 4.0, typewriter = true)
    super(viewport)
    @char_id = char_id
    @duration = duration
    @typewriter = typewriter
    
    # Texturas do balão processadas
    @body_tex = nil
    @tail_tex = nil
    begin
      b_path = pbResolveBitmap("Graphics/Pictures/speech_bubble_body")
      @body_tex = Bitmap.new(b_path) if b_path
      t_path = pbResolveBitmap("Graphics/Pictures/speech_bubble_tail")
      @tail_tex = Bitmap.new(t_path) if t_path
    rescue
    end
    
    unless @body_tex && @tail_tex
      AnilLanRework.log("[SPEECH] Erro ao carregar texturas do balão. Abortando criação.") rescue nil
      self.dispose
      return
    end

    @text = text.to_s
    @full_text_length = @text.length
    @char_index = @typewriter ? 0.0 : @full_text_length.to_f
    @frame_count = 0
    @disposed = false
    @fading_out = false
    @life_time = duration * Graphics.frame_rate rescue duration * 40
    
    # 1. Medir o texto e dimensionar o balão
    # Configura um bitmap temporário para medição de fonte
    temp_bmp = Bitmap.new(32, 32)
    temp_bmp.font.name = MessageConfig::FONT_NAME rescue "Outfit"
    temp_bmp.font.size = 15
    
    # Envelopa o texto
    @lines = wrap_text(@text, MAX_WIDTH, temp_bmp)
    text_width = 0
    text_height = 0
    
    @lines.each do |line|
      w = temp_bmp.text_size(line).width
      text_width = w if w > text_width
    end
    
    line_height = temp_bmp.text_size("A").height
    text_height = @lines.length * line_height
    
    temp_bmp.dispose

    # Margens internas robustas para o 9-slice (evita transbordo nas bordas de 24px)
    padding_x = 36
    padding_y = 20
    
    @body_width = [text_width + padding_x, 80].max
    @body_height = [text_height + padding_y, 35].max
    
    # Altura da cauda é 16, e ela se sobrepõe em 2px à base do corpo
    @tail_width = 24
    @tail_height = 16
    @tail_overlap = 2
    
    @bmp_width = @body_width
    @bmp_height = @body_height + @tail_height - @tail_overlap

    # 2. Criar bitmap limpo para o balão
    self.bitmap = Bitmap.new(@bmp_width, @bmp_height)
    self.bitmap.font.name = MessageConfig::FONT_NAME rescue "Outfit"
    self.bitmap.font.size = 15
    self.bitmap.font.color = Color.new(20, 24, 35) # Cor escura e elegante
    
    # 3. Renderizar o fundo 9-slice e a cauda uma única vez para cache
    @cached_bg = Bitmap.new(@bmp_width, @bmp_height)
    draw_9_slice_body(@cached_bg)
    draw_tail(@cached_bg)
    
    # 4. Configurar Pivot (Origem) no bico da cauda do balão (bottom-center)
    self.ox = @bmp_width / 2
    self.oy = @bmp_height
    
    # 5. Configurar micro-animação de Pop (crescimento da base do personagem)
    @zoom = 0.6
    self.zoom_x = @zoom
    self.zoom_y = @zoom
    
    # Posiciona imediatamente
    update_position
  end

  def update
    return if disposed?
    
    if @fading_out
      self.zoom_x = [self.zoom_x - 0.08, 0.0].max
      self.zoom_y = [self.zoom_y - 0.08, 0.0].max
      self.opacity = [self.opacity - 25, 0].max
      if self.opacity <= 0 || self.zoom_x <= 0
        self.dispose
      end
      return
    end

    # Reduz o tempo de vida
    @life_time -= 1
    if @life_time <= 0
      fade_out_and_dispose
      return
    end

    # Incrementa animação de pop/bounce
    if @zoom < 1.0
      @zoom += (1.0 - @zoom) * 0.22 # Suave ease-out
      if 1.0 - @zoom < 0.01
        @zoom = 1.0
      end
      self.zoom_x = @zoom
      self.zoom_y = @zoom
    end

    # Incrementa revelação progressiva da máquina de escrever
    if @typewriter && @char_index < @full_text_length
      @char_index += 0.8 # Velocidade de revelação (letras por frame)
      @char_index = @full_text_length if @char_index > @full_text_length
      redraw_text
    elsif @frame_count == 0
      redraw_text
    end

    @frame_count += 1
    update_position
  end

  def update_position
    return if disposed?
    character = find_character
    if !character
      self.dispose
      return
    end

    # Se for um RemotePeer do multiplayer e mudou de mapa, removemos o balão
    is_remote = false
    begin
      if defined?(AnilLanRework) && defined?(AnilLanRework::RemotePeer)
        is_remote = character.is_a?(AnilLanRework::RemotePeer)
      end
    rescue
    end

    if is_remote
      map_changed = false
      begin
        map_changed = (character.map_id != $game_map.map_id)
      rescue
      end
      if map_changed
        self.dispose
        return
      end
    else
      map_changed = false
      begin
        char_map = character.map
        map_changed = ($game_map && char_map && $game_map.map_id != char_map.map_id)
      rescue
      end
      if map_changed
        self.dispose
        return
      end
    end

    # Posiciona a origem (bico da cauda) exatamente acima da cabeça do personagem
    self.x = character.screen_x
    # O screen_y nativo é a base dos pés. Ajustamos para subir o balão e posicionar a cauda por cima
    self.y = character.screen_y - 58
    begin
      self.z = character.screen_z + 150
    rescue
      self.z = 9999
    end
  end

  def redraw_text
    return if disposed?
    self.bitmap.clear
    
    # 1. Desenha o fundo cacheado (Body + Tail)
    self.bitmap.blt(0, 0, @cached_bg, Rect.new(0, 0, @bmp_width, @bmp_height))
    
    # 2. Desenha o texto parcial (máquina de escrever)
    visible_chars = @char_index.to_i
    chars_drawn = 0
    
    line_height = self.bitmap.text_size("A").height
    total_text_height = @lines.length * line_height
    # Centraliza o bloco de texto verticalmente no corpo do balão de forma dinâmica (deslocado 1px para cima)
    current_y = [(@body_height - total_text_height) / 2 - 1, 8].max
    
    @lines.each do |line|
      break if chars_drawn >= visible_chars
      
      line_chars = line.length
      if chars_drawn + line_chars <= visible_chars
        # Desenha a linha completa centralizada
        draw_line_centered(line, current_y)
        chars_drawn += line_chars
      else
        # Desenha apenas parte da linha correspondente à revelação
        partial_line = line[0...(visible_chars - chars_drawn)]
        draw_line_centered(partial_line, current_y)
        break
      end
      current_y += line_height
    end
  end

  def draw_line_centered(text_line, y_pos)
    line_w = self.bitmap.text_size(text_line).width
    # Centraliza o texto horizontalmente dentro do corpo do balão
    x_pos = (@body_width - line_w) / 2
    self.bitmap.draw_text(x_pos, y_pos, line_w, self.bitmap.text_size(text_line).height, text_line)
  end

  def draw_9_slice_body(dest_bmp)
    # Cantos
    dest_bmp.blt(0, 0, @body_tex, Rect.new(0, 0, CORNER_SIZE, CORNER_SIZE)) # TL
    dest_bmp.blt(@body_width - CORNER_SIZE, 0, @body_tex, Rect.new(CORNER_SIZE + CENTER_SIZE, 0, CORNER_SIZE, CORNER_SIZE)) # TR
    dest_bmp.blt(0, @body_height - CORNER_SIZE, @body_tex, Rect.new(0, CORNER_SIZE + CENTER_SIZE, CORNER_SIZE, CORNER_SIZE)) # BL
    dest_bmp.blt(@body_width - CORNER_SIZE, @body_height - CORNER_SIZE, @body_tex, Rect.new(CORNER_SIZE + CENTER_SIZE, CORNER_SIZE + CENTER_SIZE, CORNER_SIZE, CORNER_SIZE)) # BR
    
    # Bordas Laterais Esticadas
    dest_bmp.stretch_blt(Rect.new(CORNER_SIZE, 0, @body_width - (CORNER_SIZE * 2), CORNER_SIZE), @body_tex, Rect.new(CORNER_SIZE, 0, CENTER_SIZE, CORNER_SIZE)) # Topo
    dest_bmp.stretch_blt(Rect.new(CORNER_SIZE, @body_height - CORNER_SIZE, @body_width - (CORNER_SIZE * 2), CORNER_SIZE), @body_tex, Rect.new(CORNER_SIZE, CORNER_SIZE + CENTER_SIZE, CENTER_SIZE, CORNER_SIZE)) # Base
    dest_bmp.stretch_blt(Rect.new(0, CORNER_SIZE, CORNER_SIZE, @body_height - (CORNER_SIZE * 2)), @body_tex, Rect.new(0, CORNER_SIZE, CORNER_SIZE, CENTER_SIZE)) # Esquerda
    dest_bmp.stretch_blt(Rect.new(@body_width - CORNER_SIZE, CORNER_SIZE, CORNER_SIZE, @body_height - (CORNER_SIZE * 2)), @body_tex, Rect.new(CORNER_SIZE + CENTER_SIZE, CORNER_SIZE, CORNER_SIZE, CENTER_SIZE)) # Direita
    
    # Miolo Centro Esticado
    dest_bmp.stretch_blt(Rect.new(CORNER_SIZE, CORNER_SIZE, @body_width - (CORNER_SIZE * 2), @body_height - (CORNER_SIZE * 2)), @body_tex, Rect.new(CORNER_SIZE, CORNER_SIZE, CENTER_SIZE, CENTER_SIZE))
  end

  def draw_tail(dest_bmp)
    tail_x = (@body_width - @tail_width) / 2
    tail_y = @body_height - @tail_overlap
    dest_bmp.blt(tail_x, tail_y, @tail_tex, Rect.new(0, 0, @tail_width, @tail_height))
  end

  def find_character
    return nil unless $game_map
    if @char_id == 0 || @char_id.nil?
      $game_player
    elsif @char_id.is_a?(String) && defined?(AnilLanRework)
      AnilLanRework.players[@char_id]
    else
      $game_map.events[@char_id]
    end
  end

  # Quantas linhas o balao aceita antes de cortar com reticencias.
  MAX_LINHAS = 6

  # ⚠️ UMA PALAVRA SOZINHA MAIOR QUE O BALAO NAO CABIA EM LADO NENHUM.
  #
  # O corte so acontecia nos espacos. Uma mensagem como "aaaa...a" de 60 letras
  # nao tem espaco nenhum, portanto saia uma linha unica com 60 letras e o balao
  # esticava de um lado ao outro do ecra — que e exactamente o que se via.
  #
  # Agora, quando uma palavra sozinha nao cabe na largura maxima, parte-se a
  # palavra letra a letra. E o unico corte possivel: nao ha onde mais quebrar.
  def wrap_text(text, max_width, temp_bmp)
    lines = []
    current_line = ""

    text.to_s.split(" ").each do |word|
      if temp_bmp.text_size(word).width > max_width
        # a palavra nao cabe sozinha: fecha a linha em curso e parte-a a letra
        unless current_line.empty?
          lines << current_line
          current_line = ""
        end
        pedaco = ""
        word.each_char do |c|
          if !pedaco.empty? && temp_bmp.text_size(pedaco + c).width > max_width
            lines << pedaco
            pedaco = c
          else
            pedaco += c
          end
        end
        current_line = pedaco
        next
      end

      test_line = current_line.empty? ? word : "#{current_line} #{word}"
      if temp_bmp.text_size(test_line).width > max_width
        lines << current_line unless current_line.empty?
        current_line = word
      else
        current_line = test_line
      end
    end

    lines << current_line unless current_line.empty?

    # Tecto de altura: um balao de 20 linhas tapava o mapa todo.
    if lines.length > MAX_LINHAS
      lines = lines[0, MAX_LINHAS]
      lines[-1] = lines[-1].to_s[0, [lines[-1].to_s.length - 1, 1].max] + "..."
    end

    lines
  end

  def fade_out_and_dispose
    @fading_out = true
  end

  def dispose
    return if disposed?
    @disposed = true
    @cached_bg.dispose if @cached_bg rescue nil
    self.bitmap.dispose if self.bitmap rescue nil
    super rescue nil
  end
end

#===============================================================================
# Método Global de Acesso Acessível por Eventos e Scripts
#===============================================================================
def pbSpeechBubble(text, character_id = 0, duration = 3.5)
  return unless $scene.is_a?(Scene_Map)
  begin
    $scene.add_speech_bubble(text, character_id, duration)
  rescue => e
    AnilLanRework.log("Erro ao pbSpeechBubble: #{e.message}") rescue nil
  end
end
