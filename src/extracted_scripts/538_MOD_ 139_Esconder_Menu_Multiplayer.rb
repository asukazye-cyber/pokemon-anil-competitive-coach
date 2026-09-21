# encoding: UTF-8
#===============================================================================
# MOD: 139_Esconder_Menu_Multiplayer
#-------------------------------------------------------------------------------
# Tira a opcao "Multiplayer" do menu inicial, SEM remover o codigo dela.
#
# POR QUE ESCONDER
#
# Quem entrava por ali caia offline e concluia que o jogo nao salvava. Nao
# salvava mesmo: sem ligacao, nao ha upload. O caminho correto e Partida Nueva
# (conta nova) ou o slot de save (conta ja existente), que ligam sozinhos.
#
# POR QUE UM MOD E NAO UMA EDICAO NO MENU
#
# O menu nao e do script base. O plugin "013 Multi Save" REDEFINE o
# pbStartLoadScreen inteiro e monta a propria lista de comandos (linha 865 do
# plugin). Mexer no 0311_UI_Load.rb seria codigo morto — o plugin carrega
# depois e ganha. E o PluginScripts.rxdata nao e gerado pelo compilar.rb, entao
# edita-lo obrigaria a distribuir um segundo binario.
#
# O CUIDADO QUE ISTO EXIGE (a parte que nao e obvia)
#
# O plugin guarda os indices num punhado de variaveis calculadas sobre o array:
#
#     commands[cmd_multiplayer = commands.length] = _INTL('Multiplayer')
#     commands[cmd_recover     = commands.length] = _INTL('Recuperar Partida')
#     ...
#     command = @scene.pbChoose(commands, cmd_continue)
#     case command
#     when cmd_multiplayer  then ...
#     when cmd_recover      then ...
#
# Ou seja, o despacho e por POSICAO. Se a opcao sumisse da lista exibida e mais
# nada, tudo abaixo dela subiria uma casa e "Recuperar Partida" passaria a cair
# no ramo do Multiplayer — um estrago bem pior do que o que se queria corrigir.
#
# Por isso aqui se faz as duas metades:
#   1. esconde o item da lista que a cena mostra;
#   2. traduz o indice escolhido de volta para o do array ORIGINAL antes de
#      devolver, para que o `case` do plugin continue a bater certo.
#
# Assim o plugin nunca percebe a diferenca, e o ramo `when cmd_multiplayer`
# continua la, intacto, so inalcancavel. Para reativar: apagar este ficheiro e
# recompilar.
#===============================================================================

