# encoding: UTF-8
#===============================================================================
# MOD: 183_Dex_Shiny
#-------------------------------------------------------------------------------
# Duas Pokedex novas — uma de Shiny e uma de Super Shiny — e um premio em Orbes
# por as ir preenchendo.
#
#   20 especies distintas em shiny        -> 1 Orbe
#   10 especies distintas em super shiny  -> 2 Orbes
#
# Este ficheiro e so o MOTOR: guardar, contar e pagar. O ecra vem a seguir.
#
# ⚠️ CONTA-SE NA CAPTURA, NAO NA POSSE.
#
# Se contasse o que esta nas caixas, vender ou soltar apagava a conquista — e o
# mercado de shinies e um pilar do jogo. A Pokedex normal ja funciona assim: o
# "capturado" fica para sempre depois de largares o bicho.
#
# ⚠️ E CONTA-SE NA CAPTURA TAMBEM POR SEGURANCA.
#
# Havia a tentacao de varrer as caixas de vez em quando e contar o que la
# estivesse. Nao serve: um Pokemon que veio por troca traz os campos que o OUTRO
# lado declarou. O `obtain_method` chega dentro do pacote —
#
#     pkmn.obtain_method = fetch_value(blob, "obtain_method").to_i
#
# — portanto um cliente modificado manda `0` (apanhado) num bicho trocado e a
# varredura acredita. O unico instante em que a informacao e de confianca e o da
# propria captura, na maquina que atirou a bola. E dai que este MOD ouve.
#
# De caminho isso mata o cenario das dez pessoas a passar o mesmo shiny umas as
# outras: quem regista e quem apanha, e o bicho muda de dono sem levar registo.
#
# ⚠️ O SORTEIO DA ORBE GRAVA ANTES DE SE VER O RESULTADO.
#
# E o mesmo buraco dos sacos de moedas, dos ovos de raridade e da roleta: sai a
# Orbe de Lima, o jogador fecha o jogo antes de gravar, volta a entrar e sorteia
# outra vez ate sair a que ele queria. A ordem obrigatoria e
#
#     marca as pagas -> sorteia -> poe na mochila -> GRAVA -> mostra
#
# Quando ele le o nome da Orbe, o nome ja esta em disco.
# Ver [[consumivel-consome-antes-de-sortear]].
#
# ⚠️ COMECA DO ZERO, POR DECISAO.
#
# Nao se varrem as caixas para dar credito ao que ja foi apanhado. Quem tem 249
# shinies comeca em 0/20 como toda a gente. Foi escolha do utilizador, e evita
# que os veteranos abram o sistema com uma duzia de Orbes na mao.
#===============================================================================

#-------------------------------------------------------------------------------
# ARMAZENAMENTO
#
# Vive no $PokemonGlobal (a seccao `global_metadata` do save), com acessores
# preguicosos em vez de um alias ao initialize: assim os saves antigos, que nao
# tem nenhum destes campos, respondem 0 e {} sem precisar de conversao.
#-------------------------------------------------------------------------------
class PokemonGlobalMetadata
  def anil_dex_shiny;  @anil_dex_shiny  ||= {}; end
  def anil_dex_super;  @anil_dex_super  ||= {}; end

  def anil_shiny_total;      @anil_shiny_total      ||= 0; end
  def anil_shiny_total=(v);  @anil_shiny_total       = v.to_i; end
  def anil_super_total;      @anil_super_total      ||= 0; end
  def anil_super_total=(v);  @anil_super_total       = v.to_i; end

  def anil_orbes_pagas_shiny;      @anil_orbes_pagas_shiny     ||= 0; end
  def anil_orbes_pagas_shiny=(v);  @anil_orbes_pagas_shiny      = v.to_i; end
  def anil_orbes_pagas_super;      @anil_orbes_pagas_super     ||= 0; end
  def anil_orbes_pagas_super=(v);  @anil_orbes_pagas_super      = v.to_i; end
end

