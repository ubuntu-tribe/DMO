// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IProposalContract {
    function approveProposal(uint256 proposalId) external;
    function proposalExists(uint256 proposalId) external view returns (bool);
    function getProposalStatus(uint256 proposalId) external view returns (uint8);
    function getProposalInitialFunds(uint256 proposalId) external view returns (address proposer, uint256 initialFunds);
}