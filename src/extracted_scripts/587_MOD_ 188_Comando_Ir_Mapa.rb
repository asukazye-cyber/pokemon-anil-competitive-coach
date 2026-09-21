# encoding: UTF-8
#===============================================================================
# MOD: 188_Comando_Ir_Mapa
#-------------------------------------------------------------------------------
#   /ir                 lista os destinos conhecidos
#   /ir violet          vai para Violet City (Johto)
#   /ir slateport       vai para Slateport City (Hoenn)
#   /ir 300             vai para o mapa 300, no centro
#   /ir 300 12 20       vai para o mapa 300, na casa (12,20)
#   /voltar             regressa ao sitio de onde saiu pela ultima vez
#
# ⚠️ SO ADMIN, e por uma razao concreta.
#
# Estes mapas foram importados de outro projecto e nao estao ligados ao mundo:
# nao ha porta, nao ha voo, nao ha saida. Um jogador que la fosse parar ficava
# preso — por isso existe o /voltar, e por isso o comando nao e para todos.
#
# ⚠️ NAO SE ATERRA AS CEGAS.
#
# O destino e conferido antes de o jogador sair do sitio: o mapa tem de existir
# e a casa tem de ser pisavel. Sem isso, um id errado deixava o jogador dentro
# de uma parede, ou num mapa que nao carrega — e a unica saida seria o painel de
# administracao.
#===============================================================================

module AnilComandoIr
  ACTIVO = true

  # Os destinos com nome. A chave e o que se escreve no chat, em minusculas.
  # Acrescentar aqui e a unica coisa precisa quando se importar mais um mapa.
  DESTINOS = {
    "violet"    => [300, "Violet City (Johto)"],
    "slateport" => [301, "Slateport City (Hoenn)"]
  }.freeze

  module_function

  def log(t)
    AnilLanRework.log("[IR] #{t}") rescue nil
  end

  def meu_id
    AnilLanRework.read_cfg("multiplayer_player.txt", "id", "").to_s.strip.downcase
  rescue
    ""
  end

  # A lista local existe para o comando aparecer mesmo com um servidor antigo.
  # Quem manda continua a ser o servidor em tudo o que e autoritativo; isto e um
  # teleporte local, portanto aqui a lista basta.
  ADMINS_LOCAIS = ["wallace-adm100"].freeze

  def admin?
    return true if $anil_sou_admin == true
    ADMINS_LOCAIS.include?(meu_id)
  end

  def avisar(t)
    if AnilLanRework.respond_to?(:add_popup)
      AnilLanRework.add_popup(t, 8.0) rescue nil
    else
      pbMessage(t) rescue nil
    end
  end

  def lista
    DESTINOS.map { |k, v| "#{k} (#{v[1]})" }.join(", ")
  end

  # O mapa existe mesmo? Perguntar ao ficheiro e mais honesto do que perguntar ao
  # MapInfos: um pode ter a entrada e o outro nao ter o mapa.
  def mapa_existe?(id)
    File.exist?(format("Data/Map%03d.rxdata", id.to_i))
  rescue
    false
  end

  # Procura uma casa pisavel a volta do ponto pedido. Devolve nil se nao houver
  # nenhuma — e melhor recusar do que enfiar o jogador numa parede.
  def casa_boa(mapa, x, y)
    return [x, y] if pisavel?(mapa, x, y)
    (1..8).each do |raio|
      (-raio..raio).each do |dx|
        (-raio..raio).each do |dy|
          next unless dx.abs == raio || dy.abs == raio
          nx = x + dx
          ny = y + dy
          return [nx, ny] if pisavel?(mapa, nx, ny)
        end
      end
    end
    nil
  end

  def pisavel?(mapa, x, y)
    return false unless mapa.valid?(x, y)
    return false unless mapa.passable?(x, y, 0)
    terreno = (mapa.terrain_tag(x, y) rescue nil)
    return false if terreno && (terreno.can_surf || terreno.ledge)
    true
  rescue
    false
  end

  def guardar_regresso!
    return unless $game_map && $game_player
    @regresso = [$game_map.map_id, $game_player.x, $game_player.y]
  rescue
    nil
  end

  def viajar!(map_id, x = nil, y = nil, nome = nil)
    id = map_id.to_i
    unless mapa_existe?(id)
      avisar(_INTL("O mapa {1} não existe neste jogo.", id))
      return
    end

    mapa = ($map_factory.getMap(id) rescue nil)
    unless mapa
      avisar(_INTL("Não consegui carregar o mapa {1}.", id))
      return
    end

    alvo_x = x ? x.to_i : (mapa.width / 2)
    alvo_y = y ? y.to_i : (mapa.height / 2)
    casa = casa_boa(mapa, alvo_x, alvo_y)
    if casa.nil?
      avisar(_INTL("Não achei nenhuma casa livre no mapa {1}.", id))
      return
    end

    guardar_regresso!
    $game_temp.player_new_map_id    = id
    $game_temp.player_new_x         = casa[0]
    $game_temp.player_new_y         = casa[1]
    $game_temp.player_new_direction = 2
    $game_temp.player_transferring  = true
    $game_temp.transition_processing = true
    avisar(_INTL("Indo para {1} ({2},{3}).", (nome || "mapa #{id}"), casa[0], casa[1]))
    log("teleporte para #{id} (#{casa[0]},#{casa[1]})")
  rescue => e
    avisar(_INTL("Falha ao viajar: {1}", e.message))
    log("falha: #{e.class}: #{e.message}")
  end

  def voltar!
    unless @regresso
      avisar(_INTL("Não há para onde voltar."))
      return
    end
    id, x, y = @regresso
    @regresso = nil
    viajar!(id, x, y, _INTL("de volta"))
  end

  def tratar(texto)
    return false unless ACTIVO
    t = texto.to_s.strip
    return false unless t.start_with?("/")
    m = t.match(%r{\A/(ir|voltar)(?:\s+(.*))?\z}i)
    return false unless m
    # Para quem nao e admin isto nao e um comando: o texto segue o caminho normal
    # do chat, como se este MOD nao existisse.
    return false unless admin?

    if m[1].downcase == "voltar"
      voltar!
      return true
    end

    partes = m[2].to_s.strip.split(/\s+/)
    if partes.empty?
      avisar(_INTL("Destinos: {1}.\nOu /ir <mapa> [x] [y], e /voltar.", lista))
      return true
    end

    chave = partes[0].to_s.downcase
    if DESTINOS.key?(chave)
      id, nome = DESTINOS[chave]
      viajar!(id, partes[1], partes[2], nome)
      return true
    end

    if chave =~ /\A\d+\z/
      viajar!(chave.to_i, partes[1], partes[2])
      return true
    end

    avisar(_INTL("Não conheço '{1}'. Destinos: {2}.", partes[0], lista))
    true
  rescue => e
    avisar(_INTL("Erro no comando: {1}", e.message))
    true
  end
end

module AnilLanRework
  module Chat
    class << self
      if !method_defined?(:anil_irmapa_orig_send_message)
        alias_method :anil_irmapa_orig_send_message, :send_message rescue nil
      end

      def send_message(text)
        return if AnilComandoIr.tratar(text)
        anil_irmapa_orig_send_message(text)
      end
    end
  end
end