module AnilDexShiny
  # 20 especies distintas em shiny valem 1 Orbe.
  POR_ORBE_SHINY   = 20
  ORBES_POR_SHINY  = 1
  # 10 especies distintas em super shiny valem 2.
  #
  # Nos saves auditados ha 249 shinies para 33 super shinies (~7,5 para 1), e
  # este ritmo paga o super shiny a 4x o shiny. Fica do lado conservador de
  # proposito: o caminho do super compensa, mas nao tanto que faca o outro nao
  # valer a pena.
  POR_ORBE_SUPER   = 10
  ORBES_POR_SUPER  = 2

  module_function

  def dados
    return nil unless defined?($PokemonGlobal) && $PokemonGlobal
    $PokemonGlobal
  rescue
    nil
  end

  # ── consulta (o ecra vive destes) ──────────────────────────────────────────
  def chave(especie)
    return nil if especie.nil?
    (especie.is_a?(Symbol) ? especie : especie.to_s.to_sym)
  rescue
    nil
  end

  def tem_shiny?(especie)
    d = dados
    return false unless d
    !!d.anil_dex_shiny[chave(especie)]
  rescue
    false
  end

  def tem_super?(especie)
    d = dados
    return false unless d
    !!d.anil_dex_super[chave(especie)]
  rescue
    false
  end

  def distintas_shiny
    dados ? dados.anil_dex_shiny.size : 0
  rescue
    0
  end
  def distintas_super
    dados ? dados.anil_dex_super.size : 0
  rescue
    0
  end
  def total_shiny
    dados ? dados.anil_shiny_total : 0
  rescue
    0
  end
  def total_super
    dados ? dados.anil_super_total : 0
  rescue
    0
  end

  # Quantas especies faltam para a proxima Orbe de cada caminho.
  def faltam_shiny
    POR_ORBE_SHINY - (distintas_shiny % POR_ORBE_SHINY)
  rescue
    POR_ORBE_SHINY
  end

  def faltam_super
    POR_ORBE_SUPER - (distintas_super % POR_ORBE_SUPER)
  rescue
    POR_ORBE_SUPER
  end

  # ── registo ────────────────────────────────────────────────────────────────
  #
  # Devolve true se alguma das duas dex ganhou uma especie nova.
  def registar_captura!(pkmn)
    d = dados
    return false unless d && pkmn
    return false if (pkmn.egg? rescue false)
    return false unless (pkmn.shiny? rescue false)

    sp = chave((pkmn.species rescue nil))
    return false unless sp

    # ⚠️ AS DUAS DEX SAO ESTANQUES.
    #
    # Um super shiny e tecnicamente shiny (o `super_shiny=` do motor forca o
    # `shiny = true`), e a primeira versao contava-o nas duas listas. Passa a
    # contar so na dele: um super shiny enche a casa da dex de Super Shiny e
    # NAO enche a da dex de Shiny.
    #
    # Assim as duas listas sao dois objectivos a serio, cada uma com o seu
    # ritmo de Orbes, em vez de uma ser um subconjunto gratuito da outra.
    # Na Pokedex NACIONAL entram os dois, como sempre — disso trata o motor.
    e_super = (pkmn.super_shiny? rescue false)

    novo = false

    if e_super
      d.anil_super_total = d.anil_super_total + 1
      unless d.anil_dex_super[sp]
        d.anil_dex_super[sp] = true
        novo = true
      end
    else
      d.anil_shiny_total = d.anil_shiny_total + 1
      unless d.anil_dex_shiny[sp]
        d.anil_dex_shiny[sp] = true
        novo = true
      end
    end

    d.anil_ultimo_super[sp] = e_super ? true : false

    registar_log("captura #{sp} shiny#{e_super ? "+super" : ""} — " \
                 "dex #{distintas_shiny}/#{POR_ORBE_SHINY} e #{distintas_super}/#{POR_ORBE_SUPER}")

    pagas = pagar_orbes!

    # ⚠️ O SAVE DA CAPTURA JA ACONTECEU. TEM DE SE GRAVAR OUTRA VEZ.
    #
    # O `Battle::Peer#pbStorePokemon` chama, la dentro,
    #
    #     $PokemonStorage.pbStoreCaught(pkmn)
    #
    # e o MOD 040 tem um gancho ai que dispara `save_and_upload_save_file`.
    # Ou seja: o jogo GRAVA antes de o metodo original devolver — e este
    # registo, que corre DEPOIS dele devolver, ficava so em memoria.
    #
    # O resultado era desconcertante: o Pokemon aparecia na caixa (estava no
    # ficheiro gravado) mas a dex mostrava-o como nao apanhado (o registo ficou
    # de fora). Ao voltar a entrar, o ficheiro nao tinha o registo e ele
    # "sumia do nada".
    #
    # Grava-se so quando alguma coisa mudou, e so se o pagamento ja nao gravou —
    # ele grava sempre que entrega uma Orbe.
    gravar_agora! if novo && pagas.zero?

    novo
  rescue => e
    registar_log("falha a registar: #{e.class}: #{e.message}")
    false
  end

  # ── premio ─────────────────────────────────────────────────────────────────
  def orbes_disponiveis
    cfg = (defined?(SUPER_SHINY_ORBS_CONFIG) ? SUPER_SHINY_ORBS_CONFIG : nil)
    return [] unless cfg.is_a?(Hash)
    cfg.keys.select { |id| (GameData::Item.exists?(id) rescue false) }
  rescue
    []
  end

  # Quantas Orbes o jogador ja MERECEU em cada caminho, no total.
  def devidas_shiny
    (distintas_shiny / POR_ORBE_SHINY) * ORBES_POR_SHINY
  rescue
    0
  end
  def devidas_super
    (distintas_super / POR_ORBE_SUPER) * ORBES_POR_SUPER
  rescue
    0
  end

  def pagar_orbes!
    d = dados
    return 0 unless d

    em_falta = (devidas_shiny - d.anil_orbes_pagas_shiny) +
               (devidas_super - d.anil_orbes_pagas_super)
    return 0 if em_falta <= 0

    lista = orbes_disponiveis
    if lista.empty?
      registar_log("ha #{em_falta} orbe(s) a pagar mas nenhuma esta registada no jogo")
      return 0
    end

    # ⚠️ Sorteia-se e poe-se na mochila ANTES de marcar como pago, mas so se
    # marca o que ENTROU mesmo. Com a mochila cheia o $bag.add devolve false; se
    # se marcasse na mesma, a Orbe perdia-se para sempre. Assim ela fica em
    # divida e sai na proxima captura.
    ganhas = []
    em_falta.times do
      orbe = lista.sample
      break unless orbe
      ok = ($bag.add(orbe, 1) rescue false)
      break unless ok
      ganhas << orbe
    end
    return 0 if ganhas.empty?

    # As pagas sobem primeiro pelo caminho do shiny e so depois pelo do super,
    # para a divida fechar de forma estavel independentemente da ordem do sorteio.
    ganhas.length.times do
      if d.anil_orbes_pagas_shiny < devidas_shiny
        d.anil_orbes_pagas_shiny = d.anil_orbes_pagas_shiny + 1
      else
        d.anil_orbes_pagas_super = d.anil_orbes_pagas_super + 1
      end
    end

    gravar!(ganhas)
    anunciar!(ganhas)
    ganhas.length
  rescue => e
    registar_log("falha a pagar orbes: #{e.class}: #{e.message}")
    0
  end

  # ⚠️ GRAVA ANTES DE MOSTRAR. Ver o aviso no topo do ficheiro.
  # Grava o save agora. Usa-se quando a dex mudou mas nao houve premio: sem
  # isto o registo ficava so em memoria ate ao autosave seguinte, e o save que a
  # propria captura dispara ja tinha passado.
  def gravar_agora!
    if defined?(AnilLanRework) && AnilLanRework.respond_to?(:gravar_ja!)
      AnilLanRework.gravar_ja!("dex_shiny")
    elsif defined?(Game) && Game.respond_to?(:save)
      Game.save
    end
  rescue => e
    registar_log("falha ao gravar a dex: #{e.class}: #{e.message}")
  end

  def gravar!(ganhas)
    if defined?(AnilLanRework) && AnilLanRework.respond_to?(:gravar_ja!)
      AnilLanRework.gravar_ja!("dex_shiny_orbe")
    elsif defined?(Game) && Game.respond_to?(:save)
      Game.save
    elsif defined?(SaveData) && SaveData.respond_to?(:save_to_file)
      SaveData.save_to_file(SaveData::FILE_PATH)
    end
    registar_log("orbes entregues e gravadas: #{ganhas.map(&:to_s).join(", ")}")
  rescue => e
    registar_log("falha ao gravar as orbes: #{e.class}: #{e.message}")
  end

  # ⚠️ POPUP, NAO pbMessage.
  #
  # O pbMessage para o jogo e obriga a carregar num botao — a meio de uma
  # caminhada, de uma cadeia de encontros ou de uma horda, e uma interrupcao que
  # nao se pediu. O premio nao precisa de confirmacao: precisa de ser visto.
  #
  # O add_popup com o item desenha o icone da Orbe ao lado do texto, que e
  # exactamente a apresentacao dos presentes do painel de admin e da revanche
  # (MOD 006). Uma coisa nova a menos para o jogador aprender.
  def anunciar!(ganhas)
    return if ganhas.empty?

    # A fanfarra de "apanhaste um item", uma vez so — e a mesma que o pbItemBall
    # toca quando se apanha uma bola do chao. Sem ela o premio passava
    # despercebido a quem estivesse a olhar para outro lado do ecra.
    #
    # Toca-se ANTES dos popups e uma unica vez: duas Orbes de uma vez sao um
    # premio, nao dois, e duas fanfarras sobrepostas soam a erro.
    (pbMEPlay("Item get") rescue (pbSEPlay("Item get") rescue nil))

    # Agrupa: duas Orbes iguais dao "2x", nao dois avisos seguidos.
    contagem = Hash.new(0)
    ganhas.each { |orbe| contagem[orbe] += 1 }

    contagem.each do |orbe, quantas|
      nome = (GameData::Item.get(orbe).name rescue orbe.to_s)
      texto = _INTL("Pokédex Shiny rendeu {1}x {2}!", quantas, nome)
      if defined?(AnilLanRework) && AnilLanRework.respond_to?(:add_popup)
        AnilLanRework.add_popup(texto, 8.0, orbe) rescue nil
      else
        registar_log("sem add_popup para anunciar: #{texto}")
      end
    end
  rescue
  end

  # Ficheiro proprio: os logs globais nao se ligam (travam o "recuperar
  # partida") — ver [[logs-nao-ligar-global]].
  def registar_log(texto)
    return unless (anil_diagnostico_ligado? rescue false)
    File.open("Data/anil_dex_shiny.txt", "a:UTF-8") do |f|
      f.puts("[#{Time.now.strftime('%d/%m %H:%M:%S')}] #{texto}")
    end
  rescue
  end
