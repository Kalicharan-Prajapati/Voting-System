// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract GroupVotingSystem {
    // Voting proposal structure
    struct Proposal {
        uint256 id;
        string description;
        address proposer;
        uint256 createdAt;
        uint256 votingDeadline;
        ProposalStatus status;
        uint256 votesFor;
        uint256 votesAgainst;
        mapping(address => bool) hasVoted;
        mapping(address => VoteType) votes;
    }

    // Enum for proposal status
    enum ProposalStatus {
        Pending,
        Accepted,
        Rejected,
        Cancelled
    }

    // Enum for vote types
    enum VoteType {
        None,
        For,
        Against
    }

    // Events for transparency and tracking
    event ProposalCreated(
        uint256 indexed proposalId, 
        string description, 
        address indexed proposer
    );
    event VoteCast(
        uint256 indexed proposalId, 
        address indexed voter, 
        VoteType voteType
    );
    event ProposalFinalized(
        uint256 indexed proposalId, 
        ProposalStatus status
    );

    // Contract management
    address public owner;
    uint256 public constant MIN_VOTING_DURATION = 1 days;
    uint256 public constant MAX_VOTING_DURATION = 30 days;
    uint256 public proposalCount;

    // Group membership and permissions
    mapping(address => bool) public groupMembers;
    uint256 public memberCount;

    // Proposal tracking
    mapping(uint256 => Proposal) public proposals;

    // Voting configuration
    uint256 public requiredQuorum;
    uint256 public votingPeriod;

    // Modifiers for access control
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can perform this action");
        _;
    }

    modifier onlyGroupMember() {
        require(groupMembers[msg.sender], "Only group members can vote");
        _;
    }

    constructor(uint256 _requiredQuorum, uint256 _votingPeriod) {
        owner = msg.sender;
        requiredQuorum = _requiredQuorum;
        votingPeriod = _votingPeriod;

        // Add contract creator as initial group member
        groupMembers[msg.sender] = true;
        memberCount = 1;
    }

    // Group management functions
    function addGroupMember(address _member) external onlyOwner {
        require(!groupMembers[_member], "Member already exists");
        groupMembers[_member] = true;
        memberCount++;
    }

    function removeGroupMember(address _member) external onlyOwner {
        require(groupMembers[_member], "Member does not exist");
        groupMembers[_member] = false;
        memberCount--;
    }

    // Proposal creation function
    function createProposal(string memory _description) 
        external 
        onlyGroupMember 
        returns (uint256)
    {
        proposalCount++;
        
        Proposal storage newProposal = proposals[proposalCount];
        newProposal.id = proposalCount;
        newProposal.description = _description;
        newProposal.proposer = msg.sender;
        newProposal.createdAt = block.timestamp;
        newProposal.votingDeadline = block.timestamp + votingPeriod;
        newProposal.status = ProposalStatus.Pending;

        emit ProposalCreated(proposalCount, _description, msg.sender);
        return proposalCount;
    }

    // Voting function
    function vote(uint256 _proposalId, VoteType _voteType) 
        external 
        onlyGroupMember
    {
        Proposal storage proposal = proposals[_proposalId];
        
        // Validation checks
        require(block.timestamp <= proposal.votingDeadline, "Voting period has ended");
        require(!proposal.hasVoted[msg.sender], "Already voted");
        require(_voteType != VoteType.None, "Invalid vote type");

        // Record vote
        proposal.hasVoted[msg.sender] = true;
        proposal.votes[msg.sender] = _voteType;

        // Update vote counts
        if (_voteType == VoteType.For) {
            proposal.votesFor++;
        } else {
            proposal.votesAgainst++;
        }

        emit VoteCast(_proposalId, msg.sender, _voteType);
    }

    // Finalize proposal
    function finalizeProposal(uint256 _proposalId) external {
        Proposal storage proposal = proposals[_proposalId];
        
        // Validation checks
        require(block.timestamp > proposal.votingDeadline, "Voting period not ended");
        require(proposal.status == ProposalStatus.Pending, "Proposal already finalized");

        // Calculate participation
        uint256 totalVotes = proposal.votesFor + proposal.votesAgainst;
        uint256 participationRate = (totalVotes * 100) / memberCount;

        // Determine proposal outcome
        if (participationRate >= requiredQuorum) {
            if (proposal.votesFor > proposal.votesAgainst) {
                proposal.status = ProposalStatus.Accepted;
            } else {
                proposal.status = ProposalStatus.Rejected;
            }
        } else {
            proposal.status = ProposalStatus.Rejected;
        }

        emit ProposalFinalized(_proposalId, proposal.status);
    }

    // View functions for proposal details
    function getProposalDetails(uint256 _proposalId) 
        external 
        view 
        returns (
            string memory description,
            address proposer,
            uint256 createdAt,
            uint256 votingDeadline,
            ProposalStatus status,
            uint256 votesFor,
            uint256 votesAgainst
        )
    {
        Proposal storage proposal = proposals[_proposalId];
        return (
            proposal.description,
            proposal.proposer,
            proposal.createdAt,
            proposal.votingDeadline,
            proposal.status,
            proposal.votesFor,
            proposal.votesAgainst
        );
    }

    // Group membership check
    function isGroupMember(address _member) external view returns (bool) {
        return groupMembers[_member];
    }
}