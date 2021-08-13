# @version ^0.2.0

# Function needed
# Need to create option
# Need to buy option
# Need to compare option
# Needs a put and sell option difference
# Need American of European option difference
# Need a checker that will take in count (type ex. America, other type ex. Put, Price based on off-chain oracle)



struct Option:
    optionId: uint256
    owner: address
    riskTaker: address
    underlyingTokenTicker: String[4]
    duration: uint256
    buySellType: String[4]
    optionType: String[8]
    strikePrice: uint256
    marketPrice: uint256
    startTime: uint256
    purchased: bool

# Each option is worth 10 tokens. Regardless of type of option (sell/buy)
SHARES_PER_OPTION: constant(uint256) = 100

#Curve
curveOptions: HashMap[uint256, Option]
curveCounter: uint256

# Uniswap
uniOptions: HashMap[uint256, Option]
uniCounter: uint256

# Compound
compoundOptions: HashMap[uint256, Option]
compoundCounter: uint256

# Ticker to current price on market
tokenToPrice: HashMap[String[4], uint256]

# Time multiplier at the moment
durationMultiplier: HashMap[uint256, decimal]

# Amount being held from seller
# ticker(ex. "CRV") -> id(id of counter based on counter) -> amount(seller money)
# The seller(risk_taker) address will be saved on the Option struct itself
sellerLedger: HashMap[String[4], HashMap[uint256, uint256]]

# Amount a buyer who creates a Option pays
# Contract holds this amount momentarily until
# a seller(riskTaker) sends funds for option he agrees to,
# he'll then receive the buyers payment for taking risk immediately
# Ticker -> id -> amount
buyerLedger: HashMap[String[4], HashMap[uint256, uint256]]

# hold info of wether they are a riskTaker or buyer
creatorType: HashMap[uint256, String[5]]

# Purchased options that are up for sale
# Ticker -> option Id -> price
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

#Need a function that will return current price of token for option, Will return the difference owed on each Token
# Example if TokenA = 15 and the risk would be 18 per TokenA, then this function will return 3 (The difference b/t rick price and actual price)
@internal
def strikePrice(currentAssetPrice: uint256, _duration: uint256, _buySellType: String[4], _optionType: String[8]) -> uint256:
    duration_multiplier: uint256 = 0
    # Put or Sell option shouldn't really impact the strike price, atleast not to the smart contract
    # The smart contract has to receive the funds that were agreed upon
    # buy_sell_multiplier: uint256 = 0
    option_type_multiplier: uint256 = 0
    # Will include a volatility multiplier in the future when I integrate Coingecko, etc.
    # volatility_multiplier: uint256 = 0
    
    # Will return the addon for the current asset price based on duration of option
    duration_multiplier = convert(self.durationMultiplier[_duration], uint256) *currentAssetPrice
    
    # Wille return addon for option type based on whether it's an "American" or "European" option
    if _optionType == "American":
        option_type_multiplier = convert(0.1, uint256) * currentAssetPrice
    else:
        option_type_multiplier = convert(0.4, uint256) *currentAssetPrice

    total_multiplier: uint256 = duration_multiplier + option_type_multiplier

    return  total_multiplier

# Instead of having two different create option functions and two different buyOptions,
# It'll just be one for each, I'll have different checks depending on the scenario
@external
@payable
def createOption(ownerType: uint256, _ticker: String[4], _duration: uint256, _buySellType: String[4], _optionType: String[8]):
    assert self.tokenToPrice[_ticker] > 0, "This token is not supported"
    assert _duration == 1_296_000 or _duration == 2_592_000 or _duration == 5_184_000, "That is not an accepted starting time"
    
    #check to see if price sent is enough to cover for Option
    #They need to pay 100 * current_market_price
    current_market_price: uint256 = self.tokenToPrice[_ticker]
    current_strike_price: uint256 = self.strikePrice(current_market_price, _duration, _buySellType, _optionType)
    # The seller will be paying the amount of current_market_price * 100, they will receive the current_strike_price * 10,
    # when someone buys this option. If buyer doesn't exercise their buy option of buying this particular Token for
    # current_market_price a piece, Seller will receive all of their Tokens back

    account_risk_taker: address = ZERO_ADDRESS
    account_buyer: address = ZERO_ADDRESS

    if self.creatorType[ownerType] == "buyer":
        assert msg.value >= (current_strike_price * 100), "You're not sending enough to cover strike price time 100"
        account_buyer = msg.sender
    elif self.creatorType[ownerType] == "taker":
        assert msg.value >= (current_market_price * 100), "You aren't sending enough to cover current market price times 100"
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
        self.sellerLedger[_ticker][self.curveCounter] = (current_market_price * 100)
        self.buyerLedger[_ticker][self.curveCounter] = (current_strike_price * 100)
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
        self.sellerLedger[_ticker][self.uniCounter] = (current_market_price * 100)
        self.buyerLedger[_ticker][self.uniCounter] = (current_strike_price * 100)
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
        self.sellerLedger[_ticker][self.compoundCounter] = (current_market_price * 100)
        self.buyerLedger[_ticker][self.compoundCounter] = (current_strike_price * 100)
        self.compoundCounter += 1

