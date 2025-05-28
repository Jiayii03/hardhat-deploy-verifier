// scripts/upgradeCombinedVault.js
const { ethers, upgrades } = require("hardhat");

async function main() {
  // Get the proxy address from your deployment
  const COMBINED_VAULT_PROXY_ADDRESS = "0x6C50E082E08365450F2231f88e1625e8EeB23dFF";
  
  console.log("Upgrading Combined Vault...");

  // Get the contract factory for the V2 implementation
  const UpgradedCombinedVault = await ethers.getContractFactory("CombinedVault");
  
  // Upgrade the proxy to point to the new implementation
  await upgrades.upgradeProxy(COMBINED_VAULT_PROXY_ADDRESS, UpgradedCombinedVault);
  
  console.log("CombinedVault upgraded successfully");
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });