// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "../interfaces/IGIFT.sol";

/**
 * @title RewardsContract
 * @dev Manages DAO funds and handles milestone-based disbursements
 */
contract RewardsContract is 
    Initializable, 
    UUPSUpgradeable, 
    OwnableUpgradeable, 
    ReentrancyGuardUpgradeable,
    PausableUpgradeable 
{
    // ====== State Variables ======
    IGIFT public giftToken;
    
    address public governanceContract;
    address public proposalContract;
    
    // proposalId => milestoneId => isReleased
    mapping(uint256 => mapping(uint256 => bool)) public milestoneReleased;
    
    // proposalId => total funds released
    mapping(uint256 => uint256) public proposalFundsReleased;
    
    // Timelock duration for large transfers (in seconds)
    uint256 public timelockDuration;
    
    // Amount threshold for timelock (in GIFT tokens)
    uint256 public timelockThreshold;
    
    struct TimelockTransfer {
        address recipient;
        uint256 amount;
        uint256 releaseTime;
        bool executed;
        bool cancelled;
    }
    
    // Timelock ID => TimelockTransfer
    mapping(uint256 => TimelockTransfer) public timelockTransfers;
    
    // Current timelock ID counter
    uint256 public timelockIdCounter;
    
    // ====== Events ======
    event RewardAllocated(uint256 indexed proposalId, uint256 indexed milestoneId, address recipient, uint256 amount);
    event TimelockTransferCreated(uint256 indexed timelockId, address recipient, uint256 amount, uint256 releaseTime);
    event TimelockTransferExecuted(uint256 indexed timelockId, address recipient, uint256 amount);
    event TimelockTransferCancelled(uint256 indexed timelockId);
    event ContractAddressesUpdated(address governanceContract, address proposalContract, address giftToken);
    event TimelockParamsUpdated(uint256 timelockDuration, uint256 timelockThreshold);
    
    // ====== Modifiers ======
    modifier onlyGovernanceOrProposal() {
        require(
            msg.sender == governanceContract || msg.sender == proposalContract,
            "RewardsContract: caller is not governance or proposal contract"
        );
        _;
    }
    
    /**
     * @dev Initializes the contract with required parameters
     */
    function initialize(
        address _giftToken
    ) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        
        giftToken = IGIFT(_giftToken);
        
        // Default timelock parameters
        timelockDuration = 2 days;
        timelockThreshold = 50000 * 10**18; // 50,000 GIFT tokens
        
        emit ContractAddressesUpdated(address(0), address(0), _giftToken);
        emit TimelockParamsUpdated(timelockDuration, timelockThreshold);
    }
    
    /**
     * @dev Allocate a reward for a completed milestone
     * @param proposalId The ID of the proposal
     * @param milestoneId The ID of the milestone
     * @param recipient The address to receive the funds
     * @param amount The amount of tokens to transfer
     */
    function allocateReward(
        uint256 proposalId,
        uint256 milestoneId,
        address recipient,
        uint256 amount
    ) 
        external 
        nonReentrant 
        whenNotPaused
        onlyGovernanceOrProposal 
    {
        require(recipient != address(0), "RewardsContract: recipient cannot be zero address");
        require(amount > 0, "RewardsContract: amount must be greater than zero");
        require(!milestoneReleased[proposalId][milestoneId], "RewardsContract: milestone reward already released");
        
        // Mark milestone as released
        milestoneReleased[proposalId][milestoneId] = true;
        
        // Update total funds released for this proposal
        proposalFundsReleased[proposalId] += amount;
        
        // Check if the contract has enough balance
        require(giftToken.balanceOf(address(this)) >= amount, "RewardsContract: insufficient funds");
        
        // If amount is above threshold, create a timelock transfer
        if (amount >= timelockThreshold) {
            uint256 timelockId = timelockIdCounter;
            timelockTransfers[timelockId] = TimelockTransfer({
                recipient: recipient,
                amount: amount,
                releaseTime: block.timestamp + timelockDuration,
                executed: false,
                cancelled: false
            });
            
            timelockIdCounter++;
            
            emit TimelockTransferCreated(timelockId, recipient, amount, block.timestamp + timelockDuration);
            emit RewardAllocated(proposalId, milestoneId, recipient, amount);
        } else {
            // Transfer tokens directly
            require(giftToken.transfer(recipient, amount), "RewardsContract: token transfer failed");
            
            emit RewardAllocated(proposalId, milestoneId, recipient, amount);
        }
    }
    
    /**
     * @dev Execute a timelocked transfer
     * @param timelockId The ID of the timelock transfer
     */
    function executeTimelockTransfer(uint256 timelockId) 
        external 
        nonReentrant 
        whenNotPaused
    {
        TimelockTransfer storage transfer = timelockTransfers[timelockId];
        require(!transfer.executed, "RewardsContract: transfer already executed");
        require(!transfer.cancelled, "RewardsContract: transfer was cancelled");
        require(block.timestamp >= transfer.releaseTime, "RewardsContract: timelock not expired");
        
        transfer.executed = true;
        
        require(giftToken.transfer(transfer.recipient, transfer.amount), "RewardsContract: token transfer failed");
        
        emit TimelockTransferExecuted(timelockId, transfer.recipient, transfer.amount);
    }
    
    /**
     * @dev Cancel a timelocked transfer (only owner)
     * @param timelockId The ID of the timelock transfer
     */
    function cancelTimelockTransfer(uint256 timelockId) 
        external 
        nonReentrant 
        onlyOwner 
    {
        TimelockTransfer storage transfer = timelockTransfers[timelockId];
        require(!transfer.executed, "RewardsContract: transfer already executed");
        require(!transfer.cancelled, "RewardsContract: transfer already cancelled");
        
        transfer.cancelled = true;
        
        emit TimelockTransferCancelled(timelockId);
    }
    
    /**
     * @dev Claim a reward (pull pattern for recipients)
     * @param timelockId The ID of the timelock transfer
     */
    function claimReward(uint256 timelockId) 
        external 
        nonReentrant 
        whenNotPaused
    {
        TimelockTransfer storage transfer = timelockTransfers[timelockId];
        require(msg.sender == transfer.recipient, "RewardsContract: caller is not the recipient");
        require(!transfer.executed, "RewardsContract: transfer already executed");
        require(!transfer.cancelled, "RewardsContract: transfer was cancelled");
        require(block.timestamp >= transfer.releaseTime, "RewardsContract: timelock not expired");
        
        transfer.executed = true;
        
        require(giftToken.transfer(transfer.recipient, transfer.amount), "RewardsContract: token transfer failed");
        
        emit TimelockTransferExecuted(timelockId, transfer.recipient, transfer.amount);
    }
    
    /**
     * @dev Set contract addresses
     * @param _governanceContract Address of the governance contract
     * @param _proposalContract Address of the proposal contract
     */
    function setContracts(address _governanceContract, address _proposalContract) external onlyOwner {
        require(_governanceContract != address(0), "RewardsContract: governance contract cannot be zero address");
        require(_proposalContract != address(0), "RewardsContract: proposal contract cannot be zero address");
        
        governanceContract = _governanceContract;
        proposalContract = _proposalContract;
        
        emit ContractAddressesUpdated(_governanceContract, _proposalContract, address(giftToken));
    }
    
    /**
     * @dev Update GIFT token address
     * @param _giftToken Address of the GIFT token
     */
    function setGiftToken(address _giftToken) external onlyOwner {
        require(_giftToken != address(0), "RewardsContract: GIFT token cannot be zero address");
        giftToken = IGIFT(_giftToken);
        emit ContractAddressesUpdated(governanceContract, proposalContract, _giftToken);
    }
    
    /**
     * @dev Update timelock parameters
     * @param _timelockDuration New timelock duration in seconds
     * @param _timelockThreshold New amount threshold for timelock
     */
    function updateTimelockParams(uint256 _timelockDuration, uint256 _timelockThreshold) external onlyOwner {
        timelockDuration = _timelockDuration;
        timelockThreshold = _timelockThreshold;
        emit TimelockParamsUpdated(_timelockDuration, _timelockThreshold);
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