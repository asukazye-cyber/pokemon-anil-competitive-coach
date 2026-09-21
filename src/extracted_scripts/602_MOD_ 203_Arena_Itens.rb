# encoding: utf-8
#===============================================================================
# ITENS SEGUROS NA ARENA
#
# ⚠️ PORQUE UM FICHEIRO A PARTE — a mesma razao do 201.
#
# O 189 tem dezassete mil linhas. Isto sao tabelas e contas puras, sem estado
# nenhum: vive melhor sozinho, e o 189 ganha cinco linhas de chamada nos cinco
# sitios onde a coisa passa.
#
# ⚠️ E A REGRA QUE DECIDIU O QUE ENTRA: O QUE TEM ONDE ACONTECER.
#
# Numa luta por turnos um item tem momentos definidos — inicio de turno, fim de
# turno, ordem de ataque. A arena nao tem turnos. Por isso a lista nao foi feita
# por "quais sao os itens importantes", foi feita por "quais e que tem, aqui, um
# instante em que possam agir":
#
#   multiplicador de dano    o `dano_seco` — porta unica por onde passa o dano
#                            de toda a gente (meu, ajudante, selvagens)
#   regeneracao por turno    o tique de 3 s (ver TURNO_SEG)
#   baga por limiar de vida  o mesmo tique
#   aguentar um golpe        `ferir_bicho!` / `ferir_aliado!`
#   troco de quem bateu      `recolher_troco!`, que ja sabe quem foi
#   velocidade               `velocidade_livre`
#
# FICAM DE FORA, e nao por esquecimento:
#
#   Quick Claw, Custap Berry, Lagging Tail, Full Incense
#       Mexem na ORDEM do turno. Aqui nao ha ordem: cada um ataca quando a
#       recarga dele acabar. Nao ha nada que estes itens possam mudar.
#
#   Bagas de resistencia (Occa, Passho, Chople, ...)
#       Estas doiam-me deixar de fora, e a razao e tecnica e vale a pena ler.
#       Elas cortam a metade um golpe super-eficaz E CONSOMEM-SE. So que o
#       `dano_seco` nao e chamado apenas quando alguem bate: e tambem a
#       calculadora com que a IA COMPARA golpes antes de escolher. Gastar la a
#       baga queimava-a em cada hipotese que a IA pensasse, varias vezes por
#       segundo, sem ninguem levar pancada nenhuma. Um efeito que se consome nao
#       pode viver numa funcao que tambem serve para imaginar.
#
#   Metronome
#       Precisa de contar usos seguidos do mesmo golpe, e nao ha onde guardar
#       essa conta sem inventar um turno.
#
#   (A trava dos Choice esteve aqui e SAIU desta lista — ver BONUS_ESCOLHA.)
#===============================================================================
module AnilArenaItens
  LIGADO = true

  # ⚠️ QUANTO VALE UM "TURNO" AQUI: TRES SEGUNDOS.
  #
  # Nao e um numero inventado — e o que a arena JA decidiu. O veneno tira
  # `hp_max / DOT_FRACAO` por segundo com `DOT_FRACAO = 24`, e o veneno no jogo
  # tira 1/8 por turno. 24 = 8 x 3, logo um turno da arena vale 3 segundos.
  #
  # Seguir esse numero em vez de escolher outro e o que faz os Restos curarem
  # exactamente 1/16 por turno, como no jogo, em vez de uma fatia a esmo.
  TURNO_SEG = 3.0

  def self.item_de(pkmn)
    return nil unless LIGADO && pkmn
    (pkmn.item_id rescue nil)
  rescue
    nil
  end

  def self.nome_do_item(item)
    (GameData::Item.get(item).name rescue item.to_s)
  rescue
    item.to_s
  end

  #-----------------------------------------------------------------------------
  # OS QUE MULTIPLICAM O DANO QUE SE DA
  #-----------------------------------------------------------------------------

  # ⚠️ OS CHOICE ENTRAM INTEIROS: O BONUS E A TRAVA.
  #
  # Na primeira versao entrou so o bonus. O receio era que prender o jogador a
  # um botao durante uma luta em tempo real se lesse como o jogo ter travado —
  # e isso deixava-os a dar +50% sem cobrar nada, que e um item desequilibrado.
  #
  # O utilizador escolheu a trava, e tinha razao: um item que so tem vantagem
  # nao e uma escolha de equipamento, e um bonus gratis. Com a trava, poe-los e
  # uma aposta — e ha usos deliberados que so existem por causa dela, como
  # prender-se ao Thief de proposito.
  #
  # A recusa e SEMPRE dita ao jogador (ver o `usar_golpe!`). Uma trava
  # silenciosa era, do lado de la, indistinguivel de um bug.
  BONUS_ESCOLHA = 1.5

  # Quem tem a trava. Quem a APLICA e o 189, que e quem sabe o que e que cada um
  # esta a tentar fazer.
  ESCOLHA = [:CHOICEBAND, :CHOICESPECS, :CHOICESCARF].freeze

  def self.trava_de_escolha?(pkmn)
    return false unless LIGADO && pkmn
    ESCOLHA.include?(item_de(pkmn))
  rescue
    false
  end

  FISICO_1_5   = [:CHOICEBAND].freeze
  ESPECIAL_1_5 = [:CHOICESPECS].freeze
  FISICO_1_1   = [:MUSCLEBAND].freeze
  ESPECIAL_1_1 = [:WISEGLASSES].freeze

  # x1.3, e 10% da vida maxima de troco — o troco esta no `troco_de_quem_bateu`.
  ORBE = :LIFEORB

  # x1.2 quando o golpe e super-eficaz.
  CINTO = :EXPERTBELT

  # ⚠️ UMA TABELA, E NAO UMA LEITURA DO PBS.
  #
  # No Essentials estes itens nao declaram o tipo em lado nenhum que se possa
  # perguntar: o efeito esta escrito a mao dentro do calculo de dano da batalha.
  # Nao ha nada a ler — ou se copia a tabela, ou nao se faz. Sao 40 entradas e
  # nunca mudam.
  TIPO_1_2 = {
    :CHARCOAL     => :FIRE,     :MYSTICWATER  => :WATER,
    :MIRACLESEED  => :GRASS,    :MAGNET       => :ELECTRIC,
    :NEVERMELTICE => :ICE,      :BLACKBELT    => :FIGHTING,
    :POISONBARB   => :POISON,   :SOFTSAND     => :GROUND,
    :SHARPBEAK    => :FLYING,   :TWISTEDSPOON => :PSYCHIC,
    :SILVERPOWDER => :BUG,      :HARDSTONE    => :ROCK,
    :SPELLTAG     => :GHOST,    :DRAGONFANG   => :DRAGON,
    :BLACKGLASSES => :DARK,     :METALCOAT    => :STEEL,
    :SILKSCARF    => :NORMAL,   :FAIRYFEATHER => :FAIRY,
    # As placas do Arceus valem o mesmo 1.2.
    :FLAMEPLATE   => :FIRE,     :SPLASHPLATE  => :WATER,
    :MEADOWPLATE  => :GRASS,    :ZAPPLATE     => :ELECTRIC,
    :ICICLEPLATE  => :ICE,      :FISTPLATE    => :FIGHTING,
    :TOXICPLATE   => :POISON,   :EARTHPLATE   => :GROUND,
    :SKYPLATE     => :FLYING,   :MINDPLATE    => :PSYCHIC,
    :INSECTPLATE  => :BUG,      :STONEPLATE   => :ROCK,
    :SPOOKYPLATE  => :GHOST,    :DRACOPLATE   => :DRAGON,
    :DREADPLATE   => :DARK,     :IRONPLATE    => :STEEL,
    :PIXIEPLATE   => :FAIRY,
    # E os incensos.
    :SEAINCENSE   => :WATER,    :ODDINCENSE   => :PSYCHIC,
    :ROCKINCENSE  => :ROCK,     :ROSEINCENSE  => :GRASS,
    :WAVEINCENSE  => :WATER
  }.freeze

  # Os que dobram, e so para quem de direito.
  BOLA_LUZ    = :LIGHTBALL      # Pikachu: x2 no Ataque e no Ataque Especial
  OSSO_GROSSO = :THICKCLUB      # Cubone/Marowak: x2 no Ataque

  # `mult_tipo` e a eficacia ja calculada, para o Expert Belt saber se bate bem.
  def self.factor_de_ataque(atacante, dados, especial, mult_tipo)
    return 1.0 unless LIGADO && atacante && dados
    item = item_de(atacante)
    return 1.0 unless item
    f = 1.0
    if especial
      f *= BONUS_ESCOLHA if ESPECIAL_1_5.include?(item)
      f *= 1.1 if ESPECIAL_1_1.include?(item)
    else
      f *= BONUS_ESCOLHA if FISICO_1_5.include?(item)
      f *= 1.1 if FISICO_1_1.include?(item)
    end
    f *= 1.3 if item == ORBE
    f *= 1.2 if item == CINTO && mult_tipo.to_f > 1.0
    tp = TIPO_1_2[item]
    f *= 1.2 if tp && tipo_do_golpe(dados) == tp
    f *= 2.0 if item == BOLA_LUZ && especie?(atacante, [:PIKACHU])
    f *= 2.0 if item == OSSO_GROSSO && !especial && especie?(atacante, [:CUBONE, :MAROWAK])
    f
  rescue
    1.0
  end

  def self.tipo_do_golpe(dados)
    t = (dados.type rescue nil)
    return nil unless t
    (t.respond_to?(:id) ? t.id : t.to_sym)
  rescue
    nil
  end

  def self.especie?(pkmn, lista)
    sp = (pkmn.species rescue nil)
    return false unless sp
    sp = sp.id if sp.respond_to?(:id)
    lista.include?(sp.to_sym)
  rescue
    false
  end

  #-----------------------------------------------------------------------------
  # OS QUE APARAM O DANO QUE SE LEVA
  #-----------------------------------------------------------------------------
  COLETE   = :ASSAULTVEST   # x1.5 na Defesa Especial
  EVIOLITE = :EVIOLITE      # x1.5 nas duas defesas, so a quem ainda evolui

  def self.factor_de_defesa(defensor, especial)
    return 1.0 unless LIGADO && defensor
    item = item_de(defensor)
    return 1.0 unless item
    f = 1.0
    f *= 1.5 if item == COLETE && especial
    f *= 1.5 if item == EVIOLITE && ainda_evolui?(defensor)
    f
  rescue
    1.0
  end

  # ⚠️ "Nao esta totalmente evoluido" le-se no proprio GameData, e nao a mao.
  # As formas de o perguntar mudaram entre versoes do Essentials, por isso
  # tentam-se as duas e assume-se "nao evolui" se nenhuma responder — falhar
  # para o lado de NAO dar o bonus e o lado seguro.
  def self.ainda_evolui?(pkmn)
    sp = (GameData::Species.get(pkmn.species) rescue nil)
    return false unless sp
    if sp.respond_to?(:get_evolutions)
      lista = (sp.get_evolutions(true) rescue nil) || (sp.get_evolutions rescue nil)
      return !(lista.nil? || lista.empty?)
    end
    lista = (sp.evolutions rescue nil)
    !(lista.nil? || lista.empty?)
  rescue
    false
  end

  #-----------------------------------------------------------------------------
  # A VELOCIDADE
  #-----------------------------------------------------------------------------
  VELOCIDADE = {
    :CHOICESCARF => 1.5,
    :IRONBALL    => 0.5,
    :MACHOBRACE  => 0.5,
    :POWERWEIGHT => 0.5, :POWERBRACER => 0.5, :POWERBELT   => 0.5,
    :POWERLENS   => 0.5, :POWERBAND   => 0.5, :POWERANKLET => 0.5
  }.freeze

  def self.factor_de_velocidade(pkmn)
    return 1.0 unless LIGADO && pkmn
    item = item_de(pkmn)
    return 1.0 unless item
    return (especie?(pkmn, [:DITTO]) ? 2.0 : 1.0) if item == :QUICKPOWDER
    VELOCIDADE[item] || 1.0
  rescue
    1.0
  end

  #-----------------------------------------------------------------------------
  # O QUE ACONTECE DE TURNO A TURNO
  #
  # Devolve [variacao_de_vida, mensagem]. Negativo tira. Quem chama e que sabe
  # onde e que a vida daquele Pokemon esta guardada.
  #-----------------------------------------------------------------------------
  def self.regeneracao(pkmn, hp, hp_max)
    return [0, nil] unless LIGADO && pkmn && hp.to_i > 0
    item = item_de(pkmn)
    return [0, nil] unless item
    case item
    when :LEFTOVERS
      return [0, nil] if hp.to_i >= hp_max.to_i
      [[(hp_max.to_f / 16.0).round, 1].max, nil]
    when :BLACKSLUDGE
      if tipo_do_bicho?(pkmn, :POISON)
        return [0, nil] if hp.to_i >= hp_max.to_i
        [[(hp_max.to_f / 16.0).round, 1].max, nil]
      else
        [-[(hp_max.to_f / 8.0).round, 1].max, _INTL("O Black Sludge machucou!")]
      end
    else
      [0, nil]
    end
  rescue
    [0, nil]
  end

  def self.tipo_do_bicho?(pkmn, tipo)
    tipos = [(pkmn.types rescue [])].flatten.compact
    tipos.any? { |t| (t.respond_to?(:id) ? t.id : t.to_sym) == tipo }
  rescue
    false
  end

  #-----------------------------------------------------------------------------
  # AS BAGAS QUE ESPERAM POR UM LIMIAR DE VIDA
  #
  # Devolve [cura, limpa_estado, mensagem] e CONSOME a baga. Isto e chamado do
  # tique, e nunca do calculo de dano — ver a nota do topo sobre a IA.
  #-----------------------------------------------------------------------------
  METADE = [:SITRUSBERRY, :ORANBERRY, :BERRYJUICE].freeze
  QUARTO = [:FIGYBERRY, :WIKIBERRY, :MAGOBERRY, :AGUAVBERRY, :IAPAPABERRY].freeze

  def self.talvez_baga!(pkmn, hp, hp_max, estado)
    return [0, false, nil] unless LIGADO && pkmn && hp.to_i > 0
    item = item_de(pkmn)
    return [0, false, nil] unless item
    nome = nome_do_item(item)

    # A Lum cura o estado, e so serve de alguma coisa se houver estado.
    if item == :LUMBERRY
      return [0, false, nil] unless estado
      (pkmn.item = nil) rescue nil
      return [0, true, AnilLanRework.ui_format("A {1} curou o mal-estar!", nome)]
    end

    fraccao = hp.to_f / [hp_max.to_f, 1.0].max
    if METADE.include?(item) && fraccao <= 0.5
      cura = case item
             when :SITRUSBERRY then [(hp_max.to_f / 4.0).round, 1].max
             when :ORANBERRY   then 10
             else 20
             end
      (pkmn.item = nil) rescue nil
      return [cura, false, AnilLanRework.ui_format("A {1} restaurou {2} de vida!", nome, cura)]
    end
    if QUARTO.include?(item) && fraccao <= 0.25
      cura = [(hp_max.to_f / 3.0).round, 1].max
      (pkmn.item = nil) rescue nil
      return [cura, false, AnilLanRework.ui_format("A {1} restaurou {2} de vida!", nome, cura)]
    end
    [0, false, nil]
  rescue
    [0, false, nil]
  end

  #-----------------------------------------------------------------------------
  # AGUENTAR UM GOLPE QUE MATAVA
  #
  # Devolve o dano CORRIGIDO. Chamado no instante do dano, que e o unico sitio
  # onde a pergunta "isto matava?" tem resposta.
  #-----------------------------------------------------------------------------
  def self.aguenta_o_golpe(pkmn, hp, hp_max, d)
    d = d.to_i
    return d unless LIGADO && pkmn && d > 0
    return d if d < hp.to_i            # nao matava, nao ha nada a fazer
    item = item_de(pkmn)
    return d unless item
    if item == :FOCUSSASH
      # ⚠️ A Sash so vale com a vida CHEIA. E a regra do jogo, e e o que a
      # distingue da Focus Band: uma paga-se uma vez e e certa, a outra e sorte
      # e repete-se.
      return d unless hp.to_i >= hp_max.to_i
      (pkmn.item = nil) rescue nil
      return [hp.to_i - 1, 0].max
    end
    if item == :FOCUSBAND && rand(100) < 10
      return [hp.to_i - 1, 0].max
    end
    d
  rescue
    d.to_i
  end

  #-----------------------------------------------------------------------------
  # O TROCO DE QUEM BATEU
  #
  # Devolve [cura, perda]. Chamado do `recolher_troco!`, que e o unico sitio que
  # sabe de quem foi o golpe.
  #-----------------------------------------------------------------------------
  def self.troco_de_quem_bateu(pkmn, dano_feito, hp_max)
    return [0, 0] unless LIGADO && pkmn && dano_feito.to_i > 0
    item = item_de(pkmn)
    return [0, 0] unless item
    cura = 0
    perda = 0
    cura = [(dano_feito.to_f / 8.0).round, 1].max if item == :SHELLBELL
    perda = [(hp_max.to_f / 10.0).round, 1].max if item == ORBE
    [cura, perda]
  rescue
    [0, 0]
  end
end