@external
@payable
def buyOption(_optionId: uint256, _ticker: String[4]):
    if _ticker == "CRV":
        current_option: Option = self.curveOptions[_optionId]
        assert current_option.purchased == False, "This Curve option has already been purchased"
        # This if statment will check whether a buyer or riskTaker is making the purchase
        # If a buyer is purchasing the option, we will make sure they are supplying 100 times
        # the strike price when the Option was made. Then we will deposit that amount towards the 
        # riskTaker immediately.
        if current_option.owner == ZERO_ADDRESS and current_option.riskTaker != ZERO_ADDRESS:
            assert msg.value >= (current_option.strikePrice * 100), "You don't have enough to purchase this Curve option"
            # Send the risk taker his strike payment, that he receives regardless if buyer executes his option
            send(current_option.riskTaker, (current_option.strikePrice * 100))
            self.curveOptions[_optionId].owner = msg.sender
            self.curveOptions[_optionId].purchased = True
        elif current_option.riskTaker == ZERO_ADDRESS and current_option.owner != ZERO_ADDRESS:
            assert msg.value >= (current_option.marketPrice * 100), "You don't have enough to purchase this Curve option"
            self.curveOptions[_optionId].riskTaker = msg.sender
            self.curveOptions[_optionId].purchased = True
    elif _ticker == "UNI":
        current_option: Option = self.uniOptions[_optionId]
        assert current_option.purchased == False, "This Uniswap option has already been purchased"

        if current_option.owner == ZERO_ADDRESS and current_option.riskTaker != ZERO_ADDRESS:
            assert msg.value >= (current_option.strikePrice * 100), "You don't have enough to purchase this Uniswap option"
            send(current_option.riskTaker, (current_option.strikePrice * 100))
            self.uniOptions[_optionId].owner = msg.sender
            self.uniOptions[_optionId].purchased = True
        elif current_option.riskTaker == ZERO_ADDRESS and current_option.owner != ZERO_ADDRESS:
            assert msg.value >= (current_option.marketPrice * 100), "You don't have enough to purchase this Uniswap option"
            self.uniOptions[_optionId].riskTaker = msg.sender
            self.uniOptions[_optionId].purchased = True
    else:
        current_option: Option = self.compoundOptions[_optionId]
        assert current_option.purchased == False, "This Compound option has already been purchased"

        if current_option.owner == ZERO_ADDRESS and current_option.riskTaker != ZERO_ADDRESS:
            assert msg.value >= (current_option.strikePrice * 100), "You don't have enough to purchase this Compound option"
            send(current_option.riskTaker, (current_option.strikePrice * 100))
            self.compoundOptions[_optionId].owner = msg.sender
            self.compoundOptions[_optionId].purchased = True
        elif current_option.riskTaker == ZERO_ADDRESS and current_option.owner != ZERO_ADDRESS:
            assert msg.value >= (current_option.marketPrice * 100), "You don't have enough to purchase this Compound option"
            self.compoundOptions[_optionId].riskTaker = msg.sender
            self.compoundOptions[_optionId].purchased = True


# sellPurchasedOption
# A function that allows Options that have been purchase once already to be purchased by other users if they want
# Only avaialble once Option.purchased attribute is true
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

# buyPurchasedOption
# Also the opposite of this function of buying already bought options
# secondary market function 
@external
@payable
def buyPurchasedOption(_optionId: uint256, _ticker: String[4]):
    assert self.optionForSale[_ticker][_optionId] != 0, "Not for sale"
    assert msg.value >= self.optionForSale[_ticker][_optionId], "Insufficient funds for purchase"
    if _ticker == "CRV":
        self.curveOptions[_optionId].owner = msg.sender
    elif _ticker == "UNI":
        self.curveOptions[_optionId].owner = msg.sender
    else:
        self.compoundOptions[_optionId].owner = msg.sender


