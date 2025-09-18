const contractAddress = "0x8963150721D8909CCB6e04c0d79a2B3dd351Ed54";
const contractABI = [
  // Group Management
  "function addGroupMember(address member) public",
  "function removeGroupMember(address member) public",
  "function isGroupMember(address) public view returns (bool)",

  // Proposal Lifecycle
  "function createProposal(string description) public",
  "function vote(uint proposalId, bool voteType) public",
  "function finalizeProposal(uint proposalId) public",

  // Proposal Retrieval
  "function getProposalDetails(uint proposalId) public view returns (string description, uint yesVotes, uint noVotes, bool finalized)"
];

let provider;
let signer;
let contract;

// Connect MetaMask
document.getElementById("connectWallet").onclick = async () => {
  if (window.ethereum) {
    provider = new ethers.providers.Web3Provider(window.ethereum);
    await provider.send("eth_requestAccounts", []);
    signer = provider.getSigner();
    contract = new ethers.Contract(contractAddress, contractABI, signer);

    const address = await signer.getAddress();
    document.getElementById("walletAddress").innerText = `✅ Connected: ${address}`;
  } else {
    alert("MetaMask not found. Please install it!");
  }
};

// Create Proposal
document.getElementById("createProposal").onclick = async () => {
  const desc = document.getElementById("proposalDesc").value;
  try {
    const tx = await contract.createProposal(desc);
    await tx.wait();
    alert("Proposal created successfully!");
  } catch (err) {
    alert("Error creating proposal: " + err.message);
  }
};

// Vote Yes
document.getElementById("voteYes").onclick = async () => {
  const id = document.getElementById("proposalIdVote").value;
  try {
    const tx = await contract.vote(id, true);
    await tx.wait();
    alert("Voted YES!");
  } catch (err) {
    alert("Error voting: " + err.message);
  }
};

// Vote No
document.getElementById("voteNo").onclick = async () => {
  const id = document.getElementById("proposalIdVote").value;
  try {
    const tx = await contract.vote(id, false);
    await tx.wait();
    alert("Voted NO!");
  } catch (err) {
    alert("Error voting: " + err.message);
  }
};

// Finalize Proposal
document.getElementById("finalizeProposal").onclick = async () => {
  const id = document.getElementById("proposalIdFinalize").value;
  try {
    const tx = await contract.finalizeProposal(id);
    await tx.wait();
    alert("Proposal finalized!");
  } catch (err) {
    alert("Error finalizing: " + err.message);
  }
};

// Get Proposal Details
document.getElementById("getDetails").onclick = async () => {
  const id = document.getElementById("proposalIdDetails").value;
  try {
    const details = await contract.getProposalDetails(id);
    document.getElementById("proposalDetails").innerText = `
Description: ${details.description}
Yes Votes: ${details.yesVotes}
No Votes: ${details.noVotes}
Finalized: ${details.finalized}
    `;
  } catch (err) {
    alert("Error fetching details: " + err.message);
  }
};
