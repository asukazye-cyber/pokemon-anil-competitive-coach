#===============================================================================
# Online Economy Mode (Isolated Saves & Casino Coins) for Pokémon Essentials v21.1
# Modular Script - Loads after Core Multiplayer Scripts
#===============================================================================

module AnilLanRework
  class << self
    attr_accessor :multiplayer_mode
  end
  @multiplayer_mode = false unless defined?(@multiplayer_mode)
end

#===============================================================================
# DynamicSavePath Class for Save Redirection
#===============================================================================
class DynamicSavePath
  def self.offline_path
    base = "Game.rxdata"
    File.directory?(System.data_directory) ? File.join(System.data_directory, base) : "./" + base
  end

  def self.multiplayer_path
#region debug-point cloud-save-path-resolution
    pid = nil
    
    # 1. Tenta ler do arquivo multiplayer_player.txt para manter o nome consistente
    file = "multiplayer_player.txt"
    if File.exist?(file)
      begin
        File.readlines(file, encoding: "UTF-8").each do |line|
          parts = line.strip.split("=", 2)
          if parts.size == 2 && parts[0].strip == "id"
            pid = parts[1].to_s.strip
            break
          end
        end
      rescue
      end
    end

    # 2. Normaliza o ID usando a fonte canônica do save/jogador, removendo legado LAN/JoiPlay
    if defined?(AnilLanRework)
      if AnilLanRework.respond_to?(:normalized_player_id)
        pid = AnilLanRework.normalized_player_id(pid) rescue pid
      elsif (pid.nil? || pid.empty? || pid.downcase.include?("localhost")) && AnilLanRework.respond_to?(:get_player_id)
        pid = AnilLanRework.get_player_id rescue nil
      end
    end

    # 3. Se ainda assim for nulo, vazio ou localhost, cai no fallback seguro
    if pid.nil? || pid.empty? || pid.downcase.include?("localhost")
      pid = "Game_mp"
    end

    # Sanitiza e normaliza o nome do arquivo para minusculo
    pid = pid.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
    base = "#{pid}.rxdata"
    resolved = File.directory?(System.data_directory) ? File.join(System.data_directory, base) : "./" + base
    if defined?(AnilLanRework) && AnilLanRework.respond_to?(:debug_log)
      cfg_id = nil
      begin
        cfg_id = File.exist?("multiplayer_player.txt") ? File.read("multiplayer_player.txt", encoding: "UTF-8")[/^\s*id\s*=\s*(.+)\s*$/, 1].to_s.strip : ""
      rescue
        cfg_id = ""
      end
      runtime_id = (AnilLanRework.get_player_id rescue nil).to_s
      current_name = (defined?($player) && $player) ? $player.name.to_s : ""
      current_oid = (defined?($PokemonGlobal) && $PokemonGlobal && $PokemonGlobal.respond_to?(:online_id) ? $PokemonGlobal.online_id.to_s : "")
      AnilLanRework.debug_log("DynamicSavePath.multiplayer_path - cfg_id=#{cfg_id.inspect} runtime_id=#{runtime_id.inspect} player_name=#{current_name.inspect} online_id=#{current_oid.inspect} resolved=#{resolved.inspect}")
    end
    resolved
#endregion debug-point cloud-save-path-resolution
  end

  def to_s
    get_path
  end

  def to_str
    get_path
  end

  def to_path
    get_path
  end

  def +(other)
    get_path + other.to_s
  end

  def ==(other)
    get_path == other.to_s
  end

  def eql?(other)
    get_path.eql?(other.to_s)
  end

  def hash
    get_path.hash
  end

  private

  def get_path
    if defined?(AnilLanRework) && AnilLanRework.respond_to?(:online_session?) && AnilLanRework.online_session?
      DynamicSavePath.multiplayer_path
    elsif defined?(AnilLanRework) && AnilLanRework.respond_to?(:multiplayer_mode) && AnilLanRework.multiplayer_mode
      DynamicSavePath.multiplayer_path
    elsif $PokemonGlobal && $PokemonGlobal.respond_to?(:is_multiplayer_online_save) && $PokemonGlobal.is_multiplayer_online_save
      DynamicSavePath.multiplayer_path
    else
      DynamicSavePath.offline_path
    end
  end
