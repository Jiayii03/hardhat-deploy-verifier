// scripts/deploy.js - Modified with explicit gas settings
const hre = require("hardhat");
const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with account:", deployer.address);
  console.log("Account balance:", (await ethers.provider.getBalance(deployer.address)).toString());

  // Gas settings for transactions that might fail with automatic estimation
  const overrides = {
    gasLimit: 5000000, // Explicit gas limit
    // You can also set gasPrice if needed
    // gasPrice: ethers.utils.parseUnits("10", "gwei"), 
  };

  // Constants for protocol IDs
  const AAVE_PROTOCOL_ID = 1;
  const COMPOUND_PROTOCOL_ID = 2;
  const LAYERBANK_PROTOCOL_ID = 3;

  // Step 1: Use already deployed MockUSDC
  const mockUSDCAddress = "0x78bD59b3d9DAbDab8A39958E32dA04CCe9E2E6e8";
  const MockUSDC = await ethers.getContractFactory("MockUSDC");
  const mockUSDC = MockUSDC.attach(mockUSDCAddress);
  console.log("Using already deployed MockUSDC at:", mockUSDCAddress);

  // Step 2: Deploy protocol registry
  console.log("Deploying ProtocolRegistry...");
  const ProtocolRegistry = await ethers.getContractFactory("ProtocolRegistry");
  const registry = await ProtocolRegistry.deploy();
  await registry.deployed();
  const registryAddress = registry.address;
  console.log("ProtocolRegistry deployed at:", registryAddress);

  // Step 3: Deploy all three mock protocol adapters
  console.log("Deploying MockAaveAdapter...");
  const MockAaveAdapter = await ethers.getContractFactory("MockAaveAdapter");
  const mockAaveAdapter = await MockAaveAdapter.deploy(mockUSDCAddress);
  await mockAaveAdapter.deployed();
  const mockAaveAdapterAddress = mockAaveAdapter.address;
  console.log("MockAaveAdapter deployed at:", mockAaveAdapterAddress);

  console.log("Deploying MockCompoundAdapter...");
  const MockCompoundAdapter = await ethers.getContractFactory("MockCompoundAdapter");
  const mockCompoundAdapter = await MockCompoundAdapter.deploy(mockUSDCAddress);
  await mockCompoundAdapter.deployed();
  const mockCompoundAdapterAddress = mockCompoundAdapter.address;
  console.log("MockCompoundAdapter deployed at:", mockCompoundAdapterAddress);

  console.log("Deploying MockLayerBankAdapter...");
  const MockLayerBankAdapter = await ethers.getContractFactory("MockLayerBankAdapter");
  const mockLayerBankAdapter = await MockLayerBankAdapter.deploy(mockUSDCAddress);
  await mockLayerBankAdapter.deployed();
  const mockLayerBankAdapterAddress = mockLayerBankAdapter.address;
  console.log("MockLayerBankAdapter deployed at:", mockLayerBankAdapterAddress);

  // Add adapters as minters for MockUSDC
  console.log("Adding adapters as minters for MockUSDC...");
  await mockUSDC.addMinter(mockAaveAdapterAddress, overrides);
  await mockUSDC.addMinter(mockCompoundAdapterAddress, overrides);
  await mockUSDC.addMinter(mockLayerBankAdapterAddress, overrides);
  console.log("Added adapters as minters for MockUSDC");

  // Step 4: Configure adapters
  console.log("Configuring adapters...");
  try {
    // Try/catch for each adapter to continue if one fails
    try {
      console.log("Adding USDC to Aave adapter...");
      await mockAaveAdapter.addSupportedAsset(mockUSDCAddress, mockUSDCAddress, overrides);
      console.log("Supported assets added to Aave adapter");
    } catch (error) {
      console.error("Error adding asset to Aave adapter:", error.message);
      // Continue execution even if this fails
    }

    try {
      console.log("Adding USDC to Compound adapter...");
      await mockCompoundAdapter.addSupportedAsset(mockUSDCAddress, overrides);
      console.log("Supported assets added to Compound adapter");
    } catch (error) {
      console.error("Error adding asset to Compound adapter:", error.message);
      // Continue execution even if this fails
    }

    try {
      console.log("Adding USDC to LayerBank adapter...");
      await mockLayerBankAdapter.addSupportedAsset(mockUSDCAddress, mockUSDCAddress, overrides);
      console.log("Supported assets added to LayerBank adapter");
    } catch (error) {
      console.error("Error adding asset to LayerBank adapter:", error.message);
      // Continue execution even if this fails
    }
    
    console.log("Completed asset configuration for adapters");
  } catch (error) {
    console.error("Error in adapter configuration:", error.message);
  }

  // Set APYs (configure based on your testing needs)
  console.log("Setting APYs for adapters...");
  try {
    await mockAaveAdapter.setAPY(mockUSDCAddress, 39800, overrides); // 398.0%
    await mockCompoundAdapter.setAPY(mockUSDCAddress, 36000, overrides); // 360.0%
    await mockLayerBankAdapter.setAPY(mockUSDCAddress, 3800, overrides); // 38%
    console.log("APYs set for adapters");
  } catch (error) {
    console.error("Error setting APYs:", error.message);
  }

  // Step 5: Register protocols in registry
  console.log("Registering protocols in registry...");
  try {
    await registry.registerProtocol(AAVE_PROTOCOL_ID, "Mock Aave V3 MediumRisk", overrides);
    await registry.registerProtocol(COMPOUND_PROTOCOL_ID, "Mock Compound V3 MediumRisk", overrides);
    await registry.registerProtocol(LAYERBANK_PROTOCOL_ID, "Mock LayerBank MediumRisk", overrides);
    console.log("Protocols registered in registry");
  } catch (error) {
    console.error("Error registering protocols:", error.message);
  }

  // Step 6: Register adapters in registry
  console.log("Registering adapters in registry...");
  try {
    await registry.registerAdapter(AAVE_PROTOCOL_ID, mockUSDCAddress, mockAaveAdapterAddress, overrides);
    await registry.registerAdapter(COMPOUND_PROTOCOL_ID, mockUSDCAddress, mockCompoundAdapterAddress, overrides);
    await registry.registerAdapter(LAYERBANK_PROTOCOL_ID, mockUSDCAddress, mockLayerBankAdapterAddress, overrides);
    console.log("Adapters registered in registry");
  } catch (error) {
    console.error("Error registering adapters:", error.message);
  }

  // Add active protocols to registry
  try {
    await registry.addActiveProtocol(LAYERBANK_PROTOCOL_ID, overrides);
    // You can add more active protocols if needed
    console.log("Added Layerbank as active protocol");
  } catch (error) {
    console.error("Error adding active protocol:", error.message);
  }

  // Step 7: Deploy Combined Vault
  console.log("Deploying CombinedVault...");
  const CombinedVault = await ethers.getContractFactory("CombinedVault");
  const vault = await CombinedVault.deploy(registryAddress, mockUSDCAddress);
  await vault.deployed();
  const vaultAddress = vault.address;
  console.log("CombinedVault deployed at:", vaultAddress);

  // Step 9: Deploy YieldOptimizer
  console.log("Deploying YieldOptimizer...");
  const YieldOptimizer = await ethers.getContractFactory("YieldOptimizer");
  const optimizer = await YieldOptimizer.deploy(vaultAddress, mockUSDCAddress);
  await optimizer.deployed();
  const optimizerAddress = optimizer.address;
  console.log("YieldOptimizer deployed at:", optimizerAddress);

  // Step 10: Set YieldOptimizer as authorized caller for both contracts
  console.log("Setting YieldOptimizer as authorized caller...");
  try {
    await registry.setAuthorizedCaller(optimizerAddress, overrides);
    await vault.setAuthorizedCaller(optimizerAddress, overrides);
    console.log("YieldOptimizer set as authorized caller for both contracts");
  } catch (error) {
    console.error("Error setting authorized caller:", error.message);
  }

  // Step 11: Transfer ownership of registry to deployer wallet
  console.log("Transferring registry ownership...");
  try {
    await registry.transferOwnership(deployer.address, overrides);
    console.log("Registry ownership transferred to deployer");
  } catch (error) {
    console.error("Error transferring ownership:", error.message);
  }

  // Log important addresses for reference
  console.log("\n=== Deployment Summary ===");
  console.log("MockUSDC:", mockUSDCAddress);
  console.log("ProtocolRegistry:", registryAddress);
  console.log("MockAaveAdapter:", mockAaveAdapterAddress);
  console.log("MockCompoundAdapter:", mockCompoundAdapterAddress);
  console.log("MockLayerBankAdapter:", mockLayerBankAdapterAddress);
  console.log("CombinedVault:", vaultAddress);
  console.log("YieldOptimizer:", optimizerAddress);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });