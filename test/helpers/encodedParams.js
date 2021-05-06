const web3Abi = require('web3-eth-abi')

function encodedParams (paramTypes = [], params = []) {
  const types = paramTypes.map((t) => t == 'uint' ? 'uint256' : t)
  return web3Abi.encodeParameters(types, params).slice(2)
}

module.exports = encodedParams
