#===============================================================================
# MOD: 131_Fix_Pesca_Travada.rb
#-------------------------------------------------------------------------------
# Solta o boneco que ficou "a andar parado" depois de fechar o jogo a pescar.
#
# O PROBLEMA
# `pbFishingBegin` (0249_Overworld_Fishing) poe:
#
#     $PokemonGlobal.fishing    = true
#     $game_player.lock_pattern = true
#
# e so o `pbFishingEnd` desfaz. Se o jogo fechar, a ligacao cair ou o save for
# gravado entre os dois, o estado fica GRAVADO NO SAVE. E `lock_pattern` faz o
# Game_Character sair cedo do update do padrao (0049_Game_Character:1081,
# `return if @lock_pattern`), portanto o sprite congela num frame: o jogador
# anda pelo mapa sempre com a mesma pose.
#
# Trocar de skin nao resolve — o travao esta no ESTADO, nao no grafico. Foi
# assim que apareceu: "mesmo que ele troque de skin, nao se movimenta".
#
# A CORRECAO
# Ao carregar o save, se ficou marcado como "a pescar" mas nao ha pesca nenhuma
# a decorrer, desfaz-se o que o pbFishingEnd faria. Corrige o save da pessoa na
# primeira vez que ela entra, sem precisar de mexer no ficheiro.
#
# Porque nao editar o save a mao: o `@lock_pattern` do jogador e gravado por
# REFERENCIA de simbolo (os eventos do mapa tambem tem esse campo), e
# reserializar o save fora do jogo perde dados — uma tentativa dessas encolheu
# um save de 185 KB para 1 KB. Corrigir no arranque e seguro e serve para todos.
#===============================================================================

module AnilFixPescaTravada
  class << self
    def destravar!(motivo)
      return false unless defined?($game_player) && $game_player
      preso_padrao = ($game_player.respond_to?(:lock_pattern) &&
                      $game_player.lock_pattern == true) rescue false
      preso_pesca  = (defined?($PokemonGlobal) && $PokemonGlobal &&
                      $PokemonGlobal.respond_to?(:fishing) &&
                      $PokemonGlobal.fishing == true) rescue false
      return false unless preso_padrao || preso_pesca

      # Mesma sequencia do pbFishingEnd, na ordem dele.
      begin
        if $game_player.respond_to?(:set_movement_type)
          tipo = (defined?($PokemonGlobal) && $PokemonGlobal &&
                  $PokemonGlobal.respond_to?(:surfing) && $PokemonGlobal.surfing) ?
                 :surfing_stopped : :walking_stopped
          $game_player.set_movement_type(tipo)
        end
      rescue
      end
      ($game_player.lock_pattern = false) rescue nil
      ($game_player.straighten)           rescue nil
      if defined?($PokemonGlobal) && $PokemonGlobal && $PokemonGlobal.respond_to?(:fishing=)
        ($PokemonGlobal.fishing = false) rescue nil
      end

      begin
        AnilLanRework.log("[FIX_PESCA] Estado de pesca preso desfeito (#{motivo}): " \
                          "lock_pattern=#{preso_padrao} fishing=#{preso_pesca}")
      rescue
      end
      true
    rescue
      false
    end
  end
end

#===============================================================================
# Ao carregar um save
#===============================================================================
module Game
  class << self
    alias anil_fixpesca_orig_load load unless method_defined?(:anil_fixpesca_orig_load)

    def load(save_data)
      anil_fixpesca_orig_load(save_data)
      AnilFixPescaTravada.destravar!("load") rescue nil
    end
  end
end

#===============================================================================
# Rede de seguranca: tambem ao entrar num mapa.
#
# Cobre o caso de o estado ficar preso DURANTE a sessao (uma pesca interrompida
# por desligamento do servidor, por exemplo), em que o `load` nao volta a correr.
# Sem isto o jogador ficaria congelado ate reiniciar o jogo.
#===============================================================================
if defined?(EventHandlers)
  EventHandlers.add(:on_enter_map, :anil_fix_pesca_travada, proc { |_old|
    begin
      # So mexe se NAO houver interpretador a correr: uma pesca a decorrer tem
      # sempre o evento/script activo, e nao se pode cortar isso a meio.
      parado = !(pbMapInterpreterRunning? rescue false)
      AnilFixPescaTravada.destravar!("on_enter_map") if parado
    rescue
    end
  })
end
