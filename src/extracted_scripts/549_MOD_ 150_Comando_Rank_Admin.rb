# encoding: UTF-8
#===============================================================================
# MOD: 150_Comando_Rank_Admin
#-------------------------------------------------------------------------------
# Comando de chat /rank, so para administradores. Roda a animacao de promocao
# do MOD 149 sem tocar em ponto nenhum.
#
#   /rank                    -> lista os emblemas disponiveis
#   /rank desafiante         -> anima a subida ATE Desafiante C
#   /rank desafiante b       -> anima a subida ATE Desafiante B
#   /rank lider a            -> anima a subida ate Lider A
#   /rank elite4             -> Elite 4 (sem divisao)
#   /rank campeao            -> Campeao (sem divisao)
#   /rank tudo               -> corre a escada inteira, um degrau de cada vez
#
# ⚠️ SO VISUAL. NAO MUDA O RANK.
#
# Nada aqui fala com o servidor nem escreve no @estado do MOD 147. O cartao de
# treinador continua a mostrar o rank verdadeiro — se ele mudasse, seria preciso
# desfazer a mentira depois, e bastaria um erro para o jogador ficar a ver um
# emblema que nao tem.
#
# Por isso a verificacao de administrador aqui e suficiente: o pior que alguem
# consegue, mesmo contornando-a, e ver uma animacao bonita no proprio ecra.
#
# A ANIMACAO PRECISA DE UM PONTO DE PARTIDA
#
# O MOD 149 anima a passagem de UM estado para outro — ele mostra o emblema
# antigo a virar o novo. Quando se pede um degrau directamente, usa-se o
# ANTERIOR na escada como ponto de partida, que e o que o jogador veria numa
# promocao de verdade.
#===============================================================================

