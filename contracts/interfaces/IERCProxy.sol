// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IERCProxy {
    function proxyType() external pure returns (uint256 proxyTypeId);

    function implementation() external view returns (address codeAddr);
}
