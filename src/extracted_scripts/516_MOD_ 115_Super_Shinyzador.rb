#===============================================================================
# MOD: 115_Super_Shinyzador.rb
#-------------------------------------------------------------------------------
# Faz o Super Shinyzador funcionar nos DOIS modos de encontro.
#
# ATENCAO A ESTA OPCAO, QUE E INVERTIDA:
#   $PokemonSystem.salvajes_visibles_en_ow == 0  ->  VOE LIGADO  (ve os
#                                                    selvagens no mapa)
#   == 1 (ou ausente)                           ->  VOE DESLIGADO (classico)
# O plugin define "salvajes_visibles_en_ow?" como "== 0", e o menu e um
# EnumOption ["Si", "No"] onde o indice 0 e "Si". Ler isso ao contrario faz o
# item parecer quebrado, porque o codigo cai sempre no ramo errado.
#
# COMO CADA MODO MARCA O POKEMON
#   Classico: o Pokemon nasce em pbGenerateWildPokemon, que dispara
#             :on_wild_pokemon_created. Quem marca e o handler daqui.
#   VOE:      o Pokemon tambem nasce ali, MAS logo depois o plugin roda
#             Game_Map#spawnPokeEvent, que zera shiny/super_shiny e so entao
#             consulta a switch 38 para remarcar. Se o handler daqui marcasse
#             e apagasse a switch antes, o plugin apagaria a marca e nao teria
#             mais switch para reler -- nada de super shiny. Por isso, em VOE,
#             este arquivo NAO toca no Pokemon: deixa o plugin marcar.
#
# E QUEM APAGA A SWITCH NO MODO VOE?
# O plugin apaga a switch do Shinyzador comum (linha 1389 do VOE script) mas
# ESQUECE a do super. Sem isso o efeito viraria permanente: todo selvagem
# nasceria super shiny para sempre. O wrapper de spawnPokeEvent no fim deste
# arquivo apaga depois que o plugin usou.
#===============================================================================

def anil_ssz_switches
  sw_super = (defined?(Settings::SUPER_SHINY_WILD_POKEMON_SWITCH) ? Settings::SUPER_SHINY_WILD_POKEMON_SWITCH : 38)
  sw_alt   = (defined?(SUPERSHINYZADOR_SWITCH) ? SUPERSHINYZADOR_SWITCH : 123)
  [sw_super, sw_alt]
end

def anil_ssz_voe_ligado?
  $PokemonSystem.salvajes_visibles_en_ow.to_i == 0
rescue
  false
end

if defined?(ItemHandlers)

  ItemHandlers::UseFromBag.add(:SUPERSHINYZADOR, proc { |item|
    sw_super, sw_alt = anil_ssz_switches
    sw_shiny = (defined?(SHINYZADOR_SWTICH) ? SHINYZADOR_SWTICH : 122)

    if $game_switches[sw_super] || $game_switches[sw_alt] || $game_switches[sw_shiny]
      pbMessage(_INTL("Você já usou uma poção para alterar a aparência dos Pokémon selvagens."))
      next 0   # nao consome
    else
      $game_switches[sw_super] = true
      $game_switches[sw_alt]   = true
      pbMessage(_INTL("O próximo Pokémon selvagem que você encontrar será Super Shiny!"))
      next 1   # consome
    end
  }) rescue nil

  # ⚠️ A POCAO ESPERA PELA ESPECIE DA CADEIA, E NAO PELO PRIMEIRO QUE VIER.
  #
  # Antes ela pegava no proximo selvagem, fosse ele qual fosse. Quem estava a
  # perseguir um Pokemon usava a pocao e via o brilho cair num Rattata que
  # calhou nascer ao lado — o item mais caro do jogo gasto por azar.
  #
  # ⚠️ MAS OS LENDARIOS PASSAM SEMPRE.
  #
  # Ninguem encadeia um lendario: ele aparece uma vez e nao repete. Se a pocao
  # so respeitasse a cadeia, a caca a lendarios shiny — que e a razao principal
  # por que se guarda uma pocao — deixava de funcionar. Entao um lendario ativa
  # o efeito haja cadeia ou nao. Nao e uma excepcao: e a segunda regra.
  #
  # E sem cadeia nenhuma mantem-se o comportamento antigo, para quem nunca soube
  # desta mudanca nao ver o item piorar.
  def anil_ssz_lendario?(pkmn)
    d = (GameData::Species.get(pkmn.species) rescue nil)
    return false unless d
    (d.has_flag?("Legendary") rescue false) || (d.has_flag?("Mythical") rescue false)
  rescue
    false
  end

  def anil_ssz_e_o_alvo?(pkmn)
    return true if anil_ssz_lendario?(pkmn)
    c = ($PokemonGlobal.catchcombo rescue nil)
    return true unless c.is_a?(Array) && c[0].to_i > 0 && c[1] && c[1] != 0
    c[1].to_s == pkmn.species.to_s
  rescue
    true
  end

  EventHandlers.add(:on_wild_pokemon_created, :super_shinyzador,
    proc { |pkmn|
      sw_super, sw_alt = anil_ssz_switches
      next unless $game_switches[sw_super] || $game_switches[sw_alt]
      # Em VOE quem marca e o spawnPokeEvent do plugin. Marcar aqui seria
      # desfeito por ele um instante depois.
      next if anil_ssz_voe_ligado?
      # Nao e o alvo: a pocao FICA GUARDADA e espera. Nao se consome nada.
      next unless anil_ssz_e_o_alvo?(pkmn)
      pkmn.super_shiny = true   # o setter ja forca shiny = true
      $game_switches[sw_super] = false
      $game_switches[sw_alt]   = false
    }
  ) rescue nil

end

#-------------------------------------------------------------------------------
# Modo VOE: apaga a switch depois que o plugin a usou.
# Precisa rodar apos o runPlugins porque Game_Map#spawnPokeEvent so existe
# depois que o plugin e avaliado. Mesmo padrao do 070_Multiplayer_OW_Spawns_Sync,
# que tambem envolve este metodo -- este arquivo carrega depois dele, entao o
# wrapper daqui fica por fora e enxerga o spawn inteiro.
#-------------------------------------------------------------------------------
module PluginManager
  class << self
    alias __anil_ssz_runPlugins runPlugins unless method_defined?(:__anil_ssz_runPlugins)
    def runPlugins(*args)
      __anil_ssz_runPlugins(*args)
      begin
        ::Game_Map.class_eval do
          if method_defined?(:spawnPokeEvent) && !method_defined?(:anil_ssz_original_spawnPokeEvent)
            alias anil_ssz_original_spawnPokeEvent spawnPokeEvent
            def spawnPokeEvent(x, y, pokemon)
              sw_super, sw_alt = anil_ssz_switches
              usou = ($game_switches[sw_super] || $game_switches[sw_alt]) rescue false
              ret = anil_ssz_original_spawnPokeEvent(x, y, pokemon)
              if usou
                $game_switches[sw_super] = false
                $game_switches[sw_alt]   = false
              end
              ret
            end
          end
        end
      rescue => e
        AnilLanRework.log("115_Super_Shinyzador: falha ao envolver spawnPokeEvent: #{e}") rescue nil
      end
    end
  end
end
