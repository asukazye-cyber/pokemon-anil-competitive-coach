# encoding: UTF-8
#===============================================================================
# MOD: 166_Perfume_Sweet_Scent
#-------------------------------------------------------------------------------
# O Sweet Scent ganha um segundo uso: em vez de chamar uma batalha na hora,
# deixa-se o perfume no ar. Enquanto durar, o Pokemon da cadeia aparece muito
# mais, e o jogador anda a largar petalas.
#
# ⚠️ NAO SE MEXE NA TAXA DE SHINY. NEM UM BOCADINHO.
#
# As probabilidades sobem porque o bicho APARECE mais vezes, e cada aparicao e um
# sorteio — nao porque cada sorteio fique mais generoso. Isto e deliberado: ja
# houve aqui tres sorteios de shiny a somar-se por OU, e a taxa saiu ao dobro sem
# ninguem dar por isso. O perfume mexe no QUE nasce, nunca no COMO nasce.
#
# ⚠️ SO SAI O QUE A ROTA JA DAVA.
#
# Em vez de escolher a especie a mao, pede-se ao jogo que escolha outra vez, ate
# quatro vezes, ate calhar a da cadeia. Se ela nao estiver na tabela daquele
# sitio, nunca sai — e por isso um lendario ou um Pokemon de outra rota nao pode
# aparecer por causa disto. A regra "so Pokemon normais, de rota" fica garantida
# pela propria construcao, sem lista de excepcoes para manter.
#
# ⚠️ O CLASSICO FICA.
#
# Quem quiser a batalha imediata continua a te-la: ao usar o golpe pergunta-se
# qual dos dois. O `pbSweetScent` do motor nao e tocado.
#
# ⚠️ AS PETALAS NAO VEM DE NENHUM FICHEIRO.
#
# Ha folhas de animacao com petalas (`PRAS- Petal Dance.png`), mas sao celulas de
# 192x192 de arte de ecra inteiro — recortar uma petala dali era adivinhar. Sao
# desenhadas por codigo, uma vez, num bitmap de 7x7 partilhado por todas.
#===============================================================================

module AnilPerfume
  ACTIVO = true

  # ⚠️ OS PASSOS VEM DO NIVEL DE QUEM USA.
  #
  # Dez por nivel: um de 50 da 500 passos. Assim o golpe acompanha a equipa em
  # vez de valer sempre o mesmo, e da uma razao para levar um Pokemon crescido
  # em vez do primeiro que souber o golpe.
  PASSOS_POR_NIVEL = 10
  # Piso, para um Pokemon de nivel 3 nao dar um perfume que acaba a meio do ecra.
  PASSOS_MINIMO = 100

  # Quantas vezes se volta a sortear a procura da especie da cadeia. Com quatro,
  # uma especie que valha 20% da tabela passa a sair ~59% das vezes.
  TENTATIVAS = 4

  # Quantas petalas andam no ar ao mesmo tempo.
  PETALAS = 8

  class << self
    def log(t)
      AnilLanRework.log("[PERFUME] #{t}") rescue nil
    end

    def agora
      System.uptime
    rescue
      Time.now.to_f
    end

    # --------------------------------------------------------------- o estado
    def passos
      ($PokemonGlobal.anil_perfume_passos.to_i rescue 0)
    end

    def activo?
      ACTIVO && passos > 0
    end

    def passos_de(pkmn)
      n = ((pkmn.level rescue 1).to_i * PASSOS_POR_NIVEL)
      n < PASSOS_MINIMO ? PASSOS_MINIMO : n
    rescue
      PASSOS_MINIMO
    end

    def ligar!(n)
      $PokemonGlobal.anil_perfume_passos = n.to_i
      log("perfume ligado por #{n} passos (cadeia: #{especie_da_cadeia.inspect})")
    rescue
      nil
    end

    def desligar!
      $PokemonGlobal.anil_perfume_passos = 0
    rescue
      nil
    end

    def gastar_passo!
      return unless activo?
      n = passos - 1
      $PokemonGlobal.anil_perfume_passos = n
      if n <= 0
        # ⚠️ Um som antes da caixa: o jogador pode estar a andar distraido e a
        # mensagem sozinha passa despercebida no meio do passo.
        (pbSEPlay("Battle ball drop") rescue nil)
        pbMessage(_INTL("O perfume dissipou-se. Os Pokemon voltaram ao normal.")) rescue nil
        log("perfume esgotado")
      end
    rescue
      nil
    end

    # ⚠️ Le-se a cadeia em cada spawn, e nao se guarda a especie ao activar.
    #
    # Assim o perfume acompanha a caca: se o jogador mudar de alvo a meio, o
    # efeito segue-o sem ter de o desligar e ligar outra vez.
    def especie_da_cadeia
      c = ($PokemonGlobal.catchcombo rescue nil)
      return nil unless c.is_a?(Array) && c.length >= 2
      return nil if c[0].to_i <= 0
      e = c[1]
      (e.nil? || e == 0) ? nil : e
    rescue
      nil
    end
  end
