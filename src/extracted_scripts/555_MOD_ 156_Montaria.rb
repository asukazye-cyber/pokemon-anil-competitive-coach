# encoding: UTF-8
#===============================================================================
# MOD: 156_Montaria
#-------------------------------------------------------------------------------
# Monta o jogador em cima de um Pokemon da equipa. Le as receitas do
# `Data/montarias.json`, feitas no `montaria_gui.py`.
#
# ⚠️ O TRUQUE ESTA EM DEIXAR O MOTOR FAZER A INDEXACAO.
#
# O Sprite_Character escolhe o quadro assim (0067, linha 187):
#
#     sx = @character.pattern * @cw
#     sy = ((@character.direction - 2) / 2) * @ch
#
# Ou seja: COLUNA = padrao de animacao, LINHA = direccao. E exactamente a mesma
# grelha que o editor usa. Entao em vez de andar a mexer em coordenadas de
# sprite, gera-se UM charset 4x4 novo — com o cavaleiro ja cortado, escalado e
# apagado — e troca-se o @charbitmap. O motor indexa-o sozinho, sem saber de
# nada.
#
# E como a COLUNA e o padrao, e a montaria tambem anda pelo padrao, a mascara de
# cada quadro cai no sitio certo de graca: a celula [padrao][direccao] do nosso
# charset ja tem a mascara desse mesmo passo.
#
# ⚠️ AS MASCARAS SAO PRE-CALCULADAS, UMA VEZ.
#
# A receita do DONPHAN virado para baixo tem 331 marcas — o pincel acrescenta
# uma por movimento do rato. Aplicar 331 circulos por frame era impensavel.
# O charset e construido uma vez ao montar e fica em cache; a partir dai cada
# frame e uma atribuicao de referencia.
#
# ⚠️ O SPRITE DA MONTARIA E O MOLDE DO SURF.
#
# O jogo ja desenha uma jangada por baixo do jogador: Sprite_SurfBase, criado no
# Sprite_Character#initialize so para o $game_player. Isto e a mesma classe com
# outro bitmap — nao se inventou mecanismo nenhum.
#
# ⚠️ AS RECEITAS ANTIGAS NAO TEM TODOS OS CAMPOS.
#
# As primeiras foram gravadas antes de existir escala, linha e espelhar. Le-se
# tudo com valor por omissao, senao o jogo rebentava em receitas ja feitas.
#===============================================================================

# ⚠️ ANALISADOR DE JSON PROPRIO, PORQUE NO ANDROID NAO HA BIBLIOTECA.
#
# No JoiPlay o comando dizia "nao ha receita" com o ficheiro no sitio certo. A
# causa e a mesma que o proprio servidor ja documenta no serve_update_manifest:
# o cliente pode nao ter a biblioteca `json`.
#
# E o modo como isso falha e traicoeiro:
#
#   require "json" rescue nil     -> LoadError e ScriptError, NAO StandardError,
#                                    portanto o `rescue` modificador nao o apanha
#   JSON.parse(...)               -> NameError, que JA e StandardError e ia parar
#                                    ao nosso rescue generico: receitas vazias,
#                                    sem erro visivel, "nao ha receita"
#
# Isto chega de sobra para o formato das receitas — objectos, listas, numeros,
# strings e true/false/null. Verificado contra o JSON.parse a serio com o
# ficheiro real: estrutura e tipos identicos, ate ao ultimo Float. E 66 ms
# contra 3 ms, mas corre UMA vez ao carregar.
module AnilMontariaJSON
  module_function

  def parse(texto)
    @s = texto.to_s
    @i = 0
    v = valor
    espacos
    v
  end

  def espacos
    @i += 1 while @i < @s.length && " \t\r\n".include?(@s[@i])
  end

  def valor
    espacos
    case @s[@i]
    when "{" then objecto
    when "[" then lista
    when '"' then texto
    when "t" then (@i += 4; true)
    when "f" then (@i += 5; false)
    when "n" then (@i += 4; nil)
    else numero
    end
  end

  def objecto
    @i += 1
    h = {}
    espacos
    if @s[@i] == "}"
      @i += 1
      return h
    end
    loop do
      espacos
      k = texto
      espacos
      @i += 1
      h[k] = valor
      espacos
      if @s[@i] == ","
        @i += 1
      else
        @i += 1
        break
      end
    end
    h
  end

  def lista
    @i += 1
    a = []
    espacos
    if @s[@i] == "]"
      @i += 1
      return a
    end
    loop do
      a << valor
      espacos
      if @s[@i] == ","
        @i += 1
      else
        @i += 1
        break
      end
    end
    a
  end

  def texto
    @i += 1
    fora = ""
    while @i < @s.length
      c = @s[@i]
      if c == "\\"
        @i += 1
        d = @s[@i]
        fora << case d
                when "n" then "\n"
                when "t" then "\t"
                when "r" then "\r"
                else d
                end
      elsif c == '"'
        @i += 1
        return fora
      else
        fora << c
      end
      @i += 1
    end
    fora
  end

  def numero
    ini = @i
    @i += 1 while @i < @s.length && "-+.0123456789eE".include?(@s[@i])
    bruto = @s[ini...@i]
    (bruto.include?(".") || bruto.downcase.include?("e")) ? bruto.to_f : bruto.to_i
  end
end

