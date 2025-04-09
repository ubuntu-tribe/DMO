// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../interfaces/IGovernanceContract.sol";

contract MockGovernance is IGovernanceContract {
    address public _rewardsContract;
    
    function createProposal(uint256 proposalId) external override {
        // Mock implementation
    }
    
    function rewardsContract() external view override returns (address) {
        return _rewardsContract;
    }
    
    function setRewardsContract(address rewards) external {
        _rewardsContract = rewards;
    }
}