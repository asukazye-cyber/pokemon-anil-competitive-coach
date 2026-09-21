# encoding: UTF-8
#===============================================================================
# MOD: 145_Selo_Verificado
#-------------------------------------------------------------------------------
# Selo de verificado no resumo do Pokemon, para os obtidos depois do beta.
#
# CRITERIO
#
# @timeReceived >= 01/08/2026 00:00. Antes disso, sem selo — nao e punicao, e
# so a ausencia de garantia: os Pokemon do beta vieram de uma epoca em que o
# servidor ainda nao validava nada, e nao ha como saber quais sao legitimos.
#
# O campo e de confianca razoavel: o Pokemon#initialize grava
# @timeReceived = Time.now.to_i em TODO Pokemon criado, sem excepcao.
#
# OS DO PAINEL LEVAM SELO, INDEPENDENTE DA DATA
#
# Decisao do administrador: eles sao entregues por quem administra o servidor,
# portanto a origem esta garantida por definicao. Isto importa porque os que ja
# existem sao de JULHO, antes do corte — sem esta regra ficariam sem selo.
#
# Como se reconhece um do painel:
#   1. @anil_origem carimbado    -> "painel" (o servidor grava ao criar)
#                                   "painel_inferido" (o carimbo retroativo)
#   2. sem carimbo, obtain_map==1 -> o painel grava sempre esse mapa
#
# A assinatura foi MEDIDA, nao suposta. Num save real de 83 Pokemon, os 12 com
# obtain_map == 1 eram todos do painel — 9 directos e 3 que passaram por troca
# (a troca reescreve obtain_method para 2, por isso esse campo NAO entra no
# criterio). E o Map001.rxdata tem 4 eventos, nenhum deles entrega Pokemon,
# portanto nao ha origem legitima possivel nesse mapa.
#
# O que a assinatura NAO distingue e o obtain_level == 1 sozinho: 13 Pokemon
# desse mesmo save tinham nivel de obtencao 1 sem serem do painel — sao ovos
# chocados, que legitimamente nascem no nivel 1.
#
# ⚠️ O carimbo nao aparece em lado nenhum do jogo: e uma variavel de instancia,
# nao entra no resumo nem em nenhum ecra.
#
# TROCAS
#
# O @timeReceived acompanha o Pokemon, nao o dono. Um mon do beta trocado hoje
# continua sem selo, e um pos-beta trocado mantem o dele. E o comportamento
# certo: o selo fala do bicho, nao de quem o tem.
#
# ONDE E DESENHADO
#
# A tela de resumo em uso e a do plugin 041 (SV Summary Screen), que desenha o
# selo de shiny em (182, 40) com icones de 28x28. Como e plugin, o
# PluginScripts.rxdata nao e gerado pelo compilar.rb — a correcao entra pela
# cadeia do apply_post_plugin_patches, envolvendo o drawPage.
#===============================================================================

