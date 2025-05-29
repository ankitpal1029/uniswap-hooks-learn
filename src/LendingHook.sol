// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "v4-periphery/lib/v4-core/src/interfaces/IPoolManager.sol";
import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {Currency, CurrencyLibrary} from "v4-periphery/lib/v4-core/src/types/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, toBeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {Constants} from "v4-core/test/utils/Constants.sol";

import {Variables} from "./Variables.sol";
import {Lending} from "./Lending.sol";

contract LendingHook is BaseHook, Variables {
    using CurrencyLibrary for Currency;
    using SafeERC20 for IERC20;

    enum PositionStatus {
        INACTIVE,
        ACTIVE,
        LIQUIDATING
    }

    Lending lending;
    address owner;

    uint256 public constant LIQUIDATION_THRESHOLD = 9000; // 90% threshold
    uint256 public constant LIQUIDATION_MAX_LIMIT = 9500; // 95% max limit

    mapping(PoolId => uint256 count) public beforeSwapCount;

    modifier onlyOwner() {
        require(msg.sender == owner, "UNAUTHORISED");
        _;
    }

    constructor(IPoolManager _poolManager, address _feeRecipient, address _lending, address _owner)
        BaseHook(_poolManager)
    {
        lending = Lending(_lending);
        owner = _owner;
    }

    /**
     * @notice Define which hooks are implemented
     * @return Hooks.Permissions configuration
     */
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: true, // Track supported pools
            beforeAddLiquidity: false,
            afterAddLiquidity: false, // Track LP positions
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false, // Update LP positions
            beforeSwap: true, // Apply inverse range orders & check position health
            afterSwap: false, // Update positions after price changes
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function _afterInitialize(address, PoolKey calldata key, uint160 sqrtPriceX96, int24 tick)
        internal
        override
        onlyPoolManager
        returns (bytes4)
    {
        // setup lending market
        return (IHooks.afterInitialize.selector);
    }

    function _beforeSwap(address addr, PoolKey calldata key, IPoolManager.SwapParams calldata params, bytes calldata)
        internal
        override
        onlyPoolManager
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        beforeSwapCount[key.toId()]++;
        // do another swap
        IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
            zeroForOne: true,
            // amountSpecified: amountIn,
            amountSpecified: -int256(100 ether),
            // Set the price limit to be the least possible if swapping from Token 0 to Token 1
            // or the maximum possible if swapping from Token 1 to Token 0
            // i.e. infinite slippage allowed
            sqrtPriceLimitX96: true ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
        });

        // check how to do swap
        // _handleSwap(key, params);
        // only thing that happens in this function is trigger liquidation and sell
        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function _handleSwap(PoolKey calldata key, IPoolManager.SwapParams calldata params) internal {
        poolManager.take(
            params.zeroForOne ? key.currency1 : key.currency0, address(this), uint256(params.amountSpecified)
        );
    }

    function setLending(address _lender) public onlyOwner {
        lending = Lending(_lender);
    }

    function getHookData(address user) public pure returns (bytes memory) {
        return abi.encode(user);
    }
}
