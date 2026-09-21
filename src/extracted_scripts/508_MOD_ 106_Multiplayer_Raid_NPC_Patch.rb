# encoding: utf-8
# ==============================================================================
# MOD_106_Multiplayer_Raid_NPC_Patch
# ==============================================================================
# Modifica o NPC do Cable Club nos Centros Pokémon para atuar como Lobby de Raids.
# Teleporta o jogador para a Sala 218 (Lobby PVP antigo) e inicia a batalha de Raid.
# ==============================================================================

# 1. Modificar o $game_temp para guardar o estado da Raid ativa
class Game_Temp
  attr_accessor :active_raid_boss
end

# 2. Restaurar e sobrescrever o Common Event 12 na inicialização do jogo
module Game
  class << self
    alias __raid_cable_club_initialize initialize unless method_defined?(:__raid_cable_club_initialize)
    def initialize(*args)
      __raid_cable_club_initialize(*args)
      
      # Modifica o Common Event 12 para chamar o nosso método pbRaidLobby
      if $data_common_events && $data_common_events[12]
        cmd_script = RPG::EventCommand.new
        cmd_script.instance_variable_set(:@code, 355)
        cmd_script.instance_variable_set(:@indent, 0)
        cmd_script.instance_variable_set(:@parameters, ["pbRaidLobby"])
        
        cmd_end = RPG::EventCommand.new
        cmd_end.instance_variable_set(:@code, 0)
        cmd_end.instance_variable_set(:@indent, 0)
        cmd_end.instance_variable_set(:@parameters, [])
        
        $data_common_events[12].instance_variable_set(:@list, [cmd_script, cmd_end])
      end
    end
  end
end

# Lendarios e miticos nao entram na Raid da Torre.
#
# A flag vem do PBS (pokemon.txt / pokemon_forms.txt), nao de uma lista escrita a
# mao: assim um lendario novo fica barrado sozinho, sem ninguem se lembrar de o
# acrescentar aqui. Sao 69 especies com Legendary, mais as Mythical.
#
# Paradox e UltraBeast NAO estao barrados — nao foram pedidos.
def pbRaidLendariosNaEquipe
  Array($player && $player.party).compact.select do |pkmn|
    dados = (GameData::Species.get(pkmn.species) rescue nil)
    next false unless dados
    (dados.has_flag?("Legendary") rescue false) || (dados.has_flag?("Mythical") rescue false)
  end
end

