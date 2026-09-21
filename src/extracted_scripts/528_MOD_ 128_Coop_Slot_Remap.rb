#===============================================================================
# MOD: 128_Coop_Slot_Remap.rb
#-------------------------------------------------------------------------------
# Corrige os efeitos que guardam INDICE DE SLOT quando o coop reposiciona um
# Pokemon que continua vivo.
#
#-------------------------------------------------------------------------------
# O CASO REAL (relatado 2026-07-30)
#
#   1. O aliado perdeu todos os Pokemon e saiu para o centro Pokemon.
#   2. O jogador escolheu o Golem, da SUA party, para ocupar o lugar vago.
#   3. Ao entrar o Golem, o VENUSAUR — que estava VIVO — mudou de posicao.
#   4. O Leech Seed que o Venusaur tinha lancado passou a alimentar o Golem.
#
# Porque: `effects[PBEffects::LeechSeed]` guarda o NUMERO do slot, nao o Pokemon.
# O numero deixou de ser do Venusaur e passou a ser do Golem, e a vida foi com
# ele.
#
# Nao e comportamento canonico. Nos jogos oficiais o efeito liga-se a posicao, e
# alimentar quem la esta seria correto — mas so quando o lancador SAI. Aqui ele
# ficou e foi ELE que mudou de posicao. A vida e dele.
#
#-------------------------------------------------------------------------------
# PORQUE DETECTA EM VEZ DE ENGANCHAR NO SITIO QUE REPOSICIONA
#
# O motor NUNCA renumera slots: `pbReplace` mantem o idxBattler e o
# `pbGetReplacementPokemonIndex` so percorre a fatia do dono. Logo a renumeracao
# vem do coop — mas nao foi possivel identificar a linha exata que a faz.
#
# Em vez de adivinhar esse sitio, comparamos o campo ANTES e DEPOIS: se um
# Pokemon aparecer noutro slot, sabemos que houve reposicionamento e traduzimos
# os efeitos. Fica correto independentemente de ONDE a renumeracao acontece — e
# continua correto se esse codigo mudar.
#
#-------------------------------------------------------------------------------
# AMBITO: SO REMAPEIA
#
# Trata unicamente o caso provado: o Pokemon MUDOU de slot e continua em campo.
#
# NAO limpa efeitos cujo referido desapareceu. Seria preciso adivinhar o valor
# "nenhum" de cada um dos 16 efeitos (nem todos usam -1) e um sentinela errado
# faria pior do que o bug. Esse caso — o lancador sair — e alias o unico em que
# alimentar quem ocupa a posicao E canonico.
#
#-------------------------------------------------------------------------------
# PVP: INTOCADO
#
# Tudo corre dentro de `ctx.mode == :coop`. Sem contexto coop, o metodo original
# e chamado e nada mais acontece — nem a fotografia se tira.
#===============================================================================

module CoopSlotRemap
  # Extraidos do motor com:  effects\[PBEffects::(\w+)\]\s*=\s*[^=]*\.index
  # Reproduzir a busca quando o Essentials for atualizado.
  EFEITOS_COM_INDICE = %w[
    Attract BideTarget Commander CounterTarget DestinyBondTarget
    FutureSightUserIndex JawLock LeechSeed LockOnPos MeanLook
    MirrorCoatTarget Octolock PerishSongUser SkyDrop SyrupyUser TrappingUser
  ].freeze

  class << self
    # slot -> objeto Pokemon em campo. A identidade do OBJETO e a chave: e o
    # unico jeito de saber que "e o mesmo Pokemon noutro sitio". Especie nao
    # serve (pode haver dois iguais), nem indice de party (muda na reordenacao).
    def fotografar(battlers)
      foto = {}
      Array(battlers).each do |b|
        next unless b && (b.pokemon rescue nil)
        foto[b.index.to_i] = b.pokemon
      end
      foto
    end

    # { slot_antigo => slot_novo } apenas para quem REALMENTE mudou de sitio.
    def construir_mapa(antes, depois)
      return {} unless antes.is_a?(Hash) && depois.is_a?(Hash)
      onde_esta_agora = {}
      depois.each { |slot, pkmn| onde_esta_agora[pkmn.object_id] = slot }
      mapa = {}
      antes.each do |slot_antigo, pkmn|
        novo = onde_esta_agora[pkmn.object_id]
        next if novo.nil? || novo == slot_antigo
        mapa[slot_antigo] = novo
      end
      mapa
    end

    # Traduz os efeitos. Devolve quantos foram corrigidos.
    def aplicar!(battlers, mapa)
      return 0 if !mapa.is_a?(Hash) || mapa.empty?
      corrigidos = 0
      Array(battlers).each do |b|
        efeitos = (b && b.effects rescue nil)
        next unless efeitos
        EFEITOS_COM_INDICE.each do |nome|
          chave = (PBEffects.const_get(nome) rescue nil)
          next if chave.nil?
          valor = efeitos[chave]
          # So indices validos. Um efeito desligado costuma ser -1 ou nil, e
          # nesses casos nao ha nada para traduzir.
          next unless valor.is_a?(Integer) && valor >= 0
          novo = mapa[valor]
          next if novo.nil?
          efeitos[chave] = novo
          corrigidos += 1
          registrar("efeito #{nome} do slot #{b.index}: #{valor} -> #{novo}")
        end
      end
      corrigidos
    end

    # Faz o ciclo todo a partir de uma fotografia previa.
    def reconciliar!(battlers, antes)
      return 0 if antes.nil?
      mapa = construir_mapa(antes, fotografar(battlers))
      return 0 if mapa.empty?
      registrar("reposicionamento detectado: #{mapa.inspect}")
      aplicar!(battlers, mapa)
    end

    def registrar(msg)
      AnilLanRework.log("[SLOT_REMAP] #{msg}") if defined?(AnilLanRework)
    rescue
    end
  end
end

#-------------------------------------------------------------------------------
# Gancho: o pbEORSwitch e onde o coop preenche o slot do aliado que saiu.
#
# `method_defined?` e nao `respond_to?` — aqui o self e a classe e estes sao
# metodos de INSTANCIA. (No 127 esse engano fez com que um gancho nunca chegasse
# a ser instalado e os dois jogadores jogassem por caminhos diferentes.)
#-------------------------------------------------------------------------------
class Battle
  unless method_defined?(:coop_slot_remap_original_pbEORSwitch)
    alias coop_slot_remap_original_pbEORSwitch pbEORSwitch
  end

  def pbEORSwitch(favorDraws = false)
    ctx = (AnilLanRework::BattleSync.active_context rescue nil)
    em_coop = !ctx.nil? && ctx.mode.to_s == "coop"
    antes = em_coop ? CoopSlotRemap.fotografar(@battlers) : nil

    resultado = coop_slot_remap_original_pbEORSwitch(favorDraws)

    CoopSlotRemap.reconciliar!(@battlers, antes) if em_coop
    resultado
  end
end
