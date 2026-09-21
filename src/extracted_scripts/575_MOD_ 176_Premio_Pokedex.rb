# encoding: UTF-8
#===============================================================================
# MOD: 176_Premio_Pokedex
#-------------------------------------------------------------------------------
# O premio por completar a Pokedex deixa de ser o Amuleto Iris e passa a ser
# 5 Masterballs mais uma Caixa de Presente Vermelha.
#
# ⚠️ NAO SE EDITA O MAPA. INTERCEPTA-SE A ENTREGA.
#
# O premio esta num evento — Map029, evento 20 (`oakFinal`), pagina 4:
#
#     pbItemBall(:SHINYCHARM)
#
# Trocar aquilo obrigava a editar o Map029.rxdata e a acrescenta-lo ao lote do
# updater, que hoje so leva 37 ficheiros e nenhum mapa. Mapas sao grandes e
# mudam com frequencia; por um premio, nao compensa abrir essa porta.
#
# Interceptar o `pbItemBall` faz o mesmo trabalho e viaja no Scripts.rxdata, que
# ja vai em todos os updates. E desfaz-se mudando uma constante.
#
# ⚠️ SO NAQUELE EVENTO, E NAO EM TODO O SHINYCHARM.
#
# O amuleto tambem sai das Gift Boxes e da roleta do casino, e esses continuam
# como estao. A troca esta amarrada ao mapa e ao evento — se o premio mudar de
# sitio um dia, isto deixa de agir em vez de agir no sitio errado, que e o lado
# seguro de falhar.
#===============================================================================

module AnilPremioPokedex
  ACTIVO = true

  MAPA   = 29
  EVENTO = 20

  # O que passa a ser entregue. [item, quantidade]
  PREMIO = [[:MASTERBALL, 5], [:GIFT_RED, 1]]

  module_function

  def log(t)
    AnilLanRework.log("[PREMIO_DEX] #{t}") rescue nil
  end

  def no_sitio_certo?
    return false unless ACTIVO
    return false unless ($game_map && $game_map.map_id.to_i == MAPA)
    ev = ($game_map.events[EVENTO] rescue nil)
    return false unless ev
    # O evento que esta a correr AGORA e mesmo aquele?
    (($game_map.interpreter.instance_variable_get(:@event_id) rescue nil).to_i == EVENTO) ||
      (($game_temp.anil_current_event_id rescue nil).to_i == EVENTO)
  rescue
    false
  end

  def entregar!
    dados = PREMIO.map do |item, n|
      nome = (GameData::Item.get(item).name rescue item.to_s)
      $bag.add(item, n)
      [nome, n]
    end
    pbMessage(_INTL("\\PN encontrou o prêmio da Pokédex!"))
    dados.each do |nome, n|
      if n > 1
        pbMessage(_INTL("Recebeu {1} {2}!", n, nome))
      else
        pbMessage(_INTL("Recebeu {1}!", nome))
      end
    end
    log("entregue: #{dados.map { |n, q| "#{q}x #{n}" }.join(', ')}")
    true
  rescue => e
    log("falha ao entregar: #{e.class}: #{e.message}")
    false
  end
end

#-------------------------------------------------------------------------------
# ⚠️ Entra no apply_post_plugin_patches: o pbItemBall e definido no jogo e pode
# ser reescrito por plugins. Depois deles, ganhamos sempre.
#-------------------------------------------------------------------------------
module AnilPremioPokedex
  module_function

  def instalar!
    return false unless defined?(pbItemBall) || Object.private_method_defined?(:pbItemBall)
    return false if Object.private_method_defined?(:anil_premiodex_orig_pbItemBall)
    Object.class_eval do
      alias_method :anil_premiodex_orig_pbItemBall, :pbItemBall

      # ⚠️ *args, E NAO UMA ASSINATURA COPIADA.
      #
      # A primeira versao aceitava `(item, quantity = 1)`, copiado do Essentials
      # de fabrica. Mas neste jogo o pbItemBall tem TRES parametros no motor
      # (0246_Overworld) e um plugin estende-o para QUATRO:
      #
      #     pbItemBall(:HELIXFOSSIL, 1, nil, false)
      #
      # O resultado foi um ArgumentError em QUALQUER item apanhado do chao — nao
      # so no premio da Pokedex. Um jogador novo rebentava na primeira Poke Ball
      # que encontrasse.
      #
      # Envolver um metodo de outra pessoa nunca deve fixar a forma dele. Com
      # `*args` passa-se o que vier, hoje e depois de alguem lhe acrescentar um
      # quinto parametro.
      def pbItemBall(*args, &bloco)
        item = args[0]
        if item.to_s == "SHINYCHARM" && (AnilPremioPokedex.no_sitio_certo? rescue false)
          return AnilPremioPokedex.entregar!
        end
        anil_premiodex_orig_pbItemBall(*args, &bloco)
      end
    end
    log("enxerto no pbItemBall instalado")
    true
  rescue => e
    log("falha a instalar: #{e.class}: #{e.message}")
    false
  end
end

module AnilLanRework
  class << self
    unless method_defined?(:anil_premiodex_orig_apply_post_plugin_patches)
      alias_method :anil_premiodex_orig_apply_post_plugin_patches, :apply_post_plugin_patches rescue nil
    end

    def apply_post_plugin_patches
      anil_premiodex_orig_apply_post_plugin_patches rescue nil
      AnilPremioPokedex.instalar! rescue nil
    end
  end
end
