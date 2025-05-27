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
      [
        USDC_ADDRESS,
        registry.address,
        deployer.address, // treasury address
        1000 // 10% performance fee (1000 basis points)
      ],
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
    
    // Set authorized caller in registry
    console.log("Setting authorized caller in registry...");
    await registry.setAuthorizedCaller(combinedVault.address, { gasLimit: 500000 });
    
    // Set authorized caller in adapters
    console.log("Setting authorized caller in Aave adapter...");
    await aaveAdapter.setAuthorizedCaller(combinedVault.address, { gasLimit: 500000 });
    
    console.log("Setting authorized caller in Compound adapter...");
    await compoundAdapter.setAuthorizedCaller(combinedVault.address, { gasLimit: 500000 });
    
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