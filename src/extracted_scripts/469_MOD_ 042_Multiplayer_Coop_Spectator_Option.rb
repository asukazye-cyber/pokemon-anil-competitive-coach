#===============================================================================
# MOD: 042_Multiplayer_Coop_Spectator_Option
#===============================================================================
# Adiciona a opção no menu de opções do jogo para escolher entre assistir ou
# ir direto para o Centro Pokémon após ser derrotado em uma batalha cooperativa.
#===============================================================================

class PokemonSystem
  attr_writer :coop_watch_battle

  def coop_watch_battle
    @coop_watch_battle = 0 if @coop_watch_battle.nil?
    return @coop_watch_battle
  end
end

module AnilLanRework
  def self.coop_watch_battle_until_end?
    return true if !$PokemonSystem
    return $PokemonSystem.coop_watch_battle == 0
  end
end

MenuHandlers.add(:options_menu, :coop_watch_battle, {
  "name"        => _INTL("Assistir Coop"),
  "order"       => 86,
  "type"        => EnumOption,
  "parameters"  => [_INTL("Sim"), _INTL("Não")],
  "description" => _INTL("Se derrotado em coop, assistir a batalha ou ir direto para o Centro Pokémon?"),
  "get_proc"    => proc { next $PokemonSystem.coop_watch_battle },
  "set_proc"    => proc { |value, _scene| $PokemonSystem.coop_watch_battle = value }
})
