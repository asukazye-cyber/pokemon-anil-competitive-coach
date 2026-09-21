# encoding: UTF-8
#===============================================================================
# MOD: 153_Relearner_Cobra_Pepita
#-------------------------------------------------------------------------------
# O NPC do Centro Pokemon que relembra/ensina ataques passa a cobrar uma PEPITA
# (NUGGET) por ataque aprendido.
#
# ⚠️ COBRA-SE PELO RESULTADO, NAO PELA VISITA.
#
# O ecra e o UI::MoveReminder (do plugin BetterMoveRelearner, que substitui o
# pbRelearnMoveScreen do Essentials). O valor que ele devolve nao e um contrato
# em que se possa confiar para saber se houve mesmo aprendizagem — pode voltar
# true ao fechar, conforme o modo (`:single` ou `:normal`).
#
# Por isso compara-se a lista de golpes ANTES e DEPOIS. Se mudou, ensinou-se
# alguma coisa e cobra-se. Se o jogador entrou e desistiu, nao paga nada.
#
# ⚠️ A verificacao de posse e feita ANTES de abrir o ecra, para nao deixar o
# jogador escolher um ataque e so depois descobrir que nao pode pagar.
#===============================================================================

module AnilRelearnerPepita
  ITEM = :NUGGET

  module_function

  def item_existe?
    GameData::Item.exists?(ITEM)
  rescue
    false
  end

  def nome_item
    GameData::Item.get(ITEM).name
  rescue
    "Pepita"
  end

  # Lista estavel dos golpes, para comparar antes/depois.
  def golpes(pkmn)
    return [] unless pkmn && pkmn.respond_to?(:moves)
    Array(pkmn.moves).map { |m| m && (m.id rescue m.to_s) }.compact
  rescue
    []
  end

  def tem_pepita?
    ($bag.has?(ITEM) rescue false)
  end

  def cobrar!
    $bag.remove(ITEM, 1)
  rescue
    nil
  end

  def quantas
    ($bag.quantity(ITEM) rescue 0)
  end
end

#-------------------------------------------------------------------------------
# O pbRelearnMoveScreen e um metodo de topo (Object). O plugin
# BetterMoveRelearner redefine-o, e este MOD carrega ANTES dos plugins — por
# isso o encadeamento vai no apply_post_plugin_patches, quando a versao final
# ja esta instalada. Sem isso estariamos a envolver a versao do Essentials, que
# o plugin substitui logo a seguir.
#-------------------------------------------------------------------------------
module AnilLanRework
  class << self
    unless method_defined?(:anil_pepita_orig_apply_post_plugin_patches)
      alias_method :anil_pepita_orig_apply_post_plugin_patches, :apply_post_plugin_patches rescue nil
    end

    def apply_post_plugin_patches
      anil_pepita_orig_apply_post_plugin_patches rescue nil
      begin
        next_ok = Object.method_defined?(:pbRelearnMoveScreen) ||
                  Object.private_method_defined?(:pbRelearnMoveScreen)
        if next_ok && !Object.private_method_defined?(:anil_pepita_orig_relearn)
          Object.class_eval do
            alias_method :anil_pepita_orig_relearn, :pbRelearnMoveScreen

            def pbRelearnMoveScreen(pkmn)
              unless AnilRelearnerPepita.item_existe?
                return anil_pepita_orig_relearn(pkmn)
              end

              nome = AnilRelearnerPepita.nome_item
              unless AnilRelearnerPepita.tem_pepita?
                pbMessage(_INTL("Cobro 1 {1} por cada movimento que eu relembre. Volte quando tiver uma!", nome))
                return false
              end

              antes = AnilRelearnerPepita.golpes(pkmn)
              ret   = anil_pepita_orig_relearn(pkmn)
              depois = AnilRelearnerPepita.golpes(pkmn)

              if antes != depois
                AnilRelearnerPepita.cobrar!
                pbMessage(_INTL("Paguei-me com 1 {1}. Restam {2}.",
                                nome, AnilRelearnerPepita.quantas))
              end
              ret
            end
          end
          AnilLanRework.log("[PEPITA] relearner passa a cobrar 1 #{AnilRelearnerPepita.nome_item}") rescue nil
        end
      rescue => e
        AnilLanRework.log("[PEPITA] falha ao instalar: #{e.class}: #{e.message}") rescue nil
      end
    end
  end
end

AnilLanRework.log("153_Relearner_Cobra_Pepita carregado") rescue nil
