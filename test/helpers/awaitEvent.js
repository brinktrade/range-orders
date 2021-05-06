const _ = require('lodash')

const eventListenerResolves = {}

const awaitEvent = (contract, eventName) => new Promise(resolve => {
  const eventKey = `${contract.address}-${eventName}`
  if (!eventListenerResolves[eventKey]) {
    eventListenerResolves[eventKey] = []
  }
  eventListenerResolves[eventKey].push(resolve)

  if (eventListenerResolves[eventKey].length == 1) {
    contract.on(eventName, function () {
      let eventArgs
      for (let i in arguments) {
        if (arguments[i].args) {
          eventArgs = {
            ...arguments[i].args,
            _getTransaction: arguments[i].getTransaction,
            _getTransactionReceipt: arguments[i].getTransaction
          }
          break
        }
      }
      if (eventListenerResolves[eventKey].length > 0) {
        eventListenerResolves[eventKey][0](eventArgs)
        eventListenerResolves[eventKey] = _.drop(eventListenerResolves[eventKey])
      }
    })
  }
})

module.exports = awaitEvent
