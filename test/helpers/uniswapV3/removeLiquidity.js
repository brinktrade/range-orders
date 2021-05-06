const { ethers } = require('hardhat')
const { BN, BN18 } = require('../../helpers/bignumber')

// 0x100000000000000000000000000000000 = 340282366920938500000000000000000000000
const Fixed128 = BN('340282366920938500000000000000000000000')

async function removeLiquidity ({
  pool,
  tokenId,
  owner
}) {
  const signer = owner || this.signer0

  const TestERC20 = await ethers.getContractFactory('TestERC20')
  const token0 = await TestERC20.attach(await pool.token0())
  const token1 = await TestERC20.attach(await pool.token1())
  const nftPositionManager = await positionManager.call(this, signer)

  let position = await nftPositionManager.positions(tokenId)
  const liquidity = position.liquidity

  // clear all liquidity in the position to calc amounts owed
  await nftPositionManager.decreaseLiquidity({
    tokenId,
    liquidity,
    amount0Min: 0,
    amount1Min: 0,
    deadline: this.MaxUint128
  })

  position = await nftPositionManager.positions(tokenId)
  const token0Fees = position.feeGrowthInside0LastX128.mul(liquidity).div(Fixed128)
  const token1Fees = position.feeGrowthInside1LastX128.mul(liquidity).div(Fixed128)
  console.log('token0 Fees: ', token0Fees/BN18)
  console.log('token1 Fees: ', token1Fees/BN18)
  console.log('token0: ', position.tokensOwed0.sub(token0Fees)/BN18)
  console.log('token1: ', position.tokensOwed1.sub(token1Fees)/BN18)

  // collect tokens owed
  const { token0Out, token1Out } = await collect.call(this, tokenId, token0, token1, signer)

  position = await nftPositionManager.positions(tokenId)

  // burn the NFT position
  await nftPositionManager.burn(tokenId)

  return {
    token0Out,
    token1Out
  }
}

async function collect (tokenId, token0, token1, signer) {
  const iTkn0Bal = await token0.balanceOf(signer.address)
  const iTkn1Bal = await token1.balanceOf(signer.address)
  const nftPositionManager = await positionManager.call(this, signer)
  await nftPositionManager.collect({
    tokenId,
    recipient: signer.address,
    amount0Max: this.MaxUint128,
    amount1Max: this.MaxUint128
  })
  const fTkn0Bal = await token0.balanceOf(signer.address)
  const fTkn1Bal = await token1.balanceOf(signer.address)
  return {
    token0Out: fTkn0Bal.sub(iTkn0Bal),
    token1Out: fTkn1Bal.sub(iTkn1Bal)
  }
}

async function positionManager (signer) {
  const NonfungiblePositionManager = await ethers.getContractFactory('NonfungiblePositionManager')
  const nftPositionManager = await NonfungiblePositionManager.attach(this.nftPositionManager.address).connect(signer)
  return nftPositionManager
}

module.exports = removeLiquidity