module AnilSeloVerificado
  # 01/08/2026 00:00, hora local.
  CORTE = Time.new(2026, 8, 1, 0, 0, 0).to_i

  # Onde o plugin 041 desenha o selo de shiny.
  X_SHINY = 182
  Y = 40
  # Com shiny em cena, o check fica 32 px a esquerda (28 do icone + 4 de folga),
  # os dois lado a lado sem encostar. SEM shiny, ocupa o lugar dele: um icone
  # solto no meio do vazio, com um buraco a direita, parece desalinhado.
  X_SOZINHO = X_SHINY
  X_COM_SHINY = X_SHINY - 32
  ICONE = "Graphics/UI/Summary/icon_verificado"

  # O mapa da introducao do Oak. O painel grava obtain_map = 1 em tudo o que
  # cria, e ali NAO existe nenhum Pokemon legitimo: sao 20x15 tiles com 4
  # eventos, e nenhum deles entrega Pokemon (verificado no Map001.rxdata).
  MAPA_PAINEL = 1

  module_function

  def do_painel?(pkmn)
    origem = (pkmn.instance_variable_get(:@anil_origem).to_s rescue "")
    return true if origem.start_with?("painel")
    # Sem carimbo, cai na assinatura. NAO se exige obtain_method == 0: a troca
    # reescreve esse campo para 2, e um Pokemon do painel que foi trocado
    # continua a ser do painel.
    (pkmn.instance_variable_get(:@obtain_map).to_i rescue 0) == MAPA_PAINEL
  rescue
    false
  end

  # Foi abandonado no mundo por alguem? O MOD 048 carimba no momento da soltura.
  def foi_solto?(pkmn)
    (pkmn.instance_variable_get(:@anil_solto_em).to_i rescue 0) > 0
  rescue
    false
  end

  def verificado?(pkmn)
    return false unless pkmn

    # O PAINEL VEM PRIMEIRO, E SOBREVIVE A SOLTURA.
    #
    # A garantia de um Pokemon do painel nao vem da data nem de quem o tem: vem
    # de ter sido criado por quem administra o servidor. Essa origem esta
    # gravada no proprio bicho (@anil_origem / obtain_map) e nao muda de dono
    # para dono. Um do painel solto e reapanhado continua a ser do painel.
    #
    # E ha uma razao pratica: o selo dele NAO pode depender da data, porque a
    # data que interessa e a da criacao — e um Pokemon do painel de julho fica
    # antes do corte. Se a soltura o tirasse desta regra, ele cairia no teste da
    # data e perderia o selo.
    return true if do_painel?(pkmn)

    # Para todos os outros, ser abandonado no mundo anula o selo: quem o apanhou
    # nao fez nada para o merecer.
    #
    # Isto NAO se resolvia so com a data. A recaptura reaproveita o mesmo objecto
    # (o MOD 048 passa este Pokemon ao WildBattle.start_core, nao cria outro),
    # portanto o timeReceived continua a ser o antigo e um pos-corte solto
    # continuaria a passar. Dai o carimbo proprio no momento da soltura.
    return false if foi_solto?(pkmn)
    recebido = (pkmn.instance_variable_get(:@timeReceived).to_i rescue 0)
    return false if recebido <= 0        # sem data nao ha como provar: sem selo
    recebido >= CORTE
  rescue
    false
  end

  # ---------------------------------------------------------------------------
  # CARIMBO RETROATIVO
  #
  # Os Pokemon injectados antes desta versao nao tem @anil_origem — o carimbo e
  # novo. Esta passagem marca-os a partir da assinatura, uma vez por
  # carregamento de save.
  #
  # Marca-se "painel_inferido" e nao "painel" de proposito: o primeiro foi
  # DEDUZIDO do obtain_map, o segundo foi escrito pelo proprio painel no momento
  # da criacao. Guardar essa diferenca custa nada e evita que, daqui a um ano,
  # ninguem saiba distinguir o que foi medido do que foi suposto.
  #
  # Depois disto, o selo deixa de depender do obtain_map: se algum dia o painel
  # mudar esse valor, os antigos ja estao carimbados.
  # ---------------------------------------------------------------------------
  def carimbar_retroativo!
    return unless defined?($player) && $player
    marcados = 0
    todos_os_pokemon do |pkmn|
      next unless pkmn
      next unless (pkmn.instance_variable_get(:@anil_origem).to_s rescue "").empty?
      next unless (pkmn.instance_variable_get(:@obtain_map).to_i rescue 0) == MAPA_PAINEL
      pkmn.instance_variable_set(:@anil_origem, "painel_inferido")
      marcados += 1
    end
    AnilLanRework.log("[SELO] carimbo retroativo: #{marcados} Pokemon do painel marcados") rescue nil if marcados > 0
    marcados
  rescue => e
    AnilLanRework.log("[SELO] falha no carimbo retroativo: #{e.class}: #{e.message}") rescue nil
    0
  end

  # Party e caixas. A day care e os ovos ficam de fora: nao aparecem no resumo.
  def todos_os_pokemon
    Array($player.party).each { |p| yield(p) }
    caixas = ($PokemonStorage rescue nil)
    return unless caixas
    n = (caixas.maxBoxes rescue 0)
    n.times do |i|
      caixa = (caixas[i] rescue nil)
      next unless caixa
      lista = (caixa.pokemon rescue nil)
      Array(lista).each { |p| yield(p) }
    end
  rescue
  end

  def instalar!
    return if @instalado
    return unless defined?(PokemonSummary_Scene)
    @instalado = true

    PokemonSummary_Scene.class_eval do
      unless method_defined?(:anil_selo_orig_drawPage)
        alias_method :anil_selo_orig_drawPage, :drawPage

        def drawPage(page)
          anil_selo_orig_drawPage(page)
          return unless @pokemon && AnilSeloVerificado.verificado?(@pokemon)
          # ⚠️ SEM filtro de aba — de proposito.
          #
          # Eu tinha restringido a pagina de informacao, achando que o selo de
          # shiny so aparecia ali. Nao e verdade: no plugin 041, o bloco que
          # desenha o icon_shiny/icon_super_shiny esta dentro de um simples
          # `if !@pokemon.egg?`, sem nenhuma condicao de @page_id. Ele aparece em
          # TODAS as abas.
          #
          # O resultado era um selo que sumia ao mudar para "Notas do Treinador"
          # enquanto a estrela de shiny continuava la — dois selos vizinhos com
          # regras diferentes, o que parece defeito mesmo quando nao e.
          #
          # Segue-se agora exactamente a mesma regra do vizinho: todas as abas,
          # excepto ovo (um ovo nao mostra origem nenhuma).
          return if @pokemon.egg? rescue nil
          ov = @sprites && @sprites["overlay"] && @sprites["overlay"].bitmap
          return unless ov
          # Sem shiny nem super shiny, aquele lugar fica vago: ocupa-se ele, em
          # vez de deixar o check deslocado com um buraco ao lado.
          tem_estrela = begin
            @pokemon.shiny? || @pokemon.super_shiny?
          rescue
            false
          end
          x = tem_estrela ? AnilSeloVerificado::X_COM_SHINY : AnilSeloVerificado::X_SOZINHO
          pbDrawImagePositions(ov, [[AnilSeloVerificado::ICONE, x, AnilSeloVerificado::Y]])
        rescue => e
          AnilLanRework.log("[SELO] falha ao desenhar: #{e.class}: #{e.message}") rescue nil
        end
      end
    end
    # -------------------------------------------------------------------------
    # NOME DO DONO ANTERIOR — legivel.
    #
    # O plugin 041 pinta o nome do treinador original conforme o genero:
    #
    #     when 0 then ownerbase = Color.new(60, 120, 252)   # azul
    #     when 1 then ownerbase = Color.new(228, 66, 66)    # vermelho
    #
    # O fundo daquela faixa no bg_info.png e azul saturado, RGB (0, 140, 200).
    # Medindo a luminancia dos dois:
    #
    #     fundo               115
    #     azul (60,120,252)   117   -> contraste 2   (invisivel)
    #     verde (128,248,128) 214   -> contraste 99
    #     rosa (255,152,216)  179   -> contraste 64
    #
    # Nao e questao de gosto: azul sobre azul com dois pontos de diferenca nao
    # se le. E como a maioria dos treinadores e do genero 0, quase todo nome
    # herdado aparecia assim.
    #
    # Nao se reescreve o drawPageOne (e enorme, e do plugin): deixa-se ele
    # desenhar, limpa-se aquele rectangulo do overlay e escreve-se de novo. A
    # limpeza e precisa — texto por cima de texto deixa as bordas do antigo a
    # espreitar.
    # -------------------------------------------------------------------------
    PokemonSummary_Scene.class_eval do
      unless method_defined?(:anil_dono_orig_drawPageOne)
        alias_method :anil_dono_orig_drawPageOne, :drawPageOne

        def drawPageOne
          anil_dono_orig_drawPageOne
          return unless @pokemon
          nome = (@pokemon.owner.name.to_s rescue "")
          return if nome.empty?
          ov = @sprites && @sprites["overlay"] && @sprites["overlay"].bitmap
          return unless ov
          genero = (@pokemon.owner.gender.to_i rescue 0)
          cor, sombra = if genero == 1
                          [Color.new(255, 152, 216), Color.new(128, 32, 96)]   # rosa
                        else
                          [Color.new(128, 248, 128), Color.new(16, 96, 32)]    # verde
                        end
          # Mesma linha do plugin: nome em (352, 108).
          ov.fill_rect(352, 106, 150, 28, Color.new(0, 0, 0, 0))
          pbDrawTextPositions(ov, [[nome, 352, 108, :left, cor, sombra]])
        rescue => e
          AnilLanRework.log("[SELO] falha ao repintar o dono: #{e.class}: #{e.message}") rescue nil
        end
      end
    end

    # -------------------------------------------------------------------------
    # "COMPRADO" em vez de "TROCADO", para quem veio do mercado.
    #
    # O plugin 041 monta a frase a partir de uma tabela indexada pelo
    # obtain_method:
    #
    #     mettext = [ "Encontrado con Nv. {1}",   # 0
    #                 "Huevo recibido",           # 1
    #                 "Intercambiado a Nv. {1}",  # 2
    #                 "",                         # 3  <- livre
    #                 "Encuentro fatidico..." ][@pokemon.obtain_method]
    #
    # Dava para usar o 3, que esta vago. Nao se usou: a tabela e inline dentro
    # do drawPageTwo (200 linhas, do plugin), e mudar a frase obrigaria a
    # reescrever o metodo inteiro. Alem disso um obtain_method desconhecido
    # atravessa o serializador, o mercado e as auditorias — e cada um desses
    # sitios teria de aprender o valor novo.
    #
    # Em vez disso: o obtain_method fica em 2 (e verdade — mudou de dono) e a
    # compra e marcada em @anil_comprado_em. Aqui troca-se so a PALAVRA.
    #
    # O memo inteiro sai numa unica chamada
    #     drawFormattedTextEx(overlay, 226, 80, 274, encounter_memo)
    # com coordenadas fixas, o que da um ponto de intercepcao exacto.
    #
    # A substituicao NAO usa texto fixo: reconstroi-se a frase com o mesmo
    # _INTL que o plugin usou, e troca-se por outra. Assim continua a funcionar
    # se o idioma mudar — comparar com "Trocado" escrito a mao partiria no
    # primeiro jogador em espanhol.
    # -------------------------------------------------------------------------
    # ⚠️ O drawFormattedTextEx e uma funcao GLOBAL (def no topo do
    # 0093_DrawText.rb), o que a torna um metodo PRIVADO de Object. Por isso:
    #
    #   - method_defined?(:drawFormattedTextEx) devolve FALSE, apesar de a cena
    #     poder chama-la. A guarda tem de usar private_method_defined?.
    #   - so se redefine DEPOIS de confirmar que o alias existe. Definir a nova
    #     versao com o alias em falta partiria todo o texto do resumo, nao so
    #     esta frase.
    PokemonSummary_Scene.class_eval do
      alias_criado = begin
        if private_method_defined?(:anil_comprado_orig_drawFormattedTextEx) ||
           method_defined?(:anil_comprado_orig_drawFormattedTextEx)
          true
        else
          alias_method :anil_comprado_orig_drawFormattedTextEx, :drawFormattedTextEx
          true
        end
      rescue => e
        AnilLanRework.log("[COMPRA] nao consegui embrulhar o drawFormattedTextEx: #{e.class}") rescue nil
        false
      end

      if alias_criado
        def drawFormattedTextEx(bitmap, x, y, width, text, *resto)
          begin
            if y == 80 && @pokemon &&
               (@pokemon.instance_variable_get(:@anil_comprado_em).to_i rescue 0) > 0
              nivel = (@pokemon.obtain_level rescue 0)
              trocado  = _INTL("Intercambiado a Nv. {1}", nivel)
              comprado = _INTL("Comprado a Nv. {1}", nivel)
              text = text.sub(trocado, comprado) if text.is_a?(String)
            end
          rescue
          end
          anil_comprado_orig_drawFormattedTextEx(bitmap, x, y, width, text, *resto)
        end
      end
    end

    AnilLanRework.log("[SELO] verificado instalado (corte #{Time.at(AnilSeloVerificado::CORTE)})") rescue nil
  rescue => e
    AnilLanRework.log("[SELO] falha ao instalar: #{e.class}: #{e.message}") rescue nil
  end