module AnilMontaria
  FICHEIRO = "Data/montarias.json"
  PASTA_MONTARIAS = "Graphics/Characters/Followers/"
  # Folga por cima da celula, para caber um cavaleiro com dy muito negativo
  # (o RAYQUAZA esta a -50).
  MARGEM_CIMA = 72
  DIRECOES = ["baixo", "esquerda", "direita", "cima"].freeze

  @receitas = nil
  @cache = {}

  class << self
    def log(t)
      AnilLanRework.log("[MONTARIA] #{t}") rescue nil
    end

    # ⚠️ Varios caminhos, porque o directorio de trabalho nao e o mesmo em toda
    # a parte. No JoiPlay, um caminho relativo pode nao cair onde se espera.
    def caminhos_possiveis
      [
        FICHEIRO,
        "./" + FICHEIRO,
        (File.join(Dir.pwd, FICHEIRO) rescue nil),
        "montarias.json"
      ].compact
    end

    def receitas
      return @receitas if @receitas
      @receitas = {}
      @diag = []
      alvo = nil
      caminhos_possiveis.each do |c|
        existe = (FileTest.exist?(c) rescue false)
        @diag << "#{existe ? "ok " : "-- "}#{c}"
        if existe && alvo.nil?
          alvo = c
        end
      end
      unless alvo
        log("nenhum ficheiro de receitas encontrado; procurei em: #{@diag.join(" | ")}")
        return @receitas
      end
      begin
        bruto = File.read(alvo)
        # A biblioteca so se usa se ESTIVER mesmo la. O defined? nao levanta
        # LoadError nenhum, ao contrario do require.
        @receitas = if defined?(JSON) && JSON.respond_to?(:parse)
                      @via = "JSON"
                      JSON.parse(bruto)
                    else
                      @via = "proprio"
                      AnilMontariaJSON.parse(bruto)
                    end
        @receitas = {} unless @receitas.is_a?(Hash)
        log("#{@receitas.length} receita(s) de #{alvo} (analisador: #{@via})")
      rescue => e
        log("falha ao ler #{alvo}: #{e.class}: #{e.message}")
        @receitas = {}
      end
      @receitas
    end

    def diagnostico
      receitas
      ["pwd=#{(Dir.pwd rescue "?")}",
       "json=#{defined?(JSON) ? "sim" : "NAO"}",
       "analisador=#{@via || "-"}",
       "receitas=#{@receitas.length}",
       "caminhos: #{(@diag || []).join(" | ")}"].join("\n")
    end

    # ⚠️ A CHAVE DA RECEITA PODE TRAZER A FORMA. E TEM DE TRAZER.
    #
    # As receitas sao gravadas com o nome do FICHEIRO do sprite, e os sprites de
    # forma alternativa chamam-se "ESPECIE_N": ha `NECROZMA.png`,
    # `NECROZMA_1.png` e `NECROZMA_2.png` na pasta dos followers, e o editor
    # gravou a montaria como `NECROZMA_1`.
    #
    # So que o jogo procurava sempre por `pkmn.species`, que da `NECROZMA` e
    # mais nada. Resultado: as receitas de forma — `NECROZMA_1`, `GIRATINA_1`,
    # `ARCEUS_8` — estavam TODAS inalcancaveis, e a sela respondia "nao pode ser
    # usado como montaria" a um bicho que tinha montaria feita.
    #
    # Agora tenta-se primeiro com a forma e so depois sem ela. Assim uma receita
    # feita para a forma 1 serve a forma 1, e uma receita sem sufixo continua a
    # servir o bicho todo, seja qual for a forma.
    def chave_de(especie, forma = 0)
      esp = especie.to_s.upcase
      f = forma.to_i
      if f > 0
        com_forma = "#{esp}_#{f}"
        return com_forma if receitas.key?(com_forma)
      end
      return esp if receitas.key?(esp)
      nil
    rescue
      nil
    end

    # ⚠️ Aceita tanto a especie crua como uma chave ja resolvida.
    #
    # A especie da montaria dos OUTROS jogadores chega pela rede ja como chave
    # (e o que o montar! guardou), e por isso tem de passar por aqui sem
    # tratamento: com forma 0, o `chave_de` cai directo no `receitas.key?`.
    def tem_receita?(especie, forma = 0)
      !chave_de(especie, forma).nil?
    end

    # ⚠️ A ESCALA DA MONTARIA E DA ESPECIE, NAO DA DIRECCAO.
    #
    # Ha lendarios desenhados pequenos que, montados, ficam do tamanho de um
    # cao. Esta e a ampliacao do BICHO — o cavaleiro nao cresce com ele, so se
    # realinha por cima.
    #
    # Guarda-se dentro de cada direccao (e o formato que o ficheiro ja tem) mas
    # le-se a primeira que aparecer: o editor escreve o mesmo valor nas quatro.
    ESCALA_MIN = 1.0
    ESCALA_MAX = 3.0

    def escala_montaria(especie)
      r = receitas[especie.to_s.upcase]
      return 1.0 unless r
      DIRECOES.each do |d|
        c = r[d]
        next unless c.is_a?(Hash)
        v = c["escala_mont"]
        next if v.nil?
        v = v.to_f
        return 1.0 if v <= 0
        return ESCALA_MIN if v < ESCALA_MIN
        return ESCALA_MAX if v > ESCALA_MAX
        return v
      end
      1.0
    rescue
      1.0
    end

    def receita(especie, direccao)
      r = receitas[especie.to_s.upcase]
      return nil unless r
      c = r[direccao]
      return nil unless c.is_a?(Hash)
      # ⚠️ O ASSENTO ESTA EM PIXEIS DA MONTARIA, LOGO CRESCE COM ELA.
      #
      # O `dx`/`dy` e o `galope` foram medidos com o bicho no tamanho natural.
      # Se ele passa ao dobro, o dorso tambem esta ao dobro de distancia do
      # chao: sem multiplicar, o cavaleiro ficava a flutuar a meio da barriga.
      # O `corte` e as mascaras sao fraccoes — esses nao se tocam.
      k = escala_montaria(especie)
      {
        :dx       => ((c["dx"] || 0).to_f * k).round,
        :dy       => ((c["dy"] || 0).to_f * k).round,
        :corte    => (c["corte"] || 0.0).to_f,
        :quadro   => (c["quadro"] || 0).to_i,
        :escala   => ((c["escala"] || 1.0).to_f rescue 1.0),
        :linha    => c["linha"],
        :espelhar => (c["espelhar"] ? true : false),
        :galope   => ((c["galope"].is_a?(Array) && c["galope"].length == 4) ?
                        c["galope"].map { |v| (v.to_f * k).round } : [0, 0, 0, 0]),
        # ⚠️ O contorno e uma lista de QUATRO, uma por quadro.
        #
        # Era um booleano para a direccao inteira. Mas a montaria balanca, e ha
        # passos em que o cavaleiro encosta ao corpo dela e outros em que nao —
        # nesses a borda desenhava uma linha contra o ar. As receitas antigas
        # trazem o booleano; expande-se para os quatro.
        :contorno => (c["contorno"].is_a?(Array) ?
                        (0..3).map { |i| !!c["contorno"][i] } :
                        [!!(c.key?("contorno") ? c["contorno"] : true)] * 4),
        :espessura => [[(c["espessura"] || 1).to_i, 1].max, 4].min,
        :rotacao   => [[(c["rotacao"] || 0).to_i, -45].max, 45].min,
        # Remendos: uma lista por quadro de DESTINO. Cada entrada e
        # [origem, x, y, largura, altura] em fraccoes do quadro da montaria.
        :remendos  => ((c["remendos"].is_a?(Array) && c["remendos"].length == 4) ?
                         c["remendos"] : [[], [], [], []]),
        :mascaras => (c["mascaras"].is_a?(Array) ? c["mascaras"] : [[], [], [], []])
      }
    end

    # ------------------------------------------------------------ estado
    def montado
      ($PokemonGlobal.anil_montaria rescue nil)
    end

    def montado?
      !montado.nil?
    end

    # ⚠️ QUEM ESTA MONTADO NAO E SO O $game_player.
    #
    # O sprite dos outros jogadores e um Sprite_Character normal, com um
    # AnilLanRework::RemotePeer no lugar do Game_Character (ele responde a
    # character_name, direction e pattern, que e tudo o que o motor pede). Basta
    # entao perguntar a montaria ao personagem em vez de a ir buscar sempre ao
    # $PokemonGlobal, e o mesmo enxerto passa a servir toda a gente.
    #
    # A do jogador local vem do save; a dos outros vem do pacote de estado.
    def montaria_de(personagem)
      return nil unless personagem
      return montado if defined?($game_player) && $game_player && personagem == $game_player
      # ⚠️ UM SELVAGEM SAI DAQUI NA PRIMEIRA LINHA.
      #
      # Isto corre no refresh_graphic E no update de CADA sprite, a cada frame.
      # Num mapa com encontros visiveis sao dezenas de Game_Event a passar por
      # aqui a 60 fps so para responderem "nao" — e a responder pelo caminho
      # mais caro, porque o respond_to? faz procura de metodo na cadeia toda.
      #
      # Montar so acontece em dois sitios: o $game_player e um RemotePeer. Todo
      # o resto e cenario, e um teste de classe corta-o de imediato.
      return nil if defined?(Game_Event) && personagem.is_a?(Game_Event)
      if personagem.respond_to?(:anil_montaria)
        v = (personagem.anil_montaria rescue nil)
        return nil if v.nil?
        v = v.to_s
        return nil if v.empty?
        # ⚠️ SEM RECEITA, NAO HA MONTARIA — NEM PARA O SPRITE DA MONTARIA.
        #
        # A especie chega crua do pacote, e quem esta a ver pode nao ter o
        # `montarias.json`. Sem esta guarda o charset_do_cavaleiro saltava as
        # quatro direccoes (`next unless cfg`) e devolvia um bitmap VAZIO: o
        # cavaleiro desaparecia e ficava o bicho a andar sozinho. Nunca se via
        # localmente porque o montar! ja recusa o que nao tem receita; foi a
        # rede que abriu o buraco.
        unless tem_receita?(v)
          avisar_sem_receita(v)
          return nil
        end
        return v
      end
      nil
    rescue
      nil
    end

    # Uma linha por especie, senao isto escrevia no log a 60 fps.
    def avisar_sem_receita(esp)
      @sem_receita ||= {}
      return if @sem_receita[esp]
      @sem_receita[esp] = true
      log("#{esp}: outro jogador esta montado e nao tenho a receita; fica a pe")
    rescue
      nil
    end

    # O `pkmn` e opcional: sem ele (o /montaria escrito a mao) monta-se a versao
    # de fabrica. Com ele, herda-se o brilho e o matiz daquele bicho.
    def montar!(especie, pkmn = nil)
      # ⚠️ Guarda-se a CHAVE, nao a especie.
      #
      # Dali para a frente tudo — a receita, o ficheiro do sprite, o que viaja
      # na rede — usa este valor. Sendo ja a chave resolvida, o resto do sistema
      # nao precisa de saber que existem formas.
      forma = (pkmn ? (pkmn.form.to_i rescue 0) : 0)
      esp = chave_de(especie, forma)
      if esp.nil?
        return [false, _INTL("Não há receita para {1}.", especie.to_s.upcase)]
      end
      unless FileTest.exist?(PASTA_MONTARIAS + esp + ".png") ||
             (pbResolveBitmap(PASTA_MONTARIAS + esp) rescue nil)
        return [false, _INTL("Falta o sprite {1}{2}.png.", PASTA_MONTARIAS, esp)]
      end
      $PokemonGlobal.anil_montaria = esp
      $PokemonGlobal.anil_montaria_pid = (pkmn ? (pkmn.personalID rescue nil) : nil)
      $PokemonGlobal.anil_montaria_shiny = pkmn ? ((pkmn.shiny? rescue false) ? true : false) : false
      $PokemonGlobal.anil_montaria_hue = begin
        (pkmn && (pkmn.super_shiny? rescue false) && pkmn.respond_to?(:super_shiny_hue)) ? pkmn.super_shiny_hue.to_i : 0
      rescue
        0
      end
      invalidar!
      log("montado em #{esp}")
      [true, esp]
    rescue => e
      log("falha ao montar: #{e.class}: #{e.message}")
      [false, e.message.to_s]
    end

    def desmontar!
      $PokemonGlobal.anil_montaria = nil
      $PokemonGlobal.anil_montaria_shiny = false
      $PokemonGlobal.anil_montaria_hue = 0
      $PokemonGlobal.anil_montaria_pid = nil
      invalidar!
      log("desmontado")
    rescue
      nil
    end

    # Larga as receitas E os charsets, para reler o ficheiro sem fechar o jogo.
    def recarregar!
      @receitas = nil
      invalidar!
      receitas.length
    rescue
      0
    end

    # ⚠️ ESTADO SOLIDO: MONTOU, MUDOU; ENTRE ISSO NAO MUDA NADA.
    #
    # O motor chama o refresh_graphic a CADA frame (0067, no update). O
    # refresh_graphic original sai logo numa guarda barata; o meu nao tinha
    # nenhuma, e por isso reconstruia a chave da cache — que percorre a equipa
    # com to_s.upcase, duas vezes — sessenta vezes por segundo, para o resultado
    # dar sempre o mesmo. Era isso que partia o FPS ao meio enquanto montado.
    #
    # Este numero sobe UMA vez por cada mudanca real (montar, desmontar,
    # recarregar receitas). Comparar dois inteiros custa nada e nao aloca, ao
    # contrario de construir uma chave em texto.
    def serial
      @serial ||= 0
    end

    # O selo do estado deste personagem. Inteiro de proposito: comparado por
    # frame, nao pode alocar.
    #
    # O jogador local anda pelo serial. Um RemotePeer nao tem serial nenhum — o
    # estado dele vem no pacote — entao mistura-se o que ele traz. As colisoes
    # sao inofensivas: no pior caso ficava uma coloracao por actualizar ate a
    # proxima mudanca, e nao ha crash nem fuga de bitmaps.
    def marca_de_estado(personagem)
      return serial if local?(personagem)
      esp = (personagem.anil_montaria rescue nil)
      h = esp ? esp.hash : 0
      h ^= 0x55 if (personagem.anil_montaria_shiny rescue false)
      h ^ ((personagem.anil_montaria_hue.to_i rescue 0) * 31)
    rescue
      serial
    end

    def invalidar!
      # A camada de luz sai da folha da montaria e da receita. Se uma delas muda,
      # a outra tem de cair junto — senao o /montaria recarregar deixava o brilho
      # antigo colado a uma folha nova.
      (AnilBrilhoMontaria.limpar! rescue nil) if defined?(AnilBrilhoMontaria)
      @serial = serial + 1
      # a memoria do Pokemon montado morre com o selo
      @pk_cache = nil
      @pk_cache_serial = nil
      @cache.each_value { |b| b.dispose if b && !b.disposed? }
      @cache = {}
      # e o aviso de "sem receita" tambem, senao depois de acrescentar a receita
      # e recarregar ele nunca mais voltava a dizer nada
      @sem_receita = {}
    rescue
      @serial = serial + 1
      @pk_cache = nil
      @pk_cache_serial = nil
      @cache = {}
      @sem_receita = {}
    end

    # --------------------------------------------------------- construcao
    def folha_da_skin(personagem = nil)
      personagem ||= $game_player
      nome = (personagem.character_name.to_s rescue "")
      return nil if nome.empty?
      ["Graphics/Skins/" + nome, "Graphics/Characters/" + nome].each do |cam|
        resolvido = (pbResolveBitmap(cam) rescue nil)
        next unless resolvido
        return Bitmap.new(resolvido)
      end
      nil
    rescue
      nil
    end

    # ⚠️ ROTACAO POR TRES CISALHAMENTOS, NAO POR INTERPOLACAO.
    #
    # O RGSS nao sabe rodar um Bitmap, e mexer pixel a pixel num quadro de 128
    # sao 262 144 leituras por folha. Um cisalhamento e so deslocar linhas (ou
    # colunas) INTEIRAS, e isso faz-se com blt, que e nativo: 3 passagens x 128
    # linhas x 16 quadros = 6144 chamadas.
    #
    # A decomposicao de Paeth (shear X, shear Y, shear X) tem ainda a
    # propriedade de NAO perder nem duplicar pixeis — medido no LUGIA, 2796
    # opacos em qualquer angulo. Uma rotacao com interpolacao borrava o pixel
    # art.
    #
    # ⚠️ E EXACTAMENTE O MESMO ALGORITMO DO EDITOR. Se um dos lados usasse a
    # rotacao "boa" de uma biblioteca, a pre-visualizacao voltava a mentir, como
    # ja aconteceu com o apagador.
    def rodar_quadro!(fonte, sx, sy, larg, alt, graus)
      base = Bitmap.new(larg, alt)
      base.blt(0, 0, fonte, Rect.new(sx, sy, larg, alt))
      return base if graus.to_i == 0

      a  = graus * Math::PI / 180.0
      t  = -Math.tan(a / 2.0)
      sn = Math.sin(a)
      cx = larg / 2.0
      cy = alt / 2.0

      p1 = Bitmap.new(larg, alt)
      y = 0
      while y < alt
        p1.blt(((y - cy) * t).round, y, base, Rect.new(0, y, larg, 1))
        y += 1
      end
      base.dispose

      p2 = Bitmap.new(larg, alt)
      x = 0
      while x < larg
        p2.blt(x, ((x - cx) * sn).round, p1, Rect.new(x, 0, 1, alt))
        x += 1
      end
      p1.dispose

      p3 = Bitmap.new(larg, alt)
      y = 0
      while y < alt
        p3.blt(((y - cy) * t).round, y, p2, Rect.new(0, y, larg, 1))
        y += 1
      end
      p2.dispose
      p3
    rescue
      Bitmap.new(larg, alt)
    end

    # ⚠️ A folha rodada e usada em TODO O LADO: no sprite da montaria, na fonte
    # das marcas e na medicao do balanco. Se a rotacao entrasse so no sprite, os
    # pedacos colados vinham do sitio errado.
    #
    # (Os remendos NAO vivem aqui: eles corrigem o CAVALEIRO, e sao aplicados no
    # charset_do_cavaleiro, sobre a folha da skin.)
    #
    # Fica em cache e pertence a este modulo — quem a usa NAO a liberta.
    def montaria_rodada(esp, shiny = false, hue = 0)
      # o brilho entra na chave: sem isso, trocar de um super shiny para um
      # normal reaproveitava a folha colorida do anterior
      chave = "rodada|#{esp}|#{shiny ? 1 : 0}|#{hue}"
      return @cache[chave] if @cache[chave] && !@cache[chave].disposed?
      orig = folha_da_montaria(esp, shiny, hue)
      return nil unless orig
      mw = orig.width / 4
      mh = orig.height / 4
      precisa = (0..3).any? do |d|
        cfg = receita(esp, DIRECOES[d]) || {}
        cfg[:rotacao].to_i != 0
      end
      unless precisa
        return (@cache[chave] = orig)
      end
      fora = Bitmap.new(orig.width, orig.height)
      4.times do |d|
        cfg = receita(esp, DIRECOES[d]) || {}
        g = (cfg[:rotacao] || 0).to_i
        4.times do |c|
          rodado = rodar_quadro!(orig, c * mw, d * mh, mw, mh, g)
          fora.blt(c * mw, d * mh, rodado, Rect.new(0, 0, mw, mh))
          rodado.dispose
        end
      end
      orig.dispose
      log("folha de #{esp} rodada")
      @cache[chave] = fora
    rescue => e
      log("falha ao rodar #{esp}: #{e.class}: #{e.message}")
      nil
    end

    # ⚠️ MONTADO, O FOLLOWER DEIXA DE EXISTIR — NAO E SO ESCONDIDO.
    #
    # Antes escondia-se o sprite dele a cada frame, e para isso era preciso
    # perguntar ao sistema de followers, sprite a sprite, quem era o follower.
    # Alem do custo, ficava sempre alguma coisa por tapar: primeiro a sombra, e
    # depois — a serio — as PEGADAS. O plugin dos passos faz o carimbo a partir
    # do FOLLOWER e nao do jogador (DUPLICATE_FOOTSTEPS_WITH_FOLLOWER = false),
    # portanto montado saia na areia a bota do treinador em vez da pata do
    # bicho, e nao havia como tapar isso escondendo sprites.
    #
    # O jogo ja tem a maneira certa, e e a mesma que as raids usam (ver o MOD
    # 106): FollowingPkmn.toggle_off. O evento desaparece de vez — sem sprite,
    # sem sombra, sem pegadas, e sem viajar na rede. Uma chamada ao montar e
    # outra ao desmontar, em vez de trabalho em todos os frames.
    # ⚠️ NAO SE DESLIGA O SISTEMA DE FOLLOWERS. TROCA-SE QUEM ELE MOSTRA.
    #
    # A primeira tentativa foi FollowingPkmn.toggle_off ao montar. Nao resulta:
    # o refresh_internal do plugin, quando `follower_toggled` fica false, sai
    # logo na primeira linha e NAO marca o `call_refresh`. Ou seja, deixa de
    # actualizar o follower mas nao o tira do mapa — ficava o bicho parado
    # atras do jogador, que e exactamente o que se queria evitar.
    #
    # E, mesmo que resultasse, apagava o follower por completo. O que se quer e
    # outra coisa: nao ver o MESMO Pokemon duas vezes (montado e a seguir).
    # Entao o que muda e a identidade — o follower passa a ser o proximo apto
    # que nao seja o que se esta a montar. Havendo so um, nao ha follower.
    #
    # Ver o pokemon_do_follower, e os tres sitios que o passaram a usar.

    # ⚠️ SO SE VOLTA A LIGAR O QUE ESTAVA LIGADO.
    #
    # Quem tinha o follower desligado a mao nao o quer de volta so por ter
    # andado montado. Por isso se guarda o estado anterior em vez de assumir.
    def repor_follower!
      antes = ($PokemonGlobal.anil_montaria_follower_antes rescue nil)
      $PokemonGlobal.anil_montaria_follower_antes = nil
      return unless defined?(FollowingPkmn)
      return if antes.nil?
      if antes[0] == 1
        FollowingPkmn.toggle_on(false)
      else
        FollowingPkmn.toggle_off(false)
      end
      ($PokemonGlobal.follower_toggle_locked = (antes[1] == 1)) rescue nil
      log("follower reposto (estava #{antes[0] == 1 ? "ligado" : "desligado"})")
    rescue => e
      log("nao consegui repor o follower: #{e.class}: #{e.message}")
    end

    # ⚠️ REDE DE SEGURANCA AO ARRANCAR.
    #
    # Se o jogo fechar a meio de uma montaria, o save fica com o follower
    # desligado e com o estado anterior por repor — e o jogador ficava sem
    # follower para sempre, sem perceber porque. Isto corre uma vez no arranque
    # e desfaz exactamente esse caso: ha estado guardado mas ja nao ha montaria.
    def reparar_follower_no_arranque!
      return if montado?
      return unless ($PokemonGlobal.anil_montaria_follower_antes rescue nil)
      log("estado de follower por repor de uma sessao anterior; a repor")
      repor_follower!
    rescue
      nil
    end

    # ⚠️ A COR LE-SE DO POKEMON VIVO, NAO DE UMA COPIA GUARDADA.
    #
    # A primeira versao gravava o brilho no $PokemonGlobal ao montar. Bastava
    # uma entrada em que esse valor nao voltasse — e a montaria aparecia sem
    # cor ate desmontar e montar outra vez, que era o unico sitio que voltava a
    # escrever o campo.
    #
    # Agora o campo guardado e so uma rede: quem manda e o Pokemon que esta na
    # equipa. Se ele la estiver, a cor esta certa por construcao e nao ha estado
    # nenhum para se perder pelo caminho.
    #
    # O personalID desempata: dois Arcanine na mesma equipa podem ter coloracoes
    # diferentes, e sem ele apanhava-se o primeiro que aparecesse.
    # ⚠️ PROCURA-SE UMA VEZ POR ESTADO, NAO UMA VEZ POR FRAME.
    #
    # Enquanto se esta montado o bicho nao muda: nem de especie, nem de
    # coloracao. Percorrer a equipa a 60 fps para chegar sempre ao mesmo
    # Pokemon era trabalho puro — e com `to_s.upcase` a alocar texto de cada
    # vez, que num telemovel e o que faz o recolector de lixo acordar.
    #
    # Ressalva conhecida: se o Pokemon montado for depositado no PC SEM
    # desmontar, isto fica a apontar para ele ate desmontar. A montaria mantem a
    # cor antiga e mais nada; nao ha crash. Valeu a troca.
    def pokemon_da_montaria
      s = serial
      return @pk_cache if @pk_cache_serial == s
      @pk_cache_serial = s
      @pk_cache = procurar_pokemon_da_montaria
    end

    # ⚠️ QUEM O FOLLOWER DEVE MOSTRAR.
    #
    # Sem montaria e o de sempre: o primeiro apto. Montado, salta-se o que esta
    # a ser montado — compara-se pelo personalID e nao pela especie, senao dois
    # Arcanine na equipa faziam desaparecer o errado.
    #
    # Devolve nil quando nao sobra ninguem, e o plugin ja trata disso: o
    # refresh_internal com `first_pkmn` nil poe o follower a false.
    def pokemon_do_follower
      lista = ($player.party rescue nil) || []
      aptos = lista.select { |pk| pk && !(pk.egg? rescue true) && !(pk.fainted? rescue true) }
      return (aptos.first || lista.first) unless montado?
      montado_pk = pokemon_da_montaria
      if montado_pk
        pid = (montado_pk.personalID rescue nil)
        aptos = aptos.reject { |pk| pid && (pk.personalID rescue nil) == pid }
      else
        alvo = montado.to_s.upcase
        aptos = aptos.reject { |pk| (pk.species.to_s.upcase rescue "") == alvo }
      end
      aptos.first
    rescue
      ($player.first_able_pokemon rescue nil)
    end

    def procurar_pokemon_da_montaria
      esp = montado
      return nil unless esp
      alvo = esp.to_s.upcase
      pid = ($PokemonGlobal.anil_montaria_pid rescue nil)
      primeiro = nil
      lista = ($player.party rescue nil) || []
      lista.each do |pk|
        next unless pk
        next unless (pk.species.to_s.upcase rescue "") == alvo
        return pk if pid && (pk.personalID rescue nil) == pid
        primeiro ||= pk
      end
      primeiro
    rescue
      nil
    end

    # ⚠️ A COR E DE QUEM ESTA MONTADO, NAO "A COR DA MONTARIA".
    #
    # Estas duas nao levavam personagem: liam sempre a equipa LOCAL. Enquanto so
    # o proprio jogador via a sua montaria isso passava despercebido; assim que
    # os outros passaram a ve-la, a montaria de um jogador remoto ficava com a
    # cor de um Pokemon da MINHA equipa — e as chaves de cache, que tambem usam
    # estes valores, misturavam os dois.
    #
    # Agora quem responde e o personagem: o jogador local pergunta a equipa, e um
    # RemotePeer traz os valores dele proprio, vindos no pacote de estado.
    def local?(personagem)
      personagem.nil? || (defined?($game_player) && $game_player && personagem.equal?($game_player))
    rescue
      true
    end

    # ⚠️ A CELULA DO CAVALEIRO TEM 72 PX DE CEU VAZIO POR CIMA.
    #
    # O charset montado e `mh + MARGEM_CIMA` de alto, e essa margem existe para
    # caber um cavaleiro com dy muito negativo. So que quem desenha etiquetas
    # por cima do boneco — o nome do jogador, os balões — mede-as pelo `oy` do
    # sprite, que e a altura da CELULA. Com 72 px de vazio la dentro, o nome
    # subia para fora do bicho.
    #
    # Isto devolve quanto e que ha a descontar. Zero para quem nao esta montado.
    def folga_da_celula(personagem)
      return 0 unless (montaria_de(personagem) rescue nil)
      MARGEM_CIMA
    rescue
      0
    end

    def montaria_shiny?(personagem = nil)
      unless local?(personagem)
        return (personagem.anil_montaria_shiny == true) if personagem.respond_to?(:anil_montaria_shiny)
        return false
      end
      pk = pokemon_da_montaria
      return ((pk.shiny? rescue false) ? true : false) if pk
      ($PokemonGlobal.anil_montaria_shiny == true) rescue false
    rescue
      false
    end

    def montaria_hue(personagem = nil)
      unless local?(personagem)
        return (personagem.anil_montaria_hue.to_i) if personagem.respond_to?(:anil_montaria_hue)
        return 0
      end
      pk = pokemon_da_montaria
      if pk
        return 0 unless (pk.super_shiny? rescue false)
        return 0 unless pk.respond_to?(:super_shiny_hue)
        return pk.super_shiny_hue.to_i
      end
      ($PokemonGlobal.anil_montaria_hue.to_i rescue 0)
    rescue
      0
    end

    # ⚠️ O BRILHO FAZ-SE COMO NO FOLLOWER: OUTRA PASTA + ROTACAO DE MATIZ.
    #
    # E a mesma regra do resolve_follower_char (000_Multiplayer_Online): o shiny
    # tem um desenho proprio em "Followers shiny/", e o super shiny e o desenho
    # com o matiz rodado por cima. Nao ha sprite por-Pokemon — o matiz e que
    # distingue as coloracoes.
    #
    # ⚠️ O MATIZ VAI NO CONSTRUTOR, NUNCA POR hue_change.
    #
    # O AnimatedBitmap normal PARTILHA o bitmap da RPG::Cache. Rodar o matiz
    # nesse objecto acumula e escapa para o resto do jogo — ja aconteceu. Ao
    # construtor, ele guarda a versao rodada com uma chave propria.
    #
    # E copia-se para um Bitmap nosso antes de largar o AnimatedBitmap, senao
    # ficavamos a apontar para memoria que ele acabou de libertar.
    def caminho_da_montaria(esp, shiny = false)
      if shiny
        brilhante = "Graphics/Characters/Followers shiny/" + esp.to_s
        r = (pbResolveBitmap(brilhante) rescue nil)
        return r if r
      end
      (pbResolveBitmap(PASTA_MONTARIAS + esp.to_s) rescue nil)
    rescue
      nil
    end

    # ⚠️ A AMPLIACAO ENTRA AQUI, E SO AQUI.
    #
    # Este e o unico sitio por onde a folha da montaria entra no jogo. Tudo o
    # que vem a seguir — a rotacao, a medicao do dorso, os pedacos colados sobre
    # o cavaleiro, as camadas de brilho, o sprite por baixo do jogador — le a
    # folha DAQUI e mede-se por ela. Ampliar num sitio so faz o resto seguir
    # sozinho, sem uma unica conta de escala espalhada pelo caminho.
    def folha_da_montaria(esp, shiny = false, hue = 0)
      resolvido = caminho_da_montaria(esp, shiny)
      return nil unless resolvido
      hue = hue.to_i
      base = if hue.zero?
               Bitmap.new(resolvido)
             else
               ab = AnimatedBitmap.new(resolvido, hue)
               copia = Bitmap.new(ab.width, ab.height)
               copia.blt(0, 0, ab.bitmap, Rect.new(0, 0, ab.width, ab.height))
               ab.dispose
               copia
             end
      ampliar_folha(base, escala_montaria(esp))
    rescue
      (Bitmap.new(resolvido) rescue nil)
    end

    # ⚠️ AMPLIA-SE QUADRO A QUADRO, E NAO A FOLHA INTEIRA.
    #
    # A folha e uma grelha de 4x4. Esticar a imagem toda de uma vez deixa a
    # largura do quadro em `(w * k) / 4`, que quase nunca da inteiro — e o erro
    # acumula-se de coluna para coluna ate as poses sairem cortadas. Medindo o
    # quadro primeiro e multiplicando por 4 no fim, a grelha fica exacta.
    #
    # O `stretch_blt` do motor e vizinho-mais-proximo: nao inventa cores nem
    # esbate as bordas. Com um factor inteiro (2x, 3x) o pixel fica quadrado e
    # perfeito; com um factor partido (1,5x) ha linhas com um pixel a mais, que
    # e o preco de qualquer ampliacao nao inteira e continua sem borrar.
    def ampliar_folha(base, k)
      return base unless base
      return base if k.nil? || (k - 1.0).abs < 0.001
      mw = base.width / 4
      mh = base.height / 4
      nw = [1, (mw * k).round].max
      nh = [1, (mh * k).round].max
      fora = Bitmap.new(nw * 4, nh * 4)
      4.times do |d|
        4.times do |c|
          fora.stretch_blt(Rect.new(c * nw, d * nh, nw, nh),
                           base, Rect.new(c * mw, d * mh, mw, mh))
        end
      end
      base.dispose
      log("folha ampliada #{k}x -> #{nw}x#{nh} por quadro")
      fora
    rescue => e
      log("falha ao ampliar: #{e.class}: #{e.message}")
      base
    end

    # ⚠️ A MASCARA NAO APAGA: COLA A MONTARIA POR CIMA.
    #
    # Apagar deixava buracos. Onde se apagava e a montaria NAO tinha pixel,
    # via-se o mapa atraves do cavaleiro — e como a mascara serve todas as
    # skins, uma que assentasse numa comia a cabeca de outra mais alta.
    #
    # A marca quer dizer "isto e da montaria, nao do cavaleiro". Entao copia-se
    # o pedaco CORRESPONDENTE da montaria para cima do cavaleiro. Onde ela e
    # opaca, tapa; onde e transparente, o blt nao escreve nada e o cavaleiro
    # fica. Nunca ha buraco, e nao e preciso testar pixel a pixel — a
    # transparencia da origem trata disso sozinha, numa unica chamada nativa.
    #
    # ⚠️ E QUADRADA, NAO REDONDA.
    #
    # Estamos a escolher pixeis num sprite de 64x64. Um circulo rasterizado
    # obriga a adivinhar que pixeis entram na borda, e foi dai que veio a
    # divergencia entre o PIL e o Ruby. Um quadrado da o mesmo numero nas duas
    # linguagens, sem margem para interpretacao.
    #
    # A marca e [x, y, r] em fraccoes, com r = META-ARESTA.

    # ⚠️ Marcas repetidas: o pincel grava uma por movimento do rato, e muitas
    # caem quase no mesmo sitio. Juntar as que coincidem ao pixel corta o
    # trabalho para uma fraccao sem mudar o resultado.
    def marcas_uteis(lista, w, h)
      return [] unless lista.is_a?(Array)
      vistas = {}
      lista.each do |m|
        next unless m.is_a?(Array) && m.length >= 3
        chave = [(m[0].to_f * w).round, (m[1].to_f * h).round, (m[2].to_f * h).round]
        next if vistas[chave]
        vistas[chave] = m
      end
      vistas.values
    end

    # ⚠️ FECHAR O CONTORNO NA COSTURA.
    #
    # Onde a camada da montaria e colada por cima, ela come o contorno preto que
    # o cavaleiro tinha ali, e os dois desenhos passam a encostar sem separacao —
    # no pixel art isso le-se como uma so massa. Poe-se preto de um pixel
    # exactamente na fronteira, do lado do CAVALEIRO: e a silhueta dele que se
    # fecha, tal como o resto do contorno que ele ja traz.
    #
    # ⚠️ So se varre a area MARCADA, mais uma orla de um pixel.
    #
    # Mexer pixel a pixel e caro em RGSS. A celula inteira seriam 8700 leituras
    # vezes 16 quadros; a caixa das marcas e uma fraccao disso. E corre uma
    # unica vez, ao montar.
    # ⚠️ A FRONTEIRA CRESCE A CADA PASSAGEM.
    #
    # Para uma borda de N pixeis nao chega repetir o teste: os pixeis pintados na
    # volta anterior tem de passar a contar como "montaria" na volta seguinte,
    # senao pinta-se sempre a mesma linha. Por isso ha um bitmap `ocupado`, que
    # comeca igual ao `tapa` e vai engordando.
    def contornar!(destino, cav, tapa, x0, y0, x1, y1, larg, alt, espessura = 1)
      preto = Color.new(0, 0, 0, 255)
      vizinhos = [[1, 0], [-1, 0], [0, 1], [0, -1]]
      ocupado = Bitmap.new(larg, alt)
      ocupado.blt(0, 0, tapa, Rect.new(0, 0, larg, alt))

      passo = 0
      while passo < [[espessura.to_i, 1].max, 4].min
        yi = [y0 - 1 - passo, 1].max
        yf = [y1 + 1 + passo, alt - 1].min
        xi = [x0 - 1 - passo, 1].max
        xf = [x1 + 1 + passo, larg - 1].min
        novos = []
        y = yi
        while y < yf
          x = xi
          while x < xf
            # O preto vai no pixel do CAVALEIRO, nao no da montaria: no pixel art
            # e a silhueta da figura de cima que se fecha.
            if cav.get_pixel(x, y).alpha > 0 && ocupado.get_pixel(x, y).alpha <= 0
              vizinhos.each do |dx, dy|
                next if ocupado.get_pixel(x + dx, y + dy).alpha <= 0
                novos.push([x, y])
                break
              end
            end
            x += 1
          end
          y += 1
        end
        break if novos.empty?
        novos.each do |px, py|
          destino.set_pixel(px, py, preto)
          ocupado.set_pixel(px, py, preto)
        end
        passo += 1
      end
      ocupado.dispose
    rescue
      nil
    end

    # ⚠️ O BALANCO SAI DO PROPRIO SPRITE DA MONTARIA.
    #
    # Um bicho a andar sobe e desce, e o cavaleiro tem de acompanhar — parado,
    # parece colado ao ar. Mas isso nao se pede ao editor: o dado ja esta no
    # sprite. Mede-se, em cada quadro, onde comeca o corpo do bicho na faixa
    # central (a do dorso, que e onde ele assenta):
    #
    #   DONPHAN  baixo  [20, 22, 20, 22]   -> 2 px, nos quadros 1 e 3
    #   ARCANINE baixo  [ 4,  6,  4,  6]
    #   RAYQUAZA baixo  [42, 44, 46, 48]   -> ondula em vez de trotar
    #
    # O quadro 0 e a referencia, porque foi com ele a vista que o dy foi
    # afinado no editor; os outros deslocam-se pela diferenca.
    #
    # Varre-se so a faixa do meio e para-se na primeira linha opaca — sao umas
    # centenas de get_pixel por quadro, uma unica vez.
    def topo_do_dorso(bmp, col, lin, cw, ch)
      x0 = (col * cw) + (cw / 4)
      x1 = (col * cw) + cw - (cw / 4)
      y = 0
      while y < ch
        x = x0
        while x < x1
          return y if bmp.get_pixel(x, (lin * ch) + y).alpha > 0
          x += 1
        end
        y += 1
      end
      0
    rescue
      0
    end

    # ⚠️ REMENDOS: PEDACOS DE OUTRA POSE, COLADOS NO BONECO.
    #
    # O `quadro` da receita escolhe UMA pose da skin para as quatro colunas — e
    # ha sempre um passo em que uma perna ou um braco fica melhor noutra. Cada
    # entrada e [pose de origem, x, y, largura, altura] em fraccoes do quadro da
    # skin; recorta-se essa zona da pose de origem e cola-se por cima.
    #
    # Como isto corre por COLUNA do charset, da tambem para voltar a animar o
    # cavaleiro, remendando cada coluna de uma pose diferente.
    #
    # ⚠️ O 6.º CAMPO, "ESPELHADO", ATRAVESSA O PEDACO PARA O OUTRO LADO.
    #
    # E o caso mais usado: um dos bracos fica bem e o outro nao. Marca-se o que
    # esta bem e ele vai, virado, para a posicao reflectida em torno do eixo do
    # QUADRO — o mesmo eixo que o `espelhar` da receita usa. O corpo esta
    # centrado no quadro em 80% das skins medidas, portanto os dois lados
    # coincidem.
    #
    # Espelhada, a marca faz sentido com a origem IGUAL ao destino; sem espelho
    # isso nao fazia nada. Quem trata dessa diferenca e o editor, ao gravar.
    #
    # As receitas antigas tem cinco campos e leem-se na mesma: sem 6.º campo,
    # nao ha espelho.
    def pose_remendada(skin, sw, sh, col_skin, lin_skin, lista)
      base = Bitmap.new(sw, sh)
      base.blt(0, 0, skin, Rect.new(col_skin * sw, lin_skin * sh, sw, sh))
      Array(lista).each do |r|
        next unless r.is_a?(Array) && r.length >= 5
        de = r[0].to_i % 4
        x0 = (r[1].to_f * sw).round
        y0 = (r[2].to_f * sh).round
        w  = [1, (r[3].to_f * sw).round].max
        h  = [1, (r[4].to_f * sh).round].max
        next if x0 >= sw || y0 >= sh || x0 + w <= 0 || y0 + h <= 0
        if x0 < 0
          w += x0
          x0 = 0
        end
        if y0 < 0
          h += y0
          y0 = 0
        end
        w = sw - x0 if x0 + w > sw
        h = sh - y0 if y0 + h > sh
        next if w <= 0 || h <= 0

        if r.length >= 6 && r[5] && r[5] != 0
          # vira-se o recorte para um bitmap a parte (a largura negativa e o
          # espelho, como no `espelhar` da receita) e assenta-se do outro lado
          dx = sw - (x0 + w)
          next if dx < 0 || dx + w > sw
          virado = Bitmap.new(w, h)
          virado.stretch_blt(Rect.new(w, 0, -w, h), skin,
                             Rect.new((de * sw) + x0, (lin_skin * sh) + y0, w, h))
          base.fill_rect(dx, y0, w, h, Color.new(0, 0, 0, 0))
          base.blt(dx, y0, virado, Rect.new(0, 0, w, h))
          virado.dispose
          next
        end

        # limpar antes de colar: o blt respeita a transparencia da origem, e sem
        # isto o que estava por baixo assomava pelos buracos do pedaco
        base.fill_rect(x0, y0, w, h, Color.new(0, 0, 0, 0))
        base.blt(x0, y0, skin, Rect.new((de * sw) + x0, (lin_skin * sh) + y0, w, h))
      end
      base
    end

    # Constroi o charset 4x4 do cavaleiro: coluna = padrao, linha = direccao.
    def charset_do_cavaleiro(personagem = nil)
      personagem ||= $game_player
      esp = montaria_de(personagem)
      return nil unless esp
      return nil unless tem_receita?(esp)
      # ⚠️ A chave e (montaria, skin) e NAO o jogador: dois jogadores com a
      # mesma montaria e a mesma skin partilham o charset, que e o caso comum
      # numa rota cheia. Construir um por pessoa era o que tornava isto caro.
      shiny = montaria_shiny?(personagem)
      hue   = montaria_hue(personagem)
      chave = "#{esp}|#{(personagem.character_name rescue "")}|#{shiny ? 1 : 0}|#{hue}"
      return @cache[chave] if @cache[chave] && !@cache[chave].disposed?

      skin = folha_da_skin(personagem)
      mont = montaria_rodada(esp, shiny, hue)   # em cache; NAO se liberta aqui
      return nil unless skin && mont

      sw = skin.width / 4
      sh = skin.height / 4
      mw = mont.width / 4
      mh = mont.height / 4

      cw = [sw, mw].max
      ch = mh + MARGEM_CIMA

      destino = Bitmap.new(cw * 4, ch * 4)

      4.times do |d|
        cfg = receita(esp, DIRECOES[d])
        next unless cfg

        # balanco: quanto e que o dorso sobe ou desce em cada quadro
        topos = (0..3).map { |c| topo_do_dorso(mont, c, d, mw, mh) }
        balanco = topos.map { |t| t - topos[0] }
        lin_skin = cfg[:linha].nil? ? d : (cfg[:linha].to_i % 4)
        col_skin = cfg[:quadro] % 4
        escala = cfg[:escala]
        escala = 1.0 if escala <= 0

        nw = [1, (sw * escala).round].max
        nh = [1, (sh * escala).round].max

        4.times do |c|
          # 1. o quadro escolhido da skin, isolado e ja remendado
          #
          # ⚠️ O REMENDO ENTRA ANTES DA ESCALA E DO ESPELHO.
          #
          # As fraccoes da receita sao do quadro da skin em tamanho natural, tal
          # como o corte. Remendar depois de ampliar obrigava a ampliar tambem a
          # origem e a arredondar duas vezes; antes, e um recorte exacto e a
          # mesma receita serve qualquer escala e a linha espelhada.
          pose = pose_remendada(skin, sw, sh, col_skin, lin_skin, cfg[:remendos][c])
          celula = Bitmap.new(nw, nh)
          celula.stretch_blt(Rect.new(0, 0, nw, nh), pose, Rect.new(0, 0, sw, sh))
          pose.dispose

          # 2. espelho ANTES do corte e do apagar, para as marcas baterem certo
          if cfg[:espelhar]
            espelhada = Bitmap.new(nw, nh)
            espelhada.stretch_blt(Rect.new(nw, 0, -nw, nh), celula, Rect.new(0, 0, nw, nh))
            celula.dispose
            celula = espelhada
          end

          # 3. corte, medido a partir de BAIXO
          if cfg[:corte] > 0
            y = (nh * (1.0 - cfg[:corte])).round
            celula.fill_rect(0, y, nw, nh - y, Color.new(0, 0, 0, 0))
          end

          # 4. assentar: alinhado por BAIXO (e onde os pes estao), mais o desvio,
          #    a compensacao da escala em torno do assento, o balanco medido no
          #    bicho, e o galope escrito na receita
          px = ((cw - nw) / 2) + cfg[:dx]
          py = ch - sh + cfg[:dy]
          py += (sh * (1.0 - escala) * (1.0 - cfg[:corte])).round
          py += balanco[c]
          py += cfg[:galope][c].to_i

          # ⚠️ EM CAMADAS, PARA SE SABER ONDE UMA ACABA E A OUTRA COMECA.
          #
          # Sem separar o cavaleiro dos pedacos colados da montaria nao ha como
          # descobrir a fronteira entre os dois — que e onde o contorno vai.
          cav = Bitmap.new(cw, ch)
          cav.blt(px, py, celula, Rect.new(0, 0, nw, nh))
          celula.dispose

          # 5. os pedacos da montaria que o pincel marcou.
          #
          # A montaria assenta na celula em (mont_x, mont_y) — o mesmo sitio onde
          # o Sprite_Montaria a desenha por baixo — portanto copiar dali reproduz
          # exactamente "a montaria por cima". As marcas estao em coordenadas da
          # MONTARIA.
          mont_x = (cw - mw) / 2
          mont_y = ch - mh
          tapa = Bitmap.new(cw, ch)
          mx0 = cw; my0 = ch; mx1 = 0; my1 = 0
          marcas_uteis(cfg[:mascaras][c], mw, mh).each do |m|
            mr = [m[2].to_f * mh, 0.5].max
            lado = [1, (mr * 2).round].max
            ox = ((m[0].to_f * mw) - mr).round
            oy = ((m[1].to_f * mh) - mr).round
            ax = mont_x + ox
            ay = mont_y + oy
            tapa.blt(ax, ay, mont, Rect.new((c * mw) + ox, (d * mh) + oy, lado, lado))
            mx0 = ax if ax < mx0
            my0 = ay if ay < my0
            mx1 = ax + lado if ax + lado > mx1
            my1 = ay + lado if ay + lado > my1
          end

          # 6. juntar as duas camadas e fechar o contorno na costura
          junto = Bitmap.new(cw, ch)
          junto.blt(0, 0, cav, Rect.new(0, 0, cw, ch))
          junto.blt(0, 0, tapa, Rect.new(0, 0, cw, ch))
          if cfg[:contorno][c] && mx1 > mx0
            contornar!(junto, cav, tapa, mx0, my0, mx1, my1, cw, ch, cfg[:espessura])
          end
          destino.blt(c * cw, d * ch, junto, Rect.new(0, 0, cw, ch))
          junto.dispose
          cav.dispose
          tapa.dispose
        end
      end

      skin.dispose
      # o `mont` esta em cache e e reutilizado pelo Sprite_Montaria; nao se liberta
      @cache[chave] = destino
      log("charset do cavaleiro gerado: #{cw}x#{ch} por celula")
      destino
    rescue => e
      log("falha ao gerar o charset: #{e.class}: #{e.message}")
      nil
    end
  end
