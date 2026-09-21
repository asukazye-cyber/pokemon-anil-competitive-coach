# Category has the following effects:
#   - Determines the in-battle weather.
#   - Some abilities reduce the encounter rate in certain categories of weather.
#   - Some evolution methods check the current weather's category.
#   - The :Rain category treats the last listed particle graphic as a water splash rather
#     than a raindrop, which behaves differently.
#   - :Rain auto-waters berry plants.
# Delta values are per second.
# For the tone_proc, strength goes from 0 to RPG::Weather::MAX_SPRITES (60) and
# will typically be the maximum.
module GameData
  class Weather
    attr_reader :id
    attr_reader :id_number
    attr_reader :real_name
    attr_reader :category   # :None, :Rain, :Hail, :Sandstorm, :Sun, :Fog
    attr_reader :graphics   # [[particle file names], [tile file names]]
    attr_reader :particle_delta_x
    attr_reader :particle_delta_y
    attr_reader :particle_delta_opacity
    attr_reader :tile_delta_x
    attr_reader :tile_delta_y
    attr_reader :tone_proc

    DATA = {}

    extend ClassMethods
    include InstanceMethods

    def self.load; end
    def self.save; end

    def initialize(hash)
      @id                     = hash[:id]
      @id_number              = hash[:id_number]
      @real_name              = hash[:id].to_s                || "Sin nombre"
      @category               = hash[:category]               || :None
      @particle_delta_x       = hash[:particle_delta_x]       || 0
      @particle_delta_y       = hash[:particle_delta_y]       || 0
      @particle_delta_opacity = hash[:particle_delta_opacity] || 0
      @tile_delta_x           = hash[:tile_delta_x]           || 0
      @tile_delta_y           = hash[:tile_delta_y]           || 0
      @graphics               = hash[:graphics]               || []
      @tone_proc              = hash[:tone_proc]
    end

    alias name real_name

    def has_particles?
      return @graphics[0] && @graphics[0].length > 0
    end

    def has_tiles?
      return @graphics[1] && @graphics[1].length > 0
    end

    def tone(strength)
      return (@tone_proc) ? @tone_proc.call(strength) : Tone.new(0, 0, 0, 0)
    end
  end
end

#===============================================================================

GameData::Weather.register({
  :id               => :None,
  :id_number        => 0   # Must be 0 (preset RMXP weather)
})

GameData::Weather.register({
  :id               => :Rain,
  :id_number        => 1,   # Must be 1 (preset RMXP weather)
  :category         => :Rain,
  :graphics         => [["rain_1", "rain_2", "rain_3", "rain_4"]],   # Last is splash
  :particle_delta_x => -600,
  :particle_delta_y => 2400,
  :tone_proc        => proc { |strength|
    next Tone.new(-strength / 2, -strength / 2, -strength / 2, 10)
  }
})

# NOTE: This randomly flashes the screen in RPG::Weather#update.
GameData::Weather.register({
  :id               => :Storm,
  :id_number        => 2,   # Must be 2 (preset RMXP weather)
  :category         => :Rain,
  :graphics         => [["storm_1", "storm_2", "storm_3", "storm_4"]],   # Last is splash
  :particle_delta_x => -3600,
  :particle_delta_y => 3600,
  :tone_proc        => proc { |strength|
    next Tone.new(-strength * 3 / 4, -strength * 3 / 4, -strength * 3 / 4, 10)
  }
})

# A ARTE NOVA DA NEVE PODE NAO TER CHEGADO AINDA.
#
# As definicoes abaixo viajam no Scripts.rxdata; os PNG viajam como assets, num
# lote separado do updater. Se o script chegar primeiro, o RPG_Cache levanta
# Errno::ENOENT em prepare_bitmaps e o jogo REBENTA em qualquer mapa com neve —
# muito pior do que a nevasca feia que se queria corrigir.
#
# Por isso a lista de graficos e escolhida em tempo de arranque: so se usam os
# flocos novos se eles existirem mesmo. Caso contrario fica o que sempre esteve
# la. Assim a ordem de entrega deixa de importar, e um cliente que nunca receba
# os assets continua a jogar.
ANIL_NEVE_NOVA = begin
  (pbResolveBitmap("Graphics/Weather/snow_p1") ? true : false)
