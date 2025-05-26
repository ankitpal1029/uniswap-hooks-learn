// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

contract Base is Test {
    uint256 constant numTraders = 3;

    address[numTraders] public traders;
    mapping(address => uint256) public pKey;
    address public deployer;

    function __setupTraders() internal {
        uint256 privateKey;
        string memory newUser;
        vm.startPrank(deployer);
        for (uint256 i = 0; i < numTraders; i++) {
            newUser = string(abi.encodePacked("User", uintToString(i)));
            (traders[i], privateKey) = makeAddrAndKey(newUser);
            pKey[traders[i]] = privateKey;

            vm.deal(traders[i], 100 ether);
        }
        vm.stopPrank();
    }

    /**
     * ------------------Utility Functions--------------------------------------------
     */
    function uintToString(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k--;
            bstr[k] = bytes1(uint8(48 + _i % 10));
            _i /= 10;
            if (k == 0) break; // Add this line to prevent underflow
        }
        return string(bstr);
    }
}