# cashOut
# After an Option time has ended and buyer has decided not to use option(1 day time)
# Seller can claim their money on hold back
# They would already have the strike payment
@external
def cashOut(_ticker: String[4], _optionId: uint256):
    assert self.sellerLedger[_ticker][_optionId] != 0, "There is nothing to collect"
    current_option: Option = empty(Option)
    if _ticker == "CRV":
        current_option = self.curveOptions[_optionId]
    elif _ticker == "UNI":
        current_option = self.uniOptions[_optionId]
    else:
        current_option = self.compoundOptions[_optionId]

    assert current_option.riskTaker == msg.sender, "You are not the riskTaker of this option"
    assert (current_option.startTime + current_option.duration + 86400) <= block.timestamp, "Buyer still has time to call option"
    send(msg.sender, self.sellerLedger[_ticker][_optionId])
    self.sellerLedger[_ticker][_optionId] = 0

# callOption
# buyer decides to exercise their option and purchase/sell tokens at price agreed on from riskTaker
# buyer will receive funds that are on hold from riskTaker
# buyer will also transfer corresponding tokens to riskTaker
@external
def callOption(_ticker: String[4], _optionId: uint256):
    assert self.sellerLedger[_ticker][_optionId] != 0, "Too late to call option"
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

    # If European model check that it can only be called once time has ended,
    # American option can be called anytime before elapsed time in general
    if current_option.optionType == "European":
        assert (current_option.startTime + current_option.duration) < block.timestamp, "It's too early to call this European option"

    send(msg.sender, self.sellerLedger[_ticker][_optionId])
    self.sellerLedger[_ticker][_optionId] = 0

    # Need to make up or find an actual interface I can make
    # Where the buyer sends 100 tokens that are specific to the ticker
    # mentioned above
    
    

@internal
def rebalanceStrikePrice(currentAssetPrice: uint256, start_time: uint256, duration: uint256, _optionType: String[8]) -> uint256:
    # original_duration_multiplier: uint256 = self.duration_multiplier[duration]
    
    time_left: uint256 = (start_time + duration) - block.timestamp
    time_difference: uint256 = 0
    new_time_percentage: uint256 = 0
    new_time_multiplier: uint256 = 0

    assert time_left > 0, "There's no time left for rebalancing, buy time has ended"

    if time_left > 2_592_000:
        time_difference = time_left - 2_592_000
        new_time_percentage = ((time_difference / 2_592_000) * 20) / 100 + convert(0.3, uint256)
        new_time_multiplier = new_time_percentage * currentAssetPrice
    elif time_left > 1_296_000:
        time_difference = time_left - 1_296_000
        new_time_percentage = ((time_difference / 1_296_000) * 20) / 100 + convert(0.1, uint256)
        new_time_multiplier = new_time_percentage * currentAssetPrice
    else:
        new_time_percentage = ((time_left / 1_296_000) * 10) / 100
        new_time_multiplier = new_time_percentage * currentAssetPrice

    option_type_multiplier: uint256 = 0

    if _optionType == "American":
        option_type_multiplier = convert(0.1, uint256) * currentAssetPrice
    else:
        option_type_multiplier = convert(0.4, uint256) * currentAssetPrice

    total_multiplier: uint256 = new_time_multiplier + option_type_multiplier

    return total_multiplier
    

