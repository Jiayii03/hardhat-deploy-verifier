// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../core/CombinedVault.sol";
import "../core/interfaces/IRegistry.sol";
import "../adapters/interfaces/IProtocolAdapter.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract YieldOptimizer is Initializable, OwnableUpgradeable {
    IRegistry public registry;
    CombinedVault public vault;
    IERC20 public asset;
    
    // Maximum number of active protocols
    uint256 public maxActiveProtocols;
    
    // Minimum APY difference required to trigger protocol replacement (in basis points)
    uint256 public minApyDifference;
    
    // Cooldown period between optimizations for each protocol (in seconds)
    uint256 public optimizationCooldown;
    
    // Protocol ID => last optimization timestamp
    mapping(uint256 => uint256) public lastOptimized;

    // Struct to track protocol IDs and their APYs
    struct ProtocolAPY {
        uint256 protocolId;
        uint256 apy;
        bool isActive;
    }

    event OptimizedYield(uint256 replacedProtocolId, uint256 newProtocolId, uint256 amount);
    event MaxActiveProtocolsUpdated(uint256 oldValue, uint256 newValue);
    event MinApyDifferenceUpdated(uint256 oldValue, uint256 newValue);
    event OptimizationCooldownUpdated(uint256 oldValue, uint256 newValue);
    event Initialized(address indexed initializer, address vault, address assetAddress);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    /**
     * @notice Initialize the YieldOptimizer
     * @param _vault Address of the CombinedVault
     * @param _asset Address of the asset
     */
    function initialize(address _vault, address _asset) public initializer {
        require(_vault != address(0), "Invalid vault address");
        require(_asset != address(0), "Invalid asset address");

        __Ownable_init(msg.sender);
        
        vault = CombinedVault(_vault);
        registry = vault.registry();
        asset = IERC20(_asset);
        
        // Set default values
        maxActiveProtocols = 3;
        minApyDifference = 50; // 0.5%
        optimizationCooldown = 1 days;
        
        emit Initialized(msg.sender, _vault, _asset);
    }
    
    /**
     * @notice Set the maximum number of active protocols
     * @param _maxActiveProtocols The new maximum number of active protocols
     */
    function setMaxActiveProtocols(uint256 _maxActiveProtocols) external onlyOwner {
        require(_maxActiveProtocols > 0, "Must be greater than zero");
        
        uint256 oldValue = maxActiveProtocols;
        maxActiveProtocols = _maxActiveProtocols;
        
        emit MaxActiveProtocolsUpdated(oldValue, _maxActiveProtocols);
    }
    
    /**
     * @notice Set the minimum APY difference required to trigger a replacement
     * @param _minApyDifference The new minimum APY difference in basis points (1% = 100)
     */
    function setMinApyDifference(uint256 _minApyDifference) external onlyOwner {
        uint256 oldValue = minApyDifference;
        minApyDifference = _minApyDifference;
        
        emit MinApyDifferenceUpdated(oldValue, _minApyDifference);
    }
    
    /**
     * @notice Set the cooldown period between optimizations for each protocol
     * @param _optimizationCooldown The new cooldown period in seconds
     */
    function setOptimizationCooldown(uint256 _optimizationCooldown) external onlyOwner {
        uint256 oldValue = optimizationCooldown;
        optimizationCooldown = _optimizationCooldown;
        
        emit OptimizationCooldownUpdated(oldValue, _optimizationCooldown);
    }

    /**
     * @notice Optimizes yield by selecting the highest APY protocols
     * @dev Called automatically via Chainlink Automation at the end of each epoch
     */
    function optimizeYield() external {
        // Get current active protocols
        uint256[] memory activeProtocolIds = registry.getActiveProtocolIds();
        uint256[] memory allProtocolIds = registry.getAllProtocolIds();
        
        // Track all protocol APYs (both active and inactive)
        ProtocolAPY[] memory protocolAPYs = new ProtocolAPY[](allProtocolIds.length);
        uint256 protocolCount = 0;
        
        // Get APYs for all active protocols
        for (uint256 i = 0; i < activeProtocolIds.length; i++) {
            uint256 protocolId = activeProtocolIds[i];
            address adapterAddress = address(registry.getAdapter(protocolId, address(asset)));
            
            if (adapterAddress != address(0)) {
                uint256 apy = IProtocolAdapter(adapterAddress).getAPY(address(asset));
                
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
        
        // Find inactive protocols with better APY than active ones
        for (uint256 i = 0; i < protocolCount; i++) {
            // If we have an inactive protocol with good APY
            if (!protocolAPYs[i].isActive && i < maxActiveProtocols) {
                uint256 newProtocolId = protocolAPYs[i].protocolId;
                
                // Skip if this protocol was recently optimized
                if (block.timestamp - lastOptimized[newProtocolId] < optimizationCooldown) {
                    continue;
                }
                
                // Find the lowest APY active protocol to replace
                uint256 lowestActiveIndex = type(uint256).max;
                uint256 lowestActiveAPY = type(uint256).max;
                uint256 lowestActiveProtocolId = 0;
                
                for (uint256 j = 0; j < protocolCount; j++) {
                    if (protocolAPYs[j].isActive) {
                        // If this active protocol has worse APY than our current lowest
                        if (protocolAPYs[j].apy < lowestActiveAPY) {
                            lowestActiveAPY = protocolAPYs[j].apy;
                            lowestActiveIndex = j;
                            lowestActiveProtocolId = protocolAPYs[j].protocolId;
                        }
                    }
                }
                
                // Only replace if the new protocol has significantly higher APY
                // and the lowest protocol hasn't been optimized recently
                if (lowestActiveIndex != type(uint256).max &&
                    protocolAPYs[i].apy > lowestActiveAPY + (lowestActiveAPY * minApyDifference / 10000) &&
                    block.timestamp - lastOptimized[lowestActiveProtocolId] >= optimizationCooldown) {
                    
                    // Withdraw all funds from the low-performing protocol
                    vault._withdrawAllFromProtocol(lowestActiveProtocolId);
                    
                    // Replace the protocol in the registry
                    registry.replaceActiveProtocol(lowestActiveProtocolId, newProtocolId);
                    
                    // Calculate amount to supply to new protocol (equal distribution)
                    uint256 amountToSupply = vault.totalAssets() / registry.getActiveProtocolIds().length;
                    
                    // Supply funds to the new high-performing protocol
                    vault.supplyToProtocol(newProtocolId, amountToSupply);
                    
                    // Update optimization timestamps
                    lastOptimized[lowestActiveProtocolId] = block.timestamp;
                    lastOptimized[newProtocolId] = block.timestamp;
                    
                    emit OptimizedYield(lowestActiveProtocolId, newProtocolId, amountToSupply);
                    
                    // Only do one optimization per call to avoid excessive gas usage
                    break;
                } 
                // If we have room for more active protocols, just add this one
                else if (activeProtocolIds.length < maxActiveProtocols) {
                    registry.addActiveProtocol(newProtocolId);
                    
                    uint256 amountToSupply = vault.totalAssets() / (activeProtocolIds.length + 1);
                    vault.supplyToProtocol(newProtocolId, amountToSupply);
                    
                    // Update optimization timestamp
                    lastOptimized[newProtocolId] = block.timestamp;
                    
                    emit OptimizedYield(0, newProtocolId, amountToSupply);
                    
                    // Only do one optimization per call to avoid excessive gas usage
                    break;
                }
            }
        }
    }
    
    /**
     * @notice Gets the APYs of all active protocols
     * @return activeProtocolIds Array of active protocol IDs
     * @return apys Array of APYs corresponding to active protocols
     */
    function getActiveProtocolAPYs() external view returns (uint256[] memory activeProtocolIds, uint256[] memory apys) {
        uint256[] memory protocols = registry.getActiveProtocolIds();
        activeProtocolIds = protocols;
        apys = new uint256[](protocols.length);
        
        for (uint256 i = 0; i < protocols.length; i++) {
            address adapterAddress = address(registry.getAdapter(protocols[i], address(asset)));
            if (adapterAddress != address(0)) {
                apys[i] = IProtocolAdapter(adapterAddress).getAPY(address(asset));
            }
        }
        
        return (activeProtocolIds, apys);
    }
    
    /**
     * @notice Gets the current APY for a specific protocol
     * @param protocolId The protocol ID to check
     * @return apy The current APY in basis points
     */
    function getProtocolAPY(uint256 protocolId) external view returns (uint256 apy) {
        address adapterAddress = address(registry.getAdapter(protocolId, address(asset)));
        if (adapterAddress != address(0)) {
            return IProtocolAdapter(adapterAddress).getAPY(address(asset));
        }
        return 0;
    }
    
    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}