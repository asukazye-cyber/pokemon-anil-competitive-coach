#===============================================================================
# MOD: 117_Follower_Refresh_Party.rb
#-------------------------------------------------------------------------------
# Atualiza o follower na hora em que a equipe muda.
#
# O PROBLEMA
# O Following Pokemon EX so chama FollowingPkmn.refresh em pbStartOver, remove,
# remove_event, clear e no toggle do menu de opcoes. Nao ha nada para "a equipe
# mudou". Entao, ao trazer um Pokemon da caixa para o primeiro lugar, o sprite
# so trocava quando algo ALHEIO forcava o refresh -- abrir um menu ou mudar de
# mapa. Ate la o jogador seguia com o follower antigo.
#
# ONDE ENTRA
# Nas duas telas que conseguem mudar quem lidera a equipe:
#   PokemonStorageScreen#pbStartScreen  (PC e o item Box Link)
#   PokemonPartyScreen#pbPokemonScreen  (reordenar a propria equipe)
#
# POR QUE COMPARAR ANTES E DEPOIS
# refresh() reconstroi o evento e o sprite do follower; chamar sempre que se
# fecha a caixa daria um engasgo visivel mesmo quando nada mudou. A assinatura
# cobre identidade E aparencia: trocar de Pokemon, evoluir, mudar forma, genero,
# shiny/super shiny, o tom (hue) ou virar ovo.
#
# O follower e o first_able_pokemon -- e o que o plugin usa (Event_Sprite) e o
# que o codigo multiplayer usa (visible_follower_pokemon). Nao e simplesmente
# party[0]: um primeiro Pokemon desmaiado nao lidera.
#===============================================================================

def anil_follower_assinatura
  # ⚠️ A assinatura tem de olhar para o MESMO Pokemon que o follower mostra.
  # Se ela continuasse a seguir o primeiro apto, montar e desmontar nao mudava
  # a assinatura e o follower nunca era refrescado — ficaria o bicho errado.
  pkmn = if defined?(AnilMontaria) && (AnilMontaria.montado? rescue false)
           (AnilMontaria.pokemon_do_follower rescue nil)
         else
           ($player.first_able_pokemon rescue nil) || ($player.party.first rescue nil)
         end
  return nil unless pkmn
  [
    (pkmn.personalID              rescue nil),
    (pkmn.species                 rescue nil),
    (pkmn.form                    rescue 0),
    (pkmn.gender                  rescue 0),
    (pkmn.shiny?                  rescue false),
    (pkmn.super_shiny?            rescue false),
    (pkmn.cached_super_shiny_hue  rescue nil),
    (pkmn.egg?                    rescue false)
  ]
rescue
  nil
end

def anil_follower_atualizar!(antes)
  return if antes == anil_follower_assinatura   # nada mudou: nao reconstroi
  return unless defined?($game_map) && $game_map
  if defined?(FollowingPkmn) && FollowingPkmn.respond_to?(:refresh)
    FollowingPkmn.refresh(false)
  end
  # Sem isto o sprite trocaria so na tela de quem mexeu: os outros jogadores
  # continuariam vendo o follower antigo ate o proximo sync de mapa.
  if defined?(AnilLanRework) && AnilLanRework.respond_to?(:refresh_local_follower!)
    AnilLanRework.refresh_local_follower!
  end
rescue => e
  AnilLanRework.log("117_Follower_Refresh_Party: #{e}") rescue nil
end

#-------------------------------------------------------------------------------
# Os dois envelopes PRECISAM ser aplicados depois do runPlugins: dois plugins
# REDEFINEM (nao envolvem) justamente estes metodos, e como eles sao avaliados
# no Main, depois de todos os scripts, um alias feito aqui em cima seria
# simplesmente descartado:
#
#   Modular UI Scenes        -> PokemonPartyScreen#pbPokemonScreen
#   [MUI] Enhanced Pokemon UI -> PokemonStorageScreen#pbStartScreen
#-------------------------------------------------------------------------------
module PluginManager
  class << self
    alias __anil_follower_runPlugins runPlugins unless method_defined?(:__anil_follower_runPlugins)
    def runPlugins(*args)
      __anil_follower_runPlugins(*args)

      begin
        ::PokemonStorageScreen.class_eval do
          unless method_defined?(:anil_follower_pbStartScreen)
            alias anil_follower_pbStartScreen pbStartScreen
            def pbStartScreen(*args)
              antes = anil_follower_assinatura
              ret = anil_follower_pbStartScreen(*args)
              anil_follower_atualizar!(antes)
              ret
            end
          end
        end
      rescue => e
        AnilLanRework.log("117: falha ao envolver PokemonStorageScreen: #{e}") rescue nil
      end

      begin
        ::PokemonPartyScreen.class_eval do
          unless method_defined?(:anil_follower_pbPokemonScreen)
            alias anil_follower_pbPokemonScreen pbPokemonScreen
            def pbPokemonScreen(*args)
              antes = anil_follower_assinatura
              ret = anil_follower_pbPokemonScreen(*args)
              anil_follower_atualizar!(antes)
              ret
            end
          end
        end
      rescue => e
        AnilLanRework.log("117: falha ao envolver PokemonPartyScreen: #{e}") rescue nil
      end
    end
  end
end