end

# Rebind constant FILE_PATH in SaveData
module SaveData
  send(:remove_const, :FILE_PATH) if const_defined?(:FILE_PATH)
  FILE_PATH = DynamicSavePath.new

  class << self
    def exists?
      return File.file?(FILE_PATH.to_s)
    end

    alias_method :original_get_data_from_file, :get_data_from_file
    def get_data_from_file(file_path)
      original_get_data_from_file(file_path.to_s)
    end

    alias_method :original_read_from_file, :read_from_file
    def read_from_file(file_path)
      original_read_from_file(file_path.to_s)
    end

    alias_method :original_save_to_file, :save_to_file
    def save_to_file(file_path)
      original_save_to_file(file_path.to_s)
    end

    def delete_file
      File.delete(FILE_PATH.to_s)
      File.delete(FILE_PATH.to_s + ".bak") if File.file?(FILE_PATH.to_s + ".bak")
    end
  end
end

# Game.save & Game.auto_save monkey patches moved to 040_Multiplayer_Post_Plugin_Patches.rb to run post-plugins.

#===============================================================================
# Load Screen Patches for Multiplayer Option
# Note: Since the Multi Save plugin (13_Multi_Save) loads later and overrides
# PokemonLoadScreen, the multiplayer option menu injection is implemented 
# directly in PluginScripts_Extraidos/13_Multi_Save/000_Multi_Save_rb.rb
#===============================================================================

#===============================================================================
# F7 Save Transition Patch (Scene_Map_MultiplayerMainMenu)
#===============================================================================
module Scene_Map_MultiplayerMainMenu
  def ensure_save_loaded(mode_label)
    return save_is_loaded?
  end
  module_function :ensure_save_loaded
end

#===============================================================================
# CoinMartAdapter & CoinMartScreen
#===============================================================================
class CoinMartAdapter < PokemonMartAdapter
  def getMoney
    return $player ? $player.coins : 0
  end

  def getMoneyString
    return $player ? _INTL("{1} <icon=multiplayer_coin>", $player.coins.to_s_formatted) : "0"
  end

  def setMoney(value)
    $player.coins = value if $player
  end

  def getDisplayPrice(item, selling = false)
    price = getPrice(item, selling).to_s_formatted
    return price
  end
end

