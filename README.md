# **Comprehensive Documentation for the Ubuntu Tribe DMO Smart Contract System**

## **Introduction**

This Decentralized Marketing Organization (DMO) is a suite of smart contracts designed to enable community-driven marketing initiatives for the GIFT token ecosystem. It allows GIFT token holders to propose marketing campaigns, vote on proposals, and earn reputation through successful contributions. The system implements a transparent, milestone-based funding mechanism with built-in accountability features like staking, reputation tracking, and slashing mechanisms. This documentation provides a detailed explanation of the contract architecture, functionality, and usage guidelines to help users effectively interact with the DMO system.

---

## **Table of Contents**

1. [System Overview](#system-overview)
2. [Contract Architecture](#contract-architecture)
3. [Roles and Permissions](#roles-and-permissions)
4. [Data Structures](#data-structures)
   - Key Structs
   - State Variables
   - Mappings
5. [Key Components](#key-components)
   - Governance Contract
   - Proposal Contract
   - Rewards Contract
   - Reputation Contract
   - GIFT Token Integration
6. [Core Workflows](#core-workflows)
   - Proposal Submission and Staking
   - Voting Mechanism
   - Milestone Completion and Verification
   - Funds Disbursement
   - Slashing Mechanism
7. [Technical Implementation Details](#technical-implementation-details)
   - Upgradeability Pattern
   - Security Features
   - Event Logging
8. [Integration Guide](#integration-guide)
   - Deployment Sequence
   - Contract Interactions
   - Upgrading Contracts
9. [Usage Examples](#usage-examples)
10. [Security Considerations](#security-considerations)
11. [Appendix](#appendix)

---

## **System Overview**

The DMO is a decentralized autonomous organization (DAO) specifically designed to manage marketing activities for the GIFT token ecosystem. It leverages blockchain technology to create a transparent, community-governed platform where token holders can propose, vote on, and execute marketing initiatives.

The system is funded through a transaction tax built into the GIFT token, creating a sustainable funding model for marketing activities. This tax is collected in a treasury controlled by the DAO, and funds are released based on community approval and milestone completion.

The DMO implements several key mechanisms to ensure alignment of incentives:

- **Stake-to-Propose**: Marketers must stake GIFT tokens as collateral when proposing campaigns
- **Milestone-Based Funding**: Funds are released incrementally as milestones are completed
- **Reputation System**: Successful marketers build reputation, making future proposals easier
- **Slashing Mechanism**: Failed proposals result in lost stake and reputation
- **Token-Weighted Voting**: Governance decisions made by GIFT token holders

---

## **Contract Architecture**

The DMO consists of four primary smart contracts that work together to form a complete governance system:

1. **GovernanceContract**: Manages the voting and decision-making processes
2. **ProposalContract**: Handles proposal creation, storage, and milestone tracking
3. **RewardsContract (Treasury)**: Controls funds and distributes rewards for completed milestones
4. **ReputationContract**: Tracks contributor reputation and performance history

These contracts interact with the existing GIFT token contract, which includes a tax mechanism that funds the treasury. The system is designed with upgradeability in mind, using the UUPS (Universal Upgradeable Proxy Standard) pattern to allow for future enhancements.

---

## **Roles and Permissions**

The DMO implements several roles with specific permissions:

1. **Owner**: The contract deployer or designated controller with administrative privileges, including the ability to pause contracts, update parameters, and transfer ownership.

2. **GIFT Token Holders**: Any address holding GIFT tokens can participate in governance by voting on proposals. Voting power is proportional to token holdings.

3. **Proposers (Marketers)**: GIFT holders who submit marketing proposals. They must meet minimum reputation and stake requirements.

4. **Milestone Verifiers**: Addresses authorized to review and confirm milestone completion. Initially, the owner and designated verifiers hold this role.

5. **Governance System**: The collective decision-making entity composed of GIFT token holders, which approves or rejects proposals.

---

## **Data Structures**

### **Key Structs**

1. **Proposal**
   ```solidity
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
   ```

2. **Milestone**
   ```solidity
   struct Milestone {
       string title;
       string description;
       uint256 fundsRequired;
       bool isCompleted;
   }
   ```

3. **Vote**
   ```solidity
   struct Vote {
       bool support;     // true = for, false = against
       uint256 weight;   // amount of tokens
       bool hasVoted;    // whether address has already voted
   }
   ```

4. **TimelockTransfer**
   ```solidity
   struct TimelockTransfer {
       address recipient;
       uint256 amount;
       uint256 releaseTime;
       bool executed;
       bool cancelled;
   }
   ```

### **State Variables**

- **Minimum Requirements**:
  - `minStakeAmount`: Minimum GIFT tokens required as stake to propose (default: 1000 GIFT)
  - `minReputation`: Minimum reputation score required to propose (default: 100 points)

- **Voting Parameters**:
  - `quorumPercentage`: Minimum percentage of total GIFT supply that must vote (default: 10%)
  - `majorityPercentage`: Minimum percentage of votes that must be "For" (default: 50%)
  - `votingDuration`: Length of voting period (default: 5 days)

- **Timelock Parameters**:
  - `timelockDuration`: Time delay for large fund transfers (default: 2 days)
  - `timelockThreshold`: Amount threshold for timelocked transfers (default: 50,000 GIFT)

### **Mappings**

- **Proposal Storage**:
  ```solidity
  mapping(uint256 => Proposal) public proposals;
  ```

- **Vote Tracking**:
  ```solidity
  mapping(uint256 => mapping(address => Vote)) public votes;
  mapping(uint256 => uint256) public forVotes;
  mapping(uint256 => uint256) public againstVotes;
  ```

- **Milestone Release Tracking**:
  ```solidity
  mapping(uint256 => mapping(uint256 => bool)) public milestoneReleased;
  ```

- **Reputation Scores**:
  ```solidity
  mapping(address => uint256) public reputationScores;
  ```

- **Role Assignments**:
  ```solidity
  mapping(address => bool) public milestoneVerifiers;
  mapping(address => bool) public reputationManagers;
  ```

---

## **Key Components**

### **1. Governance Contract**

The GovernanceContract is the central decision-making mechanism of the DMO. It manages voting on proposals and executes approved decisions.

**Key Functions**:

- `voteOnProposal(uint256 proposalId, bool support)`: Allows GIFT holders to vote on a proposal
- `executeProposal(uint256 proposalId)`: Executes successful proposals after voting ends
- `isProposalPassed(uint256 proposalId)`: Checks if a proposal has passed (quorum + majority)
- `setVotingThresholds()`: Updates governance parameters (admin only)

**Events**:
- `ProposalVotingStarted(uint256 indexed proposalId, uint256 startTime, uint256 endTime)`
- `VoteCast(uint256 indexed proposalId, address indexed voter, bool support, uint256 weight)`
- `ProposalExecuted(uint256 indexed proposalId)`

**Workflow**:
1. When a proposal is submitted, the GovernanceContract initiates a voting period
2. Token holders vote during the specified period with weight proportional to their holdings
3. After the voting period ends, if quorum and majority thresholds are met, the proposal passes
4. Passed proposals trigger fund release for the first milestone

### **2. Proposal Contract**

The ProposalContract handles the submission and tracking of marketing proposals and their milestones.

**Key Functions**:

- `submitProposal(...)`: Creates a new marketing proposal with milestones
- `markMilestoneComplete(uint256 proposalId, uint256 milestoneIndex)`: Marks a milestone as completed
- `failProposal(uint256 proposalId)`: Marks a proposal as failed and triggers slashing
- `getProposal(uint256 proposalId)`: Retrieves proposal details

**Events**:
- `ProposalSubmitted(uint256 indexed proposalId, address indexed proposer, uint256 totalBudget)`
- `ProposalApproved(uint256 indexed proposalId)`
- `MilestoneCompleted(uint256 indexed proposalId, uint256 milestoneIndex)`
- `ProposalCompleted(uint256 indexed proposalId)`
- `ProposalFailed(uint256 indexed proposalId)`

**Workflow**:
1. A marketer creates a proposal with a description, budget, and milestones
2. They stake GIFT tokens as collateral
3. The proposal enters the voting phase
4. If approved, milestone completion is tracked
5. Verifiers confirm milestone completion
6. When all milestones are complete, the proposal is marked completed and stake returned

### **3. Rewards Contract (Treasury)**

The RewardsContract manages the DAO treasury and handles fund disbursement for approved proposals and completed milestones.

**Key Functions**:

- `allocateReward(uint256 proposalId, uint256 milestoneId, address recipient, uint256 amount)`: Disburses funds for a milestone
- `executeTimelockTransfer(uint256 timelockId)`: Executes a timelocked transfer after delay
- `claimReward(uint256 timelockId)`: Allows recipients to claim rewards after timelock expires

**Events**:
- `RewardAllocated(uint256 indexed proposalId, uint256 indexed milestoneId, address recipient, uint256 amount)`
- `TimelockTransferCreated(uint256 indexed timelockId, address recipient, uint256 amount, uint256 releaseTime)`
- `TimelockTransferExecuted(uint256 indexed timelockId, address recipient, uint256 amount)`

**Workflow**:
1. Treasury collects GIFT tokens via the transaction tax
2. When proposals are approved, funds are allocated for milestones
3. Small transfers happen immediately, large transfers are timelocked for security
4. Upon milestone completion, funds are released to the marketer

### **4. Reputation Contract**

The ReputationContract tracks the reputation scores of marketers based on their proposal performance history.

**Key Functions**:

- `updateReputation(address user, uint256 proposalId, uint256 points)`: Increases reputation for successful marketers
- `slashReputation(address user, uint256 proposalId, uint256 penalty)`: Decreases reputation for failed proposals
- `getReputation(address user)`: Returns a user's current reputation score

**Events**:
- `ReputationUpdated(address indexed user, uint256 proposalId, int256 change, uint256 newScore)`

**Workflow**:
1. New users start with zero reputation
2. Successful proposal completion earns reputation points
3. Failed proposals lose reputation points
4. Higher reputation provides advantages for future proposals
5. Reputation decays over time to encourage continued contribution

### **5. GIFT Token Integration**

The existing GIFT token contract includes a transaction tax mechanism that funds the DMO treasury.

**Integration Points**:

- Tax collection on transfers directed to the RewardsContract
- Token balance checks for voting weight
- Token transfers for staking and reward distribution

---

## **Core Workflows**

### **1. Proposal Submission and Staking**

**Prerequisites**:
- Proposer must have minimum reputation score (default: 100)
- Proposer must have enough GIFT tokens for stake (default: 1,000 GIFT)

**Process**:
1. Marketer calls `submitProposal()` with:
   - Proposal description
   - Total budget requested
   - Milestone details (titles, descriptions, and budget per milestone)
2. System verifies the proposer meets minimum requirements
3. Proposer stakes GIFT tokens as collateral
4. Proposal is assigned a unique ID and enters voting phase
5. `ProposalSubmitted` event is emitted

### **2. Voting Mechanism**

**Eligible Voters**:
- Any address holding GIFT tokens

**Process**:
1. Proposal enters voting period (default: 5 days)
2. Token holders call `voteOnProposal()` with:
   - Proposal ID
   - Support (true for "For", false for "Against")
3. Votes are weighted by token balance at time of voting
4. Voting ends after the voting period or when all tokens have voted
5. Proposal passes if:
   - Quorum is reached (default: 10% of total supply)
   - Majority threshold is met (default: >50% support)
6. If passed, `executeProposal()` can be called to approve the proposal

### **3. Milestone Completion and Verification**

**Verifiers**:
- Owner or designated milestone verifiers

**Process**:
1. Marketer completes a milestone off-chain
2. Marketer submits evidence of completion
3. Verifier reviews evidence
4. If satisfied, verifier calls `markMilestoneComplete()`
5. System updates milestone status and moves to next milestone
6. `MilestoneCompleted` event is emitted

### **4. Funds Disbursement**

**Trigger**:
- Proposal approval (first milestone)
- Milestone completion (subsequent milestones)

**Process**:
1. System calls `allocateReward()` with:
   - Proposal ID
   - Milestone ID
   - Recipient address
   - Amount to disburse
2. If amount < threshold, funds transfer immediately
3. If amount ≥ threshold, a timelock is created with delay
4. After delay, funds can be claimed or automatically disbursed
5. `RewardAllocated` event is emitted

### **5. Slashing Mechanism**

**Slashing Conditions**:
- Proposal fails voting
- Milestone verification fails
- Proposal declared failed by verifier

**Process**:
1. System calls `failProposal()`
2. Proposal status is updated to Failed
3. Staked tokens are transferred to treasury
4. Reputation is slashed via `slashReputation()`
5. `ProposalFailed` event is emitted

---

## **Technical Implementation Details**

### **Upgradeability Pattern**

The DMO uses the UUPS (Universal Upgradeable Proxy Standard) pattern for upgradeability:

- Each contract is deployed with a transparent proxy
- Logic contracts can be upgraded while preserving state
- Upgrades require owner authorization
- Contains safeguards against implementation address conflicts

### **Security Features**

1. **ReentrancyGuard**: Prevents reentrancy attacks during fund transfers
2. **Pausable**: Allows emergency pausing of system functionality
3. **Timelocks**: Delays large transfers for security review
4. **Role-Based Access**: Restricts functions to appropriate roles
5. **Snapshot Voting**: Prevents manipulation via flash loans

### **Event Logging**

Comprehensive events are emitted for all key actions, enabling:
- Off-chain tracking and indexing
- Transparent audit trail
- User notifications
- Governance monitoring

---

## **Integration Guide**

### **Deployment Sequence**

1. Deploy the ReputationContract implementation and proxy
2. Deploy the RewardsContract implementation and proxy
3. Deploy the ProposalContract implementation and proxy
4. Deploy the GovernanceContract implementation and proxy
5. Initialize each contract with required parameters
6. Set cross-contract references
   - ProposalContract → GovernanceContract
   - RewardsContract → GovernanceContract, ProposalContract
   - GIFT TaxManager → RewardsContract (as beneficiary)
7. Set up roles
   - Add milestone verifiers
   - Add reputation managers

### **Contract Interactions**

**Proposal Creation Flow**:
1. User → ProposalContract.submitProposal()
2. ProposalContract → GovernanceContract.createProposal()
3. GovernanceContract starts voting period

**Voting Flow**:
1. User → GovernanceContract.voteOnProposal()
2. After voting period → GovernanceContract.executeProposal()
3. GovernanceContract → ProposalContract.approveProposal()
4. GovernanceContract → RewardsContract.allocateReward() (first milestone)

**Milestone Completion Flow**:
1. Verifier → ProposalContract.markMilestoneComplete()
2. ProposalContract → RewardsContract.allocateReward()
3. If final milestone → ProposalContract completes proposal and returns stake

### **Upgrading Contracts**

1. Deploy new implementation contract
2. Call `upgradeToAndCall()` on the proxy
3. Verify storage compatibility
4. Test new functionality

---

## **Usage Examples**

### **Example 1: Submitting a Marketing Proposal**

```javascript
// Prepare proposal details
const description = "Twitter Marketing Campaign";
const totalBudget = ethers.utils.parseEther("5000"); // 5,000 GIFT

const milestoneTitles = [
  "Campaign Planning",
  "Initial Execution",
  "Campaign Conclusion"
];

const milestoneDescriptions = [
  "Research target audience and create content strategy",
  "Execute the first wave of tweets and promotional content",
  "Analyze results and provide final report"
];

const milestoneFunds = [
  ethers.utils.parseEther("1000"),  // 1,000 GIFT
  ethers.utils.parseEther("3000"),  // 3,000 GIFT
  ethers.utils.parseEther("1000")   // 1,000 GIFT
];

// Approve the ProposalContract to stake tokens
await giftToken.approve(proposalContract.address, ethers.utils.parseEther("1000"));

// Submit the proposal
await proposalContract.submitProposal(
  description,
  totalBudget,
  milestoneTitles,
  milestoneDescriptions,
  milestoneFunds
);
```

### **Example 2: Voting on a Proposal**

```javascript
// Vote in favor of proposal with ID 1
await governanceContract.voteOnProposal(1, true);

// Vote against proposal with ID 2
await governanceContract.voteOnProposal(2, false);
```

### **Example 3: Marking a Milestone as Complete**

```javascript
// Verify milestone 0 of proposal ID 1 as complete
await proposalContract.markMilestoneComplete(1, 0);
```

### **Example 4: Executing a Proposal After Voting**

```javascript
// Execute a proposal after voting period has ended
await governanceContract.executeProposal(1);
```

---

## **Security Considerations**

### **1. Economic Security**

- **Stake Sizing**: Ensure stake amount is proportional to proposal size to prevent economic attacks
- **Voting Thresholds**: Quorum and majority thresholds must balance security with realistic participation
- **Timelock Parameters**: Time delays for large transfers should be sufficient for security review

### **2. Attack Vectors**

- **Flashloan Attacks**: Snapshot voting prevents manipulation of voting power
- **Sybil Attacks**: Reputation system makes it costly to create multiple identities
- **Governance Attacks**: Quorum requirements prevent low-participation takeovers

### **3. Operational Security**

- **Verifier Centralization**: Initially, milestone verification may be centralized; consider moving to a more decentralized model over time
- **Parameter Updates**: Changes to core parameters should be gradual and well-communicated
- **Emergency Procedures**: Pause functionality should be used sparingly and only in genuine emergencies

### **4. Technical Security**

- **Upgrade Controls**: Ensure upgradeability does not introduce vulnerabilities
- **Integration Risks**: Maintain consistent interfaces between contracts
- **External Calls**: Minimize external contract calls during state changes

---

## **Appendix**

### **Glossary**

- **DMO**: Decentralized Marketing Organization, the entire governance system
- **Proposal**: A marketing initiative submitted for funding
- **Milestone**: A discrete, verifiable step within a proposal
- **Quorum**: Minimum participation threshold for valid votes
- **Stake**: GIFT tokens deposited as collateral when proposing
- **Slashing**: Penalty mechanism where stake is forfeited
- **Reputation**: On-chain score reflecting a marketer's track record

### **Configuration Parameters**

| Parameter | Default Value | Description |
|-----------|---------------|-------------|
| minStakeAmount | 1,000 GIFT | Minimum stake required to propose |
| minReputation | 100 points | Minimum reputation score to propose |
| quorumPercentage | 1000 (10%) | Percentage of total supply that must vote |
| majorityPercentage | 5000 (50%) | Percentage of votes needed for approval |
| votingDuration | 5 days | Length of voting period |
| timelockDuration | 2 days | Delay for large transfers |
| timelockThreshold | 50,000 GIFT | Threshold for timelock activation |
| reputationGain | 50 points | Reputation earned for successful proposal |
| reputationPenalty | 100 points | Reputation lost for failed proposal |

### **Function Selector Reference**

| Contract | Function | Selector |
|----------|----------|----------|
| GovernanceContract | voteOnProposal(uint256,bool) | 0x3bfe6de6 |
| GovernanceContract | executeProposal(uint256) | 0x0d61b519 |
| ProposalContract | submitProposal(string,uint256,string[],string[],uint256[]) | 0xfdcb5574 |
| ProposalContract | markMilestoneComplete(uint256,uint256) | 0xb8a4c8d7 |
| RewardsContract | allocateReward(uint256,uint256,address,uint256) | 0x7d9b3348 |
| ReputationContract | getReputation(address) | 0x5f649744 |

---


# **Contact Information**

For support or inquiries, please contact:

- **Email**: [kassy@utribe.one](mailto:kassy@utribe.one)
- **Website**: [www.utribe.one](http://www.utribe.one)

---

# **Version History**

- **v1.0**: Initial documentation release for DMO smart contract system.