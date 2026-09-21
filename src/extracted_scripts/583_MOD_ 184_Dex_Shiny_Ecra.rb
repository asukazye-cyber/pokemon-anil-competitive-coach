# encoding: UTF-8
#===============================================================================
# MOD: 184_Dex_Shiny_Ecra
#-------------------------------------------------------------------------------
# O ecra das duas Pokedex novas do MOD 183.
#
# Na Pokedex, esquerda/direita passam entre tres modos:
#
#     Pokédex Nacional  <->  Pokédex Shiny  <->  Pokédex Super Shiny
#
# ⚠️ NAO SE MEXE NA LISTA, SO NO QUE ELA MOSTRA.
#
# A tentacao era filtrar o @dexlist e deixar so os apanhados em shiny. Nao se
# faz, por duas razoes:
#
#   1. o @dexlist e reconstruido pela pesquisa, pelo pbDexEntry e pelo
#      pbCloseSearch — havia quatro sitios a manter em acordo com o modo, e
#      qualquer um que escapasse devolvia a lista errada;
#   2. com a dex shiny a comecar VAZIA, a lista filtrada abria sem uma unica
#      linha. Um ecra vazio nao se percebe: nao da para ver o que falta.
#
# Entao a lista e sempre a mesma e o que muda e a marcacao.
#
# ⚠️ A SETA E A DO JOGO, NAO UMA DESENHADA A MAO.
#
# A primeira versao desenhava um triangulo pixel a pixel e saia uma bolinha
# disforme. O jogo ja tem `Graphics/UI/right_arrow` — 8 frames de 40x28, a mesma
# seta animada que a mochila usa para dizer "ha mais bolsos, carrega para o
# lado". Reaproveita-la nao e so mais bonito: e o mesmo simbolo que o jogador ja
# aprendeu noutro ecra, portanto nao ha nada de novo para perceber.
#
# E como ela vive no @sprites, o pbUpdateSpriteHash da cena anima-a sozinho —
# nao e preciso codigo nenhum de piscar.
#===============================================================================

module AnilDexShinyEcra
  MODOS = [:normal, :shiny, :super]

  # A estrela vem do iv_star_red, que ja existe. A roxa e a MESMA imagem com o
  # matiz rodado — mais um ficheiro so para isso nao se justifica.
  HUE_ESTRELA_SUPER = 275

  module_function

  def modo;        @modo ||= :normal; end
  def modo=(v);    @modo = v;         end
  def normal?;     modo == :normal;   end
  def shiny?;      modo == :shiny;    end
  def super_dex?;  modo == :super;    end

  def repor!; @modo = :normal; end

  def avancar!(passo)
    i = MODOS.index(modo) || 0
    @modo = MODOS[(i + passo) % MODOS.length]
  end

  def titulo
    case modo
    when :shiny then _INTL("Pokédex Shiny")
    when :super then _INTL("Pokédex Super Shiny")
    else nil   # nil = deixa o titulo original (o nome da dex em uso)
    end
  end

  # Ja apareceu a frente do jogador, no modo em curso? (o apanhado conta)
  def vista?(species)
    case modo
    when :shiny then (AnilDexShiny.visto_shiny?(species) rescue false)
    when :super then (AnilDexShiny.visto_super?(species) rescue false)
    else false
    end
  end

  # A especie ja foi apanhada, no modo em curso?
  def marcada?(species)
    case modo
    when :shiny then (AnilDexShiny.tem_shiny?(species) rescue false)
    when :super then (AnilDexShiny.tem_super?(species) rescue false)
    else false
    end
  end

  # As duas linhas de contagem, ja montadas e para centrar.
  #
  # O "Avistados" nao quer dizer nada numa dex de shiny — ou apanhaste ou nao.
  # Ficam os dois numeros que interessam: quantas especies tens e quantas faltam
  # para a proxima Orbe.
  def contadores
    case modo
    when :shiny
      [_INTL("Capturado: {1}", (AnilDexShiny.distintas_shiny rescue 0)),
       _INTL("Faltam: {1}",    (AnilDexShiny.faltam_shiny rescue 20))]
    when :super
      [_INTL("Capturado: {1}", (AnilDexShiny.distintas_super rescue 0)),
       _INTL("Faltam: {1}",    (AnilDexShiny.faltam_super rescue 10))]
    else
      nil
    end
  end

  # Escreve uma linha por especie, uma vez so, num ficheiro proprio.
  #
  # Serve para a pergunta "o hue esta a ser aplicado?", que nao se responde a
  # olho: um super shiny com o hue por aplicar parece so um shiny.
  def registar_hue(species, hue, aplicado)
    return unless (anil_diagnostico_ligado? rescue false)
    @vistos ||= {}
    return if @vistos[species]
    @vistos[species] = true
    File.open("Data/anil_dex_shiny.txt", "a:UTF-8") do |f|
      f.puts("[#{Time.now.strftime('%d/%m %H:%M:%S')}] hue #{species}=#{hue} aplicado=#{aplicado}")
    end
  rescue
  end

  # A estrela do modo em curso, ou nil na Nacional.
  #
  # Fica em cache e nao se liberta: sao dois bitmaps de 14x14, e recarrega-los a
  # cada linha desenhada custava mais do que os poucos bytes que ocupam.
  def estrela
    return nil if normal?
    @estrelas ||= {}
    chave = modo
    return @estrelas[chave] if @estrelas.key?(chave)
    hue = super_dex? ? HUE_ESTRELA_SUPER : 0
    bmp = nil
    begin
      caminho = "Graphics/Pictures/iv_star_red"
      # ⚠️ O hue vai ao CONSTRUTOR. Um hue_change rodava o bitmap PARTILHADO da
      # RPG::Cache e a estrela vermelha ficava roxa no resto do jogo.
      bmp = AnimatedBitmap.new(caminho, hue) if pbResolveBitmap(caminho)
    rescue
      bmp = nil
    end
    @estrelas[chave] = bmp
  end