end

class PokemonGlobalMetadata
  # Passos que faltam ao perfume. 0 ou nil = desligado.
  attr_accessor :anil_perfume_passos
end

#-------------------------------------------------------------------------------
# O uso, num sitio so — o menu da party e o golpe de campo chamam o mesmo.
#-------------------------------------------------------------------------------
module AnilPerfume
  class << self
    # ⚠️ O NOME VEM DO GOLPE, E NAO DE UM LITERAL.
    #
    # A entrada do menu dizia `_INTL("Sweet Scent")`. O _INTL traduz FRASES da
    # interface; os nomes dos golpes vivem noutro sitio — passam pelo
    # pbGetMessageFromHash(MOVE_NAMES), que e quem respeita a opcao "ataques
    # traduzidos" do jogador. Por isso a entrada ficava em ingles mesmo para
    # quem tinha escolhido portugues, e nao havia como o _INTL saber disso.
    #
    # Pedindo o nome ao proprio golpe, ele chega ja no idioma certo — e se um
    # dia a traducao mudar, esta entrada acompanha sem se lhe tocar.
    def nome_do_golpe
      n = (GameData::Move.get(:SWEETSCENT).name rescue nil)
      (n.nil? || n.to_s.empty?) ? "Sweet Scent" : n.to_s
    rescue
      "Sweet Scent"
    end

    def sabe_o_golpe?(pkmn)
      return false unless pkmn
      return false if (pkmn.egg? rescue true)
      (pkmn.moves.any? { |m| m && m.id == :SWEETSCENT } rescue false)
    rescue
      false
    end

    # ------------------------------------------------------ pedido diferido
    def pedir_uso(pkmn)
      return false unless pkmn
      @pendente = pkmn
      @fechar_menu = true
      @fechar_pausa = true
      true
    rescue
      false
    end

    def ha_pedido?
      !@pendente.nil?
    end

    # ⚠️ As bandeiras so valem se HOUVER mesmo um pedido.
    #
    # Sem esta guarda, uma bandeira esquecida fechava um menu que nada tinha a
    # ver com o perfume.
    def consumir_fechar_menu?
      return false unless @fechar_menu
      @fechar_menu = false
      ha_pedido?
    end

    def consumir_fechar_pausa?
      return false unless @fechar_pausa
      @fechar_pausa = false
      ha_pedido?
    end

    # Chamado do Scene_Map, ja com os menus fora do caminho.
    def correr_pedido!
      return unless @pendente
      return unless ($scene.is_a?(Scene_Map) rescue false)
      return if ($game_temp && $game_temp.message_window_showing rescue false)
      pkmn = @pendente
      @pendente = nil
      usar!(pkmn)
    rescue
      @pendente = nil
    end

    # ⚠️ O USO CLASSICO SAIU.
    #
    # O Sweet Scent chamava uma batalha na hora (`pbSweetScent`). Agora o golpe
    # faz uma coisa so: deixa o perfume. A pergunta de "qual dos dois" desapareceu
    # com ele — nao vale a pena uma caixa de escolha com uma opcao.
    #
    # O `pbSweetScent` do motor continua intacto para quem o chamar por script.
    # ⚠️ SEM A INTRODUCAO DO GOLPE DE CAMPO.
    #
    # O `pbHiddenMoveAnimation` faz a apresentacao completa — a bola a sair, o
    # Pokemon a aparecer no ecra, a faixa com o nome. Para um golpe que se usa
    # muitas vezes seguidas isso e uma cerimonia a mais.
    #
    # Fica so o essencial: o jogador vira-se para o companheiro, toca o som do
    # proprio golpe, e as petalas aparecem.
    def usar!(pkmn, _com_animacao = true)
      virar_para_o_companheiro
      (pbSEPlay("PRSFX- Sweet Scent") rescue pbSEPlay("Pkmn healing") rescue nil)
      ligar!(passos_de(pkmn))
      alvo = especie_da_cadeia
      if alvo
        nome = (GameData::Species.get(alvo).name rescue alvo.to_s)
        pbMessage(_INTL("{1} espalhou um perfume doce. {2} deve aparecer com mais frequencia!",
                        pkmn.name, nome))
      else
        # ⚠️ Dizer que nao ha cadeia, em vez de gastar o golpe em silencio.
        pbMessage(_INTL("{1} espalhou um perfume doce... mas nao andas a perseguir nenhum Pokemon.",
                        pkmn.name))
      end
      true
    rescue => e
      log("falha ao usar: #{e.class}: #{e.message}")
      false
    end

    # ⚠️ So se ele estiver mesmo no mapa.
    #
    # O companheiro so existe como evento se for o follower. Se o jogador usou o
    # golpe com outro Pokemon da equipa, nao ha para onde virar — e nesse caso
    # nao se mexe no boneco, em vez de o rodar para um sitio qualquer.
    def virar_para_o_companheiro
      return unless defined?(FollowingPkmn)
      return unless (FollowingPkmn.can_check? rescue false)
      ev = (FollowingPkmn.get_event rescue nil)
      return unless ev
      (pbTurnTowardEvent($game_player, ev) rescue nil)
    rescue
      nil
    end
  end
