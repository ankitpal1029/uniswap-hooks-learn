// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
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
        (tokenA, tokenB) = deployMintAndApprove2Currencies();

        deployAndApprovePosm(manager);

        // Deploy the hook to an address with the correct flags
        address flags = address(
            uint160(Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG) ^ (0x4444 << 144) // Namespace the hook to avoid collisions
        );
        bytes memory constructorArgs = abi.encode(manager); //Add all the necessary constructor arguments from the hook
        deployCodeTo("LendingHook.sol:LendingHook", constructorArgs, flags);
        hook = LendingHook(flags);
        // pointsToken = hook.pointsToken();

        // Create the pool
        key = PoolKey(Currency.wrap(address(0)), currency1, 3000, 60, IHooks(hook));
        poolId = key.toId();
        manager.initialize(key, SQRT_PRICE_1_1);

        // Provide full-range liquidity to the pool
        tickLower = TickMath.minUsableTick(key.tickSpacing);
        tickUpper = TickMath.maxUsableTick(key.tickSpacing);

        deal(address(this), 200 ether);

        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            uint128(100e18)
        );

        (tokenId,) = posm.mint(
            key,
            tickLower,
            tickUpper,
            100e18,
            amount0 + 1,
            amount1 + 1,
            address(this),
            block.timestamp,
            hook.getHookData(address(this))
        );
    }
}
