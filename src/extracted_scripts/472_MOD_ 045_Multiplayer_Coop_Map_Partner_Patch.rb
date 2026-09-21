#===============================================================================
# MOD: 045_Multiplayer_Coop_Map_Partner_Patch
#-------------------------------------------------------------------------------
# Exibe a posição em tempo real do seu parceiro cooperativo no mapa-múndi
# (Tecla S / Pokégear), mapeando automaticamente qualquer skin personalizada
# escolhida através de "Trocar Personagem" para o seu ícone correto de mapa!
#===============================================================================

if defined?(PokemonRegionMap_Scene)
  class PokemonRegionMap_Scene
    alias partner_map_original_pbStartScene pbStartScene unless method_defined?(:partner_map_original_pbStartScene)
    
    def pbStartScene(*args)
      result = partner_map_original_pbStartScene(*args)
      
      # Exibe ícone do parceiro cooperativo no mapa se estiver conectado e em grupo
      if AnilLanRework.connected? && AnilLanRework.respond_to?(:coop_party_partner_id) && AnilLanRework.coop_party_partner_id
        partner_id = AnilLanRework.coop_party_partner_id.to_s
        partner = AnilLanRework.players[partner_id] rescue nil
        if partner && partner.map_id > 0
          partner_map_metadata = GameData::MapMetadata.try_get(partner.map_id) rescue nil
          partner_pos = partner_map_metadata ? partner_map_metadata.town_map_position : nil
          mapindex = @map ? @map.id : 0 rescue 0
          if partner_pos && partner_pos[0] == mapindex
            partner_x = partner_pos[1]
            partner_y = partner_pos[2]
            
            screen_x = point_x_to_screen_x(partner_x)
            screen_y = point_y_to_screen_y(partner_y)
            
            # Se estiver na mesma coordenada exata do jogador, aplica um pequeno desvio
            if @map_x == partner_x && @map_y == partner_y
              screen_x += 8
              screen_y += 8
            end
            
            # Determina o ícone com base na skin atual do parceiro (incluindo qualquer skin personalizada)
            icon_file = nil
            if partner.char_name
              # Usa a função nativa do multiplayer para converter a skin em trainer_type
              t_type = AnilLanRework.trainer_type_for_character(partner.char_name, nil)
              if t_type
                icon_file = GameData::TrainerType.player_map_icon_filename(t_type) rescue nil
              end
            end
            
            # Fallback seguro caso não consiga determinar a skin personalizada
            if !icon_file || icon_file.empty?
              icon_file = "Graphics/UI/Town Map/player_POKEMONTRAINER_RojoNeutro"
            end
            
            # Cria sprite do parceiro
            @sprites["partner"] = IconSprite.new(0, 0, @viewport)
            @sprites["partner"].setBitmap(icon_file)
            @sprites["partner"].x = screen_x
            @sprites["partner"].y = screen_y
            @sprites["partner"].opacity = 220
            @sprites["partner"].tone = Tone.new(-50, 100, -50, 50) rescue nil # Tom esverdeado para diferenciar
            @sprites["partner"].z = 10
            
            # Garante que o cursor vermelho e o player fiquem por cima do ícone do parceiro
            @sprites["cursor"].z = 50 if @sprites["cursor"]
            @sprites["player"].z = 40 if @sprites["player"]
            
            # Cria tag de nome flutuante acima do ícone, centralizada perfeitamente
            @sprites["partner_name"] = Sprite.new(@viewport)
            @sprites["partner_name"].bitmap = Bitmap.new(160, 32)
            @sprites["partner_name"].bitmap.font.name = "Arial"
            @sprites["partner_name"].bitmap.font.size = 12 # Reduzido proporcionalmente de 15 para 12
            @sprites["partner_name"].bitmap.font.bold = true
            @sprites["partner_name"].z = 15 # Acima do ícone do parceiro, mas abaixo do cursor vermelho
            
            # Desenha a sombra (preta) com um pequeno deslocamento de 1px
            @sprites["partner_name"].bitmap.font.color = Color.new(0, 0, 0)
            @sprites["partner_name"].bitmap.draw_text(1, 1, 160, 32, partner.name.to_s, 1)
            
            # Desenha o texto principal (verde vibrante)
            @sprites["partner_name"].bitmap.font.color = Color.new(50, 255, 50)
            @sprites["partner_name"].bitmap.draw_text(0, 0, 160, 32, partner.name.to_s, 1)
            
            # Centraliza perfeitamente em cima do ponto de posição (considerando 16px como raio do centro do ícone)
            @sprites["partner_name"].x = screen_x + 16 - 80
            @sprites["partner_name"].y = screen_y - 22
          end
        end
      end
      
      result
    end
  end
end
