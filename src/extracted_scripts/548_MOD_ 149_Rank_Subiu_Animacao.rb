# encoding: UTF-8
#===============================================================================
# MOD: 149_Rank_Subiu_Animacao
#-------------------------------------------------------------------------------
# Quando o jogador SOBE de rank, o emblema aparece por cima do boneco, brilha,
# pulsa e vira o emblema seguinte. Com musica e um aviso no canto.
#
# QUANDO DISPARA
#
# So na SUBIDA, e so quando o degrau muda de verdade — nao a cada ponto ganho.
# O degrau aqui inclui a divisao: passar de "Treinador C" para "Treinador B"
# conta, porque para o jogador aquilo e uma promocao visivel (a letra debaixo do
# escudo muda). Quando so o rotulo muda de divisao, o escudo e o mesmo e a
# animacao troca apenas a letra.
#
# ⚠️ O ESTADO ANTERIOR VEM DO SERVIDOR, NAO DO SAVE.
#
# Guardar "o meu ultimo rank" no save deixaria a animacao a merce de um save
# adulterado — e ja houve injeccao por debug neste projecto. Aqui compara-se
# apenas o que o servidor mandou ANTES com o que ele mandou AGORA, dentro da
# mesma sessao. O custo e que uma subida ocorrida offline nao anima; em troca,
# ninguem consegue disparar isto a vontade.
#
# ONDE APARECE
#
# Por cima do jogador no mapa, nao numa tela propria: e o momento de outra
# pessoa ver acontecer. Se a cena atual nao for o mapa, a animacao e ADIADA
# ate voltar — mesma razao pela qual o aviso de pontos e adiado (ver MOD 147).
#===============================================================================

