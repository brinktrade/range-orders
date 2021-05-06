const { FeeAmount } = require('@uniswap/v3-sdk')
const encodePriceSqrt = require('./encodePriceSqrt')

async function createPool(token0Address, token1Address, token0Name, token1Name, feeName, token0Amt, token1Amt) {
  const amt0 = token0Address < token1Address ? token0Amt : token1Amt
  const amt1 = token0Address < token1Address ? token1Amt : token0Amt
  const tkn0Addr = token0Address < token1Address ? token0Address : token1Address
  const tkn1Addr = token0Address < token1Address ? token1Address : token0Address

  // the UNI sdk's encodePriceSqrt() wants reserve1, reserve0 - assume because price is in terms of reserve1
  // as the "quote" currency
  const priceSqrt = encodePriceSqrt(amt1, amt0)

  const UniswapV3Pool = await ethers.getContractFactory('UniswapV3Pool')
  await this.nftPositionManager.createAndInitializePoolIfNecessary(
    tkn0Addr, tkn1Addr, FeeAmount[feeName], priceSqrt
  )
  const pool = await UniswapV3Pool.attach(
    await this.uniswapV3Factory.getPool(tkn0Addr, tkn1Addr, FeeAmount[feeName])
  )

  if (!this.pools) this.pools = {}
  if (!this.pools[token0Name]) this.pools[token0Name] = {}
  if (!this.pools[token1Name]) this.pools[token1Name] = {}
  if (!this.pools[token0Address]) this.pools[token0Address] = {}
  if (!this.pools[token1Address]) this.pools[token1Address] = {}

  if (!this.pools[token0Name][token1Name]) this.pools[token0Name][token1Name] = {}
  if (!this.pools[token1Name][token0Name]) this.pools[token1Name][token0Name] = {}
  if (!this.pools[token0Address][token1Address]) this.pools[token0Address][token1Address] = {}
  if (!this.pools[token1Address][token0Address]) this.pools[token1Address][token0Address] = {}

  // add by name
  this.pools[token0Name][token1Name][feeName] = pool
  this.pools[token1Name][token0Name][feeName] = pool

  // add by address
  this.pools[tkn0Addr][tkn1Addr][feeName] = pool
  this.pools[tkn1Addr][tkn0Addr][feeName] = pool
}

module.exports = createPool
