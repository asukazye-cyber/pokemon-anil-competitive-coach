# encoding: UTF-8
#===============================================================================
# MOD: 159_Selas_Montaria
#-------------------------------------------------------------------------------
# As tres selas, uma por patamar de montaria:
#
#   SELACOMUM      couro simples      Rapidash, Donphan, Tauros...
#   SELARARA       couro com manta    Arcanine, Pidgeot...
#   SELALENDARIA   carmesim e ouro    Arceus, Rayquaza...
#
# ⚠️ A SELA DEIXA DE SER DO JOGADOR E PASSA A SER DO POKEMON.
#
# Na mochila e um item solto. Usada num Pokemon, entra NELE — e a partir dai
# viaja com o bicho: se for trocado, vendido no mercado ou guardado no PC, vai
# com a sela posta. Nao ha como a tirar de volta para a mochila, e isso e de
# proposito: e o que da valor a um Pokemon "ja selado".
#
# ⚠️ O SERIALIZADOR E CAMPO A CAMPO, NAO E MARSHAL.
#
# Guardar so uma variavel de instancia no Pokemon chegava para o SAVE (esse e
# Marshal e leva tudo), mas NAO para a troca nem para o mercado: o
# AnilLanRework::Serializer monta um hash campo a campo e tudo o que nao esteja
# na lista dele desaparece a meio do caminho. O bicho chegava do outro lado sem
# sela e ninguem percebia porque.
#
# Por isso o campo "sela" e acrescentado aos dois lados do serializador, aqui em
# baixo, por alias. Sem isso metade da funcionalidade nao existia.
#
# ⚠️ O PATAMAR AINDA NAO TRAVA NADA.
#
# A tabela de raridades esta escrita, mas o EXIGIR_PATAMAR esta a false: por
# agora qualquer sela serve em qualquer montaria. Fica assim ate as raridades
# estarem decididas — ligar isto e mudar uma palavra.
#
# ⚠️ OS ITENS ESTAO NO items.dat, NAO SO EM MEMORIA.
#
# Foram acrescentados ao Data/items.dat e aos dois PBS/items.txt (cliente e
# servidor). O registo em tempo de execucao aqui em baixo e so uma rede para
# quem ainda tiver o items.dat antigo — se o item ja existir, nao faz nada.
#===============================================================================

