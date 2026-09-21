# encoding: UTF-8
#===============================================================================
# MOD: 136_Movimento_Remoto
#-------------------------------------------------------------------------------
# DONO UNICO de como os outros jogadores (e os followers deles) se movem na tua
# tela. Nada fora daqui deve calcular passo, velocidade ou animacao de peer.
#
# POR QUE UM MODULO
#
# A mesma matematica estava escrita em TRES sitios — RemotePeer#update_anim no
# 000_Multiplayer_Online, outra copia no 000e_FPS_Patch (que sobrepoe a primeira,
# por carregar depois) e uma terceira para o follower. Corrigir uma e esquecer as
# outras dava build que compila e nao muda nada em jogo, ou pior, corpo e
# follower a andar a velocidades diferentes. Agora as tres delegam para aqui.
#
# COMO FUNCIONA: BUFFER DE INTERPOLACAO
#
# O erro anterior foi mandar o boneco andar na velocidade EXACTA do dono em
# direccao a ultima posicao conhecida. Parece certo e nao e: os pacotes chegam a
# cada ~0,067s, entao o boneco alcança o alvo e FICA PARADO ate ao proximo — 5
# frames parados em cada 18, medido. E o engasgo que se via.
#
# A solucao padrao de rede (a mesma da Valve, "entity interpolation") e desenhar
# o peer um pouco NO PASSADO:
#
#   1. Guarda-se cada posicao com o RELOGIO DE QUEM A ENVIOU (t_env).
#   2. Desenha-se o estado de (relogio de reproducao - ATRASO).
#   3. Como esse instante fica SEMPRE entre dois pontos ja conhecidos, ha sempre
#      para onde interpolar — nunca falta informacao, logo nunca ha paragem.
#
# Custo: os outros aparecem ~150ms atrasados. Isso e invisivel em jogo de
# overworld e e o preco de nao ter engasgo. Nao se extrapola (adivinhar o futuro)
# de proposito: erra a direccao em cada mudanca de rumo e produz o "escorregar e
# corrigir", que incomoda mais do que o atraso.
#
# ⚠️ O CARIMBO TEM DE SER DO REMETENTE, nao da chegada. A primeira versao usou a
# hora de chegada e ficou PIOR que o codigo antigo: o jitter da rede entrava
# direto na posicao desenhada. Medido em simulacao, 80ms de jitter davam saltos
# de 149px onde se esperavam 50. Os relogios nao precisam estar certos entre si —
# so precisam andar, porque o que se usa sao as diferencas.
#===============================================================================

