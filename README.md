# Range Order Pool for Uniswap V3

Uniswap V3 enables a new concept called "Range Orders". Range Orders can be created by minting an LP position with a very small range above or below the current price range for a pool. Because the position is outside of the active range, it is composed entirely of one asset. When the position's range is crossed, it is flipped to be composed entirely of the other asset, plus any fees that have been accrued in both assets. Range orders are a type of limit order where the limit price is set by the range at which the position is created.

These are a few challenges that range orders present:

  * If a range order is not exited after it is crossed, it could ne flipped back to the original asset if the price crosses back over the range
  * Users creating and exiting range orders directly on Uniswap V3 have to pay the gas cost for minting and burning individually owned LP NFT position.


## RangeOrderPool01 Smart Contract

Brink has created a smart contract to pool ownership of similar range orders [RangeOrderPool01.sol]. This smart contract only needs to mint one position for a given range and asset pair. Users add their individually owned orders to existing positions. Their orders can be resolved permissionlessly by any address, for a reward. This contract eliminates the need to manually monitor a range order position, and helps Range Orders behave more like normal limit orders.

The range order pool contract allows for the following:

  * Creation of range orders for any UniswapV3Pool instance.
  * Pooling of range orders with the same `tickLower` and `tickUpper` values in the same LP position. Each range order owner owns a portion of the position relative to their order size.
  * Batched creation of similar range orders in a single transaction.
  * Automated resolution of range orders that have been fully crossed.


### Order Direction

Orders on the range order pool are defined with a `tokenIn` and `tokenOut` address. Orders can only be added to positions that will be entirely composed of `tokenIn`. This means the range order position must be above or below the current price, depending on whether `tokenIn` is `token0` or `token1` in the corresponding `UniswapV3Pool`.


### Position Storage

Position data is stored in the range order pool contract by a unique hash: `sha3(tokenIn, tokenOut, fee, tickLower, tickUpper)`. Only one position will be minted for a given hash. The position will be reused by the contract indefinitely for orders that share the same paramters.


### Creating Orders

One or more orders can be created in a single transaction using the `createOrders()` function. The sender can create orders for any addresses. Creating a new order increases liquidity on an existing position, or mints a new position if it hasn't already been minted.


### Resolving Orders

Once a position's range has been fully crossed, liquidity added to the position using `createOrders()` can be resolved by calling the `resolveOrders()` function. This can be called by any sender for any resolvable position. The position's liquidity will be decreased and collected as `tokenOut`. Public resolution of orders is incentivized through an auction mechanism where the reward for resolution starts from 0 once the position becomes resolvable, and increases with `block.timestamp` until the position is fully resolved.

The `resolveOrders()` function calculates `resolvableSeconds`, the number of seconds since the position has been fully crossed. The range orders pool is deployed with a `resolveAuctionTimespan` value, which is the maximum timespan for the resolve auction. The resolver reward is calculated as `totalTokenOut * resolvableSeconds / resolveAuctionTimespan`.


### Accrued Fees

Even though range order positions have short ranges, fees can still accrue in both `tokenIn` and `tokenOut`. The range order pool distributes these fees to resolvers to further incentivize resolution. Accrued fees are distributed proportionaly to resolvers based on the amount of liquidity that is resolved relative to the total liquidity in a position.


### Withdrawing Orders

Orders can be withdrawn at any time by liquidity owners using the `withdrawOrder()` function. This function can only be called by a liquidity owner. It decreases liquidity on the owner's position, collects the assets owed, and transfers them to the owner. Any accrued fees from the position are left in the range order pool to incentivize resolution of other positions.