module AnilSelas
  COMUM     = :SELACOMUM
  RARA      = :SELARARA
  LENDARIA  = :SELALENDARIA

  PATAMARES = [COMUM, RARA, LENDARIA].freeze

  # Onde a sela fica guardada dentro do Pokemon.
  IVAR = :@anil_sela

  # ⚠️ LIGADO: a raridade e respeitada.
  #
  # A regra nao e igualdade — e "pelo menos". Uma sela lendaria serve num
  # Pokemon comum (e desperdicio, mas o jogador que decida); uma sela comum NAO
  # serve num lendario. Com igualdade exacta, quem tivesse a lendaria nao a
  # podia usar no que quisesse, o que nao faz sentido nenhum.
  EXIGIR_PATAMAR = true

  # Acima disto, uma especie sem entrada na tabela e considerada do patamar do
  # meio. Rapidash tem 530 e Absol 465, e ambos estao na tabela justamente
  # porque a regra os classificaria ao contrario.
  TOTAL_BASE_RARA = 520

  # ⚠️ FORA do `class << self`. La dentro seriam constantes da classe
  # singleton, e o AnilSelas::Y_LINHA usado no desenho rebentava com NameError.
  #
  # A fila das insignias corre da direita para a esquerda: o plugin 041 poe a
  # estrela de shiny em 182, o 145 poe o visto na casa seguinte, e a sela na
  # que sobrar. Mesmo passo, mesma linha — alinham-se sozinhas.
  X_BASE  = 182
  PASSO   = 32     # 28 do icone + 4 de folga, o mesmo do 145
  Y_LINHA = 40

  # Rede para instalacoes com o items.dat antigo. Espelha o que esta no PBS.
  DEFS = [
    { :id => COMUM, :real_name => "Sela Comum", :real_name_plural => "Selas Comuns",
      :pocket => 1, :price => 0, :sell_price => 0, :field_use => 1, :battle_use => 0,
      :flags => [], :consumable => true, :show_quantity => true,
      :real_description => "Uma sela de couro simples. Use em um Pokémon de montaria comum para equipá-la nele para sempre." },
    { :id => RARA, :real_name => "Sela Reforçada", :real_name_plural => "Selas Reforçadas",
      :pocket => 1, :price => 0, :sell_price => 0, :field_use => 1, :battle_use => 0,
      :flags => [], :consumable => true, :show_quantity => true,
      :real_description => "Sela com manta e fivelas. Use em um Pokémon de montaria incomum para equipá-la nele para sempre." },
    { :id => LENDARIA, :real_name => "Sela Lendária", :real_name_plural => "Selas Lendárias",
      :pocket => 1, :price => 0, :sell_price => 0, :field_use => 1, :battle_use => 0,
      :flags => [], :consumable => true, :show_quantity => true,
      :real_description => "Carmesim e ouro. Use em um Pokémon de montaria lendário para equipá-la nele para sempre." }
  ].freeze

  # Patamar por especie. A tabela manda; ver o sela_de para a regra por baixo.
  TABELA = {
    :DONPHAN   => COMUM,  :ABSOL     => RARA,   :ARCEUS    => LENDARIA,
    :RAYQUAZA  => LENDARIA,
    :RAPIDASH  => COMUM,  :PONYTA    => COMUM,  :TAUROS    => COMUM,
    :STANTLER  => COMUM,  :GOGOAT    => COMUM,  :MUDSDALE  => COMUM,
    :ZEBSTRIKA => COMUM,
    :ARCANINE  => RARA,   :PIDGEOT   => RARA,   :DODRIO    => RARA,
    :GYARADOS  => RARA,   :SALAMENCE => RARA,   :GARCHOMP  => RARA,
    :DRAGONITE => RARA,   :AERODACTYL=> RARA,   :CHARIZARD => RARA,
    :BRAVIARY  => RARA
  }.freeze

  class << self
    def log(t)
      AnilLanRework.log("[SELAS] #{t}") rescue nil
    end

    def sela?(id)
      PATAMARES.include?(id.to_s.upcase.to_sym)
    rescue
      false
    end

    # ------------------------------------------------------------ o patamar
    # ⚠️ AS FORMAS TEM DE CAIR NA ESPECIE BASE.
    #
    # As receitas de montaria usam ids com forma, como :GIRATINA_1. Se o
    # GameData nao conhecer esse id, o lendaria? devolvia false e o total_base
    # zero — e o Giratina passava a COMUM, ou seja, montavel com a sela mais
    # barata. Exactamente o buraco que se quer fechar.
    def dados(esp)
      d = (GameData::Species.get(esp) rescue nil)
      return d if d
      base = esp.to_s.sub(/_\d+\z/, "")
      return nil if base == esp.to_s
      (GameData::Species.get(base.to_sym) rescue nil)
    rescue
      nil
    end

    # Posicao do patamar: 0 comum, 1 rara, 2 lendaria.
    def nivel_da_sela(sela)
      PATAMARES.index(sela.to_s.upcase.to_sym) || 0
    rescue
      0
    end

    # ⚠️ "PELO MENOS", E NAO "EXACTAMENTE".
    #
    # A sela tem de ser do patamar pedido ou melhor. Assim a lendaria serve em
    # tudo e a comum so serve no que e comum.
    def sela_serve?(sela_id, especie)
      nivel_da_sela(sela_id) >= nivel_da_sela(sela_de(especie))
    rescue
      true
    end

    def lendaria?(esp)
      d = dados(esp)
      return false unless d && d.respond_to?(:flags)
      Array(d.flags).any? { |f| f.to_s =~ /\A(Legendary|Mythical)\z/i }
    rescue
      false
    end

    def total_base(esp)
      d = dados(esp)
      return 0 unless d && d.respond_to?(:base_stats) && d.base_stats
      d.base_stats.values.inject(0) { |a, v| a + v.to_i }
    rescue
      0
    end

    # A sela que uma especie pede: tabela primeiro, palpite depois.
    def sela_de(especie)
      esp = especie.to_s.upcase.to_sym
      return TABELA[esp] if TABELA.key?(esp)
      return LENDARIA if lendaria?(esp)
      total_base(esp) >= TOTAL_BASE_RARA ? RARA : COMUM
    rescue
      COMUM
    end

    def nome_da_sela(sela)
      GameData::Item.get(sela).name
    rescue
      sela.to_s
    end

    # ---------------------------------------------------- a sela do Pokemon
    def sela_do(pkmn)
      return nil unless pkmn
      v = pkmn.instance_variable_get(IVAR)
      return nil if v.nil?
      v = v.to_s.upcase.to_sym
      sela?(v) ? v : nil
    rescue
      nil
    end

    def selado?(pkmn)
      !sela_do(pkmn).nil?
    end

    def por_sela!(pkmn, sela)
      return false unless pkmn && sela?(sela)
      pkmn.instance_variable_set(IVAR, sela.to_s.upcase.to_sym)
      true
    rescue
      false
    end

    # Tem receita de montaria? Sem isso, selar nao serve de nada.
    #
    # ⚠️ A FORMA TEM DE VIR JUNTO.
    #
    # As receitas de forma alternativa sao gravadas como "ESPECIE_N" (o nome do
    # ficheiro do sprite). Perguntando so pela especie, um Necrozma com montaria
    # feita em `NECROZMA_1` ouvia "nao pode ser usado como montaria".
    def montavel?(especie, forma = 0)
      return true unless defined?(AnilMontaria)
      AnilMontaria.tem_receita?(especie, forma)
    rescue
      true
    end

    # ------------------------------------------------------------- o distintivo
    # ⚠️ AS TRES INSIGNIAS PARTILHAM UMA FILA, DA DIREITA PARA A ESQUERDA.
    #
    # O plugin 041 desenha a estrela de shiny em (182, 40) e o 145 poe o visto
    # ali ao lado — a 182 se nao houver estrela, a 150 se houver. Se eu fixasse
    # a sela num sitio, ela ficava por cima de um dos dois conforme o Pokemon.
    #
    # Entao conta-se quantas insignias vem antes e ocupa-se a casa seguinte. As
    # regras sao as mesmas do 145, portanto os tres alinham-se sozinhos.
    def x_do_distintivo(pkmn)
      n = 0
      n += 1 if (pkmn.shiny? || pkmn.super_shiny? rescue false)
      n += 1 if (defined?(AnilSeloVerificado) && AnilSeloVerificado.verificado?(pkmn) rescue false)
      X_BASE - (PASSO * n)
    rescue
      X_BASE
    end

    def ficheiro_do_distintivo(sela)
      case sela
      when RARA     then "Graphics/UI/Summary/icon_sela_rara"
      when LENDARIA then "Graphics/UI/Summary/icon_sela_lendaria"
      else               "Graphics/UI/Summary/icon_sela_comum"
      end
    end

    # ------------------------------------------------------------- registo
    def registar!
      return if $anil_selas_registadas
      $anil_selas_registadas = true
      faltavam = 0
      DEFS.each do |d|
        next if (GameData::Item.exists?(d[:id]) rescue false)
        GameData::Item.register(d) rescue nil
        faltavam += 1
      end
      log(faltavam.zero? ? "selas ja vinham no items.dat" : "#{faltavam} sela(s) registada(s) em memoria (items.dat antigo)")
    rescue => e
      log("falha ao registar: #{e.class}: #{e.message}")
    end
  end
