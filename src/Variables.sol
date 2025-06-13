// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {PoolId} from "v4-core/src/types/PoolId.sol";

abstract contract Variables {
    struct VaultVariablesState {
        bool reEntrancy;
        /**
         * Is the current active branch liquidated?
         *  If true then check the branch's minima tick before creating a new position
         *  If the new tick is greater than minima tick then initialize a new branch,
         *  make that as current branch & do proper linking
         */
        bool currentBranchLiquidated;
        /**
         * 0 -> negative, 1 -> positive
         */
        int24 topMostTick;
        int32 currentBranchIds;
        int32 totalBranchIds;
        int64 totalSupply;
        int64 totalBorrow;
        int32 totalPositions;
        // depending on the current price tick needs to be adjusted
        int24 tickAdjustmentFactor;
    }

    struct VaultVariablesConfig {
        uint16 supplyRateMagnifier;
        uint16 borrowRateMagnifier;
        uint16 collateralFactor; // 800 = 0.8 = 80% (max precision of 0.1%)
        uint16 liquidationThreshold; // 900 = 0.9 = 90% (max precision of 0.1%)
        uint16 liquidationMaxLimit; // 950 = 0.95 = 95% (max precision of 0.1%) (above this 100% liquidation can happen)
        /**
         * 100 = 0.1 = 10%. (max precision of 0.1%) (max 7 bits can also suffice for the requirement here of 0.1% to 10%).
         *  Needed to save some limits on withdrawals so liquidate can work seamlessly.
         */
        uint16 withdrawGap;
        /**
         * 100 = 0.01 = 1%. (max precision of 0.01%) (max liquidation penantly can be 10.23%).
         *  Applies when tick is in between liquidation Threshold & liquidation Max Limit.
         */
        uint16 liquidationPenalty;
        /**
         * 100 = 0.01 = 1%. (max precision of 0.01%) (max borrow fee can be 10.23%). Fees on borrow.
         */
        uint16 borrowFee;
        uint40 lastUpdateTimestamp;
    }

    struct Position {
        bool isInitialized;
        bool isSupply; // true -> supply, false -> borrow
        int256 userTick; // true -> positive, false -> negative
        uint256 userTickId; // user's tick's id
        uint256 supplyAmount; // user's supply amount. Debt will be calculated through supply & ratio.
    }
    /**
     * User's dust debt amount. User's net debt = total debt - dust amount.
     *   Total debt is calculated through supply & ratio
     */
    // uint64 dustDebtAmount;
    /// User won't pay any extra interest on dust debt & hence we will not show it as a debt on UI. For user's there's no dust.

    struct TickData {
        bool isLiquidated; // true -> liquidated, false -> non liquidated
        uint24 totalIds; // total number of ids in the tick, start from 1
        // if tick wasn't liquidated
        uint256 rawDebt;
        // if tick was liquidated
        bool isFullyLiquidated; // true -> fully liquidated, false -> not fully liquidated
        uint256 branchId; // branch id where tick was liquidated
            // int40 debtFactorCoefficient; // debt factor of the tick not sure
            // int16 debtFactorExpansion; // debt factor expansion of the tick not sure
    }

    struct BranchData {
        uint8 state; // 0 -> not liquidated, 1 -> liquidated, 2 -> merged, 3 -> closed
        /// merged means the branch is merged into it's base branch
        /// closed means all the users are 100% liquidated
        int24 minimaTick;
        uint32 partialOfMinimaTick; // Partials of minima tick of branch this is connected to. 0 if master branch.
        /**
         * Debt liquidity at this branch.
         *   Similar to last's top tick data.
         *   Remaining debt will move here from tickData after first liquidation
         */
        uint64 debtLiquidity;
        uint56 connectionDebtFactor; // TODO: understand this. Connection/adjustment debt factor of this branch with the next branch.
        uint32 branchIdOfNextBranch; // if 0 this is master branch
        uint24 minimaTickOfNextBranch; // minima tick of branch this is connected to. 0 if master branch.
    }

    struct TickId {
        bool isFullyLiquidated;
        uint256 branchId;
        uint256 debtFactor; // TODO: figure out why you need this
    }

    struct Liquidity {
        uint256 deposited;
    }

    mapping(PoolId poolId => VaultVariablesState) public vaultVariables;

    mapping(PoolId poolId => VaultVariablesConfig) public vaultVariablesConfig;

    // uniswap poolId => nftId => positionData
    mapping(PoolId poolId => mapping(uint256 => Position)) public positionData;

    /// Tick has debt only keeps data of non liquidated positions. liquidated tick's data stays in branch itself
    /// poolId => tick parent => uint (represents bool for 256 children)
    /// parent of (i)th tick:-
    /// if (i>=0) (i / 256);
    /// else ((i + 1) / 256) - 1
    /// first bit of the variable is the smallest tick & last bit is the biggest tick of that slot
    mapping(PoolId poolId => mapping(int256 => uint256)) public tickHasDebt;

    /// mapping tickId => tickData
    /// Tick related data. Total debt & other things
    mapping(PoolId poolId => mapping(int256 => TickData)) public tickData;

    // uniswap poolid => tick => tickId => tickId
    // tickId starts from 1
    mapping(PoolId poolId => mapping(int256 => mapping(uint256 => TickId))) public tickId;

    // liquidity
    mapping(PoolId poolId => mapping(address => Liquidity)) public liquidity;
}