end

#-------------------------------------------------------------------------------
# ⚠️ ENTRADA PROPRIA NO MENU DA PARTY.
#
# O jogo tem `SHOW_HMS_IN_PARTY_MENU = false`: os golpes de campo NAO aparecem
# na party, aqui. Ligar esse interruptor mostrava-os todos, em todos os Pokemon —
# mudava o menu do jogo inteiro por causa de um golpe.
#
# Entao poe-se uma entrada so nossa, com a mesma mecanica do "Montar": aparece
# apenas em quem sabe mesmo o Sweet Scent.
#-------------------------------------------------------------------------------
if defined?(MenuHandlers)
  MenuHandlers.add(:party_menu, :anil_perfume, {
    "name"      => proc { AnilPerfume.nome_do_golpe },
    "order"     => 16,
    "condition" => proc { |_screen, party, party_idx|
      next AnilPerfume::ACTIVO && AnilPerfume.sabe_o_golpe?(party[party_idx])
    },
    "effect"    => proc { |_screen, party, party_idx|
      # ⚠️ AQUI SO SE PEDE. QUEM USA E O MAPA.
      #
      # Chamar o pbEndScene de dentro do efeito nao chega: o ciclo de comandos da
      # party continua a correr por cima de uma cena ja desmontada, e foi
      # exactamente assim que o menu ficou preso quando se fez o "Montar". O
      # caminho que resulta e o mesmo que o 160 usa — levantar uma bandeira e
      # deixar os ecras sairem pela porta deles.
      AnilPerfume.pedir_uso(party[party_idx])
      next true
    }
  })
