# Uniswap V3 Range Order Positions

Uniswap V3 enables a new concept called "Range Orders". Range Orders can be created by minting an LP position with highly concentrated liquidity outside of the current price range for a pool. Because the position is outside of the active range, it is composed entirely of one asset. When the position's range is crossed, it is flipped to be composed entirely of the other asset, plus any accrued fees. Range orders function like limit orders, where the limit price is set by the range at which the position is created.

While it is possible to create range orders with the current Uniswap V3 core and periphery contracts, there are some challenges presented for owners of these positions:

  * Range orders don't behave like traditional limit orders. If a range order LP position is not liquidated after it is crossed, it can be flipped back to the original asset if the price crosses back over the range.
  * Users minting and burning range orders through the NonfungiblePositionManager have to pay the gas cost for minting and burning individually owned LP NFT positions.
  * Owners have to manually liquidate their range order positions after the range is crossed, which means they have to actively manage their position by watching the pool price.


## RangeOrderPositionManager Contract

[RangeOrderPositionManager.sol](https://github.com/brinktrade/range-orders/blob/master/contracts/RangeOrderPositionManager.sol) is a Uniswap V3 LP position manager contract that is designed to handle range orders. It is a canonical contract that supports creation and liquidation of range order positions for any UniswapV3Pool.

This contract allows liquidity for range orders to be increased, decreased, liquidated, and resolved.

### Range Order Positions

Range order positions have the following attributes:

  * `tokenIn`: The input token for the range order
  * `tokenOut`: The output token for the range order
  * `fee`: The fee amount for the UniswapV3Pool where liquidity for the position will be minted
  * `tickLower`: The lower bound of the range. This is the outer bound if `tokenIn` equals `token0` on UniswapV3Pool
  * `tickUpper`: The upper bound of the range. This is the outer bound if `tokenOut` equals `token0` on UniswapV3Pool
  * `positionHash`: `keccak256(tokenIn, tokenOut, fee, tickLower, tickUpper)`. Unique identifier for similar positions.
  * `positionIndex`: Increments from `0` for positions with the same `positionHash` value, when the previous position is liquidated.

Range order position size must be equal to 1 tick space for the given fee pool.

#### Position States

A range order position will always be in one of the following states, depending on the pool's current tick state relative to the position's `tickUpper` and `tickLower` values. Note that either `tickLower` or `tickUpper` could be the outer or inner bound for a range, depending on whether `tokenIn` or `tokenOut` is equal to `token0` on UniswapV3Pool.

  * Open: The current tick has not crossed the inner bound of the range. Owner liquidity can be added or removed.
  * Partial: The current tick has crossed the inner bound of the range, but has not crossed the outer bound. Owner liquidity cannot be added, but can be removed.
  * Filled: The current tick has crossed the outer bound of the range. Owner liquidity cannot be added or removed until the position is liquidated.
  * Liquidated: All liquidity for a position has been burned on the UniswapV3Pool and collected. Only filled positions can be liquidated. Owner liquidity for a liquidated position can be resolved to individual owners.

#### Increasing Liquidity

Liquidity for an owner address can be increased on open positions. Any address can add liquidity for any owner, as long as enough `tokenIn` is provided for the liquidity to be minted.

#### Decreasing Liquidity

Liquidity can by decreased for an owner address on open or partial positions. Only the owner address can decrease their liquidity. If the position is open, `tokenIn` will be transferred to the owner. If the position is partial, a combination of `tokenIn` and `tokenOut` will be transferred to the owner. This effectively cancels a range order fully or partially.

#### Liquidating a Position

When a position is filled, it needs to be liquidated before owners can collect their `tokenOut`. Liquidating a position burns all of the position liquidity on the UniswapV3Pool and collects the `tokenOut` to the `RangeOrderPositionManager` contract. Any address can liquidate any filled position that hasn't already been liquidated. As a reward, the liquidator receives all fees that have accrued in the position.

#### Resolving Liquidity

When a position has been liquidated, all liquidity for the position has been burned and consists entirely of `tokenOut` held in the `RangeOrderPositionManager` contract. Any address can resolve the position for an owner, which transfers `tokenOut` from `RangeOrderPositionManager` to the owner address. The amount of `tokenOut` transferred is proportional to the owner address's liquidity ownership for the position.

### External Endpoints

#### increaseLiquidity(IncreaseLiquidityParams calldata params)

Increases liquidity for a single owner on the position with latest `positionIndex`.

Takes the following struct as a parameter:

```
  struct IncreaseLiquidityParams {
    address owner;        // owner address
    uint256 inputAmount;  // amount of tokenIn provided
    address tokenIn;      // tokenIn address
    address tokenOut;     // tokenOut address
    uint24 fee;           // fee amount for UniswapV3Pool
    int24 tickLower;      // tickLower for the range
    int24 tickUpper;      // tickUpper for the range
  }
```

#### increaseLiquidityMulti(IncreaseLiquidityMultiParams calldata params)

Increases liquidity for multiple owners on the position with latest `positionIndex`.

Takes the following struct as a paramter:

```
  struct IncreaseLiquidityMultiParams {
    address[] owners;           // array of owner addresses
    uint256[] inputAmounts;     // array for tokenIn amounts for each owner
    uint256 totalInputAmount;   // total tokenIn amount
    address tokenIn;            // tokenIn address
    address tokenOut;           // tokenOut address
    uint24 fee;                 // fee amount for UniswapV3Pool
    int24 tickLower;            // tickLower for the range
    int24 tickUpper;            // tickUpper for the range
  }
```

#### decreaseLiquidity(DecreaseLiquidityParams calldata params)

Decreases liquidity for an owner.

Takes the following struct as a parameter:

```
  struct DecreaseLiquidityParams {
    uint256 positionIndex;  // index of the position
    address tokenIn;        // tokenIn address
    address tokenOut;       // tokenOut address
    uint24 fee;             // fee amount for UniswapV3Pool
    int24 tickLower;        // tickLower for the range
    int24 tickUpper;        // tickUpper for the range
    uint128 liquidity;      // amount of liquidity to decrease
    address recipient;      // recipient of underlying tokenIn/tokenOut
  }
```

#### liquidate(LiquidateParams calldata params)

Liquidates the position with latest `positionIndex`, collecting all `tokenOut` to `RangeOrderPositionManager`. Increments the latest `positionIndex`.

Takes the following struct as a parameter:

```
  struct LiquidateParams {
    address tokenIn;    // tokenIn address
    address tokenOut;   // tokenOut address
    uint24 fee;         // fee amount for UniswapV3Pool
    int24 tickLower;    // tickLower for the range
    int24 tickUpper;    // tickUpper for the range
    address recipient;  // recipient of the accrued fee reward
  }
```

#### resolve(ResolveParams calldata params)

Resolves owner liquidity for a liquidated position, transferring `tokenOut` to the given owner address.

Takes the following struct as a parameter:

```
  struct ResolveParams {
    uint256 positionIndex;  // index of the position
    address tokenIn;        // tokenIn address
    address tokenOut;       // tokenOut address
    uint24 fee;             // fee amount for UniswapV3Pool
    int24 tickLower;        // tickLower for the range
    int24 tickUpper;        // tickUpper for the range
    address owner;          // address of the liquidity owner
  }
```

### View Functions

#### factory()

Returns the UniswapV3Factory address

#### positionIndexes(bytes32 positionHash)

Returns latest position index for a given position hash

#### positions (bytes32 positionHash, uint256 positionIndex)

Returns data for the position at `positionHash` and `positionIndex`

```
  struct Position {
    uint128 liquidity;
    bool liquidated;
  }
```

#### liquidityBalances (bytes32 positionHash, uint256 positionIndex, address owner)

Returns the liquidity balance for `owner` on the position at `positionHash` and `positionIndex`

## Range Orders UI

One benefit of the `RangeOrderPositionManager` contract is that it can support UI's for range orders that feel like a traditional limit order UI's. We plan to use `RangeOrderPositionManager` to add "Uniswap V3 Limit Orders" to the [Brink](https://brink.trade) web application, currently deployed on Görli testnet [here](https://dev.brink.ninja/). This will take advantage of Brink's meta transaction relays, allowing users to pay the gas cost for their range orders in `tokenIn` instead of ETH. Of course any UI can take advantage of the canonical `RangeOrderPositionManager` to create other experiences around range orders.