class CoinMartScreen < PokemonMartScreen
  def initialize(scene, stock)
    @scene = scene
    @stock = stock
    @adapter = CoinMartAdapter.new
  end

  def pbBuyScreen
    @scene.pbStartBuyScene(@stock, @adapter)
    item = nil
    loop do
      item = @scene.pbChooseBuyItem
      break if !item
      quantity       = 0
      itemname       = @adapter.getName(item)
      itemnameplural = @adapter.getNamePlural(item)
      price = @adapter.getPrice(item)
      if @adapter.getMoney < price
        pbDisplayPaused(_INTL("Você não tem Moedas suficientes."))
        next
      end
      if GameData::Item.get(item).is_important?
        next if !pbConfirm(_INTL("Então você quer {1}?\nSerá(ão) {2} Moedas. Tudo bem?",
                                 itemname, price.to_s_formatted))
        quantity = 1
      else
        maxafford = (price <= 0) ? Settings::BAG_MAX_PER_SLOT : @adapter.getMoney / price
        maxafford = Settings::BAG_MAX_PER_SLOT if maxafford > Settings::BAG_MAX_PER_SLOT
        quantity = @scene.pbChooseNumber(
          _INTL("Quantos {1} você quer?", itemnameplural), item, maxafford
        )
        next if quantity == 0
        price *= quantity
        if quantity > 1
          next if !pbConfirm(_INTL("Então você quer {1} {2}?\nSerá(ão) {3} Moedas. Tudo bem?",
                                   quantity, itemnameplural, price.to_s_formatted))
        elsif quantity > 0
          next if !pbConfirm(_INTL("Então você quer {1} {2}?\nSerá(ão) {3} Moedas. Tudo bem?",
                                   quantity, itemname, price.to_s_formatted))
        end
      end
      if @adapter.getMoney < price
        pbDisplayPaused(_INTL("Você não tem Moedas suficientes."))
        next
      end
      added = 0
      quantity.times do
        break if !@adapter.addItem(item)
        added += 1
      end
      if added == quantity
        $stats.money_spent_at_marts += price rescue nil
        $stats.mart_items_bought += quantity rescue nil
        @adapter.setMoney(@adapter.getMoney - price)
        @stock.delete_if { |itm| GameData::Item.get(itm).is_important? && $bag.has?(itm) }
        pbDisplayPaused(_INTL("Aqui está! Muito obrigado!")) { pbSEPlay("Mart buy item") }
      else
        added.times do
          if !@adapter.removeItem(item)
            raise _INTL("Falha ao remover itens guardados.")
          end
        end
        pbDisplayPaused(_INTL("Sua Mochila está cheia."))
      end
    end
    @scene.pbEndBuyScene
  end

  def pbSellScreen
    item = @scene.pbStartSellScene(@adapter.getInventory, @adapter)
    loop do
      item = @scene.pbChooseSellItem
      break if !item
      itemname       = @adapter.getName(item)
      itemnameplural = @adapter.getNamePlural(item)
      if !@adapter.canSell?(item)
        pbDisplayPaused(_INTL("Oh, não. Não posso comprar {1}.", itemnameplural))
        next
      end
      price = @adapter.getPrice(item, true)
      qty = @adapter.getQuantity(item)
      next if qty == 0
      @scene.pbShowMoney
      if qty > 1
        qty = @scene.pbChooseNumber(
          _INTL("Quantos {1} quer vender?", itemnameplural), item, qty
        )
      end
      if qty == 0
        @scene.pbHideMoney
        next
      end
      price *= qty
      if pbConfirm(_INTL("Posso pagar {1} Moedas.\nTudo bem?", price.to_s_formatted))
        old_money = @adapter.getMoney
        @adapter.setMoney(@adapter.getMoney + price)
        $stats.money_earned_at_marts += @adapter.getMoney - old_money rescue nil
        qty.times { @adapter.removeItem(item) }
        sold_item_name = (qty > 1) ? itemnameplural : itemname
        pbDisplayPaused(_INTL("Entregou {1} e recebeu {2} Moedas.",
                              sold_item_name, price.to_s_formatted)) { pbSEPlay("Mart buy item") }
        @scene.pbRefresh
      end
      @scene.pbHideMoney
    end
    @scene.pbEndSellScene
  end
end

class PokemonMart_Scene
  alias_method :original_pbRefresh, :pbRefresh
  def pbRefresh
    original_pbRefresh
    if @adapter.is_a?(CoinMartAdapter)
      @sprites["moneywindow"].text = _INTL("Moedas:\n<r>{1}", @adapter.getMoneyString)
    end
  end
end

def pbCoinMart(stock, speech = nil, cantsell = false)
  orange_items = [
    :MASTERBALL, :PPMAX, :ABILITYCAPSULE, :ABILITYPATCH, 
    :RARECANDY, :PPUP, :MAXREVIVE, :OLDAMBER, :HELIXFOSSIL, :DOMEFOSSIL,
    :SCapsula, :ACapsula, :DCapsula, :AECapsula, :DECapsula, :VCapsula,
    :SHINYZADOR
  ]
  if stock.is_a?(Array)
    stock.delete_if do |item|
      orange_items.include?(item) || (GameData::Item.get(item).is_mega_stone? rescue false)
    end
  end
  stock.delete_if { |item| GameData::Item.get(item).is_important? && $bag.has?(item) }
  commands = []
  cmdBuy  = -1
  cmdSell = -1
  cmdQuit = -1
  commands[cmdBuy = commands.length]  = _INTL("Quiero comprar")
  commands[cmdSell = commands.length] = _INTL("Quiero vender") if !cantsell
  commands[cmdQuit = commands.length] = _INTL("No, gracias")
  cmd = pbMessage(speech || _INTL("Bem-vindo! Em que posso ajudar?"), commands, cmdQuit + 1)
  loop do
    if cmdBuy >= 0 && cmd == cmdBuy
      scene = PokemonMart_Scene.new
      screen = CoinMartScreen.new(scene, stock)
      screen.pbBuyScreen
    elsif cmdSell >= 0 && cmd == cmdSell
      scene = PokemonMart_Scene.new
      screen = CoinMartScreen.new(scene, stock)
      screen.pbSellScreen
    else
      pbMessage(_INTL("Volte sempre!"))
      break
    end
    cmd = pbMessage(_INTL("Posso ajudar em algo mais?"), commands, cmdQuit + 1)
  end
  $game_temp.clear_mart_prices
