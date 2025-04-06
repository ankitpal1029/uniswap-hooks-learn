// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {IPoolManager} from "v4-periphery/lib/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-periphery/lib/v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "v4-periphery/lib/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-periphery/lib/v4-core/src/types/BalanceDelta.sol";
import {TickMath} from "v4-periphery/lib/v4-core/src/libraries/TickMath.sol";
import {Currency, CurrencyLibrary} from "v4-periphery/lib/v4-core/src/types/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title LendingHook
 * @notice Implements an oracleless lending protocol using Uniswap V4 hooks
 * @dev This hook enables borrowing against collateral with inverse range orders for liquidation
 */
contract LendingHook is BaseHook {
    using CurrencyLibrary for Currency;
    using SafeERC20 for IERC20;

    // Position status enum
    enum PositionStatus {
        INACTIVE,
        ACTIVE,
        LIQUIDATING
    }

    // Borrowing position struct
    struct Position {
        address owner;
        uint256 collateralAmount;   // Amount of collateral token
        uint256 borrowAmount;       // Amount of borrowed token
        uint256 liquidationThreshold; // 5000-9900 for 50%-99%
        int24 lowerTick;           // Lower tick for inverse range
        int24 upperTick;           // Upper tick for inverse range
        uint256 lastUpdateTime;     // Last time position was updated
        PositionStatus status;      // Position status
        uint256 liquidationPenaltyAccrued; // Accrued penalty during liquidation
    }

    // Maps position IDs to Position structs
    mapping(bytes32 => Position) public positions;
    
    // Maps pools to supported status
    mapping(bytes32 => bool) public supportedPools;
    
    // Maps liquidation thresholds to annual penalty rates (in basis points)
    // Higher LT = higher risk = higher penalty rate
    mapping(uint256 => uint256) public penaltyRates;
    
    // Maps tokens to their lend balance (deposited for lending)
    mapping(Currency => uint256) public lendBalances;
    
    // Maps users to their lend balances per token
    mapping(address => mapping(Currency => uint256)) public userLendBalances;
    
    // Protocol fee in basis points (e.g., 1000 = 10%)
    uint256 public protocolFeeBps = 1000;
    
    // Protocol fee recipient
    address public feeRecipient;

    // Events
    event PositionCreated(bytes32 indexed positionId, address indexed owner, uint256 collateralAmount, uint256 borrowAmount, uint256 liquidationThreshold);
    event PositionRepaid(bytes32 indexed positionId, uint256 repaidAmount);
    event PositionLiquidating(bytes32 indexed positionId, uint256 collateralRemaining, uint256 borrowRemaining);
    event PositionLiquidated(bytes32 indexed positionId);
    event TokenDeposited(address indexed user, Currency indexed token, uint256 amount);
    event TokenWithdrawn(address indexed user, Currency indexed token, uint256 amount);
    event PenaltyAccrued(bytes32 indexed positionId, uint256 penaltyAmount);

    /**
     * @notice Constructor
     * @param _poolManager The Uniswap V4 pool manager
     * @param _feeRecipient Address to receive protocol fees
     */
    constructor(IPoolManager _poolManager, address _feeRecipient) BaseHook(_poolManager) {
        require(_feeRecipient != address(0), "Invalid fee recipient");
        feeRecipient = _feeRecipient;
        
        // Initialize penalty rates for different liquidation thresholds
        // Higher liquidation threshold = higher penalty rate
        penaltyRates[5000] = 500;  // 5% annual penalty for 50% LT
        penaltyRates[6000] = 750;  // 7.5% annual penalty for 60% LT
        penaltyRates[7000] = 1000; // 10% annual penalty for 70% LT
        penaltyRates[8000] = 1250; // 12.5% annual penalty for 80% LT
        penaltyRates[9000] = 1500; // 15% annual penalty for 90% LT
        penaltyRates[9500] = 1750; // 17.5% annual penalty for 95% LT
        penaltyRates[9900] = 2000; // 20% annual penalty for 99% LT
    }

    /**
     * @notice Define which hooks are implemented
     * @return Hooks.Permissions configuration
     */
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: true,  // Track supported pools
            beforeAddLiquidity: false,
            afterAddLiquidity: true,  // Track LP positions
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: true,  // Update LP positions
            beforeSwap: true,  // Apply inverse range orders & check position health
            afterSwap: true,   // Update positions after price changes
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    /**
     * @notice Add a pool to supported pools
     * @param key The Uniswap V4 pool key
     */
    function addSupportedPool(PoolKey calldata key) external {
        // Should add access control
        bytes32 poolId = _getPoolId(key);
        supportedPools[poolId] = true;
    }

    /**
     * @notice Deposit tokens for lending
     * @param token The token to deposit
     * @param amount The amount to deposit
     */
    function depositTokenForLending(Currency token, uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0");
        
        // Transfer tokens from user to contract
        IERC20(token.toAddress()).safeTransferFrom(msg.sender, address(this), amount);
        
        // Update balances
        lendBalances[token] += amount;
        userLendBalances[msg.sender][token] += amount;
        
        emit TokenDeposited(msg.sender, token, amount);
    }

    /**
     * @notice Withdraw tokens from lending
     * @param token The token to withdraw
     * @param amount The amount to withdraw
     */
    function withdrawTokenFromLending(Currency token, uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0");
        require(userLendBalances[msg.sender][token] >= amount, "Insufficient balance");
        
        // Ensure there's enough available liquidity (not borrowed)
        uint256 availableLiquidity = IERC20(token.toAddress()).balanceOf(address(this));
        require(availableLiquidity >= amount, "Insufficient liquidity");
        
        // Update balances
        lendBalances[token] -= amount;
        userLendBalances[msg.sender][token] -= amount;
        
        // Transfer tokens to user
        IERC20(token.toAddress()).safeTransfer(msg.sender, amount);
        
        emit TokenWithdrawn(msg.sender, token, amount);
    }

    /**
     * @notice Create a borrowing position
     * @param key The Uniswap V4 pool key
     * @param collateralAmount Amount of collateral to deposit
     * @param borrowAmount Amount to borrow
     * @param liquidationThreshold Liquidation threshold (5000-9900)
     * @return positionId The ID of the created position
     */
    function createBorrowingPosition(
        PoolKey calldata key,
        uint256 collateralAmount,
        uint256 borrowAmount,
        uint256 liquidationThreshold
    ) external returns (bytes32 positionId) {
        // Validate pool is supported
        bytes32 poolId = _getPoolId(key);
        require(supportedPools[poolId], "Pool not supported");
        
        // Validate parameters
        require(collateralAmount > 0, "Collateral amount must be greater than 0");
        require(borrowAmount > 0, "Borrow amount must be greater than 0");
        require(liquidationThreshold >= 5000 && liquidationThreshold <= 9900, "Invalid liquidation threshold");
        
        // Verify sufficient lending liquidity is available
        Currency borrowCurrency = key.currency1;
        require(IERC20(borrowCurrency.toAddress()).balanceOf(address(this)) >= borrowAmount, "Insufficient lending liquidity");
        
        // Calculate appropriate inverse range
        (int24 lowerTick, int24 upperTick) = _calculateInverseRangeTicks(key, liquidationThreshold);
        
        // Transfer collateral from user to contract
        IERC20(key.currency0.toAddress()).safeTransferFrom(msg.sender, address(this), collateralAmount);
        
        // Generate position ID
        positionId = keccak256(abi.encodePacked(msg.sender, poolId, block.timestamp));
        
        // Create position
        positions[positionId] = Position({
            owner: msg.sender,
            collateralAmount: collateralAmount,
            borrowAmount: borrowAmount,
            liquidationThreshold: liquidationThreshold,
            lowerTick: lowerTick,
            upperTick: upperTick,
            lastUpdateTime: block.timestamp,
            status: PositionStatus.ACTIVE,
            liquidationPenaltyAccrued: 0
        });
        
        // Transfer borrowed tokens to user
        IERC20(borrowCurrency.toAddress()).safeTransfer(msg.sender, borrowAmount);
        
        emit PositionCreated(positionId, msg.sender, collateralAmount, borrowAmount, liquidationThreshold);
        
        return positionId;
    }

    /**
     * @notice Repay a borrowing position
     * @param positionId ID of the position to repay
     * @param repayAmount Amount to repay
     */
    function repayBorrowingPosition(bytes32 positionId, uint256 repayAmount) external {
        Position storage position = positions[positionId];
        
        // Validate position
        require(position.status != PositionStatus.INACTIVE, "Position not active");
        require(position.owner == msg.sender, "Not position owner");
        require(repayAmount > 0, "Repay amount must be greater than 0");
        require(repayAmount <= position.borrowAmount, "Repay amount exceeds borrowed amount");
        
        // Update position before repayment
        _updatePositionStatus(positionId);
        
        // Calculate repayable amount
        uint256 remainingBorrowAmount = position.borrowAmount;
        uint256 amountToRepay = repayAmount > remainingBorrowAmount ? remainingBorrowAmount : repayAmount;
        
        // Transfer repayment from user
        PoolKey storage key = _getPoolKeyFromPosition(positionId);
        IERC20(key.currency1.toAddress()).safeTransferFrom(msg.sender, address(this), amountToRepay);
        
        // Update position
        position.borrowAmount -= amountToRepay;
        
        // If fully repaid, return collateral and close position
        if (position.borrowAmount == 0) {
            uint256 remainingCollateral = position.collateralAmount - position.liquidationPenaltyAccrued;
            
            // Transfer remaining collateral back to user
            if (remainingCollateral > 0) {
                IERC20(key.currency0.toAddress()).safeTransfer(position.owner, remainingCollateral);
            }
            
            // Close position
            position.status = PositionStatus.INACTIVE;
        }
        
        emit PositionRepaid(positionId, amountToRepay);
    }

    /**
     * @notice Calculate the inverse range ticks based on liquidation threshold
     * @param key The pool key
     * @param liquidationThreshold The liquidation threshold (5000-9900)
     * @return lowerTick The lower tick of the range
     * @return upperTick The upper tick of the range
     */
    function _calculateInverseRangeTicks(
        PoolKey calldata key,
        uint256 liquidationThreshold
    ) internal view returns (int24 lowerTick, int24 upperTick) {
        // Get current price from pool
        (uint160 sqrtPriceX96, int24 currentTick, , , , , ) = poolManager.getSlot0(key);
        
        // Calculate liquidation price tick based on liquidation threshold
        // For example, if LT is 80% and current tick represents $3000,
        // we want ticks that represent $2400-$3000 range
        
        // Higher LT = narrower range
        uint16 tickSpread = uint16(10000 - liquidationThreshold);
        
        // Convert LT to tick distance (simplified calculation)
        // In a real implementation, this would need more precise math
        int24 tickDistance = int24(currentTick * tickSpread / 10000);
        
        // Borrowing against token0, create inverse range when token0 price falls
        // Lower tick = liquidation boundary
        lowerTick = currentTick - tickDistance;
        upperTick = currentTick;
        
        // Ensure ticks are within valid range and properly spaced
        lowerTick = _roundTickToSpacing(lowerTick, key.tickSpacing);
        upperTick = _roundTickToSpacing(upperTick, key.tickSpacing);
        
        return (lowerTick, upperTick);
    }

    /**
     * @notice Round a tick to the nearest valid tick based on spacing
     * @param tick The tick to round
     * @param spacing The tick spacing
     * @return The rounded tick
     */
    function _roundTickToSpacing(int24 tick, int24 spacing) internal pure returns (int24) {
        int24 rounded = (tick / spacing) * spacing;
        return rounded;
    }

    /**
     * @notice Check if a position is in liquidation state
     * @param positionId The position ID to check
     * @return True if in liquidation state
     */
    function isPositionInLiquidation(bytes32 positionId) public view returns (bool) {
        Position storage position = positions[positionId];
        if (position.status == PositionStatus.INACTIVE) return false;
        
        PoolKey memory key = _getPoolKeyFromPosition(positionId);
        (uint160 sqrtPriceX96, int24 currentTick, , , , , ) = poolManager.getSlot0(key);
        
        return currentTick >= position.lowerTick && currentTick < position.upperTick;
    }

    /**
     * @notice Update a position's status based on current price
     * @param positionId The position ID to update
     */
    function _updatePositionStatus(bytes32 positionId) internal {
        Position storage position = positions[positionId];
        if (position.status == PositionStatus.INACTIVE) return;
        
        bool wasInLiquidation = position.status == PositionStatus.LIQUIDATING;
        bool isInLiquidation = isPositionInLiquidation(positionId);
        
        // Position entering liquidation
        if (!wasInLiquidation && isInLiquidation) {
            position.status = PositionStatus.LIQUIDATING;
            position.lastUpdateTime = block.timestamp;
            
            emit PositionLiquidating(positionId, position.collateralAmount, position.borrowAmount);
        }
        // Position exiting liquidation
        else if (wasInLiquidation && !isInLiquidation) {
            // Apply final penalty calculation
            _applyLiquidationPenalty(positionId);
            
            position.status = PositionStatus.ACTIVE;
        }
        // Position still in liquidation
        else if (wasInLiquidation && isInLiquidation) {
            // Apply penalty for time since last update
            _applyLiquidationPenalty(positionId);
        }
    }

    /**
     * @notice Apply liquidation penalty to a position
     * @param positionId The position ID
     */
    function _applyLiquidationPenalty(bytes32 positionId) internal {
        Position storage position = positions[positionId];
        if (position.status != PositionStatus.LIQUIDATING) return;
        
        uint256 timeDelta = block.timestamp - position.lastUpdateTime;
        if (timeDelta == 0) return;
        
        // Get penalty rate based on liquidation threshold
        uint256 penaltyRate = getPenaltyRate(position.liquidationThreshold);
        
        // Calculate penalty: annualRate * timeDelta / 365 days
        uint256 penalty = position.collateralAmount * penaltyRate * timeDelta / (365 days * 10000);
        
        // Update position
        position.liquidationPenaltyAccrued += penalty;
        position.lastUpdateTime = block.timestamp;
        
        // If penalty exceeds collateral, fully liquidate position
        if (position.liquidationPenaltyAccrued >= position.collateralAmount) {
            _fullyLiquidatePosition(positionId);
        }
        
        emit PenaltyAccrued(positionId, penalty);
    }

    /**
     * @notice Fully liquidate a position (when penalties exceed collateral)
     * @param positionId The position ID to liquidate
     */
    function _fullyLiquidatePosition(bytes32 positionId) internal {
        Position storage position = positions[positionId];
        
        // Mark as inactive
        position.status = PositionStatus.INACTIVE;
        
        // Collateral is fully consumed by penalties
        position.collateralAmount = 0;
        
        emit PositionLiquidated(positionId);
    }

    /**
     * @notice Get penalty rate for a given liquidation threshold
     * @param liquidationThreshold The liquidation threshold
     * @return The annual penalty rate in basis points
     */
    function getPenaltyRate(uint256 liquidationThreshold) public view returns (uint256) {
        // Find the nearest threshold
        uint256 thresholds = 5000;
        uint256 rate = penaltyRates[5000]; // Default to lowest rate
        
        while (thresholds <= 9900) {
            if (liquidationThreshold <= thresholds) {
                return penaltyRates[thresholds];
            }
            
            if (thresholds == 5000) thresholds = 6000;
            else if (thresholds == 6000) thresholds = 7000;
            else if (thresholds == 7000) thresholds = 8000;
            else if (thresholds == 8000) thresholds = 9000;
            else if (thresholds == 9000) thresholds = 9500;
            else if (thresholds == 9500) thresholds = 9900;
            else break;
        }
        
        return rate;
    }

    /**
     * @notice Get pool ID from a pool key
     * @param key The pool key
     * @return The pool ID
     */
    function _getPoolId(PoolKey calldata key) internal pure returns (bytes32) {
        return keccak256(abi.encode(key));
    }

    /**
     * @notice Get pool key for a position
     * @param positionId The position ID
     * @return The pool key
     */
    function _getPoolKeyFromPosition(bytes32 positionId) internal view returns (PoolKey memory) {
        // In a real implementation, you would store a mapping from positionId to poolKey
        // This is a placeholder
        revert("Not implemented");
    }

    /*************************************************************************
     *                           HOOK IMPLEMENTATIONS                         *
     *************************************************************************/

    /**
     * @notice After initialize hook
     * @dev Called after a pool is initialized
     */
    function afterInitialize(
        address sender,
        PoolKey calldata key,
        uint160 sqrtPriceX96,
        int24 tick,
        bytes calldata hookData
    ) external override returns (bytes4) {
        // Track supported pools
        bytes32 poolId = _getPoolId(key);
        // Additional logic if needed
        
        return BaseHook.afterInitialize.selector;
    }

    /**
     * @notice Before swap hook - check positions and apply inverse range effects
     * @dev Called before a swap is executed
     */
    function beforeSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) external override returns (bytes4) {
        bytes32 poolId = _getPoolId(key);
        
        // Only process for supported pools
        if (!supportedPools[poolId]) {
            return BaseHook.beforeSwap.selector;
        }
        
        // In a real implementation, you'd efficiently track all positions for this pool
        // and update their status before the swap
        
        // This is a conceptual placeholder
        // for (each position in this pool) {
        //     _updatePositionStatus(positionId);
        // }
        
        return BaseHook.beforeSwap.selector;
    }

    /**
     * @notice After swap hook - update positions after price changes
     * @dev Called after a swap is executed
     */
    function afterSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) external override returns (bytes4) {
        bytes32 poolId = _getPoolId(key);
        
        // Only process for supported pools
        if (!supportedPools[poolId]) {
            return BaseHook.afterSwap.selector;
        }
        
        // In a real implementation, update all affected positions
        // for (each position in this pool) {
        //     _updatePositionStatus(positionId);
        // }
        
        return BaseHook.afterSwap.selector;
    }

    /**
     * @notice After add liquidity hook - track LP positions
     * @dev Called after liquidity is added to a pool
     */
    function afterAddLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        BalanceDelta fees,
        bytes calldata hookData
    ) external override returns (bytes4) {
        // Implementation for tracking LP positions
        // This could be used to track liquidity providers who earn penalty fees
        
        return BaseHook.afterAddLiquidity.selector;
    }

    /**
     * @notice After remove liquidity hook - update LP positions
     * @dev Called after liquidity is removed from a pool
     */
    function afterRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        BalanceDelta fees,
        bytes calldata hookData
    ) external override returns (bytes4) {
        // Implementation for updating LP positions
        
        return BaseHook.afterRemoveLiquidity.selector;
    }
} 