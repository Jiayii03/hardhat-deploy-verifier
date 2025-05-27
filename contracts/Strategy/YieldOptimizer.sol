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

    address public authorizedCaller;
    
    // Minimum APY difference required to trigger protocol replacement (in basis points)
    uint256 public minApyDifference;
    
    // Target number of active protocols to maintain
    uint256 public targetActiveProtocolCount;
    
    // Struct to track protocol IDs and their APYs
    struct ProtocolAPY {
        uint256 protocolId;
        uint256 apy;
        bool isActive;
    }

    event OptimizedYield(uint256[] oldProtocolIds, uint256[] newProtocolIds, uint256 amount);
    event MinApyDifferenceUpdated(uint256 oldValue, uint256 newValue);
    event TargetActiveProtocolCountUpdated(uint256 oldValue, uint256 newValue);
    event Initialized(address indexed initializer, address vault, address assetAddress);
    event AuthorizedCallerUpdated(address indexed oldCaller, address indexed newCaller);

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
        minApyDifference = 0; // 0.5%
        targetActiveProtocolCount = 1; 
        
        emit Initialized(msg.sender, _vault, _asset);
    }

    modifier onlyOwnerOrAuthorized() {
        require(msg.sender == owner() || msg.sender == authorizedCaller, "Caller is not authorized");
        _;
    }

    function setAuthorizedCaller(address newCaller) external onlyOwner {
        require(newCaller != address(0), "Invalid address");
        emit AuthorizedCallerUpdated(authorizedCaller, newCaller);
        authorizedCaller = newCaller;
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
     * @notice Set the target number of active protocols to maintain
     * @param _targetCount The new target number of active protocols
     */
    function setTargetActiveProtocolCount(uint256 _targetCount) external onlyOwner {
        require(_targetCount > 0, "Target count must be > 0");
        uint256 oldValue = targetActiveProtocolCount;
        targetActiveProtocolCount = _targetCount;
        
        emit TargetActiveProtocolCountUpdated(oldValue, _targetCount);
    }

    /**
     * @notice Optimizes yield by selecting the highest APY protocols
     * @dev Called automatically via Chainlink Automation at the end of each epoch
     */
    function optimizeYield() external onlyOwnerOrAuthorized {
        // Get current active protocols
        uint256[] memory activeProtocolIds = registry.getActiveProtocolIds();
        uint256[] memory allProtocolIds = registry.getAllProtocolIds();
        
        // Use the configured target count instead of active protocols length
        uint256 targetActiveCount = targetActiveProtocolCount;
        require(targetActiveCount > 0, "No active protocols");
        
        // Track all protocol APYs (both active and inactive)
        ProtocolAPY[] memory protocolAPYs = new ProtocolAPY[](allProtocolIds.length);
        uint256 protocolCount = 0;
        
        // Get APYs for all protocols (both active and inactive)
        for (uint256 i = 0; i < allProtocolIds.length; i++) {
            uint256 protocolId = allProtocolIds[i];
            address adapterAddress = address(registry.getAdapter(protocolId, address(asset)));
            
            if (adapterAddress != address(0)) {
                uint256 apy = IProtocolAdapter(adapterAddress).getAPY(address(asset));
                
                // Check if this protocol is currently active
                bool isActive = false;
                for (uint256 j = 0; j < activeProtocolIds.length; j++) {
                    if (protocolId == activeProtocolIds[j]) {
                        isActive = true;
                        break;
                    }
                }
                
                protocolAPYs[protocolCount] = ProtocolAPY({
                    protocolId: protocolId,
                    apy: apy,
                    isActive: isActive
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

        // First, add any protocols from top N that aren't active yet
        for (uint256 i = 0; i < targetActiveCount && i < protocolCount; i++) {
            if (!protocolAPYs[i].isActive) {
                // This protocol is in top N but not active, add it
                vault.addActiveProtocol(protocolAPYs[i].protocolId);
            }
        }

        // Then, remove protocols that are not in the top N by APY
        for (uint256 i = 0; i < protocolCount; i++) {
            if (protocolAPYs[i].isActive && i >= targetActiveCount) {
                // This protocol is active but not in top N, remove it
                vault.removeActiveProtocol(protocolAPYs[i].protocolId);
            }
        }

        // Get final active protocols for event
        uint256[] memory finalActiveProtocols = registry.getActiveProtocolIds();
        uint256[] memory removedProtocols = new uint256[](activeProtocolIds.length);
        uint256[] memory addedProtocols = new uint256[](finalActiveProtocols.length);
        uint256 removedCount = 0;
        uint256 addedCount = 0;

        // Find removed protocols
        for (uint256 i = 0; i < activeProtocolIds.length; i++) {
            bool stillActive = false;
            for (uint256 j = 0; j < finalActiveProtocols.length; j++) {
                if (activeProtocolIds[i] == finalActiveProtocols[j]) {
                    stillActive = true;
                    break;
                }
            }
            if (!stillActive) {
                removedProtocols[removedCount] = activeProtocolIds[i];
                removedCount++;
            }
        }

        // Find added protocols
        for (uint256 i = 0; i < finalActiveProtocols.length; i++) {
            bool wasActive = false;
            for (uint256 j = 0; j < activeProtocolIds.length; j++) {
                if (finalActiveProtocols[i] == activeProtocolIds[j]) {
                    wasActive = true;
                    break;
                }
            }
            if (!wasActive) {
                addedProtocols[addedCount] = finalActiveProtocols[i];
                addedCount++;
            }
        }

        emit OptimizedYield(removedProtocols, addedProtocols, vault.totalAssets() / targetActiveCount);
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