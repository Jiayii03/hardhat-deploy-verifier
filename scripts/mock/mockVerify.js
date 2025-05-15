// scripts/verify.js
const hre = require("hardhat");

async function main() {
  // Replace these with your actual deployed contract addresses
  const MOCK_USDC_ADDRESS = "0x78bD59b3d9DAbDab8A39958E32dA04CCe9E2E6e8";
  const PROTOCOL_REGISTRY_ADDRESS =
    "0xb06599032788F0C6A45C1aeCf834FCDa2EDfA103";
  const MOCK_AAVE_ADAPTER_ADDRESS =
    "0x6Bc24C25617a2C6D2b8059A824CAF67CCf6179b2";
  const MOCK_COMPOUND_ADAPTER_ADDRESS =
    "0x1E2073E134c5F5EEe09cC946A341Fff8dc87544a";
  const MOCK_LAYERBANK_ADAPTER_ADDRESS =
    "0xe11E2CfC47efA3aB21fC87E9b31f406dF13D5F82";
  const COMBINED_VAULT_ADDRESS = "0xb659c44794d96d558776AacdE7Ab32a7635B980F";
  const YIELD_OPTIMIZER_ADDRESS = "0xbbC8f4d5050A9969A73f22328Bd82C88b7d439f1";

  console.log("Starting contract verification...");

  // try {
  //   console.log("Verifying MockUSDC...");
  //   await hre.run("verify:verify", {
  //     address: MOCK_USDC_ADDRESS,
  //     constructorArguments: [DEPLOYER_ADDRESS],
  //     contract: "contracts/tokens/mocks/MockUSDC.sol:MockUSDC"
  //   });
  //   console.log("MockUSDC verified successfully!");
  // } catch (error) {
  //   console.log("Error verifying MockUSDC:", error.message);
  // }

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
    console.log("Verifying MockAaveAdapter...");
    await hre.run("verify:verify", {
      address: MOCK_AAVE_ADAPTER_ADDRESS,
      constructorArguments: [MOCK_USDC_ADDRESS],
      contract: "contracts/adapters/mocks/MockAaveAdapter.sol:MockAaveAdapter",
    });
    console.log("MockAaveAdapter verified successfully!");
  } catch (error) {
    console.log("Error verifying MockAaveAdapter:", error.message);
  }

  try {
    console.log("Verifying MockCompoundAdapter...");
    await hre.run("verify:verify", {
      address: MOCK_COMPOUND_ADAPTER_ADDRESS,
      constructorArguments: [MOCK_USDC_ADDRESS],
      contract:
        "contracts/adapters/mocks/MockCompoundAdapter.sol:MockCompoundAdapter",
    });
    console.log("MockCompoundAdapter verified successfully!");
  } catch (error) {
    console.log("Error verifying MockCompoundAdapter:", error.message);
  }

  try {
    console.log("Verifying MockLayerBankAdapter...");
    await hre.run("verify:verify", {
      address: MOCK_LAYERBANK_ADAPTER_ADDRESS,
      constructorArguments: [MOCK_USDC_ADDRESS],
      contract:
        "contracts/adapters/mocks/MockLayerBankAdapter.sol:MockLayerBankAdapter",
    });
    console.log("MockLayerBankAdapter verified successfully!");
  } catch (error) {
    console.log("Error verifying MockLayerBankAdapter:", error.message);
  }

  try {
    console.log("Verifying CombinedVault...");
    await hre.run("verify:verify", {
      address: COMBINED_VAULT_ADDRESS,
      constructorArguments: [PROTOCOL_REGISTRY_ADDRESS, MOCK_USDC_ADDRESS],
      contract: "contracts/core/CombinedVault.sol:CombinedVault",
    });
    console.log("CombinedVault verified successfully!");
  } catch (error) {
    console.log("Error verifying CombinedVault:", error.message);
  }

  try {
    console.log("Verifying YieldOptimizer...");
    await hre.run("verify:verify", {
      address: YIELD_OPTIMIZER_ADDRESS,
      constructorArguments: [COMBINED_VAULT_ADDRESS, MOCK_USDC_ADDRESS],
      contract: "contracts/Strategy/YieldOptimizer.sol:YieldOptimizer",
    });
    console.log("YieldOptimizer verified successfully!");
  } catch (error) {
    console.log("Error verifying YieldOptimizer:", error.message);
  }

  console.log("Verification process completed!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
