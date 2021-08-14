# @version ^0.2.0

struct Option:
    optionId: uint256
    owner: address
    riskTaker: address
    underlyingTokenTicker: String[4]
    duration: uint256
    buySellType: String[4]
    optionType: String[8]
    strikePrice: decimal
    marketPrice: decimal
    startTime: uint256
    purchased: bool

# Each option is worth 10 tokens. Regardless of type of option (sell/buy)
SHARES_PER_OPTION: constant(uint256) = 10

# Curve
curveOptions: HashMap[uint256, Option]
curveCounter: uint256

# Uniswap
uniOptions: HashMap[uint256, Option]
uniCounter: uint256

# Compound
compoundOptions: HashMap[uint256, Option]
compoundCounter: uint256

tokenToPrice: HashMap[String[4], uint256]

durationMultiplier: HashMap[uint256, decimal]

sellerLedger: HashMap[String[4], HashMap[uint256, decimal]]

buyerLedger: HashMap[String[4], HashMap[uint256, decimal]]

creatorType: HashMap[uint256, String[5]]

optionForSale: HashMap[String[4], HashMap[uint256, uint256]]

@external
def __init__(_crv_price: uint256, _uni_price: uint256, _comp_price: uint256):
    self.tokenToPrice["CRV"] = _crv_price
    self.tokenToPrice["UNI"] = _uni_price
    self.tokenToPrice["COMP"] = _comp_price

    self.durationMultiplier[1_296_000] = 0.1
    self.durationMultiplier[2_592_000] = 0.3
    self.durationMultiplier[5_184_000] = 0.5

    self.creatorType[0] = "buyer"
    self.creatorType[1] = "taker"


@internal
def strikePrice(currentAssetPrice: decimal, _duration: uint256, _buySellType: String[4], _optionType: String[8]) -> decimal:
    duration_multiplier: decimal = 0.0
    option_type_multiplier: decimal = 0.0

    duration_multiplier = self.durationMultiplier[_duration] * currentAssetPrice
    
    if _optionType == "American":
        option_type_multiplier = 0.1 * currentAssetPrice
    else:
        option_type_multiplier = 0.4 * currentAssetPrice

    total_multiplier: decimal = duration_multiplier + option_type_multiplier

    return  total_multiplier


@external
@payable
def createOption(ownerType: uint256, _ticker: String[4], _duration: uint256, _buySellType: String[4], _optionType: String[8]):
    assert self.tokenToPrice[_ticker] > 0, "This token is not supported"
    assert _duration == 1_296_000 or _duration == 2_592_000 or _duration == 5_184_000, "That is not an accepted duration"
    
    current_market_price: decimal = convert(self.tokenToPrice[_ticker], decimal)
    current_strike_price: decimal = self.strikePrice(current_market_price, _duration, _buySellType, _optionType)

    account_risk_taker: address = ZERO_ADDRESS
    account_buyer: address = ZERO_ADDRESS

    if self.creatorType[ownerType] == "buyer":
        assert convert(msg.value, decimal) >= (current_strike_price * 10.0 * 1000000000000000000.0), "This is a big number"
        account_buyer = msg.sender
    elif self.creatorType[ownerType] == "taker":
        assert convert(msg.value, decimal) >= (current_market_price * 10.0 * 1000000000000000000.0), "You aren't sending enough to cover current market price times 100"
        account_risk_taker = msg.sender

    if _ticker == "CRV":
        self.curveOptions[self.curveCounter] = Option({
            optionId: self.curveCounter,
            owner: account_buyer,
            riskTaker: account_risk_taker,
            underlyingTokenTicker: _ticker,
            duration: _duration,
            buySellType: _buySellType,
            optionType: _optionType,
            strikePrice: current_strike_price,
            marketPrice: current_market_price,
            startTime: block.timestamp,
            purchased: False
        })
        self.sellerLedger[_ticker][self.curveCounter] = (current_market_price * 10.0)
        self.buyerLedger[_ticker][self.curveCounter] = (current_strike_price * 10.0)
        self.curveCounter += 1
    elif _ticker == "UNI":
        self.uniOptions[self.uniCounter] = Option({
            optionId: self.uniCounter,
            owner: account_buyer,
            riskTaker: account_risk_taker,
            underlyingTokenTicker: _ticker,
            duration: _duration,
            buySellType: _buySellType,
            optionType: _optionType,
            strikePrice: current_strike_price,
            marketPrice: current_market_price,
            startTime: block.timestamp,
            purchased: False
        })
        self.sellerLedger[_ticker][self.uniCounter] = (current_market_price * 10.0)
        self.buyerLedger[_ticker][self.uniCounter] = (current_strike_price * 10.0)
        self.uniCounter += 1
    else:
        self.compoundOptions[self.compoundCounter] = Option({
            optionId: self.compoundCounter,
            owner: account_buyer,
            riskTaker: account_risk_taker,
            underlyingTokenTicker: _ticker,
            duration: _duration,
            buySellType: _buySellType,
            optionType: _optionType,
            strikePrice: current_strike_price,
            marketPrice: current_market_price,
            startTime: block.timestamp,
            purchased: False
        })
        self.sellerLedger[_ticker][self.compoundCounter] = (current_market_price * 10.0)
        self.buyerLedger[_ticker][self.compoundCounter] = (current_strike_price * 10.0)
        self.compoundCounter += 1


