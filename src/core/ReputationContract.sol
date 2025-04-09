// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

/**
 * @title ReputationContract
 * @dev Tracks user contributions and DAO trustworthiness
 */
contract ReputationContract is 
    Initializable, 
    UUPSUpgradeable, 
    OwnableUpgradeable, 
    ReentrancyGuardUpgradeable,
    PausableUpgradeable 
{
    // ====== State Variables ======
    // User => reputation score
    mapping(address => uint256) public reputationScores;
    
    // Address => isReputationManager
    mapping(address => bool) public reputationManagers;
    
    // Optional: Reputation decay parameters
    uint256 public decayPeriod;      // Period after which reputation starts to decay (in seconds)
    uint256 public decayPercentage;  // Percentage of reputation that decays (in basis points)
    
    // Optional: Last activity timestamp per user
    mapping(address => uint256) public lastActivity;
    
    // ====== Events ======
    event ReputationUpdated(address indexed user, uint256 proposalId, int256 change, uint256 newScore);
    event ReputationManagerAdded(address indexed manager);
    event ReputationManagerRemoved(address indexed manager);
    event DecayParamsUpdated(uint256 decayPeriod, uint256 decayPercentage);
    
    // ====== Modifiers ======
    modifier onlyReputationManager() {
        require(reputationManagers[msg.sender] || msg.sender == owner(), "ReputationContract: not a reputation manager");
        _;
    }
    
    /**
     * @dev Initializes the contract with required parameters
     */
    function initialize() public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        
        // Owner is initially a reputation manager
        reputationManagers[msg.sender] = true;
        
        // Default decay parameters
        decayPeriod = 180 days;     // 6 months
        decayPercentage = 1000;     // 10% (in basis points)
        
        emit ReputationManagerAdded(msg.sender);
        emit DecayParamsUpdated(decayPeriod, decayPercentage);
    }
    
    /**
     * @dev Update a user's reputation (increase)
     * @param user Address of the user
     * @param proposalId The ID of the proposal (for logging)
     * @param points Number of points to add
     */
    function updateReputation(address user, uint256 proposalId, uint256 points) 
        external 
        whenNotPaused
        onlyReputationManager 
    {
        require(user != address(0), "ReputationContract: user cannot be zero address");
        
        // Apply decay if needed before updating
        applyDecayIfNeeded(user);
        
        // Update reputation
        reputationScores[user] += points;
        
        // Update last activity
        lastActivity[user] = block.timestamp;
        
        emit ReputationUpdated(user, proposalId, int256(points), reputationScores[user]);
    }
    
    /**
     * @dev Slash a user's reputation (decrease)
     * @param user Address of the user
     * @param proposalId The ID of the proposal (for logging)
     * @param penalty Number of points to deduct
     */
    function slashReputation(address user, uint256 proposalId, uint256 penalty) 
        external 
        whenNotPaused
        onlyReputationManager 
    {
        require(user != address(0), "ReputationContract: user cannot be zero address");
        
        // Apply decay if needed before slashing
        applyDecayIfNeeded(user);
        
        // Calculate new reputation (prevent underflow)
        uint256 newScore = (reputationScores[user] > penalty) ? reputationScores[user] - penalty : 0;
        reputationScores[user] = newScore;
        
        // Update last activity
        lastActivity[user] = block.timestamp;
        
        emit ReputationUpdated(user, proposalId, -1 * int256(penalty), newScore);
    }
    
    /**
     * @dev Get a user's current reputation score with decay applied
     * @param user Address of the user
     * @return Current reputation score
     */
    function getReputation(address user) external view returns (uint256) {
        if (lastActivity[user] == 0) {
            return reputationScores[user]; // No activity yet, no decay
        }
        
        uint256 timeSinceLastActivity = block.timestamp - lastActivity[user];
        if (timeSinceLastActivity < decayPeriod) {
            return reputationScores[user]; // No decay yet
        }
        
        // Calculate decay
        uint256 decayPeriods = timeSinceLastActivity / decayPeriod;
        uint256 remainingRep = reputationScores[user];
        
        for (uint256 i = 0; i < decayPeriods; i++) {
            remainingRep = remainingRep * (10000 - decayPercentage) / 10000;
        }
        
        return remainingRep;
    }
    
    /**
     * @dev Check if a user has sufficient reputation
     * @param user Address of the user
     * @param threshold Minimum reputation required
     * @return Whether the user meets the threshold
     */
    function hasSufficientReputation(address user, uint256 threshold) external view returns (bool) {
        return this.getReputation(user) >= threshold;
    }
    
    /**
     * @dev Apply decay to a user's reputation if needed
     * @param user Address of the user
     */
    function applyDecayIfNeeded(address user) internal {
        if (lastActivity[user] == 0) {
            return; // No previous activity
        }
        
        uint256 timeSinceLastActivity = block.timestamp - lastActivity[user];
        if (timeSinceLastActivity < decayPeriod) {
            return; // No decay needed
        }
        
        // Calculate decay
        uint256 decayPeriods = timeSinceLastActivity / decayPeriod;
        uint256 remainingRep = reputationScores[user];
        
        for (uint256 i = 0; i < decayPeriods; i++) {
            remainingRep = remainingRep * (10000 - decayPercentage) / 10000;
        }
        
        reputationScores[user] = remainingRep;
    }
    
    /**
     * @dev Add a reputation manager
     * @param manager Address of the new manager
     */
    function addReputationManager(address manager) external onlyOwner {
        require(manager != address(0), "ReputationContract: manager cannot be zero address");
        reputationManagers[manager] = true;
        emit ReputationManagerAdded(manager);
    }
    
    /**
     * @dev Remove a reputation manager
     * @param manager Address of the manager to remove
     */
    function removeReputationManager(address manager) external onlyOwner {
        reputationManagers[manager] = false;
        emit ReputationManagerRemoved(manager);
    }
    
    /**
     * @dev Update decay parameters
     * @param _decayPeriod New decay period in seconds
     * @param _decayPercentage New decay percentage in basis points
     */
    function updateDecayParams(uint256 _decayPeriod, uint256 _decayPercentage) external onlyOwner {
        require(_decayPercentage <= 10000, "ReputationContract: decay percentage cannot exceed 100%");
        decayPeriod = _decayPeriod;
        decayPercentage = _decayPercentage;
        emit DecayParamsUpdated(_decayPeriod, _decayPercentage);
    }
    
    /**
     * @dev Manually set a user's reputation (for initial setup or migration)
     * @param user Address of the user
     * @param score New reputation score
     */
    function setReputation(address user, uint256 score) external onlyOwner {
        require(user != address(0), "ReputationContract: user cannot be zero address");
        reputationScores[user] = score;
        lastActivity[user] = block.timestamp;
        emit ReputationUpdated(user, 0, int256(score), score);
    }
    
    /**
     * @dev Pause contract functions
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @dev Unpause contract functions
     */
    function unpause() external onlyOwner {
        _unpause();
    }
    
    /**
     * @dev Function that authorizes an upgrade to the implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}