const { BN } = require('../bignumber')

const MaxUint128 = BN(2).pow(128).sub(1)

module.exports = MaxUint128
