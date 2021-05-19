const _ = require('lodash')
const { ethers } = require('hardhat')
const { FeeAmount, nearestUsableTick } = require('@uniswap/v3-sdk')
const { expectRevert } = require('@openzeppelin/test-helpers')
const setup = require('./setup')
const increaseTime = require('./helpers/increaseTime')
const latestBlock = require('./helpers/latestBlock')
const { BN, BN6, BN9, BN18 } = require('./helpers/bignumber')
const awaitEvent = require('./helpers/awaitEvent')
const awaitEvents = require('./helpers/awaitEvents')
const { soliditySha3 } = require('web3-utils')
const { expect } = require('chai')

const abiCoder = ethers.utils.defaultAbiCoder

const bn_1m = BN(1).mul(BN6).mul(BN18)
const bn_3b = BN(3000).mul(BN6).mul(BN18)
const wethAmt = bn_1m
const aaaAmt = bn_3b

const DEFAULT_TICK_SPACING = 60
const DEFAULT_NEXT_TICK = 80040

describe('RangeOrdersPositionManager', function () {
  before(async function () {
    const UniswapV3Pool = await ethers.getContractFactory('UniswapV3Pool')
    console.log('POOL_INIT_CODE_HASH for PoolAddress.sol: ', soliditySha3(UniswapV3Pool.bytecode))

    this.logInfo = true
  })

  beforeEach(async function () {
    await setup.call(this)

    // setup WETH/AAA pool with some liquidity
    await this.createWethAAAPool(wethAmt, aaaAmt)
    await this.mintWethAAALiquidity({ wethAmount: wethAmt, tokenAmount: aaaAmt })

    const [signer0, owner1, owner2, resolver] = await ethers.getSigners()
    this.signer0 = signer0
    this.owner1 = owner1
    this.owner2 = owner2
    this.resolver = resolver

    if(this.logInfo) {
      console.log(`signer0: ${signer0.address}`)
      console.log(`owner1: ${owner1.address}`)
      console.log(`WETH: ${this.weth.address}`)
      console.log(`AAA: ${this.AAA.address}`)
      console.log(`owner2: ${owner2.address}`)
      console.log(`WETH-AAA-MEDIUM Pool: ${this.pools.WETH.AAA.MEDIUM.address}`)
      console.log(`nftPositionManager: ${this.nftPositionManager.address}`)
      console.log(`rangeOrderPool: ${this.rangeOrdersPositionManager.address}`)
      console.log()
      this.logInfo = false
    }

    const RangeOrdersPositionManager = await ethers.getContractFactory('RangeOrdersPositionManager')
    this.rangeOrdersPositionManager_owner1 = await RangeOrdersPositionManager.attach(this.rangeOrdersPositionManager.address).connect(this.owner1)
    this.rangeOrdersPositionManager_owner2 = await RangeOrdersPositionManager.attach(this.rangeOrdersPositionManager.address).connect(this.owner2)
    this.rangeOrdersPositionManager_resolver = await RangeOrdersPositionManager.attach(this.rangeOrdersPositionManager.address).connect(this.resolver)

    this.setupOrders = setupOrders.bind(this)
    this.resolveAllOrders = resolveAllOrders.bind(this)
    this.expectBalancesCleared = expectBalancesCleared.bind(this)
  })

  describe.only('createOrders()', function () {
    describe('when given ETH input orders and a valid range', function () {
      beforeEach(async function () {
        await this.setupOrders()
      })

      it('should add liquidity', async function () {
        const position = await this.rangeOrdersPositionManager.positions(this.positionHash)
        expect(position.liquidity.gt(0)).to.equal(true)
      })

      it('should increment owner liquidity', async function () {
        const position = await this.rangeOrdersPositionManager.positions(this.positionHash)
        const totalLiquidity = position.liquidity
        const owner1Liquidity = await this.rangeOrdersPositionManager.liquidityBalances(this.positionHash, this.owner1.address)
        const owner2Liquidity = await this.rangeOrdersPositionManager.liquidityBalances(this.positionHash, this.owner2.address)

        // add 1 for rounding err
        const expectedOwner1Liq = this.inputAmounts[0].mul(totalLiquidity).div(this.totalInputAmount).add(1)
        const expectedOwner2Liq = this.inputAmounts[1].mul(totalLiquidity).div(this.totalInputAmount)
        expect(expectedOwner1Liq.toString()).to.equal(owner1Liquidity.toString())
        expect(expectedOwner2Liq.toString()).to.equal(owner2Liquidity.toString())

        // check total liq
        expect(owner1Liquidity.add(owner2Liquidity).toString()).to.equal(totalLiquidity.toString())
      })
    })

    describe('when given an invalid range size', function () {
      it('should revert with BAD_RANGE_SIZE', async function () {
        // set the range to be 2 tick spaces instead of 1
        await expectRevert(this.setupOrders({
          tickLower: DEFAULT_NEXT_TICK + DEFAULT_TICK_SPACING,
          tickUpper: DEFAULT_NEXT_TICK + (DEFAULT_TICK_SPACING * 3)
        }), 'BAD_RANGE_SIZE')
      })
    })

    describe('when tokenIn is token0, and range is too low', function () {
      it('should revert with RANGE_TOO_LOW', async function () {
        await expectRevert(this.setupOrders({
          tickLower: DEFAULT_NEXT_TICK - DEFAULT_TICK_SPACING,
          tickUpper: DEFAULT_NEXT_TICK
        }), 'RANGE_TOO_LOW')
      })
    })

    describe('when tokenIn is token1, and range is too high', function () {
      it('should revert with RANGE_TOO_HIGH', async function () {
        await expectRevert(this.setupOrders({
          tokenIn: this.AAA,
          tokenOut: this.weth,
          tickLower: DEFAULT_NEXT_TICK + DEFAULT_TICK_SPACING,
          tickUpper: DEFAULT_NEXT_TICK + (DEFAULT_TICK_SPACING * 2)
        }), 'RANGE_TOO_HIGH')
      })
    })
  })

  describe('resolveOrders()', function () {
    describe('when range has been fully crossed', function () {
      beforeEach(async function () {
        await this.setupOrders()
        await this.tokenToEthSwap(this.signer0, this.AAA, BN(20000000).mul(BN18))
        this.AAAFees = BN('27250535821285555519')
      })
      describe('and 10% of auction time has passed', function () {
        beforeEach(async function () {
          await increaseTime(100)
        })
        it('should give resolver a 10% reward', async function () {
          const iResolverBal = await this.AAA.balanceOf(this.resolver.address)
          const iOwner1Bal = await this.AAA.balanceOf(this.owner1.address)
          const iOwner2Bal = await this.AAA.balanceOf(this.owner2.address)
          await this.resolveAllOrders()
          const fResolverBal = await this.AAA.balanceOf(this.resolver.address)
          const fOwner1Bal = await this.AAA.balanceOf(this.owner1.address)
          const fOwner2Bal = await this.AAA.balanceOf(this.owner2.address)
          const resolverTransfer = fResolverBal.sub(iResolverBal)/BN18
          const resolverReward = resolverTransfer - (this.AAAFees/BN18)
          const owner1Transfer = fOwner1Bal.sub(iOwner1Bal)/BN18
          const owner2Transfer = fOwner2Bal.sub(iOwner2Bal)/BN18
          const rewardPerc = resolverReward/(resolverReward+owner1Transfer+owner2Transfer)
          expect(rewardPerc - 0.1).to.be.greaterThan(-0.00000001)
          expect(rewardPerc - 0.1).to.be.lessThan(0.00000001)
        })

        it('should clear the position completely', async function () {
          await this.resolveAllOrders()
          const positionState = await this.nftPositionManager.positions(this.positionId)
          expect(positionState.liquidity.toNumber()).to.equal(0)
        })

        it('should clear all ETH and token balances from contracts', async function () {
          await this.resolveAllOrders()
          await this.expectBalancesCleared()
        })
      })
      describe('and auction time is exceeded', function () {
        beforeEach(async function () {
          await increaseTime(2000)
        })
        it('should give resolver 100% of the order output', async function () {
          const iResolverBal = await this.AAA.balanceOf(this.resolver.address)
          const iOwner1Bal = await this.AAA.balanceOf(this.owner1.address)
          const iOwner2Bal = await this.AAA.balanceOf(this.owner2.address)
          await this.resolveAllOrders()
          const fResolverBal = await this.AAA.balanceOf(this.resolver.address)
          const fOwner1Bal = await this.AAA.balanceOf(this.owner1.address)
          const fOwner2Bal = await this.AAA.balanceOf(this.owner2.address)
          const resolverTransfer = fResolverBal.sub(iResolverBal)
          const resolverReward = resolverTransfer.sub(this.AAAFees)
          const owner1Transfer = fOwner1Bal.sub(iOwner1Bal)
          const owner2Transfer = fOwner2Bal.sub(iOwner2Bal)
          const totalTransfer = resolverReward.add(owner1Transfer).add(owner2Transfer)
          expect(resolverReward.toString()).to.equal(totalTransfer.toString())
        })
        it('should clear all ETH and token balances from contracts', async function () {
          await this.resolveAllOrders()
          await this.expectBalancesCleared()
        })
      })
    })

    describe('when some fees have accrued within the range', function () {
      beforeEach(async function () {
        await this.setupOrders()
        // accrue fees in both tokens by swapping both ways in the range
        for (let i=0; i<5; i++) {
          await this.tokenToEthSwap(this.signer0, this.AAA, BN(2000000).mul(BN18))
          // console.log('TOKEN->ETH: ', (await this.pool.slot0()).tick)
        }
        for (let i=0; i<3; i++) {
          await this.ethToTokenSwap(this.signer0, this.AAA, BN(1000).mul(BN18))
          // console.log('ETH-TOKEN: ', (await this.pool.slot0()).tick)
        }
        for (let i=0; i<7; i++) {
          await this.tokenToEthSwap(this.signer0, this.AAA, BN(2000000).mul(BN18))
          // console.log('TOKEN->ETH: ', (await this.pool.slot0()).tick)
        }
      })
      it('should clear the position completely', async function () {
        await this.resolveAllOrders()
      })
      it('should clear all ETH and token balances from contracts', async function () {
        await this.resolveAllOrders()
        await this.expectBalancesCleared()
      })
    })

    describe('when tick is within the position range', function () {
      describe('when tokenIn is token0', function () {
        it('should revert with RANGE_TOO_HIGH', async function () {
          await this.setupOrders()
          // put the tick in the middle of the range
          await this.tokenToEthSwap(this.signer0, this.AAA, BN(7000000).mul(BN18))
          await this.resolveAllOrders()
          await expectRevert(this.txPromise, 'RANGE_TOO_HIGH')
        })
      })
      describe('when tokenIn is token1', function () {
        it('should revert with RANGE_TOO_LOW', async function () {
          await this.setupOrders({
            tokenIn: this.AAA,
            tokenOut: this.weth,
            tickLower: DEFAULT_NEXT_TICK - (DEFAULT_TICK_SPACING * 3),
            tickUpper: DEFAULT_NEXT_TICK - (DEFAULT_TICK_SPACING * 2),
          })
          // put the tick in the middle of the range
          await this.ethToTokenSwap(this.signer0, this.AAA, BN(10000).mul(BN18))
          await this.resolveAllOrders()
          await expectRevert(this.txPromise, 'RANGE_TOO_LOW')
        })
      })
    })
  })

  describe('withdraw()', function () {
    describe('when withdrawing 100%', function () {
      beforeEach(async function () {
        await this.setupOrders()

        this.owner1_iETHBalance = await ethers.provider.getBalance(this.owner1.address)
        const ownerLiquidity = await this.rangeOrdersPositionManager.liquidityBalances(this.positionHash, this.owner1.address)

        this.txPromise = this.rangeOrdersPositionManager_owner1.withdrawOrder([
          this.positionHash,
          this.weth.address,
          this.AAA.address,
          ownerLiquidity
        ])
      })

      // it('log gas', async function () {
      //   await logTxGas(await this.txPromise, 'withdraw()')
      // })

      it('should transfer funds back to owner', async function () {
        const evt = await awaitEvent(this.weth, 'Withdrawal')

        // WETH withdraw event check
        expect(evt.wad.toString()).to.equal(this.inputAmounts[0].toString())

        // ETH transfer check
        const tx = await evt._getTransaction()
        const ethCost = await getGasCost(tx)
        this.owner1_fETHBalance = await ethers.provider.getBalance(this.owner1.address)
        expect(this.owner1_fETHBalance.sub(this.owner1_iETHBalance).add(ethCost).toString()).to.equal(this.inputAmounts[0].toString())
      })
      it('should clear all ETH and token balances from contracts', async function () {
        await this.txPromise
        await this.expectBalancesCleared()
      })
    })

    describe('when withdrawing in the middle of the range', function () {
      beforeEach(async function () {
        await this.setupOrders()
        await this.tokenToEthSwap(this.signer0, this.AAA, BN(10000000).mul(BN18))
        const ownerLiquidity = await this.rangeOrdersPositionManager.liquidityBalances(this.positionHash, this.owner1.address)
        this.owner1_iETHBalance = await ethers.provider.getBalance(this.owner1.address)
        this.txPromise = this.rangeOrdersPositionManager_owner1.withdrawOrder([
          this.positionHash,
          this.weth.address,
          this.AAA.address,
          ownerLiquidity
        ])
      })

      it('should transfer ETH to the owner', async function () {
        await this.txPromise
        this.owner1_fETHBalance = await ethers.provider.getBalance(this.owner1.address)
        const ethAmt = this.owner1_fETHBalance.sub(this.owner1_iETHBalance)
        expect(ethAmt/BN18).to.be.greaterThan(0)
      })

      it('should transfer token to the owner', async function () {
        const eventResps = await awaitEvents([
          [this.AAA, 'Transfer'],
          [this.AAA, 'Transfer'],
          [this.AAA, 'Transfer'],
          [this.AAA, 'Transfer']
        ])
        const ownerAAATransferEvent = eventResps[3]
        expect(ownerAAATransferEvent.to).to.equal(this.owner1.address)
      })

      it('should clear all ETH and token balances from contracts', async function () {
        await this.txPromise
        await this.expectBalancesCleared()
      })
    })

    describe('when withdrawing after the range is crossed', function () {
      beforeEach(async function () {
        await this.setupOrders()
        await this.tokenToEthSwap(this.signer0, this.AAA, BN(20000000).mul(BN18))
        const ownerLiquidity = await this.rangeOrdersPositionManager.liquidityBalances(this.positionHash, this.owner1.address)
        this.txPromise = this.rangeOrdersPositionManager_owner1.withdrawOrder([
          this.positionHash,
          this.weth.address,
          this.AAA.address,
          ownerLiquidity
        ])
      })

      it('should transfer token to the owner', async function () {
        const eventResps = await awaitEvents([
          [this.AAA, 'Transfer'],
          [this.AAA, 'Transfer'],
          [this.AAA, 'Transfer'],
          [this.AAA, 'Transfer']
        ])
        const ownerTransferEvent = eventResps[3]
        expect(ownerTransferEvent.to).to.equal(this.owner1.address)
      })

      it('should clear all ETH and token balances from contracts', async function () {
        await this.txPromise
        await this.expectBalancesCleared()
      })
    })
  })
})

