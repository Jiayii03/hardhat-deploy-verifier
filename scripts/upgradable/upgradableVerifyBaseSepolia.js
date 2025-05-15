// scripts/verify-upgradeable.js
const hre = require("hardhat");
const { ethers, upgrades } = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  // Replace these with your actual deployed proxy addresses
  const REGISTRY_PROXY = "0x158Fc38C128D70bef153A10256FA878C0b294792";
  const AAVE_ADAPTER_PROXY = "0x691303a12A4fBfFEBdFB282336181E9A45730bfd";
  const COMPOUND_ADAPTER_PROXY = "0x938648Be642fD7a9591257b8BFcEE06C6224e280";

  // Create directory for flattened contracts
  const flatDir = path.join(__dirname, "../flattened-contracts");
  if (!fs.existsSync(flatDir)) {
    fs.mkdirSync(flatDir);
  }

  // Get implementation addresses
  console.log("Getting implementation addresses...");
  const registryImpl = await upgrades.erc1967.getImplementationAddress(REGISTRY_PROXY);
  const aaveAdapterImpl = await upgrades.erc1967.getImplementationAddress(AAVE_ADAPTER_PROXY);
  const compoundAdapterImpl = await upgrades.erc1967.getImplementationAddress(COMPOUND_ADAPTER_PROXY);
  
  console.log("Implementation Addresses:");
  console.log("ProtocolRegistry:", registryImpl);
  console.log("AaveAdapter:", aaveAdapterImpl);
  console.log("CompoundAdapter:", compoundAdapterImpl);

  // Function to flatten a contract
  async function flattenContract(contractPath, outputFileName) {
    console.log(`Flattening ${contractPath}...`);
    try {
      const flattenedCode = await hre.run("flatten:get-flattened-sources", {
        files: [contractPath]
      });
      
      // Clean up license identifiers and pragmas
      let cleanedCode = "";
      let licenseSeen = false;
      let pragmaSeen = false;
      
      for (const line of flattenedCode.split("\n")) {
        if (line.trim().startsWith("// SPDX-License-Identifier:")) {
          if (!licenseSeen) {
            cleanedCode += line + "\n";
            licenseSeen = true;
          }
        } else if (line.trim().startsWith("pragma solidity")) {
          if (!pragmaSeen) {
            cleanedCode += line + "\n";
            pragmaSeen = true;
          }
        } else {
          cleanedCode += line + "\n";
        }
      }
      
      const outputPath = path.join(flatDir, outputFileName);
      fs.writeFileSync(outputPath, cleanedCode);
      console.log(`Saved flattened contract to: ${outputPath}`);
      return true;
    } catch (error) {
      console.error(`Error flattening ${contractPath}:`, error.message);
      return false;
    }
  }

  // Flatten contracts for verification
  await flattenContract("contracts/core/ProtocolRegistry.sol", "ProtocolRegistry_flat.sol");
  await flattenContract("contracts/adapters/AaveAdapter.sol", "AaveAdapter_flat.sol");
  await flattenContract("contracts/adapters/CompoundAdapter.sol", "CompoundAdapter_flat.sol");

  // Verify implementations using flattened contracts
  console.log("\n=== Verifying Implementation Contracts ===");

  // Important: Temporarily disable viaIR for verification
  // Make sure you have this in your hardhat.config.js before running this script:
  // solidity: {
  //   version: "0.8.20",
  //   settings: {
  //     optimizer: {
  //       enabled: true,
  //       runs: 200
  //     },
  //     // Comment out viaIR for verification
  //     // viaIR: true
  //   }
  // }

  try {
    console.log("\nVerifying ProtocolRegistry implementation...");
    await hre.run("verify:verify", {
      address: registryImpl,
      constructorArguments: [],
      contract: "ProtocolRegistry_flat.sol:ProtocolRegistry"
    });
    console.log("✅ ProtocolRegistry implementation verified successfully!");
  } catch (error) {
    if (error.message.includes("Already Verified")) {
      console.log("✅ ProtocolRegistry already verified!");
    } else {
      console.log("Error verifying ProtocolRegistry:", error.message);
      // Try direct CLI command
      console.log(`Try running: npx hardhat verify --network base ${registryImpl} --contract "ProtocolRegistry_flat.sol:ProtocolRegistry"`);
    }
  }

  try {
    console.log("\nVerifying AaveAdapter implementation...");
    await hre.run("verify:verify", {
      address: aaveAdapterImpl,
      constructorArguments: [],
      contract: "AaveAdapter_flat.sol:AaveAdapter"
    });
    console.log("✅ AaveAdapter implementation verified successfully!");
  } catch (error) {
    if (error.message.includes("Already Verified")) {
      console.log("✅ AaveAdapter already verified!");
    } else {
      console.log("Error verifying AaveAdapter:", error.message);
      console.log(`Try running: npx hardhat verify --network base ${aaveAdapterImpl} --contract "AaveAdapter_flat.sol:AaveAdapter"`);
    }
  }

  try {
    console.log("\nVerifying CompoundAdapter implementation...");
    await hre.run("verify:verify", {
      address: compoundAdapterImpl,
      constructorArguments: [],
      contract: "CompoundAdapter_flat.sol:CompoundAdapter"
    });
    console.log("✅ CompoundAdapter implementation verified successfully!");
  } catch (error) {
    if (error.message.includes("Already Verified")) {
      console.log("✅ CompoundAdapter already verified!");
    } else {
      console.log("Error verifying CompoundAdapter:", error.message);
      console.log(`Try running: npx hardhat verify --network base ${compoundAdapterImpl} --contract "CompoundAdapter_flat.sol:CompoundAdapter"`);
    }
  }

  console.log("\n=== Verification Process Complete ===");
  console.log("If verification was successful, the implementation contracts should show as verified on Basescan.");
  console.log("If any verifications failed, try the CLI commands listed above for each contract.");
  console.log("\nIMPORTANT: If all verification attempts fail, you may need to manually verify through the Basescan UI using the flattened contract files.");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Fatal error:", error);
    process.exit(1);
  });