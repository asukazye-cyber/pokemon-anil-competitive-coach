#===============================================================================
# MOD: 182_Chat_Historico.rb
#-------------------------------------------------------------------------------
# As mensagens do chat aparecem no rodape e desaparecem passados uns segundos.
# Quem estava a andar, a lutar ou de costas para o ecra perdia-as e nao tinha
# como as ir buscar.
#
# Este MOD guarda as ultimas mensagens durante 5 minutos e mostra-as enquanto o
# jogador SEGURAR o T.
#
# ⚠️ POR QUE E QUE O CHAT PASSA A ABRIR NO LARGAR DO T.
#
# O T ja abria o chat, e abria no `triggerex?` — ou seja, no instante em que a
# tecla desce. Com isso nao ha maneira nenhuma de distinguir um toque de um
# "segurar": quando se percebesse que o jogador estava a segurar, o chat ja
# tinha aberto.
#
# Entao o T passa a decidir-se no LARGAR:
#   largou antes do LIMIAR  -> foi um toque   -> abre o chat
#   passou do LIMIAR        -> esta a segurar -> mostra o historico
#
# Um toque normal larga-se em ~0,1s, portanto na pratica o chat abre na mesma.
# E quem nao quiser esperar nada continua a ter o ENTER, que abre na descida.
#
# ⚠️ NO ANDROID NAO HA T. Quem joga no JoiPlay sem teclado nao chega aqui — o
# historico fica a espera de um botao tocavel, que e outro trabalho.
#===============================================================================

module AnilChatHistorico
  TTL        = 300.0   # 5 minutos
  MAX_LINHAS = 60      # tecto de memoria
  LIMIAR     = 0.35    # segundos a segurar antes de ser "segurar"

  MARGEM        = 12
  ALTURA_TITULO = 26
  LINHA_H       = 19

  @linhas   = []
  @premido  = false
  @desde    = 0.0
  @aberto   = false
  @pedir    = false
  @pedir_em = 0.0
  @viewport = nil
  @sprite   = nil
  @chave    = nil

  module_function

  def agora
    Time.now.to_f
  end

  # ── memoria ────────────────────────────────────────────────────────────────
  def registar(texto)
    t = texto.to_s.strip
    return if t.empty?
    @linhas << { :texto => t, :em => agora }
    @linhas.shift while @linhas.length > MAX_LINHAS
  rescue
  end

  def vivas
    limite = agora - TTL
    @linhas.select { |l| l[:em] >= limite }
  rescue
    []
  end

  def limpar_velhas!
    limite = agora - TTL
    @linhas.delete_if { |l| l[:em] < limite }
  rescue
  end

  # ── o T ────────────────────────────────────────────────────────────────────
  def pode_agora?
    return false unless $scene.is_a?(Scene_Map)
    return false if $game_temp && $game_temp.respond_to?(:in_battle) && $game_temp.in_battle
    return false if $game_temp && $game_temp.respond_to?(:message_window_showing) && $game_temp.message_window_showing
    return false if defined?(AnilLanRework::ChatInputHUD) && (AnilLanRework::ChatInputHUD.active? rescue false)
    true
  rescue
    false
  end

  def actualizar!
    limpar_velhas!

    # Um pedido de abrir o chat que ninguem foi buscar em 0,2s ja nao serve:
    # quer dizer que o frame do largar caiu num sitio onde o Scene_Map nao le o
    # T (um menu a abrir, o interpretador a correr). Deitar fora evita o chat
    # abrir sozinho meio segundo depois, do nada.
    @pedir = false if @pedir && (agora - @pedir_em) > 0.2

    unless pode_agora?
      esconder! if @aberto
      @premido = false
      return
    end

    premido = (Input.pressex?(:T) rescue false)

    if premido && !@premido
      @premido = true
      @desde   = agora
    elsif premido && @premido
      mostrar! if !@aberto && (agora - @desde) >= LIMIAR
    elsif !premido && @premido
      @premido = false
      if @aberto
        esconder!
      elsif (agora - @desde) < LIMIAR
        @pedir    = true
        @pedir_em = agora
      end
    end

    desenhar! if @aberto
  rescue => e
    (AnilLanRework.log("historico de chat: #{e.class}: #{e.message}") rescue nil)
  end

  def aberto?
    @aberto == true
  end

  # Lido pelo Scene_Map em vez do triggerex?(:T).
  def pedir_abrir_chat?
    return false unless @pedir
    @pedir = false
    true
  end

  # ── o painel ───────────────────────────────────────────────────────────────
  def mostrar!
    return if @aberto
    @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 999998
    @sprite = Sprite.new(@viewport)
    @sprite.z = 100002
    @aberto = true
    @chave  = nil
    # Limpa o rodape e o canto: dai para a frente e tudo dentro do painel.
    (AnilLanRework.limpar_popups_de_chat! rescue nil)
    (pbSEPlay("GUI menu open") rescue nil)
    desenhar!
  rescue
    @aberto = false
  end

  def esconder!
    @sprite&.bitmap&.dispose rescue nil
    @sprite&.dispose rescue nil
    @sprite = nil
    @viewport&.dispose rescue nil
    @viewport = nil
    @aberto = false
    @chave  = nil
  rescue
  end

  def cor_de(texto)
    return Color.new(170, 170, 170) if texto.start_with?("[Sistema]")
    return Color.new(120, 255, 120) if texto.include?(" entrou")
    return Color.new(255, 120, 120) if texto.include?(" saiu")
    return Color.new(120, 210, 255) if texto.start_with?("[Global]")
    return Color.new(140, 255, 180) if texto.start_with?("[Grupo]")
    return Color.new(255, 170, 255) if texto.start_with?("[De:") || texto.start_with?("[Para")
    Color.new(255, 255, 255)
  end

  def desenhar!
    return unless @sprite && !(@sprite.disposed? rescue true)

    registos = vivas
    chave = registos.map { |l| l[:em] }.join(",") + "|" + registos.length.to_s
    return if chave == @chave
    @chave = chave

    w = Graphics.width - (MARGEM * 2)
    h = Graphics.height - 60

    @sprite.bitmap&.dispose rescue nil
    @sprite.bitmap = Bitmap.new(w, h)
    @sprite.x = MARGEM
    @sprite.y = 30

    fonte = (MessageConfig::FONT_NAME rescue (Font.default_name rescue "Arial"))

    @sprite.bitmap.fill_rect(0, 0, w, h, Color.new(0, 0, 0, 205)) rescue nil
    @sprite.bitmap.fill_rect(0, 0, 3, h, Color.new(52, 152, 219)) rescue nil
    @sprite.bitmap.fill_rect(0, ALTURA_TITULO - 1, w, 1, Color.new(52, 152, 219, 160)) rescue nil

    begin
      @sprite.bitmap.font.name  = fonte
      @sprite.bitmap.font.size  = 16
      @sprite.bitmap.font.bold  = true
      @sprite.bitmap.font.color = Color.new(120, 210, 255)
      @sprite.bitmap.draw_text(10, 3, w - 20, 20, _INTL("Histórico do chat"), 0)
      @sprite.bitmap.font.bold  = false
      @sprite.bitmap.font.color = Color.new(160, 160, 160)
      @sprite.bitmap.draw_text(10, 3, w - 20, 20, _INTL("solta o T para fechar"), 2)
    rescue
    end

    if registos.empty?
      begin
        @sprite.bitmap.font.size  = 16
        @sprite.bitmap.font.color = Color.new(150, 150, 150)
        @sprite.bitmap.draw_text(12, ALTURA_TITULO + 8, w - 24, 20,
                                 _INTL("Ainda não há mensagens."), 0)
      rescue
      end
      return
    end

    # Mede com a fonte do corpo, quebra, e vai enchendo DE BAIXO PARA CIMA: a
    # mensagem mais recente fica sempre visivel, aconteca o que acontecer.
    medidor = Bitmap.new(8, 8)
    begin
      medidor.font.name = fonte
      medidor.font.size = 16
    rescue
    end

    cabem = [(h - ALTURA_TITULO - 10) / LINHA_H, 1].max
    prontas = []

    registos.reverse_each do |reg|
      partes = (AnilLanRework.quebrar_texto(reg[:texto], medidor, w - 26, 4) rescue [reg[:texto]])
      cor    = cor_de(reg[:texto])
      partes.reverse_each do |p|
        break if prontas.length >= cabem
        prontas.unshift([p, cor])
      end
      break if prontas.length >= cabem
    end
    medidor.dispose rescue nil

    begin
      @sprite.bitmap.font.size = 16
      @sprite.bitmap.font.bold = false
    rescue
    end

    base = h - 6 - (prontas.length * LINHA_H)
    prontas.each_with_index do |par, i|
      linha, cor = par
      ly = base + (i * LINHA_H)
      begin
        @sprite.bitmap.font.color = Color.new(0, 0, 0, 200)
        @sprite.bitmap.draw_text(13, ly + 1, w - 26, LINHA_H, linha, 0)
        @sprite.bitmap.font.color = cor
        @sprite.bitmap.draw_text(12, ly, w - 26, LINHA_H, linha, 0)
      rescue
      end
    end
  rescue => e
    (AnilLanRework.log("historico de chat (desenhar): #{e.class}: #{e.message}") rescue nil)
  end
