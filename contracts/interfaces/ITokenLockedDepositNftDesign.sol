// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;
import "./IVault.sol";

interface ITokenLockedDepositNftDesign {
    function buildTokenURI(
        uint256 tokenId,
        IVault.LockedDeposit memory lockedDeposit,
        string memory gTokenSymbol,
        string memory assetSymbol,
        uint8 numberInputDecimals,
        uint8 numberOutputDecimals
    ) external pure returns (string memory);
}
