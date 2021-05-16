// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.7.5;
pragma abicoder v2;

import "../../uniswap-v3-core-contracts/interfaces/IUniswapV3Pool.sol";
import "../../uniswap-v3-periphery-contracts/interfaces/INonfungiblePositionManager.sol";

interface IRangeOrdersPositionManager {

  function nonfungiblePositionManager() external view returns (INonfungiblePositionManager);

  function factory() external view returns (address);
  
  function WETH9() external view returns (address);

  function resolveAuctionTimespan() external view returns (uint32);

  /*
   * Storage for position data
   *
   * uint256 tokenId: ID of the position token in NonfungiblePositionManager
   * IUniswapV3Pool pool: The UniswapV3Pool contract for the position
   * uint128 tokenInFees: accrued fees in tokenIn that have not been collected
   * uint128 tokenOutFees: accrued fees in tokenOut that have not been collected
   * uint32 cachedSecondsOutside: cached secondsOutside value used to compute
   *   `resolveableSeconds`. equivalent to using secondsOutside for maxTick or minTick,
   *   but since the secondsOutside value for those is not gauranteed to be stored on
   *   UniswapV3Pool without creating a new position with maxTick or minTick as one of
   *   the range bounds, we are storing it here.
   */
  struct Position {
    uint256 tokenId;
    IUniswapV3Pool pool;
    uint128 tokenInFees;
    uint128 tokenOutFees;
    uint32 cachedSecondsOutside;
  }

  function positions (bytes32 positionHash) external view returns (Position memory position);

  function liquidityBalances (bytes32 positionHash, address owner)
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
   * Input params for resolveOrders()
   *
   * address[] owners: array of owners to resolve liquidity for
   * address tokenIn: input token for the resolvable orders
   * address tokenOut: output token for the resolvable orders
   * uint24 fee: fee amount for the UniswapV3Pool
   * int24 tickLower: lower bound for the resolvable orders
   * int24 tickUpper: upper bound for the resolvable orders
   * uint128 resolveLiquidity: total amount of liquidity that will be resolved on
   *    the position
   * address resolver: address that will receive the resolve reward
   */
  struct ResolveOrdersParams {
    address[] owners;
    address tokenIn;
    address tokenOut;
    uint24 fee;
    int24 tickLower;
    int24 tickUpper;
    uint128 resolveLiquidity;
    address resolver;
  }

  function resolveOrders(ResolveOrdersParams calldata params) external;

  /*
   * Input params for withdrawOrder()
   *
   * bytes32 positionHash: hash of the position to withdraw liquidity from
   * address tokenIn: input token for the order
   * address tokenOut: output token for the order
   * uint256 liquidity: amount of liquidity to withdraw
   */
  struct WithdrawParams {
    bytes32 positionHash;
    address tokenIn;
    address tokenOut;
    uint256 liquidity;
  }

  function withdrawOrder (WithdrawParams calldata params) external;

  function pullPayment (address token, address payer, uint256 value) external;

}
