// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "../interfaces/IGovernanceContract.sol";
import "../interfaces/IReputationContract.sol";
import "../interfaces/IGIFT.sol";
import "../interfaces/IRewardsContract.sol";

/**
 * @title ProposalContract
 * @dev Stores and manages marketing proposals
 */
contract ProposalContract is 
    Initializable, 
    UUPSUpgradeable, 
    OwnableUpgradeable, 
    ReentrancyGuardUpgradeable,
    PausableUpgradeable 
{
    // ====== State Variables ======
    IGovernanceContract public governanceContract;
    IReputationContract public reputationContract;
    IGIFT public giftToken;
    
    // Minimum requirements for proposals
    uint256 public minStakeAmount;  // Minimum GIFT tokens to stake
    uint256 public minReputation;   // Minimum reputation score to propose
    
    // Proposal status
    // 0: Pending, 1: Active (voting), 2: Approved, 3: Rejected, 4: Completed, 5: Failed (slashed)
    enum ProposalStatus { Pending, Active, Approved, Rejected, Completed, Failed }
    
    struct Milestone {
        string title;
        string description;
        uint256 fundsRequired;
        bool isCompleted;
    }
    
    struct Proposal {
        uint256 id;                 // Unique identifier
        address proposer;           // Address that submitted the proposal
        string description;         // Proposal description
        uint256 totalBudget;        // Total amount requested
        uint256 stakeAmount;        // Amount staked by proposer
        uint256 currentMilestone;   // Current milestone index
        ProposalStatus status;      // Current status
        Milestone[] milestones;     // Array of milestones
        bool exists;                // Whether this proposal exists
    }
    
    // proposalId => Proposal
    mapping(uint256 => Proposal) public proposals;
    
    // Current proposal ID counter
    uint256 public proposalIdCounter;
    
    // Address authorized to verify milestones
    mapping(address => bool) public milestoneVerifiers;
    
    // ====== Events ======
    event ProposalSubmitted(uint256 indexed proposalId, address indexed proposer, uint256 totalBudget);
    event ProposalApproved(uint256 indexed proposalId);
    event ProposalRejected(uint256 indexed proposalId);
    event ProposalCompleted(uint256 indexed proposalId);
    event ProposalFailed(uint256 indexed proposalId);
    event MilestoneCompleted(uint256 indexed proposalId, uint256 milestoneIndex);
    event MilestoneVerifierAdded(address indexed verifier);
    event MilestoneVerifierRemoved(address indexed verifier);
    event RequirementsUpdated(uint256 minStakeAmount, uint256 minReputation);
    event ContractAddressesUpdated(address governanceContract, address reputationContract, address giftToken);
    
    // ====== Modifiers ======
    modifier onlyGovernanceContract() {
        require(address(governanceContract) == msg.sender, "ProposalContract: caller is not governance");
        _;
    }
    
    modifier onlyMilestoneVerifier() {
        require(milestoneVerifiers[msg.sender] || msg.sender == owner(), "ProposalContract: not a milestone verifier");
        _;
    }
    
    modifier onlyProposer(uint256 proposalId) {
        require(proposals[proposalId].proposer == msg.sender, "ProposalContract: caller is not proposer");
        _;
    }
    
    modifier proposalExists(uint256 proposalId) {
        require(proposals[proposalId].exists, "ProposalContract: proposal does not exist");
        _;
    }
    
    /**
     * @dev Initializes the contract with required parameters
     */
    function initialize(
        address _reputationContract,
        address _giftToken
    ) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        
        reputationContract = IReputationContract(_reputationContract);
        giftToken = IGIFT(_giftToken);
        
        // Default proposal requirements
        minStakeAmount = 1000 * 10**18; // 1,000 GIFT tokens
        minReputation = 100; // 100 reputation points
        
        // Owner is initially a milestone verifier
        milestoneVerifiers[msg.sender] = true;
        
        emit ContractAddressesUpdated(address(0), _reputationContract, _giftToken);
        emit RequirementsUpdated(minStakeAmount, minReputation);
        emit MilestoneVerifierAdded(msg.sender);
    }
    
    /**
     * @dev Submit a new marketing proposal
     * @param description Description of the proposal
     * @param totalBudget Total budget requested in GIFT tokens
     * @param milestoneTitles Array of milestone titles
     * @param milestoneDescriptions Array of milestone descriptions
     * @param milestoneFunds Array of funds required for each milestone
     */
    function submitProposal(
        string memory description,
        uint256 totalBudget,
        string[] memory milestoneTitles,
        string[] memory milestoneDescriptions,
        uint256[] memory milestoneFunds
    ) 
        external 
        nonReentrant 
        whenNotPaused
    {
        require(milestoneTitles.length > 0, "ProposalContract: must have at least one milestone");
        require(milestoneTitles.length == milestoneDescriptions.length, "ProposalContract: titles and descriptions length mismatch");
        require(milestoneTitles.length == milestoneFunds.length, "ProposalContract: titles and funds length mismatch");
        
        // Check if proposer meets requirements
        require(giftToken.balanceOf(msg.sender) >= minStakeAmount, "ProposalContract: insufficient GIFT balance for stake");
        require(reputationContract.getReputation(msg.sender) >= minReputation, "ProposalContract: insufficient reputation");
        
        // Calculate total milestone funds to verify they match total budget
        uint256 totalMilestoneFunds = 0;
        for (uint256 i = 0; i < milestoneFunds.length; i++) {
            totalMilestoneFunds += milestoneFunds[i];
        }
        require(totalMilestoneFunds == totalBudget, "ProposalContract: milestone funds must equal total budget");
        
        // Transfer stake from proposer to this contract
        require(giftToken.transferFrom(msg.sender, address(this), minStakeAmount), "ProposalContract: stake transfer failed");
        
        // Create new proposal
        uint256 proposalId = proposalIdCounter;
        proposals[proposalId].id = proposalId;
        proposals[proposalId].proposer = msg.sender;
        proposals[proposalId].description = description;
        proposals[proposalId].totalBudget = totalBudget;
        proposals[proposalId].stakeAmount = minStakeAmount;
        proposals[proposalId].status = ProposalStatus.Pending;
        proposals[proposalId].exists = true;
        
        // Add milestones
        for (uint256 i = 0; i < milestoneTitles.length; i++) {
            proposals[proposalId].milestones.push(Milestone({
                title: milestoneTitles[i],
                description: milestoneDescriptions[i],
                fundsRequired: milestoneFunds[i],
                isCompleted: false
            }));
        }
        
        // Increment proposal counter
        proposalIdCounter++;
        
        // Start proposal voting
        proposals[proposalId].status = ProposalStatus.Active;
        governanceContract.createProposal(proposalId);
        
        emit ProposalSubmitted(proposalId, msg.sender, totalBudget);
    }
    
    /**
     * @dev Mark a milestone as completed
     * @param proposalId The ID of the proposal
     * @param milestoneIndex The index of the milestone to mark as completed
     */
    function markMilestoneComplete(uint256 proposalId, uint256 milestoneIndex) 
        external 
        nonReentrant 
        whenNotPaused
        proposalExists(proposalId)
        onlyMilestoneVerifier 
    {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.status == ProposalStatus.Approved, "ProposalContract: proposal not approved");
        require(milestoneIndex < proposal.milestones.length, "ProposalContract: milestone index out of bounds");
        require(!proposal.milestones[milestoneIndex].isCompleted, "ProposalContract: milestone already completed");
        
        // If this is not the current milestone, reject
        require(milestoneIndex == proposal.currentMilestone, "ProposalContract: can only complete current milestone");
        
        // Mark milestone as completed
        proposal.milestones[milestoneIndex].isCompleted = true;
        
        // Move to next milestone
        proposal.currentMilestone++;
        
        // If all milestones are completed, mark proposal as completed
        if (proposal.currentMilestone >= proposal.milestones.length) {
            completeProposal(proposalId);
        } else {
            // Release funds for the completed milestone
            address payable proposer = payable(proposal.proposer);
            uint256 fundsToRelease = proposal.milestones[milestoneIndex].fundsRequired;
            
            // Call rewards contract to allocate reward
            IRewardsContract(governanceContract.rewardsContract()).allocateReward(
                proposalId, 
                milestoneIndex, 
                proposer,
                fundsToRelease
            );
        }
        
        emit MilestoneCompleted(proposalId, milestoneIndex);
    }
    
    /**
     * @dev Mark a proposal as complete and return stake to proposer
     * @param proposalId The ID of the proposal to complete
     */
    function completeProposal(uint256 proposalId) 
        internal 
        proposalExists(proposalId) 
    {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.status == ProposalStatus.Approved, "ProposalContract: proposal not approved");
        
        // Check all milestones are completed
        bool allCompleted = true;
        for (uint256 i = 0; i < proposal.milestones.length; i++) {
            if (!proposal.milestones[i].isCompleted) {
                allCompleted = false;
                break;
            }
        }
        require(allCompleted, "ProposalContract: not all milestones completed");
        
        // Mark proposal as completed
        proposal.status = ProposalStatus.Completed;
        
        // Return stake to proposer
        require(giftToken.transfer(proposal.proposer, proposal.stakeAmount), "ProposalContract: stake return failed");
        
        // Update reputation
        reputationContract.updateReputation(proposal.proposer, proposalId, 50);
        
        emit ProposalCompleted(proposalId);
    }
    
    /**
     * @dev Mark a proposal as failed and slash the stake
     * @param proposalId The ID of the proposal that failed
     */
    function failProposal(uint256 proposalId) 
        external 
        nonReentrant 
        whenNotPaused
        proposalExists(proposalId)
        onlyMilestoneVerifier 
    {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.status == ProposalStatus.Approved, "ProposalContract: proposal not approved");
        
        // Mark proposal as failed
        proposal.status = ProposalStatus.Failed;
        
        // Slash stake by sending it to the rewards contract
        address rewardsContractAddress = address(governanceContract.rewardsContract());
        require(giftToken.transfer(rewardsContractAddress, proposal.stakeAmount), "ProposalContract: stake slashing failed");
        
        // Penalize reputation
        reputationContract.slashReputation(proposal.proposer, proposalId, 100);
        
        emit ProposalFailed(proposalId);
    }
    
    /**
     * @dev Mark a proposal as approved (can only be called by governance)
     * @param proposalId The ID of the proposal to approve
     */
    function approveProposal(uint256 proposalId) 
        external 
        nonReentrant 
        whenNotPaused
        proposalExists(proposalId)
        onlyGovernanceContract 
    {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.status == ProposalStatus.Active, "ProposalContract: proposal not active");
        
        proposal.status = ProposalStatus.Approved;
        
        emit ProposalApproved(proposalId);
    }
    
    /**
     * @dev Mark a proposal as rejected (can only be called by governance)
     * @param proposalId The ID of the proposal to reject
     */
    function rejectProposal(uint256 proposalId) 
        external 
        nonReentrant 
        whenNotPaused
        proposalExists(proposalId)
        onlyGovernanceContract 
    {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.status == ProposalStatus.Active, "ProposalContract: proposal not active");
        
        proposal.status = ProposalStatus.Rejected;
        
        // Return stake to proposer
        require(giftToken.transfer(proposal.proposer, proposal.stakeAmount), "ProposalContract: stake return failed");
        
        emit ProposalRejected(proposalId);
    }
    
     // dev Get proposal details
     // param proposalId The ID of the proposal
     // return Proposal details


    function getProposal(uint256 proposalId) 
        external 
        view 
        proposalExists(proposalId) 
        returns (
            address proposer,
            string memory description,
            uint256 totalBudget,
            uint256 stakeAmount,
            uint256 currentMilestone,
            uint8 status,
            uint256 milestonesCount
        ) 
    {
        Proposal storage proposal = proposals[proposalId];
        return (
            proposal.proposer,
            proposal.description,
            proposal.totalBudget,
            proposal.stakeAmount,
            proposal.currentMilestone,
            uint8(proposal.status),
            proposal.milestones.length
        );
    }
    
     // dev Get milestone details
     // param proposalId The ID of the proposal
     // param milestoneIndex The index of the milestone
     // return Milestone details
    function getMilestone(uint256 proposalId, uint256 milestoneIndex) 
        external 
        view 
        proposalExists(proposalId) 
        returns (
            string memory title,
            string memory description,
            uint256 fundsRequired,
            bool isCompleted
        ) 
    {
        require(milestoneIndex < proposals[proposalId].milestones.length, "ProposalContract: milestone index out of bounds");
        Milestone storage milestone = proposals[proposalId].milestones[milestoneIndex];
        return (
            milestone.title,
            milestone.description,
            milestone.fundsRequired,
            milestone.isCompleted
        );
    }
    
    /**
     * @dev Get proposal status
     * @param proposalId The ID of the proposal
     * @return Status of the proposal
     */
    function getProposalStatus(uint256 proposalId) 
        external 
        view 
        proposalExists(proposalId) 
        returns (uint8) 
    {
        return uint8(proposals[proposalId].status);
    }
    
    /**
     * @dev Check if a proposal exists
     * @param proposalId The ID of the proposal
     * @return Whether the proposal exists
     */
    function proposalalreadyExists(uint256 proposalId) public view returns (bool) {
        return proposals[proposalId].exists;
    }
    
    /**
     * @dev Get initial funds for the first milestone
     * @param proposalId The ID of the proposal
     * @return proposer Proposer address
     * @return initialFunds Funds for the first milestone
     */
    function getProposalInitialFunds(uint256 proposalId) 
        external 
        view 
        proposalExists(proposalId) 
        returns (address proposer, uint256 initialFunds) 
    {
        Proposal storage proposal = proposals[proposalId];
        if (proposal.milestones.length > 0) {
            return (proposal.proposer, proposal.milestones[0].fundsRequired);
        } else {
            return (proposal.proposer, 0);
        }
    }
    
    /**
     * @dev Add a milestone verifier
     * @param verifier Address of the verifier
     */
    function addMilestoneVerifier(address verifier) external onlyOwner {
        require(verifier != address(0), "ProposalContract: verifier cannot be zero address");
        milestoneVerifiers[verifier] = true;
        emit MilestoneVerifierAdded(verifier);
    }
    
    /**
     * @dev Remove a milestone verifier
     * @param verifier Address of the verifier
     */
    function removeMilestoneVerifier(address verifier) external onlyOwner {
        milestoneVerifiers[verifier] = false;
        emit MilestoneVerifierRemoved(verifier);
    }
    
    /**
     * @dev Update proposal requirements
     * @param _minStakeAmount New minimum stake amount
     * @param _minReputation New minimum reputation
     */
    function updateRequirements(uint256 _minStakeAmount, uint256 _minReputation) external onlyOwner {
        minStakeAmount = _minStakeAmount;
        minReputation = _minReputation;
        emit RequirementsUpdated(_minStakeAmount, _minReputation);
    }
    
/**
     * @dev Set governance contract address (must be set after governance is deployed)
     * @param _governanceContract Address of the governance contract
     */
    function setGovernanceContract(address _governanceContract) external onlyOwner {
        require(_governanceContract != address(0), "ProposalContract: governance contract cannot be zero address");
        governanceContract = IGovernanceContract(_governanceContract);
        emit ContractAddressesUpdated(_governanceContract, address(reputationContract), address(giftToken));
    }
    
    /**
     * @dev Update reputation contract and GIFT token addresses
     * @param _reputationContract Address of the reputation contract
     * @param _giftToken Address of the GIFT token
     */
    function updateContractAddresses(address _reputationContract, address _giftToken) external onlyOwner {
        require(_reputationContract != address(0), "ProposalContract: reputation contract cannot be zero address");
        require(_giftToken != address(0), "ProposalContract: GIFT token cannot be zero address");
        
        reputationContract = IReputationContract(_reputationContract);
        giftToken = IGIFT(_giftToken);
        
        emit ContractAddressesUpdated(address(governanceContract), _reputationContract, _giftToken);
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