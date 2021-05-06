const { tickToPrice: tickToPriceSDK } = require('@uniswap/v3-sdk')
const getToken = require('./getToken')

const tickToPrice = async (tokenAddress0, tokenAddress1, tick) => {
  const token0 = await getToken(tokenAddress0)
  const token1 = await getToken(tokenAddress1)
  const price = tickToPriceSDK(token0, token1, tick)
  return price
}

module.exports = tickToPrice
