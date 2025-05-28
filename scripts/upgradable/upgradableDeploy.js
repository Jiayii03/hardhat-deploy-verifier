// scripts/deploy.js
const hre = require("hardhat");
const { ethers, upgrades } = require("hardhat");

async function main() {
  // Store addresses for deployment summary
  const deployedAddresses = {
    registry: null,
    aaveAdapter: null,
    compoundAdapter: null,
    virtualVault: null,
    combinedVault: null
  };

  // Gas tracking variables
  let totalGasUsed = ethers.BigNumber.from(0);
  const gasUsageBreakdown = [];

  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with account:", deployer.address);
  console.log("Account balance:", (await ethers.provider.getBalance(deployer.address)).toString());

  // Helper function to track gas usage
  async function trackGasUsage(txPromise, description) {
    const tx = await txPromise;
    const receipt = await tx.wait();
    const gasUsed = receipt.gasUsed;
    totalGasUsed = totalGasUsed.add(gasUsed);
    gasUsageBreakdown.push({
      operation: description,
      gasUsed: gasUsed.toString(),
      txHash: receipt.transactionHash
    });
    console.log(`  ⛽ Gas used for ${description}: ${gasUsed.toString()}`);
    return tx;
  }

  // ==================== SCROLL MAINNET ====================
  const AAVE_POOL_ADDRESS = "0x11fCfe756c05AD438e312a7fd934381537D3cFfe";
  const COMPOUND_POOL_ADDRESS = "0xB2f97c1Bd3bf02f5e74d13f02E3e26F93D77CE44";
  
  // Token addresses
  const USDC_ADDRESS = "0x06eFdBFf2a14a7c8E15944D1F4A48F9F95F663A4";
  const USDC_ATOKEN_ADDRESS = "0x1D738a3436A8C49CefFbaB7fbF04B660fb528CbD";
  const USDC_CTOKEN_ADDRESS = "0xB2f97c1Bd3bf02f5e74d13f02E3e26F93D77CE44";

  // Protocol IDs from Constants
  const AAVE_PROTOCOL_ID = 1;
  const COMPOUND_PROTOCOL_ID = 2;

  try {
    // Step 1: Deploy ProtocolRegistry with proxy using the upgrades plugin
    console.log("\nDeploying ProtocolRegistry...");
    const ProtocolRegistry = await ethers.getContractFactory("ProtocolRegistry");
    const registry = await upgrades.deployProxy(ProtocolRegistry, [], {
      kind: "transparent",
      initializer: "initialize"
    });
    const registryDeployTx = await registry.deployTransaction.wait();
    totalGasUsed = totalGasUsed.add(registryDeployTx.gasUsed);
    gasUsageBreakdown.push({
      operation: "Deploy ProtocolRegistry Proxy",
      gasUsed: registryDeployTx.gasUsed.toString(),
      txHash: registryDeployTx.transactionHash
    });
    console.log(`  ⛽ Gas used for Deploy ProtocolRegistry Proxy: ${registryDeployTx.gasUsed.toString()}`);
    console.log("ProtocolRegistry proxy deployed at:", registry.address);
    deployedAddresses.registry = registry.address;

    // Step 2: Deploy AaveAdapter with proxy
    console.log("\nDeploying AaveAdapter...");
    const AaveAdapter = await ethers.getContractFactory("AaveAdapter");
    const aaveAdapter = await upgrades.deployProxy(
      AaveAdapter,
      [AAVE_POOL_ADDRESS],
      { kind: "transparent", initializer: "initialize" }
    );
    const aaveAdapterDeployTx = await aaveAdapter.deployTransaction.wait();
    totalGasUsed = totalGasUsed.add(aaveAdapterDeployTx.gasUsed);
    gasUsageBreakdown.push({
      operation: "Deploy AaveAdapter Proxy",
      gasUsed: aaveAdapterDeployTx.gasUsed.toString(),
      txHash: aaveAdapterDeployTx.transactionHash
    });
    console.log(`  ⛽ Gas used for Deploy AaveAdapter Proxy: ${aaveAdapterDeployTx.gasUsed.toString()}`);
    console.log("AaveAdapter proxy deployed at:", aaveAdapter.address);
    deployedAddresses.aaveAdapter = aaveAdapter.address;

    // Step 3: Deploy CompoundAdapter with proxy
    console.log("\nDeploying CompoundAdapter...");
    const CompoundAdapter = await ethers.getContractFactory("CompoundAdapter");
    const compoundAdapter = await upgrades.deployProxy(
      CompoundAdapter,
      [COMPOUND_POOL_ADDRESS],
      { kind: "transparent", initializer: "initialize" }
    );
    const compoundAdapterDeployTx = await compoundAdapter.deployTransaction.wait();
    totalGasUsed = totalGasUsed.add(compoundAdapterDeployTx.gasUsed);
    gasUsageBreakdown.push({
      operation: "Deploy CompoundAdapter Proxy",
      gasUsed: compoundAdapterDeployTx.gasUsed.toString(),
      txHash: compoundAdapterDeployTx.transactionHash
    });
    console.log(`  ⛽ Gas used for Deploy CompoundAdapter Proxy: ${compoundAdapterDeployTx.gasUsed.toString()}`);
    console.log("CompoundAdapter proxy deployed at:", compoundAdapter.address);
    deployedAddresses.compoundAdapter = compoundAdapter.address;

    // Step 4: Register protocols in registry
    console.log("\nRegistering protocols...");
    
    // Register Aave protocol
    console.log("Registering Aave protocol...");
    await trackGasUsage(
      registry.registerProtocol(AAVE_PROTOCOL_ID, "Aave V3", { gasLimit: 500000 }),
      "Register Aave Protocol"
    );
    
    // Register Compound protocol
    console.log("Registering Compound protocol...");
    await trackGasUsage(
      registry.registerProtocol(COMPOUND_PROTOCOL_ID, "Compound V3", { gasLimit: 500000 }),
      "Register Compound Protocol"
    );

    // Step 5: Configure adapters with supported assets
    console.log("\nConfiguring adapters...");
    
    // Configure Aave adapter
    console.log("Configuring Aave adapter...");
    await trackGasUsage(
      aaveAdapter.addSupportedAsset(USDC_ADDRESS, USDC_ATOKEN_ADDRESS, { gasLimit: 500000 }),
      "Configure Aave Adapter"
    );
    
    // Configure Compound adapter
    console.log("Configuring Compound adapter...");
    await trackGasUsage(
      compoundAdapter.addSupportedAsset(USDC_ADDRESS, USDC_CTOKEN_ADDRESS, { gasLimit: 500000 }),
      "Configure Compound Adapter"
    );

    // Step 6: Register adapters in registry
    console.log("\nRegistering adapters...");
    
    // Register Aave adapter
    console.log("Registering Aave adapter...");
    await trackGasUsage(
      registry.registerAdapter(AAVE_PROTOCOL_ID, USDC_ADDRESS, aaveAdapter.address, { gasLimit: 500000 }),
      "Register Aave Adapter"
    );
    
    // Register Compound adapter
    console.log("Registering Compound adapter...");
    await trackGasUsage(
      registry.registerAdapter(COMPOUND_PROTOCOL_ID, USDC_ADDRESS, compoundAdapter.address, { gasLimit: 500000 }),
      "Register Compound Adapter"
    );

    // Step 7: Deploy CombinedVault with proxy
    console.log("\nDeploying CombinedVault...");
    const CombinedVault = await ethers.getContractFactory("CombinedVault");
    const combinedVault = await upgrades.deployProxy(
      CombinedVault,
      [
        USDC_ADDRESS,
        registry.address,
        deployer.address, // treasury address
        1000 // 10% performance fee (1000 basis points)
      ],
      { 
        kind: "transparent", 
        initializer: "initialize",
        unsafeAllow: ["constructor"] // Allow constructor for payable functionality
      }
    );
    const combinedVaultDeployTx = await combinedVault.deployTransaction.wait();
    totalGasUsed = totalGasUsed.add(combinedVaultDeployTx.gasUsed);
    gasUsageBreakdown.push({
      operation: "Deploy CombinedVault Proxy",
      gasUsed: combinedVaultDeployTx.gasUsed.toString(),
      txHash: combinedVaultDeployTx.transactionHash
    });
    console.log(`  ⛽ Gas used for Deploy CombinedVault Proxy: ${combinedVaultDeployTx.gasUsed.toString()}`);
    console.log("CombinedVault proxy deployed at:", combinedVault.address);
    deployedAddresses.combinedVault = combinedVault.address;

    // Step 8: Deploy VirtualVault with proxy
    console.log("\nDeploying VirtualVault...");
    const VirtualVault = await ethers.getContractFactory("VirtualVault");
    const virtualVault = await upgrades.deployProxy(
      VirtualVault,
      [USDC_ADDRESS, combinedVault.address],
      { 
        kind: "transparent", 
        initializer: "initialize",
        unsafeAllow: ["constructor"] // Allow constructor for payable functionality
      }
    );
    const virtualVaultDeployTx = await virtualVault.deployTransaction.wait();
    totalGasUsed = totalGasUsed.add(virtualVaultDeployTx.gasUsed);
    gasUsageBreakdown.push({
      operation: "Deploy VirtualVault Proxy",
      gasUsed: virtualVaultDeployTx.gasUsed.toString(),
      txHash: virtualVaultDeployTx.transactionHash
    });
    console.log(`  ⛽ Gas used for Deploy VirtualVault Proxy: ${virtualVaultDeployTx.gasUsed.toString()}`);
    console.log("VirtualVault proxy deployed at:", virtualVault.address);
    deployedAddresses.virtualVault = virtualVault.address;

    // Step 9: Configure Registry and Vaults
    console.log("\nConfiguring Registry and Vaults...");
    
    // Set authorized caller in registry
    console.log("Setting authorized caller in registry...");
    await trackGasUsage(
      registry.setAuthorizedCaller(combinedVault.address, { gasLimit: 500000 }),
      "Set Authorized Caller in Registry"
    );
    
    // Set authorized caller in adapters
    console.log("Setting authorized caller in Aave adapter...");
    await trackGasUsage(
      aaveAdapter.setAuthorizedCaller(combinedVault.address, { gasLimit: 500000 }),
      "Set Authorized Caller in Aave Adapter"
    );
    
    console.log("Setting authorized caller in Compound adapter...");
    await trackGasUsage(
      compoundAdapter.setAuthorizedCaller(combinedVault.address, { gasLimit: 500000 }),
      "Set Authorized Caller in Compound Adapter"
    );
    
    // Add Aave as active protocol
    console.log("Adding Aave as active protocol...");
    await trackGasUsage(
      combinedVault.addActiveProtocol(AAVE_PROTOCOL_ID, { gasLimit: 500000 }),
      "Add Aave as Active Protocol"
    );
    
    // Add Compound as active protocol
    console.log("Adding Compound as active protocol...");
    await trackGasUsage(
      combinedVault.addActiveProtocol(COMPOUND_PROTOCOL_ID, { gasLimit: 500000 }),
      "Add Compound as Active Protocol"
    );

    // Step 10: Link both vaults
    console.log("\nLinking vaults...");
    
    // Set authorized caller in VirtualVault
    console.log("Setting authorized caller in VirtualVault...");
    await trackGasUsage(
      virtualVault.setAuthorizedCaller(combinedVault.address, { gasLimit: 500000 }),
      "Set Authorized Caller in VirtualVault"
    );
    
    // Set VirtualVault in CombinedVault
    console.log("Setting VirtualVault in CombinedVault...");
    await trackGasUsage(
      combinedVault.setVirtualVault(virtualVault.address, { gasLimit: 500000 }),
      "Set VirtualVault in CombinedVault"
    );

    console.log("✅ All contracts deployed and initialized!");
  } catch (error) {
    console.error("Deployment process encountered an error:", error);
    console.log("Deployment failed");
  }

  // Log deployment addresses for proxies
  console.log("\n=== Deployment Summary ===");
  console.log("USDC Address:", USDC_ADDRESS);
  console.log(`ProtocolRegistry: https://scrollscan.com/address/${deployedAddresses.registry}#code`);
  console.log(`AaveAdapter: https://scrollscan.com/address/${deployedAddresses.aaveAdapter}#code`);
  console.log(`CompoundAdapter: https://scrollscan.com/address/${deployedAddresses.compoundAdapter}#code`);
  console.log(`VirtualVault: https://scrollscan.com/address/${deployedAddresses.virtualVault}#code`);
  console.log(`CombinedVault: https://scrollscan.com/address/${deployedAddresses.combinedVault}#code`);

  // Gas Usage Summary
  console.log("\n=== Gas Usage Summary ===");
  console.log(`Total Gas Used: ${totalGasUsed.toString()} units`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Fatal error:", error);
    process.exit(1);
  });