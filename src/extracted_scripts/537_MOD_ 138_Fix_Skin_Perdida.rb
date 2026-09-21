# encoding: UTF-8
#===============================================================================
# MOD: 138_Fix_Skin_Perdida
#-------------------------------------------------------------------------------
# A skin escolhida voltava ao personagem padrao ao apanhar um item do chao.
#
# A CAUSA (e nao e das edicoes de skin)
#
# O script base ja protegia a skin no fim do Game_Player#set_movement_type:
#
#     if $player&.multiplayer_skin && !is_vehicle
#       @character_name = $player.multiplayer_skin
#     elsif new_charset
#       @character_name = new_charset
#     end
#
# Só que o plugin "050 Advanced Items - Field Moves" REDEFINE o metodo inteiro, e
# a versao dele acaba em `@character_name = new_charset if new_charset` — sem
# essa parte. Como os plugins carregam depois do script base, e a versao do
# plugin que vale, e qualquer chamada a set_movement_type devolve o boneco ao
# charset do metadata. Apanhar item passa por esse plugin, dai o sintoma.
#
# A CORRECAO
#
# Reaplica-se a skin DEPOIS do metodo (seja ele qual for) correr. Assim funciona
# tanto com o plugin como sem ele, e continuara a funcionar se o plugin for
# atualizado — nao se reescreve a logica dele, so se corrige o resultado.
#
# ⚠️ Tem de entrar pelo apply_post_plugin_patches. Um alias feito no carregamento
# normal apanharia a versao do script base, que o plugin substitui a seguir, e
# esta correcao ficaria em codigo morto.
#===============================================================================

module AnilFixSkinPerdida
  module_function

  def em_veiculo?
    return true if $PokemonGlobal&.surfing
    return true if $PokemonGlobal&.diving
    return true if $PokemonGlobal&.bicycle
    false
  rescue
    false
  end

  # A skin so vale a pena reaplicar se ela existir de facto: um nome guardado de
  # uma skin que ja nao esta no disco deixaria o jogador invisivel.
  def skin_valida
    nome = ($player.multiplayer_skin.to_s rescue "")
    return nil if nome.empty?
    return nil unless File.exist?("Graphics/Characters/#{nome}.png")
    nome
  rescue
    nil
  end

  def instalar!
    return unless defined?(Game_Player)
    return if @instalado
    @instalado = true

    Game_Player.class_eval do
      unless method_defined?(:anil_fix_skin_set_movement_type)
        alias_method :anil_fix_skin_set_movement_type, :set_movement_type

        def set_movement_type(type)
          anil_fix_skin_set_movement_type(type)
          # Veiculo tem sprite proprio (surf, bicicleta, mergulho): ai a skin nao
          # se aplica, e forcar deixaria o jogador a andar a pe sobre a agua.
          return if AnilFixSkinPerdida.em_veiculo?
          nome = AnilFixSkinPerdida.skin_valida
          @character_name = nome if nome
        end
      end
    end
    AnilLanRework.log("[SKIN] set_movement_type protegido (a skin ja nao se perde)") rescue nil
  rescue => e
    AnilLanRework.log("[SKIN] falha ao proteger set_movement_type: #{e.class}: #{e.message}") rescue nil
  end
end

module AnilLanRework
  class << self
    if !method_defined?(:anil_fixskin_orig_apply_post_plugin_patches)
      alias_method :anil_fixskin_orig_apply_post_plugin_patches, :apply_post_plugin_patches rescue nil
    end

    def apply_post_plugin_patches
      anil_fixskin_orig_apply_post_plugin_patches if respond_to?(:anil_fixskin_orig_apply_post_plugin_patches)
      AnilFixSkinPerdida.instalar!
    end
  end
end

AnilLanRework.log("138_Fix_Skin_Perdida carregado") rescue nil
