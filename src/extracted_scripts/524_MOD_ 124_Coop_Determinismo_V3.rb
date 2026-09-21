#===============================================================================
# MOD: 124_Coop_Determinismo_V3.rb
#-------------------------------------------------------------------------------
# Fase 1 (determinismo) + Fase 3 (cobertura e deteccao) do BRIEFING_COOP_DESYNC.md.
#
# Este arquivo carrega DEPOIS do 000d e do 029, entao os wrappers daqui ficam na
# camada mais externa — de proposito: o hash de turno precisa ver o estado JA
# estabilizado por todas as outras camadas.
#
# O que esta aqui:
#   1.3  ordem do turno autoritativa (host manda a ordem, guest aplica)
#   3.3  hash de turno canonico + reconciliacao por snapshot
#   + desliga o "turno autoritativo" (proto 2), que virou contraproducente
#
# O que esta no 000d (edicoes no lugar):
#   1.1  RNG contador-base (classe BattleRNG) + gate COOP_RNG_PROTO
#   3.1  campos de estado no snapshot (stages/ability/item/types/PP/flags)
#   3.2  weather/terrain dentro do snapshot
#   3.4  supressao de texto fixada no inicio da batalha
#
# NAO precisa de nada no servidor: o dispatcher relaya qualquer tipo de pacote
# que tenha "to_id" (server_runtime.rb, else do case ~5040).
#===============================================================================

#-------------------------------------------------------------------------------
# DESLIGA O TURNO AUTORITATIVO (proto 2)
#
# O proto 2 (000d, secao "EVOLUCAO do fim de turno autoritativo") fazia o guest
# SUPRIMIR pbReduceHP/pbRecoverHP durante a fase inteira e depois aplicar um lote
# de HP do host. A justificativa escrita la era: "a EXECUCAO do golpe rodava nos
# dois lados com RNG que diverge no meio do turno".
#
# Essa divergencia de RNG era causada pelo restore quebrado do BattleRNG, que o
# item 1.1 corrigiu. Com o RNG realmente sincronizado, a execucao converge e o
# proto 2 deixa de ter motivo.
#
# E o proto 2 tem um custo alto: com pbReduceHP suprimido, o guest simula a fase
# toda com HP cheio e sem dano registrado. No guest, portanto:
#   - damageState.hpLost = 0  -> Counter, Mirror Coat, Metal Burst, Bide,
#                                Rage Fist, Assurance, Avalanche calculam errado
#   - tookDamage = false      -> Focus Punch nunca e interrompido, Shell Trap e
#                                Beak Blast nunca disparam
#   - HP nunca cruza 1/2, 1/4 -> nenhuma berry ativa, Emergency Exit / Wimp Out /
#                                Berserk / Focus Sash nunca disparam
#   - ninguem desmaia na fase -> Destiny Bond, Aftermath, Supreme Overlord,
#                                Last Respects divergem
#   - Substitute nunca quebra, Illusion nunca cai
# O lote conserta so o HP; todo o resto fica permanentemente errado.
#
# PARA REVERTER: troque para true na linha abaixo. O gate duplo do 000d volta a
# valer (precisa tambem de proto >= 2 nos dois lados).
#-------------------------------------------------------------------------------
# REVERTIDO EM 2026-07-30, DEPOIS DE TESTE EM JOGO.
#
# Desligar o proto 2 causou uma REGRESSAO GRAVE: numa dupla coop, um inimigo
# morria so na tela de quem deu o golpe. Causa: o UNICO ponto do codigo que
# chama pbFaint a partir do HP autoritativo do host e o apply_coop_turn_batch
# (000d, "coop turn"), que so roda com o proto 2 ligado. O aplicador de
# snapshot escreve hp=0 mas NUNCA desmaia o battler — entao no guest o inimigo
# ficava de pe com 0 de HP.
#
# A analise de que o proto 2 seria desnecessario depois de consertar o RNG
# estava errada na pratica: ele tambem carrega o pbFaint autoritativo, que
# nenhum outro caminho faz. Fica LIGADO.
#
# (O buraco do pbFaint no snapshot foi tapado a parte, no 000d — vale para os
#  dois protos.)
# DESLIGADO em 2026-07-30 apos comparar com o build que funcionava bem
# ("Scripts testar coop invite e item no overworld.rxdata"). Esse build NAO tem
# proto 2 nenhum — nem coop_turn_batch, nem seed por turno, nem sync_field_state.
# Era proto 1 puro: espelho de HP por evento + snapshot. O proto 2 foi acrescentado
# depois e estava ATIVO em silencio (o gate testava `== false` e a variavel nunca
# era atribuida, valendo nil). Com ele o guest suprime pbReduceHP a fase inteira:
# damageState zerado, tookDamage falso, nenhuma berry, ninguem desmaia na fase.
# E a descricao exata do "desync geral".
$anil_coop_eor_authoritative = false

