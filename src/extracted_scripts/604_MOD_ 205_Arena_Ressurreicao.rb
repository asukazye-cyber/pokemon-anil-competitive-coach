# encoding: utf-8
#===============================================================================
# CAIR SEM MORRER: A RESSURREICAO NA MASMORRA
#
# Quem cai na caverna com outro jogador la dentro deixa de sair logo. Fica
# caido no sitio, a bambear, durante ESPERA segundos. Um parceiro com um Max
# Revive chega-se a ele, carrega na tecla de accao, e ele levanta-se com a vida
# cheia. Se ninguem chegar a tempo, cai como sempre caiu — perde o que trazia e
# sai.
#
# ⚠️ O PACOTE NOVO NAO PRECISA DE MEXER NO SERVIDOR, E CONFIRMEI-O ANTES.
#
# Era este o risco a serio desta funcionalidade: o servidor e um deploy a parte,
# e um tipo de pacote que ele nao conheca cai no vazio. Fui ver o despacho do
# `server_runtime` e ele tem um `else` final que reencaminha o que nao conhece
# pelo `map_id` do pacote. O `falar!` da caverna poe sempre o `map_id`. E por
# isso que o `caverna_mob` e o `caverna_dono` ja funcionam sem uma unica linha
# de servidor a falar deles — e e por isso que estes tambem funcionam.
#
# ⚠️ E A REGRA DE OURO: A VIDA DE CADA UM E DECIDIDA PELA MAQUINA DELE.
#
# A tentacao e o revivedor mandar "tu estas vivo com a vida cheia". Isso e
# autoridade dupla, e este projecto ja pagou por ela uma vez (a troca que se
# fazia sem esperar o servidor, e que deu duplicacao). Aqui:
#
#   quem cai      anuncia que caiu, e e o UNICO que decide quando se levanta
#   quem revive   manda um PEDIDO, e gasta o item quando o pedido e aceite
#
# O pior que pode acontecer e um Max Revive gasto sem ninguem se levantar — e
# isso e melhor do que um jogador vivo numa maquina e caido noutra.
#===============================================================================
module AnilArenaRessurreicao
  # ⚠️ DOIS ITENS, E A DIFERENCA ENTRE ELES E A MESMA DO JOGO.
  #
  # O Max Revive levanta com a vida cheia; o Revive levanta com metade. Aceitar
  # so o Max Revive obrigava a guardar o item raro para uma coisa que o comum ja
  # faz — e o jogador tinha o Revive na mochila a ver o parceiro cair.
  #
  # A ordem importa: procura-se primeiro o MAIS FRACO. Assim gasta-se o Revive
  # enquanto houver, e o Max Revive fica para quando nao houver mais nada. Ao
  # contrario, o jogo escolhia sempre o melhor item que se tem, que e a decisao
  # que ninguem quer que lhe tomem.
  ITENS = [
    [:REVIVE,    0.5],
    [:MAXREVIVE, 1.0]
  ].freeze

  # O que ainda se chama `ITEM` por fora: o melhor caso, para as mensagens.
  ITEM = :MAXREVIVE

  # ⚠️ Trinta segundos: chega para atravessar uma sala, e nao chega para a
  # masmorra deixar de doer. Um numero grande transformava a queda num
  # inconveniente; um pequeno tornava o socorro impossivel e o item inutil.
  ESPERA = 30.0

  # Casas. Pede-se encostado — a uma casa e meia ja se perdoa a diagonal e o
  # meio-passo de quem vem a andar.
  ALCANCE = 1.5

  # O bambear: um balanco lento, nao um tremor. (E sim, ja aprendi neste
  # projecto que tremer nao e mover.)
  RITMO  = 4.5
  ANGULO = 13.0

  class << self
    attr_accessor :caidos    # id do jogador => { :x, :y, :nome, :visto }
  end
  @caidos = {}

  def self.limpar!
    @caidos = {}
    @companhia_vista = nil
    @notado = 0.0
  end

  def self.meu_id
    (AnilLanRework.self_internal_id.to_s rescue "")
  rescue
    ""
  end

  # ⚠️ So vale a pena ficar caido se houver alguem que possa vir.
  #
  # Sozinho, isto eram trinta segundos a olhar para o chao antes de perder as
  # coisas na mesma. Sem companhia, cai-se como sempre se caiu.
  # ⚠️ A LISTA DE JOGADORES ESVAZIA-SE, E EU ESTAVA A DECIDIR POR ELA.
  #
  # O registo da derrota apanhou isto ao fim de uma noite de jogo:
  #
  #     18:58:54  DERROTA: companhia=true  ligado=true  gente=1  mapa=307
  #     19:00:27  DERROTA: companhia=false ligado=true  gente=0  mapa=308
  #
  # `gente=0` nao e "o parceiro esta noutro mapa" — e a lista INTEIRA vazia,
  # com a ligacao de pe. O proprio HUD de grupo tem a explicacao escrita no 000:
  # "ao trocar de mapa o HUD desaparecia por completo, porque o peer era apagado
  # da lista (ver route_packet, `player_disconnect` com map_change)". Ou seja,
  # entre o parceiro sair de um mapa e reaparecer no outro ha uma janela em que,
  # para este codigo, nao esta la ninguem.
  #
  # Cair nessa janela custa a masmorra inteira: em vez de trinta segundos a
  # espera de socorro, perde-se tudo e sai-se. E um preco alto para pagar por um
  # pacote de rede que estava a caminho.
  #
  # A pergunta passa a ter memoria curta. A lista manda enquanto tiver alguem;
  # nao tendo, vale o ultimo instante em que teve. Doze segundos e mais do que o
  # suficiente para uma mudanca de mapa e pouco de mais para segurar quem foi
  # mesmo embora — e quem ficar a espera sem ninguem cai na mesma, so que trinta
  # segundos mais tarde.
  MEMORIA_COMPANHIA = 12.0

  def self.peer_no_meu_mapa?
    return false unless (AnilLanRework.connected? rescue false)
    return false unless $game_map
    meu = meu_id
    (AnilLanRework.players || {}).any? do |id, peer|
      next false if id.to_s == meu
      next false unless peer
      (peer.map_id.to_i rescue -1) == $game_map.map_id.to_i
    end
  rescue
    false
  end

  # Corre no relogio da arena, uma vez por segundo. E o que da memoria a
  # pergunta de cima — sem isto ela so sabe o instante em que e feita, e o
  # instante em que ela e feita e precisamente o pior de todos.
  def self.notar_companhia!
    agora = Time.now.to_f
    return if (agora - @notado.to_f) < 1.0
    @notado = agora
    @companhia_vista = agora if peer_no_meu_mapa?
  rescue
    nil
  end

  def self.ha_companhia?
    return true if peer_no_meu_mapa?
    return false if @companhia_vista.nil?
    (Time.now.to_f - @companhia_vista.to_f) <= MEMORIA_COMPANHIA
  rescue
    false
  end

  # Para o registo da derrota: quem esta na lista e em que mapa. E a linha que
  # diz se a lista estava vazia ou so com gente noutro sitio.
  def self.retrato_da_gente
    meu = meu_id
    fora = []
    (AnilLanRework.players || {}).each do |id, peer|
      next if id.to_s == meu
      next unless peer
      fora << "#{(peer.name rescue '?')}@#{(peer.map_id rescue '?')}"
    end
    idade = @companhia_vista ? (Time.now.to_f - @companhia_vista.to_f).round(1) : nil
    "[#{fora.join(' ')}]" + (idade ? " visto_ha=#{idade}s" : " nunca_visto")
  rescue
    "[?]"
  end

  # Devolve [item, fraccao] do mais fraco que eu tenha, ou nil.
  def self.item_para_reviver
    return nil unless $bag
    ITENS.each do |(id, fraccao)|
      next unless (GameData::Item.exists?(id) rescue false)
      return [id, fraccao] if ($bag.has?(id) rescue false)
    end
    nil
  rescue
    nil
  end

  def self.tenho_o_item?
    !item_para_reviver.nil?
  rescue
    false
  end

  #-----------------------------------------------------------------------------
  # O QUE SE DIZ AOS OUTROS
  #-----------------------------------------------------------------------------
  def self.anunciar_queda!
    (AnilRaidCaverna.falar!("caverna_caido", {
      "quem" => meu_id,
      "nome" => (AnilLanRework.self_name.to_s rescue ""),
      "x"    => ($game_player ? $game_player.x : 0),
      "y"    => ($game_player ? $game_player.y : 0)
    }) rescue nil)
  end

  def self.anunciar_levantado!
    (AnilRaidCaverna.falar!("caverna_levantado", { "quem" => meu_id }) rescue nil)
  end

  # O PEDIDO. Nao diz "estas vivo"; diz "tenho um Max Revive para ti".
  # ⚠️ A FRACCAO VIAJA NO PEDIDO, e nao e decidida por quem se levanta.
  #
  # Quem gasta o item e quem sabe qual gastou. Deixar o outro lado decidir
  # obrigava-o a adivinhar — e um Revive teria de levantar com a vida cheia
  # porque o caido nao sabia que nao era um Max.
  def self.pedir_ressurreicao!(alvo, fraccao = 1.0)
    (AnilRaidCaverna.falar!("caverna_revive", {
      "quem"    => meu_id,
      "nome"    => (AnilLanRework.self_name.to_s rescue ""),
      "alvo"    => alvo.to_s,
      "fraccao" => fraccao.to_f
    }) rescue nil)
  end

  #-----------------------------------------------------------------------------
  # O QUE CHEGA DOS OUTROS
  #-----------------------------------------------------------------------------
  def self.receber_caido!(p)
    id = p["quem"].to_s
    return if id.empty? || id == meu_id
    @caidos ||= {}
    @caidos[id] = {
      :x     => p["x"].to_i,
      :y     => p["y"].to_i,
      :nome  => p["nome"].to_s,
      :visto => Time.now.to_f
    }
    nome = p["nome"].to_s
    nome = "Um parceiro" if nome.empty?
    (AnilLanRework.add_corner_popup(
      "#{nome} caiu! Chegue perto e carregue em C com um Revive.", 8.0) rescue nil)
  rescue
    nil
  end

  def self.receber_levantado!(p)
    id = p["quem"].to_s
    (@caidos || {}).delete(id)
  rescue
    nil
  end

  # ⚠️ CHEGA UM PEDIDO: SO O PROPRIO E QUE O ACEITA.
  #
  # Confirma-se que o alvo sou eu e que estou mesmo caido. Um pedido que chegue
  # atrasado — o parceiro carregou no botao no mesmo instante em que o tempo se
  # esgotou — nao ressuscita ninguem, e e assim que deve ser.
  def self.receber_pedido!(p)
    return unless p["alvo"].to_s == meu_id
    fr = (p["fraccao"] || 1.0).to_f
    fr = 1.0 if fr <= 0.0 || fr > 1.0
    (AnilArena.aceitar_ressurreicao!(p["nome"].to_s, fr) rescue nil)
  rescue
    nil
  end

  #-----------------------------------------------------------------------------
  # QUEM ESTA AO MEU ALCANCE
  #
  # Devolve [id, ficha] do caido mais proximo dentro do ALCANCE, ou nil.
  #-----------------------------------------------------------------------------
  def self.caido_ao_alcance
    return nil unless $game_player
    lista = (@caidos || {})
    return nil if lista.empty?
    agora = Time.now.to_f
    melhor = nil
    melhor_d = nil
    lista.each do |id, f|
      # ⚠️ As fichas caducam sozinhas.
      #
      # Um parceiro que feche o jogo a meio nunca manda o "levantado", e sem
      # isto ficava um fantasma reviveil no mapa para sempre. O prazo e o da
      # espera mais uma folga para o atraso da rede.
      next if (agora - f[:visto].to_f) > (ESPERA + 5.0)
      dx = f[:x].to_i - $game_player.x
      dy = f[:y].to_i - $game_player.y
      d = Math.sqrt((dx * dx) + (dy * dy))
      next if d > ALCANCE
      if melhor_d.nil? || d < melhor_d
        melhor_d = d
        melhor = [id, f]
      end
    end
    melhor
  rescue
    nil
  end

  def self.esquecer_velhos!
    agora = Time.now.to_f
    (@caidos || {}).delete_if { |_, f| (agora - f[:visto].to_f) > (ESPERA + 5.0) }
  rescue
    nil
  end
end
