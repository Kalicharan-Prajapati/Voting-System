const hre = require("hardhat");

async function main() {
  console.log("Starting deployment to Core Testnet 2...");
  
  // Get the contract factory
  const Project = await hre.ethers.getContractFactory("Project");
  
  // Deploy the contract with election name
  const electionName = "General Election 2024";
  console.log(`Deploying Project contract with election name: "${electionName}"`);
  
  const project = await Project.deploy(electionName);
  
  // Wait for deployment to be mined
  await project.waitForDeployment();
  
  const contractAddress = await project.getAddress();
  console.log(`Project contract deployed to: ${contractAddress}`);
  
  // Display deployment information
  console.log("\n=== Deployment Summary ===");
  console.log(`Network: ${hre.network.name}`);
  console.log(`Contract Address: ${contractAddress}`);
  console.log(`Election Name: ${electionName}`);
  console.log(`Deployer: ${(await hre.ethers.getSigners())[0].address}`);
  
  // Verify the contract on the explorer (optional)
  if (hre.network.name !== "hardhat" && hre.network.name !== "localhost") {
    console.log("\nWaiting for block confirmations...");
    await project.deploymentTransaction().wait(6);
    
    try {
      console.log("Verifying contract on block explorer...");
      await hre.run("verify:verify", {
        address: contractAddress,
        constructorArguments: [electionName],
      });
      console.log("Contract verified successfully!");
    } catch (error) {
      console.log("Contract verification failed:", error.message);
    }
  }
  
  // Save deployment info to file
  const fs = require("fs");
  const deploymentInfo = {
    network: hre.network.name,
    contractAddress: contractAddress,
    electionName: electionName,
    deploymentTime: new Date().toISOString(),
    deployer: (await hre.ethers.getSigners())[0].address
  };
  
  fs.writeFileSync(
    "deployment-info.json",
    JSON.stringify(deploymentInfo, null, 2)
  );
  
  console.log("\nDeployment info saved to deployment-info.json");
}

// Handle errors
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Deployment failed:", error);
    process.exit(1);
  });