# ------------------------------------------------------------------------------
# INTERRUPTOR GERAL DO COOP V3
#
# false  = desliga TUDO o que foi acrescentado em 2026-07-30 (RNG contador-base,
#          ordem de turno autoritativa, campos novos do snapshot, weather no
#          snapshot, hash de turno). O coop volta a se comportar exatamente como
#          antes dessas mudancas, com o proto 2 ligado.
# true   = liga (so tem efeito quando os DOIS clientes sao proto >= 3).
#
# Existe para nao ser preciso recompilar/reverter arquivo por arquivo se algo
# der errado em producao: e uma linha.
# ------------------------------------------------------------------------------
# DESLIGADO 2026-07-30 a pedido: volta ao coop mais proximo do build antigo.
# Isto tira do ar TUDO o que foi acrescentado hoje (RNG contador, ordem de turno,
# campos novos do snapshot, weather no snapshot, hash de turno).
$anil_coop_v3 = false

# Reconciliacao por hash: quando true, um hash divergente BLOQUEIA o guest ate
# aplicar um snapshot do host. Comeca DESLIGADO (so registra no log) porque
# introduz uma espera nova no fim de cada turno, e espera nova em coop e
# exatamente o que produz trava e piscar de janela. Ligar so depois de ler o log
# e confirmar que o mismatch e raro.
$anil_coop_v3_reconciliar = false

