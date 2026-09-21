#===============================================================================
# MOD: 100_Rarity_Eggs_System.rb (OTIMIZADO)
#-------------------------------------------------------------------------------
# Adiciona o sistema de Ovos de Raridade que brilham e são dropados por NPCs.
#
# Otimizações aplicadas:
#   1. apply_egg_tone centralizado: elimina duplicação 4× nos sprites
#   2. pbBuildEgg centralizado: elimina ~70% de código repetido entre
#      pbGenerateRarityEgg e pbUseEggItem
#   3. DROP_THRESHOLDS pré-calculado: zero somas em runtime no check_and_trigger_drop
#   4. pulse_value e item_pulse_factor: cache por frame mantido (já estava correto)
#===============================================================================

# 1. Extensão da classe Pokemon para salvar a raridade do ovo
class Pokemon
  attr_accessor :egg_rarity
end

#===============================================================================
# 4. Módulo do Sistema e Bancos de Dados
#===============================================================================
module RarityEggSystem

  # --- Cache de pulso por frame (sem alteração, já estava otimizado) ----------

  def self.pulse_value
    current_frame = Graphics.frame_count
    if @last_pulse_frame != current_frame
      @last_pulse_frame = current_frame
      @cached_pulse = (160 + 60 * Math.sin(System.uptime * 2 * Math::PI / 1.0)).to_i
    end
    @cached_pulse
  end




  # --- Configurações de Drop --------------------------------------------------

  # Chances individuais (de 1000). Total = 10% de qualquer ovo dropar.
  DROP_CHANCES = {
    :orange => 1,   # 0.1% (Elite)
    :purple => 5,   # 0.5% (Raro)
    :blue   => 14,  # 1.4% (Incomum)
    :green  => 30,  # 3.0% (Útil)
    :grey   => 50   # 5.0% (Comum)
  }.freeze

  # OTIMIZAÇÃO: thresholds acumulados pré-calculados uma única vez.
  # Evita somas repetidas a cada check_and_trigger_drop (chamado após toda batalha).
  DROP_THRESHOLDS = DROP_CHANCES.each_with_object({ acc: 0 }) do |(rarity, chance), h|
    h[rarity] = h[:acc] + chance
    h[:acc]   = h[rarity]
  end.freeze

  # --- Listas de Pokémon por raridade ----------------------------------------

  ORANGE_LIST = [
    :CHARMANDER, :FROAKIE, :GIBLE, :LARVITAR, :RIOLU, :BELDUM, :DRATINI, :BAGON,
    :GOOMY, :DREEPY, :FRIGIBAX, :LARVESTA, :HONEDGE, :SCYTHER, :TORCHIC, :MUDKIP,
    :ROWLET, :LITTEN, :SPRIGATITO, :FUECOCO, :QUAXLY, :PAWNIARD, :SNEASEL, :IMPIDIMP,
    :CHARCADET, :DURALUDON, :APPLIN, :ROOKIDEE, :TINKATINK, :HATENNA
  ].freeze

  PURPLE_LIST = [
    :TOGEPI, :MAGIKARP, :GASTLY, :RALTS, :DEINO, :JANGMOO, :BULBASAUR, :SQUIRTLE,
    :TREECKO, :CHIMCHAR, :POPPLIO, :SNIVY, :FLETCHLING, :FEEBAS, :MAGNEMITE, :PORYGON,
    :GLIGAR, :EEVEE, :DRILBUR, :ROTOM, :FERROSEED, :AXEW, :LITWICK, :SOLOSIS,
    :MIMIKYU, :MAREANIE, :SINISTEA, :DARUMAKA, :GOTHITA, :SNOM
  ].freeze

  BLUE_LIST = [
    :GROWLITHE, :ZORUA, :ABRA, :MACHOP, :GEODUDE, :RHYHORN, :ELEKID, :MAGBY,
    :SWINUB, :MURKROW, :HOUNDOUR, :ARON, :CORPHISH, :SHROOMISH, :CACNEA, :CRANIDOS,
    :SHIELDON, :HIPPOPOTAS, :SKORUPI, :CROAGUNK, :SNOVER, :SANDILE, :SIGILYPH, :TYNAMO,
    :SKRELP, :CLAUNCHER, :HAWLUCHA, :PHANTUMP, :PUMPKABOO, :NOIBAT
  ].freeze

  GREEN_LIST = [
    :ZUBAT, :NIDORANfE, :NIDORANmA, :ODDISH, :POLIWAG, :TENTACOOL, :SLOWPOKE, :PONYTA,
    :DODUO, :GRIMER, :SHELLDER, :ONIX, :KRABBY, :TANGELA, :HORSEA, :STARYU,
    :PINSIR, :CHINCHOU, :NATU, :MAREEP, :MARILL, :WOOPER, :GIRAFARIG, :DUNSPARCE,
    :SHUCKLE, :HERACROSS, :PHANPY, :TYROGUE, :WINGULL, :TORKOAL
  ].freeze

  GREY_LIST = [
    :PIDGEY, :RATTATA, :SPEAROW, :EKANS, :SANDSHREW, :DIGLETT, :MEOWTH, :PSYDUCK,
    :MANKEY, :BELLSPROUT, :HOOTHOOT, :LEDYBA, :SPINARAK, :SENTRET, :ZIGZAGOON, :WURMPLE,
    :TAILLOW, :SURSKIT, :SLAKOTH, :WHISMUR, :BIDOOF, :KRICKETOT, :STARLY, :SHINX,
    :PATRAT, :LILLIPUP, :PURRLOIN, :PIDOVE, :SEWADDLE, :VENIPEDE
  ].freeze

  # Mapa de raridade → lista (evita case/when repetido em vários métodos)
  RARITY_LISTS = {
    :orange => ORANGE_LIST,
    :purple => PURPLE_LIST,
    :blue   => BLUE_LIST,
    :green  => GREEN_LIST,
    :grey   => GREY_LIST
  }.freeze

  RARITY_NAMES = {
    :orange => "Laranja (Elite)",
    :purple => "Roxo (Raro)",
    :blue   => "Azul (Incomum)",
    :green  => "Verde (Útil)",
    :grey   => "Cinza (Comum)"
  }.freeze

  # --- Tones por raridade (constante, evita recriar Tone a cada frame) --------
  # Os valores de grey usam pulse/2; os demais usam pulse completo.
  # O módulo aplica o pulse dinamicamente; as componentes RGB ficam fixas aqui.
  RARITY_TONE_RGB = {
    :orange => [ 60,  20, -60],
    :purple => [ 40, -60,  60],
    :blue   => [-60,  20,  60],
    :green  => [-60,  60, -60],
    :grey   => [  0,   0,   0]
  }.freeze

  # OTIMIZAÇÃO: método único para aplicar tone num sprite.
  # Antes: lógica duplicada em PokemonIconSprite e PokemonSprite (4 blocos case/when).
  # Agora: 1 método chamado pelos dois sprites.
  def self.apply_egg_tone(sprite, rarity)
    rgb   = RARITY_TONE_RGB[rarity]
    pulse = pulse_value
    gray  = rarity == :grey ? pulse / 2 : pulse
    r, g, b = rgb
    if sprite.tone
      sprite.tone.set(r, g, b, gray)
    else
      sprite.tone = Tone.new(r, g, b, gray)
    end
  end

  # --- Helpers ----------------------------------------------------------------

  def self.get_trainer_name(*args)
    return nil if args.empty?
    arg = args[0]
    if arg.respond_to?(:name)
      return arg.name
    elsif arg.is_a?(Array)
      return arg[1].to_s rescue nil
    elsif arg.is_a?(Symbol) || arg.is_a?(String)
      return args[1].to_s rescue nil
    end
    nil
  end

  def self.rarity_name(rarity)
    _INTL(RARITY_NAMES[rarity] || "Desconhecido")
  end

  # --- Núcleo de criação de ovo (NOVO — elimina duplicação) -------------------
  #
  # OTIMIZAÇÃO: pbGenerateRarityEgg e pbUseEggItem compartilhavam ~70% do código.
  # Esse método centraliza a criação; os outros apenas chamam ele.
  #
  # @param rarity [Symbol] :orange, :purple, :blue, :green ou :grey
  # @param obtain_text [String] texto de origem do ovo
  # @param variant [Symbol] :normal (sorteia shiny), :shiny ou :super (garantidos)
  # @return [Pokemon] o ovo criado (ainda não adicionado à party/PC)
  def self.pbBuildEgg(rarity, obtain_text, variant = :normal)
    list    = RARITY_LISTS[rarity] || GREY_LIST
    species = list.sample
    egg     = Pokemon.new(species, 1)
    egg.name          = _INTL("Ovo")
    egg.steps_to_hatch = egg.species_data.hatch_steps || 2560
    egg.egg_rarity    = rarity
    egg.obtain_text   = obtain_text
    # A variante decide a shininess. :normal mantém o sorteio original
    # (chance dobrada); os itens de variante garantem o resultado.
    case variant
    when :super
      egg.super_shiny = true   # super_shiny= já força shiny = true
    when :shiny
      egg.shiny = true
    else
      # Dobra a chance de shiny
      egg.shiny = true if rand(65536) < Settings::SHINY_POKEMON_CHANCE * 2
    end
    egg
  end

  # Exibe mensagem de raridade (shiny ou não) após receber o ovo
  def self.show_rarity_message(egg)
    rname = rarity_name(egg.egg_rarity)
    if egg.super_shiny?
      pbMessage(_INTL("O ovo emite um brilho de raridade {1} e pulsa com um brilho quadrado raríssimo!", rname))
    elsif egg.shiny?
      pbMessage(_INTL("O ovo emite um brilho de raridade {1} e tem uma coloração brilhante especial!", rname))
    else
      pbMessage(_INTL("O ovo emite um brilho de raridade {1}!", rname))
    end
  end

  # --- Geração via drop de NPC ------------------------------------------------

  def self.pbGenerateRarityEgg(rarity = nil, trainer_name = nil)
    # Sorteia raridade se não fornecida
    if rarity.nil?
      r = rand(100)
      rarity = if    r < 1  then :orange
               elsif r < 6  then :purple
               elsif r < 20 then :blue
               elsif r < 50 then :green
               else              :grey
               end
    end

    # Fala do treinador
    if trainer_name
      msg = nil
      if defined?(AnilLanRework) && defined?(AnilLanRework::RematchSystem)
        msg = AnilLanRework::RematchSystem.get_msg_egg(rarity) rescue nil
      end

      if msg.nil?
        dialogues = {
          :grey => [
            "Ganhei esse ovo, mas não sei qual Pokémon vai nascer. Fica pra você!",
            "Achei esse ovo ali atrás... Não tenho tempo para chocar, quer ficar com ele?",
            "Tenho este ovo misterioso aqui, acho que você cuidará melhor dele do que eu.",
            "Belo combate! Não tenho espaço para mais ovos na minha equipe, leve este com você!",
            "Eu não sou muito bom chocando ovos... Leve este aqui, pode conter algo interessante!"
          ],
          :green => [
            "Bela batalha! Leve este ovo, sinto que ele dará origem a um bom parceiro de jornada.",
            "Você luta muito bem! Pegue este ovo de presente, ele parece ser promissor.",
            "Esse ovo tem uma energia forte... Fique com ele como prêmio pela sua vitória!",
            "Sua estratégia é excelente! Leve este ovo verde reluzente como recompensa.",
            "Aqui está um ovo misterioso que encontrei. Sinto que um Pokémon bem útil vai nascer dele!"
          ],
          :blue => [
            "Incrível! Você merece este ovo incomum. Cuide bem dele!",
            "Esse ovo brilha de um jeito diferente... Acho que vai nascer algo muito interessante dele!",
            "Raramente vejo treinadores como você. Leve este ovo azulado especial.",
            "Seu estilo de luta me impressionou. Fique com este ovo de brilho azulado!",
            "Este ovo brilha como o oceano... Tenho certeza de que será um ótimo Pokémon!"
          ],
          :purple => [
            "Uau, que força! Esse ovo roxo é muito raro, sinto que ele deve ser seu.",
            "Eu estava guardando esse ovo precioso, mas sua vitória provou que você é o dono ideal.",
            "Um ovo brilhante roxo! É um achado raro, leve-o com você!",
            "Que poder incrível! Este ovo raro com certeza merece um treinador como você.",
            "Um ovo de tonalidade roxa misteriosa... Um prêmio à altura do seu talento!"
          ],
          :orange => [
            "Inacreditável... Uma batalha lendária! Pegue este ovo de Elite, ele pertence apenas aos melhores!",
            "Este ovo emite uma aura colossal! Ele carrega o potencial de um Pokémon incrível. Por favor, fique com ele!",
            "Um ovo de raridade máxima! Você me derrotou com maestria, é o seu prêmio ideal.",
            "Um ovo que brilha como o sol! Só um verdadeiro campeão poderia carregá-lo.",
            "Este ovo possui uma energia absurda... É o presente perfeito para quem me derrotou tão bem!"
          ]
        }
        msg = dialogues[rarity].sample
      end
      pbMessage(_INTL("{1}: \"{2}\"", trainer_name, msg))
    end

    # ⚠️ ENTREGA O ITEM, NAO O OVO.
    #
    # Antes criava-se o Pokemon-ovo aqui e empurrava-se para a equipa — ou, com
    # a equipa cheia, para o PC. Como o drop dispara depois de QUALQUER batalha
    # de treinador, as box enchiam-se de ovos que ninguem pediu e que nao davam
    # para recusar.
    #
    # O item ja existe (EGG_GREY..EGG_ORANGE, registados no on_enter_map) e ja
    # tem handler proprio — o pbUseEggItem — que poe o ovo na equipa quando o
    # jogador decidir. Assim ele escolhe se e quando quer chocar, e pode ate
    # vender ou negociar o item.
    item = ITEM_POR_RARIDADE[rarity]
    if item && (GameData::Item.exists?(item) rescue false) && $bag.can_add?(item)
      $bag.add(item, 1)
      nome = (GameData::Item.get(item).name rescue item.to_s)
      pbMEPlay("Item get") rescue nil
      pbMessage(_INTL("Você recebeu \c[1]{1}\c[0]! Use-o na mochila quando quiser chocar o ovo.", nome))
      return nil
    end

    # Reserva: mochila cheia ou item por registar. Melhor o comportamento antigo
    # do que perder a recompensa em silencio.
    egg = pbBuildEgg(rarity, _INTL("NPC de Batalha"))
    if $player.party.length < Settings::MAX_PARTY_SIZE
      $player.party.push(egg)
      pbMessage(_INTL("Você recebeu um Ovo Misterioso brilhante e o colocou na sua equipe!"))
    else
      $PokemonStorage.pbStoreCaught(egg)
      pbMessage(_INTL("Você recebeu um Ovo Misterioso brilhante e ele foi enviado para o PC!"))
    end

    show_rarity_message(egg)
    egg
  end

  # raridade -> item da mochila. E o inverso do EGG_BASE_ITEM_RARITY, que so e
  # definido mais abaixo no ficheiro; escrito a mao para nao depender da ordem.
  ITEM_POR_RARIDADE = {
    :grey   => :EGG_GREY,
    :green  => :EGG_GREEN,
    :blue   => :EGG_BLUE,
    :purple => :EGG_PURPLE,
    :orange => :EGG_ORANGE
  }.freeze

  # --- Check de drop pós-batalha ----------------------------------------------

  def self.check_and_trigger_drop(*args)
    return if $game_temp.instance_variable_get(:@anil_skip_coop_invite) rescue false

    trainer_name = get_trainer_name(*args)

    # OTIMIZAÇÃO: thresholds pré-calculados — zero operações de soma aqui.
    r = rand(1000)
    rarity = if    r < DROP_THRESHOLDS[:orange] then :orange
             elsif r < DROP_THRESHOLDS[:purple] then :purple
             elsif r < DROP_THRESHOLDS[:blue]   then :blue
             elsif r < DROP_THRESHOLDS[:green]  then :green
             elsif r < DROP_THRESHOLDS[:grey]   then :grey
             end

    pbGenerateRarityEgg(rarity, trainer_name) if rarity
  end

  # --- Uso de item de ovo da bolsa --------------------------------------------

  # ⚠️ CONSOME -> SORTEIA -> GRAVA -> MOSTRA. A ordem e obrigatoria.
  #
  # O pbBuildEgg sorteia a especie (list.sample) E a shininess, e o
  # show_rarity_message diz na cara do jogador se o ovo saiu brilhante. Enquanto
  # a gravacao ficasse para o autosave, quem lesse a mensagem sem a parte do
  # brilho fechava o jogo, voltava a entrar com o item intacto e sorteava outra
  # vez ate sair super shiny. O item mais raro do jogo passava a ser uma questao
  # de paciencia.
  #
  # Gravar antes da mensagem fecha a porta: quando ele le o resultado, o
  # resultado ja esta em disco.
  #
  # O consumo tem de ser NOSSO porque o motor so remove DEPOIS de o handler
  # devolver, e gravar aqui dentro gravaria o item ainda na mochila. Por isso
  # estes itens levam @consumable = false mais abaixo. Mesmo desenho das caixas
  # de presente (MOD 068) e dos sacos de moedas (MOD 108).
  def self.pbUseEggItem(rarity, variant = :normal, item = nil)
    if $player.party.length >= Settings::MAX_PARTY_SIZE
      pbMessage(_INTL("Você precisa ter espaço na equipe para usar este item!"))
      return 0
    end

    if item
      return 0 if $bag.nil? || !$bag.has?(item)
      $bag.remove(item, 1)
    end

    egg = pbBuildEgg(rarity, _INTL("Item de Bolsa"), variant)
    $player.party.push(egg)
    gravar_ovo!(item, egg)
    pbMessage(_INTL("Você colocou o Ovo Misterioso na equipe!"))
    show_rarity_message(egg)
    1
  end

  def self.gravar_ovo!(item, egg)
    if defined?(AnilLanRework) && AnilLanRework.respond_to?(:gravar_ja!)
      AnilLanRework.gravar_ja!("ovo_raridade")
      (AnilLanRework.log("ovo de raridade: #{item} deu #{egg.species} shiny=#{egg.shiny?}, gravado antes de mostrar") rescue nil)
    elsif defined?(Game) && Game.respond_to?(:save)
      Game.save
    elsif defined?(SaveData) && SaveData.respond_to?(:save_to_file)
      SaveData.save_to_file(SaveData::FILE_PATH)
    end
  rescue => e
    (AnilLanRework.log("ovo de raridade: falha ao gravar: #{e.class}: #{e.message}") rescue nil)
  end