end

#-------------------------------------------------------------------------------
# A LISTA: bola de apanhado + estrela ao lado do nome
#-------------------------------------------------------------------------------
class Window_Pokedex
  alias anil_dexshiny_drawItem drawItem unless method_defined?(:anil_dexshiny_drawItem)

  def drawItem(index, count, rect)
    return anil_dexshiny_drawItem(index, count, rect) if AnilDexShinyEcra.normal?
    return if index >= self.top_row + self.page_item_max

    rect = Rect.new(rect.x + 16, rect.y, rect.width - 16, rect.height)
    entrada = @commands[index]
    return unless entrada
    species = entrada[:species]
    numero  = entrada[:number]
    numero -= 1 if entrada[:shift]

    # ⚠️ NAO SE OLHA PARA A DEX NACIONAL. As duas dex sao independentes.
    #
    # A primeira versao mostrava o nome de tudo o que ele ja tinha visto na
    # Nacional — e ai a dex de shiny abria meia preenchida sem ele ter apanhado
    # um unico shiny. O que ele sabe de um Heracross normal nao lhe diz nada
    # sobre o Heracross shiny: essa lista comeca do zero e enche-se sozinha.
    marcado = AnilDexShinyEcra.marcada?(species)
    visto   = AnilDexShinyEcra.vista?(species)

    # Tres estados, como na Pokedex normal — so que medidos NESTA dex:
    #   nem visto  -> sem bola, sem nome
    #   visto      -> bola vazia, nome
    #   capturado  -> bola cheia, nome, estrela
    if marcado
      pbCopyBitmap(self.contents, @pokeballOwn.bitmap, rect.x - 6, rect.y + 10) rescue nil
    elsif visto
      pbCopyBitmap(self.contents, @pokeballSeen.bitmap, rect.x - 6, rect.y + 10) rescue nil
    end

    num_text  = sprintf("%03d", numero)
    name_text = visto ? entrada[:name] : "----------"

    pbDrawShadowText(self.contents, rect.x + 36, rect.y + 6, rect.width, rect.height,
                     num_text, self.baseColor, self.shadowColor)
    pbDrawShadowText(self.contents, rect.x + 84, rect.y + 6, rect.width, rect.height,
                     name_text, self.baseColor, self.shadowColor)

    # A estrela vai depois do nome, e SO nos apanhados: uma estrela em cada linha
    # nao distinguia nada, e o que ela tem de dizer e "esta ja e tua".
    if marcado
      estrela = AnilDexShinyEcra.estrela
      if estrela && estrela.bitmap && !(estrela.bitmap.disposed? rescue true)
        largura = (self.contents.text_size(name_text).width rescue 0)
        self.contents.blt(rect.x + 90 + largura, rect.y + 12, estrela.bitmap,
                          Rect.new(0, 0, estrela.bitmap.width, estrela.bitmap.height))
      end
    end
  rescue
    anil_dexshiny_drawItem(index, count, rect) rescue nil
  end
end