end

#-------------------------------------------------------------------------------
# O sprite da montaria, por baixo do jogador. Copia deliberada do
# Sprite_SurfBase (0069), que e o mecanismo que o jogo ja usa para o surf.
#-------------------------------------------------------------------------------
class Sprite_Montaria
  def initialize(parent_sprite, viewport = nil)
    @parent = parent_sprite
    @viewport = viewport
    @sprite = nil
    @bitmap = nil
    @especie = nil
    @disposed = false
    update
  end

  def dispose
    return if @disposed
    @sprite&.dispose
    @sprite = nil
    @bitmap = nil          # em cache no AnilMontaria
    @parent = nil
    @disposed = true
  end

  def disposed?; @disposed; end

  def personagem
    @parent&.character
  end

  def update
    return if disposed?
    esp = (AnilMontaria.montaria_de(personagem) rescue nil)
    if esp.nil?
      if @sprite
        @sprite.dispose
        @sprite = nil
      end
      @bitmap = nil        # em cache no AnilMontaria; nao e nosso para libertar
      @especie = nil
      return
    end

    # ⚠️ Reobter tambem quando o bitmap MORREU.
    #
    # O invalidar! (que o /montaria recarregar chama) liberta a cache. Se so se
    # comparasse a especie, ficavamos a apontar para um bitmap ja libertado — e
    # com a MESMA montaria a comparacao nao acusava nada.
    # a cor entra na comparacao: o mesmo bicho pode mudar de coloracao (troca de
    # Pokemon montado) sem a especie mudar
    # ⚠️ PELO SELO, E NAO PERGUNTANDO A EQUIPA.
    #
    # Isto construia um Array e chamava o montaria_shiny? e o montaria_hue a
    # cada frame — dois percursos da equipa e uma alocacao — so para descobrir
    # que nada tinha mudado. O selo responde ao mesmo com uma comparacao de
    # inteiros. As duas perguntas caras ficam onde fazem falta: dentro do if.
    est = (AnilMontaria.marca_de_estado(personagem) rescue nil)
    if @especie != esp || @estado != est || @bitmap.nil? || @bitmap.disposed?
      @estado = est
      # ⚠️ A folha rodada pertence ao AnilMontaria e esta em cache: aqui so se
      # guarda a referencia, nunca se liberta. Libertar daqui deixava o charset
      # do cavaleiro a apontar para um bitmap morto.
      @bitmap = AnilMontaria.montaria_rodada(esp,
                                             AnilMontaria.montaria_shiny?(personagem),
                                             AnilMontaria.montaria_hue(personagem))
      @especie = esp
      @sprite&.dispose
      @sprite = nil
    end
    return unless @bitmap

    @sprite = Sprite.new(@viewport) if !@sprite
    @sprite.bitmap = @bitmap
    cw = @bitmap.width / 4
    ch = @bitmap.height / 4

    ev = personagem
    return unless ev

    # Mesmo indexamento do Sprite_Character: coluna = padrao, linha = direccao.
    sx = ev.pattern * cw
    sy = ((ev.direction - 2) / 2) * ch
    @sprite.src_rect.set(sx, sy, cw, ch)
    @sprite.x = @parent.x
    @sprite.y = @parent.y
    @sprite.ox = cw / 2
    @sprite.oy = ch
    # ⚠️ DOIS degraus atras, e nao um.
    #
    # O cavaleiro esta em `parent.z` e a montaria estava em `-1`, sem nada pelo
    # meio. A camada de brilho (MOD 165) precisa de ficar ENTRE os dois, e dois
    # sprites no mesmo z desenham-se por ordem indefinida — nao servia deixar os
    # dois no mesmo sitio. Sao precisos DOIS degraus livres: um para a camada
    # que apaga a cor por baixo (-2) e outro para a que soma a luz (-1). A
    # montaria fica em -3 e continua por baixo do cavaleiro, como sempre esteve.
    # ⚠️ QUANTO DESCE DEPENDE DE QUANTOS GRUPOS DE BRILHO HA.
    #
    # Cada grupo ocupa dois degraus entre a montaria e o cavaleiro: um para a
    # camada que apaga a cor por baixo, outro para a que soma a luz. Sem brilho
    # nenhum e o -1 de sempre.
    desloca = 1
    desloca = (AnilBrilhoMontaria.deslocamento_z(esp) rescue 1) if defined?(AnilBrilhoMontaria)
    @sprite.z = @parent.z - desloca
    @sprite.visible = @parent.visible
    @sprite.opacity = @parent.opacity

    # ⚠️ A MONTARIA TEM DE LEVAR A MESMA TONALIDADE DO JOGADOR.
    #
    # O Sprite_Character#update chama pbDayNightTint(self), e os pedacos da
    # montaria que colamos vivem DENTRO desse sprite — portanto sao tingidos. O
    # sprite da montaria aqui ao lado nao levava nada, e a diferenca aparecia
    # como uma mancha exactamente por cima da mascara.
    #
    # A cor nao e aleatoria: o tom da noite e (-70, -90, +15, 55), ou seja tira
    # vermelho, tira mais verde ainda e ACRESCENTA azul. Sobre cinzento da roxo.
    #
    # Copia-se o tom JA CALCULADO do pai em vez de chamar o pbDayNightTint outra
    # vez: assim segue tambem o que os plugins do clima lhe fizerem por cima.
    t = @parent.tone
    @sprite.tone.set(t.red, t.green, t.blue, t.gray) if t
    c = @parent.color
    @sprite.color.set(c.red, c.green, c.blue, c.alpha) if c
  rescue
    nil
  end