async function setupOrders (opts = {}) {
  const { tickLower, tickUpper, tokenIn, tokenOut } = opts
  this.pool = this.pools.WETH.AAA.MEDIUM
  this.tickSpacing = await this.pool.tickSpacing()
  const slot0 = await this.pool.slot0()
  this.initialTick = slot0.tick
  const nextTick = nearestUsableTick(this.initialTick, this.tickSpacing)
  this.rangeTickLower = tickLower || nextTick + this.tickSpacing
  this.rangeTickUpper = tickUpper || nextTick + (this.tickSpacing * 2)
  this.owners = [this.owner1.address, this.owner2.address]
  this.totalInputAmount = BN(3).mul(BN18)
  this.inputAmounts = [BN(1).mul(BN18), BN(2).mul(BN18)]

  this.tokenIn = tokenIn || this.weth
  this.tokenOut = tokenOut || this.AAA

  this.positionHash = soliditySha3(abiCoder.encode(
    ['address', 'address', 'uint24', 'int24', 'int24'],
    [this.tokenIn.address, this.tokenOut.address, FeeAmount.MEDIUM, this.rangeTickLower, this.rangeTickUpper]
  ))

  if (this.tokenIn.address !== this.weth.address) {
    // approve if tokenIn is ERC20
    await this.tokenIn.mint(this.signer0.address, this.totalInputAmount)
    await this.tokenIn.approve(this.rangeOrdersPositionManager.address, this.totalInputAmount)

    this.tx = await this.rangeOrdersPositionManager.createOrders([
      this.owners,
      this.inputAmounts,
      this.totalInputAmount,
      this.tokenIn.address,
      this.tokenOut.address,
      FeeAmount.MEDIUM,
      this.rangeTickLower,
      this.rangeTickUpper
    ])
  } else {
    // call directly as payable if tokenIn is WETH
    this.tx = await this.rangeOrdersPositionManager.createOrders([
      this.owners,
      this.inputAmounts,
      this.totalInputAmount,
      this.tokenIn.address,
      this.tokenOut.address,
      FeeAmount.MEDIUM,
      this.rangeTickLower,
      this.rangeTickUpper
    ], { value: this.totalInputAmount })
  }

  this.positionId = (await this.rangeOrdersPositionManager.positions(this.positionHash)).tokenId
}

