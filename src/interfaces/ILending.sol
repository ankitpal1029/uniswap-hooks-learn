// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Currency, CurrencyLibrary} from "v4-periphery/lib/v4-core/src/types/Currency.sol";
import {PoolKey} from "v4-periphery/lib/v4-core/src/types/PoolKey.sol";

interface ILending {
    /**
     * @notice supply funds, this is for creating a new position nft id or reuse an old one
     * @param _nftId: nft id representing the position
     * @param _key: PoolKey for where to handle this position (gives info on currency tokens basically)
     * @param _amt: amount to supply to the position
     */
    function supply(uint256 _nftId, PoolKey calldata _key, uint256 _amt) external;

    // uint256 _nftId, PoolKey calldata _key, uint256 _amt
    /**
     * @notice borrow funds, can only be done if user has supplied before
     * @param _nftId: nft id representing the position
     * @param _key: PoolKey for where to handle this position (gives info on currency tokens basically)
     * @param _amt: amount to borrow from the position
     */
    function borrow(uint256 _nftId, PoolKey calldata _key, uint256 _amt) external;

    function repay() external;

    function withdraw() external;

    function earn(PoolKey calldata _key, uint256 _amt, address _receiver) external;
}
