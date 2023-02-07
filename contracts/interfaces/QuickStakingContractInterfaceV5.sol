// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface QuickStakingContractInterfaceV5{
	function earned(address) external view returns (uint256);
	function getReward() external;
	function stake(uint) external;
	function withdraw(uint) external;
	function balanceOf(address) external view returns (uint256);
}