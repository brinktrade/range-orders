const tickToPrice = require('./tickToPrice')

async function getPriceFromTick(pool, tick) {
  const tkn0Address = await pool.token0()
  const tkn1Address = await pool.token1()
  const price = await tickToPrice(tkn0Address, tkn1Address, tick)
  return price.toSignificant(5)
}

module.exports = getPriceFromTick
