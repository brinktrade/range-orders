const web3Abi = require('web3-eth-abi')

function encodedFnSignature(functionName, paramTypes) {
  const types = paramTypes.map((t) => t == 'uint' ? 'uint256' : t)
  const fnSig = `${functionName}(${types.join(',')})`
  return web3Abi.encodeFunctionSignature(fnSig).slice(2)
}

module.exports = encodedFnSignature
