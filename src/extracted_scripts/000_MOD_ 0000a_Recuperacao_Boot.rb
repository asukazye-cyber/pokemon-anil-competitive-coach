# encoding: UTF-8
#===============================================================================
# MOD: 0000a_Recuperacao_Boot
#-------------------------------------------------------------------------------
# ⚠️ ESTA SECCAO E A PRIMEIRA DE TODAS, E TEM DE CONTINUAR A SER.
#
# O jogo carrega as seccoes do Scripts.rxdata por ordem. Se uma delas rebentar,
# o motor mostra o erro e fecha — e nada do que vem depois chega a correr. Por
# isso a rede de seguranca tem de estar ANTES de tudo: e o unico sitio de onde
# ela ainda ve o mundo se o resto estiver partido.
#
# ⚠️ COMO SE SABE QUE O ARRANQUE ANTERIOR MORREU.
#
# Aqui deixa-se uma marca. No fim do Main — quando TODAS as seccoes ja
# carregaram — a marca e apagada. Portanto:
#
#     marca ainda la ao arrancar  =  o arranque anterior nao chegou ao fim
#
# Nesse caso repoe-se o `.bak`, que e a versao que estava a funcionar antes da
# ultima actualizacao, e fecha-se o jogo. O jogador volta a abrir e esta bom.
# Nao ha nada para ele renomear nem para ele perceber.
#
# ⚠️ E GUARDA-SE O PACOTE QUE PARTIU, PARA NAO VOLTAR.
#
# Sem isto haveria um ciclo: repoe-se a versao boa, o updater descarrega outra
# vez exactamente o mesmo pacote partido, e o jogador fica a alternar entre as
# duas a cada abertura. A assinatura fica no `update_rejeitado.txt` e o updater
# recusa-a de vez (ver o script_valido? / rejeitado? no Main).
#
# ⚠️ PORQUE E QUE ISTO NAO PODE DEPENDER DE NADA.
#
# Corre antes de existir Settings, antes de existir AnilLanRework, antes de tudo.
# So se usa File, Dir e Zlib (que o motor ja traz). Um `rescue` a envolver o
# bloco inteiro: se esta rede falhar, o jogo tem de arrancar na mesma.
#===============================================================================

