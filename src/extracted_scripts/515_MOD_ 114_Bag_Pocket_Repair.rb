#===============================================================================
# MOD: 114_Bag_Pocket_Repair.rb
#-------------------------------------------------------------------------------
# Move para o bolso certo os itens que ficaram guardados no bolso errado.
#
# POR QUE ISSO ACONTECE
# O bolso NAO e lido do dado do item a cada vez: ele e decidido no momento em
# que o item entra na mochila, e o save guarda o item ja dentro de @pockets[n].
# Quando um item muda de Pocket no PBS, as unidades que o jogador JA tinha
# continuam no bolso antigo para sempre.
#
# O CASO QUE MOTIVOU
# Amuleto Iris, Mascara Turquesa, Vasija Castigo e companhia eram Objetos Clave
# (bolso 8). Passaram a ser itens comuns comercializaveis (bolso 1), com uma
# versao KEY... separada que e o Objeto Clave de verdade. Quem ja possuia a
# versao antiga continuou com ela no bolso 8 — e la ela aparecia com quantidade,
# oferecendo "Usar", "Tirar" e "Jogar no chao", porque o dado atual diz que ela
# NAO e mais um item chave. Resultado: o mesmo nome aparecendo duas vezes na aba
# de Objetos Clave, uma delas se comportando como item comum.
#
# O reparo devolve cada unidade ao bolso que o dado manda. Nada e criado nem
# destruido: o Amuleto antigo vira o item comum comercializavel que ele hoje e,
# e a aba de Objetos Clave fica so com as versoes KEY..., que tem a flag KeyItem
# e portanto nao podem ser jogadas fora nem vendidas.
#
# Roda uma vez por save, na primeira leitura da mochila.
#===============================================================================

class PokemonBag
  unless method_defined?(:anil_pocketfix_pockets)
    alias anil_pocketfix_pockets pockets

    def pockets
      ret = anil_pocketfix_pockets
      # A marca vai ANTES do reparo: se algo falhar no meio, nao entra em laco
      # de tentar de novo a cada acesso (pockets e chamado o tempo todo).
      unless @anil_pockets_repaired
        @anil_pockets_repaired = true
        anil_repair_pockets!(ret)
      end
      ret
    end

    def anil_repair_pockets!(pockets)
      return unless pockets.is_a?(Array)
      mudar = []

      pockets.each_with_index do |bolso, idx|
        next unless bolso.is_a?(Array)
        bolso.reject! do |entrada|
          next false unless entrada.is_a?(Array) && entrada[0]
          correto = begin
            GameData::Item.get(entrada[0]).pocket
          rescue
            idx # item desconhecido: deixa onde esta
          end
          if correto.to_i != idx && pockets[correto.to_i].is_a?(Array)
            mudar << [entrada[0], entrada[1].to_i, idx, correto.to_i]
            true
          else
            false
          end
        end
      end

      return if mudar.empty?

      mudar.each do |id, qtd, de, para|
        qtd = 1 if qtd < 1
        # Item chave nunca empilha: manter quantidade faria a mochila exibir
        # "x 2" num Objeto Clave.
        importante = (GameData::Item.get(id).is_important? rescue false)
        qtd = 1 if importante

        destino = pockets[para]
        existente = destino.find { |e| e.is_a?(Array) && e[0] == id }
        if existente
          existente[1] = importante ? 1 : (existente[1].to_i + qtd)
        else
          destino.push([id, qtd])
        end
        AnilLanRework.log("[BOLSO] #{id} movido do bolso #{de} para o #{para} (x#{qtd})") rescue nil
      end

      # Reordena os bolsos tocados, se a configuracao pedir ordenacao.
      # Mesmos criterios do PokemonBag original (linhas 108-110 e 292-293):
      # o indice de BAG_POCKET_AUTO_SORT e "bolso - 1", e a ordem sai da
      # posicao do item em GameData::Item.keys.
      begin
        if defined?(Settings::BAG_POCKET_AUTO_SORT)
          mudar.map { |m| m[3] }.uniq.each do |idx|
            next if idx == 0
            next unless Settings::BAG_POCKET_AUTO_SORT[idx - 1]
            pockets[idx].sort! { |a, b| GameData::Item.keys.index(a[0]) <=> GameData::Item.keys.index(b[0]) }
          end
        end
      rescue
      end
    end
  end
end
