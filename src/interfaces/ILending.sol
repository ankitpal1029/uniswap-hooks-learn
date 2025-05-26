// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Currency, CurrencyLibrary} from "v4-periphery/lib/v4-core/src/types/Currency.sol";
import {PoolKey} from "v4-periphery/lib/v4-core/src/types/PoolKey.sol";

interface ILending {
    // /**
    //  * @notice Deposit tokens for lending
    //  * @param token The token to deposit
    //  * @param amount The amount to deposit
    //  */
    // function supply(Currency token, uint256 amount) external;

    // /**
    //  * @notice Withdraw tokens from lending
    //  * @param token The token to withdraw
    //  * @param amount The amount to withdraw
    //  */
    // function withdraw(Currency token, uint256 amount) external;

    // /**
    //  * @notice Create a borrowing position
    //  * @param key The Uniswap V4 pool key
    //  * @param collateralAmount Amount of collateral to deposit
    //  * @param borrowAmount Amount to borrow
    //  * @param liquidationThreshold Liquidation threshold (5000-9900)
    //  * @return positionId The ID of the created position
    //  */
    // function borrow(PoolKey calldata key, uint256 collateralAmount, uint256 borrowAmount, uint256 liquidationThreshold)
    //     external
    //     returns (bytes32 positionId);

    // /**
    //  * @notice Repay a borrowing position
    //  * @param positionId ID of the position to repay
    //  * @param repayAmount Amount to repay
    //  */
    // function repay(bytes32 positionId, uint256 repayAmount) external;

    function supply() external;
        
    function borrow() external;
    
    function repay() external;
    
    function withdraw() external;
}
