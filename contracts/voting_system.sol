// SPDX-License-Identifier:  
pragma solidity ^0.8.0;

contract GroupVotingSystem {
    // ------------------ Enums ------------------
    enum ProposalStatus { Pending, Accepted, Rejected, Cancelled }
    enum VoteType { None, For, Against }

    // ------------------ Structs ------------------
    struct ProposalData {
        string description;
        address proposer;
        uint256 createdAt;
        uint256 votingDeadline;
        ProposalStatus status;
        uint256 totalVotes;
        uint256 votesFor;
    }

    // ------------------ State Variables ------------------
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
    mapping(address => address) public voteDelegates;

    uint256[] private allProposalIds;

    // ------------------ Events ------------------
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
    event VoteDelegated(address indexed from, address indexed to);
    event DelegationRevoked(address indexed member);
    event ProposalDescriptionUpdated(uint256 indexed proposalId, string newDescription);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // ------------------ Modifiers ------------------
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can perform this action");
        _;
    }

    modifier onlyMember() {
        require(groupMembers[msg.sender], "You are not a group member");
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
        require(block.timestamp <= proposals[proposalId].votingDeadline, "Voting has closed");
        _;
    }

    // ------------------ Constructor ------------------
    constructor(uint256 quorumPercent, uint256 period) {
        require(quorumPercent > 0 && quorumPercent <= 100, "Invalid quorum percent");
        require(period >= MIN_VOTING_DURATION && period <= MAX_VOTING_DURATION, "Invalid voting period");

        owner = msg.sender;
        groupMembers[owner] = true;
        memberCount = 1;
        requiredQuorumPercent = quorumPercent;
        votingPeriod = period;
    }

    // ------------------ Member Management ------------------
    function addGroupMember(address member) external onlyOwner {
        require(member != address(0), "Invalid address");
        require(!groupMembers[member], "Member already exists");

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
        require(groupMembers[member], "Address is not a member");

        groupMembers[member] = false;
        memberCount--;
        emit MemberRemoved(member);
    }
 // ------------------ Voting Delegation ------------------
    function delegateVote(address to) external onlyMember {
        require(to != msg.sender, "Cannot delegate to self");
        require(groupMembers[to], "Can only delegate to members");
        voteDelegates[msg.sender] = to;
        emit VoteDelegated(msg.sender, to);
    }

    function revokeDelegation() external onlyMember {
        delete voteDelegates[msg.sender];
        emit DelegationRevoked(msg.sender);
    }

    // ------------------ Proposal Management ------------------
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

    function updateProposalDescription(uint256 proposalId, string calldata newDescription) 
        external proposalExists(proposalId) isPending(proposalId) {
        require(msg.sender == proposals[proposalId].proposer || msg.sender == owner, "Not authorized");
        proposals[proposalId].description = newDescription;
        emit ProposalDescriptionUpdated(proposalId, newDescription);
    }

    function emergencyCancelProposal(uint256 proposalId) external onlyOwner {
        ProposalData storage p = proposals[proposalId];
        require(p.status == ProposalStatus.Pending, "Proposal not active");
        p.status = ProposalStatus.Cancelled;
        emit ProposalCancelled(proposalId);
    }

    function cancelProposal(uint256 proposalId)
        external onlyOwner proposalExists(proposalId) isPending(proposalId)
    {
        proposals[proposalId].status = ProposalStatus.Cancelled;
        emit ProposalCancelled(proposalId);
    }

    function extendVotingPeriod(uint256 proposalId, uint256 newDeadline)
        external onlyOwner proposalExists(proposalId) isPending(proposalId)
    {
        require(newDeadline > proposals[proposalId].votingDeadline, "New deadline must be in the future");
        require(newDeadline <= block.timestamp + MAX_VOTING_DURATION, "Exceeds max duration");

        proposals[proposalId].votingDeadline = newDeadline;
        emit VotingExtended(proposalId, newDeadline);
    }

    function finalizeProposal(uint256 proposalId)
        external onlyOwner proposalExists(proposalId) isPending(proposalId)
    {
        _finalizeSingleProposal(proposalId);
    }

    function batchFinalizeProposals(uint256[] calldata proposalIds) external onlyOwner {
        for (uint i = 0; i < proposalIds.length; i++) {
            uint256 proposalId = proposalIds[i];
            if (proposals[proposalId].status == ProposalStatus.Pending && 
                block.timestamp > proposals[proposalId].votingDeadline) {
                _finalizeSingleProposal(proposalId);
            }
        }
    }

    function _finalizeSingleProposal(uint256 proposalId) private {
        ProposalData storage p = proposals[proposalId];
        uint256 quorum = (p.totalVotes * 100) / memberCount;
        
        if (quorum >= requiredQuorumPercent) {
            p.status = (p.votesFor > p.totalVotes / 2)
                ? ProposalStatus.Accepted
                : ProposalStatus.Rejected;
            emit ProposalFinalized(proposalId, p.status);
        }
    }

    function archiveOldProposals(uint256 cutoffTimestamp) external onlyOwner {
        for (uint i = 0; i < allProposalIds.length; i++) {
            uint256 proposalId = allProposalIds[i];
            if (proposals[proposalId].createdAt < cutoffTimestamp && 
                proposals[proposalId].status == ProposalStatus.Pending) {
                proposals[proposalId].status = ProposalStatus.Cancelled;
                emit ProposalCancelled(proposalId);
            }
        }
    }

    // ------------------ Voting Functions ------------------
    function vote(uint256 proposalId, VoteType voteType)
        external onlyMember proposalExists(proposalId) isPending(proposalId) votingOpen(proposalId)
    {
        address voter = voteDelegates[msg.sender] != address(0) 
            ? voteDelegates[msg.sender] 
            : msg.sender;

        require(voteType == VoteType.For || voteType == VoteType.Against, "Invalid vote");
        require(!hasVoted[proposalId][voter], "Already voted");

        hasVoted[proposalId][voter] = true;
        voteRecord[proposalId][voter] = voteType;

        ProposalData storage p = proposals[proposalId];
        p.totalVotes++;
        if (voteType == VoteType.For) {
            p.votesFor++;
        }

        emit VoteCast(proposalId, voter, voteType);
    }

    function withdrawVote(uint256 proposalId)
        external onlyMember proposalExists(proposalId) isPending(proposalId) votingOpen(proposalId)
    {
        address voter = voteDelegates[msg.sender] != address(0) 
            ? voteDelegates[msg.sender] 
            : msg.sender;

        require(hasVoted[proposalId][voter], "You haven't voted");

        ProposalData storage p = proposals[proposalId];

        if (voteRecord[proposalId][voter] == VoteType.For) {
            p.votesFor--;
        }

        p.totalVotes--;
        hasVoted[proposalId][voter] = false;
        voteRecord[proposalId][voter] = VoteType.None;

        emit VoteWithdrawn(proposalId, voter);
    }

    // ------------------ Configuration ------------------
    function adjustQuorum(uint256 percent) external onlyOwner {
        require(percent > 0 && percent <= 100, "Invalid percent");
        requiredQuorumPercent = percent;
        emit QuorumAdjusted(percent);
    }

    function updateVotingPeriod(uint256 period) external onlyOwner {
        require(period >= MIN_VOTING_DURATION && period <= MAX_VOTING_DURATION, "Invalid voting period");
        votingPeriod = period;
        emit VotingPeriodUpdated(period);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid address");
        require(!groupMembers[newOwner], "Already a member");
        
        if (!groupMembers[newOwner]) {
            groupMembers[newOwner] = true;
            memberCount++;
        }
        
        groupMembers[owner] = false;
        memberCount--;
        
        owner = newOwner;
        emit OwnershipTransferred(owner, newOwner);
    }

    // ------------------ View Functions ------------------
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
            if (proposals[allProposalIds[i]].status == status) {
                count++;
            }
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

    function getProposalStats() external view returns (
        uint256 total,
        uint256 pending,
        uint256 accepted,
        uint256 rejected,
        uint256 cancelled
    ) {
        total = allProposalIds.length;
        for (uint i = 0; i < allProposalIds.length; i++) {
            ProposalStatus status = proposals[allProposalIds[i]].status;
            if (status == ProposalStatus.Pending) pending++;
            else if (status == ProposalStatus.Accepted) accepted++;
            else if (status == ProposalStatus.Rejected) rejected++;
            else if (status == ProposalStatus.Cancelled) cancelled++;
        }
    }

    function getVotingPower(address member) public view returns (uint256) {
        if (!groupMembers[member]) return 0;
        return 1; // Default: 1 vote per member
    }
}