end

# 2. Extensão do PokemonIconSprite
class PokemonIconSprite < Sprite
  alias rarity_egg_update update unless method_defined?(:rarity_egg_update)

  def update
    rarity_egg_update
    rarity = (@pokemon.egg? && @pokemon.egg_rarity) rescue nil
    if rarity
      if $in_bag_scene
        if @last_egg_pokemon != @pokemon || @last_egg_rarity != rarity
          RarityEggSystem.apply_egg_tone(self, rarity)
          @has_egg_tone = true
          @last_egg_pokemon = @pokemon
          @last_egg_rarity = rarity
        end
      else
        RarityEggSystem.apply_egg_tone(self, rarity)
        @has_egg_tone = true
        @last_egg_pokemon = @pokemon
        @last_egg_rarity = rarity
      end
    else
      if @has_egg_tone
        self.tone.set(0, 0, 0, 0) if self.tone
        @has_egg_tone = false
      end
      @last_egg_pokemon = nil
      @last_egg_rarity = nil
    end
  end
end

# 3. Extensão do PokemonSprite
class PokemonSprite < Sprite
  alias rarity_egg_setPokemonBitmap setPokemonBitmap unless method_defined?(:rarity_egg_setPokemonBitmap)
  alias rarity_egg_setPokemonBitmapSpecies setPokemonBitmapSpecies unless method_defined?(:rarity_egg_setPokemonBitmapSpecies)
  alias rarity_egg_update update unless method_defined?(:rarity_egg_update)

  def setPokemonBitmap(pokemon, back = false)
    @pokemon = pokemon
    rarity_egg_setPokemonBitmap(pokemon, back)
  end

  def setPokemonBitmapSpecies(pokemon, species, back = false)
    @pokemon = pokemon
    rarity_egg_setPokemonBitmapSpecies(pokemon, species, back)
  end

  def update
    rarity_egg_update
    rarity = (@is_egg && @pokemon && @pokemon.egg_rarity) rescue nil
    if rarity
      if $in_bag_scene
        if @last_egg_pokemon != @pokemon || @last_egg_rarity != rarity
          RarityEggSystem.apply_egg_tone(self, rarity)
          @has_egg_tone = true
          @last_egg_pokemon = @pokemon
          @last_egg_rarity = rarity
        end
      else
        RarityEggSystem.apply_egg_tone(self, rarity)
        @has_egg_tone = true
        @last_egg_pokemon = @pokemon
        @last_egg_rarity = rarity
      end
    else
      if @has_egg_tone
        self.tone.set(0, 0, 0, 0) if self.tone
        @has_egg_tone = false
      end
      @last_egg_pokemon = nil
      @last_egg_rarity = nil
    end
  end
