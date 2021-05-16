const _ = require('lodash')
const { ethers } = require('hardhat')
const weth9Contract = require('../weth9/weth9Contract')
const uniswapV3Helpers = require('./helpers/uniswapV3')
const { soliditySha3, randomHex } = require('web3-utils')

const abiCoder = ethers.utils.defaultAbiCoder

// makes the deployed WETH address relatively low (0x0ad413027a4794b2abffc4729602fbb2607ca46e)
const WETH_DEPLOY_SALT = '0x3404cb8734efa4dbe5db8b5caa6bf8a8d69a696ef0f49fca2a1d6755b7c9c82c'

async function setup () {
  const deployer = await ethers.getContractFactory('Deployer')
  this.deployer = await deployer.deploy()

  this.computeDeployedAddress = computeDeployedAddress.bind(this)
  this.deployContract = deployContract.bind(this)

  for(let prop in uniswapV3Helpers) {
    const fnOrObj = uniswapV3Helpers[prop]
    if (prop == 'wethAAAUtils') {
      for (let utilProp in fnOrObj) {
        this[utilProp] = fnOrObj[utilProp].bind(this)
      }
    } else {
      this[prop] = _.isFunction(fnOrObj) ? fnOrObj.bind(this) : fnOrObj
    }
  }

  const WETH9 = await weth9Contract()
  this.weth = await this.deployContract(WETH9, [], [], WETH_DEPLOY_SALT)

  const [signer0] = await ethers.getSigners()
  this.signer0 = signer0

  this.tokenA = await deployTokenGreaterThanWeth.call(this, 'Token A', 'AAA', 18)
  this.tokenB = await deployTokenGreaterThanWeth.call(this, 'Token B', 'BBB', 18)
  this.tokenC = await deployTokenGreaterThanWeth.call(this, 'Token C', 'CCC', 18)
  this.AAA = this.tokenA
  this.BBB = this.tokenB
  this.CCC = this.tokenC
  this.tokens = {}
  this.tokens[this.tokenA.address] = this.tokenA
  this.tokens[this.tokenB.address] = this.tokenB
  this.tokens[this.tokenC.address] = this.tokenC

  const UniswapV3Factory = await ethers.getContractFactory('UniswapV3Factory')
  this.uniswapV3Factory = await UniswapV3Factory.deploy()

  const SwapRouter = await ethers.getContractFactory('SwapRouter')
  this.swapRouter = await SwapRouter.deploy(this.uniswapV3Factory.address, this.weth.address)

  const NFTPositionDescriptor = await ethers.getContractFactory('NonfungibleTokenPositionDescriptor')
  this.nftPositionDescriptor = await NFTPositionDescriptor.deploy(this.weth.address)

  const NFTPositionManager = await ethers.getContractFactory('NonfungiblePositionManager')
  this.nftPositionManager = await NFTPositionManager.deploy(
    this.uniswapV3Factory.address, this.weth.address, this.nftPositionDescriptor.address
  )

  const resolveAuctionTimespan = 1000

  const RangeOrdersPositionManager = await ethers.getContractFactory('RangeOrdersPositionManager')
  this.rangeOrdersPositionManager = await RangeOrdersPositionManager.deploy(
    this.nftPositionManager.address,
    this.uniswapV3Factory.address,
    this.weth.address,
    resolveAuctionTimespan
  )
}

async function deployTokenGreaterThanWeth (name, symbol, decimals) {
  const TestERC20 = await ethers.getContractFactory('TestERC20')
  const paramTypes = ['string', 'string', 'uint8']
  const paramVals = [name, symbol, decimals]
  let tknAddr = 0
  let salt
  while (tknAddr < this.weth.address) {
    salt = randomHex(32)
    tknAddr = this.computeDeployedAddress(TestERC20, paramTypes, paramVals, salt)
  }
  const testERC20 = await this.deployContract(TestERC20, paramTypes, paramVals, salt)
  return testERC20
}

async function deployContract (contract, paramTypes, paramValues, salt) {
  const computedAddr = this.computeDeployedAddress(contract, paramTypes, paramValues, salt)
  const initParams = abiCoder.encode(paramTypes, paramValues).slice(2)
  const initCode = `${contract.bytecode}${initParams}`
  await this.deployer.deployContract(initCode, salt)
  const contractInstance = await contract.attach(computedAddr)
  return contractInstance
}

function computeDeployedAddress (contract, paramTypes, paramValues, salt) {
  const initParams = abiCoder.encode(paramTypes, paramValues).slice(2)
  const initCode = `${contract.bytecode}${initParams}`
  const codeHash = soliditySha3({ t: 'bytes', v: initCode })
  const addressAsBytes32 = soliditySha3(
    { t: 'uint8', v: 255 }, // 0xff
    { t: 'address', v: this.deployer.address },
    { t: 'bytes32', v: salt },
    { t: 'bytes32', v: codeHash }
  )
  const address = `0x${addressAsBytes32.slice(26,66)}`
  return address
}

module.exports = setup
