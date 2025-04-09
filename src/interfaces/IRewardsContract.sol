// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IRewardsContract {
    function allocateReward(uint256 proposalId, uint256 milestoneId, address recipient, uint256 amount) external;
}