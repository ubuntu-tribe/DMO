// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../core/ProposalContract.sol";
import "../core/ReputationContract.sol";
import "./mocks/MockGIFT.sol";
import "./mocks/MockGovernance.sol";

contract ProposalContractTest is Test {
    ProposalContract public proposal;
    ReputationContract public reputation;
    MockGIFT public giftToken;
    MockGovernance public mockGovernance;
    
    address public owner = address(1);
    address public user1 = address(2);
    address public user2 = address(3);
    
    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 10**18;
    uint256 public constant MIN_REPUTATION = 100;
    uint256 public constant MIN_STAKE = 1000 * 10**18;
    
    event ProposalSubmitted(uint256 indexed proposalId, address indexed proposer, uint256 totalBudget);
    event ProposalApproved(uint256 indexed proposalId);
    event MilestoneCompleted(uint256 indexed proposalId, uint256 milestoneIndex);
    event ProposalCompleted(uint256 indexed proposalId);
    
    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy token
        giftToken = new MockGIFT("GIFT", "GIFT", INITIAL_SUPPLY);
        
        // Deploy contracts
        reputation = new ReputationContract();
        reputation.initialize();
        
        proposal = new ProposalContract();
        proposal.initialize(address(reputation), address(giftToken));
        
        // Create mock governance
        mockGovernance = new MockGovernance();
        proposal.setGovernanceContract(address(mockGovernance));
        
        // Set permissions
        reputation.addReputationManager(address(proposal));
        
        // Fund users
        giftToken.transfer(user1, 100000 * 10**18);
        giftToken.transfer(user2, 50000 * 10**18);
        
        // Grant initial reputation
        reputation.setReputation(user1, 200);
        
        vm.stopPrank();
    }
    
    function testSubmitProposal() public {
        // Prepare data
        string memory description = "Marketing Campaign";
        uint256 totalBudget = 5000 * 10**18;
        
        string[] memory titles = new string[](2);
        titles[0] = "Phase 1";
        titles[1] = "Phase 2";
        
        string[] memory descs = new string[](2);
        descs[0] = "First milestone";
        descs[1] = "Second milestone";
        
        uint256[] memory funds = new uint256[](2);
        funds[0] = 2000 * 10**18;
        funds[1] = 3000 * 10**18;
        
        // Submit proposal
        vm.startPrank(user1);
        giftToken.approve(address(proposal), MIN_STAKE);
        
        vm.expectEmit(true, true, false, true);
        emit ProposalSubmitted(0, user1, totalBudget);
        
        proposal.submitProposal(description, totalBudget, titles, descs, funds);
        vm.stopPrank();
        
        // Verify proposal was created
        (address proposer, string memory desc, uint256 budget, uint256 stake, uint256 milestone, uint8 status, uint256 count) = proposal.getProposal(0);
        
        assertEq(proposer, user1);
        assertEq(desc, description);
        assertEq(budget, totalBudget);
        assertEq(stake, MIN_STAKE);
        assertEq(milestone, 0);
        assertEq(status, 1); // Active status
        assertEq(count, 2); // 2 milestones
        
        // Check proposal balance
        assertEq(giftToken.balanceOf(address(proposal)), MIN_STAKE);
    }
    
    function testRequirementChecks() public {
        string[] memory titles = new string[](1);
        titles[0] = "Milestone";
        
        string[] memory descs = new string[](1);
        descs[0] = "Description";
        
        uint256[] memory funds = new uint256[](1);
        funds[0] = 1000 * 10**18;
        
        // User without reputation tries to submit
        vm.startPrank(user2);
        giftToken.approve(address(proposal), MIN_STAKE);
        
        vm.expectRevert("ProposalContract: insufficient reputation");
        proposal.submitProposal("Test", 1000 * 10**18, titles, descs, funds);
        vm.stopPrank();
        
        // Grant reputation but still not enough funds
        vm.prank(owner);
        reputation.setReputation(user2, 200);
        
        vm.startPrank(user2);
        giftToken.transfer(address(0x1), 49000 * 10**18); // Send most funds away
        
        vm.expectRevert("ProposalContract: insufficient GIFT balance for stake");
        proposal.submitProposal("Test", 1000 * 10**18, titles, descs, funds);
        vm.stopPrank();
    }
    
    function testMilestoneWorkflow() public {
        // Submit proposal
        vm.startPrank(user1);
        giftToken.approve(address(proposal), MIN_STAKE);
        
        string[] memory titles = new string[](2);
        titles[0] = "Phase 1";
        titles[1] = "Phase 2";
        
        string[] memory descs = new string[](2);
        descs[0] = "First milestone";
        descs[1] = "Second milestone";
        
        uint256[] memory funds = new uint256[](2);
        funds[0] = 2000 * 10**18;
        funds[1] = 3000 * 10**18;
        
        proposal.submitProposal("Test Campaign", 5000 * 10**18, titles, descs, funds);
        vm.stopPrank();
        
        uint256 proposalId = 0;
        
        // Approve proposal via governance
        vm.prank(address(mockGovernance));
        proposal.approveProposal(proposalId);
        
        // Mark milestone complete as verifier
        vm.prank(owner);
        proposal.markMilestoneComplete(proposalId, 0);
        
        // Check milestone status
        (,,,bool isCompleted) = proposal.getMilestone(proposalId, 0);
        assertTrue(isCompleted);
        
        // Verify milestone counter incremented
        (,,,,uint256 currentMilestone,,) = proposal.getProposal(proposalId);
        assertEq(currentMilestone, 1);
        
        // Complete final milestone
        vm.prank(owner);
        proposal.markMilestoneComplete(proposalId, 1);
        
        // Check proposal completed
        (,,,,,uint8 status,) = proposal.getProposal(proposalId);
        assertEq(status, 4); // Completed status
        
        // Verify stake was returned
        assertEq(giftToken.balanceOf(address(proposal)), 0);
        
        // Check reputation increased
        assertEq(reputation.getReputation(user1), 250); // Initial 200 + 50 for completion
    }
    
    function testFailProposal() public {
        // Submit and approve proposal
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
        
        vm.prank(address(mockGovernance));
        proposal.approveProposal(proposalId);
        
        // Fail the proposal
        vm.prank(owner);
        proposal.failProposal(proposalId);
        
        // Check proposal status
        (,,,,,uint8 status,) = proposal.getProposal(proposalId);
        assertEq(status, 5); // Failed status
        
        // Check reputation was slashed
        assertEq(reputation.getReputation(user1), 100); // Initial 200 - 100 for failure
    }
}