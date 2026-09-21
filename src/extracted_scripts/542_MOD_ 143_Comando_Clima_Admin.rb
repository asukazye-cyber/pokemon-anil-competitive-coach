# encoding: UTF-8
#===============================================================================
# MOD: 143_Comando_Clima_Admin
#-------------------------------------------------------------------------------
# Comando de chat /clima, só para administradores.
#
#   /clima            -> mostra o clima atual e a lista de tipos
#   /clima neve       -> força neve
#   /clima nevasca    -> força nevasca
#   /clima auto       -> devolve o controlo ao clima dinamico (MOD 047)
#
# ⚠️ O EFEITO E LOCAL, so para quem digita.
#
# O $forced_weather e lido pelo AnilLanRework.get_weather_for_map, que corre em
# CADA cliente separadamente — o clima nao viaja pela rede, e derivado de uma
# semente deterministica (data + bloco de 3h + id do mapa) que todos calculam
# igual. Forcar aqui muda so o que este jogo desenha.
#
# Isso e de proposito e e o que serve para testar. Para mudar o clima do
# servidor inteiro seria preciso o servidor mandar o override a toda a gente —
# da para fazer, mas e outra coisa, e obriga a atualizar servidor e cliente.
#
# Por ser local e cosmetico, a verificacao de administrador aqui basta: o pior
# que alguem consegue, mesmo contornando-a, e mudar a propria neve.
#
# ⚠️ So funciona em mapas EXTERNOS. O MOD 047 limpa o clima em interiores
# (casas, cavernas) de proposito, e isso vem antes do override.
#===============================================================================

module AnilComandoClima
  # IDs completos (nome-sufixo), em minusculas.
  ADMINS = ["wallace-adm100"].freeze

  # O que se pode escrever -> o id que o motor conhece.
  # Varias grafias por tipo porque ninguem se lembra do nome exato a meio de um teste.
  TIPOS = {
    "auto"       => :auto,
    "normal"     => :auto,
    "limpo"      => :None,
    "nada"       => :None,
    "none"       => :None,
    "sol"        => :Sun,
    "chuva"      => :Rain,
    "chuvafote"  => :HeavyRain,
    "chuvaforte" => :HeavyRain,
    "tempestade" => :Storm,
    "raios"      => :Storm,
    "neve"       => :Snow,
    "nevasca"    => :Blizzard,
    "areia"      => :Sandstorm,
    "nevoa"      => :Fog,
    "neblina"    => :Fog,
    "nublado"    => :Cloudy,
    "encoberto"  => :Cloudy,
    "lua"        => :Moonlight
  }.freeze

  module_function

  def meu_id
    AnilLanRework.read_cfg("multiplayer_player.txt", "id", "").to_s.strip.downcase
  rescue
    ""
  end

  def admin?
    ADMINS.include?(meu_id)
  end

  def avisar(texto)
    if AnilLanRework.respond_to?(:add_popup)
      AnilLanRework.add_popup(texto, 8.0) rescue nil
    else
      pbMessage(texto) rescue nil
    end
  end

  def nome_do_tipo(valor)
    return "automatico" if valor.nil?
    par = TIPOS.find { |_, v| v == valor }
    par ? par[0] : valor.to_s
  end

  def lista_de_tipos
    # Uma grafia por tipo, para a mensagem nao virar uma parede.
    vistos = []
    TIPOS.each_value { |v| vistos << v unless vistos.include?(v) }
    vistos.map { |v| nome_do_tipo(v) }.join(", ")
  end

  # Devolve true se tratou o texto (e portanto ele NAO deve virar mensagem de chat).
  def tratar(texto)
    t = texto.to_s.strip
    return false unless t =~ %r{\A/clima(?:\s+(\S+))?\z}i
    arg = $1

    unless admin?
      avisar("[Sistema] Comando disponível apenas para administradores.")
      return true
    end

    if arg.nil?
      atual = $forced_weather ? "forçado em '#{nome_do_tipo($forced_weather)}'" : "automático"
      avisar("[Clima] Agora: #{atual}.\nUse /clima <tipo>. Tipos: #{lista_de_tipos}")
      return true
    end

    chave = arg.to_s.strip.downcase
    unless TIPOS.key?(chave)
      avisar("[Clima] Tipo '#{arg}' não existe.\nTipos: #{lista_de_tipos}")
      return true
    end

    escolhido = TIPOS[chave]
    if escolhido == :auto
      $forced_weather = nil
      avisar("[Clima] Devolvido ao automático.")
    else
      $forced_weather = escolhido
      aviso = ""
      begin
        md = $game_map ? GameData::MapMetadata.try_get($game_map.map_id) : nil
        aviso = "\n(Este mapa é interior — o clima só aparece em mapas externos.)" if md && !md.outdoor_map
      rescue
      end
      avisar("[Clima] Forçado: #{nome_do_tipo(escolhido)}.#{aviso}\n/clima auto devolve ao normal.")
    end
    AnilLanRework.log("[CLIMA] #{meu_id} definiu #{escolhido.inspect}") rescue nil
    true
  rescue => e
    AnilLanRework.log("[CLIMA] falha no comando: #{e.class}: #{e.message}") rescue nil
    false
  end
end

module AnilLanRework
  module Chat
    class << self
      if !method_defined?(:anil_clima_orig_send_message)
        alias_method :anil_clima_orig_send_message, :send_message rescue nil
      end

      def send_message(text)
        return if AnilComandoClima.tratar(text)
        anil_clima_orig_send_message(text)
      end
    end
  end
end

AnilLanRework.log("143_Comando_Clima_Admin carregado") rescue nil