module AnilLanRework
  module BattleSync
    class << self

      # ======================================================================
      # 1.3 — ORDEM DO TURNO AUTORITATIVA
      # ======================================================================
      # pbCalculatePriority (000d) monta a ordem a partir de b.pbSpeed, lido do
      # estado LOCAL. pbSpeed depende de stages, item, ability, weather/terrain e
      # dos stats reais do Pokemon do parceiro. Qualquer um desses divergindo
      # inverte a ordem do turno nos dois clientes — e a partir dai a sequencia de
      # pbReduceHP e outra, as filas de pacote desalinham e nada mais casa.
      #
      # O desempate aleatorio JA era sincronizado (usa ctx.rng). O que faltava era
      # a ordem final. Aqui o host manda a ordem resolvida e o guest REORDENA a
      # sua propria lista @priority — mantendo as entradas locais (que carregam os
      # objetos battler e as prioridades ja calculadas), mudando so a ordem.
      #
      # Custo: e um RENDEZVOUS, nao um round-trip serializado. Os dois lados
      # chegam aqui logo depois da fase de comando, entao o pacote do host
      # normalmente ja chegou e a espera retorna na hora.

      # A ordem do turno e uma CORRECAO, nao uma barreira: se o pacote nao chegar,
      # cair na ordem local e exatamente o comportamento de hoje. Por isso o
      # timeout aqui e curto — nao vale travar o jogador por isto.
      COOP_PRIORITY_TIMEOUT = 2.5 unless const_defined?(:COOP_PRIORITY_TIMEOUT)
      COOP_HASH_TIMEOUT     = 8.0 unless const_defined?(:COOP_HASH_TIMEOUT)

      def coop_v3_ativo?(battle = nil)
        ctx = @active_context
        return false unless ctx && ctx.mode == :coop
        return false unless coop_determinismo_v3?(ctx)
        return false if coop_remote_sync_disabled?(ctx)
        return false if remote_coop_eliminated_marked?(ctx)
        return false if local_coop_eliminated_marked?(ctx)
        return false if battle && ctx.battle && !ctx.battle.equal?(battle)
        true
      rescue
        false
      end

      # FIFO por (battle_id, turn), nao chave unica: pbCalculatePriority(true) roda
      # DUAS vezes num turno em que alguem troca de Pokemon — uma na fase de
      # ataque (Battle_AttackPhase) e outra na sub-fase de troca
      # (pbAttackPhaseSwitch, Battle_ActionSwitching). Com chave unica o segundo
      # pacote sobrescrevia o primeiro e o guest ficava esperando um pacote que
      # nunca vinha. Com fila, na pior das hipoteses ele consome fora de ordem e
      # cai no fallback local — nunca trava.
      def queue_coop_priority_order(packet)
        return unless packet.is_a?(Hash)
        @coop_priority_inbox ||= {}
        chave = "#{packet['battle_id']}|#{packet['turn'].to_i}"
        (@coop_priority_inbox[chave] ||= []) << packet
      end

      def take_coop_priority_order(battle_id, turn)
        @coop_priority_inbox ||= {}
        chave = "#{battle_id}|#{turn.to_i}"
        fila = @coop_priority_inbox[chave]
        return nil if fila.nil? || fila.empty?
        pacote = fila.shift
        @coop_priority_inbox.delete(chave) if fila.empty?
        pacote
      end

      def clear_coop_v3_state!
        @coop_priority_inbox = {}
        @coop_hash_inbox = {}
      end

      def serialize_coop_priority_order(battle)
        pri = battle.instance_variable_get(:@priority)
        return [] unless pri.is_a?(Array)
        pri.map { |entry| entry[0] ? entry[0].index.to_i : nil }.compact
      rescue
        []
      end

      def apply_coop_priority_order(battle, ordem, sender_client_index)
        pri = battle.instance_variable_get(:@priority)
        return false unless pri.is_a?(Array) && !pri.empty?
        return false unless ordem.is_a?(Array) && !ordem.empty?

        restante = pri.dup
        nova = []
        ordem.each do |idx_remoto|
          idx_local = translate_remote_battler_index(idx_remoto.to_i, sender_client_index, battle)
          pos = restante.index { |entry| entry[0] && entry[0].index.to_i == idx_local.to_i }
          nova << restante.delete_at(pos) if pos
        end
        # Quem o host nao listou (battler que so existe deste lado) vai para o fim,
        # preservando a ordem relativa local.
        nova.concat(restante)
        return false if nova.length != pri.length

        antes = pri.map { |e| e[0] ? e[0].index.to_i : -1 }
        pri.replace(nova)
        depois = pri.map { |e| e[0] ? e[0].index.to_i : -1 }
        if antes != depois
          AnilLanRework.log("coop v3 ordem do turno CORRIGIDA #{antes.inspect} -> #{depois.inspect}")
        end
        true
      rescue => e
        AnilLanRework.log("apply_coop_priority_order error #{e.class}: #{e.message}")
        false
      end

      def sync_coop_priority_order(battle)
        ctx = @active_context
        return unless ctx && battle
        turno = (battle.turnCount.to_i rescue 0)

        if ctx.client_index.to_i == 0
          ordem = serialize_coop_priority_order(battle)
          return if ordem.empty?
          AnilLanRework.connection.send_packet("coop_priority_order",
            "to_id"               => ctx.partner_id,
            "battle_id"           => ctx.battle_id,
            "turn"                => turno,
            "sender_client_index" => 0,
            "order"               => ordem
          )
          AnilLanRework.log("coop v3 ordem enviada turn=#{turno} order=#{ordem.inspect}")
          return
        end

        # SEM ESPERA BLOQUEANTE.
        # A primeira versao esperava ate 2,5s pelo pacote do host. Espera nova no
        # meio do turno e justamente o que faz a janela de "aguardando parceiro"
        # aparecer e sumir (o loop chama pump_network e aplica locks remotos
        # bufferizados no meio do turno). Como a ordem do host e uma CORRECAO e
        # nao uma barreira, so aplicamos se o pacote JA chegou; se nao chegou,
        # segue com a ordem local, que e o comportamento de sempre.
        pump_network
        pacote = take_coop_priority_order(ctx.battle_id, turno)
        unless pacote
          AnilLanRework.log("coop v3 ordem ainda nao chegou turn=#{turno} — usando ordem local")
          return
        end
        apply_coop_priority_order(battle, pacote["order"], pacote["sender_client_index"].to_i)
      rescue => e
        AnilLanRework.log("sync_coop_priority_order error #{e.class}: #{e.message}")
      end

      # ======================================================================
      # 3.3 — HASH DE TURNO CANONICO + RECONCILIACAO
      # ======================================================================
      # O PVP ja tinha isto (pvp_turn_state_hash). O coop nao tinha nada, entao
      # divergencia silenciosa acumulava turno a turno sem nenhum sinal — foi
      # exatamente o que a simulacao mostrou nos casos "mascarados" (Intimidate
      # com ordem invertida, contador de Toxic divergente): o HP fica certo e o
      # resto fica errado para sempre.
      #
      # O hash NAO pode usar o indice cru do battler: em coop o slot 0 de um
      # cliente e o slot 2 do outro. Tudo aqui e canonicalizado para a
      # perspectiva do host (client_index 0). Sides NAO sao invertidos em coop
      # (os dois jogadores estao no side 0) — so o PVP inverte.
      #
      # Efeitos que guardam INDICE DE BATTLER (Attract, LeechSeed, Trapping...)
      # ficam fora do hash: canonicaliza-los daria muito ruido por pouco ganho de
      # deteccao, e eles sao reparados pelo snapshot de qualquer forma.

      def coop_canonical_index(battle, idx)
        ctx = @active_context
        return idx.to_i unless ctx
        return idx.to_i if ctx.client_index.to_i == 0
        translate_coop_battler_index(idx.to_i, ctx.client_index.to_i, 0, battle).to_i
      rescue
        idx.to_i
      end

      def coop_hashable_effects(battler)
        fora = EFFECT_BATTLER_INDEX_IDS.map(&:to_i)
        BATTLER_EFFECT_IDS.reject { |id| fora.include?(id.to_i) }.map do |id|
          v = battler.effects[id]
          [id.to_i, (v.is_a?(TrueClass) || v.is_a?(FalseClass) || v.is_a?(Integer) || v.is_a?(String) || v.is_a?(Symbol)) ? v.to_s : v.class.name.to_s]
        end
      rescue
        []
      end

      def serialize_coop_turn_state(battle)
        battlers = battle.battlers.compact.map do |b|
          stages = (b.stages rescue {})
          {
            "i"      => coop_canonical_index(battle, b.index),
            "hp"     => (b.hp.to_i rescue 0),
            "thp"    => (b.totalhp.to_i rescue 0),
            "st"     => ((b.status || :NONE).to_s rescue "NONE"),
            "stc"    => (b.statusCount.to_i rescue 0),
            "sp"     => (b.species.to_s rescue ""),
            "fm"     => (b.form.to_i rescue 0),
            "ab"     => (b.ability_id.to_s rescue ""),
            "it"     => (b.item_id.to_s rescue ""),
            "ty"     => (Array(b.types).map(&:to_s).sort rescue []),
            "stg"    => (stages.is_a?(Hash) ? stages.keys.map(&:to_s).sort.map { |k| [k, (stages[k.to_sym] || stages[k]).to_i] } : []),
            "pp"     => (Array(b.moves).map { |m| m ? [m.id.to_s, m.pp.to_i] : nil }.compact rescue []),
            "fnt"    => ((b.fainted? rescue false) ? 1 : 0),
            "tc"     => (b.turnCount.to_i rescue 0),
            "dmg"    => [
                          ((b.tookMoveDamageThisRound rescue false) ? 1 : 0),
                          ((b.tookDamageThisRound rescue false) ? 1 : 0),
                          ((b.tookPhysicalHit rescue false) ? 1 : 0),
                          (b.lastHPLost.to_i rescue 0)
                        ],
            "lm"     => (b.lastMoveUsed.to_s rescue ""),
            "lr"     => (b.lastRoundMoved.to_i rescue -1),
            "ef"     => coop_hashable_effects(b)
          }
        end.sort_by { |h| h["i"] }

        {
          "turn"      => (battle.turnCount.to_i rescue 0),
          "decision"  => (battle.decision.to_i rescue 0),
          "battlers"  => battlers,
          "sides"     => Array(battle.sides).each_with_index.map { |s, i| [i, SIDE_EFFECT_IDS.map { |id| [id.to_i, s.effects[id].to_s] }] },
          "field"     => FIELD_EFFECT_IDS.map { |id| [id.to_i, battle.field.effects[id].to_s] },
          "weather"   => (battle.field.weather.to_s rescue "None"),
          "wdur"      => (battle.field.weatherDuration.to_i rescue 0),
          "terrain"   => (battle.field.terrain.to_s rescue "None"),
          "tdur"      => (battle.field.terrainDuration.to_i rescue 0)
        }
      rescue => e
        AnilLanRework.log("serialize_coop_turn_state error #{e.class}: #{e.message}")
        { "erro" => e.class.name.to_s }
      end

      def coop_turn_state_hash(battle)
        fnv1a32(canonical_hash_value(serialize_coop_turn_state(battle)))
      rescue
        0
      end

      def queue_coop_turn_hash(packet)
        return unless packet.is_a?(Hash)
        @coop_hash_inbox ||= {}
        @coop_hash_inbox["#{packet['battle_id']}|#{packet['turn'].to_i}"] = packet
      end

      def take_coop_turn_hash(battle_id, turn)
        @coop_hash_inbox ||= {}
        @coop_hash_inbox.delete("#{battle_id}|#{turn.to_i}")
      end

      # Espera generica: bombeia rede/tela, respeita o manual lock (que congela o
      # deadline, igual ao resto do 000d) e desiste no timeout.
      def coop_v3_aguardar(timeout)
        inicio = Time.now.to_f
        loop do
          valor = yield
          return valor if valor
          return nil unless AnilLanRework.connected?
          inicio = Time.now.to_f if (remote_manual_lock? rescue false)
          return nil if Time.now.to_f - inicio >= timeout
          pump_network
          Graphics.update rescue nil
          Input.update rescue nil
        end
      end

      def verify_coop_turn_hash!(battle)
        ctx = @active_context
        return true unless ctx && battle
        turno = (battle.turnCount.to_i rescue 0)
        meu = coop_turn_state_hash(battle)

        AnilLanRework.connection.send_packet("coop_turn_hash",
          "to_id"     => ctx.partner_id,
          "battle_id" => ctx.battle_id,
          "turn"      => turno,
          "hash"      => meu
        )

        # SEM ESPERA BLOQUEANTE. O hash e DIAGNOSTICO: compara com o pacote do
        # turno anterior, que ja chegou, e nunca segura o turno. Uma espera aqui
        # somava mais um ponto de trava/piscar no fim de cada turno, e o valor do
        # hash esta em detectar, nao em bloquear.
        pump_network
        pacote = take_coop_turn_hash(ctx.battle_id, turno) ||
                 take_coop_turn_hash(ctx.battle_id, turno - 1)
        return true unless pacote

        dele = pacote["hash"].to_i & 0xFFFFFFFF
        return true if dele == (meu & 0xFFFFFFFF)

        AnilLanRework.log("coop v3 HASH MISMATCH turn=#{turno} local=#{meu} remoto=#{dele}")
        if $anil_coop_v3_reconciliar == true
          recover_coop_state_after_hash_mismatch(battle, turno)
        end
        false
      rescue => e
        AnilLanRework.log("verify_coop_turn_hash! error #{e.class}: #{e.message}")
        true
      end

      # Host: manda o snapshot completo. Guest: espera e aplica.
      # (o host ja manda um snapshot no fim do EOR; este e explicito e garante que
      #  o guest bloqueia ate aplicar, em vez de seguir com estado divergente)
      def recover_coop_state_after_hash_mismatch(battle, turno = nil)
        ctx = @active_context
        return unless ctx && battle

        if ctx.client_index.to_i == 0
          send_battle_status_snapshot(battle)
          AnilLanRework.log("coop v3 reconciliacao: host enviou snapshot turn=#{turno}")
          return
        end

        pronto = coop_v3_aguardar(COOP_HASH_TIMEOUT) do
          (ctx.pending_status_events && !ctx.pending_status_events.empty?) ? true : nil
        end
        if pronto
          flush_remote_status_events
          AnilLanRework.log("coop v3 reconciliacao: guest aplicou snapshot turn=#{turno}")
        else
          AnilLanRework.log("coop v3 reconciliacao: guest NAO recebeu snapshot turn=#{turno}")
        end
      rescue => e
        AnilLanRework.log("recover_coop_state_after_hash_mismatch error #{e.class}: #{e.message}")
      end
    end
  end
