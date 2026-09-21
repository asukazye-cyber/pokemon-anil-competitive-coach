#===============================================================================
# MOD: 126_Coop_Espectador_Gravador.rb   —   PASSOS E0 e E1 de PLANO_COOP_ESPECTADOR.md
#-------------------------------------------------------------------------------
# Grava TUDO o que passa pela Battle::Scene durante uma batalha, para um ficheiro.
# O passo E2 le esse ficheiro e reproduz a batalha sem simular nada.
#
# ESTADO: INERTE por omissao ($anil_coop_gravar = false). Nao mexe em coop, nao
# usa rede, nao altera comportamento nenhum. So grava quando ligado.
#
#-------------------------------------------------------------------------------
# POR QUE UM PROXY DINAMICO E NAO UMA LISTA DE METODOS
#
# O levantamento do E0 contou os metodos de cena chamados pela batalha:
#   17 existem na Battle::Scene do engine
#   31 sao chamados mas NAO existem la — vem de plugins (DBK, Enhanced Battle UI,
#      Animated Pokemon System...): pbDamageAnimation, pbUpdateHazardSprites,
#      pbHPChanged, pbShowOpponent, pbDeleteTrickRoomBackground, ...
#
# Ou seja, a superficie visivel depende dos plugins instalados e MUDA quando se
# instala outro. Uma lista fixa estaria desatualizada no dia seguinte, e o risco
# n1 do plano e exatamente esse: metodo esquecido => ecra errado no espectador.
#
# Este proxy intercepta QUALQUER chamada por method_missing. Nada e esquecido
# por construcao; o que houver a decidir e o que se GRAVA, nao o que se apanha.
#-------------------------------------------------------------------------------
# COMO SE USA (E1, sem rede e sem parceiro)
#
#   $anil_coop_gravar = true      # no Debug, ou editando a linha abaixo
#   ... jogar uma batalha normal ...
#   -> gera coop_replay_<hora>.jsonl na raiz do jogo
#
# Depois o E2 le esse ficheiro e reproduz. Se o replay desenhar a batalha certa
# sozinho, o mecanismo esta provado ANTES de existir qualquer rede — que e a
# diferenca em relacao a tudo o que se tentou antes, so verificavel com 2 clientes.
#===============================================================================

$anil_coop_gravar = false unless defined?($anil_coop_gravar)

module CoopSpec
  ARQUIVO_PREFIXO = "coop_replay_" unless const_defined?(:ARQUIVO_PREFIXO)

  # Metodos que NAO valem a pena gravar: sao consultas sem efeito visivel, ou
  # sao chamados dezenas de vezes por frame e so inchariam o log.
  #   - update/graphics: o reprodutor corre o seu proprio laco de frames
  #   - acessores (sprites, viewport, battle...): o reprodutor tem os seus
  IGNORAR = %w[
    update pbUpdate pbGraphicsUpdate pbInputUpdate pbFrameUpdate
    sprites viewport battle battler_sprite abortable inPartyAnimation?
    respond_to? respond_to_missing? is_a? kind_of? class inspect to_s nil?
    instance_variable_get instance_variable_set
  ].freeze

  class << self
    attr_accessor :eventos
    attr_accessor :arquivo

    def gravando?
      $anil_coop_gravar == true && !@arquivo.nil?
    end

    def iniciar!(rotulo = nil)
      @eventos = 0
      @arquivo = "#{ARQUIVO_PREFIXO}#{Time.now.strftime('%H%M%S')}.jsonl"
      escrever({ "t" => "inicio", "rotulo" => rotulo.to_s, "quando" => Time.now.to_i })
      @arquivo
    rescue => e
      @arquivo = nil
      registrar_erro("iniciar! #{e.class}: #{e.message}")
      nil
    end

    def terminar!
      return unless @arquivo
      escrever({ "t" => "fim", "eventos" => @eventos.to_i })
      caminho = @arquivo
      @arquivo = nil
      caminho
    rescue
      @arquivo = nil
    end

    def registrar(metodo, args)
      return unless gravando?
      @eventos = @eventos.to_i + 1
      escrever({ "t" => "cena", "m" => metodo.to_s, "a" => args.map { |x| valor(x) } })
    rescue => e
      registrar_erro("registrar #{metodo}: #{e.class}: #{e.message}")
    end

    # ---------------------------------------------------------------------
    # Serializacao dos argumentos.
    #
    # Battler e Pokemon NAO podem ir inteiros: sao objetos enormes e, pior, o
    # espectador tem os SEUS objetos. O que interessa e a REFERENCIA (que slot,
    # que posicao na party) — o reprodutor resolve para os objetos dele.
    # ---------------------------------------------------------------------
    def valor(x)
      case x
      when nil, true, false, Integer, Float, String then x
      when Symbol then { "_" => "sym", "v" => x.to_s }
      when Array  then { "_" => "arr", "v" => x.map { |y| valor(y) } }
      when Hash   then { "_" => "hash", "v" => x.map { |k, v| [valor(k), valor(v)] } }
      else
        nome = x.class.name.to_s
        if nome.include?("Battler")
          { "_" => "battler", "i" => (x.index.to_i rescue -1) }
        elsif nome.include?("Pokemon")
          { "_" => "pkmn", "id" => (x.personalID.to_i rescue 0),
            "sp" => (x.species.to_s rescue ""), "nv" => (x.level.to_i rescue 0) }
        elsif nome.include?("Move")
          { "_" => "move", "id" => (x.id.to_s rescue "") }
        else
          # Marcador explicito: se aparecer no log, e sinal de que este tipo
          # precisa de tratamento proprio antes do E2 funcionar com ele.
          { "_" => "obj", "c" => nome }
        end
      end
    rescue
      { "_" => "obj", "c" => "?" }
    end

    def escrever(h)
      File.open(@arquivo, "a") { |f| f.puts(json(h)) } if @arquivo
    rescue
    end

    # JSON minimo proprio: nao dependemos de nenhuma lib do jogo.
    def json(v)
      case v
      when nil then "null"
      when true, false, Integer then v.to_s
      when Float then (v.finite? ? v : 0).to_s
      when String then "\"#{v.gsub('\\', '\\\\\\\\').gsub('"', '\\"').gsub("\n", '\\n').gsub("\r", "")}\""
      when Symbol then json(v.to_s)
      when Array then "[" + v.map { |x| json(x) }.join(",") + "]"
      when Hash then "{" + v.map { |k, x| "#{json(k.to_s)}:#{json(x)}" }.join(",") + "}"
      else json(v.to_s)
      end
    end

    def registrar_erro(msg)
      File.open("coop_replay_erros.txt", "a") { |f| f.puts("[#{Time.now.strftime('%H:%M:%S')}] #{msg}") }
    rescue
    end
  end

  # ===========================================================================
  # O PROXY
  #
  # Envolve a Scene real. method_missing apanha tudo, grava e reencaminha.
  # Nao herda de BasicObject de proposito: o engine faz `scene.is_a?(...)`,
  # `scene.sprites[...]` e passa a cena a plugins — precisa de se comportar como
  # um objeto normal. O que interessa e interceptar, nao esconder.
  # ===========================================================================
  class SceneGravador
    def initialize(real)
      @real = real
    end

    attr_reader :real

    def method_missing(nome, *args, &bloco)
      unless CoopSpec::IGNORAR.include?(nome.to_s)
        CoopSpec.registrar(nome, args)
      end
      @real.send(nome, *args, &bloco)
    end

    def respond_to_missing?(nome, priv = false)
      @real.respond_to?(nome, priv)
    end

    # A cena e comparada por identidade nalguns sitios; delegamos para nao
    # partir essas verificacoes.
    def is_a?(k)   ; @real.is_a?(k)   ; end
    def kind_of?(k); @real.kind_of?(k); end
    def class      ; @real.class      ; end
  end
end

#-------------------------------------------------------------------------------
# Instalacao: envolve a cena no arranque da batalha e desliga no fim.
# Nao usa alias em Battle::Scene — so troca o objeto que a Battle segura.
#-------------------------------------------------------------------------------
if defined?(Battle)
  class Battle
    unless method_defined?(:coopspec_original_pbStartBattle)
      alias coopspec_original_pbStartBattle pbStartBattle
    end

    def pbStartBattle(*args)
      if $anil_coop_gravar == true
        begin
          rotulo = (trainerBattle? ? "treinador" : "selvagem") rescue "?"
          arq = CoopSpec.iniciar!(rotulo)
          if arq && @scene && !@scene.is_a?(CoopSpec::SceneGravador)
            @scene = CoopSpec::SceneGravador.new(@scene)
          end
        rescue => e
          CoopSpec.registrar_erro("instalar gravador: #{e.class}: #{e.message}")
        end
      end
      resultado = coopspec_original_pbStartBattle(*args)
      begin
        if @scene.is_a?(CoopSpec::SceneGravador)
          @scene = @scene.real
          caminho = CoopSpec.terminar!
          puts "[CoopSpec] replay gravado: #{caminho} (#{CoopSpec.eventos} eventos)" if caminho
        end
      rescue => e
        CoopSpec.registrar_erro("desinstalar gravador: #{e.class}: #{e.message}")
      end
      resultado
    end
  end
end