#-------------------------------------------------------------------------------
# O CABECALHO, OS CONTADORES E A SETA
#-------------------------------------------------------------------------------
class PokemonPokedex_Scene
  alias anil_dexshiny_pbStartScene pbStartScene unless method_defined?(:anil_dexshiny_pbStartScene)
  alias anil_dexshiny_pbEndScene   pbEndScene   unless method_defined?(:anil_dexshiny_pbEndScene)
  alias anil_dexshiny_pbRefresh    pbRefresh    unless method_defined?(:anil_dexshiny_pbRefresh)

  def pbStartScene(*args)
    # Abre sempre na Nacional. Guardar o modo entre aberturas confundia quem
    # fechasse na dex shiny e voltasse la sem se lembrar porque.
    AnilDexShinyEcra.repor!
    resultado = anil_dexshiny_pbStartScene(*args)
    begin
      # A mesma seta animada da mochila: 8 frames de 40x28. O `play` poe-a a
      # correr e o pbUpdateSpriteHash da cena trata do resto.
      seta = AnimatedSprite.new("Graphics/UI/right_arrow", 8, 40, 28, 2, @viewport)
      seta.x = (Graphics.width / 2) + 122
      seta.y = 4
      seta.z = 99999
      seta.play
      @sprites["anil_seta_dex"] = seta
    rescue => e
      AnilLanRework.log("[DEXSHINY] seta nao carregou: #{e.class}: #{e.message}") rescue nil
    end
    resultado
  end

  def pbEndScene(*args)
    begin
      s = @sprites["anil_seta_dex"]
      s.dispose if s && !(s.disposed? rescue true)
      @sprites.delete("anil_seta_dex")
    rescue
    end
    anil_dexshiny_pbEndScene(*args)
  end

  def pbRefresh
    anil_dexshiny_pbRefresh
    return if AnilDexShinyEcra.normal?

    # ⚠️ Escreve-se POR CIMA do que o original ja desenhou.
    #
    # Reimplementar o pbRefresh inteiro era herdar as barras de scroll, as
    # silhuetas e o resto — e ficar a mante-los em duplicado. Aqui so se tapam
    # as duas zonas que mudam: o titulo e o quadro das contagens.
    begin
      overlay = @sprites["overlay"].bitmap
      base    = Color.new(88, 88, 80)
      shadow  = Color.new(168, 184, 184)

      titulo = AnilDexShinyEcra.titulo
      if titulo
        overlay.fill_rect(120, 4, 300, 34, Color.new(0, 0, 0, 0))
        pbDrawTextPositions(overlay, [
          [titulo, (Graphics.width / 2) + 40, 13, :center,
           Color.new(248, 248, 248), Color.black]
        ])
      end

      # O nome grande, por cima do sprite, some quando a especie ainda nao
      # apareceu NESTA dex.
      #
      # ⚠️ O criterio e o "visto", nao o "capturado".
      #
      # Ficou a olhar para o marcada? de quando so havia dois estados, e nunca
      # foi actualizado ao acrescentar o visto. Resultado: uma especie ja vista
      # em shiny mostrava o nome NA LISTA e o sprite A CORES, mas a caixa do
      # nome por cima do sprite ficava em branco — os tres sitios a discordar
      # sobre a mesma especie.
      especie_actual = (@sprites["pokedex"].species rescue nil)
      unless AnilDexShinyEcra.vista?(especie_actual)
        overlay.fill_rect(20, 50, 190, 32, Color.new(0, 0, 0, 0))
      end

      c = AnilDexShinyEcra.contadores
      if c
        # 112 e o centro do painel da esquerda — o mesmo x que o ecra original
        # ja usa para centrar o "Resultados:" da pesquisa.
        overlay.fill_rect(20, 306, 190, 72, Color.new(0, 0, 0, 0))
        pbDrawTextPositions(overlay, [
          [c[0], 112, 314, :center, base, shadow],
          [c[1], 112, 346, :center, base, shadow]
        ])
      end
    rescue => e
      AnilLanRework.log("[DEXSHINY] falha a desenhar: #{e.class}: #{e.message}") rescue nil
    end
  end
end

