// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract GroupVotingSystem {
    // Enum definitions
    enum ProposalStatus { Pending, Accepted, Rejected, Cancelled }
    enum VoteType { None, For, Against }

    // Proposal structure
    struct Proposal {
        uint256 id;
        string description;
        address proposer;
        uint256 createdAt;
        uint256 votingDeadline;
        ProposalStatus status;
        uint256 totalVotes;
        uint256 votesFor;
        mapping(address => bool) hasVoted;
        mapping(address => VoteType) votes;
    }

    // Events
    event ProposalCreated(uint256 indexed proposalId, string description, address indexed proposer);
    event VoteCast(uint256 indexed proposalId, address indexed voter, VoteType voteType);
    event ProposalFinalized(uint256 indexed proposalId, ProposalStatus status);
    event ProposalCancelled(uint256 indexed proposalId);
    event MemberAdded(address indexed member);
    event MemberRemoved(address indexed member);

    // Constants
    uint256 public constant MIN_VOTING_DURATION = 1 days;
    uint256 public constant MAX_VOTING_DURATION = 30 days;

    // State variables
    address public owner;
    uint256 public proposalCount;
    mapping(uint256 => Proposal) public proposals;
    mapping(address => bool) public groupMembers;
    uint256 public memberCount;
    uint256 public requiredQuorumPercent;
    uint256 public votingPeriod;

    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Caller is not the owner");
        _;
    }

    modifier onlyGroupMember() {
        require(groupMembers[msg.sender], "Caller is not a group member");
        _;
    }

    modifier onlyPending(uint256 _proposalId) {
        require(proposals[_proposalId].status == ProposalStatus.Pending, "Proposal is not pending");
        _;
    }

    modifier onlyOpen(uint256 _proposalId) {
        require(block.timestamp <= proposals[_proposalId].votingDeadline, "Voting is closed");
        _;
    }

    // Constructor
    constructor(uint256 _requiredQuorumPercent, uint256 _votingPeriod) {
        require(_requiredQuorumPercent > 0 && _requiredQuorumPercent <= 100, "Invalid quorum percent");
        require(_votingPeriod >= MIN_VOTING_DURATION && _votingPeriod <= MAX_VOTING_DURATION, "Voting period out of range");

        owner = msg.sender;
        requiredQuorumPercent = _requiredQuorumPercent;
        votingPeriod = _votingPeriod;

        groupMembers[msg.sender] = true;
        memberCount = 1;
    }

    // Group management
    function addGroupMember(address _member) external onlyOwner {
        require(_member != address(0), "Invalid address");
        require(!groupMembers[_member], "Already a member");

        groupMembers[_member] = true;
        memberCount++;

        emit MemberAdded(_member);
    }

    function removeGroupMember(address _member) external onlyOwner {
        require(groupMembers[_member], "Not a member");

        groupMembers[_member] = false;
        memberCount--;

        emit MemberRemoved(_member);
    }

    // Proposal creation
    function createProposal(string calldata _description) external onlyGroupMember returns (uint256) {
        proposalCount++;

        Proposal storage p = proposals[proposalCount];
        p.id = proposalCount;
        p.description = _description;
        p.proposer = msg.sender;
        p.createdAt = block.timestamp;
        p.votingDeadline = block.timestamp + votingPeriod;
        p.status = ProposalStatus.Pending;

        emit ProposalCreated(p.id, _description, msg.sender);
        return p.id;
    }

    // Voting
    function vote(uint256 _proposalId, VoteType _voteType) external onlyGroupMember onlyPending(_proposalId) onlyOpen(_proposalId) {
        require(_voteType == VoteType.For || _voteType == VoteType.Against, "Invalid vote type");

        Proposal storage p = proposals[_proposalId];
        require(!p.hasVoted[msg.sender], "Already voted");

        p.hasVoted[msg.sender] = true;
        p.votes[msg.sender] = _voteType;
        p.totalVotes++;

        if (_voteType == VoteType.For) {
            p.votesFor++;
        }

        emit VoteCast(_proposalId, msg.sender, _voteType);
    }

    // Finalizing proposal
    function finalizeProposal(uint256 _proposalId) external onlyOwner onlyPending(_proposalId) {
        Proposal storage p = proposals[_proposalId];
        require(block.timestamp > p.votingDeadline, "Voting period not ended");

        uint256 totalVotes = p.totalVotes;
        uint256 quorum = (memberCount * requiredQuorumPercent) / 100;

        if (totalVotes >= quorum) {
            p.status = (p.votesFor > totalVotes - p.votesFor) ? ProposalStatus.Accepted : ProposalStatus.Rejected;
        } else {
            p.status = ProposalStatus.Rejected;
        }

        emit ProposalFinalized(_proposalId, p.status);
    }

    // Cancelling a proposal
    function cancelProposal(uint256 _proposalId) external onlyOwner onlyPending(_proposalId) {
        Proposal storage p = proposals[_proposalId];

        p.status = ProposalStatus.Cancelled;
        emit ProposalCancelled(_proposalId);
    }

    // View proposal details
    function getProposalDetails(uint256 _proposalId) external view returns (
        string memory description,
        address proposer,
        uint256 createdAt,
        uint256 votingDeadline,
        ProposalStatus status,
        uint256 votesFor,
        uint256 votesAgainst
    ) {
        Proposal storage p = proposals[_proposalId];
        return (
            p.description,
            p.proposer,
            p.createdAt,
            p.votingDeadline,
            p.status,
            p.votesFor,
            p.totalVotes - p.votesFor
        );
    }

    // Check group membership
    function isGroupMember(address _addr) external view returns (bool) {
        return groupMembers[_addr];
    }
}
