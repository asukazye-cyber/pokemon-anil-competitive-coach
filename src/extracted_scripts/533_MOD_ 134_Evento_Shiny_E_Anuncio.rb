# encoding: UTF-8
#===============================================================================
# MOD: 134_Evento_Shiny_E_Anuncio
#-------------------------------------------------------------------------------
# Duas coisas que andam juntas:
#
#   1) O EVENTO de shiny em dobro (interruptor EVENTO_ATIVO).
#   2) O ANUNCIO no chat quando alguem apanha um shiny.
#
# ⚠️ PORQUE A TAXA VIVE AQUI E NAO NO Settings.
#
# Assim o evento liga e desliga num ficheiro so, com uma linha, e o resto do
# jogo fica intocado. Basta pôr EVENTO_ATIVO a false e recompilar para voltar
# ao normal — nao ha que lembrar de qual era o valor antigo.
#===============================================================================

module AnilEventoShiny
  # false = taxa normal do jogo (1 em 5041). true = evento.
  EVENTO_ATIVO = true

  # Numerador sobre 65536. O teste e "d < TAXA", com d uniforme em 0..65535.
  #
  #   13 -> 1 em 5041   (normal)
  #   26 -> 1 em 2521   (evento, o dobro)
  #
  # O SUPER shiny nao tem valor proprio: e uma fatia de 1/3 dos shinies, no
  # 0278_Pokemon.rb (`(d < CHANCE) && (((a >> 16) % 3) == 0)`). Ao dobrar a base
  # ele dobra junto — 1 em 15123 passa a 1 em 7563 — e a proporcao entre os dois
  # mantem-se. E por isso que nao ha nada a acertar do lado do super.
  TAXA_EVENTO = 26
end

if AnilEventoShiny::EVENTO_ATIVO
  module Settings
    if const_defined?(:SHINY_POKEMON_CHANCE)
      antiga = SHINY_POKEMON_CHANCE
      send(:remove_const, :SHINY_POKEMON_CHANCE)
      SHINY_POKEMON_CHANCE = AnilEventoShiny::TAXA_EVENTO
      (AnilLanRework.log("[EVENTO_SHINY] taxa #{antiga} -> #{SHINY_POKEMON_CHANCE} (1 em #{65536 / SHINY_POKEMON_CHANCE})") rescue nil)
    end
  end
end

#===============================================================================
# ANUNCIO DE CAPTURA
#===============================================================================
module AnilAnuncioShiny
  # Um anuncio por captura, mas nunca dois em menos de 30s do mesmo jogador.
  # Nao e para poupar rede — e para o caso de alguem com um cliente adulterado
  # decidir encher o chat. O servidor tem o seu proprio travao; este evita o
  # trafego a partida.
  INTERVALO = 30.0

  module_function

  def anunciar(pkmn)
    # ⚠️ CADA RECUSA DEIXA RASTO.
    #
    # A primeira versao devolvia em silencio em cinco pontos diferentes. Quando
    # o anuncio nao aparecia nao havia como saber ONDE parou — se o gancho nao
    # correu, se o guarda barrou, ou se o pacote saiu e o servidor e que nao
    # reagiu. Agora cada porta fechada escreve uma linha.
    unless pkmn
      AnilLanRework.log("[EVENTO_SHINY] sem pokemon") rescue nil
      return
    end
    unless (pkmn.shiny? rescue false)
      return   # o caso normal: quase toda a captura cai aqui, nao vale log
    end
    unless (AnilLanRework.connected? rescue false)
      AnilLanRework.log("[EVENTO_SHINY] shiny apanhado mas sem ligacao — nao anuncio") rescue nil
      return
    end

    # ⚠️ `multiplayer_mode || online_session?`, e nao so o online_session?.
    #
    # Este era o guarda que provavelmente barrava tudo. O online_session? so
    # fica true se o IP da ligacao for IDENTICO ao dedicated_server_ip (que sai
    # de multiplayer_vps_ip.txt); qualquer diferenca de forma e ele fica false
    # com o jogo perfeitamente online. Todo o resto do codigo usa a dupla — ver
    # 000_Multiplayer_Online.rb:2555 e 099:305 — e so aqui e que estava sozinho.
    ligado = (AnilLanRework.multiplayer_mode rescue false) ||
             (AnilLanRework.online_session? rescue false)
    unless ligado
      AnilLanRework.log("[EVENTO_SHINY] fora de sessao online (mp=#{(AnilLanRework.multiplayer_mode rescue '?')} sess=#{(AnilLanRework.online_session? rescue '?')})") rescue nil
      return
    end

    agora = Time.now.to_f
    @ultimo ||= 0.0
    if agora - @ultimo < INTERVALO
      AnilLanRework.log("[EVENTO_SHINY] travado pelo intervalo de #{INTERVALO}s") rescue nil
      return
    end
    @ultimo = agora

    especie = (pkmn.speciesName.to_s rescue "")
    sup     = ((pkmn.super_shiny? rescue false) ? true : false)
    AnilLanRework.connection.send_packet("shiny_capturado", {
      "especie" => especie,
      "super"   => sup
    })
    AnilLanRework.log("[EVENTO_SHINY] enviado shiny_capturado especie=#{especie.inspect} super=#{sup}") rescue nil
  rescue => e
    (AnilLanRework.log("[EVENTO_SHINY] falha ao anunciar: #{e.class}: #{e.message}") rescue nil)
  end
