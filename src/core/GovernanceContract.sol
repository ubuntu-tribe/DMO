// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "../interfaces/IProposalContract.sol";
import "../interfaces/IRewardsContract.sol";
import "../interfaces/IReputationContract.sol";
import "../interfaces/IGIFT.sol";

/**
 * @title GovernanceContract
 * @dev Manages DAO proposals, voting, and execution logic
 */
contract GovernanceContract is 
    Initializable, 
    UUPSUpgradeable, 
    OwnableUpgradeable, 
    ReentrancyGuardUpgradeable,
    PausableUpgradeable 
{
    // ====== State Variables ======
    IProposalContract public proposalContract;
    IRewardsContract public rewardsContract;
    IReputationContract public reputationContract;
    IGIFT public giftToken;
    
    uint256 public quorumPercentage; // Percentage of total staked tokens needed for quorum (in basis points)
    uint256 public majorityPercentage; // Percentage needed for majority approval (in basis points)
    uint256 public votingDuration; // Duration of voting period in seconds
    
    struct Vote {
        bool support;     // true = for, false = against
        uint256 weight;   // amount of tokens
        bool hasVoted;    // whether address has already voted
    }
    
    // proposalId => voter address => Vote details
    mapping(uint256 => mapping(address => Vote)) public votes;
    
    // proposalId => total "for" votes
    mapping(uint256 => uint256) public forVotes;
    
    // proposalId => total "against" votes
    mapping(uint256 => uint256) public againstVotes;
    
    // proposalId => voting start timestamp
    mapping(uint256 => uint256) public votingStarts;
    
    // proposalId => voting end timestamp
    mapping(uint256 => uint256) public votingEnds;
    
    // ====== Events ======
    event ProposalVotingStarted(uint256 indexed proposalId, uint256 startTime, uint256 endTime);
    event VoteCast(uint256 indexed proposalId, address indexed voter, bool support, uint256 weight);
    event ProposalExecuted(uint256 indexed proposalId);
    event GovernanceParamsUpdated(uint256 quorumPercentage, uint256 majorityPercentage, uint256 votingDuration);
    event ContractAddressesUpdated(address proposalContract, address rewardsContract, address reputationContract, address giftToken);
    
    // ====== Modifiers ======
    modifier onlyProposalContract() {
        require(msg.sender == address(proposalContract), "GovernanceContract: caller is not the proposal contract");
        _;
    }
    
    modifier proposalExists(uint256 proposalId) {
        require(proposalContract.proposalExists(proposalId), "GovernanceContract: proposal does not exist");
        _;
    }
    
    modifier votingOpen(uint256 proposalId) {
        require(
            block.timestamp >= votingStarts[proposalId] && 
            block.timestamp <= votingEnds[proposalId],
            "GovernanceContract: voting is not open"
        );
        _;
    }
    
    modifier votingClosed(uint256 proposalId) {
        require(block.timestamp > votingEnds[proposalId], "GovernanceContract: voting is still open");
        _;
    }
    
    modifier hasNotVoted(uint256 proposalId) {
        require(!votes[proposalId][msg.sender].hasVoted, "GovernanceContract: already voted");
        _;
    }
    
    modifier hasStake() {
        require(giftToken.balanceOf(msg.sender) > 0, "GovernanceContract: must have GIFT tokens to vote");
        _;
    }

    /**
     * @dev Initializes the contract with required parameters
     */
    function initialize(
        address _proposalContract,
        address _rewardsContract,
        address _reputationContract,
        address _giftToken
    ) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        
        proposalContract = IProposalContract(_proposalContract);
        rewardsContract = IRewardsContract(_rewardsContract);
        reputationContract = IReputationContract(_reputationContract);
        giftToken = IGIFT(_giftToken);
        
        // Default governance parameters
        quorumPercentage = 1000; // 10% (in basis points)
        majorityPercentage = 5000; // 50% (in basis points)
        votingDuration = 5 days; // 5 days for voting
        
        emit ContractAddressesUpdated(_proposalContract, _rewardsContract, _reputationContract, _giftToken);
        emit GovernanceParamsUpdated(quorumPercentage, majorityPercentage, votingDuration);
    }
    
    /**
     * @dev Creates a proposal and starts the voting period
     * @param proposalId The ID of the proposal to vote on
     */
    function createProposal(uint256 proposalId) 
        external 
        onlyProposalContract 
        whenNotPaused
    {
        votingStarts[proposalId] = block.timestamp;
        votingEnds[proposalId] = block.timestamp + votingDuration;
        
        emit ProposalVotingStarted(proposalId, votingStarts[proposalId], votingEnds[proposalId]);
    }
    
    /**
     * @dev Cast a vote on a proposal
     * @param proposalId The ID of the proposal to vote on
     * @param support Whether to support the proposal or not
     */
    function voteOnProposal(uint256 proposalId, bool support) 
        external 
        nonReentrant 
        whenNotPaused
        proposalExists(proposalId) 
        votingOpen(proposalId) 
        hasNotVoted(proposalId)
        hasStake() 
    {
        uint256 weight = giftToken.balanceOf(msg.sender);
        require(weight > 0, "GovernanceContract: no voting power");
        
        votes[proposalId][msg.sender] = Vote({
            support: support,
            weight: weight,
            hasVoted: true
        });
        
        if (support) {
            forVotes[proposalId] += weight;
        } else {
            againstVotes[proposalId] += weight;
        }
        
        emit VoteCast(proposalId, msg.sender, support, weight);
    }
    
    /**
     * @dev Executes a proposal if it has passed voting
     * @param proposalId The ID of the proposal to execute
     */
    function executeProposal(uint256 proposalId) 
        external 
        nonReentrant 
        whenNotPaused
        proposalExists(proposalId) 
        votingClosed(proposalId) 
    {
        require(isProposalPassed(proposalId), "GovernanceContract: proposal did not pass");
        require(proposalContract.getProposalStatus(proposalId) == 1, "GovernanceContract: proposal not in active state");
        
        // Mark proposal as approved in the proposal contract
        proposalContract.approveProposal(proposalId);
        
        // Release initial funds for the first milestone
        (address proposer, uint256 initialFunds) = proposalContract.getProposalInitialFunds(proposalId);
        if (initialFunds > 0) {
            rewardsContract.allocateReward(proposalId, 0, proposer, initialFunds);
        }
        
        emit ProposalExecuted(proposalId);
    }
    
    /**
     * @dev Checks if a proposal has passed voting (quorum reached and majority in favor)
     * @param proposalId The ID of the proposal to check
     * @return Whether the proposal passed
     */
    function isProposalPassed(uint256 proposalId) public view returns (bool) {
        return quorumReached(proposalId) && majorityReached(proposalId);
    }
    
    /**
     * @dev Checks if a proposal has reached quorum
     * @param proposalId The ID of the proposal to check
     * @return Whether quorum has been reached
     */
    function quorumReached(uint256 proposalId) public view returns (bool) {
        uint256 totalVotes = forVotes[proposalId] + againstVotes[proposalId];
        uint256 totalSupply = giftToken.totalSupply();
        return totalVotes * 10000 >= totalSupply * quorumPercentage;
    }
    
    /**
     * @dev Checks if a proposal has majority support
     * @param proposalId The ID of the proposal to check
     * @return Whether majority has been reached
     */
    function majorityReached(uint256 proposalId) public view returns (bool) {
        uint256 totalVotes = forVotes[proposalId] + againstVotes[proposalId];
        if (totalVotes == 0) return false;
        return forVotes[proposalId] * 10000 >= totalVotes * majorityPercentage;
    }
    
    /**
     * @dev Updates governance parameters
     * @param _quorumPercentage New quorum percentage (in basis points)
     * @param _majorityPercentage New majority percentage (in basis points)
     * @param _votingDuration New voting duration in seconds
     */
    function setVotingThresholds(
        uint256 _quorumPercentage,
        uint256 _majorityPercentage,
        uint256 _votingDuration
    ) 
        external 
        onlyOwner 
    {
        require(_quorumPercentage <= 10000, "GovernanceContract: quorum percentage exceeds maximum");
        require(_majorityPercentage <= 10000, "GovernanceContract: majority percentage exceeds maximum");
        require(_votingDuration >= 1 days, "GovernanceContract: voting duration too short");
        
        quorumPercentage = _quorumPercentage;
        majorityPercentage = _majorityPercentage;
        votingDuration = _votingDuration;
        
        emit GovernanceParamsUpdated(_quorumPercentage, _majorityPercentage, _votingDuration);
    }
    
    /**
     * @dev Updates contract addresses
     */
    function updateContractAddresses(
        address _proposalContract,
        address _rewardsContract,
        address _reputationContract,
        address _giftToken
    ) 
        external 
        onlyOwner 
    {
        require(_proposalContract != address(0), "GovernanceContract: proposal contract cannot be zero address");
        require(_rewardsContract != address(0), "GovernanceContract: rewards contract cannot be zero address");
        require(_reputationContract != address(0), "GovernanceContract: reputation contract cannot be zero address");
        require(_giftToken != address(0), "GovernanceContract: GIFT token cannot be zero address");
        
        proposalContract = IProposalContract(_proposalContract);
        rewardsContract = IRewardsContract(_rewardsContract);
        reputationContract = IReputationContract(_reputationContract);
        giftToken = IGIFT(_giftToken);
        
        emit ContractAddressesUpdated(_proposalContract, _rewardsContract, _reputationContract, _giftToken);
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