end

#-------------------------------------------------------------------------------
# OS ENCONTROS ("VISTO")
#
# Ate aqui so se registava a CAPTURA, e a dex abria toda a preto — nem dava para
# saber o que se tinha cruzado. Passa a haver os dois estados, como na Pokedex
# normal:
#
#     visto     -> apareceu a frente, mesmo que tenha fugido -> sprite a cores
#     capturado -> e teu                                     -> bola cheia + estrela
#
# ⚠️ SO O "CAPTURADO" CONTA PARA AS ORBES.
#
# Ver um shiny nao e um feito: um encontro que fugiu nao pode valer o mesmo que
# um que se apanhou. O "visto" serve para a dex se ler — mostra o que ja
# apareceu — e nada mais.
#
# ⚠️ E O "VISTO" DESTA DEX NAO E O DA NACIONAL.
#
# Ter visto um Heracross normal nao diz nada sobre o Heracross shiny. Sao
# listas independentes: so entra aqui quem apareceu MESMO em shiny.
#-------------------------------------------------------------------------------
class PokemonGlobalMetadata
  def anil_visto_shiny;  @anil_visto_shiny  ||= {}; end
  def anil_visto_super;  @anil_visto_super  ||= {}; end
  def anil_ultimo_super; @anil_ultimo_super ||= {}; end
