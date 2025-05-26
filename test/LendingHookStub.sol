// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {LendingHook} from "../src/LendingHook.sol";
import {IPoolManager} from "v4-periphery/lib/v4-core/src/interfaces/IPoolManager.sol";
import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";

contract LendingHookStub is LendingHook {
    constructor(IPoolManager _poolManager, address _feeRecipient, address _lending, address _owner)
        LendingHook(_poolManager, _feeRecipient, _lending, _owner)
    {}

    function validateHookAddress(BaseHook _this) internal pure override {}
}
