# encoding: UTF-8
#===============================================================================
# MOD 196 — HORDA A PEDIDO, PARA VER OS BRILHOS
#
# Um comando de administrador que poe uma horda mesmo a frente de quem o
# escreve, com a raridade escolhida a mao. Existe por uma razao so: os dois
# brilhos da horda acontecem com probabilidades que tornam um teste impossivel —
# 5% de um spawn ser horda, e dentro dela o sorteio de shiny de cada membro.
# Esperar por eles nao e testar, e apostar.
#
# ⚠️ SAO DOIS BRILHOS DIFERENTES, E O COMANDO TEM DE MOSTRAR OS DOIS.
#
#   . NO MAPA, o `Sprite_Character` pulsa o `color` do evento: VERMELHO
#     (255,40,40) para uma horda qualquer, DOURADO (255,205,40) quando ha um
#     shiny la dentro. Quem decide e o `tem_shiny?`, que olha para a horda
#     INTEIRA — inclusive os companheiros, que ainda nao estao no mapa.
#
#   . NA BATALHA, o brilho e o do proprio Pokemon: shiny normal, ou super shiny
#     com a cor do `super_shiny_hue`.
#
# Por isso isto NAO comeca uma batalha: poe a horda no mapa. Ve-se a pulsacao,
# anda-se contra ela, e a batalha que abre e a verdadeira — a mesma que o
# perfume abriria. Um comando que saltasse direito a batalha testava metade.
#
# ⚠️ E O SUPER SHINY TEM DOIS PORTOES.
#
# O metodo que da a cor (no plugin do DBK) comeca com `return 0 if !super_shiny?`
# — escrever a cor num Pokemon que nao esta MARCADO como super shiny nao faz
# nada. Foi assim que os chefes da masmorra passaram semanas sem cor. Aqui
# marcam-se sempre os dois.
#===============================================================================
module AnilHordaTeste
  module_function

  RAIO = 5      # casas: ate onde se procura sitio se a casa da frente estiver ocupada

  def log(t)
    AnilLanRework.log("[HORDATESTE] #{t}") rescue nil
  end

  def admin?
    return AnilEventoShinyComando.admin? if defined?(AnilEventoShinyComando)
    false
  rescue
    false
  end

  # A casa mesmo a frente do jogador; se nao der, a mais proxima que der.
  def sitio
    d = ($game_player.direction rescue 2)
    dx = (d == 6) ? 1 : ((d == 4) ? -1 : 0)
    dy = (d == 2) ? 1 : ((d == 8) ? -1 : 0)
    frente = [$game_player.x + dx, $game_player.y + dy]
    return frente if livre?(frente[0], frente[1])
    (1..RAIO).each do |r|
      (-r..r).each do |ax|
        (-r..r).each do |ay|
          next unless ax.abs == r || ay.abs == r
          x = $game_player.x + ax
          y = $game_player.y + ay
          return [x, y] if livre?(x, y)
        end
      end
    end
    nil
  rescue
    nil
  end

  def livre?(x, y)
    return false unless ($game_map.valid?(x, y) rescue false)
    return false unless ($game_map.passable?(x, y, 0) rescue false)
    return false if $game_map.events.each_value.any? { |e| e && e.x == x && e.y == y }
    true
  rescue
    false
  end

  # Uma especie da tabela deste mapa. Sem tabela nao ha horda: seria inventar um
  # Pokemon que nao pertence aqui.
  def especie_daqui
    dados = (GameData::Encounter.get($game_map.map_id,
                                     ($PokemonGlobal.encounter_version rescue 0)) rescue nil)
    return nil unless dados
    todas = []
    dados.types.each_value { |l| todas += l.to_a if l.is_a?(Array) }
    return nil if todas.empty?
    e = todas[rand(todas.length)]
    lo = e[2].to_i
    hi = e[3].to_i
    hi = lo if hi < lo
    [e[1], lo + rand((hi - lo) + 1)]
  rescue
    nil
  end

  def pintar!(pk, modo, i)
    case modo
    when :dourada
      # ⚠️ SO UM DELES. E este o caso que interessa ver no mapa: o dourado nao
      # quer dizer "a horda e shiny", quer dizer "ha um shiny aqui dentro" — e
      # e por isso que ele vale a pena.
      if i.zero?
        (pk.shiny = true) rescue nil
        (pk.super_shiny = false) rescue nil
      else
        (pk.shiny = false) rescue nil
        (pk.super_shiny = false) rescue nil
      end
    when :shiny
      (pk.shiny = true) rescue nil
      (pk.super_shiny = false) rescue nil
    when :super
      (pk.shiny = true) rescue nil
      (pk.super_shiny = true) rescue nil
      (pk.cached_super_shiny_hue = nil) rescue nil   # a cor sai da especie, como no jogo
    else  # :normal
      (pk.shiny = false) rescue nil
      (pk.super_shiny = false) rescue nil
    end
    pk
  rescue
    pk
  end

  def rotulo(pk)
    return "super(hue #{(pk.super_shiny_hue rescue 0)})" if (pk.super_shiny? rescue false)
    return "shiny" if (pk.shiny? rescue false)
    "normal"
  rescue
    "?"
  end

  def largar!(modo)
    par = especie_daqui
    unless par
      pbMessage(_INTL("Este mapa não tem tabela de encontros — não sei que horda pôr aqui.")) rescue nil
      return false
    end
    casa = sitio
    unless casa
      pbMessage(_INTL("Não há espaço livre à sua volta.")) rescue nil
      return false
    end
    lider = (pbGenerateWildPokemon(par[0], par[1]) rescue nil)
    unless lider
      pbMessage(_INTL("Não consegui gerar o Pokémon.")) rescue nil
      return false
    end

    # ⚠️ MARCA-SE PRIMEIRO E PINTA-SE DEPOIS.
    #
    # O `marcar!` e que cria os companheiros — e cada um deles leva o sorteio de
    # shiny normal da horda. Pintar antes seria pintar um lider que ainda nao
    # tem horda; pintar depois manda em toda a gente, que e o que um teste
    # precisa.
    (AnilHorda.marcar!(lider) rescue nil)
    membros = [lider] + (AnilHorda.membros_de(lider) rescue [])
    membros.each_with_index { |p, i| pintar!(p, modo, i) }

    (pbPlaceEncounter(casa[0], casa[1], lider) rescue nil)
    cor = (AnilHorda.tem_shiny?(lider) rescue false) ? "DOURADA" : "vermelha"
    log("horda #{modo} em #{casa[0]},#{casa[1]}: " +
        membros.map { |p| "#{p.species} #{rotulo(p)}" }.join(" | ") + "  marca #{cor}")
    pbMessage(_INTL("Horda de {1} à sua frente ({2}). A marca no chão é {3}.",
                    membros.length, modo.to_s, cor)) rescue nil
    true
  rescue => e
    log("falha a largar: #{e.class}: #{e.message}")
    pbMessage(_INTL("A horda falhou: {1}", e.message)) rescue nil
    false
  end

  # ⚠️ O CICLO DO AFINAMENTO NAO PODE PASSAR POR FECHAR O JOGO.
  #
  # Mexer no editor, gravar, ver, corrigir. Se o "ver" custar fechar e abrir o
  # jogo, ninguem afina nada — desiste-se a terceira volta. O JSON dos remendos
  # e lido uma vez por sessao; isto manda le-lo outra vez.
  def tratar_anim(texto)
    t = texto.to_s.strip
    return false unless t =~ %r{\A/anim\z}i
    return false unless admin?
    n = (AnilArena.recarregar_remendos! rescue -1)
    if n < 0
      pbMessage(_INTL("Não consegui reler as animações.")) rescue nil
    else
      pbMessage(_INTL("Animações relidas: {1} com afinação.", n)) rescue nil
    end
    true
  rescue
    true
  end

  def tratar(texto)
    return true if tratar_anim(texto)
    t = texto.to_s.strip
    return false unless t =~ %r{\A/horda(?:\s+(.*))?\z}i
    arg = $1.to_s.strip.downcase
    return false unless admin?
    if defined?(AnilRaidCaverna) && (AnilRaidCaverna.dentro? rescue false)
      pbMessage(_INTL("Aqui dentro não: a masmorra tem os habitantes dela.")) rescue nil
      return true
    end
    modo = case arg
           when "", "dourada", "dourado", "ouro" then :dourada
           when "shiny"                           then :shiny
           when "super", "supershiny"             then :super
           when "normal", "comum", "vermelha"     then :normal
           else nil
           end
    unless modo
      pbMessage(_INTL("Uso: /horda [dourada|shiny|super|normal]")) rescue nil
      return true
    end
    largar!(modo)
    true
  rescue => e
    log("falha no comando: #{e.class}: #{e.message}")
    true
  end
end

#-------------------------------------------------------------------------------
# ⚠️ ALIAS PROPRIO, COMO TODOS OS OUTROS.
#
# Dois MODs com o mesmo nome de alias fecham a corrente num circulo e matam os
# comandos todos em silencio — ja aconteceu aqui com o /event, o /tp, o
# /dexshiny e o /canal. O `testar_ganchos.rb` existe por causa disso.
#-------------------------------------------------------------------------------
module AnilLanRework
  module Chat
    class << self
      if !method_defined?(:anil_hordateste_orig_send_message)
        alias_method :anil_hordateste_orig_send_message, :send_message rescue nil
      end

      def send_message(text)
        return if AnilHordaTeste.tratar(text)
        anil_hordateste_orig_send_message(text)
      end
    end
  end
end
