# encoding: UTF-8
#===============================================================================
# MOD: 144_Estatisticas_Multiplayer
#-------------------------------------------------------------------------------
# Faz o VERSO do cartao de treinador contar as batalhas PVP e as trocas online.
#
# O QUE ESTAVA A ACONTECER
#
# O verso (tecla D no cartao) ja mostrava tres numeros ha muito tempo:
#
#     Combates Online       {wins}  {lost}
#     Intercambios Online   {trades}
#
# Eles saem de campos que o plugin 031 (Cable Club) poe no Player:
#
#     class Player < Trainer
#       def online_stats
#         @online_stats ||= { battles_wins: 0, battles_lost: 0, trade_count: 0 }
#       end
#     end
#
# ⚠️ E NINGUEM escrevia neles. Procurando no projeto inteiro so existem a
# definicao e a leitura — nenhuma atribuicao. O `||= 0` garantia que ficavam
# sempre a zero. Quem os alimentaria era o Cable Club original, e o multiplayer
# deste jogo nao passa por la.
#
# A PRIMEIRA TENTATIVA ESTAVA ERRADA
#
# Eu tinha criado contadores paralelos em $stats e desenhado na FRENTE do
# cartao, sem saber que o verso existia. Ficaram dois conjuntos de numeros sem
# ligacao entre si, e o que o jogador olhava continuava a zero. Agora escreve-se
# nos campos que o jogo JA le, e a frente do cartao volta ao original.
#
# ONDE VIVEM
#
# Em @online_stats, no Player, portanto dentro do save. Sao COSMETICOS. Quando
# o sistema ranqueado entrar, os pontos de rank NAO podem vir daqui — tem de ser
# do servidor, porque o save e enviado pelo cliente e ja houve injeccao por
# debug neste projeto.
#===============================================================================