rescue
  begin
    File.exist?("Graphics/Weather/snow_p1.png")
  rescue
    false
  end
end

ANIL_NEVE_PARTICULAS = ANIL_NEVE_NOVA ?
  ["snow_p1", "snow_p2", "snow_p3", "snow_p4", "snow_p5", "snow_p6"] :
  ["hail_1", "hail_2", "hail_3"]

# O veu (snow_veu/blizzard_tile) foi REMOVIDO da nevasca em 2026-08-23: tapava
# a tela e fazia a nevasca parecer um filtro branco em vez de neve a cair. Fica
# so a particula. Os PNGs continuam no disco, sem ninguem a usa-los.

# NOTE: This alters the movement of snow particles in RPG::Weather#update_sprite_position.
GameData::Weather.register({
  :id               => :Snow,
  :id_number        => 3,   # Must be 3 (preset RMXP weather)
  :category         => :Hail,
  # Flocos macios com alpha, em 6 variantes. O motor faz
  # `weatherBitmaps[index % length]`, ou seja, os quadros NAO sao animacao —
  # sao variantes sorteadas por particula. Mais ficheiros = mais variedade em
  # cena ao mesmo tempo. Os hail_* ficam intactos: sao o granizo das batalhas.
  :graphics         => [ANIL_NEVE_PARTICULAS],
  :particle_delta_x => -240,
  :particle_delta_y => 240,
  :tone_proc        => proc { |strength|
    next Tone.new(strength / 2, strength / 2, strength / 2, 0)
  }
})

GameData::Weather.register({
  :id               => :Blizzard,
  :id_number        => 4,
  :category         => :Hail,
  # Mesmos flocos da neve, e SO os flocos. A segunda entrada era a camada de
  # tile (o veu), que ladrilhava a tela inteira: davam-lhe um ar de filtro
  # branco por cima do mapa em vez de neve a cair. Sem ela, o
  # tile_delta_x/tile_delta_y deixariam de ter o que mover, por isso saem juntos.
  #
  # O particle_delta_x continua em -720 — e o triplo do :Snow, e e ele que
  # transforma os flocos em riscos horizontais, que e o que da a sensacao de
  # vento agora que o veu nao esta la. Se riscar demais, baixar para ~-420.
  :graphics         => [ANIL_NEVE_PARTICULAS],
  :particle_delta_x => -720,
  :particle_delta_y => 240,
  :tone_proc        => proc { |strength|
    next Tone.new(strength * 3 / 4, strength * 3 / 4, strength * 3 / 4, 0)
  }
})

GameData::Weather.register({
  :id               => :Sandstorm,
  :id_number        => 5,
  :category         => :Sandstorm,
  :graphics         => [["sandstorm_1", "sandstorm_2", "sandstorm_3", "sandstorm_4"], ["sandstorm_tile"]],
  :particle_delta_x => -1200,
  :particle_delta_y => 640,
  :tile_delta_x     => -800,
  :tile_delta_y     => 400,
  :tone_proc        => proc { |strength|
    next Tone.new(strength / 2, 0, -strength / 2, 0)
  }
})

GameData::Weather.register({
  :id               => :HeavyRain,
  :id_number        => 6,
  :category         => :Rain,
  :graphics         => [["storm_1", "storm_2", "storm_3", "storm_4"]],   # Last is splash
  :particle_delta_x => -3600,
  :particle_delta_y => 3600,
  :tone_proc        => proc { |strength|
    next Tone.new(-strength * 3 / 4, -strength * 3 / 4, -strength * 3 / 4, 10)
  }
})

# NOTE: This alters the screen tone in RPG::Weather#update_screen_tone.
GameData::Weather.register({
  :id               => :Sun,
  :id_number        => 7,
  :category         => :Sun,
  :tone_proc        => proc { |strength|
    next Tone.new(64, 64, 32, 0)
  }
})

GameData::Weather.register({
  :id               => :Fog,
  :category         => :Fog,
  :id_number        => 8,
  :tile_delta_x     => -32,
  :tile_delta_y     => 0,
  :graphics         => [nil, ["fog_tile"]]
})

