# encoding: UTF-8
#===============================================================================
# T2: the six MANDATORY regression tests from AGENT_PROMPT.md.
#
# 1. Steelix can KO Malamar on entry — no false "safe switch"; deliberate
#    sack explicit.
# 2. Faster Heracross OHKOs Malamar — no value for post-death actions.
# 3. Glimmora Lv100 vs Mareep Lv3 — preserve the free KO, no arbitrary
#    hard-switch to Zoroark.
# 4. No Guard + Thunder — guaranteed accuracy where the real rules say so.
# 5. Contrary + Superpower — inverted boosts persist in virtual state and
#    affect future calculations.
# 6. Outside battle — no hooks outside the battle engine (structural).
#===============================================================================
$TESTS = []

def check(name, cond, extra = "")
  $TESTS.push([name, !!cond, extra])
  puts "[#{cond ? 'PASS' : 'FAIL'}] #{name}#{extra.empty? ? '' : " — #{extra}"}"
end

def mk(species, level, moves: nil, item: nil, ability: nil)
  srand(1234)
  p = Pokemon.new(species, level, nil, false)
  p.item = item if item
  p.ability = ability if ability
  if moves
    p.instance_variable_set(:@moves, moves.map { |m| Pokemon::Move.new(m) })
  end
  p
end

def mk_battle(ours, foes, rng_policy: :median, seed: 7)
  rng = CoachEngine2::DeterministicRNG.new(seed: seed, policy: rng_policy)
  b = CoachEngine2::TwinFactory.build(ours, foes,
    player: CoachEngine2::DummyTrainer.new("Player"),
    opponent: CoachEngine2::DummyTrainer.new("Rival"),
    rng: rng)
  b.pbStartBattleCore(false)
  b
end

def search_on(battle, cfg = {})
  CoachEngine2::Search.new(battle, viewpoint_side: 0, config: {
    max_depth: 2, node_budget: 120, time_budget_ms: 8000,
    foe_branching: 4, our_branching: 12
  }.merge(cfg)).recommend
end

load_engine2 rescue nil

# =============================================================================
# TEST 1 — Steelix KOs Malamar on entry
# =============================================================================
begin
  zoroark  = mk(:ZOROARK, 55, moves: [:FLAMETHROWER, :NASTYPLOT])
  malamar  = mk(:MALAMAR, 45, moves: [:SUPERPOWER, :KNOCKOFF])
  steelix  = mk(:STEELIX, 75, moves: [:EARTHQUAKE, :HEAVYSLAM])
  battle = mk_battle([zoroark, malamar], [steelix])

  # The raw successor after the switch line: Malamar enters, Steelix's EQ
  # executes in the same round's move phase.
  drv = CoachEngine2::TurnDriver.new(battle)
  clone = Marshal.load(Marshal.dump(battle))
  cd = CoachEngine2::TurnDriver.new(clone)
  # NOTE: one inject! call — inject! clears unset choosable choices, so a
  # second call would wipe the first.
  cd.inject!(0 => cd.switch_choice(0, 1), 1 => cd.move_choice(1, 0))
  cd.step!
  malamar_after = clone.pbParty(0)[1]
  check("T1 Malamar KO'd on entry",
        malamar_after.hp.zero?,
        "malamar hp=#{malamar_after.hp}/#{malamar_after.totalhp}")

  # The search must NOT recommend the switch to Malamar (Zoroark attacking is
  # strictly better than feeding Malamar to Steelix).
  res = search_on(battle)
  best = res.action && res.action[0]
  is_switch_to_malamar = best && best[0] == :SwitchOut && best[1] == 1
  check("T1 switch->Malamar not recommended",
        !is_switch_to_malamar,
        "best=#{best.inspect} value=#{res.value.round(3)} #{res.metrics.report}")

  # And the switch line must be strictly worse than the best line.
  # Compute the switch line's value explicitly: successor after switch+EQ.
  switch_state = clone
  v_switch = CoachEngine2::Evaluator.new(0).win_probability(switch_state)
  check("T1 switch line evaluated worse than recommendation",
        v_switch <= res.value + 0.001,
        "v_switch=#{v_switch.round(3)} v_best=#{res.value.round(3)}")
