# encoding: UTF-8
#===============================================================================
# Headless RGSS/runtime stubs for running the real Añil battle engine outside
# the game (tests only — never shipped in Scripts.rxdata).
#===============================================================================

module Graphics
  WIDTH_CACHE = 640
  def self.width; 640; end
  def self.height; 480; end
  def self.update; end
  def self.freeze; end
  def self.transition(*_a); end
  def self.frame_reset; end
  def self.wait(*_a); end
  def self.brightness; 255; end
  def self.brightness=(*_a); end
  def self.frame_count; 0; end
  def self.frame_count=(*_a); end
  def self.fullscreen?; false; end
  def self.resize_screen(*_a); end
end

module Audio
  def self.file_test?(*_a); false; end
  %w[bgm_create bgm_play bgm_stop bgm_fade me_play se_play se_stop].each do |m|
    define_singleton_method(m) { |* _a| }
  end
end

module Input
  DOWN = 4; LEFT = 5; RIGHT = 6; UP = 8
  A = 18; B = 19; C = 20
  L = 25; R = 26
  SHIFT = 21; CTRL = 17; ALT = 23
  F5 = 35; F6 = 36; F7 = 37; F8 = 38; F9 = 39
  ACTION = 23; SPECIAL = 24
  def self.update; end
  def self.press?(_b); false; end
  def self.trigger?(_b); false; end
  def self.repeat?(_b); false; end
  def self.dir4; 0; end
  def self.dir8; 0; end
end

class Color
  attr_reader :red, :green, :blue, :alpha
  def initialize(r = 0, g = 0, b = 0, a = 255)
    @red, @green, @blue, @alpha = r, g, b, a
  end
  def set(r, g, b, a = 255)
    @red, @green, @blue, @alpha = r, g, b, a
  end
end

class Rect
  attr_accessor :x, :y, :width, :height
  def initialize(x = 0, y = 0, w = 0, h = 0)
    @x, @y, @width, @height = x, y, w, h
  end
end

class Font
  attr_accessor :name, :size, :bold, :italic, :color, :shadow, :outline
  def initialize(name = nil, size = nil)
    @name = name; @size = size || 18
    @bold = false; @italic = false
    @color = Color.new(255, 255, 255)
    @shadow = true; @outline = true
  end
  def copy; Font.new(@name, @size); end
  def set(*_a); end
end

class Table
  def initialize(*_a); end
  def [](*_a); 0; end
  def []=(*_a); end
  def resize(*_a); end
  def xsize; 1; end
  def ysize; 1; end
  def zsize; 1; end
end

class Bitmap
  attr_reader :width, :height
  def initialize(w = 0, h = 0)
    @width = w; @height = h
  end
  def dispose; end
  def disposed?; false; end
  def font; @font ||= Font.new; end
  def fill_rect(*_a); end
  def clear; end
  def draw_text(*_a); end
  def text_size(s); Rect.new(0, 0, s.to_s.length * 8, 16); end
  def blt(*_a); end
  def stretch_blt(*_a); end
end

class Viewport
  attr_accessor :x, :y, :width, :height, :z, :ox, :oy, :visible
  def initialize(*_a)
    @x = @y = @z = @ox = @oy = 0
    @visible = true
    @rect = Rect.new
  end
  def rect; @rect; end
  def dispose; end
  def disposed?; false; end
  def update; end
  def flash(*_a); end
end

class Sprite
  attr_accessor :x, :y, :z, :ox, :oy, :zoom_x, :zoom_y, :angle, :mirror,
                :visible, :opacity, :bush_depth, :bush_opacity
  def initialize(_vp = nil)
    @x = @y = @z = @ox = @oy = 0
    @zoom_x = @zoom_y = 1.0
    @angle = 0
    @visible = true
    @opacity = 255
    @bitmap = nil
  end
  def bitmap; @bitmap; end
  def bitmap=(b); @bitmap = b; end
  def src_rect; @src_rect ||= Rect.new; end
  def color; @color ||= Color.new(0, 0, 0, 0); end
  def tone; @tone ||= Color.new(0, 0, 0, 0); end
  def wave_amp; 0; end
  def wave_amp=(*_a); end
  def wave_speed; 0; end
  def wave_speed=(*_a); end
  def dispose; end
  def disposed?; false; end
  def update; end
  def flash(*_a); end
end

class Plane
  def initialize(*_a); end
  def dispose; end
  def update; end
end

class Tilemap
  def initialize(*_a); end
  def dispose; end
  def update; end
end

class Window
  attr_accessor :x, :y, :width, :height, :z, :visible, :active
  def initialize(*_a)
    @x = @y = @z = 0; @visible = true; @active = true
    @width = @height = 0
    @contents = Bitmap.new(1, 1)
    @cursor_rect = Rect.new
  end
  def contents; @contents; end
  def cursor_rect; @cursor_rect; end
  def dispose; end
  def disposed?; false; end
  def update; end
  def refresh; end
end

# RGSS data helpers -----------------------------------------------------------

