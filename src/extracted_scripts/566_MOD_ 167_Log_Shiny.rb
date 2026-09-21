# encoding: UTF-8
#===============================================================================
# MOD: 167_Log_Shiny
#-------------------------------------------------------------------------------
# Conta spawns e conta sorteios, e escreve os dois lado a lado.
#
# ⚠️ A PERGUNTA E UMA SO: NASCEU UM POKEMON SEM PASSAR PELO SORTEIO?
#
# Toda a gente que investiga isto acaba a ler codigo e a concluir que "devia
# funcionar". Este log nao conclui nada: conta. Se ao fim de uma hora os
# `spawns` e os `sorteios` forem numeros diferentes, ha spawns a escapar — e a
# linha de cada um diz porque.
#
# ⚠️ E MEDE-SE O QUE SE ESPERAVA, NAO SO O QUE SAIU.
#
# Cada sorteio soma 1/alvo a uma conta. Ao fim de N spawns sabe-se quantos
# shinies eram de esperar. "Cacei horas e nao saiu" quer dizer coisas muito
# diferentes se o esperado era 0,3 ou se era 12 — e so o segundo caso e um bug.
#
# ⚠️ DESLIGADO POR OMISSAO DESDE 05/09/2026. ANTES ESTAVA SEMPRE LIGADO.
#
# A ideia original era boa — o jogador corria o diagnostico sem instalar nada —
# mas o preco so apareceu no Android: e UMA LINHA POR SPAWN, e cada linha e um
# `File.open` + escrita + fecho. Os spawns nao param enquanto se anda, portanto
# isto era um acesso ao disco a cada poucos passos, para sempre, em todos os
# jogadores. O ficheiro chegou aos 366 KB numa sessao.
#
# Era tambem o unico dos seis logs de diagnostico que ignorava o interruptor:
# o `anil_lento`, o `recover_trace`, o `evento_sem_coordenada`, o `coopauth` e
# o `coopcc_debug` ja obedeciam todos ao `Data/anil_debug.txt`.
#
# Para voltar a medir a taxa de shiny, basta criar `Data/anil_debug.txt` — que
# e o mesmo gesto que liga os outros. Nao se liga o `$ENABLE_DEBUG_LOGS`, que
# trava o "recuperar partida".
#===============================================================================