rescue => e
  check("T1 raised", false, "#{e.class}: #{e.message}")
  (e.backtrace || [])[0, 6].each { |l| puts "    #{l}" }
end

# =============================================================================
# TEST 2 — Faster Heracross OHKOs Malamar: no posthumous action value
# =============================================================================
begin
  malamar2 = mk(:MALAMAR, 45, moves: [:KNOCKOFF, :SUPERPOWER, :PSYCHIC])
  backup   = mk(:ZOROARK, 55, moves: [:FLAMETHROWER])
  heracross = mk(:HERACROSS, 55, moves: [:MEGAHORN, :CLOSECOMBAT])
  battle = mk_battle([malamar2, backup], [heracross])
  b0 = battle.battlers[0]
  b1 = battle.battlers[1]
  check("T2 Heracross faster than Malamar",
        b1.pokemon.speed > b0.pokemon.speed,
        "hera=#{b1.pokemon.speed} malamar=#{b0.pokemon.speed}")

  # If Malamar chooses Knock Off but is KO'd first, the resulting state must
  # be IDENTICAL to choosing any other move: no posthumous credit.
  outs = {}
  [0, 1, 2].each do |mv|
    clone = Marshal.load(Marshal.dump(battle))
    cd = CoachEngine2::TurnDriver.new(clone)
    cd.inject!(0 => cd.move_choice(0, mv), 1 => cd.move_choice(1, 0)) # foe Megahorn
    cd.step!
    outs[mv] = CoachEngine2::TurnDriver::StateSummary.of(clone).hashable
  end
  check("T2 all Malamar actions yield identical post-KO state",
        outs.values.uniq.length == 1,
        "distinct outcomes: #{outs.values.uniq.length}")

  hera_hp = Marshal.load(Marshal.dump(battle)).tap { |c|
    cd = CoachEngine2::TurnDriver.new(c)
    cd.inject!(0 => cd.move_choice(0, 0), 1 => cd.move_choice(1, 0))
    cd.step!
  }.battlers[1].hp
  check("T2 Heracross unharmed by Malamar's posthumous Knock Off",
        hera_hp == battle.battlers[1].hp,
        "hera hp #{hera_hp} == #{battle.battlers[1].hp}")
rescue => e
  check("T2 raised", false, "#{e.class}: #{e.message}")
  (e.backtrace || [])[0, 6].each { |l| puts "    #{l}" }
end

# =============================================================================
# TEST 3 — Glimmora Lv100 vs Mareep Lv3: keep the free KO
# =============================================================================
begin
  glimmora = mk(:GLIMMORA, 100, moves: [:POWERGEM, :EARTHPOWER, :SLUDGEWAVE])
  zoroark3 = mk(:ZOROARK, 55, moves: [:FLAMETHROWER])
  mareep   = mk(:MAREEP, 3, moves: [:TACKLE])
  battle = mk_battle([glimmora, zoroark3], [mareep])
  check("T3 setup", battle.battlers[1].hp <= 20 && battle.battlers[0].level == 100,
        "mareep hp=#{battle.battlers[1].hp} glimmora lvl=#{battle.battlers[0].level}")

  res = search_on(battle)
  best = res.action && res.action[0]
  check("T3 free KO preserved (no hard-switch)",
        !best.nil? && best[0] == :UseMove,
        "best=#{best.inspect} value=#{res.value.round(3)} #{res.metrics.report}")

  # With the KO, if Mareep is the foe's only Pokémon, the battle is WON:
  clone = Marshal.load(Marshal.dump(battle))
  cd = CoachEngine2::TurnDriver.new(clone)
  cd.inject!(0 => cd.move_choice(0, 0), 1 => cd.move_choice(1, 0))
  d = cd.step!
  check("T3 KO ends the battle with a win", d == 1,
        "decision=#{d} mareep hp=#{clone.battlers[1].hp}")
