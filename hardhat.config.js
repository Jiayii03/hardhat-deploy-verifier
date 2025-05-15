require("@nomiclabs/hardhat-ethers");
require("@nomicfoundation/hardhat-verify");
require("@openzeppelin/hardhat-upgrades");
const { createAlchemyWeb3 } = require("@alch/alchemy-web3");
const { task } = require("hardhat/config");
const path = require("path");
require("dotenv").config();

// API URLs
const API_URL_SCROLL = process.env.API_URL_SCROLL;
const API_URL_SEPOLIA = process.env.API_URL_SEPOLIA;
const API_URL_BASE_SEPOLIA = process.env.API_URL_BASE_SEPOLIA;
const API_URL_BASE = process.env.API_URL_BASE;
const API_URL_ANVIL = process.env.API_URL_ANVIL;

// PKs
const PRIVATE_KEY = process.env.PRIVATE_KEY;
const ANVIL_PRIVATE_KEY = process.env.ANVIL_PRIVATE_KEY;

// Web3 providers
const web3Scroll = createAlchemyWeb3(API_URL_SCROLL);
const web3Sepolia = createAlchemyWeb3(API_URL_SEPOLIA);
const web3BaseSepolia = createAlchemyWeb3(API_URL_BASE_SEPOLIA);
const web3Base = createAlchemyWeb3(API_URL_BASE);

const networkIDArr = ["Scroll Sepolia:", "Sepolia:", "Base Sepolia:", "Base:"];
const providerArr = [web3Scroll, web3Sepolia, web3BaseSepolia, web3Base];

task("account", "Returns nonce and balance for specified address on all networks")
  .addParam("address", "The address to query")
  .setAction(async ({ address }) => {
    const resultArr = [["| NETWORK | NONCE | BALANCE |"]];
    for (let i = 0; i < providerArr.length; i++) {
      const nonce = await providerArr[i].eth.getTransactionCount(address, "latest");
      const balance = await providerArr[i].eth.getBalance(address);
      resultArr.push([
        networkIDArr[i],
        nonce,
        `${parseFloat(providerArr[i].utils.fromWei(balance, "ether")).toFixed(2)} ETH`
      ]);
    }
    console.log(resultArr);
  });

module.exports = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      },
      // viaIR: true
    }
  },
  networks: {
    hardhat: {},
    scrollSepolia: {
      url: API_URL_SCROLL,
      accounts: [`0x${PRIVATE_KEY}`],
      chainId: 534351,
      ensAddress: null
    },
    sepolia: {
      url: API_URL_SEPOLIA,
      accounts: [`0x${PRIVATE_KEY}`],
      chainId: 11155111
    },
    baseSepolia: {
      url: API_URL_BASE_SEPOLIA,
      accounts: [`0x${PRIVATE_KEY}`],
      chainId: 84532
    },
    base: {
      url: API_URL_BASE,
      accounts: [`0x${PRIVATE_KEY}`],
      chainId: 8453
    },
    anvilForkedBase: {
      url: API_URL_ANVIL,
      accounts: [`0x${ANVIL_PRIVATE_KEY}`],
      chainId: 8453,
      forking: {
        url: API_URL_BASE,
      }
    }
  },
  etherscan: {
    apiKey: {
      scrollSepolia: process.env.ETHERSCAN_API_KEY_SCROLL_SEPOLIA,
      sepolia: process.env.ETHERSCAN_API_KEY_SEPOLIA,
      baseSepolia: process.env.ETHERSCAN_API_KEY_BASE_SEPOLIA,
      base: process.env.ETHERSCAN_API_KEY_BASE
    },
    customChains: [
      {
        network: "scrollSepolia",
        chainId: 534351,
        ensAddress: null,
        urls: {
          apiURL: "https://api-sepolia.scrollscan.com/api",
          browserURL: "https://sepolia.scrollscan.com"
        }
      },
      {
        network: "sepolia",
        chainId: 11155111,
        urls: {
          apiURL: "https://api-sepolia.etherscan.io/api",
          browserURL: "https://sepolia.etherscan.io"
        }
      },
      {
        network: "baseSepolia",
        chainId: 84532,
        urls: {
          apiURL: "https://api-sepolia.basescan.org/api",
          browserURL: "https://sepolia.basescan.org"
        }
      },
      {
        network: "anvilForkedBase",
        chainId: 8453,
        urls: {
          apiURL: "http://127.0.0.1:8545/api",
          browserURL: "http://127.0.0.1:8545"
        }
      },
      {
        network: "base",
        chainId: 8453,
        urls: {
          apiURL: "https://api.basescan.org/api",
          browserURL: "https://basescan.org"
        }
      }
    ]
  },
  sourcify: {
    enabled: false
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts"
  },
  // Add this custom resolver for imports
  resolveJsonModule: true,
  includeExternalResources: true,
  // This is a simple way to handle the LayerBank imports
  customNetworkingPromit: (hardhatContext, { config, files, errors }) => {
    // Modify imports for LayerBank specifically
    files.forEach(file => {
      if (file.content && file.content.includes('@layerbank-contracts/')) {
        file.content = file.content.replace(
          /@layerbank-contracts\//g,
          path.join(__dirname, 'external-libs/layerbank-contracts/')
        );
      }
    });
    return { files, errors };
  }
};