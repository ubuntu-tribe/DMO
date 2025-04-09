// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../core/RewardsContract.sol";
import "./mocks/MockGIFT.sol";

contract RewardsContractTest is Test {
    RewardsContract public rewards;
    MockGIFT public giftToken;
    
    address public owner = address(1);
    address public governance = address(2);
    address public proposalContract = address(3);
    address public recipient = address(4);
    
    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 10**18;
    
    event RewardAllocated(uint256 indexed proposalId, uint256 indexed milestoneId, address recipient, uint256 amount);
    event TimelockTransferCreated(uint256 indexed timelockId, address recipient, uint256 amount, uint256 releaseTime);
    event TimelockTransferExecuted(uint256 indexed timelockId, address recipient, uint256 amount);
    
    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy token and reward contract
        giftToken = new MockGIFT("GIFT", "GIFT", INITIAL_SUPPLY);
        rewards = new RewardsContract();
        rewards.initialize(address(giftToken));
        
        // Set up permissions
        rewards.setContracts(governance, proposalContract);
        
        // Fund reward contract
        giftToken.transfer(address(rewards), 100000 * 10**18);
        
        vm.stopPrank();
    }
    
    function testInitialState() public {
        assertEq(address(rewards.giftToken()), address(giftToken));
        assertEq(rewards.governanceContract(), governance);
        assertEq(rewards.proposalContract(), proposalContract);
        assertEq(rewards.timelockDuration(), 2 days);
        assertEq(rewards.timelockThreshold(), 50000 * 10**18);
    }
    
    function testAllocateSmallReward() public {
        uint256 proposalId = 1;
        uint256 milestoneId = 0;
        uint256 amount = 1000 * 10**18;
        
        uint256 initialRecipientBalance = giftToken.balanceOf(recipient);
        
        // Allocate reward as governance
        vm.prank(governance);
        
        vm.expectEmit(true, true, true, true);
        emit RewardAllocated(proposalId, milestoneId, recipient, amount);
        
        rewards.allocateReward(proposalId, milestoneId, recipient, amount);
        
        // Check milestone marked as released
        assertTrue(rewards.milestoneReleased(proposalId, milestoneId));
        
        // Check funds were transferred immediately (below timelock threshold)
        assertEq(giftToken.balanceOf(recipient), initialRecipientBalance + amount);
        
        // Check tracking of funds
        assertEq(rewards.proposalFundsReleased(proposalId), amount);
    }
    
    function testAllocateLargeReward() public {
        uint256 proposalId = 1;
        uint256 milestoneId = 0;
        uint256 amount = 60000 * 10**18; // Above timelock threshold
        
        uint256 initialRecipientBalance = giftToken.balanceOf(recipient);
        
        // Allocate reward as governance
        vm.prank(governance);
        
        vm.expectEmit(true, true, true, false);
        emit TimelockTransferCreated(0, recipient, amount, block.timestamp + 2 days);
        
        rewards.allocateReward(proposalId, milestoneId, recipient, amount);
        
        // Check milestone marked as released
        assertTrue(rewards.milestoneReleased(proposalId, milestoneId));
        
        // Check funds were NOT transferred immediately (timelock created)
        assertEq(giftToken.balanceOf(recipient), initialRecipientBalance);
        
        // Check tracking of funds
        assertEq(rewards.proposalFundsReleased(proposalId), amount);
        
        // Check timelock details
        (address tlRecipient, uint256 tlAmount, uint256 releaseTime, bool executed, bool cancelled) = rewards.timelockTransfers(0);
        
        assertEq(tlRecipient, recipient);
        assertEq(tlAmount, amount);
        assertEq(releaseTime, block.timestamp + 2 days);
        assertFalse(executed);
        assertFalse(cancelled);
    }
    
    function testTimelockExecution() public {
        // Create timelock
        vm.prank(governance);
        rewards.allocateReward(1, 0, recipient, 60000 * 10**18);
        
        // Try to execute too early
        vm.expectRevert("RewardsContract: timelock not expired");
        rewards.executeTimelockTransfer(0);
        
        // Fast forward past timelock
        vm.warp(block.timestamp + 2 days + 1);
        
        // Execute timelock
        vm.expectEmit(true, true, true, true);
        emit TimelockTransferExecuted(0, recipient, 60000 * 10**18);
        
        rewards.executeTimelockTransfer(0);
        
        // Check funds were transferred
        assertEq(giftToken.balanceOf(recipient), 60000 * 10**18);
        
        // Check timelock marked as executed
        (,,,bool executed,) = rewards.timelockTransfers(0);
        assertTrue(executed);
        
        // Try to execute again
        vm.expectRevert("RewardsContract: transfer already executed");
        rewards.executeTimelockTransfer(0);
    }
    
    function testCancelTimelock() public {
        // Create timelock
        vm.prank(governance);
        rewards.allocateReward(1, 0, recipient, 60000 * 10**18);
        
        // Cancel as owner
        vm.prank(owner);
        rewards.cancelTimelockTransfer(0);
        
        // Check cancelled flag
        (,,,,bool cancelled) = rewards.timelockTransfers(0);
        assertTrue(cancelled);
        
        // Try to execute cancelled timelock
        vm.warp(block.timestamp + 3 days);
        vm.expectRevert("RewardsContract: transfer was cancelled");
        rewards.executeTimelockTransfer(0);
    }
    
    function testClaimReward() public {
        // Create timelock
        vm.prank(governance);
        rewards.allocateReward(1, 0, recipient, 60000 * 10**18);
        
        // Fast forward past timelock
        vm.warp(block.timestamp + 2 days + 1);
        
        // Claim as recipient
        vm.prank(recipient);
        rewards.claimReward(0);
        
        // Check funds were transferred
        assertEq(giftToken.balanceOf(recipient), 60000 * 10**18);
        
        // Non-recipient cannot claim
        vm.prank(owner);
        vm.expectRevert("RewardsContract: caller is not the recipient");
        rewards.claimReward(0);
    }
    
    function testUpdateTimelockParams() public {
        vm.prank(owner);
        rewards.updateTimelockParams(5 days, 10000 * 10**18);
        
        assertEq(rewards.timelockDuration(), 5 days);
        assertEq(rewards.timelockThreshold(), 10000 * 10**18);
        
        // Test with new params
        vm.prank(governance);
        rewards.allocateReward(1, 0, recipient, 20000 * 10**18); // Now above threshold
        
        // Check timelock created with new duration
        (,, uint256 releaseTime,,) = rewards.timelockTransfers(0);
        assertEq(releaseTime, block.timestamp + 5 days);
    }
    
    function testOnlyGovernanceOrProposal() public {
        // Random address cannot allocate
        vm.prank(address(5));
        vm.expectRevert("RewardsContract: caller is not governance or proposal contract");
        rewards.allocateReward(1, 0, recipient, 1000 * 10**18);
        
        // Governance can allocate
        vm.prank(governance);
        rewards.allocateReward(1, 0, recipient, 1000 * 10**18);
        
        // Proposal contract can allocate
        vm.prank(proposalContract);
        rewards.allocateReward(1, 1, recipient, 2000 * 10**18);
    }
}