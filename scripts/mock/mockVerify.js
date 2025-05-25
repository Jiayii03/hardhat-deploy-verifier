// scripts/verify.js
const hre = require("hardhat");
const fs = require("fs");
const path = require("path");
const axios = require("axios"); // You'll need to install axios: npm install axios

async function main() {
  // Replace these with your actual deployed contract addresses
  const DEPLOYER_ADDRESS = "0x567bDc4086eFc460811798d1075a21359E34072d";
  const MOCK_USDC_ADDRESS = "0xbbe1fa82A907C43F2fA2D01215749734E67189bc";
  const PROTOCOL_REGISTRY_ADDRESS =
    "0x0a73e889eE3333c2D65edBe2A9D38f1425B75b4A";
  const MOCK_AAVE_ADAPTER_ADDRESS =
    "0x51d27E74eCC27f13fbF3A6E6A4d8635D5199DC83";
  const MOCK_COMPOUND_ADAPTER_ADDRESS =
    "0xDbC91EB9E113E963bD4587802117eF9e7636351C";
  const MOCK_LAYERBANK_ADAPTER_ADDRESS =
    "0x2CCdF6c00B532b665D1E79174Ec67408f8BbB000";
  const COMBINED_VAULT_ADDRESS = "0x1E2073E134c5F5EEe09cC946A341Fff8dc87544a";
  const YIELD_OPTIMIZER_ADDRESS = "0xe11E2CfC47efA3aB21fC87E9b31f406dF13D5F82";

  console.log("Starting contract verification for Scroll Sepolia...");

  // Get API key from hardhat config
  const apiKey = hre.config.etherscan.apiKey.scrollSepolia;
  if (!apiKey) {
    throw new Error("No API key found for Scroll Sepolia network!");
  }

  // Create flattened directory if it doesn't exist
  const flattenedDir = path.join(__dirname, "../../flattened");
  if (!fs.existsSync(flattenedDir)) {
    fs.mkdirSync(flattenedDir, { recursive: true });
  }

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
      
      const outputPath = path.join(flattenedDir, outputFileName);
      fs.writeFileSync(outputPath, cleanedCode);
      console.log(`Saved flattened contract to: ${outputPath}`);
      return outputPath;
    } catch (error) {
      console.error(`Error flattening ${contractPath}:`, error.message);
      return null;
    }
  }

  // Function to verify a contract using Scroll Sepolia API directly
  async function verifyContractWithAPI(contractName, contractAddress, flattenedPath, constructorArgs = []) {
    console.log(`\nVerifying ${contractName} at ${contractAddress}...`);
    
    // Check if contract is already verified
    try {
      const checkResponse = await axios.get(`https://api-sepolia.scrollscan.com/api`, {
        params: {
          module: 'contract',
          action: 'getsourcecode',
          address: contractAddress,
          apikey: apiKey
        }
      });
      
      if (checkResponse.data.status === '1' && 
          checkResponse.data.result && 
          checkResponse.data.result[0].SourceCode && 
          checkResponse.data.result[0].SourceCode.length > 10) {
        console.log(`✅ ${contractName} is already verified!`);
        return true;
      }
    } catch (error) {
      console.log(`Error checking verification status: ${error.message}`);
    }
    
    // Read flattened contract code
    const sourceCode = fs.readFileSync(flattenedPath, 'utf8');
    
    // Encode constructor arguments if provided
    let encodedConstructorArgs = "";
    if (constructorArgs.length > 0) {
      try {
        const MockUSDC = await hre.ethers.getContractFactory("MockUSDC");
        encodedConstructorArgs = MockUSDC.interface.encodeDeploy(constructorArgs).slice(2);
        console.log(`Encoded constructor arguments: ${encodedConstructorArgs}`);
      } catch (error) {
        console.log(`Error encoding constructor arguments: ${error.message}`);
      }
    }
    
    // Direct API verification
    try {
      // Settings from your hardhat.config.js
      const compiler = "v0.8.20+commit.a1b79de6"; // Adjust to match your compiler version exactly
      const optimized = true;
      const runs = 200;
      
      console.log(`Submitting verification request to Scroll Sepolia API...`);
      console.log(`Using compiler: ${compiler}`);
      console.log(`Optimization: ${optimized ? 'enabled' : 'disabled'}, runs: ${runs}`);
      
      const verifyData = {
        apikey: apiKey,
        module: 'contract',
        action: 'verifysourcecode',
        contractaddress: contractAddress,
        sourceCode: sourceCode,
        codeformat: 'solidity-single-file',
        contractname: contractName,
        compilerversion: compiler,
        optimizationUsed: optimized ? '1' : '0',
        runs: runs.toString(),
        constructorArguements: encodedConstructorArgs, // Note: Scroll uses "Arguements" not "Arguments"
        evmversion: 'paris', // Try 'paris' or 'london'
        licenseType: '3' // MIT License
      };
      
      // Submit verification request
      const verifyResponse = await axios.post(
        'https://api-sepolia.scrollscan.com/api',
        new URLSearchParams(verifyData),
        {
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded'
          }
        }
      );
      
      if (verifyResponse.data.status === '1') {
        console.log(`✅ Verification request submitted successfully!`);
        console.log(`GUID: ${verifyResponse.data.result}`);
        
        // Check verification status after a delay
        console.log(`Waiting 20 seconds for verification to complete...`);
        await new Promise(resolve => setTimeout(resolve, 20000));
        
        const statusResponse = await axios.get(`https://api-sepolia.scrollscan.com/api`, {
          params: {
            module: 'contract',
            action: 'checkverifystatus',
            guid: verifyResponse.data.result,
            apikey: apiKey
          }
        });
        
        const status = statusResponse.data.result;
        console.log(`Verification status: ${status}`);
        
        if (status.includes('Success') || status.includes('Already Verified') || status === 'Pass - Verified') {
          console.log(`✅ ${contractName} successfully verified!`);
          return true;
        } else {
          console.log(`❌ Verification failed: ${status}`);
          return false;
        }
      } else {
        console.log(`❌ Verification request failed: ${verifyResponse.data.result}`);
        return false;
      }
    } catch (error) {
      console.error(`Error verifying ${contractName}:`, error.message);
      return false;
    }
  }

  // Flatten MockUSDC contract
  console.log("\n=== Flattening MockUSDC Contract ===");
  const mockUSDCFlatPath = await flattenContract(
    "contracts/tokens/mocks/MockUSDC.sol", 
    "MockUSDC_flattened.sol"
  );

  if (mockUSDCFlatPath) {
    console.log("\n=== Verifying MockUSDC Contract ===");
    const success = await verifyContractWithAPI(
      "MockUSDC", 
      MOCK_USDC_ADDRESS, 
      mockUSDCFlatPath, 
      [DEPLOYER_ADDRESS]
    );
    
    if (success) {
      console.log(`\n✅ MockUSDC verification completed successfully!`);
      console.log(`Check verification status on Scroll Sepolia explorer:`);
      console.log(`https://sepolia.scrollscan.com/address/${MOCK_USDC_ADDRESS}#code`);
    } else {
      console.log(`\n❌ MockUSDC verification failed.`);
      console.log(`You can manually verify using the flattened contract at: ${mockUSDCFlatPath}`);
      console.log(`Constructor arguments: ["${DEPLOYER_ADDRESS}"]`);
      console.log(`Contract address: ${MOCK_USDC_ADDRESS}`);
    }
  } else {
    console.log("❌ Failed to flatten MockUSDC contract");
  }

  // try {
  //   console.log("Verifying ProtocolRegistry...");
  //   await hre.run("verify:verify", {
  //     address: PROTOCOL_REGISTRY_ADDRESS,
  //     constructorArguments: [],
  //     contract: "contracts/core/ProtocolRegistry.sol:ProtocolRegistry",
  //   });
  //   console.log("ProtocolRegistry verified successfully!");
  // } catch (error) {
  //   console.log("Error verifying ProtocolRegistry:", error.message);
  // }

  // try {
  //   console.log("Verifying MockAaveAdapter...");
  //   await hre.run("verify:verify", {
  //     address: MOCK_AAVE_ADAPTER_ADDRESS,
  //     constructorArguments: [MOCK_USDC_ADDRESS],
  //     contract: "contracts/adapters/mocks/MockAaveAdapter.sol:MockAaveAdapter",
  //   });
  //   console.log("MockAaveAdapter verified successfully!");
  // } catch (error) {
  //   console.log("Error verifying MockAaveAdapter:", error.message);
  // }

  // try {
  //   console.log("Verifying MockCompoundAdapter...");
  //   await hre.run("verify:verify", {
  //     address: MOCK_COMPOUND_ADAPTER_ADDRESS,
  //     constructorArguments: [MOCK_USDC_ADDRESS],
  //     contract:
  //       "contracts/adapters/mocks/MockCompoundAdapter.sol:MockCompoundAdapter",
  //   });
  //   console.log("MockCompoundAdapter verified successfully!");
  // } catch (error) {
  //   console.log("Error verifying MockCompoundAdapter:", error.message);
  // }

  // try {
  //   console.log("Verifying MockLayerBankAdapter...");
  //   await hre.run("verify:verify", {
  //     address: MOCK_LAYERBANK_ADAPTER_ADDRESS,
  //     constructorArguments: [MOCK_USDC_ADDRESS],
  //     contract:
  //       "contracts/adapters/mocks/MockLayerBankAdapter.sol:MockLayerBankAdapter",
  //   });
  //   console.log("MockLayerBankAdapter verified successfully!");
  // } catch (error) {
  //   console.log("Error verifying MockLayerBankAdapter:", error.message);
  // }

  // try {
  //   console.log("Verifying CombinedVault...");
  //   await hre.run("verify:verify", {
  //     address: COMBINED_VAULT_ADDRESS,
  //     constructorArguments: [PROTOCOL_REGISTRY_ADDRESS, MOCK_USDC_ADDRESS],
  //     contract: "contracts/core/CombinedVault.sol:CombinedVault",
  //   });
  //   console.log("CombinedVault verified successfully!");
  // } catch (error) {
  //   console.log("Error verifying CombinedVault:", error.message);
  // }

  // try {
  //   console.log("Verifying YieldOptimizer...");
  //   await hre.run("verify:verify", {
  //     address: YIELD_OPTIMIZER_ADDRESS,
  //     constructorArguments: [COMBINED_VAULT_ADDRESS, MOCK_USDC_ADDRESS],
  //     contract: "contracts/Strategy/YieldOptimizer.sol:YieldOptimizer",
  //   });
  //   console.log("YieldOptimizer verified successfully!");
  // } catch (error) {
  //   console.log("Error verifying YieldOptimizer:", error.message);
  // }

  console.log("Verification process completed!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
