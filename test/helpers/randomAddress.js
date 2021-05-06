const { ethers } = require('hardhat')

async function randomAddress () {
  const { address, privateKey } = await ethers.Wallet.createRandom()
  return { address, privateKey }
}

module.exports = randomAddress
