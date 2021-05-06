const getPriceFromTick = require('./getPriceFromTick')

async function getPriceFromCurrentTick(pool) {
  const slot0 = await pool.slot0()
  const price = await getPriceFromTick(pool, slot0.tick)
  return price
}

module.exports = getPriceFromCurrentTick