module AnilLogShiny
  ACTIVO = (anil_diagnostico_ligado? rescue false)

  # De quantos em quantos spawns se escreve o resumo.
  RESUMO_CADA = 25

  @spawns = 0
  @sorteios = 0
  @shinies = 0
  @esperado = 0.0
  @ficheiro = nil

  class << self
    attr_reader :spawns, :sorteios

    def caminho
      @ficheiro ||= begin
        base = (defined?(Dir.pwd) ? Dir.pwd : ".")
        File.join(base, "anil_shiny.log")
      end
    end

    def escrever(txt)
      return unless ACTIVO
      File.open(caminho, "a") { |f| f.write("#{txt}\n") }
    rescue
      nil
    end

    def hora
      Time.now.strftime("%H:%M:%S")
    rescue
      "??:??:??"
    end

    # ------------------------------------------------------------- o contexto
    # Tudo o que muda a conta, lido no momento do spawn e nao adivinhado.
    def contexto
      cadeia = ($PokemonGlobal.catchcombo rescue nil)
      c_n = (cadeia.is_a?(Array) ? cadeia[0].to_i : 0)
      c_e = (cadeia.is_a?(Array) ? cadeia[1].to_s : "-")
      perfume = (AnilPerfume.activo? rescue false)
      passos  = (AnilPerfume.passos rescue 0)
      amuleto = (AnilCadeiaCoop.tem_amuleto? rescue false)
      taxa    = (Settings::SHINY_POKEMON_CHANCE rescue 0)
      # ⚠️ A MINHA cadeia e a SOMADA sao numeros diferentes.
      #
      # O alvo sai da somada (a minha mais a do parceiro), mas so a minha e
      # que se ve no jogo. Sem as duas lado a lado nao ha como saber se o
      # parceiro esta mesmo a contribuir.
      somada = (AnilCadeiaCoop.cadeia_somada(c_e) rescue c_n)
      "cadeia=#{c_n}/#{c_e} somada=#{somada} amuleto=#{amuleto ? 1 : 0} " \
      "perfume=#{perfume ? passos : 0} taxa_ess=#{taxa}"
    rescue
      "contexto indisponivel"
    end

    # ------------------------------------------------------------- os eventos
    # Um Pokemon nasceu no mapa (qualquer um: local, remoto, o que for).
    def spawn!(origem)
      return unless ACTIVO
      @spawns += 1
      @origem_ultima = origem
      @sorteado = false
    rescue
      nil
    end

    # O sorteio correu mesmo. `alvo` e o 1-em-N usado.
    def sorteio!(origem, especie, alvo, saiu)
      return unless ACTIVO
      @sorteios += 1
      @sorteado = true
      @shinies += 1 if saiu
      @esperado += (alvo > 0 ? 1.0 / alvo : 0.0)
      escrever("#{hora} [#{origem}] #{especie} alvo=1/#{alvo} " \
               "=> #{saiu ? 'SHINY' : 'normal'} | #{contexto}")
      resumo! if (@spawns % RESUMO_CADA) == 0
    rescue
      nil
    end

    # O sorteio foi SALTADO. E esta a linha que interessa se houver bug.
    def saltado!(origem, especie, porque)
      return unless ACTIVO
      @sorteado = true   # ja se explicou, nao ha que voltar a queixar
      escrever("#{hora} [#{origem}] #{especie} SEM SORTEIO (#{porque}) | #{contexto}")
    rescue
      nil
    end

    # Chamado depois do spawn: se ninguem sorteou nem explicou, e um escape.
    def fechar_spawn!(origem, especie)
      return unless ACTIVO
      return if @sorteado
      escrever("#{hora} [#{origem}] #{especie} !!! SPAWN SEM PASSAR PELO SORTEIO !!! | #{contexto}")
    rescue
      nil
    end

    def resumo!
      falta = @spawns - @sorteios
      escrever("---- spawns=#{@spawns} sorteios=#{@sorteios}" \
               "#{falta > 0 ? " FALTAM=#{falta}" : ""} " \
               "shinies=#{@shinies} esperados=#{format('%.2f', @esperado)}")
    rescue
      nil
    end
  end
end

#-------------------------------------------------------------------------------
# ⚠️ O CONTADOR DE SPAWNS FICA POR FORA DE TUDO.
#
# Instala-se depois do MOD 070, portanto envolve o hook dele — que por sua vez
# envolve o do DBK, que envolve o do VOE. Assim conta-se toda a gente que nasce,
# inclusive por caminhos que ainda nao conhecemos.
#-------------------------------------------------------------------------------
module AnilLanRework
  class << self
    if !method_defined?(:anil_logshiny_orig_apply_post_plugin_patches)
      alias_method :anil_logshiny_orig_apply_post_plugin_patches, :apply_post_plugin_patches rescue nil
    end

    def apply_post_plugin_patches
      anil_logshiny_orig_apply_post_plugin_patches if respond_to?(:anil_logshiny_orig_apply_post_plugin_patches)
      return unless AnilLogShiny::ACTIVO
      begin
        Game_Map.class_eval do
          if method_defined?(:spawnPokeEvent) && !method_defined?(:anil_logshiny_orig_spawnPokeEvent)
            alias_method :anil_logshiny_orig_spawnPokeEvent, :spawnPokeEvent

            def spawnPokeEvent(x, y, pokemon)
              origem = ($vower_sync_spawning ? "remoto" : "local")
              AnilLogShiny.spawn!(origem)
              r = anil_logshiny_orig_spawnPokeEvent(x, y, pokemon)
              AnilLogShiny.fechar_spawn!(origem, (pokemon.species.to_s rescue "?"))
              r
            end
          end
        end
        AnilLogShiny.escrever("=== #{AnilLogShiny.hora} log de shiny ligado ===")
      rescue => e
        AnilLanRework.log("[LOGSHINY] falhou: #{e.class}: #{e.message}") rescue nil
      end
    end
  end
end
