// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.7.5;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../uniswap-v3-periphery-contracts/base/Multicall.sol";
import "../uniswap-v3-periphery-contracts/interfaces/INonfungiblePositionManager.sol";
import "../uniswap-v3-periphery-contracts/interfaces/IPeripheryPayments.sol";
import "../uniswap-v3-periphery-contracts/interfaces/external/IWETH9.sol";
import "../uniswap-v3-periphery-contracts/libraries/PoolAddress.sol";
import "../uniswap-v3-periphery-contracts/libraries/PositionKey.sol";
import "../uniswap-v3-periphery-contracts/libraries/TransferHelper_V3Periphery.sol";
import "../uniswap-v3-core-contracts/interfaces/IUniswapV3Pool.sol";
import "../uniswap-v3-core-contracts/libraries/FixedPoint128.sol";
import "../uniswap-v3-core-contracts/libraries/FullMath.sol";

import "./interfaces/IUniswapV3RangeOrders.sol";

import "hardhat/console.sol";

/**
 * @dev Allows pooled ownership in Uniswap V3 "Range Order" positions, and public resolution of
 * positions for a reward.
 */
contract UniswapV3RangeOrders01 is IUniswapV3RangeOrders, Multicall {
  using SafeMath for uint256;

  // TODO: add events

  /// Address of NonfungiblePositionManager
  INonfungiblePositionManager public immutable override nonfungiblePositionManager;

  /// Address of UniswapV3Factory (must match NonfungiblePositionManager factory)
  address public immutable override factory;

  /// Address of WETH9  (must match NonfungiblePositionManager WETH9)
  address public immutable override WETH9;

  /// Number of seconds to run resolve auctions. If a position is resolvable for
  /// this many seconds, 100% of liquidity will be transferred to the resolver
  uint32 public immutable override resolveAuctionTimespan;

  mapping(bytes32 => Position) private _positions;

  mapping(bytes32 => mapping(address => uint128)) private _liquidityBalances;

  constructor (
    INonfungiblePositionManager _nonfungiblePositionManager,
    address _factory,
    address _WETH9,
    uint32 _resolveAuctionTimespan
  ) {
    nonfungiblePositionManager = _nonfungiblePositionManager;
    factory = _factory;
    WETH9 = _WETH9;
    resolveAuctionTimespan = _resolveAuctionTimespan;
  }

  /// Allows this contract to receive ETH from the WETH9 contract only
  receive() external payable {
    require(msg.sender == WETH9, 'NOT_WETH9');
  }
  
  /// returns stored data for positions
  /// positionHash => Position
  function positions (bytes32 positionHash)
    external view override
    returns (Position memory position)
  {
    position = _positions[positionHash];
    require(position.tokenId != 0, 'INVALID_POSITION_HASH');
  }

  /// Returns stored owner liquidity balances on positions
  /// positionHash => ownerAddress => liquidityBalance
  function liquidityBalances (bytes32 positionHash, address owner)
    external view override
    returns (uint128 liquidityBalance)
  {
    liquidityBalance = _liquidityBalances[positionHash][owner];
  }

  /*
   * @dev Increases liquidity balances for owners. Can be called by any address
   *
   * Requires:
   *   - tickLower/tickUpper range to be 1 tickSpacing
   *   - range is either above or below current tick, depending on direction
   *   - totalInputAmount is equal to the sum of input amounts for each owner
   *
   * NOTE: An amount of tokenIn equal to totalInputAmount must be transferred to this contract.
   * If tokenIn is WETH9, ETH must be paid by the sender.
   */
  function createOrders(CreateOrdersParams calldata params)
    external payable override
  {
    require(params.owners.length == params.inputAmounts.length, 'ORDERS_LENGTH_MISMATCH');

    // get Position from storage
    bytes32 positionHash = keccak256(abi.encode(
      params.tokenIn, params.tokenOut, params.fee, params.tickLower, params.tickUpper
    ));
    Position storage position = _positions[positionHash];

    // if position has not been minted, calculate the pool address and store it here.
    // this let's us check the pool's tick state and revert early if the range is invalid
    if (position.tokenId == 0) {
      position.pool = IUniswapV3Pool(PoolAddress.computeAddress(
        factory,
        PoolAddress.PoolKey({
          token0: params.tokenIn < params.tokenOut ? params.tokenIn : params.tokenOut,
          token1: params.tokenIn < params.tokenOut ? params.tokenOut : params.tokenIn,
          fee: params.fee
        })
      ));
    }

    ( , int24 tick, , , , , ) = position.pool.slot0();
    if (params.tokenIn < params.tokenOut) {
      // for a token0->token1 order, range must be above the current tick
      require(tick < params.tickLower, 'RANGE_TOO_LOW');
    } else {
      // for a token1->token0 order, range must be below the current tick
      require(tick >= params.tickUpper, 'RANGE_TOO_HIGH');
    }

    // range must be 1 tick space
    require(params.tickUpper - params.tickLower == position.pool.tickSpacing(), 'BAD_RANGE_SIZE');

    if(params.tokenIn != WETH9) {
      // approve tokenIn for NonfungiblePositionManager to pay the UniswapV3Pool
      IERC20(params.tokenIn).approve(address(nonfungiblePositionManager), params.totalInputAmount);
    }

    uint128 newLiquidity;
    if (position.tokenId == 0) {
      newLiquidity = _mintPosition(positionHash, params.tokenIn, params.tokenOut, params.fee, params.tickLower, params.tickUpper, params.totalInputAmount);
    } else {
      uint128 tokenInFees;
      uint128 tokenOutFees;
      (newLiquidity, tokenInFees, tokenOutFees) = _increasePositionLiquidity(positionHash, params.tokenIn, params.tokenOut, params.totalInputAmount);
      position.tokenInFees += tokenInFees;
      position.tokenOutFees += tokenOutFees;
    }

    // store individual owner liquidity
    uint256 accumInputAmount;
    bool remainder;
    for(uint8 i = 0; i < params.inputAmounts.length; i++) {
      uint256 ownerInputAmount = params.inputAmounts[i];
      accumInputAmount += ownerInputAmount;
      uint128 ownerLiquidity = uint128(FullMath.mulDiv(
        ownerInputAmount,
        newLiquidity,
        params.totalInputAmount
      ));
      if (!remainder && mulmod(ownerInputAmount, newLiquidity, params.totalInputAmount) > 0) {
        // ensure that total owner liquidity adds up to exactly the amount of liquidity in the position
        remainder = true;
        ownerLiquidity++;
      }
      _liquidityBalances[positionHash][params.owners[i]] += ownerLiquidity;
    }
    require(accumInputAmount == params.totalInputAmount, 'BAD_INPUT_AMOUNT');
  }

  /*
   * @dev Resolves owner liquidity by decreasing liquidity amount and transferring assets to owners.
   *      Can be called by any address. A reward is transferred to the resolver address. This increases
   *      based on the amount of time the position has been resolvable. The resolver also receives any
   *      accrued fees based on the percentage of liquidity in the position they are resolving.
   *
   * Requires:
   *   - tickLower/tickUpper range to be 1 tickSpacing
   *   - range is "resolvable", meaning it is below or above current tick, depending on direction. Current
   *     tick must "cross" the outer tick in the range.
   *   - resolveLiquidity is equal to the sum of liquidity balances for each owner
   *
   * NOTE: this does not support partial resolution for owners. Gas cost difference should be negligible
   *       for varying order sizes, so there is no need for resolvers to do partial resolutions. Resolvers
   *       need to specify individual owner addresses to avoid the situation where iterating over all
   *       owner addresses would exceed the block gas limit.
   */
  function resolveOrders(ResolveOrdersParams calldata params)
    external override
  {
    uint128 tokenOutOwed;
    bytes32 positionHash = keccak256(abi.encode(
      params.tokenIn, params.tokenOut, params.fee, params.tickLower, params.tickUpper
    ));

    {
      Position storage position = _positions[positionHash];

      ( , , address token0, , , , , uint128 totalLiquidity, , , , ) = nonfungiblePositionManager.positions(position.tokenId);

      {
        // require that the position has crossed the outer tick in the range
        ( , int24 tick, , , , , ) = position.pool.slot0();
        if (params.tokenIn == token0) {
          // for a token0 order, range must be below the current tick
          require(tick >= params.tickUpper, 'RANGE_TOO_HIGH');
        } else {
          // for a token1 order, range must be above the current tick
          require(tick < params.tickLower, 'RANGE_TOO_LOW');
        }
      }

      {
        // TODO: this needs to be reset after successful resolve,
        // and needs to handle the case where the position crosses back over the range
        uint32 resolvableSeconds = _blockTimestamp() - _getSecondsOutside(
          position.pool,
          params.tokenIn < params.tokenOut ? params.tickUpper : params.tickLower
        ) - (position.cachedSecondsOutside - 1);
        if (resolvableSeconds > resolveAuctionTimespan) {
          resolvableSeconds = resolveAuctionTimespan;
        }

        // since we require the range to be fully crossed, tokenInAmount should always be 0
        uint256 tokenOutAmount;
        uint128 tokenInReward;
        uint128 tokenOutFeeReward;
        {
          uint128 tokenInNewFees;
          uint128 tokenOutNewFees;
          ( , tokenOutAmount, tokenInNewFees, tokenOutNewFees) = _decreasePositionLiquidity(
            positionHash, params.tokenIn, params.tokenOut, params.resolveLiquidity
          );
          tokenInReward = uint128(FullMath.mulDiv(
            position.tokenInFees + tokenInNewFees, params.resolveLiquidity, totalLiquidity
          ));
          position.tokenInFees = uint128(FullMath.mulDiv(
            position.tokenInFees + tokenInNewFees, totalLiquidity - params.resolveLiquidity, totalLiquidity
          ));

          tokenOutFeeReward = uint128(FullMath.mulDiv(
            position.tokenOutFees + tokenOutNewFees, params.resolveLiquidity, totalLiquidity
          ));
          position.tokenOutFees = uint128(FullMath.mulDiv(
            position.tokenOutFees + tokenOutNewFees, totalLiquidity - params.resolveLiquidity, totalLiquidity
          ));
        }

        tokenOutOwed = uint128(FullMath.mulDiv(
          tokenOutAmount, resolveAuctionTimespan - resolvableSeconds, resolveAuctionTimespan
        ));
        uint128 tokenOutReward = tokenOutFeeReward + uint128(FullMath.mulDiv(
          tokenOutAmount, resolvableSeconds, resolveAuctionTimespan
        ));
        
        _collectFromPosition(
          position.tokenId,
          address(this),
          params.tokenIn < params.tokenOut ? tokenInReward : tokenOutOwed + tokenOutReward,
          params.tokenIn < params.tokenOut ? tokenOutOwed + tokenOutReward : tokenInReward
        );
        _transfer(params.tokenOut, params.resolver, tokenOutReward);
        _transfer(params.tokenIn, params.resolver, tokenInReward);
      }
    }

    // iterate to compute individual owner owed amounts, transfer to owners
    uint128 accumResolveLiquidity;
    bool remainder;
    for(uint8 i = 0; i < params.owners.length; i++) {
      address owner = params.owners[i];
      uint128 ownerLiquidity = _liquidityBalances[positionHash][owner];
      uint256 tokenOutOwnerOwed = FullMath.mulDiv(
        tokenOutOwed, ownerLiquidity, params.resolveLiquidity
      );
      if (!remainder && mulmod(tokenOutOwed, ownerLiquidity, params.resolveLiquidity) > 0) {
        remainder = true;
        tokenOutOwnerOwed++;
      }
      _transfer(params.tokenOut, owner, tokenOutOwnerOwed);
      accumResolveLiquidity += ownerLiquidity;
    }
    require(accumResolveLiquidity == params.resolveLiquidity, 'BAD_RESOLVE_LIQUIDITY');
  }

  /*
   * @dev Withdraws liquidity for an individually owned "order". Can only be called by the balance owner.
   *      There are no requirements around range for this endpoint, owners can withdraw by calling this
   *      endpoint directly at any time.
   *
   * Requires:
   *   - owner has enough liquidity balance to withdraw
   */
  /// TODO: how should we handle the scenario where an owner withdraws in the same block as a resolveOrders()
  /// call with their address? If withdrawOrder() happens first, resolveOrders() will revert (and vice-versa).
  /// Is this an edge case and we expect resolvers to deal with reverts and the additional cost of this?
  function withdrawOrder (WithdrawParams calldata params)
    external override
  {
    uint128 ownerLiquidity = _liquidityBalances[params.positionHash][msg.sender];
    require(params.liquidity <= ownerLiquidity, 'NOT_ENOUGHT_LIQUIDITY');

    Position storage position = _positions[params.positionHash];

    (uint256 token0CollectAmount, uint256 token1CollectAmount, uint128 tokenInFees, uint128 tokenOutFees) = _decreasePositionLiquidity(
      params.positionHash, params.tokenIn, params.tokenOut, ownerLiquidity
    );
    position.tokenInFees += tokenInFees;
    position.tokenOutFees += tokenOutFees;

    address token0 = params.tokenIn < params.tokenOut ? params.tokenIn : params.tokenOut;
    address token1 = params.tokenIn < params.tokenOut ? params.tokenOut : params.tokenIn;

    _collectAndTransfer(position.tokenId, msg.sender, token0, token1, uint128(token0CollectAmount), uint128(token1CollectAmount));
  }

  /* @dev Can be called with multicall() before createOrders() call.
   *      This is needed when createOrders() is called from an EOA.
   *      createOrders() could be called from another contract that transfers token to this contract,
   *      in which case pullPayment() isn't needed
   */
  function pullPayment (address token, address payer, uint256 value)
    external override
  {
    TransferHelper_V3Periphery.safeTransferFrom(token, payer, address(this), value);
  }

  /// Internal function to mint a position on NonfungiblePositionManager
  function _mintPosition (bytes32 positionHash, address tokenIn, address tokenOut, uint24 fee, int24 tickLower, int24 tickUpper, uint256 tokenInAmount)
    internal
    returns (uint128 liquidity)
  {
    Position storage position = _positions[positionHash];

    uint256 tokenId;
    (tokenId, liquidity, , ) = nonfungiblePositionManager.mint{ value: address(this).balance }(
      INonfungiblePositionManager.MintParams({
        token0: tokenIn < tokenOut ? tokenIn : tokenOut,
        token1: tokenIn < tokenOut ? tokenOut : tokenIn,
        fee: fee,
        tickLower: tickLower,
        tickUpper: tickUpper,
        amount0Desired: tokenIn < tokenOut ? tokenInAmount : uint256(0),
        amount1Desired: tokenIn < tokenOut ? uint256(0) : tokenInAmount,
        amount0Min: 0,
        amount1Min: 0,
        recipient: address(this),
        deadline: _blockTimestamp()
      })
    );
    position.tokenId = tokenId;

    // cache the current secondsOutside value for the outer tick in the range,
    // used to compute the time based relay reward. adds 1 so cached value will never be zero
    position.cachedSecondsOutside = _getSecondsOutside(
      position.pool,
      tokenIn < tokenOut ? tickUpper : tickLower
    ) + 1;
  }

  /// Internal function to increase liquidity on a NonfungiblePositionManager position
  function _increasePositionLiquidity (bytes32 positionHash, address tokenIn, address tokenOut, uint256 tokenInAmount)
    internal
    returns (uint128 liquidity, uint128 tokenInFees, uint128 tokenOutFees)
  {
    Position memory position = _positions[positionHash];

    ( , , , , , , , , , , uint128 iTokensOwed0, uint128 iTokensOwed1)
      = nonfungiblePositionManager.positions(position.tokenId);

    (liquidity, , ) = nonfungiblePositionManager.increaseLiquidity{ value: address(this).balance }(
      INonfungiblePositionManager.IncreaseLiquidityParams({
        tokenId: position.tokenId,
        amount0Desired: tokenIn < tokenOut ? tokenInAmount : uint256(0),
        amount1Desired: tokenIn < tokenOut ? uint256(0) : tokenInAmount,
        amount0Min: 0,
        amount1Min: 0,
        deadline: _blockTimestamp()
      })
    );

    ( , , , , , , , , , , uint128 fTokensOwed0, uint128 fTokensOwed1)
      = nonfungiblePositionManager.positions(position.tokenId);
    uint128 token0Fees = fTokensOwed0 - iTokensOwed0;
    uint128 token1Fees = fTokensOwed1 - iTokensOwed1;
    tokenInFees = tokenIn < tokenOut ? token0Fees : token1Fees;
    tokenOutFees = tokenIn < tokenOut ? token1Fees : token0Fees;
  }

  /// Internal function to decrease liquidity on a NonfungiblePositionManager position
  function _decreasePositionLiquidity (bytes32 positionHash, address tokenIn, address tokenOut, uint128 liquidity)
    internal
    returns (uint256 tokenInAmount, uint256 tokenOutAmount, uint128 tokenInFees, uint128 tokenOutFees)
  {
    uint256 token0Amount;
    uint256 token1Amount;
    uint128 tokensOwedDiff0;
    uint128 tokensOwedDiff1;
    {
      Position memory position = _positions[positionHash];
      ( , , , , , , , , , , uint128 iTokensOwed0, uint128 iTokensOwed1)
        = nonfungiblePositionManager.positions(position.tokenId);
      (token0Amount, token1Amount) = nonfungiblePositionManager.decreaseLiquidity(
        INonfungiblePositionManager.DecreaseLiquidityParams({
          tokenId: position.tokenId,
          liquidity: liquidity,
          amount0Min: 0,
          amount1Min: 0,
          deadline: _blockTimestamp()
        })
      );
      ( , , , , , , , , , , uint128 fTokensOwed0, uint128 fTokensOwed1)
        = nonfungiblePositionManager.positions(position.tokenId);
      tokensOwedDiff0 = fTokensOwed0 - iTokensOwed0;
      tokensOwedDiff1 = fTokensOwed1 - iTokensOwed1;
    }
    uint128 token0Fees = tokensOwedDiff0 - uint128(token0Amount);
    uint128 token1Fees = tokensOwedDiff1 - uint128(token1Amount);
    tokenInAmount = tokenIn < tokenOut ? token0Amount : token1Amount;
    tokenOutAmount = tokenIn < tokenOut ? token1Amount : token0Amount;
    tokenInFees = tokenIn < tokenOut ? token0Fees : token1Fees;
    tokenOutFees = tokenIn < tokenOut ? token1Fees : token0Fees;
  }

  // TODO: latest v3-periphery adds the interface for IPeripheryPayments, and uses address(0) instead
  // of having to pass in the positionManager address
  //
  /// Internal function to collect from on a NonfungiblePositionManager position and transfer the collected funds
  function _collectAndTransfer (uint256 tokenId, address recipient, address token0, address token1, uint128 amount0, uint128 amount1)
    internal
  {
    if (token0 == WETH9 || token1 == WETH9) {
      // if either token is WETH, collect to this contract to withdraw WETH and transfer as ETH
      _collectFromPosition(tokenId, address(this), amount0, amount1);
      _transfer(token0, recipient, amount0);
      _transfer(token1, recipient, amount1);
    } else {
      // if neither collected amount is in WETH, collect directly to recipient
      _collectFromPosition(tokenId, recipient, amount0, amount1);
    }
  }

  /// Internal function to collect from on a NonfungiblePositionManager position
  function _collectFromPosition (uint256 tokenId, address recipient, uint128 amount0, uint128 amount1)
    internal
  {
    (uint256 amount0Collected, uint256 amount1Collected) = nonfungiblePositionManager.collect(
      INonfungiblePositionManager.CollectParams({
        tokenId: tokenId,
        recipient: recipient,
        amount0Max: amount0,
        amount1Max: amount1
      })
    );
    require(amount0 == uint128(amount0Collected), 'WRONG_AMOUNT0_COLLECTED');
    require(amount1 == uint128(amount1Collected), 'WRONG_AMOUNT1_COLLECTED');
  }

  function _transfer(address token, address recipient, uint256 amount)
   internal
  {
    if (amount > 0) {
      if (token == WETH9) {
        IWETH9(WETH9).withdraw(amount);
        TransferHelper_V3Periphery.safeTransferETH(recipient, amount);
      } else {
        TransferHelper_V3Periphery.safeTransfer(token, recipient, amount);
      }
    }
  }

  // used to cache the initial secondsOutside value for range order ticks so we can
  // calculate `resolvableSeconds`, the total number of seconds an order has been resolvable for.
  // Reward for resolving orders increases as `resolvableSeconds` increases
  function _getSecondsOutside(IUniswapV3Pool pool, int24 tick) internal view returns (uint32) {
    int24 tickSpacing = pool.tickSpacing();
    require(tick % tickSpacing == 0);
    int24 compressed = tick / tickSpacing;
    int24 wordPos = compressed >> 3;
    uint8 shift = uint8(compressed % 8) * 32;
    uint256 prev = pool.secondsOutside(wordPos);
    return uint32(prev >> shift);
  }

  function _blockTimestamp() internal view virtual returns (uint32) {
    return uint32(block.timestamp);
  }
}