#-------------------------------------------------------------------------------
# O SPRITE GRANDE
#
# Na dex de shiny mostrava-se a aparencia NORMAL — o ecra dizia "Pokédex Shiny" e
# desenhava o bicho como ele aparece sempre. Tirava o sentido a coisa toda.
#
# ⚠️ O SUPER SHINY NAO TEM SPRITE PROPRIO: TEM UM HUE.
#
# A cor sai de uma rotacao de matiz por cima do sprite SHINY, e o hue de cada
# especie e derivado do nome dela (o `hue_natural` do MOD 154, que le o
# @super_shiny_hue e, na falta dele, calcula-o a partir do id). O que se mostra
# aqui e a cor com que aquela especie aparece no mato.
#
# ⚠️ O HUE VAI AO CONSTRUTOR, NUNCA AO hue_change.
#
# Um AnimatedBitmap normal partilha o bitmap da RPG::Cache com o resto do jogo.
# Chamar-lhe hue_change roda a imagem PARTILHADA, a rotacao acumula a cada
# redesenho e escapa para todo o lado — o Pokemon aparecia com a cor errada na
# equipa, na batalha, no seguidor. Ver [[hue-bitmap-partilhado-cache]].
#
# ⚠️ E O QUE AINDA NAO SE APANHOU FICA A PRETO E BRANCO.
#
# Mostrar a cores um shiny que o jogador nunca apanhou era entregar-lhe a
# recompensa antes de a ganhar. A cinzento ele ve a FORMA — sabe o que anda a
# procurar — mas a cor so aparece quando for dele. E o mesmo contrato da
# silhueta da dex normal, um degrau mais suave.
#-------------------------------------------------------------------------------
class PokemonSprite
  # Como o setSpeciesBitmap, mas com uma rotacao de matiz propria.
  # ⚠️ O SPRITE E MONTADO PELO DBK; NOS SO RODAMOS A COR NO FIM.
  #
  # A primeira versao fabricava um `AnimatedBitmap` proprio e metia-o no sprite.
  # Isso parte de duas maneiras com o plugin [DBK] Animated Pokemon System:
  #
  # 1. Os ficheiros de sprite do DBK sao FOLHAS de varios frames lado a lado. O
  #    recorte de um frame vive no `DeluxeBitmapWrapper` (constrict_x/y/w/h). Um
  #    AnimatedBitmap cru nao traz esse recorte, e o sprite aparecia com a folha
  #    inteira desenhada — o Pokemon repetido ao infinito na horizontal.
  #
  # 2. O `pbSetDisplay` do DBK chama `@_iconbitmap.constrict_x=`, que so existe
  #    no wrapper dele. Com um AnimatedBitmap la dentro rebentava com
  #    `undefined method 'constrict_x=' for #<AnimatedBitmap>` — inclusive por
  #    cima da animacao de evolucao, fechando o jogo.
  #
  # A saida e nao competir com ele: deixa-se o `setSpeciesBitmap` montar o
  # sprite como o DBK quer, e usa-se o `hue_change` do PROPRIO wrapper. Ele roda
  # os bitmaps DELE (`@bitmaps`), que sao recortes proprios e nao a imagem
  # partilhada da RPG::Cache — portanto a cor nao escapa para o resto do jogo,
  # que era o outro perigo (ver [[hue-bitmap-partilhado-cache]]). O
  # `changedHue?` garante que nao se roda duas vezes.
  #
  # ⚠️ Sprite NORMAL, nao o shiny: um super shiny e a cor base com a rotacao por
  # cima. Pedir o shiny e depois rodar dava uma terceira cor, que nao e a de
  # ninguem.
  def anil_setSpeciesBitmapHue(species, gender = 0, form = 0, hue = 0)
    return false if hue.to_i == 0
    setSpeciesBitmap(species, gender, form, false)
    bmp = instance_variable_get(:@_iconbitmap)
    return false unless bmp
    if bmp.respond_to?(:hue_change) && bmp.respond_to?(:changedHue?)
      bmp.hue_change(hue) unless bmp.changedHue?
      return true
    end

    # Sem o DBK nao ha folhas de frames nem wrapper: o caminho antigo serve, e e
    # o unico que ha.
    ficheiro = GameData::Species.sprite_filename(species, form, gender, false)
    return false unless ficheiro
    proprio = AnimatedBitmap.new(ficheiro, hue)
    return false unless proprio && proprio.bitmap
    antigo = instance_variable_get(:@_iconbitmap)
    antigo.dispose if antigo && !(antigo.disposed? rescue true)
    instance_variable_set(:@_iconbitmap, proprio)
    self.bitmap = proprio.bitmap
    self.make_grey_if_fainted = false
    instance_variable_set(:@is_egg, false)
    changeOrigin
    true
  rescue
    false
  end
end

