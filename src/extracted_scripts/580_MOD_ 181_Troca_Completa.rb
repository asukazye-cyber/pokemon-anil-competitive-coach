#===============================================================================
# MOD 181 — Troca completa (itens + Pokemon + moedas)
#===============================================================================
# Caixa partilhada: cada lado poe ate 2 itens, ate 2 Pokemon e um valor em
# moedas. O lado esquerdo e meu, o direito e do parceiro. Assimetrica de
# proposito — um lado pode dar so dinheiro e receber so um Pokemon.
#
# ⚠️ QUEM MANDA E O SERVIDOR. O cliente nao mexe em nada por conta propria.
#
# A dupe de agosto (ver execute_server_side_trade) aconteceu por o cliente
# trocar a party assim que os dois confirmaram, sem esperar. Aqui a mochila, a
# party e as moedas so mudam depois do "troca_ok", que so chega depois de o
# servidor ter validado as duas ofertas contra os saves DELE e ter gravado os
# dois ficheiros. Se o servidor recusar, nada aconteceu de nenhum dos lados.
#
# A regra "alterou, cai a confirmacao" tambem e do servidor: e ele que limpa a
# lista de confirmados a cada oferta nova e manda o "troca_reset". O botao aqui
# so reflecte isso.
#
# Teste: /troca <nome>
#===============================================================================

