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

  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with account:", deployer.address);
  console.log("Account balance:", (await ethers.provider.getBalance(deployer.address)).toString());

  // ==================== BASE MAINNET ====================
  const AAVE_POOL_ADDRESS = "0xA238Dd80C259a72e81d7e4664a9801593F98d1c5"; 
  const COMPOUND_POOL_ADDRESS = "0xb125E6687d4313864e53df431d5425969c15Eb2F"; 
  
  // Token addresses
  const USDC_ADDRESS = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"; 
  const USDC_ATOKEN_ADDRESS = "0x4e65fE4DbA92790696d040ac24Aa414708F5c0AB";
  const USDC_CTOKEN_ADDRESS = "0xb125E6687d4313864e53df431d5425969c15Eb2F"; 

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
    await registry.deployed();
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
    await aaveAdapter.deployed();
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
    await compoundAdapter.deployed();
    console.log("CompoundAdapter proxy deployed at:", compoundAdapter.address);
    deployedAddresses.compoundAdapter = compoundAdapter.address;

    // Step 4: Register protocols in registry
    console.log("\nRegistering protocols...");
    
    // Register Aave protocol
    console.log("Registering Aave protocol...");
    await registry.registerProtocol(AAVE_PROTOCOL_ID, "Aave V3", { gasLimit: 500000 });
    
    // Register Compound protocol
    console.log("Registering Compound protocol...");
    await registry.registerProtocol(COMPOUND_PROTOCOL_ID, "Compound V3", { gasLimit: 500000 });

    // Step 5: Configure adapters with supported assets
    console.log("\nConfiguring adapters...");
    
    // Configure Aave adapter
    console.log("Configuring Aave adapter...");
    await aaveAdapter.addSupportedAsset(USDC_ADDRESS, USDC_ATOKEN_ADDRESS, { gasLimit: 500000 });
    
    // Configure Compound adapter
    console.log("Configuring Compound adapter...");
    await compoundAdapter.addSupportedAsset(USDC_ADDRESS, USDC_CTOKEN_ADDRESS, { gasLimit: 500000 });

    // Step 6: Register adapters in registry
    console.log("\nRegistering adapters...");
    
    // Register Aave adapter
    console.log("Registering Aave adapter...");
    await registry.registerAdapter(AAVE_PROTOCOL_ID, USDC_ADDRESS, aaveAdapter.address, { gasLimit: 500000 });
    
    // Register Compound adapter
    console.log("Registering Compound adapter...");
    await registry.registerAdapter(COMPOUND_PROTOCOL_ID, USDC_ADDRESS, compoundAdapter.address, { gasLimit: 500000 });

    // Step 7: Deploy CombinedVault with proxy
    console.log("\nDeploying CombinedVault...");
    const CombinedVault = await ethers.getContractFactory("CombinedVault");
    const combinedVault = await upgrades.deployProxy(
      CombinedVault,
      [USDC_ADDRESS, registry.address],
      { kind: "transparent", initializer: "initialize" }
    );
    await combinedVault.deployed();
    console.log("CombinedVault proxy deployed at:", combinedVault.address);
    deployedAddresses.combinedVault = combinedVault.address;

    // Step 8: Deploy VirtualVault with proxy
    console.log("\nDeploying VirtualVault...");
    const VirtualVault = await ethers.getContractFactory("VirtualVault");
    const virtualVault = await upgrades.deployProxy(
      VirtualVault,
      [USDC_ADDRESS, combinedVault.address],
      { kind: "transparent", initializer: "initialize" }
    );
    await virtualVault.deployed();
    console.log("VirtualVault proxy deployed at:", virtualVault.address);
    deployedAddresses.virtualVault = virtualVault.address;

    // Step 9: Configure Registry and Vaults
    console.log("\nConfiguring Registry and Vaults...");
    
    // Set authorized caller
    console.log("Setting authorized caller...");
    await registry.setAuthorizedCaller(combinedVault.address);
    
    // Add Aave as active protocol
    console.log("Adding Aave as active protocol...");
    await combinedVault.addActiveProtocol(AAVE_PROTOCOL_ID, { gasLimit: 500000 });
    
    // Add Compound as active protocol
    console.log("Adding Compound as active protocol...");
    await combinedVault.addActiveProtocol(COMPOUND_PROTOCOL_ID, { gasLimit: 500000 });

    // Step 10: Link both vaults
    console.log("\nLinking vaults...");
    
    // Set authorized caller in VirtualVault
    console.log("Setting authorized caller in VirtualVault...");
    await virtualVault.setAuthorizedCaller(combinedVault.address, { gasLimit: 500000 });
    
    // Set VirtualVault in CombinedVault
    console.log("Setting VirtualVault in CombinedVault...");
    await combinedVault.setVirtualVault(virtualVault.address, { gasLimit: 500000 });

    console.log("✅ All contracts deployed and initialized!");
  } catch (error) {
    console.error("Deployment process encountered an error:", error);
    console.log("Deployment failed");
  }

  // Log deployment addresses
  console.log("\n=== Deployment Summary ===");
  console.log("USDC Address:", USDC_ADDRESS);
  console.log("\nProtocolRegistry:", deployedAddresses.registry || "Failed to deploy");
  console.log("AaveAdapter:", deployedAddresses.aaveAdapter || "Failed to deploy");
  console.log("CompoundAdapter:", deployedAddresses.compoundAdapter || "Failed to deploy");
  console.log("VirtualVault:", deployedAddresses.virtualVault || "Failed to deploy");
  console.log("CombinedVault:", deployedAddresses.combinedVault || "Failed to deploy");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Fatal error:", error);
    process.exit(1);
  });