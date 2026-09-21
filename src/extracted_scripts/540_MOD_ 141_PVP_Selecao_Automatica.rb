# encoding: UTF-8
#===============================================================================
# MOD: 141_PVP_Selecao_Automatica
#-------------------------------------------------------------------------------
# Nao pedir para escolher a equipe quando nao ha nada a escolher.
#
# O PROBLEMA
#
# Num 6x6 com a party cheia, o jogo abria na mesma o ecra de selecao. Com seis
# Pokemon para seis vagas nao existe escolha nenhuma a fazer: o jogador tinha de
# marcar os seis, um a um, so para chegar ao mesmo sitio. Era so atrito.
#
# ONDE SE CORRIGE
#
# No CableClub.choose_team, que e por onde TODOS os caminhos passam — o duelo
# personalizado (000d, dois sitios), o 029, o 110 e o proprio ecra do Cable
# Club. Corrigir aqui evita repetir a mesma condicao em cinco lados e ficar com
# um deles esquecido.
#
# QUANDO SE SALTA
#
# So quando existe UMA unica equipe possivel, e isso exige as tres coisas:
#
#   1. a party enche exactamente o limite da regra (6 Pokemon, 6 vagas);
#   2. todos passam no isPokemonValid? — se algum estivesse banido, sobrariam
#      menos que o limite e a escolha voltaria a existir;
#   3. o conjunto passa na validacao de equipe da regra.
#
# Fora disso o ecra abre como sempre. Um 6x6 com party de 4, ou um 3x3 com party
# de 6, continuam a ter escolha real e continuam a perguntar.
#
# A ORDEM
#
# Salta-se com a ordem natural da party ([0,1,2,...]), logo o primeiro Pokemon
# da batalha e o mesmo que ja lidera no mapa. Quem quiser outro lider reordena a
# party no menu antes de desafiar — que e como funciona em qualquer batalha
# normal do jogo.
#===============================================================================

module AnilPvpSelecaoAutomatica
  module_function

  # Devolve a ordem a usar sem perguntar, ou nil se a escolha for mesmo precisa.
  def ordem_obrigatoria(ruleset)
    return nil unless ruleset
    party = Array($player&.party)
    return nil if party.empty?

    limite = (ruleset.maxLength rescue nil).to_i
    return nil if limite <= 0
    # A party tem de encher o limite: com menos, deixar de fora e uma escolha.
    return nil unless party.length == limite

    # Um banido faria a equipe possivel encolher abaixo do limite.
    if ruleset.respond_to?(:isPokemonValid?)
      return nil unless party.all? { |pkmn| ruleset.isPokemonValid?(pkmn) }
    end

    # Regras de equipe (especies repetidas, itens repetidos, soma de niveis...).
    # Se a party inteira nao passar, ha combinacoes a considerar: perguntar.
    if ruleset.respond_to?(:canRegisterTeam?)
      return nil unless ruleset.canRegisterTeam?(party)
    elsif ruleset.respond_to?(:hasValidTeam?)
      return nil unless ruleset.hasValidTeam?(party)
    end

    (0...party.length).to_a
  rescue => e
    # Qualquer duvida: abrir o ecra. Saltar por engano tiraria ao jogador uma
    # decisao que era dele.
    AnilLanRework.log("[PVP] selecao automatica desistiu: #{e.class}: #{e.message}") rescue nil
    nil
  end

  def instalar!
    return unless defined?(CableClub)
    return if @instalado
    @instalado = true

    CableClub.singleton_class.class_eval do
      unless method_defined?(:anil_selauto_orig_choose_team)
        alias_method :anil_selauto_orig_choose_team, :choose_team

        def choose_team(ruleset)
          ordem = AnilPvpSelecaoAutomatica.ordem_obrigatoria(ruleset)
          if ordem
            AnilLanRework.log("[PVP] party cheia para o limite da regra: batalha inicia sem o ecra de selecao") rescue nil
            return ordem
          end
          anil_selauto_orig_choose_team(ruleset)
        end
      end
    end

    AnilLanRework.log("141_PVP_Selecao_Automatica instalado") rescue nil
  rescue => e
    AnilLanRework.log("[PVP] falha ao instalar selecao automatica: #{e.class}: #{e.message}") rescue nil
  end
end

# CableClub e de plugin, entao so existe depois do runPlugins.
if defined?(AnilLanRework)
  module AnilLanRework
    class << self
      if !method_defined?(:anil_selauto_orig_apply_post_plugin_patches)
        alias_method :anil_selauto_orig_apply_post_plugin_patches, :apply_post_plugin_patches rescue nil
      end

      def apply_post_plugin_patches
        anil_selauto_orig_apply_post_plugin_patches if respond_to?(:anil_selauto_orig_apply_post_plugin_patches)
        AnilPvpSelecaoAutomatica.instalar!
      end
    end
  end
end

AnilLanRework.log("141_PVP_Selecao_Automatica carregado") rescue nil
