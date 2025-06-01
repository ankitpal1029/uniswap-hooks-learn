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
import {IERC20} from "v4-core/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

// import {Lending}  from "../../src/LendingHook.sol";

contract LendingHookTest is Test, GasSnapshot, Fixtures {
    // use libs
    using EasyPosm for IPositionManager;
    using StateLibrary for IPoolManager;

    LendingHook hook;
    PoolId poolId;

    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;

    // Currency currency0;
    // Currency currency1;

    function setUp() public {
        // creates the pool manager, utility routers, and test tokens
        deployFreshManagerAndRouters();
        (currency0, currency1) = deployMintAndApprove2Currencies();

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
        console.log("LendingHook address:", address(hook));
        console.log("Currency0(WETH):", Currency.unwrap(currency0));
        console.log("Currency1(USDC):", Currency.unwrap(currency1));

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

    // function testSwapInternal() public {
    //     assertEq(hook.beforeSwapCount(poolId), 0);

    //     bool zeroForOne = true;
    //     int256 amountSpecified = -1e18; // negative number indicates exact input swap!

    //     (uint160 sqrtPriceX96Before,,,) = manager.getSlot0(poolId);
    //     assertEq(sqrtPriceX96Before, 79228162514264337593543950336);

    //     IERC20(Currency.unwrap(tokenA)).transfer(address(hook), 2e18);
    //     // IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
    //     //     zeroForOne: true,
    //     //     // amountSpecified: amountIn,
    //     //     amountSpecified: -int256(100 ether),
    //     //     // Set the price limit to be the least possible if swapping from Token 0 to Token 1
    //     //     // or the maximum possible if swapping from Token 1 to Token 0
    //     //     // i.e. infinite slippage allowed
    //     //     sqrtPriceLimitX96: true ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
    //     // });

    //     // BalanceDelta swapDelta = _handleSwap(key, swapParams);
    //     BalanceDelta swapDelta = swap(key, zeroForOne, amountSpecified, ZERO_BYTES);
    //     // Log price before swap
    //     (uint160 sqrtPriceX96After,,,) = manager.getSlot0(poolId);
    //     assertEq(sqrtPriceX96After, 78446055342499616417857907004);
    // }

    function testSupply() public {}
}
