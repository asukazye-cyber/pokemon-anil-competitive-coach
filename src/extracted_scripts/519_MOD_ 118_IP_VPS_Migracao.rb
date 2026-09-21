#===============================================================================
# MOD: 118_IP_VPS_Migracao.rb
#-------------------------------------------------------------------------------
# Faz o IP compilado voltar a ser a unica fonte de verdade do servidor.
#
# O PROBLEMA
# AnilLanRework.dedicated_server_ip le "multiplayer_vps_ip.txt" ANTES de cair no
# valor compilado. O arquivo, portanto, VENCE o codigo. Quem tivesse um IP
# antigo ali continuaria batendo no endereco errado para sempre, e nenhum update
# de script corrigiria — porque o pacote nao distribui esse arquivo (e nem
# deveria: distribuir sobrescreveria ajuste manual de quem precisa dele).
#
# A SOLUCAO
# Apagar o arquivo UMA VEZ. Sem ele, dedicated_server_ip devolve o IP compilado,
# que viaja junto com o Scripts.rxdata e pode ser corrigido em qualquer update.
#
# POR QUE NAO NO UPDATER
# O updater do jogo esta desativado (dois gates), entao depender dele deixaria a
# migracao sem acontecer. Aqui roda no carregamento dos scripts, antes de
# qualquer tentativa de conexao, independente de como o update chegou.
#
# NAO E DEFINITIVO: depois que a migracao roda, recriar o arquivo volta a
# funcionar normalmente — util para apontar para uma maquina local em testes.
# Para forcar uma nova limpeza no futuro (troca de VPS, por exemplo), basta
# mudar a versao abaixo.
#===============================================================================

# 4.0.8 = troca de VPS (143.95.212.43 -> 179.198.110.71), agosto/2026.
#
# ⚠️ A ordem aqui e delicada e vale explicar, porque a VPS antiga MORREU e o IP
# dela estava COMPILADO no build que os jogadores tem — ou seja, o updater
# deles tambem aponta para um servidor que nao existe mais e nao consegue
# buscar a correcao sozinho.
#
# O resgate e o jogador criar "multiplayer_vps_ip.txt" com o IP novo: esse
# ficheiro VENCE o IP compilado, o updater passa a alcancar o servidor e traz
# este build. Como a marca deles ainda diz "4.0.7", a migracao nao corre e o
# ficheiro que eles criaram SOBREVIVE — que e exactamente o que se precisa.
#
# Quando este build chegar, a versao passa a ser 4.0.8, a marca deixa de bater,
# o ficheiro provisorio e apagado e o IP compilado (ja o novo) volta a mandar.
ANIL_IP_MIGRACAO_VERSAO = "4.0.8" unless defined?(ANIL_IP_MIGRACAO_VERSAO)
ANIL_IP_MIGRACAO_MARCA  = "multiplayer_vps_ip_migrado.txt" unless defined?(ANIL_IP_MIGRACAO_MARCA)

begin
  ja_feita = begin
    File.exist?(ANIL_IP_MIGRACAO_MARCA) ? File.read(ANIL_IP_MIGRACAO_MARCA).strip : ""
  rescue
    ""
  end

  if ja_feita != ANIL_IP_MIGRACAO_VERSAO
    apagou = false
    if File.exist?("multiplayer_vps_ip.txt")
      antigo = (File.read("multiplayer_vps_ip.txt").strip rescue "?")
      File.delete("multiplayer_vps_ip.txt")
      apagou = true
      AnilLanRework.log("[IP] multiplayer_vps_ip.txt (#{antigo}) removido: o IP compilado passa a valer.") rescue nil
    end

    # A marca vai por ultimo, de proposito. Se a escrita falhar (pasta somente
    # leitura), a proxima execucao apenas tenta apagar de novo — e apagar um
    # arquivo que ja nao existe nao faz mal. O inverso (marcar antes) deixaria
    # a migracao registrada sem ter acontecido.
    begin
      File.open(ANIL_IP_MIGRACAO_MARCA, "wb") { |f| f.write(ANIL_IP_MIGRACAO_VERSAO) }
    rescue
      AnilLanRework.log("[IP] nao foi possivel gravar a marca da migracao.") rescue nil
    end

    AnilLanRework.log("[IP] migracao #{ANIL_IP_MIGRACAO_VERSAO} concluida (arquivo removido: #{apagou}).") rescue nil
  end
rescue => e
  # Nada aqui pode impedir o jogo de abrir.
  AnilLanRework.log("[IP] falha na migracao: #{e}") rescue nil
end
