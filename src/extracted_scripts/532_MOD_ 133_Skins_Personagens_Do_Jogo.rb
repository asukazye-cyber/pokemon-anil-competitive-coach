# encoding: UTF-8
#===============================================================================
# MOD: 133_Skins_Personagens_Do_Jogo
#-------------------------------------------------------------------------------
# Poe TODOS os personagens de Graphics/Characters no seletor de skins.
#
# Ate aqui o catalogo (available_characters, no 002_Script_Skins) tinha tres
# fontes: GameData::PlayerMetadata, GameData::TrainerType e a pasta
# Graphics/Skins. A pasta Graphics/Characters — que e o acervo de bonecos do
# proprio jogo — NAO entrava. Resultado: so aparecia quem por acaso estivesse
# amarrado a um tipo de treinador; os ~110 NPCs de cidade (mama, nina, tendero,
# enfermera...) e as variantes (azulFix, oakFix, campistaa) ficavam invisiveis.
#
# COMO O SPRITE DE BATALHA E A TRANSICAO FUNCIONAM
#
# Os dois saem do TIPO DE TREINADOR, nao do nome da skin:
#   - sprite de batalha : GameData::TrainerType.front_sprite_filename(tipo)
#   - barra VS          : Graphics/Transitions/hgss_vsBar_<TIPO>.png
#   - fundo custom      : Graphics/Transitions/custom_background_<TIPO>.png
#     (plugin 008_Intro_Versus, que le $game_temp.transition_animation_data[0])
#
# Logo, basta o charset resolver para o tipo certo e as tres coisas aparecem
# sozinhas — nao ha nada a desenhar aqui. O trainer_sprite_name_for_character ja
# tenta o tipo e, se falhar, procura Graphics/Trainers/<nome>.png direto.
#
# O que ele NAO resolve sozinho e o punhado de casos em que o boneco tem um nome
# e a arte de batalha tem outro (campistaa -> CAMPISTA, oakFix -> OAK,
# pescadoraow -> PESCADOR...). Para esses existe a tabela ALIAS_SPRITE abaixo.
#===============================================================================

if defined?(AnilLanRework) && defined?(AnilLanRework::SKINS_ENABLED) && AnilLanRework::SKINS_ENABLED