end

#-------------------------------------------------------------------------------
# E o golpe de campo, para quem chegar por outro caminho (o Ready Menu).
#-------------------------------------------------------------------------------
if defined?(HiddenMoveHandlers)
  HiddenMoveHandlers::UseMove.add(:SWEETSCENT, proc { |_move, pokemon|
    next AnilPerfume.usar!(pokemon)
  })
end

#-------------------------------------------------------------------------------
# Gastar um passo por cada passo do jogador.
#-------------------------------------------------------------------------------
if defined?(EventHandlers)
  EventHandlers.add(:on_step_taken, :anil_perfume, proc { |event|
    next unless AnilPerfume::ACTIVO
    next unless defined?($game_player) && $game_player && event == $game_player
    AnilPerfume.gastar_passo!
  })
end

#-------------------------------------------------------------------------------
# O que nasce.
#-------------------------------------------------------------------------------
if defined?(PokemonEncounters)
  class PokemonEncounters
    unless method_defined?(:anil_perfume_orig_choose_wild_pokemon)
      alias_method :anil_perfume_orig_choose_wild_pokemon, :choose_wild_pokemon

      # ⚠️ VOLTA A SORTEAR, EM VEZ DE ESCOLHER A MAO.
      #
      # Escolher a especie directamente obrigava a perceber o formato da tabela
      # de encontros e a inventar um nivel — e abria a porta a fazer nascer o que
      # aquele sitio nao da. Assim so pode sair o que ja podia sair, com o nivel
      # que a propria tabela decide.
      def choose_wild_pokemon(enc_type, chance_rolls = 1)
        ret = anil_perfume_orig_choose_wild_pokemon(enc_type, chance_rolls)
        return ret unless AnilPerfume.activo?
        alvo = AnilPerfume.especie_da_cadeia
        return ret unless alvo
        return ret if ret.is_a?(Array) && ret[0].to_s == alvo.to_s
        AnilPerfume::TENTATIVAS.times do
          outro = anil_perfume_orig_choose_wild_pokemon(enc_type, chance_rolls)
          return outro if outro.is_a?(Array) && outro[0].to_s == alvo.to_s
        end
        ret
      rescue
        anil_perfume_orig_choose_wild_pokemon(enc_type, chance_rolls)
      end
    end
  end
end

#-------------------------------------------------------------------------------
# As petalas.
#-------------------------------------------------------------------------------
module AnilPetalas
  # ⚠️ AS PETALAS SAO FICHEIROS, E NAO DESENHO POR CODIGO.
  #
  # A primeira versao desenhava um losango de 7x7 a mao porque as folhas de
  # animacao do jogo sao celulas de 192x192 de arte de ecra inteiro. Agora ha
  # arte propria: quatro petalas recortadas e reduzidas para 12 px.
  PASTA = "Graphics/Pictures/anil_petala_"
  QUANTAS = 4

  @bitmaps = nil

  class << self
    # Carregadas uma vez e partilhadas por todos os sprites. Nunca se libertam
    # aqui: quem as usa so guarda a referencia.
    def bitmaps
      return @bitmaps if @bitmaps && @bitmaps.all? { |b| b && !(b.disposed? rescue true) }
      lista = []
      QUANTAS.times do |i|
        cam = (pbResolveBitmap(PASTA + (i + 1).to_s) rescue nil)
        next unless cam
        b = (Bitmap.new(cam) rescue nil)
        lista << b if b
      end
      @bitmaps = lista.empty? ? nil : lista
    rescue
      nil
    end

    def largar!
      (@bitmaps || []).each { |b| b.dispose if b && !(b.disposed? rescue true) }
      @bitmaps = nil
    rescue
      @bitmaps = nil
    end
  end
