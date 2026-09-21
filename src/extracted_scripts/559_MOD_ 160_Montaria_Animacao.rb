# encoding: UTF-8
#===============================================================================
# MOD: 160_Montaria_Animacao
#-------------------------------------------------------------------------------
# O salto para cima da montaria, e o salto para fora dela.
#
# ⚠️ MONTAR DEIXOU DE ACONTECER NO MENU. E O FIM DA ANIMACAO QUE MONTA.
#
# O 156 esconde o follower no instante em que `montado?` fica verdadeiro. Se o
# menu montasse e a animacao viesse depois, nao havia em cima de quem saltar: o
# bicho evaporava-se antes do salto comecar.
#
# Entao o menu passa a registar so a INTENCAO, e quem chama o montar! e a
# aterragem. Enquanto o salto decorre o follower ainda esta la, que e o unico
# jeito de a coisa se ler.
#
# ⚠️ O TILE DO FOLLOWER ESTA OCUPADO — POR ELE.
#
# O `jump` verifica `passable?` e recusa saltar para cima de um evento. Liga-se
# o `through` durante o salto e repoe-se ao aterrar. Mas isso tambem deixaria
# aterrar dentro de uma parede se o follower estivesse num sitio esquisito, por
# isso confere-se o terreno ANTES: se o destino nao for pisavel por si so, monta
# -se sem animacao em vez de partir alguma coisa.
#
# ⚠️ A INTENCAO NAO PODE SOBREVIVER A UM FECHO DO JOGO.
#
# Ela vive no $PokemonGlobal, portanto vai no save. Fechar o jogo a meio do
# salto deixaria um pedido pendente para sempre, e ao carregar o jogador ficava
# a saltar sozinho num mapa que ja nao e o mesmo. Na entrada do mapa resolve-se
# na hora, sem animacao.
#===============================================================================

class PokemonGlobalMetadata
  # [especie, personalID] enquanto o salto de montar nao aconteceu.
  attr_accessor :anil_montaria_pendente
  # true enquanto o salto de desmontar nao aconteceu.
  attr_accessor :anil_desmontar_pendente
end

