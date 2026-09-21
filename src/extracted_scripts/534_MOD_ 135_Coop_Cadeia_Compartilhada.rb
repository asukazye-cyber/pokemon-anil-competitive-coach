# encoding: UTF-8
#===============================================================================
# MOD: 135_Coop_Cadeia_Compartilhada
#-------------------------------------------------------------------------------
# A cadeia de derrotados (catch combo) passa a SOMAR entre os dois jogadores do
# grupo, desde que seja a MESMA especie e que estejam no MESMO MAPA. Se cada um
# derrotar 20 Geodude, a cadeia vale 40 para os dois — e a chance de shiny sobe
# de acordo, mais um bonus fixo de -100 no divisor por estarem caçando juntos.
#
# COMO A CADEIA FUNCIONA NO JOGO (plugin VOE)
#   $PokemonGlobal.catchcombo = [contagem, especie]
#   Sobe 1 ao vencer ou capturar; zera quando a especie muda.
#   A chance de shiny sai de degraus de CHAINLENGTH (10):
#       0-9   -> P          10-19 -> P*4/5     20-29 -> P*3/5
#       30-39 -> P*2/5      40+   -> P/5
#   onde P = SHINYPROBABILITY.
#
# POR QUE ISTO E UM MOD E NAO UMA EDICAO DO PLUGIN
#
# A regra da cadeia vive num EventHandler do PluginScripts.rxdata, que nao pode
# ser distribuido pelo updater. Mas o EventHandlers guarda os callbacks por
# chave, e existe `EventHandlers.remove(evento, chave)` — entao da para tirar o
# handler do plugin e por o nosso no lugar, tudo a partir do Scripts.rxdata.
#
# ⚠️ O `EventHandlers.add` NAO substitui: `@callbacks[key] = proc if
# !@callbacks.has_key?(key)`. Sem o `remove` antes, o nosso handler seria
# ignorado em silencio e nada disto funcionaria.
#===============================================================================