end

#-------------------------------------------------------------------------------
# ⚠️ MONTADO, A CORRIDA NAO TROCA O CHARSET.
#
# No Android, segurar Z para correr travava o jogo por instantes. A causa esta
# no set_movement_type (0052_Game_Player): ao passar a :running ele faz
#
#     @character_name = pbGetPlayerCharset(meta.run_charset)
#
# e o nome mudar acorda o refresh_graphic — que, montado, reconstroi o charset
# inteiro do cavaleiro: 16 celulas, cada uma com a mascara e o contorno. No PC
# nem se nota; num telemovel e o tranco que se ve.
#
# Montado isso nao serve para nada: o boneco esta sentado, nao ha animacao de
# corrida para mostrar. Entao guarda-se o nome antes e repoe-se depois — a
# VELOCIDADE fica na mesma, que e o que o jogador quer de facto ao segurar Z.
#
# ⚠️ E NA AGUA TAMBEM NAO.
#
# A primeira versao deixava passar a agua e a bicicleta, com a ideia de que ai
# o charset "tem de mudar". Nao tem: montado, o veiculo E a montaria. Ao entrar
# na agua o jogo trocava o boneco pelo charset de surf — o Pokemon escolhido
# desaparecia, ficava o treinador em cima da jangada, e por baixo continuava o
# sprite da montaria a ser desenhado. Agora a regra e uma so e sem excepcoes:
#
#     enquanto estiver montado, o charset do jogador nao muda.
#
# A VELOCIDADE continua a ser a do tipo de movimento — quem nada montado nada a
# velocidade de surf. So o desenho e que fica quieto.
#-------------------------------------------------------------------------------
module AnilMontaria
  # Ja nao ha lista: montado, protegem-se TODOS os tipos. A constante fica para
  # nao partir quem a leia de fora.
  TIPOS_EM_TERRA = [:running, :walking, :walking_stopped, :jumping,
                    :ice_sliding, :cycling, :cycling_fast, :cycling_jumping,
                    :cycling_stopped].freeze

  class << self
    def instalar_patch_corrida!
      return false unless defined?(Game_Player)
      return false if Game_Player.method_defined?(:anil_montaria_orig_set_movement_type)
      Game_Player.class_eval do
        alias_method :anil_montaria_orig_set_movement_type, :set_movement_type

        def set_movement_type(type)
          antes = @character_name
          ret = anil_montaria_orig_set_movement_type(type)
          if (AnilMontaria.montado? rescue false) && !antes.to_s.empty?
            @character_name = antes
          end
          ret
        end

        # ⚠️ O OUTRO CAMINHO PARA O MESMO SITIO.
        #
        # O set_movement_type nao e o unico a escrever o charset: o
        # refresh_charset (0052) le o `$PokemonGlobal.surfing` directamente e
        # repoe o charset de surf. E ele que corre ao mudar de mapa dentro de
        # agua e depois de qualquer cena — sem este enxerto o boneco voltava ao
        # surf sozinho, um bocado depois de entrar.
        alias_method :anil_montaria_orig_refresh_charset, :refresh_charset

        def refresh_charset
          antes = @character_name
          ret = anil_montaria_orig_refresh_charset
          if (AnilMontaria.montado? rescue false) && !antes.to_s.empty?
            @character_name = antes
          end
          ret
        end
      end
      log("enxerto instalado no set_movement_type e no refresh_charset")
      true
    rescue => e
      log("falha no enxerto da corrida: #{e.class}: #{e.message}")
      false
    end
  end
