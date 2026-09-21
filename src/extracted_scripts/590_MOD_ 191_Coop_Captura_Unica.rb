# encoding: UTF-8
#===============================================================================
# MOD: 191_Coop_Captura_Unica — só quem lançou a bola fica com o Pokémon
#===============================================================================
# ⚠️ A ORDEM NUNCA FOI O PROBLEMA. O PROBLEMA E ONDE O POKEMON E GUARDADO.
#
# A regra de prioridade que foi desenhada — "quem iniciou lanca primeiro; so se
# a dele falhar e que o outro tem vez" — CONTINUA ESCRITA e continua a correr.
# Esta no `anil_rework_coop_item_priority`, e o laco dos itens ate para a meio
# quando a captura acaba a batalha:
#
#     return if @decision > 0
#
# Passei a procurar quem tinha desligado essa regra e nao ha nada desligado. O
# defeito e outro, e e mais fundo.
#
# Num coop a batalha corre INTEIRA nas duas maquinas. Quando a bola do iniciador
# acerta, as duas simulam o mesmo acerto — e as duas fazem isto:
#
#     @caughtPokemon.push(pkmn)          (0230_Battle_CatchAndStoreMixin:336)
#
# No fim, cada maquina percorre o SEU `@caughtPokemon` e guarda tudo no SEU
# jogador. O resultado sao dois Pokemon iguais, um em cada conta, e nenhuma das
# duas fez nada de errado do seu ponto de vista: cada uma viu uma captura e
# guardou-a.
#
# Ou seja: nao ha um lancamento a mais. Ha uma captura a ser CONTADA DUAS VEZES,
# uma em cada lado. E por isso que mexer na ordem nunca ia resolver.
#
#-------------------------------------------------------------------------------
# A CORRECCAO
#
# A batalha continua a acabar nas duas maquinas — o selvagem foi apanhado, e
# isso e verdade para os dois. O que muda e so quem FICA com ele: a maquina de
# quem NAO lancou tira-o da lista antes de a lista ser guardada.
#
# Nao se toca na animacao, nem nas mensagens, nem no fim da batalha. So no dono.
#
# ⚠️ Instala-se no `apply_post_plugin_patches` por duas razoes: os plugins ainda
# nao carregaram quando este ficheiro e lido (aliasar cedo ja partiu as batalhas
# todas uma vez), e o `Battle bug fixes.rb` redefine coisas de captura de raiz —
# tem de se entrar DEPOIS dele.
#===============================================================================

module AnilCoopCapturaUnica
  DIARIO = true

  module_function

  def log(t)
    return unless DIARIO
    File.open("Data/log_captura.txt", "a") { |f| f.puts("[#{Time.now.strftime('%H:%M:%S')}] #{t}") }
  rescue
    nil
  end

  def instalar!
    return if @instalado
    @instalado = true

    Battle.class_eval do
      def self.anil_cap_gancho(nome, &corpo)
        return unless method_defined?(nome)
        velho = :"anil_cap_orig_#{nome}"
        return if method_defined?(velho)
        alias_method(velho, nome)
        define_method(nome, &corpo)
      end

      # Quem lancou. O `pbThrowPokeBall` recebe o ALVO, nao o atirador, portanto
      # a unica forma de saber de quem foi a bola e apanha-lo aqui em cima.
      anil_cap_gancho(:pbUsePokeBallInBattle) do |item, idxBattler, userBattler|
        anterior = @anil_cap_quem
        @anil_cap_quem = (userBattler.index rescue nil)
        begin
          send(:anil_cap_orig_pbUsePokeBallInBattle, item, idxBattler, userBattler)
        ensure
          @anil_cap_quem = anterior
        end
      end

      # Este e o unico sitio que muda: se a bola nao foi minha, o Pokemon sai da
      # minha lista de apanhados. A batalha acaba na mesma, as mensagens sao as
      # mesmas — so nao fico com ele.
      anil_cap_gancho(:pbThrowPokeBall) do |idxBattler, ball, catch_rate = nil, showPlayer = false|
        antes = (@caughtPokemon ? @caughtPokemon.length : 0)
        r = send(:anil_cap_orig_pbThrowPokeBall, idxBattler, ball, catch_rate, showPlayer)
        begin
          depois = (@caughtPokemon ? @caughtPokemon.length : 0)
          if depois > antes
            ctx = (AnilLanRework::BattleSync.active_context rescue nil)
            if ctx && ctx.mode == :coop && @anil_cap_quem
              local, remoto = AnilLanRework::BattleSync.coop_slots_for(self)
              if remoto && @anil_cap_quem == remoto
                tirados = @caughtPokemon.slice!(antes, depois - antes)
                nomes = Array(tirados).map { |p| (p.speciesName rescue "?") }.join(", ")
                AnilCoopCapturaUnica.log("a bola foi do parceiro (slot #{remoto}); " \
                  "#{nomes} sai da minha lista — a batalha acaba na mesma")
              else
                AnilCoopCapturaUnica.log("a bola foi minha (slot #{@anil_cap_quem}, " \
                  "local=#{local.inspect}); fico com ele")
              end
            end
          end
        rescue => e
          AnilCoopCapturaUnica.log("falha a decidir o dono: #{e.class}: #{e.message}")
        end
        r
      end
    end
  rescue => e
    (File.open("Data/log_captura.txt", "a") { |f|
      f.puts("FALHOU A INSTALAR: #{e.class}: #{e.message}") } rescue nil)
  end
end

if defined?(AnilLanRework) && AnilLanRework.respond_to?(:apply_post_plugin_patches)
  module AnilLanRework
    class << self
      unless method_defined?(:anil_capunica_orig_apply_post_plugin_patches)
        alias anil_capunica_orig_apply_post_plugin_patches apply_post_plugin_patches
        def apply_post_plugin_patches
          anil_capunica_orig_apply_post_plugin_patches
          AnilCoopCapturaUnica.instalar!
        end
      end
    end
  end
end