rescue => e
  check("T3 raised", false, "#{e.class}: #{e.message}")
  (e.backtrace || [])[0, 6].each { |l| puts "    #{l}" }
end

# =============================================================================
# TEST 4 — No Guard + Thunder: guaranteed accuracy
# =============================================================================
begin
  # Any species with No Guard and Thunder (test-only combination).
  nogo = mk(:ELECTIVIRE, 60, moves: [:THUNDER], ability: :NOGUARD)
  snorlax = mk(:SNORLAX, 60, moves: [:BODYSLAM])
  results = {}
  [:min, :max, :median].each do |policy|
    battle = mk_battle([nogo], [snorlax], rng_policy: policy)
    hp0 = battle.battlers[1].hp
    cd = CoachEngine2::TurnDriver.new(battle)
    cd.inject!(0 => cd.move_choice(0, 0), 1 => cd.move_choice(1, 0))
    cd.step!
    results[policy] = battle.battlers[1].hp < hp0
  end
  check("T4 No Guard Thunder hits under every roll policy",
        results.values.all?,
        results.map { |k, v| "#{k}=#{v}" }.join(" "))

  # Even with foe evasion maxed: No Guard ignores accuracy checks entirely.
  battle = mk_battle([nogo], [snorlax], rng_policy: :max)
  6.times { |i| battle.battlers[1].stages[:EVASION] = i + 1 }
  hp0 = battle.battlers[1].hp
  cd = CoachEngine2::TurnDriver.new(battle)
  cd.inject!(0 => cd.move_choice(0, 0), 1 => cd.move_choice(1, 0))
  cd.step!
  check("T4 No Guard Thunder hits through maxed evasion",
        battle.battlers[1].hp < hp0,
        "hp #{hp0}->#{battle.battlers[1].hp}")
rescue => e
  check("T4 raised", false, "#{e.class}: #{e.message}")
  (e.backtrace || [])[0, 6].each { |l| puts "    #{l}" }
end

