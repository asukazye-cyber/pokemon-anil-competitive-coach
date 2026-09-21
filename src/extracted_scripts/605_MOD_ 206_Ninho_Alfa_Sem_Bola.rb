# encoding: utf-8
#===============================================================================
# NOS NINHOS ALFA NAO SE ATIRA BOLA
#
# ⚠️ O QUE ESTAVA A ACONTECER.
#
# Um Ninho Alfa e um evento de mapa chamado `nidoIncursion`. Ele abre uma luta
# contra um Pokemon muito forte e, ACABADA a luta, conta o que aconteceu:
#
#     "¡El Pokémon Alfa ha huido! Pero ha soltado un objeto tras de sí."
#
# Repare-se: o texto e fixo. O evento assume que o bicho foge sempre — e por
# isso nunca proibiu a bola. Quem atirasse uma e tivesse sorte APANHAVA o
# lendario, ele ia para a box, e o evento dizia na mesma que ele tinha fugido.
# Daí o relato: "o jogo diz que fugiu, mas vao para a box".
#
# ⚠️ E O MOTOR JA TEM A TRANCA. FALTAVA ALGUEM PUXA-LA.
#
# O `Battle` tem `disablePokeBalls`, e o `prepare_battle` aplica-lha a partir
# das regras da luta. Os eventos dos ninhos e que nunca chamam
# `setBattleRule("disablePokeBalls")`.
#
# ⚠️ PORQUE NAO SE CORRIGEM OS EVENTOS.
#
# Sao 21 mapas com ninhos, e mais os que vierem. Editar cada um a mao tem tres
# defeitos: os mapas NAO viajam no update (o jogador ficava com a versao velha),
# um ninho novo nasceria outra vez sem tranca, e eu teria de acertar em 21
# sitios sem falhar nenhum.
#
# Aqui e um sitio so, viaja no Scripts.rxdata, e cobre os ninhos que ainda nao
# existem.
#===============================================================================
module AnilNinhoAlfa
  # O nome do evento, como esta nos mapas. Compara-se sem maiusculas e sem
  # acentos para nao depender de como foi escrito em cada um.
  NOMES = ["nidoincursion", "ninhoincursao", "nidoalfa", "ninhoalfa"].freeze

  module_function

  def nome_de_ninho?(nome)
    n = nome.to_s.downcase.strip
    return false if n.empty?
    NOMES.any? { |alvo| n.include?(alvo) }
  rescue
    false
  end

  # ⚠️ QUEM ESTA A CORRER E QUEM MANDA, E NAO QUEM ESTA POR PERTO.
  #
  # A tentacao era varrer o mapa a procura de um evento com este nome e, se
  # houvesse, trancar a bola. Isso trancava a bola no MAPA INTEIRO: um ninho num
  # canto da rota impedia apanhar um Rattata do outro lado.
  #
  # O que interessa e quem chamou a luta. O interpretador do mapa sabe-o — o
  # `get_character(0)` devolve o evento que esta a correr o script neste
  # momento. Fora de um evento nao devolve nada, e entao nao ha nada a trancar.
  def numa_luta_de_ninho?
    interp = (pbMapInterpreter rescue nil)
    return false unless interp
    ev = (interp.get_character(0) rescue nil)
    return false unless ev
    nome_de_ninho?(ev.name)
  rescue
    false
  end
end

#-------------------------------------------------------------------------------
# O GANCHO
#
# ⚠️ TEM DE SER DEPOIS DOS PLUGINS.
#
# O `prepare_battle` e de uma classe do motor e ha plugins que lhe mexem. Um
# alias posto no corpo do ficheiro corre antes deles e pode ser deitado fora —
# e a licao que este projecto ja aprendeu com o gancho da captura. Vai no
# `apply_post_plugin_patches`, que corre no fim de tudo.
#-------------------------------------------------------------------------------
module AnilLanRework
  class << self
    unless method_defined?(:anil_ninho_orig_apply_post_plugin_patches)
      alias_method :anil_ninho_orig_apply_post_plugin_patches,
                   :apply_post_plugin_patches rescue nil
    end

    def apply_post_plugin_patches
      anil_ninho_orig_apply_post_plugin_patches rescue nil
      AnilNinhoAlfa.instalar!
    end
  end
end

module AnilNinhoAlfa
  def self.instalar!
    return if @instalado
    return unless defined?(Battle::Scene) || defined?(BattleCreationHelperMethods)
    alvo = nil
    alvo = BattleCreationHelperMethods if defined?(BattleCreationHelperMethods)
    unless alvo && (alvo.respond_to?(:prepare_battle) rescue false)
      # Nao ha onde enganchar: em vez de rebentar, fica dito no log e o jogo
      # segue como antes.
      (AnilLanRework.log("[NINHO] sem prepare_battle para enganchar") rescue nil)
      return
    end
    @instalado = true
    alvo.singleton_class.send(:alias_method, :anil_ninho_orig_prepare_battle, :prepare_battle)
    alvo.define_singleton_method(:prepare_battle) do |battle|
      anil_ninho_orig_prepare_battle(battle)
      if AnilNinhoAlfa.numa_luta_de_ninho?
        # ⚠️ Depois do original, e nao antes: o original le as regras e escreve
        # por cima. Escrevendo primeiro, ele apagava isto.
        (battle.disablePokeBalls = true) rescue nil
        (AnilLanRework.log("[NINHO] bola trancada nesta luta") rescue nil)
      end
      battle
    end
    (AnilLanRework.log("[NINHO] tranca da bola instalada") rescue nil)
  rescue => e
    (AnilLanRework.log("[NINHO] falha a instalar: #{e.class}: #{e.message}") rescue nil)
  end
end
