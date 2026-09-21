# encoding: UTF-8
#===============================================================================
# MOD: 137_Skins_Aprovacao
#-------------------------------------------------------------------------------
# Diz ao jogador em que pe esta a skin custom que ele enviou.
#
# O QUE JA EXISTIA (e continua a valer)
#
# A moderacao no servidor esta feita ha tempo e funciona: o upload cai em
# storage/skins_pending/, o /skins/download so serve de storage/skins/, e o
# envio P2P e recusado com "[SKIN_P2P] Bloqueado envio ... nao aprovada". Ou
# seja, ninguem chega a ver a skin de outra pessoa antes de aprovada.
#
# O QUE FALTAVA
#
# Retorno nenhum para o autor. Ele ve a propria skin — que e um ficheiro local,
# desenhado por ele — e conclui que toda a gente ve. Nao ve. Sem uma palavra do
# servidor, a moderacao ficava invisivel dos dois lados: o jogador achava que
# estava publicada, e o administrador nao sabia que o jogador achava isso.
#
# COMO FUNCIONA AGORA
#
#   upload aceite      -> servidor manda "pendente"  -> "Aguardando aprovacao"
#   painel aprova      -> servidor manda "aprovada"  -> avisa e limpa o estado
#   painel recusa      -> servidor manda "recusada"  -> avisa e VOLTA ao padrao
#
# O estado fica em disco porque a decisao pode demorar dias: sem isso, fechar o
# jogo apagava o "aguardando" e o jogador voltava a pensar que estava tudo certo.
#===============================================================================

module AnilSkinAprovacao
  FICHEIRO = "Data/skin_estado.txt"

  class << self
    attr_accessor :estado   # { "nome_da_skin" => "pendente" }
  end
  @estado = nil

  module_function

  def carregar
    return @estado if @estado
    @estado = {}
    begin
      if File.exist?(FICHEIRO)
        File.readlines(FICHEIRO, encoding: "UTF-8").each do |linha|
          nome, st = linha.strip.split("|", 2)
          @estado[nome] = st if nome && st && !nome.empty?
        end
      end
    rescue
      @estado = {}
    end
    @estado
  end

  def gravar
    File.open(FICHEIRO, "w:UTF-8") do |f|
      carregar.each { |nome, st| f.puts("#{nome}|#{st}") }
    end
  rescue => e
    AnilLanRework.log("[SKIN] nao consegui gravar o estado: #{e.message}") rescue nil
  end

  def pendente?(skin)
    carregar[skin.to_s] == "pendente"
  end

  # A skin em uso, tal como o resto do jogo a le.
  def skin_em_uso
    ($player && $player.respond_to?(:multiplayer_skin) ? $player.multiplayer_skin.to_s : "")
  end

  def receber(packet)
    skin = packet["skin"].to_s
    st   = packet["status"].to_s
    return if skin.empty?
    carregar

    case st
    when "pendente"
      return if @estado[skin] == "pendente"   # reenvio: nao repetir o aviso
      @estado[skin] = "pendente"
      gravar
      avisar(_INTL("Skin '{1}' enviada! Aguardando aprovação do administrador — por enquanto só você a vê.", skin))
    when "aprovada"
      @estado.delete(skin)
      gravar
      avisar(_INTL("Sua skin '{1}' foi aprovada! Agora os outros jogadores também veem você assim.", skin))
      # Os peers que ja pediram levaram com o bloqueio e nao voltam a pedir
      # sozinhos. Empurrar resolve na hora, sem ninguem reiniciar.
      AnilSkinPush.empurrar(skin) if defined?(AnilSkinPush)
    when "recusada"
      @estado.delete(skin)
      gravar
      reverter!(skin)
    end
  rescue => e
    AnilLanRework.log("[SKIN] receber falhou: #{e.class}: #{e.message}") rescue nil
  end

  # RECUSADA: volta ao personagem padrao.
  #
  # NAO se apaga o PNG do jogador. Ele desenhou aquilo; apagar seria destruir
  # trabalho por causa de uma decisao de moderacao, e o ficheiro sozinho no
  # disco dele nao incomoda ninguem — o que importa e nao ficar em uso.
  def reverter!(skin)
    return unless $player && $player.respond_to?(:multiplayer_skin=)
    return unless skin_em_uso == skin
    # nil, NAO string vazia.
    #
    # O refresh_charset faz `if $player&.multiplayer_skin && ...` — e "" e
    # VERDADEIRO em Ruby. Com string vazia ele definia @character_name = "" e o
    # jogador ficava INVISIVEL em vez de voltar ao padrao. Com nil a condicao
    # falha e cai no charset do metadata, que e o que se quer.
    $player.multiplayer_skin = nil
    begin
      # Deixa o proprio motor decidir o charset (a pe, de surf, de bicicleta).
      $game_player.refresh_charset if $game_player.respond_to?(:refresh_charset)
      AnilLanRework.refresh_local_follower!
      AnilLanRework::WorldSync.send_player_state
    rescue
    end
    avisar(_INTL("A skin '{1}' não foi aprovada. Seu personagem voltou ao visual padrão.", skin))
  end

  def avisar(texto)
    if defined?(AnilLanRework) && AnilLanRework.respond_to?(:enqueue_popup)
      AnilLanRework.enqueue_popup(texto, 8.0) rescue nil
    end
    AnilLanRework.log("[SKIN] #{texto}") rescue nil
  end

  # Lembrete ao entrar: a decisao pode demorar dias, e sem isto o jogador
  # esquece que esta a espera e volta a achar que os outros o veem.
  def lembrar_pendentes
    pend = carregar.select { |_, st| st == "pendente" }.keys
    return if pend.empty?
    em_uso = skin_em_uso
    alvo = pend.include?(em_uso) ? em_uso : pend.first
    avisar(_INTL("Sua skin '{1}' ainda aguarda aprovação — por enquanto só você a vê.", alvo))
  rescue
  end
end

module AnilLanRework
  module SkinAprovacaoRouter
    def self.on_packet(packet)
      AnilSkinAprovacao.receber(packet) if packet["type"].to_s == "skin_status"
    end
  end
end

AnilLanRework.log("137_Skins_Aprovacao carregado") rescue nil