@external
@payable
def buyOption(_optionId: uint256, _ticker: String[4]):
    if _ticker == "CRV":
        current_option: Option = self.curveOptions[_optionId]
        assert current_option.purchased == False, "This Curve option has already been purchased"

        if current_option.owner == ZERO_ADDRESS and current_option.riskTaker != ZERO_ADDRESS:
            assert convert(msg.value, decimal) >= (current_option.strikePrice * 10.0 * 1000000000000000000.0), "You don't have enough to purchase this Curve option"
            send(current_option.riskTaker, convert((current_option.strikePrice * 10.0 * 1000000000000000000.0), uint256))
            self.curveOptions[_optionId].owner = msg.sender
            self.curveOptions[_optionId].purchased = True
        elif current_option.riskTaker == ZERO_ADDRESS and current_option.owner != ZERO_ADDRESS:
            assert convert(msg.value, decimal) >= (current_option.marketPrice * 10.0 * 1_000_000_000_000_000_000.0), "You don't have enough to purchase this Curve option"
            self.curveOptions[_optionId].riskTaker = msg.sender
            self.curveOptions[_optionId].purchased = True
    elif _ticker == "UNI":
        current_option: Option = self.uniOptions[_optionId]
        assert current_option.purchased == False, "This Uniswap option has already been purchased"

        if current_option.owner == ZERO_ADDRESS and current_option.riskTaker != ZERO_ADDRESS:
            assert convert(msg.value, decimal) >= (current_option.strikePrice * 10.0 * 1000000000000000000.0), "You don't have enough to purchase this Uniswap option"
            send(current_option.riskTaker, convert((current_option.strikePrice * 10.0 * 1000000000000000000.0), uint256))
            self.uniOptions[_optionId].owner = msg.sender
            self.uniOptions[_optionId].purchased = True
        elif current_option.riskTaker == ZERO_ADDRESS and current_option.owner != ZERO_ADDRESS:
            assert convert(msg.value, decimal) >= (current_option.marketPrice * 10.0 * 1_000_000_000_000_000_000.0), "You don't have enough to purchase this Uniswap option"
            self.uniOptions[_optionId].riskTaker = msg.sender
            self.uniOptions[_optionId].purchased = True
    else:
        current_option: Option = self.compoundOptions[_optionId]
        assert current_option.purchased == False, "This Compound option has already been purchased"

        if current_option.owner == ZERO_ADDRESS and current_option.riskTaker != ZERO_ADDRESS:
            assert convert(msg.value, decimal) >= (current_option.strikePrice * 10.0 * 1000000000000000000.0), "You don't have enough to purchase this Compound option"
            send(current_option.riskTaker, convert((current_option.strikePrice * 10.0 * 1000000000000000000.0), uint256))
            self.compoundOptions[_optionId].owner = msg.sender
            self.compoundOptions[_optionId].purchased = True
        elif current_option.riskTaker == ZERO_ADDRESS and current_option.owner != ZERO_ADDRESS:
            assert convert(msg.value, decimal) >= (current_option.marketPrice * 10.0 * 1_000_000_000_000_000_000.0), "You don't have enough to purchase this Compound option"
            self.compoundOptions[_optionId].riskTaker = msg.sender
            self.compoundOptions[_optionId].purchased = True