end

#-------------------------------------------------------------------------------
# O anel de petalas, e as que se soltam dele.
#
# ⚠️ DUAS COISAS DIFERENTES, E NAO UMA DEFORMADA.
#
# A versao anterior fazia o anel inteiro ficar para tras ao andar — o circulo
# esticava-se e lia-se como um erro, nao como um rasto. Agora sao dois grupos:
#
#   o ANEL   gira colado ao jogador, sempre redondo, sem atraso nenhum;
#   as SOLTAS sao petalas que se desprenderam e ficaram no mapa a flutuar.
#
# A andar, o anel larga uma petala de vez em quando. Como as soltas ficam presas
# ao MAPA e o jogador segue caminho, elas ficam para tras sozinhas — nao e
# preciso empurra-las para lado nenhum.
#
# ⚠️ A METADE DA FRENTE PASSA A FRENTE. A DE TRAS, ATRAS.
#
# O sprite do jogador usa `screen_z(@ch)`, que soma 31 quando o charset tem mais
# de 32 px de altura. As petalas estavam em `screen_y +- 1` e por isso ficavam
# SEMPRE por baixo dele — o giro nunca passava a frente.
#
# Agora usa-se o proprio `screen_z`, com folga suficiente para valer em qualquer
# charset: a frente vai acima do maximo que o jogador pode ter, e as costas
# abaixo do minimo.
#-------------------------------------------------------------------------------
class AnilAnelDePetalas
  # Quantas giram a volta.
  QUANTAS = 10
  # Raio da orbita, em pixeis, e quanto ele respira.
  RAIO      = 20.0
  RESPIRA   = 3.0
  # Achatamento: 1.0 seria um circulo de pe; abaixo disso le-se como perspectiva.
  ACHATA    = 0.45
  # Onde fica o centro, a contar dos PES (negativo sobe): altura da cintura.
  ALTURA    = -14
  # De quantos em quantos frames a andar se larga uma petala.
  CADENCIA  = 7
  # Tecto das soltas. Sem isto, correr durante um minuto enchia o mapa.
  MAX_SOLTAS = 24

  # ⚠️ O ANEL TEM DONO, E O DONO PODE SER OUTRO JOGADOR.
  #
  # Antes lia o `$game_player` directamente e por isso so podia haver um anel,
  # o do proprio. As petalas nao apareciam a mais ninguem — quem usava o golpe
  # via o efeito sozinho, o que para um golpe que se usa em grupo e meio golpe.
  #
  # O `dono` so precisa de saber dizer onde esta e se anda: `screen_x`,
  # `screen_y`, `screen_z` e `moving?`. O `$game_player` tem isso, e o
  # RemotePeer do multiplayer tambem — de proposito, para os dois servirem sem
  # nenhum caso especial aqui dentro.
  def initialize(viewport, dono = nil)
    @dono = dono
    @viewport = viewport
    @anel = []
    @estado = []
    @soltas = []
    @t = 0.0
    @desde_larga = 0
    @disposed = false
  end

  def disposed?; @disposed; end

  def dispose
    return if @disposed
    @anel.each { |s| s.dispose if s && !(s.disposed? rescue true) }
    @soltas.each { |o| o[:sprite].dispose if o[:sprite] && !(o[:sprite].disposed? rescue true) }
    @anel = []
    @soltas = []
    @estado = []
    @disposed = true
  rescue
    @disposed = true
  end

  def dono
    @dono || $game_player
  end

  def update
    return if @disposed
    d = dono
    unless d && $game_map && (@dono ? true : (AnilPerfume.activo? rescue false))
      esconder
      return
    end
    bmps = AnilPetalas.bitmaps
    return unless bmps && !bmps.empty?

    @t += 1.0
    dx = $game_map.display_x / Game_Map::X_SUBPIXELS.to_f
    dy = $game_map.display_y / Game_Map::Y_SUBPIXELS.to_f
    cx = d.screen_x
    cy = d.screen_y + ALTURA

    # ⚠️ Folga generosa: o `screen_z(64)` e o maximo que o jogador pode ter
    # (ground + 31) e o `screen_z(0)` o minimo. Ficar entre os dois nao chegava.
    z_frente = (d.screen_z(64) rescue d.screen_y) + 8
    z_tras   = (d.screen_z(0)  rescue d.screen_y) - 8

    vx = Math.sin(@t * 0.013) * 3.0
    vy = Math.cos(@t * 0.009) * 1.5

    andar = (d.moving? rescue false)
    @desde_larga += 1

    QUANTAS.times do |i|
      e = (@estado[i] ||= nascer(i, bmps.length))
      s = @anel[i]
      if s.nil? || (s.disposed? rescue true)
        s = @anel[i] = Sprite.new(@viewport)
        vestir(s, bmps, e)
      end

      e[:t] += 1
      ang = e[:ang] + (e[:t] * e[:vel])
      raio = RAIO + (Math.sin((@t * 0.02) + i) * RESPIRA) + e[:dr]
      frente = Math.sin(ang) >= 0

      s.x = (cx + (Math.cos(ang) * raio) + vx).round
      s.y = (cy + (Math.sin(ang) * raio * ACHATA) + vy).round
      s.z = frente ? z_frente : z_tras
      s.angle = (e[:giro] + (e[:t] * e[:vgiro])) % 360
      s.opacity = opacidade(e)
      s.visible = true

      # ⚠️ Larga-se a que esta A FRENTE e ja bem visivel.
      #
      # Soltar uma da metade de tras fazia-a aparecer de tras do boneco, o que se
      # le como um erro de desenho. E uma quase transparente desaparecia sem se
      # ver que se soltou.
      if andar && @desde_larga >= CADENCIA && frente && s.opacity > 150 &&
         @soltas.length < MAX_SOLTAS
        @desde_larga = 0
        soltar(s.x + dx, s.y + dy, bmps, e)
        @estado[i] = nascer(i, bmps.length)
        vestir(s, bmps, @estado[i])
      elsif e[:t] >= e[:vida]
        @estado[i] = nascer(i, bmps.length)
        vestir(s, bmps, @estado[i])
      end
    end

    actualizar_soltas(dx, dy, z_frente)
  rescue
    nil
  end

  private

  # ------------------------------------------------------------- as soltas
  # ⚠️ Guardadas em coordenadas do MAPA.
  #
  # E o que as faz ficar para tras sem ninguem as empurrar: elas ficam onde
  # foram largadas e e o jogador que se afasta. Em coordenadas de ecra teriam de
  # ser empurradas a mao contra o movimento da camara, e qualquer diferenca
  # entre as duas velocidades notava-se logo.
  def soltar(mx, my, bmps, e)
    s = Sprite.new(@viewport)
    s.bitmap = bmps[e[:arte] % bmps.length]
    s.ox = s.bitmap.width / 2
    s.oy = s.bitmap.height / 2
    @soltas << {
      :sprite => s,
      :x => mx, :y => my,
      # deriva lenta, como as estrelas dos shiny
      :vx => (rand(11) - 5) / 12.0,
      :vy => -0.10 - (rand(20) / 100.0),
      :bal_v => (rand(20) + 10) / 300.0,
      :bal_a => (rand(10) + 5) / 10.0,
      :t => 0,
      :vida => 70 + rand(50),
      :giro => e[:giro],
      :vgiro => (rand(5) - 2) * 0.7,
      :forca => e[:forca]
    }
  rescue
    nil
  end

  def actualizar_soltas(dx, dy, z)
    @soltas.reject! do |o|
      s = o[:sprite]
      if s.nil? || (s.disposed? rescue true)
        next true
      end
      o[:t] += 1
      if o[:t] >= o[:vida]
        s.dispose
        next true
      end
      o[:x] += o[:vx] + (Math.sin(o[:t] * o[:bal_v]) * o[:bal_a])
      o[:y] += o[:vy]
      s.x = (o[:x] - dx).round
      s.y = (o[:y] - dy).round
      s.z = z
      s.angle = (o[:giro] + (o[:t] * o[:vgiro])) % 360
      # some devagar, do inicio ao fim
      v = ((o[:vida] - o[:t]) * 255) / [o[:vida], 1].max
      s.opacity = (v * o[:forca]) / 100
      s.visible = true
      false
    end
  rescue
    nil
  end

  # ------------------------------------------------------------------ o anel
  def vestir(s, bmps, e)
    s.bitmap = bmps[e[:arte] % bmps.length]
    s.ox = s.bitmap.width / 2
    s.oy = s.bitmap.height / 2
  rescue
    nil
  end

  # Aparece e desaparece devagar nas duas pontas: so desvanecer no fim dava
  # petalas a SURGIR do nada, que se nota muito mais.
  def opacidade(e)
    entra = e[:vida] / 5
    sai   = e[:vida] / 3
    v = if e[:t] < entra
          (e[:t] * 255) / [entra, 1].max
        elsif e[:t] > (e[:vida] - sai)
          ((e[:vida] - e[:t]) * 255) / [sai, 1].max
        else
          255
        end
    v = 0 if v < 0
    v = 255 if v > 255
    (v * e[:forca]) / 100
  end

  def nascer(i, n_artes)
    {
      :t     => 0,
      :vida  => 90 + rand(70),
      :ang   => ((Math::PI * 2) * i / QUANTAS) + (rand(60) / 100.0),
      :vel   => 0.010 + (rand(8) / 1000.0),
      :dr    => rand(7) - 3,
      :giro  => rand(360),
      :vgiro => (rand(3) - 1) * 0.6,
      :arte  => rand(n_artes),
      :forca => 55 + rand(45)
    }
  end

  def esconder
    @anel.each { |s| s.visible = false if s && !(s.disposed? rescue true) }
    @soltas.each { |o| o[:sprite].dispose if o[:sprite] && !(o[:sprite].disposed? rescue true) }
    @soltas = []
  rescue
    nil
  end
