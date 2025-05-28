// scripts/upgradeVirtualVault.js
const { ethers, upgrades } = require("hardhat");

async function main() {
  // Get the proxy address from your deployment
  const VIRTUAL_VAULT_PROXY_ADDRESS = "0x6a8897284DF2F50Fe797A3D6665995D50BDeE69A";
  
  console.log("Upgrading Virtual Vault...");

  // Get the contract factory for the V2 implementation
  const UpgradedVirtualVault = await ethers.getContractFactory("VirtualVault");
  
  // Upgrade the proxy to point to the new implementation
  await upgrades.upgradeProxy(VIRTUAL_VAULT_PROXY_ADDRESS, UpgradedVirtualVault);
  
  console.log("VirtualVault upgraded successfully");
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });