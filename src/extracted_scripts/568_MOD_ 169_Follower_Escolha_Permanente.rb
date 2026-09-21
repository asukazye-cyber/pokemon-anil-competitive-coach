# encoding: UTF-8
#===============================================================================
# MOD: 169_Follower_Escolha_Permanente
#-------------------------------------------------------------------------------
# ⚠️ GUARDADO E GUARDADO. PARA SEMPRE, ATE A TECLA DIZER O CONTRARIO.
#
# A primeira versao disto andava a tapar buracos um a um — envolvia o
# `pbStartSurfing` e o `pbEndSurf` e repunha o estado a seguir. Nao chegou: o
# seguidor voltava a aparecer na agua na mesma. E previsivel, porque ha meia
# duzia de sitios no motor e nos plugins a mexer no `follower_toggled`, e tapar
# um a um e uma corrida que nunca se ganha.
#
# Entao inverte-se: guarda-se a ESCOLHA do jogador, e e ela que manda. Quem quer
# que mexa no estado, seja quem for, e reposto no frame seguinte.
#
# ⚠️ O QUE E "ESCOLHA" E O QUE E O SISTEMA A MANDAR.
#
# Ha duas maneiras diferentes de mexer neste estado, e o plugin ja as separa:
#
#   FollowingPkmn.toggle(nil)   -> a TECLA do jogador. Nao mexe na tranca.
#   toggle_off / toggle_on      -> o SISTEMA (raids, cenas, o Cable Club).
#                                  Estes poem e tiram a tranca.
#
# Portanto: a escolha grava-se quando o `follower_toggled` muda FORA de uma
# chamada do sistema, e a repescagem so acontece quando NAO ha tranca posta. Uma
# raid continua a poder esconder o seguidor; o que ja nao pode e a agua deixa-lo
# ligado depois de o jogador o ter guardado.
#
# ⚠️ NA AGUA, QUEM DECIDE E O PLUGIN.
#
# Se a escolha for "visivel" e o Pokemon nao souber nadar, ele continua a nao
# aparecer — isso e o `refresh_internal` a correr o handler
# `:following_pkmn_appear`, que ja tem essa regra. Nos so garantimos que a
# ESCOLHA nao e apagada pelo caminho.
#===============================================================================

class PokemonGlobalMetadata
  # true = quero ver, false = quero guardado, nil = ainda nao disse nada.
  attr_accessor :anil_follower_escolha
end

module AnilFollowerEscolha
  ACTIVO = true
  # Nao e preciso verificar a cada frame: isto nao muda depressa.
  INTERVALO = 15

  class << self
    # Enquanto isto estiver a true, quem mexe e o sistema e nao o jogador.
    def sistema?
      @sistema == true
    end

    def como_sistema
      antes = @sistema
      @sistema = true
      yield
    ensure
      @sistema = antes
    end

    def gravar_escolha!(v)
      return if sistema?
      return unless $PokemonGlobal
      return if $PokemonGlobal.anil_follower_escolha == v
      $PokemonGlobal.anil_follower_escolha = v
      AnilLanRework.log("[FOLLOWER] escolha do jogador: #{v ? "visivel" : "guardado"}") rescue nil
    rescue
      nil
    end

    # Se alguem repintou o seguidor que devia estar guardado, apaga-se outra vez.
    def repor_escondido!
      return unless defined?(FollowingPkmn)
      ev = (FollowingPkmn.get_event rescue nil)
      dt = (FollowingPkmn.get_data rescue nil)
      sujo = false
      sujo = true if ev && !ev.character_name.to_s.empty?
      sujo = true if dt && !dt.character_name.to_s.empty?
      return unless sujo
      como_sistema { (FollowingPkmn.remove_sprite rescue nil) }
      AnilLanRework.log("[FOLLOWER] sprite reaparecido foi tirado outra vez") rescue nil
    rescue
      nil
    end

    # ⚠️ Repoe escrevendo nas variaveis, sem passar pelo `toggle`.
    #
    # O `toggle` comeca por `return if follower_toggle_locked`, e a tranca e
    # justamente o estado em que estas coisas costumam acabar.
    def verificar!
      return unless ACTIVO
      @frames = (@frames || 0) + 1
      return if @frames < INTERVALO
      @frames = 0
      return unless $PokemonGlobal && defined?(FollowingPkmn)
      escolha = $PokemonGlobal.anil_follower_escolha
      return if escolha.nil?
      # Tranca posta = o sistema esta a mandar de proposito. Respeita-se.
      return if $PokemonGlobal.follower_toggle_locked == true
      if $PokemonGlobal.follower_toggled != escolha
        como_sistema do
          $PokemonGlobal.follower_toggled = escolha
          (FollowingPkmn.refresh(false) rescue nil)
        end
        AnilLanRework.log("[FOLLOWER] estado reposto para #{escolha ? "visivel" : "guardado"}") rescue nil
        return
      end
      # ⚠️ E TAMBEM SE VIGIA O SPRITE, NAO SO A BANDEIRA.
      #
      # O plugin esconde o seguidor BLANQUEANDO o charset (`remove_sprite`), e
      # nao com transparencia. Portanto ha duas maneiras de ele reaparecer, e a
      # bandeira so cobre uma: qualquer codigo que escreva um `character_name`
      # no evento do seguidor traz o bicho de volta com o `follower_toggled`
      # ainda em false — foi o que aconteceu com o nosso proprio
      # `refresh_local_follower!`.
      #
      # Com a escolha em "guardado", se aparecer nome, tira-se. Usa-se o metodo
      # do proprio plugin para o fazer exactamente como ele faria.
      repor_escondido! if escolha == false
    rescue
      nil
    end
  end