HEAD_DIR = "/work/tests/headless"
# GameData loads "Data/<name>.dat" relative to the process cwd; the harness
# keeps the game's data (originals + generated types.dat) in the TRACKED
# repo-root Data/ directory so it survives environment restores.
DATA_DIR = "/work/Data"
# Marshal restores RGSS-dumped strings as ASCII-8BIT under WASI; the game's
# translation layer expects UTF-8. Recursively re-tags every string after load
# (PBS data contains no genuinely binary strings).
def _deep_force_utf8(obj, seen = {}.compare_by_identity)
  return obj if seen.key?(obj)
  case obj
  when String
    obj.force_encoding("UTF-8")
  when Array
    seen[obj] = true
    obj.each { |v| _deep_force_utf8(v, seen) }
  when Hash
    seen[obj] = true
    obj.each { |k, v| _deep_force_utf8(k, seen); _deep_force_utf8(v, seen) }
  when Class, Module, NilClass, TrueClass, FalseClass, Numeric, Symbol, Method, Proc
    nil
  else
    # Data objects (GameData::* instances): recurse into their ivars.
    seen[obj] = true
    obj.instance_variables.each do |iv|
      _deep_force_utf8(obj.instance_variable_get(iv), seen)
    end
  end
  obj
end

def load_data(path)
  if path.is_a?(String) && !path.start_with?("/")
    if path.start_with?("Data/")
      alt = File.join(DATA_DIR, path.sub(%r{\AData/}, ""))
      path = alt if File.exist?(alt)
    else
      alt = File.join(HEAD_DIR, path)
      path = alt if File.exist?(alt)
    end
  end
  return nil if path.is_a?(String) && !File.exist?(path)
  _deep_force_utf8(Marshal.load(File.binread(path)))
end

def save_data(obj, path)
  File.binwrite(path, Marshal.dump(obj))
end

def pbSetNarrowFont(*_a); end

# Essentials-ish globals used by battle code paths ----------------------------

$DEBUG = false
$INTERNAL = false
$player = nil
$Trainer = nil
$game_temp = nil
$game_system = nil
$game_map = nil
$game_party = nil
$game_player = nil
$game_screen = nil
# Minimal switch/variable stand-ins: battle code reads them for feature
# gates (e.g. pbCanMegaEvolve? reads $game_switches[NO_MEGA_EVOLUTION]).
# All switches default to false, all variables to 0, writes are accepted.
class GameSwitchesStub
  def [](i); @s ||= {}; @s[i] || false; end
  def []=(i, v); @s ||= {}; @s[i] = v; end
  def length; 5000; end
end
class GameVariablesStub
  def [](i); @v ||= {}; @v[i] || 0; end
  def []=(i, v); @v ||= {}; @v[i] = v; end
end
$game_switches = GameSwitchesStub.new
$game_variables = GameVariablesStub.new
$PokemonBag = nil
$PokemonGlobal = nil
$PokemonStorage = nil
$PokemonTemp = nil
$UTC = nil

module Kernel
  def pbRgssPlayer?; false; end
  def pbGetEdition; 2; end
  def nil_or_empty?(s); s.nil? || s.empty?; end
end

# Minimal stand-ins for trainer classes referenced at Pokemon construction
# time (case/when evaluates the constants even when owner is nil). The real
# game defines these elsewhere; headless tests don't need their behavior.
unless defined?(Player)
  class Player; end
end
unless defined?(NPCTrainer)
  class NPCTrainer
    attr_reader :name, :trainertype, :skill_level, :flags
    def initialize(name = "", trainertype = 0, party = [], skill_level = 1, flags: [])
      @name, @trainertype, @party = name, trainertype, party
      @skill_level, @flags = skill_level, flags
    end
    def full_name; @name; end
  end
end

# $game_temp stand-in: Pokemon#form reads in_battle/in_storage from it during
# battle-time form calculations.
unless defined?(PokemonGlobalMetadata)
  class PokemonGlobalMetadata; end
end

unless defined?(Game_Temp)
  class Game_Temp
    attr_accessor :in_battle, :in_storage, :battle_rules
    def initialize
      @in_battle = false
      @in_storage = false
      @battle_rules = nil
    end
  end
end
$game_temp = Game_Temp.new
$game_temp.in_battle = true


# The game's PBDebug.logonerr swallows exceptions from pbUseMove and friends
# and forwards them to pbPrintException (defined in 021_0019_Errors.rb, which
# the headless slice doesn't load). In TESTS an engine exception must never be
# silently swallowed: re-raise it so failures surface loudly. (In-game the real
# pbPrintException exists and the game's own behavior applies.)
module PBDebug
  def self.pbPrintException(e)
    raise e
  end
end


# mkxp/RGSS System module (uptime etc.) — absent under WASI.
unless defined?(System)
  module System
    def self.uptime; Process.clock_gettime(Process::CLOCK_MONOTONIC); end
    def self.real_uptime; Process.clock_gettime(Process::CLOCK_MONOTONIC); end
  end
end