@external
def sellPurchasedOption(_optionId: uint256, _ticker: String[4], _price: uint256):
    assert self.optionForSale[_ticker][_optionId] == 0, "This Option is already up for sale"
    if _ticker == "CRV":
        assert self.curveOptions[_optionId].owner == msg.sender, "You are not the owner of this Curve option"
        assert self.curveOptions[_optionId].purchased == True, "This option hasn't been purchased yet"
        self.optionForSale[_ticker][_optionId] = _price
    elif _ticker == "UNI":
        assert self.uniOptions[_optionId].owner == msg.sender, "You are not the owner of this Uniswap option"
        assert self.uniOptions[_optionId].purchased == True, "This option hasn't been puchased yet"
        self.optionForSale[_ticker][_optionId] = _price
    else:
        assert self.compoundOptions[_optionId].owner == msg.sender, "You are not the owner of this Compound option"
        assert self.compoundOptions[_optionId].purchased == True, "This option hasn't been purchased yet"
        self.optionForSale[_ticker][_optionId] = _price


@external
@payable
def buyPurchasedOption(_optionId: uint256, _ticker: String[4]):
    assert self.optionForSale[_ticker][_optionId] != 0, "Not for sale"
    assert msg.value >= (self.optionForSale[_ticker][_optionId] * 1_000_000_000_000_000_000), "Insufficient funds for purchase"
    if _ticker == "CRV":
        self.curveOptions[_optionId].owner = msg.sender
    elif _ticker == "UNI":
        self.curveOptions[_optionId].owner = msg.sender
    else:
        self.compoundOptions[_optionId].owner = msg.sender


@external
def cashOut(_ticker: String[4], _optionId: uint256):
    assert self.sellerLedger[_ticker][_optionId] != 0.0, "There is nothing to collect"
    current_option: Option = empty(Option)
    if _ticker == "CRV":
        current_option = self.curveOptions[_optionId]
    elif _ticker == "UNI":
        current_option = self.uniOptions[_optionId]
    else:
        current_option = self.compoundOptions[_optionId]

    assert current_option.riskTaker == msg.sender, "You are not the riskTaker of this option"
    assert (current_option.startTime + current_option.duration + 86400) <= block.timestamp, "Buyer still has time to call option"
    send(msg.sender, convert(self.sellerLedger[_ticker][_optionId], uint256))
    self.sellerLedger[_ticker][_optionId] = 0.0


@external
def callOption(_ticker: String[4], _optionId: uint256):
    assert self.sellerLedger[_ticker][_optionId] != 0.0, "Too late to call option"
    current_option: Option = empty(Option)
    if _ticker == "CRV":
        current_option = self.curveOptions[_optionId]
    elif _ticker == "UNI":
        current_option = self.uniOptions[_optionId]
    else:
        current_option = self.compoundOptions[_optionId]
    
    assert current_option.owner == msg.sender, "You are not the buyer of this option"
    assert current_option.purchased == True, "This option hasn't been purchased"
    assert (current_option.startTime + current_option.duration + 86400) > block.timestamp, "It's too late to call this option"

    if current_option.optionType == "European":
        assert (current_option.startTime + current_option.duration) < block.timestamp, "It's too early to call this European option"

    send(msg.sender, convert(self.sellerLedger[_ticker][_optionId], uint256))
    self.sellerLedger[_ticker][_optionId] = 0.0
    
    