end

def pbCasinoMart(stock, speech = nil)
  pbCoinMart(stock, speech, true)
end

# Interceptador global do PokeMart normal para impedir venda de itens laranjas, tampinhas e Mega Stones
alias anil_economy_original_pbPokemonMart pbPokemonMart unless defined?(anil_economy_original_pbPokemonMart)
def pbPokemonMart(stock, speech = nil, cantsell = false)
  orange_items = [
    :MASTERBALL, :PPMAX, :ABILITYCAPSULE, :ABILITYPATCH, 
    :RARECANDY, :PPUP, :MAXREVIVE, :OLDAMBER, :HELIXFOSSIL, :DOMEFOSSIL,
    :SCapsula, :ACapsula, :DCapsula, :AECapsula, :DECapsula, :VCapsula,
    :SHINYZADOR
  ]
  if stock.is_a?(Array)
    stock.delete_if do |item|
      orange_items.include?(item) || (GameData::Item.get(item).is_mega_stone? rescue false)
    end
  end
  anil_economy_original_pbPokemonMart(stock, speech, cantsell)
end

#===============================================================================
# Pokémon Buyer NPC (pbSellPokemonForCoins)
#===============================================================================
def pbSellPokemonForCoins
  party = $player.party
  valid_party_pkmn = party.select { |p| !p.egg? && !p.shadowPokemon? }
  if valid_party_pkmn.length <= 1
    pbMessage(_INTL("Você precisa ter pelo menos um Pokémon válido na sua equipe."))
    return
  end

  chosen = -1
  pbFadeOutIn do
    scene = PokemonParty_Scene.new
    screen = PokemonPartyScreen.new(scene, party)
    screen.pbStartScene(_INTL("Escolha um Pokémon para vender."), false)
    chosen = screen.pbChoosePokemon
    screen.pbEndScene
  end

  if chosen >= 0
    pkmn = party[chosen]
    if pkmn.egg?
      pbMessage(_INTL("Não é possível vender um Ovo."))
      return
    end
    if pkmn.shadowPokemon?
      pbMessage(_INTL("Não é possível vender um Pokémon Shadow."))
      return
    end

    # Calculate price
    price = pbCalculatePokemonCoinValue(pkmn)
    
    if pbConfirmMessage(_INTL("O valor estimado de {1} e de {2} Moedas. Deseja vende-lo?", pkmn.name, price.to_s_formatted))
      # Re-verify party size right before transaction
      valid_party_pkmn = party.select { |p| !p.egg? && !p.shadowPokemon? }
      if valid_party_pkmn.length <= 1
        pbMessage(_INTL("Você precisa ter pelo menos um Pokémon válido na sua equipe."))
        return
      end
      
      # Perform transaction
      party.delete_at(chosen)
      max_coins = Settings::MAX_COINS rescue 999_999_999
      $player.coins = [[($player.coins || 0) + price, max_coins].min, 0].max
      pbMessage(_INTL("Voce vendeu {1} por {2} Moedas.", pkmn.name, price.to_s_formatted))
      
      # Save game
      if defined?(Game) && Game.respond_to?(:save)
        Game.save
      else
        SaveData.save_to_file(SaveData::FILE_PATH)
      end
    end
  end
end