end

# ⚠️ O GANCHO TEM DE SER REINSTALADO DEPOIS DOS PLUGINS.
#
# O "Battle bug fixes.rb" (plugin de correccoes do Maruno) traz uma COPIA
# INTEIRA do Battle::CatchAndStoreMixin#pbStorePokemon e volta a inclui-la no
# Battle. Nao e um alias: e um `def` que substitui o metodo de raiz. Como os
# plugins correm no PluginManager.runPlugins, no fim do Main, isso acontece
# DEPOIS deste script — o nosso metodo era apagado, o alias ficava orfao e o
# anuncio nunca chegava a partir. Do lado do jogador parecia que a captura
# simplesmente nao avisava ninguem, sem erro nenhum no log.
#
# Os outros tres plugins que mexem no mesmo metodo (Deluxe Battle Kit, Stream
# Overlay e Challenge Modes) usam alias e encadeiam bem. So este e que arrasa.
#
# A instalacao e idempotente: se o metodo actual ja for o nosso, nao volta a
# encadear. E cada instalacao usa um nome de alias novo, para que reinstalar
# por cima da copia do plugin nao perca o que ele acrescentou.
module AnilAnuncioShiny
  class << self
    def instalar_gancho!
      return false unless defined?(Battle::CatchAndStoreMixin)
      m = Battle::CatchAndStoreMixin
      return false unless m.method_defined?(:pbStorePokemon)
      actual = m.instance_method(:pbStorePokemon)
      return false if @gancho && @gancho == actual   # ja e o nosso, nada a fazer

      @seq = (@seq || 0) + 1
      antigo = :"anil_shiny_pbStorePokemon_#{@seq}"
      m.send(:alias_method, antigo, :pbStorePokemon)
      # ⚠️ DEPOIS de guardar, nunca antes.
      # O pbStorePokemon pode ser interrompido (caixas cheias, o jogador recusa)
      # e anunciar a entrada daria "fulano apanhou" para uma captura que nao
      # chegou a acontecer.
      #
      # (*args) e nao (pkmn) porque o Challenge Modes encadeia com *args; manter
      # a mesma forma evita partir a cadeia se a ordem dos plugins mudar.
      m.send(:define_method, :pbStorePokemon) do |*args|
        resultado = send(antigo, *args)
        AnilAnuncioShiny.anunciar(args[0]) rescue nil
        resultado
      end
      @gancho = m.instance_method(:pbStorePokemon)
      (AnilLanRework.log("[EVENTO_SHINY] gancho de captura instalado (##{@seq})") rescue nil)
      true
    end
  end
end

AnilAnuncioShiny.instalar_gancho! rescue nil

# Reinstalar assim que os plugins acabarem de correr. O 040 chama isto a partir
# do PluginManager.runPlugins; encadeamos como o 101 ja faz.
module AnilLanRework
  class << self
    unless method_defined?(:anil_shiny_orig_apply_post_plugin_patches)
      alias_method :anil_shiny_orig_apply_post_plugin_patches, :apply_post_plugin_patches rescue nil
    end

    def apply_post_plugin_patches
      anil_shiny_orig_apply_post_plugin_patches rescue nil
      AnilAnuncioShiny.instalar_gancho! rescue nil
    end
  end
end

AnilLanRework.log("134_Evento_Shiny_E_Anuncio carregado (evento=#{AnilEventoShiny::EVENTO_ATIVO})") rescue nil
