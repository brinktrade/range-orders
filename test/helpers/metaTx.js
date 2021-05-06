const _ = require('lodash')
const { ethers } = require('hardhat')
const { padLeft } = require('web3-utils')
const bnToBinaryString = require('./bnToBinaryString')
const BN = ethers.BigNumber.from

const signMetaTx = async ({
  contract,
  method,
  bitmapIndex,
  bit,
  signer,
  paramTypes = [],
  params = []
}) => {
  const typedData = getTypedData(contract.address, method, bitmapIndex, bit, paramTypes, params)
  const signature = await signTypedData(signer, typedData)
  return { bitmapIndex, bit, typedData, to: contract.address, method, signature, signer, params }
}

const metaTxPromise = async ({
  contract,
  method,
  bitmapIndex,
  bit,
  signer,
  unsignedParams = [],
  paramTypes = [],
  params = [],
  value = 0
}) => {
  const signedData = await signMetaTx({
    contract,
    method,
    bitmapIndex,
    bit,
    signer,
    paramTypes,
    params
  })
  let opts = { value }
  const promise = contract[method].apply(this, [
    signedData.bitmapIndex,
    signedData.bit,
    ...signedData.params,
    signedData.signature,
    ...unsignedParams,
    opts
  ])
  return { promise, signedData }
}

const metaTxPromiseWithSignedData = ({
  contract,
  unsignedParams = [],
  value = 0,
  signedData,
}) => {
  let opts = { value }
  const promise = contract[signedData.method].apply(this, [
    signedData.bitmapIndex,
    signedData.bit,
    ...signedData.params,
    signedData.signature,
    ...unsignedParams,
    opts
  ])
  return { promise, signedData }
}

const execMetaTx = async ({
  contract,
  method,
  bitmapIndex,
  bit,
  signer,
  unsignedParams = [],
  paramTypes = [],
  params = [],
  value
}) => {
  const { promise, signedData } = await metaTxPromise({
    contract,
    method, 
    bitmapIndex,
    bit,
    signer,
    unsignedParams,
    paramTypes,
    params,
    value
  })
  const receipt = await promise
  return { receipt, signedData }
}

async function nextAvailableBit (contract) {
  let curBitmap, curBitmapBinStr
  let curBitmapIndex = -1
  let nextBitIndex = -1
  while(nextBitIndex < 0) {
    curBitmapIndex++
    curBitmap = await contract.getReplayProtectionBitmap(curBitmapIndex)
    curBitmapBinStr = reverseStr(padLeft(bnToBinaryString(curBitmap), 256, '0'))
    for (let i = 0; i < curBitmapBinStr.length; i++) {
      if (curBitmapBinStr.charAt(i) == '0') {
        nextBitIndex = i
        break
      }
    }
  }
  return {
    bitmapIndex: BN(curBitmapIndex),
    bit: BN(2).pow(BN(nextBitIndex))
  }
}

function reverseStr (str) {
  return str.split("").reverse().join("")
}

async function signTypedData(signer, typedData) {
  const signedData = await signer._signTypedData(
    typedData.domain,
    typedData.types,
    typedData.value
  )
  return signedData
}

// get typed data object for EIP712 signature
function getTypedData(verifyingContract, method, bitmapIndex, bit, paramTypes, params) {
  const methodType = capitalize(method)
  let typedData = {
    types: {
      [`${methodType}`]: [
        { name: "bitmapIndex", type: "uint256" },
        { name: "bit", type: "uint256" },
        ...paramTypes
      ]
    },
    domain: {
      name: "BrinkAccount",
      version: "1",
      chainId: 1,
      verifyingContract
    },
    value: {
      bitmapIndex: bitmapIndex.toString(),
      bit: bit.toString()
    }
  }
  for (var i in paramTypes) {
    const { name } = paramTypes[i]
    const paramValue = params[i]
    if (_.isUndefined(paramValue)) throw new Error(`No value for param ${name}`)
    typedData.value[name] = paramValue.toString()
  }
  return typedData
}

const capitalize = (s) => {
  if (typeof s !== 'string') return ''
  return s.charAt(0).toUpperCase() + s.slice(1)
}

module.exports = {
  signMetaTx,
  metaTxPromise,
  metaTxPromiseWithSignedData,
  execMetaTx,
  nextAvailableBit
}