end

module AnilDexShiny
  module_function

  def visto_shiny?(especie)
    d = dados
    return false unless d
    return true if tem_shiny?(especie)   # apanhado implica visto
    !!d.anil_visto_shiny[chave(especie)]
  rescue
    false
  end

  def visto_super?(especie)
    d = dados
    return false unless d
    return true if tem_super?(especie)
    !!d.anil_visto_super[chave(especie)]
  rescue
    false
  end

  # O ultimo encontro brilhante desta especie foi um super shiny?
  def ultimo_super?(especie)
    d = dados
    return false unless d
    !!d.anil_ultimo_super[chave(especie)]
  rescue
    false
  end

  def vistas_shiny;
 (dados ? dados.anil_visto_shiny.size : 0); rescue 0; end
  def vistas_super; (dados ? dados.anil_visto_super.size : 0); rescue 0; end

  # Chamado quando um shiny aparece a frente do jogador. Nao paga nada, nao
  # grava nada: e so memoria para o ecra. A gravacao vem no autosave normal.
  def registar_visto!(especie, e_shiny, e_super)
    return false unless e_shiny
    d = dados
    return false unless d
    sp = chave(especie)
    return false unless sp

    novo = false
    if e_super
      unless d.anil_visto_super[sp]
        d.anil_visto_super[sp] = true
        novo = true
      end
    else
      unless d.anil_visto_shiny[sp]
        d.anil_visto_shiny[sp] = true
        novo = true
      end
    end

    # Guarda-se se o ULTIMO encontro brilhante desta especie foi super. E o que
    # a tela de registo precisa de saber para escolher entre o sprite shiny e o
    # shiny com a rotacao de matiz — o last_form_seen do motor so guarda um
    # booleano "shiny", nao distingue os dois.
    d.anil_ultimo_super[sp] = e_super ? true : false
    registar_log("visto #{sp} shiny#{e_super ? "+super" : ""}") if novo
    novo
  rescue
    false
  end