end

if defined?(AnilLanRework)
  module AnilLanRework
    class << self
      if !method_defined?(:anil_selo_orig_apply_post_plugin_patches)
        alias_method :anil_selo_orig_apply_post_plugin_patches, :apply_post_plugin_patches rescue nil
      end

      def apply_post_plugin_patches
        anil_selo_orig_apply_post_plugin_patches if respond_to?(:anil_selo_orig_apply_post_plugin_patches)
        AnilSeloVerificado.instalar!
      end
    end
  end
end

# O carimbo retroativo corre uma vez por carregamento de save.
#
# O Game.load e o ponto exacto: o SaveData.load_all_values ja povoou $player e
# $PokemonStorage quando ele volta, e ele so acontece uma vez por partida
# carregada. Nao serve o :on_trainer_load (esse e o de carregar treinador para
# batalha) nem um passe por frame, que repetiria trabalho para nada.
module Game
  class << self
    if !method_defined?(:anil_selo_orig_load)
      alias_method :anil_selo_orig_load, :load

      def load(save_data)
        resultado = anil_selo_orig_load(save_data)
        AnilSeloVerificado.carimbar_retroativo! rescue nil
        resultado
      end
    end
  end
end

AnilLanRework.log("145_Selo_Verificado carregado") rescue nil