end

#-------------------------------------------------------------------------------
# Usar a sela num Pokemon.
#-------------------------------------------------------------------------------
if defined?(ItemHandlers)
  AnilSelas::PATAMARES.each do |sela_id|
    ItemHandlers::UseOnPokemon.add(sela_id, proc { |_item, _qty, pkmn, scene|
      if pkmn.egg?
        scene.pbDisplay(_INTL("Um ovo não pode usar uma sela."))
        next false
      end

      ja = AnilSelas.sela_do(pkmn)
      if ja == sela_id
        scene.pbDisplay(_INTL("{1} já está com essa sela.", pkmn.name))
        next false
      end

      unless AnilSelas.montavel?(pkmn.species, (pkmn.form.to_i rescue 0))
        scene.pbDisplay(_INTL("{1} não pode ser usado como montaria.", pkmn.name))
        next false
      end

      if AnilSelas::EXIGIR_PATAMAR && !AnilSelas.sela_serve?(sela_id, pkmn.species)
        pedida = AnilSelas.sela_de(pkmn.species)
        scene.pbDisplay(_INTL("{1} precisa de uma {2}.", pkmn.name, AnilSelas.nome_da_sela(pedida)))
        next false
      end

      AnilSelas.por_sela!(pkmn, sela_id)
      pbSEPlay("Pkmn healing") rescue nil
      if ja
        scene.pbDisplay(_INTL("A sela de {1} foi trocada pela {2}. A anterior se perdeu.",
                              pkmn.name, AnilSelas.nome_da_sela(sela_id)))
      else
        scene.pbDisplay(_INTL("{1} agora usa a {2}! Ela faz parte dele a partir de agora.",
                              pkmn.name, AnilSelas.nome_da_sela(sela_id)))
      end
      AnilSelas.log("#{pkmn.species} selado com #{sela_id}")
      next true
    })
  end