end

#-------------------------------------------------------------------------------
# ⚠️ O anel e actualizado UMA vez por frame, no Scene_Map.
#
# Podia viver no Sprite_Character do jogador, mas esse update corre para TODOS os
# sprites do mapa e e o caminho quente que ja nos custou caro. Aqui corre uma vez,
# e so quando o perfume esta ligado.
#-------------------------------------------------------------------------------
module AnilPerfume
  class << self
    def instalar!
      return false unless ACTIVO
      return false unless defined?(Scene_Map)
      return false if Scene_Map.method_defined?(:anil_perfume_orig_update)
      Scene_Map.class_eval do
        alias_method :anil_perfume_orig_update, :update

        def update(*a)
          ret = anil_perfume_orig_update(*a)
          AnilPerfume.actualizar_petalas(self)
          ret
        end
      end
      instalar_saidas!
      log("enxerto instalado no Scene_Map")
      true
    rescue => e
      log("falha a instalar: #{e.class}: #{e.message}")
      false
    end

    # ⚠️ AS DUAS PORTAS POR ONDE OS MENUS SAEM.
    #
    # A da party e o retorno do pbChoosePokemon: devolver -1 fecha-a como se o
    # jogador tivesse carregado em B. A do menu de pausa e o @done do
    # DP_PauseMenu — este jogo nao usa o menu do motor, usa o do plugin, que tem
    # um ciclo proprio e sai por essa bandeira.
    def instalar_saidas!
      if defined?(PokemonParty_Scene) &&
         !PokemonParty_Scene.method_defined?(:anil_perfume_orig_pbChoosePokemon)
        PokemonParty_Scene.class_eval do
          alias_method :anil_perfume_orig_pbChoosePokemon, :pbChoosePokemon

          def pbChoosePokemon(*args)
            return -1 if AnilPerfume.consumir_fechar_menu?
            anil_perfume_orig_pbChoosePokemon(*args)
          end
        end
      end
      if defined?(DP_PauseMenu) && !DP_PauseMenu.method_defined?(:anil_perfume_orig_update)
        DP_PauseMenu.class_eval do
          alias_method :anil_perfume_orig_update, :update

          def update
            anil_perfume_orig_update
            @done = true if AnilPerfume.consumir_fechar_pausa?
          rescue
            nil
          end
        end
      end
    rescue => e
      log("falha nas saidas: #{e.class}: #{e.message}")
    end

    # Quantos aneis de OUTROS jogadores se desenham ao mesmo tempo. Cada um
    # sao 10 sprites a girar mais as que se soltam; num mapa cheio de gente com
    # o golpe isto multiplicava-se depressa, e o telemovel e que pagava.
    MAX_ANEIS_REMOTOS = 3

    # ⚠️ UM ANEL POR DONO, E NAO UM ANEL SO.
    #
    # Guardam-se por chave: `:eu` para o proprio, e o id interno para cada
    # jogador remoto. Assim quem entra no mapa ganha o seu, quem sai perde o
    # dele, e ninguem herda as petalas de outro.
    def actualizar_petalas(cena)
      correr_pedido!
      @aneis ||= {}
      vp = (Spriteset_Map.viewport rescue nil)
      if vp.nil?
        largar_aneis!
        return
      end

      vivos = {}
      vivos[:eu] = $game_player if activo? && defined?($game_player) && $game_player
      donos_remotos.each { |id, peer| vivos[id] = peer }

      # fora os que ja nao tem dono
      @aneis.keys.each do |k|
        next if vivos.key?(k)
        (@aneis[k].dispose rescue nil)
        @aneis.delete(k)
      end

      vivos.each do |k, dono|
        anel = @aneis[k]
        if anel.nil? || (anel.disposed? rescue true)
          anel = @aneis[k] = AnilAnelDePetalas.new(vp, (k == :eu ? nil : dono))
        end
        anel.update
      end
    rescue
      nil
    end

    # ⚠️ So quem esta no MEU mapa e com o perfume ligado.
    #
    # O `anil_perfume` vem no pacote de posicao (ver o MOD 000). Clientes
    # antigos nunca o mandam, e ficam simplesmente sem petalas — nao ha nada a
    # negociar nem versao a comparar.
    def donos_remotos
      out = {}
      return out unless defined?(AnilLanRework) && (AnilLanRework.connected? rescue false)
      return out unless $game_map
      meu_mapa = $game_map.map_id.to_i
      n = 0
      (AnilLanRework.players rescue {}).each do |id, peer|
        next unless peer
        next unless (peer.anil_perfume rescue false)
        next unless peer.map_id.to_i == meu_mapa
        out[id.to_s] = peer
        n += 1
        break if n >= MAX_ANEIS_REMOTOS
      end
      out
    rescue
      {}
    end

    def largar_aneis!
      (@aneis || {}).each_value { |a| a.dispose rescue nil }
      @aneis = {}
    rescue
      @aneis = {}
    end
  end
end

module AnilLanRework
  class << self
    unless method_defined?(:anil_perfume_orig_apply_post_plugin_patches)
      alias_method :anil_perfume_orig_apply_post_plugin_patches, :apply_post_plugin_patches rescue nil
    end

    def apply_post_plugin_patches
      anil_perfume_orig_apply_post_plugin_patches rescue nil
      AnilPerfume.instalar! rescue nil
    end
  end
end

AnilLanRework.log("166_Perfume_Sweet_Scent carregado") rescue nil
