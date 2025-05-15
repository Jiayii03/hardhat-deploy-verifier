// scripts/upgradeCombinedVault.js
const { ethers, upgrades } = require("hardhat");

async function main() {
  // Get the proxy address from your deployment
  const COMPOUND_ADAPTER_PROXY_ADDRESS = "0xF7dF5097948545CA6B6a11BF9Ab7ea03e4c38817";
  
  console.log("Upgrading Compound Adapter...");

  // Get the contract factory for the V2 implementation
  const UpgradedCompoundAdapter = await ethers.getContractFactory("CompoundAdapter");
  
  // Upgrade the proxy to point to the new implementation
  await upgrades.upgradeProxy(COMPOUND_ADAPTER_PROXY_ADDRESS, UpgradedCompoundAdapter);
  
  console.log("CompoundAdapter upgraded successfully");
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });