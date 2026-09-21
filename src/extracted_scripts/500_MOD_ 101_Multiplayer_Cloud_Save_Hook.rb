# encoding: UTF-8
#===============================================================================
# MOD: 101_Multiplayer_Cloud_Save_Hook
#-------------------------------------------------------------------------------
# Garante o correto funcionamento do Cloud Save (Download/Upload de saves na Nuvem):
# 1. Corrige o Download: Remove o guard block de `multiplayer_mode == true` que
#    impedia o download automático na tela de menu (antes de iniciar o game).
# 2. Corrige o Upload: Hook universal e 100% seguro em `SaveData.save_to_file`
#    para disparar o upload automático toda vez que o jogo for salvo (manual ou auto).
# 3. Salvamento Síncrono no Exit/Disconnect: Se o jogo estiver fechando (at_exit)
#    ou o jogador estiver desconectando, executa um salvamento e upload 100%
#    síncronos no main thread. Isso evita que os threads de background sejam mortos
#    ou a conexão seja cortada pelo interpretador antes do término da transmissão.
#===============================================================================

begin
  require 'timeout'
rescue LoadError
end

unless defined?(Timeout)
  module Timeout
    class Error < RuntimeError; end
    def self.timeout(sec)
      yield
    end
  end
end

#===============================================================================
# SAVE LOCAL ATRASADO
#===============================================================================
# O servidor recusou o upload porque o save desta maquina e ANTERIOR ao que ele
# tem. Antes ele respondia "success: true" e engolia o problema; o jogador
# continuava a jogar por cima do estado velho e, assim que o save_count dele
# passava o do servidor, o estado antigo era aceite e sobrepunha o bom.
#
# Aconteceu a serio em 16/08: uma troca confirmada as 17:12 foi desfeita as
# 20:12 por este caminho — um Pokemon duplicou e outro desapareceu.
#
# Aqui faz-se duas coisas, por esta ordem de importancia:
#
#   1. PARA DE ENVIAR SAVES nesta sessao. E o que impede o estrago: sem upload,
#      o save bom no servidor nao pode ser sobreposto, aconteca o que acontecer
#      do lado de ca.
#   2. Baixa o save autoritativo para o disco e avisa o jogador para reabrir.
#
# ⚠️ NAO se recarrega a partida em andamento. O jogo ja tem o estado velho na
# memoria, e continuar a jogar depois de trocar o ficheiro debaixo dele so
# geraria uma terceira versao divergente. Reabrir o jogo e a unica forma limpa.
#===============================================================================
#===============================================================================
# O RESULTADO DO DOWNLOAD DE SAVE
#===============================================================================
# ⚠️ Antes, uma falha no download era INVISIVEL.
#
# O menu de load ja fazia a coisa certa — baixa o save do servidor, rele do
# disco e carrega:
#
#     AnilLanRework.download_and_overwrite_save_file rescue nil
#     @save_data = SaveData.read_from_file(SaveData::FILE_PATH) if SaveData.exists?
#     Game.load(@save_data)
#
# Mas o `rescue nil` na chamada e o debug_log (desligado) la dentro faziam com
# que uma falha passasse sem rasto: o jogo entrava online com o save VELHO, e
# so muito depois, quando o save_count local ultrapassasse o do servidor, o
# estado antigo era aceite e apagava o que tinha acontecido no meio.
#
# Foi assim que a troca da lorena se perdeu em 16/08: as 20:11 nao ha nenhum
# "Save enviado" no log do servidor — o download nao aconteceu, e ninguem soube.
#
# Agora o desfecho fica registado e quem chama pode decidir.
#===============================================================================
module AnilLanRework
  class << self
    # :tentando | :ok | :sem_save | :corrompido | :falha
    def resultado_download_save; @resultado_download_save; end

    def marcar_download_save(estado, bytes = 0, detalhe = "")
      @resultado_download_save = estado
      AnilSaveAtrasado.registar(
        "download do save: #{estado}#{bytes > 0 ? " (#{bytes} bytes)" : ""}#{detalhe.empty? ? "" : " — #{detalhe}"}"
      ) rescue nil

      # ═══════════════════════════════════════════════════════════════════
      # O DOWNLOAD FALHOU: TRANCA OS UPLOADS JA.
      #
      # ⚠️ Nao da para impedir a entrada a partir daqui.
      #
      # Quem chama este metodo e o menu do plugin "013 Multi Save", que esta
      # dentro do PluginScripts.rxdata — binario que o compilar.rb nao gera e
      # que nao viaja no update. Ele faz `download_and_overwrite_save_file
      # rescue nil` e segue direto para o Game.load, aconteca o que acontecer.
      # Nao ha como o interromper sem editar o plugin.
      #
      # O que da para fazer, e resolve o estrago, e garantir que uma sessao
      # iniciada sobre um save NAO VERIFICADO nunca consiga sobrepor o save bom
      # que esta na nuvem. O jogador joga, mas nao envia. Quando ligar, o
      # servidor recusa o upload com "save_desatualizado" e o AnilSaveAtrasado
      # explica-lhe o que fazer.
      #
      # Perder a sessao e mau; apagar semanas de progresso alheio, que foi o que
      # aconteceu em 16/08, e muito pior.
      # ═══════════════════════════════════════════════════════════════════
      if [:falha, :corrompido].include?(estado)
        AnilSaveAtrasado.bloquear_por_download_falhado!
      end
    end

    # O save da nuvem chegou, ou nao existe nenhum (jogador novo)? Nesses dois
    # casos e seguro entrar. Qualquer outra coisa significa que este jogo pode
    # estar prestes a jogar em cima de um estado desatualizado.
    def download_save_confiavel?
      [:ok, :sem_save].include?(@resultado_download_save)
    end

    # ⚠️ "NAO SEI" NAO E "FALHOU". A DIFERENCA DECIDE QUEM ENTRA NO JOGO.
    #
    # O menu de load usa isto para recusar a entrada. Se fosse pelo
    # download_save_confiavel? (que so aceita :ok e :sem_save), ficavam de fora
    # os casos em que o download nem chegou a ser TENTADO — e ha dois legitimos,
    # ambos com `return` antes de qualquer marcacao:
    #
    #   * partida nova (o nome ainda e o placeholder)
    #   * player_id ainda nao canonico (contas -localhost, por exemplo)
    #
    # Nesses o estado fica nil, e nil quer dizer "ninguem tentou", nao
    # "correu mal". Bloquear ai seria trancar a porta a quem nunca teve save
    # nenhum na nuvem.
    #
    # O :tentando conta como falha de proposito: foi marcado no inicio da
    # tentativa e nunca foi substituido, portanto a resposta nao chegou.
    def download_save_falhou?
      [:falha, :corrompido, :tentando].include?(@resultado_download_save)
    end

    # Usada pelo menu de load quando ele recusa a entrada, para a tentativa
    # seguinte nao herdar o veredicto da anterior.
    def limpar_resultado_download_save!
      @resultado_download_save = nil
    end
  end
end


#===============================================================================
# COMPRESSAO DO SAVE NO TRANSPORTE
#===============================================================================
# ⚠️ O save viaja em base64 dentro do JSON, e base64 INFLA 33%.
#
# Medido nos saves reais: o do guima tem 746 KB e chegava a 995 KB na rede, a
# cada login e a cada upload. Comprimido antes de codificar, cai para 211 KB —
# 4,7x menos. Nos saves pequenos o ganho e de 3x.
#
# O Zlib ja e usado por este jogo (o Mystery Gift faz deflate + pack("m0") ha
# muito tempo), portanto nao ha dependencia nova.
#
# COMPATIBILIDADE
# Quem recebe olha a marca `save_gzip`. Sem ela, trata como antes. Assim
# cliente novo e servidor antigo — ou o contrario — continuam a funcionar.
#===============================================================================
module AnilSaveZip
  module_function

  # Devolve [texto_base64, comprimido?]. Se o Zlib falhar por qualquer razao,
  # cai para o formato antigo em vez de impedir o save.
  def empacotar(binario)
    return ["", false] if binario.nil? || binario.empty?
    z = Zlib::Deflate.deflate(binario, Zlib::BEST_COMPRESSION)
    # So vale a pena se encolheu mesmo. Um save ja comprimido ficaria maior.
    if z && z.bytesize < binario.bytesize
      [[z].pack("m0"), true]
    else
      [[binario].pack("m0"), false]
    end
  rescue
    [[binario].pack("m0"), false]
  end

  def desempacotar(texto_base64, comprimido)
    bruto = texto_base64.to_s.unpack("m0").first
    return bruto unless comprimido
    Zlib::Inflate.inflate(bruto)
  rescue
    # Marca errada, ou dados truncados: devolve nil para quem chama decidir.
    nil
  end
end

#===============================================================================
# UPLOAD POR SECOES — so o que mudou
#===============================================================================
# Um save do Essentials sao 19 seccoes independentes (o SaveData tem um registo
# proprio para cada uma). Medido no save do guima, 764 KB: as CAIXAS sao a maior
# parte, e quase nunca mudam. Andar no mapa mexe em game_player, map_metadata e
# switches — poucos KB. Hoje sobem os 764 KB de cada vez.
#
# ⚠️ O FORMATO GUARDADO NAO MUDA.
#
# O servidor continua a guardar um blob unico, como sempre. Isto e so uma
# optimizacao do TRANSPORTE: ele carrega a base que ja tem, substitui as seccoes
# recebidas e regrava. Nada muda para o download, para o painel, para a
# auditoria, nem para quem nao actualizou.
#
# ⚠️ MODO DE VERIFICACAO
#
# Enquanto VERIFICAR for true, envia-se o save INTEIRO **e** as seccoes. O
# servidor grava o inteiro (risco zero) e funde as seccoes so para comparar,
# registando qualquer divergencia. Sem ganho de trafego nesta fase — de
# proposito: primeiro prova-se que a fusao da o mesmo resultado, depois liga-se.
#
# A trava de seguranca e a VERSAO: so se manda parcial se este aparelho estiver
# na mesma versao que o servidor. Costurar pedacos sobre uma base diferente da
# que conhecemos e exactamente o erro que nao se pode cometer.
#===============================================================================
module AnilSaveSecoes
  VERIFICAR = true      # enquanto true, manda inteiro + seccoes

  # Interruptor local, por instalacao.
  #
  # A constante viaja compilada no Scripts.rxdata, portanto vale para toda a
  # gente. Para poder experimentar o modo "so seccoes" numa maquina sem o impor
  # a todos, basta existir `Data/so_seccoes.txt` nessa instalacao. Sem o
  # ficheiro nada muda — e o que acontece na maquina de todos os jogadores.
  INTERRUPTOR_LOCAL = "Data/so_seccoes.txt"

  module_function

  # ⚠️ QUEM DECIDE E O SERVIDOR, pelo join_ack.
  #
  # A decisao deixou de estar compilada. Se estivesse, desligar isto em
  # emergencia obrigava a gerar um Scripts.rxdata novo e esperar que toda a
  # gente o apanhasse pelo updater — e com 30 pessoas online e saves a serem mal
  # fundidos, uma hora e muito tempo.
  #
  # Ordem de decisao:
  #   1. Data/so_seccoes.txt existe  -> LIGADO (excepcao por aparelho, para
  #                                     testar sem mexer em toda a gente)
  #   2. o servidor disse no join_ack -> vale o que ele disse
  #   3. ainda nao disse nada         -> DESLIGADO
  #
  # O 3 e deliberado: enquanto nao se sabe, manda-se o save inteiro. Mandar a
  # mais custa dados; mandar so seccoes contra um servidor que nao as sabe
  # fundir custa o save.
  #
  # ⚠️ E por isso que NAO se guarda o resultado em cache. A primeira versao
  # fazia `return @so_seccoes unless @so_seccoes.nil?`, e como isto e chamado
  # antes do join_ack chegar, ficava preso em false para a sessao inteira — o
  # interruptor do servidor nunca pegava.
  def so_seccoes?
    return true if @ficheiro_local.nil? ? (@ficheiro_local = File.exist?(INTERRUPTOR_LOCAL)) : @ficheiro_local
    return false if VERIFICAR && @servidor_diz.nil?
    !VERIFICAR || @servidor_diz == true
  rescue
    false
  end

  # Chamado ao receber o join_ack. nil = o servidor nao falou no assunto (build
  # antigo do lado dele), e nesse caso fica-se pelo save inteiro.
  def servidor_definiu!(valor)
    @servidor_diz = (valor == true)
    anotar("SECCOES: o servidor disse #{@servidor_diz ? 'LIGADO' : 'desligado'}")
  rescue
    nil
  end

  # crc32 em vez de sha: e o que existe no RGSS via Zlib, e serve — aqui so se
  # quer saber SE mudou, nao provar identidade contra um adversario.
  # ⚠️ REGISTO DEDICADO A SECCAO QUE JA FALHOU UMA VEZ.
  #
  # A `storage_system` (as caixas) foi a unica que o verificador apanhou
  # divergente, e foi ela que impediu ligar o modo "so seccoes" ha meses. Vale
  # ter os numeros do lado do CLIENTE tambem: o servidor so ve o resultado, e
  # nao sabe se a seccao chegou a ser enviada, se o CRC mudou, ou se ficou
  # pendente a espera de ACK.
  #
  # Ficheiro proprio (nunca os logs globais, que travam o "recuperar partida").
  ARQUIVO_CAIXAS = "Data/anil_caixas_seccao.txt"
  VIGIADAS = ["storage_system", "bag", "map_factory", "global_metadata"].freeze

  # ⚠️ QUAIS DESTAS SE ABREM PARA VER O QUE MUDOU LA DENTRO.
  #
  # Saber que o map_factory "mudou" nao ajuda: ele muda em 95% dos uploads e nao
  # se sabe porque. Abrir o objecto e comparar variavel a variavel diz se e uma
  # coisa que muda mesmo (mapas novos visitados) ou ruido (um contador, uma
  # ordem de hash) — e a segunda hipotese e a maior poupanca que sobra.
  #
  # So se abrem estas duas: a box e a mochila sao grandes e nao ha duvidas sobre
  # elas.
  ABRIR = ["map_factory", "global_metadata"].freeze

  # Tecto para nao gastar tempo a comparar objectos enormes.
  MAX_ABRIR = 400_000

  # Compara o dump anterior com o novo e diz QUE variaveis diferem.
  #
  # Corre so quando a seccao ja mudou (portanto raramente para as caladas) e so
  # para as que estao em ABRIR. Qualquer falha e silenciosa: isto e diagnostico,
  # nao pode estragar um save.
  def diferencas(nome, antigo, novo)
    return nil unless ABRIR.include?(nome.to_s)
    return nil if antigo.nil? || novo.nil?
    return "grande demais" if novo.bytesize > MAX_ABRIR

    a = Marshal.load(antigo)
    b = Marshal.load(novo)
    return "tipo mudou (#{a.class} -> #{b.class})" if a.class != b.class

    if a.is_a?(Hash)
      chaves = (a.keys | b.keys)
      dif = chaves.reject { |k| (Marshal.dump(a[k]) == Marshal.dump(b[k]) rescue false) }
      return dif.empty? ? "nada (mas o CRC mudou)" : dif.map(&:to_s).join(", ")
    end

    ivs = (a.instance_variables | b.instance_variables)
    dif = ivs.reject do |iv|
      (Marshal.dump(a.instance_variable_get(iv)) ==
       Marshal.dump(b.instance_variable_get(iv)) rescue false)
    end
    return "nada (mas o CRC mudou)" if dif.empty?
    # Tamanho de cada uma que mudou, para se saber onde esta o peso.
    dif.map { |iv|
      t = (Marshal.dump(b.instance_variable_get(iv)).bytesize rescue 0)
      "#{iv}(#{t}B)"
    }.join(", ")
  rescue => e
    "falhou a comparar (#{e.class})"
  end

  # ⚠️ Passou a obedecer ao interruptor comum (Data/anil_debug.txt).
  #
  # Escrevia sempre, e abre o ficheiro 3 a 6 vezes por upload — com o autosave
  # a disparar a cada batalha isso e I/O sincrono constante no telemovel. O
  # diagnostico das seccoes ja deu o que tinha a dar; para o voltar a ligar,
  # cria-se o Data/anil_debug.txt e reinicia-se.
  def anotar(texto)
    return unless (anil_diagnostico_ligado? rescue false)
    File.open(ARQUIVO_CAIXAS, "a:UTF-8") do |fh|
      fh.puts("[#{Time.now.strftime('%d/%m %H:%M:%S')}] #{texto}")
    end
  rescue
    nil
  end

  def marca(bytes)
    Zlib.crc32(bytes)
  rescue
    0
  end

  def base; @base.to_i; end

  # Retira o save inteiro do pacote quando este cliente esta em modo
  # "so seccoes". So o faz se houver mesmo seccoes para mandar: se nao houver,
  # o inteiro e a UNICA coisa que o servidor tem para gravar e tira-lo seria
  # perder a gravacao.
  def aliviar!(pacote)
    return pacote unless so_seccoes?
    secs = pacote["save_sections"]
    # ⚠️ Sem seccoes, o inteiro e a UNICA copia. Tira-lo seria perder a gravacao.
    return pacote unless secs.is_a?(Hash) && !secs.empty?
    # ⚠️ MEDE-SE O QUE VIAJA, E NAO O QUE ESTA EM MEMORIA.
    #
    # O tamanho "cru" de uma seccao (o Marshal antes de gzip e base64) nao se
    # compara com o save inteiro, que ja vai comprimido. Contar as duas coisas
    # na mesma moeda — bytes no pacote — e a unica forma de saber se isto
    # compensa mesmo.
    antes = pacote["save_data"].to_s.bytesize
    depois = 0
    secs.each_value do |v|
      depois += (v.is_a?(Hash) ? v["b64"].to_s.bytesize : v.to_s.bytesize)
    end
    pacote["save_data"] = ""
    pacote["save_gzip"] = false
    poupado = antes - depois
    pct = (antes > 0) ? ((poupado * 100.0) / antes).round : 0
    anotar("SO SECCOES: inteiro #{antes}B -> #{secs.keys.size} seccao(oes) #{depois}B "            "(#{poupado >= 0 ? 'poupou' : 'GASTOU'} #{poupado.abs}B, #{pct}%)")
    anotar("  seccoes: #{secs.keys.join(', ')}")
    pacote
  rescue
    pacote
  end

  # O servidor confirmou o upload. So agora as seccoes enviadas contam como
  # entregues, e a base avanca. Se o ACK nunca vier, ou vier negativo, os
  # pendentes sao descartados e tudo o que mudou volta a ser enviado.
  def confirmar!(versao)
    v = versao.to_i
    return if v <= 0 || @crcs.nil?
    if @pendentes.is_a?(Hash) && !@pendentes.empty?
      vig = @pendentes.keys.map(&:to_s) & VIGIADAS
      anotar("ACK v#{v}: confirmadas #{@pendentes.keys.size} seccao(oes)"              "#{vig.empty? ? '' : " — inclui #{vig.join(', ')}"}") unless vig.empty?
      @crcs.merge!(@pendentes)
      @pendentes = {}
    end
    @base = v
  end

  # ACK negativo: nada foi entregue. Esquecer os pendentes faz o proximo envio
  # incluir tudo de novo.
  def descartar_pendentes!
    @pendentes = {}
  end

  def limpar!
    @crcs = nil
    @base = 0
    @dono = nil
    @pendentes = {}
  end

  # Mesma razao da versao: duas contas na mesma instalacao nao podem partilhar a
  # contabilidade do que ja foi enviado.
  def trocou_de_conta?
    id = (AnilSaveVersao.quem rescue "")
    return false if id.empty?
    mudou = (@dono != id)
    @dono = id
    mudou
  end

  # Devolve {nome => base64(gzip(marshal))} das seccoes que mudaram, ou nil se
  # nao der para mandar parcial nesta vez.
  def seccoes_alteradas(binario, versao_atual)
    return nil if binario.nil? || binario.empty?
    return nil if versao_atual.to_i <= 0

    # ⚠️ O corte vem da GRAVACAO, nao de um load do ficheiro.
    #
    # Fatiar aqui com `Marshal.load(binario)` era o que produzia as divergencias
    # do `map_factory`: o `Game_Map#marshal_load` le os MapXXX.rxdata do disco e
    # chama `refresh` nos eventos, e o grafo recarregado ja nao e o que foi
    # gravado. Ver AnilSaveCorte, no 099.
    #
    # ⚠️ Sem corte NAO se fatia — manda-se o inteiro.
    #
    # O caminho antigo (Marshal.load do ficheiro) ficou aqui como rede durante
    # meia hora e foi um erro: misturar as duas origens faz os CRCs compararem
    # bytes de proveniencias diferentes e tudo parece ter mudado. Ou a
    # contabilidade inteira assenta no corte, ou nao ha contabilidade.
    #
    # Devolver nil e seguro: o servidor recebe o save completo, os CRCs ficam
    # como estavam, e o proximo upload que tenha corte volta a mandar so a
    # diferenca real.
    novos = (AnilSaveCorte.actual rescue nil) if defined?(AnilSaveCorte)
    return nil unless novos.is_a?(Hash) && !novos.empty?

    # ⚠️ A linha de base NAO se compara com a versao actual.
    #
    # Era o que estava aqui, e por isso nunca se enviava nada: cada upload do
    # proprio jogador incrementa a versao (1634 -> 1635 -> 1636), entao
    # `@base == versao_atual` nunca se sustentava entre dois envios e o cliente
    # refazia a base todas as vezes.
    #
    # O que a base significa e "de que estado os meus CRCs falam". Ela e
    # actualizada no ACK, quando o servidor confirma que aquele estado passou a
    # ser o dele. Aqui so se verifica se existe.
    if trocou_de_conta? || @crcs.nil? || @base.to_i <= 0
      @crcs = {}
      novos.each { |k, v| @crcs[k] = marca(v) }
      @base = versao_atual.to_i
      return nil
    end

    # ⚠️ A BAIXA SO ACONTECE NO ACK.
    #
    # Antes o @crcs era actualizado aqui, ao MONTAR o pacote. Se o servidor
    # descartasse as seccoes — e descartava, em todos os uploads com base
    # divergente — o cliente ja tinha riscado aquelas seccoes da lista e nunca
    # mais as enviava. O servidor ficava com a versao velha da mochila e das
    # caixas para sempre.
    #
    # Foi o verificador que apanhou isto: apareceram `bag` e `storage_system`
    # marcadas como "NAO enviada" e mesmo assim divergentes do save inteiro. Com
    # a fusao a valer, aquele upload teria apagado a mochila e a PC do jogador.
    mudou = {}
    @pendentes = {}
    novos.each do |k, v|
      m = marca(v)
      if VIGIADAS.include?(k.to_s)
        mudou_esta = (@crcs[k] != m)
        anotar("#{k}: #{mudou_esta ? 'MUDOU' : 'IGUAL '} #{v.to_s.bytesize}B base=v#{@base}")
        if mudou_esta
          @anterior ||= {}
          d = diferencas(k, @anterior[k], v)
          anotar("    -> mudou: #{d}") if d
        end
        (@anterior ||= {})[k] = v
      end
      next if @crcs[k] == m
      texto, comprimido = AnilSaveZip.empacotar(v)
      mudou[k] = { "b64" => texto, "gzip" => comprimido }
      @pendentes[k] = m
    end
    # Uma seccao que desaparecesse teria de ser comunicada; na pratica o conjunto
    # e fixo, mas se encolher e mais seguro mandar tudo do que fingir que nada
    # mudou.
    return nil if novos.size != @crcs.size

    mudou.empty? ? nil : mudou
  rescue => e
    AnilSaveAtrasado.registar("seccoes: falha ao calcular (#{e.class}) — enviando inteiro") rescue nil
    nil
  end
end

#===============================================================================
# A VERSAO DO SAVE NA NUVEM
#===============================================================================
# Guarda qual foi a ultima versao do servidor que ESTE APARELHO sincronizou.
#
# ⚠️ E deliberadamente um ficheiro a parte, e nao um campo dentro do save.
#
# A pergunta que isto responde e "este aparelho esta em dia?", e a resposta e
# uma propriedade da INSTALACAO, nao do conteudo. Um save copiado de outro
# telemovel traria a versao do outro aparelho e mentiria.
#
# ⚠️ E NAO se usa o save_count para isto.
#
# O save_count e local: cada instalacao tem o seu, e sobe a cada gravacao. Um PC
# usado ha meses chega aos 15.000 com conteudo de semana passada enquanto o
# telemovel esta nos 12.000 com o progresso de hoje — e o servidor, ao comparar
# 15.000 com 12.000, conclui que o PC esta a frente. Foi assim que o
# bilauzinho/bilaumaster viu o save desatualizado no PC sem uma unica rejeicao
# no log do servidor em 31 entradas.
#
# A versao do commit e uma sequencia unica, mantida pelo servidor. Nao depende
# do aparelho, nem do tamanho do ficheiro — saves encolhem em jogo normal
# (vender Pokemon, mudar para um mapa menor), entao tamanho tambem nao serve.
#===============================================================================
# ⚠️ TESTEMUNHO DE LINHAGEM DO SAVE.
#
# O servidor emite um testemunho a cada commit aceite e a cada entrega de save,
# e o proximo upload tem de o devolver. Um aparelho que se separou (o telemovel
# que continuou a jogar por fora, e depois envia um save de antes de uma venda)
# traz o testemunho antigo e e recusado — que era o furo que devolvia itens ja
# vendidos para a mochila.
#
# Guarda-se do mesmo modo que a versao, `player_id=testemunho` por linha, porque
# o Multi Save permite varias contas na mesma instalacao e o testemunho e de
# CADA conta. Um ficheiro so com um valor faria a conta A mandar o da conta B.
#
# NAO vai dentro do save: se fosse, copiar o ficheiro do save copiava tambem a
# credencial, e o fork passava a ser valido — o contrario do que se quer.
module AnilSaveToken
  ARQUIVO = "Data/anil_save_token.txt"

  module_function

  def quem
    AnilSaveVersao.quem
  rescue
    ""
  end

  def todas
    mapa = {}
    return mapa unless File.exist?(ARQUIVO)
    File.readlines(ARQUIVO, encoding: "UTF-8").each do |linha|
      k, v = linha.strip.split("=", 2)
      next if k.nil? || v.nil?
      mapa[k.strip.downcase] = v.strip
    end
    mapa
  rescue
    {}
  end

  def ler
    id = quem
    return "" if id.empty?
    todas[id].to_s
  rescue
    ""
  end

  def gravar(t)
    v = t.to_s.strip
    return if v.empty?
    id = quem
    return if id.empty?
    mapa = todas
    return if mapa[id] == v
    mapa[id] = v
    File.open(ARQUIVO, "w:UTF-8") { |f| mapa.each { |k, val| f.puts("#{k}=#{val}") } }
  rescue
  end

  def esquecer(player_id = nil)
    id = (player_id || quem).to_s.strip.downcase
    return if id.empty?
    mapa = todas
    return unless mapa.key?(id)
    mapa.delete(id)
    File.open(ARQUIVO, "w:UTF-8") { |f| mapa.each { |k, val| f.puts("#{k}=#{val}") } }
  rescue
  end
end

module AnilSaveVersao
  ARQUIVO = "Data/anil_save_versao.txt"

  module_function

  # ⚠️ A versao e POR CONTA, nao por pasta do jogo.
  #
  # O plugin "013 Multi Save" permite varias contas na mesma instalacao. Com um
  # numero unico no ficheiro, alternar de conta faria o upload de uma declarar a
  # versao da outra — e o servidor recusaria (ou aceitaria) pelo motivo errado.
  # Guarda-se `player_id=versao` por linha.
  def quem
    id = (AnilLanRework.get_player_id rescue nil).to_s.strip.downcase
    return id unless id.empty?
    (AnilLanRework.read_cfg("multiplayer_player.txt", "id", "").to_s.strip.downcase rescue "")
  rescue
    ""
  end

  def todas
    mapa = {}
    return mapa unless File.exist?(ARQUIVO)
    File.readlines(ARQUIVO, encoding: "UTF-8").each do |linha|
      k, v = linha.strip.split("=", 2)
      next if k.nil? || v.nil?
      mapa[k.strip.downcase] = v.to_i
    end
    mapa
  rescue
    {}
  end

  def ler
    id = quem
    return 0 if id.empty?
    todas[id].to_i
  rescue
    0
  end

  def gravar(v)
    n = v.to_i
    return if n <= 0
    id = quem
    return if id.empty?
    mapa = todas
    return if mapa[id] == n
    mapa[id] = n
    File.open(ARQUIVO, "w:UTF-8") { |f| mapa.each { |k, val| f.puts("#{k}=#{val}") } }
    AnilSaveAtrasado.registar("versao sincronizada: #{id} v#{n}") rescue nil
  rescue
  end

  # Instalacao nova, ou cliente que nunca sincronizou: devolve 0, e o servidor
  # trata isso como "nao sei", caindo no comportamento antigo em vez de recusar.
  def conhecida?; ler > 0; end

  # Apaga o que sabiamos desta conta. Usa-se quando o save local foi substituido
  # por fora do fluxo normal (recuperar partida): declarar a versao velha faria o
  # servidor recusar o save que ele proprio acabou de entregar. Sem versao, o
  # guarda e pulado — que e o comportamento seguro.
  def esquecer(player_id = nil)
    id = (player_id || quem).to_s.strip.downcase
    return if id.empty?
    mapa = todas
    return unless mapa.key?(id)
    mapa.delete(id)
    File.open(ARQUIVO, "w:UTF-8") { |f| mapa.each { |k, val| f.puts("#{k}=#{val}") } }
    AnilSaveAtrasado.registar("versao esquecida para #{id} (save substituido por fora)") rescue nil
  rescue
  end
end

module AnilSaveAtrasado
  module_function

  def bloqueado?; @bloqueado == true; end

  # Chamado quando o download do save da nuvem falhou no arranque. Nao mostra
  # nada aqui: o jogador ainda esta na tela de load e uma caixa de texto no meio
  # da transicao para o mapa some sem ser lida. O aviso sai na primeira recusa
  # do servidor, que acontece no primeiro autosave depois de ligar.
  def bloquear_por_download_falhado!
    return if @bloqueado
    @bloqueado = true
    registar("download do save falhou no arranque — uploads bloqueados nesta sessao por precaucao")
  rescue
  end

  def tratar(packet)
    return if @bloqueado    # uma vez por sessao basta
    @bloqueado = true

    meu  = packet["client_save_count"].to_i
    dele = packet["server_save_count"].to_i
    registar("save local atrasado: cliente=#{meu} servidor=#{dele} — uploads bloqueados nesta sessao")

    ok = begin
      AnilLanRework.download_and_overwrite_save_file
      true
    rescue => e
      registar("falha ao baixar o save autoritativo: #{e.class}: #{e.message}")
      false
    end

    # ⚠️ NAO SE PEDE AO JOGADOR QUE FECHE O JOGO. LEVA-SE O JOGO AO TITULO.
    #
    # O texto antigo dizia "feche e abra o jogo para continuar" e deixava-o a
    # jogar. So que a partir deste ponto NADA sobe para a nuvem — o bloqueio e
    # para a sessao inteira, de proposito, para nao sobrepor o save bom. Quem
    # continuasse a jogar estava a acumular horas que iam ser deitadas fora:
    # ao relogar, o cliente carrega o save autoritativo e tudo o que veio depois
    # do aviso desaparece. Era isto que os jogadores viam como "rollback".
    #
    # Pior ainda quando o download correu bem: o ficheiro no disco ja e o bom,
    # e qualquer gravacao local posterior escreve o estado velho por cima dele.
    # Continuar a jogar nao e so inutil — e destrutivo.
    #
    # Ir ao titulo e a unica resposta honesta: perde-se o que houve desde o
    # ultimo upload aceite (que ja estava perdido de qualquer maneira) e nao se
    # perde mais nada. O mesmo caminho do "conexao perdida", que ja trata do
    # ecra preto e do estado do save.
    if ok
      texto = _INTL("\r[Save desatualizado]\n\nBaixamos a versao do servidor.\nO jogo vai voltar a tela de titulo.\n\nEntre novamente para continuar.")
    else
      texto = _INTL("\r[Save desatualizado]\n\nNao consegui baixar a versao do servidor.\nVerifique sua conexao e entre novamente.")
    end
    feito = false
    if defined?(AnilLanRework) && AnilLanRework.respond_to?(:force_main_title!)
      begin
        AnilLanRework.force_main_title!("servidor_offline.png", texto)
        feito = true
      rescue => e
        registar("falha ao voltar ao titulo: #{e.class}: #{e.message}")
      end
    end
    unless feito
      # Sem o caminho do titulo, ao menos nao se mente: o aviso diz que o que
      # for feito daqui para a frente nao vai ser guardado.
      aviso = _INTL("Seu save esta desatualizado.\nFeche o jogo AGORA — nada mais sera salvo nesta sessao.")
      if defined?(pbMessage)
        pbMessage(aviso) rescue nil
      else
        AnilLanRework.add_popup(aviso, 20.0) rescue nil
      end
    end
  rescue => e
    registar("falha ao tratar save atrasado: #{e.class}: #{e.message}")
  end

  # Ficheiro proprio: o log global do jogo nao pode ser ligado (trava o
  # "recuperar partida"), e este e exactamente o tipo de evento que precisa de
  # deixar rasto para se poder auditar depois.
  def registar(texto)
    return unless (anil_diagnostico_ligado? rescue false)
    File.open("Data/anil_save_atrasado.txt", "a:UTF-8") do |f|
      f.puts("[#{Time.now.strftime('%d/%m %H:%M:%S')}] #{texto}")
    end
  rescue
  end
end

# Reabre a classe de conexão se ela estiver definida para interceptar o ACK
if defined?(AnilLanRework) && defined?(AnilLanRework::Connection)
  class AnilLanRework::Connection
    attr_accessor :last_upload_save_ack

    if !method_defined?(:anil_orig_handle_packet)
      alias_method :anil_orig_handle_packet, :handle_packet
      def handle_packet(packet)
        if packet["type"] == "upload_save_ack"
          @last_upload_save_ack = packet
          # O servidor diz em que versao ficou. E assim que este aparelho
          # aprende o seu lugar na sequencia, para o proximo upload.
          if packet["version"].to_i > 0
            AnilSaveVersao.gravar(packet["version"])
          end
          # O testemunho para o proximo upload. Roda a cada commit aceite.
          AnilSaveToken.gravar(packet["save_token"]) unless packet["save_token"].to_s.empty?
          if packet["success"] == false
            AnilSaveSecoes.descartar_pendentes!
          elsif packet["version"].to_i > 0
            AnilSaveSecoes.confirmar!(packet["version"])
          end
          # O servidor nao conseguiu montar o save a partir das seccoes. Esquece
          # o que julgavamos ja ter enviado: o proximo upload vai inteiro.
          if packet["reason"].to_s == "enviar_save_completo"
            AnilSaveSecoes.limpar!
            AnilSaveAtrasado.registar("servidor recusou a fusao — proximo upload sera completo") rescue nil
          end
          # ⚠️ Este save veio de um aparelho que se separou da linhagem.
          #
          # Nao ha nada a reenviar: o servidor vai recusar na mesma enquanto o
          # testemunho for o antigo. A unica saida e recuperar a partida, que
          # baixa o estado do servidor e emite um testemunho novo.
          if packet["reason"].to_s == "save_token_mismatch"
            AnilSaveSecoes.descartar_pendentes! rescue nil
            unless $anil_avisou_token_invalido
              $anil_avisou_token_invalido = true
              AnilLanRework.enqueue_popup(
                _INTL("Este save é de outro aparelho e não foi aceite. Use \"Recuperar partida\" para trazer o estado do servidor."),
                12.0) rescue nil
            end
          end
          AnilSaveAtrasado.tratar(packet) if packet["reason"].to_s == "save_desatualizado"
          return
        end
        anil_orig_handle_packet(packet)
      end
    end
  end
end

module AnilLanRework
  class << self
    # ──────────────────────────────────────────────────────────────────────────
    # DIAGNÓSTICO E LOGGING: Grava em cloud_save_debug.txt na raiz do jogo
    # ──────────────────────────────────────────────────────────────────────────
    def debug_log(msg)
      # Disabled
    end

    # ═══════════════════════════════════════════════════════════════════════
    # GRAVAR JA — para o que acontece do lado do SERVIDOR primeiro.
    #
    # ⚠️ NAO passa pelo can_save_safely? nem pela janela de 60s.
    #
    # Ha accoes cujo passo decisivo acontece no servidor e nao pode ser desfeito:
    # largar um item (o servidor po-e no chao), apanhar um item (o servidor
    # marca como coletado), abrir uma caixa. Se a gravacao local ficar para
    # depois, fechar o jogo no meio produz um estado divergente:
    #
    #   largar sem gravar  -> item no chao E na mochila  (DUPLICA)
    #   apanhar sem gravar -> item fora do chao e fora da mochila (PERDE)
    #
    # Escreve-se o ficheiro directamente, como o execute_trade faz depois de uma
    # troca, e so depois se pede o upload — que pode ser adiado a vontade,
    # porque o disco ja esta correcto.
    # ═══════════════════════════════════════════════════════════════════════
    def gravar_ja!(motivo = "acao_autoritativa")
      if defined?(Game) && Game.respond_to?(:save)
        Game.save
      elsif defined?(SaveData) && SaveData.respond_to?(:save_to_file)
        SaveData.save_to_file(SaveData::FILE_PATH)
      end
      save_and_upload_save_file(motivo) rescue nil
      true
    rescue => e
      log("[GRAVAR_JA] falha (#{motivo}): #{e.class}: #{e.message}") rescue nil
      false
    end

    def can_save_safely?
      return false if !$scene.is_a?(Scene_Map)
      return false if $scene.instance_variable_get(:@spritesetGlobal).nil? rescue true
      return false if $game_temp && ($game_temp.in_battle || $game_temp.transition_processing || $game_temp.player_transferring)
      return false if pbMapInterpreterRunning? rescue false
      true
    end

    # ── Throttle de autosave ──────────────────────────────────────────────────
    # Cada upload de save custava um DOWNLOAD do save inteiro no Supabase (o
    # .bak era feito baixando e reenviando), e o jogo salvava em item_added,
    # item_removed, pokemon_added, pokemon_stored, battle_ended e map_entered —
    # dezenas de vezes por hora, por jogador. Era a maior fatia do egress do
    # free tier. O lado do servidor ja nao baixa nada, mas continuar a mandar um
    # save de 46KB-484KB a cada item apanhado nao serve a ninguem.
    #
    # Os motivos ARRISCADOS ficam imediatos: sair do jogo, cair a ligacao e
    # entrar em batalha (o momento em que um crash custa mais). O resto agrupa-se
    # numa janela, com um disparo de cauda para nada se perder.
    # "trade_started" e imediato por uma razao de correcao, nao de risco:
    #
    # O servidor valida a posse do Pokemon lendo o SAVE EM DISCO
    # (player_owns_pokemon?). Com os motivos de aquisicao — pokemon_added,
    # pokemon_stored, battle_ended — agrupados nesta janela, um Pokemon acabado
    # de apanhar ainda nao estava no save do servidor, e a troca era recusada com
    # "o Pokemon selecionado nao foi encontrado na sua partida salva". Antes do
    # throttle esses motivos subiam na hora e a janela era de segundos; depois
    # dele passou a haver ate 60s em que qualquer captura recente era introcavel.
    #
    # Salvar ao ABRIR a troca resolve sem afrouxar a validacao: o convite tem uma
    # espera visivel (90s de timeout) e quem aceita ainda vai escolher o Pokemon,
    # portanto o upload chega bem antes de a posse ser conferida.
    # "gift_box" e imediato pela mesma razao do trade_started: e o save que fecha
    # a janela de duplicacao da caixa (ver MOD 068). Adiado, nao serve para nada.
    # ⚠️ A CAPTURA E IMEDIATA. Nao tinha de ser assim por acaso — nao era.
    #
    # pokemon_added / pokemon_stored / pokemon_added_silent estavam FORA desta
    # lista, ou seja, apanhados pela janela de 60s como um item qualquer. Quem
    # apanhasse um shiny e fechasse o jogo a seguir perdia-o, ate um minuto de
    # capturas. Isto e anterior ao piso do battle_started; era assim desde que o
    # throttle existe.
    #
    # Custa pouco: durante a batalha o `can_save_safely?` e falso, entao as tres
    # capturas de uma horda ficam na fila e saem como UM upload no fim (ver
    # flush_deferred_autosaves!, que agora manda um so). Uma batalha em que se
    # apanha alguma coisa passa a valer um upload; as outras nao valem nenhum.
    #
    # Nao levam piso, ao contrario do battle_started: entrar em batalha repete-se
    # de 4 em 4 segundos, apanhar nao. E o que se protege aqui e a unica coisa
    # que o jogador nao aceita perder.
    AUTOSAVE_IMEDIATO = ["game_exit", "disconnect", "battle_started", "trade_started", "gift_box",
                         "pokemon_added", "pokemon_added_silent", "pokemon_stored",
                         "pc_box"].freeze
    AUTOSAVE_JANELA   = 60.0

    # ⚠️ PISO SO PARA O battle_started.
    #
    # Os outros imediatos sao raros ou sao portoes de correcao: game_exit e
    # disconnect acontecem uma vez, trade_started tem 90s de espera visivel, e
    # gift_box fecha a janela de duplicacao da caixa (MOD 068). Nenhum deles
    # inunda.
    #
    # O battle_started inunda. Ele estava na lista para o caso de um crash a
    # meio da batalha, mas cada encontro selvagem passa por aqui, e com o doce
    # aroma sao encontros de 4 em 4 segundos. No log de 01/09 sao ~35 uploads em
    # 5m16s (v5341 -> v5381), ~50KB cada: 20MB/h por jogador so nisto.
    #
    # Com o piso, a primeira batalha depois de uma pausa continua a salvar na
    # hora — que e o caso que a protecao contra crash serve — e uma sequencia de
    # batalhas passa a valer um upload. O que se arrisca perder num crash sao os
    # PISO segundos anteriores, nao a sessao.
    AUTOSAVE_PISO_BATALHA = 30.0

    def autosave_throttle_segura?(reason)
      agora = Time.now.to_f
      @ultimo_autosave_at ||= 0.0

      if AUTOSAVE_IMEDIATO.include?(reason.to_s)
        # O battle_started respeita um piso proprio: sem ele, uma cadeia de
        # encontros furava a janela de 60s a cada batalha (ver AUTOSAVE_PISO_BATALHA).
        if reason.to_s == "battle_started" &&
           (agora - @ultimo_autosave_at) < AUTOSAVE_PISO_BATALHA
          @autosave_atrasado = reason.to_s
          return true
        end
        @ultimo_autosave_at = agora
        @autosave_atrasado  = nil
        return false
      end

      if (agora - @ultimo_autosave_at) < AUTOSAVE_JANELA
        # Guarda so o motivo mais recente: o save e um retrato do jogo inteiro,
        # entao o ultimo cobre todos os anteriores.
        @autosave_atrasado = reason.to_s
        return true
      end

      @ultimo_autosave_at = agora
      @autosave_atrasado  = nil
      false
    end

    # Disparo de cauda: chamado a cada frame do mapa. Sem isto, o ultimo evento
    # antes de o jogador ficar parado nunca subiria.
    def flush_autosave_atrasado!
      return if @autosave_atrasado.nil?
      return unless (Time.now.to_f - (@ultimo_autosave_at || 0.0)) >= AUTOSAVE_JANELA
      return unless can_save_safely?
      reason = @autosave_atrasado
      @autosave_atrasado = nil
      save_and_upload_save_file(reason)
    end

    def queue_deferred_autosave!(reason)
      @pending_autosave_reasons ||= []
      @pending_autosave_reasons << reason unless @pending_autosave_reasons.include?(reason)
    end

    def flush_deferred_autosaves!
      return if @pending_autosave_reasons.nil? || @pending_autosave_reasons.empty?
      return unless can_save_safely?
      reasons = @pending_autosave_reasons.dup
      @pending_autosave_reasons.clear
      # ⚠️ UM upload, nao um por motivo.
      #
      # Isto fazia `reasons.each { save_and_upload_save_file(r) }`. Durante uma
      # batalha o `can_save_safely?` e falso, entao os motivos acumulam-se aqui
      # (battle_started, pokemon_added, item_added...) e ao voltar ao mapa subia
      # um save INTEIRO por cada um. No log de 01/09 aparecem pares exactos no
      # mesmo segundo e com a mesma base — 16:51:27, 16:51:50, 16:52:01,
      # 16:52:13, 16:52:32, 16:53:32, 16:55:19 — cada par a gastar ~50KB duas
      # vezes pelo mesmo conteudo.
      #
      # O save e um retrato do jogo inteiro: o ultimo motivo cobre todos os
      # anteriores. E a mesma razao ja escrita no throttle, que aqui faltava.
      # Prefere-se um motivo imediato se algum o for, para nao perder a urgencia.
      escolhido = reasons.find { |r| AUTOSAVE_IMEDIATO.include?(r.to_s) } || reasons.last
      save_and_upload_save_file(escolhido)
    end

    # Snapshot capturado ANTES do disconnect limpar o estado
    attr_accessor :pre_disconnect_snapshot

    def capture_pre_disconnect_snapshot!
      return if @pre_disconnect_snapshot_captured
      return unless defined?(AnilLanRework) && AnilLanRework.respond_to?(:connection)

      conn = AnilLanRework.connection
      return unless conn

      @pre_disconnect_snapshot = {
        connection:       conn,
        session_token:    (conn.instance_variable_get(:@session_token) rescue nil),
        player_id:        (self.self_internal_id.to_s rescue ""),
        frame:            (Graphics.frame_count rescue 0),
        file_path:        (SaveData::FILE_PATH.to_s rescue ""),
        is_connected:     (AnilLanRework.connected? rescue false),
        is_mp:            ((AnilLanRework.multiplayer_mode rescue false) || (AnilLanRework.online_session? rescue false)),
        map_id:           ($game_map ? $game_map.map_id : 0),
        x:                ($game_player ? $game_player.x : 0),
        y:                ($game_player ? $game_player.y : 0),
        dir:              ($game_player ? $game_player.direction : 2)
      }
      @pre_disconnect_snapshot_captured = true
      debug_log("capture_pre_disconnect_snapshot! - Snapshot capturado. is_connected=#{@pre_disconnect_snapshot[:is_connected]} is_mp=#{@pre_disconnect_snapshot[:is_mp]} file=#{@pre_disconnect_snapshot[:file_path]}")
    rescue => e
      debug_log("capture_pre_disconnect_snapshot! - Erro: #{e.class} - #{e.message}")
    end

    def clear_pre_disconnect_snapshot!
      @pre_disconnect_snapshot = nil
      @pre_disconnect_snapshot_captured = false
    end

    # ──────────────────────────────────────────────────────────────────────────
    # NOTE: download_and_overwrite_save_file foi movido para dentro de
    # apply_cloud_save_hooks para evitar que patches pós-plugin o sobrescrevam.
    # ──────────────────────────────────────────────────────────────────────────

    # ──────────────────────────────────────────────────────────────────────────
    # NOVO MÉTODO DE UPLOAD DINÂMICO E SEGURO (Background + Reentrancy Guard)
    # ──────────────────────────────────────────────────────────────────────────
    def canonical_multiplayer_save_path
      SaveData::FILE_PATH.to_s
    rescue
      ""
    end

    def last_saved_multiplayer_path
      @last_saved_multiplayer_path.to_s
    rescue
      ""
    end

    def pick_upload_source_path(preferred_path = nil)
      # canonical_multiplayer_save_path e, na pratica, o SaveData::FILE_PATH
      # dinamico: ele reavalia online x offline a cada chamada. Como este metodo
      # roda dentro da thread de upload, o caminho pode resolver para Game.rxdata
      # se a sessao cair no meio — e o save OFFLINE subiria com o id online.
      # Nenhum candidato pode ser o save offline, em nenhuma hipotese.
      offline = (DynamicSavePath.offline_path.to_s rescue "")
      candidates = []
      candidates << preferred_path.to_s unless preferred_path.to_s.empty?
      candidates << last_saved_multiplayer_path
      candidates << canonical_multiplayer_save_path
      candidates.uniq.each do |path|
        next if path.to_s.empty?
        next if !offline.empty? && path.to_s == offline
        return path if File.exist?(path)
      end
      fallback = canonical_multiplayer_save_path.to_s
      # String vazia faz o chamador pular o upload (ele testa File.exist?).
      return "" if !offline.empty? && fallback == offline
      fallback
    end

    # =========================================================================
    # GUARDA DE DONO DO SAVE  (2026-08-01)
    #
    # O PROBLEMA QUE ISTO PARA
    #
    # O caminho do save vem do DynamicSavePath, que resolve o ficheiro a partir
    # do `multiplayer_player.txt` — um ficheiro RELATIVO a pasta do jogo, logo
    # PARTILHADO quando se abrem duas instancias da mesma pasta (o que se faz
    # para testar coop). O slot da nuvem, esse, vem do jogo CARREGADO
    # (self_internal_id -> $player.name + $PokemonGlobal.online_id).
    #
    # Sao duas fontes diferentes, e quando divergem o cliente le os bytes de um
    # jogador e envia-os, com credenciais validas, para o slot do outro. Foi
    # assim que o save do 'wallace' passou a conter o jogo da 'gaby': o servidor
    # aceita porque o player_id e legitimo, e nem consegue verificar o conteudo
    # (nao tem as classes de Pokemon — e a razao de o battle worker viver num
    # processo a parte).
    #
    # COMO DECIDE
    #
    # Compara o NOME DO FICHEIRO com a identidade do jogo carregado. E O(1), sem
    # abrir nem desserializar o save — estes caminhos correm a cada save_hook,
    # varias vezes por minuto, e nao podem pagar um Marshal.load.
    #
    # FALHA SEMPRE PARA O LADO DE DEIXAR PASSAR
    #
    # So bloqueia quando consegue provar que o ficheiro e de OUTRO jogador: sem
    # $player, sem online_id, nome de ficheiro que nao tem forma de id (o
    # Game.rxdata offline, por exemplo) ou qualquer excecao -> deixa passar. Um
    # save perdido por bloqueio a mais seria pior do que o problema original.
    # =========================================================================
    def anil_save_de_outro_jogador?(path)
      return false if path.to_s.empty?
      base = File.basename(path.to_s, ".rxdata").to_s.downcase
      # Sem forma de "<nome>-<hash6>" nao da para concluir nada (Game.rxdata,
      # "Partida 4", ficheiros temporarios...).
      return false unless base =~ /\A[a-z0-9][a-z0-9_-]*-[a-z0-9]{6}\z/

      esperado = (canonical_player_id.to_s.downcase rescue "")
      return false if esperado.empty?
      # Identidade ainda a formar-se (sem jogo carregado): nao bloqueia.
      return false unless esperado =~ /\A[a-z0-9][a-z0-9_-]*-[a-z0-9]{6}\z/
      return false if base == esperado

      debug_log("[SAVE_GUARD] RECUSADO: ficheiro #{base.inspect} nao pertence a sessao carregada (#{esperado.inspect}). " \
                "player=#{((defined?($player) && $player) ? $player.name : nil).inspect} " \
                "cfg=#{(read_cfg('multiplayer_player.txt', 'id', '') rescue '').inspect}")
      true
    rescue => e
      debug_log("[SAVE_GUARD] verificacao falhou (#{e.class}: #{e.message}) — a deixar passar")
      false
    end

    def sync_multiplayer_save_alias!(written_path)
      # Desativado para evitar vazamento do save online para os slots locais ("Partida X")
      return
    end

    def upload_active_save_file(reason = "", preferred_path = nil)
#region debug-point cloud-save-upload-client
      debug_log("upload_active_save_file chamada (reason: #{reason})")
      
      unless defined?(AnilLanRework) && AnilLanRework.connected? && AnilLanRework.connection
        debug_log("upload_active_save_file cancelada - sem conexão ativa")
        return false
      end

      unless defined?(AnilLanRework) && AnilLanRework.online_session?
        debug_log("upload_active_save_file cancelada - nao e uma sessao online (VPS)")
        return false
      end

      # Evita upload se o nome atual do jogador for placeholder
      if defined?(AnilLanRework) && AnilLanRework.respond_to?(:placeholder_player_name?) &&
         AnilLanRework.placeholder_player_name?((defined?($player) && $player) ? $player.name.to_s : "")
        debug_log("upload_active_save_file cancelada - o nome atual do jogador é placeholder")
        return false
      end
      
      # Roda assincronamente para não interferir na taxa de quadros (FPS) do jogo
      Thread.new do
        begin
          debug_log("upload_active_save_file - Iniciando background thread")
          # Aguarda a gravação no disco terminar caso haja salvamento assíncrono em andamento
          AnilAsyncSave.wait_for_save if defined?(AnilAsyncSave)
          
          filepath = pick_upload_source_path(preferred_path)
          # GUARDA: este e o caminho que le um ficheiro JA existente e o envia.
          # E o unico dos tres onde os bytes podem ser de outro jogador.
          if anil_save_de_outro_jogador?(filepath)
            debug_log("upload_active_save_file ABORTADO: #{filepath.inspect} nao e o save desta sessao (reason=#{reason})")
            return
          end
          runtime_pid = (self.self_internal_id.to_s rescue "")
          cfg_pid = (read_cfg("multiplayer_player.txt", "id", "") rescue "")
          player_name = (defined?($player) && $player) ? $player.name.to_s : ""
          online_id = (defined?($PokemonGlobal) && $PokemonGlobal && $PokemonGlobal.respond_to?(:online_id) ? $PokemonGlobal.online_id.to_s : "")
          debug_log("upload_active_save_file - filepath=#{filepath.inspect} runtime_pid=#{runtime_pid.inspect} cfg_pid=#{cfg_pid.inspect} player_name=#{player_name.inspect} online_id=#{online_id.inspect}")
          if File.exist?(filepath)
            binary_data = File.open(filepath, "rb") { |f| f.read } rescue nil
            if binary_data && binary_data.bytesize > 0
              encoded_data, save_comprimido = AnilSaveZip.empacotar(binary_data)
              
              pid = runtime_pid
              debug_log("upload_active_save_file - Lidos #{binary_data.bytesize} bytes para player_id=#{pid}")
              
              packet = {
                "type"      => "upload_save_file",
                "session"   => @connection.instance_variable_get(:@session_token),
                "sender_id" => pid,
                "frame"     => (Graphics.frame_count rescue 0),
                "player_id" => pid,
                "save_data" => encoded_data,
                "reason"    => reason,
                "mtime"     => (File.mtime(filepath).to_i rescue 0),
                "map_id"    => ($game_map ? $game_map.map_id : 0),
                "x"         => ($game_player ? $game_player.x : 0),
                "y"         => ($game_player ? $game_player.y : 0),
                "dir"       => ($game_player ? $game_player.direction : 2),
                # Em que ponto da sequencia do servidor este aparelho esta.
                # 0 = nunca sincronizou; o servidor trata como "nao sei".
                "save_version" => (AnilSaveVersao.ler rescue 0),
                # O testemunho da linhagem. Vazio = ainda nao semeado; o
                # servidor semeia no primeiro upload de cada conta.
                "save_token" => (AnilSaveToken.ler rescue ""),
                "save_gzip"    => (save_comprimido == true),
                # So o que mudou desde o ultimo envio. nil = manda inteiro.
                "save_sections" => (AnilSaveSecoes.seccoes_alteradas(binary_data, AnilSaveVersao.ler) rescue nil),
                # De que versao estas seccoes partem. O servidor recusa a fusao
                # se nao for a dele — colar diferencas sobre outra base daria um
                # save incoerente.
                "save_sections_base" => (AnilSaveSecoes.base rescue 0)
              }

              AnilSaveSecoes.aliviar!(packet) rescue nil
              @connection.send_packet("upload_save_file", packet) rescue nil
              @connection.flush_batch rescue nil
              
              debug_log("upload_active_save_file - Pacote de upload de save enviado via TCP")
            else
              debug_log("upload_active_save_file - Erro: Arquivo de save vazio ou corrompido.")
            end
          else
            debug_log("upload_active_save_file - Erro: Arquivo de save não encontrado em #{filepath}.")
          end
        rescue => e
          debug_log("upload_active_save_file - Falha no upload automático: #{e.class} - #{e.message}")
        end
      end
      true
#endregion debug-point cloud-save-upload-client
    end

    # ──────────────────────────────────────────────────────────────────────────
    # PIPELINE DE SALVAMENTO E UPLOAD 100% SÍNCRONO (Sem Threads/Race Conditions)
    # Fundamental para saídas de jogo (at_exit) e desconexões (disconnect).
    # ──────────────────────────────────────────────────────────────────────────
    def save_and_upload_synchronously(reason = "")
      debug_log("save_and_upload_synchronously chamada (reason: #{reason})")
      # ⚠️ Trava dura: o servidor ja disse que este save esta atrasado.
      # Enviar agora sobrepunha o save BOM que esta na nuvem — foi assim que a
      # troca da lorena foi desfeita. Ver AnilSaveAtrasado.
      if defined?(AnilSaveAtrasado) && AnilSaveAtrasado.bloqueado?
        debug_log("upload BLOQUEADO: save local atrasado (razao: #{reason})")
        return false
      end
      
      unless defined?(AnilLanRework) && AnilLanRework.connected? && AnilLanRework.connection
        debug_log("save_and_upload_synchronously cancelada - sem conexão ativa")
        return false
      end

      unless defined?(AnilLanRework) && AnilLanRework.online_session?
        debug_log("save_and_upload_synchronously cancelada - nao e uma sessao online (VPS)")
        return false
      end

      if defined?(AnilLanRework) && AnilLanRework.respond_to?(:placeholder_player_name?) &&
         AnilLanRework.placeholder_player_name?((defined?($player) && $player) ? $player.name.to_s : "")
        debug_log("save_and_upload_synchronously cancelada - nome placeholder")
        return false
      end

      file_path = SaveData::FILE_PATH.to_s
      debug_log("save_and_upload_synchronously - file_path: #{file_path}")

      # GUARDA: aqui os bytes sao desta sessao, mas o CAMINHO pode ser o do
      # outro jogador (duas instancias, um so multiplayer_player.txt). Gravar
      # apagava o save local dele; e o upload seguiria com o pid desta sessao.
      # Abortar e a unica saida segura — redirecionar seria adivinhar.
      if anil_save_de_outro_jogador?(file_path)
        debug_log("save_and_upload_synchronously ABORTADO: #{file_path.inspect} e o save de outro jogador (reason=#{reason})")
        return false
      end

      # 1. Compila e serializa no main thread (ultra rápido)
      serialized_str = nil
      begin
        AnilAsyncSave.wait_for_save if defined?(AnilAsyncSave)
        save_data = SaveData.compile_save_hash
        serialized_str = Marshal.dump(save_data)
      rescue => e
        debug_log("save_and_upload_synchronously - Falha ao compilar/serializar save: #{e.class}: #{e.message}")
      end

      # 2. Ativa o blackout gráfico no main thread imediatamente (cria o overlay mas sem fazer o flush síncrono longo)
      blackout_active = false
      if defined?(antighost_paint_black_and_flush!)
        antighost_paint_black_and_flush!(0) rescue nil
        blackout_active = true
      end

      # 3. Cria a thread para gravação física em disco e upload
      save_thread = Thread.new do
        # Gravação local
        begin
          if serialized_str
            temp_path = file_path + ".tmp"
            bak_path  = file_path + ".bak"
            File.open(temp_path, "wb") { |f| f.write(serialized_str) }
            File.delete(bak_path) rescue nil
            File.rename(file_path, bak_path) rescue nil
            File.rename(temp_path, file_path)
            debug_log("save_and_upload_synchronously - Gravação física em thread concluída.")
          end
        rescue => e
          debug_log("save_and_upload_synchronously - Falha na gravação física: #{e.class}: #{e.message}")
        end

        # Upload para a nuvem
        begin
          if File.exist?(file_path)
            binary_data = File.open(file_path, "rb") { |f| f.read }
            if binary_data && binary_data.bytesize > 0
              encoded_data, save_comprimido = AnilSaveZip.empacotar(binary_data)
              pid = self.self_internal_id.to_s
              debug_log("save_and_upload_synchronously - #{binary_data.bytesize} bytes, player=#{pid}")

              packet = {
                "type"      => "upload_save_file",
                "session"   => @connection.instance_variable_get(:@session_token),
                "sender_id" => pid,
                "frame"     => (Graphics.frame_count rescue 0),
                "player_id" => pid,
                "save_data" => encoded_data,
                "reason"    => reason,
                "mtime"     => (File.mtime(file_path).to_i rescue 0),
                "map_id"    => ($game_map ? $game_map.map_id : 0),
                "x"         => ($game_player ? $game_player.x : 0),
                "y"         => ($game_player ? $game_player.y : 0),
                "dir"       => ($game_player ? $game_player.direction : 2),
                # Em que ponto da sequencia do servidor este aparelho esta.
                # 0 = nunca sincronizou; o servidor trata como "nao sei".
                "save_version" => (AnilSaveVersao.ler rescue 0),
                # O testemunho da linhagem. Vazio = ainda nao semeado; o
                # servidor semeia no primeiro upload de cada conta.
                "save_token" => (AnilSaveToken.ler rescue ""),
                "save_gzip"    => (save_comprimido == true),
                # So o que mudou desde o ultimo envio. nil = manda inteiro.
                "save_sections" => (AnilSaveSecoes.seccoes_alteradas(binary_data, AnilSaveVersao.ler) rescue nil),
                # De que versao estas seccoes partem. O servidor recusa a fusao
                # se nao for a dele — colar diferencas sobre outra base daria um
                # save incoerente.
                "save_sections_base" => (AnilSaveSecoes.base rescue 0)
              }

              AnilSaveSecoes.aliviar!(packet) rescue nil
              @connection.last_upload_save_ack = nil if @connection.respond_to?(:last_upload_save_ack=)
              @connection.send_packet("upload_save_file", packet) rescue nil
              @connection.flush_batch rescue nil
              debug_log("save_and_upload_synchronously - Pacote enviado. Aguardando ACK...")

              ack_received = false
              start_t = Time.now.to_f
              timeout_seconds = 2.5
              while Time.now.to_f - start_t < timeout_seconds
                break unless @connection.connected?
                @connection.tick rescue nil
                if @connection.respond_to?(:last_upload_save_ack) && @connection.last_upload_save_ack
                  ack_received = true
                  @connection.last_upload_save_ack = nil
                  break
                end
                sleep(0.02)
              end

              debug_log(ack_received ?
                "save_and_upload_synchronously - ACK recebido! Save em nuvem OK." :
                "save_and_upload_synchronously - Timeout #{timeout_seconds}s sem ACK.")
            end
          end
        rescue => e
          debug_log("save_and_upload_synchronously - Erro no upload: #{e.class} - #{e.message}")
        end
      end

      # 4. Loop de pumping de gráficos no main thread para processar o flush de frames do blackout de forma assíncrona
      is_joiplay = false
      if respond_to?(:antighost_joiplay?)
        is_joiplay = antighost_joiplay?
      elsif defined?(System) && System.respond_to?(:platform) && System.platform.to_s =~ /android/i
        is_joiplay = true
      end
      min_frames = is_joiplay ? 200 : 4
      frame_count = 0
      begin
        while save_thread.alive? || frame_count < min_frames
          Graphics.update rescue nil
          frame_count += 1
          sleep(0.01)
        end
      ensure
        save_thread.join rescue nil
        $antighost_save_blackout_flushed = true
        if blackout_active && defined?(antighost_dispose_blackout_sprite!)
          antighost_dispose_blackout_sprite! rescue nil
        end
      end
      true
    end

    def self.save_and_upload_synchronously_from_snapshot(snap, reason = "")
      return false unless defined?(AnilLanRework) && AnilLanRework.online_session?
      debug_log("save_and_upload_synchronously_from_snapshot chamada (reason: #{reason})")

      conn      = snap[:connection]
      file_path = snap[:file_path]
      pid       = snap[:player_id]

      unless conn && conn.respond_to?(:connected?) && conn.connected?
        debug_log("save_and_upload_synchronously_from_snapshot - conexão do snapshot já fechada")
        return false
      end

      # GUARDA (mesma razao dos outros dois pontos). Receptor explicito: este
      # metodo e `def self.` dentro do `class << self`, entao uma chamada nua
      # nao chegaria ao metodo do modulo.
      if (AnilLanRework.anil_save_de_outro_jogador?(file_path) rescue false)
        debug_log("save_and_upload_synchronously_from_snapshot ABORTADO: #{file_path.inspect} e o save de outro jogador (reason=#{reason})")
        return false
      end

      # 1. Compila e serializa no main thread (ultra rápido)
      serialized_str = nil
      begin
        AnilAsyncSave.wait_for_save if defined?(AnilAsyncSave)
        save_data = SaveData.compile_save_hash
        serialized_str = Marshal.dump(save_data)
      rescue => e
        debug_log("save_and_upload_synchronously_from_snapshot - Falha ao compilar/serializar save: #{e.class}: #{e.message}")
      end

      # 2. Ativa o blackout gráfico no main thread imediatamente (cria o overlay mas sem fazer o flush síncrono longo)
      blackout_active = false
      if defined?(antighost_paint_black_and_flush!)
        antighost_paint_black_and_flush!(0) rescue nil
        blackout_active = true
      end

      # 3. Cria a thread para gravação física em disco e upload
      save_thread = Thread.new do
        begin
          if serialized_str
            temp_path      = file_path + ".tmp"
            bak_path       = file_path + ".bak"
            File.open(temp_path, "wb") { |f| f.write(serialized_str) }
            File.delete(bak_path) rescue nil
            File.rename(file_path, bak_path) rescue nil
            File.rename(temp_path, file_path)
            debug_log("save_and_upload_synchronously_from_snapshot - Gravação local OK.")
          end
        rescue => e
          debug_log("save_and_upload_synchronously_from_snapshot - Falha na gravação local: #{e.class}: #{e.message}")
        end

        begin
          if File.exist?(file_path)
            binary_data = File.open(file_path, "rb") { |f| f.read }
            if binary_data && binary_data.bytesize > 0
              encoded_data, save_comprimido = AnilSaveZip.empacotar(binary_data)
              debug_log("save_and_upload_synchronously_from_snapshot - #{binary_data.bytesize} bytes prontos para upload. pid=#{pid}")

              packet = {
                "type"      => "upload_save_file",
                "session"   => snap[:session_token],
                "sender_id" => pid,
                "frame"     => snap[:frame],
                "player_id" => pid,
                "save_data" => encoded_data,
                "reason"    => reason,
                "mtime"     => (File.mtime(file_path).to_i rescue 0),
                "map_id"    => snap[:map_id],
                "x"         => snap[:x],
                "y"         => snap[:y],
                "dir"       => snap[:dir],
                "save_version" => (AnilSaveVersao.ler rescue 0),
                # O testemunho da linhagem. Vazio = ainda nao semeado; o
                # servidor semeia no primeiro upload de cada conta.
                "save_token" => (AnilSaveToken.ler rescue ""),
                "save_gzip"    => (save_comprimido == true),
                # So o que mudou desde o ultimo envio. nil = manda inteiro.
                "save_sections" => (AnilSaveSecoes.seccoes_alteradas(binary_data, AnilSaveVersao.ler) rescue nil),
                # De que versao estas seccoes partem. O servidor recusa a fusao
                # se nao for a dele — colar diferencas sobre outra base daria um
                # save incoerente.
                "save_sections_base" => (AnilSaveSecoes.base rescue 0)
              }

              AnilSaveSecoes.aliviar!(packet) rescue nil
              conn.last_upload_save_ack = nil if conn.respond_to?(:last_upload_save_ack=)
              conn.send_packet("upload_save_file", packet) rescue nil
              conn.flush_batch rescue nil
              debug_log("save_and_upload_synchronously_from_snapshot - Pacote enviado. Aguardando ACK...")

              ack_received = false
              start_t      = Time.now.to_f
              timeout_sec  = 2.5

              while Time.now.to_f - start_t < timeout_sec
                break unless conn.connected?
                conn.tick rescue nil
                if conn.respond_to?(:last_upload_save_ack) && conn.last_upload_save_ack
                  ack_received = true
                  conn.last_upload_save_ack = nil
                  break
                end
                sleep(0.02)
              end

              debug_log(ack_received ?
                "save_and_upload_synchronously_from_snapshot - ACK recebido! Cloud save OK." :
                "save_and_upload_synchronously_from_snapshot - Timeout #{timeout_sec}s sem ACK.")
            end
          end
        rescue => e
          debug_log("save_and_upload_synchronously_from_snapshot - Erro no upload: #{e.class} - #{e.message}")
        end
      end

      # 4. Loop de pumping de gráficos no main thread para processar o flush de frames do blackout de forma assíncrona
      is_joiplay = false
      if respond_to?(:antighost_joiplay?)
        is_joiplay = antighost_joiplay?
      elsif defined?(System) && System.respond_to?(:platform) && System.platform.to_s =~ /android/i
        is_joiplay = true
      end
      min_frames = is_joiplay ? 12 : 4
      frame_count = 0
      begin
        while save_thread.alive? || frame_count < min_frames
          Graphics.update rescue nil
          frame_count += 1
          sleep(0.01)
        end
      ensure
        save_thread.join rescue nil
        $antighost_save_blackout_flushed = true
        if blackout_active && defined?(antighost_dispose_blackout_sprite!)
          # Se o jogo estiver fechando ($scene é nulo), mantém a tela preta e não destrói o sprite do blackout
          unless $scene.nil?
            antighost_dispose_blackout_sprite! rescue nil
          end
        end
      end
      true
    rescue => e
      debug_log("save_and_upload_synchronously_from_snapshot - Erro geral: #{e.class} - #{e.message}")
      false
    end

    def trigger_instant_silent_connect
      unless defined?(AnilLanRework) && AnilLanRework.respond_to?(:multiplayer_mode) && AnilLanRework.multiplayer_mode
        return false
      end
      
      AnilLanRework.update_player_config rescue nil
      player_id   = AnilLanRework.read_cfg("multiplayer_player.txt", "id", "")
      if player_id.empty?
        player_id = (self.self_internal_id.to_s rescue "jogador#{rand(9000) + 1000}")
      end
      player_name = $player.name.to_s rescue "Treinador"
      player_char = $game_player.character_name.to_s rescue "trainer_m"
      target_ip   = (AnilLanRework.respond_to?(:dedicated_server_ip) ? AnilLanRework.dedicated_server_ip : "127.0.0.1")
      
      ok = false
      begin
        debug_log("trigger_instant_silent_connect - Iniciando conexao instantanea silenciosa para #{player_id}...")
        ok = AnilLanRework.connect(target_ip, player_id, player_name, player_char, false)
        debug_log("trigger_instant_silent_connect - Conexao: #{ok ? 'SUCESSO' : 'FALHA'}")
      rescue => e
        debug_log("trigger_instant_silent_connect - Erro: #{e.class}: #{e.message}")
      end
      ok
    end

    # ──────────────────────────────────────────────────────────────────────────
    # CORE HOOK ENFORCER: Garante que os hooks rodem sempre DEPOIS de todos
    # os plugins e patches pós-plugins (evitando sobrescritas de inicialização).
    # ──────────────────────────────────────────────────────────────────────────
    def apply_cloud_save_hooks
      debug_log("apply_cloud_save_hooks - Iniciando injeção dinâmica dos ganchos por cima do pós-plugin...")
      
      class << self
        # 1. Sobrescreve save_and_upload_save_file com a nossa lógica robusta
        if !method_defined?(:anil_cloud_orig_save_and_upload)
          alias_method :anil_cloud_orig_save_and_upload, :save_and_upload_save_file rescue nil
        end

        # 5. Sobrescreve download_and_overwrite_save_file com a nossa lógica robusta (vacina contra sobrescritas do pós-plugin)
        if !method_defined?(:anil_cloud_orig_download_save)
          alias_method :anil_cloud_orig_download_save, :download_and_overwrite_save_file rescue nil
        end

        def download_and_overwrite_save_file
          raw_cfg_id = read_cfg("multiplayer_player.txt", "id", "") rescue ""
          player_id = raw_cfg_id.to_s
          if defined?(AnilLanRework)
            if AnilLanRework.respond_to?(:normalized_player_id)
              player_id = AnilLanRework.normalized_player_id(raw_cfg_id) rescue player_id
            elsif AnilLanRework.respond_to?(:get_player_id)
              runtime_id = AnilLanRework.get_player_id rescue ""
              player_id = runtime_id unless runtime_id.to_s.empty?
            end
          end
          
          # Força a temporária ativação do multiplayer_mode para passar no guard block nativo
          was_mode = @multiplayer_mode
          @multiplayer_mode = true
          
          begin
            if defined?(AnilLanRework) &&
               defined?($player) && $player &&
               AnilLanRework.respond_to?(:placeholder_player_name?) &&
               AnilLanRework.placeholder_player_name?($player.name.to_s)
              debug_log("download_and_overwrite_save_file - Download ignorado: nome placeholder/new game e cfg_bruto=#{raw_cfg_id.inspect}")
              return
            end
            if player_id.empty? || player_id !~ /\A[a-z0-9][a-z0-9_-]*-[a-z0-9]{6}\z/i
              debug_log("download_and_overwrite_save_file - Download ignorado: player_id ainda nao canonico (player_id=#{player_id.inspect}, cfg_bruto=#{raw_cfg_id.inspect})")
              return
            end
            if player_id.empty?
              debug_log("download_and_overwrite_save_file - Player ID vazio no config, usando fallback.")
              anil_cloud_orig_download_save if respond_to?(:anil_cloud_orig_download_save)
            else
              target_ip = (defined?(AnilLanRework) && AnilLanRework.respond_to?(:dedicated_server_ip) ? AnilLanRework.dedicated_server_ip : "127.0.0.1")
              debug_log("download_and_overwrite_save_file - Baixando save para player_id=#{player_id} (cfg_bruto=#{raw_cfg_id.inspect}) de #{target_ip}...")
              AnilLanRework.marcar_download_save(:tentando)
              begin
                socket = nil
                thread = Thread.new do
                  begin
                    socket = TCPSocket.new(target_ip, 7654)
                  rescue => e
                    AnilLanRework.log("Download save socket connect error: #{e.class}: #{e.message}") rescue nil
                  end
                end

                start_time = Time.now.to_f
                timeout_limit = 1.5
                while thread.alive? && (Time.now.to_f - start_time < timeout_limit)
                  Graphics.update rescue nil
                  Input.update rescue nil
                  sleep(0.01)
                end

                if thread.alive?
                  thread.kill rescue nil
                end

                raise "servidor offline ou timeout" unless socket

                req = {
                  "type" => "download_save_file",
                  "player_id" => player_id,
                  "save_version" => (AnilSaveVersao.ler rescue 0),
                  "save_token" => (AnilSaveToken.ler rescue ""),
                  # Anuncia que este cliente sabe descomprimir. Servidor antigo
                  # ignora e manda como sempre.
                  "accepts_gzip" => true
                }
                payload = AnilLanPureJSON.encode(req)
                socket.write(payload + "\n")
                socket.flush rescue nil
                
                # Leitura robusta com buffer acumulado (Joiplay/Android compatível)
                buffer = +""
                response_data = nil
                deadline = Time.now.to_f + 15.0  # 15 segundos de timeout total

                begin
                  while Time.now.to_f < deadline
                    # Espera até 5.0 segundos por legibilidade no socket antes de ler
                    rs = IO.select([socket], nil, nil, 5.0)
                    if rs
                      chunk = socket.recv(16384)
                      if chunk.nil? || chunk.empty?
                        break # EOF
                      end
                      buffer << chunk.force_encoding("UTF-8")
                      if (idx = buffer.index("\n"))
                        response_data = buffer.slice!(0, idx + 1).strip
                        break
                      end
                    else
                      # Timeout de 5s sem resposta/dados adicionais
                      break
                    end
                  end
                rescue => e
                  # Silencia erros
                end
                response_data = buffer.strip if response_data.nil? && !buffer.empty?

                socket.close rescue nil
                
                if response_data
                  packet = AnilLanPureJSON.decode(response_data)
                  # Quem acabou de receber o estado do servidor passa a ser a
                  # linhagem valida: guarda-se o testemunho que veio com ele.
                  AnilSaveToken.gravar(packet["save_token"]) if packet && !packet["save_token"].to_s.empty?
                  if packet && packet["type"] == "save_file_data" && packet["found"] == true &&
                     packet["up_to_date"] == true
                    # Nada foi enviado porque este aparelho ja tem a versao
                    # actual. O save local fica como esta — e correcto por
                    # definicao, e poupa o download inteiro.
                    AnilSaveVersao.gravar(packet["version"])
                    AnilLanRework.marcar_download_save(:ok, 0, "ja em dia (v#{packet["version"]})")
                  elsif packet && packet["type"] == "save_file_data" && packet["found"] == true
                    server_mtime = (packet["mtime"] || packet["save_mtime"]).to_i rescue 0
                    encoded_save = packet["save_data"]
                    binary_save = AnilSaveZip.desempacotar(encoded_save, packet["save_gzip"] == true)
                    
                    mp_path = SaveData::FILE_PATH.to_s
                    
                    # Valida se o save do servidor está íntegro e legível (não corrompido)
                    server_save_valid = false
                    begin
                      if binary_save && binary_save.bytesize > 100
                        test_parsed = Marshal.load(binary_save) rescue nil
                        if test_parsed.is_a?(Hash)
                          server_save_valid = true
                        end
                      end
                    rescue => e
                      server_save_valid = false
                    end
                    
                    if server_save_valid
                      File.open(mp_path, "wb") { |f| f.write(binary_save) }
                      if server_mtime > 0
                        t = Time.at(server_mtime)
                        File.utime(t, t, mp_path) rescue nil
                      end
                      debug_log("download_and_overwrite_save_file - Reposto save do servidor (Superior). Tamanho: #{binary_save.bytesize} bytes.")
                      AnilSaveVersao.gravar(packet["version"]) if packet["version"].to_i > 0
                      AnilLanRework.marcar_download_save(:ok, binary_save.bytesize)
                    else
                      debug_log("download_and_overwrite_save_file - Save do servidor corrompido ou invalido. Mantido save local.")
                      AnilLanRework.marcar_download_save(:corrompido)
                    end
                  else
                    debug_log("download_and_overwrite_save_file - Nenhum save na nuvem encontrado para #{player_id}.")
                    AnilLanRework.marcar_download_save(:sem_save)
                  end
                end
              rescue => e
                debug_log("download_and_overwrite_save_file - Erro no download do save: #{e.message}")
                AnilLanRework.marcar_download_save(:falha, 0, "#{e.class}: #{e.message}")
              end
            end
          ensure
            @multiplayer_mode = was_mode
          end
        end

        def save_and_upload_save_file(reason = "")
          debug_log("save_and_upload_save_file interceptado (razão: #{reason})")
          # ⚠️ Trava dura: o servidor ja disse que este save esta atrasado.
          # Enviar agora sobrepunha o save BOM que esta na nuvem — foi assim que a
          # troca da lorena foi desfeita. Ver AnilSaveAtrasado.
          if defined?(AnilSaveAtrasado) && AnilSaveAtrasado.bloqueado?
            debug_log("upload BLOQUEADO: save local atrasado (razao: #{reason})")
            return false
          end

          if ["game_exit", "disconnect"].include?(reason)
            unless AnilLanRework.can_save_safely?
              debug_log("save_and_upload_save_file - Salve ignorado: estado instável ou crítico detectado (razão: #{reason})")
              return false
            end
            return save_and_upload_synchronously(reason)
          end

          # Agrupa os motivos barulhentos numa janela (ver autosave_throttle_segura?).
          # Vem DEPOIS do game_exit/disconnect de proposito: esses nunca esperam.
          if AnilLanRework.autosave_throttle_segura?(reason)
            debug_log("save_and_upload_save_file - Salve agrupado pelo throttle (razão: #{reason})")
            return false
          end

          # NOVO: para qualquer outro motivo (item recebido, loja, batalha, etc.),
          # nunca serializa o jogo enquanto houver um evento/mensagem em execução,
          # o jogador estiver em batalha/transição, ou a cena não for o mapa.
          # Em vez de descartar o save, ele é adiado e disparado assim que for seguro.
          unless AnilLanRework.can_save_safely?
            debug_log("save_and_upload_save_file - Salve adiado (estado inseguro), reagendado (razão: #{reason})")
            AnilLanRework.queue_deferred_autosave!(reason)
            return false
          end

          if respond_to?(:anil_cloud_orig_save_and_upload)
            anil_cloud_orig_save_and_upload(reason)
          else
            save_and_upload_synchronously(reason)
          end
        end

        # 2. Sobrescreve disconnect para rodar o upload síncrono garantido antes do close
        if !method_defined?(:anil_cloud_orig_disconnect)
          alias_method :anil_cloud_orig_disconnect, :disconnect rescue nil
        end

        def disconnect(save = true)
          debug_log("disconnect interceptado (save: #{save})")

          # Captura o estado AGORA, antes de qualquer limpeza
          AnilLanRework.capture_pre_disconnect_snapshot! rescue nil

          snap = AnilLanRework.pre_disconnect_snapshot
          should_upload = save && snap && snap[:is_connected] && snap[:is_mp] && (AnilLanRework.online_session? rescue false)
          
          if should_upload && !AnilLanRework.can_save_safely?
            debug_log("disconnect - Ignorado save/upload: estado instável ou crítico detectado")
            should_upload = false
          end

          debug_log("disconnect - should_upload=#{should_upload} snap=#{snap ? 'presente' : 'nil'}")

          if should_upload
            begin
              AnilLanRework.save_and_upload_synchronously_from_snapshot(snap, "disconnect_backup")
            rescue => e
              debug_log("disconnect - ERRO no upload: #{e.class} - #{e.message}")
            end
          end

          AnilLanRework.clear_pre_disconnect_snapshot! rescue nil
          anil_cloud_orig_disconnect(false)
        end

        # 4. Sobrescreve resolve_online_id para invalidar hashes não-hexadecimais herdados (como WALLAC, JOIPLA)
        def resolve_online_id
          if defined?($PokemonGlobal) && $PokemonGlobal
            unless $PokemonGlobal.respond_to?(:online_id)
              class << $PokemonGlobal
                attr_accessor :online_id
              end
            end

            oid = $PokemonGlobal.online_id.to_s
            # EXTREMAMENTE IMPORTANTE: Usa o regex de hexadecimal estrito \A[A-F0-9]{6}\z/i
            # Isso invalida automaticamente nomes de PC salvos anteriormente (como WALLAC, JOIPLA)
            if oid.empty? || oid == "A78YUA" || oid.downcase.include?("localhost") || !(oid =~ /\A[A-F0-9]{6}\z/i)
              # Deriva do hash de máquina canônico do save/local
              $PokemonGlobal.online_id = persistent_machine_id.upcase
            else
              $PokemonGlobal.online_id = oid[0, 6].upcase
            end

            if defined?($player) && $player
              unless $player.respond_to?(:online_id)
                class << $player
                  attr_accessor :online_id
                end
              end
              $player.online_id = $PokemonGlobal.online_id.to_s rescue nil
            end

            return $PokemonGlobal.online_id.to_s
          end

          persistent_machine_id.upcase
        end
      end

      # 3. Hook universal no SaveData.save_to_file
      if defined?(SaveData)
        class << SaveData
          if !method_defined?(:anil_cloud_original_save_to_file)
            alias_method :anil_cloud_original_save_to_file, :save_to_file rescue nil
            
            def save_to_file(file_path)
#region debug-point cloud-save-save-hook
              AnilLanRework.capture_pre_disconnect_snapshot! rescue nil
              AnilLanRework.debug_log("SaveData.save_to_file interceptado. file_path: #{file_path}") rescue nil
              
              # Executa a gravação local nativa (incluindo AsyncSave se presente)
              anil_cloud_original_save_to_file(file_path)
              
              # Dispara o upload assíncrono em background
              is_connected = defined?(AnilLanRework) && AnilLanRework.connected?
              is_mp = defined?(AnilLanRework) && (AnilLanRework.multiplayer_mode || AnilLanRework.online_session?)
              
              AnilLanRework.debug_log("SaveData.save_to_file - is_connected: #{is_connected}, is_mp: #{is_mp}") rescue nil
              begin
                resolved_file_path = SaveData::FILE_PATH.to_s
                cfg_pid = AnilLanRework.read_cfg("multiplayer_player.txt", "id", "") rescue ""
                runtime_pid = AnilLanRework.self_internal_id.to_s rescue ""
                AnilLanRework.debug_log("SaveData.save_to_file - resolved_file_path=#{resolved_file_path.inspect} cfg_pid=#{cfg_pid.inspect} runtime_pid=#{runtime_pid.inspect}") rescue nil
              rescue
              end
              
                AnilLanRework.sync_multiplayer_save_alias!(file_path.to_s) if is_mp
                if is_connected && is_mp
                unless Thread.current[:cloud_upload_in_progress]
                  Thread.current[:cloud_upload_in_progress] = true
                  begin
                    AnilLanRework.upload_active_save_file("save_hook", file_path.to_s)
                  ensure
                    Thread.current[:cloud_upload_in_progress] = false
                  end
                else
                  AnilLanRework.debug_log("SaveData.save_to_file - Ignorado upload recursivo no mesmo thread.") rescue nil
                end
              end
#endregion debug-point cloud-save-save-hook
            end
          end

          if !method_defined?(:anil_cloud_original_load_all_values)
            alias_method :anil_cloud_original_load_all_values, :load_all_values rescue nil

            def load_all_values(save_data)
              # Força o recarregamento do :pokemon_system para garantir que as opções (velocidade do texto, etc.)
              # sejam lidas do save específico que está sendo carregado, em vez de manter o cache do boot (save offline).
              if defined?(@values) && @values
                @values.each do |val|
                  if val.id == :pokemon_system
                    val.mark_as_unloaded rescue nil
                  end
                end rescue nil
              end

              # Limpa os caches internos do MessageConfig para que reavalie o novo $PokemonSystem
              if defined?(MessageConfig)
                MessageConfig.class_variable_set(:@@textSpeed, nil) rescue nil
                MessageConfig.class_variable_set(:@@systemFrame, nil) rescue nil
                MessageConfig.class_variable_set(:@@defaultTextSkin, nil) rescue nil
              end

              # Executa a carga original
              anil_cloud_original_load_all_values(save_data)
            end
          end
        end
      end
      
      debug_log("apply_cloud_save_hooks - Ganchos dinâmicos aplicados com sucesso absoluto!")
    end
  end
end

# ──────────────────────────────────────────────────────────────────────────────
# HOOK NA INICIALIZAÇÃO DE POST-PLUGINS DO CIENTE
# Intercepta apply_post_plugin_patches para reinjetar nossos hooks por cima!
# ──────────────────────────────────────────────────────────────────────────────
module AnilLanRework
  class << self
    if !method_defined?(:anil_cloud_orig_apply_post_plugin_patches)
      alias_method :anil_cloud_orig_apply_post_plugin_patches, :apply_post_plugin_patches rescue nil
    end

    def apply_post_plugin_patches
      # 1. Executa a injeção nativa pós-plugin
      if respond_to?(:anil_cloud_orig_apply_post_plugin_patches) && anil_cloud_orig_apply_post_plugin_patches
        anil_cloud_orig_apply_post_plugin_patches
      end
      
      # 2. Executa a nossa injeção dinâmica de cloud save garantindo prioridade máxima!
      begin
        apply_cloud_save_hooks
      rescue => e
        debug_log("ERRO crítico ao encadear apply_cloud_save_hooks pós-plugin: #{e.class} - #{e.message}")
      end
    end
  end
end

# ──────────────────────────────────────────────────────────────────────────────
# Tenta aplicar os hooks imediatamente caso o pós-plugin já tenha sido rodado
# ──────────────────────────────────────────────────────────────────────────────
begin
  if defined?(AnilLanRework) && AnilLanRework.respond_to?(:save_and_upload_save_file)
    AnilLanRework.apply_cloud_save_hooks
  end
rescue => e
  AnilLanRework.debug_log("Aviso: Falha ao rodar apply_cloud_save_hooks de forma imediata: #{e.message}") rescue nil
end

# ──────────────────────────────────────────────────────────────────────────────
# HOOK NO SCENE_MAP PARA CONEXÃO INSTANTÂNEA E SILENCIOSA PÓS-RECUPERAÇÃO
# ──────────────────────────────────────────────────────────────────────────────
class Scene_Map
  alias anil_instant_conn_main main unless method_defined?(:anil_instant_conn_main)
  def main
    if $game_temp && $game_temp.respond_to?(:anil_pending_multiplayer_instant_connect) && $game_temp.anil_pending_multiplayer_instant_connect
      $game_temp.anil_pending_multiplayer_instant_connect = false
      
      # Conecta de forma síncrona e silenciosa
      if defined?(AnilLanRework) && AnilLanRework.respond_to?(:trigger_instant_silent_connect)
        AnilLanRework.trigger_instant_silent_connect
      end
    end
    anil_instant_conn_main
  end
end

class Scene_Map
  alias anil_deferred_autosave_update update unless method_defined?(:anil_deferred_autosave_update)
  def update
    anil_deferred_autosave_update
    AnilLanRework.flush_deferred_autosaves! rescue nil
    AnilLanRework.flush_autosave_atrasado! rescue nil
  end
end
