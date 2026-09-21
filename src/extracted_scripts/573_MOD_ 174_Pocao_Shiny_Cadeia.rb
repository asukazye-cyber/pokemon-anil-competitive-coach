# encoding: UTF-8
#===============================================================================
# MOD: 174_Pocao_Shiny_Cadeia
#-------------------------------------------------------------------------------
# A Pocao Shiny passa a esperar pela especie da CADEIA, em vez de pegar no
# primeiro selvagem que aparecer.
#
# ⚠️ O PROBLEMA QUE ISTO RESOLVE.
#
# Quem persegue um Pokemon usa a pocao e ve o brilho cair num Rattata que
# calhou nascer ao lado. O item mais caro do jogo gasto por azar, sem nada a
# fazer.
#
# ⚠️ OS LENDARIOS CONTINUAM COMO ESTAVAM, E ISSO SAI DE GRACA.
#
# Ninguem encadeia um lendario — ele aparece uma vez e nao repete. Se a pocao so
# respeitasse a cadeia, matava o uso que a torna valiosa.
#
# Mas os lendarios NAO passam por nenhum dos dois caminhos abaixo: eles tem o
# seu proprio consumidor, no plugin "Combates Legendarios", que este MOD nao
# toca. Nao foi preciso detectar flags nem abrir excepcoes — bastou nao mexer.
#
# ⚠️ SAO TRES CONSUMIDORES, EM TRES PLUGINS DIFERENTES.
#
#   Misc Scripts Añil ...... modo classico (sem encontros visiveis)
#   VOE script ............. encontros visiveis (o modo normal deste jogo)
#   Combates Legendarios ... lendarios por evento          <- intocado
#
# Cada um limpa o interruptor 122 a sua maneira. Trata-los aos dois primeiros
# de formas diferentes nao e feio: eles sao mesmo diferentes.
#===============================================================================

module AnilPocaoCadeia
  ACTIVO = true

  module_function

  def log(t)
    AnilLanRework.log("[POCAO] #{t}") rescue nil
  end

  def interruptor
    (defined?(SHINYZADOR_SWTICH) ? SHINYZADOR_SWTICH : 122)
  end

  def ligada?
    ($game_switches[interruptor] rescue false) == true
  rescue
    false
  end

  # ⚠️ Sem cadeia, mantem-se o comportamento antigo.
  #
  # Quem nunca soube desta mudanca nao pode ver o item piorar. A regra so entra
  # em accao para quem esta mesmo a encadear alguma coisa.
  def e_o_alvo?(pkmn)
    return true unless ACTIVO && pkmn
    c = ($PokemonGlobal.catchcombo rescue nil)
    return true unless c.is_a?(Array) && c[0].to_i > 0 && c[1] && c[1] != 0
    c[1].to_s == pkmn.species.to_s
  rescue
    true
  end

  #-----------------------------------------------------------------------------
  # 1. MODO CLASSICO
  #
  # O plugin regista `EventHandlers.add(:on_wild_pokemon_created, :shinyzador)`.
  # Registar a MESMA chave depois dele substitui o handler — nao acumula.
  #-----------------------------------------------------------------------------
  def instalar_classico!
    return false unless defined?(EventHandlers)
    EventHandlers.remove(:on_wild_pokemon_created, :shinyzador) rescue nil
    EventHandlers.add(:on_wild_pokemon_created, :shinyzador, proc { |pkmn|
      begin
        next unless ligada?
        next if ($PokemonSystem.salvajes_visibles_en_ow? rescue false)
        # Nao e o alvo: a pocao FICA GUARDADA. Nao se toca no interruptor.
        next unless e_o_alvo?(pkmn)
        pkmn.shiny = true
        pkmn.super_shiny = false
        $game_switches[interruptor] = false
        log("gasta em #{pkmn.species} (classico)")
      rescue
        nil
      end
    })
    true
  rescue => e
    log("falha no classico: #{e.class}: #{e.message}")
    false
  end
end

#-------------------------------------------------------------------------------
# 2. ENCONTROS VISIVEIS
#
# ⚠️ ESCONDE-SE O INTERRUPTOR, EM VEZ DE REESCREVER O SPAWN.
#
# Aqui quem consome a pocao esta no meio do `spawnPokeEvent` do VOE, dentro de
# um `elsif` com mais de vinte linhas a volta. Copiar esse metodo para o
# corrigir era herdar a manutencao dele para sempre.
#
# Em vez disso: se a pocao esta ligada e este Pokemon NAO e o alvo, desliga-se o
# interruptor durante a chamada e volta-se a liga-lo a seguir. O plugin corre
# como se a pocao nao existisse, e ela fica intacta para o proximo.
#
# Entra no MOD 070, que ja envolve o spawnPokeEvent para o sorteio autoritativo.
#-------------------------------------------------------------------------------
module AnilPocaoCadeia
  module_function

  def instalar_visiveis!
    return false unless defined?(Game_Map)
    return false if Game_Map.method_defined?(:anil_pocao_orig_spawnPokeEvent)
    return false unless Game_Map.method_defined?(:spawnPokeEvent)
    Game_Map.class_eval do
      alias_method :anil_pocao_orig_spawnPokeEvent, :spawnPokeEvent

      def spawnPokeEvent(x, y, pokemon)
        guardar = false
        begin
          sw = AnilPocaoCadeia.interruptor
          if AnilPocaoCadeia.ligada? && !AnilPocaoCadeia.e_o_alvo?(pokemon)
            $game_switches[sw] = false
            guardar = true
          end
        rescue
          guardar = false
        end
        begin
          anil_pocao_orig_spawnPokeEvent(x, y, pokemon)
        ensure
          # ⚠️ No `ensure`: se o spawn rebentar a meio, a pocao NAO se perde.
          ($game_switches[AnilPocaoCadeia.interruptor] = true) rescue nil if guardar
        end
      end
    end
    true
  rescue => e
    log("falha nos visiveis: #{e.class}: #{e.message}")
    false
  end
end

module AnilLanRework
  class << self
    unless method_defined?(:anil_pocao_orig_apply_post_plugin_patches)
      alias_method :anil_pocao_orig_apply_post_plugin_patches, :apply_post_plugin_patches rescue nil
    end

    def apply_post_plugin_patches
      anil_pocao_orig_apply_post_plugin_patches rescue nil
      AnilPocaoCadeia.instalar_classico! rescue nil
      AnilPocaoCadeia.instalar_visiveis! rescue nil
    end
  end
end
