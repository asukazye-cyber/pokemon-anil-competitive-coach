# encoding: utf-8
#===============================================================================
# MOD: 195_Arena_Log_Intrusos — o que o jogo normal tenta meter na arena
#===============================================================================
#
# ⚠️ A SUSPEITA E DO UTILIZADOR E VALE A PENA MEDI-LA EM VEZ DE A DISCUTIR.
#
# "O jogo local fica tentando injetar várias coisas e dependências do outro modo
# de jogo." Ja apanhamos tres casos disto, e cada um deles custou uma sessao:
#
#   · o spawner do overworld a plantar encontros no mapa 303, porque desde que
#     a caverna passou a ser um mapa a serio ele passou a ve-la como tal;
#   · o proprio jogador na lista de peers, desenhado por cima de si mesmo;
#   · o seguidor e o boneco do treinador a serem repostos por outros sistemas.
#
# Os tres foram encontrados por acaso. Este log e para deixarem de ser acaso: em
# vez de esperar que alguem repare num sprite a piscar, conta-se quantas vezes
# por segundo alguem de fora mexe no que e nosso, e diz-se quem foi.
#
# ⚠️ E A PECA CENTRAL E O CENSO DOS EVENTOS.
#
# Tudo o que aparece no mapa e um evento. Os nossos sao contados e conhecidos
# (o marcador, o ajudante, os trinta habitantes, os itens no chao, as escadas).
# Qualquer outro e um intruso — e nao e preciso saber de antemao o que ele e
# para o apanhar: basta perguntar, uma vez por segundo, "o que esta aqui que eu
# nao pus?".
#
# Ficheiro: arena_intrusos.log      Comando: /intrusolog [off|ja]
#===============================================================================

