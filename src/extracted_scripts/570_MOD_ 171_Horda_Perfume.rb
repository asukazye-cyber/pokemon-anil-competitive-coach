# encoding: UTF-8
#===============================================================================
# MOD: 171_Horda_Perfume
#-------------------------------------------------------------------------------
# Com o perfume no ar, um em cada vinte spawns nasce HORDA: um Pokemon so no
# mapa, marcado a vermelho, que ao ser enfrentado traz mais dois consigo.
#
# ⚠️ TRES E O TECTO DO MOTOR, E O QUARTO FALHA CALADO.
#
# O `setBattleMode` tem uma lista fechada que acaba no "3v3". Um "4v4" nao da
# erro nenhum: cai no `else` e vira batalha simples. Nao ha como pedir quatro.
#
# ⚠️ E TEM DE SER "1v3", E NAO TRES INIMIGOS E MAIS NADA.
#
# Passando tres foes sem regra, o motor faz isto sozinho:
#
#     setBattleRule("#{foe_party.length}v#{foe_party.length}")   # -> "3v3"
#
# Ou seja, o jogador tambem mandava tres — uma batalha tripla normal, e nao uma
# horda. O "1v3" ja existe na lista de regras aceites e e o formato certo: um
# contra tres.
#
# ⚠️ COM TRES INIMIGOS O MOTOR NAO ANUNCIA O FIM DA BATALHA.
#
# O `WildBattle.start` so dispara o :on_wild_battle_end quando ha UM foe:
#
#     if foe_party.length == 1 && can_override
#       EventHandlers.trigger(:on_wild_battle_end, ...)
#
# Portanto uma horda nao daria cadeia nenhuma — nem uma, quanto mais tres. E
# preciso dispara-lo a mao, uma vez por membro. Sem isto, a horda seria uma
# punicao: mais dificil e sem recompensa.
#===============================================================================