end

#-------------------------------------------------------------------------------
# O VOO
#-------------------------------------------------------------------------------
# ⚠️ UMA AVE GRANDE NAO BATE ASA O TEMPO TODO.
#
# Ela da dois impulsos, sobe, e depois PLANA a descer devagar ate precisar de
# outro impulso. E a assimetria entre as duas fases que faz aquilo parecer voo:
# o impulso e curto e forte, o planeio e longo e manso. Bater a asa a cadencia
# constante — que e o que sai de graca se deixarmos o padrao da CAMINHADA mandar
# — le-se como um insecto, nao como um Pidgeot.
#
# ⚠️ QUEM MANDA E O `pattern` DO PERSONAGEM, E NAO A COLUNA DO SPRITE.
#
# O cavaleiro esta colado DENTRO da folha da montaria, quadro a quadro. Mexer so
# na coluna do sprite da montaria punha a ave no quadro 0 com o cavaleiro ainda
# desenhado na pose do quadro 2 — desencontrados. Escrevendo no `pattern` do
# personagem, os dois sprites leem o mesmo numero e concordam sozinhos.
#
# ⚠️ A ALTURA VAI NO SPRITE DO CAVALEIRO, E NAO NO DA MONTARIA.
#
# O Sprite_Montaria copia o `@parent.y`. Descer o `y` do cavaleiro leva a
# montaria atras dele de borla, e nao ha duas alturas para manter em sintonia.
#
# O estado e um contador so, e tudo o resto sai dele por conta. Sem fases
# guardadas nao ha nada que possa ficar preso a meio nem que dessincronize entre
# o jogador local e os outros.
#===============================================================================
module AnilVooMontaria
  ACTIVO = true

  # ⚠️ OS TEMPOS SAO EM SEGUNDOS, E NAO EM FRAMES.
  #
  # A primeira versao contava frames a supor 40 por segundo. O motor corre a 60,
  # portanto tudo saiu uma vez e meia mais depressa do que estava escrito: a
  # meia batida ficou em 0,067 s — um borrao — e o "um segundo" de planeio foi
  # 0,67 s. O resultado lia-se como uma asa a bater sem parar, que e o oposto do
  # que se queria.
  #
  # Em segundos isso nao volta a acontecer, e ainda por cima e assim que se
  # pensa nisto: "duas batidas, depois um segundo a descer".
  PADRAO = {
    :bater     => [0, 2],   # os dois quadros que alternam no impulso
    :planar    => 0,        # o quadro da asa aberta, a planar
    :batidas   => 2,        # quantas batidas por ciclo
    :meia_s    => 0.15,     # segundos por meia batida (duas batidas = 0,6 s)
    :subida    => 28,       # px que sobe no impulso (escala com o tamanho)
    :planeio_s => 1.0       # segundos a descer, de asa aberta
  }

  ESPECIES = {
    "PIDGEOT" => {}
  }

  class << self
    def receita_de(especie)
      return nil unless ACTIVO && especie
      c = ESPECIES[especie.to_s.upcase]
      c ? PADRAO.merge(c) : nil
    rescue
      nil
    end

    def voa?(especie)
      !receita_de(especie).nil?
    end

    def fps
      f = (Graphics.frame_rate rescue 60).to_i
      f > 0 ? f : 60
    end

    # [frames de meia batida, frames do impulso, frames do ciclo inteiro]
    def tempos(r)
      f = fps
      meia = (r[:meia_s].to_f * f).round
      meia = 1 if meia < 1
      impulso = r[:batidas].to_i * 2 * meia
      impulso = 1 if impulso < 1
      planeio = (r[:planeio_s].to_f * f).round
      planeio = 1 if planeio < 1
      [meia, impulso, impulso + planeio]
    end

    # Corre uma vez por frame, por personagem montado. Decide o quadro e guarda
    # a altura para quem a for aplicar a seguir.
    def avancar!(personagem, especie)
      return unless personagem
      r = receita_de(especie)
      unless r
        personagem.instance_variable_set(:@anil_voo_alt, 0)
        return
      end

      meia, impulso, ciclo = tempos(r)
      t = (personagem.instance_variable_get(:@anil_voo_t) || -1).to_i + 1
      t = 0 if t >= ciclo || t < 0
      personagem.instance_variable_set(:@anil_voo_t, t)

      # ⚠️ A subida acompanha o tamanho, como o dy e o galope.
      #
      # Doze pixeis num Pidgeot ao natural sao um impulso; no mesmo Pidgeot a
      # dobrar seriam meio impulso. Sem isto, aumentar o sprite achatava o voo.
      k = (AnilMontaria.escala_montaria(especie) rescue 1.0)
      subida = r[:subida].to_f * (k.to_f > 0 ? k.to_f : 1.0)

      if t < impulso
        quadro = r[:bater][(t / meia) % 2].to_i
        alt    = (subida * (t + 1) / impulso).round
      else
        quadro = r[:planar].to_i
        u      = t - impulso
        alt    = (subida * (1.0 - u.to_f / (ciclo - impulso))).round
      end

      personagem.instance_variable_set(:@anil_voo_alt, alt)
      begin
        personagem.pattern = quadro
      rescue
        personagem.instance_variable_set(:@pattern, quadro)
      end
    rescue
      nil
    end

    def altura(personagem)
      return 0 unless personagem
      (personagem.instance_variable_get(:@anil_voo_alt) || 0).to_i
    rescue
      0
    end

    # ⚠️ A ESPECIE VEM DO NOME DO CHARSET, E NAO DA EQUIPA.
    #
    # O follower desenha-se com "Followers/PIDGEOT" (ou "Followers shiny/
    # PIDGEOT_1", com a forma no fim). Ler dali resolve os DOIS casos com uma
    # regra so: o meu follower e o dos outros jogadores — que sao eventos
    # normais, sem ligacao nenhuma a minha equipa, e que de outra maneira
    # ficariam de fora.
    #
    # Exige-se a pasta "Follower" no caminho: sem isso um NPC que por acaso se
    # chamasse PIDGEOT punha-se a voar.
    def especie_do_char(personagem)
      return nil unless personagem
      nome = (personagem.character_name rescue nil).to_s
      return nil if nome.empty?

      # Cache por nome: isto corre a cada frame, para cada sprite no ecra.
      if personagem.instance_variable_get(:@anil_voo_nome) == nome
        return personagem.instance_variable_get(:@anil_voo_esp)
      end

      esp = nil
      if nome =~ /Follower/i
        base = nome.split("/").last.to_s
        base = base.sub(/_\d+\z/, "")        # tira o sufixo da forma
        esp = base.upcase
        esp = nil unless ESPECIES.key?(esp)
      end

      personagem.instance_variable_set(:@anil_voo_nome, nome)
      personagem.instance_variable_set(:@anil_voo_esp, esp)
      esp
    rescue
      nil
    end
  end