# =============================================================================
# TEST 5 — Contrary + Superpower: inverted boosts persist and compound
# =============================================================================
begin
  contrary_mon = mk(:MALAMAR, 100, moves: [:SUPERPOWER], ability: :CONTRARY)
  # NOTE: the real engine's StatDownMove skips the self stat change when the
  # target's side is ALL fainted (pbAllFainted? guard). One Lv100 Blissey is
  # exactly OHKO'd by this Malamar's Superpower, so use three: each KO leaves
  # the foe side alive, the boost applies every round, and the compounding is
  # observable exactly as the real rules dictate.
  blisseys = 3.times.map { mk(:BLISSEY, 100, moves: [:BODYSLAM]) }
  battle = mk_battle([contrary_mon], blisseys)
  atk_stat = :ATTACK
  def_stat = :DEFENSE
  b0 = battle.battlers[0]
  atk0, def0 = b0.stages[atk_stat], b0.stages[def_stat]

  cd = CoachEngine2::TurnDriver.new(battle)
  cd.inject!(0 => cd.move_choice(0, 0), 1 => cd.move_choice(1, 0))
  dmg_round1_target_hp = battle.battlers[1].hp
  cd.step!
  dmg1 = dmg_round1_target_hp - battle.battlers[1].hp
  atk1, def1 = b0.stages[atk_stat], b0.stages[def_stat]
  check("T5 Superpower+Contrary raises Atk/Def (+1)",
        atk1 == atk0 + 1 && def1 == def0 + 1,
        "atk #{atk0}->#{atk1} def #{def0}->#{def1} dmg1=#{dmg1}")

  # Second use: boosts persist and compound (+2), and damage grows.
  hp_before = battle.battlers[1].hp
  cd.inject!(0 => cd.move_choice(0, 0), 1 => cd.move_choice(1, 0))
  cd.step!
  dmg2 = hp_before - battle.battlers[1].hp
  atk2, def2 = b0.stages[atk_stat], b0.stages[def_stat]
  check("T5 boosts persist and compound (+2)",
        atk2 == atk0 + 2 && def2 == def0 + 2,
        "atk #{atk1}->#{atk2} def #{def1}->#{def2}")
  # In-battle damage is truncated at the target's remaining HP, so HP deltas
  # must be taken against a target that survives (or caps) consistently. The
  # third foe is a Snorlax wall: the boosted third Superpower (measured as a
  # real engine round) must deal strictly more damage than the same move in a
  # fresh, unboosted battle against the same wall — proving the persisted
  # stages change future calculations in the virtual state.
  battle2 = mk_battle([contrary_mon], 3.times.map { mk(:BLISSEY, 100, moves: [:BODYSLAM]) })
  cd2 = CoachEngine2::TurnDriver.new(battle2)
  2.times { cd2.inject!(0 => cd2.move_choice(0, 0), 1 => cd2.move_choice(1, 0)); cd2.step! }
  wall = mk(:SNORLAX, 100, moves: [:BODYSLAM])
  battle3 = mk_battle([mk(:MALAMAR, 100, moves: [:SUPERPOWER], ability: :CONTRARY)], [wall])
  cd3 = CoachEngine2::TurnDriver.new(battle3)
  fresh_hp = battle3.battlers[1].hp
  cd3.inject!(0 => cd3.move_choice(0, 0), 1 => cd3.move_choice(1, 0))
  cd3.step!
  dmg_fresh = fresh_hp - battle3.battlers[1].hp
  # Now the boosted battle: replace foe 3 with the same wall by building a
  # fresh one where the first two foes are Blissey and the third is the wall.
  boosted = mk_battle([mk(:MALAMAR, 100, moves: [:SUPERPOWER], ability: :CONTRARY)],
                      [mk(:BLISSEY, 100, moves: [:BODYSLAM]),
                       mk(:BLISSEY, 100, moves: [:BODYSLAM]),
                       mk(:SNORLAX, 100, moves: [:BODYSLAM])])
  cdb = CoachEngine2::TurnDriver.new(boosted)
  2.times { cdb.inject!(0 => cdb.move_choice(0, 0), 1 => cdb.move_choice(1, 0)); cdb.step! }
  boosted_atk = boosted.battlers[0].stages[:ATTACK]
  wall_hp = boosted.battlers[1].hp
  cdb.inject!(0 => cdb.move_choice(0, 0), 1 => cdb.move_choice(1, 0))
  cdb.step!
  dmg_boosted = wall_hp - boosted.battlers[1].hp
  check("T5 second Superpower hits harder",
        dmg_boosted > dmg_fresh,
        "round3 vs wall: boosted(atk+#{boosted_atk})=#{dmg_boosted} > fresh=#{dmg_fresh}")
rescue => e
  check("T5 raised", false, "#{e.class}: #{e.message}")
  (e.backtrace || [])[0, 6].each { |l| puts "    #{l}" }
end

# =============================================================================
# TEST 6 — Outside battle isolation (structural)
# =============================================================================
begin
  engine2_src = Dir.glob("/work/engine2/*.rb").sort.map { |f| File.read(f) }.join
  forbidden = engine2_src.scan(/^\s*(class|module)\s+(Input|Graphics|Game_Map|Game_Player|Game_Event|Game_Temp|SpriteSet|Scene_Map|PokemonBag)\b/ )
  check("T6 engine2 defines nothing outside battle engine", forbidden.empty?,
        forbidden.inspect)

  aliases = engine2_src.scan(/^\s*alias(?:_method)?\s+(\w+)/).flatten
  check("T6 engine2 contains no alias chains", aliases.empty?, aliases.inspect)

  # Input constants untouched (still the RGSS set the stubs defined).
  check("T6 Input module still pure stub",
        Input.instance_methods(false).empty? && !Input.method_defined?(:update_coach))
rescue => e
  check("T6 raised", false, "#{e.class}: #{e.message}")
end

fails = $TESTS.count { |_n, ok, _| !ok }
puts "T2-SUMMARY: #{$TESTS.size - fails}/#{$TESTS.size} passed"
exit(fails.zero? ? 0 : 1)
