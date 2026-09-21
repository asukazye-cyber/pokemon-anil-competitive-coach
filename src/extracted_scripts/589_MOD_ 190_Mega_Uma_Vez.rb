# encoding: UTF-8
#===============================================================================
# MOD: 190_Mega_Uma_Vez — a trava da Mega Evolução (e o diário dela)
#===============================================================================
# ⚠️ NAO HAVIA TRAVA NENHUMA. HAVIA UMA CONVENCAO.
#
# Passei tres rondas a procurar quem apagava o "ja usou", e a pergunta estava
# mal feita. O motor nao TRAVA a segunda mega: ele escreve um -2 numa casa de um
# array partilhado e confia que toda a gente o respeite.
#
#     @megaEvolution[side][owner] = -2
#
# Esse array e escrito pelo motor, por dois MODs deste projecto, pelo Deluxe
# Battle Kit e pelo Cable Club. Cinco donos, um estado. Basta um deles repor a
# casa — por engano, por ordem de carga, ou porque no caso DELE fazia sentido —
# e a mega volta a estar disponivel. Nao e um bug com um culpado: e um desenho
# sem dono.
#
# Encontrar quem repoe continua a ser possivel, e o diario aqui em baixo ainda o
# mostra a acontecer. Mas nao e isso que fecha a porta. O que fecha a porta e
# uma trava PROPRIA, que so este ficheiro escreve e que mais ninguem conhece:
#
#     @anil_mega_usada[[side, owner]] = true
#
# Chave por [lado, dono] de proposito: numa batalha com dois treinadores do
# mesmo lado, cada um continua a ter a SUA mega; num coop, cada jogador tambem.
# Corta-se so o que tem de ser cortado.
#
# A trava esta em DOIS sitios, e os dois sao precisos:
#
#   pbCanMegaEvolve?  esconde o botao — e a parte que o jogador ve.
#   pbMegaEvolve      recusa a execucao — e a parte que importa. O diario
#                     mostrou a IA a escrever no marcador SEM passar pelo
#                     registo oficial, portanto ha caminhos que nao perguntam
#                     nada a ninguem antes de mega-evoluir.
#
# ⚠️ INSTALA-SE TARDE, no `apply_post_plugin_patches`. A primeira versao deste
# MOD aliasava no corpo da classe e partiu as batalhas todas: um metodo que
# ainda nao existisse fazia o `alias` levantar NameError, o script morria a
# meio, e o que se via era "a batalha ameaca comecar e volta ao overworld", sem
# erro na cara. Guardar isto aqui para nao se repetir.
#===============================================================================

