// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IGovernanceContract {
    function createProposal(uint256 proposalId) external;
    function rewardsContract() external view returns (address);
}