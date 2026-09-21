# encoding: utf-8
#===============================================================================
# 130 — TRACE DO "RECUPERAR PARTIDA"   (diagnostico, sem mudar comportamento)
#-------------------------------------------------------------------------------
# O SINTOMA
#
# O servidor autoriza e envia o save (visto no log da VPS: "Recuperacao de save
# autorizada para codigo 111111 -> wallace-adm100"), o cliente mostra "Partida
# recuperada com sucesso! Iniciando jogo..." e depois PARA: o C so faz buzzer e o
# jogo continua a ser o da sessao anterior — o multiplayer_player.txt volta a
# aparecer com o id da outra conta.
#
# POR QUE ESTE FICHEIRO EXISTE
#
# O `Game.load` do recuperar_partida corre dentro de um `begin/rescue => e`
# generico (100_Multiplayer_Whitelist ~899) que engole a excecao e tenta mostra-la
# com pbMessage. So que os dois chamadores (UI_Load e o plugin Multi Save) fazem
# `@scene.pbEndScene` ANTES de chamar o recover — logo a mensagem de erro e
# desenhada sobre uma cena ja destruida e pode simplesmente nao aparecer. O erro
# real fica invisivel.
#
# Aqui embrulha-se o Game.load para REGISTAR a excecao (classe, mensagem e
# backtrace) e deixa-la seguir na mesma. Nada muda de comportamento: so se
# observa.
#
#-------------------------------------------------------------------------------
# LOG PROPRIO — NAO LIGAR OS LOGS GLOBAIS
#
# Nome de ficheiro NOVO, fora da lista BLOCKED do 0000_Disable_Debug_Logs, e
# escrito com uma unica abertura por linha em caminhos raros (recover e load), nao
# por frame. Ligar $ENABLE_DEBUG_LOGS ou $anil_debug_log_enabled para diagnosticar
# isto seria contraproducente: ja se comprovou (2026-08-01) que desbloquear todos
# os ficheiros pesados de uma vez TRAVA o proprio recuperar partida — ligava-se a
# causa por cima do sintoma.
#
# Depois de resolvido, este ficheiro pode ser apagado sem deixar rasto.
#===============================================================================

module AnilRecoverTrace
  FICHEIRO = "recover_trace.txt"

  class << self
    def log(msg)
      return unless (anil_diagnostico_ligado? rescue false)
      linha = "[#{Time.now.strftime('%H:%M:%S.%L')}] #{msg}"
      File.open(FICHEIRO, "a") { |f| f.puts(linha) }
    rescue
    end

    # Estado que interessa comparar ANTES e DEPOIS do Game.load. Se o load pegar,
    # o nome tem de mudar para o do save recuperado; se continuar igual, o load
    # nao tomou efeito e e isso que faz o multiplayer_player.txt voltar ao id
    # antigo.
    def estado(rotulo)
      nome = (defined?($player) && $player) ? ($player.name.to_s rescue "?") : "(sem $player)"
      oid  = (defined?($PokemonGlobal) && $PokemonGlobal) ? ($PokemonGlobal.online_id.to_s rescue "?") : "?"
      pid  = (AnilLanRework.get_player_id rescue "?")
      cfg  = (File.exist?("multiplayer_player.txt") ? File.read("multiplayer_player.txt").gsub(/\s+/, "|") : "(sem ficheiro)") rescue "?"
      caminho = (SaveData::FILE_PATH.to_s rescue "?")
      log("#{rotulo}: player=#{nome.inspect} online_id=#{oid.inspect} runtime_id=#{pid.inspect}")
      log("#{rotulo}: SaveData::FILE_PATH=#{caminho.inspect}")
      log("#{rotulo}: multiplayer_player.txt=#{cfg.inspect}")
    rescue => e
      log("#{rotulo}: falhou a ler estado (#{e.class}: #{e.message})")
    end
  end
end

