const encodedFnSignature = require('./encodedFnSignature')
const encodedParams = require('./encodedParams')

function encodeFunctionCall (functionName, paramTypes = [], params = []) {
  const encodedFnSig = encodedFnSignature(functionName, paramTypes)
  const callData = encodedParams(paramTypes, params)
  return `0x${encodedFnSig}${callData}`
}

module.exports = encodeFunctionCall
