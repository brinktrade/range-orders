const fs = require('fs')
const path = require('path')
const { ethers } = require('hardhat')

module.exports = async () => {
  const [signer] = await ethers.getSigners()
  const filePath = path.join(__dirname, './WETH9.json')
  const { abi, bytecode } = JSON.parse(fs.readFileSync(filePath, 'utf8'))
  const weth9 = new ethers.ContractFactory(abi, bytecode, signer)
  return weth9
}
