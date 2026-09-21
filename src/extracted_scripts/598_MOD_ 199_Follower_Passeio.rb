# encoding: utf-8
#===============================================================================
# O POKEMON QUE SEGUE PASSA A VIVER
#
# ⚠️ ELE SO EXISTIA ENQUANTO EU ANDAVA.
#
# O `Following Pokemon EX` move os seguidores num unico sitio:
#
#     Scene_Map#update -> if $game_player.moving?  ->  move_followers
#
# Ou seja, ele so da um passo quando EU dou um passo, e sempre para a casa que
# eu acabei de deixar. Parado, ele fica um boneco colado atras de mim — nao
# olha, nao se afasta, nao faz nada. Num jogo onde ele anda o tempo todo ao
# nosso lado, isso le-se como um sprite e nao como um bicho.
#
# ⚠️ E O QUE NAO SE PODE FAZER: MOVE-LO AO MESMO TEMPO QUE O PLUGIN.
#
# Ja apanhei este defeito na arena e custou uma ronda inteira: dois sitios a
# mover o mesmo boneco dao-lhe um passo para cada lado no mesmo frame, e o que
# se ve e um bicho a "tremer". Portanto a regra aqui e simples e absoluta —
#
#     este ficheiro so mexe no seguidor quando o plugin NAO vai mexer.
#
# O plugin mexe quando `$game_player.moving?`. Este passeia quando ele esta
# quieto, e larga-lhe a mao assim que eu dou um passo.
#===============================================================================
module AnilFollowerPasseio
  # ── as medidas ──────────────────────────────────────────────────────────────
  #
  # Tres casas foi o que se pediu, e e um bom numero por uma razao que se ve em
  # jogo: a quatro ele ja sai do ecra em corredores estreitos, e a duas o
  # passeio nao chega a ler-se como passeio.
  RAIO          = 3

  # Quanto tempo entre dois passos de passeio. Um intervalo fixo da um metronomo
  # — le-se logo como um script. Sorteado entre os dois, parece indecisao.
  ESPERA_MIN    = 1.1
  ESPERA_MAX    = 3.4

  # De vez em quando ele so vira a cara, sem sair do sitio. E o gesto que mais
  # faz um bicho parecer vivo, e o mais barato de todos.
  SO_OLHA       = 40      # por cento das vezes

  # ⚠️ "ELE SO CORRE PARA ME SEGUIR" — E ESSA E A LINHA INTEIRA DO PEDIDO.
  #
  # A passear anda a velocidade normal. Quando fica para tras do raio, acelera
  # ate encostar. Se corresse sempre, o passeio parecia fuga; se nunca
  # corresse, ficava para tras e o jogo teria de o teletransportar.
  VEL_PASSEIO   = 3
  VEL_CORRIDA   = 5

  # Um passo a mais de folga antes de ele desistir do passeio e voltar. Sem
  # isto, ficava a entrar e sair da corrida na fronteira exacta do raio.
  FOLGA_VOLTA   = 0.8

  @proximo = 0.0

  module_function

  # ⚠️ NADA DISTO CORRE ONDE JA HA OUTRO DONO DO BONECO.
  #
  # A arena troca o jogador por um Pokemon e tem o seu proprio ajudante; a
  # masmorra tem os bichos do servidor. Um passeio por cima de qualquer um
  # desses e o defeito do "tremer" outra vez, agora entre ficheiros meus.
  def pode_passear?
    return false unless $scene.is_a?(Scene_Map)
    return false unless $game_map && $game_player
    return false if (AnilArena.activa? rescue false)
    return false if ($game_player.moving? rescue true)
    return false if ($game_temp.message_window_showing rescue false)
    return false if ($game_system && $game_system.map_interpreter &&
                     $game_system.map_interpreter.running? rescue false)
    return false if (FollowingPkmn.active? rescue false) == false
    true
  rescue
    false
  end

  # O evento do Pokemon que segue — e so ele. Os outros seguidores (o parceiro
  # de um evento, por exemplo) nao passeiam: eles estao ali por uma razao do
  # guiao e sair do sitio partia-a.
  def bicho
    conj = ($game_temp.followers rescue nil)
    return nil unless conj
    lista = (conj.instance_variable_get(:@events) rescue nil)
    return nil unless lista.is_a?(Array)
    lista.find do |e|
      e && defined?(Game_FollowingPkmn) && e.is_a?(Game_FollowingPkmn)
    end
  rescue
    nil
  end

  def longe(ev)
    dx = (ev.x - $game_player.x).abs
    dy = (ev.y - $game_player.y).abs
    [dx, dy].max
  rescue
    0
  end

  # ⚠️ O PLUGIN LIGA A ANIMACAO DE PASSO E NUNCA A DESLIGA.
  #
  # No `Following Event.rb` do Following Pokemon EX, o metodo que faz o
  # seguidor dar um passo acaba assim:
  #
  #     @step_anime = true
  #
  # O `@step_anime` quer dizer "anima mesmo parado" (ver `Game_Character`, linha
  # 70: "Whether character should animate while still"). Ligado no fim de cada
  # passo e nunca desligado, o bicho fica a andar no sitio para sempre — as
  # pernas a mexer com ele quieto.
  #
  # A animacao de ANDAR nao depende disto: e o `@walk_anime`, que ja esta ligado
  # e so corre enquanto ele se desloca (`@anime_count += @delta_t if @walk_anime
  # || @step_anime`). Portanto desligar isto parado nao tira nada — so devolve o
  # bicho ao repouso.
  #
  # Faz-se aqui e nao no plugin porque o plugin e outra arvore, com outro
  # compilador; um MOD chega e viaja no Scripts.rxdata.
  def parar_de_andar_no_sitio!(ev)
    return unless ev
    if (ev.moving? rescue false)
      (ev.instance_variable_set(:@step_anime, true) rescue nil)
    else
      (ev.instance_variable_set(:@step_anime, false) rescue nil)
      # Sem isto ele congela no quadro em que ia — meio passo dado. O zero e a
      # pose de pe de qualquer charset de 4 colunas.
      (ev.instance_variable_set(:@pattern, 0) rescue nil)
    end
  rescue
    nil
  end

  def correr!
    return unless pode_passear?
    ev = bicho
    return unless ev
    parar_de_andar_no_sitio!(ev)
    return if (ev.moving? rescue true)
    return if (ev.jumping? rescue false)

    d = longe(ev)

    # ── longe de mais: volta, e volta a correr ────────────────────────────────
    if d > RAIO + FOLGA_VOLTA
      (ev.move_speed = VEL_CORRIDA) rescue nil
      (ev.move_toward_player rescue nil)
      return
    end

    agora = (Graphics.frame_count rescue 0) / 60.0
    return if agora < @proximo.to_f
    @proximo = agora + ESPERA_MIN + (rand * (ESPERA_MAX - ESPERA_MIN))

    (ev.move_speed = VEL_PASSEIO) rescue nil

    # ── parar e olhar ─────────────────────────────────────────────────────────
    if rand(100) < SO_OLHA
      # Olhar para o jogador de vez em quando e o que faz parecer que ele nos
      # acompanha; olhar sempre para nos faria dele uma camera de seguranca.
      if rand(100) < 55
        (ev.turn_toward_player rescue nil)
      else
        (ev.turn_random rescue nil)
      end
      return
    end

    # ── ou dar um passo, mas so para dentro do raio ───────────────────────────
    #
    # ⚠️ SORTEAR A DIRECCAO E TENTAR NAO CHEGA: ELE FUGIA.
    #
    # Um passo ao acaso tem 50% de ser para longe, e ao fim de alguns passos ele
    # esta a cinco casas e a correr de volta — o que se ve e um ioio, nao um
    # passeio. Escolhe-se de entre as direccoes que o mantem perto E que o mapa
    # deixa passar; sem nenhuma, fica quieto, que tambem e uma coisa que os
    # bichos fazem.
    boas = [2, 4, 6, 8].select do |dir|
      nx = ev.x + (dir == 6 ? 1 : (dir == 4 ? -1 : 0))
      ny = ev.y + (dir == 2 ? 1 : (dir == 8 ? -1 : 0))
      next false if [(nx - $game_player.x).abs, (ny - $game_player.y).abs].max > RAIO
      (ev.passable?(ev.x, ev.y, dir) rescue false)
    end
    return if boas.empty?
    case boas.sample
    when 2 then (ev.move_down  rescue nil)
    when 4 then (ev.move_left  rescue nil)
    when 6 then (ev.move_right rescue nil)
    when 8 then (ev.move_up    rescue nil)
    end
  rescue
    nil
  end
end

#-------------------------------------------------------------------------------
# ⚠️ O GANCHO VEM DEPOIS DO PLUGIN, E TEM DE VIR.
#
# O `Following Pokemon EX` tambem faz alias ao `Scene_Map#update`. Se este
# corresse primeiro, mexiamos no boneco antes de o plugin decidir o que fazer
# com ele — e o resultado seria o mesmo passo dado duas vezes.
#
# O nome do alias e proprio e nao se repete em lado nenhum: dois MODs com o
# mesmo nome de alias ja mataram comandos inteiros neste projecto, em silencio.
#-------------------------------------------------------------------------------
class Scene_Map
  unless method_defined?(:anil_passeio_orig_update) ||
         private_method_defined?(:anil_passeio_orig_update)
    alias_method :anil_passeio_orig_update, :update
    def update(*args)
      anil_passeio_orig_update(*args)
      # A animacao de passo repoe-se a cada frame, ande o jogador ou nao: e
      # quando ELE anda que o plugin volta a liga-la.
      (AnilFollowerPasseio.parar_de_andar_no_sitio!(
         AnilFollowerPasseio.bicho) rescue nil)
      (AnilFollowerPasseio.correr! rescue nil)
    end
  end
end
