// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IReputationContract {
    function updateReputation(address user, uint256 proposalId, uint256 points) external;
    function slashReputation(address user, uint256 proposalId, uint256 penalty) external;
    function getReputation(address user) external view returns (uint256);
    function hasSufficientReputation(address user, uint256 threshold) external view returns (bool);
}