def pbCalculatePokemonCoinValue(pkmn)
  sp = pkmn.species_data
  level = pkmn.level
  bst = sp.base_stat_total rescue 400
  base_value = (level * 8) + (bst / 5.0)
  
  total_ivs = pkmn.iv.values.sum rescue 0
  iv_multiplier = 1.0 + (total_ivs / 186.0)
  
  shiny_multiplier = pkmn.shiny? ? 5.0 : 1.0
  
  legendary_bonus = 0
  if sp && (sp.has_flag?("Legendary") || sp.has_flag?("Mythical") || sp.has_flag?("UltraBeast") || sp.has_flag?("Paradox"))
    legendary_bonus = 1000
  end
  
  final_value = (base_value * iv_multiplier * shiny_multiplier).round + legendary_bonus
  return final_value
end

#===============================================================================
# P2P Market Patches for Casino Coins
#===============================================================================
module AnilLanRework
  module PlayerMarket
    class << self
      alias_method :original_purchase_pokemon_listing, :purchase_pokemon_listing
      def purchase_pokemon_listing(listing)
        if AnilLanRework.multiplayer_mode
          return [false, _INTL("Não há espaço livre no PC.")] unless can_receive_pokemon?
          price = listing["price"].to_i
          return [false, _INTL("Moedas insuficientes.")] if $player.coins.to_i < price
          request_id = build_request_id
          if AnilLanRework.host?
            result = host_purchase_pokemon(listing["listing_id"], AnilLanRework.self_internal_id)
          else
            host_id = host_market_id
            return [false, _INTL("Host do mercado indisponivel.")] if host_id.empty?
            AnilLanRework.connection.send_packet("market_purchase_pokemon",
              "to_id"      => host_id,
              "request_id" => request_id,
              "listing_id" => listing["listing_id"].to_i
            )
            result = wait_for_result(request_id)
          end
          return [false, _INTL("A compra falhou por tempo limite.")] unless result
          return [false, result["message"].to_s] unless result["ok"] == true
          stored, message = store_pokemon_locally(result["pokemon"])
          return [false, message] unless stored
          max_coins = Settings::MAX_COINS rescue 999_999_999
          $player.coins = [[$player.coins - result["price"].to_i, 0].max, max_coins].min
          save_game
          [true, message]
        else
          original_purchase_pokemon_listing(listing)
        end
      end

      alias_method :original_purchase_item_listing, :purchase_item_listing
      def purchase_item_listing(listing)
        if AnilLanRework.multiplayer_mode
          item_data = GameData::Item.try_get(listing["item"])
          return [false, _INTL("Item invalido.")] unless item_data
          return [false, _INTL("Moedas insuficientes.")] if $player.coins.to_i < listing["price"].to_i
          return [false, _INTL("Sem espaco na Mochila.")] unless $bag.can_add?(item_data.id, listing["quantity"].to_i)
          request_id = build_request_id
          if AnilLanRework.host?
            result = host_purchase_item(listing["listing_id"], AnilLanRework.self_internal_id)
          else
            host_id = host_market_id
            return [false, _INTL("Host do mercado indisponivel.")] if host_id.empty?
            AnilLanRework.connection.send_packet("market_purchase_item",
              "to_id"      => host_id,
              "request_id" => request_id,
              "listing_id" => listing["listing_id"].to_i
            )
            result = wait_for_result(request_id)
          end
          return [false, _INTL("A compra falhou por tempo limite.")] unless result
          return [false, result["message"].to_s] unless result["ok"] == true
          qty = result["quantity"].to_i
          $bag.add(item_data.id, qty)
          max_coins = Settings::MAX_COINS rescue 999_999_999
          $player.coins = [[$player.coins - result["price"].to_i, 0].max, max_coins].min
          save_game
          item_name = qty > 1 ? item_data.portion_name_plural : item_data.portion_name
          [true, AnilLanRework.ui_format("Comprou {1} {2}.", qty, item_name)]
        else
          original_purchase_item_listing(listing)
        end
      end

      alias_method :original_credit_sale_to_seller, :credit_sale_to_seller
      def credit_sale_to_seller(seller_id, amount)
        if AnilLanRework.multiplayer_mode
          ensure_market_metadata
          seller_key = seller_id.to_s
          return if seller_key.empty? || amount.to_i <= 0
          if seller_key == AnilLanRework.self_internal_id
            max_coins = Settings::MAX_COINS rescue 999_999_999
            $player.coins = [[$player.coins + amount.to_i, max_coins].min, 0].max
            @pending_messages << AnilLanRework.ui_format("Recebeu {1} Moedas por uma venda online.", amount.to_i)
          else
            current = $PokemonGlobal.online_market_payouts[seller_key].to_i
            $PokemonGlobal.online_market_payouts[seller_key] = current + amount.to_i
          end
          save_game
          flush_pending_payouts_for_online_players
        else
          original_credit_sale_to_seller(seller_id, amount)
        end
      end

      alias_method :original_flush_pending_payouts_for_online_players, :flush_pending_payouts_for_online_players
      def flush_pending_payouts_for_online_players
        if AnilLanRework.multiplayer_mode
          return unless AnilLanRework.host?
          ensure_market_metadata
          payouts = $PokemonGlobal.online_market_payouts
          payouts.keys.each do |seller_id|
            next if seller_id.to_s.empty?
            amount = payouts[seller_id].to_i
            next if amount <= 0
            if seller_id.to_s == AnilLanRework.self_internal_id
              max_coins = Settings::MAX_COINS rescue 999_999_999
              $player.coins = [[$player.coins + amount, max_coins].min, 0].max
              @pending_messages << AnilLanRework.ui_format("Recebeu {1} Moedas por vendas online pendentes.", amount)
              payouts.delete(seller_id)
              next
            end
            next unless AnilLanRework.players[seller_id.to_s]
            AnilLanRework.connection.send_packet("market_payout",
              "to_id"  => seller_id.to_s,
              "amount" => amount
            )
            payouts.delete(seller_id)
          end
          save_game
        else
          original_flush_pending_payouts_for_online_players
        end
      end

      alias_method :original_receive_payout, :receive_payout
      def receive_payout(packet)
        if AnilLanRework.multiplayer_mode
          amount = packet["amount"].to_i
          return if amount <= 0
          max_coins = Settings::MAX_COINS rescue 999_999_999
          $player.coins = [[$player.coins + amount, max_coins].min, 0].max
          @pending_messages << AnilLanRework.ui_format("Recebeste {1} Moedas por vendas online.", amount)
          save_game
        else
          original_receive_payout(packet)
        end
      end
    end

    class OnlineItemMarketAdapter
      alias_method :original_getMoneyString, :getMoneyString
      def getMoneyString
        if defined?(AnilLanRework) && AnilLanRework.multiplayer_mode
          return _INTL("{1} Moedas", $player.coins.to_s_formatted)
        else
          original_getMoneyString
        end
      end

      alias_method :original_getDisplayPrice, :getDisplayPrice unless method_defined?(:original_getDisplayPrice)
      def getDisplayPrice(listing, selling = false)
        if defined?(AnilLanRework) && AnilLanRework.multiplayer_mode
          listing["price"].to_i.to_s_formatted
        else
          original_getDisplayPrice(listing, selling)
        end
      end
    end

    class OnlinePokemonMarketAdapter
      alias_method :original_getMoneyString, :getMoneyString
      def getMoneyString
        if defined?(AnilLanRework) && AnilLanRework.multiplayer_mode
          return _INTL("{1} Moedas", $player.coins.to_s_formatted)
        else
          original_getMoneyString
        end
      end

      alias_method :original_getDisplayPrice, :getDisplayPrice unless method_defined?(:original_getDisplayPrice)
      def getDisplayPrice(listing, selling = false)
        if defined?(AnilLanRework) && AnilLanRework.multiplayer_mode
          listing["price"].to_i.to_s_formatted
        else
          original_getDisplayPrice(listing, selling)
        end
      end
    end
  end
end

#===============================================================================
# Desativação completa do Shinyzador
#===============================================================================
if defined?(ItemHandlers)
  ItemHandlers::UseFromBag.add(:SHINYZADOR, proc { |item|
    pbMessage(_INTL("Este item foi desativado e removido do jogo."))
    next 0
  }) rescue nil
end