# ⚠️ A MARCA MUDOU DE NOME, E ISSO NAO E ARRUMACAO.
#
# O nome antigo — `Data/boot_incompleto.txt` — passou a ser usado como RESGATE
# dos aparelhos que apanharam o build com o updater partido: publica-se no
# manifesto uma entrada `Data/boot_incompleto.txt/x`, o cliente partido cria a
# PASTA com esse nome antes de rebentar, e no arranque seguinte o `File.exist?`
# (que da true para pastas) dispara a reposicao. Ver o LEIA-ME do resgate.
#
# Se este build continuasse a usar o mesmo nome, acontecia o desastre simetrico:
#   1. o cliente ja curado instalaria a entrada e ficaria com a pasta;
#   2. no arranque seguinte via a "marca" e fazia rollback;
#   3. e voltava ao principio, para sempre.
#
# Alem disso, com uma PASTA chamada `boot_incompleto.txt` no disco, o
# `File.open(..., "wb")` desse nome falha — e esta rede nunca mais se conseguia
# armar nesses aparelhos.
#
# Um nome novo resolve os dois problemas de uma vez: o build partido continua a
# cair na armadilha (e a ser salvo), e este fica imune sem ter de apagar nada.
begin
  anil_marca = "Data/anil_arranque.dat"
  anil_alvo  = "Data/Scripts.rxdata"
  anil_bak   = "Data/Scripts.rxdata.bak"

  # ⚠️ E TEM DE SER UM FICHEIRO, COM UM NUMERO LA DENTRO.
  #
  # E o que esta rede escreve. Uma pasta, ou um ficheiro que veio de fora com
  # outro conteudo, nao e marca nenhuma — e recusa-la e o que impede alguem
  # (ou o proprio updater) de mentir ao jogo sobre o ultimo arranque.
  anil_marca_valida = begin
    File.file?(anil_marca) && File.read(anil_marca).to_s.strip =~ /\A\d+\z/ ? true : false
  rescue Exception
    false
  end

  if anil_marca_valida
    # ⚠️ So se repoe se houver mesmo para onde voltar.
    #
    # Um .bak minusculo ou inexistente e pior do que o ficheiro partido: trocava
    # um jogo que nao abre por um jogo que nao abre E sem historico. Nesse caso
    # limpa-se a marca e deixa-se seguir — se voltar a rebentar, pelo menos o
    # erro que o jogador ve e o verdadeiro.
    if File.exist?(anil_bak) && File.size(anil_bak) > 100_000
      # ⚠️ ISTO ESCREVIA UMA RECUSA QUE O UPDATER NAO CONTAVA. E DAVA UM CICLO.
      #
      # A intencao era boa: guardar a assinatura do build que partiu, para o
      # updater nao o trazer outra vez. So que ele conta assim:
      #
      #     def self.falhas_de(assinatura, tamanho)
      #       ... return (partes.length >= 3 ? partes[2].to_i : 1)
      #     def self.rejeitado?(a, t) = falhas_de(a, t) >= FALHAS_PARA_BANIR   # 2
      #
      # Uma linha com DOIS campos vale sempre 1, e 1 nunca chega a 2. Ou seja:
      # por muitas vezes que o mesmo build partisse o jogo, o updater nunca o
      # considerava banido e voltava a instala-lo no arranque seguinte.
      #
      # O resultado e um ciclo que nao para sozinho: baixa, parte, repoe, baixa
      # outra vez. Visto de fora e "ele diz que baixa dois ficheiros e nao baixa
      # nada" — baixa, instala, e a reposicao desfaz antes de se ver.
      #
      # Escreve-se no MESMO formato de tres campos que o updater usa, somando a
      # contagem da assinatura que ja la estivesse. A segunda falha bane, e o
      # jogador fica no build que funciona em vez de andar aos circulos.
      begin
        require "zlib"
        dados = File.binread(anil_alvo)
        assinatura = Zlib.crc32(dados).to_s
        tamanho = dados.bytesize.to_s
        antigas = []
        quantas = 0
        if File.exist?("Data/update_rejeitado.txt")
          File.read("Data/update_rejeitado.txt").each_line do |l|
            l = l.strip
            next if l.empty?
            partes = l.split("|")
            if partes[0].to_s == assinatura && partes[1].to_s == tamanho
              n = (partes.length >= 3 ? partes[2].to_i : 1)
              quantas = n if n > quantas
              next
            end
            antigas << l
          end
        end
        antigas << "#{assinatura}|#{tamanho}|#{quantas + 1}"
        File.open("Data/update_rejeitado.txt", "wb") { |f| f.write(antigas.join("\n") + "\n") }
      rescue Exception
        assinatura = nil
        tamanho = nil
        quantas = 0
      end

      File.delete(anil_marca) rescue nil

      # ⚠️ COPIAM-SE OS BYTES. NAO SE RENOMEIA.
      #
      # O `File.rename` ja nos correu mal no Android uma vez (ver o updater) e o
      # risco aqui e o pior que ha: se o rename do ficheiro partido para
      # ".falhou" passar e o do ".bak" para o lugar dele falhar, o jogo fica sem
      # Scripts.rxdata nenhum — e ai nao arranca de todo, nem ha segunda
      # oportunidade. Uma escrita por cima nao tem esse estado intermedio.
      dados_bons = File.binread(anil_bak)
      if dados_bons && dados_bons.bytesize > 100_000
        # copia do partido, so para diagnostico; se falhar, nao faz mal nenhum
        begin
          File.open(anil_alvo + ".falhou", "wb") { |f| f.write(File.binread(anil_alvo)) }
        rescue Exception
          nil
        end
        File.open(anil_alvo, "wb") { |f| f.write(dados_bons) }
      end

      # ⚠️ NADA DE `print` E NADA DE `exit` AQUI.
      #
      # O `print` do RGSS abre uma caixa do sistema; neste ponto do arranque, no
      # Android, isso e um risco de pendurar o jogo justamente no momento em que
      # ele se estava a curar. E o `exit` levanta SystemExit — que o `rescue
      # Exception` la de baixo, este mesmo, engolia. Ou seja: nunca saiu.
      #
      # Deixa-se um recado em ficheiro. Esta sessao continua com o build velho
      # (ja esta carregado em memoria, nao ha volta a dar); no arranque seguinte
      # ja e o bom.
      # ⚠️ UM RECADO QUE NAO IDENTIFICA NADA NAO SERVE PARA NADA.
      #
      # "A ultima atualizacao vinha com problema" nao diz QUAL, nem QUANDO, nem
      # quantas vezes ja aconteceu — e sem isso nao da para saber se o problema
      # e novo ou se e o mesmo em ciclo.
      #
      # O que esta rede PODE saber e isto: que ficheiro falhou (assinatura e
      # tamanho), a que horas, e a que tentativa vai. O PORQUE ela nao sabe e
      # nao pode saber — o erro aconteceu na sessao anterior, que ja morreu. Ai
      # a unica fonte e a caixa de erro que o jogo mostrou nessa altura.
      begin
        File.open("Data/aviso_reposto.txt", "wb") do |f|
          f.write("O arranque anterior nao chegou ao fim e o Scripts.rxdata foi desfeito.\n")
          f.write("quando:    #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}\n")
          f.write("ficheiro:  #{tamanho} bytes, assinatura #{assinatura}\n") if assinatura
          f.write("tentativa: #{quantas + 1}\n") if assinatura
          f.write("o que partiu ficou em Data/Scripts.rxdata.falhou\n")
          f.write("o que esta a correr agora e o Data/Scripts.rxdata.bak\n")
          f.write("\n")
          f.write("O MOTIVO nao esta aqui: o erro aconteceu na sessao que morreu.\n")
          f.write("Ele apareceu numa caixa de erro do jogo, com o nome do script\n")
          f.write("e a linha. E essa caixa que diz o que se partiu.\n")
        end
      rescue Exception
        nil
      end
    else
      File.delete(anil_marca) rescue nil
    end
  end

  # A marca deste arranque. O Main apaga-a quando tudo tiver carregado.
  begin
    Dir.mkdir("Data") unless Dir.exist?("Data")
  rescue Exception
    nil
  end
  File.open(anil_marca, "wb") { |f| f.write(Time.now.to_i.to_s) }
rescue Exception
  nil
end
