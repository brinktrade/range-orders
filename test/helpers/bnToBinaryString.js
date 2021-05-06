const { toBN: web3BN } = require('web3-utils')

const bnToBinaryString = (bn) => web3BN(bn.toString()).toString(2)

module.exports = bnToBinaryString
