// scripts/verify.js
const hre = require("hardhat");
const ethers = require("ethers");

async function main() {
  // Replace these with your actual deployed contract addresses
  const USDC_ADDRESS = "0x036CbD53842c5426634e7929541eC2318f3dCF7e";
  const PROTOCOL_REGISTRY_ADDRESS = "0xb06599032788F0C6A45C1aeCf834FCDa2EDfA103";
  const AAVE_ADAPTER_ADDRESS = "0x6Bc24C25617a2C6D2b8059A824CAF67CCf6179b2";
  const COMPOUND_ADAPTER_ADDRESS = "0x1E2073E134c5F5EEe09cC946A341Fff8dc87544a";
  const LAYERBANK_ADAPTER_ADDRESS = "0xe11E2CfC47efA3aB21fC87E9b31f406dF13D5F82";
  const VIRTUAL_VAULT_ADDRESS = "0xb659c44794d96d558776AacdE7Ab32a7635B980F";
  const COMBINED_VAULT_ADDRESS = "0xbbC8f4d5050A9969A73f22328Bd82C88b7d439f1";

  // Protocol pool addresses
  const AAVE_POOL_ADDRESS = "0x11fCfe756c05AD438e312a7fd934381537D3cFfe";
  const COMPOUND_POOL_ADDRESS = "0xb125E6687d4313864e53df431d5425969c15Eb2F";
  const LAYERBANK_CORE_ADDRESS = "0xEC53c830f4444a8A56455c6836b5D2aA794289Aa";

  console.log("Starting contract verification...");

  try {
    console.log("Verifying ProtocolRegistry...");
    await hre.run("verify:verify", {
      address: PROTOCOL_REGISTRY_ADDRESS,
      constructorArguments: [],
      contract: "contracts/core/ProtocolRegistry.sol:ProtocolRegistry",
    });
    console.log("ProtocolRegistry verified successfully!");
  } catch (error) {
    console.log("Error verifying ProtocolRegistry:", error.message);
  }

  try {
    console.log("Verifying AaveAdapter...");
    await hre.run("verify:verify", {
      address: AAVE_ADAPTER_ADDRESS,
      constructorArguments: [AAVE_POOL_ADDRESS],
      contract: "contracts/adapters/AaveAdapter.sol:AaveAdapter",
    });
    console.log("AaveAdapter verified successfully!");
  } catch (error) {
    console.log("Error verifying AaveAdapter:", error.message);
  }

  try {
    console.log("Verifying CompoundAdapter...");
    await hre.run("verify:verify", {
      address: COMPOUND_ADAPTER_ADDRESS,
      constructorArguments: [COMPOUND_POOL_ADDRESS],
      contract: "contracts/adapters/CompoundAdapter.sol:CompoundAdapter",
    });
    console.log("CompoundAdapter verified successfully!");
  } catch (error) {
    console.log("Error verifying CompoundAdapter:", error.message);
  }

  try {
    console.log("Verifying LayerBankAdapter...");
    await hre.run("verify:verify", {
      address: LAYERBANK_ADAPTER_ADDRESS,
      constructorArguments: [LAYERBANK_CORE_ADDRESS],
      contract: "contracts/adapters/LayerBankAdapter.sol:LayerBankAdapter",
    });
    console.log("LayerBankAdapter verified successfully!");
  } catch (error) {
    console.log("Error verifying LayerBankAdapter:", error.message);
  }

  try {
    console.log("Verifying VirtualVault...");
    await hre.run("verify:verify", {
      address: VIRTUAL_VAULT_ADDRESS,
      constructorArguments: [USDC_ADDRESS, ethers.constants.AddressZero],
      contract: "contracts/core/VirtualVault.sol:VirtualVault",
    });
    console.log("VirtualVault verified successfully!");
  } catch (error) {
    console.log("Error verifying VirtualVault:", error.message);
  }

  try {
    console.log("Verifying CombinedVault...");
    await hre.run("verify:verify", {
      address: COMBINED_VAULT_ADDRESS,
      constructorArguments: [USDC_ADDRESS, PROTOCOL_REGISTRY_ADDRESS],
      contract: "contracts/core/CombinedVault.sol:CombinedVault",
    });
    console.log("CombinedVault verified successfully!");
  } catch (error) {
    console.log("Error verifying CombinedVault:", error.message);
  }

  console.log("Verification process completed!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