module AnilMovimentoRemoto
  # ~2 intervalos de pacote (0,067s cada). Menos do que isto e o buffer seca
  # quando a rede varia e volta o engasgo; muito mais e atraso visivel.
  ATRASO = 0.15

  # ⚠️ O ATRASO QUE SE SENTE NAO E O PING: SOU EU.
  #
  # Com 13 ms de ping, o que se ve de atraso vem quase todo daqui — 150 ms de
  # buffer mais meio intervalo de envio (33 ms). O buffer nao e um defeito: e
  # ele que evita o engasgo quando a rede varia, e num mapa cheio vale a pena.
  #
  # Mas num duelo a mira depende de onde o outro esta AGORA, e 180 ms sao quase
  # duas casas de erro. Com o envio ao dobro da cadencia (ver o MOD 000e), dois
  # intervalos passam a ser 66 ms — e e esse o buffer que se usa enquanto a
  # arena estiver a correr. Menos do que isto so com previsao de movimento, que
  # e outro problema e erra em cada mudanca de rumo.
  # ⚠️ ZERO SOZINHO NAO SERVE — E POR ISSO QUE O BUFFER EXISTE.
  #
  # Com atraso zero, o instante desenhado e o do ultimo pacote recebido: o
  # boneco alcanca essa posicao e FICA PARADO ate chegar o proximo. E o engasgo
  # que este modulo foi escrito para acabar (esta medido no cabecalho: 5 frames
  # parados em cada 18).
  #
  # O que substitui o buffer nao e "nada": e PREVISAO. Sabendo a velocidade dos
  # ultimos dois pacotes, continua-se o movimento por conta propria enquanto o
  # proximo nao chega. Com pacotes de 33 ms so e preciso prever 33 ms, e a
  # 5 casas/s isso da 0,16 casas de erro no pior caso — cinco pixeis.
  #
  # E porque e que isto nao se usa fora do duelo? Porque prever erra em cada
  # mudanca de rumo, e no overworld a pessoa muda de rumo o tempo todo, aos
  # bocados. Num duelo o movimento e continuo e o erro que interessa e a MIRA,
  # que so existe agora. Sao dois problemas diferentes e levam respostas
  # diferentes.
  ATRASO_DUELO = 0.0

  # ⚠️ NA CAVERNA O ZERO NAO SE SUSTENTA, E ERA ISTO O "TELETRANSPORTE".
  #
  # Zero de buffer significa desenhar o instante do ULTIMO pacote e, dai para a
  # frente, PREVER — no maximo `PREVISAO_MAX`, 0,12 s. Passado esse tempo sem
  # pacote, o boneco fica parado onde estava; quando o pacote seguinte chega,
  # salta para onde a pessoa ja esta. E isso que se ve como travar e
  # teletransportar.
  #
  # Num duelo isso nunca acontece: sao duas pessoas, 30 pacotes por segundo
  # cada uma, e um intervalo de 33 ms cabe folgadamente nos 120 ms de previsao.
  # A caverna tem o mesmo ritmo mas MUITO mais companhia no fio — as posicoes
  # dos inimigos, o ajudante, os golpes — e basta um engasgo de 130 ms para o
  # boneco congelar e saltar.
  #
  # ⚠️ 33 ms E EXACTAMENTE UM INTERVALO DE PACOTE, E ISSO E O QUE ELE COBRE.
  #
  # Dentro da arena o envio e a cada 0,033 s (ver o MOD 000e). Um colchao do
  # mesmo tamanho quer dizer: quando um pacote chega no tempo certo, ha sempre
  # dois pontos para interpolar e o desenho corre liso; quando um se atrasa mais
  # do que 33 ms, o colchao esvazia-se e volta a haver um engasgo.
  #
  # E uma escolha, e e a que foi pedida: dois frames de atraso na mira em vez de
  # quatro, ao preco de nao aguentar um pacote perdido. Vale a pena com boa
  # ligacao — que e o caso de quem joga no PC — e e melhor do que o zero que
  # estava aqui em qualquer caso, porque o zero nao aguenta nem o jitter normal.
  #
  # Se voltar a travar, a causa e jitter acima de 33 ms, e o passo seguinte nao
  # e subir esta constante a olho: e medi-la por jogador e deixar o colchao
  # crescer sozinho, com estes 33 ms como CHAO.
  ATRASO_CAVERNA = 0.033

  # Nunca se preve mais do que isto. Passado este tempo sem pacote, e melhor
  # ficar parado no ultimo sitio conhecido do que inventar meio mapa.
  PREVISAO_MAX = 0.12


  # Chega para ~1s de historico. O que passa disso ja nao serve para nada.
  MAX_PONTOS = 16

  # Acima disto nao e andar: entrada no mapa, teleporte, ou perda longa de
  # ligacao. Interpolar nesses casos faz o boneco atravessar paredes.
  TELEPORTE_TILES = 15

  # Fraccao da deriva corrigida por frame. Baixo de proposito: a correcao
  # em si e movimento, e se for agressiva vira tremor no boneco.
  CORRECAO_RELOGIO = 0.02

  # Cadencia de envio do cliente (PLAYER_SEND_TICK = 4 frames a 60fps).
  # Usado so para reconstruir a linha do tempo de clientes antigos.
  INTERVALO_ESPERADO = 4.0 / 60.0

  module_function

  def atraso
    return ATRASO_CAVERNA if (defined?(AnilRaidCaverna) && AnilRaidCaverna.dentro?)
    return ATRASO_DUELO if (AnilArena.activa? rescue false)
    ATRASO
  rescue
    ATRASO
  end

  # Chamado quando chega um player_state, DEPOIS de os alvos estarem escritos.
  # BLINDADO de proposito. Isto corre no fim do update_from_packet: um erro
  # aqui aborta o resto do processamento do pacote e o defeito aparece bem
  # longe da causa — foi assim que um acessor em falta fez os jogadores
  # pararem de andar sem uma unica mensagem de erro visivel.
  def registrar!(peer)
    return unless peer
    pontos = (peer.mov_pontos ||= [])

    # CARIMBO PELO RELOGIO DE QUEM ENVIA, nao pela hora de chegada.
    #
    # Esta foi a diferenca entre funcionar e piorar. Com a hora de chegada, o
    # jitter da rede entra direto na posicao desenhada: medido em simulacao, 80ms
    # de jitter davam saltos de 149px onde se esperavam 50. Com o relogio do
    # remetente a linha do tempo e regular, e o jitter fica onde deve ficar — na
    # hora em que o ponto chega, nao no conteudo dele.
    #
    # CLIENTE ANTIGO (sem t_env): reconstroi-se uma linha do tempo REGULAR.
    #
    # Cair na hora de chegada seria voltar ao defeito da v1 — o jitter entrava no
    # conteudo do ponto. Como os pacotes saem em cadencia fixa (PLAYER_SEND_TICK
    # = 4 frames), da para assumir o intervalo e so reengatar se a conta fugir
    # demais do real. O resto da deriva o relogio de reproducao absorve.
    #
    # Isto importa durante a transicao: quem ja atualizou vai ver quem ainda nao
    # atualizou, e sem isto essas pessoas apareceriam pior do que antes.
    chegada = Time.now.to_f
    agora = if peer.t_env
      peer.t_env / 1000.0
    elsif pontos.last
      previsto = pontos.last[0] + INTERVALO_ESPERADO
      (previsto - chegada).abs > 0.5 ? chegada : previsto
    else
      chegada
    end

    # Pacote fora de ordem: ignora-se. Aceitar faria o boneco recuar e voltar.
    return if pontos.last && agora <= pontos.last[0]

    pontos << [agora,
               peer.target_x.to_i, peer.target_y.to_i,
               peer.f_rx ? peer.f_rx.to_i : nil,
               peer.f_ry ? peer.f_ry.to_i : nil,
               peer.dir.to_i,
               peer.f_dir ? peer.f_dir.to_i : nil]
    pontos.shift while pontos.length > MAX_PONTOS
  rescue => e
    AnilLanRework.log("[MOV] registrar! falhou: #{e.class}: #{e.message}") rescue nil
  end

  def limpar!(peer)
    return unless peer
    peer.mov_pontos = []
    peer.mov_relogio = nil
  end

  # Estado a desenhar agora: [x, y, fx, fy, dir, f_dir] ou nil se ainda nao ha
  # historico suficiente.
  # Continua o movimento dos ultimos dois pontos. Nao inventa direccao nem
  # animacao: essas ficam as do ultimo pacote, porque adivinha-las e o que
  # produz o boneco a virar-se sozinho.
  def prever(pontos, instante)
    ultimo = pontos.last
    return ultimo if pontos.length < 2
    anterior = pontos[-2]
    duracao = ultimo[0] - anterior[0]
    return ultimo if duracao <= 0.001
    avanco = instante - ultimo[0]
    return ultimo if avanco <= 0
    avanco = PREVISAO_MAX if avanco > PREVISAO_MAX
    k = avanco / duracao
    vx = (ultimo[1] - anterior[1]) * k
    vy = (ultimo[2] - anterior[2]) * k
    # Um salto entre pacotes nao e velocidade: e teleporte. Nao se prolonga.
    limite = TELEPORTE_TILES * (Game_Map::REAL_RES_X rescue 128)
    return ultimo if vx.abs > limite || vy.abs > limite
    [instante,
     ultimo[1] + vx,
     ultimo[2] + vy,
     ultimo[3] ? (ultimo[3] + ((ultimo[3] - (anterior[3] || ultimo[3])) * k)) : nil,
     ultimo[4] ? (ultimo[4] + ((ultimo[4] - (anterior[4] || ultimo[4])) * k)) : nil,
     ultimo[5],
     ultimo[6]]
  rescue
    pontos.last
  end

  def estado(peer)
    pontos = peer && peer.mov_pontos
    return nil if pontos.nil? || pontos.empty?

    # RELOGIO DE REPRODUCAO.
    #
    # Anda com o tempo LOCAL (por isso e liso, frame a frame) mas vive na linha
    # do tempo do REMETENTE. So se corrige quando desliza demais — se fosse
    # recalculado a cada frame a partir do ultimo pacote, o jitter voltaria a
    # entrar no desenho, que era o defeito da primeira versao.
    agora_local = Time.now.to_f
    alvo = pontos.last[0] - atraso
    if peer.mov_relogio.nil?
      peer.mov_relogio = alvo
    else
      passado = agora_local - (peer.mov_ultimo_frame || agora_local)
      passado = 0.05 if passado <= 0 || passado > 0.25
      peer.mov_relogio += passado
      # Deriva grande (pausa, mudanca de mapa, rede caiu): reengata.
      peer.mov_relogio = alvo if (peer.mov_relogio - alvo).abs > 0.5
      # Deriva pequena: corrige devagar, para a propria correcao nao virar
      # tremor. Medido: a 10% por frame o desvio do passo era 5,5px mesmo com
      # rede perfeita; a 2% cai para 1,2px. Com a reengata dura acima, 2% ainda
      # fecha qualquer deriva em menos de um segundo.
      peer.mov_relogio += (alvo - peer.mov_relogio) * CORRECAO_RELOGIO
    end
    peer.mov_ultimo_frame = agora_local
    instante = peer.mov_relogio

    # Ainda nao chegamos ao inicio do historico (peer acabou de aparecer).
    return pontos.first if instante <= pontos.first[0]

    # Passamos do fim do historico. Fora do duelo segura-se no ultimo conhecido,
    # que e o comportamento seguro; no duelo continua-se o movimento, porque um
    # boneco parado a meio de uma corrida e mais errado do que um boneco cinco
    # pixeis a frente.
    if instante >= pontos.last[0]
      return prever(pontos, instante) if atraso <= 0.0
      return pontos.last
    end

    i = 1
    i += 1 while i < pontos.length - 1 && pontos[i][0] < instante
    a = pontos[i - 1]
    b = pontos[i]
    duracao = b[0] - a[0]
    return b if duracao <= 0

    f = (instante - a[0]) / duracao
    [instante,
     entre(a[1], b[1], f),
     entre(a[2], b[2], f),
     (a[3] && b[3]) ? entre(a[3], b[3], f) : b[3],
     (a[4] && b[4]) ? entre(a[4], b[4], f) : b[4],
     b[5],            # direccao nao se interpola: e discreta
     b[6]]
  end

  def entre(a, b, f)
    (a + ((b - a) * f)).round
  end

  # ⚠️ O PROPRIO JOGADOR ESTAVA NA LISTA DOS OUTROS. MEDIDO, NAO SUPOSTO.
  #
  # O log de movimento apanhou isto: na maquina do wallace havia DOIS peers —
  # `gaby-ol1n2c`, saudavel, a interpolar com 17 a 53 ms de idade; e
  # `wallace-adm100`, que e o proprio dono da maquina, sempre em `segura`, com
  # a idade a descer sem fim (-64, -184, -278, -409 ms). Uma idade negativa que
  # so cresce quer dizer uma coisa: aquele peer nunca mais recebeu um ponto.
  #
  # E nao recebe mesmo — ninguem manda pacotes para si proprio. Ele foi criado
  # cedo, provavelmente antes de o `self_internal_id` estar resolvido (todas as
  # quatro portas que criam peers comparam com ele, e uma comparacao contra
  # vazio deixa passar tudo), e ficou la para sempre.
  #
  # O que ele fazia:
  #   · um SEGUNDO boneco do jogador, desenhado por cima do verdadeiro, com
  #     dados velhos — e isso e o "sprite do jogador que fica piscando";
  #   · 1172 das 2274 amostras do log em `segura`, ou seja 69% dos frames
  #     contados como "buffer seco" eram este fantasma e nao a rede.
  #
  # Varre-se aqui, no sitio por onde todos os peers passam a cada frame, porque
  # nao interessa por que porta ele entrou: interessa que nao chegue a ser
  # desenhado. E fica o registo, uma vez, para se saber que aconteceu.
  def eu_proprio?(peer)
    meu = (AnilLanRework.self_internal_id.to_s rescue "")
    return false if meu.empty?
    (peer.internal_id.to_s == meu)
  rescue
    false
  end

  def expulsar_fantasma!(peer)
    id = (peer.internal_id.to_s rescue "?")
    (AnilArenaIntrusos.anotar(:eu_na_lista_de_peers, id) rescue nil)
    AnilLanRework.players.delete(id) rescue nil
    unless @avisou_fantasma
      @avisou_fantasma = true
      (AnilLanRework.log("[PEER] eu proprio estava na lista de peers (#{id}) — removido") rescue nil)
    end
    true
  rescue
    false
  end

  # Aplica ao corpo do peer. Substitui todo o antigo update_anim.
  def aplicar!(peer)
    return unless $game_map && $game_player
    return if eu_proprio?(peer) && expulsar_fantasma!(peer)
    # Longe da camara nao vale gastar CPU.
    return if [(peer.x - $game_player.x).abs, (peer.y - $game_player.y).abs].max > 50 rescue return

    e = estado(peer)
    return unless e
    novo_x = e[1]
    novo_y = e[2]
    trx = peer.trx
    try = peer.try

    # Salto absurdo -> aparece ja no sitio, sem atravessar o mapa a andar.
    if (novo_x - peer.real_x).abs > (trx * TELEPORTE_TILES) ||
       (novo_y - peer.real_y).abs > (try * TELEPORTE_TILES)
      peer.real_x = novo_x
      peer.real_y = novo_y
      peer.x = novo_x / trx
      peer.y = novo_y / try
      peer.mov_andado = 0.0
      return
    end

    andou = (novo_x - peer.real_x).abs + (novo_y - peer.real_y).abs
    peer.real_x = novo_x
    peer.real_y = novo_y
    peer.x = peer.real_x / trx
    peer.y = peer.real_y / try

    # ANIMACAO PELA DISTANCIA PERCORRIDA, no MESMO ritmo do motor.
    #
    # Medir por distancia (e nao por tempo) faz as pernas acompanharem sempre o
    # deslocamento real, sem contador que dessincroniza. Falta so acertar QUANTOS
    # quadros por tile, e isso sai da regra do proprio Game_Character:
    #
    #   pattern_time = (move_time * 2 * (move_speed >= 5 ? 2 : 1)) / 4
    #
    # Fazendo a conta, da 2 quadros por tile a andar e 1 a correr (a partir de
    # move_speed 5 a animacao e deliberadamente mais lenta). A primeira versao
    # usava 4 fixo, e por isso as pernas iam ao dobro a andar e ao quadruplo a
    # correr — o "acelerado" que se via.
    if andou > 0
      peer.mov_andado = (peer.mov_andado || 0.0) + andou
      por_tile = ((peer.move_speed || 3.5) >= 5) ? 1.0 : 2.0
      passo = trx / por_tile
      while peer.mov_andado >= passo
        peer.mov_andado -= passo
        peer.pattern = (peer.pattern + 1) % 4
      end
      peer.instance_variable_set(:@moving, true)
    else
      peer.mov_andado = 0.0
      peer.pattern = 0
      peer.instance_variable_set(:@moving, false)
    end
  rescue => e
    AnilLanRework.log("[MOV] aplicar! falhou: #{e.class}: #{e.message}") rescue nil
  end

  # Posicao do follower no MESMO instante do corpo, para os dois nunca saírem
  # um do outro. Devolve [rx, ry, dir] ou nil quando o peer nao tem follower.
  def follower(peer)
    e = estado(peer)
    return nil unless e && e[3] && e[4]
    [e[3], e[4], e[6] || peer.dir]
  end
end

class AnilLanRework::RemotePeer
  # ⚠️ O :t_env TEM de estar aqui. O 000_Multiplayer_Online escreve @t_env no
  # peer, mas sem o acessor o `peer.t_env` do registrar! levanta NoMethodError —
  # e como isso acontece no FIM do update_from_packet, a direccao e a posicao
  # logica (que sao aplicadas antes) chegavam, e o resto nao. O resultado em jogo
  # era: os outros olhavam para os lados, nao saiam do lugar, e desapareciam
  # (a posicao logica afastava-se e a limpeza de sprites removia-os).
  attr_accessor :mov_pontos, :mov_andado, :mov_relogio, :mov_ultimo_frame, :t_env

  # As duas definicoes antigas de update_anim (aqui e no 000e_FPS_Patch) passam a
  # delegar. Uma so implementacao, um so sitio para corrigir.
  def update_anim
    AnilMovimentoRemoto.aplicar!(self)
  end
end

AnilLanRework.log("136_Movimento_Remoto carregado (buffer de interpolacao)") rescue nil