end

#-------------------------------------------------------------------------------
# O GANCHO DO "VISTO"
#
# O Player::Pokedex#register e o ponto por onde passa tudo o que o jogador ve —
# o encontro selvagem, o Pokemon do treinador, a captura. Recebe ou um objeto
# Pokemon ou os campos soltos, portanto le-se o que houver.
#
# Nao precisa de reinstalacao pos-plugin: nenhum plugin redefine esta classe
# (varridos os 104), ao contrario do que acontece com o pbStorePokemon e o
# setIconBitmap.
#-------------------------------------------------------------------------------
class Player
  class Pokedex
    alias anil_dexshiny_register register unless method_defined?(:anil_dexshiny_register)

    def register(species, gender = 0, form = 0, shiny = false, should_refresh_dexes = true)
      resultado = anil_dexshiny_register(species, gender, form, shiny, should_refresh_dexes)
      begin
        # O objeto sabe mais do que os argumentos: um battler traz o
        # super_shiny?, que nao viaja na assinatura.
        e_shiny = (species.respond_to?(:shiny?) ? species.shiny? : shiny) rescue shiny
        e_super = (species.respond_to?(:super_shiny?) ? species.super_shiny? : false) rescue false
        if e_shiny
          sp = (species.respond_to?(:species) ? species.species : species)
          AnilDexShiny.registar_visto!(sp, e_shiny, e_super)
        end
      rescue
      end
      resultado
    end
  end
end

#-------------------------------------------------------------------------------
# O GANCHO DE CAPTURA
#
# ⚠️ E no Battle::Peer, e nao no CatchAndStoreMixin.
#
# O mixin tem dois ramos — equipa e caixa — e o plugin `[v21.1 Hotfixes] Battle
# bug fixes.rb` REDEFINE o pbStorePokemon dele de raiz, sem alias, apagando
# qualquer gancho posto la (ver [[gancho-captura-plugin-clobber]]).
#
# O Battle::Peer#pbStorePokemon e o degrau abaixo: o mixin chama-o SEMPRE, venha
# o bicho parar a equipa ou a caixa, e nenhum plugin lhe toca. Um gancho so, nos
# dois caminhos, e imune a reescrita.
#
# Mesmo assim reinstala-se no apply_post_plugin_patches, pelo mesmo motivo do
# MOD 155: se um dia alguem reabrir a classe depois de nos, queremos voltar a
# envolver o metodo FINAL. O @seq da um nome novo a cada instalacao e a
# comparacao do instance_method torna a chamada idempotente.
#-------------------------------------------------------------------------------
module AnilDexShinyGancho
  module_function

  def instalar!
    return false unless defined?(Battle::Peer)
    actual = Battle::Peer.instance_method(:pbStorePokemon)
    return false if @gancho && @gancho == actual

    @seq = (@seq || 0) + 1
    antigo = :"anil_dexshiny_pbStorePokemon_#{@seq}"
    Battle::Peer.send(:alias_method, antigo, :pbStorePokemon)
    Battle::Peer.send(:define_method, :pbStorePokemon) do |player, pkmn|
      resultado = send(antigo, player, pkmn)
      begin
        # So o jogador local. Em coop o peer e chamado com o treinador que
        # recebe; registar a captura do parceiro na dex de quem esta a ver seria
        # dar a conquista a quem nao atirou a bola.
        mesmo = (defined?($player) && $player && player.equal?($player))
        AnilDexShiny.registar_captura!(pkmn) if mesmo
      rescue
      end
      resultado
    end

    @gancho = Battle::Peer.instance_method(:pbStorePokemon)
    true
  rescue => e
    AnilDexShiny.registar_log("falha a instalar o gancho: #{e.class}: #{e.message}")
    false
  end
