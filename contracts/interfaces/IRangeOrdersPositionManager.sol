// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.7.5;
pragma abicoder v2;

import "./IUniswapV3Pool.sol";

interface IRangeOrdersPositionManager {
  /*
   * Storage for position data
   *
   *
   */
  struct Position {
    // amount of liquidity for this position
    uint128 liquidity;
    // true when liquidity for the position has been burned on UniswapV3Pool after position has fully crossed
    bool resolved;
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

  /*
   * Input params for createOrders()
   *
   * address[] owners: array of owners for the new orders
   * uint256[] inputAmounts: array of tokenIn amounts for the new owners
   * uint256 totalInputAmount: total of inputAmounts, required to be equal to the sum
   *    of inputAmounts values
   * address tokenIn: input token for the orders
   * address tokenOut: output token for the orders
   * uint24 fee: fee amount for the UniswapV3Pool
   * int24 tickLower: lower bound for the range orders
   * int24 tickUpper: upper bound for the range orders
   */
  struct CreateOrdersParams {
    address[] owners;
    uint256[] inputAmounts;
    uint256 totalInputAmount;
    address tokenIn;
    address tokenOut;
    uint24 fee;
    int24 tickLower;
    int24 tickUpper;
  }

  function createOrders(CreateOrdersParams calldata params) external payable;

  /*
   * Input params for resolvePosition()
   *
   * address tokenIn: input token for the resolvable orders
   * address tokenOut: output token for the resolvable orders
   * uint24 fee: fee amount for the UniswapV3Pool
   * int24 tickLower: lower bound for the resolvable orders
   * int24 tickUpper: upper bound for the resolvable orders
   * address recipient: address that will receive the resolve reward
   */
  struct ResolvePositionParams {
    address tokenIn;
    address tokenOut;
    uint24 fee;
    int24 tickLower;
    int24 tickUpper;
    address recipient;
  }

  function resolvePosition(ResolvePositionParams calldata params) external;

  /*
   * Input params for withdrawOrder()
   *
   * uint256 positionIndex: index of the position
   * address tokenIn: input token for the order
   * address tokenOut: output token for the order
   * uint256 liquidity: amount of liquidity to withdraw
   */
  struct WithdrawParams {
    uint256 positionIndex;
    address tokenIn;
    address tokenOut;
    uint24 fee;
    int24 tickLower;
    int24 tickUpper;
    uint128 liquidity;
    address recipient;
  }

  function withdrawOrder (WithdrawParams calldata params) external;

  // function pullPayment (address token, address payer, uint256 value) external;

}
