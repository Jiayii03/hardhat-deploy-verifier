// scripts/verify-with-api.js
const hre = require("hardhat");
const { ethers, upgrades } = require("hardhat");
const fs = require("fs");
const path = require("path");
const axios = require("axios"); // You'll need to install axios: npm install axios

async function main() {
  // Your proxy addresses
  const REGISTRY_PROXY = "0x7f5b50bb94Ca80027FDe2fA00607B9d1CD51384e";
  const AAVE_ADAPTER_PROXY = "0x158Fc38C128D70bef153A10256FA878C0b294792";
  const COMPOUND_ADAPTER_PROXY = "0x691303a12A4fBfFEBdFB282336181E9A45730bfd";
  const VIRTUAL_VAULT_PROXY = "0x6a8897284DF2F50Fe797A3D6665995D50BDeE69A";
  const COMBINED_VAULT_PROXY = "0x6C50E082E08365450F2231f88e1625e8EeB23dFF";
  
  // Get API key from hardhat config
  const apiKey = hre.config.etherscan.apiKey.scroll;
  if (!apiKey) {
    throw new Error("No API key found for Scroll network!");
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
  
  // Function to verify a contract using Scrollscan API directly
  async function verifyContractWithAPI(contractName, contractAddress, flattenedPath) {
    console.log(`\nVerifying ${contractName} at ${contractAddress}...`);
    
    // Check if contract is already verified
    try {
      const checkResponse = await axios.get(`https://api.scrollscan.com/api`, {
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
      
      console.log(`Submitting verification request to Scrollscan API...`);
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
        'https://api.scrollscan.com/api',
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
        
        const statusResponse = await axios.get(`https://api.scrollscan.com/api`, {
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
                'https://api.scrollscan.com/api',
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
                
                const retryStatusResponse = await axios.get(`https://api.scrollscan.com/api`, {
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
  console.log("\n=== Flattening and Verifying Contracts ===");
  
  // ProtocolRegistry
  const registryFlatPath = await flattenContract(
    "contracts/core/ProtocolRegistry.sol", 
    "ProtocolRegistry_flat.sol"
  );
  if (registryFlatPath) {
    await verifyContractWithAPI("ProtocolRegistry", registryImpl, registryFlatPath);
  }
  
  // AaveAdapter
  const aaveAdapterFlatPath = await flattenContract(
    "contracts/adapters/AaveAdapter.sol", 
    "AaveAdapter_flat.sol"
  );
  if (aaveAdapterFlatPath) {
    await verifyContractWithAPI("AaveAdapter", aaveAdapterImpl, aaveAdapterFlatPath);
  }
  
  // CompoundAdapter
  const compoundAdapterFlatPath = await flattenContract(
    "contracts/adapters/CompoundAdapter.sol", 
    "CompoundAdapter_flat.sol"
  );
  if (compoundAdapterFlatPath) {
    await verifyContractWithAPI("CompoundAdapter", compoundAdapterImpl, compoundAdapterFlatPath);
  }

  // VirtualVault
  const virtualVaultFlatPath = await flattenContract(
    "contracts/core/VirtualVault.sol", 
    "VirtualVault_flat.sol"
  );
  if (virtualVaultFlatPath) {
    await verifyContractWithAPI("VirtualVault", virtualVaultImpl, virtualVaultFlatPath);
  }

  // CombinedVault
  const combinedVaultFlatPath = await flattenContract(
    "contracts/core/CombinedVault.sol", 
    "CombinedVault_flat.sol"
  );
  if (combinedVaultFlatPath) {  
    await verifyContractWithAPI("CombinedVault", combinedVaultImpl, combinedVaultFlatPath);
  }
  
  console.log("\n=== Verification Process Complete ===");
  console.log("Check contract verification status on Scrollscan:");
  console.log(`ProtocolRegistry Proxy: https://scrollscan.com/address/${REGISTRY_PROXY}#code`);
  console.log(`ProtocolRegistry Implementation: https://scrollscan.com/address/${registryImpl}#code`);
  console.log(`AaveAdapter Proxy: https://scrollscan.com/address/${AAVE_ADAPTER_PROXY}#code`);
  console.log(`AaveAdapter Implementation: https://scrollscan.com/address/${aaveAdapterImpl}#code`);
  console.log(`CompoundAdapter Proxy: https://scrollscan.com/address/${COMPOUND_ADAPTER_PROXY}#code`);
  console.log(`CompoundAdapter Implementation: https://scrollscan.com/address/${compoundAdapterImpl}#code`);
  console.log(`VirtualVault Proxy: https://scrollscan.com/address/${VIRTUAL_VAULT_PROXY}#code`);
  console.log(`VirtualVault Implementation: https://scrollscan.com/address/${virtualVaultImpl}#code`);
  console.log(`CombinedVault Proxy: https://scrollscan.com/address/${COMBINED_VAULT_PROXY}#code`);
  console.log(`CombinedVault Implementation: https://scrollscan.com/address/${combinedVaultImpl}#code`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Fatal error:", error);
    process.exit(1);
  });