# 3. Definição da função pbRaidLobby (chamada ao interagir com o NPC)
def pbRaidLobby
  # Verifica quais bilhetes o jogador possui na mochila
  tickets = []
  tickets << [:BILHETELARANJA, "Guzman"] if $bag.has?(:BILHETELARANJA)
  tickets << [:BILHETEGIOVANNI, "Giovanni"] if $bag.has?(:BILHETEGIOVANNI)
  tickets << [:BILHETEMISTY, "Misty"] if $bag.has?(:BILHETEMISTY)
  tickets << [:BILHETEBROCK, "Brock"] if $bag.has?(:BILHETEBROCK)
  tickets << [:BILHETESURGE, "Lt. Surge"] if $bag.has?(:BILHETESURGE)
  tickets << [:BILHETEERIKA, "Erika"] if $bag.has?(:BILHETEERIKA)
  tickets << [:BILHETEBLAINE, "Blaine"] if $bag.has?(:BILHETEBLAINE)
  tickets << [:BILHETEURANO, "Urano"] if $bag.has?(:BILHETEURANO)
  
  # ⚠️ DUAS CONDIÇÕES, E A PRIMEIRA É INVISÍVEL.
  #
  # A caverna precisa do bilhete dela, como qualquer raid — e precisa do
  # amuleto de teste, que é o que decide se ela EXISTE para este jogador. Sem
  # amuleto a opção não aparece na lista, e o NPC comporta-se exactamente como
  # sempre se comportou: quem não a devia conhecer não descobre que ela existe
  # por ver uma linha a mais no menu.
  #
  # O `defined?` é o que mantém este ficheiro a funcionar sem o MOD 192 — se
  # ele um dia sair do build, isto fica falso e o NPC volta ao que era.
  tem_caverna = begin
    defined?(AnilRaidCaverna) && AnilRaidCaverna.disponivel? &&
      ($bag.has?(AnilRaidCaverna::BILHETE) rescue false)
  rescue
    false
  end

  # ⚠️ A caverna sozinha também abre a boca do NPC. Sem esta segunda metade,
  # quem tivesse só o bilhete da caverna ouvia "precisa de um Bilhete de Raid"
  # e ficava sem perceber porquê — o bilhete estava mesmo na mochila.
  if tickets.empty? && !tem_caverna
    pbMessage(_INTL("Olá! Eu gerencio as Raids de Elite da Torre."))
    pbMessage(_INTL("Para desafiar um chefe, você precisa possuir um Bilhete de Raid (dropado nas rotas)."))
    return false
  end
  
  # Mostra a lista de opções com base nos bilhetes possuídos
  commands = []
  tickets.each do |item, boss_name|
    commands << _INTL("Desafiar {1} (1 Bilhete)", boss_name)
  end
  # ⚠️ O NPC ANUNCIAVA UMA MASMORRA E JA HA DUAS.
  #
  # Quem lesse este menu nao tinha como saber que o safari existia: dizia
  # "Caverna Instável", e o bilhete chamava-se "Bilhete da Caverna". A escolha
  # estava la — o `perguntar!` abre-a — mas ninguem abre uma porta que nao sabe
  # que tem duas saidas.
  commands << _INTL("Entrar numa masmorra (1 Bilhete)") if tem_caverna
  commands << _INTL("Sair")
  
  choice = pbMessage(_INTL("Qual Raid de Elite você deseja iniciar?"), commands, commands.length - 1)
  
  # A caverna fica logo a seguir aos chefes, antes do "Sair". O `perguntar!`
  # trata do resto: confirma, faz escolher os dois Pokémon, gasta o bilhete e
  # salta. Nada disto passa pelo caminho das Raids de Elite — não há sala de
  # duelo, não há chefe, e o retorno é o da caverna.
  if tem_caverna && choice == tickets.length
    return AnilRaidCaverna.perguntar!
  end

  if choice >= 0 && choice < tickets.length
    item_selected, boss_name = tickets[choice]

    # Barra ANTES de qualquer coisa: antes do teleporte, antes de guardar as
    # coordenadas de retorno e, sobretudo, antes de o bilhete ser consumido —
    # senao o jogador perdia o bilhete para ser recusado a seguir.
    proibidos = pbRaidLendariosNaEquipe
    if !proibidos.empty?
      nomes = proibidos.map { |p| p.name rescue "?" }.uniq.join(", ")
      pbMessage(_INTL("As Raids de Elite não aceitam Pokémon lendários."))
      pbMessage(_INTL("Deixe {1} no PC e volte aqui.", nomes))
      return false
    end

    if pbConfirmMessage(_INTL("Confirmar desafio contra {1}? Você será levado à sala de duelo.", boss_name))
      # Salva as coordenadas originais do Centro Pokémon para retorno
      $game_variables[76] = $game_map.map_id
      $game_variables[78] = $game_player.x
      $game_variables[79] = $game_player.y
      
      # Desativa bicicleta e seguidor para evitar bugs visuais
      pbDismountBike
      FollowingPkmn.toggle_off if defined?(FollowingPkmn)
      
      # Seta a raid ativa no game_temp para o handler de sprites
      $game_temp.active_raid_boss = item_selected
      
      # Teleporta para o Mapa 218 (Sala Online) coordenada (9, 18), olhando para cima (direção 8)
      pbFadeOutIn(99999) {
        $game_temp.player_new_map_id    = 218
        $game_temp.player_new_x         = 9
        $game_temp.player_new_y         = 18
        $game_temp.player_new_direction = 8
        $scene.transfer_player
        $game_map.autoplay
        $game_map.refresh
      }
      
      # A tela já clareou e o jogador está no Mapa 218!
      # Espera meia segundo para assentar a transição
      pbWait(0.5)
      
      # Caminha automaticamente 3 passos em direção ao chefe (X:9, Y:18 -> X:9, Y:15)
      pbMoveRoute($game_player, [
        PBMoveRoute::UP,
        PBMoveRoute::UP,
        PBMoveRoute::UP
      ])
      
      # Espera até concluir a movimentação
      while $game_player.moving? || $game_player.move_route_forcing
        pbWait(0.05)
      end
      
      # Diálogo e início do combate específico
      if item_selected == :BILHETELARANJA
        pbMessage(_INTL("Guzman: O quê?! Você veio até aqui me desafiar na minha própria arena?!"))
        pbMessage(_INTL("Prepare-se para ser esmagado pelo grande Guzman!"))
        
        $bag.remove(:BILHETELARANJA, 1)
        RaidTorre.iniciar_raid_guzman
      elsif item_selected == :BILHETEGIOVANNI
        pbMessage(_INTL("Giovanni: Então você aceitou o convite..."))
        pbMessage(_INTL("O poder absoluto pertence à Equipe Rocket! Mostre-me do que é capaz!"))
        
        $bag.remove(:BILHETEGIOVANNI, 1)
        RaidGiovanni.iniciar_raid_giovanni
      elsif item_selected == :BILHETEMISTY
        pbMessage(_INTL("Misty: Bem-vindo à arena aquática da Torre!"))
        pbMessage(_INTL("Minhas táticas com a água são imbatíveis. Prepare-se para uma tempestade!"))
        
        $bag.remove(:BILHETEMISTY, 1)
        RaidMisty.iniciar_raid_misty
      elsif item_selected == :BILHETEBROCK
        pbMessage(_INTL("Brock: Você quer testar a resistência dos seus laços contra a minha muralha de rocha?"))
        pbMessage(_INTL("Mostre-me se você tem a determinação de ferro necessária!"))
        
        $bag.remove(:BILHETEBROCK, 1)
        RaidBrock.iniciar_raid_brock
      elsif item_selected == :BILHETESURGE
        pbMessage(_INTL("Lt. Surge: Tenente Surge na área! Pronto para um choque de realidade?"))
        pbMessage(_INTL("Mostre toda a sua voltagem e tente passar pela minha defesa elétrica!"))
        
        $bag.remove(:BILHETESURGE, 1)
        RaidSurge.iniciar_raid_surge
      elsif item_selected == :BILHETEBLAINE
        pbMessage(_INTL("Blaine: Minhas charadas de fogo vão queimar seus neurônios!"))
        pbMessage(_INTL("Prepare-se para sentir o calor extremo do meu vulcão!"))
        
        $bag.remove(:BILHETEBLAINE, 1)
        RaidBlaine.iniciar_raid_blaine
      elsif item_selected == :BILHETEERIKA
        pbMessage(_INTL("Erika: As plantas mais delicadas escondem os espinhos mais letais..."))
        pbMessage(_INTL("Mostre-me como seu espírito floresce em batalha!"))
        
        $bag.remove(:BILHETEERIKA, 1)
        RaidErika.iniciar_raid_erika
      elsif item_selected == :BILHETEURANO
        pbMessage(_INTL("Urano: Ao igual que um inseto pode levantar até 10 vezes seu peso..."))
        pbMessage(_INTL("Você também sentirá o peso da minha determinação de ferro!"))
        
        $bag.remove(:BILHETEURANO, 1)
        RaidUrano.iniciar_raid_urano
      end
      
      # Limpa o estado da raid
      $game_temp.active_raid_boss = nil
      
      # Teleporte de volta ao Centro Pokémon de origem
      pbMessage(_INTL("Retornando ao Centro Pokémon..."))
      pbFadeOutIn(99999) {
        $game_temp.player_new_map_id    = $game_variables[76]
        $game_temp.player_new_x         = $game_variables[78]
        $game_temp.player_new_y         = $game_variables[79]
        $game_temp.player_new_direction = 2 # Olhando para baixo (sul)
        $scene.transfer_player
        FollowingPkmn.toggle_on if defined?(FollowingPkmn)
        $game_map.autoplay
        $game_map.refresh
      }
      return true
    end
  end
  return false