#-------------------------------------------------------------------------------
# ⚠️ O setIconBitmap TEM DE SER INSTALADO DEPOIS DOS PLUGINS.
#
# O plugin `[DBK] Animated Pokémon System` ([003] Pokemon UI.rb) REDEFINE o
# PokemonPokedex_Scene#setIconBitmap de raiz, sem alias:
#
#     def setIconBitmap(species)
#       gender, form, _shiny = $player.pokedex.last_form_seen(species)
#       @sprites["icon"].setSpeciesBitmap(species, gender, form, false)   # <- false!
#       @sprites["icon"].pbSetDisplay([112, 196, 224, 216], species_id)
#     end
#
# Como os plugins carregam DEPOIS de todos os MODs, o meu alias apanhava a
# versao do script base e era apagado a seguir — codigo morto. E repara no
# `false` do quarto argumento: mesmo que corresse, ele pede sempre o sprite
# NORMAL. Era isso que se via na dex de shiny.
#
# Mesma armadilha do `Battle bug fixes.rb` com o pbStorePokemon. A saida e a
# mesma: envolver o metodo FINAL, seja ele de quem for, e reinstalar no
# apply_post_plugin_patches. O @seq da um nome novo a cada instalacao, para
# nunca se envolver duas vezes o mesmo alias, e a comparacao do instance_method
# torna a chamada idempotente.
#
# ⚠️ E o pbSetDisplay chama-se no fim, uma so vez.
#
# Ele nao troca o bitmap — so le o @_iconbitmap e calcula a posicao. Portanto
# poe-se o sprite primeiro e posiciona-se depois, exactamente como o plugin faz.
#-------------------------------------------------------------------------------
module AnilDexShinyGanchoIcone
  module_function

  def instalar!
    return false unless defined?(PokemonPokedex_Scene)
    actual = PokemonPokedex_Scene.instance_method(:setIconBitmap)
    return false if @gancho && @gancho == actual

    @seq = (@seq || 0) + 1
    antigo = :"anil_dexshiny_setIconBitmap_#{@seq}"
    PokemonPokedex_Scene.send(:alias_method, antigo, :setIconBitmap)

    PokemonPokedex_Scene.send(:define_method, :setIconBitmap) do |species|
      begin
        if AnilDexShinyEcra.normal? || species.nil?
          send(antigo, species)
          # ⚠️ LIMPAR O PRETO AO VOLTAR A NACIONAL.
          #
          # A silhueta das dex novas faz-se com `color = Color.black`, e o
          # `color` fica agarrado ao SPRITE, nao ao bitmap: o metodo original
          # troca a imagem mas nunca lhe mexe. Resultado — abrir a Nacional,
          # passar para o lado e voltar deixava tudo preto, mesmo o que estava
          # capturado, porque o preto tinha sido posto por nos e ninguem o
          # tirava. Na Nacional nao se mexe em nada: e so repor o neutro.
          begin
            alvo = @sprites["icon"]
            alvo.color = Color.new(0, 0, 0, 0) if alvo && !(alvo.disposed? rescue true)
          rescue
          end
        else
          visto = AnilDexShinyEcra.vista?(species)
          gender, form, _shiny = ($player.pokedex.last_form_seen(species) rescue [0, 0, false])
          gender = gender.to_i
          form   = form.to_i

          if !visto
            # ⚠️ A SILHUETA FAZ-SE COM O `color`, NAO COM O `tone`.
            #
            # Duas rondas a por `tone = Tone.new(-255,-255,-255,255)` e o bicho
            # continuava a aparecer a cores. O plugin DBK gere o tom dos sprites
            # dele, e a silhueta que ELE proprio desenha usa outra propriedade:
            #
            #     self.color = Color.black      ([005] Pokemon Sprites.rb:295)
            #
            # O `color` mistura o sprite com a cor dada, ate a opacidade dela —
            # a 255 fica preto solido, que e exactamente "atirar preto forte por
            # cima". E, ao contrario do tone, ninguem lho mexe.
            #
            # Pede-se o sprite SHINY para a silhueta ter o contorno certo nas
            # especies em que shiny e normal diferem de feitio.
            @sprites["icon"].setSpeciesBitmap(species, gender, form, true)
            @sprites["icon"].tone  = Tone.new(0, 0, 0, 0)
            @sprites["icon"].color = Color.new(0, 0, 0, 255)
          else
            feito = false
            if AnilDexShinyEcra.super_dex?
              hue = (defined?(AnilDexCores) ? (AnilDexCores.hue_natural(species, form) rescue 0) : 0).to_i
              feito = @sprites["icon"].anil_setSpeciesBitmapHue(species, gender, form, hue) if hue != 0
              # ⚠️ Deixa rasto. O hue e a unica coisa aqui que nao da para
              # confirmar sem correr o jogo: se sair 0, ou se o
              # anil_setSpeciesBitmapHue devolver false, o Pokemon aparece como
              # shiny simples e nao ha nada no ecra que o explique.
              #
              # A formula TEM de bater com a do plugin DBK ([004] Game Data.rb):
              #     ((especie.to_s.sum % 7) + 1) * 45
              # que e exactamente a que o AnilDexCores.hue_natural usa —
              # conferido linha a linha.
              AnilDexShinyEcra.registar_hue(species, hue, feito)
            end
            @sprites["icon"].setSpeciesBitmap(species, gender, form, true) unless feito
            @sprites["icon"].tone  = Tone.new(0, 0, 0, 0)
            # ⚠️ Limpar o preto. Sem isto, o primeiro Pokemon por descobrir
            # deixava o sprite preto e TODOS os seguintes apareciam pretos —
            # o `color` fica agarrado ao sprite, nao ao bitmap.
            @sprites["icon"].color = Color.new(0, 0, 0, 0)
          end

          # Posiciona como o plugin posiciona. Nao troca o bitmap: so le o
          # @_iconbitmap e calcula os deslocamentos.
          if @sprites["icon"].respond_to?(:pbSetDisplay)
            id = (GameData::Species.get_species_form(species, form)&.id rescue nil)
            @sprites["icon"].pbSetDisplay([112, 196, 224, 216], id) rescue nil
          end
        end
      rescue => e
        # ⚠️ NAO se cai no metodo original aqui.
        #
        # Era o que estava, e foi o que escondeu este bug durante duas rondas:
        # qualquer falha nossa acabava a desenhar o Pokemon a cores, que e o
        # unico desfecho que nao se pode ter. Falhar deixando o sprite como esta
        # e sempre mais seguro do que revelar o premio.
        AnilLanRework.log("[DEXSHINY] falha no sprite: #{e.class}: #{e.message}") rescue nil
      end
    end

    @gancho = PokemonPokedex_Scene.instance_method(:setIconBitmap)
    true
  rescue => e
    AnilLanRework.log("[DEXSHINY] falha a instalar o gancho do icone: #{e.class}: #{e.message}") rescue nil
    false
  end
