// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract GroupVotingSystem {
    enum ProposalStatus { Pending, Accepted, Rejected, Cancelled }
    enum VoteType { None, For, Against }

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

    uint256 public constant MIN_VOTING_DURATION = 1 days;
    uint256 public constant MAX_VOTING_DURATION = 30 days;

    address public owner;
    mapping(uint256 => Proposal) public proposals;
    mapping(address => bool) public groupMembers;
    uint256 public memberCount;
    uint256 public requiredQuorumPercent;
    uint256 public votingPeriod;

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

    constructor(uint256 _requiredQuorumPercent, uint256 _votingPeriod) {
        require(_requiredQuorumPercent > 0 && _requiredQuorumPercent <= 100, "Invalid quorum percent");
        require(_votingPeriod >= MIN_VOTING_DURATION && _votingPeriod <= MAX_VOTING_DURATION, "Voting period out of range");

        owner = msg.sender;
        requiredQuorumPercent = _requiredQuorumPercent;
        votingPeriod = _votingPeriod;

        groupMembers[msg.sender] = true;
        memberCount = 1;
    }

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

    function createProposal(string calldata _description) external onlyGroupMember returns (uint256) {
        uint256 proposalId = proposals.length;
        Proposal storage p = proposals[proposalId];

        p.description = _description;
        p.proposer = msg.sender;
        p.createdAt = block.timestamp;
        p.votingDeadline = block.timestamp + votingPeriod;
        p.status = ProposalStatus.Pending;

        emit ProposalCreated(proposalId, _description, msg.sender);
        return proposalId;
    }

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

    function withdrawVote(uint256 _proposalId) external onlyGroupMember onlyPending(_proposalId) onlyOpen(_proposalId) {
        Proposal storage p = proposals[_proposalId];
        require(p.hasVoted[msg.sender], "Has not voted");

        p.hasVoted[msg.sender] = false;
        p.totalVotes--;

        if (p.votes[msg.sender] == VoteType.For) {
            p.votesFor--;
        }

        emit VoteWithdrawn(_proposalId, msg.sender);
    }

    function finalizeProposal(uint256 _proposalId) external onlyOwner onlyPending(_proposalId) {
        Proposal storage p = proposals[_proposalId];

        // Check if voting period has ended
        require(block.timestamp > p.votingDeadline, "Voting is still open");

        // Check if quorum is met
        uint256 totalGroupMembers = memberCount;
        uint256 totalVotes = p.totalVotes;
        uint256 quorum = (totalVotes * 100) / totalGroupMembers;
        require(quorum >= requiredQuorumPercent, "Quorum not met");

        // Determine proposal status based on votes
        if (p.votesFor > totalVotes / 2) {
            p.status = ProposalStatus.Accepted;
        } else {
            p.status = ProposalStatus.Rejected;
        }

        emit ProposalFinalized(_proposalId, p.status);
    }

    function cancelProposal(uint256 _proposalId) external onlyOwner onlyPending(_proposalId) {
        Proposal storage p = proposals[_proposalId];
        p.status = ProposalStatus.Cancelled;

        emit ProposalCancelled(_proposalId);
    }

    function amendProposal(uint256 _proposalId, string calldata _newDescription, uint256 _newDeadline) external onlyOwner onlyPending(_proposalId) {
        Proposal storage p = proposals[_proposalId];

        p.description = _newDescription;
        p.votingDeadline = block.timestamp + _newDeadline;

        emit ProposalAmended(_proposalId, _newDescription, p.votingDeadline);
    }

    function adjustQuorum(uint256 _newQuorumPercent) external onlyOwner {
        require(_newQuorumPercent > 0 && _newQuorumPercent <= 100, "Invalid quorum percent");
        requiredQuorumPercent = _newQuorumPercent;

        emit QuorumAdjusted(_newQuorumPercent);
    }

    function extendVotingPeriod(uint256 _proposalId, uint256 _newDeadline) external onlyOwner onlyPending(_proposalId) {
        require(_newDeadline > block.timestamp + votingPeriod, "New deadline must be after current deadline");

        Proposal storage p = proposals[_proposalId];
        p.votingDeadline = _newDeadline;

        emit VotingExtended(_proposalId, _newDeadline);
    }
}
