const { ethers } = require('hardhat')

const latestBlock = async () => {
  const blockNumber = await ethers.provider.getBlockNumber()
  const block = await ethers.provider.getBlock(blockNumber)
  return block
}

module.exports = latestBlock
