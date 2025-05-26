// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

abstract contract Events {
    event LogBorrow();
    event LogSupply();
    event LogWithdraw();
    event LogRepay();
    event LogLiquidation();
}
