# encoding: utf-8
# ==============================================================================
# HOTFIX — Game_Character#screen_z crash quando @tile_id ainda é nil
# (corrige NoMethodError: undefined method '>' for nil:NilClass durante login)
# ==============================================================================

class Game_Character
  alias __anilfix_screen_z screen_z unless method_defined?(:__anilfix_screen_z)
  def screen_z(height = 0)
    @tile_id ||= 0
    __anilfix_screen_z(height)
  end
end

class Sprite_OWShadow
  alias __anilfix_ow_update update unless method_defined?(:__anilfix_ow_update)
  def update
    return if @event.nil? || (@event.respond_to?(:tile_id) && @event.tile_id.nil?)
    __anilfix_ow_update
  end
end
