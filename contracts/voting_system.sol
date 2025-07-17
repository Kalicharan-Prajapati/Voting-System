// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract GroupVotingSystem {
    // Enums
    enum ProposalStatus { Pending, Accepted, Rejected, Cancelled }
    enum VoteType { None, For, Against }

    // Structs
    struct Proposal {
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

    struct ProposalDetails {
        string description;
        address proposer;
        uint256 createdAt;
        uint256 votingDeadline;
        ProposalStatus status;
        uint256 totalVotes;
        uint256 votesFor;
    }

    // Events
    event ProposalCreated(uint256 indexed proposalId, string description, address indexed proposer);
    event VoteCast(uint256 indexed proposalId, address indexed voter, VoteType voteType);
    event VoteWithdrawn(uint256 indexed proposalId, address indexed voter);
    event ProposalFinalized(uint256 indexed proposalId, ProposalStatus status);
    event ProposalCancelled(uint256 indexed proposalId);
    event MemberAdded(address indexed member);
    event MemberRemoved(address indexed member);
    event ProposalAmended(uint256 indexed proposalId, string newDescription, uint256 newDeadline);
    event QuorumAdjusted(uint256 newQuorumPercent);
    event VotingExtended(uint256 indexed proposalId, uint256 newDeadline);

    // Constants
    uint256 public constant MIN_VOTING_DURATION = 1 days;
    uint256 public constant MAX_VOTING_DURATION = 30 days;

    // State variables
    address public owner;
    uint256 public memberCount;
    uint256 public requiredQuorumPercent;
    uint256 public votingPeriod;
    mapping(uint256 => Proposal) private proposals;
    mapping(address => bool) public groupMembers;

    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Not the contract owner");
        _;
    }

    modifier onlyGroupMember() {
        require(groupMembers[msg.sender], "Not a group member");
        _;
    }

    modifier onlyPending(uint256 proposalId) {
        require(proposals[proposalId].status == ProposalStatus.Pending, "Proposal is not pending");
        _;
    }

    modifier onlyOpen(uint256 proposalId) {
        require(block.timestamp <= proposals[proposalId].votingDeadline, "Voting period is over");
        _;
    }

    // Constructor
    constructor(uint256 _quorumPercent, uint256 _votingPeriod) {
        require(_quorumPercent > 0 && _quorumPercent <= 100, "Invalid quorum percent");
        require(_votingPeriod >= MIN_VOTING_DURATION && _votingPeriod <= MAX_VOTING_DURATION, "Voting period out of bounds");

        owner = msg.sender;
        requiredQuorumPercent = _quorumPercent;
        votingPeriod = _votingPeriod;

        groupMembers[owner] = true;
        memberCount = 1;
    }

    // ---------------- Member Management ----------------

    function addGroupMember(address member) external onlyOwner {
        require(member != address(0), "Invalid address");
        require(!groupMembers[member], "Already a member");

        groupMembers[member] = true;
        memberCount++;

        emit MemberAdded(member);
    }

    function removeGroupMember(address member) external onlyOwner {
        require(groupMembers[member], "Not a member");

        groupMembers[member] = false;
        memberCount--;

        emit MemberRemoved(member);
    }

    // ---------------- Proposal Management ----------------

    function createProposal(string calldata description) external onlyGroupMember returns (uint256 proposalId) {
        proposalId = uint256(keccak256(abi.encodePacked(msg.sender, block.timestamp, description)));

        Proposal storage p = proposals[proposalId];
        p.description = description;
        p.proposer = msg.sender;
        p.createdAt = block.timestamp;
        p.votingDeadline = block.timestamp + votingPeriod;
        p.status = ProposalStatus.Pending;

        emit ProposalCreated(proposalId, description, msg.sender);
    }

    function amendProposal(uint256 proposalId, string calldata newDescription, uint256 newDuration)
        external onlyOwner onlyPending(proposalId)
    {
        require(newDuration >= MIN_VOTING_DURATION && newDuration <= MAX_VOTING_DURATION, "Invalid duration");

        Proposal storage p = proposals[proposalId];
        p.description = newDescription;
        p.votingDeadline = block.timestamp + newDuration;

        emit ProposalAmended(proposalId, newDescription, p.votingDeadline);
    }

    function cancelProposal(uint256 proposalId) external onlyOwner onlyPending(proposalId) {
        proposals[proposalId].status = ProposalStatus.Cancelled;
        emit ProposalCancelled(proposalId);
    }

    function finalizeProposal(uint256 proposalId) external onlyOwner onlyPending(proposalId) {
        Proposal storage p = proposals[proposalId];
        require(block.timestamp > p.votingDeadline, "Voting still active");

        uint256 quorum = (p.totalVotes * 100) / memberCount;
        require(quorum >= requiredQuorumPercent, "Quorum not met");

        p.status = (p.votesFor > p.totalVotes / 2) ? ProposalStatus.Accepted : ProposalStatus.Rejected;

        emit ProposalFinalized(proposalId, p.status);
    }

    function extendVotingPeriod(uint256 proposalId, uint256 newDeadline)
        external onlyOwner onlyPending(proposalId)
    {
        require(newDeadline > proposals[proposalId].votingDeadline, "Must be after current deadline");
        require(newDeadline <= block.timestamp + MAX_VOTING_DURATION, "Too far in the future");

        proposals[proposalId].votingDeadline = newDeadline;

        emit VotingExtended(proposalId, newDeadline);
    }

    // ---------------- Voting Functions ----------------

    function vote(uint256 proposalId, VoteType voteType)
        external onlyGroupMember onlyPending(proposalId) onlyOpen(proposalId)
    {
        require(voteType == VoteType.For || voteType == VoteType.Against, "Invalid vote type");

        Proposal storage p = proposals[proposalId];
        require(!p.hasVoted[msg.sender], "Already voted");

        p.hasVoted[msg.sender] = true;
        p.votes[msg.sender] = voteType;
        p.totalVotes++;

        if (voteType == VoteType.For) {
            p.votesFor++;
        }

        emit VoteCast(proposalId, msg.sender, voteType);
    }

    function withdrawVote(uint256 proposalId)
        external onlyGroupMember onlyPending(proposalId) onlyOpen(proposalId)
    {
        Proposal storage p = proposals[proposalId];
        require(p.hasVoted[msg.sender], "No vote to withdraw");

        if (p.votes[msg.sender] == VoteType.For) {
            p.votesFor--;
        }

        p.hasVoted[msg.sender] = false;
        p.totalVotes--;

        emit VoteWithdrawn(proposalId, msg.sender);
    }

    // ---------------- Config Functions ----------------

    function adjustQuorum(uint256 newPercent) external onlyOwner {
        require(newPercent > 0 && newPercent <= 100, "Invalid quorum percent");
        requiredQuorumPercent = newPercent;

        emit QuorumAdjusted(newPercent);
    }

    // ---------------- View Functions ----------------

    function getProposalDetails(uint256 proposalId) external view returns (ProposalDetails memory) {
        Proposal storage p = proposals[proposalId];
        return ProposalDetails({
            description: p.description,
            proposer: p.proposer,
            createdAt: p.createdAt,
            votingDeadline: p.votingDeadline,
            status: p.status,
            totalVotes: p.totalVotes,
            votesFor: p.votesFor
        });
    }

    function hasVoted(uint256 proposalId, address member) external view returns (bool) {
        return proposals[proposalId].hasVoted[member];
    }

    function getMemberVote(uint256 proposalId, address member) external view returns (VoteType) {
        return proposals[proposalId].votes[member];
    }

    function isGroupMember(address member) external view returns (bool) {
        return groupMembers[member];
    }

    function getRequiredQuorumPercent() external view returns (uint256) {
        return requiredQuorumPercent;
    }

    function getVotingPeriod() external view returns (uint256) {
        return votingPeriod;
    }

    function getProposalStatus(uint256 proposalId) external view returns (ProposalStatus) {
        return proposals[proposalId].status;
    }
}