@external
@payable
def rebalanceOption(_ticker:String[4], _optionId:uint256):
    assert self.sellerLedger[_ticker][_optionId] != 0, "This option does not exist"
    
    if _ticker == "CRV":
        current_option: Option = self.curveOptions[_optionId]
        current_token_price: uint256 = self.tokenToPrice[_ticker]
        new_strike_price: uint256 = self.rebalanceStrikePrice(current_token_price,
                                                              current_option.startTime,
                                                              current_option.duration,
                                                              current_option.optionType
                                                              )
        assert current_option.purchased == False, "This option has been purchased already"
        if current_option.owner == ZERO_ADDRESS:
            assert current_option.riskTaker == msg.sender, "You are not the riskTaker of this option"
            # balance_on_hold is for sellerLedger in this instance
            balance_on_hold: uint256 = self.sellerLedger[_ticker][_optionId]

            if current_token_price > current_option.marketPrice:
                # Then assert that seller is sending enough funds for change
                # Also change the strike price for when a buyer tries to purchase this option
                assert msg.value >= ((current_token_price * 100) - balance_on_hold), "You aren't sending enough to cover for the price increase of token"
                
            elif current_token_price < current_option.marketPrice:
                # Find the difference between balance on hold and how much the price has gone down,
                # Return the difference to the ristTaker
                send(msg.sender, (balance_on_hold - (current_token_price * 100)))

            self.sellerLedger[_ticker][_optionId] = current_token_price * 100
            self.curveOptions[_optionId].strikePrice = new_strike_price
            self.curveOptions[_optionId].marketPrice = current_token_price
        
        elif current_option.riskTaker == ZERO_ADDRESS:
            assert current_option.owner == msg.sender, "You are not the owner of this option"
            # balance_on_holde is specific to buyer ledger
            balance_on_hold: uint256 = self.buyerLedger[_ticker][_optionId]

            if new_strike_price > current_option.strikePrice:
                assert msg.value >= ((new_strike_price * 100) - balance_on_hold), "You aren't sending enough to cover for the price increase of token"
            elif new_strike_price < current_option.strikePrice:
                send(msg.sender, (balance_on_hold - (new_strike_price * 100)))

            self.buyerLedger[_ticker][_optionId] = new_strike_price * 100
            self.curveOptions[_optionId].strikePrice = new_strike_price
            self.curveOptions[_optionId].marketPrice = current_token_price

    elif _ticker == "UNI":
        current_option: Option = self.uniOptions[_optionId]
        current_token_price: uint256 = self.tokenToPrice[_ticker]
        new_strike_price: uint256 = self.rebalanceStrikePrice(current_token_price,
                                                              current_option.startTime,
                                                              current_option.duration,
                                                              current_option.optionType
                                                              )
        assert current_option.purchased == False, "This UNI option has been purchased already"
        if current_option.owner == ZERO_ADDRESS:
            assert current_option.riskTaker == msg.sender, "You are not the riskTaker of this UNI option"
            balance_on_hold: uint256 = self.sellerLedger[_ticker][_optionId]

            if current_token_price > current_option.marketPrice:
                assert msg.value >= ((current_token_price * 100) - balance_on_hold), "You aren't sending enough to cover for the price increase of token"
                
            elif current_token_price < current_option.marketPrice:
                send(msg.sender, (balance_on_hold - (current_token_price * 100)))

            self.sellerLedger[_ticker][_optionId] = current_token_price * 100
            self.uniOptions[_optionId].strikePrice = new_strike_price
            self.uniOptions[_optionId].marketPrice = current_token_price
        
        elif current_option.riskTaker == ZERO_ADDRESS:
            assert current_option.owner == msg.sender, "You are not the owner of this UNI option"
            balance_on_hold: uint256 = self.buyerLedger[_ticker][_optionId]

            if new_strike_price > current_option.strikePrice:
                assert msg.value >= ((new_strike_price * 100) - balance_on_hold), "You aren't sending enough to cover for the price increase of token"
            elif new_strike_price < current_option.strikePrice:
                send(msg.sender, (balance_on_hold - (new_strike_price * 100)))

            self.buyerLedger[_ticker][_optionId] = new_strike_price * 100
            self.uniOptions[_optionId].strikePrice = new_strike_price
            self.uniOptions[_optionId].marketPrice = current_token_price

    else:
        current_option: Option = self.compoundOptions[_optionId]
        current_token_price: uint256 = self.tokenToPrice[_ticker]
        new_strike_price: uint256 = self.rebalanceStrikePrice(current_token_price,
                                                              current_option.startTime,
                                                              current_option.duration,
                                                              current_option.optionType
                                                              )
        assert current_option.purchased == False, "This COMP option has been purchased already"
        if current_option.owner == ZERO_ADDRESS:
            assert current_option.riskTaker == msg.sender, "You are not the riskTaker of this COMP option"
            balance_on_hold: uint256 = self.sellerLedger[_ticker][_optionId]

            if current_token_price > current_option.marketPrice:
                assert msg.value >= ((current_token_price * 100) - balance_on_hold), "You aren't sending enough to cover for the price increase of token"
                
            elif current_token_price < current_option.marketPrice:
                send(msg.sender, (balance_on_hold - (current_token_price * 100)))

            self.sellerLedger[_ticker][_optionId] = current_token_price * 100
            self.compoundOptions[_optionId].strikePrice = new_strike_price
            self.compoundOptions[_optionId].marketPrice = current_token_price
        
        elif current_option.riskTaker == ZERO_ADDRESS:
            assert current_option.owner == msg.sender, "You are not the owner of this COMP option"
            balance_on_hold: uint256 = self.buyerLedger[_ticker][_optionId]

            if new_strike_price > current_option.strikePrice:
                assert msg.value >= ((new_strike_price * 100) - balance_on_hold), "You aren't sending enough to cover for the price increase of token"
            elif new_strike_price < current_option.strikePrice:
                send(msg.sender, (balance_on_hold - (new_strike_price * 100)))

            self.buyerLedger[_ticker][_optionId] = new_strike_price * 100
            self.compoundOptions[_optionId].strikePrice = new_strike_price
            self.compoundOptions[_optionId].marketPrice = current_token_price
            

@external
@view
def viewOptions(_ticker: String[4]):
    assert 1 == 1