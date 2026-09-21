#===============================================================================
# MOD: 108_Custom_Money_Bags.rb
#-------------------------------------------------------------------------------
# Implementação dos novos itens de Saco de Moedas com valores variáveis
# baseados em probabilidades!
#===============================================================================

MONEY_BAG_CONFIG = {
  :SACOMOEDAPEQUENO => {
    name: "Saco de Moedas (Pequeno)",
    plural: "Sacos de Moedas (Pequenos)",
    desc: "Um pequeno saco de moedas. Abra na mochila para ganhar de 10.000 a 25.000 Moedas!",
    rewards: [
      { chance: 70, amount: 10000, type: :common,   msg: "Você abriu o {1} e obteve {2} Moedas!" },
      { chance: 25, amount: 15000, type: :uncommon, msg: "¡Que sorte! Você abriu o {1} e obteve {2} Moedas!" },
      { chance: 5,  amount: 25000, type: :rare,     msg: "¡INCRÍVEL! Você deu a sorte grande no {1} e obteve {2} Moedas!" }
    ]
  },
  :SACOMOEDAMEDIO => {
    name: "Saco de Moedas (Médio)",
    plural: "Sacos de Moedas (Médios)",
    desc: "Um saco de moedas de tamanho médio. Abra na mochila para ganhar de 35.000 a 100.000 Moedas!",
    rewards: [
      { chance: 70, amount: 35000,  type: :common,   msg: "Você abriu o {1} e obteve {2} Moedas!" },
      { chance: 25, amount: 50000,  type: :uncommon, msg: "¡Que sorte! Você abriu o {1} e obteve {2} Moedas!" },
      { chance: 5,  amount: 100000, type: :rare,     msg: "¡INCRÍVEL! Você deu a sorte grande no {1} e obteve {2} Moedas!" }
    ]
  },
  :SACOMOEDAGRANDE => {
    name: "Saco de Moedas (Grande)",
    plural: "Sacos de Moedas (Grandes)",
    desc: "Um grande saco cheio de moedas reluzentes. Abra na mochila para ganhar de 150.000 a 500.000 Moedas!",
    rewards: [
      { chance: 70, amount: 150000, type: :common,   msg: "Você abriu o {1} e obteve {2} Moedas!" },
      { chance: 25, amount: 300000, type: :uncommon, msg: "¡Que sorte! Você abriu o {1} e obteve {2} Moedas!" },
      { chance: 5,  amount: 500000, type: :rare,     msg: "¡INCRÍVEL! Você deu a sorte grande no {1} e obteve {2} Moedas!" }
    ]
  }
}

