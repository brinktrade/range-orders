const { FeeAmount } = require('@uniswap/v3-sdk')

async function ethToTokenSwap (recipient, tokenOut, amountIn) {
  const iTokenBal = await tokenOut.balanceOf(recipient.address)
  const tx = await this.exactInputSwap({
    recipient: recipient.address,
    tokenIn: this.weth.address,
    tokenOut: tokenOut.address,
    amountIn,
    fee: FeeAmount.MEDIUM
  })
  const fTokenBal = await tokenOut.balanceOf(recipient.address)
  return {
    tx,
    tokenOutAmount: fTokenBal.sub(iTokenBal)
  }
}

module.exports = ethToTokenSwap
