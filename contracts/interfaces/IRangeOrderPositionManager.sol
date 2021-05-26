// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.7.5;
pragma abicoder v2;

import "./IUniswapV3Pool.sol";

interface IRangeOrderPositionManager {

  /// @return Returns the address of the Uniswap V3 factory
  function factory() external view returns (address);

  struct Position {
    // amount of liquidity for this position
    uint128 liquidity;
    // true when liquidity for the position has been burned on UniswapV3Pool after position has fully crossed
    bool liquidated;
  }

  function positionIndexes (bytes32 positionHash)
    external view
    returns (uint256 positionIndex);

  function positions (bytes32 positionHash, uint256 positionIndex)
    external view
    returns (Position memory position);

  function liquidityBalances (bytes32 positionHash, uint256 positionIndex, address owner)
    external view
    returns (uint128 liquidityBalance);

  struct IncreaseLiquidityParams {
    address owner;
    uint256 inputAmount;
    address tokenIn;
    address tokenOut;
    uint24 fee;
    int24 tickLower;
    int24 tickUpper;
  }

  /// @notice Increases liquidity for a position owner
  /// @param params owner The owner of the position
  /// inputAmount Amount of tokenIn provided
  /// tokenIn Input token for the position
  /// tokenOut Output token for the position
  /// fee The fee pool for the position
  /// tickLower Lower bound for the position
  /// tickUpper Upper bound for the position
  function increaseLiquidity(IncreaseLiquidityParams calldata params) external;

  struct IncreaseLiquidityMultiParams {
    address[] owners;
    uint256[] inputAmounts;
    uint256 totalInputAmount;
    address tokenIn;
    address tokenOut;
    uint24 fee;
    int24 tickLower;
    int24 tickUpper;
  }

  /// @notice Increases liquidity for multiple position owners
  /// @param params owners Array of owners
  /// inputAmounts Array of tokenIn amounts for each owner
  /// totalInputAmount Total of inputAmounts, required to be equal to the sum of inputAmounts values
  /// tokenIn Input token for the position
  /// tokenOut Output token for the position
  /// fee The fee pool for the position
  /// tickLower Lower bound for the position
  /// tickUpper Upper bound for the position
  function increaseLiquidityMulti(IncreaseLiquidityMultiParams calldata params) external;

  struct DecreaseLiquidityParams {
    uint256 positionIndex;
    address tokenIn;
    address tokenOut;
    uint24 fee;
    int24 tickLower;
    int24 tickUpper;
    uint128 liquidity;
    address recipient;
  }

  /// @notice Decreases liquidity
  /// @param params positionIndex Index of the position
  /// tokenIn Input token for the position
  /// tokenOut Output token for the position
  /// fee The fee pool for the position
  /// tickLower Lower bound for the position
  /// tickUpper Upper bound for the position
  /// liquidity Amount of liquidity to decrease from the position
  /// recipient The recipient of the collected assets
  function decreaseLiquidity (DecreaseLiquidityParams calldata params) external;

  struct LiquidateParams {
    address tokenIn;
    address tokenOut;
    uint24 fee;
    int24 tickLower;
    int24 tickUpper;
    address recipient;
  }

  /// @notice Liquidates a range order position that has been crossed
  /// @dev Burns all pool liquidity for a range order position and collects assets to this contract
  /// @param params tokenIn Input token for the position
  /// tokenOut Output token for the position
  /// fee The fee pool for the position
  /// tickLower Lower bound for the position
  /// tickUpper Upper bound for the position
  /// liquidity Amount of liquidity to decrease from the position
  /// recipient The recipient of the collected assets
  function liquidate(LiquidateParams calldata params) external;

  struct ResolveParams {
    uint256 positionIndex;
    address tokenIn;
    address tokenOut;
    uint24 fee;
    int24 tickLower;
    int24 tickUpper;
    address owner;
  }

  /// @notice Resolves a range order position that has been liquidated
  /// @dev Transfers liquidated assets from this contract to the position owner
  /// @param params positionIndex Index of the position
  /// tokenIn Input token for the position
  /// tokenOut Output token for the position
  /// fee The fee pool for the position
  /// tickLower Lower bound for the position
  /// tickUpper Upper bound for the position
  /// owner The position owner
  function resolve (ResolveParams calldata params) external;

}
