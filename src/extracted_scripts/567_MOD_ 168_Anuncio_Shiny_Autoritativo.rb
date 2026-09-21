# encoding: UTF-8
#===============================================================================
# MOD: 168_Anuncio_Shiny_Autoritativo
#-------------------------------------------------------------------------------
# ⚠️ HAVIA DOIS ANUNCIOS DE SHINY, E O PRIMEIRO MENTIA.
#
# O plugin VOE, no fim do `spawnPokeEvent`, faz isto:
#
#     if pokemon.super_shiny? then addUserAnimation(53, x, y)
#     elsif pokemon.shiny?    then addUserAnimation(52, x, y)
#
# com o resultado do sorteio DELE — que corre uns milissegundos antes de nos
# decidirmos o estado final no MOD 070. Quando o sorteio dele acerta e o nosso
# nao, o jogador ve o clarao, ouve o som, ve o boneco colorido durante um
# instante... e entra numa batalha com um Pokemon vulgar. O bicho nunca foi
# shiny: o que ele viu foi um palpite que nos anulamos a seguir.
#
# E nao era raro. O sorteio do plugin e da mesma ordem de grandeza do nosso
# (1 em 5000, ou 1 em 500 com amuleto e cadeia cheia), e os dois sao
# independentes — portanto quase TODO o shiny que o plugin canta e um falso
# alarme, porque a probabilidade de nos concordarmos por acaso e minuscula.
#
# ⚠️ TAPA-SE A BOCA AO PLUGIN, NAO SE LHE MEXE NO SORTEIO.
#
# O sorteio dele continua a correr — e preciso, porque e ele que pinta o sprite
# inicial e nos so corrigimos o que ficou diferente. O que se cala e o ANUNCIO,
# e so durante a criacao do spawn. Quem anuncia passa a ser o MOD 070, ja com o
# estado final na mao, usando exactamente as mesmas animacoes 52 e 53.
#
# A alternativa seria editar o PluginScripts.rxdata, que o updater nao
# distribui. Isto vive todo no Scripts.rxdata e chega a toda a gente.
#===============================================================================

module AnilAnuncioSpawn
  ACTIVO = true

  # As animacoes do proprio plugin: 52 = shiny, 53 = super shiny.
  ANIMS = [52, 53]

  class << self
    def bloqueado?
      ACTIVO && @bloqueado == true
    end

    # ⚠️ Com `ensure` sempre, e nunca a mao.
    #
    # Se o `spawnPokeEvent` rebentar a meio com a bandeira levantada, todas as
    # animacoes de shiny do resto da sessao ficavam caladas.
    def calado
      antes = @bloqueado
      @bloqueado = true
      yield
    ensure
      @bloqueado = antes
    end
  end
end

module AnilLanRework
  class << self
    if !method_defined?(:anil_anuncio_orig_apply_post_plugin_patches)
      alias_method :anil_anuncio_orig_apply_post_plugin_patches, :apply_post_plugin_patches rescue nil
    end

    def apply_post_plugin_patches
      anil_anuncio_orig_apply_post_plugin_patches if respond_to?(:anil_anuncio_orig_apply_post_plugin_patches)
      return unless AnilAnuncioSpawn::ACTIVO
      begin
        if defined?(Spriteset_Map)
          Spriteset_Map.class_eval do
            unless method_defined?(:anil_anuncio_addUserAnimation)
              alias_method :anil_anuncio_addUserAnimation, :addUserAnimation

              def addUserAnimation(animID, x, y, tinting = false, height = 3)
                if AnilAnuncioSpawn.bloqueado? && AnilAnuncioSpawn::ANIMS.include?(animID)
                  return nil
                end
                anil_anuncio_addUserAnimation(animID, x, y, tinting, height)
              end
            end
          end
          AnilLanRework.log("[ANUNCIO_SHINY] anuncio prematuro do VOE silenciado") rescue nil
        end
      rescue => e
        AnilLanRework.log("[ANUNCIO_SHINY] falhou: #{e.class}: #{e.message}") rescue nil
      end
    end
  end
end
