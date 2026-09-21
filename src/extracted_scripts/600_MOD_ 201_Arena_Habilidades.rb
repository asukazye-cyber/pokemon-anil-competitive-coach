# encoding: utf-8
#===============================================================================
# HABILIDADES, CLIMA, DRENO E ROUBO NA ARENA
#
# ⚠️ PORQUE UM FICHEIRO A PARTE.
#
# O `189_Arena_Acao.rb` tem treze mil linhas e ja e o sitio onde cada engano de
# `sub!` custa uma ronda. Isto e materia nova e bem delimitada — tabelas e
# regras de efeito — e vive melhor sozinha. O 189 so ganha quatro linhas de
# chamada, nos quatro pontos onde o dano passa.
#
# ⚠️ O QUE ESTA AQUI E O QUE A MEDICAO DISSE SER BARATO.
#
# Das 328 habilidades do PBS, a analise apontou quatro familias que nao exigem
# conceitos novos:
#
#     imunidade a tipo   12   e um teste no calculo de dano
#     contacto           13   a arena ja sabe quem tocou em quem
#     clima              21   o jogo JA tem clima por mapa (MOD 047)
#     item                9   depende do roubo, que esta aqui em baixo
#
# Ficam de fora as que dependem de entrada em campo (switch-in), porque numa
# luta em tempo real ninguem entra nem sai — nao ha momento em que aplicar.
#===============================================================================
module AnilArenaHabilidades
  LIGADO = true

  #-----------------------------------------------------------------------------
  # O CLIMA
  #
  # ⚠️ O JOGO JA TEM CLIMA, E E POR MAPA.
  #
  # O `047_Multiplayer_Dynamic_Weather` calcula-o de forma deterministica a
  # partir da data e do id do mapa, e sincroniza-o entre jogadores. Nao ha nada
  # a inventar: pergunta-se-lhe.
  #
  # Os nomes dele nao sao os das habilidades — ele tem `:Storm` e `:Blizzard`,
  # que o Pokemon nao distingue de `:Rain` e `:Snow`. Traduz-se uma vez.
  #-----------------------------------------------------------------------------
  CHUVA  = [:Rain, :Storm].freeze
  SOL    = [:Sun].freeze
  AREIA  = [:Sandstorm].freeze
  NEVE   = [:Snow, :Blizzard].freeze

  def self.clima
    return :None unless $game_map
    (AnilLanRework.get_weather_for_map($game_map.map_id) rescue :None) || :None
  rescue
    :None
  end

  def self.chove?;  CHUVA.include?(clima); end
  def self.sol?;    SOL.include?(clima);   end
  def self.areia?;  AREIA.include?(clima); end
  def self.neve?;   NEVE.include?(clima);  end

  def self.habilidade(pkmn)
    (pkmn.ability_id.to_s.upcase rescue "")
  rescue
    ""
  end

  #-----------------------------------------------------------------------------
  # IMUNIDADE POR TIPO
  #
  # ⚠️ ESTAS SAO AS MAIS BARATAS DE TODAS E AS QUE MAIS MUDAM UMA LUTA.
  #
  # Um Levitate que continua a levar de Earthquake, ou um Volt Absorb que leva
  # de Thunderbolt, sao erros que qualquer jogador vê de imediato — e sao um
  # `if` no sitio certo. Algumas ate CURAM em vez de magoar, e isso tambem cabe
  # aqui porque o resultado e um numero de dano negativo que quem chama trata.
  #-----------------------------------------------------------------------------
  IMUNE = {
    "LEVITATE"    => [:GROUND, :nada],
    "FLASHFIRE"   => [:FIRE,   :nada],
    "SOUNDPROOF"  => [:NORMAL, :nada],    # aproximacao: o PBS marca o som por flag
    "BULLETPROOF" => [:NORMAL, :nada],    # idem
    "SAPSIPPER"   => [:GRASS,  :nada],
    "MOTORDRIVE"  => [:ELECTRIC, :nada],
    "LIGHTNINGROD" => [:ELECTRIC, :nada],
    "STORMDRAIN"  => [:WATER,  :nada],
    "VOLTABSORB"  => [:ELECTRIC, :cura],
    "WATERABSORB" => [:WATER,  :cura],
    "DRYSKIN"     => [:WATER,  :cura],
    "EARTHEATER"  => [:GROUND, :cura]
  }.freeze

  # Devolve :nada, :cura, ou nil (leva normalmente).
  def self.imunidade(defensor, tipo_do_golpe)
    return nil unless LIGADO && defensor && tipo_do_golpe
    par = IMUNE[habilidade(defensor)]
    return nil unless par
    return nil unless par[0].to_s == tipo_do_golpe.to_s
    par[1]
  rescue
    nil
  end

  #-----------------------------------------------------------------------------
  # O CLIMA NO DANO E NA VELOCIDADE
  #
  # As habilidades de clima dividem-se em duas coisas que a arena sabe fazer:
  # multiplicar dano, e multiplicar velocidade. Nada aqui precisa de turnos.
  #-----------------------------------------------------------------------------
  def self.factor_de_dano(atacante, mv_tipo)
    return 1.0 unless LIGADO && atacante
    f = 1.0
    hab = habilidade(atacante)
    # O clima mexe nos tipos, mesmo sem habilidade nenhuma — e o que faz um dia
    # de chuva ser um dia de chuva.
    if chove?
      f *= 1.30 if mv_tipo.to_s == "WATER"
      f *= 0.70 if mv_tipo.to_s == "FIRE"
    elsif sol?
      f *= 1.30 if mv_tipo.to_s == "FIRE"
      f *= 0.70 if mv_tipo.to_s == "WATER"
    end
    # E depois a habilidade por cima.
    f *= 1.30 if hab == "SOLARPOWER" && sol?
    f *= 1.30 if hab == "SANDFORCE" && areia? &&
                 %w[ROCK GROUND STEEL].include?(mv_tipo.to_s)
    f
  rescue
    1.0
  end

  DOBRA_VELOCIDADE = %w[SWIFTSWIM CHLOROPHYLL SANDRUSH SLUSHRUSH].freeze

  def self.factor_de_velocidade(pkmn)
    return 1.0 unless LIGADO && pkmn
    case habilidade(pkmn)
    when "SWIFTSWIM"   then chove? ? 1.6 : 1.0
    when "CHLOROPHYLL" then sol?   ? 1.6 : 1.0
    when "SANDRUSH"    then areia? ? 1.6 : 1.0
    when "SLUSHRUSH"   then neve?  ? 1.6 : 1.0
    when "QUICKFEET"   then 1.3
    else 1.0
    end
  rescue
    1.0
  end

  # A cura lenta de quem gosta do tempo que esta a fazer. Em fraccao da vida
  # maxima, por segundo — a arena nao tem turnos onde por "1/16 por turno".
  def self.cura_por_segundo(pkmn)
    return 0.0 unless LIGADO && pkmn
    case habilidade(pkmn)
    when "RAINDISH" then chove? ? (1.0 / 16.0) / 3.0 : 0.0
    when "ICEBODY"  then neve?  ? (1.0 / 16.0) / 3.0 : 0.0
    when "DRYSKIN"  then chove? ? (1.0 / 8.0) / 3.0 : (sol? ? -((1.0 / 8.0) / 3.0) : 0.0)
    else 0.0
    end
  rescue
    0.0
  end

  #-----------------------------------------------------------------------------
  # CONTACTO
  #
  # ⚠️ A ARENA JA SABE QUEM TOCOU EM QUEM, E ISSO E METADE DO TRABALHO.
  #
  # O `contacto?(mv)` le a flag `Contact` do PBS e ja e usado para decidir o
  # alcance de um bote. Falta so responder quando o toque acontece.
  #-----------------------------------------------------------------------------
  CONTACTO = {
    "STATIC"       => [:paralisado, 30],
    "FLAMEBODY"    => [:queimado,   30],
    "POISONPOINT"  => [:envenenado, 30],
    "EFFECTSPORE"  => [:envenenado, 20],
    "CUTECHARM"    => [:apaixonado, 30]
  }.freeze

  ESPINHOS = { "ROUGHSKIN" => 8.0, "IRONBARBS" => 8.0 }.freeze

  # Devolve [estado_ou_nil, chance, dano_de_recuo]
  def self.ao_tocar(defensor)
    return [nil, 0, 0.0] unless LIGADO && defensor
    hab = habilidade(defensor)
    est, chance = CONTACTO[hab] || [nil, 0]
    recuo = ESPINHOS[hab] || 0.0
    [est, chance, recuo]
  rescue
    [nil, 0, 0.0]
  end

  #-----------------------------------------------------------------------------
  # DRENO
  #
  # O `function_code` diz tudo: `HealUserByHalfOfDamageDone` e meio, o Draining
  # Kiss e tres quartos. Sao 9 golpes e a conta e uma so.
  #-----------------------------------------------------------------------------
  def self.fraccao_de_dreno(mv)
    return 0.0 unless LIGADO && mv
    fc = (GameData::Move.get(mv.id).function_code.to_s rescue "")
    return 0.75 if fc.include?("ThreeQuartersOfDamageDone")
    return 0.50 if fc.include?("HalfOfDamageDone")
    0.0
  rescue
    0.0
  end

  #-----------------------------------------------------------------------------
  # ROUBO
  #
  # ⚠️ O ITEM VOA PARA O JOGADOR E ENTRA NA MOCHILA — foi a escolha feita.
  #
  # A outra hipotese era deixa-lo "em suspenso" ate ao fim do combate, para nao
  # furar a trava de gravacoes. Nao e preciso: a trava impede o SAVE, nao a
  # mochila. O `$bag` e memoria; o disco so e tocado quando a arena acaba, e ai
  # o item ja la esta. Nao ha travamento nenhum a pagar.
  #-----------------------------------------------------------------------------
  ROUBA  = %w[UserTakesTargetItem].freeze          # Thief, Covet
  DERRUBA = %w[RemoveTargetItem].freeze            # Knock Off

  def self.golpe_de_item(mv)
    fc = (GameData::Move.get(mv.id).function_code.to_s rescue "")
    return :rouba  if ROUBA.any?  { |p| fc.include?(p) }
    return :derruba if DERRUBA.any? { |p| fc.include?(p) }
    nil
  rescue
    nil
  end

  # `de_quem` e o Pokemon selvagem; `onde` o evento dele, para o item sair de la.
  def self.talvez_roubar!(mv, de_quem, onde)
    return unless LIGADO && mv && de_quem
    modo = golpe_de_item(mv)
    return unless modo
    item = (de_quem.item_id rescue nil)
    return unless item
    nome = (GameData::Item.get(item).name rescue item.to_s)
    (de_quem.item = nil) rescue nil
    if modo == :derruba
      (AnilArena.dizer(AnilLanRework.ui_format("Derrubou o {1}!", nome)) rescue nil)
      return
    end
    # ⚠️ A MOCHILA PODE ESTAR CHEIA, E AI O ITEM NAO SE PERDE.
    #
    # Devolve-se ao bicho: melhor ele ficar com ele do que ele desaparecer do
    # jogo por causa de um saco cheio.
    unless ($bag.add(item) rescue false)
      (de_quem.item = item) rescue nil
      (AnilArena.dizer(_INTL("A mochila está cheia!")) rescue nil)
      return
    end
    voar_item!(item, onde)
    (AnilArena.dizer(AnilLanRework.ui_format("Roubou o {1}!", nome)) rescue nil)
  rescue
    nil
  end

  #-----------------------------------------------------------------------------
  # O ITEM A VOAR
  #
  # Um arco do bicho ate ao jogador, meio segundo. E o mesmo gesto da Pokebola
  # ao contrario, e o que faz o roubo ler-se como roubo em vez de uma linha de
  # texto.
  #-----------------------------------------------------------------------------
  VOO_SEG = 0.45

  def self.voar_item!(item, onde)
    return unless onde && $game_player
    vp = (AnilArena.viewport_das_animacoes rescue nil)
    return unless vp
    bmp = (RPG::Cache.load_bitmap("Graphics/Items/", item.to_s) rescue nil)
    bmp ||= (pbGetItemIcon(item) rescue nil)
    return unless bmp
    sp = Sprite.new(vp)
    sp.bitmap = bmp
    sp.ox = bmp.width / 2
    sp.oy = bmp.height / 2
    sp.z = 2500
    (@voos ||= []) << {
      :sp => sp, :de => onde, :t => 0.0,
      :x0 => (onde.screen_x rescue 0), :y0 => (onde.screen_y rescue 0) - 16
    }
  rescue
    nil
  end

  def self.correr_voos!(dt)
    return if @voos.nil? || @voos.empty?
    fora = []
    @voos.each do |v|
      sp = v[:sp]
      if sp.nil? || (sp.disposed? rescue true)
        fora << v
        next
      end
      v[:t] += dt.to_f
      k = [v[:t] / VOO_SEG, 1.0].min
      ax = ($game_player.screen_x rescue 0)
      ay = ($game_player.screen_y rescue 0) - 16
      sp.x = (v[:x0] + ((ax - v[:x0]) * k)).round
      # O arco: sobe a meio caminho e cai no fim.
      sp.y = (v[:y0] + ((ay - v[:y0]) * k) - (Math.sin(Math::PI * k) * 28.0)).round
      sp.opacity = (k > 0.8) ? ((1.0 - k) * 5 * 255).round : 255
      if k >= 1.0
        (pbSEPlay("GUI storage pick up", 80) rescue nil)
        fora << v
      end
    end
    return if fora.empty?
    fora.each { |v| (v[:sp].dispose rescue nil) unless (v[:sp].disposed? rescue true) }
    @voos -= fora
  rescue
    limpar!
  end

  def self.limpar!
    (@voos || []).each do |v|
      (v[:sp].dispose rescue nil) if v[:sp] && !(v[:sp].disposed? rescue true)
    end
    @voos = []
  rescue
    @voos = []
  end
end
