const { ethers } = require('hardhat')
const { FeeAmount, Position } = require('@uniswap/v3-sdk')
const { getMinTick, getMaxTick } = require('./ticks')
const { BN, BN18 } = require('../bignumber')

async function addLiquidity({
  token0Address,
  token1Address,
  feeName,
  token0Amount,
  token1Amount,
  tickLower,
  tickUpper,
  signer: _signer,
  recipient
}) {
  const signer = _signer || this.signer0

  let amt0 = token0Address < token1Address ? token0Amount : token1Amount
  let amt1 = token0Address < token1Address ? token1Amount : token0Amount
  const tkn0Addr = token0Address < token1Address ? token0Address : token1Address
  const tkn1Addr = token0Address < token1Address ? token1Address : token0Address

  const pool = this.pools[tkn0Addr][tkn1Addr][feeName]
  if (!pool) throw new Error(`No pool found for ${tkn0Addr}-${tkn1Addr}`)

  if (!amt0) {
    const position = Position.fromAmount1({
      pool: await this.poolEntityFromState(pool),
      tickUpper,
      tickLower,
      amount1: amt1
    })
    amt0 = BN(position.amount0.raw.toString())
  } else if (!amt1) {
    const position = Position.fromAmount0({
      pool: await this.poolEntityFromState(pool),
      tickUpper,
      tickLower,
      amount0: amt0
    })
    amt1 = BN(position.amount1.raw.toString())
  }

  let ethPayableAmount
  let tkn0IsERC20, tkn1IsERC20
  if (tkn0Addr == this.weth.address) {
    ethPayableAmount = amt0
    tkn1IsERC20 = true
  } else if (tkn1Addr == this.weth.address) {
    ethPayableAmount = amt1
    tkn0IsERC20 = true
  } else {
    tkn0IsERC20 = true
    tkn1IsERC20 = true
  }

  const TestERC20 = await ethers.getContractFactory('TestERC20')

  if (tkn0IsERC20) {
    const tkn0 = await TestERC20.attach(this.tokens[tkn0Addr].address).connect(signer)
    await tkn0.mint(signer.address, amt0)
    await tkn0.approve(this.nftPositionManager.address, amt0)
  }

  if (tkn1IsERC20) {
    const tkn1 = await TestERC20.attach(this.tokens[tkn1Addr].address).connect(signer)
    await tkn1.mint(signer.address, amt1)
    await tkn1.approve(this.nftPositionManager.address, amt1)
  }

  const tickSpacing = await pool.tickSpacing()

  const NonfungiblePositionManager = await ethers.getContractFactory('NonfungiblePositionManager')
  const nftPositionManager = await NonfungiblePositionManager.attach(this.nftPositionManager.address).connect(signer)

  nftPositionManager.mint({
    token0: tkn0Addr,
    token1: tkn1Addr,
    tickLower: tickLower || getMinTick(tickSpacing),
    tickUpper: tickUpper || getMaxTick(tickSpacing),
    fee: FeeAmount[feeName],
    recipient: recipient || signer.address,
    amount0Desired: amt0,
    amount1Desired: amt1,
    amount0Min: 0,
    amount1Min: 0,
    deadline: this.MaxUint128,
  }, { value: ethPayableAmount || 0 })
  const { tokenId } = await new Promise(resolve => nftPositionManager.on('Transfer', (from, to, tokenId) => resolve({ from, to, tokenId })))

  return { amount0: amt0, amount1: amt1, tokenId }
}

module.exports = addLiquidity
