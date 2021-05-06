const { ethers } = require('hardhat')

const increaseTime = async t => {
  const r = await ethers.provider.send('evm_increaseTime', [t])
  return r
}

module.exports = increaseTime