module AnilArenaIntrusos
  FICHEIRO   = "arena_intrusos.log"
  RESUMO_SEG = 5.0
  CENSO_SEG  = 1.0      # de quanto em quanto tempo se conta o que esta no mapa
  DESPEJO    = 1.0
  TECTO_MB   = 4

  class << self
    attr_accessor :activo

    def ligado?; @activo == true; end

    def ligar!
      @activo     = true
      @inicio     = Time.now.to_f
      @linhas     = []
      @contas     = Hash.new(0)
      @vistos     = {}       # id de evento -> nome, para so contar os novos
      @resumo_em  = @inicio + RESUMO_SEG
      @censo_em   = @inicio + CENSO_SEG
      @despejo_em = @inicio + DESPEJO
      @resumo_desde = @inicio
      apagar!
      cabecalho!
      true
    rescue
      false
    end

    def desligar!
      return false unless ligado?
      resumo!("fim da sessão")
      despejar!
      @activo = false
      true
    rescue
      @activo = false
      false
    end

    def caminho; FICHEIRO; end

    def apagar!
      File.delete(FICHEIRO) if File.exist?(FICHEIRO)
    rescue
      nil
    end

    def ms
      ((Time.now.to_f - @inicio.to_f) * 1000.0).round
    rescue
      0
    end

    #---------------------------------------------------------------------------
    # ⚠️ UMA INTERVENCAO E UMA VEZ EM QUE ALGUEM DE FORA MEXEU NO NOSSO.
    #
    # Nao e um erro — muitas delas sao correccoes nossas a funcionar. O que
    # interessa e a FREQUENCIA: uma reposicao do seguidor por sessao e um
    # sistema a acordar; trinta por segundo e uma guerra.
    #---------------------------------------------------------------------------
    def anotar(categoria, detalhe = nil)
      return unless ligado?
      @contas[categoria] += 1
      # O fluxo cru so leva as primeiras de cada tipo: a partir daí o numero no
      # resumo diz mais do que mil linhas iguais.
      return if @contas[categoria] > 5
      @linhas << ("%7d  %-26s %s" % [ms, categoria.to_s, detalhe.to_s])
    rescue
      nil
    end

    #---------------------------------------------------------------------------
    # O CENSO
    #---------------------------------------------------------------------------
    # Os eventos que sao NOSSOS, por id ou por nome. Tudo o resto e para contar.
    def nosso?(id, nome)
      return true if defined?(AnilArena) && (
        id == AnilArena::ID_MARCADOR  || id == AnilArena::ID_MARCADOR2 ||
        id == AnilArena::ID_CORPO     || id == AnilArena::ID_ALIADO ||
        id == AnilArena::ID_PARCEIRO  ||
        (id >= AnilArena::ID_INIMIGO && id < AnilArena::ID_INIMIGO + AnilArena::MAX_BICHOS) ||
        (id >= AnilArena::ID_CAVERNA && id < AnilArena::ID_CAVERNA + AnilArena::MAX_CAVERNA)
      )
      n = nome.to_s
      return true if n.start_with?("DroppedItem")
      return true if n.start_with?("Arena")
      return true if n.start_with?("FlechaSalida")   # as escadas, que sao do mapa
      false
    rescue
      true
    end

    def censo!
      return unless ligado?
      return unless $game_map
      agora = Time.now.to_f
      return if agora < @censo_em.to_f
      @censo_em = agora + CENSO_SEG

      presentes = {}
      $game_map.events.each_pair do |id, ev|
        next unless ev
        nome = (ev.event.name.to_s rescue "")
        presentes[id] = nome
        next if @vistos.key?(id)
        @vistos[id] = nome
        next if nosso?(id, nome)
        # ⚠️ Um evento novo que nao e nosso: e isto que se anda a procurar.
        classe = (ev.class.name rescue "?")
        anotar(:evento_estranho, "id=#{id} nome=#{nome.inspect} classe=#{classe} em (#{ev.x},#{ev.y})")
      end
      # Os que desapareceram deixam de ser conhecidos, para voltarem a contar se
      # renascerem — um evento que nasce e morre em ciclo e o padrao que mais
      # interessa apanhar.
      (@vistos.keys - presentes.keys).each { |id| @vistos.delete(id) }

      @contas[:eventos_no_mapa] = presentes.length
      resumo! if agora >= @resumo_em.to_f
      despejar! if agora >= @despejo_em.to_f
    rescue
      nil
    end

    #---------------------------------------------------------------------------
    def resumo!(motivo = nil)
      return unless ligado?
      agora = Time.now.to_f
      janela = agora - @resumo_desde.to_f
      janela = 0.001 if janela <= 0
      @resumo_desde = agora
      @resumo_em = agora + RESUMO_SEG

      @linhas << ""
      @linhas << ("=" * 74)
      @linhas << ("INTRUSOS aos %d ms  (janela de %.1f s)%s" %
                  [ms, janela, motivo ? "  — #{motivo}" : ""])
      @linhas << ("=" * 74)
      if @contas.empty?
        @linhas << "  nada. ninguém de fora mexeu em nada nesta janela."
      else
        @linhas << ("%-30s %8s %10s" % ["o que aconteceu", "vezes", "por seg"])
        @contas.keys.sort_by { |k| -@contas[k] }.each do |k|
          n = @contas[k]
          next if n.zero?
          if k == :eventos_no_mapa
            @linhas << ("%-30s %8d %10s" % ["eventos no mapa (agora)", n, "—"])
          else
            @linhas << ("%-30s %8d %10.1f" % [k.to_s, n, n / janela])
          end
        end
      end
      @linhas << ("=" * 74)
      @linhas << ""
      guardado = @contas[:eventos_no_mapa]
      @contas = Hash.new(0)
      @contas[:eventos_no_mapa] = guardado
    rescue => e
      @linhas << "falha no resumo: #{e.class}: #{e.message}"
    end

    def despejar!
      @despejo_em = Time.now.to_f + DESPEJO
      return if @linhas.nil? || @linhas.empty?
      lote = @linhas
      @linhas = []
      if File.exist?(FICHEIRO) && File.size(FICHEIRO) >= (TECTO_MB * 1024 * 1024)
        File.delete(FICHEIRO) rescue nil
      end
      File.open(FICHEIRO, "a") { |f| f.puts(lote) }
    rescue
      nil
    end

    def cabecalho!
      l = []
      l << ("=" * 74)
      l << "ARENA — O QUE O JOGO NORMAL TENTA METER CÁ DENTRO"
      l << ("iniciado em %s   mapa %s" %
            [Time.now.strftime("%Y-%m-%d %H:%M:%S"), ($game_map ? $game_map.map_id : "?")])
      l << ""
      l << "Cada linha do fluxo é a PRIMEIRA vez (até 5) que uma coisa acontece."
      l << "O número que interessa está no resumo: quantas vezes por segundo."
      l << ("=" * 74)
      l << ""
      File.open(FICHEIRO, "a") { |f| f.puts(l) }
    rescue
      nil
    end
  end
