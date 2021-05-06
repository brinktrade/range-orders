async function getObservations (pool) {
  const observations = []
  let observation = { initialized: true }
  let i = 0
  while(observation.initialized) {
    observation = await pool.observations(i)
    observations.push(observation)
    i++
  }
  return observations.slice(0, observations.length-1)
}

module.exports = getObservations
