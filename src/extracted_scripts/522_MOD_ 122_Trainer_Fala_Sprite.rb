#===============================================================================
# MOD: 122_Trainer_Fala_Sprite.rb
#-------------------------------------------------------------------------------
# Mostra o sprite de batalha do treinador (da cintura para cima) no canto
# direito, por cima da caixa de mensagem, sempre que ELE fala — ao ser abordado
# pelo jogador, ao avistar na rota, na revanche, na entrega do drop.
#
# COMO SE SABE QUE QUEM FALA E UM TREINADOR
# O interpretador de mapa guarda o evento em execucao (`@event_id`, ver
# 0038_Interpreter). Com o evento na mao, procura-se nos comandos de script dele
# uma chamada de batalha de treinador e tira-se dali o TIPO. E o mesmo sinal que
# o sistema de presentes ja usa para EXCLUIR treinadores (006_Multiplayer_Rematch
# ~1186) — aqui usa-se ao contrario, para os incluir.
#
# Nao ha lista de eventos nem configuracao: quem tem batalha de treinador ganha
# retrato, quem nao tem continua como estava. Se o tipo nao resolver para um
# ficheiro em Graphics/Trainers/, nao aparece nada — nunca se interrompe a fala
# por causa do retrato.
#===============================================================================

module AnilTrainerFalaSprite
  # Fracao da altura do sprite que fica visivel. 0.55 apanha a cabeca e o tronco
  # ate um pouco abaixo da cintura na maioria dos sprites de treinador.
  FRACAO_VISIVEL = 0.55
  MARGEM_LATERAL = 6
  # Altura tipica da caixa de mensagem; o retrato assenta logo acima dela.
  ALTURA_CAIXA   = 100
  ZOOM           = 1.0

  class << self
    attr_accessor :evento_atual

    def cache
      @cache ||= {}
    end

    # O QUE MARCA UM TREINADOR NESTE JOGO
    #
    # Confirmado lendo os 200+ mapas: o comando usado e SEMPRE
    #
    #     pbTrainerIntro(:TIPO)
    #
    # 455 ocorrencias, contra ZERO de `TrainerBattle.start` ou `pbTrainerBattle`
    # — os padroes que esta lista tinha primeiro, e por isso o retrato nunca
    # aparecia. Os outros ficam no fim so como rede de seguranca, caso algum
    # evento novo use a forma do Essentials base.
    PADROES = [
      /pbTrainerIntro\s*\(\s*:([A-Za-z0-9_]+)/,
      /pbTrainerIntro\s*\(\s*["']([A-Za-z0-9_]+)["']/,
      /TrainerBattle\s*\.\s*start\s*\(\s*:([A-Za-z0-9_]+)/,
      /pbTrainerBattle\s*\(\s*:([A-Za-z0-9_]+)/,
      /TrainerBattle\s*\.\s*start\s*\(\s*["']([A-Za-z0-9_]+)["']/,
      /pbTrainerBattle\s*\(\s*["']([A-Za-z0-9_]+)["']/
    ]

    # Devolve o simbolo do tipo de treinador do evento, ou nil.
    def tipo_do_evento(ev)
      return nil unless ev
      chave = [($game_map.map_id rescue 0), (ev.id rescue 0)]
      return cache[chave] if cache.key?(chave)

      tipo = nil
      begin
        paginas = (ev.instance_variable_get(:@pages) rescue nil) ||
                  (ev.pages rescue nil) || []
        paginas.each do |pg|
          lista = (pg.list rescue nil) || []
          lista.each do |cmd|
            codigo = (cmd.code rescue nil)
            next unless codigo == 355 || codigo == 655
            texto = ((cmd.parameters rescue [])[0]).to_s
            PADROES.each do |re|
              m = texto.match(re)
              next unless m
              tipo = m[1].to_s.upcase.to_sym
              break
            end
            break if tipo
          end
          break if tipo
        end
      rescue
        tipo = nil
      end

      # So vale se existir mesmo como tipo de treinador COM ficheiro de sprite.
      tipo = nil if tipo && !sprite_existe?(tipo)
      cache[chave] = tipo
      tipo
    end

    def sprite_existe?(tipo)
      return false unless defined?(GameData) && defined?(GameData::TrainerType)
      return false unless (GameData::TrainerType.exists?(tipo) rescue false)
      f = (GameData::TrainerType.front_sprite_filename(tipo) rescue nil)
      !f.nil? && !f.to_s.empty?
    rescue
      false
    end

    # Evento que o interpretador de mapa esta a correr agora.
    def evento_em_execucao
      interp = (pbMapInterpreter rescue nil)
      return nil unless interp
      eid = (interp.instance_variable_get(:@event_id) rescue 0).to_i
      return nil if eid <= 0
      ($game_map.events[eid] rescue nil)
    rescue
      nil
    end

    def visivel?
      @sprite && !@sprite.disposed?
    end

    def mostrar!(tipo)
      return if tipo.nil?
      # Ja esta no ecra este mesmo treinador: nao repor (evitava o retrato a
      # piscar entre falas seguidas do mesmo NPC).
      return if visivel? && @tipo_no_ecra == tipo

      esconder!
      arquivo = (GameData::TrainerType.front_sprite_filename(tipo) rescue nil)
      return if arquivo.nil? || arquivo.to_s.empty?
      bmp = (Bitmap.new(arquivo) rescue nil)
      return unless bmp

      @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
      # Abaixo da caixa de mensagem (que anda na casa dos 99999x) de proposito:
      # o retrato acompanha a fala, nunca tapa o texto.
      @viewport.z = 99000
      @sprite = Sprite.new(@viewport)
      @sprite.bitmap = bmp

      altura_visivel = (bmp.height * FRACAO_VISIVEL).to_i
      altura_visivel = bmp.height if altura_visivel <= 0 || altura_visivel > bmp.height
      # Corta a metade de baixo: fica da cintura para cima.
      @sprite.src_rect = Rect.new(0, 0, bmp.width, altura_visivel)
      @sprite.zoom_x = ZOOM
      @sprite.zoom_y = ZOOM
      @sprite.x = Graphics.width - (bmp.width * ZOOM).to_i - MARGEM_LATERAL
      @sprite.y = Graphics.height - ALTURA_CAIXA - (altura_visivel * ZOOM).to_i
      @sprite.y = 0 if @sprite.y < 0
      @sprite.opacity = 0
      @tipo_no_ecra = tipo
      @fade = :entrando
    rescue
      esconder!
    end

    def esconder!
      @sprite.bitmap.dispose rescue nil if @sprite && @sprite.bitmap
      @sprite.dispose rescue nil if @sprite
      @viewport.dispose rescue nil if @viewport
      @sprite = nil
      @viewport = nil
      @tipo_no_ecra = nil
      @fade = nil
    rescue
      @sprite = nil
      @viewport = nil
    end

    # Fade curto, chamado do update do mapa.
    def atualizar!
      return unless visivel?
      if @fade == :entrando
        @sprite.opacity += 32
        @fade = nil if @sprite.opacity >= 255
      end
    rescue
    end

    # O retrato vive enquanto o evento que o pediu estiver a correr. Sem isto
    # ficaria no ecra depois de a conversa acabar.
    def limpar_se_acabou!
      return unless visivel?
      interp = (pbMapInterpreter rescue nil)
      if interp.nil? || !(interp.running? rescue false)
        esconder!
        return
      end
      eid = (interp.instance_variable_get(:@event_id) rescue 0).to_i
      esconder! if eid <= 0 || eid != @evento_id_no_ecra.to_i
    rescue
      esconder!
    end

    def registar_evento!(eid)
      @evento_id_no_ecra = eid
    end
  end
end

#===============================================================================
# Gancho na caixa de mensagem
#===============================================================================
# ⚠️ O GANCHO TEM DE SER NO TOP-LEVEL, NAO EM `module Kernel`.
#
# O `pbMessage` deste jogo e definido com um `def` no topo do 0425_Turbo, o que
# o poe em **Object**. Na cadeia de ancestrais, Object vem ANTES de Kernel:
#
#   Alvo -> Object -> Kernel -> BasicObject
#
# Portanto um `def pbMessage` dentro de `module Kernel` fica tapado pelo de
# Object e NUNCA corre — foi por isso que o retrato nao aparecia, apesar de o
# `command_101` (Show Text dos eventos) chamar mesmo `pbMessage`. Um `def` aqui
# no topo redefine em Object e ganha.
#
# (O mesmo defeito existe no gancho do 101_Force_Complete_Mode, que tambem
# envolve o pbMessage dentro de `module Kernel` — nunca chega a correr.)
unless defined?(anil_trfala_orig_pbMessage)
  alias anil_trfala_orig_pbMessage pbMessage
end

def pbMessage(message, *args, &block)
  begin
    ev = AnilTrainerFalaSprite.evento_em_execucao
    if ev
      tipo = AnilTrainerFalaSprite.tipo_do_evento(ev)
      if tipo
        AnilTrainerFalaSprite.registar_evento!((ev.id rescue 0))
        AnilTrainerFalaSprite.mostrar!(tipo)
      end
    end
  rescue
    # Um retrato nunca pode impedir a fala de acontecer.
  end
  anil_trfala_orig_pbMessage(message, *args, &block)
end

#===============================================================================
# Update do mapa: fade e limpeza quando a conversa termina
#===============================================================================
class Scene_Map
  alias anil_trfala_orig_update update unless method_defined?(:anil_trfala_orig_update)

  def update(*args)
    anil_trfala_orig_update(*args)
    begin
      AnilTrainerFalaSprite.atualizar!
      AnilTrainerFalaSprite.limpar_se_acabou!
    rescue
    end
  end
end