#===============================================================================
# ABERTURA DO SACO
#===============================================================================
# Ordem obrigatoria:  CONSOME -> premio -> GRAVA -> apresentacao.
#
# Nao e so pela duplicacao. E sobretudo pelo SORTEIO. O premio sai de um
# rand(100), e enquanto a gravacao ficasse para depois, quem tirasse o premio
# comum fechava o jogo, voltava a entrar com o saco intacto e sorteava outra
# vez ate sair o raro. Gravar antes de mostrar o resultado fecha essa porta:
# quando o jogador ve o numero, o numero ja esta em disco.
#
# Por isso o consumo tem de ser NOSSO e nao do motor. O motor so remove DEPOIS
# de o handler devolver, portanto gravar dentro do handler gravaria o saco
# ainda na mochila — que era o bug da duplicacao das caixas de presente
# (MOD 068), resolvido la da mesma maneira.
#
# Como se impede o motor de remover um SEGUNDO saco:
#
#   bag.remove(item) if intret == 1 && itm.consumed_after_use?   (UseFromBag)
#   $bag.remove(item) if ret > 0 && ...consumed_after_use?       (UseInField)
#
# Os dois caminhos passam pelo consumed_after_use?, que e
# `!is_important? && @consumable`. Marca-se @consumable = false para estes tres
# itens e o motor deixa de mexer neles nos DOIS caminhos — e podemos continuar
# a devolver 1, que DEIXA A MOCHILA ABERTA (o 2 fechava-a a cada saco).
#
# ⚠️ O @consumable e posto aqui, em codigo, e NAO no PBS de proposito. Se
# fosse no items.dat e este MOD falhasse a carregar, o saco deixava de ser
# consumido por ninguem: moedas infinitas. Assim as duas metades viajam
# sempre juntas no mesmo Scripts.rxdata.
#===============================================================================
module MoneyBagSystem
  @abrindo = false

  def self.saco?(item)
    return false if item.nil?
    MONEY_BAG_CONFIG.key?(item.is_a?(Symbol) ? item : item.to_s.to_sym)
  end

  def self.sortear(cfg)
    roll = rand(100)
    acumulado = 0
    cfg[:rewards].each do |r|
      acumulado += r[:chance]
      return r if roll < acumulado
    end
    cfg[:rewards].first
  end

  # Devolve true se o saco foi mesmo aberto.
  def self.abrir(item)
    sym = item.is_a?(Symbol) ? item : item.to_s.to_sym
    cfg = MONEY_BAG_CONFIG[sym]
    return false if cfg.nil?
    return false if @abrindo          # reentrancia: um saco de cada vez
    return false if $bag.nil? || !$bag.has?(sym)

    @abrindo = true
    begin
      # 1. consome ANTES de qualquer coisa
      $bag.remove(sym, 1)

      # 2. sorteia e paga
      premio   = sortear(cfg)
      montante = premio[:amount]

      # A MOEDA DESTE JOGO E `coins`, NAO `money`. O @money fica em 3000 para
      # toda a gente (ver first_upload_money_cap no servidor) e nenhuma loja
      # que interessa o le. Mesmo clamp que a venda por moedas do MOD 058.
      max_coins = (Settings::MAX_COINS rescue 999_999_999)
      $player.coins = [[($player.coins || 0) + montante, max_coins].min, 0].max

      # 3. GRAVA. A partir daqui o estado ja e o final; o que vem a seguir e so
      #    espectaculo e pode ser interrompido a vontade.
      gravar!(sym, montante)

      # 4. so agora se mostra
      apresentar(cfg, premio, montante)
      true
    rescue => e
      (AnilLanRework.log("saco de moedas: erro a abrir #{sym}: #{e.class}: #{e.message}") rescue nil)
      false
    ensure
      @abrindo = false
    end
  end

  def self.gravar!(sym, montante)
    if defined?(AnilLanRework) && AnilLanRework.respond_to?(:gravar_ja!)
      AnilLanRework.gravar_ja!("saco_moeda")
      (AnilLanRework.log("saco de moedas: #{sym} deu #{montante} moedas, gravado antes de mostrar") rescue nil)
    elsif defined?(Game) && Game.respond_to?(:save)
      Game.save
    elsif defined?(SaveData) && SaveData.respond_to?(:save_to_file)
      SaveData.save_to_file(SaveData::FILE_PATH)
    end
  rescue => e
    (AnilLanRework.log("saco de moedas: falha ao gravar: #{e.class}: #{e.message}") rescue nil)
  end

  def self.apresentar(cfg, premio, montante)
    case premio[:type]
    when :common   then (pbSEPlay("Mart buy item") rescue nil)
    when :uncommon then (pbSEPlay("Pkmn healing") rescue nil)
    when :rare
      (pbSEPlay("Level up") rescue nil)
      ($game_screen.start_flash(Color.new(255, 255, 128, 180), 24) rescue nil) if $game_screen
    end
    formatado = montante.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\1.').reverse
    pbMessage(_INTL(premio[:msg], cfg[:name], formatado))
  end
end

MONEY_BAG_CONFIG.each do |item_id, cfg|
  # Registar no GameData::Item se ainda nao existir (normalmente ja vem do PBS)
  if defined?(GameData::Item)
    unless GameData::Item.exists?(item_id)
      GameData::Item.register({
        :id               => item_id,
        :real_name        => cfg[:name],
        :real_name_plural => cfg[:plural],
        :pocket           => 1,
        :price            => 0,
        :field_use        => 2, # Direct
        :flags            => ["Fling_30"],
        :real_description => cfg[:desc]
      })
    end

  end

  # 1 = usado, NAO fecha a mochila. Com @consumable = false o motor nao remove.
  ItemHandlers::UseFromBag.add(item_id, proc { |item|
    next MoneyBagSystem.abrir(item) ? 1 : 0
  })

  # Caminho do item registado (pbUseKeyItemInField). Tambem nao remove nada.
  ItemHandlers::UseInField.add(item_id, proc { |item|
    next MoneyBagSystem.abrir(item)
  })
end

#===============================================================================
# ⚠️ O @consumable TEM DE SER MARCADO DEPOIS DE OS DADOS CARREGAREM
#===============================================================================
# Quando este ficheiro corre, o GameData::Item ainda esta vazio: os .dat so sao
# lidos no Main, depois de todas as seccoes de script. Marcar o @consumable la
# em cima apanhava sempre a excepcao em silencio, e o motor continuava
# autorizado a remover um SEGUNDO saco por cada abertura — o bug de origem.
#
# O on_enter_map corre com tudo ja carregado. E o mesmo caminho que o
# 100_Rarity_Eggs_System e a ficha do cassino usam.
#===============================================================================
$anil_sacos_moeda_marcados = false
if defined?(EventHandlers) && EventHandlers.respond_to?(:add)
  EventHandlers.add(:on_enter_map, :anil_sacos_moeda_consumable, proc { |_antigo|
    unless $anil_sacos_moeda_marcados
      $anil_sacos_moeda_marcados = true
      MONEY_BAG_CONFIG.each_key do |sym|
        begin
          GameData::Item.get(sym).instance_variable_set(:@consumable, false)
        rescue => e
          (AnilLanRework.log("saco de moedas: nao consegui marcar #{sym}: #{e.class}") rescue nil)
        end
      end
    end
  })
end
