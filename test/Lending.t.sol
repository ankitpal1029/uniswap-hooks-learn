// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {EasyPosm} from "./utils/EasyPosm.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {Fixtures} from "./utils/Fixtures.sol";
import {LendingHook} from "../src/LendingHook.sol";
import {LendingHookStub} from "./LendingHookStub.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";

contract LendingHookTest is Test, GasSnapshot, Fixtures {
    // use libs
    using EasyPosm for IPositionManager;
    using StateLibrary for IPoolManager;

    LendingHook hook;
    PoolId poolId;

    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;

    Currency tokenA;
    Currency tokenB;

    function setUp() public {
        // creates the pool manager, utility routers, and test tokens
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();

        deployAndApprovePosm(manager);

        // Deploy the hook to an address with the correct flags
        address flags = address(
            uint160(Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG) ^ (0x4444 << 144) // Namespace the hook to avoid collisions
        );
        bytes memory constructorArgs = abi.encode(
            manager, // _poolManager
            address(0), // _feeRecipient (set to zero address for now)
            address(0), // _lending (set to zero address for now)
            address(this) // _owner (set to test contract for testing)); //Add all the necessary constructor arguments from the hook
        );
        deployCodeTo("LendingHook.sol:LendingHook", constructorArgs, flags);
        hook = LendingHook(flags);

        // Create the pool
        key = PoolKey(currency0, currency1, 3000, 60, IHooks(hook));
        poolId = key.toId();
        manager.initialize(key, SQRT_PRICE_1_1);

        // Provide full-range liquidity to the pool
        tickLower = TickMath.minUsableTick(key.tickSpacing);
        tickUpper = TickMath.maxUsableTick(key.tickSpacing);

        uint128 liquidityAmount = 100e18;

        (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts.getAmountsForLiquidity(
            SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidityAmount
        );

        (tokenId,) = posm.mint(
            key,
            tickLower,
            tickUpper,
            liquidityAmount,
            amount0Expected + 1,
            amount1Expected + 1,
            address(this),
            block.timestamp,
            ZERO_BYTES
        );
    }

    function testCounterHooks() public {
        assertEq(hook.beforeSwapCount(poolId), 0);

        bool zeroForOne = true;
        int256 amountSpecified = -1e18; // negative number indicates exact input swap!
        BalanceDelta swapDelta = swap(key, zeroForOne, amountSpecified, ZERO_BYTES);
        // Log price before swap
        (uint160 sqrtPriceX96Before, int24 tickBefore, uint24 protocolFeeBefore, uint24 swapFeeBefore) =
            manager.getSlot0(poolId);
        console.log("Before swap:");
        console.log("sqrtPriceX96:", sqrtPriceX96Before);
        console.log("tick:", tickBefore);
        console.log("protocolFee:", protocolFeeBefore);
        console.log("swapFee:", swapFeeBefore);

        // Calculate and log actual price before swap (with proper decimal handling)
        // price = (sqrtPriceX96 * sqrtPriceX96) / (2^192)
        // Then adjust for decimals: price = price * 10^18 / 10^18
        uint256 priceBefore = (uint256(sqrtPriceX96Before) * uint256(sqrtPriceX96Before)) >> 192;
        console.log("price (token1/token0) raw:", priceBefore);
        console.log("price (token1/token0) in decimals:", priceBefore * 1e18 / (1e18)); // This will show the actual price with 18 decimals

        // Perform your swap
        uint256 swapAmount = 100 ether;
        swap(key, true, -int256(swapAmount), ZERO_BYTES);

        // Log price after swap
        (uint160 sqrtPriceX96After, int24 tickAfter, uint24 protocolFeeAfter, uint24 swapFeeAfter) =
            manager.getSlot0(poolId);
        console.log("sqrtPriceX96After", sqrtPriceX96After);
        console.log("tickAfter", tickAfter);
        console.log("protocolFeeAfter", protocolFeeAfter);
        console.log("swapFeeAfter", swapFeeAfter);

        // assertEq(int256(swapDelta.amount0()), amountSpecified);

        // assertEq(hook.beforeSwapCount(poolId), 1);
    }
}
