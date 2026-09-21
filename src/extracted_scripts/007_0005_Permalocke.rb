class PokemonGlobalMetadata
    attr_accessor :max_party_size

    alias init_permalocke_party_size initialize
    def initialize
        init_permalocke_party_size
        @max_party_size = Settings::MAX_PARTY_SIZE
    end
end

def max_party_size
    return Settings::MAX_PARTY_SIZE if !defined?(ChallengeModes) || !ChallengeModes.on?(:PERMALOCKE)
    $PokemonGlobal.max_party_size ||= Settings::MAX_PARTY_SIZE
    return $PokemonGlobal.max_party_size
end