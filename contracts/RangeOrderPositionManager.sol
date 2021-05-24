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

  // Increases liquidity for a single owner
  function increaseLiquidity(IncreaseLiquidityParams calldata params)
    external override
  {
    uint128 liquidity = _mintPoolLiquidity(
      params.inputAmount, params.tokenIn, params.tokenOut, params.fee, params.tickLower, params.tickUpper
    );

    // get Position from storage
    bytes32 positionHash = keccak256(abi.encode(
      params.tokenIn, params.tokenOut, params.fee, params.tickLower, params.tickUpper
    ));
    uint256 positionIndex = _positionIndexes[positionHash];
    Position storage position = _positions[positionHash][positionIndex];

    _liquidityBalances[positionHash][positionIndex][params.owner] += liquidity;
    position.liquidity += liquidity;
  }

  // Increases liquidity for multiple owners
  function increaseLiquidityMulti(IncreaseLiquidityMultiParams calldata params)
    external override
  {
    require(params.owners.length == params.inputAmounts.length, 'ORDERS_LENGTH_MISMATCH');

    uint128 liquidity = _mintPoolLiquidity(
      params.totalInputAmount, params.tokenIn, params.tokenOut, params.fee, params.tickLower, params.tickUpper
    );

    // get Position from storage
    bytes32 positionHash = keccak256(abi.encode(
      params.tokenIn, params.tokenOut, params.fee, params.tickLower, params.tickUpper
    ));
    uint256 positionIndex = _positionIndexes[positionHash];
    Position storage position = _positions[positionHash][positionIndex];

    // store individual owner liquidity
    uint256 accumInputAmount;
    for(uint8 i = 0; i < params.inputAmounts.length; i++) {
      uint256 ownerInputAmount = params.inputAmounts[i];
      accumInputAmount += ownerInputAmount;
      uint128 ownerLiquidity = uint128(FullMath.mulDiv(
        ownerInputAmount, liquidity, params.totalInputAmount
      ));
      _liquidityBalances[positionHash][positionIndex][params.owners[i]] += ownerLiquidity;
    }
    require(accumInputAmount == params.totalInputAmount, 'BAD_INPUT_AMOUNT');

    position.liquidity += liquidity;
  }

  // Decreases position liquidity for msg.sender
  function decreaseLiquidity (DecreaseLiquidityParams calldata params)
    external override
  {
    bytes32 positionHash = keccak256(abi.encode(
      params.tokenIn, params.tokenOut, params.fee, params.tickLower, params.tickUpper
    ));
    uint128 ownerLiquidity = _liquidityBalances[positionHash][params.positionIndex][msg.sender];
    require(params.liquidity <= ownerLiquidity, 'NOT_ENOUGHT_LIQUIDITY');

    (IUniswapV3Pool pool, ) = _pool(params.tokenIn, params.tokenOut, params.fee);
    require(_positionIsCrossed(
      pool, params.tokenIn, params.tokenOut, params.tickLower, params.tickUpper
    ) == false, 'OUT_OF_RANGE');

    address recipient = params.recipient == address(0) ? msg.sender : params.recipient;
    _burnAndCollect(pool, params.tickLower, params.tickUpper, params.liquidity, recipient);

    _positions[positionHash][params.positionIndex].liquidity -= params.liquidity;
    _liquidityBalances[positionHash][params.positionIndex][msg.sender] -= params.liquidity;
  }

  // Burns pool liquidity for position and collects to this contract
  function liquidate(LiquidateParams calldata params)
    external override
  {
    bytes32 positionHash = keccak256(abi.encode(
      params.tokenIn, params.tokenOut, params.fee, params.tickLower, params.tickUpper
    ));
    Position storage position = _positions[positionHash][_positionIndexes[positionHash]];
    require(position.liquidated == false, 'LIQUIDATED');

    (IUniswapV3Pool pool, ) = _pool(params.tokenIn, params.tokenOut, params.fee);
    require(_positionIsCrossed(
      pool, params.tokenIn, params.tokenOut, params.tickLower, params.tickUpper
    ) == true, 'OUT_OF_RANGE');

    _burnAndCollect(pool, params.tickLower, params.tickUpper, position.liquidity, address(this));

    // the remaining tokenOut are accrued fees, collect to the recipient
    pool.collect(
      params.recipient == address(0) ? msg.sender : params.recipient,
      params.tickLower, params.tickUpper,
      params.tokenIn < params.tokenOut ? 0 : type(uint128).max,
      params.tokenIn < params.tokenOut ? type(uint128).max : 0
    );

    position.liquidated = true;
    _positionIndexes[positionHash]++;
  }

  // Transfers liquidated tokenOut to position owner
  function resolve (ResolveParams calldata params)
    external override
  {
    bytes32 positionHash = keccak256(abi.encode(
      params.tokenIn, params.tokenOut, params.fee, params.tickLower, params.tickUpper
    ));
    Position storage position = _positions[positionHash][params.positionIndex];
    require(position.liquidated == true, 'NOT_LIQUIDATED');

    uint128 ownerLiquidity = _liquidityBalances[positionHash][params.positionIndex][params.owner];
    require(ownerLiquidity > 0, 'NO_LIQUIDITY');

    uint256 tokenOutOwed;
    uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(params.tickLower);
    uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(params.tickUpper);
    if (params.tokenIn < params.tokenOut) {
      tokenOutOwed = LiquidityAmounts.getAmount1ForLiquidity(sqrtRatioAX96, sqrtRatioBX96, ownerLiquidity);
    } else {
      tokenOutOwed = LiquidityAmounts.getAmount0ForLiquidity(sqrtRatioAX96, sqrtRatioBX96, ownerLiquidity);
    }
    TransferHelper.safeTransfer(params.tokenOut, params.owner, tokenOutOwed);

    position.liquidity -= ownerLiquidity;
    _liquidityBalances[positionHash][params.positionIndex][params.owner] -= ownerLiquidity;
  }

  // internal functions

  function _positionIsCrossed (IUniswapV3Pool pool, address tokenIn, address tokenOut, int24 tickLower, int24 tickUpper)
    internal view
    returns (bool)
  {
    ( , int24 tick, , , , , ) = pool.slot0();
    if (tokenIn < tokenOut) {
      // for a token0->token1 order, return true if current tick is above range
      return tick >= tickUpper;
    } else {
      // for a token1->token0 order, return true if current tick is below range
      return tick < tickLower;
    }
  }

  function _mintPoolLiquidity (
    uint256 inputAmount, address tokenIn, address tokenOut, uint24 fee, int24 tickLower, int24 tickUpper
  )
    internal
    returns (uint128 liquidity)
  {
    (IUniswapV3Pool pool, PoolAddress.PoolKey memory poolKey) = _pool(tokenIn, tokenOut, fee);

    // TODO: this should revert if the range is entered or crossed, right now it just reverts if it's
    // crossed
    require(_positionIsCrossed(pool, tokenIn, tokenOut, tickLower, tickUpper) == false, 'OUT_OF_RANGE');

    // range must be 1 tick space
    require(tickUpper - tickLower == pool.tickSpacing(), 'BAD_RANGE_SIZE');

    uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickLower);
    uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tickUpper);
    if (tokenIn < tokenOut) {
      liquidity = LiquidityAmounts.getLiquidityForAmount0(sqrtRatioAX96, sqrtRatioBX96, inputAmount);
    } else {
      liquidity = LiquidityAmounts.getLiquidityForAmount1(sqrtRatioAX96, sqrtRatioBX96, inputAmount);
    }

    // mint liquidity on the UniswapV3Pool
    pool.mint(
        address(this),
        tickLower,
        tickUpper,
        liquidity,
        abi.encode(MintCallbackData({poolKey: poolKey, payer: msg.sender}))
    );
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
