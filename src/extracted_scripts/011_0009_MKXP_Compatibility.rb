#===============================================================================
# Using mkxp-z v2.4.2/d13f35c - built 2025/10/28.
# https://github.com/mkxp-z/mkxp-z/actions/runs/18874497198
#===============================================================================
$VERBOSE = nil

# Define Encoding if it's not already defined
unless defined?(Encoding)
  module Encoding
    UTF_8 = "UTF-8".freeze
    def self.find(name)
      # Mimic Encoding.find behavior
      return UTF_8 if name == "UTF-8"

      raise ArgumentError, "unknown encoding: #{name}"
    end
  end
end


Font.default_shadow = false if Font.respond_to?(:default_shadow)
Encoding.default_internal = Encoding::UTF_8
Encoding.default_external = Encoding::UTF_8

def pbSetWindowText(string)
  System.set_window_title(string || System.game_title)
end

def pbSetResizeFactor(factor)
  if !$ResizeInitialized
    Graphics.resize_screen(Settings::SCREEN_WIDTH, Settings::SCREEN_HEIGHT)
    $ResizeInitialized = true
  end
  if factor < 0 || factor == 4
    Graphics.fullscreen = true if !Graphics.fullscreen
  else
    Graphics.fullscreen = false if Graphics.fullscreen
    Graphics.scale = (factor + 1) * 0.5
    Graphics.center
  end
end

#===============================================================================
#
#===============================================================================
class Bitmap
  attr_accessor :text_offset_y

  alias mkxp_draw_text draw_text unless method_defined?(:mkxp_draw_text)

  def draw_text(x, y, width, height = nil, text = "", align = 0)
    if x.is_a?(Rect)
      x.y -= (@text_offset_y || 0)
      # rect, string & alignment
      mkxp_draw_text(x, y, width)
    else
      y -= (@text_offset_y || 0)
      height = text_size(text).height
      mkxp_draw_text(x, y, width, height, text, align)
    end
  end
end

#===============================================================================
#
#===============================================================================
if defined?(System::VERSION) && System::VERSION != Essentials::MKXPZ_VERSION
  printf(sprintf("\e[1;33mWARNING: mkxp-z version %s detected, but this version of Pokémon Essentials was designed for mkxp-z version %s.\e[0m\r\n",
                 System::VERSION, Essentials::MKXPZ_VERSION))
  printf("\e[1;33mWARNING: Pokémon Essentials may not work properly.\e[0m\r\n")
end

Font.default_name = "Anil Sans"
Font.default_bold = true

class Font
  alias ptbr_orig_init initialize
  def initialize(*args)
    if args.length > 0
      args[0] = "Anil Sans"
    end
    ptbr_orig_init(*args)
    self.name = "Anil Sans"
    self.bold = true
  end

  alias ptbr_orig_bold= bold=
  def bold=(val)
    ptbr_orig_bold=(true)
  end

  alias ptbr_orig_name= name=
  def name=(val)
    ptbr_orig_name=("Anil Sans")
  end
end