module AnilLanRework
  module PersonagensDoJogo
    PASTA = "Graphics/Characters"

    # ------------------------------------------------------------------
    # PENEIRA 1 — pelo NOME. Barata, corta o obvio.
    #
    # NAO se exclui so por "termina em numero": ha nomes com digito no meio
    # (anciano2echado) que tambem sao variantes. Qualquer digito e sinal de
    # variante ou de numeracao de tileset.
    # ------------------------------------------------------------------
    def self.nome_valido?(base)
      n = base.to_s.strip
      return false if n.empty?
      return false if n =~ /\d/                 # 010, azul2, 144, anciano2echado
      return false if n.include?("_")           # 144_1, POKEMONTRAINER_x
      return false if n =~ /duelo|vinc/i        # sprites de cena, nao skins
      return false if n =~ /\Aberrytree/i       # arbustos de baga
      return false if n =~ /\A[A-Z]+\z/         # ARCEUS, AZELF: sprite de Pokemon
      k = chave(n)
      return false if NAO_PERSONAGEM.include?(k)
      return false if PREFIXOS_FORA.any? { |p| k.start_with?(p) }
      return false if INCOMPLETOS.any? { |i| chave(i) == k }
      true
    end

    # ------------------------------------------------------------------
    # PENEIRA 2 — pela GEOMETRIA. E esta que separa boneco de tranqueira.
    #
    # Um charset do RMXP e sempre 4 colunas x 4 linhas (4 direcoes x 4 quadros),
    # entao o quadro mede largura/4 por altura/4. Medindo os 675 PNGs da pasta:
    #
    #   64x64  -> 96 personagens      <- os dois tamanhos de boneco do jogo
    #   60x64  -> 79 personagens
    #   8x8    ->  8 ficheiros        stepsDown, stepsLeftBike (pegadas)
    #   32x32  -> 12 ficheiros        sangre, masterBall, Object ball
    #   152x128 -> snorlaxDurmiente   deitado: mais LARGO que alto
    #   160x128 -> Helice lab
    #
    # Dai as tres condicoes: quadro entre 48 e 72 de largura, entre 48 e 96 de
    # altura, e nunca mais largo do que alto — pessoa em pe e vertical, objeto
    # deitado nao e.
    #
    # A lista EXTRA e para os poucos bosses com folha maior que o normal, que a
    # regra recusaria por engano.
    # ------------------------------------------------------------------
    EXTRA = %w[urano].freeze

    def self.dimensao_png(caminho)
      File.open(caminho, "rb") do |f|
        cab = f.read(24).to_s
        return nil unless cab[0, 8] == "\x89PNG\r\n\x1a\n".b
        return cab[16, 8].unpack("N2")   # [largura, altura]
      end
    rescue
      nil
    end

    def self.spritesheet_de_caminhada?(caminho, base)
      return true if EXTRA.include?(base.to_s.downcase)
      dim = dimensao_png(caminho)
      return false unless dim
      largura, altura = dim
      return false unless largura % 4 == 0 && altura % 4 == 0
      qw = largura / 4
      qh = altura  / 4
      return false unless qw.between?(48, 72)
      return false unless qh.between?(48, 96)
      qh >= qw
    rescue
      false
    end

    # ------------------------------------------------------------------
    # OBJETOS com geometria de personagem.
    #
    # O ventilador tem folha 256x256 (quadro 64x64) e os 16 quadros preenchidos:
    # e uma animacao de objeto, nao um boneco. Nem a geometria nem a analise de
    # quadros vazios o apanham — so a lista. Acrescentar aqui o que for
    # aparecendo na revisao.
    # ------------------------------------------------------------------
    # Comparacao normalizada: minusculas E sem espacos. Sem isto o
    # "dragonite mega.png" nunca casava com a entrada da lista.
    def self.chave(n) = n.to_s.downcase.gsub(/\s+/, "")

    NAO_PERSONAGEM = %w[
      ventilador anillo arbolito bolaEnergia chapoteo corrientes cortacesped
      estatuaPersian humo nubehumo skyflyer teleport ultraportal
      fuente hoguera luz golperoca
      azulFix azulHojaCogidos azulRojoCogidos oakFix
      eric lostie dpertierra sombra sombrita boylifting
      mewtwoarmor dragonitemega
      billPokemon yCap
    ].map { |n| chave(n) }.freeze

    # Familias inteiras. Poupa ter de listar item por item — era o "nao preciso
    # falar sempre": eletrodomestico, mobilia e Pokemon de evento entram todos
    # por prefixo.
    PREFIXOS_FORA = %w[
      nido flecha object steps sil berrytree
      lavadora nevera microondas libro mueble
    ].freeze

    # ------------------------------------------------------------------
    # SPRITESHEETS INCOMPLETOS — quadros de movimento em falta pelo meio.
    #
    # Levantados com analise de pixel (System.Drawing) sobre os 185 que passavam
    # nas peneiras anteriores: divide-se a folha em 4x4 e conta-se quanto quadro
    # esta totalmente transparente. Estes tem de 1 a 12 quadros vazios de 16 —
    # ao andar, o boneco desaparece em algumas direcoes.
    #
    # E lista fixa de proposito: fazer esta analise em jogo custaria ~1 milhao de
    # get_pixel ao abrir o seletor. Se a arte for corrigida, refazer a medicao e
    # atualizar aqui.
    # ------------------------------------------------------------------
    INCOMPLETOS = %w[
      prodigio kris mostaz eusine FlechaSalida
      hoennPetra hoennPlubio hoennVito hoennErico hoennCandela
      hoennAlana hoennMarcial hoennLeti hoennNorman
      kukui sachiko huevosAves
    ].freeze

    # ------------------------------------------------------------------
    # CHARSET -> TIPO DE TREINADOR.
    #
    # E este mapa que faz aparecer o sprite de batalha E a transicao VS: os dois
    # sao indexados pelo TIPO, e o nome do boneco no mapa nao tem nada a ver com
    # o id do tipo (surge.png -> LIDER3, cujo nome real e "Teniente Surge").
    #
    # Sem isto, o trainer_sprite_name_for_character nao achava nada para os
    # lideres e eles entravam no seletor sem imagem nenhuma.
    #
    # Conferido contra PBS/trainers.txt (nome real de cada LIDER) e contra os
    # ficheiros existentes em Graphics/Trainers.
    # ------------------------------------------------------------------
    # As 47 primeiras entradas nao sao palpite: sairam de uma varredura dos
    # Map*.rxdata procurando, em cada pagina de evento, o par
    # (grafico do evento, pbTrainerIntro(:TIPO)). E o que o jogo faz de facto.
    # Foi assim que se descobriu que prismaf/prismam sao PRISMM (nao PRISMA),
    # luchador e KARATEKA, nobla/noble sao CABALLERO e pescadoraow e PESCADORA.
    #
    # Os chefes nao usam pbTrainerIntro, entao vieram de PBS/trainers.txt
    # (nome real de cada tipo) cruzado com os ficheiros que existem em
    # Graphics/Trainers e Graphics/Transitions.
    TIPO_POR_CHARSET = {
      # --- lideres de ginasio ---
      "brock"        => :LIDER1,
      "misty"        => :LIDER2,
      "surge"        => :LIDER3,   # "Teniente Surge"
      "erika"        => :LIDER4,
      "koga"         => :LIDER5,
      "sabrina"      => :LIDER6,
      "blaine"       => :LIDER7,
      "urano"        => :URANO1,
      # --- Alto Mando (ALTOMANDO1=Lorelei, 2=Bruno, 3=Agatha, 4=Lance) ---
      "lorelei"      => :ALTOMANDO1,
      "bruno"        => :ALTOMANDO2,
      "lance"        => :ALTOMANDO4,
      "agatha"       => :AGATHA1,
      # --- chefes e especiais ---
      "atlas"        => :ATLAS1,
      "atenea"       => :ATENEA1,
      "azul"         => :AZUL1,
      "giovanni"     => :GIOVANNI1,
      "surya"        => :SURYA,
      "ash"          => :ASH,
      "oak"          => :OAK,
      # O PBS chama LIDER6HOENN de "Marcial", mas a ARTE nesse tipo e a do
      # Guzman (confirmado pelo usuario: custom_vs_LIDER6HOENN.png). Nao ha
      # GUZMAN.png em Graphics/Trainers — ele reaproveita este tipo, e e dele
      # que saem o sprite de batalha e as duas transicoes.
      "guzman"       => :LIDER6HOENN,
      # --- treinadores de rota, extraidos dos eventos dos mapas ---
      "brujita"      => :BRUJITA,     "campista"     => :CAMPISTA,
      "campistaa"    => :CAMPISTA,    "cazabichas"   => :CAZABICHAS,
      "cazabichos"   => :CAZABICHOS,  "cerebrito"    => :CEREBRITO,
      # ⚠️ Os eventos dos mapas dizem cientifico->ROCKETO, rocketa->ROCKETO,
      # modelo->CHICA e nadadora->NADADOR — porque AQUELE NPC do mapa e um
      # Rocket disfarcado, ou reaproveita a arte do outro genero. Para uma SKIN
      # isso e errado: quem escolhe "cientifico" quer o cientista. Quando existe
      # arte com o nome do proprio personagem, ela ganha do evento.
      "cientifica"   => :CIENTIFICA,  "cientifico"   => :CIENTIFICO,
      "damisela"     => :DAMISELA,    "estudianta"   => :ESTUDIANTA,
      "dianta"       => :ESTUDIANTA,  "exorcista"    => :EXORCISTA,
      "fotografa"    => :FOTOGRAFA,   "guay"         => :GUAY,
      "guaya"        => :GUAYA,       "guayo"        => :GUAY,
      "jovenrica"    => :JOVENRICA,   "ladron"       => :LADRON,
      "luchador"     => :KARATEKA,    "luchadora"    => :KARATEKAA,
      "macarra"      => :MACARRA,     "marinero"     => :MARINERO,
      "medium"       => :MEDIUM,      "modelo"       => :MODELO,
      "montanero"    => :MONTANERO,   "motorista"    => :MOTORISTA,
      "nadador"      => :NADADOR,     "nadadora"     => :NADADORA,
      "ninja"        => :NINJA,       "ninjaa"       => :NINJAA,
      # CABALLERA e a versao feminina; sem isto a nobla usava a arte do noble.
      "nobla"        => :CABALLERA,   "noble"        => :CABALLERO,
      "ornitologo"   => :ORNITOLOGO,  "pescador"     => :PESCADOR,
      "pescadoraow"  => :PESCADORA,   "pokemaniaco"  => :POKEMANIACO,
      "prismaf"      => :PRISMM,      "prismam"      => :PRISMM,
      "hombreprisma" => :PRISMM,      "prisma"       => :PRISMA,
      "rocketa"      => :ROCKETA,     "rocketo"      => :ROCKETO,
      "rocketelite"  => :ELITEROCKET, "tecnico"      => :TECNICO,
      "veterana"     => :VETERANA,    "veterano"     => :VETERANO,
      "operaria"     => :MECANICO,    "operario"     => :MECANICO,
      # --- lideres de Hoenn (hoje fora pela lista INCOMPLETOS) ---
      "hoennnorman"  => :LIDER1HOENN, "hoenncandela" => :LIDER2HOENN,
      "hoennalana"   => :LIDER3HOENN, "hoennerico"   => :LIDER4HOENN,
      "hoennpetra"   => :LIDER5HOENN, "hoennmarcial" => :LIDER6HOENN,
      "hoennplubio"  => :LIDER7HOENN, "hoennvito"    => :LIDER8HOENN,
      "hoennleti"    => :LIDER8HOENN
    }.freeze

    def self.tipo_de(nome)
      chave = nome.to_s.downcase
      tipo = TIPO_POR_CHARSET[chave]
      return nil unless tipo
      return nil unless (GameData::TrainerType.exists?(tipo) rescue false)
      tipo
    rescue
      nil
    end

    # Boneco no mapa tem um nome, arte de batalha tem outro.
    # Retirado do levantamento de Graphics/Characters x Graphics/Trainers.
    ALIAS_SPRITE = {
      "campistaa"    => "CAMPISTA",
      "guayo"        => "GUAY",
      "oakfix"       => "OAK",
      "pescadoraow"  => "PESCADOR",
      "billpokemon"  => "BILL",
      "dianta"       => "ESTUDIANTA",
      "hombreprisma" => "PRISMA",
      "prismaf"      => "PRISMA",
      "prismam"      => "PRISMA",
      "rocketaradar" => "ROCKETA"
    }.freeze

    def self.lista
      @lista ||= begin
        nomes = []
        recusados = 0
        begin
          if Dir.exist?(PASTA)
            Dir.entries(PASTA).each do |f|
              next unless f.downcase.end_with?(".png")
              base = File.basename(f, ".*")
              next unless nome_valido?(base)
              if spritesheet_de_caminhada?(File.join(PASTA, f), base)
                nomes << base
              else
                recusados += 1
              end
            end
          end
        rescue => e
          AnilLanRework.log("[SKINS/JOGO] Falha ao listar #{PASTA}: #{e.message}") rescue nil
        end
        AnilLanRework.log("[SKINS/JOGO] #{nomes.size} spritesheets validos; #{recusados} recusados pela geometria.") rescue nil
        nomes.sort_by(&:downcase)
      end
    end

    # Rotulo legivel: usa o nome real do tipo de treinador quando existe, senao
    # o proprio nome do ficheiro com a primeira letra maiuscula.
    def self.rotulo(nome)
      tipo = (AnilLanRework.trainer_type_for_character(nome, nil) rescue nil)
      if tipo
        real = (GameData::TrainerType.get(tipo).real_name.to_s rescue "")
        return real unless real.empty?
      end
      nome.gsub(/([a-z])([A-Z])/, '\1 \2').capitalize
    end
  end