module AnilHorda
  ACTIVO = true

  # Percentagem dos spawns que nasce horda, com o perfume ligado. Fora do
  # perfume nao acontece: a horda e a recompensa de estar a usar o golpe.
  CHANCE = 5

  # O motor nao aceita mais. Ver a nota de topo.
  QUANTOS = 3

  # Niveis acima da tabela do mapa. Tres contra um ja e dificil; isto marca a
  # horda como algo a levar a serio, sem a tornar impossivel.
  NIVEL_EXTRA = 3

  # Hipotese de CADA membro vir na forma evoluida. Sorteado por membro, portanto
  # uma horda pode trazer zero, um, dois ou tres evoluidos.
  CHANCE_EVOLUIDO = 25

  # ⚠️ DOURADO QUANDO O LIDER E SHINY.
  #
  # A marca e um blend por cima do sprite inteiro, e um shiny no overworld
  # distingue-se justamente pela COR. Com o vermelho de sempre, uma horda shiny
  # aparecia como uma horda normal — a informacao mais rara do jogo tapada pela
  # menos rara.
  #
  # Duas cores resolvem sem acrescentar nada ao ecra: vermelho e horda, dourado
  # e horda COM shiny. Quem ja sabe o que o vermelho quer dizer percebe o
  # dourado a primeira vez que o ve.
  COR = [255, 40, 40]
  COR_SHINY = [255, 205, 40]
  PULSO_MIN = 60
  PULSO_MAX = 150
  PULSO_SEG = 1.4

  class << self
    def log(t)
      AnilLanRework.log("[HORDA] #{t}") rescue nil
    end

    # ⚠️ OS COMPANHEIROS NASCEM NO SPAWN, E NAO NA BATALHA.
    #
    # Antes eles eram criados so ao entrar no combate. Isso tinha uma
    # consequencia que so se ve a jogar: a marca dourada le o Pokemon do EVENTO,
    # e os outros dois ainda nao existiam — se o lider fosse normal e um
    # companheiro saisse shiny, nao havia aviso nenhum no mapa.
    #
    # E isso tirava o sentido a marca. O vermelho diz "sao tres"; o dourado tem
    # de poder dizer "ha um shiny aqui dentro", senao nao ha razao para preferir
    # enfrentar uma horda em vez de outra.
    #
    # Criados aqui, os tres sao sorteados ao mesmo tempo e o evento sabe o que
    # traz. Custa tres objectos em memoria enquanto ele andar no mapa — o mesmo
    # que qualquer outro spawn ja custa.
    def marcar!(pkmn)
      return unless pkmn
      pkmn.instance_variable_set(:@anil_horda, true)
      acompanhantes = []
      (QUANTOS - 1).times do
        c = companheiro(pkmn)
        acompanhantes << c if c
      end
      pkmn.instance_variable_set(:@anil_horda_membros, acompanhantes)
      log("#{pkmn.species} + #{acompanhantes.map { |c| c.species.to_s }.join(', ')}"           "#{tem_shiny?(pkmn) ? '  (COM SHINY)' : ''}")
    rescue
      nil
    end

    # Os companheiros que ja nasceram com este lider, se houver.
    def membros_de(pkmn)
      return [] unless pkmn
      (pkmn.instance_variable_get(:@anil_horda_membros) || [])
    rescue
      []
    end

    # ⚠️ O dourado olha para a HORDA INTEIRA, e nao so para quem esta no mapa.
    def tem_shiny?(lider)
      return false unless lider
      ([lider] + membros_de(lider)).any? { |p| p && ((p.shiny? || p.super_shiny?) rescue false) }
    rescue
      false
    end

    def horda?(pkmn)
      return false unless pkmn
      pkmn.instance_variable_get(:@anil_horda) == true
    rescue
      false
    end

    # ⚠️ A EVOLUCAO E OPCIONAL E PODE NAO EXISTIR.
    #
    # Muitas especies nao evoluem, e outras evoluem por metodos sem nivel. Se
    # nao houver para onde subir, fica a especie base — nunca se rebenta por
    # causa de um extra.
    def evoluir(especie)
      evos = (GameData::Species.get(especie).get_evolutions(true) rescue nil)
      return especie unless evos.is_a?(Array) && !evos.empty?
      alvo = evos.first
      alvo = alvo[0] if alvo.is_a?(Array)
      (GameData::Species.try_get(alvo) rescue nil) ? alvo : especie
    rescue
      especie
    end

    # Um companheiro: mesma especie (ou a evolucao dela), nivel acima, e o SEU
    # PROPRIO sorteio de shiny.
    def companheiro(modelo)
      esp = modelo.species
      esp = evoluir(esp) if rand(100) < CHANCE_EVOLUIDO
      nivel = (modelo.level + NIVEL_EXTRA)
      nivel = 100 if nivel > 100
      pkmn = pbGenerateWildPokemon(esp, nivel)
      return nil unless pkmn
      sortear_shiny!(pkmn)
      pkmn
    rescue => e
      log("falha a criar companheiro: #{e.class}: #{e.message}")
      nil
    end

    # ⚠️ CADA MEMBRO LEVA O SEU SORTEIO. E ESSE O PREMIO DA HORDA.
    #
    # O primeiro ja foi sorteado no spawnPokeEvent (MOD 070). Os outros dois
    # nascem aqui, e sao sorteados aqui — ao mesmo alvo, de forma independente.
    # Tres tentativas em vez de uma e o que faz valer a pena procurar hordas.
    def sortear_shiny!(pkmn)
      return unless pkmn
      if (AnilCadeiaCoop.forcado? rescue false)
        (AnilLogShiny.saltado!("horda", pkmn.species.to_s,
          "forcado por interruptor") rescue nil)
        return
      end
      alvo = (AnilCadeiaCoop.alvo_efectivo(pkmn.species) rescue 5000).to_i
      alvo = 1 if alvo < 1
      if rand(alvo) == 0
        pkmn.shiny = true
        pkmn.super_shiny = (rand(3) == 0)
      else
        pkmn.shiny = false
        pkmn.super_shiny = false
      end
      (AnilLogShiny.spawn!("horda") rescue nil)
      (AnilLogShiny.sorteio!("horda", pkmn.species.to_s, alvo, pkmn.shiny?) rescue nil)
    rescue
      nil
    end

    # ⚠️ A CADEIA CONTA PELOS TRES, E E PRECISO DIZE-LO.
    #
    # Ver a nota de topo: com mais de um inimigo o motor cala-se. Dispara-se o
    # mesmo evento que uma batalha normal dispararia, uma vez por membro — assim
    # tudo o que escuta a cadeia (o contador, o anuncio ao parceiro, o aviso no
    # ecra) funciona sem saber que houve horda.
    def contar_cadeia!(membros, resultado)
      return unless [1, 4].include?(resultado.to_i)

      # ⚠️ UMA MENSAGEM, E NAO TRES.
      #
      # Cada subida da cadeia anuncia-se. Tres membros davam tres caixas
      # seguidas — "Cadeia de 2", "de 3", "de 4" — a dizer a mesma coisa com o
      # jogador a carregar em A no meio. Dentro do `calado` a contagem corre na
      # mesma; so o anuncio e que espera pelo fim.
      ultima = nil
      AnilCadeiaCoop.calado do
        membros.each do |pk|
          next unless pk
          ultima = pk.species
          EventHandlers.trigger(:on_wild_battle_end, pk.species, pk.level, resultado) rescue nil
        end
      end

      # ⚠️ Le-se a cadeia DEPOIS, em vez de somar o numero de membros.
      #
      # Uma horda pode trazer evoluidos (25% por membro), e uma especie
      # diferente REINICIA a cadeia em vez de a somar. Contar "+3" mentiria
      # nesses casos; perguntar ao contador diz sempre a verdade.
      c = (AnilCadeiaCoop.minha_cadeia rescue [0, 0])
      AnilCadeiaCoop.anunciar_cadeia(c[1] || ultima, c[0].to_i) rescue nil
      log("cadeia apos a horda: #{c[0]}x #{c[1]}")
    rescue
      nil
    end
  end
