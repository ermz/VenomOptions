import pytest
from brownie import accounts, options
import brownie

def test_create_option(_options, alice, bob):
    with brownie.reverts("This token is not supported"):
        _options.createOption(0, "GRV", 1_296_000, "buy", "American", {"from": bob})
    with brownie.reverts("That is not an accepted duration"):
        _options.createOption(0, "CRV", 1_234_567, "buy", "European", {"from": bob})
    with brownie.reverts("This is a big number"):
        _options.createOption(0, "CRV", 1_296_000, "buy", "American", {"from": bob, "value": "2 ether"})
    # with brownie.reverts("You're not sending enough to cover strike price time 100"):
    #     _options.createOption(0, "CRV", 1_296_000, "buy", "American", {"from": bob, "value": "10 ether"})
