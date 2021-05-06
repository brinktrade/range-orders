const { BN } = require('../bignumber')
const { encodeSqrtRatioX96 } = require('@uniswap/v3-sdk')

const encodePriceSqrt = (r0, r1) => BN(encodeSqrtRatioX96(r0, r1).toString())

module.exports = encodePriceSqrt