end

#-------------------------------------------------------------------------------
# ⚠️ A SELA TEM DE ATRAVESSAR A REDE.
#
# O Serializer monta um hash campo a campo. Um campo que nao esteja na lista
# dele nao existe do outro lado — e a sela sumia em qualquer troca ou venda,
# que e justamente onde ela devia contar mais.
#
# Faz-se por alias em vez de editar o 000: assim o 000 pode ser actualizado sem
# levar isto atras, e se este MOD sair, o serializador volta ao que era.
#-------------------------------------------------------------------------------
if defined?(AnilLanRework) && defined?(AnilLanRework::Serializer)
  module AnilLanRework
    module Serializer
      class << self
        unless method_defined?(:anil_selas_orig_serialize_pokemon)
          alias_method :anil_selas_orig_serialize_pokemon, :serialize_pokemon rescue nil

          def serialize_pokemon(pkmn)
            blob = anil_selas_orig_serialize_pokemon(pkmn)
            return blob unless blob.is_a?(Hash)
            s = AnilSelas.sela_do(pkmn)
            blob["sela"] = s ? s.to_s : nil
            blob
          rescue
            blob
          end
        end

        unless method_defined?(:anil_selas_orig_apply_pokemon_blob)
          alias_method :anil_selas_orig_apply_pokemon_blob, :apply_pokemon_blob rescue nil

          def apply_pokemon_blob(pkmn, blob)
            ret = anil_selas_orig_apply_pokemon_blob(pkmn, blob)
            if pkmn && blob.is_a?(Hash) && (blob.key?("sela") || blob.key?(:sela))
              v = (blob["sela"] || blob[:sela]).to_s
              if v.empty?
                pkmn.instance_variable_set(AnilSelas::IVAR, nil)
              else
                AnilSelas.por_sela!(pkmn, v.upcase.to_sym)
              end
            end
            ret
          rescue
            ret
          end
        end
      end
    end
  end
end

#-------------------------------------------------------------------------------
# O distintivo da sela no ecra de informacao.
#
# ⚠️ Instalado no apply_post_plugin_patches, como o 145. O PokemonSummary_Scene
# e reescrito por plugins; um alias posto antes deles fica tapado.
#-------------------------------------------------------------------------------
module AnilSelas
  class << self
    def instalar_distintivo!
      return false unless defined?(PokemonSummary_Scene)
      return false if PokemonSummary_Scene.method_defined?(:anil_selas_orig_drawPage)

      PokemonSummary_Scene.class_eval do
        alias_method :anil_selas_orig_drawPage, :drawPage

        def drawPage(page)
          anil_selas_orig_drawPage(page)
          return unless @pokemon
          return if (@pokemon.egg? rescue false)
          sela = AnilSelas.sela_do(@pokemon)
          return unless sela
          ov = @sprites && @sprites["overlay"] && @sprites["overlay"].bitmap
          return unless ov
          pbDrawImagePositions(ov, [[AnilSelas.ficheiro_do_distintivo(sela),
                                     AnilSelas.x_do_distintivo(@pokemon),
                                     AnilSelas::Y_LINHA]])
        rescue => e
          AnilSelas.log("falha ao desenhar o distintivo: #{e.class}: #{e.message}")
        end
      end
      log("distintivo instalado no resumo")
      true
    rescue => e
      log("falha ao instalar o distintivo: #{e.class}: #{e.message}")
      false
    end
  end
end

module AnilLanRework
  class << self
    unless method_defined?(:anil_selas_orig_apply_post_plugin_patches)
      alias_method :anil_selas_orig_apply_post_plugin_patches, :apply_post_plugin_patches rescue nil
    end

    def apply_post_plugin_patches
      anil_selas_orig_apply_post_plugin_patches rescue nil
      AnilSelas.instalar_distintivo! rescue nil
    end
  end
end

