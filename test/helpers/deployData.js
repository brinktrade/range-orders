const web3Utils = require('web3-utils')
const ethJsAbi = require('ethereumjs-abi')
const { bufferToHex } = require('ethereumjs-util')

const deployData = (deployerAddress, proxyBytecode, implementationAddress, ownerAddress, chainId, accountDeploymentSalt) => {
  const initCode = computeAccountBytecode(proxyBytecode, implementationAddress, ownerAddress, chainId)
  const codeHash = web3Utils.soliditySha3({ t: 'bytes', v: initCode })
  const addressAsBytes32 = web3Utils.soliditySha3(
    { t: 'uint8', v: 255 }, // 0xff
    { t: 'address', v: deployerAddress },
    { t: 'bytes32', v: accountDeploymentSalt },
    { t: 'bytes32', v: codeHash }
  )
  const address = `0x${addressAsBytes32.slice(26,66)}`
  return {
    address,
    initCode
  }
}

const computeAccountBytecode = (proxyBytecode, implementationAddress, ownerAddress, chainId) => {
  const encodedParameters = bufferToHex(
    ethJsAbi.rawEncode(
      ['address', 'address', 'uint256'],
      [implementationAddress, ownerAddress, chainId]
    )
  ).replace('0x', '')
  return `${proxyBytecode}${encodedParameters}`
}

module.exports = deployData