module AnilEstatisticasMP
  module_function

  # O Hash do plugin 031. Devolve nil se o plugin nao estiver la, e ai nao se
  # conta nada — melhor do que rebentar por causa de um numero de vitrine.
  def stats_online
    return nil unless defined?($player) && $player
    return nil unless $player.respond_to?(:online_stats)
    $player.online_stats
  rescue
    nil
  end

  def registrar_pvp(venceu)
    st = stats_online
    return unless st.is_a?(Hash)
    chave = venceu ? :battles_wins : :battles_lost
    st[chave] = st[chave].to_i + 1
    diag("PVP #{venceu ? 'vitoria' : 'derrota'} -> #{st[:battles_wins].to_i}V/#{st[:battles_lost].to_i}D")
  rescue => e
    diag("falha ao contar PVP: #{e.class}: #{e.message}")
  end

  def registrar_troca
    st = stats_online
    return unless st.is_a?(Hash)
    st[:trade_count] = st[:trade_count].to_i + 1
    diag("troca online -> #{st[:trade_count].to_i}")
  rescue => e
    diag("falha ao contar troca: #{e.class}: #{e.message}")
  end

  # A batalha que acabou era um PVP?
  #
  # O contexto do BattleSync e a fonte: e criado no activate_context com
  # mode: :pvp e so existe durante um duelo. Nada e inferido.
  def era_pvp?
    ctx = (AnilLanRework::BattleSync.active_context rescue nil)
    return false unless ctx
    (ctx.mode rescue nil) == :pvp
  rescue
    false
  end

  # Log proprio, num ficheiro so deste MOD.
  #
  # ⚠️ NAO se usa o AnilLanRework.log: ele so escreve com $anil_debug_log_enabled
  # ligado, e essa flag global NAO pode ser ligada — ela trava o "recuperar
  # partida". Ficheiro separado resolve sem tocar nela.
  def diag(texto)
    return unless (anil_diagnostico_ligado? rescue false)
    File.open("Data/anil_stats_pvp.txt", "a:UTF-8") do |f|
      f.puts("[#{Time.now.strftime('%d/%m %H:%M:%S')}] #{texto}")
    end
  rescue
  end

  def instalar!
    return if @instalado
    @instalado = true

    # -------------------------------------------------------------------------
    # Conta-se no TrainerBattle.start_core, e nao no evento :on_end_battle.
    #
    # O evento traz o desfecho, mas quem diz se aquilo era PVP e o
    # BattleSync.active_context — e nao ha garantia de que ele ainda esteja de
    # pe nesse instante: durante a batalha o cliente continua a processar
    # pacotes, e varios caminhos chamam clear_context.
    #
    # O start_core e firme por tres razoes: e chamado DE DENTRO do
    # start_pvp_battle (o contexto acabou de ser criado), DEVOLVE o desfecho
    # directamente (`return outcome`, 0261:583), e nao depende das battle_rules
    # — que ja foram limpas quando a batalha acaba, o erro da primeira versao.
    # -------------------------------------------------------------------------
    if defined?(TrainerBattle) && TrainerBattle.respond_to?(:start_core)
      TrainerBattle.singleton_class.class_eval do
        unless method_defined?(:anil_stats_orig_start_core)
          alias_method :anil_stats_orig_start_core, :start_core

          def start_core(*args)
            # Lido ANTES: se algo limpar o contexto durante a batalha, ainda
            # sabemos o que ela era. Guarda-se tambem o parceiro e o battle_id
            # pela mesma razao — depois da batalha o contexto pode ja nao estar.
            era_pvp = AnilEstatisticasMP.era_pvp?
            ctx = (AnilLanRework::BattleSync.active_context rescue nil)
            parceiro = era_pvp ? (ctx.partner_id.to_s rescue "") : ""
            batalha  = era_pvp ? (ctx.battle_id.to_s  rescue "") : ""

            # O PVP nao manda o perdedor para o Centro Pokemon: a party real nem
            # entra na luta (sao copias niveladas em 50) e o restore devolve a
            # original no fim, portanto nao ha o que curar — sobrava so a multa.
            AnilRanqueado.marcar_pvp_sem_derrota! if era_pvp && defined?(AnilRanqueado)

            desfecho = anil_stats_orig_start_core(*args)

            if era_pvp
              d = desfecho.to_i
              AnilEstatisticasMP.diag("fim de PVP: desfecho=#{d} vs=#{parceiro}")
              # 1 venceu, 2 perdeu, 3 fugiu, 5 empate. Fuga conta como derrota.
              AnilEstatisticasMP.registrar_pvp(d == 1) if [1, 2, 3, 5].include?(d)

              # RANQUEADO: so o PERDEDOR reporta. Fuga tambem e derrota — quem
              # sai do duelo perdeu.
              if defined?(AnilRanqueado) && [2, 3].include?(d) && !parceiro.empty?
                turnos = begin
                  (@battle || $game_temp.instance_variable_get(:@anil_last_battle)).turnCount.to_i
                rescue
                  99
                end
                AnilRanqueado.reportar_derrota(batalha, parceiro, turnos)
              end
            end
            desfecho
          end
        end
      end
      diag("contagem instalada no start_core")
    else
      diag("AVISO: TrainerBattle.start_core indisponivel — nada sera contado")
    end
  rescue => e
    diag("falha ao instalar: #{e.class}: #{e.message}")
  end
end

if defined?(AnilLanRework)
  module AnilLanRework
    class << self
      if !method_defined?(:anil_stats_orig_apply_post_plugin_patches)
        alias_method :anil_stats_orig_apply_post_plugin_patches, :apply_post_plugin_patches rescue nil
      end

      def apply_post_plugin_patches
        anil_stats_orig_apply_post_plugin_patches if respond_to?(:anil_stats_orig_apply_post_plugin_patches)
        AnilEstatisticasMP.instalar!
      end
    end
  end
end

AnilLanRework.log("144_Estatisticas_Multiplayer carregado") rescue nil
