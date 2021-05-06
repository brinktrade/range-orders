const { expect } = require('chai')
const { expectRevert } = require('@openzeppelin/test-helpers')
const { metaTxPromise, nextAvailableBit } = require('./metaTx')

function testMetaTxEndpoint ({ only, contract, method, paramTypes, conditions }) {
  const describeFn = only ? describe.only : describe

  for(const i in conditions) {
    const { only: innerOnly, describe: describeMsg, getSigner, unsignedParamsFn = () => {}, paramsFn = () => {}, value, testFn, testFnWithoutSend, expectRevert: expectRevertMsg } = conditions[i]
    const innerDescribeFn = innerOnly ? describe.only : describeFn
    innerDescribeFn(describeMsg, function () {
      // run tests
      if (testFn) {
        beforeEach(async function () {
          const { bitmapIndex, bit } = await nextAvailableBit(this[contract])
          this.bitmapIndex = bitmapIndex
          this.bit = bit
          const signer = await getSigner()
          const { promise, signedData } = await getFunctionCallPromise.call(this, signer)
          this.receipt = await promise
          this.signedData = signedData
        })
        testFn.call(this)
      } else if (testFnWithoutSend) {
        beforeEach(async function () {
          const { bitmapIndex, bit } = await nextAvailableBit(this[contract])
          this.bitmapIndex = bitmapIndex
          this.bit = bit
          const signer = await getSigner()
          this.txCall = getFunctionCallPromise.bind(this, signer)
        })
        testFnWithoutSend.call(this)
      }

      // run an expect revert test
      if (expectRevertMsg) {
        it('should revert', async function () {
          const { bitmapIndex, bit } = await nextAvailableBit(this[contract])
          this.bitmapIndex = bitmapIndex
          this.bit = bit
          const signer = await getSigner()
          const { promise } = await getFunctionCallPromise.call(this, signer)
          await expectRevert(promise, expectRevertMsg)
        })
      }

      async function getFunctionCallPromise (signer) {
        let args = {
          contract: this[contract],
          method,
          bitmapIndex: this.bitmapIndex,
          bit: this.bit,
          signer,
          unsignedParams: unsignedParamsFn.call(this),
          paramTypes,
          params: paramsFn.call(this),
          value
        }
        return metaTxPromise(args)
      }
    })
  }
}

module.exports = testMetaTxEndpoint
