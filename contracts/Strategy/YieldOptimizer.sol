// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../core/CombinedVault.sol";
import "../core/interfaces/IRegistry.sol";
import "../adapters/interfaces/IProtocolAdapter.sol";

contract YieldOptimizer {
    IRegistry public registry;
    CombinedVault public vault;
    IERC20 public immutable asset;
    
    // Maximum number of active protocols
    uint256 public maxActiveProtocols = 3;

    // Struct to track protocol IDs and their APYs
    struct ProtocolAPY {
        uint256 protocolId;
        uint256 apy;
        bool isActive;
    }

    event OptimizedYield(uint256 replacedProtocolId, uint256 newProtocolId, uint256 amount);
    event MaxActiveProtocolsUpdated(uint256 oldValue, uint256 newValue);

    constructor(address _vault, address _asset) {
        require(_vault != address(0), "Invalid vault address");
        require(_asset != address(0), "Invalid asset address");

        vault = CombinedVault(_vault);
        registry = vault.registry();
        asset = IERC20(_asset);
    }
    
    /**
     * @notice Set the maximum number of active protocols
     * @param _maxActiveProtocols The new maximum number of active protocols
     */
    function setMaxActiveProtocols(uint256 _maxActiveProtocols) external {
        require(msg.sender == vault.owner(), "Not authorized");
        require(_maxActiveProtocols > 0, "Must be greater than zero");
        
        uint256 oldValue = maxActiveProtocols;
        maxActiveProtocols = _maxActiveProtocols;
        
        emit MaxActiveProtocolsUpdated(oldValue, _maxActiveProtocols);
    }

    /**
     * @notice Optimizes yield by selecting the highest APY protocols
     * @dev Called automatically via Chainlink Automation at the end of each epoch
     */
    function optimizeYield() external {
        // Get current active protocols
        uint256[] memory activeProtocolIds = registry.getActiveProtocolIds();
        uint256[] memory allProtocolIds = registry.getAllProtocolIds();
        
        // Create arrays to store APYs for all active and inactive protocols
        uint256[] memory activeProtocolAPYs = new uint256[](activeProtocolIds.length);
        
        // Create array for protocol APYs
        ProtocolAPY[] memory protocolAPYs = new ProtocolAPY[](allProtocolIds.length);
        uint256 protocolCount = 0;
        
        // Get APYs for all active protocols
        for (uint256 i = 0; i < activeProtocolIds.length; i++) {
            uint256 protocolId = activeProtocolIds[i];
            address adapterAddress = address(registry.getAdapter(protocolId, address(asset)));
            
            if (adapterAddress != address(0)) {
                uint256 apy = IProtocolAdapter(adapterAddress).getAPY(address(asset));
                activeProtocolAPYs[i] = apy;
                
                protocolAPYs[protocolCount] = ProtocolAPY({
                    protocolId: protocolId,
                    apy: apy,
                    isActive: true
                });
                protocolCount++;
            }
        }
        
        // Get APYs for all inactive protocols
        for (uint256 i = 0; i < allProtocolIds.length; i++) {
            uint256 protocolId = allProtocolIds[i];
            
            // Check if this protocol is already in our active list
            bool alreadyActive = false;
            for (uint256 j = 0; j < activeProtocolIds.length; j++) {
                if (protocolId == activeProtocolIds[j]) {
                    alreadyActive = true;
                    break;
                }
            }
            
            // Skip if already processed as active
            if (alreadyActive) continue;
            
            address adapterAddress = address(registry.getAdapter(protocolId, address(asset)));
            
            if (adapterAddress != address(0)) {
                uint256 apy = IProtocolAdapter(adapterAddress).getAPY(address(asset));
                
                protocolAPYs[protocolCount] = ProtocolAPY({
                    protocolId: protocolId,
                    apy: apy,
                    isActive: false
                });
                protocolCount++;
            }
        }
        
        // Sort protocols by APY (descending)
        for (uint256 i = 0; i < protocolCount; i++) {
            for (uint256 j = i + 1; j < protocolCount; j++) {
                if (protocolAPYs[j].apy > protocolAPYs[i].apy) {
                    ProtocolAPY memory temp = protocolAPYs[i];
                    protocolAPYs[i] = protocolAPYs[j];
                    protocolAPYs[j] = temp;
                }
            }
        }
        
        // // Identify protocols to remove and add
        for (uint256 i = 0; i < protocolCount; i++) {
            // If we have an inactive protocol in the top positions (based on maxActiveProtocols)
            if (!protocolAPYs[i].isActive && i < maxActiveProtocols) {
                uint256 newProtocolId = protocolAPYs[i].protocolId;
                
                // Find the lowest APY active protocol to replace
                uint256 lowestActiveIndex = 0;
                uint256 lowestActiveAPY = type(uint256).max;
                
                for (uint256 j = 0; j < activeProtocolIds.length; j++) {
                    if (activeProtocolAPYs[j] < lowestActiveAPY) {
                        lowestActiveAPY = activeProtocolAPYs[j];
                        lowestActiveIndex = j;
                    }
                }
                
                // Only replace if the new protocol has higher APY
                if (activeProtocolIds.length >= maxActiveProtocols && 
                    protocolAPYs[i].apy > lowestActiveAPY) {
                    
                    uint256 oldProtocolId = activeProtocolIds[lowestActiveIndex];
                    
                    // Withdraw funds from the protocol to be replaced
                    vault._withdrawAllFromProtocol(oldProtocolId);
                    
                    // Replace the protocol
                    registry.replaceActiveProtocol(oldProtocolId, newProtocolId);
                    
                    // Supply funds to the new protocol
                    uint256 amountToSupply = vault.totalAssets() / registry.getActiveProtocolIds().length;
                    vault.supplyToProtocol(newProtocolId, amountToSupply);
                    
                    emit OptimizedYield(oldProtocolId, newProtocolId, amountToSupply);
                } 
                // If we have room for more active protocols, just add this one
                else if (activeProtocolIds.length < maxActiveProtocols) {
                    registry.addActiveProtocol(newProtocolId);
                    
                    uint256 amountToSupply = vault.totalAssets() / (activeProtocolIds.length + 1);
                    vault.supplyToProtocol(newProtocolId, amountToSupply);
                    
                    emit OptimizedYield(0, newProtocolId, amountToSupply);
                }
            }
        }
    }
}