# encoding: UTF-8
#===============================================================================
# Coach Engine 2.0 — Explicit belief states over opponent properties.
#
# A BeliefState records what about the opponent has been LEGITIMATELY
# revealed to this client, and answers policy questions without ever
# silently treating an unknown as known:
#
#   * Observed moves: the engine itself records every move a battler uses
#     (Battler#@movesUsed, Battler#lastMoveUsed). That is client-visible
#     battle history by construction.
#   * Revealed species: a party slot is "revealed" once it has been active
#     (the client saw it in battle).
#   * Abilities/items: unknown unless an engine event revealed them; the
#     conservative answer is "unknown".
#
# Two policies use this:
#   :full     (default) — the twin is a snapshot of the client's own battle
#               object; whatever it contains was legitimately received (in
#               single player and in BattleSync multiplayer alike), so the
#               adversary model and evaluator may use it.
#   :revealed — extra-conservative: only observed moves are modelled for the
#               foe. DOCUMENTED BIAS: this UNDERCOUNTS the foe's options
#               (optimistic for us) when they have unobserved moves; the
#               evaluator substitutes a stat-based generic threat (species
#               and stats are public once a mon has been active) for
#               unobserved movesets.
#===============================================================================

module CoachEngine2
  class BeliefState
    # battle: a live battle (or twin). History is read from the engine's own
    # records; nothing is inferred beyond them.
    def self.of(battle)
      moves = {}
      species = {}
      battle.battlers.each_with_index do |b, i|
        next unless b
        # movesUsed/lastMoveUsed are engine ivars without public readers.
        used = []
        mu = b.instance_variable_get(:@movesUsed) rescue nil
        used.concat(mu.map(&:to_sym)) if mu.is_a?(Array)
        lmu = b.instance_variable_get(:@lastMoveUsed) rescue nil
        used.push(lmu) if lmu
        moves[i] = used.uniq
        species[i] = b.pokemon.species if !b.fainted?   # active slots are public
      end
      new(moves, species)
    end

    attr_reader :moves_by_battler, :species_by_battler

    def initialize(moves = {}, species = {})
      @moves_by_battler = Hash.new { |h, k| h[k] = [] }
      moves.each { |k, v| @moves_by_battler[k] = v.uniq }
      @species_by_battler = species
    end

    # True if this exact move has been observed from this battler.
    def move_observed?(_battle, idxBattler, move)
      id = move.respond_to?(:id) ? move.id : move
      @moves_by_battler[idxBattler].include?(id)
    end

    def reveal_move!(idxBattler, move_id)
      @moves_by_battler[idxBattler].push(move_id) unless move_observed?(nil, idxBattler, move_id)
      self
    end

    def observed_moves(idxBattler)
      @moves_by_battler[idxBattler].dup
    end

    # Threat modelling for the evaluator under :revealed: observed moves are
    # usable; anything else is replaced by a generic stat-based proxy (the
    # species is public once active; its stats are PBS data).
    def threat_moves_for(battle, idxBattler)
      b = battle.battlers[idxBattler]
      return [] unless b
      observed_moves(idxBattler).map { |id| GameData::Move.try_get(id) }.compact
    end
  end
end