end

#-------------------------------------------------------------------------------
# 1. QUEM NASCE HORDA
#
# O VOE dispara este evento com o Pokemon ja criado e ainda por colocar no mapa
# — o sitio exacto para o marcar.
#-------------------------------------------------------------------------------
if defined?(EventHandlers)
  EventHandlers.remove(:on_wild_pokemon_created_for_spawning, :anil_horda) rescue nil
  EventHandlers.add(:on_wild_pokemon_created_for_spawning, :anil_horda, proc { |pkmn|
    begin
      next unless AnilHorda::ACTIVO
      next unless (AnilPerfume.activo? rescue false)
      next unless rand(100) < AnilHorda::CHANCE
      AnilHorda.marcar!(pkmn)
      AnilHorda.log("#{pkmn.species} nasceu horda")
    rescue
      nil
    end
  })
end

#-------------------------------------------------------------------------------
# 2. A MARCA VERMELHA NO MAPA
#
# ⚠️ Usa-se o `color` do sprite, e nao o hue nem um sprite por cima.
#
# O `character_hue` roda a cor do bitmap, e esse bitmap vem da RPG::Cache
# partilhada — rodar ali contamina o Pokemon inteiro no jogo todo (foi o que
# aconteceu com o super shiny). Um sprite extra por cima obrigava a gerir um
# segundo objecto por evento. O `color` e um blend do proprio sprite: nao toca
# no bitmap, morre com ele, e a pulsacao e um numero.
#
# Entra no apply_post_plugin_patches como os outros: o Sprite_Character e
# reescrito por mais do que um plugin.
#-------------------------------------------------------------------------------
module AnilHorda
  class << self
    def instalar_marca!
      return false unless defined?(Sprite_Character)
      return false if Sprite_Character.method_defined?(:anil_horda_orig_update)
      Sprite_Character.class_eval do
        alias_method :anil_horda_orig_update, :update

        def update
          anil_horda_orig_update
          begin
            pk = (@character.is_a?(Game_PokeEvent) ? (@character.pokemon rescue nil) : nil)
            unless AnilHorda.horda?(pk)
              # So limpa o que foi POSTO por nos: outro plugin pode estar a usar
              # o color deste sprite para outra coisa.
              if @anil_horda_marcado
                self.color = Color.new(0, 0, 0, 0)
                @anil_horda_marcado = false
              end
            else
              t = (System.uptime rescue Time.now.to_f)
              fase = (Math.sin(t * (6.2831853 / AnilHorda::PULSO_SEG)) + 1.0) * 0.5
              a = AnilHorda::PULSO_MIN +
                  ((AnilHorda::PULSO_MAX - AnilHorda::PULSO_MIN) * fase)
              c = (AnilHorda.tem_shiny?(pk) rescue false) ?
                    AnilHorda::COR_SHINY : AnilHorda::COR
              self.color = Color.new(c[0], c[1], c[2], a)
              @anil_horda_marcado = true
            end
          rescue
            nil
          end
        end
      end
      log("marca instalada no Sprite_Character")
      true
    rescue => e
      log("falha ao instalar a marca: #{e.class}: #{e.message}")
      false
    end
  end
