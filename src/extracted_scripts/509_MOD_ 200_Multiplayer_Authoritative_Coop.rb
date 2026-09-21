#===============================================================================
# MOD: 200_Multiplayer_Authoritative_Coop.rb
#-------------------------------------------------------------------------------
# MÓDULO COOPERATIVO LOCKSTEP DETERMINÍSTICO.
# Sincroniza a Seed de RNG e troca escolhas de turno P2P via Servidor (VPS).
# Suporta: Golpes de Múltiplos Turnos (Rollout, Meteor Beam, Solar Beam, Outrage, etc.).
# Redireciona pbRandom para @battleRNG garantindo paridade em STATUS (Poison, Burn, etc.).
#===============================================================================

AUTHORITATIVE_COOP_ENABLED = true

module AuthoritativeCoop
  @active_battle_id = nil
  @client_index = 0
  @partner_id = nil
  @shared_seed = nil
  @partner_choice = nil
  @waiting_partner_choice = false

  class << self
    attr_accessor :active_battle_id, :client_index, :partner_id, :shared_seed, :partner_choice, :waiting_partner_choice

    def active?
      AUTHORITATIVE_COOP_ENABLED && !@active_battle_id.nil?
    end

    def start_lockstep_session(battle_id, client_index, partner_id, seed)
      @active_battle_id = battle_id
      @client_index = client_index
      @partner_id = partner_id
      @shared_seed = seed
      @partner_choice = nil
      @waiting_partner_choice = false
      if defined?(AnilLanRework)
        AnilLanRework.log("[LOCKSTEP_COOP] Sessão Lockstep iniciada battle_id=#{battle_id} client_index=#{client_index} seed=#{seed}")
      end
    end

    def end_lockstep_session
      @active_battle_id = nil
      @client_index = 0
      @partner_id = nil
      @shared_seed = nil
      @partner_choice = nil
      @waiting_partner_choice = false
    end

    def send_turn_choice(choice_data)
      return unless active?
      return unless defined?(AnilLanRework) && AnilLanRework.connected? && @partner_id

      packet = {
        "type" => "coop_turn_choice",
        "to_id" => @partner_id.to_s,
        "battle_id" => @active_battle_id,
        "client_index" => @client_index,
        "choice" => choice_data
      }

      AnilLanRework.send_packet(packet)
    end

    def receive_partner_choice(packet)
      return unless active?
      return unless packet["battle_id"].to_s == @active_battle_id.to_s

      @partner_choice = packet["choice"]
      @waiting_partner_choice = false
      if defined?(AnilLanRework)
        AnilLanRework.log("[LOCKSTEP_COOP] Escolha do parceiro recebida: #{@partner_choice.inspect}")
      end
    end
  end
end

# Hook Mestre na classe Battle do Essentials para Lockstep Determinístico
class Battle
  # REDIRECIONAMENTO DE RNG PARA GARANTIR PARIDADE EM STATUS, CRÍTICOS E PRECISÃO
  alias lockstep_coop_pbRandom pbRandom rescue nil
  def pbRandom(x)
    if AUTHORITATIVE_COOP_ENABLED && AuthoritativeCoop.active? && @battleRNG
      return 0 if x.to_i <= 0
      return @battleRNG.rand(x.to_i)
    end
    return lockstep_coop_pbRandom(x) if respond_to?(:lockstep_coop_pbRandom)
    return 0 if x.to_i <= 0
    return rand(x.to_i)
  end

  alias lockstep_coop_initialize initialize rescue nil
  def initialize(scene, p1, p2, player_trainers, foe_trainers)
    lockstep_coop_initialize(scene, p1, p2, player_trainers, foe_trainers) rescue nil
    if AUTHORITATIVE_COOP_ENABLED && defined?(AnilLanRework) && AnilLanRework.connected?
      ctx = (defined?(AnilLanRework::BattleSync) && AnilLanRework::BattleSync.respond_to?(:active_context)) ? AnilLanRework::BattleSync.active_context : nil
      b_id = ctx ? ctx.battle_id : "lockstep_coop_#{Time.now.to_i}"
      c_idx = ctx ? ctx.client_index : (AnilLanRework.respond_to?(:host?) && AnilLanRework.host? ? 0 : 1)
      p_id = ctx ? ctx.partner_id : (AnilLanRework.respond_to?(:nearby_peer_on_same_map) ? AnilLanRework.nearby_peer_on_same_map&.internal_id : nil)
      
      # USAR A SEED COMPARTILHADA DO CONTEXTO DE REDE
      shared_seed = (ctx && ctx.seed) ? ctx.seed.to_i : 123456

      AuthoritativeCoop.start_lockstep_session(b_id, c_idx, p_id, shared_seed)

      # Sincroniza o gerador de números aleatórios determinístico
      @battleRNG = Random.new(shared_seed)
    end
  end

  # Aviso de "batalha lockstep ativa" removido: era um pbDisplayPaused no
  # arranque de CADA batalha coop, que obrigava a carregar num botao antes de
  # jogar. O estado do lockstep ve-se no log ([LOCKSTEP_COOP]).
  #
  # Com o override inteiro fora, o pbStartBattleSendOut volta a ser o do engine
  # — menos um alias na classe Battle, que e onde o PVP tambem vive.

  alias lockstep_coop_pbCommandPhase pbCommandPhase rescue nil
  def pbCommandPhase
    if AuthoritativeCoop.active?
      orig_res = lockstep_coop_pbCommandPhase
      
      local_idx = (AuthoritativeCoop.client_index == 0) ? 0 : 2
      partner_idx = (AuthoritativeCoop.client_index == 0) ? 2 : 0

      # Envia a escolha do jogador local se houver uma feita no menu
      choice = @choices[local_idx] rescue nil
      if choice && choice[0] != :None
        AuthoritativeCoop.send_turn_choice(choice)
      end

      # VERIFICAÇÃO INTELIGENTE: O parceiro realmente precisa escolher neste turno?
      partner_needs_choice = (pbCanShowCommands?(partner_idx) && (@choices[partner_idx][0] == :None)) rescue true

      if partner_needs_choice
        AuthoritativeCoop.waiting_partner_choice = true
        while AuthoritativeCoop.waiting_partner_choice
          Graphics.update
          Input.update
          AnilLanRework.update rescue nil
        end

        if AuthoritativeCoop.partner_choice
          @choices[partner_idx] = AuthoritativeCoop.partner_choice rescue nil
        end
      else
        AuthoritativeCoop.waiting_partner_choice = false
      end

      return orig_res
    end
    lockstep_coop_pbCommandPhase
  end
end

# Interceptação de pacotes no cliente
if defined?(AnilLanRework)
  module AnilLanRework
    class << self
      alias lockstep_coop_handle_packet handle_packet rescue nil
      def handle_packet(packet)
        if AUTHORITATIVE_COOP_ENABLED && packet.is_a?(Hash)
          case packet["type"]
          when "coop_turn_choice", "coopcc_escolha"
            AuthoritativeCoop.receive_partner_choice(packet)
            return
          end
        end
        lockstep_coop_handle_packet(packet) if respond_to?(:lockstep_coop_handle_packet)
      end
    end
  end
end