end

# 5. Hook de início/fim de batalha
if defined?(TrainerBattle)
  class << TrainerBattle
    alias rarity_egg_start start unless method_defined?(:rarity_egg_start)

    def start(*args)
      outcome = rarity_egg_start(*args)
      RarityEggSystem.check_and_trigger_drop(*args) if outcome == true || outcome == 1
      outcome
    end
  end
end

#===============================================================================
# Registro Dinâmico e Handlers dos Itens de Ovo
#===============================================================================
# Variantes de ovo. Cada cor ganha uma versão shiny e uma super shiny: mesmo
# ovo e mesma lista de espécies, mudando só a garantia de shininess. Gerar a
# partir das defs base evita 10 hashes quase idênticos e faz uma cor nova
# ganhar suas variantes de graça.
EGG_VARIANTS = {
  :shiny => {
    :suffix => "_SHINY",
    :name   => " Shiny",
    :desc   => "Garante que o Pokémon nasça shiny!"
  },
  :super => {
    :suffix => "_SUPERSHINY",
    :name   => " Super Shiny",
    :desc   => "Garante que o Pokémon nasça super shiny!"
  }
}.freeze

EGG_BASE_ITEMS_DEFS = [
  {
    :id               => :EGG_GREY,
    :real_name        => "Ovo Comum",
    :real_name_plural => "Ovos Comuns",
    :pocket           => 1,
    :price            => 0,
    :sell_price       => 0,
    :field_use        => 2,
    :battle_use       => 0,
    :flags            => [],
    :consumable       => true,
    :show_quantity    => true,
    :real_description => "Um ovo misterioso cinza. Use para receber um ovo de Pokémon comum!"
  },
  {
    :id               => :EGG_GREEN,
    :real_name        => "Ovo Útil",
    :real_name_plural => "Ovos Úteis",
    :pocket           => 1,
    :price            => 0,
    :sell_price       => 0,
    :field_use        => 2,
    :battle_use       => 0,
    :flags            => [],
    :consumable       => true,
    :show_quantity    => true,
    :real_description => "Um ovo misterioso verde. Use para receber um ovo de Pokémon útil!"
  },
  {
    :id               => :EGG_BLUE,
    :real_name        => "Ovo Incomum",
    :real_name_plural => "Ovos Incomuns",
    :pocket           => 1,
    :price            => 0,
    :sell_price       => 0,
    :field_use        => 2,
    :battle_use       => 0,
    :flags            => [],
    :consumable       => true,
    :show_quantity    => true,
    :real_description => "Um ovo misterioso azul. Use para receber um ovo de Pokémon incomum!"
  },
  {
    :id               => :EGG_PURPLE,
    :real_name        => "Ovo Raro",
    :real_name_plural => "Ovos Raros",
    :pocket           => 1,
    :price            => 0,
    :sell_price       => 0,
    :field_use        => 2,
    :battle_use       => 0,
    :flags            => [],
    :consumable       => true,
    :show_quantity    => true,
    :real_description => "Um ovo misterioso roxo. Use para receber um ovo de Pokémon raro!"
  },
  {
    :id               => :EGG_ORANGE,
    :real_name        => "Ovo de Elite",
    :real_name_plural => "Ovos de Elite",
    :pocket           => 1,
    :price            => 0,
    :sell_price       => 0,
    :field_use        => 2,
    :battle_use       => 0,
    :flags            => [],
    :consumable       => true,
    :show_quantity    => true,
    :real_description => "Um ovo misterioso laranja. Use para receber um ovo de Pokémon elite!"
  }
].freeze