#-------------------------------------------------------------------------------
# "Montar" / "Desmontar" no menu da equipa.
#
# ⚠️ Pelo MenuHandlers, nao a reescrever o ecra da equipa.
#
# O 0303_UI_Party monta a lista com o MenuHandlers.each_available(:party_menu),
# portanto acrescentar uma entrada e o caminho previsto — e nao briga com os
# plugins que tambem mexem nesse ecra.
#
# ⚠️ O NOME E DINAMICO, E ISSO OBRIGA A UM TRUQUE.
#
# O each_available chama `hash["name"].call` SEM argumentos, portanto o nome nao
# sabe de que Pokemon se trata. Mas a `condition` corre imediatamente antes, com
# os argumentos todos — e ai que se guarda o indice. Depende da ordem das duas
# chamadas dentro do mesmo ciclo, que e o que o 0042 faz.
#
# ⚠️ NAO SE MONTA SOZINHO POR ESTAR EM PRIMEIRO.
#
# Foi ponderado (era a outra hipotese em cima da mesa) e nao se fez: quem
# reordena a equipa por causa de uma batalha passaria a montar sem querer, e nao
# haveria como andar a pe sem tirar o bicho da frente. Uma entrada no menu diz
# o mesmo e deixa desmontar.
#-------------------------------------------------------------------------------
if defined?(MenuHandlers)
  module AnilSelas
    @ultimo_pkmn = nil
    class << self
      attr_accessor :ultimo_pkmn

      # Da para usar a montaria deste Pokemon agora?
      def opcao_disponivel?(pkmn)
        return false unless pkmn
        return false if (pkmn.egg? rescue false)
        return false unless selado?(pkmn)
        montavel?(pkmn.species, (pkmn.form.to_i rescue 0))
      rescue
        false
      end

      def montado_neste?(pkmn)
        return false unless pkmn && defined?(AnilMontaria)
        AnilMontaria.montado.to_s.upcase == pkmn.species.to_s.upcase
      rescue
        false
      end
    end
  end

  MenuHandlers.add(:party_menu, :anil_montaria, {
    "name"      => proc {
      AnilSelas.montado_neste?(AnilSelas.ultimo_pkmn) ? _INTL("Desmontar") : _INTL("Montar")
    },
    "order"     => 15,
    "condition" => proc { |_screen, party, party_idx|
      pkmn = party[party_idx]
      AnilSelas.ultimo_pkmn = pkmn
      next AnilSelas.opcao_disponivel?(pkmn)
    },
    "effect"    => proc { |screen, party, party_idx|
      pkmn = party[party_idx]
      # ⚠️ AQUI SO SE PEDE. QUEM MONTA E A ANIMACAO (160).
      #
      # O 156 esconde o follower assim que `montado?` fica verdadeiro; montar
      # aqui fazia o bicho evaporar-se antes do salto e nao sobrava nada em
      # cima de que saltar. O 160 monta na aterragem.
      #
      # Sem o 160 carregado, monta-se a moda antiga — a funcionalidade nao pode
      # depender da animacao existir.
      if AnilSelas.montado_neste?(pkmn)
        if defined?(AnilMontariaAnim)
          AnilMontariaAnim.pedir_desmontar
        else
          AnilMontaria.desmontar! rescue nil
          AnilMontariaComando.recarregar_sprite! rescue nil
        end
        # sem mensagem: a animacao no overworld ja diz tudo, e a caixa de texto
        # so atrasava a volta ao mapa
      else
        unless (AnilMontaria.tem_receita?(pkmn.species, (pkmn.form.to_i rescue 0)) rescue false)
          screen.scene.pbDisplay(_INTL("Não há montaria pronta para {1}.", pkmn.name)) rescue nil
          next false
        end
        if defined?(AnilMontariaAnim)
          AnilMontariaAnim.pedir_montar(pkmn)
        else
          # Passa-se o POKEMON, nao so a especie: e dele que a montaria herda o
          # shiny e o matiz de super shiny.
          AnilMontaria.montar!(pkmn.species, pkmn) rescue nil
          AnilMontariaComando.recarregar_sprite! rescue nil
        end
        # idem: quem confirma que montou e o salto, nao uma caixa de texto
      end
      next false
    }
  })
end

if defined?(EventHandlers) && EventHandlers.respond_to?(:add)
  EventHandlers.add(:on_enter_map, :anil_selas_registar, proc { |_antigo|
    AnilSelas.registar!
  })
end

AnilLanRework.log("159_Selas_Montaria carregado") rescue nil