end

AnilDexShinyGanchoIcone.instalar! rescue nil

module AnilLanRework
  class << self
    unless method_defined?(:anil_dexshiny_icone_orig_apply_post_plugin_patches)
      alias_method :anil_dexshiny_icone_orig_apply_post_plugin_patches, :apply_post_plugin_patches rescue nil
    end

    def apply_post_plugin_patches
      anil_dexshiny_icone_orig_apply_post_plugin_patches rescue nil
      AnilDexShinyGanchoIcone.instalar! rescue nil
    end
  end
end

#-------------------------------------------------------------------------------
# O INPUT
#
# O pbPokedex do script base nao usa LEFT nem RIGHT — o cursor anda em UP/DOWN e
# o resto sao ACTION, BACK, USE e SPECIAL. As duas teclas estao livres.
#-------------------------------------------------------------------------------
class PokemonPokedex_Scene
  alias anil_dexshiny_pbPokedex pbPokedex unless method_defined?(:anil_dexshiny_pbPokedex)

  def pbPokedex
    pbActivateWindow(@sprites, "pokedex") do
      loop do
        Graphics.update
        Input.update
        oldindex = @sprites["pokedex"].index
        pbUpdate
        if oldindex != @sprites["pokedex"].index
          $PokemonGlobal.pokedexIndex[pbGetSavePositionIndex] = @sprites["pokedex"].index if !@searchResults
          pbRefresh
        end

        # ── a troca de dex ────────────────────────────────────────────────────
        # So fora da pesquisa: com resultados no ecra, a lista ja nao e a da dex
        # e a contagem em baixo diz outra coisa. Mudar de modo ali baralhava as
        # duas leituras.
        if !@searchResults && (Input.trigger?(Input::RIGHT) || Input.trigger?(Input::LEFT))
          AnilDexShinyEcra.avancar!(Input.trigger?(Input::RIGHT) ? 1 : -1)
          (pbPlayCursorSE rescue nil)
          @sprites["pokedex"].refresh rescue nil
          pbRefresh
          next
        end

        if Input.trigger?(Input::ACTION)
          pbSEPlay("GUI pokedex open")
          @sprites["pokedex"].active = false
          pbDexSearch
          @sprites["pokedex"].active = true
        elsif Input.trigger?(Input::BACK)
          pbPlayCloseMenuSE
          if @searchResults
            pbCloseSearch
          else
            break
          end
        elsif Input.trigger?(Input::USE)
          # Nas dex novas a ficha so abre no que ja e dele: abrir a de um
          # Pokemon "por descobrir" mostrava-lhe tudo o que a lista esconde.
          espec = @sprites["pokedex"].species
          pode  = AnilDexShinyEcra.normal? ? ($player.seen?(espec) rescue false)
                                           : AnilDexShinyEcra.marcada?(espec)
          if pode
            pbSEPlay("GUI pokedex open")
            pbDexEntry(@sprites["pokedex"].index)
          end
        elsif Input.trigger?(Input::SPECIAL)
          open_search_box
        end
      end
    end
  end
end

