// scripts/deploy.js
const hre = require("hardhat");
const { ethers } = require("hardhat");

// Helper to log gas used from either successful or failed transactions
async function logGasUsed(receipt, description, failed = false) {
  const status = failed ? "(FAILED)" : "";
  console.log(`Gas used for ${description}: ${receipt.gasUsed.toString()} units ${status}`);
  return receipt.gasUsed;
}

// Execute transaction with error handling that continues deployment
async function safeExecute(description, txPromise, gasLimit = 500000) {
  try {
    console.log(`Executing: ${description}...`);
    const tx = await txPromise({ gasLimit });
    const receipt = await tx.wait();
    return { success: true, receipt };
  } catch (error) {
    console.error(`Error during ${description}:`, error.message);
    
    // Still extract gas used from failed transaction if available
    if (error.receipt) {
      console.log(`Transaction failed but still used gas. Will continue deployment.`);
      return { success: false, receipt: error.receipt };
    } else {
      console.log(`Could not determine gas usage. Using estimate of 100000 units.`);
      // Create a mock receipt with estimated gas
      return { 
        success: false, 
        receipt: { gasUsed: ethers.BigNumber.from(100000) }
      };
    }
  }
}

async function main() {
  let totalGasUsed = ethers.BigNumber.from(0);
  
  // Store contract addresses for logging even if some steps fail
  const deployedAddresses = {
    registry: null,
    aaveAdapter: null,
    compoundAdapter: null,
    layerBankAdapter: null,
    virtualVault: null,
    combinedVault: null
  };
  
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with account:", deployer.address);
  console.log("Account balance:", (await ethers.provider.getBalance(deployer.address)).toString());

  // ==================== BASE SEPOLIA ====================
  const AAVE_POOL_ADDRESS = "0xA238Dd80C259a72e81d7e4664a9801593F98d1c5";
  const COMPOUND_POOL_ADDRESS = "0xb125E6687d4313864e53df431d5425969c15Eb2F";
  const LAYERBANK_CORE_ADDRESS = "";
  
  // Token addresses
  const USDC_ADDRESS = "0x036CbD53842c5426634e7929541eC2318f3dCF7e"; //testnet
  const USDC_ATOKEN_ADDRESS = "0x63706e401c06ac8513145b7687A14804d17f814b";
  const USDC_CTOKEN_ADDRESS = "0xb125E6687d4313864e53df431d5425969c15Eb2F";
  const USDC_GTOKEN_ADDRESS = "";

  // ==================== SCROLL SEPOLIA ====================
  // const AAVE_POOL_ADDRESS = "0x11fCfe756c05AD438e312a7fd934381537D3cFfe";
  // const COMPOUND_POOL_ADDRESS = "0xB2f97c1Bd3bf02f5e74d13f02E3e26F93D77CE44";
  // const LAYERBANK_CORE_ADDRESS = "0xEC53c830f4444a8A56455c6836b5D2aA794289Aa";
  
  // // Token addresses
  // const USDC_ADDRESS = "0x6af403A4cC878E766924B694ffaa4a0b9A10f6B3";  //testnet
  // const USDC_ATOKEN_ADDRESS = "0x1D738a3436A8C49CefFbaB7fbF04B660fb528CbD";
  // const USDC_CTOKEN_ADDRESS = "0xB2f97c1Bd3bf02f5e74d13f02E3e26F93D77CE44";
  // const USDC_GTOKEN_ADDRESS = "0x0D8F8e271DD3f2fC58e5716d3Ff7041dBe3F0688";

  // Protocol IDs from Constants
  const AAVE_PROTOCOL_ID = 1;
  const COMPOUND_PROTOCOL_ID = 2;
  const LAYERBANK_PROTOCOL_ID = 3;

  try {
    // Step 1: Deploy ProtocolRegistry
    console.log("\nDeploying ProtocolRegistry...");
    const ProtocolRegistry = await ethers.getContractFactory("ProtocolRegistry");
    const registry = await ProtocolRegistry.deploy();
    const registryReceipt = await registry.deployTransaction.wait();
    totalGasUsed = totalGasUsed.add(await logGasUsed(registryReceipt, "ProtocolRegistry deployment"));
    console.log("ProtocolRegistry deployed at:", registry.address);
    deployedAddresses.registry = registry.address;

    // Step 2: Deploy all three adapters
    console.log("\nDeploying AaveAdapter...");
    const AaveAdapter = await ethers.getContractFactory("AaveAdapter");
    const aaveAdapter = await AaveAdapter.deploy(AAVE_POOL_ADDRESS);
    const aaveReceipt = await aaveAdapter.deployTransaction.wait();
    totalGasUsed = totalGasUsed.add(await logGasUsed(aaveReceipt, "AaveAdapter deployment"));
    console.log("AaveAdapter deployed at:", aaveAdapter.address);
    deployedAddresses.aaveAdapter = aaveAdapter.address;

    console.log("\nDeploying CompoundAdapter...");
    const CompoundAdapter = await ethers.getContractFactory("CompoundAdapter");
    const compoundAdapter = await CompoundAdapter.deploy(COMPOUND_POOL_ADDRESS);
    const compoundReceipt = await compoundAdapter.deployTransaction.wait();
    totalGasUsed = totalGasUsed.add(await logGasUsed(compoundReceipt, "CompoundAdapter deployment"));
    console.log("CompoundAdapter deployed at:", compoundAdapter.address);
    deployedAddresses.compoundAdapter = compoundAdapter.address;

    console.log("\nDeploying LayerBankAdapter...");
    const LayerBankAdapter = await ethers.getContractFactory("LayerBankAdapter");
    const layerBankAdapter = await LayerBankAdapter.deploy(LAYERBANK_CORE_ADDRESS);
    const layerBankReceipt = await layerBankAdapter.deployTransaction.wait();
    totalGasUsed = totalGasUsed.add(await logGasUsed(layerBankReceipt, "LayerBankAdapter deployment"));
    console.log("LayerBankAdapter deployed at:", layerBankAdapter.address);
    deployedAddresses.layerBankAdapter = layerBankAdapter.address;

    // Step 3: Register protocols in registry
    console.log("\nRegistering protocols...");
    
    // Register Aave protocol
    let result = await safeExecute(
      "Register Aave protocol",
      (overrides) => registry.registerProtocol(AAVE_PROTOCOL_ID, "Aave V3", overrides)
    );
    totalGasUsed = totalGasUsed.add(await logGasUsed(result.receipt, "Register Aave protocol", !result.success));

    // Register Compound protocol
    result = await safeExecute(
      "Register Compound protocol",
      (overrides) => registry.registerProtocol(COMPOUND_PROTOCOL_ID, "Compound V3", overrides)
    );
    totalGasUsed = totalGasUsed.add(await logGasUsed(result.receipt, "Register Compound protocol", !result.success));
    
    // Register LayerBank protocol
    result = await safeExecute(
      "Register LayerBank protocol",
      (overrides) => registry.registerProtocol(LAYERBANK_PROTOCOL_ID, "LayerBank", overrides)
    );
    totalGasUsed = totalGasUsed.add(await logGasUsed(result.receipt, "Register LayerBank protocol", !result.success));

    // Step 4: Configure adapters with supported assets
    console.log("\nConfiguring adapters...");
    
    // Configure Aave adapter
    result = await safeExecute(
      "Configure Aave adapter",
      (overrides) => aaveAdapter.addSupportedAsset(USDC_ADDRESS, USDC_ATOKEN_ADDRESS, overrides)
    );
    totalGasUsed = totalGasUsed.add(await logGasUsed(result.receipt, "Configure Aave adapter", !result.success));
    
    // Configure Compound adapter
    result = await safeExecute(
      "Configure Compound adapter",
      (overrides) => compoundAdapter.addSupportedAsset(USDC_ADDRESS, USDC_CTOKEN_ADDRESS, overrides)
    );
    totalGasUsed = totalGasUsed.add(await logGasUsed(result.receipt, "Configure Compound adapter", !result.success));
    
    // Configure LayerBank adapter
    result = await safeExecute(
      "Configure LayerBank adapter",
      (overrides) => layerBankAdapter.addSupportedAsset(USDC_ADDRESS, USDC_GTOKEN_ADDRESS, overrides)
    );
    totalGasUsed = totalGasUsed.add(await logGasUsed(result.receipt, "Configure LayerBank adapter", !result.success));

    // Step 5: Register adapters in registry
    console.log("\nRegistering adapters...");
    
    // Register Aave adapter
    result = await safeExecute(
      "Register Aave adapter",
      (overrides) => registry.registerAdapter(AAVE_PROTOCOL_ID, USDC_ADDRESS, aaveAdapter.address, overrides)
    );
    totalGasUsed = totalGasUsed.add(await logGasUsed(result.receipt, "Register Aave adapter", !result.success));
    
    // Register Compound adapter
    result = await safeExecute(
      "Register Compound adapter",
      (overrides) => registry.registerAdapter(COMPOUND_PROTOCOL_ID, USDC_ADDRESS, compoundAdapter.address, overrides)
    );
    totalGasUsed = totalGasUsed.add(await logGasUsed(result.receipt, "Register Compound adapter", !result.success));
    
    // Register LayerBank adapter
    result = await safeExecute(
      "Register LayerBank adapter",
      (overrides) => registry.registerAdapter(LAYERBANK_PROTOCOL_ID, USDC_ADDRESS, layerBankAdapter.address, overrides)
    );
    totalGasUsed = totalGasUsed.add(await logGasUsed(result.receipt, "Register LayerBank adapter", !result.success));

    // Step 6: Deploy VirtualVault with dummy CombinedVault first
    console.log("\nDeploying VirtualVault...");
    const VirtualVault = await ethers.getContractFactory("VirtualVault");
    const virtualVault = await VirtualVault.deploy(USDC_ADDRESS, ethers.constants.AddressZero);
    const virtualVaultReceipt = await virtualVault.deployTransaction.wait();
    totalGasUsed = totalGasUsed.add(await logGasUsed(virtualVaultReceipt, "VirtualVault deployment"));
    console.log("VirtualVault deployed at:", virtualVault.address);
    deployedAddresses.virtualVault = virtualVault.address;

    // Step 7: Deploy CombinedVault
    console.log("\nDeploying CombinedVault...");
    const CombinedVault = await ethers.getContractFactory("CombinedVault");
    const combinedVault = await CombinedVault.deploy(USDC_ADDRESS, registry.address);
    const combinedVaultReceipt = await combinedVault.deployTransaction.wait();
    totalGasUsed = totalGasUsed.add(await logGasUsed(combinedVaultReceipt, "CombinedVault deployment"));
    console.log("CombinedVault deployed at:", combinedVault.address);
    deployedAddresses.combinedVault = combinedVault.address;

    // Step 8: Configure Registry and Vaults
    console.log("\nConfiguring Registry and Vaults...");
    
    // Set authorized caller
    result = await safeExecute(
      "Set authorized caller",
      (overrides) => registry.setAuthorizedCaller(combinedVault.address, overrides)
    );
    totalGasUsed = totalGasUsed.add(await logGasUsed(result.receipt, "Set authorized caller", !result.success));
    
    // Add Aave as active protocol
    result = await safeExecute(
      "Add Aave as active protocol",
      (overrides) => combinedVault.addActiveProtocol(AAVE_PROTOCOL_ID, overrides)
    );
    totalGasUsed = totalGasUsed.add(await logGasUsed(result.receipt, "Add Aave as active protocol", !result.success));
    
    // Add Compound as active protocol
    result = await safeExecute(
      "Add Compound as active protocol",
      (overrides) => combinedVault.addActiveProtocol(COMPOUND_PROTOCOL_ID, overrides)
    );
    totalGasUsed = totalGasUsed.add(await logGasUsed(result.receipt, "Add Compound as active protocol", !result.success));
    
    // Add LayerBank as active protocol
    result = await safeExecute(
      "Add LayerBank as active protocol",
      (overrides) => combinedVault.addActiveProtocol(LAYERBANK_PROTOCOL_ID, overrides)
    );
    totalGasUsed = totalGasUsed.add(await logGasUsed(result.receipt, "Add LayerBank as active protocol", !result.success));

    // Step 9: Link both vaults
    console.log("\nLinking vaults...");
    
    // Set CombinedVault in VirtualVault
    result = await safeExecute(
      "Set CombinedVault in VirtualVault",
      (overrides) => virtualVault.setCombinedVault(combinedVault.address, overrides)
    );
    totalGasUsed = totalGasUsed.add(await logGasUsed(result.receipt, "Set CombinedVault in VirtualVault", !result.success));
    
    // Set authorized caller in VirtualVault
    result = await safeExecute(
      "Set authorized caller in VirtualVault",
      (overrides) => virtualVault.setAuthorizedCaller(combinedVault.address, overrides)
    );
    totalGasUsed = totalGasUsed.add(await logGasUsed(result.receipt, "Set authorized caller in VirtualVault", !result.success));
    
    // Set VirtualVault in CombinedVault
    result = await safeExecute(
      "Set VirtualVault in CombinedVault",
      (overrides) => combinedVault.setVirtualVault(virtualVault.address, overrides)
    );
    totalGasUsed = totalGasUsed.add(await logGasUsed(result.receipt, "Set VirtualVault in CombinedVault", !result.success));

  } catch (error) {
    console.error("Deployment process encountered an error:", error);
    console.log("Continuing to gas estimation with data collected so far...");
  }

  // Log deployment addresses and total gas used
  console.log("\n=== Deployment Summary ===");
  console.log("USDC Address:", USDC_ADDRESS);
  console.log("ProtocolRegistry Address:", deployedAddresses.registry || "Failed to deploy");
  console.log("AaveAdapter Address:", deployedAddresses.aaveAdapter || "Failed to deploy");
  console.log("CompoundAdapter Address:", deployedAddresses.compoundAdapter || "Failed to deploy");
  console.log("LayerBankAdapter Address:", deployedAddresses.layerBankAdapter || "Failed to deploy");
  console.log("VirtualVault Address:", deployedAddresses.virtualVault || "Failed to deploy");
  console.log("CombinedVault Address:", deployedAddresses.combinedVault || "Failed to deploy");
  console.log("Total gas used:", totalGasUsed.toString(), "units");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Fatal error:", error);
    process.exit(1);
  });