module AnilEsconderMenuMultiplayer
  module_function

  # O rotulo passa pelo _INTL, entao compara-se com as duas formas: a literal do
  # plugin e a traduzida em uso. Sem a literal, uma traducao ativa escaparia;
  # sem a traduzida, escaparia o caso contrario.
  def rotulos_ocultos
    lista = ["Multiplayer"]
    begin
      t = _INTL("Multiplayer").to_s
      lista << t unless t.empty? || lista.include?(t)
    rescue
    end
    lista
  end

  def oculto?(cmd)
    rotulos_ocultos.include?(cmd.to_s.strip)
  end

  # Devolve [lista_visivel, mapa], onde mapa[i_visivel] = i_original.
  def filtrar(commands)
    visiveis = []
    mapa     = []
    commands.each_with_index do |c, i|
      next if oculto?(c)
      visiveis << c
      mapa     << i
    end
    [visiveis, mapa]
  end

  # Instala (ou REinstala) o embrulho do pbChoose.
  #
  # ⚠️ Tem de poder correr varias vezes. O MOD 061 (menu touch) define o pbChoose
  # dele DE DENTRO do pbStartScene, em tempo de execucao:
  #
  #     def pbStartScene(commands, ...)
  #       unless self.class.method_defined?(:touch_hooked_pbChoose)
  #         self.class.class_eval do
  #           alias touch_orig_pbChoose pbChoose rescue nil
  #           def pbChoose(commands, continue_idx = 0)
  #
  # ...e a guarda dele nunca fica verdadeira, porque touch_hooked_pbChoose nunca
  # chega a ser definido — portanto isso repete-se sempre que o menu abre.
  #
  # O resultado era o pior dos dois mundos: o nosso pbStartScene filtrava a lista
  # (o Multiplayer sumia), e logo a seguir o 061 apagava o nosso pbChoose, que e
  # quem traduz a posicao visivel de volta a original. O menu passava a devolver
  # a posicao crua e cada linha executava a acao da linha de cima: "Recuperar
  # Partida" caia no Multiplayer, "Opcoes" caia no apagar partida.
  #
  # Por isso isto e chamado DEPOIS do pbStartScene original, nunca antes.
  def instalar_pbChoose!
    return unless defined?(PokemonLoad_Scene)

    PokemonLoad_Scene.class_eval do
      # Nao voltar a embrulhar o nosso proprio embrulho — daria recursao infinita.
      # A assinatura distingue-os sem ambiguidade: so o nosso usa *args, que da
      # arity -1. O script base tem 1, o plugin 2 e o 061 tem -2.
      ja_nosso = begin
        instance_method(:pbChoose).arity == -1
      rescue
        false
      end

      unless ja_nosso
        # Nome fixo: cada reinstalacao apanha o pbChoose que estiver em vigor
        # naquele instante (o do 061), e nunca o nosso.
        alias_method :anil_esconder_mp_pbChoose, :pbChoose

        def pbChoose(*args)
          commands = args[0]
          return anil_esconder_mp_pbChoose(*args) unless commands.is_a?(Array)

          visiveis, mapa = AnilEsconderMenuMultiplayer.filtrar(commands)
          # Nada escondido: caminho original, sem risco nenhum.
          return anil_esconder_mp_pbChoose(*args) if visiveis.length == commands.length

          novos = args.dup
          novos[0] = visiveis
          # continue_idx tambem e uma posicao no array: tem de ser reescrito, ou
          # o atalho esquerda/direita passa a disparar na linha errada.
          if args.length > 1 && args[1].is_a?(Integer) && args[1] >= 0
            novos[1] = mapa.index(args[1]) || -1
          end

          escolha = anil_esconder_mp_pbChoose(*novos)
          # -2 e -3 sao os atalhos de troca de slot, e nil e cancelar: passam
          # inalterados, nao sao posicoes.
          return escolha unless escolha.is_a?(Integer) && escolha >= 0
          mapa[escolha] || escolha
        end
      end
    end
  rescue => e
    AnilLanRework.log("[MENU] falha ao instalar pbChoose: #{e.class}: #{e.message}") rescue nil
  end

  def instalar!
    return unless defined?(PokemonLoad_Scene)
    return if @instalado
    @instalado = true

    PokemonLoad_Scene.class_eval do
      # Filtra-se aqui porque a janela e dimensionada a partir desta lista: so
      # filtrar no pbChoose deixaria uma linha vazia no fim.
      unless method_defined?(:anil_esconder_mp_pbStartScene)
        alias_method :anil_esconder_mp_pbStartScene, :pbStartScene

        def pbStartScene(*args)
          commands = args[0]
          if commands.is_a?(Array)
            visiveis, _mapa = AnilEsconderMenuMultiplayer.filtrar(commands)
            args = args.dup
            args[0] = visiveis
          end
          resultado = anil_esconder_mp_pbStartScene(*args)
          # DEPOIS, nunca antes: e aqui dentro que o MOD 061 (re)define o
          # pbChoose dele e apaga o nosso. Reinstalar so agora garante que o
          # nosso embrulho fica por cima — e ele e quem traduz a posicao
          # visivel de volta a original.
          AnilEsconderMenuMultiplayer.instalar_pbChoose!
          resultado
        end
      end
    end

    # Primeira instalacao. A tela pode abrir por um caminho que nao passe pelo
    # nosso pbStartScene, e ai esta ja vale.
    instalar_pbChoose!

    AnilLanRework.log("[MENU] opcao Multiplayer escondida do menu inicial") rescue nil
  rescue => e
    AnilLanRework.log("[MENU] falha ao esconder Multiplayer: #{e.class}: #{e.message}") rescue nil
  end
end

# Tem de correr DEPOIS dos plugins: o pbChoose que interessa e o que o plugin
# instala, nao o do script base.
if defined?(AnilLanRework)
  module AnilLanRework
    class << self
      if !method_defined?(:anil_menu_mp_orig_apply_post_plugin_patches)
        alias_method :anil_menu_mp_orig_apply_post_plugin_patches, :apply_post_plugin_patches rescue nil
      end

      def apply_post_plugin_patches
        anil_menu_mp_orig_apply_post_plugin_patches if respond_to?(:anil_menu_mp_orig_apply_post_plugin_patches)
        AnilEsconderMenuMultiplayer.instalar!
      end
    end
  end
end

AnilLanRework.log("139_Esconder_Menu_Multiplayer carregado") rescue nil