#-------------------------------------------------------------------------------
# Game.load — o ponto cego. Regista entrada, saida e a excecao COMPLETA.
#-------------------------------------------------------------------------------
module Game
  class << self
    alias anil_recover_trace_original_load load unless method_defined?(:anil_recover_trace_original_load)

    def load(save_data)
      AnilRecoverTrace.log("---- Game.load INICIO (save_data=#{save_data.class}, chaves=#{(save_data.is_a?(Hash) ? save_data.keys.length : -1)})")
      AnilRecoverTrace.estado("antes do Game.load")
      resultado = anil_recover_trace_original_load(save_data)
      AnilRecoverTrace.estado("depois do Game.load")
      AnilRecoverTrace.log("---- Game.load FIM OK (scene=#{$scene.class})")
      resultado
    rescue Exception => e
      # Exception, nao StandardError: um NoMethodError num validador ou um
      # SystemStackError tambem tem de aparecer aqui. Re-lanca sempre — quem
      # decide o que fazer continua a ser o chamador.
      AnilRecoverTrace.log("---- Game.load EXPLODIU: #{e.class}: #{e.message}")
      Array(e.backtrace).first(12).each { |l| AnilRecoverTrace.log("        #{l}") }
      AnilRecoverTrace.estado("apos a falha do Game.load")
      raise
    end
  end
end

#-------------------------------------------------------------------------------
# recuperar_partida — marca inicio/fim para separar tentativas no ficheiro e
# mostrar se o metodo chegou sequer ao fim.
#-------------------------------------------------------------------------------
if defined?(Multiplayer_Whitelist)
  module Multiplayer_Whitelist
    class << self
      alias anil_recover_trace_original_recuperar recuperar_partida unless method_defined?(:anil_recover_trace_original_recuperar)

      def recuperar_partida
        AnilRecoverTrace.log("=" * 70)
        AnilRecoverTrace.log("recuperar_partida INICIO")
        AnilRecoverTrace.estado("entrada")
        r = anil_recover_trace_original_recuperar
        AnilRecoverTrace.log("recuperar_partida FIM (devolveu #{r.inspect[0, 60]})")
        AnilRecoverTrace.estado("saida")
        r
      rescue Exception => e
        AnilRecoverTrace.log("recuperar_partida EXPLODIU: #{e.class}: #{e.message}")
        Array(e.backtrace).first(12).each { |l| AnilRecoverTrace.log("        #{l}") }
        raise
      end
    end
  end
end

#-------------------------------------------------------------------------------
# SaveData.read_from_file — diz QUAL ficheiro o recover releu antes do Game.load.
# O SaveData::FILE_PATH deste projeto e dinamico (resolve-se pelo id do jogador),
# entao saber o caminho exato importa: se ele apontar para o save da sessao
# antiga, o Game.load recarrega o jogo errado e todo o resto encaixa.
#-------------------------------------------------------------------------------
if defined?(SaveData) && SaveData.respond_to?(:read_from_file)
  module SaveData
    class << self
      alias anil_recover_trace_original_read read_from_file unless method_defined?(:anil_recover_trace_original_read)

      def read_from_file(path)
        dados = anil_recover_trace_original_read(path)
        AnilRecoverTrace.log("SaveData.read_from_file(#{path.inspect}) -> #{dados.class} chaves=#{(dados.is_a?(Hash) ? dados.keys.length : -1)}")
        if dados.is_a?(Hash) && dados[:player]
          AnilRecoverTrace.log("   player do ficheiro: nome=#{(dados[:player].name rescue '?').inspect} online_id=#{(dados[:player].online_id rescue '?').inspect}")
        end
        dados
      rescue Exception => e
        AnilRecoverTrace.log("SaveData.read_from_file(#{path.inspect}) EXPLODIU: #{e.class}: #{e.message}")
        raise
      end
    end
  end
end

AnilRecoverTrace.log("130_Recover_Trace carregado") rescue nil
