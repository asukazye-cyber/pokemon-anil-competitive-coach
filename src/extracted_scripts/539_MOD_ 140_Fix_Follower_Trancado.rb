# encoding: UTF-8
#===============================================================================
# MOD: 140_Fix_Follower_Trancado
#-------------------------------------------------------------------------------
# O Pokemon seguidor desaparecia e so voltava ao ciclar a party — e sumia outra
# vez a seguir.
#
# O MECANISMO (plugin 004 Following Pokemon EX)
#
# Ha duas maneiras de esconder o seguidor, e elas NAO sao simetricas:
#
#   toggle(forced, anim)  ->  return if $PokemonGlobal.follower_toggle_locked
#                             ...so mexe em follower_toggled
#   toggle_off(anim)      ->  esconde  E  poe follower_toggle_locked = true
#   toggle_on(anim)       ->  poe follower_toggle_locked = false  E  mostra
#
# Ou seja: quem tranca e o toggle_off, e o UNICO que destranca e o toggle_on.
# O toggle desiste em silencio enquanto a tranca estiver posta.
#
# Em "Script Additions/Field Moves.rb", ao comecar a surfar:
#
#     old_toggled = $PokemonGlobal.follower_toggled
#     FollowingPkmn.toggle_off(true) if surf_anim_1 != surf_anim_2   # tranca
#     ret = __followingpkmn__pbStartSurfing(*args)
#     FollowingPkmn.toggle(old_toggled, false)                       # nao corre
#
# A ultima linha devia repor o estado anterior, mas usa o toggle — que sai logo
# por causa da tranca posta duas linhas acima. O seguidor fica escondido E
# trancado, permanentemente. Como o estado vive no $PokemonGlobal, isto entra no
# save e sobrevive a reinicios: no save analisado (wallace-adm100, versao 949)
# estava follower_toggled=false com follower_toggle_locked=true.
#
# So a tecla de ciclar party o trazia de volta, porque essa rotina acaba em
# toggle_on. Dai o sintoma: aparece ao trocar, some no surf seguinte.
#
# O nosso MOD 106 (raid de bilhete) tem a mesma exposicao por outro caminho:
# chama toggle_off antes do teleporte e toggle_on so no regresso; se a sessao
# terminar no meio, fica igualmente preso — e o autosave de "battle_started" e
# imediato, portanto o estado trancado chega mesmo a ser gravado na nuvem.
#
# A CORRECAO
#
# Nao se reescreve o pbStartSurfing (nem se pode: e do plugin, e o
# PluginScripts.rxdata nao e gerado pelo compilar.rb). Corrige-se o RESULTADO:
# uma tranca que sobreviva a um momento de repouso e, por definicao, orfa.
#
# A distincao que torna isto seguro: desligar o seguidor DE PROPOSITO (a tecla
# do jogador) passa pelo toggle, que NAO tranca. Logo:
#
#   locked == true  +  toggled == false  +  nada a decorrer   =>  preso
#
# Uma sequencia legitima (cutscene, raid, surf a decorrer) tem sempre ou o
# interpretador de eventos a correr, ou uma transicao/batalha em curso, ou o
# jogador em cima de um veiculo — e todas essas sao verificadas antes.
#===============================================================================

module AnilFixFollowerTrancado
  # Quantos frames seguidos a condicao tem de se manter. A 40 fps sao ~1,5s.
  # Existe para nao correr o risco de apanhar o intervalo de um frame entre um
  # toggle_off e o toggle_on que lhe corresponde.
  FRAMES_ESTAVEL = 60

  # Nao se verifica a cada frame: nada disto muda depressa.
  INTERVALO = 20

  module_function

  def em_veiculo?
    return true if $PokemonGlobal.surfing
    return true if $PokemonGlobal.diving
    return true if $PokemonGlobal.bicycle
    return true if $PokemonGlobal.respond_to?(:lavasurfing) && $PokemonGlobal.lavasurfing
    false
  rescue
    true   # na duvida, nao mexer
  end

  def momento_de_repouso?
    return false if $game_temp.nil?
    return false if $game_temp.in_battle
    return false if $game_temp.transition_processing
    return false if $game_temp.player_transferring
    return false if $game_temp.message_window_showing
    return false if pbMapInterpreterRunning?
    return false if $game_player && $game_player.move_route_forcing
    true
  rescue
    false
  end

  def preso?
    return false unless defined?(FollowingPkmn)
    return false unless $PokemonGlobal
    return false unless $PokemonGlobal.follower_toggle_locked == true
    # Desligado de proposito pelo jogador nao tranca — ver o cabecalho.
    return false unless $PokemonGlobal.follower_toggled == false
    # Sem Pokemon para seguir nao ha nada a repor (party toda desmaiada, so ovos).
    return false unless FollowingPkmn.get_pokemon
    return false if em_veiculo?
    momento_de_repouso?
  rescue
    false
  end

  def verificar!
    @contador ||= 0
    @frames   ||= 0
    @frames += 1
    return if @frames < INTERVALO
    @frames = 0

    if !preso?
      @contador = 0
      return
    end

    @contador += INTERVALO
    return if @contador < FRAMES_ESTAVEL
    @contador = 0

    # toggle_on e o unico que limpa a tranca. O false tira a animacao: isto e
    # uma reparacao, nao uma acao do jogador, e a animacao aqui seria um susto.
    FollowingPkmn.toggle_on(false)
    AnilLanRework.log("[FOLLOWER] tranca orfa removida (estava escondido e trancado)") rescue nil
  rescue => e
    AnilLanRework.log("[FOLLOWER] falha ao destrancar: #{e.class}: #{e.message}") rescue nil
  end
end

class Scene_Map
  alias anil_fix_follower_update update unless method_defined?(:anil_fix_follower_update)

  def update
    anil_fix_follower_update
    AnilFixFollowerTrancado.verificar! rescue nil
  end
end

AnilLanRework.log("140_Fix_Follower_Trancado carregado") rescue nil