end

#-------------------------------------------------------------------------------
# Enxerto no sprite do jogador.
#
# ⚠️ TEM DE SER NO apply_post_plugin_patches. TERCEIRA VEZ QUE ISTO MORDE.
#
# O `[v21.1 Hotfixes] Misc bug fixes.rb` REDEFINE `Sprite_Character#refresh_graphic`
# de raiz — linha 861, sem alias — e os plugins carregam depois de todos os
# scripts. Remendar no arranque era escrever para o lixo: a versao do plugin
# substituia a nossa antes de o jogo comecar, e ficava tudo com ar de correcto.
#
# O mesmo plugin ja tinha comido o `pbStorePokemon` (MOD 155) e, antes disso, o
# gancho do anuncio de shiny (MOD 134). Regra: tudo o que este plugin toca vai
# no apply_post_plugin_patches, com reinstalacao idempotente.
#
# ⚠️ O `initialize` NAO se toca.
#
# Ha varios plugins a encadea-lo (Marin's Footprints, Advanced Items). O sprite
# da montaria nasce a pedido dentro do update, que e mais barato do que entrar
# nessa fila e nao arrisca partir nenhum deles.
#-------------------------------------------------------------------------------
module AnilMontaria
  class << self
    def instalar_patches!
      return false unless defined?(Sprite_Character)
      return false if Sprite_Character.method_defined?(:anil_montaria_orig_refresh_graphic)

      Sprite_Character.class_eval do
        alias_method :anil_montaria_orig_refresh_graphic, :refresh_graphic
        alias_method :anil_montaria_orig_update, :update
        alias_method :anil_montaria_orig_dispose, :dispose

        # Trocar o @charbitmap CHEGA: o motor calcula sx/sy a partir de
        # @cw/@ch e do padrao/direccao, portanto basta dar-lhe outro charset
        # com a mesma grelha 4x4. Nao ha uma unica coordenada a mexer aqui.
        # ⚠️ ISTO CORRE A CADA FRAME. TEM DE SAIR BARATO.
        #
        # O update do motor (0067) chama o refresh_graphic sempre, sem condicao
        # — o original e que se defende sozinho com uma guarda logo a entrada.
        # O meu nao tinha nenhuma: chamava o charset_do_cavaleiro em todos os
        # frames, e so a chave da cache dele ja percorria a equipa duas vezes.
        #
        # A guarda compara tres coisas que nao alocam (especie, nome da skin,
        # selo de estado) e ainda confirma que o bitmap instalado e o NOSSO. Se
        # outro plugin trocar o @charbitmap por baixo, o equal? da falso e
        # reconstroi-se — que e o unico caso em que ha mesmo trabalho a fazer.
        def refresh_graphic
          ret = anil_montaria_orig_refresh_graphic
          return ret unless @character
          esp = (AnilMontaria.montaria_de(@character) rescue nil)
          unless esp
            @anil_mont_esp = nil
            @anil_mont_bmp = nil
            return ret
          end
          nome = (@character.character_name rescue nil)
          est  = (AnilMontaria.marca_de_estado(@character) rescue nil)
          if @anil_mont_esp == esp && @anil_mont_nome == nome && @anil_mont_est == est &&
             @charbitmap && !(@charbitmap.disposed? rescue true) &&
             @charbitmap.equal?(@anil_mont_bmp)
            return ret
          end
          # ⚠️ QUEM FUROU A GUARDA? SEM ISTO SO SE SABE QUE FUROU.
          #
          # O log mostrou o charset a ser refeito uma vez por segundo, a 45 ms.
          # Saber QUAL das quatro condicoes falhou e a diferenca entre corrigir
          # e adivinhar — sao causas completamente diferentes.
          if defined?(AnilDiagFPS) && AnilDiagFPS::ACTIVO
            motivo = if @anil_mont_esp != esp    then "especie:#{@anil_mont_esp.inspect}->#{esp.inspect}"
                     elsif @anil_mont_nome != nome then "skin:#{@anil_mont_nome.inspect}->#{nome.inspect}"
                     elsif @anil_mont_est != est   then "selo:#{@anil_mont_est.inspect}->#{est.inspect}"
                     elsif @charbitmap.nil?        then "charbitmap=nil"
                     elsif (@charbitmap.disposed? rescue true) then "charbitmap libertado"
                     else "charbitmap trocado por outrem"
                     end
            AnilDiagFPS.motivo(motivo) rescue nil
          end
          partilhado = (AnilMontaria.charset_do_cavaleiro(@character) rescue nil)
          return ret unless partilhado && !partilhado.disposed?

          # ⚠️ NUNCA ENTREGAR AO MOTOR O BITMAP DA CACHE. ELE LIBERTA-O.
          #
          # Esta era a causa do travao no mato, e nao se via de outra maneira:
          # o refresh_graphic do motor (0067, linha 121) faz `@charbitmap&.dispose`
          # antes de reconstruir, e a guarda dele inclui o `bush_depth`. Ou seja,
          # cada vez que se entra ou sai de um tufo de erva ele LIBERTA o bitmap
          # que la estiver — e o que la estava era o meu, o da cache partilhada.
          #
          # Na volta seguinte a cache tinha um bitmap morto, e o charset do
          # cavaleiro era recomposto do zero: 16 celulas com mascara e contorno,
          # 45 ms medidos. No mato isso acontecia a cada passo.
          #
          # Entao o que se entrega e uma COPIA, que o motor pode libertar a
          # vontade. Copiar a folha e um blt nativo; recompo-la sao 16.
          copia = Bitmap.new(partilhado.width, partilhado.height)
          copia.blt(0, 0, partilhado, Rect.new(0, 0, partilhado.width, partilhado.height))

          # a copia anterior, se ainda for nossa e ainda estiver viva, morre aqui
          # — senao ficava uma folha orfa por cada reconstrucao
          antiga = @anil_mont_bmp
          antiga.dispose if antiga && !(antiga.disposed? rescue true) && !antiga.equal?(copia)

          @anil_mont_esp  = esp
          @anil_mont_nome = nome
          @anil_mont_est  = est
          @anil_mont_bmp  = copia
          novo = copia
          if @charbitmap != novo
            @charbitmap = novo
            @charbitmapAnimated = false
            @cw = novo.width / 4
            @ch = novo.height / 4
            # ⚠️ O ox TEM de acompanhar o @cw.
            #
            # O refresh_graphic do plugin faz `self.ox = @cw / 2` com o @cw do
            # charset ORIGINAL, e nos trocamos o charset a seguir. Com montarias
            # de 64 nao se notava — a celula fica com 64, tal como a skin. Com as
            # de 128 (LUGIA, RAYQUAZA, ARCEUS) a celula passa a 128 e o ox ficava
            # em 32: o cavaleiro aparecia 32 px ao lado da montaria.
            #
            # O oy nao precisa: o update reescreve-o a cada frame.
            self.ox = @cw / 2
          end
          ret
        rescue
          ret
        end

        def update
          # ⚠️ A ESPECIE LE-SE ANTES, PORQUE O VOO ESCREVE NO `pattern`.
          #
          # O update do motor le o pattern para escolher a coluna. Decidir o
          # quadro DEPOIS dele deixava o voo um frame atrasado, e nas viragens
          # isso via-se. O `montaria_de` continua a ser chamado uma vez so.
          esp = (AnilMontaria.montaria_de(@character) rescue nil)
          AnilVooMontaria.avancar!(@character,
                                   esp || AnilVooMontaria.especie_do_char(@character)) rescue nil

          anil_montaria_orig_update

          # ⚠️ Sobe o CAVALEIRO; a montaria vem atras.
          #
          # O Sprite_Montaria copia o `@parent.y` logo a seguir, portanto uma
          # subtraccao aqui levanta os dois em conjunto. Duas alturas separadas
          # seriam duas coisas para manter em sintonia.
          begin
            alt = AnilVooMontaria.altura(@character)
            self.y -= alt if alt != 0
          rescue
            nil
          end

          # ⚠️ MONTAR NAO MUDA O NOME DA SKIN.
          #
          # O refresh_graphic sai logo se `@character_name == character_name`,
          # portanto montar (ou desmontar) nao o acorda sozinho. Para o jogador
          # local ha o recarregar_sprite!, mas os sprites dos OUTROS jogadores
          # nem sequer estao no @character_sprites do spriteset — vivem numa
          # lista a parte do multiplayer. Entao a mudanca deteta-se aqui, e
          # poe-se o nome a nil para obrigar a reavaliar.
          if esp != @anil_montaria_esp
            @anil_montaria_esp = esp
            @character_name = nil
            refresh_graphic rescue nil
          end

          # O follower nao se esconde aqui: ele nem sequer existe enquanto se
          # esta montado. Ver o guardar_follower! / repor_follower!.

          if esp
            @anil_montaria_sprite ||= Sprite_Montaria.new(self, (self.viewport rescue nil))
            @anil_montaria_sprite.update
          elsif @anil_montaria_sprite
            @anil_montaria_sprite.dispose
            @anil_montaria_sprite = nil
          end
        rescue
          nil
        end

        def dispose
          begin
            @anil_montaria_sprite&.dispose
            @anil_montaria_sprite = nil
          rescue
          end
          anil_montaria_orig_dispose
        end
      end

      log("enxerto instalado no Sprite_Character")
      true
    rescue => e
      log("falha ao instalar o enxerto: #{e.class}: #{e.message}")
      false
    end
  end
