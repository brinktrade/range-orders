const { FeeAmount } = require('@uniswap/v3-sdk')

async function tokenToEthSwap (recipient, tokenIn, amountIn) {
  const iEthBal = await ethers.provider.getBalance(recipient.address)
  const tx = await this.exactInputSwap({
    recipient: recipient.address,
    tokenIn: tokenIn.address,
    tokenOut: this.weth.address,
    amountIn,
    fee: FeeAmount.MEDIUM
  })
  const fEthBal = await ethers.provider.getBalance(recipient.address)
  return {
    tx,
    ethOutAmount: fEthBal.sub(iEthBal)
  }
}

module.exports = tokenToEthSwap
