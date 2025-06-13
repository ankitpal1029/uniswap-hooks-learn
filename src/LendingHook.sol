// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/console.sol";
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
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {ILending} from "./interfaces/ILending.sol";
import {ERC721} from "v4-periphery/lib/permit2/lib/solmate/src/tokens/ERC721.sol";
import {Variables} from "./Variables.sol";
import {Variables} from "./Variables.sol";
import {RatioTickMath} from "./lib/RatioTickMath.sol";

contract LendingHook is BaseHook, ILending, ERC721, Variables {
    using CurrencyLibrary for Currency;
    using SafeERC20 for IERC20;
    using StateLibrary for IPoolManager;

    enum PositionStatus {
        INACTIVE,
        ACTIVE,
        LIQUIDATING
    }

    address owner;

    uint256 public constant LIQUIDATION_THRESHOLD = 9000; // 90% threshold
    uint256 public constant LIQUIDATION_MAX_LIMIT = 9500; // 95% max limit

    mapping(PoolId => uint256 count) public beforeSwapCount;

    modifier onlyOwner() {
        require(msg.sender == owner, "UNAUTHORISED");
        _;
    }

    constructor(
        IPoolManager _poolManager,
        address _feeRecipient,
        address _owner,
        string memory _nftName,
        string memory _nftSymbol
    ) BaseHook(_poolManager) ERC721(_nftName, _nftSymbol) {
        owner = _owner;
        poolManager = _poolManager;
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
            beforeSwap: false, // Apply inverse range orders & check position health
            afterSwap: true, // Update positions after price changes
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function _afterInitialize(address, PoolKey calldata _key, uint160 _sqrtPriceX96, int24 _tick)
        internal
        override
        onlyPoolManager
        returns (bytes4)
    {
        // setup lending market
        return (IHooks.afterInitialize.selector);
    }

    function _afterSwap(
        address,
        PoolKey calldata _key,
        IPoolManager.SwapParams calldata _params,
        BalanceDelta,
        bytes calldata
    ) internal override onlyPoolManager returns (bytes4, int128) {
        (, int24 currentTick,,) = poolManager.getSlot0(_key.toId());

        int24 currentTickLower = _getTickLower(currentTick, _key.tickSpacing);

        getVaultVariables(_key.toId());
        // int24 newAdjustmentFactor = lending.getVaultVariables(_key.toId()).tickAdjustmentFactor;
        return (IHooks.afterSwap.selector, 0);

        // adjust tick adjustment factor based on price
        // now go through tickHasDebt
    }

    function _checkLiquidateable() internal {}

    function _getTickLower(int24 actualTick, int24 tickSpacing) public pure returns (int24) {
        int24 intervals = actualTick / tickSpacing;
        if (actualTick < 0 && (actualTick % tickSpacing) != 0) {
            intervals--;
        }
        return intervals * tickSpacing;
    }

    function _handleSwap(PoolKey calldata _key, IPoolManager.SwapParams calldata _params)
        internal
        returns (BalanceDelta)
    {
        // conducting the swap inside the pool manager
        BalanceDelta delta = poolManager.swap(_key, _params, "");
        // if swap is zeroForOne
        // send token0 to poolManager , receive token1 from poolManager
        if (_params.zeroForOne) {
            // negative value -> token is transferred from user's wallet

            if (delta.amount0() < 0) {
                // settle it with poolManager
                _settle(_key.currency0, uint128(-delta.amount0()));
            }

            // positive value -> token is transfered from poolManager

            if (delta.amount1() > 0) {
                // take the token from poolManager
                _take(_key.currency1, uint128(delta.amount1()));
            }
        } else {
            // negative value -> token is transferred from user's wallet

            if (delta.amount1() < 0) {
                // settle it with poolManager
                _settle(_key.currency1, uint128(delta.amount1()));
            }

            // positive value -> token is transfered from poolManager

            if (delta.amount0() > 0) {
                // take the token from poolManager
                _take(_key.currency0, uint128(delta.amount0()));
            }
        }

        return delta;
    }

    function _settle(Currency _currency, uint128 _amount) internal {
        poolManager.sync(_currency);
        // transfer the toke to poolManager
        _currency.transfer(address(poolManager), _amount);
        // notify the poolManager
        poolManager.settle();
    }

    function _take(Currency _currency, uint128 _amount) internal {
        poolManager.take(_currency, address(this), _amount);
    }

    // function setLending(address _lender) public onlyOwner {
    //     lending = Lending(_lender);
    // }

    function getHookData(address _user) public pure returns (bytes memory) {
        return abi.encode(_user);
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        return "yangit-lend.com";
    }

    function supply(uint256 _nftId, PoolKey calldata _key, uint256 _amt) external {
        // check if that nftId exists if not create nft and give it to msg.sender
        Position memory _positionInfo = positionData[_key.toId()][_nftId];

        IERC20(Currency.unwrap(_key.currency0)).transferFrom(msg.sender, address(this), _amt);

        // TODO: case where position is already liquidated but now you want to add more funds to start new position
        if (_positionInfo.isInitialized) {
            if (_positionInfo.isSupply) {
                positionData[_key.toId()][_nftId] = Position({
                    isInitialized: true,
                    isSupply: _positionInfo.isSupply,
                    userTick: 0,
                    userTickId: _positionInfo.userTickId,
                    supplyAmount: _positionInfo.supplyAmount + _amt
                });
            } else {
                // TODO: account for existing liquidations, how much collateral is left, modify user tick etc
                positionData[_key.toId()][_nftId] = Position({
                    isInitialized: true,
                    isSupply: _positionInfo.isSupply,
                    userTick: 0, // TODO: update this tick based on new supply and existing debt
                    userTickId: _positionInfo.userTickId,
                    supplyAmount: _positionInfo.supplyAmount + _amt
                });
            }
        } else {
            positionData[_key.toId()][_nftId] =
                Position({isInitialized: true, isSupply: true, userTick: 0, userTickId: 0, supplyAmount: _amt});

            _safeMint(msg.sender, _nftId);
        }
    }

    function borrow(uint256 _nftId, PoolKey calldata _key, uint256 _amt) external {
        // check if nft is owned by msg.sender
        require(ownerOf(_nftId) == msg.sender, "invalid owner");

        Position memory _existingPosition = positionData[_key.toId()][_nftId];

        if (_existingPosition.isSupply) {
            uint256 ratioX96 = (_amt * RatioTickMath.ZERO_TICK_SCALED_RATIO) / _existingPosition.supplyAmount;
            (int256 tick,) = RatioTickMath.getTickAtRatio(ratioX96);

            // TODO: check if the ratio is within limits?
            // max ratio 0.95
            // threshold ratio 0.9

            TickData memory _tickData = tickData[_key.toId()][tick];

            tickData[_key.toId()][tick + vaultVariables[_key.toId()].tickAdjustmentFactor] = TickData({
                isLiquidated: _tickData.isLiquidated,
                totalIds: _tickData.totalIds + 1,
                rawDebt: _tickData.rawDebt + _amt,
                isFullyLiquidated: _tickData.isFullyLiquidated,
                branchId: _tickData.branchId
            });
            positionData[_key.toId()][_nftId] = Position({
                isInitialized: true,
                isSupply: false,
                userTick: tick,
                userTickId: _tickData.totalIds + 1,
                supplyAmount: _existingPosition.supplyAmount
            });
        } else {
            TickData memory _tickData = tickData[_key.toId()][_existingPosition.userTick];

            // TODO: if either of these are true it means position is liquidated, whole other branch of things to be done
            if (_tickData.isLiquidated || _tickData.totalIds > _existingPosition.userTickId) {}

            // TODO: check if the new ratio is within limits? if not liquidated already
            // max ratio 0.95
            // threshold ratio 0.9

            tickData[_key.toId()][_existingPosition.userTick] = TickData({
                isLiquidated: _tickData.isLiquidated,
                totalIds: _tickData.totalIds - 1,
                rawDebt: _tickData.rawDebt + _amt,
                isFullyLiquidated: _tickData.isFullyLiquidated,
                branchId: _tickData.branchId
            });
        }

        // last step
        IERC20(Currency.unwrap(_key.currency1)).transfer(msg.sender, _amt);
    }

    function repay() external {}

    function withdraw() external {}

    function earn(PoolKey calldata _key, uint256 _amt, address _receiver) external {
        // use _key to pull curreny1 funds
        // TODO: think about handling interest for this later need to figure out how to do interest logic on loans too
        IERC20(Currency.unwrap(_key.currency1)).transferFrom(msg.sender, address(this), _amt);

        liquidity[_key.toId()][_receiver].deposited += _amt;
    }

    function modifyVaultVariables(VaultVariablesState memory _vaultVariablesState, PoolKey calldata _key) public {
        vaultVariables[_key.toId()] = _vaultVariablesState;
    }

    function getVaultVariables(PoolId _id) public view returns (VaultVariablesState memory) {
        console.logInt(vaultVariables[_id].tickAdjustmentFactor);
        return vaultVariables[_id];
    }

    function fetchPosition() public {
        // TODO: needs to navigate liquidation, interest calculation, etc
    }
}
