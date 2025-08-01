// SPDX-License-Identifier: 
pragma solidity ^0.8.0;

contract GroupVotingSystem {
    // ---------------- Enums ----------------
    enum ProposalStatus { Pending, Accepted, Rejected, Cancelled }
    enum VoteType { None, For, Against }

    // ---------------- Structs ----------------
    struct ProposalData {
        string description;
        address proposer;
        uint256 createdAt;
        uint256 votingDeadline;
        ProposalStatus status;
        uint256 totalVotes;
        uint256 votesFor;
    }

    // ---------------- State Variables ----------------
    address public owner;
    uint256 public memberCount;
    uint256 public requiredQuorumPercent;
    uint256 public votingPeriod;

    uint256 public constant MIN_VOTING_DURATION = 1 days;
    uint256 public constant MAX_VOTING_DURATION = 30 days;

    mapping(address => bool) public groupMembers;
    mapping(uint256 => ProposalData) private proposals;
    mapping(uint256 => mapping(address => bool)) private hasVoted;
    mapping(uint256 => mapping(address => VoteType)) private voteRecord;

    uint256[] private allProposalIds;

    // ---------------- Events ----------------
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
    event VotingPeriodUpdated(uint256 newPeriod);

    // ---------------- Modifiers ----------------
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    modifier onlyMember() {
        require(groupMembers[msg.sender], "Not a member");
        _;
    }

    modifier proposalExists(uint256 proposalId) {
        require(proposals[proposalId].createdAt != 0, "Proposal does not exist");
        _;
    }

    modifier isPending(uint256 proposalId) {
        require(proposals[proposalId].status == ProposalStatus.Pending, "Proposal not pending");
        _;
    }

    modifier votingOpen(uint256 proposalId) {
        require(block.timestamp <= proposals[proposalId].votingDeadline, "Voting closed");
        _;
    }

    // ---------------- Constructor ----------------
    constructor(uint256 quorumPercent, uint256 period) {
        require(quorumPercent > 0 && quorumPercent <= 100, "Invalid quorum");
        require(period >= MIN_VOTING_DURATION && period <= MAX_VOTING_DURATION, "Voting period out of range");

        owner = msg.sender;
        groupMembers[owner] = true;
        memberCount = 1;
        requiredQuorumPercent = quorumPercent;
        votingPeriod = period;
    }

    // ---------------- Member Management ----------------
    function addGroupMember(address member) external onlyOwner {
        require(member != address(0) && !groupMembers[member], "Invalid or existing member");
        groupMembers[member] = true;
        memberCount++;
        emit MemberAdded(member);
    }

    function addGroupMembers(address[] calldata members) external onlyOwner {
        for (uint256 i = 0; i < members.length; i++) {
            address member = members[i];
            if (member != address(0) && !groupMembers[member]) {
                groupMembers[member] = true;
                memberCount++;
                emit MemberAdded(member);
            }
        }
    }

    function removeGroupMember(address member) external onlyOwner {
        require(groupMembers[member], "Not a member");
        groupMembers[member] = false;
        memberCount--;
        emit MemberRemoved(member);
    }

    // ---------------- Proposal Management ----------------
    function createProposal(string calldata description) external onlyMember returns (uint256 proposalId) {
        proposalId = uint256(keccak256(abi.encodePacked(msg.sender, block.timestamp, description)));
        require(proposals[proposalId].createdAt == 0, "Proposal already exists");

        proposals[proposalId] = ProposalData({
            description: description,
            proposer: msg.sender,
            createdAt: block.timestamp,
            votingDeadline: block.timestamp + votingPeriod,
            status: ProposalStatus.Pending,
            totalVotes: 0,
            votesFor: 0
        });

        allProposalIds.push(proposalId);
        emit ProposalCreated(proposalId, description, msg.sender);
    }

    function amendProposal(uint256 proposalId, string calldata newDesc, uint256 newDuration)
        external onlyOwner proposalExists(proposalId) isPending(proposalId)
    {
        require(newDuration >= MIN_VOTING_DURATION && newDuration <= MAX_VOTING_DURATION, "Invalid duration");
        ProposalData storage p = proposals[proposalId];
        p.description = newDesc;
        p.votingDeadline = block.timestamp + newDuration;

        emit ProposalAmended(proposalId, newDesc, p.votingDeadline);
    }

    function cancelProposal(uint256 proposalId)
        external onlyOwner proposalExists(proposalId) isPending(proposalId)
    {
        proposals[proposalId].status = ProposalStatus.Cancelled;
        emit ProposalCancelled(proposalId);
    }

    function finalizeProposal(uint256 proposalId)
        external onlyOwner proposalExists(proposalId) isPending(proposalId)
    {
        ProposalData storage p = proposals[proposalId];
        require(block.timestamp > p.votingDeadline, "Voting still active");

        uint256 quorum = (p.totalVotes * 100) / memberCount;
        require(quorum >= requiredQuorumPercent, "Quorum not met");

        p.status = (p.votesFor > p.totalVotes / 2) ? ProposalStatus.Accepted : ProposalStatus.Rejected;
        emit ProposalFinalized(proposalId, p.status);
    }

    function extendVotingPeriod(uint256 proposalId, uint256 newDeadline)
        external onlyOwner proposalExists(proposalId) isPending(proposalId)
    {
        require(newDeadline > proposals[proposalId].votingDeadline, "New deadline too early");
        require(newDeadline <= block.timestamp + MAX_VOTING_DURATION, "Exceeds max duration");

        proposals[proposalId].votingDeadline = newDeadline;
        emit VotingExtended(proposalId, newDeadline);
    }

    // ---------------- Voting ----------------
    function vote(uint256 proposalId, VoteType voteType)
        external onlyMember proposalExists(proposalId) isPending(proposalId) votingOpen(proposalId)
    {
        require(voteType == VoteType.For || voteType == VoteType.Against, "Invalid vote");
        require(!hasVoted[proposalId][msg.sender], "Already voted");

        hasVoted[proposalId][msg.sender] = true;
        voteRecord[proposalId][msg.sender] = voteType;
        ProposalData storage p = proposals[proposalId];
        p.totalVotes++;
        if (voteType == VoteType.For) p.votesFor++;

        emit VoteCast(proposalId, msg.sender, voteType);
    }

    function withdrawVote(uint256 proposalId)
        external onlyMember proposalExists(proposalId) isPending(proposalId) votingOpen(proposalId)
    {
        require(hasVoted[proposalId][msg.sender], "No vote to withdraw");

        ProposalData storage p = proposals[proposalId];
        if (voteRecord[proposalId][msg.sender] == VoteType.For) p.votesFor--;

        hasVoted[proposalId][msg.sender] = false;
        p.totalVotes--;

        emit VoteWithdrawn(proposalId, msg.sender);
    }

    // ---------------- Configuration ----------------
    function adjustQuorum(uint256 percent) external onlyOwner {
        require(percent > 0 && percent <= 100, "Invalid percent");
        requiredQuorumPercent = percent;
        emit QuorumAdjusted(percent);
    }

    function updateVotingPeriod(uint256 period) external onlyOwner {
        require(period >= MIN_VOTING_DURATION && period <= MAX_VOTING_DURATION, "Invalid period");
        votingPeriod = period;
        emit VotingPeriodUpdated(period);
    }

    
    function getProposal(uint256 proposalId) external view returns (ProposalData memory) {
        return proposals[proposalId];
    }

    function hasMemberVoted(uint256 proposalId, address voter) external view returns (bool) {
        return hasVoted[proposalId][voter];
    }

    function getMemberVote(uint256 proposalId, address voter) external view returns (VoteType) {
        return voteRecord[proposalId][voter];
    }

    function isMember(address addr) external view returns (bool) {
        return groupMembers[addr];
    }

    function getAllProposalIds() external view returns (uint256[] memory) {
        return allProposalIds;
    }

    function getProposalsByStatus(ProposalStatus status) external view returns (uint256[] memory) {
        uint256 count;
        for (uint256 i = 0; i < allProposalIds.length; i++) {
            if (proposals[allProposalIds[i]].status == status) count++;
        }

        uint256[] memory filtered = new uint256[](count);
        uint256 index;
        for (uint256 i = 0; i < allProposalIds.length; i++) {
            if (proposals[allProposalIds[i]].status == status) {
                filtered[index++] = allProposalIds[i];
            }
        }

        return filtered;
    }

    function getTimeRemaining(uint256 proposalId) external view proposalExists(proposalId) returns (uint256) {
        uint256 deadline = proposals[proposalId].votingDeadline;
        return block.timestamp >= deadline ? 0 : deadline - block.timestamp;
    }

    function getVotingSummary(uint256 proposalId)
        external view proposalExists(proposalId)
        returns (string memory, ProposalStatus, uint256, uint256)
    {
        ProposalData storage p = proposals[proposalId];
        return (p.description, p.status, p.votesFor, p.totalVotes);
    }

    function totalProposals() external view returns (uint256) {
        return allProposalIds.length;
    }

    function getActiveProposals() external view returns (uint256[] memory) {
        uint256 count;
        for (uint256 i = 0; i < allProposalIds.length; i++) {
            ProposalData storage p = proposals[allProposalIds[i]];
            if (p.status == ProposalStatus.Pending && block.timestamp <= p.votingDeadline) count++;
        }

        uint256[] memory active = new uint256[](count);
        uint256 index;
        for (uint256 i = 0; i < allProposalIds.length; i++) {
            ProposalData storage p = proposals[allProposalIds[i]];
            if (p.status == ProposalStatus.Pending && block.timestamp <= p.votingDeadline) {
                active[index++] = allProposalIds[i];
            }
        }

        return active;
    }
}