EGG_VARIANT_ITEMS_DEFS = EGG_BASE_ITEMS_DEFS.flat_map { |base|
  EGG_VARIANTS.map { |_key, info|
    base.merge(
      :id               => :"#{base[:id]}#{info[:suffix]}",
      :real_name        => "#{base[:real_name]}#{info[:name]}",
      :real_name_plural => "#{base[:real_name_plural]}#{info[:name]}",
      :real_description => "#{base[:real_description]} #{info[:desc]}"
    )
  }
}.freeze

EGG_ITEMS_DEFS = (EGG_BASE_ITEMS_DEFS + EGG_VARIANT_ITEMS_DEFS).freeze

$egg_items_registered = false
if defined?(EventHandlers) && EventHandlers.respond_to?(:add)
  EventHandlers.add(:on_enter_map, :rarity_egg_items_register, proc { |_old_map_id|
    unless $egg_items_registered
      $egg_items_registered = true
      EGG_ITEMS_DEFS.each do |item_hash|
        # ⚠️ @consumable = false: o motor perde a autorizacao para remover o
        # item, nos dois caminhos (UseFromBag e UseInField), porque o consumo
        # passou a ser feito a mao dentro do pbUseEggItem — antes do sorteio,
        # para nao dar para repetir a jogada. Ver o comentario la.
        #
        # Tem de ser AQUI e nao junto aos handlers: estes itens so existem a
        # partir deste registo, que corre no on_enter_map.
        GameData::Item.register(item_hash.merge(:consumable => false)) rescue nil
      end
    end
  })