end

#-------------------------------------------------------------------------------
# 1. Sprite de batalha para os casos de nome divergente.
#-------------------------------------------------------------------------------
module AnilLanRework
  class << self
    alias anil_pers_orig_trainer_sprite_name trainer_sprite_name_for_character unless method_defined?(:anil_pers_orig_trainer_sprite_name)

    def trainer_sprite_name_for_character(char_name, back = false)
      ret = anil_pers_orig_trainer_sprite_name(char_name, back)
      return ret if ret && !ret.to_s.empty?

      # Lideres e chefes: o sprite vem do TIPO, nunca do nome do boneco.
      tipo = AnilLanRework::PersonagensDoJogo.tipo_de(char_name)
      if tipo
        arte = begin
          if back
            GameData::TrainerType.back_sprite_filename(tipo).to_s
          else
            GameData::TrainerType.front_sprite_filename(tipo).to_s
          end
        rescue
          ""
        end
        arte = normalize_graphic_name(arte, "Graphics/Trainers/") rescue arte
        return arte unless arte.to_s.empty?
      end

      # So entra aqui quando o caminho normal (tipo de treinador, depois ficheiro
      # com o mesmo nome) nao achou nada.
      apelido = AnilLanRework::PersonagensDoJogo::ALIAS_SPRITE[char_name.to_s.downcase]
      return ret unless apelido

      alvo = back ? "#{apelido}_back" : apelido
      return alvo if File.exist?("Graphics/Trainers/#{alvo}.png")
      # Sem arte de costas, o de frente ja e melhor que nada.
      return apelido if back && File.exist?("Graphics/Trainers/#{apelido}.png")
      ret
    rescue
      ret rescue ""
    end
  end