end

#-------------------------------------------------------------------------------
# OS PONTOS DE ENTRADA CONHECIDOS
#
# ⚠️ Cada um destes ja foi um defeito real. O gancho nao os corrige — eles ja
# estao corrigidos — conta quantas vezes a correccao teve de disparar, que e o
# que diz se o sistema de fora esta a insistir ou a desistir.
#-------------------------------------------------------------------------------
# ⚠️ NAO HA GANCHOS NOVOS AQUI, E ISSO E DE PROPOSITO.
#
# Cada ponto de entrada ja tem um dono — o bloqueio do spawner vive no MOD 192,
# a expulsao do peer fantasma no 136, a reposicao do ajudante no 189. Por um
# segundo embrulho em cima de cada um deles ganhava-se arrumacao e perdia-se o
# que interessa: um metodo com dois embrulhos e exactamente o tipo de coisa que
# este log foi feito para apanhar.
#
# Portanto os contadores sao chamados de DENTRO de quem ja la esta, com uma
# linha cada. Este ficheiro so guarda a conta e escreve o ficheiro.

#-------------------------------------------------------------------------------
# O CENSO CORRE NO TICK
#-------------------------------------------------------------------------------
class Scene_Map
  unless method_defined?(:anil_intruso_orig_update) ||
         private_method_defined?(:anil_intruso_orig_update)
    alias_method :anil_intruso_orig_update, :update
    def update
      anil_intruso_orig_update
      AnilArenaIntrusos.censo! if AnilArenaIntrusos.ligado?
    end
  end
end

#-------------------------------------------------------------------------------
# O COMANDO
#-------------------------------------------------------------------------------
module AnilArenaIntrusosComando
  module_function

  def tratar(texto)
    t = texto.to_s.strip
    return false unless t =~ %r{\A/intrusolog(?:\s+(.*))?\z}i
    arg = $1.to_s.strip.downcase
    a_mais = (defined?(AnilRaidCaverna) && (AnilRaidCaverna.admin? rescue false))
    return false unless a_mais || (AnilArena.libertada? rescue false)

    case arg
    when "off", "desligar", "parar"
      AnilArenaIntrusos.desligar!
      pbMessage(_INTL("Log de intrusos desligado.\nFicheiro: {1}", AnilArenaIntrusos.caminho)) rescue nil
    when "ja", "já", "resumo"
      if AnilArenaIntrusos.ligado?
        AnilArenaIntrusos.resumo!("pedido à mão")
        AnilArenaIntrusos.despejar!
        pbMessage(_INTL("Resumo escrito em {1}.", AnilArenaIntrusos.caminho)) rescue nil
      else
        pbMessage(_INTL("Não está a correr. Use /intrusolog para ligar.")) rescue nil
      end
    else
      AnilArenaIntrusos.ligar!
      pbMessage(_INTL("Log de intrusos LIGADO.\nConta tudo o que aparece na arena e não foi posto por nós.\nFicheiro: {1}", AnilArenaIntrusos.caminho)) rescue nil
    end
    true
  rescue => e
    (AnilLanRework.log("[INTRUSOLOG] falha: #{e.class}: #{e.message}") rescue nil)
    true
  end
end

module AnilLanRework
  module Chat
    class << self
      if !method_defined?(:anil_intruso_orig_send_message)
        alias_method :anil_intruso_orig_send_message, :send_message rescue nil
      end

      def send_message(text)
        return if AnilArenaIntrusosComando.tratar(text)
        anil_intruso_orig_send_message(text)
      end
    end
  end
end
