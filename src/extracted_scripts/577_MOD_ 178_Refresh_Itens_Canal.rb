# encoding: UTF-8
#===============================================================================
# MOD: 178_Refresh_Itens_Canal
#-------------------------------------------------------------------------------
# Volta a pedir os itens largados quando se muda de canal e quando se entra no
# jogo — nao so quando se carrega um mapa novo.
#
# ⚠️ O PEDIDO ESTAVA AMARRADO AO CARREGAMENTO DO MAPA.
#
# No MOD 043, a unica coisa que marca o pedido e o `Game_Map#setup`:
#
#     def setup(map_id)
#       @pending_dropped_items_request = true
#
# Trocar de canal NAO recarrega o mapa, e entrar no jogo ja no canal certo
# tambem nao. Por isso um item largado no canal 8 so aparecia depois de sair do
# mapa e voltar — o jogador estava ao lado dele e nao o via.
#
# Aqui pede-se tambem nesses dois momentos. O pacote e minusculo e o servidor ja
# sabe responder-lhe; nao ha protocolo novo.
#===============================================================================

module AnilRefreshItens
  ACTIVO = true

  module_function

  def log(t)
    AnilLanRework.log("[ITENS] #{t}") rescue nil
  end

  # Devolve true so quando o pacote saiu mesmo.
  def pedir!(porque)
    return false unless ACTIVO
    return false unless (AnilLanRework.connected? rescue false)
    return false unless $game_map
    AnilLanRework.connection.send_packet("request_dropped_items", {
      "map_id" => $game_map.map_id
    })
    log("pedido de itens do mapa #{$game_map.map_id} (#{porque})")
    true
  rescue => e
    log("falha ao pedir: #{e.class}: #{e.message}")
    false
  end

  # ⚠️ Nao se pede na hora: marca-se e cumpre-se um frame depois.
  #
  # A troca de canal e o join acontecem a meio de outras coisas — o mapa pode
  # ainda estar a assentar, e o $game_map.map_id de agora pode nao ser o de
  # daqui a um instante. Adiar um frame faz o pedido sair com o mapa certo.
  def marcar!(porque)
    @pedido = porque
  end

  # ⚠️ SO SE LIMPA O PEDIDO QUANDO ELE SAI MESMO.
  #
  # Carregar um save monta o mapa ANTES de a ligacao existir. Limpar a bandeira
  # primeiro e perguntar pelo `connected?` a seguir fazia o pedido evaporar-se
  # sem nunca sair — e nao havia retentativa. O jogador ficava ao lado do item
  # sem o ver, e so mudar de canal o trazia.
  #
  # Guardando o pedido ate ele sair, ele espera pela ligacao sozinho.
  def cumprir!
    return unless @pedido
    @pedido = nil if pedir!(@pedido)
  rescue
    @pedido = nil
  end

  def ha_pedido?
    !@pedido.nil?
  end
end

#-------------------------------------------------------------------------------
# 1. AO TROCAR DE CANAL
#-------------------------------------------------------------------------------
module AnilRefreshItens
  module_function

  def instalar_canal!
    return false unless defined?(PokemonSystem)
    return false if PokemonSystem.method_defined?(:anil_refitens_orig_canal)
    PokemonSystem.class_eval do
      alias_method :anil_refitens_orig_canal, :multiplayer_channel=

      def multiplayer_channel=(valor)
        antes = (@multiplayer_channel rescue nil)
        anil_refitens_orig_canal(valor)
        AnilRefreshItens.marcar!("mudou do canal #{antes} para #{valor}") if antes != valor
      end
    end
    true
  rescue => e
    log("falha a instalar no canal: #{e.class}: #{e.message}")
    false
  end
end

#-------------------------------------------------------------------------------
# 2. AO ENTRAR NO JOGO
#
# O join_ack e o momento em que o cliente sabe que esta mesmo ligado e em que
# canal. Antes disso, um pedido nao teria resposta.
#-------------------------------------------------------------------------------
if defined?(EventHandlers)
  EventHandlers.remove(:on_enter_map, :anil_refresh_itens) rescue nil
  EventHandlers.add(:on_enter_map, :anil_refresh_itens, proc { |_antigo|
    (AnilRefreshItens.marcar!("entrou no mapa") rescue nil)
  })
end

#-------------------------------------------------------------------------------
# 3. O cumprimento, um frame depois
#-------------------------------------------------------------------------------
if defined?(Scene_Map) && !Scene_Map.method_defined?(:anil_refitens_orig_update)
  Scene_Map.class_eval do
    alias_method :anil_refitens_orig_update, :update

    def update(*a)
      anil_refitens_orig_update(*a)
      (AnilRefreshItens.cumprir! if AnilRefreshItens.ha_pedido?) rescue nil
    end
  end
end

module AnilLanRework
  class << self
    unless method_defined?(:anil_refitens_orig_apply_post_plugin_patches)
      alias_method :anil_refitens_orig_apply_post_plugin_patches, :apply_post_plugin_patches rescue nil
    end

    def apply_post_plugin_patches
      anil_refitens_orig_apply_post_plugin_patches rescue nil
      AnilRefreshItens.instalar_canal! rescue nil
    end
  end
end
