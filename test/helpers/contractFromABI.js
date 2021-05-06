const { setupLoader } = require('@openzeppelin/contract-loader')

module.exports = (abi, bytecode, { provider, defaultSender, defaultGas, defaultGasPrice, }) => {
  const loader = setupLoader({
    provider,
    defaultSender,
    defaultGas,
    defaultGasPrice
  })

  return loader.truffle.fromABI(abi, bytecode)
}
