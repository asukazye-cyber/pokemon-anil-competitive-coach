#===============================================================================
# MOD: 120_Trade_Expert_Sem_Lendarios.rb
#-------------------------------------------------------------------------------
# Tira Lendarios e Miticos da roleta do Don Prodigio (plugin Trade Expert).
#
# POR QUE ELE ENTREGAVA LENDARIO
#   O Trade Expert sorteia qualquer especie cujo BST caia entre 90% e 110% do
#   BST do Pokemon entregue (TradeExpert.fetchEqualSpecies). Como Lendario e
#   Mitico tem BST alto mas nao excepcional perto de um pseudo-lendario, bastava
#   entregar um Dragonite/Tyranitar (600) para o sorteio incluir Lugia, Kyogre,
#   Rayquaza e companhia. A TRADING_BLACKLIST do Config.rb so cobria 7 nomes na
#   mao (Mewtwo, Mew, Celebi, Jirachi, Deoxys, Arceus, Genesect) — todo o resto
#   passava.
#
# POR QUE O PATCH ESTA AQUI E NAO NO PLUGIN
#   O jogo carrega os plugins do Data/PluginScripts.rxdata. A pasta
#   Data/PluginScripts_Extraidos/ e apenas uma copia descompilada e NAO ha
#   compilador de volta neste projeto (o compilar.rb so gera Scripts.rxdata),
#   entao editar o Script.rb de la nao teria efeito nenhum no jogo.
#   O PluginManager.runPlugins roda no Main, depois de todos os scripts — e o
#   mesmo gancho que o 110_Multiplayer_PVP_Lineup_Sync usa para vencer o plugin.
#
# O QUE ACONTECE AO ENTREGAR UM LENDARIO
#   A lista de ofertas volta vazia e o proprio plugin ja trata isso: exibe o
#   texto "notrade" ("nao tenho nada que possa te oferecer") e cancela. Nada e
#   perdido — a troca simplesmente nao acontece.
#===============================================================================

module AnilTradeExpertFilter
  # Flags do PBS (pokemon.txt) que o Don Prodigio nao pode mais oferecer.
  # Hoje o PBS tem 71 especies com "Legendary" e 23 com "Mythical".
  # Para tirar tambem os Ultra Beasts e os Paradoxos, acrescente
  # "UltraBeast" e "Paradox" aqui — o PBS ja marca os dois (11 e 22 especies).
  FLAGS_BLOQUEADAS = ["Legendary", "Mythical"]

  def self.bloqueado?(species_id)
    data = GameData::Species.try_get(species_id)
    return false unless data
    FLAGS_BLOQUEADAS.any? { |flag| data.has_flag?(flag) }
  rescue
    false
  end
end

module PluginManager
  class << self
    alias __anil_trade_expert_runPlugins runPlugins unless method_defined?(:__anil_trade_expert_runPlugins)

    def runPlugins(*args)
      __anil_trade_expert_runPlugins(*args)

      return unless defined?(::TradeExpert)
      return unless ::TradeExpert.respond_to?(:fetchEqualSpecies)

      ::TradeExpert.singleton_class.class_eval do
        unless method_defined?(:anil_sem_lendarios_fetchEqualSpecies)
          alias_method :anil_sem_lendarios_fetchEqualSpecies, :fetchEqualSpecies

          # Filtra a lista de candidatos JA montada, em vez de reescrever o
          # sorteio: assim o modo Randomizer/Monotype do plugin continua
          # decidindo o que decidia antes, e so o resultado e peneirado.
          def fetchEqualSpecies(poke, margin = 0.1)
            lista = anil_sem_lendarios_fetchEqualSpecies(poke, margin)
            return lista unless lista.is_a?(Array)
            lista.reject { |spec| AnilTradeExpertFilter.bloqueado?(spec) }
          end
        end
      end
    rescue => e
      (AnilLanRework.log("Trade Expert sem lendarios: falha ao aplicar patch: #{e.class}: #{e.message}") rescue nil)
    end
  end
end