module AnilRankSubiu
  # Duracao de cada fase, em frames (40 frames ~ 1s).
  #
  # ⚠️ A primeira versao durava menos de 2 segundos no total e o jogador nao
  # tinha tempo de ver nada. Agora sao ~6 segundos, com uma pausa no fim para o
  # emblema novo ficar parado a ser apreciado.
  FRAMES_SUBIDA = 30     # aparece e sobe ate ao lugar
  FRAMES_CARGA  = 55     # pulsa e vai carregando de luz
  FRAMES_TROCA  = 22     # o clarao onde a imagem troca
  FRAMES_POUSO  = 45     # o novo assenta, a luz sai, a letra entra
  FRAMES_PAUSA  = 55     # parado, so a brilhar de leve
  FRAMES_SAIDA  = 26

  # Altura acima do boneco. E a MESMA ancora dos baloes de ocupado
  # (000_Multiplayer_Online: `sprite.y = remote_sprite.y - 49`), para o emblema
  # nascer onde o jogador ja esta habituado a ver avisos por cima da cabeca.
  ALTURA = 49

  # Onde a letra da divisao assenta DENTRO do escudo (canto inferior esquerdo),
  # em relacao ao canto superior esquerdo do emblema de 60x48.
  LETRA_DX = 16
  LETRA_DY = 28

  # A musica. Cai para o jingle de insignia se o ficheiro proprio nao existir —
  # um cliente sem o audio novo nao pode ficar sem som nenhum.
  MUSICA     = "Rank Up"
  MUSICA_ALT = "Jingle badge"

  module_function

  def pasta_emblema(tier)
    nome = (AnilCartaoRank::EMBLEMAS[tier.to_i] rescue nil)
    return nil unless nome
    caminho = "Graphics/UI/Trainer Card/rank/" + nome
    (pbResolveBitmap(caminho) rescue nil) ? caminho : nil
  rescue
    nil
  end

  def caminho_divisao(letra)
    # Segue a mesma chave do cartao: com ela desligada, a animacao tambem nao
    # desenha letra nenhuma — o escudo troca sozinho.
    return nil unless (AnilCartaoRank::MOSTRAR_DIVISAO rescue false)
    return nil if letra.to_s.empty?
    caminho = "Graphics/UI/Trainer Card/rank/divisao_" + letra.to_s.downcase
    (pbResolveBitmap(caminho) rescue nil) ? caminho : nil
  rescue
    nil
  end

  # "Lider B" -> "B". Sem divisao (Elite 4, Campeao) -> "".
  def divisao_do_rotulo(rotulo)
    r = rotulo.to_s.strip
    return "" if r.length < 3
    ultima = r[-1, 1].to_s.upcase
    return "" unless %w[A B C].include?(ultima)
    return "" unless r[-2, 1] == " "
    ultima
  rescue
    ""
  end

  # ---------------------------------------------------------------------------
  # DECIDE SE HOUVE PROMOCAO
  #
  # Recebe o estado antigo e o novo, ambos vindos do servidor. Devolve nil se
  # nada mudou para cima.
  # ---------------------------------------------------------------------------
  def promocao(antes, depois)
    return nil unless antes.is_a?(Hash) && depois.is_a?(Hash)
    t_antes  = antes["tier"].to_i
    t_depois = depois["tier"].to_i
    d_antes  = divisao_do_rotulo(antes["rank"])
    d_depois = divisao_do_rotulo(depois["rank"])

    # Subiu de faixa (Treinador -> Desafiante, etc.)
    return { tier_antes: t_antes, tier_depois: t_depois,
             div_antes: d_antes, div_depois: d_depois } if t_depois > t_antes

    # Mesma faixa, divisao melhor. C -> B -> A, entao "menor na ordem alfabetica
    # e melhor": comparar as letras ao contrario.
    if t_depois == t_antes && !d_antes.empty? && !d_depois.empty? && d_depois < d_antes
      return { tier_antes: t_antes, tier_depois: t_depois,
               div_antes: d_antes, div_depois: d_depois }
    end
    nil
  rescue
    nil
  end

  # ---------------------------------------------------------------------------
  # O AGENDAMENTO
  #
  # Chamado pelo MOD 147 sempre que chega um estado novo. Nunca toca no ecra
  # aqui: so guarda. Quem desenha e o Scene_Map, quando o mapa estiver a andar.
  # ---------------------------------------------------------------------------
  def agendar(antes, depois)
    p = promocao(antes, depois)
    return unless p
    @pendente = p.merge(rotulo: depois["rank"].to_s)
    registar("promocao agendada: #{antes['rank']} -> #{depois['rank']}")
  rescue
  end

  def pendente?; !@pendente.nil?; end

  def registar(texto)
    AnilEstatisticasMP.diag("[RANK_SUBIU] #{texto}") if defined?(AnilEstatisticasMP)
  rescue
  end

  def pronto_para_animar?
    return false unless @pendente
    return false unless $scene.is_a?(Scene_Map)
    return false if $game_temp && ($game_temp.in_battle || $game_temp.message_window_showing)
    return false if $game_player && $game_player.moving?
    true
  rescue
    false
  end

  def escoar!
    return unless pronto_para_animar?
    p = @pendente
    @pendente = nil
    tocar!(p)
  rescue => e
    @pendente = nil
    registar("falha ao animar: #{e.class}: #{e.message}")
  end

  def tocar_musica
    [MUSICA, MUSICA_ALT].each do |m|
      begin
        pbSEPlay(m, 90)
        return
      rescue
        next
      end
    end
  rescue
  end

  # ---------------------------------------------------------------------------
  # A ANIMACAO
  #
  # Tres fases: o escudo antigo cresce e clareia, um estouro branco esconde a
  # troca, e o novo assenta. A troca DENTRO do estouro e o truque todo — sem
  # ele via-se a imagem mudar de repente, que e o que estraga o efeito.
  # ---------------------------------------------------------------------------
  def tocar!(p)
    velho = pasta_emblema(p[:tier_antes])
    novo  = pasta_emblema(p[:tier_depois])
    return unless novo

    viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    viewport.z = 99_998
    halo   = Sprite.new(viewport)   # copia ampliada por tras = o brilho
    escudo = Sprite.new(viewport)
    letra  = Sprite.new(viewport)
    clarao = Sprite.new(viewport)

    trocar_escudo = lambda do |caminho|
      bmp = pbBitmap(caminho)
      [escudo, halo].each do |s|
        s.bitmap = bmp
        s.ox = bmp.width / 2
        s.oy = bmp.height      # ancorado em BAIXO, como o balao de ocupado
      end
    end
    trocar_letra = lambda do |letraTxt|
      cam = caminho_divisao(letraTxt)
      if cam
        letra.bitmap = pbBitmap(cam)
        letra.ox = 0
        letra.oy = 0
      else
        letra.bitmap = nil
      end
    end

    trocar_escudo.call(velho || novo)
    trocar_letra.call(p[:div_antes])
    halo.z = -1
    halo.opacity = 0

    clarao.bitmap = Bitmap.new(Graphics.width, Graphics.height)
    clarao.bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(255, 255, 255))
    clarao.opacity = 0
    clarao.z = 10

    tocar_musica

    # Segue o boneco: se ele andar, o emblema acompanha.
    subida = 0.0
    posicionar = lambda do
      x = ($game_player.screen_x rescue Graphics.width / 2)
      y = ($game_player.screen_y rescue Graphics.height / 2) - ALTURA + subida
      escudo.x = halo.x = x
      escudo.y = halo.y = y
      # A letra segue o escudo, respeitando o zoom actual.
      if letra.bitmap
        z = escudo.zoom_x
        larg = escudo.bitmap.width * z
        alt  = escudo.bitmap.height * z
        letra.x = x - (larg / 2) + (LETRA_DX * z)
        letra.y = y - alt + (LETRA_DY * z)
        letra.zoom_x = letra.zoom_y = z
      end
    end

    begin
      # ---------------------------------------------------------------------
      # 1. Aparece e sobe ate ao lugar.
      # ---------------------------------------------------------------------
      FRAMES_SUBIDA.times do |i|
        t = i.to_f / FRAMES_SUBIDA
        subida = 14 * (1.0 - t) ** 2
        escudo.opacity = (255 * [t * 1.6, 1.0].min).to_i
        letra.opacity = escudo.opacity
        escudo.zoom_x = escudo.zoom_y = 0.6 + 0.4 * t
        posicionar.call
        Graphics.update
        Input.update
      end
      subida = 0.0

      # ---------------------------------------------------------------------
      # 2. Carrega. AQUI ESTA O BRILHO QUE FALTAVA.
      #
      # ⚠️ Zoom sozinho nao e brilho. A primeira versao so pulsava, e o
      # jogador via o escudo "respirar" sem nunca acender. Sao tres coisas
      # juntas: o sprite.color a branquear a propria imagem, um halo por tras
      # (a mesma imagem ampliada e transparente) e o clarao de ecra inteiro.
      # ---------------------------------------------------------------------
      FRAMES_CARGA.times do |i|
        t = i.to_f / FRAMES_CARGA
        pulso = Math.sin(t * Math::PI * 4)
        escudo.zoom_x = escudo.zoom_y = 1.0 + 0.10 * pulso * t
        escudo.color = Color.new(255, 255, 255, (170 * t).to_i)
        halo.opacity = (110 * t).to_i
        halo.zoom_x = halo.zoom_y = escudo.zoom_x * (1.25 + 0.15 * t)
        halo.color = Color.new(255, 250, 200, 255)
        clarao.opacity = (70 * t * t).to_i
        posicionar.call
        Graphics.update
        Input.update
      end

      # ---------------------------------------------------------------------
      # 3. O clarao. A imagem troca no pico, escondida pelo branco.
      # ---------------------------------------------------------------------
      meio = FRAMES_TROCA / 2
      FRAMES_TROCA.times do |i|
        t = i.to_f / FRAMES_TROCA
        clarao.opacity = i <= meio ? (70 + 185 * (i.to_f / meio)).to_i
                                   : (255 * (1.0 - (i - meio).to_f / meio)).to_i
        if i == meio
          trocar_escudo.call(novo)
          trocar_letra.call(p[:div_depois])
          letra.opacity = 0
        end
        posicionar.call
        Graphics.update
        Input.update
      end

      # ---------------------------------------------------------------------
      # 4. O novo assenta: a luz sai de cima dele e a letra entra.
      # ---------------------------------------------------------------------
      FRAMES_POUSO.times do |i|
        t = i.to_f / FRAMES_POUSO
        escudo.zoom_x = escudo.zoom_y = 1.35 - 0.35 * t + 0.06 * Math.sin(t * Math::PI * 3)
        escudo.color = Color.new(255, 255, 255, (200 * (1.0 - t)).to_i)
        halo.opacity = (150 * (1.0 - t)).to_i
        halo.zoom_x = halo.zoom_y = escudo.zoom_x * 1.3
        clarao.opacity = 0
        escudo.opacity = 255
        letra.opacity = (255 * [t * 1.5, 1.0].min).to_i
        posicionar.call
        Graphics.update
        Input.update
      end

      # ---------------------------------------------------------------------
      # 5. Fica parado a ser visto, com um brilho lento a respirar.
      # ---------------------------------------------------------------------
      escudo.color = Color.new(255, 255, 255, 0)
      FRAMES_PAUSA.times do |i|
        t = i.to_f / FRAMES_PAUSA
        respirar = (Math.sin(t * Math::PI * 2) + 1.0) / 2.0
        escudo.zoom_x = escudo.zoom_y = 1.0 + 0.03 * respirar
        halo.opacity = (40 * respirar).to_i
        halo.zoom_x = halo.zoom_y = escudo.zoom_x * 1.22
        posicionar.call
        Graphics.update
        Input.update
      end

      # ---------------------------------------------------------------------
      # 6. Sai.
      # ---------------------------------------------------------------------
      FRAMES_SAIDA.times do |i|
        t = i.to_f / FRAMES_SAIDA
        subida = -10 * t
        escudo.opacity = (255 * (1.0 - t)).to_i
        letra.opacity = escudo.opacity
        halo.opacity = (40 * (1.0 - t)).to_i
        posicionar.call
        Graphics.update
        Input.update
      end
    ensure
      escudo.dispose rescue nil
      halo.dispose rescue nil
      letra.dispose rescue nil
      clarao.bitmap.dispose rescue nil
      clarao.dispose rescue nil
      viewport.dispose rescue nil
    end

    # O aviso no canto — so para o proprio jogador, como pedido.
    AnilLanRework.add_popup(_INTL("Voce subiu para {1}!", p[:rotulo]), 5.0) rescue nil
    registar("animacao concluida: #{p[:rotulo]}")
  end

  def instalar!
    return if @instalado
    @instalado = true
    if defined?(Scene_Map)
      Scene_Map.class_eval do
        unless method_defined?(:anil_ranksubiu_orig_update)
          alias_method :anil_ranksubiu_orig_update, :update

          def update(*args)
            anil_ranksubiu_orig_update(*args)
            AnilRankSubiu.escoar! if defined?(AnilRankSubiu) && AnilRankSubiu.pendente?
          end
        end
      end
    end
    AnilLanRework.log("149_Rank_Subiu_Animacao instalado") rescue nil
  rescue => e
    AnilLanRework.log("[RANK_SUBIU] falha ao instalar: #{e.class}: #{e.message}") rescue nil
  end
end

if defined?(AnilLanRework)
  module AnilLanRework
    class << self
      if !method_defined?(:anil_ranksubiu_orig_apply_post_plugin_patches)
        alias_method :anil_ranksubiu_orig_apply_post_plugin_patches, :apply_post_plugin_patches rescue nil
      end

      def apply_post_plugin_patches
        anil_ranksubiu_orig_apply_post_plugin_patches if respond_to?(:anil_ranksubiu_orig_apply_post_plugin_patches)
        AnilRankSubiu.instalar!
      end
    end
  end
end

AnilLanRework.log("149_Rank_Subiu_Animacao carregado") rescue nil
