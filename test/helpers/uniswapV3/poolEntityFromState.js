const { Pool } = require('@uniswap/v3-sdk')

async function poolEntityFromState (pool) {
  const tokenA = await this.getToken(await pool.token0())
  const tokenB = await this.getToken(await pool.token1())
  const fee = await pool.fee()
  const slot0 = await pool.slot0()
  const liquidity = await pool.liquidity()
  // ticks array isn't needed for position calculation,
  // but it will be needed for swap input/output calcs
  const ticks = []
  const poolEntity = new Pool(
    tokenA,
    tokenB,
    fee,
    slot0.sqrtPriceX96,
    liquidity,
    slot0.tick,
    ticks
  )
  return poolEntity
}

module.exports = poolEntityFromState