end

# Onde o chefe da raid fica na Sala 218 durante o duelo.
#
# O jogador para em (9,15) — ver o pbMoveRoute de 3 passos la em cima. Com o
# chefe em y=12 ficam 3 tiles entre os dois: perto o suficiente para os dois
# caberem no ecra com folga, longe o suficiente para parecer um frente a frente.
# Se algum dia o percurso do jogador mudar, e este par que tem de acompanhar.
RAID_BOSS_X = 9
RAID_BOSS_Y = 12

# Bosses mais altos precisam de descer mais, senao a cabeca sai pela borda.
#
# A conta: o jogador para em (9,15) e a camara centra-o a meia altura do ecra
# (384/2 = 192px). Os pes do chefe ficam em 192 - (15 - y)*32, e o topo em
# "pes - altura_do_sprite". Com os charsets deste jogo:
#
#   sprite 64px (2 tiles) -> y=12 da topo=32px   ok
#   sprite 84px (guzman)  -> y=12 da topo=12px   quase colado
#   sprite 128px (urano)  -> y=12 da topo=-32px  CORTADO
#
# Por isso os dois altos ganham uma linha propria. Urano fica a 1 tile do
# jogador, o que para um chefe de 4 tiles de altura ate parece proposital.
RAID_BOSS_Y_POR_NOME = {
  "guzman" => 13,
  "urano"  => 14
}