end

#-------------------------------------------------------------------------------
# 2. O catalogo.
#
# O available_characters do 002 guarda o resultado em @cached_chars e devolve-o
# nas chamadas seguintes, entao acrescentar sem mais nada duplicaria a lista a
# cada abertura do seletor. Dai o de-duplicar por char_name.
#-------------------------------------------------------------------------------
module AnilLanRework
  class << self
    alias anil_pers_orig_available_characters available_characters unless method_defined?(:anil_pers_orig_available_characters)

    def available_characters
      lista = anil_pers_orig_available_characters
      lista = [] unless lista.is_a?(Array)

      vistos = {}
      lista.each { |c| vistos[c["char_name"].to_s.downcase] = true }

      novos = 0
      AnilLanRework::PersonagensDoJogo.lista.each do |nome|
        chave = nome.downcase
        next if vistos[chave]
        vistos[chave] = true
        novos += 1
        lista << {
          "label"          => AnilLanRework::PersonagensDoJogo.rotulo(nome),
          "char_name"      => nome,
          "trainer_sprite" => (trainer_sprite_name_for_character(nome) rescue ""),
          "player_meta_id" => nil,
          # O tipo mandado aqui e o que a animacao VS usa para achar
          # hgss_vsBar_<TIPO> / custom_background_<TIPO>.
          "trainer_type"   => (AnilLanRework::PersonagensDoJogo.tipo_de(nome) ||
                               (trainer_type_for_character(nome, nil) rescue nil)),
          "unlocked"       => true,
          "do_jogo"        => true
        }
      end

      if novos > 0
        AnilLanRework.log("[SKINS/JOGO] #{novos} personagens de Graphics/Characters acrescentados ao seletor (total #{lista.length}).") rescue nil
      end
      @cached_chars = lista
      lista
    rescue => e
      AnilLanRework.log("[SKINS/JOGO] Falha ao estender o catalogo: #{e.class}: #{e.message}") rescue nil
      anil_pers_orig_available_characters rescue []
    end
  end
end

end