module AnilCadeiaCoop
  BONUS_COOP = 100          # tirado do NUMERO FINAL (1 em N) enquanto a cadeia soma

  # ⚠️ A CADEIA VALE PARA TUDO O QUE APARECE, E NAO SO PARA A ESPECIE PERSEGUIDA.
  #
  # Ha especies com spawn muito raro. Exigir que a cadeia fosse da MESMA especie
  # tornava-as quase inalcancaveis em shiny: para encadear era preciso primeiro
  # encontra-las dezenas de vezes, que e justamente o que nao acontece.
  #
  # O valor da cadeia nao muda — os degraus sao os mesmos. O que muda e a quem
  # ele se aplica: quem tem 40 de cadeia leva 1 em 1000 em QUALQUER Pokemon que
  # nasca, e nao so no que anda a cacar.
  #
  # Poe a false para voltar ao comportamento antigo.
  CADEIA_VALE_PARA_TODOS = true
  CHAVE_HANDLER = :hacer_shiny_a_salvajes

  class << self
    # [contagem, especie, map_id] do parceiro, como ele nos contou por ultimo.
    attr_accessor :cadeia_parceiro
  end
  @cadeia_parceiro = nil

  module_function

  def parceiro
    pid = (AnilLanRework.coop_party_partner_id rescue nil)
    return nil unless pid
    AnilLanRework.players[pid.to_s] rescue nil
  end

  # A cadeia do parceiro so conta se ele estiver no MESMO MAPA e a perseguir a
  # MESMA especie. Sem isto, a cadeia subiria sozinha enquanto o outro joga
  # noutro sitio, o que nao e caçar junto.
  def cadeia_do_parceiro_para(especie)
    dados = @cadeia_parceiro
    return 0 unless dados.is_a?(Array) && dados.length >= 3
    return 0 unless parceiro
    # a especie do parceiro so importa se a cadeia ainda for por especie
    return 0 unless CADEIA_VALE_PARA_TODOS || dados[1].to_s == especie.to_s
    # o MAPA importa sempre: cacar junto e estar no mesmo sitio
    return 0 unless $game_map && dados[2].to_i == $game_map.map_id.to_i
    dados[0].to_i
  end

  def minha_cadeia
    c = ($PokemonGlobal.catchcombo rescue nil)
    c.is_a?(Array) ? c : [0, 0]
  end

  # Cadeia efectiva = a minha + a do parceiro (quando elegivel).
  def cadeia_somada(especie)
    minha = minha_cadeia
    propria = if CADEIA_VALE_PARA_TODOS
                minha[0].to_i
              else
                (minha[1].to_s == especie.to_s) ? minha[0].to_i : 0
              end
    propria + cadeia_do_parceiro_para(especie)
  end

  def somando?(especie)
    cadeia_do_parceiro_para(especie) > 0
  end

  # Avisa o parceiro sempre que a nossa cadeia mexe. Vai o mapa junto porque a
  # elegibilidade e decidida por quem RECEBE — ele e que sabe onde esta.
  def anunciar!
    return unless (AnilLanRework.connected? rescue false)
    pid = (AnilLanRework.coop_party_partner_id rescue nil)
    return unless pid
    c = minha_cadeia
    AnilLanRework.connection.send_packet("coop_chain",
      "to_id"     => pid.to_s,
      "sender_id" => AnilLanRework.self_internal_id,
      "count"     => c[0].to_i,
      "species"   => c[1].to_s,
      "map_id"    => ($game_map ? $game_map.map_id.to_i : 0)
    )
  rescue => e
    AnilLanRework.log("[CADEIA] falha ao anunciar: #{e.class}: #{e.message}") rescue nil
  end

  def receber(packet)
    pid = (AnilLanRework.coop_party_partner_id rescue nil)
    return unless pid && packet["sender_id"].to_s == pid.to_s
    @cadeia_parceiro = [packet["count"].to_i, packet["species"].to_s, packet["map_id"].to_i]
    AnilLanRework.log("[CADEIA] parceiro: #{packet['count']}x #{packet['species']} no mapa #{packet['map_id']}") rescue nil
  rescue
  end

  def limpar!
    @cadeia_parceiro = nil
  end

  # ⚠️ AS DUAS FORMAS DO AMULETO.
  #
  # O MOD 113 converte o SHINYCHARM comum na versao de objecto-chave
  # (KEYSHINYCHARM). Aqui — e nos plugins originais — so se testava a forma
  # comum, portanto quem tinha o amuleto guardado nos Objetos Clave, que e onde
  # ele acaba por ficar, NAO recebia o bonus da cadeia. Os tres sitios do jogo
  # base (0263, 0252, PokeRadar) ja testavam as duas.
  # ⚠️ SILENCIO PARA QUEM CONTA EM LOTE.
  #
  # A cadeia sobe uma vez por Pokemon derrotado, e cada subida anuncia-se. Numa
  # HORDA isso dava tres caixas seguidas — "Cadeia de 2", "de 3", "de 4" — a
  # dizer a mesma coisa tres vezes, com o jogador a carregar em A no meio.
  #
  # O incremento continua a acontecer dentro do silencio: o que se cala e o
  # anuncio, e nao a contagem. Quem silencia fica responsavel por dizer o total
  # uma vez no fim.
  def calado?
    @calado == true
  end

  def calado
    antes = @calado
    @calado = true
    yield
  ensure
    @calado = antes
  end

  # A frase da cadeia, num sitio so — para o fim de batalha normal e o lote da
  # horda dizerem exactamente a mesma coisa.
  def anunciar_cadeia(especie, meus)
    return if meus.to_i <= 1
    return unless ($PokemonSystem.mensaje_shinys rescue 0) == 0
    nome = (GameData::Species.get(especie).name rescue especie.to_s)
    total = cadeia_somada(especie)
    if somando?(especie)
      p_nome = (parceiro&.name.to_s rescue "")
      p_nome = _INTL("teu parceiro") if p_nome.empty?
      pbMessage(_INTL("Cadeia de {1} {2} seguidos! ({3} teus + {4} de {5})",
                      total, nome, meus, total - meus, p_nome))
    else
      pbMessage(_INTL("Cadeia de {1} {2} seguidos!", meus, nome))
    end
  rescue
    nil
  end

  def tem_amuleto?
    ($bag.has?(:SHINYCHARM) rescue false) || ($bag.has?(:KEYSHINYCHARM) rescue false)
  end

  # ⚠️ ALGUEM MANDOU ESTE SER SHINY. NAO SE SORTEIA NADA.
  #
  # Sao os interruptores do /event shiny e do shinyzador. Le-se ANTES de o
  # plugin correr, porque ele consome-os (poe-nos a false depois de usar).
  def forcado?
    sw_super = (defined?(Settings::SUPER_SHINY_WILD_POKEMON_SWITCH) ?
                  Settings::SUPER_SHINY_WILD_POKEMON_SWITCH : 38)
    return true if ($game_switches[sw_super] rescue false)
    return true if (defined?(SUPERSHINYZADOR_SWITCH) && $game_switches[SUPERSHINYZADOR_SWITCH] rescue false)
    return true if ($game_switches[Settings::SHINY_WILD_POKEMON_SWITCH] rescue false)
    return true if (defined?(SHINYZADOR_SWTICH) && $game_switches[SHINYZADOR_SWTICH] rescue false)
    false
  rescue
    false
  end

  # ⚠️ O EFECTIVO E O MELHOR DOS DOIS SISTEMAS, NUNCA A SOMA DELES.
  #
  # Correm dois sorteios de shiny sobre o MESMO Pokemon: o do Essentials (pelo
  # personalID, no 0278) e o da cadeia. Enquanto o plugin dos encontros
  # visiveis deitava fora o primeiro, isso nao se notava. Assim que ele passou a
  # ser respeitado, os dois passaram a somar-se por OU — e a taxa saiu ao dobro
  # sem cadeia nenhuma, e a cinco vezes com amuleto:
  #
  #     sem amuleto, sem cadeia   dava 1 em 2511   (devia ser 1 em 5000)
  #     com amuleto, sem cadeia   dava 1 em 1005   (devia ser 1 em 2500)
  #     com amuleto, cadeia 41    dava 1 em  386   (devia ser 1 em  500)
  #
  # A regra passa a ser uma so: vale o MELHOR dos dois lados, e o estado final
  # sai de UM sorteio com esse valor. Nada se acumula, e nao se perde nada:
  #
  #   - o evento shiny sobe a taxa do Essentials, e o melhor passa a ser essa;
  #   - o amuleto (nas duas formas) e a cadeia contam pelo lado da cadeia;
  #   - o bonus de grupo desce o numero final, que e onde ele sempre quis agir.
  def alvo_efectivo(especie)
    amuleto = tem_amuleto?
    base  = (Object.const_defined?(:SHINYPROBABILITY) ? Object.const_get(:SHINYPROBABILITY) : 5000).to_i
    passo = (Object.const_defined?(:CHAINLENGTH) ? Object.const_get(:CHAINLENGTH) : 10).to_i
    passo = 10 if passo <= 0
    total = cadeia_somada(especie)

    d_cadeia = if total >= passo * 4 then base / 5
               elsif total >= passo * 3 then base * 2 / 5
               elsif total >= passo * 2 then base * 3 / 5
               elsif total >= passo     then base * 4 / 5
               else base
               end
    d_cadeia /= 2 if amuleto

    # ⚠️ O AMULETO NAO ENTRA DOS DOIS LADOS.
    #
    # Ele ja esta no d_cadeia (o /2 acima). Do lado do Essentials ele vale como
    # duas tentativas extra, e contar isso outra vez fazia o amuleto pagar a
    # dobrar: com amuleto e sem cadeia dava 1 em 1680 em vez de 1 em 2500.
    #
    # Entao aqui le-se a taxa NUA do Essentials. E ela que traz o evento shiny,
    # que e a unica coisa deste lado que o d_cadeia nao sabe.
    pe = prob_essentials(false)
    d_ess = (pe > 0) ? (1.0 / pe) : d_cadeia.to_f

    d = [d_cadeia.to_f, d_ess].min
    d -= BONUS_COOP if somando?(especie)
    d = 1.0 if d < 1.0
    d.round
  rescue => e
    AnilLanRework.log("[CADEIA] alvo_efectivo falhou: #{e.class}: #{e.message}") rescue nil
    5000
  end

  # Escalao actual da cadeia, para quem quiser mostrar ao jogador.
  # Devolve 0, 10, 20, 30 ou 40 (o valor de cadeia a partir do qual o bonus
  # actual vale), usando os mesmos degraus do divisor_para.
  def escalao(especie)
    passo = (Object.const_defined?(:CHAINLENGTH) ? Object.const_get(:CHAINLENGTH) : 10).to_i
    passo = 10 if passo <= 0
    total = cadeia_somada(especie)
    return passo * 4 if total >= passo * 4
    return passo * 3 if total >= passo * 3
    return passo * 2 if total >= passo * 2
    return passo     if total >= passo
    0
  end

  # O divisor que o PLUGIN vai usar por dentro do spawnPokeEvent.
  #
  # Ele repete os mesmos degraus, mas com tres limitacoes: usa so a MINHA
  # cadeia (nao a somada do grupo), so reconhece o :SHINYCHARM comum (nao o
  # :KEYSHINYCHARM, que e onde o amuleto acaba depois de "activado"), e nao tem
  # bonus de grupo nenhum.
  def divisor_do_plugin(especie)
    base  = (Object.const_defined?(:SHINYPROBABILITY) ? Object.const_get(:SHINYPROBABILITY) : 5000).to_i
    passo = (Object.const_defined?(:CHAINLENGTH) ? Object.const_get(:CHAINLENGTH) : 10).to_i
    passo = 10 if passo <= 0
    c = minha_cadeia
    total = (c[1].to_s == especie.to_s) ? c[0].to_i : 0

    d = if total >= passo * 4 then base / 5
        elsif total >= passo * 3 then base * 2 / 5
        elsif total >= passo * 2 then base * 3 / 5
        elsif total >= passo     then base * 4 / 5
        else base
        end
    d /= 2 if ($bag.has?(:SHINYCHARM) rescue false)
    [d, 1].max
  rescue
    5000
  end

  # ⚠️ COMPENSACAO, E NAO UM SEGUNDO SORTEIO.
  #
  # Nos encontros VISIVEIS quem sorteia a cadeia e o plugin, por dentro do
  # spawnPokeEvent. O nosso handler de :on_wild_pokemon_created esta desligado
  # nesse modo de proposito — se corresse, havia DOIS sorteios de cadeia e a
  # taxa saia ao dobro.
  #
  # Mas o sorteio do plugin ignora o amuleto em objecto-chave, o bonus de grupo
  # e a cadeia somada. Entao, depois de ele falhar, faz-se UM sorteio extra com
  # exactamente a probabilidade que falta para chegar ao valor correcto:
  #
  #   alvo = 1 - (1 - plugin) * (1 - extra)
  #   =>  extra = (alvo - plugin) / (1 - plugin)
  #
  # Se o plugin ja acertou, nao ha nada a compensar. Se o divisor dele ja e
  # igual ou melhor, tambem nao.
  def divisor_de_compensacao(especie)
    d_plugin = divisor_do_plugin(especie)
    d_alvo   = divisor_para(especie)
    return nil if d_alvo >= d_plugin

    p_plugin = 1.0 / d_plugin
    p_alvo   = 1.0 / d_alvo
    p_extra  = (p_alvo - p_plugin) / (1.0 - p_plugin)
    return nil if p_extra <= 0
    return 1 if p_extra >= 1.0
    [(1.0 / p_extra).round, 1].max
  rescue
    nil
  end

  # Probabilidade do sorteio do ESSENTIALS (o outro sorteio que corre em cada
  # encontro). Le a taxa em tempo real, portanto acompanha o /event shiny.
  # O amuleto la vale como +2 tentativas, nao como divisor a metade.
  def prob_essentials(amuleto)
    chance = (Settings::SHINY_POKEMON_CHANCE rescue 13).to_i
    chance = 13 if chance <= 0
    tentativas = amuleto ? 3 : 1
    1.0 - (1.0 - chance / 65536.0) ** tentativas
  rescue
    13 / 65536.0
  end

  # O divisor do sorteio da CADEIA, ja com tudo aplicado: degrau, amuleto e
  # bonus de grupo.
  #
  # ⚠️ O BONUS DE GRUPO E SOBRE O NUMERO FINAL, NAO SOBRE ESTE DIVISOR.
  #
  # Antes fazia-se `divisor -= 100` aqui, e o efeito visivel era pequeno: aos 40
  # com amuleto tirava 1/500 para 1/450, ou seja 1 em 386 para 1 em 355. Agora o
  # alvo e o EFECTIVO — o numero que o jogador ve depois de juntar os dois
  # sorteios — descer 100: 386 passa a 286.
  #
  # Como o efectivo sai de dois sorteios independentes, nao da para subtrair
  # directamente. Resolve-se ao contrario: sabendo a probabilidade do Essentials
  # e o alvo do total, descobre-se que probabilidade a cadeia tem de ter.
  #
  #   total = 1 - (1 - essentials) * (1 - cadeia)
  #   =>  cadeia = 1 - (1 - total) / (1 - essentials)
  def divisor_para(especie, amuleto = nil)
    amuleto = tem_amuleto? if amuleto.nil?
    base  = (Object.const_defined?(:SHINYPROBABILITY) ? Object.const_get(:SHINYPROBABILITY) : 5000).to_i
    passo = (Object.const_defined?(:CHAINLENGTH) ? Object.const_get(:CHAINLENGTH) : 10).to_i
    passo = 10 if passo <= 0
    total = cadeia_somada(especie)

    divisor = if total >= passo * 4 then base / 5
              elsif total >= passo * 3 then base * 2 / 5
              elsif total >= passo * 2 then base * 3 / 5
              elsif total >= passo     then base * 4 / 5
              else base
              end
    divisor /= 2 if amuleto
    divisor = 1 if divisor < 1

    return divisor unless somando?(especie)

    # --- bonus de grupo, sobre o efectivo ---
    pe = prob_essentials(amuleto)
    pc = 1.0 / divisor
    pt = 1.0 - (1.0 - pe) * (1.0 - pc)
    return divisor if pt <= 0

    alvo_n = (1.0 / pt) - BONUS_COOP
    return 1 if alvo_n <= 1.0                 # ja tao bom que passa a garantido
    pt_alvo = 1.0 / alvo_n
    pc_novo = 1.0 - (1.0 - pt_alvo) / (1.0 - pe)
    return 1 if pc_novo >= 1.0
    return divisor if pc_novo <= 0            # o Essentials sozinho ja passa do alvo

    novo = (1.0 / pc_novo).round
    novo = 1 if novo < 1
    # Nunca pior do que sem grupo.
    [novo, divisor].min
  rescue => e
    AnilLanRework.log("[CADEIA] divisor_para falhou: #{e.class}: #{e.message}") rescue nil
    5000
  end
