// returns SDK Token instance by address
const { ethers } = require('hardhat')

const { ChainId, Price, Token } = require('@uniswap/sdk-core')

const getToken = async address => {
  const TestERC20 = await ethers.getContractFactory('TestERC20')
  const erc20 = await TestERC20.attach(address)
  const decimals = await erc20.decimals()
  return new Token(
    ChainId.MAINNET,
    address,
    decimals
  )
}

module.exports = getToken