end

#-------------------------------------------------------------------------------
# 3. A BATALHA
#-------------------------------------------------------------------------------
module AnilHorda
  class << self
    def instalar_batalha!
      return false if Object.method_defined?(:anil_horda_orig_batalha) ||
                      Object.private_method_defined?(:anil_horda_orig_batalha)
      return false unless Object.private_method_defined?(:pbSingleOrDoubleWildBattle) ||
                          Object.method_defined?(:pbSingleOrDoubleWildBattle)
      Object.class_eval do
        alias_method :anil_horda_orig_batalha, :pbSingleOrDoubleWildBattle

        def pbSingleOrDoubleWildBattle(map_id, x, y, pokemon)
          unless AnilHorda::ACTIVO && AnilHorda.horda?(pokemon)
            return anil_horda_orig_batalha(map_id, x, y, pokemon)
          end
          AnilHorda.comecar!(map_id, x, y, pokemon)
        end
      end
      log("enxerto de batalha instalado")
      true
    rescue => e
      log("falha ao instalar a batalha: #{e.class}: #{e.message}")
      false
    end

    def comecar!(map_id, x, y, pokemon)
      # ⚠️ Usa os que nasceram com ele; so cria se faltarem.
      #
      # Assim o que entra na batalha e exactamente o que a marca no mapa
      # prometeu. Criar de novo aqui daria uma horda diferente da anunciada — e
      # um dourado que nao se cumprisse seria pior do que nao ter dourado.
      membros = [pokemon] + membros_de(pokemon)
      while membros.length < QUANTOS
        c = companheiro(pokemon)
        break unless c
        membros << c
      end

      # ⚠️ Um companheiro que nao nasceu nao pode virar batalha simples calada.
      #
      # Se so houver um, segue o caminho normal — o jogador ve um encontro
      # vulgar em vez de uma horda de um, que seria absurdo.
      if membros.length < 2
        log("nao foi possivel criar companheiros; segue como encontro normal")
        return anil_horda_orig_batalha(map_id, x, y, pokemon)
      end

      log("horda de #{membros.length}x #{pokemon.species} (nivel #{membros.map(&:level).join('/')})")
      setBattleRule("1v#{membros.length}") rescue nil
      resultado = (WildBattle.start_core(*membros) rescue 0)
      contar_cadeia!(membros, resultado)

      $game_temp.encounter_type = nil rescue nil
      $game_temp.encounter_triggered = true rescue nil
      resultado
    rescue => e
      log("a horda rebentou: #{e.class}: #{e.message}")
      (anil_horda_orig_batalha(map_id, x, y, pokemon) rescue nil)
    end
  end
end

module AnilLanRework
  class << self
    unless method_defined?(:anil_horda_orig_apply_post_plugin_patches)
      alias_method :anil_horda_orig_apply_post_plugin_patches, :apply_post_plugin_patches rescue nil
    end

    def apply_post_plugin_patches
      anil_horda_orig_apply_post_plugin_patches rescue nil
      AnilHorda.instalar_marca! rescue nil
      AnilHorda.instalar_batalha! rescue nil
    end
  end
end