# 4. Inicializa o gráfico do boss ao entrar na Sala 218
EventHandlers.add(:on_map_or_spriteset_change, :initialize_raid_boss_sprite,
  proc { |scene, map_changed|
    next if !scene || !$game_map || $game_map.map_id != 218
    next if !$game_temp.active_raid_boss
    
    # Evento 20 é o evento do oponente na sala online
    event = $game_map.events[20]
    if event
      if $game_temp.active_raid_boss == :BILHETELARANJA
        event.character_name = "guzman"
      elsif $game_temp.active_raid_boss == :BILHETEGIOVANNI
        event.character_name = "giovanni"
      elsif $game_temp.active_raid_boss == :BILHETEMISTY
        event.character_name = "misty"
      elsif $game_temp.active_raid_boss == :BILHETEBROCK
        event.character_name = "brock"
      elsif $game_temp.active_raid_boss == :BILHETESURGE
        event.character_name = "surge"
      elsif $game_temp.active_raid_boss == :BILHETEBLAINE
        event.character_name = "blaine"
      elsif $game_temp.active_raid_boss == :BILHETEURANO
        event.character_name = "urano"
      elsif $game_temp.active_raid_boss == :BILHETEERIKA
        event.character_name = "erika"
      end
      event.turn_down # Olha para o sul (em direção ao jogador)

      # Desce o chefe para dentro do ecra.
      #
      # No mapa ele esta em (9,9) e o jogador acaba em (9,15) — seis tiles
      # acima. O ecra tem 12 tiles de altura e a camara centra no jogador, ou
      # seja mostra ~5,5 tiles para cada lado: o (9,9) cai exatamente na margem
      # e a cabeca do chefe fica cortada. Os sprites dos bosses ainda sao mais
      # altos que um personagem normal e sao ancorados pelos pes, o que agrava.
      #
      # Mexer aqui em vez de no Map218.rxdata: e so durante a raid, o mapa
      # recarrega limpo a seguir, e nao ha ficheiro binario para corromper. O
      # evento 20 tambem serve o lobby PVP, que fica intocado — este handler so
      # corre com uma raid ativa.
      event.moveto(RAID_BOSS_X, RAID_BOSS_Y_POR_NOME[event.character_name.to_s] || RAID_BOSS_Y)
    end
  }
)
