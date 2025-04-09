// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../core/GovernanceContract.sol";
import "../core/ProposalContract.sol";
import "../core/ReputationContract.sol";
import "../core/RewardsContract.sol";
import "./mocks/MockGIFT.sol";

contract GovernanceContractTest is Test {
    GovernanceContract public governance;
    ProposalContract public proposal;
    ReputationContract public reputation;
    RewardsContract public rewards;
    MockGIFT public giftToken;
    
    address public owner = address(1);
    address public user1 = address(2);
    address public user2 = address(3);
    address public user3 = address(4);
    
    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 10**18;
    uint256 public constant MIN_REPUTATION = 100;
    uint256 public constant MIN_STAKE = 1000 * 10**18;
    
    event ProposalVotingStarted(uint256 indexed proposalId, uint256 startTime, uint256 endTime);
    event VoteCast(uint256 indexed proposalId, address indexed voter, bool support, uint256 weight);
    event ProposalExecuted(uint256 indexed proposalId);
    
    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy token
        giftToken = new MockGIFT("GIFT", "GIFT", INITIAL_SUPPLY);
        
        // Deploy contracts
        reputation = new ReputationContract();
        rewards = new RewardsContract();
        proposal = new ProposalContract();
        governance = new GovernanceContract();
        
        // Initialize contracts
        reputation.initialize();
        rewards.initialize(address(giftToken));
        proposal.initialize(address(reputation), address(giftToken));
        governance.initialize(
            address(proposal),
            address(rewards),
            address(reputation),
            address(giftToken)
        );
        
        // Set cross-contract references
        proposal.setGovernanceContract(address(governance));
        rewards.setContracts(address(governance), address(proposal));
        
        // Set permissions
        reputation.addReputationManager(address(proposal));
        
        // Fund users
        giftToken.transfer(user1, 100000 * 10**18);
        giftToken.transfer(user2, 100000 * 10**18);
        giftToken.transfer(user3, 100000 * 10**18);
        
        // Grant initial reputation
        reputation.setReputation(user1, 200);
        reputation.setReputation(user2, 200);
        
        vm.stopPrank();
    }
    
    function testVotingParameters() public {
        assertEq(governance.quorumPercentage(), 1000); // 10%
        assertEq(governance.majorityPercentage(), 5000); // 50%
        assertEq(governance.votingDuration(), 5 days);
    }
    
    function testUpdateVotingThresholds() public {
        vm.startPrank(owner);
        governance.setVotingThresholds(2000, 6000, 7 days);
        vm.stopPrank();
        
        assertEq(governance.quorumPercentage(), 2000); // 20%
        assertEq(governance.majorityPercentage(), 6000); // 60%
        assertEq(governance.votingDuration(), 7 days);
    }
    
    function testProposalWorkflow() public {
        // Prepare proposal data
        string memory description = "Test Marketing Campaign";
        uint256 totalBudget = 5000 * 10**18;
        string[] memory titles = new string[](2);
        titles[0] = "Milestone 1";
        titles[1] = "Milestone 2";
        
        string[] memory descs = new string[](2);
        descs[0] = "First phase";
        descs[1] = "Second phase";
        
        uint256[] memory funds = new uint256[](2);
        funds[0] = 2000 * 10**18;
        funds[1] = 3000 * 10**18;
        
        // Submit proposal
        vm.startPrank(user1);
        giftToken.approve(address(proposal), MIN_STAKE);
        proposal.submitProposal(description, totalBudget, titles, descs, funds);
        vm.stopPrank();
        
        uint256 proposalId = 0; // First proposal
        
        // Check proposal was created
        (address proposer,,,,, uint8 status,) = proposal.getProposal(proposalId);
        assertEq(proposer, user1);
        assertEq(status, 1); // Active status
        
        // Vote on proposal
        vm.startPrank(user2);
        governance.voteOnProposal(proposalId, true);
        vm.stopPrank();
        
        vm.startPrank(user3);
        governance.voteOnProposal(proposalId, true);
        vm.stopPrank();
        
        // Check votes were counted
        assertEq(governance.forVotes(proposalId), 200000 * 10**18);
        
        // Fast forward to end of voting
        vm.warp(block.timestamp + 6 days);
        
        // Execute proposal
        vm.prank(owner);
        governance.executeProposal(proposalId);
        
        // Check proposal status
        (,,,,,status,) = proposal.getProposal(proposalId);
        assertEq(status, 2); // Approved status
    }
    
    function testQuorumCheck() public {
        // Prepare proposal
        vm.startPrank(user1);
        giftToken.approve(address(proposal), MIN_STAKE);
        
        string[] memory titles = new string[](1);
        titles[0] = "Milestone";
        
        string[] memory descs = new string[](1);
        descs[0] = "Description";
        
        uint256[] memory funds = new uint256[](1);
        funds[0] = 1000 * 10**18;
        
        proposal.submitProposal("Test", 1000 * 10**18, titles, descs, funds);
        vm.stopPrank();
        
        uint256 proposalId = 0;
        
        // Only user2 votes (not enough for quorum)
        vm.startPrank(user2);
        governance.voteOnProposal(proposalId, true);
        vm.stopPrank();
        
        // Fast forward
        vm.warp(block.timestamp + 6 days);
        
        // Try to execute - should fail due to quorum
        vm.expectRevert("GovernanceContract: proposal did not pass");
        governance.executeProposal(proposalId);
        
        // Verify quorum calculation
        assertFalse(governance.quorumReached(proposalId));
    }
    
    function testPauseUnpause() public {
        vm.prank(owner);
        governance.pause();
        
        // Try to vote while paused
        vm.expectRevert("Pausable: paused");
        vm.prank(user1);
        governance.voteOnProposal(0, true);
        
        // Unpause
        vm.prank(owner);
        governance.unpause();
        
        // Now should be able to vote (assuming proposal exists)
        // This would still fail but due to proposal not existing, not due to paused
        vm.expectRevert("GovernanceContract: proposal does not exist");
        vm.prank(user1);
        governance.voteOnProposal(0, true);
    }
}