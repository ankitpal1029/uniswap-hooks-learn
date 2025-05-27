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
            afterAddLiquidity: true, // Track LP positions
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: true, // Update LP positions
            beforeSwap: true, // Apply inverse range orders & check position health
            afterSwap: true, // Update positions after price changes
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function setLending(address _lender) public onlyOwner {
        lending = Lending(_lender);
    }

    function getHookData(address user) public pure returns (bytes memory) {
        return abi.encode(user);
    }
}
