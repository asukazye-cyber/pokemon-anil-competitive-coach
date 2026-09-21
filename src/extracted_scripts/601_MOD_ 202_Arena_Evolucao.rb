# encoding: utf-8
#===============================================================================
# EVOLUIR NO MAPA, SEM SAIR DA LUTA
#
# ⚠️ A EVOLUCAO DO JOGO E UM ECRA INTEIRO, E AQUI ISSO NAO SERVE.
#
# O `PokemonEvolutionScene` (0329) faz tudo o que deve fazer — para a musica,
# toca o grito, escreve a mensagem, mostra a entrada da Pokedex — e faz tudo
# isso TOMANDO CONTA DO ECRA, com `loop`s proprios de `Graphics.update`.
#
# Numa arena em tempo real isso e o mesmo problema das raids: enquanto esse
# ecra corre, a luta esta suspensa e o mapa por baixo dele nao existe. Nao se
# reaproveita.
#
# ⚠️ O QUE SE REAPROVEITA E A DECISAO, QUE E A PARTE DIFICIL.
#
# Saber SE evolui, e para o que evolui, e o `check_evolution_on_level_up` do
# proprio Pokemon — com todas as regras de item, hora, amizade e forma. Isso
# nao se reescreve. O que este ficheiro faz e so a outra metade: aplicar a
# mudanca e mostra-la no mapa.
#
# O que se perde face ao ecra original: a entrada nova da Pokedex nao e
# mostrada (fica registada na mesma) e nao ha o "quer parar a evolucao?". Numa
# luta a decorrer, um menu modal seria pior do que a falta dele.
#===============================================================================
module AnilArenaEvolucao
  LIGADO = true

  # ── o chafariz ──────────────────────────────────────────────────────────────
  #
  # Particulas a subir do boneco, cada vez mais depressa, e o sprite a branquear
  # ate estourar. E o gesto que o jogo inteiro usa para dizer "isto mudou".
  DURACAO   = 1.6      # segundos do efeito todo
  TROCA_EM  = 0.72     # fraccao do tempo em que a especie muda mesmo
  POR_SEG   = 26       # particulas por segundo no auge
  SOBE      = 46.0     # pixeis que uma particula sobe
  VIDA_PART = 0.55     # segundos de cada particula

  @activos = []

  def self.a_evoluir?
    !(@activos.nil? || @activos.empty?)
  end

  #-----------------------------------------------------------------------------
  # ⚠️ A PERGUNTA E DO POKEMON, NAO MINHA.
  #
  # Tentei primeiro uma tabela propria de "quem evolui com que nivel" e desisti
  # a meio: ha evolucoes por item, por hora do dia, por amizade, por forma, por
  # genero, e por ter um golpe aprendido. Tudo isso ja esta no
  # `check_evolution_on_level_up`, testado e a funcionar no resto do jogo.
  #
  # Duplicar uma dessas regras e garantir que ela diverge um dia.
  #-----------------------------------------------------------------------------
  def self.talvez_evoluir!(pkmn, evento)
    return false unless LIGADO && pkmn
    nova = (pkmn.check_evolution_on_level_up rescue nil)
    return false unless nova
    # Ja esta a evoluir? Um segundo pedido sobre o mesmo bicho daria dois
    # chafarizes e duas trocas de especie.
    return false if (@activos || []).any? { |e| e[:pkmn].equal?(pkmn) }
    comecar!(pkmn, evento, nova)
    true
  rescue
    false
  end

  def self.comecar!(pkmn, evento, nova)
    vp = (AnilArena.viewport_das_animacoes rescue nil)
    return unless vp
    (pbSEPlay("Battle ball shake", 80) rescue nil)
    (@activos ||= []) << {
      :pkmn => pkmn, :ev => evento, :nova => nova, :t => 0.0,
      :trocou => false, :vp => vp, :particulas => [], :acumulado => 0.0,
      :nome_antigo => (pkmn.name.to_s rescue "")
    }
  rescue
    nil
  end

  #-----------------------------------------------------------------------------
  # O RELOGIO
  #-----------------------------------------------------------------------------
  def self.correr!(dt)
    return if @activos.nil? || @activos.empty?
    d = dt.to_f
    fora = []
    @activos.each do |e|
      e[:t] += d
      correr_particulas!(e, d)
      brilhar!(e)
      if !e[:trocou] && e[:t] >= (DURACAO * TROCA_EM)
        trocar!(e)
        e[:trocou] = true
      end
      fora << e if e[:t] >= DURACAO
    end
    return if fora.empty?
    fora.each { |e| largar!(e) }
    @activos -= fora
  rescue
    limpar!
  end

  # ⚠️ O SPRITE E O DO MOTOR, E NAO SE LHE TOCA NO BITMAP.
  #
  # Branquear pelo `color` do sprite e do sprite; mexer no bitmap contaminava a
  # `RPG::Cache` partilhada e o branco escapava para o jogo todo — ja aconteceu
  # neste projecto e esta escrito no 200.
  def self.brilhar!(e)
    sp = (AnilArena.sprite_de(e[:ev]) rescue nil)
    return unless sp && !(sp.disposed? rescue true)
    k = [e[:t] / DURACAO, 1.0].min
    # Sobe ate a troca, desce depois: o estouro e no instante em que ele muda.
    f = (k < TROCA_EM) ? (k / TROCA_EM) : (1.0 - ((k - TROCA_EM) / (1.0 - TROCA_EM)))
    a = (255 * [[f, 0.0].max, 1.0].min).round
    (sp.color.set(255, 255, 255, a) rescue nil)
  rescue
    nil
  end

  def self.correr_particulas!(e, dt)
    # Nascem cada vez mais depressa ate a troca.
    k = [e[:t] / (DURACAO * TROCA_EM), 1.0].min
    e[:acumulado] += POR_SEG * k * dt
    while e[:acumulado] >= 1.0
      e[:acumulado] -= 1.0
      nascer_particula!(e)
    end
    fora = []
    e[:particulas].each do |p|
      p[:t] += dt
      sp = p[:sp]
      if sp.nil? || (sp.disposed? rescue true) || p[:t] >= VIDA_PART
        fora << p
        next
      end
      f = p[:t] / VIDA_PART
      base = (AnilArena.centro_do_boneco(e[:ev]) rescue [0, 0])
      sp.x = (base[0] + p[:dx]).round
      sp.y = (base[1] + p[:dy] - (SOBE * f)).round
      sp.opacity = ((1.0 - f) * 255).round
      z = 0.6 + (0.6 * (1.0 - f))
      sp.zoom_x = z
      sp.zoom_y = z
    end
    return if fora.empty?
    fora.each { |p| (p[:sp].dispose rescue nil) unless (p[:sp].disposed? rescue true) }
    e[:particulas] -= fora
  rescue
    nil
  end

  # ⚠️ UMA PARTICULA DESENHADA A MAO, E NAO UMA FOLHA DO DISCO.
  #
  # Um ponto de luz de 8 px nao justifica um ficheiro novo em `Graphics/`, nem
  # o risco de ele nao viajar no update (que so entrega dois ficheiros — ver o
  # `gerar_remendos_embutidos.rb`).
  def self.bitmap_da_luz
    return @luz if @luz && !(@luz.disposed? rescue true)
    b = Bitmap.new(8, 8)
    b.fill_rect(2, 0, 4, 8, Color.new(255, 255, 210, 220))
    b.fill_rect(0, 2, 8, 4, Color.new(255, 255, 210, 220))
    b.fill_rect(1, 1, 6, 6, Color.new(255, 255, 255, 255))
    @luz = b
  rescue
    nil
  end

  def self.nascer_particula!(e)
    bmp = bitmap_da_luz
    return unless bmp
    sp = Sprite.new(e[:vp])
    sp.bitmap = bmp
    sp.ox = 4
    sp.oy = 4
    sp.blend_type = 1     # aditivo: e luz, nao tinta
    sp.z = 2600
    e[:particulas] << {
      :sp => sp, :t => 0.0,
      :dx => (rand(28) - 14), :dy => (rand(18) - 4)
    }
  rescue
    nil
  end

  #-----------------------------------------------------------------------------
  # A TROCA
  #-----------------------------------------------------------------------------
  def self.trocar!(e)
    pkmn = e[:pkmn]
    nova = e[:nova]
    return unless pkmn && nova
    caido = (pkmn.fainted? rescue false)
    vida_antes = (pkmn.totalhp.to_i rescue 1)
    hp_antes   = (pkmn.hp.to_i rescue 1)
    (pkmn.species = nova) rescue nil
    (pkmn.hp = 0) rescue nil if caido
    (pkmn.calc_stats rescue nil)
    (pkmn.ready_to_evolve = false) rescue nil
    # ⚠️ A VIDA GANHA COM A EVOLUCAO E GANHA, NAO PERDIDA.
    #
    # O `calc_stats` sobe o maximo mas deixa o actual onde estava. Sem isto, um
    # bicho que evolui a meio de uma luta ficava com a mesma vida numa barra
    # maior — parecia que tinha levado dano ao evoluir.
    unless caido
      ganho = (pkmn.totalhp.to_i - vida_antes)
      (pkmn.hp = [hp_antes + [ganho, 0].max, pkmn.totalhp.to_i].min) rescue nil
    end
    ($player.pokedex.register(pkmn) rescue nil)
    ($player.pokedex.set_owned(nova) rescue nil)
    ($stats.evolution_count += 1) rescue nil
    (pbMEPlay("Evolution success") rescue nil)
    (Pokemon.play_cry(nova, pkmn.form) rescue nil)
    # A arena tem de saber: a barra de vida, o boneco do evento e a ficha do
    # ajudante ficaram todos desactualizados.
    (AnilArena.evolucao_aconteceu!(pkmn, e[:ev]) rescue nil)
    nome = (GameData::Species.get(nova).name rescue nova.to_s)
    (AnilArena.dizer(AnilLanRework.ui_format("{1} evoluiu para {2}!",
                                             e[:nome_antigo], nome)) rescue nil)
  rescue
    nil
  end

  def self.largar!(e)
    (e[:particulas] || []).each do |p|
      (p[:sp].dispose rescue nil) if p[:sp] && !(p[:sp].disposed? rescue true)
    end
    e[:particulas] = []
    sp = (AnilArena.sprite_de(e[:ev]) rescue nil)
    (sp.color.set(0, 0, 0, 0) rescue nil) if sp && !(sp.disposed? rescue true)
  rescue
    nil
  end

  def self.limpar!
    (@activos || []).each { |e| largar!(e) }
    @activos = []
  rescue
    @activos = []
  end
end