module AnilComandoRank
  ADMINS = ["wallace-adm100"].freeze

  # A escada completa, na ordem. Cada degrau e [tier, rotulo].
  #
  # Tem de bater com o FAIXAS/ELITE_INICIO do servidor (Servidor/src/ranked.rb).
  # Aqui so interessam os NOMES, porque nada disto pontua.
  ESCADA = [
    [0, "Treinador C"],
    [0, "Treinador B"],
    [0, "Treinador A"],
    [1, "Desafiante C"],
    [1, "Desafiante B"],
    [1, "Desafiante A"],
    [2, "Lider C"],
    [2, "Lider B"],
    [2, "Lider A"],
    [3, "Elite 4"],
    [4, "Campeao"]
  ].freeze

  # Grafias aceites -> nome da faixa. Varias por faixa porque ninguem escreve
  # acentos nem se lembra da forma exacta a meio de um teste.
  NOMES = {
    "treinador"  => "Treinador",
    "trainer"    => "Treinador",
    "desafiante" => "Desafiante",
    "challenger" => "Desafiante",
    "lider"      => "Lider",
    "líder"      => "Lider",
    "leader"     => "Lider",
    "elite"      => "Elite 4",
    "elite4"     => "Elite 4",
    "e4"         => "Elite 4",
    "campeao"    => "Campeao",
    "campeão"    => "Campeao",
    "champion"   => "Campeao"
  }.freeze

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

  def lista
    "treinador, desafiante, lider (com A/B/C), elite4, campeao, tudo"
  end

  # Encontra o indice do degrau pedido. Devolve nil se nao existir.
  def indice_do_degrau(faixa, divisao)
    alvo = if %w[Elite\ 4 Campeao].include?(faixa)
             faixa
           else
             "#{faixa} #{(divisao || 'C').upcase}"
           end
    ESCADA.index { |(_t, rot)| rot == alvo }
  end

  # Monta os dois "estados" que o MOD 149 compara. Sao Hashes com a MESMA forma
  # do pacote ranked_state do servidor — assim a animacao nao sabe (nem precisa
  # de saber) que isto veio de um comando.
  def estado_do_degrau(i)
    tier, rotulo = ESCADA[i]
    { "tier" => tier, "rank" => rotulo, "points" => 0 }
  end

  def animar_degrau(i)
    return false if i.nil? || i <= 0
    antes  = estado_do_degrau(i - 1)
    depois = estado_do_degrau(i)
    AnilRankSubiu.agendar(antes, depois)
    true
  rescue => e
    AnilLanRework.log("[RANK/CMD] falha ao agendar: #{e.class}: #{e.message}") rescue nil
    false
  end

  # A escada inteira, um degrau por vez. Espera cada animacao acabar antes de
  # pedir a seguinte — o MOD 149 guarda UMA promocao pendente de cada vez, e
  # empilhar pedidos so faria as do meio desaparecerem.
  def animar_tudo
    Thread.new do
      begin
        (1...ESCADA.length).each do |i|
          animar_degrau(i)
          # Espera escoar. O limite evita ficar preso se o jogador entrar numa
          # batalha ou abrir um menu no meio da sequencia.
          esperou = 0
          while AnilRankSubiu.pendente? && esperou < 600
            sleep 0.1
            esperou += 1
          end
          sleep 0.4
        end
      rescue
      end
    end
    true
  end

  # Devolve true se tratou o texto (e portanto ele NAO vira mensagem de chat).
  def tratar(texto)
    t = texto.to_s.strip
    return false unless t =~ %r{\A/rank(?:\s+(\S+))?(?:\s+(\S+))?\z}i
    arg1 = $1
    arg2 = $2

    unless admin?
      avisar("[Sistema] Comando disponível apenas para administradores.")
      return true
    end

    unless defined?(AnilRankSubiu)
      avisar("[Rank] A animação não está instalada neste build.")
      return true
    end

    if arg1.nil?
      atual = (AnilRanqueado.rotulo rescue "")
      atual = "sem rank" if atual.to_s.empty?
      avisar("[Rank] Seu rank real: #{atual} (o comando NÃO muda isso).\n" \
             "Use /rank <emblema> [A|B|C]. Opções: #{lista}")
      return true
    end

    chave = arg1.to_s.strip.downcase
    if chave == "tudo"
      animar_tudo
      avisar("[Rank] Rodando a escada inteira, do Treinador B ao Campeão.")
      return true
    end

    faixa = NOMES[chave]
    unless faixa
      avisar("[Rank] '#{arg1}' não existe.\nOpções: #{lista}")
      return true
    end

    divisao = arg2.to_s.strip.upcase
    divisao = nil unless %w[A B C].include?(divisao)
    i = indice_do_degrau(faixa, divisao)

    if i.nil?
      avisar("[Rank] '#{faixa}' não aceita divisão #{arg2}.")
      return true
    end
    if i.zero?
      # Treinador C e o primeiro degrau: nao ha de onde subir para ele.
      avisar("[Rank] Treinador C é o piso — não há promoção para animar.\n" \
             "Tente /rank treinador b.")
      return true
    end

    animar_degrau(i)
    avisar("[Rank] Animando: #{ESCADA[i - 1][1]} → #{ESCADA[i][1]} (só visual).")
    AnilLanRework.log("[RANK/CMD] #{meu_id} pediu a animacao de #{ESCADA[i][1]}") rescue nil
    true
  rescue => e
    AnilLanRework.log("[RANK/CMD] falha no comando: #{e.class}: #{e.message}") rescue nil
    false
  end
end

module AnilLanRework
  module Chat
    class << self
      if !method_defined?(:anil_rankcmd_orig_send_message)
        alias_method :anil_rankcmd_orig_send_message, :send_message rescue nil
      end

      def send_message(text)
        return if AnilComandoRank.tratar(text)
        anil_rankcmd_orig_send_message(text)
      end
    end
  end
end

AnilLanRework.log("150_Comando_Rank_Admin carregado") rescue nil
