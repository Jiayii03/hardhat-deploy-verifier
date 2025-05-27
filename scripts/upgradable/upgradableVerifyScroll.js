// scripts/verify-with-api.js
const hre = require("hardhat");
const { ethers, upgrades } = require("hardhat");
const fs = require("fs");
const path = require("path");
const axios = require("axios"); // You'll need to install axios: npm install axios

async function main() {
  // Your proxy addresses
  const REGISTRY_PROXY = "0x8ceE3EBFe716fca99197B7AF1B3e8809Dd7f1db5";
  const AAVE_ADAPTER_PROXY = "0xad0b5Af5BD6aB561926785b20632b9c0b432c972";
  const COMPOUND_ADAPTER_PROXY = "0xF7dF5097948545CA6B6a11BF9Ab7ea03e4c38817";
  const VIRTUAL_VAULT_PROXY = "0xE16Bbaf8206a2DE4409FeaA47e29c6B28Ff13c47";
  const COMBINED_VAULT_PROXY = "0x876c4462949d3a7861D469F404511AC0F2ae20C6";
  
  // Get API key from hardhat config
  const apiKey = hre.config.etherscan.apiKey.base;
  if (!apiKey) {
    throw new Error("No API key found for Base network!");
  }
  
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
  const virtualVaultImpl = await upgrades.erc1967.getImplementationAddress(VIRTUAL_VAULT_PROXY);
  const combinedVaultImpl = await upgrades.erc1967.getImplementationAddress(COMBINED_VAULT_PROXY);
  
  console.log("Implementation Addresses:");
  console.log("ProtocolRegistry:", registryImpl);
  console.log("AaveAdapter:", aaveAdapterImpl);
  console.log("CompoundAdapter:", compoundAdapterImpl);
  console.log("VirtualVault:", virtualVaultImpl);
  console.log("CombinedVault:", combinedVaultImpl);

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
      return outputPath;
    } catch (error) {
      console.error(`Error flattening ${contractPath}:`, error.message);
      return null;
    }
  }
  
  // Function to verify a contract using Basescan API directly
  async function verifyContractWithAPI(contractName, contractAddress, flattenedPath) {
    console.log(`\nVerifying ${contractName} at ${contractAddress}...`);
    
    // Check if contract is already verified
    try {
      const checkResponse = await axios.get(`https://api.basescan.org/api`, {
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
    
    // Direct API verification
    try {
      // Settings from your hardhat.config.js
      const compiler = "v0.8.20+commit.a1b79de6"; // Adjust to match your compiler version exactly
      const optimized = true;
      const runs = 200;
      
      console.log(`Submitting verification request to Basescan API...`);
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
        evmversion: 'paris', // Try 'paris' or 'london'
        licenseType: '3' // MIT License
      };
      
      // Submit verification request
      const verifyResponse = await axios.post(
        'https://api.basescan.org/api',
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
        console.log(`Waiting 15 seconds for verification to complete...`);
        await new Promise(resolve => setTimeout(resolve, 15000));
        
        const statusResponse = await axios.get(`https://api.basescan.org/api`, {
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
          
          // If it fails with the current settings, try with different EVM versions
          if (status.includes('solc version') || status.includes('invalid evm version')) {
            const evmVersions = ['london', 'berlin', 'istanbul', 'petersburg', 'constantinople', 'byzantium'];
            for (const evmVersion of evmVersions) {
              if (evmVersion === 'paris') continue; // We already tried paris
              
              console.log(`\nRetrying with EVM version: ${evmVersion}...`);
              
              const retryData = {
                ...verifyData,
                evmversion: evmVersion
              };
              
              const retryResponse = await axios.post(
                'https://api.basescan.org/api',
                new URLSearchParams(retryData),
                {
                  headers: {
                    'Content-Type': 'application/x-www-form-urlencoded'
                  }
                }
              );
              
              if (retryResponse.data.status === '1') {
                console.log(`✅ Retry verification request submitted successfully!`);
                console.log(`GUID: ${retryResponse.data.result}`);
                
                // Check verification status after a delay
                console.log(`Waiting 15 seconds for verification to complete...`);
                await new Promise(resolve => setTimeout(resolve, 15000));
                
                const retryStatusResponse = await axios.get(`https://api.basescan.org/api`, {
                  params: {
                    module: 'contract',
                    action: 'checkverifystatus',
                    guid: retryResponse.data.result,
                    apikey: apiKey
                  }
                });
                
                const retryStatus = retryStatusResponse.data.result;
                console.log(`Retry verification status: ${retryStatus}`);
                
                if (retryStatus.includes('Success') || retryStatus.includes('Already Verified') || retryStatus === 'Pass - Verified') {
                  console.log(`✅ ${contractName} successfully verified with EVM version ${evmVersion}!`);
                  return true;
                }
              }
            }
          }
          
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
  
  // Flatten and verify contracts
  // console.log("\n=== Flattening and Verifying Contracts ===");
  
  // // ProtocolRegistry
  // const registryFlatPath = await flattenContract(
  //   "contracts/core/ProtocolRegistry.sol", 
  //   "ProtocolRegistry_flat.sol"
  // );
  // if (registryFlatPath) {
  //   await verifyContractWithAPI("ProtocolRegistry", registryImpl, registryFlatPath);
  // }
  
  // // AaveAdapter
  // const aaveAdapterFlatPath = await flattenContract(
  //   "contracts/adapters/AaveAdapter.sol", 
  //   "AaveAdapter_flat.sol"
  // );
  // if (aaveAdapterFlatPath) {
  //   await verifyContractWithAPI("AaveAdapter", aaveAdapterImpl, aaveAdapterFlatPath);
  // }
  
  // // CompoundAdapter
  // const compoundAdapterFlatPath = await flattenContract(
  //   "contracts/adapters/CompoundAdapter.sol", 
  //   "CompoundAdapter_flat.sol"
  // );
  // if (compoundAdapterFlatPath) {
  //   await verifyContractWithAPI("CompoundAdapter", compoundAdapterImpl, compoundAdapterFlatPath);
  // }

  // VirtualVault
  // const virtualVaultFlatPath = await flattenContract(
  //   "contracts/core/VirtualVault.sol", 
  //   "VirtualVault_flat.sol"
  // );
  // if (virtualVaultFlatPath) {
  //   await verifyContractWithAPI("VirtualVault", virtualVaultImpl, virtualVaultFlatPath);
  // }

  // CombinedVault
  const combinedVaultFlatPath = await flattenContract(
    "contracts/core/CombinedVault.sol", 
    "CombinedVault_flat.sol"
  );
  if (combinedVaultFlatPath) {  
    await verifyContractWithAPI("CombinedVault", combinedVaultImpl, combinedVaultFlatPath);
  }
  
  console.log("\n=== Verification Process Complete ===");
  console.log("Check contract verification status on Basescan:");
  // console.log(`https://basescan.org/address/${registryImpl}#code`);
  // console.log(`https://basescan.org/address/${aaveAdapterImpl}#code`);
  // console.log(`https://basescan.org/address/${compoundAdapterImpl}#code`);
  // console.log(`https://basescan.org/address/${virtualVaultImpl}#code`);
  console.log(`https://basescan.org/address/${combinedVaultImpl}#code`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Fatal error:", error);
    process.exit(1);
  });