end

# Mapa item → raridade para eliminar case/when duplicado nos dois handlers
EGG_BASE_ITEM_RARITY = {
  :EGG_GREY   => :grey,
  :EGG_GREEN  => :green,
  :EGG_BLUE   => :blue,
  :EGG_PURPLE => :purple,
  :EGG_ORANGE => :orange
}.freeze

# item → [raridade, variante]. A raridade escolhe a lista de espécies; a
# variante decide a shininess (:normal sorteia, :shiny e :super garantem).
EGG_ITEM_RARITY_MAP = begin
  map = {}
  EGG_BASE_ITEM_RARITY.each do |item, rarity|
    map[item] = [rarity, :normal]
    EGG_VARIANTS.each do |vkey, info|
      map[:"#{item}#{info[:suffix]}"] = [rarity, vkey]
    end
  end
  map.freeze
end

if defined?(ItemHandlers)
  use_proc = proc { |item|
    rarity, variant = EGG_ITEM_RARITY_MAP[item]
    next RarityEggSystem.pbUseEggItem(rarity, variant || :normal, item)
  }

  EGG_ITEM_RARITY_MAP.each_key do |item_sym|
    ItemHandlers::UseFromBag.add(item_sym, use_proc)
    ItemHandlers::UseInField.add(item_sym, use_proc)
  end
end