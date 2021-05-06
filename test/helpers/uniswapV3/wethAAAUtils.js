async function createWethAAAPool (wethAmount, tokenAmount) {
  const tx = await this.createPool(this.weth.address, this.tokenA.address, 'WETH', 'AAA', 'MEDIUM', wethAmount, tokenAmount)
  return tx
}

async function mintWethAAALiquidity ({
  wethAmount,
  tokenAmount,
  tickLower,
  tickUpper,
  signer,
  recipient
}) {
  const res = await this.addLiquidity({
    token0Address: this.weth.address,
    token1Address: this.tokenA.address,
    feeName: 'MEDIUM',
    token0Amount: wethAmount,
    token1Amount: tokenAmount,
    tickLower,
    tickUpper,
    signer,
    recipient
  })
  return res
}

async function burnWethAAALiquidity (owner) {
  const signer = owner || this.signer0
  const tokenId = await this.nftPositionManager.tokenOfOwnerByIndex(signer.address, 0)
  const res = await this.removeLiquidity({
    pool: this.pools.WETH.AAA.MEDIUM,
    tokenId,
    owner: signer
  })
  return res
}

module.exports = {
  createWethAAAPool,
  mintWethAAALiquidity,
  burnWethAAALiquidity
}