end

#-------------------------------------------------------------------------------
# Substitui o handler de shiny por cadeia do plugin.
#-------------------------------------------------------------------------------
module AnilLanRework
  class << self
    if !method_defined?(:anil_cadeia_orig_apply_post_plugin_patches)
      alias_method :anil_cadeia_orig_apply_post_plugin_patches, :apply_post_plugin_patches rescue nil
    end

    def apply_post_plugin_patches
      anil_cadeia_orig_apply_post_plugin_patches if respond_to?(:anil_cadeia_orig_apply_post_plugin_patches)
      AnilCadeiaCoop.instalar_handler!
      AnilCadeiaCoop.instalar_incremento!
    end
  end
end

module AnilCadeiaCoop
  def self.instalar_handler!
    return unless defined?(EventHandlers)
    # Tem de sair primeiro: o add ignora chave repetida.
    EventHandlers.remove(:on_wild_pokemon_created, CHAVE_HANDLER) rescue nil
    EventHandlers.add(:on_wild_pokemon_created, CHAVE_HANDLER, proc { |pkmn|
      begin
        next if ($PokemonSystem.salvajes_visibles_en_ow rescue 1) != 1
        next unless pkmn
        $PokemonGlobal.catchcombo = [0, 0] if ($PokemonGlobal.catchcombo rescue nil).nil?

        # ⚠️ AUTORIDADE, E NAO MAIS UM SORTEIO.
        #
        # O Pokemon chega aqui com o shiny do Essentials ja decidido. Sortear de
        # novo e juntar por OU dobrava a taxa — o mesmo defeito que havia nos
        # encontros visiveis. O alvo efectivo ja tem o Essentials la dentro,
        # portanto aqui decide-se o estado FINAL, e nao um extra.
        #
        # Quem mandou o Pokemon ser shiny (evento, shinyzador) fica de fora.
        if AnilCadeiaCoop.forcado?
          (AnilLogShiny.saltado!("classico", pkmn.species.to_s,
            "forcado por interruptor (shinyzador/evento)") rescue nil)
          next
        end

        divisor = AnilCadeiaCoop.alvo_efectivo(pkmn.species)
        divisor = 1 if divisor < 1

        if rand(divisor) == 0
          pkmn.shiny = true
          # Mesma proporcao do plugin (1/3 dos shinies viram super).
          pkmn.super_shiny = (rand(3) == 0)
        else
          pkmn.shiny = false
          pkmn.super_shiny = false
        end
        # ⚠️ O modo classico nao passa pelo spawnPokeEvent, portanto nao ha
        # contador de spawns a fechar — conta-se o sorteio como spawn tambem.
        (AnilLogShiny.spawn!("classico") rescue nil)
        (AnilLogShiny.sorteio!("classico", pkmn.species.to_s, divisor,
          pkmn.shiny?) rescue nil)
      rescue => e
        AnilLanRework.log("[CADEIA] handler falhou: #{e.class}: #{e.message}") rescue nil
      end
    })
    AnilLanRework.log("[CADEIA] handler de shiny por cadeia substituido (soma coop activa)") rescue nil
  end