@internal
def rebalanceStrikePrice(currentAssetPrice: decimal, start_time: uint256, duration: uint256, _optionType: String[8]) -> decimal:

    time_left: uint256 = (start_time + duration) - block.timestamp
    time_difference: decimal = 0.0
    new_time_percentage: decimal = 0.0
    new_time_multiplier: decimal = 0.0

    assert time_left > 0, "There's no time left for rebalancing, buy time has ended"

    if time_left > 2_592_000:
        time_difference = convert(time_left, decimal) - 2_592_000.0
        new_time_percentage = ((time_difference / 2_592_000.0) * 20.0) / 100.0 + 0.3
        new_time_multiplier = new_time_percentage * currentAssetPrice
    elif time_left > 1_296_000:
        time_difference = convert(time_left, decimal) - 1_296_000.0
        new_time_percentage = ((time_difference / 1_296_000.0) * 20.0) / 100.0 + 0.1
        new_time_multiplier = new_time_percentage * currentAssetPrice
    else:
        new_time_percentage = ((convert(time_left, decimal) / 1_296_000.0) * 10.0) / 100.0
        new_time_multiplier = new_time_percentage * currentAssetPrice

    option_type_multiplier: decimal = 0.0

    if _optionType == "American":
        option_type_multiplier = 0.1 * currentAssetPrice
    else:
        option_type_multiplier = 0.4 * currentAssetPrice

    total_multiplier: decimal = new_time_multiplier + option_type_multiplier

    return total_multiplier
    

