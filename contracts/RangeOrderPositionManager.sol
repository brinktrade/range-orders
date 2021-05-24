// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.7.5;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./interfaces/IUniswapV3Pool.sol";
import "./interfaces/IRangeOrderPositionManager.sol";
import './interfaces/callback/IUniswapV3MintCallback.sol';
import './libraries/CallbackValidation.sol';
import "./libraries/FullMath.sol";
import './libraries/LiquidityAmounts.sol';
import "./libraries/PoolAddress.sol";
import './libraries/TickMath.sol';
import "./libraries/TransferHelper.sol";

import "hardhat/console.sol";

/**
 * @dev A Uniswap V3 position manager for Range Orders. Splits liquidity ownership
 * across positions with the same `tokenIn`, `tokenOut`, `fee`, `tickLower` and `tickUpper`
 * values. Allows range order positions to be resolved once they have fully "crossed" from
 * `tokenIn` to `tokenOut`.
 */
contract RangeOrderPositionManager is IRangeOrderPositionManager, IUniswapV3MintCallback {
  using SafeMath for uint256;

  // TODO: add events

  address public immutable override factory;

  // positionHash => positionIndex
  mapping(bytes32 => uint256) private _positionIndexes;

  // positionHash => positionIndex => Position
  mapping(bytes32 => mapping(uint256 => Position)) private _positions;

  // positionHash => positionIndex => owner => liquidityBalance
  mapping(bytes32 => mapping(uint256 => mapping(address => uint128))) private _liquidityBalances;

  constructor(address _factory) {
    factory = _factory;
  }

  /// returns the current positionIndex for a positionHash
  /// positionHash => positionIndex
  function positionIndexes (bytes32 positionHash)
    external view override
    returns (uint256 positionIndex)
  {
    positionIndex = _positionIndexes[positionHash];
  }
  
  /// returns stored data for positions
  /// positionHash => positionIndex => Position
  function positions (bytes32 positionHash, uint256 positionIndex)
    external view override
    returns (Position memory position)
  {
    position = _positions[positionHash][positionIndex];
  }

  /// Returns stored owner liquidity balances on positions
  /// positionHash => positionIndex => ownerAddress => liquidityBalance
  function liquidityBalances (bytes32 positionHash, uint256 positionIndex, address owner)
    external view override
    returns (uint128 liquidityBalance)
  {
    liquidityBalance = _liquidityBalances[positionHash][positionIndex][owner];
  }

  struct MintCallbackData {
    PoolAddress.PoolKey poolKey;
    address payer;
  }

  /// @inheritdoc IUniswapV3MintCallback
  function uniswapV3MintCallback(
    uint256 amount0Owed,
    uint256 amount1Owed,
    bytes calldata data
  ) external override {
    MintCallbackData memory decoded = abi.decode(data, (MintCallbackData));
    CallbackValidation.verifyCallback(factory, decoded.poolKey);
    if (amount0Owed > 0) {
      TransferHelper.safeTransferFrom(decoded.poolKey.token0, decoded.payer, msg.sender, amount0Owed);
    }
    if (amount1Owed > 0) {
      TransferHelper.safeTransferFrom(decoded.poolKey.token1, decoded.payer, msg.sender, amount1Owed);
    }
  }

  /*
   * @dev Increases liquidity balances for owners. Can be called by any address
   *
   * Requires:
   *   - tickLower/tickUpper range to be 1 tickSpacing
   *   - range is either above or below current tick, depending on direction
   *   - totalInputAmount is equal to the sum of input amounts for each owner
   *
   */
  function createOrders(CreateOrdersParams calldata params)
    external override
  {
    require(params.owners.length == params.inputAmounts.length, 'ORDERS_LENGTH_MISMATCH');

    // get Position from storage
    bytes32 positionHash = keccak256(abi.encode(
      params.tokenIn, params.tokenOut, params.fee, params.tickLower, params.tickUpper
    ));
    uint256 positionIndex = _positionIndexes[positionHash];
    Position storage position = _positions[positionHash][positionIndex];

    (IUniswapV3Pool pool, PoolAddress.PoolKey memory poolKey) = _pool(params.tokenIn, params.tokenOut, params.fee);
    ( , int24 tick, , , , , ) = pool.slot0();
    if (params.tokenIn < params.tokenOut) {
      // for a token0->token1 order, range must be above the current tick
      require(tick < params.tickLower, 'RANGE_TOO_LOW');
    } else {
      // for a token1->token0 order, range must be below the current tick
      require(tick >= params.tickUpper, 'RANGE_TOO_HIGH');
    }

    // range must be 1 tick space
    require(params.tickUpper - params.tickLower == pool.tickSpacing(), 'BAD_RANGE_SIZE');

    uint128 liquidity;
    {
      uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(params.tickLower);
      uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(params.tickUpper);
      if (params.tokenIn < params.tokenOut) {
        liquidity = LiquidityAmounts.getLiquidityForAmount0(sqrtRatioAX96, sqrtRatioBX96, params.totalInputAmount);
      } else {
        liquidity = LiquidityAmounts.getLiquidityForAmount1(sqrtRatioAX96, sqrtRatioBX96, params.totalInputAmount);
      }
    }

    // mint liquidity on the UniswapV3Pool
    pool.mint(
        address(this),
        params.tickLower,
        params.tickUpper,
        liquidity,
        abi.encode(MintCallbackData({poolKey: poolKey, payer: msg.sender}))
    );

    // store individual owner liquidity
    uint256 accumInputAmount;
    for(uint8 i = 0; i < params.inputAmounts.length; i++) {
      uint256 ownerInputAmount = params.inputAmounts[i];
      accumInputAmount += ownerInputAmount;
      uint128 ownerLiquidity = uint128(FullMath.mulDiv(
        ownerInputAmount,
        liquidity,
        params.totalInputAmount
      ));
      _liquidityBalances[positionHash][positionIndex][params.owners[i]] += ownerLiquidity;
    }
    require(accumInputAmount == params.totalInputAmount, 'BAD_INPUT_AMOUNT');

    position.liquidity += liquidity;
  }

  /*
   * @dev Withdraws liquidity for a position. Can only be called by the liquidity owner.
   *      owners can withdraw liquidity at any price. If the position range has been
   *      crossed, the first withdraw will resolve all liquidity in the position
   *
   * Requires:
   *   - owner has enough liquidity balance to withdraw
   */
  function withdrawOrder (WithdrawParams calldata params)
    external override
  {
    bytes32 positionHash = keccak256(abi.encode(
      params.tokenIn, params.tokenOut, params.fee, params.tickLower, params.tickUpper
    ));
    uint128 ownerLiquidity = _liquidityBalances[positionHash][params.positionIndex][msg.sender];
    require(params.liquidity <= ownerLiquidity, 'NOT_ENOUGHT_LIQUIDITY');

    Position storage position = _positions[positionHash][params.positionIndex];
    bool token0In = params.tokenIn < params.tokenOut;
    address recipient = params.recipient == address(0) ? msg.sender : params.recipient;

    bool withdrawComplete;
    if (position.resolved == false) {
      (IUniswapV3Pool pool, ) = _pool(params.tokenIn, params.tokenOut, params.fee);
      ( , int24 tick, , , , , ) = pool.slot0();
      if (
        (token0In == true && tick >= params.tickUpper) ||
        (token0In == false && tick < params.tickLower)
      ) {
        // if the position is fully crossed to tokenOut, resolve all liquidity.
        // recipient will receive all tokenOut fees as a reward
        _resolvePosition(
          positionHash, pool, token0In, params.tickLower, params.tickUpper, recipient
        );
      } else {
        // if the position is not fully crossed, burn the owner's liquidity and collect
        _burnAndCollect(pool, params.tickLower, params.tickUpper, params.liquidity, recipient);

        // withdraw has been completed by direct collect from pool
        withdrawComplete = true;
      }
    }

    if (withdrawComplete == false) {
      // withdraw token held in this contract that is owed to the liquidity owner
      uint256 tokenOutOwed;
      uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(params.tickLower);
      uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(params.tickUpper);
      if (token0In == true) {
        tokenOutOwed = LiquidityAmounts.getAmount1ForLiquidity(sqrtRatioAX96, sqrtRatioBX96, params.liquidity);
      } else {
        tokenOutOwed = LiquidityAmounts.getAmount0ForLiquidity(sqrtRatioAX96, sqrtRatioBX96, params.liquidity);
      }
      TransferHelper.safeTransfer(params.tokenOut, recipient, tokenOutOwed);
    }

    position.liquidity -= params.liquidity;
    _liquidityBalances[positionHash][params.positionIndex][msg.sender] -= params.liquidity;
  }

  /*
   * @dev Resolves a position by burning liquidity on UniswapV3Pool and collecting tokens to this contract
   *
   * Requires:
   *   - range is "resolvable", meaning it is below or above current tick, depending on direction. Current
   *     tick must "cross" the positon range's outer tick bound
   */
  function resolvePosition(ResolvePositionParams calldata params)
    external override
  {
    bytes32 positionHash = keccak256(abi.encode(
      params.tokenIn, params.tokenOut, params.fee, params.tickLower, params.tickUpper
    ));

    Position storage position = _positions[positionHash][_positionIndexes[positionHash]];
    require(position.resolved == false, 'POSITION_ALREADY_RESOLVED');

    bool token0In = params.tokenIn < params.tokenOut;

    (IUniswapV3Pool pool, ) = _pool(params.tokenIn, params.tokenOut, params.fee);
    ( , int24 tick, , , , , ) = pool.slot0();
    if (token0In) {
      // for a token0->token1 order, range must be below the current tick
      require(tick >= params.tickUpper, 'RANGE_TOO_HIGH');
    } else {
      // for a token1->token0 order, range must be above the current tick
      require(tick < params.tickLower, 'RANGE_TOO_LOW');
    }

    address recipient = params.recipient == address(0) ? msg.sender : params.recipient;

    _resolvePosition(positionHash, pool, token0In, params.tickLower, params.tickUpper, recipient);
  }

  // removes liquidity and fees for this position from UniswapV3Pool and collects to this contract.
  // collects and transfers all tokenOut fees to recipient.
  function _resolvePosition (
    bytes32 positionHash,
    IUniswapV3Pool pool,
    bool token0In,
    int24 tickLower,
    int24 tickUpper,
    address recipient
  )
    internal
  {
    // position at positionHash and current positionIndex
    Position storage position = _positions[positionHash][_positionIndexes[positionHash]];

    // burn all liquidity for this position on UniswapV3Pool, collect the tokens from the burn to this contract
    _burnAndCollect(pool, tickLower, tickUpper, position.liquidity, address(this));

    // the remaining tokenOut are accrued fees, collect to the recipient
    pool.collect(
      recipient, tickLower, tickUpper, token0In ? 0 : type(uint128).max, token0In ? type(uint128).max : 0
    );

    position.resolved = true;
    _positionIndexes[positionHash]++;
  }

  function _burnAndCollect (
    IUniswapV3Pool pool,
    int24 tickLower,
    int24 tickUpper,
    uint128 liquidity,
    address recipient
  )
    internal
  {
    (uint256 amount0, uint256 amount1) = pool.burn(tickLower, tickUpper, liquidity);
    pool.collect(recipient, tickLower, tickUpper, uint128(amount0), uint128(amount1));
  }

  function _pool (address tokenIn, address tokenOut, uint24 fee)
    internal view
    returns (IUniswapV3Pool pool, PoolAddress.PoolKey memory poolKey)
  {
    poolKey = PoolAddress.PoolKey({
      token0: tokenIn < tokenOut ? tokenIn : tokenOut,
      token1: tokenIn < tokenOut ? tokenOut : tokenIn,
      fee: fee
    });
    pool = IUniswapV3Pool(PoolAddress.computeAddress(
      factory,
      poolKey
    ));
  }
}