end

#-------------------------------------------------------------------------------
# Substitui tambem o handler que INCREMENTA a cadeia.
#
# Nao e so para anunciar ao parceiro: a mensagem do plugin diz "Cadena de 20"
# com a contagem propria, e o que se quer ver e o total somado (40). Como a
# mensagem esta no meio daquele handler, a unica forma de mudar o numero sem
# remendar strings por cima e ficar com o handler.
#-------------------------------------------------------------------------------
module AnilCadeiaCoop
  CHAVE_INCREMENTO = :shiny_chain_aumenta

  # ⚠️ A CADEIA DO PARCEIRO SO CONTA NO MAPA ONDE ELE CACOU. E DE PROPOSITO.
  #
  # O `cadeia_do_parceiro_para` exige que o mapa do pacote seja igual ao mapa
  # onde estou agora:
  #
  #     return 0 unless dados[2].to_i == $game_map.map_id.to_i
  #
  # E como o `anunciar!` so corre no fim de uma batalha ganha, mudar de mapa faz
  # a contribuicao do parceiro cair para zero ate ele lutar outra vez ali.
  #
  # Isso PARECE um esquecimento e chegou a ser corrigido (30/08). Foi revertido
  # no mesmo dia, por uma razao melhor: sem a amarra ao mapa, bastava encadear
  # quarenta Caterpie — que sao faceis e estao logo a saida — e passear com essa
  # taxa pelo jogo inteiro. A cadeia perdia o preco.
  #
  # A regra fica: o bonus vive no sitio onde foi ganho. Mudar de mapa exige
  # reactiva-lo com uma captura nova.
  #
  # ⚠️ Nao voltar a "corrigir" isto sem falar. Nao e um portao esquecido:
  # e o unico sitio onde a cadeia partilhada tem custo.

  def self.instalar_incremento!
    return unless defined?(EventHandlers)
    EventHandlers.remove(:on_wild_battle_end, CHAVE_INCREMENTO) rescue nil
    EventHandlers.add(:on_wild_battle_end, CHAVE_INCREMENTO, proc { |species, _level, decision|
      begin
        # 1 = venceu, 4 = capturou. Fugir ou perder nao conta.
        next unless [1, 4].include?(decision)
        $PokemonGlobal.catchcombo = [0, 0] if ($PokemonGlobal.catchcombo rescue nil).nil?
        combo = $PokemonGlobal.catchcombo
        combo[0], combo[1] = 0, species if combo[1] != species
        combo[0] += 1
        $PokemonGlobal.catchcombo = combo

        AnilCadeiaCoop.anunciar!

        next if AnilCadeiaCoop.calado?
        AnilCadeiaCoop.anunciar_cadeia(species, combo[0])

        # ⚠️ AS MENSAGENS DE MARCO VOLTARAM.
        #
        # Este handler substitui o :shiny_chain_aumenta do plugin VOE (e por
        # isso que a mensagem consegue dizer o total somado do grupo). Mas ao
        # substitui-lo levou tambem as quatro mensagens de marco que o plugin
        # dava aos 10/20/30/40 — que eram a unica forma de o jogador saber que o
        # bonus tinha subido. Repostas aqui, agora sobre a cadeia SOMADA.
        #
        # O plugin usava `milestone.key?(contagem)`, ou seja exigia o numero
        # EXACTO. Com a cadeia somada do coop a contagem pode saltar de 39 para
        # 41 e o marco nunca dispararia. Por isso guarda-se o ultimo escalao
        # anunciado e avisa-se quando ele SOBE.
        marco = AnilCadeiaCoop.escalao(species)
        if marco > 0 && marco != @ultimo_marco_anunciado
          @ultimo_marco_anunciado = marco
          texto = case marco
                  when 40 then _INTL("A chance de encontrar um shiny aumentou bastante! Nao sobe mais a partir daqui.")
                  when 30 then _INTL("A chance de encontrar um shiny aumentou muito!")
                  when 20 then _INTL("A chance de encontrar um shiny aumentou um pouco!")
                  else         _INTL("A chance de encontrar um shiny aumentou ligeiramente!")
                  end
          pbMessage(texto)
        elsif marco == 0
          @ultimo_marco_anunciado = 0
        end
      rescue => e
        AnilLanRework.log("[CADEIA] incremento falhou: #{e.class}: #{e.message}") rescue nil
      end
    })
  end
