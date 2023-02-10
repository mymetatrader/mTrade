// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IGnsToken {
    function burn(address to, uint256 amount) external;

    function mint(address from, uint256 amount) external;
}
