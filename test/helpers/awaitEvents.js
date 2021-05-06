const awaitEvent = require('./awaitEvent')

const awaitEvents = (events) => Promise.all(events.map(args => awaitEvent.apply(this, args)))

module.exports = awaitEvents
