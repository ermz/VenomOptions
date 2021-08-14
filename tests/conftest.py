import pytest
from brownie import accounts, options

@pytest.fixture()
def alice():
    return accounts[0]

@pytest.fixture()
def bob():
    return accounts[1]

@pytest.fixture()
def charles():
    return accounts[2]

@pytest.fixture()
def _options(alice):
    _option = options.deploy(3, 2, 4, {"from": alice})
    return _option