@external
@payable
def rebalanceOption(_ticker:String[4], _optionId:uint256):
    assert self.sellerLedger[_ticker][_optionId] != 0.0, "This option does not exist"
    
    if _ticker == "CRV":
        current_option: Option = self.curveOptions[_optionId]
        current_token_price: decimal = convert(self.tokenToPrice[_ticker], decimal)
        new_strike_price: decimal = self.rebalanceStrikePrice(current_token_price,
                                                              current_option.startTime,
                                                              current_option.duration,
                                                              current_option.optionType
                                                              )
        assert current_option.purchased == False, "This option has been purchased already"
        if current_option.owner == ZERO_ADDRESS:
            assert current_option.riskTaker == msg.sender, "You are not the riskTaker of this option"
            balance_on_hold: decimal = self.sellerLedger[_ticker][_optionId]

            if current_token_price > current_option.marketPrice:
                assert convert(msg.value, decimal) >= ((current_token_price * 10.0) - balance_on_hold) * 1_000_000_000_000_000_000.0, "You aren't sending enough to cover for the price increase of token"
                
            elif current_token_price < current_option.marketPrice:
                send(msg.sender, convert((balance_on_hold - (current_token_price * 10.0)) * 1_000_000_000_000_000_000.0, uint256))

            self.sellerLedger[_ticker][_optionId] = current_token_price * 10.0
            self.curveOptions[_optionId].strikePrice = new_strike_price
            self.curveOptions[_optionId].marketPrice = current_token_price
        
        elif current_option.riskTaker == ZERO_ADDRESS:
            assert current_option.owner == msg.sender, "You are not the owner of this option"
            balance_on_hold: decimal = self.buyerLedger[_ticker][_optionId]

            if new_strike_price > current_option.strikePrice:
                assert convert(msg.value, decimal) >= ((new_strike_price * 10.0) - balance_on_hold) * 1_000_000_000_000_000_000.0, "You aren't sending enough to cover for the price increase of token"
            elif new_strike_price < current_option.strikePrice:
                send(msg.sender, convert((balance_on_hold - (new_strike_price * 10.0)) * 1_000_000_000_000_000_000.0, uint256))

            self.buyerLedger[_ticker][_optionId] = new_strike_price * 10.0
            self.curveOptions[_optionId].strikePrice = new_strike_price
            self.curveOptions[_optionId].marketPrice = current_token_price

    elif _ticker == "UNI":
        current_option: Option = self.uniOptions[_optionId]
        current_token_price: decimal = convert(self.tokenToPrice[_ticker], decimal)
        new_strike_price: decimal = self.rebalanceStrikePrice(current_token_price,
                                                              current_option.startTime,
                                                              current_option.duration,
                                                              current_option.optionType
                                                              )
        assert current_option.purchased == False, "This UNI option has been purchased already"
        if current_option.owner == ZERO_ADDRESS:
            assert current_option.riskTaker == msg.sender, "You are not the riskTaker of this UNI option"
            balance_on_hold: decimal = self.sellerLedger[_ticker][_optionId]

            if current_token_price > current_option.marketPrice:
                assert convert(msg.value, decimal) >= ((current_token_price * 10.0) - balance_on_hold) * 1_000_000_000_000_000_000.0, "You aren't sending enough to cover for the price increase of token"
                
            elif current_token_price < current_option.marketPrice:
                send(msg.sender, convert((balance_on_hold - (current_token_price * 10.0)) * 1_000_000_000_000_000_000.0, uint256))

            self.sellerLedger[_ticker][_optionId] = current_token_price * 10.0
            self.uniOptions[_optionId].strikePrice = new_strike_price
            self.uniOptions[_optionId].marketPrice = current_token_price
        
        elif current_option.riskTaker == ZERO_ADDRESS:
            assert current_option.owner == msg.sender, "You are not the owner of this UNI option"
            balance_on_hold: decimal = self.buyerLedger[_ticker][_optionId]

            if new_strike_price > current_option.strikePrice:
                assert convert(msg.value, decimal) >= ((new_strike_price * 10.0) - balance_on_hold) * 1_000_000_000_000_000_000.0, "You aren't sending enough to cover for the price increase of token"
            elif new_strike_price < current_option.strikePrice:
                send(msg.sender, convert((balance_on_hold - (new_strike_price * 10.0)) * 1_000_000_000_000_000_000.0, uint256))

            self.buyerLedger[_ticker][_optionId] = new_strike_price * 10.0
            self.uniOptions[_optionId].strikePrice = new_strike_price
            self.uniOptions[_optionId].marketPrice = current_token_price

    else:
        current_option: Option = self.compoundOptions[_optionId]
        current_token_price: decimal = convert(self.tokenToPrice[_ticker], decimal)
        new_strike_price: decimal = self.rebalanceStrikePrice(current_token_price,
                                                              current_option.startTime,
                                                              current_option.duration,
                                                              current_option.optionType
                                                              )
        assert current_option.purchased == False, "This COMP option has been purchased already"
        if current_option.owner == ZERO_ADDRESS:
            assert current_option.riskTaker == msg.sender, "You are not the riskTaker of this COMP option"
            balance_on_hold: decimal = self.sellerLedger[_ticker][_optionId]

            if current_token_price > current_option.marketPrice:
                assert convert(msg.value, decimal) >= ((current_token_price * 10.0) - balance_on_hold) * 1_000_000_000_000_000_000.0, "You aren't sending enough to cover for the price increase of token"
                
            elif current_token_price < current_option.marketPrice:
                send(msg.sender, convert((balance_on_hold - (current_token_price * 10.0)) * 1_000_000_000_000_000_000.0, uint256))

            self.sellerLedger[_ticker][_optionId] = current_token_price * 10.0
            self.compoundOptions[_optionId].strikePrice = new_strike_price
            self.compoundOptions[_optionId].marketPrice = current_token_price
        
        elif current_option.riskTaker == ZERO_ADDRESS:
            assert current_option.owner == msg.sender, "You are not the owner of this COMP option"
            balance_on_hold: decimal = self.buyerLedger[_ticker][_optionId]

            if new_strike_price > current_option.strikePrice:
                assert convert(msg.value, decimal) >= ((new_strike_price * 10.0) - balance_on_hold) * 1_000_000_000_000_000_000.0, "You aren't sending enough to cover for the price increase of token"
            elif new_strike_price < current_option.strikePrice:
                send(msg.sender, convert((balance_on_hold - (new_strike_price * 10.0)) * 1_000_000_000_000_000_000.0, uint256))

            self.buyerLedger[_ticker][_optionId] = new_strike_price * 10.0
            self.compoundOptions[_optionId].strikePrice = new_strike_price
            self.compoundOptions[_optionId].marketPrice = current_token_price
            

# @external
# @view
# def viewOptions(_ticker: String[4]):
#     if _ticker == "CRV":
#         for i in range(1_000):
#             if self.curveOptions[i] == empty(Option):
#                 break
            
#             self.curveOptions[i].marketPrice