module AnilTrocaCompleta
  IMAGEM = "Graphics/UI/Mart/troca"

  # ⚠️ Anel do seletor recortado do proprio desenho, dilatado 1px.
  #
  # A elipse que eu calculava era uma aproximacao: os encaixes tem 63x64 e o
  # contorno deles nao e uma elipse perfeita. Por mais que acertasse os raios,
  # ficava torto num encaixe ou noutro. Recortado da arte, encaixa por
  # construcao — mesma receita da grelha da loja.
  #
  # So tem os quatro circulos. Os quadrados dos Pokemon continuam com o
  # rectangulo desenhado, que para um quadrado nao tem como sair torto.
  BRILHO     = "Graphics/UI/Mart/troca_brilho"       # os 4 circulos (item)
  BRILHO_MON = "Graphics/UI/Mart/troca_brilho_mon"   # os 4 quadrados (Pokemon)
  # 92 e nao 84: o anel colado ao buraco mede 85x85, e com 84 encostava a borda
  # do recorte e ficava cortado.
  CORTE      = 92

  # Canto da caixa no ecra de 512x384 (a caixa mede 382x356).
  CX = 65
  CY = 8

  # ⚠️ MEDIDO NA IMAGEM FINAL, nao convertido do original de 1032x1024.
  # Circulos = item, quadrados = Pokemon, barras = dinheiro. A divisao ao meio
  # e o que a arte manda: a barra da esquerda cobre exactamente as duas
  # primeiras colunas.
  ITEM_Y   = 69
  MON_Y    = 181
  BARRA_Y  = 251
  # ⚠️ 236 estava errado — a camada de brilho poe o terceiro circulo em 233,5.
  #
  # A minha medicao apanhou-o com 59px de largura (os outros tem 63), ou seja
  # cortou 4px de um lado e empurrou o centro. A camada, recortada do desenho
  # original, e a autoridade aqui.
  ITENS_MEUS = [62, 148]
  ITENS_DELE = [234, 318]
  MONS_MEUS  = [62, 147]
  MONS_DELE  = [233, 318]
  BARRA_MINHA = 104
  BARRA_DELE  = 275

  # ⚠️ Os dois botoes empilhados, entre as barras (y=251) e o fundo da caixa
  # (y=356). Sobram 86px, portanto 28 de altura cada com folga e sem passar por
  # cima das barras do dinheiro.
  MEIO         = 191
  BOTAO_CONF_Y = 292
  BOTAO_SAIR_Y = 326
  BOTAO_W      = 150
  BOTAO_H      = 30

  # ⚠️ COMO O TEXTO SE CENTRA — o mecanismo, nao um numero empurrado.
  #
  # Andei a somar e a tirar pixeis as cegas. O que se passa e isto: o draw_text
  # NAO centra na vertical, encosta os glifos ao TOPO do rectangulo. E o
  # text_size().height nao ajuda — devolve a altura da LINHA da fonte (~30), nao
  # a dos glifos, que nesta fonte ocupam uns 14px de altura visivel.
  #
  # Entao a conta certa e sempre a mesma:
  #
  #     descer = (altura_do_rectangulo - ALTURA_GLIFO) / 2
  #
  # Num botao de 30 dao 8; numa barra de 26 dao 6. Um numero so governa tudo, e
  # se a fonte mudar corrige-se aqui e nao em cinco sitios.
  # Afinado em jogo: 14 ainda deixava o texto alto. Menor = desce mais.
  ALTURA_GLIFO = 8

  # Os nomes no topo: maiores, a negrito, e cada um da cor do seu cursor. E o
  # que diz ao jogador, sem texto de ajuda, que o amarelo e ele.
  NOME_TAM     = 24
  NOME_MIN     = 14   # encolhe ate aqui se o nome for comprido

  # ⚠️ O NOME ALINHA COM A ABA, nao com a barra do dinheiro.
  #
  # As abas azuis no topo do desenho ja marcam os dois lados — medidas no
  # ficheiro: x 49..108 (centro 78) e x 271..331 (centro 301). O nome estava
  # centrado em 104 e 275, os centros das barras, ou seja 26px a direita de
  # cada aba. Agora cada nome fica em cima da sua.
  ABA_ESQ = 78
  ABA_DIR = 301
  NOME_Y  = 8
  # A aba esquerda esta perto da borda: 140 e o que cabe dos DOIS lados sem
  # transbordar (78 - 70 = 8 de margem).
  NOME_LARGURA = 140

  def self.descer_em(altura_caixa)
    d = ((altura_caixa - ALTURA_GLIFO) / 2.0).round
    d < 0 ? 0 : d
  end

  # Onde as etiquetas ficam. Todos estes valores sao o TOPO do texto, porque e
  # ai que o motor comeca a desenhar.
  QTD_ITEM_Y   = ITEM_Y + 22    # o "x3" por baixo do item
  DICA_MON_Y   = MON_Y  + 37    # o "C: ver" ABAIXO do quadrado (que acaba em +30)
  # ⚠️ Entre as duas linhas de encaixes: os circulos acabam em y=100 e os
  # quadrados comecam em 151. Estava por cima dos botoes, onde competia com o
  # proprio CONFIRMAR.
  CONFIRMOU_Y  = 118

  # ⚠️ O CURSOR PASSA PELOS DOIS LADOS.
  #
  # Antes so andava pelos meus encaixes. Mas confirmar uma troca sem poder olhar
  # para o que o outro pos e assinar as cegas — dai o lado dele ser navegavel,
  # em modo de leitura: nos Pokemon dele o C abre o resumo, nos itens diz o que
  # e. Nada do lado direito se edita.
  #
  # A navegacao e por LINHAS em vez de casos a mao: acrescentar um lugar deixou
  # de obrigar a reescrever os saltos todos, que foi como perdi tempo no menu
  # de interacao.
  # ⚠️ MEDIDO, nao arredondado a olho.
  #
  # Eu tinha posto 62x62 nos circulos, mas eles sao 63x64 — mais altos do que
  # largos. Com rx=ry o cursor saia redondo onde o encaixe e oval, e por isso
  # parecia entortar de um encaixe para o outro. Os quadrados sao 63x61.
  LUGARES = [
    [ITENS_MEUS[0], ITEM_Y,  63, 64],   # 0
    [ITENS_MEUS[1], ITEM_Y,  63, 64],   # 1
    [ITENS_DELE[0], ITEM_Y,  63, 64],   # 2
    [ITENS_DELE[1], ITEM_Y,  63, 64],   # 3
    [MONS_MEUS[0],  MON_Y,   63, 61],   # 4
    [MONS_MEUS[1],  MON_Y,   63, 61],   # 5
    [MONS_DELE[0],  MON_Y,   63, 61],   # 6
    [MONS_DELE[1],  MON_Y,   63, 61],   # 7
    [BARRA_MINHA,   BARRA_Y, 150, 26],  # 8
    [BARRA_DELE,    BARRA_Y, 150, 26],  # 9
    [MEIO, BOTAO_CONF_Y, BOTAO_W, BOTAO_H],  # 10
    [MEIO, BOTAO_SAIR_Y, BOTAO_W, BOTAO_H]   # 11
  ]
  LINHAS_NAV = [[0, 1, 2, 3], [4, 5, 6, 7], [8, 9], [10], [11]]

  CONFIRMAR = 10
  SAIR      = 11
  REDONDOS  = [0, 1, 2, 3]          # encaixes de item sao circulos
  QUADRADOS = [4, 5, 6, 7]          # encaixes de Pokemon
  MEUS_ITENS = { 0 => 0, 1 => 1 }
  MEUS_MONS  = { 4 => 0, 5 => 1 }
  DELE_ITENS = { 2 => 0, 3 => 1 }
  DELE_MONS  = { 6 => 0, 7 => 1 }
  MEU_DINHEIRO = 8
  # O que EU posso mexer. Tudo o resto do lado direito e so de leitura, e o
  # cursor muda de cor para se ver isso sem ter de experimentar.
  EDITAVEIS = [0, 1, 4, 5, 8, 10, 11]
  COR_MINHA = [255, 235, 90]
  COR_DELE  = [110, 225, 255]

  class << self
    attr_accessor :parceiro_id, :parceiro_nome
    attr_accessor :minha, :dele
    attr_accessor :confirmei, :ele_confirmou
    attr_accessor :resultado, :aberta

    def vazia
      { "coins" => 0, "items" => [nil, nil], "pokemon" => [nil, nil], "mons" => [nil, nil] }
    end

    def limpar!
      @minha = vazia
      @dele  = vazia
      @confirmei = false
      @ele_confirmou = false
      @resultado = nil
    end

    def log(t)
      File.open("Data/anil_troca_completa.txt", "ab") do |f|
        f.write("[#{Time.now.strftime('%d/%m %H:%M:%S')}] #{t}\n")
      end
    rescue
    end

    # ── o que viaja ──────────────────────────────────────────────────────────
    #
    # "oferta" e o que o servidor le e valida. Os Pokemon vao pelo PID; o
    # servidor procura-os na party do save dele e nunca acredita no que aqui
    # vier descrito.
    #
    # "mons_data" viaja a parte, com a descricao dos Pokemon, e serve so para o
    # OUTRO CLIENTE poder desenhar o icone e, no fim, inserir o bicho na party.
    # O servidor ignora-o — ele usa a copia que ja tem no save.
    #
    # ⚠️ Usa-se o Serializer do jogo, que produz um HASH de campos e nao um
    # Marshal. Alem de ser o que a troca 1-por-1 ja faz, nao abre a porta que um
    # Marshal.load de dados da rede abriria.
    def enviar_oferta!
      return unless AnilLanRework.connected? && @parceiro_id
      itens = @minha["items"].compact.map { |i| [i[0].to_s, i[1].to_i] }
      pids  = @minha["mons"].compact.map { |pk| (pk.personalID.to_i rescue 0) }.reject { |p| p <= 0 }
      blobs = @minha["mons"].map { |pk| pk ? (AnilLanRework::Serializer.serialize_pokemon(pk) rescue nil) : nil }
      AnilLanRework.connection.send_packet("troca_oferta",
        "to_id"     => @parceiro_id,
        "oferta"    => { "coins" => @minha["coins"].to_i, "items" => itens, "pokemon" => pids },
        "mons_data" => blobs)
      log("enviei: #{@minha['coins']} moedas, #{itens.inspect}, PIDs #{pids.inspect}")
    end

    def enviar_confirma!(aceito)
      return unless AnilLanRework.connected? && @parceiro_id
      AnilLanRework.connection.send_packet("troca_confirma",
        "to_id" => @parceiro_id, "status" => aceito ? "accepted" : "cancelled")
    end

    def enviar_cancelamento!
      return unless AnilLanRework.connected? && @parceiro_id
      AnilLanRework.connection.send_packet("troca_cancel", "to_id" => @parceiro_id)
    end

    # ⚠️ Bombear a rede DENTRO do laco da caixa.
    #
    # Sem isto os pacotes ficam na fila e so sao lidos quando a cena fecha — que
    # foi porque a oferta do parceiro nunca aparecia: ele punha o item, o
    # servidor reencaminhava, e o meu cliente so lia aquilo depois de eu sair.
    # O ecra de espera do convite ja fazia isto (ver pump_network); a minha cena
    # e que nao.
    def bombear_rede!
      return unless AnilLanRework.connected?
      AnilLanRework.connection.tick
      AnilLanRework.connection.drain { |pk| AnilLanRework::Router.route_packet(pk) }
    rescue
    end

    # ── o que chega ──────────────────────────────────────────────────────────
    #
    # ⚠️ PORTAO DE REMETENTE. Nenhum pacote de troca e aceite se nao vier do
    # parceiro DESTA caixa.
    #
    # O servidor ja enderaca tudo por send_to(to_id), e a sessao la e uma chave
    # do par — nao ha broadcast em lado nenhum. Mas um pacote mal endereçado, ou
    # uma sessao antiga a chegar atrasada, entregaria itens de outra pessoa. E
    # como o servidor valida contra o SAVE, um pacote errado aqui nao daria
    # itens a mais, mas mostrava a oferta de um estranho na minha caixa e eu
    # podia confirmar uma troca que nao era a minha.
    #
    # Com a caixa fechada (@parceiro_id nil) rejeita-se tudo: e assim que uma
    # resposta atrasada de uma troca ja cancelada deixa de mexer em nada.
    def do_parceiro?(packet)
      return false if @parceiro_id.nil? || @parceiro_id.to_s.empty?
      de = (packet["sender_id"] || packet["internal_id"] || packet["peer_id"]).to_s
      if de != @parceiro_id.to_s
        log("IGNORADO #{packet['type']} de #{de.inspect} (a troca e com #{@parceiro_id})")
        return false
      end
      true
    end

    def receber_oferta(packet)
      return unless do_parceiro?(packet)
      o = packet["oferta"] || {}
      nova = vazia
      nova["coins"] = o["coins"].to_i
      Array(o["items"]).first(2).each_with_index do |par, i|
        next unless par.is_a?(Array) && par.size >= 2
        nova["items"][i] = [par[0].to_s, par[1].to_i]
      end
      blobs = packet["mons_data"]
      if blobs.is_a?(Array)
        blobs.first(2).each_with_index do |b, i|
          next unless b.is_a?(Hash)
          nova["mons"][i] = (AnilLanRework::Serializer.deserialize_pokemon(b) rescue nil)
        end
      end
      @dele = nova
      # Uma oferta nova invalida as duas confirmacoes — e o servidor manda o
      # troca_reset a seguir, mas adianta-se aqui para o botao nao piscar.
      @confirmei = false
      @ele_confirmou = false
      log("recebi: #{nova['coins']} moedas, #{nova['items'].compact.inspect}, #{nova['mons'].compact.length} pokemon")
    end

    def receber_reset(packet)
      return unless do_parceiro?(packet)
      @confirmei = false
      @ele_confirmou = false
    end

    def receber_confirma(packet)
      return unless do_parceiro?(packet)
      @ele_confirmou = (packet["status"].to_s == "accepted")
      @resultado = :cancelado if packet["status"].to_s == "cancelled"
    end

    # ⚠️ SO AQUI E QUE SE MEXE EM ALGUMA COISA.
    #
    # Este pacote e a prova de que o servidor ja gravou os dois saves. A ordem
    # importa: tira-se primeiro e poe-se depois, para nunca haver um instante em
    # que o mesmo bem esta dos dois lados.
    def aplicar_sucesso!(packet)
      return unless do_parceiro?(packet)
      dei    = packet["dei"]    || {}
      recebi = packet["recebi"] || {}
      begin
        # 1. tirar o que dei
        @minha["items"].compact.each { |n, q| $bag.remove(n.to_sym, q) rescue nil }
        @minha["mons"].compact.each do |pk|
          i = $player.party.index { |p| p && p.personalID == pk.personalID }
          $player.party.delete_at(i) if i
        end
        $player.coins = [$player.coins - dei["coins"].to_i, 0].max if dei["coins"].to_i > 0

        # 2. receber o que veio
        Array(recebi["items"]).each do |par|
          next unless par.is_a?(Array) && par.size >= 2
          $bag.add(par[0].to_sym, par[1].to_i) rescue nil
        end
        @dele["mons"].compact.each do |pk|
          pk.obtain_method = 2 rescue nil
          $player.party.push(pk) if $player.party.length < 6
        end
        $player.coins = $player.coins + recebi["coins"].to_i if recebi["coins"].to_i > 0
        @resultado = :sucesso
        log("APLICADO. dei #{dei.inspect} / recebi #{recebi.inspect}")
      rescue => e
        log("ERRO ao aplicar: #{e.class}: #{e.message}")
        @resultado = :sucesso   # o servidor gravou; o save desce na proxima sync
      end
      # ⚠️ GRAVA JA, e usa um motivo que fura o throttle.
      #
      # "trade_started" esta no AUTOSAVE_IMEDIATO, portanto nao espera pela
      # janela de 60s. E preciso: acabaram de entrar itens, moedas e Pokemon na
      # partida, e o servidor ja gravou o lado dele. Se o jogo fechasse antes do
      # upload, o save do disco ficava atrasado em relacao a nuvem — e e o
      # pending_trade_sync que apanha isso, mas mais vale nao chegar la.
      (AnilLanRework.save_and_upload_save_file("trade_started") rescue nil)
    end

    def receber_falha(packet)
      return unless do_parceiro?(packet)
      @resultado = :falhou
    end

    # ── entrada ──────────────────────────────────────────────────────────────
    def abrir(peer_id, nome)
      return if @aberta
      @parceiro_id   = peer_id.to_s
      @parceiro_nome = nome.to_s
      limpar!
      @aberta = true
      log("abriu troca com #{nome} (#{peer_id})")
      begin
        AnilTrocaCompletaCena.new.executar
      ensure
        @aberta = false
        @parceiro_id = nil
      end
    end
  end
