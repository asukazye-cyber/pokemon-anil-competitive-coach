# encoding: UTF-8
#===============================================================================
# MOD: 175_Comando_Menu
#-------------------------------------------------------------------------------
# `/menu` abre o menu multijogador — o mesmo que o F7.
#
# ⚠️ PORQUE E QUE ISTO PRECISA DE EXISTIR.
#
# O menu do jogo online esta atras de UMA tecla, e num teclado com o F7 partido
# — ou num telemovel, onde as teclas de funcao vivem numa barra que nem sempre
# aparece — nao ha outra porta. O jogador fica sem acesso ao mercado, ao
# ranking e a tudo o resto, sem nada no ecra a explicar porque.
#
# O chat ja e o caminho que toda a gente tem, em qualquer aparelho. Um comando
# resolve sem acrescentar botoes nem mexer no HUD.
#
# ⚠️ NAO E COMANDO DE ADMIN.
#
# Ao contrario do /clima ou do /npc, isto nao da vantagem nenhuma: abre uma
# porta que ja esta aberta para quem tem o teclado bom. Limitar aos admins seria
# deixar de fora exactamente quem precisa.
#===============================================================================

module AnilComandoMenu
  ACTIVO = true

  module_function

  def log(t)
    AnilLanRework.log("[MENU] #{t}") rescue nil
  end

  # ⚠️ As mesmas condicoes do F7, e nao so "abrir".
  #
  # O atalho do teclado so responde no mapa, com o jogador parado e sem caixas
  # de texto abertas. Abrir por comando sem esses cuidados metia o menu por
  # cima de uma batalha ou de um dialogo — e o F7 nunca fez isso.
  def pode_abrir?
    return false unless ($scene.is_a?(Scene_Map) rescue false)
    return false if ($game_temp && $game_temp.in_battle rescue false)
    return false if ($game_temp && $game_temp.message_window_showing rescue false)
    return false if (pbMapInterpreterRunning? rescue false)
    true
  rescue
    false
  end

  def abrir!
    return false unless defined?(Scene_Map_MultiplayerMainMenu)
    pbPlayDecisionSE rescue nil
    ($game_player.straighten rescue nil)
    Scene_Map_MultiplayerMainMenu.open
    true
  rescue => e
    log("falha ao abrir: #{e.class}: #{e.message}")
    false
  end

  # Devolve true se tratou o texto (e portanto ele NAO vira mensagem de chat).
  def tratar(texto)
    return false unless ACTIVO
    t = texto.to_s.strip
    # Aceita "/menu" e "/menu f7" — quem so conhece a tecla escreve as duas.
    return false unless t =~ %r{\A/menu(?:\s+f7)?\z}i

    unless pode_abrir?
      (pbMessage(_INTL("Só dá para abrir o menu no mapa, parado.")) rescue nil)
      return true
    end

    # ⚠️ Abre-se DEPOIS de o chat fechar, e nao aqui.
    #
    # A caixa do chat ainda esta no ecra quando isto corre. Abrir o menu por
    # cima dela deixava as duas a disputar o teclado — foi o que aconteceu com
    # o Sweet Scent no menu da equipa, e a solucao foi a mesma: guardar o
    # pedido e cumpri-lo no ciclo seguinte do mapa.
    @pedido = true
    true
  rescue => e
    log("falha no comando: #{e.class}: #{e.message}")
    false
  end

  def ha_pedido?
    @pedido == true
  end

  def cumprir_pedido!
    return unless @pedido
    return unless pode_abrir?
    @pedido = nil
    abrir!
  rescue
    @pedido = nil
  end
end

#-------------------------------------------------------------------------------
# O gancho no chat, com o mesmo padrao dos outros comandos.
#-------------------------------------------------------------------------------
module AnilLanRework
  module Chat
    class << self
      if !method_defined?(:anil_menu_orig_send_message)
        alias_method :anil_menu_orig_send_message, :send_message rescue nil
      end

      def send_message(text)
        return if AnilComandoMenu.tratar(text)
        anil_menu_orig_send_message(text)
      end
    end
  end
end

#-------------------------------------------------------------------------------
# E o cumprimento, um frame depois, com o chat ja fora do caminho.
#-------------------------------------------------------------------------------
if defined?(Scene_Map) && !Scene_Map.method_defined?(:anil_menu_orig_update)
  Scene_Map.class_eval do
    alias_method :anil_menu_orig_update, :update

    def update(*a)
      anil_menu_orig_update(*a)
      (AnilComandoMenu.cumprir_pedido! if AnilComandoMenu.ha_pedido?) rescue nil
    end
  end
end