module AnilMegaUmaVez
  FICHEIRO = "Data/log_mega.txt"
  DIARIO   = true      # false: a trava continua; so para de escrever o diario

  module_function

  def escrever(texto)
    return unless DIARIO
    File.open(FICHEIRO, "a") { |f| f.puts("[#{Time.now.strftime('%H:%M:%S.%L')}] #{texto}") }
  rescue
    nil
  end

  def foto(mega)
    return "?" unless mega.is_a?(Array)
    mega.map { |lado| Array(lado).join(",") }.join(" | ")
  rescue
    "?"
  end

  def abrir!
    return unless DIARIO
    File.delete(FICHEIRO) rescue nil
    escrever("=" * 70)
    escrever("mega: trava propria activa; o diario e so para se ver")
    escrever("=" * 70)
  end

  def instalar!
    return if @instalado
    @instalado = true

    Battle.class_eval do
      def self.anil_mega_gancho(nome, &corpo)
        return unless method_defined?(nome)
        velho = :"anil_mega_orig_#{nome.to_s.gsub('?', '_p')}"
        return if method_defined?(velho)
        alias_method(velho, nome)
        define_method(nome, &corpo)
      end

      # A chave da trava. Sem battler valido devolve nil, e nil nunca tranca —
      # na duvida, deixa passar: um jogador impedido de megar sem razao e pior
      # do que um que mega duas vezes.
      def anil_mega_chave(idxBattler)
        b = @battlers[idxBattler]
        return nil unless b
        [b.idxOwnSide, pbGetOwnerIndexFromBattlerIndex(idxBattler)]
      rescue
        nil
      end

      def anil_mega_ja_usou?(idxBattler)
        ch = anil_mega_chave(idxBattler)
        return false unless ch
        @anil_mega_usada ||= {}
        @anil_mega_usada[ch] ? true : false
      rescue
        false
      end

      def anil_mega_marcar!(idxBattler)
        ch = anil_mega_chave(idxBattler)
        return unless ch
        @anil_mega_usada ||= {}
        @anil_mega_usada[ch] = true
        AnilMegaUmaVez.escrever("TRANCADO lado=#{ch[0]} dono=#{ch[1]}")
      rescue
        nil
      end

      # ── a porta que se ve ──────────────────────────────────────────────
      anil_mega_gancho(:pbCanMegaEvolve?) do |idxBattler|
        if anil_mega_ja_usou?(idxBattler)
          AnilMegaUmaVez.escrever("RECUSADO (botao) idx=#{idxBattler} — este dono ja megou")
          next false
        end
        send(:anil_mega_orig_pbCanMegaEvolve_p, idxBattler)
      end

      # ── a porta que importa ────────────────────────────────────────────
      anil_mega_gancho(:pbMegaEvolve) do |idxBattler|
        if anil_mega_ja_usou?(idxBattler)
          AnilMegaUmaVez.escrever("RECUSADO (execucao) idx=#{idxBattler} " \
            "— segunda mega barrada  mega=[#{AnilMegaUmaVez.foto(@megaEvolution)}]")
          next nil
        end
        b = (@battlers[idxBattler] rescue nil)
        esp = ((b && b.pokemon) ? b.pokemon.speciesName : "?")
        AnilMegaUmaVez.escrever("MEGA! idx=#{idxBattler} especie=#{esp} " \
          "mega=[#{AnilMegaUmaVez.foto(@megaEvolution)}]")
        r = send(:anil_mega_orig_pbMegaEvolve, idxBattler)
        # Marca-se DEPOIS de correr: se a mega falhar a meio, nao se gasta a
        # unica que ele tinha.
        anil_mega_marcar!(idxBattler)
        r
      end

      # O diario continua a mostrar o marcador do motor a ser reposto — e a
      # prova de que a trava propria era mesmo necessaria.
      anil_mega_gancho(:pbCommandPhase) do
        antes = AnilMegaUmaVez.foto(@megaEvolution)
        r = send(:anil_mega_orig_pbCommandPhase)
        depois = AnilMegaUmaVez.foto(@megaEvolution)
        if antes != depois && antes.include?("-2") && !depois.include?("-2")
          AnilMegaUmaVez.escrever("(o motor perdeu o -2 outra vez: [#{antes}] -> " \
            "[#{depois}] — a trava propria e que segura)")
        end
        r
      end

      anil_mega_gancho(:pbStartBattleCore) do
        AnilMegaUmaVez.abrir!
        @anil_mega_usada = {}
        send(:anil_mega_orig_pbStartBattleCore)
      end
    end
  rescue => e
    (File.open("Data/log_mega.txt", "a") { |f|
      f.puts("FALHOU A INSTALAR A TRAVA: #{e.class}: #{e.message}") } rescue nil)
  end
end

if defined?(AnilLanRework) && AnilLanRework.respond_to?(:apply_post_plugin_patches)
  module AnilLanRework
    class << self
      unless method_defined?(:anil_megauma_orig_apply_post_plugin_patches)
        alias anil_megauma_orig_apply_post_plugin_patches apply_post_plugin_patches
        def apply_post_plugin_patches
          anil_megauma_orig_apply_post_plugin_patches
          AnilMegaUmaVez.instalar!
        end
      end
    end
  end
end