end

#===============================================================================
# A cena
#===============================================================================
class AnilTrocaCompletaCena
  T = AnilTrocaCompleta

  def executar
    montar!
    laco!
  ensure
    desmontar!
  end

  def montar!
    @vp = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @vp.z = 99999
    @sp = {}
    @cursor = 0
    @t = 0

    # ⚠️ SEM o bg.png da loja.
    #
    # Estava la so para nao ficar o mapa cru por tras, mas aquele fundo traz o
    # painel branco da lista de itens desenhado dentro — aparecia a espreitar
    # pelos lados da caixa. So a caixa, sobre o mapa.

    @sp["caixa"] = IconSprite.new(T::CX, T::CY, @vp)
    @sp["caixa"].setBitmap(T::IMAGEM)
    @sp["caixa"].z = 10

    # Icones: 4 de item, 4 de Pokemon.
    4.times do |i|
      s = ItemIconSprite.new(0, 0, nil, @vp)
      s.blankzero = true
      s.setOffset(PictureOrigin::CENTER)
      s.z = 20
      @sp["it#{i}"] = s
    end
    4.times do |i|
      s = PokemonIconSprite.new(nil, @vp)
      s.setOffset(PictureOrigin::CENTER)
      s.z = 20
      # ⚠️ O quadro do icone e 64x64 mas o bicho so ocupa uns 48 la dentro —
      # o resto e margem. A 0.82 o Pokemon aparecia com ~40px ao lado de itens
      # de 48, e parecia encolhido. A 1.2 fica com ~58, do tamanho do encaixe,
      # e a margem do proprio icone impede que encoste a moldura.
      s.zoom_x = s.zoom_y = 1.2
      # ⚠️ ACIMA do anel (z 41). O icone transborda o quadrado e ficava com as
      # patas cortadas pelo brilho; o que se ve por fora do encaixe e o bicho,
      # nao a moldura.
      s.z = 45
      @sp["mn#{i}"] = s
    end

    # A camada e opcional: sem ela cai-se no anel desenhado.
    @brilho = nil
    @brilho_mon = nil
    @brilho     = (AnimatedBitmap.new(T::BRILHO)     rescue nil) if pbResolveBitmap(T::BRILHO)
    @brilho_mon = (AnimatedBitmap.new(T::BRILHO_MON) rescue nil) if pbResolveBitmap(T::BRILHO_MON)
    T.log("brilho: circulos=#{@brilho ? 'ok' : 'em falta'} quadrados=#{@brilho_mon ? 'ok' : 'em falta'}")

    @sp["texto"] = BitmapSprite.new(Graphics.width, Graphics.height, @vp)
    @sp["texto"].z = 30
    pbSetSystemFont(@sp["texto"].bitmap)

    @sp["cursor"] = BitmapSprite.new(Graphics.width, Graphics.height, @vp)
    @sp["cursor"].z = 40

    # ⚠️ Sprite SEPARADO para o anel.
    #
    # A cor da camada vem do Sprite#color, que e um tint de hardware. Um blt
    # para dentro do bitmap do cursor copiava a mascara branca e nao havia
    # forma de a tingir — foi o meu primeiro engano aqui.
    anel = BitmapSprite.new(T::CORTE, T::CORTE, @vp)
    anel.ox = T::CORTE / 2
    anel.oy = T::CORTE / 2
    anel.z  = 41
    anel.visible = false
    @sp["anel"] = anel
    @anel_slot = -1

    @sp["msg"] = Window_AdvancedTextPokemon.new("")
    @sp["msg"].viewport = @vp
    @sp["msg"].visible = false
    @sp["msg"].z = 200

    redesenhar!
  end

  def desmontar!
    # Fora do @sp, portanto o pbDisposeSpriteHash nao lhe toca.
    [@brilho, @brilho_mon].each { |bm| (bm.dispose rescue nil) if bm }
    @brilho = nil
    @brilho_mon = nil
    pbDisposeSpriteHash(@sp) if @sp
    @vp.dispose if @vp && !@vp.disposed?
  end

  # ── desenho ────────────────────────────────────────────────────────────────
  def redesenhar!
    2.times do |i|
      poe_item(@sp["it#{i}"],     T::ITENS_MEUS[i], T::ITEM_Y, T.minha["items"][i])
      poe_item(@sp["it#{i + 2}"], T::ITENS_DELE[i], T::ITEM_Y, T.dele["items"][i])
      poe_mon(@sp["mn#{i}"],      T::MONS_MEUS[i],  T::MON_Y,  T.minha["mons"][i])
      poe_mon(@sp["mn#{i + 2}"],  T::MONS_DELE[i],  T::MON_Y,  T.dele["mons"][i])
    end
    texto!
  end

  def poe_item(s, cx, cy, par)
    s.item    = par ? (par[0].to_sym rescue nil) : nil
    s.visible = !par.nil?
    s.x = T::CX + cx
    s.y = T::CY + cy
  end

  def poe_mon(s, cx, cy, pk)
    s.pokemon = pk
    s.visible = !pk.nil?
    s.x = T::CX + cx
    s.y = T::CY + cy
  end

  def texto!
    b = @sp["texto"].bitmap
    b.clear
    branco = Color.new(255, 255, 255)
    sombra = Color.new(30, 42, 52)

    meu = ($player.name.to_s rescue "")
    meu = _INTL("Tu") if meu.empty?
    escreve_nome(b, meu,                  T::CX + T::ABA_ESQ, T::CY + T::NOME_Y, T::COR_MINHA, sombra)
    escreve_nome(b, T.parceiro_nome.to_s, T::CX + T::ABA_DIR, T::CY + T::NOME_Y, T::COR_DELE,  sombra)

    # So o numero: a barra ja diz que aquilo e dinheiro. Centrado DENTRO do
    # rectangulo da barra, nao a partir de um y fixo — era isso que o punha
    # encostado ao topo.
    # Rectangulo medido no proprio desenho: y 239..264, 148x26.
    bw, bh = 148, 26
    escreve_em(b, fmt(T.minha["coins"]), T::CX + T::BARRA_MINHA - (bw / 2),
               T::CY + T::BARRA_Y - (bh / 2), bw, bh, branco, sombra, T.descer_em(bh))
    escreve_em(b, fmt(T.dele["coins"]),  T::CX + T::BARRA_DELE - (bw / 2),
               T::CY + T::BARRA_Y - (bh / 2), bw, bh, branco, sombra, T.descer_em(bh))

    2.times do |i|
      p1 = T.minha["items"][i]
      p2 = T.dele["items"][i]
      escreve(b, "x#{p1[1]}", T::CX + T::ITENS_MEUS[i], T::CY + T::QTD_ITEM_Y, branco, sombra) if p1
      escreve(b, "x#{p2[1]}", T::CX + T::ITENS_DELE[i], T::CY + T::QTD_ITEM_Y, branco, sombra) if p2
    end

    verde = T.confirmei ? Color.new(46, 140, 74) : Color.new(52, 78, 100)
    botao(b, T::MEIO, T::BOTAO_CONF_Y,
          T.confirmei ? _INTL("ESPERANDO") : _INTL("CONFIRMAR"), verde, branco, sombra)
    botao(b, T::MEIO, T::BOTAO_SAIR_Y, _INTL("SAIR"), Color.new(120, 52, 58), branco, sombra)

    if T.ele_confirmou
      escreve(b, _INTL("{1} confirmou", T.parceiro_nome), T::CX + T::MEIO, T::CY + T::CONFIRMOU_Y,
              Color.new(120, 255, 150), sombra)
    end

    # Dica so quando ela serve: em cima de um Pokemon dele que exista.
    if (i = T::DELE_MONS[@cursor]) && T.dele["mons"][i]
      escreve(b, _INTL("C: ver"), T::CX + T::MONS_DELE[i], T::CY + T::DICA_MON_Y,
              Color.new(110, 225, 255), sombra)
    end
  end

  # Botao centrado em (cx, cy), com a moldura escura por fora para se destacar
  # do metal da caixa.
  # ⚠️ O CENTRAR E DO MOTOR, NAO MEU.
  #
  # Eu calculava x = centro - text_size/2 e desenhava a partir dai. O
  # text_size nao bate certo com o que o draw_text acaba por desenhar (kerning,
  # a folga que eu somava a largura), e o texto saia sempre uns pixeis a
  # esquerda. Passando o RECTANGULO DO BOTAO ao draw_text com align 1, quem
  # centra e o motor e nao ha conta minha para errar.
  def botao(bitmap, cx, cy, txt, cor, branco, sombra)
    x = T::CX + cx - (T::BOTAO_W / 2)
    y = T::CY + cy - (T::BOTAO_H / 2)
    bitmap.fill_rect(x - 2, y - 2, T::BOTAO_W + 4, T::BOTAO_H + 4, Color.new(18, 28, 36, 220))
    bitmap.fill_rect(x, y, T::BOTAO_W, T::BOTAO_H, cor)
    bitmap.fill_rect(x, y, T::BOTAO_W, 1, Color.new(255, 255, 255, 60))
    escreve_em(bitmap, txt, x, y, T::BOTAO_W, T::BOTAO_H, branco, sombra, T.descer_em(T::BOTAO_H))
  end

  # ⚠️ Repoe o tamanho e o negrito no fim.
  #
  # O bitmap do texto e um so e e reutilizado por tudo o que se escreve na
  # caixa. Deixar a fonte grande e a negrito depois de desenhar o nome punha
  # todo o resto — quantidades, moedas, botoes — com o tamanho errado.
  def escreve_nome(bitmap, txt, cx, cy, rgb, sombra)
    tam  = bitmap.font.size
    bold = bitmap.font.bold
    bitmap.font.size = T::NOME_TAM
    bitmap.font.bold = true
    while bitmap.font.size > T::NOME_MIN && bitmap.text_size(txt).width > T::NOME_LARGURA
      bitmap.font.size -= 1
    end
    escreve(bitmap, txt, cx, cy, Color.new(rgb[0], rgb[1], rgb[2]), sombra)
    bitmap.font.size = tam
    bitmap.font.bold = bold
  end

  def escreve(bitmap, txt, cx, cy, cor, sombra)
    larg = bitmap.text_size(txt).width
    x = cx - (larg / 2)
    alt = bitmap.font.size + 8   # acompanha a fonte, senao o nome grande corta
    bitmap.font.color = sombra
    bitmap.draw_text(x + 1, cy + 1, larg + 4, alt, txt)
    bitmap.font.color = cor
    bitmap.draw_text(x, cy, larg + 4, alt, txt)
  end

  # ⚠️ CENTRAR NUM RECTANGULO, na horizontal E na vertical.
  #
  # O align 1 do draw_text so trata do horizontal; na vertical ele encosta ao
  # topo do rectangulo, e por isso as legendas dos botoes e os numeros das
  # barras apareciam colados a borda de cima. Mede-se a altura do texto e
  # centra-se a mao.
  def escreve_em(bitmap, txt, x, y, w, h, cor, sombra, desce = 0)
    ty = y + desce
    bitmap.font.color = sombra
    bitmap.draw_text(x + 1, ty + 1, w, h, txt, 1)
    bitmap.font.color = cor
    bitmap.draw_text(x, ty, w, h, txt, 1)
  end

  def fmt(n)
    n.to_i.to_s.reverse.scan(/\d{1,3}/).join(".").reverse
  end

  # Que camada serve este encaixe (nil = nao ha, desenha-se a mao).
  def camada_do(slot)
    return @brilho     if T::REDONDOS.include?(slot)  && @brilho     && @brilho.bitmap     && !@brilho.bitmap.disposed?
    return @brilho_mon if T::QUADRADOS.include?(slot) && @brilho_mon && @brilho_mon.bitmap && !@brilho_mon.bitmap.disposed?
    nil
  end

  def cursor!
    b = @sp["cursor"].bitmap
    b.clear
    cx, cy, w, h = T::LUGARES[@cursor]
    pulso = ((Math.sin(@t * 0.12) * 0.5) + 0.5)
    rgb  = T::EDITAVEIS.include?(@cursor) ? T::COR_MINHA : T::COR_DELE
    alfa = (150 + (pulso * 105)).to_i
    c    = Color.new(rgb[0], rgb[1], rgb[2], alfa)
    anel = @sp["anel"]
    cam  = camada_do(@cursor)

    if cam
      if @anel_slot != @cursor
        @anel_slot = @cursor
        lado = T::CORTE
        anel.bitmap.clear
        # As coordenadas do recorte sao as da CAMADA, que tem o tamanho da
        # caixa — os mesmos cx/cy, sem o CX/CY do ecra.
        anel.bitmap.blt(0, 0, cam.bitmap,
                        Rect.new(cx - (lado / 2), cy - (lado / 2), lado, lado))
      end
      anel.x = T::CX + cx
      anel.y = T::CY + cy
      anel.color   = Color.new(rgb[0], rgb[1], rgb[2], 255)
      anel.opacity = alfa
      anel.visible = true
    else
      anel.visible = false
      @anel_slot = -1
      if T::REDONDOS.include?(@cursor)
        anel_desenhado(b, T::CX + cx, T::CY + cy, w / 2, h / 2, 3, c)
      else
        x = T::CX + cx - (w / 2)
        y = T::CY + cy - (h / 2)
        3.times do |o|
          b.fill_rect(x - o, y - o, w + (o * 2), 1, c)
          b.fill_rect(x - o, y + h + o, w + (o * 2), 1, c)
          b.fill_rect(x - o, y - o, 1, h + (o * 2), c)
          b.fill_rect(x + w + o, y - o, 1, h + (o * 2), c)
        end
      end
    end
  end

  # ⚠️ BANDA CHEIA, nao tres contornos de 1px.
  #
  # Eu desenhava tres elipses de um pixel, uma dentro da outra. Nas zonas quase
  # horizontais (topo e fundo) o passo em x salta varios pixeis por linha e os
  # tres contornos nao se encostam — dai o ar "falhado". Aqui preenche-se a
  # BANDA entre o raio de fora e o de dentro, uma fill_rect por lado e por
  # linha: fica solida por construcao. E a mesma receita do anel da loja.
  def anel_desenhado(bitmap, cx, cy, rx, ry, espessura, cor)
    return if rx <= 0 || ry <= 0
    rxi = rx - espessura
    ryi = ry - espessura
    dy  = -ry
    while dy <= ry
      fo = 1.0 - ((dy * dy).to_f / (ry * ry))
      if fo > 0
        xe = (rx * Math.sqrt(fo)).round
        if ryi > 0 && dy.abs < ryi
          fi = 1.0 - ((dy * dy).to_f / (ryi * ryi))
          xi = fi > 0 ? (rxi * Math.sqrt(fi)).round : 0
          larg = xe - xi
          if larg > 0
            bitmap.fill_rect(cx - xe, cy + dy, larg, 1, cor)
            bitmap.fill_rect(cx + xi, cy + dy, larg, 1, cor)
          end
        else
          bitmap.fill_rect(cx - xe, cy + dy, xe * 2, 1, cor)
        end
      end
      dy += 1
    end
  end

  # ⚠️ Assinatura barata do estado visivel.
  #
  # O laco corre a 60fps e o texto!/redesenhar! limpam e redesenham bitmaps
  # inteiros. Comparar T.dele.inspect era tentador e mau: os "mons" sao objectos
  # Pokemon e o inspect deles e enorme. Aqui so entram os campos que se veem.
  def assinatura
    [T.minha["coins"], T.dele["coins"],
     T.minha["items"].map { |i| i && [i[0], i[1]] },
     T.dele["items"].map  { |i| i && [i[0], i[1]] },
     T.minha["mons"].map { |m| m && (m.personalID rescue 0) },
     T.dele["mons"].map  { |m| m && (m.personalID rescue 0) },
     T.confirmei, T.ele_confirmou, @cursor].to_s
  end

  def laco!
    antes = nil
    loop do
      Graphics.update
      Input.update
      # ⚠️ SEM ISTO NADA DO PARCEIRO CHEGA. Ver bombear_rede!.
      T.bombear_rede!
      pbUpdateSpriteHash(@sp)
      @t += 1
      cursor!

      # A oferta dele muda pela REDE, nao por input meu: e preciso reparar que
      # mudou, senao a caixa fica com o que la estava.
      agora = assinatura
      if agora != antes
        antes = agora
        redesenhar!
      end

      case T.resultado
      when :sucesso
        # ⚠️ NAO se mostra nada aqui dentro.
        #
        # A caixa fecha primeiro e a faixa aparece por cima do mapa, sozinha, a
        # desvanecer ao fim de uns segundos. Assim o jogador volta a andar na
        # hora em vez de ficar preso a olhar para um aviso — e ve o resultado
        # da troca no mundo, nao dentro de um ecra que ja acabou.
        AnilTrocaAviso.mostrar(_INTL("Troca concluida com {1}!", T.parceiro_nome))
        return
      when :falhou
        aviso(_INTL("O servidor recusou a troca. Nada foi trocado."))
        return
      when :cancelado
        aviso(_INTL("{1} saiu da troca.", T.parceiro_nome))
        return
      end

      unless AnilLanRework.connected?
        aviso(_INTL("Perdeste a ligacao."))
        return
      end

      if Input.trigger?(Input::BACK)
        sair!
        return
      end

      if Input.trigger?(Input::USE)
        return if usar!
        antes = nil   # forca o redesenho no proximo frame
        next
      end

      mudou = false
      if    Input.repeat?(Input::LEFT)  then mudou = andar(-1, 0)
      elsif Input.repeat?(Input::RIGHT) then mudou = andar(1, 0)
      elsif Input.repeat?(Input::UP)    then mudou = andar(0, -1)
      elsif Input.repeat?(Input::DOWN)  then mudou = andar(0, 1)
      end
      pbPlayCursorSE if mudou
    end
  end

  # Sair avisa o outro lado. O servidor apaga a sessao e reencaminha o
  # troca_cancel, e a caixa dele fecha com a mensagem — ninguem fica a olhar
  # para uma troca que ja nao existe.
  def sair!
    T.enviar_cancelamento!
    pbPlayCancelSE
    aviso(_INTL("Saiste da troca."))
  end

  # Onde esta o cursor, em (linha, coluna).
  def onde
    T::LINHAS_NAV.each_with_index do |linha, li|
      ci = linha.index(@cursor)
      return [li, ci] if ci
    end
    [0, 0]
  end

  # Anda na grelha. Ao mudar de linha mantem-se a coluna mais proxima, para o
  # cursor nao saltar para o principio quando a linha de baixo e mais curta.
  def andar(dx, dy)
    li, ci = onde
    if dx != 0
      novo = ci + dx
      return false if novo < 0 || novo >= T::LINHAS_NAV[li].length
      @cursor = T::LINHAS_NAV[li][novo]
      return true
    end
    nl = li + dy
    return false if nl < 0 || nl >= T::LINHAS_NAV.length
    linha = T::LINHAS_NAV[nl]
    @cursor = linha[[ci, linha.length - 1].min]
    true
  end

  # ⚠️ Qualquer alteracao volta a mandar a oferta, e e o SERVIDOR que derruba
  # as confirmacoes ao receber. Nao ha caminho em que a oferta mude sem o outro
  # lado saber.
  def usar!
    if (i = T::MEUS_ITENS[@cursor]) then mexer_item(i);  return false end
    if (i = T::MEUS_MONS[@cursor])  then mexer_mon(i);   return false end
    if (i = T::DELE_MONS[@cursor])  then ver_mon_dele(i); return false end
    if (i = T::DELE_ITENS[@cursor]) then ver_item_dele(i); return false end
    return false if @cursor == 9                     # dinheiro dele: so leitura
    case @cursor
    when T::MEU_DINHEIRO then mexer_dinheiro
    when T::CONFIRMAR
      if T.confirmei
        T.confirmei = false
        T.enviar_confirma!(false)
      else
        if nada_na_mesa?
          aviso(_INTL("Nao ha nada em cima da mesa."))
        elsif sem_espaco?
          aviso(_INTL("Sua equipe ficaria com Pokémon demais."))
        elsif ficaria_sem_mons?
          aviso(_INTL("Você não pode ficar sem nenhum Pokémon."))
        else
          T.confirmei = true
          T.enviar_confirma!(true)
        end
      end
    when T::SAIR
      sair!
      return true
    end
    false
  end

  def nada_na_mesa?
    a = T.minha; b = T.dele
    a["coins"].to_i <= 0 && a["items"].compact.empty? && a["mons"].compact.empty? &&
      b["coins"].to_i <= 0 && b["items"].compact.empty? && b["mons"].compact.empty?
  end

  # ⚠️ Bloquear aqui foi decisao explicita: nao se mexe na storage_system.
  # O servidor volta a conferir isto — ver validar_oferta.
  def sem_espaco?
    ($player.party.length - T.minha["mons"].compact.length + T.dele["mons"].compact.length) > 6
  end

  def ficaria_sem_mons?
    ($player.party.length - T.minha["mons"].compact.length + T.dele["mons"].compact.length) < 1
  end

  def mexer_item(i)
    if T.minha["items"][i]
      T.minha["items"][i] = nil
      T.enviar_oferta!
      return
    end
    esconder(true)
    escolhido = nil
    begin
      cena = PokemonBag_Scene.new
      ecra = PokemonBagScreen.new(cena, $bag)
      escolhido = ecra.pbChooseItemScreen(proc { |itm|
        next false if !itm
        next false if GameData::Item.get(itm).is_important?    # nada de chaves
        next false if T.minha["items"].compact.any? { |p| p[0].to_s == itm.to_s }
        true
      })
    rescue => e
      T.log("erro no seletor de item: #{e.class}: #{e.message}")
    end
    esconder(false)
    return if escolhido.nil?
    total = $bag.quantity(escolhido)
    return if total <= 0
    qtd = pedir_numero(_INTL("Quantos?"), total)
    return if qtd <= 0
    T.minha["items"][i] = [escolhido.to_s, qtd]
    T.enviar_oferta!
  end

  def mexer_mon(i)
    if T.minha["mons"][i]
      T.minha["mons"][i] = nil
      T.enviar_oferta!
      return
    end
    esconder(true)
    idx = nil
    begin
      # ⚠️ ASSINATURA ERRADA — era isto que fazia "nao acontecer nada".
      #
      # Ha dois pbChoosePokemon: o da CENA aceita (switching, initialsel,
      # canswitch), o do ECRA aceita so um helptext. Eu chamava o do ecra com os
      # tres argumentos da cena, dava ArgumentError, e o meu proprio rescue
      # engolia-o — nenhum erro no ecra, nenhum Pokemon adicionado.
      #
      # E faltava o pbStartScene: sem ele o ecra nem chega a montar-se. Este e o
      # mesmo padrao que a troca 1-por-1 ja usa.
      cena = PokemonParty_Scene.new
      ecra = PokemonPartyScreen.new(cena, $player.party)
      ecra.pbStartScene(_INTL("Escolhe o Pokemon para a troca"), false)
      idx = ecra.pbChoosePokemon
      ecra.pbEndScene
    rescue => e
      T.log("erro no seletor de pokemon: #{e.class}: #{e.message}")
      idx = nil
    end
    esconder(false)
    return if idx.nil? || idx < 0
    pk = $player.party[idx]
    return if pk.nil?
    return aviso(_INTL("Esse Pokemon ja esta na mesa.")) if T.minha["mons"].compact.any? { |p| p.personalID == pk.personalID }
    return aviso(_INTL("Você não pode trocar um ovo.")) if (pk.egg? rescue false)
    T.minha["mons"][i] = pk
    T.enviar_oferta!
  end

  # ⚠️ Resumo em modo REMOTO.
  #
  # O PokemonSummary_Scene tem um `remote_view` que o jogo ja usa para espreitar
  # o Pokemon de outro jogador — corta o que nao faz sentido num bicho que nao e
  # meu (dar item, mudar golpes). Usa-se o mesmo aqui: e o que garante que ver o
  # que ele pos na mesa nao deixa mexer-lhe.
  def ver_mon_dele(i)
    pk = T.dele["mons"][i]
    return if pk.nil?
    esconder(true)
    begin
      cena = PokemonSummary_Scene.new
      cena.remote_view = true rescue nil
      cena.peer_owner_name = T.parceiro_nome.to_s rescue nil
      ecra = PokemonSummaryScreen.new(cena)
      ecra.remote_view = true rescue nil
      ecra.pbStartScreen([pk], 0)
    rescue => e
      T.log("erro no resumo remoto: #{e.class}: #{e.message}")
    end
    esconder(false)
  end

  # Nos itens dele nao ha resumo: diz-se o que e e o que faz.
  def ver_item_dele(i)
    par = T.dele["items"][i]
    return if par.nil?
    sym = (par[0].to_sym rescue nil)
    return if sym.nil?
    nome = (GameData::Item.get(sym).name rescue par[0].to_s)
    desc = (GameData::Item.get(sym).description rescue "")
    aviso("#{nome} x#{par[1]}
#{desc}", 3)
  end

  def mexer_dinheiro
    tecto = ($player.coins.to_i rescue 0)
    return aviso(_INTL("Você não tem moedas.")) if tecto <= 0
    v = pedir_numero(_INTL("Quantas moedas?"), tecto)
    T.minha["coins"] = v
    T.enviar_oferta!
  end

  def pedir_numero(texto, maximo)
    esconder(true)
    valor = 0
    begin
      params = ChooseNumberParams.new
      params.setRange(0, maximo)
      params.setDefaultValue(0)
      params.setCancelValue(0)
      w = Window_AdvancedTextPokemon.newWithSize(texto, 0, 0, Graphics.width, 96)
      w.z = 99999
      valor = pbChooseNumber(w, params)
      w.dispose
    rescue => e
      T.log("erro no numero: #{e.class}: #{e.message}")
      valor = 0
    end
    esconder(false)
    valor.to_i
  end

  # As cenas da mochila e da party montam viewports proprios; esconder o nosso
  # evita o piscar e o desperdicio de as duas coisas se desenharem por cima.
  def esconder(sim)
    @vp.visible = !sim if @vp && !@vp.disposed?
  end

  def aviso(txt, linhas = 2)
    w = @sp["msg"]
    w.text = txt
    w.visible = true
    pbBottomLeftLines(w, linhas)
    fim = System.uptime + 2.0
    loop do
      Graphics.update
      Input.update
      T.bombear_rede!
      pbUpdateSpriteHash(@sp)
      break if System.uptime >= fim
      break if Input.trigger?(Input::USE) || Input.trigger?(Input::BACK)
    end
    w.visible = false
  end
end

#===============================================================================
# Rede: os pacotes que chegam
#===============================================================================
module AnilLanRework
  module Router
    class << self
      alias anil_troca_orig_route_packet route_packet unless method_defined?(:anil_troca_orig_route_packet)

      def route_packet(packet)
        case packet["type"].to_s
        when "troca_oferta"
          AnilTrocaCompleta.receber_oferta(packet) rescue nil
          return
        when "troca_reset"
          AnilTrocaCompleta.receber_reset(packet) rescue nil
          return
        when "troca_confirma"
          AnilTrocaCompleta.receber_confirma(packet) rescue nil
          return
        when "troca_ok"
          AnilTrocaCompleta.aplicar_sucesso!(packet) rescue nil
          return
        when "troca_falhou"
          AnilTrocaCompleta.receber_falha(packet) rescue nil
          return
        when "troca_cancel"
          if (AnilTrocaCompleta.do_parceiro?(packet) rescue false)
            AnilTrocaCompleta.resultado = :cancelado
            # Se ainda estou a espera da resposta ao convite, isto e a recusa —
            # sem esta linha ficava os 30 segundos todos a olhar para a faixa.
            AnilTrocaCompleta.convite_aceite = false
          end
          return
        when "troca_convite"
          AnilTrocaCompleta.receber_convite(packet) rescue nil
          return
        end
        anil_troca_orig_route_packet(packet)
      end
    end
  end
end

module AnilTrocaCompleta
  class << self
    # ⚠️ O convite abre a caixa dos DOIS lados.
    #
    # Sem isto so quem escreve o comando via a caixa, e o outro nunca saberia
    # que havia uma troca a decorrer — mandaria ofertas para o vazio.
    def receber_convite(packet)
      # ⚠️ O ACEITE VOLTA PELO MESMO TIPO DE PACOTE.
      #
      # Quem aceita responde com um "troca_convite" que traz "resposta" => true.
      # Sem esta linha, quem convidou recebia isso como um convite NOVO — e por
      # isso aparecia "o Gaby quer trocar contigo" logo a seguir a cancelar.
      # Agora tambem serve de sinal para a espera de quem convidou.
      if packet["resposta"]
        # So conta se for de quem eu convidei — dois convites ao mesmo tempo
        # nao se podem responder um ao outro.
        de_resp = (packet["sender_id"] || packet["internal_id"]).to_s
        @convite_aceite = true if @parceiro_id.to_s == de_resp
        return
      end
      return if @aberta
      de   = packet["sender_id"].to_s
      nome = packet["nome"].to_s
      return if de.empty?
      # Uma pergunta so. Antes eram duas caixas seguidas — "o X quer trocar" e
      # logo a seguir "aceitar?" — e a primeira nao dizia nada que a segunda
      # nao dissesse.
      if pbConfirmMessage(_INTL("{1} quer trocar com você. Aceita?", nome))
        AnilLanRework.connection.send_packet("troca_convite",
          "to_id" => de, "nome" => ($player.name.to_s rescue ""), "resposta" => true) rescue nil
        abrir(de, nome)
      else
        AnilLanRework.connection.send_packet("troca_cancel", "to_id" => de) rescue nil
      end
    end

    # ⚠️ QUEM CONVIDA ESPERA — a caixa so abre depois do aceite.
    #
    # Antes eu abria a caixa logo ao enviar o convite. O outro ainda estava a
    # ler a pergunta e eu ja estava a olhar para uma mesa vazia sem saber se ele
    # tinha recebido, recusado, ou fechado o jogo. E se recusasse, a minha caixa
    # so fechava quando o troca_cancel chegasse.
    #
    # @convite_aceite: nil = ainda nada, true = aceitou, false = recusou.
    attr_accessor :convite_aceite

    # Verdadeiro quando fomos NOS a desistir, e nao o outro a recusar. So serve
    # para a mensagem: "cancelaste" e "ele nao aceitou" sao coisas diferentes.
    attr_reader :convite_cancelado

    def esperar_aceite(nome, segundos = 30.0)
      @convite_aceite = nil
      @convite_cancelado = false
      vp = Viewport.new(0, 0, Graphics.width, Graphics.height)
      vp.z = 99999
      # A dica vai na faixa: o X ja cancelava, mas nada no ecra o dizia — uma
      # tecla que nao se anuncia e como se nao existisse.
      texto = _INTL("Aguardando resposta de {1}...", nome) + "\n" + _INTL("(X para cancelar)")
      faixa = (AnilLanRework::WaitBanner.new(vp, texto) rescue nil)
      fim = System.uptime + segundos
      begin
        loop do
          Graphics.update
          Input.update
          bombear_rede!
          (faixa.update rescue nil) if faixa
          break unless @convite_aceite.nil?
          break if System.uptime >= fim
          break unless AnilLanRework.connected?
          # O X e lido DEPOIS da resposta: se ela chegou neste frame, ganha.
          # Cancelar um convite ja aceite deixava os dois lados a discordar.
          if Input.trigger?(Input::BACK)
            @convite_aceite = false
            @convite_cancelado = true
            # ⚠️ AVISA-SE O OUTRO LADO, mesmo sabendo que ele nao o vai ver ja.
            #
            # Ele esta parado num pbConfirmMessage, que bloqueia o cliente dele
            # — o pacote fica na fila. Mas assim que ele responder "sim" e a
            # caixa de troca abrir, o bombear_rede! processa este troca_cancel e
            # a caixa fecha-se sozinha. Sem isto ele ficava numa troca sozinho,
            # a mandar ofertas para ninguem.
            if @parceiro_id && !@parceiro_id.to_s.empty?
              AnilLanRework.connection.send_packet("troca_cancel", "to_id" => @parceiro_id.to_s) rescue nil
            end
            break
          end
        end
      ensure
        (faixa.dispose rescue nil) if faixa
        (vp.dispose rescue nil) unless vp.disposed?
      end
      @convite_aceite == true
    end

    # Entrada pelo menu de interacao (MOD 065): ja se tem o peer na mao, nao ha
    # nome nenhum para procurar.
    def convidar_peer(peer)
      return pbMessage(_INTL("Você precisa estar conectado.")) unless AnilLanRework.connected?
      return if peer.nil?
      pid = peer.internal_id.to_s
      return pbMessage(_INTL("Nao consegui identificar esse jogador.")) if pid.empty?
      AnilLanRework.connection.send_packet("troca_convite",
        "to_id" => pid, "nome" => ($player.name.to_s rescue ""))
      @parceiro_id = pid.to_s   # ja da para receber a resposta
      aceite = esperar_aceite(peer.name.to_s)
      @parceiro_id = nil
      unless aceite
        if convite_cancelado
          pbMessage(_INTL("Você cancelou o convite de troca."))
        else
          pbMessage(_INTL("{1} não aceitou a troca.", peer.name.to_s))
        end
        return
      end
      abrir(pid, peer.name.to_s)
    end

    # ⚠️ O id do jogador e a CHAVE do hash, nao um campo do peer.
    # Mesma procura do /tp: nome exacto primeiro, pedaco do nome depois, e
    # avisa-se quando ha varios em vez de escolher um a sorte.
    def convidar(nome)
      return pbMessage(_INTL("Você precisa estar conectado.")) unless AnilLanRework.connected?
      alvo = nome.to_s.strip.downcase
      return pbMessage(_INTL("Usa: /troca <nome>")) if alvo.empty?
      achados = []
      (AnilLanRework.players || {}).each do |id, p|
        next unless p
        n = p.name.to_s.downcase
        achados << [id, p] if !n.empty? && n == alvo
      end
      if achados.empty?
        (AnilLanRework.players || {}).each do |id, p|
          next unless p
          n = p.name.to_s.downcase
          achados << [id, p] if !n.empty? && n.include?(alvo)
        end
      end
      return pbMessage(_INTL("Nao encontrei ninguem chamado {1}.", nome)) if achados.empty?
      return pbMessage(_INTL("Ha mais do que um jogador com esse nome."))  if achados.length > 1
      pid, peer = achados.first
      AnilLanRework.connection.send_packet("troca_convite",
        "to_id" => pid.to_s, "nome" => (($player.name.to_s rescue "") ))
      @parceiro_id = pid.to_s   # ja da para receber a resposta
      aceite = esperar_aceite(peer.name.to_s)
      @parceiro_id = nil
      unless aceite
        if convite_cancelado
          pbMessage(_INTL("Você cancelou o convite de troca."))
        else
          pbMessage(_INTL("{1} não aceitou a troca.", peer.name.to_s))
        end
        return
      end
      abrir(pid.to_s, peer.name.to_s)
    end
  end
end

#===============================================================================
# /troca <nome> — so para o teste
#===============================================================================
module AnilLanRework
  module Chat
    class << self
      alias anil_troca_orig_send_message send_message unless method_defined?(:anil_troca_orig_send_message)

      def send_message(text)
        t = text.to_s.strip
        if t =~ %r{\A/troca(?:\s+(.+))?\z}i
          nome = $1.to_s.strip
          if nome.empty?
            pbMessage(_INTL("Usa: /troca <nome>"))
          else
            AnilTrocaCompleta.convidar(nome)
          end
          return
        end
        anil_troca_orig_send_message(text)
      end
    end
  end
end

#===============================================================================
# Faixa que sobrevive ao fecho da caixa
#===============================================================================
# ⚠️ Nao pode viver na cena da troca: ela fecha e leva o viewport consigo.
#
# Fica aqui, com viewport proprio, e e o Scene_Map#update que a mantem viva e a
# manda embora. O jogador anda enquanto ela esta no ecra — nao ha laco nenhum a
# prender o jogo, que era o que uma caixa de dialogo faria.
module AnilTrocaAviso
  SEGUNDOS = 3.0

  class << self
    def mostrar(texto)
      apagar!
      @vp = Viewport.new(0, 0, Graphics.width, Graphics.height)
      @vp.z = 99998
      @faixa = AnilLanRework::WaitBanner.new(@vp, texto)
      @ate   = System.uptime + SEGUNDOS
    rescue => e
      (AnilTrocaCompleta.log("faixa falhou: #{e.class}: #{e.message}") rescue nil)
      apagar!
    end

    def actualizar
      return if @ate.nil?
      resta = @ate - System.uptime
      if resta <= 0
        apagar!
        return
      end
      @faixa.update rescue nil if @faixa && !(@faixa.disposed? rescue true)
    rescue
      apagar!
    end

    def apagar!
      (@faixa.dispose rescue nil) if @faixa
      (@vp.dispose rescue nil) if @vp && !@vp.disposed?
      @faixa = nil
      @vp    = nil
      @ate   = nil
    end
  end
end

class Scene_Map
  alias anil_troca_aviso_update update unless method_defined?(:anil_troca_aviso_update)

  def update
    anil_troca_aviso_update
    AnilTrocaAviso.actualizar rescue nil
  end
end
