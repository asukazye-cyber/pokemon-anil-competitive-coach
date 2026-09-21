#===============================================================================
# Walking charset, for use in text entry screens and load game screen
#===============================================================================
class TrainerWalkingCharSprite < Sprite
  attr_accessor :anim_duration

  # Default time in seconds for one animation cycle of a charset. The icon for a
  # storage box is 0.4 instead (set manually).
  ANIMATION_DURATION = 0.5

  def initialize(charset, viewport = nil)
    super(viewport)
    @animbitmap = nil
    self.charset = charset
    @current_frame = 0   # Current pattern
    @anim_duration = ANIMATION_DURATION
  end

  def dispose
    @animbitmap&.dispose
    super
  end

  def charset=(value)
    @animbitmap&.dispose
    @animbitmap = nil
    raw_value = value.to_s.strip
    raw_value = raw_value.sub(/\.(png|jpg|jpeg|gif|bmp)\z/i, "")
    candidates = []
    candidates << raw_value if !raw_value.empty?
    candidates << sprintf("Graphics/Characters/%s", raw_value) if !raw_value.empty? && raw_value !~ %r{\AGraphics/}i
    candidates << sprintf("Graphics/Skins/%s", raw_value) if !raw_value.empty? && raw_value !~ %r{\AGraphics/}i
    @charset = nil
    candidates.each do |candidate|
      @charset = pbResolveBitmap(candidate)
      break if @charset
    end
    if @charset
      @animbitmap = AnimatedBitmap.new(@charset)
      self.bitmap = @animbitmap.bitmap
      self.src_rect.set(0, 0, self.bitmap.width / 4, self.bitmap.height / 4)
    else
      self.bitmap = nil
    end
  end

  # Used for the box icon in the naming screen.
  def altcharset=(value)
    @animbitmap&.dispose
    @animbitmap = nil
    @charset = pbResolveBitmap(value)
    if @charset
      @animbitmap = AnimatedBitmap.new(@charset)
      self.bitmap = @animbitmap.bitmap
      self.src_rect.set(0, 0, self.bitmap.width / 4, self.bitmap.height)
    else
      self.bitmap = nil
    end
  end

  def update_frame
    @current_frame = (4 * (System.uptime % @anim_duration) / @anim_duration).floor
  end

  def update
    @updating = true
    super
    if @animbitmap
      @animbitmap.update
      self.bitmap = @animbitmap.bitmap
    end
    # Update animation
    update_frame
    self.src_rect.x = self.src_rect.width * @current_frame
    @updating = false
  end
end