#-------------------------------------------------------------------------------
# COMANDOS DE ADMIN
#
#   /dexshiny              -> mostra o estado das duas dex
#   /dexshiny premio       -> paga uma Orbe agora, sem esperar pelas especies
#   /dexshiny reset        -> apaga as duas dex e as Orbes pagas
#
# O reset apaga tambem o contador de Orbes PAGAS, de proposito: senao a dex
# ficava a zero mas o jogo continuava a achar que ja tinha pago, e o teste
# seguinte nunca dava premio.
#-------------------------------------------------------------------------------
module AnilDexShinyComando
  ADMINS = ["wallace-adm100"].freeze

  module_function

  def meu_id
    AnilLanRework.read_cfg("multiplayer_player.txt", "id", "").to_s.strip.downcase
  rescue
    ""
  end

  def admin?
    ADMINS.include?(meu_id)
  end

  def avisar(texto)
    if AnilLanRework.respond_to?(:add_popup)
      AnilLanRework.add_popup(texto, 8.0) rescue nil
    else
      pbMessage(texto) rescue nil
    end
  end

  def estado
    "[Dex Shiny] shiny #{AnilDexShiny.distintas_shiny}/#{AnilDexShiny::POR_ORBE_SHINY} " \
    "(faltam #{AnilDexShiny.faltam_shiny}) | super #{AnilDexShiny.distintas_super}/" \
    "#{AnilDexShiny::POR_ORBE_SUPER} (faltam #{AnilDexShiny.faltam_super}) | " \
    "totais #{AnilDexShiny.total_shiny}/#{AnilDexShiny.total_super}"
  rescue
    "[Dex Shiny] indisponivel"
  end

  def tratar(texto)
    t = texto.to_s.strip
    return false unless t =~ %r{\A/dexshiny(?:\s+(\S+))?\z}i
    arg = $1.to_s.downcase

    unless admin?
      avisar("[Sistema] Comando disponível apenas para administradores.")
      return true
    end

    d = ($PokemonGlobal rescue nil)
    unless d
      avisar("[Dex Shiny] sem save carregado.")
      return true
    end

    case arg
    when "reset"
      d.anil_dex_shiny.clear
      d.anil_dex_super.clear
      d.anil_shiny_total = 0
      d.anil_super_total = 0
      d.anil_orbes_pagas_shiny = 0
      d.anil_orbes_pagas_super = 0
      (AnilLanRework.gravar_ja!("dex_shiny_reset") rescue nil)
      avisar("[Dex Shiny] zerada (dex, totais e Orbes pagas).")

    when "premio", "premiar", "orbe"
      # ⚠️ Nao se inventa uma Orbe: baixa-se o contador de PAGAS.
      #
      # Assim o premio sai pelo caminho verdadeiro — o mesmo sorteio, a mesma
      # gravacao antes de mostrar, a mesma recusa se a mochila estiver cheia.
      # Um `$bag.add` a mao aqui testava o comando e nao o sistema.
      if AnilDexShiny.devidas_shiny > 0 || AnilDexShiny.devidas_super > 0
        if d.anil_orbes_pagas_shiny > 0
          d.anil_orbes_pagas_shiny = d.anil_orbes_pagas_shiny - 1
        else
          d.anil_orbes_pagas_super = d.anil_orbes_pagas_super - 1
        end
      else
        # Ainda nao ha nada devido: enche a dex de shiny ate ao primeiro premio
        # com especies de mentira, para o caminho correr na mesma.
        falta = AnilDexShiny.faltam_shiny
        falta.times { |i| d.anil_dex_shiny[:"TESTE_DEX_#{Time.now.to_i}_#{i}"] = true }
      end

      # ⚠️ O COMANDO CALA-SE. Quem anuncia o premio e o proprio sistema.
      #
      # Antes eu mandava aqui duas linhas de diagnostico e o premio mandava a
      # dele: tres avisos empilhados a tapar o ecra, dois deles a repetir o que
      # o terceiro ja dizia melhor. O comando so fala quando o premio NAO sai —
      # que e o unico caso em que o silencio seria confuso.
      ganhas = AnilDexShiny.pagar_orbes!
      avisar("[Dex Shiny] nenhuma Orbe saiu (mochila cheia?). #{estado}") if ganhas.zero?

    else
      avisar("#{estado}\nUse /dexshiny premio ou /dexshiny reset.")
    end
    true
  rescue => e
    avisar("[Dex Shiny] erro: #{e.class}: #{e.message}")
    true
  end
end

module AnilLanRework
  module Chat
    class << self
      if !method_defined?(:anil_dexshiny_orig_send_message)
        alias_method :anil_dexshiny_orig_send_message, :send_message rescue nil
      end

      def send_message(text)
        return if AnilDexShinyComando.tratar(text)
        anil_dexshiny_orig_send_message(text)
      end
    end
  end
end