end

module AnilLanRework
  class << self
    unless method_defined?(:anil_montaria_orig_apply_post_plugin_patches)
      alias_method :anil_montaria_orig_apply_post_plugin_patches, :apply_post_plugin_patches rescue nil
    end

    def apply_post_plugin_patches
      anil_montaria_orig_apply_post_plugin_patches rescue nil
      AnilMontaria.instalar_patch_corrida! rescue nil
      AnilMontaria.instalar_patches! rescue nil
      AnilMontaria.instalar_patch_follower! rescue nil
      AnilMontaria.reparar_follower_no_arranque! rescue nil
    end
  end
end

class PokemonGlobalMetadata
  attr_accessor :anil_montaria
  # ⚠️ O BRILHO VIAJA COM A MONTARIA, NAO SE DEDUZ DA ESPECIE.
  #
  # Dois Arcanine da mesma equipa podem ter cores diferentes: um normal, outro
  # super shiny com o seu proprio matiz. Guardar so a especie fazia a montaria
  # sair sempre com a cor de fabrica.
  attr_accessor :anil_montaria_shiny
  attr_accessor :anil_montaria_hue
  # Qual dos bichos da equipa, quando ha mais do que um da mesma especie.
  attr_accessor :anil_montaria_pid
  # [estava_ligado, estava_trancado] do follower antes de montar. nil = nao
  # fomos nos que o desligamos, e portanto nao ha nada a repor.
  attr_accessor :anil_montaria_follower_antes
end

