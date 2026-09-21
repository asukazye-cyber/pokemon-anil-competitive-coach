# encoding: utf-8
#===============================================================================
# OS ITENS-CHAVE DA ARENA, E A ARMADURA DO MEWTWO
#
# ⚠️ OS ITENS NASCEM EM RUBY, NAO NO PBS — e a razao ja esta escrita no 189.
#
# Acrescentar uma linha ao `PBS/items.txt` obriga a regerar o `items.dat`. Isso
# nao viaja: o updater entrega DOIS ficheiros, o `Scripts.rxdata` e o
# `PluginScripts.rxdata`, e mais nada. Um item posto no PBS existia na minha
# maquina e em mais nenhuma.
#
# Pior do que nao chegar: na maquina de quem joga, um `.dat` regerado a partir
# do PBS antigo dele apaga o que la estiver de novo — foi o que quase aconteceu
# aos mapas 305-308. Registado em codigo, o item viaja no proprio Scripts.rxdata
# e nao depende de ficheiro de dados nenhum.
#
# ⚠️ E OS TRES SAO PORTOES, NAO PODERES.
#
# Nenhum destes itens faz nada por si. Cada um LIGA uma coisa que ja existe e
# que ate agora estava aberta a toda a gente:
#
#     Guia Mestre   a batalha automatica
#     Pochete       a bola automatica no shiny
#     Armadura      a forma 5 do Mewtwo, que ja estava no PBS e nao tinha
#                   maneira nenhuma de ser alcancada
#
# Vale a pena reparar no que isso quer dizer: a seguir a esta mudanca, quem
# tiver o amuleto mas nao tiver o Guia Mestre perde a automatica, que hoje tem.
# E deliberado — e o pedido —, mas e uma regressao para quem ja andava a usar.
#===============================================================================
module AnilArenaChaves
  GUIA     = :GUIAMESTRE
  POCHETE  = :POCHETE
  ARMADURA = :ARMADURA

  # ⚠️ Bolso 8 e o dos objectos importantes: nao se vendem nem se perdem por
  # engano, que e o que estes tres tem de ser. O `field_use 0` quer dizer que
  # nao se "usam" — trabalham por estarem na mochila (os dois primeiros) ou por
  # estarem equipados (a armadura).
  BOLSO = 8

  DEFINICOES = [
    {
      :id               => GUIA,
      :real_name        => "Guia Mestre",
      :real_name_plural => "Guias Mestres",
      :pocket           => BOLSO,
      :price            => 0,
      :field_use        => 0,
      :flags            => [],
      :real_description => "Permite mandar o Pokémon caçar sozinho enquanto você controla o personagem."
    },
    {
      :id               => POCHETE,
      :real_name        => "Pochete",
      :real_name_plural => "Pochetes",
      :pocket           => BOLSO,
      :price            => 0,
      :field_use        => 0,
      :flags            => [],
      :real_description => "Lança uma Pokébola sozinha quando aparece um Shiny ou Super Shiny."
    },
    {
      # ⚠️ A armadura NAO e do bolso dos importantes: e para SEGURAR.
      #
      # Um item que se equipa tem de estar num bolso de onde se possa dar ao
      # Pokemon, e os importantes nao se dao. Bolso 1 (itens) e o certo.
      :id               => ARMADURA,
      :real_name        => "Armadura",
      :real_name_plural => "Armaduras",
      :pocket           => 1,
      :price            => 0,
      :field_use        => 0,
      :flags            => [],
      :real_description => "Uma armadura de combate. Equipada em MEWTWO, revela a forma blindada."
    }
  ].freeze

  def self.registar!
    return unless defined?(GameData::Item)
    DEFINICOES.each do |d|
      next if (GameData::Item.exists?(d[:id]) rescue false)
      GameData::Item.register(d)
    end
  rescue => e
    (AnilArena.log("falha a registar os itens-chave: #{e.class}: #{e.message}") rescue nil)
  end

  def self.tem?(item)
    ($bag && $bag.has?(item)) ? true : false
  rescue
    false
  end

  def self.guia?;    tem?(GUIA);    end
  def self.pochete?; tem?(POCHETE); end

  #-----------------------------------------------------------------------------
  # A ARMADURA DO MEWTWO
  #
  # ⚠️ A FORMA JA EXISTIA, E NAO TINHA PORTA.
  #
  # O `PBS/pokemon_forms.txt` ja traz `[MEWTWO,5]` — "Mega Armadura", com
  # MagicBounce e o seu `MEWTWO_5.png` na pasta de sprites. So que nao tem
  # `MegaStone` nem handler nenhum: nao havia forma de la chegar em jogo. Nao ha
  # nada a acrescentar ao PBS; ha uma porta a abrir.
  #
  # ⚠️ E O HANDLER TEM DE SE CALAR QUANDO NAO TEM OPINIAO.
  #
  # O modelo aqui e o do Giratina (`getForm` com a Griseous Core), mas ele
  # devolve `0` quando nao tem o item — pode fazê-lo, porque so tem duas formas.
  # O Mewtwo tem as Mega X e Y. Um `next 0` cego arrastava um Mega Mewtwo de
  # volta a forma normal a meio de uma batalha.
  #
  # Devolve-se `nil` — "nao tenho opiniao" — e so se devolve 0 no unico caso em
  # que ha mesmo uma decisao a tomar: ele ESTA blindado e o item desapareceu.
  FORMA = 5

  def self.registar_forma!
    # Porta fechada temporariamente: a forma blindada fica desativada ate o
    # handler ser refeito sem recursao.
    return
    return unless defined?(MultipleForms)
    MultipleForms.register(:MEWTWO, {
      "getForm" => proc { |pkmn|
        next FORMA if (pkmn.hasItem?(ARMADURA) rescue false)
        next 0 if (pkmn.form rescue 0) == FORMA
        next nil
      }
    })
  rescue => e
    (AnilArena.log("falha a registar a forma blindada: #{e.class}: #{e.message}") rescue nil)
  end
end