end

AnilDexShinyGancho.instalar! rescue nil

#-------------------------------------------------------------------------------
# EVOLUIR TAMBEM CONTA.
#
# ⚠️ O GANCHO DA CAPTURA NAO APANHA UMA EVOLUCAO.
#
# Ele esta no `Battle::Peer#pbStorePokemon`, que so corre quando uma bola pega.
# Quem apanha um Flabebe super shiny e o evolui fica com uma Floette super shiny
# na equipa, registada na Pokedex nacional — e ausente da nossa, porque nunca
# passou por uma captura.
#
# Do lado do jogador isso nao se distingue de um bug: ele TEM o bicho, ve-o na
# dex normal, e na de super shiny aparece por apanhar. O motor trata a evolucao
# como aquisicao (faz `register` e `set_owned` logo a seguir a trocar a
# especie); aqui faz-se o mesmo.
#
# A especie nova conta como distinta, portanto pode fechar um lote e pagar uma
# Orbe. E deliberado: o Flabebe deu duas especies porque o jogador o levou ate
# la, e e a mesma regra da Pokedex nacional.
#-------------------------------------------------------------------------------
module AnilDexShinyGanchoEvolucao
  module_function

  def instalar!
    return false unless defined?(PokemonEvolutionScene)
    return false unless PokemonEvolutionScene.method_defined?(:pbEvolutionSuccess)
    actual = PokemonEvolutionScene.instance_method(:pbEvolutionSuccess)
    return false if @gancho && @gancho == actual

    @seq = (@seq || 0) + 1
    antigo = :"anil_dexshiny_pbEvolutionSuccess_#{@seq}"
    PokemonEvolutionScene.send(:alias_method, antigo, :pbEvolutionSuccess)
    PokemonEvolutionScene.send(:define_method, :pbEvolutionSuccess) do
      resultado = send(antigo)
      begin
        # Depois do original: e ele que troca a especie do objecto. Antes, o
        # @pokemon ainda era o Flabebe e registava-se a especie errada.
        pkmn = instance_variable_get(:@pokemon)
        AnilDexShiny.registar_captura!(pkmn) if pkmn
      rescue => e
        AnilDexShiny.registar_log("falha ao registar a evolucao: #{e.class}: #{e.message}") rescue nil
      end
      resultado
    end

    @gancho = PokemonEvolutionScene.instance_method(:pbEvolutionSuccess)
    true
  rescue => e
    AnilDexShiny.registar_log("falha a instalar o gancho da evolucao: #{e.class}: #{e.message}") rescue nil
    false
  end
end

AnilDexShinyGanchoEvolucao.instalar! rescue nil

module AnilLanRework
  class << self
    unless method_defined?(:anil_dexshiny_orig_apply_post_plugin_patches)
      alias_method :anil_dexshiny_orig_apply_post_plugin_patches, :apply_post_plugin_patches rescue nil
    end

    def apply_post_plugin_patches
      anil_dexshiny_orig_apply_post_plugin_patches rescue nil
      AnilDexShinyGancho.instalar! rescue nil
      AnilDexShinyGanchoEvolucao.instalar! rescue nil
    end
  end
end

(AnilLanRework.log("183_Dex_Shiny carregado") rescue nil)