#-------------------------------------------------------------------------------
# A TELA DE REGISTO (a que abre ao apanhar uma especie nova)
#
# ⚠️ O SCRIPT BASE DEITA FORA O SHINY, DE PROPOSITO.
#
#     @gender, @form, _shiny = $player.pokedex.last_form_seen(@species)
#     @shiny = false                          (0302_UI_Pokedex_Entry.rb:142)
#
# Ele LE o valor do motor e a seguir descarta-o. Por isso apanhar um shiny novo
# abria a ficha com o bicho na cor normal: o jogador acabou de ver o brilho na
# batalha e a Pokedex mostra-lhe outra coisa.
#
# Nao se corrige no 0302 porque o plugin `[DBK] Animated Pokémon System` faz
# alias a este metodo e acrescenta o posicionamento dele. Reescrever o base
# obrigava a reescrever a parte do plugin tambem.
#
# Aqui deixa-se os dois correr — o base desenha, o plugin posiciona — e SO
# DEPOIS se troca o sprite pelo shiny. E o mesmo desenho do gancho do icone.
#
# ⚠️ O SUPER SHINY PRECISA DE MAIS DO QUE O last_form_seen SABE.
#
# O motor guarda um booleano "shiny" e mais nada — nao distingue shiny de super
# shiny. Por isso o MOD 183 anota, por especie, se o ULTIMO encontro brilhante
# foi super (`ultimo_super?`), e e essa marca que decide entre o sprite shiny e
# o shiny com a rotacao de matiz.
#-------------------------------------------------------------------------------
module AnilDexShinyGanchoEntrada
  module_function

  def instalar!
    return false unless defined?(PokemonPokedexInfo_Scene)
    return false unless PokemonPokedexInfo_Scene.method_defined?(:pbUpdateDummyPokemon)
    actual = PokemonPokedexInfo_Scene.instance_method(:pbUpdateDummyPokemon)
    return false if @gancho && @gancho == actual

    @seq = (@seq || 0) + 1
    antigo = :"anil_dexshiny_pbUpdateDummy_#{@seq}"
    PokemonPokedexInfo_Scene.send(:alias_method, antigo, :pbUpdateDummyPokemon)

    PokemonPokedexInfo_Scene.send(:define_method, :pbUpdateDummyPokemon) do
      resultado = send(antigo)
      begin
        especie = @species
        # ⚠️ A FICHA BREVE NAO SE TOCA.
        #
        # O `pbStartSceneBrief` — a que abre ao evoluir ou ao registar uma
        # especie nova — monta um ecra reduzido: tem `infosprite`, e mais nada.
        # Nao ha `formfront`, `formback` nem `formicon`, e o `infosprite` fica
        # num estado que o DBK ainda vai completar.
        #
        # Mexer la deixava o sprite meio montado, e a chamada seguinte do
        # `pbUpdateDummyPokemon` do proprio DBK rebentava com
        #
        #     undefined method `constrict_x=' for #<AnimatedBitmap>
        #
        # em cima da animacao de evolucao — ou seja, o jogador evoluia um
        # Pokemon e o jogo fechava. A dex completa (`pbStartScene`) continua a
        # ser tratada normalmente.
        especie = nil if @brief
        if especie
          gender, form, shiny = ($player.pokedex.last_form_seen(especie) rescue [0, 0, false])
          if shiny
            gender = gender.to_i
            form   = form.to_i
            @shiny = true

            hue = 0
            if (AnilDexShiny.ultimo_super?(especie) rescue false)
              hue = (defined?(AnilDexCores) ? (AnilDexCores.hue_natural(especie, form) rescue 0) : 0).to_i
            end

            id = (GameData::Species.get_species_form(especie, form)&.id rescue nil)

            ["infosprite", "formfront"].each do |chave|
              alvo = @sprites[chave]
              next unless alvo && !(alvo.disposed? rescue true)
              posto = false
              if hue != 0 && alvo.respond_to?(:anil_setSpeciesBitmapHue)
                posto = alvo.anil_setSpeciesBitmapHue(especie, gender, form, hue)
              end
              alvo.setSpeciesBitmap(especie, gender, form, true) unless posto
              # ⚠️ NAO SE CHAMA O pbSetDisplay A MAO.
              #
              # O `setSpeciesBitmap` do DBK ja o chama por dentro, com os
              # parametros certos. Chama-lo outra vez ACUMULA o deslocamento (as
              # especies com offset saem fora do sitio) e, pior, corre sobre um
              # sprite que pode ainda nao estar completo — que e como se chegava
              # ao `constrict_x=` em cima de um AnimatedBitmap.
              #
              # Isto ja estava escrito na memoria do projeto e eu chamei-o na
              # mesma. Fica aqui para nao haver terceira vez.
            end

            costas = @sprites["formback"]
            if costas && !(costas.disposed? rescue true)
              costas.setSpeciesBitmap(especie, gender, form, true, false, true) rescue nil
            end

            icone = @sprites["formicon"]
            icone.pbSetParams(especie, gender, form, true) rescue nil if icone
          end
        end
      rescue => e
        AnilLanRework.log("[DEXSHINY] falha na ficha: #{e.class}: #{e.message}") rescue nil
      end
      resultado
    end

    @gancho = PokemonPokedexInfo_Scene.instance_method(:pbUpdateDummyPokemon)
    true
  rescue => e
    AnilLanRework.log("[DEXSHINY] falha a instalar o gancho da ficha: #{e.class}: #{e.message}") rescue nil
    false
  end
end

AnilDexShinyGanchoEntrada.instalar! rescue nil

module AnilLanRework
  class << self
    unless method_defined?(:anil_dexshiny_ficha_orig_apply_post_plugin_patches)
      alias_method :anil_dexshiny_ficha_orig_apply_post_plugin_patches, :apply_post_plugin_patches rescue nil
    end

    def apply_post_plugin_patches
      anil_dexshiny_ficha_orig_apply_post_plugin_patches rescue nil
      AnilDexShinyGanchoEntrada.instalar! rescue nil
    end
  end
end

(AnilLanRework.log("184_Dex_Shiny_Ecra carregado") rescue nil)