end

#-------------------------------------------------------------------------------
# LINHA DE ESTADO PARA O MENU F7
#
# O jogador nao tinha como saber se o bonus estava activo: a mensagem de marco
# passa uma vez e desaparece. Isto devolve uma linha curta, pronta a colar no
# cabecalho do menu, com o amuleto e o escalao da cadeia.
#
# Texto e nao icone de proposito: o cabecalho do F7 e um pbMessage, que aceita
# codigos de cor (\c[n]) mas nao desenha bitmaps. Um icone exigiria reescrever a
# cena inteira — e a informacao que falta e o NUMERO, nao a figura.
#
#   \c[3] = verde   \c[2] = azul   \c[0] = normal
#-------------------------------------------------------------------------------
module AnilCadeiaCoop
  module_function

  # Par [item_do_amuleto_ou_nil, tamanho_da_cadeia] para a HUD desenhar.
  #
  # Devolve o ID do item que o jogador TEM de facto, para o icone ser o certo:
  # o comum e o de objecto-chave sao PNG diferentes, e depois de "activar" o
  # amuleto so existe a versao chave.
  #
  # A cadeia e a SOMADA (a minha mais a do parceiro, quando elegivel), que e o
  # numero que manda no divisor — mostrar so a minha seria enganador em coop.
  def estado_hud
    item = if ($bag.has?(:KEYSHINYCHARM) rescue false)
             :KEYSHINYCHARM
           elsif ($bag.has?(:SHINYCHARM) rescue false)
             :SHINYCHARM
           end

    c = minha_cadeia
    especie = c[1]
    cadeia = 0
    nome = nil
    if especie && especie.to_s != "0" && !especie.to_s.empty?
      cadeia = cadeia_somada(especie).to_i
      nome = (GameData::Species.get(especie).name.to_s rescue especie.to_s) if cadeia > 0
    end

    [item, cadeia, nome]
  rescue
    [nil, 0, nil]
  end
end

module AnilLanRework
  module CadeiaRouter
    def self.on_packet(packet)
      case packet["type"]
      when "coop_chain" then AnilCadeiaCoop.receber(packet)
      end
    end
  end
end

AnilLanRework.log("135_Coop_Cadeia_Compartilhada carregado") rescue nil