end

#-------------------------------------------------------------------------------
# Wrappers
#-------------------------------------------------------------------------------
if defined?(Battle)
  class Battle
    # 1.3 — depois de calcular a prioridade, alinhar a ordem com o host.
    unless method_defined?(:anil_v3_original_pbCalculatePriority)
      alias anil_v3_original_pbCalculatePriority pbCalculatePriority
    end
    def pbCalculatePriority(fullCalc = false, indexArray = nil)
      resultado = anil_v3_original_pbCalculatePriority(fullCalc, indexArray)
      return resultado unless fullCalc
      bs = AnilLanRework::BattleSync
      return resultado unless (bs.coop_v3_ativo?(self) rescue false)
      bs.sync_coop_priority_order(self)
      resultado
    end

    # 3.3 — hash no fim do turno (EOR e a fronteira natural: o estado ja assentou).
    unless method_defined?(:anil_v3_original_pbEndOfRoundPhase)
      alias anil_v3_original_pbEndOfRoundPhase pbEndOfRoundPhase
    end
    def pbEndOfRoundPhase(*args)
      resultado = anil_v3_original_pbEndOfRoundPhase(*args)
      bs = AnilLanRework::BattleSync
      begin
        if (bs.coop_v3_ativo?(self) rescue false) && @decision == 0
          bs.verify_coop_turn_hash!(self)
        end
      rescue => e
        AnilLanRework.log("coop v3 hash no EOR error #{e.class}: #{e.message}")
      end
      resultado
    end
  end
end

AnilLanRework.log("124_Coop_Determinismo_V3 carregado (proto #{AnilLanRework::BattleSync::COOP_BATTLE_PROTO}, eor_autoritativo=#{$anil_coop_eor_authoritative.inspect})")
