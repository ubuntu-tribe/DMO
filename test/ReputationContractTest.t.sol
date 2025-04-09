// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../core/ReputationContract.sol";

contract ReputationContractTest is Test {
    ReputationContract public reputation;
    
    address public owner = address(1);
    address public user1 = address(2);
    address public user2 = address(3);
    address public manager = address(4);
    
    event ReputationUpdated(address indexed user, uint256 proposalId, int256 change, uint256 newScore);
    event ReputationManagerAdded(address indexed manager);
    event ReputationManagerRemoved(address indexed manager);
    
    function setUp() public {
        vm.startPrank(owner);
        reputation = new ReputationContract();
        reputation.initialize();
        
        // Add a manager
        reputation.addReputationManager(manager);
        vm.stopPrank();
    }
    
    function testInitialState() public {
        assertTrue(reputation.reputationManagers(owner));
        assertTrue(reputation.reputationManagers(manager));
        assertEq(reputation.decayPeriod(), 180 days);
        assertEq(reputation.decayPercentage(), 1000); // 10%
    }
    
    function testUpdateReputation() public {
        // Initial reputation is 0
        assertEq(reputation.getReputation(user1), 0);
        
        // Update reputation by owner
        vm.prank(owner);
        
        vm.expectEmit(true, true, false, true);
        emit ReputationUpdated(user1, 1, int256(50), 50);
        
        reputation.updateReputation(user1, 1, 50);
        
        // Check updated value
        assertEq(reputation.getReputation(user1), 50);
        
        // Update by manager
        vm.prank(manager);
        reputation.updateReputation(user1, 2, 30);
        
        // Check cumulative value
        assertEq(reputation.getReputation(user1), 80);
    }
    
    function testSlashReputation() public {
        // Set initial rep
        vm.prank(owner);
        reputation.setReputation(user1, 100);
        
        // Slash reputation
        vm.prank(manager);
        
        vm.expectEmit(true, true, false, true);
        emit ReputationUpdated(user1, 1, -40, 60);
        
        reputation.slashReputation(user1, 1, 40);
        
        // Check new value
        assertEq(reputation.getReputation(user1), 60);
        
        // Slash more than available (should go to 0)
        vm.prank(manager);
        reputation.slashReputation(user1, 2, 100);
        
        assertEq(reputation.getReputation(user1), 0);
    }
    
    function testReputationDecay() public {
        // Set initial reputation
        vm.prank(owner);
        reputation.setReputation(user1, 1000);
        
        // Fast forward past decay period
        vm.warp(block.timestamp + 181 days);
        
        // Check decayed value
        // After 1 decay period with 10% decay: 1000 * 0.9 = 900
        assertEq(reputation.getReputation(user1), 900);
        
        // Fast forward one more decay period
        vm.warp(block.timestamp + 180 days);
        
        // Check double decay: 900 * 0.9 = 810
        assertEq(reputation.getReputation(user1), 810);
    }
    
    function testUpdateDecayParams() public {
        vm.prank(owner);
        reputation.updateDecayParams(365 days, 2000); // 1 year, 20%
        
        assertEq(reputation.decayPeriod(), 365 days);
        assertEq(reputation.decayPercentage(), 2000);
        
        // Set rep and test new decay rate
        vm.prank(owner);
        reputation.setReputation(user1, 1000);
        
        // Fast forward past new decay period
        vm.warp(block.timestamp + 366 days);
        
        // Check decayed value with new rate: 1000 * 0.8 = 800
        assertEq(reputation.getReputation(user1), 800);
    }
    
    function testReputationManagerAuthorization() public {
        // Non-manager cannot update rep
        vm.prank(user2);
        vm.expectRevert("ReputationContract: not a reputation manager");
        reputation.updateReputation(user1, 1, 50);
        
        // Add user2 as manager
        vm.prank(owner);
        reputation.addReputationManager(user2);
        
        // Now user2 can update rep
        vm.prank(user2);
        reputation.updateReputation(user1, 1, 50);
        
        // Remove user2 as manager
        vm.prank(owner);
        reputation.removeReputationManager(user2);
        
        // User2 cannot update rep anymore
        vm.prank(user2);
        vm.expectRevert("ReputationContract: not a reputation manager");
        reputation.updateReputation(user1, 2, 30);
    }
    
    function testHasSufficientReputation() public {
        // Set reputation
        vm.prank(owner);
        reputation.setReputation(user1, 75);
        
        // Check thresholds
        assertTrue(reputation.hasSufficientReputation(user1, 50));
        assertTrue(reputation.hasSufficientReputation(user1, 75));
        assertFalse(reputation.hasSufficientReputation(user1, 100));
    }
}