#-------------------------------------------------------------------------------
# Comando de teste: /montaria [ESPECIE|off]
#-------------------------------------------------------------------------------
module AnilMontariaComando
  PADRAO = "DONPHAN"

  module_function

  def admin?
    return AnilEventoShinyComando.admin? if defined?(AnilEventoShinyComando)
    true
  rescue
    true
  end

  def avisar(txt)
    if AnilLanRework.respond_to?(:add_popup)
      AnilLanRework.add_popup(txt, 6.0) rescue nil
    else
      pbMessage(txt) rescue nil
    end
  end

  # ⚠️ O refresh_graphic sai logo se nada mudou (`@character_name ==
  # @character.character_name`). Montar nao muda o nome da skin, portanto sem
  # este empurrao o sprite so mudava por acaso, quando o jogador trocasse de
  # roupa. Poe-se o nome a nil para o obrigar a reavaliar.
  def recarregar_sprite!
    conjuntos = []
    if $scene.is_a?(Scene_Map)
      if $scene.respond_to?(:spritesets) && $scene.spritesets
        conjuntos = $scene.spritesets.values
      elsif $scene.respond_to?(:spriteset) && $scene.spriteset
        conjuntos = [$scene.spriteset]
      end
    end
    n = 0
    conjuntos.each do |c|
      lista = (c.instance_variable_get(:@character_sprites) rescue nil)
      next unless lista
      lista.each do |s|
        next unless (s.respond_to?(:character) && s.character == $game_player rescue false)
        s.instance_variable_set(:@character_name, nil)
        s.refresh_graphic rescue nil
        n += 1
      end
    end
    AnilMontaria.log("sprite do jogador recarregado (#{n})")
    n
  rescue => e
    AnilMontaria.log("falha ao recarregar o sprite: #{e.class}: #{e.message}")
    0
  end

  def tratar(texto)
    t = texto.to_s.strip
    return false unless t =~ %r{\A/montaria(?:\s+(.*))?\z}i
    arg = $1.to_s.strip

    unless admin?
      avisar(_INTL("[Montaria] Apenas administradores."))
      return true
    end

    if arg.downcase == "off" || (arg.empty? && AnilMontaria.montado?)
      AnilMontaria.desmontar!
      recarregar_sprite!
      avisar(_INTL("[Montaria] Desmontado."))
      return true
    end

    if arg.downcase == "recarregar" || arg.downcase == "reload"
      n = AnilMontaria.recarregar!
      AnilMontariaComando.recarregar_sprite!
      avisar(_INTL("[Montaria] {1} receita(s) relidas do ficheiro.", n))
      return true
    end

    if arg.downcase == "lista"
      avisar(_INTL("[Montaria] Receitas: {1}", AnilMontaria.receitas.keys.join(", ")))
      return true
    end

    # ⚠️ QUEM DECIDE A FORMA E O POKEMON, NAO O FICHEIRO.
    #
    # O `montarias.json` e so o armario das receitas: guarda `NECROZMA_1` porque
    # foi esse o sprite que se editou. Quem diz qual delas se aplica e o
    # `pkmn.form` do bicho que esta na equipa. Havendo tres Necrozma no jogo
    # (0 normal, 1 Melena Crepuscular, 2 Alas del Alba), so o que tiver a forma
    # certa encontra a receita.
    #
    # Isto imprime, para a equipa toda, o que o jogo VE — especie, forma e a
    # chave que sai — para nao haver que adivinhar qual dos tres se apanhou.
    if arg.downcase == "equipa" || arg.downcase == "formas"
      linhas = []
      ($player.party rescue []).each_with_index do |pk, i|
        next unless pk
        esp = (pk.species.to_s rescue "?")
        f = (pk.form.to_i rescue 0)
        chave = (AnilMontaria.chave_de(esp, f) rescue nil)
        linhas << "#{i + 1}. #{esp} forma #{f} -> #{chave ? chave : "SEM RECEITA"}"
      end
      avisar("[Montaria] o que o jogo ve:
" + (linhas.empty? ? "equipa vazia" : linhas.join("
")))
      return true
    end

    if arg.downcase == "arco"
      $anil_diag_salto = !$anil_diag_salto
      avisar(_INTL("[Montaria] diagnostico do arco: {1}", $anil_diag_salto ? "LIGADO" : "desligado"))
      return true
    end

    if arg.downcase == "onde" || arg.downcase == "diag"
      avisar("[Montaria]\n" + AnilMontaria.diagnostico)
      return true
    end

    if arg.downcase == "estado"
      avisar(_INTL("[Montaria] enxerto={1} receitas={2} montado={3}",
                   (Sprite_Character.method_defined?(:anil_montaria_orig_refresh_graphic) ? "sim" : "NAO"),
                   AnilMontaria.receitas.length,
                   AnilMontaria.montado.inspect))
      return true
    end

    esp = arg.empty? ? PADRAO : arg.upcase
    ok, msg = AnilMontaria.montar!(esp)
    recarregar_sprite!
    avisar(ok ? _INTL("[Montaria] Montado em {1}.", msg)
              : _INTL("[Montaria] {1}", msg))
    true
  rescue => e
    AnilMontaria.log("falha no comando: #{e.class}: #{e.message}")
    false
  end
end

module AnilLanRework
  module Chat
    class << self
      unless method_defined?(:anil_montaria_orig_send_message)
        alias_method :anil_montaria_orig_send_message, :send_message rescue nil
      end

      def send_message(text)
        return if AnilMontariaComando.tratar(text)
        anil_montaria_orig_send_message(text)
      end
    end
  end
end

#-------------------------------------------------------------------------------
# ⚠️ MONTADO, O JOGADOR NAO DECLARA FOLLOWER NENHUM.
#
# Esconder o sprite do follower resolvia so para quem esta a jogar. Os OUTROS
# jogadores recebem o nome do follower no pacote de estado (`"follower"`), e
# desenhavam-no ao lado da montaria — dois bichos ao mesmo tempo.
#
# O ponto certo e a origem: o resolve_follower_char devolve vazio enquanto se
# esta montado, e o lado remoto ja sabe o que fazer com isso, sem alteracao
# nenhuma la (`if follower_name.empty? ... dispose ... next`).
#
# Assim ha UMA regra, e vale para toda a gente.
#-------------------------------------------------------------------------------
if defined?(AnilLanRework) && defined?(AnilLanRework::WorldSync)
  module AnilLanRework
    module WorldSync
      class << self
        unless method_defined?(:anil_montaria_orig_resolve_follower_char)
          alias_method :anil_montaria_orig_resolve_follower_char, :resolve_follower_char

          # ⚠️ JA NAO SE APAGA O FOLLOWER PARA OS OUTROS.
          #
          # Isto devolvia vazio enquanto montado, porque na altura o follower
          # era o MESMO Pokemon da montaria e os outros viam-no duas vezes.
          # Agora o visible_follower_pokemon ja salta o montado, portanto o que
          # viaja e o segundo da equipa — e esse deve mesmo aparecer.
          def resolve_follower_char
            anil_montaria_orig_resolve_follower_char
          end
        end
      end
    end
  end
end

#-------------------------------------------------------------------------------
# O arco do salto, do lado de quem esta a ver.
#
# ⚠️ A MESMA FORMULA DO MOTOR, PARA OS DOIS LADOS BATEREM CERTO.
#
# O Game_Character#screen_y faz:
#
#     jump_progress = (@jump_fraction - 0.5).abs
#     ret += @jump_peak * ((4 * (jump_progress**2)) - 1)
#
# Aqui e igual, com o tempo a vir de um relogio local em vez do @jump_timer:
# o aviso diz QUANDO, e o resto calcula-se. Assim o salto tem a mesma duracao e
# a mesma altura em todos os ecras, sem depender de a rede entregar amostras a
# tempo — e ela nao entregava, sao 0,125 s contra pacotes de 100 ms.
#-------------------------------------------------------------------------------
if defined?(AnilLanRework) && defined?(AnilLanRework::RemotePeer)
  class AnilLanRework::RemotePeer
    unless method_defined?(:anil_montaria_orig_screen_y)
      alias_method :anil_montaria_orig_screen_y, :screen_y

      def screen_y
        base = anil_montaria_orig_screen_y
        ini = @anil_jump_ini
        return base unless ini
        t = Time.now.to_f - ini
        # ainda nao chegou a vez deste salto: o movimento vem 150 ms atrasado
        return base if t < 0
        if t > SALTO_DURACAO
          if $anil_diag_salto
            AnilLanRework.log("[MONTARIA/ARCO] #{@name} arco terminado, " \
                              "#{@anil_jump_frames.to_i} frame(s) desenhados") rescue nil
          end
          @anil_jump_ini = nil
          @anil_jump_frames = 0
          return base
        end
        @anil_jump_frames = @anil_jump_frames.to_i + 1
        # o som toca quando o salto COMECA a ver-se, nao quando o pacote chegou
        unless @anil_jump_som
          @anil_jump_som = true
          pbSEPlay("Player jump") rescue nil
          # ⚠️ Diagnostico: sem isto nao ha como saber se o arco chegou a correr.
          #
          # O som ja tocava e o pulo nao aparecia, o que deixa duas hipoteses
          # muito diferentes — o arco correr e nao se ver, ou nem sequer correr.
          # Estas linhas separam-nas. Ligar com $anil_diag_salto = true.
          if $anil_diag_salto
            AnilLanRework.log("[MONTARIA/ARCO] #{@name} arco a comecar " \
                              "(dur=#{SALTO_DURACAO}s pico=#{SALTO_PICO}px)") rescue nil
          end
        end
        fraccao = t / SALTO_DURACAO
        progresso = (fraccao - 0.5).abs
        base + (SALTO_PICO * ((4 * (progresso**2)) - 1)).round
      rescue
        base
      end
    end
  end
end

#-------------------------------------------------------------------------------
# O follower do plugin passa a saltar o Pokemon montado.
#
# ⚠️ E AQUI QUE SE DECIDE, E NAO NO SPRITE.
#
# O FollowingPkmn.get_pokemon devolve `$player.first_able_pokemon`, e e dele que
# saem tanto a identidade como o grafico do follower. Trocar isto num sitio so
# chega para o mapa inteiro — sprite, sombra e refresh vem todos atras.
#-------------------------------------------------------------------------------
# ⚠️ TEM DE ENTRAR NO apply_post_plugin_patches, E NAO AQUI DIRECTAMENTE.
#
# O FollowingPkmn e um PLUGIN: so existe depois de o Main correr. Um
# `if defined?(FollowingPkmn)` avaliado no carregamento deste ficheiro da
# sempre false, e o enxerto nunca chegaria a ser instalado — sem erro nenhum,
# so nao funcionava. E a mesma armadilha do enxerto do Sprite_Character.
module AnilMontaria
  class << self
    def instalar_patch_follower!
      return false unless defined?(FollowingPkmn)
      return false if FollowingPkmn.singleton_class.method_defined?(:anil_montaria_orig_get_pokemon)
      FollowingPkmn.singleton_class.class_eval do
        alias_method :anil_montaria_orig_get_pokemon, :get_pokemon

        def get_pokemon
          return anil_montaria_orig_get_pokemon unless (AnilMontaria.montado? rescue false)
          return nil unless FollowingPkmn.can_check?
          (AnilMontaria.pokemon_do_follower rescue nil)
        end
      end
      log("enxerto instalado no FollowingPkmn.get_pokemon")
      true
    rescue => e
      log("falha no enxerto do follower: #{e.class}: #{e.message}")
      false
    end
  end
end

AnilLanRework.log("156_Montaria carregado") rescue nil
