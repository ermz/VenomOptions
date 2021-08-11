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
    underlyingTokenTicker: String[4]
    ExpirationTime: uint256
    buySellType: String[4]
    optionType: String[8]
    price: uint256

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

@external
@payable
def createOption(_ticker: String[4], _duration: uint256, _buySellType: String[4], _optionType: String[8], _price: uint256):
    if _ticker == "CRV":
        assert msg.value >= (_price * 1_000_000_000_000_000_000)
        self.curveOptions[self.curveCounter] = Option({
            optionId: self.curveCounter,
            owner: msg.sender,
            underlyingTokenTicker: _ticker,
            ExpirationTime: _duration,
            buySellType: _buySellType,
            optionType: _optionType,
            price: _price
        })
        self.curveCounter += 1
    elif _ticker == "UNI":
        self.uniOptions[self.uniCounter] = Option({
            optionId: self.uniCounter,
            owner: msg.sender,
            underlyingTokenTicker: _ticker,
            ExpirationTime: _duration,
            buySellType: _buySellType,
            optionType: _optionType,
            price: _price
        })
        self.uniCounter += 1
    else:
        self.compoundOptions[self.compoundCounter] = Option({
            optionId: self.compoundCounter,
            owner: msg.sender,
            underlyingTokenTicker: _ticker,
            ExpirationTime: _duration,
            buySellType: _buySellType,
            optionType: _optionType,
            price: _price
        })
        self.compoundCounter += 1

@external
@payable
def buyOption(_optionId: uint256, _ticker: String[4]):
    if _ticker == "CRV":
        assert msg.value >= self.curveOptions[_optionId].price, "You don't have enough to purchase this Curve option"
        original_owner: Option = self.curveOptions[_optionId]
        send(original_owner.owner, original_owner.price)
        self.curveOptions[_optionId].owner = msg.sender
    elif _ticker == "UNI":
        assert msg.value >= self.uniOptions[_optionId].price, "You don't have enough to purchase this Uniswap option"
        original_owner: Option = self.curveOptions[_optionId]
        send(original_owner.owner, original_owner.price)
        self.uniOptions[_optionId].owner = msg.sender
    else:
        assert msg.value >= self.compoundOptions[_optionId].price, "You don't have enough to purchase this Compound option"
        original_owner: Option = self.curveOptions[_optionId]
        send(original_owner.owner, original_owner.price)
        self.compoundOptions[_optionId].owner = msg.sender

# @external
# @payable
