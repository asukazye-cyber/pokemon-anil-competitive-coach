unless defined?(AnilMainMenuRedirectException)
  class AnilMainMenuRedirectException < Exception; end
end


module LBDSKY
  VERSION = "1.2.0" # No modificar esto
end

class Scene_DebugIntro
  def main
    Graphics.transition(0)
    sscene = PokemonLoad_Scene.new
    sscreen = PokemonLoadScreen.new(sscene)
    sscreen.pbStartLoadScreen
    Graphics.freeze
  end
end

def pbCallTitle
  return Scene_DebugIntro.new if $DEBUG && !Settings::SHOW_TITLE_SCREEN_ON_DEBUG
  return Scene_Intro.new
end

# ==============================================================================
# GameUpdater - Sistema de Atualização Automática de Scripts/Plugins
# ==============================================================================
module GameUpdater
  @updater_viewport = nil
  @updater_bg = nil
  @updater_text = nil

  def self.exibir_mensagem_download(mensagem)
    return unless defined?(Graphics) && defined?(Viewport) && defined?(Sprite) && defined?(Bitmap) && defined?(Color)
    begin
      @updater_viewport = Viewport.new(0, 0, Graphics.width, Graphics.height) rescue nil
      return unless @updater_viewport
      @updater_viewport.z = 999999
      
      # Fundo preto sólido
      @updater_bg = Sprite.new(@updater_viewport)
      @updater_bg.bitmap = Bitmap.new(Graphics.width, Graphics.height)
      @updater_bg.bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(12, 12, 28))
      
      # Sprite de texto centralizado
      @updater_text = Sprite.new(@updater_viewport)
      @updater_text.bitmap = Bitmap.new(Graphics.width, 140)
      @updater_text.bitmap.font.name = "Arial" rescue nil
      @updater_text.bitmap.font.size = 22
      @updater_text.bitmap.font.bold = true
      @updater_text.bitmap.font.color = Color.new(255, 255, 255)
      
      # Desenha a mensagem centralizada
      lines = mensagem.split("\n")
      y_offset = 0
      lines.each do |line|
        @updater_text.bitmap.draw_text(0, y_offset, Graphics.width, 40, line, 1)
        y_offset += 40
      end
      
      @updater_text.x = 0
      @updater_text.y = (Graphics.height - y_offset) / 2
      
      Graphics.update rescue nil
    rescue => e
      log_update("Erro ao exibir mensagem de download: #{e.message}")
    end
  end

  # Aviso de fim de atualizacao, na tela, por alguns segundos.
  #
  # POR QUE NAO O pbMessage
  #
  # A versao anterior usava pbMessage, que ESPERA uma tecla. Quem nunca viu
  # aquilo fica parado a olhar para uma caixa de texto sem saber que tem de
  # carregar em alguma coisa — e no telemovel nem e obvio qual e a tecla. O
  # jogador conclui que travou.
  #
  # Aqui a mensagem aparece, conta o tempo sozinha e sai. Carregar numa tecla
  # tambem fecha, para quem ja sabe nao ter de esperar.
  #
  # ⚠️ Isto corre ANTES do PluginManager.runPlugins, portanto nao se pode contar
  # com _INTL, com o sistema de mensagens nem com System.uptime. Usa-se o mesmo
  # desenho directo do aviso de download (Viewport + Sprite + Bitmap), que ja
  # esta provado neste ponto do arranque, e Time.now para medir.
  #
  # Se o desenho falhar por alguma razao, cai no pbMessage de antes: melhor uma
  # caixa que espera tecla do que nenhum aviso.
  SEGUNDOS_AVISO_REINICIO = 5.0

  def self.aviso_de_reinicio
    texto = "Atualizacao concluida!\n\nFeche o jogo e abra de novo\npara aplicar a atualizacao."
    desenhou = false
    begin
      exibir_mensagem_download(texto)
      desenhou = !@updater_viewport.nil?
    rescue
      desenhou = false
    end

    if desenhou
      begin
        inicio = Time.now
        while (Time.now - inicio) < SEGUNDOS_AVISO_REINICIO
          Graphics.update rescue nil
          Input.update rescue nil
          # Quem ja conhece nao precisa de esperar os 5 segundos.
          break if (defined?(Input) && (Input.trigger?(Input::USE) || Input.trigger?(Input::BACK))) rescue false
        end
      rescue
      end
      remover_mensagem_download rescue nil
      return
    end

    # Reserva.
    msg = "Atualizacao concluida! Feche o jogo e abra de novo para aplicar."
    if defined?(pbMessage)
      pbMessage(msg) rescue print(msg)
    else
      print msg
    end
  end

  def self.remover_mensagem_download
    begin
      @updater_text.bitmap.dispose rescue nil if @updater_text && @updater_text.bitmap
      @updater_text.dispose rescue nil if @updater_text
      @updater_bg.bitmap.dispose rescue nil if @updater_bg && @updater_bg.bitmap
      @updater_bg.dispose rescue nil if @updater_bg
      @updater_viewport.dispose rescue nil if @updater_viewport
      @updater_text = nil
      @updater_bg = nil
      @updater_viewport = nil
      Graphics.update rescue nil
    rescue => e
      log_update("Erro ao remover mensagem de download: #{e.message}")
    end
  end

  # O IP do servidor de atualizacoes e o MESMO que o jogo usa para jogar:
  # AnilLanRework.dedicated_server_ip (100_Multiplayer_Whitelist ~48), que ja tem
  # a VPS como padrao e aceita `multiplayer_vps_ip.txt` como sobreposicao.
  #
  # A versao anterior lia o `multiplayer_ip.txt`, que e ERRADO para isto: esse
  # ficheiro e reescrito sempre que alguem escolhe um host na descoberta LAN, e
  # o updater passava a procurar atualizacoes no PC do vizinho. Alem disso ele
  # nem sempre existe — numa instalacao nova nao existe — e caia-se em
  # 127.0.0.1.
  #
  # O updater corre CEDO, antes dos plugins, por isso ha um recurso que le o
  # ficheiro da VPS directamente caso o AnilLanRework ainda nao esteja carregado.
  def self.obter_ip_servidor
    if defined?(AnilLanRework) && AnilLanRework.respond_to?(:dedicated_server_ip)
      ip = AnilLanRework.dedicated_server_ip.to_s.strip
      return ip unless ip.empty?
    end
    if File.exist?("multiplayer_vps_ip.txt")
      ip = File.read("multiplayer_vps_ip.txt").strip rescue ""
      return ip unless ip.empty?
    end
    "179.198.110.71"
  rescue Exception
    "179.198.110.71"
  end

  def self.md5_suportado?
    begin
      require "digest"
      return Digest::MD5.hexdigest("test") == "098f6bcd4621d373cade4e832627b4f6"
    rescue Exception
      return false
    end
  end

  def self.calcular_md5_local(arquivo)
    return nil unless File.exist?(arquivo)
    begin
      require "digest"
      return Digest::MD5.file(arquivo).hexdigest
    rescue Exception
      return nil
    end
  end

  # INTERRUPTOR UNICO DOS LOGS DE DIAGNOSTICO.
  #
  # Desligado por omissao: o jogador comum nao sabe lidar com estes ficheiros nem
  # envia-los, entao so ocupam espaco e gastam I/O. Para investigar, poe-se a
  # true (ou cria-se Data/anil_debug.txt no aparelho do jogador, que e mais
  # facil de explicar por mensagem do que editar scripts).
  #
  # Nota para quem for investigar algo: LIGA ISTO PRIMEIRO. Toda a depuracao
  # deste updater — SERVER_IP inexistente, MKXPError, `json` e `digest` ausentes
  # no mkxp — saiu deste ficheiro, e nenhuma delas apareceria a ler codigo.
  LOG_MAX_LINHAS = 200

  def self.logs_ligados?
    return true if $anil_logs_diagnostico == true
    File.exist?("Data/anil_debug.txt")
  rescue
    false
  end

  def self.log_update(msg)
    return unless logs_ligados?
    begin
      caminho = "Data/updater_log.txt"
      # Sem isto o ficheiro cresce para sempre — estava com 122 KB de historico
      # de arranques antigos, que nao serve para nada.
      if File.exist?(caminho) && File.size(caminho) > 200_000
        linhas = File.readlines(caminho, encoding: "UTF-8") rescue []
        File.open(caminho, "wb") { |f| f.write(linhas.last(LOG_MAX_LINHAS).join) }
      end
      File.open(caminho, "a") do |f|
        f.puts("[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] #{msg}")
      end
    rescue
    end
    puts "[GameUpdater] #{msg}"
  end

  # ===========================================================================
  # ATUALIZACAO POR MANIFESTO  (pasta update/ do servidor)
  # ---------------------------------------------------------------------------
  # O servidor publica o que estiver em update/, espelhando a arvore do cliente:
  #
  #     update/Data/Scripts.rxdata   ->   Data/Scripts.rxdata
  #
  # Ele responde em /update/manifest com {path, md5, size} de cada arquivo. Aqui
  # comparamos o MD5 com o arquivo local e baixamos SO o que difere.
  #
  # MD5 e nao versao: responde a pergunta certa — "este arquivo e exatamente o
  # que deveria ser?" — e pega download truncado, relogio errado do aparelho e
  # arquivo mexido na mao.
  #
  # GRAVACAO EM DOIS PASSOS. Baixa para .tmp, confere o MD5 do que chegou, e so
  # entao substitui o original. Se a conexao cair no meio, o jogo continua com o
  # arquivo antigo, que funciona. Gravar direto em Data/Scripts.rxdata e deixar
  # o jogador sem jogo se algo falhar.
  # ===========================================================================
  # MOEDA DA ASSINATURA — decidida uma vez, por aparelho.
  #
  # O manifesto vem como  crc32|md5|tamanho|caminho  justamente porque os dois
  # lados nao calculam o mesmo: no mkxp o `require "digest"` rebenta (LoadError),
  # mas ha Zlib — e ele que descomprime o proprio Scripts.rxdata. No Windows
  # normal ha os dois. Entao escolhe-se aqui o que este aparelho consegue, e
  # `assinatura_local` e `esperado_para` passam a falar essa mesma moeda.
  #
  # ⚠️ As tres funcoes abaixo eram CHAMADAS mas nunca tinham sido escritas — a
  # migracao de MD5 para CRC32 trocou os chamadores e esqueceu as definicoes.
  # Resultado: NoMethodError em `assinatura_suportada?` logo depois de ler o
  # manifesto, e NENHUM ficheiro era baixado. O erro era engolido pelo rescue de
  # `atualizar_por_manifesto`, entao o jogo abria normalmente e nada indicava a
  # falha — so aparecia com os logs de diagnostico ligados (2026-08-02).
  def self.assinatura_modo
    return @assinatura_modo if @assinatura_modo
    @assinatura_modo = begin
      begin
        require "zlib"
        Zlib.crc32("test")
        :crc
      rescue Exception
        md5_suportado? ? :md5 : :nenhum
      end
    end
  end

  def self.assinatura_suportada?
    assinatura_modo != :nenhum
  end

  # Assinatura de um ficheiro em disco, na mesma moeda do manifesto.
  def self.assinatura_local(arquivo)
    return nil unless File.exist?(arquivo)
    modo = assinatura_modo
    return nil if modo == :nenhum
    dados = File.binread(arquivo)
    return Zlib.crc32(dados).to_s if modo == :crc
    require "digest"
    Digest::MD5.hexdigest(dados)
  rescue Exception
    nil
  end

  # O campo do manifesto correspondente a moeda deste aparelho.
  def self.esperado_para(item)
    return nil unless item.is_a?(Hash)
    case assinatura_modo
    when :crc then item["crc"].to_s
    when :md5 then item["md5"].to_s
    else nil
    end
  end

  def self.assinatura_de(arquivo)
    assinatura_local(arquivo)
  rescue Exception
    nil
  end

  # Interruptor local. Existe para o caso em que um pacote mau ja saiu: o
  # jogador cria este ficheiro e para de receber, sem ter de desinstalar nada.
  # Tambem serve para quem esta a testar um build proprio e nao quer ser
  # sobreposto pelo servidor.
  def self.atualizacao_bloqueada?
    File.exist?("Data/nao_atualizar.txt")
  rescue
    false
  end

  # CANAL DE TESTES.
  #
  # Com "Data/adm.txt" presente, o updater passa a ler a pasta update2/ do
  # servidor em vez da update/. Serve para experimentar uma build com duas ou
  # tres pessoas antes de a mandar para toda a gente.
  #
  # Mesmo esquema do nao_atualizar.txt: e um ficheiro que o proprio jogador
  # coloca, nao uma credencial. Nao poe em update2/ nada que nao possas dar a
  # qualquer um.
  #
  # Se o servidor nao tiver a pasta update2, o manifesto vem vazio e o cliente
  # diz "nada a atualizar" — nunca cai na build de producao por engano, que
  # seria pior do que nao receber nada.
  def self.canal_de_update
    File.exist?("Data/adm.txt") ? 2 : 1
  rescue
    1
  end

  # Sufixo a acrescentar aos pedidos. Vazio no canal normal, para nao mudar em
  # nada o que os clientes de hoje enviam.
  def self.sufixo_canal
    canal_de_update == 2 ? "&canal=2" : ""
  end

  # SONDA DE CANAL — este aparelho consegue receber binario inteiro?
  #
  # O HTTPLite do mkxp no Android (JoiPlay) trata o corpo da resposta como TEXTO
  # e COME todos os bytes 0x0D. Um PNG ou um .rxdata chega sempre mais curto, o
  # tamanho nunca bate com o manifesto e o lote inteiro e abortado — foi o que
  # aconteceu com o ONIX.png (esperado 227328, veio 226551: exactamente os 777
  # \r do ficheiro). Um sprite redesenhado nunca poderia passar por ali.
  #
  # Em vez de descobrir isso pelo fracasso — o que custaria um download inteiro,
  # 8 MB no caso do Scripts.rxdata — pergunta-se ao servidor por 38 bytes
  # recheados de \r e conta-se o que chegou.
  #
  # A resposta e guardada para a sessao: a sonda corre UMA vez por arranque.
  #
  # Se a rota nao existir (servidor antigo), assume-se canal cru: esse servidor
  # tambem nao teria o modo base64, entao pedi-lo so pioraria.
  PROBE_TAMANHO = 38   # tem de casar com PROBE_CORPO no server_runtime.rb

  def self.precisa_base64?
    return @precisa_b64 unless @precisa_b64.nil?
    @precisa_b64 = begin
      ip = obter_ip_servidor
      res = HTTPLite.get("http://#{ip}:7654/update/probe", {
        "Proxy-Connection" => "Close",
        "Pragma"           => "no-cache",
        "User-Agent"       => "Mozilla/5.0 (GameUpdater)"
      })
      if res.is_a?(Hash) && res[:status] == 200
        veio = res[:body].to_s.bytesize
        if veio == PROBE_TAMANHO
          log_update("Sonda: #{veio}/#{PROBE_TAMANHO} bytes — canal binario intacto")
          false
        else
          log_update("Sonda: #{veio}/#{PROBE_TAMANHO} bytes — este aparelho come 0x0D, a usar base64")
          true
        end
      else
        log_update("Sonda indisponivel (servidor antigo?) — a baixar em modo cru")
        false
      end
    rescue Exception => e
      log_update("Sonda falhou (#{e.class}: #{e.message}) — a baixar em modo cru")
      false
    end
  end

  # DOWNLOAD EM PEDACOS, para os aparelhos que falham na sonda.
  #
  # POR QUE PEDACOS E NAO O FICHEIRO INTEIRO
  #
  # Medido nos dois lados no mesmo segundo: o servidor mandou os 292.844
  # caracteres de base64 do 095.png, e o aparelho decodificou 218.848 bytes em
  # vez de 219.632. O MESMO pedido, feito de um PC, chega com diferenca ZERO em
  # 1 segundo. Servidor e rede estao bons; a perda acontece dentro do mkxp.
  #
  # Nao se sabe se e o corpo que trunca ou o unpack que falha — e nao interessa:
  # pedaco pequeno resolve os dois. Cada pedaco traz o proprio tamanho e CRC, e
  # um pedaco mau e repetido SOZINHO, em vez de deitar fora o lote inteiro.
  # O TAMANHO IMPORTA, e tem de ficar ABAIXO do que ja falhou.
  #
  # O 095.png tem 219.632 bytes, que em base64 sao 292.844 caracteres — e foi
  # exactamente esse pedido que voltou curto do aparelho. Um pedaco de 256 KB
  # daria ~350 KB de base64, ou seja, MAIOR do que o que ja se sabe que parte:
  # o ficheiro caberia num pedaco so e nada mudaria.
  #
  # 64 KB de binario dao ~87 KB de base64, mais de tres vezes abaixo do ponto
  # conhecido de falha. Custa mais pedidos (129 para um ficheiro de 8 MB), mas
  # cada um e barato e, se ainda assim falhar, o log diz quantos bytes chegaram
  # e da para descer mais.
  # ⚠️ 64 KB ERA PRUDENTE DE MAIS, E A PRUDENCIA CUSTAVA O UPDATE INTEIRO.
  #
  # Com 64 KB, o Scripts.rxdata de 9,1 MB precisa de 139 pedidos HTTP. Medido
  # num telemovel: tres minutos e meio com o jogo PARADO, sem nada no ecra a
  # dizer que esta vivo. O jogador fecha, reabre, e volta a pedir os mesmos 8
  # ficheiros — foi exactamente o que aconteceu, e o log acabava a meio porque
  # a aplicacao nunca chegou ao fim do download.
  #
  # 512 KB baixam isso para 18 pedidos. E se um deles falhar as tres tentativas,
  # em vez de desistir do ficheiro inteiro passa-se a METADE do tamanho e
  # continua-se — descendo ate ao antigo 64 KB, que ja se sabe que passa em todo
  # o lado. A prudencia fica no ramo de recurso, e nao no caso normal.
  # ⚠️ 64 KB, E NAO 512. O ANDROID DEVOLVE LIXO EM PEDIDOS GRANDES.
  #
  # Isto foi 524288 durante um tempo, para trocar 140 pedidos por 18. O log de
  # 30/08 mostrou o preco: com pedacos de 512 KB o aparelho devolve o NUMERO
  # CERTO DE BYTES com o conteudo errado. O ficheiro remonta-se ao tamanho
  # exacto, o teste de comprimento passa, e so o zlib da primeira seccao e que
  # descobre que aquilo nao presta.
  #
  #   18 pedaco(s), 9128983 bytes remontados  -> seccao 0 nao descomprime
  #  140 pedaco(s), 9128983 bytes remontados  -> instalado
  #
  # Mesmo ficheiro, mesmo servidor, mesmo minuto. So muda o tamanho do pedido.
  #
  # E o recuo automatico nao salvava: ele so desce quando o pedaco vem com o
  # COMPRIMENTO errado. Uma corrupcao que preserva o comprimento atravessa-o
  # inteiro. Entao nao se comeca por um tamanho que se sabe arriscado.
  #
  # Custa 10 segundos a mais no telemovel. O outro caminho custava a
  # actualizacao inteira, tres vezes seguidas, e uma entrada na lista negra.
  PEDACO = 65536            # 64 KB de binario -> ~88 KB de base64
  PEDACO_MINIMO = 65536     # ate onde se desce quando um pedaco falha
  PEDACO_TENTATIVAS = 3

  # DESCODIFICADOR DE BASE64 ESCRITO A MAO.
  #
  # POR QUE NAO unpack("m0")
  #
  # Medido no aparelho, com o corpo a chegar INTEIRO:
  #     pedaco 0: 4564 de 4593 bytes (base64 chegou 6124 de 6124)
  # Os 6124 caracteres de base64 chegaram todos — zero perda na rede — e mesmo
  # assim a descodificacao devolveu 4564 em vez de 4593. Faltam 29 bytes, que e
  # exactamente a contagem de \r do Blaine.dat.
  #
  # Ou seja: o problema nunca foi o transporte. E o proprio unpack("m0") do mkxp
  # que devolve a string ja sem os 0x0D. Por isso as tres tentativas deram o
  # mesmo numero: e deterministico, nao e falha de ligacao. E por isso tambem os
  # pedacos sozinhos nao resolveram — o tamanho nao tem nada a ver.
  #
  # Aqui o binario nunca passa pelo unpack: monta-se um Array de inteiros e so
  # no fim se faz pack("C*"). O unico unpack usado e o "C*" sobre o TEXTO base64,
  # que e seguro por construcao — base64 nao tem um unico 0x0D para se perder.
  B64_ALFABETO = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  B64_INVERSO = begin
    t = Array.new(256, -1)
    B64_ALFABETO.each_char.with_index { |c, i| t[c.ord] = i }
    t
  end

  def self.descodificar_base64(texto)
    inv = B64_INVERSO
    saida = []
    acumulador = 0
    contados = 0
    texto.unpack("C*").each do |byte|
      valor = inv[byte]
      next if valor < 0            # '=' e qualquer lixo sao ignorados
      acumulador = (acumulador << 6) | valor
      contados += 1
      next if contados < 4
      saida << ((acumulador >> 16) & 0xFF)
      saida << ((acumulador >> 8) & 0xFF)
      saida << (acumulador & 0xFF)
      acumulador = 0
      contados = 0
    end
    # Sobra: 3 caracteres valem 2 bytes, 2 caracteres valem 1 byte.
    if contados == 3
      acumulador >>= 2
      saida << ((acumulador >> 8) & 0xFF)
      saida << (acumulador & 0xFF)
    elsif contados == 2
      acumulador >>= 4
      saida << (acumulador & 0xFF)
    end
    saida.pack("C*")
  end

  def self.baixar_em_pedacos(url, headers, tamanho_total)
    if tamanho_total <= 0
      log_update("  sem tamanho no manifesto — nao da para pedir aos pedacos")
      return nil
    end
    partes = []
    lidos = 0
    n = 0
    tamanho = PEDACO
    marco = Time.now.to_f
    while lidos < tamanho_total
      querer = [tamanho, tamanho_total - lidos].min
      pedaco = nil
      PEDACO_TENTATIVAS.times do |tentativa|
        alvo = "#{url}&b64=1&off=#{lidos}&len=#{querer}"
        res = HTTPLite.get(alvo, headers)
        unless res.is_a?(Hash) && res[:status] == 200
          log_update("  pedaco #{n} HTTP #{res.is_a?(Hash) ? res[:status] : res.class} (tentativa #{tentativa + 1})")
          next
        end
        cru = res[:body].to_s
        bruto = begin
          descodificar_base64(cru)
        rescue Exception => e
          # Diagnostico que separa "chegou curto" de "nao descodificou": sem
          # este numero os dois defeitos dao a mesma mensagem la a frente.
          esperado_b64 = ((querer + 2) / 3) * 4
          log_update("  pedaco #{n}: base64 nao descodificou (#{e.class}); chegaram #{cru.bytesize} de #{esperado_b64}")
          next
        end
        if bruto.bytesize != querer
          esperado_b64 = ((querer + 2) / 3) * 4
          log_update("  pedaco #{n}: #{bruto.bytesize} de #{querer} bytes (base64 chegou #{cru.bytesize} de #{esperado_b64}) — tentativa #{tentativa + 1}")
          next
        end
        pedaco = bruto
        break
      end
      if pedaco.nil?
        # ⚠️ Encolher em vez de desistir.
        #
        # Um pedaco grande pode nao passar nesta ligacao e um pequeno passar. Da
        # a mesma resposta que o codigo antigo dava — desistir — apenas depois
        # de ter tentado tudo o que ha para tentar.
        if tamanho > PEDACO_MINIMO
          tamanho = [tamanho / 2, PEDACO_MINIMO].max
          log_update("  pedaco #{n} falhou; a descer para #{tamanho} bytes e a tentar de novo")
          next
        end
        log_update("  pedaco #{n} falhou #{PEDACO_TENTATIVAS} vezes ao tamanho minimo — desisto deste ficheiro")
        return nil
      end
      partes << pedaco
      lidos += pedaco.bytesize
      n += 1
      # ⚠️ Sinal de vida no log, de 10 em 10 segundos.
      #
      # Sem isto, um download que morre a meio deixa o log a acabar depois da
      # sonda e nao ha como saber se parou no primeiro pedaco ou no ultimo.
      agora = Time.now.to_f
      if agora - marco >= 10.0
        marco = agora
        log_update("  ... #{lidos} de #{tamanho_total} bytes (#{(lidos * 100 / tamanho_total)}%)")
      end
    end
    log_update("  #{n} pedaco(s), #{lidos} bytes remontados")
    partes.join
  end

  # FASE 1 — baixa e verifica, SEM tocar no ficheiro atual.
  # Devolve o caminho do .tmp validado, ou nil.
  #
  # Separado da instalacao de proposito: com varios ficheiros no lote, instalar
  # a meio caminho deixaria o jogo com versoes MISTURADAS (Scripts.rxdata novo
  # com PluginScripts.rxdata velho, por exemplo) — que rebenta em sitios que nao
  # tem nada a ver com o updater e e dificil de diagnosticar.
  def self.baixar_e_verificar(url, destino, esperado, tamanho_esperado = nil)
    headers = {
      "Proxy-Connection" => "Close",
      "Pragma"           => "no-cache",
      "User-Agent"       => "Mozilla/5.0 (GameUpdater)"
    }
    # Base64 usa so A-Za-z0-9+/= — nao ha um unico \r para o Android perder.
    # Custa +33% de trafego, e por isso so quem falha na sonda e que paga.
    # ⚠️ O ATALHO DO "DIRECTO PRIMEIRO" SAIU. NAO FUNCIONAVA.
    #
    # A ideia era: o Scripts.rxdata nao tem um unico 0x0D (o gerar_sem_cr.rb
    # garante-o e confirma-o a cada build), logo atravessaria intacto o canal
    # que come CRs, e poupava-se o +33% e os 140 pedidos do base64.
    #
    # O argumento estava errado, e o log de 30/08 mostrou porque: o aparelho
    # nao APAGA o 0x0D — CONVERTE bytes de fim de linha. Isso preserva o
    # comprimento. Vieram os 9.126.831 bytes certos, o teste de tamanho passou,
    # e o zlib da seccao 0 estava destruido.
    #
    # E o estrago nao ficou por ai: como o tamanho bateu, nao houve recuo para
    # os pedacos. A validacao apanhou a corrupcao e marcou o PACOTE como
    # partido — quando o partido era o canal. A tentativa seguinte foi recusada
    # antes sequer de descarregar, e o aparelho nunca chegou ao base64, que
    # funcionava perfeitamente (e funcionou, a terceira).
    #
    # A sonda existe para responder a uma pergunta: este canal entrega bytes
    # intactos? Quando ela diz que nao, nao ha ficheiro nenhum que seja
    # excepcao. Passa a base64, e acabou.
    modos = precisa_base64? ? [:pedacos] : [:directo]

    conteudo = nil
    b64 = false
    modos.each_with_index do |modo, idx|
      ultimo = (idx == modos.length - 1)
      b64 = (modo == :pedacos)
      if b64
        conteudo = baixar_em_pedacos(url, headers, tamanho_esperado.to_i)
        return nil if conteudo.nil?
      else
        log_update("  a tentar inteiro (sem base64)") if modos.length > 1
        res = HTTPLite.get(url, headers)
        unless res.is_a?(Hash) && res[:status] == 200
          log_update("  download falhou (HTTP #{res.is_a?(Hash) ? res[:status] : res.class})")
          if ultimo
            return false
          else
            conteudo = nil
            next
          end
        end
        conteudo = res[:body].to_s
      end
      # O tamanho vem no manifesto e era ignorado. E a checagem mais barata que
      # existe e apanha resposta truncada antes de gastar CPU no CRC.
      # Confere-se DEPOIS de decodificar: o que tem de bater e o binario final.
      if tamanho_esperado.to_i > 0 && conteudo.bytesize != tamanho_esperado.to_i
        log_update("  TAMANHO ERRADO (esperado #{tamanho_esperado}, veio #{conteudo.bytesize}#{b64 ? ", ja descodificado" : ""})#{ultimo ? " — descartado" : " — vou aos pedacos"}")
        conteudo = nil
        return nil if ultimo
        next
      end
      break
    end
    return nil if conteudo.nil?

    dir = File.dirname(destino)
    unless dir == "." || Dir.exist?(dir)
      partes = dir.tr("\\", "/").split("/")
      caminho = ""
      partes.each do |parte|
        caminho = caminho.empty? ? parte : "#{caminho}/#{parte}"
        Dir.mkdir(caminho) unless caminho.empty? || Dir.exist?(caminho)
      end
    end

    tmp = "#{destino}.tmp"
    File.open(tmp, "wb") { |f| f.write(conteudo) }

    # INTEGRIDADE — usa a MESMA assinatura da comparacao (CRC32 no mkxp).
    #
    # Antes verificava-se por MD5, e no mkxp o md5_suportado? e FALSO: a condicao
    # nunca era verdadeira e a verificacao era saltada por inteiro. O ficheiro
    # era gravado fosse o que fosse que chegasse — foi assim que um
    # PluginScripts.rxdata corrompido foi parar ao jogo e o partiu
    # ("undefined method `perma_faint'").
    #
    # Sem forma de verificar, NAO se grava: um binario corrompido em
    # PluginScripts.rxdata ou Scripts.rxdata impede o jogo de abrir, e o jogador
    # nao tem como voltar atras sozinho.
    assinatura = assinatura_de(tmp)
    if assinatura.nil?
      log_update("  sem forma de verificar integridade — descartado por seguranca")
      File.delete(tmp) rescue nil
      return nil
    end
    if assinatura != esperado.to_s
      log_update("  INTEGRIDADE FALHOU (esperado #{esperado}, veio #{assinatura}) — descartado")
      File.delete(tmp) rescue nil
      return nil
    end
    # ⚠️ CHEGAR INTEIRO NAO E O MESMO QUE PRESTAR.
    #
    # O CRC so diz que os bytes que sairam do servidor sao os que chegaram. Se o
    # que la esta em cima estiver partido — um build meu com um erro de sintaxe,
    # um byte nulo que o JoiPlay nao engole — o CRC bate certo e o jogo deixa de
    # abrir. Aconteceu. E quem nao sabe renomear o .bak fica sem jogo.
    #
    # Entao, para os ficheiros de script, ABRE-SE o pacote antes de o instalar.
    # ⚠️ A REDE DE SEGURANCA TEM DE FALHAR ABERTA, NUNCA FECHADA.
    #
    # Isto custou caro e a licao e simples. Um erro meu aqui dentro — um
    # `def rejeitado?` onde devia estar `def self.rejeitado?` — levantou um
    # NoMethodError que subiu ao `rescue Exception` do download, devolveu nil, e
    # abortou o lote inteiro. Resultado: os aparelhos que apanharam esse build
    # deixaram de conseguir instalar SEJA O QUE FOR, incluindo a correccao.
    # O updater e o unico sitio do jogo onde um defeito se tranca por dentro.
    #
    # Entao: um defeito NA VERIFICACAO nao pode valer mais do que a ausencia
    # dela. Se o codigo daqui rebentar, escreve-se no log e segue-se — o
    # ficheiro ja passou pelo tamanho e pelo CRC, que e exactamente a garantia
    # que havia antes de tudo isto existir. So um veredicto EXPLICITO de
    # "conteudo invalido" e que descarta.
    begin
      if rejeitado?(assinatura, conteudo.bytesize)
        log_update("  este pacote ja partiu o jogo antes — recusado")
        File.delete(tmp) rescue nil
        return nil
      end
      case script_valido?(tmp, destino)
      when :mau
        log_update("  CONTEUDO INVALIDO — descartado (o jogo fica com o que ja tinha)")
        registar_rejeitado(assinatura, conteudo.bytesize)
        File.delete(tmp) rescue nil
        return nil
      when :incerto
        # ⚠️ NAO SE CONDENA O QUE NAO SE CONSEGUIU JULGAR.
        #
        # A validacao abre 570 seccoes e descomprime-as todas. Num telemovel
        # isso fica sem memoria de vez em quando — e antes esse azar contava
        # como "conteudo invalido", o que metia o build na lista negra PARA
        # SEMPRE. O aparelho deixava de conseguir instalar aquela versao, boa
        # como estava, e nem um build novo com a mesma assinatura entrava.
        #
        # O tamanho e o CRC ja bateram, que era toda a garantia que existia
        # antes desta validacao ser escrita. Passa.
        log_update("  validacao inconclusiva — segue com tamanho e CRC, que ja bateram")
      end
    rescue Exception => e
      log_update("  a verificacao de conteudo rebentou (#{e.class}: #{e.message}) — segue com tamanho e CRC, que ja bateram")
    end

    tmp
  rescue Exception => e
    log_update("  erro ao baixar: #{e.class}: #{e.message}")
    File.delete("#{destino}.tmp") rescue nil
    nil
  end

  # ⚠️ VALIDACAO DE CONTEUDO DOS .rxdata DE SCRIPT.
  #
  # Nao se corre nada: so se desmonta. Um Scripts.rxdata e um Array de
  # [id, nome, zlib]. Se qualquer um destes passos falhar, o ficheiro nao serve:
  #
  #   1. o Marshal abre e da um Array com pelo menos umas dezenas de seccoes
  #   2. cada seccao descomprime
  #   3. nenhuma traz um byte nulo — o `ruby -c` aceita-os, o JoiPlay nao abre
  #   4. cada seccao COMPILA (so quando ha RubyVM; o compile nao executa nada)
  #
  # O ponto 4 e o que apanha um build partido meu, que e o caso que motivou
  # isto. Onde nao houver RubyVM, os tres primeiros ainda apanham corrupcao e o
  # pior dos casos fica igual ao de antes.
  MIN_SECCOES = 20
  FICHEIRO_REJEITADOS = "Data/update_rejeitado.txt"

  # ⚠️ AUTORIDADE DO SERVIDOR, MEDIDA PELO RESULTADO.
  #
  # O servidor publica o que o cliente DEVIA ter. Se o cliente descarrega e nao
  # consegue instalar, lote atras de lote, entao o que ele esta a correr nao
  # chega la — e o mais provavel e que o defeito esteja NELE, nao no servidor.
  # Foi exactamente o que aconteceu com o `def rejeitado?`: dezenas de lotes
  # abortados seguidos, e ninguem a tirar a conclusao obvia.
  #
  # Ao terceiro lote falhado de seguida, arma-se a marca de arranque. No
  # arranque seguinte a primeira seccao repoe o `.bak` — que e um build que
  # comprovadamente instalava — e a partir dai o updater volta a funcionar.
  #
  # ⚠️ SO CONTA O QUE E CULPA NOSSA.
  #
  # Servidor em baixo, sem rede, manifesto vazio: nada disso incrementa. O
  # contador so sobe quando o manifesto CHEGOU, havia ficheiros para instalar, e
  # a instalacao falhou mesmo assim. Sem esta distincao, jogar offline tres
  # vezes fazia o jogo andar para tras sozinho.
  FICHEIRO_FALHAS = "Data/anil_update_falhas.txt"
  MARCA_ARRANQUE  = "Data/anil_arranque.dat"
  FALHAS_ATE_REPOR = 3

  def self.falhas_seguidas
    File.exist?(FICHEIRO_FALHAS) ? File.read(FICHEIRO_FALHAS).to_i : 0
  rescue
    0
  end

  def self.limpar_falhas!
    File.delete(FICHEIRO_FALHAS) if File.exist?(FICHEIRO_FALHAS)
  rescue
    nil
  end

  def self.registar_lote_falhado!
    n = falhas_seguidas + 1
    File.open(FICHEIRO_FALHAS, "wb") { |f| f.write(n.to_s) } rescue nil
    log_update("  lote falhado #{n}/#{FALHAS_ATE_REPOR} seguidos")
    return if n < FALHAS_ATE_REPOR

    bak = "Data/Scripts.rxdata.bak"
    unless File.exist?(bak) && File.size(bak) > 100_000
      log_update("  #{n} lotes falhados, mas nao ha .bak para onde voltar — fica como esta")
      return
    end
    # ⚠️ Escreve-se a MARCA, nao se repoe aqui.
    #
    # Repor o Scripts.rxdata a meio do jogo trocava o ficheiro por baixo de um
    # programa que ja esta em memoria — meio carregado de um, meio do outro no
    # arranque seguinte, se algo corresse mal a meio. A marca faz a reposicao
    # acontecer no unico momento seguro: antes de qualquer script carregar.
    File.open(MARCA_ARRANQUE, "wb") { |f| f.write(Time.now.to_i.to_s) } rescue nil
    limpar_falhas!
    log_update("  #{n} lotes falhados seguidos — reposicao marcada para o proximo arranque")
  rescue => e
    log_update("  falha ao contar lotes falhados: #{e.class}: #{e.message}")
  end
  # Segundos que se pode gastar a compilar seccoes. Ver a nota no script_valido?.
  ORCAMENTO_SINTAXE = 5.0

  def self.script_valido?(ficheiro, destino)
    # ⚠️ SO O Scripts.rxdata. O PluginScripts.rxdata TEM OUTRO FORMATO.
    #
    # Apanhado a testar: a guarda era `nome.include?("scripts")`, e
    # "pluginscripts.rxdata" tambem contem "scripts". Mas ele nao e um Array de
    # [id, nome, zlib] — e uma lista de plugins, cada um com o seu proprio
    # cabecalho e as fontes la dentro. Passado por esta validacao, TODAS as 51
    # seccoes falhavam a descompressao e nenhuma actualizacao de plugins voltava
    # a instalar. Compara-se o nome exacto.
    nome = File.basename(destino.to_s).downcase
    return :bom unless nome == "scripts.rxdata"
    dados = Marshal.load(File.binread(ficheiro))
    unless dados.is_a?(Array) && dados.length >= MIN_SECCOES
      log_update("  validacao: nao e uma lista de seccoes (#{dados.class})")
      return :mau
    end
    # ⚠️ A ESTRUTURA VE-SE TODA; A SINTAXE, ATE AO ORCAMENTO.
    #
    # Descomprimir e procurar bytes nulos e barato e faz-se as 570 seccoes.
    # Compilar e que nao: num telemovel, mandar o Ruby analisar 570 seccoes
    # gasta segundos e memoria, no fim de um download que ja e longo.
    #
    # Entao compila-se por ORDEM DE RISCO, com um relogio a contar: primeiro as
    # seccoes "MOD:" e o Main — que sao as que eu mexo e as unicas que ja
    # partiram builds — e depois as do motor, ate o orcamento acabar. Quem
    # tiver aparelho rapido confere tudo; quem nao tiver confere o que importa.
    pode_compilar = (defined?(RubyVM::InstructionSequence) ? true : false)
    fontes = []
    dados.each_with_index do |sec, i|
      unless sec.is_a?(Array) && sec.length >= 3
        log_update("  validacao: seccao #{i} malformada")
        return :mau
      end
      begin
        fonte = Zlib::Inflate.inflate(sec[2].to_s)
      rescue Exception
        # ⚠️ INCERTO, E NAO MAU. O CRC JA PROVOU QUE OS BYTES ESTAO CERTOS.
        #
        # Para chegar aqui o ficheiro ja bateu com o CRC do manifesto, logo e
        # byte a byte o que foi publicado. E o gerar_sem_cr.rb confirma a cada
        # build que TODAS as seccoes inflam. Um inflate que falha neste ponto
        # nao pode ser o conteudo — e o ambiente: no Android, memoria.
        #
        # Condenar o pacote aqui era culpar o build pelo telemovel, e o preco
        # era a lista negra. Um erro de SINTAXE ou um byte nulo continuam :mau,
        # porque esses sao mesmo defeito meu e viajam no ficheiro.
        log_update("  validacao: seccao #{i} (#{sec[1]}) nao descomprime — sem memoria?")
        return :incerto
      end
      if fonte.include?(0.chr)
        log_update("  validacao: seccao #{i} (#{sec[1]}) tem byte nulo")
        return :mau
      end
      fontes << [i, sec[1].to_s, fonte] if pode_compilar
    end

    unless pode_compilar
      log_update("  validacao: #{dados.length} seccoes, estrutura boa (sem RubyVM: sintaxe nao conferida)")
      return :bom
    end

    arriscadas, resto = fontes.partition { |x| x[1].start_with?("MOD:") || x[1].include?("Main") }
    inicio = Time.now.to_f
    feitas = 0
    (arriscadas + resto).each do |i, nome, fonte|
      break if feitas > 0 && (Time.now.to_f - inicio) > ORCAMENTO_SINTAXE
      begin
        RubyVM::InstructionSequence.compile(fonte.dup.force_encoding("UTF-8"))
        feitas += 1
      rescue SyntaxError => e
        log_update("  validacao: seccao #{i} (#{nome}) nao compila: #{e.message.to_s[0, 120]}")
        return :mau
      rescue Exception
        # Um erro que nao e de sintaxe nao condena o ficheiro: pode ser uma
        # limitacao do proprio compile nesta build.
        feitas += 1
      end
    end
    log_update("  validacao: #{dados.length} seccoes ok; sintaxe conferida em #{feitas} (#{(Time.now.to_f - inicio).round(1)}s)")
    :bom
  rescue Exception => e
    log_update("  validacao rebentou: #{e.class}: #{e.message}")
    :incerto
  end

  # ⚠️ MEMORIA DOS PACOTES QUE JA PARTIRAM O JOGO.
  #
  # Sem isto ha um ciclo: o arranque restaura a copia boa, o updater volta a
  # descarregar exactamente o mesmo pacote partido, e o jogador fica preso a
  # alternar entre as duas versoes a cada abertura. Guarda-se a assinatura
  # (CRC + tamanho) e recusa-se de vez.
  # ⚠️ DUAS FALHAS, E NAO UMA.
  #
  # A lista negra nao expira: uma vez la dentro, aquele build nunca mais entra
  # naquele aparelho. Condenar a primeira falha significa que um unico azar —
  # falta de memoria a abrir as 570 seccoes, uma leitura truncada — bania um
  # build bom para sempre. E aconteceu.
  #
  # O formato passou a ser `crc|tamanho|falhas`. As linhas antigas, sem o
  # terceiro campo, contam como UMA falha: quem foi condenado pelo criterio
  # velho fica em liberdade condicional em vez de preso.
  FALHAS_PARA_BANIR = 2

  def self.linhas_rejeitadas
    return [] unless File.exist?(FICHEIRO_REJEITADOS)
    File.read(FICHEIRO_REJEITADOS).each_line.map(&:strip).reject(&:empty?)
  rescue
    []
  end

  def self.falhas_de(assinatura, tamanho)
    linhas_rejeitadas.each do |l|
      partes = l.split("|")
      next unless partes[0].to_s == assinatura.to_s && partes[1].to_s == tamanho.to_s
      return (partes.length >= 3 ? partes[2].to_i : 1)
    end
    0
  rescue
    0
  end

  def self.registar_rejeitado(assinatura, tamanho)
    n = falhas_de(assinatura, tamanho) + 1
    outras = linhas_rejeitadas.reject do |l|
      partes = l.split("|")
      partes[0].to_s == assinatura.to_s && partes[1].to_s == tamanho.to_s
    end
    outras << "#{assinatura}|#{tamanho}|#{n}"
    File.open(FICHEIRO_REJEITADOS, "wb") { |f| f.write(outras.join("
") + "
") }
    log_update("  falha #{n}/#{FALHAS_PARA_BANIR} deste pacote#{n >= FALHAS_PARA_BANIR ? " — banido" : " — ainda ha uma tentativa"}")
  rescue
    nil
  end

  def self.rejeitado?(assinatura, tamanho)
    falhas_de(assinatura, tamanho) >= FALHAS_PARA_BANIR
  rescue
    false
  end

  # FASE 2 — instala o lote JA VERIFICADO. Tudo ou nada.
  #
  # `prontos` e [[destino, tmp], ...]. O ficheiro atual vai para .bak em vez de
  # ser apagado: se a troca falhar a meio (disco cheio, ficheiro aberto por
  # outro processo, antivirus), desfaz-se tudo e o jogador fica exactamente como
  # estava. Antes era File.delete + rename, que alem de nao ter volta ainda
  # deixava um instante sem ficheiro nenhum.
  def self.instalar_lote(prontos)
    feitos = []
    begin
      prontos.each do |destino, tmp|
        bak = "#{destino}.bak"
        if File.exist?(destino)
          File.delete(bak) rescue nil
          File.rename(destino, bak)
        end
        File.rename(tmp, destino)
        feitos << [destino, bak]
      end
      log_update("Instalados #{feitos.length} ficheiro(s). Copia anterior guardada em .bak")
      true
    rescue Exception => e
      log_update("FALHA AO INSTALAR (#{e.class}: #{e.message}) — a reverter #{feitos.length} ficheiro(s)")
      feitos.reverse_each do |destino, bak|
        begin
          File.delete(destino) rescue nil
          File.rename(bak, destino) if File.exist?(bak)
        rescue Exception => e2
          log_update("  !! nao consegui reverter #{destino}: #{e2.message}")
        end
      end
      false
    end
  end

  def self.atualizar_por_manifesto
    if atualizacao_bloqueada?
      log_update("Data/nao_atualizar.txt presente — atualizacao ignorada nesta instalacao.")
      return false
    end
    ip  = obter_ip_servidor
    # Formato TEXTO (md5|tamanho|caminho), nao JSON: o mkxp nao tem a biblioteca
    # json disponivel nesta altura do arranque, e `require "json" rescue nil` nao
    # protege — LoadError e ScriptError, nao StandardError, entao o modificador
    # rescue deixa passar. Texto simples nao depende de nada.
    # O "?" tem de existir aqui para o sufixo do canal poder ser "&canal=2".
    url = "http://#{ip}:7654/update/manifest.txt?v=1#{sufixo_canal}"
    log_update("--- ATUALIZACAO POR MANIFESTO ---")
    log_update("CANAL DE TESTES (Data/adm.txt presente) — a ler update2/ do servidor") if canal_de_update == 2
    log_update("Consultando #{url}")

    headers = {
      "Proxy-Connection" => "Close",
      "Pragma"           => "no-cache",
      "User-Agent"       => "Mozilla/5.0 (GameUpdater)"
    }
    begin
      res = HTTPLite.get(url, headers)
    rescue Exception => e
      log_update("Sem resposta do servidor: #{e.class}: #{e.message}")
      return false
    end
    unless res.is_a?(Hash) && res[:status] == 200
      log_update("Servidor nao respondeu ao manifesto (#{res.is_a?(Hash) ? res[:status] : res.class})")
      return false
    end

    arquivos = []
    res[:body].to_s.split("
").each do |linha|
      partes = linha.strip.split("|", 4)
      next unless partes.length == 4
      arquivos << { "crc" => partes[0], "md5" => partes[1],
                    "size" => partes[2].to_i, "path" => partes[3] }
    end
    if arquivos.empty?
      log_update("Manifesto vazio ou invalido")
      return false
    end
    log_update("Manifesto: #{arquivos.length} arquivo(s) publicado(s)")

    # Sem MD5 nao ha como comparar. O calcular_md5_local devolveria nil para
    # tudo, o updater leria isso como "nao tenho esse arquivo" e baixaria o jogo
    # inteiro a CADA boot, para sempre. Melhor nao atualizar do que isso.
    # (O mkxp nem sempre traz a Digest — dai existir o md5_suportado?.)
    unless assinatura_suportada?
      log_update("Sem Zlib nem Digest neste aparelho — atualizacao ignorada.")
      return false
    end

    pendentes = []
    arquivos.each do |item|
      next unless item.is_a?(Hash)
      caminho = item["path"].to_s
      next if caminho.empty? || caminho.include?("..")   # nunca sair da arvore
      local = caminho
      atual = File.exist?(local) ? assinatura_local(local) : nil
      esperado = esperado_para(item)
      if atual.nil?
        log_update("  #{caminho}: nao existe aqui -> baixar")
        pendentes << item
      elsif atual != esperado
        log_update("  #{caminho}: diferente -> baixar")
        pendentes << item
      else
        log_update("  #{caminho}: em dia")
      end
    end

    if pendentes.empty?
      log_update("Nada a atualizar.")
      limpar_falhas!
      return true
    end

    exibir_mensagem_download("Baixando atualizacao...
#{pendentes.length} arquivo(s)") rescue nil
    # FASE 1: baixa e verifica TUDO, sem instalar nada.
    prontos = []
    falhou  = false
    pendentes.each do |item|
      caminho = item["path"].to_s
      alvo = "http://#{ip}:7654/update/get?path=#{caminho}#{sufixo_canal}"
      log_update("Baixando #{caminho} (#{item['size']} bytes)")
      # passa a assinatura que ESTE aparelho sabe calcular (crc no mkxp)
      tmp = baixar_e_verificar(alvo, caminho, esperado_para(item).to_s, item["size"])
      if tmp
        prontos << [caminho, tmp]
      else
        falhou = true
        break
      end
    end

    # Um ficheiro que falha ABORTA o lote inteiro, e os .tmp ja baixados sao
    # deitados fora. Instalar so o que veio bem deixaria o jogo com versoes
    # misturadas — um Scripts.rxdata novo a correr com plugins velhos rebenta
    # longe do updater e parece um bug de outra coisa qualquer.
    if falhou
      prontos.each { |_dest, tmp| File.delete(tmp) rescue nil }
      remover_mensagem_download rescue nil
      log_update("Lote abortado: nenhum ficheiro foi alterado. Nada mudou no jogo.")
      registar_lote_falhado!
      return false
    end

    # FASE 2: troca tudo de uma vez, guardando .bak e revertendo se algo falhar.
    unless instalar_lote(prontos)
      remover_mensagem_download rescue nil
      log_update("Instalacao revertida: o jogo ficou como estava.")
      return false
    end
    baixados = prontos.length
    entrega_dat = prontos.any? { |dest, _tmp| dest =~ /\.dat\z/i }
    remover_mensagem_download rescue nil

    # Se vieram .dat prontos, o cliente NAO os pode regerar por cima: sem o
    # arquivo-guarda ele recompila o PBS todo no proximo boot e apaga o que
    # acabamos de baixar.
    if entrega_dat && !File.exist?("Data/.pbs_compiled_raid_v3")
      File.open("Data/.pbs_compiled_raid_v3", "wb") { |f| f.write("updater") } rescue nil
      log_update("Guarda .pbs_compiled_raid_v3 criada (vieram .dat prontos)")
    end

    limpar_falhas!
    log_update("Atualizacao concluida: #{baixados}/#{pendentes.length} arquivo(s).")
    baixados > 0
  rescue Exception => e
    log_update("ERRO na atualizacao por manifesto: #{e.class}: #{e.message}")
    remover_mensagem_download rescue nil
    false
  end

  def self.executar_atualizacao
    atualizar_por_manifesto
    return true

    begin
      File.delete("Data/updater_log.txt") rescue nil
    rescue
    end

    server_ip = obter_ip_servidor
    url_check = "http://#{server_ip}:7654/update/check"

    log_update("--- INICIANDO VERIFICAÇÃO DE ATUALIZAÇÃO ---")
    log_update("IP do Servidor: #{server_ip}")
    log_update("URL de Checagem: #{url_check}")
    
    headers = {
      "Proxy-Connection" => "Close",
      "Pragma"           => "no-cache",
      "User-Agent"       => "Mozilla/5.0 (GameUpdater)"
    }

    # Realiza a requisição de status/checksum
    begin
      log_update("Enviando requisição HTTP get para: #{url_check} ...")
      res = HTTPLite.get(url_check, headers)
    rescue Exception => e
      log_update("FALHA CRÍTICA DE CONEXÃO: #{e.class} - #{e.message}")
      log_update(e.backtrace.join("\n")) rescue nil
      return false
    end

    if !res.is_a?(Hash)
      log_update("ERRO: Resposta inválida do HTTPLite. Esperava Hash, veio #{res.class}")
      return false
    end

    log_update("HTTP Status retornado: #{res[:status]}")

    if res[:status] != 200
      log_update("ERRO: Servidor retornou código HTTP #{res[:status]}")
      return false
    end

    info = nil
    begin
      require "json"
      info = JSON.parse(res[:body])
      log_update("Informações recebidas do servidor via JSON: #{info.keys.join(', ')}")
    rescue Exception => e
      log_update("JSON nativo falhou (#{e.message}). Usando parser alternativo via Regex...")
      body_str = res[:body].to_s
      info = {}
      
      # Captura md5 de scripts
      if body_str =~ /"scripts"\s*:\s*\{[^}]*"md5"\s*:\s*"([a-f0-9]{32})"/i
        info["scripts"] = { "md5" => $1 }
      end
      
      # Captura md5 de plugins
      if body_str =~ /"plugins"\s*:\s*\{[^}]*"md5"\s*:\s*"([a-f0-9]{32})"/i
        info["plugins"] = { "md5" => $1 }
      end
      
      log_update("Informações extraídas via Regex: #{info.keys.join(', ')}")
      
      if info.empty?
        log_update("ERRO ao decodificar JSON do servidor e fallback Regex falhou.")
        log_update("Conteúdo do body: #{res[:body]}") rescue nil
        return false
      end
    end

    updated_any = false

    # 1. Scripts.rxdata Check
    if info["scripts"] && !File.exist?("Data/.pbs_compiled_raid_v3")
      remote_md5 = info["scripts"]["md5"]
      remote_size = info["scripts"]["size"]
      local_path = "Data/Scripts.rxdata"
      
      local_md5 = calcular_md5_local(local_path)
      local_size = File.size(local_path) rescue 0
      
      md5_disponivel = md5_suportado? && !local_md5.nil?
      
      log_update("Scripts.rxdata - Local MD5: #{local_md5 || 'N/A'} (Tamanho: #{local_size}) | Remoto MD5: #{remote_md5} (Tamanho: #{remote_size})")
      
      desatualizado = false
      if md5_disponivel
        desatualizado = (local_md5 != remote_md5)
      else
        desatualizado = (local_size != remote_size)
        log_update("Bypass MD5 ativo (Digest::MD5 indisponível): usando comparador por tamanho de arquivo.")
      end
      
      if desatualizado
        log_update("Scripts.rxdata está DESATUALIZADO! Baixando nova versão...")
        url_download = "http://#{server_ip}:7654/update/scripts"
        
        if File.exist?(local_path)
          File.rename(local_path, "#{local_path}.bak") rescue nil
        end

        begin
          exibir_mensagem_download("Baixando novos arquivos do jogo...\nPor favor, aguarde.")
          dl = HTTPLite.get(url_download, headers)
          if dl.is_a?(Hash) && dl[:status] == 200
            corpo_download = dl[:body] || ""
            download_valido = false
            
            if md5_suportado?
              downloaded_md5 = Digest::MD5.hexdigest(corpo_download) rescue nil
              log_update("Download de Scripts concluído. MD5 baixado: #{downloaded_md5}")
              if downloaded_md5 == remote_md5
                download_valido = true
              else
                log_update("ERRO: MD5 do arquivo baixado não bate com o MD5 remoto!")
              end
            else
              log_update("Download de Scripts concluído. Tamanho baixado: #{corpo_download.bytesize} bytes.")
              if corpo_download.bytesize > 0
                download_valido = true
                log_update("Bypass MD5 ativo no download: Confiança na integridade HTTP 200 OK.")
              else
                log_update("ERRO: Corpo do download vazio.")
              end
            end
            
            if download_valido
              File.open(local_path, "wb") { |f| f.write(corpo_download) }
              log_update("Scripts.rxdata atualizado com sucesso no disco!")
              File.delete("#{local_path}.bak") rescue nil
              updated_any = true
            else
              File.rename("#{local_path}.bak", local_path) if File.exist?("#{local_path}.bak")
            end
          else
            status = dl.is_a?(Hash) ? dl[:status] : "desconhecido"
            log_update("ERRO no download do Scripts. Status HTTP: #{status}")
            File.rename("#{local_path}.bak", local_path) if File.exist?("#{local_path}.bak")
          end
        rescue Exception => e
          log_update("ERRO durante download do Scripts: #{e.message}")
          File.rename("#{local_path}.bak", local_path) if File.exist?("#{local_path}.bak")
        ensure
          remover_mensagem_download
        end
      else
        log_update("Scripts.rxdata já está na versão mais recente.")
      end
    end

    # 2. PluginScripts.rxdata Check
    if info["plugins"] && !File.exist?("Data/.pbs_compiled_raid_v3")
      remote_md5 = info["plugins"]["md5"]
      remote_size = info["plugins"]["size"]
      local_path = "Data/PluginScripts.rxdata"
      
      local_md5 = calcular_md5_local(local_path)
      local_size = File.size(local_path) rescue 0
      
      md5_disponivel = md5_suportado? && !local_md5.nil?
      
      log_update("PluginScripts.rxdata - Local MD5: #{local_md5 || 'N/A'} (Tamanho: #{local_size}) | Remoto MD5: #{remote_md5} (Tamanho: #{remote_size})")
      
      desatualizado = false
      if md5_disponivel
        desatualizado = (local_md5 != remote_md5)
      else
        desatualizado = (local_size != remote_size)
        log_update("Bypass MD5 ativo (Digest::MD5 indisponível): usando comparador por tamanho de arquivo.")
      end
      
      if desatualizado
        log_update("PluginScripts.rxdata está DESATUALIZADO! Baixando nova versão...")
        url_download = "http://#{server_ip}:7654/update/plugins"

        if File.exist?(local_path)
          File.rename(local_path, "#{local_path}.bak") rescue nil
        end

        begin
          exibir_mensagem_download("Atualizando plugins do jogo...\nPor favor, aguarde.")
          dl = HTTPLite.get(url_download, headers)
          if dl.is_a?(Hash) && dl[:status] == 200
            corpo_download = dl[:body] || ""
            download_valido = false
            
            if md5_suportado?
              downloaded_md5 = Digest::MD5.hexdigest(corpo_download) rescue nil
              log_update("Download de PluginScripts concluído. MD5 baixado: #{downloaded_md5}")
              if downloaded_md5 == remote_md5
                download_valido = true
              else
                log_update("ERRO: MD5 do plugin baixado não bate com o MD5 remoto!")
              end
            else
              log_update("Download de PluginScripts concluído. Tamanho baixado: #{corpo_download.bytesize} bytes.")
              if corpo_download.bytesize > 0
                download_valido = true
                log_update("Bypass MD5 ativo no download: Confiança na integridade HTTP 200 OK.")
              else
                log_update("ERRO: Corpo do download vazio.")
              end
            end
            
            if download_valido
              File.open(local_path, "wb") { |f| f.write(corpo_download) }
              log_update("PluginScripts.rxdata atualizado com sucesso no disco!")
              File.delete("#{local_path}.bak") rescue nil
              updated_any = true
            else
              File.rename("#{local_path}.bak", local_path) if File.exist?("#{local_path}.bak")
            end
          else
            status = dl.is_a?(Hash) ? dl[:status] : "desconhecido"
            log_update("ERRO no download do PluginScripts. Status HTTP: #{status}")
            File.rename("#{local_path}.bak", local_path) if File.exist?("#{local_path}.bak")
          end
        rescue Exception => e
          log_update("ERRO durante download do PluginScripts: #{e.message}")
          File.rename("#{local_path}.bak", local_path) if File.exist?("#{local_path}.bak")
        ensure
          remover_mensagem_download
        end
      else
        log_update("PluginScripts.rxdata já está na versão mais recente.")
      end
    end

    if updated_any
      log_update("REINICIANDO O JOGO PARA APLICAR ATUALIZAÇÕES...")
      aviso_de_reinicio
      # Força reinicialização do RGSS
      raise Reset if defined?(Reset)
      exit
    end

    log_update("Verificação finalizada. Nenhuma atualização pendente aplicada.")
    return true
  end
end

def mainFunction
  if true #$DEBUG
    pbCriticalCode { mainFunctionDebug }
  else
    mainFunctionDebug
  end
  return 1
end

def mainFunctionDebug
  begin
    # Executa verificação de atualizações antes de rodar plugins/compilador
    begin
      GameUpdater.executar_atualizacao
    rescue Exception => e
      puts "Erro ao verificar atualizacoes: #{e.message}"
    end

    MessageTypes.load_default_messages if FileTest.exist?("Data/messages_core.dat")
    PluginManager.runPlugins
    Compiler.main
    Game.initialize
    Game.set_up_system
    Graphics.update
    Graphics.freeze
    $scene = pbCallTitle
    begin
      $scene.main until $scene.nil?
    rescue AnilMainMenuRedirectException
      $scene = pbCallTitle rescue nil
      retry if $scene
    end
    Graphics.transition
  rescue Hangup
    pbPrintException($!) if !$DEBUG
    pbEmergencySave
    raise
  end
end

# ⚠️ O RECIBO DO ARRANQUE.
#
# Chegar aqui quer dizer que TODAS as seccoes do Scripts.rxdata carregaram sem
# rebentar — este e o fim do ficheiro e o Main e a ultima delas. E o unico ponto
# do jogo onde isso se pode afirmar.
#
# A marca foi posta pela PRIMEIRA seccao (MOD 0000a_Recuperacao_Boot). Apaga-se
# aqui; se um dia ela sobreviver a um arranque, e porque o arranque morreu pelo
# caminho, e essa primeira seccao repoe o .bak sozinha.
#
# Nao se mexe em mais nada e nao se depende de nada: e um File.delete.
begin
  File.delete("Data/anil_arranque.dat") if File.exist?("Data/anil_arranque.dat")
  # E o recado do que falhou tambem: se este arranque chegou aqui, o problema
  # ja nao existe. Um aviso que fica para tras e um aviso que mente na vez
  # seguinte — e foi isso que se viu: "ta dando esse aviso reposto" numa
  # sessao que tinha arrancado bem.
  File.delete("Data/aviso_reposto.txt") if File.exist?("Data/aviso_reposto.txt")
rescue Exception
  nil
end

loop do
  retval = mainFunction
  case retval
  when 0   # failed
    loop do
      Graphics.update
    end
  when 1   # ended successfully
    break
  end
end