end

if AnilFollowerEscolha::ACTIVO
  module AnilLanRework
    class << self
      unless method_defined?(:anil_folesc_orig_apply_post_plugin_patches)
        alias_method :anil_folesc_orig_apply_post_plugin_patches, :apply_post_plugin_patches rescue nil
      end

      def apply_post_plugin_patches
        anil_folesc_orig_apply_post_plugin_patches if respond_to?(:anil_folesc_orig_apply_post_plugin_patches)
        begin
          if defined?(FollowingPkmn) && defined?(PokemonGlobalMetadata)
            # ---- a tecla do jogador grava a escolha ----------------------
            FollowingPkmn.singleton_class.class_eval do
              unless method_defined?(:anil_folesc_orig_toggle)
                alias_method :anil_folesc_orig_toggle, :toggle
                def toggle(forced = nil, anim = nil)
                  if forced.nil?
                    ret = anil_folesc_orig_toggle(forced, anim)
                    AnilFollowerEscolha.gravar_escolha!($PokemonGlobal.follower_toggled == true) rescue nil
                    return ret
                  end
                  # Com valor forcado e alguem a repor estado, nao o jogador.
                  AnilFollowerEscolha.como_sistema { anil_folesc_orig_toggle(forced, anim) }
                end
              end
              unless method_defined?(:anil_folesc_orig_toggle_off)
                alias_method :anil_folesc_orig_toggle_off, :toggle_off
                def toggle_off(anim = nil)
                  AnilFollowerEscolha.como_sistema { anil_folesc_orig_toggle_off(anim) }
                end
              end
              unless method_defined?(:anil_folesc_orig_toggle_on)
                alias_method :anil_folesc_orig_toggle_on, :toggle_on
                def toggle_on(anim = nil)
                  AnilFollowerEscolha.como_sistema { anil_folesc_orig_toggle_on(anim) }
                end
              end
            end

            # ---- o repintor da agua -------------------------------------
            # ⚠️ AQUI ESTAVA O PISCAR.
            #
            # O `follow_leader` do plugin (04_09) troca o sprite quando o
            # seguidor passa de terra para agua, para usar a arte a nadar:
            #
            #     if old_terrain && (old_terrain.can_surf != new_terrain.can_surf)
            #       pkmn = FollowingPkmn.get_pokemon
            #       FollowingPkmn.change_sprite(pkmn) if pkmn
            #     end
            #
            # Sem perguntar se ele esta VISIVEL. Com o seguidor guardado, entrar
            # na agua repintava-o na mesma — aparecia um frame a fazer o salto e
            # so desaparecia quando a vigia o voltava a apagar.
            #
            # Tapa-se no `change_sprite`, que e por onde todos os caminhos
            # passam: quem esta guardado nao ganha sprite, venha o pedido de
            # onde vier. O `refresh` do plugin so o chama quando esta activo,
            # portanto nao se perde nada legitimo.
            FollowingPkmn.singleton_class.class_eval do
              unless method_defined?(:anil_folesc_orig_change_sprite)
                alias_method :anil_folesc_orig_change_sprite, :change_sprite
                def change_sprite(pkmn)
                  return if ($PokemonGlobal && $PokemonGlobal.follower_toggled == false) rescue false
                  anil_folesc_orig_change_sprite(pkmn)
                end
              end
            end

            # ---- o menu de opcoes escreve directamente ------------------
            # Ele faz `$PokemonGlobal.follower_toggled = (value == 0)`, sem
            # passar pelo toggle. Apanha-se no proprio setter.
            PokemonGlobalMetadata.class_eval do
              unless method_defined?(:anil_folesc_orig_follower_toggled=)
                alias_method :anil_folesc_orig_follower_toggled=, :follower_toggled=
                def follower_toggled=(v)
                  ret = send(:anil_folesc_orig_follower_toggled=, v)
                  AnilFollowerEscolha.gravar_escolha!(v == true) rescue nil
                  ret
                end
              end
            end
            AnilLanRework.log("[FOLLOWER] escolha permanente activa") rescue nil
          end
        rescue => e
          AnilLanRework.log("[FOLLOWER] falha na escolha permanente: #{e.class}: #{e.message}") rescue nil
        end
      end
    end
  end

  class Scene_Map
    alias anil_folesc_update update unless method_defined?(:anil_folesc_update)

    def update
      anil_folesc_update
      AnilFollowerEscolha.verificar! rescue nil
    end
  end
end

AnilLanRework.log("169_Follower_Escolha_Permanente carregado") rescue nil
