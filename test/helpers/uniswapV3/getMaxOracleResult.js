const _ = require('lodash')

// calulate the maximum timespan for the observable slots. This is limited by
// the cardinality of the pool.
//
// Estimated maximum time for an oracle result = carindality * average block time?
// there can only be one observation per block and the max number of observables is
// equal to `cardinality`. Cardinality set to 10 at 30 second block times would give us
// about a 5 minute maximum oracle time over which to access the price/liquidity geomean
async function getMaxOracleResult (pool) {
  let result = {
    geomeanTick: 0,
    timespan: 0
  }
  const observations = await mapObservations(await this.getObservations(pool))
  if (observations.length <= 1) {
    return result
  } else {
    const o1 = observations[0]
    const o2 = observations[observations.length-1]
    const timespan = o2.time - o1.time
    const geomeanTick = (o2.tickCumulative - o1.tickCumulative) / timespan
    const geomeanLiq = (o2.liquidityCumulative - o1.liquidityCumulative) / timespan
    return { geomeanTick, geomeanLiq, timespan }
  }
}

// maps the pool.observations() array
function mapObservations (observations) {
  return _.sortBy(
    observations.map(o => ({
      time: o.blockTimestamp,
      tickCumulative: o.tickCumulative.toString(),
      liquidityCumulative: o.liquidityCumulative.toString()
    })),
    ['time']
  )
}

module.exports = getMaxOracleResult