end

#-------------------------------------------------------------------------------
# Tudo o que aparece no rodape passa pelo add_corner_popup — chat, sussurros,
# avisos de sistema e os "entrou"/"saiu". Um gancho so apanha tudo.
#-------------------------------------------------------------------------------
module AnilLanRework
  class << self
    unless method_defined?(:anil_hist_add_corner_popup) ||
           private_method_defined?(:anil_hist_add_corner_popup)
      alias anil_hist_add_corner_popup add_corner_popup

      # ⚠️ COM O PAINEL ABERTO, O POPUP NAO CHEGA A NASCER.
      #
      # O painel vive num viewport de z 999998 e os popups no de 999999, ou
      # seja, eles desenham-se POR CIMA dele. Mesmo que nao desenhassem, a
      # mensagem apareceria duas vezes: uma no historico e outra no rodape.
      #
      # Enquanto o T estiver a segurar, a mensagem entra so no historico — que
      # ja se redesenha sozinho quando a lista muda. Ao largar o T, o chat volta
      # ao normal e as mensagens seguintes voltam a aparecer no rodape.
      def add_corner_popup(text, duration = 4.0)
        AnilChatHistorico.registar(text) rescue nil
        return if (AnilChatHistorico.aberto? rescue false)
        anil_hist_add_corner_popup(text, duration)
      end
    end
  end
end

#-------------------------------------------------------------------------------
# O painel tem de ser lido todos os frames, mesmo com o interpretador a correr
# ou o jogador parado num evento — senao o T ficava preso a "segurar".
#-------------------------------------------------------------------------------
class Scene_Map
  alias anil_hist_update update unless method_defined?(:anil_hist_update)

  def update
    anil_hist_update
    AnilChatHistorico.actualizar! rescue nil
  end
end

(AnilLanRework.log("182_Chat_Historico carregado") rescue nil)
