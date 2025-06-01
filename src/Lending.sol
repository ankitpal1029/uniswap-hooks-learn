// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ILending} from "./interfaces/ILending.sol";
import {ERC721} from "v4-periphery/lib/permit2/lib/solmate/src/tokens/ERC721.sol";
import {IPoolManager} from "v4-periphery/lib/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {IERC20} from "v4-core/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {Variables} from "./Variables.sol";

/**
 * This is going to only allow lending/borrowing between the two assets the poolmanager is configured for
 * i'll figure out multiple ones later for now this will work
 * assume unless said otherwise that this allows for loans taken out in currency1 with currency0 as collateral
 * currency0/currency1 (WETH/USDC)
 */
contract Lending is ILending, ERC721, Variables {
    IPoolManager public poolManager;

    constructor(IPoolManager _poolManager, string memory _nftName, string memory _nftSymbol)
        ERC721(_nftName, _nftSymbol)
    {
        poolManager = _poolManager;
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

    function borrow() external {
        // TODO: tickId is set here for the first time
    }

    function repay() external {}

    function withdraw() external {}
}