async function resolveAllOrders () {
  const owner1Liq = await this.rangeOrdersPositionManager.liquidityBalances(this.positionHash, this.owner1.address)
  const owner2Liq = await this.rangeOrdersPositionManager.liquidityBalances(this.positionHash, this.owner2.address)

  this.txPromise = this.rangeOrdersPositionManager_resolver.resolveOrders([
    this.owners,
    this.tokenIn.address,
    this.tokenOut.address,
    FeeAmount.MEDIUM,
    this.rangeTickLower,
    this.rangeTickUpper,
    owner1Liq.add(owner2Liq),
    this.resolver.address
  ])
}

async function expectBalancesCleared () {
  const nftManagerETHBal = await ethers.provider.getBalance(this.nftPositionManager.address)
  const nftManagerAAABal = await this.AAA.balanceOf(this.nftPositionManager.address)
  const rangeOrderPoolETHBal = await ethers.provider.getBalance(this.rangeOrdersPositionManager.address)
  const rangeOrderPoolAAABal = await this.AAA.balanceOf(this.rangeOrdersPositionManager.address)
  expect(nftManagerETHBal.toNumber()).to.equal(0)
  expect(nftManagerAAABal.toNumber()).to.equal(0)
  expect(rangeOrderPoolETHBal.toNumber()).to.equal(0)
  expect(rangeOrderPoolAAABal.toNumber()).to.equal(0)
}

async function logTxGas (tx, msg) {
  const receipt = await ethers.provider.getTransactionReceipt(tx.hash)
  console.log(`${msg}: gasUsed: `, receipt.gasUsed.toString())
}

async function getGasCost (tx) {
  const receipt = await ethers.provider.getTransactionReceipt(tx.hash)
  return receipt.gasUsed.mul(tx.gasPrice)
}
