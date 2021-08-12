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
SHARES_PER_OPTION: constant(uint256) = 10

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
    duration_multiplier = convert(self.durationMultiplier[_duration], uint256) * currentAssetPrice
    
    # Wille return addon for option type based on whether it's an "American" or "European" option
    if _optionType == "American":
        option_type_multiplier = convert(0.1, uint256) * currentAssetPrice
    else:
        option_type_multiplier = convert(0.4, uint256) * currentAssetPrice

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

# @external
# @payable
# def createOptionBuyer(_ticker: String[4], _duration: uint256, _buySellType: String[4], _optionType: String[8]):
#     assert self.tokenToPrice[_ticker] > 0, "This token is not supported"
#     assert _duration == 1_296_000 or _duration == 2_592_000 or _duration == 5_184_000, "That is not an accepted starting time"


# sellPurchasedOption
# A function that allows Options that have been purchase once already to be purchased by other users if they want
# Only avaialble once Option.purchased attribute is true

# buyPurchaseOption
# Also the opposite of this function of buying already bought options
# secondary market function 

# cashOut
# After an Option time has ended and buyer has decided not to use option
# Seller can claim their money on hold back
# They would already have the strike payment

# callOption
# buyer decides to exercise their option and purchase/sell tokens at price agreed on from riskTaker
# buyer will receive funds that are on hold from riskTaker
# buyer will also transfer corresponding tokens to riskTaker

# RebalanceOption
# Make your option go through marketPrice again to be more favorable
# Pay more or receive some back depending on current market
# Maybe give Option attribute regarding purchaseable time