module AnilMontariaAnim
  SOM_SALTO = "Player jump"

  # ⚠️ MEIO SEGUNDO A CONTAR DE QUANDO O MAPA VOLTA, NAO DE QUANDO SE ESCOLHE.
  #
  # A contagem so anda enquanto o `pode_animar?` for verdadeiro, e esse exige
  # Scene_Map sem menu nem mensagem. Portanto o tempo do menu a fechar nao conta
  # — sao sempre 30 frames de overworld parado antes do salto, tenha o menu
  # demorado o que tiver.
  ATRASO = 30

  # ⚠️ O BILHETE DE SAIDA, E PORQUE E ELE QUE MATA O PISCAR.
  #
  # O botao "Pokémon" do DP_PauseMenu e isto:
  #
  #     pbFadeOutIn(99999) do
  #       hiddenmove = sscreen.pbPokemonScreen
  #       if hiddenmove
  #         @sprites.visible = false     # <- DENTRO do fade
  #         @done = true
  #       end
  #     end
  #     if hiddenmove
  #       $game_temp.in_menu = false
  #       pbUseHiddenMove(hiddenmove[0], hiddenmove[1])
  #     end
  #
  # Repare-se em ONDE o `@sprites.visible = false` acontece: dentro do bloco do
  # fade, antes de o ecra voltar a aparecer. E por isso que um movimento de
  # campo (Voar, Surf) sai do menu sem se ver nada — e era por isso que a minha
  # tentativa anterior piscava: eu punha o @done DEPOIS do fade-in.
  #
  # Entao devolve-se um "movimento" fingido e usa-se a mesma porta. A unica
  # ponta solta e a linha do pbUseHiddenMove, que se trata la em baixo.
  SAIR = [nil, :ANIL_MONTARIA].freeze

  @fase = nil          # nil, :montar, :desmontar
  @through_antes = nil
  @espera = 0
  @fechar_menu = false
  @fechar_pausa = false

  class << self
    # ⚠️ SAO DOIS ECRAS, NAO UM.
    #
    # A equipa abre-se a partir do menu de pausa, e fechar so a equipa deixava o
    # menu de pausa por baixo — que foi o que aconteceu. Cada um tem a sua
    # porta e a sua bandeira:
    #
    #   equipa  -> pbChoosePokemon devolve negativo   (0303, linha 1278)
    #   pausa   -> pbShowCommands  devolve negativo   (0299, linha 118)
    #
    # Cada bandeira e lida UMA vez e limpa-se logo. E ainda ha uma segunda
    # condicao no leitor: so fecha se houver mesmo um pedido por cumprir. Sem
    # isso, uma bandeira que sobrasse fechava sozinho o proximo menu que o
    # jogador abrisse, e ninguem ia ligar uma coisa a outra.
    attr_accessor :fechar_menu
    attr_accessor :fechar_pausa
  end

  module_function

  def log(t)
    AnilLanRework.log("[MONTARIA/ANIM] #{t}") rescue nil
  end

  # --------------------------------------------------------------- pedidos
  def pedir_montar(pkmn)
    return false unless pkmn && $PokemonGlobal
    $PokemonGlobal.anil_montaria_pendente = [pkmn.species.to_s.upcase,
                                             (pkmn.personalID rescue nil)]
    @espera = ATRASO
    self.fechar_menu = true
    self.fechar_pausa = true
    true
  rescue
    false
  end

  def pedir_desmontar
    return false unless $PokemonGlobal
    $PokemonGlobal.anil_desmontar_pendente = true
    @espera = ATRASO
    self.fechar_menu = true
    self.fechar_pausa = true
    true
  rescue
    false
  end

  def limpar!
    $PokemonGlobal.anil_montaria_pendente = nil rescue nil
    $PokemonGlobal.anil_desmontar_pendente = nil rescue nil
    @fase = nil
    @espera = 0
    @fechar_menu = false
    @fechar_pausa = false
    repor_through!
  end

  # Ha mesmo um pedido a espera? E a guarda que impede uma bandeira esquecida
  # de fechar um menu que nada tem a ver com montarias.
  def ha_pedido?
    return false unless $PokemonGlobal
    !!($PokemonGlobal.anil_montaria_pendente || $PokemonGlobal.anil_desmontar_pendente)
  rescue
    false
  end

  def consumir_fechar_menu?
    return false unless @fechar_menu
    @fechar_menu = false
    ha_pedido?
  end

  def consumir_fechar_pausa?
    return false unless @fechar_pausa
    @fechar_pausa = false
    ha_pedido?
  end

  # ⚠️ O SALTO E CURTO DEMAIS PARA VIAJAR COMO POSICAO.
  #
  # Ele dura 0,125 s (jump_speed 4) e sobe 12 px. O outro lado recebe posicoes a
  # 10 por segundo e interpola-as em LINHA RECTA — ou seja, via um deslize, nunca
  # um arco, e nem sequer tinha amostras que chegassem para o desenhar.
  #
  # Entao nao se manda o arco: manda-se um AVISO. Este contador sobe a cada
  # salto, viaja no pacote de estado, e quem o ve muda toca o arco em casa, com
  # a mesma formula e o mesmo som. Um numero por salto, e nao por frame.
  def marcar_salto!
    $anil_montaria_salto_tok = ($anil_montaria_salto_tok.to_i + 1) & 0xFFFF
  rescue
    nil
  end

  # ------------------------------------------------------------- utilidades
  def pkmn_pedido
    pedido = ($PokemonGlobal.anil_montaria_pendente rescue nil)
    return nil unless pedido.is_a?(Array)
    esp, pid = pedido
    primeiro = nil
    (($player.party rescue nil) || []).each do |pk|
      next unless pk && (pk.species.to_s.upcase rescue "") == esp.to_s.upcase
      return pk if pid && (pk.personalID rescue nil) == pid
      primeiro ||= pk
    end
    primeiro
  rescue
    nil
  end

  def follower
    return nil unless defined?($game_temp) && $game_temp && $game_temp.respond_to?(:followers)
    ($game_temp.followers.get_follower_by_index(0) rescue nil)
  rescue
    nil
  end

  # Da para o jogador estar aqui a saltar agora?
  def pode_animar?
    return false unless $scene.is_a?(Scene_Map)
    return false unless $game_player && $game_map
    return false if $game_player.moving? || $game_player.jumping?
    return false if ($game_temp && $game_temp.in_menu) rescue false
    return false if (AnilLanRework.message_active rescue false)
    return false if ($game_temp && $game_temp.in_battle) rescue false
    true
  rescue
    false
  end

  # ⚠️ Pisavel SEM contar com o follower.
  #
  # O passable? do motor conta os eventos, e o follower e um deles — daria
  # sempre false justamente no tile para onde queremos saltar. Aqui pergunta-se
  # so pelo TERRENO, que e o que interessa para nao aterrar numa parede.
  def terreno_pisavel?(x, y)
    return false unless $game_map.valid?(x, y)
    return false unless $game_map.passable?(x, y, 0)
    t = ($game_map.terrain_tag(x, y) rescue nil)
    return false if t && (t.can_surf || t.ledge)
    true
  rescue
    false
  end

  def poeira!(x = nil, y = nil)
    return unless $scene.respond_to?(:spriteset)
    px = x || $game_player.x
    py = y || $game_player.y
    $scene.spriteset($game_map.map_id)&.addUserAnimation(Settings::DUST_ANIMATION_ID, px, py, true, 1)
  rescue
    nil
  end

  def repor_through!
    return if @through_antes.nil?
    ($game_player.through = @through_antes) rescue nil
    @through_antes = nil
  end

  def virar_para(dx, dy)
    if dx.abs > dy.abs
      dx < 0 ? $game_player.turn_left : $game_player.turn_right
    elsif dy != 0
      dy < 0 ? $game_player.turn_up : $game_player.turn_down
    end
  rescue
    nil
  end

  # --------------------------------------------------------------- montar
  def comecar_montar!
    pkmn = pkmn_pedido
    unless pkmn
      log("o Pokemon pedido ja nao esta na equipa; pedido descartado")
      limpar!
      return
    end

    fol = follower
    dx = fol ? (fol.x - $game_player.x) : 0
    dy = fol ? (fol.y - $game_player.y) : 0

    # Sem follower a vista, ou com ele longe/num sitio impossivel, monta-se
    # direito: mais vale sem animacao do que com o jogador a atravessar paredes.
    if fol.nil? || (dx.abs + dy.abs) != 1 || !terreno_pisavel?(fol.x, fol.y)
      log("sem salto (fol=#{fol ? "#{dx},#{dy}" : "nenhum"}); monta directo")
      concluir_montar!(pkmn)
      return
    end

    # a esta altura os menus ja fecharam; uma bandeira que sobre so pode
    # atrapalhar o proximo menu que o jogador abrir
    @fechar_menu = false
    @fechar_pausa = false
    virar_para(dx, dy)
    @through_antes = ($game_player.through rescue false)
    $game_player.through = true
    $game_player.jump(dx, dy)
    pbSEPlay(SOM_SALTO) rescue nil
    marcar_salto!
    @fase = :montar
  rescue => e
    log("falha ao comecar o salto: #{e.class}: #{e.message}")
    limpar!
  end

  def concluir_montar!(pkmn = nil)
    repor_through!
    pkmn ||= pkmn_pedido
    if pkmn
      AnilMontaria.montar!(pkmn.species, pkmn) rescue nil
      AnilMontariaComando.recarregar_sprite! rescue nil
      poeira!
    end
    $PokemonGlobal.anil_montaria_pendente = nil rescue nil
    @fase = nil
  rescue
    limpar!
  end

  # ------------------------------------------------------------- desmontar
  def comecar_desmontar!
    # Salta-se para um tile livre: primeiro o da frente, depois os outros.
    frente = case ($game_player.direction rescue 2)
             when 4 then [-1, 0]
             when 6 then [1, 0]
             when 8 then [0, -1]
             else        [0, 1]
             end
    destino = ([frente] + [[0, 1], [0, -1], [-1, 0], [1, 0]]).find do |dx, dy|
      terreno_pisavel?($game_player.x + dx, $game_player.y + dy)
    end

    unless destino
      log("sem tile livre para descer; desmonta directo")
      concluir_desmontar!
      return
    end

    # a esta altura os menus ja fecharam; uma bandeira que sobre so pode
    # atrapalhar o proximo menu que o jogador abrir
    @fechar_menu = false
    @fechar_pausa = false
    virar_para(destino[0], destino[1])
    @through_antes = ($game_player.through rescue false)
    $game_player.through = true
    $game_player.jump(destino[0], destino[1])
    pbSEPlay(SOM_SALTO) rescue nil
    marcar_salto!
    @fase = :desmontar
  rescue => e
    log("falha ao comecar a descida: #{e.class}: #{e.message}")
    limpar!
  end

  def concluir_desmontar!
    repor_through!
    AnilMontaria.desmontar! rescue nil
    AnilMontariaComando.recarregar_sprite! rescue nil
    poeira!
    $PokemonGlobal.anil_desmontar_pendente = nil rescue nil
    @fase = nil
  rescue
    limpar!
  end

  # ------------------------------------------------------------- o motor
  def actualizar
    return unless $PokemonGlobal

    # a decorrer: espera-se a aterragem
    if @fase
      return if ($game_player.jumping? rescue false)
      case @fase
      when :montar    then concluir_montar!
      when :desmontar then concluir_desmontar!
      end
      return
    end

    pendente = $PokemonGlobal.anil_desmontar_pendente || $PokemonGlobal.anil_montaria_pendente
    return unless pendente
    return unless pode_animar?

    # a espera so corre com o mapa a vista e o jogador parado
    if @espera.to_i > 0
      @espera -= 1
      return
    end

    if $PokemonGlobal.anil_desmontar_pendente
      comecar_desmontar!
    else
      comecar_montar!
    end
  rescue => e
    log("erro no ciclo: #{e.class}: #{e.message}")
    limpar!
  end

  # Ao entrar num mapa, um pedido que sobrou de outra sessao resolve-se sem
  # animacao — ver a nota de topo.
  def resolver_pendentes_sem_animacao!
    return unless $PokemonGlobal
    @espera = 0
    if $PokemonGlobal.anil_desmontar_pendente
      log("pedido de descida vindo do save; resolvido sem animacao")
      concluir_desmontar!
    end
    if $PokemonGlobal.anil_montaria_pendente
      log("pedido de montada vindo do save; resolvido sem animacao")
      concluir_montar!
    end
  rescue
    limpar!
  end
end

#-------------------------------------------------------------------------------
# Fechar o ecra da equipa sozinho ao escolher Montar/Desmontar.
#
# ⚠️ O RETORNO DO "effect" NAO SERVE PARA NADA.
#
# O 0303 faz `commands[choice]["effect"].call(...)` e deita o resultado fora —
# devolver true nao fecha ecra nenhum. Quem manda no ciclo e a linha
#
#     break if (party_idx.is_a?(Numeric) && party_idx < 0) || ...
#
# com o party_idx a vir do `pbChoosePokemon`. Entao e esse que se intercepta:
# uma vez, devolve negativo, e o ecra sai pela porta normal dele.
#
# ⚠️ A bandeira limpa-se na LEITURA, nao no fim do salto. Se ficasse pendurada,
# o proximo ecra da equipa fechava-se sozinho sem ninguem perceber porque.
#-------------------------------------------------------------------------------
module AnilMontariaAnim
  module_function

  def instalar_saida_do_menu!
    return false unless defined?(PokemonParty_Scene)
    return false if PokemonParty_Scene.method_defined?(:anil_montaria_orig_pbChoosePokemon)
    PokemonParty_Scene.class_eval do
      alias_method :anil_montaria_orig_pbChoosePokemon, :pbChoosePokemon

      def pbChoosePokemon(*args)
        return -1 if AnilMontariaAnim.consumir_fechar_menu?
        anil_montaria_orig_pbChoosePokemon(*args)
      end
    end

    # ⚠️ O MENU DE PAUSA DESTE JOGO NAO E O DO MOTOR.
    #
    # Eu tinha enxertado no PokemonPauseMenu_Scene e nao aconteceu nada: quem
    # esta no ecra e o DP_PauseMenu, do plugin PauseMenuDP (o 029 so lhe mexe no
    # initialize, e o 061 poe-lhe o toque por cima). Ele nao usa pbShowCommands
    # nenhum — tem um `main` proprio, e a saida dele e uma bandeira:
    #
    #     if @done
    #       break
    #     elsif Input.trigger?(Input::BACK)
    #
    # O `update` corre no topo de cada volta desse ciclo, portanto e o sitio
    # certo para levantar o @done: uma volta depois, o menu sai pela mesma porta
    # que o botao B usa.
    if defined?(DP_PauseMenu) && !DP_PauseMenu.method_defined?(:anil_montaria_orig_update)
      DP_PauseMenu.class_eval do
        alias_method :anil_montaria_orig_update, :update

        def update
          anil_montaria_orig_update
          @done = true if AnilMontariaAnim.consumir_fechar_pausa?
        rescue
          nil
        end
      end
      log("saida instalada no DP_PauseMenu")
    end

    # ⚠️ A PORTA PRINCIPAL: O RETORNO DO ECRA DA EQUIPA.
    #
    # Isto e o que evita o piscar. O enxerto no DP_PauseMenu#update aqui em cima
    # continua como rede, mas so dispara se esta nao tiver apanhado a bandeira —
    # e apanha, porque corre primeiro.
    if defined?(PokemonPartyScreen) &&
       !PokemonPartyScreen.method_defined?(:anil_montaria_orig_pbPokemonScreen)
      PokemonPartyScreen.class_eval do
        alias_method :anil_montaria_orig_pbPokemonScreen, :pbPokemonScreen

        def pbPokemonScreen(*args)
          ret = anil_montaria_orig_pbPokemonScreen(*args)
          return AnilMontariaAnim::SAIR if AnilMontariaAnim.consumir_fechar_pausa?
          ret
        end
      end
      log("saida instalada no retorno do ecra da equipa")
    end

    # ⚠️ E a ponta solta: o menu chama pbUseHiddenMove com o que lhe devolvemos.
    #
    # Sem isto ele ia tentar usar um movimento chamado :ANIL_MONTARIA. Nao ha
    # nenhum com esse nome, portanto a guarda nunca apanha um movimento a serio.
    unless defined?($anil_montaria_hiddenmove_patch) && $anil_montaria_hiddenmove_patch
      $anil_montaria_hiddenmove_patch = true
      if Object.private_method_defined?(:pbUseHiddenMove) || Object.method_defined?(:pbUseHiddenMove)
        Object.class_eval do
          alias_method :anil_montaria_orig_pbUseHiddenMove, :pbUseHiddenMove

          def pbUseHiddenMove(pokemon, move)
            return false if move == :ANIL_MONTARIA
            anil_montaria_orig_pbUseHiddenMove(pokemon, move)
          end
        end
        AnilMontariaAnim.log("guarda posta no pbUseHiddenMove")
      end
    end

    # E o do motor tambem, para o caso de alguma rota ainda cair nele.
    if defined?(PokemonPauseMenu_Scene) &&
       !PokemonPauseMenu_Scene.method_defined?(:anil_montaria_orig_pbShowCommands)
      PokemonPauseMenu_Scene.class_eval do
        alias_method :anil_montaria_orig_pbShowCommands, :pbShowCommands

        def pbShowCommands(*args)
          return -1 if AnilMontariaAnim.consumir_fechar_pausa?
          anil_montaria_orig_pbShowCommands(*args)
        end
      end
    end

    log("saida automatica dos dois menus instalada")
    true
  rescue => e
    log("falha ao instalar a saida do menu: #{e.class}: #{e.message}")
    false
  end
end

module AnilLanRework
  class << self
    unless method_defined?(:anil_montanim_orig_apply_post_plugin_patches)
      alias_method :anil_montanim_orig_apply_post_plugin_patches, :apply_post_plugin_patches rescue nil
    end

    def apply_post_plugin_patches
      anil_montanim_orig_apply_post_plugin_patches rescue nil
      AnilMontariaAnim.instalar_saida_do_menu! rescue nil
    end
  end
end

if defined?(EventHandlers) && EventHandlers.respond_to?(:add)
  EventHandlers.add(:on_frame_update, :anil_montaria_animacao, proc {
    AnilMontariaAnim.actualizar
  })
  EventHandlers.add(:on_enter_map, :anil_montaria_animacao_limpar, proc { |_antigo|
    AnilMontariaAnim.resolver_pendentes_sem_animacao!
  })
end

AnilLanRework.log("160_Montaria_Animacao carregado") rescue nil
