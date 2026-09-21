#===============================================================================
# MOD: 112_Text_No_Shadow.rb
#-------------------------------------------------------------------------------
# Remove a sombra dos textos, mantendo o CONTORNO (outline) onde ele existe.
#
# A sombra do Essentials nao e um efeito da fonte: e o mesmo texto desenhado
# tres vezes deslocado em +2 px (x, y e xy) com a cor de sombra, e so depois o
# texto de verdade por cima. Sao tres caminhos diferentes:
#
#   pbDrawShadowText ................. textos soltos (listas, menus, HUD)
#   renderLineBrokenChunksWithShadow . texto quebrado em linhas (descricoes)
#   drawSingleFormattedChar .......... caixa de dialogo (texto formatado)
#
# Por que nao bastou zerar as cores de sombra: elas estao espalhadas por dezenas
# de constantes (MessageConfig + uma por tela, tipo ITEMTEXTSHADOWCOLOR), e o
# renderLineBrokenChunksWithShadow nem checa alpha — desenharia do mesmo jeito.
#
# CONTORNO PRESERVADO: no texto formatado o contorno usa o MESMO slot de cor da
# sombra (ch[9]), dentro do mesmo if. Anular tudo apagaria tambem os contornos,
# que existem para dar legibilidade sobre sprites (HP em batalha, por exemplo).
# Por isso a sombra so e removida quando nao ha flag de contorno em ch[16].
#
# PARA REVERTER: apagar este arquivo e rodar compilar.rb. Nenhum outro arquivo
# foi tocado. Para so desligar, troque a constante abaixo para true.
#===============================================================================

ANIL_TEXT_SHADOW_ENABLED = false unless defined?(ANIL_TEXT_SHADOW_ENABLED)

if !ANIL_TEXT_SHADOW_ENABLED

  # --- 1. Textos soltos -------------------------------------------------------
  # A original ja tem o guarda "if shadowColor && shadowColor.alpha > 0", entao
  # passar nil basta: ela desenha so o texto base, na posicao certa.
  alias anil_noshadow_orig_pbDrawShadowText pbDrawShadowText
  def pbDrawShadowText(bitmap, x, y, width, height, string, baseColor, shadowColor = nil, align = 0)
    anil_noshadow_orig_pbDrawShadowText(bitmap, x, y, width, height, string, baseColor, nil, align)
  end

  # --- 2. Texto quebrado em linhas -------------------------------------------
  # Aqui nao da para passar nil: a original faz "bitmap.font.color = shadowColor"
  # sem checar nada e quebraria. E a reimplementacao da original, sem os tres
  # draw_text deslocados.
  def renderLineBrokenChunksWithShadow(bitmap, xDst, yDst, normtext, maxheight, baseColor, shadowColor)
    normtext.each do |text|
      width  = text[3]
      textx  = text[1] + xDst
      texty  = text[2] + yDst
      next if maxheight != 0 && text[2] >= maxheight
      height = text[4]
      text   = text[0]
      bitmap.font.color = baseColor
      bitmap.draw_text(textx, texty, width + 2, height, text)
    end
  end

  # --- 3. Caixa de dialogo ----------------------------------------------------
  # Com ch[9] nulo a original pula o bloco de sombra, mantem offset = 0 (ou seja,
  # o texto fica na posicao correta, sem o deslocamento que o contorno aplica) e
  # ainda desenha sublinhado/tachado, que usam a cor base ch[8].
  # ch[16] bits 1 e 2 sinalizam contorno: nesses casos nao se mexe.
  alias anil_noshadow_orig_drawSingleFormattedChar drawSingleFormattedChar
  def drawSingleFormattedChar(bitmap, ch)
    if ch.is_a?(Array) && ch[9] && (ch[16].to_i & 3) == 0
      ch = ch.dup
      ch[9] = nil
    end
    anil_noshadow_orig_drawSingleFormattedChar(bitmap, ch)
  end

end
