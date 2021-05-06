const { ethers } = require('hardhat')
const encodePath = require('./encodePath')

// using exactInput which supports indirect token paths,
// but could use exactInputSingle for a direct token pair

async function exactInputSwap({
  tokenIn,
  tokenOut,
  amountIn,
  recipient,
  fee,
  deadline = this.MaxUint128,
  amountOutMinimum = 0
}) {
  const signer0 = (await ethers.getSigners())[0]

  const inputIsWETH = this.weth.address == tokenIn
  const outputIsWETH = this.weth.address == tokenOut 
  const value = inputIsWETH ? amountIn : 0

  if (!inputIsWETH) {
    const TestERC20 = await ethers.getContractFactory('TestERC20')
    const token = await TestERC20.attach(tokenIn).connect(signer0)
    await token.mint(signer0.address, amountIn)
    await token.approve(this.swapRouter.address, amountIn)
  }

  // if output is WETH, send the weth from pool to the router. have the
  // router unwrap and send to the recipient by calling unwrapWETH9() after
  // the exactInput() call, using multicall()

  const params = {
    path: encodePath([tokenIn, tokenOut], fee),
    recipient: outputIsWETH ? this.swapRouter.address : recipient,
    deadline,
    amountIn,
    amountOutMinimum
  }

  const data = [this.swapRouter.interface.encodeFunctionData('exactInput', [params])]
  if (outputIsWETH) {
    data.push(this.swapRouter.interface.encodeFunctionData('unwrapWETH9', [amountOutMinimum, recipient]))
  }

  const SwapRouter = await ethers.getContractFactory('SwapRouter')
  const swapRouter = SwapRouter.attach(this.swapRouter.address).connect(signer0)
  const tx = outputIsWETH ?
    await swapRouter.multicall(data, { value }) :
    await swapRouter.exactInput(params, { value })
  return tx
}

module.exports = exactInputSwap
